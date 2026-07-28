-- ============================================================
-- SalesSetu Enterprise
-- Migration 024: Mobile App Engine
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
--   012_assignment_engine.sql
--   013_communication_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--   018_Document_Management_Engine.sql
--   021_Administration_Engine.sql
--   023_Integration_API_Engine.sql
--
-- Scope:
--   • Mobile devices, sessions and app installations
--   • Push notification token registry
--   • Offline sync queue and sync checkpoints
--   • Conflict detection and resolution
--   • Media upload queue
--   • Mobile app versions and forced update policy
--   • Device security, lost-device blocking and trust state
--   • GPS, field attendance and route tracking
--   • Background jobs, app events and diagnostics
--   • Mobile analytics, event outbox and health checks
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
    ('mobile_app','view','mobile_app.view','View mobile app data'),
    ('mobile_app','view_all','mobile_app.view_all','View all organization mobile app data'),
    ('mobile_app','manage_devices','mobile_app.manage_devices','Manage mobile devices'),
    ('mobile_app','manage_sessions','mobile_app.manage_sessions','Manage mobile sessions'),
    ('mobile_app','manage_push','mobile_app.manage_push','Manage push tokens'),
    ('mobile_app','manage_sync','mobile_app.manage_sync','Manage mobile synchronization'),
    ('mobile_app','manage_conflicts','mobile_app.manage_conflicts','Manage mobile sync conflicts'),
    ('mobile_app','manage_versions','mobile_app.manage_versions','Manage mobile app versions'),
    ('mobile_app','manage_security','mobile_app.manage_security','Manage mobile device security'),
    ('mobile_app','manage_tracking','mobile_app.manage_tracking','Manage location and field tracking'),
    ('mobile_app','manage_uploads','mobile_app.manage_uploads','Manage mobile uploads'),
    ('mobile_app','view_logs','mobile_app.view_logs','View mobile app logs'),
    ('mobile_app','view_analytics','mobile_app.view_analytics','View mobile analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. APP INSTALLATIONS
-- ============================================================

create table if not exists public.mobile_app_installations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,

  installation_id text not null,
  platform text not null
    check (platform in ('android','ios','web_mobile')),

  app_version text,
  build_number text,
  device_model text,
  manufacturer text,
  operating_system text,
  os_version text,

  locale text default 'en-IN',
  timezone text default 'Asia/Kolkata',

  status text not null default 'active'
    check (status in ('active','inactive','blocked','lost','retired')),

  first_installed_at timestamptz not null default now(),
  last_opened_at timestamptz,
  last_seen_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,installation_id)
);

create index if not exists mobile_app_installations_user_idx
  on public.mobile_app_installations (
    organization_id,
    user_id,
    status
  );

-- ============================================================
-- 3. MOBILE DEVICES
-- ============================================================

create table if not exists public.mobile_devices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  installation_id uuid not null references public.mobile_app_installations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,

  device_fingerprint text,
  device_name text,
  device_model text,
  platform text not null,
  os_version text,

  trust_status text not null default 'unverified'
    check (trust_status in ('unverified','trusted','restricted','blocked')),

  security_status text not null default 'unknown'
    check (security_status in ('unknown','secure','rooted','jailbroken','compromised')),

  biometric_enabled boolean not null default false,
  pin_enabled boolean not null default false,

  last_ip_address inet,
  last_user_agent text,
  last_location jsonb not null default '{}',

  last_seen_at timestamptz,
  blocked_at timestamptz,
  blocked_reason text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,installation_id)
);

-- ============================================================
-- 4. MOBILE SESSIONS
-- ============================================================

create table if not exists public.mobile_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  installation_id uuid not null references public.mobile_app_installations(id) on delete cascade,
  device_id uuid not null references public.mobile_devices(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,

  session_key text not null,
  refresh_token_reference text,

  status text not null default 'active'
    check (status in ('active','expired','revoked','logged_out','blocked')),

  ip_address inet,
  user_agent text,

  started_at timestamptz not null default now(),
  last_activity_at timestamptz not null default now(),
  expires_at timestamptz,
  ended_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (session_key)
);

create index if not exists mobile_sessions_active_idx
  on public.mobile_sessions (
    organization_id,
    user_id,
    status,
    last_activity_at desc
  );

-- ============================================================
-- 5. PUSH TOKENS
-- ============================================================

create table if not exists public.mobile_push_tokens (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  installation_id uuid not null references public.mobile_app_installations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,

  provider text not null
    check (provider in ('fcm','apns','web_push')),

  token_hash text not null,
  token_reference text,
  token_prefix text,

  status text not null default 'active'
    check (status in ('active','inactive','invalid','expired','revoked')),

  app_version text,
  platform text,

  last_used_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  failure_count integer not null default 0,

  expires_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (token_hash)
);

-- ============================================================
-- 6. APP VERSION MANAGEMENT
-- ============================================================

