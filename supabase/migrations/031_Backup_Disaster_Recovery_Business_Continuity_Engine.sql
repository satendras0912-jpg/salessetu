-- ============================================================
-- SalesSetu Enterprise
-- Migration 031: Backup, Disaster Recovery & Business Continuity Engine
-- PostgreSQL / Supabase
-- ============================================================
-- This module is an orchestration and governance control plane. Physical
-- backup, restore, replication, failover and failback operations must be
-- performed by trusted service-role workers or infrastructure providers.
-- Credentials and encryption keys are stored only as external references.
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- 1. Permissions
insert into public.permissions(module,action,code,description)
select x.module,x.action,x.code,x.description
from (values
 ('resilience','view','resilience.view','View resilience data'),
 ('resilience','view_all','resilience.view_all','View all organization resilience data'),
 ('resilience','manage_backup_targets','resilience.manage_backup_targets','Manage backup targets'),
 ('resilience','manage_backup_policies','resilience.manage_backup_policies','Manage backup policies and schedules'),
 ('resilience','execute_backups','resilience.execute_backups','Execute backup jobs'),
 ('resilience','verify_backups','resilience.verify_backups','Verify backup artifacts and restore points'),
 ('resilience','manage_restores','resilience.manage_restores','Manage restore requests and jobs'),
 ('resilience','approve_restores','resilience.approve_restores','Approve sensitive restores'),
 ('resilience','manage_replication','resilience.manage_replication','Manage replication and recovery sites'),
 ('resilience','manage_recovery_objectives','resilience.manage_recovery_objectives','Manage RPO and RTO objectives'),
 ('resilience','manage_bia','resilience.manage_bia','Manage business-impact assessments'),
 ('resilience','manage_continuity_plans','resilience.manage_continuity_plans','Manage continuity and recovery plans'),
 ('resilience','manage_disaster_events','resilience.manage_disaster_events','Manage disaster events'),
 ('resilience','execute_recovery','resilience.execute_recovery','Execute recovery plans'),
 ('resilience','manage_failover','resilience.manage_failover','Manage failover configurations and jobs'),
 ('resilience','approve_failover','resilience.approve_failover','Approve failover and failback'),
 ('resilience','manage_exercises','resilience.manage_exercises','Manage continuity exercises'),
 ('resilience','manage_retention','resilience.manage_retention','Manage resilience retention'),
 ('resilience','view_sensitive','resilience.view_sensitive','View sensitive recovery data'),
 ('resilience','view_logs','resilience.view_logs','View resilience logs'),
 ('resilience','view_analytics','resilience.view_analytics','View resilience analytics')
) x(module,action,code,description)
where not exists(select 1 from public.permissions p where p.code=x.code);

-- 2. Backup targets
create table if not exists public.resilience_backup_targets(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 target_code text not null,
 target_name text not null,
 description text,
 target_type text not null check(target_type in('supabase_managed','object_storage','database_server','cloud_snapshot','filesystem','vault','external_provider','custom')),
 provider_name text,
 provider_account_reference text,
 region text,
 storage_location_reference text,
 credential_reference text,
 encryption_key_reference text,
 encryption_required boolean not null default true,
 immutable_storage boolean not null default false,
 air_gapped boolean not null default false,
 cross_region boolean not null default false,
 capacity_limit_bytes bigint,
 current_usage_bytes bigint,
 health_status text not null default 'unknown' check(health_status in('unknown','healthy','degraded','unhealthy','unreachable','maintenance')),
 last_health_check_at timestamptz,
 last_successful_write_at timestamptz,
 last_error_at timestamptz,
 last_error_message text,
 status text not null default 'active' check(status in('active','inactive','maintenance','retired','archived')),
 configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,target_code)
);
create index if not exists resilience_backup_targets_health_idx on public.resilience_backup_targets(organization_id,status,health_status);

-- 3. Backup policies
create table if not exists public.resilience_backup_policies(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 policy_code text not null,
 policy_name text not null,
 description text,
 backup_type text not null check(backup_type in('full','incremental','differential','snapshot','continuous','point_in_time','logical','physical','configuration','custom')),
 scope_type text not null check(scope_type in('organization','environment','service','database','schema','table','storage_bucket','documents','configuration','custom')),
 scope_definition jsonb not null default '{}',
 primary_target_id uuid not null references public.resilience_backup_targets(id) on delete restrict,
 secondary_target_id uuid references public.resilience_backup_targets(id) on delete set null,
 retention_days integer not null default 30 check(retention_days>=1),
 minimum_restore_points integer not null default 1 check(minimum_restore_points>=1),
 maximum_restore_points integer,
 retention_tiers jsonb not null default '[]',
 compression_enabled boolean not null default true,
 encryption_enabled boolean not null default true,
 integrity_verification_required boolean not null default true,
 restore_test_required boolean not null default true,
 restore_test_interval_days integer,
 maximum_backup_duration_minutes integer,
 maximum_backup_age_minutes integer,
 rpo_minutes integer check(rpo_minutes is null or rpo_minutes>=0),
 rto_minutes integer check(rto_minutes is null or rto_minutes>=0),
 failure_notification_severity text not null default 'high' check(failure_notification_severity in('info','warning','high','critical')),
 owner_user_id uuid references auth.users(id) on delete set null,
 status text not null default 'active' check(status in('draft','active','paused','inactive','retired','archived')),
 tags text[] not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(maximum_restore_points is null or maximum_restore_points>=minimum_restore_points),
 check(secondary_target_id is null or secondary_target_id<>primary_target_id),
 unique(organization_id,policy_code)
);
create index if not exists resilience_backup_policies_status_idx on public.resilience_backup_policies(organization_id,status,backup_type);

-- 4. Backup schedules
create table if not exists public.resilience_backup_schedules(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 backup_policy_id uuid not null references public.resilience_backup_policies(id) on delete cascade,
 schedule_code text not null,
 schedule_name text not null,
 description text,
 schedule_type text not null default 'cron' check(schedule_type in('cron','interval','event','continuous','manual','custom')),
 cron_expression text,
 interval_minutes integer,
 event_name text,
 timezone text not null default 'Asia/Kolkata',
 blackout_windows jsonb not null default '[]',
 jitter_seconds integer not null default 0,
 maximum_concurrent_jobs integer not null default 1 check(maximum_concurrent_jobs>=1),
 status text not null default 'active' check(status in('active','paused','inactive','archived')),
 last_scheduled_at timestamptz,
 next_scheduled_at timestamptz,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check((schedule_type='cron' and cron_expression is not null) or (schedule_type='interval' and interval_minutes>=1) or schedule_type in('event','continuous','manual','custom')),
 unique(organization_id,schedule_code)
);
create index if not exists resilience_backup_schedules_due_idx on public.resilience_backup_schedules(status,next_scheduled_at) where status='active';

-- 5. Backup jobs
create table if not exists public.resilience_backup_jobs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 backup_policy_id uuid not null references public.resilience_backup_policies(id) on delete restrict,
 backup_schedule_id uuid references public.resilience_backup_schedules(id) on delete set null,
 target_id uuid not null references public.resilience_backup_targets(id) on delete restrict,
 job_reference text not null,
 trigger_type text not null default 'scheduled' check(trigger_type in('scheduled','manual','event','continuous','pre_deployment','pre_restore','pre_failover','recovery','custom')),
 backup_type text not null,
 status text not null default 'queued' check(status in('queued','claimed','preparing','running','uploading','verifying','completed','completed_with_warnings','failed','cancelled','expired','dead_lettered')),
 priority integer not null default 100,
 available_at timestamptz not null default now(),
 scope_snapshot jsonb not null default '{}',
 execution_parameters jsonb not null default '{}',
 attempts integer not null default 0,
 maximum_attempts integer not null default 5,
 claimed_at timestamptz,
 claimed_by text,
 lock_token text,
 lock_expires_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 duration_seconds bigint,
 source_snapshot_at timestamptz,
 source_lsn text,
 source_transaction_reference text,
 bytes_scanned bigint,
 bytes_written bigint,
 object_count bigint,
 progress_percentage numeric(8,4) not null default 0 check(progress_percentage between 0 and 100),
 checksum_algorithm text,
 aggregate_checksum text,
 artifact_count integer not null default 0,
 last_error_code text,
 last_error_message text,
 last_error_data jsonb not null default '{}',
 correlation_id text,
 trace_id text,
 idempotency_key text,
 requested_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,job_reference)
);
create index if not exists resilience_backup_jobs_worker_idx on public.resilience_backup_jobs(status,available_at,priority,created_at) where status in('queued','failed');
create index if not exists resilience_backup_jobs_policy_time_idx on public.resilience_backup_jobs(organization_id,backup_policy_id,created_at desc);
create unique index if not exists resilience_backup_jobs_idem_idx on public.resilience_backup_jobs(organization_id,idempotency_key) where idempotency_key is not null;

-- 6. Backup artifacts
create table if not exists public.resilience_backup_artifacts(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 backup_job_id uuid not null references public.resilience_backup_jobs(id) on delete cascade,
 target_id uuid not null references public.resilience_backup_targets(id) on delete restrict,
 artifact_reference text not null,
 artifact_name text not null,
 artifact_type text not null check(artifact_type in('database_dump','wal_archive','snapshot','storage_archive','configuration_export','document_archive','manifest','checksum','metadata','custom')),
 storage_path_reference text not null,
 external_version_reference text,
 size_bytes bigint,
 object_count bigint,
 checksum_algorithm text,
 checksum_value text,
 encryption_status text not null default 'unknown' check(encryption_status in('unknown','encrypted','not_encrypted','encryption_failed')),
 encryption_key_reference text,
 immutability_status text not null default 'unknown' check(immutability_status in('unknown','mutable','locked','write_once','legal_hold')),
 artifact_status text not null default 'available' check(artifact_status in('creating','available','verified','corrupt','expired','deleted','unavailable','archived')),
 backup_started_at timestamptz,
 backup_completed_at timestamptz,
 expires_at timestamptz,
 immutable_until timestamptz,
 verified_at timestamptz,
 last_accessed_at timestamptz,
 manifest jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,artifact_reference)
);
create index if not exists resilience_backup_artifacts_status_idx on public.resilience_backup_artifacts(organization_id,artifact_status,expires_at);

-- 7. Backup verification history
create table if not exists public.resilience_backup_verifications(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 backup_artifact_id uuid not null references public.resilience_backup_artifacts(id) on delete cascade,
 verification_reference text not null,
 verification_type text not null check(verification_type in('checksum','manifest','readability','malware_scan','encryption','immutability','schema_validation','sample_restore','full_restore','custom')),
 status text not null default 'pending' check(status in('pending','running','passed','passed_with_warnings','failed','cancelled','error')),
 expected_value text,
 actual_value text,
 findings jsonb not null default '[]',
 verification_data jsonb not null default '{}',
 started_at timestamptz,
 completed_at timestamptz,
 duration_seconds bigint,
 verified_by uuid references auth.users(id) on delete set null,
 worker_reference text,
 error_code text,
 error_message text,
 correlation_id text,
 trace_id text,
 created_at timestamptz not null default now(),
 unique(backup_artifact_id,verification_reference)
);
create index if not exists resilience_backup_verifications_artifact_idx on public.resilience_backup_verifications(backup_artifact_id,created_at desc);

-- 8. Restore points
create table if not exists public.resilience_restore_points(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 backup_policy_id uuid not null references public.resilience_backup_policies(id) on delete restrict,
 backup_job_id uuid not null references public.resilience_backup_jobs(id) on delete restrict,
 primary_artifact_id uuid references public.resilience_backup_artifacts(id) on delete set null,
 restore_point_reference text not null,
 restore_point_name text,
 restore_point_type text not null check(restore_point_type in('full','incremental_chain','snapshot','point_in_time','logical','configuration','custom')),
 recovery_time timestamptz not null,
 source_lsn text,
 source_transaction_reference text,
 consistency_status text not null default 'unknown' check(consistency_status in('unknown','crash_consistent','application_consistent','transaction_consistent','inconsistent')),
 verification_status text not null default 'pending' check(verification_status in('pending','verified','verified_with_warnings','failed','expired')),
 restore_readiness text not null default 'unknown' check(restore_readiness in('unknown','ready','ready_with_warnings','not_ready','expired')),
 chain_artifact_ids uuid[] not null default '{}',
 expires_at timestamptz,
 last_restore_test_at timestamptz,
 next_restore_test_due_at timestamptz,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,restore_point_reference)
);
create index if not exists resilience_restore_points_readiness_idx on public.resilience_restore_points(organization_id,restore_readiness,recovery_time desc);

-- 9. Restore requests
create table if not exists public.resilience_restore_requests(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 request_reference text not null,
 restore_point_id uuid not null references public.resilience_restore_points(id) on delete restrict,
 requested_environment_id uuid references public.observability_environments(id) on delete set null,
 requested_service_id uuid references public.observability_services(id) on delete set null,
 restore_type text not null check(restore_type in('full_environment','database','schema','table','point_in_time','storage','documents','configuration','selective','test_restore','custom')),
 target_type text not null check(target_type in('original','alternate_environment','temporary_environment','recovery_site','local_validation','custom')),
 target_reference text,
 requested_recovery_time timestamptz,
 scope_definition jsonb not null default '{}',
 business_justification text not null,
 risk_level text not null default 'high' check(risk_level in('low','medium','high','critical')),
 data_overwrite_expected boolean not null default false,
 production_impact_expected boolean not null default false,
 customer_impact_expected boolean not null default false,
 pre_restore_backup_required boolean not null default true,
 validation_required boolean not null default true,
 status text not null default 'pending_approval' check(status in('draft','pending_approval','approved','rejected','queued','in_progress','validating','completed','completed_with_warnings','failed','cancelled','expired')),
 approver_user_ids uuid[] not null default '{}',
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 rejected_by uuid references auth.users(id) on delete set null,
 rejected_at timestamptz,
 rejection_reason text,
 expires_at timestamptz,
 requested_by uuid references auth.users(id) on delete set null,
 workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,request_reference)
);
create index if not exists resilience_restore_requests_status_idx on public.resilience_restore_requests(organization_id,status,risk_level,created_at);

-- 10. Restore jobs
create table if not exists public.resilience_restore_jobs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 restore_request_id uuid not null references public.resilience_restore_requests(id) on delete cascade,
 restore_point_id uuid not null references public.resilience_restore_points(id) on delete restrict,
 job_reference text not null,
 status text not null default 'queued' check(status in('queued','claimed','preparing','pre_restore_backup','restoring','replaying','validating','completed','completed_with_warnings','failed','rolled_back','cancelled','dead_lettered')),
 priority integer not null default 50,
 available_at timestamptz not null default now(),
 execution_parameters jsonb not null default '{}',
 attempts integer not null default 0,
 maximum_attempts integer not null default 3,
 claimed_at timestamptz,
 claimed_by text,
 lock_token text,
 lock_expires_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 duration_seconds bigint,
 progress_percentage numeric(8,4) not null default 0 check(progress_percentage between 0 and 100),
 restored_bytes bigint,
 restored_object_count bigint,
 validation_status text not null default 'pending' check(validation_status in('pending','running','passed','passed_with_warnings','failed','not_required')),
 validation_results jsonb not null default '{}',
 rollback_reference text,
 last_error_code text,
 last_error_message text,
 last_error_data jsonb not null default '{}',
 correlation_id text,
 trace_id text,
 idempotency_key text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,job_reference)
);
create index if not exists resilience_restore_jobs_worker_idx on public.resilience_restore_jobs(status,available_at,priority,created_at) where status in('queued','failed');
create unique index if not exists resilience_restore_jobs_idem_idx on public.resilience_restore_jobs(organization_id,idempotency_key) where idempotency_key is not null;

