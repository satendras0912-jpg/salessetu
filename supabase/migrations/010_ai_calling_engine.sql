-- ============================================================
-- SalesSetu Enterprise
-- Migration 010: AI Calling Engine
-- File: 010_ai_calling_engine.sql
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   009_workflow_engine_v2.sql
--
-- Core capabilities:
--   • Multi-provider AI calling abstraction
--   • Campaigns, scripts, voices, qualification schemas
--   • Call jobs, attempts, provider events and webhook inbox
--   • Consent, suppression and calling-window enforcement
--   • Transcripts, segments, extracted answers and qualification
--   • Lead scoring, disposition, retries and escalation
--   • Workflow/n8n orchestration hooks
--   • Analytics views, permissions, grants and RLS
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ============================================================
-- 1. RBAC PERMISSIONS
-- Existing permissions schema:
-- permissions(id, module, action, code, description, created_at)
-- ============================================================

insert into public.permissions (module, action, code, description)
select
  permission_data.module,
  permission_data.action,
  permission_data.code,
  permission_data.description
from (
  values
    ('ai_calling','view','ai_calling.view','View AI calling configuration and records'),
    ('ai_calling','create','ai_calling.create','Create AI call campaigns, jobs and templates'),
    ('ai_calling','update','ai_calling.update','Update AI calling configuration and records'),
    ('ai_calling','delete','ai_calling.delete','Delete or archive AI calling records'),
    ('ai_calling','execute','ai_calling.execute','Queue and execute AI calls'),
    ('ai_calling','cancel','ai_calling.cancel','Cancel queued or active AI calls'),
    ('ai_calling','retry','ai_calling.retry','Retry failed AI call attempts'),
    ('ai_calling','manage_providers','ai_calling.manage_providers','Manage AI calling providers and credentials'),
    ('ai_calling','manage_scripts','ai_calling.manage_scripts','Manage call scripts and prompt templates'),
    ('ai_calling','manage_campaigns','ai_calling.manage_campaigns','Manage AI calling campaigns'),
    ('ai_calling','manage_consent','ai_calling.manage_consent','Manage call consent and suppression records'),
    ('ai_calling','review_transcripts','ai_calling.review_transcripts','Review and correct call transcripts'),
    ('ai_calling','review_qualification','ai_calling.review_qualification','Review qualification results and scores'),
    ('ai_calling','view_logs','ai_calling.view_logs','View provider events, webhook events and execution logs'),
    ('ai_calling','view_all','ai_calling.view_all','View all organization AI calling records')
) as permission_data(module, action, code, description)
where not exists (
  select 1
  from public.permissions existing_permission
  where existing_permission.code = permission_data.code
);

-- ============================================================
-- 2. ENUM-LIKE LOOKUP TABLES
-- ============================================================

create table if not exists public.ai_call_dispositions (
  code text primary key,
  display_name text not null,
  category text not null
    check (category in ('connected','not_connected','qualified','unqualified','follow_up','blocked','system')),
  is_terminal boolean not null default true,
  is_success boolean not null default false,
  default_lead_status text,
  description text,
  sort_order integer not null default 100,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

insert into public.ai_call_dispositions
  (code, display_name, category, is_terminal, is_success, default_lead_status, description, sort_order)
values
  ('qualified_hot','Qualified - Hot','qualified',true,true,'hot','High-intent qualified lead',10),
  ('qualified_warm','Qualified - Warm','qualified',true,true,'warm','Medium-intent qualified lead',20),
  ('qualified_cold','Qualified - Cold','qualified',true,true,'cold','Low-intent but valid lead',30),
  ('site_visit_requested','Site Visit Requested','qualified',true,true,'hot','Lead requested a site visit',40),
  ('callback_requested','Callback Requested','follow_up',true,true,'warm','Lead requested a callback',50),
  ('connected_not_interested','Not Interested','unqualified',true,false,'not_interested','Connected but not interested',60),
  ('wrong_number','Wrong Number','blocked',true,false,'invalid','Wrong number or unrelated recipient',70),
  ('duplicate_lead','Duplicate Lead','blocked',true,false,'duplicate','Duplicate lead confirmed during call',80),
  ('fake_lead','Fake Lead','blocked',true,false,'invalid','Fake or fabricated enquiry',90),
  ('do_not_call','Do Not Call','blocked',true,false,'do_not_call','Recipient requested no further calls',100),
  ('no_answer','No Answer','not_connected',true,false,null,'Call was not answered',110),
  ('busy','Busy','not_connected',true,false,null,'Recipient line was busy',120),
  ('voicemail','Voicemail','not_connected',true,false,null,'Call reached voicemail',130),
  ('switched_off','Switched Off','not_connected',true,false,null,'Recipient phone was switched off',140),
  ('network_failure','Network Failure','system',true,false,null,'Telecom or network failure',150),
  ('provider_failure','Provider Failure','system',true,false,null,'AI calling provider failure',160),
  ('cancelled','Cancelled','system',true,false,null,'Call job or attempt cancelled',170),
  ('unknown','Unknown','system',true,false,null,'No reliable final disposition',999)
on conflict (code) do update
set
  display_name = excluded.display_name,
  category = excluded.category,
  is_terminal = excluded.is_terminal,
  is_success = excluded.is_success,
  default_lead_status = excluded.default_lead_status,
  description = excluded.description,
  sort_order = excluded.sort_order;

-- ============================================================
-- 3. PROVIDER ABSTRACTION
-- ============================================================

create table if not exists public.ai_call_providers (
  id uuid primary key default gen_random_uuid(),
  provider_code text not null unique,
  provider_name text not null,
  provider_type text not null default 'voice_ai'
    check (provider_type in ('voice_ai','telephony','hybrid')),
  api_base_url text,
  webhook_signature_type text not null default 'none'
    check (webhook_signature_type in ('none','hmac_sha256','bearer','custom')),
  capabilities jsonb not null default '{}',
  status text not null default 'active'
    check (status in ('active','inactive','deprecated')),
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.ai_call_providers
  (provider_code, provider_name, provider_type, capabilities)
values
  (
    'bland_ai',
    'Bland AI',
    'voice_ai',
    jsonb_build_object(
      'outbound_calls', true,
      'webhooks', true,
      'recordings', true,
      'transcripts', true,
      'custom_voice', true,
      'batch_calls', true
    )
  ),
  (
    'custom_n8n',
    'Custom n8n Voice Orchestrator',
    'hybrid',
    jsonb_build_object(
      'outbound_calls', true,
      'webhooks', true,
      'recordings', false,
      'transcripts', true,
      'custom_voice', true,
      'batch_calls', true
    )
  )
on conflict (provider_code) do update
set
  provider_name = excluded.provider_name,
  provider_type = excluded.provider_type,
  capabilities = excluded.capabilities,
  updated_at = now();

create table if not exists public.ai_call_provider_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid not null references public.ai_call_providers(id) on delete restrict,
  connection_name text not null,
  status text not null default 'active'
    check (status in ('active','inactive','error','revoked')),
  credentials_reference text,
  webhook_secret_reference text,
  outbound_phone_number text,
  default_country_code text not null default '+91',
  default_voice_id text,
  default_language_code text not null default 'hi-IN',
  default_model text,
  api_configuration jsonb not null default '{}',
  rate_limit_per_minute integer not null default 30 check (rate_limit_per_minute > 0),
  concurrent_call_limit integer not null default 5 check (concurrent_call_limit > 0),
  health_status text not null default 'unknown'
    check (health_status in ('unknown','healthy','degraded','unavailable')),
  last_health_check_at timestamptz,
  last_health_error text,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, connection_name)
);

create index if not exists ai_call_provider_connections_org_status_idx
  on public.ai_call_provider_connections (organization_id, status);

-- ============================================================
-- 4. VOICES AND SCRIPT TEMPLATES
-- ============================================================

create table if not exists public.ai_call_voices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  provider_id uuid not null references public.ai_call_providers(id) on delete restrict,
  provider_voice_id text not null,
  voice_name text not null,
  language_code text not null default 'hi-IN',
  gender_label text,
  accent_label text,
  voice_style text,
  is_system_voice boolean not null default false,
  is_active boolean not null default true,
  sample_url text,
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider_id, provider_voice_id, organization_id)
);

create table if not exists public.ai_call_script_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  template_code text not null,
  template_name text not null,
  description text,
  language_code text not null default 'hi-IN',
  script_type text not null default 'qualification'
    check (script_type in ('qualification','follow_up','site_visit','reminder','verification','custom')),
  status text not null default 'draft'
    check (status in ('draft','active','inactive','archived')),
  version_number integer not null default 1 check (version_number > 0),
  opening_message text not null,
  system_prompt text not null,
  objection_handling_prompt text,
  closing_prompt text,
  voicemail_message text,
  variables_schema jsonb not null default '{}',
  compliance_instructions jsonb not null default '{}',
  maximum_call_duration_seconds integer not null default 420
    check (maximum_call_duration_seconds between 30 and 3600),
  silence_timeout_seconds integer not null default 20
    check (silence_timeout_seconds between 5 and 120),
  allow_recording boolean not null default true,
  recording_disclosure_text text,
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, template_code, version_number)
);

