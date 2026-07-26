-- ============================================================
-- SalesSetu Enterprise
-- Migration 027: Communication Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   013_communication_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--   018_Document_Management_Engine.sql
--   023_Integration_API_Engine.sql
--   025_AI_Intelligence_Engine.sql
--   026_Automation_Engine.sql
--
-- Purpose:
--   Enterprise communication orchestration layer built above the
--   existing Communication Engine (013). All new tables use _v2
--   suffix to avoid conflicts with existing production objects.
--
-- Scope:
--   • Omnichannel conversations and participants
--   • WhatsApp, SMS, email, voice, push and in-app messaging
--   • Message templates, versions and approval states
--   • Outbound message queue and worker claim/lock
--   • Inbound message ingestion and deduplication
--   • Delivery events, read receipts and provider callbacks
--   • Contact preferences, consent and quiet hours
--   • Campaigns, recipients and throttling
--   • AI-assisted drafting and conversation summaries
--   • Communication routing, assignments and SLA
--   • Attachments, media and document references
--   • Event outbox, analytics, RLS, grants and health checks
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
    ('communication_engine_v2','view','communication_engine_v2.view','View communication data'),
    ('communication_engine_v2','view_all','communication_engine_v2.view_all','View all organization communications'),
    ('communication_engine_v2','send','communication_engine_v2.send','Send messages'),
    ('communication_engine_v2','reply','communication_engine_v2.reply','Reply to conversations'),
    ('communication_engine_v2','manage_channels','communication_engine_v2.manage_channels','Manage communication channels'),
    ('communication_engine_v2','manage_templates','communication_engine_v2.manage_templates','Manage communication templates'),
    ('communication_engine_v2','manage_campaigns','communication_engine_v2.manage_campaigns','Manage communication campaigns'),
    ('communication_engine_v2','manage_routing','communication_engine_v2.manage_routing','Manage communication routing'),
    ('communication_engine_v2','manage_consent','communication_engine_v2.manage_consent','Manage contact consent and preferences'),
    ('communication_engine_v2','manage_queue','communication_engine_v2.manage_queue','Manage communication queue'),
    ('communication_engine_v2','approve_templates','communication_engine_v2.approve_templates','Approve communication templates'),
    ('communication_engine_v2','view_sensitive','communication_engine_v2.view_sensitive','View sensitive message content'),
    ('communication_engine_v2','view_logs','communication_engine_v2.view_logs','View communication logs'),
    ('communication_engine_v2','view_analytics','communication_engine_v2.view_analytics','View communication analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. CHANNEL REGISTRY
-- ============================================================

create table if not exists public.communication_channels_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  channel_code text not null,
  channel_name text not null,

  channel_type text not null
    check (
      channel_type in (
        'whatsapp',
        'sms',
        'email',
        'voice',
        'push',
        'in_app',
        'web_chat',
        'instagram',
        'facebook',
        'telegram',
        'custom'
      )
    ),

  provider_code text,
  provider_connection_id uuid references public.integration_connections(id) on delete set null,

  sender_identity text,
  sender_display_name text,

  status text not null default 'inactive'
    check (
      status in (
        'inactive',
        'pending',
        'active',
        'degraded',
        'error',
        'suspended',
        'archived'
      )
    ),

  enabled boolean not null default false,

  supports_inbound boolean not null default true,
  supports_outbound boolean not null default true,
  supports_templates boolean not null default false,
  supports_media boolean not null default false,
  supports_read_receipts boolean not null default false,

  daily_limit integer,
  per_minute_limit integer,
  maximum_message_size integer,

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,channel_code)
);

create unique index if not exists communication_channels_v2_system_unique_idx
  on public.communication_channels_v2(channel_code)
  where organization_id is null;

-- ============================================================
-- 3. CONTACT ENDPOINTS
-- ============================================================

create table if not exists public.communication_contact_endpoints_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  contact_type text not null
    check (contact_type in ('lead','customer','user','external','unknown')),

  contact_id uuid,

  endpoint_type text not null
    check (
      endpoint_type in (
        'phone',
        'email',
        'whatsapp',
        'push_token',
        'social_handle',
        'custom'
      )
    ),

  endpoint_value text not null,
  normalized_value text not null,

  label text,
  is_primary boolean not null default false,
  is_verified boolean not null default false,
  verified_at timestamptz,

  status text not null default 'active'
    check (status in ('active','inactive','invalid','blocked','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    organization_id,
    endpoint_type,
    normalized_value
  )
);

create index if not exists communication_contact_endpoints_v2_contact_idx
  on public.communication_contact_endpoints_v2 (
    organization_id,
    contact_type,
    contact_id,
    status
  );

-- ============================================================
-- 4. CONSENT AND PREFERENCES
-- ============================================================

create table if not exists public.communication_preferences_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  contact_type text not null,
  contact_id uuid,
  endpoint_id uuid references public.communication_contact_endpoints_v2(id) on delete cascade,

  channel_type text not null,

  transactional_allowed boolean not null default true,
  marketing_allowed boolean not null default false,
  service_allowed boolean not null default true,

  preferred_language text not null default 'en',
  preferred_time_window jsonb not null default '{}',

  quiet_hours_enabled boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,
  timezone text not null default 'Asia/Kolkata',

  consent_status text not null default 'unknown'
    check (
      consent_status in (
        'unknown',
        'granted',
        'denied',
        'withdrawn',
        'expired'
      )
    ),

  consent_source text,
  consent_reference text,
  consented_at timestamptz,
  withdrawn_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    organization_id,
    endpoint_id,
    channel_type
  )
);

-- ============================================================
-- 5. TEMPLATE REGISTRY
-- ============================================================

create table if not exists public.communication_templates_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  template_code text not null,
  template_name text not null,

  channel_type text not null,
  template_category text not null default 'utility'
    check (
      template_category in (
        'utility',
        'marketing',
        'authentication',
        'transactional',
        'service',
        'followup',
        'reminder',
        'custom'
      )
    ),

  language_code text not null default 'en',

  subject_template text,
  body_template text not null,

  variables jsonb not null default '[]',
  buttons jsonb not null default '[]',
  media_config jsonb not null default '{}',

  provider_template_id text,
  provider_status text,

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'pending_approval',
        'approved',
        'rejected',
        'active',
        'inactive',
        'archived'
      )
    ),

  is_system_template boolean not null default false,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    organization_id,
    template_code,
    language_code
  )
);

