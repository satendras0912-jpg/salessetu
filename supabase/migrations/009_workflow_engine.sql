-- ============================================================
-- SalesSetu Enterprise
-- Migration 009: Workflow Engine
-- Consolidated single-file migration
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- Existing RBAC schema:
-- permissions(id, module, action, code, description, ...)
insert into public.permissions (module, action, code, description)
select
  permission_data.module,
  permission_data.action,
  permission_data.code,
  permission_data.description
from (
  values
    ('workflows','view','workflows.view','View workflow definitions and executions'),
    ('workflows','create','workflows.create','Create workflow definitions'),
    ('workflows','update','workflows.update','Update workflow definitions'),
    ('workflows','delete','workflows.delete','Delete workflow definitions'),
    ('workflows','publish','workflows.publish','Publish workflow versions'),
    ('workflows','execute','workflows.execute','Start and process workflow executions'),
    ('workflows','cancel_execution','workflows.cancel_execution','Cancel workflow executions'),
    ('workflows','retry_execution','workflows.retry_execution','Retry failed workflow executions'),
    ('workflows','manage_approvals','workflows.manage_approvals','Approve or reject workflow approval tasks'),
    ('workflows','manage_webhooks','workflows.manage_webhooks','Manage workflow webhook endpoints'),
    ('workflows','manage_schedules','workflows.manage_schedules','Manage workflow schedules'),
    ('workflows','manage_integrations','workflows.manage_integrations','Manage workflow integrations'),
    ('workflows','manage_failures','workflows.manage_failures','Manage retry and dead-letter queues'),
    ('workflows','view_logs','workflows.view_logs','View workflow execution logs'),
    ('workflows','view_all','workflows.view_all','View all organization workflow records')
) as permission_data(module, action, code, description)
where not exists (
  select 1
  from public.permissions existing_permission
  where existing_permission.code = permission_data.code
);

create table if not exists public.workflow_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_code text not null,
  workflow_name text not null,
  description text,
  status text not null default 'draft'
    check (status in ('draft','active','inactive','archived')),
  current_version_id uuid,
  execution_timeout_seconds integer not null default 3600 check (execution_timeout_seconds>0),
  maximum_retry_count integer not null default 3 check (maximum_retry_count>=0),
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (organization_id,workflow_code)
);

create table if not exists public.workflow_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.workflow_definitions(id) on delete cascade,
  version_number integer not null check (version_number>0),
  status text not null default 'draft'
    check (status in ('draft','published','deprecated','archived')),
  definition jsonb not null default '{}',
  change_notes text,
  published_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workflow_id,version_number)
);

alter table public.workflow_definitions
  drop constraint if exists workflow_definitions_current_version_fk;
alter table public.workflow_definitions
  add constraint workflow_definitions_current_version_fk
  foreign key (current_version_id) references public.workflow_versions(id) on delete set null;

create table if not exists public.workflow_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.workflow_definitions(id) on delete cascade,
  workflow_version_id uuid not null references public.workflow_versions(id) on delete cascade,
  step_code text not null,
  step_name text not null,
  step_type text not null
    check (step_type in ('start','end','action','condition','delay','approval','webhook','integration','ai','subworkflow','parallel','join','transform')),
  sequence_number integer not null default 0,
  configuration jsonb not null default '{}',
  input_mapping jsonb not null default '{}',
  output_mapping jsonb not null default '{}',
  timeout_seconds integer not null default 300 check (timeout_seconds>0),
  retry_enabled boolean not null default true,
  retry_limit integer not null default 3 check (retry_limit>=0),
  retry_strategy text not null default 'exponential'
    check (retry_strategy in ('none','fixed','linear','exponential','custom')),
  retry_delay_seconds integer not null default 60 check (retry_delay_seconds>=0),
  continue_on_failure boolean not null default false,
  is_entry_step boolean not null default false,
  is_terminal_step boolean not null default false,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workflow_version_id,step_code)
);

create table if not exists public.workflow_step_transitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.workflow_definitions(id) on delete cascade,
  workflow_version_id uuid not null references public.workflow_versions(id) on delete cascade,
  from_step_id uuid not null references public.workflow_steps(id) on delete cascade,
  to_step_id uuid not null references public.workflow_steps(id) on delete cascade,
  transition_code text not null,
  transition_type text not null default 'success'
    check (transition_type in ('success','failure','condition','timeout','approved','rejected','always')),
  priority integer not null default 100,
  is_default boolean not null default false,
  condition_expression jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workflow_version_id,transition_code)
);

