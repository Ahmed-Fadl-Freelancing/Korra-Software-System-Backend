# GitHub Copilot Instructions — Korra Backend

> **This file's body is kept IDENTICAL to `CLAUDE.md`** (Copilot reads this one,
> Claude reads `CLAUDE.md`). When you change AI rules, update **both** files in this repo, and copy them to
> the frontend repo (`korra-software-system-frontend`) so both repos and both LLMs share one rulebook.
> Cross-repo roadmap & "what's next" lives in `PROGRESS.md` (identical in both repos).

---

## ⛔ NEVER MERGE TO GITHUB
- **DO NOT** run `gh pr merge` or any auto-merge command, ever.
- **DO NOT** push directly to `main`. All work goes through feature branches.
- One PR **per feature (milestone group)** — not per issue. Create the PR, then **STOP** and wait for the human to merge.

---

## Repos
- **Backend:** `Korra-Software-System-Backend` — Django 4.2 + DRF + Supabase PostgreSQL.
- **Frontend:** `korra-software-system-frontend` — React 18 + Vite + TypeScript + Tailwind.
- **Linear:** Team **Korrra** (key `KOR`). Reference the KOR id in every commit.

## Session Start — Mandatory Steps
1. Read `PROGRESS.md` (cross-repo roadmap) → find the **▶ NEXT UP** issue. If it's tagged for the other repo, switch repos.
2. Read `WORKFLOW.md` (backend feature/branch/PR detail).
3. Check out the correct feature branch (`git checkout feat/<Name>`). **Never work on `main`.**
4. Implement the issues for that feature one by one.
5. Commit after each issue: `feat(scope): description (KOR-XX)`.
6. When all issues in the feature are done: push and open **one** PR targeting `main`.
7. Update `PROGRESS.md` + `WORKFLOW.md` statuses → `In Review`. **STOP** — wait for the human to merge.