create table if not exists public.communication_template_versions_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  template_id uuid not null references public.communication_templates_v2(id) on delete cascade,

  version_number integer not null,

  subject_template text,
  body_template text not null,
  variables jsonb not null default '[]',
  buttons jsonb not null default '[]',
  media_config jsonb not null default '{}',

  is_current boolean not null default false,
  change_summary text,

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  unique (template_id,version_number)
);

create unique index if not exists communication_template_versions_v2_current_idx
  on public.communication_template_versions_v2(template_id)
  where is_current = true;

-- ============================================================
-- 6. CONVERSATIONS
-- ============================================================

create table if not exists public.communication_conversations_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  conversation_key text not null,

  channel_id uuid references public.communication_channels_v2(id) on delete set null,
  channel_type text not null,

  subject text,

  related_entity_type text,
  related_entity_id uuid,

  status text not null default 'open'
    check (
      status in (
        'open',
        'pending',
        'waiting_customer',
        'waiting_agent',
        'resolved',
        'closed',
        'spam',
        'archived'
      )
    ),

  priority text not null default 'normal'
    check (priority in ('low','normal','high','urgent')),

  assigned_user_id uuid references auth.users(id) on delete set null,
  assigned_team_id uuid,

  first_message_at timestamptz,
  last_message_at timestamptz,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,

  unread_count integer not null default 0,
  message_count integer not null default 0,

  sla_due_at timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,

  ai_summary text,
  ai_sentiment text,
  ai_intent text,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (conversation_key)
);

create index if not exists communication_conversations_v2_assignment_idx
  on public.communication_conversations_v2 (
    organization_id,
    assigned_user_id,
    status,
    priority
  );

-- ============================================================
-- 7. CONVERSATION PARTICIPANTS
-- ============================================================

create table if not exists public.communication_conversation_participants_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  conversation_id uuid not null references public.communication_conversations_v2(id) on delete cascade,

  participant_type text not null
    check (participant_type in ('lead','customer','user','agent','bot','external')),

  participant_id uuid,
  endpoint_id uuid references public.communication_contact_endpoints_v2(id) on delete set null,

  display_name text,
  role text not null default 'participant'
    check (role in ('owner','participant','observer','assignee','bot')),

  joined_at timestamptz not null default now(),
  left_at timestamptz,

  metadata jsonb not null default '{}',

  unique (
    conversation_id,
    participant_type,
    participant_id,
    endpoint_id
  )
);

-- ============================================================
-- 8. MESSAGES
-- ============================================================

create table if not exists public.communication_messages_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  conversation_id uuid references public.communication_conversations_v2(id) on delete cascade,
  channel_id uuid references public.communication_channels_v2(id) on delete set null,

  direction text not null
    check (direction in ('inbound','outbound','internal')),

  message_type text not null default 'text'
    check (
      message_type in (
        'text',
        'html',
        'template',
        'image',
        'video',
        'audio',
        'document',
        'location',
        'contact',
        'interactive',
        'voice_call',
        'system',
        'custom'
      )
    ),

  sender_type text,
  sender_id uuid,
  sender_endpoint_id uuid references public.communication_contact_endpoints_v2(id) on delete set null,

  recipient_endpoint_id uuid references public.communication_contact_endpoints_v2(id) on delete set null,

  template_id uuid references public.communication_templates_v2(id) on delete set null,
  template_version_id uuid references public.communication_template_versions_v2(id) on delete set null,

  subject text,
  body_text text,
  body_html text,
  content_json jsonb not null default '{}',

  provider_message_id text,
  provider_thread_id text,

  status text not null default 'created'
    check (
      status in (
        'created',
        'queued',
        'sending',
        'sent',
        'delivered',
        'read',
        'failed',
        'cancelled',
        'received',
        'processed'
      )
    ),

  scheduled_at timestamptz,
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  failed_at timestamptz,
  received_at timestamptz,

  reply_to_message_id uuid references public.communication_messages_v2(id) on delete set null,

  idempotency_key text,
  correlation_id text,
  trace_id text,

  ai_generated boolean not null default false,
  ai_agent_id uuid references public.ai_agents(id) on delete set null,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists communication_messages_v2_provider_unique_idx
  on public.communication_messages_v2 (
    organization_id,
    channel_id,
    provider_message_id
  )
  where provider_message_id is not null;

create unique index if not exists communication_messages_v2_idem_idx
  on public.communication_messages_v2 (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists communication_messages_v2_conversation_idx
  on public.communication_messages_v2 (
    conversation_id,
    created_at
  );

-- ============================================================
-- 9. ATTACHMENTS
-- ============================================================

create table if not exists public.communication_message_attachments_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_id uuid not null references public.communication_messages_v2(id) on delete cascade,

  attachment_type text not null
    check (
      attachment_type in (
        'image',
        'video',
        'audio',
        'document',
        'sticker',
        'location',
        'contact',
        'custom'
      )
    ),

  document_id uuid references public.documents(id) on delete set null,

  file_name text,
  mime_type text,
  file_size_bytes bigint,

  storage_bucket text,
  storage_path text,
  external_url text,

  checksum text,

  provider_media_id text,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'uploading',
        'uploaded',
        'available',
        'failed',
        'expired'
      )
    ),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

-- ============================================================
-- 10. MESSAGE QUEUE
-- ============================================================

create table if not exists public.communication_message_queue_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_id uuid not null references public.communication_messages_v2(id) on delete cascade,
  channel_id uuid not null references public.communication_channels_v2(id) on delete cascade,

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'processing',
        'sent',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,
  available_at timestamptz not null default now(),

  attempts integer not null default 0,
  maximum_attempts integer not null default 8,

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  completed_at timestamptz,

  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (message_id)
);

create index if not exists communication_message_queue_v2_worker_idx
  on public.communication_message_queue_v2 (
    status,
    available_at,
    priority,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 11. DELIVERY EVENTS
-- ============================================================

create table if not exists public.communication_delivery_events_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_id uuid not null references public.communication_messages_v2(id) on delete cascade,
  channel_id uuid references public.communication_channels_v2(id) on delete set null,

  event_type text not null
    check (
      event_type in (
        'queued',
        'sent',
        'delivered',
        'read',
        'failed',
        'bounced',
        'opened',
        'clicked',
        'received',
        'replied',
        'unsubscribed',
        'custom'
      )
    ),

  provider_event_id text,
  provider_status text,

  event_data jsonb not null default '{}',

  occurred_at timestamptz not null default now(),
  received_at timestamptz not null default now(),

  created_at timestamptz not null default now()
);

