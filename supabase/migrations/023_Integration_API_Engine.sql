-- ============================================================
-- SalesSetu Enterprise
-- Migration 023: Integration & API Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   009_workflow_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--   021_Administration_Engine.sql
--   022_Reporting_Engine.sql
--
-- Scope:
--   • Integration provider catalogue
--   • Tenant integration connections
--   • REST/API client and API-key management
--   • OAuth clients, authorization state and token metadata
--   • API endpoint registry and access policies
--   • Rate limits, idempotency and request tracing
--   • Outbound webhooks, subscriptions and retry delivery
--   • Inbound webhook inbox and deduplication
--   • External sync jobs, mappings and checkpoints
--   • Event outbox, logs, analytics and health checks
--   • RLS, permissions, grants and final validation
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
  p.module,
  p.action,
  p.code,
  p.description
from (
  values
    ('integration_api','view','integration_api.view','View integrations and API configuration'),
    ('integration_api','view_all','integration_api.view_all','View all organization integrations'),
    ('integration_api','manage_providers','integration_api.manage_providers','Manage integration providers'),
    ('integration_api','manage_connections','integration_api.manage_connections','Manage integration connections'),
    ('integration_api','manage_api_clients','integration_api.manage_api_clients','Manage API clients'),
    ('integration_api','manage_api_keys','integration_api.manage_api_keys','Manage API keys'),
    ('integration_api','manage_oauth','integration_api.manage_oauth','Manage OAuth configuration'),
    ('integration_api','manage_endpoints','integration_api.manage_endpoints','Manage API endpoints'),
    ('integration_api','manage_webhooks','integration_api.manage_webhooks','Manage webhooks'),
    ('integration_api','manage_rate_limits','integration_api.manage_rate_limits','Manage API rate limits'),
    ('integration_api','manage_sync','integration_api.manage_sync','Manage external synchronization'),
    ('integration_api','execute','integration_api.execute','Execute integration operations'),
    ('integration_api','rotate_secrets','integration_api.rotate_secrets','Rotate integration secrets'),
    ('integration_api','view_sensitive','integration_api.view_sensitive','View sensitive integration metadata'),
    ('integration_api','view_logs','integration_api.view_logs','View integration and API logs'),
    ('integration_api','view_analytics','integration_api.view_analytics','View integration analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. INTEGRATION PROVIDERS
-- ============================================================

create table if not exists public.integration_providers (
  id uuid primary key default gen_random_uuid(),

  provider_code text not null,
  provider_name text not null,
  description text,

  provider_category text not null
    check (
      provider_category in (
        'communication',
        'advertising',
        'payments',
        'storage',
        'analytics',
        'automation',
        'ai',
        'crm',
        'identity',
        'email',
        'telephony',
        'webhook',
        'custom'
      )
    ),

  authentication_types text[] not null default '{}',
  supported_capabilities text[] not null default '{}',

  base_url text,
  documentation_url text,
  logo_url text,

  status text not null default 'active'
    check (status in ('active','inactive','deprecated','archived')),

  is_system_provider boolean not null default true,
  configuration_schema jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (provider_code)
);

insert into public.integration_providers (
  provider_code,
  provider_name,
  description,
  provider_category,
  authentication_types,
  supported_capabilities,
  base_url,
  documentation_url,
  is_system_provider
)
values
  ('meta','Meta','Meta Ads, Lead Ads and Graph API','advertising',array['oauth2','access_token'],array['lead_ads','campaigns','webhooks'],'https://graph.facebook.com',null,true),
  ('google_ads','Google Ads','Google Ads integration','advertising',array['oauth2'],array['campaigns','leads','reporting'],'https://googleads.googleapis.com',null,true),
  ('interakt','Interakt','WhatsApp Business messaging via Interakt','communication',array['api_key'],array['whatsapp','templates','webhooks'],'https://api.interakt.ai',null,true),
  ('whatsapp_cloud','WhatsApp Cloud API','Meta WhatsApp Cloud API','communication',array['access_token'],array['whatsapp','templates','webhooks'],'https://graph.facebook.com',null,true),
  ('twilio','Twilio','SMS and telephony integration','telephony',array['basic','api_key'],array['sms','voice','webhooks'],'https://api.twilio.com',null,true),
  ('razorpay','Razorpay','Payments and payment links','payments',array['basic','api_key'],array['payments','refunds','webhooks'],'https://api.razorpay.com',null,true),
  ('stripe','Stripe','Payments and billing','payments',array['api_key','oauth2'],array['payments','subscriptions','webhooks'],'https://api.stripe.com',null,true),
  ('smtp','SMTP','Generic outbound email','email',array['basic'],array['email'],'smtp://',null,true),
  ('n8n','n8n','Workflow automation integration','automation',array['api_key','webhook_secret'],array['workflows','webhooks'],'https://',null,true),
  ('supabase','Supabase','Database, Auth and Storage integration','storage',array['service_role','jwt'],array['database','auth','storage','realtime'],'https://',null,true),
  ('openai','OpenAI','AI model integration','ai',array['api_key'],array['chat','embeddings','audio'],'https://api.openai.com',null,true),
  ('custom','Custom Integration','Custom provider definition','custom',array['api_key','basic','bearer','oauth2','custom'],array['custom'],null,null,true)
on conflict (provider_code) do nothing;

-- ============================================================
-- 3. INTEGRATION CONNECTIONS
-- ============================================================

create table if not exists public.integration_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  provider_id uuid not null references public.integration_providers(id) on delete restrict,

  connection_code text not null,
  connection_name text not null,

  environment text not null default 'production'
    check (environment in ('development','staging','production')),

  authentication_type text not null,
  credential_reference text,
  external_account_id text,
  external_account_name text,

  base_url text,
  api_version text,

  status text not null default 'inactive'
    check (
      status in (
        'inactive',
        'pending',
        'active',
        'degraded',
        'error',
        'expired',
        'revoked',
        'archived'
      )
    ),

  enabled boolean not null default false,

  health_status text not null default 'unknown'
    check (health_status in ('unknown','healthy','degraded','unhealthy','disabled')),

  last_health_check_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  last_error_code text,
  last_error_message text,

  token_expires_at timestamptz,
  last_secret_rotation_at timestamptz,

  scopes text[] not null default '{}',
  capabilities text[] not null default '{}',

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,connection_code)
);

create index if not exists integration_connections_provider_idx
  on public.integration_connections (
    organization_id,
    provider_id,
    status
  );

-- ============================================================
-- 4. API CLIENTS
-- ============================================================

create table if not exists public.api_clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  client_code text not null,
  client_name text not null,
  description text,

  client_type text not null default 'server'
    check (client_type in ('server','web','mobile','service','partner','internal')),

  owner_user_id uuid references auth.users(id) on delete set null,

  status text not null default 'active'
    check (status in ('active','inactive','suspended','revoked','archived')),

  allowed_origins text[] not null default '{}',
  allowed_redirect_uris text[] not null default '{}',
  allowed_ip_ranges text[] not null default '{}',

  default_scopes text[] not null default '{}',

  rate_limit_profile text,
  last_used_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,client_code)
);

-- ============================================================
-- 5. API KEYS
-- ============================================================

create table if not exists public.api_keys (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  api_client_id uuid not null references public.api_clients(id) on delete cascade,

  key_name text not null,
  key_prefix text not null,
  key_hash text not null,

  scopes text[] not null default '{}',
  allowed_ip_ranges text[] not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','expired','revoked')),

  expires_at timestamptz,
  last_used_at timestamptz,
  last_rotated_at timestamptz,
  revoked_at timestamptz,

  usage_count bigint not null default 0,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  revoked_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (key_hash)
);

create index if not exists api_keys_client_status_idx
  on public.api_keys (
    organization_id,
    api_client_id,
    status
  );

-- ============================================================
-- 6. OAUTH CLIENTS
-- ============================================================

