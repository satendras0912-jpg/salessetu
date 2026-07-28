-- ============================================================
-- SalesSetu Enterprise
-- Migration 033: Tenant Onboarding & Provisioning Engine
-- PostgreSQL / Supabase
-- ============================================================
-- End-to-end tenant signup, approval, organization provisioning,
-- owner/admin invitation, workspace initialization, billing trial,
-- onboarding checklist, data import, integration readiness, domain
-- setup, activation controls, worker queues, RLS and analytics.
--
-- Supabase Auth users, JWT custom claims, DNS changes and external
-- provider accounts must be created by a secure service-role worker.
-- This migration stores durable orchestration state and outbox tasks.
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- 1. Permissions
insert into public.permissions(module,action,code,description)
select x.module,x.action,x.code,x.description
from (values
 ('onboarding','view','onboarding.view','View tenant onboarding data'),
 ('onboarding','view_all','onboarding.view_all','View all organization onboarding data'),
 ('onboarding','create','onboarding.create','Create onboarding requests'),
 ('onboarding','manage_templates','onboarding.manage_templates','Manage onboarding templates'),
 ('onboarding','manage_requests','onboarding.manage_requests','Manage onboarding requests'),
 ('onboarding','approve','onboarding.approve','Approve onboarding requests'),
 ('onboarding','provision','onboarding.provision','Provision tenant workspaces'),
 ('onboarding','manage_members','onboarding.manage_members','Manage tenant invitations and members'),
 ('onboarding','manage_checklists','onboarding.manage_checklists','Manage onboarding checklists'),
 ('onboarding','manage_imports','onboarding.manage_imports','Manage onboarding data imports'),
 ('onboarding','manage_integrations','onboarding.manage_integrations','Manage onboarding integrations'),
 ('onboarding','manage_domains','onboarding.manage_domains','Manage onboarding domains'),
 ('onboarding','manage_activation','onboarding.manage_activation','Manage go-live activation'),
 ('onboarding','manage_tasks','onboarding.manage_tasks','Manage provisioning tasks'),
 ('onboarding','view_logs','onboarding.view_logs','View onboarding logs and health'),
 ('onboarding','view_analytics','onboarding.view_analytics','View onboarding analytics')
) x(module,action,code,description)
where not exists(select 1 from public.permissions p where p.code=x.code);

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id
from public.roles r cross join public.permissions p
where r.code in ('platform_admin','organization_admin')
  and p.module='onboarding'
on conflict(role_id,permission_id) do nothing;

