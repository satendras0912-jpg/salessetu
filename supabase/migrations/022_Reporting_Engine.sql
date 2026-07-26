-- ============================================================
-- SalesSetu Enterprise
-- Migration 022: Reporting Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   004_followups.sql
--   005_site_visits.sql
--   006_bookings.sql
--   010_ai_calling_engine.sql
--   012_assignment_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--   018_Document_Management_Engine.sql
--   019_Customer_Portal_Engine_v2.sql
--   020_Finance_Commission_Engine.sql
--   021_Administration_Engine.sql
--
-- Scope:
--   • Report catalogue and report builder
--   • Report datasets, columns, filters, sorting and grouping
--   • Saved reports, report versions and access controls
--   • Scheduled reports and recipient management
--   • Export jobs for CSV, JSON, XLSX, PDF and HTML
--   • Report cache and snapshot storage
--   • Executive, sales, agent, lead, campaign and finance reports
--   • Report delivery through email, WhatsApp and portal
--   • Event outbox, analytics, logs and health checks
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
    ('reporting','view','reporting.view','View reports'),
    ('reporting','view_all','reporting.view_all','View all organization reports'),
    ('reporting','create','reporting.create','Create reports'),
    ('reporting','update','reporting.update','Update reports'),
    ('reporting','delete','reporting.delete','Archive or delete reports'),
    ('reporting','execute','reporting.execute','Execute reports'),
    ('reporting','export','reporting.export','Export reports'),
    ('reporting','schedule','reporting.schedule','Schedule reports'),
    ('reporting','share','reporting.share','Share reports'),
    ('reporting','manage_datasets','reporting.manage_datasets','Manage report datasets'),
    ('reporting','manage_templates','reporting.manage_templates','Manage report templates'),
    ('reporting','manage_delivery','reporting.manage_delivery','Manage report delivery'),
    ('reporting','view_sensitive','reporting.view_sensitive','View sensitive report data'),
    ('reporting','view_logs','reporting.view_logs','View reporting logs'),
    ('reporting','view_analytics','reporting.view_analytics','View reporting analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. REPORT DATASETS
-- ============================================================

create table if not exists public.reporting_datasets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  dataset_code text not null,
  dataset_name text not null,
  description text,

  dataset_type text not null
    check (
      dataset_type in (
        'table',
        'view',
        'materialized_view',
        'function',
        'custom_sql',
        'api',
        'external'
      )
    ),

  source_schema text default 'public',
  source_name text,
  source_function text,
  query_template text,

  supports_filters boolean not null default true,
  supports_grouping boolean not null default true,
  supports_aggregation boolean not null default true,
  supports_pagination boolean not null default true,

  default_time_field text,
  default_sort jsonb not null default '[]',

  row_limit integer not null default 10000,
  timeout_seconds integer not null default 60,

  is_sensitive boolean not null default false,
  is_system_dataset boolean not null default false,

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,dataset_code)
);

create unique index if not exists reporting_datasets_system_unique_idx
  on public.reporting_datasets(dataset_code)
  where organization_id is null;

-- ============================================================
-- 3. SYSTEM DATASETS
-- ============================================================

insert into public.reporting_datasets (
  organization_id,
  dataset_code,
  dataset_name,
  description,
  dataset_type,
  source_schema,
  source_name,
  default_time_field,
  is_sensitive,
  is_system_dataset,
  status
)
values
  (null,'leads','Leads','Lead master dataset','table','public','leads','created_at',true,true,'active'),
  (null,'followups','Follow-ups','Follow-up task dataset','table','public','follow_up_tasks','created_at',false,true,'active'),
  (null,'site_visits','Site Visits','Site visit dataset','table','public','site_visits','created_at',false,true,'active'),
  (null,'bookings','Bookings','Booking dataset','table','public','bookings','created_at',true,true,'active'),
  (null,'customers','Customers','Customer dataset','table','public','customers','created_at',true,true,'active'),
  (null,'ai_calls','AI Calls','AI calling jobs dataset','table','public','ai_call_jobs','created_at',true,true,'active'),
  (null,'assignments','Assignments','Lead assignment dataset','table','public','lead_assignments','created_at',false,true,'active'),
  (null,'communications','Communications','Communication jobs dataset','table','public','communication_message_jobs','created_at',true,true,'active'),
  (null,'automations','Automations','Automation runs dataset','table','public','automation_runs','created_at',false,true,'active'),
  (null,'notifications','Notifications','Notification jobs dataset','table','public','notification_jobs','created_at',false,true,'active'),
  (null,'documents','Documents','Document repository dataset','table','public','documents','created_at',true,true,'active'),
  (null,'finance_invoices','Finance Invoices','Finance invoice dataset','table','public','finance_invoices','created_at',true,true,'active'),
  (null,'finance_commissions','Finance Commissions','Commission accrual dataset','table','public','finance_commission_accruals','created_at',true,true,'active'),
  (null,'analytics_daily_sales','Daily Sales Analytics','Daily sales timeseries dataset','view','public','analytics_daily_sales_timeseries','metric_date',false,true,'active'),
  (null,'analytics_agent_performance','Agent Performance','Agent performance dataset','view','public','analytics_agent_performance',null,false,true,'active')
on conflict do nothing;

-- ============================================================
-- 4. DATASET COLUMNS
-- ============================================================

