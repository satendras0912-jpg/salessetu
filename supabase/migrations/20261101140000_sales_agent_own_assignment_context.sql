-- Let a Sales Agent read only their own active lead assignment.
-- Wider assignment-view policies remain unchanged, so the team roster
-- and other agents' assignments are never exposed.

begin;

drop policy if exists lead_assignments_assigned_user_self_select_policy
on public.lead_assignments;

create policy lead_assignments_assigned_user_self_select_policy
on public.lead_assignments
for select
to authenticated
using (assigned_user_id = auth.uid());

commit;
