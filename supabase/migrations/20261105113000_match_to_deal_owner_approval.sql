-- Match → Deal conversion: a sales user requests; only the workspace owner
-- may approve and create the DealOS record. This never reserves inventory,
-- changes lead assignment/routing, or contacts a customer.
begin;

create table if not exists public.deal_conversion_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  site_visit_id uuid not null references public.site_visits(id) on delete restrict,
  inventory_unit_id uuid not null references public.inventory_units(id) on delete restrict,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  request_notes text check (request_notes is null or char_length(request_notes) <= 2000),
  requested_by uuid references auth.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz,
  decision_reason text check (decision_reason is null or char_length(decision_reason) <= 500),
  deal_id uuid references public.deals(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists deal_conversion_requests_one_pending_idx
  on public.deal_conversion_requests(organization_id, lead_id)
  where status = 'pending';

create index if not exists deal_conversion_requests_owner_queue_idx
  on public.deal_conversion_requests(organization_id, status, requested_at asc);

drop trigger if exists deal_conversion_requests_set_updated_at on public.deal_conversion_requests;
create trigger deal_conversion_requests_set_updated_at
before update on public.deal_conversion_requests
for each row execute function public.set_updated_at();

alter table public.deal_conversion_requests enable row level security;

create policy "Deal conversion requests are visible to deal creators and owners"
on public.deal_conversion_requests for select to authenticated using (
  public.has_organization_permission(organization_id, 'deals.create')
  or public.is_organization_owner(organization_id)
);

create or replace function public.assert_suitable_inventory_match(
  requested_lead_id uuid,
  requested_inventory_unit_id uuid
)
returns void language plpgsql security definer set search_path = '' as $$
declare target_lead public.leads; latest_review_decision text;
begin
  select * into target_lead from public.leads lead
  where lead.id = requested_lead_id and lead.deleted_at is null;
  if not found then raise exception 'Lead not found' using errcode = 'P0002'; end if;
  if not exists (
    select 1 from public.inventory_units unit
    where unit.id = requested_inventory_unit_id
      and unit.organization_id = target_lead.organization_id
      and unit.deleted_at is null
      and unit.unit_status = 'available'
      and unit.sales_status = 'open'
  ) then raise exception 'The selected inventory unit is not available in this workspace' using errcode = '23514'; end if;
  select review.decision into latest_review_decision
  from public.lead_inventory_match_reviews review
    where review.organization_id = target_lead.organization_id
      and review.lead_id = target_lead.id
      and review.inventory_unit_id = requested_inventory_unit_id
    order by review.reviewed_at desc, review.id desc
    limit 1;
  if latest_review_decision is distinct from 'suitable' then
    raise exception 'A current suitable manual inventory match is required before deal conversion' using errcode = '42501';
  end if;
end;
$$;

create or replace function public.request_deal_conversion(
  requested_lead_id uuid,
  requested_site_visit_id uuid,
  requested_notes text default null
)
returns public.deal_conversion_requests language plpgsql security definer set search_path = '' as $$
declare target_lead public.leads; request_record public.deal_conversion_requests; selected_inventory_unit_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication is required' using errcode = '42501'; end if;
  select * into target_lead from public.leads lead where lead.id = requested_lead_id and lead.deleted_at is null;
  if not found then raise exception 'Lead not found' using errcode = 'P0002'; end if;
  if not public.has_organization_permission(target_lead.organization_id, 'deals.create')
     and not public.is_organization_owner(target_lead.organization_id) then raise exception 'Permission denied' using errcode = '42501'; end if;
  perform public.assert_deal_conversion_eligibility(requested_lead_id, requested_site_visit_id);
  select current_review.inventory_unit_id into selected_inventory_unit_id
  from (
    select distinct on (review.inventory_unit_id)
      review.inventory_unit_id, review.decision, review.reviewed_at, review.id
    from public.lead_inventory_match_reviews review
    where review.organization_id = target_lead.organization_id
      and review.lead_id = target_lead.id
    order by review.inventory_unit_id, review.reviewed_at desc, review.id desc
  ) current_review
  where current_review.decision = 'suitable'
  order by current_review.reviewed_at desc, current_review.id desc
  limit 1;
  if selected_inventory_unit_id is null then raise exception 'A suitable manual inventory match is required before deal conversion' using errcode = '42501'; end if;
  perform public.assert_suitable_inventory_match(requested_lead_id, selected_inventory_unit_id);
  insert into public.deal_conversion_requests(organization_id,lead_id,site_visit_id,inventory_unit_id,request_notes,requested_by)
  values(target_lead.organization_id,requested_lead_id,requested_site_visit_id,selected_inventory_unit_id,nullif(btrim(requested_notes),''),auth.uid())
  returning * into request_record;
  return request_record;
end;
$$;

create or replace function public.decide_deal_conversion_request(
  requested_request_id uuid,
  requested_decision text,
  requested_reason text
)
returns table(request_id uuid, deal_id uuid, status text) language plpgsql security definer set search_path = '' as $$
declare request_record public.deal_conversion_requests; new_deal_id uuid; normalized_decision text := lower(btrim(requested_decision)); normalized_reason text := btrim(coalesce(requested_reason,''));
begin
  if auth.uid() is null then raise exception 'Authentication is required' using errcode = '42501'; end if;
  select * into request_record from public.deal_conversion_requests request where request.id = requested_request_id for update;
  if not found then raise exception 'Deal conversion request not found' using errcode = 'P0002'; end if;
  if not public.is_organization_owner(request_record.organization_id) then raise exception 'Only the workspace owner can approve a deal conversion' using errcode = '42501'; end if;
  if request_record.status <> 'pending' then raise exception 'This deal conversion request has already been decided' using errcode = '23505'; end if;
  if normalized_decision not in ('approved','rejected') or char_length(normalized_reason) < 3 or char_length(normalized_reason) > 500 then raise exception 'A valid approval decision and reason are required' using errcode = '23514'; end if;
  if normalized_decision = 'approved' then
    perform public.assert_deal_conversion_eligibility(request_record.lead_id, request_record.site_visit_id);
    perform public.assert_suitable_inventory_match(request_record.lead_id, request_record.inventory_unit_id);
    insert into public.deals(organization_id,lead_id,site_visit_id,inventory_unit_id,notes)
    values(request_record.organization_id,request_record.lead_id,request_record.site_visit_id,request_record.inventory_unit_id,request_record.request_notes)
    returning id into new_deal_id;
  end if;
  update public.deal_conversion_requests set status=normalized_decision, decided_by=auth.uid(), decided_at=now(), decision_reason=normalized_reason, deal_id=new_deal_id, updated_at=now() where id=request_record.id;
  return query select request_record.id, new_deal_id, normalized_decision;
end;
$$;

revoke all on function public.assert_suitable_inventory_match(uuid,uuid) from public;
revoke all on function public.request_deal_conversion(uuid,uuid,text) from public;
revoke all on function public.decide_deal_conversion_request(uuid,text,text) from public;
grant execute on function public.request_deal_conversion(uuid,uuid,text) to authenticated, service_role;
grant execute on function public.decide_deal_conversion_request(uuid,text,text) to authenticated, service_role;

-- The prior direct RPC bypasses the owner-approval queue, so it is no longer
-- callable by authenticated client sessions. Existing records remain intact.
revoke execute on function public.create_deal_from_qualified_visit(uuid,uuid,uuid,uuid,text,numeric,timestamptz,text) from authenticated;

select pg_notify('pgrst','reload schema');
commit;
