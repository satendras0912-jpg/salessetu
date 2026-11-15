-- Owner-controlled installment planning and payment collection for confirmed
-- bookings. A schedule is never a payment: receipts are recorded separately
-- in booking_payments and linked back to the scheduled installment.

begin;

create table if not exists public.booking_payment_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  sequence_number integer not null check (sequence_number > 0),
  payment_type text not null default 'installment' check (
    payment_type in (
      'token', 'booking_amount', 'installment', 'stamp_duty',
      'registration', 'maintenance', 'club_charge', 'parking', 'tax', 'other'
    )
  ),
  due_date date not null,
  amount_due numeric(18,2) not null check (amount_due > 0),
  amount_received numeric(18,2) not null default 0 check (amount_received >= 0 and amount_received <= amount_due),
  schedule_status text not null default 'pending' check (
    schedule_status in ('pending', 'partially_paid', 'paid', 'overdue', 'cancelled')
  ),
  notes text,
  last_payment_id uuid references public.booking_payments(id) on delete set null,
  paid_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id, sequence_number)
);

create index if not exists booking_payment_schedules_booking_idx
  on public.booking_payment_schedules (booking_id, due_date, sequence_number);

create index if not exists booking_payment_schedules_open_idx
  on public.booking_payment_schedules (organization_id, schedule_status, due_date)
  where schedule_status in ('pending', 'partially_paid', 'overdue');

create trigger booking_payment_schedules_set_updated_at
before update on public.booking_payment_schedules
for each row execute function public.set_updated_at();

alter table public.booking_payment_schedules enable row level security;

create policy "Owners can view booking payment schedules"
  on public.booking_payment_schedules
  for select to authenticated
  using (public.is_organization_owner(organization_id));

create or replace function public.create_booking_payment_schedule(
  requested_deal_id uuid,
  requested_booking_id uuid,
  requested_due_date date,
  requested_amount_due numeric,
  requested_payment_type text,
  requested_notes text default null
)
returns public.booking_payment_schedules
language plpgsql
security definer
set search_path = ''
as $function$
declare
  deal_record public.deals;
  booking_record public.bookings;
  schedule_record public.booking_payment_schedules;
  normalized_payment_type text := nullif(btrim(requested_payment_type), '');
  normalized_notes text := nullif(btrim(requested_notes), '');
  existing_scheduled_amount numeric(18,2);
  next_sequence_number integer;
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
    raise exception 'Only the workspace owner can manage payment schedules'
      using errcode = '42501';
  end if;

  if deal_record.status <> 'won'
     or deal_record.booking_id is distinct from requested_booking_id then
    raise exception 'Only the linked booking of a won deal can receive a payment schedule';
  end if;

  if requested_due_date is null or requested_amount_due is null or requested_amount_due <= 0 then
    raise exception 'A due date and positive scheduled amount are required';
  end if;

  if normalized_payment_type is null
     or normalized_payment_type not in (
       'token', 'booking_amount', 'installment', 'stamp_duty',
       'registration', 'maintenance', 'club_charge', 'parking', 'tax', 'other'
     ) then
    raise exception 'Choose a valid scheduled payment type';
  end if;

  select * into booking_record
    from public.bookings
   where id = requested_booking_id
     and organization_id = deal_record.organization_id
   for update;

  if not found or booking_record.booking_status <> 'confirmed' then
    raise exception 'Only a confirmed booking can receive a payment schedule';
  end if;

  select coalesce(sum(amount_due), 0), coalesce(max(sequence_number), 0) + 1
    into existing_scheduled_amount, next_sequence_number
    from public.booking_payment_schedules
   where booking_id = booking_record.id;

  if booking_record.booking_amount is not null
     and existing_scheduled_amount + requested_amount_due > booking_record.booking_amount then
    raise exception 'Scheduled amount cannot exceed the confirmed booking amount';
  end if;

  insert into public.booking_payment_schedules (
    organization_id, booking_id, sequence_number, payment_type, due_date,
    amount_due, notes, created_by, updated_by
  ) values (
    booking_record.organization_id, booking_record.id, next_sequence_number,
    normalized_payment_type, requested_due_date, requested_amount_due,
    normalized_notes, auth.uid(), auth.uid()
  ) returning * into schedule_record;

  return schedule_record;
end;
$function$;

