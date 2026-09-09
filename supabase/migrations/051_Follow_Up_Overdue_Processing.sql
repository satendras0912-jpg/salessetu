begin;

-- =========================================================
-- 1. PROCESSING INDEXES
-- =========================================================

create index if not exists
  follow_up_tasks_overdue_processing_idx
on public.follow_up_tasks (
  due_at,
  id
)
where deleted_at is null
  and status in (
    'pending',
    'in_progress',
    'rescheduled'
  );

create index if not exists
  follow_up_tasks_sla_processing_idx
on public.follow_up_tasks (
  sla_due_at,
  id
)
where deleted_at is null
  and sla_due_at is not null
  and status not in (
    'completed',
    'cancelled',
    'failed'
  );

create index if not exists
  follow_up_tasks_org_sla_processing_idx
on public.follow_up_tasks (
  organization_id,
  sla_due_at,
  id
)
where deleted_at is null
  and sla_due_at is not null
  and status not in (
    'completed',
    'cancelled',
    'failed'
  );

-- =========================================================
-- 2. REPLACE LEGACY UNBOUNDED PROCESSOR
-- =========================================================

drop function if exists
  public.process_overdue_follow_ups(uuid);

drop function if exists
  public.process_overdue_follow_ups(
    uuid,
    integer
  );

create function
  public.process_overdue_follow_ups(
    requested_organization_id uuid
      default null,

    requested_batch_size integer
      default 250
  )
