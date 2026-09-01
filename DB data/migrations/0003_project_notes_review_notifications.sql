-- Migration 0003 — project notes, request-review, and notifications
--
-- Applies to: Supabase project asdxuyrhxhlmsxmqiuxa. Run by hand in the Supabase SQL editor.
-- Independent of 0002 -- it can be applied before, after or alongside it.
--
-- ---------------------------------------------------------------------------------------------
-- WHY
-- ---------------------------------------------------------------------------------------------
-- After the RFQ is uploaded, the client keeps changing requirements by phone or email without ever
-- issuing a new document. Today the only place to put that is documents.notes, which is attached to
-- a file -- so a change that arrives with no file has nowhere to live, and the sales engineer has no
-- way to tell the technical office that something moved.
--
-- Three tables:
--   project_notes           -- the ordered cards on the project page
--   project_review_requests -- "note added on <project> -- please check it out"
--   notifications           -- the generic inbox those requests land in
--
-- ---------------------------------------------------------------------------------------------
-- "THE BUTTON IS NOT CLICKABLE WITHOUT A NOTE"
-- ---------------------------------------------------------------------------------------------
-- Enforced three times over, because a disabled button is a suggestion, not a guarantee:
--   UI  -- the button is disabled while the composer is empty
--   API -- the endpoint rejects a request whose note_id is absent or points at a deleted note
--   DB  -- project_review_requests.note_id is NOT NULL REFERENCES project_notes(id)
-- The third one is the only one that survives a hand-written INSERT in the SQL editor.
--
-- ---------------------------------------------------------------------------------------------
-- WHY NOT REALTIME, WHY NOT EMAIL
-- ---------------------------------------------------------------------------------------------
-- Supabase Realtime would mean the React app opening a Supabase connection, which the frontend
-- rulebook forbids outright ("the only service the frontend talks to is the Django backend").
-- Email is out because the free tier allows 2 messages an hour. So: a plain table the frontend
-- polls through Django. If push is wanted later, it reads this same table -- nothing here changes.

-- ---------------------------------------------------------------------------------------------
-- project_notes
-- ---------------------------------------------------------------------------------------------
CREATE TABLE public.project_notes (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id          uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,

  body                text NOT NULL CHECK (length(btrim(body)) > 0),

  -- Which document version this note amends, when it amends one. A note saying "client dropped the
  -- 3rd chiller" is about RFQ v1; when v2 lands and is_current moves, the note must keep pointing at
  -- v1 or it will read as if it describes the current document when it does not.
  source_document_id  uuid NULL REFERENCES public.documents(id),

  -- Card order. numeric, not integer: dragging a card between two others writes ONE row
  -- ((prev+next)/2) instead of renumbering every card below it, which is what makes two people
  -- reordering at the same time harmless.
  position            numeric NOT NULL,

  created_by_user_id  uuid NOT NULL REFERENCES auth.users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  -- Soft delete. A hard delete would take the review request and its audit trail with it.
  deleted_at          timestamptz NULL,
  deleted_by_user_id  uuid NULL REFERENCES auth.users(id)
);

CREATE INDEX project_notes_project_position_idx
  ON public.project_notes (project_id, position) WHERE deleted_at IS NULL;
CREATE INDEX project_notes_document_idx ON public.project_notes (source_document_id);

COMMENT ON COLUMN public.project_notes.position IS
  'Fractional ordering key. To insert between two cards write (prev.position + next.position)/2; '
  'to append write (max(position) + 1). Never renumber the whole project.';

-- ---------------------------------------------------------------------------------------------
-- project_review_requests
-- ---------------------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'review_request_status') THEN
    CREATE TYPE review_request_status AS ENUM ('pending','acknowledged','resolved','cancelled');
  END IF;
END $$;

CREATE TABLE public.project_review_requests (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id            uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,

  -- NOT NULL is the whole point: a review request without a note cannot exist.
  note_id               uuid NOT NULL REFERENCES public.project_notes(id),

  requested_by_user_id  uuid NOT NULL REFERENCES auth.users(id),
  -- NULL means "whoever in the technical office picks it up" -- used when the project has no
  -- tech_off_eng_id assigned yet.
  requested_to_user_id  uuid NULL REFERENCES auth.users(id),

  status                review_request_status NOT NULL DEFAULT 'pending',
  message               text,

  created_at            timestamptz NOT NULL DEFAULT now(),
  acknowledged_at       timestamptz NULL,
  acknowledged_by_user_id uuid NULL REFERENCES auth.users(id),
  resolved_at           timestamptz NULL,

  CONSTRAINT review_request_not_self_chk CHECK (
    requested_to_user_id IS NULL OR requested_to_user_id <> requested_by_user_id
  ),
  CONSTRAINT review_request_ack_chk CHECK (
    (status = 'pending') = (acknowledged_at IS NULL)
    OR status IN ('resolved','cancelled')
  )
);

-- One open request per note. Clicking "request review" twice on the same card is a double-click,
-- not a second request.
CREATE UNIQUE INDEX project_review_requests_one_open_per_note
  ON public.project_review_requests (note_id) WHERE status = 'pending';

