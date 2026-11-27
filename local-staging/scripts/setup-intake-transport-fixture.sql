-- Disposable staging fixtures; no customer data.
insert into public.organizations(id,name,slug,organization_type)
values ('3d6c4444-0000-4000-8000-000000000001','Synthetic Transport Tenant','ci-transport-tenant','brokerage');
insert into public.lead_capture_routes(route_key,display_name,organization_id)
values ('ci-transport-route','CI transport route','3d6c4444-0000-4000-8000-000000000001');
