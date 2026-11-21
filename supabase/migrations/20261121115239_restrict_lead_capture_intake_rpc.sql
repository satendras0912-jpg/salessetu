-- Forward-only hardening. Do not alter the historical intake migrations:
-- Supabase defaults grant EXECUTE to anon and authenticated separately from
-- PUBLIC, so revoking only PUBLIC did not make this SECURITY DEFINER RPC
-- service-role-only.
begin;

revoke execute
on function public.ingest_lead_capture_intake(jsonb)
from public;

revoke execute
on function public.ingest_lead_capture_intake(jsonb)
from anon, authenticated;

grant execute
on function public.ingest_lead_capture_intake(jsonb)
to service_role;

commit;
