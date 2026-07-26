-- ============================================================
-- SalesSetu Enterprise
-- Migration 030: Observability, Monitoring & Reliability Engine
-- PostgreSQL / Supabase
-- ============================================================
-- Provides service catalog, metrics, logs, traces, heartbeats,
-- synthetic monitoring, SLI/SLO tracking, error budgets, alerting,
-- incidents, escalation, on-call schedules, maintenance windows,
-- deployment correlation, retention, analytics, RLS and event hooks.
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- 1. Permissions
insert into public.permissions (module,action,code,description)
select v.module,v.action,v.code,v.description
from (
  values
    ('observability_reliability','view','observability_reliability.view','View observability data'),
    ('observability_reliability','view_all','observability_reliability.view_all','View all organization observability data'),
    ('observability_reliability','manage_services','observability_reliability.manage_services','Manage monitored services'),
    ('observability_reliability','manage_telemetry','observability_reliability.manage_telemetry','Manage telemetry definitions'),
    ('observability_reliability','ingest_telemetry','observability_reliability.ingest_telemetry','Ingest telemetry'),
    ('observability_reliability','manage_monitors','observability_reliability.manage_monitors','Manage monitors'),
    ('observability_reliability','manage_slos','observability_reliability.manage_slos','Manage SLI and SLO definitions'),
    ('observability_reliability','manage_alerts','observability_reliability.manage_alerts','Manage alerts'),
    ('observability_reliability','acknowledge_alerts','observability_reliability.acknowledge_alerts','Acknowledge incidents'),
    ('observability_reliability','manage_incidents','observability_reliability.manage_incidents','Manage reliability incidents'),
    ('observability_reliability','manage_oncall','observability_reliability.manage_oncall','Manage on-call and escalation'),
    ('observability_reliability','manage_maintenance','observability_reliability.manage_maintenance','Manage maintenance windows'),
    ('observability_reliability','manage_runbooks','observability_reliability.manage_runbooks','Manage runbooks'),
    ('observability_reliability','manage_retention','observability_reliability.manage_retention','Manage telemetry retention'),
    ('observability_reliability','view_logs','observability_reliability.view_logs','View observability logs'),
    ('observability_reliability','view_analytics','observability_reliability.view_analytics','View observability analytics')
) v(module,action,code,description)
where not exists (
  select 1 from public.permissions p where p.code=v.code
);

-- 2. Core service catalog
create table if not exists public.observability_environments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_code text not null,
  environment_name text not null,
  environment_type text not null default 'production'
    check (environment_type in ('development','testing','staging','uat','production','disaster_recovery','sandbox','custom')),
  region text,
  cloud_provider text,
  base_url text,
  criticality text not null default 'high' check (criticality in ('low','medium','high','critical')),
  status text not null default 'active' check (status in ('active','maintenance','degraded','inactive','archived')),
  timezone text not null default 'Asia/Kolkata',
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,environment_code)
);

create table if not exists public.observability_services (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.observability_environments(id) on delete cascade,
  service_code text not null,
  service_name text not null,
  description text,
  service_type text not null check (service_type in (
    'web_application','api','worker','database','queue','cache','storage',
    'integration','automation','ai_service','mobile_backend','scheduled_job',
    'network','external_dependency','custom'
  )),
  owner_user_id uuid references auth.users(id) on delete set null,
  owning_team_reference text,
  criticality text not null default 'high' check (criticality in ('low','medium','high','critical')),
  lifecycle_status text not null default 'active'
    check (lifecycle_status in ('planned','development','active','maintenance','deprecated','retired','archived')),
  health_status text not null default 'unknown'
    check (health_status in ('unknown','healthy','degraded','unhealthy','maintenance','offline')),
  health_status_reason text,
  health_last_changed_at timestamptz,
  last_heartbeat_at timestamptz,
  service_url text,
  repository_reference text,
  documentation_reference text,
  expected_heartbeat_interval_seconds integer,
  heartbeat_grace_seconds integer not null default 60,
  tags text[] not null default '{}',
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,environment_id,service_code)
);

create index if not exists observability_services_health_idx
on public.observability_services(organization_id,environment_id,health_status,criticality);

create table if not exists public.observability_service_dependencies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  upstream_service_id uuid not null references public.observability_services(id) on delete cascade,
  downstream_service_id uuid not null references public.observability_services(id) on delete cascade,
  dependency_type text not null default 'synchronous'
    check (dependency_type in ('synchronous','asynchronous','data','authentication','network','storage','external','custom')),
  criticality text not null default 'high' check (criticality in ('low','medium','high','critical')),
  failure_behavior text not null default 'degrade'
    check (failure_behavior in ('ignore','degrade','fail_closed','fail_open','retry','queue','custom')),
  timeout_ms integer,
  maximum_retries integer,
  enabled boolean not null default true,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (upstream_service_id<>downstream_service_id),
  unique (upstream_service_id,downstream_service_id,dependency_type)
);

create table if not exists public.observability_telemetry_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  source_code text not null,
  source_name text not null,
  source_type text not null check (source_type in (
    'application','database','agent','open_telemetry','webhook','synthetic',
    'cloud_provider','integration','mobile','browser','custom'
  )),
  protocol text,
  endpoint_reference text,
  credential_reference text,
  status text not null default 'active' check (status in ('active','degraded','inactive','error','archived')),
  last_seen_at timestamptz,
  last_error_at timestamptz,
  last_error_message text,
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,service_id,source_code)
);

-- 3. Metrics, logs, traces and heartbeats
create table if not exists public.observability_metric_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  metric_code text not null,
  metric_name text not null,
  description text,
  metric_type text not null default 'gauge'
    check (metric_type in ('counter','gauge','histogram','summary','rate','duration','percentage','currency','custom')),
  unit text,
  aggregation_method text not null default 'average'
    check (aggregation_method in ('sum','average','minimum','maximum','count','p50','p75','p90','p95','p99','last','custom')),
  expected_minimum numeric,
  expected_maximum numeric,
  higher_is_better boolean,
  retention_days integer not null default 30 check (retention_days>=1),
  status text not null default 'active' check (status in ('active','inactive','deprecated','archived')),
  labels_schema jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,service_id,metric_code)
);

create table if not exists public.observability_metric_samples (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.observability_environments(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  telemetry_source_id uuid references public.observability_telemetry_sources(id) on delete set null,
  metric_definition_id uuid not null references public.observability_metric_definitions(id) on delete cascade,
  numeric_value numeric not null,
  labels jsonb not null default '{}',
  attributes jsonb not null default '{}',
  observed_at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  idempotency_key text,
  correlation_id text,
  trace_id text,
  created_at timestamptz not null default now()
);
create index if not exists observability_metric_samples_query_idx
on public.observability_metric_samples(organization_id,service_id,metric_definition_id,observed_at desc);
create unique index if not exists observability_metric_samples_idem_idx
on public.observability_metric_samples(organization_id,idempotency_key)
where idempotency_key is not null;

create table if not exists public.observability_log_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.observability_environments(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  telemetry_source_id uuid references public.observability_telemetry_sources(id) on delete set null,
  log_level text not null default 'info'
    check (log_level in ('trace','debug','info','notice','warning','error','critical','alert','emergency')),
  event_name text,
  message text not null,
  logger_name text,
  operation_name text,
  error_type text,
  error_code text,
  error_message text,
  stack_trace text,
  user_id uuid references auth.users(id) on delete set null,
  related_entity_type text,
  related_entity_id uuid,
  attributes jsonb not null default '{}',
  occurred_at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  correlation_id text,
  trace_id text,
  span_id text,
  fingerprint text,
  idempotency_key text,
  created_at timestamptz not null default now()
);
create index if not exists observability_log_events_query_idx
on public.observability_log_events(organization_id,service_id,log_level,occurred_at desc);
create index if not exists observability_log_events_trace_idx
on public.observability_log_events(organization_id,trace_id,occurred_at)
where trace_id is not null;
create unique index if not exists observability_log_events_idem_idx
on public.observability_log_events(organization_id,idempotency_key)
where idempotency_key is not null;

create table if not exists public.observability_traces (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.observability_environments(id) on delete cascade,
  root_service_id uuid references public.observability_services(id) on delete set null,
  trace_id text not null,
  trace_name text,
  operation_name text,
  status text not null default 'in_progress'
    check (status in ('in_progress','ok','error','cancelled','timed_out')),
  started_at timestamptz not null,
  ended_at timestamptz,
  duration_ms bigint,
  root_span_id text,
  error_count integer not null default 0,
  span_count integer not null default 0,
  attributes jsonb not null default '{}',
  resource_attributes jsonb not null default '{}',
  correlation_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,trace_id)
);

create table if not exists public.observability_trace_spans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  trace_record_id uuid not null references public.observability_traces(id) on delete cascade,
  service_id uuid references public.observability_services(id) on delete set null,
  span_id text not null,
  parent_span_id text,
  span_name text not null,
  operation_name text,
  span_kind text not null default 'internal'
    check (span_kind in ('internal','server','client','producer','consumer')),
  status text not null default 'unset' check (status in ('unset','ok','error')),
  started_at timestamptz not null,
  ended_at timestamptz,
  duration_ms bigint,
  error_type text,
  error_message text,
  attributes jsonb not null default '{}',
  events jsonb not null default '[]',
  links jsonb not null default '[]',
  created_at timestamptz not null default now(),
  unique (trace_record_id,span_id)
);

create table if not exists public.observability_heartbeats (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.observability_environments(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  telemetry_source_id uuid references public.observability_telemetry_sources(id) on delete set null,
  heartbeat_status text not null default 'healthy'
    check (heartbeat_status in ('healthy','degraded','unhealthy','starting','stopping','maintenance','unknown')),
  response_time_ms integer,
  version text,
  instance_reference text,
  region text,
  health_details jsonb not null default '{}',
  dependency_health jsonb not null default '{}',
  observed_at timestamptz not null default now(),
  received_at timestamptz not null default now(),
  idempotency_key text,
  created_at timestamptz not null default now()
);
create index if not exists observability_heartbeats_service_idx
on public.observability_heartbeats(organization_id,service_id,observed_at desc);
create unique index if not exists observability_heartbeats_idem_idx
on public.observability_heartbeats(organization_id,idempotency_key)
where idempotency_key is not null;

-- 4. SLI, SLO and error budgets
create table if not exists public.observability_sli_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  sli_code text not null,
  sli_name text not null,
  description text,
  sli_type text not null check (sli_type in (
    'availability','latency','throughput','error_rate','freshness','durability',
    'correctness','queue_lag','custom'
  )),
  measurement_source text not null check (measurement_source in (
    'metric','monitor','log','trace','heartbeat','query','external','custom'
  )),
  metric_definition_id uuid references public.observability_metric_definitions(id) on delete set null,
  good_event_expression jsonb not null default '{}',
  valid_event_expression jsonb not null default '{}',
  threshold_operator text,
  threshold_value numeric,
  threshold_secondary_value numeric,
  aggregation_window_seconds integer not null default 300,
  status text not null default 'active' check (status in ('draft','active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,service_id,sli_code)
);

create table if not exists public.observability_slos (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  sli_definition_id uuid not null references public.observability_sli_definitions(id) on delete cascade,
  slo_code text not null,
  slo_name text not null,
  description text,
  target_percentage numeric(9,6) not null check (target_percentage>0 and target_percentage<=100),
  window_type text not null default 'rolling' check (window_type in ('rolling','calendar')),
  window_duration_days integer not null default 30 check (window_duration_days>=1),
  calendar_period text,
  warning_burn_rate numeric(12,6) not null default 2,
  critical_burn_rate numeric(12,6) not null default 10,
  minimum_event_count bigint not null default 1,
  status text not null default 'active' check (status in ('draft','active','paused','inactive','archived')),
  owner_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,service_id,slo_code)
);

create table if not exists public.observability_slo_measurements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  slo_id uuid not null references public.observability_slos(id) on delete cascade,
  window_start timestamptz not null,
  window_end timestamptz not null,
  good_events bigint not null default 0 check (good_events>=0),
  valid_events bigint not null default 0 check (valid_events>=0),
  bad_events bigint generated always as (greatest(valid_events-good_events,0)) stored,
  achievement_percentage numeric(12,8),
  burn_rate numeric(18,8),
  target_met boolean,
  measurement_status text not null default 'complete'
    check (measurement_status in ('partial','complete','estimated','invalid')),
  source_data jsonb not null default '{}',
  measured_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (window_end>window_start),
  check (good_events<=valid_events),
  unique (slo_id,window_start,window_end)
);

create table if not exists public.observability_error_budget_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  slo_id uuid not null references public.observability_slos(id) on delete cascade,
  period_start timestamptz not null,
  period_end timestamptz not null,
  total_budget_events numeric,
  consumed_budget_events numeric,
  remaining_budget_events numeric,
  budget_consumed_percentage numeric(12,8),
  remaining_percentage numeric(12,8),
  current_burn_rate numeric(18,8),
  budget_status text not null default 'healthy'
    check (budget_status in ('healthy','warning','critical','exhausted','unknown')),
  forecast_exhaustion_at timestamptz,
  calculation_data jsonb not null default '{}',
  calculated_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  check (period_end>period_start),
  unique (slo_id,period_start,period_end)
);

-- 5. Alerting and synthetic monitoring
create table if not exists public.observability_escalation_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  policy_code text not null,
  policy_name text not null,
  description text,
  repeat_enabled boolean not null default false,
  maximum_repeats integer not null default 0,
  stop_on_acknowledgement boolean not null default true,
  stop_on_resolution boolean not null default true,
  status text not null default 'active' check (status in ('draft','active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,policy_code)
);

create table if not exists public.observability_escalation_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  escalation_policy_id uuid not null references public.observability_escalation_policies(id) on delete cascade,
  step_number integer not null,
  delay_minutes integer not null default 0,
  target_type text not null check (target_type in ('user','users','oncall_schedule','team','webhook','custom')),
  target_user_ids uuid[] not null default '{}',
  target_reference text,
  notification_channels text[] not null default array['in_app']::text[],
  acknowledgement_timeout_minutes integer,
  configuration jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (escalation_policy_id,step_number)
);

