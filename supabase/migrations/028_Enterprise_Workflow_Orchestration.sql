-- ============================================================
-- SalesSetu Enterprise
-- Migration 028: Enterprise Workflow Orchestration
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   009_workflow_engine.sql
--   014_automation_execution_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--   023_Integration_API_Engine.sql
--   025_AI_Intelligence_Engine.sql
--   026_Automation_Engine.sql
--   027_Communication_Engine.sql
--
-- Purpose:
--   Central enterprise-grade orchestration layer that coordinates
--   human work, AI tasks, automations, communications, integrations,
--   timers, approvals, event signals, parallel branches, retries,
--   compensations and long-running business processes.
--
-- Design:
--   • New objects use enterprise_workflow_* names to avoid conflicts
--     with earlier workflow and automation migrations.
--   • Runtime uses immutable published versions.
--   • Workers claim jobs with SKIP LOCKED and expiring locks.
--   • Long-running waits use explicit tokens, timers and signals.
--   • Multi-tenant isolation is enforced through RLS.
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ============================================================
-- 1. PERMISSIONS
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
    ('enterprise_workflow','view','enterprise_workflow.view','View enterprise workflow data'),
    ('enterprise_workflow','view_all','enterprise_workflow.view_all','View all organization workflow data'),
    ('enterprise_workflow','create','enterprise_workflow.create','Create enterprise workflows'),
    ('enterprise_workflow','update','enterprise_workflow.update','Update enterprise workflows'),
    ('enterprise_workflow','delete','enterprise_workflow.delete','Archive enterprise workflows'),
    ('enterprise_workflow','publish','enterprise_workflow.publish','Publish workflow versions'),
    ('enterprise_workflow','execute','enterprise_workflow.execute','Start and execute workflows'),
    ('enterprise_workflow','cancel','enterprise_workflow.cancel','Cancel workflow instances'),
    ('enterprise_workflow','retry','enterprise_workflow.retry','Retry failed workflow jobs'),
    ('enterprise_workflow','approve','enterprise_workflow.approve','Approve workflow approvals'),
    ('enterprise_workflow','manage_tasks','enterprise_workflow.manage_tasks','Manage workflow human tasks'),
    ('enterprise_workflow','manage_workers','enterprise_workflow.manage_workers','Manage workflow workers'),
    ('enterprise_workflow','manage_schedules','enterprise_workflow.manage_schedules','Manage workflow timers and schedules'),
    ('enterprise_workflow','manage_events','enterprise_workflow.manage_events','Manage workflow events and signals'),
    ('enterprise_workflow','manage_compensation','enterprise_workflow.manage_compensation','Manage workflow compensations'),
    ('enterprise_workflow','view_logs','enterprise_workflow.view_logs','View workflow logs'),
    ('enterprise_workflow','view_analytics','enterprise_workflow.view_analytics','View workflow analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. WORKFLOW DEFINITIONS
-- ============================================================

create table if not exists public.enterprise_workflow_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_code text not null,
  workflow_name text not null,
  description text,

  category text not null default 'general'
    check (
      category in (
        'lead',
        'assignment',
        'qualification',
        'communication',
        'followup',
        'site_visit',
        'booking',
        'finance',
        'customer_success',
        'document',
        'reporting',
        'ai',
        'integration',
        'mobile',
        'general',
        'custom'
      )
    ),

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'active',
        'paused',
        'inactive',
        'archived'
      )
    ),

  orchestration_mode text not null default 'durable'
    check (
      orchestration_mode in (
        'durable',
        'short_running',
        'event_driven',
        'state_machine',
        'hybrid'
      )
    ),

  concurrency_policy text not null default 'allow'
    check (
      concurrency_policy in (
        'allow',
        'skip_if_running',
        'queue',
        'cancel_previous',
        'single_per_entity'
      )
    ),

  maximum_concurrent_instances integer not null default 25,
  default_timeout_seconds integer not null default 86400,

  owner_user_id uuid references auth.users(id) on delete set null,

  is_system_workflow boolean not null default false,

  tags text[] not null default '{}',
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,workflow_code)
);

create index if not exists enterprise_workflow_definitions_org_idx
  on public.enterprise_workflow_definitions (
    organization_id,
    status,
    category
  );

-- ============================================================
-- 3. WORKFLOW VERSIONS
-- ============================================================

create table if not exists public.enterprise_workflow_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.enterprise_workflow_definitions(id) on delete cascade,

  version_number integer not null,
  version_label text,

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'published',
        'deprecated',
        'archived'
      )
    ),

  graph_definition jsonb not null default '{}',
  input_schema jsonb not null default '{}',
  output_schema jsonb not null default '{}',
  variable_schema jsonb not null default '{}',

  validation_status text not null default 'pending'
    check (
      validation_status in (
        'pending',
        'valid',
        'invalid'
      )
    ),

  validation_errors jsonb not null default '[]',

  is_current boolean not null default false,

  published_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,

  change_summary text,
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  unique (workflow_id,version_number)
);

create unique index if not exists enterprise_workflow_versions_current_idx
  on public.enterprise_workflow_versions(workflow_id)
  where is_current = true;

-- ============================================================
-- 4. WORKFLOW STATES
-- ============================================================

create table if not exists public.enterprise_workflow_states (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_version_id uuid not null references public.enterprise_workflow_versions(id) on delete cascade,

  state_key text not null,
  state_name text not null,

  state_type text not null
    check (
      state_type in (
        'start',
        'end',
        'task',
        'human_task',
        'ai_task',
        'automation',
        'communication',
        'integration',
        'decision',
        'parallel_split',
        'parallel_join',
        'exclusive_gateway',
        'inclusive_gateway',
        'wait',
        'timer',
        'signal',
        'approval',
        'subworkflow',
        'compensation',
        'transform',
        'script',
        'custom'
      )
    ),

  execution_order integer,

  position_x numeric(12,4),
  position_y numeric(12,4),

  timeout_seconds integer,
  maximum_attempts integer not null default 3,

  retry_strategy text not null default 'exponential'
    check (
      retry_strategy in (
        'none',
        'fixed',
        'linear',
        'exponential',
        'custom'
      )
    ),

  initial_retry_delay_seconds integer not null default 30,
  maximum_retry_delay_seconds integer not null default 3600,

  continue_on_error boolean not null default false,
  requires_approval boolean not null default false,
  compensatable boolean not null default false,

  handler_type text,
  handler_reference text,

  configuration jsonb not null default '{}',
  input_mapping jsonb not null default '{}',
  output_mapping jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workflow_version_id,state_key)
);

-- ============================================================
-- 5. WORKFLOW TRANSITIONS
-- ============================================================

create table if not exists public.enterprise_workflow_transitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_version_id uuid not null references public.enterprise_workflow_versions(id) on delete cascade,

  source_state_id uuid not null references public.enterprise_workflow_states(id) on delete cascade,
  target_state_id uuid not null references public.enterprise_workflow_states(id) on delete cascade,

  transition_key text not null,
  transition_name text,

  transition_type text not null default 'success'
    check (
      transition_type in (
        'success',
        'failure',
        'true',
        'false',
        'case',
        'default',
        'approved',
        'rejected',
        'timeout',
        'signal',
        'loop',
        'compensate',
        'custom'
      )
    ),

  condition_expression jsonb not null default '{}',
  priority integer not null default 100,

  enabled boolean not null default true,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (
    workflow_version_id,
    transition_key
  )
);

create index if not exists enterprise_workflow_transitions_source_idx
  on public.enterprise_workflow_transitions (
    source_state_id,
    enabled,
    priority
  );

-- ============================================================
-- 6. WORKFLOW TRIGGERS
-- ============================================================

create table if not exists public.enterprise_workflow_triggers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.enterprise_workflow_definitions(id) on delete cascade,
  workflow_version_id uuid references public.enterprise_workflow_versions(id) on delete set null,

  trigger_code text not null,
  trigger_name text not null,

  trigger_type text not null
    check (
      trigger_type in (
        'manual',
        'event',
        'schedule',
        'webhook',
        'api',
        'database_change',
        'form_submission',
        'message_received',
        'ai_decision',
        'automation_event',
        'custom'
      )
    ),

  source_module text,
  event_pattern text,
  source_entity_type text,

  cron_expression text,
  timezone text not null default 'Asia/Kolkata',

  filter_expression jsonb not null default '{}',
  input_mapping jsonb not null default '{}',

  debounce_seconds integer not null default 0,
  deduplication_window_seconds integer not null default 0,

  enabled boolean not null default true,
  status text not null default 'active'
    check (status in ('active','paused','inactive','archived')),

  next_scheduled_at timestamptz,
  last_triggered_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workflow_id,trigger_code)
);

create index if not exists enterprise_workflow_triggers_due_idx
  on public.enterprise_workflow_triggers (
    status,
    enabled,
    next_scheduled_at
  )
  where trigger_type = 'schedule'
    and status = 'active'
    and enabled = true;

-- ============================================================
-- 7. WORKFLOW VARIABLES
-- ============================================================

