-- =========================================================
-- SalesSetu Enterprise
-- Migration: 008_inventory
-- Complete Inventory, Pricing and Reservation Engine
-- =========================================================

begin;

-- 1. Permissions
insert into public.permissions (module, action, code, description)
values
 ('inventory','view','inventory.view','View builders, projects and inventory'),
 ('inventory','create','inventory.create','Create inventory records'),
 ('inventory','update','inventory.update','Update inventory records'),
 ('inventory','delete','inventory.delete','Delete inventory records'),
 ('inventory','manage_builders','inventory.manage_builders','Manage builders'),
 ('inventory','manage_projects','inventory.manage_projects','Manage projects'),
 ('inventory','manage_pricing','inventory.manage_pricing','Manage pricing'),
 ('inventory','manage_availability','inventory.manage_availability','Manage availability'),
 ('inventory','reserve','inventory.reserve','Reserve units'),
 ('inventory','release_reservation','inventory.release_reservation','Release reservations'),
 ('inventory','manage_documents','inventory.manage_documents','Manage inventory documents'),
 ('inventory','view_all','inventory.view_all','View all inventory')
on conflict (code) do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
cross join public.permissions p
where r.code in ('platform_admin','organization_admin')
  and p.module = 'inventory'
on conflict (role_id, permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
 'inventory.view','inventory.create','inventory.update','inventory.manage_builders',
 'inventory.manage_projects','inventory.manage_pricing','inventory.manage_availability',
 'inventory.reserve','inventory.release_reservation','inventory.manage_documents','inventory.view_all'
)
where r.code = 'sales_manager'
on conflict (role_id, permission_id) do nothing;

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in ('inventory.view','inventory.reserve')
where r.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;

-- 2. Builders
create table public.builders (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 builder_code text not null,
 legal_name text not null,
 brand_name text not null,
 description text,
 status text not null default 'active' check (status in ('prospect','onboarding','active','inactive','suspended','archived')),
 registration_number text,
 gst_number text,
 pan_number text,
 website_url text,
 logo_url text,
 primary_contact_name text,
 primary_contact_phone text,
 primary_contact_email text,
 office_address text,
 city text,
 state text,
 postal_code text,
 country text not null default 'India',
 years_in_business integer check (years_in_business is null or years_in_business >= 0),
 completed_projects_count integer not null default 0 check (completed_projects_count >= 0),
 ongoing_projects_count integer not null default 0 check (ongoing_projects_count >= 0),
 rating numeric(3,2) check (rating is null or rating between 0 and 5),
 is_verified boolean not null default false,
 tags text[] not null default '{}'::text[],
 metadata jsonb not null default '{}'::jsonb,
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 deleted_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (organization_id,builder_code)
);
create index builders_org_idx on public.builders(organization_id);
create index builders_status_idx on public.builders(organization_id,status) where deleted_at is null;
create trigger builders_updated_at before update on public.builders for each row execute function public.set_updated_at();

