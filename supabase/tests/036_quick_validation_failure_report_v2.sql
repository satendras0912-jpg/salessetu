-- ============================================================
-- SalesSetu Module 036
-- Quick Validation Failure Report v2
--
-- Returns one readable result set containing:
--   • latest run summary
--   • failure counts by severity/category
--   • top 50 actionable failures
--
-- Read-only: this script does not modify data.
--
-- v2 fix:
-- PostgreSQL format() does not support printf-style numeric precision.
-- Readiness is formatted with to_char() and then inserted through %s.
-- ============================================================

with latest_run as (
  select r.*
  from public.platform_validation_runs r
  where r.run_type = 'manual'
  order by r.created_at desc
  limit 1
),
failure_groups as (
  select
    v.severity,
    v.category,
    count(*)::integer as failure_count
  from public.platform_validation_results v
  join latest_run r
    on r.id = v.validation_run_id
  where not v.passed
  group by v.severity, v.category
),
top_failures as (
  select
    v.severity,
    v.category,
    v.module_number,
    v.check_code,
    v.component_type,
    v.component_name,
    v.message,
    v.remediation,
    v.details,
    row_number() over (
      order by
        case v.severity
          when 'critical' then 1
          when 'high' then 2
          when 'medium' then 3
          when 'low' then 4
          else 5
        end,
        v.module_number nulls last,
        v.category,
        v.check_code
    ) as priority_rank
  from public.platform_validation_results v
  join latest_run r
    on r.id = v.validation_run_id
  where not v.passed
),
report as (
  select
    0::integer as sort_group,
    0::bigint as sort_rank,
    'RUN_SUMMARY'::text as row_type,
    r.status::text as severity,
    null::text as category,
    null::integer as module_number,
    r.run_code::text as check_code,
    null::text as component_type,
    null::text as component_name,
    r.failed_checks::integer as failure_count,
    format(
      'Readiness %s%% | %s passed | %s failed | %s total',
      to_char(coalesce(r.readiness_score, 0), 'FM999990.000'),
      r.passed_checks,
      r.failed_checks,
      r.total_checks
    )::text as message,
    case
      when r.critical_failures > 0 then
        'Resolve critical failures before production use.'
      when r.high_failures > 0 then
        'Resolve high-severity failures before production use.'
      when r.failed_checks > 0 then
        'Review grouped and detailed failures below.'
      else
        'No remediation required.'
    end::text as remediation,
    jsonb_build_object(
      'run_id', r.id,
      'profile_id', r.profile_id,
      'status', r.status,
      'total_checks', r.total_checks,
      'passed_checks', r.passed_checks,
      'failed_checks', r.failed_checks,
      'critical_failures', r.critical_failures,
      'high_failures', r.high_failures,
      'readiness_score', r.readiness_score,
      'started_at', r.started_at,
      'completed_at', r.completed_at,
      'summary', r.summary
    ) as details
  from latest_run r

  union all

  select
    1::integer,
    case g.severity
      when 'critical' then 1
      when 'high' then 2
      when 'medium' then 3
      when 'low' then 4
      else 5
    end::bigint,
    'FAILURE_GROUP'::text,
    g.severity::text,
    g.category::text,
    null::integer,
    null::text,
    null::text,
    null::text,
    g.failure_count,
    format(
      '%s failure(s) in %s',
      g.failure_count,
      g.category
    )::text,
    'Inspect matching FAILURE_DETAIL rows.'::text,
    '{}'::jsonb
  from failure_groups g

  union all

  select
    2::integer,
    f.priority_rank::bigint,
    'FAILURE_DETAIL'::text,
    f.severity::text,
    f.category::text,
    f.module_number,
    f.check_code::text,
    f.component_type::text,
    f.component_name::text,
    1::integer,
    f.message::text,
    coalesce(
      nullif(f.remediation, ''),
      'Manual review required.'
    )::text,
    f.details
  from top_failures f
  where f.priority_rank <= 50
)
select
  row_type,
  severity,
  category,
  module_number,
  check_code,
  component_type,
  component_name,
  failure_count,
  message,
  remediation,
  details
from report
order by sort_group, sort_rank, category, check_code;
