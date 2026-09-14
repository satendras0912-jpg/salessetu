-- 053_Follow_Up_Completion_Control.sql
--
-- Purpose:
--   Harden follow-up completion with:
--   - server-side input validation
--   - organization permission validation
--   - row locking
--   - optimistic concurrency protection
--   - terminal-state validation
--   - idempotent completion behavior
--   - completion audit metadata
--   - restricted function execution
-- ============================================================

begin;

create or replace function public.complete_follow_up_task(
  requested_task_id uuid,
  requested_outcome text,
  requested_notes text default null,
  requested_expected_updated_at timestamptz default null
)
returns public.follow_up_tasks
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_task public.follow_up_tasks;
  clean_outcome text;
  clean_notes text;
  completion_time timestamptz;
begin
  if requested_task_id is null then
    raise exception
      'A valid follow-up task ID is required';
  end if;

  clean_outcome :=
    nullif(
      regexp_replace(
        btrim(requested_outcome),
        '[[:space:]]+',
        ' ',
        'g'
      ),
      ''
    );

  if clean_outcome is null then
    raise exception
      'A follow-up completion outcome is required';
  end if;

  if char_length(clean_outcome) > 250 then
    raise exception
      'Follow-up outcome must not exceed 250 characters';
  end if;

  clean_notes :=
    nullif(
      btrim(requested_notes),
      ''
    );

  if char_length(clean_notes) > 5000 then
    raise exception
      'Completion notes must not exceed 5000 characters';
  end if;

  select *
  into target_task
  from public.follow_up_tasks
  where id = requested_task_id
    and deleted_at is null
  for update;

  if not found then
    raise exception
      'Follow-up task not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_task.organization_id,
      'followups.complete'
    ) then
    raise exception
      'Permission denied';
  end if;

  if requested_expected_updated_at is not null
    and target_task.updated_at is distinct from
      requested_expected_updated_at then
    raise exception
      'Follow-up task changed after the form was opened'
      using errcode = '40001';
  end if;

  if target_task.status = 'completed' then
    return target_task;
  end if;

  if target_task.status = 'cancelled' then
    raise exception
      'Cancelled follow-up task cannot be completed';
  end if;

  if target_task.status = 'failed' then
    raise exception
      'Failed follow-up task cannot be completed';
  end if;

  completion_time := now();

  update public.follow_up_tasks
  set
    status =
      'completed',

    completion_outcome =
      clean_outcome,

    completion_notes =
      clean_notes,

    completed_at =
      completion_time,

    metadata =
      coalesce(
        metadata,
        '{}'::jsonb
      ) ||
      jsonb_build_object(
        'last_completion_outcome',
          clean_outcome,

        'last_completed_at',
          completion_time,

        'last_completed_by',
          auth.uid(),

        'completion_previous_status',
          target_task.status
      ),

    updated_by =
      auth.uid(),

    updated_at =
      completion_time

  where id = target_task.id
  returning *
  into target_task;

  return target_task;
end;
$function$;

comment on function
  public.complete_follow_up_task(
    uuid,
    text,
    text,
    timestamptz
  )
is
  'Securely completes an active follow-up task using followups.complete permission, input validation, row locking, terminal-state protection, optimistic concurrency, and completion audit metadata.';

revoke all on function
  public.complete_follow_up_task(
    uuid,
    text,
    text,
    timestamptz
  )
from public, anon, authenticated;

grant execute on function
  public.complete_follow_up_task(
    uuid,
    text,
    text,
    timestamptz
  )
to authenticated, service_role;

do $verification$
declare
  function_oid oid;
  function_definition text;
  function_configuration text[];
  is_security_definer boolean;
  default_argument_count integer;
begin
  function_oid :=
    to_regprocedure(
      'public.complete_follow_up_task(uuid,text,text,timestamptz)'
    );

  if function_oid is null then
    raise exception
      'Migration 053 verification failed: complete_follow_up_task was not created';
  end if;

  select
    function_row.prosecdef,
    function_row.proconfig,
    function_row.pronargdefaults
  into
    is_security_definer,
    function_configuration,
    default_argument_count
  from pg_catalog.pg_proc function_row
  where function_row.oid = function_oid;

  if not is_security_definer then
    raise exception
      'Migration 053 verification failed: complete_follow_up_task is not SECURITY DEFINER';
  end if;

  if not exists (
    select 1
    from unnest(
      coalesce(
        function_configuration,
        array[]::text[]
      )
    ) as configuration(configuration_value)
    where configuration_value in (
      'search_path=',
      'search_path=""'
    )
  ) then
    raise exception
      'Migration 053 verification failed: secure empty search_path was not found';
  end if;

  if default_argument_count <> 2 then
    raise exception
      'Migration 053 verification failed: RPC default arguments changed';
  end if;

  function_definition :=
    lower(
      pg_get_functiondef(
        function_oid
      )
    );

  if position(
    'followups.complete'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 053 verification failed: followups.complete permission guard was not found';
  end if;

  if position(
    'for update'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 053 verification failed: row locking was not found';
  end if;

  if position(
    '40001'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 053 verification failed: concurrency error code was not found';
  end if;

  if position(
    'char_length(clean_outcome) > 250'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 053 verification failed: completion outcome limit was not found';
  end if;

  if position(
    'char_length(clean_notes) > 5000'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 053 verification failed: completion notes limit was not found';
  end if;

  if position(
    'target_task.status = ''cancelled'''
    in function_definition
  ) = 0 then
    raise exception
      'Migration 053 verification failed: cancelled-state protection was not found';
  end if;

  if position(
    'target_task.status = ''failed'''
    in function_definition
  ) = 0 then
    raise exception
      'Migration 053 verification failed: failed-state protection was not found';
  end if;

  if position(
    'last_completed_at'
    in function_definition
  ) = 0
    or position(
      'last_completed_by'
      in function_definition
    ) = 0
    or position(
      'completion_previous_status'
      in function_definition
    ) = 0 then
    raise exception
      'Migration 053 verification failed: completion audit metadata was not found';
  end if;

  if has_function_privilege(
    'anon',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Migration 053 verification failed: anon can execute complete_follow_up_task';
  end if;

  if not has_function_privilege(
    'authenticated',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Migration 053 verification failed: authenticated cannot execute complete_follow_up_task';
  end if;

  if not has_function_privilege(
    'service_role',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Migration 053 verification failed: service_role cannot execute complete_follow_up_task';
  end if;
end;
$verification$;

commit;
