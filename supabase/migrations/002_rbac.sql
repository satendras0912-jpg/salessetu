-- =========================================================
-- SalesSetu Enterprise
-- Migration: 002_rbac
-- Enterprise RBAC Foundation
-- =========================================================

-- =========================================================
-- ROLES
-- =========================================================

create table public.roles (

    id uuid primary key default gen_random_uuid(),

    code text not null unique,
    name text not null,
    description text,

    is_system boolean not null default true,

    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()

);

create trigger roles_updated_at
before update on public.roles
for each row
execute function public.set_updated_at();

create index roles_code_idx
on public.roles(code);

-- =========================================================
-- PERMISSIONS
-- =========================================================

create table public.permissions (

    id uuid primary key default gen_random_uuid(),

    module text not null,

    action text not null,

    code text not null unique,

    description text,

    created_at timestamptz not null default now()

);

create index permissions_module_idx
on public.permissions(module);

create index permissions_code_idx
on public.permissions(code);

-- =========================================================
-- ROLE PERMISSIONS
-- =========================================================

create table public.role_permissions (

    id uuid primary key default gen_random_uuid(),

    role_id uuid not null
        references public.roles(id)
        on delete cascade,

    permission_id uuid not null
        references public.permissions(id)
        on delete cascade,

    created_at timestamptz default now(),

    unique(role_id, permission_id)

);

create index role_permissions_role_idx
on public.role_permissions(role_id);

create index role_permissions_permission_idx
on public.role_permissions(permission_id);

-- =========================================================
-- MEMBER ROLES
-- =========================================================

create table public.member_roles (

    id uuid primary key default gen_random_uuid(),

    organization_member_id uuid not null
        references public.organization_members(id)
        on delete cascade,

    role_id uuid not null
        references public.roles(id)
        on delete cascade,

    assigned_by uuid
        references auth.users(id),

    assigned_at timestamptz default now(),

    unique(organization_member_id, role_id)

);

create index member_roles_member_idx
on public.member_roles(organization_member_id);

create index member_roles_role_idx
on public.member_roles(role_id);

-- =========================================================
-- ENABLE RLS
-- =========================================================

alter table public.roles
enable row level security;

alter table public.permissions
enable row level security;

alter table public.role_permissions
enable row level security;

alter table public.member_roles
enable row level security;

-- =========================================================
-- DEFAULT SYSTEM ROLES
-- =========================================================

insert into public.roles (
  code,
  name,
  description,
  is_system
)
values
  (
    'platform_admin',
    'Platform Administrator',
    'SalesSetu platform-level administrator',
    true
  ),
  (
    'organization_admin',
    'Organization Administrator',
    'Full administrative access within an organization',
    true
  ),
  (
    'sales_manager',
    'Sales Manager',
    'Manages sales team, leads, assignments and pipeline',
    true
  ),
  (
    'sales_agent',
    'Sales Agent',
    'Works on assigned leads, follow-ups, visits and deals',
    true
  ),
  (
    'marketing_manager',
    'Marketing Manager',
    'Manages campaigns, forms, lead sources and marketing analytics',
    true
  ),
  (
    'customer_success',
    'Customer Success',
    'Manages customers after booking and handles service requests',
    true
  ),
  (
    'finance_manager',
    'Finance Manager',
    'Manages billing, invoices, payments and commissions',
    true
  ),
  (
    'viewer',
    'Viewer',
    'Read-only access to permitted organization information',
    true
  )
on conflict (code) do nothing;