create or replace function public.record_booking_schedule_payment(
  requested_deal_id uuid,
  requested_booking_id uuid,
  requested_schedule_id uuid,
  requested_amount numeric,
  requested_payment_reference text,
  requested_payment_mode text,
  requested_payment_date timestamptz,
  requested_notes text default null
)
returns public.booking_payment_schedules
language plpgsql
security definer
set search_path = ''
as $function$
declare
  deal_record public.deals;
  schedule_record public.booking_payment_schedules;
  booking_record public.bookings;
  payment_record public.booking_payments;
  normalized_reference text := nullif(btrim(requested_payment_reference), '');
  normalized_mode text := nullif(btrim(requested_payment_mode), '');
  normalized_notes text := nullif(btrim(requested_notes), '');
  resulting_amount_received numeric(18,2);
  resulting_schedule_status text;
  total_paid numeric(18,2);
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
    raise exception 'Only the workspace owner can record scheduled payments'
      using errcode = '42501';
  end if;

  if deal_record.status <> 'won'
     or deal_record.booking_id is distinct from requested_booking_id then
    raise exception 'Only the linked booking of a won deal can receive a scheduled payment';
  end if;

  select * into schedule_record
    from public.booking_payment_schedules
   where id = requested_schedule_id
   for update;

  if not found then
    raise exception 'Payment schedule not found';
  end if;

  if schedule_record.organization_id <> deal_record.organization_id
     or schedule_record.booking_id <> requested_booking_id then
    raise exception 'The selected installment does not belong to this confirmed booking';
  end if;

  if schedule_record.schedule_status in ('paid', 'cancelled') then
    raise exception 'This scheduled payment is closed';
  end if;

  if requested_amount is null or requested_amount <= 0
     or requested_amount > schedule_record.amount_due - schedule_record.amount_received then
    raise exception 'Payment amount must not exceed the remaining scheduled amount';
  end if;

  if normalized_reference is null or normalized_mode is null or requested_payment_date is null then
    raise exception 'Payment reference, mode and date are required';
  end if;

  if normalized_mode not in (
    'cash', 'cheque', 'bank_transfer', 'upi', 'credit_card', 'debit_card',
    'payment_gateway', 'loan_disbursement', 'other'
  ) then
    raise exception 'Choose a valid payment mode';
  end if;

  select * into booking_record
    from public.bookings
   where id = schedule_record.booking_id
     and organization_id = schedule_record.organization_id
   for update;

  if not found or booking_record.booking_status <> 'confirmed' then
    raise exception 'The linked booking is not confirmed';
  end if;

  insert into public.booking_payments (
    organization_id, booking_id, payment_type, amount, currency, payment_mode,
    payment_reference, payment_date, payment_status, remarks, metadata, created_by, updated_by
  ) values (
    booking_record.organization_id, booking_record.id, schedule_record.payment_type,
    requested_amount, booking_record.booking_currency, normalized_mode,
    normalized_reference, requested_payment_date, 'paid', normalized_notes,
    jsonb_build_object('recorded_by', 'booking_payment_schedule', 'schedule_id', schedule_record.id),
    auth.uid(), auth.uid()
  ) returning * into payment_record;

  resulting_amount_received := schedule_record.amount_received + requested_amount;
  resulting_schedule_status := case
    when resulting_amount_received >= schedule_record.amount_due then 'paid'
    else 'partially_paid'
  end;

  update public.booking_payment_schedules
     set amount_received = resulting_amount_received,
         schedule_status = resulting_schedule_status,
         last_payment_id = payment_record.id,
         paid_at = case when resulting_schedule_status = 'paid' then now() else paid_at end,
         updated_by = auth.uid(), updated_at = now()
   where id = schedule_record.id
   returning * into schedule_record;

  select coalesce(sum(amount), 0)
    into total_paid
    from public.booking_payments
   where booking_id = booking_record.id
     and payment_status = 'paid';

  update public.bookings
     set payment_status = case
       when booking_record.booking_amount is not null
            and total_paid >= booking_record.booking_amount then 'paid'::public.booking_payment_status
       when total_paid > 0 then 'partial'::public.booking_payment_status
       else 'pending'::public.booking_payment_status
     end,
         updated_by = auth.uid(), updated_at = now()
   where id = booking_record.id;

  return schedule_record;
end;
$function$;

revoke all on function public.create_booking_payment_schedule(uuid, uuid, date, numeric, text, text) from public;
grant execute on function public.create_booking_payment_schedule(uuid, uuid, date, numeric, text, text) to authenticated;

revoke all on function public.record_booking_schedule_payment(uuid, uuid, uuid, numeric, text, text, timestamptz, text) from public;
grant execute on function public.record_booking_schedule_payment(uuid, uuid, uuid, numeric, text, text, timestamptz, text) to authenticated;

select pg_notify('pgrst', 'reload schema');

commit;
