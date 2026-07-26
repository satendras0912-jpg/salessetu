-- ============================================================
-- SalesSetu Enterprise
-- Migration 012: Assignment Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   009_workflow_engine_v2.sql
--   011_lead_validation_engine_production_v2.sql
--
-- Scope:
--   • Agent and team routing
--   • Round-robin, weighted, capacity and skill-based assignment
--   • Project, source, language, geography and budget rules
--   • Working hours, leave and availability
--   • Assignment queue, recommendations, history and SLA
--   • Reassignment and escalation
--   • Workflow/n8n event outbox
--   • Analytics, RLS, permissions and health checks
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
  permission_data.module,
  permission_data.action,
  permission_data.code,
  permission_data.description
from (
  values
    ('assignment','view','assignment.view','View assignment records and queues'),
    ('assignment','view_all','assignment.view_all','View all organization assignment records'),
    ('assignment','create','assignment.create','Create assignment requests'),
    ('assignment','execute','assignment.execute','Execute automatic assignment'),
    ('assignment','manual_assign','assignment.manual_assign','Assign leads manually'),
    ('assignment','reassign','assignment.reassign','Reassign assigned leads'),
    ('assignment','unassign','assignment.unassign','Unassign leads'),
    ('assignment','manage_teams','assignment.manage_teams','Manage assignment teams'),
    ('assignment','manage_agents','assignment.manage_agents','Manage assignment agent profiles'),
    ('assignment','manage_rules','assignment.manage_rules','Manage routing rules'),
    ('assignment','manage_capacity','assignment.manage_capacity','Manage agent capacities'),
    ('assignment','manage_schedule','assignment.manage_schedule','Manage working schedules and leave'),
    ('assignment','manage_sla','assignment.manage_sla','Manage assignment SLA and escalation'),
    ('assignment','override','assignment.override','Override assignment recommendations'),
    ('assignment','view_analytics','assignment.view_analytics','View assignment analytics'),
    ('assignment','view_logs','assignment.view_logs','View assignment logs')
) as permission_data(module,action,code,description)
where not exists (
  select 1
  from public.permissions p
  where p.code = permission_data.code
);

-- ============================================================
-- 2. COMPATIBILITY COLUMNS ON LEADS
-- ============================================================

alter table public.leads
  add column if not exists assigned_to uuid references auth.users(id) on delete set null,
  add column if not exists assigned_team_id uuid,
  add column if not exists assignment_status text,
  add column if not exists assigned_at timestamptz,
  add column if not exists assignment_due_at timestamptz,
  add column if not exists assignment_metadata jsonb not null default '{}';

create index if not exists leads_assignment_agent_idx
  on public.leads (organization_id,assigned_to,assigned_at desc);

create index if not exists leads_assignment_status_idx
  on public.leads (organization_id,assignment_status,created_at desc);

-- ============================================================
-- 3. ASSIGNMENT TEAMS
-- ============================================================

create table if not exists public.assignment_teams (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  team_code text not null,
  team_name text not null,
  description text,

  team_type text not null default 'sales'
    check (team_type in ('sales','presales','inside_sales','field_sales','site_visit','closing','customer_success','custom')),

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  default_assignment_strategy text not null default 'round_robin'
    check (
      default_assignment_strategy in (
        'round_robin',
        'weighted_round_robin',
        'least_loaded',
        'capacity_based',
        'skill_based',
        'priority_based',
        'random',
        'manual'
      )
    ),

  timezone text not null default 'Asia/Kolkata',
  maximum_open_leads integer,
  daily_assignment_limit integer,
  response_sla_minutes integer not null default 15,
  acceptance_sla_minutes integer not null default 10,

  project_ids uuid[] not null default '{}',
  supported_languages text[] not null default '{}',
  supported_locations text[] not null default '{}',
  supported_sources text[] not null default '{}',

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,team_code)
);

alter table public.leads
  drop constraint if exists leads_assigned_team_id_fkey;

alter table public.leads
  add constraint leads_assigned_team_id_fkey
  foreign key (assigned_team_id)
  references public.assignment_teams(id)
  on delete set null;

create index if not exists assignment_teams_org_status_idx
  on public.assignment_teams (organization_id,status,team_type);

-- ============================================================
-- 4. AGENT PROFILES
-- ============================================================

create table if not exists public.assignment_agent_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  agent_code text,
  display_name text,
  status text not null default 'active'
    check (status in ('active','inactive','suspended','on_leave','offline')),

  availability_status text not null default 'available'
    check (availability_status in ('available','busy','away','offline','on_leave')),

  timezone text not null default 'Asia/Kolkata',

  maximum_open_leads integer not null default 50
    check (maximum_open_leads >= 0),

  daily_assignment_limit integer not null default 25
    check (daily_assignment_limit >= 0),

  hourly_assignment_limit integer
    check (hourly_assignment_limit is null or hourly_assignment_limit >= 0),

  minimum_lead_score numeric(8,2) not null default 0,
  maximum_lead_score numeric(8,2) not null default 100,

  assignment_weight numeric(8,2) not null default 1
    check (assignment_weight > 0),

  priority_rank integer not null default 100,

  languages text[] not null default '{}',
  locations text[] not null default '{}',
  source_expertise text[] not null default '{}',
  project_ids uuid[] not null default '{}',
  builder_ids uuid[] not null default '{}',
  skills text[] not null default '{}',

  budget_min numeric(18,2),
  budget_max numeric(18,2),

  auto_assignment_enabled boolean not null default true,
  accept_new_leads boolean not null default true,

  current_open_leads integer not null default 0,
  assigned_today integer not null default 0,
  assigned_this_hour integer not null default 0,

  last_assigned_at timestamptz,
  last_activity_at timestamptz,
  counters_reset_at timestamptz not null default now(),

  performance_score numeric(8,2) not null default 50,
  response_score numeric(8,2) not null default 50,
  conversion_score numeric(8,2) not null default 50,
  quality_score numeric(8,2) not null default 50,

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,user_id),
  unique (organization_id,agent_code),
  check (maximum_lead_score >= minimum_lead_score),
  check (budget_max is null or budget_min is null or budget_max >= budget_min)
);

create index if not exists assignment_agent_profiles_eligibility_idx
  on public.assignment_agent_profiles (
    organization_id,status,availability_status,accept_new_leads,auto_assignment_enabled
  );

create index if not exists assignment_agent_profiles_load_idx
  on public.assignment_agent_profiles (
    organization_id,current_open_leads,assigned_today,last_assigned_at
  );

-- ============================================================
-- 5. TEAM MEMBERS
-- ============================================================

create table if not exists public.assignment_team_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  team_id uuid not null references public.assignment_teams(id) on delete cascade,
  agent_profile_id uuid not null references public.assignment_agent_profiles(id) on delete cascade,

  role text not null default 'member'
    check (role in ('leader','manager','member','backup')),

  status text not null default 'active'
    check (status in ('active','inactive','temporary','archived')),

  assignment_weight numeric(8,2) not null default 1
    check (assignment_weight > 0),

  priority_rank integer not null default 100,
  capacity_override integer,
  daily_limit_override integer,

  active_from timestamptz not null default now(),
  active_until timestamptz,

  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (team_id,agent_profile_id),
  check (active_until is null or active_until > active_from)
);

create index if not exists assignment_team_members_team_idx
  on public.assignment_team_members (organization_id,team_id,status,priority_rank);

-- ============================================================
-- 6. AGENT WORKING HOURS
-- ============================================================

create table if not exists public.assignment_agent_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agent_profile_id uuid not null references public.assignment_agent_profiles(id) on delete cascade,

  day_of_week integer not null check (day_of_week between 0 and 6),
  start_time time not null,
  end_time time not null,

  timezone text not null default 'Asia/Kolkata',
  is_working_day boolean not null default true,

  effective_from date,
  effective_until date,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (agent_profile_id,day_of_week,start_time,end_time),
  check (end_time > start_time),
  check (effective_until is null or effective_from is null or effective_until >= effective_from)
);

create index if not exists assignment_agent_schedules_lookup_idx
  on public.assignment_agent_schedules (agent_profile_id,day_of_week,is_working_day);

-- ============================================================
-- 7. AGENT LEAVE / BLOCKED WINDOWS
-- ============================================================

create table if not exists public.assignment_agent_unavailability (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  agent_profile_id uuid not null references public.assignment_agent_profiles(id) on delete cascade,

  unavailability_type text not null default 'leave'
    check (unavailability_type in ('leave','meeting','training','break','manual_block','system_block','custom')),

  starts_at timestamptz not null,
  ends_at timestamptz not null,

  reason text,
  status text not null default 'active'
    check (status in ('active','cancelled','expired')),

  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (ends_at > starts_at)
);

create index if not exists assignment_agent_unavailability_lookup_idx
  on public.assignment_agent_unavailability (
    organization_id,agent_profile_id,status,starts_at,ends_at
  );

