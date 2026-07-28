-- =========================================================
-- SalesSetu Enterprise
-- Migration: 037_Auth_Identity_Context_Bootstrap
-- Purpose:
--   1. Automatically create public.profile for Auth users
--   2. Bootstrap the current founder account
--   3. Create the SalesSetu platform organization
--   4. Create active organization membership
--   5. Assign platform_admin role
-- =========================================================

begin;

-- =========================================================
-- 1. AUTOMATIC PROFILE CREATION FOR FUTURE AUTH USERS
-- =========================================================

create or replace function public.handle_new_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_display_name text;
begin
  v_display_name := coalesce(
    nullif(
      btrim(new.raw_user_meta_data ->> 'display_name'),
      ''
    ),
    nullif(
      btrim(new.raw_user_meta_data ->> 'full_name'),
      ''
    ),
    nullif(
      btrim(
        concat_ws(
          ' ',
          new.raw_user_meta_data ->> 'first_name',
          new.raw_user_meta_data ->> 'last_name'
        )
      ),
      ''
    ),
    nullif(
      split_part(coalesce(new.email, ''), '@', 1),
      ''
    ),
    'SalesSetu User'
  );

  insert into public.profiles (
    id,
    first_name,
    last_name,
    display_name,
    phone,
    status,
    timezone,
    locale,
    metadata
  )
  values (
    new.id,
    nullif(
      btrim(new.raw_user_meta_data ->> 'first_name'),
      ''
    ),
    nullif(
      btrim(new.raw_user_meta_data ->> 'last_name'),
      ''
    ),
    v_display_name,
    nullif(btrim(coalesce(new.phone, '')), ''),
    'active',
    'Asia/Kolkata',
    'en-IN',
    jsonb_build_object(
      'created_from', 'auth.users',
      'auth_provider',
      coalesce(
        new.raw_app_meta_data ->> 'provider',
        'email'
      )
    )
  )
  on conflict (id) do nothing;

  return new;
end;
$function$;

revoke all
on function public.handle_new_auth_user_profile()
from public;

drop trigger if exists
  on_auth_user_created_create_profile
on auth.users;

create trigger on_auth_user_created_create_profile
after insert on auth.users
for each row
execute function public.handle_new_auth_user_profile();

comment on function public.handle_new_auth_user_profile()
is 'Creates a protected public.profiles record for each new Supabase Auth user.';


-- =========================================================
-- 2. BOOTSTRAP CURRENT FOUNDER ACCOUNT
-- =========================================================

do $bootstrap$
declare
  v_email text := 'digitalavalokan@gmail.com';

  v_user_id uuid;
  v_organization_id uuid;
  v_organization_member_id uuid;
  v_platform_admin_role_id uuid;
begin

  -- -------------------------------------------------------
  -- Locate the existing Supabase Auth user
  -- -------------------------------------------------------

  select auth_user.id
  into v_user_id
  from auth.users as auth_user
  where lower(auth_user.email) = lower(v_email)
  order by auth_user.created_at asc
  limit 1;

  if v_user_id is null then
    raise exception
      'Auth user with email % was not found.',
      v_email;
  end if;


  -- -------------------------------------------------------
  -- Create or update public profile
  -- -------------------------------------------------------

  insert into public.profiles (
    id,
    first_name,
    last_name,
    display_name,
    status,
    timezone,
    locale,
    metadata
  )
  values (
    v_user_id,
    'Satendra',
    'Singh',
    'Satendra Singh',
    'active',
    'Asia/Kolkata',
    'en-IN',
    jsonb_build_object(
      'account_type', 'founder',
      'bootstrap_migration', '037'
    )
  )
  on conflict (id)
  do update set
    first_name = excluded.first_name,
    last_name = excluded.last_name,
    display_name = excluded.display_name,
    status = 'active',
    timezone = excluded.timezone,
    locale = excluded.locale,
    metadata =
      coalesce(public.profiles.metadata, '{}'::jsonb)
      || excluded.metadata,
    updated_at = now();


  -- -------------------------------------------------------
  -- Create the SalesSetu platform organization
  -- -------------------------------------------------------

  insert into public.organizations (
    name,
    slug,
    organization_type,
    status,
    email,
    settings,
    metadata,
    created_by
  )
  values (
    'SalesSetu Platform',
    'salessetu-platform',
    'platform',
    'active',
    v_email,
    jsonb_build_object(
      'timezone', 'Asia/Kolkata',
      'locale', 'en-IN',
      'default_currency', 'INR'
    ),
    jsonb_build_object(
      'bootstrap_migration', '037',
      'platform_owner_email', v_email
    ),
    v_user_id
  )
  on conflict (slug)
  do update set
    name = excluded.name,
    organization_type = excluded.organization_type,
    status = 'active',
    email = coalesce(
      public.organizations.email,
      excluded.email
    ),
    settings =
      coalesce(public.organizations.settings, '{}'::jsonb)
      || excluded.settings,
    metadata =
      coalesce(public.organizations.metadata, '{}'::jsonb)
      || excluded.metadata,
    updated_at = now()
  returning id into v_organization_id;


  -- -------------------------------------------------------
  -- Protect an existing different owner
  -- -------------------------------------------------------

  if exists (
    select 1
    from public.organization_members as existing_owner
    where existing_owner.organization_id = v_organization_id
      and existing_owner.is_owner = true
      and existing_owner.membership_status = 'active'
      and existing_owner.user_id <> v_user_id
  ) then
    raise exception
      'Organization % already has a different active owner.',
      v_organization_id;
  end if;


  -- -------------------------------------------------------
  -- Create active owner membership
  -- -------------------------------------------------------

  insert into public.organization_members (
    organization_id,
    user_id,
    membership_status,
    is_owner,
    joined_at,
    metadata
  )
  values (
    v_organization_id,
    v_user_id,
    'active',
    true,
    now(),
    jsonb_build_object(
      'bootstrap_migration', '037',
      'membership_source', 'founder_bootstrap'
    )
  )
  on conflict (organization_id, user_id)
  do update set
    membership_status = 'active',
    is_owner = true,
    joined_at = coalesce(
      public.organization_members.joined_at,
      excluded.joined_at
    ),
    metadata =
      coalesce(
        public.organization_members.metadata,
        '{}'::jsonb
      )
      || excluded.metadata,
    updated_at = now()
  returning id into v_organization_member_id;


  -- -------------------------------------------------------
  -- Find platform_admin role
  -- -------------------------------------------------------

  select role_record.id
  into v_platform_admin_role_id
  from public.roles as role_record
  where role_record.code = 'platform_admin'
  limit 1;

  if v_platform_admin_role_id is null then
    raise exception
      'Required role platform_admin was not found.';
  end if;


  -- -------------------------------------------------------
  -- Assign platform_admin role
  -- -------------------------------------------------------

  insert into public.member_roles (
    organization_member_id,
    role_id,
    assigned_by,
    assigned_at
  )
  values (
    v_organization_member_id,
    v_platform_admin_role_id,
    v_user_id,
    now()
  )
  on conflict (
    organization_member_id,
    role_id
  )
  do update set
    assigned_by = excluded.assigned_by,
    assigned_at = excluded.assigned_at;


  raise notice
    'Founder bootstrap completed. User: %, Organization: %, Membership: %',
    v_user_id,
    v_organization_id,
    v_organization_member_id;

end;
$bootstrap$;

commit;