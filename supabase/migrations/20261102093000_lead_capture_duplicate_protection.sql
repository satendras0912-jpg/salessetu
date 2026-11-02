-- =========================================================
-- SalesSetu Enterprise
-- Lead capture duplicate protection
-- A same-day repeat enquiry for the same route, phone and project
-- resolves to the existing intake/lead instead of creating a new lead.
-- =========================================================

begin;

create or replace function public.lead_capture_fallback_idempotency_key(
  p_route_key text,
  p_phone text,
  p_preferred_project text,
  p_received_at timestamptz default now()
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when nullif(
      regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'),
      ''
    ) is null then null
    else 'daily:' || encode(
      extensions.digest(
        concat_ws(
          '|',
          'lead-capture-v1',
          lower(btrim(coalesce(p_route_key, ''))),
          regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'),
          lower(btrim(coalesce(p_preferred_project, ''))),
          (coalesce(p_received_at, now()) at time zone 'Asia/Kolkata')::date::text
        ),
        'sha256'
      ),
      'hex'
    )
  end;
$$;

create or replace function public.normalize_lead_capture_intake()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  supplied_key text;
begin
  new.route_key := lower(btrim(coalesce(new.route_key, '')));

  if new.route_key = '' then
    raise exception 'A lead capture route key is required';
  end if;

  new.received_at := coalesce(new.received_at, now());
  new.metadata := coalesce(new.metadata, '{}'::jsonb);

  supplied_key := nullif(
    btrim(
      coalesce(
        new.idempotency_key,
        new.metadata ->> 'idempotency_key',
        new.metadata ->> 'submission_id'
      )
    ),
    ''
  );

  new.idempotency_key := coalesce(
    supplied_key,
    public.lead_capture_fallback_idempotency_key(
      new.route_key,
      new.phone,
      new.preferred_project,
      new.received_at
    )
  );

  new.metadata := new.metadata || jsonb_strip_nulls(
    jsonb_build_object(
      'idempotency_key', new.idempotency_key,
      'idempotency_source',
        case
          when supplied_key is not null then 'provided'
          when new.idempotency_key is not null then 'daily_phone_project_fallback'
          else null
        end
    )
  );

  new.processing_status := coalesce(new.processing_status, 'pending');
  new.processing_attempts := coalesce(new.processing_attempts, 0);
  new.max_processing_attempts := greatest(
    1,
    least(10, coalesce(new.max_processing_attempts, 5))
  );

  return new;
end;
$$;

-- Seed a key for the earliest historical intake in each same-day
-- route/phone/project group. Existing lead records remain untouched.
with candidates as (
  select
    intake.id,
    public.lead_capture_fallback_idempotency_key(
      intake.route_key,
      intake.phone,
      intake.preferred_project,
      intake.received_at
    ) as generated_key,
    row_number() over (
      partition by
        intake.route_key,
        public.lead_capture_fallback_idempotency_key(
          intake.route_key,
          intake.phone,
          intake.preferred_project,
          intake.received_at
        )
      order by intake.received_at asc, intake.id asc
    ) as position_in_group
  from public.lead_capture_intake as intake
  where intake.idempotency_key is null
    and nullif(regexp_replace(coalesce(intake.phone, ''), '[^0-9]', '', 'g'), '') is not null
)
update public.lead_capture_intake as intake
set
  idempotency_key = candidates.generated_key,
  metadata = coalesce(intake.metadata, '{}'::jsonb) || jsonb_build_object(
    'idempotency_key', candidates.generated_key,
    'idempotency_source', 'daily_phone_project_backfill'
  )
from candidates
where intake.id = candidates.id
  and candidates.position_in_group = 1
  and candidates.generated_key is not null;

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
  supplied_key text;
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

  supplied_key := nullif(
    btrim(
      coalesce(
        p_payload ->> 'idempotency_key',
        metadata_value ->> 'idempotency_key',
        metadata_value ->> 'submission_id'
      )
    ),
    ''
  );

  normalized_idempotency_key := coalesce(
    supplied_key,
    public.lead_capture_fallback_idempotency_key(
      normalized_route_key,
      p_payload ->> 'phone',
      p_payload ->> 'preferred_project',
      now()
    )
  );

  metadata_value := metadata_value || jsonb_strip_nulls(
    jsonb_build_object(
      'idempotency_key', normalized_idempotency_key,
      'idempotency_source',
        case
          when supplied_key is not null then 'provided'
          when normalized_idempotency_key is not null then 'daily_phone_project_fallback'
          else null
        end
    )
  );

  if normalized_idempotency_key is not null then
    select *
    into existing_record
    from public.lead_capture_intake
    where route_key = normalized_route_key
      and idempotency_key = normalized_idempotency_key
    order by received_at asc
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
      order by received_at asc
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
on function public.lead_capture_fallback_idempotency_key(text, text, text, timestamptz)
from public;

grant execute
on function public.lead_capture_fallback_idempotency_key(text, text, text, timestamptz)
to service_role;

revoke all
on function public.ingest_lead_capture_intake(jsonb)
from public;

grant execute
on function public.ingest_lead_capture_intake(jsonb)
to service_role;

commit;
