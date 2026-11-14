-- Ensure a booking-hold expiry returns the unit to availability after the
-- reservation state has changed. This intentionally avoids a single data
-- modifying CTE, whose availability check can otherwise see the old active
-- reservation snapshot and leave the unit blocked.

begin;

create or replace function public.expire_booking_inventory_reservations()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_reservation record;
  expired_count integer := 0;
begin
  for expired_reservation in
    update public.inventory_reservations reservation_record
       set status = 'expired',
           released_at = now(),
           release_reason = 'Reservation expiry elapsed',
           updated_at = now()
     where reservation_record.reservation_type = 'booking_hold'
       and reservation_record.status = 'active'
       and reservation_record.expires_at <= now()
     returning reservation_record.id,
               reservation_record.organization_id,
               reservation_record.booking_id,
               reservation_record.inventory_unit_id
  loop
    update public.inventory_units unit_record
       set unit_status = 'available',
           sales_status = 'open',
           updated_at = now()
     where unit_record.id = expired_reservation.inventory_unit_id
       and unit_record.unit_status = 'reserved'
       and not exists (
         select 1
         from public.inventory_reservations remaining_reservation
         where remaining_reservation.inventory_unit_id = unit_record.id
           and remaining_reservation.status in ('active', 'confirmed')
       );

    if expired_reservation.booking_id is not null then
      insert into public.booking_reservation_events (
        organization_id,
        booking_id,
        inventory_reservation_id,
        event_type,
        event_reason,
        metadata
      ) values (
        expired_reservation.organization_id,
        expired_reservation.booking_id,
        expired_reservation.id,
        'expired',
        'Reservation expiry elapsed',
        jsonb_build_object('automatic', true)
      );
    end if;

    expired_count := expired_count + 1;
  end loop;

  -- Repair any unit previously left reserved by the old expiry implementation.
  -- A unit remains protected whenever another active or confirmed reservation
  -- exists, regardless of reservation type.
  update public.inventory_units unit_record
     set unit_status = 'available',
         sales_status = 'open',
         updated_at = now()
   where unit_record.unit_status = 'reserved'
     and exists (
       select 1
       from public.inventory_reservations expired_reservation
       where expired_reservation.inventory_unit_id = unit_record.id
         and expired_reservation.reservation_type = 'booking_hold'
         and expired_reservation.status = 'expired'
     )
     and not exists (
       select 1
       from public.inventory_reservations remaining_reservation
       where remaining_reservation.inventory_unit_id = unit_record.id
         and remaining_reservation.status in ('active', 'confirmed')
     );

  return expired_count;
end;
$$;

revoke all on function public.expire_booking_inventory_reservations() from public;

commit;
