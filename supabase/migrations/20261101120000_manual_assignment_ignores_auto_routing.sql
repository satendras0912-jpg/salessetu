-- SalesSetu
-- Manual assignment must not be blocked when automatic routing is disabled.
-- Capacity, availability, leave and working-hours safeguards remain enforced.

begin;

create or replace function public.is_manual_assignment_agent_available(
  requested_agent_profile_id uuid,
  requested_at timestamptz default now()
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  agent_record public.assignment_agent_profiles;
  local_timestamp timestamp;
  local_day integer;
  local_time time;
  schedule_exists boolean;
  blocked boolean;
begin
  select *
  into agent_record
  from public.assignment_agent_profiles
  where id = requested_agent_profile_id;

  if not found then
    return false;
  end if;

  -- Deliberately independent of auto_assignment_enabled:
  -- an owner can manually assign while automatic routing is disabled.
  if agent_record.status <> 'active'
    or agent_record.availability_status <> 'available'
    or not agent_record.accept_new_leads then
    return false;
  end if;

  if agent_record.current_open_leads >= agent_record.maximum_open_leads
    or agent_record.assigned_today >= agent_record.daily_assignment_limit
    or (
      agent_record.hourly_assignment_limit is not null
      and agent_record.assigned_this_hour >= agent_record.hourly_assignment_limit
    ) then
    return false;
  end if;

  select exists (
    select 1
    from public.assignment_agent_unavailability unavailability_row
    where unavailability_row.agent_profile_id = agent_record.id
      and unavailability_row.status = 'active'
      and requested_at >= unavailability_row.starts_at
      and requested_at < unavailability_row.ends_at
  )
  into blocked;

  if blocked then
    return false;
  end if;

  local_timestamp := requested_at at time zone agent_record.timezone;
  local_day := extract(dow from local_timestamp)::integer;
  local_time := local_timestamp::time;

  select exists (
    select 1
    from public.assignment_agent_schedules schedule_row
    where schedule_row.agent_profile_id = agent_record.id
      and schedule_row.day_of_week = local_day
      and schedule_row.is_working_day = true
      and local_time >= schedule_row.start_time
      and local_time < schedule_row.end_time
      and (
        schedule_row.effective_from is null
        or local_timestamp::date >= schedule_row.effective_from
      )
      and (
        schedule_row.effective_until is null
        or local_timestamp::date <= schedule_row.effective_until
      )
  )
  into schedule_exists;

  if exists (
    select 1
    from public.assignment_agent_schedules schedule_row
    where schedule_row.agent_profile_id = agent_record.id
  ) then
    return schedule_exists;
  end if;

  return true;
end;
$function$;

revoke all on function
  public.is_manual_assignment_agent_available(uuid, timestamptz)
from public;

grant execute on function
  public.is_manual_assignment_agent_available(uuid, timestamptz)
to authenticated, service_role;

do $replace_manual_assignment$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.manual_assign_lead(uuid,uuid,uuid,text,boolean)'::regprocedure
  )
  into function_definition;

  if function_definition is null then
    raise exception
      'Manual assignment fix failed: manual_assign_lead function is missing.';
  end if;

  function_definition := replace(
    function_definition,
    'public.is_assignment_agent_available(',
    'public.is_manual_assignment_agent_available('
  );

  if position(
    'public.is_manual_assignment_agent_available('
    in function_definition
  ) = 0 then
    raise exception
      'Manual assignment fix failed: availability check was not replaced.';
  end if;

  execute function_definition;
end;
$replace_manual_assignment$;

do $verify_manual_assignment$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.manual_assign_lead(uuid,uuid,uuid,text,boolean)'::regprocedure
  )
  into function_definition;

  if position(
    'public.is_manual_assignment_agent_available('
    in function_definition
  ) = 0 then
    raise exception
      'Manual assignment verification failed: manual availability safeguard is missing.';
  end if;
end;
$verify_manual_assignment$;

commit;
