-- ============================================================
-- SalesSetu
-- Migration 039
-- Lead Operational Controls Hardening
--
-- Scope:
--   1. Align lead assignment status constraint with assignment RPCs.
--   2. Harden manual assignment and add safe unassignment.
--   3. Prevent direct mutation of assignment-engine managed lead fields.
--   4. Enforce dedicated follow-up permissions on protected fields.
--   5. Add safe follow-up assignment/completion RPCs.
--   6. Enforce dedicated site-visit permissions on protected fields.
--   7. Add safe site-visit assignment/cancellation RPCs.
--   8. Add an optimistic-concurrency lead status transition RPC.
--   9. Remove anonymous/PUBLIC execution from operational functions.
--
-- This migration is intentionally idempotent.
-- ============================================================

begin;

select pg_advisory_xact_lock(
  hashtextextended(
    '039_Lead_Operational_Controls_Hardening',
    0
  )
);

-- ============================================================
-- 1. PREFLIGHT
-- ============================================================

do $preflight$
declare
  required_relation text;
  required_permission text;
begin
  foreach required_relation in array array[
    'public.leads',
    'public.lead_assignments',
    'public.assignment_agent_profiles',
    'public.assignment_teams',
    'public.assignment_team_members',
    'public.assignment_history',
    'public.organization_members',
    'public.follow_up_tasks',
    'public.site_visits'
  ]
  loop
    if to_regclass(required_relation) is null then
      raise exception
        'Migration 039 preflight failed: missing relation %.',
        required_relation;
    end if;
  end loop;

  foreach required_permission in array array[
    'leads.update',
    'assignment.manual_assign',
    'assignment.reassign',
    'assignment.unassign',
    'assignment.override',
    'followups.assign',
    'followups.complete',
    'followups.delete',
    'followups.manage_sla',
    'site_visits.assign',
    'site_visits.check_in',
    'site_visits.complete',
    'site_visits.cancel',
    'site_visits.delete'
  ]
  loop
    if not exists (
      select 1
      from public.permissions permission_row
      where permission_row.code =
        required_permission
    ) then
      raise exception
        'Migration 039 preflight failed: missing permission %.',
        required_permission;
    end if;
  end loop;

  if to_regprocedure(
    'public.has_organization_permission(uuid,text)'
  ) is null then
    raise exception
      'Migration 039 preflight failed: has_organization_permission(uuid,text) is missing.';
  end if;
end;
$preflight$;

-- ============================================================
-- 2. ASSIGNMENT STATUS COMPATIBILITY
-- ============================================================

alter table public.leads
  drop constraint if exists
    leads_assignment_status_check;

alter table public.leads
  add constraint leads_assignment_status_check
  check (
    assignment_status in (
      'unassigned',
      'assigned',
      'accepted',
      'rejected',
      'active',
      'completed',
      'reassigned'
    )
  );

-- ============================================================
-- 3. HARDEN MANUAL ASSIGNMENT
-- ============================================================

create or replace function public.manual_assign_lead(
  requested_lead_id uuid,
  requested_agent_profile_id uuid,
  requested_team_id uuid default null,
  requested_reason text default 'Manual assignment',
  requested_override_capacity boolean default false
)
returns public.lead_assignments
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_lead public.leads;
  agent_record public.assignment_agent_profiles;
  team_record public.assignment_teams;
  previous_record public.lead_assignments;
  assignment_record public.lead_assignments;