create table if not exists public.mobile_app_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  platform text not null
    check (platform in ('android','ios','web_mobile')),

  version_name text not null,
  build_number text not null,

  release_status text not null default 'draft'
    check (release_status in ('draft','testing','released','deprecated','blocked')),

  minimum_supported_version text,
  forced_update boolean not null default false,

  release_notes text,
  download_url text,

  released_at timestamptz,
  deprecated_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,platform,version_name,build_number)
);

-- ============================================================
-- 7. MOBILE PREFERENCES
-- ============================================================

create table if not exists public.mobile_user_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  language text not null default 'en',
  theme text not null default 'system'
    check (theme in ('system','light','dark')),

  biometric_login boolean not null default false,
  auto_sync boolean not null default true,
  sync_on_mobile_data boolean not null default true,
  background_location boolean not null default false,

  push_notifications boolean not null default true,
  lead_notifications boolean not null default true,
  followup_notifications boolean not null default true,
  site_visit_notifications boolean not null default true,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,user_id)
);

-- ============================================================
-- 8. OFFLINE SYNC QUEUE
-- ============================================================

create table if not exists public.mobile_sync_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  installation_id uuid references public.mobile_app_installations(id) on delete cascade,

  entity_type text not null,
  entity_id uuid,
  local_id text,

  operation text not null
    check (operation in ('create','update','delete','upsert')),

  payload jsonb not null default '{}',
  base_version text,
  local_version text,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'syncing',
        'synced',
        'conflict',
        'failed',
        'cancelled'
      )
    ),

  priority integer not null default 100,

  attempts integer not null default 0,
  maximum_attempts integer not null default 10,

  scheduled_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  synced_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists mobile_sync_queue_worker_idx
  on public.mobile_sync_queue (
    status,
    scheduled_at,
    priority,
    created_at
  )
  where status in ('pending','failed');

-- ============================================================
-- 9. SYNC CHECKPOINTS
-- ============================================================

create table if not exists public.mobile_sync_checkpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  installation_id uuid not null references public.mobile_app_installations(id) on delete cascade,

  entity_type text not null,

  server_cursor text,
  last_server_updated_at timestamptz,
  last_sync_started_at timestamptz,
  last_sync_completed_at timestamptz,

  sync_status text not null default 'idle'
    check (sync_status in ('idle','syncing','completed','failed','conflict')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (installation_id,entity_type)
);

-- ============================================================
-- 10. SYNC CONFLICTS
-- ============================================================

create table if not exists public.mobile_sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sync_queue_id uuid references public.mobile_sync_queue(id) on delete set null,

  entity_type text not null,
  entity_id uuid,
  local_id text,

  conflict_type text not null
    check (
      conflict_type in (
        'version_mismatch',
        'deleted_on_server',
        'duplicate',
        'validation',
        'permission',
        'custom'
      )
    ),

  local_payload jsonb not null default '{}',
  server_payload jsonb not null default '{}',

  resolution_strategy text
    check (
      resolution_strategy is null
      or resolution_strategy in (
        'local_wins',
        'server_wins',
        'merge',
        'manual',
        'discard'
      )
    ),

  status text not null default 'open'
    check (status in ('open','resolved','ignored','cancelled')),

  resolved_payload jsonb,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,

  notes text,
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 11. MEDIA UPLOAD QUEUE
-- ============================================================

create table if not exists public.mobile_media_uploads (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  installation_id uuid references public.mobile_app_installations(id) on delete cascade,

  entity_type text,
  entity_id uuid,

  file_name text not null,
  mime_type text,
  file_size_bytes bigint,

  local_reference text,
  storage_bucket text,
  storage_path text,

  checksum text,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'uploading',
        'uploaded',
        'processing',
        'completed',
        'failed',
        'cancelled'
      )
    ),

  upload_progress numeric(8,4) not null default 0
    check (upload_progress between 0 and 100),

  document_id uuid references public.documents(id) on delete set null,

  attempts integer not null default 0,
  maximum_attempts integer not null default 5,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 12. LOCATION TRACKING
-- ============================================================

