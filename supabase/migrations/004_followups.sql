-- =========================================================
-- SalesSetu Enterprise
-- Migration: 004_followups
-- Purpose: Follow-up, activity and communication foundation
-- =========================================================

begin;

-- =========================================================
-- 1. FOLLOW-UP PERMISSIONS
-- =========================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
values
  (
    'followups',
    'view',
    'followups.view',
    'View follow-ups and sales activities'
  ),
  (
    'followups',
    'create',
    'followups.create',
    'Create follow-ups and activities'
  ),
  (
    'followups',
    'update',
    'followups.update',
    'Update follow-ups and activities'
  ),
  (
    'followups',
    'complete',
    'followups.complete',
    'Complete follow-up tasks'
  ),
  (
    'followups',
    'assign',
    'followups.assign',
    'Assign follow-ups to organization members'
  ),
  (
    'followups',
    'delete',
    'followups.delete',
    'Delete follow-up records'
  ),
  (
    'followups',
    'manage_sla',
    'followups.manage_sla',
    'Manage follow-up SLA and escalation rules'
  )
on conflict (code) do nothing;

-- Platform and organization administrators get all
-- follow-up permissions.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
cross join public.permissions p
where r.code in (
  'platform_admin',
  'organization_admin'
)
and p.module = 'followups'
on conflict (role_id, permission_id) do nothing;

-- Sales managers get all operational follow-up permissions.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'followups.view',
    'followups.create',
    'followups.update',
    'followups.complete',
    'followups.assign',
    'followups.delete',
    'followups.manage_sla'
  )
where r.code = 'sales_manager'
on conflict (role_id, permission_id) do nothing;

-- Sales agents can manage their normal follow-up work.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'followups.view',
    'followups.create',
    'followups.update',
    'followups.complete'
  )
where r.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;

-- Customer success users receive operational permissions.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'followups.view',
    'followups.create',
    'followups.update',
    'followups.complete'
  )
where r.code = 'customer_success'
on conflict (role_id, permission_id) do nothing;

-- Viewer receives read-only access.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code = 'followups.view'
where r.code = 'viewer'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- 2. LEAD ACTIVITIES
-- Unified timeline of calls, messages, notes, meetings,
-- tasks and automated interactions.
-- =========================================================

create table public.lead_activities (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  activity_type text not null
    check (
      activity_type in (
        'call',
        'whatsapp',
        'email',
        'sms',
        'meeting',
        'site_visit',
        'note',
        'task',
        'status_change',
        'assignment',
        'ai_call',
        'system_event',
        'other'
      )
    ),

  direction text
    check (
      direction is null
      or direction in (
        'inbound',
        'outbound',
        'internal'
      )
    ),

  activity_status text not null default 'completed'
    check (
      activity_status in (
        'scheduled',
        'in_progress',
        'completed',
        'failed',
        'cancelled',
        'no_response',
        'missed'
      )
    ),

  subject text,
  description text,

  outcome text,
  outcome_code text,

  channel_provider text,
  external_activity_id text,

  duration_seconds integer
    check (
      duration_seconds is null
      or duration_seconds >= 0
    ),

  started_at timestamptz,
  completed_at timestamptz,

  performed_by uuid
    references auth.users(id)
    on delete set null,

  is_automated boolean not null default false,

  ai_generated boolean not null default false,
  ai_summary text,
  ai_sentiment text
    check (
      ai_sentiment is null
      or ai_sentiment in (
        'positive',
        'neutral',
        'negative',
        'unknown'
      )
    ),

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint lead_activities_time_valid
    check (
      started_at is null
      or completed_at is null
      or completed_at >= started_at
    )
);

create index lead_activities_organization_idx
  on public.lead_activities(organization_id);

create index lead_activities_lead_idx
  on public.lead_activities(
    lead_id,
    created_at desc
  );

create index lead_activities_type_idx
  on public.lead_activities(
    organization_id,
    activity_type,
    created_at desc
  );

create index lead_activities_performed_by_idx
  on public.lead_activities(
    organization_id,
    performed_by,
    created_at desc
  );

create index lead_activities_external_idx
  on public.lead_activities(
    organization_id,
    channel_provider,
    external_activity_id
  )
  where external_activity_id is not null;

create trigger lead_activities_set_updated_at
before update on public.lead_activities
for each row
execute function public.set_updated_at();

