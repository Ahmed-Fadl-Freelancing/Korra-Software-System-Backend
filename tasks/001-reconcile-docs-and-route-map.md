# 001 — Reconcile docs with actual code state

## Goal
`PROGRESS.md`, `WORKFLOW.md`, and `CLAUDE.md`'s route table currently describe several things
incorrectly relative to the actual code (verified by direct code read 2026-08-21 — see
`../../korra-project/PLAN.md` "Docs vs. reality" section for the full list and evidence). Fix the
docs so the next person (human or agent) doesn't waste time re-verifying what's actually done.

This is a docs-only task — no application code changes.

## What's wrong today

1. **Auth (KOR-113–116) marked "🔧 In Review (PR #2)"** in `PROGRESS.md:20,38-41`, `WORKFLOW.md:134-140`,
   and `CLAUDE.md`'s route table (all four `/auth/*` rows marked "🔧 In Progress"). Reality: PR #2
   (`feat/Auth`) is merged to `main` (commit `67c07ea`). All four endpoints plus `/me` are
   code-complete. Update all three files' status to "✅ Done".

2. **PDF extraction marked "🔲 Todo" everywhere** (`PROGRESS.md:59-63`, `WORKFLOW.md:63-67`,
   `CLAUDE.md`'s route table). Reality: `PdfExtractionJob` model, the Celery task with retry/backoff,
   and both HTTP views (`POST /pdf-extraction/jobs/`, `GET /pdf-extraction/jobs/<id>/`) are fully
   implemented. Only `pdf_extraction/services.py`'s `fetch_pdf()` and `parse_pdf()` are stubs (they
   unconditionally raise `PdfExtractionError`). Update status to reflect partial completion — don't
   mark the whole milestone "Todo" when most of the plumbing is done; be specific that only the two
   extraction functions remain (that's task 002).

3. **Route path mismatch.** `CLAUDE.md`'s route table and `PROJECT_FLOW.md §4.2` document
   `POST /pdf-extraction/` and `GET /pdf-extraction/{job_id}/`. The actual code
   (`pdf_extraction/urls.py:7-8`) mounts an extra `jobs/` segment:
   `POST /pdf-extraction/jobs/`, `GET /pdf-extraction/jobs/<int:job_id>/`.

   There's a **third** name in play too: the frontend's `ISSUES.md` (KOR-55-2) calls for
   `POST /opportunities/extract` for the same trigger action. Nothing has shipped frontend code
   against any of these three names yet (verified — no frontend code calls any pdf-extraction path
   today), so there's no runtime tiebreaker forcing one choice.

   **Decide one canonical path and propagate it everywhere**: `CLAUDE.md` (this repo),
   `PROJECT_FLOW.md` (this repo AND the frontend repo — keep them identical per both files' own
   header instructions), and flag to whoever picks up frontend task 003 that `ISSUES.md`'s
   `POST /opportunities/extract` naming needs to be corrected there too before that task starts.
   Default recommendation if no other constraint exists: match what's already shipped in code
   (`POST /pdf-extraction/jobs/`) rather than changing working code to match stale docs — but this is
   a judgment call, not a hard requirement; pick whichever and just make it consistent everywhere.

4. **`/opportunities` and `/tasks` marked "📋 Backlog"** but stub routing/views already exist
   (`opportunities/views.py`, `workflow/views.py` — both return `{<resource>: [], "detail": "stub – not
   yet implemented"}`). Fine to leave the milestone status as "Backlog" for the CRUD work itself, but
   note in `WORKFLOW.md`'s per-feature detail that the stub scaffolding already exists so task 003/004
   don't need to create the URL wiring from scratch.

5. **`GET /analytics/summary`** is referenced in `PROJECT_FLOW.md` (dashboard widget data sources)
   but appears in **no** route table in this repo at all — not even as "Backlog". Add it to
   `CLAUDE.md`'s API Route Map (status: 📋 Backlog) and to `PROGRESS.md`'s milestone table (it doesn't
   currently belong to any milestone — add it under Milestone 8 or wherever the manager-dashboard work
   is tracked; create that milestone entry if none exists).

6. **`rpa/tasks.py`'s two stub Celery tasks (`pricing_generate`, `uipath_trigger`) don't map 1:1 to
   KOR-101/102`** ("Track RPA status on opportunities field" / "Retry logic for failed UiPath RPA
   jobs") as currently worded in `PROGRESS.md:89-90`. Leave the Todo status but add a note that the
   existing stubs aren't necessarily the right starting shape for those two issues — whoever picks up
   task 005 should read `rpa/tasks.py` fresh rather than assuming the stub names map directly.

## Files to touch
- `PROGRESS.md`
- `WORKFLOW.md`
- `CLAUDE.md` (API Route Map section)
- `.github/copilot-instructions.md` (kept identical to `CLAUDE.md` by repo convention — update both)
- `PROJECT_FLOW.md` (if the PDF-extraction path name changes)

## Acceptance criteria
- No status table in this repo claims auth is "In Review"/"In Progress" — it's "Done".
- PDF extraction status distinguishes "job lifecycle/HTTP layer: done" from "fetch/parse: todo"
  rather than a single blanket "Todo".
- Exactly one canonical path is documented for the PDF-extraction trigger endpoint, consistently,
  in every doc file in this repo that mentions it.
- `GET /analytics/summary` appears somewhere in the route map / milestone tracking, even if just as
  Backlog — it should no longer be entirely undocumented.
- `CLAUDE.md` and `.github/copilot-instructions.md` bodies remain identical (repo's own stated
  requirement).

## Cross-repo dependency
None to start — this is docs-only in this repo. However: whoever does frontend task 003 (PDF
extraction UI) should read the outcome of this task first, since it depends on which endpoint path
this task settles on. Also update the frontend's `PROJECT_FLOW.md`/`ISSUES.md` to match once the
path is picked (small follow-up, can be a fast frontend PR or folded into frontend task 003's setup).
