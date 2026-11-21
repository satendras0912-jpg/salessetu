-- Manual GEO ownership for tenant pilots. This records an accountable Sales Agent
-- without turning on auto-routing or changing an existing lead/follow-up owner.

begin;

alter table public.geo_coverage_queues
  add column if not exists assignment_agent_profile_id uuid
    references public.assignment_agent_profiles(id) on delete set null;

create index if not exists geo_coverage_queues_organization_agent_idx
  on public.geo_coverage_queues (
    organization_id,
    assignment_agent_profile_id
  );

create or replace function public.configure_geo_coverage_assignment(
  p_organization_id uuid,
  p_geo_tag text,
  p_assignee_user_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  acting_user_id uuid := auth.uid();
  target_agent_profile_id uuid;
begin
  if acting_user_id is null then
    raise exception 'You must be signed in to configure GEO coverage.'
      using errcode = '42501';
  end if;

  if p_organization_id is null or p_geo_tag is null or p_geo_tag not in (
    'noida',
    'greater_noida',
    'greater_noida_west',
    'siddharth_vihar',
    'wave_city',
    'raj_nagar_extension',
    'ghaziabad'
  ) then
    raise exception 'Choose a valid organization and GEO area.'
      using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.organization_members as organization_member
    where organization_member.organization_id = p_organization_id
      and organization_member.user_id = acting_user_id
      and organization_member.membership_status = 'active'
      and organization_member.is_owner is true
  ) then
    raise exception 'Only the active workspace owner can configure GEO coverage.'
      using errcode = '42501';
  end if;

  if p_assignee_user_id is not null then
    select agent_profile.id
    into target_agent_profile_id
    from public.assignment_agent_profiles as agent_profile
    join public.organization_members as organization_member
      on organization_member.organization_id = agent_profile.organization_id
      and organization_member.user_id = agent_profile.user_id
    join public.member_roles as member_role
      on member_role.organization_member_id = organization_member.id
    join public.roles as role_record
      on role_record.id = member_role.role_id
      and role_record.code = 'sales_agent'
    where agent_profile.organization_id = p_organization_id
      and agent_profile.user_id = p_assignee_user_id
      and agent_profile.status = 'active'
      and organization_member.membership_status = 'active'
      and not exists (
        select 1
        from public.member_roles as other_member_role
        join public.roles as other_role
          on other_role.id = other_member_role.role_id
        where other_member_role.organization_member_id = organization_member.id
          and other_role.code <> 'sales_agent'
      )
    limit 1;

    if target_agent_profile_id is null then
      raise exception 'Choose an active Sales Agent in this workspace.'
        using errcode = '22023';
    end if;
  end if;

  insert into public.geo_coverage_queues (
    organization_id,
    geo_tag,
    assignment_team_id,
    assignment_agent_profile_id,
    status,
    auto_assignment_enabled
  )
  values (
    p_organization_id,
    p_geo_tag,
    null,
    target_agent_profile_id,
    case when target_agent_profile_id is null then 'draft' else 'active' end,
    false
  )
  on conflict (organization_id, geo_tag)
  do update set
    assignment_team_id = null,
    assignment_agent_profile_id = excluded.assignment_agent_profile_id,
    status = excluded.status,
    auto_assignment_enabled = false,
    updated_at = now();
end;
$$;

revoke all on function public.configure_geo_coverage_assignment(uuid, text, uuid)
from public;
grant execute on function public.configure_geo_coverage_assignment(uuid, text, uuid)
to authenticated;

commit;