-- =========================================================
-- 3. FOLLOW-UP TASKS
-- =========================================================

create table public.follow_up_tasks (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  related_activity_id uuid
    references public.lead_activities(id)
    on delete set null,

  title text not null,
  description text,

  follow_up_type text not null
    check (
      follow_up_type in (
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
      )
    ),

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'in_progress',
        'completed',
        'cancelled',
        'overdue',
        'rescheduled',
        'failed'
      )
    ),

  priority text not null default 'normal'
    check (
      priority in (
        'low',
        'normal',
        'high',
        'urgent'
      )
    ),

  assigned_to uuid
    references auth.users(id)
    on delete set null,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz,

  due_at timestamptz not null,

  reminder_at timestamptz,

  reminder_sent_at timestamptz,

  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,

  completion_outcome text,
  completion_notes text,

  attempt_count integer not null default 0
    check (attempt_count >= 0),

  max_attempts integer
    check (
      max_attempts is null
      or max_attempts > 0
    ),

  next_retry_at timestamptz,

  is_automated boolean not null default false,

  automation_workflow_id text,

  sla_due_at timestamptz,

  sla_status text not null default 'not_applicable'
    check (
      sla_status in (
        'not_applicable',
        'within_sla',
        'at_risk',
        'breached',
        'resolved'
      )
    ),

  escalation_level integer not null default 0
    check (escalation_level >= 0),

  escalated_at timestamptz,

  escalated_to uuid
    references auth.users(id)
    on delete set null,

  recurrence_rule text,

  parent_task_id uuid
    references public.follow_up_tasks(id)
    on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  deleted_by uuid
    references auth.users(id)
    on delete set null,

  deleted_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint follow_up_tasks_completion_time_valid
    check (
      started_at is null
      or completed_at is null
      or completed_at >= started_at
    ),

  constraint follow_up_tasks_reminder_valid
    check (
      reminder_at is null
      or reminder_at <= due_at
    ),

  constraint follow_up_tasks_not_parent_of_self
    check (
      parent_task_id is null
      or parent_task_id <> id
    )
);

create index follow_up_tasks_organization_idx
  on public.follow_up_tasks(organization_id);

create index follow_up_tasks_lead_idx
  on public.follow_up_tasks(
    lead_id,
    due_at
  );

create index follow_up_tasks_assignee_idx
  on public.follow_up_tasks(
    organization_id,
    assigned_to,
    status,
    due_at
  )
  where deleted_at is null;

create index follow_up_tasks_due_idx
  on public.follow_up_tasks(
    organization_id,
    due_at
  )
  where status in (
    'pending',
    'in_progress',
    'rescheduled'
  )
  and deleted_at is null;

create index follow_up_tasks_reminder_idx
  on public.follow_up_tasks(reminder_at)
  where reminder_sent_at is null
    and status in (
      'pending',
      'in_progress',
      'rescheduled'
    )
    and deleted_at is null;

create index follow_up_tasks_sla_idx
  on public.follow_up_tasks(
    organization_id,
    sla_status,
    sla_due_at
  )
  where deleted_at is null;

create index follow_up_tasks_parent_idx
  on public.follow_up_tasks(parent_task_id)
  where parent_task_id is not null;

create trigger follow_up_tasks_set_updated_at
before update on public.follow_up_tasks
for each row
execute function public.set_updated_at();

-- =========================================================
-- 4. FOLLOW-UP STATUS HISTORY
-- =========================================================

create table public.follow_up_status_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  follow_up_task_id uuid not null
    references public.follow_up_tasks(id)
    on delete cascade,

  previous_status text,

  new_status text not null,

  previous_assignee_id uuid
    references auth.users(id)
    on delete set null,

  new_assignee_id uuid
    references auth.users(id)
    on delete set null,

  change_reason text,

  changed_by uuid
    references auth.users(id)
    on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  changed_at timestamptz not null default now()
);

create index follow_up_status_history_org_idx
  on public.follow_up_status_history(organization_id);

create index follow_up_status_history_task_idx
  on public.follow_up_status_history(
    follow_up_task_id,
    changed_at desc
  );

-- =========================================================
-- 5. VALIDATE LEAD ORGANIZATION
-- =========================================================

