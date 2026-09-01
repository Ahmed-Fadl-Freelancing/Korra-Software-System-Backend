-- Migration 0004 — in-tender vs in-hand, plus the commercial fields analytics needs
--
-- Applies to: Supabase project asdxuyrhxhlmsxmqiuxa. Run by hand in the Supabase SQL editor,
-- after 0002 (it adds a column to project_items).
--
-- =============================================================================================
-- PART 1 — IN-TENDER vs IN-HAND
-- =============================================================================================
-- The situation: Korra quotes a contractor. Sometimes that contractor already HOLDS the main
-- contract and is genuinely choosing a supplier ("in hand"). Sometimes he does not hold it yet --
-- he is bidding for it, and he needs Korra's number to build his own bid ("in tender"). If he then
-- loses that bid, Korra's opportunity dies no matter how good the quote was.
--
-- THIS IS AN ATTRIBUTE OF THE DEAL, NOT A WORKFLOW STATUS.
-- That distinction is the whole design. projects.status already has a 'tenderingPhase' value, and
-- the temptation is to reuse it -- but status answers "where is OUR work" (technicalApproval,
-- finalNegotiation) while this answers "does the contractor even have the job". They move
-- independently: a contractor can still be in tender while Korra's own work has already reached
-- technical approval. Folding them into one column means every time the internal status advances,
-- the record of whether the job was ever secured is destroyed.
--
-- So: a separate tender_stage column, and 'tenderingPhase' goes back to meaning only what it says
-- about Korra's internal workflow.
--
-- WHAT IT BUYS:
--   * Priority of work -- an in-hand deal is real revenue that is being decided now; an in-tender
--     deal is a lottery ticket. The engineer's queue should be sorted accordingly. That sort is
--     derived in the view in 0005, not stored, so it cannot go stale.
--   * An honest win rate. Losing because the contractor lost his own tender is not losing to a
--     competitor. Without somewhere to put that, it gets miscoded as loss_reason='price' and
--     quietly destroys the number the sales manager is trying to read. Hence the new
--     'contractor_lost_tender' loss reason below.
--   * Weighted pipeline: in-hand and in-tender value cannot be added together as if they were the
--     same money.
--
-- ---------------------------------------------------------------------------------------------
-- ON THE NEW ENUM VALUE
-- ---------------------------------------------------------------------------------------------
-- Same situation as 0002, and verified the same way: 'contractor_lost_tender' is referenced only
-- inside a PL/pgSQL function body, so the whole file runs as one transaction. See the longer note
-- in 0002 for why, and for the one change that would break it.
-- ---------------------------------------------------------------------------------------------

ALTER TYPE loss_reason ADD VALUE IF NOT EXISTS 'contractor_lost_tender';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'project_tender_stage') THEN
    CREATE TYPE project_tender_stage AS ENUM ('inTender','inHand');
  END IF;
END $$;

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS tender_stage project_tender_stage NOT NULL DEFAULT 'inTender';

COMMENT ON COLUMN public.projects.tender_stage IS
  'inTender = the contractor does not hold the main contract yet and is bidding with our number. '
  'inHand   = the contractor holds it and is choosing a supplier now. Independent of status: a '
  'project can be inTender while status is technicalApproval. Drives work priority and keeps '
  '"the contractor lost his tender" out of the competitive win-rate.';

-- Default is inTender because it is the conservative reading: treating a speculative deal as
-- secured overstates the pipeline, the reverse only understates it.

CREATE INDEX IF NOT EXISTS projects_tender_stage_idx ON public.projects (tender_stage, status);