create index if not exists ai_call_script_templates_org_status_idx
  on public.ai_call_script_templates (organization_id, status, script_type);

-- ============================================================
-- 5. QUALIFICATION SCHEMAS AND QUESTIONS
-- ============================================================

create table if not exists public.ai_call_qualification_schemas (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  schema_code text not null,
  schema_name text not null,
  description text,
  industry text not null default 'real_estate',
  status text not null default 'draft'
    check (status in ('draft','active','inactive','archived')),
  hot_threshold numeric(8,2) not null default 75,
  warm_threshold numeric(8,2) not null default 45,
  minimum_valid_answers integer not null default 2 check (minimum_valid_answers >= 0),
  disqualifying_rules jsonb not null default '[]',
  scoring_configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, schema_code)
);

create table if not exists public.ai_call_qualification_questions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  qualification_schema_id uuid not null references public.ai_call_qualification_schemas(id) on delete cascade,
  question_code text not null,
  question_text text not null,
  question_type text not null
    check (question_type in ('text','number','currency','date','boolean','single_choice','multi_choice','location','duration')),
  sequence_number integer not null default 0,
  is_required boolean not null default false,
  options jsonb not null default '[]',
  extraction_instructions text,
  validation_rules jsonb not null default '{}',
  scoring_rules jsonb not null default '{}',
  maximum_score numeric(8,2) not null default 0,
  disqualifying_values jsonb not null default '[]',
  lead_field_mapping text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (qualification_schema_id, question_code)
);

create index if not exists ai_call_qualification_questions_schema_seq_idx
  on public.ai_call_qualification_questions (qualification_schema_id, sequence_number);

-- ============================================================
-- 6. CAMPAIGNS
-- ============================================================

create table if not exists public.ai_call_campaigns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  campaign_code text not null,
  campaign_name text not null,
  description text,
  campaign_type text not null default 'qualification'
    check (campaign_type in ('qualification','follow_up','site_visit','reminder','verification','custom')),
  status text not null default 'draft'
    check (status in ('draft','scheduled','active','paused','completed','cancelled','archived')),
  provider_connection_id uuid not null references public.ai_call_provider_connections(id) on delete restrict,
  script_template_id uuid not null references public.ai_call_script_templates(id) on delete restrict,
  qualification_schema_id uuid references public.ai_call_qualification_schemas(id) on delete set null,
  voice_id uuid references public.ai_call_voices(id) on delete set null,
  workflow_id uuid references public.workflow_definitions(id) on delete set null,
  timezone text not null default 'Asia/Kolkata',
  calling_window_start time not null default '09:00',
  calling_window_end time not null default '19:00',
  allowed_weekdays smallint[] not null default array[1,2,3,4,5,6],
  maximum_attempts integer not null default 3 check (maximum_attempts between 1 and 10),
  retry_strategy text not null default 'scheduled'
    check (retry_strategy in ('none','fixed','scheduled','progressive')),
  retry_delays_minutes integer[] not null default array[60,360,1440],
  priority integer not null default 100,
  daily_call_limit integer,
  concurrent_call_limit integer,
  consent_required boolean not null default true,
  stop_on_connected_call boolean not null default true,
  stop_on_do_not_call boolean not null default true,
  auto_update_lead boolean not null default true,
  auto_create_followup boolean not null default true,
  auto_assign_hot_lead boolean not null default true,
  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, campaign_code)
);

create index if not exists ai_call_campaigns_org_status_idx
  on public.ai_call_campaigns (organization_id, status, priority);

-- ============================================================
-- 7. CONSENT, CONTACT PREFERENCES AND SUPPRESSION
-- ============================================================

create table if not exists public.ai_call_consents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete cascade,
  phone_number text not null,
  consent_type text not null default 'outbound_ai_call'
    check (consent_type in ('outbound_ai_call','recording','marketing','follow_up')),
  consent_status text not null
    check (consent_status in ('granted','denied','withdrawn','unknown')),
  consent_source text
    check (consent_source is null or consent_source in ('lead_form','website','whatsapp','verbal','written','import','agent','system')),
  consent_text text,
  evidence_data jsonb not null default '{}',
  granted_at timestamptz,
  withdrawn_at timestamptz,
  expires_at timestamptz,
  captured_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ai_call_consents_org_phone_idx
  on public.ai_call_consents (organization_id, phone_number, consent_type, created_at desc);

create table if not exists public.ai_call_suppression_list (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  phone_number text not null,
  lead_id uuid references public.leads(id) on delete set null,
  suppression_type text not null
    check (suppression_type in ('do_not_call','wrong_number','fraud','complaint','legal','temporary','internal')),
  reason text,
  active_from timestamptz not null default now(),
  active_until timestamptz,
  is_active boolean not null default true,
  source text,
  created_by uuid references auth.users(id) on delete set null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, phone_number, suppression_type)
);

create index if not exists ai_call_suppression_active_idx
  on public.ai_call_suppression_list (organization_id, phone_number)
  where is_active = true;

-- ============================================================
-- 8. CALL JOBS
-- ============================================================

create table if not exists public.ai_call_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  campaign_id uuid references public.ai_call_campaigns(id) on delete set null,
  provider_connection_id uuid not null references public.ai_call_provider_connections(id) on delete restrict,
  script_template_id uuid not null references public.ai_call_script_templates(id) on delete restrict,
  qualification_schema_id uuid references public.ai_call_qualification_schemas(id) on delete set null,
  voice_id uuid references public.ai_call_voices(id) on delete set null,
  lead_id uuid references public.leads(id) on delete cascade,
  workflow_execution_id uuid references public.workflow_executions(id) on delete set null,
  source_type text not null default 'manual'
    check (source_type in ('manual','campaign','workflow','n8n','api','followup','system')),
  source_reference text,
  idempotency_key text,
  status text not null default 'draft'
    check (status in (
      'draft','validation_pending','blocked','queued','scheduled','dispatching',
      'in_progress','completed','partially_completed','failed','cancelled','expired'
    )),
  priority integer not null default 100,
  phone_number text not null,
  country_code text not null default '+91',
  contact_name text,
  language_code text not null default 'hi-IN',
  scheduled_at timestamptz,
  expires_at timestamptz,
  maximum_attempts integer not null default 3 check (maximum_attempts between 1 and 10),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz,
  final_disposition_code text references public.ai_call_dispositions(code) on delete set null,
  qualification_status text
    check (qualification_status is null or qualification_status in ('unprocessed','processing','qualified_hot','qualified_warm','qualified_cold','unqualified','manual_review','failed')),
  qualification_score numeric(8,2),
  consent_status text
    check (consent_status is null or consent_status in ('granted','denied','withdrawn','unknown','not_required')),
  blocked_reason text,
  script_variables jsonb not null default '{}',
  call_context jsonb not null default '{}',
  result_data jsonb not null default '{}',
  error_data jsonb not null default '{}',
  metadata jsonb not null default '{}',
  queued_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancellation_reason text,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists ai_call_jobs_idempotency_idx
  on public.ai_call_jobs (organization_id, idempotency_key)
  where idempotency_key is not null;

create index if not exists ai_call_jobs_queue_idx
  on public.ai_call_jobs (status, priority, scheduled_at, created_at)
  where status in ('queued','scheduled');

create index if not exists ai_call_jobs_lead_idx
  on public.ai_call_jobs (organization_id, lead_id, created_at desc);

-- ============================================================
-- 9. CALL ATTEMPTS
-- ============================================================

create table if not exists public.ai_call_attempts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  call_job_id uuid not null references public.ai_call_jobs(id) on delete cascade,
  attempt_number integer not null check (attempt_number > 0),
  provider_connection_id uuid not null references public.ai_call_provider_connections(id) on delete restrict,
  provider_call_id text,
  provider_batch_id text,
  status text not null default 'created'
    check (status in (
      'created','dispatching','initiated','ringing','answered','in_progress',
      'completed','failed','cancelled','no_answer','busy','voicemail','expired'
    )),
  disposition_code text references public.ai_call_dispositions(code) on delete set null,
  from_phone_number text,
  to_phone_number text not null,
  provider_request jsonb not null default '{}',
  provider_response jsonb not null default '{}',
  call_metrics jsonb not null default '{}',
  error_code text,
  error_message text,
  error_data jsonb not null default '{}',
  recording_url text,
  recording_storage_path text,
  recording_duration_seconds integer,
  call_duration_seconds integer,
  ring_duration_seconds integer,
  provider_cost numeric(12,4),
  provider_currency text,
  provider_created_at timestamptz,
  dispatched_at timestamptz,
  initiated_at timestamptz,
  answered_at timestamptz,
  ended_at timestamptz,
  completed_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (call_job_id, attempt_number)
);

