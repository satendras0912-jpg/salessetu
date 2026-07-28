-- ============================================================
-- SalesSetu Module 036
-- Batched Foreign-Key Orphan Integrity Audit
--
-- Scope:
--   Audits every single-column foreign-key constraint in public schema,
--   matching the deep referential-integrity scope of
--   public.run_platform_validation(..., 'production', ...).
--
-- Why batched:
--   The monolithic production profile exceeded the Supabase SQL Editor
--   upstream timeout. This audit persists progress and processes a limited
--   number of constraints per call.
--
-- Execution:
--   1. Run this complete file once. It installs the profile and batch worker,
--      starts a new audit, and processes the first 50 constraints.
--   2. Re-run only:
--
--        select * from public.run_fk_integrity_audit_batch(50);
--
--      until remaining_constraints = 0.
--   3. Then run the final report query shown at the bottom.
--
-- Safety:
--   • Read-only against business tables.
--   • Writes only audit rows to platform_validation_* tables and logs.
--   • Existing validation runs/results are preserved.
--   • Each batch is committed independently by the SQL Editor.
-- ============================================================

begin;

insert into public.platform_validation_profiles (
  profile_code,
  profile_name,
  description,
  configuration,
  status
)
values (
  'production_fk_integrity_batched',
  'Production FK Integrity — Batched',
  'Batched orphan-row audit for all public single-column foreign-key constraints.',
  jsonb_build_object(
    'check_fk_indexes', false,
    'check_fk_integrity', true,
    'check_queue_locks', false,
    'auto_create_issues', false,
    'execution_mode', 'batched'
  ),
  'active'
)
on conflict (profile_code)
do update
set
  profile_name = excluded.profile_name,
  description = excluded.description,
  configuration = excluded.configuration,
  status = 'active',
  updated_at = now();

create or replace function public.start_fk_integrity_audit()
returns public.platform_validation_runs
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_profile public.platform_validation_profiles;
  v_run public.platform_validation_runs;
  v_total_constraints integer;
begin
  select *
  into v_profile
  from public.platform_validation_profiles
  where profile_code = 'production_fk_integrity_batched'
    and status = 'active';

  if not found then
    raise exception
      'Active validation profile production_fk_integrity_batched not found';
  end if;

  -- Reuse an unfinished audit rather than creating overlapping runs.
  select *
  into v_run
  from public.platform_validation_runs
  where profile_id = v_profile.id
    and status in ('queued', 'running')
  order by requested_at desc
  limit 1;

  if found then
    return v_run;
  end if;

  select count(*)
  into v_total_constraints
  from pg_catalog.pg_constraint con
  join pg_catalog.pg_class child_table
    on child_table.oid = con.conrelid
  join pg_catalog.pg_namespace child_schema
    on child_schema.oid = child_table.relnamespace
  where con.contype = 'f'
    and pg_catalog.cardinality(con.conkey) = 1
    and child_schema.nspname = 'public'
    and child_table.relkind in ('r', 'p');

  insert into public.platform_validation_runs (
    organization_id,
    profile_id,
    run_code,
    run_type,
    status,
    requested_by,
    requested_at,
    started_at,
    total_checks,
    passed_checks,
    failed_checks,
    critical_failures,
    high_failures,
    readiness_score,
    configuration_snapshot,
    summary,
    correlation_id
  )
  values (
    null,
    v_profile.id,
    'FK-AUDIT-' ||
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 18)),
    'manual',
    'running',
    auth.uid(),
    now(),
    now(),
    0,
    0,
    0,
    0,
    0,
    0,
    v_profile.configuration,
    jsonb_build_object(
      'audit_scope', 'public_single_column_foreign_keys',
      'expected_constraints', v_total_constraints,
      'processed_constraints', 0,
      'remaining_constraints', v_total_constraints
    ),
    gen_random_uuid()::text
  )
  returning *
  into v_run;

  return v_run;
end;
$function$;

