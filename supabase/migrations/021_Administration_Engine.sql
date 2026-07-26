-- ============================================================
-- SalesSetu Enterprise
-- Migration 021: Administration Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   012_assignment_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--   020_Finance_Commission_Engine.sql
--
-- Scope:
--   • Tenant and organization administration
--   • Branches, departments, teams, designations and employees
--   • Business hours, holidays, shifts and availability
--   • SLA policies and approval matrices
--   • Branding, domains and tenant preferences
--   • Feature flags, licenses and subscription limits
--   • API credentials registry and integration settings
--   • Maintenance mode and system preferences
--   • Admin event outbox, analytics, logs and health checks
--   • RLS, permissions, grants and final validation
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ============================================================
-- 1. RBAC PERMISSIONS
-- ============================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
select
  p.module,
  p.action,
  p.code,
  p.description
from (
  values
    ('administration','view','administration.view','View administration settings'),
    ('administration','view_all','administration.view_all','View all tenant administration data'),
    ('administration','manage_org','administration.manage_org','Manage organization profile'),
    ('administration','manage_branches','administration.manage_branches','Manage branches'),
    ('administration','manage_departments','administration.manage_departments','Manage departments'),
    ('administration','manage_teams','administration.manage_teams','Manage teams'),
    ('administration','manage_designations','administration.manage_designations','Manage designations'),
    ('administration','manage_employees','administration.manage_employees','Manage employees'),
    ('administration','manage_calendar','administration.manage_calendar','Manage business hours and holidays'),
    ('administration','manage_shifts','administration.manage_shifts','Manage shifts'),
    ('administration','manage_sla','administration.manage_sla','Manage SLA policies'),
    ('administration','manage_approvals','administration.manage_approvals','Manage approval matrices'),
    ('administration','manage_branding','administration.manage_branding','Manage organization branding'),
    ('administration','manage_domains','administration.manage_domains','Manage domains'),
    ('administration','manage_features','administration.manage_features','Manage feature flags'),
    ('administration','manage_limits','administration.manage_limits','Manage tenant limits'),
    ('administration','manage_integrations','administration.manage_integrations','Manage integration configuration'),
    ('administration','manage_api_keys','administration.manage_api_keys','Manage API credentials registry'),
    ('administration','manage_maintenance','administration.manage_maintenance','Manage maintenance mode'),
    ('administration','view_logs','administration.view_logs','View administration logs'),
    ('administration','view_analytics','administration.view_analytics','View administration analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. ORGANIZATION ADMIN PROFILE
-- ============================================================

create table if not exists public.admin_organization_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  legal_name text,
  trade_name text,
  short_name text,

  organization_code text,
  industry text,
  sub_industry text,

  registration_number text,
  gstin text,
  pan text,
  cin text,

  primary_email text,
  primary_phone text,
  website_url text,

  headquarters_address jsonb not null default '{}',
  billing_address jsonb not null default '{}',

  timezone text not null default 'Asia/Kolkata',
  locale text not null default 'en-IN',
  default_currency text not null default 'INR',
  default_country_code text not null default 'IN',

  fiscal_year_start_month integer not null default 4
    check (fiscal_year_start_month between 1 and 12),

  status text not null default 'active'
    check (status in ('active','inactive','suspended','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id)
);

-- ============================================================
-- 3. BRANCHES
-- ============================================================

create table if not exists public.admin_branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  branch_code text not null,
  branch_name text not null,
  branch_type text not null default 'office'
    check (branch_type in ('head_office','office','sales_office','site_office','remote','virtual','other')),

  parent_branch_id uuid references public.admin_branches(id) on delete set null,

  email text,
  phone text,

  address jsonb not null default '{}',

  latitude numeric(10,7),
  longitude numeric(10,7),

  timezone text not null default 'Asia/Kolkata',

  manager_user_id uuid references auth.users(id) on delete set null,

  status text not null default 'active'
    check (status in ('active','inactive','closed','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,branch_code)
);

create index if not exists admin_branches_org_status_idx
  on public.admin_branches (organization_id,status);

-- ============================================================
-- 4. DEPARTMENTS
-- ============================================================

create table if not exists public.admin_departments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.admin_branches(id) on delete set null,
  parent_department_id uuid references public.admin_departments(id) on delete set null,

  department_code text not null,
  department_name text not null,
  description text,

  head_user_id uuid references auth.users(id) on delete set null,

  cost_center_code text,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,department_code)
);

-- ============================================================
-- 5. TEAMS
-- ============================================================

create table if not exists public.admin_teams (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.admin_branches(id) on delete set null,
  department_id uuid references public.admin_departments(id) on delete set null,
  parent_team_id uuid references public.admin_teams(id) on delete set null,

  team_code text not null,
  team_name text not null,
  team_type text not null default 'functional'
    check (team_type in ('functional','sales','support','operations','project','temporary','other')),

  leader_user_id uuid references auth.users(id) on delete set null,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,team_code)
);

-- ============================================================
-- 6. DESIGNATIONS
-- ============================================================

create table if not exists public.admin_designations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  designation_code text not null,
  designation_name text not null,
  description text,

  grade text,
  level_number integer,

  managerial boolean not null default false,
  sales_role boolean not null default false,
  support_role boolean not null default false,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,designation_code)
);

-- ============================================================
-- 7. EMPLOYEE RECORDS
-- ============================================================

