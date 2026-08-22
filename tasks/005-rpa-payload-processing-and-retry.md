# 005 — RPA webhook payload processing + status tracking + retry logic

## Goal
`POST /webhooks/uipath`'s HMAC signature verification is fully implemented and correct
(`rpa/views.py:21-46`) — don't touch that part. What's missing is everything *after* verification:
the view currently just logs the payload and returns `{"received": True}`
(`rpa/views.py:56-64`, `# TODO: update DB, trigger follow-up Celery tasks`). Separately,
`rpa/tasks.py` has two Celery tasks that are pure stubs (`pricing_generate`, `uipath_trigger`, both
just `log` + `return {"status": "stubbed", ...}`).

## Relevant files
- `rpa/views.py` — `UiPathWebhookView.post()`, after the signature check passes.
- `rpa/tasks.py` — `pricing_generate(opportunity_id)` (docstring lists 4 planned steps: fetch data,
  render template, upload PDF, update record) and `uipath_trigger(opportunity_id)` (3 planned steps).
  Read both docstrings in full before writing — they already describe the intended shape, just not
  the implementation.
- `opportunities/models.py` (from backend task 003) — you'll need the `Project` model to actually
  write RPA status back to an opportunity row.

## What to build
1. **Webhook payload persistence**: on a verified UiPath callback, update the relevant `Project` row
   (status, RPA-tracking fields — see point 2) and/or write whatever record the payload represents.
   The exact payload shape isn't documented anywhere in this repo — if UiPath's actual webhook
   contract isn't available, ask the human rather than guessing field names; this is exactly the kind
   of "undocumented business logic" worth stopping for rather than inventing silently.
2. **RPA status tracking on opportunities** (KOR-101): add a field (or fields) to track RPA job state
   on a `Project` — e.g. `rpa_status`, `rpa_last_triggered_at`, `rpa_error`. This likely means an
   additive Supabase schema change (a new column on `projects`) — same convention as backend task
   004's schema step: propose it, get it confirmed, then mirror into `DB data/schema.sql`.
3. **Retry logic for failed UiPath RPA jobs** (KOR-102): implement real retry behavior in
   `pricing_generate`/`uipath_trigger` — Celery's `autoretry_for`/`self.retry()` pattern already
   exists elsewhere in this codebase (`pdf_extraction/tasks.py`) as a reference implementation to
   follow for consistency (max retries, backoff, fall-through-to-failed behavior).

## Acceptance criteria
- `UiPathWebhookView` persists something real to the DB after a verified callback — not just a log
  line.
- `pricing_generate`/`uipath_trigger` do real work (or as much as is buildable without an actual
  UiPath Orchestrator endpoint to call — if the external UiPath side isn't available to integrate
  against yet, implement everything up to that boundary and clearly mark what's blocked on external
  access, don't leave a silent stub with no explanation).
- Retry behavior is tested at least manually (force a failure, confirm it retries per the configured
  policy, then confirm it lands in a terminal failed state after max retries — same verification
  pattern as `pdf_extraction`'s existing retry logic).
- Any new `projects` columns are documented in `DB data/schema.sql` and `CLAUDE.md`'s schema table.

## Cross-repo dependency
Depends on backend task 003 (needs a real `Project` model to write status back to — this task is
close to meaningless without real opportunity rows to operate against).
