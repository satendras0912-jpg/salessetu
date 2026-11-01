-- SalesSetu
-- Manual assignment in-app notification.
-- Keeps manual assignment independent from automatic routing and respects
-- the assignee's in-app notification preferences.

begin;

create or replace function public.create_assignment_in_app_notification(
  requested_assignment_id uuid
)
returns public.notification_jobs
language plpgsql
security definer
set search_path = ''
as $function$
declare
  assignment_record public.lead_assignments;
  lead_record public.leads;
  category_record public.notification_categories;
  existing_job public.notification_jobs;
  notification_job_record public.notification_jobs;
  recipient_record public.notification_recipients;
  eligibility jsonb;
  lead_display_name text;
  notification_body text;
  notification_idempotency_key text;
begin
  select *
  into assignment_record
  from public.lead_assignments
  where id = requested_assignment_id
  for update;

  if not found then
    raise exception 'Assignment not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      assignment_record.organization_id,
      'assignment.manual_assign'
    ) then
    raise exception 'Permission denied';
  end if;

  notification_idempotency_key :=
    'lead_assignment_in_app:'
    || assignment_record.id::text;

  select *
  into existing_job
  from public.notification_jobs
  where organization_id = assignment_record.organization_id
    and idempotency_key = notification_idempotency_key
  limit 1;

  if found then
    return existing_job;
  end if;

  select *
  into category_record
  from public.notification_categories
  where category_code = 'assignment_created'
    and status = 'active'
    and (
      organization_id = assignment_record.organization_id
      or organization_id is null
    )
  order by
    case
      when organization_id = assignment_record.organization_id
        then 0
      else 1
    end
  limit 1;

  if not found then
    raise exception
      'Active assignment_created notification category not found';
  end if;

  select *
  into lead_record
  from public.leads
  where id = assignment_record.lead_id
    and organization_id = assignment_record.organization_id;

  if not found then
    raise exception 'Assigned lead not found';
  end if;

  lead_display_name :=
    coalesce(
      nullif(btrim(lead_record.full_name), ''),
      nullif(
        btrim(
          concat_ws(
            ' ',
            lead_record.first_name,
            lead_record.last_name
          )
        ),
        ''
      ),
      'New lead'
    );

  notification_body :=
    'You have been assigned '
    || lead_display_name
    || coalesce(
      nullif(
        ' for ' || btrim(lead_record.preferred_project),
        ' for '
      ),
      ''
    )
    || '. Open the lead to start follow-up.';

  insert into public.notification_jobs (
    organization_id,
    category_id,
    source_module,
    source_type,
    source_id,
    source_reference,
    event_name,
    idempotency_key,
    correlation_id,
    trace_id,
    title,
    body,
    rendered_title,
    rendered_body,
    variables,
    actions,
    deep_link,
    severity,
    priority,
    status,
    recipient_count,
    delivered_count,
    started_at,
    completed_at,
    created_by,
    updated_by,
    metadata
  )
  values (
    assignment_record.organization_id,
    category_record.id,
    'leads',
    'lead_assignment',
    assignment_record.id,
    assignment_record.id::text,
    'lead.assignment.created',
    notification_idempotency_key,
    gen_random_uuid()::text,
    gen_random_uuid()::text,
    'New lead assigned',
    notification_body,
    'New lead assigned',
    notification_body,
    jsonb_build_object(
      'assignment_id',
      assignment_record.id,
      'lead_id',
      assignment_record.lead_id,
      'assignment_type',
      assignment_record.assignment_type,
      'assignment_reason',
      assignment_record.assignment_reason
    ),
    '[]'::jsonb,
    '/dashboard/leads/' || assignment_record.lead_id::text,
    'info',
    40,
    'processing',
    1,
    0,
    now(),
    null,
    auth.uid(),
    auth.uid(),
    jsonb_build_object(
      'channel_codes',
      array['in_app']::text[],
      'category_code',
      'assignment_created',
      'delivery_source',
      'manual_assignment'
    )
  )
  returning *
  into notification_job_record;

  insert into public.notification_recipients (
    organization_id,
    notification_job_id,
    recipient_type,
    user_id,
    status
  )
  values (
    assignment_record.organization_id,
    notification_job_record.id,
    'user',
    assignment_record.assigned_user_id,
    'pending'
  )
  returning *
  into recipient_record;

  eligibility :=
    public.check_notification_eligibility(
      assignment_record.organization_id,
      assignment_record.assigned_user_id,
      'assignment_created',
      'in_app',
      'info',
      now()
    );

  if coalesce(
    (eligibility ->> 'eligible')::boolean,
    false
  ) then
    insert into public.notification_delivery_attempts (
      organization_id,
      notification_job_id,
      notification_recipient_id,
      channel_code,
      status,
      attempt_number,
      delivered_at
    )
    values (
      assignment_record.organization_id,
      notification_job_record.id,
      recipient_record.id,
      'in_app',
      'delivered',
      1,
      now()
    );

    insert into public.notification_inbox (
      organization_id,
      user_id,
      notification_job_id,
      notification_recipient_id,
      title,
      body,
      category_code,
      severity,
      priority,
      deep_link,
      actions,
      metadata
    )
    values (
      assignment_record.organization_id,
      assignment_record.assigned_user_id,
      notification_job_record.id,
      recipient_record.id,
      notification_job_record.rendered_title,
      notification_job_record.rendered_body,
      'assignment_created',
      notification_job_record.severity,
      notification_job_record.priority,
      notification_job_record.deep_link,
      notification_job_record.actions,
      jsonb_build_object(
        'source_module',
        'leads',
        'source_type',
        'lead_assignment',
        'source_id',
        assignment_record.id
      )
    );

    update public.notification_recipients
    set
      status = 'delivered',
      delivered_at = now()
    where id = recipient_record.id;

    update public.notification_jobs
    set
      status = 'delivered',
      delivered_count = 1,
      completed_at = now(),
      updated_at = now()
    where id = notification_job_record.id;
  else
    update public.notification_recipients
    set
      status = 'suppressed',
      suppression_reason = eligibility ->> 'reason'
    where id = recipient_record.id;

    update public.notification_jobs
    set
      status = 'delivered',
      suppressed_count = 1,
      completed_at = now(),
      updated_at = now()
    where id = notification_job_record.id;
  end if;

  select *
  into notification_job_record
  from public.notification_jobs
  where id = notification_job_record.id;

  return notification_job_record;
