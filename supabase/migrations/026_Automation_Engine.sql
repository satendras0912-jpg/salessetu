-- ============================================================
-- SalesSetu Enterprise
-- Migration 026: Automation Engine
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
--
-- Purpose:
--   This migration adds the enterprise orchestration layer above the
--   existing workflow and automation-execution foundations.
--
-- Scope:
--   • Automation definitions, versions and deployment states
--   • Trigger registry: event, webhook, schedule, manual and data change
--   • Node graph, conditions, branching, loops, waits and approvals
--   • Execution instances, node runs and worker queue
--   • Retry policies, dead-letter handling and idempotency
--   • Scheduled executions and delayed jobs
--   • Human approval requests
--   • Automation variables, secrets references and execution context
--   • AI-agent, communication, notification and integration actions
--   • Event outbox, logs, analytics, RLS and health checks
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
    ('automation_engine','view','automation_engine.view','View automation engine data'),
    ('automation_engine','view_all','automation_engine.view_all','View all organization automations'),
    ('automation_engine','create','automation_engine.create','Create automations'),
    ('automation_engine','update','automation_engine.update','Update automations'),
    ('automation_engine','delete','automation_engine.delete','Archive automations'),
    ('automation_engine','publish','automation_engine.publish','Publish automation versions'),
    ('automation_engine','execute','automation_engine.execute','Execute automations'),
    ('automation_engine','cancel','automation_engine.cancel','Cancel automation executions'),
    ('automation_engine','retry','automation_engine.retry','Retry failed automation jobs'),
    ('automation_engine','approve','automation_engine.approve','Approve human approval steps'),
    ('automation_engine','manage_triggers','automation_engine.manage_triggers','Manage automation triggers'),
    ('automation_engine','manage_workers','automation_engine.manage_workers','Manage automation workers'),
    ('automation_engine','manage_schedules','automation_engine.manage_schedules','Manage automation schedules'),
    ('automation_engine','manage_secrets','automation_engine.manage_secrets','Manage automation secret references'),
    ('automation_engine','view_logs','automation_engine.view_logs','View automation logs'),
    ('automation_engine','view_analytics','automation_engine.view_analytics','View automation analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. AUTOMATION DEFINITIONS
-- ============================================================

create table if not exists public.automation_definitions_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_code text not null,
  automation_name text not null,
  description text,

  category text not null default 'general'
    check (
      category in (
        'lead',
        'assignment',
        'followup',
        'communication',
        'notification',
        'site_visit',
        'booking',
        'finance',
        'customer_success',
        'ai',
        'integration',
        'reporting',
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

  execution_mode text not null default 'asynchronous'
    check (
      execution_mode in (
        'synchronous',
        'asynchronous',
        'hybrid'
      )
    ),

  concurrency_policy text not null default 'allow'
    check (
      concurrency_policy in (
        'allow',
        'skip_if_running',
        'cancel_previous',
        'queue'
      )
    ),

  maximum_concurrent_executions integer not null default 10,
  default_timeout_seconds integer not null default 900,

  default_retry_policy_id uuid,
  owner_user_id uuid references auth.users(id) on delete set null,

  is_system_automation boolean not null default false,

  tags text[] not null default '{}',
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,automation_code)
);

create index if not exists automation_definitions_v2_org_status_idx
  on public.automation_definitions_v2 (
    organization_id,
    status,
    category
  );

-- ============================================================
-- 3. RETRY POLICIES
-- ============================================================

create table if not exists public.automation_retry_policies_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  policy_code text not null,
  policy_name text not null,

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

  initial_delay_seconds integer not null default 30,
  maximum_delay_seconds integer not null default 3600,
  multiplier numeric(8,4) not null default 2,
  jitter_enabled boolean not null default true,

  retryable_error_codes text[] not null default '{}',
  non_retryable_error_codes text[] not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  is_system_policy boolean not null default false,
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,policy_code)
);

create unique index if not exists automation_retry_policies_v2_system_unique_idx
  on public.automation_retry_policies_v2(policy_code)
  where organization_id is null;

insert into public.automation_retry_policies_v2 (
  organization_id,
  policy_code,
  policy_name,
  maximum_attempts,
  retry_strategy,
  initial_delay_seconds,
  maximum_delay_seconds,
  multiplier,
  jitter_enabled,
  is_system_policy
)
values
  (null,'no_retry','No Retry',1,'none',0,0,1,false,true),
  (null,'standard','Standard Retry',3,'exponential',30,1800,2,true,true),
  (null,'aggressive','Aggressive Retry',8,'exponential',15,3600,2,true,true),
  (null,'slow_external','Slow External Service Retry',5,'exponential',120,21600,2,true,true)
on conflict do nothing;

alter table public.automation_definitions_v2
  drop constraint if exists automation_definitions_v2_default_retry_policy_id_fkey;

alter table public.automation_definitions_v2
  add constraint automation_definitions_v2_default_retry_policy_id_fkey
  foreign key (default_retry_policy_id)
  references public.automation_retry_policies_v2(id)
  on delete set null;

-- ============================================================
-- 4. AUTOMATION VERSIONS
-- ============================================================

create table if not exists public.automation_versions_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automation_definitions_v2(id) on delete cascade,

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

  unique (automation_id,version_number)
);

create unique index if not exists automation_versions_v2_current_unique_idx
  on public.automation_versions_v2(automation_id)
  where is_current = true;

-- ============================================================
-- 5. AUTOMATION TRIGGERS
-- ============================================================

create table if not exists public.automation_triggers_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automation_definitions_v2(id) on delete cascade,
  automation_version_id uuid references public.automation_versions_v2(id) on delete set null,

  trigger_code text not null,
  trigger_name text not null,

  trigger_type text not null
    check (
      trigger_type in (
        'manual',
        'event',
        'webhook',
        'schedule',
        'database_change',
        'api',
        'form_submission',
        'message_received',
        'ai_decision',
        'custom'
      )
    ),

  event_pattern text,
  source_module text,
  source_entity_type text,

  cron_expression text,
  timezone text not null default 'Asia/Kolkata',

  webhook_endpoint_id uuid references public.webhook_endpoints(id) on delete set null,
  api_endpoint_id uuid references public.api_endpoints(id) on delete set null,

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

  unique (automation_id,trigger_code)
);

