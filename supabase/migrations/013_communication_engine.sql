-- ============================================================
-- SalesSetu Enterprise
-- Migration 013: Communication Engine
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
--
-- Scope:
--   • Multi-channel communication: WhatsApp, Email, SMS, Push, In-app
--   • Provider abstraction and organization connections
--   • Templates, variables, localization and approval
--   • Conversations, messages, recipients, attachments and delivery events
--   • Campaigns, broadcasts, sequences and steps
--   • Preferences, consent, DND and suppression
--   • Retry queues, webhook inbox and event outbox
--   • Interakt, Meta Cloud API, SMTP/Resend and SMS-provider readiness
--   • Workflow/n8n handoff, analytics, RLS, grants and health checks
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
    ('communication','view','communication.view','View communication records'),
    ('communication','view_all','communication.view_all','View all organization communication records'),
    ('communication','send','communication.send','Send communication messages'),
    ('communication','send_bulk','communication.send_bulk','Send bulk communication'),
    ('communication','manage_templates','communication.manage_templates','Manage communication templates'),
    ('communication','manage_channels','communication.manage_channels','Manage channel settings'),
    ('communication','manage_providers','communication.manage_providers','Manage communication providers'),
    ('communication','manage_connections','communication.manage_connections','Manage provider connections'),
    ('communication','manage_campaigns','communication.manage_campaigns','Manage communication campaigns'),
    ('communication','manage_sequences','communication.manage_sequences','Manage communication sequences'),
    ('communication','manage_preferences','communication.manage_preferences','Manage communication preferences'),
    ('communication','manage_suppression','communication.manage_suppression','Manage communication suppression'),
    ('communication','retry','communication.retry','Retry failed communication messages'),
    ('communication','cancel','communication.cancel','Cancel queued communication'),
    ('communication','view_logs','communication.view_logs','View communication logs'),
    ('communication','view_analytics','communication.view_analytics','View communication analytics'),
    ('communication','override','communication.override','Override communication restrictions')
) as permission_data(module,action,code,description)
where not exists (
  select 1
  from public.permissions p
  where p.code = permission_data.code
);

-- ============================================================
-- 2. CHANNEL CATALOGUE
-- ============================================================

create table if not exists public.communication_channels (
  code text primary key,
  display_name text not null,
  channel_group text not null
    check (channel_group in ('messaging','email','telephony','push','in_app','other')),
  supports_inbound boolean not null default false,
  supports_outbound boolean not null default true,
  supports_templates boolean not null default false,
  supports_attachments boolean not null default false,
  supports_delivery_receipts boolean not null default false,
  supports_read_receipts boolean not null default false,
  supports_conversations boolean not null default false,
  supports_marketing boolean not null default true,
  supports_transactional boolean not null default true,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

insert into public.communication_channels (
  code,display_name,channel_group,
  supports_inbound,supports_outbound,supports_templates,
  supports_attachments,supports_delivery_receipts,
  supports_read_receipts,supports_conversations,
  supports_marketing,supports_transactional
)
values
  ('whatsapp','WhatsApp','messaging',true,true,true,true,true,true,true,true,true),
  ('email','Email','email',true,true,true,true,true,false,true,true,true),
  ('sms','SMS','messaging',false,true,true,false,true,false,false,true,true),
  ('push','Push Notification','push',false,true,true,true,true,true,false,true,true),
  ('in_app','In-app Notification','in_app',false,true,true,true,true,true,false,true,true)
on conflict (code) do update
set
  display_name = excluded.display_name,
  channel_group = excluded.channel_group,
  supports_inbound = excluded.supports_inbound,
  supports_outbound = excluded.supports_outbound,
  supports_templates = excluded.supports_templates,
  supports_attachments = excluded.supports_attachments,
  supports_delivery_receipts = excluded.supports_delivery_receipts,
  supports_read_receipts = excluded.supports_read_receipts,
  supports_conversations = excluded.supports_conversations,
  supports_marketing = excluded.supports_marketing,
  supports_transactional = excluded.supports_transactional;

-- ============================================================
-- 3. PROVIDERS
-- ============================================================

create table if not exists public.communication_providers (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null unique,
  provider_name text not null,
  provider_type text not null
    check (provider_type in ('whatsapp','email','sms','push','in_app','multi_channel','custom')),
  status text not null default 'active'
    check (status in ('active','inactive','deprecated')),
  supports_webhooks boolean not null default true,
  supports_templates boolean not null default true,
  supports_bulk boolean not null default true,
  configuration_schema jsonb not null default '{}',
  capability_metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.communication_providers (
  provider_code,provider_name,provider_type,
  supports_webhooks,supports_templates,supports_bulk
)
values
  ('interakt','Interakt','whatsapp',true,true,true),
  ('meta_whatsapp_cloud','Meta WhatsApp Cloud API','whatsapp',true,true,true),
  ('resend','Resend','email',true,true,true),
  ('smtp','SMTP','email',false,true,true),
  ('twilio_sms','Twilio SMS','sms',true,true,true),
  ('msg91','MSG91','sms',true,true,true),
  ('firebase','Firebase Cloud Messaging','push',true,true,true),
  ('internal_in_app','SalesSetu In-app','in_app',false,true,true)
on conflict (provider_code) do update
set
  provider_name = excluded.provider_name,
  provider_type = excluded.provider_type,
  supports_webhooks = excluded.supports_webhooks,
  supports_templates = excluded.supports_templates,
  supports_bulk = excluded.supports_bulk,
  updated_at = now();

-- ============================================================
-- 4. PROVIDER CONNECTIONS
-- ============================================================

create table if not exists public.communication_provider_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid not null references public.communication_providers(id) on delete restrict,
  connection_name text not null,
  channel_code text not null references public.communication_channels(code) on delete restrict,

  status text not null default 'draft'
    check (status in ('draft','active','inactive','error','revoked')),

  is_default boolean not null default false,
  sender_identity text,
  sender_name text,
  phone_number text,
  email_address text,

  credentials_encrypted jsonb not null default '{}',
  configuration jsonb not null default '{}',
  webhook_configuration jsonb not null default '{}',
  rate_limit_configuration jsonb not null default '{}',

  last_health_check_at timestamptz,
  last_health_status text,
  last_error text,

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,connection_name)
);

create unique index if not exists communication_provider_default_idx
  on public.communication_provider_connections (organization_id,channel_code)
  where is_default = true and status = 'active';

create index if not exists communication_provider_connections_lookup_idx
  on public.communication_provider_connections (organization_id,channel_code,status,is_default);

-- ============================================================
-- 5. TEMPLATE CATEGORIES
-- ============================================================

create table if not exists public.communication_template_categories (
  code text primary key,
  display_name text not null,
  description text,
  marketing_allowed boolean not null default true,
  transactional_allowed boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.communication_template_categories (
  code,display_name,description,marketing_allowed,transactional_allowed
)
values
  ('greeting','Greeting','Initial greeting and welcome messages',true,true),
  ('lead_followup','Lead Follow-up','Lead nurturing and follow-up messages',true,true),
  ('qualification','Qualification','Lead qualification communication',true,true),
  ('site_visit','Site Visit','Site visit scheduling and reminders',true,true),
  ('booking','Booking','Booking confirmation and updates',false,true),
  ('payment','Payment','Payment reminders and confirmations',false,true),
  ('document','Document','Document requests and confirmations',false,true),
  ('customer_success','Customer Success','Post-booking and customer support communication',true,true),
  ('broadcast','Broadcast','General promotional broadcast communication',true,false),
  ('system','System','System-generated operational communication',false,true)
on conflict (code) do update
set
  display_name = excluded.display_name,
  description = excluded.description,
  marketing_allowed = excluded.marketing_allowed,
  transactional_allowed = excluded.transactional_allowed;

-- ============================================================
-- 6. TEMPLATES
-- ============================================================

create table if not exists public.communication_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  template_code text not null,
  template_name text not null,
  category_code text not null references public.communication_template_categories(code) on delete restrict,
  channel_code text not null references public.communication_channels(code) on delete restrict,

  language_code text not null default 'en',
  locale text,
  version integer not null default 1 check (version > 0),

  status text not null default 'draft'
    check (status in ('draft','pending_approval','approved','rejected','active','inactive','archived')),

  message_type text not null default 'transactional'
    check (message_type in ('marketing','transactional','service','authentication','utility')),

  subject_template text,
  body_template text not null,
  header_template text,
  footer_template text,

  variable_schema jsonb not null default '{}',
  button_schema jsonb not null default '[]',
  attachment_schema jsonb not null default '[]',

  provider_template_name text,
  provider_template_id text,
  provider_status text,
  provider_rejection_reason text,

  is_system_template boolean not null default false,
  is_default boolean not null default false,

  approval_requested_at timestamptz,
  approved_at timestamptz,
  activated_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,template_code,channel_code,language_code,version)
);

