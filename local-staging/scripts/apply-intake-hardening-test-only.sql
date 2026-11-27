-- Disposable CI database only. This is a test fixture, not a production migration.
do $$
declare
  signature text;
  function_id regprocedure;
  definition text;
  updated_definition text;
begin
  foreach signature in array array[
    'public.ingest_lead_capture_intake(jsonb)',
    'public.attempt_lead_capture_intake(uuid)'
  ] loop
    function_id := to_regprocedure(signature);
    if function_id is null then raise exception 'Missing function: %', signature; end if;
    definition := pg_get_functiondef(function_id);
    updated_definition := replace(definition, 'auth.role() <> ''service_role''', 'auth.role() is distinct from ''service_role''');
    if updated_definition = definition then
      raise exception 'Expected guard was not found in %', signature;
    end if;
    execute updated_definition;
  end loop;
end
$$;
revoke execute on function public.ingest_lead_capture_intake(jsonb) from public, anon, authenticated;
revoke execute on function public.attempt_lead_capture_intake(uuid) from public, anon, authenticated;
grant execute on function public.ingest_lead_capture_intake(jsonb) to service_role;
grant execute on function public.attempt_lead_capture_intake(uuid) to service_role;
