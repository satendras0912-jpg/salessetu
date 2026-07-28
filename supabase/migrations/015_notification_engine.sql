-- ============================================================
-- SalesSetu Enterprise
-- Migration 015: Notification Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   009_workflow_engine_v2.sql
--   012_assignment_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--
-- Scope:
--   • In-app, push, email, SMS and WhatsApp notification orchestration
--   • User, role, team, organization and lead-targeted notifications
--   • Templates, categories, preferences and quiet hours
--   • Notification inbox, recipient states and read tracking
--   • Digests, reminders, escalation and retry queues
--   • Provider abstraction and communication-engine handoff
--   • Workflow/n8n event outbox
--   • Analytics, RLS, permissions, grants and health checks
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
    ('notification','view','notification.view','View notifications'),
    ('notification','view_all','notification.view_all','View all organization notifications'),
    ('notification','send','notification.send','Send notifications'),
    ('notification','send_bulk','notification.send_bulk','Send bulk notifications'),
    ('notification','manage_templates','notification.manage_templates','Manage notification templates'),
    ('notification','manage_categories','notification.manage_categories','Manage notification categories'),
    ('notification','manage_preferences','notification.manage_preferences','Manage notification preferences'),
    ('notification','manage_channels','notification.manage_channels','Manage notification channels'),
    ('notification','manage_digests','notification.manage_digests','Manage notification digests'),
    ('notification','manage_escalations','notification.manage_escalations','Manage notification escalation rules'),
    ('notification','retry','notification.retry','Retry failed notifications'),
    ('notification','cancel','notification.cancel','Cancel queued notifications'),
    ('notification','mark_read','notification.mark_read','Mark notifications as read'),
    ('notification','view_logs','notification.view_logs','View notification logs'),
    ('notification','view_analytics','notification.view_analytics','View notification analytics'),
    ('notification','override','notification.override','Override notification restrictions')
) as permission_data(module,action,code,description)
where not exists (
  select 1
  from public.permissions p
  where p.code = permission_data.code
);

-- ============================================================
-- 2. NOTIFICATION CHANNELS
-- ============================================================

create table if not exists public.notification_channels (
  code text primary key,
  display_name text not null,
  channel_group text not null
    check (channel_group in ('in_app','push','email','sms','whatsapp','webhook','other')),

  supports_actions boolean not null default false,
  supports_deep_links boolean not null default false,
  supports_images boolean not null default false,
  supports_badges boolean not null default false,
  supports_delivery_receipts boolean not null default false,
  supports_read_receipts boolean not null default false,

  default_priority integer not null default 100,
  status text not null default 'active'
    check (status in ('active','inactive','deprecated')),

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

insert into public.notification_channels (
  code,
  display_name,
  channel_group,
  supports_actions,
  supports_deep_links,
  supports_images,
  supports_badges,
  supports_delivery_receipts,
  supports_read_receipts,
  default_priority
)
values
  ('in_app','In-app','in_app',true,true,true,true,true,true,50),
  ('push','Push Notification','push',true,true,true,true,true,true,40),
  ('email','Email','email',true,true,true,false,true,false,70),
  ('sms','SMS','sms',false,false,false,false,true,false,80),
  ('whatsapp','WhatsApp','whatsapp',true,true,true,false,true,true,60),
  ('webhook','Webhook','webhook',false,false,false,false,true,false,100)
on conflict (code) do update
set
  display_name = excluded.display_name,
  channel_group = excluded.channel_group,
  supports_actions = excluded.supports_actions,
  supports_deep_links = excluded.supports_deep_links,
  supports_images = excluded.supports_images,
  supports_badges = excluded.supports_badges,
  supports_delivery_receipts = excluded.supports_delivery_receipts,
  supports_read_receipts = excluded.supports_read_receipts,
  default_priority = excluded.default_priority;

-- ============================================================
-- 3. NOTIFICATION CATEGORIES
-- ============================================================

create table if not exists public.notification_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  category_code text not null,
  category_name text not null,
  description text,

  severity text not null default 'info'
    check (severity in ('info','success','warning','error','critical')),

  default_channels text[] not null default array['in_app'],
  default_priority integer not null default 100,

  is_system_category boolean not null default false,
  is_user_configurable boolean not null default true,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,category_code)
);

create unique index if not exists notification_categories_system_unique_idx
  on public.notification_categories (category_code)
  where organization_id is null;

insert into public.notification_categories (
  organization_id,
  category_code,
  category_name,
  description,
  severity,
  default_channels,
  default_priority,
  is_system_category,
  is_user_configurable
)
values
  (null,'lead_created','Lead Created','New lead created','info',array['in_app'],70,true,true),
  (null,'lead_validated','Lead Validated','Lead validation completed','success',array['in_app'],60,true,true),
  (null,'lead_rejected','Lead Rejected','Lead validation rejected','warning',array['in_app'],40,true,true),
  (null,'assignment_created','Assignment Created','Lead assigned to an agent','info',array['in_app','push'],40,true,true),
  (null,'assignment_sla','Assignment SLA','Assignment SLA breached','critical',array['in_app','push','email'],10,true,true),
  (null,'ai_call_completed','AI Call Completed','AI call completed','success',array['in_app'],60,true,true),
  (null,'ai_call_failed','AI Call Failed','AI call failed','error',array['in_app','push'],20,true,true),
  (null,'followup_due','Follow-up Due','Follow-up reminder','warning',array['in_app','push'],30,true,true),
  (null,'site_visit','Site Visit','Site visit notification','info',array['in_app','push','whatsapp'],40,true,true),
  (null,'booking','Booking','Booking update','success',array['in_app','email','whatsapp'],40,true,true),
  (null,'payment','Payment','Payment update','warning',array['in_app','email','whatsapp'],30,true,true),
  (null,'system_alert','System Alert','System operational alert','critical',array['in_app','email'],5,true,false),
  (null,'automation_failed','Automation Failed','Automation execution failed','error',array['in_app','email'],10,true,true)
on conflict do nothing;

-- ============================================================
-- 4. NOTIFICATION TEMPLATES
-- ============================================================

create table if not exists public.notification_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  template_code text not null,
  template_name text not null,

  category_id uuid references public.notification_categories(id) on delete set null,
  channel_code text not null references public.notification_channels(code) on delete restrict,

  language_code text not null default 'en',
  version integer not null default 1 check (version > 0),

  status text not null default 'draft'
    check (status in ('draft','active','inactive','archived')),

  title_template text not null,
  body_template text not null,
  short_body_template text,

  deep_link_template text,
  image_url_template text,

  action_schema jsonb not null default '[]',
  variable_schema jsonb not null default '{}',

  priority integer,
  ttl_seconds integer,
  sound text,
  badge_increment integer not null default 0,

  is_system_template boolean not null default false,
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    organization_id,
    template_code,
    channel_code,
    language_code,
    version
  )
);

create index if not exists notification_templates_lookup_idx
  on public.notification_templates (
    organization_id,
    template_code,
    channel_code,
    language_code,
    status
  );

-- ============================================================
-- 5. USER DEVICES
-- ============================================================

create table if not exists public.notification_user_devices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  device_type text not null
    check (device_type in ('web','android','ios','desktop','other')),

  device_identifier text,
  push_token text,
  endpoint text,

  browser text,
  operating_system text,
  app_version text,

  status text not null default 'active'
    check (status in ('active','inactive','invalid','revoked','expired')),

  timezone text default 'Asia/Kolkata',
  language_code text default 'en',

  last_seen_at timestamptz,
  token_refreshed_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,user_id,device_identifier),
  unique (push_token)
);

create index if not exists notification_user_devices_user_idx
  on public.notification_user_devices (
    organization_id,
    user_id,
    status
  );

-- ============================================================
-- 6. USER PREFERENCES
-- ============================================================

