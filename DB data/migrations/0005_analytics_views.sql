-- Migration 0005 — analytics views
--
-- Applies to: Supabase project asdxuyrhxhlmsxmqiuxa. Run after 0002 and 0004.
--
-- ---------------------------------------------------------------------------------------------
-- WHAT THIS IS AND IS NOT
-- ---------------------------------------------------------------------------------------------
-- This is not the star schema. The star schema is deferred until the data volume justifies it, and
-- these views become its source when that day comes. What matters right now is that the GRAIN is
-- settled -- one row per product line, not one per project -- because a fact table built on the old
-- grain would bake the "a project has one outcome" bug in permanently.
--
-- Everything below is a plain view: no refresh, no staleness, correct the moment a row changes.
-- If any of them gets slow, the fix is MATERIALIZED VIEW + a refresh job, not a redesign.
--
-- ---------------------------------------------------------------------------------------------
-- THE RULES EVERY VIEW HERE OBEYS (inconsistency between them is how two dashboards end up
-- disagreeing about the same number in front of the same manager)
-- ---------------------------------------------------------------------------------------------
--  1. Cancelled lines never appear in a win-rate denominator.
--  2. Pending and quoted lines are pipeline, never outcome.
--  3. loss_reason = 'contractor_lost_tender' is NOT a competitive loss. The contractor lost his own
--     bid; Korra was never compared to anyone. It is counted separately, as tender attrition.
--  4. Soft-deleted notes are invisible everywhere.
--  5. Revenue on a won line is awarded_quantity x unit_price, never quantity x unit_price --
--     3 chillers quoted and 2 awarded is 2 chillers of revenue.
--  6. All amounts are USD (0004).

-- =============================================================================================
-- v_project_item_outcomes — the base view. Everything else reads this.
-- =============================================================================================
CREATE OR REPLACE VIEW public.v_project_item_outcomes AS
SELECT
  i.id                       AS item_id,
  i.project_id,
  p.name                     AS project_name,
  p.status                   AS project_status,
  p.tender_stage,
  p.tender_group_id,
  p.application,
  p.scope,
  p.sales_eng_id,
  p.tech_off_eng_id,
  p.region_id,
  rg.name                    AS region_name,
  c.name                     AS contractor_name,
  o.name                     AS owner_name,
  cs.name                    AS consultant_name,

  i.product_family,
  i.product_id,
  pr.model_code,
  pr.name                    AS product_name,
  i.label,

  i.quantity                 AS quantity_quoted,
  i.awarded_quantity,
  i.quantity - COALESCE(i.awarded_quantity, i.quantity) AS quantity_shortfall,

  i.unit_price,
  i.currency,
  i.quantity * i.unit_price                          AS quoted_value,
  CASE WHEN i.line_status = 'won'
       THEN i.awarded_quantity * i.unit_price END    AS won_value,

  i.competitor_id,
  comp.name                  AS competitor_name,
  i.competitor_price,
  -- Positive = Korra was more expensive. This is the number "price compared to competitor" means.
  CASE WHEN i.competitor_price IS NOT NULL AND i.competitor_price <> 0
       THEN round(((i.unit_price - i.competitor_price) / i.competitor_price) * 100, 2) END
                             AS price_delta_pct,

  i.line_status,
  i.win_reason,
  i.loss_reason,
  i.decided_at,
  i.decided_by_user_id,
  i.promised_delivery_weeks,

  p.bid_due_date,
  p.tender_due_date,
  p.quoted_at,
  p.created_at               AS project_created_at,

  -- Rule 3, computed once here so no downstream view has to remember it.
  (i.line_status = 'lost' AND i.loss_reason = 'contractor_lost_tender') AS is_tender_attrition,
  (i.line_status IN ('won','lost')
     AND NOT (i.line_status = 'lost' AND i.loss_reason = 'contractor_lost_tender'))
                             AS is_competitive_decision
FROM public.project_items i
JOIN public.projects    p    ON p.id  = i.project_id
LEFT JOIN public.products    pr   ON pr.id   = i.product_id
LEFT JOIN public.competitors comp ON comp.id = i.competitor_id
LEFT JOIN public.contractors c    ON c.id    = p.contractor_id
LEFT JOIN public.owners      o    ON o.id    = p.owner_id
LEFT JOIN public.consultants cs   ON cs.id   = p.consultant_id
LEFT JOIN public.regions     rg   ON rg.id   = p.region_id
WHERE i.line_status <> 'cancelled';   -- rule 1, applied once at the source

