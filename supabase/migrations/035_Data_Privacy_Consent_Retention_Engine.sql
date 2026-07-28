begin;
create extension if not exists pgcrypto;

-- 035 Data Privacy, Consent & Retention Engine

insert into public.permissions(module,action,code,description)
select * from (values
('privacy','view','privacy.view','View privacy records'),
('privacy','view_all','privacy.view_all','View all privacy records'),
('privacy','manage_consents','privacy.manage_consents','Manage consent records'),
('privacy','manage_requests','privacy.manage_requests','Manage data-subject requests'),
('privacy','approve_requests','privacy.approve_requests','Approve privacy requests'),
('privacy','manage_retention','privacy.manage_retention','Manage retention policies'),
('privacy','manage_legal_holds','privacy.manage_legal_holds','Manage legal holds'),
('privacy','execute_deletion','privacy.execute_deletion','Execute deletion or anonymization'),
('privacy','manage_incidents','privacy.manage_incidents','Manage privacy incidents'),
('privacy','view_logs','privacy.view_logs','View privacy logs'),
('privacy','view_analytics','privacy.view_analytics','View privacy analytics')
) x(module,action,code,description)
where not exists(select 1 from public.permissions p where p.code=x.code);

insert into public.role_permissions(role_id,permission_id)
select r.id,p.id from public.roles r cross join public.permissions p
where r.code in ('platform_admin','organization_admin') and p.module='privacy'
on conflict(role_id,permission_id) do nothing;

create table if not exists public.privacy_jurisdictions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 code text not null,name text not null,country_code text,regulation text,
 request_deadline_days integer not null default 30 check(request_deadline_days>0),
 breach_notification_hours integer,
 config jsonb not null default '{}',status text not null default 'active'
 check(status in('active','inactive','archived')),
 created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_jurisdictions_org_uq on public.privacy_jurisdictions(organization_id,code) where organization_id is not null;
create unique index if not exists privacy_jurisdictions_global_uq on public.privacy_jurisdictions(code) where organization_id is null;