-- 3. Projects
create table public.projects (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 builder_id uuid not null references public.builders(id) on delete restrict,
 project_code text not null,
 project_name text not null,
 slug text,
 description text,
 project_type text not null check (project_type in ('residential','commercial','mixed_use','plot','villa','farmhouse','industrial','retail','office','warehouse','other')),
 development_type text check (development_type is null or development_type in ('new_launch','pre_launch','under_construction','ready_to_move','resale','completed','redevelopment')),
 status text not null default 'draft' check (status in ('draft','pre_launch','launched','active','sold_out','on_hold','completed','cancelled','archived')),
 inventory_status text not null default 'available' check (inventory_status in ('available','limited','sold_out','not_released','on_hold')),
 rera_number text,
 launch_date date,
 possession_date date,
 expected_completion_date date,
 total_land_area numeric(15,2) check (total_land_area is null or total_land_area >= 0),
 land_area_unit text,
 total_towers integer check (total_towers is null or total_towers >= 0),
 total_units integer check (total_units is null or total_units >= 0),
 available_units integer check (available_units is null or available_units >= 0),
 sold_units integer check (sold_units is null or sold_units >= 0),
 address_line_1 text,
 address_line_2 text,
 locality text,
 city text not null,
 state text,
 postal_code text,
 country text not null default 'India',
 latitude numeric(10,7) check (latitude is null or latitude between -90 and 90),
 longitude numeric(10,7) check (longitude is null or longitude between -180 and 180),
 location_url text,
 minimum_price numeric(18,2) check (minimum_price is null or minimum_price >= 0),
 maximum_price numeric(18,2) check (maximum_price is null or maximum_price >= 0),
 price_currency text not null default 'INR',
 base_price_per_sqft numeric(18,2) check (base_price_per_sqft is null or base_price_per_sqft >= 0),
 brokerage_percentage numeric(7,4) check (brokerage_percentage is null or brokerage_percentage between 0 and 100),
 brokerage_fixed_amount numeric(18,2) check (brokerage_fixed_amount is null or brokerage_fixed_amount >= 0),
 featured_image_url text,
 brochure_url text,
 walkthrough_video_url text,
 amenities text[] not null default '{}'::text[],
 specifications jsonb not null default '{}'::jsonb,
 highlights text[] not null default '{}'::text[],
 tags text[] not null default '{}'::text[],
 metadata jsonb not null default '{}'::jsonb,
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 deleted_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (organization_id,project_code),
 unique (organization_id,slug),
 check (minimum_price is null or maximum_price is null or maximum_price >= minimum_price)
);
create index projects_org_idx on public.projects(organization_id);
create index projects_builder_idx on public.projects(builder_id,status) where deleted_at is null;
create index projects_location_idx on public.projects(organization_id,city,locality) where deleted_at is null;
create trigger projects_updated_at before update on public.projects for each row execute function public.set_updated_at();

-- 4. Project hierarchy
create table public.project_phases (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 phase_code text not null,
 phase_name text not null,
 status text not null default 'planned' check (status in ('planned','pre_launch','launched','under_construction','completed','on_hold','cancelled')),
 launch_date date,
 possession_date date,
 total_units integer check (total_units is null or total_units >= 0),
 available_units integer check (available_units is null or available_units >= 0),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (project_id,phase_code)
);
create trigger project_phases_updated_at before update on public.project_phases for each row execute function public.set_updated_at();

create table public.project_towers (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 phase_id uuid references public.project_phases(id) on delete set null,
 tower_code text not null,
 tower_name text not null,
 status text not null default 'active' check (status in ('planned','active','under_construction','completed','on_hold','cancelled')),
 total_floors integer check (total_floors is null or total_floors >= 0),
 units_per_floor integer check (units_per_floor is null or units_per_floor >= 0),
 total_units integer check (total_units is null or total_units >= 0),
 lifts_count integer check (lifts_count is null or lifts_count >= 0),
 possession_date date,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (project_id,tower_code)
);
create trigger project_towers_updated_at before update on public.project_towers for each row execute function public.set_updated_at();

create table public.project_floors (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 tower_id uuid not null references public.project_towers(id) on delete cascade,
 floor_number integer not null,
 floor_label text,
 floor_type text not null default 'standard' check (floor_type in ('basement','ground','podium','standard','refuge','penthouse','terrace','other')),
 status text not null default 'active' check (status in ('active','inactive','blocked','completed')),
 total_units integer check (total_units is null or total_units >= 0),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (tower_id,floor_number)
);
create trigger project_floors_updated_at before update on public.project_floors for each row execute function public.set_updated_at();