create table if not exists public.observability_alert_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid references public.observability_environments(id) on delete cascade,
  service_id uuid references public.observability_services(id) on delete cascade,
  alert_code text not null,
  alert_name text not null,
  description text,
  alert_type text not null check (alert_type in (
    'metric_threshold','log_pattern','trace_error','heartbeat_missing','monitor_failure',
    'slo_burn','error_budget','queue_lag','capacity','security_signal','custom'
  )),
  severity text not null default 'warning' check (severity in ('info','warning','high','critical')),
  evaluation_expression jsonb not null default '{}',
  evaluation_interval_seconds integer not null default 60 check (evaluation_interval_seconds>=10),
  lookback_seconds integer not null default 300 check (lookback_seconds>=10),
  minimum_failure_count integer not null default 1,
  recovery_count integer not null default 1,
  auto_resolve boolean not null default true,
  create_incident boolean not null default true,
  deduplication_window_seconds integer not null default 900,
  suppression_window_seconds integer not null default 0,
  escalation_policy_id uuid references public.observability_escalation_policies(id) on delete set null,
  runbook_reference text,
  status text not null default 'active' check (status in ('draft','active','paused','inactive','archived')),
  last_evaluated_at timestamptz,
  next_evaluation_at timestamptz,
  last_triggered_at timestamptz,
  last_recovered_at timestamptz,
  tags text[] not null default '{}',
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,alert_code)
);

create index if not exists observability_alert_rules_due_idx
on public.observability_alert_rules(status,next_evaluation_at,severity)
where status='active';

create table if not exists public.observability_synthetic_monitors (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.observability_environments(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  alert_rule_id uuid references public.observability_alert_rules(id) on delete set null,
  monitor_code text not null,
  monitor_name text not null,
  description text,
  monitor_type text not null check (monitor_type in ('http','https','tcp','dns','database','api','browser','workflow','heartbeat','custom')),
  target_reference text not null,
  request_configuration jsonb not null default '{}',
  assertion_configuration jsonb not null default '{}',
  interval_seconds integer not null default 300 check (interval_seconds>=30),
  timeout_seconds integer not null default 30 check (timeout_seconds>=1),
  locations text[] not null default '{}',
  failure_threshold integer not null default 3,
  recovery_threshold integer not null default 2,
  current_status text not null default 'unknown'
    check (current_status in ('unknown','up','degraded','down','paused','maintenance')),
  consecutive_failures integer not null default 0,
  consecutive_successes integer not null default 0,
  last_checked_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  next_check_at timestamptz,
  status text not null default 'active' check (status in ('draft','active','paused','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,monitor_code)
);

create table if not exists public.observability_monitor_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  monitor_id uuid not null references public.observability_synthetic_monitors(id) on delete cascade,
  run_reference text not null,
  execution_location text,
  status text not null check (status in ('passed','failed','degraded','timed_out','cancelled','error')),
  response_status_code integer,
  response_time_ms integer,
  assertion_results jsonb not null default '[]',
  response_summary jsonb not null default '{}',
  error_type text,
  error_code text,
  error_message text,
  started_at timestamptz not null,
  completed_at timestamptz not null,
  correlation_id text,
  trace_id text,
  created_at timestamptz not null default now(),
  check (completed_at>=started_at),
  unique (monitor_id,run_reference)
);

create table if not exists public.observability_alert_evaluation_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  alert_rule_id uuid not null references public.observability_alert_rules(id) on delete cascade,
  evaluation_type text not null default 'scheduled'
    check (evaluation_type in ('scheduled','event','manual','recovery','backfill')),
  status text not null default 'queued'
    check (status in ('queued','claimed','processing','completed','failed','cancelled','dead_lettered')),
  priority integer not null default 100,
  available_at timestamptz not null default now(),
  evaluation_window_start timestamptz,
  evaluation_window_end timestamptz,
  payload jsonb not null default '{}',
  attempts integer not null default 0,
  maximum_attempts integer not null default 8,
  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,
  completed_at timestamptz,
  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',
  correlation_id text,
  trace_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists observability_alert_jobs_worker_idx
on public.observability_alert_evaluation_jobs(status,available_at,priority,created_at)
where status in ('queued','failed');

-- 6. Reliability incidents, on-call, maintenance and deployment
create table if not exists public.observability_reliability_incidents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid references public.observability_environments(id) on delete set null,
  primary_service_id uuid references public.observability_services(id) on delete set null,
  incident_code text not null,
  incident_title text not null,
  description text,
  incident_type text not null default 'service_degradation'
    check (incident_type in ('service_outage','service_degradation','performance','data_delay','queue_backlog','capacity','deployment_failure','dependency_failure','slo_breach','monitor_failure','operational_error','custom')),
  severity text not null default 'warning' check (severity in ('info','warning','high','critical')),
  priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
  status text not null default 'open'
    check (status in ('open','acknowledged','investigating','identified','monitoring','resolved','closed','false_positive','cancelled','archived')),
  impact_scope text,
  customer_impact text,
  affected_service_ids uuid[] not null default '{}',
  affected_region_codes text[] not null default '{}',
  incident_commander_id uuid references auth.users(id) on delete set null,
  responder_user_ids uuid[] not null default '{}',
  escalation_policy_id uuid references public.observability_escalation_policies(id) on delete set null,
  source_alert_rule_id uuid references public.observability_alert_rules(id) on delete set null,
  source_alert_fingerprint text,
  detected_at timestamptz not null default now(),
  acknowledged_at timestamptz,
  investigation_started_at timestamptz,
  identified_at timestamptz,
  monitoring_started_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  time_to_acknowledge_seconds bigint,
  time_to_resolve_seconds bigint,
  root_cause text,
  resolution_summary text,
  prevention_actions text,
  lessons_learned text,
  postmortem_required boolean not null default false,
  postmortem_document_id uuid references public.documents(id) on delete set null,
  workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
  correlation_id text,
  trace_id text,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,incident_code)
);

create table if not exists public.observability_alert_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  alert_rule_id uuid not null references public.observability_alert_rules(id) on delete cascade,
  service_id uuid references public.observability_services(id) on delete set null,
  alert_fingerprint text not null,
  event_type text not null check (event_type in ('triggered','retriggered','acknowledged','suppressed','recovered','resolved','evaluation_error','custom')),
  severity text not null check (severity in ('info','warning','high','critical')),
  summary text not null,
  details text,
  current_value numeric,
  threshold_value numeric,
  evaluation_data jsonb not null default '{}',
  incident_id uuid references public.observability_reliability_incidents(id) on delete set null,
  occurred_at timestamptz not null default now(),
  correlation_id text,
  trace_id text,
  created_at timestamptz not null default now()
);

create table if not exists public.observability_incident_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  incident_id uuid not null references public.observability_reliability_incidents(id) on delete cascade,
  event_type text not null check (event_type in (
    'created','alert_linked','acknowledged','status_changed','assignment_changed',
    'severity_changed','note_added','diagnostic_added','communication_sent',
    'deployment_linked','mitigation_action','resolved','reopened','postmortem_updated','custom'
  )),
  event_summary text not null,
  event_data jsonb not null default '{}',
  performed_by uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now(),
  correlation_id text,
  trace_id text,
  created_at timestamptz not null default now()
);

create table if not exists public.observability_oncall_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  schedule_code text not null,
  schedule_name text not null,
  description text,
  timezone text not null default 'Asia/Kolkata',
  handoff_time time not null default '09:00:00',
  rotation_length_days integer not null default 7,
  participants uuid[] not null default '{}',
  status text not null default 'active' check (status in ('draft','active','paused','inactive','archived')),
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,schedule_code)
);

create table if not exists public.observability_oncall_shifts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  oncall_schedule_id uuid not null references public.observability_oncall_schedules(id) on delete cascade,
  primary_user_id uuid not null references auth.users(id) on delete cascade,
  secondary_user_id uuid references auth.users(id) on delete set null,
  shift_start timestamptz not null,
  shift_end timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled','active','completed','cancelled','overridden')),
  override_reason text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (shift_end>shift_start)
);

create table if not exists public.observability_maintenance_windows (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid references public.observability_environments(id) on delete cascade,
  maintenance_code text not null,
  maintenance_name text not null,
  description text,
  service_ids uuid[] not null default '{}',
  alert_rule_ids uuid[] not null default '{}',
  monitor_ids uuid[] not null default '{}',
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  recurrence_rule text,
  timezone text not null default 'Asia/Kolkata',
  suppress_alerts boolean not null default true,
  pause_monitors boolean not null default false,
  mark_services_maintenance boolean not null default true,
  status text not null default 'scheduled'
    check (status in ('draft','scheduled','active','completed','cancelled','archived')),
  owner_user_id uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at>starts_at),
  unique (organization_id,maintenance_code)
);

create table if not exists public.observability_deployment_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.observability_environments(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  deployment_reference text not null,
  deployment_type text not null default 'application'
    check (deployment_type in ('application','database','configuration','infrastructure','feature_flag','rollback','hotfix','custom')),
  version_before text,
  version_after text,
  commit_reference text,
  repository_reference text,
  pipeline_reference text,
  status text not null check (status in ('started','succeeded','failed','rolled_back','cancelled')),
  deployment_strategy text,
  change_summary text,
  started_at timestamptz not null,
  completed_at timestamptz,
  deployed_by uuid references auth.users(id) on delete set null,
  related_incident_id uuid references public.observability_reliability_incidents(id) on delete set null,
  correlation_id text,
  trace_id text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (organization_id,environment_id,service_id,deployment_reference)
);

create table if not exists public.observability_runbooks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  runbook_code text not null,
  runbook_name text not null,
  description text,
  runbook_type text not null default 'diagnostic'
    check (runbook_type in ('diagnostic','mitigation','recovery','deployment','rollback','capacity','incident_response','custom')),
  service_ids uuid[] not null default '{}',
  alert_rule_ids uuid[] not null default '{}',
  instructions_markdown text,
  procedure_json jsonb not null default '[]',
  automation_workflow_id uuid references public.enterprise_workflow_definitions(id) on delete set null,
  owner_user_id uuid references auth.users(id) on delete set null,
  status text not null default 'draft'
    check (status in ('draft','under_review','approved','active','deprecated','archived')),
  version_number integer not null default 1,
  last_tested_at timestamptz,
  next_test_due_at timestamptz,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,runbook_code,version_number)
);

-- 7. Capacity, retention, outbox and engine logs
create table if not exists public.observability_capacity_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.observability_environments(id) on delete cascade,
  service_id uuid not null references public.observability_services(id) on delete cascade,
  resource_type text not null check (resource_type in (
    'cpu','memory','storage','database_connections','queue_depth','api_requests',
    'worker_concurrency','network','tokens','credits','custom'
  )),
  provisioned_capacity numeric,
  used_capacity numeric,
  available_capacity numeric,
  utilization_percentage numeric(12,6),
  forecast_7d numeric,
  forecast_30d numeric,
  exhaustion_forecast_at timestamptz,
  capacity_status text not null default 'healthy'
    check (capacity_status in ('healthy','warning','critical','exhausted','unknown')),
  attributes jsonb not null default '{}',
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.observability_retention_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  policy_code text not null,
  policy_name text not null,
  telemetry_type text not null
    check (telemetry_type in ('metrics','logs','traces','heartbeats','monitor_runs','alert_events','capacity','all')),
  retention_days integer not null check (retention_days>=1),
  archive_before_delete boolean not null default false,
  archive_destination_reference text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id,policy_code)
);