create table if not exists public.notification_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  category_code text not null,
  channel_code text not null references public.notification_channels(code) on delete cascade,

  preference_status text not null default 'enabled'
    check (preference_status in ('enabled','disabled','digest_only','critical_only')),

  minimum_severity text not null default 'info'
    check (minimum_severity in ('info','success','warning','error','critical')),

  quiet_hours_enabled boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,
  quiet_hours_timezone text default 'Asia/Kolkata',

  allow_weekends boolean not null default true,

  digest_frequency text
    check (
      digest_frequency is null
      or digest_frequency in ('hourly','daily','weekly')
    ),

  digest_time time,
  digest_day_of_week integer
    check (
      digest_day_of_week is null
      or digest_day_of_week between 0 and 6
    ),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    organization_id,
    user_id,
    category_code,
    channel_code
  )
);

create index if not exists notification_preferences_lookup_idx
  on public.notification_preferences (
    organization_id,
    user_id,
    category_code,
    channel_code
  );

-- ============================================================
-- 7. ROLE / TEAM SUBSCRIPTIONS
-- ============================================================

create table if not exists public.notification_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  subscriber_type text not null
    check (subscriber_type in ('user','role','team','organization')),

  subscriber_user_id uuid references auth.users(id) on delete cascade,
  subscriber_role_id uuid,
  subscriber_team_id uuid references public.assignment_teams(id) on delete cascade,

  event_name text not null,
  category_code text,

  channel_codes text[] not null default array['in_app'],

  filter_expression jsonb not null default '{}',
  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists notification_subscriptions_event_idx
  on public.notification_subscriptions (
    organization_id,
    event_name,
    status
  );

-- ============================================================
-- 8. NOTIFICATION JOBS
-- ============================================================

create table if not exists public.notification_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  category_id uuid references public.notification_categories(id) on delete set null,
  template_id uuid references public.notification_templates(id) on delete set null,

  source_module text,
  source_type text,
  source_id uuid,
  source_reference text,

  event_name text,
  idempotency_key text,
  correlation_id text,
  trace_id text,

  title text,
  body text,
  short_body text,

  rendered_title text,
  rendered_body text,
  rendered_short_body text,

  variables jsonb not null default '{}',
  actions jsonb not null default '[]',

  deep_link text,
  image_url text,

  severity text not null default 'info'
    check (severity in ('info','success','warning','error','critical')),

  priority integer not null default 100,

  status text not null default 'queued'
    check (
      status in (
        'draft',
        'pending',
        'queued',
        'processing',
        'scheduled',
        'partially_delivered',
        'delivered',
        'failed',
        'cancelled',
        'expired'
      )
    ),

  scheduled_at timestamptz,
  expires_at timestamptz,

  recipient_count integer not null default 0,
  delivered_count integer not null default 0,
  read_count integer not null default 0,
  failed_count integer not null default 0,
  suppressed_count integer not null default 0,

  attempts integer not null default 0,
  maximum_attempts integer not null default 5,
  next_retry_at timestamptz,

  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists notification_jobs_idempotency_idx
  on public.notification_jobs (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists notification_jobs_queue_idx
  on public.notification_jobs (
    status,
    coalesce(scheduled_at,created_at),
    priority,
    created_at
  )
  where status in ('pending','queued','scheduled','failed');

-- ============================================================
-- 9. NOTIFICATION RECIPIENTS
-- ============================================================

create table if not exists public.notification_recipients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  notification_job_id uuid not null references public.notification_jobs(id) on delete cascade,

  recipient_type text not null
    check (recipient_type in ('user','role','team','organization','lead','endpoint')),

  user_id uuid references auth.users(id) on delete cascade,
  role_id uuid,
  team_id uuid references public.assignment_teams(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,

  endpoint_type text,
  endpoint_value text,

  language_code text default 'en',
  timezone text default 'Asia/Kolkata',

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'eligible',
        'suppressed',
        'queued',
        'delivered',
        'read',
        'failed',
        'cancelled',
        'expired'
      )
    ),

  suppression_reason text,

  delivered_at timestamptz,
  read_at timestamptz,
  dismissed_at timestamptz,
  failed_at timestamptz,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists notification_recipients_job_idx
  on public.notification_recipients (
    notification_job_id,
    status
  );

create index if not exists notification_recipients_user_idx
  on public.notification_recipients (
    organization_id,
    user_id,
    created_at desc
  );

-- ============================================================
-- 10. DELIVERY ATTEMPTS
-- ============================================================

create table if not exists public.notification_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  notification_job_id uuid not null references public.notification_jobs(id) on delete cascade,
  notification_recipient_id uuid not null references public.notification_recipients(id) on delete cascade,

  channel_code text not null references public.notification_channels(code) on delete restrict,

  communication_message_job_id uuid references public.communication_message_jobs(id) on delete set null,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'queued',
        'sending',
        'sent',
        'delivered',
        'read',
        'failed',
        'suppressed',
        'cancelled',
        'expired'
      )
    ),

  attempt_number integer not null default 1,

  provider_reference text,
  provider_status text,
  provider_response jsonb not null default '{}',

  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  failed_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    notification_recipient_id,
    channel_code,
    attempt_number
  )
);

create index if not exists notification_delivery_attempts_queue_idx
  on public.notification_delivery_attempts (
    status,
    channel_code,
    created_at
  )
  where status in ('pending','queued','failed');

-- ============================================================
-- 11. IN-APP INBOX
-- ============================================================

create table if not exists public.notification_inbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  notification_job_id uuid not null references public.notification_jobs(id) on delete cascade,
  notification_recipient_id uuid not null references public.notification_recipients(id) on delete cascade,

  title text not null,
  body text not null,
  short_body text,

  category_code text,
  severity text not null default 'info',
  priority integer not null default 100,

  deep_link text,
  image_url text,
  actions jsonb not null default '[]',

  status text not null default 'unread'
    check (status in ('unread','read','dismissed','archived')),

  read_at timestamptz,
  dismissed_at timestamptz,
  archived_at timestamptz,

  expires_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (notification_recipient_id)
);

create index if not exists notification_inbox_user_status_idx
  on public.notification_inbox (
    organization_id,
    user_id,
    status,
    created_at desc
  );

-- ============================================================
-- 12. DIGEST CONFIGURATIONS
-- ============================================================

create table if not exists public.notification_digest_configs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,

  digest_name text not null,

  frequency text not null
    check (frequency in ('hourly','daily','weekly')),

  channel_code text not null references public.notification_channels(code) on delete restrict,

  category_codes text[] not null default '{}',

  send_time time,
  day_of_week integer
    check (day_of_week is null or day_of_week between 0 and 6),

  timezone text not null default 'Asia/Kolkata',

  status text not null default 'active'
    check (status in ('active','paused','inactive','archived')),

  next_run_at timestamptz,
  last_run_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,user_id,digest_name)
);

create index if not exists notification_digest_configs_due_idx
  on public.notification_digest_configs (
    status,
    next_run_at
  )
  where status = 'active';

-- ============================================================
-- 13. DIGEST ITEMS
-- ============================================================

create table if not exists public.notification_digest_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  digest_config_id uuid not null references public.notification_digest_configs(id) on delete cascade,

  notification_job_id uuid not null references public.notification_jobs(id) on delete cascade,
  notification_recipient_id uuid not null references public.notification_recipients(id) on delete cascade,

  status text not null default 'pending'
    check (status in ('pending','included','sent','removed','expired')),

  included_at timestamptz,
  sent_at timestamptz,

  created_at timestamptz not null default now(),

  unique (
    digest_config_id,
    notification_recipient_id
  )
);

-- ============================================================
-- 14. ESCALATION POLICIES
-- ============================================================

create table if not exists public.notification_escalation_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  policy_code text not null,
  policy_name text not null,

  category_code text,
  event_name text,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  trigger_after_minutes integer not null default 15,
  maximum_escalations integer not null default 3,

  require_unread boolean not null default true,
  require_undelivered boolean not null default false,

  escalation_channels text[] not null default array['in_app','push'],

  escalate_to_type text not null default 'manager'
    check (
      escalate_to_type in (
        'manager',
        'team_leader',
        'role',
        'user',
        'team',
        'organization'
      )
    ),

  escalate_to_user_id uuid references auth.users(id) on delete set null,
  escalate_to_team_id uuid references public.assignment_teams(id) on delete set null,
  escalate_to_role_id uuid,

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,policy_code)
);

