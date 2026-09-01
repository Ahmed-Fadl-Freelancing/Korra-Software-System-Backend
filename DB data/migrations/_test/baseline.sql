-- Replica of the live Supabase schema, reconstructed from DB data/schema.sql + Enum.json,
-- plus the Supabase-provided objects the migrations depend on.
DO $r$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF; END $r$;
DO $r$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF; END $r$;
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), email text);
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
  $$ SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;

CREATE TYPE chiller_compressor_type  AS ENUM ('Centrifugal','Screw','Scroll','Reciprocating');
CREATE TYPE chiller_condenser_method AS ENUM ('AirCooled','WaterCooled');
CREATE TYPE document_type            AS ENUM ('offer','submittal','rfq');
CREATE TYPE loss_reason              AS ENUM ('price','technical','relationship','delivery_delay','response_delay','scope_changed','bad_experience');
CREATE TYPE product_family           AS ENUM ('Chiller','Pump','Generator');
CREATE TYPE project_application      AS ENUM ('Industrial','Commercial','Health','Residential');
CREATE TYPE project_scope            AS ENUM ('Supply','SupplyInstallation','Maintenance','Retrofit','Other');
CREATE TYPE project_status           AS ENUM ('won','lost','technicalApproval','onHold','withDifferentContractor','tenderingPhase','cancelled','finalNegotiation');
CREATE TYPE win_reason               AS ENUM ('price','technical','relationship','service','sole_source','bundled_deal');

CREATE TABLE public.departments (
  id uuid NOT NULL DEFAULT gen_random_uuid(), name text NOT NULL UNIQUE, manager_user_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT departments_pkey PRIMARY KEY (id),
  CONSTRAINT departments_manager_user_fk FOREIGN KEY (manager_user_id) REFERENCES auth.users(id));
CREATE TABLE public.user_profiles (
  user_id uuid NOT NULL, employee_code text NOT NULL UNIQUE, full_name text NOT NULL,
  department_id uuid, job_title text, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_pkey PRIMARY KEY (user_id),
  CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT user_profiles_department_id_fkey FOREIGN KEY (department_id) REFERENCES public.departments(id));
CREATE TABLE public.roles (
  id uuid NOT NULL DEFAULT gen_random_uuid(), code text NOT NULL UNIQUE, name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(), CONSTRAINT roles_pkey PRIMARY KEY (id));
CREATE TABLE public.user_roles (
  user_id uuid NOT NULL, role_id uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id),
  CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id),
  CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id));
CREATE TABLE public.contractors (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.owners (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.consultants (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());
CREATE TABLE public.products (
  id uuid NOT NULL DEFAULT gen_random_uuid(), family product_family NOT NULL,
  chiller_condenser chiller_condenser_method, chiller_compressor chiller_compressor_type,
  name text, model_code text NOT NULL UNIQUE, capacity_kw numeric, capacity_tr numeric,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb, is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT products_pkey PRIMARY KEY (id),
  -- live CHECK, absent from schema.sql, confirmed during earlier testing
  CONSTRAINT products_chiller_gate_check CHECK (
    family <> 'Chiller' OR (chiller_condenser IS NOT NULL AND chiller_compressor IS NOT NULL)));
CREATE TABLE public.projects (
  id uuid NOT NULL DEFAULT gen_random_uuid(), name text NOT NULL,
  contractor_id uuid, consultant_id uuid, owner_id uuid,
  sales_eng_id uuid NOT NULL, tech_off_eng_id uuid,
  current_offer_id uuid, current_submittal_id uuid,
  application project_application NOT NULL, scope project_scope NOT NULL,
  status project_status NOT NULL DEFAULT 'tenderingPhase', product_id uuid,
  extracted_data jsonb NOT NULL DEFAULT '{}'::jsonb, selection_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT projects_pkey PRIMARY KEY (id),
  CONSTRAINT projects_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(id),
  CONSTRAINT projects_contractor_id_fkey FOREIGN KEY (contractor_id) REFERENCES public.contractors(id),
  CONSTRAINT projects_consultant_id_fkey FOREIGN KEY (consultant_id) REFERENCES public.consultants(id),
  CONSTRAINT projects_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.owners(id),
  CONSTRAINT projects_sales_eng_id_fkey FOREIGN KEY (sales_eng_id) REFERENCES auth.users(id),
  CONSTRAINT projects_tech_off_eng_id_fkey FOREIGN KEY (tech_off_eng_id) REFERENCES auth.users(id));
CREATE TABLE public.documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(), project_id uuid NOT NULL,
  doc_type document_type NOT NULL, version integer NOT NULL CHECK (version > 0),
  bucket text NOT NULL DEFAULT 'documents', path text NOT NULL, filename text NOT NULL,
  content_type text NOT NULL DEFAULT 'application/pdf', created_by_user_id uuid NOT NULL,
  is_current boolean NOT NULL DEFAULT false, notes text, sha256 text,
  created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT documents_pkey PRIMARY KEY (id),
  CONSTRAINT documents_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id),
  CONSTRAINT documents_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES auth.users(id));
ALTER TABLE public.projects
  ADD CONSTRAINT projects_current_offer_fk FOREIGN KEY (current_offer_id) REFERENCES public.documents(id),
  ADD CONSTRAINT projects_current_submittal_fk FOREIGN KEY (current_submittal_id) REFERENCES public.documents(id);
CREATE TABLE public.project_status_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(), project_id uuid NOT NULL,
  from_status project_status, to_status project_status NOT NULL,
  changed_by_user_id uuid NOT NULL, changed_at timestamptz NOT NULL DEFAULT now(),
  notes text, meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  our_price numeric, competitor_name text, competitor_price numeric,
  win_reason win_reason, loss_reason loss_reason, relationship_contact_name text,
  CONSTRAINT project_status_history_pkey PRIMARY KEY (id),
  CONSTRAINT project_status_history_changed_by_user_id_fkey FOREIGN KEY (changed_by_user_id) REFERENCES auth.users(id),
  CONSTRAINT project_status_history_project_id_fkey FOREIGN KEY (project_id) REFERENCES public.projects(id));

-- The undocumented audit trigger on projects that demands SET LOCAL app.user_id.
-- Reproduced here from its observed behaviour so the roll-up is tested against it.
CREATE OR REPLACE FUNCTION public.projects_audit_status() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_actor uuid;
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    v_actor := nullif(current_setting('app.user_id', true), '')::uuid;
    IF v_actor IS NULL THEN
      RAISE EXCEPTION 'Missing app.user_id in DB session';
    END IF;
    INSERT INTO public.project_status_history (project_id, from_status, to_status, changed_by_user_id)
    VALUES (NEW.id, OLD.status, NEW.status, v_actor);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER projects_audit_status_trg AFTER UPDATE ON public.projects
  FOR EACH ROW EXECUTE FUNCTION public.projects_audit_status();
