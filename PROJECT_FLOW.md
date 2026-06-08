# Korra System — Project Flow (Canonical Reference)

> **This file is the authoritative spec.** Every milestone, PR, and type definition
> must comply with what's written here. If the schema or business logic changes,
> update this file first, then the code.
>
> Cross-repo: keep an identical copy in both repos.
>
> **⛔ NEVER MERGE PRs TO `main`:** One PR per feature branch. Wait for human review.
> All work: `feat/<Name>` branches (backend) or equivalent (frontend).

---

## 1. Database Canonical Values

These are the seeded string values used in the DB. Frontend types and backend
serialisers must match these exactly (case-sensitive).

### 1.1 Department names (`departments.name`)

| Value (exact) | Frontend route | Usage |
|---|---|---|
| `Sales` | `/app/sales` | Sales Engineers + their Manager |
| `Tech Office` | `/app/tech` | Tech Office Engineers + their Manager |

### 1.2 Role codes (`roles.code`)

| Value (exact) | Who has it | Permissions |
|---|---|---|
| `sales_engineer` | Sales dept users | Create/view own opportunities |
| `tech_engineer` | Tech Office users | View assigned opportunities, add tech data |
| `manager` | Manager of any dept | All data for their department + KPI widgets |
| `admin` | Super admin | Full access |

> A user can have **multiple roles** (e.g. `sales_engineer` + `manager`).

### 1.3 Project status (`project_status` enum)

| Value | Display label |
|---|---|
| `tenderingPhase` | Tendering |
| `technicalApproval` | Tech Approval |
| `finalNegotiation` | Final Negotiation |
| `won` | Won |
| `lost` | Lost |
| `onHold` | On Hold |
| `withDifferentContractor` | Different Contractor |
| `cancelled` | Cancelled |

### 1.4 Other enums (from `Enum.json`)

| Enum | Values |
|---|---|
| `product_family` | `Chiller`, `Pump`, `Generator` |
| `project_scope` | `Supply`, `SupplyInstallation`, `Maintenance`, `Retrofit`, `Other` |
| `project_application` | `Industrial`, `Commercial`, `Health`, `Residential` |
| `document_type` | `offer`, `submittal`, `rfq` |
| `chiller_compressor_type` | `Centrifugal`, `Screw`, `Scroll`, `Reciprocating` |
| `chiller_condenser_method` | `AirCooled`, `WaterCooled` |
| `win_reason` | `price`, `technical`, `relationship`, `service`, `sole_source`, `bundled_deal` |
| `loss_reason` | `price`, `technical`, `relationship`, `delivery_delay`, `response_delay`, `scope_changed`, `bad_experience` |

---

## 2. Authentication Flow

### 2.1 Signup

1. User fills: `email`, `password` on `/signup`.
2. Frontend calls `POST /auth/signup` → Django proxies to Supabase GoTrue.
3. Supabase creates `auth.users` record + sends confirmation email.
4. Backend: Admin (or trigger) must manually create `public.user_profiles` record with:
   - `user_id` = `auth.users.id`
   - `employee_code`, `full_name`, `job_title` = set by admin
   - `department_id` = NULL (assigned by admin after email confirm)
   - `is_active` = true
5. Frontend shows "Check your email" screen. No auto-redirect.

> **Admin assigns department and roles** after the user confirms email.
> Until department is set, `GET /me` returns `department: null` (pending activation).

### 2.2 Login

1. User fills: `email`, `password` on `/login`.
2. Frontend calls `POST /auth/login` → Django proxies to Supabase → returns `access_token` + `refresh_token`.
3. Frontend stores both in `localStorage` under `korra_access_token` / `korra_refresh_token`.
4. Frontend calls `GET /me` → Django returns full profile (see §2.4).
5. If `user.department === null` → redirect to `/pending`.
6. If `user.department.name === "Sales"` → redirect to `/app/sales`.
7. If `user.department.name === "Tech Office"` → redirect to `/app/tech`.

### 2.3 Token lifecycle

- All protected requests: `Authorization: Bearer <korra_access_token>`.
- On 401: frontend auto-calls `POST /auth/refresh` with `korra_refresh_token`.
- If refresh fails: clear tokens, redirect to `/login`.
- Logout: `POST /auth/logout` + clear localStorage.

### 2.4 `GET /me` — response contract

Backend must return this exact shape:

```json
{
  "user_id": "uuid",
  "employee_code": "EMP-ABC123",
  "full_name": "Ahmed Fadl",
  "department": {
    "id": "uuid",
    "name": "Sales"
  },
  "roles": ["sales_engineer"]
}
```

If department not yet assigned (pending activation):
```json
{
  "user_id": "uuid",
  "employee_code": "EMP-ABC123",
  "full_name": "Ahmed Fadl",
  "department": null,
  "roles": []
}
```

Frontend must also store the JWT `email` from the token itself (not from this endpoint).

---

## 3. Routing & Access Control

```
/login              — public
/signup             — public
/pending            — authenticated, department not yet assigned
/app/sales/*        — department === "Sales"
/app/tech/*         — department === "Tech Office"
```