begin
  select *
  into target_lead
  from public.leads
  where id = requested_lead_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Lead not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_lead.organization_id,
      'assignment.manual_assign'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into agent_record
  from public.assignment_agent_profiles
  where id = requested_agent_profile_id
    and organization_id =
      target_lead.organization_id
    and status = 'active'
  for update;

  if not found then
    raise exception
      'Active agent profile not found in this organization';
  end if;

  if not exists (
    select 1
    from public.organization_members member_row
    where member_row.organization_id =
      target_lead.organization_id
      and member_row.user_id =
        agent_record.user_id
      and member_row.membership_status =
        'active'
  ) then
    raise exception
      'Assigned agent must be an active organization member';
  end if;

  if requested_team_id is not null then
    select *
    into team_record
    from public.assignment_teams
    where id = requested_team_id
      and organization_id =
        target_lead.organization_id
      and status = 'active';

    if not found then
      raise exception
        'Active assignment team not found in this organization';
    end if;

    if not exists (
      select 1
      from public.assignment_team_members member_row
      where member_row.organization_id =
        target_lead.organization_id
        and member_row.team_id =
          requested_team_id
        and member_row.agent_profile_id =
          agent_record.id
        and member_row.status in (
          'active',
          'temporary'
        )
        and member_row.active_from <= now()
        and (
          member_row.active_until is null
          or member_row.active_until > now()
        )
    ) then
      raise exception
        'Agent is not an active member of the selected team';
    end if;
  end if;

  if requested_override_capacity
    and auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_lead.organization_id,
      'assignment.override'
    ) then
    raise exception
      'Capacity override permission is required';
  end if;

  if not requested_override_capacity
    and not public.is_assignment_agent_available(
      agent_record.id,
      now()
    ) then
    raise exception
      'Agent is not available or capacity is full';
  end if;

  select *
  into previous_record
  from public.lead_assignments
  where organization_id =
      target_lead.organization_id
    and lead_id = target_lead.id
    and status in (
      'assigned',
      'accepted',
      'active'
    )
  order by assigned_at desc
  limit 1
  for update;

  if found then
    if auth.role() <> 'service_role'
      and not public.has_organization_permission(
        target_lead.organization_id,
        'assignment.reassign'
      ) then
      raise exception
        'Reassignment permission is required';
    end if;

    if previous_record.agent_profile_id =
      agent_record.id
      and previous_record.team_id is not distinct from
        requested_team_id then
      return previous_record;
    end if;

    update public.lead_assignments
    set
      status = 'reassigned',
      completed_at =
        coalesce(completed_at, now()),
      unassigned_at =
        coalesce(unassigned_at, now()),
      reassignment_reason =
        coalesce(requested_reason, 'Manual reassignment'),
      updated_by = auth.uid(),
      updated_at = now()
    where id = previous_record.id;

    update public.assignment_agent_profiles
    set
      current_open_leads =
        greatest(current_open_leads - 1, 0),
      updated_at = now()
    where id =
      previous_record.agent_profile_id;
  end if;

  insert into public.lead_assignments (
    organization_id,
    lead_id,
    team_id,
    agent_profile_id,
    assigned_user_id,
    assignment_type,
    strategy,
    status,
    assigned_at,
    previous_assignment_id,
    reassignment_reason,
    assignment_reason,
    created_by,
    updated_by,
    assignment_context
  )
  values (
    target_lead.organization_id,
    target_lead.id,
    requested_team_id,
    agent_record.id,
    agent_record.user_id,
    case
      when previous_record.id is null
        then 'manual'
      else 'reassignment'
    end,
    'manual',
    'assigned',
    now(),
    previous_record.id,
    case
      when previous_record.id is null
        then null
      else requested_reason
    end,
    requested_reason,
    auth.uid(),
    auth.uid(),
    jsonb_build_object(
      'manual', true,
      'capacity_override',
        requested_override_capacity
    )
  )
  returning *
  into assignment_record;

  update public.assignment_agent_profiles
  set
    current_open_leads =
      current_open_leads + 1,
    assigned_today =
      assigned_today + 1,
    assigned_this_hour =
      assigned_this_hour + 1,
    last_assigned_at = now(),
    updated_at = now()
  where id = agent_record.id;

  update public.leads
  set
    assigned_to =
      agent_record.user_id,
    assigned_by =
      auth.uid(),
    assigned_team_id =
      requested_team_id,
    assignment_status =
      case
        when previous_record.id is null
          then 'assigned'
        else 'reassigned'
      end,
    assigned_at = now(),
    assignment_due_at = null,
    assignment_metadata =
      assignment_metadata ||
      jsonb_build_object(
        'assignment_id',
          assignment_record.id,
        'manual',
          true,
        'reason',
          requested_reason,
        'capacity_override',
          requested_override_capacity
      ),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_lead.id;

  insert into public.assignment_history (
    organization_id,
    lead_id,
    assignment_id,
    event_type,
    from_agent_profile_id,
    to_agent_profile_id,
    from_team_id,
    to_team_id,
    reason,
    event_data,
    actor_type,
    actor_user_id
  )
  values (
    target_lead.organization_id,
    target_lead.id,
    assignment_record.id,
    case
      when previous_record.id is null
        then 'assigned'
      else 'reassigned'
    end,
    previous_record.agent_profile_id,
    agent_record.id,
    previous_record.team_id,
    requested_team_id,
    requested_reason,
    jsonb_build_object(
      'capacity_override',
        requested_override_capacity
    ),
    case
      when auth.role() = 'service_role'
        then 'system'
      else 'user'
    end,
    auth.uid()
  );

  return assignment_record;
