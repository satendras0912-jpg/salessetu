-- ============================================================
-- SalesSetu Enterprise
-- 011_lead_validation_engine.sql
-- Production master migration
-- Consolidated Part 1 + Part 2 + Part 3
-- ============================================================
--
-- Run the complete file once in Supabase SQL Editor as postgres.
-- Transaction begins in Part 1 and commits at the end of Part 3.
-- Includes compatibility guards for partially-created tables.
-- ============================================================

-- ============================================================
-- SalesSetu Enterprise
-- Migration 011: Lead Validation Engine
-- Part 1: Schema, Tables, Indexes, Permissions and RLS
-- PostgreSQL / Supabase
-- ============================================================
--
-- IMPORTANT:
--   • This is Part 1 only.
--   • Do not add COMMIT yet.
--   • Part 2 and Part 3 will extend this same transaction.
--   • Final consolidated migration will contain the final COMMIT.
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   009_workflow_engine_v2.sql
--   010_ai_calling_engine.sql
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ============================================================
-- 1. RBAC PERMISSIONS
-- Existing schema:
-- permissions(id, module, action, code, description, created_at)
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
    ('lead_validation','view','lead_validation.view','View lead validation records and results'),
    ('lead_validation','create','lead_validation.create','Create lead validation jobs and profiles'),
    ('lead_validation','update','lead_validation.update','Update lead validation configuration and results'),
    ('lead_validation','delete','lead_validation.delete','Delete or archive lead validation records'),
    ('lead_validation','execute','lead_validation.execute','Execute lead validation jobs'),
    ('lead_validation','retry','lead_validation.retry','Retry failed lead validation jobs'),
    ('lead_validation','cancel','lead_validation.cancel','Cancel queued or running validation jobs'),
    ('lead_validation','manage_rules','lead_validation.manage_rules','Manage lead validation rules'),
    ('lead_validation','manage_profiles','lead_validation.manage_profiles','Manage validation profiles'),
    ('lead_validation','manage_blacklist','lead_validation.manage_blacklist','Manage blacklist and suppression data'),
    ('lead_validation','manage_sources','lead_validation.manage_sources','Manage source quality settings'),
    ('lead_validation','review','lead_validation.review','Review validation results manually'),
    ('lead_validation','override','lead_validation.override','Override validation decisions and scores'),
    ('lead_validation','view_evidence','lead_validation.view_evidence','View detailed validation evidence'),
    ('lead_validation','view_logs','lead_validation.view_logs','View lead validation logs'),
    ('lead_validation','view_all','lead_validation.view_all','View all organization validation records')
) as permission_data(module, action, code, description)
where not exists (
  select 1
  from public.permissions existing_permission
  where existing_permission.code = permission_data.code
);

-- ============================================================
-- 2. VALIDATION RULE CATALOGUE
-- ============================================================

create table if not exists public.lead_validation_rule_types (
  code text primary key,
  display_name text not null,
  category text not null
    check (
      category in (
        'identity',
        'contact',
        'duplicate',
        'fraud',
        'behavior',
        'source',
        'consent',
        'suppression',
        'location',
        'quality',
        'custom'
      )
    ),
  default_severity text not null default 'medium'
    check (default_severity in ('info','low','medium','high','critical')),
  default_weight numeric(8,2) not null default 0,
  is_blocking_by_default boolean not null default false,
  description text,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

insert into public.lead_validation_rule_types (
  code,
  display_name,
  category,
  default_severity,
  default_weight,
  is_blocking_by_default,
  description
)
values
  ('phone_format','Phone Format Validation','contact','high',20,true,'Validates normalized phone structure'),
  ('phone_length','Phone Length Validation','contact','high',20,true,'Validates phone number length'),
  ('phone_repeated_digits','Repeated Digit Phone','fraud','medium',15,false,'Detects suspicious repeated phone digits'),
  ('email_format','Email Format Validation','contact','medium',10,false,'Validates email syntax'),
  ('disposable_email','Disposable Email Detection','fraud','high',25,false,'Detects disposable email domains'),
  ('duplicate_phone','Duplicate Phone Detection','duplicate','high',30,false,'Detects leads sharing the same phone'),
  ('duplicate_email','Duplicate Email Detection','duplicate','medium',20,false,'Detects leads sharing the same email'),
  ('duplicate_device','Duplicate Device Detection','duplicate','medium',20,false,'Detects repeated device fingerprints'),
  ('duplicate_ip','Duplicate IP Detection','duplicate','medium',15,false,'Detects repeated IP submissions'),
  ('rapid_submission','Rapid Submission Detection','behavior','high',25,false,'Detects automated or repeated fast submissions'),
  ('form_completion_speed','Form Completion Speed','behavior','medium',15,false,'Detects unrealistically fast form completion'),
  ('source_reputation','Source Reputation Score','source','medium',20,false,'Checks historical source quality'),
  ('campaign_reputation','Campaign Reputation Score','source','medium',20,false,'Checks historical campaign quality'),
  ('consent_available','Consent Availability','consent','critical',40,true,'Checks required outreach consent'),
  ('suppression_match','Suppression Match','suppression','critical',100,true,'Checks DNC and blacklist suppression'),
  ('location_consistency','Location Consistency','location','medium',15,false,'Checks declared and detected location consistency'),
  ('name_quality','Name Quality Validation','identity','low',10,false,'Detects invalid or placeholder names'),
  ('budget_quality','Budget Quality Validation','quality','low',10,false,'Checks budget field quality'),
  ('project_interest_quality','Project Interest Quality','quality','low',10,false,'Checks project interest quality'),
  ('custom_rule','Custom Rule','custom','medium',10,false,'Organization-defined validation rule')
on conflict (code) do update
set
  display_name = excluded.display_name,
  category = excluded.category,
  default_severity = excluded.default_severity,
  default_weight = excluded.default_weight,
  is_blocking_by_default = excluded.is_blocking_by_default,
  description = excluded.description;

-- ============================================================
-- 3. VALIDATION PROFILES
-- ============================================================

create table if not exists public.lead_validation_profiles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  profile_code text not null,
  profile_name text not null,
  description text,

  industry text not null default 'real_estate',
  profile_type text not null default 'standard'
    check (
      profile_type in (
        'standard',
        'strict',
        'lenient',
        'campaign_specific',
        'source_specific',
        'custom'
      )
    ),

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'active',
        'inactive',
        'archived'
      )
    ),

  trust_score_threshold numeric(8,2) not null default 60,
  manual_review_threshold numeric(8,2) not null default 40,
  rejection_threshold numeric(8,2) not null default 20,

  authenticity_weight numeric(8,2) not null default 30,
  contactability_weight numeric(8,2) not null default 25,
  completeness_weight numeric(8,2) not null default 15,
  intent_weight numeric(8,2) not null default 20,
  source_quality_weight numeric(8,2) not null default 10,

  duplicate_window_days integer not null default 180
    check (duplicate_window_days >= 0),

  duplicate_phone_enabled boolean not null default true,
  duplicate_email_enabled boolean not null default true,
  duplicate_device_enabled boolean not null default true,
  duplicate_ip_enabled boolean not null default true,

  require_phone boolean not null default true,
  require_email boolean not null default false,
  require_consent boolean not null default true,

  auto_approve_enabled boolean not null default true,
  auto_reject_enabled boolean not null default true,
  manual_review_enabled boolean not null default true,

  allow_ai_call_when_manual_review boolean not null default false,
  allow_ai_call_when_duplicate boolean not null default false,

  default_ai_call_eligibility text not null default 'blocked'
    check (
      default_ai_call_eligibility in (
        'allowed',
        'blocked',
        'manual_review'
      )
    ),

  configuration jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id, profile_code)
);

create index if not exists lead_validation_profiles_org_status_idx
  on public.lead_validation_profiles (
    organization_id,
    status,
    profile_type
  );

-- ============================================================
-- 4. VALIDATION RULES
-- ============================================================

create table if not exists public.lead_validation_rules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  validation_profile_id uuid not null
    references public.lead_validation_profiles(id)
    on delete cascade,

  rule_type_code text not null
    references public.lead_validation_rule_types(code)
    on delete restrict,

  rule_code text not null,
  rule_name text not null,
  description text,

  status text not null default 'active'
    check (
      status in (
        'draft',
        'active',
        'inactive',
        'archived'
      )
    ),

  execution_order integer not null default 100,
  severity text not null default 'medium'
    check (
      severity in (
        'info',
        'low',
        'medium',
        'high',
        'critical'
      )
    ),

  score_impact numeric(8,2) not null default 0,
  is_blocking boolean not null default false,
  stop_processing_on_failure boolean not null default false,

  condition_configuration jsonb not null default '{}',
  validation_configuration jsonb not null default '{}',
  success_output jsonb not null default '{}',
  failure_output jsonb not null default '{}',

  applies_to_sources text[] not null default '{}',
  excluded_sources text[] not null default '{}',
  applies_to_campaigns text[] not null default '{}',

  metadata jsonb not null default '{}',

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (validation_profile_id, rule_code)
);

create index if not exists lead_validation_rules_profile_order_idx
  on public.lead_validation_rules (
    validation_profile_id,
    status,
    execution_order
  );

create index if not exists lead_validation_rules_org_type_idx
  on public.lead_validation_rules (
    organization_id,
    rule_type_code,
    status
  );

-- ============================================================
-- 5. VALIDATION JOBS
-- ============================================================

create table if not exists public.lead_validation_jobs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  validation_profile_id uuid not null
    references public.lead_validation_profiles(id)
    on delete restrict,

  workflow_execution_id uuid
    references public.workflow_executions(id)
    on delete set null,

  ai_call_job_id uuid
    references public.ai_call_jobs(id)
    on delete set null,

  source_type text not null default 'system'
    check (
      source_type in (
        'lead_created',
        'lead_updated',
        'manual',
        'workflow',
        'n8n',
        'api',
        'import',
        'campaign',
        'system'
      )
    ),

  source_reference text,
  idempotency_key text,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'queued',
        'running',
        'waiting',
        'manual_review',
        'approved',
        'rejected',
        'suppressed',
        'duplicate',
        'failed',
        'cancelled',
        'expired'
      )
    ),

  decision text
    check (
      decision is null
      or decision in (
        'approved',
        'manual_review',
        'rejected',
        'suppressed',
        'duplicate',
        'failed'
      )
    ),

  priority integer not null default 100,

  validation_input jsonb not null default '{}',
  normalized_input jsonb not null default '{}',
  validation_output jsonb not null default '{}',
  error_data jsonb not null default '{}',

  authenticity_score numeric(8,2),
  contactability_score numeric(8,2),
  completeness_score numeric(8,2),
  intent_score numeric(8,2),
  source_quality_score numeric(8,2),
  trust_score numeric(8,2),

  duplicate_score numeric(8,2),
  fraud_score numeric(8,2),
  spam_score numeric(8,2),

  ai_call_eligibility text
    check (
      ai_call_eligibility is null
      or ai_call_eligibility in (
        'allowed',
        'blocked',
        'manual_review',
        'not_required'
      )
    ),

  ai_call_block_reason text,

  matched_duplicate_lead_id uuid
    references public.leads(id)
    on delete set null,

  matched_suppression_id uuid,

  validation_attempt integer not null default 0,
  maximum_attempts integer not null default 3
    check (maximum_attempts between 1 and 10),

  next_retry_at timestamptz,
  queued_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  cancelled_at timestamptz,
  expires_at timestamptz,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.lead_validation_jobs
  add column if not exists lead_id uuid;


