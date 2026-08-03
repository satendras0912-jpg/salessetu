-- ============================================================
-- 041_Assignment_Default_Team_Bootstrap.sql
--
-- Purpose:
--   Bootstrap the first operational assignment configuration
--   for the SalesSetu Platform organization.
--
-- Creates idempotently:
--   1. Platform administrator agent profile
--   2. Default sales assignment team
--   3. Administrator team-leader membership
-- ============================================================

do $migration$

declare
  target_organization_id constant uuid :=
    '955b8449-5c16-4eeb-a778-e2cd95f44ca7'::uuid;

  target_user_id constant uuid :=
    '5eec53aa-d4c3-4baf-b31e-dd4c072dde0b'::uuid;

  target_user_email constant text :=
    'digitalavalokan@gmail.com';

  target_agent_code constant text :=
    'PLATFORM-ADMIN-001';

  target_team_code constant text :=
    'DEFAULT-SALES';

  resolved_agent_profile_id uuid;
  resolved_team_id uuid;
  resolved_team_membership_id uuid;

begin
  -- ==========================================================
  -- 1. Verify authenticated user
  -- ==========================================================

  if not exists (
    select 1
    from auth.users as authenticated_user
    where authenticated_user.id = target_user_id
      and lower(authenticated_user.email) =
          lower(target_user_email)
  ) then
    raise exception
      'Assignment bootstrap stopped: authenticated user was not found or email did not match.';
  end if;

  -- ==========================================================
  -- 2. Verify active organization-owner membership
  -- ==========================================================

  if not exists (
    select 1
    from public.organization_members as organization_member
    where organization_member.organization_id =
          target_organization_id
      and organization_member.user_id =
          target_user_id
      and organization_member.membership_status =
          'active'
      and organization_member.is_owner is true
  ) then
    raise exception
      'Assignment bootstrap stopped: user is not an active organization owner.';
  end if;

  -- ==========================================================
  -- 3. Protect deterministic agent code
  -- ==========================================================

  if exists (
    select 1
    from public.assignment_agent_profiles as agent_profile
    where agent_profile.organization_id =
          target_organization_id
      and agent_profile.agent_code =
          target_agent_code
      and agent_profile.user_id <>
          target_user_id
  ) then
    raise exception
      'Assignment bootstrap stopped: agent code % is already assigned to another user.',
      target_agent_code;
  end if;

  -- ==========================================================
  -- 4. Create or normalize administrator agent profile
  -- ==========================================================

  insert into public.assignment_agent_profiles (
    organization_id,
    user_id,
    agent_code,
    display_name,
    status,
    availability_status,
    timezone,
    auto_assignment_enabled,
    accept_new_leads,
    created_by,
    updated_by,
    metadata
  )
  values (
    target_organization_id,
    target_user_id,
    target_agent_code,
    'SalesSetu Platform Administrator',
    'active',
    'available',
    'Asia/Kolkata',
    true,
    true,
    target_user_id,
    target_user_id,
    jsonb_build_object(
      'bootstrap_migration',
      '041_Assignment_Default_Team_Bootstrap',
      'bootstrap_type',
      'platform_administrator'
    )
  )
  on conflict (organization_id, user_id)
  do update
  set
    agent_code = coalesce(
      assignment_agent_profiles.agent_code,
      excluded.agent_code
    ),
    display_name = coalesce(
      assignment_agent_profiles.display_name,
      excluded.display_name
    ),
    status = 'active',
    availability_status = 'available',
    timezone = excluded.timezone,
    auto_assignment_enabled = true,
    accept_new_leads = true,
    updated_by = excluded.updated_by,
    updated_at = now();

  select agent_profile.id
  into resolved_agent_profile_id
  from public.assignment_agent_profiles as agent_profile
  where agent_profile.organization_id =
        target_organization_id
    and agent_profile.user_id =
        target_user_id;

  if resolved_agent_profile_id is null then
    raise exception
      'Assignment bootstrap stopped: administrator agent profile could not be resolved.';
  end if;

  -- ==========================================================
  -- 5. Create or normalize default sales team
  -- ==========================================================

  insert into public.assignment_teams (
    organization_id,
    team_code,
    team_name,
    description,
    team_type,
    status,
    default_assignment_strategy,
    timezone,
    created_by,
    updated_by,
    metadata
  )
  values (
    target_organization_id,
    target_team_code,
    'Default Sales Team',
    'Default operational team for SalesSetu lead assignment.',
    'sales',
    'active',
    'round_robin',
    'Asia/Kolkata',
    target_user_id,
    target_user_id,
    jsonb_build_object(
      'bootstrap_migration',
      '041_Assignment_Default_Team_Bootstrap',
      'bootstrap_type',
      'default_sales_team'
    )
  )
  on conflict (organization_id, team_code)
  do update
  set
    team_name = excluded.team_name,
    description = excluded.description,
    team_type = 'sales',
    status = 'active',
    default_assignment_strategy =
      excluded.default_assignment_strategy,
    timezone = excluded.timezone,
    updated_by = excluded.updated_by,
    updated_at = now();

  select assignment_team.id
  into resolved_team_id
  from public.assignment_teams as assignment_team
  where assignment_team.organization_id =
        target_organization_id
    and assignment_team.team_code =
        target_team_code;

  if resolved_team_id is null then
    raise exception
      'Assignment bootstrap stopped: default sales team could not be resolved.';
  end if;

  -- ==========================================================
  -- 6. Create or normalize team-leader membership
  -- ==========================================================

  insert into public.assignment_team_members (
    organization_id,
    team_id,
    agent_profile_id,
    role,
    status,
    assignment_weight,
    priority_rank,
    created_by,
    metadata
  )
  values (
    target_organization_id,
    resolved_team_id,
    resolved_agent_profile_id,
    'leader',
    'active',
    1,
    1,
    target_user_id,
    jsonb_build_object(
      'bootstrap_migration',
      '041_Assignment_Default_Team_Bootstrap',
      'bootstrap_type',
      'default_team_leader'
    )
  )
  on conflict (team_id, agent_profile_id)
  do update
  set
    organization_id = excluded.organization_id,
    role = 'leader',
    status = 'active',
    assignment_weight = 1,
    priority_rank = 1,
    updated_at = now();

  select team_member.id
  into resolved_team_membership_id
  from public.assignment_team_members as team_member
  where team_member.organization_id =
        target_organization_id
    and team_member.team_id =
        resolved_team_id
    and team_member.agent_profile_id =
        resolved_agent_profile_id;

  if resolved_team_membership_id is null then
    raise exception
      'Assignment bootstrap stopped: team-leader membership could not be resolved.';
  end if;

  -- ==========================================================
  -- 7. Completion notice
  -- ==========================================================

  raise notice
    'Assignment bootstrap complete. Agent: %, Team: %, Membership: %',
    resolved_agent_profile_id,
    resolved_team_id,
    resolved_team_membership_id;

end;

$migration$;