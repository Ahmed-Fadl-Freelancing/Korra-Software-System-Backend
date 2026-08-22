# 007 — GET /analytics/summary (manager dashboard data)

## Goal
`PROJECT_FLOW.md §5`'s role-based dashboard spec lists Manager KPI widgets sourced from
`GET /analytics/summary` (and mentions `/analytics/export` for a data-export feature, per the
frontend's `ISSUES.md` KOR-57). Neither endpoint has any backend code today — not even a stub, and
not tracked in any status table (backend task 001 adds it to the docs as Backlog; this task builds
it).

## Why this is sequenced after opportunities/tasks CRUD
This endpoint aggregates data — team workload, bottlenecks, win/loss counts, whatever the manager
dashboard actually needs. It's not meaningful to build against `opportunities`/`tasks` tables that are
still stub-returning-empty-arrays (backend tasks 003/004). Do this once those are live and have real
data to aggregate, otherwise you're building an aggregation endpoint with nothing real to aggregate
and no way to verify it's correct.

## Relevant files / spec
- `PROJECT_FLOW.md §5` (this repo) — read the Manager dashboard widget table for what data points are
  actually expected (team workload by engineer, bottleneck opportunities, KPI strip numbers, etc.).
- `korra-software-system-frontend`'s `src/components/dashboard/ManagerWidgets.tsx` — currently 100%
  hardcoded fake data (`teamWorkload`, `bottlenecks` arrays). This is the actual consumer — look at
  what shape it currently fakes to understand what shape it'll eventually want for real (frontend
  task 007 rebuilds this component against your endpoint — coordinate on the response shape rather
  than designing it in isolation).
- Opportunities (`opportunities/models.py` from task 003) and Tasks (`workflow/models.py` from task
  004) models — this endpoint will query/aggregate across both.

## What to build
- `GET /analytics/summary` — new app or fold into an existing one (your call; a new `analytics/` app
  matching the existing flat-app-per-feature convention is probably cleanest). Returns aggregated
  counts/summaries: opportunities by status, tasks by assignee/status, whatever else the dashboard
  spec and `ManagerWidgets.tsx`'s real requirements converge on.
- Restrict this endpoint to users with the `manager` role — this is a legitimate use case for
  `accounts/permissions.py`'s `IsManager` class (fix its role-code bug first if backend task 006
  hasn't landed yet, or fix it inline as part of this task).
- Consider whether `/analytics/export` (mentioned in frontend `ISSUES.md` KOR-57 for an Excel export
  button) is in scope for this task or a separate follow-up — it's fine to scope this task to
  `/summary` only and leave `/export` as a noted follow-up if it needs different tooling (e.g. a
  spreadsheet-generation library not yet in `requirements.txt`).

## Acceptance criteria
- `GET /analytics/summary` returns real aggregated data from the `projects`/`workflow_tasks` tables,
  gated to manager-role users (non-managers get 403, not just filtered/empty data).
- Response shape was coordinated with (or at least reviewed against) what frontend task 007's
  `ManagerWidgets.tsx` rebuild actually needs — avoid designing this in a vacuum.
- Added to `CLAUDE.md`'s route map with real status (not the "entirely undocumented" gap noted in
  backend task 001).

## Cross-repo dependency
Depends on backend tasks 003 and 004 (needs real opportunity/task data to aggregate). Unblocks
frontend task 007 (manager dashboard real-data rebuild).