create table if not exists public.oauth_clients (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  connection_id uuid references public.integration_connections(id) on delete cascade,

  client_name text not null,
  external_client_id text,
  client_secret_reference text,

  authorization_url text,
  token_url text,
  revocation_url text,
  user_info_url text,

  redirect_uris text[] not null default '{}',
  default_scopes text[] not null default '{}',

  pkce_required boolean not null default true,

  status text not null default 'active'
    check (status in ('active','inactive','revoked','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.oauth_authorization_states (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  oauth_client_id uuid not null references public.oauth_clients(id) on delete cascade,

  state_hash text not null,
  state_prefix text,
  code_verifier_reference text,

  redirect_uri text,
  requested_scopes text[] not null default '{}',

  status text not null default 'pending'
    check (status in ('pending','used','expired','revoked')),

  expires_at timestamptz not null,
  used_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (state_hash)
);

create table if not exists public.oauth_token_metadata (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  oauth_client_id uuid not null references public.oauth_clients(id) on delete cascade,
  connection_id uuid references public.integration_connections(id) on delete cascade,

  external_subject text,
  access_token_reference text,
  refresh_token_reference text,

  token_type text,
  scopes text[] not null default '{}',

  issued_at timestamptz,
  expires_at timestamptz,
  refresh_expires_at timestamptz,

  status text not null default 'active'
    check (status in ('active','expired','revoked','error')),

  last_refresh_at timestamptz,
  refresh_failure_count integer not null default 0,
  last_error text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 7. API ENDPOINT REGISTRY
-- ============================================================

create table if not exists public.api_endpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  endpoint_code text not null,
  endpoint_name text not null,
  description text,

  http_method text not null
    check (http_method in ('GET','POST','PUT','PATCH','DELETE','OPTIONS')),

  path_pattern text not null,
  version text not null default 'v1',

  module_code text,
  resource_type text,
  action_code text,

  authentication_required boolean not null default true,
  required_scopes text[] not null default '{}',
  required_permission_code text,

  rate_limit_profile text,

  request_schema jsonb not null default '{}',
  response_schema jsonb not null default '{}',

  idempotency_required boolean not null default false,
  audit_enabled boolean not null default true,

  status text not null default 'active'
    check (status in ('draft','active','inactive','deprecated','archived')),

  is_system_endpoint boolean not null default false,
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,endpoint_code)
);

create unique index if not exists api_endpoints_system_unique_idx
  on public.api_endpoints(endpoint_code)
  where organization_id is null;

-- ============================================================
-- 8. API ACCESS POLICIES
-- ============================================================

create table if not exists public.api_access_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  policy_code text not null,
  policy_name text not null,
  description text,

  api_client_id uuid references public.api_clients(id) on delete cascade,
  endpoint_id uuid references public.api_endpoints(id) on delete cascade,

  allowed boolean not null default true,

  conditions jsonb not null default '{}',
  allowed_ip_ranges text[] not null default '{}',
  required_scopes text[] not null default '{}',

  valid_from timestamptz not null default now(),
  valid_until timestamptz,

  status text not null default 'active'
    check (status in ('active','inactive','expired','revoked')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),

  unique (organization_id,policy_code)
);

-- ============================================================
-- 9. RATE LIMIT PROFILES
-- ============================================================

create table if not exists public.api_rate_limit_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  profile_code text not null,
  profile_name text not null,

  window_seconds integer not null check (window_seconds > 0),
  request_limit integer not null check (request_limit > 0),

  burst_limit integer,
  concurrent_limit integer,

  key_strategy text not null default 'api_key'
    check (key_strategy in ('api_key','client','user','ip','organization','composite')),

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  is_system_profile boolean not null default false,
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,profile_code)
);

create unique index if not exists api_rate_limit_profiles_system_unique_idx
  on public.api_rate_limit_profiles(profile_code)
  where organization_id is null;

insert into public.api_rate_limit_profiles (
  organization_id,
  profile_code,
  profile_name,
  window_seconds,
  request_limit,
  burst_limit,
  concurrent_limit,
  key_strategy,
  is_system_profile
)
values
  (null,'standard','Standard API Limit',60,120,30,20,'api_key',true),
  (null,'high_volume','High Volume API Limit',60,1000,200,100,'api_key',true),
  (null,'public','Public API Limit',60,30,10,5,'ip',true),
  (null,'webhook','Webhook Delivery Limit',60,300,100,50,'organization',true)
on conflict do nothing;

create table if not exists public.api_rate_limit_counters (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  profile_id uuid not null references public.api_rate_limit_profiles(id) on delete cascade,

  counter_key text not null,
  window_started_at timestamptz not null,
  window_ends_at timestamptz not null,

  request_count integer not null default 0,
  rejected_count integer not null default 0,

  updated_at timestamptz not null default now(),

  unique (profile_id,counter_key,window_started_at)
);

-- ============================================================
-- 10. IDEMPOTENCY KEYS
-- ============================================================

create table if not exists public.api_idempotency_keys (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  api_client_id uuid references public.api_clients(id) on delete set null,
  endpoint_id uuid references public.api_endpoints(id) on delete set null,

  idempotency_key text not null,
  request_hash text not null,

  status text not null default 'processing'
    check (status in ('processing','completed','failed','expired')),

  response_status integer,
  response_headers jsonb not null default '{}',
  response_body jsonb,

  locked_at timestamptz not null default now(),
  completed_at timestamptz,
  expires_at timestamptz not null,

  correlation_id text,
  trace_id text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,idempotency_key)
);

create index if not exists api_idempotency_keys_expiry_idx
  on public.api_idempotency_keys(status,expires_at);

-- ============================================================
-- 11. API REQUEST LOGS
-- ============================================================

create table if not exists public.api_request_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  api_client_id uuid references public.api_clients(id) on delete set null,
  api_key_id uuid references public.api_keys(id) on delete set null,
  endpoint_id uuid references public.api_endpoints(id) on delete set null,

  request_id text not null,
  correlation_id text,
  trace_id text,

  http_method text,
  path text,
  query_parameters jsonb not null default '{}',

  request_headers jsonb not null default '{}',
  request_body_hash text,
  request_size_bytes bigint,

  response_status integer,
  response_size_bytes bigint,
  duration_ms bigint,

  ip_address inet,
  user_agent text,

  authentication_status text,
  authorization_status text,

  rate_limited boolean not null default false,
  idempotent_replay boolean not null default false,

  error_code text,
  error_message text,

  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (request_id)
);

create index if not exists api_request_logs_org_time_idx
  on public.api_request_logs (
    organization_id,
    occurred_at desc
  );

-- ============================================================
-- 12. OUTBOUND WEBHOOK ENDPOINTS
-- ============================================================

create table if not exists public.webhook_endpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  endpoint_code text not null,
  endpoint_name text not null,
  endpoint_url text not null,

  secret_reference text,

  signing_algorithm text not null default 'hmac_sha256'
    check (signing_algorithm in ('none','hmac_sha256','hmac_sha512','custom')),

  headers jsonb not null default '{}',
  timeout_seconds integer not null default 30,

  verify_ssl boolean not null default true,
  follow_redirects boolean not null default false,

  maximum_attempts integer not null default 10,
  retry_policy jsonb not null default '{"type":"exponential","base_seconds":30,"max_seconds":3600}',

  status text not null default 'active'
    check (status in ('active','inactive','error','archived')),

  health_status text not null default 'unknown'
    check (health_status in ('unknown','healthy','degraded','unhealthy','disabled')),

  last_success_at timestamptz,
  last_failure_at timestamptz,
  failure_count integer not null default 0,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,endpoint_code)
);

-- ============================================================
-- 13. WEBHOOK SUBSCRIPTIONS
-- ============================================================

create table if not exists public.webhook_subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  webhook_endpoint_id uuid not null references public.webhook_endpoints(id) on delete cascade,

  subscription_code text not null,
  subscription_name text not null,

  event_patterns text[] not null default '{}',
  source_modules text[] not null default '{}',

  filter_expression jsonb not null default '{}',
  transform_template jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','paused','inactive','archived')),

  delivery_mode text not null default 'at_least_once'
    check (delivery_mode in ('at_most_once','at_least_once')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,subscription_code)
);

