-- ============================================================
-- SalesSetu Enterprise
-- Migration 034: Feature Flag & Configuration Engine
-- PostgreSQL / Supabase
-- ============================================================
-- Provides tenant-aware feature flags, staged rollouts, targeting,
-- emergency kill switches, versioned configuration, SDK clients,
-- snapshots, exposure analytics, event outbox, RLS and audit logs.
-- ============================================================

begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ============================================================
-- 1. PERMISSIONS
-- ============================================================

insert into public.permissions (module,action,code,description)
select v.module,v.action,v.code,v.description
from (
  values
    ('feature_configuration','view','feature_configuration.view','View feature flags and configuration'),
    ('feature_configuration','view_all','feature_configuration.view_all','View all feature and configuration data'),
    ('feature_configuration','manage_flags','feature_configuration.manage_flags','Manage feature flags'),
    ('feature_configuration','manage_rules','feature_configuration.manage_rules','Manage feature targeting rules and segments'),
    ('feature_configuration','manage_overrides','feature_configuration.manage_overrides','Manage feature overrides'),
    ('feature_configuration','manage_config','feature_configuration.manage_config','Manage versioned configuration'),
    ('feature_configuration','approve_changes','feature_configuration.approve_changes','Approve controlled changes'),
    ('feature_configuration','manage_sdk','feature_configuration.manage_sdk','Manage feature SDK clients'),
    ('feature_configuration','manage_kill_switch','feature_configuration.manage_kill_switch','Manage emergency kill switches'),
    ('feature_configuration','view_exposures','feature_configuration.view_exposures','View feature exposures'),
    ('feature_configuration','view_logs','feature_configuration.view_logs','View feature configuration logs'),
    ('feature_configuration','view_analytics','feature_configuration.view_analytics','View feature analytics')
) v(module,action,code,description)
where not exists (
  select 1 from public.permissions p where p.code=v.code
);

insert into public.role_permissions (role_id,permission_id)
select r.id,p.id
from public.roles r
cross join public.permissions p
where r.code in ('platform_admin','organization_admin')
  and p.module='feature_configuration'
on conflict (role_id,permission_id) do nothing;

-- ============================================================
-- 2. ENVIRONMENTS
-- ============================================================

create table if not exists public.feature_environments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  environment_code text not null,
  environment_name text not null,
  description text,
  environment_type text not null default 'production'
    check (environment_type in ('development','test','staging','preview','production','disaster_recovery','custom')),
  is_default boolean not null default false,
  is_production boolean not null default false,
  evaluation_enabled boolean not null default true,
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',
  status text not null default 'active'
    check (status in ('active','inactive','archived')),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_environments_org_code_uidx
  on public.feature_environments(organization_id,environment_code)
  where organization_id is not null;

create unique index if not exists feature_environments_global_code_uidx
  on public.feature_environments(environment_code)
  where organization_id is null;

create unique index if not exists feature_environments_org_default_uidx
  on public.feature_environments(organization_id)
  where organization_id is not null and is_default=true and status='active';

create unique index if not exists feature_environments_global_default_uidx
  on public.feature_environments((is_default))
  where organization_id is null and is_default=true and status='active';

-- ============================================================
-- 3. FEATURE FLAGS AND VARIANTS
-- ============================================================

create table if not exists public.feature_flags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  feature_key text not null,
  feature_name text not null,
  description text,
  module_code text,
  owner_team text,
  flag_type text not null default 'boolean'
    check (flag_type in ('boolean','string','number','json','multivariate')),
  lifecycle_stage text not null default 'development'
    check (lifecycle_stage in ('development','internal','beta','general_availability','deprecated','retired')),
  default_enabled boolean not null default false,
  default_variant_key text not null default 'off',
  evaluation_enabled boolean not null default true,
  prerequisites jsonb not null default '[]',
  prerequisite_mode text not null default 'all'
    check (prerequisite_mode in ('all','any')),
  tags text[] not null default '{}',
  change_control_required boolean not null default false,
  exposure_logging_enabled boolean not null default true,
  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_flags_org_key_uidx
  on public.feature_flags(organization_id,feature_key)
  where organization_id is not null;

create unique index if not exists feature_flags_global_key_uidx
  on public.feature_flags(feature_key)
  where organization_id is null;

create index if not exists feature_flags_module_idx
  on public.feature_flags(organization_id,module_code,lifecycle_stage,status);

create table if not exists public.feature_flag_variants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  feature_flag_id uuid not null references public.feature_flags(id) on delete cascade,
  variant_key text not null,
  variant_name text not null,
  description text,
  boolean_value boolean,
  string_value text,
  number_value numeric,
  json_value jsonb,
  is_control boolean not null default false,
  is_enabled_variant boolean not null default true,
  weight numeric(8,4) not null default 0 check (weight between 0 and 100),
  sequence_number integer not null default 100,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(feature_flag_id,variant_key)
);