-- =========================================================
-- DEFAULT PERMISSIONS
-- Permission format: module.action
-- =========================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
values

  -- Organization
  (
    'organization',
    'view',
    'organization.view',
    'View organization information'
  ),
  (
    'organization',
    'update',
    'organization.update',
    'Update organization information'
  ),
  (
    'organization',
    'manage_members',
    'organization.manage_members',
    'Invite, activate, suspend and remove organization members'
  ),
  (
    'organization',
    'manage_roles',
    'organization.manage_roles',
    'Assign and remove roles from organization members'
  ),

  -- Leads
  (
    'leads',
    'view',
    'leads.view',
    'View leads'
  ),
  (
    'leads',
    'create',
    'leads.create',
    'Create leads'
  ),
  (
    'leads',
    'update',
    'leads.update',
    'Update leads'
  ),
  (
    'leads',
    'delete',
    'leads.delete',
    'Delete leads'
  ),
  (
    'leads',
    'assign',
    'leads.assign',
    'Assign leads to sales agents'
  ),
  (
    'leads',
    'export',
    'leads.export',
    'Export lead data'
  ),

  -- Marketing
  (
    'marketing',
    'view',
    'marketing.view',
    'View campaigns and marketing performance'
  ),
  (
    'marketing',
    'manage',
    'marketing.manage',
    'Create and manage campaigns, forms and lead sources'
  ),

  -- Sales
  (
    'sales',
    'view',
    'sales.view',
    'View sales activities and pipeline'
  ),
  (
    'sales',
    'manage',
    'sales.manage',
    'Manage follow-ups, site visits, deals and bookings'
  ),

  -- Customer Success
  (
    'customer_success',
    'view',
    'customer_success.view',
    'View customer-success records'
  ),
  (
    'customer_success',
    'manage',
    'customer_success.manage',
    'Manage onboarding and customer service processes'
  ),

  -- Finance
  (
    'finance',
    'view',
    'finance.view',
    'View financial records'
  ),
  (
    'finance',
    'manage',
    'finance.manage',
    'Manage billing, payments, invoices and commissions'
  ),

  -- Reports
  (
    'reports',
    'view',
    'reports.view',
    'View organization reports and dashboards'
  ),
  (
    'reports',
    'export',
    'reports.export',
    'Export reports'
  ),

  -- Integrations
  (
    'integrations',
    'view',
    'integrations.view',
    'View configured integrations'
  ),
  (
    'integrations',
    'manage',
    'integrations.manage',
    'Configure and manage organization integrations'
  ),

  -- Workflow
  (
    'workflow',
    'view',
    'workflow.view',
    'View workflow definitions and executions'
  ),
  (
    'workflow',
    'manage',
    'workflow.manage',
    'Create, publish and manage workflows'
  ),

  -- Audit
  (
    'audit',
    'view',
    'audit.view',
    'View organization audit records'
  )

on conflict (code) do nothing;

-- =========================================================
-- ROLE → PERMISSION MAPPING
-- =========================================================

-- Organization Admin receives every organization permission.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
cross join public.permissions p
where r.code = 'organization_admin'
on conflict (role_id, permission_id) do nothing;

-- Platform Administrator receives every permission.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
cross join public.permissions p
where r.code = 'platform_admin'
on conflict (role_id, permission_id) do nothing;

-- Sales Manager permissions.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'organization.view',
    'organization.manage_members',
    'leads.view',
    'leads.create',
    'leads.update',
    'leads.assign',
    'leads.export',
    'sales.view',
    'sales.manage',
    'reports.view',
    'reports.export',
    'workflow.view'
  )
where r.code = 'sales_manager'
on conflict (role_id, permission_id) do nothing;

-- Sales Agent permissions.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'organization.view',
    'leads.view',
    'leads.create',
    'leads.update',
    'sales.view',
    'sales.manage'
  )
where r.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;

-- Marketing Manager permissions.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'organization.view',
    'leads.view',
    'leads.create',
    'leads.export',
    'marketing.view',
    'marketing.manage',
    'reports.view',
    'reports.export',
    'integrations.view'
  )
where r.code = 'marketing_manager'
on conflict (role_id, permission_id) do nothing;

-- Customer Success permissions.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'organization.view',
    'leads.view',
    'sales.view',
    'customer_success.view',
    'customer_success.manage',
    'reports.view'
  )
where r.code = 'customer_success'
on conflict (role_id, permission_id) do nothing;