create unique index if not exists ai_call_attempts_provider_call_unique_idx
  on public.ai_call_attempts (provider_connection_id, provider_call_id)
  where provider_call_id is not null;

create index if not exists ai_call_attempts_job_status_idx
  on public.ai_call_attempts (call_job_id, status, attempt_number desc);

-- ============================================================
-- 10. PROVIDER WEBHOOK INBOX AND EVENTS
-- ============================================================

create table if not exists public.ai_call_webhook_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  provider_id uuid references public.ai_call_providers(id) on delete set null,
  provider_connection_id uuid references public.ai_call_provider_connections(id) on delete set null,
  provider_event_id text,
  provider_call_id text,
  event_type text not null,
  event_timestamp timestamptz,
  signature_valid boolean,
  request_headers jsonb not null default '{}',
  request_payload jsonb not null default '{}',
  processing_status text not null default 'received'
    check (processing_status in ('received','processing','processed','ignored','failed','dead_lettered')),
  processing_attempts integer not null default 0,
  next_processing_at timestamptz,
  error_message text,
  error_data jsonb not null default '{}',
  call_job_id uuid references public.ai_call_jobs(id) on delete set null,
  call_attempt_id uuid references public.ai_call_attempts(id) on delete set null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create unique index if not exists ai_call_webhook_provider_event_unique_idx
  on public.ai_call_webhook_events (provider_connection_id, provider_event_id)
  where provider_event_id is not null;

create index if not exists ai_call_webhook_processing_idx
  on public.ai_call_webhook_events (processing_status, next_processing_at, received_at)
  where processing_status in ('received','failed');

create table if not exists public.ai_call_attempt_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  call_job_id uuid not null references public.ai_call_jobs(id) on delete cascade,
  call_attempt_id uuid not null references public.ai_call_attempts(id) on delete cascade,
  webhook_event_id uuid references public.ai_call_webhook_events(id) on delete set null,
  event_type text not null,
  event_source text not null default 'provider'
    check (event_source in ('provider','system','workflow','agent','n8n')),
  event_timestamp timestamptz not null default now(),
  event_data jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists ai_call_attempt_events_attempt_time_idx
  on public.ai_call_attempt_events (call_attempt_id, event_timestamp);

-- ============================================================
-- 11. TRANSCRIPTS
-- ============================================================

create table if not exists public.ai_call_transcripts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  call_job_id uuid not null references public.ai_call_jobs(id) on delete cascade,
  call_attempt_id uuid not null references public.ai_call_attempts(id) on delete cascade,
  transcript_status text not null default 'pending'
    check (transcript_status in ('pending','processing','completed','failed','manual_review')),
  language_code text,
  raw_transcript text,
  normalized_transcript text,
  provider_transcript jsonb not null default '{}',
  summary text,
  sentiment text
    check (sentiment is null or sentiment in ('very_negative','negative','neutral','positive','very_positive','mixed')),
  sentiment_score numeric(8,4),
  intent_summary text,
  objections jsonb not null default '[]',
  commitments jsonb not null default '[]',
  entities jsonb not null default '{}',
  compliance_flags jsonb not null default '[]',
  quality_score numeric(8,2),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_notes text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (call_attempt_id)
);

create table if not exists public.ai_call_transcript_segments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  transcript_id uuid not null references public.ai_call_transcripts(id) on delete cascade,
  sequence_number integer not null,
  speaker text not null
    check (speaker in ('assistant','customer','agent','system','unknown')),
  start_ms integer,
  end_ms integer,
  text_content text not null,
  confidence numeric(8,4),
  sentiment text,
  extracted_entities jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (transcript_id, sequence_number)
);

create index if not exists ai_call_transcript_segments_transcript_seq_idx
  on public.ai_call_transcript_segments (transcript_id, sequence_number);

-- ============================================================
-- 12. QUALIFICATION RESPONSES AND RESULTS
-- ============================================================

create table if not exists public.ai_call_qualification_responses (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  call_job_id uuid not null references public.ai_call_jobs(id) on delete cascade,
  call_attempt_id uuid not null references public.ai_call_attempts(id) on delete cascade,
  qualification_schema_id uuid not null references public.ai_call_qualification_schemas(id) on delete restrict,
  qualification_question_id uuid not null references public.ai_call_qualification_questions(id) on delete restrict,
  question_code text not null,
  raw_answer text,
  normalized_answer jsonb not null default 'null'::jsonb,
  confidence numeric(8,4),
  is_valid boolean,
  validation_errors jsonb not null default '[]',
  awarded_score numeric(8,2) not null default 0,
  evidence_segments jsonb not null default '[]',
  manually_overridden boolean not null default false,
  overridden_by uuid references auth.users(id) on delete set null,
  overridden_at timestamptz,
  override_reason text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (call_attempt_id, qualification_question_id)
);

create table if not exists public.ai_call_qualification_results (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  call_job_id uuid not null references public.ai_call_jobs(id) on delete cascade,
  call_attempt_id uuid not null references public.ai_call_attempts(id) on delete cascade,
  qualification_schema_id uuid not null references public.ai_call_qualification_schemas(id) on delete restrict,
  lead_id uuid references public.leads(id) on delete set null,
  status text not null default 'processing'
    check (status in ('processing','qualified_hot','qualified_warm','qualified_cold','unqualified','manual_review','failed')),
  total_score numeric(8,2) not null default 0,
  maximum_score numeric(8,2) not null default 0,
  normalized_score numeric(8,2) not null default 0,
  valid_answer_count integer not null default 0,
  required_answer_count integer not null default 0,
  missing_required_questions jsonb not null default '[]',
  disqualifying_reasons jsonb not null default '[]',
  qualification_summary text,
  recommended_action text,
  recommended_followup_at timestamptz,
  recommended_agent_id uuid references auth.users(id) on delete set null,
  extracted_profile jsonb not null default '{}',
  scoring_breakdown jsonb not null default '{}',
  model_name text,
  model_version text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  review_status text
    check (review_status is null or review_status in ('pending','confirmed','corrected','rejected')),
  review_notes text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (call_attempt_id)
);

create index if not exists ai_call_qualification_results_lead_status_idx
  on public.ai_call_qualification_results (organization_id, lead_id, status, created_at desc);

-- ============================================================
-- 13. FOLLOW-UP ACTIONS AND ESCALATIONS
-- ============================================================

create table if not exists public.ai_call_actions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  call_job_id uuid not null references public.ai_call_jobs(id) on delete cascade,
  call_attempt_id uuid references public.ai_call_attempts(id) on delete set null,
  qualification_result_id uuid references public.ai_call_qualification_results(id) on delete set null,
  lead_id uuid references public.leads(id) on delete cascade,
  action_type text not null
    check (action_type in (
      'agent_callback','whatsapp_followup','site_visit','send_brochure',
      'assign_agent','mark_do_not_call','update_lead','create_followup',
      'escalate','none'
    )),
  status text not null default 'pending'
    check (status in ('pending','queued','processing','completed','failed','cancelled','skipped')),
  priority integer not null default 100,
  due_at timestamptz,
  assigned_to uuid references auth.users(id) on delete set null,
  workflow_execution_id uuid references public.workflow_executions(id) on delete set null,
  payload jsonb not null default '{}',
  result_data jsonb not null default '{}',
  error_data jsonb not null default '{}',
  completed_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists ai_call_actions_due_idx
  on public.ai_call_actions (organization_id, status, due_at, priority)
  where status in ('pending','queued');

-- ============================================================
-- 14. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'ai_call_providers',
    'ai_call_provider_connections',
    'ai_call_voices',
    'ai_call_script_templates',
    'ai_call_qualification_schemas',
    'ai_call_qualification_questions',
    'ai_call_campaigns',
    'ai_call_consents',
    'ai_call_suppression_list',
    'ai_call_jobs',
    'ai_call_attempts',
    'ai_call_transcripts',
    'ai_call_qualification_responses',
    'ai_call_qualification_results',
    'ai_call_actions'
  ]
  loop
    execute format(
      'drop trigger if exists %I_set_updated_at on public.%I',
      table_name,
      table_name
    );

    execute format(
      'create trigger %I_set_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      table_name,
      table_name
    );
  end loop;
end;
$$;

