-- ============================================================
-- 042_Follow_Up_Concurrency_Error_Code_Fix.sql
--
-- Purpose:
--   Fix optimistic-concurrency error handling for follow-up
--   assignment and completion RPCs.
--
-- Problem:
--   SQLSTATE 40001 means serialization_failure in PostgreSQL.
--   It must not be used for a normal stale-form conflict.
--
-- Fix:
--   Replace legacy 40001 with P0001.
--
-- Safe to run when:
--   - 40001 is still present, or
--   - P0001 has already been manually applied.
-- ============================================================

do $migration$
declare
  target_function regprocedure;
  function_definition text;
  patched_definition text;
  legacy_code_count integer;
  patched_guard_count integer;
begin
  foreach target_function in array array[
    'public.assign_follow_up_task(uuid,uuid,text,timestamptz)'::regprocedure,
    'public.complete_follow_up_task(uuid,text,text,timestamptz)'::regprocedure
  ]
  loop
    function_definition :=
      pg_get_functiondef(target_function);

    if position(
      'Follow-up task changed after the form was opened'
      in function_definition
    ) = 0 then
      raise exception
        'Expected follow-up concurrency guard was not found in %.',
        target_function;
    end if;

    select count(*)
    into legacy_code_count
    from regexp_matches(
      function_definition,
      'using[[:space:]]+errcode[[:space:]]*=[[:space:]]*''40001''[[:space:]]*;',
      'gi'
    );

    if legacy_code_count > 1 then
      raise exception
        'More than one ERRCODE 40001 clause was found in %. Refusing automatic rewrite.',
        target_function;
    end if;

    select count(*)
    into patched_guard_count
    from regexp_matches(
      function_definition,
      '''Follow-up task changed after the form was opened''[[:space:]]+using[[:space:]]+errcode[[:space:]]*=[[:space:]]*''P0001''[[:space:]]*;',
      'gi'
    );

    if legacy_code_count = 1 then
      patched_definition :=
        regexp_replace(
          function_definition,
          'using[[:space:]]+errcode[[:space:]]*=[[:space:]]*''40001''[[:space:]]*;',
          'using errcode = ''P0001'';',
          'i'
        );

      execute patched_definition;

    elsif patched_guard_count = 1 then
      null;

    else
      raise exception
        'Neither legacy 40001 nor patched P0001 concurrency guard was found in %.',
        target_function;
    end if;
  end loop;
end
$migration$;


-- ============================================================
-- Verification
-- ============================================================

do $verification$
declare
  target_function regprocedure;
  function_definition text;
  legacy_code_count integer;
  patched_guard_count integer;
begin
  foreach target_function in array array[
    'public.assign_follow_up_task(uuid,uuid,text,timestamptz)'::regprocedure,
    'public.complete_follow_up_task(uuid,text,text,timestamptz)'::regprocedure
  ]
  loop
    function_definition :=
      pg_get_functiondef(target_function);

    select count(*)
    into legacy_code_count
    from regexp_matches(
      function_definition,
      'using[[:space:]]+errcode[[:space:]]*=[[:space:]]*''40001''[[:space:]]*;',
      'gi'
    );

    if legacy_code_count <> 0 then
      raise exception
        'Migration verification failed: ERRCODE 40001 remains in %.',
        target_function;
    end if;

    select count(*)
    into patched_guard_count
    from regexp_matches(
      function_definition,
      '''Follow-up task changed after the form was opened''[[:space:]]+using[[:space:]]+errcode[[:space:]]*=[[:space:]]*''P0001''[[:space:]]*;',
      'gi'
    );

    if patched_guard_count <> 1 then
      raise exception
        'Migration verification failed: expected one P0001 concurrency guard in %, found %.',
        target_function,
        patched_guard_count;
    end if;
  end loop;
end
$verification$;