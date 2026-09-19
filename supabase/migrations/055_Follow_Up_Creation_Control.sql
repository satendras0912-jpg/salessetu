-- 055_Follow_Up_Creation_Control.sql
--
-- Purpose:
--   Harden follow-up creation with:
--   - organization permission validation
--   - lead/organization integrity protection
--   - active-assignee validation
--   - server-side input validation
--   - assignment permission enforcement
--   - trusted audit fields
--   - strict RPC execution grants
-- ============================================================

begin;

-- ============================================================
-- 1. DIRECT-INSERT CREATION INTEGRITY GUARD
-- ============================================================

create or replace function
  public.guard_follow_up_creation_fields()
returns trigger
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  clean_title text;
  clean_description text;
  caller_is_privileged boolean;
begin
  if new.organization_id is null then
    raise exception
      'A valid organization ID is required'
      using errcode = '22023';
  end if;

  if new.lead_id is null then
    raise exception
      'A valid lead ID is required'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.leads lead_row
    where lead_row.id = new.lead_id
      and lead_row.organization_id =
        new.organization_id
      and lead_row.deleted_at is null
  ) then
    raise exception
      'Lead not found in the requested organization'
      using errcode = 'P0002';
  end if;

  clean_title :=
    regexp_replace(
      btrim(new.title),
      '[[:space:]]+',
      ' ',
      'g'
    );

  if clean_title is null
    or clean_title = '' then
    raise exception
      'A follow-up title is required'
      using errcode = '23514';
  end if;

  if char_length(clean_title) > 200 then
    raise exception
      'Follow-up title must not exceed 200 characters'
      using errcode = '23514';
  end if;

  clean_description :=
    nullif(
      btrim(new.description),
      ''
    );

  if clean_description is not null
    and char_length(clean_description) > 1000 then
    raise exception
      'Follow-up description must not exceed 1000 characters'
      using errcode = '23514';
  end if;

  if new.follow_up_type is null
    or new.follow_up_type not in (
      'call',
      'whatsapp',
      'email',
      'sms',
      'meeting',
      'site_visit',
      'document',
      'payment',
      'general',
      'other'
    ) then
    raise exception
      'Invalid follow-up type'
      using errcode = '23514';
  end if;

  if new.priority is null
    or new.priority not in (
      'low',
      'normal',
      'high',
      'urgent'
    ) then
    raise exception
      'Invalid follow-up priority'
      using errcode = '23514';
  end if;

  if new.due_at is null then
    raise exception
      'A valid follow-up due date and time is required'
      using errcode = '23514';
  end if;

  if new.reminder_at is not null
    and new.reminder_at > new.due_at then
    raise exception
      'The reminder must be scheduled on or before the follow-up due time'
      using errcode = '23514';
  end if;

  if new.assigned_to is not null
    and not exists (
      select 1
      from public.organization_members member_row
      where member_row.organization_id =
        new.organization_id
        and member_row.user_id =
          new.assigned_to
        and member_row.membership_status =
          'active'
    ) then
    raise exception
      'The selected assignee is not an active organization member'
      using errcode = '23503';
  end if;

  caller_is_privileged :=
    current_user in (
      'postgres',
      'service_role',
      'supabase_admin'
    )
    or coalesce(
      auth.role(),
      ''
    ) = 'service_role';

  if not caller_is_privileged then
    if not public.has_organization_permission(
      new.organization_id,
      'followups.create'
    ) then
      raise exception
        'followups.create permission is required'
        using errcode = '42501';
    end if;

    if new.status is distinct from 'pending' then
      raise exception
        'New follow-up task status must be pending'
        using errcode = '23514';
    end if;

    if new.assigned_to is not null
      and new.assigned_to
        is distinct from auth.uid()
      and not public.has_organization_permission(
        new.organization_id,
        'followups.assign'
      ) then
      raise exception
        'followups.assign permission is required'
        using errcode = '42501';
    end if;

    if new.assigned_by is not null
      or new.assigned_at is not null then
      raise exception
        'Follow-up assignment audit fields are system managed'
        using errcode = '23514';
    end if;

    if new.started_at is not null
      or new.completed_at is not null
      or new.cancelled_at is not null
      or new.completion_outcome is not null
      or new.completion_notes is not null
      or new.deleted_at is not null
      or new.deleted_by is not null then
      raise exception
        'Follow-up lifecycle fields cannot be supplied during creation'
        using errcode = '23514';
    end if;

    new.created_by := auth.uid();
    new.updated_by := auth.uid();
  end if;

  new.title := clean_title;
  new.description := clean_description;

  return new;
end;
$function$;

comment on function
  public.guard_follow_up_creation_fields()
is
  'Validates follow-up creation integrity for direct table inserts.';

revoke all on function
  public.guard_follow_up_creation_fields()
from public, anon, authenticated;

drop trigger if exists
  "00_follow_up_tasks_guard_creation_fields"
on public.follow_up_tasks;

create trigger
  "00_follow_up_tasks_guard_creation_fields"
