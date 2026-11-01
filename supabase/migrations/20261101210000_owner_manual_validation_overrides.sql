-- =========================================================
-- SalesSetu Enterprise
-- Owner-only override for held and rejected manual validations
-- =========================================================

begin;

create table if not exists public.lead_manual_validation_overrides (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  status text not null default 'active'
    check (status in ('active', 'revoked')),

  override_reason text not null
    check (char_length(btrim(override_reason)) between 3 and 500),

  notes text
    check (notes is null or char_length(notes) <= 2_000),

  granted_by uuid
    references auth.users(id)
    on delete set null,

  granted_at timestamptz not null default now(),

  revoked_by uuid
    references auth.users(id)
    on delete set null,

  revoked_at timestamptz,
  revoke_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists lead_manual_validation_overrides_one_active_idx
  on public.lead_manual_validation_overrides (
    organization_id,
    lead_id
  )
  where status = 'active';

create index if not exists lead_manual_validation_overrides_lead_idx
  on public.lead_manual_validation_overrides (
    organization_id,
    lead_id,
    granted_at desc
  );

create trigger lead_manual_validation_overrides_set_updated_at
before update on public.lead_manual_validation_overrides
for each row
execute function public.set_updated_at();

alter table public.lead_manual_validation_overrides
  enable row level security;

drop policy if exists "Manual validation overrides are visible to reviewers"
  on public.lead_manual_validation_overrides;

create policy "Manual validation overrides are visible to reviewers"
on public.lead_manual_validation_overrides
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
      lead_manual_validation_overrides.organization_id
      and member.user_id = auth.uid()
      and member.membership_status = 'active'
      and member.is_owner = true
  )
);

create or replace function public.assert_manual_validation_sales_access(
  requested_lead_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  latest_decision text;
begin
  select review.decision
  into latest_decision
  from public.lead_manual_validation_reviews review
  where review.lead_id = requested_lead_id
  order by review.reviewed_at desc, review.id desc
  limit 1;

  if latest_decision not in ('hold', 'rejected') then
    return;
  end if;

  if exists (
    select 1
    from public.lead_manual_validation_overrides override
    where override.lead_id = requested_lead_id
      and override.status = 'active'
  ) then
    return;
  end if;

  raise exception using
    message = 'Lead sales activity is blocked by manual validation',
    detail = 'The lead is on hold or rejected. A workspace owner must record an override before sales activity can continue.',
    errcode = '42501';
end;
$$;

revoke all
on function public.assert_manual_validation_sales_access(uuid)
from public;

create or replace function public.grant_manual_lead_validation_override(
  p_lead_id uuid,
  p_override_reason text,
  p_notes text default null
)
returns public.lead_manual_validation_overrides
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_lead public.leads;
  latest_decision text;
  override_record public.lead_manual_validation_overrides;
  normalized_reason text := btrim(coalesce(p_override_reason, ''));
  normalized_notes text := nullif(btrim(coalesce(p_notes, '')), '');
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if char_length(normalized_reason) < 3
    or char_length(normalized_reason) > 500 then
    raise exception
      'Override reason must contain between 3 and 500 characters';
  end if;

  if normalized_notes is not null
    and char_length(normalized_notes) > 2000 then
    raise exception 'Override notes cannot exceed 2000 characters';
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

  if not exists (
    select 1
    from public.organization_members member
    where member.organization_id = target_lead.organization_id
      and member.user_id = auth.uid()
      and member.membership_status = 'active'
      and member.is_owner = true
  ) then
    raise exception 'Only the workspace owner can override manual validation';
  end if;

  select review.decision
  into latest_decision
  from public.lead_manual_validation_reviews review
  where review.organization_id = target_lead.organization_id
    and review.lead_id = target_lead.id
  order by review.reviewed_at desc, review.id desc
  limit 1;

  if latest_decision not in ('hold', 'rejected') then
    raise exception
      'An owner override is only available for held or rejected leads';
  end if;

  update public.lead_manual_validation_overrides
  set
    status = 'revoked',
    revoked_by = auth.uid(),
    revoked_at = now(),
    revoke_reason = 'Replaced by a newer owner override',
    updated_at = now()
  where organization_id = target_lead.organization_id
    and lead_id = target_lead.id
    and status = 'active';

  insert into public.lead_manual_validation_overrides (
    organization_id,
    lead_id,
    status,
    override_reason,
    notes,
    granted_by,
    granted_at
  )
  values (
    target_lead.organization_id,
    target_lead.id,
    'active',
    normalized_reason,
    normalized_notes,
    auth.uid(),
    now()
  )
  returning *
  into override_record;

  return override_record;
end;
$$;

revoke all
on function public.grant_manual_lead_validation_override(uuid,text,text)
from public;

grant execute
on function public.grant_manual_lead_validation_override(uuid,text,text)
to authenticated, service_role;

create or replace function public.enforce_manual_validation_follow_up_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT'
    or new.status not in ('completed', 'cancelled', 'failed') then
    perform public.assert_manual_validation_sales_access(new.lead_id);
  end if;

  return new;
end;
$$;

drop trigger if exists follow_up_tasks_manual_validation_gate
  on public.follow_up_tasks;

create trigger follow_up_tasks_manual_validation_gate
before insert or update on public.follow_up_tasks
for each row
execute function public.enforce_manual_validation_follow_up_gate();

create or replace function public.enforce_manual_validation_site_visit_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT'
    or new.status not in (
      'completed',
      'cancelled',
      'no_show',
      'failed'
    ) then
    perform public.assert_manual_validation_sales_access(new.lead_id);
  end if;

  return new;
end;
$$;

drop trigger if exists site_visits_manual_validation_gate
  on public.site_visits;

create trigger site_visits_manual_validation_gate
before insert or update on public.site_visits
for each row
execute function public.enforce_manual_validation_site_visit_gate();

create or replace function public.enforce_manual_validation_assignment_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.assert_manual_validation_sales_access(new.lead_id);
  end if;

  return new;
end;
$$;

drop trigger if exists lead_assignments_manual_validation_gate
  on public.lead_assignments;

create trigger lead_assignments_manual_validation_gate
before insert on public.lead_assignments
for each row
execute function public.enforce_manual_validation_assignment_gate();

commit;