-- ============================================================
-- 8. ROUTING RULES
-- ============================================================

create table if not exists public.assignment_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  rule_code text not null,
  rule_name text not null,
  description text,

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  priority integer not null default 100,
  stop_on_match boolean not null default true,

  target_team_id uuid references public.assignment_teams(id) on delete set null,
  target_agent_profile_id uuid references public.assignment_agent_profiles(id) on delete set null,

  strategy text not null default 'round_robin'
    check (
      strategy in (
        'round_robin',
        'weighted_round_robin',
        'least_loaded',
        'capacity_based',
        'skill_based',
        'priority_based',
        'random',
        'manual'
      )
    ),

  source_types text[] not null default '{}',
  campaign_ids text[] not null default '{}',
  project_ids uuid[] not null default '{}',
  builder_ids uuid[] not null default '{}',
  languages text[] not null default '{}',
  locations text[] not null default '{}',
  lead_statuses text[] not null default '{}',
  validation_decisions text[] not null default '{}',

  minimum_trust_score numeric(8,2),
  maximum_trust_score numeric(8,2),
  minimum_budget numeric(18,2),
  maximum_budget numeric(18,2),

  working_hours_only boolean not null default true,
  allow_fallback boolean not null default true,

  condition_expression jsonb not null default '{}',
  scoring_configuration jsonb not null default '{}',
  assignment_configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  active_from timestamptz not null default now(),
  active_until timestamptz,

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,rule_code),
  check (maximum_trust_score is null or minimum_trust_score is null or maximum_trust_score >= minimum_trust_score),
  check (maximum_budget is null or minimum_budget is null or maximum_budget >= minimum_budget),
  check (active_until is null or active_until > active_from)
);

create index if not exists assignment_rules_execution_idx
  on public.assignment_rules (organization_id,status,priority,active_from);

-- ============================================================
-- 9. ASSIGNMENT REQUESTS / QUEUE
-- ============================================================

create table if not exists public.assignment_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,

  validation_result_id uuid references public.lead_validation_results(id) on delete set null,
  workflow_execution_id uuid references public.workflow_executions(id) on delete set null,

  source_type text not null default 'system'
    check (source_type in ('lead_created','validation_approved','workflow','n8n','api','manual','reassignment','system')),

  source_reference text,
  idempotency_key text,

  status text not null default 'queued'
    check (
      status in (
        'pending','queued','evaluating','recommended','assigned',
        'manual_review','waiting','failed','cancelled','expired'
      )
    ),

  priority integer not null default 100,
  requested_strategy text,

  preferred_team_id uuid references public.assignment_teams(id) on delete set null,
  preferred_agent_profile_id uuid references public.assignment_agent_profiles(id) on delete set null,

  assignment_context jsonb not null default '{}',
  normalized_context jsonb not null default '{}',
  recommendation_output jsonb not null default '{}',
  error_data jsonb not null default '{}',

  attempts integer not null default 0,
  maximum_attempts integer not null default 3 check (maximum_attempts between 1 and 10),
  next_retry_at timestamptz,

  queued_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  expires_at timestamptz,

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists assignment_requests_idempotency_idx
  on public.assignment_requests (organization_id,idempotency_key)
  where idempotency_key is not null;

create index if not exists assignment_requests_queue_idx
  on public.assignment_requests (status,priority,queued_at,created_at)
  where status in ('pending','queued','waiting');

create index if not exists assignment_requests_lead_idx
  on public.assignment_requests (organization_id,lead_id,created_at desc);

-- ============================================================
-- 10. CANDIDATE RECOMMENDATIONS
-- ============================================================

create table if not exists public.assignment_candidates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  assignment_request_id uuid not null references public.assignment_requests(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,

  team_id uuid references public.assignment_teams(id) on delete set null,
  agent_profile_id uuid not null references public.assignment_agent_profiles(id) on delete cascade,

  rank integer not null,
  eligible boolean not null default true,

  total_score numeric(10,4) not null default 0,
  capacity_score numeric(10,4) not null default 0,
  skill_score numeric(10,4) not null default 0,
  project_score numeric(10,4) not null default 0,
  source_score numeric(10,4) not null default 0,
  language_score numeric(10,4) not null default 0,
  location_score numeric(10,4) not null default 0,
  performance_score numeric(10,4) not null default 0,
  availability_score numeric(10,4) not null default 0,
  fairness_score numeric(10,4) not null default 0,

  eligibility_reasons jsonb not null default '[]',
  rejection_reasons jsonb not null default '[]',
  score_breakdown jsonb not null default '{}',

  selected boolean not null default false,
  selected_at timestamptz,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),

  unique (assignment_request_id,agent_profile_id)
);

create index if not exists assignment_candidates_rank_idx
  on public.assignment_candidates (assignment_request_id,eligible,rank,total_score desc);

-- ============================================================
-- 11. ASSIGNMENTS
-- ============================================================

create table if not exists public.lead_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  assignment_request_id uuid references public.assignment_requests(id) on delete set null,

  team_id uuid references public.assignment_teams(id) on delete set null,
  agent_profile_id uuid not null references public.assignment_agent_profiles(id) on delete restrict,
  assigned_user_id uuid not null references auth.users(id) on delete restrict,

  assignment_type text not null default 'automatic'
    check (assignment_type in ('automatic','manual','reassignment','escalation','fallback','import')),

  strategy text not null,
  status text not null default 'assigned'
    check (
      status in (
        'assigned','accepted','rejected','active','completed',
        'reassigned','unassigned','expired','cancelled'
      )
    ),

  priority integer not null default 100,
  assignment_score numeric(10,4),

  assigned_at timestamptz not null default now(),
  acceptance_due_at timestamptz,
  response_due_at timestamptz,

  accepted_at timestamptz,
  rejected_at timestamptz,
  first_response_at timestamptz,
  completed_at timestamptz,
  unassigned_at timestamptz,

  previous_assignment_id uuid references public.lead_assignments(id) on delete set null,
  reassignment_reason text,

  rule_id uuid references public.assignment_rules(id) on delete set null,

  assignment_reason text,
  assignment_context jsonb not null default '{}',
  score_breakdown jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists lead_assignments_one_active_idx
  on public.lead_assignments (organization_id,lead_id)
  where status in ('assigned','accepted','active');

create index if not exists lead_assignments_agent_idx
  on public.lead_assignments (organization_id,agent_profile_id,status,assigned_at desc);

create index if not exists lead_assignments_sla_idx
  on public.lead_assignments (organization_id,status,acceptance_due_at,response_due_at);

-- ============================================================
-- 12. ASSIGNMENT HISTORY
-- ============================================================

create table if not exists public.assignment_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  assignment_id uuid references public.lead_assignments(id) on delete set null,
  assignment_request_id uuid references public.assignment_requests(id) on delete set null,

  event_type text not null
    check (
      event_type in (
        'requested','evaluated','recommended','assigned','accepted',
        'rejected','first_response','completed','unassigned',
        'reassigned','escalated','expired','failed','overridden'
      )
    ),

  from_agent_profile_id uuid references public.assignment_agent_profiles(id) on delete set null,
  to_agent_profile_id uuid references public.assignment_agent_profiles(id) on delete set null,
  from_team_id uuid references public.assignment_teams(id) on delete set null,
  to_team_id uuid references public.assignment_teams(id) on delete set null,

  reason text,
  event_data jsonb not null default '{}',

  actor_type text not null default 'system'
    check (actor_type in ('system','user','workflow','n8n','api','scheduler')),

  actor_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists assignment_history_lead_idx
  on public.assignment_history (organization_id,lead_id,created_at desc);

-- ============================================================
-- 13. SLA AND ESCALATION RULES
-- ============================================================

create table if not exists public.assignment_sla_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  policy_code text not null,
  policy_name text not null,
  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  applies_to_team_id uuid references public.assignment_teams(id) on delete cascade,
  lead_priorities integer[] not null default '{}',

  acceptance_sla_minutes integer not null default 10,
  first_response_sla_minutes integer not null default 15,
  maximum_reassignments integer not null default 3,

  on_acceptance_breach text not null default 'reassign'
    check (on_acceptance_breach in ('notify','reassign','escalate','manual_review','ignore')),

  on_response_breach text not null default 'escalate'
    check (on_response_breach in ('notify','reassign','escalate','manual_review','ignore')),

  escalation_team_id uuid references public.assignment_teams(id) on delete set null,
  escalation_agent_profile_id uuid references public.assignment_agent_profiles(id) on delete set null,

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,policy_code)
);

-- ============================================================
-- 14. EVENT OUTBOX
-- ============================================================