create table if not exists public.observability_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  event_name text not null,
  source_type text,
  source_id uuid,
  destination text not null default 'internal'
    check (destination in (
      'internal','automation_engine','enterprise_workflow','communication_engine',
      'notification_engine','integration_api','ai_intelligence','reporting',
      'mobile','security_governance','n8n','analytics','audit','webhook'
    )),
  status text not null default 'pending'
    check (status in ('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
  priority integer not null default 100,
  idempotency_key text,
  correlation_id text,
  trace_id text,
  payload jsonb not null default '{}',
  available_at timestamptz not null default now(),
  delivery_attempts integer not null default 0,
  maximum_attempts integer not null default 10,
  delivered_at timestamptz,
  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists observability_event_outbox_idem_idx
on public.observability_event_outbox(organization_id,idempotency_key)
where idempotency_key is not null;

create table if not exists public.observability_engine_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  log_level text not null default 'info' check (log_level in ('debug','info','warning','error','critical')),
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
-- 8. Updated-at triggers
drop trigger if exists observability_environments_set_updated_at on public.observability_environments;
create trigger observability_environments_set_updated_at
before update on public.observability_environments
for each row execute function public.set_updated_at();

drop trigger if exists observability_services_set_updated_at on public.observability_services;
create trigger observability_services_set_updated_at
before update on public.observability_services
for each row execute function public.set_updated_at();

drop trigger if exists observability_telemetry_sources_set_updated_at on public.observability_telemetry_sources;
create trigger observability_telemetry_sources_set_updated_at
before update on public.observability_telemetry_sources
for each row execute function public.set_updated_at();

drop trigger if exists observability_metric_definitions_set_updated_at on public.observability_metric_definitions;
create trigger observability_metric_definitions_set_updated_at
before update on public.observability_metric_definitions
for each row execute function public.set_updated_at();

drop trigger if exists observability_traces_set_updated_at on public.observability_traces;
create trigger observability_traces_set_updated_at
before update on public.observability_traces
for each row execute function public.set_updated_at();

drop trigger if exists observability_sli_definitions_set_updated_at on public.observability_sli_definitions;
create trigger observability_sli_definitions_set_updated_at
before update on public.observability_sli_definitions
for each row execute function public.set_updated_at();

drop trigger if exists observability_slos_set_updated_at on public.observability_slos;
create trigger observability_slos_set_updated_at
before update on public.observability_slos
for each row execute function public.set_updated_at();

drop trigger if exists observability_escalation_policies_set_updated_at on public.observability_escalation_policies;
create trigger observability_escalation_policies_set_updated_at
before update on public.observability_escalation_policies
for each row execute function public.set_updated_at();

drop trigger if exists observability_alert_rules_set_updated_at on public.observability_alert_rules;
create trigger observability_alert_rules_set_updated_at
before update on public.observability_alert_rules
for each row execute function public.set_updated_at();

drop trigger if exists observability_synthetic_monitors_set_updated_at on public.observability_synthetic_monitors;
create trigger observability_synthetic_monitors_set_updated_at
before update on public.observability_synthetic_monitors
for each row execute function public.set_updated_at();

drop trigger if exists observability_alert_evaluation_jobs_set_updated_at on public.observability_alert_evaluation_jobs;
create trigger observability_alert_evaluation_jobs_set_updated_at
before update on public.observability_alert_evaluation_jobs
for each row execute function public.set_updated_at();

drop trigger if exists observability_reliability_incidents_set_updated_at on public.observability_reliability_incidents;
create trigger observability_reliability_incidents_set_updated_at
before update on public.observability_reliability_incidents
for each row execute function public.set_updated_at();

drop trigger if exists observability_oncall_schedules_set_updated_at on public.observability_oncall_schedules;
create trigger observability_oncall_schedules_set_updated_at
before update on public.observability_oncall_schedules
for each row execute function public.set_updated_at();

drop trigger if exists observability_oncall_shifts_set_updated_at on public.observability_oncall_shifts;
create trigger observability_oncall_shifts_set_updated_at
before update on public.observability_oncall_shifts
for each row execute function public.set_updated_at();

drop trigger if exists observability_maintenance_windows_set_updated_at on public.observability_maintenance_windows;
create trigger observability_maintenance_windows_set_updated_at
before update on public.observability_maintenance_windows
for each row execute function public.set_updated_at();

drop trigger if exists observability_runbooks_set_updated_at on public.observability_runbooks;
create trigger observability_runbooks_set_updated_at
before update on public.observability_runbooks
for each row execute function public.set_updated_at();

drop trigger if exists observability_retention_policies_set_updated_at on public.observability_retention_policies;
create trigger observability_retention_policies_set_updated_at
before update on public.observability_retention_policies
for each row execute function public.set_updated_at();

drop trigger if exists observability_event_outbox_set_updated_at on public.observability_event_outbox;
create trigger observability_event_outbox_set_updated_at
before update on public.observability_event_outbox
for each row execute function public.set_updated_at();


-- 9. Environment and service registration
create or replace function public.register_observability_environment(
  requested_organization_id uuid,
  requested_environment_code text,
  requested_environment_name text,
  requested_environment_type text default 'production',
  requested_region text default null,
  requested_cloud_provider text default null,
  requested_base_url text default null,
  requested_criticality text default 'high',
  requested_timezone text default 'Asia/Kolkata',
  requested_metadata jsonb default '{}'::jsonb
)
returns public.observability_environments
language plpgsql security definer set search_path=''
as $$
declare r public.observability_environments;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.manage_services'
  ) then raise exception 'Permission denied'; end if;

  insert into public.observability_environments(
    organization_id,environment_code,environment_name,environment_type,region,
    cloud_provider,base_url,criticality,status,timezone,metadata,created_by,updated_by
  ) values (
    requested_organization_id,requested_environment_code,requested_environment_name,
    requested_environment_type,requested_region,requested_cloud_provider,requested_base_url,
    requested_criticality,'active',requested_timezone,coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),auth.uid()
  )
  on conflict (organization_id,environment_code) do update set
    environment_name=excluded.environment_name,
    environment_type=excluded.environment_type,
    region=excluded.region,
    cloud_provider=excluded.cloud_provider,
    base_url=excluded.base_url,
    criticality=excluded.criticality,
    timezone=excluded.timezone,
    metadata=excluded.metadata,
    updated_by=auth.uid(),
    updated_at=now()
  returning * into r;
  return r;
end;
$$;

create or replace function public.register_observability_service(
  requested_organization_id uuid,
  requested_environment_id uuid,
  requested_service_code text,
  requested_service_name text,
  requested_service_type text,
  requested_description text default null,
  requested_owner_user_id uuid default null,
  requested_criticality text default 'high',
  requested_service_url text default null,
  requested_expected_heartbeat_interval_seconds integer default null,
  requested_heartbeat_grace_seconds integer default 60,
  requested_configuration jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.observability_services
language plpgsql security definer set search_path=''
as $$
declare r public.observability_services;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.manage_services'
  ) then raise exception 'Permission denied'; end if;

  if not exists (
    select 1 from public.observability_environments e
    where e.id=requested_environment_id and e.organization_id=requested_organization_id
  ) then raise exception 'Environment does not belong to organization'; end if;

  insert into public.observability_services(
    organization_id,environment_id,service_code,service_name,description,service_type,
    owner_user_id,criticality,lifecycle_status,health_status,service_url,
    expected_heartbeat_interval_seconds,heartbeat_grace_seconds,configuration,metadata,
    created_by,updated_by
  ) values (
    requested_organization_id,requested_environment_id,requested_service_code,
    requested_service_name,requested_description,requested_service_type,
    requested_owner_user_id,requested_criticality,'active','unknown',requested_service_url,
    requested_expected_heartbeat_interval_seconds,greatest(coalesce(requested_heartbeat_grace_seconds,60),0),
    coalesce(requested_configuration,'{}'::jsonb),coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),auth.uid()
  )
  on conflict (organization_id,environment_id,service_code) do update set
    service_name=excluded.service_name,
    description=excluded.description,
    service_type=excluded.service_type,
    owner_user_id=excluded.owner_user_id,
    criticality=excluded.criticality,
    service_url=excluded.service_url,
    expected_heartbeat_interval_seconds=excluded.expected_heartbeat_interval_seconds,
    heartbeat_grace_seconds=excluded.heartbeat_grace_seconds,
    configuration=excluded.configuration,
    metadata=excluded.metadata,
    updated_by=auth.uid(),
    updated_at=now()
  returning * into r;
  return r;
end;
$$;

-- 10. Telemetry ingestion
create or replace function public.register_observability_metric_definition(
  requested_organization_id uuid,
  requested_service_id uuid,
  requested_metric_code text,
  requested_metric_name text,
  requested_metric_type text default 'gauge',
  requested_unit text default null,
  requested_description text default null,
  requested_aggregation_method text default 'average',
  requested_retention_days integer default 30,
  requested_labels_schema jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.observability_metric_definitions
language plpgsql security definer set search_path=''
as $$
declare r public.observability_metric_definitions;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.manage_telemetry'
  ) then raise exception 'Permission denied'; end if;

  insert into public.observability_metric_definitions(
    organization_id,service_id,metric_code,metric_name,description,metric_type,unit,
    aggregation_method,retention_days,status,labels_schema,metadata,created_by,updated_by
  ) values (
    requested_organization_id,requested_service_id,requested_metric_code,requested_metric_name,
    requested_description,requested_metric_type,requested_unit,requested_aggregation_method,
    greatest(coalesce(requested_retention_days,30),1),'active',
    coalesce(requested_labels_schema,'{}'::jsonb),coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),auth.uid()
  )
  on conflict (organization_id,service_id,metric_code) do update set
    metric_name=excluded.metric_name,
    description=excluded.description,
    metric_type=excluded.metric_type,
    unit=excluded.unit,
    aggregation_method=excluded.aggregation_method,
    retention_days=excluded.retention_days,
    labels_schema=excluded.labels_schema,
    metadata=excluded.metadata,
    updated_by=auth.uid(),
    updated_at=now()
  returning * into r;
  return r;
end;
$$;

create or replace function public.ingest_observability_metric(
  requested_organization_id uuid,
  requested_metric_definition_id uuid,
  requested_numeric_value numeric,
  requested_telemetry_source_id uuid default null,
  requested_labels jsonb default '{}'::jsonb,
  requested_attributes jsonb default '{}'::jsonb,
  requested_observed_at timestamptz default now(),
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns public.observability_metric_samples
language plpgsql security definer set search_path=''
as $$
declare m public.observability_metric_definitions;
s public.observability_services;
r public.observability_metric_samples;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.ingest_telemetry'
  ) then raise exception 'Permission denied'; end if;

  if requested_idempotency_key is not null then
    select * into r from public.observability_metric_samples
    where organization_id=requested_organization_id
      and idempotency_key=requested_idempotency_key limit 1;
    if found then return r; end if;
  end if;

  select * into m from public.observability_metric_definitions
  where id=requested_metric_definition_id
    and organization_id=requested_organization_id
    and status='active';
  if not found then raise exception 'Active metric definition not found'; end if;

  select * into s from public.observability_services where id=m.service_id;

  insert into public.observability_metric_samples(
    organization_id,environment_id,service_id,telemetry_source_id,metric_definition_id,
    numeric_value,labels,attributes,observed_at,idempotency_key,correlation_id,trace_id
  ) values (
    requested_organization_id,s.environment_id,s.id,requested_telemetry_source_id,m.id,
    requested_numeric_value,coalesce(requested_labels,'{}'::jsonb),
    coalesce(requested_attributes,'{}'::jsonb),coalesce(requested_observed_at,now()),
    requested_idempotency_key,requested_correlation_id,requested_trace_id
  ) returning * into r;

  if requested_telemetry_source_id is not null then
    update public.observability_telemetry_sources
    set last_seen_at=now(),status=case when status='error' then 'active' else status end,updated_at=now()
    where id=requested_telemetry_source_id and organization_id=requested_organization_id;
  end if;
  return r;
end;
$$;

create or replace function public.ingest_observability_log(
  requested_organization_id uuid,
  requested_service_id uuid,
  requested_log_level text,
  requested_message text,
  requested_telemetry_source_id uuid default null,
  requested_event_name text default null,
  requested_error_type text default null,
  requested_error_code text default null,
  requested_error_message text default null,
  requested_stack_trace text default null,
  requested_attributes jsonb default '{}'::jsonb,
  requested_occurred_at timestamptz default now(),
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_span_id text default null,
  requested_fingerprint text default null,
  requested_idempotency_key text default null
)
returns public.observability_log_events
language plpgsql security definer set search_path=''
as $$
declare s public.observability_services;
r public.observability_log_events;
fp text;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.ingest_telemetry'
  ) then raise exception 'Permission denied'; end if;

  if requested_idempotency_key is not null then
    select * into r from public.observability_log_events
    where organization_id=requested_organization_id
      and idempotency_key=requested_idempotency_key limit 1;
    if found then return r; end if;
  end if;

  select * into s from public.observability_services
  where id=requested_service_id and organization_id=requested_organization_id;
  if not found then raise exception 'Service not found'; end if;

  fp:=coalesce(requested_fingerprint,encode(digest(
    coalesce(requested_error_type,'')||':'||coalesce(requested_error_code,'')||':'||
    coalesce(requested_event_name,'')||':'||left(coalesce(requested_message,''),500),'sha256'
  ),'hex'));

  insert into public.observability_log_events(
    organization_id,environment_id,service_id,telemetry_source_id,log_level,event_name,
    message,error_type,error_code,error_message,stack_trace,attributes,occurred_at,
    correlation_id,trace_id,span_id,fingerprint,idempotency_key
  ) values (
    requested_organization_id,s.environment_id,s.id,requested_telemetry_source_id,
    requested_log_level,requested_event_name,requested_message,requested_error_type,
    requested_error_code,requested_error_message,requested_stack_trace,
    coalesce(requested_attributes,'{}'::jsonb),coalesce(requested_occurred_at,now()),
    requested_correlation_id,requested_trace_id,requested_span_id,fp,requested_idempotency_key
  ) returning * into r;
  return r;
end;
$$;

create or replace function public.record_observability_heartbeat(
  requested_organization_id uuid,
  requested_service_id uuid,
  requested_heartbeat_status text default 'healthy',
  requested_telemetry_source_id uuid default null,
  requested_response_time_ms integer default null,
  requested_version text default null,
  requested_instance_reference text default null,
  requested_region text default null,
  requested_health_details jsonb default '{}'::jsonb,
  requested_dependency_health jsonb default '{}'::jsonb,
  requested_observed_at timestamptz default now(),
  requested_idempotency_key text default null
)
returns public.observability_heartbeats
language plpgsql security definer set search_path=''
as $$
declare s public.observability_services;
r public.observability_heartbeats;
mapped text;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.ingest_telemetry'
  ) then raise exception 'Permission denied'; end if;

  if requested_idempotency_key is not null then
    select * into r from public.observability_heartbeats
    where organization_id=requested_organization_id
      and idempotency_key=requested_idempotency_key limit 1;
    if found then return r; end if;
  end if;

  select * into s from public.observability_services
  where id=requested_service_id and organization_id=requested_organization_id for update;
  if not found then raise exception 'Service not found'; end if;

  insert into public.observability_heartbeats(
    organization_id,environment_id,service_id,telemetry_source_id,heartbeat_status,
    response_time_ms,version,instance_reference,region,health_details,dependency_health,
    observed_at,idempotency_key
  ) values (
    requested_organization_id,s.environment_id,s.id,requested_telemetry_source_id,
    requested_heartbeat_status,requested_response_time_ms,requested_version,
    requested_instance_reference,requested_region,coalesce(requested_health_details,'{}'::jsonb),
    coalesce(requested_dependency_health,'{}'::jsonb),coalesce(requested_observed_at,now()),
    requested_idempotency_key
  ) returning * into r;

  mapped:=case requested_heartbeat_status
    when 'healthy' then 'healthy'
    when 'degraded' then 'degraded'
    when 'unhealthy' then 'unhealthy'
    when 'maintenance' then 'maintenance'
    when 'starting' then 'degraded'
    when 'stopping' then 'degraded'
    else 'unknown' end;

  update public.observability_services set
    health_status=mapped,
    health_status_reason='heartbeat:'||requested_heartbeat_status,
    health_last_changed_at=case when health_status is distinct from mapped then now() else health_last_changed_at end,
    last_heartbeat_at=coalesce(requested_observed_at,now()),
    updated_at=now()
  where id=s.id;

  return r;
end;
$$;

