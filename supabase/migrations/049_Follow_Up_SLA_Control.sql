-- ============================================================
-- 049_Follow_Up_SLA_Control.sql
--
-- Purpose:
--   Add secure per-task follow-up SLA management with:
--   - followups.manage_sla permission validation
--   - SLA deadline set, update and clear support
--   - row locking
--   - optimistic concurrency protection
--   - terminal-state protection
--   - SLA change audit metadata
-- ============================================================

begin;

create or replace function public.manage_follow_up_sla(
  requested_task_id uuid,
  requested_sla_due_at timestamptz,
  requested_reason text,
  requested_expected_updated_at timestamptz
)
returns public.follow_up_tasks
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_task public.follow_up_tasks;
  clean_reason text;
  next_sla_status text;
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
      'An SLA change reason is required';
  end if;

  if char_length(clean_reason) > 1000 then
    raise exception
      'SLA change reason must not exceed 1000 characters';
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

  if coalesce(auth.role(), '') <> 'service_role'
    and not public.has_organization_permission(
      target_task.organization_id,
      'followups.manage_sla'
    ) then
    raise exception
      'Permission denied';
  end if;

  if requested_expected_updated_at is null then
    raise exception
      'The original follow-up update timestamp is required';
  end if;

  if target_task.updated_at is distinct from
    requested_expected_updated_at then
    raise exception
      'Follow-up task changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if target_task.status in (
    'completed',
    'cancelled',
    'failed'
  ) then
    raise exception
      'Terminal follow-up task SLA cannot be changed';
  end if;

  next_sla_status :=
    case
      when requested_sla_due_at is null
        then 'not_applicable'

      when requested_sla_due_at < now()
        then 'breached'

      when requested_sla_due_at <=
        now() + interval '30 minutes'
        then 'at_risk'

      else 'within_sla'
    end;

  update public.follow_up_tasks
  set
    sla_due_at =
      requested_sla_due_at,

    sla_status =
      next_sla_status,

    metadata =
      coalesce(
        metadata,
        '{}'::jsonb
      ) ||
      jsonb_build_object(
        'last_sla_change_reason',
          clean_reason,

        'last_sla_changed_at',
          now(),

        'last_sla_due_at',
          requested_sla_due_at,

        'last_sla_status',
          next_sla_status
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
  public.manage_follow_up_sla(
    uuid,
    timestamptz,
    text,
    timestamptz
  )
is
  'Securely sets, updates or clears a follow-up SLA deadline using followups.manage_sla permission, audit metadata and optimistic concurrency protection.';

revoke all on function
  public.manage_follow_up_sla(
    uuid,
    timestamptz,
    text,
    timestamptz
  )
from public, anon, authenticated;

grant execute on function
  public.manage_follow_up_sla(
    uuid,
    timestamptz,
    text,
    timestamptz
  )
to authenticated, service_role;

do $verification$
declare
  function_definition text;
begin
  if to_regprocedure(
    'public.manage_follow_up_sla(uuid,timestamptz,text,timestamptz)'
  ) is null then
    raise exception
      'Migration verification failed: manage_follow_up_sla was not created';
  end if;

  function_definition :=
    pg_get_functiondef(
      'public.manage_follow_up_sla(uuid,timestamptz,text,timestamptz)'::regprocedure
    );

  if position(
    'followups.manage_sla'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: followups.manage_sla permission guard was not found';
  end if;

  if position(
    'P0001'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: concurrency error code was not found';
  end if;

  if position(
    'sla_due_at'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: SLA deadline update was not found';
  end if;

  if position(
    'not_applicable'
    in function_definition
  ) = 0
    or position(
      'within_sla'
      in function_definition
    ) = 0
    or position(
      'at_risk'
      in function_definition
    ) = 0
    or position(
      'breached'
      in function_definition
    ) = 0 then
    raise exception
      'Migration verification failed: required SLA status handling was not found';
  end if;

  if has_function_privilege(
    'anon',
    'public.manage_follow_up_sla(uuid,timestamptz,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: anon can execute manage_follow_up_sla';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.manage_follow_up_sla(uuid,timestamptz,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: authenticated cannot execute manage_follow_up_sla';
  end if;
end;
$verification$;

commit;