end;
$function$;

-- ============================================================
-- 4. SAFE UNASSIGNMENT RPC
-- ============================================================

create or replace function public.unassign_lead(
  requested_lead_id uuid,
  requested_reason text default 'Manual unassignment'
)
returns public.leads
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_lead public.leads;
  assignment_record public.lead_assignments;
begin
  select *
  into target_lead
  from public.leads
  where id = requested_lead_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Lead not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_lead.organization_id,
      'assignment.unassign'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into assignment_record
  from public.lead_assignments
  where organization_id =
      target_lead.organization_id
    and lead_id = target_lead.id
    and status in (
      'assigned',
      'accepted',
      'active'
    )
  order by assigned_at desc
  limit 1
  for update;

  if found then
    update public.lead_assignments
    set
      status = 'unassigned',
      unassigned_at =
        coalesce(unassigned_at, now()),
      completed_at =
        coalesce(completed_at, now()),
      reassignment_reason =
        coalesce(requested_reason, 'Manual unassignment'),
      assignment_context =
        assignment_context ||
        jsonb_build_object(
          'unassignment_reason',
            requested_reason
        ),
      updated_by = auth.uid(),
      updated_at = now()
    where id = assignment_record.id;

    update public.assignment_agent_profiles
    set
      current_open_leads =
        greatest(current_open_leads - 1, 0),
      updated_at = now()
    where id =
      assignment_record.agent_profile_id;
  end if;

  update public.leads
  set
    assigned_to = null,
    assigned_by = auth.uid(),
    assigned_team_id = null,
    assignment_status = 'unassigned',
    assigned_at = null,
    assignment_due_at = null,
    assignment_metadata =
      assignment_metadata ||
      jsonb_build_object(
        'unassigned_at',
          now(),
        'unassignment_reason',
          requested_reason
      ),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_lead.id
  returning *
  into target_lead;

  insert into public.assignment_history (
    organization_id,
    lead_id,
    assignment_id,
    event_type,
    from_agent_profile_id,
    from_team_id,
    reason,
    actor_type,
    actor_user_id
  )
  values (
    target_lead.organization_id,
    target_lead.id,
    assignment_record.id,
    'unassigned',
    assignment_record.agent_profile_id,
    assignment_record.team_id,
    requested_reason,
    case
      when auth.role() = 'service_role'
        then 'system'
      else 'user'
    end,
    auth.uid()
  );

  return target_lead;
end;
$function$;

-- ============================================================
-- 5. PROTECT ASSIGNMENT-ENGINE MANAGED LEAD FIELDS
-- ============================================================

create or replace function
  public.guard_lead_assignment_fields()
returns trigger
language plpgsql
set search_path to ''
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

  if new.organization_id
    is distinct from old.organization_id then
    raise exception
      'Lead organization cannot be changed';
  end if;

  if new.assigned_to
      is distinct from old.assigned_to
    or new.assigned_by
      is distinct from old.assigned_by
    or new.assigned_at
      is distinct from old.assigned_at
    or new.assignment_status
      is distinct from old.assignment_status
    or new.assigned_team_id
      is distinct from old.assigned_team_id
    or new.assignment_due_at
      is distinct from old.assignment_due_at
    or new.assignment_metadata
      is distinct from old.assignment_metadata then

    raise exception
      'Assignment fields must be changed through assignment RPCs';
  end if;

  return new;
end;
$function$;