create table if not exists public.workflow_triggers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.workflow_definitions(id) on delete cascade,
  workflow_version_id uuid not null references public.workflow_versions(id) on delete cascade,
  trigger_code text not null,
  trigger_type text not null
    check (trigger_type in ('manual','event','webhook','schedule','record_change','integration')),
  event_name text,
  entity_type text,
  conditions jsonb not null default '{}',
  configuration jsonb not null default '{}',
  is_enabled boolean not null default true,
  priority integer not null default 100,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (workflow_version_id,trigger_code)
);

create table if not exists public.workflow_executions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.workflow_definitions(id) on delete restrict,
  workflow_version_id uuid not null references public.workflow_versions(id) on delete restrict,
  trigger_id uuid references public.workflow_triggers(id) on delete set null,
  parent_execution_id uuid references public.workflow_executions(id) on delete set null,
  status text not null default 'pending'
    check (status in ('pending','queued','running','waiting','paused','retrying','completed','partially_completed','failed','cancelled','compensating','compensated')),
  trigger_type text,
  trigger_reference text,
  entity_type text,
  entity_id uuid,
  idempotency_key text,
  correlation_id text,
  trace_id text not null default gen_random_uuid()::text,
  priority integer not null default 100,
  input_data jsonb not null default '{}',
  context_data jsonb not null default '{}',
  output_data jsonb not null default '{}',
  error_data jsonb not null default '{}',
  current_step_id uuid references public.workflow_steps(id) on delete set null,
  retry_count integer not null default 0,
  maximum_retry_count integer not null default 3,
  next_retry_at timestamptz,
  waiting_since timestamptz,
  pause_reason text,
  paused_at timestamptz,
  paused_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  timeout_at timestamptz,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists workflow_executions_idempotency_idx
on public.workflow_executions (organization_id,idempotency_key)
where idempotency_key is not null;

create table if not exists public.workflow_step_executions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_execution_id uuid not null references public.workflow_executions(id) on delete cascade,
  workflow_step_id uuid not null references public.workflow_steps(id) on delete restrict,
  status text not null default 'pending'
    check (status in ('pending','queued','running','waiting','paused','retrying','completed','failed','skipped','cancelled','timed_out')),
  retry_count integer not null default 0,
  next_retry_at timestamptz,
  input_data jsonb not null default '{}',
  output_data jsonb not null default '{}',
  error_data jsonb not null default '{}',
  transition_result text,
  worker_id text,
  lock_token text,
  locked_at timestamptz,
  heartbeat_at timestamptz,
  started_at timestamptz,
  waiting_since timestamptz,
  paused_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  duration_ms bigint,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workflow_execution_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_execution_id uuid not null references public.workflow_executions(id) on delete cascade,
  step_execution_id uuid references public.workflow_step_executions(id) on delete set null,
  log_level text not null default 'info'
    check (log_level in ('debug','info','warning','error','critical')),
  log_type text not null default 'execution',
  event_name text,
  message text,
  error_code text,
  error_message text,
  log_data jsonb not null default '{}',
  trace_id text,
  created_at timestamptz not null default now()
);

create table if not exists public.workflow_approval_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_execution_id uuid not null references public.workflow_executions(id) on delete cascade,
  step_execution_id uuid not null references public.workflow_step_executions(id) on delete cascade,
  approval_code text not null,
  title text not null,
  description text,
  status text not null default 'pending'
    check (status in ('pending','approved','rejected','cancelled','expired')),
  assigned_to uuid references auth.users(id) on delete set null,
  required_decisions integer not null default 1 check (required_decisions>0),
  approval_data jsonb not null default '{}',
  due_at timestamptz,
  decided_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workflow_approval_decisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  approval_task_id uuid not null references public.workflow_approval_tasks(id) on delete cascade,
  decided_by uuid not null references auth.users(id) on delete restrict,
  decision text not null check (decision in ('approved','rejected')),
  comments text,
  decision_data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (approval_task_id,decided_by)
);

