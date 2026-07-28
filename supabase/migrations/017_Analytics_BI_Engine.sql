-- ============================================================
-- SalesSetu Enterprise
-- Migration 017: Analytics & BI Engine
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
--   007_customer_success.sql
--   008_inventory.sql
--   009_workflow_engine_v2.sql
--   010_ai_calling_engine.sql
--   011_lead_validation_engine_production_v2.sql
--   012_assignment_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--
-- Scope:
--   • Enterprise KPI catalogue and scorecards
--   • Executive, sales, agent, builder and project analytics
--   • Lead-source, campaign and funnel analytics
--   • Validation, AI calling, assignment and follow-up analytics
--   • Site visit, booking, revenue and conversion analytics
--   • Communication, notification and automation analytics
--   • Time-series snapshots and materialized rollups
--   • Cohorts, targets, forecasts and alert thresholds
--   • RLS, permissions, grants, health checks and refresh jobs
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
    ('analytics','view','analytics.view','View analytics dashboards'),
    ('analytics','view_all','analytics.view_all','View all organization analytics'),
    ('analytics','view_financial','analytics.view_financial','View financial analytics'),
    ('analytics','manage_kpis','analytics.manage_kpis','Manage KPI definitions'),
    ('analytics','manage_targets','analytics.manage_targets','Manage KPI targets'),
    ('analytics','manage_dashboards','analytics.manage_dashboards','Manage dashboard definitions'),
    ('analytics','manage_forecasts','analytics.manage_forecasts','Manage forecasts'),
    ('analytics','refresh','analytics.refresh','Refresh analytics snapshots'),
    ('analytics','export','analytics.export','Export analytics reports'),
    ('analytics','view_logs','analytics.view_logs','View analytics logs'),
    ('analytics','view_health','analytics.view_health','View analytics engine health')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. KPI DEFINITIONS
-- ============================================================

create table if not exists public.analytics_kpi_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  kpi_code text not null,
  kpi_name text not null,
  description text,

  category text not null
    check (
      category in (
        'executive',
        'lead',
        'sales',
        'agent',
        'builder',
        'project',
        'campaign',
        'validation',
        'ai_calling',
        'assignment',
        'followup',
        'site_visit',
        'booking',
        'revenue',
        'communication',
        'notification',
        'automation',
        'customer_success',
        'inventory',
        'custom'
      )
    ),

  metric_type text not null
    check (
      metric_type in (
        'count',
        'sum',
        'average',
        'percentage',
        'ratio',
        'duration',
        'currency',
        'score'
      )
    ),

  aggregation_method text not null default 'sum'
    check (
      aggregation_method in (
        'sum',
        'count',
        'avg',
        'min',
        'max',
        'distinct_count',
        'ratio',
        'custom'
      )
    ),

  data_source text not null,
  expression_sql text,
  numerator_expression text,
  denominator_expression text,

  unit text,
  decimal_places integer not null default 2,
  higher_is_better boolean not null default true,

  default_time_grain text not null default 'day'
    check (default_time_grain in ('hour','day','week','month','quarter','year')),

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  is_system_kpi boolean not null default false,
  is_financial boolean not null default false,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,kpi_code)
);

create unique index if not exists analytics_kpi_system_unique_idx
  on public.analytics_kpi_definitions (kpi_code)
  where organization_id is null;

-- ============================================================
-- 3. SYSTEM KPIs
-- ============================================================

insert into public.analytics_kpi_definitions (
  organization_id,kpi_code,kpi_name,description,
  category,metric_type,aggregation_method,data_source,
  unit,decimal_places,higher_is_better,
  default_time_grain,status,is_system_kpi,is_financial
)
values
  (null,'total_leads','Total Leads','Total leads created','lead','count','count','leads','count',0,true,'day','active',true,false),
  (null,'validated_leads','Validated Leads','Leads approved by validation engine','validation','count','count','lead_validation_results','count',0,true,'day','active',true,false),
  (null,'lead_validation_rate','Lead Validation Rate','Approved leads as percentage of total leads','validation','percentage','ratio','lead_validation_results','percent',2,true,'day','active',true,false),
  (null,'assigned_leads','Assigned Leads','Leads assigned to agents','assignment','count','count','lead_assignments','count',0,true,'day','active',true,false),
  (null,'assignment_sla_rate','Assignment SLA Rate','Assignments responded within SLA','assignment','percentage','ratio','lead_assignments','percent',2,true,'day','active',true,false),
  (null,'ai_calls_completed','AI Calls Completed','Completed AI calls','ai_calling','count','count','ai_call_jobs','count',0,true,'day','active',true,false),
  (null,'ai_call_connect_rate','AI Call Connect Rate','Connected AI calls as percentage of attempted calls','ai_calling','percentage','ratio','ai_call_attempts','percent',2,true,'day','active',true,false),
  (null,'followups_due','Follow-ups Due','Open follow-ups due','followup','count','count','follow_up_tasks','count',0,false,'day','active',true,false),
  (null,'site_visits_scheduled','Site Visits Scheduled','Scheduled site visits','site_visit','count','count','site_visits','count',0,true,'day','active',true,false),
  (null,'site_visit_completion_rate','Site Visit Completion Rate','Completed site visits as percentage of scheduled visits','site_visit','percentage','ratio','site_visits','percent',2,true,'day','active',true,false),
  (null,'bookings_count','Bookings','Total bookings','booking','count','count','bookings','count',0,true,'day','active',true,false),
  (null,'booking_conversion_rate','Booking Conversion Rate','Bookings as percentage of total leads','booking','percentage','ratio','bookings','percent',2,true,'day','active',true,false),
  (null,'booking_value','Booking Value','Total booking value','revenue','currency','sum','bookings','currency',2,true,'day','active',true,true),
  (null,'communication_delivery_rate','Communication Delivery Rate','Delivered/read communication percentage','communication','percentage','ratio','communication_message_jobs','percent',2,true,'day','active',true,false),
  (null,'notification_read_rate','Notification Read Rate','Read notifications as percentage of delivered notifications','notification','percentage','ratio','notification_jobs','percent',2,true,'day','active',true,false),
  (null,'automation_success_rate','Automation Success Rate','Successful automation runs percentage','automation','percentage','ratio','automation_runs','percent',2,true,'day','active',true,false),
  (null,'active_inventory','Active Inventory','Available inventory units','inventory','count','count','inventory_units','count',0,true,'day','active',true,false)