-- 5. Unit configurations and units
create table public.unit_configurations (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 configuration_code text not null,
 configuration_name text not null,
 property_type text not null check (property_type in ('apartment','villa','duplex','penthouse','studio','plot','shop','office','warehouse','farmhouse','floor','other')),
 bedrooms numeric(4,1), bathrooms numeric(4,1), balconies numeric(4,1),
 carpet_area numeric(15,2), built_up_area numeric(15,2), super_area numeric(15,2),
 area_unit text not null default 'sq_ft',
 base_price numeric(18,2),
 base_price_per_unit numeric(18,2),
 price_unit text not null default 'per_sq_ft',
 floor_plan_url text,
 is_active boolean not null default true,
 specifications jsonb not null default '{}'::jsonb,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (project_id,configuration_code)
);
create trigger unit_configurations_updated_at before update on public.unit_configurations for each row execute function public.set_updated_at();

create table public.inventory_units (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 phase_id uuid references public.project_phases(id) on delete set null,
 tower_id uuid references public.project_towers(id) on delete set null,
 floor_id uuid references public.project_floors(id) on delete set null,
 configuration_id uuid references public.unit_configurations(id) on delete set null,
 inventory_code text not null,
 unit_number text not null,
 property_type text not null check (property_type in ('apartment','villa','duplex','penthouse','studio','plot','shop','office','warehouse','farmhouse','floor','other')),
 unit_status text not null default 'available' check (unit_status in ('not_released','available','reserved','blocked','token_received','booked','sold','cancelled','owner_inventory','management_hold','unavailable')),
 sales_status text not null default 'open' check (sales_status in ('open','negotiation','on_hold','closed','not_for_sale')),
 ownership_type text not null default 'developer',
 facing text,
 view_type text,
 floor_number integer,
 bedrooms numeric(4,1), bathrooms numeric(4,1), balconies numeric(4,1),
 carpet_area numeric(15,2), built_up_area numeric(15,2), super_area numeric(15,2), plot_area numeric(15,2),
 area_unit text not null default 'sq_ft',
 base_price numeric(18,2),
 base_price_per_unit numeric(18,2),
 current_price numeric(18,2),
 all_inclusive_price numeric(18,2),
 minimum_negotiable_price numeric(18,2),
 currency text not null default 'INR',
 plc_amount numeric(18,2), floor_rise_amount numeric(18,2), parking_charges numeric(18,2), club_charges numeric(18,2), maintenance_charges numeric(18,2), other_charges numeric(18,2),
 available_from date,
 possession_date date,
 construction_status text,
 completion_percentage numeric(5,2),
 inventory_source text not null default 'developer',
 is_featured boolean not null default false,
 is_exclusive boolean not null default false,
 exclusive_until timestamptz,
 primary_image_url text,
 floor_plan_url text,
 amenities text[] not null default '{}'::text[],
 specifications jsonb not null default '{}'::jsonb,
 tags text[] not null default '{}'::text[],
 metadata jsonb not null default '{}'::jsonb,
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 deleted_at timestamptz,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (organization_id,inventory_code),
 unique (project_id,unit_number),
 check (minimum_negotiable_price is null or current_price is null or minimum_negotiable_price <= current_price)
);
create index inventory_units_project_idx on public.inventory_units(project_id,unit_status,sales_status) where deleted_at is null;
create index inventory_units_price_idx on public.inventory_units(organization_id,current_price) where deleted_at is null;
create index inventory_units_type_idx on public.inventory_units(organization_id,property_type,bedrooms) where deleted_at is null;
create trigger inventory_units_updated_at before update on public.inventory_units for each row execute function public.set_updated_at();

-- 6. Pricing, payment plans, documents
create table public.inventory_price_components (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 inventory_unit_id uuid references public.inventory_units(id) on delete cascade,
 configuration_id uuid references public.unit_configurations(id) on delete cascade,
 component_code text not null,
 component_name text not null,
 component_type text not null,
 calculation_type text not null check (calculation_type in ('fixed','per_sq_ft','per_sq_m','percentage','per_unit','formula')),
 amount numeric(18,2),
 percentage numeric(7,4),
 formula text,
 is_mandatory boolean not null default true,
 is_taxable boolean not null default false,
 tax_percentage numeric(7,4),
 valid_from date,
 valid_until date,
 status text not null default 'active' check (status in ('draft','active','inactive','expired')),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check (inventory_unit_id is not null or configuration_id is not null)
);
create trigger inventory_price_components_updated_at before update on public.inventory_price_components for each row execute function public.set_updated_at();