before insert on public.follow_up_tasks
for each row
execute function
  public.guard_follow_up_creation_fields();

-- ============================================================
-- 2. SAFE FOLLOW-UP CREATION RPC
-- ============================================================

create or replace function
  public.create_follow_up_task(
    requested_lead_id uuid,
    requested_title text,
    requested_description text,
    requested_follow_up_type text,
    requested_priority text,
    requested_assigned_to uuid,
    requested_due_at timestamptz,
    requested_reminder_at timestamptz
  )
returns public.follow_up_tasks
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_lead public.leads;
  created_task public.follow_up_tasks;
  clean_title text;
  clean_description text;
begin
  if requested_lead_id is null then
    raise exception
      'A valid lead ID is required'
      using errcode = '22023';
  end if;

  clean_title :=
    regexp_replace(
      btrim(requested_title),
      '[[:space:]]+',
      ' ',
      'g'
    );

  if clean_title is null
    or clean_title = '' then
    raise exception
      'A follow-up title is required'
      using errcode = '23514';
  end if;

  if char_length(clean_title) > 200 then
    raise exception
      'Follow-up title must not exceed 200 characters'
      using errcode = '23514';
  end if;

  clean_description :=
    nullif(
      btrim(requested_description),
      ''
    );

  if clean_description is not null
    and char_length(clean_description) > 1000 then
    raise exception
      'Follow-up description must not exceed 1000 characters'
      using errcode = '23514';
  end if;

  if requested_follow_up_type is null
    or requested_follow_up_type not in (
      'call',
      'whatsapp',
      'email',
      'sms',
      'meeting',
      'site_visit',
      'document',
      'payment',
      'general',
      'other'
    ) then
    raise exception
      'Invalid follow-up type'
      using errcode = '23514';
  end if;

  if requested_priority is null
    or requested_priority not in (
      'low',
      'normal',
      'high',
      'urgent'
    ) then
    raise exception
      'Invalid follow-up priority'
      using errcode = '23514';
  end if;

  if requested_due_at is null then
    raise exception
      'A valid follow-up due date and time is required'
      using errcode = '23514';
  end if;

  if requested_reminder_at is not null
    and requested_reminder_at >
      requested_due_at then
    raise exception
      'The reminder must be scheduled on or before the follow-up due time'
      using errcode = '23514';
  end if;

  select *
  into target_lead
  from public.leads
  where id = requested_lead_id
    and deleted_at is null
  for share;

  if not found then
    raise exception
      'Lead not found'
      using errcode = 'P0002';
  end if;

  if coalesce(
    auth.role(),
    ''
  ) <> 'service_role'
    and not public.has_organization_permission(
      target_lead.organization_id,
      'followups.create'
    ) then
    raise exception
      'followups.create permission is required'
      using errcode = '42501';
  end if;

  if requested_assigned_to is not null
    and not exists (
      select 1
      from public.organization_members member_row
      where member_row.organization_id =
        target_lead.organization_id
        and member_row.user_id =
          requested_assigned_to
        and member_row.membership_status =
          'active'
    ) then
    raise exception
      'The selected assignee is not an active organization member'
      using errcode = '23503';
  end if;

  if coalesce(
    auth.role(),
    ''
  ) <> 'service_role'
    and requested_assigned_to is not null
    and requested_assigned_to
      is distinct from auth.uid()
    and not public.has_organization_permission(
      target_lead.organization_id,
      'followups.assign'
    ) then
    raise exception
      'followups.assign permission is required'
      using errcode = '42501';
  end if;

  insert into public.follow_up_tasks (
    organization_id,
    lead_id,
    title,
    description,
    follow_up_type,
    status,
    priority,
    assigned_to,
    due_at,
    reminder_at,
    created_by,
    updated_by
  )
  values (
    target_lead.organization_id,
    target_lead.id,
    clean_title,
    clean_description,
    requested_follow_up_type,
    'pending',
    requested_priority,
    requested_assigned_to,
    requested_due_at,
    requested_reminder_at,
    auth.uid(),
    auth.uid()
  )
  returning *
  into created_task;

  return created_task;
end;
$function$;

comment on function
  public.create_follow_up_task(
    uuid,
    text,
    text,
    text,
    text,
    uuid,
    timestamptz,
    timestamptz
  )
is
  'Securely creates a validated follow-up task for an active lead.';

revoke all on function
  public.create_follow_up_task(
    uuid,
    text,
    text,
    text,
    text,
    uuid,
    timestamptz,
    timestamptz
  )
from public, anon, authenticated;

grant execute on function
  public.create_follow_up_task(
    uuid,
    text,
    text,
    text,
    text,
    uuid,
    timestamptz,
    timestamptz
  )
to authenticated, service_role;

-- ============================================================
-- 3. DEPLOYMENT VERIFICATION
-- ============================================================

do $verification$
declare
  rpc_definition text;
  rpc_config text[];
  rpc_security_definer boolean;
  rpc_default_count integer;

  guard_definition text;
  guard_config text[];

  creation_trigger_count integer;
