-- Booking Reservation Control
--
-- An owner may temporarily reserve the inventory unit attached to a draft
-- booking. This does not collect a payment, create a customer, route a lead,
-- or notify anyone. A booking can only become confirmed while its own active
-- reservation is still valid.

begin;

create table if not exists public.booking_reservation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  inventory_reservation_id uuid not null references public.inventory_reservations(id) on delete cascade,
  event_type text not null check (event_type in ('reserved','released','expired','confirmed')),
  event_reason text,
  occurred_by uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists booking_reservation_events_booking_idx
  on public.booking_reservation_events(booking_id, occurred_at desc);

create unique index if not exists inventory_reservations_active_booking_idx
  on public.inventory_reservations(booking_id)
  where booking_id is not null and status in ('active','confirmed');

alter table public.booking_reservation_events enable row level security;

create policy "Owners can view booking reservation events"
  on public.booking_reservation_events
  for select
  to authenticated
  using (public.is_organization_owner(organization_id));

create or replace function public.expire_booking_inventory_reservations()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  expired_count integer := 0;
begin
  with expired_reservations as (
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
  ), released_units as (
    update public.inventory_units unit_record
       set unit_status = 'available',
           sales_status = 'open',
           updated_at = now()
     where unit_record.id in (
       select inventory_unit_id
       from expired_reservations
     )
       and unit_record.unit_status = 'reserved'
       and not exists (
         select 1
         from public.inventory_reservations reservation_record
         where reservation_record.inventory_unit_id = unit_record.id
           and reservation_record.status in ('active','confirmed')
       )
    returning unit_record.id
  ), logged_events as (
    insert into public.booking_reservation_events (
      organization_id,
      booking_id,
      inventory_reservation_id,
      event_type,
      event_reason,
      metadata
    )
    select
      organization_id,
      booking_id,
      id,
      'expired',
      'Reservation expiry elapsed',
      jsonb_build_object('automatic', true)
    from expired_reservations
    where booking_id is not null
    returning id
  )
  select count(*) into expired_count from logged_events;

  return expired_count;
end;
$$;

revoke all on function public.expire_booking_inventory_reservations() from public;

create or replace function public.reserve_booking_inventory(
  requested_booking_id uuid,
  requested_expires_at timestamptz,
  requested_notes text default null
)
returns public.inventory_reservations
language plpgsql
security definer
set search_path = ''
as $$
declare
  booking_record public.bookings;
  unit_record public.inventory_units;
  reservation_record public.inventory_reservations;
  reservation_number_value text;
begin
  select * into booking_record
  from public.bookings
  where id = requested_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;

  if not public.is_organization_owner(booking_record.organization_id) then
    raise exception 'Only the workspace owner can reserve inventory for a booking'
      using errcode = '42501';
  end if;

  if booking_record.booking_status <> 'draft' then
    raise exception 'Only a draft booking can receive an inventory reservation';
  end if;

  if booking_record.inventory_unit_id is null then
    raise exception 'The draft booking must have an inventory unit before it can be reserved';
  end if;

  if requested_expires_at <= now() then
    raise exception 'Reservation expiry must be in the future';
  end if;

  if requested_expires_at > now() + interval '72 hours' then
    raise exception 'Reservation expiry cannot be more than 72 hours away';
  end if;

  perform public.expire_booking_inventory_reservations();

  select * into unit_record
  from public.inventory_units
  where id = booking_record.inventory_unit_id
    and organization_id = booking_record.organization_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'The booking inventory unit is unavailable';
  end if;

  if unit_record.unit_status <> 'available' then
    raise exception 'The booking inventory unit is not available for reservation';
  end if;

  if exists (
    select 1
    from public.inventory_reservations existing_reservation
    where existing_reservation.booking_id = booking_record.id
      and existing_reservation.status in ('active','confirmed')
  ) then
    raise exception 'This booking already has an active inventory reservation';
  end if;

  reservation_number_value :=
    'BKG-HOLD-' || upper(substring(replace(booking_record.id::text, '-', '') from 1 for 8)) || '-' ||
    upper(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 12));

  insert into public.inventory_reservations (
    organization_id,
    inventory_unit_id,
    lead_id,
    booking_id,
    reservation_number,
    reservation_type,
    status,
    reserved_by,
    expires_at,
    notes,
    created_by,
    updated_by
  ) values (
    booking_record.organization_id,
    unit_record.id,
    booking_record.lead_id,
    booking_record.id,
    reservation_number_value,
    'booking_hold',
    'active',
    auth.uid(),
    requested_expires_at,
    nullif(btrim(requested_notes), ''),
    auth.uid(),
    auth.uid()
  )
  returning * into reservation_record;

  update public.inventory_units
     set unit_status = 'reserved',
         sales_status = 'on_hold',
         updated_by = auth.uid(),
         updated_at = now()
   where id = unit_record.id;

  insert into public.booking_reservation_events (
    organization_id,
    booking_id,
    inventory_reservation_id,
    event_type,
    event_reason,
    occurred_by,
    metadata
  ) values (
    booking_record.organization_id,
    booking_record.id,
    reservation_record.id,
    'reserved',
    'Draft booking inventory hold created',
    auth.uid(),
    jsonb_build_object(
      'expires_at', requested_expires_at,
      'side_effects', jsonb_build_array('no_payment', 'no_customer', 'no_routing', 'no_notification')
    )
  );

  return reservation_record;