create table public.project_payment_plans (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 project_id uuid not null references public.projects(id) on delete cascade,
 plan_code text not null,
 plan_name text not null,
 plan_type text not null,
 description text,
 booking_percentage numeric(7,4),
 booking_amount numeric(18,2),
 discount_percentage numeric(7,4),
 valid_from date,
 valid_until date,
 status text not null default 'active' check (status in ('draft','active','inactive','expired')),
 terms_and_conditions text,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (project_id,plan_code)
);
create trigger project_payment_plans_updated_at before update on public.project_payment_plans for each row execute function public.set_updated_at();

create table public.project_payment_plan_milestones (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 payment_plan_id uuid not null references public.project_payment_plans(id) on delete cascade,
 milestone_code text not null,
 milestone_name text not null,
 sequence_number integer not null check (sequence_number >= 0),
 milestone_type text not null,
 payment_percentage numeric(7,4),
 fixed_amount numeric(18,2),
 due_after_days integer,
 construction_stage text,
 description text,
 is_mandatory boolean not null default true,
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (payment_plan_id,milestone_code)
);
create trigger payment_plan_milestones_updated_at before update on public.project_payment_plan_milestones for each row execute function public.set_updated_at();

create table public.inventory_documents (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 builder_id uuid references public.builders(id) on delete cascade,
 project_id uuid references public.projects(id) on delete cascade,
 inventory_unit_id uuid references public.inventory_units(id) on delete cascade,
 document_name text not null,
 document_type text not null,
 storage_bucket text,
 storage_path text,
 public_url text,
 mime_type text,
 version_number integer not null default 1,
 status text not null default 'active',
 is_public boolean not null default false,
 uploaded_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check (builder_id is not null or project_id is not null or inventory_unit_id is not null)
);
create trigger inventory_documents_updated_at before update on public.inventory_documents for each row execute function public.set_updated_at();

-- 7. History and reservations
create table public.inventory_unit_status_history (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 inventory_unit_id uuid not null references public.inventory_units(id) on delete cascade,
 previous_status text,
 new_status text not null,
 previous_price numeric(18,2),
 new_price numeric(18,2),
 change_type text not null default 'status_change',
 change_reason text,
 changed_by uuid references auth.users(id) on delete set null,
 changed_at timestamptz not null default now()
);

create table public.inventory_reservations (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 inventory_unit_id uuid not null references public.inventory_units(id) on delete cascade,
 lead_id uuid references public.leads(id) on delete set null,
 customer_id uuid references public.customers(id) on delete set null,
 booking_id uuid references public.bookings(id) on delete set null,
 reservation_number text not null,
 status text not null default 'active' check (status in ('active','confirmed','converted','expired','released','cancelled')),
 reservation_type text not null default 'temporary_hold',
 reserved_by uuid references auth.users(id) on delete set null,
 reserved_at timestamptz not null default now(),
 expires_at timestamptz,
 confirmed_at timestamptz,
 released_at timestamptz,
 released_by uuid references auth.users(id) on delete set null,
 release_reason text,
 token_amount numeric(18,2),
 notes text,
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (organization_id,reservation_number),
 check (lead_id is not null or customer_id is not null or reservation_type in ('management_hold','builder_hold'))
);
create unique index inventory_reservations_active_unit_idx on public.inventory_reservations(inventory_unit_id) where status in ('active','confirmed');
create trigger inventory_reservations_updated_at before update on public.inventory_reservations for each row execute function public.set_updated_at();

-- 8. Validation
create or replace function public.validate_inventory_relations()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if not exists (select 1 from public.projects p where p.id = new.project_id and p.organization_id = new.organization_id and p.deleted_at is null) then
   raise exception 'Project must belong to the same organization';
 end if;
 return new;
end;
$$;

