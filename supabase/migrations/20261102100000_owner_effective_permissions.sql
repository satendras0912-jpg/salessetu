begin;

-- ============================================================================
-- Owner effective permissions
-- Purpose:
--   Keep the application permission context aligned with the database's
--   owner-override policy. Workspace owners must receive every registered
--   permission, including permissions introduced after their membership.
--
-- This fixes site-visits.create being omitted from an owner's effective
-- permission context even though has_organization_permission() treats an
-- active owner as fully authorized.
-- ============================================================================

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

revoke all
on function public.get_my_organization_permissions(uuid)
from public;

revoke all
on function public.get_my_organization_permissions(uuid)
from anon;

grant execute
on function public.get_my_organization_permissions(uuid)
to authenticated, service_role;

comment on function public.get_my_organization_permissions(uuid) is
'Returns effective permissions for the authenticated user in an active organization. Owners receive every registered permission.';

select pg_notify('pgrst', 'reload schema');

commit;
