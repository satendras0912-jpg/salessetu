-- Disposable staging only: synthetic rows are rolled back.
begin;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);

insert into public.organizations(id, name, slug, organization_type)
values
  ('1d6c4444-0000-4000-8000-000000000001', 'Synthetic Brokerage A', 'ci-synthetic-brokerage-a', 'brokerage'),
  ('1d6c4444-0000-4000-8000-000000000002', 'Synthetic Brokerage B', 'ci-synthetic-brokerage-b', 'brokerage');
insert into public.lead_capture_routes(route_key, display_name, organization_id)
values ('ci-synthetic-route-a', 'CI synthetic route', '1d6c4444-0000-4000-8000-000000000001');

do $$
declare
  payload jsonb := jsonb_build_object('route_key', 'ci-synthetic-route-a',
    'full_name', 'Synthetic CI Test', 'phone', '9999000000',
    'idempotency_key', 'ci-synthetic-idempotency-test',
    'metadata', jsonb_build_object('synthetic', true));
  first_receipt jsonb;
  second_receipt jsonb;
  actual_org uuid;
  matching_leads integer;
begin
  first_receipt := public.ingest_lead_capture_intake(payload);
  if first_receipt ->> 'status' is distinct from 'processed'
     or first_receipt ->> 'lead_id' is null
     or first_receipt ->> 'intake_id' is null
     or first_receipt -> 'duplicate' is distinct from 'false'::jsonb then
    raise exception 'First intake did not return a saved-lead receipt: %', first_receipt;
  end if;
  select organization_id into actual_org from public.leads
    where id = (first_receipt ->> 'lead_id')::uuid;
  if actual_org is distinct from '1d6c4444-0000-4000-8000-000000000001'::uuid then
    raise exception 'Lead was not stored in the expected synthetic tenant';
  end if;
  second_receipt := public.ingest_lead_capture_intake(payload);
  if second_receipt -> 'duplicate' is distinct from 'true'::jsonb
     or second_receipt ->> 'lead_id' is distinct from first_receipt ->> 'lead_id'
     or second_receipt ->> 'intake_id' is distinct from first_receipt ->> 'intake_id' then
    raise exception 'Duplicate receipt did not match original';
  end if;
  select count(*) into matching_leads from public.leads
    where metadata ->> 'idempotency_key' = 'ci-synthetic-idempotency-test';
  if matching_leads <> 1 then raise exception 'Expected one matching synthetic lead; found %', matching_leads; end if;
  raise notice 'PASS: synthetic route, persisted receipt, trigger and idempotency';
end $$;

-- Test real RLS under two synthetic authenticated owner identities.
insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values
 ('2d6c4444-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ci-owner-a@example.invalid', '{}'::jsonb, '{}'::jsonb),
 ('2d6c4444-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'ci-owner-b@example.invalid', '{}'::jsonb, '{}'::jsonb);
insert into public.organization_members(organization_id, user_id, is_owner)
values
 ('1d6c4444-0000-4000-8000-000000000001', '2d6c4444-0000-4000-8000-000000000001', true),
 ('1d6c4444-0000-4000-8000-000000000002', '2d6c4444-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"2d6c4444-0000-4000-8000-000000000001"}', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '2d6c4444-0000-4000-8000-000000000001', true);
set local role authenticated;
do $$
declare visible integer;
begin
 select count(*) into visible from public.leads where metadata ->> 'idempotency_key' = 'ci-synthetic-idempotency-test';
 if visible <> 1 then raise exception 'Expected tenant A owner to see synthetic lead, saw %', visible; end if;
end $$;
select set_config('request.jwt.claims', '{"role":"authenticated","sub":"2d6c4444-0000-4000-8000-000000000002"}', true);
select set_config('request.jwt.claim.sub', '2d6c4444-0000-4000-8000-000000000002', true);
do $$
declare visible integer;
begin
 select count(*) into visible from public.leads where metadata ->> 'idempotency_key' = 'ci-synthetic-idempotency-test';
 if visible <> 0 then raise exception 'Tenant B owner saw tenant A synthetic lead'; end if;
 raise notice 'PASS: synthetic owners respect cross-tenant lead visibility';
end $$;
reset role;
rollback;
