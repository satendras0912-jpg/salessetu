-- ============================================================================
-- SalesSetu Enterprise
-- Gated Deal Conversion
-- Purpose:
--   Allow DealOS creation only from a manually approved lead with a completed
--   site visit. Held/rejected leads continue only through an active owner
--   override already recorded in the manual-validation audit.
--   No routing, notification or customer communication is triggered here.
-- ============================================================================

begin;

create or replace function public.assert_deal_conversion_eligibility(
  requested_lead_id uuid,
  requested_site_visit_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_lead public.leads;
  target_visit public.site_visits;
  latest_decision text;
begin
  if auth.uid() is null
    and auth.role() <> 'service_role' then
    raise exception 'Authentication is required';
  end if;

  if requested_lead_id is null
    or requested_site_visit_id is null then
    raise exception
      'A lead and a completed site visit are required before creating a deal'
      using errcode = '23514';
  end if;

  select *
  into target_lead
  from public.leads lead
  where lead.id = requested_lead_id
    and lead.deleted_at is null
  for update;

  if not found then
    raise exception 'Lead not found' using errcode = 'P0002';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_lead.organization_id,
      'deals.create'
    )
    and not public.is_organization_owner(
      target_lead.organization_id
    ) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;

  select review.decision
  into latest_decision
  from public.lead_manual_validation_reviews review
  where review.organization_id = target_lead.organization_id
    and review.lead_id = target_lead.id
  order by review.reviewed_at desc, review.id desc
  limit 1;

  if latest_decision = 'approved' then
    null;
  elsif latest_decision in ('hold', 'rejected') then
    perform public.assert_manual_validation_sales_access(
      target_lead.id
    );
  else
    raise exception
      'Lead requires manual validation approval before deal conversion'
      using errcode = '42501';
  end if;

  select *
  into target_visit
  from public.site_visits visit
  where visit.id = requested_site_visit_id
    and visit.organization_id = target_lead.organization_id
    and visit.lead_id = target_lead.id;

  if not found then
    raise exception
      'The selected site visit does not belong to this lead'
      using errcode = '23514';
  end if;

  if target_visit.status <> 'completed' then
    raise exception
      'A completed site visit is required before deal conversion'
      using errcode = '23514';
  end if;
end;
$function$;

revoke all
on function public.assert_deal_conversion_eligibility(uuid, uuid)
from public;

grant execute
on function public.assert_deal_conversion_eligibility(uuid, uuid)
to authenticated, service_role;

create or replace function public.enforce_deal_conversion_eligibility()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if tg_op = 'INSERT'
    or new.lead_id is distinct from old.lead_id
    or new.site_visit_id is distinct from old.site_visit_id then
    perform public.assert_deal_conversion_eligibility(
      new.lead_id,
      new.site_visit_id
    );
  end if;

  return new;
end;
$function$;

drop trigger if exists "00_deals_conversion_eligibility"
  on public.deals;

create trigger "00_deals_conversion_eligibility"
before insert or update of lead_id, site_visit_id
on public.deals
for each row
execute function public.enforce_deal_conversion_eligibility();

create unique index if not exists deals_one_active_per_site_visit_idx
on public.deals (site_visit_id)
where site_visit_id is not null
  and deleted_at is null
  and status <> 'cancelled';

commit;
