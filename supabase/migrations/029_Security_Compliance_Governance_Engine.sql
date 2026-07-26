-- ============================================================
-- SalesSetu Enterprise
-- Migration 029: Security, Compliance & Governance Engine
-- PostgreSQL / Supabase
-- ============================================================
begin;
create extension if not exists pgcrypto;


insert into public.permissions(module,action,code,description)
select v.module,v.action,v.code,v.description
from (values
('security_governance','view','security_governance.view','View security and governance data'),
('security_governance','view_all','security_governance.view_all','View all organization security and governance data'),
('security_governance','manage_frameworks','security_governance.manage_frameworks','Manage compliance frameworks and controls'),
('security_governance','manage_policies','security_governance.manage_policies','Manage security and compliance policies'),
('security_governance','publish_policies','security_governance.publish_policies','Publish security and compliance policies'),
('security_governance','manage_risks','security_governance.manage_risks','Manage security and compliance risks'),
('security_governance','manage_assessments','security_governance.manage_assessments','Manage compliance and risk assessments'),
('security_governance','manage_findings','security_governance.manage_findings','Manage findings and remediation'),
('security_governance','manage_data_governance','security_governance.manage_data_governance','Manage data classification, retention and legal holds'),
('security_governance','manage_access_reviews','security_governance.manage_access_reviews','Manage access reviews'),
('security_governance','manage_sod','security_governance.manage_sod','Manage segregation-of-duties rules'),
('security_governance','request_privileged_access','security_governance.request_privileged_access','Request privileged access'),
('security_governance','approve_privileged_access','security_governance.approve_privileged_access','Approve privileged access'),
('security_governance','manage_incidents','security_governance.manage_incidents','Manage security incidents'),
('security_governance','manage_privacy_requests','security_governance.manage_privacy_requests','Manage privacy requests'),
('security_governance','manage_evidence','security_governance.manage_evidence','Manage compliance evidence'),
('security_governance','view_sensitive','security_governance.view_sensitive','View sensitive security and privacy data'),
('security_governance','view_logs','security_governance.view_logs','View security governance logs'),
('security_governance','view_analytics','security_governance.view_analytics','View security governance analytics')
) as v(module,action,code,description)
where not exists (
  select 1 from public.permissions p where p.code=v.code
);


create table if not exists public.security_governance_frameworks (
id uuid primary key default gen_random_uuid(),
organization_id uuid references public.organizations(id) on delete cascade,
framework_code text not null,
framework_name text not null,
framework_version text,
framework_type text not null default 'custom' check (framework_type in ('standard','regulation','contractual','internal','industry','custom')),
jurisdiction text,
description text,
status text not null default 'active' check (status in ('active','inactive','deprecated','archived')),
is_system_framework boolean not null default false,
configuration jsonb not null default '{}',
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,framework_code,framework_version)
);


create table if not exists public.security_governance_controls (
id uuid primary key default gen_random_uuid(),
organization_id uuid references public.organizations(id) on delete cascade,
framework_id uuid references public.security_governance_frameworks(id) on delete cascade,
control_code text not null,
control_name text not null,
control_domain text,
description text,
objective text,
control_type text not null default 'preventive' check (control_type in ('preventive','detective','corrective','deterrent','compensating','directive','recovery','custom')),
implementation_type text not null default 'hybrid' check (implementation_type in ('manual','automated','hybrid')),
frequency text not null default 'continuous',
evidence_requirements jsonb not null default '[]',
test_procedure jsonb not null default '{}',
status text not null default 'active' check (status in ('draft','active','inactive','deprecated','archived')),
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,framework_id,control_code)
);


create table if not exists public.security_governance_policies (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
policy_code text not null,
policy_name text not null,
description text,
policy_type text not null check (policy_type in ('information_security','privacy','access_control','acceptable_use','data_retention','incident_response','business_continuity','vendor_security','secure_development','change_management','risk_management','compliance','internal_control','custom')),
owner_user_id uuid references auth.users(id) on delete set null,
approver_user_ids uuid[] not null default '{}',
status text not null default 'draft' check (status in ('draft','under_review','approved','published','superseded','retired','archived')),
effective_from date,
review_due_at date,
expires_at date,
acknowledgement_required boolean not null default false,
acknowledgement_interval_days integer,
tags text[] not null default '{}',
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,policy_code)
);


create table if not exists public.security_governance_policy_versions (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
policy_id uuid not null references public.security_governance_policies(id) on delete cascade,
version_number integer not null,
version_label text,
title text not null,
policy_text text not null,
policy_json jsonb not null default '{}',
document_id uuid references public.documents(id) on delete set null,
status text not null default 'draft' check (status in ('draft','under_review','approved','published','superseded','archived')),
is_current boolean not null default false,
approved_by uuid references auth.users(id) on delete set null,
approved_at timestamptz,
published_by uuid references auth.users(id) on delete set null,
published_at timestamptz,
change_summary text,
created_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
unique (policy_id,version_number)
);


create table if not exists public.security_governance_policy_attestations (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
policy_id uuid not null references public.security_governance_policies(id) on delete cascade,
policy_version_id uuid not null references public.security_governance_policy_versions(id) on delete cascade,
user_id uuid not null references auth.users(id) on delete cascade,
attestation_status text not null default 'pending' check (attestation_status in ('pending','acknowledged','declined','expired')),
acknowledgement_text text,
acknowledged_at timestamptz,
declined_at timestamptz,
decline_reason text,
due_at timestamptz,
reminder_count integer not null default 0,
last_reminder_at timestamptz,
ip_address inet,
user_agent text,
metadata jsonb not null default '{}',
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (policy_version_id,user_id)
);


create table if not exists public.security_governance_data_classifications (
id uuid primary key default gen_random_uuid(),
organization_id uuid references public.organizations(id) on delete cascade,
classification_code text not null,
classification_name text not null,
description text,
sensitivity_level integer not null default 1 check (sensitivity_level between 1 and 10),
handling_requirements jsonb not null default '{}',
encryption_required boolean not null default false,
masking_required boolean not null default false,
access_logging_required boolean not null default true,
default_retention_days integer,
status text not null default 'active' check (status in ('active','inactive','archived')),
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,classification_code)
);


create table if not exists public.security_governance_data_assets (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
asset_code text not null,
asset_name text not null,
asset_type text not null check (asset_type in ('database','table','column','document','file','api','integration','storage_bucket','report','dataset','model','application','device','custom')),
asset_reference text,
source_system text,
owner_user_id uuid references auth.users(id) on delete set null,
custodian_user_id uuid references auth.users(id) on delete set null,
classification_id uuid references public.security_governance_data_classifications(id) on delete set null,
contains_personal_data boolean not null default false,
contains_sensitive_personal_data boolean not null default false,
contains_financial_data boolean not null default false,
contains_authentication_data boolean not null default false,
data_subject_categories text[] not null default '{}',
data_categories text[] not null default '{}',
residency_locations text[] not null default '{}',
processing_purposes text[] not null default '{}',
status text not null default 'active' check (status in ('active','inactive','deprecated','archived','disposed')),
last_reviewed_at timestamptz,
next_review_due_at timestamptz,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,asset_code)
);


create table if not exists public.security_governance_retention_policies (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
retention_code text not null,
retention_name text not null,
description text,
applies_to_asset_types text[] not null default '{}',
applies_to_classification_ids uuid[] not null default '{}',
applies_to_data_categories text[] not null default '{}',
retention_period_days integer not null check (retention_period_days >= 0),
retention_start_event text not null default 'created_at',
disposal_action text not null default 'delete' check (disposal_action in ('delete','anonymize','archive','review','custom')),
legal_basis text,
exception_rules jsonb not null default '[]',
status text not null default 'active' check (status in ('draft','active','inactive','archived')),
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,retention_code)
);


create table if not exists public.security_governance_legal_holds (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
hold_code text not null,
hold_name text not null,
description text,
matter_reference text,
issuing_authority text,
status text not null default 'active' check (status in ('draft','active','released','expired','archived')),
effective_from timestamptz not null default now(),
expires_at timestamptz,
released_at timestamptz,
owner_user_id uuid references auth.users(id) on delete set null,
released_by uuid references auth.users(id) on delete set null,
release_reason text,
instructions jsonb not null default '{}',
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,hold_code)
);


