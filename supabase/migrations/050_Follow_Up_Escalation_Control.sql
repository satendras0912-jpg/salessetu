-- ============================================================
-- 050_Follow_Up_Escalation_Control.sql
--
-- Purpose:
--   Add secure and auditable follow-up escalation with:
--   - followups.assign permission validation
--   - active organization-member validation
--   - row locking
--   - optimistic concurrency protection
--   - terminal-state protection
--   - escalation reason and audit metadata
--   - SLA state preservation
-- ============================================================

begin;

-- Remove the older RPC that does not provide
-- optimistic concurrency or terminal-state protection.
drop function if exists
  public.escalate_follow_up_task(
    uuid,
    uuid,
    text
  );

create or replace function public.escalate_follow_up_task(
  requested_task_id uuid,
  requested_escalated_to uuid,
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
  next_escalation_level integer;
begin
  if requested_task_id is null then
    raise exception
      'A valid follow-up task ID is required';
  end if;

  if requested_escalated_to is null then
    raise exception
      'A valid escalation member is required';
  end if;

  clean_reason :=
    nullif(
      btrim(requested_reason),
      ''
    );

  if clean_reason is null then
    raise exception
      'An escalation reason is required';
  end if;

  if char_length(clean_reason) > 1000 then
    raise exception
      'Escalation reason must not exceed 1000 characters';
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
      'followups.assign'
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
      'Terminal follow-up task cannot be escalated';
  end if;

  if not exists (
    select 1
    from public.organization_members om
    where om.organization_id =
      target_task.organization_id
      and om.user_id =
        requested_escalated_to
      and om.membership_status =
        'active'
  ) then
    raise exception
      'Escalation user must be an active organization member';
  end if;

  next_escalation_level :=
    coalesce(
      target_task.escalation_level,
      0
    ) + 1;

  update public.follow_up_tasks
  set
    escalation_level =
      next_escalation_level,

    escalated_at =
      now(),

    escalated_to =
      requested_escalated_to,

    metadata =
      coalesce(
        metadata,
        '{}'::jsonb
      ) ||
      jsonb_build_object(
        'last_escalation_reason',
          clean_reason,

        'last_escalated_at',
          now(),

        'last_escalated_to',
          requested_escalated_to,

        'previous_escalated_to',
          target_task.escalated_to,

        'last_escalation_level',
          next_escalation_level,

        'last_escalated_by',
          auth.uid()
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
  public.escalate_follow_up_task(
    uuid,
    uuid,
    text,
    timestamptz
  )
is
  'Escalates an active follow-up task using followups.assign permission, active-member validation, row locking, audit metadata and optimistic concurrency protection while preserving SLA state.';

revoke all on function
  public.escalate_follow_up_task(
    uuid,
    uuid,
    text,
    timestamptz
  )
from public, anon, authenticated;

grant execute on function
  public.escalate_follow_up_task(
    uuid,
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
    'public.escalate_follow_up_task(uuid,uuid,text)'
  ) is not null then
    raise exception
      'Migration verification failed: insecure three-argument escalation RPC still exists';
  end if;

  if to_regprocedure(
    'public.escalate_follow_up_task(uuid,uuid,text,timestamptz)'
  ) is null then
    raise exception
      'Migration verification failed: secure escalation RPC was not created';
  end if;

  function_definition :=
    pg_get_functiondef(
      'public.escalate_follow_up_task(uuid,uuid,text,timestamptz)'::regprocedure
    );

  if position(
    'followups.assign'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: followups.assign permission guard was not found';
  end if;

  if position(
    'P0001'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: concurrency error code was not found';
  end if;

  if position(
    'for update'
    in lower(function_definition)
  ) = 0 then
    raise exception
      'Migration verification failed: row locking was not found';
  end if;

  if position(
    'terminal follow-up task cannot be escalated'
    in lower(function_definition)
  ) = 0 then
    raise exception
      'Migration verification failed: terminal-state protection was not found';
  end if;

  if position(
    'last_escalation_reason'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: escalation audit metadata was not found';
  end if;

  if position(
    'sla_status'
    in function_definition
  ) > 0 then
    raise exception
      'Migration verification failed: escalation RPC must preserve SLA state';
  end if;

  if has_function_privilege(
    'anon',
    'public.escalate_follow_up_task(uuid,uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: anon can execute escalation RPC';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.escalate_follow_up_task(uuid,uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: authenticated cannot execute escalation RPC';
  end if;
end;
$verification$;

commit;
