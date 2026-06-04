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
> Last updated: 2026-06-04 — KOR-113–116 created in Linear, status: In Review (PR #2 open)

---

## ▶ NEXT UP

| Repo | Issue | Title | Branch | Status |
|------|-------|-------|--------|--------|
| **[BE]** | **KOR-113–116** | Auth session endpoints — signup / login / logout / refresh (Supabase proxy) | `feat/Auth` | 🔧 In Review (PR #2) |
| [FE] | KOR-5x | Wire login/signup forms to backend `/auth/*` (replace direct Supabase calls if desired) | `feat/Auth` | 🔲 Todo — confirm ID in FE repo |

> ℹ️ Frontend issue IDs below come from the handover docs (`BACKEND_HANDOVER.md`)
> and may differ from Linear. **Confirm the real KOR id in the frontend repo's
> own PROGRESS.md / Linear before starting an [FE] task.**

---

## Milestone 2 — Auth Foundation & Session

**Branch:** `feat/Auth` (BE new work) · earlier BE work landed on `feature/auth-foundation`

| Repo | Issue | Title | Status |
|------|-------|-------|--------|
| [BE] | KOR-83 | `SupabaseJWTAuthentication` — local HS256 verify with `SUPABASE_JWT_SECRET` | ✅ Done |
| [BE] | KOR-84 | `GET /me` — profile + department + roles | ✅ Done |
| [BE] | KOR-85 | `GET /health` — liveness probe | ✅ Done |
| [BE] | KOR-113 | `POST /auth/signup` — proxy to Supabase Auth | 🔧 In Review (PR #2) |
| [BE] | KOR-114 | `POST /auth/login` — password grant, relays Supabase tokens | 🔧 In Review (PR #2) |
| [BE] | KOR-115 | `POST /auth/logout` — revoke Supabase session | 🔧 In Review (PR #2) |
| [BE] | KOR-116 | `POST /auth/refresh` — refresh-token grant | 🔧 In Review (PR #2) |
| [FE] | KOR-53 | Auth foundation — Supabase JWT, `AuthContext`, `/me` hydration | ✅ Done (per handover) |
| [FE] | KOR-54 | App layout support | 🔲 Todo (per handover) |

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
| [FE] | KOR-55 | Opportunity intake — PDF extraction UI (upload + confidence review) | `feat/Opportunity` | 🔲 Todo (per handover) |
| [FE] | KOR-56 | Opportunity intake — manual creation form | `feat/Opportunity` | 🔲 Todo (per handover) |

## Milestone 4 — Opportunity Management

| Repo | Issue | Title | Branch | Status |
|------|-------|-------|--------|--------|
| [BE] | KOR-93 | `GET /opportunities` — list for current user | `feat/Opportunity` | 📋 Backlog |
| [BE] | KOR-94 | `POST /opportunities` — from PDF (Path A) | `feat/Opportunity` | 📋 Backlog |
| [BE] | KOR-95 | `POST /opportunities/manual` — manual (Path B) | `feat/Opportunity` | 📋 Backlog |
| [BE] | KOR-96 | `GET + PATCH /opportunities/{id}` — detail / status | `feat/Opportunity` | 📋 Backlog |

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
