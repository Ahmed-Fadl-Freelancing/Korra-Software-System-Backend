# Proposal 001 — Multi-product projects, project notes, and analytics readiness

> **Status: proposal, not applied.** No SQL has been run. Read this, push back on the open
> decisions at the bottom, then the migrations get written as numbered files in
> `DB data/migrations/` per this repo's convention.
>
> Written against the schema in `DB data/schema.sql` + `DB data/Enum.json` as of the merge of PR #6.

---

## 0. The one sentence that explains all of this

**The schema's grain is "one product per project". The business's grain is "one product line per
project."** A project with 3 chillers and 4 pumps that wins the pumps and loses the chillers cannot
be represented today — not partially, not awkwardly, *not at all*. Every other problem below
(win/loss reasons, competitor pricing, market share, every analytics question) is downstream of
that one mismatch.

Today:

```
projects.product_id      → ONE product   (uuid FK, nullable)
projects.status          → ONE status    (project_status enum)
project_status_history   → win_reason / loss_reason / our_price /
                           competitor_name / competitor_price  ← at PROJECT level
```

There is also no `quantity` column anywhere in the schema. "3 chillers" is currently unrepresentable
even before you get to outcomes.

---

## 1. Change set A — multi-product projects with per-line outcomes (P0)

### A1. New table: `project_items`

The header/line-item split. A project becomes the *header* (customer, application, scope, who owns
it); each product line carries its own quantity, price, outcome and reason.

```sql
CREATE TYPE project_item_status AS ENUM ('pending','quoted','won','lost','cancelled');

CREATE TABLE public.project_items (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id         uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,

  -- what is being sold on this line
  product_family     product_family NOT NULL,        -- always known (sales picks it at intake)
  product_id         uuid NULL REFERENCES public.products(id),  -- NULL until Tech selects a model
  label              text,                            -- "Building A", "Basement pumps" — lets the same
                                                      -- model appear twice on one project meaningfully
  quantity           integer NOT NULL CHECK (quantity > 0),

  -- commercial
  unit_price         numeric,
  currency           char(3) NOT NULL DEFAULT 'EGP',
  competitor_id      uuid NULL REFERENCES public.competitors(id),
  competitor_price   numeric,

  -- outcome
  line_status        project_item_status NOT NULL DEFAULT 'pending',
  win_reason         win_reason NULL,
  loss_reason        loss_reason NULL,
  decided_at         timestamptz NULL,
  decided_by_user_id uuid NULL REFERENCES auth.users(id),

  notes              text,
  attributes         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),

  -- a won line must carry a win reason and no loss reason, and vice versa
  CONSTRAINT project_items_won_reason_chk CHECK (
    line_status <> 'won' OR (win_reason IS NOT NULL AND loss_reason IS NULL)),
  CONSTRAINT project_items_lost_reason_chk CHECK (
    line_status <> 'lost' OR (loss_reason IS NOT NULL AND win_reason IS NULL)),
  -- undecided lines carry no reasons at all
  CONSTRAINT project_items_undecided_chk CHECK (
    line_status IN ('won','lost') OR (win_reason IS NULL AND loss_reason IS NULL)),
  -- decided_at is set exactly when the line is decided
  CONSTRAINT project_items_decided_at_chk CHECK (
    (line_status IN ('won','lost')) = (decided_at IS NOT NULL))
);

CREATE INDEX project_items_project_idx     ON public.project_items(project_id);
CREATE INDEX project_items_status_idx      ON public.project_items(line_status);
CREATE INDEX project_items_family_idx      ON public.project_items(product_family);
CREATE INDEX project_items_competitor_idx  ON public.project_items(competitor_id);
```

**Why `product_id` is nullable but `product_family` is not.** At RFQ intake, sales knows "3 chillers"
but not which model — model selection is Tech Office's job. This also fixes a bug found live during
testing: the current manual-create flow tries to get-or-create a `products` row from the sales form,
which crashes for Chillers because the real DB has a `products_chiller_gate_check` constraint
requiring `chiller_condenser` + `chiller_compressor` (that constraint is **not** visible in
`schema.sql` — that dump omits CHECK constraints — but it is live; we hit it). With this design,
sales never creates `products` rows at all: it creates a line with a family, and Tech attaches a real
product later.

