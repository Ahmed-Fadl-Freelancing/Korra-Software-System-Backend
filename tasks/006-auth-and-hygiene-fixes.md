# 006 — Auth/permissions hygiene, env var mismatch, dead code cleanup

## Goal
A grab-bag of correctness/hygiene issues found during a full code read (2026-08-21), none individually
huge but each a real bug or real risk if left alone. No dependency on any other task — pick this up
whenever convenient, ideally before backend task 003 starts relying on the permissions layer.

## Items

### 1. `UserRole` model PK likely doesn't match the real table
`accounts/models.py`'s `UserRole` declares `id: UUIDField(primary_key=True, default=uuid.uuid4)`, but
the actual Supabase table (`DB data/schema.sql:33-40`) defines `user_roles` with a **composite primary
key `(user_id, role_id)`** and no separate `id` column at all. Confirm against the real live schema
(not just the `schema.sql` snapshot, which is explicitly labeled "for context only, not meant to be
run" — verify against the actual Supabase DB) and fix the model to match: either drop the synthetic
`id` and set `Meta.unique_together`/no explicit PK handling appropriate for a `managed=False`
composite-key table, or confirm a real `id` column does exist in production and this was a
false-positive — either way, verify, don't assume the snapshot file is stale in the "safe" direction.

### 2. `accounts/permissions.py`'s role-check classes are dead and wrong
`IsSales`, `IsEngineer`, `IsManager`, `IsAdmin` (`accounts/permissions.py:33-50`) check for role codes
`"sales"`/`"engineer"`/`"manager"`/`"admin"`. The canonical role codes (per `CLAUDE.md`'s enum table
and `PROJECT_FLOW.md §1.2`) are `sales_engineer`/`tech_engineer`/`manager`/`admin` — `IsSales`/
`IsEngineer` would never match a real role row as written. Also confirmed via grep: **none of these
four classes are referenced anywhere** — dead code today. Fix the role-code strings to match canonical
values, and either start using them somewhere real (they'll be needed once backend task 003's
`PATCH /opportunities/{id}` or task 004's task-assignment logic wants role-gating) or, if you'd rather
defer usage, at least fix the bug so the next person who does wire them in doesn't inherit a silent
mismatch.

### 3. `SUPABASE_JWT_SECRET` vs `.env.example`'s `SUPABASE_SECRET_KEY`
`core/settings.py:131` reads `SUPABASE_JWT_SECRET` — this is what `SupabaseJWTAuthentication` needs to
verify every request; if unset, auth fails closed with a 500. `.env.example` has no
`SUPABASE_JWT_SECRET` entry at all — it has `SUPABASE_SECRET_KEY` instead (a different name, and
confirmed via grep that `SUPABASE_SECRET_KEY` is never read by any Python code — it's pure dead
placeholder text). Add `SUPABASE_JWT_SECRET=` to `.env.example` (placeholder value, obviously), and
either remove the unused `SUPABASE_SECRET_KEY` entry or rename it if it was meant to be the same thing
under a different name — confirm which with the human if genuinely ambiguous, but the safer default is
"add the real one, since its absence is an actual functional gap in the onboarding docs."

### 4. `.env.example` contains real-looking (non-placeholder) key material
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SECRET_KEY`, `SUPABASE_SERVICE_ROLE_KEY` in
`.env.example` currently look like real base64/JWT-shaped values, not `your-key-here`-style
placeholders. Replace them with obvious placeholders. If these are in fact live credentials for a
real Supabase project, flag to the human that they may need rotating (this task shouldn't rotate them
itself without confirmation — just stop hardcoding lookalike-real values in a file meant to be a
template).

### 5. `linear` Django app is dead code
`linear/linear_service.py` (a full 216-line GraphQL client for Linear issues/teams) is registered in
`INSTALLED_APPS` (`core/settings.py:46`) but has no `__init__.py`/`apps.py`/`models.py`/`urls.py`, is
never wired into `core/urls.py`, and is never imported anywhere else in the codebase. Decide: either
give it real app scaffolding and wire it up (if backend-side Linear integration is actually wanted —
note the frontend already has its own direct-to-Linear-GraphQL client, `src/lib/linear-client.ts`, so
check whether duplicating this server-side is actually desired before building it out), or remove it
from `INSTALLED_APPS` and delete the dead file if it's not going to be used. Don't leave it half-wired
as-is.

## Acceptance criteria
- `UserRole`'s PK matches the verified real Supabase schema (checked against live DB, not just the
  snapshot file).
- `IsSales`/`IsEngineer`/`IsManager`/`IsAdmin` check the canonical role-code strings.
- `.env.example` has a `SUPABASE_JWT_SECRET` entry; the `SUPABASE_SECRET_KEY`/naming mismatch is
  resolved one way or the other (not left inconsistent).
- No real-looking key material remains in `.env.example`.
- `linear` app is either functional (registered + wired + used) or removed — not left half-present.

## Cross-repo dependency
None. Independent hygiene work, safe to parallelize with anything else.
