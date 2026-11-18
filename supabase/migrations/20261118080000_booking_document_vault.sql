-- Private, tenant-scoped document vault for confirmed booking checklists.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'booking-documents',
  'booking-documents',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create table if not exists public.booking_document_files (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  deal_id uuid not null references public.deals(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  checklist_item_id uuid not null references public.booking_document_checklist_items(id) on delete cascade,
  storage_path text not null unique,
  original_filename text not null check (char_length(original_filename) between 1 and 180),
  mime_type text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  byte_size integer not null check (byte_size > 0 and byte_size <= 10485760),
  is_current boolean not null default true,
  review_status text not null default 'pending' check (review_status in ('pending', 'approved', 'rejected')),
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  uploaded_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz
);

create unique index if not exists booking_document_files_one_current_per_item_idx
  on public.booking_document_files (checklist_item_id)
  where is_current;

create index if not exists booking_document_files_booking_lookup_idx
  on public.booking_document_files (organization_id, booking_id, checklist_item_id)
  where is_current;

alter table public.booking_document_files enable row level security;

create policy "Accessible deal users can read booking document metadata"
on public.booking_document_files for select to authenticated using (
  public.can_access_deal(deal_id)
);

drop policy if exists "Accessible booking document users can read private files" on storage.objects;
create policy "Accessible booking document users can read private files"
on storage.objects for select to authenticated using (
  bucket_id = 'booking-documents'
  and exists (
    select 1
    from public.booking_document_files document_file
    where document_file.storage_path = name
      and document_file.is_current
      and public.can_access_deal(document_file.deal_id)
  )
);

create or replace function public.register_booking_document_upload(
  requested_deal_id uuid,
  requested_booking_id uuid,
  requested_item_id uuid,
  requested_storage_path text,
  requested_original_filename text,
  requested_mime_type text,
  requested_byte_size integer
)
returns public.booking_document_files
language plpgsql security definer set search_path = '' as $function$
declare
  item_record public.booking_document_checklist_items;
  file_record public.booking_document_files;
  previous_status text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  perform public.ensure_booking_document_checklist(requested_deal_id, requested_booking_id);

  select * into item_record
  from public.booking_document_checklist_items
  where id = requested_item_id
    and deal_id = requested_deal_id
    and booking_id = requested_booking_id
  for update;

  if not found then
    raise exception 'Checklist item not found' using errcode = 'P0002';
  end if;

  if char_length(btrim(requested_storage_path)) < 12
    or char_length(btrim(requested_original_filename)) not between 1 and 180
    or requested_mime_type not in ('application/pdf', 'image/jpeg', 'image/png')
    or requested_byte_size is null
    or requested_byte_size <= 0
    or requested_byte_size > 10485760 then
    raise exception 'The uploaded file does not meet document-vault requirements' using errcode = '23514';
  end if;

  previous_status := item_record.status;

  update public.booking_document_files
  set is_current = false
  where checklist_item_id = item_record.id
    and is_current;

  insert into public.booking_document_files (
    organization_id, deal_id, booking_id, checklist_item_id, storage_path,
    original_filename, mime_type, byte_size, uploaded_by
  ) values (
    item_record.organization_id, item_record.deal_id, item_record.booking_id, item_record.id,
    btrim(requested_storage_path), btrim(requested_original_filename), requested_mime_type,
    requested_byte_size, auth.uid()
  ) returning * into file_record;

  update public.booking_document_checklist_items
  set status = 'submitted',
      updated_by = auth.uid(),
      reviewed_by = null,
      reviewed_at = null,
      updated_at = now()
  where id = item_record.id;

  insert into public.booking_document_checklist_audit (
    organization_id, deal_id, booking_id, checklist_item_id, action,
    from_status, to_status, reason, performed_by
  ) values (
    item_record.organization_id, item_record.deal_id, item_record.booking_id, item_record.id,
    'updated', previous_status, 'submitted',
    'Document uploaded: ' || btrim(requested_original_filename), auth.uid()
  );

  return file_record;
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
    raise exception 'Only the workspace owner can approve or reject a checklist document' using errcode = '42501';
  end if;
  if normalized_status = 'approved' and not exists (
    select 1 from public.booking_document_files document_file
    where document_file.checklist_item_id = item_record.id
      and document_file.is_current
  ) then
    raise exception 'Upload a private PDF, JPG or PNG before approving this document' using errcode = '23514';
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

  update public.booking_document_files
  set review_status = case
        when normalized_status = 'approved' then 'approved'
        when normalized_status = 'rejected' then 'rejected'
        else 'pending'
      end,
      reviewed_by = case when normalized_status in ('approved','rejected') then auth.uid() else null end,
      reviewed_at = case when normalized_status in ('approved','rejected') then now() else null end
  where checklist_item_id = item_record.id
    and is_current;

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

revoke all on function public.register_booking_document_upload(uuid,uuid,uuid,text,text,text,integer) from public;
grant execute on function public.register_booking_document_upload(uuid,uuid,uuid,text,text,text,integer) to authenticated;

select pg_notify('pgrst', 'reload schema');
commit;
