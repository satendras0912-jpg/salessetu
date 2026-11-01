-- ============================================================
-- 20261101101500_kavyarpit_employee_ids.sql
--
-- Kavyarpit Sales Agent employee IDs:
--   KRV-001, KRV-002, ...
-- Codes are tenant-scoped, sequential and never reused.
-- ============================================================

begin;

update public.organizations
set settings = jsonb_set(
  coalesce(settings, '{}'::jsonb),
  '{employee_id_prefix}',
  '"KRV"'::jsonb,
  true
)
where name = 'Kavyarpit Realty Pvt Ltd'
  and nullif(trim(settings ->> 'employee_id_prefix'), '') is null;

with ranked_sales_agents as (
  select
    agent_profile.id,
    row_number() over (
      partition by agent_profile.organization_id
      order by agent_profile.created_at, agent_profile.id
    ) as employee_number
  from public.assignment_agent_profiles as agent_profile
  join public.organizations as organization
    on organization.id = agent_profile.organization_id
  join public.organization_members as organization_member
    on organization_member.organization_id = agent_profile.organization_id
    and organization_member.user_id = agent_profile.user_id
  join public.member_roles as member_role
    on member_role.organization_member_id = organization_member.id
  join public.roles as role_record
    on role_record.id = member_role.role_id
    and role_record.code = 'sales_agent'
  where organization.name = 'Kavyarpit Realty Pvt Ltd'
)
update public.assignment_agent_profiles as agent_profile
set agent_code = concat(
  'KRV-',
  lpad(ranked_sales_agents.employee_number::text, 3, '0')
)
from ranked_sales_agents
where agent_profile.id = ranked_sales_agents.id;

create or replace function public.next_organization_employee_id(
  p_organization_id uuid
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  employee_prefix text;
  next_number integer;
begin
  select coalesce(
    nullif(
      upper(
        regexp_replace(
          coalesce(organization.settings ->> 'employee_id_prefix', ''),
          '[^A-Za-z0-9]',
          '',
          'g'
        )
      ),
      ''
    ),
    'EMP'
  )
  into employee_prefix
  from public.organizations as organization
  where organization.id = p_organization_id;

  if employee_prefix is null then
    raise exception 'Workspace was not found.'
      using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      concat('employee-id:', p_organization_id::text),
      0
    )
  );

  select coalesce(
    max(
      substring(agent_profile.agent_code from '([0-9]+)$')::integer
    ),
    0
  ) + 1
  into next_number
  from public.assignment_agent_profiles as agent_profile
  where agent_profile.organization_id = p_organization_id
    and agent_profile.agent_code ~ (
      '^' || employee_prefix || '-[0-9]+$'
    );

  return concat(
    employee_prefix,
    '-',
    lpad(next_number::text, 3, '0')
  );
end;
$$;

revoke all on function public.next_organization_employee_id(uuid)
from public;

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
  generated_employee_id text;
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

  generated_employee_id :=
    public.next_organization_employee_id(p_organization_id);

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
    generated_employee_id,
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
    agent_code = public.assignment_agent_profiles.agent_code,
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

commit;