create unique index if not exists communication_delivery_events_v2_provider_idx
  on public.communication_delivery_events_v2 (
    organization_id,
    provider_event_id
  )
  where provider_event_id is not null;

-- ============================================================
-- 12. CAMPAIGNS
-- ============================================================

create table if not exists public.communication_campaigns_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  campaign_code text not null,
  campaign_name text not null,
  description text,

  channel_id uuid references public.communication_channels_v2(id) on delete set null,
  channel_type text not null,

  template_id uuid references public.communication_templates_v2(id) on delete set null,

  campaign_type text not null default 'broadcast'
    check (
      campaign_type in (
        'broadcast',
        'drip',
        'transactional',
        'followup',
        'reminder',
        'nurture',
        'custom'
      )
    ),

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'scheduled',
        'running',
        'paused',
        'completed',
        'cancelled',
        'failed',
        'archived'
      )
    ),

  scheduled_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,

  audience_filter jsonb not null default '{}',
  personalization_mapping jsonb not null default '{}',

  per_minute_limit integer,
  daily_limit integer,

  total_recipients integer not null default 0,
  queued_count integer not null default 0,
  sent_count integer not null default 0,
  delivered_count integer not null default 0,
  read_count integer not null default 0,
  failed_count integer not null default 0,
  response_count integer not null default 0,

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,campaign_code)
);

create table if not exists public.communication_campaign_recipients_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  campaign_id uuid not null references public.communication_campaigns_v2(id) on delete cascade,

  contact_type text not null,
  contact_id uuid,
  endpoint_id uuid references public.communication_contact_endpoints_v2(id) on delete set null,

  personalization_data jsonb not null default '{}',

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'queued',
        'sent',
        'delivered',
        'read',
        'responded',
        'failed',
        'skipped',
        'cancelled'
      )
    ),

  message_id uuid references public.communication_messages_v2(id) on delete set null,

  scheduled_at timestamptz,
  sent_at timestamptz,
  completed_at timestamptz,

  error_code text,
  error_message text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    campaign_id,
    endpoint_id
  )
);

-- ============================================================
-- 13. ROUTING RULES
-- ============================================================

create table if not exists public.communication_routing_rules_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  rule_code text not null,
  rule_name text not null,

  priority integer not null default 100,

  channel_types text[] not null default '{}',
  event_types text[] not null default '{}',

  condition_expression jsonb not null default '{}',

  assignment_strategy text not null default 'none'
    check (
      assignment_strategy in (
        'none',
        'specific_user',
        'round_robin',
        'least_loaded',
        'skill_based',
        'team',
        'ai'
      )
    ),

  assigned_user_id uuid references auth.users(id) on delete set null,
  assigned_team_id uuid,

  sla_minutes integer,
  auto_reply_template_id uuid references public.communication_templates_v2(id) on delete set null,
  ai_agent_id uuid references public.ai_agents(id) on delete set null,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,rule_code)
);

-- ============================================================
-- 14. AI DRAFTS AND SUMMARIES
-- ============================================================

create table if not exists public.communication_ai_drafts_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  conversation_id uuid references public.communication_conversations_v2(id) on delete cascade,
  message_id uuid references public.communication_messages_v2(id) on delete set null,

  ai_agent_id uuid references public.ai_agents(id) on delete set null,
  ai_task_id uuid references public.ai_tasks(id) on delete set null,

  draft_type text not null
    check (
      draft_type in (
        'reply',
        'followup',
        'summary',
        'translation',
        'rewrite',
        'classification',
        'custom'
      )
    ),

  input_context jsonb not null default '{}',

  draft_subject text,
  draft_body text,
  draft_data jsonb not null default '{}',

  confidence_score numeric(8,4),

  status text not null default 'generated'
    check (
      status in (
        'generated',
        'reviewed',
        'approved',
        'rejected',
        'used',
        'expired'
      )
    ),

  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.communication_conversation_summaries_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  conversation_id uuid not null references public.communication_conversations_v2(id) on delete cascade,

  summary_text text not null,
  key_points jsonb not null default '[]',
  detected_intent text,
  detected_sentiment text,
  next_best_actions jsonb not null default '[]',

  ai_agent_id uuid references public.ai_agents(id) on delete set null,
  message_count integer,

  generated_at timestamptz not null default now(),
  expires_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

-- ============================================================
-- 15. EVENT OUTBOX AND LOGS
-- ============================================================

create table if not exists public.communication_engine_event_outbox_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  conversation_id uuid references public.communication_conversations_v2(id) on delete set null,
  message_id uuid references public.communication_messages_v2(id) on delete set null,
  campaign_id uuid references public.communication_campaigns_v2(id) on delete set null,

  event_name text not null,

  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'automation_engine',
        'workflow_engine',
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

