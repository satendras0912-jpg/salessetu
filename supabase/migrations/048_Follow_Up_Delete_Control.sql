-- ============================================================
-- 048_Follow_Up_Delete_Control.sql
--
-- Purpose:
--   Add secure and auditable follow-up soft deletion with:
--   - followups.delete permission validation
--   - direct hard-delete protection
--   - row locking
--   - optimistic concurrency protection
--   - deletion reason and audit metadata
-- ============================================================

begin;

-- Direct client-side hard deletion is disabled.
-- Authorized users must use delete_follow_up_task().
drop policy if exists
  "Authorized users can delete follow-up tasks"
on public.follow_up_tasks;

revoke delete
on table public.follow_up_tasks
from public, anon, authenticated;

create or replace function public.delete_follow_up_task(
  requested_task_id uuid,
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
      'A deletion reason is required';
  end if;

  if char_length(clean_reason) > 1000 then
    raise exception
      'Deletion reason must not exceed 1000 characters';
  end if;

  select *
  into target_task
  from public.follow_up_tasks
  where id = requested_task_id
  for update;

  if not found then
    raise exception
      'Follow-up task not found';
  end if;

  if coalesce(auth.role(), '') <> 'service_role'
    and not public.has_organization_permission(
      target_task.organization_id,
      'followups.delete'
    ) then
    raise exception
      'Permission denied';
  end if;

  if target_task.deleted_at is not null then
    return target_task;
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

  update public.follow_up_tasks
  set
    metadata =
      coalesce(
        metadata,
        '{}'::jsonb
      ) ||
      jsonb_build_object(
        'last_deletion_reason',
          clean_reason,

        'last_deleted_at',
          now()
      ),

    deleted_by =
      auth.uid(),

    deleted_at =
      now(),

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
  public.delete_follow_up_task(
    uuid,
    text,
    timestamptz
  )
is
  'Soft deletes a follow-up task using followups.delete permission, row locking, audit metadata and optimistic concurrency protection.';

revoke all on function
  public.delete_follow_up_task(
    uuid,
    text,
    timestamptz
  )
from public, anon, authenticated;

grant execute on function
  public.delete_follow_up_task(
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
    'public.delete_follow_up_task(uuid,text,timestamptz)'
  ) is null then
    raise exception
      'Migration verification failed: delete_follow_up_task was not created';
  end if;

  function_definition :=
    pg_get_functiondef(
      'public.delete_follow_up_task(uuid,text,timestamptz)'::regprocedure
    );

  if position(
    'followups.delete'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: followups.delete permission guard was not found';
  end if;

  if position(
    'P0001'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: concurrency error code was not found';
  end if;

  if position(
    'deleted_at'
    in function_definition
  ) = 0 then
    raise exception
      'Migration verification failed: soft-delete field update was not found';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'follow_up_tasks'
      and cmd = 'DELETE'
  ) then
    raise exception
      'Migration verification failed: a direct follow-up DELETE policy still exists';
  end if;

  if has_table_privilege(
    'authenticated',
    'public.follow_up_tasks',
    'DELETE'
  ) then
    raise exception
      'Migration verification failed: authenticated retains direct DELETE privilege';
  end if;

  if has_function_privilege(
    'anon',
    'public.delete_follow_up_task(uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: anon can execute delete_follow_up_task';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.delete_follow_up_task(uuid,text,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: authenticated cannot execute delete_follow_up_task';
  end if;
end;
$verification$;

commit;
