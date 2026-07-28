-- ============================================================
-- SalesSetu Enterprise
-- Migration 016: Audit & Activity Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   009_workflow_engine_v2.sql
--   010_ai_calling_engine.sql
--   011_lead_validation_engine_production_v2.sql
--   012_assignment_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--   015_notification_engine.sql
--
-- Scope:
--   • Immutable audit trail
--   • User activity timeline
--   • API, workflow, automation and integration audit
--   • Security events, sessions, IP and device tracking
--   • Sensitive-field change history
--   • Before/after snapshots and diff metadata
--   • Retention, archival and legal-hold controls
--   • Compliance reports and analytics
--   • RLS, permissions, grants and health checks
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
    ('audit','view','audit.view','View audit records'),
    ('audit','view_all','audit.view_all','View all organization audit records'),
    ('audit','view_sensitive','audit.view_sensitive','View sensitive audit details'),
    ('audit','export','audit.export','Export audit and compliance reports'),
    ('audit','manage_retention','audit.manage_retention','Manage audit retention policies'),
    ('audit','manage_legal_hold','audit.manage_legal_hold','Manage legal holds'),
    ('audit','manage_security','audit.manage_security','Manage audit security settings'),
    ('audit','manage_sessions','audit.manage_sessions','Manage user sessions'),
    ('audit','resolve_security_event','audit.resolve_security_event','Resolve security events'),
    ('audit','view_logs','audit.view_logs','View audit engine logs'),
    ('audit','view_analytics','audit.view_analytics','View audit analytics'),
    ('audit','override','audit.override','Override audit restrictions')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. AUDIT EVENT TYPES
-- ============================================================