create table if not exists public.workflow_retry_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_execution_id uuid not null references public.workflow_executions(id) on delete cascade,
  step_execution_id uuid references public.workflow_step_executions(id) on delete cascade,
  workflow_step_id uuid references public.workflow_steps(id) on delete set null,
  queue_status text not null default 'pending'
    check (queue_status in ('pending','claimed','processing','completed','failed','cancelled','dead_lettered')),
  retry_attempt integer not null default 1 check (retry_attempt>0),
  maximum_attempts integer not null default 3 check (maximum_attempts>0),
  retry_strategy text not null default 'exponential'
    check (retry_strategy in ('fixed','linear','exponential','custom')),
  retry_delay_seconds integer not null default 60 check (retry_delay_seconds>=0),
  scheduled_at timestamptz not null default now(),
  claimed_at timestamptz,
  claimed_by text,
  processing_started_at timestamptz,
  completed_at timestamptz,
  failure_code text,
  failure_message text,
  failure_data jsonb not null default '{}',
  retry_payload jsonb not null default '{}',
  priority integer not null default 100,
  lock_token text,
  lock_expires_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workflow_dead_letter_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_execution_id uuid not null references public.workflow_executions(id) on delete cascade,
  step_execution_id uuid references public.workflow_step_executions(id) on delete set null,
  workflow_id uuid references public.workflow_definitions(id) on delete set null,
  workflow_version_id uuid references public.workflow_versions(id) on delete set null,
  workflow_step_id uuid references public.workflow_steps(id) on delete set null,
  retry_queue_id uuid references public.workflow_retry_queue(id) on delete set null,
  dead_letter_status text not null default 'open'
    check (dead_letter_status in ('open','assigned','investigating','ready_for_replay','replaying','replayed','resolved','ignored','archived')),
  source_type text not null default 'retry_queue',
  failure_code text,
  failure_message text,
  failure_data jsonb not null default '{}',
  original_payload jsonb not null default '{}',
  execution_snapshot jsonb not null default '{}',
  retry_snapshot jsonb not null default '{}',
  retry_attempt integer not null default 0,
  maximum_attempts integer not null default 0,
  dead_letter_reason text,
  dead_lettered_at timestamptz not null default now(),
  dead_lettered_by uuid references auth.users(id) on delete set null,
  assigned_to uuid references auth.users(id) on delete set null,
  assigned_at timestamptz,
  investigation_notes text,
  resolution_type text,
  resolution_notes text,
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  replay_count integer not null default 0,
  last_replayed_at timestamptz,
  last_replayed_by uuid references auth.users(id) on delete set null,
  replay_execution_id uuid references public.workflow_executions(id) on delete set null,
  priority integer not null default 100,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workflow_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.workflow_definitions(id) on delete cascade,
  workflow_version_id uuid references public.workflow_versions(id) on delete set null,
  schedule_name text not null,
  schedule_type text not null default 'cron' check (schedule_type in ('cron','interval','once')),
  cron_expression text,
  interval_seconds integer,
  run_at timestamptz,
  timezone text not null default 'UTC',
  is_enabled boolean not null default true,
  next_run_at timestamptz,
  last_run_at timestamptz,
  input_data jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workflow_event_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.workflow_definitions(id) on delete cascade,
  workflow_version_id uuid references public.workflow_versions(id) on delete set null,
  event_name text not null,
  entity_type text,
  filter_conditions jsonb not null default '{}',
  is_enabled boolean not null default true,
  priority integer not null default 100,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists workflow_executions_org_status_idx
  on public.workflow_executions (organization_id,status,created_at desc);
create index if not exists workflow_step_executions_execution_idx
  on public.workflow_step_executions (workflow_execution_id,status);
create index if not exists workflow_retry_due_idx
  on public.workflow_retry_queue (queue_status,scheduled_at,priority);
create index if not exists workflow_dlq_org_status_idx
  on public.workflow_dead_letter_queue (organization_id,dead_letter_status,dead_lettered_at desc);
create unique index if not exists workflow_retry_active_unique_idx
  on public.workflow_retry_queue (workflow_execution_id,step_execution_id)
  where queue_status in ('pending','claimed','processing');

do $$
declare t text;
begin
  foreach t in array array[
    'workflow_definitions','workflow_versions','workflow_steps',
    'workflow_step_transitions','workflow_triggers','workflow_executions',
    'workflow_step_executions','workflow_approval_tasks',
    'workflow_retry_queue','workflow_dead_letter_queue',
    'workflow_schedules','workflow_event_subscriptions'
  ] loop
    execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
    execute format(
      'create trigger %I_set_updated_at before update on public.%I
       for each row execute function public.set_updated_at()',t,t
    );
  end loop;