create table if not exists public.feature_flag_environment_state (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  feature_flag_id uuid not null references public.feature_flags(id) on delete cascade,
  environment_id uuid not null references public.feature_environments(id) on delete cascade,
  enabled boolean not null default false,
  default_variant_key text,
  rollout_percentage numeric(8,4) not null default 0 check (rollout_percentage between 0 and 100),
  rollout_stickiness_key text not null default 'user_id',
  emergency_disabled boolean not null default false,
  emergency_reason text,
  emergency_activated_at timestamptz,
  emergency_activated_by uuid references auth.users(id) on delete set null,
  scheduled_enable_at timestamptz,
  scheduled_disable_at timestamptz,
  version integer not null default 1 check (version>=1),
  status text not null default 'active' check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_flag_environment_state_org_uidx
  on public.feature_flag_environment_state(organization_id,feature_flag_id,environment_id)
  where organization_id is not null;

create unique index if not exists feature_flag_environment_state_global_uidx
  on public.feature_flag_environment_state(feature_flag_id,environment_id)
  where organization_id is null;

-- ============================================================
-- 4. SEGMENTS, RULES AND OVERRIDES
-- ============================================================

create table if not exists public.feature_segments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  segment_key text not null,
  segment_name text not null,
  description text,
  match_mode text not null default 'all' check (match_mode in ('all','any')),
  conditions jsonb not null default '[]',
  status text not null default 'active' check (status in ('draft','active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_segments_org_key_uidx
  on public.feature_segments(organization_id,segment_key)
  where organization_id is not null;

create unique index if not exists feature_segments_global_key_uidx
  on public.feature_segments(segment_key)
  where organization_id is null;

create table if not exists public.feature_segment_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  segment_id uuid not null references public.feature_segments(id) on delete cascade,
  subject_type text not null
    check (subject_type in ('user','organization','role','plan','email','phone','device','custom')),
  subject_key text not null,
  inclusion_type text not null default 'include' check (inclusion_type in ('include','exclude')),
  starts_at timestamptz,
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(segment_id,subject_type,subject_key,inclusion_type)
);

create table if not exists public.feature_flag_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  feature_flag_id uuid not null references public.feature_flags(id) on delete cascade,
  environment_id uuid not null references public.feature_environments(id) on delete cascade,
  rule_key text not null,
  rule_name text not null,
  description text,
  priority integer not null default 100,
  match_mode text not null default 'all' check (match_mode in ('all','any')),
  conditions jsonb not null default '[]',
  segment_ids uuid[] not null default '{}',
  serve_enabled boolean,
  serve_variant_key text,
  rollout_percentage numeric(8,4)
    check (rollout_percentage is null or rollout_percentage between 0 and 100),
  rollout_variants jsonb not null default '[]',
  stickiness_key text,
  starts_at timestamptz,
  expires_at timestamptz,
  stop_evaluation boolean not null default true,
  status text not null default 'active' check (status in ('draft','active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_flag_rules_org_uidx
  on public.feature_flag_rules(organization_id,feature_flag_id,environment_id,rule_key)
  where organization_id is not null;

create unique index if not exists feature_flag_rules_global_uidx
  on public.feature_flag_rules(feature_flag_id,environment_id,rule_key)
  where organization_id is null;

create index if not exists feature_flag_rules_eval_idx
  on public.feature_flag_rules(organization_id,feature_flag_id,environment_id,status,priority);

create table if not exists public.feature_flag_overrides (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  feature_flag_id uuid not null references public.feature_flags(id) on delete cascade,
  environment_id uuid not null references public.feature_environments(id) on delete cascade,
  target_type text not null
    check (target_type in ('user','organization','role','plan','email','phone','device','session','custom')),
  target_key text not null,
  enabled boolean,
  variant_key text,
  priority integer not null default 10,
  reason text,
  starts_at timestamptz,
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_flag_overrides_org_uidx
  on public.feature_flag_overrides(organization_id,feature_flag_id,environment_id,target_type,target_key)
  where organization_id is not null;

create unique index if not exists feature_flag_overrides_global_uidx
  on public.feature_flag_overrides(feature_flag_id,environment_id,target_type,target_key)
  where organization_id is null;

create index if not exists feature_flag_overrides_eval_idx
  on public.feature_flag_overrides(organization_id,feature_flag_id,environment_id,target_type,target_key,status,priority);

-- ============================================================
-- 5. KILL SWITCHES
-- ============================================================

create table if not exists public.feature_kill_switches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  switch_key text not null,
  switch_name text not null,
  description text,
  scope_type text not null default 'feature'
    check (scope_type in ('feature','module','organization','environment','platform')),
  feature_flag_id uuid references public.feature_flags(id) on delete cascade,
  environment_id uuid references public.feature_environments(id) on delete cascade,
  module_code text,
  active boolean not null default false,
  force_enabled boolean,
  force_variant_key text,
  severity text not null default 'critical' check (severity in ('info','warning','high','critical')),
  activation_reason text,
  activated_at timestamptz,
  activated_by uuid references auth.users(id) on delete set null,
  released_at timestamptz,
  released_by uuid references auth.users(id) on delete set null,
  release_reason text,
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_kill_switches_org_key_uidx
  on public.feature_kill_switches(organization_id,switch_key)
  where organization_id is not null;

create unique index if not exists feature_kill_switches_global_key_uidx
  on public.feature_kill_switches(switch_key)
  where organization_id is null;

-- ============================================================
-- 6. CONFIGURATION ENGINE
-- ============================================================

create table if not exists public.configuration_namespaces (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  namespace_key text not null,
  namespace_name text not null,
  description text,
  module_code text,
  schema_definition jsonb not null default '{}',
  validation_enabled boolean not null default false,
  change_control_required boolean not null default false,
  status text not null default 'active' check (status in ('draft','active','inactive','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists configuration_namespaces_org_key_uidx
  on public.configuration_namespaces(organization_id,namespace_key)
  where organization_id is not null;

create unique index if not exists configuration_namespaces_global_key_uidx
  on public.configuration_namespaces(namespace_key)
  where organization_id is null;

create table if not exists public.configuration_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  namespace_id uuid not null references public.configuration_namespaces(id) on delete cascade,
  environment_id uuid references public.feature_environments(id) on delete cascade,
  configuration_key text not null,
  display_name text,
  description text,
  value_type text not null default 'json'
    check (value_type in ('boolean','string','number','json','secret_reference')),
  boolean_value boolean,
  string_value text,
  number_value numeric,
  json_value jsonb,
  secret_reference text,
  default_value jsonb,
  is_sensitive boolean not null default false,
  is_required boolean not null default false,
  is_read_only boolean not null default false,
  inheritance_mode text not null default 'inherit' check (inheritance_mode in ('inherit','override','locked')),
  version integer not null default 1 check (version>=1),
  effective_from timestamptz not null default now(),
  effective_until timestamptz,
  status text not null default 'active' check (status in ('draft','active','inactive','archived')),
  checksum text,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists configuration_entries_org_env_key_uidx
  on public.configuration_entries(namespace_id,organization_id,environment_id,configuration_key)
  where organization_id is not null and environment_id is not null and status<>'archived';

create unique index if not exists configuration_entries_org_key_uidx
  on public.configuration_entries(namespace_id,organization_id,configuration_key)
  where organization_id is not null and environment_id is null and status<>'archived';

create unique index if not exists configuration_entries_global_env_key_uidx
  on public.configuration_entries(namespace_id,environment_id,configuration_key)
  where organization_id is null and environment_id is not null and status<>'archived';

create unique index if not exists configuration_entries_global_key_uidx
  on public.configuration_entries(namespace_id,configuration_key)
  where organization_id is null and environment_id is null and status<>'archived';

create table if not exists public.configuration_entry_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  configuration_entry_id uuid not null references public.configuration_entries(id) on delete cascade,
  version integer not null,
  value_type text not null,
  boolean_value boolean,
  string_value text,
  number_value numeric,
  json_value jsonb,
  secret_reference text,
  effective_from timestamptz,
  effective_until timestamptz,
  checksum text,
  change_type text not null default 'update'
    check (change_type in ('create','update','activate','deactivate','rollback','archive')),
  change_reason text,
  changed_by uuid references auth.users(id) on delete set null,
  changed_at timestamptz not null default now(),
  metadata jsonb not null default '{}',
  unique(configuration_entry_id,version)
);

-- ============================================================
-- 7. CHANGE CONTROL, SDK, CACHE AND SNAPSHOTS
-- ============================================================

create table if not exists public.feature_configuration_change_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  environment_id uuid references public.feature_environments(id) on delete cascade,
  request_code text not null unique,
  change_scope text not null
    check (change_scope in ('feature_flag','feature_rule','feature_override','kill_switch','configuration_entry','configuration_namespace','bulk')),
  target_id uuid,
  target_key text,
  change_type text not null
    check (change_type in ('create','update','enable','disable','activate','release','rollback','archive','bulk_update')),
  proposed_change jsonb not null default '{}',
  current_snapshot jsonb not null default '{}',
  risk_level text not null default 'low' check (risk_level in ('low','medium','high','critical')),
  status text not null default 'draft'
    check (status in ('draft','submitted','under_review','approved','rejected','scheduled','applying','applied','failed','cancelled','expired')),
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  rejected_by uuid references auth.users(id) on delete set null,
  rejected_at timestamptz,
  rejection_reason text,
  scheduled_at timestamptz,
  applied_at timestamptz,
  failure_code text,
  failure_message text,
  failure_data jsonb not null default '{}',
  idempotency_key text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_configuration_change_requests_idem_uidx
  on public.feature_configuration_change_requests(idempotency_key)
  where idempotency_key is not null;

create table if not exists public.feature_sdk_clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.feature_environments(id) on delete cascade,
  client_code text not null,
  client_name text not null,
  client_type text not null default 'server'
    check (client_type in ('server','web','mobile','edge','worker','integration','custom')),
  key_prefix text not null,
  key_hash text not null,
  allowed_origins text[] not null default '{}',
  allowed_ip_ranges text[] not null default '{}',
  rate_limit_per_minute integer not null default 600 check (rate_limit_per_minute>0),
  last_used_at timestamptz,
  last_rotated_at timestamptz,
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','inactive','revoked','expired','archived')),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,environment_id,client_code)
);

create unique index if not exists feature_sdk_clients_hash_uidx
  on public.feature_sdk_clients(key_hash)
  where status='active';

create table if not exists public.feature_configuration_cache_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.feature_environments(id) on delete cascade,
  cache_key text not null default 'default',
  version bigint not null default 1,
  feature_version bigint not null default 1,
  configuration_version bigint not null default 1,
  last_invalidated_at timestamptz not null default now(),
  invalidation_reason text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,environment_id,cache_key)
);

create unique index if not exists feature_configuration_cache_versions_global_uidx
  on public.feature_configuration_cache_versions(environment_id,cache_key)
  where organization_id is null;

create table if not exists public.feature_configuration_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  environment_id uuid not null references public.feature_environments(id) on delete cascade,
  snapshot_code text not null,
  snapshot_type text not null default 'full' check (snapshot_type in ('features','configuration','full')),
  cache_version bigint not null,
  payload jsonb not null default '{}',
  checksum text not null,
  generated_at timestamptz not null default now(),
  expires_at timestamptz,
  status text not null default 'active' check (status in ('active','expired','archived')),
  metadata jsonb not null default '{}',
  generated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(organization_id,environment_id,snapshot_code)
);

-- ============================================================
-- 8. EXPOSURES, OUTBOX AND LOGS
-- ============================================================

create table if not exists public.feature_flag_exposures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  environment_id uuid references public.feature_environments(id) on delete set null,
  feature_flag_id uuid references public.feature_flags(id) on delete set null,
  feature_key text not null,
  subject_type text not null default 'anonymous',
  subject_key text,
  user_id uuid references auth.users(id) on delete set null,
  session_id text,
  device_id text,
  enabled boolean not null,
  variant_key text,
  variant_value jsonb,
  evaluation_reason text not null,
  matched_rule_id uuid references public.feature_flag_rules(id) on delete set null,
  matched_override_id uuid references public.feature_flag_overrides(id) on delete set null,
  matched_segment_ids uuid[] not null default '{}',
  rollout_bucket numeric(8,4),
  context_hash text,
  evaluation_context jsonb not null default '{}',
  correlation_id text,
  trace_id text,
  evaluated_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists feature_flag_exposures_analytics_idx
  on public.feature_flag_exposures(organization_id,environment_id,feature_key,evaluated_at desc);

create table if not exists public.feature_configuration_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  environment_id uuid references public.feature_environments(id) on delete cascade,
  event_name text not null,
  source_type text,
  source_id uuid,
  destination text not null default 'internal'
    check (destination in ('internal','service_worker','automation_engine','enterprise_workflow','communication_engine','notification_engine','integration_api','analytics','audit','observability','mobile','web','edge','n8n','webhook','external')),
  status text not null default 'pending'
    check (status in ('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
  priority integer not null default 100,
  payload jsonb not null default '{}',
  available_at timestamptz not null default now(),
  delivery_attempts integer not null default 0,
  maximum_attempts integer not null default 10,
  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,
  delivered_at timestamptz,
  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',
  idempotency_key text,
  correlation_id text,
  trace_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists feature_configuration_event_outbox_idem_uidx
  on public.feature_configuration_event_outbox(idempotency_key)
  where idempotency_key is not null;

create index if not exists feature_configuration_event_outbox_worker_idx
  on public.feature_configuration_event_outbox(status,available_at,priority,created_at)
  where status in ('pending','failed');

create table if not exists public.feature_configuration_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  environment_id uuid references public.feature_environments(id) on delete set null,
  log_level text not null default 'info' check (log_level in ('debug','info','warning','error','critical')),
  event_name text,
  message text,
  source_type text,
  source_id uuid,
  actor_user_id uuid references auth.users(id) on delete set null,
  error_code text,
  error_message text,
  log_data jsonb not null default '{}',
  correlation_id text,
  trace_id text,
  created_at timestamptz not null default now()
);

create index if not exists feature_configuration_logs_org_time_idx
  on public.feature_configuration_logs(organization_id,created_at desc);

-- ============================================================
-- 9. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare t text;
begin
  foreach t in array array[
    'feature_environments','feature_flags','feature_flag_variants',
    'feature_flag_environment_state','feature_segments','feature_segment_members',
    'feature_flag_rules','feature_flag_overrides','feature_kill_switches',
    'configuration_namespaces','configuration_entries',
    'feature_configuration_change_requests','feature_sdk_clients',
    'feature_configuration_cache_versions','feature_configuration_event_outbox'
  ] loop
    execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
    execute format(
      'create trigger %I_set_updated_at before update on public.%I '
      'for each row execute function public.set_updated_at()',t,t
    );
  end loop;
end;
$$;

-- ============================================================
-- 10. CONFIGURATION VALUE AND HISTORY TRIGGERS
-- ============================================================

create or replace function public.validate_configuration_entry_value()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare value_count integer;
begin
  value_count :=
      case when new.boolean_value is not null then 1 else 0 end
    + case when new.string_value is not null then 1 else 0 end
    + case when new.number_value is not null then 1 else 0 end
    + case when new.json_value is not null then 1 else 0 end
    + case when new.secret_reference is not null then 1 else 0 end;

  if new.value_type='boolean' and new.boolean_value is null then
    raise exception 'boolean_value is required';
  elsif new.value_type='string' and new.string_value is null then
    raise exception 'string_value is required';
  elsif new.value_type='number' and new.number_value is null then
    raise exception 'number_value is required';
  elsif new.value_type='json' and new.json_value is null then
    raise exception 'json_value is required';
  elsif new.value_type='secret_reference' and coalesce(length(trim(new.secret_reference)),0)<3 then
    raise exception 'secret_reference is required';
  end if;

  if new.is_sensitive and new.value_type<>'secret_reference' then
    raise exception 'Sensitive configuration must use secret_reference';
  end if;

  if value_count>1 then
    raise exception 'Only one typed configuration value may be populated';
  end if;

  new.checksum := encode(extensions.digest(concat_ws('|',new.value_type,
    coalesce(new.boolean_value::text,''),coalesce(new.string_value,''),
    coalesce(new.number_value::text,''),coalesce(new.json_value::text,''),
    coalesce(new.secret_reference,'')),'sha256'),'hex');

  return new;
end;
$$;

create or replace function public.prepare_configuration_entry_version()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='UPDATE' and (
       old.value_type is distinct from new.value_type
    or old.boolean_value is distinct from new.boolean_value
    or old.string_value is distinct from new.string_value
    or old.number_value is distinct from new.number_value
    or old.json_value is distinct from new.json_value
    or old.secret_reference is distinct from new.secret_reference
    or old.status is distinct from new.status
    or old.effective_from is distinct from new.effective_from
    or old.effective_until is distinct from new.effective_until
  ) then
    new.version := old.version+1;
  end if;
  return new;
end;
$$;

create or replace function public.record_configuration_entry_version()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare change_kind text;
begin
  if tg_op='UPDATE' and new.version is not distinct from old.version then
    return new;
  end if;

  change_kind := case
    when tg_op='INSERT' then 'create'
    when tg_op='UPDATE' and old.status<>'active' and new.status='active' then 'activate'
    when tg_op='UPDATE' and old.status='active' and new.status<>'active' then 'deactivate'
    else 'update'
  end;

  insert into public.configuration_entry_versions(
    organization_id,configuration_entry_id,version,value_type,
    boolean_value,string_value,number_value,json_value,secret_reference,
    effective_from,effective_until,checksum,change_type,change_reason,
    changed_by,metadata
  ) values (
    new.organization_id,new.id,new.version,new.value_type,
    new.boolean_value,new.string_value,new.number_value,new.json_value,new.secret_reference,
    new.effective_from,new.effective_until,new.checksum,change_kind,
    coalesce(new.metadata->>'change_reason',case when tg_op='INSERT' then 'Initial value' else 'Configuration updated' end),
    coalesce(new.updated_by,new.created_by),new.metadata
  ) on conflict(configuration_entry_id,version) do nothing;

  return new;
end;
$$;

drop trigger if exists configuration_entries_prepare_version on public.configuration_entries;
create trigger configuration_entries_prepare_version
before insert or update on public.configuration_entries
for each row execute function public.prepare_configuration_entry_version();

drop trigger if exists configuration_entries_validate on public.configuration_entries;
create trigger configuration_entries_validate
before insert or update on public.configuration_entries
for each row execute function public.validate_configuration_entry_value();

drop trigger if exists configuration_entries_history on public.configuration_entries;
create trigger configuration_entries_history
after insert or update on public.configuration_entries
for each row execute function public.record_configuration_entry_version();

-- ============================================================
-- 11. HELPERS
-- ============================================================

create or replace function public.feature_safe_uuid(p_value text)
returns uuid
language plpgsql
immutable
set search_path=''
as $$
begin
  if p_value is null or p_value='' then return null; end if;
  return p_value::uuid;
exception when others then return null;
end;
$$;

create or replace function public.feature_context_value(p_context jsonb,p_path text)
returns jsonb
language sql
immutable
set search_path=''
as $$
  select case when p_context is null or p_path is null then null
              else p_context #> string_to_array(p_path,'.') end;
$$;

create or replace function public.feature_condition_matches(p_context jsonb,p_condition jsonb)
returns boolean
language plpgsql
immutable
set search_path=''
as $$
declare
  attr text := p_condition->>'attribute';
  op text := lower(coalesce(p_condition->>'operator','eq'));
  expected jsonb := p_condition->'value';
  actual jsonb;
  atext text;
  etext text;
begin
  actual := public.feature_context_value(coalesce(p_context,'{}'::jsonb),attr);
  if op='exists' then return actual is not null; end if;
  if op='not_exists' then return actual is null; end if;
  if actual is null then return false; end if;

  atext := trim(both '"' from actual::text);
  etext := trim(both '"' from coalesce(expected,'null'::jsonb)::text);

  if op in ('eq','equals') then return actual=expected;
  elsif op in ('neq','not_equals') then return actual<>expected;
  elsif op='in' then
    return exists(select 1 from jsonb_array_elements(coalesce(expected,'[]'::jsonb)) x where x=actual);
  elsif op='not_in' then
    return not exists(select 1 from jsonb_array_elements(coalesce(expected,'[]'::jsonb)) x where x=actual);
  elsif op='contains' then
    if jsonb_typeof(actual)='array' then return actual @> jsonb_build_array(expected); end if;
    return position(lower(etext) in lower(atext))>0;
  elsif op='not_contains' then
    if jsonb_typeof(actual)='array' then return not(actual @> jsonb_build_array(expected)); end if;
    return position(lower(etext) in lower(atext))=0;
  elsif op='starts_with' then return lower(atext) like lower(etext)||'%';
  elsif op='ends_with' then return lower(atext) like '%'||lower(etext);
  elsif op='regex' then return atext ~ etext;
  elsif op in ('gt','greater_than') then return atext::numeric>etext::numeric;
  elsif op in ('gte','greater_than_or_equal') then return atext::numeric>=etext::numeric;
  elsif op in ('lt','less_than') then return atext::numeric<etext::numeric;
  elsif op in ('lte','less_than_or_equal') then return atext::numeric<=etext::numeric;
  elsif op='before' then return atext::timestamptz<etext::timestamptz;
  elsif op='after' then return atext::timestamptz>etext::timestamptz;
  end if;
  return false;
exception when others then return false;
end;
$$;

create or replace function public.feature_conditions_match(
  p_context jsonb,p_conditions jsonb,p_match_mode text default 'all'
)
returns boolean
language plpgsql
immutable
set search_path=''
as $$
declare total_count integer; matched_count integer;
begin
  if p_conditions is null or jsonb_typeof(p_conditions)<>'array' or jsonb_array_length(p_conditions)=0 then
    return true;
  end if;
  select count(*),count(*) filter(where public.feature_condition_matches(p_context,c))
  into total_count,matched_count from jsonb_array_elements(p_conditions)c;
  if lower(coalesce(p_match_mode,'all'))='any' then return matched_count>0; end if;
  return matched_count=total_count;
end;
$$;

create or replace function public.feature_rollout_bucket(
  p_feature_key text,p_environment_code text,p_stickiness_value text
)
returns numeric
language sql
immutable
set search_path=''
as $$
  select round(((('x'||substr(encode(extensions.digest(
    coalesce(p_feature_key,'')||':'||coalesce(p_environment_code,'')||':'||coalesce(p_stickiness_value,'anonymous'),
    'sha256'),'hex'),1,15))::bit(60)::bigint % 1000000)::numeric/10000),4);
$$;

create or replace function public.resolve_feature_environment(
  p_organization_id uuid,p_environment_code text default null
)
returns public.feature_environments
language plpgsql
stable
security definer
set search_path=''
as $$
declare r public.feature_environments;
begin
  select e.* into r from public.feature_environments e
  where e.status='active' and e.evaluation_enabled=true
    and (p_environment_code is null or e.environment_code=p_environment_code)
    and (e.organization_id=p_organization_id or e.organization_id is null)
  order by case when e.organization_id=p_organization_id then 0 else 1 end,
           case when e.is_default then 0 else 1 end,
           e.created_at
  limit 1;
  if not found then raise exception 'Feature environment not found'; end if;
  return r;
end;
$$;

create or replace function public.resolve_feature_flag(p_organization_id uuid,p_feature_key text)
returns public.feature_flags
language plpgsql
stable
security definer
set search_path=''
as $$
declare r public.feature_flags;
begin
  select f.* into r from public.feature_flags f
  where f.feature_key=p_feature_key and f.status='active'
    and (f.organization_id=p_organization_id or f.organization_id is null)
  order by case when f.organization_id=p_organization_id then 0 else 1 end
  limit 1;
  if not found then raise exception 'Feature flag not found: %',p_feature_key; end if;
  return r;
end;
$$;

create or replace function public.feature_variant_payload(p_feature_flag_id uuid,p_variant_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v public.feature_flag_variants;
begin
  select * into v from public.feature_flag_variants
  where feature_flag_id=p_feature_flag_id and variant_key=p_variant_key and status='active'
  limit 1;
  if not found then return jsonb_build_object('variant_key',p_variant_key,'value',null); end if;
  return jsonb_build_object(
    'variant_id',v.id,'variant_key',v.variant_key,'variant_name',v.variant_name,
    'enabled',v.is_enabled_variant,
    'value',case when v.boolean_value is not null then to_jsonb(v.boolean_value)
                 when v.string_value is not null then to_jsonb(v.string_value)
                 when v.number_value is not null then to_jsonb(v.number_value)
                 else v.json_value end
  );
end;
$$;

create or replace function public.feature_segment_matches(
  p_segment_id uuid,p_organization_id uuid,p_context jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  s public.feature_segments;
  excluded boolean;
  included boolean;
begin
  select * into s from public.feature_segments
  where id=p_segment_id and status='active'
    and (organization_id=p_organization_id or organization_id is null);
  if not found then return false; end if;

  select exists(
    select 1 from public.feature_segment_members m
    where m.segment_id=s.id and m.status='active' and m.inclusion_type='exclude'
      and (m.starts_at is null or m.starts_at<=now())
      and (m.expires_at is null or m.expires_at>now())
      and ((m.subject_type='user' and m.subject_key=p_context->>'user_id')
        or (m.subject_type='organization' and m.subject_key=coalesce(p_context->>'organization_id',p_organization_id::text))
        or (m.subject_type='role' and m.subject_key=p_context->>'role')
        or (m.subject_type='plan' and m.subject_key=p_context->>'plan_code')
        or (m.subject_type='email' and lower(m.subject_key)=lower(p_context->>'email'))
        or (m.subject_type='phone' and m.subject_key=p_context->>'phone')
        or (m.subject_type='device' and m.subject_key=p_context->>'device_id'))
  ) into excluded;
  if excluded then return false; end if;

  select exists(
    select 1 from public.feature_segment_members m
    where m.segment_id=s.id and m.status='active' and m.inclusion_type='include'
      and (m.starts_at is null or m.starts_at<=now())
      and (m.expires_at is null or m.expires_at>now())
      and ((m.subject_type='user' and m.subject_key=p_context->>'user_id')
        or (m.subject_type='organization' and m.subject_key=coalesce(p_context->>'organization_id',p_organization_id::text))
        or (m.subject_type='role' and m.subject_key=p_context->>'role')
        or (m.subject_type='plan' and m.subject_key=p_context->>'plan_code')
        or (m.subject_type='email' and lower(m.subject_key)=lower(p_context->>'email'))
        or (m.subject_type='phone' and m.subject_key=p_context->>'phone')
        or (m.subject_type='device' and m.subject_key=p_context->>'device_id'))
  ) into included;

  return included or public.feature_conditions_match(p_context,s.conditions,s.match_mode);
end;
$$;

create or replace function public.feature_rule_segments_match(
  p_segment_ids uuid[],p_organization_id uuid,p_context jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
declare sid uuid;
begin
  if p_segment_ids is null or cardinality(p_segment_ids)=0 then return true; end if;
  foreach sid in array p_segment_ids loop
    if not public.feature_segment_matches(sid,p_organization_id,p_context) then return false; end if;
  end loop;
  return true;
end;
$$;

create or replace function public.pick_feature_variant(
  p_feature_flag_id uuid,p_bucket numeric,p_rollout_variants jsonb default '[]'::jsonb
)
returns text
language plpgsql
stable
security definer
set search_path=''
as $$
declare running numeric:=0; item jsonb; k text; w numeric;
begin
  if p_rollout_variants is not null and jsonb_typeof(p_rollout_variants)='array' and jsonb_array_length(p_rollout_variants)>0 then
    for item in select value from jsonb_array_elements(p_rollout_variants) loop
      k:=item->>'variant_key'; w:=coalesce((item->>'weight')::numeric,0); running:=running+w;
      if p_bucket<running then return k; end if;
    end loop;
  end if;
  running:=0;
  for k,w in select variant_key,weight from public.feature_flag_variants
             where feature_flag_id=p_feature_flag_id and status='active' and weight>0
             order by sequence_number,created_at loop
    running:=running+w;
    if p_bucket<running then return k; end if;
  end loop;
  return null;
end;
$$;

-- ============================================================
-- 12. EVENT OUTBOX FUNCTIONS
-- ============================================================

create or replace function public.publish_feature_configuration_event(
  p_organization_id uuid,p_environment_id uuid,p_event_name text,
  p_payload jsonb default '{}'::jsonb,p_destination text default 'internal',
  p_source_type text default null,p_source_id uuid default null,
  p_priority integer default 100,p_idempotency_key text default null,
  p_correlation_id text default null,p_trace_id text default null,
  p_available_at timestamptz default now()
)
returns public.feature_configuration_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare e public.feature_configuration_event_outbox;
begin
  if p_idempotency_key is not null then
    select * into e from public.feature_configuration_event_outbox
    where idempotency_key=p_idempotency_key limit 1;
    if found then return e; end if;
  end if;
  insert into public.feature_configuration_event_outbox(
    organization_id,environment_id,event_name,source_type,source_id,destination,
    status,priority,payload,available_at,idempotency_key,correlation_id,trace_id
  ) values (
    p_organization_id,p_environment_id,p_event_name,p_source_type,p_source_id,p_destination,
    'pending',p_priority,coalesce(p_payload,'{}'::jsonb),coalesce(p_available_at,now()),
    p_idempotency_key,p_correlation_id,p_trace_id
  ) returning * into e;
  return e;
end;
$$;

create or replace function public.claim_feature_configuration_event(
  p_worker_id text,p_destination text default null,p_lock_seconds integer default 300
)
returns public.feature_configuration_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare e public.feature_configuration_event_outbox;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may claim events'; end if;

  update public.feature_configuration_event_outbox
  set status='failed',available_at=now(),claimed_at=null,claimed_by=null,
      lock_token=null,lock_expires_at=null,
      last_error_code=coalesce(last_error_code,'LOCK_EXPIRED'),
      last_error_message=coalesce(last_error_message,'Event lock expired'),updated_at=now()
  where status in ('claimed','processing') and lock_expires_at is not null and lock_expires_at<=now();

  select * into e from public.feature_configuration_event_outbox
  where status in ('pending','failed') and available_at<=now()
    and delivery_attempts<maximum_attempts
    and (p_destination is null or destination=p_destination)
  order by priority,created_at for update skip locked limit 1;
  if not found then return null; end if;

  update public.feature_configuration_event_outbox
  set status='claimed',delivery_attempts=delivery_attempts+1,claimed_at=now(),
      claimed_by=p_worker_id,lock_token=gen_random_uuid()::text,
      lock_expires_at=now()+make_interval(secs=>greatest(p_lock_seconds,1)),updated_at=now()
  where id=e.id returning * into e;
  return e;
end;
$$;

create or replace function public.complete_feature_configuration_event(
  p_event_id uuid,p_lock_token text,p_result_data jsonb default '{}'::jsonb
)
returns public.feature_configuration_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare e public.feature_configuration_event_outbox;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may complete events'; end if;
  select * into e from public.feature_configuration_event_outbox where id=p_event_id for update;
  if not found then raise exception 'Event not found'; end if;
  if e.lock_token is distinct from p_lock_token then raise exception 'Invalid lock token'; end if;
  update public.feature_configuration_event_outbox
  set status='delivered',delivered_at=now(),payload=payload||jsonb_build_object('delivery_result',coalesce(p_result_data,'{}'::jsonb)),
      claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
      last_error_code=null,last_error_message=null,last_error_data='{}',updated_at=now()
  where id=e.id returning * into e;
  return e;
end;
$$;

create or replace function public.fail_feature_configuration_event(
  p_event_id uuid,p_lock_token text,p_error_code text,p_error_message text,
  p_error_data jsonb default '{}'::jsonb
)
returns public.feature_configuration_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare e public.feature_configuration_event_outbox; next_status text; delay_seconds integer;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may fail events'; end if;
  select * into e from public.feature_configuration_event_outbox where id=p_event_id for update;
  if not found then raise exception 'Event not found'; end if;
  if e.lock_token is distinct from p_lock_token then raise exception 'Invalid lock token'; end if;
  next_status:=case when e.delivery_attempts>=e.maximum_attempts then 'dead_lettered' else 'failed' end;
  delay_seconds:=least(3600,greatest(30,power(2,greatest(e.delivery_attempts,1))::integer*30));
  update public.feature_configuration_event_outbox
  set status=next_status,available_at=case when next_status='failed' then now()+make_interval(secs=>delay_seconds) else available_at end,
      last_error_code=p_error_code,last_error_message=p_error_message,last_error_data=coalesce(p_error_data,'{}'::jsonb),
      claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
  where id=e.id returning * into e;
  insert into public.feature_configuration_logs(
    organization_id,environment_id,log_level,event_name,message,source_type,source_id,
    error_code,error_message,log_data,correlation_id,trace_id
  ) values (
    e.organization_id,e.environment_id,case when next_status='dead_lettered' then 'critical' else 'error' end,
    'feature_configuration.event.'||next_status,'Feature configuration event delivery failed',
    'feature_configuration_event_outbox',e.id,p_error_code,p_error_message,
    coalesce(p_error_data,'{}'::jsonb),e.correlation_id,e.trace_id
  );
  return e;
end;
$$;

-- ============================================================
-- 13. CACHE INVALIDATION
-- ============================================================

create or replace function public.invalidate_feature_configuration_cache(
  p_organization_id uuid,p_environment_id uuid,p_scope text default 'full',
  p_reason text default null,p_payload jsonb default '{}'::jsonb
)
returns public.feature_configuration_cache_versions
language plpgsql
security definer
set search_path=''
as $$
declare c public.feature_configuration_cache_versions;
begin
  select * into c
  from public.feature_configuration_cache_versions cv
  where cv.organization_id is not distinct from p_organization_id
    and cv.environment_id=p_environment_id and cv.cache_key='default'
  limit 1 for update;

  if found then
    update public.feature_configuration_cache_versions
    set version=version+1,
        feature_version=case when p_scope in ('feature','full') then feature_version+1 else feature_version end,
        configuration_version=case when p_scope in ('configuration','full') then configuration_version+1 else configuration_version end,
        last_invalidated_at=now(),invalidation_reason=p_reason,
        metadata=metadata||coalesce(p_payload,'{}'::jsonb),updated_at=now()
    where id=c.id returning * into c;
  else
    insert into public.feature_configuration_cache_versions(
      organization_id,environment_id,cache_key,version,feature_version,
      configuration_version,last_invalidated_at,invalidation_reason,metadata
    ) values (
      p_organization_id,p_environment_id,'default',2,
      case when p_scope in ('feature','full') then 2 else 1 end,
      case when p_scope in ('configuration','full') then 2 else 1 end,
      now(),p_reason,coalesce(p_payload,'{}'::jsonb)
    ) returning * into c;
  end if;

  perform public.publish_feature_configuration_event(
    p_organization_id,p_environment_id,'feature_configuration.cache.invalidated',
    jsonb_build_object('scope',p_scope,'reason',p_reason,'cache_version',c.version,
      'feature_version',c.feature_version,'configuration_version',c.configuration_version,'payload',p_payload),
    'integration_api','feature_configuration_cache_version',c.id,20,
    'feature-config-cache:'||coalesce(p_organization_id::text,'global')||':'||p_environment_id::text||':'||c.version::text
  );
  return c;
end;
$$;

-- ============================================================
-- 14. FEATURE EVALUATION
-- ============================================================

create or replace function public.evaluate_feature_flag(
  p_organization_id uuid,p_feature_key text,p_environment_code text default 'production',
  p_context jsonb default '{}'::jsonb,p_log_exposure boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  f public.feature_flags;
  e public.feature_environments;
  s public.feature_flag_environment_state;
  k public.feature_kill_switches;
  o public.feature_flag_overrides;
  r public.feature_flag_rules;
  ctx jsonb;
  candidates jsonb;
  selected_enabled boolean;
  selected_variant text;
  reason text;
  variant jsonb;
  matched_rule uuid;
  matched_override uuid;
  matched_segments uuid[]:='{}';
  stickiness_key text;
  stickiness_value text;
  bucket numeric;
  exposure uuid;
  now_value timestamptz:=now();
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.view') then
    raise exception 'Permission denied';
  end if;

  ctx:=coalesce(p_context,'{}'::jsonb)||jsonb_build_object(
    'organization_id',coalesce(p_context->>'organization_id',p_organization_id::text)
  );
  e:=public.resolve_feature_environment(p_organization_id,p_environment_code);
  f:=public.resolve_feature_flag(p_organization_id,p_feature_key);

  if not f.evaluation_enabled or f.lifecycle_stage='retired' then
    return jsonb_build_object('feature_key',f.feature_key,'enabled',f.default_enabled,
      'variant_key',f.default_variant_key,'variant',public.feature_variant_payload(f.id,f.default_variant_key),
      'reason','flag_disabled','environment',e.environment_code);
  end if;

  select ks.* into k from public.feature_kill_switches ks
  where ks.active=true and ks.status='active' and (ks.expires_at is null or ks.expires_at>now_value)
    and (ks.organization_id=p_organization_id or ks.organization_id is null)
    and (ks.environment_id is null or ks.environment_id=e.id)
    and ((ks.scope_type='feature' and ks.feature_flag_id=f.id)
      or (ks.scope_type='module' and ks.module_code=f.module_code)
      or (ks.scope_type='organization' and ks.organization_id=p_organization_id)
      or (ks.scope_type='environment' and ks.environment_id=e.id)
      or ks.scope_type='platform')
  order by case ks.severity when 'critical' then 0 when 'high' then 1 when 'warning' then 2 else 3 end,
           ks.activated_at desc nulls last limit 1;

  if found then
    selected_enabled:=coalesce(k.force_enabled,false);
    selected_variant:=coalesce(k.force_variant_key,case when selected_enabled then 'on' else 'off' end);
    reason:='kill_switch';
  else
    select st.* into s from public.feature_flag_environment_state st
    where st.feature_flag_id=f.id and st.environment_id=e.id and st.status='active'
      and (st.organization_id=p_organization_id or st.organization_id is null)
    order by case when st.organization_id=p_organization_id then 0 else 1 end
    limit 1;

    if found and (s.emergency_disabled or (s.scheduled_disable_at is not null and s.scheduled_disable_at<=now_value)) then
      selected_enabled:=false;
      selected_variant:=coalesce(s.default_variant_key,'off');
      reason:=case when s.emergency_disabled then 'environment_emergency_disabled' else 'scheduled_disable_reached' end;
    elsif found and s.scheduled_enable_at is not null and s.scheduled_enable_at>now_value then
      selected_enabled:=false; selected_variant:='off'; reason:='scheduled_enable_pending';
    else
      candidates:=jsonb_build_array(
        jsonb_build_object('type','user','key',ctx->>'user_id'),
        jsonb_build_object('type','organization','key',p_organization_id::text),
        jsonb_build_object('type','role','key',ctx->>'role'),
        jsonb_build_object('type','plan','key',ctx->>'plan_code'),
        jsonb_build_object('type','email','key',lower(ctx->>'email')),
        jsonb_build_object('type','phone','key',ctx->>'phone'),
        jsonb_build_object('type','device','key',ctx->>'device_id'),
        jsonb_build_object('type','session','key',ctx->>'session_id')
      );

      select ov.* into o from public.feature_flag_overrides ov
      where ov.feature_flag_id=f.id and ov.environment_id=e.id and ov.status='active'
        and (ov.organization_id=p_organization_id or ov.organization_id is null)
        and (ov.starts_at is null or ov.starts_at<=now_value)
        and (ov.expires_at is null or ov.expires_at>now_value)
        and exists(select 1 from jsonb_array_elements(candidates)c
                   where c->>'key' is not null and c->>'key'<>''
                     and c->>'type'=ov.target_type and c->>'key'=ov.target_key)
      order by case when ov.organization_id=p_organization_id then 0 else 1 end,
               ov.priority,ov.created_at desc limit 1;

      if found then
        selected_enabled:=coalesce(o.enabled,true);
        selected_variant:=coalesce(o.variant_key,case when selected_enabled then 'on' else 'off' end);
        reason:='target_override'; matched_override:=o.id;
      else
        for r in select rr.* from public.feature_flag_rules rr
                 where rr.feature_flag_id=f.id and rr.environment_id=e.id and rr.status='active'
                   and (rr.organization_id=p_organization_id or rr.organization_id is null)
                   and (rr.starts_at is null or rr.starts_at<=now_value)
                   and (rr.expires_at is null or rr.expires_at>now_value)
                 order by case when rr.organization_id=p_organization_id then 0 else 1 end,
                          rr.priority,rr.created_at loop
          if public.feature_conditions_match(ctx,r.conditions,r.match_mode)
             and public.feature_rule_segments_match(r.segment_ids,p_organization_id,ctx) then
            matched_rule:=r.id; matched_segments:=r.segment_ids; reason:='targeting_rule';
            if r.rollout_percentage is not null then
              stickiness_key:=coalesce(r.stickiness_key,s.rollout_stickiness_key,'user_id');
              stickiness_value:=coalesce(ctx->>stickiness_key,ctx->>'user_id',ctx->>'device_id',ctx->>'session_id',p_organization_id::text,'anonymous');
              bucket:=public.feature_rollout_bucket(f.feature_key,e.environment_code,stickiness_value);
              if bucket<r.rollout_percentage then
                selected_enabled:=coalesce(r.serve_enabled,true);
                selected_variant:=coalesce(r.serve_variant_key,
                  public.pick_feature_variant(f.id,public.feature_rollout_bucket(f.feature_key||':'||r.rule_key,e.environment_code,stickiness_value),r.rollout_variants),
                  case when coalesce(r.serve_enabled,true) then 'on' else 'off' end);
              else
                selected_enabled:=false; selected_variant:='off'; reason:='targeting_rule_rollout_excluded';
              end if;
            else
              selected_enabled:=coalesce(r.serve_enabled,true);
              selected_variant:=coalesce(r.serve_variant_key,case when coalesce(r.serve_enabled,true) then 'on' else 'off' end);
            end if;
            if r.stop_evaluation then exit; end if;
          end if;
        end loop;
      end if;

      if selected_variant is null then
        selected_enabled:=coalesce(s.enabled,f.default_enabled);
        selected_variant:=coalesce(s.default_variant_key,f.default_variant_key,case when selected_enabled then 'on' else 'off' end);
        if selected_enabled and coalesce(s.rollout_percentage,0)>0 and s.rollout_percentage<100 then
          stickiness_key:=coalesce(s.rollout_stickiness_key,'user_id');
          stickiness_value:=coalesce(ctx->>stickiness_key,ctx->>'user_id',ctx->>'device_id',ctx->>'session_id',p_organization_id::text,'anonymous');
          bucket:=public.feature_rollout_bucket(f.feature_key,e.environment_code,stickiness_value);
          if bucket>=s.rollout_percentage then
            selected_enabled:=false; selected_variant:='off'; reason:='environment_rollout_excluded';
          else
            selected_variant:=coalesce(public.pick_feature_variant(f.id,
              public.feature_rollout_bucket(f.feature_key||':variants',e.environment_code,stickiness_value)),selected_variant);
            reason:='environment_rollout_included';
          end if;
        else
          reason:='environment_default';
        end if;
      end if;
    end if;
  end if;

  variant:=public.feature_variant_payload(f.id,selected_variant);
  if variant?'enabled' then selected_enabled:=coalesce((variant->>'enabled')::boolean,selected_enabled); end if;

  if p_log_exposure and f.exposure_logging_enabled then
    insert into public.feature_flag_exposures(
      organization_id,environment_id,feature_flag_id,feature_key,subject_type,subject_key,
      user_id,session_id,device_id,enabled,variant_key,variant_value,evaluation_reason,
      matched_rule_id,matched_override_id,matched_segment_ids,rollout_bucket,context_hash,
      evaluation_context,correlation_id,trace_id
    ) values (
      p_organization_id,e.id,f.id,f.feature_key,coalesce(ctx->>'subject_type','anonymous'),ctx->>'subject_key',
      public.feature_safe_uuid(ctx->>'user_id'),ctx->>'session_id',ctx->>'device_id',selected_enabled,
      selected_variant,variant->'value',reason,matched_rule,matched_override,matched_segments,bucket,
      encode(extensions.digest((ctx-'secret'-'token'-'password')::text,'sha256'),'hex'),ctx-'secret'-'token'-'password',
      ctx->>'correlation_id',ctx->>'trace_id'
    ) returning id into exposure;
  end if;

  return jsonb_build_object(
    'feature_key',f.feature_key,'feature_flag_id',f.id,'enabled',selected_enabled,
    'variant_key',selected_variant,'variant',variant,'reason',reason,
    'matched_rule_id',matched_rule,'matched_override_id',matched_override,
    'matched_segment_ids',matched_segments,'rollout_bucket',bucket,
    'environment',e.environment_code,'environment_id',e.id,'exposure_id',exposure,'evaluated_at',now_value
  );
end;
$$;

create or replace function public.evaluate_feature_flags(
  p_organization_id uuid,p_feature_keys text[],p_environment_code text default 'production',
  p_context jsonb default '{}'::jsonb,p_log_exposure boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare k text; result jsonb:='{}'; one jsonb;
begin
  foreach k in array p_feature_keys loop
    begin
      one:=public.evaluate_feature_flag(p_organization_id,k,p_environment_code,p_context,p_log_exposure);
    exception when others then
      one:=jsonb_build_object('feature_key',k,'enabled',false,'variant_key','off','reason','evaluation_error','error',sqlerrm);
    end;
    result:=result||jsonb_build_object(k,one);
  end loop;
  return result;
end;
$$;

-- ============================================================
-- 15. CONFIGURATION FUNCTIONS
-- ============================================================

create or replace function public.resolve_configuration_value(
  p_organization_id uuid,p_namespace_key text,p_configuration_key text,
  p_environment_code text default 'production',p_include_secret_reference boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare env public.feature_environments; ns public.configuration_namespaces; ent public.configuration_entries; val jsonb;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.view') then
    raise exception 'Permission denied';
  end if;
  env:=public.resolve_feature_environment(p_organization_id,p_environment_code);
  select * into ns from public.configuration_namespaces n
  where n.namespace_key=p_namespace_key and n.status='active'
    and (n.organization_id=p_organization_id or n.organization_id is null)
  order by case when n.organization_id=p_organization_id then 0 else 1 end limit 1;
  if not found then return jsonb_build_object('found',false,'reason','namespace_not_found'); end if;

  select * into ent from public.configuration_entries x
  where x.namespace_id=ns.id and x.configuration_key=p_configuration_key and x.status='active'
    and x.effective_from<=now() and (x.effective_until is null or x.effective_until>now())
    and (x.organization_id=p_organization_id or x.organization_id is null)
    and (x.environment_id=env.id or x.environment_id is null)
  order by case when x.organization_id=p_organization_id then 0 else 1 end,
           case when x.environment_id=env.id then 0 else 1 end,x.version desc limit 1;
  if not found then return jsonb_build_object('found',false,'reason','configuration_not_found'); end if;

  val:=case when ent.value_type='boolean' then to_jsonb(ent.boolean_value)
            when ent.value_type='string' then to_jsonb(ent.string_value)
            when ent.value_type='number' then to_jsonb(ent.number_value)
            when ent.value_type='json' then ent.json_value
            when ent.value_type='secret_reference' and p_include_secret_reference and auth.role()='service_role' then to_jsonb(ent.secret_reference)
            else null end;
  return jsonb_build_object('found',true,'namespace_key',ns.namespace_key,'configuration_key',ent.configuration_key,
    'value_type',ent.value_type,'value',val,'secret',ent.value_type='secret_reference','version',ent.version,
    'checksum',ent.checksum,'environment',env.environment_code,'source_organization_id',ent.organization_id,
    'source_environment_id',ent.environment_id,'effective_from',ent.effective_from,'effective_until',ent.effective_until);
end;
$$;

create or replace function public.upsert_configuration_value(
  p_organization_id uuid,p_namespace_key text,p_configuration_key text,
  p_environment_code text default 'production',p_value_type text default 'json',
  p_value jsonb default '{}'::jsonb,p_is_sensitive boolean default false,
  p_is_required boolean default false,p_inheritance_mode text default 'override',
  p_change_reason text default null,p_metadata jsonb default '{}'::jsonb
)
returns public.configuration_entries
language plpgsql
security definer
set search_path=''
as $$
declare
  env public.feature_environments; ns public.configuration_namespaces; ent public.configuration_entries;
  bv boolean; sv text; nv numeric; jv jsonb; secret text;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.manage_config') then
    raise exception 'Permission denied';
  end if;
  env:=public.resolve_feature_environment(p_organization_id,p_environment_code);
  select * into ns from public.configuration_namespaces n
  where n.namespace_key=p_namespace_key and n.status='active'
    and (n.organization_id=p_organization_id or n.organization_id is null)
  order by case when n.organization_id=p_organization_id then 0 else 1 end limit 1;
  if not found then
    insert into public.configuration_namespaces(
      organization_id,namespace_key,namespace_name,description,status,created_by,updated_by
    ) values (p_organization_id,p_namespace_key,initcap(replace(p_namespace_key,'_',' ')),
      'Tenant configuration namespace','active',auth.uid(),auth.uid()) returning * into ns;
  end if;
  if ns.change_control_required and auth.role()<>'service_role' then raise exception 'Approved change request required'; end if;

  if p_value_type='boolean' then bv:=(p_value#>>'{}')::boolean;
  elsif p_value_type='string' then sv:=p_value#>>'{}';
  elsif p_value_type='number' then nv:=(p_value#>>'{}')::numeric;
  elsif p_value_type='json' then jv:=p_value;
  elsif p_value_type='secret_reference' then secret:=p_value#>>'{}';
  else raise exception 'Unsupported value type'; end if;
  if p_is_sensitive and p_value_type<>'secret_reference' then raise exception 'Sensitive values require secret_reference'; end if;

  select * into ent from public.configuration_entries
  where namespace_id=ns.id and organization_id=p_organization_id and environment_id=env.id
    and configuration_key=p_configuration_key and status<>'archived' limit 1 for update;
  if found then
    update public.configuration_entries set
      value_type=p_value_type,boolean_value=bv,string_value=sv,number_value=nv,json_value=jv,
      secret_reference=secret,is_sensitive=p_is_sensitive,is_required=p_is_required,
      inheritance_mode=p_inheritance_mode,status='active',
      metadata=metadata||coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('change_reason',coalesce(p_change_reason,'Configuration updated')),
      updated_by=auth.uid(),updated_at=now()
    where id=ent.id returning * into ent;
  else
    insert into public.configuration_entries(
      organization_id,namespace_id,environment_id,configuration_key,display_name,value_type,
      boolean_value,string_value,number_value,json_value,secret_reference,is_sensitive,is_required,
      inheritance_mode,status,metadata,created_by,updated_by
    ) values (
      p_organization_id,ns.id,env.id,p_configuration_key,initcap(replace(p_configuration_key,'_',' ')),p_value_type,
      bv,sv,nv,jv,secret,p_is_sensitive,p_is_required,p_inheritance_mode,'active',
      coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('change_reason',coalesce(p_change_reason,'Configuration created')),
      auth.uid(),auth.uid()
    ) returning * into ent;
  end if;
  perform public.invalidate_feature_configuration_cache(p_organization_id,env.id,'configuration',
    'Configuration updated: '||p_namespace_key||'.'||p_configuration_key,
    jsonb_build_object('configuration_entry_id',ent.id,'version',ent.version));
  return ent;
end;
$$;

-- ============================================================
-- 16. FLAG MANAGEMENT FUNCTIONS
-- ============================================================

create or replace function public.set_feature_flag_environment_state(
  p_organization_id uuid,p_feature_key text,p_environment_code text,
  p_enabled boolean,p_default_variant_key text default null,
  p_rollout_percentage numeric default 100,p_stickiness_key text default 'user_id',
  p_change_reason text default null,p_metadata jsonb default '{}'::jsonb
)
returns public.feature_flag_environment_state
language plpgsql
security definer
set search_path=''
as $$
declare f public.feature_flags; e public.feature_environments; s public.feature_flag_environment_state;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.manage_flags') then
    raise exception 'Permission denied';
  end if;
  f:=public.resolve_feature_flag(p_organization_id,p_feature_key);
  e:=public.resolve_feature_environment(p_organization_id,p_environment_code);
  if f.change_control_required and auth.role()<>'service_role' then raise exception 'Approved change request required'; end if;

  select * into s
  from public.feature_flag_environment_state st
  where st.organization_id is not distinct from p_organization_id
    and st.feature_flag_id=f.id
    and st.environment_id=e.id
  limit 1 for update;

  if found then
    update public.feature_flag_environment_state
    set enabled=p_enabled,
        default_variant_key=coalesce(p_default_variant_key,f.default_variant_key),
        rollout_percentage=greatest(0,least(100,p_rollout_percentage)),
        rollout_stickiness_key=p_stickiness_key,
        version=version+1,status='active',
        metadata=metadata||coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('change_reason',p_change_reason),
        updated_by=auth.uid(),updated_at=now()
    where id=s.id returning * into s;
  else
    insert into public.feature_flag_environment_state(
      organization_id,feature_flag_id,environment_id,enabled,default_variant_key,
      rollout_percentage,rollout_stickiness_key,status,metadata,created_by,updated_by
    ) values (
      p_organization_id,f.id,e.id,p_enabled,coalesce(p_default_variant_key,f.default_variant_key),
      greatest(0,least(100,p_rollout_percentage)),p_stickiness_key,'active',
      coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('change_reason',p_change_reason),auth.uid(),auth.uid()
    ) returning * into s;
  end if;

  perform public.invalidate_feature_configuration_cache(p_organization_id,e.id,'feature',
    'Feature state updated: '||p_feature_key,
    jsonb_build_object('feature_flag_id',f.id,'enabled',s.enabled,'rollout_percentage',s.rollout_percentage,'version',s.version));
  return s;
end;
$$;

create or replace function public.upsert_feature_flag_override(
  p_organization_id uuid,p_feature_key text,p_environment_code text,
  p_target_type text,p_target_key text,p_enabled boolean default null,
  p_variant_key text default null,p_priority integer default 10,
  p_reason text default null,p_starts_at timestamptz default null,
  p_expires_at timestamptz default null,p_metadata jsonb default '{}'::jsonb
)
returns public.feature_flag_overrides
language plpgsql
security definer
set search_path=''
as $$
declare f public.feature_flags; e public.feature_environments; o public.feature_flag_overrides;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.manage_overrides') then
    raise exception 'Permission denied';
  end if;
  f:=public.resolve_feature_flag(p_organization_id,p_feature_key);
  e:=public.resolve_feature_environment(p_organization_id,p_environment_code);
  select * into o
  from public.feature_flag_overrides ov
  where ov.organization_id is not distinct from p_organization_id
    and ov.feature_flag_id=f.id and ov.environment_id=e.id
    and ov.target_type=p_target_type and ov.target_key=p_target_key
  limit 1 for update;

  if found then
    update public.feature_flag_overrides
    set enabled=p_enabled,variant_key=p_variant_key,priority=p_priority,
        reason=p_reason,starts_at=p_starts_at,expires_at=p_expires_at,status='active',
        metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_by=auth.uid(),updated_at=now()
    where id=o.id returning * into o;
  else
    insert into public.feature_flag_overrides(
      organization_id,feature_flag_id,environment_id,target_type,target_key,enabled,variant_key,
      priority,reason,starts_at,expires_at,status,metadata,created_by,updated_by
    ) values (
      p_organization_id,f.id,e.id,p_target_type,p_target_key,p_enabled,p_variant_key,
      p_priority,p_reason,p_starts_at,p_expires_at,'active',coalesce(p_metadata,'{}'::jsonb),auth.uid(),auth.uid()
    ) returning * into o;
  end if;
  perform public.invalidate_feature_configuration_cache(p_organization_id,e.id,'feature','Feature override updated',
    jsonb_build_object('feature_flag_id',f.id,'override_id',o.id,'target_type',p_target_type,'target_key',p_target_key));
  return o;
end;
$$;

create or replace function public.set_feature_kill_switch(
  p_organization_id uuid,p_switch_key text,p_switch_name text,p_scope_type text,
  p_feature_key text default null,p_environment_code text default null,
  p_module_code text default null,p_active boolean default true,
  p_force_enabled boolean default false,p_force_variant_key text default null,
  p_severity text default 'critical',p_reason text default null,
  p_expires_at timestamptz default null,p_metadata jsonb default '{}'::jsonb
)
returns public.feature_kill_switches
language plpgsql
security definer
set search_path=''
as $$
declare f public.feature_flags; e public.feature_environments; k public.feature_kill_switches;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.manage_kill_switch') then
    raise exception 'Permission denied';
  end if;
  if p_feature_key is not null then f:=public.resolve_feature_flag(p_organization_id,p_feature_key); end if;
  if p_environment_code is not null then e:=public.resolve_feature_environment(p_organization_id,p_environment_code); end if;

  select * into k from public.feature_kill_switches
  where ((organization_id=p_organization_id) or (organization_id is null and p_organization_id is null))
    and switch_key=p_switch_key limit 1 for update;
  if found then
    update public.feature_kill_switches set
      switch_name=p_switch_name,scope_type=p_scope_type,feature_flag_id=f.id,environment_id=e.id,
      module_code=p_module_code,active=p_active,force_enabled=p_force_enabled,
      force_variant_key=p_force_variant_key,severity=p_severity,
      activation_reason=case when p_active then p_reason else activation_reason end,
      activated_at=case when p_active then now() else activated_at end,
      activated_by=case when p_active then auth.uid() else activated_by end,
      released_at=case when not p_active then now() else null end,
      released_by=case when not p_active then auth.uid() else null end,
      release_reason=case when not p_active then p_reason else null end,
      expires_at=p_expires_at,metadata=metadata||coalesce(p_metadata,'{}'::jsonb),updated_at=now()
    where id=k.id returning * into k;
  else
    insert into public.feature_kill_switches(
      organization_id,switch_key,switch_name,scope_type,feature_flag_id,environment_id,module_code,
      active,force_enabled,force_variant_key,severity,activation_reason,activated_at,activated_by,
      released_at,released_by,release_reason,expires_at,status,metadata
    ) values (
      p_organization_id,p_switch_key,p_switch_name,p_scope_type,f.id,e.id,p_module_code,
      p_active,p_force_enabled,p_force_variant_key,p_severity,case when p_active then p_reason end,
      case when p_active then now() end,case when p_active then auth.uid() end,
      case when not p_active then now() end,case when not p_active then auth.uid() end,
      case when not p_active then p_reason end,p_expires_at,'active',coalesce(p_metadata,'{}'::jsonb)
    ) returning * into k;
  end if;

  if e.id is not null then perform public.invalidate_feature_configuration_cache(p_organization_id,e.id,'feature',
    case when p_active then 'Kill switch activated' else 'Kill switch released' end,
    jsonb_build_object('kill_switch_id',k.id,'switch_key',k.switch_key,'active',k.active,'reason',p_reason)); end if;

  perform public.publish_feature_configuration_event(p_organization_id,e.id,
    case when p_active then 'feature_configuration.kill_switch.activated' else 'feature_configuration.kill_switch.released' end,
    jsonb_build_object('kill_switch_id',k.id,'switch_key',k.switch_key,'scope_type',k.scope_type,
      'feature_flag_id',k.feature_flag_id,'module_code',k.module_code,'active',k.active,
      'force_enabled',k.force_enabled,'force_variant_key',k.force_variant_key,'severity',k.severity,'reason',p_reason),
    'observability','feature_kill_switch',k.id,1,
    'feature-kill-switch:'||k.id::text||':'||extract(epoch from k.updated_at)::bigint::text);
  return k;
end;
$$;

-- ============================================================
-- 17. SDK CLIENTS AND SNAPSHOTS
-- ============================================================

create or replace function public.create_feature_sdk_client(
  p_organization_id uuid,p_environment_code text,p_client_code text,p_client_name text,
  p_client_type text default 'server',p_allowed_origins text[] default '{}',
  p_allowed_ip_ranges text[] default '{}',p_rate_limit_per_minute integer default 600,
  p_expires_at timestamptz default null,p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare e public.feature_environments; c public.feature_sdk_clients; raw_key text; h text;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.manage_sdk') then
    raise exception 'Permission denied';
  end if;
  e:=public.resolve_feature_environment(p_organization_id,p_environment_code);
  raw_key:='ssf_'||lower(e.environment_code)||'_'||encode(extensions.gen_random_bytes(32),'hex');
  h:=encode(extensions.digest(raw_key,'sha256'),'hex');
  insert into public.feature_sdk_clients(
    organization_id,environment_id,client_code,client_name,client_type,key_prefix,key_hash,
    allowed_origins,allowed_ip_ranges,rate_limit_per_minute,last_rotated_at,expires_at,status,
    metadata,created_by,updated_by
  ) values (
    p_organization_id,e.id,p_client_code,p_client_name,p_client_type,substr(raw_key,1,18),h,
    coalesce(p_allowed_origins,'{}'),coalesce(p_allowed_ip_ranges,'{}'),greatest(p_rate_limit_per_minute,1),
    now(),p_expires_at,'active',coalesce(p_metadata,'{}'::jsonb),auth.uid(),auth.uid()
  ) on conflict(organization_id,environment_id,client_code) do update set
    client_name=excluded.client_name,client_type=excluded.client_type,key_prefix=excluded.key_prefix,
    key_hash=excluded.key_hash,allowed_origins=excluded.allowed_origins,allowed_ip_ranges=excluded.allowed_ip_ranges,
    rate_limit_per_minute=excluded.rate_limit_per_minute,last_rotated_at=now(),expires_at=excluded.expires_at,
    status='active',metadata=public.feature_sdk_clients.metadata||excluded.metadata,updated_by=auth.uid(),updated_at=now()
  returning * into c;
  return jsonb_build_object('sdk_client_id',c.id,'organization_id',c.organization_id,'environment_id',c.environment_id,
    'client_code',c.client_code,'client_type',c.client_type,'key_prefix',c.key_prefix,'sdk_key',raw_key,'expires_at',c.expires_at);
end;
$$;

create or replace function public.authenticate_feature_sdk_client(p_sdk_key text)
returns public.feature_sdk_clients
language plpgsql
security definer
set search_path=''
as $$
declare c public.feature_sdk_clients; h text;
begin
  h:=encode(extensions.digest(p_sdk_key,'sha256'),'hex');
  select * into c from public.feature_sdk_clients
  where key_hash=h and status='active' and (expires_at is null or expires_at>now()) limit 1;
  if not found then raise exception 'Invalid or expired feature SDK key'; end if;
  update public.feature_sdk_clients set last_used_at=now(),updated_at=now() where id=c.id;
  return c;
end;
$$;

create or replace function public.generate_feature_configuration_snapshot(
  p_organization_id uuid,p_environment_code text default 'production',
  p_snapshot_type text default 'full',p_expires_in_seconds integer default 3600
)
returns public.feature_configuration_snapshots
language plpgsql
security definer
set search_path=''
as $$
declare
  e public.feature_environments; c public.feature_configuration_cache_versions;
  s public.feature_configuration_snapshots; fp jsonb:='{}'; cp jsonb:='{}'; payload jsonb; checksum_value text;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.view') then
    raise exception 'Permission denied';
  end if;
  e:=public.resolve_feature_environment(p_organization_id,p_environment_code);
  select * into c from public.feature_configuration_cache_versions
  where organization_id=p_organization_id and environment_id=e.id and cache_key='default' limit 1;
  if not found then
    insert into public.feature_configuration_cache_versions(
      organization_id,environment_id,cache_key,version,feature_version,configuration_version,
      last_invalidated_at,invalidation_reason
    ) values (p_organization_id,e.id,'default',1,1,1,now(),'Initial snapshot') returning * into c;
  end if;

  if p_snapshot_type in ('features','full') then
    select coalesce(jsonb_object_agg(f.feature_key,jsonb_build_object(
      'feature_flag_id',f.id,'feature_name',f.feature_name,'module_code',f.module_code,
      'flag_type',f.flag_type,'default_enabled',f.default_enabled,'default_variant_key',f.default_variant_key,
      'environment_enabled',coalesce(st.enabled,f.default_enabled),
      'environment_default_variant_key',coalesce(st.default_variant_key,f.default_variant_key),
      'rollout_percentage',coalesce(st.rollout_percentage,0),'emergency_disabled',coalesce(st.emergency_disabled,false),
      'version',coalesce(st.version,1),'updated_at',greatest(f.updated_at,coalesce(st.updated_at,f.updated_at))
    )),'{}'::jsonb) into fp
    from public.feature_flags f left join public.feature_flag_environment_state st
      on st.feature_flag_id=f.id and st.environment_id=e.id and st.status='active'
    where f.status='active' and (f.organization_id=p_organization_id or f.organization_id is null);
  end if;

  if p_snapshot_type in ('configuration','full') then
    select coalesce(jsonb_object_agg(namespace_key,namespace_values),'{}'::jsonb) into cp
    from (
      select n.namespace_key,jsonb_object_agg(x.configuration_key,jsonb_build_object(
        'value_type',x.value_type,
        'value',case when x.value_type='boolean' then to_jsonb(x.boolean_value)
                     when x.value_type='string' then to_jsonb(x.string_value)
                     when x.value_type='number' then to_jsonb(x.number_value)
                     when x.value_type='json' then x.json_value else null end,
        'secret',x.value_type='secret_reference','version',x.version,'checksum',x.checksum
      )) namespace_values
      from public.configuration_namespaces n
      join lateral(
        select distinct on(ce.configuration_key) ce.* from public.configuration_entries ce
        where ce.namespace_id=n.id and ce.status='active' and ce.effective_from<=now()
          and (ce.effective_until is null or ce.effective_until>now())
          and (ce.organization_id=p_organization_id or ce.organization_id is null)
          and (ce.environment_id=e.id or ce.environment_id is null)
        order by ce.configuration_key,
          case when ce.organization_id=p_organization_id then 0 else 1 end,
          case when ce.environment_id=e.id then 0 else 1 end,ce.version desc
      )x on true
      where n.status='active' and (n.organization_id=p_organization_id or n.organization_id is null)
      group by n.namespace_key
    )q;
  end if;

  payload:=jsonb_build_object('organization_id',p_organization_id,'environment_id',e.id,
    'environment_code',e.environment_code,'snapshot_type',p_snapshot_type,'cache_version',c.version,
    'feature_version',c.feature_version,'configuration_version',c.configuration_version,
    'features',fp,'configuration',cp,'generated_at',now());
  checksum_value:=encode(extensions.digest(payload::text,'sha256'),'hex');
  insert into public.feature_configuration_snapshots(
    organization_id,environment_id,snapshot_code,snapshot_type,cache_version,payload,checksum,
    generated_at,expires_at,status,metadata,generated_by
  ) values (
    p_organization_id,e.id,'SNAP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
    p_snapshot_type,c.version,payload,checksum_value,now(),
    now()+make_interval(secs=>greatest(p_expires_in_seconds,60)),'active',
    jsonb_build_object('feature_version',c.feature_version,'configuration_version',c.configuration_version),auth.uid()
  ) returning * into s;
  update public.feature_configuration_snapshots set status='expired'
  where organization_id=p_organization_id and environment_id=e.id and id<>s.id
    and status='active' and expires_at<=now();
  return s;
end;
$$;

-- ============================================================
-- 18. CHANGE REQUEST FUNCTIONS
-- ============================================================

create or replace function public.create_feature_configuration_change_request(
  p_organization_id uuid,p_environment_code text,p_change_scope text,p_target_id uuid,
  p_target_key text,p_change_type text,p_proposed_change jsonb,
  p_current_snapshot jsonb default '{}'::jsonb,p_risk_level text default 'low',
  p_scheduled_at timestamptz default null,p_idempotency_key text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns public.feature_configuration_change_requests
language plpgsql
security definer
set search_path=''
as $$
declare e public.feature_environments; r public.feature_configuration_change_requests;
begin
  if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'feature_configuration.manage_flags')
     and not public.has_organization_permission(p_organization_id,'feature_configuration.manage_config') then
    raise exception 'Permission denied';
  end if;
  e:=public.resolve_feature_environment(p_organization_id,p_environment_code);
  if p_idempotency_key is not null then
    select * into r from public.feature_configuration_change_requests where idempotency_key=p_idempotency_key limit 1;
    if found then return r; end if;
  end if;
  insert into public.feature_configuration_change_requests(
    organization_id,environment_id,request_code,change_scope,target_id,target_key,change_type,
    proposed_change,current_snapshot,risk_level,status,requested_by,scheduled_at,idempotency_key,metadata
  ) values (
    p_organization_id,e.id,'FCR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
    p_change_scope,p_target_id,p_target_key,p_change_type,coalesce(p_proposed_change,'{}'::jsonb),
    coalesce(p_current_snapshot,'{}'::jsonb),p_risk_level,'draft',auth.uid(),p_scheduled_at,
    p_idempotency_key,coalesce(p_metadata,'{}'::jsonb)
  ) returning * into r;
  return r;
end;
$$;

create or replace function public.submit_feature_configuration_change_request(p_change_request_id uuid)
returns public.feature_configuration_change_requests
language plpgsql
security definer
set search_path=''
as $$
declare r public.feature_configuration_change_requests;
begin
  select * into r from public.feature_configuration_change_requests where id=p_change_request_id for update;
  if not found then raise exception 'Change request not found'; end if;
  if auth.role()<>'service_role' and r.requested_by is distinct from auth.uid()
     and not public.has_organization_permission(r.organization_id,'feature_configuration.manage_flags') then
    raise exception 'Permission denied';
  end if;
  if r.status<>'draft' then raise exception 'Only draft requests may be submitted'; end if;
  update public.feature_configuration_change_requests
  set status='submitted',requested_at=now(),updated_at=now() where id=r.id returning * into r;
  perform public.publish_feature_configuration_event(r.organization_id,r.environment_id,
    'feature_configuration.change_request.submitted',jsonb_build_object(
      'change_request_id',r.id,'request_code',r.request_code,'change_scope',r.change_scope,
      'change_type',r.change_type,'target_id',r.target_id,'target_key',r.target_key,'risk_level',r.risk_level),
    'notification_engine','feature_configuration_change_request',r.id,20,
    'feature-change-request-submitted:'||r.id::text,r.id::text);
  return r;
end;
$$;

create or replace function public.decide_feature_configuration_change_request(
  p_change_request_id uuid,p_decision text,p_reason text default null
)
returns public.feature_configuration_change_requests
language plpgsql
security definer
set search_path=''
as $$
declare r public.feature_configuration_change_requests;
begin
  select * into r from public.feature_configuration_change_requests where id=p_change_request_id for update;
  if not found then raise exception 'Change request not found'; end if;
  if auth.role()<>'service_role' and not public.has_organization_permission(r.organization_id,'feature_configuration.approve_changes') then
    raise exception 'Permission denied';
  end if;
  if r.status not in ('submitted','under_review') then raise exception 'Request is not awaiting decision'; end if;
  if p_decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  update public.feature_configuration_change_requests set
    status=case when p_decision='approved' and scheduled_at is not null and scheduled_at>now() then 'scheduled' else p_decision end,
    approved_by=case when p_decision='approved' then auth.uid() else approved_by end,
    approved_at=case when p_decision='approved' then now() else approved_at end,
    rejected_by=case when p_decision='rejected' then auth.uid() else rejected_by end,
    rejected_at=case when p_decision='rejected' then now() else rejected_at end,
    rejection_reason=case when p_decision='rejected' then p_reason else rejection_reason end,
    metadata=metadata||jsonb_build_object('decision_reason',p_reason),updated_at=now()
  where id=r.id returning * into r;
  perform public.publish_feature_configuration_event(r.organization_id,r.environment_id,
    'feature_configuration.change_request.'||p_decision,
    jsonb_build_object('change_request_id',r.id,'request_code',r.request_code,'decision',p_decision,'reason',p_reason,'status',r.status),
    case when p_decision='approved' then 'service_worker' else 'notification_engine' end,
    'feature_configuration_change_request',r.id,20,
    'feature-change-request-decision:'||r.id::text||':'||p_decision,r.id::text,null,coalesce(r.scheduled_at,now()));
  return r;
end;
$$;

-- ============================================================
-- 19. ANALYTICS VIEWS
-- ============================================================

create or replace view public.feature_flag_status_dashboard
with (security_invoker=true)
as
select f.organization_id,e.environment_code,f.module_code,f.lifecycle_stage,f.status,
  count(*) feature_count,
  count(*) filter(where coalesce(s.enabled,f.default_enabled)) enabled_count,
  count(*) filter(where coalesce(s.emergency_disabled,false)) emergency_disabled_count,
  count(*) filter(where s.rollout_percentage>0 and s.rollout_percentage<100) partial_rollout_count,
  avg(coalesce(s.rollout_percentage,0)) average_rollout_percentage,
  max(greatest(f.updated_at,coalesce(s.updated_at,f.updated_at))) latest_update_at
from public.feature_flags f
cross join public.feature_environments e
left join public.feature_flag_environment_state s
  on s.feature_flag_id=f.id and s.environment_id=e.id and s.status='active'
where f.status<>'archived' and e.status='active'
  and (e.organization_id=f.organization_id or e.organization_id is null or f.organization_id is null)
group by f.organization_id,e.environment_code,f.module_code,f.lifecycle_stage,f.status;

create or replace view public.feature_exposure_dashboard
with (security_invoker=true)
as
select x.organization_id,e.environment_code,x.feature_key,x.enabled,x.variant_key,x.evaluation_reason,
  count(*) exposure_count,
  count(distinct x.subject_key) filter(where x.subject_key is not null) unique_subject_count,
  count(distinct x.user_id) filter(where x.user_id is not null) unique_user_count,
  count(*) filter(where x.evaluated_at>=now()-interval '24 hours') exposures_last_24h,
  count(*) filter(where x.evaluated_at>=now()-interval '7 days') exposures_last_7d,
  min(x.evaluated_at) first_exposure_at,max(x.evaluated_at) latest_exposure_at
from public.feature_flag_exposures x
left join public.feature_environments e on e.id=x.environment_id
group by x.organization_id,e.environment_code,x.feature_key,x.enabled,x.variant_key,x.evaluation_reason;

create or replace view public.configuration_status_dashboard
with (security_invoker=true)
as
select ce.organization_id,e.environment_code,n.namespace_key,n.module_code,ce.value_type,ce.status,
  count(*) configuration_count,
  count(*) filter(where ce.is_sensitive) sensitive_count,
  count(*) filter(where ce.is_required) required_count,
  count(*) filter(where ce.effective_until is not null and ce.effective_until<=now()+interval '7 days') expiring_within_7d,
  avg(ce.version) average_version,max(ce.updated_at) latest_update_at
from public.configuration_entries ce
join public.configuration_namespaces n on n.id=ce.namespace_id
left join public.feature_environments e on e.id=ce.environment_id
group by ce.organization_id,e.environment_code,n.namespace_key,n.module_code,ce.value_type,ce.status;

create or replace view public.feature_rollout_dashboard
with (security_invoker=true)
as
select f.organization_id,e.environment_code,f.feature_key,f.feature_name,f.module_code,
  coalesce(s.enabled,f.default_enabled) enabled,
  coalesce(s.default_variant_key,f.default_variant_key) default_variant_key,
  coalesce(s.rollout_percentage,0) rollout_percentage,
  coalesce(s.emergency_disabled,false) emergency_disabled,
  count(distinct r.id) filter(where r.status='active') active_rule_count,
  count(distinct o.id) filter(where o.status='active' and (o.expires_at is null or o.expires_at>now())) active_override_count,
  count(distinct k.id) filter(where k.active and k.status='active') active_kill_switch_count,
  greatest(f.updated_at,coalesce(s.updated_at,f.updated_at)) latest_update_at
from public.feature_flags f
cross join public.feature_environments e
left join public.feature_flag_environment_state s on s.feature_flag_id=f.id and s.environment_id=e.id
left join public.feature_flag_rules r on r.feature_flag_id=f.id and r.environment_id=e.id
left join public.feature_flag_overrides o on o.feature_flag_id=f.id and o.environment_id=e.id
left join public.feature_kill_switches k on
  ((k.feature_flag_id=f.id) or (k.scope_type='module' and k.module_code=f.module_code) or k.scope_type='platform')
  and (k.environment_id is null or k.environment_id=e.id)
where f.status='active' and e.status='active'
  and (e.organization_id=f.organization_id or e.organization_id is null or f.organization_id is null)
group by f.organization_id,e.environment_code,f.id,f.feature_key,f.feature_name,f.module_code,
  f.default_enabled,f.default_variant_key,f.updated_at,s.enabled,s.default_variant_key,
  s.rollout_percentage,s.emergency_disabled,s.updated_at;

create or replace view public.feature_configuration_change_dashboard
with (security_invoker=true)
as
select r.organization_id,e.environment_code,r.change_scope,r.change_type,r.risk_level,r.status,
  count(*) request_count,
  count(*) filter(where r.created_at>=now()-interval '7 days') requests_last_7d,
  count(*) filter(where r.status in ('submitted','under_review')) pending_approval_count,
  count(*) filter(where r.status='scheduled') scheduled_count,
  count(*) filter(where r.status='failed') failed_count,
  avg(extract(epoch from(coalesce(r.approved_at,r.rejected_at,now())-r.created_at))/3600) average_decision_hours,
  max(r.updated_at) latest_update_at
from public.feature_configuration_change_requests r
left join public.feature_environments e on e.id=r.environment_id
group by r.organization_id,e.environment_code,r.change_scope,r.change_type,r.risk_level,r.status;

grant select on
  public.feature_flag_status_dashboard,
  public.feature_exposure_dashboard,
  public.configuration_status_dashboard,
  public.feature_rollout_dashboard,
  public.feature_configuration_change_dashboard
to authenticated,service_role;

-- ============================================================
-- 20. HEALTH CHECK
-- ============================================================

create or replace function public.get_feature_configuration_engine_health(p_organization_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if auth.role()<>'service_role' and (p_organization_id is null or not public.has_organization_permission(p_organization_id,'feature_configuration.view_logs')) then
    raise exception 'Permission denied';
  end if;
  return jsonb_build_object(
    'organization_id',p_organization_id,'checked_at',now(),
    'active_flags',(select count(*) from public.feature_flags f where f.status='active'
      and (p_organization_id is null or f.organization_id=p_organization_id or f.organization_id is null)),
    'partial_rollouts',(select count(*) from public.feature_flag_environment_state s where s.status='active'
      and s.enabled and s.rollout_percentage>0 and s.rollout_percentage<100
      and (p_organization_id is null or s.organization_id=p_organization_id or s.organization_id is null)),
    'active_kill_switches',(select count(*) from public.feature_kill_switches k where k.active and k.status='active'
      and (k.expires_at is null or k.expires_at>now())
      and (p_organization_id is null or k.organization_id=p_organization_id or k.organization_id is null)),
    'expired_active_overrides',(select count(*) from public.feature_flag_overrides o where o.status='active'
      and o.expires_at is not null and o.expires_at<=now()
      and (p_organization_id is null or o.organization_id=p_organization_id or o.organization_id is null)),
    'scheduled_changes_due',(select count(*) from public.feature_configuration_change_requests r
      where r.status='scheduled' and r.scheduled_at<=now()
      and (p_organization_id is null or r.organization_id=p_organization_id)),
    'sensitive_plaintext_violations',(select count(*) from public.configuration_entries ce
      where ce.is_sensitive and ce.value_type<>'secret_reference'
      and (p_organization_id is null or ce.organization_id=p_organization_id or ce.organization_id is null)),
    'expired_sdk_clients_active',(select count(*) from public.feature_sdk_clients c
      where c.status='active' and c.expires_at is not null and c.expires_at<=now()
      and (p_organization_id is null or c.organization_id=p_organization_id)),
    'pending_outbox_events',(select count(*) from public.feature_configuration_event_outbox o
      where o.status in ('pending','failed','claimed','processing')
      and (p_organization_id is null or o.organization_id=p_organization_id or o.organization_id is null)),
    'dead_lettered_outbox_events',(select count(*) from public.feature_configuration_event_outbox o
      where o.status='dead_lettered'
      and (p_organization_id is null or o.organization_id=p_organization_id or o.organization_id is null)),
    'expired_event_locks',(select count(*) from public.feature_configuration_event_outbox o
      where o.status in ('claimed','processing') and o.lock_expires_at is not null and o.lock_expires_at<=now()
      and (p_organization_id is null or o.organization_id=p_organization_id or o.organization_id is null)),
    'exposures_last_24h',(select count(*) from public.feature_flag_exposures x
      where x.evaluated_at>=now()-interval '24 hours'
      and (p_organization_id is null or x.organization_id=p_organization_id))
  );
end;
$$;

-- ============================================================
-- 21. ROW LEVEL SECURITY
-- ============================================================

alter table public.feature_environments enable row level security;
alter table public.feature_flags enable row level security;
alter table public.feature_flag_variants enable row level security;
alter table public.feature_flag_environment_state enable row level security;
alter table public.feature_segments enable row level security;
alter table public.feature_segment_members enable row level security;
alter table public.feature_flag_rules enable row level security;
alter table public.feature_flag_overrides enable row level security;
alter table public.feature_kill_switches enable row level security;
alter table public.configuration_namespaces enable row level security;
alter table public.configuration_entries enable row level security;
alter table public.configuration_entry_versions enable row level security;
alter table public.feature_configuration_change_requests enable row level security;
alter table public.feature_sdk_clients enable row level security;
alter table public.feature_configuration_cache_versions enable row level security;
alter table public.feature_configuration_snapshots enable row level security;
alter table public.feature_flag_exposures enable row level security;
alter table public.feature_configuration_event_outbox enable row level security;
alter table public.feature_configuration_logs enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'feature_environments','feature_flags','feature_flag_variants','feature_flag_environment_state',
    'feature_segments','feature_segment_members','feature_flag_rules','feature_flag_overrides',
    'feature_kill_switches','configuration_namespaces','configuration_entries',
    'configuration_entry_versions','feature_configuration_change_requests','feature_sdk_clients',
    'feature_configuration_cache_versions','feature_configuration_snapshots','feature_flag_exposures',
    'feature_configuration_event_outbox','feature_configuration_logs'
  ] loop
    execute format('drop policy if exists %I_select_policy on public.%I',t,t);
    execute format(
      'create policy %I_select_policy on public.%I for select to authenticated using '
      '(organization_id is null or public.has_organization_permission(organization_id,''feature_configuration.view'') '
      'or public.has_organization_permission(organization_id,''feature_configuration.view_all''))',t,t
    );
    execute format('drop policy if exists %I_service_policy on public.%I',t,t);
    execute format(
      'create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t
    );
  end loop;
end;
$$;

-- ============================================================
-- 22. GRANTS
-- ============================================================

grant select on
  public.feature_environments,public.feature_flags,public.feature_flag_variants,
  public.feature_flag_environment_state,public.feature_segments,public.feature_segment_members,
  public.feature_flag_rules,public.feature_flag_overrides,public.feature_kill_switches,
  public.configuration_namespaces,public.configuration_entries,public.configuration_entry_versions,
  public.feature_configuration_change_requests,public.feature_sdk_clients,
  public.feature_configuration_cache_versions,public.feature_configuration_snapshots,
  public.feature_flag_exposures,public.feature_configuration_event_outbox,
  public.feature_configuration_logs
to authenticated;

grant all on
  public.feature_environments,public.feature_flags,public.feature_flag_variants,
  public.feature_flag_environment_state,public.feature_segments,public.feature_segment_members,
  public.feature_flag_rules,public.feature_flag_overrides,public.feature_kill_switches,
  public.configuration_namespaces,public.configuration_entries,public.configuration_entry_versions,
  public.feature_configuration_change_requests,public.feature_sdk_clients,
  public.feature_configuration_cache_versions,public.feature_configuration_snapshots,
  public.feature_flag_exposures,public.feature_configuration_event_outbox,
  public.feature_configuration_logs
to service_role;

do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'feature_safe_uuid','feature_context_value','feature_condition_matches','feature_conditions_match',
      'feature_rollout_bucket','resolve_feature_environment','resolve_feature_flag','feature_variant_payload',
      'feature_segment_matches','feature_rule_segments_match','pick_feature_variant','evaluate_feature_flag',
      'evaluate_feature_flags','resolve_configuration_value','upsert_configuration_value',
      'invalidate_feature_configuration_cache','set_feature_flag_environment_state',
      'upsert_feature_flag_override','set_feature_kill_switch','create_feature_sdk_client',
      'generate_feature_configuration_snapshot','create_feature_configuration_change_request',
      'submit_feature_configuration_change_request','decide_feature_configuration_change_request',
      'get_feature_configuration_engine_health'
    )
  loop
    execute format('revoke all on function %s from public',r.signature);
    execute format('grant execute on function %s to authenticated,service_role',r.signature);
  end loop;

  for r in
    select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in (
      'validate_configuration_entry_value','prepare_configuration_entry_version','record_configuration_entry_version',
      'authenticate_feature_sdk_client','publish_feature_configuration_event',
      'claim_feature_configuration_event','complete_feature_configuration_event',
      'fail_feature_configuration_event'
    )
  loop
    execute format('revoke all on function %s from public',r.signature);
    execute format('grant execute on function %s to service_role',r.signature);
  end loop;
end;
$$;

-- ============================================================
-- 23. SYSTEM ENVIRONMENTS
-- ============================================================

insert into public.feature_environments(
  organization_id,environment_code,environment_name,description,environment_type,
  is_default,is_production,evaluation_enabled,status,configuration,metadata
) values
  (null,'development','Development','Development feature environment','development',false,false,true,'active',
   jsonb_build_object('cache_ttl_seconds',30),jsonb_build_object('seeded_by_migration','034')),
  (null,'staging','Staging','Pre-production feature environment','staging',false,false,true,'active',
   jsonb_build_object('cache_ttl_seconds',60),jsonb_build_object('seeded_by_migration','034')),
  (null,'production','Production','Production feature environment','production',true,true,true,'active',
   jsonb_build_object('cache_ttl_seconds',300),jsonb_build_object('seeded_by_migration','034'))
on conflict do nothing;

-- ============================================================
-- 24. SYSTEM FLAGS AND VARIANTS
-- ============================================================

insert into public.feature_flags(
  organization_id,feature_key,feature_name,description,module_code,owner_team,flag_type,
  lifecycle_stage,default_enabled,default_variant_key,evaluation_enabled,tags,
  change_control_required,exposure_logging_enabled,status,metadata
) values
  (null,'lead_validation_engine','Lead Validation Engine','Duplicate and fake lead validation','lead_validation','platform','boolean','general_availability',true,'on',true,array['core','lead','validation'],true,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'ai_calling','AI Calling','AI calling and qualification','ai_calling','ai','boolean','general_availability',true,'on',true,array['ai','calling'],true,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'automatic_assignment','Automatic Lead Assignment','Automatic agent assignment','assignment','sales','boolean','general_availability',true,'on',true,array['lead','assignment'],false,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'whatsapp_automation','WhatsApp Automation','Automated WhatsApp engagement','communication','communication','boolean','general_availability',true,'on',true,array['whatsapp','automation'],true,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'customer_portal','Customer Portal','Controlled customer portal access','customer_portal','product','boolean','beta',false,'off',true,array['customer','portal','beta'],true,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'advanced_analytics','Advanced Analytics','Advanced BI dashboards','analytics','data','boolean','general_availability',true,'on',true,array['analytics','bi'],false,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'mobile_application','Mobile Application','SalesSetu mobile application','mobile','product','boolean','beta',false,'off',true,array['mobile','beta'],true,true,'active',jsonb_build_object('seeded_by_migration','034'))
on conflict do nothing;

with flags as (
  select id,feature_key,default_enabled,default_variant_key from public.feature_flags
  where organization_id is null and feature_key in (
    'lead_validation_engine','ai_calling','automatic_assignment','whatsapp_automation',
    'customer_portal','advanced_analytics','mobile_application'
  )
),envs as (
  select id,environment_code from public.feature_environments
  where organization_id is null and environment_code in ('development','staging','production')
)
insert into public.feature_flag_environment_state(
  organization_id,feature_flag_id,environment_id,enabled,default_variant_key,
  rollout_percentage,rollout_stickiness_key,status,metadata
)
select null,f.id,e.id,
  case when e.environment_code='development' then true else f.default_enabled end,
  case when e.environment_code='development' then 'on' else f.default_variant_key end,
  case when f.feature_key in ('customer_portal','mobile_application') and e.environment_code='staging' then 25
       when f.feature_key in ('customer_portal','mobile_application') and e.environment_code='production' then 0
       else 100 end,
  'user_id','active',jsonb_build_object('seeded_by_migration','034')
from flags f cross join envs e
where not exists (
  select 1 from public.feature_flag_environment_state st
  where st.organization_id is null and st.feature_flag_id=f.id and st.environment_id=e.id
);

with flags as (select id from public.feature_flags where organization_id is null)
insert into public.feature_flag_variants(
  organization_id,feature_flag_id,variant_key,variant_name,description,boolean_value,
  is_control,is_enabled_variant,weight,sequence_number,status,metadata
)
select null,f.id,v.variant_key,v.variant_name,v.description,v.boolean_value,
  v.is_control,v.is_enabled_variant,v.weight,v.sequence_number,'active',jsonb_build_object('seeded_by_migration','034')
from flags f cross join (
  values
    ('off','Off','Feature disabled',false,true,false,0::numeric,10),
    ('on','On','Feature enabled',true,false,true,100::numeric,20)
) v(variant_key,variant_name,description,boolean_value,is_control,is_enabled_variant,weight,sequence_number)
on conflict(feature_flag_id,variant_key) do nothing;

-- ============================================================
-- 25. SYSTEM CONFIGURATION NAMESPACES
-- ============================================================

insert into public.configuration_namespaces(
  organization_id,namespace_key,namespace_name,description,module_code,
  validation_enabled,change_control_required,status,metadata
) values
  (null,'platform','Platform','Core platform configuration','platform',false,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'lead_management','Lead Management','Lead capture and qualification configuration','leads',false,false,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'communication','Communication','Messaging and communication configuration','communication',false,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'ai','AI','AI model and calling configuration','ai',false,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'security','Security','Security and compliance configuration','security',false,true,'active',jsonb_build_object('seeded_by_migration','034')),
  (null,'billing','Billing','Subscription and quota configuration','billing',false,true,'active',jsonb_build_object('seeded_by_migration','034'))
on conflict do nothing;

insert into public.feature_configuration_cache_versions(
  organization_id,environment_id,cache_key,version,feature_version,configuration_version,
  last_invalidated_at,invalidation_reason,metadata
)
select null,e.id,'default',1,1,1,now(),'Migration 034 initial cache version',jsonb_build_object('seeded_by_migration','034')
from public.feature_environments e
where e.organization_id is null and e.status='active'
  and not exists (
    select 1 from public.feature_configuration_cache_versions c
    where c.organization_id is null and c.environment_id=e.id and c.cache_key='default'
  );

-- ============================================================
-- 26. FINAL VALIDATION
-- ============================================================

do $$
declare item text; missing text[]:='{}';
begin
  foreach item in array array[
    'feature_environments','feature_flags','feature_flag_variants','feature_flag_environment_state',
    'feature_segments','feature_segment_members','feature_flag_rules','feature_flag_overrides',
    'feature_kill_switches','configuration_namespaces','configuration_entries',
    'configuration_entry_versions','feature_configuration_change_requests','feature_sdk_clients',
    'feature_configuration_cache_versions','feature_configuration_snapshots','feature_flag_exposures',
    'feature_configuration_event_outbox','feature_configuration_logs'
  ] loop
    if not exists(select 1 from information_schema.tables where table_schema='public' and table_name=item) then
      missing:=array_append(missing,'table:'||item);
    end if;
  end loop;

  foreach item in array array[
    'feature_safe_uuid','feature_context_value','feature_condition_matches','feature_conditions_match',
    'feature_rollout_bucket','resolve_feature_environment','resolve_feature_flag','feature_variant_payload',
    'feature_segment_matches','feature_rule_segments_match','pick_feature_variant',
    'publish_feature_configuration_event','claim_feature_configuration_event',
    'complete_feature_configuration_event','fail_feature_configuration_event',
    'invalidate_feature_configuration_cache','evaluate_feature_flag','evaluate_feature_flags',
    'resolve_configuration_value','upsert_configuration_value','set_feature_flag_environment_state',
    'upsert_feature_flag_override','set_feature_kill_switch','create_feature_sdk_client',
    'authenticate_feature_sdk_client','generate_feature_configuration_snapshot',
    'create_feature_configuration_change_request','submit_feature_configuration_change_request',
    'decide_feature_configuration_change_request','get_feature_configuration_engine_health'
  ] loop
    if not exists(select 1 from information_schema.routines where routine_schema='public' and routine_name=item) then
      missing:=array_append(missing,'function:'||item);
    end if;
  end loop;

  if cardinality(missing)>0 then
    raise exception '034 migration validation failed. Missing: %',array_to_string(missing,', ');
  end if;
end;
$$;

-- ============================================================
-- 27. MIGRATION AUDIT
-- ============================================================

insert into public.feature_configuration_logs(
  organization_id,log_level,event_name,message,source_type,log_data
)
select o.id,'info','migration.034.completed',
  'Feature Flag and Configuration Engine migration 034 completed','migration',
  jsonb_build_object(
    'migration','034_feature_flag_configuration_engine','completed_at',now(),
    'modules',jsonb_build_array(
      'environments','feature_flags','variants','segments','targeting_rules','overrides',
      'percentage_rollouts','kill_switches','configuration_namespaces','configuration_entries',
      'version_history','change_requests','approvals','sdk_clients','cache_versions','snapshots',
      'exposure_logging','analytics','event_outbox','health_monitoring'
    )
  )
from public.organizations o
where not exists(
  select 1 from public.feature_configuration_logs l
  where l.organization_id=o.id and l.event_name='migration.034.completed'
);

commit;