-- 11. Recovery sites
create table if not exists public.resilience_recovery_sites(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 site_code text not null,
 site_name text not null,
 description text,
 site_type text not null check(site_type in('hot','warm','cold','cloud_region','secondary_provider','on_premise','temporary','custom')),
 provider_name text,
 account_reference text,
 region text,
 location_reference text,
 environment_id uuid references public.observability_environments(id) on delete set null,
 network_reference text,
 credential_reference text,
 encryption_key_reference text,
 provisioned_capacity jsonb not null default '{}',
 supported_service_ids uuid[] not null default '{}',
 readiness_status text not null default 'unknown' check(readiness_status in('unknown','ready','partially_ready','not_ready','provisioning','maintenance')),
 last_readiness_check_at timestamptz,
 last_successful_failover_at timestamptz,
 last_successful_failback_at timestamptz,
 status text not null default 'active' check(status in('active','inactive','maintenance','retired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,site_code)
);

-- 12. Replication
create table if not exists public.resilience_replication_configurations(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 configuration_code text not null,
 configuration_name text not null,
 description text,
 source_environment_id uuid references public.observability_environments(id) on delete set null,
 source_service_id uuid references public.observability_services(id) on delete set null,
 recovery_site_id uuid not null references public.resilience_recovery_sites(id) on delete restrict,
 target_environment_id uuid references public.observability_environments(id) on delete set null,
 replication_type text not null check(replication_type in('synchronous','asynchronous','log_shipping','streaming','snapshot_copy','object_replication','configuration_sync','custom')),
 direction text not null default 'primary_to_recovery' check(direction in('primary_to_recovery','bidirectional','recovery_to_primary','custom')),
 maximum_lag_seconds integer check(maximum_lag_seconds is null or maximum_lag_seconds>=0),
 maximum_data_loss_seconds integer check(maximum_data_loss_seconds is null or maximum_data_loss_seconds>=0),
 replication_scope jsonb not null default '{}',
 connection_reference text,
 status text not null default 'active' check(status in('draft','active','paused','degraded','failed','inactive','retired')),
 last_sync_at timestamptz,
 last_error_at timestamptz,
 last_error_message text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,configuration_code)
);
create table if not exists public.resilience_replication_snapshots(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 replication_configuration_id uuid not null references public.resilience_replication_configurations(id) on delete cascade,
 snapshot_reference text not null,
 status text not null check(status in('healthy','warning','critical','failed','paused','unknown')),
 source_position text,
 target_position text,
 lag_seconds bigint,
 lag_bytes bigint,
 source_timestamp timestamptz,
 target_timestamp timestamptz,
 last_successful_sync_at timestamptz,
 error_code text,
 error_message text,
 details jsonb not null default '{}',
 observed_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 unique(replication_configuration_id,snapshot_reference)
);
create index if not exists resilience_replication_snapshots_recent_idx on public.resilience_replication_snapshots(organization_id,replication_configuration_id,observed_at desc);

-- 13. Recovery objectives
create table if not exists public.resilience_recovery_objectives(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 objective_code text not null,
 objective_name text not null,
 description text,
 objective_scope_type text not null check(objective_scope_type in('organization','business_process','environment','service','database','application','data_asset','custom')),
 scope_reference text,
 service_id uuid references public.observability_services(id) on delete set null,
 criticality text not null default 'high' check(criticality in('low','medium','high','critical')),
 rpo_minutes integer not null check(rpo_minutes>=0),
 rto_minutes integer not null check(rto_minutes>=0),
 maximum_tolerable_downtime_minutes integer,
 minimum_service_level_percentage numeric(8,4) check(minimum_service_level_percentage is null or minimum_service_level_percentage between 0 and 100),
 recovery_priority integer not null default 100 check(recovery_priority>=1),
 dependencies jsonb not null default '[]',
 owner_user_id uuid references auth.users(id) on delete set null,
 last_validated_at timestamptz,
 next_validation_due_at timestamptz,
 status text not null default 'active' check(status in('draft','active','inactive','retired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(maximum_tolerable_downtime_minutes is null or maximum_tolerable_downtime_minutes>=rto_minutes),
 unique(organization_id,objective_code)
);

-- 14. Business processes and BIA
create table if not exists public.resilience_business_processes(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 process_code text not null,
 process_name text not null,
 description text,
 process_category text,
 owner_user_id uuid references auth.users(id) on delete set null,
 alternate_owner_user_id uuid references auth.users(id) on delete set null,
 criticality text not null default 'high' check(criticality in('low','medium','high','critical')),
 operating_hours jsonb not null default '{}',
 peak_periods jsonb not null default '[]',
 customer_facing boolean not null default false,
 revenue_impacting boolean not null default false,
 regulatory_impacting boolean not null default false,
 service_ids uuid[] not null default '{}',
 data_asset_references text[] not null default '{}',
 third_party_references text[] not null default '{}',
 minimum_staffing integer,
 alternate_work_location text,
 status text not null default 'active' check(status in('draft','active','inactive','retired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,process_code)
);
create table if not exists public.resilience_bia_assessments(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 business_process_id uuid not null references public.resilience_business_processes(id) on delete cascade,
 assessment_reference text not null,
 assessment_name text not null,
 assessment_status text not null default 'draft' check(assessment_status in('draft','in_progress','under_review','approved','superseded','archived')),
 disruption_scenarios jsonb not null default '[]',
 financial_impact jsonb not null default '{}',
 operational_impact jsonb not null default '{}',
 customer_impact jsonb not null default '{}',
 legal_regulatory_impact jsonb not null default '{}',
 reputation_impact jsonb not null default '{}',
 impact_score numeric(12,4),
 criticality_rating text check(criticality_rating is null or criticality_rating in('low','medium','high','critical')),
 maximum_tolerable_downtime_minutes integer,
 target_rto_minutes integer,
 target_rpo_minutes integer,
 minimum_resource_requirements jsonb not null default '{}',
 recovery_dependencies jsonb not null default '[]',
 assessor_user_ids uuid[] not null default '{}',
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 assessment_date date not null default current_date,
 review_due_at date,
 summary text,
 recommendations text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(business_process_id,assessment_reference)
);
create table if not exists public.resilience_bia_dependencies(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 bia_assessment_id uuid not null references public.resilience_bia_assessments(id) on delete cascade,
 dependency_type text not null check(dependency_type in('service','application','database','data','personnel','facility','vendor','network','equipment','utility','regulatory','custom')),
 dependency_reference text not null,
 dependency_name text not null,
 description text,
 criticality text not null default 'high' check(criticality in('low','medium','high','critical')),
 maximum_unavailable_minutes integer,
 minimum_capacity_percentage numeric(8,4),
 alternative_reference text,
 workaround_available boolean not null default false,
 workaround_description text,
 recovery_sequence integer,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now()
);

-- 15. Continuity plans and steps
create table if not exists public.resilience_continuity_plans(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 plan_code text not null,
 plan_name text not null,
 description text,
 plan_type text not null check(plan_type in('business_continuity','disaster_recovery','it_recovery','crisis_management','cyber_recovery','data_recovery','workplace_recovery','vendor_continuity','custom')),
 scope_definition jsonb not null default '{}',
 business_process_ids uuid[] not null default '{}',
 service_ids uuid[] not null default '{}',
 recovery_objective_ids uuid[] not null default '{}',
 primary_recovery_site_id uuid references public.resilience_recovery_sites(id) on delete set null,
 alternate_recovery_site_id uuid references public.resilience_recovery_sites(id) on delete set null,
 owner_user_id uuid references auth.users(id) on delete set null,
 coordinator_user_id uuid references auth.users(id) on delete set null,
 activation_authority_user_ids uuid[] not null default '{}',
 status text not null default 'draft' check(status in('draft','under_review','approved','active','suspended','superseded','retired','archived')),
 version_number integer not null default 1,
 effective_from date,
 review_due_at date,
 last_exercised_at timestamptz,
 next_exercise_due_at timestamptz,
 plan_document_id uuid references public.documents(id) on delete set null,
 workflow_definition_id uuid references public.enterprise_workflow_definitions(id) on delete set null,
 activation_criteria jsonb not null default '[]',
 communication_strategy jsonb not null default '{}',
 metadata jsonb not null default '{}',
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(alternate_recovery_site_id is null or alternate_recovery_site_id<>primary_recovery_site_id),
 unique(organization_id,plan_code,version_number)
);
create table if not exists public.resilience_continuity_plan_steps(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 continuity_plan_id uuid not null references public.resilience_continuity_plans(id) on delete cascade,
 step_code text not null,
 step_name text not null,
 description text,
 phase text not null check(phase in('detection','assessment','declaration','activation','containment','failover','recovery','validation','business_resumption','failback','stand_down','post_incident','custom')),
 sequence_number integer not null,
 parallel_group text,
 action_type text not null default 'manual' check(action_type in('manual','automated','approval','notification','backup','restore','failover','validation','workflow','custom')),
 responsible_user_id uuid references auth.users(id) on delete set null,
 responsible_role_reference text,
 estimated_duration_minutes integer,
 timeout_minutes integer,
 prerequisite_step_codes text[] not null default '{}',
 success_criteria jsonb not null default '{}',
 execution_parameters jsonb not null default '{}',
 observability_runbook_id uuid references public.observability_runbooks(id) on delete set null,
 workflow_definition_id uuid references public.enterprise_workflow_definitions(id) on delete set null,
 requires_approval boolean not null default false,
 approver_user_ids uuid[] not null default '{}',
 rollback_instructions text,
 evidence_requirements jsonb not null default '[]',
 status text not null default 'active' check(status in('active','inactive','deprecated')),
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(continuity_plan_id,step_code)
);
create unique index if not exists resilience_plan_steps_sequence_idx on public.resilience_continuity_plan_steps(continuity_plan_id,sequence_number,coalesce(parallel_group,''));

-- 16. Disaster scenarios and events
create table if not exists public.resilience_disaster_scenarios(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 scenario_code text not null,
 scenario_name text not null,
 description text,
 scenario_type text not null check(scenario_type in('regional_outage','database_failure','data_corruption','cyber_attack','ransomware','provider_outage','network_failure','facility_loss','key_person_unavailability','vendor_failure','natural_disaster','pandemic','configuration_failure','deployment_failure','custom')),
 probability_rating text not null default 'medium' check(probability_rating in('rare','low','medium','high','very_high')),
 impact_rating text not null default 'high' check(impact_rating in('low','medium','high','critical')),
 early_warning_indicators jsonb not null default '[]',
 declaration_criteria jsonb not null default '[]',
 affected_service_ids uuid[] not null default '{}',
 affected_process_ids uuid[] not null default '{}',
 recommended_plan_ids uuid[] not null default '{}',
 status text not null default 'active' check(status in('active','inactive','retired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,scenario_code)
);
create table if not exists public.resilience_disaster_events(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 event_reference text not null,
 event_title text not null,
 description text,
 scenario_id uuid references public.resilience_disaster_scenarios(id) on delete set null,
 event_type text not null,
 severity text not null default 'high' check(severity in('warning','high','critical','catastrophic')),
 status text not null default 'detected' check(status in('detected','assessing','declared','plan_activated','recovering','business_resuming','contained','resolved','closed','false_alarm','cancelled','archived')),
 source_type text,
 source_reference text,
 related_observability_incident_id uuid references public.observability_reliability_incidents(id) on delete set null,
 related_security_incident_id uuid references public.security_governance_incidents(id) on delete set null,
 affected_environment_ids uuid[] not null default '{}',
 affected_service_ids uuid[] not null default '{}',
 affected_process_ids uuid[] not null default '{}',
 affected_regions text[] not null default '{}',
 customer_impact text,
 business_impact text,
 regulatory_impact text,
 declared_by uuid references auth.users(id) on delete set null,
 event_commander_id uuid references auth.users(id) on delete set null,
 response_team_user_ids uuid[] not null default '{}',
 detected_at timestamptz not null default now(),
 assessed_at timestamptz,
 declared_at timestamptz,
 plan_activated_at timestamptz,
 contained_at timestamptz,
 resolved_at timestamptz,
 closed_at timestamptz,
 declaration_reason text,
 resolution_summary text,
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,event_reference)
);
create index if not exists resilience_disaster_events_active_idx on public.resilience_disaster_events(organization_id,status,severity,detected_at desc);

-- 17. Recovery runs and steps
create table if not exists public.resilience_recovery_runs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 run_reference text not null,
 disaster_event_id uuid references public.resilience_disaster_events(id) on delete set null,
 continuity_plan_id uuid not null references public.resilience_continuity_plans(id) on delete restrict,
 run_type text not null default 'actual' check(run_type in('actual','exercise','test','validation','partial','custom')),
 status text not null default 'planned' check(status in('planned','awaiting_approval','approved','running','paused','blocked','validating','completed','completed_with_warnings','failed','cancelled','rolled_back')),
 recovery_site_id uuid references public.resilience_recovery_sites(id) on delete set null,
 target_rpo_minutes integer,
 target_rto_minutes integer,
 actual_data_loss_minutes numeric(12,4),
 actual_recovery_time_minutes numeric(12,4),
 rpo_met boolean,
 rto_met boolean,
 run_commander_id uuid references auth.users(id) on delete set null,
 participant_user_ids uuid[] not null default '{}',
 approval_required boolean not null default true,
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 progress_percentage numeric(8,4) not null default 0 check(progress_percentage between 0 and 100),
 current_phase text,
 current_step_code text,
 result_summary text,
 lessons_learned text,
 workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,run_reference)
);
create table if not exists public.resilience_recovery_run_steps(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 recovery_run_id uuid not null references public.resilience_recovery_runs(id) on delete cascade,
 plan_step_id uuid not null references public.resilience_continuity_plan_steps(id) on delete restrict,
 step_code text not null,
 sequence_number integer not null,
 phase text not null,
 status text not null default 'pending' check(status in('pending','ready','awaiting_approval','approved','running','blocked','succeeded','succeeded_with_warnings','failed','skipped','cancelled','rolled_back')),
 assigned_user_id uuid references auth.users(id) on delete set null,
 approval_required boolean not null default false,
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 duration_seconds bigint,
 execution_input jsonb not null default '{}',
 execution_output jsonb not null default '{}',
 evidence jsonb not null default '[]',
 error_code text,
 error_message text,
 error_data jsonb not null default '{}',
 worker_reference text,
 correlation_id text,
 trace_id text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(recovery_run_id,plan_step_id),
 unique(recovery_run_id,step_code)
);
create index if not exists resilience_recovery_run_steps_execution_idx on public.resilience_recovery_run_steps(recovery_run_id,status,sequence_number);

-- 18. Failover configurations and jobs
create table if not exists public.resilience_failover_configurations(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 configuration_code text not null,
 configuration_name text not null,
 description text,
 source_environment_id uuid references public.observability_environments(id) on delete set null,
 source_service_id uuid references public.observability_services(id) on delete set null,
 recovery_site_id uuid not null references public.resilience_recovery_sites(id) on delete restrict,
 target_environment_id uuid references public.observability_environments(id) on delete set null,
 replication_configuration_id uuid references public.resilience_replication_configurations(id) on delete set null,
 failover_mode text not null default 'manual' check(failover_mode in('automatic','semi_automatic','manual','approval_gated','custom')),
 routing_strategy text check(routing_strategy is null or routing_strategy in('dns','load_balancer','service_discovery','application_config','database_promotion','manual','custom')),
 activation_conditions jsonb not null default '[]',
 prechecks jsonb not null default '[]',
 validation_checks jsonb not null default '[]',
 failback_conditions jsonb not null default '[]',
 estimated_failover_minutes integer,
 estimated_failback_minutes integer,
 data_loss_warning_threshold_seconds integer,
 approval_required boolean not null default true,
 approver_user_ids uuid[] not null default '{}',
 observability_runbook_id uuid references public.observability_runbooks(id) on delete set null,
 workflow_definition_id uuid references public.enterprise_workflow_definitions(id) on delete set null,
 status text not null default 'active' check(status in('draft','active','paused','inactive','retired','archived')),
 last_tested_at timestamptz,
 next_test_due_at timestamptz,
 last_successful_failover_at timestamptz,
 last_successful_failback_at timestamptz,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,configuration_code)
);
create table if not exists public.resilience_failover_jobs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 failover_configuration_id uuid not null references public.resilience_failover_configurations(id) on delete restrict,
 disaster_event_id uuid references public.resilience_disaster_events(id) on delete set null,
 recovery_run_id uuid references public.resilience_recovery_runs(id) on delete set null,
 job_reference text not null,
 operation_type text not null check(operation_type in('failover','failback','switchover','test_failover','test_failback')),
 status text not null default 'pending_approval' check(status in('draft','pending_approval','approved','queued','claimed','prechecking','replication_validation','routing_change','promotion','validation','completed','completed_with_warnings','failed','rolled_back','cancelled','dead_lettered')),
 priority integer not null default 10,
 available_at timestamptz not null default now(),
 approval_required boolean not null default true,
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 rejection_reason text,
 execution_parameters jsonb not null default '{}',
 attempts integer not null default 0,
 maximum_attempts integer not null default 2,
 claimed_at timestamptz,
 claimed_by text,
 lock_token text,
 lock_expires_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 duration_seconds bigint,
 progress_percentage numeric(8,4) not null default 0 check(progress_percentage between 0 and 100),
 precheck_results jsonb not null default '{}',
 validation_results jsonb not null default '{}',
 routing_change_reference text,
 promotion_reference text,
 rollback_reference text,
 estimated_data_loss_seconds bigint,
 actual_data_loss_seconds bigint,
 last_error_code text,
 last_error_message text,
 last_error_data jsonb not null default '{}',
 requested_by uuid references auth.users(id) on delete set null,
 correlation_id text,
 trace_id text,
 idempotency_key text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,job_reference)
);
create index if not exists resilience_failover_jobs_worker_idx on public.resilience_failover_jobs(status,available_at,priority,created_at) where status in('queued','failed');
create unique index if not exists resilience_failover_jobs_idem_idx on public.resilience_failover_jobs(organization_id,idempotency_key) where idempotency_key is not null;

-- 19. Exercises
create table if not exists public.resilience_exercises(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 exercise_reference text not null,
 exercise_name text not null,
 description text,
 exercise_type text not null check(exercise_type in('tabletop','walkthrough','simulation','technical_recovery','backup_restore','failover','full_interruption','communication','vendor','custom')),
 scenario_id uuid references public.resilience_disaster_scenarios(id) on delete set null,
 continuity_plan_id uuid references public.resilience_continuity_plans(id) on delete set null,
 recovery_run_id uuid references public.resilience_recovery_runs(id) on delete set null,
 scope_definition jsonb not null default '{}',
 objectives jsonb not null default '[]',
 success_criteria jsonb not null default '[]',
 coordinator_user_id uuid references auth.users(id) on delete set null,
 participant_user_ids uuid[] not null default '{}',
 observer_user_ids uuid[] not null default '{}',
 status text not null default 'planned' check(status in('draft','planned','approved','in_progress','completed','completed_with_findings','cancelled','archived')),
 planned_start_at timestamptz,
 planned_end_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 overall_result text check(overall_result is null or overall_result in('passed','passed_with_findings','failed','inconclusive')),
 score numeric(8,4),
 report_document_id uuid references public.documents(id) on delete set null,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,exercise_reference)
);
create table if not exists public.resilience_exercise_results(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 exercise_id uuid not null references public.resilience_exercises(id) on delete cascade,
 result_reference text not null,
 objective_reference text,
 area text,
 result_status text not null check(result_status in('passed','passed_with_observation','failed','not_tested','not_applicable')),
 expected_result text,
 actual_result text,
 rpo_target_minutes integer,
 rpo_actual_minutes numeric(12,4),
 rpo_met boolean,
 rto_target_minutes integer,
 rto_actual_minutes numeric(12,4),
 rto_met boolean,
 finding_severity text check(finding_severity is null or finding_severity in('informational','low','medium','high','critical')),
 finding_summary text,
 corrective_action text,
 owner_user_id uuid references auth.users(id) on delete set null,
 due_at timestamptz,
 evidence jsonb not null default '[]',
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(exercise_id,result_reference)
);

