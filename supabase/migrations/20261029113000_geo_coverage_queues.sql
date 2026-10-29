-- Area coverage is intentionally prepared in draft mode. It does not assign
-- leads, change task ownership, or enable any outreach automation.
create table if not exists public.geo_coverage_queues (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  geo_tag text not null check (geo_tag in (
    'noida',
    'greater_noida',
    'greater_noida_west',
    'siddharth_vihar',
    'wave_city',
    'raj_nagar_extension',
    'ghaziabad'
  )),
  assignment_team_id uuid references public.assignment_teams(id) on delete set null,
  status text not null default 'draft' check (status in ('draft', 'active', 'paused')),
  auto_assignment_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, geo_tag),
  check (not auto_assignment_enabled or (status = 'active' and assignment_team_id is not null))
);

create index if not exists geo_coverage_queues_organization_status_idx
  on public.geo_coverage_queues (organization_id, status, geo_tag);

create or replace function public.set_geo_coverage_queues_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists geo_coverage_queues_set_updated_at on public.geo_coverage_queues;
create trigger geo_coverage_queues_set_updated_at
before update on public.geo_coverage_queues
for each row execute function public.set_geo_coverage_queues_updated_at();

insert into public.geo_coverage_queues (
  organization_id,
  geo_tag,
  status,
  auto_assignment_enabled
)
select
  organization.id,
  geo.geo_tag,
  'draft',
  false
from public.organizations as organization
cross join (
  values
    ('noida'),
    ('greater_noida'),
    ('greater_noida_west'),
    ('siddharth_vihar'),
    ('wave_city'),
    ('raj_nagar_extension'),
    ('ghaziabad')
) as geo(geo_tag)
on conflict (organization_id, geo_tag) do nothing;

alter table public.geo_coverage_queues enable row level security;

drop policy if exists geo_coverage_queues_select_policy on public.geo_coverage_queues;
create policy geo_coverage_queues_select_policy
on public.geo_coverage_queues
for select to authenticated
using (
  public.has_organization_permission(organization_id, 'followups.view')
);

drop policy if exists geo_coverage_queues_write_policy on public.geo_coverage_queues;
create policy geo_coverage_queues_write_policy
on public.geo_coverage_queues
for all to authenticated
using (
  public.has_organization_permission(organization_id, 'assignment.manage_rules')
)
with check (
  public.has_organization_permission(organization_id, 'assignment.manage_rules')
);

drop policy if exists geo_coverage_queues_service_policy on public.geo_coverage_queues;
create policy geo_coverage_queues_service_policy
on public.geo_coverage_queues
for all to service_role
using (true)
with check (true);

grant select, insert, update, delete on public.geo_coverage_queues to authenticated;