create unique index if not exists lead_validation_jobs_idempotency_idx
  on public.lead_validation_jobs (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists lead_validation_jobs_queue_idx
  on public.lead_validation_jobs (
    status,
    priority,
    queued_at,
    created_at
  )
  where status in (
    'pending',
    'queued',
    'waiting'
  );

create index if not exists lead_validation_jobs_lead_idx
  on public.lead_validation_jobs (
    organization_id,
    lead_id,
    created_at desc
  );

create index if not exists lead_validation_jobs_review_idx
  on public.lead_validation_jobs (
    organization_id,
    status,
    trust_score,
    created_at
  )
  where status = 'manual_review';

-- ============================================================
-- 6. VALIDATION RESULTS
-- ============================================================

create table if not exists public.lead_validation_results (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  validation_job_id uuid not null
    references public.lead_validation_jobs(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  validation_profile_id uuid not null
    references public.lead_validation_profiles(id)
    on delete restrict,

  result_version integer not null default 1
    check (result_version > 0),

  status text not null default 'processing'
    check (
      status in (
        'processing',
        'approved',
        'manual_review',
        'rejected',
        'suppressed',
        'duplicate',
        'failed'
      )
    ),

  decision text
    check (
      decision is null
      or decision in (
        'approved',
        'manual_review',
        'rejected',
        'suppressed',
        'duplicate',
        'failed'
      )
    ),

  authenticity_score numeric(8,2) not null default 0,
  contactability_score numeric(8,2) not null default 0,
  completeness_score numeric(8,2) not null default 0,
  intent_score numeric(8,2) not null default 0,
  source_quality_score numeric(8,2) not null default 0,
  trust_score numeric(8,2) not null default 0,

  duplicate_score numeric(8,2) not null default 0,
  fraud_score numeric(8,2) not null default 0,
  spam_score numeric(8,2) not null default 0,

  passed_rule_count integer not null default 0,
  failed_rule_count integer not null default 0,
  warning_rule_count integer not null default 0,
  blocking_rule_count integer not null default 0,

  decision_reasons jsonb not null default '[]',
  risk_factors jsonb not null default '[]',
  quality_factors jsonb not null default '[]',

  duplicate_matches jsonb not null default '[]',
  blacklist_matches jsonb not null default '[]',
  suppression_matches jsonb not null default '[]',

  normalized_phone text,
  normalized_email text,
  detected_country_code text,
  detected_region text,
  detected_city text,

  phone_valid boolean,
  email_valid boolean,
  consent_valid boolean,
  source_valid boolean,

  ai_call_eligibility text not null default 'blocked'
    check (
      ai_call_eligibility in (
        'allowed',
        'blocked',
        'manual_review',
        'not_required'
      )
    ),

  ai_call_block_reason text,

  recommended_action text,
  recommended_workflow_code text,

  summary text,
  score_breakdown jsonb not null default '{}',
  model_data jsonb not null default '{}',

  manually_reviewed boolean not null default false,
  reviewed_by uuid
    references auth.users(id)
    on delete set null,

  reviewed_at timestamptz,
  review_decision text
    check (
      review_decision is null
      or review_decision in (
        'approved',
        'rejected',
        'suppressed',
        'duplicate',
        'needs_more_information'
      )
    ),

  review_notes text,

  overridden boolean not null default false,
  overridden_by uuid
    references auth.users(id)
    on delete set null,

  overridden_at timestamptz,
  override_reason text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (validation_job_id, result_version)
);

alter table public.lead_validation_results
  add column if not exists lead_id uuid;


create index if not exists lead_validation_results_lead_idx
  on public.lead_validation_results (
    organization_id,
    lead_id,
    created_at desc
  );

create index if not exists lead_validation_results_decision_idx
  on public.lead_validation_results (
    organization_id,
    decision,
    trust_score,
    created_at desc
  );

create index if not exists lead_validation_results_ai_call_idx
  on public.lead_validation_results (
    organization_id,
    ai_call_eligibility,
    created_at desc
  );

-- ============================================================
-- 7. RULE EXECUTION RESULTS
-- ============================================================

create table if not exists public.lead_validation_rule_results (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  validation_job_id uuid not null
    references public.lead_validation_jobs(id)
    on delete cascade,

  validation_result_id uuid
    references public.lead_validation_results(id)
    on delete cascade,

  validation_rule_id uuid not null
    references public.lead_validation_rules(id)
    on delete restrict,

  rule_type_code text not null
    references public.lead_validation_rule_types(code)
    on delete restrict,

  rule_code text not null,
  execution_order integer not null default 100,

  status text not null
    check (
      status in (
        'pending',
        'running',
        'passed',
        'failed',
        'warning',
        'skipped',
        'error'
      )
    ),

  severity text not null
    check (
      severity in (
        'info',
        'low',
        'medium',
        'high',
        'critical'
      )
    ),

  is_blocking boolean not null default false,
  score_impact numeric(8,2) not null default 0,
  awarded_score numeric(8,2) not null default 0,

  input_data jsonb not null default '{}',
  output_data jsonb not null default '{}',
  evidence_summary jsonb not null default '{}',

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  started_at timestamptz,
  completed_at timestamptz,
  duration_ms bigint,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (validation_job_id, validation_rule_id)
);

create index if not exists lead_validation_rule_results_job_order_idx
  on public.lead_validation_rule_results (
    validation_job_id,
    execution_order
  );

create index if not exists lead_validation_rule_results_failure_idx
  on public.lead_validation_rule_results (
    organization_id,
    status,
    severity,
    created_at desc
  )
  where status in ('failed','warning','error');

-- ============================================================
-- 8. VALIDATION EVIDENCE
-- ============================================================

create table if not exists public.lead_validation_evidence (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  validation_job_id uuid not null
    references public.lead_validation_jobs(id)
    on delete cascade,

  validation_result_id uuid
    references public.lead_validation_results(id)
    on delete cascade,

  rule_result_id uuid
    references public.lead_validation_rule_results(id)
    on delete cascade,

  evidence_type text not null
    check (
      evidence_type in (
        'lead_field',
        'duplicate_match',
        'phone_check',
        'email_check',
        'ip_check',
        'device_check',
        'source_check',
        'consent_check',
        'suppression_check',
        'behavior_check',
        'location_check',
        'external_api',
        'ai_analysis',
        'manual_note',
        'system'
      )
    ),

  evidence_key text,
  evidence_value jsonb not null default '{}',
  evidence_text text,

  confidence numeric(8,4),
  reliability text
    check (
      reliability is null
      or reliability in (
        'unknown',
        'low',
        'medium',
        'high',
        'verified'
      )
    ),

  source_name text,
  source_reference text,
  source_timestamp timestamptz,

  is_sensitive boolean not null default false,
  is_redacted boolean not null default false,

  metadata jsonb not null default '{}',

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now()
);

create index if not exists lead_validation_evidence_job_idx
  on public.lead_validation_evidence (
    validation_job_id,
    evidence_type,
    created_at
  );

create index if not exists lead_validation_evidence_result_idx
  on public.lead_validation_evidence (
    validation_result_id,
    evidence_type
  );

-- ============================================================
-- 9. DUPLICATE MATCHES
-- ============================================================

create table if not exists public.lead_duplicate_matches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  validation_job_id uuid not null
    references public.lead_validation_jobs(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  matched_lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  match_type text not null
    check (
      match_type in (
        'exact_phone',
        'exact_email',
        'normalized_phone',
        'normalized_email',
        'device_fingerprint',
        'ip_address',
        'name_phone',
        'name_email',
        'fuzzy_identity',
        'campaign_duplicate',
        'cross_source_duplicate',
        'custom'
      )
    ),

  match_score numeric(8,2) not null default 0,
  confidence numeric(8,4),

  matching_fields jsonb not null default '{}',
  differences jsonb not null default '{}',

  match_window_days integer,
  previous_lead_created_at timestamptz,

  status text not null default 'detected'
    check (
      status in (
        'detected',
        'confirmed',
        'dismissed',
        'merged',
        'ignored'
      )
    ),

  reviewed_by uuid
    references auth.users(id)
    on delete set null,

  reviewed_at timestamptz,
  review_notes text,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (lead_id <> matched_lead_id)
);

alter table public.lead_duplicate_matches
  add column if not exists organization_id uuid,
  add column if not exists validation_job_id uuid,
  add column if not exists lead_id uuid,
  add column if not exists matched_lead_id uuid,
  add column if not exists match_type text,
  add column if not exists match_score numeric(8,2) not null default 0,
  add column if not exists confidence numeric(8,4),
  add column if not exists matching_fields jsonb not null default '{}',
  add column if not exists differences jsonb not null default '{}',
  add column if not exists match_window_days integer,
  add column if not exists previous_lead_created_at timestamptz,
  add column if not exists status text not null default 'detected',
  add column if not exists reviewed_by uuid,
  add column if not exists reviewed_at timestamptz,
  add column if not exists review_notes text,
  add column if not exists metadata jsonb not null default '{}',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();


do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'lead_duplicate_matches_lead_distinct_chk'
      and conrelid = 'public.lead_duplicate_matches'::regclass
  ) then
    alter table public.lead_duplicate_matches
      add constraint lead_duplicate_matches_lead_distinct_chk
      check (lead_id is null or matched_lead_id is null or lead_id <> matched_lead_id)
      not valid;
  end if;
end;
$$;


create index if not exists lead_duplicate_matches_lead_idx
  on public.lead_duplicate_matches (
    organization_id,
    lead_id,
    match_score desc
  );

create index if not exists lead_duplicate_matches_matched_idx
  on public.lead_duplicate_matches (
    organization_id,
    matched_lead_id,
    match_score desc
  );

create unique index if not exists lead_duplicate_matches_unique_idx
  on public.lead_duplicate_matches (
    validation_job_id,
    lead_id,
    matched_lead_id,
    match_type
  );

-- ============================================================
-- 10. DEVICE AND SESSION FINGERPRINTS
-- ============================================================

create table if not exists public.lead_submission_fingerprints (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  source_type text,
  source_id text,
  campaign_id text,
  ad_id text,
  form_id text,

  session_id text,
  device_fingerprint text,
  browser_fingerprint text,
  user_agent text,

  ip_address inet,
  forwarded_ip_address inet,

  country_code text,
  region text,
  city text,
  latitude numeric(10,7),
  longitude numeric(10,7),

  referrer_url text,
  landing_page_url text,

  form_started_at timestamptz,
  form_submitted_at timestamptz,
  form_completion_seconds integer,

  field_interaction_count integer,
  mouse_event_count integer,
  keyboard_event_count integer,

  is_vpn boolean,
  is_proxy boolean,
  is_tor boolean,
  is_datacenter_ip boolean,

  fingerprint_data jsonb not null default '{}',
  behavior_data jsonb not null default '{}',
  network_data jsonb not null default '{}',

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.lead_submission_fingerprints
  add column if not exists lead_id uuid;


create index if not exists lead_submission_fingerprints_device_idx
  on public.lead_submission_fingerprints (
    organization_id,
    device_fingerprint,
    created_at desc
  )
  where device_fingerprint is not null;

create index if not exists lead_submission_fingerprints_ip_idx
  on public.lead_submission_fingerprints (
    organization_id,
    ip_address,
    created_at desc
  )
  where ip_address is not null;

create index if not exists lead_submission_fingerprints_campaign_idx
  on public.lead_submission_fingerprints (
    organization_id,
    campaign_id,
    created_at desc
  );

-- ============================================================
-- 11. BLACKLIST AND SUPPRESSION
-- ============================================================

create table if not exists public.lead_validation_blacklist (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid
    references public.organizations(id)
    on delete cascade,

  blacklist_type text not null
    check (
      blacklist_type in (
        'phone',
        'email',
        'email_domain',
        'ip_address',
        'device_fingerprint',
        'browser_fingerprint',
        'name',
        'source',
        'campaign',
        'location',
        'custom'
      )
    ),

  match_value text not null,
  normalized_value text,

  match_mode text not null default 'exact'
    check (
      match_mode in (
        'exact',
        'prefix',
        'suffix',
        'contains',
        'regex',
        'cidr'
      )
    ),

  scope text not null default 'organization'
    check (
      scope in (
        'global',
        'organization'
      )
    ),

  severity text not null default 'high'
    check (
      severity in (
        'low',
        'medium',
        'high',
        'critical'
      )
    ),

  action text not null default 'reject'
    check (
      action in (
        'flag',
        'manual_review',
        'reject',
        'suppress',
        'block_ai_call'
      )
    ),

  reason text,
  source text,

  is_active boolean not null default true,
  active_from timestamptz not null default now(),
  active_until timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists lead_validation_blacklist_lookup_idx
  on public.lead_validation_blacklist (
    organization_id,
    blacklist_type,
    normalized_value,
    is_active
  );

create index if not exists lead_validation_blacklist_global_idx
  on public.lead_validation_blacklist (
    blacklist_type,
    normalized_value
  )
  where scope = 'global'
    and is_active = true;

-- ============================================================
-- 12. DISPOSABLE AND RISKY EMAIL DOMAINS
-- ============================================================

create table if not exists public.lead_validation_email_domains (
  domain text primary key,
  domain_type text not null
    check (
      domain_type in (
        'disposable',
        'temporary',
        'free',
        'business',
        'education',
        'government',
        'invalid',
        'suspicious',
        'unknown'
      )
    ),

  risk_score numeric(8,2) not null default 0,
  is_blocked boolean not null default false,
  source text,
  last_verified_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists lead_validation_email_domains_risk_idx
  on public.lead_validation_email_domains (
    domain_type,
    risk_score desc
  );

-- ============================================================
-- 13. SOURCE QUALITY
-- ============================================================

create table if not exists public.lead_source_quality_scores (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  source_type text not null,
  source_identifier text not null,

  campaign_identifier text,
  adset_identifier text,
  ad_identifier text,
  form_identifier text,

  period_start date not null,
  period_end date not null,

  total_leads integer not null default 0,
  validated_leads integer not null default 0,
  approved_leads integer not null default 0,
  manual_review_leads integer not null default 0,
  rejected_leads integer not null default 0,
  duplicate_leads integer not null default 0,
  fake_leads integer not null default 0,
  suppressed_leads integer not null default 0,

  contacted_leads integer not null default 0,
  connected_leads integer not null default 0,
  qualified_leads integer not null default 0,
  site_visit_leads integer not null default 0,
  converted_leads integer not null default 0,

  approval_rate numeric(8,2) not null default 0,
  rejection_rate numeric(8,2) not null default 0,
  duplicate_rate numeric(8,2) not null default 0,
  fake_rate numeric(8,2) not null default 0,
  contactability_rate numeric(8,2) not null default 0,
  qualification_rate numeric(8,2) not null default 0,
  conversion_rate numeric(8,2) not null default 0,

  average_trust_score numeric(8,2) not null default 0,
  source_quality_score numeric(8,2) not null default 0,

  status text not null default 'normal'
    check (
      status in (
        'excellent',
        'good',
        'normal',
        'poor',
        'blocked'
      )
    ),

  scoring_data jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  check (period_end >= period_start),

  unique (
    organization_id,
    source_type,
    source_identifier,
    campaign_identifier,
    adset_identifier,
    ad_identifier,
    form_identifier,
    period_start,
    period_end
  )
);

create index if not exists lead_source_quality_scores_org_period_idx
  on public.lead_source_quality_scores (
    organization_id,
    period_end desc,
    source_quality_score desc
  );

create index if not exists lead_source_quality_scores_campaign_idx
  on public.lead_source_quality_scores (
    organization_id,
    campaign_identifier,
    period_end desc
  );

-- ============================================================
-- 14. MANUAL REVIEW QUEUE
-- ============================================================

create table if not exists public.lead_validation_review_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  validation_job_id uuid not null
    references public.lead_validation_jobs(id)
    on delete cascade,

  validation_result_id uuid
    references public.lead_validation_results(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'assigned',
        'in_review',
        'approved',
        'rejected',
        'suppressed',
        'duplicate',
        'cancelled',
        'expired'
      )
    ),

  priority integer not null default 100,

  assigned_to uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz,
  due_at timestamptz,

  review_reason text,
  review_context jsonb not null default '{}',

  decision text
    check (
      decision is null
      or decision in (
        'approved',
        'rejected',
        'suppressed',
        'duplicate',
        'needs_more_information'
      )
    ),

  decision_notes text,
  decision_data jsonb not null default '{}',

  decided_by uuid
    references auth.users(id)
    on delete set null,

  decided_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (validation_job_id)
);

alter table public.lead_validation_review_tasks
  add column if not exists lead_id uuid;


create index if not exists lead_validation_review_tasks_queue_idx
  on public.lead_validation_review_tasks (
    organization_id,
    status,
    priority,
    due_at,
    created_at
  )
  where status in (
    'pending',
    'assigned',
    'in_review'
  );

create index if not exists lead_validation_review_tasks_assignee_idx
  on public.lead_validation_review_tasks (
    organization_id,
    assigned_to,
    status,
    due_at
  );

-- ============================================================
-- 15. RETRY QUEUE
-- ============================================================

create table if not exists public.lead_validation_retry_queue (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  validation_job_id uuid not null
    references public.lead_validation_jobs(id)
    on delete cascade,

  queue_status text not null default 'pending'
    check (
      queue_status in (
        'pending',
        'claimed',
        'processing',
        'completed',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  retry_attempt integer not null default 1
    check (retry_attempt > 0),

  maximum_attempts integer not null default 3
    check (maximum_attempts > 0),

  retry_strategy text not null default 'exponential'
    check (
      retry_strategy in (
        'fixed',
        'linear',
        'exponential',
        'custom'
      )
    ),

  retry_delay_seconds integer not null default 60
    check (retry_delay_seconds >= 0),

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

create unique index if not exists lead_validation_retry_active_unique_idx
  on public.lead_validation_retry_queue (
    validation_job_id
  )
  where queue_status in (
    'pending',
    'claimed',
    'processing'
  );

create index if not exists lead_validation_retry_due_idx
  on public.lead_validation_retry_queue (
    queue_status,
    scheduled_at,
    priority
  )
  where queue_status = 'pending';

-- ============================================================
-- 16. VALIDATION LOGS
-- ============================================================

create table if not exists public.lead_validation_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  validation_job_id uuid
    references public.lead_validation_jobs(id)
    on delete cascade,

  validation_result_id uuid
    references public.lead_validation_results(id)
    on delete set null,

  rule_result_id uuid
    references public.lead_validation_rule_results(id)
    on delete set null,

  lead_id uuid
    references public.leads(id)
    on delete set null,

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

  log_type text not null default 'validation',
  event_name text,
  message text,

  error_code text,
  error_message text,

  log_data jsonb not null default '{}',

  trace_id text,
  correlation_id text,

  created_at timestamptz not null default now()
);

alter table public.lead_validation_logs
  add column if not exists lead_id uuid;


create index if not exists lead_validation_logs_job_idx
  on public.lead_validation_logs (
    validation_job_id,
    created_at
  );

create index if not exists lead_validation_logs_org_level_idx
  on public.lead_validation_logs (
    organization_id,
    log_level,
    created_at desc
  );

-- ============================================================
-- 17. WEBHOOK / EXTERNAL VALIDATION EVENTS
-- ============================================================

create table if not exists public.lead_validation_external_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid
    references public.organizations(id)
    on delete cascade,

  validation_job_id uuid
    references public.lead_validation_jobs(id)
    on delete set null,

  provider_name text,
  provider_event_id text,
  event_type text not null,

  request_payload jsonb not null default '{}',
  response_payload jsonb not null default '{}',

  processing_status text not null default 'received'
    check (
      processing_status in (
        'received',
        'processing',
        'processed',
        'ignored',
        'failed',
        'dead_lettered'
      )
    ),

  processing_attempts integer not null default 0,
  next_processing_at timestamptz,

  signature_valid boolean,

  error_code text,
  error_message text,
  error_data jsonb not null default '{}',

  received_at timestamptz not null default now(),
  processed_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

create unique index if not exists lead_validation_external_event_unique_idx
  on public.lead_validation_external_events (
    provider_name,
    provider_event_id
  )
  where provider_event_id is not null;

create index if not exists lead_validation_external_processing_idx
  on public.lead_validation_external_events (
    processing_status,
    next_processing_at,
    received_at
  )
  where processing_status in (
    'received',
    'failed'
  );

-- ============================================================
-- 18. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'lead_validation_profiles',
    'lead_validation_rules',
    'lead_validation_jobs',
    'lead_validation_results',
    'lead_validation_rule_results',
    'lead_duplicate_matches',
    'lead_submission_fingerprints',
    'lead_validation_blacklist',
    'lead_validation_email_domains',
    'lead_source_quality_scores',
    'lead_validation_review_tasks',
    'lead_validation_retry_queue'
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
-- 19. ENABLE ROW LEVEL SECURITY
-- ============================================================

alter table public.lead_validation_rule_types
  enable row level security;

alter table public.lead_validation_profiles
  enable row level security;

alter table public.lead_validation_rules
  enable row level security;

alter table public.lead_validation_jobs
  enable row level security;

alter table public.lead_validation_results
  enable row level security;

alter table public.lead_validation_rule_results
  enable row level security;

alter table public.lead_validation_evidence
  enable row level security;

alter table public.lead_duplicate_matches
  enable row level security;

alter table public.lead_submission_fingerprints
  enable row level security;

alter table public.lead_validation_blacklist
  enable row level security;

alter table public.lead_validation_email_domains
  enable row level security;

alter table public.lead_source_quality_scores
  enable row level security;

alter table public.lead_validation_review_tasks
  enable row level security;

alter table public.lead_validation_retry_queue
  enable row level security;

alter table public.lead_validation_logs
  enable row level security;

alter table public.lead_validation_external_events
  enable row level security;

-- ============================================================
-- 20. GLOBAL REFERENCE TABLE POLICIES
-- ============================================================

drop policy if exists
lead_validation_rule_types_authenticated_select
on public.lead_validation_rule_types;

create policy
lead_validation_rule_types_authenticated_select
on public.lead_validation_rule_types
for select
to authenticated
using (true);

drop policy if exists
lead_validation_rule_types_service_all
on public.lead_validation_rule_types;

create policy
lead_validation_rule_types_service_all
on public.lead_validation_rule_types
for all
to service_role
using (true)
with check (true);

drop policy if exists
lead_validation_email_domains_authenticated_select
on public.lead_validation_email_domains;

create policy
lead_validation_email_domains_authenticated_select
on public.lead_validation_email_domains
for select
to authenticated
using (true);

drop policy if exists
lead_validation_email_domains_service_all
on public.lead_validation_email_domains;

create policy
lead_validation_email_domains_service_all
on public.lead_validation_email_domains
for all
to service_role
using (true)
with check (true);

-- ============================================================
-- 21. ORGANIZATION-SCOPED SELECT AND SERVICE POLICIES
-- ============================================================

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'lead_validation_profiles',
    'lead_validation_rules',
    'lead_validation_jobs',
    'lead_validation_results',
    'lead_validation_rule_results',
    'lead_validation_evidence',
    'lead_duplicate_matches',
    'lead_submission_fingerprints',
    'lead_validation_blacklist',
    'lead_source_quality_scores',
    'lead_validation_review_tasks',
    'lead_validation_retry_queue',
    'lead_validation_logs',
    'lead_validation_external_events'
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
         public.has_organization_permission(
           organization_id,
           ''lead_validation.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''lead_validation.view_all''
         )
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

-- ============================================================
-- 22. AUTHENTICATED WRITE POLICIES
-- ============================================================

drop policy if exists
lead_validation_profiles_write
on public.lead_validation_profiles;

create policy
lead_validation_profiles_write
on public.lead_validation_profiles
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'lead_validation.manage_profiles'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'lead_validation.manage_profiles'
  )
);

drop policy if exists
lead_validation_rules_write
on public.lead_validation_rules;

create policy
lead_validation_rules_write
on public.lead_validation_rules
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'lead_validation.manage_rules'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'lead_validation.manage_rules'
  )
);

drop policy if exists
lead_validation_jobs_write
on public.lead_validation_jobs;

create policy
lead_validation_jobs_write
on public.lead_validation_jobs
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'lead_validation.execute'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'lead_validation.execute'
  )
);

drop policy if exists
lead_validation_blacklist_write
on public.lead_validation_blacklist;

create policy
lead_validation_blacklist_write
on public.lead_validation_blacklist
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'lead_validation.manage_blacklist'
  )
)
with check (
  organization_id is null
  or public.has_organization_permission(
    organization_id,
    'lead_validation.manage_blacklist'
  )
);

