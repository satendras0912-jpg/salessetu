-- Booking Reservation Monitoring and Alerts
--
-- Owner-only operational visibility for booking inventory holds. A short-lived
-- in-app alert is created when an active booking hold enters its final 30
-- minutes. The existing expiry scheduler remains responsible for release;
-- this migration does not create payments, customers, lead routing or any
-- outbound notification.

begin;

create table if not exists public.booking_reservation_alerts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  inventory_reservation_id uuid not null references public.inventory_reservations(id) on delete cascade,
  alert_type text not null check (alert_type in ('expires_soon')),
  status text not null default 'open' check (status in ('open', 'resolved')),
  expires_at timestamptz not null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (inventory_reservation_id, alert_type)
);

create index if not exists booking_reservation_alerts_open_idx
  on public.booking_reservation_alerts (organization_id, status, expires_at);

alter table public.booking_reservation_alerts enable row level security;

create policy "Owners can view booking reservation alerts"
  on public.booking_reservation_alerts
  for select
  to authenticated
  using (public.is_organization_owner(organization_id));

create or replace function public.refresh_booking_reservation_alerts()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_count integer := 0;
begin
  insert into public.booking_reservation_alerts (
    organization_id,
    inventory_reservation_id,
    alert_type,
    status,
    expires_at
  )
  select
    reservation_record.organization_id,
    reservation_record.id,
    'expires_soon',
    'open',
    reservation_record.expires_at
  from public.inventory_reservations reservation_record
  where reservation_record.reservation_type = 'booking_hold'
    and reservation_record.status = 'active'
    and reservation_record.expires_at is not null
    and reservation_record.expires_at > now()
    and reservation_record.expires_at <= now() + interval '30 minutes'
  on conflict (inventory_reservation_id, alert_type) do update
    set expires_at = excluded.expires_at,
        updated_at = now()
    where public.booking_reservation_alerts.status = 'open';

  get diagnostics changed_count = row_count;

  update public.booking_reservation_alerts alert_record
     set status = 'resolved',
         resolved_at = now(),
         updated_at = now()
   where alert_record.status = 'open'
     and not exists (
       select 1
       from public.inventory_reservations reservation_record
       where reservation_record.id = alert_record.inventory_reservation_id
         and reservation_record.status = 'active'
         and reservation_record.expires_at is not null
         and reservation_record.expires_at > now()
     );

  return changed_count;
end;
$$;

revoke all on function public.refresh_booking_reservation_alerts() from public;

-- Keep alerts in step with the existing one-minute booking-hold expiry job.
-- pg_cron is optional in non-production/local installations.
do $$
begin
  if exists (
    select 1
    from pg_extension
    where extname = 'pg_cron'
  ) then
    if exists (
      select 1
      from cron.job
      where jobname = 'booking-reservation-alerts'
    ) then
      perform cron.unschedule('booking-reservation-alerts');
    end if;

    perform cron.schedule(
      'booking-reservation-alerts',
      '* * * * *',
      'select public.refresh_booking_reservation_alerts();'
    );
  end if;
end;
$$;

select public.refresh_booking_reservation_alerts();

commit;
