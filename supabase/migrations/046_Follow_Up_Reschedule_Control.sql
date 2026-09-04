-- ============================================================
-- 046_Follow_Up_Reschedule_Control.sql
--
-- Purpose:
--   Add a secure follow-up reschedule operation with:
--   - organization permission validation
--   - row locking
--   - optimistic concurrency protection
--   - due/reminder validation
--   - audit metadata
-- ============================================================

begin;

create or replace function public.reschedule_follow_up_task(
  requested_task_id uuid,
  requested_due_at timestamptz,
  requested_reminder_at timestamptz default null,
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
begin
  if requested_task_id is null then
    raise exception
      'A valid follow-up task ID is required';
  end if;

  if requested_due_at is null then
    raise exception
      'A follow-up due date and time is required';
  end if;

  clean_reason :=
    nullif(
      btrim(requested_reason),
      ''
    );

  if clean_reason is null then
    raise exception
      'A reschedule reason is required';
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
      'Completed follow-up task cannot be rescheduled';
  end if;

  if target_task.status = 'cancelled' then
    raise exception
      'Cancelled follow-up task cannot be rescheduled';
  end if;

  if requested_due_at <= now() then
    raise exception
      'The rescheduled due time must be in the future';
  end if;

  if requested_reminder_at is not null
    and requested_reminder_at > requested_due_at then
    raise exception
      'The reminder must be scheduled on or before the follow-up due time';
  end if;

  update public.follow_up_tasks
  set
    status = 'rescheduled',

    due_at =
      requested_due_at,

    reminder_at =
      requested_reminder_at,

    metadata =
      coalesce(
        metadata,
        '{}'::jsonb
      ) ||
      jsonb_build_object(
        'last_reschedule_reason',
          clean_reason,

        'last_rescheduled_at',
          now(),

        'previous_due_at',
          target_task.due_at,

        'previous_reminder_at',
          target_task.reminder_at
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
  public.reschedule_follow_up_task(
    uuid,
    timestamptz,
    timestamptz,
    text,
    timestamptz
  )
is
  'Securely reschedules an active follow-up task using followups.update permission and optimistic concurrency protection.';

revoke all on function
  public.reschedule_follow_up_task(
    uuid,
    timestamptz,
    timestamptz,
    text,
    timestamptz
  )
from public, anon, authenticated;

grant execute on function
  public.reschedule_follow_up_task(
    uuid,
    timestamptz,
    timestamptz,
    text,
    timestamptz
  )
to authenticated, service_role;

do $verification$
begin
  if to_regprocedure(
    'public.reschedule_follow_up_task(uuid,timestamptz,timestamptz,text,timestamptz)'
  ) is null then
    raise exception
      'Migration verification failed: reschedule_follow_up_task was not created';
  end if;
end;
$verification$;

commit;
