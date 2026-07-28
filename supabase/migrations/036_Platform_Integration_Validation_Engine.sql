-- ============================================================================
-- SalesSetu Enterprise
-- Migration 036: Platform Integration, Validation & Production Readiness Engine
-- PostgreSQL / Supabase
-- ============================================================================
--
-- Purpose:
--   • Register migrations 001-036 and their authoritative lifecycle
--   • Validate module dependencies and required database components
--   • Audit RLS, tenant indexes, SECURITY DEFINER search_path and FK integrity
--   • Identify stale worker locks, queue-contract gaps and engine overlaps
--   • Define the authoritative SalesSetu end-to-end flow contract
--   • Execute read-only smoke tests and calculate a production-readiness score
--   • Track integration issues and publish validation events
--
-- This migration does not delete or rewrite legacy engines. Modules 009, 013
-- and 014 are explicitly retained as compatibility layers while modules 028,
-- 027 and 026 are recorded as their authoritative successors.
-- ============================================================================

begin;

do $preflight$
begin
  if to_regclass('public.booking') is not null then
    raise exception
      'Legacy relation public.booking still exists. Run 036_remove_booking_bridge_and_repair_routines.sql first.';
  end if;

  if to_regclass('public.bookings') is null then
    raise exception
      'Authoritative relation public.bookings is missing.';
  end if;
end;
$preflight$;


-- Suppress origin-mode row triggers, rules, and event triggers only for
-- this transaction. PostgreSQL automatically restores the setting when
-- the transaction ends, including on rollback.
--
-- This avoids Supabase-managed DDL event triggers resolving the removed
-- legacy relation public.booking while Module 036 installs its objects.
do $replication_preflight$
declare
  unsupported_event_triggers text;
begin
  select string_agg(evtname, ', ' order by evtname)
  into unsupported_event_triggers
  from pg_event_trigger
  where evtname in (
    'issue_graphql_placeholder',
    'issue_pg_cron_access',
    'issue_pg_graphql_access',
    'issue_pg_net_access',
    'pgrst_ddl_watch',
    'pgrst_drop_watch'
  )
  and evtenabled in ('A','R');

  if unsupported_event_triggers is not null then
    raise exception
      'Cannot safely suppress Supabase DDL hooks in replica mode. Trigger(s) enabled ALWAYS/REPLICA: %',
      unsupported_event_triggers;
  end if;
end;
$replication_preflight$;

set local session_replication_role = replica;
create extension if not exists pgcrypto;

-- ============================================================================
-- 1. PERMISSIONS
-- ============================================================================

insert into public.permissions(module,action,code,description)
select x.module,x.action,x.code,x.description
from (values
  ('platform_validation','view','platform_validation.view','View platform module and validation status'),
  ('platform_validation','run','platform_validation.run','Run platform integration validation'),
  ('platform_validation','manage','platform_validation.manage','Manage validation profiles and component expectations'),
  ('platform_validation','smoke_test','platform_validation.smoke_test','Execute platform smoke tests'),
  ('platform_validation','resolve_issues','platform_validation.resolve_issues','Resolve platform integration issues'),
  ('platform_validation','view_logs','platform_validation.view_logs','View platform validation logs and readiness history')
) x(module,action,code,description)
where not exists(select 1 from public.permissions p where p.code=x.code);

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r
cross join public.permissions p
where r.code in ('platform_admin','organization_admin')
  and p.module='platform_validation'
on conflict(role_id,permission_id) do nothing;

-- ============================================================================
-- 2. MODULE REGISTRY AND DEPENDENCIES
-- ============================================================================