-- ============================================================
-- 15. PHONE NORMALIZATION
-- ============================================================

create or replace function public.normalize_ai_call_phone(
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

  digits := regexp_replace(requested_phone, '[^0-9]', '', 'g');
  country_digits := regexp_replace(coalesce(requested_default_country_code, '+91'), '[^0-9]', '', 'g');

  if digits = '' then
    return null;
  end if;

  if length(digits) = 10 then
    return '+' || country_digits || digits;
  end if;

  if left(digits, length(country_digits)) = country_digits then
    return '+' || digits;
  end if;

  if left(digits, 2) = '00' then
    return '+' || substring(digits from 3);
  end if;

  return '+' || digits;
end;
$$;

revoke all on function public.normalize_ai_call_phone(text,text) from public;
grant execute on function public.normalize_ai_call_phone(text,text)
to authenticated, service_role;

-- ============================================================
-- 16. CALL ELIGIBILITY CHECK
-- ============================================================

create or replace function public.check_ai_call_eligibility(
  requested_organization_id uuid,
  requested_phone_number text,
  requested_lead_id uuid default null,
  requested_campaign_id uuid default null,
  requested_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_phone text;
  campaign_record public.ai_call_campaigns;
  local_time time;
  local_dow integer;
  consent_required boolean := true;
  active_consent text;
  suppression_exists boolean;
  result jsonb;
begin
  normalized_phone := public.normalize_ai_call_phone(requested_phone_number, '+91');

  if normalized_phone is null then
    return jsonb_build_object(
      'eligible', false,
      'reason_code', 'INVALID_PHONE',
      'reason', 'Phone number is invalid'
    );
  end if;

  if requested_campaign_id is not null then
    select *
    into campaign_record
    from public.ai_call_campaigns
    where id = requested_campaign_id
      and organization_id = requested_organization_id;

    if not found then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'CAMPAIGN_NOT_FOUND',
        'reason', 'Campaign not found'
      );
    end if;

    consent_required := campaign_record.consent_required;

    if campaign_record.status <> 'active' then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'CAMPAIGN_NOT_ACTIVE',
        'reason', 'Campaign is not active'
      );
    end if;

    local_time := (requested_at at time zone campaign_record.timezone)::time;
    local_dow := extract(isodow from requested_at at time zone campaign_record.timezone)::integer;

    if not local_dow = any(campaign_record.allowed_weekdays) then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'WEEKDAY_NOT_ALLOWED',
        'reason', 'Calling is not allowed on this weekday'
      );
    end if;

    if local_time < campaign_record.calling_window_start
       or local_time > campaign_record.calling_window_end then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'OUTSIDE_CALLING_WINDOW',
        'reason', 'Current time is outside the campaign calling window'
      );
    end if;
  end if;

  select exists (
    select 1
    from public.ai_call_suppression_list suppression
    where suppression.organization_id = requested_organization_id
      and public.normalize_ai_call_phone(suppression.phone_number, '+91') = normalized_phone
      and suppression.is_active = true
      and suppression.active_from <= requested_at
      and (
        suppression.active_until is null
        or suppression.active_until > requested_at
      )
  )
  into suppression_exists;

  if suppression_exists then
    return jsonb_build_object(
      'eligible', false,
      'reason_code', 'SUPPRESSED',
      'reason', 'Phone number is on the suppression list'
    );
  end if;

  if consent_required then
    select consent.consent_status
    into active_consent
    from public.ai_call_consents consent
    where consent.organization_id = requested_organization_id
      and public.normalize_ai_call_phone(consent.phone_number, '+91') = normalized_phone
      and consent.consent_type = 'outbound_ai_call'
      and (
        consent.expires_at is null
        or consent.expires_at > requested_at
      )
    order by consent.created_at desc
    limit 1;

    if coalesce(active_consent, 'unknown') <> 'granted' then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'CONSENT_NOT_GRANTED',
        'reason', 'Outbound AI call consent is not granted',
        'consent_status', coalesce(active_consent, 'unknown')
      );
    end if;
  end if;

  result := jsonb_build_object(
    'eligible', true,
    'reason_code', 'ELIGIBLE',
    'reason', 'Call is eligible',
    'normalized_phone', normalized_phone
  );

  return result;
end;
$$;

revoke all on function public.check_ai_call_eligibility(uuid,text,uuid,uuid,timestamptz)
from public;

grant execute on function public.check_ai_call_eligibility(uuid,text,uuid,uuid,timestamptz)
to authenticated, service_role;

-- ============================================================
-- 17. CREATE / QUEUE CALL JOB
-- ============================================================

create or replace function public.create_ai_call_job(
  requested_organization_id uuid,
  requested_phone_number text,
  requested_lead_id uuid default null,
  requested_campaign_id uuid default null,
  requested_provider_connection_id uuid default null,
  requested_script_template_id uuid default null,
  requested_qualification_schema_id uuid default null,
  requested_voice_id uuid default null,
  requested_contact_name text default null,
  requested_language_code text default 'hi-IN',
  requested_scheduled_at timestamptz default null,
  requested_script_variables jsonb default '{}'::jsonb,
  requested_call_context jsonb default '{}'::jsonb,
  requested_source_type text default 'manual',
  requested_source_reference text default null,
  requested_idempotency_key text default null,
  requested_priority integer default 100
)
returns public.ai_call_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  campaign_record public.ai_call_campaigns;
  connection_id uuid;
  script_id uuid;
  schema_id uuid;
  voice_record_id uuid;
  max_attempts integer := 3;
  normalized_phone text;
  eligibility jsonb;
  existing_job public.ai_call_jobs;
  created_job public.ai_call_jobs;
  target_status text;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'ai_calling.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_job
    from public.ai_call_jobs job
    where job.organization_id = requested_organization_id
      and job.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_job;
    end if;
  end if;

  normalized_phone := public.normalize_ai_call_phone(requested_phone_number, '+91');

  if normalized_phone is null then
    raise exception 'Invalid phone number';
  end if;

  if requested_campaign_id is not null then
    select *
    into campaign_record
    from public.ai_call_campaigns campaign
    where campaign.id = requested_campaign_id
      and campaign.organization_id = requested_organization_id;

    if not found then
      raise exception 'AI call campaign not found';
    end if;

    connection_id := coalesce(
      requested_provider_connection_id,
      campaign_record.provider_connection_id
    );

    script_id := coalesce(
      requested_script_template_id,
      campaign_record.script_template_id
    );

    schema_id := coalesce(
      requested_qualification_schema_id,
      campaign_record.qualification_schema_id
    );

    voice_record_id := coalesce(
      requested_voice_id,
      campaign_record.voice_id
    );

    max_attempts := campaign_record.maximum_attempts;
  else
    connection_id := requested_provider_connection_id;
    script_id := requested_script_template_id;
    schema_id := requested_qualification_schema_id;
    voice_record_id := requested_voice_id;
  end if;

  if connection_id is null then
    raise exception 'Provider connection is required';
  end if;

  if script_id is null then
    raise exception 'Script template is required';
  end if;

  eligibility := public.check_ai_call_eligibility(
    requested_organization_id,
    normalized_phone,
    requested_lead_id,
    requested_campaign_id,
    coalesce(requested_scheduled_at, now())
  );

  target_status :=
    case
      when (eligibility ->> 'eligible')::boolean then
        case
          when requested_scheduled_at is null or requested_scheduled_at <= now()
            then 'queued'
          else 'scheduled'
        end
      else 'blocked'
    end;

  insert into public.ai_call_jobs (
    organization_id,
    campaign_id,
    provider_connection_id,
    script_template_id,
    qualification_schema_id,
    voice_id,
    lead_id,
    source_type,
    source_reference,
    idempotency_key,
    status,
    priority,
    phone_number,
    contact_name,
    language_code,
    scheduled_at,
    maximum_attempts,
    consent_status,
    blocked_reason,
    script_variables,
    call_context,
    queued_at,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    requested_campaign_id,
    connection_id,
    script_id,
    schema_id,
    voice_record_id,
    requested_lead_id,
    requested_source_type,
    requested_source_reference,
    requested_idempotency_key,
    target_status,
    requested_priority,
    normalized_phone,
    requested_contact_name,
    requested_language_code,
    requested_scheduled_at,
    max_attempts,
    case
      when (eligibility ->> 'eligible')::boolean then 'granted'
      when eligibility ->> 'reason_code' = 'CONSENT_NOT_GRANTED'
        then coalesce(eligibility ->> 'consent_status', 'unknown')
      else null
    end,
    case
      when (eligibility ->> 'eligible')::boolean then null
      else eligibility ->> 'reason'
    end,
    coalesce(requested_script_variables, '{}'::jsonb),
    coalesce(requested_call_context, '{}'::jsonb)
      || jsonb_build_object('eligibility', eligibility),
    case when target_status = 'queued' then now() else null end,
    auth.uid(),
    auth.uid()
  )
  returning *
  into created_job;

  return created_job;
