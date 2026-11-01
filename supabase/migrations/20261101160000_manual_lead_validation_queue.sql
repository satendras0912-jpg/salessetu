-- =========================================================
-- SalesSetu Enterprise
-- Manual lead validation queue
-- Manual review only. This migration does not assign or route leads.
-- =========================================================

begin;

create table if not exists public.lead_manual_validation_reviews (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  decision text not null
    check (decision in ('approved', 'hold', 'rejected')),

  reason text not null
    check (char_length(btrim(reason)) between 3 and 500),

  notes text
    check (notes is null or char_length(notes) <= 2_000),

  reviewed_by uuid
    references auth.users(id)
    on delete set null,

  reviewed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint lead_manual_validation_reviews_org_lead_unique
    unique (organization_id, lead_id)
);

create index if not exists lead_manual_validation_reviews_queue_idx
  on public.lead_manual_validation_reviews (
    organization_id,
    decision,
    reviewed_at desc
  );

create trigger lead_manual_validation_reviews_set_updated_at
before update on public.lead_manual_validation_reviews
for each row
execute function public.set_updated_at();

create table if not exists public.lead_manual_validation_audits (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  review_id uuid not null
    references public.lead_manual_validation_reviews(id)
    on delete cascade,

  decision text not null
    check (decision in ('approved', 'hold', 'rejected')),

  reason text not null,
  notes text,

  decided_by uuid
    references auth.users(id)
    on delete set null,

  decided_at timestamptz not null default now()
);

create index if not exists lead_manual_validation_audits_lead_idx
  on public.lead_manual_validation_audits (
    organization_id,
    lead_id,
    decided_at desc
  );

alter table public.lead_manual_validation_reviews
  enable row level security;

alter table public.lead_manual_validation_audits
  enable row level security;

drop policy if exists "Manual lead validation reviews are visible to reviewers"
  on public.lead_manual_validation_reviews;

create policy "Manual lead validation reviews are visible to reviewers"
on public.lead_manual_validation_reviews
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'lead_validation.view'
  )
  or public.has_organization_permission(
    organization_id,
    'lead_validation.review'
  )
  or exists (
    select 1
    from public.organization_members member
    where member.organization_id =
      lead_manual_validation_reviews.organization_id
      and member.user_id = auth.uid()
      and member.membership_status = 'active'
      and member.is_owner = true
  )
);

drop policy if exists "Manual lead validation audits are visible to reviewers"
  on public.lead_manual_validation_audits;

create policy "Manual lead validation audits are visible to reviewers"
on public.lead_manual_validation_audits
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'lead_validation.view'
  )
  or public.has_organization_permission(
    organization_id,
    'lead_validation.review'
  )
  or exists (
    select 1
    from public.organization_members member
    where member.organization_id =
      lead_manual_validation_audits.organization_id
      and member.user_id = auth.uid()
      and member.membership_status = 'active'
      and member.is_owner = true
  )
);

create or replace function public.decide_manual_lead_validation(
  p_lead_id uuid,
  p_decision text,
  p_reason text,
  p_notes text default null
)
returns public.lead_manual_validation_reviews
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_lead public.leads;
  review_record public.lead_manual_validation_reviews;
  normalized_decision text := lower(btrim(coalesce(p_decision, '')));
  normalized_reason text := btrim(coalesce(p_reason, ''));
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  if auth.uid() is null and auth.role() <> 'service_role' then
    raise exception 'Authentication is required';
  end if;

  if normalized_decision not in ('approved', 'hold', 'rejected') then
    raise exception 'Invalid manual validation decision';
  end if;

  if char_length(normalized_reason) < 3
    or char_length(normalized_reason) > 500 then
    raise exception
      'Validation reason must contain between 3 and 500 characters';
  end if;

  if normalized_notes is not null
    and char_length(normalized_notes) > 2000 then
    raise exception 'Validation notes cannot exceed 2000 characters';
  end if;

  select *
  into target_lead
  from public.leads lead
  where lead.id = p_lead_id
    and lead.deleted_at is null
  for update;

  if not found then
    raise exception 'Lead not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_lead.organization_id,
      'lead_validation.review'
    )
    and not exists (
      select 1
      from public.organization_members member
      where member.organization_id =
        target_lead.organization_id
        and member.user_id = auth.uid()
        and member.membership_status = 'active'
        and member.is_owner = true
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.lead_manual_validation_reviews (
    organization_id,
    lead_id,
    decision,
    reason,
    notes,
    reviewed_by,
    reviewed_at
  )
  values (
    target_lead.organization_id,
    target_lead.id,
    normalized_decision,
    normalized_reason,
    normalized_notes,
    auth.uid(),
    now()
  )
  on conflict (organization_id, lead_id)
  do update set
    decision = excluded.decision,
    reason = excluded.reason,
    notes = excluded.notes,
    reviewed_by = excluded.reviewed_by,
    reviewed_at = excluded.reviewed_at,
    updated_at = now()
  returning *
  into review_record;

  insert into public.lead_manual_validation_audits (
    organization_id,
    lead_id,
    review_id,
    decision,
    reason,
    notes,
    decided_by,
    decided_at
  )
  values (
    review_record.organization_id,
    review_record.lead_id,
    review_record.id,
    review_record.decision,
    review_record.reason,
    review_record.notes,
    auth.uid(),
    review_record.reviewed_at
  );

  update public.leads
  set
    qualification_status =
      case review_record.decision
        when 'approved' then 'qualified'
        when 'hold' then 'manual_review'
        else 'unqualified'
      end,
    qualification_reason = review_record.reason,
    qualification_summary = review_record.notes,
    qualified_at =
      case
        when review_record.decision = 'approved'
          then coalesce(qualified_at, now())
        else qualified_at
      end,
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_lead.id;

  return review_record;
end;
$$;

revoke all
on function public.decide_manual_lead_validation(
  uuid,text,text,text
)
from public;

grant execute
on function public.decide_manual_lead_validation(
  uuid,text,text,text
)
to authenticated, service_role;

commit;