## Branch Naming
- New work: **`feat/<Name>`** in PascalCase — e.g. `feat/Auth`, `feat/PdfExtraction`, `feat/Opportunity`.
- (Historical merged branches used `feature/<name>` — leave those as-is; don't rewrite history.)

---

## Architecture Constraints (never violate)
- Django is **stateless**. It never mints its **own** tokens or uses sessions/cookies.
- **Auth = Supabase JWT.** `SupabaseJWTAuthentication` decodes the HS256 JWT locally with `SUPABASE_JWT_SECRET` — **no per-request network call** to Supabase.
- `request.user` is an `AuthenticatedUser` (lightweight) with `user_id` = JWT `sub` claim; `request.auth` = the raw bearer token.
- **`/auth/*` endpoints are a Supabase Auth (GoTrue) proxy.** They forward credentials to Supabase, which issues the tokens; Django only relays them. This does **not** violate "never issue JWTs" — Django never signs a token itself.
- Authorization: query `user_profiles` + `user_roles`. **Never trust JWT claims for roles.**
- RLS enforced in Supabase PostgreSQL. Django trusts the DB layer — do **not** re-implement RLS.
- PDF extraction uses `pymupdf` (fitz) only, **in Django**. Never on the frontend.
- Extraction response shape: `{ status: "success"|"partial"|"failed", fields: {...}, confidence: {...} }`.
- UiPath webhook auth = HMAC-SHA256 (`X-UiPath-Signature`). **Not** JWT.

---

## API Route Map
| Method | Path | Feature / Branch | Auth | Status |
|---|---|---|---|---|
| GET | `/health` | auth-foundation | public | ✅ Done |
| GET | `/me` | auth-foundation | JWT | ✅ Done |
| POST | `/auth/signup` | `feat/Auth` | public | 🔧 In Progress |
| POST | `/auth/login` | `feat/Auth` | public | 🔧 In Progress |
| POST | `/auth/logout` | `feat/Auth` | JWT | 🔧 In Progress |
| POST | `/auth/refresh` | `feat/Auth` | public | 🔧 In Progress |
| POST | `/documents/signed-upload-url` | document-storage | JWT | ✅ Done |
| GET | `/documents/signed-download-url` | document-storage | JWT | ✅ Done |
| POST/GET | `/pdf-extraction/`, `/pdf-extraction/{id}/` | `feat/PdfExtraction` | JWT | 🔲 Todo |
| GET/POST | `/opportunities`, `/opportunities/manual` | `feat/Opportunity` | JWT | 📋 Backlog |
| GET/PATCH | `/opportunities/{id}` | `feat/Opportunity` | JWT | 📋 Backlog |
| GET/POST/PATCH | `/tasks`, `/tasks/{id}` | `feat/WorkflowTasks` | JWT | 📋 Backlog |
| POST | `/webhooks/uipath` | rpa-integration | HMAC | ✅ Done |

## Database Schema — Key Tables
| Table | Key Columns |
|---|---|
| `user_profiles` | **PK `user_id`** (= auth.uid / JWT sub), `employee_code`, `full_name`, `department_id` (FK), `job_title`, `is_active` |
| `departments` | `id`, `name`, `manager_user_id` |
| `roles` | `id`, `code`, `name` |
| `user_roles` | junction (`user_id`, `role_id`) |
| `projects` | `id`, `name`, `application`, `scope`, `status`, `sales_eng_id`, `extracted_data` (JSONB) |
| `documents` | `id`, `project_id`, `doc_type`, `version`, `bucket`, `path`, `is_current` |
| `project_status_history` | audit trail: `from_status`, `to_status`, `changed_by_user_id`, `changed_at` |

> ⚠️ `user_profiles` primary key column is **`user_id`**, not `id`. Map it with `db_column="user_id"`.

## Database Enums (exact PostgreSQL string values)
| Enum | Values |
|---|---|
| `document_type` | `offer`, `submittal`, `rfq` |
| `project_status` | `won`, `lost`, `technicalApproval`, `onHold`, `withDifferentContractor`, `tenderingPhase`, `cancelled`, `finalNegotiation` |
| `project_application` | `Industrial`, `Commercial`, `Health`, `Residential` |
| `project_scope` | `Supply`, `SupplyInstallation`, `Maintenance`, `Retrofit`, `Other` |
| `product_family` | `Chiller`, `Pump`, `Generator` |
| `chiller_condenser_method` | `AirCooled`, `WaterCooled` |
| `chiller_compressor_type` | `Centrifugal`, `Screw`, `Scroll`, `Reciprocating` |
| `win_reason` | `price`, `technical`, `relationship`, `service`, `sole_source`, `bundled_deal` |
| `loss_reason` | `price`, `technical`, `relationship`, `delivery_delay`, `response_delay`, `scope_changed`, `bad_experience` |

---

## Code Conventions
| Aspect | Convention |
|--------|-----------|
| Models | `PascalCase` in `app/models.py` (`managed = False` for Supabase tables) |
| Serializers | `app/serializers.py` |
| Views | `app/views.py` |
| Middleware | `middleware/` |
| Secrets | Always via `django-environ` + `.env` |
| Commits | `feat(scope): description (KOR-XX)` |

## Stack
Python 3.11+, Django 4.2, DRF 3, psycopg2, PyMuPDF (fitz), PyJWT, httpx, supabase-py, Celery + Redis, django-environ, django-cors-headers.

## Hard "Never Do" List
- Never use Django sessions or cookies.
- Never **sign/issue** a JWT in Django (Supabase issues them; `/auth/*` only relays).
- Never process PDFs on the frontend.
- Never bypass or re-implement Supabase RLS.
- Never hardcode `SUPABASE_JWT_SECRET`, `SUPABASE_ANON_KEY`, `DATABASE_URL`, or any credential.
- **Never merge a PR** — wait for the human reviewer.