create table if not exists public.admin_employees (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,

  employee_code text not null,
  full_name text not null,

  work_email text,
  personal_email text,
  phone text,

  branch_id uuid references public.admin_branches(id) on delete set null,
  department_id uuid references public.admin_departments(id) on delete set null,
  team_id uuid references public.admin_teams(id) on delete set null,
  designation_id uuid references public.admin_designations(id) on delete set null,

  manager_employee_id uuid references public.admin_employees(id) on delete set null,

  employment_type text not null default 'full_time'
    check (employment_type in ('full_time','part_time','contract','consultant','intern','temporary')),

  employment_status text not null default 'active'
    check (employment_status in ('active','probation','notice','inactive','terminated','resigned','retired')),

  date_of_joining date,
  date_of_exit date,

  timezone text not null default 'Asia/Kolkata',
  locale text not null default 'en-IN',

  sales_capacity integer not null default 0,
  daily_lead_capacity integer not null default 0,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,employee_code)
);

create index if not exists admin_employees_org_status_idx
  on public.admin_employees (organization_id,employment_status);

-- ============================================================
-- 8. TEAM MEMBERSHIPS
-- ============================================================

create table if not exists public.admin_team_memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  team_id uuid not null references public.admin_teams(id) on delete cascade,
  employee_id uuid not null references public.admin_employees(id) on delete cascade,

  membership_role text not null default 'member'
    check (membership_role in ('member','lead','manager','observer')),

  is_primary boolean not null default false,

  effective_from date not null default current_date,
  effective_to date,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (team_id,employee_id,effective_from)
);

-- ============================================================
-- 9. BUSINESS HOURS
-- ============================================================

create table if not exists public.admin_business_hours (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.admin_branches(id) on delete cascade,

  day_of_week integer not null check (day_of_week between 0 and 6),
  is_working_day boolean not null default true,

  start_time time,
  end_time time,
  break_start time,
  break_end time,

  timezone text not null default 'Asia/Kolkata',

  status text not null default 'active'
    check (status in ('active','inactive')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,branch_id,day_of_week)
);

-- ============================================================
-- 10. HOLIDAYS
-- ============================================================

create table if not exists public.admin_holidays (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid references public.admin_branches(id) on delete cascade,

  holiday_name text not null,
  holiday_date date not null,
  holiday_type text not null default 'public'
    check (holiday_type in ('public','company','regional','optional','restricted')),

  is_full_day boolean not null default true,
  start_time time,
  end_time time,

  status text not null default 'active'
    check (status in ('active','cancelled','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  unique (organization_id,branch_id,holiday_date,holiday_name)
);

-- ============================================================
-- 11. SHIFTS
-- ============================================================

create table if not exists public.admin_shifts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  shift_code text not null,
  shift_name text not null,

  start_time time not null,
  end_time time not null,
  timezone text not null default 'Asia/Kolkata',

  working_days integer[] not null default array[1,2,3,4,5,6],

  grace_minutes integer not null default 0,
  break_minutes integer not null default 0,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,shift_code)
);

create table if not exists public.admin_employee_shifts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid not null references public.admin_employees(id) on delete cascade,
  shift_id uuid not null references public.admin_shifts(id) on delete cascade,

  effective_from date not null,
  effective_to date,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (employee_id,shift_id,effective_from)
);

-- ============================================================
-- 12. SLA POLICIES
-- ============================================================

create table if not exists public.admin_sla_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  policy_code text not null,
  policy_name text not null,
  description text,

  module_code text not null,
  entity_type text,

  priority text,
  response_minutes integer,
  resolution_minutes integer,

  business_hours_only boolean not null default true,
  pause_on_waiting_customer boolean not null default true,

  escalation_enabled boolean not null default true,
  escalation_config jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,policy_code)
);

-- ============================================================
-- 13. APPROVAL MATRICES
-- ============================================================

create table if not exists public.admin_approval_matrices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  matrix_code text not null,
  matrix_name text not null,
  description text,

  module_code text not null,
  entity_type text not null,
  action_code text not null,

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,matrix_code)
);

create table if not exists public.admin_approval_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  approval_matrix_id uuid not null references public.admin_approval_matrices(id) on delete cascade,

  step_order integer not null,
  step_name text not null,

  approver_type text not null
    check (approver_type in ('user','role','designation','manager','team','department_head','custom')),

  approver_user_id uuid references auth.users(id) on delete set null,
  approver_team_id uuid references public.admin_teams(id) on delete set null,
  approver_designation_id uuid references public.admin_designations(id) on delete set null,

  minimum_approvals integer not null default 1,
  allow_self_approval boolean not null default false,

  conditions jsonb not null default '{}',
  timeout_minutes integer,
  escalation_config jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (approval_matrix_id,step_order)
);

-- ============================================================
-- 14. BRANDING
-- ============================================================

create table if not exists public.admin_branding_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  brand_name text,
  logo_url text,
  logo_dark_url text,
  favicon_url text,

  primary_color text,
  secondary_color text,
  accent_color text,
  background_color text,
  text_color text,

  font_family text,
  email_header_url text,
  email_footer_html text,

  login_page_config jsonb not null default '{}',
  portal_config jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id)
);

-- ============================================================
-- 15. DOMAINS
-- ============================================================

