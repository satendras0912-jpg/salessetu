begin;

-- Deal conversion is an authenticated, tenant-scoped transaction.
-- The function keeps the existing validation and completed-visit gates in
-- the database while avoiding a second, inconsistent RLS authorization path.

create or replace function public.create_deal_from_qualified_visit(
  requested_lead_id uuid,
  requested_site_visit_id uuid,
  requested_inventory_unit_id uuid default null,
  requested_assigned_to uuid default null,
  requested_currency_code text default 'INR',
  requested_booking_probability numeric default null,
  requested_next_action_at timestamptz default null,
  requested_notes text default null
)
returns table (
  id uuid,
  lead_id uuid,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_lead public.leads;
begin
  if auth.uid() is null
    and auth.role() <> 'service_role' then
    raise exception 'Authentication is required'
      using errcode = '42501';
  end if;

  perform public.assert_deal_conversion_eligibility(
    requested_lead_id,
    requested_site_visit_id
  );

  select *
  into target_lead
  from public.leads lead
  where lead.id = requested_lead_id
    and lead.deleted_at is null;

  if not found then
    raise exception 'Lead not found'
      using errcode = 'P0002';
  end if;

  return query
  insert into public.deals as deal (
    organization_id,
    lead_id,
    site_visit_id,
    inventory_unit_id,
    assigned_to,
    currency_code,
    booking_probability,
    next_action_at,
    notes
  )
  values (
    target_lead.organization_id,
    requested_lead_id,
    requested_site_visit_id,
    requested_inventory_unit_id,
    requested_assigned_to,
    requested_currency_code,
    requested_booking_probability,
    requested_next_action_at,
    requested_notes
  )
  returning
    deal.id,
    deal.lead_id,
    deal.updated_at;
end;
$function$;

revoke all
on function public.create_deal_from_qualified_visit(
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  numeric,
  timestamptz,
  text
)
from public;

grant execute
on function public.create_deal_from_qualified_visit(
  uuid,
  uuid,
  uuid,
  uuid,
  text,
  numeric,
  timestamptz,
  text
)
to authenticated, service_role;

select pg_notify(
  'pgrst',
  'reload schema'
);

commit;