create trigger project_phases_validate before insert or update of organization_id,project_id on public.project_phases for each row execute function public.validate_inventory_relations();
create trigger project_towers_validate before insert or update of organization_id,project_id on public.project_towers for each row execute function public.validate_inventory_relations();
create trigger project_floors_validate before insert or update of organization_id,project_id on public.project_floors for each row execute function public.validate_inventory_relations();
create trigger unit_configurations_validate before insert or update of organization_id,project_id on public.unit_configurations for each row execute function public.validate_inventory_relations();
create trigger inventory_units_validate before insert or update of organization_id,project_id on public.inventory_units for each row execute function public.validate_inventory_relations();
create trigger price_components_validate before insert or update of organization_id,project_id on public.inventory_price_components for each row execute function public.validate_inventory_relations();
create trigger payment_plans_validate before insert or update of organization_id,project_id on public.project_payment_plans for each row execute function public.validate_inventory_relations();

-- 9. History and project counts
create or replace function public.record_inventory_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if tg_op = 'INSERT' then
   insert into public.inventory_unit_status_history(organization_id,inventory_unit_id,new_status,new_price,change_type,changed_by)
   values(new.organization_id,new.id,new.unit_status,new.current_price,'created',coalesce(new.created_by,auth.uid()));
 elsif new.unit_status is distinct from old.unit_status or new.current_price is distinct from old.current_price then
   insert into public.inventory_unit_status_history(organization_id,inventory_unit_id,previous_status,new_status,previous_price,new_price,change_type,changed_by)
   values(new.organization_id,new.id,old.unit_status,new.unit_status,old.current_price,new.current_price,
     case when new.unit_status is distinct from old.unit_status then 'status_change' else 'price_change' end,
     coalesce(new.updated_by,auth.uid()));
 end if;
 return new;
end;
$$;
create trigger inventory_units_history after insert or update of unit_status,current_price on public.inventory_units for each row execute function public.record_inventory_history();

