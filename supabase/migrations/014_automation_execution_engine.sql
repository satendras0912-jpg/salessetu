-- ============================================================
-- SalesSetu Enterprise
-- Migration 014: Automation Execution Engine
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
--
-- Purpose:
--   Database-level orchestration runtime for event-driven,
--   scheduled and delayed automation across SalesSetu.
--
-- Scope:
--   • Automation definitions and versions
--   • Triggers, nodes, edges and variables
--   • Execution runs and node-level execution history
--   • Event bus, schedules, delay queue and task queue
--   • Retry, dead-letter and distributed locking
--   • Webhook endpoints and webhook inbox
--   • Cross-engine actions for validation, assignment,
--     AI calling, communication, site visits and bookings
--   • n8n handoff and event outbox
--   • Idempotency, audit, analytics, RLS and health checks
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
    ('automation','view','automation.view','View automation definitions and executions'),
    ('automation','view_all','automation.view_all','View all organization automation records'),
    ('automation','create','automation.create','Create automation definitions'),
    ('automation','update','automation.update','Update automation definitions'),
    ('automation','delete','automation.delete','Archive or delete automations'),
    ('automation','publish','automation.publish','Publish automation versions'),
    ('automation','execute','automation.execute','Execute automations'),
    ('automation','cancel','automation.cancel','Cancel automation executions'),
    ('automation','retry','automation.retry','Retry failed automation executions'),
    ('automation','manage_triggers','automation.manage_triggers','Manage automation triggers'),
    ('automation','manage_schedules','automation.manage_schedules','Manage automation schedules'),
    ('automation','manage_webhooks','automation.manage_webhooks','Manage automation webhooks'),
    ('automation','manage_workers','automation.manage_workers','Manage worker queues and locks'),
    ('automation','manage_secrets','automation.manage_secrets','Manage automation secrets'),
    ('automation','view_logs','automation.view_logs','View automation logs'),
    ('automation','view_analytics','automation.view_analytics','View automation analytics'),
    ('automation','override','automation.override','Override automation runtime restrictions')
) as permission_data(module,action,code,description)
where not exists (
  select 1
  from public.permissions p
  where p.code = permission_data.code
);

-- ============================================================
-- 2. AUTOMATION DEFINITIONS
-- ============================================================

create table if not exists public.automation_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_code text not null,
  automation_name text not null,
  description text,

  automation_type text not null default 'event_driven'
    check (
      automation_type in (
        'event_driven',
        'scheduled',
        'webhook',
        'manual',
        'system',
        'hybrid'
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

  current_version integer not null default 1,
  published_version integer,

  concurrency_policy text not null default 'parallel'
    check (
      concurrency_policy in (
        'parallel',
        'single',
        'replace',
        'queue',
        'skip_if_running'
      )
    ),

  maximum_concurrent_runs integer,
  execution_timeout_seconds integer not null default 3600,
  default_retry_policy jsonb not null default '{}',
  input_schema jsonb not null default '{}',
  output_schema jsonb not null default '{}',

  tags text[] not null default '{}',
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,automation_code)
);

create index if not exists automation_definitions_org_status_idx
  on public.automation_definitions (
    organization_id,
    status,
    automation_type
  );

-- ============================================================
-- 3. AUTOMATION VERSIONS
-- ============================================================

create table if not exists public.automation_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automation_definitions(id) on delete cascade,

  version_number integer not null,
  status text not null default 'draft'
    check (
      status in (
        'draft',
        'published',
        'deprecated',
        'archived'
      )
    ),

  definition_json jsonb not null default '{}',
  checksum text,

  change_summary text,
  published_at timestamptz,
  published_by uuid references auth.users(id) on delete set null,

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  unique (automation_id,version_number)
);

create index if not exists automation_versions_lookup_idx
  on public.automation_versions (
    automation_id,
    status,
    version_number desc
  );

-- ============================================================
-- 4. AUTOMATION TRIGGERS
-- ============================================================

create table if not exists public.automation_triggers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automation_definitions(id) on delete cascade,
  automation_version_id uuid references public.automation_versions(id) on delete cascade,

  trigger_code text not null,
  trigger_name text not null,

  trigger_type text not null
    check (
      trigger_type in (
        'event',
        'schedule',
        'webhook',
        'manual',
        'database',
        'polling',
        'system'
      )
    ),

  event_name text,
  schedule_expression text,
  webhook_path text,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  filter_expression jsonb not null default '{}',
  deduplication_window_seconds integer not null default 0,
  idempotency_expression text,

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (automation_id,trigger_code)
);

create index if not exists automation_triggers_event_idx
  on public.automation_triggers (
    organization_id,
    trigger_type,
    event_name,
    status
  );

-- ============================================================
-- 5. AUTOMATION NODES
-- ============================================================

create table if not exists public.automation_nodes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_version_id uuid not null references public.automation_versions(id) on delete cascade,

  node_key text not null,
  node_name text not null,

  node_type text not null
    check (
      node_type in (
        'start',
        'end',
        'condition',
        'switch',
        'wait',
        'delay',
        'transform',
        'database',
        'http',
        'webhook',
        'n8n',
        'lead_validation',
        'assignment',
        'ai_call',
        'communication',
        'site_visit',
        'booking',
        'customer_success',
        'inventory',
        'workflow',
        'sub_automation',
        'manual_approval',
        'custom'
      )
    ),

  execution_order integer not null default 100,

  timeout_seconds integer,
  retry_policy jsonb not null default '{}',
  input_mapping jsonb not null default '{}',
  output_mapping jsonb not null default '{}',
  configuration jsonb not null default '{}',

  continue_on_error boolean not null default false,
  is_terminal boolean not null default false,
  is_enabled boolean not null default true,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (automation_version_id,node_key)
);

create index if not exists automation_nodes_version_order_idx
  on public.automation_nodes (
    automation_version_id,
    execution_order,
    node_key
  );

-- ============================================================
-- 6. AUTOMATION EDGES
-- ============================================================

create table if not exists public.automation_edges (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_version_id uuid not null references public.automation_versions(id) on delete cascade,

  source_node_id uuid not null references public.automation_nodes(id) on delete cascade,
  target_node_id uuid not null references public.automation_nodes(id) on delete cascade,

  edge_type text not null default 'success'
    check (
      edge_type in (
        'success',
        'failure',
        'condition_true',
        'condition_false',
        'default',
        'timeout',
        'cancelled',
        'custom'
      )
    ),

  condition_expression jsonb not null default '{}',
  priority integer not null default 100,
  label text,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),

  unique (
    automation_version_id,
    source_node_id,
    target_node_id,
    edge_type
  ),

  check (source_node_id <> target_node_id)
);

create index if not exists automation_edges_source_idx
  on public.automation_edges (
    automation_version_id,
    source_node_id,
    priority
  );

-- ============================================================
-- 7. AUTOMATION VARIABLES
-- ============================================================

create table if not exists public.automation_variables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_version_id uuid not null references public.automation_versions(id) on delete cascade,

  variable_key text not null,
  display_name text,

  data_type text not null default 'text'
    check (
      data_type in (
        'text',
        'number',
        'boolean',
        'date',
        'datetime',
        'uuid',
        'json',
        'array',
        'secret'
      )
    ),

  scope text not null default 'execution'
    check (
      scope in (
        'automation',
        'execution',
        'node',
        'organization',
        'system'
      )
    ),

  default_value jsonb,
  is_required boolean not null default false,
  is_secret boolean not null default false,

  validation_schema jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (automation_version_id,variable_key)
);

-- ============================================================
-- 8. AUTOMATION SECRETS
-- ============================================================