create index if not exists automation_triggers_v2_due_idx
  on public.automation_triggers_v2 (
    status,
    enabled,
    next_scheduled_at
  )
  where trigger_type = 'schedule'
    and status = 'active'
    and enabled = true;

-- ============================================================
-- 6. AUTOMATION NODES
-- ============================================================

create table if not exists public.automation_nodes_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_version_id uuid not null references public.automation_versions_v2(id) on delete cascade,

  node_key text not null,
  node_name text not null,

  node_type text not null
    check (
      node_type in (
        'start',
        'end',
        'condition',
        'switch',
        'loop',
        'wait',
        'delay',
        'approval',
        'database',
        'http_request',
        'webhook',
        'communication',
        'notification',
        'ai_agent',
        'ai_task',
        'workflow',
        'automation',
        'integration',
        'document',
        'report',
        'finance',
        'assignment',
        'site_visit',
        'booking',
        'code',
        'transform',
        'custom'
      )
    ),

  execution_order integer,
  position_x numeric(12,4),
  position_y numeric(12,4),

  timeout_seconds integer,
  retry_policy_id uuid references public.automation_retry_policies_v2(id) on delete set null,

  continue_on_error boolean not null default false,
  requires_approval boolean not null default false,

  configuration jsonb not null default '{}',
  input_mapping jsonb not null default '{}',
  output_mapping jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (automation_version_id,node_key)
);

-- ============================================================
-- 7. NODE CONNECTIONS
-- ============================================================

create table if not exists public.automation_node_connections_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_version_id uuid not null references public.automation_versions_v2(id) on delete cascade,

  source_node_id uuid not null references public.automation_nodes_v2(id) on delete cascade,
  target_node_id uuid not null references public.automation_nodes_v2(id) on delete cascade,

  source_port text default 'default',
  target_port text default 'default',

  connection_type text not null default 'success'
    check (
      connection_type in (
        'success',
        'failure',
        'true',
        'false',
        'case',
        'default',
        'loop',
        'approved',
        'rejected',
        'timeout',
        'custom'
      )
    ),

  condition_expression jsonb not null default '{}',
  priority integer not null default 100,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (
    automation_version_id,
    source_node_id,
    target_node_id,
    source_port,
    target_port,
    connection_type
  )
);

-- ============================================================
-- 8. AUTOMATION VARIABLES
-- ============================================================

create table if not exists public.automation_variables_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automation_definitions_v2(id) on delete cascade,

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
        'json',
        'uuid',
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

  unique (automation_id,variable_key)
);

-- ============================================================
-- 9. AUTOMATION EXECUTIONS
-- ============================================================

create table if not exists public.automation_executions_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automation_definitions_v2(id) on delete cascade,
  automation_version_id uuid not null references public.automation_versions_v2(id) on delete restrict,
  trigger_id uuid references public.automation_triggers_v2(id) on delete set null,

  execution_key text not null,
  parent_execution_id uuid references public.automation_executions_v2(id) on delete set null,

  execution_type text not null default 'event'
    check (
      execution_type in (
        'manual',
        'event',
        'webhook',
        'schedule',
        'api',
        'retry',
        'child',
        'test'
      )
    ),

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'running',
        'waiting',
        'waiting_approval',
        'completed',
        'partially_completed',
        'failed',
        'cancelled',
        'timed_out',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,

  input_data jsonb not null default '{}',
  output_data jsonb not null default '{}',
  execution_context jsonb not null default '{}',
  variables jsonb not null default '{}',

  current_node_id uuid references public.automation_nodes_v2(id) on delete set null,

  scheduled_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,

  timeout_at timestamptz,

  requested_by uuid references auth.users(id) on delete set null,

  idempotency_key text,
  correlation_id text,
  trace_id text,

  node_count integer not null default 0,
  completed_node_count integer not null default 0,
  failed_node_count integer not null default 0,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (execution_key)
);

create unique index if not exists automation_executions_v2_idempotency_idx
  on public.automation_executions_v2 (
    organization_id,
    automation_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists automation_executions_v2_queue_idx
  on public.automation_executions_v2 (
    status,
    scheduled_at,
    priority,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 10. NODE EXECUTIONS
-- ============================================================

create table if not exists public.automation_node_executions_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  execution_id uuid not null references public.automation_executions_v2(id) on delete cascade,
  node_id uuid not null references public.automation_nodes_v2(id) on delete restrict,

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
        'waiting_approval',
        'completed',
        'failed',
        'skipped',
        'cancelled',
        'timed_out'
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

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    execution_id,
    node_id,
    iteration_number,
    attempt_number
  )
);

create index if not exists automation_node_executions_v2_queue_idx
  on public.automation_node_executions_v2 (
    status,
    retry_at,
    created_at
  )
  where status in ('pending','queued','failed');

-- ============================================================
-- 11. WORKER QUEUE
-- ============================================================