create table if not exists public.reporting_dataset_columns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  dataset_id uuid not null references public.reporting_datasets(id) on delete cascade,

  column_code text not null,
  column_name text not null,
  source_expression text not null,

  data_type text not null
    check (
      data_type in (
        'text',
        'integer',
        'numeric',
        'boolean',
        'date',
        'timestamp',
        'uuid',
        'json',
        'currency',
        'percentage',
        'duration'
      )
    ),

  aggregation_options text[] not null default '{}',
  filter_operators text[] not null default '{}',

  is_dimension boolean not null default true,
  is_metric boolean not null default false,
  is_filterable boolean not null default true,
  is_sortable boolean not null default true,
  is_groupable boolean not null default true,
  is_sensitive boolean not null default false,

  display_order integer not null default 100,
  formatting jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (dataset_id,column_code)
);

-- ============================================================
-- 5. REPORT TEMPLATES
-- ============================================================

create table if not exists public.reporting_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  template_code text not null,
  template_name text not null,
  description text,

  report_category text not null
    check (
      report_category in (
        'executive',
        'sales',
        'lead',
        'agent',
        'campaign',
        'builder',
        'project',
        'finance',
        'operations',
        'ai',
        'automation',
        'communication',
        'customer_success',
        'inventory',
        'custom'
      )
    ),

  template_type text not null default 'tabular'
    check (
      template_type in (
        'tabular',
        'summary',
        'matrix',
        'chart',
        'dashboard',
        'statement',
        'custom'
      )
    ),

  dataset_id uuid references public.reporting_datasets(id) on delete set null,

  definition jsonb not null default '{}',
  default_filters jsonb not null default '[]',
  default_parameters jsonb not null default '{}',
  default_format text not null default 'pdf'
    check (default_format in ('csv','json','xlsx','pdf','html')),

  is_system_template boolean not null default false,
  is_sensitive boolean not null default false,

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,template_code)
);

create unique index if not exists reporting_templates_system_unique_idx
  on public.reporting_templates(template_code)
  where organization_id is null;

-- ============================================================
-- 6. REPORTS
-- ============================================================

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  report_code text not null,
  report_name text not null,
  description text,

  report_category text not null,
  report_type text not null default 'tabular',

  template_id uuid references public.reporting_templates(id) on delete set null,
  dataset_id uuid references public.reporting_datasets(id) on delete set null,

  owner_user_id uuid references auth.users(id) on delete set null,

  visibility text not null default 'private'
    check (visibility in ('private','team','organization','public','restricted')),

  status text not null default 'draft'
    check (status in ('draft','active','inactive','archived')),

  definition jsonb not null default '{}',
  parameters jsonb not null default '{}',

  default_format text not null default 'pdf'
    check (default_format in ('csv','json','xlsx','pdf','html')),

  cache_enabled boolean not null default true,
  cache_ttl_seconds integer not null default 900,

  is_sensitive boolean not null default false,

  last_executed_at timestamptz,
  last_execution_status text,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,report_code)
);

create index if not exists reports_org_status_idx
  on public.reports(organization_id,status,report_category);

-- ============================================================
-- 7. REPORT VERSIONS
-- ============================================================

create table if not exists public.reporting_report_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  version_number integer not null,
  definition jsonb not null default '{}',
  parameters jsonb not null default '{}',

  change_summary text,
  is_current boolean not null default false,

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  unique (report_id,version_number)
);

create unique index if not exists reporting_report_versions_current_unique_idx
  on public.reporting_report_versions(report_id)
  where is_current = true;

-- ============================================================
-- 8. REPORT COLUMNS
-- ============================================================

create table if not exists public.reporting_report_columns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,
  dataset_column_id uuid references public.reporting_dataset_columns(id) on delete set null,

  column_order integer not null,
  column_code text not null,
  column_label text not null,
  expression text,

  aggregation text
    check (aggregation is null or aggregation in ('sum','count','avg','min','max','distinct_count','custom')),

  visible boolean not null default true,
  width integer,
  formatting jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (report_id,column_order),
  unique (report_id,column_code)
);

-- ============================================================
-- 9. REPORT FILTERS
-- ============================================================

