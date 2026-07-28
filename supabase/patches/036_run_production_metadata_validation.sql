-- ============================================================
-- SalesSetu Module 036
-- Production Metadata Validation Profile
--
-- Purpose:
--   Run every normal production-readiness check, including foreign-key
--   index coverage, but defer expensive row-by-row orphan scans to a
--   separate batched integrity audit.
--
-- Why:
--   The monolithic "production" profile exceeded the Supabase SQL Editor
--   upstream timeout and left no active or committed production run.
--
-- This script:
--   1. Creates/updates the active profile "production_metadata".
--   2. Runs the validation once.
--   3. Returns the persisted validation-run record.
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
  'production_metadata',
  'Production Metadata Validation',
  'Full production metadata, security, dependency, queue and FK-index audit without expensive referential-integrity row scans.',
  jsonb_build_object(
    'check_fk_indexes', true,
    'check_fk_integrity', false,
    'check_queue_locks', true,
    'auto_create_issues', false
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

commit;

select
  (
    public.run_platform_validation(
      null,
      'production_metadata',
      'manual'
    )
  ).*;