create table if not exists public.security_governance_legal_hold_assets (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
legal_hold_id uuid not null references public.security_governance_legal_holds(id) on delete cascade,
data_asset_id uuid not null references public.security_governance_data_assets(id) on delete cascade,
hold_reason text,
added_by uuid references auth.users(id) on delete set null,
added_at timestamptz not null default now(),
released_at timestamptz,
metadata jsonb not null default '{}',
unique (legal_hold_id,data_asset_id)
);


create table if not exists public.security_governance_risks (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
risk_code text not null,
risk_name text not null,
description text,
risk_category text not null check (risk_category in ('cybersecurity','privacy','compliance','operational','third_party','data','financial','legal','business_continuity','technology','fraud','custom')),
risk_source text,
related_entity_type text,
related_entity_id uuid,
owner_user_id uuid references auth.users(id) on delete set null,
inherent_likelihood integer not null default 1 check (inherent_likelihood between 1 and 5),
inherent_impact integer not null default 1 check (inherent_impact between 1 and 5),
inherent_score integer generated always as (inherent_likelihood * inherent_impact) stored,
residual_likelihood integer check (residual_likelihood between 1 and 5),
residual_impact integer check (residual_impact between 1 and 5),
residual_score integer generated always as (case when residual_likelihood is null or residual_impact is null then null else residual_likelihood * residual_impact end) stored,
risk_appetite text not null default 'medium' check (risk_appetite in ('very_low','low','medium','high','very_high')),
treatment_strategy text not null default 'mitigate' check (treatment_strategy in ('accept','avoid','mitigate','transfer','monitor','custom')),
treatment_plan text,
status text not null default 'open' check (status in ('open','assessed','treatment_planned','mitigating','accepted','closed','archived')),
target_date date,
last_assessed_at timestamptz,
next_assessment_due_at timestamptz,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,risk_code)
);


create table if not exists public.security_governance_assessments (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
assessment_code text not null,
assessment_name text not null,
description text,
assessment_type text not null check (assessment_type in ('compliance','risk','privacy','security','vendor','internal_audit','control_self_assessment','readiness','custom')),
framework_id uuid references public.security_governance_frameworks(id) on delete set null,
scope_definition jsonb not null default '{}',
assessor_user_ids uuid[] not null default '{}',
owner_user_id uuid references auth.users(id) on delete set null,
status text not null default 'draft' check (status in ('draft','planned','in_progress','under_review','completed','cancelled','archived')),
planned_start_at timestamptz,
planned_end_at timestamptz,
started_at timestamptz,
completed_at timestamptz,
overall_score numeric(8,4),
overall_rating text,
summary text,
conclusion text,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,assessment_code)
);


create table if not exists public.security_governance_control_tests (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
assessment_id uuid references public.security_governance_assessments(id) on delete cascade,
control_id uuid not null references public.security_governance_controls(id) on delete cascade,
test_code text not null,
test_name text not null,
test_type text not null default 'operating_effectiveness',
procedure_performed text,
expected_result text,
actual_result text,
result_status text not null default 'not_started' check (result_status in ('not_started','in_progress','passed','failed','partially_passed','not_applicable','cancelled')),
score numeric(8,4),
tested_by uuid references auth.users(id) on delete set null,
reviewed_by uuid references auth.users(id) on delete set null,
started_at timestamptz,
completed_at timestamptz,
reviewed_at timestamptz,
metadata jsonb not null default '{}',
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,assessment_id,test_code)
);


create table if not exists public.security_governance_evidence (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
evidence_code text not null,
evidence_name text not null,
description text,
evidence_type text not null check (evidence_type in ('document','screenshot','log','report','query_result','configuration','attestation','interview','sample','external_reference','custom')),
document_id uuid references public.documents(id) on delete set null,
external_reference text,
source_system text,
source_entity_type text,
source_entity_id uuid,
collected_by uuid references auth.users(id) on delete set null,
collected_at timestamptz not null default now(),
period_start timestamptz,
period_end timestamptz,
checksum text,
immutable_reference text,
confidentiality_level text not null default 'internal' check (confidentiality_level in ('public','internal','confidential','restricted')),
status text not null default 'active' check (status in ('active','superseded','expired','rejected','archived')),
expires_at timestamptz,
metadata jsonb not null default '{}',
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,evidence_code)
);


create table if not exists public.security_governance_evidence_links (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
evidence_id uuid not null references public.security_governance_evidence(id) on delete cascade,
target_type text not null,
target_id uuid not null,
relationship_type text not null default 'supports',
notes text,
created_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
unique (evidence_id,target_type,target_id,relationship_type)
);


create table if not exists public.security_governance_findings (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
finding_code text not null,
finding_name text not null,
description text,
finding_type text not null check (finding_type in ('control_deficiency','nonconformity','vulnerability','privacy_gap','policy_exception','access_issue','sod_violation','incident_issue','audit_observation','custom')),
source_type text,
source_id uuid,
control_id uuid references public.security_governance_controls(id) on delete set null,
risk_id uuid references public.security_governance_risks(id) on delete set null,
assessment_id uuid references public.security_governance_assessments(id) on delete set null,
severity text not null default 'medium' check (severity in ('informational','low','medium','high','critical')),
likelihood integer check (likelihood between 1 and 5),
impact integer check (impact between 1 and 5),
risk_score integer generated always as (case when likelihood is null or impact is null then null else likelihood * impact end) stored,
owner_user_id uuid references auth.users(id) on delete set null,
status text not null default 'open' check (status in ('open','triaged','accepted','remediation_planned','in_progress','resolved','verified','closed','reopened','archived')),
due_at timestamptz,
resolved_at timestamptz,
verified_at timestamptz,
root_cause text,
management_response text,
acceptance_reason text,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,finding_code)
);


create table if not exists public.security_governance_remediation_actions (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
finding_id uuid not null references public.security_governance_findings(id) on delete cascade,
action_code text not null,
action_name text not null,
description text,
action_type text not null default 'corrective',
owner_user_id uuid references auth.users(id) on delete set null,
status text not null default 'open' check (status in ('open','planned','in_progress','blocked','completed','verified','cancelled')),
priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
planned_start_at timestamptz,
due_at timestamptz,
started_at timestamptz,
completed_at timestamptz,
verified_at timestamptz,
completion_evidence jsonb not null default '{}',
verification_notes text,
workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (finding_id,action_code)
);


create table if not exists public.security_governance_access_reviews (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
review_code text not null,
review_name text not null,
description text,
review_type text not null check (review_type in ('user_access','role_access','privileged_access','application_access','data_access','third_party_access','custom')),
scope_definition jsonb not null default '{}',
reviewer_user_ids uuid[] not null default '{}',
owner_user_id uuid references auth.users(id) on delete set null,
status text not null default 'draft' check (status in ('draft','planned','in_progress','under_review','completed','cancelled','archived')),
planned_start_at timestamptz,
due_at timestamptz,
started_at timestamptz,
completed_at timestamptz,
total_items integer not null default 0,
approved_items integer not null default 0,
revoked_items integer not null default 0,
modified_items integer not null default 0,
pending_items integer not null default 0,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,review_code)
);


create table if not exists public.security_governance_access_review_items (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
access_review_id uuid not null references public.security_governance_access_reviews(id) on delete cascade,
subject_type text not null,
subject_id uuid,
subject_reference text,
access_type text not null,
access_reference text not null,
access_details jsonb not null default '{}',
risk_level text not null default 'medium' check (risk_level in ('low','medium','high','critical')),
reviewer_user_id uuid references auth.users(id) on delete set null,
decision text not null default 'pending' check (decision in ('pending','approve','revoke','modify','escalate','not_applicable')),
decision_notes text,
decided_at timestamptz,
remediation_status text not null default 'not_required' check (remediation_status in ('not_required','pending','in_progress','completed','failed')),
remediated_at timestamptz,
metadata jsonb not null default '{}',
created_at timestamptz not null default now(),
updated_at timestamptz not null default now()
);


