-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.departments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  manager_user_id uuid,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT departments_pkey PRIMARY KEY (id),
  CONSTRAINT departments_manager_user_fk FOREIGN KEY (manager_user_id) REFERENCES auth.users(id)
);
CREATE TABLE public.user_profiles (
  user_id uuid NOT NULL,
  employee_code text NOT NULL UNIQUE,
  full_name text NOT NULL,
  department_id uuid,
  job_title text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_pkey PRIMARY KEY (user_id),
  CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT user_profiles_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id)
);
CREATE TABLE public.roles (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT roles_pkey PRIMARY KEY (id)
);
CREATE TABLE public.user_roles (
  user_id uuid NOT NULL,
  role_id uuid NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id),
  CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id)
);
CREATE TABLE public.contractors (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT contractors_pkey PRIMARY KEY (id)
);
CREATE TABLE public.owners (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT owners_pkey PRIMARY KEY (id)
);
CREATE TABLE public.consultants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT consultants_pkey PRIMARY KEY (id)
);
CREATE TABLE public.products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  family USER-DEFINED NOT NULL,
  chiller_condenser USER-DEFINED,
  chiller_compressor USER-DEFINED,
  name text,
  model_code text NOT NULL UNIQUE,
  capacity_kw numeric,
  capacity_tr numeric,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT products_pkey PRIMARY KEY (id)
);
CREATE TABLE public.projects (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  name text NOT NULL,
  contractor_id uuid,
  consultant_id uuid,
  owner_id uuid,
  sales_eng_id uuid NOT NULL,
  tech_off_eng_id uuid,
  current_offer_id uuid,
  current_submittal_id uuid,
  application USER-DEFINED NOT NULL,
  scope USER-DEFINED NOT NULL,
  status USER-DEFINED NOT NULL DEFAULT 'tenderingPhase'::project_status,
  product_id uuid,
  extracted_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  selection_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT projects_pkey PRIMARY KEY (id),
  CONSTRAINT projects_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT projects_contractor_id_fkey FOREIGN KEY (contractor_id) REFERENCES public.contractors(id),
  CONSTRAINT projects_consultant_id_fkey FOREIGN KEY (consultant_id) REFERENCES public.consultants(id),
  CONSTRAINT projects_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.owners(id),
  CONSTRAINT projects_sales_eng_id_fkey FOREIGN KEY (sales_eng_id) REFERENCES auth.users(id),
  CONSTRAINT projects_tech_off_eng_id_fkey FOREIGN KEY (tech_off_eng_id) REFERENCES auth.users(id),
  CONSTRAINT projects_current_offer_fk FOREIGN KEY (current_offer_id) REFERENCES public.documents(id),
  CONSTRAINT projects_current_submittal_fk FOREIGN KEY (current_submittal_id) REFERENCES public.documents(id)
);
CREATE TABLE public.documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  doc_type USER-DEFINED NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  bucket text NOT NULL DEFAULT 'documents'::text,
  path text NOT NULL,
  filename text NOT NULL,
  content_type text NOT NULL DEFAULT 'application/pdf'::text,
  created_by_user_id uuid NOT NULL,
  is_current boolean NOT NULL DEFAULT false,
  notes text,
  sha256 text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT documents_pkey PRIMARY KEY (id),
  CONSTRAINT documents_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id),
  CONSTRAINT documents_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id)
);
CREATE TABLE public.project_status_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  project_id uuid NOT NULL,
  from_status USER-DEFINED,
  to_status USER-DEFINED NOT NULL,
  changed_by_user_id uuid NOT NULL,
  changed_at timestamp with time zone NOT NULL DEFAULT now(),
  notes text,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  our_price numeric,
  competitor_name text,
  competitor_price numeric,
  win_reason USER-DEFINED,
  loss_reason USER-DEFINED,
  relationship_contact_name text,
  CONSTRAINT project_status_history_pkey PRIMARY KEY (id),
  CONSTRAINT project_status_history_changed_by_user_id_fkey FOREIGN KEY (changed_by_user_id) REFERENCES auth.users(id),
  CONSTRAINT project_status_history_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id)
);