-- 20. Event outbox and logs
create table if not exists public.resilience_event_outbox(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 event_name text not null,
 source_type text,
 source_id uuid,
 destination text not null default 'internal' check(destination in('internal','automation_engine','enterprise_workflow','communication_engine','notification_engine','integration_api','ai_intelligence','reporting','mobile','security_governance','observability','n8n','analytics','audit','webhook')),
 status text not null default 'pending' check(status in('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
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
create unique index if not exists resilience_event_outbox_idem_idx on public.resilience_event_outbox(organization_id,idempotency_key) where idempotency_key is not null;
create table if not exists public.resilience_logs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete set null,
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
create index if not exists resilience_logs_org_time_idx on public.resilience_logs(organization_id,created_at desc);

-- 21. updated_at triggers
do $$
declare t text;
begin
 foreach t in array array[
  'resilience_backup_targets','resilience_backup_policies','resilience_backup_schedules','resilience_backup_jobs','resilience_backup_artifacts','resilience_restore_points','resilience_restore_requests','resilience_restore_jobs','resilience_recovery_sites','resilience_replication_configurations','resilience_recovery_objectives','resilience_business_processes','resilience_bia_assessments','resilience_continuity_plans','resilience_continuity_plan_steps','resilience_disaster_scenarios','resilience_disaster_events','resilience_recovery_runs','resilience_recovery_run_steps','resilience_failover_configurations','resilience_failover_jobs','resilience_exercises','resilience_exercise_results','resilience_event_outbox'
 ] loop
  execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
  execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
 end loop;
end $$;

-- 22. Register backup target
create or replace function public.register_resilience_backup_target(
 requested_organization_id uuid, requested_target_code text, requested_target_name text,
 requested_target_type text, requested_description text default null,
 requested_provider_name text default null, requested_region text default null,
 requested_storage_location_reference text default null,
 requested_credential_reference text default null,
 requested_encryption_key_reference text default null,
 requested_immutable_storage boolean default false,
 requested_air_gapped boolean default false,
 requested_cross_region boolean default false,
 requested_configuration jsonb default '{}'::jsonb,
 requested_metadata jsonb default '{}'::jsonb
) returns public.resilience_backup_targets
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_backup_targets;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'resilience.manage_backup_targets') then raise exception 'Permission denied'; end if;
 insert into public.resilience_backup_targets(
  organization_id,target_code,target_name,description,target_type,provider_name,region,
  storage_location_reference,credential_reference,encryption_key_reference,
  immutable_storage,air_gapped,cross_region,health_status,status,configuration,metadata,created_by,updated_by
 ) values(
  requested_organization_id,requested_target_code,requested_target_name,requested_description,
  requested_target_type,requested_provider_name,requested_region,requested_storage_location_reference,
  requested_credential_reference,requested_encryption_key_reference,requested_immutable_storage,
  requested_air_gapped,requested_cross_region,'unknown','active',coalesce(requested_configuration,'{}'),
  coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
 ) on conflict(organization_id,target_code) do update set
  target_name=excluded.target_name,description=excluded.description,target_type=excluded.target_type,
  provider_name=excluded.provider_name,region=excluded.region,
  storage_location_reference=excluded.storage_location_reference,
  credential_reference=excluded.credential_reference,encryption_key_reference=excluded.encryption_key_reference,
  immutable_storage=excluded.immutable_storage,air_gapped=excluded.air_gapped,cross_region=excluded.cross_region,
  configuration=excluded.configuration,metadata=excluded.metadata,updated_by=auth.uid(),updated_at=now()
 returning * into r;
 return r;
end $$;

-- 23. Create backup policy
create or replace function public.create_resilience_backup_policy(
 requested_organization_id uuid, requested_policy_code text, requested_policy_name text,
 requested_backup_type text, requested_scope_type text, requested_primary_target_id uuid,
 requested_scope_definition jsonb default '{}'::jsonb,
 requested_secondary_target_id uuid default null, requested_description text default null,
 requested_retention_days integer default 30, requested_minimum_restore_points integer default 1,
 requested_rpo_minutes integer default null, requested_rto_minutes integer default null,
 requested_restore_test_interval_days integer default 30, requested_owner_user_id uuid default null,
 requested_metadata jsonb default '{}'::jsonb
) returns public.resilience_backup_policies
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_backup_policies;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'resilience.manage_backup_policies') then raise exception 'Permission denied'; end if;
 if not exists(select 1 from public.resilience_backup_targets where id=requested_primary_target_id and organization_id=requested_organization_id) then raise exception 'Primary target does not belong to organization'; end if;
 if requested_secondary_target_id is not null and not exists(select 1 from public.resilience_backup_targets where id=requested_secondary_target_id and organization_id=requested_organization_id) then raise exception 'Secondary target does not belong to organization'; end if;
 insert into public.resilience_backup_policies(
  organization_id,policy_code,policy_name,description,backup_type,scope_type,scope_definition,
  primary_target_id,secondary_target_id,retention_days,minimum_restore_points,
  restore_test_interval_days,rpo_minutes,rto_minutes,owner_user_id,status,metadata,created_by,updated_by
 ) values(
  requested_organization_id,requested_policy_code,requested_policy_name,requested_description,
  requested_backup_type,requested_scope_type,coalesce(requested_scope_definition,'{}'),
  requested_primary_target_id,requested_secondary_target_id,greatest(coalesce(requested_retention_days,30),1),
  greatest(coalesce(requested_minimum_restore_points,1),1),requested_restore_test_interval_days,
  requested_rpo_minutes,requested_rto_minutes,requested_owner_user_id,'active',
  coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
 ) on conflict(organization_id,policy_code) do update set
  policy_name=excluded.policy_name,description=excluded.description,backup_type=excluded.backup_type,
  scope_type=excluded.scope_type,scope_definition=excluded.scope_definition,
  primary_target_id=excluded.primary_target_id,secondary_target_id=excluded.secondary_target_id,
  retention_days=excluded.retention_days,minimum_restore_points=excluded.minimum_restore_points,
  restore_test_interval_days=excluded.restore_test_interval_days,rpo_minutes=excluded.rpo_minutes,
  rto_minutes=excluded.rto_minutes,owner_user_id=excluded.owner_user_id,metadata=excluded.metadata,
  updated_by=auth.uid(),updated_at=now()
 returning * into r;
 return r;
end $$;

-- 24. Enqueue backup job
create or replace function public.enqueue_resilience_backup_job(
 requested_backup_policy_id uuid, requested_trigger_type text default 'manual',
 requested_backup_schedule_id uuid default null, requested_target_id uuid default null,
 requested_available_at timestamptz default now(), requested_priority integer default 100,
 requested_scope_snapshot jsonb default '{}'::jsonb,
 requested_execution_parameters jsonb default '{}'::jsonb,
 requested_idempotency_key text default null, requested_correlation_id text default null,
 requested_trace_id text default null
) returns public.resilience_backup_jobs
language plpgsql security definer set search_path=''
as $$
declare p public.resilience_backup_policies; r public.resilience_backup_jobs; existing public.resilience_backup_jobs; target uuid;
begin
 select * into p from public.resilience_backup_policies where id=requested_backup_policy_id and status='active';
 if not found then raise exception 'Active backup policy not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(p.organization_id,'resilience.execute_backups') then raise exception 'Permission denied'; end if;
 target:=coalesce(requested_target_id,p.primary_target_id);
 if not exists(select 1 from public.resilience_backup_targets where id=target and organization_id=p.organization_id and status='active') then raise exception 'Active backup target not found'; end if;
 if requested_idempotency_key is not null then
  select * into existing from public.resilience_backup_jobs where organization_id=p.organization_id and idempotency_key=requested_idempotency_key limit 1;
  if found then return existing; end if;
 end if;
 insert into public.resilience_backup_jobs(
  organization_id,backup_policy_id,backup_schedule_id,target_id,job_reference,trigger_type,
  backup_type,status,priority,available_at,scope_snapshot,execution_parameters,
  correlation_id,trace_id,idempotency_key,requested_by
 ) values(
  p.organization_id,p.id,requested_backup_schedule_id,target,
  'BKP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),requested_trigger_type,
  p.backup_type,'queued',requested_priority,coalesce(requested_available_at,now()),
  case when coalesce(requested_scope_snapshot,'{}')='{}'::jsonb then p.scope_definition else requested_scope_snapshot end,
  coalesce(requested_execution_parameters,'{}'),requested_correlation_id,requested_trace_id,
  requested_idempotency_key,auth.uid()
 ) returning * into r;
 return r;
end $$;

-- 25. Claim/start/complete/fail backup jobs
create or replace function public.claim_resilience_backup_job(
 requested_worker_id text, requested_organization_id uuid default null,
 requested_lock_seconds integer default 900
) returns public.resilience_backup_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_backup_jobs;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may claim backup jobs'; end if;
 select * into r from public.resilience_backup_jobs j
 where j.status in('queued','failed') and j.available_at<=now() and j.attempts<j.maximum_attempts
 and (j.lock_expires_at is null or j.lock_expires_at<=now())
 and (requested_organization_id is null or j.organization_id=requested_organization_id)
 order by j.priority,j.available_at,j.created_at for update skip locked limit 1;
 if not found then return null; end if;
 update public.resilience_backup_jobs set status='claimed',attempts=attempts+1,claimed_at=now(),
  claimed_by=requested_worker_id,lock_token=gen_random_uuid()::text,
  lock_expires_at=now()+make_interval(secs=>greatest(requested_lock_seconds,1)),updated_at=now()
 where id=r.id returning * into r;
 return r;
end $$;

create or replace function public.start_resilience_backup_job(
 requested_job_id uuid, requested_lock_token text,
 requested_source_snapshot_at timestamptz default now(), requested_source_lsn text default null,
 requested_source_transaction_reference text default null
) returns public.resilience_backup_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_backup_jobs;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may start backup jobs'; end if;
 select * into r from public.resilience_backup_jobs where id=requested_job_id for update;
 if not found then raise exception 'Backup job not found'; end if;
 if r.lock_token is distinct from requested_lock_token then raise exception 'Invalid backup lock token'; end if;
 if r.lock_expires_at is not null and r.lock_expires_at<=now() then raise exception 'Backup lock expired'; end if;
 update public.resilience_backup_jobs set status='running',started_at=coalesce(started_at,now()),
  source_snapshot_at=coalesce(requested_source_snapshot_at,now()),source_lsn=requested_source_lsn,
  source_transaction_reference=requested_source_transaction_reference,
  progress_percentage=greatest(progress_percentage,1),updated_at=now()
 where id=requested_job_id returning * into r;
 return r;
end $$;

create or replace function public.complete_resilience_backup_job(
 requested_job_id uuid, requested_lock_token text,
 requested_artifacts jsonb default '[]'::jsonb,
 requested_bytes_scanned bigint default null, requested_bytes_written bigint default null,
 requested_object_count bigint default null, requested_checksum_algorithm text default null,
 requested_aggregate_checksum text default null, requested_completed_with_warnings boolean default false
) returns public.resilience_backup_jobs
language plpgsql security definer set search_path=''
as $$
declare j public.resilience_backup_jobs; p public.resilience_backup_policies; a public.resilience_backup_artifacts; item jsonb; n integer:=0;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may complete backup jobs'; end if;
 select * into j from public.resilience_backup_jobs where id=requested_job_id for update;
 if not found then raise exception 'Backup job not found'; end if;
 if j.lock_token is distinct from requested_lock_token then raise exception 'Invalid backup lock token'; end if;
 select * into p from public.resilience_backup_policies where id=j.backup_policy_id;
 for item in select value from jsonb_array_elements(coalesce(requested_artifacts,'[]')) loop
  insert into public.resilience_backup_artifacts(
   organization_id,backup_job_id,target_id,artifact_reference,artifact_name,artifact_type,
   storage_path_reference,external_version_reference,size_bytes,object_count,checksum_algorithm,
   checksum_value,encryption_status,encryption_key_reference,immutability_status,artifact_status,
   backup_started_at,backup_completed_at,expires_at,immutable_until,manifest,metadata
  ) values(
   j.organization_id,j.id,j.target_id,
   coalesce(item->>'artifact_reference','ART-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18))),
   coalesce(item->>'artifact_name','Backup artifact'),coalesce(item->>'artifact_type','custom'),
   coalesce(item->>'storage_path_reference','unresolved:'||j.id::text),item->>'external_version_reference',
   nullif(item->>'size_bytes','')::bigint,nullif(item->>'object_count','')::bigint,
   coalesce(item->>'checksum_algorithm',requested_checksum_algorithm),
   coalesce(item->>'checksum_value',requested_aggregate_checksum),
   coalesce(item->>'encryption_status','unknown'),item->>'encryption_key_reference',
   coalesce(item->>'immutability_status','unknown'),'available',j.started_at,now(),
   now()+make_interval(days=>p.retention_days),
   case when item->>'immutable_until' is null then null else (item->>'immutable_until')::timestamptz end,
   coalesce(item->'manifest','{}'),coalesce(item->'metadata','{}')
  ) on conflict(organization_id,artifact_reference) do update set
   artifact_name=excluded.artifact_name,artifact_type=excluded.artifact_type,
   storage_path_reference=excluded.storage_path_reference,external_version_reference=excluded.external_version_reference,
   size_bytes=excluded.size_bytes,object_count=excluded.object_count,
   checksum_algorithm=excluded.checksum_algorithm,checksum_value=excluded.checksum_value,
   encryption_status=excluded.encryption_status,encryption_key_reference=excluded.encryption_key_reference,
   immutability_status=excluded.immutability_status,artifact_status='available',
   backup_completed_at=excluded.backup_completed_at,expires_at=excluded.expires_at,
   immutable_until=excluded.immutable_until,manifest=excluded.manifest,metadata=excluded.metadata,updated_at=now()
  returning * into a;
  n:=n+1;
 end loop;
 update public.resilience_backup_jobs set
  status=case when requested_completed_with_warnings then 'completed_with_warnings' else 'completed' end,
  completed_at=now(),duration_seconds=case when started_at is null then null else greatest(0,extract(epoch from(now()-started_at))::bigint) end,
  bytes_scanned=requested_bytes_scanned,bytes_written=requested_bytes_written,object_count=requested_object_count,
  checksum_algorithm=requested_checksum_algorithm,aggregate_checksum=requested_aggregate_checksum,
  artifact_count=n,progress_percentage=100,claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
 where id=j.id returning * into j;
 if n>0 then
  select * into a from public.resilience_backup_artifacts where backup_job_id=j.id
  order by case when artifact_type in('database_dump','snapshot') then 0 else 1 end,created_at limit 1;
  insert into public.resilience_restore_points(
   organization_id,backup_policy_id,backup_job_id,primary_artifact_id,restore_point_reference,
   restore_point_name,restore_point_type,recovery_time,source_lsn,source_transaction_reference,
   consistency_status,verification_status,restore_readiness,chain_artifact_ids,expires_at,
   next_restore_test_due_at,metadata
  ) values(
   j.organization_id,j.backup_policy_id,j.id,a.id,
   'RPT-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
   'Restore point for '||j.job_reference,
   case when j.backup_type='point_in_time' then 'point_in_time' when j.backup_type='snapshot' then 'snapshot'
    when j.backup_type in('incremental','differential') then 'incremental_chain'
    when j.backup_type='configuration' then 'configuration' when j.backup_type='logical' then 'logical' else 'full' end,
   coalesce(j.source_snapshot_at,j.completed_at,now()),j.source_lsn,j.source_transaction_reference,
   case when j.backup_type in('logical','point_in_time') then 'transaction_consistent' else 'unknown' end,
   case when p.integrity_verification_required then 'pending' else 'verified' end,
   case when p.integrity_verification_required then 'unknown' else 'ready' end,
   (select coalesce(array_agg(x.id order by x.created_at),'{}'::uuid[]) from public.resilience_backup_artifacts x where x.backup_job_id=j.id),
   now()+make_interval(days=>p.retention_days),
   case when p.restore_test_interval_days is null then null else now()+make_interval(days=>p.restore_test_interval_days) end,
   jsonb_build_object('created_from_job',j.id,'artifact_count',n)
  );
 end if;
 update public.resilience_backup_targets set health_status='healthy',last_successful_write_at=now(),
  last_error_at=null,last_error_message=null,updated_at=now() where id=j.target_id;
 return j;
end $$;

create or replace function public.fail_resilience_backup_job(
 requested_job_id uuid, requested_lock_token text, requested_error_code text,
 requested_error_message text, requested_error_data jsonb default '{}'::jsonb
) returns public.resilience_backup_jobs
language plpgsql security definer set search_path=''
as $$
declare j public.resilience_backup_jobs; next_status text; delay_seconds integer;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may fail backup jobs'; end if;
 select * into j from public.resilience_backup_jobs where id=requested_job_id for update;
 if not found then raise exception 'Backup job not found'; end if;
 if j.lock_token is distinct from requested_lock_token then raise exception 'Invalid backup lock token'; end if;
 next_status:=case when j.attempts>=j.maximum_attempts then 'dead_lettered' else 'failed' end;
 delay_seconds:=least(21600,greatest(60,power(2,greatest(j.attempts,1))::integer*60));
 update public.resilience_backup_jobs set status=next_status,
  available_at=case when next_status='failed' then now()+make_interval(secs=>delay_seconds) else available_at end,
  completed_at=case when next_status='dead_lettered' then now() else completed_at end,
  last_error_code=requested_error_code,last_error_message=requested_error_message,
  last_error_data=coalesce(requested_error_data,'{}'),claimed_at=null,claimed_by=null,
  lock_token=null,lock_expires_at=null,updated_at=now()
 where id=j.id returning * into j;
 update public.resilience_backup_targets set health_status=case when next_status='dead_lettered' then 'unhealthy' else 'degraded' end,
  last_error_at=now(),last_error_message=requested_error_message,updated_at=now() where id=j.target_id;
 insert into public.resilience_logs(organization_id,log_level,event_name,message,source_type,source_id,error_code,error_message,log_data,correlation_id,trace_id)
 values(j.organization_id,case when next_status='dead_lettered' then 'critical' else 'error' end,
  'backup_job.'||next_status,'Backup job failed','backup_job',j.id,requested_error_code,requested_error_message,
  coalesce(requested_error_data,'{}'),j.correlation_id,j.trace_id);
 return j;
end $$;

-- 26. Backup verification
create or replace function public.record_resilience_backup_verification(
 requested_backup_artifact_id uuid, requested_verification_type text, requested_status text,
 requested_expected_value text default null, requested_actual_value text default null,
 requested_findings jsonb default '[]'::jsonb, requested_verification_data jsonb default '{}'::jsonb,
 requested_error_code text default null, requested_error_message text default null,
 requested_correlation_id text default null, requested_trace_id text default null
) returns public.resilience_backup_verifications
language plpgsql security definer set search_path=''
as $$
declare a public.resilience_backup_artifacts; v public.resilience_backup_verifications; agg text;
begin
 select * into a from public.resilience_backup_artifacts where id=requested_backup_artifact_id for update;
 if not found then raise exception 'Backup artifact not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(a.organization_id,'resilience.verify_backups') then raise exception 'Permission denied'; end if;
 insert into public.resilience_backup_verifications(
  organization_id,backup_artifact_id,verification_reference,verification_type,status,
  expected_value,actual_value,findings,verification_data,started_at,completed_at,duration_seconds,
  verified_by,error_code,error_message,correlation_id,trace_id
 ) values(
  a.organization_id,a.id,'VER-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
  requested_verification_type,requested_status,requested_expected_value,requested_actual_value,
  coalesce(requested_findings,'[]'),coalesce(requested_verification_data,'{}'),now(),now(),0,
  auth.uid(),requested_error_code,requested_error_message,requested_correlation_id,requested_trace_id
 ) returning * into v;
 select case
  when exists(select 1 from public.resilience_backup_verifications where backup_artifact_id=a.id and status in('failed','error')) then 'failed'
  when exists(select 1 from public.resilience_backup_verifications where backup_artifact_id=a.id and status='passed_with_warnings') then 'verified_with_warnings'
  when exists(select 1 from public.resilience_backup_verifications where backup_artifact_id=a.id and status in('pending','running')) then 'pending'
  else 'verified' end into agg;
 update public.resilience_backup_artifacts set artifact_status=case when agg='failed' then 'corrupt' when agg in('verified','verified_with_warnings') then 'verified' else artifact_status end,
  verified_at=case when agg in('verified','verified_with_warnings') then now() else verified_at end,updated_at=now() where id=a.id;
 update public.resilience_restore_points set verification_status=agg,
  restore_readiness=case when agg='verified' then 'ready' when agg='verified_with_warnings' then 'ready_with_warnings' when agg='failed' then 'not_ready' else 'unknown' end,
  updated_at=now() where primary_artifact_id=a.id or a.id=any(chain_artifact_ids);
 return v;
end $$;

-- 27. Restore request and approval
create or replace function public.create_resilience_restore_request(
 requested_restore_point_id uuid, requested_restore_type text, requested_target_type text,
 requested_business_justification text, requested_environment_id uuid default null,
 requested_service_id uuid default null, requested_target_reference text default null,
 requested_recovery_time timestamptz default null, requested_scope_definition jsonb default '{}'::jsonb,
 requested_risk_level text default 'high', requested_data_overwrite_expected boolean default false,
 requested_production_impact_expected boolean default false,
 requested_customer_impact_expected boolean default false,
 requested_approver_user_ids uuid[] default '{}', requested_expires_at timestamptz default null,
 requested_correlation_id text default null, requested_trace_id text default null,
 requested_metadata jsonb default '{}'::jsonb
) returns public.resilience_restore_requests
language plpgsql security definer set search_path=''
as $$
declare rp public.resilience_restore_points; r public.resilience_restore_requests;
begin
 select * into rp from public.resilience_restore_points where id=requested_restore_point_id;
 if not found then raise exception 'Restore point not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(rp.organization_id,'resilience.manage_restores') then raise exception 'Permission denied'; end if;
 if rp.restore_readiness in('not_ready','expired') then raise exception 'Restore point is not ready'; end if;
 insert into public.resilience_restore_requests(
  organization_id,request_reference,restore_point_id,requested_environment_id,requested_service_id,
  restore_type,target_type,target_reference,requested_recovery_time,scope_definition,business_justification,
  risk_level,data_overwrite_expected,production_impact_expected,customer_impact_expected,
  pre_restore_backup_required,validation_required,status,approver_user_ids,expires_at,requested_by,
  correlation_id,trace_id,metadata
 ) values(
  rp.organization_id,'RST-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),rp.id,
  requested_environment_id,requested_service_id,requested_restore_type,requested_target_type,
  requested_target_reference,requested_recovery_time,coalesce(requested_scope_definition,'{}'),
  requested_business_justification,requested_risk_level,requested_data_overwrite_expected,
  requested_production_impact_expected,requested_customer_impact_expected,
  requested_target_type='original' or requested_production_impact_expected,true,'pending_approval',
  coalesce(requested_approver_user_ids,'{}'),requested_expires_at,auth.uid(),requested_correlation_id,
  requested_trace_id,coalesce(requested_metadata,'{}')
 ) returning * into r;
 return r;
end $$;

create or replace function public.respond_resilience_restore_request(
 requested_restore_request_id uuid, requested_approved boolean, requested_reason text default null
) returns public.resilience_restore_requests
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_restore_requests;
begin
 select * into r from public.resilience_restore_requests where id=requested_restore_request_id for update;
 if not found then raise exception 'Restore request not found'; end if;
 if r.status<>'pending_approval' then raise exception 'Restore request is not pending approval'; end if;
 if auth.role()<>'service_role' and auth.uid()<>all(r.approver_user_ids)
  and not public.has_organization_permission(r.organization_id,'resilience.approve_restores') then raise exception 'Permission denied'; end if;
 update public.resilience_restore_requests set status=case when requested_approved then 'approved' else 'rejected' end,
  approved_by=case when requested_approved then auth.uid() else approved_by end,
  approved_at=case when requested_approved then now() else approved_at end,
  rejected_by=case when requested_approved then rejected_by else auth.uid() end,
  rejected_at=case when requested_approved then rejected_at else now() end,
  rejection_reason=case when requested_approved then rejection_reason else requested_reason end,updated_at=now()
 where id=r.id returning * into r;
 return r;
end $$;

-- 28. Restore job queue
create or replace function public.enqueue_resilience_restore_job(
 requested_restore_request_id uuid, requested_available_at timestamptz default now(),
 requested_priority integer default 50, requested_execution_parameters jsonb default '{}'::jsonb,
 requested_idempotency_key text default null
) returns public.resilience_restore_jobs
language plpgsql security definer set search_path=''
as $$
declare rr public.resilience_restore_requests; r public.resilience_restore_jobs; existing public.resilience_restore_jobs;
begin
 select * into rr from public.resilience_restore_requests where id=requested_restore_request_id for update;
 if not found then raise exception 'Restore request not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(rr.organization_id,'resilience.manage_restores') then raise exception 'Permission denied'; end if;
 if rr.status<>'approved' then raise exception 'Restore request must be approved'; end if;
 if rr.expires_at is not null and rr.expires_at<=now() then update public.resilience_restore_requests set status='expired',updated_at=now() where id=rr.id; raise exception 'Restore request expired'; end if;
 if requested_idempotency_key is not null then
  select * into existing from public.resilience_restore_jobs where organization_id=rr.organization_id and idempotency_key=requested_idempotency_key limit 1;
  if found then return existing; end if;
 end if;
 insert into public.resilience_restore_jobs(
  organization_id,restore_request_id,restore_point_id,job_reference,status,priority,available_at,
  execution_parameters,correlation_id,trace_id,idempotency_key
 ) values(
  rr.organization_id,rr.id,rr.restore_point_id,'RSJ-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
  'queued',requested_priority,coalesce(requested_available_at,now()),coalesce(requested_execution_parameters,'{}'),
  rr.correlation_id,rr.trace_id,requested_idempotency_key
 ) returning * into r;
 update public.resilience_restore_requests set status='queued',updated_at=now() where id=rr.id;
 return r;
end $$;

create or replace function public.claim_resilience_restore_job(
 requested_worker_id text, requested_organization_id uuid default null,
 requested_lock_seconds integer default 1800
) returns public.resilience_restore_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_restore_jobs;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may claim restore jobs'; end if;
 select * into r from public.resilience_restore_jobs j where j.status in('queued','failed') and j.available_at<=now()
  and j.attempts<j.maximum_attempts and (j.lock_expires_at is null or j.lock_expires_at<=now())
  and (requested_organization_id is null or j.organization_id=requested_organization_id)
 order by j.priority,j.available_at,j.created_at for update skip locked limit 1;
 if not found then return null; end if;
 update public.resilience_restore_jobs set status='claimed',attempts=attempts+1,claimed_at=now(),
  claimed_by=requested_worker_id,lock_token=gen_random_uuid()::text,
  lock_expires_at=now()+make_interval(secs=>greatest(requested_lock_seconds,1)),started_at=coalesce(started_at,now()),updated_at=now()
 where id=r.id returning * into r;
 update public.resilience_restore_requests set status='in_progress',updated_at=now() where id=r.restore_request_id;
 return r;
end $$;

create or replace function public.complete_resilience_restore_job(
 requested_job_id uuid, requested_lock_token text, requested_validation_status text default 'passed',
 requested_validation_results jsonb default '{}'::jsonb, requested_restored_bytes bigint default null,
 requested_restored_object_count bigint default null, requested_completed_with_warnings boolean default false
) returns public.resilience_restore_jobs
language plpgsql security definer set search_path=''
as $$
declare j public.resilience_restore_jobs; rr public.resilience_restore_requests;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may complete restore jobs'; end if;
 select * into j from public.resilience_restore_jobs where id=requested_job_id for update;
 if not found then raise exception 'Restore job not found'; end if;
 if j.lock_token is distinct from requested_lock_token then raise exception 'Invalid restore lock token'; end if;
 update public.resilience_restore_jobs set
  status=case when requested_completed_with_warnings or requested_validation_status='passed_with_warnings' then 'completed_with_warnings' else 'completed' end,
  validation_status=requested_validation_status,validation_results=coalesce(requested_validation_results,'{}'),
  restored_bytes=requested_restored_bytes,restored_object_count=requested_restored_object_count,
  progress_percentage=100,completed_at=now(),duration_seconds=case when started_at is null then null else greatest(0,extract(epoch from(now()-started_at))::bigint) end,
  claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
 where id=j.id returning * into j;
 update public.resilience_restore_requests set status=case when j.status='completed_with_warnings' then 'completed_with_warnings' else 'completed' end,updated_at=now()
 where id=j.restore_request_id returning * into rr;
 update public.resilience_restore_points set
  last_restore_test_at=case when rr.restore_type='test_restore' then now() else last_restore_test_at end,
  restore_readiness=case when requested_validation_status='passed' then 'ready' when requested_validation_status='passed_with_warnings' then 'ready_with_warnings' when requested_validation_status='failed' then 'not_ready' else restore_readiness end,
  updated_at=now() where id=j.restore_point_id;
 return j;
end $$;

create or replace function public.fail_resilience_restore_job(
 requested_job_id uuid, requested_lock_token text, requested_error_code text,
 requested_error_message text, requested_error_data jsonb default '{}'::jsonb,
 requested_rolled_back boolean default false
) returns public.resilience_restore_jobs
language plpgsql security definer set search_path=''
as $$
declare j public.resilience_restore_jobs; next_status text;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may fail restore jobs'; end if;
 select * into j from public.resilience_restore_jobs where id=requested_job_id for update;
 if not found then raise exception 'Restore job not found'; end if;
 if j.lock_token is distinct from requested_lock_token then raise exception 'Invalid restore lock token'; end if;
 next_status:=case when requested_rolled_back then 'rolled_back' when j.attempts>=j.maximum_attempts then 'dead_lettered' else 'failed' end;
 update public.resilience_restore_jobs set status=next_status,
  available_at=case when next_status='failed' then now()+interval '10 minutes' else available_at end,
  completed_at=case when next_status in('rolled_back','dead_lettered') then now() else completed_at end,
  last_error_code=requested_error_code,last_error_message=requested_error_message,
  last_error_data=coalesce(requested_error_data,'{}'),claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
 where id=j.id returning * into j;
 update public.resilience_restore_requests set status=case when next_status='failed' then 'in_progress' else 'failed' end,updated_at=now() where id=j.restore_request_id;
 return j;
end $$;

-- 29. Replication snapshot
create or replace function public.record_resilience_replication_snapshot(
 requested_replication_configuration_id uuid, requested_status text,
 requested_lag_seconds bigint default null, requested_lag_bytes bigint default null,
 requested_source_position text default null, requested_target_position text default null,
 requested_source_timestamp timestamptz default null, requested_target_timestamp timestamptz default null,
 requested_last_successful_sync_at timestamptz default null,
 requested_error_code text default null, requested_error_message text default null,
 requested_details jsonb default '{}'::jsonb
) returns public.resilience_replication_snapshots
language plpgsql security definer set search_path=''
as $$
declare c public.resilience_replication_configurations; r public.resilience_replication_snapshots; effective text;
begin
 select * into c from public.resilience_replication_configurations where id=requested_replication_configuration_id for update;
 if not found then raise exception 'Replication configuration not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(c.organization_id,'resilience.manage_replication') then raise exception 'Permission denied'; end if;
 effective:=requested_status;
 if requested_lag_seconds is not null and c.maximum_lag_seconds is not null and requested_lag_seconds>c.maximum_lag_seconds then
  effective:=case when requested_lag_seconds>c.maximum_lag_seconds*3 then 'critical' else 'warning' end;
 end if;
 insert into public.resilience_replication_snapshots(
  organization_id,replication_configuration_id,snapshot_reference,status,source_position,target_position,
  lag_seconds,lag_bytes,source_timestamp,target_timestamp,last_successful_sync_at,error_code,error_message,details
 ) values(
  c.organization_id,c.id,'RPS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),effective,
  requested_source_position,requested_target_position,requested_lag_seconds,requested_lag_bytes,
  requested_source_timestamp,requested_target_timestamp,requested_last_successful_sync_at,
  requested_error_code,requested_error_message,coalesce(requested_details,'{}')
 ) returning * into r;
 update public.resilience_replication_configurations set
  status=case when effective='healthy' then 'active' when effective='warning' then 'degraded'
    when effective in('critical','failed') then 'failed' when effective='paused' then 'paused' else status end,
  last_sync_at=coalesce(requested_last_successful_sync_at,last_sync_at),
  last_error_at=case when effective in('critical','failed') then now() else last_error_at end,
  last_error_message=case when effective in('critical','failed') then requested_error_message else last_error_message end,
  updated_at=now() where id=c.id;
 return r;
end $$;

-- 30. Create continuity plan
create or replace function public.create_resilience_continuity_plan(
 requested_organization_id uuid, requested_plan_code text, requested_plan_name text,
 requested_plan_type text, requested_description text default null,
 requested_scope_definition jsonb default '{}'::jsonb,
 requested_business_process_ids uuid[] default '{}', requested_service_ids uuid[] default '{}',
 requested_recovery_objective_ids uuid[] default '{}', requested_primary_recovery_site_id uuid default null,
 requested_owner_user_id uuid default null, requested_coordinator_user_id uuid default null,
 requested_activation_authority_user_ids uuid[] default '{}',
 requested_activation_criteria jsonb default '[]'::jsonb,
 requested_communication_strategy jsonb default '{}'::jsonb,
 requested_plan_document_id uuid default null, requested_workflow_definition_id uuid default null,
 requested_review_due_at date default null, requested_metadata jsonb default '{}'::jsonb
) returns public.resilience_continuity_plans
language plpgsql security definer set search_path=''
as $$
declare n integer; r public.resilience_continuity_plans;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'resilience.manage_continuity_plans') then raise exception 'Permission denied'; end if;
 select coalesce(max(version_number),0)+1 into n from public.resilience_continuity_plans where organization_id=requested_organization_id and plan_code=requested_plan_code;
 update public.resilience_continuity_plans set status='superseded',updated_at=now()
  where organization_id=requested_organization_id and plan_code=requested_plan_code and status in('approved','active');
 insert into public.resilience_continuity_plans(
  organization_id,plan_code,plan_name,description,plan_type,scope_definition,business_process_ids,
  service_ids,recovery_objective_ids,primary_recovery_site_id,owner_user_id,coordinator_user_id,
  activation_authority_user_ids,status,version_number,review_due_at,plan_document_id,
  workflow_definition_id,activation_criteria,communication_strategy,metadata,created_by,updated_by
 ) values(
  requested_organization_id,requested_plan_code,requested_plan_name,requested_description,requested_plan_type,
  coalesce(requested_scope_definition,'{}'),coalesce(requested_business_process_ids,'{}'),coalesce(requested_service_ids,'{}'),
  coalesce(requested_recovery_objective_ids,'{}'),requested_primary_recovery_site_id,requested_owner_user_id,
  requested_coordinator_user_id,coalesce(requested_activation_authority_user_ids,'{}'),'draft',n,
  requested_review_due_at,requested_plan_document_id,requested_workflow_definition_id,
  coalesce(requested_activation_criteria,'[]'),coalesce(requested_communication_strategy,'{}'),
  coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
 ) returning * into r;
 return r;
end $$;

-- 31. Declare disaster event
create or replace function public.declare_resilience_disaster_event(
 requested_organization_id uuid, requested_event_title text, requested_event_type text,
 requested_description text default null, requested_scenario_id uuid default null,
 requested_severity text default 'high', requested_source_type text default null,
 requested_source_reference text default null, requested_observability_incident_id uuid default null,
 requested_security_incident_id uuid default null, requested_affected_environment_ids uuid[] default '{}',
 requested_affected_service_ids uuid[] default '{}', requested_affected_process_ids uuid[] default '{}',
 requested_customer_impact text default null, requested_business_impact text default null,
 requested_declaration_reason text default null, requested_event_commander_id uuid default null,
 requested_response_team_user_ids uuid[] default '{}', requested_correlation_id text default null,
 requested_trace_id text default null, requested_metadata jsonb default '{}'::jsonb
) returns public.resilience_disaster_events
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_disaster_events;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'resilience.manage_disaster_events') then raise exception 'Permission denied'; end if;
 insert into public.resilience_disaster_events(
  organization_id,event_reference,event_title,description,scenario_id,event_type,severity,status,
  source_type,source_reference,related_observability_incident_id,related_security_incident_id,
  affected_environment_ids,affected_service_ids,affected_process_ids,customer_impact,business_impact,
  declared_by,event_commander_id,response_team_user_ids,detected_at,assessed_at,declared_at,
  declaration_reason,correlation_id,trace_id,metadata,created_by,updated_by
 ) values(
  requested_organization_id,'DRE-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
  requested_event_title,requested_description,requested_scenario_id,requested_event_type,requested_severity,'declared',
  requested_source_type,requested_source_reference,requested_observability_incident_id,requested_security_incident_id,
  coalesce(requested_affected_environment_ids,'{}'),coalesce(requested_affected_service_ids,'{}'),
  coalesce(requested_affected_process_ids,'{}'),requested_customer_impact,requested_business_impact,
  auth.uid(),requested_event_commander_id,coalesce(requested_response_team_user_ids,'{}'),now(),now(),now(),
  requested_declaration_reason,requested_correlation_id,requested_trace_id,coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
 ) returning * into r;
 return r;
