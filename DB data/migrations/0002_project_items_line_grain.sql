-- Migration 0002 — line-item grain for projects (multi-product opportunities)
--
-- Applies to: Supabase project asdxuyrhxhlmsxmqiuxa. Run by hand in the Supabase SQL editor,
-- same as 0001. Nothing in this repo runs it automatically.
--
-- ---------------------------------------------------------------------------------------------
-- WHY
-- ---------------------------------------------------------------------------------------------
-- projects.product_id is a single nullable FK and projects.status is a single enum, so a project
-- carrying 3 chillers and 4 pumps cannot be represented at all -- and a project that is WON on the
-- pumps and LOST on the chillers has no representation whatsoever. The commercial outcome columns
-- (our_price, competitor_name, competitor_price, win_reason, loss_reason) live on
-- project_status_history, which is keyed to the project, so they can only ever hold ONE outcome.
--
-- There is also no quantity column anywhere in the schema: "3 chillers" is unrepresentable before
-- you even reach the outcome problem.
--
-- This migration introduces the header/line split: projects stays the header (customer,
-- application, scope, ownership) and project_items carries one row per product line with its own
-- quantity, price, competitor and outcome.
--
-- ---------------------------------------------------------------------------------------------
-- DECISIONS BAKED IN HERE (agreed 2026-09-01)
-- ---------------------------------------------------------------------------------------------
-- * A line is won or lost AS A WHOLE. There is no partial win inside one product family.
--   When the client awards fewer units than were quoted (3 chillers quoted, 2 awarded), the sales
--   engineer who owns the project edits awarded_quantity down; the 1 undelivered unit is NOT
--   recorded as a loss. quantity keeps the quoted figure so the shortfall stays visible to
--   analytics as (quantity - awarded_quantity) instead of being silently overwritten.
-- * The project-level roll-up is a DATABASE TRIGGER, not application code, because rows in this
--   schema get hand-edited in the Supabase SQL editor and a service-layer roll-up would go stale
--   every time that happens.
-- * projects.product_id is NOT dropped here. It is left in place, unused, so that this migration
--   can be applied before the Django serializers and the React app are switched over. A later
--   migration drops it once nothing reads it.
-- * All money is USD. See 0004 for the rest of the commercial fields.
--
-- ---------------------------------------------------------------------------------------------
-- ON THE NEW ENUM VALUE (verified, not assumed)
-- ---------------------------------------------------------------------------------------------
-- The usual warning is that ALTER TYPE ... ADD VALUE cannot run in a transaction, or that the new
-- value cannot be USED in the transaction that added it -- which matters because the Supabase SQL
-- editor wraps a multi-statement run in one transaction.
--
-- Neither bites here, and this was checked rather than guessed: the whole file was run as a single
-- transaction against a PostgreSQL 16 replica of this schema and applied cleanly, after which the
-- roll-up correctly produced 'partiallyWon'.
--   * Adding a value inside a transaction has been legal since PostgreSQL 12 (Supabase is 15+).
--   * The "cannot use it yet" rule only applies to a statement that EVALUATES the new literal.
--     'partiallyWon' appears in this file only inside a PL/pgSQL function body, which is resolved
--     when the function is called, not when it is created.
--
-- SO: run this file top to bottom in one go.
--
-- The one thing that would break that: adding a statement to this file that writes or compares
-- the new value directly -- a backfill like UPDATE projects SET status='partiallyWon' ... . If you
-- ever add one, it has to move to a separate execution, or the run fails with
-- "unsafe use of new value "partiallyWon" of enum type project_status".
-- ---------------------------------------------------------------------------------------------

ALTER TYPE project_status ADD VALUE IF NOT EXISTS 'partiallyWon';

-- --- competitors -----------------------------------------------------------------------------
-- project_status_history.competitor_name is free text today. Free text makes market-share
-- analysis impossible: "Carrier", "carrier" and "Carier" are three different competitors to a
-- GROUP BY. A lookup table is the whole fix.
CREATE TABLE IF NOT EXISTS public.competitors (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL UNIQUE,
  country     text,
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- --- line status -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'project_item_status') THEN
    CREATE TYPE project_item_status AS ENUM ('pending','quoted','won','lost','cancelled');
  END IF;
END $$;

