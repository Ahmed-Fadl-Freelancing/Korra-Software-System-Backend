# Korra Backend — Workflow & Feature Tracker

> **Source of truth** for features, branches, Linear issues, and PR status.
> Update this file whenever a feature moves to a new state.
> Last updated: 2026-06-02

---

## How This Works

\`\`\`
Feature (logical unit)
  └── Branch: feature/<name>
        └── Linear Issues: KOR-XX, KOR-YY, ... (Project: Korra Backend App)
              └── PR: one PR per branch, targeting main
\`\`\`

**States:** \`Done\` | \`In Review\` | \`In Progress\` | \`Todo\` | \`Backlog\`

**Workflow Steps:**
1.  **Start Feature:** Create branch \`feature/<name>\` from \`main\`.
2.  **Implementation:** Build issues one by one. Commit with \`feat(scope): description (KOR-XX)\`.
3.  **Completion:** Update \`WORKFLOW.md\` status to \`In Review\`.
4.  **Handoff:** Mark issues as \`In Review\` in Linear. Open PR on GitHub.
5.  **Merge:** Detection of merge → Update status to \`Done\` in \`WORKFLOW.md\` and Linear.

---

## Feature Map

### Feature 1 — Auth Foundation
**Branch:** \`feature/auth-foundation\`
**Status:** ✅ Done
**PR:** *(merged)*

| Issue | Title | State |
|-------|-------|-------|
| KOR-83 | Implement Supabase JWT authentication class | ✅ Done |
| KOR-84 | Create GET /me endpoint — profile + roles | ✅ Done |
| KOR-85 | GET /health endpoint — liveness probe | ✅ Done |

---

### Feature 2 — Document Storage
**Branch:** \`feature/document-storage\`
**Status:** ✅ Done
**PR:** *(merged)*

| Issue | Title | State |
|-------|-------|-------|
| KOR-86 | POST /documents/signed-upload-url | ✅ Done |
| KOR-87 | GET /documents/signed-download-url | ✅ Done |

---

### Feature 3 — PDF Extraction Pipeline
**Branch:** \`feature/pdf-extraction\`
**Status:** 🔧 Todo
**PR:** *(not yet opened)*

| Issue | Title | State |
|-------|-------|-------|
| KOR-88 | Implement fetch_pdf — download PDF from Storage | Todo |
| KOR-89 | Implement parse_pdf — PyMuPDF extraction | Todo |
| KOR-90 | Celery async task — wrap extraction pipeline | Todo |
| KOR-91 | POST /pdf-extraction/ — trigger job | Todo |
| KOR-92 | GET /pdf-extraction/{job_id}/ — poll status | Todo |

---

### Feature 4 — Opportunity Management
**Branch:** \`feature/opportunity-management\`
**Status:** 📋 Backlog
**PR:** *(not yet opened)*

| Issue | Title | State |
|-------|-------|-------|
| KOR-93 | GET /opportunities — list for current user | Backlog |
| KOR-94 | POST /opportunities — from PDF (Path A) | Backlog |
| KOR-95 | POST /opportunities/manual — Manual (Path B) | Backlog |
| KOR-96 | GET + PATCH /opportunities/{id} — detail/status | Backlog |

---

### Feature 5 — Workflow Tasks
**Branch:** \`feature/workflow-tasks\`
**Status:** 📋 Backlog
**PR:** *(not yet opened)*

| Issue | Title | State |
|-------|-------|-------|
| KOR-97 | GET /tasks — list assigned | Backlog |
| KOR-98 | POST /tasks — create linked to opportunity | Backlog |
| KOR-99 | PATCH /tasks/{id} — update status | Backlog |

---

### Feature 6 — RPA Integration
**Branch:** \`feature/rpa-integration\`
**Status:** 🔧 In Progress
**PR:** *(not yet opened)*

| Issue | Title | State |
|-------|-------|-------|
| KOR-100 | POST /webhooks/uipath — HMAC verified receiver | ✅ Done |
| KOR-101 | Track RPA status on opportunities field | Todo |
| KOR-102 | Retry logic for failed UiPath RPA jobs | Todo |

---

### Feature 7 — DB Security & Audit
**Branch:** \`feature/db-security-audit\`
**Status:** 📋 Backlog
**PR:** *(not yet opened)*

| Issue | Title | State |
|-------|-------|-------|
| KOR-103 | Enable RLS on core tables | Backlog |
| KOR-104 | RLS policy — Sales Engineers (Own rows) | Backlog |
| KOR-105 | RLS policy — Managers (All rows) | Backlog |
| KOR-106 | PostgreSQL trigger — status history audit | Backlog |

---

### Feature 8 — Auth Session Endpoints
**Branch:** \`feat/Auth\`
**Status:** 🔧 In Progress
**PR:** *(not yet opened)*

Supabase Auth (GoTrue) proxy — Django relays Supabase-issued tokens; it never mints its own JWT.

| Issue | Title | State |
|-------|-------|-------|
| KOR-113 | POST /auth/signup — proxy to Supabase Auth | 🔧 In Review |
| KOR-114 | POST /auth/login — password grant, relay tokens | 🔧 In Review |
| KOR-115 | POST /auth/logout — revoke Supabase session | 🔧 In Review |
| KOR-116 | POST /auth/refresh — refresh-token grant | 🔧 In Review |

> Also fixes the \`user_profiles\` PK mapping (column is \`user_id\`, not \`id\`) that \`/me\` depends on.
> Linear issues created 2026-06-04. PR #2 open — waiting for human merge.

---

## Progress Summary

> **Branch convention for new work:** \`feat/<Name>\` (PascalCase). Cross-repo roadmap: \`PROGRESS.md\`.

| Feature | Branch | Issues | Status |
|---------|--------|--------|--------|
| 1 Auth Foundation | \`feature/auth-foundation\` | KOR-83–85 | ✅ Done |
| 8 Auth Session Endpoints | \`feat/Auth\` | KOR-113–116 | 🔧 In Review (PR #2) |
| 2 Document Storage | \`feature/document-storage\` | KOR-86–87 | ✅ Done |
| 3 PDF Extraction | \`feature/pdf-extraction\` | KOR-88–92 | 🔧 Todo |
| 4 Opportunity Mgmt | \`feature/opportunity-management\` | KOR-93–96 | 📋 Backlog |
| 5 Workflow Tasks | \`feature/workflow-tasks\` | KOR-97–99 | 📋 Backlog |
| 6 RPA Integration | \`feature/rpa-integration\` | KOR-100–102 | 🔧 In Progress |
| 7 DB Security | \`feature/db-security-audit\` | KOR-103–106 | 📋 Backlog |