end;
$function$;

revoke all on function
  public.create_assignment_in_app_notification(uuid)
from public;

grant execute on function
  public.create_assignment_in_app_notification(uuid)
to authenticated, service_role;

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
set search_path = ''
as $function$
declare
  organization_value uuid;
  agent_record public.assignment_agent_profiles;
  assignment_record public.lead_assignments;
  previous_record public.lead_assignments;
begin
  select organization_id
  into organization_value
  from public.leads
  where id = requested_lead_id;

  if organization_value is null then
    raise exception 'Lead not found';
  end if;

  if not public.has_organization_permission(
    organization_value,
    'assignment.manual_assign'
  ) then
    raise exception 'Permission denied';
  end if;

  select *
  into agent_record
  from public.assignment_agent_profiles
  where id = requested_agent_profile_id
    and organization_id = organization_value
  for update;

  if not found then
    raise exception 'Agent profile not found';
  end if;

  if not requested_override_capacity
    and not public.is_manual_assignment_agent_available(
      agent_record.id,
      now()
    ) then
    raise exception 'Agent is not available or capacity is full';
  end if;

  select *
  into previous_record
  from public.lead_assignments
  where organization_id = organization_value
    and lead_id = requested_lead_id
    and status in ('assigned', 'accepted', 'active')
  order by assigned_at desc
  limit 1
  for update;

  if found then
    update public.lead_assignments
    set
      status = 'reassigned',
      completed_at = now(),
      updated_at = now()
    where id = previous_record.id;

    update public.assignment_agent_profiles
    set
      current_open_leads = greatest(
        current_open_leads - 1,
        0
      ),
      updated_at = now()
    where id = previous_record.agent_profile_id;
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
    updated_by
  )
  values (
    organization_value,
    requested_lead_id,
    requested_team_id,
    agent_record.id,
    agent_record.user_id,
    case
      when previous_record.id is null then 'manual'
      else 'reassignment'
    end,
    'manual',
    'assigned',
    now(),
    previous_record.id,
    case
      when previous_record.id is null then null
      else requested_reason
    end,
    requested_reason,
    auth.uid(),
    auth.uid()
  )
  returning *
  into assignment_record;

  update public.assignment_agent_profiles
  set
    current_open_leads = current_open_leads + 1,
    assigned_today = assigned_today + 1,
    assigned_this_hour = assigned_this_hour + 1,
    last_assigned_at = now(),
    updated_at = now()
  where id = agent_record.id;

  update public.leads
  set
    assigned_to = agent_record.user_id,
    assigned_team_id = requested_team_id,
    assignment_status = 'assigned',
    assigned_at = now(),
    assignment_metadata =
      assignment_metadata
      || jsonb_build_object(
        'assignment_id',
        assignment_record.id,
        'manual',
        true,
        'reason',
        requested_reason
      ),
    updated_at = now()
  where id = requested_lead_id;

  insert into public.assignment_history (
    organization_id,
    lead_id,
    assignment_id,
    event_type,
    from_agent_profile_id,
    to_agent_profile_id,
    to_team_id,
    reason,
    actor_type,
    actor_user_id
  )
  values (
    organization_value,
    requested_lead_id,
    assignment_record.id,
    case
      when previous_record.id is null then 'assigned'
      else 'reassigned'
    end,
    previous_record.agent_profile_id,
    agent_record.id,
    requested_team_id,
    requested_reason,
    'user',
    auth.uid()
  );

  begin
    perform public.create_assignment_in_app_notification(
      assignment_record.id
    );
  exception
    when others then
      update public.lead_assignments
      set
        assignment_context =
          coalesce(assignment_context, '{}'::jsonb)
          || jsonb_build_object(
            'assignment_notification_error',
            SQLERRM,
            'assignment_notification_error_at',
            now()
          ),
        updated_at = now()
      where id = assignment_record.id;

      raise warning
        'Lead assignment notification could not be created: %',
        SQLERRM;
  end;

  return assignment_record;
end;
$function$;

revoke all on function
  public.manual_assign_lead(uuid, uuid, uuid, text, boolean)
from public;

grant execute on function
  public.manual_assign_lead(uuid, uuid, uuid, text, boolean)
to authenticated, service_role;

commit;
