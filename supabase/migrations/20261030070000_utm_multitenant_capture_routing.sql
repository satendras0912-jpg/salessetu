-- =========================================================
-- SalesSetu Enterprise
-- Migration: UTM multi-tenant capture routing
-- Purpose: Resolve a public capture route to a trusted
--          organization before creating a lead.
-- =========================================================

begin;

-- The route belongs to the organization. A public form can identify a route,
-- but it never supplies organization_id to the lead table.
create table if not exists public.lead_capture_routes (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_source_id uuid
    references public.lead_sources(id)
    on delete set null,

  route_key text not null
    check (
      route_key = lower(trim(route_key))
      and route_key ~ '^[a-z0-9][a-z0-9_-]{2,127}$'
    ),

  display_name text not null,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint lead_capture_routes_route_key_unique unique (route_key)
);

create index if not exists lead_capture_routes_organization_idx
  on public.lead_capture_routes(organization_id, is_active);

create trigger lead_capture_routes_set_updated_at
before update on public.lead_capture_routes
for each row
execute function public.set_updated_at();

alter table public.lead_capture_routes
  enable row level security;

create policy "Authorized users can manage lead capture routes"
on public.lead_capture_routes
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.manage_sources'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'leads.manage_sources'
  )
);

-- n8n writes to this intake table. It has no organization_id by design.
-- The database trigger below owns the organization resolution.
create table if not exists public.lead_capture_intake (
  id uuid primary key default gen_random_uuid(),

  route_key text not null,

  full_name text,
  phone text,
  preferred_project text,
  preferred_location text,

  campaign_name text,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_term text,
  utm_content text,

  landing_page_url text,
  referrer_url text,

  source text,
  medium text,
  campaign text,

  metadata jsonb not null default '{}'::jsonb,

  processed_lead_id uuid
    references public.leads(id)
    on delete set null,
  processed_at timestamptz,

  received_at timestamptz not null default now()
);

create index if not exists lead_capture_intake_route_received_idx
  on public.lead_capture_intake(route_key, received_at desc);

alter table public.lead_capture_intake
  enable row level security;

revoke all on table public.lead_capture_intake
from anon, authenticated;

grant insert on table public.lead_capture_intake
to service_role;

-- A failed route is rejected atomically, so an unconfigured tenant cannot
-- accidentally receive a lead.
create or replace function public.process_lead_capture_intake()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_route public.lead_capture_routes%rowtype;
  target_lead_id uuid;
begin
  select *
  into target_route
  from public.lead_capture_routes
  where route_key = lower(trim(new.route_key))
    and is_active = true
  for share;

  if not found then
    raise exception
      using
        errcode = 'P0001',
        message = 'No active SalesSetu lead capture route matches this key';
  end if;

  insert into public.leads (
    organization_id,
    lead_source_id,
    full_name,
    phone,
    preferred_project,
    preferred_location,
    campaign_name,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    landing_page_url,
    referrer_url,
    external_provider,
    custom_fields,
    metadata
  )
  values (
    target_route.organization_id,
    target_route.lead_source_id,
    nullif(trim(new.full_name), ''),
    nullif(trim(new.phone), ''),
    nullif(trim(new.preferred_project), ''),
    nullif(trim(new.preferred_location), ''),
    coalesce(
      nullif(trim(new.campaign_name), ''),
      nullif(trim(new.campaign), ''),
      nullif(trim(new.utm_campaign), '')
    ),
    nullif(trim(new.utm_source), ''),
    nullif(trim(new.utm_medium), ''),
    nullif(trim(new.utm_campaign), ''),
    nullif(trim(new.utm_term), ''),
    nullif(trim(new.utm_content), ''),
    nullif(trim(new.landing_page_url), ''),
    nullif(trim(new.referrer_url), ''),
    'n8n_sales_lead_attribution',
    jsonb_strip_nulls(
      jsonb_build_object(
        'source', nullif(trim(new.source), ''),
        'medium', nullif(trim(new.medium), ''),
        'campaign', nullif(trim(new.campaign), '')
      )
    ),
    coalesce(new.metadata, '{}'::jsonb)
      || jsonb_build_object(
        'capture_route_key', target_route.route_key,
        'capture_intake_id', new.id,
        'captured_via', 'n8n'
      )
  )
  returning id into target_lead_id;

  new.route_key := target_route.route_key;
  new.processed_lead_id := target_lead_id;
  new.processed_at := now();

  return new;
end;
$$;

create trigger lead_capture_intake_process
before insert on public.lead_capture_intake
for each row
execute function public.process_lead_capture_intake();

commit;
