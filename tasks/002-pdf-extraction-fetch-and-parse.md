# 002 — Implement PDF fetch + parse, add the missing migration

## Goal
`pdf_extraction/services.py`'s `fetch_pdf()` and `parse_pdf()` are the only two unimplemented pieces
of an otherwise-complete extraction pipeline (model, Celery retry/backoff orchestration, both HTTP
views are all done). Implement them for real, and fix the fact that `PdfExtractionJob` — the one
genuinely Django-managed model in this codebase — has never had a migration generated.

## Relevant files
- `pdf_extraction/services.py` — `fetch_pdf(bucket, storage_path)` (currently raises
  `PdfExtractionError("fetch_pdf not yet implemented")` at line 54, with a commented-out sketch above
  it using `supabase.create_client(...).storage.from_(bucket).download(storage_path)` — that sketch is
  a reasonable starting point). `parse_pdf(pdf_bytes)` (currently raises
  `PdfExtractionError("parse_pdf not yet implemented")` at line 79). `persist_result()` is already
  done — don't touch it.
- `pdf_extraction/models.py` — `PdfExtractionJob`. Note its module docstring currently claims "all
  models are currently unmanaged stubs" — that's inaccurate (there's no `Meta.managed = False`), fix
  the docstring while you're in this file so it stops misleading the next reader.
- `pdf_extraction/tasks.py` — `extract_pdf` Celery task; don't need to change retry logic (already
  correct), but verify your `fetch_pdf`/`parse_pdf` changes still raise `PdfExtractionError`
  consistently so the existing catch-and-retry logic keeps working.
- `requirements.txt` — add `pymupdf` (the architecture doc, `CLAUDE.md:44`, mandates it specifically:
  "PDF extraction uses `pymupdf` (fitz) only, in Django. Never on the frontend." — don't substitute
  pdfplumber/pypdf2 even though `services.py`'s stale TODO comment mentions them as options).
- No `migrations/` directory exists anywhere in this repo. Run
  `python manage.py makemigrations pdf_extraction` to generate the first migration for this app —
  this is a real gap (not a stylistic choice): without it, `PdfExtractionJob`'s table has never been
  created in any real deployment.

## What "implement fetch_pdf" means concretely
Download the PDF bytes from Supabase Storage given `(bucket, storage_path)` — the job row already
stores these fields (`PdfExtractionJob.bucket`, `.storage_path`). Use the `supabase` package (already
a dependency, `supabase==2.8.1`) with the service-role key (`settings.SUPABASE_SERVICE_ROLE_KEY`) —
follow the same client-construction pattern used in `documents/views.py` for signed URLs, since that's
the only other place in the codebase that talks to Supabase Storage. Raise `PdfExtractionError` on any
failure (network, missing object, permission) so the existing Celery retry logic in `tasks.py`
continues to work unchanged.

## What "implement parse_pdf" means concretely
Given the raw PDF bytes, extract the fields the `extracted_data` JSON blob on `projects` is meant to
hold (see `DB data/schema.sql`'s `projects.extracted_data jsonb` column and `PROJECT_FLOW.md §4`'s
Path A description for what fields matter — product family, scope, application, contractor/consultant/
owner names, etc., if they're present in the source PDF). The response shape the rest of the system
expects, per `CLAUDE.md`: `{status: "success"|"partial"|"failed", fields: {...}, confidence: {...}}`.
Use `pymupdf`/`fitz` — text extraction plus whatever field-detection heuristic is reasonable (regex/
keyword matching against known label patterns is fine for a first version; this doesn't need to be an
ML pipeline). Raise `PdfExtractionError` on failure, matching the existing pattern.

## Acceptance criteria
- `pymupdf` is in `requirements.txt` and actually imported/used in `services.py`.
- `fetch_pdf()` performs a real Supabase Storage download and returns bytes (or raises
  `PdfExtractionError`) — no stub `raise` left in place.
- `parse_pdf()` performs real PDF text extraction and returns a dict matching the
  `{status, fields, confidence}` shape — no stub `raise` left in place.
- A migration exists for `pdf_extraction` (`python manage.py makemigrations` produces no pending
  changes for this app afterward) and `python manage.py migrate` succeeds against a fresh DB.
- Manually exercise the full pipeline once: `POST /pdf-extraction/jobs/` with a real bucket/path →
  poll `GET /pdf-extraction/jobs/<id>/` → confirm it reaches `status: "done"` with a populated
  `result`, not `status: "failed"`.
- `pdf_extraction/models.py`'s inaccurate "unmanaged stubs" docstring is corrected.

## Cross-repo dependency
Depends on backend task 001 having settled the canonical route path name (don't build frontend
integration against a path that's about to be renamed — this task itself doesn't need the renaming
done first, only frontend task 003 does).