create index if not exists communication_templates_lookup_idx
  on public.communication_templates (organization_id,channel_code,status,template_code,language_code);

-- ============================================================
-- 7. TEMPLATE VARIABLES
-- ============================================================

create table if not exists public.communication_template_variables (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.communication_templates(id) on delete cascade,

  variable_key text not null,
  display_name text,
  data_type text not null default 'text'
    check (data_type in ('text','number','date','datetime','boolean','currency','url','phone','email','json')),

  source_type text not null default 'runtime'
    check (source_type in ('runtime','lead','assignment','booking','site_visit','organization','agent','system','custom')),

  source_path text,
  default_value text,
  is_required boolean not null default false,
  validation_rule jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (template_id,variable_key)
);

-- ============================================================
-- 8. CONTACT ENDPOINTS
-- ============================================================

create table if not exists public.communication_contact_endpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,

  endpoint_type text not null
    check (endpoint_type in ('phone','whatsapp','email','push_token','in_app_user','custom')),

  endpoint_value text not null,
  normalized_value text,
  label text,

  is_primary boolean not null default false,
  is_verified boolean not null default false,
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified','pending','verified','failed','expired')),

  status text not null default 'active'
    check (status in ('active','inactive','bounced','invalid','suppressed','archived')),

  country_code text,
  timezone text,
  language_code text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,endpoint_type,normalized_value)
);

create index if not exists communication_contact_endpoints_lead_idx
  on public.communication_contact_endpoints (organization_id,lead_id,endpoint_type,status);

-- ============================================================
-- 9. PREFERENCES AND CONSENT
-- ============================================================

create table if not exists public.communication_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  endpoint_id uuid references public.communication_contact_endpoints(id) on delete cascade,

  channel_code text not null references public.communication_channels(code) on delete cascade,
  message_type text not null default 'marketing'
    check (message_type in ('marketing','transactional','service','authentication','utility','all')),

  preference_status text not null default 'unknown'
    check (preference_status in ('opted_in','opted_out','unknown','restricted')),

  consent_source text,
  consent_reference text,
  consent_text text,
  consent_ip inet,
  consent_user_agent text,

  granted_at timestamptz,
  withdrawn_at timestamptz,
  expires_at timestamptz,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,lead_id,user_id,endpoint_id,channel_code,message_type)
);

create index if not exists communication_preferences_lookup_idx
  on public.communication_preferences (
    organization_id,lead_id,channel_code,message_type,preference_status
  );

-- ============================================================
-- 10. SUPPRESSION LIST
-- ============================================================

create table if not exists public.communication_suppression_list (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  suppression_type text not null
    check (suppression_type in ('phone','email','domain','whatsapp','push_token','lead','user','custom')),

  suppression_value text not null,
  normalized_value text,

  channel_code text references public.communication_channels(code) on delete cascade,

  reason_code text not null default 'manual',
  reason text,

  scope text not null default 'organization'
    check (scope in ('global','organization')),

  status text not null default 'active'
    check (status in ('active','inactive','expired','removed')),

  active_from timestamptz not null default now(),
  active_until timestamptz,

  created_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists communication_suppression_lookup_idx
  on public.communication_suppression_list (
    organization_id,suppression_type,normalized_value,channel_code,status
  );

-- ============================================================
-- 11. CONVERSATIONS
-- ============================================================

create table if not exists public.communication_conversations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,

  channel_code text not null references public.communication_channels(code) on delete restrict,
  provider_connection_id uuid references public.communication_provider_connections(id) on delete set null,

  external_conversation_id text,
  conversation_key text,

  status text not null default 'open'
    check (status in ('open','pending','resolved','closed','archived','blocked')),

  assigned_user_id uuid references auth.users(id) on delete set null,
  assigned_team_id uuid references public.assignment_teams(id) on delete set null,

  subject text,
  last_message_at timestamptz,
  last_inbound_at timestamptz,
  last_outbound_at timestamptz,
  unread_count integer not null default 0,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,channel_code,conversation_key)
);

create index if not exists communication_conversations_lead_idx
  on public.communication_conversations (organization_id,lead_id,channel_code,last_message_at desc);

-- ============================================================
-- 12. MESSAGE JOBS
-- ============================================================

create table if not exists public.communication_message_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,

  conversation_id uuid references public.communication_conversations(id) on delete set null,
  provider_connection_id uuid references public.communication_provider_connections(id) on delete set null,
  template_id uuid references public.communication_templates(id) on delete set null,

  workflow_execution_id uuid references public.workflow_executions(id) on delete set null,
  assignment_id uuid references public.lead_assignments(id) on delete set null,

  channel_code text not null references public.communication_channels(code) on delete restrict,
  direction text not null default 'outbound'
    check (direction in ('outbound','inbound','system')),

  message_type text not null default 'transactional'
    check (message_type in ('marketing','transactional','service','authentication','utility','system')),

  source_type text not null default 'system'
    check (source_type in ('manual','workflow','n8n','campaign','sequence','api','webhook','system')),

  source_reference text,
  idempotency_key text,

  priority integer not null default 100,

  status text not null default 'queued'
    check (
      status in (
        'draft','pending','queued','validating','scheduled','sending',
        'sent','delivered','read','failed','cancelled','suppressed',
        'expired','received','processed'
      )
    ),

  subject text,
  body text,
  rendered_subject text,
  rendered_body text,

  variables jsonb not null default '{}',
  buttons jsonb not null default '[]',
  metadata jsonb not null default '{}',

  scheduled_at timestamptz,
  queued_at timestamptz not null default now(),
  sending_started_at timestamptz,
  sent_at timestamptz,
  delivered_at timestamptz,
  read_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  expires_at timestamptz,

  attempts integer not null default 0,
  maximum_attempts integer not null default 5
    check (maximum_attempts between 1 and 20),
  next_retry_at timestamptz,

  provider_message_id text,
  provider_status text,
  provider_response jsonb not null default '{}',

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists communication_message_jobs_idempotency_idx
  on public.communication_message_jobs (organization_id,idempotency_key)
  where idempotency_key is not null;

create index if not exists communication_message_jobs_queue_idx
  on public.communication_message_jobs (
    status,coalesce(scheduled_at,queued_at),priority,created_at
  )
  where status in ('pending','queued','scheduled','failed');

create index if not exists communication_message_jobs_lead_idx
  on public.communication_message_jobs (organization_id,lead_id,created_at desc);

-- ============================================================
-- 13. RECIPIENTS
-- ============================================================

create table if not exists public.communication_message_recipients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_job_id uuid not null references public.communication_message_jobs(id) on delete cascade,

  recipient_type text not null
    check (recipient_type in ('to','cc','bcc','reply_to','sender')),

  endpoint_id uuid references public.communication_contact_endpoints(id) on delete set null,
  recipient_name text,
  recipient_address text not null,
  normalized_address text,

  status text not null default 'pending'
    check (status in ('pending','valid','invalid','suppressed','sent','delivered','read','failed')),

  error_code text,
  error_message text,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists communication_message_recipients_job_idx
  on public.communication_message_recipients (message_job_id,recipient_type,status);

-- ============================================================
-- 14. ATTACHMENTS
-- ============================================================

create table if not exists public.communication_message_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_job_id uuid not null references public.communication_message_jobs(id) on delete cascade,

  attachment_type text not null default 'file'
    check (attachment_type in ('file','image','video','audio','document','location','contact','template_media')),

  file_name text,
  mime_type text,
  file_size bigint,
  storage_bucket text,
  storage_path text,
  public_url text,
  provider_media_id text,

  status text not null default 'ready'
    check (status in ('pending','uploading','ready','failed','expired')),

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

-- ============================================================
-- 15. DELIVERY EVENTS
-- ============================================================

create table if not exists public.communication_delivery_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_job_id uuid not null references public.communication_message_jobs(id) on delete cascade,

  event_type text not null
    check (
      event_type in (
        'created','queued','scheduled','sending','sent','delivered','read',
        'received','processed','failed','bounced','complained','suppressed',
        'cancelled','expired','clicked','opened'
      )
    ),

  provider_event_id text,
  provider_status text,

  event_at timestamptz not null default now(),
  event_data jsonb not null default '{}',

  created_at timestamptz not null default now()
);

