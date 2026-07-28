-- =========================================================
-- SalesSetu Enterprise
-- Migration: 001_initial_schema
-- Purpose: Multi-tenant organization and user foundation
-- =========================================================

-- ---------------------------------------------------------
-- 1. Updated-at trigger function
-- ---------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------
-- 2. Organizations
-- ---------------------------------------------------------

create table public.organizations (
  id uuid primary key default gen_random_uuid(),

  name text not null,
  slug text not null unique,

  organization_type text not null
    check (
      organization_type in (
        'platform',
        'brokerage',
        'builder',
        'channel_partner',
        'agency',
        'other'
      )
    ),

  status text not null default 'active'
    check (
      status in (
        'active',
        'inactive',
        'suspended',
        'archived'
      )
    ),

  email text,
  phone text,
  website text,
  logo_url text,

  settings jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,

  created_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index organizations_status_idx
  on public.organizations(status);

create index organizations_type_idx
  on public.organizations(organization_type);

create trigger organizations_set_updated_at
before update on public.organizations
for each row
execute function public.set_updated_at();

-- ---------------------------------------------------------
-- 3. Profiles
-- One profile per Supabase Auth user
-- ---------------------------------------------------------

create table public.profiles (
  id uuid primary key
    references auth.users(id)
    on delete cascade,

  first_name text,
  last_name text,
  display_name text,

  phone text,
  avatar_url text,

  status text not null default 'active'
    check (
      status in (
        'active',
        'inactive',
        'suspended'
      )
    ),

  timezone text not null default 'Asia/Kolkata',
  locale text not null default 'en-IN',

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index profiles_status_idx
  on public.profiles(status);

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

-- ---------------------------------------------------------
-- 4. Organization Members
-- Links users with organizations
-- ---------------------------------------------------------

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  membership_status text not null default 'active'
    check (
      membership_status in (
        'invited',
        'active',
        'inactive',
        'suspended',
        'removed'
      )
    ),

  is_owner boolean not null default false,
  joined_at timestamptz,
  invited_at timestamptz,
  invited_by uuid references auth.users(id) on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint organization_members_unique_membership
    unique (organization_id, user_id)
);

create index organization_members_organization_idx
  on public.organization_members(organization_id);

create index organization_members_user_idx
  on public.organization_members(user_id);

create index organization_members_status_idx
  on public.organization_members(membership_status);

create unique index organization_single_owner_idx
  on public.organization_members(organization_id)
  where is_owner = true
    and membership_status = 'active';

create trigger organization_members_set_updated_at
before update on public.organization_members
for each row
execute function public.set_updated_at();

-- ---------------------------------------------------------
-- 5. Helper function
-- Checks whether current authenticated user belongs
-- to a given organization.
-- ---------------------------------------------------------

create or replace function public.is_organization_member(
  requested_organization_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members
    where organization_id = requested_organization_id
      and user_id = (select auth.uid())
      and membership_status = 'active'
  );
$$;

revoke all on function public.is_organization_member(uuid) from public;
grant execute on function public.is_organization_member(uuid)
  to authenticated;

-- ---------------------------------------------------------
-- 6. Enable Row Level Security
-- Policies will be added after RBAC tables are created.
-- ---------------------------------------------------------

alter table public.organizations
  enable row level security;

alter table public.profiles
  enable row level security;

alter table public.organization_members
  enable row level security;

-- ---------------------------------------------------------
-- 7. Basic profile policies
-- ---------------------------------------------------------

create policy "Users can view own profile"
on public.profiles
for select
to authenticated
using (
  id = (select auth.uid())
);

create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using (
  id = (select auth.uid())
)
with check (
  id = (select auth.uid())
);

-- ---------------------------------------------------------
-- 8. Organization read policies
-- ---------------------------------------------------------

create policy "Members can view their organizations"
on public.organizations
for select
to authenticated
using (
  public.is_organization_member(id)
);

create policy "Users can view own memberships"
on public.organization_members
for select
to authenticated
using (
  user_id = (select auth.uid())
);