-- 11. Trace ingestion
create or replace function public.upsert_observability_trace(
  requested_organization_id uuid,
  requested_environment_id uuid,
  requested_trace_id text,
  requested_started_at timestamptz,
  requested_root_service_id uuid default null,
  requested_trace_name text default null,
  requested_operation_name text default null,
  requested_status text default 'in_progress',
  requested_ended_at timestamptz default null,
  requested_root_span_id text default null,
  requested_attributes jsonb default '{}'::jsonb,
  requested_resource_attributes jsonb default '{}'::jsonb,
  requested_correlation_id text default null
)
returns public.observability_traces
language plpgsql security definer set search_path=''
as $$
declare r public.observability_traces;
d bigint;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.ingest_telemetry'
  ) then raise exception 'Permission denied'; end if;

  d:=case when requested_ended_at is null then null else greatest(
    0,round(extract(epoch from (requested_ended_at-requested_started_at))*1000)::bigint
  ) end;

  insert into public.observability_traces(
    organization_id,environment_id,root_service_id,trace_id,trace_name,operation_name,
    status,started_at,ended_at,duration_ms,root_span_id,attributes,resource_attributes,correlation_id
  ) values (
    requested_organization_id,requested_environment_id,requested_root_service_id,
    requested_trace_id,requested_trace_name,requested_operation_name,requested_status,
    requested_started_at,requested_ended_at,d,requested_root_span_id,
    coalesce(requested_attributes,'{}'::jsonb),coalesce(requested_resource_attributes,'{}'::jsonb),
    requested_correlation_id
  )
  on conflict (organization_id,trace_id) do update set
    root_service_id=coalesce(excluded.root_service_id,observability_traces.root_service_id),
    trace_name=coalesce(excluded.trace_name,observability_traces.trace_name),
    operation_name=coalesce(excluded.operation_name,observability_traces.operation_name),
    status=excluded.status,
    ended_at=coalesce(excluded.ended_at,observability_traces.ended_at),
    duration_ms=coalesce(excluded.duration_ms,observability_traces.duration_ms),
    root_span_id=coalesce(excluded.root_span_id,observability_traces.root_span_id),
    attributes=observability_traces.attributes||excluded.attributes,
    resource_attributes=observability_traces.resource_attributes||excluded.resource_attributes,
    correlation_id=coalesce(excluded.correlation_id,observability_traces.correlation_id),
    updated_at=now()
  returning * into r;
  return r;
end;
$$;

create or replace function public.upsert_observability_trace_span(
  requested_trace_record_id uuid,
  requested_span_id text,
  requested_span_name text,
  requested_started_at timestamptz,
  requested_service_id uuid default null,
  requested_parent_span_id text default null,
  requested_operation_name text default null,
  requested_span_kind text default 'internal',
  requested_status text default 'unset',
  requested_ended_at timestamptz default null,
  requested_error_type text default null,
  requested_error_message text default null,
  requested_attributes jsonb default '{}'::jsonb,
  requested_events jsonb default '[]'::jsonb,
  requested_links jsonb default '[]'::jsonb
)
returns public.observability_trace_spans
language plpgsql security definer set search_path=''
as $$
declare t public.observability_traces;
r public.observability_trace_spans;
d bigint;
begin
  select * into t from public.observability_traces where id=requested_trace_record_id for update;
  if not found then raise exception 'Trace not found'; end if;

  if auth.role()<>'service_role' and not public.has_organization_permission(
    t.organization_id,'observability_reliability.ingest_telemetry'
  ) then raise exception 'Permission denied'; end if;

  d:=case when requested_ended_at is null then null else greatest(
    0,round(extract(epoch from (requested_ended_at-requested_started_at))*1000)::bigint
  ) end;

  insert into public.observability_trace_spans(
    organization_id,trace_record_id,service_id,span_id,parent_span_id,span_name,
    operation_name,span_kind,status,started_at,ended_at,duration_ms,error_type,
    error_message,attributes,events,links
  ) values (
    t.organization_id,t.id,requested_service_id,requested_span_id,requested_parent_span_id,
    requested_span_name,requested_operation_name,requested_span_kind,requested_status,
    requested_started_at,requested_ended_at,d,requested_error_type,requested_error_message,
    coalesce(requested_attributes,'{}'::jsonb),coalesce(requested_events,'[]'::jsonb),
    coalesce(requested_links,'[]'::jsonb)
  )
  on conflict (trace_record_id,span_id) do update set
    service_id=coalesce(excluded.service_id,observability_trace_spans.service_id),
    parent_span_id=coalesce(excluded.parent_span_id,observability_trace_spans.parent_span_id),
    span_name=excluded.span_name,
    operation_name=coalesce(excluded.operation_name,observability_trace_spans.operation_name),
    span_kind=excluded.span_kind,
    status=excluded.status,
    ended_at=coalesce(excluded.ended_at,observability_trace_spans.ended_at),
    duration_ms=coalesce(excluded.duration_ms,observability_trace_spans.duration_ms),
    error_type=coalesce(excluded.error_type,observability_trace_spans.error_type),
    error_message=coalesce(excluded.error_message,observability_trace_spans.error_message),
    attributes=observability_trace_spans.attributes||excluded.attributes,
    events=excluded.events,
    links=excluded.links
  returning * into r;

  update public.observability_traces set
    span_count=(select count(*) from public.observability_trace_spans s where s.trace_record_id=t.id),
    error_count=(select count(*) from public.observability_trace_spans s where s.trace_record_id=t.id and s.status='error'),
    status=case when requested_status='error' then 'error' else status end,
    updated_at=now()
  where id=t.id;
  return r;
end;
$$;

-- 12. SLO measurement and monitor run recording
create or replace function public.record_observability_slo_measurement(
  requested_slo_id uuid,
  requested_window_start timestamptz,
  requested_window_end timestamptz,
  requested_good_events bigint,
  requested_valid_events bigint,
  requested_measurement_status text default 'complete',
  requested_source_data jsonb default '{}'::jsonb
)
returns public.observability_slo_measurements
language plpgsql security definer set search_path=''
as $$
declare s public.observability_slos;
r public.observability_slo_measurements;
a numeric;
allowed numeric;
observed numeric;
burn numeric;
begin
  select * into s from public.observability_slos where id=requested_slo_id;
  if not found then raise exception 'SLO not found'; end if;
  if auth.role()<>'service_role' and not public.has_organization_permission(
    s.organization_id,'observability_reliability.manage_slos'
  ) then raise exception 'Permission denied'; end if;
  if requested_valid_events<0 or requested_good_events<0 or requested_good_events>requested_valid_events
    then raise exception 'Invalid SLO event counts'; end if;

  a:=case when requested_valid_events=0 then null else
    requested_good_events::numeric/requested_valid_events::numeric*100 end;
  allowed:=(100-s.target_percentage)/100;
  observed:=case when requested_valid_events=0 then null else
    (requested_valid_events-requested_good_events)::numeric/requested_valid_events::numeric end;
  burn:=case when allowed<=0 or observed is null then null else observed/allowed end;

  insert into public.observability_slo_measurements(
    organization_id,slo_id,window_start,window_end,good_events,valid_events,
    achievement_percentage,burn_rate,target_met,measurement_status,source_data
  ) values (
    s.organization_id,s.id,requested_window_start,requested_window_end,
    requested_good_events,requested_valid_events,a,burn,
    case when a is null then null else a>=s.target_percentage end,
    requested_measurement_status,coalesce(requested_source_data,'{}'::jsonb)
  )
  on conflict (slo_id,window_start,window_end) do update set
    good_events=excluded.good_events,
    valid_events=excluded.valid_events,
    achievement_percentage=excluded.achievement_percentage,
    burn_rate=excluded.burn_rate,
    target_met=excluded.target_met,
    measurement_status=excluded.measurement_status,
    source_data=excluded.source_data,
    measured_at=now()
  returning * into r;
  return r;
end;
$$;