create unique index if not exists communication_delivery_provider_event_idx
  on public.communication_delivery_events (organization_id,provider_event_id)
  where provider_event_id is not null;

create index if not exists communication_delivery_events_job_idx
  on public.communication_delivery_events (message_job_id,event_at);

-- ============================================================
-- 16. CAMPAIGNS
-- ============================================================

create table if not exists public.communication_campaigns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  campaign_code text not null,
  campaign_name text not null,
  description text,

  campaign_type text not null default 'broadcast'
    check (campaign_type in ('broadcast','drip','event_triggered','transactional','nurture','remarketing','custom')),

  channel_code text not null references public.communication_channels(code) on delete restrict,
  template_id uuid references public.communication_templates(id) on delete set null,
  provider_connection_id uuid references public.communication_provider_connections(id) on delete set null,

  status text not null default 'draft'
    check (status in ('draft','scheduled','running','paused','completed','cancelled','archived')),

  audience_definition jsonb not null default '{}',
  exclusion_definition jsonb not null default '{}',
  variable_mapping jsonb not null default '{}',

  schedule_type text not null default 'manual'
    check (schedule_type in ('manual','once','recurring','event_triggered')),

  scheduled_at timestamptz,
  recurrence_rule text,

  timezone text not null default 'Asia/Kolkata',

  maximum_recipients integer,
  batch_size integer not null default 100,
  throttle_per_minute integer,

  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,

  total_recipients integer not null default 0,
  queued_count integer not null default 0,
  sent_count integer not null default 0,
  delivered_count integer not null default 0,
  read_count integer not null default 0,
  failed_count integer not null default 0,
  suppressed_count integer not null default 0,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,campaign_code)
);

create index if not exists communication_campaigns_org_status_idx
  on public.communication_campaigns (organization_id,status,scheduled_at);

-- ============================================================
-- 17. CAMPAIGN RECIPIENTS
-- ============================================================

create table if not exists public.communication_campaign_recipients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  campaign_id uuid not null references public.communication_campaigns(id) on delete cascade,

  lead_id uuid references public.leads(id) on delete cascade,
  endpoint_id uuid references public.communication_contact_endpoints(id) on delete set null,

  recipient_address text not null,
  normalized_address text,

  variables jsonb not null default '{}',

  status text not null default 'pending'
    check (status in ('pending','queued','sent','delivered','read','failed','suppressed','cancelled')),

  message_job_id uuid references public.communication_message_jobs(id) on delete set null,

  scheduled_at timestamptz,
  processed_at timestamptz,

  error_code text,
  error_message text,

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),

  unique (campaign_id,lead_id,recipient_address)
);

create index if not exists communication_campaign_recipients_queue_idx
  on public.communication_campaign_recipients (campaign_id,status,scheduled_at,created_at);

-- ============================================================
-- 18. SEQUENCES
-- ============================================================

create table if not exists public.communication_sequences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  sequence_code text not null,
  sequence_name text not null,
  description text,

  status text not null default 'draft'
    check (status in ('draft','active','paused','inactive','archived')),

  trigger_type text not null default 'manual'
    check (trigger_type in ('manual','lead_created','validation_approved','assignment_created','site_visit','booking','workflow','event')),

  trigger_configuration jsonb not null default '{}',
  exit_conditions jsonb not null default '{}',

  timezone text not null default 'Asia/Kolkata',
  maximum_duration_days integer,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,sequence_code)
);

-- ============================================================
-- 19. SEQUENCE STEPS
-- ============================================================

create table if not exists public.communication_sequence_steps (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sequence_id uuid not null references public.communication_sequences(id) on delete cascade,

  step_order integer not null check (step_order > 0),
  step_name text,

  channel_code text references public.communication_channels(code) on delete restrict,
  template_id uuid references public.communication_templates(id) on delete set null,
  provider_connection_id uuid references public.communication_provider_connections(id) on delete set null,

  delay_value integer not null default 0,
  delay_unit text not null default 'minutes'
    check (delay_unit in ('minutes','hours','days','weeks')),

  send_window jsonb not null default '{}',
  condition_expression jsonb not null default '{}',
  variable_mapping jsonb not null default '{}',

  on_success_action jsonb not null default '{}',
  on_failure_action jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (sequence_id,step_order)
);

-- ============================================================
-- 20. SEQUENCE ENROLLMENTS
-- ============================================================

create table if not exists public.communication_sequence_enrollments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sequence_id uuid not null references public.communication_sequences(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,

  status text not null default 'active'
    check (status in ('active','paused','completed','exited','cancelled','failed')),

  current_step_order integer not null default 1,
  enrolled_at timestamptz not null default now(),
  next_step_at timestamptz,
  completed_at timestamptz,
  exited_at timestamptz,

  exit_reason text,
  enrollment_context jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (sequence_id,lead_id)
);

create index if not exists communication_sequence_enrollments_due_idx
  on public.communication_sequence_enrollments (status,next_step_at)
  where status = 'active';

-- ============================================================
-- 21. RETRY QUEUE
-- ============================================================

create table if not exists public.communication_retry_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_job_id uuid not null references public.communication_message_jobs(id) on delete cascade,

  status text not null default 'pending'
    check (status in ('pending','claimed','processing','completed','failed','cancelled','dead_lettered')),

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
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists communication_retry_active_idx
  on public.communication_retry_queue (message_job_id)
  where status in ('pending','claimed','processing');

create index if not exists communication_retry_due_idx
  on public.communication_retry_queue (status,scheduled_at)
  where status = 'pending';

-- ============================================================
-- 22. WEBHOOK INBOX
-- ============================================================

create table if not exists public.communication_webhook_inbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  provider_connection_id uuid references public.communication_provider_connections(id) on delete set null,

  provider_code text,
  provider_event_id text,
  event_type text not null,

  signature_valid boolean,
  headers jsonb not null default '{}',
  payload jsonb not null default '{}',

  status text not null default 'received'
    check (status in ('received','processing','processed','ignored','failed','dead_lettered')),

  attempts integer not null default 0,
  next_retry_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  received_at timestamptz not null default now(),
  processed_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index if not exists communication_webhook_provider_event_idx
  on public.communication_webhook_inbox (provider_code,provider_event_id)
  where provider_event_id is not null;

create index if not exists communication_webhook_processing_idx
  on public.communication_webhook_inbox (status,next_retry_at,received_at)
  where status in ('received','failed');

-- ============================================================
-- 23. EVENT OUTBOX
-- ============================================================

