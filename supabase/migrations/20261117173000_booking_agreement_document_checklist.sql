-- Post-booking agreement and document checklist.
-- Agents can progress their assigned deal's checklist. The workspace owner is
-- the only approver for restricted documents and the final agreement stage.
begin;

create table if not exists public.booking_document_checklist_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  deal_id uuid not null references public.deals(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  item_code text not null check (item_code in ('buyer_kyc','pan_card','booking_form','allotment_letter','agreement')),
  item_name text not null,
  required boolean not null default true,
  requires_owner_approval boolean not null default true,
  status text not null default 'not_started' check (status in ('not_started','requested','submitted','under_review','approved','rejected','not_required')),
  due_date date,
  notes text check (notes is null or char_length(notes) <= 2000),
  updated_by uuid references auth.users(id) on delete set null,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id, item_code),
  check (
    (status in ('approved','rejected') and reviewed_by is not null and reviewed_at is not null)
    or status not in ('approved','rejected')
  )
);

create index if not exists booking_document_checklist_booking_idx
  on public.booking_document_checklist_items (organization_id, booking_id, status);

create table if not exists public.booking_document_checklist_audit (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  deal_id uuid not null references public.deals(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  checklist_item_id uuid not null references public.booking_document_checklist_items(id) on delete cascade,
  action text not null check (action in ('seeded','updated','approved','rejected')),
  from_status text,
  to_status text not null,
  reason text,
  performed_by uuid references auth.users(id) on delete set null,
  performed_at timestamptz not null default now()
);

create index if not exists booking_document_checklist_audit_lookup_idx
  on public.booking_document_checklist_audit (organization_id, booking_id, performed_at desc);

drop trigger if exists booking_document_checklist_items_set_updated_at on public.booking_document_checklist_items;
create trigger booking_document_checklist_items_set_updated_at
before update on public.booking_document_checklist_items
for each row execute function public.set_updated_at();

alter table public.booking_document_checklist_items enable row level security;
alter table public.booking_document_checklist_audit enable row level security;

create policy "Accessible deal users can read booking document checklists"
on public.booking_document_checklist_items for select to authenticated using (
  public.can_access_deal(deal_id)
);

create policy "Accessible deal users can read booking document checklist audit"
on public.booking_document_checklist_audit for select to authenticated using (
  public.can_access_deal(deal_id)
);

create or replace function public.ensure_booking_document_checklist(
  requested_deal_id uuid,
  requested_booking_id uuid
)
returns setof public.booking_document_checklist_items
language plpgsql security definer set search_path = '' as $function$
declare
  deal_record public.deals;
  booking_record public.bookings;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  select * into deal_record
  from public.deals
  where id = requested_deal_id and deleted_at is null
  for update;

  if not found or deal_record.booking_id is distinct from requested_booking_id then
    raise exception 'The requested booking is not linked to this deal' using errcode = '23514';
  end if;

  if not public.is_organization_member(deal_record.organization_id)
    or not public.can_access_deal(deal_record.id) then
    raise exception 'You do not have access to this booking checklist' using errcode = '42501';
  end if;

  select * into booking_record
  from public.bookings
  where id = requested_booking_id and organization_id = deal_record.organization_id;

  if not found or booking_record.booking_status <> 'confirmed' or deal_record.status <> 'won' then
    raise exception 'A confirmed booking on a won deal is required' using errcode = '23514';
  end if;

  insert into public.booking_document_checklist_items (
    organization_id, deal_id, booking_id, item_code, item_name, required, requires_owner_approval, updated_by
  )
  values
    (deal_record.organization_id, deal_record.id, booking_record.id, 'buyer_kyc', 'Buyer KYC / address proof', true, true, auth.uid()),
    (deal_record.organization_id, deal_record.id, booking_record.id, 'pan_card', 'PAN card', true, true, auth.uid()),
    (deal_record.organization_id, deal_record.id, booking_record.id, 'booking_form', 'Signed booking form', true, true, auth.uid()),
    (deal_record.organization_id, deal_record.id, booking_record.id, 'allotment_letter', 'Allotment letter', true, true, auth.uid()),
    (deal_record.organization_id, deal_record.id, booking_record.id, 'agreement', 'Buyer agreement', true, true, auth.uid())
  on conflict (booking_id, item_code) do nothing;

  insert into public.booking_document_checklist_audit (
    organization_id, deal_id, booking_id, checklist_item_id, action, to_status, reason, performed_by
  )
  select c.organization_id, c.deal_id, c.booking_id, c.id, 'seeded', c.status, 'Checklist created for confirmed booking', auth.uid()
  from public.booking_document_checklist_items c
  where c.booking_id = booking_record.id
    and not exists (
      select 1 from public.booking_document_checklist_audit a
      where a.checklist_item_id = c.id and a.action = 'seeded'
    );

  return query
  select *
  from public.booking_document_checklist_items
  where booking_id = booking_record.id
  order by case item_code
    when 'buyer_kyc' then 1
    when 'pan_card' then 2
    when 'booking_form' then 3
    when 'allotment_letter' then 4
    when 'agreement' then 5
    else 99
  end;
end;
$function$;

create or replace function public.update_booking_document_checklist_item(
  requested_deal_id uuid,
  requested_booking_id uuid,
  requested_item_id uuid,
  requested_status text,
  requested_due_date date default null,
  requested_notes text default null
)
returns public.booking_document_checklist_items
language plpgsql security definer set search_path = '' as $function$
declare
  item_record public.booking_document_checklist_items;
  previous_status text;
  normalized_status text := lower(btrim(requested_status));
  normalized_notes text := nullif(btrim(requested_notes), '');
  is_owner boolean := false;
begin
  if auth.uid() is null then raise exception 'Authentication is required' using errcode = '42501'; end if;
  perform public.ensure_booking_document_checklist(requested_deal_id, requested_booking_id);
  select public.is_organization_owner(organization_id) into is_owner
  from public.deals where id = requested_deal_id;

  select * into item_record
  from public.booking_document_checklist_items
  where id = requested_item_id
    and deal_id = requested_deal_id
    and booking_id = requested_booking_id
  for update;

  if not found then raise exception 'Checklist item not found' using errcode = 'P0002'; end if;
  previous_status := item_record.status;
  if normalized_status not in ('not_started','requested','submitted','under_review','approved','rejected','not_required') then
    raise exception 'Choose a valid checklist status' using errcode = '23514';
  end if;
  if char_length(coalesce(normalized_notes, '')) > 2000 then
    raise exception 'Notes cannot exceed 2000 characters' using errcode = '23514';
  end if;
  if normalized_status in ('approved','rejected') and not is_owner then
    raise exception 'Only the workspace owner can approve or reject a document' using errcode = '42501';
  end if;
  if item_record.item_code = 'agreement' and normalized_status = 'approved' and not is_owner then
    raise exception 'Only the workspace owner can complete the agreement stage' using errcode = '42501';
  end if;
  if item_record.item_code = 'agreement' and normalized_status = 'approved' and exists (
    select 1
    from public.booking_document_checklist_items prerequisite
    where prerequisite.booking_id = requested_booking_id
      and prerequisite.id <> item_record.id
      and prerequisite.required
      and prerequisite.status <> 'not_required'
      and prerequisite.status <> 'approved'
  ) then
    raise exception 'Approve or mark not required all prerequisite documents before completing the agreement' using errcode = '23514';
  end if;

  update public.booking_document_checklist_items
  set status = normalized_status,
      due_date = requested_due_date,
      notes = normalized_notes,
      updated_by = auth.uid(),
      reviewed_by = case when normalized_status in ('approved','rejected') then auth.uid() else null end,
      reviewed_at = case when normalized_status in ('approved','rejected') then now() else null end,
      updated_at = now()
  where id = item_record.id
  returning * into item_record;

  insert into public.booking_document_checklist_audit (
    organization_id, deal_id, booking_id, checklist_item_id, action, from_status, to_status, reason, performed_by
  ) values (
    item_record.organization_id, item_record.deal_id, item_record.booking_id, item_record.id,
    case when normalized_status = 'approved' then 'approved' when normalized_status = 'rejected' then 'rejected' else 'updated' end,
    previous_status,
    item_record.status, normalized_notes, auth.uid()
  );

  return item_record;
end;
$function$;

revoke all on function public.ensure_booking_document_checklist(uuid,uuid) from public;
revoke all on function public.update_booking_document_checklist_item(uuid,uuid,uuid,text,date,text) from public;
grant execute on function public.ensure_booking_document_checklist(uuid,uuid) to authenticated;
grant execute on function public.update_booking_document_checklist_item(uuid,uuid,uuid,text,date,text) to authenticated;

select pg_notify('pgrst', 'reload schema');
commit;