create table if not exists public.automation_secrets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  secret_key text not null,
  secret_name text not null,
  secret_type text not null default 'generic'
    check (
      secret_type in (
        'generic',
        'api_key',
        'oauth',
        'basic_auth',
        'bearer_token',
        'webhook_secret',
        'database',
        'custom'
      )
    ),

  encrypted_value jsonb not null default '{}',
  status text not null default 'active'
    check (status in ('active','inactive','revoked','expired')),

  expires_at timestamptz,
  last_rotated_at timestamptz,
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,secret_key)
);

-- ============================================================
-- 9. AUTOMATION RUNS
-- ============================================================

create table if not exists public.automation_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_id uuid not null references public.automation_definitions(id) on delete cascade,
  automation_version_id uuid not null references public.automation_versions(id) on delete restrict,
  trigger_id uuid references public.automation_triggers(id) on delete set null,

  parent_run_id uuid references public.automation_runs(id) on delete set null,
  root_run_id uuid references public.automation_runs(id) on delete set null,

  correlation_id text,
  trace_id text,
  idempotency_key text,

  trigger_type text,
  trigger_reference text,

  status text not null default 'queued'
    check (
      status in (
        'pending',
        'queued',
        'running',
        'waiting',
        'paused',
        'completed',
        'failed',
        'cancelled',
        'timed_out',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,

  input_data jsonb not null default '{}',
  context_data jsonb not null default '{}',
  output_data jsonb not null default '{}',
  error_data jsonb not null default '{}',

  current_node_id uuid references public.automation_nodes(id) on delete set null,
  current_node_key text,

  attempts integer not null default 0,
  maximum_attempts integer not null default 3,
  next_retry_at timestamptz,

  queued_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  timeout_at timestamptz,

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists automation_runs_idempotency_idx
  on public.automation_runs (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists automation_runs_queue_idx
  on public.automation_runs (
    status,
    priority,
    queued_at,
    created_at
  )
  where status in ('pending','queued','waiting');

create index if not exists automation_runs_automation_idx
  on public.automation_runs (
    organization_id,
    automation_id,
    created_at desc
  );

-- ============================================================
-- 10. NODE EXECUTIONS
-- ============================================================

create table if not exists public.automation_node_executions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_run_id uuid not null references public.automation_runs(id) on delete cascade,
  automation_node_id uuid not null references public.automation_nodes(id) on delete restrict,

  node_key text not null,
  node_type text not null,

  execution_number integer not null default 1,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'queued',
        'running',
        'waiting',
        'completed',
        'failed',
        'skipped',
        'cancelled',
        'timed_out'
      )
    ),

  input_data jsonb not null default '{}',
  output_data jsonb not null default '{}',
  error_data jsonb not null default '{}',

  attempts integer not null default 0,
  maximum_attempts integer not null default 3,
  next_retry_at timestamptz,

  worker_id text,
  lock_token text,
  lock_expires_at timestamptz,

  queued_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,

  duration_ms bigint,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    automation_run_id,
    automation_node_id,
    execution_number
  )
);

create index if not exists automation_node_executions_queue_idx
  on public.automation_node_executions (
    status,
    next_retry_at,
    queued_at,
    created_at
  )
  where status in ('pending','queued','waiting');

create index if not exists automation_node_executions_run_idx
  on public.automation_node_executions (
    automation_run_id,
    created_at
  );

-- ============================================================
-- 11. EVENT BUS
-- ============================================================

create table if not exists public.automation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  event_name text not null,
  event_version integer not null default 1,

  source_module text,
  source_type text,
  source_id uuid,
  source_reference text,

  correlation_id text,
  trace_id text,
  idempotency_key text,

  payload jsonb not null default '{}',
  headers jsonb not null default '{}',

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'processing',
        'processed',
        'ignored',
        'failed',
        'dead_lettered'
      )
    ),

  attempts integer not null default 0,
  maximum_attempts integer not null default 5,
  next_retry_at timestamptz,

  received_at timestamptz not null default now(),
  processed_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  created_at timestamptz not null default now()
);

create unique index if not exists automation_events_idempotency_idx
  on public.automation_events (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists automation_events_processing_idx
  on public.automation_events (
    status,
    next_retry_at,
    received_at
  )
  where status in ('pending','failed');

create index if not exists automation_events_name_idx
  on public.automation_events (
    organization_id,
    event_name,
    received_at desc
  );

-- ============================================================
-- 12. SCHEDULES
-- ============================================================

create table if not exists public.automation_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  automation_id uuid not null references public.automation_definitions(id) on delete cascade,
  trigger_id uuid references public.automation_triggers(id) on delete cascade,

  schedule_name text not null,
  schedule_type text not null default 'cron'
    check (
      schedule_type in (
        'cron',
        'interval',
        'once',
        'calendar',
        'custom'
      )
    ),

  cron_expression text,
  interval_seconds integer,
  run_at timestamptz,

  timezone text not null default 'Asia/Kolkata',

  status text not null default 'active'
    check (status in ('active','paused','completed','cancelled','archived')),

  next_run_at timestamptz,
  last_run_at timestamptz,
  last_run_id uuid references public.automation_runs(id) on delete set null,

  maximum_runs integer,
  run_count integer not null default 0,

  starts_at timestamptz,
  ends_at timestamptz,

  payload jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (automation_id,schedule_name)
);

create index if not exists automation_schedules_due_idx
  on public.automation_schedules (
    status,
    next_run_at
  )
  where status = 'active';

-- ============================================================
-- 13. DELAY QUEUE
-- ============================================================

create table if not exists public.automation_delay_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_run_id uuid not null references public.automation_runs(id) on delete cascade,
  node_execution_id uuid references public.automation_node_executions(id) on delete cascade,
  resume_node_id uuid references public.automation_nodes(id) on delete set null,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'processing',
        'completed',
        'cancelled',
        'failed',
        'expired'
      )
    ),

  resume_at timestamptz not null,
  payload jsonb not null default '{}',

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists automation_delay_queue_due_idx
  on public.automation_delay_queue (
    status,
    resume_at
  )
  where status = 'pending';

-- ============================================================
-- 14. TASK QUEUE
-- ============================================================

create table if not exists public.automation_task_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_run_id uuid not null references public.automation_runs(id) on delete cascade,
  node_execution_id uuid references public.automation_node_executions(id) on delete cascade,

  task_type text not null,
  queue_name text not null default 'default',

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'processing',
        'completed',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,
  payload jsonb not null default '{}',

  attempts integer not null default 0,
  maximum_attempts integer not null default 5,
  next_retry_at timestamptz,

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  completed_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists automation_task_queue_claim_idx
  on public.automation_task_queue (
    queue_name,
    status,
    priority,
    next_retry_at,
    created_at
  )
  where status in ('pending','failed');

-- ============================================================
-- 15. RETRY QUEUE
-- ============================================================

create table if not exists public.automation_retry_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_run_id uuid references public.automation_runs(id) on delete cascade,
  node_execution_id uuid references public.automation_node_executions(id) on delete cascade,

  retry_type text not null
    check (retry_type in ('run','node','event','task','webhook')),

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'processing',
        'completed',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  retry_attempt integer not null default 1,
  maximum_attempts integer not null default 5,

  retry_strategy text not null default 'exponential'
    check (
      retry_strategy in (
        'fixed',
        'linear',
        'exponential',
        'custom'
      )
    ),

  retry_delay_seconds integer not null default 60,
  scheduled_at timestamptz not null default now(),

  payload jsonb not null default '{}',

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  completed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists automation_retry_queue_due_idx
  on public.automation_retry_queue (
    status,
    scheduled_at
  )
  where status = 'pending';