end $$;

-- 32. Start and approve recovery run
create or replace function public.start_resilience_recovery_run(
 requested_continuity_plan_id uuid, requested_disaster_event_id uuid default null,
 requested_run_type text default 'actual', requested_recovery_site_id uuid default null,
 requested_run_commander_id uuid default null, requested_participant_user_ids uuid[] default '{}',
 requested_target_rpo_minutes integer default null, requested_target_rto_minutes integer default null,
 requested_approval_required boolean default true, requested_correlation_id text default null,
 requested_trace_id text default null, requested_metadata jsonb default '{}'::jsonb
) returns public.resilience_recovery_runs
language plpgsql security definer set search_path=''
as $$
declare p public.resilience_continuity_plans; r public.resilience_recovery_runs; first_seq integer;
begin
 select * into p from public.resilience_continuity_plans where id=requested_continuity_plan_id and status in('approved','active');
 if not found then raise exception 'Approved or active plan not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(p.organization_id,'resilience.execute_recovery') then raise exception 'Permission denied'; end if;
 insert into public.resilience_recovery_runs(
  organization_id,run_reference,disaster_event_id,continuity_plan_id,run_type,status,recovery_site_id,
  target_rpo_minutes,target_rto_minutes,run_commander_id,participant_user_ids,approval_required,
  started_at,correlation_id,trace_id,metadata,created_by,updated_by
 ) values(
  p.organization_id,'RRN-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),requested_disaster_event_id,p.id,
  requested_run_type,case when requested_approval_required then 'awaiting_approval' else 'running' end,
  coalesce(requested_recovery_site_id,p.primary_recovery_site_id),requested_target_rpo_minutes,requested_target_rto_minutes,
  requested_run_commander_id,coalesce(requested_participant_user_ids,'{}'),requested_approval_required,
  case when requested_approval_required then null else now() end,requested_correlation_id,requested_trace_id,
  coalesce(requested_metadata,'{}'),auth.uid(),auth.uid()
 ) returning * into r;
 select min(sequence_number) into first_seq from public.resilience_continuity_plan_steps where continuity_plan_id=p.id and status='active';
 insert into public.resilience_recovery_run_steps(
  organization_id,recovery_run_id,plan_step_id,step_code,sequence_number,phase,status,assigned_user_id,
  approval_required,execution_input,correlation_id,trace_id
 ) select p.organization_id,r.id,s.id,s.step_code,s.sequence_number,s.phase,
  case when r.status='running' and s.sequence_number=first_seq then case when s.requires_approval then 'awaiting_approval' else 'ready' end else 'pending' end,
  s.responsible_user_id,s.requires_approval,s.execution_parameters,requested_correlation_id,requested_trace_id
 from public.resilience_continuity_plan_steps s where s.continuity_plan_id=p.id and s.status='active' order by s.sequence_number;
 if requested_disaster_event_id is not null then
  update public.resilience_disaster_events set status='plan_activated',plan_activated_at=now(),updated_at=now()
  where id=requested_disaster_event_id and organization_id=p.organization_id;
 end if;
 return r;