CREATE INDEX project_review_requests_project_idx ON public.project_review_requests (project_id);
CREATE INDEX project_review_requests_inbox_idx
  ON public.project_review_requests (requested_to_user_id, status) WHERE status = 'pending';

-- A review request may not point at a note that is already deleted, and may not point at a note
-- belonging to a different project. Neither is expressible as a CHECK (both need another row), so
-- it is a trigger.
CREATE OR REPLACE FUNCTION public.review_request_validate_note()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_project_id uuid;
  v_deleted_at timestamptz;
BEGIN
  SELECT project_id, deleted_at INTO v_project_id, v_deleted_at
  FROM public.project_notes WHERE id = NEW.note_id;

  IF v_deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot request review on a deleted note (note %)', NEW.note_id;
  END IF;
  IF v_project_id <> NEW.project_id THEN
    RAISE EXCEPTION 'Note % belongs to project %, not %', NEW.note_id, v_project_id, NEW.project_id;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER project_review_requests_validate_note
  BEFORE INSERT OR UPDATE OF note_id ON public.project_review_requests
  FOR EACH ROW EXECUTE FUNCTION public.review_request_validate_note();

-- ---------------------------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_type') THEN
    CREATE TYPE notification_type AS ENUM (
      'note_added',
      'review_requested',
      'review_acknowledged',
      'status_changed',
      'line_decided',
      'document_uploaded'
    );
  END IF;
END $$;

CREATE TABLE public.notifications (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES auth.users(id),   -- the recipient
  type           notification_type NOT NULL,
  title          text NOT NULL,
  body           text,

  -- What it is about. project_id is the common case; entity_id points at the note, the review
  -- request or the line, so the frontend can deep-link straight to the card.
  project_id     uuid NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  entity_id      uuid NULL,

  read_at        timestamptz NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_unread_idx
  ON public.notifications (user_id, created_at DESC) WHERE read_at IS NULL;
CREATE INDEX notifications_user_idx ON public.notifications (user_id, created_at DESC);

-- ---------------------------------------------------------------------------------------------
-- fan-out: a review request becomes notification rows
-- ---------------------------------------------------------------------------------------------
-- requested_to_user_id set    -> exactly one row, for that person
-- requested_to_user_id NULL   -> one row per active tech_office engineer, deduped
--                                (a user with two roles must not get two copies)
-- Never a row for the requester.
CREATE OR REPLACE FUNCTION public.review_request_fanout()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_project_name text;
BEGIN
  SELECT name INTO v_project_name FROM public.projects WHERE id = NEW.project_id;

  INSERT INTO public.notifications (user_id, type, title, body, project_id, entity_id)
  SELECT DISTINCT u.user_id,
         'review_requested'::notification_type,
         format('note added on %s — please check it out', v_project_name),
         NEW.message,
         NEW.project_id,
         NEW.id
  FROM (
    SELECT NEW.requested_to_user_id AS user_id
    WHERE NEW.requested_to_user_id IS NOT NULL
    UNION
    SELECT ur.user_id
    FROM public.user_roles ur
    JOIN public.roles r        ON r.id = ur.role_id
    JOIN public.user_profiles p ON p.user_id = ur.user_id
    WHERE NEW.requested_to_user_id IS NULL
      AND r.code IN ('tech_engineer','tech_office')
      AND p.is_active
  ) u
  WHERE u.user_id IS NOT NULL
    AND u.user_id <> NEW.requested_by_user_id;

  RETURN NULL;
END $$;

CREATE TRIGGER project_review_requests_fanout
  AFTER INSERT ON public.project_review_requests
  FOR EACH ROW EXECUTE FUNCTION public.review_request_fanout();

CREATE TRIGGER project_notes_touch_updated_at
  BEFORE UPDATE ON public.project_notes
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();   -- defined in 0002

-- ---------------------------------------------------------------------------------------------
-- RLS -- review against the policies already on projects before running (see note in 0002).
-- ---------------------------------------------------------------------------------------------
ALTER TABLE public.project_notes           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.project_review_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications           ENABLE ROW LEVEL SECURITY;

CREATE POLICY project_notes_select ON public.project_notes
  FOR SELECT TO authenticated USING (true);
CREATE POLICY project_notes_write ON public.project_notes
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY review_requests_select ON public.project_review_requests
  FOR SELECT TO authenticated USING (true);
CREATE POLICY review_requests_write ON public.project_review_requests
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

-- Notifications are the one table that is genuinely per-user: you read your own inbox, nobody
-- else's. Inserts come from the trigger above (SECURITY INVOKER, running as the requester), so
-- the insert policy has to allow writing a row addressed to someone else.
CREATE POLICY notifications_select_own ON public.notifications
  FOR SELECT TO authenticated USING (user_id = auth.uid());
CREATE POLICY notifications_update_own ON public.notifications
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY notifications_insert ON public.notifications
  FOR INSERT TO authenticated WITH CHECK (true);
