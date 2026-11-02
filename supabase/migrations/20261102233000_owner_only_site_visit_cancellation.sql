-- ============================================================================
-- Migration: Owner-only Site Visit Cancellation
-- Purpose:
--   Restrict Site Visit cancellation to the owning organization member.
--   Sales Agents retain their independent check-in and completion permissions.
-- ============================================================================

begin;

set local search_path = public, pg_temp;

create or replace function public.cancel_site_visit(
  requested_site_visit_id uuid,
  requested_reason text,
  requested_expected_updated_at timestamptz default null
)
returns public.site_visits
language plpgsql
security definer
set search_path = ''
as $function$
declare
  target_visit public.site_visits;
begin
  select *
  into target_visit
  from public.site_visits
  where id = requested_site_visit_id
    and deleted_at is null
  for update;

  if not found then
    raise exception
      'Site visit not found';
  end if;

  -- A service-role caller is an internal trusted integration. Every interactive
  -- caller must be the workspace owner for this organization.
  if auth.role() <> 'service_role'
    and not public.is_organization_owner(
      target_visit.organization_id,
      auth.uid()
    ) then
    raise exception
      'Only the workspace owner can cancel a site visit';
  end if;

  if requested_expected_updated_at is null then
    raise exception
      'Expected update timestamp is required';
  end if;

  if target_visit.updated_at
    is distinct from requested_expected_updated_at then
    raise exception
      'Site visit changed after the form was opened'
      using errcode = 'P0001';
  end if;

  if target_visit.status = 'cancelled' then
    return target_visit;
  end if;

  if target_visit.status in (
    'completed',
    'no_show',
    'failed'
  ) then
    raise exception
      'Site visit cannot be cancelled in status %',
      target_visit.status;
  end if;

  if nullif(
    btrim(requested_reason),
    ''
  ) is null then
    raise exception
      'Cancellation reason is required';
  end if;

  update public.site_visits
  set
    status = 'cancelled',
    cancellation_reason = btrim(requested_reason),
    updated_by = auth.uid(),
    updated_at = now()
  where id = target_visit.id
  returning *
  into target_visit;

  return target_visit;
end;
$function$;

revoke all
on function public.cancel_site_visit(uuid, text, timestamptz)
from public, anon, authenticated, service_role;

grant execute
on function public.cancel_site_visit(uuid, text, timestamptz)
to authenticated, service_role;

do $verification$
declare
  function_definition text;
begin
  function_definition := pg_get_functiondef(
    'public.cancel_site_visit(uuid,text,timestamptz)'::regprocedure
  );

  if position('is_organization_owner' in function_definition) = 0 then
    raise exception
      'Migration verification failed: owner guard is missing from cancel_site_visit.';
  end if;

  if position('site_visits.cancel' in function_definition) > 0 then
    raise exception
      'Migration verification failed: legacy permission guard remains in cancel_site_visit.';
  end if;
end;
$verification$;

notify pgrst, 'reload schema';

commit;