-- =============================================================================================
-- v_win_rate_by_family — "analytics of products"
-- =============================================================================================
CREATE OR REPLACE VIEW public.v_win_rate_by_family AS
SELECT
  product_family,
  count(*) FILTER (WHERE line_status = 'won')                        AS won_lines,
  count(*) FILTER (WHERE line_status = 'lost'
                     AND NOT is_tender_attrition)                    AS lost_lines,
  count(*) FILTER (WHERE is_tender_attrition)                        AS tender_attrition_lines,
  count(*) FILTER (WHERE line_status IN ('pending','quoted'))        AS open_lines,
  sum(won_value)                                                     AS won_value_usd,
  sum(quoted_value) FILTER (WHERE line_status IN ('pending','quoted')) AS open_value_usd,
  -- NULLIF keeps a family with no decisions yet out of the numbers instead of reporting it as 0%.
  round(
    100.0 * count(*) FILTER (WHERE line_status = 'won')
    / NULLIF(count(*) FILTER (WHERE is_competitive_decision), 0), 1
  )                                                                  AS win_rate_pct
FROM public.v_project_item_outcomes
GROUP BY product_family;

-- =============================================================================================
-- v_decision_reasons — "lost reasons" and "win reasons", one shape
-- =============================================================================================
CREATE OR REPLACE VIEW public.v_decision_reasons AS
SELECT 'won'::text AS outcome, win_reason::text AS reason, product_family,
       count(*) AS lines, sum(won_value) AS value_usd
FROM public.v_project_item_outcomes
WHERE line_status = 'won'
GROUP BY win_reason, product_family
UNION ALL
SELECT 'lost', loss_reason::text, product_family,
       count(*), sum(quoted_value)
FROM public.v_project_item_outcomes
WHERE line_status = 'lost'
GROUP BY loss_reason, product_family;

-- =============================================================================================
-- v_competitor_performance — "market share and price compared to competitor"
-- =============================================================================================
CREATE OR REPLACE VIEW public.v_competitor_performance AS
SELECT
  competitor_id,
  competitor_name,
  product_family,
  count(*) FILTER (WHERE line_status = 'won')  AS beat_them,
  count(*) FILTER (WHERE line_status = 'lost'
                     AND NOT is_tender_attrition) AS lost_to_them,
  round(avg(price_delta_pct), 2)               AS avg_price_delta_pct,
  round(avg(price_delta_pct) FILTER (WHERE line_status = 'lost'), 2)
                                               AS avg_price_delta_pct_when_lost,
  round(
    100.0 * count(*) FILTER (WHERE line_status = 'won')
    / NULLIF(count(*) FILTER (WHERE is_competitive_decision), 0), 1
  )                                            AS win_rate_vs_pct
FROM public.v_project_item_outcomes
WHERE competitor_id IS NOT NULL
GROUP BY competitor_id, competitor_name, product_family;

-- =============================================================================================
-- v_project_rollup — "analytics of projects", one row per project
-- =============================================================================================
-- Note this deliberately reads project_items directly rather than the base view: it needs the
-- cancelled lines in order to report has_open_lines honestly.
CREATE OR REPLACE VIEW public.v_project_rollup AS
SELECT
  p.id AS project_id,
  p.name,
  p.status,
  p.tender_stage,
  p.application,
  p.scope,
  p.sales_eng_id,
  p.region_id,
  p.bid_due_date,
  p.tender_due_date,
  count(i.id)                                                        AS total_lines,
  count(i.id) FILTER (WHERE i.line_status = 'won')                   AS won_lines,
  count(i.id) FILTER (WHERE i.line_status = 'lost')                  AS lost_lines,
  count(i.id) FILTER (WHERE i.line_status IN ('pending','quoted'))   AS open_lines,
  count(i.id) FILTER (WHERE i.line_status = 'cancelled')             AS cancelled_lines,
  sum(i.quantity * i.unit_price)
    FILTER (WHERE i.line_status <> 'cancelled')                      AS quoted_value_usd,
  sum(i.awarded_quantity * i.unit_price)
    FILTER (WHERE i.line_status = 'won')                             AS won_value_usd,
  p.created_at,
  p.quoted_at,
  -- Rule 5 of the queue: nothing sorts a work list like a deadline that is already past.
  (p.bid_due_date IS NOT NULL AND p.bid_due_date < current_date
     AND p.status NOT IN ('won','lost','cancelled','withDifferentContractor')) AS is_overdue
