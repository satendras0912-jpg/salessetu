-- ============================================================================
-- Migration: 043_Site_Visit_Operational_Concurrency_Hardening
-- Purpose:
--   1. Harden Site Visit operational RPCs with optimistic concurrency.
--   2. Replace SQLSTATE 40001 stale-form errors with application-safe P0001.
--   3. Retire legacy check-in/check-out/complete RPC signatures that could
--      bypass optimistic concurrency.
--   4. Prevent an agent check-in from falsely marking the customer checked in.
--   5. Correct assignment audit ownership on reassignment.
--   6. Add lifecycle guards for operational Site Visit mutations.
-- ============================================================================

begin;

set local search_path = public, pg_temp;

lock table public.site_visits
in share row exclusive mode;

-- ============================================================================
-- 1. FIX SITE-VISIT SYSTEM-MANAGED FIELDS
--
-- Important corrections:
--   - status = checked_in must NOT automatically set customer_checked_in_at.
--     The check-in RPC explicitly records the party that actually checked in.
--
--   - Reassigning an agent must update assigned_by to the current actor.
--     The previous implementation could retain the original assigned_by.
-- ============================================================================

create or replace function
public.set_site_visit_system_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT' then
    if new.assigned_agent_id is not null then
      new.assigned_at :=
        coalesce(
          new.assigned_at,
          now()
        );

      new.assigned_by :=
        coalesce(
          new.assigned_by,
          auth.uid()
        );
    end if;

    if new.status = 'confirmed' then
      new.confirmed_at :=
        coalesce(
          new.confirmed_at,
          now()
        );
    end if;

    return new;
  end if;

  if new.assigned_agent_id
    is distinct from old.assigned_agent_id then

    new.assigned_at :=
      case
        when new.assigned_agent_id is null
          then null
        else now()
      end;

    new.assigned_by :=
      case
        when new.assigned_agent_id is null
          then null
        else auth.uid()
      end;
  end if;

  if new.status is distinct from old.status then
    if new.status = 'confirmed' then
      new.confirmed_at :=
        coalesce(
          new.confirmed_at,
          now()
        );
    end if;

    -- Do NOT infer customer check-in from status alone.
    -- check_in_site_visit() records the actual party explicitly.

    if new.status = 'in_progress' then
      new.visit_started_at :=
        coalesce(
          new.visit_started_at,
          now()
        );
    end if;

    if new.status = 'completed' then
      new.visit_completed_at :=
        coalesce(
          new.visit_completed_at,
          now()
        );
    end if;

    if new.status = 'cancelled' then
      new.cancelled_at :=
        coalesce(
          new.cancelled_at,
          now()
        );

      new.cancelled_by :=
        coalesce(
          new.cancelled_by,
          auth.uid()
        );
    end if;
  end if;

  return new;
end;
$function$;

-- ============================================================================
-- 2. HARDEN SITE-VISIT ASSIGNMENT RPC
-- ============================================================================

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
    raise exception
      'Site visit not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_visit.organization_id,
      'site_visits.assign'
    ) then
    raise exception
      'Permission denied';
  end if;

  if requested_expected_updated_at is null then
    raise exception
      'Expected update timestamp is required';
  end if;

  if target_visit.updated_at
    is distinct from requested_expected_updated_at then
    raise exception
      'Site visit changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if target_visit.status in (
    'completed',
    'cancelled',
    'no_show',
    'failed'
  ) then
    raise exception
      'Site visit cannot be assigned in status %',
      target_visit.status;
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
      coalesce(
        metadata,
        '{}'::jsonb
      ) ||
      jsonb_build_object(
        'last_assignment_reason',
        requested_reason
      ),

    updated_by =
      auth.uid(),

    updated_at =
      now()

  where id = target_visit.id

  returning *
  into target_visit;

  return target_visit;
end;
$function$;

-- ============================================================================
-- 3. HARDEN SITE-VISIT CANCELLATION RPC
-- ============================================================================

create or replace function public.cancel_site_visit(
  requested_site_visit_id uuid,
  requested_reason text,
  requested_expected_updated_at timestamptz default null
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
    raise exception
      'Site visit not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_visit.organization_id,
      'site_visits.cancel'
    ) then
    raise exception
      'Permission denied';
  end if;

  if requested_expected_updated_at is null then
    raise exception
      'Expected update timestamp is required';
  end if;

  if target_visit.updated_at
    is distinct from requested_expected_updated_at then
    raise exception
      'Site visit changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if target_visit.status = 'cancelled' then
    return target_visit;
  end if;

  if target_visit.status in (
    'completed',
    'no_show',
    'failed'
  ) then
    raise exception
      'Site visit cannot be cancelled in status %',
      target_visit.status;
  end if;

  if nullif(
    btrim(requested_reason),
    ''
  ) is null then
    raise exception
      'Cancellation reason is required';
  end if;

  update public.site_visits
  set
    status =
      'cancelled',

    cancellation_reason =
      btrim(requested_reason),

    updated_by =
      auth.uid(),

    updated_at =
      now()

  where id = target_visit.id

  returning *
  into target_visit;

  return target_visit;
