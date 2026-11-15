-- Sales agents may submit a receipt against an accessible confirmed booking.
-- Only a workspace owner can approve it; the approved decision is the sole
-- path that creates a paid booking_payment and changes schedule totals.
begin;

create table if not exists public.booking_payment_receipt_submissions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  deal_id uuid not null references public.deals(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  schedule_id uuid not null references public.booking_payment_schedules(id) on delete restrict,
  amount numeric(18,2) not null check (amount > 0),
  payment_reference text not null check (char_length(btrim(payment_reference)) between 1 and 200),
  payment_mode text not null check (payment_mode in ('cash','cheque','bank_transfer','upi','credit_card','debit_card','payment_gateway','loan_disbursement','other')),
  payment_date timestamptz not null,
  notes text check (notes is null or char_length(notes) <= 1000),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  submitted_by uuid references auth.users(id) on delete set null,
  submitted_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_reason text check (decision_reason is null or char_length(decision_reason) <= 1000),
  booking_payment_id uuid references public.booking_payments(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'pending' and decided_at is null and decided_by is null and booking_payment_id is null) or status in ('approved','rejected'))
);

create index if not exists booking_payment_receipt_submissions_owner_queue_idx
  on public.booking_payment_receipt_submissions (organization_id, status, submitted_at asc);

create index if not exists booking_payment_receipt_submissions_schedule_idx
  on public.booking_payment_receipt_submissions (schedule_id, status);

drop trigger if exists booking_payment_receipt_submissions_set_updated_at on public.booking_payment_receipt_submissions;
create trigger booking_payment_receipt_submissions_set_updated_at
before update on public.booking_payment_receipt_submissions
for each row execute function public.set_updated_at();

alter table public.booking_payment_receipt_submissions enable row level security;

create policy "Receipt submissions visible to submitter, owner and accessible deal users"
on public.booking_payment_receipt_submissions for select to authenticated using (
  submitted_by = auth.uid()
  or public.is_organization_owner(organization_id)
  or public.can_access_deal(deal_id)
);

-- Let an assigned sales agent see schedule context for a deal they can already
-- access; financial mutations remain inside the RPCs below.
create policy "Accessible deal users can view booking payment schedules"
on public.booking_payment_schedules for select to authenticated using (
  public.can_access_deal((select d.id from public.deals d where d.booking_id = booking_payment_schedules.booking_id and d.organization_id = booking_payment_schedules.organization_id and d.deleted_at is null limit 1))
);

create or replace function public.submit_booking_payment_receipt(
  requested_deal_id uuid,
  requested_booking_id uuid,
  requested_schedule_id uuid,
  requested_amount numeric,
  requested_payment_reference text,
  requested_payment_mode text,
  requested_payment_date timestamptz,
  requested_notes text default null
)
returns public.booking_payment_receipt_submissions
language plpgsql security definer set search_path = '' as $function$
declare
  deal_record public.deals;
  booking_record public.bookings;
  schedule_record public.booking_payment_schedules;
  request_record public.booking_payment_receipt_submissions;
  pending_total numeric(18,2);
  normalized_reference text := nullif(btrim(requested_payment_reference), '');
  normalized_mode text := nullif(btrim(requested_payment_mode), '');
  normalized_notes text := nullif(btrim(requested_notes), '');
begin
  if auth.uid() is null then raise exception 'Authentication is required' using errcode = '42501'; end if;
  select * into deal_record from public.deals where id = requested_deal_id and deleted_at is null for update;
  if not found then raise exception 'Deal not found' using errcode = 'P0002'; end if;
  if not public.is_organization_member(deal_record.organization_id) or not public.can_access_deal(deal_record.id) then raise exception 'You do not have access to submit a receipt for this deal' using errcode = '42501'; end if;
  if deal_record.status <> 'won' or deal_record.booking_id is distinct from requested_booking_id then raise exception 'Only the linked booking of a won deal can receive a receipt submission' using errcode = '23514'; end if;
  select * into booking_record from public.bookings where id = requested_booking_id and organization_id = deal_record.organization_id for update;
  if not found or booking_record.booking_status <> 'confirmed' then raise exception 'The linked booking is not confirmed' using errcode = '23514'; end if;
  select * into schedule_record from public.booking_payment_schedules where id = requested_schedule_id for update;
  if not found or schedule_record.organization_id <> deal_record.organization_id or schedule_record.booking_id <> booking_record.id then raise exception 'The selected installment does not belong to this confirmed booking' using errcode = '23514'; end if;
  if schedule_record.schedule_status in ('paid','cancelled') then raise exception 'This scheduled payment is closed' using errcode = '23514'; end if;
  if requested_amount is null or requested_amount <= 0 or normalized_reference is null or normalized_mode is null or requested_payment_date is null then raise exception 'Amount, payment reference, mode and date are required' using errcode = '23514'; end if;
  if normalized_mode not in ('cash','cheque','bank_transfer','upi','credit_card','debit_card','payment_gateway','loan_disbursement','other') then raise exception 'Choose a valid payment mode' using errcode = '23514'; end if;
  select coalesce(sum(amount), 0) into pending_total from public.booking_payment_receipt_submissions where schedule_id = schedule_record.id and status = 'pending';
  if requested_amount > schedule_record.amount_due - schedule_record.amount_received - pending_total then raise exception 'Receipt amount exceeds the unapproved balance of this installment' using errcode = '23514'; end if;
  insert into public.booking_payment_receipt_submissions (organization_id,deal_id,booking_id,schedule_id,amount,payment_reference,payment_mode,payment_date,notes,submitted_by)
  values (deal_record.organization_id,deal_record.id,booking_record.id,schedule_record.id,requested_amount,normalized_reference,normalized_mode,requested_payment_date,normalized_notes,auth.uid())
  returning * into request_record;
  return request_record;