end $$;

create or replace function public.approve_resilience_recovery_run(
 requested_recovery_run_id uuid, requested_approved boolean, requested_reason text default null
) returns public.resilience_recovery_runs
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_recovery_runs; p public.resilience_continuity_plans; first_seq integer;
begin
 select * into r from public.resilience_recovery_runs where id=requested_recovery_run_id for update;
 if not found then raise exception 'Recovery run not found'; end if;
 select * into p from public.resilience_continuity_plans where id=r.continuity_plan_id;
 if auth.role()<>'service_role' and auth.uid()<>all(p.activation_authority_user_ids)
  and not public.has_organization_permission(r.organization_id,'resilience.execute_recovery') then raise exception 'Permission denied'; end if;
 if r.status<>'awaiting_approval' then raise exception 'Recovery run is not awaiting approval'; end if;
 update public.resilience_recovery_runs set status=case when requested_approved then 'running' else 'cancelled' end,
  approved_by=case when requested_approved then auth.uid() else approved_by end,
  approved_at=case when requested_approved then now() else approved_at end,
  started_at=case when requested_approved then coalesce(started_at,now()) else started_at end,
  result_summary=case when requested_approved then result_summary else requested_reason end,
  updated_by=auth.uid(),updated_at=now() where id=r.id returning * into r;
 if requested_approved then
  select min(sequence_number) into first_seq from public.resilience_recovery_run_steps where recovery_run_id=r.id;
  update public.resilience_recovery_run_steps set status=case when approval_required then 'awaiting_approval' else 'ready' end,updated_at=now()
  where recovery_run_id=r.id and sequence_number=first_seq and status='pending';
 end if;
 return r;
