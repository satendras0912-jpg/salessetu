-- Booking confirmation is the only owner-controlled path that finalizes a
-- booking-ready deal.  Payment and document references are recorded as facts;
-- this migration never fabricates a receipt or a verified document.

begin;

create table if not exists public.booking_deal_confirmations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete restrict,
  deal_id uuid not null references public.deals(id) on delete restrict,
  payment_id uuid not null references public.booking_payments(id) on delete restrict,
  document_id uuid references public.booking_documents(id) on delete set null,
  payment_reference text not null,
  payment_amount numeric(18,2) not null check (payment_amount > 0),
  payment_mode text not null,
  document_status text not null check (document_status in ('not_required', 'requested', 'under_review')),
  confirmation_reason text not null,
  confirmation_notes text,
  confirmed_by uuid references auth.users(id) on delete set null,
  confirmed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  unique (deal_id)
);

create index if not exists booking_deal_confirmations_org_idx
  on public.booking_deal_confirmations (organization_id, confirmed_at desc);

alter table public.booking_deal_confirmations enable row level security;

create policy "Owners can view booking deal confirmations"
  on public.booking_deal_confirmations
  for select to authenticated
  using (public.is_organization_owner(organization_id));

alter table public.deals
  add column if not exists winning_booking_confirmation_id uuid
  references public.booking_deal_confirmations(id) on delete restrict;

create index if not exists deals_winning_booking_confirmation_idx
  on public.deals (winning_booking_confirmation_id)
  where winning_booking_confirmation_id is not null;

create or replace function public.require_confirmed_booking_for_won_deal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  linked_booking_status public.booking_status;
  confirmation_record public.booking_deal_confirmations;
begin
  if new.status <> 'won' or old.status = 'won' or new.deleted_at is not null then
    return new;
  end if;

  select b.booking_status
    into linked_booking_status
    from public.bookings b
   where b.id = new.booking_id
     and b.organization_id = new.organization_id;

  if linked_booking_status is distinct from 'confirmed'::public.booking_status then
    raise exception 'A deal can only be marked won after its linked booking is confirmed'
      using errcode = 'P0001';
  end if;

  select * into confirmation_record
    from public.booking_deal_confirmations confirmation_row
   where confirmation_row.id = new.winning_booking_confirmation_id
     and confirmation_row.organization_id = new.organization_id
     and confirmation_row.booking_id = new.booking_id
     and confirmation_row.deal_id = new.id;

  if not found then
    raise exception 'Owner booking confirmation is required before a deal can be marked won'
      using errcode = 'P0001';
  end if;

  return new;
end;
$function$;

drop trigger if exists deals_require_confirmed_booking_for_won on public.deals;
create trigger deals_require_confirmed_booking_for_won
before update of status, booking_id, winning_booking_confirmation_id on public.deals
for each row execute function public.require_confirmed_booking_for_won_deal();

create or replace function public.confirm_booking_and_win_deal(
  requested_deal_id uuid,
  requested_booking_id uuid,
  requested_expected_updated_at timestamptz,
  requested_payment_reference text,
  requested_payment_amount numeric,
  requested_payment_mode text,
  requested_document_status text,
  requested_document_name text default null,
  requested_confirmation_reason text default null,
  requested_confirmation_notes text default null
)
returns public.deals
language plpgsql
security definer
set search_path = ''
as $function$
declare
  deal_record public.deals;
  booking_record public.bookings;
  reservation_record public.inventory_reservations;
  payment_record public.booking_payments;
  document_record public.booking_documents;
  confirmation_record public.booking_deal_confirmations;
  normalized_payment_reference text := nullif(btrim(requested_payment_reference), '');
  normalized_payment_mode text := nullif(btrim(requested_payment_mode), '');
  normalized_document_status text := nullif(btrim(requested_document_status), '');
  normalized_document_name text := nullif(btrim(requested_document_name), '');
  normalized_reason text := nullif(btrim(requested_confirmation_reason), '');
  normalized_notes text := nullif(btrim(requested_confirmation_notes), '');
  resulting_payment_status public.booking_payment_status;
