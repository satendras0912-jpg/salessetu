-- =========================================================
-- SalesSetu Enterprise
-- Lead capture reliability guard
-- Idempotency, retry queue and owner-visible failure alerts.
-- Auto-routing remains intentionally disabled.
-- =========================================================

begin;

alter table public.lead_capture_intake
  add column if not exists idempotency_key text,
  add column if not exists processing_status text not null default 'pending',
  add column if not exists processing_attempts integer not null default 0,
  add column if not exists max_processing_attempts integer not null default 5,
  add column if not exists last_attempt_at timestamptz,
  add column if not exists retry_after timestamptz,
  add column if not exists failure_code text,
  add column if not exists failure_detail text;

alter table public.lead_capture_intake
  drop constraint if exists lead_capture_intake_processing_status_check,
  add constraint lead_capture_intake_processing_status_check
    check (processing_status in ('pending', 'processing', 'processed', 'retryable', 'failed'));

alter table public.lead_capture_intake
  drop constraint if exists lead_capture_intake_processing_attempts_check,
  add constraint lead_capture_intake_processing_attempts_check
    check (
      processing_attempts >= 0
      and max_processing_attempts between 1 and 10
      and processing_attempts <= max_processing_attempts
    );

create unique index if not exists lead_capture_intake_idempotency_idx
  on public.lead_capture_intake (route_key, idempotency_key)
  where idempotency_key is not null;

create index if not exists lead_capture_intake_retry_idx
  on public.lead_capture_intake (
    processing_status,
    retry_after,
    received_at
  )
  where processing_status in ('pending', 'retryable');

create or replace function public.normalize_lead_capture_intake()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.route_key := lower(btrim(coalesce(new.route_key, '')));

  if new.route_key = '' then
    raise exception 'A lead capture route key is required';
  end if;

  new.idempotency_key := nullif(
    btrim(
      coalesce(
        new.idempotency_key,
        coalesce(new.metadata, '{}'::jsonb) ->> 'idempotency_key',
        coalesce(new.metadata, '{}'::jsonb) ->> 'submission_id'
      )
    ),
    ''
  );

  new.metadata := coalesce(new.metadata, '{}'::jsonb);
  new.processing_status := coalesce(new.processing_status, 'pending');
  new.processing_attempts := coalesce(new.processing_attempts, 0);
  new.max_processing_attempts := greatest(
    1,
    least(10, coalesce(new.max_processing_attempts, 5))
  );

  return new;
end;
$$;

drop trigger if exists lead_capture_intake_normalize
  on public.lead_capture_intake;

create trigger lead_capture_intake_normalize
before insert on public.lead_capture_intake
for each row
execute function public.normalize_lead_capture_intake();