create table if not exists public.enterprise_workflow_variables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.enterprise_workflow_definitions(id) on delete cascade,

  variable_key text not null,
  variable_name text,

  variable_type text not null default 'text'
    check (
      variable_type in (
        'text',
        'integer',
        'numeric',
        'boolean',
        'date',
        'timestamp',
        'uuid',
        'json',
        'array',
        'secret_reference'
      )
    ),

  default_value jsonb,
  secret_reference text,

  required boolean not null default false,
  runtime_editable boolean not null default true,
  sensitive boolean not null default false,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workflow_id,variable_key)
);

-- ============================================================
-- 8. WORKFLOW INSTANCES
-- ============================================================

create table if not exists public.enterprise_workflow_instances (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.enterprise_workflow_definitions(id) on delete cascade,
  workflow_version_id uuid not null references public.enterprise_workflow_versions(id) on delete restrict,
  trigger_id uuid references public.enterprise_workflow_triggers(id) on delete set null,

  instance_key text not null,
  business_key text,

  parent_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
  root_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,

  related_entity_type text,
  related_entity_id uuid,

  instance_type text not null default 'event'
    check (
      instance_type in (
        'manual',
        'event',
        'schedule',
        'webhook',
        'api',
        'child',
        'retry',
        'test'
      )
    ),

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'running',
        'waiting',
        'waiting_signal',
        'waiting_timer',
        'waiting_approval',
        'waiting_human_task',
        'compensating',
        'completed',
        'partially_completed',
        'failed',
        'cancelled',
        'timed_out',
        'dead_lettered'
      )
    ),

  current_state_id uuid references public.enterprise_workflow_states(id) on delete set null,

  priority integer not null default 100,

  input_data jsonb not null default '{}',
  output_data jsonb not null default '{}',
  variables jsonb not null default '{}',
  context_data jsonb not null default '{}',

  scheduled_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  timeout_at timestamptz,

  requested_by uuid references auth.users(id) on delete set null,

  idempotency_key text,
  correlation_id text,
  trace_id text,

  total_state_count integer not null default 0,
  completed_state_count integer not null default 0,
  failed_state_count integer not null default 0,
  active_token_count integer not null default 0,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (instance_key)
);

create unique index if not exists enterprise_workflow_instances_idem_idx
  on public.enterprise_workflow_instances (
    organization_id,
    workflow_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists enterprise_workflow_instances_status_idx
  on public.enterprise_workflow_instances (
    organization_id,
    status,
    scheduled_at,
    priority
  );

-- ============================================================
-- 9. EXECUTION TOKENS
-- ============================================================

create table if not exists public.enterprise_workflow_tokens (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_instance_id uuid not null references public.enterprise_workflow_instances(id) on delete cascade,

  token_key text not null,

  current_state_id uuid references public.enterprise_workflow_states(id) on delete set null,
  previous_state_id uuid references public.enterprise_workflow_states(id) on delete set null,

  branch_key text,
  parent_token_id uuid references public.enterprise_workflow_tokens(id) on delete set null,

  status text not null default 'active'
    check (
      status in (
        'active',
        'waiting',
        'completed',
        'cancelled',
        'failed',
        'joined'
      )
    ),

  token_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workflow_instance_id,token_key)
);

create index if not exists enterprise_workflow_tokens_active_idx
  on public.enterprise_workflow_tokens (
    workflow_instance_id,
    status,
    current_state_id
  );

-- ============================================================
-- 10. STATE EXECUTIONS
-- ============================================================

create table if not exists public.enterprise_workflow_state_executions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_instance_id uuid not null references public.enterprise_workflow_instances(id) on delete cascade,
  token_id uuid references public.enterprise_workflow_tokens(id) on delete set null,
  state_id uuid not null references public.enterprise_workflow_states(id) on delete restrict,

  iteration_number integer not null default 1,
  attempt_number integer not null default 1,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'queued',
        'claimed',
        'running',
        'waiting',
        'waiting_signal',
        'waiting_timer',
        'waiting_approval',
        'waiting_human_task',
        'completed',
        'failed',
        'skipped',
        'cancelled',
        'timed_out',
        'compensated'
      )
    ),

  input_data jsonb not null default '{}',
  output_data jsonb not null default '{}',

  started_at timestamptz,
  completed_at timestamptz,
  duration_ms bigint,

  retry_at timestamptz,

  worker_id text,
  lock_token text,
  lock_expires_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  compensation_required boolean not null default false,
  compensation_completed boolean not null default false,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    workflow_instance_id,
    state_id,
    token_id,
    iteration_number,
    attempt_number
  )
);

create index if not exists enterprise_workflow_state_executions_queue_idx
  on public.enterprise_workflow_state_executions (
    status,
    retry_at,
    created_at
  )
  where status in ('pending','queued','failed');

-- ============================================================
-- 11. ORCHESTRATION JOB QUEUE
-- ============================================================

create table if not exists public.enterprise_workflow_job_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_instance_id uuid not null references public.enterprise_workflow_instances(id) on delete cascade,
  state_execution_id uuid references public.enterprise_workflow_state_executions(id) on delete cascade,
  token_id uuid references public.enterprise_workflow_tokens(id) on delete set null,

  job_type text not null
    check (
      job_type in (
        'start_instance',
        'execute_state',
        'resume_state',
        'evaluate_transition',
        'join_parallel',
        'run_compensation',
        'timeout_check',
        'process_signal',
        'schedule_trigger',
        'custom'
      )
    ),

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'processing',
        'completed',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,
  available_at timestamptz not null default now(),

  attempts integer not null default 0,
  maximum_attempts integer not null default 10,

  payload jsonb not null default '{}',

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

create index if not exists enterprise_workflow_job_queue_worker_idx
  on public.enterprise_workflow_job_queue (
    status,
    available_at,
    priority,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 12. HUMAN TASKS
-- ============================================================

create table if not exists public.enterprise_workflow_human_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_instance_id uuid not null references public.enterprise_workflow_instances(id) on delete cascade,
  state_execution_id uuid not null references public.enterprise_workflow_state_executions(id) on delete cascade,

  task_key text not null,
  task_title text not null,
  task_description text,

  task_type text not null default 'general'
    check (
      task_type in (
        'general',
        'review',
        'data_entry',
        'approval',
        'verification',
        'followup',
        'document',
        'call',
        'site_visit',
        'custom'
      )
    ),

  status text not null default 'open'
    check (
      status in (
        'open',
        'claimed',
        'in_progress',
        'completed',
        'rejected',
        'cancelled',
        'expired'
      )
    ),

  priority text not null default 'normal'
    check (priority in ('low','normal','high','urgent')),

  assigned_user_id uuid references auth.users(id) on delete set null,
  assigned_role_ids uuid[] not null default '{}',
  assigned_team_ids uuid[] not null default '{}',

  due_at timestamptz,
  claimed_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,

  form_schema jsonb not null default '{}',
  task_data jsonb not null default '{}',
  result_data jsonb not null default '{}',

  resolution_notes text,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workflow_instance_id,task_key)
);

create index if not exists enterprise_workflow_human_tasks_assignment_idx
  on public.enterprise_workflow_human_tasks (
    organization_id,
    assigned_user_id,
    status,
    due_at
  );

-- ============================================================
-- 13. APPROVAL CHAINS
-- ============================================================

create table if not exists public.enterprise_workflow_approval_chains (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  chain_code text not null,
  chain_name text not null,
  description text,

  approval_mode text not null default 'sequential'
    check (
      approval_mode in (
        'sequential',
        'parallel_any',
        'parallel_all',
        'majority',
        'custom'
      )
    ),

  minimum_approvals integer not null default 1,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,chain_code)
);

create table if not exists public.enterprise_workflow_approval_chain_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  approval_chain_id uuid not null references public.enterprise_workflow_approval_chains(id) on delete cascade,

  step_number integer not null,
  step_name text,

  approver_user_ids uuid[] not null default '{}',
  approver_role_ids uuid[] not null default '{}',
  approver_team_ids uuid[] not null default '{}',

  required_approvals integer not null default 1,

  timeout_minutes integer,
  escalation_user_ids uuid[] not null default '{}',

  condition_expression jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (approval_chain_id,step_number)
);

-- ============================================================
-- 14. APPROVAL REQUESTS
-- ============================================================

create table if not exists public.enterprise_workflow_approval_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_instance_id uuid not null references public.enterprise_workflow_instances(id) on delete cascade,
  state_execution_id uuid not null references public.enterprise_workflow_state_executions(id) on delete cascade,
  approval_chain_id uuid references public.enterprise_workflow_approval_chains(id) on delete set null,

  request_title text not null,
  request_description text,

  current_step_number integer not null default 1,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'approved',
        'rejected',
        'expired',
        'cancelled'
      )
    ),

  approval_payload jsonb not null default '{}',

  approved_count integer not null default 0,
  rejected_count integer not null default 0,

  expires_at timestamptz,
  completed_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.enterprise_workflow_approval_responses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  approval_request_id uuid not null references public.enterprise_workflow_approval_requests(id) on delete cascade,
  chain_step_id uuid references public.enterprise_workflow_approval_chain_steps(id) on delete set null,

  responder_user_id uuid not null references auth.users(id) on delete cascade,

  response text not null
    check (response in ('approved','rejected','abstained')),

  response_notes text,
  response_data jsonb not null default '{}',

  responded_at timestamptz not null default now(),

  unique (
    approval_request_id,
    chain_step_id,
    responder_user_id
  )
);

