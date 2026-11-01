-- Allow a Sales Agent to resolve their own employee identity when
-- viewing follow-up tasks assigned to them. Existing assignment-view
-- policies remain unchanged; this does not expose the wider team roster.

begin;

drop policy if exists assignment_agent_profiles_self_select_policy
on public.assignment_agent_profiles;

create policy assignment_agent_profiles_self_select_policy
on public.assignment_agent_profiles
for select
to authenticated
using (user_id = auth.uid());

commit;
