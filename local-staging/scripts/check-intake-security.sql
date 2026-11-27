-- Run only against an isolated staging database containing the real functions.
-- Metadata assertions only: this script does not call either intake function.
do $$
declare
  signature text;
  function_id regprocedure;
  definition text;
begin
  foreach signature in array array[
    'public.ingest_lead_capture_intake(jsonb)',
    'public.attempt_lead_capture_intake(uuid)'
  ] loop
    function_id := to_regprocedure(signature);
    if function_id is null then
      raise exception 'Required function missing: %', signature;
    end if;
    if has_function_privilege('anon', function_id, 'EXECUTE')
       or has_function_privilege('authenticated', function_id, 'EXECUTE')
       or not has_function_privilege('service_role', function_id, 'EXECUTE') then
      raise exception 'Unexpected role privileges for %', signature;
    end if;
    definition := lower(pg_get_functiondef(function_id));
    if definition !~ 'auth\.role\(\)\s+is\s+distinct\s+from\s+''service_role''' then
      raise exception 'Null-safe service-role guard not found in %; manual review required', signature;
    end if;
    raise notice 'PASS: metadata checks for %', signature;
  end loop;
end
$$;