end;
$$;

revoke all on function public.reserve_booking_inventory(uuid, timestamptz, text) from public;
grant execute on function public.reserve_booking_inventory(uuid, timestamptz, text) to authenticated;

create or replace function public.release_booking_inventory_reservation(
  requested_booking_id uuid,
  requested_reason text
)
returns public.inventory_reservations
language plpgsql
security definer
set search_path = ''
as $$
declare
  reservation_record public.inventory_reservations;
begin
  select reservation_row.* into reservation_record
  from public.inventory_reservations reservation_row
  join public.bookings booking_record
    on booking_record.id = reservation_row.booking_id
  where reservation_row.booking_id = requested_booking_id
    and reservation_row.reservation_type = 'booking_hold'
    and reservation_row.status = 'active'
  for update of reservation_row;

  if not found then
    raise exception 'No active booking inventory reservation exists';
  end if;

  if not public.is_organization_owner(reservation_record.organization_id) then
    raise exception 'Only the workspace owner can release a booking inventory reservation'
      using errcode = '42501';
  end if;

  if nullif(btrim(requested_reason), '') is null then
    raise exception 'A release reason is required';
  end if;

  update public.inventory_reservations
     set status = 'released',
         released_at = now(),
         released_by = auth.uid(),
         release_reason = btrim(requested_reason),
         updated_by = auth.uid(),
         updated_at = now()
   where id = reservation_record.id
  returning * into reservation_record;

  update public.inventory_units unit_record
     set unit_status = 'available',
         sales_status = 'open',
         updated_by = auth.uid(),
         updated_at = now()
   where unit_record.id = reservation_record.inventory_unit_id
     and unit_record.unit_status = 'reserved'
     and not exists (
       select 1
       from public.inventory_reservations existing_reservation
       where existing_reservation.inventory_unit_id = unit_record.id
         and existing_reservation.status in ('active','confirmed')
     );

  insert into public.booking_reservation_events (
    organization_id,
    booking_id,
    inventory_reservation_id,
    event_type,
    event_reason,
    occurred_by
  ) values (
    reservation_record.organization_id,
    requested_booking_id,
    reservation_record.id,
    'released',
    reservation_record.release_reason,
    auth.uid()
  );

  return reservation_record;
end;
$$;

revoke all on function public.release_booking_inventory_reservation(uuid, text) from public;
grant execute on function public.release_booking_inventory_reservation(uuid, text) to authenticated;

create or replace function public.require_active_booking_reservation_for_confirmation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  reservation_record public.inventory_reservations;
begin
  if new.booking_status <> 'confirmed'
     or old.booking_status = 'confirmed' then
    return new;
  end if;

  select * into reservation_record
  from public.inventory_reservations
  where booking_id = new.id
    and inventory_unit_id = new.inventory_unit_id
    and reservation_type = 'booking_hold'
    and status = 'active'
    and expires_at > now()
  for update;

  if not found then
    raise exception 'A deal can only be confirmed after its linked inventory reservation is active';
  end if;

  update public.inventory_reservations
     set status = 'confirmed',
         confirmed_at = now(),
         updated_by = auth.uid(),
         updated_at = now()
   where id = reservation_record.id;

  insert into public.booking_reservation_events (
    organization_id,
    booking_id,
    inventory_reservation_id,
    event_type,
    event_reason,
    occurred_by
  ) values (
    new.organization_id,
    new.id,
    reservation_record.id,
    'confirmed',
    'Booking confirmed with an active inventory reservation',
    auth.uid()
  );

  return new;
end;
$$;

drop trigger if exists bookings_require_active_reservation_for_confirmation on public.bookings;
create trigger bookings_require_active_reservation_for_confirmation
before update of booking_status on public.bookings
for each row
execute function public.require_active_booking_reservation_for_confirmation();

-- The scheduler runs under the migration/database owner. The public function
-- remains ungranted, so neither the browser nor normal application sessions
-- can expire other tenants' reservations.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    if exists (select 1 from cron.job where jobname = 'booking-reservation-expiry') then
      perform cron.unschedule('booking-reservation-expiry');
    end if;

    perform cron.schedule(
      'booking-reservation-expiry',
      '* * * * *',
      'select public.expire_booking_inventory_reservations();'
    );
  end if;
end;
$$;

select pg_notify('pgrst', 'reload schema');

commit;
