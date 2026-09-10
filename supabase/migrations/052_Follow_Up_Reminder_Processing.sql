-- ============================================================
-- 052_Follow_Up_Reminder_Processing.sql
--
-- Purpose:
--   Process due follow-up reminders through the authoritative
--   Notification Engine with:
--   - service-role-only execution
--   - bounded batch processing
--   - FOR UPDATE SKIP LOCKED concurrency protection
--   - organization-scoped idempotency
--   - in-app notification delivery
--   - automatic reminder delivery reset after rescheduling
--   - migration contract verification
-- ============================================================

begin;

-- ============================================================
-- 1. REMINDER PROCESSING INDEXES
-- ============================================================

create index if not exists
  follow_up_tasks_reminder_processing_idx
on public.follow_up_tasks (
  reminder_at,
  due_at,
  id
)
where deleted_at is null
  and reminder_at is not null
  and reminder_sent_at is null
  and assigned_to is not null
  and status in (
    'pending',
    'in_progress',
    'rescheduled',
    'overdue'
  );

create index if not exists
  follow_up_tasks_org_reminder_processing_idx
on public.follow_up_tasks (
  organization_id,
  reminder_at,
  due_at,
  id
)
where deleted_at is null
  and reminder_at is not null
  and reminder_sent_at is null
  and assigned_to is not null
  and status in (
    'pending',
    'in_progress',
    'rescheduled',
    'overdue'
  );

-- ============================================================
-- 2. PROTECT SYSTEM-MANAGED REMINDER DELIVERY FIELD
-- ============================================================

create or replace function
  public.guard_follow_up_reminder_delivery_fields()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  if current_user in (
    'postgres',
    'service_role',
    'supabase_admin'
  )
    or auth.role() = 'service_role' then

    return new;

  end if;

  if new.reminder_sent_at
      is distinct from old.reminder_sent_at then

    raise exception using
      errcode = '42501',
      message =
        'Follow-up reminder delivery fields are system managed';

  end if;

  return new;
end;
$function$;

drop trigger if exists
  "01_follow_up_tasks_guard_reminder_delivery"
on public.follow_up_tasks;

create trigger
  "01_follow_up_tasks_guard_reminder_delivery"
before update of reminder_sent_at
on public.follow_up_tasks
for each row
execute function
  public.guard_follow_up_reminder_delivery_fields();

-- ============================================================
-- 3. RESET DELIVERY STATE WHEN REMINDER CONTEXT CHANGES
-- ============================================================

create or replace function
  public.reset_follow_up_reminder_delivery()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  reset_reason text;
begin
  if new.reminder_at
      is not distinct from old.reminder_at
    and new.due_at
      is not distinct from old.due_at
    and new.assigned_to
      is not distinct from old.assigned_to then

    return new;

  end if;

  reset_reason :=
    case
      when new.reminder_at
          is distinct from old.reminder_at
        and new.due_at
          is distinct from old.due_at
        and new.assigned_to
          is distinct from old.assigned_to
      then 'reminder_due_and_assignee_changed'

      when new.reminder_at
          is distinct from old.reminder_at
        and new.due_at
          is distinct from old.due_at
      then 'reminder_and_due_changed'

      when new.reminder_at
          is distinct from old.reminder_at
        and new.assigned_to
          is distinct from old.assigned_to
      then 'reminder_and_assignee_changed'

      when new.due_at
          is distinct from old.due_at
        and new.assigned_to
          is distinct from old.assigned_to
      then 'due_and_assignee_changed'

      when new.reminder_at
          is distinct from old.reminder_at
      then 'reminder_changed'

      when new.due_at
          is distinct from old.due_at
      then 'due_changed'

      else 'assignee_changed'
    end;

  new.reminder_sent_at := null;

  new.metadata :=
    coalesce(
      new.metadata,
      '{}'::jsonb
    )
    ||
    jsonb_build_object(
      'reminder_delivery_reset_at',
      now(),

      'reminder_delivery_reset_reason',
      reset_reason
    );

  return new;
end;
$function$;

drop trigger if exists
  "05_follow_up_tasks_reset_reminder_delivery"
on public.follow_up_tasks;

create trigger
  "05_follow_up_tasks_reset_reminder_delivery"
before update of
  reminder_at,
  due_at,
  assigned_to
on public.follow_up_tasks
for each row
execute function
  public.reset_follow_up_reminder_delivery();