-- ============================================================
-- 14. WEBHOOK DELIVERY JOBS
-- ============================================================

create table if not exists public.webhook_delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  webhook_endpoint_id uuid not null references public.webhook_endpoints(id) on delete cascade,
  webhook_subscription_id uuid references public.webhook_subscriptions(id) on delete set null,

  event_name text not null,
  event_id text,
  idempotency_key text,

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'delivering',
        'delivered',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,

  payload jsonb not null default '{}',
  headers jsonb not null default '{}',

  scheduled_at timestamptz not null default now(),
  next_attempt_at timestamptz not null default now(),

  attempts integer not null default 0,
  maximum_attempts integer not null default 10,

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  response_status integer,
  response_headers jsonb not null default '{}',
  response_body_preview text,
  response_time_ms bigint,

  delivered_at timestamptz,

  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists webhook_delivery_jobs_idempotency_idx
  on public.webhook_delivery_jobs (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists webhook_delivery_jobs_queue_idx
  on public.webhook_delivery_jobs (
    status,
    next_attempt_at,
    priority,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 15. INBOUND WEBHOOK INBOX
-- ============================================================

create table if not exists public.inbound_webhook_inbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  provider_id uuid references public.integration_providers(id) on delete set null,
  connection_id uuid references public.integration_connections(id) on delete set null,

  provider_event_id text,
  event_name text,
  endpoint_key text,

  signature_status text not null default 'not_checked'
    check (signature_status in ('not_checked','valid','invalid','missing','error')),

  deduplication_key text,
  request_headers jsonb not null default '{}',
  request_body jsonb not null default '{}',

  source_ip inet,
  received_at timestamptz not null default now(),

  status text not null default 'received'
    check (
      status in (
        'received',
        'validated',
        'processing',
        'processed',
        'ignored',
        'failed',
        'dead_lettered'
      )
    ),

  processing_attempts integer not null default 0,
  processed_at timestamptz,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists inbound_webhook_inbox_dedup_idx
  on public.inbound_webhook_inbox (
    organization_id,
    deduplication_key
  )
  where deduplication_key is not null;

create index if not exists inbound_webhook_inbox_status_idx
  on public.inbound_webhook_inbox (
    status,
    received_at
  )
  where status in ('received','validated','failed');

-- ============================================================
-- 16. SYNC DEFINITIONS
-- ============================================================

create table if not exists public.integration_sync_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  connection_id uuid not null references public.integration_connections(id) on delete cascade,

  sync_code text not null,
  sync_name text not null,

  direction text not null
    check (direction in ('inbound','outbound','bidirectional')),

  entity_type text not null,
  source_resource text,
  target_resource text,

  sync_mode text not null default 'incremental'
    check (sync_mode in ('full','incremental','event_driven','manual')),

  schedule_expression text,
  timezone text not null default 'Asia/Kolkata',

  batch_size integer not null default 100,
  maximum_records integer,

  conflict_strategy text not null default 'latest_wins'
    check (
      conflict_strategy in (
        'source_wins',
        'target_wins',
        'latest_wins',
        'manual',
        'merge',
        'custom'
      )
    ),

  enabled boolean not null default false,

  status text not null default 'active'
    check (status in ('active','paused','inactive','archived')),

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,sync_code)
);

-- ============================================================
-- 17. FIELD MAPPINGS
-- ============================================================

create table if not exists public.integration_field_mappings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sync_definition_id uuid not null references public.integration_sync_definitions(id) on delete cascade,

  mapping_order integer not null default 100,

  source_field text not null,
  target_field text not null,

  transformation_type text not null default 'direct'
    check (
      transformation_type in (
        'direct',
        'constant',
        'lookup',
        'expression',
        'format',
        'split',
        'concat',
        'custom'
      )
    ),

  transformation_config jsonb not null default '{}',

  required boolean not null default false,
  default_value jsonb,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (sync_definition_id,source_field,target_field)
);

-- ============================================================
-- 18. SYNC CHECKPOINTS
-- ============================================================

create table if not exists public.integration_sync_checkpoints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sync_definition_id uuid not null references public.integration_sync_definitions(id) on delete cascade,

  checkpoint_key text not null,
  checkpoint_value jsonb not null default '{}',

  last_synced_at timestamptz,
  last_external_cursor text,
  last_external_updated_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (sync_definition_id,checkpoint_key)
);

-- ============================================================
-- 19. SYNC JOBS
-- ============================================================

create table if not exists public.integration_sync_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  sync_definition_id uuid not null references public.integration_sync_definitions(id) on delete cascade,

  execution_type text not null default 'manual'
    check (execution_type in ('manual','scheduled','event','retry','backfill')),

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'claimed',
        'running',
        'completed',
        'partially_completed',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,

  scheduled_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  started_at timestamptz,
  completed_at timestamptz,

  records_read integer not null default 0,
  records_created integer not null default 0,
  records_updated integer not null default 0,
  records_skipped integer not null default 0,
  records_failed integer not null default 0,

  input_data jsonb not null default '{}',
  result_data jsonb not null default '{}',

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists integration_sync_jobs_queue_idx
  on public.integration_sync_jobs (
    status,
    scheduled_at,
    priority,
    created_at
  )
  where status in ('queued','failed');

-- ============================================================
-- 20. EXTERNAL ENTITY LINKS
-- ============================================================

create table if not exists public.integration_entity_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  connection_id uuid not null references public.integration_connections(id) on delete cascade,

  local_entity_type text not null,
  local_entity_id uuid not null,

  external_entity_type text not null,
  external_entity_id text not null,

  external_url text,

  sync_status text not null default 'linked'
    check (sync_status in ('linked','synced','out_of_sync','conflict','deleted','error')),

  local_updated_at timestamptz,
  external_updated_at timestamptz,
  last_synced_at timestamptz,

  checksum text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (
    organization_id,
    connection_id,
    local_entity_type,
    local_entity_id,
    external_entity_type
  ),

  unique (
    organization_id,
    connection_id,
    external_entity_type,
    external_entity_id
  )
);

-- ============================================================
-- 21. INTEGRATION EVENT OUTBOX AND LOGS
-- ============================================================

create table if not exists public.integration_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,

  connection_id uuid references public.integration_connections(id) on delete set null,
  sync_job_id uuid references public.integration_sync_jobs(id) on delete set null,

  event_name text not null,
  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'automation_engine',
        'workflow_engine',
        'notification_engine',
        'communication_engine',
        'n8n',
        'analytics',
        'audit',
        'webhook'
      )
    ),

  source_type text,
  source_id uuid,

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