create table if not exists public.mobile_location_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  installation_id uuid references public.mobile_app_installations(id) on delete cascade,

  event_type text not null
    check (
      event_type in (
        'check_in',
        'check_out',
        'location_ping',
        'site_arrival',
        'site_departure',
        'route_point'
      )
    ),

  latitude numeric(10,7) not null,
  longitude numeric(10,7) not null,
  accuracy_meters numeric(10,2),

  altitude_meters numeric(10,2),
  speed_mps numeric(10,2),
  heading_degrees numeric(10,2),

  recorded_at timestamptz not null,
  received_at timestamptz not null default now(),

  related_entity_type text,
  related_entity_id uuid,

  source text not null default 'gps'
    check (source in ('gps','network','manual','geofence')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

create index if not exists mobile_location_events_user_time_idx
  on public.mobile_location_events (
    organization_id,
    user_id,
    recorded_at desc
  );

-- ============================================================
-- 13. FIELD ATTENDANCE
-- ============================================================

create table if not exists public.mobile_field_attendance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  employee_id uuid references public.admin_employees(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,

  attendance_date date not null,

  check_in_at timestamptz,
  check_out_at timestamptz,

  check_in_location jsonb not null default '{}',
  check_out_location jsonb not null default '{}',

  attendance_status text not null default 'present'
    check (
      attendance_status in (
        'present',
        'absent',
        'late',
        'half_day',
        'leave',
        'holiday',
        'week_off'
      )
    ),

  total_minutes integer,
  distance_meters numeric(18,2),

  verified boolean not null default false,
  verified_by uuid references auth.users(id) on delete set null,
  verified_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,user_id,attendance_date)
);

-- ============================================================
-- 14. BACKGROUND JOBS
-- ============================================================

create table if not exists public.mobile_background_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  installation_id uuid references public.mobile_app_installations(id) on delete cascade,

  job_type text not null
    check (
      job_type in (
        'sync',
        'upload',
        'download',
        'location',
        'notification_refresh',
        'cache_cleanup',
        'diagnostics',
        'custom'
      )
    ),

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'running',
        'completed',
        'failed',
        'cancelled'
      )
    ),

  scheduled_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,

  input_data jsonb not null default '{}',
  result_data jsonb not null default '{}',

  error_code text,
  error_message text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 15. MOBILE APP EVENTS AND LOGS
-- ============================================================

create table if not exists public.mobile_app_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  installation_id uuid references public.mobile_app_installations(id) on delete set null,

  event_name text not null,
  screen_name text,
  action_name text,

  event_data jsonb not null default '{}',

  occurred_at timestamptz not null default now(),

  app_version text,
  platform text,

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now()
);

create index if not exists mobile_app_events_org_time_idx
  on public.mobile_app_events (
    organization_id,
    occurred_at desc
  );

create table if not exists public.mobile_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  installation_id uuid references public.mobile_app_installations(id) on delete set null,
  device_id uuid references public.mobile_devices(id) on delete set null,

  log_level text not null default 'info'
    check (log_level in ('debug','info','warning','error','critical')),

  event_name text,
  message text,

  error_code text,
  error_message text,
  stack_trace text,

  log_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now()
);

-- ============================================================
-- 16. MOBILE EVENT OUTBOX
-- ============================================================