end $$;

-- 33. Update recovery step
create or replace function public.update_resilience_recovery_run_step(
 requested_run_step_id uuid, requested_status text,
 requested_execution_output jsonb default '{}'::jsonb, requested_evidence jsonb default '[]'::jsonb,
 requested_error_code text default null, requested_error_message text default null,
 requested_error_data jsonb default '{}'::jsonb
) returns public.resilience_recovery_run_steps
language plpgsql security definer set search_path=''
as $$
declare s public.resilience_recovery_run_steps; r public.resilience_recovery_runs; total integer; done integer; failed integer; next_seq integer;
begin
 select * into s from public.resilience_recovery_run_steps where id=requested_run_step_id for update;
 if not found then raise exception 'Recovery run step not found'; end if;
 if auth.role()<>'service_role' and auth.uid() is distinct from s.assigned_user_id
  and not public.has_organization_permission(s.organization_id,'resilience.execute_recovery') then raise exception 'Permission denied'; end if;
 update public.resilience_recovery_run_steps set status=requested_status,
  started_at=case when requested_status='running' then coalesce(started_at,now()) else started_at end,
  completed_at=case when requested_status in('succeeded','succeeded_with_warnings','failed','skipped','cancelled','rolled_back') then now() else completed_at end,
  duration_seconds=case when requested_status in('succeeded','succeeded_with_warnings','failed','skipped','cancelled','rolled_back') and started_at is not null then greatest(0,extract(epoch from(now()-started_at))::bigint) else duration_seconds end,
  execution_output=coalesce(requested_execution_output,'{}'),evidence=coalesce(requested_evidence,'[]'),
  error_code=requested_error_code,error_message=requested_error_message,error_data=coalesce(requested_error_data,'{}'),updated_at=now()
 where id=s.id returning * into s;
 select * into r from public.resilience_recovery_runs where id=s.recovery_run_id for update;
 select count(*) into total from public.resilience_recovery_run_steps where recovery_run_id=r.id;
 select count(*) into done from public.resilience_recovery_run_steps where recovery_run_id=r.id and status in('succeeded','succeeded_with_warnings','skipped','rolled_back');
 select count(*) into failed from public.resilience_recovery_run_steps where recovery_run_id=r.id and status='failed';
 update public.resilience_recovery_runs set
  progress_percentage=case when total=0 then 0 else round(done::numeric/total::numeric*100,4) end,
  current_phase=s.phase,current_step_code=s.step_code,
  status=case when failed>0 then 'failed' when done=total and total>0 then
   case when exists(select 1 from public.resilience_recovery_run_steps x where x.recovery_run_id=r.id and x.status='succeeded_with_warnings') then 'completed_with_warnings' else 'completed' end else status end,
  completed_at=case when failed>0 or(done=total and total>0) then now() else completed_at end,
  actual_recovery_time_minutes=case when started_at is not null and(failed>0 or(done=total and total>0)) then extract(epoch from(now()-started_at))/60 else actual_recovery_time_minutes end,
  rto_met=case when target_rto_minutes is not null and started_at is not null and(failed>0 or(done=total and total>0)) then extract(epoch from(now()-started_at))/60<=target_rto_minutes else rto_met end,
  updated_at=now() where id=r.id returning * into r;
 if requested_status in('succeeded','succeeded_with_warnings','skipped') then
  select min(sequence_number) into next_seq from public.resilience_recovery_run_steps where recovery_run_id=r.id and sequence_number>s.sequence_number and status='pending';
  if next_seq is not null then update public.resilience_recovery_run_steps set status=case when approval_required then 'awaiting_approval' else 'ready' end,updated_at=now()
   where recovery_run_id=r.id and sequence_number=next_seq and status='pending'; end if;
 end if;
 return s;
end $$;

-- 34. Failover job creation, approval and worker claim
create or replace function public.create_resilience_failover_job(
 requested_failover_configuration_id uuid, requested_operation_type text,
 requested_disaster_event_id uuid default null, requested_recovery_run_id uuid default null,
 requested_execution_parameters jsonb default '{}'::jsonb, requested_idempotency_key text default null,
 requested_correlation_id text default null, requested_trace_id text default null
) returns public.resilience_failover_jobs
language plpgsql security definer set search_path=''
as $$
declare c public.resilience_failover_configurations; r public.resilience_failover_jobs; existing public.resilience_failover_jobs;
begin
 select * into c from public.resilience_failover_configurations where id=requested_failover_configuration_id and status='active';
 if not found then raise exception 'Active failover configuration not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(c.organization_id,'resilience.manage_failover') then raise exception 'Permission denied'; end if;
 if requested_idempotency_key is not null then select * into existing from public.resilience_failover_jobs where organization_id=c.organization_id and idempotency_key=requested_idempotency_key limit 1; if found then return existing; end if; end if;
 insert into public.resilience_failover_jobs(
  organization_id,failover_configuration_id,disaster_event_id,recovery_run_id,job_reference,
  operation_type,status,priority,available_at,approval_required,execution_parameters,requested_by,
  correlation_id,trace_id,idempotency_key
 ) values(
  c.organization_id,c.id,requested_disaster_event_id,requested_recovery_run_id,
  'FOV-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),requested_operation_type,
  case when c.approval_required then 'pending_approval' else 'queued' end,10,now(),c.approval_required,
  coalesce(requested_execution_parameters,'{}'),auth.uid(),requested_correlation_id,requested_trace_id,requested_idempotency_key
 ) returning * into r;
 return r;
end $$;

create or replace function public.respond_resilience_failover_job(
 requested_failover_job_id uuid, requested_approved boolean, requested_reason text default null
) returns public.resilience_failover_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_failover_jobs; c public.resilience_failover_configurations;
begin
 select * into r from public.resilience_failover_jobs where id=requested_failover_job_id for update;
 if not found then raise exception 'Failover job not found'; end if;
 select * into c from public.resilience_failover_configurations where id=r.failover_configuration_id;
 if r.status<>'pending_approval' then raise exception 'Failover job is not pending approval'; end if;
 if auth.role()<>'service_role' and auth.uid()<>all(c.approver_user_ids)
  and not public.has_organization_permission(r.organization_id,'resilience.approve_failover') then raise exception 'Permission denied'; end if;
 update public.resilience_failover_jobs set status=case when requested_approved then 'queued' else 'cancelled' end,
  approved_by=case when requested_approved then auth.uid() else approved_by end,
  approved_at=case when requested_approved then now() else approved_at end,
  rejection_reason=case when requested_approved then rejection_reason else requested_reason end,updated_at=now()
 where id=r.id returning * into r;
 return r;
end $$;

create or replace function public.claim_resilience_failover_job(
 requested_worker_id text, requested_organization_id uuid default null,
 requested_lock_seconds integer default 1800
) returns public.resilience_failover_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_failover_jobs;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may claim failover jobs'; end if;
 select * into r from public.resilience_failover_jobs j where j.status in('queued','failed') and j.available_at<=now()
  and j.attempts<j.maximum_attempts and(j.lock_expires_at is null or j.lock_expires_at<=now())
  and(requested_organization_id is null or j.organization_id=requested_organization_id)
 order by j.priority,j.available_at,j.created_at for update skip locked limit 1;
 if not found then return null; end if;
 update public.resilience_failover_jobs set status='claimed',attempts=attempts+1,claimed_at=now(),
  claimed_by=requested_worker_id,lock_token=gen_random_uuid()::text,
  lock_expires_at=now()+make_interval(secs=>greatest(requested_lock_seconds,1)),started_at=coalesce(started_at,now()),updated_at=now()
 where id=r.id returning * into r;
 return r;
end $$;

create or replace function public.complete_resilience_failover_job(
 requested_job_id uuid, requested_lock_token text,
 requested_precheck_results jsonb default '{}'::jsonb,
 requested_validation_results jsonb default '{}'::jsonb,
 requested_routing_change_reference text default null,
 requested_promotion_reference text default null,
 requested_actual_data_loss_seconds bigint default null,
 requested_completed_with_warnings boolean default false
) returns public.resilience_failover_jobs
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_failover_jobs;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may complete failover jobs'; end if;
 select * into r from public.resilience_failover_jobs where id=requested_job_id for update;
 if not found then raise exception 'Failover job not found'; end if;
 if r.lock_token is distinct from requested_lock_token then raise exception 'Invalid failover lock token'; end if;
 update public.resilience_failover_jobs set
  status=case when requested_completed_with_warnings then 'completed_with_warnings' else 'completed' end,
  precheck_results=coalesce(requested_precheck_results,'{}'),validation_results=coalesce(requested_validation_results,'{}'),
  routing_change_reference=requested_routing_change_reference,promotion_reference=requested_promotion_reference,
  actual_data_loss_seconds=requested_actual_data_loss_seconds,progress_percentage=100,completed_at=now(),
  duration_seconds=case when started_at is null then null else greatest(0,extract(epoch from(now()-started_at))::bigint) end,
  claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
 where id=r.id returning * into r;
 update public.resilience_failover_configurations set
  last_successful_failover_at=case when r.operation_type in('failover','switchover','test_failover') then now() else last_successful_failover_at end,
  last_successful_failback_at=case when r.operation_type in('failback','test_failback') then now() else last_successful_failback_at end,
  last_tested_at=case when r.operation_type in('test_failover','test_failback') then now() else last_tested_at end,updated_at=now()
 where id=r.failover_configuration_id;
 return r;
end $$;

-- 35. Event publishing
create or replace function public.publish_resilience_event(
 requested_organization_id uuid, requested_event_name text,
 requested_payload jsonb default '{}'::jsonb, requested_destination text default 'internal',
 requested_source_type text default null, requested_source_id uuid default null,
 requested_priority integer default 100, requested_idempotency_key text default null,
 requested_correlation_id text default null, requested_trace_id text default null,
 requested_available_at timestamptz default now()
) returns public.resilience_event_outbox
language plpgsql security definer set search_path=''
as $$
declare r public.resilience_event_outbox; existing public.resilience_event_outbox;
begin
 if requested_idempotency_key is not null then
  select * into existing from public.resilience_event_outbox where organization_id is not distinct from requested_organization_id and idempotency_key=requested_idempotency_key limit 1;
  if found then return existing; end if;
 end if;
 insert into public.resilience_event_outbox(
  organization_id,event_name,source_type,source_id,destination,status,priority,idempotency_key,
  correlation_id,trace_id,payload,available_at
 ) values(
  requested_organization_id,requested_event_name,requested_source_type,requested_source_id,requested_destination,
  'pending',requested_priority,requested_idempotency_key,requested_correlation_id,requested_trace_id,
  coalesce(requested_payload,'{}'),coalesce(requested_available_at,now())
 ) returning * into r;
 return r;
end $$;