create table if not exists public.automation_job_queue_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  execution_id uuid not null references public.automation_executions_v2(id) on delete cascade,
  node_execution_id uuid references public.automation_node_executions_v2(id) on delete cascade,

  job_type text not null
    check (
      job_type in (
        'start_execution',
        'execute_node',
        'resume_execution',
        'retry_node',
        'timeout_check',
        'schedule_trigger',
        'approval_timeout',
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

create index if not exists automation_job_queue_v2_worker_idx
  on public.automation_job_queue_v2 (
    status,
    available_at,
    priority,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 12. DELAYED JOBS AND WAIT STATES
-- ============================================================

create table if not exists public.automation_wait_states_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  execution_id uuid not null references public.automation_executions_v2(id) on delete cascade,
  node_execution_id uuid not null references public.automation_node_executions_v2(id) on delete cascade,

  wait_type text not null
    check (
      wait_type in (
        'duration',
        'until_time',
        'event',
        'webhook',
        'approval',
        'condition',
        'manual'
      )
    ),

  resume_at timestamptz,
  resume_event_pattern text,
  resume_token text,

  status text not null default 'waiting'
    check (
      status in (
        'waiting',
        'resumed',
        'expired',
        'cancelled'
      )
    ),

  timeout_at timestamptz,

  resume_payload jsonb not null default '{}',

  resumed_at timestamptz,
  resumed_by uuid references auth.users(id) on delete set null,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (resume_token)
);

create index if not exists automation_wait_states_v2_due_idx
  on public.automation_wait_states_v2 (
    status,
    resume_at,
    timeout_at
  )
  where status = 'waiting';

-- ============================================================
-- 13. APPROVAL REQUESTS
-- ============================================================

create table if not exists public.automation_approval_requests_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  execution_id uuid not null references public.automation_executions_v2(id) on delete cascade,
  node_execution_id uuid not null references public.automation_node_executions_v2(id) on delete cascade,

  approval_title text not null,
  approval_description text,

  approval_type text not null default 'single'
    check (
      approval_type in (
        'single',
        'any',
        'all',
        'majority',
        'sequential'
      )
    ),

  required_approvals integer not null default 1,

  approver_user_ids uuid[] not null default '{}',
  approver_role_ids uuid[] not null default '{}',
  approver_team_ids uuid[] not null default '{}',

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

  expires_at timestamptz,

  approved_count integer not null default 0,
  rejected_count integer not null default 0,

  completed_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.automation_approval_responses_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  approval_request_id uuid not null references public.automation_approval_requests_v2(id) on delete cascade,
  responder_user_id uuid not null references auth.users(id) on delete cascade,

  response text not null
    check (response in ('approved','rejected','abstained')),

  response_notes text,
  response_data jsonb not null default '{}',

  responded_at timestamptz not null default now(),

  unique (approval_request_id,responder_user_id)
);

-- ============================================================
-- 14. IDEMPOTENCY RECORDS
-- ============================================================

create table if not exists public.automation_idempotency_records_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automation_definitions_v2(id) on delete cascade,

  idempotency_key text not null,
  request_hash text,

  execution_id uuid references public.automation_executions_v2(id) on delete set null,

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

  unique (organization_id,automation_id,idempotency_key)
);

-- ============================================================
-- 15. DEAD LETTER QUEUE
-- ============================================================

create table if not exists public.automation_dead_letters_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  execution_id uuid references public.automation_executions_v2(id) on delete set null,
  node_execution_id uuid references public.automation_node_executions_v2(id) on delete set null,
  job_id uuid references public.automation_job_queue_v2(id) on delete set null,

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
-- 16. AUTOMATION EVENT OUTBOX
-- ============================================================

create table if not exists public.automation_engine_event_outbox_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  automation_id uuid references public.automation_definitions_v2(id) on delete set null,
  execution_id uuid references public.automation_executions_v2(id) on delete set null,
  node_execution_id uuid references public.automation_node_executions_v2(id) on delete set null,

  event_name text not null,

  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'workflow_engine',
        'notification_engine',
        'communication_engine',
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

