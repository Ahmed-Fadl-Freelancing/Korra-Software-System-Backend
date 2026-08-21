# 003 — Real Opportunities (projects) CRUD API

## Goal
`GET /opportunities` currently returns a hardcoded empty-array stub
(`opportunities/views.py:14-21`, `# TODO: query opportunities table once schema is confirmed`). The
schema is not actually unconfirmed — `DB data/schema.sql:77-104` fully defines the `projects` table
(what the UI calls "Opportunities") and its lookup tables. Build the real model layer and the four
endpoints `PROGRESS.md` Milestone 4 calls for.

## Relevant files / schema
- `DB data/schema.sql` — read `projects` (lines ~77-104), `contractors`, `owners`, `consultants`,
  `products` in full before writing any model; these are the tables you're mapping.
- `DB data/Enum.json` — canonical string values for `project_status`, `project_application`,
  `project_scope`, `product_family` (also mirrored in this repo's `CLAUDE.md` "Database Enums"
  table — use whichever is more convenient, they should already agree; flag it if they don't, don't
  silently pick one).
- `accounts/models.py` — follow its pattern for new models: `managed = False`, explicit `db_table`,
  `db_column` wherever the Python attribute name would otherwise differ from the SQL column
  (`projects.sales_eng_id` is a FK to `auth.users`, i.e. effectively to `UserProfile` — model it the
  same way `UserRole.user` references `UserProfile` today).
- `opportunities/` — currently has `views.py` + `urls.py` only, no `models.py`/`serializers.py`. Add
  both.
- `accounts/permissions.py` — **do not** wire `IsSales`/`IsEngineer`/`IsManager`/`IsAdmin` into these
  new views without first checking backend task 006; those classes currently check role codes
  (`"sales"`, `"engineer"`) that don't match the canonical values (`sales_engineer`, `tech_engineer`)
  and are unused/broken today. If role-scoping is needed for `POST`/`PATCH`, either fix those classes
  as part of this task or query `user_roles` directly inline (matching the pattern in
  `accounts/views.py`'s `MeView`) — pick one and note which you did, but don't wire in the broken
  classes as-is.

## Endpoints to build
Per `CLAUDE.md`'s route map and `PROGRESS.md` Milestone 4:
- `GET /opportunities` — list, replacing the current stub. Filterable at minimum by
  `sales_eng_id`/`tech_eng_id` (the frontend's dashboard spec in `PROJECT_FLOW.md §5` expects
  `?sales_eng_id=me` / `?tech_eng_id=me` query params — support `me` as a special value resolving to
  `request.user.user_id`, not just literal UUIDs).
- `POST /opportunities` — create via the PDF-extraction path (Path A): accepts extracted-and-reviewed
  fields, likely referencing a completed `PdfExtractionJob`.
- `POST /opportunities/manual` — create via manual entry (Path B): accepts the full field set
  directly from a form, no PDF job reference required.
- `GET /opportunities/{id}` — detail.
- `PATCH /opportunities/{id}` — partial update (status transitions, field corrections, etc.). Consider
  whether a status change should also write a `project_status_history` row (the table exists in
  `schema.sql:124-142` specifically for this audit trail) — if you implement status-change tracking
  here, do it; if you defer it, say so explicitly in your PR description so it doesn't get assumed
  done.

## Acceptance criteria
- `Project`, `Contractor`, `Owner`, `Consultant`, `Product` models exist in `opportunities/models.py`
  (or split across files if that reads better — your call), all `managed = False`, matching
  `schema.sql` exactly (column names, nullability, FK targets).
- All five endpoints above return real data from Postgres, not stub responses.
- Serializer validation rejects a `POST` missing required non-nullable DB fields (`application`,
  `scope`, `sales_eng_id`, etc.) with a clear 400, not a raw DB constraint error.
- `PATCH` only allows updating fields that make sense to update post-creation (don't allow silently
  changing `sales_eng_id` to reassign ownership unless that's an intentional feature — if unsure,
  restrict to `status` + the extracted/selection data fields and note the restriction in your PR).
- Manually verify against a real Supabase-backed dev DB: create via both `/opportunities` and
  `/opportunities/manual`, list, fetch detail, patch status.

## Cross-repo dependency
Unblocks frontend task 004 (manual opportunity form rebuild) and backend tasks 005/007 (both need
real opportunity rows to operate against). No backend dependency itself.
