-- ============================================================================
-- SalesSetu Enterprise
-- Migration: 038_Site_Visit_History_Trigger_Fix
--
-- Purpose:
--   Correct the site_visits_record_history trigger timing.
--
-- Problem:
--   The trigger previously ran BEFORE INSERT OR UPDATE and attempted to insert
--   a site_visit_status_history row before the parent site_visits row existed.
--   Because site_visit_status_history.site_visit_id has an immediate foreign
--   key to site_visits.id, new site-visit creation failed.
--
-- Resolution:
--   Preserve the existing trigger events, UPDATE OF column list and function,
--   while changing only the timing from BEFORE to AFTER.
--
-- Safety:
--   - Idempotent when the trigger is already AFTER.
--   - Fails explicitly if the expected trigger or function is missing.
--   - Locks site_visits against concurrent writes while replacing the trigger.
--   - Verifies the final trigger state before committing.
-- ============================================================================

begin;

set local search_path = public, pg_temp;

lock table public.site_visits
  in share row exclusive mode;

do $migration$
declare
  current_trigger_definition text;
  corrected_trigger_definition text;
  current_trigger_timing text;
  trigger_function_schema text;
  trigger_function_name text;
begin
  select
    pg_get_triggerdef(trigger_row.oid, true),

    case
      when (trigger_row.tgtype & 2) = 2
        then 'BEFORE'
      when (trigger_row.tgtype & 64) = 64
        then 'INSTEAD OF'
      else 'AFTER'
    end,

    function_schema.nspname,
    function_row.proname

  into
    current_trigger_definition,
    current_trigger_timing,
    trigger_function_schema,
    trigger_function_name

  from pg_trigger trigger_row

  join pg_class table_row
    on table_row.oid = trigger_row.tgrelid

  join pg_namespace table_schema
    on table_schema.oid = table_row.relnamespace

  join pg_proc function_row
    on function_row.oid = trigger_row.tgfoid

  join pg_namespace function_schema
    on function_schema.oid =
      function_row.pronamespace

  where table_schema.nspname = 'public'
    and table_row.relname = 'site_visits'
    and trigger_row.tgname =
      'site_visits_record_history'
    and trigger_row.tgisinternal = false;

  if not found then
    raise exception
      'Expected trigger public.site_visits_record_history was not found.';
  end if;

  if trigger_function_schema <> 'public'
    or trigger_function_name <>
      'record_site_visit_history'
  then
    raise exception
      'Unexpected trigger function %.%. Expected public.record_site_visit_history.',
      trigger_function_schema,
      trigger_function_name;
  end if;

  if current_trigger_timing = 'AFTER' then
    raise notice
      'Trigger site_visits_record_history is already AFTER. No change required.';

    return;
  end if;

  if current_trigger_timing <> 'BEFORE' then
    raise exception
      'Unexpected timing for site_visits_record_history: %.',
      current_trigger_timing;
  end if;

  corrected_trigger_definition :=
    replace(
      current_trigger_definition,
      ' BEFORE ',
      ' AFTER '
    );

  if corrected_trigger_definition =
    current_trigger_definition
  then
    raise exception
      'Unable to convert site_visits_record_history from BEFORE to AFTER.';
  end if;

  execute
    'drop trigger site_visits_record_history
     on public.site_visits';

  execute corrected_trigger_definition;

  raise notice
    'Trigger site_visits_record_history changed from BEFORE to AFTER.';
end;
$migration$;

-- Final migration assertion.
do $verification$
declare
  final_trigger_timing text;
  includes_insert_event boolean;
begin
  select
    case
      when (trigger_row.tgtype & 2) = 2
        then 'BEFORE'
      when (trigger_row.tgtype & 64) = 64
        then 'INSTEAD OF'
      else 'AFTER'
    end,

    (trigger_row.tgtype & 4) = 4

  into
    final_trigger_timing,
    includes_insert_event

  from pg_trigger trigger_row

  join pg_class table_row
    on table_row.oid = trigger_row.tgrelid

  join pg_namespace table_schema
    on table_schema.oid = table_row.relnamespace

  where table_schema.nspname = 'public'
    and table_row.relname = 'site_visits'
    and trigger_row.tgname =
      'site_visits_record_history'
    and trigger_row.tgisinternal = false;

  if not found then
    raise exception
      'Post-migration verification failed: trigger was not found.';
  end if;

  if final_trigger_timing <> 'AFTER' then
    raise exception
      'Post-migration verification failed: expected AFTER, found %.',
      final_trigger_timing;
  end if;

  if not includes_insert_event then
    raise exception
      'Post-migration verification failed: INSERT event is missing.';
  end if;

  raise notice
    'Verified site_visits_record_history as AFTER INSERT/UPDATE.';
end;
$verification$;

commit;