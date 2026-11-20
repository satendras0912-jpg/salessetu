-- A site visit may be checked in and completed before its planned start time.
-- Activity rows must always reflect the actual operational timestamps, otherwise
-- lead_activities_time_valid rejects a legitimate completion.

begin;

create or replace function public.complete_site_visit(
  requested_site_visit_id uuid,
  requested_outcome text,
  requested_outcome_summary text,
  requested_probability_of_booking numeric,
  requested_agent_notes text,
  requested_expected_updated_at timestamptz
)
returns public.site_visits
language plpgsql
security definer
set search_path = ''
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
      'site_visits.complete'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_expected_updated_at is null then
    raise exception 'Expected update timestamp is required';
  end if;

  if target_visit.updated_at is distinct from requested_expected_updated_at then
    raise exception 'Site visit changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if target_visit.status = 'completed' then
    raise exception 'Site visit is already completed';
  end if;

  if target_visit.status not in (
    'scheduled', 'confirmed', 'agent_en_route', 'customer_en_route',
    'rescheduled', 'checked_in', 'in_progress'
  ) then
    raise exception 'Site visit cannot be completed from status %', target_visit.status;
  end if;

  if requested_outcome is null
    or requested_outcome not in (
      'interested', 'highly_interested', 'considering', 'follow_up_required',
      'negotiation_started', 'booking_expected', 'not_interested',
      'budget_mismatch', 'location_mismatch', 'unit_mismatch', 'postponed',
      'no_show', 'other'
    ) then
    raise exception 'Invalid site visit outcome';
  end if;

  if requested_probability_of_booking is not null
    and (requested_probability_of_booking < 0 or requested_probability_of_booking > 100) then
    raise exception 'Probability of booking must be between 0 and 100';
  end if;

  update public.site_visits
  set
    status = 'completed',
    outcome = requested_outcome,
    outcome_summary = nullif(btrim(requested_outcome_summary), ''),
    probability_of_booking = requested_probability_of_booking,
    agent_notes = nullif(btrim(requested_agent_notes), ''),
    -- Preserve the real check-in moment when available. For a legitimate
    -- completion without check-in, start and completion are the same instant.
    visit_started_at = coalesce(
      visit_started_at,
      agent_checked_in_at,
      customer_checked_in_at,
      now()
    ),
    visit_completed_at = coalesce(visit_completed_at, now()),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_visit.id
  returning * into target_visit;

  return target_visit;
end;
$function$;

create or replace function public.create_site_visit_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  generated_subject text;
  generated_description text;
  generated_activity_status text;
begin
  if tg_op = 'INSERT' then
    insert into public.lead_activities (
      organization_id, lead_id, activity_type, direction, activity_status,
      subject, description, started_at, performed_by, is_automated,
      metadata, created_by
    )
    values (
      new.organization_id, new.lead_id, 'site_visit', 'internal', 'scheduled',
      'Site visit scheduled', concat(new.project_name, ' — ', new.scheduled_start_at),
      new.scheduled_start_at, new.assigned_agent_id, new.is_automated,
      jsonb_build_object(
        'site_visit_id', new.id,
        'project_name', new.project_name,
        'visit_number', new.visit_number
      ),
      coalesce(new.created_by, auth.uid())
    );
    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  generated_subject := case new.status
    when 'confirmed' then 'Site visit confirmed'
    when 'checked_in' then 'Customer checked in'
    when 'in_progress' then 'Site visit started'
    when 'completed' then 'Site visit completed'
    when 'cancelled' then 'Site visit cancelled'
    when 'no_show' then 'Site visit marked no-show'
    when 'rescheduled' then 'Site visit rescheduled'
    else 'Site visit updated'
  end;

  generated_description := case
    when new.status = 'completed'
      then coalesce(new.outcome_summary, new.agent_notes, 'Site visit completed')
    when new.status = 'cancelled'
      then coalesce(new.cancellation_reason, 'Site visit cancelled')
    when new.status = 'no_show'
      then concat('No-show party: ', coalesce(new.no_show_party, 'unknown'))
    else concat(new.project_name, ' — status changed to ', new.status)
  end;

  generated_activity_status := case
    when new.status = 'cancelled' then 'cancelled'
    when new.status = 'no_show' then 'no_response'
    when new.status = 'completed' then 'completed'
    when new.status = 'in_progress' then 'in_progress'
    else 'scheduled'
  end;

  insert into public.lead_activities (
    organization_id, lead_id, activity_type, direction, activity_status,
    subject, description, outcome, started_at, completed_at, performed_by,
    is_automated, metadata, created_by
  )
  values (
    new.organization_id, new.lead_id, 'site_visit', 'internal',
    generated_activity_status, generated_subject, generated_description,
    new.outcome,
    coalesce(
      new.visit_started_at,
      new.agent_checked_in_at,
      new.customer_checked_in_at,
      least(new.scheduled_start_at, new.visit_completed_at),
      new.scheduled_start_at,
      new.visit_completed_at
    ),
    new.visit_completed_at,
    new.assigned_agent_id,
    new.is_automated,
    jsonb_build_object(
      'site_visit_id', new.id,
      'project_name', new.project_name,
      'visit_status', new.status
    ),
    coalesce(new.updated_by, auth.uid())
  );

  return new;
end;
$function$;

notify pgrst, 'reload schema';

commit;
