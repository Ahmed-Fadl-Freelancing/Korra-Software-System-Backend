# Korra — Cross-Repo Progress & Roadmap

> **Single source of truth shared by BOTH repos.** This exact file lives in
> `Korra-Software-System-Backend` and `korra-software-system-frontend` and must be
> kept **identical** in both. When you finish an issue in either repo, update this
> file in that repo and copy it to the other (or paste the diff).
>
> Legend: `[BE]` backend repo · `[FE]` frontend repo · ✅ Done · 🔧 In Progress · 🔲 Todo · 📋 Backlog
>
> Linear: Team **Korrra** (key `KOR`). One PR **per feature (milestone group)**, never per issue.
> Branch convention (new work): **`feat/<Name>`** (e.g. `feat/Auth`).
> Last updated: 2026-08-22 — KOR-93/95/96 (Opportunities list/manual-create/detail) and the
> `POST /documents/` metadata endpoint implemented on `claude/korra-project-setup-sumr8a`: real
> `Project`/`Document` models against the existing Supabase tables (no migration needed, tables
> already exist), contractor/owner/consultant get-or-created by name, `CreateOpportunity` rebuilt
> with real dropdowns/inputs in place of PDF extraction (still deferred — KOR-94/88-92 unchanged).
> Also corrected KOR-113–116's stale "In Review" status below — that PR merged to `main` a while
> ago. Day-to-day workstream sequencing lives in `korra-project/PLAN.md` (shared workspace, kept in
> sync with the backend repo) — see it for what's next and each task's `tasks/NNN-*.md` for full
> detail.
>
> **Brand:** Card palette = Blue · White · Silver. All UI must follow this. See `ISSUES.md` → Brand Identity for exact tokens.

---

## ▶ NEXT UP

KOR-117–121 and KOR-93/95/96 are done (see Milestones 2 and 4 below). Next-task sequencing now
lives in `korra-project/PLAN.md` — read it for the prioritized workstream order, and read the
relevant `tasks/NNN-*.md` file in this repo (or the backend repo) in full before starting any task.

---

## Milestone 2 — Auth Foundation & Session

**Branch:** `feat/Auth` (BE new work) · earlier BE work landed on `feature/auth-foundation`