create or replace function public.record_observability_monitor_run(
  requested_monitor_id uuid,
  requested_run_reference text,
  requested_status text,
  requested_started_at timestamptz,
  requested_completed_at timestamptz,
  requested_execution_location text default null,
  requested_response_status_code integer default null,
  requested_response_time_ms integer default null,
  requested_assertion_results jsonb default '[]'::jsonb,
  requested_response_summary jsonb default '{}'::jsonb,
  requested_error_type text default null,
  requested_error_code text default null,
  requested_error_message text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns public.observability_monitor_runs
language plpgsql security definer set search_path=''
as $$
declare m public.observability_synthetic_monitors;
r public.observability_monitor_runs;
ns text;
nf integer;
nsuccess integer;
begin
  select * into m from public.observability_synthetic_monitors
  where id=requested_monitor_id for update;
  if not found then raise exception 'Synthetic monitor not found'; end if;
  if auth.role()<>'service_role' and not public.has_organization_permission(
    m.organization_id,'observability_reliability.ingest_telemetry'
  ) then raise exception 'Permission denied'; end if;

  insert into public.observability_monitor_runs(
    organization_id,monitor_id,run_reference,execution_location,status,
    response_status_code,response_time_ms,assertion_results,response_summary,
    error_type,error_code,error_message,started_at,completed_at,correlation_id,trace_id
  ) values (
    m.organization_id,m.id,requested_run_reference,requested_execution_location,
    requested_status,requested_response_status_code,requested_response_time_ms,
    coalesce(requested_assertion_results,'[]'::jsonb),
    coalesce(requested_response_summary,'{}'::jsonb),requested_error_type,
    requested_error_code,requested_error_message,requested_started_at,
    requested_completed_at,requested_correlation_id,requested_trace_id
  )
  on conflict (monitor_id,run_reference) do update set
    execution_location=excluded.execution_location,status=excluded.status,
    response_status_code=excluded.response_status_code,response_time_ms=excluded.response_time_ms,
    assertion_results=excluded.assertion_results,response_summary=excluded.response_summary,
    error_type=excluded.error_type,error_code=excluded.error_code,error_message=excluded.error_message,
    started_at=excluded.started_at,completed_at=excluded.completed_at,
    correlation_id=excluded.correlation_id,trace_id=excluded.trace_id
  returning * into r;

  if requested_status='passed' then
    nsuccess:=m.consecutive_successes+1; nf:=0;
    ns:=case when nsuccess>=m.recovery_threshold then 'up' else m.current_status end;
  elsif requested_status='degraded' then
    nsuccess:=0; nf:=m.consecutive_failures+1; ns:='degraded';
  else
    nsuccess:=0; nf:=m.consecutive_failures+1;
    ns:=case when nf>=m.failure_threshold then 'down' else m.current_status end;
  end if;

  update public.observability_synthetic_monitors set
    current_status=ns,consecutive_failures=nf,consecutive_successes=nsuccess,
    last_checked_at=requested_completed_at,
    last_success_at=case when requested_status='passed' then requested_completed_at else last_success_at end,
    last_failure_at=case when requested_status in ('failed','timed_out','error','degraded')
      then requested_completed_at else last_failure_at end,
    next_check_at=requested_completed_at+make_interval(secs=>interval_seconds),
    updated_at=now()
  where id=m.id;

  update public.observability_services set
    health_status=case when ns='up' then 'healthy' when ns='degraded' then 'degraded'
      when ns='down' then 'unhealthy' when ns='maintenance' then 'maintenance' else health_status end,
    health_status_reason='synthetic_monitor:'||m.monitor_code,
    updated_at=now()
  where id=m.service_id;
  return r;
end;
$$;

-- 13. Alert evaluation worker queue
create or replace function public.enqueue_observability_alert_evaluation(
  requested_alert_rule_id uuid,
  requested_evaluation_type text default 'scheduled',
  requested_available_at timestamptz default now(),
  requested_priority integer default 100,
  requested_window_start timestamptz default null,
  requested_window_end timestamptz default null,
  requested_payload jsonb default '{}'::jsonb,
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns public.observability_alert_evaluation_jobs
language plpgsql security definer set search_path=''
as $$
declare a public.observability_alert_rules;
r public.observability_alert_evaluation_jobs;
begin
  select * into a from public.observability_alert_rules
  where id=requested_alert_rule_id and status='active';
  if not found then raise exception 'Active alert rule not found'; end if;
  if auth.role()<>'service_role' and not public.has_organization_permission(
    a.organization_id,'observability_reliability.manage_alerts'
  ) then raise exception 'Permission denied'; end if;

  insert into public.observability_alert_evaluation_jobs(
    organization_id,alert_rule_id,evaluation_type,status,priority,available_at,
    evaluation_window_start,evaluation_window_end,payload,correlation_id,trace_id
  ) values (
    a.organization_id,a.id,requested_evaluation_type,'queued',requested_priority,
    coalesce(requested_available_at,now()),requested_window_start,requested_window_end,
    coalesce(requested_payload,'{}'::jsonb),requested_correlation_id,requested_trace_id
  ) returning * into r;
  return r;
end;
$$;

create or replace function public.claim_observability_alert_evaluation_job(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.observability_alert_evaluation_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.observability_alert_evaluation_jobs;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may claim alert jobs'; end if;

  select * into r from public.observability_alert_evaluation_jobs j
  where j.status in ('queued','failed') and j.available_at<=now()
    and j.attempts<j.maximum_attempts
    and (requested_organization_id is null or j.organization_id=requested_organization_id)
  order by j.priority,j.available_at,j.created_at
  for update skip locked limit 1;

  if not found then return null; end if;

  update public.observability_alert_evaluation_jobs set
    status='claimed',attempts=attempts+1,claimed_at=now(),claimed_by=requested_worker_id,
    lock_token=gen_random_uuid()::text,
    lock_expires_at=now()+make_interval(secs=>greatest(requested_lock_seconds,1)),
    updated_at=now()
  where id=r.id returning * into r;
  return r;
end;
$$;

create or replace function public.complete_observability_alert_evaluation_job(
  requested_job_id uuid,
  requested_lock_token text,
  requested_result_data jsonb default '{}'::jsonb
)
returns public.observability_alert_evaluation_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.observability_alert_evaluation_jobs;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may complete alert jobs'; end if;
  select * into r from public.observability_alert_evaluation_jobs where id=requested_job_id for update;
  if not found then raise exception 'Alert evaluation job not found'; end if;
  if r.lock_token is distinct from requested_lock_token then raise exception 'Invalid lock token'; end if;

  update public.observability_alert_evaluation_jobs set
    status='completed',completed_at=now(),
    payload=payload||jsonb_build_object('result',coalesce(requested_result_data,'{}'::jsonb)),
    claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
  where id=requested_job_id returning * into r;

  update public.observability_alert_rules set
    last_evaluated_at=now(),
    next_evaluation_at=now()+make_interval(secs=>evaluation_interval_seconds),
    updated_at=now()
  where id=r.alert_rule_id;
  return r;
end;
$$;

create or replace function public.fail_observability_alert_evaluation_job(
  requested_job_id uuid,
  requested_lock_token text,
  requested_error_code text,
  requested_error_message text,
  requested_error_data jsonb default '{}'::jsonb
)
returns public.observability_alert_evaluation_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.observability_alert_evaluation_jobs;
ns text;
delay_seconds integer;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may fail alert jobs'; end if;
  select * into r from public.observability_alert_evaluation_jobs where id=requested_job_id for update;
  if not found then raise exception 'Alert evaluation job not found'; end if;
  if r.lock_token is distinct from requested_lock_token then raise exception 'Invalid lock token'; end if;

  ns:=case when r.attempts>=r.maximum_attempts then 'dead_lettered' else 'failed' end;
  delay_seconds:=least(3600,greatest(30,power(2,greatest(r.attempts,1))::integer*30));

  update public.observability_alert_evaluation_jobs set
    status=ns,
    available_at=case when ns='failed' then now()+make_interval(secs=>delay_seconds) else available_at end,
    last_error_code=requested_error_code,last_error_message=requested_error_message,
    last_error_data=coalesce(requested_error_data,'{}'::jsonb),
    claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
  where id=requested_job_id returning * into r;

  insert into public.observability_engine_logs(
    organization_id,log_level,event_name,message,source_type,source_id,error_code,error_message,
    log_data,correlation_id,trace_id
  ) values (
    r.organization_id,case when ns='dead_lettered' then 'critical' else 'error' end,
    'alert_evaluation.'||ns,'Alert evaluation failed','alert_evaluation_job',r.id,
    requested_error_code,requested_error_message,coalesce(requested_error_data,'{}'::jsonb),
    r.correlation_id,r.trace_id
  );
  return r;
end;
$$;

-- 14. Reliability incident and alert lifecycle
create or replace function public.open_observability_reliability_incident(
  requested_organization_id uuid,
  requested_incident_title text,
  requested_incident_type text default 'service_degradation',
  requested_severity text default 'warning',
  requested_primary_service_id uuid default null,
  requested_environment_id uuid default null,
  requested_description text default null,
  requested_source_alert_rule_id uuid default null,
  requested_source_alert_fingerprint text default null,
  requested_affected_service_ids uuid[] default '{}',
  requested_incident_commander_id uuid default null,
  requested_escalation_policy_id uuid default null,
  requested_customer_impact text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.observability_reliability_incidents
language plpgsql security definer set search_path=''
as $$
declare r public.observability_reliability_incidents;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.manage_incidents'
  ) then raise exception 'Permission denied'; end if;

  if requested_source_alert_fingerprint is not null then
    select * into r from public.observability_reliability_incidents
    where organization_id=requested_organization_id
      and source_alert_fingerprint=requested_source_alert_fingerprint
      and status not in ('resolved','closed','false_positive','cancelled','archived')
    order by created_at desc limit 1 for update;

    if found then
      update public.observability_reliability_incidents set
        severity=case
          when requested_severity='critical' then 'critical'
          when requested_severity='high' and severity in ('info','warning') then 'high'
          when requested_severity='warning' and severity='info' then 'warning'
          else severity end,
        description=coalesce(requested_description,description),
        customer_impact=coalesce(requested_customer_impact,customer_impact),
        metadata=metadata||coalesce(requested_metadata,'{}'::jsonb),
        updated_by=auth.uid(),updated_at=now()
      where id=r.id returning * into r;
      return r;
    end if;
  end if;

  insert into public.observability_reliability_incidents(
    organization_id,environment_id,primary_service_id,incident_code,incident_title,
    description,incident_type,severity,priority,status,customer_impact,affected_service_ids,
    incident_commander_id,escalation_policy_id,source_alert_rule_id,source_alert_fingerprint,
    detected_at,postmortem_required,correlation_id,trace_id,metadata,created_by,updated_by
  ) values (
    requested_organization_id,requested_environment_id,requested_primary_service_id,
    'REL-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
    requested_incident_title,requested_description,requested_incident_type,requested_severity,
    case when requested_severity='critical' then 'urgent'
      when requested_severity='high' then 'high' else 'normal' end,
    'open',requested_customer_impact,coalesce(requested_affected_service_ids,'{}'::uuid[]),
    requested_incident_commander_id,requested_escalation_policy_id,requested_source_alert_rule_id,
    requested_source_alert_fingerprint,now(),requested_severity in ('high','critical'),
    requested_correlation_id,requested_trace_id,coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),auth.uid()
  ) returning * into r;

  insert into public.observability_incident_events(
    organization_id,incident_id,event_type,event_summary,event_data,performed_by,correlation_id,trace_id
  ) values (
    r.organization_id,r.id,'created','Reliability incident created',
    jsonb_build_object('severity',r.severity,'incident_type',r.incident_type),
    auth.uid(),r.correlation_id,r.trace_id
  );
  return r;
end;
$$;

create or replace function public.record_observability_alert_event(
  requested_alert_rule_id uuid,
  requested_alert_fingerprint text,
  requested_event_type text,
  requested_summary text,
  requested_details text default null,
  requested_current_value numeric default null,
  requested_threshold_value numeric default null,
  requested_evaluation_data jsonb default '{}'::jsonb,
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns public.observability_alert_events
language plpgsql security definer set search_path=''
as $$
declare a public.observability_alert_rules;
e public.observability_alert_events;
i public.observability_reliability_incidents;
begin
  select * into a from public.observability_alert_rules where id=requested_alert_rule_id for update;
  if not found then raise exception 'Alert rule not found'; end if;
  if auth.role()<>'service_role' and not public.has_organization_permission(
    a.organization_id,'observability_reliability.manage_alerts'
  ) then raise exception 'Permission denied'; end if;

  if requested_event_type in ('triggered','retriggered') and a.create_incident then
    i:=public.open_observability_reliability_incident(
      a.organization_id,requested_summary,
      case a.alert_type when 'monitor_failure' then 'monitor_failure'
        when 'slo_burn' then 'slo_breach' when 'error_budget' then 'slo_breach'
        when 'capacity' then 'capacity' when 'queue_lag' then 'queue_backlog'
        else 'service_degradation' end,
      a.severity,a.service_id,a.environment_id,requested_details,a.id,
      requested_alert_fingerprint,
      case when a.service_id is null then '{}'::uuid[] else array[a.service_id] end,
      null,a.escalation_policy_id,null,requested_correlation_id,requested_trace_id,
      coalesce(requested_evaluation_data,'{}'::jsonb)
    );
  elsif requested_event_type in ('recovered','resolved') and a.auto_resolve then
    select * into i from public.observability_reliability_incidents
    where organization_id=a.organization_id
      and source_alert_fingerprint=requested_alert_fingerprint
      and status not in ('resolved','closed','false_positive','cancelled','archived')
    order by created_at desc limit 1 for update;
    if found then
      update public.observability_reliability_incidents set
        status='resolved',resolved_at=now(),
        time_to_resolve_seconds=greatest(0,extract(epoch from (now()-detected_at))::bigint),
        resolution_summary=coalesce(resolution_summary,'Automatically resolved after alert recovery'),
        updated_at=now()
      where id=i.id returning * into i;
    end if;
  end if;

  insert into public.observability_alert_events(
    organization_id,alert_rule_id,service_id,alert_fingerprint,event_type,severity,
    summary,details,current_value,threshold_value,evaluation_data,incident_id,
    occurred_at,correlation_id,trace_id
  ) values (
    a.organization_id,a.id,a.service_id,requested_alert_fingerprint,requested_event_type,
    a.severity,requested_summary,requested_details,requested_current_value,
    requested_threshold_value,coalesce(requested_evaluation_data,'{}'::jsonb),i.id,
    now(),requested_correlation_id,requested_trace_id
  ) returning * into e;

  update public.observability_alert_rules set
    last_evaluated_at=now(),
    last_triggered_at=case when requested_event_type in ('triggered','retriggered') then now() else last_triggered_at end,
    last_recovered_at=case when requested_event_type in ('recovered','resolved') then now() else last_recovered_at end,
    next_evaluation_at=now()+make_interval(secs=>evaluation_interval_seconds),
    updated_at=now()
  where id=a.id;
  return e;
end;
$$;

create or replace function public.acknowledge_observability_incident(
  requested_incident_id uuid,
  requested_notes text default null
)
returns public.observability_reliability_incidents
language plpgsql security definer set search_path=''
as $$
declare r public.observability_reliability_incidents;
begin
  select * into r from public.observability_reliability_incidents
  where id=requested_incident_id for update;
  if not found then raise exception 'Reliability incident not found'; end if;
  if auth.role()<>'service_role' and not public.has_organization_permission(
    r.organization_id,'observability_reliability.acknowledge_alerts'
  ) then raise exception 'Permission denied'; end if;

  update public.observability_reliability_incidents set
    status=case when status='open' then 'acknowledged' else status end,
    acknowledged_at=coalesce(acknowledged_at,now()),
    time_to_acknowledge_seconds=coalesce(time_to_acknowledge_seconds,
      greatest(0,extract(epoch from (now()-detected_at))::bigint)),
    incident_commander_id=coalesce(incident_commander_id,auth.uid()),
    updated_by=auth.uid(),updated_at=now()
  where id=requested_incident_id returning * into r;

  insert into public.observability_incident_events(
    organization_id,incident_id,event_type,event_summary,event_data,performed_by,correlation_id,trace_id
  ) values (
    r.organization_id,r.id,'acknowledged','Reliability incident acknowledged',
    jsonb_build_object('notes',requested_notes),auth.uid(),r.correlation_id,r.trace_id
  );
  return r;
end;
$$;

create or replace function public.update_observability_incident_status(
  requested_incident_id uuid,
  requested_status text,
  requested_event_summary text default null,
  requested_event_data jsonb default '{}'::jsonb
)
returns public.observability_reliability_incidents
language plpgsql security definer set search_path=''
as $$
declare r public.observability_reliability_incidents;
begin
  select * into r from public.observability_reliability_incidents
  where id=requested_incident_id for update;
  if not found then raise exception 'Reliability incident not found'; end if;
  if auth.role()<>'service_role' and not public.has_organization_permission(
    r.organization_id,'observability_reliability.manage_incidents'
  ) then raise exception 'Permission denied'; end if;

  update public.observability_reliability_incidents set
    status=requested_status,
    acknowledged_at=case when requested_status='acknowledged' then coalesce(acknowledged_at,now()) else acknowledged_at end,
    investigation_started_at=case when requested_status='investigating' then coalesce(investigation_started_at,now()) else investigation_started_at end,
    identified_at=case when requested_status='identified' then coalesce(identified_at,now()) else identified_at end,
    monitoring_started_at=case when requested_status='monitoring' then coalesce(monitoring_started_at,now()) else monitoring_started_at end,
    resolved_at=case when requested_status='resolved' then coalesce(resolved_at,now()) else resolved_at end,
    closed_at=case when requested_status='closed' then coalesce(closed_at,now()) else closed_at end,
    time_to_resolve_seconds=case when requested_status='resolved' and time_to_resolve_seconds is null
      then greatest(0,extract(epoch from (now()-detected_at))::bigint) else time_to_resolve_seconds end,
    updated_by=auth.uid(),updated_at=now()
  where id=requested_incident_id returning * into r;

  insert into public.observability_incident_events(
    organization_id,incident_id,event_type,event_summary,event_data,performed_by,correlation_id,trace_id
  ) values (
    r.organization_id,r.id,case when requested_status='resolved' then 'resolved' else 'status_changed' end,
    coalesce(requested_event_summary,'Incident status changed to '||requested_status),
    coalesce(requested_event_data,'{}'::jsonb)||jsonb_build_object('status',requested_status),
    auth.uid(),r.correlation_id,r.trace_id
  );
  return r;
end;
$$;

-- 15. Event outbox, deployment recording and retention cleanup
create or replace function public.publish_observability_event(
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
returns public.observability_event_outbox
language plpgsql security definer set search_path=''
as $$
declare r public.observability_event_outbox;
begin
  if requested_idempotency_key is not null then
    select * into r from public.observability_event_outbox
    where organization_id is not distinct from requested_organization_id
      and idempotency_key=requested_idempotency_key limit 1;
    if found then return r; end if;
  end if;

  insert into public.observability_event_outbox(
    organization_id,event_name,source_type,source_id,destination,status,priority,
    idempotency_key,correlation_id,trace_id,payload,available_at
  ) values (
    requested_organization_id,requested_event_name,requested_source_type,requested_source_id,
    requested_destination,'pending',requested_priority,requested_idempotency_key,
    requested_correlation_id,requested_trace_id,coalesce(requested_payload,'{}'::jsonb),
    coalesce(requested_available_at,now())
  ) returning * into r;
  return r;
end;
$$;

create or replace function public.record_observability_deployment_event(
  requested_organization_id uuid,
  requested_environment_id uuid,
  requested_service_id uuid,
  requested_deployment_reference text,
  requested_deployment_type text,
  requested_status text,
  requested_started_at timestamptz,
  requested_completed_at timestamptz default null,
  requested_version_before text default null,
  requested_version_after text default null,
  requested_commit_reference text default null,
  requested_pipeline_reference text default null,
  requested_deployment_strategy text default null,
  requested_change_summary text default null,
  requested_related_incident_id uuid default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.observability_deployment_events
language plpgsql security definer set search_path=''
as $$
declare r public.observability_deployment_events;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.manage_services'
  ) then raise exception 'Permission denied'; end if;

  insert into public.observability_deployment_events(
    organization_id,environment_id,service_id,deployment_reference,deployment_type,
    version_before,version_after,commit_reference,pipeline_reference,status,
    deployment_strategy,change_summary,started_at,completed_at,deployed_by,
    related_incident_id,correlation_id,trace_id,metadata
  ) values (
    requested_organization_id,requested_environment_id,requested_service_id,
    requested_deployment_reference,requested_deployment_type,requested_version_before,
    requested_version_after,requested_commit_reference,requested_pipeline_reference,
    requested_status,requested_deployment_strategy,requested_change_summary,
    requested_started_at,requested_completed_at,auth.uid(),requested_related_incident_id,
    requested_correlation_id,requested_trace_id,coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (organization_id,environment_id,service_id,deployment_reference) do update set
    deployment_type=excluded.deployment_type,version_before=excluded.version_before,
    version_after=excluded.version_after,commit_reference=excluded.commit_reference,
    pipeline_reference=excluded.pipeline_reference,status=excluded.status,
    deployment_strategy=excluded.deployment_strategy,change_summary=excluded.change_summary,
    started_at=excluded.started_at,completed_at=excluded.completed_at,
    related_incident_id=excluded.related_incident_id,correlation_id=excluded.correlation_id,
    trace_id=excluded.trace_id,metadata=excluded.metadata
  returning * into r;
  return r;
end;
$$;

create or replace function public.purge_observability_telemetry(
  requested_organization_id uuid,
  requested_dry_run boolean default true,
  requested_batch_limit integer default 50000
)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare metric_days integer:=30;
log_days integer:=30;
trace_days integer:=14;
heartbeat_days integer:=30;
monitor_days integer:=90;
alert_days integer:=365;
counts jsonb;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(
    requested_organization_id,'observability_reliability.manage_retention'
  ) then raise exception 'Permission denied'; end if;

  select coalesce(min(retention_days) filter(where telemetry_type in ('metrics','all') and status='active'),30)
    into metric_days from public.observability_retention_policies where organization_id=requested_organization_id;
  select coalesce(min(retention_days) filter(where telemetry_type in ('logs','all') and status='active'),30)
    into log_days from public.observability_retention_policies where organization_id=requested_organization_id;
  select coalesce(min(retention_days) filter(where telemetry_type in ('traces','all') and status='active'),14)
    into trace_days from public.observability_retention_policies where organization_id=requested_organization_id;
  select coalesce(min(retention_days) filter(where telemetry_type in ('heartbeats','all') and status='active'),30)
    into heartbeat_days from public.observability_retention_policies where organization_id=requested_organization_id;
  select coalesce(min(retention_days) filter(where telemetry_type in ('monitor_runs','all') and status='active'),90)
    into monitor_days from public.observability_retention_policies where organization_id=requested_organization_id;
  select coalesce(min(retention_days) filter(where telemetry_type in ('alert_events','all') and status='active'),365)
    into alert_days from public.observability_retention_policies where organization_id=requested_organization_id;

  counts:=jsonb_build_object(
    'metrics',(select count(*) from public.observability_metric_samples where organization_id=requested_organization_id and observed_at<now()-make_interval(days=>metric_days)),
    'logs',(select count(*) from public.observability_log_events where organization_id=requested_organization_id and occurred_at<now()-make_interval(days=>log_days)),
    'traces',(select count(*) from public.observability_traces where organization_id=requested_organization_id and started_at<now()-make_interval(days=>trace_days)),
    'heartbeats',(select count(*) from public.observability_heartbeats where organization_id=requested_organization_id and observed_at<now()-make_interval(days=>heartbeat_days)),
    'monitor_runs',(select count(*) from public.observability_monitor_runs where organization_id=requested_organization_id and completed_at<now()-make_interval(days=>monitor_days)),
    'alert_events',(select count(*) from public.observability_alert_events where organization_id=requested_organization_id and occurred_at<now()-make_interval(days=>alert_days))
  );

  if not requested_dry_run then
    delete from public.observability_metric_samples where id in (
      select id from public.observability_metric_samples
      where organization_id=requested_organization_id and observed_at<now()-make_interval(days=>metric_days)
      order by observed_at limit greatest(requested_batch_limit,1)
    );
    delete from public.observability_log_events where id in (
      select id from public.observability_log_events
      where organization_id=requested_organization_id and occurred_at<now()-make_interval(days=>log_days)
      order by occurred_at limit greatest(requested_batch_limit,1)
    );
    delete from public.observability_traces where id in (
      select id from public.observability_traces
      where organization_id=requested_organization_id and started_at<now()-make_interval(days=>trace_days)
      order by started_at limit greatest(requested_batch_limit,1)
    );
    delete from public.observability_heartbeats where id in (
      select id from public.observability_heartbeats
      where organization_id=requested_organization_id and observed_at<now()-make_interval(days=>heartbeat_days)
      order by observed_at limit greatest(requested_batch_limit,1)
    );
    delete from public.observability_monitor_runs where id in (
      select id from public.observability_monitor_runs
      where organization_id=requested_organization_id and completed_at<now()-make_interval(days=>monitor_days)
      order by completed_at limit greatest(requested_batch_limit,1)
    );
    delete from public.observability_alert_events where id in (
      select id from public.observability_alert_events
      where organization_id=requested_organization_id and occurred_at<now()-make_interval(days=>alert_days)
      order by occurred_at limit greatest(requested_batch_limit,1)
    );
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,'dry_run',requested_dry_run,
    'batch_limit',greatest(requested_batch_limit,1),'eligible_records',counts,'completed_at',now()
  );
end;
$$;

-- 16. Event triggers
create or replace function public.emit_observability_service_status_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='UPDATE' and new.health_status is not distinct from old.health_status then return new; end if;
  perform public.publish_observability_event(
    new.organization_id,'observability.service.'||new.health_status,
    jsonb_build_object(
      'service_id',new.id,'service_code',new.service_code,'service_name',new.service_name,
      'environment_id',new.environment_id,'criticality',new.criticality,
      'health_status',new.health_status,'health_status_reason',new.health_status_reason,
      'last_heartbeat_at',new.last_heartbeat_at
    ),
    case when new.health_status in ('unhealthy','offline') then 'notification_engine'
      when new.health_status='degraded' then 'automation_engine' else 'analytics' end,
    'service',new.id,
    case when new.criticality='critical' and new.health_status in ('unhealthy','offline') then 1
      when new.health_status in ('unhealthy','offline') then 10 else 50 end,
    'obs-service:'||new.id::text||':'||new.health_status||':'||
      extract(epoch from date_trunc('minute',now()))::bigint::text,
    new.id::text,null,now()
  );
  return new;
end;
$$;

drop trigger if exists observability_services_emit_status_events on public.observability_services;
create trigger observability_services_emit_status_events
after insert or update on public.observability_services
for each row execute function public.emit_observability_service_status_events();

create or replace function public.emit_observability_incident_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='UPDATE' and new.status is not distinct from old.status
    and new.severity is not distinct from old.severity then return new; end if;
  perform public.publish_observability_event(
    new.organization_id,'observability.incident.'||new.status,
    jsonb_build_object(
      'incident_id',new.id,'incident_code',new.incident_code,
      'incident_title',new.incident_title,'incident_type',new.incident_type,
      'severity',new.severity,'priority',new.priority,'status',new.status,
      'environment_id',new.environment_id,'primary_service_id',new.primary_service_id,
      'customer_impact',new.customer_impact,'detected_at',new.detected_at,
      'resolved_at',new.resolved_at
    ),
    case when new.status in ('open','acknowledged','investigating')
      and new.severity in ('high','critical') then 'notification_engine'
      when new.status='resolved' then 'reporting' else 'analytics' end,
    'reliability_incident',new.id,
    case when new.severity='critical' then 1 when new.severity='high' then 10 else 50 end,
    'obs-incident:'||new.id::text||':'||new.status,
    coalesce(new.correlation_id,new.id::text),new.trace_id,now()
  );
  return new;
end;
$$;

drop trigger if exists observability_incidents_emit_events on public.observability_reliability_incidents;
create trigger observability_incidents_emit_events
after insert or update on public.observability_reliability_incidents
for each row execute function public.emit_observability_incident_events();

create or replace function public.emit_observability_deployment_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  perform public.publish_observability_event(
    new.organization_id,'observability.deployment.'||new.status,
    jsonb_build_object(
      'deployment_id',new.id,'deployment_reference',new.deployment_reference,
      'deployment_type',new.deployment_type,'environment_id',new.environment_id,
      'service_id',new.service_id,'version_before',new.version_before,
      'version_after',new.version_after,'status',new.status,'started_at',new.started_at,
      'completed_at',new.completed_at
    ),
    case when new.status='failed' then 'notification_engine' else 'analytics' end,
    'deployment',new.id,case when new.status='failed' then 10 else 100 end,
    'obs-deployment:'||new.id::text||':'||new.status,
    coalesce(new.correlation_id,new.id::text),new.trace_id,now()
  );
  return new;
end;
$$;

drop trigger if exists observability_deployments_emit_events on public.observability_deployment_events;
create trigger observability_deployments_emit_events
after insert or update on public.observability_deployment_events
for each row execute function public.emit_observability_deployment_events();

-- 17. Analytics views
create or replace view public.observability_service_health_dashboard
with (security_invoker=true) as
select
  s.organization_id,s.environment_id,e.environment_code,e.environment_name,
  s.service_type,s.criticality,s.health_status,
  count(*) as service_count,
  count(*) filter(where s.health_status='healthy') as healthy_count,
  count(*) filter(where s.health_status='degraded') as degraded_count,
  count(*) filter(where s.health_status in ('unhealthy','offline')) as unhealthy_count,
  count(*) filter(
    where s.expected_heartbeat_interval_seconds is not null and (
      s.last_heartbeat_at is null or
      s.last_heartbeat_at<now()-make_interval(
        secs=>s.expected_heartbeat_interval_seconds+s.heartbeat_grace_seconds
      )
    )
  ) as missing_heartbeat_count,
  max(s.last_heartbeat_at) as latest_heartbeat_at,
  max(s.updated_at) as latest_status_update_at
from public.observability_services s
join public.observability_environments e on e.id=s.environment_id
group by s.organization_id,s.environment_id,e.environment_code,e.environment_name,
  s.service_type,s.criticality,s.health_status;

create or replace view public.observability_monitor_dashboard
with (security_invoker=true) as
select
  organization_id,environment_id,service_id,monitor_type,current_status,status,
  count(*) as monitor_count,
  sum(consecutive_failures) as total_consecutive_failures,
  count(*) filter(where next_check_at is not null and next_check_at<now() and status='active')
    as overdue_monitor_count,
  max(last_checked_at) as latest_check_at,
  max(last_success_at) as latest_success_at,
  max(last_failure_at) as latest_failure_at
from public.observability_synthetic_monitors
group by organization_id,environment_id,service_id,monitor_type,current_status,status;

create or replace view public.observability_slo_dashboard
with (security_invoker=true) as
select
  s.organization_id,s.service_id,s.id as slo_id,s.slo_code,s.slo_name,
  s.target_percentage,s.status,
  m.window_start,m.window_end,m.achievement_percentage,m.burn_rate,m.target_met,
  b.budget_consumed_percentage,b.remaining_percentage,b.budget_status,b.forecast_exhaustion_at
from public.observability_slos s
left join lateral (
  select x.window_start,x.window_end,x.achievement_percentage,x.burn_rate,x.target_met
  from public.observability_slo_measurements x
  where x.slo_id=s.id order by x.window_end desc limit 1
) m on true
left join lateral (
  select x.budget_consumed_percentage,x.remaining_percentage,x.budget_status,x.forecast_exhaustion_at
  from public.observability_error_budget_snapshots x
  where x.slo_id=s.id order by x.period_end desc limit 1
) b on true;

create or replace view public.observability_incident_dashboard
with (security_invoker=true) as
select
  organization_id,incident_type,severity,status,count(*) as incident_count,
  round(avg(time_to_acknowledge_seconds),2) as average_tta_seconds,
  round(avg(time_to_resolve_seconds),2) as average_ttr_seconds,
  count(*) filter(where status not in ('resolved','closed','false_positive','cancelled','archived'))
    as active_incident_count,
  count(*) filter(where postmortem_required and postmortem_document_id is null
    and status in ('resolved','closed')) as missing_postmortem_count,
  max(detected_at) as latest_detected_at,max(resolved_at) as latest_resolved_at
from public.observability_reliability_incidents
group by organization_id,incident_type,severity,status;

create or replace view public.observability_alert_dashboard
with (security_invoker=true) as
select
  r.organization_id,r.alert_type,r.severity,r.status,
  count(distinct r.id) as alert_rule_count,
  count(e.id) filter(where e.event_type in ('triggered','retriggered')
    and e.occurred_at>=now()-interval '24 hours') as triggered_24h,
  count(e.id) filter(where e.event_type in ('recovered','resolved')
    and e.occurred_at>=now()-interval '24 hours') as recovered_24h,
  count(distinct e.incident_id) filter(where e.incident_id is not null) as linked_incident_count,
  max(r.last_evaluated_at) as latest_evaluation_at,max(r.last_triggered_at) as latest_triggered_at
from public.observability_alert_rules r
left join public.observability_alert_events e on e.alert_rule_id=r.id
group by r.organization_id,r.alert_type,r.severity,r.status;

grant select on
  public.observability_service_health_dashboard,
  public.observability_monitor_dashboard,
  public.observability_slo_dashboard,
  public.observability_incident_dashboard,
  public.observability_alert_dashboard
to authenticated,service_role;

-- 18. Module health
create or replace function public.get_observability_reliability_health(
  requested_organization_id uuid default null
)
returns jsonb
language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.role()<>'service_role' and (
    requested_organization_id is null or not public.has_organization_permission(
      requested_organization_id,'observability_reliability.view_logs'
    )
  ) then raise exception 'Permission denied'; end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,'checked_at',now(),
    'active_services',(
      select count(*) from public.observability_services s
      where s.lifecycle_status='active'
        and (requested_organization_id is null or s.organization_id=requested_organization_id)
    ),
    'unhealthy_services',(
      select count(*) from public.observability_services s
      where s.health_status in ('unhealthy','offline')
        and (requested_organization_id is null or s.organization_id=requested_organization_id)
    ),
    'missing_heartbeats',(
      select count(*) from public.observability_services s
      where s.expected_heartbeat_interval_seconds is not null
        and (s.last_heartbeat_at is null or s.last_heartbeat_at<now()-make_interval(
          secs=>s.expected_heartbeat_interval_seconds+s.heartbeat_grace_seconds
        ))
        and (requested_organization_id is null or s.organization_id=requested_organization_id)
    ),
    'down_monitors',(
      select count(*) from public.observability_synthetic_monitors m
      where m.status='active' and m.current_status='down'
        and (requested_organization_id is null or m.organization_id=requested_organization_id)
    ),
    'slo_breaches_24h',(
      select count(*) from public.observability_slo_measurements m
      join public.observability_slos s on s.id=m.slo_id
      where s.status='active' and m.target_met=false
        and m.window_end>=now()-interval '24 hours'
        and (requested_organization_id is null or m.organization_id=requested_organization_id)
    ),
    'active_incidents',(
      select count(*) from public.observability_reliability_incidents i
      where i.status not in ('resolved','closed','false_positive','cancelled','archived')
        and (requested_organization_id is null or i.organization_id=requested_organization_id)
    ),
    'critical_incidents',(
      select count(*) from public.observability_reliability_incidents i
      where i.severity='critical'
        and i.status not in ('resolved','closed','false_positive','cancelled','archived')
        and (requested_organization_id is null or i.organization_id=requested_organization_id)
    ),
    'queued_alert_evaluations',(
      select count(*) from public.observability_alert_evaluation_jobs j
      where j.status in ('queued','failed','claimed','processing')
        and (requested_organization_id is null or j.organization_id=requested_organization_id)
    ),
    'expired_worker_locks',(
      select count(*) from public.observability_alert_evaluation_jobs j
      where j.status='claimed' and j.lock_expires_at<=now()
        and (requested_organization_id is null or j.organization_id=requested_organization_id)
    ),
    'pending_outbox_events',(
      select count(*) from public.observability_event_outbox e
      where e.status in ('pending','failed')
        and (requested_organization_id is null or e.organization_id=requested_organization_id)
    )
  );
end;
$$;

-- 19. Row-level security
alter table public.observability_environments enable row level security;
alter table public.observability_services enable row level security;
alter table public.observability_service_dependencies enable row level security;
alter table public.observability_telemetry_sources enable row level security;
alter table public.observability_metric_definitions enable row level security;
alter table public.observability_metric_samples enable row level security;
alter table public.observability_log_events enable row level security;
alter table public.observability_traces enable row level security;
alter table public.observability_trace_spans enable row level security;
alter table public.observability_heartbeats enable row level security;
alter table public.observability_sli_definitions enable row level security;
alter table public.observability_slos enable row level security;
alter table public.observability_slo_measurements enable row level security;
alter table public.observability_error_budget_snapshots enable row level security;
alter table public.observability_escalation_policies enable row level security;
alter table public.observability_escalation_steps enable row level security;
alter table public.observability_alert_rules enable row level security;
alter table public.observability_synthetic_monitors enable row level security;
alter table public.observability_monitor_runs enable row level security;
alter table public.observability_alert_evaluation_jobs enable row level security;
alter table public.observability_reliability_incidents enable row level security;
alter table public.observability_alert_events enable row level security;
alter table public.observability_incident_events enable row level security;
alter table public.observability_oncall_schedules enable row level security;
alter table public.observability_oncall_shifts enable row level security;
alter table public.observability_maintenance_windows enable row level security;
alter table public.observability_deployment_events enable row level security;
alter table public.observability_runbooks enable row level security;
alter table public.observability_capacity_snapshots enable row level security;
alter table public.observability_retention_policies enable row level security;
alter table public.observability_event_outbox enable row level security;
alter table public.observability_engine_logs enable row level security;

drop policy if exists observability_environments_select_policy on public.observability_environments;
create policy observability_environments_select_policy
on public.observability_environments for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_environments_service_policy on public.observability_environments;
create policy observability_environments_service_policy
on public.observability_environments for all to service_role
using (true) with check (true);

drop policy if exists observability_services_select_policy on public.observability_services;
create policy observability_services_select_policy
on public.observability_services for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_services_service_policy on public.observability_services;
create policy observability_services_service_policy
on public.observability_services for all to service_role
using (true) with check (true);

drop policy if exists observability_service_dependencies_select_policy on public.observability_service_dependencies;
create policy observability_service_dependencies_select_policy
on public.observability_service_dependencies for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_service_dependencies_service_policy on public.observability_service_dependencies;
create policy observability_service_dependencies_service_policy
on public.observability_service_dependencies for all to service_role
using (true) with check (true);

drop policy if exists observability_telemetry_sources_select_policy on public.observability_telemetry_sources;
create policy observability_telemetry_sources_select_policy
on public.observability_telemetry_sources for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_telemetry_sources_service_policy on public.observability_telemetry_sources;
create policy observability_telemetry_sources_service_policy
on public.observability_telemetry_sources for all to service_role
using (true) with check (true);

drop policy if exists observability_metric_definitions_select_policy on public.observability_metric_definitions;
create policy observability_metric_definitions_select_policy
on public.observability_metric_definitions for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_metric_definitions_service_policy on public.observability_metric_definitions;
create policy observability_metric_definitions_service_policy
on public.observability_metric_definitions for all to service_role
using (true) with check (true);

drop policy if exists observability_metric_samples_select_policy on public.observability_metric_samples;
create policy observability_metric_samples_select_policy
on public.observability_metric_samples for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_metric_samples_service_policy on public.observability_metric_samples;
create policy observability_metric_samples_service_policy
on public.observability_metric_samples for all to service_role
using (true) with check (true);

drop policy if exists observability_log_events_select_policy on public.observability_log_events;
create policy observability_log_events_select_policy
on public.observability_log_events for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_log_events_service_policy on public.observability_log_events;
create policy observability_log_events_service_policy
on public.observability_log_events for all to service_role
using (true) with check (true);

drop policy if exists observability_traces_select_policy on public.observability_traces;
create policy observability_traces_select_policy
on public.observability_traces for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_traces_service_policy on public.observability_traces;
create policy observability_traces_service_policy
on public.observability_traces for all to service_role
using (true) with check (true);

drop policy if exists observability_trace_spans_select_policy on public.observability_trace_spans;
create policy observability_trace_spans_select_policy
on public.observability_trace_spans for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_trace_spans_service_policy on public.observability_trace_spans;
create policy observability_trace_spans_service_policy
on public.observability_trace_spans for all to service_role
using (true) with check (true);

drop policy if exists observability_heartbeats_select_policy on public.observability_heartbeats;
create policy observability_heartbeats_select_policy
on public.observability_heartbeats for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_heartbeats_service_policy on public.observability_heartbeats;
create policy observability_heartbeats_service_policy
on public.observability_heartbeats for all to service_role
using (true) with check (true);

drop policy if exists observability_sli_definitions_select_policy on public.observability_sli_definitions;
create policy observability_sli_definitions_select_policy
on public.observability_sli_definitions for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_sli_definitions_service_policy on public.observability_sli_definitions;
create policy observability_sli_definitions_service_policy
on public.observability_sli_definitions for all to service_role
using (true) with check (true);

drop policy if exists observability_slos_select_policy on public.observability_slos;
create policy observability_slos_select_policy
on public.observability_slos for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_slos_service_policy on public.observability_slos;
create policy observability_slos_service_policy
on public.observability_slos for all to service_role
using (true) with check (true);

drop policy if exists observability_slo_measurements_select_policy on public.observability_slo_measurements;
create policy observability_slo_measurements_select_policy
on public.observability_slo_measurements for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_slo_measurements_service_policy on public.observability_slo_measurements;
create policy observability_slo_measurements_service_policy
on public.observability_slo_measurements for all to service_role
using (true) with check (true);

drop policy if exists observability_error_budget_snapshots_select_policy on public.observability_error_budget_snapshots;
create policy observability_error_budget_snapshots_select_policy
on public.observability_error_budget_snapshots for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_error_budget_snapshots_service_policy on public.observability_error_budget_snapshots;
create policy observability_error_budget_snapshots_service_policy
on public.observability_error_budget_snapshots for all to service_role
using (true) with check (true);

drop policy if exists observability_escalation_policies_select_policy on public.observability_escalation_policies;
create policy observability_escalation_policies_select_policy
on public.observability_escalation_policies for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_escalation_policies_service_policy on public.observability_escalation_policies;
create policy observability_escalation_policies_service_policy
on public.observability_escalation_policies for all to service_role
using (true) with check (true);

drop policy if exists observability_escalation_steps_select_policy on public.observability_escalation_steps;
create policy observability_escalation_steps_select_policy
on public.observability_escalation_steps for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_escalation_steps_service_policy on public.observability_escalation_steps;
create policy observability_escalation_steps_service_policy
on public.observability_escalation_steps for all to service_role
using (true) with check (true);

drop policy if exists observability_alert_rules_select_policy on public.observability_alert_rules;
create policy observability_alert_rules_select_policy
on public.observability_alert_rules for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_alert_rules_service_policy on public.observability_alert_rules;
create policy observability_alert_rules_service_policy
on public.observability_alert_rules for all to service_role
using (true) with check (true);

drop policy if exists observability_synthetic_monitors_select_policy on public.observability_synthetic_monitors;
create policy observability_synthetic_monitors_select_policy
on public.observability_synthetic_monitors for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_synthetic_monitors_service_policy on public.observability_synthetic_monitors;
create policy observability_synthetic_monitors_service_policy
on public.observability_synthetic_monitors for all to service_role
using (true) with check (true);

drop policy if exists observability_monitor_runs_select_policy on public.observability_monitor_runs;
create policy observability_monitor_runs_select_policy
on public.observability_monitor_runs for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_monitor_runs_service_policy on public.observability_monitor_runs;
create policy observability_monitor_runs_service_policy
on public.observability_monitor_runs for all to service_role
using (true) with check (true);

drop policy if exists observability_alert_evaluation_jobs_select_policy on public.observability_alert_evaluation_jobs;
create policy observability_alert_evaluation_jobs_select_policy
on public.observability_alert_evaluation_jobs for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_alert_evaluation_jobs_service_policy on public.observability_alert_evaluation_jobs;
create policy observability_alert_evaluation_jobs_service_policy
on public.observability_alert_evaluation_jobs for all to service_role
using (true) with check (true);

drop policy if exists observability_reliability_incidents_select_policy on public.observability_reliability_incidents;
create policy observability_reliability_incidents_select_policy
on public.observability_reliability_incidents for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_reliability_incidents_service_policy on public.observability_reliability_incidents;
create policy observability_reliability_incidents_service_policy
on public.observability_reliability_incidents for all to service_role
using (true) with check (true);

drop policy if exists observability_alert_events_select_policy on public.observability_alert_events;
create policy observability_alert_events_select_policy
on public.observability_alert_events for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_alert_events_service_policy on public.observability_alert_events;
create policy observability_alert_events_service_policy
on public.observability_alert_events for all to service_role
using (true) with check (true);

drop policy if exists observability_incident_events_select_policy on public.observability_incident_events;
create policy observability_incident_events_select_policy
on public.observability_incident_events for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_incident_events_service_policy on public.observability_incident_events;
create policy observability_incident_events_service_policy
on public.observability_incident_events for all to service_role
using (true) with check (true);

drop policy if exists observability_oncall_schedules_select_policy on public.observability_oncall_schedules;
create policy observability_oncall_schedules_select_policy
on public.observability_oncall_schedules for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_oncall_schedules_service_policy on public.observability_oncall_schedules;
create policy observability_oncall_schedules_service_policy
on public.observability_oncall_schedules for all to service_role
using (true) with check (true);

drop policy if exists observability_oncall_shifts_select_policy on public.observability_oncall_shifts;
create policy observability_oncall_shifts_select_policy
on public.observability_oncall_shifts for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_oncall_shifts_service_policy on public.observability_oncall_shifts;
create policy observability_oncall_shifts_service_policy
on public.observability_oncall_shifts for all to service_role
using (true) with check (true);

drop policy if exists observability_maintenance_windows_select_policy on public.observability_maintenance_windows;
create policy observability_maintenance_windows_select_policy
on public.observability_maintenance_windows for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_maintenance_windows_service_policy on public.observability_maintenance_windows;
create policy observability_maintenance_windows_service_policy
on public.observability_maintenance_windows for all to service_role
using (true) with check (true);

drop policy if exists observability_deployment_events_select_policy on public.observability_deployment_events;
create policy observability_deployment_events_select_policy
on public.observability_deployment_events for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_deployment_events_service_policy on public.observability_deployment_events;
create policy observability_deployment_events_service_policy
on public.observability_deployment_events for all to service_role
using (true) with check (true);

drop policy if exists observability_runbooks_select_policy on public.observability_runbooks;
create policy observability_runbooks_select_policy
on public.observability_runbooks for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_runbooks_service_policy on public.observability_runbooks;
create policy observability_runbooks_service_policy
on public.observability_runbooks for all to service_role
using (true) with check (true);

drop policy if exists observability_capacity_snapshots_select_policy on public.observability_capacity_snapshots;
create policy observability_capacity_snapshots_select_policy
on public.observability_capacity_snapshots for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_capacity_snapshots_service_policy on public.observability_capacity_snapshots;
create policy observability_capacity_snapshots_service_policy
on public.observability_capacity_snapshots for all to service_role
using (true) with check (true);

drop policy if exists observability_retention_policies_select_policy on public.observability_retention_policies;
create policy observability_retention_policies_select_policy
on public.observability_retention_policies for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_retention_policies_service_policy on public.observability_retention_policies;
create policy observability_retention_policies_service_policy
on public.observability_retention_policies for all to service_role
using (true) with check (true);

drop policy if exists observability_event_outbox_select_policy on public.observability_event_outbox;
create policy observability_event_outbox_select_policy
on public.observability_event_outbox for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_event_outbox_service_policy on public.observability_event_outbox;
create policy observability_event_outbox_service_policy
on public.observability_event_outbox for all to service_role
using (true) with check (true);

drop policy if exists observability_engine_logs_select_policy on public.observability_engine_logs;
create policy observability_engine_logs_select_policy
on public.observability_engine_logs for select to authenticated
using (
  public.has_organization_permission(organization_id,'observability_reliability.view')
  or public.has_organization_permission(organization_id,'observability_reliability.view_all')
);

drop policy if exists observability_engine_logs_service_policy on public.observability_engine_logs;
create policy observability_engine_logs_service_policy
on public.observability_engine_logs for all to service_role
using (true) with check (true);

drop policy if exists observability_incidents_manage_policy
on public.observability_reliability_incidents;
create policy observability_incidents_manage_policy
on public.observability_reliability_incidents
for all to authenticated
using (public.has_organization_permission(organization_id,'observability_reliability.manage_incidents'))
with check (public.has_organization_permission(organization_id,'observability_reliability.manage_incidents'));

drop policy if exists observability_alert_rules_manage_policy
on public.observability_alert_rules;
create policy observability_alert_rules_manage_policy
on public.observability_alert_rules
for all to authenticated
using (public.has_organization_permission(organization_id,'observability_reliability.manage_alerts'))
with check (public.has_organization_permission(organization_id,'observability_reliability.manage_alerts'));

-- 20. Grants
grant select on
  public.observability_environments,
  public.observability_services,
  public.observability_service_dependencies,
  public.observability_telemetry_sources,
  public.observability_metric_definitions,
  public.observability_metric_samples,
  public.observability_log_events,
  public.observability_traces,
  public.observability_trace_spans,
  public.observability_heartbeats,
  public.observability_sli_definitions,
  public.observability_slos,
  public.observability_slo_measurements,
  public.observability_error_budget_snapshots,
  public.observability_escalation_policies,
  public.observability_escalation_steps,
  public.observability_alert_rules,
  public.observability_synthetic_monitors,
  public.observability_monitor_runs,
  public.observability_alert_evaluation_jobs,
  public.observability_reliability_incidents,
  public.observability_alert_events,
  public.observability_incident_events,
  public.observability_oncall_schedules,
  public.observability_oncall_shifts,
  public.observability_maintenance_windows,
  public.observability_deployment_events,
  public.observability_runbooks,
  public.observability_capacity_snapshots,
  public.observability_retention_policies,
  public.observability_event_outbox,
  public.observability_engine_logs
to authenticated;

grant insert,update,delete on
  public.observability_environments,
  public.observability_services,
  public.observability_service_dependencies,
  public.observability_telemetry_sources,
  public.observability_metric_definitions,
  public.observability_sli_definitions,
  public.observability_slos,
  public.observability_escalation_policies,
  public.observability_escalation_steps,
  public.observability_alert_rules,
  public.observability_synthetic_monitors,
  public.observability_reliability_incidents,
  public.observability_oncall_schedules,
  public.observability_oncall_shifts,
  public.observability_maintenance_windows,
  public.observability_runbooks,
  public.observability_retention_policies
to authenticated;

grant all on
  public.observability_environments,
  public.observability_services,
  public.observability_service_dependencies,
  public.observability_telemetry_sources,
  public.observability_metric_definitions,
  public.observability_metric_samples,
  public.observability_log_events,
  public.observability_traces,
  public.observability_trace_spans,
  public.observability_heartbeats,
  public.observability_sli_definitions,
  public.observability_slos,
  public.observability_slo_measurements,
  public.observability_error_budget_snapshots,
  public.observability_escalation_policies,
  public.observability_escalation_steps,
  public.observability_alert_rules,
  public.observability_synthetic_monitors,
  public.observability_monitor_runs,
  public.observability_alert_evaluation_jobs,
  public.observability_reliability_incidents,
  public.observability_alert_events,
  public.observability_incident_events,
  public.observability_oncall_schedules,
  public.observability_oncall_shifts,
  public.observability_maintenance_windows,
  public.observability_deployment_events,
  public.observability_runbooks,
  public.observability_capacity_snapshots,
  public.observability_retention_policies,
  public.observability_event_outbox,
  public.observability_engine_logs
to service_role;

revoke all on function public.register_observability_environment(uuid,text,text,text,text,text,text,text,text,jsonb) from public;
grant execute on function public.register_observability_environment(uuid,text,text,text,text,text,text,text,text,jsonb) to authenticated,service_role;

revoke all on function public.register_observability_service(uuid,uuid,text,text,text,text,uuid,text,text,integer,integer,jsonb,jsonb) from public;
grant execute on function public.register_observability_service(uuid,uuid,text,text,text,text,uuid,text,text,integer,integer,jsonb,jsonb) to authenticated,service_role;

revoke all on function public.register_observability_metric_definition(uuid,uuid,text,text,text,text,text,text,integer,jsonb,jsonb) from public;
grant execute on function public.register_observability_metric_definition(uuid,uuid,text,text,text,text,text,text,integer,jsonb,jsonb) to authenticated,service_role;

revoke all on function public.ingest_observability_metric(uuid,uuid,numeric,uuid,jsonb,jsonb,timestamptz,text,text,text) from public;
grant execute on function public.ingest_observability_metric(uuid,uuid,numeric,uuid,jsonb,jsonb,timestamptz,text,text,text) to authenticated,service_role;

revoke all on function public.ingest_observability_log(uuid,uuid,text,text,uuid,text,text,text,text,text,jsonb,timestamptz,text,text,text,text,text) from public;
grant execute on function public.ingest_observability_log(uuid,uuid,text,text,uuid,text,text,text,text,text,jsonb,timestamptz,text,text,text,text,text) to authenticated,service_role;

revoke all on function public.record_observability_heartbeat(uuid,uuid,text,uuid,integer,text,text,text,jsonb,jsonb,timestamptz,text) from public;
grant execute on function public.record_observability_heartbeat(uuid,uuid,text,uuid,integer,text,text,text,jsonb,jsonb,timestamptz,text) to authenticated,service_role;

revoke all on function public.upsert_observability_trace(uuid,uuid,text,timestamptz,uuid,text,text,text,timestamptz,text,jsonb,jsonb,text) from public;
grant execute on function public.upsert_observability_trace(uuid,uuid,text,timestamptz,uuid,text,text,text,timestamptz,text,jsonb,jsonb,text) to authenticated,service_role;

revoke all on function public.upsert_observability_trace_span(uuid,text,text,timestamptz,uuid,text,text,text,text,timestamptz,text,text,jsonb,jsonb,jsonb) from public;
grant execute on function public.upsert_observability_trace_span(uuid,text,text,timestamptz,uuid,text,text,text,text,timestamptz,text,text,jsonb,jsonb,jsonb) to authenticated,service_role;

revoke all on function public.record_observability_slo_measurement(uuid,timestamptz,timestamptz,bigint,bigint,text,jsonb) from public;
grant execute on function public.record_observability_slo_measurement(uuid,timestamptz,timestamptz,bigint,bigint,text,jsonb) to authenticated,service_role;

revoke all on function public.record_observability_monitor_run(uuid,text,text,timestamptz,timestamptz,text,integer,integer,jsonb,jsonb,text,text,text,text,text) from public;
grant execute on function public.record_observability_monitor_run(uuid,text,text,timestamptz,timestamptz,text,integer,integer,jsonb,jsonb,text,text,text,text,text) to authenticated,service_role;

revoke all on function public.enqueue_observability_alert_evaluation(uuid,text,timestamptz,integer,timestamptz,timestamptz,jsonb,text,text) from public;
grant execute on function public.enqueue_observability_alert_evaluation(uuid,text,timestamptz,integer,timestamptz,timestamptz,jsonb,text,text) to authenticated,service_role;

revoke all on function public.claim_observability_alert_evaluation_job(text,uuid,integer) from public;
grant execute on function public.claim_observability_alert_evaluation_job(text,uuid,integer) to service_role;

revoke all on function public.complete_observability_alert_evaluation_job(uuid,text,jsonb) from public;
grant execute on function public.complete_observability_alert_evaluation_job(uuid,text,jsonb) to service_role;

revoke all on function public.fail_observability_alert_evaluation_job(uuid,text,text,text,jsonb) from public;
grant execute on function public.fail_observability_alert_evaluation_job(uuid,text,text,text,jsonb) to service_role;

revoke all on function public.open_observability_reliability_incident(uuid,text,text,text,uuid,uuid,text,uuid,text,uuid[],uuid,uuid,text,text,text,jsonb) from public;
grant execute on function public.open_observability_reliability_incident(uuid,text,text,text,uuid,uuid,text,uuid,text,uuid[],uuid,uuid,text,text,text,jsonb) to authenticated,service_role;

revoke all on function public.record_observability_alert_event(uuid,text,text,text,text,numeric,numeric,jsonb,text,text) from public;
grant execute on function public.record_observability_alert_event(uuid,text,text,text,text,numeric,numeric,jsonb,text,text) to authenticated,service_role;

revoke all on function public.acknowledge_observability_incident(uuid,text) from public;
grant execute on function public.acknowledge_observability_incident(uuid,text) to authenticated,service_role;

revoke all on function public.update_observability_incident_status(uuid,text,text,jsonb) from public;
grant execute on function public.update_observability_incident_status(uuid,text,text,jsonb) to authenticated,service_role;

revoke all on function public.publish_observability_event(uuid,text,jsonb,text,text,uuid,integer,text,text,text,timestamptz) from public;
grant execute on function public.publish_observability_event(uuid,text,jsonb,text,text,uuid,integer,text,text,text,timestamptz) to authenticated,service_role;

revoke all on function public.record_observability_deployment_event(uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,text,text,text,text,text,text,uuid,text,text,jsonb) from public;
grant execute on function public.record_observability_deployment_event(uuid,uuid,uuid,text,text,text,timestamptz,timestamptz,text,text,text,text,text,text,uuid,text,text,jsonb) to authenticated,service_role;

revoke all on function public.purge_observability_telemetry(uuid,boolean,integer) from public;
grant execute on function public.purge_observability_telemetry(uuid,boolean,integer) to authenticated,service_role;

revoke all on function public.get_observability_reliability_health(uuid) from public;
grant execute on function public.get_observability_reliability_health(uuid) to authenticated,service_role;


-- 21. Default retention policies
insert into public.observability_retention_policies(
  organization_id,policy_code,policy_name,telemetry_type,retention_days,status,metadata
)
select
  o.id,s.policy_code,s.policy_name,s.telemetry_type,s.retention_days,'active',
  jsonb_build_object('seeded_by_migration','030','default_policy',true)
from public.organizations o
cross join (
  values
    ('metrics_default','Metrics retention','metrics',30),
    ('logs_default','Logs retention','logs',30),
    ('traces_default','Traces retention','traces',14),
    ('heartbeats_default','Heartbeats retention','heartbeats',30),
    ('monitor_runs_default','Monitor runs retention','monitor_runs',90),
    ('alert_events_default','Alert events retention','alert_events',365),
    ('capacity_default','Capacity retention','capacity',90)
) s(policy_code,policy_name,telemetry_type,retention_days)
where not exists (
  select 1 from public.observability_retention_policies p
  where p.organization_id=o.id and p.policy_code=s.policy_code
);

-- 22. Final validation
do $$
declare item text;
missing_items text[]:='{}';
begin
  foreach item in array array[
    'observability_environments','observability_services','observability_service_dependencies',
    'observability_telemetry_sources','observability_metric_definitions','observability_metric_samples',
    'observability_log_events','observability_traces','observability_trace_spans',
    'observability_heartbeats','observability_sli_definitions','observability_slos',
    'observability_slo_measurements','observability_error_budget_snapshots',
    'observability_escalation_policies','observability_escalation_steps','observability_alert_rules',
    'observability_synthetic_monitors','observability_monitor_runs',
    'observability_alert_evaluation_jobs','observability_reliability_incidents',
    'observability_alert_events','observability_incident_events','observability_oncall_schedules',
    'observability_oncall_shifts','observability_maintenance_windows',
    'observability_deployment_events','observability_runbooks',
    'observability_capacity_snapshots','observability_retention_policies',
    'observability_event_outbox','observability_engine_logs'
  ] loop
    if not exists (
      select 1 from information_schema.tables
      where table_schema='public' and table_name=item
    ) then missing_items:=array_append(missing_items,'table:'||item); end if;
  end loop;

  foreach item in array array[
    'register_observability_environment','register_observability_service',
    'register_observability_metric_definition','ingest_observability_metric',
    'ingest_observability_log','record_observability_heartbeat',
    'upsert_observability_trace','upsert_observability_trace_span',
    'record_observability_slo_measurement','record_observability_monitor_run',
    'enqueue_observability_alert_evaluation','claim_observability_alert_evaluation_job',
    'complete_observability_alert_evaluation_job','fail_observability_alert_evaluation_job',
    'open_observability_reliability_incident','record_observability_alert_event',
    'acknowledge_observability_incident','update_observability_incident_status',
    'publish_observability_event','record_observability_deployment_event',
    'purge_observability_telemetry','get_observability_reliability_health'
  ] loop
    if not exists (
      select 1 from information_schema.routines
      where routine_schema='public' and routine_name=item
    ) then missing_items:=array_append(missing_items,'function:'||item); end if;
  end loop;

  if cardinality(missing_items)>0 then
    raise exception '030 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- 23. Migration audit
insert into public.observability_engine_logs(
  organization_id,log_level,event_name,message,source_type,log_data
)
select
  o.id,'info','migration.030.completed',
  'Observability, Monitoring and Reliability Engine migration 030 completed',
  'migration',
  jsonb_build_object(
    'migration','030_observability_monitoring_reliability_engine',
    'completed_at',now(),
    'modules',jsonb_build_array(
      'environments','service_catalog','dependencies','telemetry_sources','metrics',
      'logs','traces','heartbeats','synthetic_monitors','sli','slo','error_budgets',
      'alert_rules','alert_queue','alert_events','reliability_incidents',
      'escalation','oncall','maintenance','deployments','runbooks','capacity',
      'retention','analytics','event_outbox'
    )
  )
from public.organizations o
where not exists (
  select 1 from public.observability_engine_logs l
  where l.organization_id=o.id and l.event_name='migration.030.completed'
);

commit;