on conflict do nothing;

-- ============================================================
-- 4. KPI TARGETS
-- ============================================================

create table if not exists public.analytics_kpi_targets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  kpi_definition_id uuid not null references public.analytics_kpi_definitions(id) on delete cascade,

  target_scope text not null
    check (
      target_scope in (
        'organization',
        'team',
        'agent',
        'builder',
        'project',
        'campaign',
        'source',
        'custom'
      )
    ),

  scope_id uuid,
  scope_key text,

  period_type text not null
    check (period_type in ('day','week','month','quarter','year','custom')),

  period_start date not null,
  period_end date not null,

  target_value numeric not null,
  warning_threshold numeric,
  critical_threshold numeric,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (period_end >= period_start),

  unique (
    organization_id,
    kpi_definition_id,
    target_scope,
    scope_id,
    scope_key,
    period_start,
    period_end
  )
);

create index if not exists analytics_kpi_targets_lookup_idx
  on public.analytics_kpi_targets (
    organization_id,
    kpi_definition_id,
    target_scope,
    period_start,
    period_end
  );

-- ============================================================
-- 5. KPI SNAPSHOTS
-- ============================================================

create table if not exists public.analytics_kpi_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  kpi_definition_id uuid not null references public.analytics_kpi_definitions(id) on delete cascade,

  time_grain text not null
    check (time_grain in ('hour','day','week','month','quarter','year')),

  period_start timestamptz not null,
  period_end timestamptz not null,

  dimension_type text not null default 'organization',
  dimension_id uuid,
  dimension_key text,

  metric_value numeric,
  numerator_value numeric,
  denominator_value numeric,

  comparison_value numeric,
  change_value numeric,
  change_percent numeric,

  target_value numeric,
  target_achievement_percent numeric,

  status text not null default 'ready'
    check (status in ('ready','partial','stale','error')),

  calculated_at timestamptz not null default now(),
  source_watermark timestamptz,
  calculation_metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    organization_id,
    kpi_definition_id,
    time_grain,
    period_start,
    dimension_type,
    dimension_id,
    dimension_key
  )
);

create index if not exists analytics_kpi_snapshots_lookup_idx
  on public.analytics_kpi_snapshots (
    organization_id,
    kpi_definition_id,
    time_grain,
    period_start desc
  );

-- ============================================================
-- 6. DASHBOARD DEFINITIONS
-- ============================================================

create table if not exists public.analytics_dashboards (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  dashboard_code text not null,
  dashboard_name text not null,
  description text,

  dashboard_type text not null
    check (
      dashboard_type in (
        'executive',
        'sales',
        'agent',
        'builder',
        'project',
        'campaign',
        'operations',
        'finance',
        'custom'
      )
    ),

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  layout_configuration jsonb not null default '{}',
  filter_configuration jsonb not null default '{}',
  refresh_configuration jsonb not null default '{}',

  is_system_dashboard boolean not null default false,
  is_default boolean not null default false,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,dashboard_code)
);

create unique index if not exists analytics_dashboards_system_unique_idx
  on public.analytics_dashboards (dashboard_code)
  where organization_id is null;

-- ============================================================
-- 7. DASHBOARD WIDGETS
-- ============================================================

create table if not exists public.analytics_dashboard_widgets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  dashboard_id uuid not null references public.analytics_dashboards(id) on delete cascade,

  widget_code text not null,
  widget_name text not null,

  widget_type text not null
    check (
      widget_type in (
        'kpi',
        'line_chart',
        'bar_chart',
        'area_chart',
        'pie_chart',
        'funnel',
        'table',
        'leaderboard',
        'heatmap',
        'cohort',
        'forecast',
        'text',
        'custom'
      )
    ),

  kpi_definition_id uuid references public.analytics_kpi_definitions(id) on delete set null,
  query_reference text,

  display_order integer not null default 100,
  width integer not null default 6,
  height integer not null default 4,

  visualization_config jsonb not null default '{}',
  filter_config jsonb not null default '{}',
  drilldown_config jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (dashboard_id,widget_code)
);

-- ============================================================
-- 8. FUNNEL DEFINITIONS
-- ============================================================

create table if not exists public.analytics_funnel_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  funnel_code text not null,
  funnel_name text not null,
  description text,

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  entity_type text not null default 'lead',
  attribution_model text not null default 'first_touch'
    check (
      attribution_model in (
        'first_touch',
        'last_touch',
        'linear',
        'time_decay',
        'custom'
      )
    ),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,funnel_code)
);

-- ============================================================
-- 9. FUNNEL STAGES
-- ============================================================