create table if not exists public.communication_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_job_id uuid references public.communication_message_jobs(id) on delete set null,
  campaign_id uuid references public.communication_campaigns(id) on delete set null,
  sequence_enrollment_id uuid references public.communication_sequence_enrollments(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,

  event_name text not null,
  destination text not null default 'internal'
    check (destination in ('internal','workflow_engine','n8n','webhook','analytics','notification','audit')),

  status text not null default 'pending'
    check (status in ('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),

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

create unique index if not exists communication_event_outbox_idempotency_idx
  on public.communication_event_outbox (organization_id,idempotency_key)
  where idempotency_key is not null;

create index if not exists communication_event_outbox_queue_idx
  on public.communication_event_outbox (status,available_at,priority,created_at)
  where status in ('pending','failed');

-- ============================================================
-- 24. LOGS
-- ============================================================

create table if not exists public.communication_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  message_job_id uuid references public.communication_message_jobs(id) on delete set null,
  campaign_id uuid references public.communication_campaigns(id) on delete set null,
  sequence_enrollment_id uuid references public.communication_sequence_enrollments(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,

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

create index if not exists communication_logs_org_created_idx
  on public.communication_logs (organization_id,created_at desc);

-- ============================================================
-- 25. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'communication_providers',
    'communication_provider_connections',
    'communication_templates',
    'communication_contact_endpoints',
    'communication_preferences',
    'communication_suppression_list',
    'communication_conversations',
    'communication_message_jobs',
    'communication_campaigns',
    'communication_sequences',
    'communication_sequence_steps',
    'communication_sequence_enrollments',
    'communication_retry_queue',
    'communication_event_outbox'
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
-- 26. NORMALIZATION HELPERS
-- ============================================================

create or replace function public.normalize_communication_phone(
  requested_phone text,
  requested_default_country_code text default '+91'
)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  digits text;
  country_digits text;
begin
  if requested_phone is null then
    return null;
  end if;

  digits := regexp_replace(requested_phone,'[^0-9]','','g');
  country_digits := regexp_replace(coalesce(requested_default_country_code,'+91'),'[^0-9]','','g');

  if digits = '' then
    return null;
  end if;

  if length(digits)=10 then
    return '+'||country_digits||digits;
  end if;

  if left(digits,2)='00' then
    return '+'||substring(digits from 3);
  end if;

  return '+'||digits;
end;
$$;

create or replace function public.normalize_communication_email(
  requested_email text
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when requested_email is null then null
    else nullif(lower(btrim(requested_email)),'')
  end;
$$;

revoke all on function public.normalize_communication_phone(text,text) from public;
revoke all on function public.normalize_communication_email(text) from public;
grant execute on function public.normalize_communication_phone(text,text) to authenticated,service_role;
grant execute on function public.normalize_communication_email(text) to authenticated,service_role;

-- ============================================================
-- 27. RESOLVE DEFAULT CONNECTION
-- ============================================================

create or replace function public.resolve_communication_connection(
  requested_organization_id uuid,
  requested_channel_code text,
  requested_connection_id uuid default null
)
returns public.communication_provider_connections
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  connection_record public.communication_provider_connections;
begin
  if requested_connection_id is not null then
    select *
    into connection_record
    from public.communication_provider_connections c
    where c.id = requested_connection_id
      and c.organization_id = requested_organization_id
      and c.channel_code = requested_channel_code
      and c.status = 'active';

    if not found then
      raise exception 'Active communication connection not found';
    end if;

    return connection_record;
  end if;

  select *
  into connection_record
  from public.communication_provider_connections c
  where c.organization_id = requested_organization_id
    and c.channel_code = requested_channel_code
    and c.status = 'active'
  order by c.is_default desc,c.created_at
  limit 1;

  if not found then
    raise exception 'No active provider connection configured';
  end if;

  return connection_record;
end;
$$;

revoke all on function public.resolve_communication_connection(uuid,text,uuid) from public;
grant execute on function public.resolve_communication_connection(uuid,text,uuid) to authenticated,service_role;

-- ============================================================
-- 28. COMMUNICATION ELIGIBILITY
-- ============================================================

create or replace function public.check_communication_eligibility(
  requested_organization_id uuid,
  requested_channel_code text,
  requested_recipient_address text,
  requested_message_type text default 'marketing',
  requested_lead_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_address text;
  preference_status_value text;
  suppression_match boolean;
begin
  normalized_address :=
    case
      when requested_channel_code in ('whatsapp','sms')
        then public.normalize_communication_phone(requested_recipient_address,'+91')
      when requested_channel_code='email'
        then public.normalize_communication_email(requested_recipient_address)
      else nullif(btrim(requested_recipient_address),'')
    end;

  select exists (
    select 1
    from public.communication_suppression_list s
    where s.status='active'
      and s.active_from<=now()
      and (s.active_until is null or s.active_until>now())
      and (s.scope='global' or s.organization_id=requested_organization_id)
      and (s.channel_code is null or s.channel_code=requested_channel_code)
      and coalesce(s.normalized_value,s.suppression_value)=normalized_address
  )
  into suppression_match;

  select p.preference_status
  into preference_status_value
  from public.communication_preferences p
  where p.organization_id=requested_organization_id
    and (requested_lead_id is null or p.lead_id=requested_lead_id)
    and p.channel_code=requested_channel_code
    and p.message_type in (requested_message_type,'all')
    and (p.expires_at is null or p.expires_at>now())
  order by
    case p.preference_status
      when 'opted_out' then 0
      when 'restricted' then 1
      when 'opted_in' then 2
      else 3
    end,
    p.updated_at desc
  limit 1;

  return jsonb_build_object(
    'eligible',
    not suppression_match
      and coalesce(preference_status_value,'unknown') not in ('opted_out','restricted'),
    'normalized_address',normalized_address,
    'suppressed',suppression_match,
    'preference_status',coalesce(preference_status_value,'unknown'),
    'reason',
    case
      when suppression_match then 'Recipient is suppressed'
      when preference_status_value='opted_out' then 'Recipient opted out'
      when preference_status_value='restricted' then 'Recipient communication is restricted'
      else null
    end
  );
end;
$$;

revoke all on function public.check_communication_eligibility(uuid,text,text,text,uuid) from public;
grant execute on function public.check_communication_eligibility(uuid,text,text,text,uuid) to authenticated,service_role;

-- ============================================================
-- 29. CREATE MESSAGE JOB
-- ============================================================

create or replace function public.create_communication_message(
  requested_organization_id uuid,
  requested_channel_code text,
  requested_recipient_address text,
  requested_lead_id uuid default null,
  requested_template_id uuid default null,
  requested_provider_connection_id uuid default null,
  requested_subject text default null,
  requested_body text default null,
  requested_variables jsonb default '{}'::jsonb,
  requested_message_type text default 'transactional',
  requested_source_type text default 'manual',
  requested_source_reference text default null,
  requested_idempotency_key text default null,
  requested_priority integer default 100,
  requested_scheduled_at timestamptz default null,
  requested_workflow_execution_id uuid default null,
  requested_assignment_id uuid default null
)
returns public.communication_message_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_job public.communication_message_jobs;
  connection_record public.communication_provider_connections;
  template_record public.communication_templates;
  eligibility jsonb;
  created_job public.communication_message_jobs;
  normalized_address text;
  effective_subject text;
  effective_body text;
begin
  if auth.role()<>'service_role'
    and not public.has_organization_permission(requested_organization_id,'communication.send') then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_job
    from public.communication_message_jobs j
    where j.organization_id=requested_organization_id
      and j.idempotency_key=requested_idempotency_key
    limit 1;

    if found then
      return existing_job;
    end if;
  end if;

  connection_record := public.resolve_communication_connection(
    requested_organization_id,
    requested_channel_code,
    requested_provider_connection_id
  );

  if requested_template_id is not null then
    select *
    into template_record
    from public.communication_templates t
    where t.id=requested_template_id
      and (t.organization_id is null or t.organization_id=requested_organization_id)
      and t.channel_code=requested_channel_code
      and t.status in ('approved','active');

    if not found then
      raise exception 'Approved communication template not found';
    end if;
  end if;

  eligibility := public.check_communication_eligibility(
    requested_organization_id,
    requested_channel_code,
    requested_recipient_address,
    requested_message_type,
    requested_lead_id
  );

  normalized_address := eligibility->>'normalized_address';

  effective_subject := coalesce(requested_subject,template_record.subject_template);
  effective_body := coalesce(requested_body,template_record.body_template);

  if effective_body is null then
    raise exception 'Message body is required';
  end if;

  insert into public.communication_message_jobs (
    organization_id,lead_id,provider_connection_id,template_id,
    workflow_execution_id,assignment_id,
    channel_code,direction,message_type,source_type,source_reference,
    idempotency_key,priority,status,subject,body,rendered_subject,
    rendered_body,variables,scheduled_at,queued_at,created_by,updated_by
  )
  values (
    requested_organization_id,requested_lead_id,connection_record.id,
    requested_template_id,requested_workflow_execution_id,requested_assignment_id,
    requested_channel_code,'outbound',requested_message_type,
    requested_source_type,requested_source_reference,
    requested_idempotency_key,requested_priority,
    case
      when coalesce((eligibility->>'eligible')::boolean,false)=false then 'suppressed'
      when requested_scheduled_at is not null and requested_scheduled_at>now() then 'scheduled'
      else 'queued'
    end,
    effective_subject,effective_body,effective_subject,effective_body,
    coalesce(requested_variables,'{}'::jsonb),
    requested_scheduled_at,now(),auth.uid(),auth.uid()
  )
  returning * into created_job;

  insert into public.communication_message_recipients (
    organization_id,message_job_id,recipient_type,
    recipient_address,normalized_address,status
  )
  values (
    requested_organization_id,created_job.id,'to',
    requested_recipient_address,normalized_address,
    case
      when created_job.status='suppressed' then 'suppressed'
      else 'valid'
    end
  );

  insert into public.communication_delivery_events (
    organization_id,message_job_id,event_type,event_data
  )
  values (
    requested_organization_id,created_job.id,
    case when created_job.status='suppressed' then 'suppressed' else 'created' end,
    jsonb_build_object('eligibility',eligibility)
  );

  return created_job;
end;
$$;

revoke all on function public.create_communication_message(
  uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,text,text,text,integer,timestamptz,uuid,uuid
) from public;

grant execute on function public.create_communication_message(
  uuid,text,text,uuid,uuid,uuid,text,text,jsonb,text,text,text,text,integer,timestamptz,uuid,uuid
) to authenticated,service_role;

-- ============================================================
-- 30. CLAIM MESSAGE JOB
-- ============================================================

create or replace function public.claim_communication_message(
  requested_worker_id text,
  requested_channel_code text default null,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.communication_message_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.communication_message_jobs;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may claim communication jobs';
  end if;

  select *
  into target_job
  from public.communication_message_jobs j
  where j.status in ('pending','queued','scheduled','failed')
    and (j.scheduled_at is null or j.scheduled_at<=now())
    and (j.next_retry_at is null or j.next_retry_at<=now())
    and (j.expires_at is null or j.expires_at>now())
    and j.attempts<j.maximum_attempts
    and (requested_channel_code is null or j.channel_code=requested_channel_code)
    and (requested_organization_id is null or j.organization_id=requested_organization_id)
  order by j.priority,coalesce(j.scheduled_at,j.queued_at),j.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.communication_message_jobs
  set
    status='sending',
    attempts=attempts+1,
    sending_started_at=now(),
    metadata=metadata||jsonb_build_object(
      'worker_id',requested_worker_id,
      'lock_token',gen_random_uuid()::text,
      'lock_expires_at',now()+make_interval(secs=>greatest(requested_lock_seconds,1))
    ),
    updated_at=now()
  where id=target_job.id
  returning * into target_job;

  return target_job;
end;
$$;

revoke all on function public.claim_communication_message(text,text,uuid,integer) from public;
grant execute on function public.claim_communication_message(text,text,uuid,integer) to service_role;

-- ============================================================
-- 31. MARK SENT / FAILED
-- ============================================================

create or replace function public.mark_communication_message_sent(
  requested_message_job_id uuid,
  requested_provider_message_id text,
  requested_provider_status text default 'sent',
  requested_provider_response jsonb default '{}'::jsonb
)
returns public.communication_message_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.communication_message_jobs;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may update provider delivery';
  end if;

  update public.communication_message_jobs
  set
    status='sent',
    provider_message_id=requested_provider_message_id,
    provider_status=requested_provider_status,
    provider_response=coalesce(requested_provider_response,'{}'::jsonb),
    sent_at=now(),
    error_code=null,
    error_message=null,
    error_data='{}'::jsonb,
    updated_at=now()
  where id=requested_message_job_id
  returning * into target_job;

  if not found then
    raise exception 'Communication message job not found';
  end if;

  update public.communication_message_recipients
  set status='sent'
  where message_job_id=target_job.id
    and status in ('pending','valid');

  insert into public.communication_delivery_events (
    organization_id,message_job_id,event_type,provider_status,event_data
  )
  values (
    target_job.organization_id,target_job.id,'sent',
    requested_provider_status,coalesce(requested_provider_response,'{}'::jsonb)
  );

  return target_job;
end;
$$;

create or replace function public.mark_communication_message_failed(
  requested_message_job_id uuid,
  requested_error_code text,
  requested_error_message text,
  requested_error_data jsonb default '{}'::jsonb,
  requested_retry_delay_seconds integer default 60
)
returns public.communication_message_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.communication_message_jobs;
  next_status text;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may fail communication jobs';
  end if;

  select *
  into target_job
  from public.communication_message_jobs
  where id=requested_message_job_id
  for update;

  if not found then
    raise exception 'Communication message job not found';
  end if;

  next_status := case
    when target_job.attempts>=target_job.maximum_attempts then 'failed'
    else 'failed'
  end;

  update public.communication_message_jobs
  set
    status=next_status,
    failed_at=now(),
    next_retry_at=case
      when attempts<maximum_attempts
        then now()+make_interval(secs=>greatest(requested_retry_delay_seconds,1))
      else null
    end,
    error_code=requested_error_code,
    error_message=requested_error_message,
    error_data=coalesce(requested_error_data,'{}'::jsonb),
    updated_at=now()
  where id=target_job.id
  returning * into target_job;

  insert into public.communication_delivery_events (
    organization_id,message_job_id,event_type,event_data
  )
  values (
    target_job.organization_id,target_job.id,'failed',
    jsonb_build_object(
      'error_code',requested_error_code,
      'error_message',requested_error_message,
      'error_data',coalesce(requested_error_data,'{}'::jsonb)
    )
  );

  if target_job.attempts<target_job.maximum_attempts then
    insert into public.communication_retry_queue (
      organization_id,message_job_id,status,retry_attempt,
      maximum_attempts,retry_strategy,retry_delay_seconds,
      scheduled_at,error_code,error_message,error_data
    )
    values (
      target_job.organization_id,target_job.id,'pending',
      target_job.attempts+1,target_job.maximum_attempts,
      'exponential',requested_retry_delay_seconds,
      target_job.next_retry_at,requested_error_code,
      requested_error_message,coalesce(requested_error_data,'{}'::jsonb)
    )
    on conflict (message_job_id)
    where status in ('pending','claimed','processing')
    do nothing;
  end if;

  return target_job;
end;
$$;

revoke all on function public.mark_communication_message_sent(uuid,text,text,jsonb) from public;
revoke all on function public.mark_communication_message_failed(uuid,text,text,jsonb,integer) from public;
grant execute on function public.mark_communication_message_sent(uuid,text,text,jsonb) to service_role;
grant execute on function public.mark_communication_message_failed(uuid,text,text,jsonb,integer) to service_role;

-- ============================================================
-- 32. UPDATE DELIVERY STATUS
-- ============================================================

create or replace function public.update_communication_delivery_status(
  requested_message_job_id uuid,
  requested_event_type text,
  requested_provider_event_id text default null,
  requested_provider_status text default null,
  requested_event_at timestamptz default now(),
  requested_event_data jsonb default '{}'::jsonb
)
returns public.communication_message_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.communication_message_jobs;
begin
  if requested_event_type not in (
    'sent','delivered','read','received','processed','failed',
    'bounced','complained','suppressed','cancelled','expired','clicked','opened'
  ) then
    raise exception 'Unsupported delivery event type';
  end if;

  select *
  into target_job
  from public.communication_message_jobs
  where id=requested_message_job_id
  for update;

  if not found then
    raise exception 'Communication message job not found';
  end if;

  insert into public.communication_delivery_events (
    organization_id,message_job_id,event_type,provider_event_id,
    provider_status,event_at,event_data
  )
  values (
    target_job.organization_id,target_job.id,requested_event_type,
    requested_provider_event_id,requested_provider_status,
    coalesce(requested_event_at,now()),
    coalesce(requested_event_data,'{}'::jsonb)
  )
  on conflict (organization_id,provider_event_id)
  where provider_event_id is not null
  do nothing;

  update public.communication_message_jobs
  set
    status=case
      when requested_event_type='delivered' then 'delivered'
      when requested_event_type='read' then 'read'
      when requested_event_type='received' then 'received'
      when requested_event_type='processed' then 'processed'
      when requested_event_type in ('failed','bounced','complained') then 'failed'
      when requested_event_type='suppressed' then 'suppressed'
      when requested_event_type='cancelled' then 'cancelled'
      when requested_event_type='expired' then 'expired'
      else status
    end,
    delivered_at=case when requested_event_type='delivered' then requested_event_at else delivered_at end,
    read_at=case when requested_event_type='read' then requested_event_at else read_at end,
    failed_at=case when requested_event_type in ('failed','bounced','complained') then requested_event_at else failed_at end,
    provider_status=coalesce(requested_provider_status,provider_status),
    updated_at=now()
  where id=target_job.id
  returning * into target_job;

  update public.communication_message_recipients
  set status=case
    when requested_event_type='delivered' then 'delivered'
    when requested_event_type='read' then 'read'
    when requested_event_type in ('failed','bounced','complained') then 'failed'
    else status
  end
  where message_job_id=target_job.id;

  return target_job;
end;
$$;

revoke all on function public.update_communication_delivery_status(
  uuid,text,text,text,timestamptz,jsonb
) from public;

grant execute on function public.update_communication_delivery_status(
  uuid,text,text,text,timestamptz,jsonb
) to service_role;

-- ============================================================
-- 33. CREATE INBOUND MESSAGE
-- ============================================================

create or replace function public.create_inbound_communication_message(
  requested_organization_id uuid,
  requested_channel_code text,
  requested_sender_address text,
  requested_body text,
  requested_provider_connection_id uuid default null,
  requested_provider_message_id text default null,
  requested_conversation_key text default null,
  requested_lead_id uuid default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.communication_message_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  connection_record public.communication_provider_connections;
  conversation_record public.communication_conversations;
  created_job public.communication_message_jobs;
  normalized_address text;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may create inbound messages';
  end if;

  connection_record := public.resolve_communication_connection(
    requested_organization_id,requested_channel_code,requested_provider_connection_id
  );

  normalized_address :=
    case
      when requested_channel_code in ('whatsapp','sms')
        then public.normalize_communication_phone(requested_sender_address,'+91')
      when requested_channel_code='email'
        then public.normalize_communication_email(requested_sender_address)
      else requested_sender_address
    end;

  insert into public.communication_conversations (
    organization_id,lead_id,channel_code,provider_connection_id,
    external_conversation_id,conversation_key,status,
    last_message_at,last_inbound_at,unread_count,metadata
  )
  values (
    requested_organization_id,requested_lead_id,requested_channel_code,
    connection_record.id,requested_conversation_key,
    coalesce(requested_conversation_key,normalized_address),
    'open',now(),now(),1,coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (organization_id,channel_code,conversation_key)
  do update set
    lead_id=coalesce(excluded.lead_id,communication_conversations.lead_id),
    last_message_at=now(),
    last_inbound_at=now(),
    unread_count=communication_conversations.unread_count+1,
    updated_at=now()
  returning * into conversation_record;

  insert into public.communication_message_jobs (
    organization_id,lead_id,conversation_id,provider_connection_id,
    channel_code,direction,message_type,source_type,
    status,body,rendered_body,provider_message_id,
    provider_status,metadata,created_at,updated_at
  )
  values (
    requested_organization_id,requested_lead_id,conversation_record.id,
    connection_record.id,requested_channel_code,'inbound','service',
    'webhook','received',requested_body,requested_body,
    requested_provider_message_id,'received',
    coalesce(requested_metadata,'{}'::jsonb),now(),now()
  )
  returning * into created_job;

  insert into public.communication_message_recipients (
    organization_id,message_job_id,recipient_type,
    recipient_address,normalized_address,status
  )
  values (
    requested_organization_id,created_job.id,'sender',
    requested_sender_address,normalized_address,'delivered'
  );

  insert into public.communication_delivery_events (
    organization_id,message_job_id,event_type,event_data
  )
  values (
    requested_organization_id,created_job.id,'received',
    coalesce(requested_metadata,'{}'::jsonb)
  );

  return created_job;
end;
$$;

revoke all on function public.create_inbound_communication_message(
  uuid,text,text,text,uuid,text,text,uuid,jsonb
) from public;

grant execute on function public.create_inbound_communication_message(
  uuid,text,text,text,uuid,text,text,uuid,jsonb
) to service_role;

-- ============================================================
-- 34. PUBLISH EVENT
-- ============================================================

create or replace function public.publish_communication_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_message_job_id uuid default null,
  requested_campaign_id uuid default null,
  requested_sequence_enrollment_id uuid default null,
  requested_lead_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.communication_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.communication_event_outbox;
  created_event public.communication_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.communication_event_outbox e
    where e.organization_id=requested_organization_id
      and e.idempotency_key=requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.communication_event_outbox (
    organization_id,message_job_id,campaign_id,sequence_enrollment_id,
    lead_id,event_name,destination,status,priority,idempotency_key,
    correlation_id,trace_id,payload,available_at
  )
  values (
    requested_organization_id,requested_message_job_id,requested_campaign_id,
    requested_sequence_enrollment_id,requested_lead_id,requested_event_name,
    requested_destination,'pending',requested_priority,requested_idempotency_key,
    requested_correlation_id,requested_trace_id,
    coalesce(requested_payload,'{}'::jsonb),
    coalesce(requested_available_at,now())
  )
  returning * into created_event;

  return created_event;
end;
$$;

revoke all on function public.publish_communication_event(
  uuid,text,jsonb,text,uuid,uuid,uuid,uuid,integer,text,text,text,timestamptz
) from public;

grant execute on function public.publish_communication_event(
  uuid,text,jsonb,text,uuid,uuid,uuid,uuid,integer,text,text,text,timestamptz
) to authenticated,service_role;

-- ============================================================
-- 35. MESSAGE EVENT TRIGGER
-- ============================================================

create or replace function public.emit_communication_message_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload_data jsonb;
begin
  if tg_op='UPDATE'
    and new.status is not distinct from old.status
    and new.provider_status is not distinct from old.provider_status then
    return new;
  end if;

  payload_data := jsonb_build_object(
    'organization_id',new.organization_id,
    'message_job_id',new.id,
    'lead_id',new.lead_id,
    'conversation_id',new.conversation_id,
    'channel_code',new.channel_code,
    'direction',new.direction,
    'message_type',new.message_type,
    'status',new.status,
    'provider_message_id',new.provider_message_id,
    'provider_status',new.provider_status,
    'sent_at',new.sent_at,
    'delivered_at',new.delivered_at,
    'read_at',new.read_at
  );

  perform public.publish_communication_event(
    new.organization_id,
    'communication.message.'||new.status,
    payload_data,
    'workflow_engine',
    new.id,null,null,new.lead_id,
    case when new.status in ('failed','suppressed') then 10 else 50 end,
    'communication-workflow:'||new.id::text||':'||new.status,
    new.id::text,null,now()
  );

  perform public.publish_communication_event(
    new.organization_id,
    'communication.message.'||new.status,
    payload_data,
    'n8n',
    new.id,null,null,new.lead_id,
    50,
    'communication-n8n:'||new.id::text||':'||new.status,
    new.id::text,null,now()
  );

  return new;
end;
$$;

drop trigger if exists communication_message_jobs_emit_events
on public.communication_message_jobs;

create trigger communication_message_jobs_emit_events
after insert or update on public.communication_message_jobs
for each row
execute function public.emit_communication_message_events();

-- ============================================================
-- 36. CLAIM / COMPLETE OUTBOX EVENT
-- ============================================================

create or replace function public.claim_communication_event(
  requested_worker_id text,
  requested_destination text default null,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.communication_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_event public.communication_event_outbox;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may claim communication events';
  end if;

  select *
  into target_event
  from public.communication_event_outbox e
  where e.status in ('pending','failed')
    and e.available_at<=now()
    and e.delivery_attempts<e.maximum_attempts
    and (requested_destination is null or e.destination=requested_destination)
    and (requested_organization_id is null or e.organization_id=requested_organization_id)
  order by e.priority,e.available_at,e.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.communication_event_outbox
  set
    status='claimed',
    claimed_at=now(),
    claimed_by=requested_worker_id,
    lock_token=gen_random_uuid()::text,
    lock_expires_at=now()+make_interval(secs=>greatest(requested_lock_seconds,1)),
    delivery_attempts=delivery_attempts+1,
    updated_at=now()
  where id=target_event.id
  returning * into target_event;

  return target_event;
end;
$$;

create or replace function public.complete_communication_event(
  requested_event_id uuid,
  requested_lock_token text
)
returns public.communication_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_event public.communication_event_outbox;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may complete communication events';
  end if;

  select *
  into target_event
  from public.communication_event_outbox
  where id=requested_event_id
  for update;

  if not found then
    raise exception 'Communication event not found';
  end if;

  if target_event.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid communication event lock token';
  end if;

  update public.communication_event_outbox
  set
    status='delivered',
    delivered_at=now(),
    claimed_at=null,
    claimed_by=null,
    lock_token=null,
    lock_expires_at=null,
    updated_at=now()
  where id=requested_event_id
  returning * into target_event;

  return target_event;
end;
$$;

revoke all on function public.claim_communication_event(text,text,uuid,integer) from public;
revoke all on function public.complete_communication_event(uuid,text) from public;
grant execute on function public.claim_communication_event(text,text,uuid,integer) to service_role;
grant execute on function public.complete_communication_event(uuid,text) to service_role;

-- ============================================================
-- 37. CAMPAIGN RECIPIENT QUEUE PROCESSOR
-- ============================================================

create or replace function public.queue_communication_campaign_recipient(
  requested_campaign_recipient_id uuid
)
returns public.communication_message_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient_record public.communication_campaign_recipients;
  campaign_record public.communication_campaigns;
  created_job public.communication_message_jobs;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may queue campaign recipients';
  end if;

  select *
  into recipient_record
  from public.communication_campaign_recipients
  where id=requested_campaign_recipient_id
  for update;

  if not found then
    raise exception 'Campaign recipient not found';
  end if;

  if recipient_record.status not in ('pending','queued') then
    if recipient_record.message_job_id is not null then
      select *
      into created_job
      from public.communication_message_jobs
      where id=recipient_record.message_job_id;
      return created_job;
    end if;
    raise exception 'Campaign recipient is not queueable';
  end if;

  select *
  into campaign_record
  from public.communication_campaigns
  where id=recipient_record.campaign_id;

  if campaign_record.status not in ('scheduled','running') then
    raise exception 'Campaign is not active';
  end if;

  created_job := public.create_communication_message(
    campaign_record.organization_id,
    campaign_record.channel_code,
    recipient_record.recipient_address,
    recipient_record.lead_id,
    campaign_record.template_id,
    campaign_record.provider_connection_id,
    null,
    null,
    recipient_record.variables,
    'marketing',
    'campaign',
    campaign_record.id::text,
    'campaign-recipient:'||recipient_record.id::text,
    100,
    recipient_record.scheduled_at,
    null,
    null
  );

  update public.communication_campaign_recipients
  set
    status=case when created_job.status='suppressed' then 'suppressed' else 'queued' end,
    message_job_id=created_job.id,
    processed_at=now()
  where id=recipient_record.id;

  return created_job;
end;
$$;

revoke all on function public.queue_communication_campaign_recipient(uuid) from public;
grant execute on function public.queue_communication_campaign_recipient(uuid) to service_role;

-- ============================================================
-- 38. SEQUENCE ENROLLMENT
-- ============================================================

create or replace function public.enroll_lead_in_communication_sequence(
  requested_sequence_id uuid,
  requested_lead_id uuid,
  requested_context jsonb default '{}'::jsonb
)
returns public.communication_sequence_enrollments
language plpgsql
security definer
set search_path = ''
as $$
declare
  sequence_record public.communication_sequences;
  enrollment_record public.communication_sequence_enrollments;
  first_step public.communication_sequence_steps;
begin
  select *
  into sequence_record
  from public.communication_sequences
  where id=requested_sequence_id
    and status='active';

  if not found then
    raise exception 'Active communication sequence not found';
  end if;

  if auth.role()<>'service_role'
    and not public.has_organization_permission(sequence_record.organization_id,'communication.manage_sequences') then
    raise exception 'Permission denied';
  end if;

  select *
  into first_step
  from public.communication_sequence_steps
  where sequence_id=sequence_record.id
    and status='active'
  order by step_order
  limit 1;

  if not found then
    raise exception 'Communication sequence has no active steps';
  end if;

  insert into public.communication_sequence_enrollments (
    organization_id,sequence_id,lead_id,status,current_step_order,
    enrolled_at,next_step_at,enrollment_context,created_by
  )
  values (
    sequence_record.organization_id,sequence_record.id,requested_lead_id,
    'active',first_step.step_order,now(),
    now()+case first_step.delay_unit
      when 'minutes' then make_interval(mins=>first_step.delay_value)
      when 'hours' then make_interval(hours=>first_step.delay_value)
      when 'days' then make_interval(days=>first_step.delay_value)
      when 'weeks' then make_interval(days=>first_step.delay_value*7)
    end,
    coalesce(requested_context,'{}'::jsonb),
    auth.uid()
  )
  on conflict (sequence_id,lead_id)
  do update set
    status='active',
    current_step_order=excluded.current_step_order,
    next_step_at=excluded.next_step_at,
    enrollment_context=excluded.enrollment_context,
    updated_at=now()
  returning * into enrollment_record;

  return enrollment_record;
end;
$$;

revoke all on function public.enroll_lead_in_communication_sequence(uuid,uuid,jsonb) from public;
grant execute on function public.enroll_lead_in_communication_sequence(uuid,uuid,jsonb) to authenticated,service_role;

-- ============================================================
-- 39. ANALYTICS VIEWS
-- ============================================================

create or replace view public.communication_message_dashboard
with (security_invoker=true) as
select
  organization_id,
  channel_code,
  date_trunc('day',created_at)::date as communication_date,
  count(*) as total_messages,
  count(*) filter (where direction='outbound') as outbound_count,
  count(*) filter (where direction='inbound') as inbound_count,
  count(*) filter (where status='sent') as sent_count,
  count(*) filter (where status='delivered') as delivered_count,
  count(*) filter (where status='read') as read_count,
  count(*) filter (where status='failed') as failed_count,
  count(*) filter (where status='suppressed') as suppressed_count,
  round(
    (count(*) filter (where status in ('delivered','read'))::numeric
      / nullif(count(*) filter (where direction='outbound'),0))*100,
    2
  ) as delivery_rate,
  round(
    (count(*) filter (where status='read')::numeric
      / nullif(count(*) filter (where status in ('delivered','read')),0))*100,
    2
  ) as read_rate
from public.communication_message_jobs
group by organization_id,channel_code,date_trunc('day',created_at)::date;

create or replace view public.communication_campaign_dashboard
with (security_invoker=true) as
select
  c.organization_id,
  c.id as campaign_id,
  c.campaign_name,
  c.channel_code,
  c.status,
  c.total_recipients,
  count(r.id) as recipient_count,
  count(r.id) filter (where r.status='queued') as queued_count,
  count(r.id) filter (where r.status='sent') as sent_count,
  count(r.id) filter (where r.status='delivered') as delivered_count,
  count(r.id) filter (where r.status='read') as read_count,
  count(r.id) filter (where r.status='failed') as failed_count,
  count(r.id) filter (where r.status='suppressed') as suppressed_count
from public.communication_campaigns c
left join public.communication_campaign_recipients r
  on r.campaign_id=c.id
group by c.id;

create or replace view public.communication_provider_health
with (security_invoker=true) as
select
  c.organization_id,
  c.id as provider_connection_id,
  p.provider_code,
  p.provider_name,
  c.channel_code,
  c.status,
  c.is_default,
  c.last_health_check_at,
  c.last_health_status,
  c.last_error,
  count(j.id) filter (where j.created_at>=now()-interval '24 hours') as messages_24h,
  count(j.id) filter (
    where j.created_at>=now()-interval '24 hours'
      and j.status='failed'
  ) as failed_messages_24h
from public.communication_provider_connections c
join public.communication_providers p
  on p.id=c.provider_id
left join public.communication_message_jobs j
  on j.provider_connection_id=c.id
group by c.id,p.id;

create or replace view public.communication_conversation_dashboard
with (security_invoker=true) as
select
  organization_id,
  channel_code,
  count(*) as total_conversations,
  count(*) filter (where status='open') as open_conversations,
  count(*) filter (where status='pending') as pending_conversations,
  count(*) filter (where unread_count>0) as unread_conversations,
  sum(unread_count) as total_unread_messages,
  max(last_message_at) as latest_message_at
from public.communication_conversations
group by organization_id,channel_code;

grant select on
  public.communication_message_dashboard,
  public.communication_campaign_dashboard,
  public.communication_provider_health,
  public.communication_conversation_dashboard
to authenticated,service_role;

-- ============================================================
-- 40. HEALTH CHECK
-- ============================================================

create or replace function public.get_communication_engine_health(
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
      or not public.has_organization_permission(requested_organization_id,'communication.view_logs')
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),
    'active_connections',(
      select count(*)
      from public.communication_provider_connections c
      where c.status='active'
        and (requested_organization_id is null or c.organization_id=requested_organization_id)
    ),
    'queued_messages',(
      select count(*)
      from public.communication_message_jobs j
      where j.status in ('pending','queued','scheduled')
        and (requested_organization_id is null or j.organization_id=requested_organization_id)
    ),
    'sending_messages',(
      select count(*)
      from public.communication_message_jobs j
      where j.status='sending'
        and (requested_organization_id is null or j.organization_id=requested_organization_id)
    ),
    'failed_messages_24h',(
      select count(*)
      from public.communication_message_jobs j
      where j.status='failed'
        and j.updated_at>=now()-interval '24 hours'
        and (requested_organization_id is null or j.organization_id=requested_organization_id)
    ),
    'pending_retries',(
      select count(*)
      from public.communication_retry_queue r
      where r.status='pending'
        and (requested_organization_id is null or r.organization_id=requested_organization_id)
    ),
    'pending_webhooks',(
      select count(*)
      from public.communication_webhook_inbox w
      where w.status in ('received','failed')
        and (requested_organization_id is null or w.organization_id=requested_organization_id)
    ),
    'pending_outbox_events',(
      select count(*)
      from public.communication_event_outbox e
      where e.status in ('pending','failed')
        and (requested_organization_id is null or e.organization_id=requested_organization_id)
    ),
    'active_sequences',(
      select count(*)
      from public.communication_sequences s
      where s.status='active'
        and (requested_organization_id is null or s.organization_id=requested_organization_id)
    ),
    'running_campaigns',(
      select count(*)
      from public.communication_campaigns c
      where c.status='running'
        and (requested_organization_id is null or c.organization_id=requested_organization_id)
    )
  );
end;
$$;

revoke all on function public.get_communication_engine_health(uuid) from public;
grant execute on function public.get_communication_engine_health(uuid) to authenticated,service_role;

-- ============================================================
-- 41. RLS
-- ============================================================

alter table public.communication_channels enable row level security;
alter table public.communication_providers enable row level security;
alter table public.communication_provider_connections enable row level security;
alter table public.communication_template_categories enable row level security;
alter table public.communication_templates enable row level security;
alter table public.communication_template_variables enable row level security;
alter table public.communication_contact_endpoints enable row level security;
alter table public.communication_preferences enable row level security;
alter table public.communication_suppression_list enable row level security;
alter table public.communication_conversations enable row level security;
alter table public.communication_message_jobs enable row level security;
alter table public.communication_message_recipients enable row level security;
alter table public.communication_message_attachments enable row level security;
alter table public.communication_delivery_events enable row level security;
alter table public.communication_campaigns enable row level security;
alter table public.communication_campaign_recipients enable row level security;
alter table public.communication_sequences enable row level security;
alter table public.communication_sequence_steps enable row level security;
alter table public.communication_sequence_enrollments enable row level security;
alter table public.communication_retry_queue enable row level security;
alter table public.communication_webhook_inbox enable row level security;
alter table public.communication_event_outbox enable row level security;
alter table public.communication_logs enable row level security;

drop policy if exists communication_channels_authenticated_select
on public.communication_channels;

create policy communication_channels_authenticated_select
on public.communication_channels
for select to authenticated
using (true);

drop policy if exists communication_providers_authenticated_select
on public.communication_providers;

create policy communication_providers_authenticated_select
on public.communication_providers
for select to authenticated
using (true);

drop policy if exists communication_template_categories_authenticated_select
on public.communication_template_categories;

create policy communication_template_categories_authenticated_select
on public.communication_template_categories
for select to authenticated
using (true);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'communication_provider_connections',
    'communication_templates',
    'communication_contact_endpoints',
    'communication_preferences',
    'communication_suppression_list',
    'communication_conversations',
    'communication_message_jobs',
    'communication_message_recipients',
    'communication_message_attachments',
    'communication_delivery_events',
    'communication_campaigns',
    'communication_campaign_recipients',
    'communication_sequences',
    'communication_sequence_steps',
    'communication_sequence_enrollments',
    'communication_retry_queue',
    'communication_webhook_inbox',
    'communication_event_outbox',
    'communication_logs'
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
         public.has_organization_permission(organization_id,''communication.view'')
         or public.has_organization_permission(organization_id,''communication.view_all'')
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

drop policy if exists communication_provider_connections_write
on public.communication_provider_connections;

create policy communication_provider_connections_write
on public.communication_provider_connections
for all to authenticated
using (public.has_organization_permission(organization_id,'communication.manage_connections'))
with check (public.has_organization_permission(organization_id,'communication.manage_connections'));

drop policy if exists communication_templates_write
on public.communication_templates;

create policy communication_templates_write
on public.communication_templates
for all to authenticated
using (
  organization_id is not null
  and public.has_organization_permission(organization_id,'communication.manage_templates')
)
with check (
  organization_id is not null
  and public.has_organization_permission(organization_id,'communication.manage_templates')
);

drop policy if exists communication_campaigns_write
on public.communication_campaigns;

create policy communication_campaigns_write
on public.communication_campaigns
for all to authenticated
using (public.has_organization_permission(organization_id,'communication.manage_campaigns'))
with check (public.has_organization_permission(organization_id,'communication.manage_campaigns'));

drop policy if exists communication_sequences_write
on public.communication_sequences;

create policy communication_sequences_write
on public.communication_sequences
for all to authenticated
using (public.has_organization_permission(organization_id,'communication.manage_sequences'))
with check (public.has_organization_permission(organization_id,'communication.manage_sequences'));

drop policy if exists communication_preferences_write
on public.communication_preferences;

create policy communication_preferences_write
on public.communication_preferences
for all to authenticated
using (public.has_organization_permission(organization_id,'communication.manage_preferences'))
with check (public.has_organization_permission(organization_id,'communication.manage_preferences'));

-- ============================================================
-- 42. GRANTS
-- ============================================================

grant select on
  public.communication_channels,
  public.communication_providers,
  public.communication_template_categories
to authenticated;

grant select on
  public.communication_provider_connections,
  public.communication_templates,
  public.communication_template_variables,
  public.communication_contact_endpoints,
  public.communication_preferences,
  public.communication_suppression_list,
  public.communication_conversations,
  public.communication_message_jobs,
  public.communication_message_recipients,
  public.communication_message_attachments,
  public.communication_delivery_events,
  public.communication_campaigns,
  public.communication_campaign_recipients,
  public.communication_sequences,
  public.communication_sequence_steps,
  public.communication_sequence_enrollments,
  public.communication_retry_queue,
  public.communication_webhook_inbox,
  public.communication_event_outbox,
  public.communication_logs
to authenticated;

grant insert,update,delete on
  public.communication_provider_connections,
  public.communication_templates,
  public.communication_template_variables,
  public.communication_contact_endpoints,
  public.communication_preferences,
  public.communication_suppression_list,
  public.communication_campaigns,
  public.communication_campaign_recipients,
  public.communication_sequences,
  public.communication_sequence_steps,
  public.communication_sequence_enrollments
to authenticated;

grant all on
  public.communication_channels,
  public.communication_providers,
  public.communication_provider_connections,
  public.communication_template_categories,
  public.communication_templates,
  public.communication_template_variables,
  public.communication_contact_endpoints,
  public.communication_preferences,
  public.communication_suppression_list,
  public.communication_conversations,
  public.communication_message_jobs,
  public.communication_message_recipients,
  public.communication_message_attachments,
  public.communication_delivery_events,
  public.communication_campaigns,
  public.communication_campaign_recipients,
  public.communication_sequences,
  public.communication_sequence_steps,
  public.communication_sequence_enrollments,
  public.communication_retry_queue,
  public.communication_webhook_inbox,
  public.communication_event_outbox,
  public.communication_logs
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
    'communication_channels',
    'communication_providers',
    'communication_provider_connections',
    'communication_templates',
    'communication_contact_endpoints',
    'communication_preferences',
    'communication_suppression_list',
    'communication_conversations',
    'communication_message_jobs',
    'communication_message_recipients',
    'communication_message_attachments',
    'communication_delivery_events',
    'communication_campaigns',
    'communication_campaign_recipients',
    'communication_sequences',
    'communication_sequence_steps',
    'communication_sequence_enrollments',
    'communication_retry_queue',
    'communication_webhook_inbox',
    'communication_event_outbox',
    'communication_logs'
  ]
  loop
    if not exists (
      select 1
      from information_schema.tables
      where table_schema='public'
        and table_name=item
    ) then
      missing_items := array_append(missing_items,'table:'||item);
    end if;
  end loop;

  foreach item in array array[
    'check_communication_eligibility',
    'create_communication_message',
    'claim_communication_message',
    'mark_communication_message_sent',
    'mark_communication_message_failed',
    'update_communication_delivery_status',
    'create_inbound_communication_message',
    'publish_communication_event',
    'claim_communication_event',
    'complete_communication_event',
    'queue_communication_campaign_recipient',
    'enroll_lead_in_communication_sequence',
    'get_communication_engine_health'
  ]
  loop
    if not exists (
      select 1
      from information_schema.routines
      where routine_schema='public'
        and routine_name=item
    ) then
      missing_items := array_append(missing_items,'function:'||item);
    end if;
  end loop;

  if cardinality(missing_items)>0 then
    raise exception '013 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 44. MIGRATION AUDIT
-- ============================================================

insert into public.communication_logs (
  organization_id,log_level,event_name,message,log_data
)
select
  o.id,
  'info',
  'migration.013.completed',
  'Communication Engine migration 013 completed',
  jsonb_build_object(
    'migration','013_communication_engine',
    'completed_at',now(),
    'modules',jsonb_build_array(
      'channels',
      'providers',
      'connections',
      'templates',
      'contact_endpoints',
      'preferences',
      'suppression',
      'conversations',
      'messages',
      'recipients',
      'attachments',
      'delivery_events',
      'campaigns',
      'sequences',
      'retry_queue',
      'webhook_inbox',
      'event_outbox',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.communication_logs l
  where l.organization_id=o.id
    and l.event_name='migration.013.completed'
);

commit;