create table if not exists public.audit_event_types (
  code text primary key,
  display_name text not null,
  event_group text not null
    check (
      event_group in (
        'data',
        'authentication',
        'authorization',
        'security',
        'api',
        'workflow',
        'automation',
        'integration',
        'communication',
        'system',
        'compliance'
      )
    ),
  default_severity text not null default 'info'
    check (default_severity in ('info','warning','error','critical')),
  is_sensitive boolean not null default false,
  is_system boolean not null default false,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

insert into public.audit_event_types (
  code,
  display_name,
  event_group,
  default_severity,
  is_sensitive,
  is_system
)
values
  ('record.created','Record Created','data','info',false,true),
  ('record.updated','Record Updated','data','info',false,true),
  ('record.deleted','Record Deleted','data','warning',true,true),
  ('record.restored','Record Restored','data','info',false,true),
  ('auth.login.success','Login Success','authentication','info',true,true),
  ('auth.login.failed','Login Failed','authentication','warning',true,true),
  ('auth.logout','Logout','authentication','info',true,true),
  ('auth.session.revoked','Session Revoked','authentication','warning',true,true),
  ('auth.password.changed','Password Changed','security','warning',true,true),
  ('auth.mfa.changed','MFA Changed','security','warning',true,true),
  ('authorization.denied','Authorization Denied','authorization','warning',true,true),
  ('security.suspicious_activity','Suspicious Activity','security','critical',true,true),
  ('security.ip_blocked','IP Blocked','security','critical',true,true),
  ('security.device_blocked','Device Blocked','security','critical',true,true),
  ('api.request','API Request','api','info',true,true),
  ('api.error','API Error','api','error',true,true),
  ('workflow.executed','Workflow Executed','workflow','info',false,true),
  ('automation.executed','Automation Executed','automation','info',false,true),
  ('integration.webhook.received','Webhook Received','integration','info',true,true),
  ('integration.webhook.failed','Webhook Failed','integration','error',true,true),
  ('communication.sent','Communication Sent','communication','info',true,true),
  ('communication.failed','Communication Failed','communication','error',true,true),
  ('compliance.exported','Compliance Exported','compliance','warning',true,true),
  ('compliance.legal_hold','Legal Hold Changed','compliance','critical',true,true),
  ('system.config.changed','System Configuration Changed','system','warning',true,true)
on conflict (code) do update
set
  display_name = excluded.display_name,
  event_group = excluded.event_group,
  default_severity = excluded.default_severity,
  is_sensitive = excluded.is_sensitive,
  is_system = excluded.is_system;

-- ============================================================
-- 3. AUDIT ACTORS
-- ============================================================

create table if not exists public.audit_actors (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  actor_type text not null
    check (
      actor_type in (
        'user',
        'service_role',
        'system',
        'api_key',
        'webhook',
        'workflow',
        'automation',
        'integration',
        'anonymous'
      )
    ),

  user_id uuid references auth.users(id) on delete set null,
  external_actor_id text,
  display_name text,
  email text,

  ip_address inet,
  user_agent text,
  device_id text,
  session_id text,
  api_key_id text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

create index if not exists audit_actors_user_idx
  on public.audit_actors (
    organization_id,
    user_id,
    created_at desc
  );

create index if not exists audit_actors_session_idx
  on public.audit_actors (
    session_id,
    created_at desc
  );

-- ============================================================
-- 4. AUDIT EVENTS
-- ============================================================

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  event_type_code text not null references public.audit_event_types(code) on delete restrict,
  event_name text not null,
  event_group text not null,
  severity text not null default 'info'
    check (severity in ('info','warning','error','critical')),

  actor_id uuid references public.audit_actors(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  actor_type text,

  source_module text,
  source_table text,
  source_record_id uuid,
  source_reference text,

  action text,
  operation text,

  request_id text,
  correlation_id text,
  trace_id text,
  session_id text,

  ip_address inet,
  user_agent text,
  device_id text,

  before_data jsonb,
  after_data jsonb,
  changed_fields text[] not null default '{}',
  diff_data jsonb not null default '{}',

  context_data jsonb not null default '{}',
  metadata jsonb not null default '{}',

  is_sensitive boolean not null default false,
  is_redacted boolean not null default false,
  is_immutable boolean not null default true,

  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists audit_events_org_time_idx
  on public.audit_events (
    organization_id,
    occurred_at desc
  );

create index if not exists audit_events_source_idx
  on public.audit_events (
    organization_id,
    source_table,
    source_record_id,
    occurred_at desc
  );

create index if not exists audit_events_actor_idx
  on public.audit_events (
    organization_id,
    actor_user_id,
    occurred_at desc
  );

create index if not exists audit_events_correlation_idx
  on public.audit_events (
    correlation_id,
    occurred_at desc
  );

create index if not exists audit_events_security_idx
  on public.audit_events (
    organization_id,
    severity,
    event_group,
    occurred_at desc
  )
  where event_group in ('authentication','authorization','security');

-- ============================================================
-- 5. SENSITIVE FIELD REGISTRY
-- ============================================================

create table if not exists public.audit_sensitive_fields (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  table_name text not null,
  column_name text not null,

  sensitivity_level text not null default 'confidential'
    check (
      sensitivity_level in (
        'internal',
        'confidential',
        'restricted',
        'highly_restricted'
      )
    ),

  masking_strategy text not null default 'redact'
    check (
      masking_strategy in (
        'redact',
        'mask',
        'hash',
        'last_four',
        'email_mask',
        'phone_mask',
        'none'
      )
    ),

  reason text,
  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,table_name,column_name)
);

-- ============================================================
-- 6. USER ACTIVITY TIMELINE
-- ============================================================

create table if not exists public.audit_user_activities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  user_id uuid references auth.users(id) on delete set null,
  audit_event_id uuid references public.audit_events(id) on delete cascade,

  activity_type text not null,
  activity_title text,
  activity_description text,

  entity_type text,
  entity_id uuid,
  entity_reference text,

  activity_data jsonb not null default '{}',

  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists audit_user_activities_user_idx
  on public.audit_user_activities (
    organization_id,
    user_id,
    occurred_at desc
  );

-- ============================================================
-- 7. USER SESSIONS
-- ============================================================

create table if not exists public.audit_user_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  session_key text not null,
  auth_provider text,
  auth_method text,

  status text not null default 'active'
    check (
      status in (
        'active',
        'expired',
        'revoked',
        'logged_out',
        'blocked'
      )
    ),

  ip_address inet,
  user_agent text,
  device_id text,
  device_type text,
  operating_system text,
  browser text,

  country_code text,
  region text,
  city text,
  timezone text,

  risk_score numeric(8,2) not null default 0,
  risk_factors jsonb not null default '[]',

  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz,
  ended_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (session_key)
);

create index if not exists audit_user_sessions_user_idx
  on public.audit_user_sessions (
    organization_id,
    user_id,
    status,
    last_seen_at desc
  );

-- ============================================================
-- 8. SECURITY EVENTS
-- ============================================================

create table if not exists public.audit_security_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  audit_event_id uuid references public.audit_events(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  session_id uuid references public.audit_user_sessions(id) on delete set null,

  security_event_type text not null,
  severity text not null default 'warning'
    check (severity in ('info','warning','error','critical')),

  status text not null default 'open'
    check (
      status in (
        'open',
        'investigating',
        'resolved',
        'false_positive',
        'ignored',
        'archived'
      )
    ),

  title text not null,
  description text,

  ip_address inet,
  device_id text,
  user_agent text,

  detection_source text,
  risk_score numeric(8,2) not null default 0,
  indicators jsonb not null default '[]',
  evidence jsonb not null default '{}',

  assigned_to uuid references auth.users(id) on delete set null,

  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  resolution_notes text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists audit_security_events_open_idx
  on public.audit_security_events (
    organization_id,
    status,
    severity,
    created_at desc
  );

-- ============================================================
-- 9. API AUDIT
-- ============================================================

create table if not exists public.audit_api_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  audit_event_id uuid references public.audit_events(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,

  request_id text,
  correlation_id text,
  trace_id text,

  http_method text,
  request_path text,
  query_params jsonb not null default '{}',
  request_headers jsonb not null default '{}',
  request_body jsonb,

  response_status integer,
  response_headers jsonb not null default '{}',
  response_body jsonb,

  duration_ms bigint,

  ip_address inet,
  user_agent text,

  provider text,
  endpoint_type text,
  api_key_id text,

  error_code text,
  error_message text,

  requested_at timestamptz not null default now(),
  responded_at timestamptz,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists audit_api_requests_time_idx
  on public.audit_api_requests (
    organization_id,
    requested_at desc
  );

create index if not exists audit_api_requests_status_idx
  on public.audit_api_requests (
    organization_id,
    response_status,
    requested_at desc
  );

-- ============================================================
-- 10. INTEGRATION AUDIT
-- ============================================================

create table if not exists public.audit_integration_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  audit_event_id uuid references public.audit_events(id) on delete set null,

  integration_type text,
  provider_code text,
  connection_id uuid,

  direction text not null
    check (direction in ('inbound','outbound')),

  event_name text,
  external_event_id text,
  external_reference text,

  request_payload jsonb,
  response_payload jsonb,

  status text not null default 'received'
    check (
      status in (
        'received',
        'processing',
        'processed',
        'delivered',
        'failed',
        'ignored'
      )
    ),

  attempts integer not null default 0,
  duration_ms bigint,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists audit_integration_events_lookup_idx
  on public.audit_integration_events (
    organization_id,
    provider_code,
    occurred_at desc
  );

-- ============================================================
-- 11. RETENTION POLICIES
-- ============================================================

create table if not exists public.audit_retention_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  policy_code text not null,
  policy_name text not null,

  target_type text not null
    check (
      target_type in (
        'audit_events',
        'user_activities',
        'sessions',
        'security_events',
        'api_requests',
        'integration_events',
        'logs',
        'all'
      )
    ),

  retention_days integer not null check (retention_days > 0),

  archive_before_delete boolean not null default true,
  archive_after_days integer,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  legal_hold_override boolean not null default true,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,policy_code)
);

-- ============================================================
-- 12. LEGAL HOLDS
-- ============================================================

create table if not exists public.audit_legal_holds (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  hold_code text not null,
  hold_name text not null,
  description text,

  status text not null default 'active'
    check (status in ('active','released','expired','archived')),

  applies_to_type text not null
    check (
      applies_to_type in (
        'organization',
        'user',
        'entity',
        'event_type',
        'date_range',
        'custom'
      )
    ),

  user_id uuid references auth.users(id) on delete set null,
  entity_type text,
  entity_id uuid,
  event_type_code text references public.audit_event_types(code) on delete set null,

  starts_at timestamptz not null default now(),
  ends_at timestamptz,

  filter_expression jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  released_by uuid references auth.users(id) on delete set null,
  released_at timestamptz,
  release_notes text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,hold_code)
);

