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

1. User fills: `email`, `password`, `full_name`, `job_title` on `/signup`.
2. Frontend calls `POST /auth/signup` → Django proxies to Supabase GoTrue.
3. Django passes `full_name` + `job_title` as metadata (`data` field) to GoTrue.
4. Supabase creates `auth.users` with metadata in `raw_user_meta_data`.
5. **PostgreSQL trigger** fires on INSERT → auto-creates `public.user_profiles`:
   - `user_id` = `auth.users.id`
   - `employee_code` = `EMP-` + first 6 chars of UUID uppercased (auto-generated)
   - `full_name` = from `raw_user_meta_data->>'full_name'`
   - `job_title` = from `raw_user_meta_data->>'job_title'` (cast to `job_title_level` enum)
   - `department_id` = NULL
   - `is_active` = true
6. Supabase sends confirmation email.
7. Frontend shows "Check your email" screen. No auto-redirect.

> **Admin assigns `department_id` and roles** after user confirms email.
> Until department is set, `GET /me` returns `department: null` → frontend shows `/pending`.

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
type JobTitleLevel =
  | "Junior Engineer" | "Senior Engineer" | "Lead Engineer"
  | "Section Head" | "Department Manager" | "General Manager"
  | "Director" | "Board Member";

interface UserProfile {
  user_id: string;
  employee_code: string;
  full_name: string;
  department: { id: string; name: DepartmentName } | null;
  roles: RoleCode[];
}

// email is read from the JWT token, not from /me
// job_title is stored in user_profiles but not returned by /me (not needed client-side)

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

## 6. Supabase SQL Setup (run once in Supabase SQL editor)

### Step 1 — Create `job_title_level` enum

```sql
CREATE TYPE public.job_title_level AS ENUM (
  'Junior Engineer',
  'Senior Engineer',
  'Lead Engineer',
  'Section Head',
  'Department Manager',
  'General Manager',
  'Director',
  'Board Member'
);
```

### Step 2 — Alter `user_profiles.job_title` to use enum

```sql
ALTER TABLE public.user_profiles
  ALTER COLUMN job_title TYPE public.job_title_level
  USING job_title::public.job_title_level;
```

### Step 3 — Create trigger to auto-create `user_profiles` on signup

```sql
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER AS $$
DECLARE
  jt_value text;
BEGIN
  jt_value := NEW.raw_user_meta_data->>'job_title';

  INSERT INTO public.user_profiles (user_id, employee_code, full_name, job_title, is_active)
  VALUES (
    NEW.id,
    'EMP-' || UPPER(SUBSTRING(NEW.id::text, 1, 6)),
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    CASE WHEN jt_value IS NOT NULL THEN jt_value::public.job_title_level ELSE NULL END,
    true
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();
```

> After signup, `department_id` and `user_roles` are assigned by admin.
> Until then `GET /me` returns `department: null` → frontend routes to `/pending`.

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