| Repo | Issue | Title | Status |
|------|-------|-------|--------|
| [BE] | KOR-83 | `SupabaseJWTAuthentication` — local HS256 verify with `SUPABASE_JWT_SECRET` | ✅ Done |
| [BE] | KOR-84 | `GET /me` — profile + department + roles | ✅ Done |
| [BE] | KOR-85 | `GET /health` — liveness probe | ✅ Done |
| [BE] | KOR-113 | `POST /auth/signup` — proxy to Supabase Auth | ✅ Done (merged to `main`, PR #2) |
| [BE] | KOR-114 | `POST /auth/login` — password grant, relays Supabase tokens | ✅ Done (merged to `main`, PR #2) |
| [BE] | KOR-115 | `POST /auth/logout` — revoke Supabase session | ✅ Done (merged to `main`, PR #2) |
| [BE] | KOR-116 | `POST /auth/refresh` — refresh-token grant | ✅ Done (merged to `main`, PR #2) |
| [FE] | KOR-53 | Auth foundation — Backend Proxy (`/auth/*`), `AuthContext`, signIn/signUp/signOut | ✅ Done (merged) |
| [FE] | KOR-54 | App Layout — AppLayout, AppSidebar, Topbar skeleton | ✅ Done |
| [FE] | KOR-117 | GET /me — restore user profile fetch after login | ✅ Done |
| [FE] | KOR-118 | AuthContext — expose user profile, hasDepartment, hasRole, departmentName | ✅ Done |
| [FE] | KOR-119 | Department-based routing — /app → /app/sales or /app/tech | ✅ Done |
| [FE] | KOR-120 | ProtectedRoute — department null guard + role/section guards | ✅ Done |
| [FE] | KOR-121 | Topbar — display user full_name, department badge, manager badge | ✅ Done |

> **Architecture note:** Django never mints its own JWT. The `/auth/*` endpoints
> forward credentials to **Supabase Auth (GoTrue)**; Supabase issues the
> access/refresh tokens, and every later request is verified **locally** by
> `SupabaseJWTAuthentication`. The frontend may still call Supabase directly —
> the backend endpoints are an equivalent server-side path.

---

## Milestone 3 — Opportunity Ingestion

| Repo | Issue | Title | Branch | Status |
|------|-------|-------|--------|--------|
| [BE] | KOR-86 | `POST /documents/signed-upload-url` | `feature/document-storage` | ✅ Done |
| [BE] | KOR-87 | `GET /documents/signed-download-url` | `feature/document-storage` | ✅ Done |
| [BE] | KOR-88 | `fetch_pdf` — download PDF from Storage | `feat/PdfExtraction` | 🔲 Todo |
| [BE] | KOR-89 | `parse_pdf` — PyMuPDF (fitz) extraction | `feat/PdfExtraction` | 🔲 Todo |
| [BE] | KOR-90 | Celery async task wrapping the extraction pipeline | `feat/PdfExtraction` | 🔲 Todo |
| [BE] | KOR-91 | `POST /pdf-extraction/` — trigger job | `feat/PdfExtraction` | 🔲 Todo |
| [BE] | KOR-92 | `GET /pdf-extraction/{job_id}/` — poll status | `feat/PdfExtraction` | 🔲 Todo |
| [FE] | KOR-55 | Opportunity intake — PDF extraction UI (upload + confidence review) | `feat/Opportunity` | 🔲 Todo — deferred until KOR-88–92 land; see KOR-56 for the manual-entry stand-in used meanwhile |
| [FE] | KOR-56 | Opportunity intake — manual creation form | `feat/Opportunity` | ✅ Done — real dropdowns (application/scope/product family) + inputs, wired to `POST /opportunities/manual`; also uploads + registers documents against the created project |

## Milestone 4 — Opportunity Management

| Repo | Issue | Title | Branch | Status |
|------|-------|-------|--------|--------|
| [BE] | KOR-93 | `GET /opportunities` — list for current user | `feat/Opportunity` | ✅ Done |
| [BE] | KOR-94 | `POST /opportunities` — from PDF (Path A) | `feat/Opportunity` | 📋 Backlog — deferred until real PDF extraction (Milestone 3) lands; Path B below covers the same data-integration flow for now |
| [BE] | KOR-95 | `POST /opportunities/manual` — manual (Path B) | `feat/Opportunity` | ✅ Done — real `Project` row written to Supabase; contractor/owner/consultant get-or-created by name, product get-or-created by model code |
| [BE] | KOR-96 | `GET + PATCH /opportunities/{id}` — detail / status | `feat/Opportunity` | ✅ Done (PATCH currently limited to `status`) |
| [BE] | — | `POST /documents/` — persist metadata for a file already uploaded via signed URL, mark version/is_current | `feat/Opportunity` | ✅ Done (not originally tracked as its own KOR issue — added alongside KOR-95 since Path B needs it to actually register an uploaded file) |

## Milestone 5 — Workflow Tasks

| Repo | Issue | Title | Branch | Status |
|------|-------|-------|--------|--------|
| [BE] | KOR-97 | `GET /tasks` — list assigned | `feat/WorkflowTasks` | 📋 Backlog |
| [BE] | KOR-98 | `POST /tasks` — create linked to opportunity | `feat/WorkflowTasks` | 📋 Backlog |
| [BE] | KOR-99 | `PATCH /tasks/{id}` — update status | `feat/WorkflowTasks` | 📋 Backlog |

## Milestone 6 — RPA Integration

| Repo | Issue | Title | Branch | Status |
|------|-------|-------|--------|--------|
| [BE] | KOR-100 | `POST /webhooks/uipath` — HMAC-verified receiver | `feature/rpa-integration` | ✅ Done |
| [BE] | KOR-101 | Track RPA status on opportunities | `feature/rpa-integration` | 🔲 Todo |
| [BE] | KOR-102 | Retry logic for failed UiPath RPA jobs | `feature/rpa-integration` | 🔲 Todo |

## Milestone 7 — DB Security & Audit

| Repo | Issue | Title | Branch | Status |
|------|-------|-------|--------|--------|
| [BE] | KOR-103 | Enable RLS on core tables | `feat/DbSecurity` | 📋 Backlog |
| [BE] | KOR-104 | RLS policy — Sales Engineers (own rows) | `feat/DbSecurity` | 📋 Backlog |
| [BE] | KOR-105 | RLS policy — Managers (all rows) | `feat/DbSecurity` | 📋 Backlog |
| [BE] | KOR-106 | PostgreSQL trigger — status-history audit | `feat/DbSecurity` | 📋 Backlog |

---

## How to use this file

1. Look at **▶ NEXT UP** to find the next issue — for **either** repo.
2. If the next issue is tagged for the **other** repo, switch to that repo and open
   its copy of this file / Linear to get the canonical id, then work there.
3. One branch + one PR per **milestone feature group**, not per issue.
4. After each issue: flip its status here, commit, and keep both repos' copies in sync.