create table if not exists public.security_governance_sod_rules (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
rule_code text not null,
rule_name text not null,
description text,
conflict_type text not null default 'permission' check (conflict_type in ('permission','role','process','approval','data','custom')),
left_side jsonb not null,
right_side jsonb not null,
severity text not null default 'high' check (severity in ('low','medium','high','critical')),
enforcement_mode text not null default 'detect' check (enforcement_mode in ('detect','warn','block','require_approval')),
status text not null default 'active' check (status in ('active','inactive','archived')),
exception_process jsonb not null default '{}',
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,rule_code)
);


create table if not exists public.security_governance_sod_violations (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
sod_rule_id uuid not null references public.security_governance_sod_rules(id) on delete cascade,
subject_type text not null,
subject_id uuid,
subject_reference text,
detected_access jsonb not null default '{}',
status text not null default 'open' check (status in ('open','under_review','approved_exception','remediating','resolved','false_positive','archived')),
severity text not null,
detected_at timestamptz not null default now(),
owner_user_id uuid references auth.users(id) on delete set null,
exception_expires_at timestamptz,
exception_reason text,
approved_by uuid references auth.users(id) on delete set null,
resolved_at timestamptz,
resolution_notes text,
metadata jsonb not null default '{}',
created_at timestamptz not null default now(),
updated_at timestamptz not null default now()
);


create table if not exists public.security_governance_privileged_access_requests (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
request_code text not null,
requester_user_id uuid references auth.users(id) on delete set null,
access_type text not null,
resource_type text not null,
resource_reference text not null,
requested_permissions text[] not null default '{}',
business_justification text not null,
requested_start_at timestamptz,
requested_end_at timestamptz,
risk_level text not null default 'high' check (risk_level in ('low','medium','high','critical')),
status text not null default 'pending' check (status in ('pending','approved','rejected','active','expired','revoked','cancelled')),
approver_user_ids uuid[] not null default '{}',
approved_by uuid references auth.users(id) on delete set null,
approved_at timestamptz,
rejected_by uuid references auth.users(id) on delete set null,
rejected_at timestamptz,
rejection_reason text,
activated_at timestamptz,
expired_at timestamptz,
revoked_at timestamptz,
revoked_by uuid references auth.users(id) on delete set null,
revocation_reason text,
credential_reference text,
session_reference text,
metadata jsonb not null default '{}',
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,request_code)
);


create table if not exists public.security_governance_incidents (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
incident_code text not null,
incident_title text not null,
description text,
incident_type text not null check (incident_type in ('unauthorized_access','data_exposure','data_loss','malware','phishing','credential_compromise','service_disruption','fraud','privacy_incident','policy_violation','third_party_incident','vulnerability_exploitation','custom')),
severity text not null default 'medium' check (severity in ('informational','low','medium','high','critical')),
priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
status text not null default 'reported' check (status in ('reported','triaged','investigating','contained','eradicated','recovering','resolved','closed','false_positive','archived')),
source_type text,
source_reference text,
related_entity_type text,
related_entity_id uuid,
incident_owner_id uuid references auth.users(id) on delete set null,
response_team_user_ids uuid[] not null default '{}',
detected_at timestamptz,
reported_at timestamptz not null default now(),
triaged_at timestamptz,
contained_at timestamptz,
resolved_at timestamptz,
closed_at timestamptz,
affected_systems text[] not null default '{}',
affected_data_assets uuid[] not null default '{}',
affected_subject_count integer,
personal_data_involved boolean not null default false,
sensitive_data_involved boolean not null default false,
root_cause text,
containment_actions text,
remediation_summary text,
lessons_learned text,
regulatory_notification_required boolean,
customer_notification_required boolean,
workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,incident_code)
);


create table if not exists public.security_governance_incident_events (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
incident_id uuid not null references public.security_governance_incidents(id) on delete cascade,
event_type text not null,
event_summary text not null,
event_data jsonb not null default '{}',
performed_by uuid references auth.users(id) on delete set null,
occurred_at timestamptz not null default now(),
correlation_id text,
trace_id text,
created_at timestamptz not null default now()
);


create table if not exists public.security_governance_breach_assessments (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
incident_id uuid not null references public.security_governance_incidents(id) on delete cascade,
assessment_code text not null,
assessment_status text not null default 'draft' check (assessment_status in ('draft','in_progress','completed','reopened','archived')),
personal_data_breach boolean,
risk_to_individuals text check (risk_to_individuals in ('none','low','medium','high','unknown')),
notification_required boolean,
notification_deadline timestamptz,
regulator_notification_status text not null default 'not_required',
data_subject_notification_status text not null default 'not_required',
facts jsonb not null default '{}',
risk_analysis text,
decision_rationale text,
assessed_by uuid references auth.users(id) on delete set null,
reviewed_by uuid references auth.users(id) on delete set null,
completed_at timestamptz,
reviewed_at timestamptz,
metadata jsonb not null default '{}',
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (incident_id,assessment_code)
);


create table if not exists public.security_governance_privacy_requests (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
request_code text not null,
request_type text not null check (request_type in ('access','correction','deletion','restriction','portability','objection','consent_withdrawal','complaint','information','custom')),
requester_type text not null default 'data_subject',
requester_reference text,
requester_name text,
requester_email text,
requester_phone text,
related_contact_type text,
related_contact_id uuid,
identity_verification_status text not null default 'pending' check (identity_verification_status in ('pending','verified','failed','waived')),
identity_verified_at timestamptz,
identity_verified_by uuid references auth.users(id) on delete set null,
status text not null default 'received' check (status in ('received','identity_verification','in_progress','waiting_requester','waiting_third_party','approved','partially_approved','rejected','completed','cancelled','overdue','archived')),
priority text not null default 'normal' check (priority in ('low','normal','high','urgent')),
received_at timestamptz not null default now(),
due_at timestamptz,
completed_at timestamptz,
owner_user_id uuid references auth.users(id) on delete set null,
request_details text,
scope_definition jsonb not null default '{}',
decision text,
decision_reason text,
response_summary text,
response_document_id uuid references public.documents(id) on delete set null,
workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,request_code)
);


create table if not exists public.security_governance_third_parties (
id uuid primary key default gen_random_uuid(),
organization_id uuid not null references public.organizations(id) on delete cascade,
third_party_code text not null,
third_party_name text not null,
third_party_type text not null default 'vendor',
service_description text,
owner_user_id uuid references auth.users(id) on delete set null,
risk_tier text not null default 'medium' check (risk_tier in ('low','medium','high','critical')),
handles_personal_data boolean not null default false,
handles_sensitive_data boolean not null default false,
has_system_access boolean not null default false,
countries_of_operation text[] not null default '{}',
data_processing_locations text[] not null default '{}',
status text not null default 'prospective' check (status in ('prospective','under_review','approved','active','suspended','terminated','archived')),
contract_start_date date,
contract_end_date date,
next_review_due_at date,
metadata jsonb not null default '{}',
created_by uuid references auth.users(id) on delete set null,
updated_by uuid references auth.users(id) on delete set null,
created_at timestamptz not null default now(),
updated_at timestamptz not null default now(),
unique (organization_id,third_party_code)
);