create table if not exists public.privacy_purposes(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 code text not null,name text not null,description text,
 category text not null default 'service_delivery',
 lawful_basis text not null default 'consent',
 consent_required boolean not null default true,
 explicit_consent_required boolean not null default false,
 withdrawal_allowed boolean not null default true,
 retention_days integer check(retention_days is null or retention_days>=0),
 data_categories text[] not null default '{}',
 status text not null default 'active' check(status in('draft','active','inactive','retired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_purposes_org_uq on public.privacy_purposes(organization_id,code) where organization_id is not null;
create unique index if not exists privacy_purposes_global_uq on public.privacy_purposes(code) where organization_id is null;

create table if not exists public.privacy_notices(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 jurisdiction_id uuid references public.privacy_jurisdictions(id) on delete set null,
 code text not null,name text not null,notice_type text not null default 'privacy_notice',
 language_code text not null default 'en-IN',version integer not null default 1,
 title text not null,summary text,content_markdown text,content_html text,
 effective_from timestamptz not null default now(),effective_until timestamptz,
 requires_reconsent boolean not null default false,checksum text not null,
 status text not null default 'draft' check(status in('draft','approved','active','superseded','expired','archived')),
 approved_by uuid references auth.users(id),approved_at timestamptz,
 metadata jsonb not null default '{}',created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_notices_org_uq on public.privacy_notices(organization_id,code,language_code,version) where organization_id is not null;
create unique index if not exists privacy_notices_global_uq on public.privacy_notices(code,language_code,version) where organization_id is null;

create table if not exists public.privacy_subjects(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subject_type text not null default 'lead',
 lead_id uuid references public.leads(id) on delete set null,
 customer_id uuid references public.customers(id) on delete set null,
 user_id uuid references auth.users(id) on delete set null,
 external_id text,full_name text,email text,phone text,country_code text default 'IN',
 normalized_email text generated always as(nullif(lower(trim(email)),'')) stored,
 normalized_phone text generated always as(nullif(regexp_replace(coalesce(phone,''),'[^0-9]','','g'),'')) stored,
 identity_status text not null default 'unverified' check(identity_status in('unverified','pending','verified','failed','restricted')),
 status text not null default 'active' check(status in('active','restricted','anonymized','deleted','archived')),
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_subjects_lead_uq on public.privacy_subjects(organization_id,lead_id) where lead_id is not null;
create unique index if not exists privacy_subjects_customer_uq on public.privacy_subjects(organization_id,customer_id) where customer_id is not null;
create unique index if not exists privacy_subjects_user_uq on public.privacy_subjects(organization_id,user_id) where user_id is not null;
create index if not exists privacy_subjects_contact_idx on public.privacy_subjects(organization_id,normalized_email,normalized_phone);

create table if not exists public.privacy_consents(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subject_id uuid not null references public.privacy_subjects(id) on delete cascade,
 purpose_id uuid not null references public.privacy_purposes(id) on delete restrict,
 notice_id uuid references public.privacy_notices(id) on delete set null,
 status text not null check(status in('granted','denied','withdrawn','expired','pending','not_required')),
 method text not null default 'web_form',explicit_consent boolean not null default false,
 granted_at timestamptz,denied_at timestamptz,withdrawn_at timestamptz,expires_at timestamptz,
 withdrawal_reason text,source_reference text,source_url text,source_ip inet,user_agent text,device_id text,session_id text,
 consent_text_snapshot text,proof_document_id uuid references public.documents(id) on delete set null,
 proof_data jsonb not null default '{}',recorded_by uuid references auth.users(id),
 idempotency_key text,metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_consents_idem_uq on public.privacy_consents(idempotency_key) where idempotency_key is not null;
create index if not exists privacy_consents_lookup_idx on public.privacy_consents(subject_id,purpose_id,created_at desc);

create table if not exists public.privacy_preferences(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subject_id uuid not null references public.privacy_subjects(id) on delete cascade,
 channel text not null,purpose_code text not null default 'marketing',
 preference_status text not null default 'opted_out'
 check(preference_status in('opted_in','opted_out','transactional_only','temporarily_paused','unknown')),
 quiet_hours_start time,quiet_hours_end time,timezone text default 'Asia/Kolkata',paused_until timestamptz,
 source text,reason text,effective_at timestamptz not null default now(),
 recorded_by uuid references auth.users(id),metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(subject_id,channel,purpose_code)
);

create table if not exists public.privacy_suppressions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subject_id uuid references public.privacy_subjects(id) on delete cascade,
 suppression_type text not null,normalized_value text,reason_code text not null,reason text,
 starts_at timestamptz not null default now(),expires_at timestamptz,
 status text not null default 'active' check(status in('active','inactive','expired','archived')),
 source_type text,source_id uuid,created_by uuid references auth.users(id),
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index if not exists privacy_suppressions_lookup_idx on public.privacy_suppressions(organization_id,suppression_type,normalized_value,status);

create table if not exists public.privacy_classifications(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 code text not null,name text not null,description text,sensitivity integer not null default 1 check(sensitivity between 0 and 5),
 category text not null,encryption_required boolean not null default false,masking_required boolean not null default false,
 access_logging_required boolean not null default true,retention_days integer,
 status text not null default 'active' check(status in('active','inactive','archived')),
 metadata jsonb not null default '{}',created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_classifications_org_uq on public.privacy_classifications(organization_id,code) where organization_id is not null;
create unique index if not exists privacy_classifications_global_uq on public.privacy_classifications(code) where organization_id is null;

create table if not exists public.privacy_processing_activities(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 jurisdiction_id uuid references public.privacy_jurisdictions(id) on delete set null,
 code text not null,name text not null,description text,owner_user_id uuid references auth.users(id),
 purpose_codes text[] not null default '{}',lawful_bases text[] not null default '{}',
 data_categories text[] not null default '{}',subject_categories text[] not null default '{}',
 recipients text[] not null default '{}',subprocessors jsonb not null default '[]',
 international_transfer boolean not null default false,transfer_countries text[] not null default '{}',
 security_measures jsonb not null default '{}',automated_decision_making boolean not null default false,
 profiling boolean not null default false,dpi_required boolean not null default false,dpi_completed_at timestamptz,
 dpi_document_id uuid references public.documents(id) on delete set null,last_reviewed_at timestamptz,next_review_at timestamptz,
 status text not null default 'active' check(status in('draft','active','under_review','retired','archived')),
 metadata jsonb not null default '{}',created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(organization_id,code)
);

create table if not exists public.privacy_requests(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subject_id uuid references public.privacy_subjects(id) on delete set null,
 jurisdiction_id uuid references public.privacy_jurisdictions(id) on delete set null,
 request_code text not null unique,request_type text not null,request_source text not null default 'customer_portal',
 request_details text,requested_data jsonb not null default '{}',requester_name text,requester_email text,requester_phone text,
 identity_status text not null default 'pending' check(identity_status in('pending','verified','failed','waived')),
 identity_method text,identity_verified_at timestamptz,identity_verified_by uuid references auth.users(id),identity_evidence jsonb not null default '{}',
 status text not null default 'received' check(status in('received','identity_verification','triage','in_progress','awaiting_approval','approved','rejected','partially_completed','completed','cancelled','expired')),
 priority text not null default 'normal' check(priority in('low','normal','high','urgent')),
 received_at timestamptz not null default now(),due_at timestamptz not null,assigned_to uuid references auth.users(id),
 decision text,decision_reason text,decided_by uuid references auth.users(id),decided_at timestamptz,
 completed_at timestamptz,completion_summary text,export_document_id uuid references public.documents(id),
 response_document_id uuid references public.documents(id),legal_basis_for_rejection text,
 idempotency_key text,correlation_id text,trace_id text,metadata jsonb not null default '{}',
 created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_requests_idem_uq on public.privacy_requests(idempotency_key) where idempotency_key is not null;
create index if not exists privacy_requests_due_idx on public.privacy_requests(organization_id,status,due_at,priority);

create table if not exists public.privacy_request_tasks(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 request_id uuid not null references public.privacy_requests(id) on delete cascade,
 task_code text not null,task_name text not null,task_type text not null,sequence_number integer not null default 100,
 dependency_task_codes text[] not null default '{}',required boolean not null default true,blocking boolean not null default true,
 handler_code text,destination text not null default 'service_worker',
 status text not null default 'queued' check(status in('queued','claimed','running','waiting','completed','skipped','failed','cancelled','dead_lettered')),
 input_data jsonb not null default '{}',output_data jsonb not null default '{}',available_at timestamptz not null default now(),
 attempt_count integer not null default 0,maximum_attempts integer not null default 5,
 claimed_at timestamptz,claimed_by text,lock_token text,lock_expires_at timestamptz,
 started_at timestamptz,completed_at timestamptz,failed_at timestamptz,
 last_error_code text,last_error_message text,last_error_data jsonb not null default '{}',
 idempotency_key text,correlation_id text,trace_id text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(request_id,task_code)
);
create index if not exists privacy_request_tasks_worker_idx on public.privacy_request_tasks(status,available_at,sequence_number,created_at) where status in('queued','failed');

create table if not exists public.privacy_retention_policies(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 jurisdiction_id uuid references public.privacy_jurisdictions(id) on delete set null,
 code text not null,name text not null,description text,entity_type text not null,source_table text,timestamp_column text not null default 'created_at',
 retention_basis text not null default 'business_need',retention_days integer not null check(retention_days>=0),
 grace_days integer not null default 30 check(grace_days>=0),action_on_expiry text not null default 'anonymize',
 subject_filter jsonb not null default '{}',exclusion_filter jsonb not null default '{}',
 legal_hold_respected boolean not null default true,consent_withdrawal_accelerates boolean not null default false,
 execution_mode text not null default 'scheduled',batch_size integer not null default 500,schedule_cron text,
 last_evaluated_at timestamptz,next_evaluation_at timestamptz,
 status text not null default 'active' check(status in('draft','active','paused','inactive','archived')),
 metadata jsonb not null default '{}',created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_retention_policies_org_uq on public.privacy_retention_policies(organization_id,code) where organization_id is not null;
create unique index if not exists privacy_retention_policies_global_uq on public.privacy_retention_policies(code) where organization_id is null;

create table if not exists public.privacy_legal_holds(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 hold_code text not null,hold_name text not null,description text,hold_type text not null default 'litigation',
 matter_reference text,scope_definition jsonb not null default '{}',entity_types text[] not null default '{}',
 starts_at timestamptz not null default now(),expires_at timestamptz,
 status text not null default 'active' check(status in('draft','active','released','expired','archived')),
 released_at timestamptz,released_by uuid references auth.users(id),release_reason text,
 approved_by uuid references auth.users(id),approved_at timestamptz,
 metadata jsonb not null default '{}',created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 unique(organization_id,hold_code)
);

create table if not exists public.privacy_legal_hold_items(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 legal_hold_id uuid not null references public.privacy_legal_holds(id) on delete cascade,
 entity_type text not null,entity_id uuid,subject_id uuid references public.privacy_subjects(id) on delete set null,
 match_criteria jsonb not null default '{}',status text not null default 'active' check(status in('active','released','expired','archived')),
 added_reason text,created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index if not exists privacy_legal_hold_items_idx on public.privacy_legal_hold_items(organization_id,entity_type,entity_id,status);

create table if not exists public.privacy_retention_jobs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 policy_id uuid references public.privacy_retention_policies(id) on delete set null,
 job_code text not null unique,job_type text not null,status text not null default 'queued'
 check(status in('queued','claimed','running','completed','partially_completed','failed','cancelled','dead_lettered')),
 criteria jsonb not null default '{}',total_records bigint not null default 0,processed_records bigint not null default 0,
 completed_records bigint not null default 0,skipped_records bigint not null default 0,failed_records bigint not null default 0,
 available_at timestamptz not null default now(),attempt_count integer not null default 0,maximum_attempts integer not null default 5,
 claimed_at timestamptz,claimed_by text,lock_token text,lock_expires_at timestamptz,started_at timestamptz,completed_at timestamptz,failed_at timestamptz,
 last_error_code text,last_error_message text,last_error_data jsonb not null default '{}',
 idempotency_key text,correlation_id text,trace_id text,initiated_by uuid references auth.users(id),
 metadata jsonb not null default '{}',created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_retention_jobs_idem_uq on public.privacy_retention_jobs(idempotency_key) where idempotency_key is not null;
create index if not exists privacy_retention_jobs_worker_idx on public.privacy_retention_jobs(status,available_at,created_at) where status in('queued','failed');

create table if not exists public.privacy_incidents(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 jurisdiction_id uuid references public.privacy_jurisdictions(id) on delete set null,
 incident_code text not null unique,incident_name text not null,description text,incident_type text not null,
 severity text not null default 'medium' check(severity in('low','medium','high','critical')),
 status text not null default 'reported' check(status in('reported','triage','investigating','contained','assessing_notification','notification_required','notification_completed','resolved','closed','false_positive')),
 detected_at timestamptz not null default now(),occurred_at timestamptz,contained_at timestamptz,resolved_at timestamptz,
 affected_subject_count bigint not null default 0,affected_record_count bigint not null default 0,
 affected_data_categories text[] not null default '{}',affected_systems text[] not null default '{}',
 risk_assessment jsonb not null default '{}',regulator_notification_required boolean,subject_notification_required boolean,
 regulator_notification_due_at timestamptz,subject_notification_due_at timestamptz,regulator_notified_at timestamptz,subjects_notified_at timestamptz,
 containment_actions jsonb not null default '[]',remediation_actions jsonb not null default '[]',root_cause text,owner_user_id uuid references auth.users(id),
 metadata jsonb not null default '{}',created_by uuid references auth.users(id),updated_by uuid references auth.users(id),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create index if not exists privacy_incidents_idx on public.privacy_incidents(organization_id,severity,status,detected_at desc);

create table if not exists public.privacy_event_outbox(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 subject_id uuid references public.privacy_subjects(id) on delete set null,
 event_name text not null,source_type text,source_id uuid,destination text not null default 'internal',
 status text not null default 'pending' check(status in('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
 priority integer not null default 100,payload jsonb not null default '{}',available_at timestamptz not null default now(),
 delivery_attempts integer not null default 0,maximum_attempts integer not null default 10,
 claimed_at timestamptz,claimed_by text,lock_token text,lock_expires_at timestamptz,delivered_at timestamptz,
 last_error_code text,last_error_message text,last_error_data jsonb not null default '{}',
 idempotency_key text,correlation_id text,trace_id text,
 created_at timestamptz not null default now(),updated_at timestamptz not null default now()
);
create unique index if not exists privacy_event_outbox_idem_uq on public.privacy_event_outbox(idempotency_key) where idempotency_key is not null;
create index if not exists privacy_event_outbox_worker_idx on public.privacy_event_outbox(status,available_at,priority,created_at) where status in('pending','failed');

create table if not exists public.privacy_logs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete set null,
 subject_id uuid references public.privacy_subjects(id) on delete set null,
 log_level text not null default 'info',event_name text,message text,source_type text,source_id uuid,
 actor_user_id uuid references auth.users(id),error_code text,error_message text,log_data jsonb not null default '{}',
 correlation_id text,trace_id text,created_at timestamptz not null default now()
);
create index if not exists privacy_logs_idx on public.privacy_logs(organization_id,created_at desc);

-- generic updated_at triggers
do $$
declare t text;
begin
 foreach t in array array[
 'privacy_jurisdictions','privacy_purposes','privacy_notices','privacy_subjects','privacy_consents',
 'privacy_preferences','privacy_suppressions','privacy_classifications','privacy_processing_activities',
 'privacy_requests','privacy_request_tasks','privacy_retention_policies','privacy_legal_holds',
 'privacy_legal_hold_items','privacy_retention_jobs','privacy_incidents','privacy_event_outbox'
 ] loop
  execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
  execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
 end loop;
end $$;

create or replace function public.publish_privacy_event(
 p_organization_id uuid,p_subject_id uuid,p_event_name text,p_payload jsonb default '{}',
 p_destination text default 'internal',p_source_type text default null,p_source_id uuid default null,
 p_priority integer default 100,p_idempotency_key text default null,p_correlation_id text default null,
 p_trace_id text default null,p_available_at timestamptz default now()
) returns public.privacy_event_outbox
language plpgsql security definer set search_path=''
as $$
declare r public.privacy_event_outbox;
begin
 if p_idempotency_key is not null then
  select * into r from public.privacy_event_outbox where idempotency_key=p_idempotency_key limit 1;
  if found then return r; end if;
 end if;
 insert into public.privacy_event_outbox(
  organization_id,subject_id,event_name,source_type,source_id,destination,priority,payload,available_at,idempotency_key,correlation_id,trace_id
 ) values(
  p_organization_id,p_subject_id,p_event_name,p_source_type,p_source_id,p_destination,p_priority,coalesce(p_payload,'{}'),coalesce(p_available_at,now()),p_idempotency_key,p_correlation_id,p_trace_id
 ) returning * into r;
 return r;
end $$;

create or replace function public.upsert_privacy_subject(
 p_organization_id uuid,p_subject_type text,p_lead_id uuid default null,p_customer_id uuid default null,
 p_user_id uuid default null,p_external_id text default null,p_full_name text default null,
 p_email text default null,p_phone text default null,p_metadata jsonb default '{}'
) returns public.privacy_subjects
language plpgsql security definer set search_path=''
as $$
declare r public.privacy_subjects;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'privacy.manage_consents') then raise exception 'Permission denied'; end if;
 select * into r from public.privacy_subjects s where s.organization_id=p_organization_id and(
  (p_lead_id is not null and s.lead_id=p_lead_id) or (p_customer_id is not null and s.customer_id=p_customer_id) or
  (p_user_id is not null and s.user_id=p_user_id) or (p_external_id is not null and s.external_id=p_external_id) or
  (p_email is not null and s.normalized_email=lower(trim(p_email))) or
  (p_phone is not null and s.normalized_phone=regexp_replace(p_phone,'[^0-9]','','g'))
 ) order by s.created_at limit 1 for update;
 if found then
  update public.privacy_subjects set subject_type=p_subject_type,lead_id=coalesce(lead_id,p_lead_id),
   customer_id=coalesce(customer_id,p_customer_id),user_id=coalesce(user_id,p_user_id),
   external_id=coalesce(external_id,p_external_id),full_name=coalesce(p_full_name,full_name),
   email=coalesce(p_email,email),phone=coalesce(p_phone,phone),metadata=metadata||coalesce(p_metadata,'{}'),updated_at=now()
  where id=r.id returning * into r;
 else
  insert into public.privacy_subjects(organization_id,subject_type,lead_id,customer_id,user_id,external_id,full_name,email,phone,metadata)
  values(p_organization_id,p_subject_type,p_lead_id,p_customer_id,p_user_id,p_external_id,p_full_name,p_email,p_phone,coalesce(p_metadata,'{}'))
  returning * into r;
 end if;
 return r;
end $$;

create or replace function public.record_privacy_consent(
 p_organization_id uuid,p_subject_id uuid,p_purpose_code text,p_status text,
 p_method text default 'web_form',p_explicit boolean default false,p_expires_at timestamptz default null,
 p_notice_code text default null,p_proof_data jsonb default '{}',p_idempotency_key text default null
) returns public.privacy_consents
language plpgsql security definer set search_path=''
as $$
declare purpose public.privacy_purposes; notice public.privacy_notices; r public.privacy_consents;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'privacy.manage_consents') then raise exception 'Permission denied'; end if;
 if p_idempotency_key is not null then select * into r from public.privacy_consents where idempotency_key=p_idempotency_key; if found then return r; end if; end if;
 select * into purpose from public.privacy_purposes p where p.code=p_purpose_code and p.status='active'
 and(p.organization_id=p_organization_id or p.organization_id is null)
 order by case when p.organization_id=p_organization_id then 0 else 1 end limit 1;
 if not found then raise exception 'Privacy purpose not found'; end if;
 if purpose.explicit_consent_required and p_status='granted' and not p_explicit then raise exception 'Explicit consent required'; end if;
 if p_notice_code is not null then
  select * into notice from public.privacy_notices n where n.code=p_notice_code and n.status='active'
   and(n.organization_id=p_organization_id or n.organization_id is null)
  order by case when n.organization_id=p_organization_id then 0 else 1 end,n.version desc limit 1;
 end if;
 insert into public.privacy_consents(
  organization_id,subject_id,purpose_id,notice_id,status,method,explicit_consent,granted_at,denied_at,withdrawn_at,expires_at,proof_data,recorded_by,idempotency_key
 ) values(
  p_organization_id,p_subject_id,purpose.id,notice.id,p_status,p_method,p_explicit,
  case when p_status='granted' then now() end,case when p_status='denied' then now() end,
  case when p_status='withdrawn' then now() end,p_expires_at,coalesce(p_proof_data,'{}'),auth.uid(),p_idempotency_key
 ) returning * into r;
 if p_status in('denied','withdrawn') then
  insert into public.privacy_suppressions(organization_id,subject_id,suppression_type,reason_code,reason,source_type,source_id,created_by)
  values(p_organization_id,p_subject_id,case when purpose.category in('marketing','communication') then 'all_channels' else 'processing' end,
   'CONSENT_'||upper(p_status),'Consent '||p_status||' for '||purpose.code,'privacy_consent',r.id,auth.uid());
 end if;
 perform public.publish_privacy_event(p_organization_id,p_subject_id,'privacy.consent.'||p_status,
  jsonb_build_object('consent_id',r.id,'purpose_code',purpose.code,'status',p_status),'audit','privacy_consent',r.id,20,'privacy-consent:'||r.id::text);
 return r;
end $$;

create or replace function public.check_privacy_consent(
 p_organization_id uuid,p_subject_id uuid,p_purpose_code text
) returns jsonb
language plpgsql stable security definer set search_path=''
as $$
declare purpose public.privacy_purposes; c public.privacy_consents; suppressed boolean;
begin
 select * into purpose from public.privacy_purposes p where p.code=p_purpose_code and p.status='active'
 and(p.organization_id=p_organization_id or p.organization_id is null)
 order by case when p.organization_id=p_organization_id then 0 else 1 end limit 1;
 if not found then return jsonb_build_object('allowed',false,'reason','purpose_not_found'); end if;
 select exists(select 1 from public.privacy_suppressions s where s.organization_id=p_organization_id and s.subject_id=p_subject_id
 and s.status='active' and s.starts_at<=now() and(s.expires_at is null or s.expires_at>now())
 and s.suppression_type in('all_channels','processing')) into suppressed;
 if suppressed then return jsonb_build_object('allowed',false,'reason','suppressed'); end if;
 if not purpose.consent_required then return jsonb_build_object('allowed',true,'reason','consent_not_required','lawful_basis',purpose.lawful_basis); end if;
 select * into c from public.privacy_consents where organization_id=p_organization_id and subject_id=p_subject_id and purpose_id=purpose.id
 order by created_at desc limit 1;
 if not found then return jsonb_build_object('allowed',false,'reason','consent_missing'); end if;
 return jsonb_build_object('allowed',c.status in('granted','not_required') and(c.expires_at is null or c.expires_at>now()),
  'reason',case when c.status not in('granted','not_required') then 'consent_'||c.status when c.expires_at<=now() then 'consent_expired' else 'consent_valid' end,
  'consent_id',c.id,'status',c.status,'expires_at',c.expires_at);
end $$;

create or replace function public.create_privacy_request(
 p_organization_id uuid,p_subject_id uuid,p_request_type text,p_request_source text default 'customer_portal',
 p_request_details text default null,p_jurisdiction_code text default 'IN_DPDP',p_priority text default 'normal',
 p_idempotency_key text default null,p_metadata jsonb default '{}'
) returns public.privacy_requests
language plpgsql security definer set search_path=''
as $$
declare j public.privacy_jurisdictions; r public.privacy_requests;
begin
 if p_idempotency_key is not null then select * into r from public.privacy_requests where idempotency_key=p_idempotency_key; if found then return r; end if; end if;
 select * into j from public.privacy_jurisdictions x where x.code=p_jurisdiction_code and x.status='active'
 and(x.organization_id=p_organization_id or x.organization_id is null)
 order by case when x.organization_id=p_organization_id then 0 else 1 end limit 1;
 if not found then raise exception 'Jurisdiction not found'; end if;
 insert into public.privacy_requests(
  organization_id,subject_id,jurisdiction_id,request_code,request_type,request_source,request_details,priority,due_at,idempotency_key,correlation_id,metadata,created_by,updated_by
 ) values(
  p_organization_id,p_subject_id,j.id,'DSR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
  p_request_type,p_request_source,p_request_details,p_priority,now()+make_interval(days=>j.request_deadline_days),
  p_idempotency_key,gen_random_uuid()::text,coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) returning * into r;
 perform public.initialize_privacy_request_tasks(r.id);
 perform public.publish_privacy_event(p_organization_id,p_subject_id,'privacy.request.created',
  jsonb_build_object('request_id',r.id,'request_code',r.request_code,'request_type',r.request_type,'due_at',r.due_at),
  'notification_engine','privacy_request',r.id,20,'privacy-request:'||r.id::text,r.correlation_id);
 return r;
end $$;

create or replace function public.initialize_privacy_request_tasks(p_request_id uuid)
returns integer language plpgsql security definer set search_path=''
as $$
declare r public.privacy_requests;n integer;
begin
 select * into r from public.privacy_requests where id=p_request_id;
 if not found then raise exception 'Privacy request not found'; end if;
 insert into public.privacy_request_tasks(
  organization_id,request_id,task_code,task_name,task_type,sequence_number,dependency_task_codes,handler_code,destination,input_data,idempotency_key,correlation_id,trace_id
 )
 select r.organization_id,r.id,v.code,v.name,v.typ,v.seq,v.dep,v.handler,v.dest,
 jsonb_build_object('request_id',r.id,'request_type',r.request_type,'subject_id',r.subject_id),
 'privacy-task:'||r.id::text||':'||v.code,r.correlation_id,r.trace_id
 from(values
 ('VERIFY_IDENTITY','Verify identity','identity',10,'{}'::text[],'privacy.identity.verify','service_worker'),
 ('DISCOVER_DATA','Discover subject data','discovery',20,array['VERIFY_IDENTITY']::text[],'privacy.data.discover','service_worker'),
 ('LEGAL_REVIEW','Legal review','legal_review',30,array['DISCOVER_DATA']::text[],'privacy.legal.review','security_governance'),
 ('EXECUTE_REQUEST','Execute request','execute',40,array['LEGAL_REVIEW']::text[],'privacy.request.execute','service_worker'),
 ('PREPARE_RESPONSE','Prepare response','notification',50,array['EXECUTE_REQUEST']::text[],'privacy.response.prepare','document_engine'),
 ('SEND_RESPONSE','Send response','notification',60,array['PREPARE_RESPONSE']::text[],'privacy.response.send','communication_engine')
 )v(code,name,typ,seq,dep,handler,dest)
 on conflict(request_id,task_code) do nothing;
 get diagnostics n=row_count; return n;
end $$;

create or replace function public.claim_privacy_request_task(p_worker_id text,p_destination text default null,p_lock_seconds integer default 300)
returns public.privacy_request_tasks language plpgsql security definer set search_path=''
as $$
declare r public.privacy_request_tasks;
begin
 if auth.role()<>'service_role' then raise exception 'service_role required'; end if;
 update public.privacy_request_tasks set status='failed',available_at=now(),claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,
 last_error_code=coalesce(last_error_code,'LOCK_EXPIRED'),last_error_message=coalesce(last_error_message,'Lock expired'),updated_at=now()
 where status in('claimed','running') and lock_expires_at<=now();
 select * into r from public.privacy_request_tasks t where t.status in('queued','failed') and t.available_at<=now() and t.attempt_count<t.maximum_attempts
 and(p_destination is null or t.destination=p_destination)
 and not exists(select 1 from unnest(t.dependency_task_codes)d where not exists(
  select 1 from public.privacy_request_tasks x where x.request_id=t.request_id and x.task_code=d and x.status in('completed','skipped')))
 order by t.sequence_number,t.created_at for update skip locked limit 1;
 if not found then return null; end if;
 update public.privacy_request_tasks set status='claimed',attempt_count=attempt_count+1,claimed_at=now(),claimed_by=p_worker_id,
 lock_token=gen_random_uuid()::text,lock_expires_at=now()+make_interval(secs=>greatest(p_lock_seconds,1)),started_at=coalesce(started_at,now()),updated_at=now()
 where id=r.id returning * into r; return r;
end $$;

create or replace function public.complete_privacy_request_task(p_task_id uuid,p_lock_token text,p_output jsonb default '{}')
returns public.privacy_request_tasks language plpgsql security definer set search_path=''
as $$
declare r public.privacy_request_tasks;remaining integer;
begin
 if auth.role()<>'service_role' then raise exception 'service_role required'; end if;
 select * into r from public.privacy_request_tasks where id=p_task_id for update;
 if not found or r.lock_token is distinct from p_lock_token then raise exception 'Invalid task or lock'; end if;
 update public.privacy_request_tasks set status='completed',output_data=coalesce(p_output,'{}'),completed_at=now(),claimed_at=null,claimed_by=null,
 lock_token=null,lock_expires_at=null,last_error_code=null,last_error_message=null,last_error_data='{}',updated_at=now()
 where id=r.id returning * into r;
 select count(*) into remaining from public.privacy_request_tasks where request_id=r.request_id and required=true and status not in('completed','skipped');
 update public.privacy_requests set status=case when remaining=0 then 'completed' else 'in_progress' end,
 completed_at=case when remaining=0 then now() else completed_at end,updated_at=now() where id=r.request_id;
 return r;
end $$;

create or replace function public.is_entity_under_privacy_legal_hold(
 p_organization_id uuid,p_entity_type text,p_entity_id uuid,p_subject_id uuid default null
) returns boolean language sql stable security definer set search_path=''
as $$
select exists(
 select 1 from public.privacy_legal_holds h join public.privacy_legal_hold_items i on i.legal_hold_id=h.id
 where h.organization_id=p_organization_id and h.status='active' and h.starts_at<=now() and(h.expires_at is null or h.expires_at>now())
 and i.status='active' and i.entity_type=p_entity_type and(i.entity_id=p_entity_id or(p_subject_id is not null and i.subject_id=p_subject_id))
);
$$;

create or replace function public.create_privacy_retention_job(
 p_organization_id uuid,p_policy_id uuid,p_job_type text,p_criteria jsonb default '{}',p_idempotency_key text default null
) returns public.privacy_retention_jobs language plpgsql security definer set search_path=''
as $$
declare r public.privacy_retention_jobs;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_organization_id,'privacy.manage_retention') then raise exception 'Permission denied'; end if;
 if p_idempotency_key is not null then select * into r from public.privacy_retention_jobs where idempotency_key=p_idempotency_key; if found then return r; end if; end if;
 insert into public.privacy_retention_jobs(organization_id,policy_id,job_code,job_type,criteria,idempotency_key,correlation_id,initiated_by)
 values(p_organization_id,p_policy_id,'RET-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),p_job_type,coalesce(p_criteria,'{}'),p_idempotency_key,gen_random_uuid()::text,auth.uid())
 returning * into r; return r;
end $$;

create or replace function public.claim_privacy_retention_job(p_worker_id text,p_lock_seconds integer default 600)
returns public.privacy_retention_jobs language plpgsql security definer set search_path=''
as $$
declare r public.privacy_retention_jobs;
begin
 if auth.role()<>'service_role' then raise exception 'service_role required'; end if;
 select * into r from public.privacy_retention_jobs where status in('queued','failed') and available_at<=now() and attempt_count<maximum_attempts
 order by created_at for update skip locked limit 1;
 if not found then return null; end if;
 update public.privacy_retention_jobs set status='claimed',attempt_count=attempt_count+1,claimed_at=now(),claimed_by=p_worker_id,
 lock_token=gen_random_uuid()::text,lock_expires_at=now()+make_interval(secs=>greatest(p_lock_seconds,1)),started_at=coalesce(started_at,now()),updated_at=now()
 where id=r.id returning * into r; return r;
end $$;

create or replace function public.claim_privacy_event(p_worker_id text,p_destination text default null,p_lock_seconds integer default 300)
returns public.privacy_event_outbox language plpgsql security definer set search_path=''
as $$
declare r public.privacy_event_outbox;
begin
 if auth.role()<>'service_role' then raise exception 'service_role required'; end if;
 select * into r from public.privacy_event_outbox where status in('pending','failed') and available_at<=now() and delivery_attempts<maximum_attempts
 and(p_destination is null or destination=p_destination) order by priority,created_at for update skip locked limit 1;
 if not found then return null; end if;
 update public.privacy_event_outbox set status='claimed',delivery_attempts=delivery_attempts+1,claimed_at=now(),claimed_by=p_worker_id,
 lock_token=gen_random_uuid()::text,lock_expires_at=now()+make_interval(secs=>greatest(p_lock_seconds,1)),updated_at=now()
 where id=r.id returning * into r; return r;
end $$;

create or replace function public.complete_privacy_event(p_event_id uuid,p_lock_token text,p_result jsonb default '{}')
returns public.privacy_event_outbox language plpgsql security definer set search_path=''
as $$
declare r public.privacy_event_outbox;
begin
 if auth.role()<>'service_role' then raise exception 'service_role required'; end if;
 select * into r from public.privacy_event_outbox where id=p_event_id for update;
 if not found or r.lock_token is distinct from p_lock_token then raise exception 'Invalid event or lock'; end if;
 update public.privacy_event_outbox set status='delivered',delivered_at=now(),payload=payload||jsonb_build_object('delivery_result',coalesce(p_result,'{}')),
 claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now() where id=r.id returning * into r; return r;
end $$;

create or replace view public.privacy_consent_dashboard with(security_invoker=true) as
select c.organization_id,p.code as purpose_code,c.status,c.method,count(*) consent_events,count(distinct c.subject_id) subjects,
count(*) filter(where c.created_at>=now()-interval '30 days') events_last_30d,max(c.created_at) latest_event_at
from public.privacy_consents c join public.privacy_purposes p on p.id=c.purpose_id
group by c.organization_id,p.code,c.status,c.method;

create or replace view public.privacy_request_dashboard with(security_invoker=true) as
select organization_id,request_type,status,priority,count(*) request_count,
count(*) filter(where due_at<now() and status not in('completed','rejected','cancelled','expired')) overdue_count,
min(due_at) filter(where status not in('completed','rejected','cancelled','expired')) next_due_at,max(updated_at) latest_update_at
from public.privacy_requests group by organization_id,request_type,status,priority;

create or replace view public.privacy_incident_dashboard with(security_invoker=true) as
select organization_id,incident_type,severity,status,count(*) incident_count,sum(affected_subject_count) affected_subjects,
sum(affected_record_count) affected_records,max(updated_at) latest_update_at
from public.privacy_incidents group by organization_id,incident_type,severity,status;

grant select on public.privacy_consent_dashboard,public.privacy_request_dashboard,public.privacy_incident_dashboard to authenticated,service_role;

create or replace function public.get_privacy_engine_health(p_organization_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
 if auth.role()<>'service_role' and(p_organization_id is null or not public.has_organization_permission(p_organization_id,'privacy.view_logs')) then raise exception 'Permission denied'; end if;
 return jsonb_build_object(
 'organization_id',p_organization_id,'checked_at',now(),
 'expired_consents',(select count(*) from public.privacy_consents c where c.status='granted' and c.expires_at<=now() and(p_organization_id is null or c.organization_id=p_organization_id)),
 'overdue_requests',(select count(*) from public.privacy_requests r where r.due_at<now() and r.status not in('completed','rejected','cancelled','expired') and(p_organization_id is null or r.organization_id=p_organization_id)),
 'dead_lettered_tasks',(select count(*) from public.privacy_request_tasks t where t.status='dead_lettered' and(p_organization_id is null or t.organization_id=p_organization_id)),
 'active_legal_holds',(select count(*) from public.privacy_legal_holds h where h.status='active' and(p_organization_id is null or h.organization_id=p_organization_id)),
 'open_high_incidents',(select count(*) from public.privacy_incidents i where i.severity in('high','critical') and i.status not in('resolved','closed','false_positive') and(p_organization_id is null or i.organization_id=p_organization_id)),
 'pending_events',(select count(*) from public.privacy_event_outbox e where e.status in('pending','failed','claimed','processing') and(p_organization_id is null or e.organization_id=p_organization_id))
 );
end $$;

-- RLS
do $$
declare t text;
begin
 foreach t in array array[
 'privacy_jurisdictions','privacy_purposes','privacy_notices','privacy_subjects','privacy_consents','privacy_preferences',
 'privacy_suppressions','privacy_classifications','privacy_processing_activities','privacy_requests','privacy_request_tasks',
 'privacy_retention_policies','privacy_legal_holds','privacy_legal_hold_items','privacy_retention_jobs','privacy_incidents',
 'privacy_event_outbox','privacy_logs'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists %I_select_policy on public.%I',t,t);
  execute format('create policy %I_select_policy on public.%I for select to authenticated using(organization_id is null or public.has_organization_permission(organization_id,''privacy.view'') or public.has_organization_permission(organization_id,''privacy.view_all''))',t,t);
  execute format('drop policy if exists %I_service_policy on public.%I',t,t);
  execute format('create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t);
 end loop;
end $$;

grant select on
public.privacy_jurisdictions,public.privacy_purposes,public.privacy_notices,public.privacy_subjects,
public.privacy_consents,public.privacy_preferences,public.privacy_suppressions,public.privacy_classifications,
public.privacy_processing_activities,public.privacy_requests,public.privacy_request_tasks,
public.privacy_retention_policies,public.privacy_legal_holds,public.privacy_legal_hold_items,
public.privacy_retention_jobs,public.privacy_incidents,public.privacy_event_outbox,public.privacy_logs
to authenticated;

grant all on
public.privacy_jurisdictions,public.privacy_purposes,public.privacy_notices,public.privacy_subjects,
public.privacy_consents,public.privacy_preferences,public.privacy_suppressions,public.privacy_classifications,
public.privacy_processing_activities,public.privacy_requests,public.privacy_request_tasks,
public.privacy_retention_policies,public.privacy_legal_holds,public.privacy_legal_hold_items,
public.privacy_retention_jobs,public.privacy_incidents,public.privacy_event_outbox,public.privacy_logs
to service_role;

-- Seeds
insert into public.privacy_jurisdictions(organization_id,code,name,country_code,regulation,request_deadline_days,breach_notification_hours,config)
values
(null,'IN_DPDP','India DPDP','IN','Digital Personal Data Protection',30,null,jsonb_build_object('grievance_required',true)),
(null,'EU_GDPR','EU GDPR',null,'General Data Protection Regulation',30,72,jsonb_build_object('portability',true))
on conflict do nothing;

insert into public.privacy_purposes(organization_id,code,name,category,lawful_basis,consent_required,explicit_consent_required,withdrawal_allowed,retention_days,data_categories)
values
(null,'service_delivery','Service Delivery','service_delivery','contract',false,false,false,2555,array['identity','contact','transactional']),
(null,'marketing','Marketing','marketing','consent',true,false,true,730,array['identity','contact','preferences']),
(null,'transactional_communication','Transactional Communication','communication','contract',false,false,false,2555,array['identity','contact']),
(null,'ai_calling','AI Calling and Qualification','ai_processing','consent',true,true,true,365,array['identity','contact','voice']),
(null,'analytics','Product Analytics','analytics','legitimate_interest',false,false,true,730,array['usage','device','behavioral']),
(null,'security_fraud','Security and Fraud Prevention','security','legitimate_interest',false,false,false,1095,array['identity','device','security_logs'])
on conflict do nothing;

insert into public.privacy_classifications(organization_id,code,name,sensitivity,category,encryption_required,masking_required,access_logging_required,retention_days)
values
(null,'PUBLIC','Public',0,'public',false,false,false,null),
(null,'INTERNAL','Internal',1,'internal',false,false,true,1095),
(null,'PERSONAL','Personal Data',3,'personal_data',true,true,true,730),
(null,'SENSITIVE','Sensitive Personal Data',5,'sensitive_personal_data',true,true,true,365),
(null,'AUTHENTICATION','Authentication Data',5,'authentication',true,true,true,365),
(null,'FINANCIAL','Financial Data',5,'financial',true,true,true,2920)
on conflict do nothing;

-- Validation
do $$
declare n integer;
begin
 select count(*) into n from information_schema.tables where table_schema='public' and table_name in(
 'privacy_jurisdictions','privacy_purposes','privacy_notices','privacy_subjects','privacy_consents',
 'privacy_preferences','privacy_suppressions','privacy_classifications','privacy_processing_activities',
 'privacy_requests','privacy_request_tasks','privacy_retention_policies','privacy_legal_holds',
 'privacy_legal_hold_items','privacy_retention_jobs','privacy_incidents','privacy_event_outbox','privacy_logs');
 if n<>18 then raise exception '035 validation failed: expected 18 privacy tables, found %',n; end if;
end $$;

insert into public.privacy_logs(organization_id,log_level,event_name,message,source_type,log_data)
select o.id,'info','migration.035.completed','Data Privacy, Consent and Retention Engine migration 035 completed','migration',
jsonb_build_object('migration','035_data_privacy_consent_retention_engine','completed_at',now(),
'modules',jsonb_build_array('jurisdictions','purposes','notices','subjects','consents','preferences','suppression',
'classifications','processing_activities','data_subject_requests','retention','legal_holds','incidents','event_outbox','analytics'))
from public.organizations o
where not exists(select 1 from public.privacy_logs l where l.organization_id=o.id and l.event_name='migration.035.completed');

commit;