create table if not exists public.assignment_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  assignment_request_id uuid references public.assignment_requests(id) on delete set null,
  assignment_id uuid references public.lead_assignments(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,

  event_name text not null,
  destination text not null default 'internal'
    check (destination in ('internal','workflow_engine','n8n','webhook','notification','analytics','audit')),

  status text not null default 'pending'
    check (status in ('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),

  priority integer not null default 100,
  idempotency_key text,
  payload jsonb not null default '{}',
  headers jsonb not null default '{}',

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

create unique index if not exists assignment_event_outbox_idempotency_idx
  on public.assignment_event_outbox (organization_id,idempotency_key)
  where idempotency_key is not null;

create index if not exists assignment_event_outbox_queue_idx
  on public.assignment_event_outbox (status,available_at,priority,created_at)
  where status in ('pending','failed');

-- ============================================================
-- 15. LOGS
-- ============================================================

create table if not exists public.assignment_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  assignment_request_id uuid references public.assignment_requests(id) on delete cascade,
  assignment_id uuid references public.lead_assignments(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,

  log_level text not null default 'info'
    check (log_level in ('debug','info','warning','error','critical')),

  event_name text,
  message text,
  error_code text,
  error_message text,
  log_data jsonb not null default '{}',

  trace_id text,
  correlation_id text,
  created_at timestamptz not null default now()
);

create index if not exists assignment_logs_org_created_idx
  on public.assignment_logs (organization_id,created_at desc);

-- ============================================================
-- 16. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'assignment_teams',
    'assignment_agent_profiles',
    'assignment_team_members',
    'assignment_agent_schedules',
    'assignment_agent_unavailability',
    'assignment_rules',
    'assignment_requests',
    'lead_assignments',
    'assignment_sla_policies',
    'assignment_event_outbox'
  ]
  loop
    execute format(
      'drop trigger if exists %I_set_updated_at on public.%I',
      target_table,target_table
    );

    execute format(
      'create trigger %I_set_updated_at
       before update on public.%I
       for each row execute function public.set_updated_at()',
      target_table,target_table
    );
  end loop;
end;
$$;

-- ============================================================
-- 17. HELPER: LEAD SNAPSHOT
-- ============================================================

create or replace function public.get_assignment_lead_snapshot(
  requested_lead_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  payload jsonb;
begin
  select to_jsonb(l)
  into payload
  from public.leads l
  where l.id = requested_lead_id;

  if payload is null then
    raise exception 'Lead not found';
  end if;

  return payload;
end;
$$;

revoke all on function public.get_assignment_lead_snapshot(uuid) from public;
grant execute on function public.get_assignment_lead_snapshot(uuid) to authenticated,service_role;

-- ============================================================
-- 18. HELPER: AGENT AVAILABILITY
-- ============================================================

create or replace function public.is_assignment_agent_available(
  requested_agent_profile_id uuid,
  requested_at timestamptz default now()
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  agent_record public.assignment_agent_profiles;
  local_timestamp timestamp;
  local_day integer;
  local_time time;
  schedule_exists boolean;
  blocked boolean;
begin
  select *
  into agent_record
  from public.assignment_agent_profiles
  where id = requested_agent_profile_id;

  if not found then
    return false;
  end if;

  if agent_record.status <> 'active'
    or agent_record.availability_status <> 'available'
    or not agent_record.accept_new_leads
    or not agent_record.auto_assignment_enabled then
    return false;
  end if;

  if agent_record.current_open_leads >= agent_record.maximum_open_leads
    or agent_record.assigned_today >= agent_record.daily_assignment_limit
    or (
      agent_record.hourly_assignment_limit is not null
      and agent_record.assigned_this_hour >= agent_record.hourly_assignment_limit
    ) then
    return false;
  end if;

  select exists (
    select 1
    from public.assignment_agent_unavailability u
    where u.agent_profile_id = agent_record.id
      and u.status = 'active'
      and requested_at >= u.starts_at
      and requested_at < u.ends_at
  )
  into blocked;

  if blocked then
    return false;
  end if;

  local_timestamp := requested_at at time zone agent_record.timezone;
  local_day := extract(dow from local_timestamp)::integer;
  local_time := local_timestamp::time;

  select exists (
    select 1
    from public.assignment_agent_schedules s
    where s.agent_profile_id = agent_record.id
      and s.day_of_week = local_day
      and s.is_working_day = true
      and local_time >= s.start_time
      and local_time < s.end_time
      and (s.effective_from is null or local_timestamp::date >= s.effective_from)
      and (s.effective_until is null or local_timestamp::date <= s.effective_until)
  )
  into schedule_exists;

  if exists (
    select 1
    from public.assignment_agent_schedules s
    where s.agent_profile_id = agent_record.id
  ) then
    return schedule_exists;
  end if;

  return true;
end;
$$;

revoke all on function public.is_assignment_agent_available(uuid,timestamptz) from public;
grant execute on function public.is_assignment_agent_available(uuid,timestamptz) to authenticated,service_role;

-- ============================================================
-- 19. CREATE ASSIGNMENT REQUEST
-- ============================================================

create or replace function public.create_assignment_request(
  requested_lead_id uuid,
  requested_source_type text default 'manual',
  requested_source_reference text default null,
  requested_idempotency_key text default null,
  requested_priority integer default 100,
  requested_preferred_team_id uuid default null,
  requested_preferred_agent_profile_id uuid default null,
  requested_context jsonb default '{}'::jsonb,
  requested_validation_result_id uuid default null,
  requested_workflow_execution_id uuid default null
)
returns public.assignment_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_value uuid;
  existing_request public.assignment_requests;
  created_request public.assignment_requests;
  lead_snapshot jsonb;
begin
  select l.organization_id
  into organization_value
  from public.leads l
  where l.id = requested_lead_id;

  if organization_value is null then
    raise exception 'Lead not found or organization missing';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(organization_value,'assignment.create') then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_request
    from public.assignment_requests r
    where r.organization_id = organization_value
      and r.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_request;
    end if;
  end if;

  lead_snapshot := public.get_assignment_lead_snapshot(requested_lead_id);

  insert into public.assignment_requests (
    organization_id,lead_id,validation_result_id,workflow_execution_id,
    source_type,source_reference,idempotency_key,status,priority,
    preferred_team_id,preferred_agent_profile_id,
    assignment_context,normalized_context,created_by,updated_by
  )
  values (
    organization_value,requested_lead_id,requested_validation_result_id,
    requested_workflow_execution_id,requested_source_type,
    requested_source_reference,requested_idempotency_key,'queued',
    requested_priority,requested_preferred_team_id,
    requested_preferred_agent_profile_id,
    coalesce(requested_context,'{}'::jsonb),
    jsonb_build_object('lead_snapshot',lead_snapshot),
    auth.uid(),auth.uid()
  )
  returning * into created_request;

  insert into public.assignment_history (
    organization_id,lead_id,assignment_request_id,event_type,
    reason,event_data,actor_type,actor_user_id
  )
  values (
    organization_value,requested_lead_id,created_request.id,'requested',
    'Assignment request created',
    jsonb_build_object('source_type',requested_source_type,'priority',requested_priority),
    case when auth.role()='service_role' then 'system' else 'user' end,
    auth.uid()
  );

  return created_request;
end;
$$;

revoke all on function public.create_assignment_request(
  uuid,text,text,text,integer,uuid,uuid,jsonb,uuid,uuid
) from public;

grant execute on function public.create_assignment_request(
  uuid,text,text,text,integer,uuid,uuid,jsonb,uuid,uuid
) to authenticated,service_role;

-- ============================================================
-- 20. CLAIM ASSIGNMENT REQUEST
-- ============================================================

create or replace function public.claim_assignment_request(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.assignment_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_request public.assignment_requests;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim assignment requests';
  end if;

  select *
  into target_request
  from public.assignment_requests r
  where r.status in ('pending','queued','waiting')
    and (r.next_retry_at is null or r.next_retry_at <= now())
    and (r.expires_at is null or r.expires_at > now())
    and (requested_organization_id is null or r.organization_id = requested_organization_id)
  order by r.priority,r.queued_at,r.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.assignment_requests
  set
    status='evaluating',
    attempts=attempts+1,
    started_at=coalesce(started_at,now()),
    metadata=metadata||jsonb_build_object(
      'worker_id',requested_worker_id,
      'lock_token',gen_random_uuid()::text,
      'lock_expires_at',now()+make_interval(secs=>greatest(requested_lock_seconds,1))
    ),
    updated_at=now()
  where id=target_request.id
  returning * into target_request;

  return target_request;
end;
$$;

revoke all on function public.claim_assignment_request(text,uuid,integer) from public;
grant execute on function public.claim_assignment_request(text,uuid,integer) to service_role;

-- ============================================================
-- 21. RESOLVE MATCHING RULE
-- ============================================================

create or replace function public.resolve_assignment_rule(
  requested_assignment_request_id uuid
)
returns public.assignment_rules
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  request_record public.assignment_requests;
  lead_payload jsonb;
  validation_record public.lead_validation_results;
  source_value text;
  campaign_value text;
  language_value text;
  location_value text;
  budget_value numeric;
  project_value uuid;
  matched_rule public.assignment_rules;
begin
  select *
  into request_record
  from public.assignment_requests
  where id = requested_assignment_request_id;

  if not found then
    raise exception 'Assignment request not found';
  end if;

  lead_payload := request_record.normalized_context->'lead_snapshot';

  source_value := coalesce(
    lead_payload->>'lead_source',
    lead_payload->>'source',
    lead_payload->>'source_type'
  );

  campaign_value := coalesce(
    lead_payload->>'campaign_id',
    lead_payload->>'utm_campaign'
  );

  language_value := coalesce(
    lead_payload->>'preferred_language',
    lead_payload->>'language'
  );

  location_value := coalesce(
    lead_payload->>'preferred_location',
    lead_payload->>'location',
    lead_payload->>'city'
  );

  begin
    budget_value := nullif(coalesce(
      lead_payload->>'budget',
      lead_payload->>'maximum_budget'
    ),'')::numeric;
  exception when invalid_text_representation then
    budget_value := null;
  end;

  begin
    project_value := nullif(coalesce(
      lead_payload->>'project_id',
      lead_payload->>'interested_project_id'
    ),'')::uuid;
  exception when invalid_text_representation then
    project_value := null;
  end;

  if request_record.validation_result_id is not null then
    select *
    into validation_record
    from public.lead_validation_results
    where id = request_record.validation_result_id;
  end if;

  select *
  into matched_rule
  from public.assignment_rules rule
  where rule.organization_id = request_record.organization_id
    and rule.status = 'active'
    and rule.active_from <= now()
    and (rule.active_until is null or rule.active_until > now())
    and (
      cardinality(rule.source_types)=0
      or source_value = any(rule.source_types)
    )
    and (
      cardinality(rule.campaign_ids)=0
      or campaign_value = any(rule.campaign_ids)
    )
    and (
      cardinality(rule.languages)=0
      or language_value = any(rule.languages)
    )
    and (
      cardinality(rule.locations)=0
      or location_value = any(rule.locations)
    )
    and (
      cardinality(rule.project_ids)=0
      or project_value = any(rule.project_ids)
    )
    and (
      rule.minimum_budget is null
      or budget_value >= rule.minimum_budget
    )
    and (
      rule.maximum_budget is null
      or budget_value <= rule.maximum_budget
    )
    and (
      rule.minimum_trust_score is null
      or validation_record.trust_score >= rule.minimum_trust_score
    )
    and (
      rule.maximum_trust_score is null
      or validation_record.trust_score <= rule.maximum_trust_score
    )
    and (
      cardinality(rule.validation_decisions)=0
      or validation_record.decision = any(rule.validation_decisions)
    )
  order by rule.priority,rule.created_at
  limit 1;

  return matched_rule;
end;
$$;

revoke all on function public.resolve_assignment_rule(uuid) from public;
grant execute on function public.resolve_assignment_rule(uuid) to authenticated,service_role;

-- ============================================================
-- 22. GENERATE CANDIDATES
-- ============================================================

create or replace function public.generate_assignment_candidates(
  requested_assignment_request_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_record public.assignment_requests;
  rule_record public.assignment_rules;
  lead_payload jsonb;
  validation_record public.lead_validation_results;
  candidate record;
  selected_team uuid;
  strategy_value text;
  total_value numeric;
  rank_value integer := 0;
  inserted_count integer := 0;
  lead_language text;
  lead_location text;
  lead_source text;
  lead_budget numeric;
  lead_project uuid;
begin
  select *
  into request_record
  from public.assignment_requests
  where id = requested_assignment_request_id
  for update;

  if not found then
    raise exception 'Assignment request not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(request_record.organization_id,'assignment.execute') then
    raise exception 'Permission denied';
  end if;

  rule_record := public.resolve_assignment_rule(request_record.id);

  selected_team := coalesce(
    request_record.preferred_team_id,
    rule_record.target_team_id
  );

  strategy_value := coalesce(
    request_record.requested_strategy,
    rule_record.strategy,
    (
      select t.default_assignment_strategy
      from public.assignment_teams t
      where t.id = selected_team
    ),
    'least_loaded'
  );

  lead_payload := request_record.normalized_context->'lead_snapshot';

  lead_language := coalesce(lead_payload->>'preferred_language',lead_payload->>'language');
  lead_location := coalesce(lead_payload->>'preferred_location',lead_payload->>'location',lead_payload->>'city');
  lead_source := coalesce(lead_payload->>'lead_source',lead_payload->>'source',lead_payload->>'source_type');

  begin
    lead_budget := nullif(coalesce(lead_payload->>'budget',lead_payload->>'maximum_budget'),'')::numeric;
  exception when invalid_text_representation then
    lead_budget := null;
  end;

  begin
    lead_project := nullif(coalesce(lead_payload->>'project_id',lead_payload->>'interested_project_id'),'')::uuid;
  exception when invalid_text_representation then
    lead_project := null;
  end;

  if request_record.validation_result_id is not null then
    select *
    into validation_record
    from public.lead_validation_results
    where id = request_record.validation_result_id;
  end if;

  delete from public.assignment_candidates
  where assignment_request_id = request_record.id;

  for candidate in
    select
      agent.*,
      member.team_id,
      coalesce(member.assignment_weight,agent.assignment_weight) as effective_weight,
      coalesce(member.priority_rank,agent.priority_rank) as effective_priority
    from public.assignment_agent_profiles agent
    left join public.assignment_team_members member
      on member.agent_profile_id = agent.id
      and member.status = 'active'
      and member.active_from <= now()
      and (member.active_until is null or member.active_until > now())
    where agent.organization_id = request_record.organization_id
      and (
        request_record.preferred_agent_profile_id is null
        or agent.id = request_record.preferred_agent_profile_id
      )
      and (
        selected_team is null
        or member.team_id = selected_team
      )
      and public.is_assignment_agent_available(agent.id,now())
      and (
        validation_record.trust_score is null
        or (
          validation_record.trust_score >= agent.minimum_lead_score
          and validation_record.trust_score <= agent.maximum_lead_score
        )
      )
      and (
        lead_budget is null
        or (
          (agent.budget_min is null or lead_budget >= agent.budget_min)
          and (agent.budget_max is null or lead_budget <= agent.budget_max)
        )
      )
  loop
    total_value :=
      (
        case
          when cardinality(candidate.languages)=0 or lead_language is null then 50
          when lead_language=any(candidate.languages) then 100
          else 0
        end * 0.12
      )
      + (
        case
          when cardinality(candidate.locations)=0 or lead_location is null then 50
          when lead_location=any(candidate.locations) then 100
          else 0
        end * 0.12
      )
      + (
        case
          when cardinality(candidate.source_expertise)=0 or lead_source is null then 50
          when lead_source=any(candidate.source_expertise) then 100
          else 0
        end * 0.08
      )
      + (
        case
          when cardinality(candidate.project_ids)=0 or lead_project is null then 50
          when lead_project=any(candidate.project_ids) then 100
          else 0
        end * 0.18
      )
      + (
        greatest(
          0,
          100 - (
            candidate.current_open_leads::numeric
            / greatest(candidate.maximum_open_leads,1)
          ) * 100
        ) * 0.20
      )
      + (candidate.performance_score * 0.12)
      + (candidate.response_score * 0.08)
      + (candidate.conversion_score * 0.05)
      + (
        case
          when candidate.last_assigned_at is null then 100
          else least(100,extract(epoch from (now()-candidate.last_assigned_at))/3600)
        end * 0.05
      );

    if strategy_value='weighted_round_robin' then
      total_value := total_value * candidate.effective_weight;
    elsif strategy_value='priority_based' then
      total_value := total_value + greatest(0,100-candidate.effective_priority);
    elsif strategy_value='least_loaded' or strategy_value='capacity_based' then
      total_value := total_value + greatest(
        0,
        100 - (
          candidate.current_open_leads::numeric
          / greatest(candidate.maximum_open_leads,1)
        ) * 100
      );
    end if;

    rank_value := rank_value + 1;

    insert into public.assignment_candidates (
      organization_id,assignment_request_id,lead_id,team_id,
      agent_profile_id,rank,eligible,total_score,
      capacity_score,skill_score,project_score,source_score,
      language_score,location_score,performance_score,
      availability_score,fairness_score,score_breakdown
    )
    values (
      request_record.organization_id,request_record.id,request_record.lead_id,
      candidate.team_id,candidate.id,rank_value,true,total_value,
      greatest(0,100-(candidate.current_open_leads::numeric/greatest(candidate.maximum_open_leads,1))*100),
      50,
      case when cardinality(candidate.project_ids)=0 or lead_project is null then 50 when lead_project=any(candidate.project_ids) then 100 else 0 end,
      case when cardinality(candidate.source_expertise)=0 or lead_source is null then 50 when lead_source=any(candidate.source_expertise) then 100 else 0 end,
      case when cardinality(candidate.languages)=0 or lead_language is null then 50 when lead_language=any(candidate.languages) then 100 else 0 end,
      case when cardinality(candidate.locations)=0 or lead_location is null then 50 when lead_location=any(candidate.locations) then 100 else 0 end,
      candidate.performance_score,
      100,
      case when candidate.last_assigned_at is null then 100 else least(100,extract(epoch from (now()-candidate.last_assigned_at))/3600) end,
      jsonb_build_object(
        'strategy',strategy_value,
        'rule_id',rule_record.id,
        'current_open_leads',candidate.current_open_leads,
        'maximum_open_leads',candidate.maximum_open_leads,
        'assignment_weight',candidate.effective_weight,
        'priority_rank',candidate.effective_priority
      )
    );

    inserted_count := inserted_count + 1;
  end loop;

  with ranked as (
    select id,row_number() over (
      order by total_score desc,created_at,id
    ) as new_rank
    from public.assignment_candidates
    where assignment_request_id=request_record.id
  )
  update public.assignment_candidates c
  set rank=ranked.new_rank
  from ranked
  where c.id=ranked.id;

  update public.assignment_requests
  set
    status=case when inserted_count>0 then 'recommended' else 'manual_review' end,
    recommendation_output=jsonb_build_object(
      'candidate_count',inserted_count,
      'strategy',strategy_value,
      'rule_id',rule_record.id,
      'team_id',selected_team
    ),
    updated_at=now()
  where id=request_record.id;

  return inserted_count;
end;
$$;

revoke all on function public.generate_assignment_candidates(uuid) from public;
grant execute on function public.generate_assignment_candidates(uuid) to authenticated,service_role;

-- ============================================================
-- 23. EXECUTE ASSIGNMENT
-- ============================================================

create or replace function public.execute_assignment_request(
  requested_assignment_request_id uuid
)
returns public.lead_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  request_record public.assignment_requests;
  candidate_record public.assignment_candidates;
  agent_record public.assignment_agent_profiles;
  team_record public.assignment_teams;
  rule_record public.assignment_rules;
  assignment_record public.lead_assignments;
  strategy_value text;
  acceptance_minutes integer;
  response_minutes integer;
begin
  select *
  into request_record
  from public.assignment_requests
  where id=requested_assignment_request_id
  for update;

  if not found then
    raise exception 'Assignment request not found';
  end if;

  if auth.role()<>'service_role'
    and not public.has_organization_permission(request_record.organization_id,'assignment.execute') then
    raise exception 'Permission denied';
  end if;

  if exists (
    select 1
    from public.lead_assignments a
    where a.organization_id=request_record.organization_id
      and a.lead_id=request_record.lead_id
      and a.status in ('assigned','accepted','active')
  ) then
    raise exception 'Lead already has an active assignment';
  end if;

  if not exists (
    select 1 from public.assignment_candidates
    where assignment_request_id=request_record.id
  ) then
    perform public.generate_assignment_candidates(request_record.id);
  end if;

  select *
  into candidate_record
  from public.assignment_candidates c
  where c.assignment_request_id=request_record.id
    and c.eligible=true
  order by c.rank,c.total_score desc
  for update skip locked
  limit 1;

  if not found then
    update public.assignment_requests
    set status='manual_review',completed_at=now(),updated_at=now()
    where id=request_record.id;

    raise exception 'No eligible assignment candidate found';
  end if;

  select *
  into agent_record
  from public.assignment_agent_profiles
  where id=candidate_record.agent_profile_id
  for update;

  if not public.is_assignment_agent_available(agent_record.id,now()) then
    update public.assignment_candidates
    set eligible=false,
        rejection_reasons=rejection_reasons||jsonb_build_array('Agent became unavailable')
    where id=candidate_record.id;

    raise exception 'Selected agent is no longer available';
  end if;

  if candidate_record.team_id is not null then
    select *
    into team_record
    from public.assignment_teams
    where id=candidate_record.team_id;
  end if;

  rule_record := public.resolve_assignment_rule(request_record.id);

  strategy_value := coalesce(
    request_record.requested_strategy,
    rule_record.strategy,
    team_record.default_assignment_strategy,
    'least_loaded'
  );

  acceptance_minutes := coalesce(team_record.acceptance_sla_minutes,10);
  response_minutes := coalesce(team_record.response_sla_minutes,15);

  insert into public.lead_assignments (
    organization_id,lead_id,assignment_request_id,team_id,
    agent_profile_id,assigned_user_id,assignment_type,
    strategy,status,priority,assignment_score,
    assigned_at,acceptance_due_at,response_due_at,
    rule_id,assignment_reason,assignment_context,
    score_breakdown,created_by,updated_by
  )
  values (
    request_record.organization_id,request_record.lead_id,request_record.id,
    candidate_record.team_id,candidate_record.agent_profile_id,
    agent_record.user_id,'automatic',strategy_value,'assigned',
    request_record.priority,candidate_record.total_score,now(),
    now()+make_interval(mins=>acceptance_minutes),
    now()+make_interval(mins=>response_minutes),
    rule_record.id,'Best eligible candidate selected by Assignment Engine',
    request_record.normalized_context,candidate_record.score_breakdown,
    auth.uid(),auth.uid()
  )
  returning * into assignment_record;

  update public.assignment_candidates
  set selected=true,selected_at=now()
  where id=candidate_record.id;

  update public.assignment_agent_profiles
  set
    current_open_leads=current_open_leads+1,
    assigned_today=assigned_today+1,
    assigned_this_hour=assigned_this_hour+1,
    last_assigned_at=now(),
    updated_at=now()
  where id=agent_record.id;

  update public.leads
  set
    assigned_to=agent_record.user_id,
    assigned_team_id=candidate_record.team_id,
    assignment_status='assigned',
    assigned_at=now(),
    assignment_due_at=assignment_record.response_due_at,
    assignment_metadata=assignment_metadata||jsonb_build_object(
      'assignment_id',assignment_record.id,
      'assignment_request_id',request_record.id,
      'strategy',strategy_value,
      'score',candidate_record.total_score
    ),
    updated_at=now()
  where id=request_record.lead_id;

  update public.assignment_requests
  set status='assigned',completed_at=now(),updated_at=now()
  where id=request_record.id;

  insert into public.assignment_history (
    organization_id,lead_id,assignment_id,assignment_request_id,
    event_type,to_agent_profile_id,to_team_id,reason,event_data,
    actor_type,actor_user_id
  )
  values (
    request_record.organization_id,request_record.lead_id,assignment_record.id,
    request_record.id,'assigned',agent_record.id,candidate_record.team_id,
    'Automatic assignment completed',
    jsonb_build_object('strategy',strategy_value,'score',candidate_record.total_score),
    case when auth.role()='service_role' then 'system' else 'user' end,
    auth.uid()
  );

  return assignment_record;
end;
$$;

revoke all on function public.execute_assignment_request(uuid) from public;
grant execute on function public.execute_assignment_request(uuid) to authenticated,service_role;

-- ============================================================
-- 24. MANUAL ASSIGNMENT
-- ============================================================

create or replace function public.manual_assign_lead(
  requested_lead_id uuid,
  requested_agent_profile_id uuid,
  requested_team_id uuid default null,
  requested_reason text default 'Manual assignment',
  requested_override_capacity boolean default false
)
returns public.lead_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_value uuid;
  agent_record public.assignment_agent_profiles;
  assignment_record public.lead_assignments;
  previous_record public.lead_assignments;
begin
  select organization_id
  into organization_value
  from public.leads
  where id=requested_lead_id;

  if organization_value is null then
    raise exception 'Lead not found';
  end if;

  if not public.has_organization_permission(organization_value,'assignment.manual_assign') then
    raise exception 'Permission denied';
  end if;

  select *
  into agent_record
  from public.assignment_agent_profiles
  where id=requested_agent_profile_id
    and organization_id=organization_value
  for update;

  if not found then
    raise exception 'Agent profile not found';
  end if;

  if not requested_override_capacity
    and not public.is_assignment_agent_available(agent_record.id,now()) then
    raise exception 'Agent is not available or capacity is full';
  end if;

  select *
  into previous_record
  from public.lead_assignments
  where organization_id=organization_value
    and lead_id=requested_lead_id
    and status in ('assigned','accepted','active')
  order by assigned_at desc
  limit 1
  for update;

  if found then
    update public.lead_assignments
    set status='reassigned',completed_at=now(),updated_at=now()
    where id=previous_record.id;

    update public.assignment_agent_profiles
    set current_open_leads=greatest(current_open_leads-1,0),updated_at=now()
    where id=previous_record.agent_profile_id;
  end if;

  insert into public.lead_assignments (
    organization_id,lead_id,team_id,agent_profile_id,assigned_user_id,
    assignment_type,strategy,status,assigned_at,
    previous_assignment_id,reassignment_reason,assignment_reason,
    created_by,updated_by
  )
  values (
    organization_value,requested_lead_id,requested_team_id,
    agent_record.id,agent_record.user_id,
    case when previous_record.id is null then 'manual' else 'reassignment' end,
    'manual','assigned',now(),previous_record.id,
    case when previous_record.id is null then null else requested_reason end,
    requested_reason,auth.uid(),auth.uid()
  )
  returning * into assignment_record;

  update public.assignment_agent_profiles
  set current_open_leads=current_open_leads+1,
      assigned_today=assigned_today+1,
      assigned_this_hour=assigned_this_hour+1,
      last_assigned_at=now(),
      updated_at=now()
  where id=agent_record.id;

  update public.leads
  set assigned_to=agent_record.user_id,
      assigned_team_id=requested_team_id,
      assignment_status='assigned',
      assigned_at=now(),
      assignment_metadata=assignment_metadata||jsonb_build_object(
        'assignment_id',assignment_record.id,
        'manual',true,
        'reason',requested_reason
      ),
      updated_at=now()
  where id=requested_lead_id;

  insert into public.assignment_history (
    organization_id,lead_id,assignment_id,event_type,
    from_agent_profile_id,to_agent_profile_id,to_team_id,
    reason,actor_type,actor_user_id
  )
  values (
    organization_value,requested_lead_id,assignment_record.id,
    case when previous_record.id is null then 'assigned' else 'reassigned' end,
    previous_record.agent_profile_id,agent_record.id,requested_team_id,
    requested_reason,'user',auth.uid()
  );

  return assignment_record;
end;
$$;

revoke all on function public.manual_assign_lead(uuid,uuid,uuid,text,boolean) from public;
grant execute on function public.manual_assign_lead(uuid,uuid,uuid,text,boolean) to authenticated,service_role;

-- ============================================================
-- 25. ACCEPT / REJECT ASSIGNMENT
-- ============================================================

create or replace function public.respond_to_lead_assignment(
  requested_assignment_id uuid,
  requested_response text,
  requested_notes text default null
)
returns public.lead_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  assignment_record public.lead_assignments;
begin
  if requested_response not in ('accept','reject') then
    raise exception 'Response must be accept or reject';
  end if;

  select *
  into assignment_record
  from public.lead_assignments
  where id=requested_assignment_id
  for update;

  if not found then
    raise exception 'Assignment not found';
  end if;

  if auth.role()<>'service_role'
    and auth.uid()<>assignment_record.assigned_user_id
    and not public.has_organization_permission(assignment_record.organization_id,'assignment.override') then
    raise exception 'Permission denied';
  end if;

  if assignment_record.status not in ('assigned','accepted') then
    return assignment_record;
  end if;

  if requested_response='accept' then
    update public.lead_assignments
    set status='accepted',accepted_at=now(),
        assignment_context=assignment_context||jsonb_build_object('response_notes',requested_notes),
        updated_at=now()
    where id=requested_assignment_id
    returning * into assignment_record;

    update public.leads
    set assignment_status='accepted',updated_at=now()
    where id=assignment_record.lead_id;
  else
    update public.lead_assignments
    set status='rejected',rejected_at=now(),
        assignment_context=assignment_context||jsonb_build_object('rejection_notes',requested_notes),
        updated_at=now()
    where id=requested_assignment_id
    returning * into assignment_record;

    update public.assignment_agent_profiles
    set current_open_leads=greatest(current_open_leads-1,0),updated_at=now()
    where id=assignment_record.agent_profile_id;

    update public.leads
    set assigned_to=null,assigned_team_id=null,
        assignment_status='unassigned',assigned_at=null,
        updated_at=now()
    where id=assignment_record.lead_id;
  end if;

  insert into public.assignment_history (
    organization_id,lead_id,assignment_id,event_type,
    from_agent_profile_id,reason,event_data,actor_type,actor_user_id
  )
  values (
    assignment_record.organization_id,assignment_record.lead_id,
    assignment_record.id,
    case when requested_response='accept' then 'accepted' else 'rejected' end,
    assignment_record.agent_profile_id,requested_notes,
    jsonb_build_object('response',requested_response),
    case when auth.role()='service_role' then 'system' else 'user' end,
    auth.uid()
  );

  return assignment_record;
end;
$$;

revoke all on function public.respond_to_lead_assignment(uuid,text,text) from public;
grant execute on function public.respond_to_lead_assignment(uuid,text,text) to authenticated,service_role;

-- ============================================================
-- 26. RECORD FIRST RESPONSE / COMPLETE
-- ============================================================

create or replace function public.mark_assignment_first_response(
  requested_assignment_id uuid
)
returns public.lead_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare a public.lead_assignments;
begin
  select * into a
  from public.lead_assignments
  where id=requested_assignment_id
  for update;

  if not found then raise exception 'Assignment not found'; end if;

  if auth.role()<>'service_role'
    and auth.uid()<>a.assigned_user_id
    and not public.has_organization_permission(a.organization_id,'assignment.override') then
    raise exception 'Permission denied';
  end if;

  update public.lead_assignments
  set first_response_at=coalesce(first_response_at,now()),
      status=case when status in ('assigned','accepted') then 'active' else status end,
      updated_at=now()
  where id=a.id
  returning * into a;

  update public.leads
  set assignment_status='active',updated_at=now()
  where id=a.lead_id;

  return a;
end;
$$;

create or replace function public.complete_lead_assignment(
  requested_assignment_id uuid,
  requested_reason text default 'Assignment completed'
)
returns public.lead_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare a public.lead_assignments;
begin
  select * into a
  from public.lead_assignments
  where id=requested_assignment_id
  for update;

  if not found then raise exception 'Assignment not found'; end if;

  if auth.role()<>'service_role'
    and auth.uid()<>a.assigned_user_id
    and not public.has_organization_permission(a.organization_id,'assignment.override') then
    raise exception 'Permission denied';
  end if;

  update public.lead_assignments
  set status='completed',completed_at=now(),
      assignment_context=assignment_context||jsonb_build_object('completion_reason',requested_reason),
      updated_at=now()
  where id=a.id
  returning * into a;

  update public.assignment_agent_profiles
  set current_open_leads=greatest(current_open_leads-1,0),updated_at=now()
  where id=a.agent_profile_id;

  update public.leads
  set assignment_status='completed',updated_at=now()
  where id=a.lead_id;

  return a;
end;
$$;

revoke all on function public.mark_assignment_first_response(uuid) from public;
revoke all on function public.complete_lead_assignment(uuid,text) from public;
grant execute on function public.mark_assignment_first_response(uuid) to authenticated,service_role;
grant execute on function public.complete_lead_assignment(uuid,text) to authenticated,service_role;

-- ============================================================
-- 27. SLA PROCESSOR
-- ============================================================

create or replace function public.process_assignment_sla_breaches(
  requested_organization_id uuid default null,
  requested_limit integer default 100
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  a record;
  processed integer:=0;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may process SLA breaches';
  end if;

  for a in
    select *
    from public.lead_assignments x
    where x.status in ('assigned','accepted','active')
      and (
        (x.status='assigned' and x.acceptance_due_at is not null and x.acceptance_due_at<=now())
        or (x.first_response_at is null and x.response_due_at is not null and x.response_due_at<=now())
      )
      and (requested_organization_id is null or x.organization_id=requested_organization_id)
    order by least(
      coalesce(x.acceptance_due_at,'infinity'::timestamptz),
      coalesce(x.response_due_at,'infinity'::timestamptz)
    )
    limit greatest(requested_limit,1)
    for update skip locked
  loop
    insert into public.assignment_history (
      organization_id,lead_id,assignment_id,event_type,
      from_agent_profile_id,from_team_id,reason,event_data,actor_type
    )
    values (
      a.organization_id,a.lead_id,a.id,'escalated',
      a.agent_profile_id,a.team_id,'Assignment SLA breached',
      jsonb_build_object(
        'acceptance_due_at',a.acceptance_due_at,
        'response_due_at',a.response_due_at,
        'accepted_at',a.accepted_at,
        'first_response_at',a.first_response_at
      ),
      'scheduler'
    );

    insert into public.assignment_event_outbox (
      organization_id,assignment_id,lead_id,event_name,destination,
      status,priority,idempotency_key,payload
    )
    values (
      a.organization_id,a.id,a.lead_id,'assignment.sla.breached','n8n',
      'pending',10,
      'assignment-sla-breach:'||a.id::text||':'||extract(epoch from date_trunc('hour',now()))::bigint::text,
      jsonb_build_object(
        'assignment_id',a.id,
        'lead_id',a.lead_id,
        'assigned_user_id',a.assigned_user_id,
        'team_id',a.team_id,
        'acceptance_due_at',a.acceptance_due_at,
        'response_due_at',a.response_due_at
      )
    )
    on conflict (organization_id,idempotency_key)
    where idempotency_key is not null
    do nothing;

    processed:=processed+1;
  end loop;

  return processed;
end;
$$;

revoke all on function public.process_assignment_sla_breaches(uuid,integer) from public;
grant execute on function public.process_assignment_sla_breaches(uuid,integer) to service_role;

-- ============================================================
-- 28. EVENT PUBLISHER AND TRIGGER
-- ============================================================

create or replace function public.publish_assignment_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_assignment_request_id uuid default null,
  requested_assignment_id uuid default null,
  requested_lead_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null
)
returns public.assignment_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.assignment_event_outbox;
  created_event public.assignment_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.assignment_event_outbox
    where organization_id=requested_organization_id
      and idempotency_key=requested_idempotency_key
    limit 1;

    if found then return existing_event; end if;
  end if;

  insert into public.assignment_event_outbox (
    organization_id,assignment_request_id,assignment_id,lead_id,
    event_name,destination,status,priority,idempotency_key,payload
  )
  values (
    requested_organization_id,requested_assignment_request_id,
    requested_assignment_id,requested_lead_id,
    requested_event_name,requested_destination,'pending',
    requested_priority,requested_idempotency_key,
    coalesce(requested_payload,'{}'::jsonb)
  )
  returning * into created_event;

  return created_event;
end;
$$;

create or replace function public.emit_assignment_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare payload_data jsonb;
begin
  if tg_op='UPDATE'
    and new.status is not distinct from old.status
    and new.assigned_user_id is not distinct from old.assigned_user_id then
    return new;
  end if;

  payload_data:=jsonb_build_object(
    'organization_id',new.organization_id,
    'assignment_id',new.id,
    'assignment_request_id',new.assignment_request_id,
    'lead_id',new.lead_id,
    'team_id',new.team_id,
    'agent_profile_id',new.agent_profile_id,
    'assigned_user_id',new.assigned_user_id,
    'status',new.status,
    'assignment_type',new.assignment_type,
    'strategy',new.strategy,
    'assignment_score',new.assignment_score,
    'assigned_at',new.assigned_at,
    'acceptance_due_at',new.acceptance_due_at,
    'response_due_at',new.response_due_at
  );

  perform public.publish_assignment_event(
    new.organization_id,
    'assignment.'||new.status,
    payload_data,
    'workflow_engine',
    new.assignment_request_id,new.id,new.lead_id,
    case when new.status in ('rejected','expired') then 10 else 50 end,
    'assignment-workflow:'||new.id::text||':'||new.status
  );

  perform public.publish_assignment_event(
    new.organization_id,
    'assignment.'||new.status,
    payload_data,
    'n8n',
    new.assignment_request_id,new.id,new.lead_id,
    50,
    'assignment-n8n:'||new.id::text||':'||new.status
  );

  return new;
end;
$$;

drop trigger if exists lead_assignments_emit_events
on public.lead_assignments;

create trigger lead_assignments_emit_events
after insert or update on public.lead_assignments
for each row execute function public.emit_assignment_events();

revoke all on function public.publish_assignment_event(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text
) from public;

grant execute on function public.publish_assignment_event(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text
) to authenticated,service_role;

-- ============================================================
-- 29. CLAIM / COMPLETE OUTBOX
-- ============================================================

create or replace function public.claim_assignment_event(
  requested_worker_id text,
  requested_destination text default null,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.assignment_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare e public.assignment_event_outbox;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may claim events';
  end if;

  select *
  into e
  from public.assignment_event_outbox x
  where x.status in ('pending','failed')
    and x.available_at<=now()
    and x.delivery_attempts<x.maximum_attempts
    and (requested_destination is null or x.destination=requested_destination)
    and (requested_organization_id is null or x.organization_id=requested_organization_id)
  order by x.priority,x.available_at,x.created_at
  for update skip locked
  limit 1;

  if not found then return null; end if;

  update public.assignment_event_outbox
  set status='claimed',claimed_at=now(),claimed_by=requested_worker_id,
      lock_token=gen_random_uuid()::text,
      lock_expires_at=now()+make_interval(secs=>greatest(requested_lock_seconds,1)),
      delivery_attempts=delivery_attempts+1,updated_at=now()
  where id=e.id
  returning * into e;

  return e;
end;
$$;

create or replace function public.complete_assignment_event(
  requested_event_id uuid,
  requested_lock_token text
)
returns public.assignment_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare e public.assignment_event_outbox;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may complete events'; end if;

  select * into e from public.assignment_event_outbox where id=requested_event_id for update;
  if not found then raise exception 'Event not found'; end if;
  if e.lock_token is distinct from requested_lock_token then raise exception 'Invalid lock token'; end if;

  update public.assignment_event_outbox
  set status='delivered',delivered_at=now(),
      claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
      updated_at=now()
  where id=requested_event_id
  returning * into e;

  return e;
end;
$$;

revoke all on function public.claim_assignment_event(text,text,uuid,integer) from public;
revoke all on function public.complete_assignment_event(uuid,text) from public;
grant execute on function public.claim_assignment_event(text,text,uuid,integer) to service_role;
grant execute on function public.complete_assignment_event(uuid,text) to service_role;

-- ============================================================
-- 30. COUNTER RESET
-- ============================================================

create or replace function public.reset_assignment_agent_counters()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare changed integer;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may reset counters';
  end if;

  update public.assignment_agent_profiles
  set
    assigned_this_hour=case
      when date_trunc('hour',counters_reset_at)<date_trunc('hour',now()) then 0
      else assigned_this_hour
    end,
    assigned_today=case
      when counters_reset_at::date<current_date then 0
      else assigned_today
    end,
    counters_reset_at=now(),
    updated_at=now();

  get diagnostics changed=row_count;
  return changed;
end;
$$;

revoke all on function public.reset_assignment_agent_counters() from public;
grant execute on function public.reset_assignment_agent_counters() to service_role;

-- ============================================================
-- 31. ANALYTICS VIEWS
-- ============================================================

create or replace view public.assignment_latest_active
with (security_invoker=true) as
select distinct on (organization_id,lead_id) *
from public.lead_assignments
where status in ('assigned','accepted','active')
order by organization_id,lead_id,assigned_at desc,id desc;

create or replace view public.assignment_agent_workload
with (security_invoker=true) as
select
  p.organization_id,
  p.id as agent_profile_id,
  p.user_id,
  p.display_name,
  p.status,
  p.availability_status,
  p.maximum_open_leads,
  p.current_open_leads,
  p.daily_assignment_limit,
  p.assigned_today,
  p.assignment_weight,
  p.performance_score,
  p.response_score,
  p.conversion_score,
  count(a.id) filter (where a.status='assigned') as pending_acceptance,
  count(a.id) filter (where a.status='accepted') as accepted_count,
  count(a.id) filter (where a.status='active') as active_count,
  count(a.id) filter (
    where a.status in ('assigned','accepted','active')
      and a.response_due_at<=now()
      and a.first_response_at is null
  ) as overdue_count,
  round(
    (p.current_open_leads::numeric/nullif(p.maximum_open_leads,0))*100,
    2
  ) as capacity_utilization_percent
from public.assignment_agent_profiles p
left join public.lead_assignments a
  on a.agent_profile_id=p.id
  and a.status in ('assigned','accepted','active')
group by p.id;

create or replace view public.assignment_daily_dashboard
with (security_invoker=true) as
select
  organization_id,
  date_trunc('day',assigned_at)::date as assignment_date,
  count(*) as total_assignments,
  count(*) filter (where assignment_type='automatic') as automatic_count,
  count(*) filter (where assignment_type='manual') as manual_count,
  count(*) filter (where assignment_type='reassignment') as reassignment_count,
  count(*) filter (where status='accepted') as accepted_count,
  count(*) filter (where status='rejected') as rejected_count,
  count(*) filter (where first_response_at is not null) as responded_count,
  count(*) filter (
    where first_response_at is not null
      and first_response_at<=response_due_at
  ) as responded_within_sla_count,
  round(avg(assignment_score),2) as average_assignment_score,
  round(avg(extract(epoch from (accepted_at-assigned_at))/60)
    filter (where accepted_at is not null),2) as average_acceptance_minutes,
  round(avg(extract(epoch from (first_response_at-assigned_at))/60)
    filter (where first_response_at is not null),2) as average_first_response_minutes
from public.lead_assignments
group by organization_id,date_trunc('day',assigned_at)::date;

create or replace view public.assignment_team_dashboard
with (security_invoker=true) as
select
  t.organization_id,
  t.id as team_id,
  t.team_name,
  count(distinct m.agent_profile_id) filter (where m.status='active') as active_agents,
  count(a.id) filter (where a.status in ('assigned','accepted','active')) as open_assignments,
  count(a.id) filter (
    where a.response_due_at<=now()
      and a.first_response_at is null
      and a.status in ('assigned','accepted','active')
  ) as overdue_assignments,
  round(avg(a.assignment_score),2) as average_assignment_score
from public.assignment_teams t
left join public.assignment_team_members m on m.team_id=t.id
left join public.lead_assignments a on a.team_id=t.id
group by t.id;

grant select on
  public.assignment_latest_active,
  public.assignment_agent_workload,
  public.assignment_daily_dashboard,
  public.assignment_team_dashboard
to authenticated,service_role;

-- ============================================================
-- 32. HEALTH CHECK
-- ============================================================

create or replace function public.get_assignment_engine_health(
  requested_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.role()<>'service_role'
    and (
      requested_organization_id is null
      or not public.has_organization_permission(requested_organization_id,'assignment.view_logs')
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),
    'available_agents',(
      select count(*) from public.assignment_agent_profiles p
      where p.status='active'
        and p.availability_status='available'
        and p.accept_new_leads=true
        and (requested_organization_id is null or p.organization_id=requested_organization_id)
    ),
    'queued_requests',(
      select count(*) from public.assignment_requests r
      where r.status in ('pending','queued','waiting')
        and (requested_organization_id is null or r.organization_id=requested_organization_id)
    ),
    'manual_review_requests',(
      select count(*) from public.assignment_requests r
      where r.status='manual_review'
        and (requested_organization_id is null or r.organization_id=requested_organization_id)
    ),
    'open_assignments',(
      select count(*) from public.lead_assignments a
      where a.status in ('assigned','accepted','active')
        and (requested_organization_id is null or a.organization_id=requested_organization_id)
    ),
    'overdue_assignments',(
      select count(*) from public.lead_assignments a
      where a.status in ('assigned','accepted','active')
        and a.first_response_at is null
        and a.response_due_at is not null
        and a.response_due_at<=now()
        and (requested_organization_id is null or a.organization_id=requested_organization_id)
    ),
    'pending_outbox_events',(
      select count(*) from public.assignment_event_outbox e
      where e.status in ('pending','failed')
        and (requested_organization_id is null or e.organization_id=requested_organization_id)
    )
  );
end;
$$;

revoke all on function public.get_assignment_engine_health(uuid) from public;
grant execute on function public.get_assignment_engine_health(uuid) to authenticated,service_role;

-- ============================================================
-- 33. RLS
-- ============================================================

alter table public.assignment_teams enable row level security;
alter table public.assignment_agent_profiles enable row level security;
alter table public.assignment_team_members enable row level security;
alter table public.assignment_agent_schedules enable row level security;
alter table public.assignment_agent_unavailability enable row level security;
alter table public.assignment_rules enable row level security;
alter table public.assignment_requests enable row level security;
alter table public.assignment_candidates enable row level security;
alter table public.lead_assignments enable row level security;
alter table public.assignment_history enable row level security;
alter table public.assignment_sla_policies enable row level security;
alter table public.assignment_event_outbox enable row level security;
alter table public.assignment_logs enable row level security;

do $$
declare target_table text;
begin
  foreach target_table in array array[
    'assignment_teams',
    'assignment_agent_profiles',
    'assignment_team_members',
    'assignment_agent_schedules',
    'assignment_agent_unavailability',
    'assignment_rules',
    'assignment_requests',
    'assignment_candidates',
    'lead_assignments',
    'assignment_history',
    'assignment_sla_policies',
    'assignment_event_outbox',
    'assignment_logs'
  ]
  loop
    execute format(
      'drop policy if exists %I_select_policy on public.%I',
      target_table,target_table
    );

    execute format(
      'create policy %I_select_policy
       on public.%I
       for select to authenticated
       using (
         public.has_organization_permission(organization_id,''assignment.view'')
         or public.has_organization_permission(organization_id,''assignment.view_all'')
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
       for all to service_role
       using (true) with check (true)',
      target_table,target_table
    );
  end loop;
end;
$$;

drop policy if exists assignment_teams_write_policy on public.assignment_teams;
create policy assignment_teams_write_policy
on public.assignment_teams
for all to authenticated
using (public.has_organization_permission(organization_id,'assignment.manage_teams'))
with check (public.has_organization_permission(organization_id,'assignment.manage_teams'));

drop policy if exists assignment_agent_profiles_write_policy on public.assignment_agent_profiles;
create policy assignment_agent_profiles_write_policy
on public.assignment_agent_profiles
for all to authenticated
using (public.has_organization_permission(organization_id,'assignment.manage_agents'))
with check (public.has_organization_permission(organization_id,'assignment.manage_agents'));

drop policy if exists assignment_team_members_write_policy on public.assignment_team_members;
create policy assignment_team_members_write_policy
on public.assignment_team_members
for all to authenticated
using (public.has_organization_permission(organization_id,'assignment.manage_teams'))
with check (public.has_organization_permission(organization_id,'assignment.manage_teams'));

drop policy if exists assignment_rules_write_policy on public.assignment_rules;
create policy assignment_rules_write_policy
on public.assignment_rules
for all to authenticated
using (public.has_organization_permission(organization_id,'assignment.manage_rules'))
with check (public.has_organization_permission(organization_id,'assignment.manage_rules'));

drop policy if exists assignment_requests_write_policy on public.assignment_requests;
create policy assignment_requests_write_policy
on public.assignment_requests
for all to authenticated
using (public.has_organization_permission(organization_id,'assignment.execute'))
with check (public.has_organization_permission(organization_id,'assignment.execute'));

-- ============================================================
-- 34. GRANTS
-- ============================================================

grant select on
  public.assignment_teams,
  public.assignment_agent_profiles,
  public.assignment_team_members,
  public.assignment_agent_schedules,
  public.assignment_agent_unavailability,
  public.assignment_rules,
  public.assignment_requests,
  public.assignment_candidates,
  public.lead_assignments,
  public.assignment_history,
  public.assignment_sla_policies,
  public.assignment_event_outbox,
  public.assignment_logs
to authenticated;

grant insert,update,delete on
  public.assignment_teams,
  public.assignment_agent_profiles,
  public.assignment_team_members,
  public.assignment_agent_schedules,
  public.assignment_agent_unavailability,
  public.assignment_rules,
  public.assignment_requests,
  public.assignment_sla_policies
to authenticated;

grant all on
  public.assignment_teams,
  public.assignment_agent_profiles,
  public.assignment_team_members,
  public.assignment_agent_schedules,
  public.assignment_agent_unavailability,
  public.assignment_rules,
  public.assignment_requests,
  public.assignment_candidates,
  public.lead_assignments,
  public.assignment_history,
  public.assignment_sla_policies,
  public.assignment_event_outbox,
  public.assignment_logs
to service_role;

-- ============================================================
-- 35. FINAL VALIDATION
-- ============================================================

do $$
declare
  required_item text;
  missing_items text[]:='{}';
begin
  foreach required_item in array array[
    'assignment_teams',
    'assignment_agent_profiles',
    'assignment_team_members',
    'assignment_agent_schedules',
    'assignment_agent_unavailability',
    'assignment_rules',
    'assignment_requests',
    'assignment_candidates',
    'lead_assignments',
    'assignment_history',
    'assignment_sla_policies',
    'assignment_event_outbox',
    'assignment_logs'
  ]
  loop
    if not exists (
      select 1 from information_schema.tables
      where table_schema='public' and table_name=required_item
    ) then
      missing_items:=array_append(missing_items,'table:'||required_item);
    end if;
  end loop;

  foreach required_item in array array[
    'create_assignment_request',
    'claim_assignment_request',
    'resolve_assignment_rule',
    'generate_assignment_candidates',
    'execute_assignment_request',
    'manual_assign_lead',
    'respond_to_lead_assignment',
    'mark_assignment_first_response',
    'complete_lead_assignment',
    'process_assignment_sla_breaches',
    'publish_assignment_event',
    'claim_assignment_event',
    'complete_assignment_event',
    'get_assignment_engine_health'
  ]
  loop
    if not exists (
      select 1 from information_schema.routines
      where routine_schema='public' and routine_name=required_item
    ) then
      missing_items:=array_append(missing_items,'function:'||required_item);
    end if;
  end loop;

  if cardinality(missing_items)>0 then
    raise exception '012 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 36. MIGRATION AUDIT
-- ============================================================

insert into public.assignment_logs (
  organization_id,log_level,event_name,message,log_data
)
select
  o.id,
  'info',
  'migration.012.completed',
  'Assignment Engine migration 012 completed',
  jsonb_build_object(
    'migration','012_assignment_engine',
    'completed_at',now(),
    'modules',jsonb_build_array(
      'teams',
      'agent_profiles',
      'working_hours',
      'availability',
      'routing_rules',
      'assignment_queue',
      'candidate_scoring',
      'automatic_assignment',
      'manual_assignment',
      'reassignment',
      'sla',
      'event_outbox',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.assignment_logs l
  where l.organization_id=o.id
    and l.event_name='migration.012.completed'
);

commit;