create or replace function public.run_fk_integrity_audit_batch(
  p_batch_size integer default 50
)
returns table (
  validation_run_id uuid,
  run_code text,
  batch_processed integer,
  batch_passed integer,
  batch_failed integer,
  total_processed integer,
  total_passed integer,
  total_failed integer,
  remaining_constraints integer,
  status text,
  readiness_score numeric,
  started_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_run public.platform_validation_runs;
  v_fk record;
  v_batch_size integer;
  v_orphan_exists boolean;
  v_batch_processed integer := 0;
  v_batch_passed integer := 0;
  v_batch_failed integer := 0;
  v_total_constraints integer := 0;
  v_total_processed integer := 0;
  v_total_passed integer := 0;
  v_total_failed integer := 0;
  v_remaining integer := 0;
  v_status text;
  v_readiness numeric(7,3);
  v_completed_at timestamptz;
begin
  v_batch_size := greatest(1, least(coalesce(p_batch_size, 50), 200));

  perform pg_catalog.set_config('statement_timeout', '0', true);
  perform pg_catalog.set_config('lock_timeout', '10s', true);

  v_run := public.start_fk_integrity_audit();

  for v_fk in
    select
      con.oid as constraint_oid,
      con.conname as constraint_name,
      con.convalidated,
      child_schema.nspname as child_schema,
      child_table.relname as child_table,
      child_column.attname as child_column,
      parent_schema.nspname as parent_schema,
      parent_table.relname as parent_table,
      parent_column.attname as parent_column
    from pg_catalog.pg_constraint con
    join pg_catalog.pg_class child_table
      on child_table.oid = con.conrelid
    join pg_catalog.pg_namespace child_schema
      on child_schema.oid = child_table.relnamespace
    join pg_catalog.pg_class parent_table
      on parent_table.oid = con.confrelid
    join pg_catalog.pg_namespace parent_schema
      on parent_schema.oid = parent_table.relnamespace
    join pg_catalog.pg_attribute child_column
      on child_column.attrelid = child_table.oid
     and child_column.attnum = con.conkey[1]
    join pg_catalog.pg_attribute parent_column
      on parent_column.attrelid = parent_table.oid
     and parent_column.attnum = con.confkey[1]
    where con.contype = 'f'
      and pg_catalog.cardinality(con.conkey) = 1
      and child_schema.nspname = 'public'
      and child_table.relkind in ('r', 'p')
      and not exists (
        select 1
        from public.platform_validation_results existing_result
        where existing_result.validation_run_id = v_run.id
          and existing_result.category = 'referential_integrity'
          and existing_result.details ->> 'constraint_oid' =
              con.oid::text
      )
    order by
      child_schema.nspname,
      child_table.relname,
      con.conname,
      con.oid
    limit v_batch_size
  loop
    execute pg_catalog.format(
      'select exists(
         select 1
         from %I.%I child_row
         where child_row.%I is not null
           and not exists(
             select 1
             from %I.%I parent_row
             where parent_row.%I = child_row.%I
           )
         limit 1
       )',
      v_fk.child_schema,
      v_fk.child_table,
      v_fk.child_column,
      v_fk.parent_schema,
      v_fk.parent_table,
      v_fk.parent_column,
      v_fk.child_column
    )
    into v_orphan_exists;

    insert into public.platform_validation_results (
      validation_run_id,
      organization_id,
      check_code,
      category,
      component_type,
      component_name,
      module_number,
      passed,
      severity,
      score_weight,
      score_awarded,
      message,
      remediation,
      details
    )
    values (
      v_run.id,
      null,
      'FK_INTEGRITY_' ||
        upper(
          regexp_replace(
            v_fk.child_schema || '_' ||
            v_fk.child_table || '_' ||
            v_fk.constraint_name || '_' ||
            v_fk.constraint_oid::text,
            '[^A-Za-z0-9]+',
            '_',
            'g'
          )
        ),
      'referential_integrity',
      'constraint',
      v_fk.child_schema || '.' ||
        v_fk.child_table || '.' ||
        v_fk.constraint_name,
      null,
      not v_orphan_exists,
      'critical',
      2,
      case when v_orphan_exists then 0 else 2 end,
      case
        when v_orphan_exists then
          format(
            'Orphaned rows detected for foreign key %I on %I.%I(%I)',
            v_fk.constraint_name,
            v_fk.child_schema,
            v_fk.child_table,
            v_fk.child_column
          )
        else
          format(
            'No orphaned rows detected for foreign key %I on %I.%I(%I)',
            v_fk.constraint_name,
            v_fk.child_schema,
            v_fk.child_table,
            v_fk.child_column
          )
      end,
      'Repair orphaned child rows before production deployment; preserve foreign-key enforcement.',
      jsonb_build_object(
        'constraint_oid', v_fk.constraint_oid,
        'constraint_name', v_fk.constraint_name,
        'constraint_validated', v_fk.convalidated,
        'child_schema', v_fk.child_schema,
        'child_table', v_fk.child_table,
        'child_column', v_fk.child_column,
        'parent_schema', v_fk.parent_schema,
        'parent_table', v_fk.parent_table,
        'parent_column', v_fk.parent_column,
        'orphan_exists', v_orphan_exists,
        'audited_at', clock_timestamp()
      )
    );

    v_batch_processed := v_batch_processed + 1;

    if v_orphan_exists then
      v_batch_failed := v_batch_failed + 1;
    else
      v_batch_passed := v_batch_passed + 1;
    end if;
  end loop;

  select count(*)
  into v_total_constraints
  from pg_catalog.pg_constraint con
  join pg_catalog.pg_class child_table
    on child_table.oid = con.conrelid
  join pg_catalog.pg_namespace child_schema
    on child_schema.oid = child_table.relnamespace
  where con.contype = 'f'
    and pg_catalog.cardinality(con.conkey) = 1
    and child_schema.nspname = 'public'
    and child_table.relkind in ('r', 'p');

  select
    count(*),
    count(*) filter (where result_row.passed),
    count(*) filter (where not result_row.passed)
  into
    v_total_processed,
    v_total_passed,
    v_total_failed
  from public.platform_validation_results result_row
  where result_row.validation_run_id = v_run.id
    and result_row.category = 'referential_integrity';

  v_remaining := greatest(v_total_constraints - v_total_processed, 0);

  v_readiness :=
    case
      when v_total_processed = 0 then 0
      else round(
        (v_total_passed::numeric / v_total_processed::numeric) * 100,
        3
      )
    end;

  if v_remaining = 0 then
    v_status := case
      when v_total_failed > 0 then 'blocked'
      else 'completed'
    end;
    v_completed_at := now();
  else
    v_status := 'running';
    v_completed_at := null;
  end if;

  update public.platform_validation_runs
  set
    status = v_status,
    completed_at = v_completed_at,
    total_checks = v_total_processed,
    passed_checks = v_total_passed,
    failed_checks = v_total_failed,
    critical_failures = v_total_failed,
    high_failures = 0,
    readiness_score = v_readiness,
    summary = jsonb_build_object(
      'audit_scope', 'public_single_column_foreign_keys',
      'expected_constraints', v_total_constraints,
      'processed_constraints', v_total_processed,
      'remaining_constraints', v_remaining,
      'passed_constraints', v_total_passed,
      'failed_constraints', v_total_failed,
      'integrity_score', v_readiness,
      'latest_batch_processed', v_batch_processed,
      'latest_batch_passed', v_batch_passed,
      'latest_batch_failed', v_batch_failed
    ),
    updated_at = now()
  where id = v_run.id
  returning *
  into v_run;

  if to_regclass('public.platform_integration_logs') is not null then
    insert into public.platform_integration_logs (
      organization_id,
      log_level,
      event_name,
      message,
      source_type,
      source_id,
      log_data,
      correlation_id
    )
    values (
      null,
      case
        when v_total_failed > 0 then 'critical'
        when v_remaining = 0 then 'info'
        else 'info'
      end,
      case
        when v_remaining = 0 then
          'platform.fk_integrity.audit_completed'
        else
          'platform.fk_integrity.batch_completed'
      end,
      format(
        'FK integrity audit processed %s constraint(s); %s remain; %s failures found',
        v_batch_processed,
        v_remaining,
        v_total_failed
      ),
      'platform_validation_run',
      v_run.id,
      v_run.summary,
      v_run.correlation_id
    );
  end if;

  return query
  select
    v_run.id,
    v_run.run_code,
    v_batch_processed,
    v_batch_passed,
    v_batch_failed,
    v_total_processed,
    v_total_passed,
    v_total_failed,
    v_remaining,
    v_status,
    v_readiness,
    v_run.started_at,
    v_completed_at;
