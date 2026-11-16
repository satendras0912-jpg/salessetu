-- Owner-only DealOS booking handoff. The booking, unit hold and deal link are
-- created in one transaction so a failed hold cannot leave an orphan booking.
begin;

create or replace function public.create_deal_booking_hold(
  requested_deal_id uuid,
  requested_expected_updated_at timestamptz,
  requested_expires_at timestamptz,
  requested_notes text
)
returns table(
  deal_id uuid,
  booking_id uuid,
  reservation_id uuid,
  booking_number text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_deal public.deals;
  target_unit public.inventory_units;
  target_project public.projects;
  created_booking public.bookings;
  created_reservation public.inventory_reservations;
  normalized_notes text := nullif(btrim(requested_notes), '');
  generated_booking_number text;
  generated_reservation_number text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  if requested_deal_id is null
     or requested_expected_updated_at is null
     or requested_expires_at is null then
    raise exception 'Deal, update timestamp and hold expiry are required' using errcode = '23514';
  end if;

  if normalized_notes is null
     or char_length(normalized_notes) < 3
     or char_length(normalized_notes) > 500 then
    raise exception 'A booking-hold reason between 3 and 500 characters is required' using errcode = '23514';
  end if;

  if requested_expires_at <= now() then
    raise exception 'The booking hold expiry must be in the future' using errcode = '23514';
  end if;

  if requested_expires_at > now() + interval '72 hours' then
    raise exception 'A booking hold cannot exceed 72 hours' using errcode = '23514';
  end if;

  -- Clear earlier elapsed holds before evaluating availability. The function is
  -- optional in older development databases, but present in production.
  if to_regprocedure('public.expire_booking_inventory_reservations()') is not null then
    execute 'select public.expire_booking_inventory_reservations()';
  end if;

  select *
    into target_deal
    from public.deals deal
   where deal.id = requested_deal_id
     and deal.deleted_at is null
   for update;

  if not found then
    raise exception 'Deal not found' using errcode = 'P0002';
  end if;

  if not public.is_organization_owner(target_deal.organization_id) then
    raise exception 'Only the workspace owner can create a booking hold' using errcode = '42501';
  end if;

  if target_deal.updated_at is distinct from requested_expected_updated_at then
    raise exception 'The deal changed after this booking hold was opened' using errcode = '40001';
  end if;

  if target_deal.status <> 'booking_ready' then
    raise exception 'A booking hold can only be created for a booking-ready deal' using errcode = '23514';
  end if;

  if target_deal.booking_id is not null then
    raise exception 'This deal already has a linked booking' using errcode = '23505';
  end if;

  if target_deal.inventory_unit_id is null then
    raise exception 'This deal does not have a selected inventory unit' using errcode = '23514';
  end if;

  select *
    into target_unit
    from public.inventory_units unit
   where unit.id = target_deal.inventory_unit_id
     and unit.organization_id = target_deal.organization_id
     and unit.deleted_at is null
   for update;

  if not found then
    raise exception 'The selected inventory unit is not available in this workspace' using errcode = 'P0002';
  end if;

  if target_unit.unit_status <> 'available' or target_unit.sales_status <> 'open' then
    raise exception 'The selected inventory unit is not available for a booking hold' using errcode = '23514';
  end if;

  select *
    into target_project
    from public.projects project
   where project.id = target_unit.project_id
     and project.organization_id = target_deal.organization_id
     and project.deleted_at is null;

  if not found then
    raise exception 'The selected unit project is not available in this workspace' using errcode = 'P0002';
  end if;

  generated_booking_number :=
    'BKG-HOLD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  generated_reservation_number :=
    'RSV-HOLD-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));

  insert into public.bookings (
    organization_id,
    lead_id,
    site_visit_id,
    booking_number,
    project_reference_id,
    project_name,
    property_type,
    unit_number,
    unit_price,
    booking_status,
    payment_status,
    remarks,
    inventory_unit_id,
    booked_by,
    created_by,
    updated_by
  ) values (
    target_deal.organization_id,
    target_deal.lead_id,
    target_deal.site_visit_id,
    generated_booking_number,
    target_project.id::text,
    target_project.project_name,
    target_unit.property_type,
    target_unit.unit_number,
    coalesce(target_unit.current_price, target_unit.all_inclusive_price),
    'draft',
    'pending',
    normalized_notes,
    target_unit.id,
    auth.uid(),
    auth.uid(),
    auth.uid()
  )
  returning * into created_booking;

  insert into public.inventory_reservations (
    organization_id,
    inventory_unit_id,
    lead_id,
    booking_id,
    reservation_number,
    status,
    reservation_type,
    reserved_by,
    expires_at,
    notes,
    created_by,
    updated_by
  ) values (
    target_deal.organization_id,
    target_unit.id,
    target_deal.lead_id,
    created_booking.id,
    generated_reservation_number,
    'active',
    'booking_hold',
    auth.uid(),
    requested_expires_at,
    normalized_notes,
    auth.uid(),
    auth.uid()
  )
  returning * into created_reservation;

  update public.inventory_units
     set unit_status = 'reserved',
         sales_status = 'on_hold',
         updated_by = auth.uid(),
         updated_at = now()
   where id = target_unit.id;

  update public.deals
     set booking_id = created_booking.id,
         updated_by = auth.uid(),
         updated_at = now()
   where id = target_deal.id
     and organization_id = target_deal.organization_id;

  return query
  select
    target_deal.id,
    created_booking.id,
    created_reservation.id,
    created_booking.booking_number,
    created_reservation.expires_at;
end;
$function$;

revoke all on function public.create_deal_booking_hold(uuid, timestamptz, timestamptz, text) from public;
grant execute on function public.create_deal_booking_hold(uuid, timestamptz, timestamptz, text) to authenticated, service_role;

comment on function public.create_deal_booking_hold(uuid, timestamptz, timestamptz, text) is
'Owner-only atomic DealOS flow: creates a draft booking, temporary inventory hold and deal booking link without payment, customer contact, routing or notification.';

select pg_notify('pgrst', 'reload schema');

commit;