create table if not exists public.analytics_funnel_stages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  funnel_id uuid not null references public.analytics_funnel_definitions(id) on delete cascade,

  stage_order integer not null,
  stage_code text not null,
  stage_name text not null,

  source_table text,
  source_status_field text,
  accepted_values text[] not null default '{}',
  condition_expression jsonb not null default '{}',

  is_entry_stage boolean not null default false,
  is_conversion_stage boolean not null default false,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (funnel_id,stage_order),
  unique (funnel_id,stage_code)
);

-- ============================================================
-- 10. FUNNEL SNAPSHOTS
-- ============================================================

create table if not exists public.analytics_funnel_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  funnel_id uuid not null references public.analytics_funnel_definitions(id) on delete cascade,

  period_start timestamptz not null,
  period_end timestamptz not null,
  time_grain text not null default 'day',

  dimension_type text not null default 'organization',
  dimension_id uuid,
  dimension_key text,

  stage_metrics jsonb not null default '[]',
  entry_count integer not null default 0,
  conversion_count integer not null default 0,
  overall_conversion_rate numeric(10,4),
  average_cycle_time_hours numeric(18,4),

  calculated_at timestamptz not null default now(),
  metadata jsonb not null default '{}',

  unique (
    organization_id,
    funnel_id,
    period_start,
    dimension_type,
    dimension_id,
    dimension_key
  )
);

-- ============================================================
-- 11. COHORT DEFINITIONS
-- ============================================================

create table if not exists public.analytics_cohort_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  cohort_code text not null,
  cohort_name text not null,
  description text,

  entity_type text not null default 'lead',
  cohort_date_field text not null default 'created_at',
  cohort_grain text not null default 'month'
    check (cohort_grain in ('day','week','month','quarter')),

  filter_definition jsonb not null default '{}',
  metric_definition jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,cohort_code)
);

-- ============================================================
-- 12. COHORT SNAPSHOTS
-- ============================================================

create table if not exists public.analytics_cohort_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  cohort_definition_id uuid not null references public.analytics_cohort_definitions(id) on delete cascade,

  cohort_period_start date not null,
  observation_period integer not null,

  cohort_size integer not null default 0,
  retained_count integer not null default 0,
  conversion_count integer not null default 0,

  retention_rate numeric(10,4),
  conversion_rate numeric(10,4),
  average_value numeric(18,2),

  calculated_at timestamptz not null default now(),
  metadata jsonb not null default '{}',

  unique (
    organization_id,
    cohort_definition_id,
    cohort_period_start,
    observation_period
  )
);

-- ============================================================
-- 13. FORECAST MODELS
-- ============================================================

create table if not exists public.analytics_forecast_models (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  model_code text not null,
  model_name text not null,
  description text,

  forecast_type text not null
    check (
      forecast_type in (
        'lead_volume',
        'booking_volume',
        'revenue',
        'conversion_rate',
        'site_visits',
        'inventory_demand',
        'custom'
      )
    ),

  algorithm text not null default 'moving_average'
    check (
      algorithm in (
        'moving_average',
        'linear_regression',
        'seasonal',
        'weighted_pipeline',
        'manual',
        'external',
        'custom'
      )
    ),

  horizon_periods integer not null default 3,
  time_grain text not null default 'month'
    check (time_grain in ('day','week','month','quarter')),

  training_window_periods integer not null default 12,
  configuration jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  last_trained_at timestamptz,
  last_generated_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,model_code)
);

-- ============================================================
-- 14. FORECAST RESULTS
-- ============================================================

create table if not exists public.analytics_forecast_results (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  forecast_model_id uuid not null references public.analytics_forecast_models(id) on delete cascade,

  forecast_period_start date not null,
  forecast_period_end date not null,

  dimension_type text not null default 'organization',
  dimension_id uuid,
  dimension_key text,

  forecast_value numeric,
  lower_bound numeric,
  upper_bound numeric,
  confidence_score numeric(8,4),

  actual_value numeric,
  variance_value numeric,
  variance_percent numeric,

  generated_at timestamptz not null default now(),
  metadata jsonb not null default '{}',

  unique (
    organization_id,
    forecast_model_id,
    forecast_period_start,
    dimension_type,
    dimension_id,
    dimension_key
  )
);

-- ============================================================
-- 15. ANALYTICS REFRESH JOBS
-- ============================================================

create table if not exists public.analytics_refresh_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  refresh_type text not null
    check (
      refresh_type in (
        'all',
        'kpi',
        'funnel',
        'cohort',
        'forecast',
        'materialized_view',
        'dashboard',
        'custom'
      )
    ),

  target_id uuid,
  target_key text,

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'running',
        'completed',
        'failed',
        'cancelled'
      )
    ),

  priority integer not null default 100,

  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  scheduled_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  started_at timestamptz,
  completed_at timestamptz,

  result_data jsonb not null default '{}',
  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists analytics_refresh_jobs_queue_idx
  on public.analytics_refresh_jobs (
    status,
    scheduled_at,
    priority,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 16. ANALYTICS ALERT RULES
-- ============================================================

create table if not exists public.analytics_alert_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  kpi_definition_id uuid not null references public.analytics_kpi_definitions(id) on delete cascade,

  rule_code text not null,
  rule_name text not null,

  comparison_operator text not null
    check (
      comparison_operator in (
        'gt',
        'gte',
        'lt',
        'lte',
        'eq',
        'neq',
        'change_gt',
        'change_lt'
      )
    ),

  threshold_value numeric not null,
  severity text not null default 'warning'
    check (severity in ('info','warning','error','critical')),

  evaluation_grain text not null default 'day'
    check (evaluation_grain in ('hour','day','week','month')),

  notification_category_code text default 'system_alert',
  recipient_user_ids uuid[] not null default '{}',
  recipient_team_ids uuid[] not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  cooldown_minutes integer not null default 60,
  last_triggered_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,rule_code)
);

