begin;

-- The original platform-admin seed ran before assignment permissions existed.
-- Add only the manual-assignment grant required by the live lead workflow.
--
-- Organization owners already receive implicit access through
-- has_organization_permission(); this covers a platform administrator whose
-- membership is not marked as an organization owner.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  role_row.id,
  permission_row.id
from public.roles role_row
join public.permissions permission_row
  on permission_row.code = 'assignment.manual_assign'
where role_row.code = 'platform_admin'
on conflict (role_id, permission_id) do nothing;

select pg_notify('pgrst', 'reload schema');

commit;
