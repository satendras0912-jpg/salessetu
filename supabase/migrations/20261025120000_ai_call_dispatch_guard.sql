-- Persist dispatch intent before any external request. A process crash, timeout,
-- malformed provider response or failed initiation write must never cause redial.
alter table public.ai_call_jobs
  add column if not exists dispatch_requires_reconciliation boolean not null default false;

create or replace function public.check_ai_call_eligibility(
  requested_organization_id uuid,
  requested_phone_number text,
  requested_lead_id uuid default null,
  requested_campaign_id uuid default null,
  requested_at timestamptz default now()
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_phone text;
  campaign_record public.ai_call_campaigns;
  local_time time;
  local_dow integer;
  consent_required boolean := true;
  active_consent text;
  consent_expires_at timestamptz;
  suppression_exists boolean;
  result jsonb;
begin
  normalized_phone := public.normalize_ai_call_phone(requested_phone_number, '+91');

  if normalized_phone is null then
    return jsonb_build_object(
      'eligible', false,
      'reason_code', 'INVALID_PHONE',
      'reason', 'Phone number is invalid'
    );
  end if;

  if requested_campaign_id is not null then
    select *
    into campaign_record
    from public.ai_call_campaigns
    where id = requested_campaign_id
      and organization_id = requested_organization_id;

    if not found then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'CAMPAIGN_NOT_FOUND',
        'reason', 'Campaign not found'
      );
    end if;

    consent_required := campaign_record.consent_required;

    if campaign_record.status <> 'active' then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'CAMPAIGN_NOT_ACTIVE',
        'reason', 'Campaign is not active'
      );
    end if;

    local_time := (requested_at at time zone campaign_record.timezone)::time;
    local_dow := extract(isodow from requested_at at time zone campaign_record.timezone)::integer;

    if not local_dow = any(campaign_record.allowed_weekdays) then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'WEEKDAY_NOT_ALLOWED',
        'reason', 'Calling is not allowed on this weekday'
      );
    end if;

    if local_time < campaign_record.calling_window_start
       or local_time > campaign_record.calling_window_end then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'OUTSIDE_CALLING_WINDOW',
        'reason', 'Current time is outside the campaign calling window'
      );
    end if;
  end if;

  select exists (
    select 1
    from public.ai_call_suppression_list suppression
    where suppression.organization_id = requested_organization_id
      and public.normalize_ai_call_phone(suppression.phone_number, '+91') = normalized_phone
      and suppression.is_active = true
      and suppression.active_from <= requested_at
      and (
        suppression.active_until is null
        or suppression.active_until > requested_at
      )
  )
  into suppression_exists;

  if suppression_exists then
    return jsonb_build_object(
      'eligible', false,
      'reason_code', 'SUPPRESSED',
      'reason', 'Phone number is on the suppression list'
    );
  end if;

  if consent_required then
    select consent.consent_status, consent.expires_at
    into active_consent, consent_expires_at
    from public.ai_call_consents consent
    where consent.organization_id = requested_organization_id
      and public.normalize_ai_call_phone(consent.phone_number, '+91') = normalized_phone
      and consent.consent_type = 'outbound_ai_call'
    order by consent.created_at desc, consent.id desc
    limit 1;

    if coalesce(active_consent, 'unknown') <> 'granted'
      or consent_expires_at <= requested_at then
      return jsonb_build_object(
        'eligible', false,
        'reason_code', 'CONSENT_NOT_GRANTED',
        'reason', 'Outbound AI call consent is not granted',
        'consent_status', coalesce(active_consent, 'unknown')
      );
    end if;
  end if;

  result := jsonb_build_object(
    'eligible', true,
    'reason_code', 'ELIGIBLE',
    'reason', 'Call is eligible',
    'normalized_phone', normalized_phone
  );

  return result;
end;
$$;

