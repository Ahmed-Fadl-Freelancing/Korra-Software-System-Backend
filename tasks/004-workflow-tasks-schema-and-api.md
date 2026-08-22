# 004 — Design workflow_tasks schema, then build the Tasks API

## Goal
`GET /tasks` currently returns a hardcoded empty-array stub (`workflow/views.py:15-20`,
`# TODO: query workflow_tasks table once schema is confirmed`). Unlike Opportunities, this one's TODO
comment is accurate — **no `workflow_tasks` (or similarly named) table exists anywhere in
`DB data/schema.sql`**. This task starts with actual schema design, not just Django wiring.

## Step 1 — schema design (needs a human decision, don't just invent it silently)
Before writing any Django code, propose a `workflow_tasks` table design and confirm it with the
human before implementing. At minimum it needs to support what the frontend's `Task` type
(`src/types/index.ts` in the frontend repo) and dashboard spec (`PROJECT_FLOW.md §5`, "Urgent Tasks"
widget, `GET /tasks?assigned_to=me`) already assume: a title, a status (`pending`/`in_progress`/
`completed`/`blocked` per the frontend type — confirm these are the values you actually want, they
were invented by the frontend before any backend schema existed), a due date, a priority
(`low`/`medium`/`high`/`urgent`), an assignee (FK to `auth.users`/`user_profiles`), and a link back to
the opportunity it belongs to (`opportunity_id` FK to `projects`, mirroring the frontend's
`opportunity_name` display field — you'll want the FK, the frontend can join/display the name).
Write the proposed `CREATE TABLE` SQL and get it reviewed (via PR description, Linear comment, or
however the human prefers) before running it against Supabase — this repo's convention is DB schema
changes happen in Supabase directly, then get mirrored into `DB data/schema.sql` as a reference
snapshot (see how `projects`/`documents` are documented there already — follow that pattern for
consistency, and update that file once the real table exists).

## Step 2 — Django + API layer (same shape as opportunities task 003)
- Add `workflow/models.py` (currently doesn't exist) — `managed = False`, matching whatever schema
  you land on in step 1.
- Add `workflow/serializers.py`.
- Replace the stub in `workflow/views.py` with real implementations:
  - `GET /tasks` — list, supporting `?assigned_to=me` per the frontend spec.
  - `POST /tasks` — create.
  - `PATCH /tasks/{id}` — update (status changes especially — this is likely the most common
    operation once the frontend task-detail UI exists).

## Acceptance criteria
- A `workflow_tasks` table design has been reviewed/confirmed by the human before implementation
  (don't skip straight to Django code on your own schema guess).
- `DB data/schema.sql` is updated with the new table once it exists for real, matching the "for
  context only" snapshot convention already used for the other tables in that file.
- All three endpoints (`GET /tasks`, `POST /tasks`, `PATCH /tasks/{id}`) work against real data.
- `CLAUDE.md`'s Database Schema table gets a new row for `workflow_tasks` (it's currently missing —
  another gap task 001 didn't catch because the table didn't exist yet at the time that task was
  written).

## Cross-repo dependency
Unblocks frontend task 005 (task UI beyond read-only stub display). Depends on nothing else in this
repo, but the schema-design step benefits from checking whether backend task 003's `Project` model is
already merged (so the `opportunity_id` FK target actually exists) — sequence after 003 if convenient,
but not a hard blocker if you'd rather design the schema in parallel.
