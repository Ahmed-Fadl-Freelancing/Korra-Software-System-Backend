"""
Linear GraphQL API client.

All requests go through Django — the frontend never calls Linear directly.
Uses LINEAR_API_KEY from Django settings.
"""
import logging

import httpx
from django.conf import settings

logger = logging.getLogger(__name__)

LINEAR_API_URL = "https://api.linear.app/graphql"


def _gql(query: str, variables: dict | None = None) -> dict:
    api_key = getattr(settings, "LINEAR_API_KEY", "")
    if not api_key:
        raise ValueError("LINEAR_API_KEY is not set in Django settings")

    try:
        response = httpx.post(
            LINEAR_API_URL,
            json={"query": query, "variables": variables or {}},
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            timeout=10.0,
        )
        response.raise_for_status()
    except httpx.HTTPError as exc:
        raise ValueError(f"Linear API request failed: {exc}")

    body = response.json()

    if "errors" in body:
        raise ValueError(f"Linear API error: {body['errors']}")

    return body.get("data", {})


# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

GET_ISSUES = """
query GetIssues($teamKey: String!, $statusFilter: [String!]) {
  issues(
    filter: {
      team: { key: { eq: $teamKey } }
    }
    orderBy: updatedAt
  ) {
    nodes {
      id
      identifier
      title
      description
      priority
      url
      createdAt
      updatedAt
      state {
        id
        name
        type
      }
      assignee {
        id
        name
        email
      }
      labels {
        nodes {
          id
          name
          color
        }
      }
    }
  }
}
"""

GET_TEAM_STATES = """
query GetTeamStates($teamKey: String!) {
  teams(filter: { key: { eq: $teamKey } }) {
    nodes {
      id
      states {
        nodes {
          id
          name
          type
        }
      }
    }
  }
}
"""

CREATE_ISSUE = """
mutation CreateIssue($input: IssueCreateInput!) {
  issueCreate(input: $input) {
    success
    issue {
      id
      identifier
      title
      url
      state {
        name
      }
    }
  }
}
"""

UPDATE_ISSUE_STATE = """
mutation UpdateIssueState($id: String!, $stateId: String!) {
  issueUpdate(id: $id, input: { stateId: $stateId }) {
    success
    issue {
      id
      identifier
      state {
        name
        type
      }
    }
  }
}
"""

GET_ISSUE_BY_IDENTIFIER = """
query GetIssueByIdentifier($identifier: String!) {
  issue(id: $identifier) {
    id
    identifier
    title
    state {
      id
      name
    }
  }
}
"""


# ---------------------------------------------------------------------------
# Service functions
# ---------------------------------------------------------------------------

def get_issues(team_key: str, status_filter: list[str] | None = None) -> list[dict]:
    data = _gql(GET_ISSUES, {"teamKey": team_key})
    issues = data.get("issues", {}).get("nodes", [])

    if status_filter:
        issues = [i for i in issues if i.get("state", {}).get("name") in status_filter]

    return issues


def create_issue(title: str, description: str, team_key: str, priority: int = 0) -> dict:
    """
    priority: 0=No priority, 1=Urgent, 2=High, 3=Medium, 4=Low
    Returns the created issue dict.
    """
    # Resolve team ID from key
    teams_data = _gql(GET_TEAM_STATES, {"teamKey": team_key})
    teams = teams_data.get("teams", {}).get("nodes", [])
    if not teams:
        raise ValueError(f"Linear team with key '{team_key}' not found")
    team_id = teams[0]["id"]

    data = _gql(CREATE_ISSUE, {
        "input": {
            "teamId": team_id,
            "title": title,
            "description": description,
            "priority": priority,
        }
    })

    result = data.get("issueCreate", {})
    if not result.get("success"):
        raise ValueError("Linear issueCreate returned success=false")

    return result.get("issue", {})


def update_issue_status(issue_id: str, status_name: str, team_key: str) -> dict:
    """
    issue_id: Linear internal UUID (not identifier like KOR-53).
    status_name: e.g. 'In Progress', 'In Review', 'Done'.
    """
    teams_data = _gql(GET_TEAM_STATES, {"teamKey": team_key})
    teams = teams_data.get("teams", {}).get("nodes", [])
    if not teams:
        raise ValueError(f"Linear team with key '{team_key}' not found")

    states = teams[0].get("states", {}).get("nodes", [])
    matched = next((s for s in states if s["name"].lower() == status_name.lower()), None)
    if not matched:
        available = [s["name"] for s in states]
        raise ValueError(f"State '{status_name}' not found. Available: {available}")

    data = _gql(UPDATE_ISSUE_STATE, {"id": issue_id, "stateId": matched["id"]})
    result = data.get("issueUpdate", {})
    if not result.get("success"):
        raise ValueError("Linear issueUpdate returned success=false")

    return result.get("issue", {})
