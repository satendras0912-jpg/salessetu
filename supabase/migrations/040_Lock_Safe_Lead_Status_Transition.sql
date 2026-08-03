-- ============================================================
-- Migration 040
-- Lock-safe lead status transition RPC v2
--
-- Purpose:
--   1. Avoid long row-lock waits that can surface as PostgREST
--      "upstream request timeout" responses.
--   2. Preserve optimistic concurrency with expected_updated_at.
--   3. Return a compact JSONB response instead of the complete
--      public.leads composite row.
--   4. Fail fast with SQLSTATE 40001 when another transition is
--      already changing the same lead.
-- ============================================================

begin;

create or replace function
  public.transition_lead_status_v2(
    requested_lead_id uuid,
    requested_status text,
    requested_lifecycle_stage text default null,
    requested_temperature text default null,
    requested_reason text default null,
    requested_expected_updated_at timestamptz default null
  )
returns jsonb
language plpgsql
security definer
set search_path to ''
set lock_timeout to '1500ms'
as $function$
declare
  target_lead public.leads;

  current_organization_id uuid;
  current_temperature text;
  current_updated_at timestamptz;

  target_temperature text;
begin
  if requested_lead_id is null then
    raise exception 'Lead ID is required';
  end if;

  if requested_status is null
    or btrim(requested_status) = '' then
    raise exception 'Lead status is required';
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
    raise exception 'Invalid lead status'
      using errcode = '23514';
  end if;

  if requested_lifecycle_stage is not null
    and requested_lifecycle_stage not in (
      'lead',
      'prospect',
      'opportunity',
      'customer',
      'lost'
    ) then
    raise exception 'Invalid lifecycle stage'
      using errcode = '23514';
  end if;

  /*
   * This initial read is intentionally not FOR UPDATE.
   * PostgreSQL MVCC can read the last committed row without
   * waiting for another transaction's row lock.
   */
  select
    lead.organization_id,
    lead.lead_temperature,
    lead.updated_at
  into
    current_organization_id,
    current_temperature,
    current_updated_at
  from public.leads lead
  where lead.id = requested_lead_id
    and lead.deleted_at is null;

  if not found then
    raise exception 'Lead not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      current_organization_id,
      'leads.update'
    ) then
    raise exception 'Permission denied'
      using errcode = '42501';
  end if;

  if requested_temperature is null then
    target_temperature :=
      current_temperature;

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
    raise exception 'Invalid lead temperature'
      using errcode = '23514';
  end if;

  /*
   * Fast stale-form rejection before attempting the UPDATE.
   * The UPDATE below repeats the same predicate, which is the
   * authoritative optimistic-concurrency check.
   */
  if requested_expected_updated_at is not null
    and current_updated_at is distinct from
      requested_expected_updated_at then
    raise exception
      'Lead changed after the form was opened'
      using errcode = '40001';
  end if;

  begin
    update public.leads lead
    set
      lead_status = requested_status,

      lifecycle_stage =
        coalesce(
          requested_lifecycle_stage,
          lead.lifecycle_stage
        ),

      lead_temperature =
        target_temperature,

      metadata =
        coalesce(
          lead.metadata,
          '{}'::jsonb
        )
        ||
        jsonb_build_object(
          'last_status_change_reason',
            nullif(
              btrim(
                coalesce(
                  requested_reason,
                  ''
                )
              ),
              ''
            ),

          'last_status_changed_by',
            auth.uid(),

          'last_status_changed_at',
            clock_timestamp()
        ),

      updated_by = auth.uid(),
      updated_at = clock_timestamp()

    where lead.id = requested_lead_id
      and lead.deleted_at is null
      and (
        requested_expected_updated_at is null
        or lead.updated_at is not distinct from
          requested_expected_updated_at
      )

    returning lead.*
    into target_lead;

  exception
    when lock_not_available then
      raise exception
        'Lead is currently being changed by another request'
        using errcode = '40001';
  end;

  if not found then
    /*
     * The row still exists, but the expected timestamp no
     * longer matches. Treat this as an optimistic-concurrency
     * conflict instead of retrying or waiting.
     */
    select lead.updated_at
    into current_updated_at
    from public.leads lead
    where lead.id = requested_lead_id
      and lead.deleted_at is null;

    if not found then
      raise exception 'Lead not found';
    end if;

    raise exception
      'Lead changed after the form was opened'
      using errcode = '40001';
  end if;

  return jsonb_build_object(
    'lead_id',
      target_lead.id,

    'updated_at',
      target_lead.updated_at,

    'lead_status',
      target_lead.lead_status,

    'lifecycle_stage',
      target_lead.lifecycle_stage,

    'lead_temperature',
      target_lead.lead_temperature
  );
end;
$function$;

comment on function
  public.transition_lead_status_v2(
    uuid,
    text,
    text,
    text,
    text,
    timestamptz
  )
is
  'Lock-safe, optimistic-concurrency lead status transition. Returns a compact JSONB result and fails fast on concurrent row locks.';

revoke all on function
  public.transition_lead_status_v2(
    uuid,
    text,
    text,
    text,
    text,
    timestamptz
  )
from public;

revoke all on function
  public.transition_lead_status_v2(
    uuid,
    text,
    text,
    text,
    text,
    timestamptz
  )
from anon;

grant execute on function
  public.transition_lead_status_v2(
    uuid,
    text,
    text,
    text,
    text,
    timestamptz
  )
to authenticated;

grant execute on function
  public.transition_lead_status_v2(
    uuid,
    text,
    text,
    text,
    text,
    timestamptz
  )
to service_role;

notify pgrst, 'reload schema';

do $verification$
declare
  function_oid oid;
begin
  select function_row.oid
  into function_oid
  from pg_proc function_row

  join pg_namespace schema_row
    on schema_row.oid =
      function_row.pronamespace

  where schema_row.nspname = 'public'
    and function_row.proname =
      'transition_lead_status_v2'

    and pg_get_function_identity_arguments(
      function_row.oid
    ) =
      'requested_lead_id uuid, requested_status text, requested_lifecycle_stage text, requested_temperature text, requested_reason text, requested_expected_updated_at timestamp with time zone';

  if function_oid is null then
    raise exception
      'Verification failed: transition_lead_status_v2 is missing.';
  end if;

  if has_function_privilege(
    'anon',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Verification failed: anon can execute transition_lead_status_v2.';
  end if;

  if not has_function_privilege(
    'authenticated',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Verification failed: authenticated cannot execute transition_lead_status_v2.';
  end if;

  if not has_function_privilege(
    'service_role',
    function_oid,
    'EXECUTE'
  ) then
    raise exception
      'Verification failed: service_role cannot execute transition_lead_status_v2.';
  end if;

  raise notice
    'Migration 040 verified: lock-safe lead status transition v2 installed.';
end;
$verification$;

commit;