-- ============================================================
-- 17. ANALYTICS LOGS
-- ============================================================

create table if not exists public.analytics_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  refresh_job_id uuid references public.analytics_refresh_jobs(id) on delete set null,
  kpi_definition_id uuid references public.analytics_kpi_definitions(id) on delete set null,
  dashboard_id uuid references public.analytics_dashboards(id) on delete set null,

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

create index if not exists analytics_logs_org_created_idx
  on public.analytics_logs (
    organization_id,
    created_at desc
  );

-- ============================================================
-- 18. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'analytics_kpi_definitions',
    'analytics_kpi_targets',
    'analytics_kpi_snapshots',
    'analytics_dashboards',
    'analytics_dashboard_widgets',
    'analytics_funnel_definitions',
    'analytics_cohort_definitions',
    'analytics_forecast_models',
    'analytics_refresh_jobs',
    'analytics_alert_rules'
  ]
  loop
    execute format(
      'drop trigger if exists %I_set_updated_at on public.%I',
      target_table,
      target_table
    );

    execute format(
      'create trigger %I_set_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      target_table,
      target_table
    );
  end loop;
end;
$$;

-- ============================================================
-- 19. EXECUTIVE DASHBOARD VIEW
-- ============================================================

create or replace view public.analytics_executive_dashboard
with (security_invoker = true)
as
select
  o.id as organization_id,

  (select count(*) from public.leads l where l.organization_id = o.id) as total_leads,

  (select count(*) from public.lead_validation_results v
    where v.organization_id = o.id
      and v.decision in ('approved','accept','accepted','valid')) as validated_leads,

  (select count(*) from public.lead_assignments a
    where a.organization_id = o.id
      and a.status in ('assigned','accepted','active','completed')) as assigned_leads,

  (select count(*) from public.site_visits s
    where s.organization_id = o.id) as total_site_visits,

  (select count(*) from public.site_visits s
    where s.organization_id = o.id
      and s.status = 'completed') as completed_site_visits,

  (select count(*) from public.bookings b
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

  (select count(*) from public.assignment_agent_profiles p
    where p.organization_id = o.id
      and p.status = 'active') as active_agents,

  (select count(*) from public.automation_runs r
    where r.organization_id = o.id
      and r.status = 'running') as running_automations,

  (select count(*) from public.audit_security_events s
    where s.organization_id = o.id
      and s.status in ('open','investigating')) as open_security_events,

  now() as refreshed_at

from public.organizations o;

-- ============================================================
-- 20. LEAD SOURCE PERFORMANCE VIEW
-- ============================================================

create or replace view public.analytics_lead_source_performance
with (security_invoker = true)
as
select
  l.organization_id,
  coalesce(
    to_jsonb(l)->>'source',
    to_jsonb(l)->>'lead_source',
    to_jsonb(l)->>'source_type',
    'unknown'
  ) as source_name,

  count(*) as total_leads,

  count(*) filter (
    where exists (
      select 1
      from public.lead_validation_results v
      where v.organization_id = l.organization_id
        and v.lead_id = l.id
        and v.decision in ('approved','accept','accepted','valid')
    )
  ) as validated_leads,

  count(*) filter (
    where exists (
      select 1
      from public.lead_assignments a
      where a.organization_id = l.organization_id
        and a.lead_id = l.id
    )
  ) as assigned_leads,

  count(*) filter (
    where exists (
      select 1
      from public.site_visits s
      where s.organization_id = l.organization_id
        and s.lead_id = l.id
    )
  ) as site_visit_leads,

  count(*) filter (
    where exists (
      select 1
      from public.bookings b
      where b.organization_id = l.organization_id
        and b.lead_id = l.id
    )
  ) as booked_leads,

  round(
    count(*) filter (
      where exists (
        select 1
        from public.bookings b
        where b.organization_id = l.organization_id
          and b.lead_id = l.id
      )
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as booking_conversion_rate

from public.leads l
group by
  l.organization_id,
  coalesce(
    to_jsonb(l)->>'source',
    to_jsonb(l)->>'lead_source',
    to_jsonb(l)->>'source_type',
    'unknown'
  );

-- ============================================================
-- 21. AGENT PERFORMANCE VIEW
-- ============================================================

create or replace view public.analytics_agent_performance
with (security_invoker = true)
as
select
  p.organization_id,
  p.id as agent_profile_id,
  p.user_id,
  p.display_name,

  count(distinct a.id) as total_assignments,

  count(distinct a.id) filter (
    where a.status in ('accepted','active','completed')
  ) as accepted_assignments,

  count(distinct a.id) filter (
    where a.first_response_at is not null
  ) as responded_assignments,

  count(distinct s.id) as site_visits,

  count(distinct s.id) filter (
    where s.status = 'completed'
  ) as completed_site_visits,

  count(distinct b.id) as bookings,

  round(
    count(distinct b.id)::numeric
    / nullif(count(distinct a.lead_id),0) * 100,
    2
  ) as lead_to_booking_conversion_rate,

  round(
    avg(
      extract(
        epoch from (
          a.first_response_at - a.assigned_at
        )
      ) / 60
    ) filter (
      where a.first_response_at is not null
    ),
    2
  ) as average_first_response_minutes,

  p.performance_score,
  p.response_score,
  p.conversion_score,
  p.quality_score

from public.assignment_agent_profiles p
left join public.lead_assignments a
  on a.agent_profile_id = p.id
left join public.site_visits s
  on s.lead_id = a.lead_id
  and s.organization_id = p.organization_id
left join public.bookings b
  on b.lead_id = a.lead_id
  and b.organization_id = p.organization_id
group by p.id;

-- ============================================================
-- 22. PROJECT PERFORMANCE VIEW
-- ============================================================

create or replace view public.analytics_project_performance
with (security_invoker = true)
as
select
  i.organization_id,
  coalesce(
    to_jsonb(i)->>'project_id',
    to_jsonb(i)->>'project_name',
    'unknown'
  ) as project_key,

  count(*) as inventory_units,

  count(*) filter (
    where coalesce(
      to_jsonb(i)->>'status',
      to_jsonb(i)->>'availability_status',
      ''
    ) in ('available','active','open')
  ) as available_units,

  count(distinct s.id) as site_visits,
  count(distinct b.id) as bookings,

  round(
    count(distinct b.id)::numeric
    / nullif(count(distinct s.id),0) * 100,
    2
  ) as visit_to_booking_conversion_rate

from public.inventory_units i
left join public.site_visits s
  on s.organization_id = i.organization_id
  and (
    to_jsonb(s)->>'project_id' = to_jsonb(i)->>'project_id'
    or to_jsonb(s)->>'project_name' = to_jsonb(i)->>'project_name'
  )
left join public.bookings b
  on b.organization_id = i.organization_id
  and (
    to_jsonb(b)->>'project_id' = to_jsonb(i)->>'project_id'
    or to_jsonb(b)->>'project_name' = to_jsonb(i)->>'project_name'
  )
group by
  i.organization_id,
  coalesce(
    to_jsonb(i)->>'project_id',
    to_jsonb(i)->>'project_name',
    'unknown'
  );

-- ============================================================
-- 23. FUNNEL VIEW
-- ============================================================

create or replace view public.analytics_sales_funnel
with (security_invoker = true)
as
select
  o.id as organization_id,

  (select count(*) from public.leads l
    where l.organization_id = o.id) as leads,

  (select count(distinct v.lead_id)
    from public.lead_validation_results v
    where v.organization_id = o.id
      and v.decision in ('approved','accept','accepted','valid')) as validated,

  (select count(distinct a.lead_id)
    from public.lead_assignments a
    where a.organization_id = o.id) as assigned,

  (select count(distinct s.lead_id)
    from public.site_visits s
    where s.organization_id = o.id) as site_visit,

  (select count(distinct s.lead_id)
    from public.site_visits s
    where s.organization_id = o.id
      and s.status = 'completed') as site_visit_completed,

  (select count(distinct b.lead_id)
    from public.bookings b
    where b.organization_id = o.id) as booked

from public.organizations o;

-- ============================================================
-- 24. DAILY SALES TIMESERIES VIEW
-- ============================================================

create or replace view public.analytics_daily_sales_timeseries
with (security_invoker = true)
as
select
  x.organization_id,
  x.metric_date,

  sum(x.leads) as leads,
  sum(x.validated_leads) as validated_leads,
  sum(x.assignments) as assignments,
  sum(x.site_visits) as site_visits,
  sum(x.bookings) as bookings,
  sum(x.booking_value) as booking_value

from (
  select
    l.organization_id,
    l.created_at::date as metric_date,
    count(*) as leads,
    0::bigint as validated_leads,
    0::bigint as assignments,
    0::bigint as site_visits,
    0::bigint as bookings,
    0::numeric as booking_value
  from public.leads l
  group by l.organization_id,l.created_at::date

  union all

  select
    v.organization_id,
    v.created_at::date,
    0,
    count(*) filter (
      where v.decision in ('approved','accept','accepted','valid')
    ),
    0,0,0,0
  from public.lead_validation_results v
  group by v.organization_id,v.created_at::date

  union all

  select
    a.organization_id,
    a.assigned_at::date,
    0,0,count(*),0,0,0
  from public.lead_assignments a
  group by a.organization_id,a.assigned_at::date

  union all

  select
    s.organization_id,
    coalesce(
      nullif(to_jsonb(s)->>'scheduled_at','')::timestamptz,
      s.created_at
    )::date,
    0,0,0,count(*),0,0
  from public.site_visits s
  group by
    s.organization_id,
    coalesce(
      nullif(to_jsonb(s)->>'scheduled_at','')::timestamptz,
      s.created_at
    )::date

  union all

  select
    b.organization_id,
    b.created_at::date,
    0,0,0,0,count(*),
    coalesce(sum(
      coalesce(
        nullif(to_jsonb(b)->>'booking_amount','')::numeric,
        nullif(to_jsonb(b)->>'amount','')::numeric,
        nullif(to_jsonb(b)->>'total_amount','')::numeric,
        0
      )
    ),0)
  from public.bookings b
  group by b.organization_id,b.created_at::date
) x
group by x.organization_id,x.metric_date;

-- ============================================================
-- 25. OPERATIONS QUALITY VIEW
-- ============================================================

create or replace view public.analytics_operations_quality
with (security_invoker = true)
as
select
  o.id as organization_id,

  (select count(*) from public.lead_validation_results v
    where v.organization_id = o.id
      and v.decision in ('rejected','reject','invalid')) as rejected_leads,

  (select count(*) from public.lead_duplicate_matches d
    where d.organization_id = o.id
      and d.status in ('detected','confirmed')) as duplicate_matches,

  (select count(*) from public.assignment_requests r
    where r.organization_id = o.id
      and r.status = 'manual_review') as assignment_manual_review,

  (select count(*) from public.communication_message_jobs j
    where j.organization_id = o.id
      and j.status = 'failed') as failed_communications,

  (select count(*) from public.automation_runs r
    where r.organization_id = o.id
      and r.status = 'failed') as failed_automations,

  (select count(*) from public.notification_jobs n
    where n.organization_id = o.id
      and n.status = 'failed') as failed_notifications,

  (select count(*) from public.audit_security_events s
    where s.organization_id = o.id
      and s.status in ('open','investigating')) as open_security_events

from public.organizations o;

-- ============================================================
-- 26. COMMUNICATION PERFORMANCE VIEW
-- ============================================================

create or replace view public.analytics_communication_performance
with (security_invoker = true)
as
select
  organization_id,
  channel_code,

  count(*) as total_messages,

  count(*) filter (
    where status in ('sent','delivered','read')
  ) as sent_messages,

  count(*) filter (
    where status in ('delivered','read')
  ) as delivered_messages,

  count(*) filter (
    where status = 'read'
  ) as read_messages,

  count(*) filter (
    where status = 'failed'
  ) as failed_messages,

  round(
    count(*) filter (
      where status in ('delivered','read')
    )::numeric
    / nullif(
      count(*) filter (
        where direction = 'outbound'
      ),
      0
    ) * 100,
    2
  ) as delivery_rate,

  round(
    count(*) filter (
      where status = 'read'
    )::numeric
    / nullif(
      count(*) filter (
        where status in ('delivered','read')
      ),
      0
    ) * 100,
    2
  ) as read_rate

from public.communication_message_jobs
group by organization_id,channel_code;

-- ============================================================
-- 27. AUTOMATION PERFORMANCE VIEW
-- ============================================================

create or replace view public.analytics_automation_performance
with (security_invoker = true)
as
select
  r.organization_id,
  r.automation_id,
  d.automation_code,
  d.automation_name,

  count(*) as total_runs,

  count(*) filter (
    where r.status = 'completed'
  ) as completed_runs,

  count(*) filter (
    where r.status = 'failed'
  ) as failed_runs,

  round(
    count(*) filter (
      where r.status = 'completed'
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as success_rate,

  round(
    avg(
      extract(
        epoch from (
          coalesce(r.completed_at,r.failed_at,now())
          - coalesce(r.started_at,r.created_at)
        )
      )
    ),
    2
  ) as average_duration_seconds

from public.automation_runs r
join public.automation_definitions d
  on d.id = r.automation_id
group by
  r.organization_id,
  r.automation_id,
  d.automation_code,
  d.automation_name;

-- ============================================================
-- 28. MATERIALIZED DAILY ORG SUMMARY
-- ============================================================

create materialized view if not exists public.analytics_mv_daily_org_summary
as
select
  d.organization_id,
  d.metric_date,
  d.leads,
  d.validated_leads,
  d.assignments,
  d.site_visits,
  d.bookings,
  d.booking_value,

  round(
    d.validated_leads::numeric
    / nullif(d.leads,0) * 100,
    2
  ) as validation_rate,

  round(
    d.bookings::numeric
    / nullif(d.leads,0) * 100,
    2
  ) as lead_to_booking_rate

from public.analytics_daily_sales_timeseries d
with no data;

create unique index if not exists analytics_mv_daily_org_summary_unique_idx
  on public.analytics_mv_daily_org_summary (
    organization_id,
    metric_date
  );

-- ============================================================
-- 29. REFRESH MATERIALIZED VIEWS
-- ============================================================

create or replace function public.refresh_analytics_materialized_views()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  started_at_value timestamptz := clock_timestamp();
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may refresh analytics materialized views';
  end if;

  refresh materialized view public.analytics_mv_daily_org_summary;

  return jsonb_build_object(
    'status',
    'completed',
    'refreshed_views',
    jsonb_build_array(
      'analytics_mv_daily_org_summary'
    ),
    'duration_ms',
    extract(
      epoch from (
        clock_timestamp() - started_at_value
      )
    ) * 1000,
    'completed_at',
    now()
  );
end;
$$;

revoke all
on function public.refresh_analytics_materialized_views()
from public;

grant execute
on function public.refresh_analytics_materialized_views()
to service_role;

-- ============================================================
-- 30. QUEUE REFRESH JOB
-- ============================================================

create or replace function public.create_analytics_refresh_job(
  requested_organization_id uuid default null,
  requested_refresh_type text default 'all',
  requested_target_id uuid default null,
  requested_target_key text default null,
  requested_priority integer default 100,
  requested_scheduled_at timestamptz default now()
)
returns public.analytics_refresh_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.analytics_refresh_jobs;
begin
  if auth.role() <> 'service_role'
    and (
      requested_organization_id is null
      or not public.has_organization_permission(
        requested_organization_id,
        'analytics.refresh'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.analytics_refresh_jobs (
    organization_id,
    refresh_type,
    target_id,
    target_key,
    status,
    priority,
    requested_by,
    requested_at,
    scheduled_at
  )
  values (
    requested_organization_id,
    requested_refresh_type,
    requested_target_id,
    requested_target_key,
    'queued',
    requested_priority,
    auth.uid(),
    now(),
    coalesce(requested_scheduled_at,now())
  )
  returning * into job_record;

  return job_record;
end;
$$;

revoke all
on function public.create_analytics_refresh_job(
  uuid,text,uuid,text,integer,timestamptz
)
from public;

grant execute
on function public.create_analytics_refresh_job(
  uuid,text,uuid,text,integer,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 31. CLAIM REFRESH JOB
-- ============================================================

create or replace function public.claim_analytics_refresh_job(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.analytics_refresh_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.analytics_refresh_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim analytics refresh jobs';
  end if;

  select *
  into job_record
  from public.analytics_refresh_jobs j
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

  update public.analytics_refresh_jobs
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
on function public.claim_analytics_refresh_job(text,uuid,integer)
from public;

grant execute
on function public.claim_analytics_refresh_job(text,uuid,integer)
to service_role;

-- ============================================================
-- 32. COMPLETE REFRESH JOB
-- ============================================================

create or replace function public.complete_analytics_refresh_job(
  requested_job_id uuid,
  requested_lock_token text,
  requested_result_data jsonb default '{}'::jsonb
)
returns public.analytics_refresh_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.analytics_refresh_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete analytics refresh jobs';
  end if;

  select *
  into job_record
  from public.analytics_refresh_jobs
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Analytics refresh job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid analytics refresh lock token';
  end if;

  update public.analytics_refresh_jobs
  set
    status = 'completed',
    started_at = coalesce(started_at,claimed_at,now()),
    completed_at = now(),
    result_data = coalesce(requested_result_data,'{}'::jsonb),
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where id = requested_job_id
  returning * into job_record;

  return job_record;
end;
$$;

revoke all
on function public.complete_analytics_refresh_job(uuid,text,jsonb)
from public;

grant execute
on function public.complete_analytics_refresh_job(uuid,text,jsonb)
to service_role;

-- ============================================================
-- 33. EXECUTIVE KPI SUMMARY FUNCTION
-- ============================================================

create or replace function public.get_analytics_executive_summary(
  requested_organization_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result_data jsonb;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'analytics.view'
    )
    and not public.has_organization_permission(
      requested_organization_id,
      'analytics.view_all'
    ) then
    raise exception 'Permission denied';
  end if;

  select to_jsonb(d)
  into result_data
  from public.analytics_executive_dashboard d
  where d.organization_id = requested_organization_id;

  return coalesce(result_data,'{}'::jsonb);
end;
$$;

revoke all
on function public.get_analytics_executive_summary(uuid)
from public;

grant execute
on function public.get_analytics_executive_summary(uuid)
to authenticated,service_role;

-- ============================================================
-- 34. ANALYTICS HEALTH CHECK
-- ============================================================

create or replace function public.get_analytics_engine_health(
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
        'analytics.view_health'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',
    requested_organization_id,
    'checked_at',
    now(),

    'active_kpis',
    (
      select count(*)
      from public.analytics_kpi_definitions k
      where k.status = 'active'
        and (
          k.organization_id is null
          or requested_organization_id is null
          or k.organization_id = requested_organization_id
        )
    ),

    'active_dashboards',
    (
      select count(*)
      from public.analytics_dashboards d
      where d.status = 'active'
        and (
          d.organization_id is null
          or requested_organization_id is null
          or d.organization_id = requested_organization_id
        )
    ),

    'queued_refresh_jobs',
    (
      select count(*)
      from public.analytics_refresh_jobs j
      where j.status in ('queued','claimed','running','failed')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'stale_snapshots',
    (
      select count(*)
      from public.analytics_kpi_snapshots s
      where s.status = 'stale'
        and (
          requested_organization_id is null
          or s.organization_id = requested_organization_id
        )
    ),

    'active_alert_rules',
    (
      select count(*)
      from public.analytics_alert_rules a
      where a.status = 'active'
        and (
          requested_organization_id is null
          or a.organization_id = requested_organization_id
        )
    ),

    'latest_daily_summary_date',
    (
      select max(metric_date)
      from public.analytics_mv_daily_org_summary s
      where (
        requested_organization_id is null
        or s.organization_id = requested_organization_id
      )
    )
  );
end;
$$;

revoke all
on function public.get_analytics_engine_health(uuid)
from public;

grant execute
on function public.get_analytics_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 35. RLS
-- ============================================================

alter table public.analytics_kpi_definitions enable row level security;
alter table public.analytics_kpi_targets enable row level security;
alter table public.analytics_kpi_snapshots enable row level security;
alter table public.analytics_dashboards enable row level security;
alter table public.analytics_dashboard_widgets enable row level security;
alter table public.analytics_funnel_definitions enable row level security;
alter table public.analytics_funnel_stages enable row level security;
alter table public.analytics_funnel_snapshots enable row level security;
alter table public.analytics_cohort_definitions enable row level security;
alter table public.analytics_cohort_snapshots enable row level security;
alter table public.analytics_forecast_models enable row level security;
alter table public.analytics_forecast_results enable row level security;
alter table public.analytics_refresh_jobs enable row level security;
alter table public.analytics_alert_rules enable row level security;
alter table public.analytics_logs enable row level security;

drop policy if exists analytics_kpi_definitions_select
on public.analytics_kpi_definitions;

create policy analytics_kpi_definitions_select
on public.analytics_kpi_definitions
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'analytics.view'
  )
  or public.has_organization_permission(
    organization_id,
    'analytics.view_all'
  )
);

drop policy if exists analytics_dashboards_select
on public.analytics_dashboards;

create policy analytics_dashboards_select
on public.analytics_dashboards
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'analytics.view'
  )
  or public.has_organization_permission(
    organization_id,
    'analytics.view_all'
  )
);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'analytics_kpi_targets',
    'analytics_kpi_snapshots',
    'analytics_dashboard_widgets',
    'analytics_funnel_definitions',
    'analytics_funnel_stages',
    'analytics_funnel_snapshots',
    'analytics_cohort_definitions',
    'analytics_cohort_snapshots',
    'analytics_forecast_models',
    'analytics_forecast_results',
    'analytics_refresh_jobs',
    'analytics_alert_rules',
    'analytics_logs'
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
           ''analytics.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''analytics.view_all''
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

drop policy if exists analytics_kpi_definitions_write
on public.analytics_kpi_definitions;

create policy analytics_kpi_definitions_write
on public.analytics_kpi_definitions
for all
to authenticated
using (
  organization_id is not null
  and public.has_organization_permission(
    organization_id,
    'analytics.manage_kpis'
  )
)
with check (
  organization_id is not null
  and public.has_organization_permission(
    organization_id,
    'analytics.manage_kpis'
  )
);

drop policy if exists analytics_kpi_targets_write
on public.analytics_kpi_targets;

create policy analytics_kpi_targets_write
on public.analytics_kpi_targets
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'analytics.manage_targets'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'analytics.manage_targets'
  )
);

drop policy if exists analytics_dashboards_write
on public.analytics_dashboards;

create policy analytics_dashboards_write
on public.analytics_dashboards
for all
to authenticated
using (
  organization_id is not null
  and public.has_organization_permission(
    organization_id,
    'analytics.manage_dashboards'
  )
)
with check (
  organization_id is not null
  and public.has_organization_permission(
    organization_id,
    'analytics.manage_dashboards'
  )
);

-- ============================================================
-- 36. GRANTS
-- ============================================================

grant select
on
  public.analytics_kpi_definitions,
  public.analytics_kpi_targets,
  public.analytics_kpi_snapshots,
  public.analytics_dashboards,
  public.analytics_dashboard_widgets,
  public.analytics_funnel_definitions,
  public.analytics_funnel_stages,
  public.analytics_funnel_snapshots,
  public.analytics_cohort_definitions,
  public.analytics_cohort_snapshots,
  public.analytics_forecast_models,
  public.analytics_forecast_results,
  public.analytics_refresh_jobs,
  public.analytics_alert_rules,
  public.analytics_logs
to authenticated;

grant insert,update,delete
on
  public.analytics_kpi_definitions,
  public.analytics_kpi_targets,
  public.analytics_dashboards,
  public.analytics_dashboard_widgets,
  public.analytics_funnel_definitions,
  public.analytics_funnel_stages,
  public.analytics_cohort_definitions,
  public.analytics_forecast_models,
  public.analytics_alert_rules
to authenticated;

grant select
on
  public.analytics_executive_dashboard,
  public.analytics_lead_source_performance,
  public.analytics_agent_performance,
  public.analytics_project_performance,
  public.analytics_sales_funnel,
  public.analytics_daily_sales_timeseries,
  public.analytics_operations_quality,
  public.analytics_communication_performance,
  public.analytics_automation_performance,
  public.analytics_mv_daily_org_summary
to authenticated,service_role;

grant all
on
  public.analytics_kpi_definitions,
  public.analytics_kpi_targets,
  public.analytics_kpi_snapshots,
  public.analytics_dashboards,
  public.analytics_dashboard_widgets,
  public.analytics_funnel_definitions,
  public.analytics_funnel_stages,
  public.analytics_funnel_snapshots,
  public.analytics_cohort_definitions,
  public.analytics_cohort_snapshots,
  public.analytics_forecast_models,
  public.analytics_forecast_results,
  public.analytics_refresh_jobs,
  public.analytics_alert_rules,
  public.analytics_logs
to service_role;

-- ============================================================
-- 37. INITIAL MATERIALIZED VIEW REFRESH
-- ============================================================

refresh materialized view public.analytics_mv_daily_org_summary;

-- ============================================================
-- 38. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'analytics_kpi_definitions',
    'analytics_kpi_targets',
    'analytics_kpi_snapshots',
    'analytics_dashboards',
    'analytics_dashboard_widgets',
    'analytics_funnel_definitions',
    'analytics_funnel_stages',
    'analytics_funnel_snapshots',
    'analytics_cohort_definitions',
    'analytics_cohort_snapshots',
    'analytics_forecast_models',
    'analytics_forecast_results',
    'analytics_refresh_jobs',
    'analytics_alert_rules',
    'analytics_logs'
  ]
  loop
    if not exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = item
    ) then
      missing_items :=
        array_append(
          missing_items,
          'table:' || item
        );
    end if;
  end loop;

  foreach item in array array[
    'refresh_analytics_materialized_views',
    'create_analytics_refresh_job',
    'claim_analytics_refresh_job',
    'complete_analytics_refresh_job',
    'get_analytics_executive_summary',
    'get_analytics_engine_health'
  ]
  loop
    if not exists (
      select 1
      from information_schema.routines
      where routine_schema = 'public'
        and routine_name = item
    ) then
      missing_items :=
        array_append(
          missing_items,
          'function:' || item
        );
    end if;
  end loop;

  if cardinality(missing_items) > 0 then
    raise exception
      '017 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 39. MIGRATION AUDIT
-- ============================================================

insert into public.analytics_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.017.completed',
  'Analytics & BI Engine migration 017 completed',
  jsonb_build_object(
    'migration',
    '017_analytics_bi_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'kpi_definitions',
      'targets',
      'snapshots',
      'dashboards',
      'widgets',
      'funnels',
      'cohorts',
      'forecasts',
      'refresh_jobs',
      'alerts',
      'executive_dashboard',
      'sales_funnel',
      'agent_performance',
      'project_performance',
      'lead_source_performance',
      'communication_performance',
      'automation_performance',
      'materialized_rollups'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.analytics_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.017.completed'
);

commit;