create or replace function public.validate_follow_up_lead()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.leads l
    where l.id = new.lead_id
      and l.organization_id = new.organization_id
      and l.deleted_at is null
  ) then
    raise exception
      'Lead must belong to the follow-up organization';
  end if;

  return new;
end;
$$;

create trigger follow_up_tasks_validate_lead
before insert or update of
  organization_id,
  lead_id
on public.follow_up_tasks
for each row
execute function public.validate_follow_up_lead();

create trigger lead_activities_validate_lead
before insert or update of
  organization_id,
  lead_id
on public.lead_activities
for each row
execute function public.validate_follow_up_lead();

-- =========================================================
-- 6. VALIDATE ASSIGNED USERS
-- =========================================================

create or replace function public.validate_follow_up_assignees()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.assigned_to is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.assigned_to
        and om.membership_status = 'active'
    ) then

    raise exception
      'Assigned user must be an active organization member';

  end if;

  if new.escalated_to is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.escalated_to
        and om.membership_status = 'active'
    ) then

    raise exception
      'Escalation user must be an active organization member';

  end if;

  return new;
end;
$$;

create trigger follow_up_tasks_validate_assignees
before insert or update of
  organization_id,
  assigned_to,
  escalated_to
on public.follow_up_tasks
for each row
execute function public.validate_follow_up_assignees();

-- =========================================================
-- 7. AUTOMATIC ASSIGNMENT AND STATUS FIELDS
-- =========================================================

create or replace function public.set_follow_up_system_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    if new.assigned_to is not null then
      new.assigned_at :=
        coalesce(new.assigned_at, now());

      new.assigned_by :=
        coalesce(new.assigned_by, auth.uid());
    end if;

    if new.status = 'completed' then
      new.completed_at :=
        coalesce(new.completed_at, now());
    end if;

    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to then
    new.assigned_at :=
      case
        when new.assigned_to is null
          then null
        else now()
      end;

    new.assigned_by :=
      coalesce(new.assigned_by, auth.uid());
  end if;

  if new.status is distinct from old.status then

    if new.status = 'in_progress'
      and new.started_at is null then
      new.started_at = now();
    end if;

    if new.status = 'completed' then
      new.completed_at =
        coalesce(new.completed_at, now());

      new.sla_status =
        case
          when new.sla_due_at is null
            then 'not_applicable'
          when now() <= new.sla_due_at
            then 'resolved'
          else 'breached'
        end;
    end if;

    if new.status = 'cancelled' then
      new.cancelled_at =
        coalesce(new.cancelled_at, now());
    end if;

  end if;

  return new;
end;
$$;

create trigger follow_up_tasks_set_system_fields
before insert or update of
  assigned_to,
  status
on public.follow_up_tasks
for each row
execute function public.set_follow_up_system_fields();

-- =========================================================
-- 8. ENABLE RLS
-- Policies will be added in Part 2.
-- =========================================================

alter table public.lead_activities
  enable row level security;

alter table public.follow_up_tasks
  enable row level security;

alter table public.follow_up_status_history
  enable row level security;

  -- =========================================================
-- 9. VALIDATE RELATED ACTIVITY AND PARENT TASK
-- =========================================================

create or replace function public.validate_follow_up_relations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.related_activity_id is not null
    and not exists (
      select 1
      from public.lead_activities la
      where la.id = new.related_activity_id
        and la.organization_id = new.organization_id
        and la.lead_id = new.lead_id
    ) then

    raise exception
      'Related activity must belong to the same organization and lead';

  end if;

  if new.parent_task_id is not null
    and not exists (
      select 1
      from public.follow_up_tasks ft
      where ft.id = new.parent_task_id
        and ft.organization_id = new.organization_id
        and ft.lead_id = new.lead_id
        and ft.deleted_at is null
    ) then

    raise exception
      'Parent task must belong to the same organization and lead';

  end if;

  return new;
end;
$$;

create trigger follow_up_tasks_validate_relations
before insert or update of
  organization_id,
  lead_id,
  related_activity_id,
  parent_task_id
on public.follow_up_tasks
for each row
execute function public.validate_follow_up_relations();

-- =========================================================
-- 10. FOLLOW-UP STATUS HISTORY TRIGGER
-- =========================================================

