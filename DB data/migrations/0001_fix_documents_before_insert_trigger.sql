-- Migration 0001 — fix the documents-insert bug found during live testing (2026-08-24).
--
-- Applies to: Supabase project asdxuyrhxhlmsxmqiuxa. Run directly in the Supabase SQL editor —
-- this repo has no migration runner of its own for hand-written SQL like this (Django's own
-- migrations only ever apply to Django-managed tables, none of which this touches). Track future
-- hand-run SQL against Supabase the same way: a new numbered file in this folder, applied once,
-- kept here permanently as the record of what changed and why.
--
-- ---------------------------------------------------------------------------------------------
-- SYMPTOM (found via live testing, see korra-project/SUCCESS_FLOW_STEPS.md step 8):
-- ---------------------------------------------------------------------------------------------
-- Inserting ANY row into public.documents fails unconditionally:
--   insert or update on table "projects" violates foreign key constraint "projects_current_offer_fk"
--   details: Key (current_offer_id)=(<uuid>) is not present in table "documents"
-- (or projects_current_submittal_fk for doc_type in {submittal, rfq} — same failure, different column)
--
-- ---------------------------------------------------------------------------------------------
-- ROOT CAUSE, confirmed via:
--   select tgname, pg_get_triggerdef(oid) from pg_trigger where tgrelid = 'public.documents'::regclass;
-- ---------------------------------------------------------------------------------------------
-- trg_documents_before_insert fires BEFORE INSERT and calls documents_set_version_and_current().
-- That function's version/is_current logic belongs in a BEFORE trigger (it mutates NEW before the
-- row is written). But it also updates projects.current_offer_id / current_submittal_id to point
-- at the new document's id -- from inside that same BEFORE trigger, i.e. before the documents row
-- has actually been written to the table. projects_current_offer_fk / projects_current_submittal_fk
-- are NOT DEFERRABLE INITIALLY IMMEDIATE, so the FK is checked immediately and fails every time --
-- the row it's pointing at genuinely doesn't exist in `documents` yet at that point in the
-- transaction. This is a timing bug, not a logic bug.
--
-- Caveat: this session has no SELECT access to the original function's source (PostgREST doesn't
-- expose function bodies, and this sandbox has no raw SQL execution channel to Supabase either --
-- see SUCCESS_FLOW_STEPS.md's "How this was actually tested"). The rewrite below reconstructs the
-- intended behavior from the trigger's name, its timing, and the exact observed failure -- not
-- from the literal original code. Review before running. Everything here is idempotent
-- (CREATE OR REPLACE / DROP IF EXISTS + CREATE), safe to run more than once.
--
-- ---------------------------------------------------------------------------------------------
-- FIX: split into two triggers by timing.
-- ---------------------------------------------------------------------------------------------
-- BEFORE INSERT stays scoped to mutating NEW's own columns (version, is_current) and flipping the
-- previously-current row for the same (project_id, doc_type) -- exactly what a BEFORE trigger is
-- for. A new AFTER INSERT trigger handles the projects-table sync, since by then the documents row
-- is committed and the FK check succeeds.

CREATE OR REPLACE FUNCTION public.documents_set_version_and_current()
RETURNS TRIGGER AS $$
BEGIN
  -- Auto-increment version per (project_id, doc_type)
  SELECT COALESCE(MAX(version), 0) + 1
    INTO NEW.version
  FROM public.documents
  WHERE project_id = NEW.project_id AND doc_type = NEW.doc_type;

  -- The newly inserted document becomes the current version for its (project_id, doc_type)
  NEW.is_current := true;

  -- Un-mark any previous "current" document of the same project_id + doc_type
  UPDATE public.documents
  SET is_current = false
  WHERE project_id = NEW.project_id
    AND doc_type = NEW.doc_type
    AND is_current = true;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- New: sync projects.current_offer_id / current_submittal_id AFTER the document row exists.
CREATE OR REPLACE FUNCTION public.documents_sync_project_current()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.doc_type = 'offer' THEN
    UPDATE public.projects SET current_offer_id = NEW.id WHERE id = NEW.project_id;
  ELSIF NEW.doc_type IN ('submittal', 'rfq') THEN
    UPDATE public.projects SET current_submittal_id = NEW.id WHERE id = NEW.project_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_documents_after_insert_sync_project ON public.documents;
CREATE TRIGGER trg_documents_after_insert_sync_project
AFTER INSERT ON public.documents
FOR EACH ROW EXECUTE FUNCTION public.documents_sync_project_current();

-- ---------------------------------------------------------------------------------------------
-- Related, but NOT part of this migration (no SQL involved, done directly via the Storage Admin
-- API during the same test session): the "documents" Storage bucket's allowed_mime_types was
-- ["document/pdf"] -- not a real MIME type, a typo for "application/pdf" -- which rejected every
-- real PDF upload unconditionally. Corrected to ["application/pdf"], confirmed by reading the
-- bucket config back. Noted here only so this file is a complete record of everything touched in
-- this pass, not because it belongs in a .sql migration.
-- ---------------------------------------------------------------------------------------------