end;
$function$;

comment on function public.start_fk_integrity_audit() is
  'Starts or resumes the current batched public single-column FK orphan audit.';

comment on function public.run_fk_integrity_audit_batch(integer) is
  'Processes the next batch of public single-column FK orphan checks and persists progress.';

grant execute
on function public.start_fk_integrity_audit()
to service_role;

grant execute
on function public.run_fk_integrity_audit_batch(integer)
to service_role;

commit;

-- ============================================================
-- PROCESS FIRST BATCH
-- Re-run only this SELECT until remaining_constraints = 0.
-- ============================================================

select *
from public.run_fk_integrity_audit_batch(50);

-- ============================================================
-- FINAL REPORT
-- Run after remaining_constraints reaches 0.
-- ============================================================
--
-- select
--   r.run_code,
--   r.status,
--   r.total_checks,
--   r.passed_checks,
--   r.failed_checks,
--   r.critical_failures,
--   r.readiness_score,
--   r.started_at,
--   r.completed_at,
--   r.summary
-- from public.platform_validation_runs r
-- join public.platform_validation_profiles p
--   on p.id = r.profile_id
-- where p.profile_code = 'production_fk_integrity_batched'
-- order by r.requested_at desc
-- limit 1;
--
-- select
--   result_row.component_name,
--   result_row.message,
--   result_row.remediation,
--   result_row.details
-- from public.platform_validation_results result_row
-- join public.platform_validation_runs run_row
--   on run_row.id = result_row.validation_run_id
-- join public.platform_validation_profiles profile_row
--   on profile_row.id = run_row.profile_id
-- where profile_row.profile_code = 'production_fk_integrity_batched'
--   and result_row.passed = false
-- order by result_row.component_name;