-- ============================================================
-- 15. ESCALATION QUEUE
-- ============================================================

create table if not exists public.notification_escalation_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  notification_job_id uuid not null references public.notification_jobs(id) on delete cascade,
  notification_recipient_id uuid references public.notification_recipients(id) on delete cascade,
  escalation_policy_id uuid not null references public.notification_escalation_policies(id) on delete cascade,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'processing',
        'completed',
        'cancelled',
        'failed',
        'expired'
      )
    ),

  escalation_level integer not null default 1,
  scheduled_at timestamptz not null,
  processed_at timestamptz,

  result_data jsonb not null default '{}',
  error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists notification_escalation_queue_due_idx
  on public.notification_escalation_queue (
    status,
    scheduled_at
  )
  where status = 'pending';

-- ============================================================
-- 16. RETRY QUEUE
-- ============================================================

create table if not exists public.notification_retry_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  notification_job_id uuid not null references public.notification_jobs(id) on delete cascade,
  delivery_attempt_id uuid references public.notification_delivery_attempts(id) on delete cascade,

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
    check (retry_strategy in ('fixed','linear','exponential','custom')),

  retry_delay_seconds integer not null default 60,
  scheduled_at timestamptz not null default now(),

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

create index if not exists notification_retry_queue_due_idx
  on public.notification_retry_queue (
    status,
    scheduled_at
  )
  where status = 'pending';

-- ============================================================
-- 17. EVENT OUTBOX
-- ============================================================

create table if not exists public.notification_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  notification_job_id uuid references public.notification_jobs(id) on delete set null,
  notification_recipient_id uuid references public.notification_recipients(id) on delete set null,

  event_name text not null,

  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'workflow_engine',
        'automation_engine',
        'n8n',
        'webhook',
        'analytics',
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

