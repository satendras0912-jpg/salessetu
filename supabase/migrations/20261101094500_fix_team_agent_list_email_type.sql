-- Fix return-type compatibility for auth.users.email in the
-- tenant-scoped Sales Agent listing RPC. Existing deployments
-- received the original 20261101093000 migration before this fix.

begin;

create or replace function public.list_organization_sales_agents(
  p_organization_id uuid
)
returns table (
  membership_id uuid,
  user_id uuid,
  email text,
  display_name text,
  agent_code text,
  membership_status text,
  agent_status text,
  availability_status text,
  auto_assignment_enabled boolean,
  accept_new_leads boolean,
  invited_at timestamptz,
  joined_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null
    or not public.has_organization_permission(
      p_organization_id,
      'organization.manage_members'
    ) then
    raise exception 'You are not allowed to view this organization team.'
      using errcode = '42501';
  end if;

  return query
  select
    organization_member.id,
    organization_member.user_id,
    authenticated_user.email::text,
    coalesce(
      agent_profile.display_name,
      profile.display_name,
      authenticated_user.email
    ),
    agent_profile.agent_code,
    organization_member.membership_status,
    agent_profile.status,
    agent_profile.availability_status,
    coalesce(agent_profile.auto_assignment_enabled, false),
    coalesce(agent_profile.accept_new_leads, false),
    organization_member.invited_at,
    organization_member.joined_at
  from public.organization_members as organization_member
  join public.member_roles as member_role
    on member_role.organization_member_id = organization_member.id
  join public.roles as role_record
    on role_record.id = member_role.role_id
    and role_record.code = 'sales_agent'
  join auth.users as authenticated_user
    on authenticated_user.id = organization_member.user_id
  left join public.assignment_agent_profiles as agent_profile
    on agent_profile.organization_id = organization_member.organization_id
    and agent_profile.user_id = organization_member.user_id
  left join public.profiles as profile
    on profile.id = organization_member.user_id
  where organization_member.organization_id = p_organization_id
    and not exists (
      select 1
      from public.member_roles as other_member_role
      join public.roles as other_role
        on other_role.id = other_member_role.role_id
      where other_member_role.organization_member_id =
            organization_member.id
        and other_role.code <> 'sales_agent'
    )
  order by
    case organization_member.membership_status
      when 'active' then 0
      when 'suspended' then 1
      else 2
    end,
    coalesce(
      agent_profile.display_name,
      profile.display_name,
      authenticated_user.email
    );
end;
$$;

revoke all on function public.list_organization_sales_agents(uuid)
from public;
grant execute on function public.list_organization_sales_agents(uuid)
to authenticated;

commit;