begin
  select * into deal_record
    from public.deals
   where id = requested_deal_id
     and deleted_at is null
   for update;

  if not found then
    raise exception 'Deal not found';
  end if;

  if not public.is_organization_owner(deal_record.organization_id) then
    raise exception 'Only the workspace owner can confirm a booking and mark a deal won'
      using errcode = '42501';
  end if;

  if deal_record.booking_id is distinct from requested_booking_id
     or deal_record.status <> 'booking_ready' then
    raise exception 'Only the linked booking of a booking-ready deal can be confirmed';
  end if;

  if requested_expected_updated_at is null
     or deal_record.updated_at is distinct from requested_expected_updated_at then
    raise exception 'This deal changed after the confirmation form was opened';
  end if;

  if normalized_payment_reference is null then
    raise exception 'A payment reference is required';
  end if;

  if requested_payment_amount is null or requested_payment_amount <= 0 then
    raise exception 'A payment amount greater than zero is required';
  end if;

  if normalized_payment_mode is null then
    raise exception 'A payment mode is required';
  end if;

  if normalized_document_status is null
     or normalized_document_status not in ('not_required', 'requested', 'under_review') then
    raise exception 'Choose a valid document status';
  end if;

  if normalized_document_status <> 'not_required' and normalized_document_name is null then
    raise exception 'A document reference is required when a document is pending or under review';
  end if;

  if normalized_reason is null then
    raise exception 'A booking confirmation reason is required';
  end if;

  select * into booking_record
    from public.bookings
   where id = requested_booking_id
     and organization_id = deal_record.organization_id
   for update;

  if not found then
    raise exception 'Linked booking not found';
  end if;

  if booking_record.inventory_unit_id is null then
    raise exception 'The linked booking has no inventory unit';
  end if;

  if booking_record.booking_status <> 'draft' then
    raise exception 'Only a draft booking can be confirmed through this workflow';
  end if;

  select * into reservation_record
    from public.inventory_reservations
   where booking_id = booking_record.id
     and inventory_unit_id = booking_record.inventory_unit_id
     and reservation_type = 'booking_hold'
     and status = 'active'
     and expires_at > now()
   for update;

  if not found then
    raise exception 'An active, unexpired booking inventory reservation is required';
  end if;

  insert into public.booking_payments (
    organization_id, booking_id, payment_type, amount, currency, payment_mode,
    payment_reference, payment_date, payment_status, remarks, metadata, created_by, updated_by
  ) values (
    booking_record.organization_id, booking_record.id, 'booking_amount', requested_payment_amount,
    booking_record.booking_currency, normalized_payment_mode, normalized_payment_reference, now(),
    'paid', normalized_reason,
    jsonb_build_object('recorded_by', 'booking_deal_confirmation', 'receipt_verified', false),
    auth.uid(), auth.uid()
  ) returning * into payment_record;

  if normalized_document_status <> 'not_required' then
    insert into public.booking_documents (
      organization_id, booking_id, document_name, document_type, document_status,
      verified, uploaded_by, metadata
    ) values (
      booking_record.organization_id, booking_record.id, normalized_document_name,
      'booking_confirmation_reference', normalized_document_status, false, auth.uid(),
      jsonb_build_object('recorded_by', 'booking_deal_confirmation', 'file_verified', false)
    ) returning * into document_record;
  end if;

  resulting_payment_status := case
    when booking_record.booking_amount is not null
      and requested_payment_amount >= booking_record.booking_amount then 'paid'::public.booking_payment_status
    else 'partial'::public.booking_payment_status
  end;

  update public.bookings
     set booking_status = 'confirmed', payment_status = resulting_payment_status,
         booked_by = auth.uid(), booked_at = now(),
         remarks = concat_ws(E'\n', nullif(booking_record.remarks, ''), normalized_notes),
         updated_by = auth.uid(), updated_at = now()
   where id = booking_record.id;

  update public.inventory_units
     set unit_status = 'booked', sales_status = 'closed', updated_by = auth.uid(), updated_at = now()
   where id = booking_record.inventory_unit_id
     and organization_id = booking_record.organization_id;

  insert into public.booking_deal_confirmations (
    organization_id, booking_id, deal_id, payment_id, document_id, payment_reference,
    payment_amount, payment_mode, document_status, confirmation_reason, confirmation_notes,
    confirmed_by, metadata
  ) values (
    booking_record.organization_id, booking_record.id, deal_record.id, payment_record.id,
    document_record.id, normalized_payment_reference, requested_payment_amount,
    normalized_payment_mode, normalized_document_status, normalized_reason, normalized_notes,
    auth.uid(), jsonb_build_object('inventory_unit_id', booking_record.inventory_unit_id)
  ) returning * into confirmation_record;

  update public.deals
     set status = 'won', winning_booking_confirmation_id = confirmation_record.id,
         updated_by = auth.uid(), updated_at = now()
   where id = deal_record.id
   returning * into deal_record;

  return deal_record;
end;
$function$;

revoke all on function public.confirm_booking_and_win_deal(uuid, uuid, timestamptz, text, numeric, text, text, text, text, text) from public;
grant execute on function public.confirm_booking_and_win_deal(uuid, uuid, timestamptz, text, numeric, text, text, text, text, text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