end;
$$;

revoke all on function public.create_ai_call_job(
  uuid,text,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,
  jsonb,jsonb,text,text,text,integer
) from public;

grant execute on function public.create_ai_call_job(
  uuid,text,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,
  jsonb,jsonb,text,text,text,integer
) to authenticated, service_role;

-- ============================================================
-- 18. CLAIM CALL JOB
-- ============================================================

create or replace function public.claim_ai_call_job(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_minutes integer default 10
)
returns public.ai_call_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.ai_call_jobs;
begin
  if requested_worker_id is null or btrim(requested_worker_id) = '' then
    raise exception 'Worker ID is required';
  end if;

  if auth.role() <> 'service_role'
    and (
      requested_organization_id is null
      or not public.has_organization_permission(
        requested_organization_id,
        'ai_calling.execute'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into target_job
  from public.ai_call_jobs job
  where job.status in ('queued','scheduled')
    and coalesce(job.scheduled_at, now()) <= now()
    and (job.expires_at is null or job.expires_at > now())
    and job.attempt_count < job.maximum_attempts
    and (
      requested_organization_id is null
      or job.organization_id = requested_organization_id
    )
  order by
    job.priority asc,
    coalesce(job.scheduled_at, job.created_at) asc,
    job.created_at asc
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.ai_call_jobs
  set
    status = 'dispatching',
    started_at = coalesce(started_at, now()),
    metadata = metadata || jsonb_build_object(
      'claimed_by', requested_worker_id,
      'claimed_at', now(),
      'claim_expires_at', now() + make_interval(mins => greatest(requested_lock_minutes, 1))
    ),
    updated_at = now()
  where id = target_job.id
  returning *
  into target_job;

  return target_job;
end;
$$;

revoke all on function public.claim_ai_call_job(text,uuid,integer) from public;
grant execute on function public.claim_ai_call_job(text,uuid,integer)
to authenticated, service_role;

-- ============================================================
-- 19. CREATE CALL ATTEMPT
-- ============================================================

create or replace function public.start_ai_call_attempt(
  requested_call_job_id uuid,
  requested_provider_request jsonb default '{}'::jsonb,
  requested_from_phone_number text default null
)
returns public.ai_call_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.ai_call_jobs;
  created_attempt public.ai_call_attempts;
  next_attempt_number integer;
begin
  select *
  into target_job
  from public.ai_call_jobs job
  where job.id = requested_call_job_id
  for update;

  if not found then
    raise exception 'AI call job not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_job.organization_id,
      'ai_calling.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  if target_job.status not in ('queued','scheduled','dispatching','failed') then
    raise exception 'Call job cannot start from status %', target_job.status;
  end if;

  if target_job.attempt_count >= target_job.maximum_attempts then
    raise exception 'Maximum call attempts exhausted';
  end if;

  next_attempt_number := target_job.attempt_count + 1;

  insert into public.ai_call_attempts (
    organization_id,
    call_job_id,
    attempt_number,
    provider_connection_id,
    status,
    from_phone_number,
    to_phone_number,
    provider_request,
    dispatched_at
  )
  values (
    target_job.organization_id,
    target_job.id,
    next_attempt_number,
    target_job.provider_connection_id,
    'dispatching',
    requested_from_phone_number,
    target_job.phone_number,
    coalesce(requested_provider_request, '{}'::jsonb),
    now()
  )
  returning *
  into created_attempt;

  update public.ai_call_jobs
  set
    status = 'dispatching',
    attempt_count = next_attempt_number,
    next_attempt_at = null,
    updated_at = now()
  where id = target_job.id;

  return created_attempt;
end;
$$;

revoke all on function public.start_ai_call_attempt(uuid,jsonb,text) from public;
grant execute on function public.start_ai_call_attempt(uuid,jsonb,text)
to authenticated, service_role;

-- ============================================================
-- 20. MARK PROVIDER CALL INITIATED
-- ============================================================

create or replace function public.mark_ai_call_initiated(
  requested_call_attempt_id uuid,
  requested_provider_call_id text,
  requested_provider_response jsonb default '{}'::jsonb,
  requested_provider_batch_id text default null
)
returns public.ai_call_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.ai_call_attempts;
begin
  select *
  into target_attempt
  from public.ai_call_attempts attempt
  where attempt.id = requested_call_attempt_id
  for update;

  if not found then
    raise exception 'AI call attempt not found';
  end if;

  update public.ai_call_attempts
  set
    status = 'initiated',
    provider_call_id = requested_provider_call_id,
    provider_batch_id = requested_provider_batch_id,
    provider_response = coalesce(requested_provider_response, '{}'::jsonb),
    initiated_at = now(),
    updated_at = now()
  where id = target_attempt.id
  returning *
  into target_attempt;

  update public.ai_call_jobs
  set
    status = 'in_progress',
    updated_at = now()
  where id = target_attempt.call_job_id;

  insert into public.ai_call_attempt_events (
    organization_id,
    call_job_id,
    call_attempt_id,
    event_type,
    event_source,
    event_data
  )
  values (
    target_attempt.organization_id,
    target_attempt.call_job_id,
    target_attempt.id,
    'call.initiated',
    'provider',
    jsonb_build_object(
      'provider_call_id', requested_provider_call_id,
      'provider_batch_id', requested_provider_batch_id
    )
  );

  return target_attempt;
end;
$$;

revoke all on function public.mark_ai_call_initiated(uuid,text,jsonb,text) from public;
grant execute on function public.mark_ai_call_initiated(uuid,text,jsonb,text)
to authenticated, service_role;

-- ============================================================
-- 21. COMPLETE / FAIL CALL ATTEMPT
-- ============================================================

create or replace function public.complete_ai_call_attempt(
  requested_call_attempt_id uuid,
  requested_status text,
  requested_disposition_code text default null,
  requested_call_duration_seconds integer default null,
  requested_recording_url text default null,
  requested_provider_cost numeric default null,
  requested_provider_currency text default null,
  requested_result_data jsonb default '{}'::jsonb,
  requested_error_code text default null,
  requested_error_message text default null,
  requested_error_data jsonb default '{}'::jsonb
)
returns public.ai_call_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.ai_call_attempts;
  target_job public.ai_call_jobs;
  terminal_success boolean := false;
  next_delay_minutes integer;
  next_time timestamptz;
  campaign_record public.ai_call_campaigns;
  final_job_status text;
begin
  if requested_status not in (
    'completed','failed','cancelled','no_answer','busy','voicemail','expired'
  ) then
    raise exception 'Invalid terminal call attempt status';
  end if;

  select *
  into target_attempt
  from public.ai_call_attempts attempt
  where attempt.id = requested_call_attempt_id
  for update;

  if not found then
    raise exception 'AI call attempt not found';
  end if;

  select *
  into target_job
  from public.ai_call_jobs job
  where job.id = target_attempt.call_job_id
  for update;

  select coalesce(disposition.is_success, false)
  into terminal_success
  from public.ai_call_dispositions disposition
  where disposition.code = requested_disposition_code;

  terminal_success := coalesce(terminal_success, requested_status = 'completed');

  update public.ai_call_attempts
  set
    status = requested_status,
    disposition_code = requested_disposition_code,
    call_duration_seconds = requested_call_duration_seconds,
    recording_url = requested_recording_url,
    provider_cost = requested_provider_cost,
    provider_currency = requested_provider_currency,
    error_code = requested_error_code,
    error_message = requested_error_message,
    error_data = coalesce(requested_error_data, '{}'::jsonb),
    call_metrics = call_metrics || coalesce(requested_result_data, '{}'::jsonb),
    ended_at = coalesce(ended_at, now()),
    completed_at = now(),
    updated_at = now()
  where id = target_attempt.id
  returning *
  into target_attempt;

  if target_job.campaign_id is not null then
    select *
    into campaign_record
    from public.ai_call_campaigns campaign
    where campaign.id = target_job.campaign_id;
  end if;

  if terminal_success then
    final_job_status := 'completed';
    next_time := null;
  elsif target_job.attempt_count < target_job.maximum_attempts
    and requested_status in ('failed','no_answer','busy','voicemail') then

    if campaign_record.id is not null
      and array_length(campaign_record.retry_delays_minutes, 1) is not null then

      next_delay_minutes :=
        campaign_record.retry_delays_minutes[
          least(
            target_job.attempt_count,
            array_length(campaign_record.retry_delays_minutes, 1)
          )
        ];
    else
      next_delay_minutes := 60 * greatest(target_job.attempt_count, 1);
    end if;

    final_job_status := 'scheduled';
    next_time := now() + make_interval(mins => greatest(next_delay_minutes, 1));
  else
    final_job_status := 'failed';
    next_time := null;
  end if;

  update public.ai_call_jobs
  set
    status = final_job_status,
    final_disposition_code = requested_disposition_code,
    next_attempt_at = next_time,
    scheduled_at = case
      when final_job_status = 'scheduled' then next_time
      else scheduled_at
    end,
    result_data = result_data || coalesce(requested_result_data, '{}'::jsonb),
    error_data = case
      when requested_error_code is null and requested_error_message is null
        then error_data
      else coalesce(requested_error_data, '{}'::jsonb)
        || jsonb_build_object(
          'code', requested_error_code,
          'message', requested_error_message
        )
    end,
    completed_at = case
      when final_job_status in ('completed','failed') then now()
      else completed_at
    end,
    updated_at = now()
  where id = target_job.id
  returning *
  into target_job;

  insert into public.ai_call_attempt_events (
    organization_id,
    call_job_id,
    call_attempt_id,
    event_type,
    event_source,
    event_data
  )
  values (
    target_attempt.organization_id,
    target_attempt.call_job_id,
    target_attempt.id,
    'call.' || requested_status,
    'system',
    jsonb_build_object(
      'disposition_code', requested_disposition_code,
      'job_status', final_job_status,
      'next_attempt_at', next_time,
      'error_code', requested_error_code,
      'error_message', requested_error_message
    )
  );

  return target_attempt;
end;
$$;

revoke all on function public.complete_ai_call_attempt(
  uuid,text,text,integer,text,numeric,text,jsonb,text,text,jsonb
) from public;

grant execute on function public.complete_ai_call_attempt(
  uuid,text,text,integer,text,numeric,text,jsonb,text,text,jsonb
) to authenticated, service_role;

-- ============================================================
-- 22. CANCEL CALL JOB
-- ============================================================

create or replace function public.cancel_ai_call_job(
  requested_call_job_id uuid,
  requested_reason text default 'Cancelled manually'
)
returns public.ai_call_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.ai_call_jobs;
begin
  select *
  into target_job
  from public.ai_call_jobs job
  where job.id = requested_call_job_id
  for update;

  if not found then
    raise exception 'AI call job not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_job.organization_id,
      'ai_calling.cancel'
    ) then
    raise exception 'Permission denied';
  end if;

  if target_job.status in ('completed','failed','cancelled','expired') then
    return target_job;
  end if;

  update public.ai_call_attempts
  set
    status = 'cancelled',
    error_code = 'JOB_CANCELLED',
    error_message = requested_reason,
    ended_at = coalesce(ended_at, now()),
    completed_at = coalesce(completed_at, now()),
    updated_at = now()
  where call_job_id = target_job.id
    and status not in ('completed','failed','cancelled','no_answer','busy','voicemail','expired');

  update public.ai_call_jobs
  set
    status = 'cancelled',
    final_disposition_code = 'cancelled',
    cancellation_reason = requested_reason,
    cancelled_at = now(),
    cancelled_by = auth.uid(),
    next_attempt_at = null,
    updated_at = now()
  where id = target_job.id
  returning *
  into target_job;

  return target_job;
end;
$$;

revoke all on function public.cancel_ai_call_job(uuid,text) from public;
grant execute on function public.cancel_ai_call_job(uuid,text)
to authenticated, service_role;

-- ============================================================
-- 23. REGISTER CONSENT
-- ============================================================

create or replace function public.register_ai_call_consent(
  requested_organization_id uuid,
  requested_phone_number text,
  requested_consent_status text,
  requested_lead_id uuid default null,
  requested_consent_type text default 'outbound_ai_call',
  requested_consent_source text default 'agent',
  requested_consent_text text default null,
  requested_evidence_data jsonb default '{}'::jsonb,
  requested_expires_at timestamptz default null
)
returns public.ai_call_consents
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_consent public.ai_call_consents;
  normalized_phone text;
begin
  if not public.has_organization_permission(
    requested_organization_id,
    'ai_calling.manage_consent'
  ) then
    raise exception 'Permission denied';
  end if;

  if requested_consent_status not in ('granted','denied','withdrawn','unknown') then
    raise exception 'Invalid consent status';
  end if;

  normalized_phone := public.normalize_ai_call_phone(requested_phone_number, '+91');

  insert into public.ai_call_consents (
    organization_id,
    lead_id,
    phone_number,
    consent_type,
    consent_status,
    consent_source,
    consent_text,
    evidence_data,
    granted_at,
    withdrawn_at,
    expires_at,
    captured_by
  )
  values (
    requested_organization_id,
    requested_lead_id,
    normalized_phone,
    requested_consent_type,
    requested_consent_status,
    requested_consent_source,
    requested_consent_text,
    coalesce(requested_evidence_data, '{}'::jsonb),
    case when requested_consent_status = 'granted' then now() else null end,
    case when requested_consent_status = 'withdrawn' then now() else null end,
    requested_expires_at,
    auth.uid()
  )
  returning *
  into created_consent;

  if requested_consent_status in ('denied','withdrawn') then
    insert into public.ai_call_suppression_list (
      organization_id,
      phone_number,
      lead_id,
      suppression_type,
      reason,
      source,
      created_by
    )
    values (
      requested_organization_id,
      normalized_phone,
      requested_lead_id,
      'do_not_call',
      'Consent ' || requested_consent_status,
      requested_consent_source,
      auth.uid()
    )
    on conflict (organization_id, phone_number, suppression_type)
    do update set
      is_active = true,
      reason = excluded.reason,
      active_from = now(),
      active_until = null,
      updated_at = now();
  end if;

  return created_consent;
end;
$$;

revoke all on function public.register_ai_call_consent(
  uuid,text,text,uuid,text,text,text,jsonb,timestamptz
) from public;

grant execute on function public.register_ai_call_consent(
  uuid,text,text,uuid,text,text,text,jsonb,timestamptz
) to authenticated, service_role;

-- ============================================================
-- 24. TRANSCRIPT UPSERT
-- ============================================================

create or replace function public.upsert_ai_call_transcript(
  requested_call_attempt_id uuid,
  requested_raw_transcript text,
  requested_provider_transcript jsonb default '{}'::jsonb,
  requested_language_code text default null,
  requested_summary text default null,
  requested_sentiment text default null,
  requested_sentiment_score numeric default null,
  requested_entities jsonb default '{}'::jsonb,
  requested_objections jsonb default '[]'::jsonb,
  requested_commitments jsonb default '[]'::jsonb
)
returns public.ai_call_transcripts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.ai_call_attempts;
  transcript_record public.ai_call_transcripts;
begin
  select *
  into target_attempt
  from public.ai_call_attempts attempt
  where attempt.id = requested_call_attempt_id;

  if not found then
    raise exception 'AI call attempt not found';
  end if;

  insert into public.ai_call_transcripts (
    organization_id,
    call_job_id,
    call_attempt_id,
    transcript_status,
    language_code,
    raw_transcript,
    normalized_transcript,
    provider_transcript,
    summary,
    sentiment,
    sentiment_score,
    entities,
    objections,
    commitments
  )
  values (
    target_attempt.organization_id,
    target_attempt.call_job_id,
    target_attempt.id,
    'completed',
    requested_language_code,
    requested_raw_transcript,
    requested_raw_transcript,
    coalesce(requested_provider_transcript, '{}'::jsonb),
    requested_summary,
    requested_sentiment,
    requested_sentiment_score,
    coalesce(requested_entities, '{}'::jsonb),
    coalesce(requested_objections, '[]'::jsonb),
    coalesce(requested_commitments, '[]'::jsonb)
  )
  on conflict (call_attempt_id)
  do update set
    transcript_status = 'completed',
    language_code = excluded.language_code,
    raw_transcript = excluded.raw_transcript,
    normalized_transcript = excluded.normalized_transcript,
    provider_transcript = excluded.provider_transcript,
    summary = excluded.summary,
    sentiment = excluded.sentiment,
    sentiment_score = excluded.sentiment_score,
    entities = excluded.entities,
    objections = excluded.objections,
    commitments = excluded.commitments,
    updated_at = now()
  returning *
  into transcript_record;

  return transcript_record;
end;
$$;

revoke all on function public.upsert_ai_call_transcript(
  uuid,text,jsonb,text,text,text,numeric,jsonb,jsonb,jsonb
) from public;

grant execute on function public.upsert_ai_call_transcript(
  uuid,text,jsonb,text,text,text,numeric,jsonb,jsonb,jsonb
) to authenticated, service_role;

-- ============================================================
-- 25. CALCULATE QUALIFICATION RESULT
-- ============================================================

create or replace function public.calculate_ai_call_qualification(
  requested_call_attempt_id uuid
)
returns public.ai_call_qualification_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.ai_call_attempts;
  target_job public.ai_call_jobs;
  target_schema public.ai_call_qualification_schemas;
  total_score_value numeric(8,2);
  maximum_score_value numeric(8,2);
  normalized_score_value numeric(8,2);
  valid_count integer;
  required_count integer;
  missing_questions jsonb;
  disqualifying jsonb;
  final_status text;
  created_result public.ai_call_qualification_results;
begin
  select *
  into target_attempt
  from public.ai_call_attempts attempt
  where attempt.id = requested_call_attempt_id;

  if not found then
    raise exception 'AI call attempt not found';
  end if;

  select *
  into target_job
  from public.ai_call_jobs job
  where job.id = target_attempt.call_job_id;

  if target_job.qualification_schema_id is null then
    raise exception 'Call job has no qualification schema';
  end if;

  select *
  into target_schema
  from public.ai_call_qualification_schemas schema_record
  where schema_record.id = target_job.qualification_schema_id;

  select
    coalesce(sum(response.awarded_score), 0),
    coalesce(sum(question.maximum_score), 0),
    count(*) filter (where response.is_valid = true),
    count(*) filter (where question.is_required = true),
    coalesce(
      jsonb_agg(question.question_code)
        filter (
          where question.is_required = true
            and coalesce(response.is_valid, false) = false
        ),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'question_code', question.question_code,
          'answer', response.normalized_answer
        )
      ) filter (
        where response.normalized_answer is not null
          and question.disqualifying_values @> jsonb_build_array(response.normalized_answer)
      ),
      '[]'::jsonb
    )
  into
    total_score_value,
    maximum_score_value,
    valid_count,
    required_count,
    missing_questions,
    disqualifying
  from public.ai_call_qualification_questions question
  left join public.ai_call_qualification_responses response
    on response.qualification_question_id = question.id
   and response.call_attempt_id = target_attempt.id
  where question.qualification_schema_id = target_schema.id;

  normalized_score_value :=
    case
      when maximum_score_value > 0
        then round((total_score_value / maximum_score_value) * 100, 2)
      else 0
    end;

  final_status :=
    case
      when jsonb_array_length(disqualifying) > 0 then 'unqualified'
      when valid_count < target_schema.minimum_valid_answers then 'manual_review'
      when normalized_score_value >= target_schema.hot_threshold then 'qualified_hot'
      when normalized_score_value >= target_schema.warm_threshold then 'qualified_warm'
      else 'qualified_cold'
    end;

  insert into public.ai_call_qualification_results (
    organization_id,
    call_job_id,
    call_attempt_id,
    qualification_schema_id,
    lead_id,
    status,
    total_score,
    maximum_score,
    normalized_score,
    valid_answer_count,
    required_answer_count,
    missing_required_questions,
    disqualifying_reasons,
    qualification_summary,
    recommended_action,
    extracted_profile,
    scoring_breakdown
  )
  values (
    target_attempt.organization_id,
    target_job.id,
    target_attempt.id,
    target_schema.id,
    target_job.lead_id,
    final_status,
    total_score_value,
    maximum_score_value,
    normalized_score_value,
    valid_count,
    required_count,
    missing_questions,
    disqualifying,
    'AI call qualification completed with score ' || normalized_score_value::text,
    case final_status
      when 'qualified_hot' then 'assign_agent_and_schedule_site_visit'
      when 'qualified_warm' then 'agent_callback_and_nurture'
      when 'qualified_cold' then 'whatsapp_nurture'
      when 'manual_review' then 'manual_review'
      else 'close_or_suppress'
    end,
    '{}'::jsonb,
    jsonb_build_object(
      'total_score', total_score_value,
      'maximum_score', maximum_score_value,
      'normalized_score', normalized_score_value
    )
  )
  on conflict (call_attempt_id)
  do update set
    status = excluded.status,
    total_score = excluded.total_score,
    maximum_score = excluded.maximum_score,
    normalized_score = excluded.normalized_score,
    valid_answer_count = excluded.valid_answer_count,
    required_answer_count = excluded.required_answer_count,
    missing_required_questions = excluded.missing_required_questions,
    disqualifying_reasons = excluded.disqualifying_reasons,
    qualification_summary = excluded.qualification_summary,
    recommended_action = excluded.recommended_action,
    scoring_breakdown = excluded.scoring_breakdown,
    updated_at = now()
  returning *
  into created_result;

  update public.ai_call_jobs
  set
    qualification_status = final_status,
    qualification_score = normalized_score_value,
    final_disposition_code = case final_status
      when 'qualified_hot' then 'qualified_hot'
      when 'qualified_warm' then 'qualified_warm'
      when 'qualified_cold' then 'qualified_cold'
      when 'unqualified' then 'connected_not_interested'
      else final_disposition_code
    end,
    updated_at = now()
  where id = target_job.id;

  return created_result;