-- --- composite key on products ---------------------------------------------------------------
-- Lets project_items carry a composite FK (product_id, product_family) -> products(id, family),
-- so a Pump line pointing at a Chiller product is rejected BY THE DATABASE rather than by a code
-- review that someone skips. MATCH SIMPLE (the default) means the FK is not checked at all while
-- product_id is NULL, which is exactly what a family-only intake line needs.
ALTER TABLE public.products
  ADD CONSTRAINT products_id_family_key UNIQUE (id, family);

-- --- project_items ---------------------------------------------------------------------------
CREATE TABLE public.project_items (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id          uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,

  -- what is being sold on this line
  product_family      product_family NOT NULL,   -- always known: sales picks it at intake
  product_id          uuid NULL,                 -- NULL until Tech selects an actual model
  label               text,                      -- "Building A", "Basement pumps" -- lets the same
                                                 -- model appear twice on one project meaningfully

  -- quantity: quoted vs awarded (see DECISIONS above)
  quantity            integer NOT NULL CHECK (quantity > 0),
  awarded_quantity    integer NULL CHECK (awarded_quantity > 0),

  -- commercial. All amounts USD; see 0004.
  unit_price          numeric,
  currency            char(3) NOT NULL DEFAULT 'USD',
  competitor_id       uuid NULL REFERENCES public.competitors(id),
  competitor_price    numeric,

  -- outcome
  line_status         project_item_status NOT NULL DEFAULT 'pending',
  win_reason          win_reason NULL,
  loss_reason         loss_reason NULL,
  decided_at          timestamptz NULL,
  decided_by_user_id  uuid NULL REFERENCES auth.users(id),

  position            integer NOT NULL DEFAULT 0,   -- display order on the project page
  notes               text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT project_items_product_family_fk
    FOREIGN KEY (product_id, product_family) REFERENCES public.products(id, family),

  -- A won line carries a win_reason and no loss_reason.
  CONSTRAINT project_items_won_reason_chk CHECK (
    line_status <> 'won' OR (win_reason IS NOT NULL AND loss_reason IS NULL)
  ),
  -- A lost line carries a loss_reason and no win_reason.
  CONSTRAINT project_items_lost_reason_chk CHECK (
    line_status <> 'lost' OR (loss_reason IS NOT NULL AND win_reason IS NULL)
  ),
  -- An undecided line carries neither.
  CONSTRAINT project_items_open_reason_chk CHECK (
    line_status IN ('won','lost') OR (win_reason IS NULL AND loss_reason IS NULL)
  ),
  -- decided_at is set exactly when the line is decided.
  CONSTRAINT project_items_decided_at_chk CHECK (
    (line_status IN ('won','lost')) = (decided_at IS NOT NULL)
  ),
  -- awarded_quantity only exists on a won line, and can never exceed what was quoted.
  CONSTRAINT project_items_awarded_qty_chk CHECK (
    (line_status = 'won' AND awarded_quantity IS NOT NULL AND awarded_quantity <= quantity)
    OR (line_status <> 'won' AND awarded_quantity IS NULL)
  )
);

CREATE INDEX project_items_project_idx        ON public.project_items (project_id);
CREATE INDEX project_items_product_idx        ON public.project_items (product_id);
CREATE INDEX project_items_family_status_idx  ON public.project_items (product_family, line_status);
CREATE INDEX project_items_competitor_idx     ON public.project_items (competitor_id);

COMMENT ON COLUMN public.project_items.quantity IS
  'Quantity QUOTED. Never edited down after an award -- edit awarded_quantity instead, so the '
  'shortfall stays visible as (quantity - awarded_quantity).';
COMMENT ON COLUMN public.project_items.awarded_quantity IS
  'Quantity actually awarded. Set only on a won line; defaults to quantity when the line is won. '
  'Editable by the project''s own sales engineer.';

-- --- keep updated_at honest ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE TRIGGER project_items_touch_updated_at
  BEFORE UPDATE ON public.project_items
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

CREATE TRIGGER competitors_touch_updated_at
  BEFORE UPDATE ON public.competitors
  FOR EACH ROW EXECUTE FUNCTION public.touch_updated_at();

