-- ============================================================
-- 20261101105000_correct_kavyarpit_employee_id_order.sql
-- Owner KRV-001, Shweta KRV-002, Arpit KRV-003.
-- Future Sales Agents continue from KRV-004.
-- ============================================================

begin;

with assignments(email, employee_id) as (
  values
    ('digitalavalokan@gmail.com', 'KRV-001'),
    ('shwetas0912@gmail.com', 'KRV-002'),
    ('nagixmas@gmail.com', 'KRV-003')
),
target_members as (
  select
    organization_member.id,
    assignments.employee_id
  from public.organization_members as organization_member
  join public.organizations as organization
    on organization.id = organization_member.organization_id
  join auth.users as authenticated_user
    on authenticated_user.id = organization_member.user_id
  join assignments
    on lower(authenticated_user.email) = assignments.email
  where organization.name = 'Kavyarpit Realty Pvt Ltd'
)
update public.organization_members as organization_member
set metadata = jsonb_set(
  coalesce(organization_member.metadata, '{}'::jsonb),
  '{employee_id}',
  to_jsonb(target_members.employee_id),
  true
)
from target_members
where organization_member.id = target_members.id;

update public.assignment_agent_profiles as agent_profile
set agent_code = concat('KRV-TMP-', replace(agent_profile.id::text, '-', ''))
from public.organizations as organization
where organization.id = agent_profile.organization_id
  and organization.name = 'Kavyarpit Realty Pvt Ltd';

update public.assignment_agent_profiles as agent_profile
set agent_code = organization_member.metadata ->> 'employee_id'
from public.organization_members as organization_member
join public.organizations as organization
  on organization.id = organization_member.organization_id
where organization_member.organization_id = agent_profile.organization_id
  and organization_member.user_id = agent_profile.user_id
  and organization.name = 'Kavyarpit Realty Pvt Ltd'
  and organization_member.metadata ? 'employee_id';

commit;