create table if not exists public.admin_domains (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  domain_type text not null
    check (domain_type in ('primary','portal','landing','email','api','automation','custom')),

  domain_name text not null,
  subdomain text,

  verification_status text not null default 'pending'
    check (verification_status in ('pending','verified','failed','expired')),

  verification_token text,
  verified_at timestamptz,

  ssl_status text not null default 'pending'
    check (ssl_status in ('pending','active','failed','expired')),

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,domain_name)
);

-- ============================================================
-- 16. FEATURE FLAGS
-- ============================================================

create table if not exists public.admin_feature_flags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  feature_code text not null,
  feature_name text not null,
  description text,

  enabled boolean not null default false,

  rollout_percentage numeric(8,4) not null default 100
    check (rollout_percentage between 0 and 100),

  targeting_rules jsonb not null default '{}',
  configuration jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  is_system_feature boolean not null default false,

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,feature_code)
);

create unique index if not exists admin_feature_flags_system_unique_idx
  on public.admin_feature_flags(feature_code)
  where organization_id is null;

-- ============================================================
-- 17. LICENSES AND TENANT LIMITS
-- ============================================================

create table if not exists public.admin_licenses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  license_code text not null,
  plan_code text not null,
  plan_name text not null,

  status text not null default 'trial'
    check (status in ('trial','active','grace','suspended','expired','cancelled')),

  starts_at timestamptz not null default now(),
  trial_ends_at timestamptz,
  renews_at timestamptz,
  expires_at timestamptz,
  cancelled_at timestamptz,

  billing_cycle text default 'monthly'
    check (billing_cycle in ('monthly','quarterly','annual','custom')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,license_code)
);

create table if not exists public.admin_tenant_limits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  limit_code text not null,
  limit_name text not null,

  limit_value numeric,
  current_usage numeric not null default 0,

  period_type text not null default 'lifetime'
    check (period_type in ('daily','weekly','monthly','annual','lifetime')),

  hard_limit boolean not null default true,
  warning_threshold_percentage numeric(8,4) not null default 80,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  updated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  unique (organization_id,limit_code)
);

-- ============================================================
-- 18. API CREDENTIAL REGISTRY
-- ============================================================

create table if not exists public.admin_api_credentials (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  credential_code text not null,
  credential_name text not null,

  provider text not null,
  credential_type text not null
    check (credential_type in ('api_key','oauth','basic','bearer','service_account','webhook_secret','custom')),

  environment text not null default 'production'
    check (environment in ('development','staging','production')),

  secret_reference text,
  public_identifier text,

  scopes text[] not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','expired','revoked','error')),

  expires_at timestamptz,
  last_used_at timestamptz,
  last_rotated_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,credential_code)
);

-- ============================================================
-- 19. INTEGRATION SETTINGS
-- ============================================================

create table if not exists public.admin_integration_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  integration_code text not null,
  integration_name text not null,
  provider text not null,

  integration_type text not null
    check (integration_type in ('communication','automation','payments','storage','analytics','ai','crm','webhook','custom')),

  credential_id uuid references public.admin_api_credentials(id) on delete set null,

  enabled boolean not null default false,
  configuration jsonb not null default '{}',

  health_status text not null default 'unknown'
    check (health_status in ('unknown','healthy','degraded','unhealthy','disabled')),

  last_health_check_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_error text,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,integration_code)
);

-- ============================================================
-- 20. SYSTEM PREFERENCES
-- ============================================================

create table if not exists public.admin_system_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  preference_group text not null,
  preference_key text not null,
  preference_value jsonb not null default '{}',

  is_sensitive boolean not null default false,
  editable_by_tenant boolean not null default true,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,preference_group,preference_key)
);

-- ============================================================
-- 21. MAINTENANCE MODE
-- ============================================================

create table if not exists public.admin_maintenance_windows (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  maintenance_code text not null,
  title text not null,
  description text,

  scope text not null default 'organization'
    check (scope in ('global','organization','module','feature')),

  module_code text,
  feature_code text,

  status text not null default 'scheduled'
    check (status in ('scheduled','active','completed','cancelled')),

  starts_at timestamptz not null,
  ends_at timestamptz,

  allow_admin_access boolean not null default true,
  allow_read_only_access boolean not null default false,

  message_title text,
  message_body text,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,maintenance_code)
);

-- ============================================================
-- 22. EVENT OUTBOX AND LOGS
-- ============================================================

create table if not exists public.admin_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  event_name text not null,
  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'automation_engine',
        'workflow_engine',
        'notification_engine',
        'communication_engine',
        'n8n',
        'analytics',
        'audit'
      )
    ),

  source_type text,
  source_id uuid,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'processing',
        'delivered',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,
  idempotency_key text,
  correlation_id text,
  trace_id text,

  payload jsonb not null default '{}',
  available_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  delivery_attempts integer not null default 0,
  maximum_attempts integer not null default 10,

  delivered_at timestamptz,

  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists admin_event_outbox_idempotency_idx
  on public.admin_event_outbox (organization_id,idempotency_key)
  where idempotency_key is not null;

create index if not exists admin_event_outbox_queue_idx
  on public.admin_event_outbox (status,available_at,priority,created_at)
  where status in ('pending','failed');