-- ============================================================
-- 15. TIMERS
-- ============================================================

create table if not exists public.enterprise_workflow_timers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_instance_id uuid not null references public.enterprise_workflow_instances(id) on delete cascade,
  state_execution_id uuid references public.enterprise_workflow_state_executions(id) on delete cascade,
  token_id uuid references public.enterprise_workflow_tokens(id) on delete set null,

  timer_type text not null
    check (
      timer_type in (
        'duration',
        'absolute',
        'cron',
        'timeout',
        'reminder',
        'custom'
      )
    ),

  timer_key text not null,
  due_at timestamptz not null,

  cron_expression text,
  timezone text not null default 'Asia/Kolkata',

  status text not null default 'scheduled'
    check (
      status in (
        'scheduled',
        'fired',
        'cancelled',
        'expired',
        'failed'
      )
    ),

  payload jsonb not null default '{}',

  fired_at timestamptz,
  error_message text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (workflow_instance_id,timer_key)
);

create index if not exists enterprise_workflow_timers_due_idx
  on public.enterprise_workflow_timers (
    status,
    due_at
  )
  where status = 'scheduled';

-- ============================================================
-- 16. SIGNAL SUBSCRIPTIONS
-- ============================================================

create table if not exists public.enterprise_workflow_signal_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_instance_id uuid not null references public.enterprise_workflow_instances(id) on delete cascade,
  state_execution_id uuid references public.enterprise_workflow_state_executions(id) on delete cascade,
  token_id uuid references public.enterprise_workflow_tokens(id) on delete set null,

  signal_name text not null,
  correlation_key text,

  filter_expression jsonb not null default '{}',

  status text not null default 'waiting'
    check (
      status in (
        'waiting',
        'received',
        'expired',
        'cancelled'
      )
    ),

  expires_at timestamptz,

  received_payload jsonb,
  received_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists enterprise_workflow_signal_subscriptions_lookup_idx
  on public.enterprise_workflow_signal_subscriptions (
    organization_id,
    signal_name,
    correlation_key,
    status
  );

-- ============================================================
-- 17. INBOUND SIGNALS
-- ============================================================

create table if not exists public.enterprise_workflow_signals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  signal_name text not null,
  correlation_key text,

  signal_source text,
  source_event_id text,

  payload jsonb not null default '{}',

  status text not null default 'received'
    check (
      status in (
        'received',
        'matched',
        'processed',
        'unmatched',
        'failed'
      )
    ),

  matched_subscription_id uuid references public.enterprise_workflow_signal_subscriptions(id) on delete set null,
  matched_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,

  received_at timestamptz not null default now(),
  processed_at timestamptz,

  error_message text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

create unique index if not exists enterprise_workflow_signals_source_unique_idx
  on public.enterprise_workflow_signals (
    organization_id,
    signal_source,
    source_event_id
  )
  where source_event_id is not null;

-- ============================================================
-- 18. COMPENSATION DEFINITIONS
-- ============================================================

create table if not exists public.enterprise_workflow_compensation_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_version_id uuid not null references public.enterprise_workflow_versions(id) on delete cascade,
  state_id uuid not null references public.enterprise_workflow_states(id) on delete cascade,

  compensation_key text not null,
  compensation_name text not null,

  handler_type text not null,
  handler_reference text,

  execution_order integer not null default 100,

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (workflow_version_id,compensation_key)
);

create table if not exists public.enterprise_workflow_compensation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_instance_id uuid not null references public.enterprise_workflow_instances(id) on delete cascade,
  state_execution_id uuid references public.enterprise_workflow_state_executions(id) on delete set null,
  compensation_definition_id uuid not null references public.enterprise_workflow_compensation_definitions(id) on delete restrict,

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

  input_data jsonb not null default '{}',
  output_data jsonb not null default '{}',

  started_at timestamptz,
  completed_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 19. IDEMPOTENCY
-- ============================================================

create table if not exists public.enterprise_workflow_idempotency_records (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_id uuid not null references public.enterprise_workflow_definitions(id) on delete cascade,

  idempotency_key text not null,
  request_hash text,

  workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,

  status text not null default 'processing'
    check (
      status in (
        'processing',
        'completed',
        'failed',
        'expired'
      )
    ),

  response_data jsonb,
  expires_at timestamptz not null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    organization_id,
    workflow_id,
    idempotency_key
  )
);

-- ============================================================
-- 20. DEAD LETTER QUEUE
-- ============================================================