end;
$$;

revoke all on function public.calculate_ai_call_qualification(uuid) from public;
grant execute on function public.calculate_ai_call_qualification(uuid)
to authenticated, service_role;

-- ============================================================
-- 26. WEBHOOK EVENT INGESTION
-- ============================================================

create or replace function public.ingest_ai_call_webhook_event(
  requested_provider_connection_id uuid,
  requested_event_type text,
  requested_payload jsonb,
  requested_headers jsonb default '{}'::jsonb,
  requested_provider_event_id text default null,
  requested_provider_call_id text default null,
  requested_event_timestamp timestamptz default null,
  requested_signature_valid boolean default null
)
returns public.ai_call_webhook_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  connection_record public.ai_call_provider_connections;
  existing_event public.ai_call_webhook_events;
  created_event public.ai_call_webhook_events;
  attempt_record public.ai_call_attempts;
begin
  select *
  into connection_record
  from public.ai_call_provider_connections connection
  where connection.id = requested_provider_connection_id;

  if not found then
    raise exception 'AI call provider connection not found';
  end if;

  if requested_provider_event_id is not null then
    select *
    into existing_event
    from public.ai_call_webhook_events event_record
    where event_record.provider_connection_id = requested_provider_connection_id
      and event_record.provider_event_id = requested_provider_event_id
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  if requested_provider_call_id is not null then
    select *
    into attempt_record
    from public.ai_call_attempts attempt
    where attempt.provider_connection_id = requested_provider_connection_id
      and attempt.provider_call_id = requested_provider_call_id
    limit 1;
  end if;

  insert into public.ai_call_webhook_events (
    organization_id,
    provider_id,
    provider_connection_id,
    provider_event_id,
    provider_call_id,
    event_type,
    event_timestamp,
    signature_valid,
    request_headers,
    request_payload,
    processing_status,
    call_job_id,
    call_attempt_id
  )
  values (
    connection_record.organization_id,
    connection_record.provider_id,
    connection_record.id,
    requested_provider_event_id,
    requested_provider_call_id,
    requested_event_type,
    coalesce(requested_event_timestamp, now()),
    requested_signature_valid,
    coalesce(requested_headers, '{}'::jsonb),
    coalesce(requested_payload, '{}'::jsonb),
    'received',
    attempt_record.call_job_id,
    attempt_record.id
  )
  returning *
  into created_event;

  return created_event;