end $$;

create or replace function public.calculate_workflow_retry_delay(
  requested_retry_strategy text,
  requested_base_delay_seconds integer,
  requested_retry_attempt integer
)
returns integer
language sql
immutable
security definer
set search_path=''
as $$
select least(
  greatest(
    floor(
      case coalesce(requested_retry_strategy,'fixed')
        when 'fixed' then greatest(coalesce(requested_base_delay_seconds,0),0)
        when 'linear' then greatest(coalesce(requested_base_delay_seconds,0),0)*greatest(coalesce(requested_retry_attempt,1),1)
        when 'exponential' then greatest(coalesce(requested_base_delay_seconds,0),0)*power(2,greatest(coalesce(requested_retry_attempt,1)-1,0))
        else greatest(coalesce(requested_base_delay_seconds,0),0)
      end
    )::integer,0
  ),86400
);
$$;

create or replace function public.start_workflow_execution(
  requested_workflow_id uuid,
  requested_input_data jsonb default '{}'::jsonb,
  requested_context_data jsonb default '{}'::jsonb,
  requested_trigger_type text default 'manual',
  requested_idempotency_key text default null,
  requested_priority integer default 100
)
returns public.workflow_executions
language plpgsql
security definer
set search_path=''
as $$
declare
  w public.workflow_definitions;
  v public.workflow_versions;
  s public.workflow_steps;
  e public.workflow_executions;
begin
  select * into w from public.workflow_definitions
  where id=requested_workflow_id and deleted_at is null;

  if not found then raise exception 'Workflow not found'; end if;
  if auth.role()<>'service_role'
     and not public.has_organization_permission(w.organization_id,'workflows.execute') then
    raise exception 'Permission denied';
  end if;
  if w.status<>'active' then raise exception 'Workflow is not active'; end if;

  if requested_idempotency_key is not null then
    select * into e from public.workflow_executions
    where organization_id=w.organization_id
      and idempotency_key=requested_idempotency_key
    limit 1;
    if found then return e; end if;
  end if;

  select * into v from public.workflow_versions
  where id=w.current_version_id and status='published';
  if not found then raise exception 'Published version not found'; end if;

  select * into s from public.workflow_steps
  where workflow_version_id=v.id and is_entry_step=true
  limit 1;
  if not found then raise exception 'Entry step not found'; end if;

  insert into public.workflow_executions (
    organization_id,workflow_id,workflow_version_id,status,
    trigger_type,idempotency_key,priority,input_data,context_data,
    current_step_id,maximum_retry_count,started_at,timeout_at,created_by
  ) values (
    w.organization_id,w.id,v.id,'running',
    requested_trigger_type,requested_idempotency_key,requested_priority,
    coalesce(requested_input_data,'{}'::jsonb),
    coalesce(requested_context_data,'{}'::jsonb),
    s.id,w.maximum_retry_count,now(),
    now()+make_interval(secs=>w.execution_timeout_seconds),auth.uid()
  ) returning * into e;

  insert into public.workflow_step_executions (
    organization_id,workflow_execution_id,workflow_step_id,status,input_data,started_at
  ) values (
    e.organization_id,e.id,s.id,'running',e.input_data,now()
  );

  return e;
end;
$$;

create or replace function public.enqueue_workflow_retry(
  requested_workflow_execution_id uuid,
  requested_step_execution_id uuid default null,
  requested_failure_code text default null,
  requested_failure_message text default null,
  requested_failure_data jsonb default '{}'::jsonb
)
returns public.workflow_retry_queue
language plpgsql
security definer
set search_path=''
as $$
declare
  e public.workflow_executions;
  se public.workflow_step_executions;
  s public.workflow_steps;
  a integer;
  m integer;
  d integer;
  r public.workflow_retry_queue;
