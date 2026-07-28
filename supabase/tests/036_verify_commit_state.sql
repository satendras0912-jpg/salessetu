-- ============================================================
-- SalesSetu Module 036 Commit-State Verification
-- Read-only. This determines whether V7 actually committed even
-- though Supabase SQL Editor displayed relation "booking" error.
-- ============================================================

with required_relations(name) as (
  values
    ('platform_module_registry'),
    ('platform_module_dependencies'),
    ('platform_component_expectations'),
    ('platform_engine_authority'),
    ('platform_flow_contracts'),
    ('platform_validation_profiles'),
    ('platform_validation_runs'),
    ('platform_validation_results'),
    ('platform_smoke_test_runs'),
    ('platform_smoke_test_results'),
    ('platform_readiness_snapshots'),
    ('platform_integration_issues'),
    ('platform_integration_event_outbox'),
    ('platform_integration_logs')
),
relation_status as (
  select
    r.name,
    to_regclass(format('public.%I', r.name)) as relation_oid
  from required_relations r
),
summary as (
  select
    count(*) as expected_relations,
    count(*) filter (where relation_oid is not null) as existing_relations
  from relation_status
)
select
  'SUMMARY'::text as check_type,
  'module_036_relations'::text as check_name,
  jsonb_build_object(
    'expected', s.expected_relations,
    'existing', s.existing_relations,
    'all_exist', s.existing_relations = s.expected_relations
  ) as result
from summary s

union all

select
  'RELATION'::text,
  rs.name,
  jsonb_build_object(
    'exists', rs.relation_oid is not null,
    'regclass', rs.relation_oid::text
  )
from relation_status rs

union all

select
  'MIGRATION_MARKER'::text,
  'migration.036.completed'::text,
  jsonb_build_object(
    'log_table_exists',
      to_regclass('public.platform_integration_logs') is not null,
    'marker_exists',
      case
        when to_regclass('public.platform_integration_logs') is null then false
        else exists (
          select 1
          from public.platform_integration_logs l
          where l.event_name = 'migration.036.completed'
        )
      end
  )

union all

select
  'MODULE_REGISTRY'::text,
  'module_036_status'::text,
  case
    when to_regclass('public.platform_module_registry') is null then
      jsonb_build_object('registry_exists', false)
    else
      coalesce(
        (
          select jsonb_build_object(
            'registry_exists', true,
            'module_number', m.module_number,
            'module_code', m.module_code,
            'detected_status', m.detected_status,
            'marker_verified', m.marker_verified,
            'required_component_count', m.required_component_count,
            'detected_component_count', m.detected_component_count,
            'last_validated_at', m.last_validated_at
          )
          from public.platform_module_registry m
          where m.module_number = 36
          limit 1
        ),
        jsonb_build_object(
          'registry_exists', true,
          'module_036_row_exists', false
        )
      )
  end

union all

select
  'BOOKING_RELATIONS'::text,
  'booking_vs_bookings'::text,
  jsonb_build_object(
    'legacy_booking', to_regclass('public.booking')::text,
    'authoritative_bookings', to_regclass('public.bookings')::text
  )

union all

select
  'SESSION'::text,
  'replication_role'::text,
  jsonb_build_object(
    'session_replication_role', current_setting('session_replication_role')
  )

order by check_type, check_name;