-- --- tender groups ---------------------------------------------------------------------------
-- The same building, tendered once by its owner, reaches Korra through three different contractors
-- who are all bidding for it. That is ONE opportunity for Korra, quoted three times -- but it is
-- three rows in projects. Counted naively, winning it through contractor B reads as 1 win and 2
-- losses (33%) when the truth is that Korra got the building (100%). Market share is exactly the
-- number this distorts, and market share is on the list of what you want to see.
--
-- Nullable, so it costs nothing when the situation does not arise.
CREATE TABLE IF NOT EXISTS public.tender_groups (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name           text NOT NULL,
  owner_id       uuid NULL REFERENCES public.owners(id),
  consultant_id  uuid NULL REFERENCES public.consultants(id),
  tender_due_date date NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.projects
  ADD COLUMN IF NOT EXISTS tender_group_id uuid NULL REFERENCES public.tender_groups(id);

COMMENT ON COLUMN public.projects.tender_group_id IS
  'Set when several projects are competing quotes for the SAME end job through different '
  'contractors. Analytics counts the group once, not once per contractor.';

CREATE INDEX IF NOT EXISTS projects_tender_group_idx ON public.projects (tender_group_id);

-- --- "the contractor lost his tender" ---------------------------------------------------------
-- One event kills every open line at once. Doing it line by line from the API invites a half-killed
-- project when the second call fails, so it is one function.
--
-- projects.status becomes 'withDifferentContractor' -- a value that already exists and means
-- exactly this. 0002's roll-up treats it as terminal and will not relabel it 'lost', so the reason
-- the project died survives.
CREATE OR REPLACE FUNCTION public.project_contractor_lost_tender(
  p_project_id uuid,
  p_actor_id   uuid,
  p_note       text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config(
    'app.user_id',
    COALESCE(NULLIF(current_setting('app.user_id', true), ''), p_actor_id::text),
    true
  );

  PERFORM 1 FROM public.projects WHERE id = p_project_id FOR UPDATE;

  -- ORDER MATTERS. The project goes terminal FIRST, before the lines are touched.
  --
  -- Do it the other way round and killing the last open line makes the roll-up fire while the
  -- project is still live: it sees won + lost, writes 'partiallyWon', and the audit trail then
  -- records a transition into a state the project was never actually in, immediately followed by
  -- the real one. Setting the terminal status first makes the roll-up's own terminal-status guard
  -- swallow the line updates, so the history gets exactly one honest row.
  UPDATE public.projects
     SET status = 'withDifferentContractor', updated_at = now()
   WHERE id = p_project_id
     AND status IS DISTINCT FROM 'withDifferentContractor';

  UPDATE public.project_items
     SET line_status        = 'lost',
         loss_reason        = 'contractor_lost_tender',
         win_reason         = NULL,
         decided_at         = now(),
         decided_by_user_id = p_actor_id
   WHERE project_id = p_project_id
     AND line_status IN ('pending','quoted');
END $$;

COMMENT ON FUNCTION public.project_contractor_lost_tender IS
  'Call when the contractor loses the main tender. Kills every still-open line with '
  'loss_reason=contractor_lost_tender and sets the project to withDifferentContractor. Already-'
  'decided lines are left alone -- if we had genuinely won a line before the tender collapsed, '
  'that is still true and analytics should still see it.';

-- =============================================================================================
-- PART 2 — THE COMMERCIAL FIELDS
-- =============================================================================================
-- Two of the loss reasons that already exist in the enum -- response_delay and delivery_delay --
-- are recordable today but not MEASURABLE: nothing in the schema records when the quote was due or
-- how long delivery was promised, so nobody can ever check whether the reason was fair or how bad
-- the delay was. These columns close that.

ALTER TABLE public.projects
  -- when Korra's quote is due to the contractor. Drives the work queue in every case.
  ADD COLUMN IF NOT EXISTS bid_due_date date NULL,
  -- when the contractor's own bid is due to the owner. Only meaningful while inTender; it is what
  -- makes an in-tender deal urgent rather than merely open.
  ADD COLUMN IF NOT EXISTS tender_due_date date NULL,
  ADD COLUMN IF NOT EXISTS region_id uuid NULL,
  -- set when the quote actually goes out, so (quoted_at - created_at) is the response time that
  -- response_delay is claiming was too long.
  ADD COLUMN IF NOT EXISTS quoted_at timestamptz NULL;

-- Region as a lookup table, for the same reason competitors is one: "Cairo", "cairo" and "New
-- Cairo" grouped by free text are three markets.
CREATE TABLE IF NOT EXISTS public.regions (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL UNIQUE,
  country    text NOT NULL DEFAULT 'Egypt',
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.projects
  ADD CONSTRAINT projects_region_id_fkey FOREIGN KEY (region_id) REFERENCES public.regions(id);

CREATE INDEX IF NOT EXISTS projects_region_idx   ON public.projects (region_id);
CREATE INDEX IF NOT EXISTS projects_bid_due_idx  ON public.projects (bid_due_date)
  WHERE status NOT IN ('won','lost','cancelled','withDifferentContractor');

-- Delivery is promised per product line, not per project: the pumps ship in 6 weeks and the
-- chillers in 20.
ALTER TABLE public.project_items
  ADD COLUMN IF NOT EXISTS promised_delivery_weeks integer NULL
    CHECK (promised_delivery_weeks IS NULL OR promised_delivery_weeks > 0);

-- =============================================================================================
-- PART 3 — CURRENCY
-- =============================================================================================
-- Everything is stored in USD. project_items.currency stays as an explicit label rather than an
-- assumption someone has to remember, but every amount in the database is USD and every SUM may
-- treat it as such.
--
-- THE CONVERTER IS A DISPLAY FEATURE, NOT A STORAGE ONE.
-- The calculator in the frontend converts for the person reading the screen. It must never write a
-- converted number back into unit_price or competitor_price: today's rate applied to last quarter's
-- deal silently rewrites history, and every report run on a different day then disagrees with the
-- last one.
--
-- AND IT CANNOT CALL THE FX API DIRECTLY. Two reasons: the frontend rulebook allows exactly one
-- backend (Django), and a Vite env var is compiled into the public bundle, so a VITE_ FX API key is
-- a published key. Django proxies it -- GET /fx/rates?base=USD, cached daily -- and the calculator
-- reads that.
--
-- If a non-USD quote ever has to be STORED, that is a separate migration adding entered_currency,
-- entered_amount, fx_rate_to_usd and fx_rate_at to the line, so the original number and the rate
-- that converted it are both preserved. Do not improvise it with the columns that exist.
ALTER TABLE public.project_items
  ALTER COLUMN currency SET DEFAULT 'USD';

UPDATE public.project_items SET currency = 'USD' WHERE currency <> 'USD';

COMMENT ON COLUMN public.project_items.currency IS
  'Always USD. Amounts are stored in USD; conversion is display-only, served by Django''s '
  '/fx/rates proxy. Never write a converted amount back into unit_price or competitor_price.';

-- --- RLS on the new lookup tables --------------------------------------------------------------
ALTER TABLE public.regions       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tender_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY regions_select ON public.regions
  FOR SELECT TO authenticated USING (true);
CREATE POLICY regions_write ON public.regions
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY tender_groups_select ON public.tender_groups
  FOR SELECT TO authenticated USING (true);
CREATE POLICY tender_groups_write ON public.tender_groups
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