create table if not exists public.reporting_report_filters (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  filter_order integer not null default 100,
  field_code text not null,
  operator text not null
    check (
      operator in (
        'eq','neq','gt','gte','lt','lte',
        'in','not_in','between',
        'contains','starts_with','ends_with',
        'is_null','is_not_null',
        'relative_date','custom'
      )
    ),

  value jsonb,
  parameter_name text,

  required boolean not null default false,
  runtime_editable boolean not null default true,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 10. GROUPING AND SORTING
-- ============================================================

create table if not exists public.reporting_report_grouping (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  group_order integer not null,
  field_code text not null,
  display_label text,

  subtotal_enabled boolean not null default false,
  page_break_after boolean not null default false,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (report_id,group_order)
);

create table if not exists public.reporting_report_sorting (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  sort_order integer not null,
  field_code text not null,
  direction text not null default 'asc'
    check (direction in ('asc','desc')),

  nulls_position text not null default 'last'
    check (nulls_position in ('first','last')),

  created_at timestamptz not null default now(),

  unique (report_id,sort_order)
);

-- ============================================================
-- 11. REPORT ACCESS
-- ============================================================

create table if not exists public.reporting_report_access (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  principal_type text not null
    check (principal_type in ('user','role','team','organization','public')),

  principal_user_id uuid references auth.users(id) on delete cascade,
  principal_team_id uuid,
  principal_role_id uuid,
  principal_key text,

  permission_level text not null
    check (permission_level in ('view','execute','export','edit','manage')),

  valid_from timestamptz not null default now(),
  valid_until timestamptz,

  status text not null default 'active'
    check (status in ('active','inactive','expired','revoked')),

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 12. REPORT SCHEDULES
-- ============================================================

create table if not exists public.reporting_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  schedule_name text not null,
  schedule_type text not null default 'recurring'
    check (schedule_type in ('one_time','recurring','event_driven')),

  cron_expression text,
  timezone text not null default 'Asia/Kolkata',

  next_run_at timestamptz,
  last_run_at timestamptz,

  output_format text not null default 'pdf'
    check (output_format in ('csv','json','xlsx','pdf','html')),

  delivery_channels text[] not null default array['email'],
  parameters jsonb not null default '{}',
  filters jsonb not null default '[]',

  status text not null default 'active'
    check (status in ('active','paused','completed','failed','archived')),

  retry_limit integer not null default 3,

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reporting_schedules_due_idx
  on public.reporting_schedules(status,next_run_at)
  where status = 'active';

-- ============================================================
-- 13. REPORT RECIPIENTS
-- ============================================================

create table if not exists public.reporting_schedule_recipients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  schedule_id uuid not null references public.reporting_schedules(id) on delete cascade,

  recipient_type text not null
    check (recipient_type in ('user','email','phone','team','role','customer','external')),

  user_id uuid references auth.users(id) on delete set null,
  recipient_name text,
  email text,
  phone text,
  external_reference text,

  channels text[] not null default array['email'],

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

-- ============================================================
-- 14. REPORT EXECUTION JOBS
-- ============================================================

create table if not exists public.reporting_execution_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,
  schedule_id uuid references public.reporting_schedules(id) on delete set null,

  execution_type text not null default 'manual'
    check (execution_type in ('manual','scheduled','api','event','preview')),

  requested_by uuid references auth.users(id) on delete set null,

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'running',
        'completed',
        'failed',
        'cancelled',
        'expired'
      )
    ),

  priority integer not null default 100,

  parameters jsonb not null default '{}',
  filters jsonb not null default '[]',

  output_format text not null default 'pdf'
    check (output_format in ('csv','json','xlsx','pdf','html')),

  requested_at timestamptz not null default now(),
  scheduled_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  started_at timestamptz,
  completed_at timestamptz,

  row_count integer,
  duration_ms bigint,

  result_summary jsonb not null default '{}',

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reporting_execution_jobs_queue_idx
  on public.reporting_execution_jobs(
    status,
    scheduled_at,
    priority,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 15. REPORT OUTPUTS
-- ============================================================

create table if not exists public.reporting_outputs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  execution_job_id uuid not null references public.reporting_execution_jobs(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  output_format text not null,
  file_name text,
  mime_type text,

  storage_provider text default 'supabase_storage',
  storage_bucket text,
  storage_path text,

  document_id uuid references public.documents(id) on delete set null,

  file_size_bytes bigint,
  checksum text,

  status text not null default 'ready'
    check (status in ('generating','ready','expired','deleted','failed')),

  generated_at timestamptz not null default now(),
  expires_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

-- ============================================================
-- 16. DELIVERY JOBS
-- ============================================================

create table if not exists public.reporting_delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  execution_job_id uuid not null references public.reporting_execution_jobs(id) on delete cascade,
  output_id uuid references public.reporting_outputs(id) on delete set null,

  delivery_channel text not null
    check (delivery_channel in ('email','whatsapp','sms','portal','webhook','download')),

  recipient_type text,
  recipient_reference text,
  recipient_name text,
  recipient_email text,
  recipient_phone text,

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'processing',
        'delivered',
        'failed',
        'cancelled',
        'expired'
      )
    ),

  attempts integer not null default 0,
  maximum_attempts integer not null default 5,

  scheduled_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  delivered_at timestamptz,

  provider_reference text,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reporting_delivery_jobs_queue_idx
  on public.reporting_delivery_jobs(status,scheduled_at,created_at)
  where status in ('queued','failed');

-- ============================================================
-- 17. REPORT CACHE
-- ============================================================

create table if not exists public.reporting_cache (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  cache_key text not null,
  parameter_hash text not null,
  filter_hash text not null,

  result_data jsonb,
  row_count integer,

  generated_at timestamptz not null default now(),
  expires_at timestamptz not null,

  status text not null default 'valid'
    check (status in ('valid','stale','expired','invalidated')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (organization_id,cache_key)
);

create index if not exists reporting_cache_expiry_idx
  on public.reporting_cache(status,expires_at);

-- ============================================================
-- 18. REPORT SNAPSHOTS
-- ============================================================

create table if not exists public.reporting_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  report_id uuid not null references public.reports(id) on delete cascade,

  snapshot_name text,
  snapshot_period_start timestamptz,
  snapshot_period_end timestamptz,

  result_data jsonb not null default '{}',
  summary_data jsonb not null default '{}',

  row_count integer,
  generated_at timestamptz not null default now(),

  generated_by uuid references auth.users(id) on delete set null,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

-- ============================================================
-- 19. REPORT EVENT OUTBOX AND LOGS
-- ============================================================

create table if not exists public.reporting_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  report_id uuid references public.reports(id) on delete set null,
  execution_job_id uuid references public.reporting_execution_jobs(id) on delete set null,

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
        'audit',
        'webhook'
      )
    ),

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