begin
  select * into e from public.workflow_executions
  where id=requested_workflow_execution_id for update;
  if not found then raise exception 'Execution not found'; end if;

  if requested_step_execution_id is not null then
    select * into se from public.workflow_step_executions
    where id=requested_step_execution_id and workflow_execution_id=e.id;
    if not found then raise exception 'Step execution not found'; end if;
    select * into s from public.workflow_steps where id=se.workflow_step_id;
    a:=se.retry_count+1;
    m:=greatest(s.retry_limit,1);
    d:=public.calculate_workflow_retry_delay(s.retry_strategy,s.retry_delay_seconds,a);
  else
    a:=e.retry_count+1;
    m:=greatest(e.maximum_retry_count,1);
    d:=public.calculate_workflow_retry_delay('exponential',60,a);
  end if;

  if a>m then raise exception 'Maximum retry attempts exhausted'; end if;

  insert into public.workflow_retry_queue (
    organization_id,workflow_execution_id,step_execution_id,workflow_step_id,
    retry_attempt,maximum_attempts,retry_strategy,retry_delay_seconds,
    scheduled_at,failure_code,failure_message,failure_data,retry_payload,priority
  ) values (
    e.organization_id,e.id,requested_step_execution_id,s.id,
    a,m,coalesce(s.retry_strategy,'exponential'),coalesce(s.retry_delay_seconds,60),
    now()+make_interval(secs=>d),
    requested_failure_code,requested_failure_message,
    coalesce(requested_failure_data,'{}'::jsonb),
    coalesce(se.input_data,e.input_data,'{}'::jsonb),e.priority
  ) returning * into r;

  update public.workflow_executions
  set status='retrying',retry_count=greatest(retry_count,a),
      next_retry_at=r.scheduled_at,updated_at=now()
  where id=e.id;

  if requested_step_execution_id is not null then
    update public.workflow_step_executions
    set status='retrying',retry_count=a,next_retry_at=r.scheduled_at,updated_at=now()
    where id=requested_step_execution_id;
  end if;

  return r;
end;
$$;

create or replace function public.cancel_workflow_execution(
  requested_execution_id uuid,
  requested_reason text default 'Cancelled manually'
)
returns public.workflow_executions
language plpgsql
security definer
set search_path=''
as $$
declare e public.workflow_executions;
begin
  select * into e from public.workflow_executions
  where id=requested_execution_id for update;
  if not found then raise exception 'Execution not found'; end if;

  if auth.role()<>'service_role'
     and not public.has_organization_permission(e.organization_id,'workflows.cancel_execution') then
    raise exception 'Permission denied';
  end if;

  if e.status in ('completed','partially_completed','cancelled','compensated') then
    return e;
  end if;

  update public.workflow_step_executions
  set status='cancelled',cancelled_at=now(),
      worker_id=null,lock_token=null,locked_at=null,heartbeat_at=null,updated_at=now()
  where workflow_execution_id=e.id
    and status not in ('completed','failed','skipped','cancelled');

  update public.workflow_retry_queue
  set queue_status='cancelled',completed_at=now(),
      failure_code='EXECUTION_CANCELLED',failure_message=requested_reason,
      lock_token=null,lock_expires_at=null,updated_at=now()
  where workflow_execution_id=e.id
    and queue_status in ('pending','claimed','processing');

  update public.workflow_approval_tasks
  set status='cancelled',decided_at=now(),updated_at=now()
  where workflow_execution_id=e.id and status='pending';

  update public.workflow_executions
  set status='cancelled',cancellation_reason=requested_reason,
      cancelled_at=now(),cancelled_by=auth.uid(),
      current_step_id=null,next_retry_at=null,waiting_since=null,updated_at=now()
  where id=e.id returning * into e;

  return e;
end;
$$;

create or replace function public.pause_workflow_execution(
  requested_execution_id uuid,
  requested_reason text default 'Paused manually'
)
returns public.workflow_executions
language plpgsql
security definer
set search_path=''
as $$
declare e public.workflow_executions;
begin
  select * into e from public.workflow_executions
  where id=requested_execution_id for update;
  if not found then raise exception 'Execution not found'; end if;
  if e.status not in ('running','waiting','retrying','queued') then
    raise exception 'Execution cannot be paused';
  end if;

  update public.workflow_step_executions
  set status='paused',paused_at=now(),updated_at=now()
  where workflow_execution_id=e.id
    and status in ('running','waiting','retrying','queued');

  update public.workflow_executions
  set status='paused',pause_reason=requested_reason,
      paused_at=now(),paused_by=auth.uid(),updated_at=now()
  where id=e.id returning * into e;

  return e;
end;
$$;