-- 36. Retention metadata expiry
create or replace function public.expire_resilience_records(
 requested_organization_id uuid, requested_dry_run boolean default true,
 requested_batch_limit integer default 10000
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare artifacts bigint; points bigint; requests bigint; logs bigint;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(requested_organization_id,'resilience.manage_retention') then raise exception 'Permission denied'; end if;
 select count(*) into artifacts from public.resilience_backup_artifacts where organization_id=requested_organization_id and expires_at<=now() and artifact_status not in('deleted','expired') and(immutable_until is null or immutable_until<=now());
 select count(*) into points from public.resilience_restore_points where organization_id=requested_organization_id and expires_at<=now() and restore_readiness<>'expired';
 select count(*) into requests from public.resilience_restore_requests where organization_id=requested_organization_id and expires_at<=now() and status in('draft','pending_approval','approved');
 select count(*) into logs from public.resilience_logs where organization_id=requested_organization_id and created_at<now()-interval '730 days';
 if not requested_dry_run then
  update public.resilience_backup_artifacts set artifact_status='expired',updated_at=now() where id in(
   select id from public.resilience_backup_artifacts where organization_id=requested_organization_id and expires_at<=now()
    and artifact_status not in('deleted','expired') and(immutable_until is null or immutable_until<=now()) order by expires_at limit greatest(requested_batch_limit,1));
  update public.resilience_restore_points set verification_status='expired',restore_readiness='expired',updated_at=now() where id in(
   select id from public.resilience_restore_points where organization_id=requested_organization_id and expires_at<=now() and restore_readiness<>'expired' order by expires_at limit greatest(requested_batch_limit,1));
  update public.resilience_restore_requests set status='expired',updated_at=now() where id in(
   select id from public.resilience_restore_requests where organization_id=requested_organization_id and expires_at<=now() and status in('draft','pending_approval','approved') order by expires_at limit greatest(requested_batch_limit,1));
  delete from public.resilience_logs where id in(
   select id from public.resilience_logs where organization_id=requested_organization_id and created_at<now()-interval '730 days' order by created_at limit greatest(requested_batch_limit,1));
 end if;
 return jsonb_build_object('organization_id',requested_organization_id,'dry_run',requested_dry_run,
  'eligible_records',jsonb_build_object('backup_artifacts',artifacts,'restore_points',points,'restore_requests',requests,'logs',logs),'completed_at',now());
end $$;

-- 37. Event triggers
create or replace function public.emit_resilience_backup_job_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if tg_op='UPDATE' and new.status is not distinct from old.status then return new; end if;
 perform public.publish_resilience_event(
  new.organization_id,'resilience.backup_job.'||new.status,
  jsonb_build_object('backup_job_id',new.id,'job_reference',new.job_reference,'backup_policy_id',new.backup_policy_id,
   'target_id',new.target_id,'backup_type',new.backup_type,'status',new.status,'attempts',new.attempts,
   'maximum_attempts',new.maximum_attempts,'bytes_written',new.bytes_written,'artifact_count',new.artifact_count,
   'started_at',new.started_at,'completed_at',new.completed_at,'error_code',new.last_error_code,'error_message',new.last_error_message),
  case when new.status in('failed','dead_lettered') then 'notification_engine' when new.status in('completed','completed_with_warnings') then 'observability' else 'analytics' end,
  'backup_job',new.id,case when new.status='dead_lettered' then 1 when new.status='failed' then 10 else 100 end,
  'resilience-backup-job:'||new.id::text||':'||new.status,coalesce(new.correlation_id,new.id::text),new.trace_id,now());
 return new;
end $$;
drop trigger if exists resilience_backup_jobs_emit_events on public.resilience_backup_jobs;
create trigger resilience_backup_jobs_emit_events after insert or update on public.resilience_backup_jobs for each row execute function public.emit_resilience_backup_job_events();

create or replace function public.emit_resilience_restore_job_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if tg_op='UPDATE' and new.status is not distinct from old.status then return new; end if;
 perform public.publish_resilience_event(
  new.organization_id,'resilience.restore_job.'||new.status,
  jsonb_build_object('restore_job_id',new.id,'job_reference',new.job_reference,'restore_request_id',new.restore_request_id,
   'restore_point_id',new.restore_point_id,'status',new.status,'validation_status',new.validation_status,
   'progress_percentage',new.progress_percentage,'restored_bytes',new.restored_bytes,'started_at',new.started_at,
   'completed_at',new.completed_at,'error_code',new.last_error_code,'error_message',new.last_error_message),
  case when new.status in('failed','dead_lettered','rolled_back') then 'notification_engine' when new.status in('completed','completed_with_warnings') then 'reporting' else 'analytics' end,
  'restore_job',new.id,case when new.status in('dead_lettered','rolled_back') then 1 when new.status='failed' then 10 else 100 end,
  'resilience-restore-job:'||new.id::text||':'||new.status,coalesce(new.correlation_id,new.id::text),new.trace_id,now());
 return new;
end $$;
drop trigger if exists resilience_restore_jobs_emit_events on public.resilience_restore_jobs;
create trigger resilience_restore_jobs_emit_events after insert or update on public.resilience_restore_jobs for each row execute function public.emit_resilience_restore_job_events();

create or replace function public.emit_resilience_disaster_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if tg_op='UPDATE' and new.status is not distinct from old.status and new.severity is not distinct from old.severity then return new; end if;
 perform public.publish_resilience_event(
  new.organization_id,'resilience.disaster_event.'||new.status,
  jsonb_build_object('disaster_event_id',new.id,'event_reference',new.event_reference,'event_title',new.event_title,
   'event_type',new.event_type,'severity',new.severity,'status',new.status,'scenario_id',new.scenario_id,
   'affected_environment_ids',new.affected_environment_ids,'affected_service_ids',new.affected_service_ids,
   'affected_process_ids',new.affected_process_ids,'event_commander_id',new.event_commander_id,
   'detected_at',new.detected_at,'declared_at',new.declared_at,'resolved_at',new.resolved_at),
  case when new.status in('declared','plan_activated','recovering') then 'notification_engine' when new.status in('resolved','closed') then 'reporting' else 'enterprise_workflow' end,
  'disaster_event',new.id,case when new.severity='catastrophic' then 1 when new.severity='critical' then 2 when new.severity='high' then 10 else 50 end,
  'resilience-disaster-event:'||new.id::text||':'||new.status,coalesce(new.correlation_id,new.id::text),new.trace_id,now());
 return new;
end $$;
drop trigger if exists resilience_disaster_events_emit_events on public.resilience_disaster_events;
create trigger resilience_disaster_events_emit_events after insert or update on public.resilience_disaster_events for each row execute function public.emit_resilience_disaster_events();

create or replace function public.emit_resilience_recovery_run_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if tg_op='UPDATE' and new.status is not distinct from old.status and new.progress_percentage is not distinct from old.progress_percentage then return new; end if;
 perform public.publish_resilience_event(
  new.organization_id,'resilience.recovery_run.'||new.status,
  jsonb_build_object('recovery_run_id',new.id,'run_reference',new.run_reference,'run_type',new.run_type,
   'status',new.status,'continuity_plan_id',new.continuity_plan_id,'disaster_event_id',new.disaster_event_id,
   'recovery_site_id',new.recovery_site_id,'progress_percentage',new.progress_percentage,
   'current_phase',new.current_phase,'current_step_code',new.current_step_code,
   'target_rpo_minutes',new.target_rpo_minutes,'target_rto_minutes',new.target_rto_minutes,
   'actual_data_loss_minutes',new.actual_data_loss_minutes,'actual_recovery_time_minutes',new.actual_recovery_time_minutes,
   'rpo_met',new.rpo_met,'rto_met',new.rto_met),
  case when new.status in('failed','blocked') then 'notification_engine' when new.status in('completed','completed_with_warnings') then 'reporting' else 'observability' end,
  'recovery_run',new.id,case when new.status='failed' then 1 when new.status='blocked' then 10 else 100 end,
  'resilience-recovery-run:'||new.id::text||':'||new.status,coalesce(new.correlation_id,new.id::text),new.trace_id,now());
 return new;
end $$;
drop trigger if exists resilience_recovery_runs_emit_events on public.resilience_recovery_runs;
create trigger resilience_recovery_runs_emit_events after insert or update on public.resilience_recovery_runs for each row execute function public.emit_resilience_recovery_run_events();

create or replace function public.emit_resilience_replication_events()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if new.status not in('warning','critical','failed') then return new; end if;
 perform public.publish_resilience_event(
  new.organization_id,'resilience.replication.'||new.status,
  jsonb_build_object('replication_snapshot_id',new.id,'replication_configuration_id',new.replication_configuration_id,
   'status',new.status,'lag_seconds',new.lag_seconds,'lag_bytes',new.lag_bytes,
   'last_successful_sync_at',new.last_successful_sync_at,'error_code',new.error_code,
   'error_message',new.error_message,'observed_at',new.observed_at),
  'notification_engine','replication_snapshot',new.id,case when new.status in('critical','failed') then 5 else 25 end,
  'resilience-replication:'||new.replication_configuration_id::text||':'||date_trunc('minute',new.observed_at)::text,
  new.replication_configuration_id::text,null,now());
 return new;
end $$;
drop trigger if exists resilience_replication_snapshots_emit_events on public.resilience_replication_snapshots;
create trigger resilience_replication_snapshots_emit_events after insert on public.resilience_replication_snapshots for each row execute function public.emit_resilience_replication_events();

-- 38. Dashboards
create or replace view public.resilience_backup_dashboard with(security_invoker=true) as
select p.organization_id,p.id backup_policy_id,p.policy_code,p.policy_name,p.backup_type,p.status policy_status,p.rpo_minutes,p.rto_minutes,
 count(distinct j.id) total_jobs,
 count(distinct j.id) filter(where j.status in('completed','completed_with_warnings')) successful_jobs,
 count(distinct j.id) filter(where j.status in('failed','dead_lettered')) failed_jobs,
 round(count(distinct j.id) filter(where j.status in('completed','completed_with_warnings'))::numeric/
  nullif(count(distinct j.id) filter(where j.status in('completed','completed_with_warnings','failed','dead_lettered')),0)*100,2) success_rate,
 max(j.completed_at) filter(where j.status in('completed','completed_with_warnings')) latest_success_at,
 max(j.completed_at) filter(where j.status in('failed','dead_lettered')) latest_failure_at,
 count(distinct rp.id) restore_point_count,
 count(distinct rp.id) filter(where rp.restore_readiness in('ready','ready_with_warnings')) ready_restore_point_count,
 count(distinct rp.id) filter(where rp.next_restore_test_due_at<now()) overdue_restore_test_count
from public.resilience_backup_policies p
left join public.resilience_backup_jobs j on j.backup_policy_id=p.id
left join public.resilience_restore_points rp on rp.backup_policy_id=p.id
group by p.organization_id,p.id,p.policy_code,p.policy_name,p.backup_type,p.status,p.rpo_minutes,p.rto_minutes;

create or replace view public.resilience_restore_dashboard with(security_invoker=true) as
select rr.organization_id,rr.restore_type,rr.target_type,rr.risk_level,rr.status,count(distinct rr.id) request_count,
 count(distinct rr.id) filter(where rr.status='pending_approval') pending_approval_count,
 count(distinct rr.id) filter(where rr.expires_at<=now() and rr.status in('draft','pending_approval','approved')) expired_or_expiring_count,
 count(distinct rj.id) filter(where rj.status in('completed','completed_with_warnings')) successful_job_count,
 count(distinct rj.id) filter(where rj.status in('failed','dead_lettered','rolled_back')) failed_job_count,
 round(avg(rj.duration_seconds),2) average_restore_duration_seconds,max(rj.completed_at) latest_restore_completed_at
from public.resilience_restore_requests rr left join public.resilience_restore_jobs rj on rj.restore_request_id=rr.id
group by rr.organization_id,rr.restore_type,rr.target_type,rr.risk_level,rr.status;

create or replace view public.resilience_replication_dashboard with(security_invoker=true) as
select c.organization_id,c.id replication_configuration_id,c.configuration_code,c.configuration_name,c.replication_type,c.status,
 c.maximum_lag_seconds,x.status latest_snapshot_status,x.lag_seconds,x.lag_bytes,x.last_successful_sync_at,x.observed_at,
 case when x.observed_at is null then 'unknown' when c.maximum_lag_seconds is not null and x.lag_seconds>c.maximum_lag_seconds then 'rpo_at_risk'
  when x.status in('critical','failed') then 'critical' when x.status='warning' then 'warning' else 'healthy' end recovery_readiness
from public.resilience_replication_configurations c
left join lateral(select s.status,s.lag_seconds,s.lag_bytes,s.last_successful_sync_at,s.observed_at
 from public.resilience_replication_snapshots s where s.replication_configuration_id=c.id order by s.observed_at desc limit 1)x on true;

create or replace view public.resilience_recovery_objective_dashboard with(security_invoker=true) as
select o.organization_id,o.id recovery_objective_id,o.objective_code,o.objective_name,o.objective_scope_type,o.criticality,o.rpo_minutes,o.rto_minutes,o.status,
 count(distinct r.id) recovery_run_count,count(distinct r.id) filter(where r.rpo_met=true) rpo_met_count,
 count(distinct r.id) filter(where r.rpo_met=false) rpo_missed_count,
 count(distinct r.id) filter(where r.rto_met=true) rto_met_count,
 count(distinct r.id) filter(where r.rto_met=false) rto_missed_count,
 round(avg(r.actual_data_loss_minutes),2) average_data_loss_minutes,
 round(avg(r.actual_recovery_time_minutes),2) average_recovery_time_minutes,max(r.completed_at) latest_test_or_recovery_at
from public.resilience_recovery_objectives o
left join public.resilience_continuity_plans p on o.id=any(p.recovery_objective_ids)
left join public.resilience_recovery_runs r on r.continuity_plan_id=p.id
group by o.organization_id,o.id,o.objective_code,o.objective_name,o.objective_scope_type,o.criticality,o.rpo_minutes,o.rto_minutes,o.status;

create or replace view public.resilience_continuity_dashboard with(security_invoker=true) as
select p.organization_id,p.plan_type,p.status,count(*) plan_count,
 count(*) filter(where p.review_due_at<current_date and p.status in('approved','active')) overdue_review_count,
 count(*) filter(where p.next_exercise_due_at<now() and p.status in('approved','active')) overdue_exercise_count,
 count(*) filter(where p.plan_document_id is null) missing_document_count,
 count(*) filter(where not exists(select 1 from public.resilience_continuity_plan_steps s where s.continuity_plan_id=p.id and s.status='active')) plans_without_steps_count,
 max(p.last_exercised_at) latest_exercise_at,max(p.updated_at) latest_update_at
from public.resilience_continuity_plans p group by p.organization_id,p.plan_type,p.status;

create or replace view public.resilience_disaster_dashboard with(security_invoker=true) as
select organization_id,event_type,severity,status,count(*) event_count,
 count(*) filter(where status not in('resolved','closed','false_alarm','cancelled','archived')) active_event_count,
 round(avg(extract(epoch from(coalesce(resolved_at,now())-detected_at))/60),2) average_resolution_minutes,
 max(detected_at) latest_detected_at,max(resolved_at) latest_resolved_at
from public.resilience_disaster_events group by organization_id,event_type,severity,status;

create or replace view public.resilience_exercise_dashboard with(security_invoker=true) as
select e.organization_id,e.exercise_type,e.status,e.overall_result,count(distinct e.id) exercise_count,
 round(avg(e.score),2) average_score,count(r.id) filter(where r.result_status='failed') failed_result_count,
 count(r.id) filter(where r.rpo_met=false) rpo_miss_count,count(r.id) filter(where r.rto_met=false) rto_miss_count,
 count(r.id) filter(where r.due_at<now() and r.corrective_action is not null) overdue_corrective_action_count,
 max(e.completed_at) latest_completed_at
from public.resilience_exercises e left join public.resilience_exercise_results r on r.exercise_id=e.id
group by e.organization_id,e.exercise_type,e.status,e.overall_result;

-- 39. Health check
create or replace function public.get_resilience_health(requested_organization_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
 if auth.role()<>'service_role' and(requested_organization_id is null or not public.has_organization_permission(requested_organization_id,'resilience.view_logs')) then raise exception 'Permission denied'; end if;
 return jsonb_build_object(
  'organization_id',requested_organization_id,'checked_at',now(),
  'active_backup_targets',(select count(*) from public.resilience_backup_targets where status='active' and(requested_organization_id is null or organization_id=requested_organization_id)),
  'unhealthy_backup_targets',(select count(*) from public.resilience_backup_targets where status='active' and health_status in('degraded','unhealthy','unreachable') and(requested_organization_id is null or organization_id=requested_organization_id)),
  'active_backup_policies',(select count(*) from public.resilience_backup_policies where status='active' and(requested_organization_id is null or organization_id=requested_organization_id)),
  'backup_failures_24h',(select count(*) from public.resilience_backup_jobs where status in('failed','dead_lettered') and updated_at>=now()-interval '24 hours' and(requested_organization_id is null or organization_id=requested_organization_id)),
  'stale_backup_policies',(select count(*) from public.resilience_backup_policies p where p.status='active' and p.maximum_backup_age_minutes is not null
    and not exists(select 1 from public.resilience_backup_jobs j where j.backup_policy_id=p.id and j.status in('completed','completed_with_warnings') and j.completed_at>=now()-make_interval(mins=>p.maximum_backup_age_minutes))
    and(requested_organization_id is null or p.organization_id=requested_organization_id)),
  'ready_restore_points',(select count(*) from public.resilience_restore_points where restore_readiness in('ready','ready_with_warnings') and(requested_organization_id is null or organization_id=requested_organization_id)),
  'overdue_restore_tests',(select count(*) from public.resilience_restore_points where next_restore_test_due_at<now() and restore_readiness<>'expired' and(requested_organization_id is null or organization_id=requested_organization_id)),
  'pending_restore_approvals',(select count(*) from public.resilience_restore_requests where status='pending_approval' and(requested_organization_id is null or organization_id=requested_organization_id)),
  'active_restore_jobs',(select count(*) from public.resilience_restore_jobs where status in('queued','claimed','preparing','pre_restore_backup','restoring','replaying','validating') and(requested_organization_id is null or organization_id=requested_organization_id)),
  'replication_at_risk',(select count(*) from public.resilience_replication_configurations where status in('degraded','failed') and(requested_organization_id is null or organization_id=requested_organization_id)),
  'recovery_sites_not_ready',(select count(*) from public.resilience_recovery_sites where status='active' and readiness_status in('unknown','partially_ready','not_ready') and(requested_organization_id is null or organization_id=requested_organization_id)),
  'continuity_plan_reviews_overdue',(select count(*) from public.resilience_continuity_plans where status in('approved','active') and review_due_at<current_date and(requested_organization_id is null or organization_id=requested_organization_id)),
  'continuity_exercises_overdue',(select count(*) from public.resilience_continuity_plans where status in('approved','active') and next_exercise_due_at<now() and(requested_organization_id is null or organization_id=requested_organization_id)),
  'active_disaster_events',(select count(*) from public.resilience_disaster_events where status not in('resolved','closed','false_alarm','cancelled','archived') and(requested_organization_id is null or organization_id=requested_organization_id)),
  'active_recovery_runs',(select count(*) from public.resilience_recovery_runs where status in('awaiting_approval','approved','running','paused','blocked','validating') and(requested_organization_id is null or organization_id=requested_organization_id)),
  'pending_failover_approvals',(select count(*) from public.resilience_failover_jobs where status='pending_approval' and(requested_organization_id is null or organization_id=requested_organization_id)),
  'expired_worker_locks',(
   (select count(*) from public.resilience_backup_jobs where status='claimed' and lock_expires_at<=now() and(requested_organization_id is null or organization_id=requested_organization_id))+
   (select count(*) from public.resilience_restore_jobs where status='claimed' and lock_expires_at<=now() and(requested_organization_id is null or organization_id=requested_organization_id))+
   (select count(*) from public.resilience_failover_jobs where status='claimed' and lock_expires_at<=now() and(requested_organization_id is null or organization_id=requested_organization_id))
  ),
  'pending_outbox_events',(select count(*) from public.resilience_event_outbox where status in('pending','failed') and(requested_organization_id is null or organization_id=requested_organization_id))
 );
end $$;

-- 40. RLS
do $$
declare t text;
begin
 foreach t in array array[
  'resilience_backup_targets','resilience_backup_policies','resilience_backup_schedules','resilience_backup_jobs','resilience_backup_artifacts','resilience_backup_verifications','resilience_restore_points','resilience_restore_requests','resilience_restore_jobs','resilience_recovery_sites','resilience_replication_configurations','resilience_replication_snapshots','resilience_recovery_objectives','resilience_business_processes','resilience_bia_assessments','resilience_bia_dependencies','resilience_continuity_plans','resilience_continuity_plan_steps','resilience_disaster_scenarios','resilience_disaster_events','resilience_recovery_runs','resilience_recovery_run_steps','resilience_failover_configurations','resilience_failover_jobs','resilience_exercises','resilience_exercise_results','resilience_event_outbox','resilience_logs'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('drop policy if exists %I_select_policy on public.%I',t,t);
  execute format('create policy %I_select_policy on public.%I for select to authenticated using(public.has_organization_permission(organization_id,''resilience.view'') or public.has_organization_permission(organization_id,''resilience.view_all''))',t,t);
  execute format('drop policy if exists %I_service_policy on public.%I',t,t);
  execute format('create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t);
 end loop;
end $$;

drop policy if exists resilience_restore_requests_requester_select_policy on public.resilience_restore_requests;
create policy resilience_restore_requests_requester_select_policy on public.resilience_restore_requests for select to authenticated
using(requested_by=auth.uid() or public.has_organization_permission(organization_id,'resilience.manage_restores') or public.has_organization_permission(organization_id,'resilience.view_all'));

drop policy if exists resilience_recovery_runs_participant_select_policy on public.resilience_recovery_runs;
create policy resilience_recovery_runs_participant_select_policy on public.resilience_recovery_runs for select to authenticated
using(run_commander_id=auth.uid() or auth.uid()=any(participant_user_ids) or public.has_organization_permission(organization_id,'resilience.execute_recovery') or public.has_organization_permission(organization_id,'resilience.view_all'));

-- Configuration write policies
do $$
declare t text; permission_code text;
begin
 for t,permission_code in
  select * from (values
   ('resilience_backup_targets','resilience.manage_backup_targets'),
   ('resilience_backup_policies','resilience.manage_backup_policies'),
   ('resilience_backup_schedules','resilience.manage_backup_policies'),
   ('resilience_recovery_sites','resilience.manage_replication'),
   ('resilience_replication_configurations','resilience.manage_replication'),
   ('resilience_recovery_objectives','resilience.manage_recovery_objectives'),
   ('resilience_business_processes','resilience.manage_bia'),
   ('resilience_bia_assessments','resilience.manage_bia'),
   ('resilience_bia_dependencies','resilience.manage_bia'),
   ('resilience_continuity_plans','resilience.manage_continuity_plans'),
   ('resilience_continuity_plan_steps','resilience.manage_continuity_plans'),
   ('resilience_disaster_scenarios','resilience.manage_continuity_plans'),
   ('resilience_disaster_events','resilience.manage_disaster_events'),
   ('resilience_recovery_runs','resilience.execute_recovery'),
   ('resilience_recovery_run_steps','resilience.execute_recovery'),
   ('resilience_failover_configurations','resilience.manage_failover'),
   ('resilience_exercises','resilience.manage_exercises'),
   ('resilience_exercise_results','resilience.manage_exercises')
  ) v(table_name,permission_name)
 loop
  execute format('drop policy if exists %I_manage_policy on public.%I',t,t);
  execute format('create policy %I_manage_policy on public.%I for all to authenticated using(public.has_organization_permission(organization_id,%L)) with check(public.has_organization_permission(organization_id,%L))',t,t,permission_code,permission_code);
 end loop;
end $$;

-- 41. Grants
grant select on
 public.resilience_backup_targets,public.resilience_backup_policies,public.resilience_backup_schedules,
 public.resilience_backup_jobs,public.resilience_backup_artifacts,public.resilience_backup_verifications,
 public.resilience_restore_points,public.resilience_restore_requests,public.resilience_restore_jobs,
 public.resilience_recovery_sites,public.resilience_replication_configurations,public.resilience_replication_snapshots,
 public.resilience_recovery_objectives,public.resilience_business_processes,public.resilience_bia_assessments,
 public.resilience_bia_dependencies,public.resilience_continuity_plans,public.resilience_continuity_plan_steps,
 public.resilience_disaster_scenarios,public.resilience_disaster_events,public.resilience_recovery_runs,
 public.resilience_recovery_run_steps,public.resilience_failover_configurations,public.resilience_failover_jobs,
 public.resilience_exercises,public.resilience_exercise_results,public.resilience_event_outbox,public.resilience_logs
 to authenticated;

grant insert,update,delete on
 public.resilience_backup_targets,public.resilience_backup_policies,public.resilience_backup_schedules,
 public.resilience_recovery_sites,public.resilience_replication_configurations,public.resilience_recovery_objectives,
 public.resilience_business_processes,public.resilience_bia_assessments,public.resilience_bia_dependencies,
 public.resilience_continuity_plans,public.resilience_continuity_plan_steps,public.resilience_disaster_scenarios,
 public.resilience_disaster_events,public.resilience_recovery_runs,public.resilience_recovery_run_steps,
 public.resilience_failover_configurations,public.resilience_exercises,public.resilience_exercise_results
 to authenticated;

grant all on
 public.resilience_backup_targets,public.resilience_backup_policies,public.resilience_backup_schedules,
 public.resilience_backup_jobs,public.resilience_backup_artifacts,public.resilience_backup_verifications,
 public.resilience_restore_points,public.resilience_restore_requests,public.resilience_restore_jobs,
 public.resilience_recovery_sites,public.resilience_replication_configurations,public.resilience_replication_snapshots,
 public.resilience_recovery_objectives,public.resilience_business_processes,public.resilience_bia_assessments,
 public.resilience_bia_dependencies,public.resilience_continuity_plans,public.resilience_continuity_plan_steps,
 public.resilience_disaster_scenarios,public.resilience_disaster_events,public.resilience_recovery_runs,
 public.resilience_recovery_run_steps,public.resilience_failover_configurations,public.resilience_failover_jobs,
 public.resilience_exercises,public.resilience_exercise_results,public.resilience_event_outbox,public.resilience_logs
 to service_role;

grant select on
 public.resilience_backup_dashboard,public.resilience_restore_dashboard,public.resilience_replication_dashboard,
 public.resilience_recovery_objective_dashboard,public.resilience_continuity_dashboard,
 public.resilience_disaster_dashboard,public.resilience_exercise_dashboard
 to authenticated,service_role;

-- Dynamic function grants avoid signature drift
do $$
declare r record;
begin
 for r in
  select p.oid::regprocedure signature,p.proname
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
   'register_resilience_backup_target','create_resilience_backup_policy','enqueue_resilience_backup_job',
   'record_resilience_backup_verification','create_resilience_restore_request','respond_resilience_restore_request',
   'enqueue_resilience_restore_job','record_resilience_replication_snapshot','create_resilience_continuity_plan',
   'declare_resilience_disaster_event','start_resilience_recovery_run','approve_resilience_recovery_run',
   'update_resilience_recovery_run_step','create_resilience_failover_job','respond_resilience_failover_job',
   'publish_resilience_event','expire_resilience_records','get_resilience_health'
  )
 loop
  execute format('revoke all on function %s from public',r.signature);
  execute format('grant execute on function %s to authenticated,service_role',r.signature);
 end loop;
 for r in
  select p.oid::regprocedure signature
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
   'claim_resilience_backup_job','start_resilience_backup_job','complete_resilience_backup_job','fail_resilience_backup_job',
   'claim_resilience_restore_job','complete_resilience_restore_job','fail_resilience_restore_job',
   'claim_resilience_failover_job','complete_resilience_failover_job'
  )
 loop
  execute format('revoke all on function %s from public',r.signature);
  execute format('grant execute on function %s to service_role',r.signature);
 end loop;
end $$;

-- 42. Final validation
do $$
declare item text; missing text[]:='{}';
begin
 foreach item in array array[
  'resilience_backup_targets','resilience_backup_policies','resilience_backup_schedules','resilience_backup_jobs',
  'resilience_backup_artifacts','resilience_backup_verifications','resilience_restore_points','resilience_restore_requests',
  'resilience_restore_jobs','resilience_recovery_sites','resilience_replication_configurations','resilience_replication_snapshots',
  'resilience_recovery_objectives','resilience_business_processes','resilience_bia_assessments','resilience_bia_dependencies',
  'resilience_continuity_plans','resilience_continuity_plan_steps','resilience_disaster_scenarios','resilience_disaster_events',
  'resilience_recovery_runs','resilience_recovery_run_steps','resilience_failover_configurations','resilience_failover_jobs',
  'resilience_exercises','resilience_exercise_results','resilience_event_outbox','resilience_logs'
 ] loop
  if not exists(select 1 from information_schema.tables where table_schema='public' and table_name=item) then missing:=array_append(missing,'table:'||item); end if;
 end loop;
 foreach item in array array[
  'register_resilience_backup_target','create_resilience_backup_policy','enqueue_resilience_backup_job',
  'claim_resilience_backup_job','start_resilience_backup_job','complete_resilience_backup_job','fail_resilience_backup_job',
  'record_resilience_backup_verification','create_resilience_restore_request','respond_resilience_restore_request',
  'enqueue_resilience_restore_job','claim_resilience_restore_job','complete_resilience_restore_job','fail_resilience_restore_job',
  'record_resilience_replication_snapshot','create_resilience_continuity_plan','declare_resilience_disaster_event',
  'start_resilience_recovery_run','approve_resilience_recovery_run','update_resilience_recovery_run_step',
  'create_resilience_failover_job','respond_resilience_failover_job','claim_resilience_failover_job',
  'complete_resilience_failover_job','publish_resilience_event','expire_resilience_records','get_resilience_health'
 ] loop
  if not exists(select 1 from information_schema.routines where routine_schema='public' and routine_name=item) then missing:=array_append(missing,'function:'||item); end if;
 end loop;
 if cardinality(missing)>0 then raise exception '031 migration validation failed. Missing: %',array_to_string(missing,', '); end if;
end $$;

-- 43. Migration audit
insert into public.resilience_logs(organization_id,log_level,event_name,message,source_type,log_data)
select o.id,'info','migration.031.completed',
 'Backup, Disaster Recovery and Business Continuity Engine migration 031 completed','migration',
 jsonb_build_object('migration','031_backup_disaster_recovery_business_continuity_engine','completed_at',now(),
  'modules',jsonb_build_array('backup_targets','backup_policies','backup_schedules','backup_jobs','backup_artifacts',
   'backup_verification','restore_points','restore_requests','restore_jobs','recovery_sites','replication',
   'recovery_objectives','business_processes','business_impact_analysis','continuity_plans','disaster_scenarios',
   'disaster_events','recovery_runs','failover','failback','continuity_exercises','analytics','health_monitoring','event_outbox'))
from public.organizations o
where not exists(select 1 from public.resilience_logs l where l.organization_id=o.id and l.event_name='migration.031.completed');

commit;