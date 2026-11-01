begin;

-- Allow standard Sales Agents to enter the authenticated workspace.
-- This is intentionally limited to the dashboard landing permission;
-- no owner, administrative, member-management, workflow, billing,
-- or assignment-management permissions are granted here.
insert into public.role_permissions (
  role_id,
  permission_id
)
select
  role_record.id,
  permission_record.id
from public.roles as role_record
join public.permissions as permission_record
  on permission_record.code = 'dashboard.view'
where role_record.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;

commit;