end;
$$;

revoke all on function public.ingest_ai_call_webhook_event(
  uuid,text,jsonb,jsonb,text,text,timestamptz,boolean
) from public;

grant execute on function public.ingest_ai_call_webhook_event(
  uuid,text,jsonb,jsonb,text,text,timestamptz,boolean
) to service_role;

-- ============================================================
-- 27. ANALYTICS VIEWS
-- ============================================================

create or replace view public.ai_call_campaign_summary_v
with (security_invoker = true)
as
select
  campaign.organization_id,
  campaign.id as campaign_id,
  campaign.campaign_code,
  campaign.campaign_name,
  campaign.status as campaign_status,
  count(job.id) as total_jobs,
  count(job.id) filter (where job.status = 'completed') as completed_jobs,
  count(job.id) filter (where job.status = 'failed') as failed_jobs,
  count(job.id) filter (where job.status = 'blocked') as blocked_jobs,
  count(job.id) filter (
    where job.final_disposition_code in (
      'qualified_hot','qualified_warm','qualified_cold','site_visit_requested','callback_requested'
    )
  ) as successful_connections,
  count(job.id) filter (where job.qualification_status = 'qualified_hot') as hot_leads,
  count(job.id) filter (where job.qualification_status = 'qualified_warm') as warm_leads,
  count(job.id) filter (where job.qualification_status = 'qualified_cold') as cold_leads,
  avg(job.qualification_score) filter (where job.qualification_score is not null) as average_qualification_score,
  min(job.created_at) as first_job_at,
  max(job.created_at) as latest_job_at