-- 2. Templates
create table if not exists public.onboarding_templates(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 template_code text not null,
 template_name text not null,
 description text,
 tenant_type text not null default 'brokerage' check(tenant_type in('brokerage','builder','hybrid','agency','enterprise','other')),
 version integer not null default 1 check(version>=1),
 is_default boolean not null default false,
 is_system_template boolean not null default false,
 estimated_completion_minutes integer not null default 60 check(estimated_completion_minutes>=0),
 status text not null default 'active' check(status in('draft','active','inactive','retired','archived')),
 configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists onboarding_templates_org_uidx on public.onboarding_templates(organization_id,template_code,version) where organization_id is not null;
create unique index if not exists onboarding_templates_system_uidx on public.onboarding_templates(template_code,version) where organization_id is null;
create unique index if not exists onboarding_templates_org_default_uidx on public.onboarding_templates(organization_id,tenant_type) where organization_id is not null and is_default and status='active';
create unique index if not exists onboarding_templates_system_default_uidx on public.onboarding_templates(tenant_type) where organization_id is null and is_default and status='active';

create table if not exists public.onboarding_template_steps(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 template_id uuid not null references public.onboarding_templates(id) on delete cascade,
 step_code text not null,
 step_name text not null,
 description text,
 step_category text not null default 'workspace' check(step_category in('company','workspace','team','billing','security','communication','automation','ai','inventory','data_import','domain','training','activation','custom')),
 execution_mode text not null default 'manual' check(execution_mode in('manual','automatic','worker','external','approval','hybrid')),
 sequence_number integer not null default 100,
 required boolean not null default true,
 blocking boolean not null default true,
 dependency_step_codes text[] not null default '{}',
 owner_type text not null default 'tenant_admin' check(owner_type in('tenant_admin','tenant_member','platform_admin','sales','support','system','worker','external')),
 target_module text,
 target_action text,
 estimated_minutes integer not null default 5 check(estimated_minutes>=0),
 auto_complete_rule jsonb not null default '{}',
 validation_rule jsonb not null default '{}',
 form_schema jsonb not null default '{}',
 default_data jsonb not null default '{}',
 status text not null default 'active' check(status in('active','inactive','archived')),
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(template_id,step_code)
);
create index if not exists onboarding_template_steps_sequence_idx on public.onboarding_template_steps(template_id,sequence_number,status);

-- 3. Signup and approval
create table if not exists public.tenant_onboarding_requests(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete set null,
 template_id uuid references public.onboarding_templates(id) on delete set null,
 request_code text not null unique,
 requested_by_user_id uuid references auth.users(id) on delete set null,
 organization_name text not null,
 requested_slug text,
 provisioned_slug text,
 tenant_type text not null default 'brokerage' check(tenant_type in('brokerage','builder','hybrid','agency','enterprise','other')),
 legal_name text,
 trade_name text,
 industry text not null default 'real_estate',
 sub_industry text,
 owner_full_name text not null,
 owner_email text not null,
 owner_phone text,
 website_url text,
 country_code text not null default 'IN',
 state_code text,
 city text,
 timezone text not null default 'Asia/Kolkata',
 locale text not null default 'en-IN',
 currency text not null default 'INR',
 expected_users integer not null default 3 check(expected_users>=1),
 expected_monthly_leads integer not null default 1000 check(expected_monthly_leads>=0),
 preferred_plan_code text not null default 'starter',
 preferred_price_code text not null default 'starter_monthly',
 requested_trial_days integer check(requested_trial_days is null or requested_trial_days>=0),
 referral_code text,
 sales_owner_user_id uuid references auth.users(id) on delete set null,
 source_channel text,
 utm_source text,
 utm_medium text,
 utm_campaign text,
 utm_content text,
 utm_term text,
 status text not null default 'draft' check(status in('draft','submitted','under_review','more_information_required','approved','provisioning','provisioned','activation_pending','active','rejected','cancelled','failed','archived')),
 approval_status text not null default 'not_required' check(approval_status in('not_required','pending','approved','rejected','cancelled')),
 risk_level text not null default 'low' check(risk_level in('low','medium','high','critical')),
 risk_score numeric(8,4) not null default 0 check(risk_score between 0 and 100),
 submitted_at timestamptz,
 review_started_at timestamptz,
 approved_at timestamptz,
 approved_by uuid references auth.users(id) on delete set null,
 rejected_at timestamptz,
 rejected_by uuid references auth.users(id) on delete set null,
 rejection_reason text,
 provisioning_started_at timestamptz,
 provisioned_at timestamptz,
 activated_at timestamptz,
 activated_by uuid references auth.users(id) on delete set null,
 cancelled_at timestamptz,
 cancellation_reason text,
 failure_code text,
 failure_message text,
 failure_data jsonb not null default '{}',
 company_data jsonb not null default '{}',
 workspace_preferences jsonb not null default '{}',
 billing_preferences jsonb not null default '{}',
 integration_preferences jsonb not null default '{}',
 security_preferences jsonb not null default '{}',
 metadata jsonb not null default '{}',
 idempotency_key text,
 correlation_id text,
 trace_id text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists tenant_onboarding_requests_idem_uidx on public.tenant_onboarding_requests(idempotency_key) where idempotency_key is not null;
create index if not exists tenant_onboarding_requests_status_idx on public.tenant_onboarding_requests(status,approval_status,created_at);
create index if not exists tenant_onboarding_requests_owner_idx on public.tenant_onboarding_requests(lower(owner_email),status);

create table if not exists public.onboarding_request_contacts(
 id uuid primary key default gen_random_uuid(),
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 organization_id uuid references public.organizations(id) on delete cascade,
 contact_type text not null check(contact_type in('owner','administrator','billing','technical','sales','support','legal','other')),
 full_name text not null,
 email text,
 phone text,
 designation text,
 is_primary boolean not null default false,
 can_receive_invite boolean not null default true,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists onboarding_request_contacts_primary_uidx on public.onboarding_request_contacts(onboarding_request_id,contact_type) where is_primary;

create table if not exists public.onboarding_approvals(
 id uuid primary key default gen_random_uuid(),
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 organization_id uuid references public.organizations(id) on delete cascade,
 approval_code text not null,
 approval_type text not null default 'tenant_provisioning' check(approval_type in('tenant_provisioning','enterprise_plan','discount','custom_domain','data_import','go_live','security_exception','custom')),
 sequence_number integer not null default 1,
 approver_user_id uuid references auth.users(id) on delete set null,
 approver_role_id uuid references public.roles(id) on delete set null,
 status text not null default 'pending' check(status in('pending','approved','rejected','cancelled','skipped')),
 requested_at timestamptz not null default now(),
 decided_at timestamptz,
 decision_notes text,
 decision_data jsonb not null default '{}',
 expires_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(onboarding_request_id,approval_code)
);

-- 4. Members and invitations
create table if not exists public.onboarding_tenant_members(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid references public.tenant_onboarding_requests(id) on delete set null,
 user_id uuid references auth.users(id) on delete set null,
 member_code text not null,
 email text not null,
 full_name text,
 phone text,
 role_id uuid references public.roles(id) on delete set null,
 requested_role_code text not null default 'organization_admin',
 member_type text not null default 'employee' check(member_type in('owner','administrator','employee','contractor','partner','service_account','other')),
 status text not null default 'invited' check(status in('invited','pending_auth','active','suspended','revoked','expired','archived')),
 is_owner boolean not null default false,
 is_primary_admin boolean not null default false,
 invited_at timestamptz,
 joined_at timestamptz,
 last_active_at timestamptz,
 access_provisioned_at timestamptz,
 access_provisioning_status text not null default 'pending' check(access_provisioning_status in('pending','queued','processing','provisioned','failed','revoked')),
 access_failure_message text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,member_code)
);
create unique index if not exists onboarding_tenant_members_user_uidx on public.onboarding_tenant_members(organization_id,user_id) where user_id is not null and status<>'archived';
create unique index if not exists onboarding_tenant_members_email_uidx on public.onboarding_tenant_members(organization_id,(lower(email))) where status<>'archived';
create unique index if not exists onboarding_tenant_members_owner_uidx on public.onboarding_tenant_members(organization_id) where is_owner and status<>'archived';

create table if not exists public.onboarding_invitations(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid references public.tenant_onboarding_requests(id) on delete set null,
 tenant_member_id uuid references public.onboarding_tenant_members(id) on delete cascade,
 invitation_code text not null,
 email text not null,
 full_name text,
 phone text,
 requested_role_code text not null default 'organization_admin',
 member_type text not null default 'employee',
 token_hash text not null,
 status text not null default 'pending' check(status in('pending','sent','delivered','accepted','expired','revoked','failed','archived')),
 expires_at timestamptz not null,
 sent_at timestamptz,
 delivered_at timestamptz,
 accepted_at timestamptz,
 accepted_by_user_id uuid references auth.users(id) on delete set null,
 revoked_at timestamptz,
 revoked_by uuid references auth.users(id) on delete set null,
 revocation_reason text,
 send_attempts integer not null default 0,
 last_send_attempt_at timestamptz,
 last_error_message text,
 redirect_url text,
 metadata jsonb not null default '{}',
 invited_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,invitation_code)
);
create unique index if not exists onboarding_invitations_token_uidx on public.onboarding_invitations(token_hash) where status in('pending','sent','delivered');
create index if not exists onboarding_invitations_pending_idx on public.onboarding_invitations(organization_id,status,expires_at) where status in('pending','sent','delivered');

-- 5. Provisioning workers
create table if not exists public.onboarding_provisioning_runs(
 id uuid primary key default gen_random_uuid(),
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 organization_id uuid references public.organizations(id) on delete cascade,
 run_code text not null unique,
 run_type text not null default 'initial' check(run_type in('initial','retry','repair','reprovision','upgrade','custom')),
 status text not null default 'queued' check(status in('queued','running','waiting','completed','partially_completed','failed','cancelled','rolled_back')),
 total_tasks integer not null default 0,
 completed_tasks integer not null default 0,
 failed_tasks integer not null default 0,
 skipped_tasks integer not null default 0,
 progress_percentage numeric(8,4) not null default 0 check(progress_percentage between 0 and 100),
 started_at timestamptz,
 completed_at timestamptz,
 failed_at timestamptz,
 failure_code text,
 failure_message text,
 failure_data jsonb not null default '{}',
 initiated_by uuid references auth.users(id) on delete set null,
 idempotency_key text,
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists onboarding_provisioning_runs_idem_uidx on public.onboarding_provisioning_runs(idempotency_key) where idempotency_key is not null;

create table if not exists public.onboarding_provisioning_tasks(
 id uuid primary key default gen_random_uuid(),
 provisioning_run_id uuid not null references public.onboarding_provisioning_runs(id) on delete cascade,
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 organization_id uuid references public.organizations(id) on delete cascade,
 task_code text not null,
 task_name text not null,
 task_type text not null check(task_type in('database','auth','rbac','billing','configuration','communication','integration','domain','data_import','sample_data','security','activation','external','custom')),
 handler_code text not null,
 destination text not null default 'internal' check(destination in('internal','service_worker','integration_api','automation_engine','enterprise_workflow','communication_engine','notification_engine','billing','security_governance','document_engine','n8n','external')),
 sequence_number integer not null default 100,
 priority integer not null default 100,
 dependency_task_codes text[] not null default '{}',
 required boolean not null default true,
 blocking boolean not null default true,
 status text not null default 'queued' check(status in('queued','claimed','running','waiting','completed','skipped','failed','cancelled','dead_lettered')),
 input_data jsonb not null default '{}',
 output_data jsonb not null default '{}',
 available_at timestamptz not null default now(),
 attempt_count integer not null default 0,
 maximum_attempts integer not null default 5,
 claimed_at timestamptz,
 claimed_by text,
 lock_token text,
 lock_expires_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 failed_at timestamptz,
 last_error_code text,
 last_error_message text,
 last_error_data jsonb not null default '{}',
 idempotency_key text,
 correlation_id text,
 trace_id text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(provisioning_run_id,task_code)
);
create unique index if not exists onboarding_provisioning_tasks_idem_uidx on public.onboarding_provisioning_tasks(idempotency_key) where idempotency_key is not null;
create index if not exists onboarding_provisioning_tasks_worker_idx on public.onboarding_provisioning_tasks(status,available_at,priority,sequence_number,created_at) where status in('queued','failed');

-- 6. Workspace and checklist
create table if not exists public.onboarding_workspace_settings(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid references public.tenant_onboarding_requests(id) on delete set null,
 setting_group text not null,
 setting_key text not null,
 setting_value jsonb not null default '{}',
 source text not null default 'onboarding' check(source in('onboarding','template','tenant','platform','billing_plan','integration','system')),
 locked boolean not null default false,
 sensitive boolean not null default false,
 status text not null default 'active' check(status in('active','inactive','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,setting_group,setting_key)
);

create table if not exists public.onboarding_checklist_items(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 template_step_id uuid references public.onboarding_template_steps(id) on delete set null,
 item_code text not null,
 item_name text not null,
 description text,
 category text not null,
 sequence_number integer not null default 100,
 required boolean not null default true,
 blocking boolean not null default true,
 dependency_item_codes text[] not null default '{}',
 owner_type text not null default 'tenant_admin',
 assigned_user_id uuid references auth.users(id) on delete set null,
 status text not null default 'pending' check(status in('pending','available','in_progress','waiting','completed','skipped','failed','cancelled')),
 progress_percentage numeric(8,4) not null default 0 check(progress_percentage between 0 and 100),
 due_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 completed_by uuid references auth.users(id) on delete set null,
 completion_notes text,
 completion_data jsonb not null default '{}',
 validation_status text not null default 'not_validated' check(validation_status in('not_validated','pending','passed','failed','warning','skipped')),
 validation_message text,
 validation_data jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(onboarding_request_id,item_code)
);
create index if not exists onboarding_checklist_progress_idx on public.onboarding_checklist_items(organization_id,onboarding_request_id,status,sequence_number);

create table if not exists public.onboarding_progress_events(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 checklist_item_id uuid references public.onboarding_checklist_items(id) on delete set null,
 provisioning_task_id uuid references public.onboarding_provisioning_tasks(id) on delete set null,
 event_name text not null,
 previous_status text,
 new_status text,
 progress_percentage numeric(8,4),
 actor_user_id uuid references auth.users(id) on delete set null,
 actor_type text not null default 'user' check(actor_type in('user','service_role','worker','system','external')),
 event_data jsonb not null default '{}',
 correlation_id text,
 trace_id text,
 occurred_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
create index if not exists onboarding_progress_events_request_idx on public.onboarding_progress_events(onboarding_request_id,occurred_at desc);

-- 7. Imports and sample data
create table if not exists public.onboarding_data_import_jobs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 import_code text not null,
 import_type text not null check(import_type in('leads','contacts','inventory','projects','agents','customers','followups','site_visits','bookings','documents','custom')),
 source_type text not null check(source_type in('csv','xlsx','json','api','webhook','google_sheet','airtable','crm','database','manual','custom')),
 source_reference text,
 source_document_id uuid references public.documents(id) on delete set null,
 mapping_configuration jsonb not null default '{}',
 validation_configuration jsonb not null default '{}',
 transformation_configuration jsonb not null default '{}',
 status text not null default 'draft' check(status in('draft','uploaded','validating','validation_failed','ready','queued','processing','completed','partially_completed','failed','cancelled','archived')),
 total_records bigint not null default 0,
 valid_records bigint not null default 0,
 invalid_records bigint not null default 0,
 duplicate_records bigint not null default 0,
 imported_records bigint not null default 0,
 skipped_records bigint not null default 0,
 failed_records bigint not null default 0,
 progress_percentage numeric(8,4) not null default 0 check(progress_percentage between 0 and 100),
 dry_run boolean not null default true,
 started_at timestamptz,
 completed_at timestamptz,
 failed_at timestamptz,
 failure_code text,
 failure_message text,
 failure_data jsonb not null default '{}',
 result_summary jsonb not null default '{}',
 initiated_by uuid references auth.users(id) on delete set null,
 idempotency_key text,
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,import_code)
);
create unique index if not exists onboarding_import_jobs_idem_uidx on public.onboarding_data_import_jobs(idempotency_key) where idempotency_key is not null;
create index if not exists onboarding_import_jobs_worker_idx on public.onboarding_data_import_jobs(status,created_at) where status in('ready','queued','failed');

create table if not exists public.onboarding_sample_data_packs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 pack_code text not null,
 pack_name text not null,
 description text,
 tenant_type text not null default 'brokerage',
 version integer not null default 1,
 is_system_pack boolean not null default false,
 included_modules text[] not null default '{}',
 record_manifest jsonb not null default '{}',
 provisioning_configuration jsonb not null default '{}',
 status text not null default 'active' check(status in('draft','active','inactive','retired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists onboarding_sample_packs_org_uidx on public.onboarding_sample_data_packs(organization_id,pack_code,version) where organization_id is not null;
create unique index if not exists onboarding_sample_packs_system_uidx on public.onboarding_sample_data_packs(pack_code,version) where organization_id is null;

create table if not exists public.onboarding_sample_data_jobs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 sample_data_pack_id uuid not null references public.onboarding_sample_data_packs(id) on delete restrict,
 job_code text not null,
 status text not null default 'queued' check(status in('queued','processing','completed','partially_completed','failed','cancelled','rolled_back')),
 created_record_counts jsonb not null default '{}',
 created_record_ids jsonb not null default '{}',
 started_at timestamptz,
 completed_at timestamptz,
 failed_at timestamptz,
 failure_message text,
 result_data jsonb not null default '{}',
 initiated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,job_code)
);

-- 8. Integration and domain readiness
create table if not exists public.onboarding_integration_requirements(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 requirement_code text not null,
 integration_code text not null,
 integration_name text not null,
 provider text,
 integration_type text not null check(integration_type in('communication','automation','ai','payments','advertising','analytics','storage','calendar','email','crm','webhook','custom')),
 required boolean not null default false,
 blocking boolean not null default false,
 status text not null default 'not_started' check(status in('not_started','credentials_required','configuration_pending','verification_pending','connected','healthy','degraded','failed','waived','archived')),
 credential_reference text,
 external_account_id text,
 configuration jsonb not null default '{}',
 health_data jsonb not null default '{}',
 last_health_check_at timestamptz,
 connected_at timestamptz,
 failed_at timestamptz,
 failure_message text,
 configured_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,requirement_code)
);

create table if not exists public.onboarding_domain_requests(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 request_code text not null,
 domain_name text not null,
 domain_type text not null default 'custom' check(domain_type in('platform_subdomain','custom','white_label','api','automation')),
 verification_method text not null default 'dns_txt' check(verification_method in('dns_txt','dns_cname','http_file','email','manual')),
 verification_token text,
 verification_record jsonb not null default '{}',
 verification_status text not null default 'pending' check(verification_status in('pending','verifying','verified','failed','expired','waived')),
 ssl_status text not null default 'pending' check(ssl_status in('pending','provisioning','active','failed','expired','not_required')),
 routing_status text not null default 'pending' check(routing_status in('pending','configuring','active','failed','disabled')),
 status text not null default 'requested' check(status in('requested','processing','active','failed','cancelled','archived')),
 verified_at timestamptz,
 ssl_activated_at timestamptz,
 routing_activated_at timestamptz,
 failure_message text,
 metadata jsonb not null default '{}',
 requested_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,request_code)
);
create unique index if not exists onboarding_domain_requests_domain_uidx on public.onboarding_domain_requests((lower(domain_name)));

-- 9. Activation controls
create table if not exists public.onboarding_activation_checks(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 onboarding_request_id uuid not null references public.tenant_onboarding_requests(id) on delete cascade,
 check_code text not null,
 check_name text not null,
 description text,
 check_category text not null default 'workspace' check(check_category in('company','workspace','billing','members','security','communication','automation','integration','data','domain','training','custom')),
 required boolean not null default true,
 blocking boolean not null default true,
 validation_mode text not null default 'automatic' check(validation_mode in('automatic','manual','worker','external','approval')),
 status text not null default 'pending' check(status in('pending','checking','passed','failed','warning','waived','not_applicable')),
 score_weight numeric(8,4) not null default 1 check(score_weight>=0),
 checked_at timestamptz,
 checked_by uuid references auth.users(id) on delete set null,
 result_message text,
 result_data jsonb not null default '{}',
 failure_remediation text,
 waived_at timestamptz,
 waived_by uuid references auth.users(id) on delete set null,
 waiver_reason text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(onboarding_request_id,check_code)
);
create index if not exists onboarding_activation_checks_status_idx on public.onboarding_activation_checks(organization_id,onboarding_request_id,required,blocking,status);

-- 10. Event outbox and logs
create table if not exists public.onboarding_event_outbox(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 onboarding_request_id uuid references public.tenant_onboarding_requests(id) on delete cascade,
 event_name text not null,
 source_type text,
 source_id uuid,
 destination text not null default 'internal' check(destination in('internal','service_worker','automation_engine','enterprise_workflow','communication_engine','notification_engine','integration_api','billing','security_governance','document_engine','reporting','analytics','audit','observability','n8n','webhook','external')),
 status text not null default 'pending' check(status in('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
 priority integer not null default 100,
 payload jsonb not null default '{}',
 available_at timestamptz not null default now(),
 delivery_attempts integer not null default 0,
 maximum_attempts integer not null default 10,
 claimed_at timestamptz,
 claimed_by text,
 lock_token text,
 lock_expires_at timestamptz,
 delivered_at timestamptz,
 last_error_code text,
 last_error_message text,
 last_error_data jsonb not null default '{}',
 idempotency_key text,
 correlation_id text,
 trace_id text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists onboarding_event_outbox_idem_uidx on public.onboarding_event_outbox(idempotency_key) where idempotency_key is not null;
create index if not exists onboarding_event_outbox_worker_idx on public.onboarding_event_outbox(status,available_at,priority,created_at) where status in('pending','failed');

create table if not exists public.onboarding_logs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete set null,
 onboarding_request_id uuid references public.tenant_onboarding_requests(id) on delete set null,
 log_level text not null default 'info' check(log_level in('debug','info','warning','error','critical')),
 event_name text,
 message text,
 source_type text,
 source_id uuid,
 actor_user_id uuid references auth.users(id) on delete set null,
 error_code text,
 error_message text,
 log_data jsonb not null default '{}',
 correlation_id text,
 trace_id text,
 created_at timestamptz not null default now()
);
create index if not exists onboarding_logs_org_time_idx on public.onboarding_logs(organization_id,created_at desc);
create index if not exists onboarding_logs_request_time_idx on public.onboarding_logs(onboarding_request_id,created_at desc);

-- 11. Updated-at triggers
do $$
declare t text;
begin
 foreach t in array array[
  'onboarding_templates','onboarding_template_steps','tenant_onboarding_requests',
  'onboarding_request_contacts','onboarding_approvals','onboarding_tenant_members',
  'onboarding_invitations','onboarding_provisioning_runs','onboarding_provisioning_tasks',
  'onboarding_workspace_settings','onboarding_checklist_items','onboarding_data_import_jobs',
  'onboarding_sample_data_packs','onboarding_sample_data_jobs',
  'onboarding_integration_requirements','onboarding_domain_requests',
  'onboarding_activation_checks','onboarding_event_outbox'
 ] loop
  execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
  execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
 end loop;
end;
$$;

-- ============================================================
-- 12. Core helpers and event outbox
-- ============================================================

create or replace function public.normalize_onboarding_slug(p_value text)
returns text
language sql
immutable
set search_path=''
as $$
 select nullif(trim(both '-' from regexp_replace(regexp_replace(lower(coalesce(p_value,'')),'[^a-z0-9]+','-','g'),'-+','-','g')),'');
$$;

create or replace function public.publish_onboarding_event(
 p_organization_id uuid,
 p_onboarding_request_id uuid,
 p_event_name text,
 p_payload jsonb default '{}'::jsonb,
 p_destination text default 'internal',
 p_source_type text default null,
 p_source_id uuid default null,
 p_priority integer default 100,
 p_idempotency_key text default null,
 p_correlation_id text default null,
 p_trace_id text default null,
 p_available_at timestamptz default now()
)
returns public.onboarding_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare existing_row public.onboarding_event_outbox; result_row public.onboarding_event_outbox;
begin
 if p_idempotency_key is not null then
  select * into existing_row from public.onboarding_event_outbox where idempotency_key=p_idempotency_key limit 1;
  if found then return existing_row; end if;
 end if;
 insert into public.onboarding_event_outbox(
  organization_id,onboarding_request_id,event_name,source_type,source_id,destination,status,priority,payload,available_at,idempotency_key,correlation_id,trace_id
 ) values(
  p_organization_id,p_onboarding_request_id,p_event_name,p_source_type,p_source_id,p_destination,'pending',p_priority,coalesce(p_payload,'{}'::jsonb),coalesce(p_available_at,now()),p_idempotency_key,p_correlation_id,p_trace_id
 ) returning * into result_row;
 return result_row;
end;
$$;

create or replace function public.claim_onboarding_event(
 p_worker_id text,
 p_destination text default null,
 p_lock_seconds integer default 300
)
returns public.onboarding_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare result_row public.onboarding_event_outbox;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may claim onboarding events'; end if;
 update public.onboarding_event_outbox
 set status='failed',available_at=now(),claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
     last_error_code=coalesce(last_error_code,'LOCK_EXPIRED'),last_error_message=coalesce(last_error_message,'Onboarding event lock expired'),updated_at=now()
 where status in('claimed','processing') and lock_expires_at is not null and lock_expires_at<=now();
 select * into result_row
 from public.onboarding_event_outbox
 where status in('pending','failed') and available_at<=now() and delivery_attempts<maximum_attempts
   and (p_destination is null or destination=p_destination)
 order by priority,created_at
 for update skip locked limit 1;
 if not found then return null; end if;
 update public.onboarding_event_outbox
 set status='claimed',delivery_attempts=delivery_attempts+1,claimed_at=now(),claimed_by=p_worker_id,
     lock_token=gen_random_uuid()::text,lock_expires_at=now()+make_interval(secs=>greatest(p_lock_seconds,1)),updated_at=now()
 where id=result_row.id returning * into result_row;
 return result_row;
end;
$$;

create or replace function public.complete_onboarding_event(
 p_event_id uuid,
 p_lock_token text,
 p_result_data jsonb default '{}'::jsonb
)
returns public.onboarding_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare result_row public.onboarding_event_outbox;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may complete onboarding events'; end if;
 select * into result_row from public.onboarding_event_outbox where id=p_event_id for update;
 if not found then raise exception 'Onboarding event not found'; end if;
 if result_row.lock_token is distinct from p_lock_token then raise exception 'Invalid onboarding event lock token'; end if;
 update public.onboarding_event_outbox
 set status='delivered',delivered_at=now(),payload=payload||jsonb_build_object('delivery_result',coalesce(p_result_data,'{}'::jsonb)),
     claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,last_error_code=null,last_error_message=null,last_error_data='{}',updated_at=now()
 where id=p_event_id returning * into result_row;
 return result_row;
end;
$$;

create or replace function public.fail_onboarding_event(
 p_event_id uuid,
 p_lock_token text,
 p_error_code text,
 p_error_message text,
 p_error_data jsonb default '{}'::jsonb
)
returns public.onboarding_event_outbox
language plpgsql
security definer
set search_path=''
as $$
declare result_row public.onboarding_event_outbox; next_status text; retry_seconds integer;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may fail onboarding events'; end if;
 select * into result_row from public.onboarding_event_outbox where id=p_event_id for update;
 if not found then raise exception 'Onboarding event not found'; end if;
 if result_row.lock_token is distinct from p_lock_token then raise exception 'Invalid onboarding event lock token'; end if;
 next_status:=case when result_row.delivery_attempts>=result_row.maximum_attempts then 'dead_lettered' else 'failed' end;
 retry_seconds:=least(3600,greatest(30,power(2,greatest(result_row.delivery_attempts,1))::integer*30));
 update public.onboarding_event_outbox
 set status=next_status,available_at=case when next_status='failed' then now()+make_interval(secs=>retry_seconds) else available_at end,
     last_error_code=p_error_code,last_error_message=p_error_message,last_error_data=coalesce(p_error_data,'{}'::jsonb),
     claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
 where id=p_event_id returning * into result_row;
 insert into public.onboarding_logs(organization_id,onboarding_request_id,log_level,event_name,message,source_type,source_id,error_code,error_message,log_data,correlation_id,trace_id)
 values(result_row.organization_id,result_row.onboarding_request_id,case when next_status='dead_lettered' then 'critical' else 'error' end,
        'onboarding.event.'||next_status,'Onboarding event delivery failed','onboarding_event_outbox',result_row.id,p_error_code,p_error_message,
        coalesce(p_error_data,'{}'::jsonb),result_row.correlation_id,result_row.trace_id);
 return result_row;
end;
$$;

create or replace function public.resolve_onboarding_template(
 p_tenant_type text,
 p_organization_id uuid default null,
 p_template_code text default null
)
returns public.onboarding_templates
language plpgsql
stable
security definer
set search_path=''
as $$
declare result_row public.onboarding_templates;
begin
 select * into result_row
 from public.onboarding_templates t
 where t.status='active' and t.tenant_type=p_tenant_type
   and (p_template_code is null or t.template_code=p_template_code)
   and (t.organization_id=p_organization_id or t.organization_id is null)
 order by case when t.organization_id=p_organization_id then 0 else 1 end,
          case when t.is_default then 0 else 1 end,t.version desc
 limit 1;
 if not found then raise exception 'No active onboarding template found for tenant type %',p_tenant_type; end if;
 return result_row;
end;
$$;

create or replace function public.generate_unique_onboarding_slug(p_requested_slug text,p_organization_name text)
returns text
language plpgsql
stable
security definer
set search_path=''
as $$
declare base_slug text; candidate text; counter integer:=0;
begin
 base_slug:=public.normalize_onboarding_slug(coalesce(p_requested_slug,p_organization_name));
 if base_slug is null then base_slug:='tenant'; end if;
 candidate:=base_slug;
 while exists(select 1 from public.organizations o where o.slug=candidate) loop
  counter:=counter+1;
  candidate:=base_slug||'-'||counter::text;
  if counter>10000 then candidate:=base_slug||'-'||lower(substr(replace(gen_random_uuid()::text,'-',''),1,8)); exit; end if;
 end loop;
 return candidate;
end;
$$;

-- ============================================================
-- 13. Signup request lifecycle
-- ============================================================

create or replace function public.create_tenant_onboarding_request(
 p_organization_name text,
 p_owner_full_name text,
 p_owner_email text,
 p_owner_phone text default null,
 p_tenant_type text default 'brokerage',
 p_requested_slug text default null,
 p_legal_name text default null,
 p_trade_name text default null,
 p_state_code text default null,
 p_city text default null,
 p_timezone text default 'Asia/Kolkata',
 p_locale text default 'en-IN',
 p_currency text default 'INR',
 p_expected_users integer default 3,
 p_expected_monthly_leads integer default 1000,
 p_preferred_plan_code text default 'starter',
 p_preferred_price_code text default 'starter_monthly',
 p_requested_trial_days integer default null,
 p_source_channel text default null,
 p_utm_source text default null,
 p_utm_medium text default null,
 p_utm_campaign text default null,
 p_idempotency_key text default null,
 p_company_data jsonb default '{}'::jsonb,
 p_workspace_preferences jsonb default '{}'::jsonb,
 p_integration_preferences jsonb default '{}'::jsonb,
 p_metadata jsonb default '{}'::jsonb
)
returns public.tenant_onboarding_requests
language plpgsql
security definer
set search_path=''
as $$
declare existing_row public.tenant_onboarding_requests; template_row public.onboarding_templates; result_row public.tenant_onboarding_requests; normalized_slug text;
begin
 if auth.uid() is null and auth.role()<>'service_role' then raise exception 'Authentication is required'; end if;
 if p_organization_name is null or length(trim(p_organization_name))<2 then raise exception 'Organization name is required'; end if;
 if p_owner_email is null or position('@' in p_owner_email)<=1 then raise exception 'A valid owner email is required'; end if;
 if p_idempotency_key is not null then
  select * into existing_row from public.tenant_onboarding_requests where idempotency_key=p_idempotency_key limit 1;
  if found then return existing_row; end if;
 end if;
 template_row:=public.resolve_onboarding_template(p_tenant_type,null,null);
 normalized_slug:=public.normalize_onboarding_slug(coalesce(p_requested_slug,p_organization_name));
 insert into public.tenant_onboarding_requests(
  template_id,request_code,requested_by_user_id,organization_name,requested_slug,tenant_type,legal_name,trade_name,industry,
  owner_full_name,owner_email,owner_phone,country_code,state_code,city,timezone,locale,currency,expected_users,expected_monthly_leads,
  preferred_plan_code,preferred_price_code,requested_trial_days,source_channel,utm_source,utm_medium,utm_campaign,status,approval_status,
  company_data,workspace_preferences,integration_preferences,metadata,idempotency_key,correlation_id
 ) values(
  template_row.id,'ONB-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),auth.uid(),trim(p_organization_name),normalized_slug,p_tenant_type,
  p_legal_name,p_trade_name,'real_estate',trim(p_owner_full_name),lower(trim(p_owner_email)),p_owner_phone,'IN',p_state_code,p_city,p_timezone,p_locale,p_currency,
  greatest(p_expected_users,1),greatest(p_expected_monthly_leads,0),p_preferred_plan_code,p_preferred_price_code,p_requested_trial_days,p_source_channel,
  p_utm_source,p_utm_medium,p_utm_campaign,'draft',case when p_preferred_plan_code='enterprise' then 'pending' else 'not_required' end,
  coalesce(p_company_data,'{}'::jsonb),coalesce(p_workspace_preferences,'{}'::jsonb),coalesce(p_integration_preferences,'{}'::jsonb),coalesce(p_metadata,'{}'::jsonb),
  p_idempotency_key,gen_random_uuid()::text
 ) returning * into result_row;
 insert into public.onboarding_request_contacts(onboarding_request_id,contact_type,full_name,email,phone,is_primary,can_receive_invite,created_by,updated_by)
 values(result_row.id,'owner',result_row.owner_full_name,result_row.owner_email,result_row.owner_phone,true,true,auth.uid(),auth.uid());
 insert into public.onboarding_progress_events(onboarding_request_id,event_name,new_status,progress_percentage,actor_user_id,actor_type,event_data,correlation_id)
 values(result_row.id,'onboarding.request.created','draft',0,auth.uid(),case when auth.role()='service_role' then 'service_role' else 'user' end,
        jsonb_build_object('tenant_type',result_row.tenant_type,'preferred_plan_code',result_row.preferred_plan_code),result_row.correlation_id);
 return result_row;
end;
$$;

create or replace function public.submit_tenant_onboarding_request(p_onboarding_request_id uuid)
returns public.tenant_onboarding_requests
language plpgsql
security definer
set search_path=''
as $$
declare result_row public.tenant_onboarding_requests;
begin
 select * into result_row from public.tenant_onboarding_requests where id=p_onboarding_request_id for update;
 if not found then raise exception 'Onboarding request not found'; end if;
 if auth.role()<>'service_role' and result_row.requested_by_user_id is distinct from auth.uid() then raise exception 'Permission denied'; end if;
 if result_row.status not in('draft','more_information_required') then raise exception 'Request cannot be submitted from status %',result_row.status; end if;
 update public.tenant_onboarding_requests
 set status=case when approval_status='pending' then 'under_review' else 'approved' end,
     submitted_at=coalesce(submitted_at,now()),review_started_at=case when approval_status='pending' then coalesce(review_started_at,now()) else review_started_at end,
     approved_at=case when approval_status='not_required' then coalesce(approved_at,now()) else approved_at end,updated_at=now()
 where id=result_row.id returning * into result_row;
 if result_row.approval_status='pending' then
  insert into public.onboarding_approvals(onboarding_request_id,approval_code,approval_type,sequence_number,approver_role_id,status,requested_at)
  select result_row.id,'TENANT_PROVISIONING',case when result_row.preferred_plan_code='enterprise' then 'enterprise_plan' else 'tenant_provisioning' end,1,r.id,'pending',now()
  from public.roles r where r.code='platform_admin' limit 1
  on conflict(onboarding_request_id,approval_code) do nothing;
 end if;
 insert into public.onboarding_progress_events(onboarding_request_id,event_name,previous_status,new_status,progress_percentage,actor_user_id,actor_type,correlation_id)
 values(result_row.id,'onboarding.request.submitted','draft',result_row.status,5,auth.uid(),case when auth.role()='service_role' then 'service_role' else 'user' end,result_row.correlation_id);
 perform public.publish_onboarding_event(null,result_row.id,'onboarding.request.submitted',
  jsonb_build_object('request_id',result_row.id,'request_code',result_row.request_code,'organization_name',result_row.organization_name,'tenant_type',result_row.tenant_type,
                     'owner_email',result_row.owner_email,'approval_status',result_row.approval_status,'status',result_row.status),
  case when result_row.approval_status='pending' then 'notification_engine' else 'service_worker' end,'tenant_onboarding_request',result_row.id,50,
  'onboarding-request-submitted:'||result_row.id::text,result_row.correlation_id,result_row.trace_id,now());
 return result_row;
end;
$$;

create or replace function public.decide_tenant_onboarding_request(
 p_onboarding_request_id uuid,
 p_decision text,
 p_decision_notes text default null,
 p_decision_data jsonb default '{}'::jsonb
)
returns public.tenant_onboarding_requests
language plpgsql
security definer
set search_path=''
as $$
declare result_row public.tenant_onboarding_requests;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may decide onboarding requests'; end if;
 if p_decision not in('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
 select * into result_row from public.tenant_onboarding_requests where id=p_onboarding_request_id for update;
 if not found then raise exception 'Onboarding request not found'; end if;
 if result_row.status not in('submitted','under_review','more_information_required') then raise exception 'Request cannot be decided from status %',result_row.status; end if;
 update public.onboarding_approvals
 set status=p_decision,decided_at=now(),approver_user_id=auth.uid(),decision_notes=p_decision_notes,decision_data=coalesce(p_decision_data,'{}'::jsonb),updated_at=now()
 where onboarding_request_id=result_row.id and status='pending';
 update public.tenant_onboarding_requests
 set approval_status=p_decision,status=p_decision,
     approved_at=case when p_decision='approved' then now() else approved_at end,
     approved_by=case when p_decision='approved' then auth.uid() else approved_by end,
     rejected_at=case when p_decision='rejected' then now() else rejected_at end,
     rejected_by=case when p_decision='rejected' then auth.uid() else rejected_by end,
     rejection_reason=case when p_decision='rejected' then p_decision_notes else rejection_reason end,updated_at=now()
 where id=result_row.id returning * into result_row;
 insert into public.onboarding_progress_events(onboarding_request_id,event_name,previous_status,new_status,progress_percentage,actor_user_id,actor_type,event_data,correlation_id)
 values(result_row.id,'onboarding.request.'||p_decision,'under_review',p_decision,case when p_decision='approved' then 10 else 0 end,auth.uid(),'service_role',
        jsonb_build_object('notes',p_decision_notes,'decision_data',coalesce(p_decision_data,'{}'::jsonb)),result_row.correlation_id);
 perform public.publish_onboarding_event(null,result_row.id,'onboarding.request.'||p_decision,
  jsonb_build_object('request_id',result_row.id,'request_code',result_row.request_code,'decision',p_decision,'notes',p_decision_notes),
  case when p_decision='approved' then 'service_worker' else 'communication_engine' end,'tenant_onboarding_request',result_row.id,20,
  'onboarding-request-decision:'||result_row.id::text||':'||p_decision,result_row.correlation_id,result_row.trace_id,now());
 return result_row;
end;
$$;

-- ============================================================
-- 14. Invitation lifecycle
-- ============================================================

create or replace function public.create_onboarding_invitation(
 p_organization_id uuid,
 p_onboarding_request_id uuid,
 p_email text,
 p_full_name text default null,
 p_phone text default null,
 p_requested_role_code text default 'sales_agent',
 p_member_type text default 'employee',
 p_expiry_days integer default 7,
 p_redirect_url text default null,
 p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare role_row public.roles; member_row public.onboarding_tenant_members; invite_row public.onboarding_invitations; raw_token text; hashed_token text;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'onboarding.manage_members') then raise exception 'Permission denied'; end if;
 select * into role_row from public.roles where code=p_requested_role_code limit 1;
 if not found then raise exception 'Role not found: %',p_requested_role_code; end if;
 insert into public.onboarding_tenant_members(
  organization_id,onboarding_request_id,member_code,email,full_name,phone,role_id,requested_role_code,member_type,status,is_owner,is_primary_admin,invited_at,
  access_provisioning_status,metadata,created_by,updated_by
 ) values(
  p_organization_id,p_onboarding_request_id,'MEM-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,16)),lower(trim(p_email)),p_full_name,p_phone,role_row.id,
  p_requested_role_code,p_member_type,'invited',coalesce((p_metadata->>'is_owner')::boolean,false),coalesce((p_metadata->>'is_primary_admin')::boolean,false),now(),
  'pending',coalesce(p_metadata,'{}'::jsonb),auth.uid(),auth.uid()
 ) on conflict(organization_id,(lower(email))) where status<>'archived'
 do update set full_name=excluded.full_name,phone=excluded.phone,role_id=excluded.role_id,requested_role_code=excluded.requested_role_code,
               member_type=excluded.member_type,status='invited',invited_at=now(),metadata=public.onboarding_tenant_members.metadata||excluded.metadata,
               updated_by=auth.uid(),updated_at=now()
 returning * into member_row;
 raw_token:=encode(gen_random_bytes(32),'hex');
 hashed_token:=encode(digest(raw_token,'sha256'),'hex');
 update public.onboarding_invitations set status='revoked',revoked_at=now(),revoked_by=auth.uid(),revocation_reason='Superseded',updated_at=now()
 where organization_id=p_organization_id and lower(email)=lower(trim(p_email)) and status in('pending','sent','delivered');
 insert into public.onboarding_invitations(
  organization_id,onboarding_request_id,tenant_member_id,invitation_code,email,full_name,phone,requested_role_code,member_type,token_hash,status,expires_at,redirect_url,metadata,invited_by
 ) values(
  p_organization_id,p_onboarding_request_id,member_row.id,'INV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),lower(trim(p_email)),p_full_name,p_phone,
  p_requested_role_code,p_member_type,hashed_token,'pending',now()+make_interval(days=>greatest(p_expiry_days,1)),p_redirect_url,coalesce(p_metadata,'{}'::jsonb),auth.uid()
 ) returning * into invite_row;
 perform public.publish_onboarding_event(p_organization_id,p_onboarding_request_id,'onboarding.invitation.created',
  jsonb_build_object('invitation_id',invite_row.id,'invitation_code',invite_row.invitation_code,'email',invite_row.email,'full_name',invite_row.full_name,
                     'role_code',invite_row.requested_role_code,'expires_at',invite_row.expires_at,'redirect_url',invite_row.redirect_url,'requires_token_delivery',true),
  'communication_engine','onboarding_invitation',invite_row.id,20,'onboarding-invitation-created:'||invite_row.id::text,invite_row.id::text,null,now());
 return jsonb_build_object('invitation_id',invite_row.id,'invitation_code',invite_row.invitation_code,'tenant_member_id',member_row.id,'organization_id',p_organization_id,
                           'email',invite_row.email,'role_code',invite_row.requested_role_code,'expires_at',invite_row.expires_at,'invitation_token',raw_token);
end;
$$;

create or replace function public.accept_onboarding_invitation(p_invitation_token text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare hashed_token text; invite_row public.onboarding_invitations; member_row public.onboarding_tenant_members;
begin
 if auth.uid() is null then raise exception 'Authentication is required'; end if;
 hashed_token:=encode(digest(p_invitation_token,'sha256'),'hex');
 select * into invite_row from public.onboarding_invitations where token_hash=hashed_token and status in('pending','sent','delivered') for update;
 if not found then raise exception 'Invitation is invalid or no longer available'; end if;
 if invite_row.expires_at<=now() then
  update public.onboarding_invitations set status='expired',updated_at=now() where id=invite_row.id;
  raise exception 'Invitation has expired';
 end if;
 update public.onboarding_tenant_members
 set user_id=auth.uid(),status='pending_auth',joined_at=coalesce(joined_at,now()),access_provisioning_status='queued',updated_by=auth.uid(),updated_at=now()
 where id=invite_row.tenant_member_id returning * into member_row;
 update public.onboarding_invitations set status='accepted',accepted_at=now(),accepted_by_user_id=auth.uid(),updated_at=now() where id=invite_row.id returning * into invite_row;
 perform public.publish_onboarding_event(invite_row.organization_id,invite_row.onboarding_request_id,'onboarding.invitation.accepted',
  jsonb_build_object('invitation_id',invite_row.id,'tenant_member_id',member_row.id,'organization_id',member_row.organization_id,'user_id',auth.uid(),
                     'role_code',member_row.requested_role_code,'email',member_row.email),
  'service_worker','onboarding_tenant_member',member_row.id,10,'onboarding-invitation-accepted:'||invite_row.id::text,invite_row.id::text,null,now());
 return jsonb_build_object('accepted',true,'organization_id',member_row.organization_id,'tenant_member_id',member_row.id,'user_id',auth.uid(),
                           'role_code',member_row.requested_role_code,'access_provisioning_status',member_row.access_provisioning_status);
end;
$$;

-- ============================================================
-- 15. Workspace initialization
-- ============================================================

create or replace function public.initialize_onboarding_checklist(
 p_onboarding_request_id uuid,
 p_organization_id uuid
)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare request_row public.tenant_onboarding_requests; inserted_count integer;
begin
 select * into request_row from public.tenant_onboarding_requests where id=p_onboarding_request_id;
 if not found then raise exception 'Onboarding request not found'; end if;
 insert into public.onboarding_checklist_items(
  organization_id,onboarding_request_id,template_step_id,item_code,item_name,description,category,sequence_number,required,blocking,dependency_item_codes,
  owner_type,status,progress_percentage,metadata
 )
 select p_organization_id,request_row.id,s.id,s.step_code,s.step_name,s.description,s.step_category,s.sequence_number,s.required,s.blocking,s.dependency_step_codes,
        s.owner_type,case when cardinality(s.dependency_step_codes)=0 then 'available' else 'pending' end,0,
        jsonb_build_object('execution_mode',s.execution_mode,'target_module',s.target_module,'target_action',s.target_action,
                           'validation_rule',s.validation_rule,'form_schema',s.form_schema,'default_data',s.default_data)
 from public.onboarding_template_steps s
 where s.template_id=request_row.template_id and s.status='active'
 on conflict(onboarding_request_id,item_code) do nothing;
 get diagnostics inserted_count=row_count;
 return inserted_count;
end;
$$;

create or replace function public.initialize_onboarding_activation_checks(
 p_onboarding_request_id uuid,
 p_organization_id uuid
)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare inserted_count integer;
begin
 insert into public.onboarding_activation_checks(
  organization_id,onboarding_request_id,check_code,check_name,description,check_category,required,blocking,validation_mode,status,score_weight,failure_remediation,metadata
 )
 select p_organization_id,p_onboarding_request_id,s.check_code,s.check_name,s.description,s.category,s.required,s.blocking,s.mode,'pending',s.weight,s.remediation,
        jsonb_build_object('seeded_by','initialize_onboarding_activation_checks')
 from (values
  ('organization_profile','Organization profile','Legal, contact and workspace details are configured','company',true,true,'automatic',1.0::numeric,'Complete the organization profile'),
  ('primary_admin','Primary administrator','An authenticated primary administrator is linked','members',true,true,'automatic',1.5::numeric,'Accept the owner invitation and provision RBAC access'),
  ('billing_subscription','Billing subscription','A trial or active subscription is available','billing',true,true,'automatic',1.0::numeric,'Activate a subscription or trial'),
  ('default_branch','Default branch','At least one active branch exists','workspace',true,true,'automatic',0.5::numeric,'Create a head-office branch'),
  ('business_hours','Business hours','Working hours are configured','workspace',true,false,'automatic',0.5::numeric,'Configure business hours'),
  ('security_baseline','Security baseline','Required security controls are provisioned','security',true,true,'worker',1.0::numeric,'Complete security baseline provisioning'),
  ('communication_channel','Communication channel','At least one communication channel is ready','communication',false,false,'worker',0.5::numeric,'Connect WhatsApp, email or SMS'),
  ('automation_ready','Automation readiness','Core lead workflow is enabled','automation',false,false,'worker',0.5::numeric,'Enable the default lead automation'),
  ('lead_source_ready','Lead source','At least one lead source or form is configured','data',false,false,'manual',0.5::numeric,'Configure Meta, Google, website or WhatsApp lead capture'),
  ('training_completed','Admin training','Primary administrator completed quick-start training','training',false,false,'manual',0.5::numeric,'Complete quick-start training')
 ) s(check_code,check_name,description,category,required,blocking,mode,weight,remediation)
 on conflict(onboarding_request_id,check_code) do nothing;
 get diagnostics inserted_count=row_count;
 return inserted_count;
end;
$$;

create or replace function public.create_default_onboarding_workspace(
 p_onboarding_request_id uuid,
 p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare request_row public.tenant_onboarding_requests; branch_row public.admin_branches; department_row public.admin_departments; team_row public.admin_teams;
begin
 select * into request_row from public.tenant_onboarding_requests where id=p_onboarding_request_id;
 if not found then raise exception 'Onboarding request not found'; end if;
 insert into public.admin_organization_profiles(
  organization_id,legal_name,trade_name,short_name,organization_code,industry,sub_industry,primary_email,primary_phone,website_url,
  headquarters_address,billing_address,timezone,locale,default_currency,default_country_code,status,metadata,created_by,updated_by
 ) values(
  p_organization_id,coalesce(request_row.legal_name,request_row.organization_name),coalesce(request_row.trade_name,request_row.organization_name),request_row.organization_name,
  upper(substr(replace(p_organization_id::text,'-',''),1,10)),request_row.industry,request_row.sub_industry,request_row.owner_email,request_row.owner_phone,request_row.website_url,
  jsonb_build_object('city',request_row.city,'state_code',request_row.state_code,'country_code',request_row.country_code),
  jsonb_build_object('city',request_row.city,'state_code',request_row.state_code,'country_code',request_row.country_code),
  request_row.timezone,request_row.locale,request_row.currency,request_row.country_code,'active',jsonb_build_object('onboarding_request_id',request_row.id),auth.uid(),auth.uid()
 ) on conflict(organization_id) do update set
  legal_name=excluded.legal_name,trade_name=excluded.trade_name,short_name=excluded.short_name,industry=excluded.industry,sub_industry=excluded.sub_industry,
  primary_email=excluded.primary_email,primary_phone=excluded.primary_phone,website_url=excluded.website_url,headquarters_address=excluded.headquarters_address,
  billing_address=excluded.billing_address,timezone=excluded.timezone,locale=excluded.locale,default_currency=excluded.default_currency,
  default_country_code=excluded.default_country_code,metadata=public.admin_organization_profiles.metadata||excluded.metadata,updated_by=auth.uid(),updated_at=now();

 insert into public.admin_branches(
  organization_id,branch_code,branch_name,branch_type,email,phone,address,timezone,status,metadata,created_by,updated_by
 ) values(
  p_organization_id,'HEAD_OFFICE','Head Office','head_office',request_row.owner_email,request_row.owner_phone,
  jsonb_build_object('city',request_row.city,'state_code',request_row.state_code,'country_code',request_row.country_code),request_row.timezone,'active',
  jsonb_build_object('onboarding_request_id',request_row.id),auth.uid(),auth.uid()
 ) on conflict(organization_id,branch_code) do update set
  branch_name=excluded.branch_name,email=excluded.email,phone=excluded.phone,address=excluded.address,timezone=excluded.timezone,status='active',
  metadata=public.admin_branches.metadata||excluded.metadata,updated_by=auth.uid(),updated_at=now()
 returning * into branch_row;

 insert into public.admin_departments(
  organization_id,branch_id,department_code,department_name,description,status,metadata,created_by,updated_by
 ) values(
  p_organization_id,branch_row.id,'SALES','Sales','Default SalesSetu sales department','active',jsonb_build_object('onboarding_request_id',request_row.id),auth.uid(),auth.uid()
 ) on conflict(organization_id,department_code) do update set
  branch_id=excluded.branch_id,department_name=excluded.department_name,status='active',metadata=public.admin_departments.metadata||excluded.metadata,
  updated_by=auth.uid(),updated_at=now()
 returning * into department_row;

 insert into public.admin_teams(
  organization_id,branch_id,department_id,team_code,team_name,team_type,status,metadata,created_by,updated_by
 ) values(
  p_organization_id,branch_row.id,department_row.id,'PRIMARY_SALES','Primary Sales Team','sales','active',jsonb_build_object('onboarding_request_id',request_row.id),auth.uid(),auth.uid()
 ) on conflict(organization_id,team_code) do update set
  branch_id=excluded.branch_id,department_id=excluded.department_id,team_name=excluded.team_name,status='active',metadata=public.admin_teams.metadata||excluded.metadata,
  updated_by=auth.uid(),updated_at=now()
 returning * into team_row;

 insert into public.admin_system_preferences(
  organization_id,preference_group,preference_key,preference_value,is_sensitive,editable_by_tenant,status,metadata,created_by,updated_by
 ) values
  (p_organization_id,'localization','timezone',to_jsonb(request_row.timezone),false,true,'active',jsonb_build_object('source','onboarding'),auth.uid(),auth.uid()),
  (p_organization_id,'localization','locale',to_jsonb(request_row.locale),false,true,'active',jsonb_build_object('source','onboarding'),auth.uid(),auth.uid()),
  (p_organization_id,'finance','currency',to_jsonb(request_row.currency),false,true,'active',jsonb_build_object('source','onboarding'),auth.uid(),auth.uid()),
  (p_organization_id,'lead_management','default_country_code',to_jsonb(request_row.country_code),false,true,'active',jsonb_build_object('source','onboarding'),auth.uid(),auth.uid())
 on conflict(organization_id,preference_group,preference_key) do update set
  preference_value=excluded.preference_value,status='active',metadata=public.admin_system_preferences.metadata||excluded.metadata,updated_by=auth.uid(),updated_at=now();

 insert into public.admin_business_hours(
  organization_id,branch_id,day_of_week,is_working_day,start_time,end_time,break_start,break_end,timezone,status,metadata
 )
 select p_organization_id,branch_row.id,d.day_of_week,d.is_working_day,d.start_time,d.end_time,d.break_start,d.break_end,request_row.timezone,'active',jsonb_build_object('source','onboarding')
 from (values
  (0,false,null::time,null::time,null::time,null::time),
  (1,true,time '09:30',time '18:30',time '13:30',time '14:00'),
  (2,true,time '09:30',time '18:30',time '13:30',time '14:00'),
  (3,true,time '09:30',time '18:30',time '13:30',time '14:00'),
  (4,true,time '09:30',time '18:30',time '13:30',time '14:00'),
  (5,true,time '09:30',time '18:30',time '13:30',time '14:00'),
  (6,true,time '10:00',time '17:00',time '13:30',time '14:00')
 ) d(day_of_week,is_working_day,start_time,end_time,break_start,break_end)
 on conflict(organization_id,branch_id,day_of_week) do update set
  is_working_day=excluded.is_working_day,start_time=excluded.start_time,end_time=excluded.end_time,break_start=excluded.break_start,break_end=excluded.break_end,
  timezone=excluded.timezone,status='active',metadata=public.admin_business_hours.metadata||excluded.metadata,updated_at=now();

 return jsonb_build_object('organization_id',p_organization_id,'branch_id',branch_row.id,'department_id',department_row.id,'team_id',team_row.id);
end;
$$;

create or replace function public.create_onboarding_owner_member(
 p_onboarding_request_id uuid,
 p_organization_id uuid
)
returns public.onboarding_tenant_members
language plpgsql
security definer
set search_path=''
as $$
declare request_row public.tenant_onboarding_requests; role_row public.roles; member_row public.onboarding_tenant_members;
begin
 select * into request_row from public.tenant_onboarding_requests where id=p_onboarding_request_id;
 if not found then raise exception 'Onboarding request not found'; end if;
 select * into role_row from public.roles where code='organization_admin' limit 1;
 insert into public.onboarding_tenant_members(
  organization_id,onboarding_request_id,user_id,member_code,email,full_name,phone,role_id,requested_role_code,member_type,status,is_owner,is_primary_admin,
  invited_at,joined_at,access_provisioning_status,metadata,created_by,updated_by
 ) values(
  p_organization_id,request_row.id,request_row.requested_by_user_id,'OWNER',request_row.owner_email,request_row.owner_full_name,request_row.owner_phone,role_row.id,
  'organization_admin','owner',case when request_row.requested_by_user_id is null then 'invited' else 'pending_auth' end,true,true,now(),
  case when request_row.requested_by_user_id is not null then now() end,'queued',jsonb_build_object('onboarding_request_id',request_row.id),auth.uid(),auth.uid()
 ) on conflict(organization_id,member_code) do update set
  user_id=coalesce(public.onboarding_tenant_members.user_id,excluded.user_id),email=excluded.email,full_name=excluded.full_name,phone=excluded.phone,role_id=excluded.role_id,
  requested_role_code=excluded.requested_role_code,status=excluded.status,is_owner=true,is_primary_admin=true,
  metadata=public.onboarding_tenant_members.metadata||excluded.metadata,updated_by=auth.uid(),updated_at=now()
 returning * into member_row;
 return member_row;
end;
$$;

create or replace function public.provision_onboarding_billing(
 p_onboarding_request_id uuid,
 p_organization_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare request_row public.tenant_onboarding_requests; customer_row public.billing_customers; subscription_row public.billing_subscriptions; price_row public.billing_plan_prices;
begin
 select * into request_row from public.tenant_onboarding_requests where id=p_onboarding_request_id;
 if not found then raise exception 'Onboarding request not found'; end if;
 select price.* into price_row
 from public.billing_plan_prices price
 join public.billing_plans plan on plan.id=price.plan_id
 join public.billing_products product on product.id=plan.product_id
 where product.product_code='salessetu' and plan.plan_code=request_row.preferred_plan_code and price.price_code=request_row.preferred_price_code
   and price.status='active' and plan.status='active' and (price.organization_id is null or price.organization_id=p_organization_id)
 order by case when price.organization_id=p_organization_id then 0 else 1 end limit 1;
 if not found then raise exception 'Billing price not found for plan % and price %',request_row.preferred_plan_code,request_row.preferred_price_code; end if;
 select * into customer_row from public.billing_customers where organization_id=p_organization_id and customer_code='TENANT' limit 1;
 if not found then
  customer_row:=public.create_billing_customer(
   p_organization_id,request_row.organization_name,request_row.owner_email,request_row.owner_phone,
   coalesce(request_row.legal_name,request_row.organization_name),request_row.owner_email,request_row.owner_phone,
   request_row.currency,request_row.country_code,request_row.state_code,
   jsonb_build_object('city',request_row.city,'state_code',request_row.state_code,'country_code',request_row.country_code),
   null,null,jsonb_build_object('onboarding_request_id',request_row.id,'customer_role','tenant')
  );
  update public.billing_customers set customer_code='TENANT',updated_at=now() where id=customer_row.id returning * into customer_row;
 end if;
 select * into subscription_row from public.billing_subscriptions
 where organization_id=p_organization_id and is_primary=true and status in('incomplete','trialing','active','past_due','grace','paused','suspended')
 order by created_at desc limit 1;
 if not found then
  subscription_row:=public.start_billing_subscription(
   p_organization_id,customer_row.id,price_row.id,1,null,null,request_row.requested_trial_days,'automatic',null,true,
   jsonb_build_object('onboarding_request_id',request_row.id,'expected_users',request_row.expected_users,'expected_monthly_leads',request_row.expected_monthly_leads)
  );
 end if;
 return jsonb_build_object('billing_customer_id',customer_row.id,'subscription_id',subscription_row.id,'subscription_status',subscription_row.status,
                           'trial_ends_at',subscription_row.trial_ends_at,'plan_id',subscription_row.plan_id,'plan_price_id',subscription_row.plan_price_id);
end;
$$;

-- ============================================================
-- 16. Tenant provisioning orchestration
-- ============================================================

create or replace function public.provision_tenant_onboarding(
 p_onboarding_request_id uuid,
 p_idempotency_key text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare request_row public.tenant_onboarding_requests; organization_row public.organizations; owner_row public.onboarding_tenant_members; run_row public.onboarding_provisioning_runs;
        unique_slug text; workspace_result jsonb; billing_result jsonb; invitation_result jsonb;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may provision a tenant'; end if;
 select * into request_row from public.tenant_onboarding_requests where id=p_onboarding_request_id for update;
 if not found then raise exception 'Onboarding request not found'; end if;
 if request_row.status in('provisioned','activation_pending','active') and request_row.organization_id is not null then
  return jsonb_build_object('already_provisioned',true,'request_id',request_row.id,'organization_id',request_row.organization_id,'status',request_row.status);
 end if;
 if request_row.status not in('approved','provisioning') then raise exception 'Request is not approved for provisioning'; end if;
 if request_row.approval_status not in('approved','not_required') then raise exception 'Onboarding approval is not complete'; end if;
 unique_slug:=public.generate_unique_onboarding_slug(request_row.requested_slug,request_row.organization_name);
 update public.tenant_onboarding_requests set status='provisioning',provisioning_started_at=coalesce(provisioning_started_at,now()),provisioned_slug=unique_slug,updated_at=now()
 where id=request_row.id returning * into request_row;
 insert into public.onboarding_provisioning_runs(
  onboarding_request_id,run_code,run_type,status,started_at,initiated_by,idempotency_key,correlation_id,trace_id,metadata
 ) values(
  request_row.id,'PRV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),case when request_row.provisioning_started_at is null then 'initial' else 'retry' end,
  'running',now(),auth.uid(),p_idempotency_key,request_row.correlation_id,request_row.trace_id,jsonb_build_object('provisioned_slug',unique_slug)
 ) returning * into run_row;
 begin
  insert into public.organizations(name,slug,organization_type,status)
  values(request_row.organization_name,unique_slug,request_row.tenant_type,'active') returning * into organization_row;
  update public.tenant_onboarding_requests set organization_id=organization_row.id,provisioned_slug=organization_row.slug,updated_at=now()
  where id=request_row.id returning * into request_row;
  update public.onboarding_request_contacts set organization_id=organization_row.id,updated_at=now() where onboarding_request_id=request_row.id;
  update public.onboarding_approvals set organization_id=organization_row.id,updated_at=now() where onboarding_request_id=request_row.id;
  update public.onboarding_provisioning_runs set organization_id=organization_row.id,updated_at=now() where id=run_row.id returning * into run_row;
  workspace_result:=public.create_default_onboarding_workspace(request_row.id,organization_row.id);
  owner_row:=public.create_onboarding_owner_member(request_row.id,organization_row.id);
  billing_result:=public.provision_onboarding_billing(request_row.id,organization_row.id);
  perform public.initialize_onboarding_checklist(request_row.id,organization_row.id);
  perform public.initialize_onboarding_activation_checks(request_row.id,organization_row.id);

  insert into public.onboarding_workspace_settings(organization_id,onboarding_request_id,setting_group,setting_key,setting_value,source,status,metadata,created_by,updated_by)
  values
   (organization_row.id,request_row.id,'tenant','type',to_jsonb(request_row.tenant_type),'onboarding','active','{}',auth.uid(),auth.uid()),
   (organization_row.id,request_row.id,'tenant','onboarding_request_id',to_jsonb(request_row.id::text),'onboarding','active','{}',auth.uid(),auth.uid()),
   (organization_row.id,request_row.id,'workspace','preferences',request_row.workspace_preferences,'tenant','active','{}',auth.uid(),auth.uid()),
   (organization_row.id,request_row.id,'integrations','preferences',request_row.integration_preferences,'tenant','active','{}',auth.uid(),auth.uid())
  on conflict(organization_id,setting_group,setting_key) do update set setting_value=excluded.setting_value,source=excluded.source,status='active',updated_by=auth.uid(),updated_at=now();

  insert into public.onboarding_provisioning_tasks(
   provisioning_run_id,onboarding_request_id,organization_id,task_code,task_name,task_type,handler_code,destination,sequence_number,priority,
   dependency_task_codes,required,blocking,status,input_data,idempotency_key,correlation_id,trace_id
  )
  select run_row.id,request_row.id,organization_row.id,s.task_code,s.task_name,s.task_type,s.handler_code,s.destination,s.sequence_number,s.priority,s.dependencies,
         s.required,s.blocking,'queued',s.input_data||jsonb_build_object('organization_id',organization_row.id,'onboarding_request_id',request_row.id,'owner_member_id',owner_row.id),
         'onboarding-task:'||run_row.id::text||':'||s.task_code,request_row.correlation_id,request_row.trace_id
  from (values
   ('AUTH_OWNER','Provision owner authentication and access','auth','onboarding.auth.provision_owner','service_worker',10,10,'{}'::text[],true,true,
    jsonb_build_object('email',request_row.owner_email,'full_name',request_row.owner_full_name,'role_code','organization_admin')),
   ('RBAC_OWNER','Bind organization administrator role','rbac','onboarding.rbac.bind_owner','service_worker',20,10,array['AUTH_OWNER']::text[],true,true,
    jsonb_build_object('role_code','organization_admin')),
   ('SECURITY_BASELINE','Apply tenant security baseline','security','onboarding.security.apply_baseline','security_governance',30,20,array['RBAC_OWNER']::text[],true,true,
    request_row.security_preferences),
   ('COMMUNICATION_SETUP','Prepare communication channels','communication','onboarding.communication.prepare','communication_engine',40,50,array['RBAC_OWNER']::text[],false,false,
    request_row.integration_preferences),
   ('AUTOMATION_SETUP','Enable default lead automation','configuration','onboarding.automation.prepare','automation_engine',50,50,array['RBAC_OWNER']::text[],false,false,
    jsonb_build_object('tenant_type',request_row.tenant_type)),
   ('WELCOME_COMMUNICATION','Send owner welcome and setup guidance','external','onboarding.communication.welcome','communication_engine',60,50,array['AUTH_OWNER']::text[],true,false,
    jsonb_build_object('email',request_row.owner_email,'full_name',request_row.owner_full_name)),
   ('ACTIVATION_EVALUATION','Evaluate tenant activation readiness','activation','onboarding.activation.evaluate','service_worker',100,100,array['RBAC_OWNER','SECURITY_BASELINE']::text[],true,true,'{}'::jsonb)
  ) s(task_code,task_name,task_type,handler_code,destination,sequence_number,priority,dependencies,required,blocking,input_data)
  on conflict(provisioning_run_id,task_code) do nothing;

  update public.onboarding_provisioning_runs
  set total_tasks=(select count(*) from public.onboarding_provisioning_tasks t where t.provisioning_run_id=run_row.id),status='waiting',updated_at=now()
  where id=run_row.id returning * into run_row;

  if request_row.requested_by_user_id is null then
   invitation_result:=public.create_onboarding_invitation(
    organization_row.id,request_row.id,request_row.owner_email,request_row.owner_full_name,request_row.owner_phone,'organization_admin','owner',7,null,
    jsonb_build_object('is_owner',true,'is_primary_admin',true)
   );
  else
   invitation_result:=jsonb_build_object('not_required',true,'user_id',request_row.requested_by_user_id);
  end if;

  update public.tenant_onboarding_requests set status='activation_pending',provisioned_at=now(),failure_code=null,failure_message=null,failure_data='{}',updated_at=now()
  where id=request_row.id returning * into request_row;
  insert into public.onboarding_progress_events(
   organization_id,onboarding_request_id,event_name,previous_status,new_status,progress_percentage,actor_user_id,actor_type,event_data,correlation_id,trace_id
  ) values(
   organization_row.id,request_row.id,'onboarding.tenant.provisioned','provisioning','activation_pending',35,auth.uid(),'service_role',
   jsonb_build_object('workspace',workspace_result,'billing',billing_result,'owner_invitation',invitation_result,'provisioning_run_id',run_row.id),
   request_row.correlation_id,request_row.trace_id
  );
  perform public.publish_onboarding_event(
   organization_row.id,request_row.id,'onboarding.tenant.provisioned',
   jsonb_build_object('request_id',request_row.id,'organization_id',organization_row.id,'slug',organization_row.slug,'owner_member_id',owner_row.id,
                      'provisioning_run_id',run_row.id,'billing',billing_result),
   'enterprise_workflow','tenant_onboarding_request',request_row.id,20,'onboarding-tenant-provisioned:'||request_row.id::text,
   request_row.correlation_id,request_row.trace_id,now()
  );
  return jsonb_build_object('request_id',request_row.id,'organization_id',organization_row.id,'organization_slug',organization_row.slug,
                            'owner_member_id',owner_row.id,'provisioning_run_id',run_row.id,'workspace',workspace_result,'billing',billing_result,
                            'owner_invitation',invitation_result,'status',request_row.status);
 exception when others then
  update public.tenant_onboarding_requests set status='failed',failure_code=sqlstate,failure_message=sqlerrm,
         failure_data=jsonb_build_object('provisioning_run_id',run_row.id),updated_at=now() where id=request_row.id;
  update public.onboarding_provisioning_runs set status='failed',failed_at=now(),failure_code=sqlstate,failure_message=sqlerrm,updated_at=now() where id=run_row.id;
  insert into public.onboarding_logs(organization_id,onboarding_request_id,log_level,event_name,message,source_type,source_id,actor_user_id,error_code,error_message,log_data,correlation_id,trace_id)
  values(case when organization_row.id is null then null else organization_row.id end,request_row.id,'critical','onboarding.provisioning.failed','Tenant provisioning failed',
         'onboarding_provisioning_run',run_row.id,auth.uid(),sqlstate,sqlerrm,jsonb_build_object('request_code',request_row.request_code,'requested_slug',unique_slug),
         request_row.correlation_id,request_row.trace_id);
  raise;
 end;
end;
$$;

-- ============================================================
-- 17. Member access completion
-- ============================================================

create or replace function public.complete_onboarding_member_access(
 p_tenant_member_id uuid,
 p_success boolean,
 p_failure_message text default null,
 p_access_data jsonb default '{}'::jsonb
)
returns public.onboarding_tenant_members
language plpgsql
security definer
set search_path=''
as $$
declare member_row public.onboarding_tenant_members; request_row public.tenant_onboarding_requests;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may complete member access provisioning'; end if;
 update public.onboarding_tenant_members
 set status=case when p_success then 'active' else 'pending_auth' end,
     access_provisioned_at=case when p_success then now() else access_provisioned_at end,
     access_provisioning_status=case when p_success then 'provisioned' else 'failed' end,
     access_failure_message=case when p_success then null else p_failure_message end,
     metadata=metadata||coalesce(p_access_data,'{}'::jsonb),updated_at=now()
 where id=p_tenant_member_id returning * into member_row;
 if not found then raise exception 'Tenant member not found'; end if;
 if p_success and member_row.user_id is not null then
  select * into request_row from public.tenant_onboarding_requests where id=member_row.onboarding_request_id;
  insert into public.admin_employees(
   organization_id,user_id,employee_code,full_name,work_email,phone,branch_id,department_id,team_id,employment_type,employment_status,date_of_joining,
   timezone,locale,sales_capacity,daily_lead_capacity,metadata,created_by,updated_by
  )
  select member_row.organization_id,member_row.user_id,case when member_row.is_owner then 'OWNER' else 'EMP-'||upper(substr(replace(member_row.id::text,'-',''),1,12)) end,
         coalesce(member_row.full_name,member_row.email),member_row.email,member_row.phone,b.id,d.id,t.id,'full_time','active',current_date,
         coalesce(request_row.timezone,'Asia/Kolkata'),coalesce(request_row.locale,'en-IN'),case when member_row.requested_role_code='sales_agent' then 50 else 0 end,
         case when member_row.requested_role_code='sales_agent' then 20 else 0 end,
         jsonb_build_object('onboarding_tenant_member_id',member_row.id,'role_code',member_row.requested_role_code),auth.uid(),auth.uid()
  from lateral(
   select id from public.admin_branches where organization_id=member_row.organization_id and status='active'
   order by case when branch_type='head_office' then 0 else 1 end,created_at limit 1
  ) b
  left join lateral(
   select id from public.admin_departments where organization_id=member_row.organization_id and status='active'
   order by case when department_code='SALES' then 0 else 1 end,created_at limit 1
  ) d on true
  left join lateral(
   select id from public.admin_teams where organization_id=member_row.organization_id and status='active'
   order by case when team_code='PRIMARY_SALES' then 0 else 1 end,created_at limit 1
  ) t on true
  where not exists(select 1 from public.admin_employees e where e.organization_id=member_row.organization_id and e.user_id=member_row.user_id);
 end if;
 return member_row;
end;
$$;

-- ============================================================
-- 18. Checklist and activation
-- ============================================================

create or replace function public.complete_onboarding_checklist_item(
 p_checklist_item_id uuid,
 p_status text default 'completed',
 p_completion_notes text default null,
 p_completion_data jsonb default '{}'::jsonb,
 p_validation_status text default 'passed',
 p_validation_message text default null,
 p_validation_data jsonb default '{}'::jsonb
)
returns public.onboarding_checklist_items
language plpgsql
security definer
set search_path=''
as $$
declare item_row public.onboarding_checklist_items; dependency_code text;
begin
 select * into item_row from public.onboarding_checklist_items where id=p_checklist_item_id for update;
 if not found then raise exception 'Onboarding checklist item not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(item_row.organization_id,'onboarding.manage_checklists') then raise exception 'Permission denied'; end if;
 if p_status not in('completed','skipped','failed','cancelled') then raise exception 'Unsupported checklist completion status'; end if;
 foreach dependency_code in array item_row.dependency_item_codes loop
  if not exists(
   select 1 from public.onboarding_checklist_items d
   where d.onboarding_request_id=item_row.onboarding_request_id and d.item_code=dependency_code and d.status in('completed','skipped')
  ) then raise exception 'Dependency checklist item % is not complete',dependency_code; end if;
 end loop;
 update public.onboarding_checklist_items
 set status=p_status,progress_percentage=case when p_status in('completed','skipped') then 100 else progress_percentage end,
     started_at=coalesce(started_at,now()),completed_at=now(),completed_by=auth.uid(),completion_notes=p_completion_notes,
     completion_data=coalesce(p_completion_data,'{}'::jsonb),validation_status=p_validation_status,validation_message=p_validation_message,
     validation_data=coalesce(p_validation_data,'{}'::jsonb),updated_at=now()
 where id=item_row.id returning * into item_row;
 update public.onboarding_checklist_items child
 set status='available',updated_at=now()
 where child.onboarding_request_id=item_row.onboarding_request_id and child.status='pending'
   and not exists(
    select 1 from unnest(child.dependency_item_codes) dep_code
    where not exists(
     select 1 from public.onboarding_checklist_items dep
     where dep.onboarding_request_id=child.onboarding_request_id and dep.item_code=dep_code and dep.status in('completed','skipped')
    )
   );
 insert into public.onboarding_progress_events(organization_id,onboarding_request_id,checklist_item_id,event_name,new_status,progress_percentage,actor_user_id,actor_type,event_data)
 values(item_row.organization_id,item_row.onboarding_request_id,item_row.id,'onboarding.checklist.'||p_status,p_status,item_row.progress_percentage,auth.uid(),
        case when auth.role()='service_role' then 'service_role' else 'user' end,
        jsonb_build_object('item_code',item_row.item_code,'validation_status',item_row.validation_status));
 return item_row;
end;
$$;

create or replace function public.set_onboarding_activation_check(
 p_activation_check_id uuid,
 p_status text,
 p_result_message text default null,
 p_result_data jsonb default '{}'::jsonb,
 p_failure_remediation text default null
)
returns public.onboarding_activation_checks
language plpgsql
security definer
set search_path=''
as $$
declare check_row public.onboarding_activation_checks;
begin
 select * into check_row from public.onboarding_activation_checks where id=p_activation_check_id for update;
 if not found then raise exception 'Activation check not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(check_row.organization_id,'onboarding.manage_activation') then raise exception 'Permission denied'; end if;
 if p_status not in('pending','checking','passed','failed','warning','waived','not_applicable') then raise exception 'Invalid activation-check status'; end if;
 update public.onboarding_activation_checks
 set status=p_status,checked_at=now(),checked_by=auth.uid(),result_message=p_result_message,result_data=coalesce(p_result_data,'{}'::jsonb),
     failure_remediation=coalesce(p_failure_remediation,failure_remediation),updated_at=now()
 where id=check_row.id returning * into check_row;
 return check_row;
end;
$$;

create or replace function public.evaluate_onboarding_activation_checks(p_onboarding_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare request_row public.tenant_onboarding_requests; c public.onboarding_activation_checks;
        required_total integer; required_passed integer; blocking_failed integer; total_weight numeric; passed_weight numeric; readiness numeric;
begin
 select * into request_row from public.tenant_onboarding_requests where id=p_onboarding_request_id;
 if not found then raise exception 'Onboarding request not found'; end if;
 if request_row.organization_id is null then raise exception 'Tenant has not been provisioned'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(request_row.organization_id,'onboarding.manage_activation') then raise exception 'Permission denied'; end if;
 for c in select * from public.onboarding_activation_checks where onboarding_request_id=request_row.id and validation_mode='automatic' loop
  update public.onboarding_activation_checks
  set status=case c.check_code
    when 'organization_profile' then case when exists(select 1 from public.admin_organization_profiles p where p.organization_id=request_row.organization_id and p.status='active') then 'passed' else 'failed' end
    when 'primary_admin' then case when exists(select 1 from public.onboarding_tenant_members m where m.organization_id=request_row.organization_id and m.is_primary_admin and m.user_id is not null and m.status='active' and m.access_provisioning_status='provisioned') then 'passed' else 'failed' end
    when 'billing_subscription' then case when exists(select 1 from public.billing_subscriptions s where s.organization_id=request_row.organization_id and s.is_primary and s.status in('trialing','active','grace')) then 'passed' else 'failed' end
    when 'default_branch' then case when exists(select 1 from public.admin_branches b where b.organization_id=request_row.organization_id and b.status='active') then 'passed' else 'failed' end
    when 'business_hours' then case when exists(select 1 from public.admin_business_hours h where h.organization_id=request_row.organization_id and h.status='active' and h.is_working_day) then 'passed' else 'failed' end
    else status end,
    checked_at=now(),checked_by=auth.uid(),result_message='Automatic onboarding readiness check completed',updated_at=now()
  where id=c.id;
 end loop;
 select count(*) filter(where required),count(*) filter(where required and status in('passed','waived','not_applicable')),
        count(*) filter(where blocking and status='failed'),coalesce(sum(score_weight),0),
        coalesce(sum(score_weight) filter(where status in('passed','waived','not_applicable')),0)
 into required_total,required_passed,blocking_failed,total_weight,passed_weight
 from public.onboarding_activation_checks where onboarding_request_id=request_row.id;
 readiness:=case when total_weight=0 then 0 else round(passed_weight/total_weight*100,2) end;
 return jsonb_build_object('onboarding_request_id',request_row.id,'organization_id',request_row.organization_id,'required_total',required_total,
                           'required_passed',required_passed,'blocking_failed',blocking_failed,'readiness_score',readiness,
                           'ready_for_activation',required_total=required_passed and blocking_failed=0,'evaluated_at',now());
end;
$$;

create or replace function public.activate_onboarded_tenant(
 p_onboarding_request_id uuid,
 p_activation_notes text default null,
 p_force boolean default false
)
returns public.tenant_onboarding_requests
language plpgsql
security definer
set search_path=''
as $$
declare request_row public.tenant_onboarding_requests; readiness jsonb; ready_flag boolean;
begin
 select * into request_row from public.tenant_onboarding_requests where id=p_onboarding_request_id for update;
 if not found then raise exception 'Onboarding request not found'; end if;
 if request_row.organization_id is null then raise exception 'Tenant has not been provisioned'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(request_row.organization_id,'onboarding.manage_activation') then raise exception 'Permission denied'; end if;
 readiness:=public.evaluate_onboarding_activation_checks(request_row.id);
 ready_flag:=coalesce((readiness->>'ready_for_activation')::boolean,false);
 if not ready_flag and not p_force then raise exception 'Tenant is not ready for activation: %',readiness::text; end if;
 update public.tenant_onboarding_requests
 set status='active',activated_at=now(),activated_by=auth.uid(),metadata=metadata||jsonb_build_object('activation_notes',p_activation_notes,'activation_readiness',readiness,'forced_activation',p_force),updated_at=now()
 where id=request_row.id returning * into request_row;
 update public.onboarding_provisioning_runs
 set status=case when failed_tasks>0 then 'partially_completed' else 'completed' end,completed_at=now(),progress_percentage=100,updated_at=now()
 where onboarding_request_id=request_row.id and status in('running','waiting');
 insert into public.onboarding_progress_events(organization_id,onboarding_request_id,event_name,previous_status,new_status,progress_percentage,actor_user_id,actor_type,event_data,correlation_id,trace_id)
 values(request_row.organization_id,request_row.id,'onboarding.tenant.activated','activation_pending','active',100,auth.uid(),
        case when auth.role()='service_role' then 'service_role' else 'user' end,
        jsonb_build_object('activation_notes',p_activation_notes,'readiness',readiness,'forced',p_force),request_row.correlation_id,request_row.trace_id);
 perform public.publish_onboarding_event(request_row.organization_id,request_row.id,'onboarding.tenant.activated',
  jsonb_build_object('request_id',request_row.id,'organization_id',request_row.organization_id,'organization_name',request_row.organization_name,
                     'slug',request_row.provisioned_slug,'activated_at',request_row.activated_at,'readiness',readiness),
  'communication_engine','tenant_onboarding_request',request_row.id,10,'onboarding-tenant-activated:'||request_row.id::text,
  request_row.correlation_id,request_row.trace_id,now());
 return request_row;
end;
$$;

-- ============================================================
-- 19. Provisioning task worker
-- ============================================================

create or replace function public.refresh_onboarding_provisioning_run(p_provisioning_run_id uuid)
returns public.onboarding_provisioning_runs
language plpgsql
security definer
set search_path=''
as $$
declare run_row public.onboarding_provisioning_runs; totals record;
begin
 select count(*) total_tasks,count(*) filter(where status='completed') completed_tasks,
        count(*) filter(where status in('failed','dead_lettered')) failed_tasks,count(*) filter(where status='skipped') skipped_tasks,
        count(*) filter(where status in('queued','claimed','running','waiting','failed')) pending_tasks,
        count(*) filter(where required and status='dead_lettered') required_dead_lettered
 into totals
 from public.onboarding_provisioning_tasks where provisioning_run_id=p_provisioning_run_id;
 update public.onboarding_provisioning_runs
 set total_tasks=totals.total_tasks,completed_tasks=totals.completed_tasks,failed_tasks=totals.failed_tasks,skipped_tasks=totals.skipped_tasks,
     progress_percentage=case when totals.total_tasks=0 then 0 else round((totals.completed_tasks+totals.skipped_tasks)::numeric/totals.total_tasks*100,2) end,
     status=case when totals.required_dead_lettered>0 then 'failed' when totals.pending_tasks=0 and totals.failed_tasks>0 then 'partially_completed'
                 when totals.pending_tasks=0 then 'completed' else 'waiting' end,
     completed_at=case when totals.pending_tasks=0 then coalesce(completed_at,now()) else completed_at end,
     failed_at=case when totals.required_dead_lettered>0 then coalesce(failed_at,now()) else failed_at end,updated_at=now()
 where id=p_provisioning_run_id returning * into run_row;
 return run_row;
end;
$$;

create or replace function public.claim_onboarding_provisioning_task(
 p_worker_id text,
 p_destination text default null,
 p_lock_seconds integer default 300
)
returns public.onboarding_provisioning_tasks
language plpgsql
security definer
set search_path=''
as $$
declare task_row public.onboarding_provisioning_tasks;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may claim provisioning tasks'; end if;
 update public.onboarding_provisioning_tasks
 set status='failed',available_at=now(),claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
     last_error_code=coalesce(last_error_code,'LOCK_EXPIRED'),last_error_message=coalesce(last_error_message,'Provisioning task lock expired'),updated_at=now()
 where status in('claimed','running') and lock_expires_at is not null and lock_expires_at<=now();
 select * into task_row
 from public.onboarding_provisioning_tasks t
 where t.status in('queued','failed') and t.available_at<=now() and t.attempt_count<t.maximum_attempts
   and (p_destination is null or t.destination=p_destination)
   and not exists(
    select 1 from unnest(t.dependency_task_codes) dep_code
    where not exists(
     select 1 from public.onboarding_provisioning_tasks dep
     where dep.provisioning_run_id=t.provisioning_run_id and dep.task_code=dep_code and dep.status in('completed','skipped')
    )
   )
 order by t.priority,t.sequence_number,t.created_at
 for update skip locked limit 1;
 if not found then return null; end if;
 update public.onboarding_provisioning_tasks
 set status='claimed',attempt_count=attempt_count+1,claimed_at=now(),claimed_by=p_worker_id,lock_token=gen_random_uuid()::text,
     lock_expires_at=now()+make_interval(secs=>greatest(p_lock_seconds,1)),started_at=coalesce(started_at,now()),updated_at=now()
 where id=task_row.id returning * into task_row;
 return task_row;
end;
$$;

create or replace function public.complete_onboarding_provisioning_task(
 p_task_id uuid,
 p_lock_token text,
 p_output_data jsonb default '{}'::jsonb,
 p_status text default 'completed'
)
returns public.onboarding_provisioning_tasks
language plpgsql
security definer
set search_path=''
as $$
declare task_row public.onboarding_provisioning_tasks;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may complete provisioning tasks'; end if;
 select * into task_row from public.onboarding_provisioning_tasks where id=p_task_id for update;
 if not found then raise exception 'Provisioning task not found'; end if;
 if task_row.lock_token is distinct from p_lock_token then raise exception 'Invalid provisioning task lock token'; end if;
 if p_status not in('completed','skipped','cancelled') then raise exception 'Invalid successful task status'; end if;
 update public.onboarding_provisioning_tasks
 set status=p_status,output_data=coalesce(p_output_data,'{}'::jsonb),completed_at=now(),claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
     last_error_code=null,last_error_message=null,last_error_data='{}',updated_at=now()
 where id=task_row.id returning * into task_row;
 perform public.refresh_onboarding_provisioning_run(task_row.provisioning_run_id);
 insert into public.onboarding_progress_events(organization_id,onboarding_request_id,provisioning_task_id,event_name,previous_status,new_status,actor_type,event_data,correlation_id,trace_id)
 values(task_row.organization_id,task_row.onboarding_request_id,task_row.id,'onboarding.provisioning_task.'||p_status,'claimed',p_status,'worker',
        coalesce(p_output_data,'{}'::jsonb),task_row.correlation_id,task_row.trace_id);
 return task_row;
end;
$$;

create or replace function public.fail_onboarding_provisioning_task(
 p_task_id uuid,
 p_lock_token text,
 p_error_code text,
 p_error_message text,
 p_error_data jsonb default '{}'::jsonb
)
returns public.onboarding_provisioning_tasks
language plpgsql
security definer
set search_path=''
as $$
declare task_row public.onboarding_provisioning_tasks; next_status text; retry_seconds integer;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may fail provisioning tasks'; end if;
 select * into task_row from public.onboarding_provisioning_tasks where id=p_task_id for update;
 if not found then raise exception 'Provisioning task not found'; end if;
 if task_row.lock_token is distinct from p_lock_token then raise exception 'Invalid provisioning task lock token'; end if;
 next_status:=case when task_row.attempt_count>=task_row.maximum_attempts then 'dead_lettered' else 'failed' end;
 retry_seconds:=least(3600,greatest(30,power(2,greatest(task_row.attempt_count,1))::integer*30));
 update public.onboarding_provisioning_tasks
 set status=next_status,available_at=case when next_status='failed' then now()+make_interval(secs=>retry_seconds) else available_at end,
     failed_at=now(),last_error_code=p_error_code,last_error_message=p_error_message,last_error_data=coalesce(p_error_data,'{}'::jsonb),
     claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
 where id=task_row.id returning * into task_row;
 perform public.refresh_onboarding_provisioning_run(task_row.provisioning_run_id);
 insert into public.onboarding_logs(organization_id,onboarding_request_id,log_level,event_name,message,source_type,source_id,error_code,error_message,log_data,correlation_id,trace_id)
 values(task_row.organization_id,task_row.onboarding_request_id,case when next_status='dead_lettered' then 'critical' else 'error' end,
        'onboarding.provisioning_task.'||next_status,'Provisioning task failed','onboarding_provisioning_task',task_row.id,p_error_code,p_error_message,
        coalesce(p_error_data,'{}'::jsonb),task_row.correlation_id,task_row.trace_id);
 return task_row;
end;
$$;

-- ============================================================
-- 20. Data import and domain requests
-- ============================================================

create or replace function public.create_onboarding_data_import_job(
 p_organization_id uuid,
 p_onboarding_request_id uuid,
 p_import_type text,
 p_source_type text,
 p_source_reference text default null,
 p_source_document_id uuid default null,
 p_mapping_configuration jsonb default '{}'::jsonb,
 p_validation_configuration jsonb default '{}'::jsonb,
 p_transformation_configuration jsonb default '{}'::jsonb,
 p_dry_run boolean default true,
 p_idempotency_key text default null,
 p_metadata jsonb default '{}'::jsonb
)
returns public.onboarding_data_import_jobs
language plpgsql
security definer
set search_path=''
as $$
declare existing_row public.onboarding_data_import_jobs; result_row public.onboarding_data_import_jobs;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'onboarding.manage_imports') then raise exception 'Permission denied'; end if;
 if p_idempotency_key is not null then
  select * into existing_row from public.onboarding_data_import_jobs where idempotency_key=p_idempotency_key limit 1;
  if found then return existing_row; end if;
 end if;
 insert into public.onboarding_data_import_jobs(
  organization_id,onboarding_request_id,import_code,import_type,source_type,source_reference,source_document_id,mapping_configuration,
  validation_configuration,transformation_configuration,status,dry_run,initiated_by,idempotency_key,correlation_id,metadata
 ) values(
  p_organization_id,p_onboarding_request_id,'IMP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),p_import_type,p_source_type,p_source_reference,
  p_source_document_id,coalesce(p_mapping_configuration,'{}'::jsonb),coalesce(p_validation_configuration,'{}'::jsonb),coalesce(p_transformation_configuration,'{}'::jsonb),
  case when p_source_reference is null and p_source_document_id is null then 'draft' else 'uploaded' end,p_dry_run,auth.uid(),p_idempotency_key,gen_random_uuid()::text,
  coalesce(p_metadata,'{}'::jsonb)
 ) returning * into result_row;
 return result_row;
end;
$$;

create or replace function public.request_onboarding_domain(
 p_organization_id uuid,
 p_onboarding_request_id uuid,
 p_domain_name text,
 p_domain_type text default 'custom',
 p_verification_method text default 'dns_txt',
 p_metadata jsonb default '{}'::jsonb
)
returns public.onboarding_domain_requests
language plpgsql
security definer
set search_path=''
as $$
declare result_row public.onboarding_domain_requests; token_value text;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'onboarding.manage_domains') then raise exception 'Permission denied'; end if;
 token_value:='salessetu-verification='||encode(gen_random_bytes(20),'hex');
 insert into public.onboarding_domain_requests(
  organization_id,onboarding_request_id,request_code,domain_name,domain_type,verification_method,verification_token,verification_record,
  verification_status,ssl_status,routing_status,status,metadata,requested_by
 ) values(
  p_organization_id,p_onboarding_request_id,'DOM-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),lower(trim(p_domain_name)),p_domain_type,
  p_verification_method,token_value,
  jsonb_build_object('type',case when p_verification_method='dns_cname' then 'CNAME' else 'TXT' end,
                     'name',case when p_verification_method='dns_cname' then lower(trim(p_domain_name)) else '_salessetu.'||lower(trim(p_domain_name)) end,
                     'value',token_value),
  'pending','pending','pending','requested',coalesce(p_metadata,'{}'::jsonb),auth.uid()
 ) returning * into result_row;
 perform public.publish_onboarding_event(p_organization_id,p_onboarding_request_id,'onboarding.domain.requested',
  jsonb_build_object('domain_request_id',result_row.id,'domain_name',result_row.domain_name,'domain_type',result_row.domain_type,
                     'verification_method',result_row.verification_method,'verification_record',result_row.verification_record),
  'integration_api','onboarding_domain_request',result_row.id,50,'onboarding-domain-requested:'||result_row.id::text,result_row.id::text,null,now());
 return result_row;
end;
$$;

-- ============================================================
-- 21. Analytics views
-- ============================================================

create or replace view public.onboarding_pipeline_dashboard
with (security_invoker=true)
as
select r.organization_id,r.tenant_type,r.preferred_plan_code,r.status,r.approval_status,
       count(*) request_count,
       count(*) filter(where r.created_at>=now()-interval '7 days') created_last_7d,
       count(*) filter(where r.created_at>=now()-interval '30 days') created_last_30d,
       count(*) filter(where r.status='active') activated_count,
       count(*) filter(where r.status='failed') failed_count,
       avg(extract(epoch from(coalesce(r.activated_at,r.provisioned_at,now())-r.created_at))/3600) average_elapsed_hours,
       min(r.created_at) oldest_request_at,max(r.updated_at) latest_update_at
from public.tenant_onboarding_requests r
group by r.organization_id,r.tenant_type,r.preferred_plan_code,r.status,r.approval_status;

create or replace view public.onboarding_progress_dashboard
with (security_invoker=true)
as
select r.id onboarding_request_id,r.organization_id,r.request_code,r.organization_name,r.tenant_type,r.status,
       count(c.id) checklist_item_count,
       count(c.id) filter(where c.status in('completed','skipped')) checklist_completed_count,
       count(c.id) filter(where c.required and c.status not in('completed','skipped')) required_remaining_count,
       count(c.id) filter(where c.blocking and c.status='failed') blocking_failed_count,
       round(coalesce(avg(case when c.status in('completed','skipped') then 100 else c.progress_percentage end),0),2) checklist_progress_percentage,
       max(c.updated_at) latest_checklist_update_at
from public.tenant_onboarding_requests r
left join public.onboarding_checklist_items c on c.onboarding_request_id=r.id
group by r.id,r.organization_id,r.request_code,r.organization_name,r.tenant_type,r.status;

create or replace view public.onboarding_task_dashboard
with (security_invoker=true)
as
select t.organization_id,t.provisioning_run_id,t.destination,t.task_type,t.status,
       count(*) task_count,count(*) filter(where t.required) required_task_count,
       count(*) filter(where t.status in('failed','dead_lettered')) failed_task_count,
       count(*) filter(where t.status in('claimed','running') and t.lock_expires_at<=now()) expired_lock_count,
       avg(t.attempt_count) average_attempt_count,
       min(t.available_at) filter(where t.status in('queued','failed')) next_available_at,
       max(t.updated_at) latest_update_at
from public.onboarding_provisioning_tasks t
group by t.organization_id,t.provisioning_run_id,t.destination,t.task_type,t.status;

create or replace view public.onboarding_activation_readiness_dashboard
with (security_invoker=true)
as
select c.organization_id,c.onboarding_request_id,count(*) check_count,
       count(*) filter(where c.required) required_check_count,
       count(*) filter(where c.required and c.status in('passed','waived','not_applicable')) required_passed_count,
       count(*) filter(where c.blocking and c.status='failed') blocking_failed_count,
       round(coalesce(sum(c.score_weight) filter(where c.status in('passed','waived','not_applicable')),0)/nullif(sum(c.score_weight),0)*100,2) readiness_score,
       bool_and(case when c.required then c.status in('passed','waived','not_applicable') else true end)
        and count(*) filter(where c.blocking and c.status='failed')=0 ready_for_activation,
       max(c.checked_at) last_checked_at
from public.onboarding_activation_checks c
group by c.organization_id,c.onboarding_request_id;

create or replace view public.onboarding_invitation_dashboard
with (security_invoker=true)
as
select i.organization_id,i.requested_role_code,i.status,count(*) invitation_count,
       count(*) filter(where i.status in('pending','sent','delivered') and i.expires_at<=now()) expired_pending_count,
       count(*) filter(where i.status='accepted') accepted_count,
       avg(extract(epoch from(i.accepted_at-i.created_at))/3600) filter(where i.accepted_at is not null) average_acceptance_hours,
       min(i.expires_at) filter(where i.status in('pending','sent','delivered')) next_expiry_at,
       max(i.updated_at) latest_update_at
from public.onboarding_invitations i
group by i.organization_id,i.requested_role_code,i.status;

create or replace view public.onboarding_import_dashboard
with (security_invoker=true)
as
select j.organization_id,j.import_type,j.source_type,j.status,count(*) import_job_count,
       sum(j.total_records) total_records,sum(j.valid_records) valid_records,sum(j.invalid_records) invalid_records,
       sum(j.duplicate_records) duplicate_records,sum(j.imported_records) imported_records,sum(j.failed_records) failed_records,
       avg(j.progress_percentage) average_progress_percentage,max(j.updated_at) latest_update_at
from public.onboarding_data_import_jobs j
group by j.organization_id,j.import_type,j.source_type,j.status;

create or replace view public.onboarding_time_to_value_dashboard
with (security_invoker=true)
as
select r.organization_id,r.id onboarding_request_id,r.request_code,r.organization_name,r.tenant_type,r.preferred_plan_code,r.status,
       r.created_at,r.submitted_at,r.approved_at,r.provisioning_started_at,r.provisioned_at,r.activated_at,
       extract(epoch from(r.submitted_at-r.created_at))/60 minutes_to_submit,
       extract(epoch from(r.approved_at-r.submitted_at))/60 minutes_to_approve,
       extract(epoch from(r.provisioned_at-r.provisioning_started_at))/60 minutes_to_provision,
       extract(epoch from(r.activated_at-r.created_at))/3600 hours_to_activate
from public.tenant_onboarding_requests r;

grant select on
 public.onboarding_pipeline_dashboard,public.onboarding_progress_dashboard,public.onboarding_task_dashboard,
 public.onboarding_activation_readiness_dashboard,public.onboarding_invitation_dashboard,public.onboarding_import_dashboard,
 public.onboarding_time_to_value_dashboard
to authenticated,service_role;

-- ============================================================
-- 22. Engine health
-- ============================================================

create or replace function public.get_onboarding_engine_health(p_organization_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
 if auth.role()<>'service_role' and (p_organization_id is null or not public.has_organization_permission(p_organization_id,'onboarding.view_logs')) then
  raise exception 'Permission denied';
 end if;
 return jsonb_build_object(
  'organization_id',p_organization_id,'checked_at',now(),
  'pending_requests',(select count(*) from public.tenant_onboarding_requests r where r.status in('submitted','under_review','approved','provisioning','activation_pending') and (p_organization_id is null or r.organization_id=p_organization_id)),
  'failed_requests',(select count(*) from public.tenant_onboarding_requests r where r.status='failed' and (p_organization_id is null or r.organization_id=p_organization_id)),
  'stale_provisioning_requests',(select count(*) from public.tenant_onboarding_requests r where r.status='provisioning' and r.provisioning_started_at<now()-interval '30 minutes' and (p_organization_id is null or r.organization_id=p_organization_id)),
  'pending_tasks',(select count(*) from public.onboarding_provisioning_tasks t where t.status in('queued','failed','claimed','running','waiting') and (p_organization_id is null or t.organization_id=p_organization_id)),
  'dead_lettered_tasks',(select count(*) from public.onboarding_provisioning_tasks t where t.status='dead_lettered' and (p_organization_id is null or t.organization_id=p_organization_id)),
  'expired_task_locks',(select count(*) from public.onboarding_provisioning_tasks t where t.status in('claimed','running') and t.lock_expires_at is not null and t.lock_expires_at<=now() and (p_organization_id is null or t.organization_id=p_organization_id)),
  'pending_invitations',(select count(*) from public.onboarding_invitations i where i.status in('pending','sent','delivered') and i.expires_at>now() and (p_organization_id is null or i.organization_id=p_organization_id)),
  'expired_invitations',(select count(*) from public.onboarding_invitations i where i.status in('pending','sent','delivered') and i.expires_at<=now() and (p_organization_id is null or i.organization_id=p_organization_id)),
  'member_access_failures',(select count(*) from public.onboarding_tenant_members m where m.access_provisioning_status='failed' and (p_organization_id is null or m.organization_id=p_organization_id)),
  'blocking_activation_failures',(select count(*) from public.onboarding_activation_checks c where c.blocking and c.status='failed' and (p_organization_id is null or c.organization_id=p_organization_id)),
  'pending_import_jobs',(select count(*) from public.onboarding_data_import_jobs j where j.status in('uploaded','validating','ready','queued','processing','failed') and (p_organization_id is null or j.organization_id=p_organization_id)),
  'pending_outbox_events',(select count(*) from public.onboarding_event_outbox e where e.status in('pending','failed','claimed','processing') and (p_organization_id is null or e.organization_id=p_organization_id)),
  'dead_lettered_outbox_events',(select count(*) from public.onboarding_event_outbox e where e.status='dead_lettered' and (p_organization_id is null or e.organization_id=p_organization_id))
 );
end;
$$;

-- ============================================================
-- 23. Row-level security
-- ============================================================

alter table public.onboarding_templates enable row level security;
alter table public.onboarding_template_steps enable row level security;
alter table public.tenant_onboarding_requests enable row level security;
alter table public.onboarding_request_contacts enable row level security;
alter table public.onboarding_approvals enable row level security;
alter table public.onboarding_tenant_members enable row level security;
alter table public.onboarding_invitations enable row level security;
alter table public.onboarding_provisioning_runs enable row level security;
alter table public.onboarding_provisioning_tasks enable row level security;
alter table public.onboarding_workspace_settings enable row level security;
alter table public.onboarding_checklist_items enable row level security;
alter table public.onboarding_progress_events enable row level security;
alter table public.onboarding_data_import_jobs enable row level security;
alter table public.onboarding_sample_data_packs enable row level security;
alter table public.onboarding_sample_data_jobs enable row level security;
alter table public.onboarding_integration_requirements enable row level security;
alter table public.onboarding_domain_requests enable row level security;
alter table public.onboarding_activation_checks enable row level security;
alter table public.onboarding_event_outbox enable row level security;
alter table public.onboarding_logs enable row level security;

drop policy if exists onboarding_templates_select_policy on public.onboarding_templates;
create policy onboarding_templates_select_policy on public.onboarding_templates for select to authenticated
using(organization_id is null or public.has_organization_permission(organization_id,'onboarding.view') or public.has_organization_permission(organization_id,'onboarding.view_all'));
drop policy if exists onboarding_templates_service_policy on public.onboarding_templates;
create policy onboarding_templates_service_policy on public.onboarding_templates for all to service_role using(true) with check(true);

drop policy if exists onboarding_template_steps_select_policy on public.onboarding_template_steps;
create policy onboarding_template_steps_select_policy on public.onboarding_template_steps for select to authenticated
using(organization_id is null or public.has_organization_permission(organization_id,'onboarding.view') or public.has_organization_permission(organization_id,'onboarding.view_all'));
drop policy if exists onboarding_template_steps_service_policy on public.onboarding_template_steps;
create policy onboarding_template_steps_service_policy on public.onboarding_template_steps for all to service_role using(true) with check(true);

drop policy if exists tenant_onboarding_requests_select_policy on public.tenant_onboarding_requests;
create policy tenant_onboarding_requests_select_policy on public.tenant_onboarding_requests for select to authenticated
using(requested_by_user_id=auth.uid() or (organization_id is not null and (public.has_organization_permission(organization_id,'onboarding.view') or public.has_organization_permission(organization_id,'onboarding.view_all'))));
drop policy if exists tenant_onboarding_requests_service_policy on public.tenant_onboarding_requests;
create policy tenant_onboarding_requests_service_policy on public.tenant_onboarding_requests for all to service_role using(true) with check(true);

drop policy if exists onboarding_request_contacts_select_policy on public.onboarding_request_contacts;
create policy onboarding_request_contacts_select_policy on public.onboarding_request_contacts for select to authenticated
using(exists(select 1 from public.tenant_onboarding_requests r where r.id=onboarding_request_contacts.onboarding_request_id and
 (r.requested_by_user_id=auth.uid() or (r.organization_id is not null and (public.has_organization_permission(r.organization_id,'onboarding.view') or public.has_organization_permission(r.organization_id,'onboarding.view_all'))))));
drop policy if exists onboarding_request_contacts_service_policy on public.onboarding_request_contacts;
create policy onboarding_request_contacts_service_policy on public.onboarding_request_contacts for all to service_role using(true) with check(true);

drop policy if exists onboarding_approvals_select_policy on public.onboarding_approvals;
create policy onboarding_approvals_select_policy on public.onboarding_approvals for select to authenticated
using(exists(select 1 from public.tenant_onboarding_requests r where r.id=onboarding_approvals.onboarding_request_id and
 (r.requested_by_user_id=auth.uid() or (r.organization_id is not null and (public.has_organization_permission(r.organization_id,'onboarding.view') or public.has_organization_permission(r.organization_id,'onboarding.view_all'))))));
drop policy if exists onboarding_approvals_service_policy on public.onboarding_approvals;
create policy onboarding_approvals_service_policy on public.onboarding_approvals for all to service_role using(true) with check(true);

do $$
declare t text;
begin
 foreach t in array array[
  'onboarding_tenant_members','onboarding_invitations','onboarding_provisioning_runs','onboarding_provisioning_tasks',
  'onboarding_workspace_settings','onboarding_checklist_items','onboarding_progress_events','onboarding_data_import_jobs',
  'onboarding_sample_data_jobs','onboarding_integration_requirements','onboarding_domain_requests','onboarding_activation_checks',
  'onboarding_event_outbox','onboarding_logs'
 ] loop
  execute format('drop policy if exists %I_select_policy on public.%I',t,t);
  execute format('create policy %I_select_policy on public.%I for select to authenticated using(organization_id is not null and (public.has_organization_permission(organization_id,''onboarding.view'') or public.has_organization_permission(organization_id,''onboarding.view_all'')))',t,t);
  execute format('drop policy if exists %I_service_policy on public.%I',t,t);
  execute format('create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t);
 end loop;
end;
$$;

drop policy if exists onboarding_tenant_members_self_select_policy on public.onboarding_tenant_members;
create policy onboarding_tenant_members_self_select_policy on public.onboarding_tenant_members for select to authenticated
using(user_id=auth.uid() or public.has_organization_permission(organization_id,'onboarding.view') or public.has_organization_permission(organization_id,'onboarding.view_all'));

drop policy if exists onboarding_sample_data_packs_select_policy on public.onboarding_sample_data_packs;
create policy onboarding_sample_data_packs_select_policy on public.onboarding_sample_data_packs for select to authenticated
using(organization_id is null or public.has_organization_permission(organization_id,'onboarding.view') or public.has_organization_permission(organization_id,'onboarding.view_all'));
drop policy if exists onboarding_sample_data_packs_service_policy on public.onboarding_sample_data_packs;
create policy onboarding_sample_data_packs_service_policy on public.onboarding_sample_data_packs for all to service_role using(true) with check(true);

-- ============================================================
-- 24. Grants
-- ============================================================

grant select on
 public.onboarding_templates,public.onboarding_template_steps,public.tenant_onboarding_requests,public.onboarding_request_contacts,
 public.onboarding_approvals,public.onboarding_tenant_members,public.onboarding_invitations,public.onboarding_provisioning_runs,
 public.onboarding_provisioning_tasks,public.onboarding_workspace_settings,public.onboarding_checklist_items,public.onboarding_progress_events,
 public.onboarding_data_import_jobs,public.onboarding_sample_data_packs,public.onboarding_sample_data_jobs,
 public.onboarding_integration_requirements,public.onboarding_domain_requests,public.onboarding_activation_checks,
 public.onboarding_event_outbox,public.onboarding_logs
to authenticated;

grant all on
 public.onboarding_templates,public.onboarding_template_steps,public.tenant_onboarding_requests,public.onboarding_request_contacts,
 public.onboarding_approvals,public.onboarding_tenant_members,public.onboarding_invitations,public.onboarding_provisioning_runs,
 public.onboarding_provisioning_tasks,public.onboarding_workspace_settings,public.onboarding_checklist_items,public.onboarding_progress_events,
 public.onboarding_data_import_jobs,public.onboarding_sample_data_packs,public.onboarding_sample_data_jobs,
 public.onboarding_integration_requirements,public.onboarding_domain_requests,public.onboarding_activation_checks,
 public.onboarding_event_outbox,public.onboarding_logs
to service_role;

do $$
declare r record;
begin
 for r in
  select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
   'normalize_onboarding_slug','resolve_onboarding_template','create_tenant_onboarding_request','submit_tenant_onboarding_request',
   'generate_unique_onboarding_slug','create_onboarding_invitation','accept_onboarding_invitation','complete_onboarding_checklist_item',
   'set_onboarding_activation_check','evaluate_onboarding_activation_checks','activate_onboarded_tenant',
   'create_onboarding_data_import_job','request_onboarding_domain','publish_onboarding_event','get_onboarding_engine_health'
  )
 loop
  execute format('revoke all on function %s from public',r.signature);
  execute format('grant execute on function %s to authenticated,service_role',r.signature);
 end loop;
 for r in
  select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
   'decide_tenant_onboarding_request','initialize_onboarding_checklist','initialize_onboarding_activation_checks',
   'create_default_onboarding_workspace','create_onboarding_owner_member','provision_onboarding_billing','provision_tenant_onboarding',
   'complete_onboarding_member_access','claim_onboarding_provisioning_task','complete_onboarding_provisioning_task',
   'fail_onboarding_provisioning_task','refresh_onboarding_provisioning_run','claim_onboarding_event','complete_onboarding_event','fail_onboarding_event'
  )
 loop
  execute format('revoke all on function %s from public',r.signature);
  execute format('grant execute on function %s to service_role',r.signature);
 end loop;
end;
$$;

-- ============================================================
-- 25. System templates and steps
-- ============================================================

insert into public.onboarding_templates(
 organization_id,template_code,template_name,description,tenant_type,version,is_default,is_system_template,estimated_completion_minutes,status,configuration,metadata
)
select null,s.template_code,s.template_name,s.description,s.tenant_type,1,true,true,s.minutes,'active',
       jsonb_build_object('default_plan_code',s.plan_code,'default_price_code',s.price_code,'default_trial_days',s.trial_days,'sample_data_available',true),
       jsonb_build_object('seeded_by_migration','033')
from (values
 ('REAL_ESTATE_BROKERAGE_STANDARD','Real Estate Brokerage Standard Onboarding','Default SalesSetu onboarding flow for a brokerage','brokerage',90,'starter','starter_monthly',7),
 ('REAL_ESTATE_BUILDER_STANDARD','Real Estate Builder Standard Onboarding','Default SalesSetu onboarding flow for a builder','builder',120,'growth','growth_monthly',14),
 ('REAL_ESTATE_HYBRID_STANDARD','Real Estate Hybrid Standard Onboarding','Default SalesSetu onboarding flow for a brokerage-builder hybrid','hybrid',120,'growth','growth_monthly',14),
 ('AGENCY_STANDARD','Agency Standard Onboarding','Default SalesSetu onboarding flow for a service agency','agency',90,'starter','starter_monthly',7),
 ('ENTERPRISE_STANDARD','Enterprise Standard Onboarding','Default SalesSetu onboarding flow for an enterprise tenant','enterprise',150,'professional','professional_monthly',14),
 ('OTHER_STANDARD','General Tenant Standard Onboarding','Default SalesSetu onboarding flow for another tenant type','other',90,'starter','starter_monthly',7)
) s(template_code,template_name,description,tenant_type,minutes,plan_code,price_code,trial_days)
where not exists(select 1 from public.onboarding_templates t where t.organization_id is null and t.template_code=s.template_code and t.version=1);

with templates as(
 select id,tenant_type from public.onboarding_templates
 where organization_id is null and template_code in('REAL_ESTATE_BROKERAGE_STANDARD','REAL_ESTATE_BUILDER_STANDARD','REAL_ESTATE_HYBRID_STANDARD','AGENCY_STANDARD','ENTERPRISE_STANDARD','OTHER_STANDARD') and version=1
), steps as(
 select * from (values
  ('COMPANY_PROFILE','Complete company profile','Verify legal, contact and location details','company','manual',10,true,true,'{}'::text[],'tenant_admin','administration','organization_profile',10),
  ('OWNER_ACCESS','Activate owner access','Provision authenticated organization administrator access','team','worker',20,true,true,array['COMPANY_PROFILE']::text[],'system','rbac','organization_admin',5),
  ('TEAM_SETUP','Add team members','Invite managers and sales agents','team','manual',30,false,false,array['OWNER_ACCESS']::text[],'tenant_admin','administration','employees',10),
  ('BILLING_TRIAL','Review subscription and trial','Confirm selected plan, trial and billing profile','billing','hybrid',40,true,true,array['COMPANY_PROFILE']::text[],'tenant_admin','billing','subscription',5),
  ('COMMUNICATION_CHANNEL','Connect communication channel','Connect WhatsApp, email or SMS','communication','external',50,false,false,array['OWNER_ACCESS']::text[],'tenant_admin','communication','channel',15),
  ('AI_CALLING','Configure AI calling','Select provider, voice, script and qualification schema','ai','hybrid',60,false,false,array['OWNER_ACCESS']::text[],'tenant_admin','ai_calling','campaign',15),
  ('LEAD_SOURCE','Connect a lead source','Connect Meta, Google, website form or WhatsApp','data_import','external',70,false,false,array['OWNER_ACCESS']::text[],'tenant_admin','integrations','lead_source',15),
  ('INVENTORY_SETUP','Add projects and inventory','Create or import projects, units and pricing','inventory','manual',80,false,false,array['OWNER_ACCESS']::text[],'tenant_admin','inventory','projects',20),
  ('AUTOMATION_SETUP','Enable default automation','Enable validation, AI qualification, assignment and follow-up workflow','automation','worker',90,false,false,array['LEAD_SOURCE']::text[],'system','automation','workflow',5),
  ('SECURITY_REVIEW','Review security settings','Review member access, MFA guidance and governance','security','hybrid',100,true,true,array['OWNER_ACCESS']::text[],'tenant_admin','security','baseline',10),
  ('QUICK_START_TRAINING','Complete quick-start training','Learn lead, follow-up, visit and booking workflows','training','manual',110,false,false,array['OWNER_ACCESS']::text[],'tenant_admin','training','quick_start',15),
  ('GO_LIVE','Activate workspace','Review readiness and activate the tenant','activation','approval',120,true,true,array['BILLING_TRIAL','SECURITY_REVIEW']::text[],'tenant_admin','onboarding','activate',5)
 ) s(step_code,step_name,description,category,execution_mode,sequence_number,required,blocking,dependencies,owner_type,target_module,target_action,estimated_minutes)
)
insert into public.onboarding_template_steps(
 organization_id,template_id,step_code,step_name,description,step_category,execution_mode,sequence_number,required,blocking,dependency_step_codes,
 owner_type,target_module,target_action,estimated_minutes,validation_rule,default_data,status
)
select null,t.id,s.step_code,s.step_name,s.description,s.category,s.execution_mode,s.sequence_number,
       case when s.step_code='INVENTORY_SETUP' and t.tenant_type in('builder','hybrid') then true else s.required end,
       s.blocking,s.dependencies,s.owner_type,s.target_module,s.target_action,s.estimated_minutes,'{}','{}','active'
from templates t cross join steps s
where not exists(select 1 from public.onboarding_template_steps x where x.template_id=t.id and x.step_code=s.step_code);

-- ============================================================
-- 26. System sample-data packs
-- ============================================================

insert into public.onboarding_sample_data_packs(
 organization_id,pack_code,pack_name,description,tenant_type,version,is_system_pack,included_modules,record_manifest,provisioning_configuration,status,metadata
)
select null,s.pack_code,s.pack_name,s.description,s.tenant_type,1,true,s.modules,s.manifest,
       jsonb_build_object('production_safe',true,'mark_as_sample',true,'allow_rollback',true),'active',jsonb_build_object('seeded_by_migration','033')
from (values
 ('BROKERAGE_DEMO','Brokerage Demo Data','Optional demonstration data for a brokerage','brokerage',
  array['builders','projects','inventory','leads','followups','site_visits','analytics']::text[],
  jsonb_build_object('builders',1,'projects',2,'inventory_units',10,'leads',12,'followups',8,'site_visits',3)),
 ('BUILDER_DEMO','Builder Demo Data','Optional demonstration data for a builder','builder',
  array['builders','projects','towers','floors','inventory','payment_plans','leads','analytics']::text[],
  jsonb_build_object('builders',1,'projects',1,'towers',2,'floors',10,'inventory_units',20,'payment_plans',2,'leads',10))
) s(pack_code,pack_name,description,tenant_type,modules,manifest)
where not exists(select 1 from public.onboarding_sample_data_packs p where p.organization_id is null and p.pack_code=s.pack_code and p.version=1);

-- ============================================================
-- 27. Final validation
-- ============================================================

do $$
declare item text; missing_items text[]:='{}';
begin
 foreach item in array array[
  'onboarding_templates','onboarding_template_steps','tenant_onboarding_requests','onboarding_request_contacts','onboarding_approvals',
  'onboarding_tenant_members','onboarding_invitations','onboarding_provisioning_runs','onboarding_provisioning_tasks',
  'onboarding_workspace_settings','onboarding_checklist_items','onboarding_progress_events','onboarding_data_import_jobs',
  'onboarding_sample_data_packs','onboarding_sample_data_jobs','onboarding_integration_requirements','onboarding_domain_requests',
  'onboarding_activation_checks','onboarding_event_outbox','onboarding_logs'
 ] loop
  if not exists(select 1 from information_schema.tables where table_schema='public' and table_name=item) then
   missing_items:=array_append(missing_items,'table:'||item);
  end if;
 end loop;
 foreach item in array array[
  'normalize_onboarding_slug','publish_onboarding_event','claim_onboarding_event','complete_onboarding_event','fail_onboarding_event',
  'resolve_onboarding_template','generate_unique_onboarding_slug','create_tenant_onboarding_request','submit_tenant_onboarding_request',
  'decide_tenant_onboarding_request','create_onboarding_invitation','accept_onboarding_invitation','initialize_onboarding_checklist',
  'initialize_onboarding_activation_checks','create_default_onboarding_workspace','create_onboarding_owner_member','provision_onboarding_billing',
  'provision_tenant_onboarding','complete_onboarding_member_access','complete_onboarding_checklist_item','set_onboarding_activation_check',
  'evaluate_onboarding_activation_checks','activate_onboarded_tenant','refresh_onboarding_provisioning_run','claim_onboarding_provisioning_task',
  'complete_onboarding_provisioning_task','fail_onboarding_provisioning_task','create_onboarding_data_import_job','request_onboarding_domain',
  'get_onboarding_engine_health'
 ] loop
  if not exists(select 1 from information_schema.routines where routine_schema='public' and routine_name=item) then
   missing_items:=array_append(missing_items,'function:'||item);
  end if;
 end loop;
 if cardinality(missing_items)>0 then raise exception '033 migration validation failed. Missing: %',array_to_string(missing_items,', '); end if;
end;
$$;

-- 28. Migration audit
insert into public.onboarding_logs(organization_id,log_level,event_name,message,source_type,log_data)
select o.id,'info','migration.033.completed','Tenant Onboarding and Provisioning Engine migration 033 completed','migration',
       jsonb_build_object('migration','033_tenant_onboarding_provisioning_engine','completed_at',now(),
        'modules',jsonb_build_array('templates','signup_requests','approvals','organization_provisioning','workspace_initialization','owner_admin',
         'invitations','rbac_queue','billing_trial','checklists','activation_checks','data_import','sample_data','integrations','domains','task_workers','event_outbox','analytics','health_monitoring'))
from public.organizations o
where not exists(select 1 from public.onboarding_logs l where l.organization_id=o.id and l.event_name='migration.033.completed');

commit;