create or replace function public.record_follow_up_status_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    insert into public.follow_up_status_history (
      organization_id,
      follow_up_task_id,
      previous_status,
      new_status,
      previous_assignee_id,
      new_assignee_id,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      null,
      new.status,
      null,
      new.assigned_to,
      coalesce(new.created_by, auth.uid())
    );

    return new;
  end if;

  if new.status is distinct from old.status
    or new.assigned_to is distinct from old.assigned_to then

    insert into public.follow_up_status_history (
      organization_id,
      follow_up_task_id,
      previous_status,
      new_status,
      previous_assignee_id,
      new_assignee_id,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      old.status,
      new.status,
      old.assigned_to,
      new.assigned_to,
      coalesce(new.updated_by, auth.uid())
    );

  end if;

  return new;
end;
$$;

create trigger follow_up_tasks_record_status_history
after insert or update of
  status,
  assigned_to
on public.follow_up_tasks
for each row
execute function public.record_follow_up_status_history();

-- =========================================================
-- 11. CREATE ACTIVITY WHEN FOLLOW-UP IS COMPLETED
-- =========================================================

create or replace function public.create_follow_up_completion_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_activity_type text;
begin
  if tg_op <> 'UPDATE' then
    return new;
  end if;

  if new.status = 'completed'
    and old.status is distinct from 'completed' then

    generated_activity_type :=
      case new.follow_up_type
        when 'call' then 'call'
        when 'whatsapp' then 'whatsapp'
        when 'email' then 'email'
        when 'sms' then 'sms'
        when 'meeting' then 'meeting'
        when 'site_visit' then 'site_visit'
        else 'task'
      end;

    insert into public.lead_activities (
      organization_id,
      lead_id,
      activity_type,
      direction,
      activity_status,
      subject,
      description,
      outcome,
      started_at,
      completed_at,
      performed_by,
      is_automated,
      metadata,
      created_by
    )
    values (
      new.organization_id,
      new.lead_id,
      generated_activity_type,
      case
        when generated_activity_type in (
          'call',
          'whatsapp',
          'email',
          'sms'
        )
          then 'outbound'
        else 'internal'
      end,
      'completed',
      new.title,
      new.description,
      new.completion_outcome,
      new.started_at,
      coalesce(new.completed_at, now()),
      new.assigned_to,
      new.is_automated,
      jsonb_build_object(
        'follow_up_task_id',
        new.id,
        'completion_notes',
        new.completion_notes
      ),
      coalesce(new.updated_by, auth.uid())
    );

  end if;

  return new;
end;
$$;

create trigger follow_up_tasks_create_completion_activity
after update of status
on public.follow_up_tasks
for each row
execute function public.create_follow_up_completion_activity();

-- =========================================================
-- 12. SYNC LEAD CONTACT TIMESTAMPS
-- =========================================================

create or replace function public.sync_lead_contact_from_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.activity_type not in (
    'call',
    'whatsapp',
    'email',
    'sms',
    'meeting',
    'ai_call'
  ) then
    return new;
  end if;

  if new.activity_status <> 'completed' then
    return new;
  end if;

  update public.leads
  set
    first_contacted_at = coalesce(
      first_contacted_at,
      new.completed_at,
      new.started_at,
      new.created_at
    ),
    last_contacted_at = greatest(
      coalesce(
        last_contacted_at,
        '-infinity'::timestamptz
      ),
      coalesce(
        new.completed_at,
        new.started_at,
        new.created_at
      )
    ),
    updated_at = now()
  where id = new.lead_id
    and organization_id = new.organization_id
    and deleted_at is null;

  return new;
end;
$$;

create trigger lead_activities_sync_contact_timestamps
after insert or update of
  activity_status,
  completed_at
on public.lead_activities
for each row
execute function public.sync_lead_contact_from_activity();

-- =========================================================
-- 13. SYNC NEXT FOLLOW-UP DATE ON LEAD
-- =========================================================

