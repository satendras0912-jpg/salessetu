-- LOCAL CONTRACT FIXTURE ONLY. Not SalesSetu production schema.
-- This SQL runs solely inside ./local-staging/supabase/migrations.
begin;
create table public.local_test_leads (
  id uuid primary key default gen_random_uuid(),
  route_key text not null check (route_key = 'kavyarpit-local-test'),
  synthetic_reference text not null check (synthetic_reference ~ '^QA-[A-Z0-9-]{4,50}$'),
  created_at timestamptz not null default now()
);
create table public.local_test_receipts (
  id uuid primary key default gen_random_uuid(),
  route_key text not null check (route_key = 'kavyarpit-local-test'),
  idempotency_key text not null,
  processing_status text not null default 'pending' check (processing_status in ('pending','processed')),
  processed_lead_id uuid references public.local_test_leads(id) on delete restrict,
  received_at timestamptz not null default now(),
  unique (route_key, idempotency_key)
);
alter table public.local_test_leads enable row level security;
alter table public.local_test_receipts enable row level security;
revoke all on table public.local_test_leads, public.local_test_receipts from public, anon, authenticated;
grant select, insert, update on table public.local_test_leads, public.local_test_receipts to service_role;

create function public.local_ingest_test_receipt(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_route text := nullif(btrim(p_payload ->> 'route_key'), '');
  v_key text := nullif(btrim(p_payload ->> 'idempotency_key'), '');
  v_ref text := nullif(btrim(p_payload ->> 'synthetic_reference'), '');
  v_receipt_id uuid;
  v_lead_id uuid;
  v_status text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'LOCAL_SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if v_route is distinct from 'kavyarpit-local-test'
    or v_key is null or length(v_key) > 120
    or v_ref is null or v_ref !~ '^QA-[A-Z0-9-]{4,50}$'
    or p_payload ?| array['email','phone','whatsapp','full_name'] then
    raise exception 'INVALID_SYNTHETIC_TEST_INPUT' using errcode = '22023';
  end if;

  insert into public.local_test_receipts(route_key,idempotency_key)
  values(v_route,v_key)
  on conflict(route_key,idempotency_key) do nothing
  returning id into v_receipt_id;

  if v_receipt_id is null then
    select r.id,r.processed_lead_id,r.processing_status
      into v_receipt_id,v_lead_id,v_status
    from public.local_test_receipts r
    where r.route_key=v_route and r.idempotency_key=v_key;
    return jsonb_build_object('intake_id',v_receipt_id,'lead_id',v_lead_id,
      'status',v_status,'duplicate',true,'route_key',v_route);
  end if;

  insert into public.local_test_leads(route_key,synthetic_reference)
  values(v_route,v_ref) returning id into v_lead_id;
  update public.local_test_receipts
  set processing_status='processed',processed_lead_id=v_lead_id
  where id=v_receipt_id;
  return jsonb_build_object('intake_id',v_receipt_id,'lead_id',v_lead_id,
    'status','processed','duplicate',false,'route_key',v_route);
end;
$function$;
revoke all on function public.local_ingest_test_receipt(jsonb) from public, anon, authenticated;
grant execute on function public.local_ingest_test_receipt(jsonb) to service_role;
commit;
