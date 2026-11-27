-- This script must run only in a disposable, synthetic staging database.
do $$
declare amount integer;
begin
  select count(*) into amount from public.leads
  where organization_id = '3d6c4444-0000-4000-8000-000000000001'::uuid
    and metadata ->> 'idempotency_key' = 'ci-only-transport-test';
  if amount <> 1 then raise exception 'Expected exactly one lead in synthetic transport tenant, found %', amount; end if;
  select count(*) into amount from public.leads
  where organization_id <> '3d6c4444-0000-4000-8000-000000000001'::uuid
    and metadata ->> 'idempotency_key' = 'ci-only-transport-test';
  if amount <> 0 then raise exception 'Transport lead appeared in an unexpected tenant'; end if;
  raise notice 'PASS: authenticated fixture saved exactly one lead in the synthetic tenant';
end
$$;