drop trigger if exists
  "00_leads_guard_assignment_fields"
on public.leads;

create trigger
  "00_leads_guard_assignment_fields"
before update on public.leads
for each row
execute function
  public.guard_lead_assignment_fields();

-- ============================================================
-- 6. FOLLOW-UP PROTECTED-FIELD GUARD
-- ============================================================

create or replace function
  public.guard_follow_up_operational_fields()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  organization_value uuid;
begin
  if current_user in (
    'postgres',
    'service_role',
    'supabase_admin'
  )
    or auth.role() = 'service_role' then
    return new;
  end if;

  organization_value := new.organization_id;

  if tg_op = 'INSERT' then
    if new.assigned_to is not null
      and new.assigned_to
        is distinct from auth.uid()
      and not public.has_organization_permission(
        organization_value,
        'followups.assign'
      ) then
      raise exception
        'followups.assign permission is required';
    end if;

    if new.status = 'completed'
      and not public.has_organization_permission(
        organization_value,
        'followups.complete'
      ) then
      raise exception
        'followups.complete permission is required';
    end if;

    if (
      new.escalated_to is not null
      or new.escalated_at is not null
      or new.escalation_level > 0
    )
      and not public.has_organization_permission(
        organization_value,
        'followups.assign'
      ) then
      raise exception
        'followups.assign permission is required for escalation';
    end if;

    return new;
  end if;

  if new.organization_id
      is distinct from old.organization_id
    or new.lead_id
      is distinct from old.lead_id then
    raise exception
      'Follow-up organization and lead cannot be changed';
  end if;

  if new.assigned_by
      is distinct from old.assigned_by
    or new.assigned_at
      is distinct from old.assigned_at then
    raise exception
      'Follow-up assignment audit fields are system managed';
  end if;

  if new.assigned_to
      is distinct from old.assigned_to
    or new.escalated_to
      is distinct from old.escalated_to
    or new.escalated_at
      is distinct from old.escalated_at
    or new.escalation_level
      is distinct from old.escalation_level then

    if not public.has_organization_permission(
      organization_value,
      'followups.assign'
    ) then
      raise exception
        'followups.assign permission is required';
    end if;
  end if;

  if (
    (
      new.status = 'completed'
      and old.status is distinct from 'completed'
    )
    or new.completed_at
      is distinct from old.completed_at
    or new.completion_outcome
      is distinct from old.completion_outcome
    or new.completion_notes
      is distinct from old.completion_notes
  ) then
    if not public.has_organization_permission(
      organization_value,
      'followups.complete'
    ) then
      raise exception
        'followups.complete permission is required';
    end if;
  end if;

  if new.sla_status
      is distinct from old.sla_status
    or new.sla_due_at
      is distinct from old.sla_due_at then

    if not public.has_organization_permission(
      organization_value,
      'followups.manage_sla'
    ) then
      raise exception
        'followups.manage_sla permission is required';
    end if;
  end if;

  if new.deleted_at
      is distinct from old.deleted_at
    or new.deleted_by
      is distinct from old.deleted_by then

    if not public.has_organization_permission(
      organization_value,
      'followups.delete'
    ) then
      raise exception
        'followups.delete permission is required';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists
  "00_follow_up_tasks_guard_operational_fields"
on public.follow_up_tasks;

create trigger
  "00_follow_up_tasks_guard_operational_fields"
before insert or update on public.follow_up_tasks
for each row
execute function
  public.guard_follow_up_operational_fields();