end;
$function$;

-- ============================================================================
-- 4. RETIRE LEGACY CHECK-IN / CHECK-OUT / COMPLETE SIGNATURES
--
-- The old signatures did not require expected_updated_at and therefore could
-- bypass optimistic concurrency.
--
-- DROP is intentionally performed without CASCADE. If an unexpected database
-- dependency exists, the migration must fail rather than silently remove it.
-- ============================================================================

drop function if exists
public.check_in_site_visit(
  uuid,
  text,
  numeric,
  numeric,
  text
);

drop function if exists
public.check_out_site_visit(
  uuid,
  text
);

drop function if exists
public.complete_site_visit(
  uuid,
  text,
  text,
  numeric,
  text
);

-- ============================================================================
-- 5. CONCURRENCY-SAFE SITE-VISIT CHECK-IN
-- ============================================================================

create function public.check_in_site_visit(
  requested_site_visit_id uuid,
  requested_party text,
  requested_latitude numeric,
  requested_longitude numeric,
  requested_method text,
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
    raise exception
      'Site visit not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_visit.organization_id,
      'site_visits.check_in'
    ) then
    raise exception
      'Permission denied';
  end if;

  if requested_expected_updated_at is null then
    raise exception
      'Expected update timestamp is required';
  end if;

  if target_visit.updated_at
    is distinct from requested_expected_updated_at then
    raise exception
      'Site visit changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if requested_party is null
    or requested_party not in (
      'customer',
      'agent'
    ) then
    raise exception
      'Check-in party must be customer or agent';
  end if;

  if requested_method is null
    or requested_method not in (
      'manual',
      'gps',
      'qr_code',
      'otp',
      'agent_confirmation',
      'system'
    ) then
    raise exception
      'Invalid check-in method';
  end if;

  if requested_latitude is not null
    and (
      requested_latitude < -90
      or requested_latitude > 90
    ) then
    raise exception
      'Invalid latitude';
  end if;

  if requested_longitude is not null
    and (
      requested_longitude < -180
      or requested_longitude > 180
    ) then
    raise exception
      'Invalid longitude';
  end if;

  if target_visit.status not in (
    'scheduled',
    'confirmed',
    'agent_en_route',
    'customer_en_route',
    'rescheduled',
    'checked_in',
    'in_progress'
  ) then
    raise exception
      'Site visit cannot be checked in from status %',
      target_visit.status;
  end if;

  if requested_party = 'customer'
    and target_visit.customer_checked_in_at
      is not null then
    return target_visit;
  end if;

  if requested_party = 'agent'
    and target_visit.agent_checked_in_at
      is not null then
    return target_visit;
  end if;

  update public.site_visits
  set
    customer_checked_in_at =
      case
        when requested_party = 'customer'
          then now()
        else customer_checked_in_at
      end,

    agent_checked_in_at =
      case
        when requested_party = 'agent'
          then now()
        else agent_checked_in_at
      end,

    customer_check_in_latitude =
      case
        when requested_party = 'customer'
          then requested_latitude
        else customer_check_in_latitude
      end,

    customer_check_in_longitude =
      case
        when requested_party = 'customer'
          then requested_longitude
        else customer_check_in_longitude
      end,

    agent_check_in_latitude =
      case
        when requested_party = 'agent'
          then requested_latitude
        else agent_check_in_latitude
      end,

    agent_check_in_longitude =
      case
        when requested_party = 'agent'
          then requested_longitude
        else agent_check_in_longitude
      end,

    check_in_method =
      requested_method,

    status =
      case
        when status in (
          'scheduled',
          'confirmed',
          'agent_en_route',
          'customer_en_route',
          'rescheduled'
        )
          then 'checked_in'
        else status
      end,

    updated_by =
      auth.uid(),

    updated_at =
      now()

  where id = target_visit.id

  returning *
  into target_visit;

  return target_visit;
end;
$function$;

-- ============================================================================
-- 6. CONCURRENCY-SAFE SITE-VISIT CHECK-OUT
-- ============================================================================