-- ============================================================
-- 13. ARCHIVE QUEUE
-- ============================================================

create table if not exists public.audit_archive_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  target_table text not null,
  record_id uuid not null,

  archive_reason text,
  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'processing',
        'archived',
        'failed',
        'cancelled'
      )
    ),

  scheduled_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  archive_location text,
  archive_reference text,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  completed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists audit_archive_queue_due_idx
  on public.audit_archive_queue (
    status,
    scheduled_at
  )
  where status = 'pending';

-- ============================================================
-- 14. EXPORT JOBS
-- ============================================================

create table if not exists public.audit_export_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  requested_by uuid references auth.users(id) on delete set null,

  export_type text not null
    check (
      export_type in (
        'audit_events',
        'security_events',
        'user_activity',
        'api_activity',
        'compliance_report',
        'custom'
      )
    ),

  format text not null default 'csv'
    check (format in ('csv','json','xlsx','pdf')),

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'processing',
        'completed',
        'failed',
        'cancelled',
        'expired'
      )
    ),

  filter_definition jsonb not null default '{}',

  row_count integer,
  file_path text,
  file_url text,
  checksum text,

  expires_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  started_at timestamptz,
  completed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists audit_export_jobs_queue_idx
  on public.audit_export_jobs (
    status,
    created_at
  )
  where status in ('queued','processing');

-- ============================================================
-- 15. ENGINE LOGS
-- ============================================================

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  audit_event_id uuid references public.audit_events(id) on delete set null,
  security_event_id uuid references public.audit_security_events(id) on delete set null,
  export_job_id uuid references public.audit_export_jobs(id) on delete set null,

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

create index if not exists audit_logs_org_created_idx
  on public.audit_logs (
    organization_id,
    created_at desc
  );

-- ============================================================
-- 16. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'audit_sensitive_fields',
    'audit_user_sessions',
    'audit_security_events',
    'audit_retention_policies',
    'audit_legal_holds',
    'audit_archive_queue',
    'audit_export_jobs'
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
-- 17. JSON DIFF HELPER
-- ============================================================

create or replace function public.audit_jsonb_diff(
  old_data jsonb,
  new_data jsonb
)
returns jsonb
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_object_agg(
      key,
      jsonb_build_object(
        'before',
        old_data -> key,
        'after',
        new_data -> key
      )
    ),
    '{}'::jsonb
  )
  from (
    select key
    from jsonb_object_keys(
      coalesce(old_data,'{}'::jsonb)
      || coalesce(new_data,'{}'::jsonb)
    ) key
    where old_data -> key is distinct from new_data -> key
  ) changed;
$$;

revoke all
on function public.audit_jsonb_diff(jsonb,jsonb)
from public;

grant execute
on function public.audit_jsonb_diff(jsonb,jsonb)
to authenticated,service_role;

-- ============================================================
-- 18. CHANGED FIELDS HELPER
-- ============================================================

create or replace function public.audit_changed_fields(
  old_data jsonb,
  new_data jsonb
)
returns text[]
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    array_agg(key order by key),
    '{}'::text[]
  )
  from (
    select key
    from jsonb_object_keys(
      coalesce(old_data,'{}'::jsonb)
      || coalesce(new_data,'{}'::jsonb)
    ) key
    where old_data -> key is distinct from new_data -> key
  ) changed;
$$;

revoke all
on function public.audit_changed_fields(jsonb,jsonb)
from public;

grant execute
on function public.audit_changed_fields(jsonb,jsonb)
to authenticated,service_role;

-- ============================================================
-- 19. CREATE AUDIT ACTOR
-- ============================================================