drop policy if exists
lead_source_quality_scores_write
on public.lead_source_quality_scores;

create policy
lead_source_quality_scores_write
on public.lead_source_quality_scores
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'lead_validation.manage_sources'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'lead_validation.manage_sources'
  )
);

drop policy if exists
lead_validation_review_tasks_write
on public.lead_validation_review_tasks;

create policy
lead_validation_review_tasks_write
on public.lead_validation_review_tasks
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'lead_validation.review'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'lead_validation.review'
  )
);

-- ============================================================
-- 23. GRANTS
-- ============================================================

grant select
on public.lead_validation_rule_types
to authenticated;

grant select
on public.lead_validation_email_domains
to authenticated;

grant select
on
  public.lead_validation_profiles,
  public.lead_validation_rules,
  public.lead_validation_jobs,
  public.lead_validation_results,
  public.lead_validation_rule_results,
  public.lead_validation_evidence,
  public.lead_duplicate_matches,
  public.lead_submission_fingerprints,
  public.lead_validation_blacklist,
  public.lead_source_quality_scores,
  public.lead_validation_review_tasks,
  public.lead_validation_retry_queue,
  public.lead_validation_logs,
  public.lead_validation_external_events
to authenticated;

grant insert, update, delete
on
  public.lead_validation_profiles,
  public.lead_validation_rules,
  public.lead_validation_jobs,
  public.lead_validation_blacklist,
  public.lead_source_quality_scores,
  public.lead_validation_review_tasks
to authenticated;

grant all
on
  public.lead_validation_rule_types,
  public.lead_validation_profiles,
  public.lead_validation_rules,
  public.lead_validation_jobs,
  public.lead_validation_results,
  public.lead_validation_rule_results,
  public.lead_validation_evidence,
  public.lead_duplicate_matches,
  public.lead_submission_fingerprints,
  public.lead_validation_blacklist,
  public.lead_validation_email_domains,
  public.lead_source_quality_scores,
  public.lead_validation_review_tasks,
  public.lead_validation_retry_queue,
  public.lead_validation_logs,
  public.lead_validation_external_events
to service_role;

-- ============================================================
-- 24. PART 1 VALIDATION
-- ============================================================

do $$
begin
  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'lead_validation_jobs'
  ) then
    raise exception
      '011 Part 1 validation failed: lead_validation_jobs missing';
  end if;

  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'lead_validation_results'
  ) then
    raise exception
      '011 Part 1 validation failed: lead_validation_results missing';
  end if;

  if not exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = 'lead_duplicate_matches'
  ) then
    raise exception
      '011 Part 1 validation failed: lead_duplicate_matches missing';
  end if;
end;
$$;

-- ============================================================
-- SalesSetu Enterprise
-- Migration 011: Lead Validation Engine
-- Part 2: Validation Functions, Duplicate Detection,
-- Fraud Scoring and AI-Call Eligibility
-- PostgreSQL / Supabase
-- ============================================================
--
-- IMPORTANT:
--   • Append this file after Part 1.
--   • This file does not contain BEGIN or COMMIT.
--   • Part 3 will add analytics, orchestration and final COMMIT.
-- ============================================================

-- ============================================================
-- 25. GENERIC HELPERS
-- ============================================================

create or replace function public.lead_validation_json_text(
  requested_payload jsonb,
  requested_keys text[]
)
returns text
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  candidate_key text;
  candidate_value text;
begin
  if requested_payload is null then
    return null;
  end if;

  foreach candidate_key in array requested_keys
  loop
    candidate_value := nullif(btrim(requested_payload ->> candidate_key), '');

    if candidate_value is not null then
      return candidate_value;
    end if;
  end loop;

  return null;
end;
$$;

revoke all
on function public.lead_validation_json_text(jsonb,text[])
from public;

grant execute
on function public.lead_validation_json_text(jsonb,text[])
to authenticated, service_role;