begin
  if to_regprocedure(
    'public.create_follow_up_task(uuid,text,text,text,text,uuid,timestamptz,timestamptz)'
  ) is null then
    raise exception
      'Migration 055 verification failed: create_follow_up_task was not created';
  end if;

  if to_regprocedure(
    'public.guard_follow_up_creation_fields()'
  ) is null then
    raise exception
      'Migration 055 verification failed: creation guard was not created';
  end if;

  select
    pg_get_functiondef(function_row.oid),
    function_row.proconfig,
    function_row.prosecdef,
    function_row.pronargdefaults
  into
    rpc_definition,
    rpc_config,
    rpc_security_definer,
    rpc_default_count
  from pg_proc function_row
  where function_row.oid =
    'public.create_follow_up_task(uuid,text,text,text,text,uuid,timestamptz,timestamptz)'::regprocedure;

  if not rpc_security_definer then
    raise exception
      'Migration 055 verification failed: create RPC is not security definer';
  end if;

  if rpc_config is null
    or not exists (
      select 1
      from unnest(rpc_config) config_value
      where config_value like 'search_path=%'
    ) then
    raise exception
      'Migration 055 verification failed: create RPC search_path is not fixed';
  end if;

  if rpc_default_count <> 0 then
    raise exception
      'Migration 055 verification failed: unexpected RPC parameter defaults were found';
  end if;

  if position(
    'followups.create'
    in rpc_definition
  ) = 0 then
    raise exception
      'Migration 055 verification failed: create permission guard was not found';
  end if;

  if position(
    'followups.assign'
    in rpc_definition
  ) = 0 then
    raise exception
      'Migration 055 verification failed: assign permission guard was not found';
  end if;

  if position(
    'membership_status'
    in rpc_definition
  ) = 0 then
    raise exception
      'Migration 055 verification failed: active-member guard was not found';
  end if;

  if position(
    'char_length(clean_title) > 200'
    in rpc_definition
  ) = 0 then
    raise exception
      'Migration 055 verification failed: title limit was not found';
  end if;

  if position(
    'char_length(clean_description) > 1000'
    in rpc_definition
  ) = 0 then
    raise exception
      'Migration 055 verification failed: description limit was not found';
  end if;

  if position(
    'requested_reminder_at >'
    in rpc_definition
  ) = 0 then
    raise exception
      'Migration 055 verification failed: reminder timing guard was not found';
  end if;

  if position(
    'for share'
in lower(rpc_definition)
  ) = 0 then
    raise exception
      'Migration 055 verification failed: lead row lock was not found';
  end if;

  if position(
    'insert into public.follow_up_tasks'
in lower(rpc_definition)
  ) = 0 then
    raise exception
      'Migration 055 verification failed: trusted follow-up insert was not found';
  end if;

  select
    pg_get_functiondef(function_row.oid),
    function_row.proconfig
  into
    guard_definition,
    guard_config
  from pg_proc function_row
  where function_row.oid =
    'public.guard_follow_up_creation_fields()'::regprocedure;

  if guard_config is null
    or not exists (
      select 1
      from unnest(guard_config) config_value
      where config_value like 'search_path=%'
    ) then
    raise exception
      'Migration 055 verification failed: creation guard search_path is not fixed';
  end if;

  if position(
    'lead_row.organization_id = new.organization_id'
    in regexp_replace(
  guard_definition,
  '[[:space:]]+',
  ' ',
  'g'
)
  ) = 0 then
    raise exception
      'Migration 055 verification failed: lead organization guard was not found';
  end if;

  if position(
    'Follow-up assignment audit fields are system managed'
    in guard_definition
  ) = 0 then
    raise exception
      'Migration 055 verification failed: audit-field guard was not found';
  end if;

  select count(*)
  into creation_trigger_count
  from pg_trigger trigger_row
  where trigger_row.tgrelid =
    'public.follow_up_tasks'::regclass
    and trigger_row.tgname =
      '00_follow_up_tasks_guard_creation_fields'
    and not trigger_row.tgisinternal;

  if creation_trigger_count <> 1 then
    raise exception
      'Migration 055 verification failed: creation guard trigger is missing';
  end if;

  if has_function_privilege(
    'anon',
    'public.create_follow_up_task(uuid,text,text,text,text,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 055 verification failed: anon can execute create_follow_up_task';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.create_follow_up_task(uuid,text,text,text,text,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 055 verification failed: authenticated cannot execute create_follow_up_task';
  end if;

  if not has_function_privilege(
    'service_role',
    'public.create_follow_up_task(uuid,text,text,text,text,uuid,timestamptz,timestamptz)',
    'EXECUTE'
  ) then
    raise exception
      'Migration 055 verification failed: service_role cannot execute create_follow_up_task';
  end if;

  if has_function_privilege(
    'anon',
    'public.guard_follow_up_creation_fields()',
    'EXECUTE'
  ) then
    raise exception
      'Migration 055 verification failed: anon can execute the creation guard';
  end if;
end;
$verification$;

commit;