-- --- awarded_quantity: default it on a win, refuse it anywhere else --------------------------
-- Marking a line won should not also require restating the quantity, so it defaults. The sales
-- engineer edits it down afterwards only in the "awarded 2 of 4" case.
--
-- The two "not won" cases are deliberately NOT the same thing:
--   * the line is TRANSITIONING out of won -> the stale value is cleared, silently. Nobody asked
--     for it to survive.
--   * somebody is explicitly WRITING a value onto a line that is not won -> that is a caller bug,
--     and clearing it quietly would mean the API returns 200 having thrown the number away. Raise.
CREATE OR REPLACE FUNCTION public.project_items_default_awarded_qty()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.line_status = 'won' THEN
    IF NEW.awarded_quantity IS NULL THEN
      NEW.awarded_quantity := NEW.quantity;
    END IF;
  ELSE
    IF NEW.awarded_quantity IS NOT NULL
       AND (TG_OP = 'INSERT' OR NEW.awarded_quantity IS DISTINCT FROM OLD.awarded_quantity) THEN
      RAISE EXCEPTION 'awarded_quantity may only be set on a won line (this line is %)',
                      NEW.line_status
        USING ERRCODE = 'check_violation';
    END IF;
    NEW.awarded_quantity := NULL;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER project_items_default_awarded_qty_trg
  BEFORE INSERT OR UPDATE ON public.project_items
  FOR EACH ROW EXECUTE FUNCTION public.project_items_default_awarded_qty();

-- ---------------------------------------------------------------------------------------------
-- THE ROLL-UP
-- ---------------------------------------------------------------------------------------------
-- projects.status becomes a function of its lines:
--
--   no lines at all                         -> no change (normal for the first minutes after intake)
--   any line still pending or quoted        -> no change (the project is still in its workflow)
--   every non-cancelled line won            -> 'won'
--   every non-cancelled line lost           -> 'lost'
--   a mix of won and lost                   -> 'partiallyWon'
--   every line cancelled                    -> 'cancelled'
--
-- TERMINAL STATUSES ARE NEVER OVERWRITTEN. 'cancelled' and 'withDifferentContractor' mean the
-- opportunity died for a reason that has nothing to do with which lines were won -- see 0004,
-- where a contractor losing his own tender kills every open line at once. The roll-up must not
-- then relabel that project as a plain 'lost' and hide why it really died.
--
-- ** THE app.user_id TRAP **
-- There is an audit trigger on public.projects that raises "Missing app.user_id in DB session"
-- unless the calling transaction has run SET LOCAL app.user_id first. This roll-up UPDATEs
-- projects, so it inherits that requirement -- and a hand-edit of project_items in the SQL editor
-- has no such GUC set, so the hand-edit would fail with an error naming a table the person never
-- touched. The function therefore sets the GUC itself, falling back to the user who decided the
-- line and then to the project's sales engineer, and only when it is not already set (a real API
-- request always sets it, and that value must win).
CREATE OR REPLACE FUNCTION public.project_items_rollup_status()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_project_id  uuid := COALESCE(NEW.project_id, OLD.project_id);
  v_actor       uuid := COALESCE(NEW.decided_by_user_id, OLD.decided_by_user_id);
  v_current     project_status;
  v_sales_eng   uuid;
  v_open        integer;
  v_won         integer;
  v_lost        integer;
  v_cancelled   integer;
  v_total       integer;
  v_new         project_status;
BEGIN
  -- Serialise concurrent decisions on two lines of the same project. Without this lock, two
  -- transactions each see one decided line and one open line, and neither rolls up.
  SELECT status, sales_eng_id INTO v_current, v_sales_eng
  FROM public.projects WHERE id = v_project_id FOR UPDATE;

  IF NOT FOUND THEN
    RETURN NULL;  -- project already gone (ON DELETE CASCADE); nothing to roll up
  END IF;

  IF v_current IN ('cancelled','withDifferentContractor') THEN
    RETURN NULL;  -- terminal, see note above
  END IF;

  SELECT
    count(*) FILTER (WHERE line_status IN ('pending','quoted')),
    count(*) FILTER (WHERE line_status = 'won'),
    count(*) FILTER (WHERE line_status = 'lost'),
    count(*) FILTER (WHERE line_status = 'cancelled'),
    count(*)
  INTO v_open, v_won, v_lost, v_cancelled, v_total
  FROM public.project_items WHERE project_id = v_project_id;

  IF v_total = 0 OR v_open > 0 THEN
    RETURN NULL;  -- nothing to decide yet
  END IF;

  IF v_cancelled = v_total THEN
    v_new := 'cancelled';
  ELSIF v_lost = 0 THEN
    v_new := 'won';
  ELSIF v_won = 0 THEN
    v_new := 'lost';
  ELSE
    v_new := 'partiallyWon';
  END IF;

  IF v_new IS DISTINCT FROM v_current THEN
    PERFORM set_config(
      'app.user_id',
      COALESCE(NULLIF(current_setting('app.user_id', true), ''),
               v_actor::text,
               v_sales_eng::text),
      true  -- is_local: scoped to this transaction, never leaks to the next pooled query
    );
    UPDATE public.projects SET status = v_new, updated_at = now() WHERE id = v_project_id;
  END IF;

  RETURN NULL;