create or replace function public.normalize_lead_validation_phone(
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
  country_digits :=
    regexp_replace(
      coalesce(requested_default_country_code, '+91'),
      '[^0-9]',
      '',
      'g'
    );

  if digits = '' then
    return null;
  end if;

  if length(digits) = 10 then
    return '+' || country_digits || digits;
  end if;

  if left(digits, 2) = '00' then
    return '+' || substring(digits from 3);
  end if;

  if left(digits, length(country_digits)) = country_digits then
    return '+' || digits;
  end if;

  return '+' || digits;
end;
$$;

revoke all
on function public.normalize_lead_validation_phone(text,text)
from public;

grant execute
on function public.normalize_lead_validation_phone(text,text)
to authenticated, service_role;

create or replace function public.normalize_lead_validation_email(
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
    else nullif(lower(btrim(requested_email)), '')
  end;
$$;

revoke all
on function public.normalize_lead_validation_email(text)
from public;

grant execute
on function public.normalize_lead_validation_email(text)
to authenticated, service_role;

create or replace function public.is_valid_lead_validation_email(
  requested_email text
)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select coalesce(
    public.normalize_lead_validation_email(requested_email)
      ~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$',
    false
  );
$$;

revoke all
on function public.is_valid_lead_validation_email(text)
from public;

grant execute
on function public.is_valid_lead_validation_email(text)
to authenticated, service_role;

create or replace function public.get_lead_validation_email_domain(
  requested_email text
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select case
    when public.is_valid_lead_validation_email(requested_email)
      then split_part(
        public.normalize_lead_validation_email(requested_email),
        '@',
        2
      )
    else null
  end;
$$;

revoke all
on function public.get_lead_validation_email_domain(text)
from public;

grant execute
on function public.get_lead_validation_email_domain(text)
to authenticated, service_role;

create or replace function public.clamp_lead_validation_score(
  requested_score numeric
)
returns numeric
language sql
immutable
security definer
set search_path = ''
as $$
  select least(
    greatest(
      coalesce(requested_score, 0),
      0
    ),
    100
  );
$$;

revoke all
on function public.clamp_lead_validation_score(numeric)
from public;

grant execute
on function public.clamp_lead_validation_score(numeric)
to authenticated, service_role;

-- ============================================================
-- 26. LEAD SNAPSHOT
-- Uses to_jsonb so the function remains compatible with
-- different leads table column naming conventions.
-- ============================================================

create or replace function public.get_lead_validation_snapshot(
  requested_lead_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lead_payload jsonb;
begin
  select to_jsonb(lead_record)
  into lead_payload
  from public.leads lead_record
  where lead_record.id = requested_lead_id;

  if lead_payload is null then
    raise exception 'Lead not found';
  end if;

  return lead_payload;
end;
$$;

revoke all
on function public.get_lead_validation_snapshot(uuid)
from public;

grant execute
on function public.get_lead_validation_snapshot(uuid)
to authenticated, service_role;

create or replace function public.get_lead_validation_organization_id(
  requested_lead_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  lead_payload jsonb;
  organization_value text;
begin
  lead_payload := public.get_lead_validation_snapshot(requested_lead_id);

  organization_value :=
    public.lead_validation_json_text(
      lead_payload,
      array[
        'organization_id',
        'organisation_id',
        'org_id'
      ]
    );

  if organization_value is null then
    raise exception
      'Lead organization_id could not be resolved';
  end if;

  return organization_value::uuid;
exception
  when invalid_text_representation then
    raise exception
      'Lead organization_id is not a valid UUID';
end;
$$;

revoke all
on function public.get_lead_validation_organization_id(uuid)
from public;

grant execute
on function public.get_lead_validation_organization_id(uuid)
to authenticated, service_role;

-- ============================================================
-- 27. DEFAULT PROFILE RESOLUTION
-- ============================================================

create or replace function public.resolve_lead_validation_profile(
  requested_organization_id uuid,
  requested_profile_id uuid default null
)
returns public.lead_validation_profiles
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  profile_record public.lead_validation_profiles;
begin
  if requested_profile_id is not null then
    select *
    into profile_record
    from public.lead_validation_profiles profile
    where profile.id = requested_profile_id
      and profile.organization_id = requested_organization_id
      and profile.status = 'active';

    if not found then
      raise exception
        'Active lead validation profile not found';
    end if;

    return profile_record;
  end if;

  select *
  into profile_record
  from public.lead_validation_profiles profile
  where profile.organization_id = requested_organization_id
    and profile.status = 'active'
  order by
    case profile.profile_type
      when 'standard' then 0
      when 'strict' then 1
      when 'lenient' then 2
      else 3
    end,
    profile.created_at asc
  limit 1;

  if not found then
    raise exception
      'No active lead validation profile is configured';
  end if;

  return profile_record;
end;
$$;

revoke all
on function public.resolve_lead_validation_profile(uuid,uuid)
from public;

grant execute
on function public.resolve_lead_validation_profile(uuid,uuid)
to authenticated, service_role;

-- ============================================================
-- 28. CREATE VALIDATION JOB
-- ============================================================

create or replace function public.create_lead_validation_job(
  requested_lead_id uuid,
  requested_profile_id uuid default null,
  requested_source_type text default 'manual',
  requested_source_reference text default null,
  requested_idempotency_key text default null,
  requested_priority integer default 100,
  requested_validation_input jsonb default '{}'::jsonb,
  requested_workflow_execution_id uuid default null
)
returns public.lead_validation_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  organization_value uuid;
  profile_record public.lead_validation_profiles;
  lead_snapshot jsonb;
  existing_job public.lead_validation_jobs;
  created_job public.lead_validation_jobs;
begin
  organization_value :=
    public.get_lead_validation_organization_id(
      requested_lead_id
    );

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      organization_value,
      'lead_validation.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select *
    into existing_job
    from public.lead_validation_jobs job
    where job.organization_id = organization_value
      and job.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_job;
    end if;
  end if;

  profile_record :=
    public.resolve_lead_validation_profile(
      organization_value,
      requested_profile_id
    );

  lead_snapshot :=
    public.get_lead_validation_snapshot(
      requested_lead_id
    );

  insert into public.lead_validation_jobs (
    organization_id,
    lead_id,
    validation_profile_id,
    workflow_execution_id,
    source_type,
    source_reference,
    idempotency_key,
    status,
    priority,
    validation_input,
    normalized_input,
    maximum_attempts,
    queued_at,
    created_by,
    updated_by,
    metadata
  )
  values (
    organization_value,
    requested_lead_id,
    profile_record.id,
    requested_workflow_execution_id,
    requested_source_type,
    requested_source_reference,
    requested_idempotency_key,
    'queued',
    requested_priority,
    coalesce(requested_validation_input, '{}'::jsonb)
      || jsonb_build_object(
        'lead_snapshot',
        lead_snapshot
      ),
    '{}'::jsonb,
    3,
    now(),
    auth.uid(),
    auth.uid(),
    jsonb_build_object(
      'profile_code',
      profile_record.profile_code,
      'profile_type',
      profile_record.profile_type
    )
  )
  returning *
  into created_job;

  insert into public.lead_validation_logs (
    organization_id,
    validation_job_id,
    lead_id,
    log_level,
    log_type,
    event_name,
    message,
    log_data
  )
  values (
    organization_value,
    created_job.id,
    requested_lead_id,
    'info',
    'job',
    'lead_validation.job.created',
    'Lead validation job created',
    jsonb_build_object(
      'profile_id',
      profile_record.id,
      'source_type',
      requested_source_type,
      'priority',
      requested_priority
    )
  );

  return created_job;
end;
$$;

revoke all
on function public.create_lead_validation_job(
  uuid,uuid,text,text,text,integer,jsonb,uuid
)
from public;

grant execute
on function public.create_lead_validation_job(
  uuid,uuid,text,text,text,integer,jsonb,uuid
)
to authenticated, service_role;

-- ============================================================
-- 29. CLAIM VALIDATION JOB
-- ============================================================

create or replace function public.claim_lead_validation_job(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.lead_validation_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
begin
  if requested_worker_id is null
    or btrim(requested_worker_id) = '' then
    raise exception 'Worker ID is required';
  end if;

  if auth.role() <> 'service_role'
    and (
      requested_organization_id is null
      or not public.has_organization_permission(
        requested_organization_id,
        'lead_validation.execute'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into target_job
  from public.lead_validation_jobs job
  where job.status in ('pending','queued','waiting')
    and (
      job.next_retry_at is null
      or job.next_retry_at <= now()
    )
    and (
      job.expires_at is null
      or job.expires_at > now()
    )
    and (
      requested_organization_id is null
      or job.organization_id = requested_organization_id
    )
  order by
    job.priority asc,
    coalesce(job.queued_at, job.created_at) asc,
    job.created_at asc
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.lead_validation_jobs
  set
    status = 'running',
    validation_attempt = validation_attempt + 1,
    started_at = coalesce(started_at, now()),
    metadata =
      metadata
      || jsonb_build_object(
        'worker_id',
        requested_worker_id,
        'lock_token',
        gen_random_uuid()::text,
        'lock_expires_at',
        now()
          + make_interval(
              secs => greatest(
                requested_lock_seconds,
                1
              )
            )
      ),
    updated_at = now()
  where id = target_job.id
  returning *
  into target_job;

  return target_job;
end;
$$;

revoke all
on function public.claim_lead_validation_job(text,uuid,integer)
from public;

grant execute
on function public.claim_lead_validation_job(text,uuid,integer)
to authenticated, service_role;

-- ============================================================
-- 30. NORMALIZE VALIDATION INPUT
-- ============================================================

create or replace function public.normalize_lead_validation_job_input(
  requested_validation_job_id uuid
)
returns public.lead_validation_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  lead_snapshot jsonb;
  phone_value text;
  email_value text;
  name_value text;
  source_value text;
  campaign_value text;
  project_value text;
  budget_value text;
  normalized_phone text;
  normalized_email text;
  email_domain text;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id
  for update;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_job.organization_id,
      'lead_validation.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  lead_snapshot :=
    coalesce(
      target_job.validation_input -> 'lead_snapshot',
      public.get_lead_validation_snapshot(
        target_job.lead_id
      )
    );

  phone_value :=
    public.lead_validation_json_text(
      lead_snapshot,
      array[
        'phone',
        'phone_number',
        'mobile',
        'mobile_number',
        'whatsapp_number',
        'contact_number'
      ]
    );

  email_value :=
    public.lead_validation_json_text(
      lead_snapshot,
      array[
        'email',
        'email_address'
      ]
    );

  name_value :=
    public.lead_validation_json_text(
      lead_snapshot,
      array[
        'name',
        'full_name',
        'lead_name',
        'customer_name'
      ]
    );

  source_value :=
    public.lead_validation_json_text(
      lead_snapshot,
      array[
        'source',
        'lead_source',
        'source_name',
        'source_type'
      ]
    );

  campaign_value :=
    public.lead_validation_json_text(
      lead_snapshot,
      array[
        'campaign_id',
        'campaign_name',
        'utm_campaign'
      ]
    );

  project_value :=
    public.lead_validation_json_text(
      lead_snapshot,
      array[
        'project_preference',
        'project_interest',
        'project_name',
        'interested_project'
      ]
    );

  budget_value :=
    public.lead_validation_json_text(
      lead_snapshot,
      array[
        'budget',
        'budget_range',
        'maximum_budget'
      ]
    );

  normalized_phone :=
    public.normalize_lead_validation_phone(
      phone_value,
      '+91'
    );

  normalized_email :=
    public.normalize_lead_validation_email(
      email_value
    );

  email_domain :=
    public.get_lead_validation_email_domain(
      normalized_email
    );

  update public.lead_validation_jobs
  set
    normalized_input =
      jsonb_build_object(
        'phone_raw',
        phone_value,
        'phone',
        normalized_phone,
        'email_raw',
        email_value,
        'email',
        normalized_email,
        'email_domain',
        email_domain,
        'name',
        name_value,
        'source',
        source_value,
        'campaign',
        campaign_value,
        'project_interest',
        project_value,
        'budget',
        budget_value,
        'lead_snapshot',
        lead_snapshot
      ),
    updated_at = now()
  where id = target_job.id
  returning *
  into target_job;

  return target_job;
end;
$$;

revoke all
on function public.normalize_lead_validation_job_input(uuid)
from public;

grant execute
on function public.normalize_lead_validation_job_input(uuid)
to authenticated, service_role;

-- ============================================================
-- 31. RULE RESULT UPSERT
-- ============================================================

create or replace function public.upsert_lead_validation_rule_result(
  requested_validation_job_id uuid,
  requested_validation_rule_id uuid,
  requested_status text,
  requested_awarded_score numeric default 0,
  requested_output_data jsonb default '{}'::jsonb,
  requested_evidence_summary jsonb default '{}'::jsonb,
  requested_error_code text default null,
  requested_error_message text default null,
  requested_error_data jsonb default '{}'::jsonb
)
returns public.lead_validation_rule_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  target_rule public.lead_validation_rules;
  result_record public.lead_validation_rule_results;
begin
  if requested_status not in (
    'pending',
    'running',
    'passed',
    'failed',
    'warning',
    'skipped',
    'error'
  ) then
    raise exception 'Invalid rule result status';
  end if;

  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  select *
  into target_rule
  from public.lead_validation_rules rule
  where rule.id = requested_validation_rule_id
    and rule.validation_profile_id =
      target_job.validation_profile_id;

  if not found then
    raise exception
      'Lead validation rule not found for job profile';
  end if;

  insert into public.lead_validation_rule_results (
    organization_id,
    validation_job_id,
    validation_rule_id,
    rule_type_code,
    rule_code,
    execution_order,
    status,
    severity,
    is_blocking,
    score_impact,
    awarded_score,
    input_data,
    output_data,
    evidence_summary,
    error_code,
    error_message,
    error_data,
    started_at,
    completed_at,
    duration_ms
  )
  values (
    target_job.organization_id,
    target_job.id,
    target_rule.id,
    target_rule.rule_type_code,
    target_rule.rule_code,
    target_rule.execution_order,
    requested_status,
    target_rule.severity,
    target_rule.is_blocking,
    target_rule.score_impact,
    coalesce(requested_awarded_score, 0),
    target_job.normalized_input,
    coalesce(requested_output_data, '{}'::jsonb),
    coalesce(requested_evidence_summary, '{}'::jsonb),
    requested_error_code,
    requested_error_message,
    coalesce(requested_error_data, '{}'::jsonb),
    now(),
    now(),
    0
  )
  on conflict (
    validation_job_id,
    validation_rule_id
  )
  do update set
    status = excluded.status,
    awarded_score = excluded.awarded_score,
    output_data = excluded.output_data,
    evidence_summary = excluded.evidence_summary,
    error_code = excluded.error_code,
    error_message = excluded.error_message,
    error_data = excluded.error_data,
    completed_at = now(),
    updated_at = now()
  returning *
  into result_record;

  return result_record;
end;
$$;

revoke all
on function public.upsert_lead_validation_rule_result(
  uuid,uuid,text,numeric,jsonb,jsonb,text,text,jsonb
)
from public;

grant execute
on function public.upsert_lead_validation_rule_result(
  uuid,uuid,text,numeric,jsonb,jsonb,text,text,jsonb
)
to authenticated, service_role;

-- ============================================================
-- 32. PHONE QUALITY CHECK
-- ============================================================

create or replace function public.evaluate_lead_validation_phone(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  normalized_phone text;
  digits text;
  is_present boolean;
  is_length_valid boolean;
  repeated_digits boolean;
  score numeric := 100;
  reasons jsonb := '[]'::jsonb;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  normalized_phone :=
    target_job.normalized_input ->> 'phone';

  digits :=
    regexp_replace(
      coalesce(normalized_phone, ''),
      '[^0-9]',
      '',
      'g'
    );

  is_present :=
    normalized_phone is not null;

  is_length_valid :=
    length(digits) between 10 and 15;

  repeated_digits :=
    digits ~ '^([0-9])\1{7,}$'
    or digits in (
      '1234567890',
      '0123456789',
      '9999999999',
      '8888888888',
      '7777777777',
      '0000000000'
    );

  if not is_present then
    score := 0;
    reasons :=
      reasons
      || jsonb_build_array(
        'Phone number is missing'
      );
  elsif not is_length_valid then
    score := score - 80;
    reasons :=
      reasons
      || jsonb_build_array(
        'Phone number length is invalid'
      );
  end if;

  if repeated_digits then
    score := score - 70;
    reasons :=
      reasons
      || jsonb_build_array(
        'Phone number pattern is suspicious'
      );
  end if;

  return jsonb_build_object(
    'valid',
    is_present
      and is_length_valid
      and not repeated_digits,
    'phone_present',
    is_present,
    'length_valid',
    is_length_valid,
    'repeated_digits',
    repeated_digits,
    'score',
    public.clamp_lead_validation_score(score),
    'reasons',
    reasons
  );
end;
$$;

revoke all
on function public.evaluate_lead_validation_phone(uuid)
from public;

grant execute
on function public.evaluate_lead_validation_phone(uuid)
to authenticated, service_role;

-- ============================================================
-- 33. EMAIL QUALITY CHECK
-- ============================================================

create or replace function public.evaluate_lead_validation_email(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  profile_record public.lead_validation_profiles;
  normalized_email text;
  email_domain text;
  email_present boolean;
  email_valid boolean;
  domain_record public.lead_validation_email_domains;
  score numeric := 100;
  reasons jsonb := '[]'::jsonb;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  select *
  into profile_record
  from public.lead_validation_profiles profile
  where profile.id = target_job.validation_profile_id;

  normalized_email :=
    target_job.normalized_input ->> 'email';

  email_domain :=
    target_job.normalized_input ->> 'email_domain';

  email_present :=
    normalized_email is not null;

  email_valid :=
    public.is_valid_lead_validation_email(
      normalized_email
    );

  if not email_present then
    if profile_record.require_email then
      score := 0;
      reasons :=
        reasons
        || jsonb_build_array(
          'Required email address is missing'
        );
    else
      score := 70;
      reasons :=
        reasons
        || jsonb_build_array(
          'Email address is not provided'
        );
    end if;
  elsif not email_valid then
    score := 0;
    reasons :=
      reasons
      || jsonb_build_array(
        'Email address format is invalid'
      );
  else
    select *
    into domain_record
    from public.lead_validation_email_domains domain_data
    where domain_data.domain = email_domain;

    if found then
      score :=
        score - coalesce(
          domain_record.risk_score,
          0
        );

      if domain_record.is_blocked then
        score := 0;
      end if;

      if domain_record.domain_type in (
        'disposable',
        'temporary',
        'invalid',
        'suspicious'
      ) then
        reasons :=
          reasons
          || jsonb_build_array(
            'Email domain is classified as '
            || domain_record.domain_type
          );
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'valid',
    (
      not profile_record.require_email
      and not email_present
    )
    or (
      email_valid
      and coalesce(
        domain_record.is_blocked,
        false
      ) = false
    ),
    'email_present',
    email_present,
    'format_valid',
    email_valid,
    'domain',
    email_domain,
    'domain_type',
    domain_record.domain_type,
    'domain_risk_score',
    domain_record.risk_score,
    'domain_blocked',
    coalesce(
      domain_record.is_blocked,
      false
    ),
    'score',
    public.clamp_lead_validation_score(score),
    'reasons',
    reasons
  );
end;
$$;

revoke all
on function public.evaluate_lead_validation_email(uuid)
from public;

grant execute
on function public.evaluate_lead_validation_email(uuid)
to authenticated, service_role;

-- ============================================================
-- 34. NAME QUALITY CHECK
-- ============================================================

create or replace function public.evaluate_lead_validation_name(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  name_value text;
  normalized_name text;
  suspicious boolean := false;
  score numeric := 100;
  reasons jsonb := '[]'::jsonb;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  name_value :=
    target_job.normalized_input ->> 'name';

  normalized_name :=
    lower(
      btrim(
        coalesce(
          name_value,
          ''
        )
      )
    );

  if normalized_name = '' then
    score := 20;
    reasons :=
      reasons
      || jsonb_build_array(
        'Lead name is missing'
      );
  end if;

  suspicious :=
    normalized_name in (
      'test',
      'testing',
      'abc',
      'abcd',
      'xyz',
      'name',
      'unknown',
      'na',
      'n/a',
      'none',
      'customer',
      'user'
    )
    or normalized_name ~ '^[0-9]+$'
    or normalized_name ~ '^([a-z])\1{2,}$';

  if suspicious then
    score := 0;
    reasons :=
      reasons
      || jsonb_build_array(
        'Lead name appears to be fake or placeholder'
      );
  elsif normalized_name <> ''
    and length(normalized_name) < 2 then
    score := 30;
    reasons :=
      reasons
      || jsonb_build_array(
        'Lead name is too short'
      );
  end if;

  return jsonb_build_object(
    'valid',
    normalized_name <> ''
      and not suspicious
      and length(normalized_name) >= 2,
    'name',
    name_value,
    'suspicious',
    suspicious,
    'score',
    public.clamp_lead_validation_score(score),
    'reasons',
    reasons
  );
end;
$$;

revoke all
on function public.evaluate_lead_validation_name(uuid)
from public;

grant execute
on function public.evaluate_lead_validation_name(uuid)
to authenticated, service_role;

-- ============================================================
-- 35. SUPPRESSION / BLACKLIST CHECK
-- ============================================================

create or replace function public.evaluate_lead_validation_blacklist(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  phone_value text;
  email_value text;
  domain_value text;
  source_value text;
  campaign_value text;
  matches jsonb := '[]'::jsonb;
  blocking_match boolean := false;
  match_record record;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  phone_value :=
    target_job.normalized_input ->> 'phone';

  email_value :=
    target_job.normalized_input ->> 'email';

  domain_value :=
    target_job.normalized_input ->> 'email_domain';

  source_value :=
    target_job.normalized_input ->> 'source';

  campaign_value :=
    target_job.normalized_input ->> 'campaign';

  for match_record in
    select blacklist.*
    from public.lead_validation_blacklist blacklist
    where blacklist.is_active = true
      and blacklist.active_from <= now()
      and (
        blacklist.active_until is null
        or blacklist.active_until > now()
      )
      and (
        blacklist.scope = 'global'
        or blacklist.organization_id =
          target_job.organization_id
      )
      and (
        (
          blacklist.blacklist_type = 'phone'
          and blacklist.match_mode = 'exact'
          and coalesce(
            blacklist.normalized_value,
            blacklist.match_value
          ) = phone_value
        )
        or (
          blacklist.blacklist_type = 'email'
          and blacklist.match_mode = 'exact'
          and lower(
            coalesce(
              blacklist.normalized_value,
              blacklist.match_value
            )
          ) = email_value
        )
        or (
          blacklist.blacklist_type = 'email_domain'
          and blacklist.match_mode = 'exact'
          and lower(
            coalesce(
              blacklist.normalized_value,
              blacklist.match_value
            )
          ) = domain_value
        )
        or (
          blacklist.blacklist_type = 'source'
          and blacklist.match_mode = 'exact'
          and lower(blacklist.match_value) =
            lower(source_value)
        )
        or (
          blacklist.blacklist_type = 'campaign'
          and blacklist.match_mode = 'exact'
          and lower(blacklist.match_value) =
            lower(campaign_value)
        )
      )
  loop
    matches :=
      matches
      || jsonb_build_array(
        jsonb_build_object(
          'blacklist_id',
          match_record.id,
          'type',
          match_record.blacklist_type,
          'action',
          match_record.action,
          'severity',
          match_record.severity,
          'reason',
          match_record.reason
        )
      );

    if match_record.action in (
      'reject',
      'suppress',
      'block_ai_call'
    ) then
      blocking_match := true;
    end if;
  end loop;

  return jsonb_build_object(
    'matched',
    jsonb_array_length(matches) > 0,
    'blocking',
    blocking_match,
    'matches',
    matches,
    'score',
    case
      when blocking_match then 0
      when jsonb_array_length(matches) > 0 then 40
      else 100
    end
  );
end;
$$;

revoke all
on function public.evaluate_lead_validation_blacklist(uuid)
from public;

grant execute
on function public.evaluate_lead_validation_blacklist(uuid)
to authenticated, service_role;

-- ============================================================
-- 36. CONSENT CHECK
-- Uses AI Calling consent table created in migration 010.
-- ============================================================

create or replace function public.evaluate_lead_validation_consent(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  profile_record public.lead_validation_profiles;
  phone_value text;
  latest_consent_status text;
  consent_required boolean;
  consent_valid boolean;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  select *
  into profile_record
  from public.lead_validation_profiles profile
  where profile.id = target_job.validation_profile_id;

  consent_required :=
    profile_record.require_consent;

  phone_value :=
    target_job.normalized_input ->> 'phone';

  select consent.consent_status
  into latest_consent_status
  from public.ai_call_consents consent
  where consent.organization_id =
      target_job.organization_id
    and public.normalize_lead_validation_phone(
      consent.phone_number,
      '+91'
    ) = phone_value
    and consent.consent_type =
      'outbound_ai_call'
    and (
      consent.expires_at is null
      or consent.expires_at > now()
    )
  order by consent.created_at desc
  limit 1;

  consent_valid :=
    not consent_required
    or latest_consent_status = 'granted';

  return jsonb_build_object(
    'required',
    consent_required,
    'status',
    coalesce(
      latest_consent_status,
      'unknown'
    ),
    'valid',
    consent_valid,
    'score',
    case
      when not consent_required then 100
      when latest_consent_status = 'granted' then 100
      when latest_consent_status in (
        'denied',
        'withdrawn'
      ) then 0
      else 30
    end
  );
end;
$$;

revoke all
on function public.evaluate_lead_validation_consent(uuid)
from public;

grant execute
on function public.evaluate_lead_validation_consent(uuid)
to authenticated, service_role;

-- ============================================================
-- 37. SOURCE QUALITY CHECK
-- ============================================================

create or replace function public.evaluate_lead_validation_source(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  source_value text;
  campaign_value text;
  source_record public.lead_source_quality_scores;
  source_score numeric := 50;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  source_value :=
    target_job.normalized_input ->> 'source';

  campaign_value :=
    target_job.normalized_input ->> 'campaign';

  select *
  into source_record
  from public.lead_source_quality_scores score_record
  where score_record.organization_id =
      target_job.organization_id
    and (
      score_record.source_identifier =
        source_value
      or (
        campaign_value is not null
        and score_record.campaign_identifier =
          campaign_value
      )
    )
  order by score_record.period_end desc
  limit 1;

  if found then
    source_score :=
      public.clamp_lead_validation_score(
        source_record.source_quality_score
      );
  end if;

  return jsonb_build_object(
    'source',
    source_value,
    'campaign',
    campaign_value,
    'historical_data_available',
    found,
    'status',
    source_record.status,
    'approval_rate',
    source_record.approval_rate,
    'fake_rate',
    source_record.fake_rate,
    'duplicate_rate',
    source_record.duplicate_rate,
    'score',
    source_score
  );
end;
$$;

revoke all
on function public.evaluate_lead_validation_source(uuid)
from public;

grant execute
on function public.evaluate_lead_validation_source(uuid)
to authenticated, service_role;

-- ============================================================
-- 38. DUPLICATE DETECTION
-- Dynamic JSON extraction keeps this compatible with the
-- current leads schema.
-- ============================================================

create or replace function public.detect_lead_duplicates(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  profile_record public.lead_validation_profiles;
  target_phone text;
  target_email text;
  candidate_record record;
  candidate_payload jsonb;
  candidate_phone text;
  candidate_email text;
  match_type_value text;
  match_score_value numeric;
  matches jsonb := '[]'::jsonb;
  highest_score numeric := 0;
  highest_match_lead_id uuid;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id
  for update;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  select *
  into profile_record
  from public.lead_validation_profiles profile
  where profile.id = target_job.validation_profile_id;

  target_phone :=
    target_job.normalized_input ->> 'phone';

  target_email :=
    target_job.normalized_input ->> 'email';

  delete from public.lead_duplicate_matches
  where validation_job_id = target_job.id;

  for candidate_record in
    select
      lead_record.id,
      to_jsonb(lead_record) as payload
    from public.leads lead_record
    where lead_record.id <> target_job.lead_id
      and (
        to_jsonb(lead_record) ->> 'organization_id'
      ) = target_job.organization_id::text
      and coalesce(
        (
          to_jsonb(lead_record) ->> 'created_at'
        )::timestamptz,
        now()
      ) >=
        now()
        - make_interval(
            days =>
              profile_record.duplicate_window_days
          )
  loop
    candidate_payload :=
      candidate_record.payload;

    candidate_phone :=
      public.normalize_lead_validation_phone(
        public.lead_validation_json_text(
          candidate_payload,
          array[
            'phone',
            'phone_number',
            'mobile',
            'mobile_number',
            'whatsapp_number',
            'contact_number'
          ]
        ),
        '+91'
      );

    candidate_email :=
      public.normalize_lead_validation_email(
        public.lead_validation_json_text(
          candidate_payload,
          array[
            'email',
            'email_address'
          ]
        )
      );

    match_type_value := null;
    match_score_value := 0;

    if profile_record.duplicate_phone_enabled
      and target_phone is not null
      and candidate_phone = target_phone then

      match_type_value := 'normalized_phone';
      match_score_value := 100;

    elsif profile_record.duplicate_email_enabled
      and target_email is not null
      and candidate_email = target_email then

      match_type_value := 'normalized_email';
      match_score_value := 85;
    end if;

    if match_type_value is not null then
      insert into public.lead_duplicate_matches (
        organization_id,
        validation_job_id,
        lead_id,
        matched_lead_id,
        match_type,
        match_score,
        confidence,
        matching_fields,
        previous_lead_created_at,
        status
      )
      values (
        target_job.organization_id,
        target_job.id,
        target_job.lead_id,
        candidate_record.id,
        match_type_value,
        match_score_value,
        match_score_value / 100,
        jsonb_build_object(
          'phone',
          case
            when candidate_phone = target_phone
              then target_phone
            else null
          end,
          'email',
          case
            when candidate_email = target_email
              then target_email
            else null
          end
        ),
        nullif(
          candidate_payload ->> 'created_at',
          ''
        )::timestamptz,
        'detected'
      )
      on conflict (
        validation_job_id,
        lead_id,
        matched_lead_id,
        match_type
      )
      do update set
        match_score = excluded.match_score,
        confidence = excluded.confidence,
        matching_fields =
          excluded.matching_fields,
        updated_at = now();

      matches :=
        matches
        || jsonb_build_array(
          jsonb_build_object(
            'matched_lead_id',
            candidate_record.id,
            'match_type',
            match_type_value,
            'match_score',
            match_score_value
          )
        );

      if match_score_value > highest_score then
        highest_score :=
          match_score_value;

        highest_match_lead_id :=
          candidate_record.id;
      end if;
    end if;
  end loop;

  update public.lead_validation_jobs
  set
    duplicate_score = highest_score,
    matched_duplicate_lead_id =
      highest_match_lead_id,
    updated_at = now()
  where id = target_job.id;

  return jsonb_build_object(
    'duplicate_detected',
    highest_score > 0,
    'highest_score',
    highest_score,
    'matched_duplicate_lead_id',
    highest_match_lead_id,
    'match_count',
    jsonb_array_length(matches),
    'matches',
    matches
  );
end;
$$;

revoke all
on function public.detect_lead_duplicates(uuid)
from public;

grant execute
on function public.detect_lead_duplicates(uuid)
to authenticated, service_role;

-- ============================================================
-- 39. DEVICE / IP BEHAVIOUR CHECK
-- ============================================================

create or replace function public.evaluate_lead_submission_behavior(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  fingerprint_record public.lead_submission_fingerprints;
  same_device_count integer := 0;
  same_ip_count integer := 0;
  rapid_count integer := 0;
  behavior_score numeric := 100;
  fraud_score_value numeric := 0;
  reasons jsonb := '[]'::jsonb;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  select *
  into fingerprint_record
  from public.lead_submission_fingerprints fingerprint
  where fingerprint.lead_id = target_job.lead_id
  order by fingerprint.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'fingerprint_available',
      false,
      'behavior_score',
      70,
      'fraud_score',
      10,
      'reasons',
      jsonb_build_array(
        'Submission fingerprint is not available'
      )
    );
  end if;

  if fingerprint_record.device_fingerprint
    is not null then

    select count(*)
    into same_device_count
    from public.lead_submission_fingerprints fingerprint
    where fingerprint.organization_id =
        target_job.organization_id
      and fingerprint.device_fingerprint =
        fingerprint_record.device_fingerprint
      and fingerprint.lead_id <>
        target_job.lead_id
      and fingerprint.created_at >=
        now() - interval '24 hours';
  end if;

  if fingerprint_record.ip_address
    is not null then

    select count(*)
    into same_ip_count
    from public.lead_submission_fingerprints fingerprint
    where fingerprint.organization_id =
        target_job.organization_id
      and fingerprint.ip_address =
        fingerprint_record.ip_address
      and fingerprint.lead_id <>
        target_job.lead_id
      and fingerprint.created_at >=
        now() - interval '24 hours';
  end if;

  select count(*)
  into rapid_count
  from public.lead_submission_fingerprints fingerprint
  where fingerprint.organization_id =
      target_job.organization_id
    and fingerprint.created_at between
      fingerprint_record.created_at
        - interval '5 minutes'
      and fingerprint_record.created_at
        + interval '5 minutes'
    and (
      (
        fingerprint_record.device_fingerprint
          is not null
        and fingerprint.device_fingerprint =
          fingerprint_record.device_fingerprint
      )
      or (
        fingerprint_record.ip_address
          is not null
        and fingerprint.ip_address =
          fingerprint_record.ip_address
      )
    );

  if same_device_count >= 3 then
    behavior_score := behavior_score - 35;
    fraud_score_value := fraud_score_value + 30;
    reasons :=
      reasons
      || jsonb_build_array(
        'Multiple leads submitted from the same device'
      );
  end if;

  if same_ip_count >= 5 then
    behavior_score := behavior_score - 30;
    fraud_score_value := fraud_score_value + 25;
    reasons :=
      reasons
      || jsonb_build_array(
        'Multiple leads submitted from the same IP address'
      );
  end if;

  if rapid_count >= 3 then
    behavior_score := behavior_score - 40;
    fraud_score_value := fraud_score_value + 40;
    reasons :=
      reasons
      || jsonb_build_array(
        'Rapid repeated submissions detected'
      );
  end if;

  if coalesce(
    fingerprint_record.form_completion_seconds,
    999
  ) < 5 then
    behavior_score := behavior_score - 30;
    fraud_score_value := fraud_score_value + 25;
    reasons :=
      reasons
      || jsonb_build_array(
        'Form was completed unrealistically fast'
      );
  end if;

  if coalesce(
    fingerprint_record.is_vpn,
    false
  )
  or coalesce(
    fingerprint_record.is_proxy,
    false
  )
  or coalesce(
    fingerprint_record.is_tor,
    false
  ) then
    behavior_score := behavior_score - 20;
    fraud_score_value := fraud_score_value + 20;
    reasons :=
      reasons
      || jsonb_build_array(
        'Anonymous or proxied network detected'
      );
  end if;

  return jsonb_build_object(
    'fingerprint_available',
    true,
    'same_device_count_24h',
    same_device_count,
    'same_ip_count_24h',
    same_ip_count,
    'rapid_submission_count',
    rapid_count,
    'form_completion_seconds',
    fingerprint_record.form_completion_seconds,
    'vpn',
    fingerprint_record.is_vpn,
    'proxy',
    fingerprint_record.is_proxy,
    'tor',
    fingerprint_record.is_tor,
    'behavior_score',
    public.clamp_lead_validation_score(
      behavior_score
    ),
    'fraud_score',
    public.clamp_lead_validation_score(
      fraud_score_value
    ),
    'reasons',
    reasons
  );
end;
$$;

revoke all
on function public.evaluate_lead_submission_behavior(uuid)
from public;

grant execute
on function public.evaluate_lead_submission_behavior(uuid)
to authenticated, service_role;

-- ============================================================
-- 40. COMPLETENESS AND INTENT SCORE
-- ============================================================

create or replace function public.evaluate_lead_quality_fields(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  phone_value text;
  email_value text;
  name_value text;
  source_value text;
  campaign_value text;
  project_value text;
  budget_value text;
  completeness_score_value numeric := 0;
  intent_score_value numeric := 0;
  present_fields integer := 0;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  phone_value :=
    target_job.normalized_input ->> 'phone';

  email_value :=
    target_job.normalized_input ->> 'email';

  name_value :=
    target_job.normalized_input ->> 'name';

  source_value :=
    target_job.normalized_input ->> 'source';

  campaign_value :=
    target_job.normalized_input ->> 'campaign';

  project_value :=
    target_job.normalized_input ->> 'project_interest';

  budget_value :=
    target_job.normalized_input ->> 'budget';

  present_fields :=
    (
      case when phone_value is not null then 1 else 0 end
      + case when email_value is not null then 1 else 0 end
      + case when name_value is not null then 1 else 0 end
      + case when source_value is not null then 1 else 0 end
      + case when campaign_value is not null then 1 else 0 end
      + case when project_value is not null then 1 else 0 end
      + case when budget_value is not null then 1 else 0 end
    );

  completeness_score_value :=
    round(
      (
        present_fields::numeric
        / 7::numeric
      ) * 100,
      2
    );

  intent_score_value :=
    (
      case when project_value is not null then 35 else 0 end
      + case when budget_value is not null then 30 else 0 end
      + case when campaign_value is not null then 15 else 0 end
      + case when phone_value is not null then 10 else 0 end
      + case when email_value is not null then 10 else 0 end
    );

  return jsonb_build_object(
    'present_field_count',
    present_fields,
    'total_field_count',
    7,
    'completeness_score',
    public.clamp_lead_validation_score(
      completeness_score_value
    ),
    'intent_score',
    public.clamp_lead_validation_score(
      intent_score_value
    ),
    'project_interest_present',
    project_value is not null,
    'budget_present',
    budget_value is not null,
    'campaign_present',
    campaign_value is not null
  );
end;
$$;

revoke all
on function public.evaluate_lead_quality_fields(uuid)
from public;

grant execute
on function public.evaluate_lead_quality_fields(uuid)
to authenticated, service_role;

-- ============================================================
-- 41. TRUST SCORE CALCULATION
-- ============================================================

create or replace function public.calculate_lead_validation_scores(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  profile_record public.lead_validation_profiles;
  phone_result jsonb;
  email_result jsonb;
  name_result jsonb;
  blacklist_result jsonb;
  consent_result jsonb;
  source_result jsonb;
  duplicate_result jsonb;
  behavior_result jsonb;
  quality_result jsonb;

  authenticity_score_value numeric;
  contactability_score_value numeric;
  completeness_score_value numeric;
  intent_score_value numeric;
  source_quality_score_value numeric;
  duplicate_score_value numeric;
  fraud_score_value numeric;
  spam_score_value numeric;
  trust_score_value numeric;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id
  for update;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  if target_job.normalized_input = '{}'::jsonb then
    target_job :=
      public.normalize_lead_validation_job_input(
        target_job.id
      );
  end if;

  select *
  into profile_record
  from public.lead_validation_profiles profile
  where profile.id = target_job.validation_profile_id;

  phone_result :=
    public.evaluate_lead_validation_phone(
      target_job.id
    );

  email_result :=
    public.evaluate_lead_validation_email(
      target_job.id
    );

  name_result :=
    public.evaluate_lead_validation_name(
      target_job.id
    );

  blacklist_result :=
    public.evaluate_lead_validation_blacklist(
      target_job.id
    );

  consent_result :=
    public.evaluate_lead_validation_consent(
      target_job.id
    );

  source_result :=
    public.evaluate_lead_validation_source(
      target_job.id
    );

  duplicate_result :=
    public.detect_lead_duplicates(
      target_job.id
    );

  behavior_result :=
    public.evaluate_lead_submission_behavior(
      target_job.id
    );

  quality_result :=
    public.evaluate_lead_quality_fields(
      target_job.id
    );

  authenticity_score_value :=
    public.clamp_lead_validation_score(
      (
        (name_result ->> 'score')::numeric
        * 0.30
      )
      + (
        (
          100
          - (behavior_result ->> 'fraud_score')::numeric
        )
        * 0.45
      )
      + (
        (
          100
          - (duplicate_result ->> 'highest_score')::numeric
        )
        * 0.25
      )
    );

  contactability_score_value :=
    public.clamp_lead_validation_score(
      (
        (phone_result ->> 'score')::numeric
        * 0.70
      )
      + (
        (email_result ->> 'score')::numeric
        * 0.30
      )
    );

  completeness_score_value :=
    public.clamp_lead_validation_score(
      (
        quality_result
        ->> 'completeness_score'
      )::numeric
    );

  intent_score_value :=
    public.clamp_lead_validation_score(
      (
        quality_result
        ->> 'intent_score'
      )::numeric
    );

  source_quality_score_value :=
    public.clamp_lead_validation_score(
      (
        source_result
        ->> 'score'
      )::numeric
    );

  duplicate_score_value :=
    public.clamp_lead_validation_score(
      (
        duplicate_result
        ->> 'highest_score'
      )::numeric
    );

  fraud_score_value :=
    public.clamp_lead_validation_score(
      (
        behavior_result
        ->> 'fraud_score'
      )::numeric
      + case
          when (
            name_result
            ->> 'suspicious'
          )::boolean
            then 30
          else 0
        end
      + case
          when (
            email_result
            ->> 'domain_blocked'
          )::boolean
            then 40
          else 0
        end
    );

  spam_score_value :=
    public.clamp_lead_validation_score(
      (
        fraud_score_value
        * 0.60
      )
      + (
        duplicate_score_value
        * 0.40
      )
    );

  trust_score_value :=
    public.clamp_lead_validation_score(
      (
        authenticity_score_value
        * (
            profile_record.authenticity_weight
            / 100
          )
      )
      + (
        contactability_score_value
        * (
            profile_record.contactability_weight
            / 100
          )
      )
      + (
        completeness_score_value
        * (
            profile_record.completeness_weight
            / 100
          )
      )
      + (
        intent_score_value
        * (
            profile_record.intent_weight
            / 100
          )
      )
      + (
        source_quality_score_value
        * (
            profile_record.source_quality_weight
            / 100
          )
      )
    );

  update public.lead_validation_jobs
  set
    authenticity_score =
      authenticity_score_value,
    contactability_score =
      contactability_score_value,
    completeness_score =
      completeness_score_value,
    intent_score =
      intent_score_value,
    source_quality_score =
      source_quality_score_value,
    duplicate_score =
      duplicate_score_value,
    fraud_score =
      fraud_score_value,
    spam_score =
      spam_score_value,
    trust_score =
      trust_score_value,
    validation_output =
      jsonb_build_object(
        'phone',
        phone_result,
        'email',
        email_result,
        'name',
        name_result,
        'blacklist',
        blacklist_result,
        'consent',
        consent_result,
        'source',
        source_result,
        'duplicates',
        duplicate_result,
        'behavior',
        behavior_result,
        'quality',
        quality_result
      ),
    updated_at = now()
  where id = target_job.id;

  return jsonb_build_object(
    'authenticity_score',
    authenticity_score_value,
    'contactability_score',
    contactability_score_value,
    'completeness_score',
    completeness_score_value,
    'intent_score',
    intent_score_value,
    'source_quality_score',
    source_quality_score_value,
    'duplicate_score',
    duplicate_score_value,
    'fraud_score',
    fraud_score_value,
    'spam_score',
    spam_score_value,
    'trust_score',
    trust_score_value,
    'phone',
    phone_result,
    'email',
    email_result,
    'name',
    name_result,
    'blacklist',
    blacklist_result,
    'consent',
    consent_result,
    'source',
    source_result,
    'duplicates',
    duplicate_result,
    'behavior',
    behavior_result,
    'quality',
    quality_result
  );
end;
$$;

revoke all
on function public.calculate_lead_validation_scores(uuid)
from public;

grant execute
on function public.calculate_lead_validation_scores(uuid)
to authenticated, service_role;

-- ============================================================
-- 42. VALIDATION DECISION
-- ============================================================

create or replace function public.determine_lead_validation_decision(
  requested_validation_job_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  profile_record public.lead_validation_profiles;
  validation_output jsonb;
  blacklist_blocking boolean;
  consent_valid boolean;
  phone_valid boolean;
  duplicate_detected boolean;
  decision_value text;
  ai_eligibility_value text;
  block_reason text;
  reasons jsonb := '[]'::jsonb;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id
  for update;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  if target_job.trust_score is null then
    perform public.calculate_lead_validation_scores(
      target_job.id
    );

    select *
    into target_job
    from public.lead_validation_jobs job
    where job.id = requested_validation_job_id;
  end if;

  select *
  into profile_record
  from public.lead_validation_profiles profile
  where profile.id = target_job.validation_profile_id;

  validation_output :=
    target_job.validation_output;

  blacklist_blocking :=
    coalesce(
      (
        validation_output
        -> 'blacklist'
        ->> 'blocking'
      )::boolean,
      false
    );

  consent_valid :=
    coalesce(
      (
        validation_output
        -> 'consent'
        ->> 'valid'
      )::boolean,
      false
    );

  phone_valid :=
    coalesce(
      (
        validation_output
        -> 'phone'
        ->> 'valid'
      )::boolean,
      false
    );

  duplicate_detected :=
    coalesce(
      (
        validation_output
        -> 'duplicates'
        ->> 'duplicate_detected'
      )::boolean,
      false
    );

  if blacklist_blocking then
    decision_value := 'suppressed';
    ai_eligibility_value := 'blocked';
    block_reason :=
      'Lead matched blacklist or suppression rule';

    reasons :=
      reasons
      || jsonb_build_array(
        block_reason
      );

  elsif not consent_valid
    and profile_record.require_consent then

    decision_value := 'rejected';
    ai_eligibility_value := 'blocked';
    block_reason :=
      'Required outbound AI call consent is not granted';

    reasons :=
      reasons
      || jsonb_build_array(
        block_reason
      );

  elsif not phone_valid
    and profile_record.require_phone then

    decision_value := 'rejected';
    ai_eligibility_value := 'blocked';
    block_reason :=
      'Required phone number is invalid';

    reasons :=
      reasons
      || jsonb_build_array(
        block_reason
      );

  elsif duplicate_detected
    and target_job.duplicate_score >= 95
    and not profile_record.allow_ai_call_when_duplicate then

    decision_value := 'duplicate';
    ai_eligibility_value := 'blocked';
    block_reason :=
      'High-confidence duplicate lead detected';

    reasons :=
      reasons
      || jsonb_build_array(
        block_reason
      );

  elsif target_job.trust_score >=
    profile_record.trust_score_threshold then

    decision_value := 'approved';
    ai_eligibility_value := 'allowed';

    reasons :=
      reasons
      || jsonb_build_array(
        'Lead trust score meets approval threshold'
      );

  elsif target_job.trust_score >=
    profile_record.manual_review_threshold
    and profile_record.manual_review_enabled then

    decision_value := 'manual_review';

    ai_eligibility_value :=
      case
        when profile_record.allow_ai_call_when_manual_review
          then 'allowed'
        else 'manual_review'
      end;

    block_reason :=
      case
        when profile_record.allow_ai_call_when_manual_review
          then null
        else 'Lead requires manual validation review'
      end;

    reasons :=
      reasons
      || jsonb_build_array(
        'Lead trust score requires manual review'
      );

  else
    decision_value := 'rejected';
    ai_eligibility_value := 'blocked';
    block_reason :=
      'Lead trust score is below validation threshold';

    reasons :=
      reasons
      || jsonb_build_array(
        block_reason
      );
  end if;

  return jsonb_build_object(
    'decision',
    decision_value,
    'ai_call_eligibility',
    ai_eligibility_value,
    'ai_call_block_reason',
    block_reason,
    'reasons',
    reasons,
    'trust_score',
    target_job.trust_score,
    'thresholds',
    jsonb_build_object(
      'approval',
      profile_record.trust_score_threshold,
      'manual_review',
      profile_record.manual_review_threshold,
      'rejection',
      profile_record.rejection_threshold
    )
  );
end;
$$;

revoke all
on function public.determine_lead_validation_decision(uuid)
from public;

grant execute
on function public.determine_lead_validation_decision(uuid)
to authenticated, service_role;

-- ============================================================
-- 43. COMPLETE VALIDATION JOB
-- ============================================================

create or replace function public.complete_lead_validation_job(
  requested_validation_job_id uuid
)
returns public.lead_validation_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  decision_data jsonb;
  decision_value text;
  ai_eligibility_value text;
  created_result public.lead_validation_results;
  review_task public.lead_validation_review_tasks;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id
  for update;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_job.organization_id,
      'lead_validation.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  perform public.calculate_lead_validation_scores(
    target_job.id
  );

  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id;

  decision_data :=
    public.determine_lead_validation_decision(
      target_job.id
    );

  decision_value :=
    decision_data ->> 'decision';

  ai_eligibility_value :=
    decision_data ->> 'ai_call_eligibility';

  insert into public.lead_validation_results (
    organization_id,
    validation_job_id,
    lead_id,
    validation_profile_id,
    result_version,
    status,
    decision,
    authenticity_score,
    contactability_score,
    completeness_score,
    intent_score,
    source_quality_score,
    trust_score,
    duplicate_score,
    fraud_score,
    spam_score,
    passed_rule_count,
    failed_rule_count,
    warning_rule_count,
    blocking_rule_count,
    decision_reasons,
    risk_factors,
    quality_factors,
    duplicate_matches,
    blacklist_matches,
    suppression_matches,
    normalized_phone,
    normalized_email,
    phone_valid,
    email_valid,
    consent_valid,
    source_valid,
    ai_call_eligibility,
    ai_call_block_reason,
    recommended_action,
    recommended_workflow_code,
    summary,
    score_breakdown,
    model_data
  )
  values (
    target_job.organization_id,
    target_job.id,
    target_job.lead_id,
    target_job.validation_profile_id,
    1,
    decision_value,
    decision_value,
    coalesce(target_job.authenticity_score, 0),
    coalesce(target_job.contactability_score, 0),
    coalesce(target_job.completeness_score, 0),
    coalesce(target_job.intent_score, 0),
    coalesce(target_job.source_quality_score, 0),
    coalesce(target_job.trust_score, 0),
    coalesce(target_job.duplicate_score, 0),
    coalesce(target_job.fraud_score, 0),
    coalesce(target_job.spam_score, 0),
    (
      select count(*)
      from public.lead_validation_rule_results rule_result
      where rule_result.validation_job_id = target_job.id
        and rule_result.status = 'passed'
    ),
    (
      select count(*)
      from public.lead_validation_rule_results rule_result
      where rule_result.validation_job_id = target_job.id
        and rule_result.status in ('failed','error')
    ),
    (
      select count(*)
      from public.lead_validation_rule_results rule_result
      where rule_result.validation_job_id = target_job.id
        and rule_result.status = 'warning'
    ),
    (
      select count(*)
      from public.lead_validation_rule_results rule_result
      where rule_result.validation_job_id = target_job.id
        and rule_result.is_blocking = true
        and rule_result.status in ('failed','error')
    ),
    decision_data -> 'reasons',
    jsonb_build_array(
      jsonb_build_object(
        'fraud_score',
        target_job.fraud_score
      ),
      jsonb_build_object(
        'spam_score',
        target_job.spam_score
      ),
      jsonb_build_object(
        'duplicate_score',
        target_job.duplicate_score
      )
    ),
    jsonb_build_array(
      jsonb_build_object(
        'authenticity_score',
        target_job.authenticity_score
      ),
      jsonb_build_object(
        'contactability_score',
        target_job.contactability_score
      ),
      jsonb_build_object(
        'completeness_score',
        target_job.completeness_score
      ),
      jsonb_build_object(
        'intent_score',
        target_job.intent_score
      )
    ),
    coalesce(
      target_job.validation_output
        -> 'duplicates'
        -> 'matches',
      '[]'::jsonb
    ),
    coalesce(
      target_job.validation_output
        -> 'blacklist'
        -> 'matches',
      '[]'::jsonb
    ),
    coalesce(
      target_job.validation_output
        -> 'blacklist'
        -> 'matches',
      '[]'::jsonb
    ),
    target_job.normalized_input ->> 'phone',
    target_job.normalized_input ->> 'email',
    coalesce(
      (
        target_job.validation_output
          -> 'phone'
          ->> 'valid'
      )::boolean,
      false
    ),
    coalesce(
      (
        target_job.validation_output
          -> 'email'
          ->> 'valid'
      )::boolean,
      false
    ),
    coalesce(
      (
        target_job.validation_output
          -> 'consent'
          ->> 'valid'
      )::boolean,
      false
    ),
    true,
    ai_eligibility_value,
    decision_data ->> 'ai_call_block_reason',
    case decision_value
      when 'approved' then 'start_ai_call'
      when 'manual_review' then 'manual_validation_review'
      when 'duplicate' then 'merge_or_close_duplicate'
      when 'suppressed' then 'stop_all_outreach'
      else 'reject_or_request_new_contact'
    end,
    case decision_value
      when 'approved' then 'lead_validated'
      when 'manual_review' then 'lead_manual_review'
      when 'duplicate' then 'lead_duplicate'
      when 'suppressed' then 'lead_suppressed'
      else 'lead_rejected'
    end,
    'Lead validation completed with trust score '
      || coalesce(
          target_job.trust_score,
          0
        )::text,
    jsonb_build_object(
      'authenticity',
      target_job.authenticity_score,
      'contactability',
      target_job.contactability_score,
      'completeness',
      target_job.completeness_score,
      'intent',
      target_job.intent_score,
      'source_quality',
      target_job.source_quality_score,
      'trust',
      target_job.trust_score,
      'duplicate',
      target_job.duplicate_score,
      'fraud',
      target_job.fraud_score,
      'spam',
      target_job.spam_score
    ),
    target_job.validation_output
  )
  on conflict (
    validation_job_id,
    result_version
  )
  do update set
    status = excluded.status,
    decision = excluded.decision,
    authenticity_score =
      excluded.authenticity_score,
    contactability_score =
      excluded.contactability_score,
    completeness_score =
      excluded.completeness_score,
    intent_score =
      excluded.intent_score,
    source_quality_score =
      excluded.source_quality_score,
    trust_score =
      excluded.trust_score,
    duplicate_score =
      excluded.duplicate_score,
    fraud_score =
      excluded.fraud_score,
    spam_score =
      excluded.spam_score,
    decision_reasons =
      excluded.decision_reasons,
    risk_factors =
      excluded.risk_factors,
    quality_factors =
      excluded.quality_factors,
    duplicate_matches =
      excluded.duplicate_matches,
    blacklist_matches =
      excluded.blacklist_matches,
    suppression_matches =
      excluded.suppression_matches,
    normalized_phone =
      excluded.normalized_phone,
    normalized_email =
      excluded.normalized_email,
    phone_valid =
      excluded.phone_valid,
    email_valid =
      excluded.email_valid,
    consent_valid =
      excluded.consent_valid,
    ai_call_eligibility =
      excluded.ai_call_eligibility,
    ai_call_block_reason =
      excluded.ai_call_block_reason,
    recommended_action =
      excluded.recommended_action,
    recommended_workflow_code =
      excluded.recommended_workflow_code,
    summary =
      excluded.summary,
    score_breakdown =
      excluded.score_breakdown,
    model_data =
      excluded.model_data,
    updated_at = now()
  returning *
  into created_result;

  update public.lead_validation_rule_results
  set
    validation_result_id =
      created_result.id,
    updated_at = now()
  where validation_job_id =
    target_job.id;

  update public.lead_validation_evidence
  set
    validation_result_id =
      created_result.id
  where validation_job_id =
    target_job.id
    and validation_result_id is null;

  update public.lead_validation_jobs
  set
    status = decision_value,
    decision = decision_value,
    ai_call_eligibility =
      ai_eligibility_value,
    ai_call_block_reason =
      decision_data
      ->> 'ai_call_block_reason',
    completed_at = now(),
    updated_at = now()
  where id = target_job.id;

  if decision_value = 'manual_review' then
    insert into public.lead_validation_review_tasks (
      organization_id,
      validation_job_id,
      validation_result_id,
      lead_id,
      status,
      priority,
      review_reason,
      review_context,
      due_at
    )
    values (
      target_job.organization_id,
      target_job.id,
      created_result.id,
      target_job.lead_id,
      'pending',
      target_job.priority,
      'Lead validation requires manual review',
      jsonb_build_object(
        'trust_score',
        target_job.trust_score,
        'decision_reasons',
        decision_data -> 'reasons'
      ),
      now() + interval '4 hours'
    )
    on conflict (validation_job_id)
    do update set
      validation_result_id =
        excluded.validation_result_id,
      status = 'pending',
      priority = excluded.priority,
      review_reason =
        excluded.review_reason,
      review_context =
        excluded.review_context,
      due_at = excluded.due_at,
      updated_at = now()
    returning *
    into review_task;
  end if;

  insert into public.lead_validation_logs (
    organization_id,
    validation_job_id,
    validation_result_id,
    lead_id,
    log_level,
    log_type,
    event_name,
    message,
    log_data
  )
  values (
    target_job.organization_id,
    target_job.id,
    created_result.id,
    target_job.lead_id,
    case
      when decision_value = 'approved'
        then 'info'
      when decision_value =
        'manual_review'
        then 'warning'
      else 'error'
    end,
    'result',
    'lead_validation.completed',
    'Lead validation completed',
    jsonb_build_object(
      'decision',
      decision_value,
      'trust_score',
      target_job.trust_score,
      'ai_call_eligibility',
      ai_eligibility_value,
      'review_task_id',
      review_task.id
    )
  );

  return created_result;
end;
$$;

revoke all
on function public.complete_lead_validation_job(uuid)
from public;

grant execute
on function public.complete_lead_validation_job(uuid)
to authenticated, service_role;

-- ============================================================
-- 44. RUN VALIDATION END-TO-END
-- ============================================================

create or replace function public.run_lead_validation(
  requested_validation_job_id uuid
)
returns public.lead_validation_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id
  for update;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_job.organization_id,
      'lead_validation.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.lead_validation_jobs
  set
    status = 'running',
    started_at = coalesce(
      started_at,
      now()
    ),
    validation_attempt =
      greatest(
        validation_attempt,
        1
      ),
    updated_at = now()
  where id = target_job.id;

  perform public.normalize_lead_validation_job_input(
    target_job.id
  );

  return public.complete_lead_validation_job(
    target_job.id
  );

exception
  when others then
    update public.lead_validation_jobs
    set
      status = 'failed',
      decision = 'failed',
      failed_at = now(),
      error_data =
        jsonb_build_object(
          'sqlstate',
          sqlstate,
          'message',
          sqlerrm
        ),
      updated_at = now()
    where id = requested_validation_job_id;

    insert into public.lead_validation_logs (
      organization_id,
      validation_job_id,
      lead_id,
      log_level,
      log_type,
      event_name,
      message,
      error_code,
      error_message,
      log_data
    )
    select
      job.organization_id,
      job.id,
      job.lead_id,
      'error',
      'execution',
      'lead_validation.failed',
      'Lead validation execution failed',
      sqlstate,
      sqlerrm,
      jsonb_build_object(
        'validation_job_id',
        requested_validation_job_id
      )
    from public.lead_validation_jobs job
    where job.id =
      requested_validation_job_id;

    raise;
end;
$$;

revoke all
on function public.run_lead_validation(uuid)
from public;

grant execute
on function public.run_lead_validation(uuid)
to authenticated, service_role;

-- ============================================================
-- 45. AI CALL ELIGIBILITY GATE
-- ============================================================

create or replace function public.check_lead_ai_call_eligibility(
  requested_lead_id uuid,
  requested_campaign_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  organization_value uuid;
  latest_result public.lead_validation_results;
  ai_call_check jsonb;
begin
  organization_value :=
    public.get_lead_validation_organization_id(
      requested_lead_id
    );

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      organization_value,
      'lead_validation.view'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into latest_result
  from public.lead_validation_results result_record
  where result_record.organization_id =
      organization_value
    and result_record.lead_id =
      requested_lead_id
  order by result_record.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object(
      'eligible',
      false,
      'eligibility',
      'blocked',
      'reason_code',
      'VALIDATION_NOT_COMPLETED',
      'reason',
      'Lead validation has not been completed'
    );
  end if;

  if latest_result.ai_call_eligibility <>
    'allowed' then

    return jsonb_build_object(
      'eligible',
      false,
      'eligibility',
      latest_result.ai_call_eligibility,
      'reason_code',
      'VALIDATION_BLOCKED',
      'reason',
      coalesce(
        latest_result.ai_call_block_reason,
        'Lead validation does not allow AI calling'
      ),
      'validation_result_id',
      latest_result.id,
      'decision',
      latest_result.decision,
      'trust_score',
      latest_result.trust_score
    );
  end if;

  ai_call_check :=
    public.check_ai_call_eligibility(
      organization_value,
      latest_result.normalized_phone,
      requested_lead_id,
      requested_campaign_id,
      now()
    );

  return
    ai_call_check
    || jsonb_build_object(
      'validation_result_id',
      latest_result.id,
      'validation_decision',
      latest_result.decision,
      'trust_score',
      latest_result.trust_score
    );
end;
$$;

revoke all
on function public.check_lead_ai_call_eligibility(uuid,uuid)
from public;

grant execute
on function public.check_lead_ai_call_eligibility(uuid,uuid)
to authenticated, service_role;

-- ============================================================
-- 46. MANUAL REVIEW DECISION
-- ============================================================

create or replace function public.decide_lead_validation_review(
  requested_review_task_id uuid,
  requested_decision text,
  requested_notes text default null,
  requested_decision_data jsonb default '{}'::jsonb
)
returns public.lead_validation_review_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  review_task public.lead_validation_review_tasks;
  final_ai_eligibility text;
begin
  if requested_decision not in (
    'approved',
    'rejected',
    'suppressed',
    'duplicate',
    'needs_more_information'
  ) then
    raise exception
      'Invalid lead validation review decision';
  end if;

  select *
  into review_task
  from public.lead_validation_review_tasks task
  where task.id = requested_review_task_id
  for update;

  if not found then
    raise exception
      'Lead validation review task not found';
  end if;

  if not public.has_organization_permission(
    review_task.organization_id,
    'lead_validation.review'
  ) then
    raise exception 'Permission denied';
  end if;

  if review_task.status in (
    'approved',
    'rejected',
    'suppressed',
    'duplicate',
    'cancelled',
    'expired'
  ) then
    return review_task;
  end if;

  final_ai_eligibility :=
    case requested_decision
      when 'approved' then 'allowed'
      when 'needs_more_information'
        then 'manual_review'
      else 'blocked'
    end;

  update public.lead_validation_review_tasks
  set
    status =
      case requested_decision
        when 'needs_more_information'
          then 'in_review'
        else requested_decision
      end,
    decision =
      requested_decision,
    decision_notes =
      requested_notes,
    decision_data =
      coalesce(
        requested_decision_data,
        '{}'::jsonb
      ),
    decided_by =
      auth.uid(),
    decided_at =
      case
        when requested_decision =
          'needs_more_information'
          then null
        else now()
      end,
    updated_at = now()
  where id = review_task.id
  returning *
  into review_task;

  update public.lead_validation_results
  set
    status =
      case requested_decision
        when 'needs_more_information'
          then 'manual_review'
        else requested_decision
      end,
    decision =
      case requested_decision
        when 'needs_more_information'
          then 'manual_review'
        else requested_decision
      end,
    manually_reviewed = true,
    reviewed_by = auth.uid(),
    reviewed_at = now(),
    review_decision =
      requested_decision,
    review_notes =
      requested_notes,
    ai_call_eligibility =
      final_ai_eligibility,
    ai_call_block_reason =
      case
        when final_ai_eligibility = 'allowed'
          then null
        else coalesce(
          requested_notes,
          'Manual review did not approve AI calling'
        )
      end,
    updated_at = now()
  where id =
    review_task.validation_result_id;

  update public.lead_validation_jobs
  set
    status =
      case requested_decision
        when 'needs_more_information'
          then 'manual_review'
        else requested_decision
      end,
    decision =
      case requested_decision
        when 'needs_more_information'
          then 'manual_review'
        else requested_decision
      end,
    ai_call_eligibility =
      final_ai_eligibility,
    ai_call_block_reason =
      case
        when final_ai_eligibility = 'allowed'
          then null
        else coalesce(
          requested_notes,
          'Manual review did not approve AI calling'
        )
      end,
    completed_at =
      case
        when requested_decision =
          'needs_more_information'
          then completed_at
        else now()
      end,
    updated_at = now()
  where id =
    review_task.validation_job_id;

  return review_task;
end;
$$;

revoke all
on function public.decide_lead_validation_review(
  uuid,text,text,jsonb
)
from public;

grant execute
on function public.decide_lead_validation_review(
  uuid,text,text,jsonb
)
to authenticated, service_role;

-- ============================================================
-- 47. CANCEL VALIDATION JOB
-- ============================================================

create or replace function public.cancel_lead_validation_job(
  requested_validation_job_id uuid,
  requested_reason text default 'Cancelled manually'
)
returns public.lead_validation_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id
  for update;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_job.organization_id,
      'lead_validation.cancel'
    ) then
    raise exception 'Permission denied';
  end if;

  if target_job.status in (
    'approved',
    'rejected',
    'suppressed',
    'duplicate',
    'failed',
    'cancelled',
    'expired'
  ) then
    return target_job;
  end if;

  update public.lead_validation_retry_queue
  set
    queue_status = 'cancelled',
    completed_at = now(),
    failure_code =
      'VALIDATION_CANCELLED',
    failure_message =
      requested_reason,
    lock_token = null,
    lock_expires_at = null,
    updated_at = now()
  where validation_job_id =
    target_job.id
    and queue_status in (
      'pending',
      'claimed',
      'processing'
    );

  update public.lead_validation_review_tasks
  set
    status = 'cancelled',
    decision_notes =
      requested_reason,
    decided_at = now(),
    updated_at = now()
  where validation_job_id =
    target_job.id
    and status in (
      'pending',
      'assigned',
      'in_review'
    );

  update public.lead_validation_jobs
  set
    status = 'cancelled',
    cancelled_at = now(),
    ai_call_eligibility = 'blocked',
    ai_call_block_reason =
      requested_reason,
    error_data =
      error_data
      || jsonb_build_object(
        'cancelled',
        true,
        'reason',
        requested_reason
      ),
    updated_at = now()
  where id = target_job.id
  returning *
  into target_job;

  return target_job;
end;
$$;

revoke all
on function public.cancel_lead_validation_job(uuid,text)
from public;

grant execute
on function public.cancel_lead_validation_job(uuid,text)
to authenticated, service_role;

-- ============================================================
-- 48. RETRY ENQUEUE
-- ============================================================

create or replace function public.enqueue_lead_validation_retry(
  requested_validation_job_id uuid,
  requested_failure_code text default null,
  requested_failure_message text default null,
  requested_failure_data jsonb default '{}'::jsonb,
  requested_retry_payload jsonb default '{}'::jsonb,
  requested_priority integer default 100
)
returns public.lead_validation_retry_queue
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.lead_validation_jobs;
  attempt_value integer;
  delay_seconds integer;
  scheduled_time timestamptz;
  existing_retry public.lead_validation_retry_queue;
  created_retry public.lead_validation_retry_queue;
begin
  select *
  into target_job
  from public.lead_validation_jobs job
  where job.id = requested_validation_job_id
  for update;

  if not found then
    raise exception 'Lead validation job not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_job.organization_id,
      'lead_validation.retry'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into existing_retry
  from public.lead_validation_retry_queue retry
  where retry.validation_job_id =
      target_job.id
    and retry.queue_status in (
      'pending',
      'claimed',
      'processing'
    )
  limit 1;

  if found then
    return existing_retry;
  end if;

  attempt_value :=
    target_job.validation_attempt + 1;

  if attempt_value >
    target_job.maximum_attempts then
    raise exception
      'Maximum lead validation attempts exhausted';
  end if;

  delay_seconds :=
    public.calculate_workflow_retry_delay(
      'exponential',
      60,
      attempt_value
    );

  scheduled_time :=
    now()
    + make_interval(
        secs => delay_seconds
      );

  insert into public.lead_validation_retry_queue (
    organization_id,
    validation_job_id,
    queue_status,
    retry_attempt,
    maximum_attempts,
    retry_strategy,
    retry_delay_seconds,
    scheduled_at,
    failure_code,
    failure_message,
    failure_data,
    retry_payload,
    priority
  )
  values (
    target_job.organization_id,
    target_job.id,
    'pending',
    attempt_value,
    target_job.maximum_attempts,
    'exponential',
    delay_seconds,
    scheduled_time,
    requested_failure_code,
    requested_failure_message,
    coalesce(
      requested_failure_data,
      '{}'::jsonb
    ),
    coalesce(
      requested_retry_payload,
      '{}'::jsonb
    ),
    requested_priority
  )
  returning *
  into created_retry;

  update public.lead_validation_jobs
  set
    status = 'waiting',
    next_retry_at =
      scheduled_time,
    error_data =
      coalesce(
        requested_failure_data,
        '{}'::jsonb
      )
      || jsonb_build_object(
        'code',
        requested_failure_code,
        'message',
        requested_failure_message
      ),
    updated_at = now()
  where id = target_job.id;

  return created_retry;
end;
$$;

revoke all
on function public.enqueue_lead_validation_retry(
  uuid,text,text,jsonb,jsonb,integer
)
from public;

grant execute
on function public.enqueue_lead_validation_retry(
  uuid,text,text,jsonb,jsonb,integer
)
to authenticated, service_role;

-- ============================================================
-- 49. PART 2 VALIDATION
-- ============================================================

do $$
begin
  if not exists (
    select 1
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name =
        'create_lead_validation_job'
  ) then
    raise exception
      '011 Part 2 validation failed: create_lead_validation_job missing';
  end if;

  if not exists (
    select 1
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name =
        'run_lead_validation'
  ) then
    raise exception
      '011 Part 2 validation failed: run_lead_validation missing';
  end if;

  if not exists (
    select 1
    from information_schema.routines
    where routine_schema = 'public'
      and routine_name =
        'check_lead_ai_call_eligibility'
  ) then
    raise exception
      '011 Part 2 validation failed: AI call eligibility function missing';
  end if;
end;
$$;

-- ============================================================
-- SalesSetu Enterprise
-- Migration 011: Lead Validation Engine
-- Part 3: Orchestration, Outbox, Analytics, Maintenance & COMMIT
-- Append after Part 1 and Part 2.
-- ============================================================

-- 50. Reliable event outbox
create table if not exists public.lead_validation_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  validation_job_id uuid references public.lead_validation_jobs(id) on delete set null,
  validation_result_id uuid references public.lead_validation_results(id) on delete set null,
  lead_id uuid references public.leads(id) on delete set null,
  event_name text not null,
  event_version integer not null default 1 check (event_version > 0),
  destination text not null default 'internal'
    check (destination in ('internal','workflow_engine','ai_calling','n8n','webhook','analytics','manual_review','audit')),
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
  maximum_attempts integer not null default 10 check (maximum_attempts between 1 and 100),
  delivered_at timestamptz,
  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',
  response_status integer,
  response_payload jsonb not null default '{}',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.lead_validation_event_outbox
  add column if not exists lead_id uuid;


create unique index if not exists lead_validation_event_outbox_idempotency_idx
  on public.lead_validation_event_outbox (organization_id,idempotency_key)
  where idempotency_key is not null;

create index if not exists lead_validation_event_outbox_queue_idx
  on public.lead_validation_event_outbox (status,available_at,priority,created_at)
  where status in ('pending','failed');

drop trigger if exists lead_validation_event_outbox_set_updated_at
on public.lead_validation_event_outbox;

create trigger lead_validation_event_outbox_set_updated_at
before update on public.lead_validation_event_outbox
for each row execute function public.set_updated_at();

alter table public.lead_validation_event_outbox enable row level security;

drop policy if exists lead_validation_event_outbox_select_policy
on public.lead_validation_event_outbox;

create policy lead_validation_event_outbox_select_policy
on public.lead_validation_event_outbox
for select to authenticated
using (
  public.has_organization_permission(organization_id,'lead_validation.view_logs')
  or public.has_organization_permission(organization_id,'lead_validation.view_all')
);

drop policy if exists lead_validation_event_outbox_service_policy
on public.lead_validation_event_outbox;

create policy lead_validation_event_outbox_service_policy
on public.lead_validation_event_outbox
for all to service_role
using (true) with check (true);

grant select on public.lead_validation_event_outbox to authenticated;
grant all on public.lead_validation_event_outbox to service_role;

-- 51. Publish event
create or replace function public.publish_lead_validation_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_validation_job_id uuid default null,
  requested_validation_result_id uuid default null,
  requested_lead_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.lead_validation_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.lead_validation_event_outbox;
  created_event public.lead_validation_event_outbox;
begin
  if requested_event_name is null or btrim(requested_event_name) = '' then
    raise exception 'Event name is required';
  end if;

  if requested_destination not in (
    'internal','workflow_engine','ai_calling','n8n','webhook','analytics','manual_review','audit'
  ) then
    raise exception 'Invalid event destination';
  end if;

  if auth.role() <> 'service_role'
     and not public.has_organization_permission(requested_organization_id,'lead_validation.execute') then
    raise exception 'Permission denied';
  end if;

  if requested_idempotency_key is not null then
    select * into existing_event
    from public.lead_validation_event_outbox e
    where e.organization_id = requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then return existing_event; end if;
  end if;

  insert into public.lead_validation_event_outbox (
    organization_id,validation_job_id,validation_result_id,lead_id,
    event_name,destination,status,priority,idempotency_key,
    correlation_id,trace_id,payload,available_at
  )
  values (
    requested_organization_id,requested_validation_job_id,
    requested_validation_result_id,requested_lead_id,
    requested_event_name,requested_destination,'pending',
    requested_priority,requested_idempotency_key,
    requested_correlation_id,requested_trace_id,
    coalesce(requested_payload,'{}'::jsonb),
    coalesce(requested_available_at,now())
  )
  returning * into created_event;

  return created_event;
end;
$$;

revoke all on function public.publish_lead_validation_event(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text,text,text,timestamptz
) from public;

grant execute on function public.publish_lead_validation_event(
  uuid,text,jsonb,text,uuid,uuid,uuid,integer,text,text,text,timestamptz
) to authenticated,service_role;

-- 52. Claim/complete/fail outbox events
create or replace function public.claim_lead_validation_event(
  requested_worker_id text,
  requested_destination text default null,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.lead_validation_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare target_event public.lead_validation_event_outbox;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim outbox events';
  end if;
  if requested_worker_id is null or btrim(requested_worker_id) = '' then
    raise exception 'Worker ID is required';
  end if;

  select * into target_event
  from public.lead_validation_event_outbox e
  where e.status in ('pending','failed')
    and e.available_at <= now()
    and e.delivery_attempts < e.maximum_attempts
    and (requested_destination is null or e.destination = requested_destination)
    and (requested_organization_id is null or e.organization_id = requested_organization_id)
  order by e.priority,e.available_at,e.created_at
  for update skip locked
  limit 1;

  if not found then return null; end if;

  update public.lead_validation_event_outbox
  set status='claimed',
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

create or replace function public.complete_lead_validation_event(
  requested_event_id uuid,
  requested_lock_token text,
  requested_response_status integer default 200,
  requested_response_payload jsonb default '{}'::jsonb
)
returns public.lead_validation_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare target_event public.lead_validation_event_outbox;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may complete outbox events';
  end if;

  select * into target_event
  from public.lead_validation_event_outbox
  where id=requested_event_id
  for update;

  if not found then raise exception 'Outbox event not found'; end if;
  if target_event.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid lock token';
  end if;

  update public.lead_validation_event_outbox
  set status='delivered',
      delivered_at=now(),
      response_status=requested_response_status,
      response_payload=coalesce(requested_response_payload,'{}'::jsonb),
      claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
      last_error_code=null,last_error_message=null,last_error_data='{}'::jsonb,
      updated_at=now()
  where id=requested_event_id
  returning * into target_event;

  return target_event;
end;
$$;

create or replace function public.fail_lead_validation_event(
  requested_event_id uuid,
  requested_lock_token text,
  requested_error_code text default null,
  requested_error_message text default null,
  requested_error_data jsonb default '{}'::jsonb,
  requested_retry_delay_seconds integer default 60
)
returns public.lead_validation_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_event public.lead_validation_event_outbox;
  next_status text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may fail outbox events';
  end if;

  select * into target_event
  from public.lead_validation_event_outbox
  where id=requested_event_id
  for update;

  if not found then raise exception 'Outbox event not found'; end if;
  if target_event.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid lock token';
  end if;

  next_status := case
    when target_event.delivery_attempts >= target_event.maximum_attempts
      then 'dead_lettered'
    else 'failed'
  end;

  update public.lead_validation_event_outbox
  set status=next_status,
      available_at=case when next_status='failed'
        then now()+make_interval(secs=>greatest(requested_retry_delay_seconds,1))
        else available_at end,
      last_error_code=requested_error_code,
      last_error_message=requested_error_message,
      last_error_data=coalesce(requested_error_data,'{}'::jsonb),
      claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
      updated_at=now()
  where id=requested_event_id
  returning * into target_event;

  return target_event;
end;
$$;

revoke all on function public.claim_lead_validation_event(text,text,uuid,integer) from public;
revoke all on function public.complete_lead_validation_event(uuid,text,integer,jsonb) from public;
revoke all on function public.fail_lead_validation_event(uuid,text,text,text,jsonb,integer) from public;

grant execute on function public.claim_lead_validation_event(text,text,uuid,integer) to service_role;
grant execute on function public.complete_lead_validation_event(uuid,text,integer,jsonb) to service_role;
grant execute on function public.fail_lead_validation_event(uuid,text,text,text,jsonb,integer) to service_role;

-- 53. Retry queue processor
create or replace function public.claim_lead_validation_retry(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_seconds integer default 300
)
returns public.lead_validation_retry_queue
language plpgsql
security definer
set search_path = ''
as $$
declare retry_record public.lead_validation_retry_queue;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may claim retries';
  end if;

  select * into retry_record
  from public.lead_validation_retry_queue r
  where r.queue_status='pending'
    and r.scheduled_at<=now()
    and (requested_organization_id is null or r.organization_id=requested_organization_id)
  order by r.priority,r.scheduled_at,r.created_at
  for update skip locked
  limit 1;

  if not found then return null; end if;

  update public.lead_validation_retry_queue
  set queue_status='claimed',
      claimed_at=now(),
      claimed_by=requested_worker_id,
      lock_token=gen_random_uuid()::text,
      lock_expires_at=now()+make_interval(secs=>greatest(requested_lock_seconds,1)),
      updated_at=now()
  where id=retry_record.id
  returning * into retry_record;

  return retry_record;
end;
$$;

create or replace function public.process_claimed_lead_validation_retry(
  requested_retry_id uuid,
  requested_lock_token text
)
returns public.lead_validation_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  retry_record public.lead_validation_retry_queue;
  result_record public.lead_validation_results;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may process retries';
  end if;

  select * into retry_record
  from public.lead_validation_retry_queue
  where id=requested_retry_id
  for update;

  if not found then raise exception 'Validation retry not found'; end if;
  if retry_record.lock_token is distinct from requested_lock_token then
    raise exception 'Invalid retry lock token';
  end if;

  update public.lead_validation_retry_queue
  set queue_status='processing',processing_started_at=now(),updated_at=now()
  where id=requested_retry_id;

  result_record := public.run_lead_validation(retry_record.validation_job_id);

  update public.lead_validation_retry_queue
  set queue_status='completed',completed_at=now(),
      lock_token=null,lock_expires_at=null,updated_at=now()
  where id=requested_retry_id;

  return result_record;
exception when others then
  update public.lead_validation_retry_queue
  set queue_status=case when retry_attempt>=maximum_attempts then 'dead_lettered' else 'failed' end,
      failure_code=sqlstate,failure_message=sqlerrm,
      lock_token=null,lock_expires_at=null,updated_at=now()
  where id=requested_retry_id;
  raise;
end;
$$;

revoke all on function public.claim_lead_validation_retry(text,uuid,integer) from public;
revoke all on function public.process_claimed_lead_validation_retry(uuid,text) from public;
grant execute on function public.claim_lead_validation_retry(text,uuid,integer) to service_role;
grant execute on function public.process_claimed_lead_validation_retry(uuid,text) to service_role;

-- 54. Manual review assignment and escalation
create or replace function public.assign_lead_validation_review(
  requested_review_task_id uuid,
  requested_assignee_id uuid,
  requested_due_at timestamptz default null
)
returns public.lead_validation_review_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare task_record public.lead_validation_review_tasks;
begin
  select * into task_record
  from public.lead_validation_review_tasks
  where id=requested_review_task_id
  for update;

  if not found then raise exception 'Review task not found'; end if;

  if auth.role()<>'service_role'
    and not public.has_organization_permission(task_record.organization_id,'lead_validation.review') then
    raise exception 'Permission denied';
  end if;

  update public.lead_validation_review_tasks
  set status='assigned',
      assigned_to=requested_assignee_id,
      assigned_at=now(),
      due_at=coalesce(requested_due_at,due_at,now()+interval '4 hours'),
      updated_at=now()
  where id=requested_review_task_id
  returning * into task_record;

  perform public.publish_lead_validation_event(
    task_record.organization_id,
    'lead_validation.review.assigned',
    jsonb_build_object(
      'review_task_id',task_record.id,
      'validation_job_id',task_record.validation_job_id,
      'lead_id',task_record.lead_id,
      'assigned_to',task_record.assigned_to,
      'due_at',task_record.due_at
    ),
    'manual_review',
    task_record.validation_job_id,
    task_record.validation_result_id,
    task_record.lead_id,
    task_record.priority,
    'review-assigned:'||task_record.id::text||':'||coalesce(task_record.assigned_to::text,'none'),
    task_record.validation_job_id::text,
    null,
    now()
  );

  return task_record;
end;
$$;

create or replace function public.escalate_overdue_lead_validation_reviews(
  requested_organization_id uuid default null,
  requested_limit integer default 100
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  task_record record;
  processed integer:=0;
begin
  if auth.role()<>'service_role' then
    raise exception 'Only service_role may escalate reviews';
  end if;

  for task_record in
    select *
    from public.lead_validation_review_tasks t
    where t.status in ('pending','assigned','in_review')
      and t.due_at is not null and t.due_at<=now()
      and (requested_organization_id is null or t.organization_id=requested_organization_id)
    order by t.due_at
    limit greatest(requested_limit,1)
    for update skip locked
  loop
    update public.lead_validation_review_tasks
    set priority=least(priority,10),
        review_context=review_context||jsonb_build_object('sla_overdue',true,'escalated_at',now()),
        updated_at=now()
    where id=task_record.id;

    perform public.publish_lead_validation_event(
      task_record.organization_id,
      'lead_validation.review.overdue',
      jsonb_build_object('review_task_id',task_record.id,'lead_id',task_record.lead_id,'due_at',task_record.due_at),
      'manual_review',
      task_record.validation_job_id,
      task_record.validation_result_id,
      task_record.lead_id,
      10,
      'review-overdue:'||task_record.id::text||':'||extract(epoch from date_trunc('hour',now()))::bigint::text,
      task_record.validation_job_id::text,
      null,
      now()
    );
    processed:=processed+1;
  end loop;
  return processed;
end;
$$;

revoke all on function public.assign_lead_validation_review(uuid,uuid,timestamptz) from public;
revoke all on function public.escalate_overdue_lead_validation_reviews(uuid,integer) from public;
grant execute on function public.assign_lead_validation_review(uuid,uuid,timestamptz) to authenticated,service_role;
grant execute on function public.escalate_overdue_lead_validation_reviews(uuid,integer) to service_role;

-- 55. Emit downstream events
create or replace function public.emit_lead_validation_result_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare payload_data jsonb;
begin
  if tg_op='UPDATE'
    and new.decision is not distinct from old.decision
    and new.ai_call_eligibility is not distinct from old.ai_call_eligibility
    and new.trust_score is not distinct from old.trust_score
    and new.review_decision is not distinct from old.review_decision then
    return new;
  end if;

  payload_data:=jsonb_build_object(
    'organization_id',new.organization_id,
    'validation_job_id',new.validation_job_id,
    'validation_result_id',new.id,
    'lead_id',new.lead_id,
    'decision',new.decision,
    'trust_score',new.trust_score,
    'fraud_score',new.fraud_score,
    'duplicate_score',new.duplicate_score,
    'spam_score',new.spam_score,
    'ai_call_eligibility',new.ai_call_eligibility,
    'recommended_action',new.recommended_action,
    'recommended_workflow_code',new.recommended_workflow_code
  );

  perform public.publish_lead_validation_event(
    new.organization_id,'lead_validation.completed',payload_data,'n8n',
    new.validation_job_id,new.id,new.lead_id,50,
    'validation-completed:'||new.id::text||':'||coalesce(new.decision,'unknown'),
    new.validation_job_id::text,null,now()
  );

  perform public.publish_lead_validation_event(
    new.organization_id,'lead_validation.'||coalesce(new.decision,'unknown'),payload_data,'workflow_engine',
    new.validation_job_id,new.id,new.lead_id,40,
    'validation-workflow:'||new.id::text||':'||coalesce(new.decision,'unknown'),
    new.validation_job_id::text,null,now()
  );

  if new.decision='approved' and new.ai_call_eligibility='allowed' then
    perform public.publish_lead_validation_event(
      new.organization_id,'lead_validation.ai_call.allowed',payload_data,'ai_calling',
      new.validation_job_id,new.id,new.lead_id,20,
      'validation-ai-call:'||new.id::text,
      new.validation_job_id::text,null,now()
    );
  end if;

  if new.decision='manual_review' then
    perform public.publish_lead_validation_event(
      new.organization_id,'lead_validation.manual_review.required',payload_data,'manual_review',
      new.validation_job_id,new.id,new.lead_id,15,
      'validation-review:'||new.id::text,
      new.validation_job_id::text,null,now()
    );
  end if;

  if new.decision='duplicate' then
    perform public.publish_lead_validation_event(
      new.organization_id,'lead_validation.duplicate.detected',payload_data,'n8n',
      new.validation_job_id,new.id,new.lead_id,10,
      'validation-duplicate:'||new.id::text,
      new.validation_job_id::text,null,now()
    );
  end if;

  if new.fraud_score>=70 or new.spam_score>=70 then
    perform public.publish_lead_validation_event(
      new.organization_id,'lead_validation.fraud.alert',payload_data,'n8n',
      new.validation_job_id,new.id,new.lead_id,5,
      'validation-fraud:'||new.id::text,
      new.validation_job_id::text,null,now()
    );
  end if;

  return new;
end;
$$;

drop trigger if exists lead_validation_results_emit_events
on public.lead_validation_results;

create trigger lead_validation_results_emit_events
after insert or update on public.lead_validation_results
for each row execute function public.emit_lead_validation_result_events();

-- 56. Workflow and AI handoff
create or replace function public.get_lead_validation_workflow_handoff(
  requested_validation_result_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare r public.lead_validation_results;
begin
  select * into r from public.lead_validation_results where id=requested_validation_result_id;
  if not found then raise exception 'Validation result not found'; end if;

  if auth.role()<>'service_role'
    and not public.has_organization_permission(r.organization_id,'lead_validation.view') then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'event_name','lead_validation.workflow_handoff',
    'workflow_code',coalesce(r.recommended_workflow_code,
      case r.decision
        when 'approved' then 'lead_validated'
        when 'manual_review' then 'lead_manual_review'
        when 'duplicate' then 'lead_duplicate'
        when 'suppressed' then 'lead_suppressed'
        when 'rejected' then 'lead_rejected'
        else 'lead_validation_failed'
      end),
    'organization_id',r.organization_id,
    'lead_id',r.lead_id,
    'validation_job_id',r.validation_job_id,
    'validation_result_id',r.id,
    'decision',r.decision,
    'trust_score',r.trust_score,
    'ai_call_eligibility',r.ai_call_eligibility,
    'recommended_action',r.recommended_action,
    'score_breakdown',r.score_breakdown,
    'decision_reasons',r.decision_reasons
  );
end;
$$;

create or replace function public.prepare_lead_validation_ai_call_handoff(
  requested_validation_result_id uuid,
  requested_campaign_id uuid default null,
  requested_priority integer default 100
)
returns public.lead_validation_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  r public.lead_validation_results;
  eligibility jsonb;
begin
  select * into r from public.lead_validation_results where id=requested_validation_result_id;
  if not found then raise exception 'Validation result not found'; end if;

  eligibility:=public.check_lead_ai_call_eligibility(r.lead_id,requested_campaign_id);

  if coalesce((eligibility->>'eligible')::boolean,false)=false then
    raise exception 'Lead is not eligible for AI calling: %',coalesce(eligibility->>'reason','Unknown reason');
  end if;

  return public.publish_lead_validation_event(
    r.organization_id,
    'lead_validation.ai_call.handoff',
    jsonb_build_object(
      'organization_id',r.organization_id,
      'lead_id',r.lead_id,
      'validation_job_id',r.validation_job_id,
      'validation_result_id',r.id,
      'campaign_id',requested_campaign_id,
      'normalized_phone',r.normalized_phone,
      'trust_score',r.trust_score,
      'eligibility',eligibility
    ),
    'ai_calling',
    r.validation_job_id,
    r.id,
    r.lead_id,
    requested_priority,
    'ai-call-handoff:'||r.id::text||':'||coalesce(requested_campaign_id::text,'default'),
    r.validation_job_id::text,
    null,
    now()
  );
end;
$$;

revoke all on function public.get_lead_validation_workflow_handoff(uuid) from public;
revoke all on function public.prepare_lead_validation_ai_call_handoff(uuid,uuid,integer) from public;
grant execute on function public.get_lead_validation_workflow_handoff(uuid) to authenticated,service_role;
grant execute on function public.prepare_lead_validation_ai_call_handoff(uuid,uuid,integer) to authenticated,service_role;

-- 57. Analytics views
create or replace view public.lead_validation_latest_results
with (security_invoker=true) as
select distinct on (organization_id,lead_id) *
from public.lead_validation_results
order by organization_id,lead_id,created_at desc,id desc;

create or replace view public.lead_validation_dashboard
with (security_invoker=true) as
select
  organization_id,
  date_trunc('day',created_at)::date as validation_date,
  count(*) as total_validations,
  count(*) filter (where decision='approved') as approved_count,
  count(*) filter (where decision='manual_review') as manual_review_count,
  count(*) filter (where decision='rejected') as rejected_count,
  count(*) filter (where decision='duplicate') as duplicate_count,
  count(*) filter (where decision='suppressed') as suppressed_count,
  count(*) filter (where ai_call_eligibility='allowed') as ai_call_allowed_count,
  round(avg(trust_score),2) as average_trust_score,
  round(avg(fraud_score),2) as average_fraud_score,
  round(avg(duplicate_score),2) as average_duplicate_score,
  round((count(*) filter (where decision='approved')::numeric/nullif(count(*),0))*100,2) as approval_rate,
  round((count(*) filter (where decision='duplicate')::numeric/nullif(count(*),0))*100,2) as duplicate_rate
from public.lead_validation_results
group by organization_id,date_trunc('day',created_at)::date;

create or replace view public.lead_validation_trust_distribution
with (security_invoker=true) as
select
  organization_id,
  date_trunc('day',created_at)::date as validation_date,
  case
    when trust_score<20 then '00-19'
    when trust_score<40 then '20-39'
    when trust_score<60 then '40-59'
    when trust_score<80 then '60-79'
    else '80-100'
  end as trust_score_band,
  count(*) as lead_count,
  round(avg(trust_score),2) as average_trust_score
from public.lead_validation_results
group by organization_id,date_trunc('day',created_at)::date,
  case
    when trust_score<20 then '00-19'
    when trust_score<40 then '20-39'
    when trust_score<60 then '40-59'
    when trust_score<80 then '60-79'
    else '80-100'
  end;

create or replace view public.lead_validation_risk_trends
with (security_invoker=true) as
select
  organization_id,
  date_trunc('day',created_at)::date as validation_date,
  count(*) filter (where duplicate_score>=80) as high_duplicate_count,
  count(*) filter (where fraud_score>=70) as high_fraud_count,
  count(*) filter (where spam_score>=70) as high_spam_count,
  count(*) filter (where phone_valid=false) as invalid_phone_count,
  count(*) filter (where email_valid=false) as invalid_email_count,
  count(*) filter (where consent_valid=false) as invalid_consent_count,
  round(avg(duplicate_score),2) as average_duplicate_score,
  round(avg(fraud_score),2) as average_fraud_score,
  round(avg(spam_score),2) as average_spam_score
from public.lead_validation_results
group by organization_id,date_trunc('day',created_at)::date;

create or replace view public.lead_validation_review_dashboard
with (security_invoker=true) as
select
  organization_id,
  count(*) filter (where status='pending') as pending_count,
  count(*) filter (where status='assigned') as assigned_count,
  count(*) filter (where status='in_review') as in_review_count,
  count(*) filter (where status='approved') as approved_count,
  count(*) filter (where status='rejected') as rejected_count,
  count(*) filter (
    where status in ('pending','assigned','in_review')
      and due_at is not null and due_at<=now()
  ) as overdue_count
from public.lead_validation_review_tasks
group by organization_id;

create or replace view public.lead_validation_outbox_health
with (security_invoker=true) as
select
  organization_id,destination,
  count(*) filter (where status='pending') as pending_count,
  count(*) filter (where status='delivered') as delivered_count,
  count(*) filter (where status='failed') as failed_count,
  count(*) filter (where status='dead_lettered') as dead_lettered_count,
  min(available_at) filter (where status in ('pending','failed')) as oldest_pending_at,
  max(delivered_at) as latest_delivered_at
from public.lead_validation_event_outbox
group by organization_id,destination;

grant select on
  public.lead_validation_latest_results,
  public.lead_validation_dashboard,
  public.lead_validation_trust_distribution,
  public.lead_validation_risk_trends,
  public.lead_validation_review_dashboard,
  public.lead_validation_outbox_health
to authenticated,service_role;

-- 58. Reporting
create or replace function public.get_lead_validation_daily_summary(
  requested_organization_id uuid,
  requested_start_date date default current_date,
  requested_end_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result_data jsonb;
begin
  if requested_end_date<requested_start_date then
    raise exception 'End date cannot be before start date';
  end if;

  if auth.role()<>'service_role'
    and not public.has_organization_permission(requested_organization_id,'lead_validation.view') then
    raise exception 'Permission denied';
  end if;

  select jsonb_build_object(
    'organization_id',requested_organization_id,
    'start_date',requested_start_date,
    'end_date',requested_end_date,
    'total_validations',count(*),
    'approved',count(*) filter (where decision='approved'),
    'manual_review',count(*) filter (where decision='manual_review'),
    'rejected',count(*) filter (where decision='rejected'),
    'duplicates',count(*) filter (where decision='duplicate'),
    'suppressed',count(*) filter (where decision='suppressed'),
    'ai_call_allowed',count(*) filter (where ai_call_eligibility='allowed'),
    'average_trust_score',round(avg(trust_score),2),
    'average_fraud_score',round(avg(fraud_score),2),
    'approval_rate',round((count(*) filter (where decision='approved')::numeric/nullif(count(*),0))*100,2)
  )
  into result_data
  from public.lead_validation_results
  where organization_id=requested_organization_id
    and created_at>=requested_start_date::timestamptz
    and created_at<(requested_end_date+1)::timestamptz;

  return result_data;
end;
$$;

revoke all on function public.get_lead_validation_daily_summary(uuid,date,date) from public;
grant execute on function public.get_lead_validation_daily_summary(uuid,date,date) to authenticated,service_role;

-- 59. Maintenance and health
create or replace function public.release_expired_lead_validation_locks()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare retries integer:=0; events integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may release locks'; end if;

  update public.lead_validation_retry_queue
  set queue_status='pending',claimed_at=null,claimed_by=null,
      lock_token=null,lock_expires_at=null,scheduled_at=now(),updated_at=now()
  where queue_status in ('claimed','processing')
    and lock_expires_at is not null and lock_expires_at<=now();
  get diagnostics retries=row_count;

  update public.lead_validation_event_outbox
  set status=case when delivery_attempts>=maximum_attempts then 'dead_lettered' else 'failed' end,
      claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
      available_at=case when delivery_attempts>=maximum_attempts then available_at else now() end,
      last_error_code=coalesce(last_error_code,'LOCK_EXPIRED'),
      last_error_message=coalesce(last_error_message,'Worker lock expired'),
      updated_at=now()
  where status in ('claimed','processing')
    and lock_expires_at is not null and lock_expires_at<=now();
  get diagnostics events=row_count;

  return jsonb_build_object('retry_locks_released',retries,'event_locks_released',events,'released_at',now());
end;
$$;

create or replace function public.cleanup_lead_validation_history(
  requested_log_retention interval default interval '180 days',
  requested_event_retention interval default interval '90 days',
  requested_limit integer default 5000
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare logs integer:=0; events integer:=0;
begin
  if auth.role()<>'service_role' then raise exception 'Only service_role may clean history'; end if;

  with x as (
    select id from public.lead_validation_logs
    where created_at<=now()-requested_log_retention
    order by created_at limit greatest(requested_limit,1)
  )
  delete from public.lead_validation_logs l using x where l.id=x.id;
  get diagnostics logs=row_count;

  with x as (
    select id from public.lead_validation_event_outbox
    where status in ('delivered','cancelled')
      and created_at<=now()-requested_event_retention
    order by created_at limit greatest(requested_limit,1)
  )
  delete from public.lead_validation_event_outbox e using x where e.id=x.id;
  get diagnostics events=row_count;

  return jsonb_build_object('deleted_logs',logs,'deleted_events',events,'processed_at',now());
end;
$$;

create or replace function public.get_lead_validation_health(
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
    and (requested_organization_id is null
      or not public.has_organization_permission(requested_organization_id,'lead_validation.view_logs')) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),
    'queued_jobs',(select count(*) from public.lead_validation_jobs j
      where j.status in ('pending','queued','waiting')
        and (requested_organization_id is null or j.organization_id=requested_organization_id)),
    'running_jobs',(select count(*) from public.lead_validation_jobs j
      where j.status='running'
        and (requested_organization_id is null or j.organization_id=requested_organization_id)),
    'failed_jobs_24h',(select count(*) from public.lead_validation_jobs j
      where j.status='failed' and j.updated_at>=now()-interval '24 hours'
        and (requested_organization_id is null or j.organization_id=requested_organization_id)),
    'pending_reviews',(select count(*) from public.lead_validation_review_tasks t
      where t.status in ('pending','assigned','in_review')
        and (requested_organization_id is null or t.organization_id=requested_organization_id)),
    'pending_outbox_events',(select count(*) from public.lead_validation_event_outbox e
      where e.status in ('pending','failed')
        and (requested_organization_id is null or e.organization_id=requested_organization_id)),
    'dead_lettered_events',(select count(*) from public.lead_validation_event_outbox e
      where e.status='dead_lettered'
        and (requested_organization_id is null or e.organization_id=requested_organization_id))
  );
end;
$$;

revoke all on function public.release_expired_lead_validation_locks() from public;
revoke all on function public.cleanup_lead_validation_history(interval,interval,integer) from public;
revoke all on function public.get_lead_validation_health(uuid) from public;

grant execute on function public.release_expired_lead_validation_locks() to service_role;
grant execute on function public.cleanup_lead_validation_history(interval,interval,integer) to service_role;
grant execute on function public.get_lead_validation_health(uuid) to authenticated,service_role;

-- 60. Additional indexes
create index if not exists lead_validation_results_created_idx
  on public.lead_validation_results (organization_id,created_at desc);

create index if not exists lead_validation_results_risk_idx
  on public.lead_validation_results (
    organization_id,fraud_score desc,spam_score desc,duplicate_score desc,created_at desc
  );

create index if not exists lead_validation_jobs_status_updated_idx
  on public.lead_validation_jobs (organization_id,status,updated_at desc);

create index if not exists lead_validation_review_tasks_due_idx
  on public.lead_validation_review_tasks (organization_id,due_at,priority)
  where status in ('pending','assigned','in_review');

-- 61. Final validation
do $$
declare
  item text;
  missing text[]:='{}';
begin
  foreach item in array array[
    'lead_validation_profiles','lead_validation_rules','lead_validation_jobs',
    'lead_validation_results','lead_validation_rule_results',
    'lead_validation_evidence','lead_duplicate_matches',
    'lead_submission_fingerprints','lead_validation_blacklist',
    'lead_validation_email_domains','lead_source_quality_scores',
    'lead_validation_review_tasks','lead_validation_retry_queue',
    'lead_validation_logs','lead_validation_external_events',
    'lead_validation_event_outbox'
  ]
  loop
    if not exists (
      select 1 from information_schema.tables
      where table_schema='public' and table_name=item
    ) then missing:=array_append(missing,'table:'||item); end if;
  end loop;

  foreach item in array array[
    'create_lead_validation_job','run_lead_validation',
    'detect_lead_duplicates','calculate_lead_validation_scores',
    'check_lead_ai_call_eligibility','publish_lead_validation_event',
    'claim_lead_validation_event','claim_lead_validation_retry',
    'assign_lead_validation_review','get_lead_validation_workflow_handoff',
    'prepare_lead_validation_ai_call_handoff',
    'get_lead_validation_daily_summary','get_lead_validation_health'
  ]
  loop
    if not exists (
      select 1 from information_schema.routines
      where routine_schema='public' and routine_name=item
    ) then missing:=array_append(missing,'function:'||item); end if;
  end loop;

  foreach item in array array[
    'lead_validation_latest_results','lead_validation_dashboard',
    'lead_validation_trust_distribution','lead_validation_risk_trends',
    'lead_validation_review_dashboard','lead_validation_outbox_health'
  ]
  loop
    if not exists (
      select 1 from information_schema.views
      where table_schema='public' and table_name=item
    ) then missing:=array_append(missing,'view:'||item); end if;
  end loop;

  if cardinality(missing)>0 then
    raise exception '011 migration validation failed. Missing: %',array_to_string(missing,', ');
  end if;
end;
$$;

-- 62. Migration audit
insert into public.lead_validation_logs (
  organization_id,log_level,log_type,event_name,message,log_data
)
select
  o.id,'info','migration','migration.011.completed',
  'Lead Validation Engine migration 011 completed',
  jsonb_build_object(
    'migration','011_lead_validation_engine',
    'completed_at',now(),
    'modules',jsonb_build_array(
      'profiles','rules','jobs','results','duplicate_detection',
      'fraud_scoring','consent_gate','ai_call_gate',
      'manual_review','retry_queue','event_outbox',
      'workflow_handoff','analytics','maintenance'
    )
  )
from public.organizations o
where not exists (
  select 1 from public.lead_validation_logs l
  where l.organization_id=o.id and l.event_name='migration.011.completed'
);

commit;