create unique index if not exists reporting_event_outbox_idempotency_idx
  on public.reporting_event_outbox(organization_id,idempotency_key)
  where idempotency_key is not null;

create table if not exists public.reporting_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  report_id uuid references public.reports(id) on delete set null,
  execution_job_id uuid references public.reporting_execution_jobs(id) on delete set null,
  delivery_job_id uuid references public.reporting_delivery_jobs(id) on delete set null,

  log_level text not null default 'info'
    check (log_level in ('debug','info','warning','error','critical')),

  event_name text,
  message text,

  error_code text,
  error_message text,
  log_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now()
);

create index if not exists reporting_logs_org_created_idx
  on public.reporting_logs(organization_id,created_at desc);

-- ============================================================
-- 20. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'reporting_datasets',
    'reporting_dataset_columns',
    'reporting_templates',
    'reports',
    'reporting_report_columns',
    'reporting_report_filters',
    'reporting_schedules',
    'reporting_execution_jobs',
    'reporting_delivery_jobs',
    'reporting_event_outbox'
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
-- 21. CREATE REPORT
-- ============================================================

create or replace function public.create_reporting_report(
  requested_organization_id uuid,
  requested_report_name text,
  requested_report_category text,
  requested_dataset_id uuid default null,
  requested_template_id uuid default null,
  requested_description text default null,
  requested_visibility text default 'private',
  requested_default_format text default 'pdf',
  requested_definition jsonb default '{}'::jsonb,
  requested_parameters jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_record public.reports;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'reporting.create'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.reports (
    organization_id,
    report_code,
    report_name,
    description,
    report_category,
    report_type,
    template_id,
    dataset_id,
    owner_user_id,
    visibility,
    status,
    definition,
    parameters,
    default_format,
    created_by,
    updated_by,
    metadata
  )
  values (
    requested_organization_id,
    'RPT-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
    requested_report_name,
    requested_description,
    requested_report_category,
    coalesce(requested_definition->>'report_type','tabular'),
    requested_template_id,
    requested_dataset_id,
    auth.uid(),
    requested_visibility,
    'active',
    coalesce(requested_definition,'{}'::jsonb),
    coalesce(requested_parameters,'{}'::jsonb),
    requested_default_format,
    auth.uid(),
    auth.uid(),
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into report_record;

  insert into public.reporting_report_versions (
    organization_id,
    report_id,
    version_number,
    definition,
    parameters,
    change_summary,
    is_current,
    created_by
  )
  values (
    report_record.organization_id,
    report_record.id,
    1,
    report_record.definition,
    report_record.parameters,
    'Initial version',
    true,
    auth.uid()
  );

  return report_record;
end;
$$;

revoke all
on function public.create_reporting_report(
  uuid,text,text,uuid,uuid,text,text,text,jsonb,jsonb,jsonb
)
from public;

grant execute
on function public.create_reporting_report(
  uuid,text,text,uuid,uuid,text,text,text,jsonb,jsonb,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 22. SAVE REPORT VERSION
-- ============================================================

create or replace function public.save_reporting_report_version(
  requested_report_id uuid,
  requested_definition jsonb,
  requested_parameters jsonb default '{}'::jsonb,
  requested_change_summary text default null
)
returns public.reporting_report_versions
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_record public.reports;
  next_version integer;
  version_record public.reporting_report_versions;
begin
  select *
  into report_record
  from public.reports
  where id = requested_report_id
  for update;

  if not found then
    raise exception 'Report not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from report_record.owner_user_id
    and not public.has_organization_permission(
      report_record.organization_id,
      'reporting.update'
    ) then
    raise exception 'Permission denied';
  end if;

  select coalesce(max(version_number),0) + 1
  into next_version
  from public.reporting_report_versions
  where report_id = requested_report_id;

  update public.reporting_report_versions
  set is_current = false
  where report_id = requested_report_id
    and is_current = true;

  insert into public.reporting_report_versions (
    organization_id,
    report_id,
    version_number,
    definition,
    parameters,
    change_summary,
    is_current,
    created_by
  )
  values (
    report_record.organization_id,
    report_record.id,
    next_version,
    requested_definition,
    coalesce(requested_parameters,'{}'::jsonb),
    requested_change_summary,
    true,
    auth.uid()
  )
  returning * into version_record;

  update public.reports
  set
    definition = requested_definition,
    parameters = coalesce(requested_parameters,'{}'::jsonb),
    updated_by = auth.uid(),
    updated_at = now()
  where id = requested_report_id;

  return version_record;
end;
$$;

revoke all
on function public.save_reporting_report_version(uuid,jsonb,jsonb,text)
from public;

grant execute
on function public.save_reporting_report_version(uuid,jsonb,jsonb,text)
to authenticated,service_role;

-- ============================================================
-- 23. CREATE EXECUTION JOB
-- ============================================================

create or replace function public.create_reporting_execution_job(
  requested_report_id uuid,
  requested_execution_type text default 'manual',
  requested_output_format text default null,
  requested_parameters jsonb default '{}'::jsonb,
  requested_filters jsonb default '[]'::jsonb,
  requested_schedule_id uuid default null,
  requested_priority integer default 100,
  requested_scheduled_at timestamptz default now(),
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns public.reporting_execution_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_record public.reports;
  job_record public.reporting_execution_jobs;
begin
  select *
  into report_record
  from public.reports
  where id = requested_report_id
    and status = 'active';

  if not found then
    raise exception 'Active report not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from report_record.owner_user_id
    and not public.has_organization_permission(
      report_record.organization_id,
      'reporting.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.reporting_execution_jobs (
    organization_id,
    report_id,
    schedule_id,
    execution_type,
    requested_by,
    status,
    priority,
    parameters,
    filters,
    output_format,
    requested_at,
    scheduled_at,
    correlation_id,
    trace_id
  )
  values (
    report_record.organization_id,
    report_record.id,
    requested_schedule_id,
    requested_execution_type,
    auth.uid(),
    'queued',
    requested_priority,
    coalesce(requested_parameters,'{}'::jsonb),
    coalesce(requested_filters,'[]'::jsonb),
    coalesce(requested_output_format,report_record.default_format),
    now(),
    coalesce(requested_scheduled_at,now()),
    requested_correlation_id,
    requested_trace_id
  )
  returning * into job_record;

  return job_record;
end;
$$;

revoke all
on function public.create_reporting_execution_job(
  uuid,text,text,jsonb,jsonb,uuid,integer,timestamptz,text,text
)
from public;

grant execute
on function public.create_reporting_execution_job(
  uuid,text,text,jsonb,jsonb,uuid,integer,timestamptz,text,text
)
to authenticated,service_role;

-- ============================================================
-- 24. CLAIM EXECUTION JOB
-- ============================================================

create or replace function public.claim_reporting_execution_job(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 600
)
returns public.reporting_execution_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.reporting_execution_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim reporting jobs';
  end if;

  select *
  into job_record
  from public.reporting_execution_jobs j
  where j.status in ('queued','failed')
    and j.scheduled_at <= now()
    and (
      requested_organization_id is null
      or j.organization_id = requested_organization_id
    )
  order by j.priority,j.scheduled_at,j.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.reporting_execution_jobs
  set
    status = 'claimed',
    claimed_at = now(),
    claimed_by = requested_worker_id,
    lock_token = gen_random_uuid()::text,
    lock_expires_at = now() + make_interval(
      secs => greatest(requested_lock_seconds,1)
    ),
    updated_at = now()
  where id = job_record.id
  returning * into job_record;

  return job_record;
end;
$$;

revoke all
on function public.claim_reporting_execution_job(text,uuid,integer)
from public;

grant execute
on function public.claim_reporting_execution_job(text,uuid,integer)
to service_role;

-- ============================================================
-- 25. COMPLETE EXECUTION JOB
-- ============================================================

create or replace function public.complete_reporting_execution_job(
  requested_job_id uuid,
  requested_lock_token text,
  requested_row_count integer default null,
  requested_duration_ms bigint default null,
  requested_result_summary jsonb default '{}'::jsonb
)
returns public.reporting_execution_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.reporting_execution_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete reporting jobs';
  end if;

  select *
  into job_record
  from public.reporting_execution_jobs
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Reporting execution job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid reporting lock token';
  end if;

  update public.reporting_execution_jobs
  set
    status = 'completed',
    started_at = coalesce(started_at,claimed_at,now()),
    completed_at = now(),
    row_count = requested_row_count,
    duration_ms = requested_duration_ms,
    result_summary = coalesce(requested_result_summary,'{}'::jsonb),
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where id = requested_job_id
  returning * into job_record;

  update public.reports
  set
    last_executed_at = now(),
    last_execution_status = 'completed',
    updated_at = now()
  where id = job_record.report_id;

  return job_record;
end;
$$;

revoke all
on function public.complete_reporting_execution_job(
  uuid,text,integer,bigint,jsonb
)
from public;

grant execute
on function public.complete_reporting_execution_job(
  uuid,text,integer,bigint,jsonb
)
to service_role;

-- ============================================================
-- 26. CREATE REPORT OUTPUT
-- ============================================================

create or replace function public.create_reporting_output(
  requested_execution_job_id uuid,
  requested_file_name text,
  requested_mime_type text,
  requested_storage_bucket text,
  requested_storage_path text,
  requested_file_size_bytes bigint default null,
  requested_checksum text default null,
  requested_document_id uuid default null,
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.reporting_outputs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.reporting_execution_jobs;
  output_record public.reporting_outputs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may create report outputs';
  end if;

  select *
  into job_record
  from public.reporting_execution_jobs
  where id = requested_execution_job_id;

  if not found then
    raise exception 'Reporting execution job not found';
  end if;

  insert into public.reporting_outputs (
    organization_id,
    execution_job_id,
    report_id,
    output_format,
    file_name,
    mime_type,
    storage_bucket,
    storage_path,
    document_id,
    file_size_bytes,
    checksum,
    status,
    expires_at,
    metadata
  )
  values (
    job_record.organization_id,
    job_record.id,
    job_record.report_id,
    job_record.output_format,
    requested_file_name,
    requested_mime_type,
    requested_storage_bucket,
    requested_storage_path,
    requested_document_id,
    requested_file_size_bytes,
    requested_checksum,
    'ready',
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into output_record;

  return output_record;
end;
$$;

revoke all
on function public.create_reporting_output(
  uuid,text,text,text,text,bigint,text,uuid,timestamptz,jsonb
)
from public;

grant execute
on function public.create_reporting_output(
  uuid,text,text,text,text,bigint,text,uuid,timestamptz,jsonb
)
to service_role;

-- ============================================================
-- 27. CREATE SCHEDULE
-- ============================================================

create or replace function public.create_reporting_schedule(
  requested_report_id uuid,
  requested_schedule_name text,
  requested_cron_expression text,
  requested_timezone text default 'Asia/Kolkata',
  requested_output_format text default 'pdf',
  requested_delivery_channels text[] default array['email'],
  requested_parameters jsonb default '{}'::jsonb,
  requested_filters jsonb default '[]'::jsonb,
  requested_next_run_at timestamptz default null
)
returns public.reporting_schedules
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_record public.reports;
  schedule_record public.reporting_schedules;
begin
  select *
  into report_record
  from public.reports
  where id = requested_report_id;

  if not found then
    raise exception 'Report not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      report_record.organization_id,
      'reporting.schedule'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.reporting_schedules (
    organization_id,
    report_id,
    schedule_name,
    schedule_type,
    cron_expression,
    timezone,
    next_run_at,
    output_format,
    delivery_channels,
    parameters,
    filters,
    status,
    created_by,
    updated_by
  )
  values (
    report_record.organization_id,
    report_record.id,
    requested_schedule_name,
    'recurring',
    requested_cron_expression,
    requested_timezone,
    requested_next_run_at,
    requested_output_format,
    coalesce(requested_delivery_channels,array['email']),
    coalesce(requested_parameters,'{}'::jsonb),
    coalesce(requested_filters,'[]'::jsonb),
    'active',
    auth.uid(),
    auth.uid()
  )
  returning * into schedule_record;

  return schedule_record;
end;
$$;

revoke all
on function public.create_reporting_schedule(
  uuid,text,text,text,text,text[],jsonb,jsonb,timestamptz
)
from public;

grant execute
on function public.create_reporting_schedule(
  uuid,text,text,text,text,text[],jsonb,jsonb,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 28. PUBLISH REPORT EVENT
-- ============================================================

create or replace function public.publish_reporting_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_report_id uuid default null,
  requested_execution_job_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.reporting_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.reporting_event_outbox;
  created_event public.reporting_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.reporting_event_outbox e
    where e.organization_id = requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.reporting_event_outbox (
    organization_id,
    report_id,
    execution_job_id,
    event_name,
    destination,
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
    requested_report_id,
    requested_execution_job_id,
    requested_event_name,
    requested_destination,
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
on function public.publish_reporting_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_reporting_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 29. REPORT JOB EVENT TRIGGER
-- ============================================================

create or replace function public.emit_reporting_job_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE'
    and new.status is not distinct from old.status then
    return new;
  end if;

  perform public.publish_reporting_event(
    new.organization_id,
    'reporting.execution.' || new.status,
    jsonb_build_object(
      'execution_job_id',new.id,
      'report_id',new.report_id,
      'status',new.status,
      'output_format',new.output_format,
      'row_count',new.row_count,
      'duration_ms',new.duration_ms,
      'error_code',new.error_code,
      'error_message',new.error_message
    ),
    case
      when new.status in ('completed','failed') then 'notification_engine'
      else 'analytics'
    end,
    new.report_id,
    new.id,
    case when new.status = 'failed' then 10 else 50 end,
    'report-execution:' || new.id::text || ':' || new.status,
    coalesce(new.correlation_id,new.id::text),
    new.trace_id,
    now()
  );

  return new;
end;
$$;

drop trigger if exists reporting_execution_jobs_emit_events
on public.reporting_execution_jobs;

create trigger reporting_execution_jobs_emit_events
after insert or update
on public.reporting_execution_jobs
for each row
execute function public.emit_reporting_job_events();

-- ============================================================
-- 30. STANDARD REPORTING VIEWS
-- ============================================================

create or replace view public.reporting_executive_summary
with (security_invoker = true)
as
select
  o.id as organization_id,

  (select count(*)
   from public.leads l
   where l.organization_id = o.id) as total_leads,

  (select count(*)
   from public.site_visits s
   where s.organization_id = o.id) as total_site_visits,

  (select count(*)
   from public.bookings b
   where b.organization_id = o.id) as total_bookings,

  (select coalesce(sum(
      coalesce(
        nullif(to_jsonb(b)->>'booking_amount','')::numeric,
        nullif(to_jsonb(b)->>'amount','')::numeric,
        nullif(to_jsonb(b)->>'total_amount','')::numeric,
        0
      )
    ),0)
   from public.bookings b
   where b.organization_id = o.id) as total_booking_value,

  (select count(*)
   from public.finance_invoices i
   where i.organization_id = o.id
     and i.status = 'overdue') as overdue_invoices,

  (select count(*)
   from public.customer_portal_support_tickets t
   where t.organization_id = o.id
     and t.status not in ('resolved','closed','cancelled')) as open_support_tickets,

  now() as generated_at

from public.organizations o;

create or replace view public.reporting_sales_pipeline
with (security_invoker = true)
as
select
  l.organization_id,
  coalesce(
    to_jsonb(l)->>'status',
    to_jsonb(l)->>'lead_status',
    'unknown'
  ) as lead_status,

  count(*) as lead_count,

  count(*) filter (
    where exists (
      select 1
      from public.lead_assignments a
      where a.organization_id = l.organization_id
        and a.lead_id = l.id
    )
  ) as assigned_count,

  count(*) filter (
    where exists (
      select 1
      from public.site_visits s
      where s.organization_id = l.organization_id
        and s.lead_id = l.id
    )
  ) as site_visit_count,

  count(*) filter (
    where exists (
      select 1
      from public.bookings b
      where b.organization_id = l.organization_id
        and b.lead_id = l.id
    )
  ) as booking_count

from public.leads l
group by
  l.organization_id,
  coalesce(
    to_jsonb(l)->>'status',
    to_jsonb(l)->>'lead_status',
    'unknown'
  );

create or replace view public.reporting_agent_summary
with (security_invoker = true)
as
select *
from public.analytics_agent_performance;

create or replace view public.reporting_finance_summary
with (security_invoker = true)
as
select *
from public.finance_executive_dashboard;

create or replace view public.reporting_ai_summary
with (security_invoker = true)
as
select
  j.organization_id,
  count(*) as total_jobs,

  count(*) filter (
    where j.status in ('completed','succeeded')
  ) as completed_jobs,

  count(*) filter (
    where j.status in ('failed','cancelled')
  ) as failed_jobs,

  round(
    count(*) filter (
      where j.status in ('completed','succeeded')
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as completion_rate

from public.ai_call_jobs j
group by j.organization_id;

create or replace view public.reporting_automation_summary
with (security_invoker = true)
as
select *
from public.analytics_automation_performance;

-- ============================================================
-- 31. REPORTING ANALYTICS VIEWS
-- ============================================================

create or replace view public.reporting_usage_dashboard
with (security_invoker = true)
as
select
  r.organization_id,
  r.report_category,

  count(*) as report_count,

  count(*) filter (
    where r.status = 'active'
  ) as active_reports,

  count(e.id) as execution_count,

  count(e.id) filter (
    where e.status = 'completed'
  ) as completed_executions,

  count(e.id) filter (
    where e.status = 'failed'
  ) as failed_executions,

  round(
    count(e.id) filter (
      where e.status = 'completed'
    )::numeric
    / nullif(count(e.id),0) * 100,
    2
  ) as execution_success_rate,

  max(e.completed_at) as latest_execution_at

from public.reports r
left join public.reporting_execution_jobs e
  on e.report_id = r.id
group by r.organization_id,r.report_category;

create or replace view public.reporting_schedule_dashboard
with (security_invoker = true)
as
select
  s.organization_id,
  s.status,
  s.output_format,

  count(*) as schedule_count,

  count(*) filter (
    where s.next_run_at <= now()
      and s.status = 'active'
  ) as due_schedules,

  max(s.last_run_at) as latest_run_at,
  min(s.next_run_at) filter (
    where s.status = 'active'
  ) as next_scheduled_run_at

from public.reporting_schedules s
group by s.organization_id,s.status,s.output_format;

create or replace view public.reporting_delivery_dashboard
with (security_invoker = true)
as
select
  organization_id,
  delivery_channel,
  status,

  count(*) as delivery_count,

  count(*) filter (
    where status = 'delivered'
  ) as delivered_count,

  count(*) filter (
    where status = 'failed'
  ) as failed_count,

  round(
    count(*) filter (
      where status = 'delivered'
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as delivery_success_rate

from public.reporting_delivery_jobs
group by organization_id,delivery_channel,status;

grant select
on
  public.reporting_executive_summary,
  public.reporting_sales_pipeline,
  public.reporting_agent_summary,
  public.reporting_finance_summary,
  public.reporting_ai_summary,
  public.reporting_automation_summary,
  public.reporting_usage_dashboard,
  public.reporting_schedule_dashboard,
  public.reporting_delivery_dashboard
to authenticated,service_role;

-- ============================================================
-- 32. HEALTH CHECK
-- ============================================================

create or replace function public.get_reporting_engine_health(
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
        'reporting.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'active_reports',(
      select count(*)
      from public.reports r
      where r.status = 'active'
        and (
          requested_organization_id is null
          or r.organization_id = requested_organization_id
        )
    ),

    'active_schedules',(
      select count(*)
      from public.reporting_schedules s
      where s.status = 'active'
        and (
          requested_organization_id is null
          or s.organization_id = requested_organization_id
        )
    ),

    'queued_execution_jobs',(
      select count(*)
      from public.reporting_execution_jobs j
      where j.status in ('queued','claimed','running','failed')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'queued_delivery_jobs',(
      select count(*)
      from public.reporting_delivery_jobs j
      where j.status in ('queued','claimed','processing','failed')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'expired_cache_entries',(
      select count(*)
      from public.reporting_cache c
      where c.expires_at <= now()
        and c.status = 'valid'
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'failed_executions_24h',(
      select count(*)
      from public.reporting_execution_jobs j
      where j.status = 'failed'
        and j.updated_at >= now() - interval '24 hours'
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.reporting_event_outbox e
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
on function public.get_reporting_engine_health(uuid)
from public;

grant execute
on function public.get_reporting_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 33. RLS
-- ============================================================

alter table public.reporting_datasets enable row level security;
alter table public.reporting_dataset_columns enable row level security;
alter table public.reporting_templates enable row level security;
alter table public.reports enable row level security;
alter table public.reporting_report_versions enable row level security;
alter table public.reporting_report_columns enable row level security;
alter table public.reporting_report_filters enable row level security;
alter table public.reporting_report_grouping enable row level security;
alter table public.reporting_report_sorting enable row level security;
alter table public.reporting_report_access enable row level security;
alter table public.reporting_schedules enable row level security;
alter table public.reporting_schedule_recipients enable row level security;
alter table public.reporting_execution_jobs enable row level security;
alter table public.reporting_outputs enable row level security;
alter table public.reporting_delivery_jobs enable row level security;
alter table public.reporting_cache enable row level security;
alter table public.reporting_snapshots enable row level security;
alter table public.reporting_event_outbox enable row level security;
alter table public.reporting_logs enable row level security;

drop policy if exists reporting_datasets_select_policy
on public.reporting_datasets;

create policy reporting_datasets_select_policy
on public.reporting_datasets
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'reporting.view'
  )
  or public.has_organization_permission(
    organization_id,
    'reporting.view_all'
  )
);

drop policy if exists reporting_templates_select_policy
on public.reporting_templates;

create policy reporting_templates_select_policy
on public.reporting_templates
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'reporting.view'
  )
  or public.has_organization_permission(
    organization_id,
    'reporting.view_all'
  )
);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'reporting_dataset_columns',
    'reports',
    'reporting_report_versions',
    'reporting_report_columns',
    'reporting_report_filters',
    'reporting_report_grouping',
    'reporting_report_sorting',
    'reporting_report_access',
    'reporting_schedules',
    'reporting_schedule_recipients',
    'reporting_execution_jobs',
    'reporting_outputs',
    'reporting_delivery_jobs',
    'reporting_cache',
    'reporting_snapshots',
    'reporting_event_outbox',
    'reporting_logs'
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
           ''reporting.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''reporting.view_all''
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

drop policy if exists reports_write_policy
on public.reports;

create policy reports_write_policy
on public.reports
for all
to authenticated
using (
  owner_user_id = auth.uid()
  or public.has_organization_permission(
    organization_id,
    'reporting.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'reporting.create'
  )
  or public.has_organization_permission(
    organization_id,
    'reporting.update'
  )
);

drop policy if exists reporting_schedules_write_policy
on public.reporting_schedules;

create policy reporting_schedules_write_policy
on public.reporting_schedules
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'reporting.schedule'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'reporting.schedule'
  )
);

-- ============================================================
-- 34. GRANTS
-- ============================================================

grant select
on
  public.reporting_datasets,
  public.reporting_dataset_columns,
  public.reporting_templates,
  public.reports,
  public.reporting_report_versions,
  public.reporting_report_columns,
  public.reporting_report_filters,
  public.reporting_report_grouping,
  public.reporting_report_sorting,
  public.reporting_report_access,
  public.reporting_schedules,
  public.reporting_schedule_recipients,
  public.reporting_execution_jobs,
  public.reporting_outputs,
  public.reporting_delivery_jobs,
  public.reporting_cache,
  public.reporting_snapshots,
  public.reporting_event_outbox,
  public.reporting_logs
to authenticated;

grant insert,update,delete
on
  public.reporting_datasets,
  public.reporting_dataset_columns,
  public.reporting_templates,
  public.reports,
  public.reporting_report_versions,
  public.reporting_report_columns,
  public.reporting_report_filters,
  public.reporting_report_grouping,
  public.reporting_report_sorting,
  public.reporting_report_access,
  public.reporting_schedules,
  public.reporting_schedule_recipients
to authenticated;

grant all
on
  public.reporting_datasets,
  public.reporting_dataset_columns,
  public.reporting_templates,
  public.reports,
  public.reporting_report_versions,
  public.reporting_report_columns,
  public.reporting_report_filters,
  public.reporting_report_grouping,
  public.reporting_report_sorting,
  public.reporting_report_access,
  public.reporting_schedules,
  public.reporting_schedule_recipients,
  public.reporting_execution_jobs,
  public.reporting_outputs,
  public.reporting_delivery_jobs,
  public.reporting_cache,
  public.reporting_snapshots,
  public.reporting_event_outbox,
  public.reporting_logs
to service_role;

-- ============================================================
-- 35. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'reporting_datasets',
    'reporting_dataset_columns',
    'reporting_templates',
    'reports',
    'reporting_report_versions',
    'reporting_report_columns',
    'reporting_report_filters',
    'reporting_report_grouping',
    'reporting_report_sorting',
    'reporting_report_access',
    'reporting_schedules',
    'reporting_schedule_recipients',
    'reporting_execution_jobs',
    'reporting_outputs',
    'reporting_delivery_jobs',
    'reporting_cache',
    'reporting_snapshots',
    'reporting_event_outbox',
    'reporting_logs'
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
    'create_reporting_report',
    'save_reporting_report_version',
    'create_reporting_execution_job',
    'claim_reporting_execution_job',
    'complete_reporting_execution_job',
    'create_reporting_output',
    'create_reporting_schedule',
    'publish_reporting_event',
    'get_reporting_engine_health'
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
      '022 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 36. MIGRATION AUDIT
-- ============================================================

insert into public.reporting_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.022.completed',
  'Reporting Engine migration 022 completed',
  jsonb_build_object(
    'migration',
    '022_reporting_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'datasets',
      'dataset_columns',
      'templates',
      'reports',
      'versions',
      'columns',
      'filters',
      'grouping',
      'sorting',
      'access',
      'schedules',
      'recipients',
      'execution_jobs',
      'outputs',
      'delivery_jobs',
      'cache',
      'snapshots',
      'standard_reports',
      'analytics',
      'event_outbox'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.reporting_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.022.completed'
);

commit;