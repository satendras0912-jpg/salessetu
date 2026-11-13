-- ============================================================
-- DealOS: confirmed booking required before a deal can be won
-- ============================================================

begin;

create or replace function public.require_confirmed_booking_for_won_deal()
returns trigger
language plpgsql
set search_path = public
as $function$
declare
  linked_booking_status public.booking_status;
begin
  if new.status = 'won' and new.deleted_at is null then
    select b.booking_status
      into linked_booking_status
      from public.bookings b
     where b.id = new.booking_id
       and b.organization_id = new.organization_id;

    if linked_booking_status is distinct from 'confirmed'::public.booking_status then
      raise exception
        'A deal can only be marked won after its linked booking is confirmed'
        using errcode = 'P0001';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists deals_require_confirmed_booking_for_won on public.deals;

create trigger deals_require_confirmed_booking_for_won
before insert or update of status, booking_id
on public.deals
for each row
execute function public.require_confirmed_booking_for_won_deal();

comment on function public.require_confirmed_booking_for_won_deal() is
'Prevents DealOS from closing a deal as won until its same-organization Booking Engine record is confirmed.';

select pg_notify(
  'pgrst',
  'reload schema'
);

commit;