returns table (
  processed_count integer,
  overdue_count integer,
  sla_breached_count integer,
  sla_at_risk_count integer,
  remaining_count bigint,
  processed_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  caller_role text :=
    coalesce(
      auth.role(),
      ''
    );

  caller_user_id uuid :=
    auth.uid();

  processing_time timestamptz :=
    now();

  updated_processed_count integer := 0;
  updated_overdue_count integer := 0;
  updated_breached_count integer := 0;
  updated_at_risk_count integer := 0;
  pending_processing_count bigint := 0;
begin
  if requested_batch_size is null
    or requested_batch_size < 1
    or requested_batch_size > 1000 then

    raise exception using
      errcode = '22023',
      message =
        'Batch size must be between 1 and 1000';

  end if;

  if caller_role <> 'service_role' then
    if caller_user_id is null then
      raise exception using
        errcode = '42501',
        message =
          'Authentication is required';
    end if;

    if requested_organization_id is null then
      raise exception using
        errcode = '42501',
        message =
          'Organization ID is required for authenticated users';
    end if;

    if not public.has_organization_permission(
      requested_organization_id,
      'followups.manage_sla'
    ) then
      raise exception using
        errcode = '42501',
        message =
          'followups.manage_sla permission is required';
    end if;
  end if;

  if requested_organization_id is not null
    and not exists (
      select 1
      from public.organizations
      where id =
        requested_organization_id
    ) then

    raise exception using
      errcode = 'P0002',
      message =
        'Organization not found';

  end if;

  with candidate_tasks as materialized (
    select
      task.id,
      task.status as previous_status,
      task.sla_status
        as previous_sla_status,

      case
        when task.status in (
          'pending',
          'in_progress',
          'rescheduled'
        )
          and task.due_at <
            processing_time
        then 'overdue'
        else task.status
      end as next_status,

      case
        when task.status not in (
          'completed',
          'cancelled',
          'failed'
        )
          and task.sla_due_at
            is not null
          and task.sla_due_at <
            processing_time
          and task.sla_status <>
            'breached'
        then 'breached'

        when task.status not in (
          'completed',
          'cancelled',
          'failed'
        )
          and task.sla_due_at
            is not null
          and task.sla_due_at >=
            processing_time
          and task.sla_due_at <=
            processing_time +
              interval '30 minutes'
          and task.sla_status not in (
            'at_risk',
            'breached'
          )
        then 'at_risk'

        else task.sla_status
      end as next_sla_status
    from public.follow_up_tasks
      as task
    where task.deleted_at is null
      and (
        requested_organization_id
          is null
        or task.organization_id =
          requested_organization_id
      )
      and (
        (
          task.status in (
            'pending',
            'in_progress',
            'rescheduled'
          )
          and task.due_at <
            processing_time
        )
        or
        (
          task.status not in (
            'completed',
            'cancelled',
            'failed'
          )
          and task.sla_due_at
            is not null
          and (
            (
              task.sla_due_at <
                processing_time
              and task.sla_status <>
                'breached'
            )
            or
            (
              task.sla_due_at >=
                processing_time
              and task.sla_due_at <=
                processing_time +
                  interval '30 minutes'
              and task.sla_status
                not in (
                  'at_risk',
                  'breached'
                )
            )
          )
        )
      )
    order by
      coalesce(
        task.sla_due_at,
        task.due_at
      ),
      task.due_at,
      task.id
    for update of task
      skip locked
    limit requested_batch_size
  ),
  updated_tasks as (
    update public.follow_up_tasks
      as task
    set
      status =
        candidate.next_status,

      sla_status =
        candidate.next_sla_status,

      updated_by =
        caller_user_id,

      metadata =
        coalesce(
          task.metadata,
          '{}'::jsonb
        )
        ||
        jsonb_build_object(
          'last_overdue_processing_at',
          processing_time,

          'last_overdue_processing_source',
          case
            when caller_role =
              'service_role'
            then 'system'
            else 'manual'
          end,

          'last_overdue_processed_by',
          caller_user_id
        )
        ||
        case
          when candidate.next_status =
              'overdue'
            and candidate.previous_status
              is distinct from
                candidate.next_status
          then jsonb_build_object(
            'last_overdue_transition_at',
            processing_time,

            'last_overdue_previous_status',
            candidate.previous_status
          )
          else '{}'::jsonb
        end
        ||
        case
          when candidate.previous_sla_status
              is distinct from
                candidate.next_sla_status
          then jsonb_build_object(
            'last_automatic_sla_transition_at',
            processing_time,

            'last_automatic_sla_previous_status',
            candidate.previous_sla_status,

            'last_automatic_sla_status',
            candidate.next_sla_status
          )
          else '{}'::jsonb
        end,

      updated_at =
        processing_time
    from candidate_tasks
      as candidate
    where task.id =
      candidate.id
    returning
      candidate.previous_status,
      candidate.next_status,
      candidate.previous_sla_status,
      candidate.next_sla_status
  )
  select
    count(*)::integer,

    (
      count(*) filter (
        where next_status =
            'overdue'
          and previous_status
            is distinct from
              next_status
      )
    )::integer,

    (
      count(*) filter (
        where next_sla_status =
            'breached'
          and previous_sla_status
            is distinct from
              next_sla_status
      )
    )::integer,

    (
      count(*) filter (
        where next_sla_status =
            'at_risk'
          and previous_sla_status
            is distinct from
              next_sla_status
      )
    )::integer
  into
    updated_processed_count,
    updated_overdue_count,
    updated_breached_count,
    updated_at_risk_count
  from updated_tasks;

  select count(*)
  into pending_processing_count
  from public.follow_up_tasks
    as task
  where task.deleted_at is null
    and (
      requested_organization_id
        is null
      or task.organization_id =
        requested_organization_id
    )
    and (
      (
        task.status in (
          'pending',
          'in_progress',
          'rescheduled'
        )
        and task.due_at <
          processing_time
      )
      or
      (
        task.status not in (
          'completed',
          'cancelled',
          'failed'
        )
        and task.sla_due_at
          is not null
        and (
          (
            task.sla_due_at <
              processing_time
            and task.sla_status <>
              'breached'
          )
          or
          (
            task.sla_due_at >=
              processing_time
            and task.sla_due_at <=
              processing_time +
                interval '30 minutes'
            and task.sla_status
              not in (
                'at_risk',
                'breached'
              )
          )
        )
      )
    );

  return query
  select
    updated_processed_count,
    updated_overdue_count,
    updated_breached_count,
    updated_at_risk_count,
    pending_processing_count,
    processing_time;
end;
$function$;

comment on function
  public.process_overdue_follow_ups(
    uuid,
    integer
  )
is
  'Processes overdue and SLA transitions in bounded, concurrency-safe batches. Authenticated callers require followups.manage_sla; service_role may process all organizations.';

revoke all
on function
  public.process_overdue_follow_ups(
    uuid,
    integer
  )
from public;

revoke all
on function
  public.process_overdue_follow_ups(
    uuid,
    integer
  )
from anon;

grant execute
on function
  public.process_overdue_follow_ups(
    uuid,
    integer
  )
to authenticated;

grant execute
on function
  public.process_overdue_follow_ups(
    uuid,
    integer
  )
to service_role;

-- =========================================================
-- 3. MIGRATION VERIFICATION
-- =========================================================

do $verification$
declare
  processor_definition text;
begin
  if to_regprocedure(
    'public.process_overdue_follow_ups(uuid)'
  ) is not null then
    raise exception
      'Migration verification failed: legacy processor still exists';
  end if;

  if to_regprocedure(
    'public.process_overdue_follow_ups(uuid,integer)'
  ) is null then
    raise exception
      'Migration verification failed: bounded processor was not created';
  end if;

  select pg_get_functiondef(
    to_regprocedure(
      'public.process_overdue_follow_ups(uuid,integer)'
    )
  )
  into processor_definition;

  if position(
    'skip locked'
    in lower(processor_definition)
  ) = 0 then
    raise exception
      'Migration verification failed: SKIP LOCKED protection is missing';
  end if;

  if position(
    '''failed'''
    in lower(processor_definition)
  ) = 0 then
    raise exception
      'Migration verification failed: failed terminal status is not protected';
  end if;

  if not exists (
    select 1
    from pg_proc
    where oid = to_regprocedure(
      'public.process_overdue_follow_ups(uuid,integer)'
    )
      and prosecdef
  ) then
    raise exception
      'Migration verification failed: processor is not SECURITY DEFINER';
  end if;

  if has_function_privilege(
    'anon',
    'public.process_overdue_follow_ups(uuid,integer)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: anon can execute processor';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.process_overdue_follow_ups(uuid,integer)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: authenticated cannot execute processor';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.process_overdue_follow_ups(uuid,integer)',
    'EXECUTE'
  ) then
    raise exception
      'Migration verification failed: service_role cannot execute processor';
  end if;

  if to_regclass(
    'public.follow_up_tasks_overdue_processing_idx'
  ) is null then
    raise exception
      'Migration verification failed: overdue processing index is missing';
  end if;

  if to_regclass(
    'public.follow_up_tasks_sla_processing_idx'
  ) is null then
    raise exception
      'Migration verification failed: SLA processing index is missing';
  end if;

  if to_regclass(
    'public.follow_up_tasks_org_sla_processing_idx'
  ) is null then
    raise exception
      'Migration verification failed: organization SLA processing index is missing';
  end if;
end;
$verification$;

commit;