create or replace function public.refresh_lead_next_follow_up(
  requested_lead_id uuid,
  requested_organization_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  calculated_next_follow_up timestamptz;
begin
  select min(ft.due_at)
  into calculated_next_follow_up
  from public.follow_up_tasks ft
  where ft.organization_id = requested_organization_id
    and ft.lead_id = requested_lead_id
    and ft.deleted_at is null
    and ft.status in (
      'pending',
      'in_progress',
      'rescheduled'
    );

  update public.leads
  set
    next_follow_up_at = calculated_next_follow_up,
    updated_at = now()
  where id = requested_lead_id
    and organization_id = requested_organization_id;
end;
$$;

revoke all
on function public.refresh_lead_next_follow_up(uuid, uuid)
from public;

-- Trigger wrapper because trigger functions cannot directly
-- receive row-column values as normal function parameters.

create or replace function public.trigger_refresh_lead_next_follow_up()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then

    perform public.refresh_lead_next_follow_up(
      old.lead_id,
      old.organization_id
    );

    return old;
  end if;

  perform public.refresh_lead_next_follow_up(
    new.lead_id,
    new.organization_id
  );

  if tg_op = 'UPDATE'
    and (
      old.lead_id is distinct from new.lead_id
      or old.organization_id
        is distinct from new.organization_id
    ) then

    perform public.refresh_lead_next_follow_up(
      old.lead_id,
      old.organization_id
    );

  end if;

  return new;
end;
$$;

create trigger follow_up_tasks_refresh_lead_next_follow_up
after insert or update of
  lead_id,
  organization_id,
  status,
  due_at,
  deleted_at
or delete
on public.follow_up_tasks
for each row
execute function public.trigger_refresh_lead_next_follow_up();

-- =========================================================
-- 14. UPDATE OVERDUE AND SLA STATUS
-- Intended for a scheduled backend/n8n execution.
-- =========================================================

create or replace function public.process_overdue_follow_ups(
  requested_organization_id uuid default null
)
returns table (
  overdue_count integer,
  sla_breached_count integer,
  sla_at_risk_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_overdue_count integer := 0;
  updated_breached_count integer := 0;
  updated_at_risk_count integer := 0;
begin
  if auth.role() <> 'service_role'
    and requested_organization_id is null then

    raise exception
      'Organization ID is required for authenticated users';

  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'followups.manage_sla'
    ) then

    raise exception 'Permission denied';

  end if;

  update public.follow_up_tasks
  set
    status = 'overdue',
    updated_at = now()
  where deleted_at is null
    and status in (
      'pending',
      'in_progress',
      'rescheduled'
    )
    and due_at < now()
    and (
      requested_organization_id is null
      or organization_id = requested_organization_id
    );

  get diagnostics updated_overdue_count = row_count;

  update public.follow_up_tasks
  set
    sla_status = 'breached',
    updated_at = now()
  where deleted_at is null
    and status not in (
      'completed',
      'cancelled'
    )
    and sla_due_at is not null
    and sla_due_at < now()
    and sla_status <> 'breached'
    and (
      requested_organization_id is null
      or organization_id = requested_organization_id
    );

  get diagnostics updated_breached_count = row_count;

  update public.follow_up_tasks
  set
    sla_status = 'at_risk',
    updated_at = now()
  where deleted_at is null
    and status not in (
      'completed',
      'cancelled'
    )
    and sla_due_at is not null
    and sla_due_at >= now()
    and sla_due_at <= now() + interval '30 minutes'
    and sla_status not in (
      'at_risk',
      'breached'
    )
    and (
      requested_organization_id is null
      or organization_id = requested_organization_id
    );

  get diagnostics updated_at_risk_count = row_count;

  return query
  select
    updated_overdue_count,
    updated_breached_count,
    updated_at_risk_count;
end;
$$;

revoke all
on function public.process_overdue_follow_ups(uuid)
from public;

grant execute
on function public.process_overdue_follow_ups(uuid)
to authenticated;

grant execute
on function public.process_overdue_follow_ups(uuid)
to service_role;

-- =========================================================
-- 15. ESCALATE A FOLLOW-UP TASK
-- =========================================================

create or replace function public.escalate_follow_up_task(
  requested_task_id uuid,
  requested_escalated_to uuid,
  requested_reason text default null
)
returns public.follow_up_tasks
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_task public.follow_up_tasks;
begin
  select *
  into target_task
  from public.follow_up_tasks
  where id = requested_task_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Follow-up task not found';
  end if;

  if not public.has_organization_permission(
    target_task.organization_id,
    'followups.assign'
  ) then
    raise exception 'Permission denied';
  end if;

  if not exists (
    select 1
    from public.organization_members om
    where om.organization_id =
      target_task.organization_id
      and om.user_id = requested_escalated_to
      and om.membership_status = 'active'
  ) then
    raise exception
      'Escalation user must be an active organization member';
  end if;

  update public.follow_up_tasks
  set
    escalation_level = escalation_level + 1,
    escalated_at = now(),
    escalated_to = requested_escalated_to,
    sla_status = case
      when sla_status = 'not_applicable'
        then sla_status
      else 'at_risk'
    end,
    metadata = metadata || jsonb_build_object(
      'last_escalation_reason',
      requested_reason
    ),
    updated_by = auth.uid(),
    updated_at = now()
  where id = requested_task_id
  returning *
  into target_task;

  return target_task;
end;
$$;

revoke all
on function public.escalate_follow_up_task(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.escalate_follow_up_task(
  uuid,
  uuid,
  text
)
to authenticated;

-- =========================================================
-- 16. FOLLOW-UP DASHBOARD FUNCTION
-- =========================================================

create or replace function public.get_follow_up_dashboard(
  requested_organization_id uuid,
  requested_assignee_id uuid default null
)
returns table (
  total_open bigint,
  due_today bigint,
  overdue bigint,
  completed_today bigint,
  sla_at_risk bigint,
  sla_breached bigint,
  unassigned bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_organization_permission(
    requested_organization_id,
    'followups.view'
  ) then
    raise exception 'Permission denied';
  end if;

  return query
  select
    count(*) filter (
      where ft.status in (
        'pending',
        'in_progress',
        'rescheduled',
        'overdue'
      )
    ) as total_open,

    count(*) filter (
      where ft.status in (
        'pending',
        'in_progress',
        'rescheduled'
      )
      and ft.due_at >= date_trunc(
        'day',
        now()
      )
      and ft.due_at < date_trunc(
        'day',
        now()
      ) + interval '1 day'
    ) as due_today,

    count(*) filter (
      where ft.status = 'overdue'
        or (
          ft.status in (
            'pending',
            'in_progress',
            'rescheduled'
          )
          and ft.due_at < now()
        )
    ) as overdue,

    count(*) filter (
      where ft.status = 'completed'
        and ft.completed_at >= date_trunc(
          'day',
          now()
        )
        and ft.completed_at < date_trunc(
          'day',
          now()
        ) + interval '1 day'
    ) as completed_today,

    count(*) filter (
      where ft.sla_status = 'at_risk'
    ) as sla_at_risk,

    count(*) filter (
      where ft.sla_status = 'breached'
    ) as sla_breached,

    count(*) filter (
      where ft.assigned_to is null
        and ft.status in (
          'pending',
          'in_progress',
          'rescheduled',
          'overdue'
        )
    ) as unassigned

  from public.follow_up_tasks ft

  where ft.organization_id =
    requested_organization_id

    and ft.deleted_at is null

    and (
      requested_assignee_id is null
      or ft.assigned_to = requested_assignee_id
    );
end;
$$;

revoke all
on function public.get_follow_up_dashboard(uuid, uuid)
from public;

grant execute
on function public.get_follow_up_dashboard(uuid, uuid)
to authenticated;

-- =========================================================
-- 17. LEAD ACTIVITY RLS POLICIES
-- =========================================================

create policy "Authorized users can view lead activities"
on public.lead_activities
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'followups.view'
  )
);

create policy "Authorized users can create lead activities"
on public.lead_activities
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'followups.create'
  )
);

create policy "Authorized users can update lead activities"
on public.lead_activities
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'followups.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'followups.update'
  )
);

create policy "Authorized users can delete lead activities"
on public.lead_activities
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'followups.delete'
  )
);

-- =========================================================
-- 18. FOLLOW-UP TASK RLS POLICIES
-- =========================================================

create policy "Authorized users can view follow-up tasks"
on public.follow_up_tasks
for select
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'followups.view'
  )
);

create policy "Authorized users can create follow-up tasks"
on public.follow_up_tasks
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'followups.create'
  )
);

create policy "Authorized users can update follow-up tasks"
on public.follow_up_tasks
for update
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'followups.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'followups.update'
  )
);

create policy "Authorized users can delete follow-up tasks"
on public.follow_up_tasks
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'followups.delete'
  )
);

-- =========================================================
-- 19. FOLLOW-UP STATUS HISTORY RLS
-- System-written; authenticated users receive read access.
-- =========================================================

create policy "Authorized users can view follow-up history"
on public.follow_up_status_history
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'followups.view'
  )
);

commit;