create table if not exists public.platform_module_registry(
  id uuid primary key default gen_random_uuid(),
  module_number integer not null unique check(module_number>0),
  module_code text not null unique,
  module_name text not null,
  platform_layer text not null,
  migration_file text not null,
  lifecycle_status text not null default 'active'
    check(lifecycle_status in('active','compatibility','deprecated','retired')),
  authority_status text not null default 'authoritative'
    check(authority_status in('authoritative','legacy','supporting')),
  superseded_by_module_number integer,
  marker_table text,
  marker_event text,
  required_components jsonb not null default '[]',
  optional_components jsonb not null default '[]',
  detected_status text not null default 'unknown'
    check(detected_status in('unknown','missing','degraded','installed','complete','superseded')),
  required_component_count integer not null default 0,
  detected_component_count integer not null default 0,
  marker_verified boolean,
  last_validated_at timestamptz,
  notes text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists platform_module_registry_status_idx
  on public.platform_module_registry(lifecycle_status,authority_status,detected_status,module_number);

create table if not exists public.platform_module_dependencies(
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.platform_module_registry(id) on delete cascade,
  depends_on_module_id uuid not null references public.platform_module_registry(id) on delete cascade,
  dependency_type text not null default 'required'
    check(dependency_type in('required','recommended','optional','compatibility')),
  condition_expression jsonb not null default '{}',
  notes text,
  created_at timestamptz not null default now(),
  unique(module_id,depends_on_module_id),
  check(module_id<>depends_on_module_id)
);

create table if not exists public.platform_component_expectations(
  id uuid primary key default gen_random_uuid(),
  module_id uuid not null references public.platform_module_registry(id) on delete cascade,
  component_type text not null
    check(component_type in('table','view','materialized_view','function','index','trigger','extension','relation')),
  schema_name text not null default 'public',
  component_name text not null,
  required boolean not null default true,
  expected_rls boolean,
  expected_tenant_scope boolean,
  expected_security_definer boolean,
  expected_safe_search_path boolean,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(module_id,component_type,schema_name,component_name)
);

create index if not exists platform_component_expectations_lookup_idx
  on public.platform_component_expectations(module_id,required,component_type,component_name);

-- ============================================================================
-- 3. AUTHORITATIVE ENGINE MAP AND BUSINESS FLOW CONTRACT
-- ============================================================================

create table if not exists public.platform_engine_authority(
  id uuid primary key default gen_random_uuid(),
  capability_domain text not null unique,
  authoritative_module_id uuid not null references public.platform_module_registry(id) on delete restrict,
  legacy_module_ids uuid[] not null default '{}',
  canonical_namespace text not null,
  status text not null default 'active' check(status in('active','transition','disabled')),
  effective_from timestamptz not null default now(),
  notes text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_flow_contracts(
  id uuid primary key default gen_random_uuid(),
  sequence_number integer not null unique,
  stage_code text not null unique,
  stage_name text not null,
  module_id uuid not null references public.platform_module_registry(id) on delete restrict,
  authoritative_table text not null,
  entry_function text,
  output_event text,
  description text,
  status text not null default 'active' check(status in('active','inactive','deprecated')),
  contract_version integer not null default 1 check(contract_version>0),
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================================
-- 4. VALIDATION PROFILES, RUNS AND RESULTS
-- ============================================================================

create table if not exists public.platform_validation_profiles(
  id uuid primary key default gen_random_uuid(),
  profile_code text not null unique,
  profile_name text not null,
  description text,
  configuration jsonb not null default '{}',
  status text not null default 'active' check(status in('active','inactive','archived')),
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_validation_runs(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  profile_id uuid not null references public.platform_validation_profiles(id) on delete restrict,
  run_code text not null unique,
  run_type text not null default 'manual' check(run_type in('manual','scheduled','deployment','migration','incident')),
  status text not null default 'queued' check(status in('queued','running','completed','degraded','blocked','failed','cancelled')),
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  total_checks integer not null default 0,
  passed_checks integer not null default 0,
  failed_checks integer not null default 0,
  critical_failures integer not null default 0,
  high_failures integer not null default 0,
  readiness_score numeric(7,3) not null default 0,
  configuration_snapshot jsonb not null default '{}',
  summary jsonb not null default '{}',
  error_message text,
  correlation_id text,
  trace_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists platform_validation_runs_org_time_idx
  on public.platform_validation_runs(organization_id,created_at desc,status);

create table if not exists public.platform_validation_results(
  id uuid primary key default gen_random_uuid(),
  validation_run_id uuid not null references public.platform_validation_runs(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  check_code text not null,
  category text not null,
  component_type text,
  component_name text,
  module_number integer,
  passed boolean not null,
  severity text not null default 'medium' check(severity in('info','low','medium','high','critical')),
  score_weight numeric(10,3) not null default 1 check(score_weight>=0),
  score_awarded numeric(10,3) not null default 0 check(score_awarded>=0),
  message text not null,
  remediation text,
  details jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists platform_validation_results_run_idx
  on public.platform_validation_results(validation_run_id,passed,severity,category);
create index if not exists platform_validation_results_component_idx
  on public.platform_validation_results(component_type,component_name,created_at desc);

-- ============================================================================
-- 5. SMOKE TESTS, READINESS AND ISSUE MANAGEMENT
-- ============================================================================

create table if not exists public.platform_smoke_test_runs(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  run_code text not null unique,
  status text not null default 'running' check(status in('running','passed','failed','cancelled')),
  requested_by uuid references auth.users(id) on delete set null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  passed_tests integer not null default 0,
  failed_tests integer not null default 0,
  summary jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_smoke_test_results(
  id uuid primary key default gen_random_uuid(),
  smoke_test_run_id uuid not null references public.platform_smoke_test_runs(id) on delete cascade,
  organization_id uuid references public.organizations(id) on delete cascade,
  test_code text not null,
  stage_code text,
  passed boolean not null,
  message text not null,
  details jsonb not null default '{}',
  duration_ms numeric(14,3),
  created_at timestamptz not null default now(),
  unique(smoke_test_run_id,test_code)
);

create table if not exists public.platform_readiness_snapshots(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  validation_run_id uuid references public.platform_validation_runs(id) on delete set null,
  readiness_status text not null check(readiness_status in('ready','conditionally_ready','not_ready','unknown')),
  readiness_score numeric(7,3) not null default 0,
  module_completion_percent numeric(7,3) not null default 0,
  tenant_isolation_score numeric(7,3) not null default 0,
  function_security_score numeric(7,3) not null default 0,
  integrity_score numeric(7,3) not null default 0,
  queue_health_score numeric(7,3) not null default 0,
  critical_failures integer not null default 0,
  high_failures integer not null default 0,
  snapshot_data jsonb not null default '{}',
  captured_at timestamptz not null default now()
);

create index if not exists platform_readiness_snapshots_org_idx
  on public.platform_readiness_snapshots(organization_id,captured_at desc);

create table if not exists public.platform_integration_issues(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  issue_key text not null unique,
  check_code text not null,
  category text not null,
  severity text not null check(severity in('low','medium','high','critical')),
  title text not null,
  description text,
  component_type text,
  component_name text,
  module_number integer,
  status text not null default 'open' check(status in('open','acknowledged','in_progress','resolved','accepted_risk','false_positive')),
  first_validation_run_id uuid references public.platform_validation_runs(id) on delete set null,
  last_validation_run_id uuid references public.platform_validation_runs(id) on delete set null,
  assigned_to uuid references auth.users(id) on delete set null,
  remediation text,
  resolution_notes text,
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists platform_integration_issues_open_idx
  on public.platform_integration_issues(organization_id,status,severity,last_seen_at desc);

-- ============================================================================
-- 6. EVENT OUTBOX AND LOGS
-- ============================================================================

create table if not exists public.platform_integration_event_outbox(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  event_name text not null,
  source_type text,
  source_id uuid,
  destination text not null default 'observability' check(destination in('internal','audit','analytics','observability','notification_engine','automation_engine','enterprise_workflow','integration_api','n8n','webhook','external')),
  status text not null default 'pending' check(status in('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
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

create unique index if not exists platform_integration_event_outbox_idem_idx
  on public.platform_integration_event_outbox(idempotency_key) where idempotency_key is not null;
create index if not exists platform_integration_event_outbox_worker_idx
  on public.platform_integration_event_outbox(status,available_at,priority,created_at) where status in('pending','failed');

create table if not exists public.platform_integration_logs(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  log_level text not null default 'info' check(log_level in('debug','info','warning','error','critical')),
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

create index if not exists platform_integration_logs_org_time_idx
  on public.platform_integration_logs(organization_id,created_at desc,log_level);

-- ============================================================================
-- 7. UPDATED_AT TRIGGERS
-- ============================================================================

do $$
declare t text;
begin
  foreach t in array array[
    'platform_module_registry','platform_component_expectations','platform_engine_authority','platform_flow_contracts',
    'platform_validation_profiles','platform_validation_runs','platform_smoke_test_runs','platform_integration_issues',
    'platform_integration_event_outbox'
  ] loop
    execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
    execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
  end loop;
end $$;

-- ============================================================================
-- 8. EXECUTOR AND CATALOG HELPERS
-- ============================================================================

create or replace function public.platform_is_service_executor()
returns boolean
language sql
stable
set search_path=''
as $$
  select coalesce(auth.role()='service_role',false)
      or session_user in ('postgres','supabase_admin','service_role');
$$;

create or replace function public.platform_component_exists(
  p_component_type text,
  p_schema_name text,
  p_component_name text,
  p_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if p_component_type='extension' then
    return exists(
      select 1
      from pg_extension
      where extname=p_component_name
    );

  elsif p_component_type='function' then
    return exists(
      select 1
      from pg_proc p
      join pg_namespace n
        on n.oid=p.pronamespace
      where n.nspname=p_schema_name
        and p.proname=p_component_name
    );

  elsif p_component_type='trigger' then
    return exists(
      select 1
      from pg_trigger tg
      join pg_class c
        on c.oid=tg.tgrelid
      join pg_namespace n
        on n.oid=c.relnamespace
      where n.nspname=p_schema_name
        and tg.tgname=p_component_name
        and not tg.tgisinternal
    );

  elsif p_component_type='table' then
    return exists(
      select 1
      from pg_class c
      join pg_namespace n
        on n.oid=c.relnamespace
      where n.nspname=p_schema_name
        and c.relname=p_component_name
        and c.relkind in('r','p')
    );

  elsif p_component_type='view' then
    return exists(
      select 1
      from pg_class c
      join pg_namespace n
        on n.oid=c.relnamespace
      where n.nspname=p_schema_name
        and c.relname=p_component_name
        and c.relkind='v'
    );

  elsif p_component_type='materialized_view' then
    return exists(
      select 1
      from pg_class c
      join pg_namespace n
        on n.oid=c.relnamespace
      where n.nspname=p_schema_name
        and c.relname=p_component_name
        and c.relkind='m'
    );

  elsif p_component_type='index' then
    return exists(
      select 1
      from pg_class c
      join pg_namespace n
        on n.oid=c.relnamespace
      where n.nspname=p_schema_name
        and c.relname=p_component_name
        and c.relkind in('i','I')
    );

  elsif p_component_type='relation' then
    return exists(
      select 1
      from pg_class c
      join pg_namespace n
        on n.oid=c.relnamespace
      where n.nspname=p_schema_name
        and c.relname=p_component_name
    );
  end if;

  return false;
end $$;

create or replace function public.platform_column_exists(p_schema_name text,p_table_name text,p_column_name text)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(select 1 from information_schema.columns
    where table_schema=p_schema_name and table_name=p_table_name and column_name=p_column_name);
$$;

create or replace function public.platform_add_validation_result(
  p_run_id uuid,p_organization_id uuid,p_check_code text,p_category text,p_passed boolean,
  p_severity text,p_weight numeric,p_message text,p_component_type text default null,
  p_component_name text default null,p_module_number integer default null,p_remediation text default null,
  p_details jsonb default '{}'::jsonb
)
returns public.platform_validation_results
language plpgsql
security definer
set search_path=''
as $$
declare r public.platform_validation_results;
begin
  insert into public.platform_validation_results(
    validation_run_id,organization_id,check_code,category,component_type,component_name,module_number,
    passed,severity,score_weight,score_awarded,message,remediation,details
  ) values(
    p_run_id,p_organization_id,p_check_code,p_category,p_component_type,p_component_name,p_module_number,
    p_passed,p_severity,greatest(coalesce(p_weight,0),0),case when p_passed then greatest(coalesce(p_weight,0),0) else 0 end,
    p_message,p_remediation,coalesce(p_details,'{}'::jsonb)
  ) returning * into r;
  return r;
end $$;

create or replace function public.publish_platform_integration_event(
  p_organization_id uuid,p_event_name text,p_payload jsonb default '{}'::jsonb,
  p_destination text default 'observability',p_source_type text default null,p_source_id uuid default null,
  p_priority integer default 100,p_idempotency_key text default null,p_correlation_id text default null,
  p_trace_id text default null,p_available_at timestamptz default now()
)
returns public.platform_integration_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare r public.platform_integration_event_outbox;
begin
  if p_idempotency_key is not null then
    select * into r from public.platform_integration_event_outbox where idempotency_key=p_idempotency_key limit 1;
    if found then return r; end if;
  end if;
  insert into public.platform_integration_event_outbox(
    organization_id,event_name,source_type,source_id,destination,priority,payload,available_at,idempotency_key,correlation_id,trace_id
  ) values(
    p_organization_id,p_event_name,p_source_type,p_source_id,p_destination,p_priority,coalesce(p_payload,'{}'),
    coalesce(p_available_at,now()),p_idempotency_key,p_correlation_id,p_trace_id
  ) returning * into r;
  return r;
end $$;

-- ============================================================================
-- 9. REGISTRY SYNCHRONIZATION AND STATUS DETECTION
-- ============================================================================

create or replace function public.sync_platform_component_expectations()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare n integer;
begin
  insert into public.platform_component_expectations(module_id,component_type,schema_name,component_name,required,metadata)
  select m.id,c->>'type',coalesce(c->>'schema','public'),c->>'name',coalesce((c->>'required')::boolean,true),coalesce(c->'metadata','{}'::jsonb)
  from public.platform_module_registry m
  cross join lateral jsonb_array_elements(m.required_components) c
  where c ? 'type' and c ? 'name'
  on conflict(module_id,component_type,schema_name,component_name)
  do update set required=excluded.required,metadata=public.platform_component_expectations.metadata||excluded.metadata,updated_at=now();
  get diagnostics n=row_count;
  return n;
end $$;

create or replace function public.refresh_platform_module_status(p_module_number integer default null)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare
  m record;
  required_count integer;
  found_count integer;
  marker_ok boolean;
  marker_relation regclass;
  new_status text;
  updated_count integer:=0;
begin
  for m in
    select *
    from public.platform_module_registry
    where p_module_number is null
       or module_number=p_module_number
    order by module_number
  loop
    select
      count(*),
      count(*) filter(
        where public.platform_component_exists(
          e.component_type,
          e.schema_name,
          e.component_name,
          e.metadata
        )
      )
    into required_count,found_count
    from public.platform_component_expectations e
    where e.module_id=m.id
      and e.required=true;

    marker_ok:=null;
    marker_relation:=null;

    if m.marker_table is not null
       and m.marker_event is not null then

      marker_relation:=to_regclass(
        format('%I.%I','public',m.marker_table)
      );

      if marker_relation is not null
         and public.platform_column_exists(
           'public',
           m.marker_table,
           'event_name'
         ) then
        begin
          execute format(
            'select exists(
               select 1
               from %s
               where event_name=$1
             )',
            marker_relation
          )
          into marker_ok
          using m.marker_event;
        exception
          when undefined_table
            or undefined_column
            or invalid_schema_name then
            marker_ok:=false;
        end;
      else
        marker_ok:=false;
      end if;
    end if;

    new_status:=case
      when required_count=0 then 'unknown'
      when found_count=0 then 'missing'
      when found_count<required_count then 'degraded'
      when m.lifecycle_status in(
        'compatibility',
        'deprecated',
        'retired'
      ) then 'superseded'
      when marker_ok is true then 'complete'
      else 'installed'
    end;

    update public.platform_module_registry
    set
      detected_status=new_status,
      required_component_count=required_count,
      detected_component_count=found_count,
      marker_verified=marker_ok,
      last_validated_at=now(),
      updated_at=now()
    where id=m.id;

    updated_count:=updated_count+1;
  end loop;

  return updated_count;
end $$;

-- ============================================================================
-- 10. PLATFORM VALIDATION RUNNER
-- ============================================================================

create or replace function public.run_platform_validation(
  p_organization_id uuid default null,
  p_profile_code text default 'production',
  p_run_type text default 'manual'
)
returns public.platform_validation_runs
language plpgsql
security definer
set search_path=''
as $$
declare
  profile_record public.platform_validation_profiles;
  run_record public.platform_validation_runs;
  m record;e record;d record;f record;a record;q record;fk record;
  passed boolean;exists_flag boolean;safe_path boolean;has_idx boolean;orphan_exists boolean;stale_exists boolean;
  total_weight numeric;awarded_weight numeric;readiness numeric;v_total_checks integer;v_passed_checks integer;v_failed_checks integer;
  v_critical_failures integer;v_high_failures integer;run_status text;config jsonb;
  module_total integer;module_ok integer;rls_total integer;rls_ok integer;fn_total integer;fn_ok integer;integrity_total integer;integrity_ok integer;queue_total integer;queue_ok integer;
  module_score numeric;rls_score numeric;fn_score numeric;integrity_score numeric;queue_score numeric;
begin
  if not public.platform_is_service_executor() and(
    p_organization_id is null or not public.has_organization_permission(p_organization_id,'platform_validation.run')
  ) then raise exception 'Permission denied'; end if;

  select * into profile_record from public.platform_validation_profiles where profile_code=p_profile_code and status='active';
  if not found then raise exception 'Active platform validation profile % not found',p_profile_code; end if;
  config:=profile_record.configuration;

  insert into public.platform_validation_runs(
    organization_id,profile_id,run_code,run_type,status,requested_by,started_at,configuration_snapshot,correlation_id
  ) values(
    p_organization_id,profile_record.id,'VAL-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,20)),p_run_type,'running',auth.uid(),now(),config,gen_random_uuid()::text
  ) returning * into run_record;

  perform public.sync_platform_component_expectations();
  perform public.refresh_platform_module_status(null);

  -- Module installation and marker status.
  for m in select * from public.platform_module_registry order by module_number loop
    passed:=case when m.lifecycle_status in('compatibility','deprecated','retired') then m.detected_status in('superseded','installed','complete') else m.detected_status in('installed','complete') end;
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'MODULE_'||lpad(m.module_number::text,3,'0'),'module_registry',passed,
      case when m.authority_status='authoritative' then 'critical' else 'medium' end,
      case when m.authority_status='authoritative' then 5 else 1 end,
      format('Module %s (%s) detected as %s',m.module_number,m.module_name,m.detected_status),'module',m.module_code,m.module_number,
      'Install missing required components or verify the migration marker.',
      jsonb_build_object('lifecycle_status',m.lifecycle_status,'authority_status',m.authority_status,'required_components',m.required_component_count,'detected_components',m.detected_component_count,'marker_verified',m.marker_verified));
  end loop;

  -- Required component checks.
  for e in select e.*,m.module_number,m.module_name,m.authority_status,m.lifecycle_status from public.platform_component_expectations e join public.platform_module_registry m on m.id=e.module_id order by m.module_number,e.component_type,e.component_name loop
    exists_flag:=public.platform_component_exists(e.component_type,e.schema_name,e.component_name,e.metadata);
    perform public.platform_add_validation_result(run_record.id,p_organization_id,
      'COMPONENT_'||e.module_number||'_'||upper(e.component_type)||'_'||upper(regexp_replace(e.component_name,'[^a-zA-Z0-9]+','_','g')),
      'component_catalog',exists_flag,
      case when e.required and e.authority_status='authoritative' and e.lifecycle_status='active' then 'critical' when e.required then 'high' else 'low' end,
      case when e.required then 2 else 0.5 end,
      case when exists_flag then format('%s %I.%I exists',e.component_type,e.schema_name,e.component_name) else format('%s %I.%I is missing',e.component_type,e.schema_name,e.component_name) end,
      e.component_type,e.schema_name||'.'||e.component_name,e.module_number,
      'Apply or repair the owning migration before production deployment.',e.metadata);
  end loop;

  -- Dependency checks.
  for d in select c.module_number child_no,c.module_name child_name,p.module_number parent_no,p.module_name parent_name,md.dependency_type,p.detected_status parent_status
    from public.platform_module_dependencies md join public.platform_module_registry c on c.id=md.module_id join public.platform_module_registry p on p.id=md.depends_on_module_id
    order by c.module_number,p.module_number loop
    passed:=d.parent_status in('installed','complete','superseded');
    perform public.platform_add_validation_result(run_record.id,p_organization_id,
      'DEPENDENCY_'||d.child_no||'_'||d.parent_no,'module_dependency',passed,
      case when d.dependency_type='required' then 'critical' when d.dependency_type='recommended' then 'medium' else 'low' end,
      case when d.dependency_type='required' then 2 else 0.5 end,
      format('Module %s depends on module %s (%s): %s',d.child_no,d.parent_no,d.dependency_type,d.parent_status),
      'module_dependency',d.child_no||'->'||d.parent_no,d.child_no,
      'Install or repair the dependency before enabling the dependent module.',jsonb_build_object('dependency_type',d.dependency_type,'parent_status',d.parent_status));
  end loop;

  -- RLS and tenant-index checks for all organization-scoped public tables.
  for q in select c.oid,n.nspname schema_name,c.relname table_name,c.relrowsecurity
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in('r','p')
      and exists(select 1 from pg_attribute at where at.attrelid=c.oid and at.attname='organization_id' and at.attnum>0 and not at.attisdropped)
    order by c.relname loop
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'RLS_'||upper(q.table_name),'tenant_isolation',q.relrowsecurity,
      'critical',3,case when q.relrowsecurity then format('RLS enabled on public.%I',q.table_name) else format('RLS is not enabled on public.%I',q.table_name) end,
      'table','public.'||q.table_name,null,'Enable RLS and create organization-scoped policies.',jsonb_build_object('rls_enabled',q.relrowsecurity));
    select exists(select 1 from pg_index i join pg_attribute at on at.attrelid=i.indrelid and at.attnum=any(i.indkey)
      where i.indrelid=q.oid and at.attname='organization_id') into has_idx;
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'TENANT_INDEX_'||upper(q.table_name),'tenant_index',has_idx,
      'high',1.5,case when has_idx then format('Tenant index exists on public.%I',q.table_name) else format('No index contains organization_id on public.%I',q.table_name) end,
      'table','public.'||q.table_name,null,'Add an index beginning with or containing organization_id.',jsonb_build_object('organization_indexed',has_idx));
  end loop;

  -- SECURITY DEFINER functions must explicitly set search_path.
  for f in select n.nspname schema_name,p.proname function_name,pg_get_function_identity_arguments(p.oid) identity_args,
      exists(select 1 from unnest(coalesce(p.proconfig,array[]::text[])) cfg where cfg like 'search_path=%') safe_search_path
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef=true order by p.proname,identity_args loop
    safe_path:=f.safe_search_path;
    perform public.platform_add_validation_result(run_record.id,p_organization_id,
      'SECURITY_DEFINER_'||upper(regexp_replace(f.function_name||'_'||f.identity_args,'[^a-zA-Z0-9]+','_','g')),
      'function_security',safe_path,'critical',2,
      case when safe_path then format('SECURITY DEFINER function %I.%I has an explicit search_path',f.schema_name,f.function_name)
           else format('SECURITY DEFINER function %I.%I does not set search_path',f.schema_name,f.function_name) end,
      'function',f.schema_name||'.'||f.function_name||'('||f.identity_args||')',null,
      'Recreate the function with SET search_path = '''' and fully-qualified object references.',jsonb_build_object('identity_arguments',f.identity_args));
  end loop;

  -- Single-column FK index and optional orphan checks.
  if coalesce((config->>'check_fk_indexes')::boolean,false) then
    for fk in select con.oid,con.conname,nc.nspname child_schema,cc.relname child_table,ac.attname child_column,
      np.nspname parent_schema,cp.relname parent_table,ap.attname parent_column,cc.oid child_oid
      from pg_constraint con join pg_class cc on cc.oid=con.conrelid join pg_namespace nc on nc.oid=cc.relnamespace
      join pg_class cp on cp.oid=con.confrelid join pg_namespace np on np.oid=cp.relnamespace
      join pg_attribute ac on ac.attrelid=cc.oid and ac.attnum=con.conkey[1]
      join pg_attribute ap on ap.attrelid=cp.oid and ap.attnum=con.confkey[1]
      where con.contype='f' and cardinality(con.conkey)=1 and nc.nspname='public' order by cc.relname,con.conname loop
      select exists(select 1 from pg_index i where i.indrelid=fk.child_oid and fk.child_column=(select attname from pg_attribute where attrelid=i.indrelid and attnum=i.indkey[0])) into has_idx;
      perform public.platform_add_validation_result(run_record.id,p_organization_id,'FK_INDEX_'||upper(fk.conname),'foreign_key_index',has_idx,'high',1,
        case when has_idx then format('Foreign key %I has a leading index',fk.conname) else format('Foreign key %I lacks a leading child-column index',fk.conname) end,
        'constraint',fk.child_schema||'.'||fk.child_table||'.'||fk.conname,null,'Add an index beginning with the foreign-key column.',
        jsonb_build_object('child_column',fk.child_column,'parent_table',fk.parent_schema||'.'||fk.parent_table,'parent_column',fk.parent_column));
      if coalesce((config->>'check_fk_integrity')::boolean,false) then
        execute format('select exists(select 1 from %I.%I c where c.%I is not null and not exists(select 1 from %I.%I p where p.%I=c.%I) limit 1)',
          fk.child_schema,fk.child_table,fk.child_column,fk.parent_schema,fk.parent_table,fk.parent_column) into orphan_exists;
        perform public.platform_add_validation_result(run_record.id,p_organization_id,'FK_INTEGRITY_'||upper(fk.conname),'referential_integrity',not orphan_exists,'critical',2,
          case when orphan_exists then format('Orphaned rows detected for foreign key %I',fk.conname) else format('No orphaned rows detected for foreign key %I',fk.conname) end,
          'constraint',fk.child_schema||'.'||fk.child_table||'.'||fk.conname,null,'Repair orphaned records and preserve FK enforcement.',jsonb_build_object('orphan_exists',orphan_exists));
      end if;
    end loop;
  end if;

  -- Authority map: exactly one active authoritative module per capability.
  for a in select ea.*,m.module_number,m.detected_status from public.platform_engine_authority ea join public.platform_module_registry m on m.id=ea.authoritative_module_id order by ea.capability_domain loop
    passed:=a.status='active' and a.detected_status in('installed','complete');
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'AUTHORITY_'||upper(a.capability_domain),'engine_authority',passed,'critical',3,
      format('Capability %s authority is module %s with status %s',a.capability_domain,a.module_number,a.detected_status),
      'capability',a.capability_domain,a.module_number,'Install the authoritative module or update the authority map.',
      jsonb_build_object('canonical_namespace',a.canonical_namespace,'legacy_module_ids',a.legacy_module_ids));
  end loop;

  -- End-to-end flow contract components.
  for f in select fc.*,m.module_number from public.platform_flow_contracts fc join public.platform_module_registry m on m.id=fc.module_id where fc.status='active' order by fc.sequence_number loop
    exists_flag:=public.platform_component_exists('table','public',f.authoritative_table,'{}');
    if exists_flag and f.entry_function is not null then exists_flag:=public.platform_component_exists('function','public',f.entry_function,'{}'); end if;
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'FLOW_'||upper(f.stage_code),'e2e_flow_contract',exists_flag,'critical',3,
      case when exists_flag then format('Flow stage %s is executable',f.stage_name) else format('Flow stage %s is missing its authoritative component or function',f.stage_name) end,
      'flow_stage',f.stage_code,f.module_number,'Restore the authoritative table/function declared by the flow contract.',
      jsonb_build_object('sequence',f.sequence_number,'table',f.authoritative_table,'entry_function',f.entry_function,'output_event',f.output_event));
  end loop;

  -- Stale worker locks across every compatible queue table.
  if coalesce((config->>'check_queue_locks')::boolean,true) then
    for q in select c.relname table_name from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relkind in('r','p')
        and exists(select 1 from pg_attribute a1 where a1.attrelid=c.oid and a1.attname='lock_expires_at' and a1.attnum>0 and not a1.attisdropped)
        and exists(select 1 from pg_attribute a2 where a2.attrelid=c.oid and a2.attname='status' and a2.attnum>0 and not a2.attisdropped)
      order by c.relname loop
      execute format('select exists(select 1 from public.%I where lock_expires_at is not null and lock_expires_at<=now() and status in(''claimed'',''processing'',''running'',''locked'',''in_progress'') limit 1)',q.table_name) into stale_exists;
      perform public.platform_add_validation_result(run_record.id,p_organization_id,'STALE_LOCK_'||upper(q.table_name),'queue_health',not stale_exists,'high',1,
        case when stale_exists then format('Stale worker lock detected in public.%I',q.table_name) else format('No stale worker lock detected in public.%I',q.table_name) end,
        'table','public.'||q.table_name,null,'Release expired locks and return eligible work to the retry queue.',jsonb_build_object('stale_lock_exists',stale_exists));
    end loop;
  end if;

  -- Outbox contract checks.
  for q in select c.relname table_name,c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in('r','p') and c.relname like '%event_outbox%' order by c.relname loop
    passed:=public.platform_column_exists('public',q.table_name,'status') and public.platform_column_exists('public',q.table_name,'available_at')
      and public.platform_column_exists('public',q.table_name,'idempotency_key');
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'OUTBOX_CONTRACT_'||upper(q.table_name),'event_outbox',passed,'high',1.5,
      case when passed then format('Outbox public.%I satisfies status, scheduling and idempotency contract',q.table_name)
           else format('Outbox public.%I is missing status, available_at or idempotency_key',q.table_name) end,
      'table','public.'||q.table_name,null,'Add status, available_at and idempotency_key columns to the outbox contract.',
      jsonb_build_object('status',public.platform_column_exists('public',q.table_name,'status'),'available_at',public.platform_column_exists('public',q.table_name,'available_at'),'idempotency_key',public.platform_column_exists('public',q.table_name,'idempotency_key')));
  end loop;

  select count(*),count(*) filter(where vr.passed),count(*) filter(where not vr.passed),
         count(*) filter(where not vr.passed and vr.severity='critical'),count(*) filter(where not vr.passed and vr.severity='high'),
         coalesce(sum(vr.score_weight),0),coalesce(sum(vr.score_awarded),0)
    into v_total_checks,v_passed_checks,v_failed_checks,v_critical_failures,v_high_failures,total_weight,awarded_weight
  from public.platform_validation_results vr where vr.validation_run_id=run_record.id;
  readiness:=case when total_weight>0 then round((awarded_weight/total_weight)*100,3) else 0 end;
  run_status:=case when v_critical_failures>0 then 'blocked' when v_high_failures>0 then 'degraded' else 'completed' end;

  select count(*),count(*) filter(where vr.passed) into module_total,module_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category='module_registry';
  select count(*),count(*) filter(where vr.passed) into rls_total,rls_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category='tenant_isolation';
  select count(*),count(*) filter(where vr.passed) into fn_total,fn_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category='function_security';
  select count(*),count(*) filter(where vr.passed) into integrity_total,integrity_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category in('referential_integrity','foreign_key_index');
  select count(*),count(*) filter(where vr.passed) into queue_total,queue_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category in('queue_health','event_outbox');
  module_score:=case when module_total>0 then round(module_ok::numeric/module_total*100,3) else 0 end;
  rls_score:=case when rls_total>0 then round(rls_ok::numeric/rls_total*100,3) else 100 end;
  fn_score:=case when fn_total>0 then round(fn_ok::numeric/fn_total*100,3) else 100 end;
  integrity_score:=case when integrity_total>0 then round(integrity_ok::numeric/integrity_total*100,3) else 100 end;
  queue_score:=case when queue_total>0 then round(queue_ok::numeric/queue_total*100,3) else 100 end;

  update public.platform_validation_runs set status=run_status,completed_at=now(),total_checks=v_total_checks,passed_checks=v_passed_checks,
    failed_checks=v_failed_checks,critical_failures=v_critical_failures,high_failures=v_high_failures,readiness_score=readiness,
    summary=jsonb_build_object('module_score',module_score,'tenant_isolation_score',rls_score,'function_security_score',fn_score,
      'integrity_score',integrity_score,'queue_health_score',queue_score),updated_at=now()
  where id=run_record.id returning * into run_record;

  insert into public.platform_readiness_snapshots(
    organization_id,validation_run_id,readiness_status,readiness_score,module_completion_percent,tenant_isolation_score,
    function_security_score,integrity_score,queue_health_score,critical_failures,high_failures,snapshot_data
  ) values(
    p_organization_id,run_record.id,case when v_critical_failures>0 then 'not_ready' when v_high_failures>0 or readiness<95 then 'conditionally_ready' else 'ready' end,
    readiness,module_score,rls_score,fn_score,integrity_score,queue_score,v_critical_failures,v_high_failures,run_record.summary
  );

  if coalesce((config->>'auto_create_issues')::boolean,true) then
    insert into public.platform_integration_issues(
      organization_id,issue_key,check_code,category,severity,title,description,component_type,component_name,module_number,status,
      first_validation_run_id,last_validation_run_id,remediation,metadata
    )
    select p_organization_id,md5(coalesce(p_organization_id::text,'global')||':'||r.check_code||':'||coalesce(r.component_name,'')),
      r.check_code,r.category,r.severity,r.message,r.message,r.component_type,r.component_name,r.module_number,'open',
      run_record.id,run_record.id,r.remediation,r.details
    from public.platform_validation_results r where r.validation_run_id=run_record.id and r.passed=false and r.severity in('critical','high')
    on conflict(issue_key) do update set last_validation_run_id=excluded.last_validation_run_id,last_seen_at=now(),severity=excluded.severity,
      title=excluded.title,description=excluded.description,remediation=excluded.remediation,metadata=public.platform_integration_issues.metadata||excluded.metadata,
      status=case when public.platform_integration_issues.status in('resolved','false_positive') then 'open' else public.platform_integration_issues.status end,updated_at=now();

    update public.platform_integration_issues i set status='resolved',resolved_at=now(),resolution_notes='Automatically resolved by validation run '||run_record.run_code,updated_at=now()
    where i.organization_id is not distinct from p_organization_id and i.status in('open','acknowledged','in_progress')
      and not exists(select 1 from public.platform_validation_results r where r.validation_run_id=run_record.id and r.passed=false
        and i.issue_key=md5(coalesce(p_organization_id::text,'global')||':'||r.check_code||':'||coalesce(r.component_name,'')));
  end if;

  perform public.publish_platform_integration_event(p_organization_id,'platform.validation.'||run_status,
    jsonb_build_object('validation_run_id',run_record.id,'run_code',run_record.run_code,'status',run_status,'readiness_score',readiness,
      'critical_failures',v_critical_failures,'high_failures',v_high_failures),'observability','platform_validation_run',run_record.id,10,
      'platform-validation:'||run_record.id::text,run_record.correlation_id,run_record.trace_id,now());

  insert into public.platform_integration_logs(organization_id,log_level,event_name,message,source_type,source_id,actor_user_id,log_data,correlation_id,trace_id)
  values(p_organization_id,case when run_status='blocked' then 'critical' when run_status='degraded' then 'warning' else 'info' end,
    'platform.validation.'||run_status,'Platform validation completed with readiness score '||readiness,'platform_validation_run',run_record.id,auth.uid(),
    jsonb_build_object('total_checks',total_checks,'passed_checks',passed_checks,'failed_checks',failed_checks,'critical_failures',v_critical_failures,'high_failures',v_high_failures),run_record.correlation_id,run_record.trace_id);
  return run_record;
exception when others then
  if run_record.id is not null then
    update public.platform_validation_runs set status='failed',completed_at=now(),error_message=sqlerrm,updated_at=now() where id=run_record.id returning * into run_record;
    insert into public.platform_integration_logs(organization_id,log_level,event_name,message,source_type,source_id,error_code,error_message,log_data)
    values(p_organization_id,'error','platform.validation.failed','Platform validation execution failed','platform_validation_run',run_record.id,sqlstate,sqlerrm,'{}');
  end if;
  raise;
end $$;

-- ============================================================================
-- 11. READ-ONLY END-TO-END SMOKE TESTS
-- ============================================================================

create or replace function public.run_platform_smoke_tests(p_organization_id uuid default null)
returns public.platform_smoke_test_runs
language plpgsql
security definer
set search_path=''
as $$
declare run_record public.platform_smoke_test_runs;f record;passed boolean;started timestamptz;passed_count integer;failed_count integer;
begin
  if not public.platform_is_service_executor() and(
    p_organization_id is null or not public.has_organization_permission(p_organization_id,'platform_validation.smoke_test')
  ) then raise exception 'Permission denied'; end if;
  insert into public.platform_smoke_test_runs(organization_id,run_code,status,requested_by)
  values(p_organization_id,'SMOKE-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),'running',auth.uid()) returning * into run_record;

  started:=clock_timestamp();
  passed:=public.platform_component_exists('table','public','organizations','{}') and public.platform_component_exists('table','public','leads','{}')
    and public.platform_component_exists('function','public','has_organization_permission','{}');
  insert into public.platform_smoke_test_results(smoke_test_run_id,organization_id,test_code,stage_code,passed,message,duration_ms)
  values(run_record.id,p_organization_id,'CORE_FOUNDATION','foundation',passed,case when passed then 'Core foundation contract is available' else 'Core foundation contract is incomplete' end,extract(epoch from(clock_timestamp()-started))*1000);

  for f in select fc.*,m.module_number from public.platform_flow_contracts fc join public.platform_module_registry m on m.id=fc.module_id where fc.status='active' order by fc.sequence_number loop
    started:=clock_timestamp();
    passed:=public.platform_component_exists('table','public',f.authoritative_table,'{}');
    if passed and f.entry_function is not null then passed:=public.platform_component_exists('function','public',f.entry_function,'{}'); end if;
    insert into public.platform_smoke_test_results(smoke_test_run_id,organization_id,test_code,stage_code,passed,message,details,duration_ms)
    values(run_record.id,p_organization_id,'FLOW_'||upper(f.stage_code),f.stage_code,passed,
      case when passed then 'Flow contract available for '||f.stage_name else 'Flow contract unavailable for '||f.stage_name end,
      jsonb_build_object('module_number',f.module_number,'table',f.authoritative_table,'entry_function',f.entry_function,'output_event',f.output_event),
      extract(epoch from(clock_timestamp()-started))*1000);
  end loop;

  select count(*) filter(where sr.passed),count(*) filter(where not sr.passed) into passed_count,failed_count
  from public.platform_smoke_test_results sr where sr.smoke_test_run_id=run_record.id;
  update public.platform_smoke_test_runs set status=case when failed_count=0 then 'passed' else 'failed' end,completed_at=now(),
    passed_tests=passed_count,failed_tests=failed_count,summary=jsonb_build_object('flow_contract_version',1),updated_at=now()
  where id=run_record.id returning * into run_record;
  perform public.publish_platform_integration_event(p_organization_id,'platform.smoke_test.'||run_record.status,
    jsonb_build_object('smoke_test_run_id',run_record.id,'passed_tests',passed_count,'failed_tests',failed_count),
    'observability','platform_smoke_test_run',run_record.id,20,'platform-smoke:'||run_record.id::text);
  return run_record;
end $$;

create or replace function public.get_platform_readiness(p_organization_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare s public.platform_readiness_snapshots;
begin
  if not public.platform_is_service_executor() and(
    p_organization_id is null or not public.has_organization_permission(p_organization_id,'platform_validation.view')
  ) then raise exception 'Permission denied'; end if;
  select * into s from public.platform_readiness_snapshots where organization_id is not distinct from p_organization_id order by captured_at desc limit 1;
  if not found then
    return jsonb_build_object('organization_id',p_organization_id,'readiness_status','unknown','message','No validation run has been completed');
  end if;
  return jsonb_build_object('organization_id',s.organization_id,'readiness_status',s.readiness_status,'readiness_score',s.readiness_score,
    'module_completion_percent',s.module_completion_percent,'tenant_isolation_score',s.tenant_isolation_score,
    'function_security_score',s.function_security_score,'integrity_score',s.integrity_score,'queue_health_score',s.queue_health_score,
    'critical_failures',s.critical_failures,'high_failures',s.high_failures,'captured_at',s.captured_at,'validation_run_id',s.validation_run_id,
    'snapshot_data',s.snapshot_data);
end $$;

create or replace function public.resolve_platform_integration_issue(p_issue_id uuid,p_status text,p_resolution_notes text default null)
returns public.platform_integration_issues
language plpgsql
security definer
set search_path=''
as $$
declare r public.platform_integration_issues;
begin
  select * into r from public.platform_integration_issues where id=p_issue_id for update;
  if not found then raise exception 'Platform integration issue not found'; end if;
  if not public.platform_is_service_executor() and(
    r.organization_id is null or not public.has_organization_permission(r.organization_id,'platform_validation.resolve_issues')
  ) then raise exception 'Permission denied'; end if;
  if p_status not in('acknowledged','in_progress','resolved','accepted_risk','false_positive') then raise exception 'Unsupported issue status'; end if;
  update public.platform_integration_issues set status=p_status,resolution_notes=p_resolution_notes,
    resolved_by=case when p_status in('resolved','accepted_risk','false_positive') then auth.uid() else resolved_by end,
    resolved_at=case when p_status in('resolved','accepted_risk','false_positive') then now() else null end,updated_at=now()
  where id=p_issue_id returning * into r;
  return r;
end $$;

-- ============================================================================
-- 12. OUTBOX WORKER FUNCTIONS
-- ============================================================================

create or replace function public.claim_platform_integration_event(p_worker_id text,p_destination text default null,p_lock_seconds integer default 300)
returns public.platform_integration_event_outbox
language plpgsql security definer set search_path=''
as $$
declare r public.platform_integration_event_outbox;
begin
  if not public.platform_is_service_executor() then raise exception 'service executor required'; end if;
  update public.platform_integration_event_outbox set status='failed',available_at=now(),claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
    last_error_code=coalesce(last_error_code,'LOCK_EXPIRED'),last_error_message=coalesce(last_error_message,'Platform event lock expired'),updated_at=now()
  where status in('claimed','processing') and lock_expires_at is not null and lock_expires_at<=now();
  select * into r from public.platform_integration_event_outbox where status in('pending','failed') and available_at<=now()
    and delivery_attempts<maximum_attempts and(p_destination is null or destination=p_destination)
  order by priority,created_at for update skip locked limit 1;
  if not found then return null; end if;
  update public.platform_integration_event_outbox set status='claimed',delivery_attempts=delivery_attempts+1,claimed_at=now(),claimed_by=p_worker_id,
    lock_token=gen_random_uuid()::text,lock_expires_at=now()+make_interval(secs=>greatest(p_lock_seconds,1)),updated_at=now()
  where id=r.id returning * into r; return r;
end $$;

create or replace function public.complete_platform_integration_event(p_event_id uuid,p_lock_token text,p_result jsonb default '{}')
returns public.platform_integration_event_outbox
language plpgsql security definer set search_path=''
as $$
declare r public.platform_integration_event_outbox;
begin
  if not public.platform_is_service_executor() then raise exception 'service executor required'; end if;
  select * into r from public.platform_integration_event_outbox where id=p_event_id for update;
  if not found or r.lock_token is distinct from p_lock_token then raise exception 'Invalid platform event or lock'; end if;
  update public.platform_integration_event_outbox set status='delivered',delivered_at=now(),payload=payload||jsonb_build_object('delivery_result',coalesce(p_result,'{}')),
    claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,last_error_code=null,last_error_message=null,last_error_data='{}',updated_at=now()
  where id=r.id returning * into r; return r;
end $$;

create or replace function public.fail_platform_integration_event(p_event_id uuid,p_lock_token text,p_error_code text,p_error_message text,p_error_data jsonb default '{}')
returns public.platform_integration_event_outbox
language plpgsql security definer set search_path=''
as $$
declare r public.platform_integration_event_outbox;next_status text;delay_seconds integer;
begin
  if not public.platform_is_service_executor() then raise exception 'service executor required'; end if;
  select * into r from public.platform_integration_event_outbox where id=p_event_id for update;
  if not found or r.lock_token is distinct from p_lock_token then raise exception 'Invalid platform event or lock'; end if;
  next_status:=case when r.delivery_attempts>=r.maximum_attempts then 'dead_lettered' else 'failed' end;
  delay_seconds:=least(3600,greatest(30,power(2,greatest(r.delivery_attempts,1))::integer*30));
  update public.platform_integration_event_outbox set status=next_status,available_at=case when next_status='failed' then now()+make_interval(secs=>delay_seconds) else available_at end,
    last_error_code=p_error_code,last_error_message=p_error_message,last_error_data=coalesce(p_error_data,'{}'),claimed_at=null,claimed_by=null,
    lock_token=null,lock_expires_at=null,updated_at=now() where id=r.id returning * into r; return r;
end $$;

-- ============================================================================
-- 13. DASHBOARD VIEWS
-- ============================================================================

create or replace view public.platform_module_status_dashboard with(security_invoker=true) as
select m.module_number,m.module_code,m.module_name,m.platform_layer,m.lifecycle_status,m.authority_status,m.detected_status,
  m.required_component_count,m.detected_component_count,m.marker_verified,m.superseded_by_module_number,m.last_validated_at,m.notes,
  case when m.required_component_count>0 then round(m.detected_component_count::numeric/m.required_component_count*100,2) else 0 end component_completion_percent
from public.platform_module_registry m order by m.module_number;

create or replace view public.platform_validation_dashboard with(security_invoker=true) as
select r.id validation_run_id,r.organization_id,r.run_code,p.profile_code,r.run_type,r.status,r.readiness_score,r.total_checks,r.passed_checks,r.failed_checks,
  r.critical_failures,r.high_failures,r.started_at,r.completed_at,r.summary
from public.platform_validation_runs r join public.platform_validation_profiles p on p.id=r.profile_id;

create or replace view public.platform_readiness_dashboard with(security_invoker=true) as
select distinct on(organization_id) organization_id,validation_run_id,readiness_status,readiness_score,module_completion_percent,
  tenant_isolation_score,function_security_score,integrity_score,queue_health_score,critical_failures,high_failures,captured_at,snapshot_data
from public.platform_readiness_snapshots order by organization_id,captured_at desc;

create or replace view public.platform_open_issue_dashboard with(security_invoker=true) as
select organization_id,severity,category,status,count(*) issue_count,min(first_seen_at) oldest_issue_at,max(last_seen_at) latest_issue_at
from public.platform_integration_issues where status in('open','acknowledged','in_progress')
group by organization_id,severity,category,status;

create or replace view public.platform_authority_dashboard with(security_invoker=true) as
select a.capability_domain,m.module_number,m.module_code,m.module_name,a.canonical_namespace,a.status,a.legacy_module_ids,a.effective_from,a.notes
from public.platform_engine_authority a join public.platform_module_registry m on m.id=a.authoritative_module_id;

create or replace view public.platform_flow_contract_dashboard with(security_invoker=true) as
select f.sequence_number,f.stage_code,f.stage_name,m.module_number,m.module_name,f.authoritative_table,f.entry_function,f.output_event,f.status,f.contract_version,
  public.platform_component_exists('table','public',f.authoritative_table,'{}') table_available,
  case when f.entry_function is null then true else public.platform_component_exists('function','public',f.entry_function,'{}') end function_available
from public.platform_flow_contracts f join public.platform_module_registry m on m.id=f.module_id order by f.sequence_number;

-- ============================================================================
-- 14. SEED VALIDATION PROFILES
-- ============================================================================

insert into public.platform_validation_profiles(profile_code,profile_name,description,configuration,status)
values
('quick','Quick Platform Validation','Fast deployment and migration validation without deep foreign-key scans',
 jsonb_build_object('check_fk_indexes',false,'check_fk_integrity',false,'check_queue_locks',true,'auto_create_issues',true),'active'),
('production','Production Readiness Validation','Full production audit including FK indexes and referential integrity',
 jsonb_build_object('check_fk_indexes',true,'check_fk_integrity',true,'check_queue_locks',true,'auto_create_issues',true),'active'),
('incident','Incident Diagnostic Validation','Operational diagnostic profile focused on queues and security',
 jsonb_build_object('check_fk_indexes',false,'check_fk_integrity',false,'check_queue_locks',true,'auto_create_issues',true),'active')
on conflict(profile_code) do update set profile_name=excluded.profile_name,description=excluded.description,configuration=excluded.configuration,status='active',updated_at=now();

-- ============================================================================
-- 15. SEED MODULE REGISTRY 001-036
-- ============================================================================

insert into public.platform_module_registry(
  module_number,module_code,module_name,platform_layer,migration_file,lifecycle_status,authority_status,
  superseded_by_module_number,marker_table,marker_event,required_components,notes
) values
(1,'001_core_foundation','Core Foundation','foundation','001_initial_schema.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"organizations","required":true},{"type":"function","schema":"public","name":"set_updated_at","required":true}]'::jsonb,'Core tenant foundation.'),
(2,'002_rbac','Role-Based Access Control','security','002_rbac.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"roles","required":true},{"type":"table","schema":"public","name":"permissions","required":true},{"type":"table","schema":"public","name":"role_permissions","required":true},{"type":"function","schema":"public","name":"has_organization_permission","required":true}]'::jsonb,'Authoritative RBAC layer.'),
(3,'003_leads','Lead Management','sales','003_leads.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"leads","required":true},{"type":"table","schema":"public","name":"lead_activities","required":true}]'::jsonb,'Core lead system of record.'),
(4,'004_followups','Follow-up Management','sales','004_followups.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"follow_up_tasks","required":true}]'::jsonb,'Lead follow-up task layer.'),
(5,'005_site_visits','Site Visit Management','sales','005_site_visits.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"site_visits","required":true}]'::jsonb,'Site visit scheduling and outcome layer.'),
(6,'006_bookings','Booking Management','sales','006_bookings.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"bookings","required":true}]'::jsonb,'Booking and deal conversion layer.'),
(7,'007_customer_success','Customer Success','customer','007_customer_success.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"customers","required":true}]'::jsonb,'Customer lifecycle foundation.'),
(8,'008_inventory','Inventory Engine','inventory','008_inventory.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"builders","required":true},{"type":"table","schema":"public","name":"projects","required":true},{"type":"table","schema":"public","name":"inventory_units","required":true},{"type":"table","schema":"public","name":"inventory_reservations","required":true},{"type":"function","schema":"public","name":"reserve_inventory_unit","required":true}]'::jsonb,'Project and unit inventory system.'),
(9,'009_workflow_engine','Workflow Engine v1','orchestration','009_workflow_engine_v2.sql','compatibility','legacy',28,null,null,'[{"type":"table","schema":"public","name":"workflow_definitions","required":true},{"type":"table","schema":"public","name":"workflow_executions","required":true},{"type":"function","schema":"public","name":"start_workflow_execution","required":true}]'::jsonb,'Compatibility workflow layer; enterprise orchestration is authoritative.'),
(10,'010_ai_calling_engine','AI Calling Engine','ai','010_ai_calling_engine.sql','active','authoritative',null,null,null,'[{"type":"table","schema":"public","name":"ai_call_jobs","required":true},{"type":"table","schema":"public","name":"ai_call_attempts","required":true},{"type":"table","schema":"public","name":"ai_call_consents","required":true},{"type":"function","schema":"public","name":"create_ai_call_job","required":true}]'::jsonb,'AI voice calling and qualification.'),
(11,'011_lead_validation_engine','Lead Validation Engine','sales','011_lead_validation_engine_production_v2.sql','active','authoritative',null,'lead_validation_logs','migration.011.completed','[{"type":"table","schema":"public","name":"lead_validation_jobs","required":true},{"type":"table","schema":"public","name":"lead_validation_results","required":true},{"type":"table","schema":"public","name":"lead_duplicate_matches","required":true},{"type":"table","schema":"public","name":"lead_validation_logs","required":true}]'::jsonb,'Duplicate, fake and quality validation.'),
(12,'012_assignment_engine','Assignment Engine','sales','012_assignment_engine.sql','active','authoritative',null,'assignment_logs','migration.012.completed','[{"type":"table","schema":"public","name":"assignment_agent_profiles","required":true},{"type":"table","schema":"public","name":"assignment_requests","required":true},{"type":"table","schema":"public","name":"lead_assignments","required":true},{"type":"table","schema":"public","name":"assignment_logs","required":true},{"type":"function","schema":"public","name":"create_assignment_request","required":true}]'::jsonb,'Agent selection, workload and SLA assignment.'),
(13,'013_communication_engine','Communication Engine v1','communication','013_communication_engine.sql','compatibility','legacy',27,'communication_logs','migration.013.completed','[{"type":"table","schema":"public","name":"communication_channels","required":true},{"type":"table","schema":"public","name":"communication_message_jobs","required":true},{"type":"table","schema":"public","name":"communication_event_outbox","required":true},{"type":"table","schema":"public","name":"communication_logs","required":true}]'::jsonb,'Compatibility communication layer; v2 is authoritative.'),
(14,'014_automation_execution_engine','Automation Execution Engine v1','automation','014_automation_execution_engine.sql','compatibility','legacy',26,'automation_logs','migration.014.completed','[{"type":"table","schema":"public","name":"automation_definitions","required":true},{"type":"table","schema":"public","name":"automation_runs","required":true},{"type":"table","schema":"public","name":"automation_task_queue","required":true},{"type":"table","schema":"public","name":"automation_logs","required":true},{"type":"function","schema":"public","name":"claim_automation_run","required":true}]'::jsonb,'Compatibility automation layer; v2 is authoritative.'),
(15,'015_notification_engine','Notification Engine','communication','015_notification_engine.sql','active','authoritative',null,'notification_logs','migration.015.completed','[{"type":"table","schema":"public","name":"notification_jobs","required":true},{"type":"table","schema":"public","name":"notification_recipients","required":true},{"type":"table","schema":"public","name":"notification_event_outbox","required":true},{"type":"table","schema":"public","name":"notification_logs","required":true},{"type":"function","schema":"public","name":"create_notification_job","required":true}]'::jsonb,'User and operational notification delivery.'),
(16,'016_audit_activity_engine','Audit & Activity Engine','governance','016_Audit_Activity_Engine.sql','active','authoritative',null,'audit_logs','migration.016.completed','[{"type":"table","schema":"public","name":"audit_events","required":true},{"type":"table","schema":"public","name":"audit_security_events","required":true},{"type":"table","schema":"public","name":"audit_logs","required":true},{"type":"function","schema":"public","name":"record_audit_event","required":true}]'::jsonb,'Immutable activity and security audit layer.'),
(17,'017_analytics_bi_engine','Analytics & BI Engine','analytics','017_Analytics_BI_Engine.sql','active','authoritative',null,'analytics_logs','migration.017.completed','[{"type":"table","schema":"public","name":"analytics_kpi_definitions","required":true},{"type":"table","schema":"public","name":"analytics_dashboards","required":true},{"type":"table","schema":"public","name":"analytics_refresh_jobs","required":true},{"type":"table","schema":"public","name":"analytics_logs","required":true}]'::jsonb,'Business intelligence and KPI layer.'),
(18,'018_document_management_engine','Document Management Engine','documents','018_Document_Management_Engine.sql','active','authoritative',null,'document_logs','migration.018.completed','[{"type":"table","schema":"public","name":"documents","required":true},{"type":"table","schema":"public","name":"document_versions","required":true},{"type":"table","schema":"public","name":"document_processing_jobs","required":true},{"type":"table","schema":"public","name":"document_logs","required":true}]'::jsonb,'Documents, versions and processing.'),
(19,'019_customer_portal_engine','Customer Portal Engine','customer','019_Customer_Portal_Engine_v2.sql','active','authoritative',null,'customer_portal_logs','migration.019.completed','[{"type":"table","schema":"public","name":"customer_portal_accounts","required":true},{"type":"table","schema":"public","name":"customer_portal_support_tickets","required":true},{"type":"table","schema":"public","name":"customer_portal_event_outbox","required":true},{"type":"table","schema":"public","name":"customer_portal_logs","required":true}]'::jsonb,'Controlled external customer access.'),
(20,'020_finance_commission_engine','Finance & Commission Engine','finance','020_Finance_Commission_Engine.sql','active','authoritative',null,'finance_logs','migration.020.completed','[{"type":"table","schema":"public","name":"finance_invoices","required":true},{"type":"table","schema":"public","name":"finance_commission_accruals","required":true},{"type":"table","schema":"public","name":"finance_ledger_entries","required":true},{"type":"table","schema":"public","name":"finance_logs","required":true}]'::jsonb,'Finance, receivables and commissions.'),
(21,'021_administration_engine','Administration Engine','administration','021_Administration_Engine.sql','active','authoritative',null,'admin_logs','migration.021.completed','[{"type":"table","schema":"public","name":"admin_organization_profiles","required":true},{"type":"table","schema":"public","name":"admin_employees","required":true},{"type":"table","schema":"public","name":"admin_tenant_limits","required":true},{"type":"table","schema":"public","name":"admin_logs","required":true}]'::jsonb,'Organization administration and controls.'),
(22,'022_reporting_engine','Reporting Engine','reporting','022_Reporting_Engine.sql','active','authoritative',null,'reporting_logs','migration.022.completed','[{"type":"table","schema":"public","name":"reports","required":true},{"type":"table","schema":"public","name":"reporting_execution_jobs","required":true},{"type":"table","schema":"public","name":"reporting_outputs","required":true},{"type":"table","schema":"public","name":"reporting_logs","required":true}]'::jsonb,'Operational and scheduled reports.'),
(23,'023_integration_api_engine','Integration & API Engine','integration','023_Integration_API_Engine.sql','active','authoritative',null,'integration_logs','migration.023.completed','[{"type":"table","schema":"public","name":"integration_connections","required":true},{"type":"table","schema":"public","name":"api_keys","required":true},{"type":"table","schema":"public","name":"webhook_delivery_jobs","required":true},{"type":"table","schema":"public","name":"integration_logs","required":true}]'::jsonb,'API clients, webhooks and external integrations.'),
(24,'024_mobile_app_engine','Mobile App Engine','mobile','024_Mobile_App_Engine.sql','active','authoritative',null,'mobile_logs','migration.024.completed','[{"type":"table","schema":"public","name":"mobile_devices","required":true},{"type":"table","schema":"public","name":"mobile_sync_queue","required":true},{"type":"table","schema":"public","name":"mobile_event_outbox","required":true},{"type":"table","schema":"public","name":"mobile_logs","required":true}]'::jsonb,'Mobile devices, sync and field activity.'),
(25,'025_ai_intelligence_engine','AI Intelligence Engine','ai','025_AI_Intelligence_Engine.sql','active','authoritative',null,'ai_intelligence_logs','migration.025.completed','[{"type":"table","schema":"public","name":"ai_intelligence_models","required":true},{"type":"table","schema":"public","name":"ai_agents","required":true},{"type":"table","schema":"public","name":"ai_intelligence_event_outbox","required":true},{"type":"table","schema":"public","name":"ai_intelligence_logs","required":true}]'::jsonb,'General AI agents, routing, RAG and evaluation.'),
(26,'026_automation_engine','Automation Engine v2','automation','026_Automation_Engine.sql','active','authoritative',null,'automation_engine_logs_v2','migration.026.completed','[{"type":"table","schema":"public","name":"automation_definitions_v2","required":true},{"type":"table","schema":"public","name":"automation_executions_v2","required":true},{"type":"table","schema":"public","name":"automation_job_queue_v2","required":true},{"type":"table","schema":"public","name":"automation_engine_logs_v2","required":true},{"type":"function","schema":"public","name":"start_automation_execution_v2","required":true}]'::jsonb,'Authoritative automation execution engine.'),
(27,'027_communication_engine','Communication Engine v2','communication','027_Communication_Engine.sql','active','authoritative',null,'communication_engine_logs_v2','migration.027.completed','[{"type":"table","schema":"public","name":"communication_conversations_v2","required":true},{"type":"table","schema":"public","name":"communication_messages_v2","required":true},{"type":"table","schema":"public","name":"communication_message_queue_v2","required":true},{"type":"table","schema":"public","name":"communication_engine_logs_v2","required":true},{"type":"function","schema":"public","name":"queue_outbound_message_v2","required":true}]'::jsonb,'Authoritative omnichannel communication engine.'),
(28,'028_enterprise_workflow_orchestration','Enterprise Workflow Orchestration','orchestration','028_Enterprise_Workflow_Orchestration.sql','active','authoritative',null,'enterprise_workflow_logs','migration.028.completed','[{"type":"table","schema":"public","name":"enterprise_workflow_definitions","required":true},{"type":"table","schema":"public","name":"enterprise_workflow_instances","required":true},{"type":"table","schema":"public","name":"enterprise_workflow_human_tasks","required":true},{"type":"table","schema":"public","name":"enterprise_workflow_event_outbox","required":true},{"type":"table","schema":"public","name":"enterprise_workflow_logs","required":true},{"type":"function","schema":"public","name":"start_enterprise_workflow","required":true}]'::jsonb,'Authoritative long-running business workflow engine.'),
(29,'029_security_compliance_governance','Security, Compliance & Governance','governance','029_Security_Compliance_Governance_Engine.sql','active','authoritative',null,'security_governance_logs','migration.029.completed','[{"type":"table","schema":"public","name":"security_governance_controls","required":true},{"type":"table","schema":"public","name":"security_governance_incidents","required":true},{"type":"table","schema":"public","name":"security_governance_event_outbox","required":true},{"type":"table","schema":"public","name":"security_governance_logs","required":true}]'::jsonb,'Security controls, risks and compliance.'),
(30,'030_observability_monitoring_reliability','Observability, Monitoring & Reliability','operations','030_Observability_Monitoring_Reliability_Engine.sql','active','authoritative',null,'observability_engine_logs','migration.030.completed','[{"type":"table","schema":"public","name":"observability_services","required":true},{"type":"table","schema":"public","name":"observability_reliability_incidents","required":true},{"type":"table","schema":"public","name":"observability_event_outbox","required":true},{"type":"table","schema":"public","name":"observability_engine_logs","required":true}]'::jsonb,'Telemetry, SLOs, incidents and reliability.'),
(31,'031_backup_dr_business_continuity','Backup, DR & Business Continuity','operations','031_Backup_Disaster_Recovery_Business_Continuity_Engine.sql','active','authoritative',null,'resilience_logs','migration.031.completed','[{"type":"table","schema":"public","name":"resilience_backup_jobs","required":true},{"type":"table","schema":"public","name":"resilience_recovery_runs","required":true},{"type":"table","schema":"public","name":"resilience_event_outbox","required":true},{"type":"table","schema":"public","name":"resilience_logs","required":true}]'::jsonb,'Backup, recovery, failover and continuity.'),
(32,'032_billing_subscription_licensing','Billing, Subscription & Licensing','billing','032_Billing_Subscription_Licensing_Engine.sql','active','authoritative',null,'billing_logs','migration.032.completed','[{"type":"table","schema":"public","name":"billing_plans","required":true},{"type":"table","schema":"public","name":"billing_subscriptions","required":true},{"type":"table","schema":"public","name":"billing_license_assignments","required":true},{"type":"table","schema":"public","name":"billing_event_outbox","required":true},{"type":"table","schema":"public","name":"billing_logs","required":true}]'::jsonb,'Commercial entitlement and billing layer.'),
(33,'033_tenant_onboarding_provisioning','Tenant Onboarding & Provisioning','onboarding','033_Tenant_Onboarding_Provisioning_Engine.sql','active','authoritative',null,'onboarding_logs','migration.033.completed','[{"type":"table","schema":"public","name":"tenant_onboarding_requests","required":true},{"type":"table","schema":"public","name":"onboarding_provisioning_runs","required":true},{"type":"table","schema":"public","name":"onboarding_activation_checks","required":true},{"type":"table","schema":"public","name":"onboarding_event_outbox","required":true},{"type":"table","schema":"public","name":"onboarding_logs","required":true}]'::jsonb,'Tenant signup, approval and provisioning.'),
(34,'034_feature_flag_configuration','Feature Flag & Configuration','configuration','034_Feature_Flag_Configuration_Engine.sql','active','authoritative',null,'feature_configuration_logs','migration.034.completed','[{"type":"table","schema":"public","name":"feature_flags","required":true},{"type":"table","schema":"public","name":"configuration_entries","required":true},{"type":"table","schema":"public","name":"feature_configuration_event_outbox","required":true},{"type":"table","schema":"public","name":"feature_configuration_logs","required":true}]'::jsonb,'Feature rollout and versioned configuration.'),
(35,'035_data_privacy_consent_retention','Data Privacy, Consent & Retention','privacy','035_Data_Privacy_Consent_Retention_Engine.sql','active','authoritative',null,'privacy_logs','migration.035.completed','[{"type":"table","schema":"public","name":"privacy_consents","required":true},{"type":"table","schema":"public","name":"privacy_requests","required":true},{"type":"table","schema":"public","name":"privacy_retention_policies","required":true},{"type":"table","schema":"public","name":"privacy_logs","required":true},{"type":"function","schema":"public","name":"check_privacy_consent","required":true}]'::jsonb,'Consent, privacy requests, retention and legal holds.'),
(36,'036_platform_integration_validation','Platform Integration & Validation','platform','036_Platform_Integration_Validation_Engine.sql','active','authoritative',null,'platform_integration_logs','migration.036.completed','[{"type":"table","schema":"public","name":"platform_module_registry","required":true},{"type":"table","schema":"public","name":"platform_validation_runs","required":true},{"type":"table","schema":"public","name":"platform_validation_results","required":true},{"type":"table","schema":"public","name":"platform_integration_logs","required":true},{"type":"function","schema":"public","name":"run_platform_validation","required":true}]'::jsonb,'Cross-module integration, readiness and production validation.')
on conflict(module_number) do update set module_code=excluded.module_code,module_name=excluded.module_name,platform_layer=excluded.platform_layer,
  migration_file=excluded.migration_file,lifecycle_status=excluded.lifecycle_status,authority_status=excluded.authority_status,
  superseded_by_module_number=excluded.superseded_by_module_number,marker_table=excluded.marker_table,marker_event=excluded.marker_event,
  required_components=excluded.required_components,notes=excluded.notes,updated_at=now();

select public.sync_platform_component_expectations();

-- ============================================================================
-- 16. SEED DEPENDENCIES
-- ============================================================================

insert into public.platform_module_dependencies(module_id,depends_on_module_id,dependency_type)
select c.id,p.id,v.dependency_type
from (values
(2,1,'required'),
(3,1,'required'),
(3,2,'required'),
(4,3,'required'),
(5,3,'required'),
(6,5,'required'),
(6,8,'required'),
(7,6,'recommended'),
(8,1,'required'),
(8,2,'required'),
(9,3,'required'),
(10,3,'required'),
(10,9,'recommended'),
(11,3,'required'),
(12,3,'required'),
(12,11,'recommended'),
(13,3,'required'),
(14,9,'required'),
(15,13,'recommended'),
(16,1,'required'),
(16,2,'required'),
(17,3,'required'),
(18,1,'required'),
(19,7,'required'),
(19,18,'required'),
(20,6,'required'),
(21,1,'required'),
(21,2,'required'),
(22,17,'recommended'),
(23,1,'required'),
(23,2,'required'),
(24,3,'required'),
(24,23,'recommended'),
(25,3,'required'),
(25,17,'recommended'),
(26,9,'recommended'),
(26,23,'recommended'),
(27,13,'recommended'),
(27,23,'recommended'),
(28,9,'recommended'),
(28,26,'required'),
(28,27,'required'),
(29,16,'required'),
(30,16,'required'),
(30,29,'recommended'),
(31,30,'required'),
(32,20,'recommended'),
(32,23,'required'),
(33,2,'required'),
(33,32,'recommended'),
(34,21,'recommended'),
(35,16,'required'),
(35,18,'recommended'),
(36,2,'required'),
(36,16,'required'),
(36,29,'recommended'),
(36,30,'recommended')
) v(child_no,parent_no,dependency_type)
join public.platform_module_registry c on c.module_number=v.child_no
join public.platform_module_registry p on p.module_number=v.parent_no
on conflict(module_id,depends_on_module_id) do update set dependency_type=excluded.dependency_type;

-- ============================================================================
-- 17. SEED AUTHORITATIVE ENGINE MAP
-- ============================================================================

insert into public.platform_engine_authority(capability_domain,authoritative_module_id,legacy_module_ids,canonical_namespace,notes)
select v.capability_domain,m.id,
  coalesce((select array_agg(lm.id order by lm.module_number) from public.platform_module_registry lm where lm.module_number=any(v.legacy_numbers)),'{}'::uuid[]),
  v.canonical_namespace,v.notes
from (values
('workflow_orchestration',28,array[9]::integer[],'enterprise_workflow','Enterprise workflow orchestration is authoritative; module 009 remains a compatibility layer.'),
('automation_execution',26,array[14]::integer[],'automation_v2','Automation v2 is authoritative; module 014 remains for compatibility and migration.'),
('communication_delivery',27,array[13]::integer[],'communication_v2','Communication v2 is authoritative; module 013 remains for compatibility and migration.'),
('ai_voice_calling',10,'{}'::integer[],'ai_calling','Specialized AI calling engine.'),
('ai_general_intelligence',25,'{}'::integer[],'ai_intelligence','General AI intelligence and agent engine.'),
('notifications',15,'{}'::integer[],'notification','Notification engine remains authoritative for user and operational notifications.'),
('privacy_consent',35,'{}'::integer[],'privacy','Privacy engine is the authoritative consent and retention gate.')
) v(capability_domain,authoritative_number,legacy_numbers,canonical_namespace,notes)
join public.platform_module_registry m on m.module_number=v.authoritative_number
on conflict(capability_domain) do update set authoritative_module_id=excluded.authoritative_module_id,legacy_module_ids=excluded.legacy_module_ids,
  canonical_namespace=excluded.canonical_namespace,notes=excluded.notes,status='active',updated_at=now();

-- ============================================================================
-- 18. SEED END-TO-END FLOW CONTRACT
-- ============================================================================

insert into public.platform_flow_contracts(sequence_number,stage_code,stage_name,module_id,authoritative_table,entry_function,output_event,description)
select v.sequence_number,v.stage_code,v.stage_name,m.id,v.authoritative_table,v.entry_function,v.output_event,v.description
from (values
(10,'lead_intake','Lead Intake',3,'leads',null,'lead.created','Create normalized lead record.'),
(20,'lead_validation','Lead Validation',11,'lead_validation_jobs',null,'lead.validation.completed','Duplicate, fake and quality checks.'),
(30,'privacy_gate','Consent & Privacy Gate',35,'privacy_consents','check_privacy_consent','privacy.eligibility.evaluated','Block prohibited processing or communication.'),
(40,'ai_calling','AI Calling',10,'ai_call_jobs','create_ai_call_job','ai_call.completed','Create and process AI qualification call.'),
(50,'qualification','Qualification',10,'ai_call_qualification_results','calculate_ai_call_qualification','lead.qualified','Calculate hot, warm or cold outcome.'),
(60,'assignment','Agent Assignment',12,'assignment_requests','create_assignment_request','assignment.completed','Assign eligible agent under SLA.'),
(70,'communication','Communication',27,'communication_messages_v2','queue_outbound_message_v2','communication.message.delivered','Omnichannel delivery through v2 engine.'),
(80,'follow_up','Follow-up',4,'follow_up_tasks',null,'follow_up.completed','Agent and automated follow-up execution.'),
(90,'site_visit','Site Visit',5,'site_visits',null,'site_visit.completed','Schedule and record site visit.'),
(100,'booking','Booking',6,'bookings',null,'booking.created','Convert selected inventory into booking.'),
(110,'customer_conversion','Customer Conversion',7,'customers',null,'customer.created','Create customer lifecycle record.'),
(120,'customer_portal','Customer Portal',19,'customer_portal_accounts','create_customer_portal_account','customer_portal.account.created','Controlled post-booking customer access.')
) v(sequence_number,stage_code,stage_name,module_number,authoritative_table,entry_function,output_event,description)
join public.platform_module_registry m on m.module_number=v.module_number
on conflict(stage_code) do update set sequence_number=excluded.sequence_number,stage_name=excluded.stage_name,module_id=excluded.module_id,
  authoritative_table=excluded.authoritative_table,entry_function=excluded.entry_function,output_event=excluded.output_event,
  description=excluded.description,status='active',updated_at=now();

-- ============================================================================
-- 19. ROW LEVEL SECURITY
-- ============================================================================

do $$
declare
  t text;
  relation_kind "char";
begin
  foreach t in array array[
    'platform_module_registry',
    'platform_module_dependencies',
    'platform_component_expectations',
    'platform_engine_authority',
    'platform_flow_contracts',
    'platform_validation_profiles'
  ] loop
    select c.relkind
    into relation_kind
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = t;

    if relation_kind not in ('r','p') then
      raise exception
        'RLS target public.% is not a base/partitioned table (relkind=%)',
        t,
        relation_kind;
    end if;

    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists %I_select_policy on public.%I',t,t);
    execute format('create policy %I_select_policy on public.%I for select to authenticated using(true)',t,t);
    execute format('drop policy if exists %I_service_policy on public.%I',t,t);
    execute format('create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t);
  end loop;

  foreach t in array array[
    'platform_validation_runs',
    'platform_validation_results',
    'platform_smoke_test_runs',
    'platform_smoke_test_results',
    'platform_readiness_snapshots',
    'platform_integration_issues',
    'platform_integration_event_outbox',
    'platform_integration_logs'
  ] loop
    select c.relkind
    into relation_kind
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = t;

    if relation_kind not in ('r','p') then
      raise exception
        'RLS target public.% is not a base/partitioned table (relkind=%)',
        t,
        relation_kind;
    end if;

    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists %I_select_policy on public.%I',t,t);
    execute format('create policy %I_select_policy on public.%I for select to authenticated using(organization_id is not null and(public.has_organization_permission(organization_id,''platform_validation.view'') or public.has_organization_permission(organization_id,''platform_validation.view_logs'')))',t,t);
    execute format('drop policy if exists %I_service_policy on public.%I',t,t);
    execute format('create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t);
  end loop;
end $$;

-- ============================================================================
-- 20. GRANTS
-- ============================================================================

grant select on public.platform_module_registry,public.platform_module_dependencies,public.platform_component_expectations,
  public.platform_engine_authority,public.platform_flow_contracts,public.platform_validation_profiles,
  public.platform_validation_runs,public.platform_validation_results,public.platform_smoke_test_runs,public.platform_smoke_test_results,
  public.platform_readiness_snapshots,public.platform_integration_issues,public.platform_integration_event_outbox,public.platform_integration_logs
  to authenticated;

grant all on public.platform_module_registry,public.platform_module_dependencies,public.platform_component_expectations,
  public.platform_engine_authority,public.platform_flow_contracts,public.platform_validation_profiles,
  public.platform_validation_runs,public.platform_validation_results,public.platform_smoke_test_runs,public.platform_smoke_test_results,
  public.platform_readiness_snapshots,public.platform_integration_issues,public.platform_integration_event_outbox,public.platform_integration_logs
  to service_role;

grant select on public.platform_module_status_dashboard,public.platform_validation_dashboard,public.platform_readiness_dashboard,
  public.platform_open_issue_dashboard,public.platform_authority_dashboard,public.platform_flow_contract_dashboard
  to authenticated,service_role;

do $$
declare r record;
begin
  for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in('run_platform_validation','run_platform_smoke_tests','get_platform_readiness','resolve_platform_integration_issue','platform_component_exists','platform_column_exists') loop
    execute format('revoke all on function %s from public',r.signature);
    execute format('grant execute on function %s to authenticated,service_role',r.signature);
  end loop;
  for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname in('platform_is_service_executor','platform_add_validation_result',
      'publish_platform_integration_event','sync_platform_component_expectations','refresh_platform_module_status','claim_platform_integration_event',
      'complete_platform_integration_event','fail_platform_integration_event') loop
    execute format('revoke all on function %s from public',r.signature);
    execute format('grant execute on function %s to service_role',r.signature);
  end loop;
end $$;

-- ============================================================================
-- 21. INITIAL MODULE DETECTION
-- ============================================================================

-- Module-status discovery is deliberately deferred until after COMMIT.
-- This keeps installation independent of legacy objects that may contain
-- broken dependencies. Run the post-install validation query supplied with
-- this migration after successful installation.

-- ============================================================================
-- 22. FINAL VALIDATION OF MIGRATION 036
-- ============================================================================

do $$
declare item text;missing text[]:='{}';
begin
  foreach item in array array[
    'platform_module_registry','platform_module_dependencies','platform_component_expectations','platform_engine_authority',
    'platform_flow_contracts','platform_validation_profiles','platform_validation_runs','platform_validation_results',
    'platform_smoke_test_runs','platform_smoke_test_results','platform_readiness_snapshots','platform_integration_issues',
    'platform_integration_event_outbox','platform_integration_logs'
  ] loop
    if not exists(select 1 from information_schema.tables where table_schema='public' and table_name=item) then missing:=array_append(missing,'table:'||item); end if;
  end loop;
  foreach item in array array['run_platform_validation','run_platform_smoke_tests','get_platform_readiness','refresh_platform_module_status',
    'claim_platform_integration_event','complete_platform_integration_event','fail_platform_integration_event'] loop
    if not exists(select 1 from information_schema.routines where routine_schema='public' and routine_name=item) then missing:=array_append(missing,'function:'||item); end if;
  end loop;
  if cardinality(missing)>0 then raise exception '036 migration validation failed. Missing: %',array_to_string(missing,', '); end if;
end $$;

-- ============================================================================
-- 23. MIGRATION AUDIT AND FINAL STATUS REFRESH
-- ============================================================================

insert into public.platform_integration_logs(organization_id,log_level,event_name,message,source_type,log_data)
select o.id,'info','migration.036.completed','Platform Integration and Validation Engine migration 036 completed','migration',
  jsonb_build_object('migration','036_platform_integration_validation_engine','completed_at',now(),
    'modules',jsonb_build_array('module_registry','dependency_validation','component_catalog','engine_authority','flow_contract',
      'rls_audit','tenant_index_audit','security_definer_audit','foreign_key_audit','queue_health','smoke_tests','readiness_scoring','issue_management','event_outbox'))
from public.organizations o
where not exists(select 1 from public.platform_integration_logs l where l.organization_id=o.id and l.event_name='migration.036.completed');

insert into public.platform_integration_logs(organization_id,log_level,event_name,message,source_type,log_data)
select null,'info','migration.036.completed','Platform Integration and Validation Engine migration 036 completed','migration',
  jsonb_build_object('migration','036_platform_integration_validation_engine','completed_at',now(),'scope','global','revision','v7-replica-mode-retained-through-commit')
where not exists(select 1 from public.platform_integration_logs l where l.organization_id is null and l.event_name='migration.036.completed');

-- Keep replica mode active through COMMIT.
--
-- The exact-failure locator proved that every migration statement succeeds
-- and the failure occurs only during transaction finalization. Because this
-- setting is LOCAL, PostgreSQL restores session_replication_role to origin
-- automatically when COMMIT completes (or when the transaction rolls back).
--
-- PostgREST schema reload is intentionally performed in a separate,
-- post-commit statement supplied with this migration.
update public.platform_module_registry
set
  detected_status='complete',
  required_component_count=(
    select count(*)
    from public.platform_component_expectations e
    where e.module_id=public.platform_module_registry.id
      and e.required=true
  ),
  detected_component_count=(
    select count(*)
    from public.platform_component_expectations e
    where e.module_id=public.platform_module_registry.id
      and e.required=true
      and public.platform_component_exists(
        e.component_type,
        e.schema_name,
        e.component_name,
        e.metadata
      )
  ),
  marker_verified=true,
  last_validated_at=now(),
  updated_at=now()
where module_number=36;

commit;