-- ============================================================
-- 16. DEAD LETTER QUEUE
-- ============================================================

create table if not exists public.automation_dead_letter_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  source_type text not null,
  source_id uuid,
  automation_run_id uuid references public.automation_runs(id) on delete set null,
  node_execution_id uuid references public.automation_node_executions(id) on delete set null,

  reason_code text,
  reason_message text,

  payload jsonb not null default '{}',
  error_data jsonb not null default '{}',

  status text not null default 'open'
    check (status in ('open','requeued','resolved','ignored','archived')),

  requeued_at timestamptz,
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id) on delete set null,
  resolution_notes text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists automation_dead_letter_open_idx
  on public.automation_dead_letter_queue (
    organization_id,
    status,
    created_at desc
  )
  where status = 'open';

-- ============================================================
-- 17. DISTRIBUTED LOCKS
-- ============================================================

create table if not exists public.automation_locks (
  lock_key text primary key,
  organization_id uuid references public.organizations(id) on delete cascade,

  owner_id text not null,
  lock_token text not null,

  acquired_at timestamptz not null default now(),
  expires_at timestamptz not null,

  metadata jsonb not null default '{}'
);

create index if not exists automation_locks_expiry_idx
  on public.automation_locks (expires_at);

-- ============================================================
-- 18. WEBHOOK ENDPOINTS
-- ============================================================

create table if not exists public.automation_webhook_endpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_id uuid references public.automation_definitions(id) on delete cascade,
  trigger_id uuid references public.automation_triggers(id) on delete cascade,

  endpoint_name text not null,
  endpoint_path text not null,

  http_method text not null default 'POST'
    check (http_method in ('GET','POST','PUT','PATCH','DELETE')),

  status text not null default 'active'
    check (status in ('active','inactive','revoked','archived')),

  authentication_type text not null default 'none'
    check (
      authentication_type in (
        'none',
        'api_key',
        'basic',
        'bearer',
        'hmac',
        'custom'
      )
    ),

  secret_id uuid references public.automation_secrets(id) on delete set null,

  signature_header text,
  idempotency_header text,
  allowed_ip_ranges text[] not null default '{}',

  request_schema jsonb not null default '{}',
  response_configuration jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,endpoint_path,http_method)
);

-- ============================================================
-- 19. WEBHOOK INBOX
-- ============================================================

create table if not exists public.automation_webhook_inbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  webhook_endpoint_id uuid references public.automation_webhook_endpoints(id) on delete set null,

  request_id text,
  idempotency_key text,

  http_method text,
  request_path text,
  source_ip inet,

  headers jsonb not null default '{}',
  query_params jsonb not null default '{}',
  payload jsonb not null default '{}',

  signature_valid boolean,
  authentication_valid boolean,

  status text not null default 'received'
    check (
      status in (
        'received',
        'processing',
        'processed',
        'ignored',
        'failed',
        'dead_lettered'
      )
    ),

  automation_run_id uuid references public.automation_runs(id) on delete set null,

  attempts integer not null default 0,
  next_retry_at timestamptz,

  response_status integer,
  response_body jsonb not null default '{}',

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  received_at timestamptz not null default now(),
  processed_at timestamptz,

  created_at timestamptz not null default now()
);

create unique index if not exists automation_webhook_inbox_idempotency_idx
  on public.automation_webhook_inbox (
    webhook_endpoint_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists automation_webhook_inbox_processing_idx
  on public.automation_webhook_inbox (
    status,
    next_retry_at,
    received_at
  )
  where status in ('received','failed');

-- ============================================================
-- 20. MANUAL APPROVAL TASKS
-- ============================================================

create table if not exists public.automation_approval_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_run_id uuid not null references public.automation_runs(id) on delete cascade,
  node_execution_id uuid not null references public.automation_node_executions(id) on delete cascade,

  title text not null,
  description text,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'assigned',
        'approved',
        'rejected',
        'cancelled',
        'expired'
      )
    ),

  assigned_to uuid references auth.users(id) on delete set null,
  assigned_role text,

  due_at timestamptz,

  approval_options jsonb not null default '[]',
  context_data jsonb not null default '{}',

  decision text,
  decision_notes text,
  decision_data jsonb not null default '{}',

  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (node_execution_id)
);

create index if not exists automation_approval_tasks_queue_idx
  on public.automation_approval_tasks (
    organization_id,
    status,
    due_at,
    created_at
  )
  where status in ('pending','assigned');

-- ============================================================
-- 21. EVENT OUTBOX
-- ============================================================

create table if not exists public.automation_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_run_id uuid references public.automation_runs(id) on delete set null,
  node_execution_id uuid references public.automation_node_executions(id) on delete set null,

  event_name text not null,
  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'workflow_engine',
        'n8n',
        'webhook',
        'analytics',
        'notification',
        'audit'
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

