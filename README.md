# Korra Software System — Backend

Django REST API powering **Korra**, an internal sales/tech-office opportunity-tracking
system: it manages users and roles, tracks opportunities through their lifecycle
(tendering → technical approval → negotiation → won/lost), stores and signs document
uploads, extracts data from PDFs, and receives automation webhooks from UiPath.

Companion repo: [`korra-software-system-frontend`](https://github.com/Ahmed-Fadl-Freelancing/korra-software-system-frontend) (React + Vite + TypeScript).

## Stack

- **Django 4.2** + **Django REST Framework**
- **Supabase** — PostgreSQL database, Auth (GoTrue), and file storage
- **Celery + Redis** — background jobs
- **PyMuPDF (fitz)** — PDF field extraction
- **Gunicorn** — production server, containerized with Docker

## Architecture

- Django is **stateless** — it never mints its own JWTs or uses sessions/cookies.
- Authentication is handled by **Supabase Auth**. The `/auth/*` endpoints are a thin
  proxy to Supabase GoTrue; every subsequent request is verified **locally** via
  `SupabaseJWTAuthentication`, which decodes the HS256 JWT with `SUPABASE_JWT_SECRET`
  (no per-request network round-trip).
- Authorization is resolved from `user_profiles` + `user_roles` in the database —
  JWT claims are never trusted for role checks.
- Row-Level Security is enforced at the Supabase Postgres layer; Django relies on it
  rather than re-implementing access rules in application code.
- The UiPath RPA webhook is authenticated with an HMAC-SHA256 signature
  (`X-UiPath-Signature`), not JWT.

## Apps

| App | Responsibility |
|---|---|
| `accounts` | Auth proxy (signup/login/logout/refresh), `/me` profile endpoint |
| `core` | Project settings, root URL config, health check |
| `opportunities` | Opportunity lifecycle (sales pipeline records) |
| `documents` | Signed upload/download URLs for Supabase Storage |
| `pdf_extraction` | Async jobs that pull structured fields out of uploaded PDFs |
| `rpa` | Inbound webhook endpoint for UiPath automations |
| `workflow` | Task list endpoints |
| `linear` | Linear issue-tracker integration |
| `middleware` | Custom middleware (request ID tagging) |

## API Overview

| Method | Path | Auth |
|---|---|---|
| GET | `/health` | public |
| GET | `/me` | JWT |
| POST | `/auth/signup` \| `/login` \| `/logout` \| `/refresh` | public (Supabase proxy) |
| GET | `/tasks` | JWT |
| GET | `/opportunities` | JWT |
| POST/GET | `/documents/signed-upload-url` \| `/signed-download-url` | JWT |
| POST | `/webhooks/uipath` | HMAC signature |
| POST/GET | `/pdf-extraction/jobs/` \| `/jobs/<id>/` | JWT |

## Getting Started

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in Supabase + Redis credentials
python manage.py migrate
python manage.py runserver
```

Or with Docker:

```bash
docker build -t korra-backend .
docker run --env-file .env -p 8000:8000 korra-backend
```

## Project Docs

This repo tracks work against a shared cross-repo spec:

- `PROJECT_FLOW.md` — canonical schema, enums, and business-logic reference
- `PROGRESS.md` — cross-repo milestone/issue tracker (kept in sync with the frontend repo)
- `WORKFLOW.md` — branch/PR conventions
- Work is tracked in Linear (team **Korra**, key `KOR`); one PR per feature, reviewed by a human before merge.

## Status

Actively in development. See `PROGRESS.md` for the current milestone and what's next.