from public.ai_call_campaigns campaign
left join public.ai_call_jobs job
  on job.campaign_id = campaign.id
group by
  campaign.organization_id,
  campaign.id,
  campaign.campaign_code,
  campaign.campaign_name,
  campaign.status;

create or replace view public.ai_call_provider_performance_v
with (security_invoker = true)
as
select
  attempt.organization_id,
  attempt.provider_connection_id,
  connection.connection_name,
  provider.provider_code,
  count(*) as total_attempts,
  count(*) filter (where attempt.status = 'completed') as completed_attempts,
  count(*) filter (where attempt.status = 'failed') as failed_attempts,
  count(*) filter (where attempt.status = 'no_answer') as no_answer_attempts,
  avg(attempt.call_duration_seconds) filter (
    where attempt.call_duration_seconds is not null
  ) as average_call_duration_seconds,
  sum(attempt.provider_cost) as total_provider_cost,
  max(attempt.created_at) as latest_attempt_at
from public.ai_call_attempts attempt
join public.ai_call_provider_connections connection
  on connection.id = attempt.provider_connection_id
join public.ai_call_providers provider
  on provider.id = connection.provider_id
group by
  attempt.organization_id,
  attempt.provider_connection_id,
  connection.connection_name,
  provider.provider_code;

create or replace view public.ai_call_lead_history_v
with (security_invoker = true)
as
select
  job.organization_id,
  job.lead_id,
  job.id as call_job_id,
  job.status as call_job_status,
  job.final_disposition_code,
  job.qualification_status,
  job.qualification_score,
  job.attempt_count,
  job.created_at,
  job.completed_at,
  transcript.summary as call_summary,
  transcript.sentiment,
  result.recommended_action,
  result.recommended_followup_at
from public.ai_call_jobs job
left join lateral (
  select transcript_record.*
  from public.ai_call_attempts attempt
  join public.ai_call_transcripts transcript_record
    on transcript_record.call_attempt_id = attempt.id
  where attempt.call_job_id = job.id
  order by attempt.attempt_number desc
  limit 1
) transcript on true
left join lateral (
  select result_record.*
  from public.ai_call_qualification_results result_record
  where result_record.call_job_id = job.id
  order by result_record.created_at desc
  limit 1
) result on true;

-- ============================================================
-- 28. ROW LEVEL SECURITY
-- ============================================================

alter table public.ai_call_providers enable row level security;
alter table public.ai_call_provider_connections enable row level security;
alter table public.ai_call_voices enable row level security;
alter table public.ai_call_script_templates enable row level security;
alter table public.ai_call_qualification_schemas enable row level security;
alter table public.ai_call_qualification_questions enable row level security;
alter table public.ai_call_campaigns enable row level security;
alter table public.ai_call_consents enable row level security;
alter table public.ai_call_suppression_list enable row level security;
alter table public.ai_call_jobs enable row level security;
alter table public.ai_call_attempts enable row level security;
alter table public.ai_call_webhook_events enable row level security;
alter table public.ai_call_attempt_events enable row level security;
alter table public.ai_call_transcripts enable row level security;
alter table public.ai_call_transcript_segments enable row level security;
alter table public.ai_call_qualification_responses enable row level security;
alter table public.ai_call_qualification_results enable row level security;
alter table public.ai_call_actions enable row level security;

-- Global provider catalogue: authenticated users may read.
drop policy if exists ai_call_providers_authenticated_select
on public.ai_call_providers;

create policy ai_call_providers_authenticated_select
on public.ai_call_providers
for select
to authenticated
using (true);

drop policy if exists ai_call_providers_service_all
on public.ai_call_providers;

create policy ai_call_providers_service_all
on public.ai_call_providers
for all
to service_role
using (true)
with check (true);

-- Organization-scoped tables.
do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'ai_call_provider_connections',
    'ai_call_voices',
    'ai_call_script_templates',
    'ai_call_qualification_schemas',
    'ai_call_qualification_questions',
    'ai_call_campaigns',
    'ai_call_consents',
    'ai_call_suppression_list',
    'ai_call_jobs',
    'ai_call_attempts',
    'ai_call_webhook_events',
    'ai_call_attempt_events',
    'ai_call_transcripts',
    'ai_call_transcript_segments',
    'ai_call_qualification_responses',
    'ai_call_qualification_results',
    'ai_call_actions'
  ]
  loop
    execute format(
      'drop policy if exists %I_select_policy on public.%I',
      table_name,
      table_name
    );

    execute format(
      'create policy %I_select_policy
       on public.%I
       for select
       to authenticated
       using (
         public.has_organization_permission(organization_id, ''ai_calling.view'')
         or public.has_organization_permission(organization_id, ''ai_calling.view_all'')
       )',
      table_name,
      table_name
    );

    execute format(
      'drop policy if exists %I_service_policy on public.%I',
      table_name,
      table_name
    );

    execute format(
      'create policy %I_service_policy
       on public.%I
       for all
       to service_role
       using (true)
       with check (true)',
      table_name,
      table_name
    );
  end loop;
end;
$$;

-- Authenticated write policies for primary configuration tables.
drop policy if exists ai_call_provider_connections_write
on public.ai_call_provider_connections;

create policy ai_call_provider_connections_write
on public.ai_call_provider_connections
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_providers'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_providers'
  )
);

drop policy if exists ai_call_scripts_write
on public.ai_call_script_templates;

create policy ai_call_scripts_write
on public.ai_call_script_templates
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_scripts'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_scripts'
  )
);

drop policy if exists ai_call_campaigns_write
on public.ai_call_campaigns;

create policy ai_call_campaigns_write
on public.ai_call_campaigns
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_campaigns'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_campaigns'
  )
);

drop policy if exists ai_call_jobs_write
on public.ai_call_jobs;

create policy ai_call_jobs_write
on public.ai_call_jobs
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'ai_calling.execute'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'ai_calling.execute'
  )
);

drop policy if exists ai_call_consent_write
on public.ai_call_consents;

create policy ai_call_consent_write
on public.ai_call_consents
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_consent'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_consent'
  )
);

drop policy if exists ai_call_suppression_write
on public.ai_call_suppression_list;

create policy ai_call_suppression_write
on public.ai_call_suppression_list
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_consent'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'ai_calling.manage_consent'
  )
);

-- ============================================================
-- 29. GRANTS
-- ============================================================

grant select on public.ai_call_providers to authenticated;

grant select on
  public.ai_call_provider_connections,
  public.ai_call_voices,
  public.ai_call_script_templates,
  public.ai_call_qualification_schemas,
  public.ai_call_qualification_questions,
  public.ai_call_campaigns,
  public.ai_call_consents,
  public.ai_call_suppression_list,
  public.ai_call_jobs,
  public.ai_call_attempts,
  public.ai_call_webhook_events,
  public.ai_call_attempt_events,
  public.ai_call_transcripts,
  public.ai_call_transcript_segments,
  public.ai_call_qualification_responses,
  public.ai_call_qualification_results,
  public.ai_call_actions
to authenticated;

grant insert, update, delete on
  public.ai_call_provider_connections,
  public.ai_call_voices,
  public.ai_call_script_templates,
  public.ai_call_qualification_schemas,
  public.ai_call_qualification_questions,
  public.ai_call_campaigns,
  public.ai_call_consents,
  public.ai_call_suppression_list,
  public.ai_call_jobs
to authenticated;

grant all on
  public.ai_call_providers,
  public.ai_call_provider_connections,
  public.ai_call_voices,
  public.ai_call_script_templates,
  public.ai_call_qualification_schemas,
  public.ai_call_qualification_questions,
  public.ai_call_campaigns,
  public.ai_call_consents,
  public.ai_call_suppression_list,
  public.ai_call_jobs,
  public.ai_call_attempts,
  public.ai_call_webhook_events,
  public.ai_call_attempt_events,
  public.ai_call_transcripts,
  public.ai_call_transcript_segments,
  public.ai_call_qualification_responses,
  public.ai_call_qualification_results,
  public.ai_call_actions
to service_role;

grant select on
  public.ai_call_campaign_summary_v,
  public.ai_call_provider_performance_v,
  public.ai_call_lead_history_v
to authenticated, service_role;

-- ============================================================
-- 30. FINAL VALIDATION
-- ============================================================

do $$
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'ai_call_jobs'
  ) then
    raise exception '010_ai_calling_engine migration validation failed: ai_call_jobs missing';
  end if;

  if not exists (
    select 1
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name = 'create_ai_call_job'
  ) then
    raise exception '010_ai_calling_engine migration validation failed: create_ai_call_job missing';
  end if;
end;
$$;

commit;