FROM public.projects p
LEFT JOIN public.project_items i ON i.project_id = p.id
GROUP BY p.id;

-- =============================================================================================
-- v_work_queue — priority of work (the reason tender_stage exists)
-- =============================================================================================
-- Priority is DERIVED, not stored. A stored priority column is wrong the day after it is written:
-- a deal that was low priority becomes urgent purely because the date moved, and nobody goes back
-- to re-rank the list by hand.
--
--   in-hand outranks in-tender          -- one is revenue being decided, the other is a lottery ticket
--   overdue outranks everything         -- the quote is already late
--   nearer deadline outranks later      -- within the same bucket
--   a project with no lines yet outranks a merely-open one -- it blocks everything downstream
--
-- WHAT COUNTS AS WORK: a non-terminal project that either still has undecided lines, or has no
-- lines at all and needs them. Filtering on status alone is not enough -- a 'partiallyWon' project
-- whose every line is already decided has nothing left to do on it, and would otherwise sit in
-- somebody's queue forever.
CREATE OR REPLACE VIEW public.v_work_queue AS
SELECT
  r.*,
  (CASE WHEN r.is_overdue                                        THEN 1000 ELSE 0 END)
  + (CASE WHEN r.tender_stage = 'inHand'                          THEN 500 ELSE 0 END)
  + (CASE
       WHEN r.bid_due_date IS NULL                                THEN 0
       WHEN r.bid_due_date <= current_date + 3                    THEN 300
       WHEN r.bid_due_date <= current_date + 7                    THEN 200
       WHEN r.bid_due_date <= current_date + 14                   THEN 100
       ELSE 50
     END)
  + (CASE WHEN r.total_lines = 0                                  THEN 75 ELSE 0 END)
  AS priority_score
FROM public.v_project_rollup r
WHERE r.status NOT IN ('won','lost','cancelled','withDifferentContractor')
  AND (r.open_lines > 0 OR r.total_lines = 0);

-- =============================================================================================
-- v_tender_group_outcomes — market share without triple-counting
-- =============================================================================================
-- One row per end job. Three contractors bidding the same building are one opportunity: winning it
-- through any of them is a win, and it is only a loss when Korra is on none of the winning bids.
-- Ungrouped projects (tender_group_id IS NULL) are their own group of one.
CREATE OR REPLACE VIEW public.v_tender_group_outcomes AS
SELECT
  COALESCE(p.tender_group_id, p.id)            AS group_key,
  (p.tender_group_id IS NOT NULL)              AS is_grouped,
  max(COALESCE(g.name, p.name))                AS group_name,
  count(DISTINCT p.id)                         AS quoted_via_projects,
  bool_or(p.status IN ('won','partiallyWon'))  AS korra_won_any,
  sum(r.won_value_usd)                         AS won_value_usd,
  sum(r.quoted_value_usd)                      AS quoted_value_usd
FROM public.projects p
JOIN public.v_project_rollup r ON r.project_id = p.id
LEFT JOIN public.tender_groups g ON g.id = p.tender_group_id
GROUP BY COALESCE(p.tender_group_id, p.id), (p.tender_group_id IS NOT NULL);

-- =============================================================================================
-- GRANTS
-- =============================================================================================
-- Views run with the definer's rights by default, which would bypass RLS on the tables underneath.
-- security_invoker makes each view honour the caller's policies instead, so a view can never become
-- the hole in a table's row-level security. Requires PostgreSQL 15+ (Supabase is).
ALTER VIEW public.v_project_item_outcomes  SET (security_invoker = true);
ALTER VIEW public.v_win_rate_by_family     SET (security_invoker = true);
ALTER VIEW public.v_decision_reasons       SET (security_invoker = true);
ALTER VIEW public.v_competitor_performance SET (security_invoker = true);
ALTER VIEW public.v_project_rollup         SET (security_invoker = true);
ALTER VIEW public.v_work_queue             SET (security_invoker = true);
ALTER VIEW public.v_tender_group_outcomes  SET (security_invoker = true);

GRANT SELECT ON public.v_project_item_outcomes,
               public.v_win_rate_by_family,
               public.v_decision_reasons,
               public.v_competitor_performance,
               public.v_project_rollup,
               public.v_work_queue,
               public.v_tender_group_outcomes
  TO authenticated;
