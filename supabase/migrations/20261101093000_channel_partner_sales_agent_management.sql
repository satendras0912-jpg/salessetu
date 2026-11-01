-- ============================================================
-- 20261101093000_channel_partner_sales_agent_management.sql
--
-- Tenant-scoped self-service sales-agent management.
-- Only users with organization.manage_members in the active
-- organization may use these RPCs. They can only manage the
-- sales_agent role; ownership and administrative roles are blocked.
-- ============================================================

begin;

create or replace function public.find_organization_user_by_email(
  p_organization_id uuid,
  p_email text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_user_id uuid;
begin
  if (select auth.uid()) is null
    or not public.has_organization_permission(
      p_organization_id,
      'organization.manage_members'
    ) then
    raise exception 'You are not allowed to manage this organization team.'
      using errcode = '42501';
  end if;

  select authenticated_user.id
  into resolved_user_id
  from auth.users as authenticated_user
  where lower(authenticated_user.email) = lower(trim(p_email))
  limit 1;

  return resolved_user_id;
end;
$$;

revoke all on function public.find_organization_user_by_email(uuid, text)
from public;
grant execute on function public.find_organization_user_by_email(uuid, text)
to authenticated;

create or replace function public.upsert_organization_sales_agent(
  p_organization_id uuid,
  p_user_id uuid,
  p_display_name text
)
returns table (
  membership_id uuid,
  agent_profile_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  managing_user_id uuid := (select auth.uid());
  sales_agent_role_id uuid;
  existing_membership public.organization_members;
  resolved_membership_id uuid;
  resolved_agent_profile_id uuid;
  normalized_display_name text := nullif(trim(p_display_name), '');
begin
  if managing_user_id is null
    or not public.has_organization_permission(
      p_organization_id,
      'organization.manage_members'
    ) then
    raise exception 'You are not allowed to manage this organization team.'
      using errcode = '42501';
  end if;

  if normalized_display_name is null then
    raise exception 'A sales agent name is required.'
      using errcode = '22023';
  end if;

  select role_record.id
  into sales_agent_role_id
  from public.roles as role_record
  where role_record.code = 'sales_agent';

  if sales_agent_role_id is null then
    raise exception 'The Sales Agent role is not configured.'
      using errcode = 'P0001';
  end if;

  select organization_member.*
  into existing_membership
  from public.organization_members as organization_member
  where organization_member.organization_id = p_organization_id
    and organization_member.user_id = p_user_id
  limit 1;

  if existing_membership.id is not null then
    if existing_membership.is_owner then
      raise exception 'Workspace owners cannot be managed as sales agents.'
        using errcode = '42501';
    end if;

    if exists (
      select 1
      from public.member_roles as member_role
      join public.roles as role_record
        on role_record.id = member_role.role_id
      where member_role.organization_member_id = existing_membership.id
        and role_record.code <> 'sales_agent'
    ) then
      raise exception 'This member already has a non-agent role in this workspace.'
        using errcode = '42501';
    end if;

    update public.organization_members
    set
      membership_status = 'active',
      joined_at = coalesce(joined_at, now()),
      invited_at = coalesce(invited_at, now()),
      invited_by = coalesce(invited_by, managing_user_id),
      updated_at = now()
    where id = existing_membership.id
    returning id into resolved_membership_id;
  else
    insert into public.organization_members (
      organization_id,
      user_id,
      membership_status,
      is_owner,
      joined_at,
      invited_at,
      invited_by,
      metadata
    )
    values (
      p_organization_id,
      p_user_id,
      'active',
      false,
      now(),
      now(),
      managing_user_id,
      jsonb_build_object(
        'provisioned_by',
        'channel_partner_sales_agent_management'
      )
    )
    returning id into resolved_membership_id;
  end if;

  insert into public.member_roles (
    organization_member_id,
    role_id,
    assigned_by
  )
  values (
    resolved_membership_id,
    sales_agent_role_id,
    managing_user_id
  )
  on conflict (organization_member_id, role_id) do nothing;

  insert into public.assignment_agent_profiles (
    organization_id,
    user_id,
    agent_code,
    display_name,
    status,
    availability_status,
    auto_assignment_enabled,
    accept_new_leads,
    created_by,
    updated_by,
    metadata
  )
  values (
    p_organization_id,
    p_user_id,
    concat(
      'AGENT-',
      upper(substr(replace(p_user_id::text, '-', ''), 1, 8))
    ),
    normalized_display_name,
    'active',
    'available',
    false,
    true,
    managing_user_id,
    managing_user_id,
    jsonb_build_object(
      'provisioned_by',
      'channel_partner_sales_agent_management',
      'routing_default',
      'manual'
    )
  )
  on conflict (organization_id, user_id)
  do update
  set
    display_name = excluded.display_name,
    status = 'active',
    availability_status = 'available',
    auto_assignment_enabled = false,
    accept_new_leads = true,
    updated_by = excluded.updated_by,
    updated_at = now()
  returning id into resolved_agent_profile_id;

  membership_id := resolved_membership_id;
  agent_profile_id := resolved_agent_profile_id;
  return next;
end;
$$;

revoke all on function public.upsert_organization_sales_agent(uuid, uuid, text)
from public;
grant execute on function public.upsert_organization_sales_agent(uuid, uuid, text)
to authenticated;

create or replace function public.set_organization_sales_agent_status(
  p_organization_id uuid,
  p_membership_id uuid,
  p_next_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  managing_user_id uuid := (select auth.uid());
  target_member public.organization_members;
  normalized_status text := lower(trim(p_next_status));
  agent_status text;
  availability text;
  accept_leads boolean;
begin
  if managing_user_id is null
    or not public.has_organization_permission(
      p_organization_id,
      'organization.manage_members'
    ) then
    raise exception 'You are not allowed to manage this organization team.'
      using errcode = '42501';
  end if;

  if normalized_status not in ('active', 'suspended', 'removed') then
    raise exception 'Unsupported sales-agent status.'
      using errcode = '22023';
  end if;

  select organization_member.*
  into target_member
  from public.organization_members as organization_member
  where organization_member.id = p_membership_id
    and organization_member.organization_id = p_organization_id
  limit 1;

  if target_member.id is null then
    raise exception 'Sales agent membership was not found.'
      using errcode = 'P0002';
  end if;

  if target_member.is_owner
    or target_member.user_id = managing_user_id then
    raise exception 'You cannot change this membership.'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.member_roles as member_role
    join public.roles as role_record
      on role_record.id = member_role.role_id
    where member_role.organization_member_id = target_member.id
      and role_record.code = 'sales_agent'
  )
  or exists (
    select 1
    from public.member_roles as member_role
    join public.roles as role_record
      on role_record.id = member_role.role_id
    where member_role.organization_member_id = target_member.id
      and role_record.code <> 'sales_agent'
  ) then
    raise exception 'Only standard Sales Agent memberships can be changed here.'
      using errcode = '42501';
  end if;

  agent_status := case
    when normalized_status = 'active' then 'active'
    when normalized_status = 'suspended' then 'suspended'
    else 'inactive'
  end;

  availability := case
    when normalized_status = 'active' then 'available'
    else 'offline'
  end;

  accept_leads := normalized_status = 'active';

  update public.organization_members
  set
    membership_status = normalized_status,
    joined_at = case
      when normalized_status = 'active' then coalesce(joined_at, now())
      else joined_at
    end,
    updated_at = now()
  where id = target_member.id;

  update public.assignment_agent_profiles
  set
    status = agent_status,
    availability_status = availability,
    auto_assignment_enabled = false,
    accept_new_leads = accept_leads,
    updated_by = managing_user_id,
    updated_at = now()
  where organization_id = p_organization_id
    and user_id = target_member.user_id;
end;
$$;

revoke all on function public.set_organization_sales_agent_status(uuid, uuid, text)
from public;
grant execute on function public.set_organization_sales_agent_status(uuid, uuid, text)
to authenticated;

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