end;
$function$;

create or replace function public.decide_booking_payment_receipt(
  requested_submission_id uuid,
  requested_decision text,
  requested_reason text
)
returns public.booking_payment_receipt_submissions
language plpgsql security definer set search_path = '' as $function$
declare
  request_record public.booking_payment_receipt_submissions;
  schedule_record public.booking_payment_schedules;
  booking_record public.bookings;
  payment_record public.booking_payments;
  normalized_decision text := lower(btrim(requested_decision));
  normalized_reason text := nullif(btrim(requested_reason), '');
  resulting_amount_received numeric(18,2);
  resulting_schedule_status text;
begin
  if auth.uid() is null then raise exception 'Authentication is required' using errcode = '42501'; end if;
  select * into request_record from public.booking_payment_receipt_submissions where id = requested_submission_id for update;
  if not found then raise exception 'Receipt submission not found' using errcode = 'P0002'; end if;
  if not public.is_organization_owner(request_record.organization_id) then raise exception 'Only the workspace owner can approve or reject a receipt' using errcode = '42501'; end if;
  if request_record.status <> 'pending' then raise exception 'This receipt submission has already been decided' using errcode = '23505'; end if;
  if normalized_decision not in ('approved','rejected') or normalized_reason is null or char_length(normalized_reason) > 1000 then raise exception 'An approval decision and reason are required' using errcode = '23514'; end if;
  select * into schedule_record from public.booking_payment_schedules where id = request_record.schedule_id for update;
  select * into booking_record from public.bookings where id = request_record.booking_id and organization_id = request_record.organization_id for update;
  if not found or booking_record.booking_status <> 'confirmed' then raise exception 'The linked booking is not confirmed' using errcode = '23514'; end if;
  if normalized_decision = 'approved' then
    if schedule_record.schedule_status in ('paid','cancelled') or request_record.amount > schedule_record.amount_due - schedule_record.amount_received then raise exception 'This installment no longer has enough outstanding balance' using errcode = '23514'; end if;
    insert into public.booking_payments (organization_id,booking_id,payment_type,amount,currency,payment_mode,payment_reference,payment_date,payment_status,remarks,metadata,created_by,updated_by)
    values (request_record.organization_id,request_record.booking_id,schedule_record.payment_type,request_record.amount,booking_record.booking_currency,request_record.payment_mode,request_record.payment_reference,request_record.payment_date,'paid',request_record.notes,jsonb_build_object('recorded_by','receipt_owner_approval','schedule_id',schedule_record.id,'receipt_submission_id',request_record.id,'submitted_by',request_record.submitted_by),auth.uid(),auth.uid()) returning * into payment_record;
    resulting_amount_received := schedule_record.amount_received + request_record.amount;
    resulting_schedule_status := case when resulting_amount_received >= schedule_record.amount_due then 'paid' else 'partially_paid' end;
    update public.booking_payment_schedules set amount_received = resulting_amount_received, schedule_status = resulting_schedule_status, last_payment_id = payment_record.id, paid_at = case when resulting_schedule_status = 'paid' then now() else paid_at end, updated_by = auth.uid(), updated_at = now() where id = schedule_record.id;
    update public.booking_payment_receipt_submissions set status = 'approved', decided_by = auth.uid(), decided_at = now(), decision_reason = normalized_reason, booking_payment_id = payment_record.id, updated_at = now() where id = request_record.id returning * into request_record;
  else
    update public.booking_payment_receipt_submissions set status = 'rejected', decided_by = auth.uid(), decided_at = now(), decision_reason = normalized_reason, updated_at = now() where id = request_record.id returning * into request_record;
  end if;
  return request_record;
end;
$function$;

revoke all on function public.submit_booking_payment_receipt(uuid,uuid,uuid,numeric,text,text,timestamptz,text) from public;
revoke all on function public.decide_booking_payment_receipt(uuid,text,text) from public;
grant execute on function public.submit_booking_payment_receipt(uuid,uuid,uuid,numeric,text,text,timestamptz,text) to authenticated;
grant execute on function public.decide_booking_payment_receipt(uuid,text,text) to authenticated;

-- New schedule receipts must follow the approval ledger. Historical paid rows remain unchanged.
revoke execute on function public.record_booking_schedule_payment(uuid,uuid,uuid,numeric,text,text,timestamptz,text) from authenticated;

select pg_notify('pgrst', 'reload schema');
commit;