create function public.check_out_site_visit(
  requested_site_visit_id uuid,
  requested_party text,
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
    raise exception
      'Site visit not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_visit.organization_id,
      'site_visits.check_in'
    ) then
    raise exception
      'Permission denied';
  end if;

  if requested_expected_updated_at is null then
    raise exception
      'Expected update timestamp is required';
  end if;

  if target_visit.updated_at
    is distinct from requested_expected_updated_at then
    raise exception
      'Site visit changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if requested_party is null
    or requested_party not in (
      'customer',
      'agent'
    ) then
    raise exception
      'Check-out party must be customer or agent';
  end if;

  if target_visit.status not in (
    'checked_in',
    'in_progress',
    'completed'
  ) then
    raise exception
      'Site visit cannot be checked out from status %',
      target_visit.status;
  end if;

  if requested_party = 'customer'
    and target_visit.customer_checked_in_at
      is null then
    raise exception
      'Customer must be checked in before check-out';
  end if;

  if requested_party = 'agent'
    and target_visit.agent_checked_in_at
      is null then
    raise exception
      'Agent must be checked in before check-out';
  end if;

  if requested_party = 'customer'
    and target_visit.customer_checked_out_at
      is not null then
    return target_visit;
  end if;

  if requested_party = 'agent'
    and target_visit.agent_checked_out_at
      is not null then
    return target_visit;
  end if;

  update public.site_visits
  set
    customer_checked_out_at =
      case
        when requested_party = 'customer'
          then now()
        else customer_checked_out_at
      end,

    agent_checked_out_at =
      case
        when requested_party = 'agent'
          then now()
        else agent_checked_out_at
      end,

    updated_by =
      auth.uid(),

    updated_at =
      now()

  where id = target_visit.id

  returning *
  into target_visit;

  return target_visit;
end;
$function$;

-- ============================================================================
-- 7. CONCURRENCY-SAFE SITE-VISIT COMPLETION
-- ============================================================================

create function public.complete_site_visit(
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
    raise exception
      'Site visit not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_visit.organization_id,
      'site_visits.complete'
    ) then
    raise exception
      'Permission denied';
  end if;

  if requested_expected_updated_at is null then
    raise exception
      'Expected update timestamp is required';
  end if;

  if target_visit.updated_at
    is distinct from requested_expected_updated_at then
    raise exception
      'Site visit changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if target_visit.status = 'completed' then
    raise exception
      'Site visit is already completed';
  end if;

  if target_visit.status not in (
    'scheduled',
    'confirmed',
    'agent_en_route',
    'customer_en_route',
    'rescheduled',
    'checked_in',
    'in_progress'
  ) then
    raise exception
      'Site visit cannot be completed from status %',
      target_visit.status;
  end if;

  if requested_outcome is null
    or requested_outcome not in (
      'interested',
      'highly_interested',
      'considering',
      'follow_up_required',
      'negotiation_started',
      'booking_expected',
      'not_interested',
      'budget_mismatch',
      'location_mismatch',
      'unit_mismatch',
      'postponed',
      'no_show',
      'other'
    ) then
    raise exception
      'Invalid site visit outcome';
  end if;

  if requested_probability_of_booking is not null
    and (
      requested_probability_of_booking < 0
      or requested_probability_of_booking > 100
    ) then
    raise exception
      'Probability of booking must be between 0 and 100';
  end if;

  update public.site_visits
  set
    status =
      'completed',

    outcome =
      requested_outcome,

    outcome_summary =
      nullif(
        btrim(requested_outcome_summary),
        ''
      ),

    probability_of_booking =
      requested_probability_of_booking,

    agent_notes =
      nullif(
        btrim(requested_agent_notes),
        ''
      ),

    visit_completed_at =
      coalesce(
        visit_completed_at,
        now()
      ),

    updated_by =
      auth.uid(),

    updated_at =
      now()

  where id = target_visit.id

  returning *
  into target_visit;

  return target_visit;
end;
$function$;

-- ============================================================================
-- 8. EXECUTE PRIVILEGES
-- ============================================================================

revoke all
on function public.assign_site_visit(
  uuid,
  uuid,
  uuid,
  text,
  timestamptz
)
from public, anon, authenticated, service_role;

revoke all
on function public.cancel_site_visit(
  uuid,
  text,
  timestamptz
)
from public, anon, authenticated, service_role;

revoke all
on function public.check_in_site_visit(
  uuid,
  text,
  numeric,
  numeric,
  text,
  timestamptz
)
from public, anon, authenticated, service_role;

revoke all
on function public.check_out_site_visit(
  uuid,
  text,
  timestamptz
)
from public, anon, authenticated, service_role;

revoke all
on function public.complete_site_visit(
  uuid,
  text,
  text,
  numeric,
  text,
  timestamptz
)
from public, anon, authenticated, service_role;

grant execute
on function public.assign_site_visit(
  uuid,
  uuid,
  uuid,
  text,
  timestamptz
)
to authenticated, service_role;

grant execute
on function public.cancel_site_visit(
  uuid,
  text,
  timestamptz
)
to authenticated, service_role;