create or replace function public.claim_ai_call_job(
  requested_worker_id text,
  requested_organization_id uuid default null,
  requested_lock_minutes integer default 10
)
returns public.ai_call_jobs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.ai_call_jobs;
begin
  if requested_worker_id is null or btrim(requested_worker_id) = '' then
    raise exception 'Worker ID is required';
  end if;

  if auth.role() is distinct from 'service_role'
    and (
      requested_organization_id is null
      or not public.has_organization_permission(
        requested_organization_id,
        'ai_calling.execute'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into target_job
  from public.ai_call_jobs job
  where job.status in ('queued','scheduled')
    and not job.dispatch_requires_reconciliation
    and coalesce(job.scheduled_at, now()) <= now()
    and (job.expires_at is null or job.expires_at > now())
    and job.attempt_count < job.maximum_attempts
    and (
      requested_organization_id is null
      or job.organization_id = requested_organization_id
    )
  order by
    job.priority asc,
    coalesce(job.scheduled_at, job.created_at) asc,
    job.created_at asc
  for update skip locked
  limit 1;

  if not found then
    return null;
  end if;

  update public.ai_call_jobs
  set
    status = 'dispatching',
    started_at = coalesce(started_at, now()),
    metadata = metadata || jsonb_build_object(
      'claimed_by', requested_worker_id,
      'claimed_at', now(),
      'claim_expires_at', now() + make_interval(mins => greatest(requested_lock_minutes, 1))
    ),
    updated_at = now()
  where id = target_job.id
  returning *
  into target_job;

  return target_job;
end;
$$;

create or replace function public.start_ai_call_attempt(
  requested_call_job_id uuid,
  requested_provider_request jsonb default '{}'::jsonb,
  requested_from_phone_number text default null
)
returns public.ai_call_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_job public.ai_call_jobs;
  created_attempt public.ai_call_attempts;
  next_attempt_number integer;
begin
  select *
  into target_job
  from public.ai_call_jobs job
  where job.id = requested_call_job_id
  for update;

  if not found then
    raise exception 'AI call job not found';
  end if;

  if auth.role() is distinct from 'service_role'
    and not public.has_organization_permission(
      target_job.organization_id,
      'ai_calling.execute'
    ) then
    raise exception 'Permission denied';
  end if;

  if target_job.status not in ('queued','scheduled','dispatching','failed') then
    raise exception 'Call job cannot start from status %', target_job.status;
  end if;

  if target_job.attempt_count >= target_job.maximum_attempts then
    raise exception 'Maximum call attempts exhausted';
  end if;

  if target_job.dispatch_requires_reconciliation or exists (
    select 1 from public.ai_call_attempts
    where call_job_id = target_job.id
      and status in ('created','dispatching','initiated','ringing','answered','in_progress')
  ) then
    raise exception 'An existing call attempt must be reconciled before dispatch';
  end if;

  next_attempt_number := target_job.attempt_count + 1;

  insert into public.ai_call_attempts (
    organization_id,
    call_job_id,
    attempt_number,
    provider_connection_id,
    status,
    from_phone_number,
    to_phone_number,
    provider_request,
    dispatched_at
  )
  values (
    target_job.organization_id,
    target_job.id,
    next_attempt_number,
    target_job.provider_connection_id,
    'dispatching',
    requested_from_phone_number,
    target_job.phone_number,
    coalesce(requested_provider_request, '{}'::jsonb),
    now()
  )
  returning *
  into created_attempt;

  update public.ai_call_jobs
  set
    status = 'dispatching',
    attempt_count = next_attempt_number,
    next_attempt_at = null,
    updated_at = now()
  where id = target_job.id;

  return created_attempt;
end;
$$;

create or replace function public.authorize_ai_call_dispatch(
  requested_call_attempt_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.ai_call_attempts;
  target_job public.ai_call_jobs;
  eligibility jsonb;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Permission denied';
  end if;

  -- Match completion's attempt -> job lock order.
  select * into target_attempt from public.ai_call_attempts
  where id = requested_call_attempt_id for update;
  if not found then raise exception 'AI call attempt not found'; end if;

  select * into target_job from public.ai_call_jobs
  where id = target_attempt.call_job_id for update;
  if not found then raise exception 'AI call job not found'; end if;

  if target_job.dispatch_requires_reconciliation
    or target_attempt.status <> 'dispatching'
    or target_job.status <> 'dispatching'
    or target_attempt.attempt_number <> target_job.attempt_count then
    return jsonb_build_object('authorized', false, 'reason', 'RECONCILIATION_REQUIRED');
  end if;

  eligibility := public.check_ai_call_eligibility(
    target_job.organization_id, target_job.phone_number,
    target_job.lead_id, target_job.campaign_id, clock_timestamp()
  );
  if not exists (
    select 1 from public.ai_call_provider_connections c
    join public.ai_call_providers p on p.id = c.provider_id
    where c.id = target_job.provider_connection_id
      and c.organization_id = target_job.organization_id
      and c.status = 'active' and p.status = 'active'
  ) or not exists (
    select 1 from public.ai_call_script_templates s
    where s.id = target_job.script_template_id
      and s.organization_id = target_job.organization_id and s.status = 'active'
  ) then
    eligibility := jsonb_build_object('eligible', false, 'reason_code', 'CONFIGURATION_INACTIVE');
  end if;
  if target_job.expires_at <= clock_timestamp() then
    eligibility := jsonb_build_object('eligible', false, 'reason_code', 'JOB_EXPIRED');
  end if;

  if (eligibility->>'eligible')::boolean is distinct from true then
    update public.ai_call_jobs set status = 'blocked', next_attempt_at = null,
      blocked_reason = eligibility->>'reason_code',
      error_data = coalesce(error_data, '{}'::jsonb) || jsonb_build_object(
        'dispatch_eligibility', eligibility), updated_at = now()
    where id = target_job.id;
    update public.ai_call_attempts set status = 'cancelled',
      error_code = 'dispatch_ineligible', error_data = eligibility,
      ended_at = now(), completed_at = now(), updated_at = now()
    where id = target_attempt.id;
    return jsonb_build_object('authorized', false, 'reason', 'INELIGIBLE');
  end if;

  update public.ai_call_jobs set dispatch_requires_reconciliation = true,
    metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'dispatch_authorized_at', clock_timestamp(),
      'dispatch_authorized_attempt_id', target_attempt.id),
    updated_at = now()
  where id = target_job.id;
  return jsonb_build_object('authorized', true);
end;
$$;

revoke all on function public.authorize_ai_call_dispatch(uuid) from public, authenticated;
grant execute on function public.authorize_ai_call_dispatch(uuid) to service_role;


create or replace function public.mark_ai_call_initiated(
  requested_call_attempt_id uuid,
  requested_provider_call_id text,
  requested_provider_response jsonb default '{}'::jsonb,
  requested_provider_batch_id text default null
)
returns public.ai_call_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.ai_call_attempts;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Permission denied';
  end if;
  select *
  into target_attempt
  from public.ai_call_attempts attempt
  where attempt.id = requested_call_attempt_id
  for update;

  if not found then
    raise exception 'AI call attempt not found';
  end if;

  -- A verified terminal webhook may arrive before the dispatch response.
  if target_attempt.status in ('completed','failed','cancelled','no_answer','busy','voicemail','expired') then
    return target_attempt;
  end if;

  update public.ai_call_attempts
  set
    status = 'initiated',
    provider_call_id = requested_provider_call_id,
    provider_batch_id = requested_provider_batch_id,
    provider_response = coalesce(requested_provider_response, '{}'::jsonb),
    initiated_at = now(),
    updated_at = now()
  where id = target_attempt.id
  returning *
  into target_attempt;

  update public.ai_call_jobs
  set
    status = 'in_progress',
    dispatch_requires_reconciliation = false,
    updated_at = now()
  where id = target_attempt.call_job_id;

  insert into public.ai_call_attempt_events (
    organization_id,
    call_job_id,
    call_attempt_id,
    event_type,
    event_source,
    event_data
  )
  values (
    target_attempt.organization_id,
    target_attempt.call_job_id,
    target_attempt.id,
    'call.initiated',
    'provider',
    jsonb_build_object(
      'provider_call_id', requested_provider_call_id,
      'provider_batch_id', requested_provider_batch_id
    )
  );

  return target_attempt;
end;
$$;

create or replace function public.complete_ai_call_attempt(
  requested_call_attempt_id uuid,
  requested_status text,
  requested_disposition_code text default null,
  requested_call_duration_seconds integer default null,
  requested_recording_url text default null,
  requested_provider_cost numeric default null,
  requested_provider_currency text default null,
  requested_result_data jsonb default '{}'::jsonb,
  requested_error_code text default null,
  requested_error_message text default null,
  requested_error_data jsonb default '{}'::jsonb
)
returns public.ai_call_attempts
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.ai_call_attempts;
  target_job public.ai_call_jobs;
  terminal_success boolean := false;
  next_delay_minutes integer;
  next_time timestamptz;
  campaign_record public.ai_call_campaigns;
  final_job_status text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Permission denied';
  end if;
  if requested_status not in (
    'completed','failed','cancelled','no_answer','busy','voicemail','expired'
  ) then
    raise exception 'Invalid terminal call attempt status';
  end if;

  select *
  into target_attempt
  from public.ai_call_attempts attempt
  where attempt.id = requested_call_attempt_id
  for update;

  if not found then
    raise exception 'AI call attempt not found';
  end if;

  -- Duplicate or late completion must not reschedule a job or clear a newer hold.
  if target_attempt.status in ('completed','failed','cancelled','no_answer','busy','voicemail','expired') then
    return target_attempt;
  end if;

  select *
  into target_job
  from public.ai_call_jobs job
  where job.id = target_attempt.call_job_id
  for update;

  select coalesce(disposition.is_success, false)
  into terminal_success
  from public.ai_call_dispositions disposition
  where disposition.code = requested_disposition_code;

  terminal_success := coalesce(terminal_success, requested_status = 'completed');

  update public.ai_call_attempts
  set
    status = requested_status,
    disposition_code = requested_disposition_code,
    call_duration_seconds = requested_call_duration_seconds,
    recording_url = requested_recording_url,
    provider_cost = requested_provider_cost,
    provider_currency = requested_provider_currency,
    error_code = requested_error_code,
    error_message = requested_error_message,
    error_data = coalesce(requested_error_data, '{}'::jsonb),
    call_metrics = call_metrics || coalesce(requested_result_data, '{}'::jsonb),
    ended_at = coalesce(ended_at, now()),
    completed_at = now(),
    updated_at = now()
  where id = target_attempt.id
  returning *
  into target_attempt;

  if target_job.campaign_id is not null then
    select *
    into campaign_record
    from public.ai_call_campaigns campaign
    where campaign.id = target_job.campaign_id;
  end if;

  if terminal_success then
    final_job_status := 'completed';
    next_time := null;
  elsif target_job.attempt_count < target_job.maximum_attempts
    and requested_status in ('failed','no_answer','busy','voicemail') then

    if campaign_record.id is not null
      and array_length(campaign_record.retry_delays_minutes, 1) is not null then

      next_delay_minutes :=
        campaign_record.retry_delays_minutes[
          least(
            target_job.attempt_count,
            array_length(campaign_record.retry_delays_minutes, 1)
          )
        ];
    else
      next_delay_minutes := 60 * greatest(target_job.attempt_count, 1);
    end if;

    final_job_status := 'scheduled';
    next_time := now() + make_interval(mins => greatest(next_delay_minutes, 1));
  else
    final_job_status := 'failed';
    next_time := null;
  end if;

  update public.ai_call_jobs
  set
    status = final_job_status,
    dispatch_requires_reconciliation = false,
    final_disposition_code = requested_disposition_code,
    next_attempt_at = next_time,
    scheduled_at = case
      when final_job_status = 'scheduled' then next_time
      else scheduled_at
    end,
    result_data = result_data || coalesce(requested_result_data, '{}'::jsonb),
    error_data = case
      when requested_error_code is null and requested_error_message is null
        then error_data
      else coalesce(requested_error_data, '{}'::jsonb)
        || jsonb_build_object(
          'code', requested_error_code,
          'message', requested_error_message
        )
    end,
    completed_at = case
      when final_job_status in ('completed','failed') then now()
      else completed_at
    end,
    updated_at = now()
  where id = target_job.id
  returning *
  into target_job;

  insert into public.ai_call_attempt_events (
    organization_id,
    call_job_id,
    call_attempt_id,
    event_type,
    event_source,
    event_data
  )
  values (
    target_attempt.organization_id,
    target_attempt.call_job_id,
    target_attempt.id,
    'call.' || requested_status,
    'system',
    jsonb_build_object(
      'disposition_code', requested_disposition_code,
      'job_status', final_job_status,
      'next_attempt_at', next_time,
      'error_code', requested_error_code,
      'error_message', requested_error_message
    )
  );

  return target_attempt;
end;
$$;

revoke all on function public.mark_ai_call_initiated(uuid,text,jsonb,text) from public, authenticated;
grant execute on function public.mark_ai_call_initiated(uuid,text,jsonb,text) to service_role;
revoke all on function public.complete_ai_call_attempt(uuid,text,text,integer,text,numeric,text,jsonb,text,text,jsonb) from public, authenticated;
grant execute on function public.complete_ai_call_attempt(uuid,text,text,integer,text,numeric,text,jsonb,text,text,jsonb) to service_role;
