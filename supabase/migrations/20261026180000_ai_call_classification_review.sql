-- Require the dispatch guard migration first. Preserve its permissions and duplicate protection.
BEGIN;
DO $guard$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'ai_call_jobs'
      AND column_name = 'dispatch_requires_reconciliation'
  ) THEN
    RAISE EXCEPTION 'Apply 20261025120000_ai_call_dispatch_guard.sql first';
  END IF;
END;
$guard$;
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
  classification_review boolean := requested_status = 'voicemail'
    and coalesce(requested_result_data -> 'classification_review_required', 'false'::jsonb) = 'true'::jsonb;
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

  if classification_review then
    final_job_status := 'blocked';
    next_time := null;
  elsif terminal_success then
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
    dispatch_requires_reconciliation = classification_review,
    blocked_reason = case when classification_review then 'Call outcome conflicts with conversation evidence; classification review required.' else blocked_reason end,
    qualification_status = case when classification_review then 'manual_review' else qualification_status end,
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
revoke all on function public.complete_ai_call_attempt(uuid,text,text,integer,text,numeric,text,jsonb,text,text,jsonb) from public, authenticated;
grant execute on function public.complete_ai_call_attempt(uuid,text,text,integer,text,numeric,text,jsonb,text,text,jsonb) to service_role;
COMMIT;