create table if not exists public.admin_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  log_level text not null default 'info'
    check (log_level in ('debug','info','warning','error','critical')),

  event_name text,
  message text,

  source_type text,
  source_id uuid,

  error_code text,
  error_message text,
  log_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now()
);

create index if not exists admin_logs_org_created_idx
  on public.admin_logs (organization_id,created_at desc);

-- ============================================================
-- 23. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'admin_organization_profiles',
    'admin_branches',
    'admin_departments',
    'admin_teams',
    'admin_designations',
    'admin_employees',
    'admin_team_memberships',
    'admin_business_hours',
    'admin_shifts',
    'admin_employee_shifts',
    'admin_sla_policies',
    'admin_approval_matrices',
    'admin_branding_profiles',
    'admin_domains',
    'admin_feature_flags',
    'admin_licenses',
    'admin_tenant_limits',
    'admin_api_credentials',
    'admin_integration_settings',
    'admin_system_preferences',
    'admin_maintenance_windows',
    'admin_event_outbox'
  ]
  loop
    execute format(
      'drop trigger if exists %I_set_updated_at on public.%I',
      target_table,target_table
    );

    execute format(
      'create trigger %I_set_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      target_table,target_table
    );
  end loop;
end;
$$;

-- ============================================================
-- 24. CREATE BRANCH
-- ============================================================