create unique index if not exists communication_engine_event_outbox_v2_idem_idx
  on public.communication_engine_event_outbox_v2 (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create table if not exists public.communication_engine_logs_v2 (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,

  conversation_id uuid references public.communication_conversations_v2(id) on delete set null,
  message_id uuid references public.communication_messages_v2(id) on delete set null,
  campaign_id uuid references public.communication_campaigns_v2(id) on delete set null,

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

create index if not exists communication_engine_logs_v2_org_time_idx
  on public.communication_engine_logs_v2 (
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
    'communication_channels_v2',
    'communication_contact_endpoints_v2',
    'communication_preferences_v2',
    'communication_templates_v2',
    'communication_conversations_v2',
    'communication_messages_v2',
    'communication_message_queue_v2',
    'communication_campaigns_v2',
    'communication_campaign_recipients_v2',
    'communication_routing_rules_v2',
    'communication_ai_drafts_v2',
    'communication_engine_event_outbox_v2'
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
-- 17. UPSERT CONTACT ENDPOINT
-- ============================================================

create or replace function public.upsert_communication_contact_endpoint_v2(
  requested_organization_id uuid,
  requested_contact_type text,
  requested_contact_id uuid,
  requested_endpoint_type text,
  requested_endpoint_value text,
  requested_normalized_value text,
  requested_label text default null,
  requested_is_primary boolean default false,
  requested_is_verified boolean default false,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.communication_contact_endpoints_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint_record public.communication_contact_endpoints_v2;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'communication_engine_v2.manage_consent'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.communication_contact_endpoints_v2 (
    organization_id,
    contact_type,
    contact_id,
    endpoint_type,
    endpoint_value,
    normalized_value,
    label,
    is_primary,
    is_verified,
    verified_at,
    status,
    metadata
  )
  values (
    requested_organization_id,
    requested_contact_type,
    requested_contact_id,
    requested_endpoint_type,
    requested_endpoint_value,
    requested_normalized_value,
    requested_label,
    requested_is_primary,
    requested_is_verified,
    case when requested_is_verified then now() else null end,
    'active',
    coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (
    organization_id,
    endpoint_type,
    normalized_value
  )
  do update set
    contact_type = excluded.contact_type,
    contact_id = excluded.contact_id,
    endpoint_value = excluded.endpoint_value,
    label = excluded.label,
    is_primary = excluded.is_primary,
    is_verified = excluded.is_verified,
    verified_at = case
      when excluded.is_verified then coalesce(
        communication_contact_endpoints_v2.verified_at,
        now()
      )
      else communication_contact_endpoints_v2.verified_at
    end,
    status = 'active',
    metadata = excluded.metadata,
    updated_at = now()
  returning * into endpoint_record;

  return endpoint_record;
end;
$$;

revoke all
on function public.upsert_communication_contact_endpoint_v2(
  uuid,text,uuid,text,text,text,text,boolean,boolean,jsonb
)
from public;

grant execute
on function public.upsert_communication_contact_endpoint_v2(
  uuid,text,uuid,text,text,text,text,boolean,boolean,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 18. CREATE OR GET CONVERSATION
-- ============================================================

create or replace function public.get_or_create_conversation_v2(
  requested_organization_id uuid,
  requested_channel_id uuid,
  requested_channel_type text,
  requested_contact_endpoint_id uuid,
  requested_related_entity_type text default null,
  requested_related_entity_id uuid default null,
  requested_subject text default null,
  requested_priority text default 'normal',
  requested_metadata jsonb default '{}'::jsonb
)
returns public.communication_conversations_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint_record public.communication_contact_endpoints_v2;
  conversation_record public.communication_conversations_v2;
  generated_key text;
begin
  select *
  into endpoint_record
  from public.communication_contact_endpoints_v2
  where id = requested_contact_endpoint_id
    and organization_id = requested_organization_id
    and status = 'active';

  if not found then
    raise exception 'Active contact endpoint not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'communication_engine_v2.reply'
    ) then
    raise exception 'Permission denied';
  end if;

  generated_key := requested_organization_id::text
    || ':'
    || requested_channel_type
    || ':'
    || endpoint_record.normalized_value;

  select *
  into conversation_record
  from public.communication_conversations_v2
  where conversation_key = generated_key
    and status not in ('closed','archived')
  order by created_at desc
  limit 1;

  if found then
    return conversation_record;
  end if;

  insert into public.communication_conversations_v2 (
    organization_id,
    conversation_key,
    channel_id,
    channel_type,
    subject,
    related_entity_type,
    related_entity_id,
    status,
    priority,
    first_message_at,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    generated_key,
    requested_channel_id,
    requested_channel_type,
    requested_subject,
    requested_related_entity_type,
    requested_related_entity_id,
    'open',
    requested_priority,
    now(),
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  returning * into conversation_record;

  insert into public.communication_conversation_participants_v2 (
    organization_id,
    conversation_id,
    participant_type,
    participant_id,
    endpoint_id,
    display_name,
    role
  )
  values (
    requested_organization_id,
    conversation_record.id,
    endpoint_record.contact_type,
    endpoint_record.contact_id,
    endpoint_record.id,
    null,
    'participant'
  )
  on conflict do nothing;

  return conversation_record;
end;
$$;

revoke all
on function public.get_or_create_conversation_v2(
  uuid,uuid,text,uuid,text,uuid,text,text,jsonb
)
from public;

grant execute
on function public.get_or_create_conversation_v2(
  uuid,uuid,text,uuid,text,uuid,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 19. QUEUE OUTBOUND MESSAGE
-- ============================================================

create or replace function public.queue_outbound_message_v2(
  requested_organization_id uuid,
  requested_conversation_id uuid,
  requested_channel_id uuid,
  requested_recipient_endpoint_id uuid,
  requested_message_type text default 'text',
  requested_subject text default null,
  requested_body_text text default null,
  requested_body_html text default null,
  requested_content_json jsonb default '{}'::jsonb,
  requested_template_id uuid default null,
  requested_template_version_id uuid default null,
  requested_scheduled_at timestamptz default now(),
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_ai_generated boolean default false,
  requested_ai_agent_id uuid default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.communication_messages_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  channel_record public.communication_channels_v2;
  conversation_record public.communication_conversations_v2;
  endpoint_record public.communication_contact_endpoints_v2;
  existing_message public.communication_messages_v2;
  message_record public.communication_messages_v2;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'communication_engine_v2.send'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into channel_record
  from public.communication_channels_v2
  where id = requested_channel_id
    and organization_id = requested_organization_id
    and status = 'active'
    and enabled = true
    and supports_outbound = true;

  if not found then
    raise exception 'Active outbound channel not found';
  end if;

  select *
  into conversation_record
  from public.communication_conversations_v2
  where id = requested_conversation_id
    and organization_id = requested_organization_id;

  if not found then
    raise exception 'Conversation not found';
  end if;

  select *
  into endpoint_record
  from public.communication_contact_endpoints_v2
  where id = requested_recipient_endpoint_id
    and organization_id = requested_organization_id
    and status = 'active';

  if not found then
    raise exception 'Recipient endpoint not found';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_message
    from public.communication_messages_v2
    where organization_id = requested_organization_id
      and idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_message;
    end if;
  end if;

  insert into public.communication_messages_v2 (
    organization_id,
    conversation_id,
    channel_id,
    direction,
    message_type,
    sender_type,
    sender_id,
    recipient_endpoint_id,
    template_id,
    template_version_id,
    subject,
    body_text,
    body_html,
    content_json,
    status,
    scheduled_at,
    idempotency_key,
    correlation_id,
    trace_id,
    ai_generated,
    ai_agent_id,
    metadata,
    created_by
  )
  values (
    requested_organization_id,
    conversation_record.id,
    channel_record.id,
    'outbound',
    requested_message_type,
    case when requested_ai_generated then 'bot' else 'user' end,
    auth.uid(),
    endpoint_record.id,
    requested_template_id,
    requested_template_version_id,
    requested_subject,
    requested_body_text,
    requested_body_html,
    coalesce(requested_content_json,'{}'::jsonb),
    'queued',
    coalesce(requested_scheduled_at,now()),
    requested_idempotency_key,
    requested_correlation_id,
    requested_trace_id,
    requested_ai_generated,
    requested_ai_agent_id,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid()
  )
  returning * into message_record;

  insert into public.communication_message_queue_v2 (
    organization_id,
    message_id,
    channel_id,
    status,
    priority,
    available_at
  )
  values (
    requested_organization_id,
    message_record.id,
    channel_record.id,
    'queued',
    requested_priority,
    coalesce(requested_scheduled_at,now())
  );

  update public.communication_conversations_v2
  set
    message_count = message_count + 1,
    last_message_at = now(),
    last_outbound_at = now(),
    updated_at = now()
  where id = conversation_record.id;

  return message_record;
end;
$$;

revoke all
on function public.queue_outbound_message_v2(
  uuid,uuid,uuid,uuid,text,text,text,text,jsonb,uuid,uuid,timestamptz,integer,text,text,text,boolean,uuid,jsonb
)
from public;

grant execute
on function public.queue_outbound_message_v2(
  uuid,uuid,uuid,uuid,text,text,text,text,jsonb,uuid,uuid,timestamptz,integer,text,text,text,boolean,uuid,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 20. INGEST INBOUND MESSAGE
-- ============================================================

create or replace function public.ingest_inbound_message_v2(
  requested_organization_id uuid,
  requested_channel_id uuid,
  requested_sender_endpoint_id uuid,
  requested_message_type text,
  requested_body_text text default null,
  requested_content_json jsonb default '{}'::jsonb,
  requested_provider_message_id text default null,
  requested_provider_thread_id text default null,
  requested_received_at timestamptz default now(),
  requested_related_entity_type text default null,
  requested_related_entity_id uuid default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.communication_messages_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  channel_record public.communication_channels_v2;
  endpoint_record public.communication_contact_endpoints_v2;
  existing_message public.communication_messages_v2;
  conversation_record public.communication_conversations_v2;
  message_record public.communication_messages_v2;
begin
  select *
  into channel_record
  from public.communication_channels_v2
  where id = requested_channel_id
    and organization_id = requested_organization_id
    and status = 'active'
    and enabled = true
    and supports_inbound = true;

  if not found then
    raise exception 'Active inbound channel not found';
  end if;

  select *
  into endpoint_record
  from public.communication_contact_endpoints_v2
  where id = requested_sender_endpoint_id
    and organization_id = requested_organization_id;

  if not found then
    raise exception 'Sender endpoint not found';
  end if;

  if requested_provider_message_id is not null then
    select *
    into existing_message
    from public.communication_messages_v2
    where organization_id = requested_organization_id
      and channel_id = requested_channel_id
      and provider_message_id = requested_provider_message_id
    limit 1;

    if found then
      return existing_message;
    end if;
  end if;

  conversation_record := public.get_or_create_conversation_v2(
    requested_organization_id,
    requested_channel_id,
    channel_record.channel_type,
    requested_sender_endpoint_id,
    requested_related_entity_type,
    requested_related_entity_id,
    null,
    'normal',
    jsonb_build_object('source','inbound_message')
  );

  insert into public.communication_messages_v2 (
    organization_id,
    conversation_id,
    channel_id,
    direction,
    message_type,
    sender_type,
    sender_id,
    sender_endpoint_id,
    body_text,
    content_json,
    provider_message_id,
    provider_thread_id,
    status,
    received_at,
    correlation_id,
    trace_id,
    metadata
  )
  values (
    requested_organization_id,
    conversation_record.id,
    channel_record.id,
    'inbound',
    requested_message_type,
    endpoint_record.contact_type,
    endpoint_record.contact_id,
    endpoint_record.id,
    requested_body_text,
    coalesce(requested_content_json,'{}'::jsonb),
    requested_provider_message_id,
    requested_provider_thread_id,
    'received',
    coalesce(requested_received_at,now()),
    requested_correlation_id,
    requested_trace_id,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into message_record;

  update public.communication_conversations_v2
  set
    status = case
      when status in ('resolved','closed') then 'open'
      else status
    end,
    message_count = message_count + 1,
    unread_count = unread_count + 1,
    last_message_at = coalesce(requested_received_at,now()),
    last_inbound_at = coalesce(requested_received_at,now()),
    updated_at = now()
  where id = conversation_record.id;

  return message_record;
end;
$$;

revoke all
on function public.ingest_inbound_message_v2(
  uuid,uuid,uuid,text,text,jsonb,text,text,timestamptz,text,uuid,text,text,jsonb
)
from public;

grant execute
on function public.ingest_inbound_message_v2(
  uuid,uuid,uuid,text,text,jsonb,text,text,timestamptz,text,uuid,text,text,jsonb
)
to anon,authenticated,service_role;

-- ============================================================
-- 21. CLAIM MESSAGE JOB
-- ============================================================

create or replace function public.claim_communication_message_job_v2(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.communication_message_queue_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.communication_message_queue_v2;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim communication jobs';
  end if;

  select *
  into job_record
  from public.communication_message_queue_v2 q
  where q.status in ('queued','failed')
    and q.available_at <= now()
    and q.attempts < q.maximum_attempts
    and (
      requested_organization_id is null
      or q.organization_id = requested_organization_id
    )
  order by
    q.priority,
    q.available_at,
    q.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.communication_message_queue_v2
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

  update public.communication_messages_v2
  set
    status = 'sending',
    updated_at = now()
  where id = job_record.message_id;

  return job_record;
end;
$$;

revoke all
on function public.claim_communication_message_job_v2(
  text,uuid,integer
)
from public;

grant execute
on function public.claim_communication_message_job_v2(
  text,uuid,integer
)
to service_role;

-- ============================================================
-- 22. COMPLETE MESSAGE JOB
-- ============================================================

create or replace function public.complete_communication_message_job_v2(
  requested_job_id uuid,
  requested_lock_token text,
  requested_provider_message_id text default null,
  requested_provider_thread_id text default null,
  requested_provider_data jsonb default '{}'::jsonb
)
returns public.communication_message_queue_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.communication_message_queue_v2;
  message_record public.communication_messages_v2;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete communication jobs';
  end if;

  select *
  into job_record
  from public.communication_message_queue_v2
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Communication job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid communication job lock token';
  end if;

  update public.communication_message_queue_v2
  set
    status = 'sent',
    completed_at = now(),
    claimed_at = null,
    claimed_by = null,
    lock_token = null,
    lock_expires_at = null,
    metadata = metadata || jsonb_build_object(
      'provider_data',
      coalesce(requested_provider_data,'{}'::jsonb)
    ),
    updated_at = now()
  where id = requested_job_id
  returning * into job_record;

  update public.communication_messages_v2
  set
    status = 'sent',
    provider_message_id = coalesce(
      requested_provider_message_id,
      provider_message_id
    ),
    provider_thread_id = coalesce(
      requested_provider_thread_id,
      provider_thread_id
    ),
    sent_at = now(),
    updated_at = now()
  where id = job_record.message_id
  returning * into message_record;

  insert into public.communication_delivery_events_v2 (
    organization_id,
    message_id,
    channel_id,
    event_type,
    provider_status,
    event_data,
    occurred_at
  )
  values (
    job_record.organization_id,
    message_record.id,
    message_record.channel_id,
    'sent',
    'sent',
    coalesce(requested_provider_data,'{}'::jsonb),
    now()
  );

  return job_record;
end;
$$;

revoke all
on function public.complete_communication_message_job_v2(
  uuid,text,text,text,jsonb
)
from public;

grant execute
on function public.complete_communication_message_job_v2(
  uuid,text,text,text,jsonb
)
to service_role;

-- ============================================================
-- 23. FAIL MESSAGE JOB
-- ============================================================

create or replace function public.fail_communication_message_job_v2(
  requested_job_id uuid,
  requested_lock_token text,
  requested_error_code text,
  requested_error_message text,
  requested_error_data jsonb default '{}'::jsonb
)
returns public.communication_message_queue_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.communication_message_queue_v2;
  next_status text;
  retry_delay integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may fail communication jobs';
  end if;

  select *
  into job_record
  from public.communication_message_queue_v2
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Communication job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid communication job lock token';
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

  update public.communication_message_queue_v2
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

  update public.communication_messages_v2
  set
    status = 'failed',
    failed_at = now(),
    error_code = requested_error_code,
    error_message = requested_error_message,
    error_data = coalesce(requested_error_data,'{}'::jsonb),
    updated_at = now()
  where id = job_record.message_id;

  insert into public.communication_delivery_events_v2 (
    organization_id,
    message_id,
    channel_id,
    event_type,
    provider_status,
    event_data,
    occurred_at
  )
  values (
    job_record.organization_id,
    job_record.message_id,
    job_record.channel_id,
    'failed',
    next_status,
    jsonb_build_object(
      'error_code',requested_error_code,
      'error_message',requested_error_message,
      'error_data',coalesce(requested_error_data,'{}'::jsonb)
    ),
    now()
  );

  return job_record;
end;
$$;

revoke all
on function public.fail_communication_message_job_v2(
  uuid,text,text,text,jsonb
)
from public;

grant execute
on function public.fail_communication_message_job_v2(
  uuid,text,text,text,jsonb
)
to service_role;

-- ============================================================
-- 24. RECORD DELIVERY EVENT
-- ============================================================

create or replace function public.record_communication_delivery_event_v2(
  requested_message_id uuid,
  requested_event_type text,
  requested_provider_event_id text default null,
  requested_provider_status text default null,
  requested_event_data jsonb default '{}'::jsonb,
  requested_occurred_at timestamptz default now()
)
returns public.communication_delivery_events_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  message_record public.communication_messages_v2;
  event_record public.communication_delivery_events_v2;
begin
  select *
  into message_record
  from public.communication_messages_v2
  where id = requested_message_id
  for update;

  if not found then
    raise exception 'Communication message not found';
  end if;

  insert into public.communication_delivery_events_v2 (
    organization_id,
    message_id,
    channel_id,
    event_type,
    provider_event_id,
    provider_status,
    event_data,
    occurred_at
  )
  values (
    message_record.organization_id,
    message_record.id,
    message_record.channel_id,
    requested_event_type,
    requested_provider_event_id,
    requested_provider_status,
    coalesce(requested_event_data,'{}'::jsonb),
    coalesce(requested_occurred_at,now())
  )
  on conflict (
    organization_id,
    provider_event_id
  )
  where provider_event_id is not null
  do update set
    provider_status = excluded.provider_status,
    event_data = excluded.event_data,
    occurred_at = excluded.occurred_at
  returning * into event_record;

  update public.communication_messages_v2
  set
    status = case requested_event_type
      when 'delivered' then 'delivered'
      when 'read' then 'read'
      when 'failed' then 'failed'
      when 'received' then 'received'
      else status
    end,
    delivered_at = case
      when requested_event_type = 'delivered'
        then coalesce(requested_occurred_at,now())
      else delivered_at
    end,
    read_at = case
      when requested_event_type = 'read'
        then coalesce(requested_occurred_at,now())
      else read_at
    end,
    failed_at = case
      when requested_event_type = 'failed'
        then coalesce(requested_occurred_at,now())
      else failed_at
    end,
    updated_at = now()
  where id = requested_message_id;

  return event_record;
end;
$$;

revoke all
on function public.record_communication_delivery_event_v2(
  uuid,text,text,text,jsonb,timestamptz
)
from public;

grant execute
on function public.record_communication_delivery_event_v2(
  uuid,text,text,text,jsonb,timestamptz
)
to anon,authenticated,service_role;

-- ============================================================
-- 25. PUBLISH COMMUNICATION EVENT
-- ============================================================

create or replace function public.publish_communication_engine_event_v2(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_conversation_id uuid default null,
  requested_message_id uuid default null,
  requested_campaign_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.communication_engine_event_outbox_v2
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.communication_engine_event_outbox_v2;
  created_event public.communication_engine_event_outbox_v2;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.communication_engine_event_outbox_v2
    where organization_id is not distinct from requested_organization_id
      and idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.communication_engine_event_outbox_v2 (
    organization_id,
    conversation_id,
    message_id,
    campaign_id,
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
    requested_conversation_id,
    requested_message_id,
    requested_campaign_id,
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
on function public.publish_communication_engine_event_v2(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_communication_engine_event_v2(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 26. MESSAGE EVENT TRIGGER
-- ============================================================

create or replace function public.emit_communication_message_events_v2()
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

  perform public.publish_communication_engine_event_v2(
    new.organization_id,
    'communication.message.' || new.status,
    jsonb_build_object(
      'message_id',new.id,
      'conversation_id',new.conversation_id,
      'channel_id',new.channel_id,
      'direction',new.direction,
      'message_type',new.message_type,
      'status',new.status,
      'provider_message_id',new.provider_message_id,
      'error_code',new.error_code,
      'error_message',new.error_message
    ),
    case
      when new.status in ('failed')
        then 'notification_engine'
      when new.status in ('received','read')
        then 'automation_engine'
      else 'analytics'
    end,
    new.conversation_id,
    new.id,
    null,
    case when new.status = 'failed' then 10 else 50 end,
    'communication-message:' || new.id::text || ':' || new.status,
    coalesce(new.correlation_id,new.id::text),
    new.trace_id,
    now()
  );

  return new;
end;
$$;

drop trigger if exists communication_messages_v2_emit_events
on public.communication_messages_v2;

create trigger communication_messages_v2_emit_events
after insert or update
on public.communication_messages_v2
for each row
execute function public.emit_communication_message_events_v2();

-- ============================================================
-- 27. ANALYTICS VIEWS
-- ============================================================

create or replace view public.communication_message_dashboard_v2
with (security_invoker = true)
as
select
  m.organization_id,
  m.channel_id,
  c.channel_type,
  m.direction,
  m.status,

  count(*) as message_count,

  count(*) filter (
    where m.status = 'sent'
  ) as sent_count,

  count(*) filter (
    where m.status = 'delivered'
  ) as delivered_count,

  count(*) filter (
    where m.status = 'read'
  ) as read_count,

  count(*) filter (
    where m.status = 'failed'
  ) as failed_count,

  round(
    count(*) filter (
      where m.status in ('delivered','read')
    )::numeric
    / nullif(
      count(*) filter (
        where m.direction = 'outbound'
      ),
      0
    ) * 100,
    2
  ) as delivery_rate,

  max(m.created_at) as latest_message_at

from public.communication_messages_v2 m
left join public.communication_channels_v2 c
  on c.id = m.channel_id
group by
  m.organization_id,
  m.channel_id,
  c.channel_type,
  m.direction,
  m.status;

create or replace view public.communication_conversation_dashboard_v2
with (security_invoker = true)
as
select
  organization_id,
  channel_type,
  status,
  priority,

  count(*) as conversation_count,

  count(*) filter (
    where unread_count > 0
  ) as unread_conversations,

  round(avg(unread_count),2) as average_unread_count,
  round(avg(message_count),2) as average_message_count,

  count(*) filter (
    where sla_due_at is not null
      and sla_due_at < now()
      and status not in ('resolved','closed','archived')
  ) as sla_breached_count,

  max(last_message_at) as latest_message_at

from public.communication_conversations_v2
group by
  organization_id,
  channel_type,
  status,
  priority;

create or replace view public.communication_campaign_dashboard_v2
with (security_invoker = true)
as
select
  organization_id,
  channel_type,
  campaign_type,
  status,

  count(*) as campaign_count,
  coalesce(sum(total_recipients),0) as total_recipients,
  coalesce(sum(sent_count),0) as sent_count,
  coalesce(sum(delivered_count),0) as delivered_count,
  coalesce(sum(read_count),0) as read_count,
  coalesce(sum(failed_count),0) as failed_count,
  coalesce(sum(response_count),0) as response_count,

  round(
    coalesce(sum(delivered_count),0)::numeric
    / nullif(coalesce(sum(sent_count),0),0) * 100,
    2
  ) as delivery_rate,

  round(
    coalesce(sum(response_count),0)::numeric
    / nullif(coalesce(sum(delivered_count),0),0) * 100,
    2
  ) as response_rate,

  max(completed_at) as latest_completion_at

from public.communication_campaigns_v2
group by
  organization_id,
  channel_type,
  campaign_type,
  status;

create or replace view public.communication_queue_dashboard_v2
with (security_invoker = true)
as
select
  organization_id,
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

from public.communication_message_queue_v2
group by
  organization_id,
  status;

grant select
on
  public.communication_message_dashboard_v2,
  public.communication_conversation_dashboard_v2,
  public.communication_campaign_dashboard_v2,
  public.communication_queue_dashboard_v2
to authenticated,service_role;

-- ============================================================
-- 28. HEALTH CHECK
-- ============================================================

create or replace function public.get_communication_engine_health_v2(
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
        'communication_engine_v2.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'active_channels',(
      select count(*)
      from public.communication_channels_v2 c
      where c.status = 'active'
        and c.enabled = true
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'open_conversations',(
      select count(*)
      from public.communication_conversations_v2 c
      where c.status in ('open','pending','waiting_customer','waiting_agent')
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'unread_conversations',(
      select count(*)
      from public.communication_conversations_v2 c
      where c.unread_count > 0
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'queued_messages',(
      select count(*)
      from public.communication_message_queue_v2 q
      where q.status in ('queued','claimed','processing','failed')
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'dead_lettered_messages',(
      select count(*)
      from public.communication_message_queue_v2 q
      where q.status = 'dead_lettered'
        and (
          requested_organization_id is null
          or q.organization_id = requested_organization_id
        )
    ),

    'failed_messages_24h',(
      select count(*)
      from public.communication_messages_v2 m
      where m.status = 'failed'
        and m.updated_at >= now() - interval '24 hours'
        and (
          requested_organization_id is null
          or m.organization_id = requested_organization_id
        )
    ),

    'sla_breaches',(
      select count(*)
      from public.communication_conversations_v2 c
      where c.sla_due_at is not null
        and c.sla_due_at < now()
        and c.status not in ('resolved','closed','archived')
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'running_campaigns',(
      select count(*)
      from public.communication_campaigns_v2 c
      where c.status in ('scheduled','running','paused')
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.communication_engine_event_outbox_v2 e
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
on function public.get_communication_engine_health_v2(uuid)
from public;

grant execute
on function public.get_communication_engine_health_v2(uuid)
to authenticated,service_role;

-- ============================================================
-- 29. ROW LEVEL SECURITY
-- ============================================================

alter table public.communication_channels_v2 enable row level security;
alter table public.communication_contact_endpoints_v2 enable row level security;
alter table public.communication_preferences_v2 enable row level security;
alter table public.communication_templates_v2 enable row level security;
alter table public.communication_template_versions_v2 enable row level security;
alter table public.communication_conversations_v2 enable row level security;
alter table public.communication_conversation_participants_v2 enable row level security;
alter table public.communication_messages_v2 enable row level security;
alter table public.communication_message_attachments_v2 enable row level security;
alter table public.communication_message_queue_v2 enable row level security;
alter table public.communication_delivery_events_v2 enable row level security;
alter table public.communication_campaigns_v2 enable row level security;
alter table public.communication_campaign_recipients_v2 enable row level security;
alter table public.communication_routing_rules_v2 enable row level security;
alter table public.communication_ai_drafts_v2 enable row level security;
alter table public.communication_conversation_summaries_v2 enable row level security;
alter table public.communication_engine_event_outbox_v2 enable row level security;
alter table public.communication_engine_logs_v2 enable row level security;

drop policy if exists communication_channels_v2_select_policy
on public.communication_channels_v2;

create policy communication_channels_v2_select_policy
on public.communication_channels_v2
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'communication_engine_v2.view'
  )
  or public.has_organization_permission(
    organization_id,
    'communication_engine_v2.view_all'
  )
);

drop policy if exists communication_channels_v2_service_policy
on public.communication_channels_v2;

create policy communication_channels_v2_service_policy
on public.communication_channels_v2
for all
to service_role
using (true)
with check (true);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'communication_contact_endpoints_v2',
    'communication_preferences_v2',
    'communication_templates_v2',
    'communication_template_versions_v2',
    'communication_conversations_v2',
    'communication_conversation_participants_v2',
    'communication_messages_v2',
    'communication_message_attachments_v2',
    'communication_message_queue_v2',
    'communication_delivery_events_v2',
    'communication_campaigns_v2',
    'communication_campaign_recipients_v2',
    'communication_routing_rules_v2',
    'communication_ai_drafts_v2',
    'communication_conversation_summaries_v2',
    'communication_engine_event_outbox_v2',
    'communication_engine_logs_v2'
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
           ''communication_engine_v2.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''communication_engine_v2.view_all''
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

drop policy if exists communication_conversations_v2_write_policy
on public.communication_conversations_v2;

create policy communication_conversations_v2_write_policy
on public.communication_conversations_v2
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'communication_engine_v2.reply'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'communication_engine_v2.reply'
  )
);

drop policy if exists communication_templates_v2_write_policy
on public.communication_templates_v2;

create policy communication_templates_v2_write_policy
on public.communication_templates_v2
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'communication_engine_v2.manage_templates'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'communication_engine_v2.manage_templates'
  )
);

drop policy if exists communication_campaigns_v2_write_policy
on public.communication_campaigns_v2;

create policy communication_campaigns_v2_write_policy
on public.communication_campaigns_v2
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'communication_engine_v2.manage_campaigns'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'communication_engine_v2.manage_campaigns'
  )
);

-- ============================================================
-- 30. GRANTS
-- ============================================================

grant select
on
  public.communication_channels_v2,
  public.communication_contact_endpoints_v2,
  public.communication_preferences_v2,
  public.communication_templates_v2,
  public.communication_template_versions_v2,
  public.communication_conversations_v2,
  public.communication_conversation_participants_v2,
  public.communication_messages_v2,
  public.communication_message_attachments_v2,
  public.communication_message_queue_v2,
  public.communication_delivery_events_v2,
  public.communication_campaigns_v2,
  public.communication_campaign_recipients_v2,
  public.communication_routing_rules_v2,
  public.communication_ai_drafts_v2,
  public.communication_conversation_summaries_v2,
  public.communication_engine_event_outbox_v2,
  public.communication_engine_logs_v2
to authenticated;

grant insert,update,delete
on
  public.communication_channels_v2,
  public.communication_contact_endpoints_v2,
  public.communication_preferences_v2,
  public.communication_templates_v2,
  public.communication_template_versions_v2,
  public.communication_conversations_v2,
  public.communication_conversation_participants_v2,
  public.communication_campaigns_v2,
  public.communication_campaign_recipients_v2,
  public.communication_routing_rules_v2,
  public.communication_ai_drafts_v2
to authenticated;

grant insert,update
on
  public.communication_messages_v2,
  public.communication_message_attachments_v2,
  public.communication_delivery_events_v2
to authenticated;

grant all
on
  public.communication_channels_v2,
  public.communication_contact_endpoints_v2,
  public.communication_preferences_v2,
  public.communication_templates_v2,
  public.communication_template_versions_v2,
  public.communication_conversations_v2,
  public.communication_conversation_participants_v2,
  public.communication_messages_v2,
  public.communication_message_attachments_v2,
  public.communication_message_queue_v2,
  public.communication_delivery_events_v2,
  public.communication_campaigns_v2,
  public.communication_campaign_recipients_v2,
  public.communication_routing_rules_v2,
  public.communication_ai_drafts_v2,
  public.communication_conversation_summaries_v2,
  public.communication_engine_event_outbox_v2,
  public.communication_engine_logs_v2
to service_role;

-- ============================================================
-- 31. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'communication_channels_v2',
    'communication_contact_endpoints_v2',
    'communication_preferences_v2',
    'communication_templates_v2',
    'communication_template_versions_v2',
    'communication_conversations_v2',
    'communication_conversation_participants_v2',
    'communication_messages_v2',
    'communication_message_attachments_v2',
    'communication_message_queue_v2',
    'communication_delivery_events_v2',
    'communication_campaigns_v2',
    'communication_campaign_recipients_v2',
    'communication_routing_rules_v2',
    'communication_ai_drafts_v2',
    'communication_conversation_summaries_v2',
    'communication_engine_event_outbox_v2',
    'communication_engine_logs_v2'
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
    'upsert_communication_contact_endpoint_v2',
    'get_or_create_conversation_v2',
    'queue_outbound_message_v2',
    'ingest_inbound_message_v2',
    'claim_communication_message_job_v2',
    'complete_communication_message_job_v2',
    'fail_communication_message_job_v2',
    'record_communication_delivery_event_v2',
    'publish_communication_engine_event_v2',
    'get_communication_engine_health_v2'
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
      '027 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 32. MIGRATION AUDIT
-- ============================================================

insert into public.communication_engine_logs_v2 (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.027.completed',
  'Communication Engine migration 027 completed',
  jsonb_build_object(
    'migration',
    '027_communication_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'channels',
      'contact_endpoints',
      'preferences',
      'consent',
      'templates',
      'template_versions',
      'conversations',
      'participants',
      'messages',
      'attachments',
      'message_queue',
      'delivery_events',
      'campaigns',
      'campaign_recipients',
      'routing',
      'ai_drafts',
      'summaries',
      'analytics',
      'event_outbox'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.communication_engine_logs_v2 l
  where l.organization_id = o.id
    and l.event_name = 'migration.027.completed'
);

commit;