create table if not exists public.enterprise_workflow_dead_letters (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
  state_execution_id uuid references public.enterprise_workflow_state_executions(id) on delete set null,
  job_id uuid references public.enterprise_workflow_job_queue(id) on delete set null,

  failure_type text not null,
  failure_source text,

  payload jsonb not null default '{}',

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  status text not null default 'open'
    check (
      status in (
        'open',
        'retried',
        'resolved',
        'ignored',
        'archived'
      )
    ),

  retried_at timestamptz,
  retried_by uuid references auth.users(id) on delete set null,

  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  resolution_notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 21. EVENT OUTBOX
-- ============================================================

create table if not exists public.enterprise_workflow_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  workflow_id uuid references public.enterprise_workflow_definitions(id) on delete set null,
  workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
  state_execution_id uuid references public.enterprise_workflow_state_executions(id) on delete set null,

  event_name text not null,

  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'automation_engine',
        'communication_engine',
        'notification_engine',
        'integration_api',
        'ai_intelligence',
        'reporting',
        'mobile',
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

  delivery_attempts integer not null default 0,
  maximum_attempts integer not null default 10,

  delivered_at timestamptz,

  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists enterprise_workflow_event_outbox_idem_idx
  on public.enterprise_workflow_event_outbox (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

-- ============================================================
-- 22. LOGS
-- ============================================================

create table if not exists public.enterprise_workflow_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,

  workflow_id uuid references public.enterprise_workflow_definitions(id) on delete set null,
  workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
  state_execution_id uuid references public.enterprise_workflow_state_executions(id) on delete set null,

  log_level text not null default 'info'
    check (
      log_level in (
        'debug',
        'info',
        'warning',
        'error',
        'critical'
      )
    ),

  event_name text,
  message text,

  error_code text,
  error_message text,
  log_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now()
);

create index if not exists enterprise_workflow_logs_org_time_idx
  on public.enterprise_workflow_logs (
    organization_id,
    created_at desc
  );

-- ============================================================
-- 23. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'enterprise_workflow_definitions',
    'enterprise_workflow_states',
    'enterprise_workflow_triggers',
    'enterprise_workflow_variables',
    'enterprise_workflow_instances',
    'enterprise_workflow_tokens',
    'enterprise_workflow_state_executions',
    'enterprise_workflow_job_queue',
    'enterprise_workflow_human_tasks',
    'enterprise_workflow_approval_chains',
    'enterprise_workflow_approval_requests',
    'enterprise_workflow_timers',
    'enterprise_workflow_signal_subscriptions',
    'enterprise_workflow_compensation_runs',
    'enterprise_workflow_idempotency_records',
    'enterprise_workflow_dead_letters',
    'enterprise_workflow_event_outbox'
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
-- 24. CREATE WORKFLOW
-- ============================================================

create or replace function public.create_enterprise_workflow(
  requested_organization_id uuid,
  requested_workflow_code text,
  requested_workflow_name text,
  requested_category text default 'general',
  requested_description text default null,
  requested_orchestration_mode text default 'durable',
  requested_configuration jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.enterprise_workflow_definitions
language plpgsql
security definer
set search_path = ''
as $$
declare
  workflow_record public.enterprise_workflow_definitions;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'enterprise_workflow.create'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.enterprise_workflow_definitions (
    organization_id,
    workflow_code,
    workflow_name,
    description,
    category,
    status,
    orchestration_mode,
    owner_user_id,
    configuration,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    requested_workflow_code,
    requested_workflow_name,
    requested_description,
    requested_category,
    'draft',
    requested_orchestration_mode,
    auth.uid(),
    coalesce(requested_configuration,'{}'::jsonb),
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  on conflict (organization_id,workflow_code)
  do update set
    workflow_name = excluded.workflow_name,
    description = excluded.description,
    category = excluded.category,
    orchestration_mode = excluded.orchestration_mode,
    configuration = excluded.configuration,
    metadata = excluded.metadata,
    updated_by = auth.uid(),
    updated_at = now()
  returning * into workflow_record;

  return workflow_record;
end;
$$;

revoke all
on function public.create_enterprise_workflow(
  uuid,text,text,text,text,text,jsonb,jsonb
)
from public;

grant execute
on function public.create_enterprise_workflow(
  uuid,text,text,text,text,text,jsonb,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 25. CREATE VERSION
-- ============================================================

create or replace function public.create_enterprise_workflow_version(
  requested_workflow_id uuid,
  requested_graph_definition jsonb default '{}'::jsonb,
  requested_input_schema jsonb default '{}'::jsonb,
  requested_output_schema jsonb default '{}'::jsonb,
  requested_variable_schema jsonb default '{}'::jsonb,
  requested_change_summary text default null
)
returns public.enterprise_workflow_versions
language plpgsql
security definer
set search_path = ''
as $$
declare
  workflow_record public.enterprise_workflow_definitions;
  next_version integer;
  version_record public.enterprise_workflow_versions;
begin
  select *
  into workflow_record
  from public.enterprise_workflow_definitions
  where id = requested_workflow_id
  for update;

  if not found then
    raise exception 'Workflow not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      workflow_record.organization_id,
      'enterprise_workflow.update'
    ) then
    raise exception 'Permission denied';
  end if;

  select coalesce(max(version_number),0) + 1
  into next_version
  from public.enterprise_workflow_versions
  where workflow_id = requested_workflow_id;

  update public.enterprise_workflow_versions
  set is_current = false
  where workflow_id = requested_workflow_id
    and is_current = true;

  insert into public.enterprise_workflow_versions (
    organization_id,
    workflow_id,
    version_number,
    version_label,
    status,
    graph_definition,
    input_schema,
    output_schema,
    variable_schema,
    validation_status,
    is_current,
    change_summary,
    created_by
  )
  values (
    workflow_record.organization_id,
    workflow_record.id,
    next_version,
    'Version ' || next_version::text,
    'draft',
    coalesce(requested_graph_definition,'{}'::jsonb),
    coalesce(requested_input_schema,'{}'::jsonb),
    coalesce(requested_output_schema,'{}'::jsonb),
    coalesce(requested_variable_schema,'{}'::jsonb),
    'pending',
    true,
    requested_change_summary,
    auth.uid()
  )
  returning * into version_record;

  return version_record;
end;
$$;

revoke all
on function public.create_enterprise_workflow_version(
  uuid,jsonb,jsonb,jsonb,jsonb,text
)
from public;

grant execute
on function public.create_enterprise_workflow_version(
  uuid,jsonb,jsonb,jsonb,jsonb,text
)
to authenticated,service_role;

-- ============================================================
-- 26. PUBLISH VERSION
-- ============================================================

create or replace function public.publish_enterprise_workflow_version(
  requested_version_id uuid
)
returns public.enterprise_workflow_versions
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_record public.enterprise_workflow_versions;
  workflow_record public.enterprise_workflow_definitions;
  start_state_count integer;
  end_state_count integer;
begin
  select *
  into version_record
  from public.enterprise_workflow_versions
  where id = requested_version_id
  for update;

  if not found then
    raise exception 'Workflow version not found';
  end if;

  select *
  into workflow_record
  from public.enterprise_workflow_definitions
  where id = version_record.workflow_id
  for update;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      workflow_record.organization_id,
      'enterprise_workflow.publish'
    ) then
    raise exception 'Permission denied';
  end if;

  select count(*)
  into start_state_count
  from public.enterprise_workflow_states
  where workflow_version_id = requested_version_id
    and state_type = 'start';

  select count(*)
  into end_state_count
  from public.enterprise_workflow_states
  where workflow_version_id = requested_version_id
    and state_type = 'end';

  if start_state_count <> 1 then
    raise exception 'Workflow must contain exactly one start state';
  end if;

  if end_state_count < 1 then
    raise exception 'Workflow must contain at least one end state';
  end if;

  update public.enterprise_workflow_versions
  set
    status = 'deprecated',
    is_current = false
  where workflow_id = version_record.workflow_id
    and status = 'published'
    and id <> requested_version_id;

  update public.enterprise_workflow_versions
  set
    status = 'published',
    validation_status = 'valid',
    validation_errors = '[]'::jsonb,
    is_current = true,
    published_at = now(),
    published_by = auth.uid()
  where id = requested_version_id
  returning * into version_record;

  update public.enterprise_workflow_definitions
  set
    status = 'active',
    updated_by = auth.uid(),
    updated_at = now()
  where id = version_record.workflow_id;

  return version_record;
end;
$$;

revoke all
on function public.publish_enterprise_workflow_version(uuid)
from public;

grant execute
on function public.publish_enterprise_workflow_version(uuid)
to authenticated,service_role;

-- ============================================================
-- 27. START WORKFLOW INSTANCE
-- ============================================================

create or replace function public.start_enterprise_workflow(
  requested_workflow_id uuid,
  requested_input_data jsonb default '{}'::jsonb,
  requested_instance_type text default 'manual',
  requested_trigger_id uuid default null,
  requested_business_key text default null,
  requested_related_entity_type text default null,
  requested_related_entity_id uuid default null,
  requested_priority integer default 100,
  requested_scheduled_at timestamptz default now(),
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.enterprise_workflow_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  workflow_record public.enterprise_workflow_definitions;
  version_record public.enterprise_workflow_versions;
  start_state_record public.enterprise_workflow_states;
  existing_instance public.enterprise_workflow_instances;
  instance_record public.enterprise_workflow_instances;
  token_record public.enterprise_workflow_tokens;
  state_total integer;
begin
  select *
  into workflow_record
  from public.enterprise_workflow_definitions
  where id = requested_workflow_id
    and status = 'active';

  if not found then
    raise exception 'Active workflow not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      workflow_record.organization_id,
      'enterprise_workflow.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_instance
    from public.enterprise_workflow_instances
    where organization_id = workflow_record.organization_id
      and workflow_id = workflow_record.id
      and idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_instance;
    end if;
  end if;

  select *
  into version_record
  from public.enterprise_workflow_versions
  where workflow_id = workflow_record.id
    and status = 'published'
    and is_current = true
  order by version_number desc
  limit 1;

  if not found then
    raise exception 'Published workflow version not found';
  end if;

  select *
  into start_state_record
  from public.enterprise_workflow_states
  where workflow_version_id = version_record.id
    and state_type = 'start'
  limit 1;

  if not found then
    raise exception 'Workflow start state not found';
  end if;

  select count(*)
  into state_total
  from public.enterprise_workflow_states
  where workflow_version_id = version_record.id;

  insert into public.enterprise_workflow_instances (
    organization_id,
    workflow_id,
    workflow_version_id,
    trigger_id,
    instance_key,
    business_key,
    related_entity_type,
    related_entity_id,
    instance_type,
    status,
    current_state_id,
    priority,
    input_data,
    variables,
    context_data,
    scheduled_at,
    timeout_at,
    requested_by,
    idempotency_key,
    correlation_id,
    trace_id,
    total_state_count,
    active_token_count,
    metadata
  )
  values (
    workflow_record.organization_id,
    workflow_record.id,
    version_record.id,
    requested_trigger_id,
    'WFI-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,20)),
    requested_business_key,
    requested_related_entity_type,
    requested_related_entity_id,
    requested_instance_type,
    'queued',
    start_state_record.id,
    requested_priority,
    coalesce(requested_input_data,'{}'::jsonb),
    '{}'::jsonb,
    jsonb_build_object(
      'workflow_code',workflow_record.workflow_code,
      'version_number',version_record.version_number
    ),
    coalesce(requested_scheduled_at,now()),
    coalesce(requested_scheduled_at,now())
      + make_interval(secs => workflow_record.default_timeout_seconds),
    auth.uid(),
    requested_idempotency_key,
    requested_correlation_id,
    requested_trace_id,
    state_total,
    1,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into instance_record;

  insert into public.enterprise_workflow_tokens (
    organization_id,
    workflow_instance_id,
    token_key,
    current_state_id,
    status,
    token_data
  )
  values (
    instance_record.organization_id,
    instance_record.id,
    'TOKEN-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,16)),
    start_state_record.id,
    'active',
    '{}'::jsonb
  )
  returning * into token_record;

  insert into public.enterprise_workflow_job_queue (
    organization_id,
    workflow_instance_id,
    token_id,
    job_type,
    status,
    priority,
    available_at,
    payload,
    correlation_id,
    trace_id
  )
  values (
    instance_record.organization_id,
    instance_record.id,
    token_record.id,
    'start_instance',
    'queued',
    requested_priority,
    coalesce(requested_scheduled_at,now()),
    jsonb_build_object(
      'workflow_instance_id',instance_record.id,
      'start_state_id',start_state_record.id,
      'token_id',token_record.id
    ),
    instance_record.correlation_id,
    instance_record.trace_id
  );

  if requested_idempotency_key is not null then
    insert into public.enterprise_workflow_idempotency_records (
      organization_id,
      workflow_id,
      idempotency_key,
      request_hash,
      workflow_instance_id,
      status,
      expires_at
    )
    values (
      instance_record.organization_id,
      instance_record.workflow_id,
      requested_idempotency_key,
      encode(
        digest(
          coalesce(requested_input_data,'{}'::jsonb)::text,
          'sha256'
        ),
        'hex'
      ),
      instance_record.id,
      'processing',
      now() + interval '7 days'
    )
    on conflict do nothing;
  end if;

  return instance_record;
end;
$$;

revoke all
on function public.start_enterprise_workflow(
  uuid,jsonb,text,uuid,text,text,uuid,integer,timestamptz,text,text,text,jsonb
)
from public;

grant execute
on function public.start_enterprise_workflow(
  uuid,jsonb,text,uuid,text,text,uuid,integer,timestamptz,text,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 28. CLAIM ORCHESTRATION JOB
-- ============================================================

create or replace function public.claim_enterprise_workflow_job(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.enterprise_workflow_job_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.enterprise_workflow_job_queue;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim workflow jobs';
  end if;

  select *
  into job_record
  from public.enterprise_workflow_job_queue j
  where j.status in ('queued','failed')
    and j.available_at <= now()
    and j.attempts < j.maximum_attempts
    and (
      requested_organization_id is null
      or j.organization_id = requested_organization_id
    )
  order by
    j.priority,
    j.available_at,
    j.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.enterprise_workflow_job_queue
  set
    status = 'claimed',
    attempts = attempts + 1,
    claimed_at = now(),
    claimed_by = requested_worker_id,
    lock_token = gen_random_uuid()::text,
    lock_expires_at = now()
      + make_interval(secs => greatest(requested_lock_seconds,1)),
    updated_at = now()
  where id = job_record.id
  returning * into job_record;

  update public.enterprise_workflow_instances
  set
    status = case
      when status = 'queued' then 'running'
      else status
    end,
    started_at = coalesce(started_at,now()),
    updated_at = now()
  where id = job_record.workflow_instance_id;

  return job_record;
end;
$$;

revoke all
on function public.claim_enterprise_workflow_job(
  text,uuid,integer
)
from public;

grant execute
on function public.claim_enterprise_workflow_job(
  text,uuid,integer
)
to service_role;

-- ============================================================
-- 29. COMPLETE ORCHESTRATION JOB
-- ============================================================

create or replace function public.complete_enterprise_workflow_job(
  requested_job_id uuid,
  requested_lock_token text,
  requested_result_data jsonb default '{}'::jsonb
)
returns public.enterprise_workflow_job_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.enterprise_workflow_job_queue;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete workflow jobs';
  end if;

  select *
  into job_record
  from public.enterprise_workflow_job_queue
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Workflow job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid workflow job lock token';
  end if;

  update public.enterprise_workflow_job_queue
  set
    status = 'completed',
    completed_at = now(),
    payload = payload || jsonb_build_object(
      'result',
      coalesce(requested_result_data,'{}'::jsonb)
    ),
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
on function public.complete_enterprise_workflow_job(
  uuid,text,jsonb
)
from public;

grant execute
on function public.complete_enterprise_workflow_job(
  uuid,text,jsonb
)
to service_role;

-- ============================================================
-- 30. FAIL ORCHESTRATION JOB
-- ============================================================

create or replace function public.fail_enterprise_workflow_job(
  requested_job_id uuid,
  requested_lock_token text,
  requested_error_code text,
  requested_error_message text,
  requested_error_data jsonb default '{}'::jsonb
)
returns public.enterprise_workflow_job_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.enterprise_workflow_job_queue;
  next_status text;
  retry_delay integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may fail workflow jobs';
  end if;

  select *
  into job_record
  from public.enterprise_workflow_job_queue
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Workflow job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid workflow job lock token';
  end if;

  next_status := case
    when job_record.attempts >= job_record.maximum_attempts
      then 'dead_lettered'
    else 'failed'
  end;

  retry_delay := least(
    7200,
    greatest(
      30,
      power(2,greatest(job_record.attempts,1))::integer * 30
    )
  );

  update public.enterprise_workflow_job_queue
  set
    status = next_status,
    available_at = case
      when next_status = 'failed'
        then now() + make_interval(secs => retry_delay)
      else available_at
    end,
    last_error_code = requested_error_code,
    last_error_message = requested_error_message,
    last_error_data = coalesce(requested_error_data,'{}'::jsonb),
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where id = requested_job_id
  returning * into job_record;

  if next_status = 'dead_lettered' then
    insert into public.enterprise_workflow_dead_letters (
      organization_id,
      workflow_instance_id,
      state_execution_id,
      job_id,
      failure_type,
      failure_source,
      payload,
      error_code,
      error_message,
      error_data
    )
    values (
      job_record.organization_id,
      job_record.workflow_instance_id,
      job_record.state_execution_id,
      job_record.id,
      'maximum_attempts_exceeded',
      'enterprise_workflow_job_queue',
      job_record.payload,
      requested_error_code,
      requested_error_message,
      coalesce(requested_error_data,'{}'::jsonb)
    );

    update public.enterprise_workflow_instances
    set
      status = 'dead_lettered',
      error_code = requested_error_code,
      error_message = requested_error_message,
      error_data = coalesce(requested_error_data,'{}'::jsonb),
      updated_at = now()
    where id = job_record.workflow_instance_id;
  end if;

  return job_record;
end;
$$;

revoke all
on function public.fail_enterprise_workflow_job(
  uuid,text,text,text,jsonb
)
from public;

grant execute
on function public.fail_enterprise_workflow_job(
  uuid,text,text,text,jsonb
)
to service_role;

-- ============================================================
-- 31. CREATE HUMAN TASK
-- ============================================================

create or replace function public.create_enterprise_workflow_human_task(
  requested_workflow_instance_id uuid,
  requested_state_execution_id uuid,
  requested_task_key text,
  requested_task_title text,
  requested_task_description text default null,
  requested_task_type text default 'general',
  requested_priority text default 'normal',
  requested_assigned_user_id uuid default null,
  requested_assigned_role_ids uuid[] default '{}',
  requested_assigned_team_ids uuid[] default '{}',
  requested_due_at timestamptz default null,
  requested_form_schema jsonb default '{}'::jsonb,
  requested_task_data jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.enterprise_workflow_human_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.enterprise_workflow_instances;
  task_record public.enterprise_workflow_human_tasks;
begin
  select *
  into instance_record
  from public.enterprise_workflow_instances
  where id = requested_workflow_instance_id;

  if not found then
    raise exception 'Workflow instance not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      instance_record.organization_id,
      'enterprise_workflow.manage_tasks'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.enterprise_workflow_human_tasks (
    organization_id,
    workflow_instance_id,
    state_execution_id,
    task_key,
    task_title,
    task_description,
    task_type,
    status,
    priority,
    assigned_user_id,
    assigned_role_ids,
    assigned_team_ids,
    due_at,
    form_schema,
    task_data,
    metadata,
    created_by
  )
  values (
    instance_record.organization_id,
    instance_record.id,
    requested_state_execution_id,
    requested_task_key,
    requested_task_title,
    requested_task_description,
    requested_task_type,
    'open',
    requested_priority,
    requested_assigned_user_id,
    coalesce(requested_assigned_role_ids,'{}'::uuid[]),
    coalesce(requested_assigned_team_ids,'{}'::uuid[]),
    requested_due_at,
    coalesce(requested_form_schema,'{}'::jsonb),
    coalesce(requested_task_data,'{}'::jsonb),
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid()
  )
  returning * into task_record;

  update public.enterprise_workflow_instances
  set
    status = 'waiting_human_task',
    updated_at = now()
  where id = instance_record.id;

  update public.enterprise_workflow_state_executions
  set
    status = 'waiting_human_task',
    updated_at = now()
  where id = requested_state_execution_id;

  return task_record;
end;
$$;

revoke all
on function public.create_enterprise_workflow_human_task(
  uuid,uuid,text,text,text,text,text,uuid,uuid[],uuid[],timestamptz,jsonb,jsonb,jsonb
)
from public;

grant execute
on function public.create_enterprise_workflow_human_task(
  uuid,uuid,text,text,text,text,text,uuid,uuid[],uuid[],timestamptz,jsonb,jsonb,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 32. COMPLETE HUMAN TASK
-- ============================================================

create or replace function public.complete_enterprise_workflow_human_task(
  requested_task_id uuid,
  requested_status text,
  requested_result_data jsonb default '{}'::jsonb,
  requested_resolution_notes text default null
)
returns public.enterprise_workflow_human_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  task_record public.enterprise_workflow_human_tasks;
begin
  select *
  into task_record
  from public.enterprise_workflow_human_tasks
  where id = requested_task_id
  for update;

  if not found then
    raise exception 'Human task not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from task_record.assigned_user_id
    and not public.has_organization_permission(
      task_record.organization_id,
      'enterprise_workflow.manage_tasks'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_status not in ('completed','rejected','cancelled') then
    raise exception 'Invalid final human task status';
  end if;

  update public.enterprise_workflow_human_tasks
  set
    status = requested_status,
    result_data = coalesce(requested_result_data,'{}'::jsonb),
    resolution_notes = requested_resolution_notes,
    completed_at = now(),
    updated_at = now()
  where id = requested_task_id
  returning * into task_record;

  update public.enterprise_workflow_state_executions
  set
    status = case
      when requested_status = 'completed' then 'completed'
      when requested_status = 'rejected' then 'failed'
      else 'cancelled'
    end,
    output_data = output_data || jsonb_build_object(
      'human_task_result',
      coalesce(requested_result_data,'{}'::jsonb)
    ),
    completed_at = now(),
    updated_at = now()
  where id = task_record.state_execution_id;

  update public.enterprise_workflow_instances
  set
    status = case
      when requested_status = 'completed' then 'running'
      when requested_status = 'rejected' then 'failed'
      else 'cancelled'
    end,
    updated_at = now()
  where id = task_record.workflow_instance_id;

  return task_record;
end;
$$;

revoke all
on function public.complete_enterprise_workflow_human_task(
  uuid,text,jsonb,text
)
from public;

grant execute
on function public.complete_enterprise_workflow_human_task(
  uuid,text,jsonb,text
)
to authenticated,service_role;

-- ============================================================
-- 33. SCHEDULE TIMER
-- ============================================================

create or replace function public.schedule_enterprise_workflow_timer(
  requested_workflow_instance_id uuid,
  requested_timer_key text,
  requested_due_at timestamptz,
  requested_timer_type text default 'absolute',
  requested_state_execution_id uuid default null,
  requested_token_id uuid default null,
  requested_cron_expression text default null,
  requested_timezone text default 'Asia/Kolkata',
  requested_payload jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.enterprise_workflow_timers
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.enterprise_workflow_instances;
  timer_record public.enterprise_workflow_timers;
begin
  select *
  into instance_record
  from public.enterprise_workflow_instances
  where id = requested_workflow_instance_id;

  if not found then
    raise exception 'Workflow instance not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      instance_record.organization_id,
      'enterprise_workflow.manage_schedules'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.enterprise_workflow_timers (
    organization_id,
    workflow_instance_id,
    state_execution_id,
    token_id,
    timer_type,
    timer_key,
    due_at,
    cron_expression,
    timezone,
    status,
    payload,
    metadata
  )
  values (
    instance_record.organization_id,
    instance_record.id,
    requested_state_execution_id,
    requested_token_id,
    requested_timer_type,
    requested_timer_key,
    requested_due_at,
    requested_cron_expression,
    requested_timezone,
    'scheduled',
    coalesce(requested_payload,'{}'::jsonb),
    coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (workflow_instance_id,timer_key)
  do update set
    state_execution_id = excluded.state_execution_id,
    token_id = excluded.token_id,
    timer_type = excluded.timer_type,
    due_at = excluded.due_at,
    cron_expression = excluded.cron_expression,
    timezone = excluded.timezone,
    status = 'scheduled',
    payload = excluded.payload,
    metadata = excluded.metadata,
    updated_at = now()
  returning * into timer_record;

  update public.enterprise_workflow_instances
  set
    status = 'waiting_timer',
    updated_at = now()
  where id = instance_record.id;

  return timer_record;
end;
$$;

revoke all
on function public.schedule_enterprise_workflow_timer(
  uuid,text,timestamptz,text,uuid,uuid,text,text,jsonb,jsonb
)
from public;

grant execute
on function public.schedule_enterprise_workflow_timer(
  uuid,text,timestamptz,text,uuid,uuid,text,text,jsonb,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 34. SUBSCRIBE TO SIGNAL
-- ============================================================

create or replace function public.subscribe_enterprise_workflow_signal(
  requested_workflow_instance_id uuid,
  requested_signal_name text,
  requested_correlation_key text default null,
  requested_state_execution_id uuid default null,
  requested_token_id uuid default null,
  requested_filter_expression jsonb default '{}'::jsonb,
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.enterprise_workflow_signal_subscriptions
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.enterprise_workflow_instances;
  subscription_record public.enterprise_workflow_signal_subscriptions;
begin
  select *
  into instance_record
  from public.enterprise_workflow_instances
  where id = requested_workflow_instance_id;

  if not found then
    raise exception 'Workflow instance not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      instance_record.organization_id,
      'enterprise_workflow.manage_events'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.enterprise_workflow_signal_subscriptions (
    organization_id,
    workflow_instance_id,
    state_execution_id,
    token_id,
    signal_name,
    correlation_key,
    filter_expression,
    status,
    expires_at,
    metadata
  )
  values (
    instance_record.organization_id,
    instance_record.id,
    requested_state_execution_id,
    requested_token_id,
    requested_signal_name,
    requested_correlation_key,
    coalesce(requested_filter_expression,'{}'::jsonb),
    'waiting',
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into subscription_record;

  update public.enterprise_workflow_instances
  set
    status = 'waiting_signal',
    updated_at = now()
  where id = instance_record.id;

  return subscription_record;
end;
$$;

revoke all
on function public.subscribe_enterprise_workflow_signal(
  uuid,text,text,uuid,uuid,jsonb,timestamptz,jsonb
)
from public;

grant execute
on function public.subscribe_enterprise_workflow_signal(
  uuid,text,text,uuid,uuid,jsonb,timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 35. PUBLISH SIGNAL
-- ============================================================

create or replace function public.publish_enterprise_workflow_signal(
  requested_organization_id uuid,
  requested_signal_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_correlation_key text default null,
  requested_signal_source text default null,
  requested_source_event_id text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.enterprise_workflow_signals
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_signal public.enterprise_workflow_signals;
  subscription_record public.enterprise_workflow_signal_subscriptions;
  signal_record public.enterprise_workflow_signals;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'enterprise_workflow.manage_events'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_source_event_id is not null then
    select *
    into existing_signal
    from public.enterprise_workflow_signals
    where organization_id = requested_organization_id
      and signal_source is not distinct from requested_signal_source
      and source_event_id = requested_source_event_id
    limit 1;

    if found then
      return existing_signal;
    end if;
  end if;

  select *
  into subscription_record
  from public.enterprise_workflow_signal_subscriptions
  where organization_id = requested_organization_id
    and signal_name = requested_signal_name
    and status = 'waiting'
    and (
      correlation_key is null
      or correlation_key = requested_correlation_key
    )
    and (
      expires_at is null
      or expires_at > now()
    )
  order by created_at
  for update skip locked
  limit 1;

  insert into public.enterprise_workflow_signals (
    organization_id,
    signal_name,
    correlation_key,
    signal_source,
    source_event_id,
    payload,
    status,
    matched_subscription_id,
    matched_instance_id,
    metadata
  )
  values (
    requested_organization_id,
    requested_signal_name,
    requested_correlation_key,
    requested_signal_source,
    requested_source_event_id,
    coalesce(requested_payload,'{}'::jsonb),
    case when subscription_record.id is null then 'unmatched' else 'matched' end,
    subscription_record.id,
    subscription_record.workflow_instance_id,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into signal_record;

  if subscription_record.id is not null then
    update public.enterprise_workflow_signal_subscriptions
    set
      status = 'received',
      received_payload = coalesce(requested_payload,'{}'::jsonb),
      received_at = now(),
      updated_at = now()
    where id = subscription_record.id;

    insert into public.enterprise_workflow_job_queue (
      organization_id,
      workflow_instance_id,
      state_execution_id,
      token_id,
      job_type,
      status,
      priority,
      available_at,
      payload
    )
    values (
      subscription_record.organization_id,
      subscription_record.workflow_instance_id,
      subscription_record.state_execution_id,
      subscription_record.token_id,
      'process_signal',
      'queued',
      50,
      now(),
      jsonb_build_object(
        'signal_id',signal_record.id,
        'subscription_id',subscription_record.id,
        'payload',coalesce(requested_payload,'{}'::jsonb)
      )
    );

    update public.enterprise_workflow_instances
    set
      status = 'running',
      updated_at = now()
    where id = subscription_record.workflow_instance_id;
  end if;

  return signal_record;
end;
$$;

revoke all
on function public.publish_enterprise_workflow_signal(
  uuid,text,jsonb,text,text,text,jsonb
)
from public;

grant execute
on function public.publish_enterprise_workflow_signal(
  uuid,text,jsonb,text,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 36. CANCEL WORKFLOW INSTANCE
-- ============================================================

create or replace function public.cancel_enterprise_workflow_instance(
  requested_workflow_instance_id uuid,
  requested_reason text default null
)
returns public.enterprise_workflow_instances
language plpgsql
security definer
set search_path = ''
as $$
declare
  instance_record public.enterprise_workflow_instances;
begin
  select *
  into instance_record
  from public.enterprise_workflow_instances
  where id = requested_workflow_instance_id
  for update;

  if not found then
    raise exception 'Workflow instance not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      instance_record.organization_id,
      'enterprise_workflow.cancel'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.enterprise_workflow_instances
  set
    status = 'cancelled',
    completed_at = now(),
    error_message = requested_reason,
    updated_at = now()
  where id = requested_workflow_instance_id
  returning * into instance_record;

  update public.enterprise_workflow_job_queue
  set
    status = 'cancelled',
    updated_at = now()
  where workflow_instance_id = requested_workflow_instance_id
    and status in ('queued','claimed','processing','failed');

  update public.enterprise_workflow_state_executions
  set
    status = 'cancelled',
    completed_at = now(),
    updated_at = now()
  where workflow_instance_id = requested_workflow_instance_id
    and status not in (
      'completed',
      'failed',
      'skipped',
      'cancelled',
      'compensated'
    );

  update public.enterprise_workflow_tokens
  set
    status = 'cancelled',
    updated_at = now()
  where workflow_instance_id = requested_workflow_instance_id
    and status in ('active','waiting');

  update public.enterprise_workflow_human_tasks
  set
    status = 'cancelled',
    completed_at = now(),
    updated_at = now()
  where workflow_instance_id = requested_workflow_instance_id
    and status in ('open','claimed','in_progress');

  update public.enterprise_workflow_timers
  set
    status = 'cancelled',
    updated_at = now()
  where workflow_instance_id = requested_workflow_instance_id
    and status = 'scheduled';

  update public.enterprise_workflow_signal_subscriptions
  set
    status = 'cancelled',
    updated_at = now()
  where workflow_instance_id = requested_workflow_instance_id
    and status = 'waiting';

  return instance_record;
end;
$$;

revoke all
on function public.cancel_enterprise_workflow_instance(
  uuid,text
)
from public;

grant execute
on function public.cancel_enterprise_workflow_instance(
  uuid,text
)
to authenticated,service_role;

-- ============================================================
-- 37. PUBLISH WORKFLOW EVENT
-- ============================================================

create or replace function public.publish_enterprise_workflow_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_workflow_id uuid default null,
  requested_workflow_instance_id uuid default null,
  requested_state_execution_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.enterprise_workflow_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.enterprise_workflow_event_outbox;
  created_event public.enterprise_workflow_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.enterprise_workflow_event_outbox
    where organization_id is not distinct from requested_organization_id
      and idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.enterprise_workflow_event_outbox (
    organization_id,
    workflow_id,
    workflow_instance_id,
    state_execution_id,
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
    requested_workflow_id,
    requested_workflow_instance_id,
    requested_state_execution_id,
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
on function public.publish_enterprise_workflow_event(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_enterprise_workflow_event(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 38. INSTANCE EVENT TRIGGER
-- ============================================================

create or replace function public.emit_enterprise_workflow_instance_events()
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

  perform public.publish_enterprise_workflow_event(
    new.organization_id,
    'enterprise_workflow.instance.' || new.status,
    jsonb_build_object(
      'workflow_instance_id',new.id,
      'workflow_id',new.workflow_id,
      'workflow_version_id',new.workflow_version_id,
      'status',new.status,
      'business_key',new.business_key,
      'related_entity_type',new.related_entity_type,
      'related_entity_id',new.related_entity_id,
      'completed_state_count',new.completed_state_count,
      'failed_state_count',new.failed_state_count,
      'active_token_count',new.active_token_count,
      'error_code',new.error_code,
      'error_message',new.error_message
    ),
    case
      when new.status in ('failed','timed_out','dead_lettered')
        then 'notification_engine'
      when new.status = 'completed'
        then 'analytics'
      else 'internal'
    end,
    new.workflow_id,
    new.id,
    null,
    case
      when new.status in ('failed','timed_out','dead_lettered') then 10
      else 50
    end,
    'enterprise-workflow-instance:' || new.id::text || ':' || new.status,
    coalesce(new.correlation_id,new.id::text),
    new.trace_id,
    now()
  );

  return new;
end;
$$;

drop trigger if exists enterprise_workflow_instances_emit_events
on public.enterprise_workflow_instances;

create trigger enterprise_workflow_instances_emit_events
after insert or update
on public.enterprise_workflow_instances
for each row
execute function public.emit_enterprise_workflow_instance_events();

-- ============================================================
-- 39. ANALYTICS VIEWS
-- ============================================================

create or replace view public.enterprise_workflow_instance_dashboard
with (security_invoker = true)
as
select
  i.organization_id,
  i.workflow_id,
  w.workflow_code,
  w.workflow_name,
  i.status,

  count(*) as instance_count,

  count(*) filter (
    where i.status = 'completed'
  ) as completed_count,

  count(*) filter (
    where i.status in ('failed','timed_out','dead_lettered')
  ) as failed_count,

  count(*) filter (
    where i.status in (
      'waiting',
      'waiting_signal',
      'waiting_timer',
      'waiting_approval',
      'waiting_human_task'
    )
  ) as waiting_count,

  round(
    count(*) filter (
      where i.status = 'completed'
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as success_rate,

  round(
    avg(
      extract(
        epoch from (
          coalesce(i.completed_at,now())
          - coalesce(i.started_at,i.created_at)
        )
      ) * 1000
    ),
    2
  ) as average_duration_ms,

  max(i.completed_at) as latest_completion_at,
  max(i.created_at) as latest_instance_at

from public.enterprise_workflow_instances i
join public.enterprise_workflow_definitions w
  on w.id = i.workflow_id
group by
  i.organization_id,
  i.workflow_id,
  w.workflow_code,
  w.workflow_name,
  i.status;

create or replace view public.enterprise_workflow_state_dashboard
with (security_invoker = true)
as
select
  s.organization_id,
  s.state_id,
  d.state_key,
  d.state_name,
  d.state_type,
  s.status,

  count(*) as execution_count,

  round(avg(s.duration_ms),2) as average_duration_ms,

  count(*) filter (
    where s.status = 'completed'
  ) as completed_count,

  count(*) filter (
    where s.status in ('failed','timed_out')
  ) as failed_count,

  max(s.completed_at) as latest_completion_at

from public.enterprise_workflow_state_executions s
join public.enterprise_workflow_states d
  on d.id = s.state_id
group by
  s.organization_id,
  s.state_id,
  d.state_key,
  d.state_name,
  d.state_type,
  s.status;

create or replace view public.enterprise_workflow_task_dashboard
with (security_invoker = true)
as
select
  organization_id,
  task_type,
  status,
  priority,

  count(*) as task_count,

  count(*) filter (
    where due_at is not null
      and due_at < now()
      and status not in ('completed','rejected','cancelled','expired')
  ) as overdue_count,

  round(
    avg(
      extract(
        epoch from (
          coalesce(completed_at,now())
          - created_at
        )
      ) / 60
    ),
    2
  ) as average_resolution_minutes,

  max(completed_at) as latest_completion_at

from public.enterprise_workflow_human_tasks
group by
  organization_id,
  task_type,
  status,
  priority;

create or replace view public.enterprise_workflow_queue_dashboard
with (security_invoker = true)
as
select
  organization_id,
  job_type,
  status,

  count(*) as job_count,
  coalesce(sum(attempts),0) as total_attempts,

  count(*) filter (
    where status in ('queued','failed')
      and available_at <= now()
  ) as due_jobs,

  min(available_at) filter (
    where status in ('queued','failed')
  ) as next_available_at,

  max(completed_at) as latest_completion_at

from public.enterprise_workflow_job_queue
group by
  organization_id,
  job_type,
  status;

create or replace view public.enterprise_workflow_wait_dashboard
with (security_invoker = true)
as
select
  i.organization_id,
  i.status,

  count(*) as waiting_instance_count,

  count(*) filter (
    where i.status = 'waiting_signal'
  ) as waiting_signal_count,

  count(*) filter (
    where i.status = 'waiting_timer'
  ) as waiting_timer_count,

  count(*) filter (
    where i.status = 'waiting_approval'
  ) as waiting_approval_count,

  count(*) filter (
    where i.status = 'waiting_human_task'
  ) as waiting_human_task_count,

  max(i.updated_at) as latest_wait_update_at

from public.enterprise_workflow_instances i
where i.status in (
  'waiting',
  'waiting_signal',
  'waiting_timer',
  'waiting_approval',
  'waiting_human_task'
)
group by
  i.organization_id,
  i.status;

grant select
on
  public.enterprise_workflow_instance_dashboard,
  public.enterprise_workflow_state_dashboard,
  public.enterprise_workflow_task_dashboard,
  public.enterprise_workflow_queue_dashboard,
  public.enterprise_workflow_wait_dashboard
to authenticated,service_role;

-- ============================================================
-- 40. HEALTH CHECK
-- ============================================================

create or replace function public.get_enterprise_workflow_health(
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
        'enterprise_workflow.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'active_workflows',(
      select count(*)
      from public.enterprise_workflow_definitions w
      where w.status = 'active'
        and (
          requested_organization_id is null
          or w.organization_id = requested_organization_id
        )
    ),

    'active_triggers',(
      select count(*)
      from public.enterprise_workflow_triggers t
      where t.status = 'active'
        and t.enabled = true
        and (
          requested_organization_id is null
          or t.organization_id = requested_organization_id
        )
    ),

    'running_instances',(
      select count(*)
      from public.enterprise_workflow_instances i
      where i.status in (
        'queued',
        'running',
        'waiting',
        'waiting_signal',
        'waiting_timer',
        'waiting_approval',
        'waiting_human_task',
        'compensating'
      )
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'queued_jobs',(
      select count(*)
      from public.enterprise_workflow_job_queue j
      where j.status in ('queued','claimed','processing','failed')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'expired_worker_locks',(
      select count(*)
      from public.enterprise_workflow_job_queue j
      where j.status = 'claimed'
        and j.lock_expires_at <= now()
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'overdue_human_tasks',(
      select count(*)
      from public.enterprise_workflow_human_tasks t
      where t.due_at is not null
        and t.due_at < now()
        and t.status in ('open','claimed','in_progress')
        and (
          requested_organization_id is null
          or t.organization_id = requested_organization_id
        )
    ),

    'due_timers',(
      select count(*)
      from public.enterprise_workflow_timers t
      where t.status = 'scheduled'
        and t.due_at <= now()
        and (
          requested_organization_id is null
          or t.organization_id = requested_organization_id
        )
    ),

    'waiting_signals',(
      select count(*)
      from public.enterprise_workflow_signal_subscriptions s
      where s.status = 'waiting'
        and (
          requested_organization_id is null
          or s.organization_id = requested_organization_id
        )
    ),

    'open_dead_letters',(
      select count(*)
      from public.enterprise_workflow_dead_letters d
      where d.status = 'open'
        and (
          requested_organization_id is null
          or d.organization_id = requested_organization_id
        )
    ),

    'failed_instances_24h',(
      select count(*)
      from public.enterprise_workflow_instances i
      where i.status in ('failed','timed_out','dead_lettered')
        and i.updated_at >= now() - interval '24 hours'
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.enterprise_workflow_event_outbox e
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
on function public.get_enterprise_workflow_health(uuid)
from public;

grant execute
on function public.get_enterprise_workflow_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 41. ROW LEVEL SECURITY
-- ============================================================

alter table public.enterprise_workflow_definitions enable row level security;
alter table public.enterprise_workflow_versions enable row level security;
alter table public.enterprise_workflow_states enable row level security;
alter table public.enterprise_workflow_transitions enable row level security;
alter table public.enterprise_workflow_triggers enable row level security;
alter table public.enterprise_workflow_variables enable row level security;
alter table public.enterprise_workflow_instances enable row level security;
alter table public.enterprise_workflow_tokens enable row level security;
alter table public.enterprise_workflow_state_executions enable row level security;
alter table public.enterprise_workflow_job_queue enable row level security;
alter table public.enterprise_workflow_human_tasks enable row level security;
alter table public.enterprise_workflow_approval_chains enable row level security;
alter table public.enterprise_workflow_approval_chain_steps enable row level security;
alter table public.enterprise_workflow_approval_requests enable row level security;
alter table public.enterprise_workflow_approval_responses enable row level security;
alter table public.enterprise_workflow_timers enable row level security;
alter table public.enterprise_workflow_signal_subscriptions enable row level security;
alter table public.enterprise_workflow_signals enable row level security;
alter table public.enterprise_workflow_compensation_definitions enable row level security;
alter table public.enterprise_workflow_compensation_runs enable row level security;
alter table public.enterprise_workflow_idempotency_records enable row level security;
alter table public.enterprise_workflow_dead_letters enable row level security;
alter table public.enterprise_workflow_event_outbox enable row level security;
alter table public.enterprise_workflow_logs enable row level security;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'enterprise_workflow_definitions',
    'enterprise_workflow_versions',
    'enterprise_workflow_states',
    'enterprise_workflow_transitions',
    'enterprise_workflow_triggers',
    'enterprise_workflow_variables',
    'enterprise_workflow_instances',
    'enterprise_workflow_tokens',
    'enterprise_workflow_state_executions',
    'enterprise_workflow_job_queue',
    'enterprise_workflow_human_tasks',
    'enterprise_workflow_approval_chains',
    'enterprise_workflow_approval_chain_steps',
    'enterprise_workflow_approval_requests',
    'enterprise_workflow_approval_responses',
    'enterprise_workflow_timers',
    'enterprise_workflow_signal_subscriptions',
    'enterprise_workflow_signals',
    'enterprise_workflow_compensation_definitions',
    'enterprise_workflow_compensation_runs',
    'enterprise_workflow_idempotency_records',
    'enterprise_workflow_dead_letters',
    'enterprise_workflow_event_outbox',
    'enterprise_workflow_logs'
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
           ''enterprise_workflow.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''enterprise_workflow.view_all''
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

drop policy if exists enterprise_workflow_definitions_write_policy
on public.enterprise_workflow_definitions;

create policy enterprise_workflow_definitions_write_policy
on public.enterprise_workflow_definitions
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'enterprise_workflow.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'enterprise_workflow.create'
  )
  or public.has_organization_permission(
    organization_id,
    'enterprise_workflow.update'
  )
);

drop policy if exists enterprise_workflow_human_tasks_assignee_policy
on public.enterprise_workflow_human_tasks;

create policy enterprise_workflow_human_tasks_assignee_policy
on public.enterprise_workflow_human_tasks
for update
to authenticated
using (
  assigned_user_id = auth.uid()
  or public.has_organization_permission(
    organization_id,
    'enterprise_workflow.manage_tasks'
  )
)
with check (
  assigned_user_id = auth.uid()
  or public.has_organization_permission(
    organization_id,
    'enterprise_workflow.manage_tasks'
  )
);

-- ============================================================
-- 42. GRANTS
-- ============================================================

grant select
on
  public.enterprise_workflow_definitions,
  public.enterprise_workflow_versions,
  public.enterprise_workflow_states,
  public.enterprise_workflow_transitions,
  public.enterprise_workflow_triggers,
  public.enterprise_workflow_variables,
  public.enterprise_workflow_instances,
  public.enterprise_workflow_tokens,
  public.enterprise_workflow_state_executions,
  public.enterprise_workflow_job_queue,
  public.enterprise_workflow_human_tasks,
  public.enterprise_workflow_approval_chains,
  public.enterprise_workflow_approval_chain_steps,
  public.enterprise_workflow_approval_requests,
  public.enterprise_workflow_approval_responses,
  public.enterprise_workflow_timers,
  public.enterprise_workflow_signal_subscriptions,
  public.enterprise_workflow_signals,
  public.enterprise_workflow_compensation_definitions,
  public.enterprise_workflow_compensation_runs,
  public.enterprise_workflow_idempotency_records,
  public.enterprise_workflow_dead_letters,
  public.enterprise_workflow_event_outbox,
  public.enterprise_workflow_logs
to authenticated;

grant insert,update,delete
on
  public.enterprise_workflow_definitions,
  public.enterprise_workflow_versions,
  public.enterprise_workflow_states,
  public.enterprise_workflow_transitions,
  public.enterprise_workflow_triggers,
  public.enterprise_workflow_variables,
  public.enterprise_workflow_approval_chains,
  public.enterprise_workflow_approval_chain_steps,
  public.enterprise_workflow_compensation_definitions
to authenticated;

grant insert,update
on
  public.enterprise_workflow_human_tasks,
  public.enterprise_workflow_approval_requests,
  public.enterprise_workflow_approval_responses,
  public.enterprise_workflow_timers,
  public.enterprise_workflow_signal_subscriptions,
  public.enterprise_workflow_signals
to authenticated;

grant all
on
  public.enterprise_workflow_definitions,
  public.enterprise_workflow_versions,
  public.enterprise_workflow_states,
  public.enterprise_workflow_transitions,
  public.enterprise_workflow_triggers,
  public.enterprise_workflow_variables,
  public.enterprise_workflow_instances,
  public.enterprise_workflow_tokens,
  public.enterprise_workflow_state_executions,
  public.enterprise_workflow_job_queue,
  public.enterprise_workflow_human_tasks,
  public.enterprise_workflow_approval_chains,
  public.enterprise_workflow_approval_chain_steps,
  public.enterprise_workflow_approval_requests,
  public.enterprise_workflow_approval_responses,
  public.enterprise_workflow_timers,
  public.enterprise_workflow_signal_subscriptions,
  public.enterprise_workflow_signals,
  public.enterprise_workflow_compensation_definitions,
  public.enterprise_workflow_compensation_runs,
  public.enterprise_workflow_idempotency_records,
  public.enterprise_workflow_dead_letters,
  public.enterprise_workflow_event_outbox,
  public.enterprise_workflow_logs
to service_role;

-- ============================================================
-- 43. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'enterprise_workflow_definitions',
    'enterprise_workflow_versions',
    'enterprise_workflow_states',
    'enterprise_workflow_transitions',
    'enterprise_workflow_triggers',
    'enterprise_workflow_variables',
    'enterprise_workflow_instances',
    'enterprise_workflow_tokens',
    'enterprise_workflow_state_executions',
    'enterprise_workflow_job_queue',
    'enterprise_workflow_human_tasks',
    'enterprise_workflow_approval_chains',
    'enterprise_workflow_approval_chain_steps',
    'enterprise_workflow_approval_requests',
    'enterprise_workflow_approval_responses',
    'enterprise_workflow_timers',
    'enterprise_workflow_signal_subscriptions',
    'enterprise_workflow_signals',
    'enterprise_workflow_compensation_definitions',
    'enterprise_workflow_compensation_runs',
    'enterprise_workflow_idempotency_records',
    'enterprise_workflow_dead_letters',
    'enterprise_workflow_event_outbox',
    'enterprise_workflow_logs'
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
    'create_enterprise_workflow',
    'create_enterprise_workflow_version',
    'publish_enterprise_workflow_version',
    'start_enterprise_workflow',
    'claim_enterprise_workflow_job',
    'complete_enterprise_workflow_job',
    'fail_enterprise_workflow_job',
    'create_enterprise_workflow_human_task',
    'complete_enterprise_workflow_human_task',
    'schedule_enterprise_workflow_timer',
    'subscribe_enterprise_workflow_signal',
    'publish_enterprise_workflow_signal',
    'cancel_enterprise_workflow_instance',
    'publish_enterprise_workflow_event',
    'get_enterprise_workflow_health'
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
      '028 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 44. MIGRATION AUDIT
-- ============================================================

insert into public.enterprise_workflow_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.028.completed',
  'Enterprise Workflow Orchestration migration 028 completed',
  jsonb_build_object(
    'migration',
    '028_enterprise_workflow_orchestration',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'definitions',
      'versions',
      'states',
      'transitions',
      'triggers',
      'variables',
      'instances',
      'tokens',
      'state_executions',
      'worker_queue',
      'human_tasks',
      'approval_chains',
      'approval_requests',
      'timers',
      'signals',
      'compensations',
      'idempotency',
      'dead_letters',
      'analytics',
      'event_outbox'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.enterprise_workflow_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.028.completed'
);

commit;