-- ============================================================
-- 7. SAFE FOLLOW-UP ASSIGNMENT RPC
-- ============================================================

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

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_task.organization_id,
      'followups.assign'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_expected_updated_at is not null
    and target_task.updated_at is distinct from
      requested_expected_updated_at then
    raise exception
      'Follow-up task changed after the form was opened'
      using errcode = '40001';
  end if;

  if requested_assigned_to is not null
    and not exists (
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

  update public.follow_up_tasks
  set
    assigned_to = requested_assigned_to,
    metadata =
      metadata ||
      jsonb_build_object(
        'last_assignment_reason',
          requested_reason
      ),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_task.id
  returning *
  into target_task;

  return target_task;
end;
$function$;

-- ============================================================
-- 8. SAFE FOLLOW-UP COMPLETION RPC
-- ============================================================

create or replace function public.complete_follow_up_task(
  requested_task_id uuid,
  requested_outcome text,
  requested_notes text default null,
  requested_expected_updated_at timestamptz default null
)
returns public.follow_up_tasks
language plpgsql
security definer
set search_path to ''
as $function$
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

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_task.organization_id,
      'followups.complete'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_expected_updated_at is not null
    and target_task.updated_at is distinct from
      requested_expected_updated_at then
    raise exception
      'Follow-up task changed after the form was opened'
      using errcode = '40001';
  end if;

  if target_task.status = 'cancelled' then
    raise exception
      'Cancelled follow-up task cannot be completed';
  end if;

  if target_task.status = 'completed' then
    return target_task;
  end if;

  update public.follow_up_tasks
  set
    status = 'completed',
    completion_outcome =
      nullif(btrim(requested_outcome), ''),
    completion_notes =
      nullif(btrim(requested_notes), ''),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_task.id
  returning *
  into target_task;

  return target_task;
end;
$function$;

-- ============================================================
-- 9. SITE-VISIT PROTECTED-FIELD GUARD
-- ============================================================

create or replace function
  public.guard_site_visit_operational_fields()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  organization_value uuid;
begin
  if current_user in (
    'postgres',
    'service_role',
    'supabase_admin'
  )
    or auth.role() = 'service_role' then
    return new;
  end if;

  organization_value := new.organization_id;

  if tg_op = 'INSERT' then
    if (
      new.assigned_agent_id is not null
      and new.assigned_agent_id
        is distinct from auth.uid()
    )
      or (
        new.coordinator_id is not null
        and new.coordinator_id
          is distinct from auth.uid()
      ) then

      if not public.has_organization_permission(
        organization_value,
        'site_visits.assign'
      ) then
        raise exception
          'site_visits.assign permission is required';
      end if;
    end if;

    if new.status = 'completed'
      and not public.has_organization_permission(
        organization_value,
        'site_visits.complete'
      ) then
      raise exception
        'site_visits.complete permission is required';
    end if;

    if new.status = 'cancelled'
      and not public.has_organization_permission(
        organization_value,
        'site_visits.cancel'
      ) then
      raise exception
        'site_visits.cancel permission is required';
    end if;

    if new.status in (
      'checked_in',
      'in_progress'
    )
      and not public.has_organization_permission(
        organization_value,
        'site_visits.check_in'
      ) then
      raise exception
        'site_visits.check_in permission is required';
    end if;

    return new;
  end if;

  if new.organization_id
      is distinct from old.organization_id
    or new.lead_id
      is distinct from old.lead_id then
    raise exception
      'Site-visit organization and lead cannot be changed';
  end if;

  if new.assigned_by
      is distinct from old.assigned_by
    or new.assigned_at
      is distinct from old.assigned_at then
    raise exception
      'Site-visit assignment audit fields are system managed';
  end if;

  if new.assigned_agent_id
      is distinct from old.assigned_agent_id
    or new.coordinator_id
      is distinct from old.coordinator_id then

    if not public.has_organization_permission(
      organization_value,
      'site_visits.assign'
    ) then
      raise exception
        'site_visits.assign permission is required';
    end if;
  end if;

  if (
    (
      new.status in (
        'checked_in',
        'in_progress'
      )
      and old.status is distinct from new.status
    )
    or new.customer_checked_in_at
      is distinct from old.customer_checked_in_at
    or new.agent_checked_in_at
      is distinct from old.agent_checked_in_at
    or new.customer_checked_out_at
      is distinct from old.customer_checked_out_at
    or new.agent_checked_out_at
      is distinct from old.agent_checked_out_at
    or new.customer_check_in_latitude
      is distinct from old.customer_check_in_latitude
    or new.customer_check_in_longitude
      is distinct from old.customer_check_in_longitude
    or new.agent_check_in_latitude
      is distinct from old.agent_check_in_latitude
    or new.agent_check_in_longitude
      is distinct from old.agent_check_in_longitude
    or new.check_in_method
      is distinct from old.check_in_method
  ) then
    if not public.has_organization_permission(
      organization_value,
      'site_visits.check_in'
    ) then
      raise exception
        'site_visits.check_in permission is required';
    end if;
  end if;

  if (
    (
      new.status = 'completed'
      and old.status is distinct from 'completed'
    )
    or new.visit_completed_at
      is distinct from old.visit_completed_at
    or new.outcome
      is distinct from old.outcome
    or new.outcome_summary
      is distinct from old.outcome_summary
    or new.agent_notes
      is distinct from old.agent_notes
    or new.customer_feedback
      is distinct from old.customer_feedback
    or new.customer_rating
      is distinct from old.customer_rating
    or new.agent_rating
      is distinct from old.agent_rating
    or new.project_rating
      is distinct from old.project_rating
    or new.probability_of_booking
      is distinct from old.probability_of_booking
    or new.expected_booking_date
      is distinct from old.expected_booking_date
    or new.expected_booking_value
      is distinct from old.expected_booking_value
  ) then
    if not public.has_organization_permission(
      organization_value,
      'site_visits.complete'
    ) then
      raise exception
        'site_visits.complete permission is required';
    end if;
  end if;

  if (
    (
      new.status = 'cancelled'
      and old.status is distinct from 'cancelled'
    )
    or new.cancelled_at
      is distinct from old.cancelled_at
    or new.cancelled_by
      is distinct from old.cancelled_by
    or new.cancellation_reason
      is distinct from old.cancellation_reason
  ) then
    if not public.has_organization_permission(
      organization_value,
      'site_visits.cancel'
    ) then
      raise exception
        'site_visits.cancel permission is required';
    end if;
  end if;

  if new.deleted_at
      is distinct from old.deleted_at
    or new.deleted_by
      is distinct from old.deleted_by then

    if not public.has_organization_permission(
      organization_value,
      'site_visits.delete'
    ) then
      raise exception
        'site_visits.delete permission is required';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists
  "00_site_visits_guard_operational_fields"
on public.site_visits;

create trigger
  "00_site_visits_guard_operational_fields"
before insert or update on public.site_visits
for each row
execute function
  public.guard_site_visit_operational_fields();

-- ============================================================
-- 10. SAFE SITE-VISIT ASSIGNMENT RPC
-- ============================================================

create or replace function public.assign_site_visit(
  requested_site_visit_id uuid,
  requested_agent_id uuid,
  requested_coordinator_id uuid default null,
  requested_reason text default null,
  requested_expected_updated_at timestamptz default null
)
returns public.site_visits
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_visit public.site_visits;
begin
  select *
  into target_visit
  from public.site_visits
  where id = requested_site_visit_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Site visit not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_visit.organization_id,
      'site_visits.assign'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_expected_updated_at is not null
    and target_visit.updated_at is distinct from
      requested_expected_updated_at then
    raise exception
      'Site visit changed after the form was opened'
      using errcode = '40001';
  end if;

  if requested_agent_id is not null
    and not exists (
      select 1
      from public.organization_members member_row
      where member_row.organization_id =
        target_visit.organization_id
        and member_row.user_id =
          requested_agent_id
        and member_row.membership_status =
          'active'
    ) then
    raise exception
      'Assigned agent must be an active organization member';
  end if;

  if requested_coordinator_id is not null
    and not exists (
      select 1
      from public.organization_members member_row
      where member_row.organization_id =
        target_visit.organization_id
        and member_row.user_id =
          requested_coordinator_id
        and member_row.membership_status =
          'active'
    ) then
    raise exception
      'Coordinator must be an active organization member';
  end if;

  update public.site_visits
  set
    assigned_agent_id =
      requested_agent_id,
    coordinator_id =
      requested_coordinator_id,
    metadata =
      metadata ||
      jsonb_build_object(
        'last_assignment_reason',
          requested_reason
      ),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_visit.id
  returning *
  into target_visit;

  return target_visit;
end;
$function$;

-- ============================================================
-- 11. SAFE SITE-VISIT CANCELLATION RPC
-- ============================================================

create or replace function public.cancel_site_visit(
  requested_site_visit_id uuid,
  requested_reason text,
  requested_expected_updated_at timestamptz default null
)
returns public.site_visits
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_visit public.site_visits;
begin
  select *
  into target_visit
  from public.site_visits
  where id = requested_site_visit_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Site visit not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_visit.organization_id,
      'site_visits.cancel'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_expected_updated_at is not null
    and target_visit.updated_at is distinct from
      requested_expected_updated_at then
    raise exception
      'Site visit changed after the form was opened'
      using errcode = '40001';
  end if;

  if target_visit.status = 'completed' then
    raise exception
      'Completed site visit cannot be cancelled';
  end if;

  if target_visit.status = 'cancelled' then
    return target_visit;
  end if;

  if nullif(btrim(requested_reason), '') is null then
    raise exception
      'Cancellation reason is required';
  end if;

  update public.site_visits
  set
    status = 'cancelled',
    cancellation_reason =
      btrim(requested_reason),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_visit.id
  returning *
  into target_visit;

  return target_visit;
end;
$function$;

-- ============================================================
-- 12. OPTIMISTIC LEAD STATUS TRANSITION RPC
-- ============================================================

create or replace function
  public.transition_lead_status(
    requested_lead_id uuid,
    requested_status text,
    requested_lifecycle_stage text default null,
    requested_temperature text default null,
    requested_reason text default null,
    requested_expected_updated_at timestamptz default null
  )
returns public.leads
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_lead public.leads;
  target_temperature text;
begin
  select *
  into target_lead
  from public.leads
  where id = requested_lead_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Lead not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_lead.organization_id,
      'leads.update'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_expected_updated_at is not null
    and target_lead.updated_at is distinct from
      requested_expected_updated_at then
    raise exception
      'Lead changed after the form was opened'
      using errcode = '40001';
  end if;

  if requested_status not in (
    'new',
    'contact_attempted',
    'connected',
    'qualified',
    'unqualified',
    'nurturing',
    'site_visit_planned',
    'site_visit_completed',
    'negotiation',
    'booked',
    'lost',
    'duplicate',
    'invalid',
    'archived'
  ) then
    raise exception 'Invalid lead status';
  end if;

  if requested_lifecycle_stage is not null
    and requested_lifecycle_stage not in (
      'lead',
      'prospect',
      'opportunity',
      'customer',
      'lost'
    ) then
    raise exception 'Invalid lifecycle stage';
  end if;

  if requested_temperature is null then
    target_temperature :=
      target_lead.lead_temperature;
  elsif btrim(requested_temperature) = '' then
    target_temperature := null;
  elsif requested_temperature in (
    'hot',
    'warm',
    'cold'
  ) then
    target_temperature :=
      requested_temperature;
  else
    raise exception 'Invalid lead temperature';
  end if;

  update public.leads
  set
    lead_status = requested_status,
    lifecycle_stage =
      coalesce(
        requested_lifecycle_stage,
        lifecycle_stage
      ),
    lead_temperature =
      target_temperature,
    metadata =
      metadata ||
      jsonb_build_object(
        'last_status_change_reason',
          requested_reason,
        'last_status_changed_by',
          auth.uid(),
        'last_status_changed_at',
          now()
      ),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_lead.id
  returning *
  into target_lead;

  return target_lead;
end;
$function$;

-- ============================================================
-- 13. EXECUTION GRANTS
-- ============================================================

do $revoke_operational_execute$
declare
  function_record record;
begin
  for function_record in
    select function_row.oid
    from pg_proc function_row
    join pg_namespace schema_row
      on schema_row.oid =
        function_row.pronamespace
    where schema_row.nspname = 'public'
      and function_row.proname = any (
        array[
          'manual_assign_lead',
          'unassign_lead',
          'respond_to_lead_assignment',
          'mark_assignment_first_response',
          'complete_lead_assignment',
          'create_assignment_request',
          'execute_assignment_request',
          'assign_follow_up_task',
          'complete_follow_up_task',
          'escalate_follow_up_task',
          'process_overdue_follow_ups',
          'refresh_lead_next_follow_up',
          'check_in_site_visit',
          'check_out_site_visit',
          'complete_site_visit',
          'assign_site_visit',
          'cancel_site_visit',
          'transition_lead_status',
          'guard_lead_assignment_fields',
          'guard_follow_up_operational_fields',
          'guard_site_visit_operational_fields',
          'set_follow_up_system_fields',
          'record_follow_up_status_history',
          'create_follow_up_completion_activity',
          'trigger_refresh_lead_next_follow_up',
          'set_site_visit_system_fields',
          'record_site_visit_history',
          'create_site_visit_activity',
          'sync_lead_from_site_visit',
          'record_lead_status_history',
          'record_lead_assignment_history',
          'set_lead_assignment_fields'
        ]
      )
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      function_record.oid::regprocedure
    );
  end loop;