grant execute
on function public.check_in_site_visit(
  uuid,
  text,
  numeric,
  numeric,
  text,
  timestamptz
)
to authenticated, service_role;

grant execute
on function public.check_out_site_visit(
  uuid,
  text,
  timestamptz
)
to authenticated, service_role;

grant execute
on function public.complete_site_visit(
  uuid,
  text,
  text,
  numeric,
  text,
  timestamptz
)
to authenticated, service_role;

-- ============================================================================
-- 9. VERIFICATION
-- ============================================================================

do $verification$
declare
  target_function regprocedure;
  function_definition text;
  system_function_definition text;
begin
  -- Legacy concurrency-bypass signatures must be gone.

  if to_regprocedure(
    'public.check_in_site_visit(uuid,text,numeric,numeric,text)'
  ) is not null then
    raise exception
      'Migration 043 verification failed: legacy check_in_site_visit signature remains.';
  end if;

  if to_regprocedure(
    'public.check_out_site_visit(uuid,text)'
  ) is not null then
    raise exception
      'Migration 043 verification failed: legacy check_out_site_visit signature remains.';
  end if;

  if to_regprocedure(
    'public.complete_site_visit(uuid,text,text,numeric,text)'
  ) is not null then
    raise exception
      'Migration 043 verification failed: legacy complete_site_visit signature remains.';
  end if;

  -- Required hardened RPC signatures must exist.

  foreach target_function in array array[
    'public.assign_site_visit(uuid,uuid,uuid,text,timestamptz)'::regprocedure,
    'public.cancel_site_visit(uuid,text,timestamptz)'::regprocedure,
    'public.check_in_site_visit(uuid,text,numeric,numeric,text,timestamptz)'::regprocedure,
    'public.check_out_site_visit(uuid,text,timestamptz)'::regprocedure,
    'public.complete_site_visit(uuid,text,text,numeric,text,timestamptz)'::regprocedure
  ]
  loop
    if has_function_privilege(
      'anon',
      target_function::oid,
      'EXECUTE'
    ) then
      raise exception
        'Migration 043 verification failed: anon EXECUTE remains on %.',
        target_function;
    end if;

    if not has_function_privilege(
      'authenticated',
      target_function::oid,
      'EXECUTE'
    ) then
      raise exception
        'Migration 043 verification failed: authenticated EXECUTE missing on %.',
        target_function;
    end if;

    if not has_function_privilege(
      'service_role',
      target_function::oid,
      'EXECUTE'
    ) then
      raise exception
        'Migration 043 verification failed: service_role EXECUTE missing on %.',
        target_function;
    end if;
  end loop;

  -- Assignment and cancellation must use application-safe P0001,
  -- never transaction-retry SQLSTATE 40001.

  foreach target_function in array array[
    'public.assign_site_visit(uuid,uuid,uuid,text,timestamptz)'::regprocedure,
    'public.cancel_site_visit(uuid,text,timestamptz)'::regprocedure
  ]
  loop
    function_definition :=
      pg_get_functiondef(
        target_function
      );

    if function_definition ~
      '''40001''' then
      raise exception
        'Migration 043 verification failed: SQLSTATE 40001 remains in %.',
        target_function;
    end if;

    if function_definition !~
      '''P0001''' then
      raise exception
        'Migration 043 verification failed: P0001 concurrency guard missing in %.',
        target_function;
    end if;
  end loop;

  -- Hardened mutation RPCs must all include an expected update timestamp.

  foreach target_function in array array[
    'public.check_in_site_visit(uuid,text,numeric,numeric,text,timestamptz)'::regprocedure,
    'public.check_out_site_visit(uuid,text,timestamptz)'::regprocedure,
    'public.complete_site_visit(uuid,text,text,numeric,text,timestamptz)'::regprocedure
  ]
  loop
    function_definition :=
      pg_get_functiondef(
        target_function
      );

    if position(
      'requested_expected_updated_at'
      in function_definition
    ) = 0 then
      raise exception
        'Migration 043 verification failed: expected_updated_at guard missing in %.',
        target_function;
    end if;

    if function_definition !~
      '''P0001''' then
      raise exception
        'Migration 043 verification failed: P0001 concurrency guard missing in %.',
        target_function;
    end if;
  end loop;

  -- Prevent the historical false-customer-check-in behavior.

  system_function_definition :=
    pg_get_functiondef(
      'public.set_site_visit_system_fields()'::regprocedure
    );

  if system_function_definition ~*
    'new\.status[[:space:]]*=[[:space:]]*''checked_in''' then
    raise exception
      'Migration 043 verification failed: system trigger still infers customer check-in from checked_in status.';
  end if;

  raise notice
    'Migration 043 verified: Site Visit operational concurrency is hardened.';
end;
$verification$;

notify pgrst, 'reload schema';

commit;