create or replace function public.create_admin_branch(
  requested_organization_id uuid,
  requested_branch_code text,
  requested_branch_name text,
  requested_branch_type text default 'office',
  requested_parent_branch_id uuid default null,
  requested_email text default null,
  requested_phone text default null,
  requested_address jsonb default '{}'::jsonb,
  requested_timezone text default 'Asia/Kolkata',
  requested_manager_user_id uuid default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.admin_branches
language plpgsql
security definer
set search_path = ''
as $$
declare
  branch_record public.admin_branches;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'administration.manage_branches'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.admin_branches (
    organization_id,
    branch_code,
    branch_name,
    branch_type,
    parent_branch_id,
    email,
    phone,
    address,
    timezone,
    manager_user_id,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    requested_branch_code,
    requested_branch_name,
    requested_branch_type,
    requested_parent_branch_id,
    requested_email,
    requested_phone,
    coalesce(requested_address,'{}'::jsonb),
    requested_timezone,
    requested_manager_user_id,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  on conflict (organization_id,branch_code)
  do update set
    branch_name = excluded.branch_name,
    branch_type = excluded.branch_type,
    parent_branch_id = excluded.parent_branch_id,
    email = excluded.email,
    phone = excluded.phone,
    address = excluded.address,
    timezone = excluded.timezone,
    manager_user_id = excluded.manager_user_id,
    updated_by = auth.uid(),
    updated_at = now()
  returning * into branch_record;

  return branch_record;
end;
$$;

revoke all
on function public.create_admin_branch(
  uuid,text,text,text,uuid,text,text,jsonb,text,uuid,jsonb
)
from public;

grant execute
on function public.create_admin_branch(
  uuid,text,text,text,uuid,text,text,jsonb,text,uuid,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 25. CREATE EMPLOYEE
-- ============================================================

create or replace function public.create_admin_employee(
  requested_organization_id uuid,
  requested_employee_code text,
  requested_full_name text,
  requested_user_id uuid default null,
  requested_work_email text default null,
  requested_phone text default null,
  requested_branch_id uuid default null,
  requested_department_id uuid default null,
  requested_team_id uuid default null,
  requested_designation_id uuid default null,
  requested_manager_employee_id uuid default null,
  requested_employment_type text default 'full_time',
  requested_date_of_joining date default current_date,
  requested_daily_lead_capacity integer default 0,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.admin_employees
language plpgsql
security definer
set search_path = ''
as $$
declare
  employee_record public.admin_employees;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'administration.manage_employees'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.admin_employees (
    organization_id,
    user_id,
    employee_code,
    full_name,
    work_email,
    phone,
    branch_id,
    department_id,
    team_id,
    designation_id,
    manager_employee_id,
    employment_type,
    employment_status,
    date_of_joining,
    daily_lead_capacity,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    requested_user_id,
    requested_employee_code,
    requested_full_name,
    requested_work_email,
    requested_phone,
    requested_branch_id,
    requested_department_id,
    requested_team_id,
    requested_designation_id,
    requested_manager_employee_id,
    requested_employment_type,
    'active',
    requested_date_of_joining,
    requested_daily_lead_capacity,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  on conflict (organization_id,employee_code)
  do update set
    user_id = coalesce(excluded.user_id,admin_employees.user_id),
    full_name = excluded.full_name,
    work_email = excluded.work_email,
    phone = excluded.phone,
    branch_id = excluded.branch_id,
    department_id = excluded.department_id,
    team_id = excluded.team_id,
    designation_id = excluded.designation_id,
    manager_employee_id = excluded.manager_employee_id,
    employment_type = excluded.employment_type,
    daily_lead_capacity = excluded.daily_lead_capacity,
    updated_by = auth.uid(),
    updated_at = now()
  returning * into employee_record;

  return employee_record;
end;
$$;

revoke all
on function public.create_admin_employee(
  uuid,text,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,text,date,integer,jsonb
)
from public;

grant execute
on function public.create_admin_employee(
  uuid,text,text,uuid,text,text,uuid,uuid,uuid,uuid,uuid,text,date,integer,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 26. CHECK BUSINESS TIME
-- ============================================================

create or replace function public.is_admin_business_time(
  requested_organization_id uuid,
  requested_branch_id uuid default null,
  requested_timestamp timestamptz default now()
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  local_timestamp timestamp;
  local_date date;
  local_time time;
  local_dow integer;
  timezone_value text;
  hours_record public.admin_business_hours;
begin
  select coalesce(
    (
      select b.timezone
      from public.admin_branches b
      where b.id = requested_branch_id
    ),
    (
      select p.timezone
      from public.admin_organization_profiles p
      where p.organization_id = requested_organization_id
    ),
    'Asia/Kolkata'
  )
  into timezone_value;

  local_timestamp := requested_timestamp at time zone timezone_value;
  local_date := local_timestamp::date;
  local_time := local_timestamp::time;
  local_dow := extract(dow from local_timestamp)::integer;

  if exists (
    select 1
    from public.admin_holidays h
    where h.organization_id = requested_organization_id
      and (h.branch_id is null or h.branch_id = requested_branch_id)
      and h.holiday_date = local_date
      and h.status = 'active'
      and h.is_full_day = true
  ) then
    return false;
  end if;

  select *
  into hours_record
  from public.admin_business_hours h
  where h.organization_id = requested_organization_id
    and h.branch_id is not distinct from requested_branch_id
    and h.day_of_week = local_dow
    and h.status = 'active';

  if not found then
    select *
    into hours_record
    from public.admin_business_hours h
    where h.organization_id = requested_organization_id
      and h.branch_id is null
      and h.day_of_week = local_dow
      and h.status = 'active';
  end if;

  if not found or not hours_record.is_working_day then
    return false;
  end if;

  return local_time between hours_record.start_time and hours_record.end_time;
end;
$$;

revoke all
on function public.is_admin_business_time(uuid,uuid,timestamptz)
from public;

grant execute
on function public.is_admin_business_time(uuid,uuid,timestamptz)
to authenticated,service_role;

-- ============================================================
-- 27. FEATURE FLAG EVALUATION
-- ============================================================

create or replace function public.is_admin_feature_enabled(
  requested_organization_id uuid,
  requested_feature_code text,
  requested_context jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  feature_record public.admin_feature_flags;
  hash_value integer;
begin
  select *
  into feature_record
  from public.admin_feature_flags f
  where f.feature_code = requested_feature_code
    and f.status = 'active'
    and (
      f.organization_id = requested_organization_id
      or f.organization_id is null
    )
  order by
    case when f.organization_id = requested_organization_id then 0 else 1 end
  limit 1;

  if not found or not feature_record.enabled then
    return false;
  end if;

  if feature_record.rollout_percentage >= 100 then
    return true;
  end if;

  hash_value := abs(
    hashtext(
      requested_organization_id::text
      || ':'
      || requested_feature_code
      || ':'
      || coalesce(requested_context->>'subject_id','default')
    )
  ) % 100;

  return hash_value < feature_record.rollout_percentage;
end;
$$;

revoke all
on function public.is_admin_feature_enabled(uuid,text,jsonb)
from public;

grant execute
on function public.is_admin_feature_enabled(uuid,text,jsonb)
to authenticated,service_role;

-- ============================================================
-- 28. LIMIT USAGE
-- ============================================================

create or replace function public.increment_admin_tenant_usage(
  requested_organization_id uuid,
  requested_limit_code text,
  requested_increment numeric default 1
)
returns public.admin_tenant_limits
language plpgsql
security definer
set search_path = ''
as $$
declare
  limit_record public.admin_tenant_limits;
begin
  select *
  into limit_record
  from public.admin_tenant_limits
  where organization_id = requested_organization_id
    and limit_code = requested_limit_code
    and status = 'active'
  for update;

  if not found then
    raise exception 'Tenant limit not found';
  end if;

  if limit_record.hard_limit
    and limit_record.limit_value is not null
    and limit_record.current_usage + requested_increment > limit_record.limit_value then
    raise exception 'Tenant limit exceeded';
  end if;

  update public.admin_tenant_limits
  set
    current_usage = current_usage + requested_increment,
    updated_at = now()
  where id = limit_record.id
  returning * into limit_record;

  return limit_record;
end;
$$;

revoke all
on function public.increment_admin_tenant_usage(uuid,text,numeric)
from public;

grant execute
on function public.increment_admin_tenant_usage(uuid,text,numeric)
to authenticated,service_role;

-- ============================================================
-- 29. MAINTENANCE MODE CHECK
-- ============================================================

create or replace function public.get_admin_maintenance_status(
  requested_organization_id uuid default null,
  requested_module_code text default null,
  requested_feature_code text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  maintenance_record public.admin_maintenance_windows;
begin
  select *
  into maintenance_record
  from public.admin_maintenance_windows m
  where m.status = 'active'
    and m.starts_at <= now()
    and (m.ends_at is null or m.ends_at > now())
    and (
      m.scope = 'global'
      or (
        m.scope = 'organization'
        and m.organization_id = requested_organization_id
      )
      or (
        m.scope = 'module'
        and m.organization_id = requested_organization_id
        and m.module_code = requested_module_code
      )
      or (
        m.scope = 'feature'
        and m.organization_id = requested_organization_id
        and m.feature_code = requested_feature_code
      )
    )
  order by
    case m.scope
      when 'feature' then 1
      when 'module' then 2
      when 'organization' then 3
      else 4
    end
  limit 1;

  if not found then
    return jsonb_build_object(
      'maintenance',false
    );
  end if;

  return jsonb_build_object(
    'maintenance',true,
    'scope',maintenance_record.scope,
    'title',maintenance_record.message_title,
    'message',maintenance_record.message_body,
    'allow_admin_access',maintenance_record.allow_admin_access,
    'allow_read_only_access',maintenance_record.allow_read_only_access,
    'starts_at',maintenance_record.starts_at,
    'ends_at',maintenance_record.ends_at
  );
end;
$$;

revoke all
on function public.get_admin_maintenance_status(uuid,text,text)
from public;

grant execute
on function public.get_admin_maintenance_status(uuid,text,text)
to anon,authenticated,service_role;

-- ============================================================
-- 30. PUBLISH ADMIN EVENT
-- ============================================================

create or replace function public.publish_admin_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_source_type text default null,
  requested_source_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.admin_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.admin_event_outbox;
  created_event public.admin_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.admin_event_outbox e
    where e.organization_id is not distinct from requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.admin_event_outbox (
    organization_id,
    event_name,
    destination,
    source_type,
    source_id,
    status,
    priority,
    idempotency_key,
    correlation_id,
    trace_id,
    payload,
    available_at
  )
  values (
    requested_organization_id,
    requested_event_name,
    requested_destination,
    requested_source_type,
    requested_source_id,
    'pending',
    requested_priority,
    requested_idempotency_key,
    requested_correlation_id,
    requested_trace_id,
    coalesce(requested_payload,'{}'::jsonb),
    coalesce(requested_available_at,now())
  )
  returning * into created_event;

  return created_event;
end;
$$;

revoke all
on function public.publish_admin_event(
  uuid,text,jsonb,text,text,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_admin_event(
  uuid,text,jsonb,text,text,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 31. FEATURE FLAG EVENT TRIGGER
-- ============================================================

create or replace function public.emit_admin_feature_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and new.enabled is not distinct from old.enabled
    and new.configuration is not distinct from old.configuration then
    return new;
  end if;

  perform public.publish_admin_event(
    new.organization_id,
    'administration.feature.changed',
    jsonb_build_object(
      'feature_id',new.id,
      'feature_code',new.feature_code,
      'enabled',new.enabled,
      'rollout_percentage',new.rollout_percentage,
      'configuration',new.configuration
    ),
    'automation_engine',
    'feature_flag',
    new.id,
    50,
    'admin-feature:' || new.id::text || ':' || new.updated_at::text,
    new.id::text,
    null,
    now()
  );

  return new;
end;
$$;

drop trigger if exists admin_feature_flags_emit_events
on public.admin_feature_flags;

create trigger admin_feature_flags_emit_events
after insert or update
on public.admin_feature_flags
for each row
execute function public.emit_admin_feature_events();

-- ============================================================
-- 32. ANALYTICS VIEWS
-- ============================================================

create or replace view public.admin_organization_dashboard
with (security_invoker = true)
as
select
  o.id as organization_id,

  (select count(*) from public.admin_branches b
   where b.organization_id = o.id and b.status = 'active') as active_branches,

  (select count(*) from public.admin_departments d
   where d.organization_id = o.id and d.status = 'active') as active_departments,

  (select count(*) from public.admin_teams t
   where t.organization_id = o.id and t.status = 'active') as active_teams,

  (select count(*) from public.admin_employees e
   where e.organization_id = o.id and e.employment_status = 'active') as active_employees,

  (select count(*) from public.admin_integration_settings i
   where i.organization_id = o.id and i.enabled = true) as enabled_integrations,

  (select count(*) from public.admin_feature_flags f
   where f.organization_id = o.id and f.enabled = true and f.status = 'active') as enabled_features,

  (select count(*) from public.admin_domains d
   where d.organization_id = o.id and d.verification_status = 'verified') as verified_domains,

  (select count(*) from public.admin_maintenance_windows m
   where m.organization_id = o.id and m.status = 'active') as active_maintenance_windows,

  now() as refreshed_at

from public.organizations o;

create or replace view public.admin_employee_dashboard
with (security_invoker = true)
as
select
  e.organization_id,
  e.branch_id,
  e.department_id,
  e.team_id,
  e.designation_id,
  e.employment_status,

  count(*) as employee_count,

  count(*) filter (
    where e.user_id is not null
  ) as linked_user_count,

  coalesce(sum(e.daily_lead_capacity),0) as total_daily_lead_capacity,

  min(e.date_of_joining) as earliest_joining_date,
  max(e.date_of_joining) as latest_joining_date

from public.admin_employees e
group by
  e.organization_id,
  e.branch_id,
  e.department_id,
  e.team_id,
  e.designation_id,
  e.employment_status;

create or replace view public.admin_license_usage_dashboard
with (security_invoker = true)
as
select
  l.organization_id,
  l.license_code,
  l.plan_code,
  l.plan_name,
  l.status as license_status,
  l.starts_at,
  l.trial_ends_at,
  l.renews_at,
  l.expires_at,

  count(t.id) as configured_limits,

  count(t.id) filter (
    where t.limit_value is not null
      and t.current_usage >= t.limit_value
  ) as exceeded_limits,

  count(t.id) filter (
    where t.limit_value is not null
      and t.current_usage >= (
        t.limit_value * t.warning_threshold_percentage / 100
      )
  ) as warning_limits

from public.admin_licenses l
left join public.admin_tenant_limits t
  on t.organization_id = l.organization_id
group by l.id;

create or replace view public.admin_integration_health_dashboard
with (security_invoker = true)
as
select
  organization_id,
  integration_type,
  provider,
  health_status,

  count(*) as integration_count,

  count(*) filter (
    where enabled = true
  ) as enabled_count,

  max(last_success_at) as latest_success_at,
  max(last_failure_at) as latest_failure_at

from public.admin_integration_settings
group by organization_id,integration_type,provider,health_status;

grant select
on
  public.admin_organization_dashboard,
  public.admin_employee_dashboard,
  public.admin_license_usage_dashboard,
  public.admin_integration_health_dashboard
to authenticated,service_role;

-- ============================================================
-- 33. HEALTH CHECK
-- ============================================================

create or replace function public.get_administration_engine_health(
  requested_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role'
    and (
      requested_organization_id is null
      or not public.has_organization_permission(
        requested_organization_id,
        'administration.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'active_branches',(
      select count(*)
      from public.admin_branches b
      where b.status = 'active'
        and (
          requested_organization_id is null
          or b.organization_id = requested_organization_id
        )
    ),

    'active_employees',(
      select count(*)
      from public.admin_employees e
      where e.employment_status = 'active'
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    ),

    'unhealthy_integrations',(
      select count(*)
      from public.admin_integration_settings i
      where i.enabled = true
        and i.health_status in ('degraded','unhealthy')
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'expired_credentials',(
      select count(*)
      from public.admin_api_credentials c
      where c.status = 'expired'
        or (c.expires_at is not null and c.expires_at <= now())
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'tenant_limit_warnings',(
      select count(*)
      from public.admin_tenant_limits t
      where t.status = 'active'
        and t.limit_value is not null
        and t.current_usage >= (
          t.limit_value * t.warning_threshold_percentage / 100
        )
        and (
          requested_organization_id is null
          or t.organization_id = requested_organization_id
        )
    ),

    'active_maintenance_windows',(
      select count(*)
      from public.admin_maintenance_windows m
      where m.status = 'active'
        and m.starts_at <= now()
        and (m.ends_at is null or m.ends_at > now())
        and (
          requested_organization_id is null
          or m.organization_id = requested_organization_id
          or m.organization_id is null
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.admin_event_outbox e
      where e.status in ('pending','failed')
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    )
  );
end;
$$;

revoke all
on function public.get_administration_engine_health(uuid)
from public;

grant execute
on function public.get_administration_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 34. RLS
-- ============================================================

alter table public.admin_organization_profiles enable row level security;
alter table public.admin_branches enable row level security;
alter table public.admin_departments enable row level security;
alter table public.admin_teams enable row level security;
alter table public.admin_designations enable row level security;
alter table public.admin_employees enable row level security;
alter table public.admin_team_memberships enable row level security;
alter table public.admin_business_hours enable row level security;
alter table public.admin_holidays enable row level security;
alter table public.admin_shifts enable row level security;
alter table public.admin_employee_shifts enable row level security;
alter table public.admin_sla_policies enable row level security;
alter table public.admin_approval_matrices enable row level security;
alter table public.admin_approval_steps enable row level security;
alter table public.admin_branding_profiles enable row level security;
alter table public.admin_domains enable row level security;
alter table public.admin_feature_flags enable row level security;
alter table public.admin_licenses enable row level security;
alter table public.admin_tenant_limits enable row level security;
alter table public.admin_api_credentials enable row level security;
alter table public.admin_integration_settings enable row level security;
alter table public.admin_system_preferences enable row level security;
alter table public.admin_maintenance_windows enable row level security;
alter table public.admin_event_outbox enable row level security;
alter table public.admin_logs enable row level security;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'admin_organization_profiles',
    'admin_branches',
    'admin_departments',
    'admin_teams',
    'admin_designations',
    'admin_employees',
    'admin_team_memberships',
    'admin_business_hours',
    'admin_holidays',
    'admin_shifts',
    'admin_employee_shifts',
    'admin_sla_policies',
    'admin_approval_matrices',
    'admin_approval_steps',
    'admin_branding_profiles',
    'admin_domains',
    'admin_licenses',
    'admin_tenant_limits',
    'admin_api_credentials',
    'admin_integration_settings',
    'admin_system_preferences',
    'admin_maintenance_windows',
    'admin_event_outbox',
    'admin_logs'
  ]
  loop
    execute format(
      'drop policy if exists %I_select_policy on public.%I',
      target_table,target_table
    );

    execute format(
      'create policy %I_select_policy
       on public.%I
       for select
       to authenticated
       using (
         public.has_organization_permission(
           organization_id,
           ''administration.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''administration.view_all''
         )
       )',
      target_table,target_table
    );

    execute format(
      'drop policy if exists %I_service_policy on public.%I',
      target_table,target_table
    );

    execute format(
      'create policy %I_service_policy
       on public.%I
       for all
       to service_role
       using (true)
       with check (true)',
      target_table,target_table
    );
  end loop;
end;
$$;

drop policy if exists admin_feature_flags_select_policy
on public.admin_feature_flags;

create policy admin_feature_flags_select_policy
on public.admin_feature_flags
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'administration.view'
  )
  or public.has_organization_permission(
    organization_id,
    'administration.view_all'
  )
);

drop policy if exists admin_feature_flags_service_policy
on public.admin_feature_flags;

create policy admin_feature_flags_service_policy
on public.admin_feature_flags
for all
to service_role
using (true)
with check (true);

drop policy if exists admin_branches_write_policy
on public.admin_branches;

create policy admin_branches_write_policy
on public.admin_branches
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'administration.manage_branches'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'administration.manage_branches'
  )
);

drop policy if exists admin_employees_write_policy
on public.admin_employees;

create policy admin_employees_write_policy
on public.admin_employees
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'administration.manage_employees'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'administration.manage_employees'
  )
);

-- ============================================================
-- 35. GRANTS
-- ============================================================

grant select
on
  public.admin_organization_profiles,
  public.admin_branches,
  public.admin_departments,
  public.admin_teams,
  public.admin_designations,
  public.admin_employees,
  public.admin_team_memberships,
  public.admin_business_hours,
  public.admin_holidays,
  public.admin_shifts,
  public.admin_employee_shifts,
  public.admin_sla_policies,
  public.admin_approval_matrices,
  public.admin_approval_steps,
  public.admin_branding_profiles,
  public.admin_domains,
  public.admin_feature_flags,
  public.admin_licenses,
  public.admin_tenant_limits,
  public.admin_api_credentials,
  public.admin_integration_settings,
  public.admin_system_preferences,
  public.admin_maintenance_windows,
  public.admin_event_outbox,
  public.admin_logs
to authenticated;

grant insert,update,delete
on
  public.admin_organization_profiles,
  public.admin_branches,
  public.admin_departments,
  public.admin_teams,
  public.admin_designations,
  public.admin_employees,
  public.admin_team_memberships,
  public.admin_business_hours,
  public.admin_holidays,
  public.admin_shifts,
  public.admin_employee_shifts,
  public.admin_sla_policies,
  public.admin_approval_matrices,
  public.admin_approval_steps,
  public.admin_branding_profiles,
  public.admin_domains,
  public.admin_feature_flags,
  public.admin_licenses,
  public.admin_tenant_limits,
  public.admin_api_credentials,
  public.admin_integration_settings,
  public.admin_system_preferences,
  public.admin_maintenance_windows
to authenticated;

grant all
on
  public.admin_organization_profiles,
  public.admin_branches,
  public.admin_departments,
  public.admin_teams,
  public.admin_designations,
  public.admin_employees,
  public.admin_team_memberships,
  public.admin_business_hours,
  public.admin_holidays,
  public.admin_shifts,
  public.admin_employee_shifts,
  public.admin_sla_policies,
  public.admin_approval_matrices,
  public.admin_approval_steps,
  public.admin_branding_profiles,
  public.admin_domains,
  public.admin_feature_flags,
  public.admin_licenses,
  public.admin_tenant_limits,
  public.admin_api_credentials,
  public.admin_integration_settings,
  public.admin_system_preferences,
  public.admin_maintenance_windows,
  public.admin_event_outbox,
  public.admin_logs
to service_role;

-- ============================================================
-- 36. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'admin_organization_profiles',
    'admin_branches',
    'admin_departments',
    'admin_teams',
    'admin_designations',
    'admin_employees',
    'admin_team_memberships',
    'admin_business_hours',
    'admin_holidays',
    'admin_shifts',
    'admin_employee_shifts',
    'admin_sla_policies',
    'admin_approval_matrices',
    'admin_approval_steps',
    'admin_branding_profiles',
    'admin_domains',
    'admin_feature_flags',
    'admin_licenses',
    'admin_tenant_limits',
    'admin_api_credentials',
    'admin_integration_settings',
    'admin_system_preferences',
    'admin_maintenance_windows',
    'admin_event_outbox',
    'admin_logs'
  ]
  loop
    if not exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = item
    ) then
      missing_items := array_append(
        missing_items,
        'table:' || item
      );
    end if;
  end loop;

  foreach item in array array[
    'create_admin_branch',
    'create_admin_employee',
    'is_admin_business_time',
    'is_admin_feature_enabled',
    'increment_admin_tenant_usage',
    'get_admin_maintenance_status',
    'publish_admin_event',
    'get_administration_engine_health'
  ]
  loop
    if not exists (
      select 1
      from information_schema.routines
      where routine_schema = 'public'
        and routine_name = item
    ) then
      missing_items := array_append(
        missing_items,
        'function:' || item
      );
    end if;
  end loop;

  if cardinality(missing_items) > 0 then
    raise exception
      '021 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 37. MIGRATION AUDIT
-- ============================================================

insert into public.admin_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.021.completed',
  'Administration Engine migration 021 completed',
  jsonb_build_object(
    'migration',
    '021_administration_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'organization_profile',
      'branches',
      'departments',
      'teams',
      'designations',
      'employees',
      'business_hours',
      'holidays',
      'shifts',
      'sla',
      'approval_matrices',
      'branding',
      'domains',
      'feature_flags',
      'licenses',
      'tenant_limits',
      'api_credentials',
      'integration_settings',
      'system_preferences',
      'maintenance',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.admin_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.021.completed'
);

commit;