end;
$revoke_operational_execute$;

do $grant_authenticated_operational_execute$
declare
  function_record record;
begin
  for function_record in
    select function_row.oid
    from pg_proc function_row
    join pg_namespace schema_row
      on schema_row.oid =
        function_row.pronamespace
    where schema_row.nspname = 'public'
      and function_row.proname = any (
        array[
          'manual_assign_lead',
          'unassign_lead',
          'respond_to_lead_assignment',
          'mark_assignment_first_response',
          'complete_lead_assignment',
          'create_assignment_request',
          'execute_assignment_request',
          'assign_follow_up_task',
          'complete_follow_up_task',
          'escalate_follow_up_task',
          'process_overdue_follow_ups',
          'check_in_site_visit',
          'check_out_site_visit',
          'complete_site_visit',
          'assign_site_visit',
          'cancel_site_visit',
          'transition_lead_status'
        ]
      )
  loop
    execute format(
      'grant execute on function %s to authenticated, service_role',
      function_record.oid::regprocedure
    );
  end loop;
end;
$grant_authenticated_operational_execute$;

grant execute on function
  public.refresh_lead_next_follow_up(uuid, uuid)
to service_role;

-- ============================================================
-- 14. VERIFICATION
-- ============================================================

do $verification$
declare
  assignment_constraint text;
  anonymous_execute_count integer;