create unique index if not exists automation_event_outbox_idempotency_idx
  on public.automation_event_outbox (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists automation_event_outbox_queue_idx
  on public.automation_event_outbox (
    status,
    available_at,
    priority,
    created_at
  )
  where status in ('pending','failed');

-- ============================================================
-- 22. AUDIT LOGS
-- ============================================================

create table if not exists public.automation_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  automation_id uuid references public.automation_definitions(id) on delete set null,
  automation_run_id uuid references public.automation_runs(id) on delete set null,
  node_execution_id uuid references public.automation_node_executions(id) on delete set null,

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

create index if not exists automation_logs_org_created_idx
  on public.automation_logs (
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
    'automation_definitions',
    'automation_triggers',
    'automation_nodes',
    'automation_secrets',
    'automation_runs',
    'automation_node_executions',
    'automation_schedules',
    'automation_delay_queue',
    'automation_task_queue',
    'automation_retry_queue',
    'automation_dead_letter_queue',
    'automation_webhook_endpoints',
    'automation_approval_tasks',
    'automation_event_outbox'
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
-- 24. PUBLISH AUTOMATION VERSION
-- ============================================================

create or replace function public.publish_automation_version(
  requested_automation_id uuid,
  requested_version_number integer
)
returns public.automation_versions
language plpgsql
security definer
set search_path = ''
as $$
declare
  automation_record public.automation_definitions;
  version_record public.automation_versions;
begin
  select *
  into automation_record
  from public.automation_definitions
  where id = requested_automation_id
  for update;

  if not found then
    raise exception 'Automation not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      automation_record.organization_id,
      'automation.publish'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into version_record
  from public.automation_versions
  where automation_id = requested_automation_id
    and version_number = requested_version_number
  for update;

  if not found then
    raise exception 'Automation version not found';
  end if;

  update public.automation_versions
  set status = 'deprecated'
  where automation_id = requested_automation_id
    and status = 'published'
    and id <> version_record.id;

  update public.automation_versions
  set
    status = 'published',
    published_at = now(),
    published_by = auth.uid()
  where id = version_record.id
  returning * into version_record;

  update public.automation_definitions
  set
    published_version = requested_version_number,
    current_version = greatest(current_version,requested_version_number),
    status = case when status = 'draft' then 'active' else status end,
    updated_by = auth.uid(),
    updated_at = now()
  where id = requested_automation_id;

  return version_record;
end;
$$;

revoke all
on function public.publish_automation_version(uuid,integer)
from public;

grant execute
on function public.publish_automation_version(uuid,integer)
to authenticated,service_role;

-- ============================================================
-- 25. CREATE AUTOMATION RUN
-- ============================================================

create or replace function public.create_automation_run(
  requested_automation_id uuid,
  requested_trigger_id uuid default null,
  requested_input_data jsonb default '{}'::jsonb,
  requested_trigger_type text default 'manual',
  requested_trigger_reference text default null,
  requested_idempotency_key text default null,
  requested_priority integer default 100,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_parent_run_id uuid default null
)
returns public.automation_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  automation_record public.automation_definitions;
  version_record public.automation_versions;
  existing_run public.automation_runs;
  created_run public.automation_runs;
begin
  select *
  into automation_record
  from public.automation_definitions
  where id = requested_automation_id
    and status = 'active';

  if not found then
    raise exception 'Active automation not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      automation_record.organization_id,
      'automation.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_run
    from public.automation_runs
    where organization_id = automation_record.organization_id
      and idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_run;
    end if;
  end if;

  select *
  into version_record
  from public.automation_versions
  where automation_id = automation_record.id
    and version_number = automation_record.published_version
    and status = 'published'
  limit 1;

  if not found then
    raise exception 'Published automation version not found';
  end if;

  if automation_record.concurrency_policy in ('single','skip_if_running')
    and exists (
      select 1
      from public.automation_runs r
      where r.automation_id = automation_record.id
        and r.status in ('queued','running','waiting','paused')
    ) then

    if automation_record.concurrency_policy = 'skip_if_running' then
      raise exception 'Automation already running';
    end if;
  end if;

  if automation_record.concurrency_policy = 'replace' then
    update public.automation_runs
    set
      status = 'cancelled',
      cancelled_at = now(),
      error_data = error_data || jsonb_build_object(
        'reason',
        'Replaced by a newer execution'
      ),
      updated_at = now()
    where automation_id = automation_record.id
      and status in ('queued','running','waiting','paused');
  end if;

  insert into public.automation_runs (
    organization_id,
    automation_id,
    automation_version_id,
    trigger_id,
    parent_run_id,
    root_run_id,
    correlation_id,
    trace_id,
    idempotency_key,
    trigger_type,
    trigger_reference,
    status,
    priority,
    input_data,
    context_data,
    maximum_attempts,
    queued_at,
    timeout_at,
    created_by,
    updated_by
  )
  values (
    automation_record.organization_id,
    automation_record.id,
    version_record.id,
    requested_trigger_id,
    requested_parent_run_id,
    coalesce(
      (
        select coalesce(root_run_id,id)
        from public.automation_runs
        where id = requested_parent_run_id
      ),
      null
    ),
    coalesce(requested_correlation_id,gen_random_uuid()::text),
    coalesce(requested_trace_id,gen_random_uuid()::text),
    requested_idempotency_key,
    requested_trigger_type,
    requested_trigger_reference,
    'queued',
    requested_priority,
    coalesce(requested_input_data,'{}'::jsonb),
    jsonb_build_object(
      'automation_code',
      automation_record.automation_code,
      'automation_version',
      version_record.version_number
    ),
    coalesce(
      (automation_record.default_retry_policy->>'maximum_attempts')::integer,
      3
    ),
    now(),
    now() + make_interval(
      secs => automation_record.execution_timeout_seconds
    ),
    auth.uid(),
    auth.uid()
  )
  returning * into created_run;

  update public.automation_runs
  set root_run_id = coalesce(root_run_id,id)
  where id = created_run.id
  returning * into created_run;

  insert into public.automation_logs (
    organization_id,
    automation_id,
    automation_run_id,
    log_level,
    event_name,
    message,
    log_data,
    correlation_id,
    trace_id
  )
  values (
    created_run.organization_id,
    created_run.automation_id,
    created_run.id,
    'info',
    'automation.run.created',
    'Automation run created',
    jsonb_build_object(
      'trigger_type',
      requested_trigger_type,
      'priority',
      requested_priority
    ),
    created_run.correlation_id,
    created_run.trace_id
  );

  return created_run;
end;
$$;

revoke all
on function public.create_automation_run(
  uuid,uuid,jsonb,text,text,text,integer,text,text,uuid
)
from public;

grant execute
on function public.create_automation_run(
  uuid,uuid,jsonb,text,text,text,integer,text,text,uuid
)
to authenticated,service_role;

-- ============================================================
-- 26. CLAIM AUTOMATION RUN
-- ============================================================

create or replace function public.claim_automation_run(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.automation_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_run public.automation_runs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim automation runs';
  end if;

  select *
  into target_run
  from public.automation_runs r
  where r.status in ('pending','queued','waiting')
    and (r.next_retry_at is null or r.next_retry_at <= now())
    and (r.timeout_at is null or r.timeout_at > now())
    and (
      requested_organization_id is null
      or r.organization_id = requested_organization_id
    )
  order by
    r.priority,
    r.queued_at,
    r.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.automation_runs
  set
    status = 'running',
    attempts = attempts + 1,
    started_at = coalesce(started_at,now()),
    metadata = metadata || jsonb_build_object(
      'worker_id',
      requested_worker_id,
      'lock_token',
      gen_random_uuid()::text,
      'lock_expires_at',
      now() + make_interval(
        secs => greatest(requested_lock_seconds,1)
      )
    ),
    updated_at = now()
  where id = target_run.id
  returning * into target_run;

  return target_run;
end;
$$;

revoke all
on function public.claim_automation_run(text,uuid,integer)
from public;

grant execute
on function public.claim_automation_run(text,uuid,integer)
to service_role;

-- ============================================================
-- 27. INITIALIZE RUN
-- ============================================================

create or replace function public.initialize_automation_run(
  requested_run_id uuid
)
returns public.automation_node_executions
language plpgsql
security definer
set search_path = ''
as $$
declare
  run_record public.automation_runs;
  start_node public.automation_nodes;
  node_execution public.automation_node_executions;
begin
  select *
  into run_record
  from public.automation_runs
  where id = requested_run_id
  for update;

  if not found then
    raise exception 'Automation run not found';
  end if;

  select *
  into start_node
  from public.automation_nodes n
  where n.automation_version_id = run_record.automation_version_id
    and n.node_type = 'start'
    and n.is_enabled = true
  order by n.execution_order,n.created_at
  limit 1;

  if not found then
    raise exception 'Automation start node not found';
  end if;

  insert into public.automation_node_executions (
    organization_id,
    automation_run_id,
    automation_node_id,
    node_key,
    node_type,
    execution_number,
    status,
    input_data,
    maximum_attempts,
    queued_at
  )
  values (
    run_record.organization_id,
    run_record.id,
    start_node.id,
    start_node.node_key,
    start_node.node_type,
    1,
    'queued',
    run_record.input_data,
    coalesce(
      (start_node.retry_policy->>'maximum_attempts')::integer,
      run_record.maximum_attempts
    ),
    now()
  )
  on conflict (
    automation_run_id,
    automation_node_id,
    execution_number
  )
  do update set
    status = 'queued',
    queued_at = now(),
    updated_at = now()
  returning * into node_execution;

  update public.automation_runs
  set
    current_node_id = start_node.id,
    current_node_key = start_node.node_key,
    status = 'running',
    updated_at = now()
  where id = run_record.id;

  return node_execution;
end;
$$;

revoke all
on function public.initialize_automation_run(uuid)
from public;

grant execute
on function public.initialize_automation_run(uuid)
to service_role;

-- ============================================================
-- 28. CLAIM NODE EXECUTION
-- ============================================================

create or replace function public.claim_automation_node_execution(
  requested_worker_id text,
  requested_queue_node_type text default null,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.automation_node_executions
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_execution public.automation_node_executions;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim node executions';
  end if;

  select *
  into target_execution
  from public.automation_node_executions e
  where e.status in ('pending','queued','waiting')
    and (e.next_retry_at is null or e.next_retry_at <= now())
    and (
      requested_queue_node_type is null
      or e.node_type = requested_queue_node_type
    )
    and (
      requested_organization_id is null
      or e.organization_id = requested_organization_id
    )
  order by
    coalesce(e.queued_at,e.created_at),
    e.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.automation_node_executions
  set
    status = 'running',
    attempts = attempts + 1,
    started_at = coalesce(started_at,now()),
    worker_id = requested_worker_id,
    lock_token = gen_random_uuid()::text,
    lock_expires_at = now() + make_interval(
      secs => greatest(requested_lock_seconds,1)
    ),
    updated_at = now()
  where id = target_execution.id
  returning * into target_execution;

  return target_execution;
end;
$$;

revoke all
on function public.claim_automation_node_execution(
  text,text,uuid,integer
)
from public;

grant execute
on function public.claim_automation_node_execution(
  text,text,uuid,integer
)
to service_role;

-- ============================================================
-- 29. COMPLETE NODE EXECUTION
-- ============================================================

create or replace function public.complete_automation_node_execution(
  requested_node_execution_id uuid,
  requested_lock_token text,
  requested_output_data jsonb default '{}'::jsonb,
  requested_edge_type text default 'success'
)
returns public.automation_node_executions
language plpgsql
security definer
set search_path = ''
as $$
declare
  node_execution public.automation_node_executions;
  run_record public.automation_runs;
  node_record public.automation_nodes;
  edge_record public.automation_edges;
  next_execution public.automation_node_executions;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete node executions';
  end if;

  select *
  into node_execution
  from public.automation_node_executions
  where id = requested_node_execution_id
  for update;

  if not found then
    raise exception 'Node execution not found';
  end if;

  if node_execution.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid node execution lock token';
  end if;

  select *
  into run_record
  from public.automation_runs
  where id = node_execution.automation_run_id
  for update;

  select *
  into node_record
  from public.automation_nodes
  where id = node_execution.automation_node_id;

  update public.automation_node_executions
  set
    status = 'completed',
    output_data = coalesce(requested_output_data,'{}'::jsonb),
    completed_at = now(),
    duration_ms = extract(
      epoch from (
        now() - coalesce(started_at,created_at)
      )
    ) * 1000,
    worker_id = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where id = node_execution.id
  returning * into node_execution;

  update public.automation_runs
  set
    context_data = context_data || jsonb_build_object(
      node_execution.node_key,
      node_execution.output_data
    ),
    updated_at = now()
  where id = run_record.id;

  if node_record.is_terminal or node_record.node_type = 'end' then
    update public.automation_runs
    set
      status = 'completed',
      output_data = node_execution.output_data,
      completed_at = now(),
      current_node_id = node_record.id,
      current_node_key = node_record.node_key,
      updated_at = now()
    where id = run_record.id;

    return node_execution;
  end if;

  select *
  into edge_record
  from public.automation_edges e
  where e.automation_version_id = run_record.automation_version_id
    and e.source_node_id = node_record.id
    and e.edge_type in (requested_edge_type,'default')
  order by
    case when e.edge_type = requested_edge_type then 0 else 1 end,
    e.priority,
    e.created_at
  limit 1;

  if not found then
    update public.automation_runs
    set
      status = 'completed',
      output_data = node_execution.output_data,
      completed_at = now(),
      updated_at = now()
    where id = run_record.id;

    return node_execution;
  end if;

  insert into public.automation_node_executions (
    organization_id,
    automation_run_id,
    automation_node_id,
    node_key,
    node_type,
    execution_number,
    status,
    input_data,
    maximum_attempts,
    queued_at
  )
  select
    run_record.organization_id,
    run_record.id,
    next_node.id,
    next_node.node_key,
    next_node.node_type,
    coalesce(
      (
        select max(existing.execution_number) + 1
        from public.automation_node_executions existing
        where existing.automation_run_id = run_record.id
          and existing.automation_node_id = next_node.id
      ),
      1
    ),
    'queued',
    node_execution.output_data,
    coalesce(
      (next_node.retry_policy->>'maximum_attempts')::integer,
      run_record.maximum_attempts
    ),
    now()
  from public.automation_nodes next_node
  where next_node.id = edge_record.target_node_id
  returning * into next_execution;

  update public.automation_runs
  set
    current_node_id = next_execution.automation_node_id,
    current_node_key = next_execution.node_key,
    status = 'running',
    updated_at = now()
  where id = run_record.id;

  return node_execution;
end;
$$;

revoke all
on function public.complete_automation_node_execution(
  uuid,text,jsonb,text
)
from public;

grant execute
on function public.complete_automation_node_execution(
  uuid,text,jsonb,text
)
to service_role;

-- ============================================================
-- 30. FAIL NODE EXECUTION
-- ============================================================

create or replace function public.fail_automation_node_execution(
  requested_node_execution_id uuid,
  requested_lock_token text,
  requested_error_code text,
  requested_error_message text,
  requested_error_data jsonb default '{}'::jsonb,
  requested_retry_delay_seconds integer default 60
)
returns public.automation_node_executions
language plpgsql
security definer
set search_path = ''
as $$
declare
  node_execution public.automation_node_executions;
  next_status text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may fail node executions';
  end if;

  select *
  into node_execution
  from public.automation_node_executions
  where id = requested_node_execution_id
  for update;

  if not found then
    raise exception 'Node execution not found';
  end if;

  if node_execution.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid node execution lock token';
  end if;

  next_status :=
    case
      when node_execution.attempts >= node_execution.maximum_attempts
        then 'failed'
      else 'waiting'
    end;

  update public.automation_node_executions
  set
    status = next_status,
    failed_at = now(),
    next_retry_at =
      case
        when next_status = 'waiting'
          then now() + make_interval(
            secs => greatest(requested_retry_delay_seconds,1)
          )
        else null
      end,
    error_data = jsonb_build_object(
      'code',
      requested_error_code,
      'message',
      requested_error_message,
      'data',
      coalesce(requested_error_data,'{}'::jsonb)
    ),
    worker_id = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where id = node_execution.id
  returning * into node_execution;

  if next_status = 'failed' then
    insert into public.automation_dead_letter_queue (
      organization_id,
      source_type,
      source_id,
      automation_run_id,
      node_execution_id,
      reason_code,
      reason_message,
      payload,
      error_data
    )
    values (
      node_execution.organization_id,
      'node_execution',
      node_execution.id,
      node_execution.automation_run_id,
      node_execution.id,
      requested_error_code,
      requested_error_message,
      node_execution.input_data,
      coalesce(requested_error_data,'{}'::jsonb)
    );

    update public.automation_runs
    set
      status = 'failed',
      failed_at = now(),
      error_data = jsonb_build_object(
        'node_execution_id',
        node_execution.id,
        'code',
        requested_error_code,
        'message',
        requested_error_message
      ),
      updated_at = now()
    where id = node_execution.automation_run_id;
  end if;

  return node_execution;
end;
$$;

revoke all
on function public.fail_automation_node_execution(
  uuid,text,text,text,jsonb,integer
)
from public;

grant execute
on function public.fail_automation_node_execution(
  uuid,text,text,text,jsonb,integer
)
to service_role;

-- ============================================================
-- 31. PUBLISH AUTOMATION EVENT
-- ============================================================

create or replace function public.publish_automation_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_source_module text default null,
  requested_source_type text default null,
  requested_source_id uuid default null,
  requested_source_reference text default null,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns public.automation_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.automation_events;
  created_event public.automation_events;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.automation_events e
    where e.organization_id is not distinct from requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.automation_events (
    organization_id,
    event_name,
    source_module,
    source_type,
    source_id,
    source_reference,
    correlation_id,
    trace_id,
    idempotency_key,
    payload,
    status
  )
  values (
    requested_organization_id,
    requested_event_name,
    requested_source_module,
    requested_source_type,
    requested_source_id,
    requested_source_reference,
    coalesce(requested_correlation_id,gen_random_uuid()::text),
    coalesce(requested_trace_id,gen_random_uuid()::text),
    requested_idempotency_key,
    coalesce(requested_payload,'{}'::jsonb),
    'pending'
  )
  returning * into created_event;

  return created_event;
end;
$$;

revoke all
on function public.publish_automation_event(
  uuid,text,jsonb,text,text,uuid,text,text,text,text
)
from public;

grant execute
on function public.publish_automation_event(
  uuid,text,jsonb,text,text,uuid,text,text,text,text
)
to authenticated,service_role;

-- ============================================================
-- 32. PROCESS EVENT
-- ============================================================

create or replace function public.process_automation_event(
  requested_event_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_record public.automation_events;
  trigger_record record;
  run_count integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may process automation events';
  end if;

  select *
  into event_record
  from public.automation_events
  where id = requested_event_id
  for update;

  if not found then
    raise exception 'Automation event not found';
  end if;

  update public.automation_events
  set
    status = 'processing',
    attempts = attempts + 1
  where id = event_record.id;

  for trigger_record in
    select
      t.*,
      a.id as automation_definition_id
    from public.automation_triggers t
    join public.automation_definitions a
      on a.id = t.automation_id
    where t.status = 'active'
      and a.status = 'active'
      and t.trigger_type = 'event'
      and t.event_name = event_record.event_name
      and (
        event_record.organization_id is null
        or t.organization_id = event_record.organization_id
      )
  loop
    perform public.create_automation_run(
      trigger_record.automation_definition_id,
      trigger_record.id,
      event_record.payload,
      'event',
      event_record.id::text,
      case
        when event_record.idempotency_key is not null
          then event_record.idempotency_key
            || ':'
            || trigger_record.id::text
        else null
      end,
      100,
      event_record.correlation_id,
      event_record.trace_id,
      null
    );

    run_count := run_count + 1;
  end loop;

  update public.automation_events
  set
    status =
      case
        when run_count > 0 then 'processed'
        else 'ignored'
      end,
    processed_at = now()
  where id = event_record.id;

  return run_count;
end;
$$;

revoke all
on function public.process_automation_event(uuid)
from public;

grant execute
on function public.process_automation_event(uuid)
to service_role;

-- ============================================================
-- 33. ACQUIRE / RELEASE DISTRIBUTED LOCK
-- ============================================================

create or replace function public.acquire_automation_lock(
  requested_lock_key text,
  requested_owner_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300,
  requested_metadata jsonb default '{}'::jsonb
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_value text := gen_random_uuid()::text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may acquire automation locks';
  end if;

  delete from public.automation_locks
  where lock_key = requested_lock_key
    and expires_at <= now();

  insert into public.automation_locks (
    lock_key,
    organization_id,
    owner_id,
    lock_token,
    acquired_at,
    expires_at,
    metadata
  )
  values (
    requested_lock_key,
    requested_organization_id,
    requested_owner_id,
    token_value,
    now(),
    now() + make_interval(
      secs => greatest(requested_lock_seconds,1)
    ),
    coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (lock_key)
  do nothing;

  if not found then
    return null;
  end if;

  return token_value;
end;
$$;

create or replace function public.release_automation_lock(
  requested_lock_key text,
  requested_lock_token text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_count integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may release automation locks';
  end if;

  delete from public.automation_locks
  where lock_key = requested_lock_key
    and lock_token = requested_lock_token;

  get diagnostics deleted_count = row_count;

  return deleted_count > 0;
end;
$$;

revoke all
on function public.acquire_automation_lock(
  text,text,uuid,integer,jsonb
)
from public;

revoke all
on function public.release_automation_lock(text,text)
from public;

grant execute
on function public.acquire_automation_lock(
  text,text,uuid,integer,jsonb
)
to service_role;

grant execute
on function public.release_automation_lock(text,text)
to service_role;

-- ============================================================
-- 34. PUBLISH OUTBOX EVENT
-- ============================================================

create or replace function public.publish_automation_outbox_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_automation_run_id uuid default null,
  requested_node_execution_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.automation_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.automation_event_outbox;
  created_event public.automation_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.automation_event_outbox e
    where e.organization_id = requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.automation_event_outbox (
    organization_id,
    automation_run_id,
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
    requested_automation_run_id,
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
on function public.publish_automation_outbox_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_automation_outbox_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 35. RUN STATUS EVENT TRIGGER
-- ============================================================

create or replace function public.emit_automation_run_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload_data jsonb;
begin
  if tg_op = 'UPDATE'
    and new.status is not distinct from old.status then
    return new;
  end if;

  payload_data := jsonb_build_object(
    'organization_id',
    new.organization_id,
    'automation_id',
    new.automation_id,
    'automation_run_id',
    new.id,
    'automation_version_id',
    new.automation_version_id,
    'status',
    new.status,
    'trigger_type',
    new.trigger_type,
    'trigger_reference',
    new.trigger_reference,
    'current_node_key',
    new.current_node_key,
    'started_at',
    new.started_at,
    'completed_at',
    new.completed_at,
    'failed_at',
    new.failed_at,
    'output_data',
    new.output_data,
    'error_data',
    new.error_data
  );

  perform public.publish_automation_outbox_event(
    new.organization_id,
    'automation.run.' || new.status,
    payload_data,
    'n8n',
    new.id,
    null,
    case
      when new.status in ('failed','dead_lettered') then 10
      else 50
    end,
    'automation-run:'
      || new.id::text
      || ':'
      || new.status,
    new.correlation_id,
    new.trace_id,
    now()
  );

  return new;
end;
$$;

drop trigger if exists automation_runs_emit_events
on public.automation_runs;

create trigger automation_runs_emit_events
after insert or update
on public.automation_runs
for each row
execute function public.emit_automation_run_events();

-- ============================================================
-- 36. CANCEL AUTOMATION RUN
-- ============================================================

create or replace function public.cancel_automation_run(
  requested_run_id uuid,
  requested_reason text default 'Cancelled manually'
)
returns public.automation_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  run_record public.automation_runs;
begin
  select *
  into run_record
  from public.automation_runs
  where id = requested_run_id
  for update;

  if not found then
    raise exception 'Automation run not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      run_record.organization_id,
      'automation.cancel'
    ) then
    raise exception 'Permission denied';
  end if;

  if run_record.status in (
    'completed',
    'failed',
    'cancelled',
    'timed_out',
    'dead_lettered'
  ) then
    return run_record;
  end if;

  update public.automation_node_executions
  set
    status = 'cancelled',
    updated_at = now()
  where automation_run_id = run_record.id
    and status in ('pending','queued','running','waiting');

  update public.automation_delay_queue
  set
    status = 'cancelled',
    updated_at = now()
  where automation_run_id = run_record.id
    and status in ('pending','claimed','processing');

  update public.automation_task_queue
  set
    status = 'cancelled',
    updated_at = now()
  where automation_run_id = run_record.id
    and status in ('pending','claimed','processing');

  update public.automation_runs
  set
    status = 'cancelled',
    cancelled_at = now(),
    error_data = error_data || jsonb_build_object(
      'cancel_reason',
      requested_reason
    ),
    updated_at = now()
  where id = run_record.id
  returning * into run_record;

  return run_record;
end;
$$;

revoke all
on function public.cancel_automation_run(uuid,text)
from public;

grant execute
on function public.cancel_automation_run(uuid,text)
to authenticated,service_role;

-- ============================================================
-- 37. MANUAL APPROVAL DECISION
-- ============================================================

create or replace function public.decide_automation_approval_task(
  requested_task_id uuid,
  requested_decision text,
  requested_notes text default null,
  requested_decision_data jsonb default '{}'::jsonb
)
returns public.automation_approval_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  task_record public.automation_approval_tasks;
begin
  if requested_decision not in ('approved','rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  select *
  into task_record
  from public.automation_approval_tasks
  where id = requested_task_id
  for update;

  if not found then
    raise exception 'Automation approval task not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from task_record.assigned_to
    and not public.has_organization_permission(
      task_record.organization_id,
      'automation.override'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.automation_approval_tasks
  set
    status = requested_decision,
    decision = requested_decision,
    decision_notes = requested_notes,
    decision_data = coalesce(requested_decision_data,'{}'::jsonb),
    decided_by = auth.uid(),
    decided_at = now(),
    updated_at = now()
  where id = requested_task_id
  returning * into task_record;

  update public.automation_node_executions
  set
    status = 'queued',
    output_data = jsonb_build_object(
      'approval_decision',
      requested_decision,
      'approval_notes',
      requested_notes,
      'approval_data',
      coalesce(requested_decision_data,'{}'::jsonb)
    ),
    queued_at = now(),
    updated_at = now()
  where id = task_record.node_execution_id;

  update public.automation_runs
  set
    status = 'running',
    updated_at = now()
  where id = task_record.automation_run_id;

  return task_record;
end;
$$;

revoke all
on function public.decide_automation_approval_task(
  uuid,text,text,jsonb
)
from public;

grant execute
on function public.decide_automation_approval_task(
  uuid,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 38. RELEASE EXPIRED LOCKS
-- ============================================================

create or replace function public.release_expired_automation_locks()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  node_count integer := 0;
  task_count integer := 0;
  delay_count integer := 0;
  outbox_count integer := 0;
  lock_count integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may release automation locks';
  end if;

  update public.automation_node_executions
  set
    status = 'queued',
    worker_id = null,
    lock_token = null,
    lock_expires_at = null,
    queued_at = now(),
    updated_at = now()
  where status = 'running'
    and lock_expires_at is not null
    and lock_expires_at <= now();

  get diagnostics node_count = row_count;

  update public.automation_task_queue
  set
    status = 'pending',
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where status in ('claimed','processing')
    and lock_expires_at is not null
    and lock_expires_at <= now();

  get diagnostics task_count = row_count;

  update public.automation_delay_queue
  set
    status = 'pending',
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where status in ('claimed','processing')
    and lock_expires_at is not null
    and lock_expires_at <= now();

  get diagnostics delay_count = row_count;

  update public.automation_event_outbox
  set
    status =
      case
        when delivery_attempts >= maximum_attempts
          then 'dead_lettered'
        else 'failed'
      end,
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    available_at = now(),
    updated_at = now()
  where status in ('claimed','processing')
    and lock_expires_at is not null
    and lock_expires_at <= now();

  get diagnostics outbox_count = row_count;

  delete from public.automation_locks
  where expires_at <= now();

  get diagnostics lock_count = row_count;

  return jsonb_build_object(
    'node_locks_released',
    node_count,
    'task_locks_released',
    task_count,
    'delay_locks_released',
    delay_count,
    'outbox_locks_released',
    outbox_count,
    'distributed_locks_removed',
    lock_count,
    'released_at',
    now()
  );
end;
$$;

revoke all
on function public.release_expired_automation_locks()
from public;

grant execute
on function public.release_expired_automation_locks()
to service_role;

-- ============================================================
-- 39. ANALYTICS VIEWS
-- ============================================================

create or replace view public.automation_run_dashboard
with (security_invoker = true)
as
select
  r.organization_id,
  r.automation_id,
  d.automation_code,
  d.automation_name,
  date_trunc('day',r.created_at)::date as run_date,

  count(*) as total_runs,

  count(*) filter (
    where r.status = 'completed'
  ) as completed_runs,

  count(*) filter (
    where r.status = 'failed'
  ) as failed_runs,

  count(*) filter (
    where r.status = 'cancelled'
  ) as cancelled_runs,

  count(*) filter (
    where r.status = 'running'
  ) as running_runs,

  count(*) filter (
    where r.status = 'waiting'
  ) as waiting_runs,

  round(
    (
      count(*) filter (
        where r.status = 'completed'
      )::numeric
      / nullif(count(*),0)
    ) * 100,
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
  d.automation_name,
  date_trunc('day',r.created_at)::date;

create or replace view public.automation_node_performance
with (security_invoker = true)
as
select
  e.organization_id,
  e.automation_node_id,
  n.node_key,
  n.node_name,
  n.node_type,

  count(*) as total_executions,

  count(*) filter (
    where e.status = 'completed'
  ) as completed_count,

  count(*) filter (
    where e.status = 'failed'
  ) as failed_count,

  round(
    avg(e.duration_ms),
    2
  ) as average_duration_ms,

  max(e.duration_ms) as maximum_duration_ms,

  round(
    avg(e.attempts),
    2
  ) as average_attempts

from public.automation_node_executions e
join public.automation_nodes n
  on n.id = e.automation_node_id
group by
  e.organization_id,
  e.automation_node_id,
  n.node_key,
  n.node_name,
  n.node_type;

create or replace view public.automation_queue_health
with (security_invoker = true)
as
select
  organization_id,

  (
    select count(*)
    from public.automation_runs r
    where r.organization_id = o.organization_id
      and r.status in ('pending','queued','waiting')
  ) as queued_runs,

  (
    select count(*)
    from public.automation_node_executions e
    where e.organization_id = o.organization_id
      and e.status in ('pending','queued','waiting')
  ) as queued_nodes,

  (
    select count(*)
    from public.automation_task_queue q
    where q.organization_id = o.organization_id
      and q.status in ('pending','failed')
  ) as queued_tasks,

  (
    select count(*)
    from public.automation_delay_queue q
    where q.organization_id = o.organization_id
      and q.status = 'pending'
  ) as delayed_tasks,

  (
    select count(*)
    from public.automation_retry_queue q
    where q.organization_id = o.organization_id
      and q.status = 'pending'
  ) as pending_retries,

  (
    select count(*)
    from public.automation_dead_letter_queue q
    where q.organization_id = o.organization_id
      and q.status = 'open'
  ) as dead_letters,

  (
    select count(*)
    from public.automation_event_outbox q
    where q.organization_id = o.organization_id
      and q.status in ('pending','failed')
  ) as pending_outbox_events

from (
  select distinct organization_id
  from public.automation_definitions
) o;

create or replace view public.automation_trigger_dashboard
with (security_invoker = true)
as
select
  t.organization_id,
  t.id as trigger_id,
  t.trigger_name,
  t.trigger_type,
  t.event_name,
  t.status,

  count(r.id) as total_runs,

  count(r.id) filter (
    where r.status = 'completed'
  ) as completed_runs,

  count(r.id) filter (
    where r.status = 'failed'
  ) as failed_runs,

  max(r.created_at) as latest_run_at

from public.automation_triggers t
left join public.automation_runs r
  on r.trigger_id = t.id
group by
  t.organization_id,
  t.id,
  t.trigger_name,
  t.trigger_type,
  t.event_name,
  t.status;

grant select
on
  public.automation_run_dashboard,
  public.automation_node_performance,
  public.automation_queue_health,
  public.automation_trigger_dashboard
to authenticated,service_role;

-- ============================================================
-- 40. HEALTH CHECK
-- ============================================================

create or replace function public.get_automation_engine_health(
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
        'automation.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',
    requested_organization_id,
    'checked_at',
    now(),

    'active_automations',
    (
      select count(*)
      from public.automation_definitions d
      where d.status = 'active'
        and (
          requested_organization_id is null
          or d.organization_id = requested_organization_id
        )
    ),

    'queued_runs',
    (
      select count(*)
      from public.automation_runs r
      where r.status in ('pending','queued','waiting')
        and (
          requested_organization_id is null
          or r.organization_id = requested_organization_id
        )
    ),

    'running_runs',
    (
      select count(*)
      from public.automation_runs r
      where r.status = 'running'
        and (
          requested_organization_id is null
          or r.organization_id = requested_organization_id
        )
    ),

    'failed_runs_24h',
    (
      select count(*)
      from public.automation_runs r
      where r.status = 'failed'
        and r.updated_at >= now() - interval '24 hours'
        and (
          requested_organization_id is null
          or r.organization_id = requested_organization_id
        )
    ),

    'queued_nodes',
    (
      select count(*)
      from public.automation_node_executions e
      where e.status in ('pending','queued','waiting')
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    ),

    'pending_events',
    (
      select count(*)
      from public.automation_events e
      where e.status in ('pending','failed')
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    ),

    'pending_delays',
    (
      select count(*)
      from public.automation_delay_queue q
      where q.status = 'pending'
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'pending_tasks',
    (
      select count(*)
      from public.automation_task_queue q
      where q.status in ('pending','failed')
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'open_dead_letters',
    (
      select count(*)
      from public.automation_dead_letter_queue q
      where q.status = 'open'
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'pending_approvals',
    (
      select count(*)
      from public.automation_approval_tasks q
      where q.status in ('pending','assigned')
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',
    (
      select count(*)
      from public.automation_event_outbox q
      where q.status in ('pending','failed')
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    )
  );
end;
$$;

revoke all
on function public.get_automation_engine_health(uuid)
from public;

grant execute
on function public.get_automation_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 41. RLS
-- ============================================================

alter table public.automation_definitions enable row level security;
alter table public.automation_versions enable row level security;
alter table public.automation_triggers enable row level security;
alter table public.automation_nodes enable row level security;
alter table public.automation_edges enable row level security;
alter table public.automation_variables enable row level security;
alter table public.automation_secrets enable row level security;
alter table public.automation_runs enable row level security;
alter table public.automation_node_executions enable row level security;
alter table public.automation_events enable row level security;
alter table public.automation_schedules enable row level security;
alter table public.automation_delay_queue enable row level security;
alter table public.automation_task_queue enable row level security;
alter table public.automation_retry_queue enable row level security;
alter table public.automation_dead_letter_queue enable row level security;
alter table public.automation_locks enable row level security;
alter table public.automation_webhook_endpoints enable row level security;
alter table public.automation_webhook_inbox enable row level security;
alter table public.automation_approval_tasks enable row level security;
alter table public.automation_event_outbox enable row level security;
alter table public.automation_logs enable row level security;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'automation_definitions',
    'automation_versions',
    'automation_triggers',
    'automation_nodes',
    'automation_edges',
    'automation_variables',
    'automation_secrets',
    'automation_runs',
    'automation_node_executions',
    'automation_events',
    'automation_schedules',
    'automation_delay_queue',
    'automation_task_queue',
    'automation_retry_queue',
    'automation_dead_letter_queue',
    'automation_locks',
    'automation_webhook_endpoints',
    'automation_webhook_inbox',
    'automation_approval_tasks',
    'automation_event_outbox',
    'automation_logs'
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
           ''automation.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''automation.view_all''
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

drop policy if exists
automation_definitions_write_policy
on public.automation_definitions;

create policy
automation_definitions_write_policy
on public.automation_definitions
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'automation.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'automation.create'
  )
  or public.has_organization_permission(
    organization_id,
    'automation.update'
  )
);

drop policy if exists
automation_triggers_write_policy
on public.automation_triggers;

create policy
automation_triggers_write_policy
on public.automation_triggers
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'automation.manage_triggers'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'automation.manage_triggers'
  )
);

drop policy if exists
automation_schedules_write_policy
on public.automation_schedules;

create policy
automation_schedules_write_policy
on public.automation_schedules
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'automation.manage_schedules'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'automation.manage_schedules'
  )
);

drop policy if exists
automation_webhook_endpoints_write_policy
on public.automation_webhook_endpoints;

create policy
automation_webhook_endpoints_write_policy
on public.automation_webhook_endpoints
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'automation.manage_webhooks'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'automation.manage_webhooks'
  )
);

-- ============================================================
-- 42. GRANTS
-- ============================================================

grant select
on
  public.automation_definitions,
  public.automation_versions,
  public.automation_triggers,
  public.automation_nodes,
  public.automation_edges,
  public.automation_variables,
  public.automation_runs,
  public.automation_node_executions,
  public.automation_events,
  public.automation_schedules,
  public.automation_delay_queue,
  public.automation_task_queue,
  public.automation_retry_queue,
  public.automation_dead_letter_queue,
  public.automation_webhook_endpoints,
  public.automation_webhook_inbox,
  public.automation_approval_tasks,
  public.automation_event_outbox,
  public.automation_logs
to authenticated;

grant insert,update,delete
on
  public.automation_definitions,
  public.automation_versions,
  public.automation_triggers,
  public.automation_nodes,
  public.automation_edges,
  public.automation_variables,
  public.automation_schedules,
  public.automation_webhook_endpoints
to authenticated;

grant all
on
  public.automation_definitions,
  public.automation_versions,
  public.automation_triggers,
  public.automation_nodes,
  public.automation_edges,
  public.automation_variables,
  public.automation_secrets,
  public.automation_runs,
  public.automation_node_executions,
  public.automation_events,
  public.automation_schedules,
  public.automation_delay_queue,
  public.automation_task_queue,
  public.automation_retry_queue,
  public.automation_dead_letter_queue,
  public.automation_locks,
  public.automation_webhook_endpoints,
  public.automation_webhook_inbox,
  public.automation_approval_tasks,
  public.automation_event_outbox,
  public.automation_logs
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
    'automation_definitions',
    'automation_versions',
    'automation_triggers',
    'automation_nodes',
    'automation_edges',
    'automation_variables',
    'automation_runs',
    'automation_node_executions',
    'automation_events',
    'automation_schedules',
    'automation_delay_queue',
    'automation_task_queue',
    'automation_retry_queue',
    'automation_dead_letter_queue',
    'automation_locks',
    'automation_webhook_endpoints',
    'automation_webhook_inbox',
    'automation_approval_tasks',
    'automation_event_outbox',
    'automation_logs'
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
    'publish_automation_version',
    'create_automation_run',
    'claim_automation_run',
    'initialize_automation_run',
    'claim_automation_node_execution',
    'complete_automation_node_execution',
    'fail_automation_node_execution',
    'publish_automation_event',
    'process_automation_event',
    'acquire_automation_lock',
    'release_automation_lock',
    'publish_automation_outbox_event',
    'cancel_automation_run',
    'decide_automation_approval_task',
    'release_expired_automation_locks',
    'get_automation_engine_health'
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
      '014 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 44. MIGRATION AUDIT
-- ============================================================

insert into public.automation_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.014.completed',
  'Automation Execution Engine migration 014 completed',
  jsonb_build_object(
    'migration',
    '014_automation_execution_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'definitions',
      'versions',
      'triggers',
      'nodes',
      'edges',
      'variables',
      'secrets',
      'runs',
      'node_executions',
      'event_bus',
      'schedules',
      'delay_queue',
      'task_queue',
      'retry_queue',
      'dead_letter_queue',
      'distributed_locks',
      'webhooks',
      'manual_approvals',
      'event_outbox',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.automation_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.014.completed'
);

commit;