END $$;

CREATE TRIGGER project_items_rollup_trg
  AFTER INSERT OR UPDATE OF line_status OR DELETE ON public.project_items
  FOR EACH ROW EXECUTE FUNCTION public.project_items_rollup_status();

-- ---------------------------------------------------------------------------------------------
-- DEPRECATE THE PROJECT-LEVEL OUTCOME COLUMNS
-- ---------------------------------------------------------------------------------------------
-- Not dropped: existing rows are real history and the current serializers still read them. They
-- are marked so nobody writes new data into a shape that cannot hold two outcomes. A later
-- migration drops them once the backfill is done and nothing reads them.
COMMENT ON COLUMN public.project_status_history.our_price IS
  'DEPRECATED as of 0002 -- price is per line now: project_items.unit_price. Read-only history.';
COMMENT ON COLUMN public.project_status_history.competitor_name IS
  'DEPRECATED as of 0002 -- use project_items.competitor_id -> competitors.name. Read-only history.';
COMMENT ON COLUMN public.project_status_history.competitor_price IS
  'DEPRECATED as of 0002 -- per line now: project_items.competitor_price. Read-only history.';
COMMENT ON COLUMN public.project_status_history.win_reason IS
  'DEPRECATED as of 0002 -- per line now: project_items.win_reason. Read-only history.';
COMMENT ON COLUMN public.project_status_history.loss_reason IS
  'DEPRECATED as of 0002 -- per line now: project_items.loss_reason. Read-only history.';
COMMENT ON COLUMN public.projects.product_id IS
  'DEPRECATED as of 0002 -- a project has many products now: see project_items. Left in place so '
  'this migration can land before the Django serializers and the React app switch over. Stop '
  'writing it; a later migration drops it.';

-- ---------------------------------------------------------------------------------------------
-- BACKFILL -- every existing project gets one line, so no project is invisible to the new views.
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.project_items (project_id, product_family, product_id, quantity, line_status, position)
SELECT p.id, pr.family, p.product_id, 1, 'pending', 0
FROM public.projects p
JOIN public.products pr ON pr.id = p.product_id
WHERE p.product_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.project_items i WHERE i.project_id = p.id);
-- Projects that never had a product_id get no line: there is nothing truthful to invent. They
-- show up in the "needs lines" filter the intake UI should expose.

-- ---------------------------------------------------------------------------------------------
-- RLS -- REVIEW THESE AGAINST THE POLICIES ALREADY ON projects BEFORE RUNNING.
-- ---------------------------------------------------------------------------------------------
-- New Supabase tables are readable by anon unless RLS is on, so it goes on. These are baseline
-- policies: any authenticated employee reads, any authenticated employee writes. If projects
-- itself is narrower than that (per-department, per-sales-engineer), match it here instead --
-- a line is exactly as sensitive as the project it hangs off.
ALTER TABLE public.project_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.competitors   ENABLE ROW LEVEL SECURITY;

CREATE POLICY project_items_select ON public.project_items
  FOR SELECT TO authenticated USING (true);
CREATE POLICY project_items_write ON public.project_items
  FOR ALL TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY competitors_select ON public.competitors
  FOR SELECT TO authenticated USING (true);
CREATE POLICY competitors_write ON public.competitors
  FOR ALL TO authenticated USING (true) WITH CHECK (true);