create unique index if not exists integration_event_outbox_idempotency_idx
  on public.integration_event_outbox (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create table if not exists public.integration_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,

  connection_id uuid references public.integration_connections(id) on delete set null,
  sync_job_id uuid references public.integration_sync_jobs(id) on delete set null,
  webhook_delivery_job_id uuid references public.webhook_delivery_jobs(id) on delete set null,
  inbound_webhook_id uuid references public.inbound_webhook_inbox(id) on delete set null,

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

create index if not exists integration_logs_org_created_idx
  on public.integration_logs (
    organization_id,
    created_at desc
  );

-- ============================================================
-- 22. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'integration_providers',
    'integration_connections',
    'api_clients',
    'api_keys',
    'oauth_clients',
    'oauth_token_metadata',
    'api_endpoints',
    'api_rate_limit_profiles',
    'api_rate_limit_counters',
    'api_idempotency_keys',
    'webhook_endpoints',
    'webhook_subscriptions',
    'webhook_delivery_jobs',
    'inbound_webhook_inbox',
    'integration_sync_definitions',
    'integration_field_mappings',
    'integration_sync_checkpoints',
    'integration_sync_jobs',
    'integration_entity_links',
    'integration_event_outbox'
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
-- 23. CREATE INTEGRATION CONNECTION
-- ============================================================

create or replace function public.create_integration_connection(
  requested_organization_id uuid,
  requested_provider_code text,
  requested_connection_code text,
  requested_connection_name text,
  requested_authentication_type text,
  requested_environment text default 'production',
  requested_credential_reference text default null,
  requested_external_account_id text default null,
  requested_external_account_name text default null,
  requested_base_url text default null,
  requested_api_version text default null,
  requested_scopes text[] default '{}',
  requested_capabilities text[] default '{}',
  requested_configuration jsonb default '{}'::jsonb,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.integration_connections
language plpgsql
security definer
set search_path = ''
as $$
declare
  provider_record public.integration_providers;
  connection_record public.integration_connections;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'integration_api.manage_connections'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into provider_record
  from public.integration_providers
  where provider_code = requested_provider_code
    and status = 'active';

  if not found then
    raise exception 'Active integration provider not found';
  end if;

  insert into public.integration_connections (
    organization_id,
    provider_id,
    connection_code,
    connection_name,
    environment,
    authentication_type,
    credential_reference,
    external_account_id,
    external_account_name,
    base_url,
    api_version,
    status,
    enabled,
    health_status,
    scopes,
    capabilities,
    configuration,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    provider_record.id,
    requested_connection_code,
    requested_connection_name,
    requested_environment,
    requested_authentication_type,
    requested_credential_reference,
    requested_external_account_id,
    requested_external_account_name,
    coalesce(requested_base_url,provider_record.base_url),
    requested_api_version,
    'inactive',
    false,
    'unknown',
    coalesce(requested_scopes,'{}'::text[]),
    coalesce(requested_capabilities,'{}'::text[]),
    coalesce(requested_configuration,'{}'::jsonb),
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  on conflict (organization_id,connection_code)
  do update set
    provider_id = excluded.provider_id,
    connection_name = excluded.connection_name,
    environment = excluded.environment,
    authentication_type = excluded.authentication_type,
    credential_reference = excluded.credential_reference,
    external_account_id = excluded.external_account_id,
    external_account_name = excluded.external_account_name,
    base_url = excluded.base_url,
    api_version = excluded.api_version,
    scopes = excluded.scopes,
    capabilities = excluded.capabilities,
    configuration = excluded.configuration,
    metadata = excluded.metadata,
    updated_by = auth.uid(),
    updated_at = now()
  returning * into connection_record;

  return connection_record;
end;
$$;

revoke all
on function public.create_integration_connection(
  uuid,text,text,text,text,text,text,text,text,text,text,text[],text[],jsonb,jsonb
)
from public;

grant execute
on function public.create_integration_connection(
  uuid,text,text,text,text,text,text,text,text,text,text,text[],text[],jsonb,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 24. CREATE API KEY
-- ============================================================

create or replace function public.create_api_key(
  requested_api_client_id uuid,
  requested_key_name text,
  requested_scopes text[] default '{}',
  requested_allowed_ip_ranges text[] default '{}',
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  client_record public.api_clients;
  raw_key text;
  key_hash_value text;
  key_record public.api_keys;
begin
  select *
  into client_record
  from public.api_clients
  where id = requested_api_client_id
    and status = 'active';

  if not found then
    raise exception 'Active API client not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      client_record.organization_id,
      'integration_api.manage_api_keys'
    ) then
    raise exception 'Permission denied';
  end if;

  raw_key := 'ssk_'
    || lower(substr(replace(gen_random_uuid()::text,'-',''),1,24))
    || lower(substr(replace(gen_random_uuid()::text,'-',''),1,24));

  key_hash_value := encode(
    digest(raw_key,'sha256'),
    'hex'
  );

  insert into public.api_keys (
    organization_id,
    api_client_id,
    key_name,
    key_prefix,
    key_hash,
    scopes,
    allowed_ip_ranges,
    status,
    expires_at,
    metadata,
    created_by
  )
  values (
    client_record.organization_id,
    client_record.id,
    requested_key_name,
    left(raw_key,12),
    key_hash_value,
    coalesce(requested_scopes,client_record.default_scopes),
    coalesce(requested_allowed_ip_ranges,'{}'::text[]),
    'active',
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid()
  )
  returning * into key_record;

  return jsonb_build_object(
    'api_key_id',key_record.id,
    'api_key',raw_key,
    'key_prefix',key_record.key_prefix,
    'expires_at',key_record.expires_at
  );
end;
$$;

revoke all
on function public.create_api_key(
  uuid,text,text[],text[],timestamptz,jsonb
)
from public;

grant execute
on function public.create_api_key(
  uuid,text,text[],text[],timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 25. VALIDATE API KEY
-- ============================================================

create or replace function public.validate_api_key(
  requested_api_key text,
  requested_required_scopes text[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  key_hash_value text;
  key_record public.api_keys;
  client_record public.api_clients;
begin
  key_hash_value := encode(
    digest(requested_api_key,'sha256'),
    'hex'
  );

  select *
  into key_record
  from public.api_keys
  where key_hash = key_hash_value
  for update;

  if not found then
    return jsonb_build_object(
      'valid',false,
      'reason','invalid_api_key'
    );
  end if;

  if key_record.status <> 'active'
    or (
      key_record.expires_at is not null
      and key_record.expires_at <= now()
    ) then
    return jsonb_build_object(
      'valid',false,
      'reason','expired_or_inactive'
    );
  end if;

  select *
  into client_record
  from public.api_clients
  where id = key_record.api_client_id
    and status = 'active';

  if not found then
    return jsonb_build_object(
      'valid',false,
      'reason','inactive_client'
    );
  end if;

  if cardinality(coalesce(requested_required_scopes,'{}'::text[])) > 0
    and not requested_required_scopes <@ key_record.scopes then
    return jsonb_build_object(
      'valid',false,
      'reason','insufficient_scope'
    );
  end if;

  update public.api_keys
  set
    last_used_at = now(),
    usage_count = usage_count + 1,
    updated_at = now()
  where id = key_record.id;

  update public.api_clients
  set
    last_used_at = now(),
    updated_at = now()
  where id = client_record.id;

  return jsonb_build_object(
    'valid',true,
    'organization_id',key_record.organization_id,
    'api_client_id',client_record.id,
    'api_key_id',key_record.id,
    'scopes',key_record.scopes,
    'allowed_ip_ranges',key_record.allowed_ip_ranges
  );
end;
$$;

revoke all
on function public.validate_api_key(text,text[])
from public;

grant execute
on function public.validate_api_key(text,text[])
to anon,authenticated,service_role;

-- ============================================================
-- 26. REGISTER IDEMPOTENCY KEY
-- ============================================================

create or replace function public.register_api_idempotency_key(
  requested_organization_id uuid,
  requested_idempotency_key text,
  requested_request_hash text,
  requested_api_client_id uuid default null,
  requested_endpoint_id uuid default null,
  requested_expires_at timestamptz default now() + interval '24 hours',
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_record public.api_idempotency_keys;
  created_record public.api_idempotency_keys;
begin
  select *
  into existing_record
  from public.api_idempotency_keys
  where organization_id = requested_organization_id
    and idempotency_key = requested_idempotency_key
  for update;

  if found then
    if existing_record.request_hash is distinct from requested_request_hash then
      return jsonb_build_object(
        'accepted',false,
        'reason','idempotency_key_reused_with_different_request',
        'record_id',existing_record.id
      );
    end if;

    return jsonb_build_object(
      'accepted',false,
      'replay',true,
      'status',existing_record.status,
      'response_status',existing_record.response_status,
      'response_headers',existing_record.response_headers,
      'response_body',existing_record.response_body,
      'record_id',existing_record.id
    );
  end if;

  insert into public.api_idempotency_keys (
    organization_id,
    api_client_id,
    endpoint_id,
    idempotency_key,
    request_hash,
    status,
    expires_at,
    correlation_id,
    trace_id
  )
  values (
    requested_organization_id,
    requested_api_client_id,
    requested_endpoint_id,
    requested_idempotency_key,
    requested_request_hash,
    'processing',
    requested_expires_at,
    requested_correlation_id,
    requested_trace_id
  )
  returning * into created_record;

  return jsonb_build_object(
    'accepted',true,
    'replay',false,
    'record_id',created_record.id
  );
end;
$$;

revoke all
on function public.register_api_idempotency_key(
  uuid,text,text,uuid,uuid,timestamptz,text,text
)
from public;

grant execute
on function public.register_api_idempotency_key(
  uuid,text,text,uuid,uuid,timestamptz,text,text
)
to authenticated,service_role;

-- ============================================================
-- 27. COMPLETE IDEMPOTENCY KEY
-- ============================================================

create or replace function public.complete_api_idempotency_key(
  requested_record_id uuid,
  requested_response_status integer,
  requested_response_headers jsonb default '{}'::jsonb,
  requested_response_body jsonb default null
)
returns public.api_idempotency_keys
language plpgsql
security definer
set search_path = ''
as $$
declare
  record_value public.api_idempotency_keys;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete idempotency records';
  end if;

  update public.api_idempotency_keys
  set
    status = 'completed',
    response_status = requested_response_status,
    response_headers = coalesce(requested_response_headers,'{}'::jsonb),
    response_body = requested_response_body,
    completed_at = now(),
    updated_at = now()
  where id = requested_record_id
  returning * into record_value;

  if not found then
    raise exception 'Idempotency record not found';
  end if;

  return record_value;
end;
$$;

revoke all
on function public.complete_api_idempotency_key(uuid,integer,jsonb,jsonb)
from public;

grant execute
on function public.complete_api_idempotency_key(uuid,integer,jsonb,jsonb)
to service_role;

-- ============================================================
-- 28. CHECK RATE LIMIT
-- ============================================================

create or replace function public.check_api_rate_limit(
  requested_profile_code text,
  requested_counter_key text,
  requested_organization_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_record public.api_rate_limit_profiles;
  counter_record public.api_rate_limit_counters;
  window_start timestamptz;
  window_end timestamptz;
begin
  select *
  into profile_record
  from public.api_rate_limit_profiles p
  where p.profile_code = requested_profile_code
    and p.status = 'active'
    and (
      p.organization_id = requested_organization_id
      or p.organization_id is null
    )
  order by
    case when p.organization_id = requested_organization_id then 0 else 1 end
  limit 1;

  if not found then
    return jsonb_build_object(
      'allowed',true,
      'reason','profile_not_found'
    );
  end if;

  window_start := to_timestamp(
    floor(
      extract(epoch from now()) / profile_record.window_seconds
    ) * profile_record.window_seconds
  );

  window_end := window_start
    + make_interval(secs => profile_record.window_seconds);

  insert into public.api_rate_limit_counters (
    organization_id,
    profile_id,
    counter_key,
    window_started_at,
    window_ends_at,
    request_count,
    rejected_count
  )
  values (
    requested_organization_id,
    profile_record.id,
    requested_counter_key,
    window_start,
    window_end,
    1,
    0
  )
  on conflict (profile_id,counter_key,window_started_at)
  do update set
    request_count = api_rate_limit_counters.request_count + 1,
    updated_at = now()
  returning * into counter_record;

  if counter_record.request_count > profile_record.request_limit then
    update public.api_rate_limit_counters
    set
      rejected_count = rejected_count + 1,
      updated_at = now()
    where id = counter_record.id;

    return jsonb_build_object(
      'allowed',false,
      'limit',profile_record.request_limit,
      'remaining',0,
      'reset_at',window_end
    );
  end if;

  return jsonb_build_object(
    'allowed',true,
    'limit',profile_record.request_limit,
    'remaining',greatest(
      profile_record.request_limit - counter_record.request_count,
      0
    ),
    'reset_at',window_end
  );
end;
$$;

revoke all
on function public.check_api_rate_limit(text,text,uuid)
from public;

grant execute
on function public.check_api_rate_limit(text,text,uuid)
to anon,authenticated,service_role;

-- ============================================================
-- 29. ENQUEUE WEBHOOK DELIVERY
-- ============================================================

create or replace function public.enqueue_webhook_delivery(
  requested_webhook_endpoint_id uuid,
  requested_event_name text,
  requested_payload jsonb,
  requested_subscription_id uuid default null,
  requested_event_id text default null,
  requested_headers jsonb default '{}'::jsonb,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_scheduled_at timestamptz default now()
)
returns public.webhook_delivery_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  endpoint_record public.webhook_endpoints;
  existing_record public.webhook_delivery_jobs;
  delivery_record public.webhook_delivery_jobs;
begin
  select *
  into endpoint_record
  from public.webhook_endpoints
  where id = requested_webhook_endpoint_id
    and status = 'active';

  if not found then
    raise exception 'Active webhook endpoint not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      endpoint_record.organization_id,
      'integration_api.manage_webhooks'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_record
    from public.webhook_delivery_jobs
    where organization_id = endpoint_record.organization_id
      and idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_record;
    end if;
  end if;

  insert into public.webhook_delivery_jobs (
    organization_id,
    webhook_endpoint_id,
    webhook_subscription_id,
    event_name,
    event_id,
    idempotency_key,
    status,
    priority,
    payload,
    headers,
    scheduled_at,
    next_attempt_at,
    maximum_attempts,
    correlation_id,
    trace_id
  )
  values (
    endpoint_record.organization_id,
    endpoint_record.id,
    requested_subscription_id,
    requested_event_name,
    requested_event_id,
    requested_idempotency_key,
    'queued',
    requested_priority,
    coalesce(requested_payload,'{}'::jsonb),
    coalesce(requested_headers,'{}'::jsonb),
    coalesce(requested_scheduled_at,now()),
    coalesce(requested_scheduled_at,now()),
    endpoint_record.maximum_attempts,
    requested_correlation_id,
    requested_trace_id
  )
  returning * into delivery_record;

  return delivery_record;
end;
$$;

revoke all
on function public.enqueue_webhook_delivery(
  uuid,text,jsonb,uuid,text,jsonb,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.enqueue_webhook_delivery(
  uuid,text,jsonb,uuid,text,jsonb,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 30. CLAIM WEBHOOK DELIVERY
-- ============================================================

create or replace function public.claim_webhook_delivery(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.webhook_delivery_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery_record public.webhook_delivery_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim webhook deliveries';
  end if;

  select *
  into delivery_record
  from public.webhook_delivery_jobs j
  where j.status in ('queued','failed')
    and j.next_attempt_at <= now()
    and j.attempts < j.maximum_attempts
    and (
      requested_organization_id is null
      or j.organization_id = requested_organization_id
    )
  order by j.priority,j.next_attempt_at,j.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.webhook_delivery_jobs
  set
    status = 'claimed',
    attempts = attempts + 1,
    claimed_at = now(),
    claimed_by = requested_worker_id,
    lock_token = gen_random_uuid()::text,
    lock_expires_at = now() + make_interval(
      secs => greatest(requested_lock_seconds,1)
    ),
    updated_at = now()
  where id = delivery_record.id
  returning * into delivery_record;

  return delivery_record;
end;
$$;

revoke all
on function public.claim_webhook_delivery(text,uuid,integer)
from public;

grant execute
on function public.claim_webhook_delivery(text,uuid,integer)
to service_role;

-- ============================================================
-- 31. COMPLETE WEBHOOK DELIVERY
-- ============================================================

create or replace function public.complete_webhook_delivery(
  requested_delivery_id uuid,
  requested_lock_token text,
  requested_response_status integer,
  requested_response_headers jsonb default '{}'::jsonb,
  requested_response_body_preview text default null,
  requested_response_time_ms bigint default null
)
returns public.webhook_delivery_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery_record public.webhook_delivery_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete webhook deliveries';
  end if;

  select *
  into delivery_record
  from public.webhook_delivery_jobs
  where id = requested_delivery_id
  for update;

  if not found then
    raise exception 'Webhook delivery not found';
  end if;

  if delivery_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid webhook delivery lock token';
  end if;

  if requested_response_status between 200 and 299 then
    update public.webhook_delivery_jobs
    set
      status = 'delivered',
      response_status = requested_response_status,
      response_headers = coalesce(requested_response_headers,'{}'::jsonb),
      response_body_preview = requested_response_body_preview,
      response_time_ms = requested_response_time_ms,
      delivered_at = now(),
      claimed_at = null,
      claimed_by = null,
      lock_token = null,
      lock_expires_at = null,
      updated_at = now()
    where id = requested_delivery_id
    returning * into delivery_record;

    update public.webhook_endpoints
    set
      health_status = 'healthy',
      last_success_at = now(),
      failure_count = 0,
      updated_at = now()
    where id = delivery_record.webhook_endpoint_id;
  else
    update public.webhook_delivery_jobs
    set
      status = case
        when attempts >= maximum_attempts then 'dead_lettered'
        else 'failed'
      end,
      response_status = requested_response_status,
      response_headers = coalesce(requested_response_headers,'{}'::jsonb),
      response_body_preview = requested_response_body_preview,
      response_time_ms = requested_response_time_ms,
      next_attempt_at = now() + make_interval(
        secs => least(
          3600,
          greatest(30,power(2,attempts)::integer * 30)
        )
      ),
      claimed_at = null,
      claimed_by = null,
      lock_token = null,
      lock_expires_at = null,
      updated_at = now()
    where id = requested_delivery_id
    returning * into delivery_record;

    update public.webhook_endpoints
    set
      health_status = case
        when failure_count + 1 >= 5 then 'unhealthy'
        else 'degraded'
      end,
      last_failure_at = now(),
      failure_count = failure_count + 1,
      updated_at = now()
    where id = delivery_record.webhook_endpoint_id;
  end if;

  return delivery_record;
end;
$$;

revoke all
on function public.complete_webhook_delivery(
  uuid,text,integer,jsonb,text,bigint
)
from public;

grant execute
on function public.complete_webhook_delivery(
  uuid,text,integer,jsonb,text,bigint
)
to service_role;

-- ============================================================
-- 32. INGEST INBOUND WEBHOOK
-- ============================================================

create or replace function public.ingest_inbound_webhook(
  requested_provider_code text,
  requested_endpoint_key text,
  requested_request_headers jsonb,
  requested_request_body jsonb,
  requested_organization_id uuid default null,
  requested_connection_id uuid default null,
  requested_provider_event_id text default null,
  requested_event_name text default null,
  requested_deduplication_key text default null,
  requested_signature_status text default 'not_checked',
  requested_source_ip inet default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.inbound_webhook_inbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  provider_record public.integration_providers;
  existing_record public.inbound_webhook_inbox;
  inbox_record public.inbound_webhook_inbox;
begin
  select *
  into provider_record
  from public.integration_providers
  where provider_code = requested_provider_code;

  if not found then
    raise exception 'Integration provider not found';
  end if;

  if requested_deduplication_key is not null then
    select *
    into existing_record
    from public.inbound_webhook_inbox
    where organization_id is not distinct from requested_organization_id
      and deduplication_key = requested_deduplication_key
    limit 1;

    if found then
      return existing_record;
    end if;
  end if;

  insert into public.inbound_webhook_inbox (
    organization_id,
    provider_id,
    connection_id,
    provider_event_id,
    event_name,
    endpoint_key,
    signature_status,
    deduplication_key,
    request_headers,
    request_body,
    source_ip,
    received_at,
    status,
    correlation_id,
    trace_id,
    metadata
  )
  values (
    requested_organization_id,
    provider_record.id,
    requested_connection_id,
    requested_provider_event_id,
    requested_event_name,
    requested_endpoint_key,
    requested_signature_status,
    requested_deduplication_key,
    coalesce(requested_request_headers,'{}'::jsonb),
    coalesce(requested_request_body,'{}'::jsonb),
    requested_source_ip,
    now(),
    case
      when requested_signature_status = 'invalid' then 'failed'
      when requested_signature_status in ('valid','not_checked') then 'received'
      else 'received'
    end,
    requested_correlation_id,
    requested_trace_id,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into inbox_record;

  return inbox_record;
end;
$$;

revoke all
on function public.ingest_inbound_webhook(
  text,text,jsonb,jsonb,uuid,uuid,text,text,text,text,inet,text,text,jsonb
)
from public;

grant execute
on function public.ingest_inbound_webhook(
  text,text,jsonb,jsonb,uuid,uuid,text,text,text,text,inet,text,text,jsonb
)
to anon,authenticated,service_role;

-- ============================================================
-- 33. CREATE SYNC JOB
-- ============================================================

create or replace function public.create_integration_sync_job(
  requested_sync_definition_id uuid,
  requested_execution_type text default 'manual',
  requested_priority integer default 100,
  requested_scheduled_at timestamptz default now(),
  requested_input_data jsonb default '{}'::jsonb,
  requested_correlation_id text default null,
  requested_trace_id text default null
)
returns public.integration_sync_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  definition_record public.integration_sync_definitions;
  job_record public.integration_sync_jobs;
begin
  select *
  into definition_record
  from public.integration_sync_definitions
  where id = requested_sync_definition_id
    and status = 'active';

  if not found then
    raise exception 'Active sync definition not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      definition_record.organization_id,
      'integration_api.manage_sync'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.integration_sync_jobs (
    organization_id,
    sync_definition_id,
    execution_type,
    status,
    priority,
    scheduled_at,
    input_data,
    correlation_id,
    trace_id,
    created_by
  )
  values (
    definition_record.organization_id,
    definition_record.id,
    requested_execution_type,
    'queued',
    requested_priority,
    coalesce(requested_scheduled_at,now()),
    coalesce(requested_input_data,'{}'::jsonb),
    requested_correlation_id,
    requested_trace_id,
    auth.uid()
  )
  returning * into job_record;

  return job_record;
end;
$$;

revoke all
on function public.create_integration_sync_job(
  uuid,text,integer,timestamptz,jsonb,text,text
)
from public;

grant execute
on function public.create_integration_sync_job(
  uuid,text,integer,timestamptz,jsonb,text,text
)
to authenticated,service_role;

-- ============================================================
-- 34. CLAIM SYNC JOB
-- ============================================================

create or replace function public.claim_integration_sync_job(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 600
)
returns public.integration_sync_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.integration_sync_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim sync jobs';
  end if;

  select *
  into job_record
  from public.integration_sync_jobs j
  where j.status in ('queued','failed')
    and j.scheduled_at <= now()
    and (
      requested_organization_id is null
      or j.organization_id = requested_organization_id
    )
  order by j.priority,j.scheduled_at,j.created_at
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.integration_sync_jobs
  set
    status = 'claimed',
    claimed_at = now(),
    claimed_by = requested_worker_id,
    lock_token = gen_random_uuid()::text,
    lock_expires_at = now() + make_interval(
      secs => greatest(requested_lock_seconds,1)
    ),
    started_at = coalesce(started_at,now()),
    updated_at = now()
  where id = job_record.id
  returning * into job_record;

  return job_record;
end;
$$;

revoke all
on function public.claim_integration_sync_job(text,uuid,integer)
from public;

grant execute
on function public.claim_integration_sync_job(text,uuid,integer)
to service_role;

-- ============================================================
-- 35. COMPLETE SYNC JOB
-- ============================================================

create or replace function public.complete_integration_sync_job(
  requested_job_id uuid,
  requested_lock_token text,
  requested_records_read integer default 0,
  requested_records_created integer default 0,
  requested_records_updated integer default 0,
  requested_records_skipped integer default 0,
  requested_records_failed integer default 0,
  requested_result_data jsonb default '{}'::jsonb
)
returns public.integration_sync_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_record public.integration_sync_jobs;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete sync jobs';
  end if;

  select *
  into job_record
  from public.integration_sync_jobs
  where id = requested_job_id
  for update;

  if not found then
    raise exception 'Sync job not found';
  end if;

  if job_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid sync-job lock token';
  end if;

  update public.integration_sync_jobs
  set
    status = case
      when requested_records_failed > 0
        and (
          requested_records_created > 0
          or requested_records_updated > 0
        )
        then 'partially_completed'
      when requested_records_failed > 0 then 'failed'
      else 'completed'
    end,
    records_read = requested_records_read,
    records_created = requested_records_created,
    records_updated = requested_records_updated,
    records_skipped = requested_records_skipped,
    records_failed = requested_records_failed,
    result_data = coalesce(requested_result_data,'{}'::jsonb),
    completed_at = now(),
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
on function public.complete_integration_sync_job(
  uuid,text,integer,integer,integer,integer,integer,jsonb
)
from public;

grant execute
on function public.complete_integration_sync_job(
  uuid,text,integer,integer,integer,integer,integer,jsonb
)
to service_role;

-- ============================================================
-- 36. PUBLISH INTEGRATION EVENT
-- ============================================================

create or replace function public.publish_integration_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_connection_id uuid default null,
  requested_sync_job_id uuid default null,
  requested_source_type text default null,
  requested_source_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.integration_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.integration_event_outbox;
  created_event public.integration_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.integration_event_outbox e
    where e.organization_id is not distinct from requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.integration_event_outbox (
    organization_id,
    connection_id,
    sync_job_id,
    event_name,
    destination,
    source_type,
    source_id,
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
    requested_connection_id,
    requested_sync_job_id,
    requested_event_name,
    requested_destination,
    requested_source_type,
    requested_source_id,
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
on function public.publish_integration_event(
  uuid,text,jsonb,text,uuid,uuid,text,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_integration_event(
  uuid,text,jsonb,text,uuid,uuid,text,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 37. SYNC JOB EVENT TRIGGER
-- ============================================================

create or replace function public.emit_integration_sync_events()
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

  perform public.publish_integration_event(
    new.organization_id,
    'integration.sync.' || new.status,
    jsonb_build_object(
      'sync_job_id',new.id,
      'sync_definition_id',new.sync_definition_id,
      'status',new.status,
      'records_read',new.records_read,
      'records_created',new.records_created,
      'records_updated',new.records_updated,
      'records_skipped',new.records_skipped,
      'records_failed',new.records_failed,
      'error_code',new.error_code,
      'error_message',new.error_message
    ),
    case
      when new.status in ('failed','partially_completed') then 'notification_engine'
      else 'analytics'
    end,
    null,
    new.id,
    'integration_sync_job',
    new.id,
    case when new.status = 'failed' then 10 else 50 end,
    'integration-sync:' || new.id::text || ':' || new.status,
    coalesce(new.correlation_id,new.id::text),
    new.trace_id,
    now()
  );

  return new;
end;
$$;

drop trigger if exists integration_sync_jobs_emit_events
on public.integration_sync_jobs;

create trigger integration_sync_jobs_emit_events
after insert or update
on public.integration_sync_jobs
for each row
execute function public.emit_integration_sync_events();

-- ============================================================
-- 38. ANALYTICS VIEWS
-- ============================================================

create or replace view public.integration_connection_dashboard
with (security_invoker = true)
as
select
  c.organization_id,
  p.provider_code,
  p.provider_name,
  p.provider_category,

  count(*) as connection_count,

  count(*) filter (
    where c.enabled = true
      and c.status = 'active'
  ) as active_connections,

  count(*) filter (
    where c.health_status = 'healthy'
  ) as healthy_connections,

  count(*) filter (
    where c.health_status in ('degraded','unhealthy')
  ) as unhealthy_connections,

  max(c.last_success_at) as latest_success_at,
  max(c.last_failure_at) as latest_failure_at

from public.integration_connections c
join public.integration_providers p
  on p.id = c.provider_id
group by
  c.organization_id,
  p.provider_code,
  p.provider_name,
  p.provider_category;

create or replace view public.api_usage_dashboard
with (security_invoker = true)
as
select
  l.organization_id,
  l.api_client_id,
  l.endpoint_id,

  count(*) as request_count,

  count(*) filter (
    where l.response_status between 200 and 299
  ) as successful_requests,

  count(*) filter (
    where l.response_status >= 400
  ) as failed_requests,

  count(*) filter (
    where l.rate_limited = true
  ) as rate_limited_requests,

  round(avg(l.duration_ms),2) as average_duration_ms,
  percentile_cont(0.95) within group (
    order by l.duration_ms
  ) as p95_duration_ms,

  max(l.occurred_at) as latest_request_at

from public.api_request_logs l
group by
  l.organization_id,
  l.api_client_id,
  l.endpoint_id;

create or replace view public.webhook_delivery_dashboard
with (security_invoker = true)
as
select
  j.organization_id,
  j.webhook_endpoint_id,
  j.status,

  count(*) as delivery_count,

  count(*) filter (
    where j.status = 'delivered'
  ) as delivered_count,

  count(*) filter (
    where j.status in ('failed','dead_lettered')
  ) as failed_count,

  round(
    count(*) filter (
      where j.status = 'delivered'
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as delivery_success_rate,

  round(avg(j.response_time_ms),2) as average_response_time_ms,

  max(j.delivered_at) as latest_delivery_at

from public.webhook_delivery_jobs j
group by
  j.organization_id,
  j.webhook_endpoint_id,
  j.status;

create or replace view public.integration_sync_dashboard
with (security_invoker = true)
as
select
  j.organization_id,
  j.sync_definition_id,
  j.status,

  count(*) as job_count,

  coalesce(sum(j.records_read),0) as records_read,
  coalesce(sum(j.records_created),0) as records_created,
  coalesce(sum(j.records_updated),0) as records_updated,
  coalesce(sum(j.records_skipped),0) as records_skipped,
  coalesce(sum(j.records_failed),0) as records_failed,

  max(j.completed_at) as latest_completion_at

from public.integration_sync_jobs j
group by
  j.organization_id,
  j.sync_definition_id,
  j.status;

grant select
on
  public.integration_connection_dashboard,
  public.api_usage_dashboard,
  public.webhook_delivery_dashboard,
  public.integration_sync_dashboard
to authenticated,service_role;

-- ============================================================
-- 39. HEALTH CHECK
-- ============================================================

create or replace function public.get_integration_api_engine_health(
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
        'integration_api.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'active_connections',(
      select count(*)
      from public.integration_connections c
      where c.status = 'active'
        and c.enabled = true
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'unhealthy_connections',(
      select count(*)
      from public.integration_connections c
      where c.health_status in ('degraded','unhealthy')
        and (
          requested_organization_id is null
          or c.organization_id = requested_organization_id
        )
    ),

    'expired_api_keys',(
      select count(*)
      from public.api_keys k
      where (
        k.status = 'expired'
        or (
          k.expires_at is not null
          and k.expires_at <= now()
        )
      )
      and (
        requested_organization_id is null
        or k.organization_id = requested_organization_id
      )
    ),

    'queued_webhook_deliveries',(
      select count(*)
      from public.webhook_delivery_jobs j
      where j.status in ('queued','claimed','delivering','failed')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'dead_lettered_webhooks',(
      select count(*)
      from public.webhook_delivery_jobs j
      where j.status = 'dead_lettered'
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'pending_inbound_webhooks',(
      select count(*)
      from public.inbound_webhook_inbox i
      where i.status in ('received','validated','processing','failed')
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'queued_sync_jobs',(
      select count(*)
      from public.integration_sync_jobs j
      where j.status in ('queued','claimed','running','failed')
        and (
          requested_organization_id is null
          or j.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.integration_event_outbox e
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
on function public.get_integration_api_engine_health(uuid)
from public;

grant execute
on function public.get_integration_api_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 40. ROW LEVEL SECURITY
-- ============================================================

alter table public.integration_providers enable row level security;
alter table public.integration_connections enable row level security;
alter table public.api_clients enable row level security;
alter table public.api_keys enable row level security;
alter table public.oauth_clients enable row level security;
alter table public.oauth_authorization_states enable row level security;
alter table public.oauth_token_metadata enable row level security;
alter table public.api_endpoints enable row level security;
alter table public.api_access_policies enable row level security;
alter table public.api_rate_limit_profiles enable row level security;
alter table public.api_rate_limit_counters enable row level security;
alter table public.api_idempotency_keys enable row level security;
alter table public.api_request_logs enable row level security;
alter table public.webhook_endpoints enable row level security;
alter table public.webhook_subscriptions enable row level security;
alter table public.webhook_delivery_jobs enable row level security;
alter table public.inbound_webhook_inbox enable row level security;
alter table public.integration_sync_definitions enable row level security;
alter table public.integration_field_mappings enable row level security;
alter table public.integration_sync_checkpoints enable row level security;
alter table public.integration_sync_jobs enable row level security;
alter table public.integration_entity_links enable row level security;
alter table public.integration_event_outbox enable row level security;
alter table public.integration_logs enable row level security;

drop policy if exists integration_providers_authenticated_select
on public.integration_providers;

create policy integration_providers_authenticated_select
on public.integration_providers
for select
to authenticated
using (true);

drop policy if exists integration_providers_service_policy
on public.integration_providers;

create policy integration_providers_service_policy
on public.integration_providers
for all
to service_role
using (true)
with check (true);

drop policy if exists api_endpoints_authenticated_select
on public.api_endpoints;

create policy api_endpoints_authenticated_select
on public.api_endpoints
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'integration_api.view'
  )
  or public.has_organization_permission(
    organization_id,
    'integration_api.view_all'
  )
);

drop policy if exists api_endpoints_service_policy
on public.api_endpoints;

create policy api_endpoints_service_policy
on public.api_endpoints
for all
to service_role
using (true)
with check (true);

drop policy if exists api_rate_limit_profiles_authenticated_select
on public.api_rate_limit_profiles;

create policy api_rate_limit_profiles_authenticated_select
on public.api_rate_limit_profiles
for select
to authenticated
using (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'integration_api.view'
  )
  or public.has_organization_permission(
    organization_id,
    'integration_api.view_all'
  )
);

drop policy if exists api_rate_limit_profiles_service_policy
on public.api_rate_limit_profiles;

create policy api_rate_limit_profiles_service_policy
on public.api_rate_limit_profiles
for all
to service_role
using (true)
with check (true);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'integration_connections',
    'api_clients',
    'api_keys',
    'oauth_clients',
    'oauth_authorization_states',
    'oauth_token_metadata',
    'api_access_policies',
    'api_rate_limit_counters',
    'api_idempotency_keys',
    'api_request_logs',
    'webhook_endpoints',
    'webhook_subscriptions',
    'webhook_delivery_jobs',
    'inbound_webhook_inbox',
    'integration_sync_definitions',
    'integration_field_mappings',
    'integration_sync_checkpoints',
    'integration_sync_jobs',
    'integration_entity_links',
    'integration_event_outbox',
    'integration_logs'
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
           ''integration_api.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''integration_api.view_all''
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

drop policy if exists integration_connections_write_policy
on public.integration_connections;

create policy integration_connections_write_policy
on public.integration_connections
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'integration_api.manage_connections'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'integration_api.manage_connections'
  )
);

drop policy if exists api_clients_write_policy
on public.api_clients;

create policy api_clients_write_policy
on public.api_clients
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'integration_api.manage_api_clients'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'integration_api.manage_api_clients'
  )
);

drop policy if exists webhook_endpoints_write_policy
on public.webhook_endpoints;

create policy webhook_endpoints_write_policy
on public.webhook_endpoints
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'integration_api.manage_webhooks'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'integration_api.manage_webhooks'
  )
);

-- ============================================================
-- 41. GRANTS
-- ============================================================

grant select
on
  public.integration_providers,
  public.integration_connections,
  public.api_clients,
  public.api_keys,
  public.oauth_clients,
  public.oauth_authorization_states,
  public.oauth_token_metadata,
  public.api_endpoints,
  public.api_access_policies,
  public.api_rate_limit_profiles,
  public.api_rate_limit_counters,
  public.api_idempotency_keys,
  public.api_request_logs,
  public.webhook_endpoints,
  public.webhook_subscriptions,
  public.webhook_delivery_jobs,
  public.inbound_webhook_inbox,
  public.integration_sync_definitions,
  public.integration_field_mappings,
  public.integration_sync_checkpoints,
  public.integration_sync_jobs,
  public.integration_entity_links,
  public.integration_event_outbox,
  public.integration_logs
to authenticated;

grant insert,update,delete
on
  public.integration_connections,
  public.api_clients,
  public.api_keys,
  public.oauth_clients,
  public.oauth_authorization_states,
  public.oauth_token_metadata,
  public.api_access_policies,
  public.webhook_endpoints,
  public.webhook_subscriptions,
  public.integration_sync_definitions,
  public.integration_field_mappings,
  public.integration_sync_checkpoints,
  public.integration_entity_links
to authenticated;

grant all
on
  public.integration_providers,
  public.integration_connections,
  public.api_clients,
  public.api_keys,
  public.oauth_clients,
  public.oauth_authorization_states,
  public.oauth_token_metadata,
  public.api_endpoints,
  public.api_access_policies,
  public.api_rate_limit_profiles,
  public.api_rate_limit_counters,
  public.api_idempotency_keys,
  public.api_request_logs,
  public.webhook_endpoints,
  public.webhook_subscriptions,
  public.webhook_delivery_jobs,
  public.inbound_webhook_inbox,
  public.integration_sync_definitions,
  public.integration_field_mappings,
  public.integration_sync_checkpoints,
  public.integration_sync_jobs,
  public.integration_entity_links,
  public.integration_event_outbox,
  public.integration_logs
to service_role;

-- ============================================================
-- 42. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'integration_providers',
    'integration_connections',
    'api_clients',
    'api_keys',
    'oauth_clients',
    'oauth_authorization_states',
    'oauth_token_metadata',
    'api_endpoints',
    'api_access_policies',
    'api_rate_limit_profiles',
    'api_rate_limit_counters',
    'api_idempotency_keys',
    'api_request_logs',
    'webhook_endpoints',
    'webhook_subscriptions',
    'webhook_delivery_jobs',
    'inbound_webhook_inbox',
    'integration_sync_definitions',
    'integration_field_mappings',
    'integration_sync_checkpoints',
    'integration_sync_jobs',
    'integration_entity_links',
    'integration_event_outbox',
    'integration_logs'
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
    'create_integration_connection',
    'create_api_key',
    'validate_api_key',
    'register_api_idempotency_key',
    'complete_api_idempotency_key',
    'check_api_rate_limit',
    'enqueue_webhook_delivery',
    'claim_webhook_delivery',
    'complete_webhook_delivery',
    'ingest_inbound_webhook',
    'create_integration_sync_job',
    'claim_integration_sync_job',
    'complete_integration_sync_job',
    'publish_integration_event',
    'get_integration_api_engine_health'
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
      '023 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 43. MIGRATION AUDIT
-- ============================================================

insert into public.integration_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.023.completed',
  'Integration & API Engine migration 023 completed',
  jsonb_build_object(
    'migration',
    '023_integration_api_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'providers',
      'connections',
      'api_clients',
      'api_keys',
      'oauth',
      'endpoints',
      'access_policies',
      'rate_limits',
      'idempotency',
      'request_logs',
      'webhook_endpoints',
      'webhook_subscriptions',
      'webhook_delivery',
      'inbound_webhook_inbox',
      'sync_definitions',
      'field_mappings',
      'checkpoints',
      'sync_jobs',
      'entity_links',
      'analytics',
      'event_outbox'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.integration_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.023.completed'
);

commit;