create or replace function public.create_lead_capture_failure_notification(
  p_intake_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  intake_record public.lead_capture_intake;
  route_record public.lead_capture_routes;
  category_id_value uuid;
  notification_job_id uuid;
  recipient_id_value uuid;
  owner_record record;
  recipient_total integer := 0;
  notification_key text;
  notification_body text;
begin
  select *
  into intake_record
  from public.lead_capture_intake
  where id = p_intake_id;

  if not found or intake_record.processing_status not in ('retryable', 'failed') then
    return;
  end if;

  select *
  into route_record
  from public.lead_capture_routes
  where route_key = intake_record.route_key
  limit 1;

  if not found then
    -- An unknown route is retained in the retry queue for investigation,
    -- but cannot be assigned to a tenant owner safely.
    return;
  end if;

  notification_key := 'lead_capture_failure:' || intake_record.id::text;

  if exists (
    select 1
    from public.notification_jobs
    where organization_id = route_record.organization_id
      and idempotency_key = notification_key
  ) then
    return;
  end if;

  select id
  into category_id_value
  from public.notification_categories
  where organization_id is null
    and category_code = 'system_alert'
    and status = 'active'
  limit 1;

  notification_body :=
    'A website lead capture for route '
    || intake_record.route_key
    || ' could not be processed. '
    || coalesce(
      nullif(btrim(intake_record.failure_detail), ''),
      'Review the capture retry queue.'
    );

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
    metadata
  )
  values (
    route_record.organization_id,
    category_id_value,
    'lead_capture',
    'lead_capture_intake',
    intake_record.id,
    intake_record.id::text,
    'lead.capture.failed',
    notification_key,
    intake_record.id::text,
    intake_record.id::text,
    'Lead capture needs attention',
    notification_body,
    'Lead capture needs attention',
    notification_body,
    jsonb_build_object(
      'intake_id', intake_record.id,
      'route_key', intake_record.route_key,
      'processing_status', intake_record.processing_status,
      'processing_attempts', intake_record.processing_attempts,
      'failure_code', intake_record.failure_code
    ),
    '[]'::jsonb,
    '/dashboard/leads',
    'error',
    10,
    'processing',
    0,
    0,
    now(),
    null,
    jsonb_build_object(
      'channel_codes', array['in_app']::text[],
      'delivery_source', 'lead_capture_reliability_guard'
    )
  )
  returning id
  into notification_job_id;

  for owner_record in
    select member.user_id
    from public.organization_members member
    where member.organization_id = route_record.organization_id
      and member.membership_status = 'active'
      and member.is_owner = true
  loop
    insert into public.notification_recipients (
      organization_id,
      notification_job_id,
      recipient_type,
      user_id,
      status,
      delivered_at,
      metadata
    )
    values (
      route_record.organization_id,
      notification_job_id,
      'user',
      owner_record.user_id,
      'delivered',
      now(),
      jsonb_build_object('recipient_scope', 'workspace_owner')
    )
    returning id
    into recipient_id_value;

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
      route_record.organization_id,
      notification_job_id,
      recipient_id_value,
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
      route_record.organization_id,
      owner_record.user_id,
      notification_job_id,
      recipient_id_value,
      'Lead capture needs attention',
      notification_body,
      'system_alert',
      'error',
      10,
      '/dashboard/leads',
      '[]'::jsonb,
      jsonb_build_object(
        'intake_id', intake_record.id,
        'route_key', intake_record.route_key,
        'source_module', 'lead_capture'
      )
    );

    recipient_total := recipient_total + 1;
  end loop;

  update public.notification_jobs
  set
    status = 'delivered',
    recipient_count = recipient_total,
    delivered_count = recipient_total,
    completed_at = now(),
    updated_at = now()
  where id = notification_job_id;
end;
$$;

revoke all
on function public.create_lead_capture_failure_notification(uuid)
from public;

grant execute
on function public.create_lead_capture_failure_notification(uuid)
to service_role;

