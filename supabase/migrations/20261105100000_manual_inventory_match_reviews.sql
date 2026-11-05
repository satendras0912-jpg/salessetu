-- =========================================================
-- SalesSetu Enterprise
-- Manual inventory match reviews
-- Internal decisions only: no lead assignment, inventory reservation,
-- routing, alerts or customer communication.
-- =========================================================

begin;

insert into public.permissions (module, action, code, description)
values (
  'inventory',
  'match_review',
  'inventory.match_review',
  'Record internal suitable or not-suitable decisions for inventory suggestions'
)
on conflict (code) do nothing;

insert into public.role_permissions (role_id, permission_id)
select roles.id, permissions.id
from public.roles roles
join public.permissions permissions
  on permissions.code = 'inventory.match_review'
where roles.code in (
  'platform_admin',
  'organization_admin',
  'sales_manager',
  'sales_agent'
)
on conflict (role_id, permission_id) do nothing;

create table if not exists public.lead_inventory_match_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  inventory_unit_id uuid not null references public.inventory_units(id) on delete cascade,
  decision text not null check (decision in ('suitable', 'not_suitable')),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  notes text check (notes is null or char_length(notes) <= 2000),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint lead_inventory_match_reviews_one_current_decision
    unique (organization_id, lead_id, inventory_unit_id)
);

create index if not exists lead_inventory_match_reviews_lead_idx
  on public.lead_inventory_match_reviews (
    organization_id, lead_id, reviewed_at desc
  );

create table if not exists public.lead_inventory_match_review_audits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  lead_id uuid not null references public.leads(id) on delete cascade,
  inventory_unit_id uuid not null references public.inventory_units(id) on delete cascade,
  review_id uuid not null references public.lead_inventory_match_reviews(id) on delete cascade,
  previous_decision text check (previous_decision is null or previous_decision in ('suitable', 'not_suitable')),
  previous_reason text,
  previous_notes text,
  decision text not null check (decision in ('suitable', 'not_suitable')),
  reason text not null,
  notes text,
  decided_by uuid references auth.users(id) on delete set null,
  decided_at timestamptz not null default now()
);

create index if not exists lead_inventory_match_review_audits_lead_idx
  on public.lead_inventory_match_review_audits (
    organization_id, lead_id, decided_at desc
  );

create trigger lead_inventory_match_reviews_set_updated_at
before update on public.lead_inventory_match_reviews
for each row execute function public.set_updated_at();

alter table public.lead_inventory_match_reviews enable row level security;
alter table public.lead_inventory_match_review_audits enable row level security;

create policy "Inventory match reviews are visible to inventory viewers"
on public.lead_inventory_match_reviews
for select to authenticated
using (
  public.has_organization_permission(organization_id, 'inventory.view')
  or public.has_organization_permission(organization_id, 'inventory.match_review')
  or exists (
    select 1 from public.organization_members member
    where member.organization_id = lead_inventory_match_reviews.organization_id
      and member.user_id = auth.uid()
      and member.membership_status = 'active'
      and member.is_owner = true
  )
);

create policy "Inventory match review audits are visible to inventory viewers"
on public.lead_inventory_match_review_audits
for select to authenticated
using (
  public.has_organization_permission(organization_id, 'inventory.view')
  or public.has_organization_permission(organization_id, 'inventory.match_review')
  or exists (
    select 1 from public.organization_members member
    where member.organization_id = lead_inventory_match_review_audits.organization_id
      and member.user_id = auth.uid()
      and member.membership_status = 'active'
      and member.is_owner = true
  )
);

create or replace function public.decide_lead_inventory_match_review(
  p_lead_id uuid,
  p_inventory_unit_id uuid,
  p_decision text,
  p_reason text,
  p_notes text default null
)
returns public.lead_inventory_match_reviews
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_lead public.leads;
  target_inventory public.inventory_units;
  previous_review public.lead_inventory_match_reviews;
  review_record public.lead_inventory_match_reviews;
  normalized_decision text := lower(btrim(coalesce(p_decision, '')));
  normalized_reason text := btrim(coalesce(p_reason, ''));
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  if auth.uid() is null and auth.role() <> 'service_role' then
    raise exception 'Authentication is required';
  end if;

  if normalized_decision not in ('suitable', 'not_suitable') then
    raise exception 'Invalid inventory match review decision';
  end if;

  if char_length(normalized_reason) < 3 or char_length(normalized_reason) > 500 then
    raise exception 'Review reason must contain between 3 and 500 characters';
  end if;

  if normalized_notes is not null and char_length(normalized_notes) > 2000 then
    raise exception 'Review notes cannot exceed 2000 characters';
  end if;

  select * into target_lead
  from public.leads lead
  where lead.id = p_lead_id and lead.deleted_at is null
  for update;

  if not found then
    raise exception 'Lead not found';
  end if;

  select * into target_inventory
  from public.inventory_units unit
  where unit.id = p_inventory_unit_id
    and unit.organization_id = target_lead.organization_id
    and unit.deleted_at is null
  for update;

  if not found then
    raise exception 'Inventory unit not found in this workspace';
  end if;

  if target_inventory.unit_status <> 'available'
    or target_inventory.sales_status <> 'open'
    or nullif(
      btrim(target_inventory.metadata ->> 'verification_date'),
      ''
    ) is null then
    raise exception 'Only verified available inventory can be reviewed';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_lead.organization_id,
      'inventory.match_review'
    )
    and not exists (
      select 1 from public.organization_members member
      where member.organization_id = target_lead.organization_id
        and member.user_id = auth.uid()
        and member.membership_status = 'active'
        and member.is_owner = true
    ) then
    raise exception 'Permission denied';
  end if;

  select * into previous_review
  from public.lead_inventory_match_reviews review
  where review.organization_id = target_lead.organization_id
    and review.lead_id = target_lead.id
    and review.inventory_unit_id = target_inventory.id
  for update;

  insert into public.lead_inventory_match_reviews (
    organization_id, lead_id, inventory_unit_id, decision, reason, notes,
    reviewed_by, reviewed_at
  ) values (
    target_lead.organization_id, target_lead.id, target_inventory.id,
    normalized_decision, normalized_reason, normalized_notes, auth.uid(), now()
  )
  on conflict (organization_id, lead_id, inventory_unit_id)
  do update set
    decision = excluded.decision,
    reason = excluded.reason,
    notes = excluded.notes,
    reviewed_by = excluded.reviewed_by,
    reviewed_at = excluded.reviewed_at,
    updated_at = now()
  returning * into review_record;

  insert into public.lead_inventory_match_review_audits (
    organization_id, lead_id, inventory_unit_id, review_id,
    previous_decision, previous_reason, previous_notes,
    decision, reason, notes, decided_by, decided_at
  ) values (
    review_record.organization_id, review_record.lead_id,
    review_record.inventory_unit_id, review_record.id,
    previous_review.decision, previous_review.reason, previous_review.notes,
    review_record.decision, review_record.reason, review_record.notes,
    auth.uid(), review_record.reviewed_at
  );

  -- No mutation is made to leads, assignments, reservations, routing,
  -- notifications or customer communication.
  return review_record;
end;
$$;

revoke all on function public.decide_lead_inventory_match_review(
  uuid, uuid, text, text, text
) from public;

grant execute on function public.decide_lead_inventory_match_review(
  uuid, uuid, text, text, text
) to authenticated, service_role;

commit;
