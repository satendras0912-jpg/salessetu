begin;

-- ============================================================
-- SalesSetu Database-backed Permission Service
-- ============================================================

-- ------------------------------------------------------------
-- 1. Required frontend permission codes
-- ------------------------------------------------------------

insert into public.permissions (
  module,
  action,
  code,
  description
)
select
  v.module,
  v.action,
  v.code,
  v.description
from (
  values
    (
      'dashboard',
      'view',
      'dashboard.view',
      'Access the authenticated SalesSetu dashboard.'
    ),
    (
      'dashboard',
      'context_read',
      'dashboard.context.read',
      'View organization, membership and role context.'
    )
) as v(module, action, code, description)
where not exists (
  select 1
  from public.permissions p
  where p.code = v.code
);

-- ------------------------------------------------------------
-- 2. Grant baseline dashboard permissions to platform_admin
-- ------------------------------------------------------------

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
    'dashboard.view',
    'dashboard.context.read'
  )
where r.code = 'platform_admin'
  and not exists (
    select 1
    from public.role_permissions rp
    where rp.role_id = r.id
      and rp.permission_id = p.id
  );

-- ------------------------------------------------------------
-- 3. Resolve permissions for authenticated user and organization
-- ------------------------------------------------------------

create or replace function public.get_my_organization_permissions(
  p_organization_id uuid
)
returns table (
  permission_id uuid,
  permission_code text,
  permission_module text,
  permission_action text,
  permission_description text,
  granted_via text,
  role_code text
)
language sql
stable
security definer
set search_path = ''
as $function$

  with active_membership as (
    select
      om.id as organization_member_id,
      om.is_owner
    from public.organization_members om
    join public.organizations o
      on o.id = om.organization_id
    where om.organization_id = p_organization_id
      and om.user_id = auth.uid()
      and lower(
        coalesce(
          om.membership_status::text,
          'active'
        )
      ) = 'active'
      and lower(
        coalesce(
          o.status::text,
          'active'
        )
      ) = 'active'
    limit 1
  ),

  role_grants as (
    select distinct
      p.id as permission_id,
      p.code::text as permission_code,
      p.module::text as permission_module,
      p.action::text as permission_action,
      p.description::text as permission_description,
      'role'::text as granted_via,
      r.code::text as role_code
    from active_membership am
    join public.member_roles mr
      on mr.organization_member_id =
         am.organization_member_id
    join public.roles r
      on r.id = mr.role_id
    join public.role_permissions rp
      on rp.role_id = r.id
    join public.permissions p
      on p.id = rp.permission_id
  ),

  owner_grants as (
    select
      p.id as permission_id,
      p.code::text as permission_code,
      p.module::text as permission_module,
      p.action::text as permission_action,
      p.description::text as permission_description,
      'owner'::text as granted_via,
      null::text as role_code
    from active_membership am
    cross join public.permissions p
    where am.is_owner is true
  ),

  combined_grants as (
    select * from role_grants

    union

    select * from owner_grants
  )

  select
    cg.permission_id,
    cg.permission_code,
    cg.permission_module,
    cg.permission_action,
    cg.permission_description,
    cg.granted_via,
    cg.role_code
  from combined_grants cg
  order by
    cg.permission_code,
    cg.granted_via,
    cg.role_code;

$function$;

-- ------------------------------------------------------------
-- 4. Restrict RPC execution
-- ------------------------------------------------------------

revoke all
on function public.get_my_organization_permissions(uuid)
from public;

revoke all
on function public.get_my_organization_permissions(uuid)
from anon;

grant execute
on function public.get_my_organization_permissions(uuid)
to authenticated;

grant execute
on function public.get_my_organization_permissions(uuid)
to service_role;

comment on function public.get_my_organization_permissions(uuid) is
'Returns permission grants for the currently authenticated user within an active SalesSetu organization. Owners receive all registered permissions.';

-- ------------------------------------------------------------
-- 5. Reload PostgREST schema cache
-- ------------------------------------------------------------

select pg_notify('pgrst', 'reload schema');

commit;