create table if not exists public.security_governance_event_outbox (
id uuid primary key default gen_random_uuid(),
organization_id uuid references public.organizations(id) on delete cascade,
event_name text not null,
source_type text,
source_id uuid,
destination text not null default 'internal' check (destination in ('internal','automation_engine','enterprise_workflow','communication_engine','notification_engine','integration_api','ai_intelligence','reporting','mobile','n8n','analytics','audit','webhook')),
status text not null default 'pending' check (status in ('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
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


create table if not exists public.security_governance_logs (
id uuid primary key default gen_random_uuid(),
organization_id uuid references public.organizations(id) on delete set null,
log_level text not null default 'info' check (log_level in ('debug','info','warning','error','critical')),
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


create unique index if not exists security_governance_frameworks_system_idx
on public.security_governance_frameworks(framework_code,coalesce(framework_version,''))
where organization_id is null;

create unique index if not exists security_governance_classifications_system_idx
on public.security_governance_data_classifications(classification_code)
where organization_id is null;

create unique index if not exists security_governance_policy_versions_current_idx
on public.security_governance_policy_versions(policy_id)
where is_current=true;

create unique index if not exists security_governance_event_outbox_idem_idx
on public.security_governance_event_outbox(organization_id,idempotency_key)
where idempotency_key is not null;

create index if not exists security_governance_risks_score_idx
on public.security_governance_risks(organization_id,status,inherent_score desc,residual_score desc);

create index if not exists security_governance_findings_priority_idx
on public.security_governance_findings(organization_id,status,severity,due_at);

create index if not exists security_governance_incidents_active_idx
on public.security_governance_incidents(organization_id,status,severity,reported_at desc);

create index if not exists security_governance_privacy_due_idx
on public.security_governance_privacy_requests(organization_id,status,due_at);

create index if not exists security_governance_logs_org_time_idx
on public.security_governance_logs(organization_id,created_at desc);


do $$
declare t text;
begin
  foreach t in array array['security_governance_frameworks','security_governance_controls','security_governance_policies','security_governance_policy_attestations','security_governance_data_classifications','security_governance_data_assets','security_governance_retention_policies','security_governance_legal_holds','security_governance_risks','security_governance_assessments','security_governance_control_tests','security_governance_evidence','security_governance_findings','security_governance_remediation_actions','security_governance_access_reviews','security_governance_access_review_items','security_governance_sod_rules','security_governance_sod_violations','security_governance_privileged_access_requests','security_governance_incidents','security_governance_breach_assessments','security_governance_privacy_requests','security_governance_third_parties','security_governance_event_outbox']
  loop
    execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
    execute format(
      'create trigger %I_set_updated_at before update on public.%I
       for each row execute function public.set_updated_at()',t,t
    );
  end loop;
end;
$$;


create or replace function public.create_security_governance_policy(
  requested_organization_id uuid,
  requested_policy_code text,
  requested_policy_name text,
  requested_policy_type text,
  requested_description text default null,
  requested_owner_user_id uuid default null,
  requested_acknowledgement_required boolean default false,
  requested_review_due_at date default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.security_governance_policies
language plpgsql security definer set search_path=''
as $$
declare r public.security_governance_policies;
begin
  if auth.role()<>'service_role'
     and not public.has_organization_permission(requested_organization_id,'security_governance.manage_policies')
  then raise exception 'Permission denied'; end if;

  insert into public.security_governance_policies(
    organization_id,policy_code,policy_name,description,policy_type,owner_user_id,
    status,acknowledgement_required,review_due_at,metadata,created_by,updated_by
  )
  values(
    requested_organization_id,requested_policy_code,requested_policy_name,
    requested_description,requested_policy_type,requested_owner_user_id,'draft',
    requested_acknowledgement_required,requested_review_due_at,
    coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
  )
  on conflict(organization_id,policy_code) do update set
    policy_name=excluded.policy_name,
    description=excluded.description,
    policy_type=excluded.policy_type,
    owner_user_id=excluded.owner_user_id,
    acknowledgement_required=excluded.acknowledgement_required,
    review_due_at=excluded.review_due_at,
    metadata=excluded.metadata,
    updated_by=auth.uid(),
    updated_at=now()
  returning * into r;
  return r;
end;
$$;

create or replace function public.create_security_governance_policy_version(
  requested_policy_id uuid,
  requested_title text,
  requested_policy_text text,
  requested_policy_json jsonb default '{}'::jsonb,
  requested_document_id uuid default null,
  requested_change_summary text default null
)
returns public.security_governance_policy_versions
language plpgsql security definer set search_path=''
as $$
declare p public.security_governance_policies; n integer; r public.security_governance_policy_versions;
begin
  select * into p from public.security_governance_policies where id=requested_policy_id for update;
  if not found then raise exception 'Security policy not found'; end if;
  if auth.role()<>'service_role'
     and not public.has_organization_permission(p.organization_id,'security_governance.manage_policies')
  then raise exception 'Permission denied'; end if;

  select coalesce(max(version_number),0)+1 into n
  from public.security_governance_policy_versions where policy_id=p.id;

  update public.security_governance_policy_versions
  set is_current=false where policy_id=p.id and is_current=true;

  insert into public.security_governance_policy_versions(
    organization_id,policy_id,version_number,version_label,title,policy_text,
    policy_json,document_id,status,is_current,change_summary,created_by
  )
  values(
    p.organization_id,p.id,n,'Version '||n,requested_title,requested_policy_text,
    coalesce(requested_policy_json,'{}'),requested_document_id,'draft',true,
    requested_change_summary,auth.uid()
  )
  returning * into r;
  return r;
end;
$$;

create or replace function public.publish_security_governance_policy_version(
  requested_version_id uuid,
  requested_effective_from date default current_date,
  requested_review_due_at date default null
)
returns public.security_governance_policy_versions
language plpgsql security definer set search_path=''
as $$
declare v public.security_governance_policy_versions; p public.security_governance_policies;
begin
  select * into v from public.security_governance_policy_versions
  where id=requested_version_id for update;
  if not found then raise exception 'Policy version not found'; end if;

  select * into p from public.security_governance_policies where id=v.policy_id for update;
  if auth.role()<>'service_role'
     and not public.has_organization_permission(p.organization_id,'security_governance.publish_policies')
  then raise exception 'Permission denied'; end if;

  update public.security_governance_policy_versions
  set status='superseded',is_current=false
  where policy_id=p.id and status='published' and id<>v.id;

  update public.security_governance_policy_versions
  set status='published',is_current=true,
      approved_by=coalesce(approved_by,auth.uid()),
      approved_at=coalesce(approved_at,now()),
      published_by=auth.uid(),published_at=now()
  where id=v.id returning * into v;

  update public.security_governance_policies
  set status='published',effective_from=requested_effective_from,
      review_due_at=coalesce(requested_review_due_at,review_due_at),
      updated_by=auth.uid(),updated_at=now()
  where id=p.id;

  return v;
end;
$$;

create or replace function public.attest_security_governance_policy(
  requested_policy_version_id uuid,
  requested_attestation_status text,
  requested_acknowledgement_text text default null,
  requested_decline_reason text default null,
  requested_ip_address inet default null,
  requested_user_agent text default null
)
returns public.security_governance_policy_attestations
language plpgsql security definer set search_path=''
as $$
declare v public.security_governance_policy_versions; r public.security_governance_policy_attestations;
begin
  select * into v from public.security_governance_policy_versions
  where id=requested_policy_version_id and status='published';
  if not found then raise exception 'Published policy version not found'; end if;
  if auth.uid() is null then raise exception 'Authenticated user required'; end if;
  if requested_attestation_status not in ('acknowledged','declined')
  then raise exception 'Invalid attestation status'; end if;

  insert into public.security_governance_policy_attestations(
    organization_id,policy_id,policy_version_id,user_id,attestation_status,
    acknowledgement_text,acknowledged_at,declined_at,decline_reason,ip_address,user_agent
  )
  values(
    v.organization_id,v.policy_id,v.id,auth.uid(),requested_attestation_status,
    requested_acknowledgement_text,
    case when requested_attestation_status='acknowledged' then now() end,
    case when requested_attestation_status='declined' then now() end,
    requested_decline_reason,requested_ip_address,requested_user_agent
  )
  on conflict(policy_version_id,user_id) do update set
    attestation_status=excluded.attestation_status,
    acknowledgement_text=excluded.acknowledgement_text,
    acknowledged_at=excluded.acknowledged_at,
    declined_at=excluded.declined_at,
    decline_reason=excluded.decline_reason,
    ip_address=excluded.ip_address,
    user_agent=excluded.user_agent,
    updated_at=now()
  returning * into r;
  return r;
end;
$$;

create or replace function public.register_security_governance_risk(
  requested_organization_id uuid,
  requested_risk_code text,
  requested_risk_name text,
  requested_risk_category text,
  requested_description text default null,
  requested_owner_user_id uuid default null,
  requested_inherent_likelihood integer default 1,
  requested_inherent_impact integer default 1,
  requested_treatment_strategy text default 'mitigate',
  requested_target_date date default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.security_governance_risks
language plpgsql security definer set search_path=''
as $$
declare r public.security_governance_risks;
begin
  if auth.role()<>'service_role'
     and not public.has_organization_permission(requested_organization_id,'security_governance.manage_risks')
  then raise exception 'Permission denied'; end if;

  insert into public.security_governance_risks(
    organization_id,risk_code,risk_name,description,risk_category,owner_user_id,
    inherent_likelihood,inherent_impact,treatment_strategy,status,target_date,
    metadata,created_by,updated_by
  )
  values(
    requested_organization_id,requested_risk_code,requested_risk_name,
    requested_description,requested_risk_category,requested_owner_user_id,
    requested_inherent_likelihood,requested_inherent_impact,
    requested_treatment_strategy,'open',requested_target_date,
    coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
  )
  on conflict(organization_id,risk_code) do update set
    risk_name=excluded.risk_name,
    description=excluded.description,
    risk_category=excluded.risk_category,
    owner_user_id=excluded.owner_user_id,
    inherent_likelihood=excluded.inherent_likelihood,
    inherent_impact=excluded.inherent_impact,
    treatment_strategy=excluded.treatment_strategy,
    target_date=excluded.target_date,
    metadata=excluded.metadata,
    updated_by=auth.uid(),
    updated_at=now()
  returning * into r;
  return r;
end;
$$;

create or replace function public.open_security_governance_finding(
  requested_organization_id uuid,
  requested_finding_code text,
  requested_finding_name text,
  requested_finding_type text,
  requested_description text default null,
  requested_severity text default 'medium',
  requested_control_id uuid default null,
  requested_risk_id uuid default null,
  requested_assessment_id uuid default null,
  requested_owner_user_id uuid default null,
  requested_due_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.security_governance_findings
language plpgsql security definer set search_path=''
as $$
declare r public.security_governance_findings;
begin
  if auth.role()<>'service_role'
     and not public.has_organization_permission(requested_organization_id,'security_governance.manage_findings')
  then raise exception 'Permission denied'; end if;

  insert into public.security_governance_findings(
    organization_id,finding_code,finding_name,description,finding_type,control_id,
    risk_id,assessment_id,severity,owner_user_id,status,due_at,metadata,created_by,updated_by
  )
  values(
    requested_organization_id,requested_finding_code,requested_finding_name,
    requested_description,requested_finding_type,requested_control_id,
    requested_risk_id,requested_assessment_id,requested_severity,
    requested_owner_user_id,'open',requested_due_at,
    coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
  )
  on conflict(organization_id,finding_code) do update set
    finding_name=excluded.finding_name,
    description=excluded.description,
    finding_type=excluded.finding_type,
    control_id=excluded.control_id,
    risk_id=excluded.risk_id,
    assessment_id=excluded.assessment_id,
    severity=excluded.severity,
    owner_user_id=excluded.owner_user_id,
    due_at=excluded.due_at,
    metadata=excluded.metadata,
    updated_by=auth.uid(),
    updated_at=now()
  returning * into r;
  return r;
end;
$$;

create or replace function public.request_security_governance_privileged_access(
  requested_organization_id uuid,
  requested_access_type text,
  requested_resource_type text,
  requested_resource_reference text,
  requested_permissions text[],
  requested_business_justification text,
  requested_start_at timestamptz default now(),
  requested_end_at timestamptz default null,
  requested_risk_level text default 'high',
  requested_approver_user_ids uuid[] default '{}',
  requested_metadata jsonb default '{}'::jsonb
)
returns public.security_governance_privileged_access_requests
language plpgsql security definer set search_path=''
as $$
declare r public.security_governance_privileged_access_requests;
begin
  if auth.uid() is null and auth.role()<>'service_role'
  then raise exception 'Authenticated user required'; end if;
  if auth.role()<>'service_role'
     and not public.has_organization_permission(requested_organization_id,'security_governance.request_privileged_access')
  then raise exception 'Permission denied'; end if;

  insert into public.security_governance_privileged_access_requests(
    organization_id,request_code,requester_user_id,access_type,resource_type,
    resource_reference,requested_permissions,business_justification,
    requested_start_at,requested_end_at,risk_level,status,approver_user_ids,metadata
  )
  values(
    requested_organization_id,
    'PAR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
    auth.uid(),requested_access_type,requested_resource_type,
    requested_resource_reference,coalesce(requested_permissions,'{}'),
    requested_business_justification,coalesce(requested_start_at,now()),
    requested_end_at,requested_risk_level,'pending',
    coalesce(requested_approver_user_ids,'{}'),coalesce(requested_metadata,'{}')
  )
  returning * into r;
  return r;
end;
$$;

create or replace function public.respond_security_governance_privileged_access(
  requested_request_id uuid,
  requested_approved boolean,
  requested_reason text default null,
  requested_credential_reference text default null,
  requested_session_reference text default null
)
returns public.security_governance_privileged_access_requests
language plpgsql security definer set search_path=''
as $$
declare r public.security_governance_privileged_access_requests;
begin
  select * into r from public.security_governance_privileged_access_requests
  where id=requested_request_id for update;
  if not found then raise exception 'Privileged access request not found'; end if;

  if auth.role()<>'service_role'
     and auth.uid()<>all(r.approver_user_ids)
     and not public.has_organization_permission(r.organization_id,'security_governance.approve_privileged_access')
  then raise exception 'Permission denied'; end if;

  update public.security_governance_privileged_access_requests
  set status=case when requested_approved then 'approved' else 'rejected' end,
      approved_by=case when requested_approved then auth.uid() else approved_by end,
      approved_at=case when requested_approved then now() else approved_at end,
      rejected_by=case when requested_approved then rejected_by else auth.uid() end,
      rejected_at=case when requested_approved then rejected_at else now() end,
      rejection_reason=case when requested_approved then rejection_reason else requested_reason end,
      credential_reference=case when requested_approved then requested_credential_reference else credential_reference end,
      session_reference=case when requested_approved then requested_session_reference else session_reference end,
      updated_at=now()
  where id=requested_request_id returning * into r;
  return r;
end;
$$;

create or replace function public.report_security_governance_incident(
  requested_organization_id uuid,
  requested_incident_title text,
  requested_incident_type text,
  requested_description text default null,
  requested_severity text default 'medium',
  requested_priority text default 'normal',
  requested_source_type text default null,
  requested_source_reference text default null,
  requested_incident_owner_id uuid default null,
  requested_detected_at timestamptz default now(),
  requested_personal_data_involved boolean default false,
  requested_sensitive_data_involved boolean default false,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.security_governance_incidents
language plpgsql security definer set search_path=''
as $$
declare r public.security_governance_incidents;
begin
  if auth.role()<>'service_role'
     and not public.has_organization_permission(requested_organization_id,'security_governance.manage_incidents')
  then raise exception 'Permission denied'; end if;

  insert into public.security_governance_incidents(
    organization_id,incident_code,incident_title,description,incident_type,
    severity,priority,status,source_type,source_reference,incident_owner_id,
    detected_at,reported_at,personal_data_involved,sensitive_data_involved,
    metadata,created_by,updated_by
  )
  values(
    requested_organization_id,
    'SEC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
    requested_incident_title,requested_description,requested_incident_type,
    requested_severity,requested_priority,'reported',requested_source_type,
    requested_source_reference,requested_incident_owner_id,requested_detected_at,
    now(),requested_personal_data_involved,requested_sensitive_data_involved,
    coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
  )
  returning * into r;

  insert into public.security_governance_incident_events(
    organization_id,incident_id,event_type,event_summary,event_data,performed_by
  )
  values(
    r.organization_id,r.id,'reported','Security incident reported',
    jsonb_build_object('severity',r.severity,'priority',r.priority,'incident_type',r.incident_type),
    auth.uid()
  );

  return r;
end;
$$;

create or replace function public.update_security_governance_incident_status(
  requested_incident_id uuid,
  requested_status text,
  requested_event_summary text default null,
  requested_event_data jsonb default '{}'::jsonb
)
returns public.security_governance_incidents
language plpgsql security definer set search_path=''
as $$
declare r public.security_governance_incidents;
begin
  select * into r from public.security_governance_incidents
  where id=requested_incident_id for update;
  if not found then raise exception 'Security incident not found'; end if;
  if auth.role()<>'service_role'
     and not public.has_organization_permission(r.organization_id,'security_governance.manage_incidents')
  then raise exception 'Permission denied'; end if;

  update public.security_governance_incidents
  set status=requested_status,
      triaged_at=case when requested_status='triaged' then coalesce(triaged_at,now()) else triaged_at end,
      contained_at=case when requested_status='contained' then coalesce(contained_at,now()) else contained_at end,
      resolved_at=case when requested_status='resolved' then coalesce(resolved_at,now()) else resolved_at end,
      closed_at=case when requested_status='closed' then coalesce(closed_at,now()) else closed_at end,
      updated_by=auth.uid(),updated_at=now()
  where id=requested_incident_id returning * into r;

  insert into public.security_governance_incident_events(
    organization_id,incident_id,event_type,event_summary,event_data,performed_by
  )
  values(
    r.organization_id,r.id,'status_changed',
    coalesce(requested_event_summary,'Incident status changed to '||requested_status),
    coalesce(requested_event_data,'{}')||jsonb_build_object('status',requested_status),
    auth.uid()
  );
  return r;
end;
$$;

create or replace function public.submit_security_governance_privacy_request(
  requested_organization_id uuid,
  requested_request_type text,
  requested_requester_type text default 'data_subject',
  requested_requester_reference text default null,
  requested_requester_name text default null,
  requested_requester_email text default null,
  requested_requester_phone text default null,
  requested_related_contact_type text default null,
  requested_related_contact_id uuid default null,
  requested_request_details text default null,
  requested_scope_definition jsonb default '{}'::jsonb,
  requested_due_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.security_governance_privacy_requests
language plpgsql security definer set search_path=''
as $$
declare r public.security_governance_privacy_requests;
begin
  if auth.role()<>'service_role' and auth.uid() is not null
     and not public.has_organization_permission(requested_organization_id,'security_governance.manage_privacy_requests')
  then raise exception 'Permission denied'; end if;

  insert into public.security_governance_privacy_requests(
    organization_id,request_code,request_type,requester_type,requester_reference,
    requester_name,requester_email,requester_phone,related_contact_type,
    related_contact_id,identity_verification_status,status,received_at,due_at,
    request_details,scope_definition,metadata,created_by,updated_by
  )
  values(
    requested_organization_id,
    'PRV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
    requested_request_type,requested_requester_type,requested_requester_reference,
    requested_requester_name,requested_requester_email,requested_requester_phone,
    requested_related_contact_type,requested_related_contact_id,'pending','received',
    now(),requested_due_at,requested_request_details,
    coalesce(requested_scope_definition,'{}'),coalesce(requested_metadata,'{}'),
    auth.uid(),auth.uid()
  )
  returning * into r;
  return r;
end;
$$;

create or replace function public.publish_security_governance_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_source_type text default null,
  requested_source_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.security_governance_event_outbox
language plpgsql security definer set search_path=''
as $$
declare e public.security_governance_event_outbox; r public.security_governance_event_outbox;
begin
  if requested_idempotency_key is not null then
    select * into e from public.security_governance_event_outbox
    where organization_id is not distinct from requested_organization_id
      and idempotency_key=requested_idempotency_key limit 1;
    if found then return e; end if;
  end if;

  insert into public.security_governance_event_outbox(
    organization_id,event_name,source_type,source_id,destination,status,priority,
    idempotency_key,correlation_id,trace_id,payload,available_at
  )
  values(
    requested_organization_id,requested_event_name,requested_source_type,
    requested_source_id,requested_destination,'pending',requested_priority,
    requested_idempotency_key,requested_correlation_id,requested_trace_id,
    coalesce(requested_payload,'{}'),coalesce(requested_available_at,now())
  )
  returning * into r;
  return r;
end;
$$;


revoke all on function public.create_security_governance_policy(uuid,text,text,text,text,uuid,boolean,date,jsonb) from public;
grant execute on function public.create_security_governance_policy(uuid,text,text,text,text,uuid,boolean,date,jsonb) to authenticated,service_role;


revoke all on function public.create_security_governance_policy_version(uuid,text,text,jsonb,uuid,text) from public;
grant execute on function public.create_security_governance_policy_version(uuid,text,text,jsonb,uuid,text) to authenticated,service_role;


revoke all on function public.publish_security_governance_policy_version(uuid,date,date) from public;
grant execute on function public.publish_security_governance_policy_version(uuid,date,date) to authenticated,service_role;


revoke all on function public.attest_security_governance_policy(uuid,text,text,text,inet,text) from public;
grant execute on function public.attest_security_governance_policy(uuid,text,text,text,inet,text) to authenticated,service_role;


revoke all on function public.register_security_governance_risk(uuid,text,text,text,text,uuid,integer,integer,text,date,jsonb) from public;
grant execute on function public.register_security_governance_risk(uuid,text,text,text,text,uuid,integer,integer,text,date,jsonb) to authenticated,service_role;


revoke all on function public.open_security_governance_finding(uuid,text,text,text,text,text,uuid,uuid,uuid,uuid,timestamptz,jsonb) from public;
grant execute on function public.open_security_governance_finding(uuid,text,text,text,text,text,uuid,uuid,uuid,uuid,timestamptz,jsonb) to authenticated,service_role;


revoke all on function public.request_security_governance_privileged_access(uuid,text,text,text,text[],text,timestamptz,timestamptz,text,uuid[],jsonb) from public;
grant execute on function public.request_security_governance_privileged_access(uuid,text,text,text,text[],text,timestamptz,timestamptz,text,uuid[],jsonb) to authenticated,service_role;


revoke all on function public.respond_security_governance_privileged_access(uuid,boolean,text,text,text) from public;
grant execute on function public.respond_security_governance_privileged_access(uuid,boolean,text,text,text) to authenticated,service_role;


revoke all on function public.report_security_governance_incident(uuid,text,text,text,text,text,text,text,uuid,timestamptz,boolean,boolean,jsonb) from public;
grant execute on function public.report_security_governance_incident(uuid,text,text,text,text,text,text,text,uuid,timestamptz,boolean,boolean,jsonb) to authenticated,service_role;


revoke all on function public.update_security_governance_incident_status(uuid,text,text,jsonb) from public;
grant execute on function public.update_security_governance_incident_status(uuid,text,text,jsonb) to authenticated,service_role;


revoke all on function public.submit_security_governance_privacy_request(uuid,text,text,text,text,text,text,text,uuid,text,jsonb,timestamptz,jsonb) from public;
grant execute on function public.submit_security_governance_privacy_request(uuid,text,text,text,text,text,text,text,uuid,text,jsonb,timestamptz,jsonb) to anon,authenticated,service_role;


revoke all on function public.publish_security_governance_event(uuid,text,jsonb,text,text,uuid,integer,text,text,text,timestamptz) from public;
grant execute on function public.publish_security_governance_event(uuid,text,jsonb,text,text,uuid,integer,text,text,text,timestamptz) to authenticated,service_role;


create or replace function public.emit_security_governance_incident_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='UPDATE'
     and new.status is not distinct from old.status
     and new.severity is not distinct from old.severity
  then return new; end if;

  perform public.publish_security_governance_event(
    new.organization_id,
    'security.incident.'||new.status,
    jsonb_build_object(
      'incident_id',new.id,'incident_code',new.incident_code,
      'incident_type',new.incident_type,'severity',new.severity,
      'priority',new.priority,'status',new.status,
      'personal_data_involved',new.personal_data_involved,
      'sensitive_data_involved',new.sensitive_data_involved
    ),
    case when new.severity in ('high','critical') then 'notification_engine' else 'analytics' end,
    'security_incident',new.id,
    case when new.severity='critical' then 1 else 10 end,
    'security-incident:'||new.id::text||':'||new.status,
    new.id::text,null,now()
  );
  return new;
end;
$$;

drop trigger if exists security_governance_incidents_emit_events
on public.security_governance_incidents;
create trigger security_governance_incidents_emit_events
after insert or update on public.security_governance_incidents
for each row execute function public.emit_security_governance_incident_events();

create or replace function public.emit_security_governance_finding_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if tg_op='UPDATE'
     and new.status is not distinct from old.status
     and new.severity is not distinct from old.severity
  then return new; end if;

  perform public.publish_security_governance_event(
    new.organization_id,
    'security.finding.'||new.status,
    jsonb_build_object(
      'finding_id',new.id,'finding_code',new.finding_code,
      'finding_type',new.finding_type,'severity',new.severity,
      'status',new.status,'due_at',new.due_at,'owner_user_id',new.owner_user_id
    ),
    case when new.severity in ('high','critical') then 'notification_engine' else 'analytics' end,
    'security_finding',new.id,
    case when new.severity='critical' then 5 else 50 end,
    'security-finding:'||new.id::text||':'||new.status,
    new.id::text,null,now()
  );
  return new;
end;
$$;

drop trigger if exists security_governance_findings_emit_events
on public.security_governance_findings;
create trigger security_governance_findings_emit_events
after insert or update on public.security_governance_findings
for each row execute function public.emit_security_governance_finding_events();

create or replace view public.security_governance_risk_dashboard
with (security_invoker=true) as
select organization_id,risk_category,status,treatment_strategy,
       count(*) risk_count,
       round(avg(inherent_score),2) average_inherent_score,
       round(avg(residual_score),2) average_residual_score,
       count(*) filter(where inherent_score>=15) high_inherent_risk_count,
       count(*) filter(where coalesce(residual_score,0)>=15) high_residual_risk_count,
       count(*) filter(where next_assessment_due_at<now()) overdue_assessment_count,
       max(updated_at) latest_update_at
from public.security_governance_risks
group by organization_id,risk_category,status,treatment_strategy;

create or replace view public.security_governance_finding_dashboard
with (security_invoker=true) as
select organization_id,finding_type,severity,status,
       count(*) finding_count,
       count(*) filter(
         where due_at<now() and status not in ('resolved','verified','closed','archived')
       ) overdue_count,
       round(avg(risk_score),2) average_risk_score,
       max(resolved_at) latest_resolution_at,
       max(updated_at) latest_update_at
from public.security_governance_findings
group by organization_id,finding_type,severity,status;

create or replace view public.security_governance_incident_dashboard
with (security_invoker=true) as
select organization_id,incident_type,severity,status,
       count(*) incident_count,
       count(*) filter(where personal_data_involved) personal_data_incident_count,
       count(*) filter(where regulatory_notification_required) regulatory_notification_count,
       round(avg(extract(epoch from (coalesce(resolved_at,now())-reported_at))/3600),2)
         average_resolution_hours,
       max(reported_at) latest_reported_at,
       max(resolved_at) latest_resolved_at
from public.security_governance_incidents
group by organization_id,incident_type,severity,status;

create or replace view public.security_governance_privacy_dashboard
with (security_invoker=true) as
select organization_id,request_type,status,
       count(*) request_count,
       count(*) filter(
         where due_at<now() and status not in ('completed','cancelled','rejected','archived')
       ) overdue_count,
       round(avg(extract(epoch from (coalesce(completed_at,now())-received_at))/86400),2)
         average_resolution_days,
       max(received_at) latest_received_at,
       max(completed_at) latest_completed_at
from public.security_governance_privacy_requests
group by organization_id,request_type,status;

create or replace view public.security_governance_access_dashboard
with (security_invoker=true) as
select r.organization_id,r.review_type,r.status,
       count(distinct r.id) review_count,
       count(i.id) review_item_count,
       count(i.id) filter(where i.decision='approve') approved_item_count,
       count(i.id) filter(where i.decision='revoke') revoked_item_count,
       count(i.id) filter(where i.decision='pending') pending_item_count,
       count(i.id) filter(where i.risk_level in ('high','critical') and i.decision='pending')
         high_risk_pending_count,
       max(r.completed_at) latest_completion_at
from public.security_governance_access_reviews r
left join public.security_governance_access_review_items i
  on i.access_review_id=r.id
group by r.organization_id,r.review_type,r.status;

grant select on
  public.security_governance_risk_dashboard,
  public.security_governance_finding_dashboard,
  public.security_governance_incident_dashboard,
  public.security_governance_privacy_dashboard,
  public.security_governance_access_dashboard
to authenticated,service_role;

create or replace function public.get_security_governance_health(
  requested_organization_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  if auth.role()<>'service_role'
     and (
       requested_organization_id is null
       or not public.has_organization_permission(
         requested_organization_id,'security_governance.view_logs'
       )
     )
  then raise exception 'Permission denied'; end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),
    'published_policies',(
      select count(*) from public.security_governance_policies p
      where p.status='published'
        and (requested_organization_id is null or p.organization_id=requested_organization_id)
    ),
    'policy_reviews_overdue',(
      select count(*) from public.security_governance_policies p
      where p.review_due_at<current_date and p.status='published'
        and (requested_organization_id is null or p.organization_id=requested_organization_id)
    ),
    'open_high_risks',(
      select count(*) from public.security_governance_risks r
      where r.status not in ('closed','archived')
        and coalesce(r.residual_score,r.inherent_score)>=15
        and (requested_organization_id is null or r.organization_id=requested_organization_id)
    ),
    'open_critical_findings',(
      select count(*) from public.security_governance_findings f
      where f.severity='critical'
        and f.status not in ('resolved','verified','closed','archived')
        and (requested_organization_id is null or f.organization_id=requested_organization_id)
    ),
    'active_security_incidents',(
      select count(*) from public.security_governance_incidents i
      where i.status not in ('resolved','closed','false_positive','archived')
        and (requested_organization_id is null or i.organization_id=requested_organization_id)
    ),
    'overdue_privacy_requests',(
      select count(*) from public.security_governance_privacy_requests p
      where p.due_at<now()
        and p.status not in ('completed','rejected','cancelled','archived')
        and (requested_organization_id is null or p.organization_id=requested_organization_id)
    ),
    'active_privileged_access',(
      select count(*) from public.security_governance_privileged_access_requests p
      where p.status in ('approved','active')
        and (requested_organization_id is null or p.organization_id=requested_organization_id)
    ),
    'open_sod_violations',(
      select count(*) from public.security_governance_sod_violations v
      where v.status in ('open','under_review','remediating')
        and (requested_organization_id is null or v.organization_id=requested_organization_id)
    ),
    'pending_outbox_events',(
      select count(*) from public.security_governance_event_outbox e
      where e.status in ('pending','failed')
        and (requested_organization_id is null or e.organization_id=requested_organization_id)
    )
  );
end;
$$;

revoke all on function public.get_security_governance_health(uuid) from public;
grant execute on function public.get_security_governance_health(uuid)
to authenticated,service_role;

alter table public.security_governance_frameworks enable row level security;

alter table public.security_governance_controls enable row level security;

alter table public.security_governance_policies enable row level security;

alter table public.security_governance_policy_versions enable row level security;

alter table public.security_governance_policy_attestations enable row level security;

alter table public.security_governance_data_classifications enable row level security;

alter table public.security_governance_data_assets enable row level security;

alter table public.security_governance_retention_policies enable row level security;

alter table public.security_governance_legal_holds enable row level security;

alter table public.security_governance_legal_hold_assets enable row level security;

alter table public.security_governance_risks enable row level security;

alter table public.security_governance_assessments enable row level security;

alter table public.security_governance_control_tests enable row level security;

alter table public.security_governance_evidence enable row level security;

alter table public.security_governance_evidence_links enable row level security;

alter table public.security_governance_findings enable row level security;

alter table public.security_governance_remediation_actions enable row level security;

alter table public.security_governance_access_reviews enable row level security;

alter table public.security_governance_access_review_items enable row level security;

alter table public.security_governance_sod_rules enable row level security;

alter table public.security_governance_sod_violations enable row level security;

alter table public.security_governance_privileged_access_requests enable row level security;

alter table public.security_governance_incidents enable row level security;

alter table public.security_governance_incident_events enable row level security;

alter table public.security_governance_breach_assessments enable row level security;

alter table public.security_governance_privacy_requests enable row level security;

alter table public.security_governance_third_parties enable row level security;

alter table public.security_governance_event_outbox enable row level security;

alter table public.security_governance_logs enable row level security;


drop policy if exists security_governance_frameworks_select_policy on public.security_governance_frameworks;
create policy security_governance_frameworks_select_policy on public.security_governance_frameworks
for select to authenticated
using (
  organization_id is null
  or public.has_organization_permission(organization_id,'security_governance.view')
  or public.has_organization_permission(organization_id,'security_governance.view_all')
);
drop policy if exists security_governance_frameworks_service_policy on public.security_governance_frameworks;
create policy security_governance_frameworks_service_policy on public.security_governance_frameworks
for all to service_role using (true) with check (true);


drop policy if exists security_governance_data_classifications_select_policy on public.security_governance_data_classifications;
create policy security_governance_data_classifications_select_policy on public.security_governance_data_classifications
for select to authenticated
using (
  organization_id is null
  or public.has_organization_permission(organization_id,'security_governance.view')
  or public.has_organization_permission(organization_id,'security_governance.view_all')
);
drop policy if exists security_governance_data_classifications_service_policy on public.security_governance_data_classifications;
create policy security_governance_data_classifications_service_policy on public.security_governance_data_classifications
for all to service_role using (true) with check (true);


drop policy if exists security_governance_controls_select_policy on public.security_governance_controls;
create policy security_governance_controls_select_policy on public.security_governance_controls
for select to authenticated
using (
  organization_id is null
  or public.has_organization_permission(organization_id,'security_governance.view')
  or public.has_organization_permission(organization_id,'security_governance.view_all')
);
drop policy if exists security_governance_controls_service_policy on public.security_governance_controls;
create policy security_governance_controls_service_policy on public.security_governance_controls
for all to service_role using (true) with check (true);


do $$
declare t text;
begin
  foreach t in array array['security_governance_policies','security_governance_policy_versions','security_governance_policy_attestations','security_governance_data_assets','security_governance_retention_policies','security_governance_legal_holds','security_governance_legal_hold_assets','security_governance_risks','security_governance_assessments','security_governance_control_tests','security_governance_evidence','security_governance_evidence_links','security_governance_findings','security_governance_remediation_actions','security_governance_access_reviews','security_governance_access_review_items','security_governance_sod_rules','security_governance_sod_violations','security_governance_privileged_access_requests','security_governance_incidents','security_governance_incident_events','security_governance_breach_assessments','security_governance_privacy_requests','security_governance_third_parties','security_governance_event_outbox','security_governance_logs']
  loop
    execute format('drop policy if exists %I_select_policy on public.%I',t,t);
    execute format(
      'create policy %I_select_policy on public.%I for select to authenticated
       using (
         public.has_organization_permission(organization_id,''security_governance.view'')
         or public.has_organization_permission(organization_id,''security_governance.view_all'')
       )',t,t
    );
    execute format('drop policy if exists %I_service_policy on public.%I',t,t);
    execute format(
      'create policy %I_service_policy on public.%I for all to service_role
       using (true) with check (true)',t,t
    );
  end loop;
end;
$$;


drop policy if exists security_governance_policy_attestations_self_policy
on public.security_governance_policy_attestations;
create policy security_governance_policy_attestations_self_policy
on public.security_governance_policy_attestations
for all to authenticated
using (
  user_id=auth.uid()
  or public.has_organization_permission(organization_id,'security_governance.manage_policies')
)
with check (
  user_id=auth.uid()
  or public.has_organization_permission(organization_id,'security_governance.manage_policies')
);

drop policy if exists security_governance_privileged_access_requester_policy
on public.security_governance_privileged_access_requests;
create policy security_governance_privileged_access_requester_policy
on public.security_governance_privileged_access_requests
for select to authenticated
using (
  requester_user_id=auth.uid()
  or public.has_organization_permission(organization_id,'security_governance.view')
  or public.has_organization_permission(organization_id,'security_governance.view_all')
);


grant select on
  public.security_governance_frameworks,
  public.security_governance_controls,
  public.security_governance_policies,
  public.security_governance_policy_versions,
  public.security_governance_policy_attestations,
  public.security_governance_data_classifications,
  public.security_governance_data_assets,
  public.security_governance_retention_policies,
  public.security_governance_legal_holds,
  public.security_governance_legal_hold_assets,
  public.security_governance_risks,
  public.security_governance_assessments,
  public.security_governance_control_tests,
  public.security_governance_evidence,
  public.security_governance_evidence_links,
  public.security_governance_findings,
  public.security_governance_remediation_actions,
  public.security_governance_access_reviews,
  public.security_governance_access_review_items,
  public.security_governance_sod_rules,
  public.security_governance_sod_violations,
  public.security_governance_privileged_access_requests,
  public.security_governance_incidents,
  public.security_governance_incident_events,
  public.security_governance_breach_assessments,
  public.security_governance_privacy_requests,
  public.security_governance_third_parties,
  public.security_governance_event_outbox,
  public.security_governance_logs
to authenticated;

grant all on
  public.security_governance_frameworks,
  public.security_governance_controls,
  public.security_governance_policies,
  public.security_governance_policy_versions,
  public.security_governance_policy_attestations,
  public.security_governance_data_classifications,
  public.security_governance_data_assets,
  public.security_governance_retention_policies,
  public.security_governance_legal_holds,
  public.security_governance_legal_hold_assets,
  public.security_governance_risks,
  public.security_governance_assessments,
  public.security_governance_control_tests,
  public.security_governance_evidence,
  public.security_governance_evidence_links,
  public.security_governance_findings,
  public.security_governance_remediation_actions,
  public.security_governance_access_reviews,
  public.security_governance_access_review_items,
  public.security_governance_sod_rules,
  public.security_governance_sod_violations,
  public.security_governance_privileged_access_requests,
  public.security_governance_incidents,
  public.security_governance_incident_events,
  public.security_governance_breach_assessments,
  public.security_governance_privacy_requests,
  public.security_governance_third_parties,
  public.security_governance_event_outbox,
  public.security_governance_logs
to service_role;


do $$
declare item text; missing_items text[]:='{}';
begin
  foreach item in array array['security_governance_frameworks','security_governance_controls','security_governance_policies','security_governance_policy_versions','security_governance_policy_attestations','security_governance_data_classifications','security_governance_data_assets','security_governance_retention_policies','security_governance_legal_holds','security_governance_legal_hold_assets','security_governance_risks','security_governance_assessments','security_governance_control_tests','security_governance_evidence','security_governance_evidence_links','security_governance_findings','security_governance_remediation_actions','security_governance_access_reviews','security_governance_access_review_items','security_governance_sod_rules','security_governance_sod_violations','security_governance_privileged_access_requests','security_governance_incidents','security_governance_incident_events','security_governance_breach_assessments','security_governance_privacy_requests','security_governance_third_parties','security_governance_event_outbox','security_governance_logs']
  loop
    if not exists(
      select 1 from information_schema.tables
      where table_schema='public' and table_name=item
    ) then missing_items:=array_append(missing_items,'table:'||item); end if;
  end loop;

  foreach item in array array['create_security_governance_policy','create_security_governance_policy_version','publish_security_governance_policy_version','attest_security_governance_policy','register_security_governance_risk','open_security_governance_finding','request_security_governance_privileged_access','respond_security_governance_privileged_access','report_security_governance_incident','update_security_governance_incident_status','submit_security_governance_privacy_request','publish_security_governance_event','get_security_governance_health']
  loop
    if not exists(
      select 1 from information_schema.routines
      where routine_schema='public' and routine_name=item
    ) then missing_items:=array_append(missing_items,'function:'||item); end if;
  end loop;

  if cardinality(missing_items)>0 then
    raise exception '029 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

insert into public.security_governance_logs(
  organization_id,log_level,event_name,message,source_type,log_data
)
select o.id,'info','migration.029.completed',
       'Security, Compliance and Governance Engine migration 029 completed',
       'migration',
       jsonb_build_object(
         'migration','029_security_compliance_governance_engine',
         'completed_at',now(),
         'modules',jsonb_build_array(
           'frameworks','controls','policies','attestations','data_classification',
           'data_assets','retention','legal_holds','risk_register','assessments',
           'control_tests','evidence','findings','remediation','access_reviews',
           'segregation_of_duties','privileged_access','security_incidents',
           'breach_assessments','privacy_requests','third_party_security',
           'analytics','event_outbox'
         )
       )
from public.organizations o
where not exists(
  select 1 from public.security_governance_logs l
  where l.organization_id=o.id and l.event_name='migration.029.completed'
);

commit;