`ProtectedRoute` checks (in order):
1. Not authenticated → `/login`
2. Authenticated + `department === null` → `/pending`
3. Wrong department for route → redirect to own department home
4. Missing role for section → redirect to department home

`isManager` = `roles.includes("manager")` — adds KPI widgets on top of normal role view.
Manager in Sales sees Sales data. Manager in Tech sees Tech data. No cross-department view unless `admin`.

---

## 4. Projects (called "Opportunities" in UI)

> DB table name is `projects`. The UI label is "Opportunities". Keep consistent in UI copy.

### 4.1 TypeScript types (canonical)

```typescript
type ProjectStatus =
  | "tenderingPhase" | "technicalApproval" | "finalNegotiation"
  | "won" | "lost" | "onHold" | "withDifferentContractor" | "cancelled";

type ProductFamily = "Chiller" | "Pump" | "Generator";
type ProjectScope = "Supply" | "SupplyInstallation" | "Maintenance" | "Retrofit" | "Other";
type ProjectApplication = "Industrial" | "Commercial" | "Health" | "Residential";
type DocumentType = "offer" | "submittal" | "rfq";
type RoleCode = "sales_engineer" | "tech_engineer" | "manager" | "admin";
type DepartmentName = "Sales" | "Tech Office";

interface UserProfile {
  user_id: string;
  email: string;
  employee_code: string;
  full_name: string;
  job_title: string | null;
  is_active: boolean;
  department: { id: string; name: DepartmentName } | null;
  roles: RoleCode[];
}

interface Project {
  id: string;
  name: string;
  contractor: { id: string; name: string } | null;
  consultant: { id: string; name: string } | null;
  owner: { id: string; name: string } | null;
  sales_engineer: { user_id: string; full_name: string };
  tech_engineer: { user_id: string; full_name: string } | null;
  application: ProjectApplication;
  scope: ProjectScope;
  status: ProjectStatus;
  product: { id: string; family: ProductFamily; model_code: string } | null;
  extracted_data: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}
```

### 4.2 Path A — PDF Extraction

1. Sales uploads PDF → `POST /documents/signed-upload-url` → upload to Supabase Storage.
2. Trigger `POST /pdf-extraction/` with `document_id`.
3. Poll `GET /pdf-extraction/{job_id}/` until `status === "done"`.
4. Show extracted fields + confidence scores for user to review/edit.
5. User confirms → `POST /opportunities` creates `projects` record with `status: tenderingPhase`.

### 4.3 Path B — Manual Entry

1. Sales fills: `name`, `contractor`, `owner`, `consultant`, `application`, `scope`, `product_family`.
2. Submit → `POST /opportunities` → initial `status: tenderingPhase`.

---

## 5. Role-Based Dashboard Content

### Sales Dashboard (`/app/sales`)

| Widget | Who sees it | Data source |
|---|---|---|
| KPI strip (my open opps, waiting on tech, offers ready, awarded) | all Sales | `GET /opportunities?sales_eng_id=me` |
| Manager KPI strip (pipeline value, win rate) | `isManager` only | `GET /analytics/summary` |
| Urgent Tasks | all Sales | `GET /tasks?assigned_to=me` |
| Recently Updated Opportunities | all Sales | `GET /opportunities?limit=4` |
| Linear Issues | all | direct Linear API |

### Tech Dashboard (`/app/tech`)

| Widget | Who sees it | Data source |
|---|---|---|
| Assigned opportunities | all Tech | `GET /opportunities?tech_eng_id=me` |
| Pending tech review | all Tech | `GET /opportunities?status=technicalApproval` |
| Manager KPI widgets | `isManager` only | `GET /analytics/summary` |

---

## 6. User Profile Creation (Admin responsibility)

When a user signs up via `/auth/signup`:
- Supabase creates `auth.users` record.
- Admin manually (or via backend API) creates `public.user_profiles` record with:
  - `user_id` = auth.users.id
  - `employee_code` = admin assigns (e.g., `EMP-ABC123`)
  - `full_name` = admin enters
  - `department_id` = NULL (set later)
  - `job_title` = NULL (set later)
  - `is_active` = true

**Optional:** Automate with Supabase trigger (SQL above) — but admin still assigns `employee_code`, `full_name`, `department_id` afterward.

---

## 7. Hard Rules — Never Do

**Both repos:**
- Never merge PRs to `main` (human approval required).
- Never push directly to `main` (use `feat/<Name>` branches).

**Frontend:**
- Never calls Supabase SDK directly (use `/auth/*` endpoints instead).
- Never reads JWT claims for role/department — always uses `GET /me` response.
- Never hardcodes department names or role codes as raw strings in components
  — always import `DepartmentName` / `RoleCode` from `@/types`.
- Never processes PDFs.

**Backend:**
- Never mint/sign JWTs (Supabase Auth issues them; `/auth/*` only relays).
- Never hardcode secrets — always via `django-environ` + `.env`.