create or replace function public.create_audit_actor(
  requested_organization_id uuid default null,
  requested_actor_type text default 'user',
  requested_user_id uuid default auth.uid(),
  requested_external_actor_id text default null,
  requested_display_name text default null,
  requested_email text default null,
  requested_ip_address inet default null,
  requested_user_agent text default null,
  requested_device_id text default null,
  requested_session_id text default null,
  requested_api_key_id text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.audit_actors
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_record public.audit_actors;
begin
  insert into public.audit_actors (
    organization_id,
    actor_type,
    user_id,
    external_actor_id,
    display_name,
    email,
    ip_address,
    user_agent,
    device_id,
    session_id,
    api_key_id,
    metadata
  )
  values (
    requested_organization_id,
    requested_actor_type,
    requested_user_id,
    requested_external_actor_id,
    requested_display_name,
    requested_email,
    requested_ip_address,
    requested_user_agent,
    requested_device_id,
    requested_session_id,
    requested_api_key_id,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into actor_record;

  return actor_record;
end;
$$;

revoke all
on function public.create_audit_actor(
  uuid,text,uuid,text,text,text,inet,text,text,text,text,jsonb
)
from public;

grant execute
on function public.create_audit_actor(
  uuid,text,uuid,text,text,text,inet,text,text,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 20. RECORD AUDIT EVENT
-- ============================================================

create or replace function public.record_audit_event(
  requested_organization_id uuid,
  requested_event_type_code text,
  requested_event_name text,
  requested_source_module text default null,
  requested_source_table text default null,
  requested_source_record_id uuid default null,
  requested_action text default null,
  requested_operation text default null,
  requested_before_data jsonb default null,
  requested_after_data jsonb default null,
  requested_actor_id uuid default null,
  requested_actor_user_id uuid default auth.uid(),
  requested_actor_type text default null,
  requested_request_id text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_session_id text default null,
  requested_ip_address inet default null,
  requested_user_agent text default null,
  requested_device_id text default null,
  requested_context_data jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb,
  requested_occurred_at timestamptz default now()
)
returns public.audit_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  type_record public.audit_event_types;
  event_record public.audit_events;
  changed_fields_value text[];
  diff_value jsonb;
begin
  select *
  into type_record
  from public.audit_event_types
  where code = requested_event_type_code;

  if not found then
    raise exception 'Audit event type not found';
  end if;

  changed_fields_value :=
    public.audit_changed_fields(
      requested_before_data,
      requested_after_data
    );

  diff_value :=
    public.audit_jsonb_diff(
      requested_before_data,
      requested_after_data
    );

  insert into public.audit_events (
    organization_id,
    event_type_code,
    event_name,
    event_group,
    severity,
    actor_id,
    actor_user_id,
    actor_type,
    source_module,
    source_table,
    source_record_id,
    action,
    operation,
    request_id,
    correlation_id,
    trace_id,
    session_id,
    ip_address,
    user_agent,
    device_id,
    before_data,
    after_data,
    changed_fields,
    diff_data,
    context_data,
    metadata,
    is_sensitive,
    occurred_at
  )
  values (
    requested_organization_id,
    type_record.code,
    requested_event_name,
    type_record.event_group,
    type_record.default_severity,
    requested_actor_id,
    requested_actor_user_id,
    coalesce(
      requested_actor_type,
      case
        when auth.role() = 'service_role' then 'service_role'
        when requested_actor_user_id is not null then 'user'
        else 'system'
      end
    ),
    requested_source_module,
    requested_source_table,
    requested_source_record_id,
    requested_action,
    requested_operation,
    requested_request_id,
    requested_correlation_id,
    requested_trace_id,
    requested_session_id,
    requested_ip_address,
    requested_user_agent,
    requested_device_id,
    requested_before_data,
    requested_after_data,
    changed_fields_value,
    diff_value,
    coalesce(requested_context_data,'{}'::jsonb),
    coalesce(requested_metadata,'{}'::jsonb),
    type_record.is_sensitive,
    coalesce(requested_occurred_at,now())
  )
  returning * into event_record;

  if requested_actor_user_id is not null then
    insert into public.audit_user_activities (
      organization_id,
      user_id,
      audit_event_id,
      activity_type,
      activity_title,
      activity_description,
      entity_type,
      entity_id,
      activity_data,
      occurred_at
    )
    values (
      requested_organization_id,
      requested_actor_user_id,
      event_record.id,
      requested_event_type_code,
      requested_event_name,
      requested_action,
      requested_source_table,
      requested_source_record_id,
      jsonb_build_object(
        'source_module',
        requested_source_module,
        'operation',
        requested_operation
      ),
      event_record.occurred_at
    );
  end if;

  return event_record;
end;
$$;

revoke all
on function public.record_audit_event(
  uuid,text,text,text,text,uuid,text,text,jsonb,jsonb,uuid,uuid,text,text,text,text,
  text,inet,text,text,jsonb,jsonb,timestamptz
)
from public;

grant execute
on function public.record_audit_event(
  uuid,text,text,text,text,uuid,text,text,jsonb,jsonb,uuid,uuid,text,text,text,text,
  text,inet,text,text,jsonb,jsonb,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 21. GENERIC ROW AUDIT TRIGGER
-- ============================================================

create or replace function public.audit_row_change_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_value uuid;
  record_id_value uuid;
  before_value jsonb;
  after_value jsonb;
  event_type_value text;
begin
  if tg_op = 'INSERT' then
    before_value := null;
    after_value := to_jsonb(new);
    event_type_value := 'record.created';

    organization_value :=
      nullif(after_value->>'organization_id','')::uuid;

    record_id_value :=
      nullif(after_value->>'id','')::uuid;

  elsif tg_op = 'UPDATE' then
    before_value := to_jsonb(old);
    after_value := to_jsonb(new);
    event_type_value := 'record.updated';

    organization_value :=
      coalesce(
        nullif(after_value->>'organization_id','')::uuid,
        nullif(before_value->>'organization_id','')::uuid
      );

    record_id_value :=
      coalesce(
        nullif(after_value->>'id','')::uuid,
        nullif(before_value->>'id','')::uuid
      );

  elsif tg_op = 'DELETE' then
    before_value := to_jsonb(old);
    after_value := null;
    event_type_value := 'record.deleted';

    organization_value :=
      nullif(before_value->>'organization_id','')::uuid;

    record_id_value :=
      nullif(before_value->>'id','')::uuid;
  end if;

  perform public.record_audit_event(
    organization_value,
    event_type_value,
    tg_table_name || '.' || lower(tg_op),
    tg_table_name,
    tg_table_name,
    record_id_value,
    lower(tg_op),
    lower(tg_op),
    before_value,
    after_value,
    null,
    auth.uid(),
    case
      when auth.role() = 'service_role' then 'service_role'
      else 'user'
    end,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    '{}'::jsonb,
    jsonb_build_object(
      'trigger_name',
      tg_name
    ),
    now()
  );

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

-- ============================================================
-- 22. ATTACH CORE AUDIT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'leads',
    'follow_up_tasks',
    'site_visits',
    'bookings',
    'customers',
    'inventory_units',
    'lead_validation_results',
    'lead_assignments',
    'communication_message_jobs',
    'automation_runs',
    'notification_jobs'
  ]
  loop
    if exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = target_table
    ) then
      execute format(
        'drop trigger if exists %I_audit_row_changes on public.%I',
        target_table,
        target_table
      );

      execute format(
        'create trigger %I_audit_row_changes
         after insert or update or delete
         on public.%I
         for each row
         execute function public.audit_row_change_trigger()',
        target_table,
        target_table
      );
    end if;
  end loop;
end;
$$;

-- ============================================================
-- 23. SESSION REGISTRATION
-- ============================================================

create or replace function public.register_audit_session(
  requested_organization_id uuid,
  requested_user_id uuid,
  requested_session_key text,
  requested_auth_provider text default null,
  requested_auth_method text default null,
  requested_ip_address inet default null,
  requested_user_agent text default null,
  requested_device_id text default null,
  requested_device_type text default null,
  requested_operating_system text default null,
  requested_browser text default null,
  requested_country_code text default null,
  requested_region text default null,
  requested_city text default null,
  requested_timezone text default null,
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.audit_user_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_record public.audit_user_sessions;
begin
  insert into public.audit_user_sessions (
    organization_id,
    user_id,
    session_key,
    auth_provider,
    auth_method,
    status,
    ip_address,
    user_agent,
    device_id,
    device_type,
    operating_system,
    browser,
    country_code,
    region,
    city,
    timezone,
    expires_at,
    metadata
  )
  values (
    requested_organization_id,
    requested_user_id,
    requested_session_key,
    requested_auth_provider,
    requested_auth_method,
    'active',
    requested_ip_address,
    requested_user_agent,
    requested_device_id,
    requested_device_type,
    requested_operating_system,
    requested_browser,
    requested_country_code,
    requested_region,
    requested_city,
    requested_timezone,
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (session_key)
  do update set
    status = 'active',
    last_seen_at = now(),
    ip_address = excluded.ip_address,
    user_agent = excluded.user_agent,
    device_id = excluded.device_id,
    updated_at = now()
  returning * into session_record;

  perform public.record_audit_event(
    requested_organization_id,
    'auth.login.success',
    'User session registered',
    'authentication',
    'audit_user_sessions',
    session_record.id,
    'login',
    'create_session',
    null,
    to_jsonb(session_record),
    null,
    requested_user_id,
    'user',
    null,
    session_record.id::text,
    null,
    requested_session_key,
    requested_ip_address,
    requested_user_agent,
    requested_device_id,
    '{}'::jsonb,
    '{}'::jsonb,
    now()
  );

  return session_record;
end;
$$;

revoke all
on function public.register_audit_session(
  uuid,uuid,text,text,text,inet,text,text,text,text,text,text,text,text,text,
  timestamptz,jsonb
)
from public;

grant execute
on function public.register_audit_session(
  uuid,uuid,text,text,text,inet,text,text,text,text,text,text,text,text,text,
  timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 24. REVOKE SESSION
-- ============================================================

create or replace function public.revoke_audit_session(
  requested_session_id uuid,
  requested_reason text default 'Session revoked'
)
returns public.audit_user_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  session_record public.audit_user_sessions;
begin
  select *
  into session_record
  from public.audit_user_sessions
  where id = requested_session_id
  for update;

  if not found then
    raise exception 'Audit session not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from session_record.user_id
    and not public.has_organization_permission(
      session_record.organization_id,
      'audit.manage_sessions'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.audit_user_sessions
  set
    status = 'revoked',
    ended_at = now(),
    metadata = metadata || jsonb_build_object(
      'revocation_reason',
      requested_reason
    ),
    updated_at = now()
  where id = session_record.id
  returning * into session_record;

  perform public.record_audit_event(
    session_record.organization_id,
    'auth.session.revoked',
    'User session revoked',
    'authentication',
    'audit_user_sessions',
    session_record.id,
    'revoke',
    'update',
    null,
    to_jsonb(session_record),
    null,
    auth.uid(),
    case
      when auth.role() = 'service_role' then 'service_role'
      else 'user'
    end,
    null,
    session_record.id::text,
    null,
    session_record.session_key,
    session_record.ip_address,
    session_record.user_agent,
    session_record.device_id,
    jsonb_build_object(
      'reason',
      requested_reason
    ),
    '{}'::jsonb,
    now()
  );

  return session_record;
end;
$$;

revoke all
on function public.revoke_audit_session(uuid,text)
from public;

grant execute
on function public.revoke_audit_session(uuid,text)
to authenticated,service_role;

-- ============================================================
-- 25. CREATE SECURITY EVENT
-- ============================================================

create or replace function public.create_audit_security_event(
  requested_organization_id uuid,
  requested_security_event_type text,
  requested_title text,
  requested_description text default null,
  requested_severity text default 'warning',
  requested_user_id uuid default null,
  requested_session_id uuid default null,
  requested_ip_address inet default null,
  requested_device_id text default null,
  requested_user_agent text default null,
  requested_detection_source text default null,
  requested_risk_score numeric default 0,
  requested_indicators jsonb default '[]'::jsonb,
  requested_evidence jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.audit_security_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  security_record public.audit_security_events;
  audit_record public.audit_events;
begin
  audit_record := public.record_audit_event(
    requested_organization_id,
    'security.suspicious_activity',
    requested_title,
    'security',
    'audit_security_events',
    null,
    'detect',
    'insert',
    null,
    null,
    null,
    requested_user_id,
    'system',
    null,
    null,
    null,
    null,
    requested_ip_address,
    requested_user_agent,
    requested_device_id,
    jsonb_build_object(
      'risk_score',
      requested_risk_score,
      'indicators',
      requested_indicators
    ),
    requested_metadata,
    now()
  );

  insert into public.audit_security_events (
    organization_id,
    audit_event_id,
    user_id,
    session_id,
    security_event_type,
    severity,
    status,
    title,
    description,
    ip_address,
    device_id,
    user_agent,
    detection_source,
    risk_score,
    indicators,
    evidence,
    metadata
  )
  values (
    requested_organization_id,
    audit_record.id,
    requested_user_id,
    requested_session_id,
    requested_security_event_type,
    requested_severity,
    'open',
    requested_title,
    requested_description,
    requested_ip_address,
    requested_device_id,
    requested_user_agent,
    requested_detection_source,
    requested_risk_score,
    coalesce(requested_indicators,'[]'::jsonb),
    coalesce(requested_evidence,'{}'::jsonb),
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into security_record;

  return security_record;
end;
$$;

revoke all
on function public.create_audit_security_event(
  uuid,text,text,text,text,uuid,uuid,inet,text,text,text,numeric,jsonb,jsonb,jsonb
)
from public;

grant execute
on function public.create_audit_security_event(
  uuid,text,text,text,text,uuid,uuid,inet,text,text,text,numeric,jsonb,jsonb,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 26. RESOLVE SECURITY EVENT
-- ============================================================

create or replace function public.resolve_audit_security_event(
  requested_security_event_id uuid,
  requested_status text,
  requested_resolution_notes text default null
)
returns public.audit_security_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_record public.audit_security_events;
begin
  if requested_status not in (
    'resolved',
    'false_positive',
    'ignored',
    'archived'
  ) then
    raise exception 'Invalid security event resolution status';
  end if;

  select *
  into event_record
  from public.audit_security_events
  where id = requested_security_event_id
  for update;

  if not found then
    raise exception 'Security event not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      event_record.organization_id,
      'audit.resolve_security_event'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.audit_security_events
  set
    status = requested_status,
    resolved_by = auth.uid(),
    resolved_at = now(),
    resolution_notes = requested_resolution_notes,
    updated_at = now()
  where id = event_record.id
  returning * into event_record;

  return event_record;
end;
$$;

revoke all
on function public.resolve_audit_security_event(uuid,text,text)
from public;

grant execute
on function public.resolve_audit_security_event(uuid,text,text)
to authenticated,service_role;

-- ============================================================
-- 27. RETENTION / ARCHIVE PROCESSOR
-- ============================================================

create or replace function public.process_audit_retention(
  requested_organization_id uuid default null,
  requested_limit integer default 5000
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  archived_events integer := 0;
  archived_api integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may process audit retention';
  end if;

  with eligible as (
    select e.id,e.organization_id
    from public.audit_events e
    join public.audit_retention_policies p
      on (
        p.organization_id is null
        or p.organization_id = e.organization_id
      )
     and p.status = 'active'
     and p.target_type in ('audit_events','all')
    where e.occurred_at
      <= now() - make_interval(days => p.retention_days)
      and (
        requested_organization_id is null
        or e.organization_id = requested_organization_id
      )
      and not exists (
        select 1
        from public.audit_legal_holds h
        where h.organization_id = e.organization_id
          and h.status = 'active'
          and (
            h.applies_to_type = 'organization'
            or (
              h.applies_to_type = 'event_type'
              and h.event_type_code = e.event_type_code
            )
            or (
              h.applies_to_type = 'user'
              and h.user_id = e.actor_user_id
            )
            or (
              h.applies_to_type = 'entity'
              and h.entity_type = e.source_table
              and h.entity_id = e.source_record_id
            )
          )
      )
    order by e.occurred_at
    limit greatest(requested_limit,1)
  )
  insert into public.audit_archive_queue (
    organization_id,
    target_table,
    record_id,
    archive_reason,
    status,
    scheduled_at
  )
  select
    eligible.organization_id,
    'audit_events',
    eligible.id,
    'Retention policy',
    'pending',
    now()
  from eligible
  on conflict do nothing;

  get diagnostics archived_events = row_count;

  with eligible as (
    select a.id,a.organization_id
    from public.audit_api_requests a
    join public.audit_retention_policies p
      on (
        p.organization_id is null
        or p.organization_id = a.organization_id
      )
     and p.status = 'active'
     and p.target_type in ('api_requests','all')
    where a.requested_at
      <= now() - make_interval(days => p.retention_days)
      and (
        requested_organization_id is null
        or a.organization_id = requested_organization_id
      )
    order by a.requested_at
    limit greatest(requested_limit,1)
  )
  insert into public.audit_archive_queue (
    organization_id,
    target_table,
    record_id,
    archive_reason,
    status,
    scheduled_at
  )
  select
    eligible.organization_id,
    'audit_api_requests',
    eligible.id,
    'Retention policy',
    'pending',
    now()
  from eligible
  on conflict do nothing;

  get diagnostics archived_api = row_count;

  return jsonb_build_object(
    'audit_events_queued',
    archived_events,
    'api_requests_queued',
    archived_api,
    'processed_at',
    now()
  );
end;
$$;

revoke all
on function public.process_audit_retention(uuid,integer)
from public;

grant execute
on function public.process_audit_retention(uuid,integer)
to service_role;

-- ============================================================
-- 28. ANALYTICS VIEWS
-- ============================================================

create or replace view public.audit_activity_dashboard
with (security_invoker = true)
as
select
  organization_id,
  date_trunc('day',occurred_at)::date as activity_date,
  event_group,
  severity,

  count(*) as total_events,

  count(*) filter (
    where is_sensitive = true
  ) as sensitive_events,

  count(*) filter (
    where actor_user_id is not null
  ) as user_events,

  count(distinct actor_user_id) as unique_users,

  count(*) filter (
    where source_table is not null
  ) as data_events

from public.audit_events
group by
  organization_id,
  date_trunc('day',occurred_at)::date,
  event_group,
  severity;

create or replace view public.audit_security_dashboard
with (security_invoker = true)
as
select
  organization_id,
  date_trunc('day',created_at)::date as security_date,
  severity,
  status,

  count(*) as total_events,

  round(avg(risk_score),2) as average_risk_score,

  max(risk_score) as maximum_risk_score,

  count(*) filter (
    where status = 'open'
  ) as open_events,

  count(*) filter (
    where status = 'resolved'
  ) as resolved_events

from public.audit_security_events
group by
  organization_id,
  date_trunc('day',created_at)::date,
  severity,
  status;

create or replace view public.audit_user_activity_summary
with (security_invoker = true)
as
select
  organization_id,
  user_id,

  count(*) as total_activities,

  count(*) filter (
    where occurred_at >= now() - interval '24 hours'
  ) as activities_24h,

  count(*) filter (
    where occurred_at >= now() - interval '7 days'
  ) as activities_7d,

  min(occurred_at) as first_activity_at,
  max(occurred_at) as latest_activity_at

from public.audit_user_activities
group by
  organization_id,
  user_id;

create or replace view public.audit_api_dashboard
with (security_invoker = true)
as
select
  organization_id,
  date_trunc('day',requested_at)::date as request_date,
  http_method,
  request_path,

  count(*) as total_requests,

  count(*) filter (
    where response_status between 200 and 299
  ) as successful_requests,

  count(*) filter (
    where response_status >= 400
  ) as failed_requests,

  round(avg(duration_ms),2) as average_duration_ms,

  max(duration_ms) as maximum_duration_ms

from public.audit_api_requests
group by
  organization_id,
  date_trunc('day',requested_at)::date,
  http_method,
  request_path;

create or replace view public.audit_session_dashboard
with (security_invoker = true)
as
select
  organization_id,
  user_id,
  status,

  count(*) as session_count,

  count(*) filter (
    where status = 'active'
  ) as active_sessions,

  round(avg(risk_score),2) as average_risk_score,

  max(last_seen_at) as latest_seen_at

from public.audit_user_sessions
group by
  organization_id,
  user_id,
  status;

grant select
on
  public.audit_activity_dashboard,
  public.audit_security_dashboard,
  public.audit_user_activity_summary,
  public.audit_api_dashboard,
  public.audit_session_dashboard
to authenticated,service_role;

-- ============================================================
-- 29. HEALTH CHECK
-- ============================================================

create or replace function public.get_audit_engine_health(
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
        'audit.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',
    requested_organization_id,
    'checked_at',
    now(),

    'events_24h',
    (
      select count(*)
      from public.audit_events e
      where e.occurred_at >= now() - interval '24 hours'
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    ),

    'critical_events_24h',
    (
      select count(*)
      from public.audit_events e
      where e.occurred_at >= now() - interval '24 hours'
        and e.severity = 'critical'
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    ),

    'open_security_events',
    (
      select count(*)
      from public.audit_security_events s
      where s.status in ('open','investigating')
        and (
          requested_organization_id is null
          or s.organization_id = requested_organization_id
        )
    ),

    'active_sessions',
    (
      select count(*)
      from public.audit_user_sessions s
      where s.status = 'active'
        and (
          requested_organization_id is null
          or s.organization_id = requested_organization_id
        )
    ),

    'pending_archive_items',
    (
      select count(*)
      from public.audit_archive_queue q
      where q.status = 'pending'
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'queued_exports',
    (
      select count(*)
      from public.audit_export_jobs j
      where j.status in ('queued','processing')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'active_legal_holds',
    (
      select count(*)
      from public.audit_legal_holds h
      where h.status = 'active'
        and (
          requested_organization_id is null
          or h.organization_id = requested_organization_id
        )
    )
  );
end;
$$;

revoke all
on function public.get_audit_engine_health(uuid)
from public;

grant execute
on function public.get_audit_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 30. IMMUTABILITY GUARD
-- ============================================================

create or replace function public.prevent_audit_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() = 'service_role'
    and current_setting(
      'app.audit_allow_mutation',
      true
    ) = 'on' then
    if tg_op = 'DELETE' then
      return old;
    end if;

    return new;
  end if;

  raise exception
    'Audit events are immutable';
end;
$$;

drop trigger if exists audit_events_immutable_guard
on public.audit_events;

create trigger audit_events_immutable_guard
before update or delete
on public.audit_events
for each row
execute function public.prevent_audit_event_mutation();

-- ============================================================
-- 31. RLS
-- ============================================================

alter table public.audit_event_types enable row level security;
alter table public.audit_actors enable row level security;
alter table public.audit_events enable row level security;
alter table public.audit_sensitive_fields enable row level security;
alter table public.audit_user_activities enable row level security;
alter table public.audit_user_sessions enable row level security;
alter table public.audit_security_events enable row level security;
alter table public.audit_api_requests enable row level security;
alter table public.audit_integration_events enable row level security;
alter table public.audit_retention_policies enable row level security;
alter table public.audit_legal_holds enable row level security;
alter table public.audit_archive_queue enable row level security;
alter table public.audit_export_jobs enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists audit_event_types_authenticated_select
on public.audit_event_types;

create policy audit_event_types_authenticated_select
on public.audit_event_types
for select
to authenticated
using (true);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'audit_actors',
    'audit_events',
    'audit_sensitive_fields',
    'audit_user_activities',
    'audit_user_sessions',
    'audit_security_events',
    'audit_api_requests',
    'audit_integration_events',
    'audit_retention_policies',
    'audit_legal_holds',
    'audit_archive_queue',
    'audit_export_jobs',
    'audit_logs'
  ]
  loop
    execute format(
      'drop policy if exists %I_select_policy on public.%I',
      target_table,
      target_table
    );

    execute format(
      'create policy %I_select_policy
       on public.%I
       for select
       to authenticated
       using (
         public.has_organization_permission(
           organization_id,
           ''audit.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''audit.view_all''
         )
       )',
      target_table,
      target_table
    );

    execute format(
      'drop policy if exists %I_service_policy on public.%I',
      target_table,
      target_table
    );

    execute format(
      'create policy %I_service_policy
       on public.%I
       for all
       to service_role
       using (true)
       with check (true)',
      target_table,
      target_table
    );
  end loop;
end;
$$;

drop policy if exists audit_user_sessions_self_select
on public.audit_user_sessions;

create policy audit_user_sessions_self_select
on public.audit_user_sessions
for select
to authenticated
using (
  auth.uid() = user_id
  or public.has_organization_permission(
    organization_id,
    'audit.view_all'
  )
);

drop policy if exists audit_retention_policies_write
on public.audit_retention_policies;

create policy audit_retention_policies_write
on public.audit_retention_policies
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'audit.manage_retention'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'audit.manage_retention'
  )
);

drop policy if exists audit_legal_holds_write
on public.audit_legal_holds;

create policy audit_legal_holds_write
on public.audit_legal_holds
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'audit.manage_legal_hold'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'audit.manage_legal_hold'
  )
);

-- ============================================================
-- 32. GRANTS
-- ============================================================

grant select
on
  public.audit_event_types,
  public.audit_actors,
  public.audit_events,
  public.audit_sensitive_fields,
  public.audit_user_activities,
  public.audit_user_sessions,
  public.audit_security_events,
  public.audit_api_requests,
  public.audit_integration_events,
  public.audit_retention_policies,
  public.audit_legal_holds,
  public.audit_archive_queue,
  public.audit_export_jobs,
  public.audit_logs
to authenticated;

grant insert,update,delete
on
  public.audit_sensitive_fields,
  public.audit_retention_policies,
  public.audit_legal_holds
to authenticated;

grant all
on
  public.audit_event_types,
  public.audit_actors,
  public.audit_events,
  public.audit_sensitive_fields,
  public.audit_user_activities,
  public.audit_user_sessions,
  public.audit_security_events,
  public.audit_api_requests,
  public.audit_integration_events,
  public.audit_retention_policies,
  public.audit_legal_holds,
  public.audit_archive_queue,
  public.audit_export_jobs,
  public.audit_logs
to service_role;

-- ============================================================
-- 33. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'audit_event_types',
    'audit_actors',
    'audit_events',
    'audit_sensitive_fields',
    'audit_user_activities',
    'audit_user_sessions',
    'audit_security_events',
    'audit_api_requests',
    'audit_integration_events',
    'audit_retention_policies',
    'audit_legal_holds',
    'audit_archive_queue',
    'audit_export_jobs',
    'audit_logs'
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
    'audit_jsonb_diff',
    'audit_changed_fields',
    'create_audit_actor',
    'record_audit_event',
    'register_audit_session',
    'revoke_audit_session',
    'create_audit_security_event',
    'resolve_audit_security_event',
    'process_audit_retention',
    'get_audit_engine_health'
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
      '016 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 34. MIGRATION AUDIT
-- ============================================================

insert into public.audit_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.016.completed',
  'Audit & Activity Engine migration 016 completed',
  jsonb_build_object(
    'migration',
    '016_audit_activity_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'event_types',
      'actors',
      'immutable_audit_events',
      'sensitive_fields',
      'user_activity',
      'sessions',
      'security_events',
      'api_audit',
      'integration_audit',
      'retention',
      'legal_holds',
      'archive_queue',
      'exports',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.audit_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.016.completed'
);

commit;