-- ============================================================
-- 4. REPAIR PREVIOUSLY RESCHEDULED FUTURE REMINDERS
-- ============================================================

update public.follow_up_tasks
set
  reminder_sent_at = null,

  metadata =
    coalesce(
      metadata,
      '{}'::jsonb
    )
    ||
    jsonb_build_object(
      'reminder_delivery_repaired_at',
      now(),

      'reminder_delivery_repair_reason',
      'reminder_after_previous_delivery'
    ),

  updated_at = now()
where deleted_at is null
  and reminder_at is not null
  and reminder_sent_at is not null
  and reminder_at > reminder_sent_at
  and status in (
    'pending',
    'in_progress',
    'rescheduled',
    'overdue'
  );

-- ============================================================
-- 5. BOUNDED DUE-REMINDER PROCESSOR
-- ============================================================

drop function if exists
  public.process_due_follow_up_reminders(
    uuid,
    integer
  );

create function
  public.process_due_follow_up_reminders(
    requested_organization_id uuid
      default null,

    requested_batch_size integer
      default 250
  )
returns table (
  processed_count integer,
  notification_job_count integer,
  delivery_attempt_count integer,
  remaining_count bigint,
  unassigned_due_count bigint,
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

  task_record record;

  notification_job_record
    public.notification_jobs;

  reminder_idempotency_key text;

  in_app_attempt_id uuid;

  expanded_attempt_count integer := 0;
  updated_row_count integer := 0;

  processed_task_count integer := 0;
  created_notification_count integer := 0;
  created_delivery_attempt_count integer := 0;

  pending_reminder_count bigint := 0;
  pending_unassigned_count bigint := 0;
begin
  if caller_role <> 'service_role' then

    raise exception using
      errcode = '42501',
      message =
        'Only service_role may process due follow-up reminders';

  end if;

  if requested_batch_size is null
    or requested_batch_size < 1
    or requested_batch_size > 1000 then

    raise exception using
      errcode = '22023',
      message =
        'Batch size must be between 1 and 1000';

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

  if not exists (
    select 1
    from public.notification_categories
    where category_code = 'followup_due'
      and organization_id is null
      and status = 'active'
  ) then

    raise exception using
      errcode = 'P0002',
      message =
        'Active followup_due notification category not found';

  end if;

  for task_record in
    select
      task.id,
      task.organization_id,
      task.lead_id,
      task.title,
      task.follow_up_type,
      task.status,
      task.assigned_to,
      task.reminder_at,
      task.due_at
    from public.follow_up_tasks
      as task
    where task.deleted_at is null
      and task.reminder_at is not null
      and task.reminder_sent_at is null
      and task.assigned_to is not null
      and task.reminder_at <=
        processing_time
      and task.status in (
        'pending',
        'in_progress',
        'rescheduled',
        'overdue'
      )
      and (
        requested_organization_id
          is null
        or task.organization_id =
          requested_organization_id
      )
    order by
      task.reminder_at,
      task.due_at,
      task.id
    for update of task
      skip locked
    limit requested_batch_size
  loop
    reminder_idempotency_key :=
      'follow_up_reminder:'
      ||
      pg_catalog.md5(
        task_record.id::text
        || '|'
        || task_record.assigned_to::text
        || '|'
        || extract(
          epoch from task_record.reminder_at
        )::text
        || '|'
        || extract(
          epoch from task_record.due_at
        )::text
      );

    select *
    into notification_job_record
    from public.create_notification_job(
      requested_organization_id =>
        task_record.organization_id,

      requested_category_code =>
        'followup_due',

      requested_title =>
        'Follow-up due: '
        || task_record.title,

      requested_body =>
        'Follow-up "'
        || task_record.title
        || '" is due on '
        || pg_catalog.to_char(
          task_record.due_at
            at time zone 'Asia/Kolkata',
          'DD Mon YYYY, HH12:MI AM'
        )
        || ' IST.',

      requested_recipient_user_ids =>
        array[
          task_record.assigned_to
        ]::uuid[],

      requested_channel_codes =>
        array[
          'in_app'
        ]::text[],

      requested_variables =>
        jsonb_build_object(
          'follow_up_task_id',
          task_record.id,

          'lead_id',
          task_record.lead_id,

          'follow_up_type',
          task_record.follow_up_type,

          'status',
          task_record.status,

          'reminder_at',
          task_record.reminder_at,

          'due_at',
          task_record.due_at
        ),

      requested_deep_link =>
        '/dashboard/leads/'
        || task_record.lead_id::text,

      requested_severity =>
        'warning',

      requested_priority =>
        30,

      requested_event_name =>
        'follow_up.reminder.due',

      requested_source_module =>
        'leads',

      requested_source_type =>
        'follow_up_task',

      requested_source_id =>
        task_record.id,

      requested_source_reference =>
        task_record.id::text,

      requested_idempotency_key =>
        reminder_idempotency_key
    );

    select
      public.expand_notification_recipients(
        notification_job_record.id
      )
    into expanded_attempt_count;

    created_delivery_attempt_count :=
      created_delivery_attempt_count
      +
      coalesce(
        expanded_attempt_count,
        0
      );

    in_app_attempt_id := null;

    select attempt.id
    into in_app_attempt_id
    from public.notification_delivery_attempts
      as attempt
    where attempt.notification_job_id =
        notification_job_record.id
      and attempt.channel_code =
        'in_app'
    order by
      attempt.attempt_number desc,
      attempt.created_at desc
    limit 1;

    if in_app_attempt_id is not null then

      perform
        public.update_notification_delivery_status(
          in_app_attempt_id,
          'delivered',
          null,
          'delivered',
          jsonb_build_object(
            'delivery_channel',
            'in_app',

            'delivery_source',
            'follow_up_reminder_processor'
          ),
          null,
          null,
          '{}'::jsonb
        );

    end if;

    update public.follow_up_tasks
    set
      reminder_sent_at =
        processing_time,

      updated_by =
        caller_user_id,

      metadata =
        coalesce(
          metadata,
          '{}'::jsonb
        )
        ||
        jsonb_build_object(
          'last_reminder_processing_at',
          processing_time,

          'last_reminder_processing_source',
          'system',

          'last_reminder_processed_by',
          caller_user_id,

          'last_reminder_notification_job_id',
          notification_job_record.id,

          'last_reminder_recipient_user_id',
          task_record.assigned_to,

          'last_reminder_idempotency_key',
          reminder_idempotency_key
        ),

      updated_at =
        processing_time
    where id =
      task_record.id
      and reminder_sent_at is null;

    get diagnostics
      updated_row_count = row_count;

    if updated_row_count = 1 then
      processed_task_count :=
        processed_task_count + 1;

      created_notification_count :=
        created_notification_count + 1;
    end if;
  end loop;

  select count(*)
  into pending_reminder_count
  from public.follow_up_tasks
    as task
  where task.deleted_at is null
    and task.reminder_at is not null
    and task.reminder_sent_at is null
    and task.assigned_to is not null
    and task.reminder_at <=
      processing_time
    and task.status in (
      'pending',
      'in_progress',
      'rescheduled',
      'overdue'
    )
    and (
      requested_organization_id
        is null
      or task.organization_id =
        requested_organization_id
    );

  select count(*)
  into pending_unassigned_count
  from public.follow_up_tasks
    as task
  where task.deleted_at is null
    and task.reminder_at is not null
    and task.reminder_sent_at is null
    and task.assigned_to is null
    and task.reminder_at <=
      processing_time
    and task.status in (
      'pending',
      'in_progress',
      'rescheduled',
      'overdue'
    )
    and (
      requested_organization_id
        is null
      or task.organization_id =
        requested_organization_id
    );

  return query
  select
    processed_task_count,
    created_notification_count,
    created_delivery_attempt_count,
    pending_reminder_count,
    pending_unassigned_count,
    processing_time;
end;
$function$;

comment on function
  public.process_due_follow_up_reminders(
    uuid,
    integer
  )
is
  'Creates and expands idempotent in-app notification jobs for due follow-up reminders in bounded, concurrency-safe batches. Execution is restricted to service_role.';

revoke all
on function
  public.process_due_follow_up_reminders(
    uuid,
    integer
  )
from public;

revoke all
on function
  public.process_due_follow_up_reminders(
    uuid,
    integer
  )
from anon;

revoke all
on function
  public.process_due_follow_up_reminders(
    uuid,
    integer
  )
from authenticated;

grant execute
on function
  public.process_due_follow_up_reminders(
    uuid,
    integer
  )
to service_role;

-- ============================================================
-- 6. MIGRATION VERIFICATION
-- ============================================================

do $verification$
declare
  processor_oid oid :=
    to_regprocedure(
      'public.process_due_follow_up_reminders(uuid,integer)'
    );

  processor_source text;
begin
  if processor_oid is null then

    raise exception
      'Migration verification failed: reminder processor was not created';

  end if;

  select procedure.prosrc
  into processor_source
  from pg_proc
    as procedure
  where procedure.oid =
    processor_oid;

  if not exists (
    select 1
    from pg_proc
      as procedure
    where procedure.oid =
        processor_oid
      and procedure.prosecdef
  ) then

    raise exception
      'Migration verification failed: reminder processor is not SECURITY DEFINER';

  end if;

  if not exists (
    select 1
    from pg_proc
      as procedure,
      unnest(
        procedure.proconfig
      ) as configuration
    where procedure.oid =
        processor_oid
      and configuration =
        'search_path=""'
  ) then

    raise exception
      'Migration verification failed: reminder processor search_path is not empty';

  end if;

  if position(
    'skip locked'
    in lower(
      processor_source
    )
  ) = 0 then

    raise exception
      'Migration verification failed: SKIP LOCKED protection is missing';

  end if;

  if position(
    'create_notification_job'
    in lower(
      processor_source
    )
  ) = 0 then

    raise exception
      'Migration verification failed: Notification Engine job creation is missing';

  end if;

  if position(
    'expand_notification_recipients'
    in lower(
      processor_source
    )
  ) = 0 then

    raise exception
      'Migration verification failed: notification recipient expansion is missing';

  end if;

  if position(
    'update_notification_delivery_status'
    in lower(
      processor_source
    )
  ) = 0 then

    raise exception
      'Migration verification failed: in-app delivery aggregation is missing';

  end if;

  if has_function_privilege(
    'anon',
    processor_oid,
    'EXECUTE'
  ) then

    raise exception
      'Migration verification failed: anon may execute reminder processor';

  end if;

  if has_function_privilege(
    'authenticated',
    processor_oid,
    'EXECUTE'
  ) then

    raise exception
      'Migration verification failed: authenticated may execute reminder processor';

  end if;

  if not has_function_privilege(
    'service_role',
    processor_oid,
    'EXECUTE'
  ) then

    raise exception
      'Migration verification failed: service_role cannot execute reminder processor';

  end if;

  if to_regprocedure(
    'public.create_notification_job(uuid,text,text,text,uuid[],text[],uuid,jsonb,jsonb,text,text,text,integer,text,text,text,uuid,text,text,text,text,timestamptz,timestamptz)'
  ) is null then

    raise exception
      'Migration verification failed: create_notification_job dependency is missing';

  end if;

  if to_regprocedure(
    'public.expand_notification_recipients(uuid)'
  ) is null then

    raise exception
      'Migration verification failed: expand_notification_recipients dependency is missing';

  end if;

  if to_regprocedure(
    'public.update_notification_delivery_status(uuid,text,text,text,jsonb,text,text,jsonb)'
  ) is null then

    raise exception
      'Migration verification failed: update_notification_delivery_status dependency is missing';

  end if;

  if not exists (
    select 1
    from public.notification_categories
    where category_code =
        'followup_due'
      and organization_id is null
      and status =
        'active'
  ) then

    raise exception
      'Migration verification failed: active followup_due category is missing';

  end if;

  if to_regclass(
    'public.follow_up_tasks_reminder_processing_idx'
  ) is null then

    raise exception
      'Migration verification failed: global reminder processing index is missing';

  end if;

  if to_regclass(
    'public.follow_up_tasks_org_reminder_processing_idx'
  ) is null then

    raise exception
      'Migration verification failed: organization reminder processing index is missing';

  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid =
        'public.follow_up_tasks'::regclass
      and tgname =
        '01_follow_up_tasks_guard_reminder_delivery'
      and not tgisinternal
  ) then

    raise exception
      'Migration verification failed: reminder delivery guard trigger is missing';

  end if;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid =
        'public.follow_up_tasks'::regclass
      and tgname =
        '05_follow_up_tasks_reset_reminder_delivery'
      and not tgisinternal
  ) then

    raise exception
      'Migration verification failed: reminder reset trigger is missing';

  end if;
end;
$verification$;

commit;