create unique index if not exists automation_engine_event_outbox_v2_idem_idx
  on public.automation_engine_event_outbox_v2 (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

-- ============================================================
-- 17. LOGS
-- ============================================================

create table if not exists public.automation_engine_logs_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,

  automation_id uuid references public.automation_definitions_v2(id) on delete set null,
  execution_id uuid references public.automation_executions_v2(id) on delete set null,
  node_execution_id uuid references public.automation_node_executions_v2(id) on delete set null,

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

create index if not exists automation_engine_logs_v2_org_created_idx
  on public.automation_engine_logs_v2 (
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
    'automation_definitions_v2',
    'automation_retry_policies_v2',
    'automation_triggers_v2',
    'automation_nodes_v2',
    'automation_variables_v2',
    'automation_executions_v2',
    'automation_node_executions_v2',
    'automation_job_queue_v2',
    'automation_wait_states_v2',
    'automation_approval_requests_v2',
    'automation_idempotency_records_v2',
    'automation_dead_letters_v2',
    'automation_engine_event_outbox_v2'
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
-- 19. CREATE AUTOMATION
-- ============================================================

create or replace function public.create_automation_v2(
  requested_organization_id uuid,
  requested_automation_code text,
  requested_automation_name text,
  requested_category text default 'general',
  requested_description text default null,
  requested_execution_mode text default 'asynchronous',
  requested_configuration jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.automation_definitions_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  automation_record public.automation_definitions_v2;
  version_record public.automation_versions_v2;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'automation_engine.create'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.automation_definitions_v2 (
    organization_id,
    automation_code,
    automation_name,
    description,
    category,
    status,
    execution_mode,
    owner_user_id,
    configuration,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    requested_automation_code,
    requested_automation_name,
    requested_description,
    requested_category,
    'draft',
    requested_execution_mode,
    auth.uid(),
    coalesce(requested_configuration,'{}'::jsonb),
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  returning * into automation_record;

  insert into public.automation_versions_v2 (
    organization_id,
    automation_id,
    version_number,
    version_label,
    status,
    graph_definition,
    validation_status,
    is_current,
    change_summary,
    created_by
  )
  values (
    automation_record.organization_id,
    automation_record.id,
    1,
    'Initial version',
    'draft',
    '{}'::jsonb,
    'pending',
    true,
    'Initial version',
    auth.uid()
  )
  returning * into version_record;

  return automation_record;
end;
$$;

revoke all
on function public.create_automation_v2(
  uuid,text,text,text,text,text,jsonb,jsonb
)
from public;

grant execute
on function public.create_automation_v2(
  uuid,text,text,text,text,text,jsonb,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 20. CREATE AUTOMATION VERSION
-- ============================================================

create or replace function public.create_automation_version_v2(
  requested_automation_id uuid,
  requested_graph_definition jsonb default '{}'::jsonb,
  requested_input_schema jsonb default '{}'::jsonb,
  requested_output_schema jsonb default '{}'::jsonb,
  requested_change_summary text default null
)
returns public.automation_versions_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  automation_record public.automation_definitions_v2;
  next_version integer;
  version_record public.automation_versions_v2;
begin
  select *
  into automation_record
  from public.automation_definitions_v2
  where id = requested_automation_id
  for update;

  if not found then
    raise exception 'Automation not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      automation_record.organization_id,
      'automation_engine.update'
    ) then
    raise exception 'Permission denied';
  end if;

  select coalesce(max(version_number),0) + 1
  into next_version
  from public.automation_versions_v2
  where automation_id = requested_automation_id;

  update public.automation_versions_v2
  set is_current = false
  where automation_id = requested_automation_id
    and is_current = true;

  insert into public.automation_versions_v2 (
    organization_id,
    automation_id,
    version_number,
    version_label,
    status,
    graph_definition,
    input_schema,
    output_schema,
    validation_status,
    is_current,
    change_summary,
    created_by
  )
  values (
    automation_record.organization_id,
    automation_record.id,
    next_version,
    'Version ' || next_version::text,
    'draft',
    coalesce(requested_graph_definition,'{}'::jsonb),
    coalesce(requested_input_schema,'{}'::jsonb),
    coalesce(requested_output_schema,'{}'::jsonb),
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
on function public.create_automation_version_v2(
  uuid,jsonb,jsonb,jsonb,text
)
from public;

grant execute
on function public.create_automation_version_v2(
  uuid,jsonb,jsonb,jsonb,text
)
to authenticated,service_role;

-- ============================================================
-- 21. PUBLISH AUTOMATION VERSION
-- ============================================================

create or replace function public.publish_automation_version_v2(
  requested_version_id uuid
)
returns public.automation_versions_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  version_record public.automation_versions_v2;
  automation_record public.automation_definitions_v2;
  start_node_count integer;
  end_node_count integer;
begin
  select *
  into version_record
  from public.automation_versions_v2
  where id = requested_version_id
  for update;

  if not found then
    raise exception 'Automation version not found';
  end if;

  select *
  into automation_record
  from public.automation_definitions_v2
  where id = version_record.automation_id
  for update;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      automation_record.organization_id,
      'automation_engine.publish'
    ) then
    raise exception 'Permission denied';
  end if;

  select count(*)
  into start_node_count
  from public.automation_nodes_v2
  where automation_version_id = requested_version_id
    and node_type = 'start';

  select count(*)
  into end_node_count
  from public.automation_nodes_v2
  where automation_version_id = requested_version_id
    and node_type = 'end';

  if start_node_count <> 1 then
    raise exception 'Automation must contain exactly one start node';
  end if;

  if end_node_count < 1 then
    raise exception 'Automation must contain at least one end node';
  end if;

  update public.automation_versions_v2
  set
    status = 'deprecated',
    is_current = false
  where automation_id = version_record.automation_id
    and status = 'published'
    and id <> version_record.id;

  update public.automation_versions_v2
  set
    status = 'published',
    validation_status = 'valid',
    validation_errors = '[]'::jsonb,
    is_current = true,
    published_at = now(),
    published_by = auth.uid()
  where id = requested_version_id
  returning * into version_record;

  update public.automation_definitions_v2
  set
    status = 'active',
    updated_by = auth.uid(),
    updated_at = now()
  where id = version_record.automation_id;

  return version_record;
end;
$$;

revoke all
on function public.publish_automation_version_v2(uuid)
from public;

grant execute
on function public.publish_automation_version_v2(uuid)
to authenticated,service_role;

-- ============================================================
-- 22. START AUTOMATION EXECUTION
-- ============================================================

create or replace function public.start_automation_execution_v2(
  requested_automation_id uuid,
  requested_input_data jsonb default '{}'::jsonb,
  requested_execution_type text default 'manual',
  requested_trigger_id uuid default null,
  requested_priority integer default 100,
  requested_scheduled_at timestamptz default now(),
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.automation_executions_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  automation_record public.automation_definitions_v2;
  version_record public.automation_versions_v2;
  existing_execution public.automation_executions_v2;
  execution_record public.automation_executions_v2;
  node_total integer;
begin
  select *
  into automation_record
  from public.automation_definitions_v2
  where id = requested_automation_id
    and status = 'active';

  if not found then
    raise exception 'Active automation not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      automation_record.organization_id,
      'automation_engine.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_execution
    from public.automation_executions_v2
    where organization_id = automation_record.organization_id
      and automation_id = automation_record.id
      and idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_execution;
    end if;
  end if;

  select *
  into version_record
  from public.automation_versions_v2
  where automation_id = automation_record.id
    and status = 'published'
    and is_current = true
  order by version_number desc
  limit 1;

  if not found then
    raise exception 'Published automation version not found';
  end if;

  select count(*)
  into node_total
  from public.automation_nodes_v2
  where automation_version_id = version_record.id;

  insert into public.automation_executions_v2 (
    organization_id,
    automation_id,
    automation_version_id,
    trigger_id,
    execution_key,
    execution_type,
    status,
    priority,
    input_data,
    execution_context,
    scheduled_at,
    timeout_at,
    requested_by,
    idempotency_key,
    correlation_id,
    trace_id,
    node_count,
    metadata
  )
  values (
    automation_record.organization_id,
    automation_record.id,
    version_record.id,
    requested_trigger_id,
    'AEX-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,20)),
    requested_execution_type,
    'queued',
    requested_priority,
    coalesce(requested_input_data,'{}'::jsonb),
    jsonb_build_object(
      'automation_code',automation_record.automation_code,
      'version_number',version_record.version_number
    ),
    coalesce(requested_scheduled_at,now()),
    coalesce(requested_scheduled_at,now())
      + make_interval(secs => automation_record.default_timeout_seconds),
    auth.uid(),
    requested_idempotency_key,
    requested_correlation_id,
    requested_trace_id,
    node_total,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into execution_record;

  insert into public.automation_job_queue_v2 (
    organization_id,
    execution_id,
    job_type,
    status,
    priority,
    available_at,
    payload,
    correlation_id,
    trace_id
  )
  values (
    execution_record.organization_id,
    execution_record.id,
    'start_execution',
    'queued',
    requested_priority,
    coalesce(requested_scheduled_at,now()),
    jsonb_build_object(
      'execution_id',execution_record.id
    ),
    execution_record.correlation_id,
    execution_record.trace_id
  );

  return execution_record;
end;
$$;

revoke all
on function public.start_automation_execution_v2(
  uuid,jsonb,text,uuid,integer,timestamptz,text,text,text,jsonb
)
from public;

grant execute
on function public.start_automation_execution_v2(
  uuid,jsonb,text,uuid,integer,timestamptz,text,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 23. CLAIM AUTOMATION JOB
-- ============================================================

create or replace function public.claim_automation_job_v2(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.automation_job_queue_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.automation_job_queue_v2;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim automation jobs';
  end if;

  select *
  into job_record
  from public.automation_job_queue_v2 j
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

  update public.automation_job_queue_v2
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

  return job_record;
end;
$$;

revoke all
on function public.claim_automation_job_v2(text,uuid,integer)
from public;

grant execute
on function public.claim_automation_job_v2(text,uuid,integer)
to service_role;

-- ============================================================
-- 24. COMPLETE AUTOMATION JOB
-- ============================================================

create or replace function public.complete_automation_job_v2(
  requested_job_id uuid,
  requested_lock_token text,
  requested_result_data jsonb default '{}'::jsonb
)
returns public.automation_job_queue_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.automation_job_queue_v2;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete automation jobs';
  end if;

  select *
  into job_record
  from public.automation_job_queue_v2
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Automation job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid automation job lock token';
  end if;

  update public.automation_job_queue_v2
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
on function public.complete_automation_job_v2(uuid,text,jsonb)
from public;

grant execute
on function public.complete_automation_job_v2(uuid,text,jsonb)
to service_role;

-- ============================================================
-- 25. FAIL AUTOMATION JOB
-- ============================================================

create or replace function public.fail_automation_job_v2(
  requested_job_id uuid,
  requested_lock_token text,
  requested_error_code text,
  requested_error_message text,
  requested_error_data jsonb default '{}'::jsonb
)
returns public.automation_job_queue_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.automation_job_queue_v2;
  next_status text;
  retry_delay integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may fail automation jobs';
  end if;

  select *
  into job_record
  from public.automation_job_queue_v2
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Automation job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid automation job lock token';
  end if;

  next_status := case
    when job_record.attempts >= job_record.maximum_attempts
      then 'dead_lettered'
    else 'failed'
  end;

  retry_delay := least(
    3600,
    greatest(
      30,
      power(2,greatest(job_record.attempts,1))::integer * 30
    )
  );

  update public.automation_job_queue_v2
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
    insert into public.automation_dead_letters_v2 (
      organization_id,
      execution_id,
      node_execution_id,
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
      job_record.execution_id,
      job_record.node_execution_id,
      job_record.id,
      'maximum_attempts_exceeded',
      'automation_job_queue',
      job_record.payload,
      requested_error_code,
      requested_error_message,
      coalesce(requested_error_data,'{}'::jsonb)
    );
  end if;

  return job_record;
end;
$$;

revoke all
on function public.fail_automation_job_v2(
  uuid,text,text,text,jsonb
)
from public;

grant execute
on function public.fail_automation_job_v2(
  uuid,text,text,text,jsonb
)
to service_role;

-- ============================================================
-- 26. CREATE APPROVAL REQUEST
-- ============================================================

create or replace function public.create_automation_approval_v2(
  requested_execution_id uuid,
  requested_node_execution_id uuid,
  requested_approval_title text,
  requested_approval_description text default null,
  requested_approval_type text default 'single',
  requested_required_approvals integer default 1,
  requested_approver_user_ids uuid[] default '{}',
  requested_approver_role_ids uuid[] default '{}',
  requested_approver_team_ids uuid[] default '{}',
  requested_approval_payload jsonb default '{}'::jsonb,
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.automation_approval_requests_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  execution_record public.automation_executions_v2;
  approval_record public.automation_approval_requests_v2;
begin
  select *
  into execution_record
  from public.automation_executions_v2
  where id = requested_execution_id;

  if not found then
    raise exception 'Automation execution not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      execution_record.organization_id,
      'automation_engine.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.automation_approval_requests_v2 (
    organization_id,
    execution_id,
    node_execution_id,
    approval_title,
    approval_description,
    approval_type,
    required_approvals,
    approver_user_ids,
    approver_role_ids,
    approver_team_ids,
    status,
    approval_payload,
    expires_at,
    metadata
  )
  values (
    execution_record.organization_id,
    execution_record.id,
    requested_node_execution_id,
    requested_approval_title,
    requested_approval_description,
    requested_approval_type,
    greatest(requested_required_approvals,1),
    coalesce(requested_approver_user_ids,'{}'::uuid[]),
    coalesce(requested_approver_role_ids,'{}'::uuid[]),
    coalesce(requested_approver_team_ids,'{}'::uuid[]),
    'pending',
    coalesce(requested_approval_payload,'{}'::jsonb),
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into approval_record;

  update public.automation_executions_v2
  set
    status = 'waiting_approval',
    updated_at = now()
  where id = requested_execution_id;

  update public.automation_node_executions_v2
  set
    status = 'waiting_approval',
    updated_at = now()
  where id = requested_node_execution_id;

  return approval_record;
end;
$$;

revoke all
on function public.create_automation_approval_v2(
  uuid,uuid,text,text,text,integer,uuid[],uuid[],uuid[],jsonb,timestamptz,jsonb
)
from public;

grant execute
on function public.create_automation_approval_v2(
  uuid,uuid,text,text,text,integer,uuid[],uuid[],uuid[],jsonb,timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 27. RESPOND TO APPROVAL
-- ============================================================

create or replace function public.respond_automation_approval_v2(
  requested_approval_request_id uuid,
  requested_response text,
  requested_response_notes text default null,
  requested_response_data jsonb default '{}'::jsonb
)
returns public.automation_approval_requests_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  approval_record public.automation_approval_requests_v2;
  approval_total integer;
  rejection_total integer;
  final_status text;
begin
  select *
  into approval_record
  from public.automation_approval_requests_v2
  where id = requested_approval_request_id
  for update;

  if not found then
    raise exception 'Approval request not found';
  end if;

  if approval_record.status <> 'pending' then
    raise exception 'Approval request is no longer pending';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() <> all(approval_record.approver_user_ids)
    and not public.has_organization_permission(
      approval_record.organization_id,
      'automation_engine.approve'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.automation_approval_responses_v2 (
    organization_id,
    approval_request_id,
    responder_user_id,
    response,
    response_notes,
    response_data
  )
  values (
    approval_record.organization_id,
    approval_record.id,
    auth.uid(),
    requested_response,
    requested_response_notes,
    coalesce(requested_response_data,'{}'::jsonb)
  )
  on conflict (approval_request_id,responder_user_id)
  do update set
    response = excluded.response,
    response_notes = excluded.response_notes,
    response_data = excluded.response_data,
    responded_at = now();

  select
    count(*) filter (where response = 'approved'),
    count(*) filter (where response = 'rejected')
  into
    approval_total,
    rejection_total
  from public.automation_approval_responses_v2
  where approval_request_id = approval_record.id;

  final_status := 'pending';

  if approval_record.approval_type in ('single','any')
    and approval_total >= 1 then
    final_status := 'approved';
  elsif approval_record.approval_type = 'all'
    and rejection_total > 0 then
    final_status := 'rejected';
  elsif approval_record.approval_type = 'all'
    and approval_total >= greatest(
      cardinality(approval_record.approver_user_ids),
      approval_record.required_approvals
    ) then
    final_status := 'approved';
  elsif approval_record.approval_type in ('majority','sequential')
    and approval_total >= approval_record.required_approvals then
    final_status := 'approved';
  elsif rejection_total >= approval_record.required_approvals then
    final_status := 'rejected';
  end if;

  update public.automation_approval_requests_v2
  set
    approved_count = approval_total,
    rejected_count = rejection_total,
    status = final_status,
    completed_at = case
      when final_status in ('approved','rejected') then now()
      else completed_at
    end,
    updated_at = now()
  where id = approval_record.id
  returning * into approval_record;

  if final_status in ('approved','rejected') then
    update public.automation_node_executions_v2
    set
      status = case
        when final_status = 'approved' then 'completed'
        else 'failed'
      end,
      completed_at = now(),
      output_data = output_data || jsonb_build_object(
        'approval_status',final_status
      ),
      updated_at = now()
    where id = approval_record.node_execution_id;

    update public.automation_executions_v2
    set
      status = case
        when final_status = 'approved' then 'running'
        else 'failed'
      end,
      updated_at = now()
    where id = approval_record.execution_id;
  end if;

  return approval_record;
end;
$$;

revoke all
on function public.respond_automation_approval_v2(
  uuid,text,text,jsonb
)
from public;

grant execute
on function public.respond_automation_approval_v2(
  uuid,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 28. CANCEL EXECUTION
-- ============================================================

create or replace function public.cancel_automation_execution_v2(
  requested_execution_id uuid,
  requested_reason text default null
)
returns public.automation_executions_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  execution_record public.automation_executions_v2;
begin
  select *
  into execution_record
  from public.automation_executions_v2
  where id = requested_execution_id
  for update;

  if not found then
    raise exception 'Automation execution not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      execution_record.organization_id,
      'automation_engine.cancel'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.automation_executions_v2
  set
    status = 'cancelled',
    completed_at = now(),
    error_message = requested_reason,
    updated_at = now()
  where id = requested_execution_id
  returning * into execution_record;

  update public.automation_job_queue_v2
  set
    status = 'cancelled',
    updated_at = now()
  where execution_id = requested_execution_id
    and status in ('queued','claimed','processing','failed');

  update public.automation_node_executions_v2
  set
    status = 'cancelled',
    completed_at = now(),
    updated_at = now()
  where execution_id = requested_execution_id
    and status not in ('completed','failed','skipped','cancelled');

  update public.automation_wait_states_v2
  set
    status = 'cancelled',
    updated_at = now()
  where execution_id = requested_execution_id
    and status = 'waiting';

  return execution_record;
end;
$$;

revoke all
on function public.cancel_automation_execution_v2(uuid,text)
from public;

grant execute
on function public.cancel_automation_execution_v2(uuid,text)
to authenticated,service_role;

-- ============================================================
-- 29. PUBLISH AUTOMATION EVENT
-- ============================================================

create or replace function public.publish_automation_engine_event_v2(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_automation_id uuid default null,
  requested_execution_id uuid default null,
  requested_node_execution_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.automation_engine_event_outbox_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.automation_engine_event_outbox_v2;
  created_event public.automation_engine_event_outbox_v2;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.automation_engine_event_outbox_v2
    where organization_id is not distinct from requested_organization_id
      and idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.automation_engine_event_outbox_v2 (
    organization_id,
    automation_id,
    execution_id,
    node_execution_id,
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
    requested_automation_id,
    requested_execution_id,
    requested_node_execution_id,
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
on function public.publish_automation_engine_event_v2(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_automation_engine_event_v2(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 30. EXECUTION EVENT TRIGGER
-- ============================================================

create or replace function public.emit_automation_execution_events_v2()
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

  perform public.publish_automation_engine_event_v2(
    new.organization_id,
    'automation.execution.' || new.status,
    jsonb_build_object(
      'execution_id',new.id,
      'automation_id',new.automation_id,
      'automation_version_id',new.automation_version_id,
      'status',new.status,
      'execution_type',new.execution_type,
      'completed_node_count',new.completed_node_count,
      'failed_node_count',new.failed_node_count,
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
    new.automation_id,
    new.id,
    null,
    case
      when new.status in ('failed','timed_out','dead_lettered') then 10
      else 50
    end,
    'automation-execution:' || new.id::text || ':' || new.status,
    coalesce(new.correlation_id,new.id::text),
    new.trace_id,
    now()
  );

  return new;
end;
$$;

drop trigger if exists automation_executions_v2_emit_events
on public.automation_executions_v2;

create trigger automation_executions_v2_emit_events
after insert or update
on public.automation_executions_v2
for each row
execute function public.emit_automation_execution_events_v2();

-- ============================================================
-- 31. ANALYTICS VIEWS
-- ============================================================

create or replace view public.automation_engine_execution_dashboard_v2
with (security_invoker = true)
as
select
  e.organization_id,
  e.automation_id,
  a.automation_code,
  a.automation_name,
  e.status,

  count(*) as execution_count,

  count(*) filter (
    where e.status = 'completed'
  ) as completed_count,

  count(*) filter (
    where e.status in ('failed','timed_out','dead_lettered')
  ) as failed_count,

  round(
    count(*) filter (
      where e.status = 'completed'
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as success_rate,

  round(
    avg(
      extract(
        epoch from (
          coalesce(e.completed_at,now())
          - coalesce(e.started_at,e.created_at)
        )
      ) * 1000
    ),
    2
  ) as average_duration_ms,

  max(e.completed_at) as latest_completion_at,
  max(e.created_at) as latest_execution_at

from public.automation_executions_v2 e
join public.automation_definitions_v2 a
  on a.id = e.automation_id
group by
  e.organization_id,
  e.automation_id,
  a.automation_code,
  a.automation_name,
  e.status;

create or replace view public.automation_engine_node_dashboard_v2
with (security_invoker = true)
as
select
  n.organization_id,
  n.node_id,
  d.node_key,
  d.node_name,
  d.node_type,
  n.status,

  count(*) as execution_count,

  round(avg(n.duration_ms),2) as average_duration_ms,

  count(*) filter (
    where n.status = 'completed'
  ) as completed_count,

  count(*) filter (
    where n.status in ('failed','timed_out')
  ) as failed_count,

  max(n.completed_at) as latest_completion_at

from public.automation_node_executions_v2 n
join public.automation_nodes_v2 d
  on d.id = n.node_id
group by
  n.organization_id,
  n.node_id,
  d.node_key,
  d.node_name,
  d.node_type,
  n.status;

create or replace view public.automation_engine_queue_dashboard_v2
with (security_invoker = true)
as
select
  organization_id,
  job_type,
  status,

  count(*) as job_count,
  coalesce(sum(attempts),0) as total_attempts,

  count(*) filter (
    where available_at <= now()
      and status in ('queued','failed')
  ) as due_jobs,

  min(available_at) filter (
    where status in ('queued','failed')
  ) as next_available_at,

  max(completed_at) as latest_completion_at

from public.automation_job_queue_v2
group by
  organization_id,
  job_type,
  status;

create or replace view public.automation_engine_approval_dashboard_v2
with (security_invoker = true)
as
select
  organization_id,
  approval_type,
  status,

  count(*) as approval_count,
  coalesce(sum(approved_count),0) as approved_responses,
  coalesce(sum(rejected_count),0) as rejected_responses,

  count(*) filter (
    where status = 'pending'
      and expires_at is not null
      and expires_at <= now()
  ) as expired_pending_count,

  max(completed_at) as latest_completion_at

from public.automation_approval_requests_v2
group by
  organization_id,
  approval_type,
  status;

grant select
on
  public.automation_engine_execution_dashboard_v2,
  public.automation_engine_node_dashboard_v2,
  public.automation_engine_queue_dashboard_v2,
  public.automation_engine_approval_dashboard_v2
to authenticated,service_role;

-- ============================================================
-- 32. HEALTH CHECK
-- ============================================================

create or replace function public.get_automation_engine_health_v2(
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
        'automation_engine.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'active_automations',(
      select count(*)
      from public.automation_definitions_v2 a
      where a.status = 'active'
        and (
          requested_organization_id is null
          or a.organization_id = requested_organization_id
        )
    ),

    'active_triggers',(
      select count(*)
      from public.automation_triggers_v2 t
      where t.status = 'active'
        and t.enabled = true
        and (
          requested_organization_id is null
          or t.organization_id = requested_organization_id
        )
    ),

    'queued_executions',(
      select count(*)
      from public.automation_executions_v2 e
      where e.status in ('queued','claimed','running','waiting','waiting_approval')
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    ),

    'queued_jobs',(
      select count(*)
      from public.automation_job_queue_v2 j
      where j.status in ('queued','claimed','processing','failed')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'expired_worker_locks',(
      select count(*)
      from public.automation_job_queue_v2 j
      where j.status = 'claimed'
        and j.lock_expires_at <= now()
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'waiting_approvals',(
      select count(*)
      from public.automation_approval_requests_v2 a
      where a.status = 'pending'
        and (
          requested_organization_id is null
          or a.organization_id = requested_organization_id
        )
    ),

    'dead_letters',(
      select count(*)
      from public.automation_dead_letters_v2 d
      where d.status = 'open'
        and (
          requested_organization_id is null
          or d.organization_id = requested_organization_id
        )
    ),

    'failed_executions_24h',(
      select count(*)
      from public.automation_executions_v2 e
      where e.status in ('failed','timed_out','dead_lettered')
        and e.updated_at >= now() - interval '24 hours'
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.automation_engine_event_outbox_v2 e
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
on function public.get_automation_engine_health_v2(uuid)
from public;

grant execute
on function public.get_automation_engine_health_v2(uuid)
to authenticated,service_role;

-- ============================================================
-- 33. ROW LEVEL SECURITY
-- ============================================================

alter table public.automation_definitions_v2 enable row level security;
alter table public.automation_retry_policies_v2 enable row level security;
alter table public.automation_versions_v2 enable row level security;
alter table public.automation_triggers_v2 enable row level security;
alter table public.automation_nodes_v2 enable row level security;
alter table public.automation_node_connections_v2 enable row level security;
alter table public.automation_variables_v2 enable row level security;
alter table public.automation_executions_v2 enable row level security;
alter table public.automation_node_executions_v2 enable row level security;
alter table public.automation_job_queue_v2 enable row level security;
alter table public.automation_wait_states_v2 enable row level security;
alter table public.automation_approval_requests_v2 enable row level security;
alter table public.automation_approval_responses_v2 enable row level security;
alter table public.automation_idempotency_records_v2 enable row level security;
alter table public.automation_dead_letters_v2 enable row level security;
alter table public.automation_engine_event_outbox_v2 enable row level security;
alter table public.automation_engine_logs_v2 enable row level security;

drop policy if exists automation_retry_policies_v2_select_policy
on public.automation_retry_policies_v2;

create policy automation_retry_policies_v2_select_policy
on public.automation_retry_policies_v2
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'automation_engine.view'
  )
  or public.has_organization_permission(
    organization_id,
    'automation_engine.view_all'
  )
);

drop policy if exists automation_retry_policies_v2_service_policy
on public.automation_retry_policies_v2;

create policy automation_retry_policies_v2_service_policy
on public.automation_retry_policies_v2
for all
to service_role
using (true)
with check (true);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'automation_definitions_v2',
    'automation_versions_v2',
    'automation_triggers_v2',
    'automation_nodes_v2',
    'automation_node_connections_v2',
    'automation_variables_v2',
    'automation_executions_v2',
    'automation_node_executions_v2',
    'automation_job_queue_v2',
    'automation_wait_states_v2',
    'automation_approval_requests_v2',
    'automation_approval_responses_v2',
    'automation_idempotency_records_v2',
    'automation_dead_letters_v2',
    'automation_engine_event_outbox_v2',
    'automation_engine_logs_v2'
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
           ''automation_engine.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''automation_engine.view_all''
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

drop policy if exists automation_definitions_v2_write_policy
on public.automation_definitions_v2;

create policy automation_definitions_v2_write_policy
on public.automation_definitions_v2
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'automation_engine.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'automation_engine.create'
  )
  or public.has_organization_permission(
    organization_id,
    'automation_engine.update'
  )
);

drop policy if exists automation_approval_requests_v2_response_policy
on public.automation_approval_requests_v2;

create policy automation_approval_requests_v2_response_policy
on public.automation_approval_requests_v2
for update
to authenticated
using (
  auth.uid() = any(approver_user_ids)
  or public.has_organization_permission(
    organization_id,
    'automation_engine.approve'
  )
)
with check (
  auth.uid() = any(approver_user_ids)
  or public.has_organization_permission(
    organization_id,
    'automation_engine.approve'
  )
);

-- ============================================================
-- 34. GRANTS
-- ============================================================

grant select
on
  public.automation_definitions_v2,
  public.automation_retry_policies_v2,
  public.automation_versions_v2,
  public.automation_triggers_v2,
  public.automation_nodes_v2,
  public.automation_node_connections_v2,
  public.automation_variables_v2,
  public.automation_executions_v2,
  public.automation_node_executions_v2,
  public.automation_job_queue_v2,
  public.automation_wait_states_v2,
  public.automation_approval_requests_v2,
  public.automation_approval_responses_v2,
  public.automation_idempotency_records_v2,
  public.automation_dead_letters_v2,
  public.automation_engine_event_outbox_v2,
  public.automation_engine_logs_v2
to authenticated;

grant insert,update,delete
on
  public.automation_definitions_v2,
  public.automation_versions_v2,
  public.automation_triggers_v2,
  public.automation_nodes_v2,
  public.automation_node_connections_v2,
  public.automation_variables_v2
to authenticated;

grant insert,update
on
  public.automation_approval_requests_v2,
  public.automation_approval_responses_v2
to authenticated;

grant all
on
  public.automation_definitions_v2,
  public.automation_retry_policies_v2,
  public.automation_versions_v2,
  public.automation_triggers_v2,
  public.automation_nodes_v2,
  public.automation_node_connections_v2,
  public.automation_variables_v2,
  public.automation_executions_v2,
  public.automation_node_executions_v2,
  public.automation_job_queue_v2,
  public.automation_wait_states_v2,
  public.automation_approval_requests_v2,
  public.automation_approval_responses_v2,
  public.automation_idempotency_records_v2,
  public.automation_dead_letters_v2,
  public.automation_engine_event_outbox_v2,
  public.automation_engine_logs_v2
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
    'automation_definitions_v2',
    'automation_retry_policies_v2',
    'automation_versions_v2',
    'automation_triggers_v2',
    'automation_nodes_v2',
    'automation_node_connections_v2',
    'automation_variables_v2',
    'automation_executions_v2',
    'automation_node_executions_v2',
    'automation_job_queue_v2',
    'automation_wait_states_v2',
    'automation_approval_requests_v2',
    'automation_approval_responses_v2',
    'automation_idempotency_records_v2',
    'automation_dead_letters_v2',
    'automation_engine_event_outbox_v2',
    'automation_engine_logs_v2'
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
    'create_automation_v2',
    'create_automation_version_v2',
    'publish_automation_version_v2',
    'start_automation_execution_v2',
    'claim_automation_job_v2',
    'complete_automation_job_v2',
    'fail_automation_job_v2',
    'create_automation_approval_v2',
    'respond_automation_approval_v2',
    'cancel_automation_execution_v2',
    'publish_automation_engine_event_v2',
    'get_automation_engine_health_v2'
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
      '026 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 36. MIGRATION AUDIT
-- ============================================================

insert into public.automation_engine_logs_v2 (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.026.completed',
  'Automation Engine migration 026 completed',
  jsonb_build_object(
    'migration',
    '026_automation_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'definitions',
      'versions',
      'triggers',
      'nodes',
      'connections',
      'variables',
      'executions',
      'node_executions',
      'worker_queue',
      'wait_states',
      'approvals',
      'idempotency',
      'retry_policies',
      'dead_letters',
      'analytics',
      'event_outbox'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.automation_engine_logs_v2 l
  where l.organization_id = o.id
    and l.event_name = 'migration.026.completed'
);

commit;