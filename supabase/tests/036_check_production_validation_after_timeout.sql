-- ============================================================
-- SalesSetu Module 036
-- Production Validation Status After SQL Editor Upstream Timeout
--
-- Read-only. Determines whether the production validation:
--   • is still running in PostgreSQL,
--   • completed and committed,
--   • failed/rolled back before creating a visible run record.
-- ============================================================

with active_validation_sessions as (
  select
    a.pid,
    a.state,
    a.query_start,
    clock_timestamp() - a.query_start as elapsed,
    a.wait_event_type,
    a.wait_event,
    left(regexp_replace(a.query, E'[\\n\\r\\t]+', ' ', 'g'), 500) as query_text
  from pg_stat_activity a
  where a.datname = current_database()
    and a.pid <> pg_backend_pid()
    and a.state <> 'idle'
    and a.query ilike '%run_platform_validation%'
),
latest_production_run as (
  select
    r.id,
    r.run_code,
    p.profile_code,
    r.run_type,
    r.status,
    r.requested_at,
    r.started_at,
    r.completed_at,
    r.total_checks,
    r.passed_checks,
    r.failed_checks,
    r.critical_failures,
    r.high_failures,
    r.readiness_score,
    r.error_message,
    r.summary
  from public.platform_validation_runs r
  join public.platform_validation_profiles p
    on p.id = r.profile_id
  where p.profile_code = 'production'
  order by r.requested_at desc
  limit 1
),
latest_result_counts as (
  select
    count(*)::integer as stored_results,
    count(*) filter (where v.passed)::integer as passed_results,
    count(*) filter (where not v.passed)::integer as failed_results
  from public.platform_validation_results v
  join latest_production_run r
    on r.id = v.validation_run_id
)
select
  'ACTIVE_DATABASE_EXECUTION'::text as section,
  case
    when exists (select 1 from active_validation_sessions)
      then jsonb_build_object(
        'is_running', true,
        'sessions',
        (
          select jsonb_agg(
            jsonb_build_object(
              'pid', s.pid,
              'state', s.state,
              'query_start', s.query_start,
              'elapsed', s.elapsed::text,
              'wait_event_type', s.wait_event_type,
              'wait_event', s.wait_event,
              'query', s.query_text
            )
            order by s.query_start
          )
          from active_validation_sessions s
        )
      )
    else jsonb_build_object('is_running', false)
  end as result

union all

select
  'LATEST_COMMITTED_PRODUCTION_RUN'::text,
  case
    when exists (select 1 from latest_production_run) then
      (
        select jsonb_build_object(
          'run_id', r.id,
          'run_code', r.run_code,
          'profile_code', r.profile_code,
          'run_type', r.run_type,
          'status', r.status,
          'requested_at', r.requested_at,
          'started_at', r.started_at,
          'completed_at', r.completed_at,
          'total_checks', r.total_checks,
          'passed_checks', r.passed_checks,
          'failed_checks', r.failed_checks,
          'critical_failures', r.critical_failures,
          'high_failures', r.high_failures,
          'readiness_score', r.readiness_score,
          'error_message', r.error_message,
          'summary', r.summary
        )
        from latest_production_run r
      )
    else jsonb_build_object('run_exists', false)
  end

union all

select
  'LATEST_COMMITTED_RESULT_COUNTS'::text,
  case
    when exists (select 1 from latest_production_run) then
      (
        select jsonb_build_object(
          'stored_results', c.stored_results,
          'passed_results', c.passed_results,
          'failed_results', c.failed_results
        )
        from latest_result_counts c
      )
    else jsonb_build_object(
      'stored_results', 0,
      'note', 'No committed production validation run is visible.'
    )
  end

union all

select
  'INTERPRETATION'::text,
  jsonb_build_object(
    'database_time', clock_timestamp(),
    'guidance',
    case
      when exists (select 1 from active_validation_sessions)
        then 'Production validation is still executing. Do not run it again.'
      when exists (
        select 1
        from latest_production_run
        where status in ('completed','degraded','blocked','failed','cancelled')
      )
        then 'A committed production validation result exists. Use that run; do not rerun yet.'
      else
        'No active execution and no committed production run were found. The timed-out request likely did not complete; use a direct database connection or a batched validation path.'
    end
  );