create or replace function public.attempt_lead_capture_intake(
  p_intake_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  intake_record public.lead_capture_intake;
  route_record public.lead_capture_routes;
  target_lead_id uuid;
  attempt_number integer;
  failure_state text;
  failure_message text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may process lead capture intake';
  end if;

  select *
  into intake_record
  from public.lead_capture_intake
  where id = p_intake_id
  for update;

  if not found then
    raise exception 'Lead capture intake record not found';
  end if;

  if intake_record.processed_lead_id is not null
    or intake_record.processing_status = 'processed' then
    return jsonb_build_object(
      'intake_id', intake_record.id,
      'status', 'processed',
      'lead_id', intake_record.processed_lead_id,
      'duplicate', true
    );
  end if;

  if intake_record.processing_attempts >= intake_record.max_processing_attempts then
    update public.lead_capture_intake
    set
      processing_status = 'failed',
      retry_after = null
    where id = intake_record.id;

    perform public.create_lead_capture_failure_notification(intake_record.id);

    return jsonb_build_object(
      'intake_id', intake_record.id,
      'status', 'failed',
      'lead_id', null,
      'duplicate', false
    );
  end if;

  attempt_number := intake_record.processing_attempts + 1;

  update public.lead_capture_intake
  set
    processing_status = 'processing',
    processing_attempts = attempt_number,
    last_attempt_at = now(),
    retry_after = null,
    failure_code = null,
    failure_detail = null
  where id = intake_record.id;

  begin
    select *
    into route_record
    from public.lead_capture_routes
    where route_key = intake_record.route_key
      and is_active = true
    for share;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'No active SalesSetu lead capture route matches this key';
    end if;

    insert into public.leads (
      organization_id,
      lead_source_id,
      full_name,
      phone,
      preferred_project,
      preferred_location,
      campaign_name,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_term,
      utm_content,
      landing_page_url,
      referrer_url,
      external_provider,
      custom_fields,
      metadata
    )
    values (
      route_record.organization_id,
      route_record.lead_source_id,
      nullif(btrim(intake_record.full_name), ''),
      nullif(btrim(intake_record.phone), ''),
      nullif(btrim(intake_record.preferred_project), ''),
      nullif(btrim(intake_record.preferred_location), ''),
      coalesce(
        nullif(btrim(intake_record.campaign_name), ''),
        nullif(btrim(intake_record.campaign), ''),
        nullif(btrim(intake_record.utm_campaign), '')
      ),
      nullif(btrim(intake_record.utm_source), ''),
      nullif(btrim(intake_record.utm_medium), ''),
      nullif(btrim(intake_record.utm_campaign), ''),
      nullif(btrim(intake_record.utm_term), ''),
      nullif(btrim(intake_record.utm_content), ''),
      nullif(btrim(intake_record.landing_page_url), ''),
      nullif(btrim(intake_record.referrer_url), ''),
      'n8n_sales_lead_attribution',
      jsonb_strip_nulls(
        jsonb_build_object(
          'source', nullif(btrim(intake_record.source), ''),
          'medium', nullif(btrim(intake_record.medium), ''),
          'campaign', nullif(btrim(intake_record.campaign), '')
        )
      ),
      intake_record.metadata
        || jsonb_build_object(
          'capture_route_key', route_record.route_key,
          'capture_intake_id', intake_record.id,
          'captured_via', 'n8n',
          'idempotency_key', intake_record.idempotency_key
        )
    )
    returning id
    into target_lead_id;

    update public.lead_capture_intake
    set
      route_key = route_record.route_key,
      processed_lead_id = target_lead_id,
      processed_at = now(),
      processing_status = 'processed',
      retry_after = null,
      failure_code = null,
      failure_detail = null
    where id = intake_record.id;

    return jsonb_build_object(
      'intake_id', intake_record.id,
      'status', 'processed',
      'lead_id', target_lead_id,
      'duplicate', false
    );
  exception
    when others then
      get stacked diagnostics
        failure_state = returned_sqlstate,
        failure_message = message_text;

      update public.lead_capture_intake
      set
        processing_status = case
          when attempt_number >= max_processing_attempts then 'failed'
          else 'retryable'
        end,
        retry_after = case
          when attempt_number >= max_processing_attempts then null
          else now() + make_interval(
            mins => least(30, power(2, greatest(attempt_number - 1, 0))::integer)
          )
        end,
        failure_code = failure_state,
        failure_detail = left(failure_message, 1000)
      where id = intake_record.id;

      begin
        perform public.create_lead_capture_failure_notification(
          intake_record.id
        );
      exception
        when others then
          raise warning
            'Lead capture failure notification could not be created: %',
            SQLERRM;
      end;

      return jsonb_build_object(
        'intake_id', intake_record.id,
        'status', case
          when attempt_number >= intake_record.max_processing_attempts
            then 'failed'
          else 'retryable'
        end,
        'lead_id', null,
        'duplicate', false,
        'failure_code', failure_state
      );
  end;
end;
$$;

revoke all
on function public.attempt_lead_capture_intake(uuid)
from public;

grant execute
on function public.attempt_lead_capture_intake(uuid)
to service_role;

create or replace function public.enqueue_lead_capture_intake_processing()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.attempt_lead_capture_intake(new.id);
  return new;
end;
$$;

drop trigger if exists lead_capture_intake_process
  on public.lead_capture_intake;

drop trigger if exists lead_capture_intake_enqueue_processing
  on public.lead_capture_intake;

create trigger lead_capture_intake_enqueue_processing
after insert on public.lead_capture_intake
for each row
execute function public.enqueue_lead_capture_intake_processing();

create or replace function public.retry_lead_capture_intakes(
  p_limit integer default 25
)
returns table (
  intake_id uuid,
  processing_status text,
  processed_lead_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  intake_id_value uuid;
  result jsonb;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may retry lead capture intake';
  end if;

  for intake_id_value in
    select id
    from public.lead_capture_intake
    where processing_status in ('pending', 'retryable')
      and processed_lead_id is null
      and (
        retry_after is null
        or retry_after <= now()
      )
    order by received_at asc
    limit greatest(1, least(coalesce(p_limit, 25), 100))
    for update skip locked
  loop
    result := public.attempt_lead_capture_intake(intake_id_value);

    return query
    select
      intake_id_value,
      result ->> 'status',
      nullif(result ->> 'lead_id', '')::uuid;
  end loop;
end;
$$;

revoke all
on function public.retry_lead_capture_intakes(integer)
from public;

grant execute
on function public.retry_lead_capture_intakes(integer)
to service_role;

create or replace function public.ingest_lead_capture_intake(
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_route_key text;
  normalized_idempotency_key text;
  metadata_value jsonb;
  existing_record public.lead_capture_intake;
  inserted_record public.lead_capture_intake;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may ingest lead capture intake';
  end if;

  normalized_route_key := lower(
    btrim(coalesce(p_payload ->> 'route_key', ''))
  );

  if normalized_route_key = '' then
    raise exception 'A lead capture route key is required';
  end if;

  metadata_value := case
    when jsonb_typeof(p_payload -> 'metadata') = 'object'
      then p_payload -> 'metadata'
    else '{}'::jsonb
  end;

  normalized_idempotency_key := nullif(
    btrim(
      coalesce(
        p_payload ->> 'idempotency_key',
        metadata_value ->> 'idempotency_key',
        metadata_value ->> 'submission_id'
      )
    ),
    ''
  );

  if normalized_idempotency_key is not null then
    select *
    into existing_record
    from public.lead_capture_intake
    where route_key = normalized_route_key
      and idempotency_key = normalized_idempotency_key
    limit 1;

    if found then
      return jsonb_build_object(
        'intake_id', existing_record.id,
        'status', existing_record.processing_status,
        'lead_id', existing_record.processed_lead_id,
        'duplicate', true
      );
    end if;
  end if;

  begin
    insert into public.lead_capture_intake (
      route_key,
      idempotency_key,
      full_name,
      phone,
      preferred_project,
      preferred_location,
      campaign_name,
      utm_source,
      utm_medium,
      utm_campaign,
      utm_term,
      utm_content,
      landing_page_url,
      referrer_url,
      source,
      medium,
      campaign,
      metadata
    )
    values (
      normalized_route_key,
      normalized_idempotency_key,
      p_payload ->> 'full_name',
      p_payload ->> 'phone',
      p_payload ->> 'preferred_project',
      p_payload ->> 'preferred_location',
      p_payload ->> 'campaign_name',
      p_payload ->> 'utm_source',
      p_payload ->> 'utm_medium',
      p_payload ->> 'utm_campaign',
      p_payload ->> 'utm_term',
      p_payload ->> 'utm_content',
      p_payload ->> 'landing_page_url',
      p_payload ->> 'referrer_url',
      p_payload ->> 'source',
      p_payload ->> 'medium',
      p_payload ->> 'campaign',
      metadata_value
    )
    returning *
    into inserted_record;
  exception
    when unique_violation then
      select *
      into existing_record
      from public.lead_capture_intake
      where route_key = normalized_route_key
        and idempotency_key = normalized_idempotency_key
      limit 1;

      if found then
        return jsonb_build_object(
          'intake_id', existing_record.id,
          'status', existing_record.processing_status,
          'lead_id', existing_record.processed_lead_id,
          'duplicate', true
        );
      end if;

      raise;
  end;

  select *
  into inserted_record
  from public.lead_capture_intake
  where id = inserted_record.id;

  return jsonb_build_object(
    'intake_id', inserted_record.id,
    'status', inserted_record.processing_status,
    'lead_id', inserted_record.processed_lead_id,
    'duplicate', false
  );
end;
$$;

revoke all
on function public.ingest_lead_capture_intake(jsonb)
from public;

grant execute
on function public.ingest_lead_capture_intake(jsonb)
to service_role;

commit;
