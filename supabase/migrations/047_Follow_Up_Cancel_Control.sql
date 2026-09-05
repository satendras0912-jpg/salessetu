-- ============================================================
-- 047_Follow_Up_Cancel_Control.sql
--
-- Purpose:
--   Add a secure follow-up cancellation operation with:
--   - organization permission validation
--   - row locking
--   - optimistic concurrency protection
--   - terminal-state validation
--   - cancellation audit metadata
-- ============================================================

begin;

create or replace function public.cancel_follow_up_task(
  requested_task_id uuid,
  requested_reason text,
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
begin
  if requested_task_id is null then
    raise exception
      'A valid follow-up task ID is required';
  end if;

  clean_reason :=
    nullif(
      btrim(requested_reason),
      ''
    );

  if clean_reason is null then
    raise exception
      'A cancellation reason is required';
  end if;

  if char_length(clean_reason) > 1000 then
    raise exception
      'Cancellation reason must not exceed 1000 characters';
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
      'followups.update'
    ) then
    raise exception
      'Permission denied';
  end if;

  if requested_expected_updated_at is not null
    and target_task.updated_at is distinct from
      requested_expected_updated_at then
    raise exception
      'Follow-up task changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if target_task.status = 'completed' then
    raise exception
      'Completed follow-up task cannot be cancelled';
  end if;

  if target_task.status = 'failed' then
    raise exception
      'Failed follow-up task cannot be cancelled';
  end if;

  if target_task.status = 'cancelled' then
    return target_task;
  end if;

  update public.follow_up_tasks
  set
    status =
      'cancelled',

    metadata =
      coalesce(
        metadata,
        '{}'::jsonb
      ) ||
      jsonb_build_object(
        'last_cancellation_reason',
          clean_reason,

        'last_cancelled_at',
          now()
      ),

    updated_by =
      auth.uid(),

    updated_at =
      now()

  where id = target_task.id
  returning *
  into target_task;

  return target_task;
end;
$function$;

comment on function
  public.cancel_follow_up_task(
    uuid,
    text,
    timestamptz
  )
is
  'Securely cancels an active follow-up task using followups.update permission and optimistic concurrency protection.';

revoke all on function
  public.cancel_follow_up_task(
    uuid,
    text,
    timestamptz
  )
from public, anon, authenticated;

grant execute on function
  public.cancel_follow_up_task(
    uuid,
    text,
    timestamptz
  )
to authenticated, service_role;

do $verification$
declare
  function_definition text;
begin
  if to_regprocedure(
    'public.cancel_follow_up_task(uuid,text,timestamptz)'
  ) is null then
    raise exception
      'Migration verification failed: cancel_follow_up_task was not created';
  end if;

  function_definition :=
    pg_get_functiondef(
      'public.cancel_follow_up_task(uuid,text,timestamptz)'::regprocedure
    );

  if position(
    'followups.update'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: followups.update permission guard was not found';
  end if;

  if position(
    'P0001'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: concurrency error code was not found';
  end if;

  if has_function_privilege(
    'anon',
    'public.cancel_follow_up_task(uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: anon can execute cancel_follow_up_task';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.cancel_follow_up_task(uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: authenticated cannot execute cancel_follow_up_task';
  end if;
end;
$verification$;

commit;