begin
  select pg_get_constraintdef(
    constraint_row.oid,
    true
  )
  into assignment_constraint
  from pg_constraint constraint_row
  where constraint_row.conrelid =
      'public.leads'::regclass
    and constraint_row.conname =
      'leads_assignment_status_check';

  if assignment_constraint is null
    or position(
      '''active''' in assignment_constraint
    ) = 0
    or position(
      '''completed''' in assignment_constraint
    ) = 0 then
    raise exception
      'Migration 039 verification failed: assignment status constraint is incomplete.';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid =
        'public.leads'::regclass
      and trigger_row.tgname =
        '00_leads_guard_assignment_fields'
      and not trigger_row.tgisinternal
  ) then
    raise exception
      'Migration 039 verification failed: lead assignment guard trigger is missing.';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid =
        'public.follow_up_tasks'::regclass
      and trigger_row.tgname =
        '00_follow_up_tasks_guard_operational_fields'
      and not trigger_row.tgisinternal
  ) then
    raise exception
      'Migration 039 verification failed: follow-up guard trigger is missing.';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid =
        'public.site_visits'::regclass
      and trigger_row.tgname =
        '00_site_visits_guard_operational_fields'
      and not trigger_row.tgisinternal
  ) then
    raise exception
      'Migration 039 verification failed: site-visit guard trigger is missing.';
  end if;

  select count(*)
  into anonymous_execute_count
  from pg_proc function_row
  join pg_namespace schema_row
    on schema_row.oid =
      function_row.pronamespace
  where schema_row.nspname = 'public'
    and function_row.proname = any (
      array[
        'manual_assign_lead',
        'unassign_lead',
        'assign_follow_up_task',
        'complete_follow_up_task',
        'assign_site_visit',
        'cancel_site_visit',
        'transition_lead_status'
      ]
    )
    and has_function_privilege(
      'anon',
      function_row.oid,
      'EXECUTE'
    );

  if anonymous_execute_count <> 0 then
    raise exception
      'Migration 039 verification failed: anonymous operational EXECUTE grants remain.';
  end if;

  raise notice
    'Migration 039 verified: operational controls hardened.';
end;
$verification$;

commit;