**Guarding model/family agreement** — declaratively, so a Pump line can never point at a Chiller
product:

```sql
ALTER TABLE public.products ADD CONSTRAINT products_id_family_uk UNIQUE (id, family);
ALTER TABLE public.project_items
  ADD CONSTRAINT project_items_product_family_fk
  FOREIGN KEY (product_id, product_family) REFERENCES public.products(id, family);
```

### A2. New table: `competitors`

"Market share" and "price vs competitor" are unanswerable against a free-text
`project_status_history.competitor_name` — you will get five spellings of one company inside a month.

```sql
CREATE TABLE public.competitors (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name       text NOT NULL UNIQUE,
  country    text,
  notes      text,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

Same get-or-create-by-name pattern already used for `contractors` / `owners` / `consultants`.

### A3. `projects.status` becomes a roll-up, and needs a new value

```sql
ALTER TYPE project_status ADD VALUE 'partiallyWon';
```

> **Operational caveat:** in PostgreSQL 12+ this *can* run inside a transaction, but the new value
> **cannot be referenced** until that transaction commits. So this goes in its **own migration file**,
> applied and committed before any migration or code that writes `'partiallyWon'`.

Roll-up rule, over lines that are not `cancelled`:

| Lines state | `projects.status` becomes |
|---|---|
| every line `won` | `won` |
| every line `lost` | `lost` |
| at least one `won` **and** at least one `lost`, none undecided | `partiallyWon` |
| any line still `pending`/`quoted` | **unchanged** (stays in its workflow status) |
| every line `cancelled` | `cancelled` |
| zero lines | **unchanged** (normal right after intake) |

### A4. Deprecate the project-level outcome columns

`project_status_history.our_price`, `competitor_name`, `competitor_price`, `win_reason`,
`loss_reason` now have a *lower-grain* home on `project_items`. Leaving both writable guarantees they
drift and gives you two contradictory answers to "why did we lose this?".

Recommendation: **stop writing them**, keep the columns (nullable, existing rows preserved), and let
`project_status_history` go back to being what its name says — a pure workflow audit trail
(`from_status`, `to_status`, `changed_by_user_id`, `changed_at`, `notes`, `meta`). Add a comment in
the migration so the next person knows they're frozen, not forgotten.

---

## 2. Change set B — project notes + request-review (P1)

Today there is nowhere to put "the client changed the flow rate over the phone, no new RFQ".
`documents.notes` is one text field bolted to one document version; `project_status_history.notes`
only exists when the status changes. Neither is a project-level, orderable, reviewable note.

### B1. `project_notes`

```sql
CREATE TABLE public.project_notes (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id         uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  body               text NOT NULL CHECK (length(btrim(body)) > 0),   -- no empty notes, ever
  author_user_id     uuid NOT NULL REFERENCES auth.users(id),
  source_document_id uuid NULL REFERENCES public.documents(id),        -- "amends this RFQ version"
  position           numeric NOT NULL,                                 -- fractional ordering
  is_pinned          boolean NOT NULL DEFAULT false,
  deleted_at         timestamptz NULL,                                 -- soft delete
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX project_notes_project_idx ON public.project_notes(project_id, position)
  WHERE deleted_at IS NULL;
```

**Why `position numeric` and not `integer`.** Fractional indexing: to drop a card between positions
`1` and `2`, write `1.5` — no renumbering of other rows, no unique constraint to fight, no
`DEFERRABLE INITIALLY DEFERRED` dance when two cards swap places. (That last one matters here: this
schema already has `NOT DEFERRABLE INITIALLY IMMEDIATE` constraints that bit us once during document
testing.)

**Why soft delete.** A review request points at a note. If notes hard-delete, either the review trail
breaks or the FK blocks the delete. `deleted_at` keeps the history honest.

### B2. `project_review_requests`

```sql
CREATE TYPE review_request_status AS ENUM ('pending','acknowledged','resolved','cancelled');

CREATE TABLE public.project_review_requests (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  project_id            uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  note_id               uuid NOT NULL REFERENCES public.project_notes(id),  -- ★ see below
  requested_by_user_id  uuid NOT NULL REFERENCES auth.users(id),
  requested_to_user_id  uuid NULL REFERENCES auth.users(id),   -- NULL = whole Tech Office
  status                review_request_status NOT NULL DEFAULT 'pending',
  message               text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  acknowledged_at       timestamptz NULL,
  resolved_at           timestamptz NULL,
  CONSTRAINT review_no_self_request CHECK (requested_to_user_id <> requested_by_user_id)
);

-- one open request per note — stops double-clicking the button spamming Tech Office
CREATE UNIQUE INDEX project_review_requests_one_open_idx
  ON public.project_review_requests(note_id) WHERE status = 'pending';
```

★ **`note_id NOT NULL` is the answer to "make that btn not clickable without a note."** Enforce it in
three places, not one:

1. **UI** — button disabled while the note box is empty (best UX).
2. **API** — 400 if `note_id` missing or the note body is blank (stops a crafted request).
3. **DB** — `NOT NULL` + the `body` CHECK (stops anything that bypasses the API, including hand-edits
   in the Supabase SQL editor, which is a workflow this project actually uses).

### B3. `notifications`

"notify tech-engineer on specific project: *note added on `<project-name>`, please check it out*".

```sql
CREATE TYPE notification_type AS ENUM
  ('review_requested','note_added','status_changed','document_uploaded','assignment_changed');

CREATE TABLE public.notifications (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  recipient_user_id uuid NOT NULL REFERENCES auth.users(id),
  type              notification_type NOT NULL,
  project_id        uuid NULL REFERENCES public.projects(id) ON DELETE CASCADE,
  payload           jsonb NOT NULL DEFAULT '{}'::jsonb,  -- { note_id, project_name, requested_by_name }
  read_at           timestamptz NULL,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX notifications_unread_idx
  ON public.notifications(recipient_user_id, created_at DESC) WHERE read_at IS NULL;
```

Delivery: the frontend polls `GET /notifications?unread=true`. Two alternatives, both rejected for now:

- **Supabase Realtime** would need the frontend to hold a Supabase client — a direct violation of the
  repo's "the only service the frontend talks to is the Django backend" rule. If you want live
  push later, proxy it (SSE from the backend), don't punch a hole in that rule.
- **Email** is a non-starter today: this project is on the Supabase free tier, capped at ~2 emails/hour
  (we hit that limit during testing this session).

When `requested_to_user_id` is NULL (no tech engineer assigned yet), fan out one `notifications` row
per user holding the `tech_engineer` role — one row per recipient keeps "mark as read" per-user
trivial, versus a single broadcast row that needs a separate read-receipt table.

---

## 3. Change set C — analytics (P2/P3)

### C1. What the change sets above unlock

Every item on your list becomes ordinary SQL **only after** change set A, because they all need the
line grain:

| You want | Needs | Possible today? |
|---|---|---|
| Win rate by product family | per-line outcome | ❌ mixed projects are uncountable |
| Lost/won reason breakdown | per-line reasons | ❌ project-level reason lies about mixed projects |
| Market share | `competitors` + quantity | ❌ free-text competitor names |
| Price vs competitor | unit_price + competitor_price + currency | ❌ no quantity, no per-line price |
| Product performance | line grain per product | ❌ one product per project |
| Pipeline velocity (tendering → won) | `project_status_history` timestamps | ✅ already possible |

### C2. Serve analytics from views first, not a warehouse

Do **not** build the star schema yet. Build **Postgres views** now, so dashboards code against a
stable contract:

```sql
CREATE VIEW public.v_project_item_outcomes AS
SELECT
  pi.id                AS item_id,
  pi.project_id,
  p.name               AS project_name,
  p.application, p.scope,
  pi.product_family,
  pi.product_id,
  pr.model_code,
  pi.quantity,
  pi.unit_price, pi.currency,
  pi.unit_price * pi.quantity   AS line_value,
  pi.competitor_id, c.name      AS competitor_name,
  pi.competitor_price,
  pi.line_status, pi.win_reason, pi.loss_reason,
  pi.decided_at,
  p.sales_eng_id, p.tech_off_eng_id,
  p.contractor_id, p.consultant_id, p.owner_id,
  p.created_at         AS project_created_at
FROM public.project_items pi
JOIN public.projects    p  ON p.id  = pi.project_id
LEFT JOIN public.products    pr ON pr.id = pi.product_id
LEFT JOIN public.competitors c  ON c.id  = pi.competitor_id;
```

When volume eventually justifies it, `MATERIALIZED VIEW` or an ETL into fact tables — and the
dashboard queries don't change, because the view contract is the same.

### C3. If/when you do build the star schema — get the grain right now

The fact table's grain is **one `project_items` row**, not one project. Fixing the grain today (change
set A) means the later warehouse is a mechanical copy job:

- `fact_project_item` (grain = one line outcome) — measures: quantity, unit_price, line_value,
  competitor_price, price_delta, is_won
- dims: `dim_date`, `dim_product`, `dim_competitor`, `dim_customer` (contractor/consultant/owner),
  `dim_employee`, `dim_application`, `dim_scope`

Skip this now. Get the OLTP grain right and views will carry you a long way.

### C4. Gaps that will block analytics you haven't asked about yet

Worth deciding now, cheap to add, expensive to backfill:

1. **Currency.** Any `SUM(price)` across mixed EGP/USD quotes is meaningless. `currency` is in the
   `project_items` DDL above — keep it even if everything is EGP today.
2. **No dates for time-based loss reasons.** `loss_reason` includes `delivery_delay` and
   `response_delay`, but the schema stores no `bid_due_date`, no `submitted_at`, no
   `promised_delivery_date` — so those two reasons can only ever be someone's opinion, never a
   measured fact. Suggest `projects.bid_due_date date` and `project_items.promised_delivery_weeks int`.
3. **No geography.** "Market share" almost always gets sliced by region/city. There's no `region`
   anywhere. Suggest `projects.region text` (or a `regions` lookup if you'll standardise it).
4. **Partial-quantity outcomes.** See the open decision at the bottom.

---

## 4. Priority order

| P | Work | Why this order |
|---|---|---|
| **P0** | `project_items`, `competitors`, `partiallyWon`, roll-up, deprecate project-level outcome cols | Nothing else is correct without the right grain. Also fixes the live Chiller-create crash. |
| **P1** | `project_notes`, `project_review_requests`, `notifications` | Independent of P0, small, immediate day-to-day value. Can run in parallel. |
| **P2** | `v_*` analytics views + `GET /analytics/summary` (already scoped in `tasks/007`) | Needs P0's data to be meaningful. |
| **P3** | Star schema / fact tables | Only when volume justifies it. P2's views become its source. |

---

## 5. End-to-end sequence flow (what to validate)

```
INTAKE
 1. Sales creates project (header): name, contractor/owner/consultant, application, scope
    → projects row, status = tenderingPhase, NO lines yet
 2. Sales adds lines:  3 × Chiller (model TBD),  4 × Pump (model TBD)
    → 2 project_items rows, line_status = pending, product_id NULL
 3. Sales uploads RFQ PDF  → documents row (doc_type=rfq, version auto by trigger, is_current=true)

CLARIFICATION (no new document)
 4. Client changes a requirement by phone
    → project_notes row (body NOT NULL/non-blank, source_document_id = current RFQ, position = max+1)
 5. Sales clicks "Request review"  [button disabled until a note exists]
    → project_review_requests row (note_id NOT NULL, requested_to = tech engineer or NULL)
    → notifications row(s) for the recipient(s): "note added on <project> — please check it out"

TECH REVIEW
 6. Tech opens project, reads note cards in `position` order, acknowledges the request
    → review_request.status = acknowledged, acknowledged_at set
 7. Tech selects real models per line
    → project_items.product_id set (composite FK guarantees family matches)
 8. Status → technicalApproval
    → projects.status updated INSIDE a transaction that first does SET LOCAL app.user_id
    → project_status_history row written by the existing audit trigger

PRICING & NEGOTIATION
 9. unit_price + currency set per line; competitor_id + competitor_price recorded per line
10. Status → finalNegotiation

OUTCOME  (the part that does not work today)
11. Client awards pumps, rejects chillers:
      pump line   → line_status=won,  win_reason=price,     decided_at=now()
      chiller line→ line_status=lost, loss_reason=technical, decided_at=now()
    Each write: lock parent project row, apply line change, recompute roll-up
12. Roll-up: won + lost, none undecided → projects.status = partiallyWon
    (same transaction, same SET LOCAL app.user_id, one project_status_history row)

ANALYTICS
13. v_project_item_outcomes now has 2 rows for this project — one won, one lost, each with its own
    reason, price, competitor. Win-rate, reason breakdown and price-delta are all correct at line
    grain; the project counts once as "partially won", not once as "won" and not once as "lost".
```

---

## 6. Edge cases to validate

### Outcomes & roll-up
1. All lines won → `won`. All lost → `lost`. Mixed → `partiallyWon`.
2. **Some lines still undecided** → roll-up must *not* fire. Project stays in its workflow status.
3. **Zero lines** → roll-up must be a no-op, not a crash or a status change (this is the normal state
   for a few minutes right after intake).
4. **All lines cancelled** → project `cancelled`. Cancelled lines are excluded from the won/lost
   comparison everywhere else (and from win-rate denominators).
5. **Re-deciding a line** after the project already rolled up (won → lost) → roll-up recomputes, a new
   `project_status_history` row is written; `win_reason` must be cleared as `loss_reason` is set (the
   CHECK constraints force this — verify the API does it in one UPDATE, not two).
6. **Concurrent decisions on two lines of the same project** in two transactions → both roll-ups race
   on the parent. `SELECT … FROM projects WHERE id = ? FOR UPDATE` before recomputing serialises them.
   Verified live with two overlapping sessions (§11): the later one blocks, re-reads after the first
   commits, and lands on `partiallyWon` with exactly one history row — not the "each sees one line
   still open, so neither rolls up" outcome you get without the lock.
7. **★ The `app.user_id` trap.** Any UPDATE on `projects` fires the existing audit trigger, which
   errors with *"Missing app.user_id in DB session"* unless the transaction ran
   `SET LOCAL app.user_id = '<uuid>'` first. The roll-up updates `projects`. So: if the roll-up is a
   DB trigger on `project_items`, the *calling* transaction must still have set that GUC — test
   this explicitly, it will not be obvious when it breaks.

### Reasons & constraints
8. `won` with no `win_reason` → rejected by CHECK.
9. `lost` carrying a leftover `win_reason` → rejected by CHECK.
10. `pending` line carrying any reason → rejected by CHECK.
11. `decided_at` set on a pending line (or missing on a decided one) → rejected by CHECK.

### Products & lines
12. Line created as family-only (`product_id` NULL) → allowed; this is the intake default.
13. Pump line pointed at a Chiller product → rejected by the composite FK.
14. **Chiller model creation still requires** `chiller_condenser` + `chiller_compressor`
    (`products_chiller_gate_check`, live but absent from `schema.sql`). Model-selection UI must collect
    both; nothing else may auto-create Chiller products.
15. Same product twice on one project (Building A / Building B) → must be allowed. No unique index on
    `(project_id, product_id)`. `label` distinguishes them.
16. `quantity = 0` or negative → rejected by CHECK.

### Notes & review
17. Whitespace-only note → rejected at DB, API and UI.
18. Review request with no note → structurally impossible (`note_id NOT NULL`).
19. Second review request on a note that already has an open one → rejected by the partial unique index.
20. Requesting review from yourself → rejected by CHECK.
21. Note deleted while a review request references it → soft delete only; the request and its trail survive.
22. Two users reorder cards simultaneously → fractional positions make this harmless (last write wins
    on that one card; no other rows touched).
23. Note attached to an RFQ version that is later superseded (`is_current` moves to v2) → note stays
    attached to v1; the UI must show *which version* it annotates, or the note will read as if it
    describes the current document when it doesn't.
24. Review requested when the project has no `tech_off_eng_id` → `requested_to_user_id` NULL → fan out
    to every `tech_engineer`. Verify nobody gets two rows for one request.

### Analytics
25. Mixed-currency SUM → must be blocked or converted; never silently added.
26. Win rate = won / (won + lost). Pending, quoted and cancelled lines must be out of the denominator.
27. Projects with zero lines must not appear in product analytics (they'd read as a phantom zero).
28. Soft-deleted notes and cancelled lines filtered consistently across *every* view — inconsistency
    here is how two dashboards end up disagreeing.

---

## 7. Decisions — RESOLVED 2026-09-01, and where each one landed

| # | Question | Decision | Implemented in |
|---|---|---|---|
| 1 | Partial quantity | **No partial win inside a family.** A line is won or lost whole. When fewer units are awarded than quoted, the project's own sales engineer edits `awarded_quantity` down; the shortfall is *not* recorded as a loss. | `0002` — `quantity` (quoted) + `awarded_quantity` (nullable, won-only, `<= quantity`), defaulted on win by trigger |
| 2 | Roll-up in a trigger or the service layer | **Trigger**, because rows get hand-edited in the Supabase SQL editor and a service-layer roll-up goes stale every time that happens | `0002` — `project_items_rollup_status()` |
| 3 | Drop `projects.product_id` | **Keep for now**, marked deprecated, stop writing it. Backend switches to `project_items` first, frontend follows, a later migration drops it. | `0002` — `COMMENT ON COLUMN` |
| 4 | `bid_due_date` / `region` / `promised_delivery_weeks` | **Add all three**, plus `tender_due_date` and `quoted_at` — without those last two the `response_delay` and `delivery_delay` loss reasons stay unmeasurable | `0004` |
| 5 | Currency | **USD everywhere.** Conversion is a display feature served by a Django `/fx/rates` proxy, never written back into a price column. | `0004` Part 3 |

### 1 — why `awarded_quantity` and not just editing `quantity`

The instinct is to let the sales engineer change `quantity` from 3 to 2 and be done. Don't: that
destroys the fact that 3 were quoted. Six months later nobody can answer "how often do we get
scaled down after winning, and on which product?" — which is a real signal about pricing and about
how the RFQ was read. Two columns, one editable field in the UI, and the shortfall stays visible as
`quantity - awarded_quantity`.

Editing is restricted to the project's own sales engineer (`projects.sales_eng_id`) — enforce it in
the API, not only the UI.

### 2 — what the question actually was

When the pump line is marked won and the chiller line lost, *something* has to notice and set
`projects.status = 'partiallyWon'`. That code lives in one of two places:

- **In Postgres**, as a trigger on `project_items` — fires on *any* change, including rows edited
  by hand in the Supabase SQL editor.
- **In Django**, in the service layer — fires only when the change arrives through the API. Every
  hand-edit silently leaves the project's status wrong.

Given that this project's normal workflow includes hand-editing rows in the SQL editor, the trigger
is the only one that stays correct. The cost is hidden behaviour, which this schema has already
inflicted twice (the `documents` BEFORE-INSERT bug in `0001`, and the `app.user_id` audit trigger) —
so the function is written defensively: it takes `FOR UPDATE` on the parent before recomputing, it
refuses to overwrite a terminal status, and it sets `app.user_id` itself when the caller hasn't
(see edge case 7).

---

## 8. Change set D — in-tender vs in-hand (answering the sixth question)

**This is an attribute of the deal, not a workflow status.** That single distinction is the whole
answer.

The pull is to reuse `projects.status = 'tenderingPhase'`, since the value already exists. It's the
wrong move. `status` answers *"where is Korra's work"* — `technicalApproval`, `finalNegotiation`.
The new question is *"does the contractor even have the job"*. The two move independently: a
contractor can still be bidding while Korra's own work has already reached technical approval. Fold
them into one column and every time the internal status advances, the record of whether the job was
ever secured is erased.

So: `projects.tender_stage` — `inTender` | `inHand`, defaulting to `inTender` (treating a
speculative deal as secured overstates the pipeline; the reverse only understates it).

### What it buys

**Priority of work — the thing you asked about.** An in-hand deal is revenue being decided now; an
in-tender deal is a lottery ticket. `v_work_queue` in `0005` sorts on it. The score is *derived, not
stored*: a stored priority column is wrong the day after it's written, because a deal becomes urgent
purely by the date moving and nobody re-ranks the list by hand.

```
overdue quote                +1000
in-hand                      + 500
due within 3 / 7 / 14 days   + 300 / +200 / +100
no lines yet (needs intake)  +  75
```

A project is *in* the queue when it is non-terminal **and** either still has undecided lines or has
no lines at all. Filtering on status alone is not enough: a `partiallyWon` project whose every line
is already decided has nothing left to do on it and would otherwise sit in somebody's queue
forever.

**An honest win rate.** The contractor loses his own tender, so Korra's opportunity dies — through
no fault of the quote. Today the only way to record that is `lost` with a `loss_reason` that isn't
true, and `price` is the one people reach for. That single miscoding is enough to make the sales
manager's win/loss chart lie. Hence the new `loss_reason = 'contractor_lost_tender'`, and the rule
every view in `0005` obeys: **tender attrition is not a competitive loss and never enters a win-rate
denominator.** It gets its own column so the two questions stay separable:

- *Did the contractor pick us?* → competitive win rate
- *Did the work turn into revenue?* → realisation rate, attrition included

**Market share that isn't triple-counted.** One building, tendered by its owner, reaches Korra
through three contractors who are all bidding for it. That's one opportunity quoted three times, but
three rows in `projects`. Counted naively, winning it through contractor B reads as 1 win and 2
losses — 33%, when the truth is Korra got the building. `tender_groups` + `projects.tender_group_id`
(both nullable, so they cost nothing when the case doesn't arise) let `v_tender_group_outcomes`
count the group once.

### The kill path

A contractor losing his tender kills every open line at once. Doing that line-by-line from the API
invites a half-killed project when the second call fails, so it's one function:
`project_contractor_lost_tender(project_id, actor_id, note)`. It sets every still-open line to
`lost` / `contractor_lost_tender`, and the project to `withDifferentContractor` — a `project_status`
value that already exists and means exactly this. The roll-up in `0002` treats
`withDifferentContractor` and `cancelled` as **terminal and never overwritten**, so the reason the
project died survives instead of being flattened to a plain `lost`.

Lines already decided before the collapse are left alone: if a line was genuinely won, that's still
true and analytics should still see it.

---

## 9. Additional edge cases (29–40), from change sets A′ and D

### Quantity
29. `awarded_quantity` set on a line that is not won → rejected. Note this is enforced by the
    *trigger*, not the CHECK: the first version cleared the value silently, so the API would have
    returned 200 having thrown the number away. Caught by the test run below.
30. `awarded_quantity > quantity` → rejected by CHECK.
31. Line flipped won → lost after an award → `awarded_quantity` must return to NULL. The
    `BEFORE` trigger does it; verify the API doesn't try to set both in a way that fights it.
32. A user who is not the project's `sales_eng_id` edits `awarded_quantity` → API must reject.
    There is no DB constraint for this one; it is the only rule in this set that lives only in code.

### Tender stage
33. `inTender` → `inHand` mid-flight (the contractor wins his tender while Korra is still quoting)
    → allowed, and it must **not** touch `projects.status`. The work queue re-ranks on its own,
    because the score is derived.
34. `project_contractor_lost_tender` on a project that already has won lines → those lines keep
    their outcome; only open lines are killed. Project still goes to `withDifferentContractor`.
35. Roll-up must not fire after `withDifferentContractor` is set — otherwise the last line's
    decision relabels the project `lost` and the real reason vanishes. Terminal-status guard.
36. Same function called twice → second call is a no-op (no open lines left). Confirm it doesn't
    write a second `project_status_history` row.
37. `tender_due_date` earlier than `bid_due_date` → nonsense (Korra's quote due after the
    contractor's bid). Not constrained in the DB because real tenders do get extended; warn in
    the UI.
38. Three projects in one `tender_group`, two lost and one won → `v_tender_group_outcomes` reports
    **one** win. The per-project views still report 1 won and 2 lost. Both are correct; the
    dashboard must label which question it is answering.

### Currency
39. Any write of a non-USD amount into `unit_price` / `competitor_price` → wrong by construction.
    The converter is display-only; it never writes back.
40. FX API key in a `VITE_` variable → published in the browser bundle. The key lives in Django,
    which proxies `GET /fx/rates` with a daily cache — and the frontend rulebook allows exactly one
    backend anyway.

---

## 10. Migration files written

| # | File | Contents |
|---|---|---|
| 1 | `0002_project_items_line_grain.sql` | `competitors`, `project_item_status`, `partiallyWon`, `project_items` + 6 CHECKs + composite FK, roll-up trigger, awarded-qty trigger, deprecation comments, backfill, RLS |
| 2 | `0003_project_notes_review_notifications.sql` | `project_notes`, `project_review_requests` (`note_id NOT NULL`), `notifications` + fan-out trigger, RLS |
| 3 | `0004_tender_stage_and_commercial_fields.sql` | `contractor_lost_tender`, `project_tender_stage`, `tender_groups`, `regions`, `bid_due_date` / `tender_due_date` / `quoted_at` / `region_id`, `promised_delivery_weeks`, USD, contractor-lost-tender function |
| 4 | `0005_analytics_views.sql` | 7 views incl. `v_project_item_outcomes`, `v_work_queue`, `v_tender_group_outcomes`; `security_invoker` on all of them |

Run each file top to bottom, in that order, in the Supabase SQL editor. **No file needs splitting**
— see the note at the top of `0002` on why the usual enum-in-a-transaction warning does not apply
here, and what change to the file would make it apply.

Nothing has been applied to the live database.

---

## 11. Verification — what was actually run

These migrations were not written and handed over unrun. A PostgreSQL 16 cluster was built locally,
this schema was reconstructed into it from `DB data/schema.sql` + `Enum.json` (including the live
`products_chiller_gate_check` that `schema.sql` omits, and a reproduction of the audit trigger on
`projects` that demands `app.user_id`), and all four migrations were applied — **each as a single
transaction, the way the Supabase SQL editor runs a file**.

Then **51 assertions** ran against the result, covering the edge cases in §6 and §9: the full
3-chillers-and-4-pumps scenario end to end, every CHECK constraint, the composite family FK, the
Chiller gate, the zero-line project, blank notes, the note-less review request, the duplicate
review request, the self-request, the soft-deleted note, the fan-out dedupe, the terminal-status
guard, the analytics rules, and the two-session race. All 51 pass.

The harness is committed alongside the migrations in `DB data/migrations/_test/` so it can be
re-run after any change to them.

### Three real bugs the test run found

1. **`awarded_quantity` was silently discarded.** Setting it on a line that was not won passed
   without error, because the BEFORE trigger nulled the value before the CHECK could see it — so the
   API would have returned 200 having dropped the number. The trigger now distinguishes a *transition*
   out of `won` (clear it, silently, as intended) from an explicit *write* onto a non-won line
   (raise). Edge case 29 only became true after this fix.
2. **The fan-out trigger would not insert.** `'review_requested'` in an `INSERT … SELECT` is untyped
   text, and PostgreSQL will not implicitly cast text to an enum in that position. Every review
   request would have failed at runtime. Needed an explicit `::notification_type`.
3. **The contractor-lost-tender path wrote a status transition that never happened.** It killed the
   open lines first, which fired the roll-up while the project was still live — recording a move into
   `partiallyWon`, immediately followed by the real move to `withDifferentContractor`. Two rows in the
   audit trail, one of them a fiction. The function now sets the terminal status *first*, so the
   roll-up's own terminal guard swallows the line updates and the history gets one honest row.

### One thing I had documented wrongly

The earlier draft warned that `ALTER TYPE … ADD VALUE` had to be run on its own, separately from the
rest of the file. Tested: it does not. Adding an enum value inside a transaction has been legal since
PostgreSQL 12, and the "cannot use it yet" rule only applies to a statement that *evaluates* the new
literal — here both new values appear only inside PL/pgSQL function bodies, resolved at call time.
The whole file runs in one transaction and the roll-up then produces `partiallyWon` correctly. The
warning has been replaced with the accurate version, including the one edit that would reintroduce
the problem (adding a backfill that writes the new value directly).

### Not covered by the harness

- **RLS policies.** The ones in these files are baseline "any authenticated employee" policies. The
  live policies on `projects` are not in `schema.sql`, so they could not be replicated or compared.
  Read the RLS block in each file before running it — a line is exactly as sensitive as the project
  it hangs off, and if `projects` is narrower than this, these need to match.
- **The `awarded_quantity` ownership rule** — that only the project's own `sales_eng_id` may edit
  it. That one lives in the API layer, not the database (edge case 32).
- **Live Supabase.** The sandbox cannot open a raw Postgres connection through the proxy, so this
  ran against a reconstruction, not the real database.
