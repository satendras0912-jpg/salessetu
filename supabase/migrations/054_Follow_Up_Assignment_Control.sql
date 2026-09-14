-- 054_Follow_Up_Assignment_Control.sql
--
-- Purpose:
--   Harden follow-up assignment with:
--   - server-side input validation
--   - organization permission validation
--   - active-member validation
--   - row locking
--   - optimistic concurrency protection
--   - terminal-state protection
--   - idempotent assignment behavior
--   - assignment audit fields and metadata
--   - restricted function execution
-- ============================================================

begin;

create or replace function public.assign_follow_up_task(
  requested_task_id uuid,
  requested_assigned_to uuid,
  requested_reason text default null,
  requested_expected_updated_at timestamptz default null
)
returns public.follow_up_tasks
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_task public.follow_up_tasks;
  clean_reason text;
  assignment_time timestamptz;
begin
  if requested_task_id is null then
    raise exception
      'A valid follow-up task ID is required';
  end if;

  if requested_assigned_to is null then
    raise exception
      'A valid follow-up assignee is required';
  end if;

  clean_reason :=
    nullif(
      btrim(requested_reason),
      ''
    );

  if char_length(clean_reason) > 1000 then
    raise exception
      'Assignment reason must not exceed 1000 characters';
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
      'followups.assign'
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

  if target_task.status in (
    'completed',
    'cancelled',
    'failed'
  ) then
    raise exception
      'Terminal follow-up task cannot be assigned'
      using
        errcode = '23514',
        detail = format(
          'Follow-up task status is %s.',
          target_task.status
        );
  end if;

  if not exists (
    select 1
    from public.organization_members member_row
    where member_row.organization_id =
      target_task.organization_id
      and member_row.user_id =
        requested_assigned_to
      and member_row.membership_status =
        'active'
  ) then
    raise exception
      'Assigned user must be an active organization member';
  end if;

  if target_task.assigned_to
    is not distinct from requested_assigned_to then
    return target_task;
  end if;

  assignment_time := now();

  update public.follow_up_tasks
  set
    assigned_to =
      requested_assigned_to,

    assigned_by =
      auth.uid(),

    assigned_at =
      assignment_time,

    metadata =
      coalesce(
        metadata,
        '{}'::jsonb
      ) ||
      jsonb_build_object(
        'last_assignment_reason',
          clean_reason,

        'last_assigned_at',
          assignment_time,

        'last_assigned_by',
          auth.uid(),

        'previous_assigned_to',
          target_task.assigned_to
      ),

    updated_by =
      auth.uid(),

    updated_at =
      assignment_time

  where id = target_task.id
  returning *
  into target_task;

  return target_task;
end;
$function$;

comment on function
  public.assign_follow_up_task(
    uuid,
    uuid,
    text,
    timestamptz
  )
is
  'Securely assigns an active follow-up task to an active organization member using followups.assign permission, row locking, optimistic concurrency, terminal-state protection, and assignment audit metadata.';

revoke all on function
  public.assign_follow_up_task(
    uuid,
    uuid,
    text,
    timestamptz
  )
from public, anon, authenticated;

grant execute on function
  public.assign_follow_up_task(
    uuid,
    uuid,
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
      'public.assign_follow_up_task(uuid,uuid,text,timestamptz)'
    );

  if function_oid is null then
    raise exception
      'Migration 054 verification failed: assign_follow_up_task was not created';
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
      'Migration 054 verification failed: assign_follow_up_task is not SECURITY DEFINER';
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
      'Migration 054 verification failed: secure empty search_path was not found';
  end if;

  if default_argument_count <> 2 then
    raise exception
      'Migration 054 verification failed: RPC default arguments changed';
  end if;

  function_definition :=
    lower(
      pg_get_functiondef(
        function_oid
      )
    );

  if position(
    'requested_assigned_to is null'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 054 verification failed: required assignee validation was not found';
  end if;

  if position(
    'char_length(clean_reason) > 1000'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 054 verification failed: assignment reason limit was not found';
  end if;

  if position(
    'followups.assign'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 054 verification failed: followups.assign permission guard was not found';
  end if;

  if position(
    'for update'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 054 verification failed: row locking was not found';
  end if;

  if position(
    '40001'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 054 verification failed: concurrency error code was not found';
  end if;

  if position(
    'target_task.status in'
    in function_definition
  ) = 0
    or position(
      '''completed'''
      in function_definition
    ) = 0
    or position(
      '''cancelled'''
      in function_definition
    ) = 0
    or position(
      '''failed'''
      in function_definition
    ) = 0
    or position(
      '23514'
      in function_definition
    ) = 0 then
    raise exception
      'Migration 054 verification failed: terminal-state protection was not found';
  end if;

  if position(
    'public.organization_members'
    in function_definition
  ) = 0
    or position(
      'membership_status'
      in function_definition
    ) = 0
    or position(
      '''active'''
      in function_definition
    ) = 0 then
    raise exception
      'Migration 054 verification failed: active-member validation was not found';
  end if;

  if position(
    'is not distinct from requested_assigned_to'
    in function_definition
  ) = 0 then
    raise exception
      'Migration 054 verification failed: idempotent assignment guard was not found';
  end if;

  if position(
    'assigned_by'
    in function_definition
  ) = 0
    or position(
      'assigned_at'
      in function_definition
    ) = 0
    or position(
      'last_assignment_reason'
      in function_definition
    ) = 0
    or position(
      'last_assigned_at'
      in function_definition
    ) = 0
    or position(
      'last_assigned_by'
      in function_definition
    ) = 0
    or position(
      'previous_assigned_to'
      in function_definition
    ) = 0 then
    raise exception
      'Migration 054 verification failed: assignment audit data was not found';
  end if;

  if has_function_privilege(
    'anon',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Migration 054 verification failed: anon can execute assign_follow_up_task';
  end if;

  if not has_function_privilege(
    'authenticated',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Migration 054 verification failed: authenticated cannot execute assign_follow_up_task';
  end if;

  if not has_function_privilege(
    'service_role',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Migration 054 verification failed: service_role cannot execute assign_follow_up_task';
  end if;
end;
$verification$;

commit;