create unique index if not exists notification_event_outbox_idempotency_idx
  on public.notification_event_outbox (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists notification_event_outbox_queue_idx
  on public.notification_event_outbox (
    status,
    available_at,
    priority,
    created_at
  )
  where status in ('pending','failed');

-- ============================================================
-- 18. LOGS
-- ============================================================

create table if not exists public.notification_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  notification_job_id uuid references public.notification_jobs(id) on delete set null,
  notification_recipient_id uuid references public.notification_recipients(id) on delete set null,
  delivery_attempt_id uuid references public.notification_delivery_attempts(id) on delete set null,

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

create index if not exists notification_logs_org_created_idx
  on public.notification_logs (
    organization_id,
    created_at desc
  );

-- ============================================================
-- 19. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'notification_categories',
    'notification_templates',
    'notification_user_devices',
    'notification_preferences',
    'notification_subscriptions',
    'notification_jobs',
    'notification_delivery_attempts',
    'notification_inbox',
    'notification_digest_configs',
    'notification_escalation_policies',
    'notification_escalation_queue',
    'notification_retry_queue',
    'notification_event_outbox'
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
-- 20. SEVERITY RANK HELPER
-- ============================================================

create or replace function public.notification_severity_rank(
  requested_severity text
)
returns integer
language sql
immutable
security definer
set search_path = ''
as $$
  select case requested_severity
    when 'critical' then 5
    when 'error' then 4
    when 'warning' then 3
    when 'success' then 2
    else 1
  end;
$$;

revoke all
on function public.notification_severity_rank(text)
from public;

grant execute
on function public.notification_severity_rank(text)
to authenticated,service_role;

-- ============================================================
-- 21. CHECK USER NOTIFICATION ELIGIBILITY
-- ============================================================

create or replace function public.check_notification_eligibility(
  requested_organization_id uuid,
  requested_user_id uuid,
  requested_category_code text,
  requested_channel_code text,
  requested_severity text default 'info',
  requested_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  preference_record public.notification_preferences;
  local_timestamp timestamp;
  local_time time;
  local_day integer;
  in_quiet_hours boolean := false;
  severity_allowed boolean := true;
begin
  select *
  into preference_record
  from public.notification_preferences p
  where p.organization_id = requested_organization_id
    and p.user_id = requested_user_id
    and p.category_code in (requested_category_code,'*')
    and p.channel_code = requested_channel_code
  order by
    case when p.category_code = requested_category_code then 0 else 1 end
  limit 1;

  if found then
    if preference_record.preference_status = 'disabled' then
      return jsonb_build_object(
        'eligible',
        false,
        'reason',
        'Notification channel disabled by user',
        'preference_status',
        preference_record.preference_status
      );
    end if;

    severity_allowed :=
      public.notification_severity_rank(requested_severity)
      >= public.notification_severity_rank(
        preference_record.minimum_severity
      );

    if not severity_allowed then
      return jsonb_build_object(
        'eligible',
        false,
        'reason',
        'Severity below user preference threshold',
        'preference_status',
        preference_record.preference_status
      );
    end if;

    if preference_record.preference_status = 'critical_only'
      and requested_severity <> 'critical' then
      return jsonb_build_object(
        'eligible',
        false,
        'reason',
        'User accepts only critical notifications',
        'preference_status',
        preference_record.preference_status
      );
    end if;

    if preference_record.quiet_hours_enabled
      and preference_record.quiet_hours_start is not null
      and preference_record.quiet_hours_end is not null then

      local_timestamp :=
        requested_at at time zone
          coalesce(
            preference_record.quiet_hours_timezone,
            'Asia/Kolkata'
          );

      local_time := local_timestamp::time;
      local_day := extract(dow from local_timestamp)::integer;

      if not preference_record.allow_weekends
        and local_day in (0,6)
        and requested_severity <> 'critical' then
        return jsonb_build_object(
          'eligible',
          false,
          'reason',
          'Weekend notifications disabled',
          'preference_status',
          preference_record.preference_status
        );
      end if;

      if preference_record.quiet_hours_start
        < preference_record.quiet_hours_end then
        in_quiet_hours :=
          local_time >= preference_record.quiet_hours_start
          and local_time < preference_record.quiet_hours_end;
      else
        in_quiet_hours :=
          local_time >= preference_record.quiet_hours_start
          or local_time < preference_record.quiet_hours_end;
      end if;

      if in_quiet_hours
        and requested_severity <> 'critical' then
        return jsonb_build_object(
          'eligible',
          false,
          'reason',
          'Notification blocked during quiet hours',
          'preference_status',
          preference_record.preference_status
        );
      end if;
    end if;

    if preference_record.preference_status = 'digest_only'
      and requested_severity <> 'critical' then
      return jsonb_build_object(
        'eligible',
        false,
        'digest_only',
        true,
        'reason',
        'Notification should be included in digest',
        'preference_status',
        preference_record.preference_status
      );
    end if;
  end if;

  return jsonb_build_object(
    'eligible',
    true,
    'reason',
    null,
    'preference_status',
    coalesce(preference_record.preference_status,'default')
  );
end;
$$;

revoke all
on function public.check_notification_eligibility(
  uuid,uuid,text,text,text,timestamptz
)
from public;

grant execute
on function public.check_notification_eligibility(
  uuid,uuid,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 22. CREATE NOTIFICATION JOB
-- ============================================================

create or replace function public.create_notification_job(
  requested_organization_id uuid,
  requested_category_code text,
  requested_title text,
  requested_body text,
  requested_recipient_user_ids uuid[] default '{}',
  requested_channel_codes text[] default array['in_app'],
  requested_template_id uuid default null,
  requested_variables jsonb default '{}'::jsonb,
  requested_actions jsonb default '[]'::jsonb,
  requested_deep_link text default null,
  requested_image_url text default null,
  requested_severity text default 'info',
  requested_priority integer default 100,
  requested_event_name text default null,
  requested_source_module text default null,
  requested_source_type text default null,
  requested_source_id uuid default null,
  requested_source_reference text default null,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_scheduled_at timestamptz default null,
  requested_expires_at timestamptz default null
)
returns public.notification_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  category_record public.notification_categories;
  template_record public.notification_templates;
  existing_job public.notification_jobs;
  created_job public.notification_jobs;
  user_value uuid;
  category_channels text[];
  final_channels text[];
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'notification.send'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_job
    from public.notification_jobs j
    where j.organization_id = requested_organization_id
      and j.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_job;
    end if;
  end if;

  select *
  into category_record
  from public.notification_categories c
  where c.category_code = requested_category_code
    and c.status = 'active'
    and (
      c.organization_id = requested_organization_id
      or c.organization_id is null
    )
  order by
    case when c.organization_id = requested_organization_id then 0 else 1 end
  limit 1;

  if not found then
    raise exception 'Notification category not found';
  end if;

  category_channels := category_record.default_channels;
  final_channels :=
    case
      when cardinality(requested_channel_codes) = 0
        then category_channels
      else requested_channel_codes
    end;

  if requested_template_id is not null then
    select *
    into template_record
    from public.notification_templates t
    where t.id = requested_template_id
      and t.status = 'active'
      and (
        t.organization_id = requested_organization_id
        or t.organization_id is null
      );

    if not found then
      raise exception 'Active notification template not found';
    end if;
  end if;

  insert into public.notification_jobs (
    organization_id,
    category_id,
    template_id,
    source_module,
    source_type,
    source_id,
    source_reference,
    event_name,
    idempotency_key,
    correlation_id,
    trace_id,
    title,
    body,
    short_body,
    rendered_title,
    rendered_body,
    rendered_short_body,
    variables,
    actions,
    deep_link,
    image_url,
    severity,
    priority,
    status,
    scheduled_at,
    expires_at,
    recipient_count,
    created_by,
    updated_by,
    metadata
  )
  values (
    requested_organization_id,
    category_record.id,
    requested_template_id,
    requested_source_module,
    requested_source_type,
    requested_source_id,
    requested_source_reference,
    requested_event_name,
    requested_idempotency_key,
    coalesce(requested_correlation_id,gen_random_uuid()::text),
    coalesce(requested_trace_id,gen_random_uuid()::text),
    coalesce(requested_title,template_record.title_template),
    coalesce(requested_body,template_record.body_template),
    template_record.short_body_template,
    coalesce(requested_title,template_record.title_template),
    coalesce(requested_body,template_record.body_template),
    template_record.short_body_template,
    coalesce(requested_variables,'{}'::jsonb),
    coalesce(requested_actions,template_record.action_schema,'[]'::jsonb),
    coalesce(requested_deep_link,template_record.deep_link_template),
    coalesce(requested_image_url,template_record.image_url_template),
    coalesce(requested_severity,category_record.severity),
    coalesce(requested_priority,category_record.default_priority),
    case
      when requested_scheduled_at is not null
        and requested_scheduled_at > now()
        then 'scheduled'
      else 'queued'
    end,
    requested_scheduled_at,
    requested_expires_at,
    cardinality(requested_recipient_user_ids),
    auth.uid(),
    auth.uid(),
    jsonb_build_object(
      'channel_codes',
      final_channels,
      'category_code',
      requested_category_code
    )
  )
  returning * into created_job;

  foreach user_value in array requested_recipient_user_ids
  loop
    insert into public.notification_recipients (
      organization_id,
      notification_job_id,
      recipient_type,
      user_id,
      status
    )
    values (
      requested_organization_id,
      created_job.id,
      'user',
      user_value,
      'pending'
    );
  end loop;

  insert into public.notification_logs (
    organization_id,
    notification_job_id,
    log_level,
    event_name,
    message,
    log_data,
    correlation_id,
    trace_id
  )
  values (
    requested_organization_id,
    created_job.id,
    'info',
    'notification.job.created',
    'Notification job created',
    jsonb_build_object(
      'recipient_count',
      created_job.recipient_count,
      'channels',
      final_channels
    ),
    created_job.correlation_id,
    created_job.trace_id
  );

  return created_job;
end;
$$;

revoke all
on function public.create_notification_job(
  uuid,text,text,text,uuid[],text[],uuid,jsonb,jsonb,text,text,text,
  integer,text,text,text,uuid,text,text,text,text,timestamptz,timestamptz
)
from public;

grant execute
on function public.create_notification_job(
  uuid,text,text,text,uuid[],text[],uuid,jsonb,jsonb,text,text,text,
  integer,text,text,text,uuid,text,text,text,text,timestamptz,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 23. EXPAND RECIPIENT CHANNELS
-- ============================================================

create or replace function public.expand_notification_recipients(
  requested_notification_job_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.notification_jobs;
  recipient_record public.notification_recipients;
  channel_value text;
  channels_value text[];
  eligibility jsonb;
  inserted_count integer := 0;
  category_code_value text;
begin
  select *
  into job_record
  from public.notification_jobs
  where id = requested_notification_job_id
  for update;

  if not found then
    raise exception 'Notification job not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      job_record.organization_id,
      'notification.send'
    ) then
    raise exception 'Permission denied';
  end if;

  channels_value :=
    coalesce(
      array(
        select jsonb_array_elements_text(
          job_record.metadata -> 'channel_codes'
        )
      ),
      array['in_app']
    );

  select c.category_code
  into category_code_value
  from public.notification_categories c
  where c.id = job_record.category_id;

  for recipient_record in
    select *
    from public.notification_recipients r
    where r.notification_job_id = job_record.id
      and r.status = 'pending'
      and r.user_id is not null
  loop
    foreach channel_value in array channels_value
    loop
      eligibility := public.check_notification_eligibility(
        job_record.organization_id,
        recipient_record.user_id,
        category_code_value,
        channel_value,
        job_record.severity,
        now()
      );

      if coalesce((eligibility->>'eligible')::boolean,false) then
        insert into public.notification_delivery_attempts (
          organization_id,
          notification_job_id,
          notification_recipient_id,
          channel_code,
          status,
          attempt_number
        )
        values (
          job_record.organization_id,
          job_record.id,
          recipient_record.id,
          channel_value,
          'queued',
          1
        )
        on conflict (
          notification_recipient_id,
          channel_code,
          attempt_number
        )
        do nothing;

        inserted_count := inserted_count + 1;

        if channel_value = 'in_app' then
          insert into public.notification_inbox (
            organization_id,
            user_id,
            notification_job_id,
            notification_recipient_id,
            title,
            body,
            short_body,
            category_code,
            severity,
            priority,
            deep_link,
            image_url,
            actions,
            expires_at,
            metadata
          )
          values (
            job_record.organization_id,
            recipient_record.user_id,
            job_record.id,
            recipient_record.id,
            coalesce(job_record.rendered_title,job_record.title,'Notification'),
            coalesce(job_record.rendered_body,job_record.body,''),
            job_record.rendered_short_body,
            category_code_value,
            job_record.severity,
            job_record.priority,
            job_record.deep_link,
            job_record.image_url,
            job_record.actions,
            job_record.expires_at,
            jsonb_build_object(
              'source_module',
              job_record.source_module,
              'source_type',
              job_record.source_type,
              'source_id',
              job_record.source_id
            )
          )
          on conflict (notification_recipient_id)
          do nothing;

          update public.notification_delivery_attempts
          set
            status = 'delivered',
            delivered_at = now(),
            updated_at = now()
          where notification_recipient_id = recipient_record.id
            and channel_code = 'in_app'
            and attempt_number = 1;
        end if;
      else
        if coalesce((eligibility->>'digest_only')::boolean,false) then
          insert into public.notification_digest_items (
            organization_id,
            digest_config_id,
            notification_job_id,
            notification_recipient_id,
            status
          )
          select
            job_record.organization_id,
            config.id,
            job_record.id,
            recipient_record.id,
            'pending'
          from public.notification_digest_configs config
          where config.organization_id = job_record.organization_id
            and config.user_id = recipient_record.user_id
            and config.status = 'active'
            and (
              cardinality(config.category_codes) = 0
              or category_code_value = any(config.category_codes)
            )
          on conflict (
            digest_config_id,
            notification_recipient_id
          )
          do nothing;
        end if;

        update public.notification_recipients
        set
          status = 'suppressed',
          suppression_reason = eligibility->>'reason'
        where id = recipient_record.id;
      end if;
    end loop;

    if exists (
      select 1
      from public.notification_delivery_attempts a
      where a.notification_recipient_id = recipient_record.id
        and a.status in ('queued','sent','delivered','read')
    ) then
      update public.notification_recipients
      set status = 'queued'
      where id = recipient_record.id;
    end if;
  end loop;

  update public.notification_jobs
  set
    status = 'processing',
    started_at = coalesce(started_at,now()),
    suppressed_count = (
      select count(*)
      from public.notification_recipients r
      where r.notification_job_id = job_record.id
        and r.status = 'suppressed'
    ),
    updated_at = now()
  where id = job_record.id;

  return inserted_count;
end;
$$;

revoke all
on function public.expand_notification_recipients(uuid)
from public;

grant execute
on function public.expand_notification_recipients(uuid)
to authenticated,service_role;

-- ============================================================
-- 24. CLAIM DELIVERY ATTEMPT
-- ============================================================

create or replace function public.claim_notification_delivery_attempt(
  requested_worker_id text,
  requested_channel_code text default null,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.notification_delivery_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.notification_delivery_attempts;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim notification deliveries';
  end if;

  select *
  into target_attempt
  from public.notification_delivery_attempts a
  where a.status in ('pending','queued','failed')
    and (
      requested_channel_code is null
      or a.channel_code = requested_channel_code
    )
    and (
      requested_organization_id is null
      or a.organization_id = requested_organization_id
    )
  order by a.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.notification_delivery_attempts
  set
    status = 'sending',
    provider_response =
      provider_response || jsonb_build_object(
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
  where id = target_attempt.id
  returning * into target_attempt;

  return target_attempt;
end;
$$;

revoke all
on function public.claim_notification_delivery_attempt(
  text,text,uuid,integer
)
from public;

grant execute
on function public.claim_notification_delivery_attempt(
  text,text,uuid,integer
)
to service_role;

-- ============================================================
-- 25. HANDOFF TO COMMUNICATION ENGINE
-- ============================================================

create or replace function public.handoff_notification_to_communication(
  requested_delivery_attempt_id uuid
)
returns public.communication_message_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt_record public.notification_delivery_attempts;
  recipient_record public.notification_recipients;
  job_record public.notification_jobs;
  address_value text;
  message_job public.communication_message_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may hand off notifications';
  end if;

  select *
  into attempt_record
  from public.notification_delivery_attempts
  where id = requested_delivery_attempt_id
  for update;

  if not found then
    raise exception 'Notification delivery attempt not found';
  end if;

  if attempt_record.channel_code = 'in_app' then
    raise exception 'In-app notifications do not require communication handoff';
  end if;

  select *
  into recipient_record
  from public.notification_recipients
  where id = attempt_record.notification_recipient_id;

  select *
  into job_record
  from public.notification_jobs
  where id = attempt_record.notification_job_id;

  if recipient_record.endpoint_value is not null then
    address_value := recipient_record.endpoint_value;
  elsif recipient_record.user_id is not null then
    select
      case attempt_record.channel_code
        when 'email' then u.email
        else null
      end
    into address_value
    from auth.users u
    where u.id = recipient_record.user_id;
  end if;

  if address_value is null then
    raise exception
      'Recipient address is unavailable for channel %',
      attempt_record.channel_code;
  end if;

  message_job := public.create_communication_message(
    job_record.organization_id,
    attempt_record.channel_code,
    address_value,
    recipient_record.lead_id,
    null,
    null,
    job_record.rendered_title,
    job_record.rendered_body,
    job_record.variables,
    'transactional',
    'system',
    'notification:' || job_record.id::text,
    'notification-delivery:' || attempt_record.id::text,
    job_record.priority,
    null,
    null,
    null
  );

  update public.notification_delivery_attempts
  set
    communication_message_job_id = message_job.id,
    status =
      case
        when message_job.status = 'suppressed'
          then 'suppressed'
        else 'queued'
      end,
    provider_reference = message_job.id::text,
    updated_at = now()
  where id = attempt_record.id;

  return message_job;
end;
$$;

revoke all
on function public.handoff_notification_to_communication(uuid)
from public;

grant execute
on function public.handoff_notification_to_communication(uuid)
to service_role;

-- ============================================================
-- 26. UPDATE DELIVERY STATUS
-- ============================================================

create or replace function public.update_notification_delivery_status(
  requested_delivery_attempt_id uuid,
  requested_status text,
  requested_provider_reference text default null,
  requested_provider_status text default null,
  requested_provider_response jsonb default '{}'::jsonb,
  requested_error_code text default null,
  requested_error_message text default null,
  requested_error_data jsonb default '{}'::jsonb
)
returns public.notification_delivery_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt_record public.notification_delivery_attempts;
  recipient_record public.notification_recipients;
  job_record public.notification_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may update notification delivery';
  end if;

  if requested_status not in (
    'queued',
    'sending',
    'sent',
    'delivered',
    'read',
    'failed',
    'suppressed',
    'cancelled',
    'expired'
  ) then
    raise exception 'Unsupported notification delivery status';
  end if;

  update public.notification_delivery_attempts
  set
    status = requested_status,
    provider_reference =
      coalesce(requested_provider_reference,provider_reference),
    provider_status =
      coalesce(requested_provider_status,provider_status),
    provider_response =
      provider_response
      || coalesce(requested_provider_response,'{}'::jsonb),
    sent_at =
      case
        when requested_status = 'sent'
          then coalesce(sent_at,now())
        else sent_at
      end,
    delivered_at =
      case
        when requested_status = 'delivered'
          then coalesce(delivered_at,now())
        else delivered_at
      end,
    read_at =
      case
        when requested_status = 'read'
          then coalesce(read_at,now())
        else read_at
      end,
    failed_at =
      case
        when requested_status = 'failed'
          then coalesce(failed_at,now())
        else failed_at
      end,
    error_code = requested_error_code,
    error_message = requested_error_message,
    error_data = coalesce(requested_error_data,'{}'::jsonb),
    updated_at = now()
  where id = requested_delivery_attempt_id
  returning * into attempt_record;

  if not found then
    raise exception 'Notification delivery attempt not found';
  end if;

  select *
  into recipient_record
  from public.notification_recipients
  where id = attempt_record.notification_recipient_id
  for update;

  select *
  into job_record
  from public.notification_jobs
  where id = attempt_record.notification_job_id
  for update;

  if requested_status in ('delivered','read') then
    update public.notification_recipients
    set
      status = requested_status,
      delivered_at =
        case
          when requested_status = 'delivered'
            then coalesce(delivered_at,now())
          else delivered_at
        end,
      read_at =
        case
          when requested_status = 'read'
            then coalesce(read_at,now())
          else read_at
        end
    where id = recipient_record.id;
  elsif requested_status in ('failed','suppressed','cancelled','expired') then
    update public.notification_recipients
    set
      status = requested_status,
      failed_at =
        case
          when requested_status = 'failed'
            then now()
          else failed_at
        end
    where id = recipient_record.id;
  end if;

  update public.notification_jobs
  set
    delivered_count = (
      select count(*)
      from public.notification_recipients r
      where r.notification_job_id = job_record.id
        and r.status in ('delivered','read')
    ),
    read_count = (
      select count(*)
      from public.notification_recipients r
      where r.notification_job_id = job_record.id
        and r.status = 'read'
    ),
    failed_count = (
      select count(*)
      from public.notification_recipients r
      where r.notification_job_id = job_record.id
        and r.status = 'failed'
    ),
    suppressed_count = (
      select count(*)
      from public.notification_recipients r
      where r.notification_job_id = job_record.id
        and r.status = 'suppressed'
    ),
    status =
      case
        when not exists (
          select 1
          from public.notification_delivery_attempts a
          where a.notification_job_id = job_record.id
            and a.status in (
              'pending',
              'queued',
              'sending'
            )
        )
        and exists (
          select 1
          from public.notification_delivery_attempts a
          where a.notification_job_id = job_record.id
            and a.status in ('delivered','read')
        )
          then 'delivered'
        when not exists (
          select 1
          from public.notification_delivery_attempts a
          where a.notification_job_id = job_record.id
            and a.status in (
              'pending',
              'queued',
              'sending'
            )
        )
        and exists (
          select 1
          from public.notification_delivery_attempts a
          where a.notification_job_id = job_record.id
            and a.status = 'failed'
        )
          then 'partially_delivered'
        else status
      end,
    completed_at =
      case
        when not exists (
          select 1
          from public.notification_delivery_attempts a
          where a.notification_job_id = job_record.id
            and a.status in (
              'pending',
              'queued',
              'sending'
            )
        )
          then now()
        else completed_at
      end,
    updated_at = now()
  where id = job_record.id;

  return attempt_record;
end;
$$;

revoke all
on function public.update_notification_delivery_status(
  uuid,text,text,text,jsonb,text,text,jsonb
)
from public;

grant execute
on function public.update_notification_delivery_status(
  uuid,text,text,text,jsonb,text,text,jsonb
)
to service_role;

-- ============================================================
-- 27. MARK INBOX ITEM READ
-- ============================================================

create or replace function public.mark_notification_read(
  requested_inbox_id uuid
)
returns public.notification_inbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  inbox_record public.notification_inbox;
begin
  select *
  into inbox_record
  from public.notification_inbox
  where id = requested_inbox_id
  for update;

  if not found then
    raise exception 'Notification inbox item not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from inbox_record.user_id
    and not public.has_organization_permission(
      inbox_record.organization_id,
      'notification.mark_read'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.notification_inbox
  set
    status = 'read',
    read_at = coalesce(read_at,now()),
    updated_at = now()
  where id = inbox_record.id
  returning * into inbox_record;

  update public.notification_recipients
  set
    status = 'read',
    read_at = coalesce(read_at,now())
  where id = inbox_record.notification_recipient_id;

  update public.notification_delivery_attempts
  set
    status = 'read',
    read_at = coalesce(read_at,now()),
    updated_at = now()
  where notification_recipient_id =
      inbox_record.notification_recipient_id
    and channel_code = 'in_app';

  update public.notification_jobs
  set
    read_count = (
      select count(*)
      from public.notification_recipients r
      where r.notification_job_id =
        inbox_record.notification_job_id
        and r.status = 'read'
    ),
    updated_at = now()
  where id = inbox_record.notification_job_id;

  return inbox_record;
end;
$$;

revoke all
on function public.mark_notification_read(uuid)
from public;

grant execute
on function public.mark_notification_read(uuid)
to authenticated,service_role;

-- ============================================================
-- 28. MARK ALL USER NOTIFICATIONS READ
-- ============================================================

create or replace function public.mark_all_notifications_read(
  requested_organization_id uuid,
  requested_user_id uuid default auth.uid()
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer := 0;
begin
  if auth.role() <> 'service_role'
    and auth.uid() is distinct from requested_user_id
    and not public.has_organization_permission(
      requested_organization_id,
      'notification.mark_read'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.notification_inbox
  set
    status = 'read',
    read_at = coalesce(read_at,now()),
    updated_at = now()
  where organization_id = requested_organization_id
    and user_id = requested_user_id
    and status = 'unread';

  get diagnostics changed_count = row_count;

  update public.notification_recipients r
  set
    status = 'read',
    read_at = coalesce(read_at,now())
  where r.organization_id = requested_organization_id
    and r.user_id = requested_user_id
    and exists (
      select 1
      from public.notification_inbox i
      where i.notification_recipient_id = r.id
        and i.status = 'read'
    );

  return changed_count;
end;
$$;

revoke all
on function public.mark_all_notifications_read(uuid,uuid)
from public;

grant execute
on function public.mark_all_notifications_read(uuid,uuid)
to authenticated,service_role;

-- ============================================================
-- 29. PUBLISH NOTIFICATION EVENT
-- ============================================================

create or replace function public.publish_notification_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_notification_job_id uuid default null,
  requested_notification_recipient_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.notification_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.notification_event_outbox;
  created_event public.notification_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.notification_event_outbox e
    where e.organization_id = requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.notification_event_outbox (
    organization_id,
    notification_job_id,
    notification_recipient_id,
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
    requested_notification_job_id,
    requested_notification_recipient_id,
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
on function public.publish_notification_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_notification_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 30. JOB STATUS EVENT TRIGGER
-- ============================================================

create or replace function public.emit_notification_job_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload_data jsonb;
begin
  if tg_op = 'UPDATE'
    and new.status is not distinct from old.status
    and new.delivered_count is not distinct from old.delivered_count
    and new.read_count is not distinct from old.read_count then
    return new;
  end if;

  payload_data := jsonb_build_object(
    'organization_id',
    new.organization_id,
    'notification_job_id',
    new.id,
    'category_id',
    new.category_id,
    'event_name',
    new.event_name,
    'status',
    new.status,
    'severity',
    new.severity,
    'priority',
    new.priority,
    'recipient_count',
    new.recipient_count,
    'delivered_count',
    new.delivered_count,
    'read_count',
    new.read_count,
    'failed_count',
    new.failed_count,
    'suppressed_count',
    new.suppressed_count,
    'source_module',
    new.source_module,
    'source_type',
    new.source_type,
    'source_id',
    new.source_id
  );

  perform public.publish_notification_event(
    new.organization_id,
    'notification.job.' || new.status,
    payload_data,
    'automation_engine',
    new.id,
    null,
    case
      when new.status = 'failed' then 10
      else 50
    end,
    'notification-job:'
      || new.id::text
      || ':'
      || new.status,
    new.correlation_id,
    new.trace_id,
    now()
  );

  perform public.publish_notification_event(
    new.organization_id,
    'notification.job.' || new.status,
    payload_data,
    'n8n',
    new.id,
    null,
    50,
    'notification-n8n:'
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

drop trigger if exists notification_jobs_emit_events
on public.notification_jobs;

create trigger notification_jobs_emit_events
after insert or update
on public.notification_jobs
for each row
execute function public.emit_notification_job_events();

-- ============================================================
-- 31. CLAIM / COMPLETE EVENT OUTBOX
-- ============================================================

create or replace function public.claim_notification_event(
  requested_worker_id text,
  requested_destination text default null,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.notification_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_event public.notification_event_outbox;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim notification events';
  end if;

  select *
  into target_event
  from public.notification_event_outbox e
  where e.status in ('pending','failed')
    and e.available_at <= now()
    and e.delivery_attempts < e.maximum_attempts
    and (
      requested_destination is null
      or e.destination = requested_destination
    )
    and (
      requested_organization_id is null
      or e.organization_id = requested_organization_id
    )
  order by
    e.priority,
    e.available_at,
    e.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.notification_event_outbox
  set
    status = 'claimed',
    claimed_at = now(),
    claimed_by = requested_worker_id,
    lock_token = gen_random_uuid()::text,
    lock_expires_at = now() + make_interval(
      secs => greatest(requested_lock_seconds,1)
    ),
    delivery_attempts = delivery_attempts + 1,
    updated_at = now()
  where id = target_event.id
  returning * into target_event;

  return target_event;
end;
$$;

create or replace function public.complete_notification_event(
  requested_event_id uuid,
  requested_lock_token text
)
returns public.notification_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_event public.notification_event_outbox;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete notification events';
  end if;

  select *
  into target_event
  from public.notification_event_outbox
  where id = requested_event_id
  for update;

  if not found then
    raise exception 'Notification event not found';
  end if;

  if target_event.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid notification event lock token';
  end if;

  update public.notification_event_outbox
  set
    status = 'delivered',
    delivered_at = now(),
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where id = requested_event_id
  returning * into target_event;

  return target_event;
end;
$$;

revoke all
on function public.claim_notification_event(
  text,text,uuid,integer
)
from public;

revoke all
on function public.complete_notification_event(uuid,text)
from public;

grant execute
on function public.claim_notification_event(
  text,text,uuid,integer
)
to service_role;

grant execute
on function public.complete_notification_event(uuid,text)
to service_role;

-- ============================================================
-- 32. ESCALATION PROCESSOR
-- ============================================================

create or replace function public.process_notification_escalations(
  requested_organization_id uuid default null,
  requested_limit integer default 100
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  queue_record record;
  processed_count integer := 0;
  recipient_users uuid[] := '{}';
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may process escalations';
  end if;

  for queue_record in
    select
      q.*,
      p.escalate_to_type,
      p.escalate_to_user_id,
      p.escalate_to_team_id,
      p.escalation_channels
    from public.notification_escalation_queue q
    join public.notification_escalation_policies p
      on p.id = q.escalation_policy_id
    where q.status = 'pending'
      and q.scheduled_at <= now()
      and p.status = 'active'
      and (
        requested_organization_id is null
        or q.organization_id = requested_organization_id
      )
    order by q.scheduled_at
    limit greatest(requested_limit,1)
    for update skip locked
  loop
    recipient_users := '{}';

    if queue_record.escalate_to_type = 'user'
      and queue_record.escalate_to_user_id is not null then
      recipient_users :=
        array[queue_record.escalate_to_user_id];

    elsif queue_record.escalate_to_type in ('team','team_leader')
      and queue_record.escalate_to_team_id is not null then
      select coalesce(array_agg(p.user_id),'{}'::uuid[])
      into recipient_users
      from public.assignment_team_members m
      join public.assignment_agent_profiles p
        on p.id = m.agent_profile_id
      where m.team_id = queue_record.escalate_to_team_id
        and m.status = 'active'
        and (
          queue_record.escalate_to_type = 'team'
          or m.role in ('leader','manager')
        );
    end if;

    if cardinality(recipient_users) > 0 then
      perform public.create_notification_job(
        queue_record.organization_id,
        'system_alert',
        'Escalation Required',
        'A notification requires escalation.',
        recipient_users,
        queue_record.escalation_channels,
        null,
        jsonb_build_object(
          'source_notification_job_id',
          queue_record.notification_job_id,
          'escalation_level',
          queue_record.escalation_level
        ),
        '[]'::jsonb,
        null,
        null,
        'critical',
        5,
        'notification.escalated',
        'notification',
        'notification_job',
        queue_record.notification_job_id,
        queue_record.id::text,
        'notification-escalation:'
          || queue_record.id::text,
        queue_record.id::text,
        null,
        null,
        null
      );
    end if;

    update public.notification_escalation_queue
    set
      status = 'completed',
      processed_at = now(),
      result_data = jsonb_build_object(
        'recipient_users',
        recipient_users
      ),
      updated_at = now()
    where id = queue_record.id;

    processed_count := processed_count + 1;
  end loop;

  return processed_count;
end;
$$;

revoke all
on function public.process_notification_escalations(
  uuid,integer
)
from public;

grant execute
on function public.process_notification_escalations(
  uuid,integer
)
to service_role;

-- ============================================================
-- 33. RELEASE EXPIRED LOCKS
-- ============================================================

create or replace function public.release_expired_notification_locks()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  retry_count integer := 0;
  event_count integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may release notification locks';
  end if;

  update public.notification_retry_queue
  set
    status = 'pending',
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    scheduled_at = now(),
    updated_at = now()
  where status in ('claimed','processing')
    and lock_expires_at is not null
    and lock_expires_at <= now();

  get diagnostics retry_count = row_count;

  update public.notification_event_outbox
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

  get diagnostics event_count = row_count;

  return jsonb_build_object(
    'retry_locks_released',
    retry_count,
    'event_locks_released',
    event_count,
    'released_at',
    now()
  );
end;
$$;

revoke all
on function public.release_expired_notification_locks()
from public;

grant execute
on function public.release_expired_notification_locks()
to service_role;

-- ============================================================
-- 34. ANALYTICS VIEWS
-- ============================================================

create or replace view public.notification_user_inbox_summary
with (security_invoker = true)
as
select
  organization_id,
  user_id,

  count(*) as total_notifications,

  count(*) filter (
    where status = 'unread'
  ) as unread_count,

  count(*) filter (
    where status = 'read'
  ) as read_count,

  count(*) filter (
    where severity = 'critical'
      and status = 'unread'
  ) as unread_critical_count,

  max(created_at) as latest_notification_at

from public.notification_inbox
group by
  organization_id,
  user_id;

create or replace view public.notification_delivery_dashboard
with (security_invoker = true)
as
select
  j.organization_id,
  a.channel_code,
  date_trunc('day',j.created_at)::date as notification_date,

  count(distinct j.id) as total_jobs,
  count(a.id) as total_attempts,

  count(a.id) filter (
    where a.status = 'sent'
  ) as sent_count,

  count(a.id) filter (
    where a.status = 'delivered'
  ) as delivered_count,

  count(a.id) filter (
    where a.status = 'read'
  ) as read_count,

  count(a.id) filter (
    where a.status = 'failed'
  ) as failed_count,

  count(a.id) filter (
    where a.status = 'suppressed'
  ) as suppressed_count,

  round(
    (
      count(a.id) filter (
        where a.status in ('delivered','read')
      )::numeric
      / nullif(count(a.id),0)
    ) * 100,
    2
  ) as delivery_rate,

  round(
    (
      count(a.id) filter (
        where a.status = 'read'
      )::numeric
      / nullif(
        count(a.id) filter (
          where a.status in ('delivered','read')
        ),
        0
      )
    ) * 100,
    2
  ) as read_rate

from public.notification_jobs j
left join public.notification_delivery_attempts a
  on a.notification_job_id = j.id
group by
  j.organization_id,
  a.channel_code,
  date_trunc('day',j.created_at)::date;

create or replace view public.notification_category_dashboard
with (security_invoker = true)
as
select
  j.organization_id,
  c.category_code,
  c.category_name,

  count(j.id) as total_jobs,

  sum(j.recipient_count) as total_recipients,
  sum(j.delivered_count) as delivered_count,
  sum(j.read_count) as read_count,
  sum(j.failed_count) as failed_count,
  sum(j.suppressed_count) as suppressed_count,

  max(j.created_at) as latest_notification_at

from public.notification_jobs j
left join public.notification_categories c
  on c.id = j.category_id
group by
  j.organization_id,
  c.category_code,
  c.category_name;

create or replace view public.notification_queue_health
with (security_invoker = true)
as
select
  o.organization_id,

  (
    select count(*)
    from public.notification_jobs j
    where j.organization_id = o.organization_id
      and j.status in (
        'pending',
        'queued',
        'scheduled',
        'processing'
      )
  ) as queued_jobs,

  (
    select count(*)
    from public.notification_delivery_attempts a
    where a.organization_id = o.organization_id
      and a.status in (
        'pending',
        'queued',
        'sending',
        'failed'
      )
  ) as pending_deliveries,

  (
    select count(*)
    from public.notification_retry_queue q
    where q.organization_id = o.organization_id
      and q.status = 'pending'
  ) as pending_retries,

  (
    select count(*)
    from public.notification_escalation_queue q
    where q.organization_id = o.organization_id
      and q.status = 'pending'
  ) as pending_escalations,

  (
    select count(*)
    from public.notification_event_outbox q
    where q.organization_id = o.organization_id
      and q.status in ('pending','failed')
  ) as pending_outbox_events

from (
  select distinct organization_id
  from public.notification_jobs
) o;

grant select
on
  public.notification_user_inbox_summary,
  public.notification_delivery_dashboard,
  public.notification_category_dashboard,
  public.notification_queue_health
to authenticated,service_role;

-- ============================================================
-- 35. HEALTH CHECK
-- ============================================================

create or replace function public.get_notification_engine_health(
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
        'notification.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',
    requested_organization_id,
    'checked_at',
    now(),

    'active_templates',
    (
      select count(*)
      from public.notification_templates t
      where t.status = 'active'
        and (
          requested_organization_id is null
          or t.organization_id = requested_organization_id
          or t.organization_id is null
        )
    ),

    'active_devices',
    (
      select count(*)
      from public.notification_user_devices d
      where d.status = 'active'
        and (
          requested_organization_id is null
          or d.organization_id = requested_organization_id
        )
    ),

    'queued_jobs',
    (
      select count(*)
      from public.notification_jobs j
      where j.status in (
        'pending',
        'queued',
        'scheduled',
        'processing'
      )
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'pending_deliveries',
    (
      select count(*)
      from public.notification_delivery_attempts a
      where a.status in (
        'pending',
        'queued',
        'sending',
        'failed'
      )
        and (
          requested_organization_id is null
          or a.organization_id = requested_organization_id
        )
    ),

    'failed_jobs_24h',
    (
      select count(*)
      from public.notification_jobs j
      where j.status = 'failed'
        and j.updated_at >= now() - interval '24 hours'
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'pending_retries',
    (
      select count(*)
      from public.notification_retry_queue q
      where q.status = 'pending'
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'pending_escalations',
    (
      select count(*)
      from public.notification_escalation_queue q
      where q.status = 'pending'
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',
    (
      select count(*)
      from public.notification_event_outbox q
      where q.status in ('pending','failed')
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'unread_inbox_items',
    (
      select count(*)
      from public.notification_inbox i
      where i.status = 'unread'
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    )
  );
end;
$$;

revoke all
on function public.get_notification_engine_health(uuid)
from public;

grant execute
on function public.get_notification_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 36. RLS
-- ============================================================

alter table public.notification_channels enable row level security;
alter table public.notification_categories enable row level security;
alter table public.notification_templates enable row level security;
alter table public.notification_user_devices enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.notification_subscriptions enable row level security;
alter table public.notification_jobs enable row level security;
alter table public.notification_recipients enable row level security;
alter table public.notification_delivery_attempts enable row level security;
alter table public.notification_inbox enable row level security;
alter table public.notification_digest_configs enable row level security;
alter table public.notification_digest_items enable row level security;
alter table public.notification_escalation_policies enable row level security;
alter table public.notification_escalation_queue enable row level security;
alter table public.notification_retry_queue enable row level security;
alter table public.notification_event_outbox enable row level security;
alter table public.notification_logs enable row level security;

drop policy if exists
notification_channels_authenticated_select
on public.notification_channels;

create policy
notification_channels_authenticated_select
on public.notification_channels
for select
to authenticated
using (true);

drop policy if exists
notification_categories_authenticated_select
on public.notification_categories;

create policy
notification_categories_authenticated_select
on public.notification_categories
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'notification.view'
  )
  or public.has_organization_permission(
    organization_id,
    'notification.view_all'
  )
);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'notification_templates',
    'notification_user_devices',
    'notification_preferences',
    'notification_subscriptions',
    'notification_jobs',
    'notification_recipients',
    'notification_delivery_attempts',
    'notification_digest_configs',
    'notification_digest_items',
    'notification_escalation_policies',
    'notification_escalation_queue',
    'notification_retry_queue',
    'notification_event_outbox',
    'notification_logs'
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
           ''notification.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''notification.view_all''
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
notification_inbox_user_select
on public.notification_inbox;

create policy
notification_inbox_user_select
on public.notification_inbox
for select
to authenticated
using (
  auth.uid() = user_id
  or public.has_organization_permission(
    organization_id,
    'notification.view_all'
  )
);

drop policy if exists
notification_inbox_user_update
on public.notification_inbox;

create policy
notification_inbox_user_update
on public.notification_inbox
for update
to authenticated
using (
  auth.uid() = user_id
  or public.has_organization_permission(
    organization_id,
    'notification.mark_read'
  )
)
with check (
  auth.uid() = user_id
  or public.has_organization_permission(
    organization_id,
    'notification.mark_read'
  )
);

drop policy if exists
notification_templates_write_policy
on public.notification_templates;

create policy
notification_templates_write_policy
on public.notification_templates
for all
to authenticated
using (
  organization_id is not null
  and public.has_organization_permission(
    organization_id,
    'notification.manage_templates'
  )
)
with check (
  organization_id is not null
  and public.has_organization_permission(
    organization_id,
    'notification.manage_templates'
  )
);

drop policy if exists
notification_preferences_write_policy
on public.notification_preferences;

create policy
notification_preferences_write_policy
on public.notification_preferences
for all
to authenticated
using (
  auth.uid() = user_id
  or public.has_organization_permission(
    organization_id,
    'notification.manage_preferences'
  )
)
with check (
  auth.uid() = user_id
  or public.has_organization_permission(
    organization_id,
    'notification.manage_preferences'
  )
);

-- ============================================================
-- 37. GRANTS
-- ============================================================

grant select
on
  public.notification_channels,
  public.notification_categories,
  public.notification_templates,
  public.notification_user_devices,
  public.notification_preferences,
  public.notification_subscriptions,
  public.notification_jobs,
  public.notification_recipients,
  public.notification_delivery_attempts,
  public.notification_inbox,
  public.notification_digest_configs,
  public.notification_digest_items,
  public.notification_escalation_policies,
  public.notification_escalation_queue,
  public.notification_retry_queue,
  public.notification_event_outbox,
  public.notification_logs
to authenticated;

grant insert,update,delete
on
  public.notification_templates,
  public.notification_user_devices,
  public.notification_preferences,
  public.notification_subscriptions,
  public.notification_digest_configs,
  public.notification_escalation_policies
to authenticated;

grant all
on
  public.notification_channels,
  public.notification_categories,
  public.notification_templates,
  public.notification_user_devices,
  public.notification_preferences,
  public.notification_subscriptions,
  public.notification_jobs,
  public.notification_recipients,
  public.notification_delivery_attempts,
  public.notification_inbox,
  public.notification_digest_configs,
  public.notification_digest_items,
  public.notification_escalation_policies,
  public.notification_escalation_queue,
  public.notification_retry_queue,
  public.notification_event_outbox,
  public.notification_logs
to service_role;

-- ============================================================
-- 38. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'notification_channels',
    'notification_categories',
    'notification_templates',
    'notification_user_devices',
    'notification_preferences',
    'notification_subscriptions',
    'notification_jobs',
    'notification_recipients',
    'notification_delivery_attempts',
    'notification_inbox',
    'notification_digest_configs',
    'notification_digest_items',
    'notification_escalation_policies',
    'notification_escalation_queue',
    'notification_retry_queue',
    'notification_event_outbox',
    'notification_logs'
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
    'notification_severity_rank',
    'check_notification_eligibility',
    'create_notification_job',
    'expand_notification_recipients',
    'claim_notification_delivery_attempt',
    'handoff_notification_to_communication',
    'update_notification_delivery_status',
    'mark_notification_read',
    'mark_all_notifications_read',
    'publish_notification_event',
    'claim_notification_event',
    'complete_notification_event',
    'process_notification_escalations',
    'release_expired_notification_locks',
    'get_notification_engine_health'
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
      '015 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 39. MIGRATION AUDIT
-- ============================================================

insert into public.notification_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.015.completed',
  'Notification Engine migration 015 completed',
  jsonb_build_object(
    'migration',
    '015_notification_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'channels',
      'categories',
      'templates',
      'user_devices',
      'preferences',
      'subscriptions',
      'jobs',
      'recipients',
      'delivery_attempts',
      'inbox',
      'digests',
      'escalations',
      'retry_queue',
      'event_outbox',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.notification_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.015.completed'
);

commit;