create table if not exists public.mobile_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  installation_id uuid references public.mobile_app_installations(id) on delete set null,

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

  delivery_attempts integer not null default 0,
  maximum_attempts integer not null default 10,

  delivered_at timestamptz,

  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists mobile_event_outbox_idempotency_idx
  on public.mobile_event_outbox (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

-- ============================================================
-- 17. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'mobile_app_installations',
    'mobile_devices',
    'mobile_sessions',
    'mobile_push_tokens',
    'mobile_app_versions',
    'mobile_user_preferences',
    'mobile_sync_queue',
    'mobile_sync_checkpoints',
    'mobile_sync_conflicts',
    'mobile_media_uploads',
    'mobile_field_attendance',
    'mobile_background_jobs',
    'mobile_event_outbox'
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
-- 18. REGISTER INSTALLATION
-- ============================================================

create or replace function public.register_mobile_installation(
  requested_organization_id uuid,
  requested_installation_id text,
  requested_platform text,
  requested_app_version text default null,
  requested_build_number text default null,
  requested_device_model text default null,
  requested_manufacturer text default null,
  requested_operating_system text default null,
  requested_os_version text default null,
  requested_locale text default 'en-IN',
  requested_timezone text default 'Asia/Kolkata',
  requested_metadata jsonb default '{}'::jsonb
)
returns public.mobile_app_installations
language plpgsql
security definer
set search_path = ''
as $$
declare
  installation_record public.mobile_app_installations;
begin
  insert into public.mobile_app_installations (
    organization_id,
    user_id,
    installation_id,
    platform,
    app_version,
    build_number,
    device_model,
    manufacturer,
    operating_system,
    os_version,
    locale,
    timezone,
    status,
    first_installed_at,
    last_opened_at,
    last_seen_at,
    metadata
  )
  values (
    requested_organization_id,
    auth.uid(),
    requested_installation_id,
    requested_platform,
    requested_app_version,
    requested_build_number,
    requested_device_model,
    requested_manufacturer,
    requested_operating_system,
    requested_os_version,
    requested_locale,
    requested_timezone,
    'active',
    now(),
    now(),
    now(),
    coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (organization_id,installation_id)
  do update set
    user_id = auth.uid(),
    platform = excluded.platform,
    app_version = excluded.app_version,
    build_number = excluded.build_number,
    device_model = excluded.device_model,
    manufacturer = excluded.manufacturer,
    operating_system = excluded.operating_system,
    os_version = excluded.os_version,
    locale = excluded.locale,
    timezone = excluded.timezone,
    status = 'active',
    last_opened_at = now(),
    last_seen_at = now(),
    metadata = excluded.metadata,
    updated_at = now()
  returning * into installation_record;

  return installation_record;
end;
$$;

revoke all
on function public.register_mobile_installation(
  uuid,text,text,text,text,text,text,text,text,text,text,jsonb
)
from public;

grant execute
on function public.register_mobile_installation(
  uuid,text,text,text,text,text,text,text,text,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 19. REGISTER PUSH TOKEN
-- ============================================================

create or replace function public.register_mobile_push_token(
  requested_installation_id uuid,
  requested_provider text,
  requested_raw_token text,
  requested_token_reference text default null,
  requested_app_version text default null,
  requested_platform text default null,
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.mobile_push_tokens
language plpgsql
security definer
set search_path = ''
as $$
declare
  installation_record public.mobile_app_installations;
  token_hash_value text;
  token_record public.mobile_push_tokens;
begin
  select *
  into installation_record
  from public.mobile_app_installations
  where id = requested_installation_id;

  if not found then
    raise exception 'Mobile installation not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from installation_record.user_id then
    raise exception 'Permission denied';
  end if;

  token_hash_value := encode(
    digest(requested_raw_token,'sha256'),
    'hex'
  );

  insert into public.mobile_push_tokens (
    organization_id,
    installation_id,
    user_id,
    provider,
    token_hash,
    token_reference,
    token_prefix,
    status,
    app_version,
    platform,
    expires_at,
    metadata
  )
  values (
    installation_record.organization_id,
    installation_record.id,
    installation_record.user_id,
    requested_provider,
    token_hash_value,
    requested_token_reference,
    left(requested_raw_token,12),
    'active',
    requested_app_version,
    requested_platform,
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (token_hash)
  do update set
    installation_id = excluded.installation_id,
    user_id = excluded.user_id,
    status = 'active',
    app_version = excluded.app_version,
    platform = excluded.platform,
    expires_at = excluded.expires_at,
    updated_at = now()
  returning * into token_record;

  return token_record;
end;
$$;

revoke all
on function public.register_mobile_push_token(
  uuid,text,text,text,text,text,timestamptz,jsonb
)
from public;

grant execute
on function public.register_mobile_push_token(
  uuid,text,text,text,text,text,timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 20. CREATE MOBILE SESSION
-- ============================================================

create or replace function public.create_mobile_session(
  requested_installation_id uuid,
  requested_device_id uuid,
  requested_session_key text,
  requested_ip_address inet default null,
  requested_user_agent text default null,
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.mobile_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  installation_record public.mobile_app_installations;
  device_record public.mobile_devices;
  session_record public.mobile_sessions;
begin
  select *
  into installation_record
  from public.mobile_app_installations
  where id = requested_installation_id
    and status = 'active';

  if not found then
    raise exception 'Active mobile installation not found';
  end if;

  select *
  into device_record
  from public.mobile_devices
  where id = requested_device_id
    and installation_id = requested_installation_id;

  if not found then
    raise exception 'Mobile device not found';
  end if;

  if device_record.trust_status = 'blocked'
    or device_record.security_status in ('rooted','jailbroken','compromised') then
    raise exception 'Device is not allowed';
  end if;

  insert into public.mobile_sessions (
    organization_id,
    installation_id,
    device_id,
    user_id,
    session_key,
    status,
    ip_address,
    user_agent,
    started_at,
    last_activity_at,
    expires_at,
    metadata
  )
  values (
    installation_record.organization_id,
    installation_record.id,
    device_record.id,
    installation_record.user_id,
    requested_session_key,
    'active',
    requested_ip_address,
    requested_user_agent,
    now(),
    now(),
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (session_key)
  do update set
    status = 'active',
    last_activity_at = now(),
    ip_address = excluded.ip_address,
    user_agent = excluded.user_agent,
    expires_at = excluded.expires_at,
    updated_at = now()
  returning * into session_record;

  return session_record;
end;
$$;

revoke all
on function public.create_mobile_session(
  uuid,uuid,text,inet,text,timestamptz,jsonb
)
from public;

grant execute
on function public.create_mobile_session(
  uuid,uuid,text,inet,text,timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 21. ENQUEUE MOBILE SYNC
-- ============================================================

create or replace function public.enqueue_mobile_sync(
  requested_organization_id uuid,
  requested_installation_id uuid,
  requested_entity_type text,
  requested_operation text,
  requested_payload jsonb,
  requested_entity_id uuid default null,
  requested_local_id text default null,
  requested_base_version text default null,
  requested_local_version text default null,
  requested_priority integer default 100,
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns public.mobile_sync_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  installation_record public.mobile_app_installations;
  queue_record public.mobile_sync_queue;
begin
  select *
  into installation_record
  from public.mobile_app_installations
  where id = requested_installation_id
    and organization_id = requested_organization_id
    and status = 'active';

  if not found then
    raise exception 'Active installation not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from installation_record.user_id then
    raise exception 'Permission denied';
  end if;

  insert into public.mobile_sync_queue (
    organization_id,
    user_id,
    installation_id,
    entity_type,
    entity_id,
    local_id,
    operation,
    payload,
    base_version,
    local_version,
    status,
    priority,
    correlation_id,
    trace_id
  )
  values (
    requested_organization_id,
    installation_record.user_id,
    installation_record.id,
    requested_entity_type,
    requested_entity_id,
    requested_local_id,
    requested_operation,
    coalesce(requested_payload,'{}'::jsonb),
    requested_base_version,
    requested_local_version,
    'pending',
    requested_priority,
    requested_correlation_id,
    requested_trace_id
  )
  returning * into queue_record;

  return queue_record;
end;
$$;

revoke all
on function public.enqueue_mobile_sync(
  uuid,uuid,text,text,jsonb,uuid,text,text,text,integer,text,text
)
from public;

grant execute
on function public.enqueue_mobile_sync(
  uuid,uuid,text,text,jsonb,uuid,text,text,text,integer,text,text
)
to authenticated,service_role;

-- ============================================================
-- 22. CLAIM MOBILE SYNC
-- ============================================================

create or replace function public.claim_mobile_sync(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.mobile_sync_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  queue_record public.mobile_sync_queue;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim mobile sync jobs';
  end if;

  select *
  into queue_record
  from public.mobile_sync_queue q
  where q.status in ('pending','failed')
    and q.scheduled_at <= now()
    and q.attempts < q.maximum_attempts
    and (
      requested_organization_id is null
      or q.organization_id = requested_organization_id
    )
  order by q.priority,q.scheduled_at,q.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.mobile_sync_queue
  set
    status = 'claimed',
    attempts = attempts + 1,
    claimed_at = now(),
    claimed_by = requested_worker_id,
    lock_token = gen_random_uuid()::text,
    lock_expires_at = now() + make_interval(
      secs => greatest(requested_lock_seconds,1)
    ),
    updated_at = now()
  where id = queue_record.id
  returning * into queue_record;

  return queue_record;
end;
$$;

revoke all
on function public.claim_mobile_sync(text,uuid,integer)
from public;

grant execute
on function public.claim_mobile_sync(text,uuid,integer)
to service_role;

-- ============================================================
-- 23. COMPLETE MOBILE SYNC
-- ============================================================

create or replace function public.complete_mobile_sync(
  requested_sync_id uuid,
  requested_lock_token text,
  requested_server_entity_id uuid default null,
  requested_server_version text default null,
  requested_result_data jsonb default '{}'::jsonb
)
returns public.mobile_sync_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  queue_record public.mobile_sync_queue;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete mobile sync jobs';
  end if;

  select *
  into queue_record
  from public.mobile_sync_queue
  where id = requested_sync_id
  for update;

  if not found then
    raise exception 'Mobile sync job not found';
  end if;

  if queue_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid mobile sync lock token';
  end if;

  update public.mobile_sync_queue
  set
    status = 'synced',
    entity_id = coalesce(requested_server_entity_id,entity_id),
    synced_at = now(),
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    error_code = null,
    error_message = null,
    error_data = coalesce(requested_result_data,'{}'::jsonb),
    updated_at = now()
  where id = requested_sync_id
  returning * into queue_record;

  return queue_record;
end;
$$;

revoke all
on function public.complete_mobile_sync(
  uuid,text,uuid,text,jsonb
)
from public;

grant execute
on function public.complete_mobile_sync(
  uuid,text,uuid,text,jsonb
)
to service_role;

-- ============================================================
-- 24. RESOLVE MOBILE CONFLICT
-- ============================================================

create or replace function public.resolve_mobile_sync_conflict(
  requested_conflict_id uuid,
  requested_resolution_strategy text,
  requested_resolved_payload jsonb default null,
  requested_notes text default null
)
returns public.mobile_sync_conflicts
language plpgsql
security definer
set search_path = ''
as $$
declare
  conflict_record public.mobile_sync_conflicts;
begin
  select *
  into conflict_record
  from public.mobile_sync_conflicts
  where id = requested_conflict_id
  for update;

  if not found then
    raise exception 'Mobile sync conflict not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      conflict_record.organization_id,
      'mobile_app.manage_conflicts'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.mobile_sync_conflicts
  set
    resolution_strategy = requested_resolution_strategy,
    status = 'resolved',
    resolved_payload = requested_resolved_payload,
    resolved_by = auth.uid(),
    resolved_at = now(),
    notes = requested_notes,
    updated_at = now()
  where id = requested_conflict_id
  returning * into conflict_record;

  if conflict_record.sync_queue_id is not null then
    update public.mobile_sync_queue
    set
      status = case
        when requested_resolution_strategy = 'discard' then 'cancelled'
        else 'pending'
      end,
      payload = case
        when requested_resolved_payload is not null
          then requested_resolved_payload
        else payload
      end,
      scheduled_at = now(),
      updated_at = now()
    where id = conflict_record.sync_queue_id;
  end if;

  return conflict_record;
end;
$$;

revoke all
on function public.resolve_mobile_sync_conflict(
  uuid,text,jsonb,text
)
from public;

grant execute
on function public.resolve_mobile_sync_conflict(
  uuid,text,jsonb,text
)
to authenticated,service_role;

-- ============================================================
-- 25. APP UPDATE STATUS
-- ============================================================

create or replace function public.get_mobile_app_update_status(
  requested_organization_id uuid,
  requested_platform text,
  requested_version_name text,
  requested_build_number text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  latest_record public.mobile_app_versions;
begin
  select *
  into latest_record
  from public.mobile_app_versions v
  where v.platform = requested_platform
    and v.release_status = 'released'
    and (
      v.organization_id = requested_organization_id
      or v.organization_id is null
    )
  order by
    case when v.organization_id = requested_organization_id then 0 else 1 end,
    v.released_at desc nulls last,
    v.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'update_available',false,
      'forced_update',false
    );
  end if;

  return jsonb_build_object(
    'update_available',
      requested_version_name is distinct from latest_record.version_name
      or requested_build_number is distinct from latest_record.build_number,
    'forced_update',
      latest_record.forced_update
      and (
        requested_version_name is distinct from latest_record.version_name
        or requested_build_number is distinct from latest_record.build_number
      ),
    'latest_version',latest_record.version_name,
    'latest_build',latest_record.build_number,
    'minimum_supported_version',latest_record.minimum_supported_version,
    'release_notes',latest_record.release_notes,
    'download_url',latest_record.download_url
  );
end;
$$;

revoke all
on function public.get_mobile_app_update_status(
  uuid,text,text,text
)
from public;

grant execute
on function public.get_mobile_app_update_status(
  uuid,text,text,text
)
to anon,authenticated,service_role;

-- ============================================================
-- 26. BLOCK MOBILE DEVICE
-- ============================================================

create or replace function public.block_mobile_device(
  requested_device_id uuid,
  requested_reason text
)
returns public.mobile_devices
language plpgsql
security definer
set search_path = ''
as $$
declare
  device_record public.mobile_devices;
begin
  select *
  into device_record
  from public.mobile_devices
  where id = requested_device_id
  for update;

  if not found then
    raise exception 'Mobile device not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      device_record.organization_id,
      'mobile_app.manage_security'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.mobile_devices
  set
    trust_status = 'blocked',
    blocked_at = now(),
    blocked_reason = requested_reason,
    updated_at = now()
  where id = requested_device_id
  returning * into device_record;

  update public.mobile_sessions
  set
    status = 'blocked',
    ended_at = now(),
    updated_at = now()
  where device_id = requested_device_id
    and status = 'active';

  update public.mobile_app_installations
  set
    status = 'blocked',
    updated_at = now()
  where id = device_record.installation_id;

  return device_record;
end;
$$;

revoke all
on function public.block_mobile_device(uuid,text)
from public;

grant execute
on function public.block_mobile_device(uuid,text)
to authenticated,service_role;

-- ============================================================
-- 27. PUBLISH MOBILE EVENT
-- ============================================================

create or replace function public.publish_mobile_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_user_id uuid default null,
  requested_installation_id uuid default null,
  requested_source_type text default null,
  requested_source_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.mobile_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.mobile_event_outbox;
  created_event public.mobile_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.mobile_event_outbox e
    where e.organization_id is not distinct from requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.mobile_event_outbox (
    organization_id,
    user_id,
    installation_id,
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
    requested_user_id,
    requested_installation_id,
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
on function public.publish_mobile_event(
  uuid,text,jsonb,text,uuid,uuid,text,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_mobile_event(
  uuid,text,jsonb,text,uuid,uuid,text,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 28. ANALYTICS VIEWS
-- ============================================================

create or replace view public.mobile_device_dashboard
with (security_invoker = true)
as
select
  organization_id,
  platform,
  status,

  count(*) as installation_count,

  count(*) filter (
    where last_seen_at >= now() - interval '30 days'
  ) as active_30_days,

  count(*) filter (
    where status = 'blocked'
  ) as blocked_installations,

  max(last_seen_at) as latest_seen_at

from public.mobile_app_installations
group by organization_id,platform,status;

create or replace view public.mobile_sync_dashboard
with (security_invoker = true)
as
select
  organization_id,
  entity_type,
  status,

  count(*) as sync_count,
  coalesce(sum(attempts),0) as total_attempts,

  count(*) filter (
    where status = 'synced'
  ) as synced_count,

  count(*) filter (
    where status = 'failed'
  ) as failed_count,

  count(*) filter (
    where status = 'conflict'
  ) as conflict_count,

  max(synced_at) as latest_sync_at

from public.mobile_sync_queue
group by organization_id,entity_type,status;

create or replace view public.mobile_attendance_dashboard
with (security_invoker = true)
as
select
  organization_id,
  attendance_date,
  attendance_status,

  count(*) as attendance_count,

  count(*) filter (
    where verified = true
  ) as verified_count,

  round(avg(total_minutes),2) as average_minutes,
  round(avg(distance_meters),2) as average_distance_meters

from public.mobile_field_attendance
group by organization_id,attendance_date,attendance_status;

create or replace view public.mobile_engagement_dashboard
with (security_invoker = true)
as
select
  organization_id,
  event_name,

  count(*) as event_count,
  count(distinct user_id) as unique_users,
  count(distinct installation_id) as unique_installations,

  min(occurred_at) as first_event_at,
  max(occurred_at) as latest_event_at

from public.mobile_app_events
group by organization_id,event_name;

grant select
on
  public.mobile_device_dashboard,
  public.mobile_sync_dashboard,
  public.mobile_attendance_dashboard,
  public.mobile_engagement_dashboard
to authenticated,service_role;

-- ============================================================
-- 29. HEALTH CHECK
-- ============================================================

create or replace function public.get_mobile_app_engine_health(
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
        'mobile_app.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'active_installations',(
      select count(*)
      from public.mobile_app_installations i
      where i.status = 'active'
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'blocked_devices',(
      select count(*)
      from public.mobile_devices d
      where d.trust_status = 'blocked'
        and (
          requested_organization_id is null
          or d.organization_id = requested_organization_id
        )
    ),

    'active_sessions',(
      select count(*)
      from public.mobile_sessions s
      where s.status = 'active'
        and (
          requested_organization_id is null
          or s.organization_id = requested_organization_id
        )
    ),

    'invalid_push_tokens',(
      select count(*)
      from public.mobile_push_tokens p
      where p.status in ('invalid','expired','revoked')
        and (
          requested_organization_id is null
          or p.organization_id = requested_organization_id
        )
    ),

    'pending_sync_jobs',(
      select count(*)
      from public.mobile_sync_queue q
      where q.status in ('pending','claimed','syncing','failed')
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'open_conflicts',(
      select count(*)
      from public.mobile_sync_conflicts c
      where c.status = 'open'
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'pending_uploads',(
      select count(*)
      from public.mobile_media_uploads u
      where u.status in ('pending','uploading','processing','failed')
        and (
          requested_organization_id is null
          or u.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.mobile_event_outbox e
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
on function public.get_mobile_app_engine_health(uuid)
from public;

grant execute
on function public.get_mobile_app_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 30. RLS
-- ============================================================

alter table public.mobile_app_installations enable row level security;
alter table public.mobile_devices enable row level security;
alter table public.mobile_sessions enable row level security;
alter table public.mobile_push_tokens enable row level security;
alter table public.mobile_app_versions enable row level security;
alter table public.mobile_user_preferences enable row level security;
alter table public.mobile_sync_queue enable row level security;
alter table public.mobile_sync_checkpoints enable row level security;
alter table public.mobile_sync_conflicts enable row level security;
alter table public.mobile_media_uploads enable row level security;
alter table public.mobile_location_events enable row level security;
alter table public.mobile_field_attendance enable row level security;
alter table public.mobile_background_jobs enable row level security;
alter table public.mobile_app_events enable row level security;
alter table public.mobile_logs enable row level security;
alter table public.mobile_event_outbox enable row level security;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'mobile_app_installations',
    'mobile_devices',
    'mobile_sessions',
    'mobile_push_tokens',
    'mobile_user_preferences',
    'mobile_sync_queue',
    'mobile_sync_checkpoints',
    'mobile_media_uploads',
    'mobile_location_events',
    'mobile_field_attendance',
    'mobile_background_jobs',
    'mobile_app_events'
  ]
  loop
    execute format(
      'drop policy if exists %I_self_select_policy on public.%I',
      target_table,
      target_table
    );

    execute format(
      'create policy %I_self_select_policy
       on public.%I
       for select
       to authenticated
       using (
         user_id = auth.uid()
         or public.has_organization_permission(
           organization_id,
           ''mobile_app.view_all''
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

drop policy if exists mobile_app_versions_select_policy
on public.mobile_app_versions;

create policy mobile_app_versions_select_policy
on public.mobile_app_versions
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'mobile_app.view'
  )
  or public.has_organization_permission(
    organization_id,
    'mobile_app.view_all'
  )
);

drop policy if exists mobile_app_versions_service_policy
on public.mobile_app_versions;

create policy mobile_app_versions_service_policy
on public.mobile_app_versions
for all
to service_role
using (true)
with check (true);

drop policy if exists mobile_sync_conflicts_select_policy
on public.mobile_sync_conflicts;

create policy mobile_sync_conflicts_select_policy
on public.mobile_sync_conflicts
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'mobile_app.manage_conflicts'
  )
  or public.has_organization_permission(
    organization_id,
    'mobile_app.view_all'
  )
);

drop policy if exists mobile_sync_conflicts_service_policy
on public.mobile_sync_conflicts;

create policy mobile_sync_conflicts_service_policy
on public.mobile_sync_conflicts
for all
to service_role
using (true)
with check (true);

drop policy if exists mobile_logs_select_policy
on public.mobile_logs;

create policy mobile_logs_select_policy
on public.mobile_logs
for select
to authenticated
using (
  user_id = auth.uid()
  or public.has_organization_permission(
    organization_id,
    'mobile_app.view_logs'
  )
);

drop policy if exists mobile_logs_service_policy
on public.mobile_logs;

create policy mobile_logs_service_policy
on public.mobile_logs
for all
to service_role
using (true)
with check (true);

drop policy if exists mobile_event_outbox_select_policy
on public.mobile_event_outbox;

create policy mobile_event_outbox_select_policy
on public.mobile_event_outbox
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'mobile_app.view_logs'
  )
);

drop policy if exists mobile_event_outbox_service_policy
on public.mobile_event_outbox;

create policy mobile_event_outbox_service_policy
on public.mobile_event_outbox
for all
to service_role
using (true)
with check (true);

-- ============================================================
-- 31. GRANTS
-- ============================================================

grant select
on
  public.mobile_app_installations,
  public.mobile_devices,
  public.mobile_sessions,
  public.mobile_push_tokens,
  public.mobile_app_versions,
  public.mobile_user_preferences,
  public.mobile_sync_queue,
  public.mobile_sync_checkpoints,
  public.mobile_sync_conflicts,
  public.mobile_media_uploads,
  public.mobile_location_events,
  public.mobile_field_attendance,
  public.mobile_background_jobs,
  public.mobile_app_events,
  public.mobile_logs,
  public.mobile_event_outbox
to authenticated;

grant insert,update
on
  public.mobile_app_installations,
  public.mobile_devices,
  public.mobile_sessions,
  public.mobile_push_tokens,
  public.mobile_user_preferences,
  public.mobile_sync_queue,
  public.mobile_sync_checkpoints,
  public.mobile_media_uploads,
  public.mobile_location_events,
  public.mobile_field_attendance,
  public.mobile_background_jobs,
  public.mobile_app_events
to authenticated;

grant all
on
  public.mobile_app_installations,
  public.mobile_devices,
  public.mobile_sessions,
  public.mobile_push_tokens,
  public.mobile_app_versions,
  public.mobile_user_preferences,
  public.mobile_sync_queue,
  public.mobile_sync_checkpoints,
  public.mobile_sync_conflicts,
  public.mobile_media_uploads,
  public.mobile_location_events,
  public.mobile_field_attendance,
  public.mobile_background_jobs,
  public.mobile_app_events,
  public.mobile_logs,
  public.mobile_event_outbox
to service_role;

-- ============================================================
-- 32. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'mobile_app_installations',
    'mobile_devices',
    'mobile_sessions',
    'mobile_push_tokens',
    'mobile_app_versions',
    'mobile_user_preferences',
    'mobile_sync_queue',
    'mobile_sync_checkpoints',
    'mobile_sync_conflicts',
    'mobile_media_uploads',
    'mobile_location_events',
    'mobile_field_attendance',
    'mobile_background_jobs',
    'mobile_app_events',
    'mobile_logs',
    'mobile_event_outbox'
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
    'register_mobile_installation',
    'register_mobile_push_token',
    'create_mobile_session',
    'enqueue_mobile_sync',
    'claim_mobile_sync',
    'complete_mobile_sync',
    'resolve_mobile_sync_conflict',
    'get_mobile_app_update_status',
    'block_mobile_device',
    'publish_mobile_event',
    'get_mobile_app_engine_health'
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
      '024 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 33. MIGRATION AUDIT
-- ============================================================

insert into public.mobile_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.024.completed',
  'Mobile App Engine migration 024 completed',
  jsonb_build_object(
    'migration',
    '024_mobile_app_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'installations',
      'devices',
      'sessions',
      'push_tokens',
      'app_versions',
      'preferences',
      'offline_sync',
      'sync_checkpoints',
      'conflicts',
      'media_uploads',
      'location_tracking',
      'field_attendance',
      'background_jobs',
      'events',
      'analytics',
      'event_outbox'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.mobile_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.024.completed'
);

commit;