create or replace function public.resume_workflow_execution(
  requested_execution_id uuid
)
returns public.workflow_executions
language plpgsql
security definer
set search_path=''
as $$
declare e public.workflow_executions;
begin
  select * into e from public.workflow_executions
  where id=requested_execution_id for update;
  if not found then raise exception 'Execution not found'; end if;
  if e.status<>'paused' then raise exception 'Execution is not paused'; end if;

  update public.workflow_step_executions
  set status=case
      when waiting_since is not null then 'waiting'
      when next_retry_at is not null then 'retrying'
      else 'running'
    end,
    paused_at=null,updated_at=now()
  where workflow_execution_id=e.id and status='paused';

  update public.workflow_executions
  set status=case
      when waiting_since is not null then 'waiting'
      when next_retry_at is not null then 'retrying'
      else 'running'
    end,
    pause_reason=null,paused_at=null,paused_by=null,updated_at=now()
  where id=e.id returning * into e;

  return e;
end;
$$;

alter table public.workflow_definitions enable row level security;
alter table public.workflow_versions enable row level security;
alter table public.workflow_steps enable row level security;
alter table public.workflow_step_transitions enable row level security;
alter table public.workflow_triggers enable row level security;
alter table public.workflow_executions enable row level security;
alter table public.workflow_step_executions enable row level security;
alter table public.workflow_execution_logs enable row level security;
alter table public.workflow_approval_tasks enable row level security;
alter table public.workflow_approval_decisions enable row level security;
alter table public.workflow_retry_queue enable row level security;
alter table public.workflow_dead_letter_queue enable row level security;
alter table public.workflow_schedules enable row level security;
alter table public.workflow_event_subscriptions enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'workflow_definitions','workflow_versions','workflow_steps',
    'workflow_step_transitions','workflow_triggers','workflow_executions',
    'workflow_step_executions','workflow_execution_logs',
    'workflow_approval_tasks','workflow_approval_decisions',
    'workflow_retry_queue','workflow_dead_letter_queue',
    'workflow_schedules','workflow_event_subscriptions'
  ] loop
    execute format('drop policy if exists %I_select_policy on public.%I',t,t);
    execute format(
      'create policy %I_select_policy on public.%I
       for select to authenticated
       using (
         public.has_organization_permission(organization_id,''workflows.view'')
         or public.has_organization_permission(organization_id,''workflows.view_all'')
       )',t,t
    );
    execute format('drop policy if exists %I_service_policy on public.%I',t,t);
    execute format(
      'create policy %I_service_policy on public.%I
       for all to service_role using (true) with check (true)',t,t
    );
  end loop;
end $$;

grant select on
  public.workflow_definitions,public.workflow_versions,public.workflow_steps,
  public.workflow_step_transitions,public.workflow_triggers,
  public.workflow_executions,public.workflow_step_executions,
  public.workflow_execution_logs,public.workflow_approval_tasks,
  public.workflow_approval_decisions,public.workflow_retry_queue,
  public.workflow_dead_letter_queue,public.workflow_schedules,
  public.workflow_event_subscriptions
to authenticated;

grant all on
  public.workflow_definitions,public.workflow_versions,public.workflow_steps,
  public.workflow_step_transitions,public.workflow_triggers,
  public.workflow_executions,public.workflow_step_executions,
  public.workflow_execution_logs,public.workflow_approval_tasks,
  public.workflow_approval_decisions,public.workflow_retry_queue,
  public.workflow_dead_letter_queue,public.workflow_schedules,
  public.workflow_event_subscriptions
to service_role;

revoke all on function public.calculate_workflow_retry_delay(text,integer,integer) from public;
revoke all on function public.start_workflow_execution(uuid,jsonb,jsonb,text,text,integer) from public;
revoke all on function public.enqueue_workflow_retry(uuid,uuid,text,text,jsonb) from public;
revoke all on function public.cancel_workflow_execution(uuid,text) from public;
revoke all on function public.pause_workflow_execution(uuid,text) from public;
revoke all on function public.resume_workflow_execution(uuid) from public;

grant execute on function public.start_workflow_execution(uuid,jsonb,jsonb,text,text,integer)
to authenticated,service_role;
grant execute on function public.enqueue_workflow_retry(uuid,uuid,text,text,jsonb)
to authenticated,service_role;
grant execute on function public.cancel_workflow_execution(uuid,text)
to authenticated,service_role;
grant execute on function public.pause_workflow_execution(uuid,text)
to authenticated,service_role;
grant execute on function public.resume_workflow_execution(uuid)
to authenticated,service_role;

commit;