create or replace function public.refresh_project_inventory_counts(requested_project_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare t integer; a integer; s integer;
begin
 select count(*), count(*) filter(where unit_status='available'), count(*) filter(where unit_status in ('booked','sold'))
 into t,a,s from public.inventory_units where project_id=requested_project_id and deleted_at is null;
 update public.projects set total_units=t, available_units=a, sold_units=s,
 inventory_status=case when t=0 then 'not_released' when a=0 then 'sold_out' when a<=greatest(1,ceil(t*0.10)::int) then 'limited' else 'available' end,
 updated_at=now() where id=requested_project_id;
end;
$$;

create or replace function public.trigger_refresh_project_inventory_counts()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if tg_op='DELETE' then perform public.refresh_project_inventory_counts(old.project_id); return old; end if;
 perform public.refresh_project_inventory_counts(new.project_id);
 if tg_op='UPDATE' and old.project_id is distinct from new.project_id then perform public.refresh_project_inventory_counts(old.project_id); end if;
 return new;
end;
$$;
create trigger inventory_units_counts after insert or update of project_id,unit_status,deleted_at or delete on public.inventory_units for each row execute function public.trigger_refresh_project_inventory_counts();

-- 10. Reservation functions
create or replace function public.reserve_inventory_unit(
 requested_inventory_unit_id uuid,
 requested_reservation_number text,
 requested_lead_id uuid default null,
 requested_customer_id uuid default null,
 requested_expires_at timestamptz default null,
 requested_token_amount numeric default null,
 requested_notes text default null
)
returns public.inventory_reservations language plpgsql security definer set search_path = '' as $$
declare u public.inventory_units; r public.inventory_reservations;
begin
 select * into u from public.inventory_units where id=requested_inventory_unit_id and deleted_at is null for update;
 if not found then raise exception 'Inventory unit not found'; end if;
 if not public.has_organization_permission(u.organization_id,'inventory.reserve') then raise exception 'Permission denied'; end if;
 if u.unit_status <> 'available' then raise exception 'Unit is not available'; end if;
 insert into public.inventory_reservations(organization_id,inventory_unit_id,lead_id,customer_id,reservation_number,reserved_by,expires_at,token_amount,notes,created_by)
 values(u.organization_id,u.id,requested_lead_id,requested_customer_id,requested_reservation_number,auth.uid(),requested_expires_at,requested_token_amount,requested_notes,auth.uid())
 returning * into r;
 update public.inventory_units set unit_status='reserved',sales_status='on_hold',updated_by=auth.uid(),updated_at=now() where id=u.id;
 return r;
end;
$$;
revoke all on function public.reserve_inventory_unit(uuid,text,uuid,uuid,timestamptz,numeric,text) from public;
grant execute on function public.reserve_inventory_unit(uuid,text,uuid,uuid,timestamptz,numeric,text) to authenticated;

create or replace function public.release_inventory_reservation(requested_reservation_id uuid, requested_reason text)
returns public.inventory_reservations language plpgsql security definer set search_path = '' as $$
declare r public.inventory_reservations;
begin
 select * into r from public.inventory_reservations where id=requested_reservation_id for update;
 if not found then raise exception 'Reservation not found'; end if;
 if not public.has_organization_permission(r.organization_id,'inventory.release_reservation') then raise exception 'Permission denied'; end if;
 update public.inventory_reservations set status='released',released_at=now(),released_by=auth.uid(),release_reason=requested_reason,updated_by=auth.uid(),updated_at=now()
 where id=r.id returning * into r;
 update public.inventory_units set unit_status='available',sales_status='open',updated_by=auth.uid(),updated_at=now() where id=r.inventory_unit_id;
 return r;
end;
$$;
revoke all on function public.release_inventory_reservation(uuid,text) from public;
grant execute on function public.release_inventory_reservation(uuid,text) to authenticated;

-- 11. Booking link
alter table public.bookings add column if not exists inventory_unit_id uuid references public.inventory_units(id) on delete set null;
create index if not exists bookings_inventory_unit_idx on public.bookings(inventory_unit_id) where inventory_unit_id is not null;

create or replace function public.sync_inventory_from_booking()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.inventory_unit_id is null then return new; end if;
 if new.booking_status in ('token_paid','application_submitted','documents_pending','documents_verified','loan_processing','loan_approved','agreement_signed','payment_pending','confirmed') then
   update public.inventory_units set unit_status=case when new.booking_status='confirmed' then 'booked' else 'token_received' end,sales_status='closed',updated_at=now() where id=new.inventory_unit_id;
 elsif new.booking_status in ('cancelled','refunded') then
   update public.inventory_units set unit_status='available',sales_status='open',updated_at=now() where id=new.inventory_unit_id;
 end if;
 return new;
end;
$$;
create trigger bookings_sync_inventory after insert or update of booking_status,inventory_unit_id on public.bookings for each row execute function public.sync_inventory_from_booking();

-- 12. Dashboard and search
create or replace function public.get_inventory_dashboard(requested_organization_id uuid, requested_project_id uuid default null)
returns table(total_units bigint,available_units bigint,reserved_units bigint,booked_units bigint,sold_units bigint,total_inventory_value numeric,available_inventory_value numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
 if not public.has_organization_permission(requested_organization_id,'inventory.view') then raise exception 'Permission denied'; end if;
 return query select count(*),count(*) filter(where unit_status='available'),count(*) filter(where unit_status='reserved'),count(*) filter(where unit_status='booked'),count(*) filter(where unit_status='sold'),
 coalesce(sum(coalesce(current_price,all_inclusive_price,0)),0),coalesce(sum(coalesce(current_price,all_inclusive_price,0)) filter(where unit_status='available'),0)
 from public.inventory_units where organization_id=requested_organization_id and deleted_at is null and (requested_project_id is null or project_id=requested_project_id);
end;
$$;
revoke all on function public.get_inventory_dashboard(uuid,uuid) from public;
grant execute on function public.get_inventory_dashboard(uuid,uuid) to authenticated;

-- 13. RLS
alter table public.builders enable row level security;
alter table public.projects enable row level security;
alter table public.project_phases enable row level security;
alter table public.project_towers enable row level security;
alter table public.project_floors enable row level security;
alter table public.unit_configurations enable row level security;
alter table public.inventory_units enable row level security;
alter table public.inventory_price_components enable row level security;
alter table public.project_payment_plans enable row level security;
alter table public.project_payment_plan_milestones enable row level security;
alter table public.inventory_documents enable row level security;
alter table public.inventory_unit_status_history enable row level security;
alter table public.inventory_reservations enable row level security;

create policy "View builders" on public.builders for select to authenticated using (deleted_at is null and public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage builders" on public.builders for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_builders')) with check (public.has_organization_permission(organization_id,'inventory.manage_builders'));
create policy "View projects" on public.projects for select to authenticated using (deleted_at is null and public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage projects" on public.projects for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_projects')) with check (public.has_organization_permission(organization_id,'inventory.manage_projects'));
create policy "View phases" on public.project_phases for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage phases" on public.project_phases for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_projects')) with check (public.has_organization_permission(organization_id,'inventory.manage_projects'));
create policy "View towers" on public.project_towers for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage towers" on public.project_towers for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_projects')) with check (public.has_organization_permission(organization_id,'inventory.manage_projects'));
create policy "View floors" on public.project_floors for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage floors" on public.project_floors for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_projects')) with check (public.has_organization_permission(organization_id,'inventory.manage_projects'));
create policy "View configurations" on public.unit_configurations for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage configurations" on public.unit_configurations for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_projects')) with check (public.has_organization_permission(organization_id,'inventory.manage_projects'));
create policy "View inventory units" on public.inventory_units for select to authenticated using (deleted_at is null and public.has_organization_permission(organization_id,'inventory.view'));
create policy "Create inventory units" on public.inventory_units for insert to authenticated with check (public.has_organization_permission(organization_id,'inventory.create'));
create policy "Update inventory units" on public.inventory_units for update to authenticated using (public.has_organization_permission(organization_id,'inventory.update')) with check (public.has_organization_permission(organization_id,'inventory.update'));
create policy "Delete inventory units" on public.inventory_units for delete to authenticated using (public.has_organization_permission(organization_id,'inventory.delete'));
create policy "View pricing" on public.inventory_price_components for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage pricing" on public.inventory_price_components for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_pricing')) with check (public.has_organization_permission(organization_id,'inventory.manage_pricing'));
create policy "View payment plans" on public.project_payment_plans for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage payment plans" on public.project_payment_plans for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_pricing')) with check (public.has_organization_permission(organization_id,'inventory.manage_pricing'));
create policy "View milestones" on public.project_payment_plan_milestones for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage milestones" on public.project_payment_plan_milestones for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_pricing')) with check (public.has_organization_permission(organization_id,'inventory.manage_pricing'));
create policy "View documents" on public.inventory_documents for select to authenticated using (is_public=true or public.has_organization_permission(organization_id,'inventory.view'));
create policy "Manage documents" on public.inventory_documents for all to authenticated using (public.has_organization_permission(organization_id,'inventory.manage_documents')) with check (public.has_organization_permission(organization_id,'inventory.manage_documents'));
create policy "View inventory history" on public.inventory_unit_status_history for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "View reservations" on public.inventory_reservations for select to authenticated using (public.has_organization_permission(organization_id,'inventory.view'));
create policy "Create reservations" on public.inventory_reservations for insert to authenticated with check (public.has_organization_permission(organization_id,'inventory.reserve'));
create policy "Update reservations" on public.inventory_reservations for update to authenticated using (public.has_organization_permission(organization_id,'inventory.reserve') or public.has_organization_permission(organization_id,'inventory.release_reservation')) with check (public.has_organization_permission(organization_id,'inventory.reserve') or public.has_organization_permission(organization_id,'inventory.release_reservation'));
create policy "Delete reservations" on public.inventory_reservations for delete to authenticated using (public.has_organization_permission(organization_id,'inventory.release_reservation'));

commit;