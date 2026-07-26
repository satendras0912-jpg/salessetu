-- ============================================================
-- SalesSetu Module 036
-- Check whether the latest production validation completed after
-- the Supabase SQL Editor displayed "Failed to fetch".
--
-- Read-only: this script does not modify data.
-- ============================================================

with latest_run as (
  select
    r.*
  from public.platform_validation_runs r
  order by r.created_at desc
  limit 1
)
select
  'LATEST_RUN'::text as section,
  jsonb_build_object(
    'id', r.id,
    'run_code', r.run_code,
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
  ) as result
from latest_run r

union all

select
  'RESULT_COUNTS'::text,
  jsonb_build_object(
    'stored_results', count(*),
    'passed', count(*) filter (where v.passed),
    'failed', count(*) filter (where not v.passed),
    'critical_failed',
      count(*) filter (where not v.passed and v.severity = 'critical'),
    'high_failed',
      count(*) filter (where not v.passed and v.severity = 'high')
  )
from public.platform_validation_results v
join latest_run r
  on r.id = v.validation_run_id

union all

select
  'TOP_FAILURES'::text,
  coalesce(
    jsonb_agg(
      jsonb_build_object(
        'check_code', failure.check_code,
        'category', failure.category,
        'severity', failure.severity,
        'component_name', failure.component_name,
        'module_number', failure.module_number,
        'message', failure.message,
        'remediation', failure.remediation
      )
      order by
        case failure.severity
          when 'critical' then 1
          when 'high' then 2
          when 'medium' then 3
          when 'low' then 4
          else 5
        end,
        failure.check_code
    ),
    '[]'::jsonb
  )
from (
  select v.*
  from public.platform_validation_results v
  join latest_run r
    on r.id = v.validation_run_id
  where not v.passed
  order by
    case v.severity
      when 'critical' then 1
      when 'high' then 2
      when 'medium' then 3
      when 'low' then 4
      else 5
    end,
    v.check_code
  limit 20
) failure

union all

select
  'CURRENT_DATABASE_SESSION'::text,
  jsonb_build_object(
    'database_time', now(),
    'replication_role', current_setting('session_replication_role'),
    'database', current_database(),
    'user', current_user
  );