-- Finance Manager permissions.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'organization.view',
    'sales.view',
    'finance.view',
    'finance.manage',
    'reports.view',
    'reports.export'
  )
where r.code = 'finance_manager'
on conflict (role_id, permission_id) do nothing;

-- Viewer permissions.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'organization.view',
    'leads.view',
    'marketing.view',
    'sales.view',
    'customer_success.view',
    'finance.view',
    'reports.view',
    'integrations.view',
    'workflow.view'
  )
where r.code = 'viewer'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- RBAC HELPER FUNCTIONS
-- =========================================================

-- Checks whether the current user is the active owner
-- of the requested organization.

create or replace function public.is_organization_owner(
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
    from public.organization_members om
    where om.organization_id = requested_organization_id
      and om.user_id = (select auth.uid())
      and om.membership_status = 'active'
      and om.is_owner = true
  );
$$;

revoke all
on function public.is_organization_owner(uuid)
from public;

grant execute
on function public.is_organization_owner(uuid)
to authenticated;

-- Returns the organization associated with a membership.

create or replace function public.get_member_organization_id(
  requested_organization_member_id uuid
)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select om.organization_id
  from public.organization_members om
  where om.id = requested_organization_member_id
  limit 1;
$$;

revoke all
on function public.get_member_organization_id(uuid)
from public;

grant execute
on function public.get_member_organization_id(uuid)
to authenticated;

-- Checks whether the current authenticated user has
-- a specific permission inside an organization.
--
-- Organization owner receives implicit full access.

create or replace function public.has_organization_permission(
  requested_organization_id uuid,
  requested_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    public.is_organization_owner(requested_organization_id)
    or exists (
      select 1
      from public.organization_members om
      join public.member_roles mr
        on mr.organization_member_id = om.id
      join public.role_permissions rp
        on rp.role_id = mr.role_id
      join public.permissions p
        on p.id = rp.permission_id
      where om.organization_id = requested_organization_id
        and om.user_id = (select auth.uid())
        and om.membership_status = 'active'
        and p.code = requested_permission_code
    );
$$;

revoke all
on function public.has_organization_permission(uuid, text)
from public;

grant execute
on function public.has_organization_permission(uuid, text)
to authenticated;

-- =========================================================
-- RLS POLICIES: ROLE CATALOGUE
-- =========================================================

create policy "Authenticated users can view roles"
on public.roles
for select
to authenticated
using (true);

create policy "Authenticated users can view permissions"
on public.permissions
for select
to authenticated
using (true);

create policy "Authenticated users can view role permissions"
on public.role_permissions
for select
to authenticated
using (true);

-- =========================================================
-- RLS POLICIES: MEMBER ROLE ASSIGNMENTS
-- =========================================================

create policy "Organization members can view member roles"
on public.member_roles
for select
to authenticated
using (
  public.is_organization_member(
    public.get_member_organization_id(
      organization_member_id
    )
  )
);

create policy "Authorized users can assign member roles"
on public.member_roles
for insert
to authenticated
with check (
  public.has_organization_permission(
    public.get_member_organization_id(
      organization_member_id
    ),
    'organization.manage_roles'
  )
);

create policy "Authorized users can remove member roles"
on public.member_roles
for delete
to authenticated
using (
  public.has_organization_permission(
    public.get_member_organization_id(
      organization_member_id
    ),
    'organization.manage_roles'
  )
);

-- =========================================================
-- ORGANIZATION ADMINISTRATION POLICIES
-- =========================================================

create policy "Authorized users can update organization"
on public.organizations
for update
to authenticated
using (
  public.has_organization_permission(
    id,
    'organization.update'
  )
)
with check (
  public.has_organization_permission(
    id,
    'organization.update'
  )
);

create policy "Authorized users can view organization members"
on public.organization_members
for select
to authenticated
using (
  user_id = (select auth.uid())
  or public.has_organization_permission(
    organization_id,
    'organization.manage_members'
  )
);

create policy "Authorized users can update organization members"
on public.organization_members
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'organization.manage_members'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'organization.manage_members'
  )
);