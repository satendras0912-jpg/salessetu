-- ============================================================
-- SalesSetu Enterprise
-- Migration 032: Billing, Subscription & Licensing Engine
-- PostgreSQL / Supabase
-- ============================================================
-- SaaS billing control plane for catalog, plans, subscriptions,
-- entitlements, usage, quotas, invoicing, payments, refunds,
-- dunning, licensing and provider webhook orchestration.
--
-- Money fields ending in _minor use the smallest currency unit.
-- Provider secrets, mandate secrets and payment credentials are
-- stored only as external references.
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- 1. Permissions
insert into public.permissions(module,action,code,description)
select x.module,x.action,x.code,x.description
from (values
 ('billing','view','billing.view','View billing and licensing data'),
 ('billing','view_all','billing.view_all','View all organization billing data'),
 ('billing','manage_catalog','billing.manage_catalog','Manage products, plans and prices'),
 ('billing','manage_providers','billing.manage_providers','Manage billing provider accounts'),
 ('billing','manage_customers','billing.manage_customers','Manage billing customers and tax profiles'),
 ('billing','manage_subscriptions','billing.manage_subscriptions','Manage subscriptions and trials'),
 ('billing','manage_entitlements','billing.manage_entitlements','Manage entitlements, limits and quotas'),
 ('billing','record_usage','billing.record_usage','Record billable usage'),
 ('billing','manage_usage','billing.manage_usage','Manage usage meters and aggregation'),
 ('billing','manage_invoices','billing.manage_invoices','Manage invoices and invoice items'),
 ('billing','manage_payments','billing.manage_payments','Manage payments, allocations and refunds'),
 ('billing','manage_tax','billing.manage_tax','Manage tax registrations and rates'),
 ('billing','manage_discounts','billing.manage_discounts','Manage discounts and coupons'),
 ('billing','manage_credits','billing.manage_credits','Manage customer credit balances'),
 ('billing','manage_dunning','billing.manage_dunning','Manage payment recovery and dunning'),
 ('billing','manage_licenses','billing.manage_licenses','Manage license pools and assignments'),
 ('billing','manage_webhooks','billing.manage_webhooks','Manage provider webhook processing'),
 ('billing','view_sensitive','billing.view_sensitive','View sensitive billing references'),
 ('billing','view_logs','billing.view_logs','View billing engine logs and health'),
 ('billing','view_analytics','billing.view_analytics','View billing analytics')
) x(module,action,code,description)
where not exists(select 1 from public.permissions p where p.code=x.code);

-- 2. Providers
create table if not exists public.billing_providers(
 id uuid primary key default gen_random_uuid(),
 provider_code text not null unique,
 provider_name text not null,
 provider_type text not null check(provider_type in('payment_gateway','subscription_platform','invoice_platform','tax_platform','bank_transfer','manual','custom')),
 supports_subscriptions boolean not null default false,
 supports_invoices boolean not null default false,
 supports_payments boolean not null default true,
 supports_refunds boolean not null default true,
 supports_webhooks boolean not null default true,
 supports_usage_billing boolean not null default false,
 supported_currencies text[] not null default '{}',
 supported_countries text[] not null default '{}',
 status text not null default 'active' check(status in('active','inactive','deprecated','archived')),
 is_system_provider boolean not null default false,
 configuration_schema jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.billing_provider_accounts(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 provider_id uuid not null references public.billing_providers(id) on delete restrict,
 account_code text not null,
 account_name text not null,
 environment text not null default 'production' check(environment in('development','staging','production')),
 external_account_id text,
 public_identifier text,
 credential_reference text,
 webhook_secret_reference text,
 default_currency text not null default 'INR',
 default_country text not null default 'IN',
 status text not null default 'active' check(status in('active','inactive','verification_pending','restricted','error','revoked','archived')),
 last_verified_at timestamptz,
 last_webhook_at timestamptz,
 last_error_at timestamptz,
 last_error_message text,
 configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,account_code)
);
create index if not exists billing_provider_accounts_idx on public.billing_provider_accounts(organization_id,provider_id,status);

-- 3. Product catalog
create table if not exists public.billing_products(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 product_code text not null,
 product_name text not null,
 description text,
 product_type text not null default 'saas' check(product_type in('saas','service','implementation','support','marketplace','advertising','custom')),
 status text not null default 'active' check(status in('draft','active','inactive','retired','archived')),
 is_system_product boolean not null default false,
 tax_code text,
 sac_hsn_code text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_products_org_uidx on public.billing_products(organization_id,product_code) where organization_id is not null;
create unique index if not exists billing_products_system_uidx on public.billing_products(product_code) where organization_id is null;

create table if not exists public.billing_plans(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 product_id uuid not null references public.billing_products(id) on delete cascade,
 plan_code text not null,
 plan_name text not null,
 description text,
 plan_tier integer not null default 1,
 display_order integer not null default 100,
 plan_type text not null default 'standard' check(plan_type in('free','trial','standard','premium','enterprise','custom')),
 status text not null default 'active' check(status in('draft','active','inactive','retired','archived')),
 is_system_plan boolean not null default false,
 is_public boolean not null default true,
 requires_sales_approval boolean not null default false,
 default_trial_days integer not null default 0 check(default_trial_days>=0),
 minimum_quantity numeric(18,4) not null default 1,
 maximum_quantity numeric(18,4),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_plans_org_uidx on public.billing_plans(organization_id,product_id,plan_code) where organization_id is not null;
create unique index if not exists billing_plans_system_uidx on public.billing_plans(product_id,plan_code) where organization_id is null;
create index if not exists billing_plans_catalog_idx on public.billing_plans(product_id,status,display_order);

create table if not exists public.billing_plan_prices(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 plan_id uuid not null references public.billing_plans(id) on delete cascade,
 provider_id uuid references public.billing_providers(id) on delete set null,
 price_code text not null,
 price_name text not null,
 price_type text not null default 'flat' check(price_type in('flat','per_seat','metered','tiered','volume','package','custom')),
 billing_interval text not null default 'month' check(billing_interval in('day','week','month','quarter','year','one_time','custom')),
 interval_count integer not null default 1 check(interval_count>=1),
 currency text not null default 'INR',
 amount_minor bigint,
 setup_fee_minor bigint not null default 0,
 minimum_charge_minor bigint not null default 0,
 tax_inclusive boolean not null default false,
 is_custom_price boolean not null default false,
 external_price_id text,
 external_plan_id text,
 trial_days_override integer check(trial_days_override is null or trial_days_override>=0),
 valid_from timestamptz not null default now(),
 valid_until timestamptz,
 status text not null default 'active' check(status in('draft','active','inactive','expired','archived')),
 pricing_configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(is_custom_price=true or amount_minor is not null)
);
create unique index if not exists billing_plan_prices_org_uidx on public.billing_plan_prices(organization_id,plan_id,price_code) where organization_id is not null;
create unique index if not exists billing_plan_prices_system_uidx on public.billing_plan_prices(plan_id,price_code) where organization_id is null;
create index if not exists billing_plan_prices_active_idx on public.billing_plan_prices(plan_id,currency,billing_interval,status,valid_from);

-- 4. Add-ons
create table if not exists public.billing_addons(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 product_id uuid not null references public.billing_products(id) on delete cascade,
 addon_code text not null,
 addon_name text not null,
 description text,
 addon_type text not null default 'feature' check(addon_type in('feature','seat','usage_pack','service','support','implementation','custom')),
 quantity_unit text,
 minimum_quantity numeric(18,4) not null default 1,
 maximum_quantity numeric(18,4),
 status text not null default 'active' check(status in('draft','active','inactive','retired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_addons_org_uidx on public.billing_addons(organization_id,product_id,addon_code) where organization_id is not null;
create unique index if not exists billing_addons_system_uidx on public.billing_addons(product_id,addon_code) where organization_id is null;

create table if not exists public.billing_addon_prices(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 addon_id uuid not null references public.billing_addons(id) on delete cascade,
 provider_id uuid references public.billing_providers(id) on delete set null,
 price_code text not null,
 price_type text not null default 'flat' check(price_type in('flat','per_unit','tiered','volume','package','custom')),
 billing_interval text not null default 'month' check(billing_interval in('day','week','month','quarter','year','one_time','custom')),
 interval_count integer not null default 1,
 currency text not null default 'INR',
 amount_minor bigint,
 tax_inclusive boolean not null default false,
 is_custom_price boolean not null default false,
 external_price_id text,
 valid_from timestamptz not null default now(),
 valid_until timestamptz,
 status text not null default 'active' check(status in('draft','active','inactive','expired','archived')),
 pricing_configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(is_custom_price=true or amount_minor is not null)
);
create unique index if not exists billing_addon_prices_org_uidx on public.billing_addon_prices(organization_id,addon_id,price_code) where organization_id is not null;
create unique index if not exists billing_addon_prices_system_uidx on public.billing_addon_prices(addon_id,price_code) where organization_id is null;

-- 5. Entitlements
create table if not exists public.billing_entitlement_definitions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 entitlement_code text not null,
 entitlement_name text not null,
 description text,
 entitlement_type text not null check(entitlement_type in('feature','limit','quota','configuration','permission','support_level','custom')),
 value_type text not null default 'boolean' check(value_type in('boolean','integer','numeric','text','json')),
 unit text,
 reset_period text not null default 'none' check(reset_period in('none','daily','weekly','monthly','quarterly','annual','billing_period')),
 hard_limit_default boolean not null default true,
 status text not null default 'active' check(status in('active','inactive','deprecated','archived')),
 is_system_entitlement boolean not null default false,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_entitlement_org_uidx on public.billing_entitlement_definitions(organization_id,entitlement_code) where organization_id is not null;
create unique index if not exists billing_entitlement_system_uidx on public.billing_entitlement_definitions(entitlement_code) where organization_id is null;

create table if not exists public.billing_plan_entitlements(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 plan_id uuid not null references public.billing_plans(id) on delete cascade,
 entitlement_definition_id uuid not null references public.billing_entitlement_definitions(id) on delete cascade,
 enabled boolean not null default true,
 unlimited boolean not null default false,
 boolean_value boolean,
 integer_value bigint,
 numeric_value numeric(20,6),
 text_value text,
 json_value jsonb,
 hard_limit boolean,
 warning_threshold_percentage numeric(8,4) not null default 80 check(warning_threshold_percentage between 0 and 100),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(plan_id,entitlement_definition_id)
);

-- 6. Customers and payment methods
create table if not exists public.billing_customers(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 customer_code text not null,
 customer_name text not null,
 legal_name text,
 email text,
 phone text,
 customer_type text not null default 'organization' check(customer_type in('organization','individual','partner','reseller','internal','custom')),
 billing_email text,
 billing_phone text,
 currency text not null default 'INR',
 country_code text not null default 'IN',
 state_code text,
 billing_address jsonb not null default '{}',
 shipping_address jsonb not null default '{}',
 provider_account_id uuid references public.billing_provider_accounts(id) on delete set null,
 external_customer_id text,
 status text not null default 'active' check(status in('active','inactive','delinquent','suspended','closed','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,customer_code)
);
create index if not exists billing_customers_external_idx on public.billing_customers(provider_account_id,external_customer_id) where external_customer_id is not null;

create table if not exists public.billing_customer_tax_profiles(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 billing_customer_id uuid not null references public.billing_customers(id) on delete cascade,
 tax_country text not null default 'IN',
 tax_state text,
 gstin text,
 pan text,
 tax_registration_number text,
 tax_exempt boolean not null default false,
 reverse_charge_applicable boolean not null default false,
 exemption_reason text,
 tax_details jsonb not null default '{}',
 status text not null default 'active' check(status in('active','inactive','invalid','archived')),
 verified_at timestamptz,
 verified_by uuid references auth.users(id) on delete set null,
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(billing_customer_id,tax_country,tax_state)
);

create table if not exists public.billing_payment_methods(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 billing_customer_id uuid not null references public.billing_customers(id) on delete cascade,
 provider_account_id uuid references public.billing_provider_accounts(id) on delete set null,
 payment_method_code text not null,
 payment_method_type text not null check(payment_method_type in('card','upi','netbanking','bank_transfer','emandate','wallet','cash','cheque','manual','custom')),
 external_payment_method_id text,
 token_reference text,
 display_label text,
 masked_identifier text,
 is_default boolean not null default false,
 reusable boolean not null default false,
 mandate_status text check(mandate_status is null or mandate_status in('pending','active','paused','revoked','expired','failed')),
 status text not null default 'active' check(status in('active','inactive','expired','failed','revoked','archived')),
 expires_month integer,
 expires_year integer,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(billing_customer_id,payment_method_code)
);
create unique index if not exists billing_payment_methods_default_uidx on public.billing_payment_methods(billing_customer_id) where is_default=true and status='active';

-- 7. Subscriptions
create table if not exists public.billing_subscriptions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 billing_customer_id uuid not null references public.billing_customers(id) on delete restrict,
 product_id uuid not null references public.billing_products(id) on delete restrict,
 plan_id uuid not null references public.billing_plans(id) on delete restrict,
 plan_price_id uuid not null references public.billing_plan_prices(id) on delete restrict,
 provider_account_id uuid references public.billing_provider_accounts(id) on delete set null,
 subscription_code text not null,
 external_subscription_id text,
 status text not null default 'incomplete' check(status in('incomplete','trialing','active','past_due','grace','paused','suspended','cancelled','expired','failed','archived')),
 is_primary boolean not null default true,
 quantity numeric(18,4) not null default 1 check(quantity>0),
 currency text not null default 'INR',
 unit_amount_minor bigint,
 recurring_amount_minor bigint not null default 0,
 starts_at timestamptz not null default now(),
 trial_starts_at timestamptz,
 trial_ends_at timestamptz,
 current_period_start timestamptz not null,
 current_period_end timestamptz not null,
 next_billing_at timestamptz,
 grace_ends_at timestamptz,
 paused_at timestamptz,
 resumes_at timestamptz,
 cancel_at_period_end boolean not null default false,
 cancellation_requested_at timestamptz,
 cancelled_at timestamptz,
 cancellation_reason text,
 ended_at timestamptz,
 collection_method text not null default 'automatic' check(collection_method in('automatic','invoice','manual','partner','complimentary')),
 default_payment_method_id uuid references public.billing_payment_methods(id) on delete set null,
 tax_behavior text not null default 'exclusive' check(tax_behavior in('exclusive','inclusive','exempt','automatic')),
 purchase_order_reference text,
 contract_reference text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(current_period_end>current_period_start),
 unique(organization_id,subscription_code)
);
create unique index if not exists billing_subscriptions_external_uidx on public.billing_subscriptions(provider_account_id,external_subscription_id) where external_subscription_id is not null;
create unique index if not exists billing_subscriptions_primary_active_uidx on public.billing_subscriptions(organization_id) where is_primary=true and status in('incomplete','trialing','active','past_due','grace','paused','suspended');
create index if not exists billing_subscriptions_renewal_idx on public.billing_subscriptions(status,next_billing_at,current_period_end) where status in('trialing','active','past_due','grace');

create table if not exists public.billing_subscription_items(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
 item_code text not null,
 item_type text not null check(item_type in('base_plan','addon','seat','metered','service','discount','custom')),
 plan_price_id uuid references public.billing_plan_prices(id) on delete set null,
 addon_id uuid references public.billing_addons(id) on delete set null,
 addon_price_id uuid references public.billing_addon_prices(id) on delete set null,
 quantity numeric(18,4) not null default 1,
 unit_amount_minor bigint,
 recurring_amount_minor bigint not null default 0,
 currency text not null default 'INR',
 external_subscription_item_id text,
 starts_at timestamptz not null default now(),
 ends_at timestamptz,
 status text not null default 'active' check(status in('active','paused','cancelled','expired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(subscription_id,item_code)
);

create table if not exists public.billing_subscription_change_requests(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
 change_code text not null,
 change_type text not null check(change_type in('upgrade','downgrade','price_change','quantity_change','addon_add','addon_remove','pause','resume','cancel','reactivate','custom')),
 current_plan_id uuid references public.billing_plans(id) on delete set null,
 requested_plan_id uuid references public.billing_plans(id) on delete set null,
 requested_plan_price_id uuid references public.billing_plan_prices(id) on delete set null,
 current_quantity numeric(18,4),
 requested_quantity numeric(18,4),
 effective_mode text not null default 'period_end' check(effective_mode in('immediate','period_end','scheduled','manual')),
 effective_at timestamptz,
 proration_behavior text not null default 'create_prorations' check(proration_behavior in('create_prorations','none','invoice_immediately','credit_only','custom')),
 estimated_proration_minor bigint,
 status text not null default 'pending' check(status in('pending','approved','scheduled','processing','completed','rejected','cancelled','failed')),
 requested_by uuid references auth.users(id) on delete set null,
 approved_by uuid references auth.users(id) on delete set null,
 approved_at timestamptz,
 completed_at timestamptz,
 rejected_at timestamptz,
 rejection_reason text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(subscription_id,change_code)
);

create table if not exists public.billing_trials(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
 trial_code text not null,
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 status text not null default 'active' check(status in('scheduled','active','converted','expired','cancelled','extended','archived')),
 extension_count integer not null default 0,
 maximum_extension_days integer not null default 0,
 converted_at timestamptz,
 expired_at timestamptz,
 cancelled_at timestamptz,
 conversion_source text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(ends_at>starts_at),
 unique(subscription_id,trial_code)
);

create table if not exists public.billing_subscription_entitlement_overrides(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
 entitlement_definition_id uuid not null references public.billing_entitlement_definitions(id) on delete cascade,
 enabled boolean not null default true,
 unlimited boolean not null default false,
 boolean_value boolean,
 integer_value bigint,
 numeric_value numeric(20,6),
 text_value text,
 json_value jsonb,
 hard_limit boolean,
 warning_threshold_percentage numeric(8,4) check(warning_threshold_percentage is null or warning_threshold_percentage between 0 and 100),
 reason text,
 valid_from timestamptz not null default now(),
 valid_until timestamptz,
 status text not null default 'active' check(status in('active','inactive','expired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(subscription_id,entitlement_definition_id)
);
-- 8. Usage metering and quota enforcement
create table if not exists public.billing_usage_meter_definitions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 product_id uuid references public.billing_products(id) on delete cascade,
 entitlement_definition_id uuid references public.billing_entitlement_definitions(id) on delete set null,
 meter_code text not null,
 meter_name text not null,
 description text,
 event_name text not null,
 quantity_field text,
 aggregation_method text not null default 'sum' check(aggregation_method in('sum','count','maximum','minimum','last','unique_count','custom')),
 unit text not null,
 reset_period text not null default 'billing_period' check(reset_period in('none','daily','weekly','monthly','quarterly','annual','billing_period')),
 included_quantity numeric(20,6) not null default 0,
 overage_price_minor bigint,
 overage_package_size numeric(20,6) not null default 1,
 allow_negative_corrections boolean not null default true,
 status text not null default 'active' check(status in('draft','active','inactive','deprecated','archived')),
 is_system_meter boolean not null default false,
 dimensions_schema jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_usage_meter_org_uidx on public.billing_usage_meter_definitions(organization_id,meter_code) where organization_id is not null;
create unique index if not exists billing_usage_meter_system_uidx on public.billing_usage_meter_definitions(meter_code) where organization_id is null;

create table if not exists public.billing_usage_events(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 billing_customer_id uuid references public.billing_customers(id) on delete set null,
 subscription_id uuid references public.billing_subscriptions(id) on delete set null,
 meter_definition_id uuid not null references public.billing_usage_meter_definitions(id) on delete restrict,
 event_id text not null,
 event_name text not null,
 quantity numeric(20,6) not null default 1,
 dimension_key text,
 dimensions jsonb not null default '{}',
 event_data jsonb not null default '{}',
 source_type text,
 source_id uuid,
 occurred_at timestamptz not null default now(),
 received_at timestamptz not null default now(),
 billing_period_start timestamptz,
 billing_period_end timestamptz,
 correction_of_event_id uuid references public.billing_usage_events(id) on delete set null,
 status text not null default 'accepted' check(status in('accepted','aggregated','invoiced','rejected','corrected','cancelled')),
 rejection_reason text,
 idempotency_key text,
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(organization_id,event_id)
);
create unique index if not exists billing_usage_events_idem_uidx on public.billing_usage_events(organization_id,idempotency_key) where idempotency_key is not null;
create index if not exists billing_usage_events_agg_idx on public.billing_usage_events(organization_id,subscription_id,meter_definition_id,occurred_at) where status in('accepted','aggregated');

create table if not exists public.billing_usage_aggregates(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
 meter_definition_id uuid not null references public.billing_usage_meter_definitions(id) on delete cascade,
 period_start timestamptz not null,
 period_end timestamptz not null,
 aggregated_quantity numeric(20,6) not null default 0,
 included_quantity numeric(20,6) not null default 0,
 billable_quantity numeric(20,6) generated always as(greatest(aggregated_quantity-included_quantity,0)) stored,
 estimated_charge_minor bigint not null default 0,
 aggregation_method text not null,
 event_count bigint not null default 0,
 status text not null default 'open' check(status in('open','finalized','invoiced','adjusted','cancelled')),
 finalized_at timestamptz,
 invoiced_at timestamptz,
 calculation_data jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(period_end>period_start),
 unique(subscription_id,meter_definition_id,period_start,period_end)
);

create table if not exists public.billing_quota_counters(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
 entitlement_definition_id uuid not null references public.billing_entitlement_definitions(id) on delete cascade,
 period_start timestamptz not null,
 period_end timestamptz not null,
 allowed_quantity numeric(20,6),
 consumed_quantity numeric(20,6) not null default 0,
 reserved_quantity numeric(20,6) not null default 0,
 remaining_quantity numeric(20,6) generated always as(case when allowed_quantity is null then null else greatest(allowed_quantity-consumed_quantity-reserved_quantity,0) end) stored,
 unlimited boolean not null default false,
 hard_limit boolean not null default true,
 warning_threshold_percentage numeric(8,4) not null default 80,
 warning_emitted_at timestamptz,
 exhausted_at timestamptz,
 last_consumed_at timestamptz,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check(period_end>period_start),
 unique(subscription_id,entitlement_definition_id,period_start,period_end)
);
create index if not exists billing_quota_counters_active_idx on public.billing_quota_counters(organization_id,subscription_id,period_end);

-- 9. Tax
create table if not exists public.billing_tax_registrations(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 registration_code text not null,
 legal_name text not null,
 country_code text not null default 'IN',
 state_code text,
 registration_type text not null check(registration_type in('gst','vat','sales_tax','service_tax','income_tax','custom')),
 registration_number text not null,
 effective_from date not null default current_date,
 effective_until date,
 invoice_prefix text,
 status text not null default 'active' check(status in('active','inactive','expired','cancelled','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,registration_code)
);

create table if not exists public.billing_tax_rates(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 tax_code text not null,
 tax_name text not null,
 country_code text not null default 'IN',
 state_code text,
 tax_type text not null check(tax_type in('cgst','sgst','igst','cess','vat','sales_tax','withholding','custom')),
 rate_percentage numeric(9,6) not null check(rate_percentage>=0),
 compound boolean not null default false,
 inclusive boolean not null default false,
 applies_to_product_types text[] not null default '{}',
 applies_to_tax_codes text[] not null default '{}',
 effective_from date not null default current_date,
 effective_until date,
 status text not null default 'active' check(status in('active','inactive','expired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_tax_rates_org_uidx on public.billing_tax_rates(organization_id,tax_code,effective_from) where organization_id is not null;
create unique index if not exists billing_tax_rates_system_uidx on public.billing_tax_rates(tax_code,effective_from) where organization_id is null;

-- 10. Discounts and coupons
create table if not exists public.billing_discounts(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 discount_code text not null,
 discount_name text not null,
 description text,
 discount_type text not null check(discount_type in('percentage','fixed_amount','free_period','credit','custom')),
 percentage_value numeric(9,6),
 fixed_amount_minor bigint,
 free_period_days integer,
 currency text default 'INR',
 duration_type text not null default 'once' check(duration_type in('once','repeating','forever','custom')),
 duration_cycles integer,
 maximum_redemptions integer,
 maximum_redemptions_per_customer integer not null default 1,
 minimum_invoice_amount_minor bigint,
 valid_from timestamptz not null default now(),
 valid_until timestamptz,
 applicable_plan_ids uuid[] not null default '{}',
 applicable_product_ids uuid[] not null default '{}',
 status text not null default 'active' check(status in('draft','active','paused','expired','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_discounts_org_uidx on public.billing_discounts(organization_id,discount_code) where organization_id is not null;
create unique index if not exists billing_discounts_system_uidx on public.billing_discounts(discount_code) where organization_id is null;

create table if not exists public.billing_coupons(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 discount_id uuid not null references public.billing_discounts(id) on delete cascade,
 coupon_code text not null,
 provider_id uuid references public.billing_providers(id) on delete set null,
 external_coupon_id text,
 maximum_redemptions integer,
 redemption_count integer not null default 0,
 valid_from timestamptz not null default now(),
 valid_until timestamptz,
 status text not null default 'active' check(status in('active','paused','expired','exhausted','archived')),
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_coupons_org_uidx on public.billing_coupons(organization_id,coupon_code) where organization_id is not null;
create unique index if not exists billing_coupons_system_uidx on public.billing_coupons(coupon_code) where organization_id is null;

create table if not exists public.billing_coupon_redemptions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 coupon_id uuid not null references public.billing_coupons(id) on delete restrict,
 billing_customer_id uuid not null references public.billing_customers(id) on delete cascade,
 subscription_id uuid references public.billing_subscriptions(id) on delete set null,
 redemption_code text not null,
 status text not null default 'active' check(status in('active','consumed','cancelled','expired','archived')),
 redeemed_at timestamptz not null default now(),
 consumed_at timestamptz,
 cancelled_at timestamptz,
 remaining_cycles integer,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(organization_id,redemption_code)
);

-- 11. Credits
create table if not exists public.billing_credit_accounts(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 billing_customer_id uuid not null references public.billing_customers(id) on delete cascade,
 currency text not null default 'INR',
 balance_minor bigint not null default 0,
 reserved_minor bigint not null default 0,
 available_minor bigint generated always as(greatest(balance_minor-reserved_minor,0)) stored,
 status text not null default 'active' check(status in('active','frozen','closed','archived')),
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(billing_customer_id,currency)
);

create table if not exists public.billing_credit_transactions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 credit_account_id uuid not null references public.billing_credit_accounts(id) on delete cascade,
 transaction_code text not null,
 transaction_type text not null check(transaction_type in('grant','adjustment','invoice_application','refund_credit','promotional_credit','expiration','reversal','reservation','reservation_release','custom')),
 amount_minor bigint not null,
 balance_before_minor bigint,
 balance_after_minor bigint,
 related_entity_type text,
 related_entity_id uuid,
 expires_at timestamptz,
 notes text,
 idempotency_key text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(organization_id,transaction_code)
);
create unique index if not exists billing_credit_txn_idem_uidx on public.billing_credit_transactions(organization_id,idempotency_key) where idempotency_key is not null;

-- 12. Invoices
create table if not exists public.billing_invoices(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 billing_customer_id uuid not null references public.billing_customers(id) on delete restrict,
 subscription_id uuid references public.billing_subscriptions(id) on delete set null,
 provider_account_id uuid references public.billing_provider_accounts(id) on delete set null,
 invoice_number text not null,
 external_invoice_id text,
 invoice_type text not null default 'subscription' check(invoice_type in('subscription','usage','one_time','setup_fee','renewal','proration','credit_note','debit_note','proforma','manual','custom')),
 currency text not null default 'INR',
 subtotal_minor bigint not null default 0,
 discount_minor bigint not null default 0,
 taxable_minor bigint not null default 0,
 tax_minor bigint not null default 0,
 credit_applied_minor bigint not null default 0,
 total_minor bigint not null default 0,
 paid_minor bigint not null default 0,
 refunded_minor bigint not null default 0,
 outstanding_minor bigint generated always as(greatest(total_minor-paid_minor-credit_applied_minor,0)) stored,
 status text not null default 'draft' check(status in('draft','open','issued','sent','partially_paid','paid','past_due','uncollectible','void','cancelled','refunded','archived')),
 billing_period_start timestamptz,
 billing_period_end timestamptz,
 invoice_date date not null default current_date,
 due_date date,
 tax_behavior text not null default 'exclusive' check(tax_behavior in('exclusive','inclusive','exempt','automatic')),
 tax_registration_id uuid references public.billing_tax_registrations(id) on delete set null,
 coupon_redemption_id uuid references public.billing_coupon_redemptions(id) on delete set null,
 finance_invoice_id uuid references public.finance_invoices(id) on delete set null,
 document_id uuid references public.documents(id) on delete set null,
 finalized_at timestamptz,
 issued_at timestamptz,
 sent_at timestamptz,
 paid_at timestamptz,
 voided_at timestamptz,
 collection_attempt_count integer not null default 0,
 next_collection_attempt_at timestamptz,
 billing_details jsonb not null default '{}',
 tax_details jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,invoice_number)
);
create unique index if not exists billing_invoices_external_uidx on public.billing_invoices(provider_account_id,external_invoice_id) where external_invoice_id is not null;
create index if not exists billing_invoices_collection_idx on public.billing_invoices(organization_id,status,due_date,next_collection_attempt_at) where status in('open','issued','sent','partially_paid','past_due');

create table if not exists public.billing_invoice_items(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 invoice_id uuid not null references public.billing_invoices(id) on delete cascade,
 line_number integer not null,
 item_type text not null default 'subscription' check(item_type in('subscription','addon','seat','usage','setup_fee','service','proration','discount','credit','tax','adjustment','custom')),
 item_code text,
 description text not null,
 subscription_item_id uuid references public.billing_subscription_items(id) on delete set null,
 usage_aggregate_id uuid references public.billing_usage_aggregates(id) on delete set null,
 quantity numeric(20,6) not null default 1,
 unit_amount_minor bigint not null default 0,
 gross_amount_minor bigint not null default 0,
 discount_minor bigint not null default 0,
 taxable_minor bigint not null default 0,
 tax_minor bigint not null default 0,
 line_total_minor bigint not null default 0,
 tax_rate_percentage numeric(9,6),
 period_start timestamptz,
 period_end timestamptz,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 unique(invoice_id,line_number)
);
create index if not exists billing_invoice_items_idx on public.billing_invoice_items(invoice_id,line_number);

-- 13. Payments and refunds
create table if not exists public.billing_payments(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 billing_customer_id uuid not null references public.billing_customers(id) on delete restrict,
 provider_account_id uuid references public.billing_provider_accounts(id) on delete set null,
 payment_method_id uuid references public.billing_payment_methods(id) on delete set null,
 payment_code text not null,
 external_payment_id text,
 external_order_id text,
 external_signature_reference text,
 payment_type text not null default 'invoice' check(payment_type in('invoice','subscription','advance','deposit','manual','credit_topup','custom')),
 amount_minor bigint not null check(amount_minor>=0),
 currency text not null default 'INR',
 payment_method_type text,
 status text not null default 'pending' check(status in('created','pending','authorized','captured','succeeded','partially_refunded','refunded','failed','cancelled','reversed','disputed','archived')),
 failure_code text,
 failure_message text,
 received_at timestamptz,
 authorized_at timestamptz,
 captured_at timestamptz,
 failed_at timestamptz,
 reversed_at timestamptz,
 reconciled boolean not null default false,
 reconciled_at timestamptz,
 finance_receipt_id uuid references public.finance_payment_receipts(id) on delete set null,
 idempotency_key text,
 correlation_id text,
 trace_id text,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,payment_code)
);
create unique index if not exists billing_payments_external_uidx on public.billing_payments(provider_account_id,external_payment_id) where external_payment_id is not null;
create unique index if not exists billing_payments_idem_uidx on public.billing_payments(organization_id,idempotency_key) where idempotency_key is not null;

create table if not exists public.billing_payment_allocations(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 payment_id uuid not null references public.billing_payments(id) on delete cascade,
 invoice_id uuid not null references public.billing_invoices(id) on delete cascade,
 allocated_minor bigint not null check(allocated_minor>0),
 allocation_type text not null default 'payment' check(allocation_type in('payment','advance','adjustment','reversal','custom')),
 allocated_at timestamptz not null default now(),
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(payment_id,invoice_id,allocation_type)
);

create table if not exists public.billing_refunds(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 payment_id uuid not null references public.billing_payments(id) on delete restrict,
 invoice_id uuid references public.billing_invoices(id) on delete set null,
 refund_code text not null,
 external_refund_id text,
 amount_minor bigint not null check(amount_minor>0),
 currency text not null default 'INR',
 status text not null default 'pending' check(status in('pending','processing','succeeded','failed','cancelled','reversed','archived')),
 reason text,
 requested_by uuid references auth.users(id) on delete set null,
 approved_by uuid references auth.users(id) on delete set null,
 requested_at timestamptz not null default now(),
 approved_at timestamptz,
 processed_at timestamptz,
 failed_at timestamptz,
 failure_code text,
 failure_message text,
 metadata jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,refund_code)
);
create unique index if not exists billing_refunds_external_uidx on public.billing_refunds(external_refund_id) where external_refund_id is not null;

-- 14. Dunning
create table if not exists public.billing_dunning_policies(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 policy_code text not null,
 policy_name text not null,
 description text,
 grace_period_days integer not null default 3,
 maximum_attempts integer not null default 4,
 retry_schedule_days integer[] not null default array[1,3,5,7],
 suspend_after_days integer,
 cancel_after_days integer,
 send_reminders boolean not null default true,
 reminder_channels text[] not null default array['email','whatsapp','in_app']::text[],
 allow_manual_override boolean not null default true,
 status text not null default 'active' check(status in('draft','active','inactive','archived')),
 configuration jsonb not null default '{}',
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,policy_code)
);

create table if not exists public.billing_dunning_cases(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 dunning_policy_id uuid references public.billing_dunning_policies(id) on delete set null,
 billing_customer_id uuid not null references public.billing_customers(id) on delete cascade,
 subscription_id uuid references public.billing_subscriptions(id) on delete set null,
 invoice_id uuid not null references public.billing_invoices(id) on delete cascade,
 case_code text not null,
 status text not null default 'open' check(status in('open','retrying','grace','resolved','suspended','cancelled','written_off','archived')),
 attempt_count integer not null default 0,
 next_attempt_at timestamptz,
 opened_at timestamptz not null default now(),
 grace_ends_at timestamptz,
 resolved_at timestamptz,
 suspended_at timestamptz,
 cancelled_at timestamptz,
 resolution_type text,
 resolution_notes text,
 workflow_instance_id uuid references public.enterprise_workflow_instances(id) on delete set null,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,case_code)
);
create index if not exists billing_dunning_cases_due_idx on public.billing_dunning_cases(organization_id,status,next_attempt_at) where status in('open','retrying','grace');

create table if not exists public.billing_dunning_attempts(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 dunning_case_id uuid not null references public.billing_dunning_cases(id) on delete cascade,
 attempt_number integer not null,
 attempt_type text not null check(attempt_type in('payment_retry','email','whatsapp','sms','in_app','phone_call','manual','custom')),
 status text not null default 'scheduled' check(status in('scheduled','processing','succeeded','failed','cancelled','skipped')),
 scheduled_at timestamptz,
 started_at timestamptz,
 completed_at timestamptz,
 payment_id uuid references public.billing_payments(id) on delete set null,
 result_data jsonb not null default '{}',
 error_code text,
 error_message text,
 created_at timestamptz not null default now(),
 unique(dunning_case_id,attempt_number,attempt_type)
);

-- 15. License pools and assignments
create table if not exists public.billing_license_pools(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 subscription_id uuid not null references public.billing_subscriptions(id) on delete cascade,
 license_code text not null,
 license_name text not null,
 license_type text not null default 'user_seat' check(license_type in('tenant','user_seat','agent_seat','manager_seat','api_client','branch','project','custom')),
 allocated_quantity integer,
 unlimited boolean not null default false,
 assigned_quantity integer not null default 0,
 available_quantity integer generated always as(case when unlimited then null when allocated_quantity is null then 0 else greatest(allocated_quantity-assigned_quantity,0) end) stored,
 status text not null default 'active' check(status in('active','suspended','expired','cancelled','archived')),
 starts_at timestamptz not null default now(),
 ends_at timestamptz,
 metadata jsonb not null default '{}',
 created_by uuid references auth.users(id) on delete set null,
 updated_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(subscription_id,license_code)
);

create table if not exists public.billing_license_assignments(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.organizations(id) on delete cascade,
 license_pool_id uuid not null references public.billing_license_pools(id) on delete cascade,
 assignment_code text not null,
 assignee_type text not null check(assignee_type in('user','service_account','api_client','branch','project','custom')),
 user_id uuid references auth.users(id) on delete cascade,
 assignee_reference text,
 status text not null default 'active' check(status in('active','suspended','revoked','expired','archived')),
 assigned_at timestamptz not null default now(),
 expires_at timestamptz,
 revoked_at timestamptz,
 revoked_by uuid references auth.users(id) on delete set null,
 revocation_reason text,
 last_used_at timestamptz,
 metadata jsonb not null default '{}',
 assigned_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organization_id,assignment_code)
);
create unique index if not exists billing_license_assignments_user_uidx on public.billing_license_assignments(license_pool_id,user_id) where user_id is not null and status='active';

-- 16. Provider webhooks
create table if not exists public.billing_webhook_inbox(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 provider_id uuid not null references public.billing_providers(id) on delete restrict,
 provider_account_id uuid references public.billing_provider_accounts(id) on delete set null,
 provider_event_id text not null,
 event_type text not null,
 payload jsonb not null default '{}',
 headers jsonb not null default '{}',
 signature_valid boolean,
 signature_validation_error text,
 status text not null default 'received' check(status in('received','validated','processing','processed','ignored','failed','dead_lettered')),
 processing_attempts integer not null default 0,
 maximum_attempts integer not null default 10,
 available_at timestamptz not null default now(),
 claimed_at timestamptz,
 claimed_by text,
 lock_token text,
 lock_expires_at timestamptz,
 processed_at timestamptz,
 last_error_code text,
 last_error_message text,
 last_error_data jsonb not null default '{}',
 correlation_id text,
 trace_id text,
 received_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(provider_id,provider_event_id)
);
create index if not exists billing_webhook_worker_idx on public.billing_webhook_inbox(status,available_at,received_at) where status in('received','validated','failed');

-- 17. Event outbox and logs
create table if not exists public.billing_event_outbox(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete cascade,
 event_name text not null,
 source_type text,
 source_id uuid,
 destination text not null default 'internal' check(destination in('internal','automation_engine','enterprise_workflow','communication_engine','notification_engine','integration_api','ai_intelligence','reporting','mobile','security_governance','observability','finance','n8n','analytics','audit','webhook')),
 status text not null default 'pending' check(status in('pending','claimed','processing','delivered','failed','cancelled','dead_lettered')),
 priority integer not null default 100,
 idempotency_key text,
 correlation_id text,
 trace_id text,
 payload jsonb not null default '{}',
 available_at timestamptz not null default now(),
 delivery_attempts integer not null default 0,
 maximum_attempts integer not null default 10,
 delivered_at timestamptz,
 last_error_code text,
 last_error_message text,
 last_error_data jsonb not null default '{}',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create unique index if not exists billing_outbox_idem_uidx on public.billing_event_outbox(organization_id,idempotency_key) where idempotency_key is not null;

create table if not exists public.billing_logs(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid references public.organizations(id) on delete set null,
 log_level text not null default 'info' check(log_level in('debug','info','warning','error','critical')),
 event_name text,
 message text,
 source_type text,
 source_id uuid,
 actor_user_id uuid references auth.users(id) on delete set null,
 error_code text,
 error_message text,
 log_data jsonb not null default '{}',
 correlation_id text,
 trace_id text,
 created_at timestamptz not null default now()
);
create index if not exists billing_logs_org_time_idx on public.billing_logs(organization_id,created_at desc);
-- 18. Updated-at triggers
do $$
declare t text;
begin
 foreach t in array array[
  'billing_providers','billing_provider_accounts','billing_products','billing_plans','billing_plan_prices',
  'billing_addons','billing_addon_prices','billing_entitlement_definitions','billing_plan_entitlements',
  'billing_customers','billing_customer_tax_profiles','billing_payment_methods','billing_subscriptions',
  'billing_subscription_items','billing_subscription_change_requests','billing_trials',
  'billing_subscription_entitlement_overrides','billing_usage_meter_definitions','billing_usage_aggregates',
  'billing_quota_counters','billing_tax_registrations','billing_tax_rates','billing_discounts','billing_coupons',
  'billing_credit_accounts','billing_invoices','billing_payments','billing_refunds','billing_dunning_policies',
  'billing_dunning_cases','billing_license_pools','billing_license_assignments','billing_webhook_inbox',
  'billing_event_outbox'
 ] loop
  execute format('drop trigger if exists %I_set_updated_at on public.%I',t,t);
  execute format('create trigger %I_set_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
 end loop;
end $$;

-- 19. Billing-period helper
create or replace function public.calculate_billing_period_end(p_start timestamptz,p_interval text,p_count integer default 1)
returns timestamptz language plpgsql immutable set search_path='' as $$
begin
 return case p_interval
  when 'day' then p_start+make_interval(days=>greatest(p_count,1))
  when 'week' then p_start+make_interval(days=>greatest(p_count,1)*7)
  when 'month' then p_start+make_interval(months=>greatest(p_count,1))
  when 'quarter' then p_start+make_interval(months=>greatest(p_count,1)*3)
  when 'year' then p_start+make_interval(years=>greatest(p_count,1))
  when 'one_time' then p_start+interval '100 years'
  else p_start+make_interval(months=>greatest(p_count,1))
 end;
end $$;

-- 20. Event publisher
create or replace function public.publish_billing_event(
 p_org uuid,p_event text,p_payload jsonb default '{}',p_destination text default 'internal',
 p_source_type text default null,p_source_id uuid default null,p_priority integer default 100,
 p_idempotency_key text default null,p_correlation_id text default null,p_trace_id text default null,
 p_available_at timestamptz default now()
) returns public.billing_event_outbox
language plpgsql security definer set search_path='' as $$
declare e public.billing_event_outbox;
begin
 if p_idempotency_key is not null then
  select * into e from public.billing_event_outbox
  where organization_id is not distinct from p_org and idempotency_key=p_idempotency_key limit 1;
  if found then return e; end if;
 end if;
 insert into public.billing_event_outbox(
  organization_id,event_name,source_type,source_id,destination,status,priority,idempotency_key,
  correlation_id,trace_id,payload,available_at
 ) values(
  p_org,p_event,p_source_type,p_source_id,p_destination,'pending',p_priority,p_idempotency_key,
  p_correlation_id,p_trace_id,coalesce(p_payload,'{}'),coalesce(p_available_at,now())
 ) returning * into e;
 return e;
end $$;

-- 21. Sync billing subscription to Administration Engine
create or replace function public.sync_billing_subscription_license(p_subscription_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.billing_subscriptions; p public.billing_plans; pe record; license_status text; v_limit numeric;
begin
 select * into s from public.billing_subscriptions where id=p_subscription_id;
 if not found then raise exception 'Subscription not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(s.organization_id,'billing.manage_subscriptions') then raise exception 'Permission denied'; end if;
 select * into p from public.billing_plans where id=s.plan_id;
 if not found then raise exception 'Plan not found'; end if;

 license_status:=case s.status
  when 'trialing' then 'trial' when 'active' then 'active'
  when 'past_due' then 'grace' when 'grace' then 'grace'
  when 'paused' then 'suspended' when 'suspended' then 'suspended'
  when 'cancelled' then 'cancelled' when 'expired' then 'expired'
  else 'trial' end;

 insert into public.admin_licenses(
  organization_id,license_code,plan_code,plan_name,status,starts_at,trial_ends_at,renews_at,
  expires_at,cancelled_at,billing_cycle,metadata
 ) values(
  s.organization_id,case when s.is_primary then 'PRIMARY' else 'SUB-'||s.id::text end,
  p.plan_code,p.plan_name,license_status,s.starts_at,s.trial_ends_at,s.next_billing_at,s.ended_at,
  s.cancelled_at,case (select billing_interval from public.billing_plan_prices where id=s.plan_price_id)
   when 'month' then 'monthly' when 'quarter' then 'quarterly' when 'year' then 'annual' else 'custom' end,
  jsonb_build_object('billing_subscription_id',s.id,'is_primary',s.is_primary,'synced_at',now())
 ) on conflict(organization_id,license_code) do update set
  plan_code=excluded.plan_code,plan_name=excluded.plan_name,status=excluded.status,starts_at=excluded.starts_at,
  trial_ends_at=excluded.trial_ends_at,renews_at=excluded.renews_at,expires_at=excluded.expires_at,
  cancelled_at=excluded.cancelled_at,billing_cycle=excluded.billing_cycle,
  metadata=public.admin_licenses.metadata||excluded.metadata,updated_at=now();

 for pe in
  select d.entitlement_code,d.entitlement_name,d.reset_period,e.unlimited,e.integer_value,e.numeric_value,
         coalesce(e.hard_limit,d.hard_limit_default) hard_limit,e.warning_threshold_percentage
  from public.billing_plan_entitlements e join public.billing_entitlement_definitions d on d.id=e.entitlement_definition_id
  where e.plan_id=s.plan_id and e.enabled and d.entitlement_type in('limit','quota')
 loop
  v_limit:=case when pe.unlimited then null else coalesce(pe.numeric_value,pe.integer_value::numeric) end;
  insert into public.admin_tenant_limits(
   organization_id,limit_code,limit_name,limit_value,current_usage,period_type,hard_limit,
   warning_threshold_percentage,status,metadata
  ) values(
   s.organization_id,pe.entitlement_code,pe.entitlement_name,v_limit,0,
   case pe.reset_period when 'daily' then 'daily' when 'weekly' then 'weekly'
    when 'monthly' then 'monthly' when 'annual' then 'annual' when 'billing_period' then 'monthly'
    else 'lifetime' end,
   pe.hard_limit,pe.warning_threshold_percentage,'active',
   jsonb_build_object('billing_subscription_id',s.id,'unlimited',pe.unlimited,'synced_at',now())
  ) on conflict(organization_id,limit_code) do update set
   limit_name=excluded.limit_name,limit_value=excluded.limit_value,period_type=excluded.period_type,
   hard_limit=excluded.hard_limit,warning_threshold_percentage=excluded.warning_threshold_percentage,
   status='active',metadata=public.admin_tenant_limits.metadata||excluded.metadata,updated_at=now();
 end loop;

 -- Maintain user-seat pool from the "users" entitlement.
 select d.entitlement_code,d.entitlement_name,e.unlimited,e.integer_value
 into pe
 from public.billing_plan_entitlements e join public.billing_entitlement_definitions d on d.id=e.entitlement_definition_id
 where e.plan_id=s.plan_id and d.entitlement_code='users' and e.enabled limit 1;
 if found then
  insert into public.billing_license_pools(
   organization_id,subscription_id,license_code,license_name,license_type,allocated_quantity,unlimited,status,
   starts_at,ends_at,metadata,created_by,updated_by
  ) values(
   s.organization_id,s.id,'USERS','SalesSetu user seats','user_seat',
   case when pe.unlimited then null else pe.integer_value::integer end,pe.unlimited,
   case when s.status in('trialing','active','past_due','grace') then 'active' else 'suspended' end,
   s.starts_at,s.ended_at,jsonb_build_object('synced_from_plan',p.plan_code),auth.uid(),auth.uid()
  ) on conflict(subscription_id,license_code) do update set
   allocated_quantity=excluded.allocated_quantity,unlimited=excluded.unlimited,status=excluded.status,
   ends_at=excluded.ends_at,metadata=public.billing_license_pools.metadata||excluded.metadata,
   updated_by=auth.uid(),updated_at=now();
 end if;

 return jsonb_build_object('subscription_id',s.id,'organization_id',s.organization_id,'plan_code',p.plan_code,'license_status',license_status,'synced_at',now());
end $$;

-- 22. Provider account
create or replace function public.register_billing_provider_account(
 p_org uuid,p_provider_code text,p_account_code text,p_account_name text,p_environment text default 'production',
 p_external_account_id text default null,p_public_identifier text default null,p_credential_reference text default null,
 p_webhook_secret_reference text default null,p_currency text default 'INR',p_configuration jsonb default '{}',
 p_metadata jsonb default '{}'
) returns public.billing_provider_accounts
language plpgsql security definer set search_path='' as $$
declare prov public.billing_providers; a public.billing_provider_accounts;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.manage_providers') then raise exception 'Permission denied'; end if;
 select * into prov from public.billing_providers where provider_code=p_provider_code and status='active';
 if not found then raise exception 'Active provider not found'; end if;
 insert into public.billing_provider_accounts(
  organization_id,provider_id,account_code,account_name,environment,external_account_id,public_identifier,
  credential_reference,webhook_secret_reference,default_currency,status,configuration,metadata,created_by,updated_by
 ) values(
  p_org,prov.id,p_account_code,p_account_name,p_environment,p_external_account_id,p_public_identifier,
  p_credential_reference,p_webhook_secret_reference,p_currency,'active',coalesce(p_configuration,'{}'),
  coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) on conflict(organization_id,account_code) do update set
  provider_id=excluded.provider_id,account_name=excluded.account_name,environment=excluded.environment,
  external_account_id=excluded.external_account_id,public_identifier=excluded.public_identifier,
  credential_reference=excluded.credential_reference,webhook_secret_reference=excluded.webhook_secret_reference,
  default_currency=excluded.default_currency,configuration=excluded.configuration,metadata=excluded.metadata,
  updated_by=auth.uid(),updated_at=now()
 returning * into a;
 return a;
end $$;

-- 23. Billing customer
create or replace function public.create_billing_customer(
 p_org uuid,p_name text,p_email text default null,p_phone text default null,p_legal_name text default null,
 p_billing_email text default null,p_billing_phone text default null,p_currency text default 'INR',
 p_country text default 'IN',p_state text default null,p_address jsonb default '{}',
 p_provider_account_id uuid default null,p_external_customer_id text default null,p_metadata jsonb default '{}'
) returns public.billing_customers
language plpgsql security definer set search_path='' as $$
declare c public.billing_customers;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.manage_customers') then raise exception 'Permission denied'; end if;
 insert into public.billing_customers(
  organization_id,customer_code,customer_name,legal_name,email,phone,billing_email,billing_phone,currency,
  country_code,state_code,billing_address,provider_account_id,external_customer_id,status,metadata,created_by,updated_by
 ) values(
  p_org,'CUS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),p_name,p_legal_name,p_email,p_phone,
  coalesce(p_billing_email,p_email),coalesce(p_billing_phone,p_phone),p_currency,p_country,p_state,coalesce(p_address,'{}'),
  p_provider_account_id,p_external_customer_id,'active',coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) returning * into c;
 return c;
end $$;

-- 24. Catalog functions
create or replace function public.create_billing_product(
 p_org uuid,p_code text,p_name text,p_type text default 'saas',p_description text default null,
 p_tax_code text default null,p_sac_hsn text default null,p_metadata jsonb default '{}'
) returns public.billing_products
language plpgsql security definer set search_path='' as $$
declare r public.billing_products;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.manage_catalog') then raise exception 'Permission denied'; end if;
 insert into public.billing_products(organization_id,product_code,product_name,description,product_type,status,tax_code,sac_hsn_code,metadata,created_by,updated_by)
 values(p_org,p_code,p_name,p_description,p_type,'active',p_tax_code,p_sac_hsn,coalesce(p_metadata,'{}'),auth.uid(),auth.uid())
 on conflict(organization_id,product_code) where organization_id is not null do update set
  product_name=excluded.product_name,description=excluded.description,product_type=excluded.product_type,
  tax_code=excluded.tax_code,sac_hsn_code=excluded.sac_hsn_code,metadata=excluded.metadata,updated_by=auth.uid(),updated_at=now()
 returning * into r;
 return r;
end $$;

create or replace function public.create_billing_plan(
 p_org uuid,p_product uuid,p_code text,p_name text,p_type text default 'standard',p_description text default null,
 p_tier integer default 1,p_order integer default 100,p_trial_days integer default 0,p_public boolean default true,
 p_sales_approval boolean default false,p_metadata jsonb default '{}'
) returns public.billing_plans
language plpgsql security definer set search_path='' as $$
declare r public.billing_plans;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.manage_catalog') then raise exception 'Permission denied'; end if;
 if not exists(select 1 from public.billing_products where id=p_product and (organization_id is null or organization_id=p_org)) then raise exception 'Product not available'; end if;
 insert into public.billing_plans(
  organization_id,product_id,plan_code,plan_name,description,plan_tier,display_order,plan_type,status,is_public,
  requires_sales_approval,default_trial_days,metadata,created_by,updated_by
 ) values(
  p_org,p_product,p_code,p_name,p_description,p_tier,p_order,p_type,'active',p_public,p_sales_approval,
  greatest(p_trial_days,0),coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) on conflict(organization_id,product_id,plan_code) where organization_id is not null do update set
  plan_name=excluded.plan_name,description=excluded.description,plan_tier=excluded.plan_tier,display_order=excluded.display_order,
  plan_type=excluded.plan_type,is_public=excluded.is_public,requires_sales_approval=excluded.requires_sales_approval,
  default_trial_days=excluded.default_trial_days,metadata=excluded.metadata,updated_by=auth.uid(),updated_at=now()
 returning * into r;
 return r;
end $$;

create or replace function public.create_billing_plan_price(
 p_org uuid,p_plan uuid,p_code text,p_name text,p_amount bigint,p_currency text default 'INR',
 p_interval text default 'month',p_interval_count integer default 1,p_type text default 'flat',
 p_tax_inclusive boolean default false,p_custom boolean default false,p_provider uuid default null,
 p_external_price text default null,p_external_plan text default null,p_trial_days integer default null,
 p_metadata jsonb default '{}'
) returns public.billing_plan_prices
language plpgsql security definer set search_path='' as $$
declare r public.billing_plan_prices;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.manage_catalog') then raise exception 'Permission denied'; end if;
 insert into public.billing_plan_prices(
  organization_id,plan_id,provider_id,price_code,price_name,price_type,billing_interval,interval_count,currency,
  amount_minor,tax_inclusive,is_custom_price,external_price_id,external_plan_id,trial_days_override,status,metadata,
  created_by,updated_by
 ) values(
  p_org,p_plan,p_provider,p_code,p_name,p_type,p_interval,greatest(p_interval_count,1),p_currency,p_amount,
  p_tax_inclusive,p_custom,p_external_price,p_external_plan,p_trial_days,'active',coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) on conflict(organization_id,plan_id,price_code) where organization_id is not null do update set
  provider_id=excluded.provider_id,price_name=excluded.price_name,price_type=excluded.price_type,
  billing_interval=excluded.billing_interval,interval_count=excluded.interval_count,currency=excluded.currency,
  amount_minor=excluded.amount_minor,tax_inclusive=excluded.tax_inclusive,is_custom_price=excluded.is_custom_price,
  external_price_id=excluded.external_price_id,external_plan_id=excluded.external_plan_id,
  trial_days_override=excluded.trial_days_override,metadata=excluded.metadata,updated_by=auth.uid(),updated_at=now()
 returning * into r;
 return r;
end $$;

-- 25. Set plan entitlement
create or replace function public.set_billing_plan_entitlement(
 p_org uuid,p_plan uuid,p_entitlement_code text,p_enabled boolean default true,p_unlimited boolean default false,
 p_boolean boolean default null,p_integer bigint default null,p_numeric numeric default null,p_text text default null,
 p_json jsonb default null,p_hard_limit boolean default null,p_warning numeric default 80,p_metadata jsonb default '{}'
) returns public.billing_plan_entitlements
language plpgsql security definer set search_path='' as $$
declare d public.billing_entitlement_definitions; r public.billing_plan_entitlements;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.manage_entitlements') then raise exception 'Permission denied'; end if;
 select * into d from public.billing_entitlement_definitions
 where entitlement_code=p_entitlement_code and status='active' and (organization_id is null or organization_id=p_org)
 order by case when organization_id=p_org then 0 else 1 end limit 1;
 if not found then raise exception 'Entitlement not found'; end if;
 insert into public.billing_plan_entitlements(
  organization_id,plan_id,entitlement_definition_id,enabled,unlimited,boolean_value,integer_value,numeric_value,
  text_value,json_value,hard_limit,warning_threshold_percentage,metadata,created_by,updated_by
 ) values(
  p_org,p_plan,d.id,p_enabled,p_unlimited,p_boolean,p_integer,p_numeric,p_text,p_json,p_hard_limit,
  coalesce(p_warning,80),coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) on conflict(plan_id,entitlement_definition_id) do update set
  enabled=excluded.enabled,unlimited=excluded.unlimited,boolean_value=excluded.boolean_value,
  integer_value=excluded.integer_value,numeric_value=excluded.numeric_value,text_value=excluded.text_value,
  json_value=excluded.json_value,hard_limit=excluded.hard_limit,
  warning_threshold_percentage=excluded.warning_threshold_percentage,metadata=excluded.metadata,
  updated_by=auth.uid(),updated_at=now()
 returning * into r;
 return r;
end $$;

-- 26. Start subscription
create or replace function public.start_billing_subscription(
 p_org uuid,p_customer uuid,p_price uuid,p_quantity numeric default 1,p_provider_account uuid default null,
 p_external_subscription text default null,p_trial_days integer default null,p_collection text default 'automatic',
 p_payment_method uuid default null,p_primary boolean default true,p_metadata jsonb default '{}'
) returns public.billing_subscriptions
language plpgsql security definer set search_path='' as $$
declare pr public.billing_plan_prices; pl public.billing_plans; c public.billing_customers; s public.billing_subscriptions;
 v_start timestamptz:=now(); v_end timestamptz; v_trial integer; v_status text; v_amount bigint;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.manage_subscriptions') then raise exception 'Permission denied'; end if;
 select * into c from public.billing_customers where id=p_customer and organization_id=p_org and status='active';
 if not found then raise exception 'Active billing customer not found'; end if;
 select * into pr from public.billing_plan_prices where id=p_price and status='active' and valid_from<=now()
  and (valid_until is null or valid_until>now()) and (organization_id is null or organization_id=p_org);
 if not found then raise exception 'Active plan price not found'; end if;
 select * into pl from public.billing_plans where id=pr.plan_id and status='active';
 if not found then raise exception 'Active plan not found'; end if;
 if pr.is_custom_price and pr.amount_minor is null then raise exception 'Custom price requires agreed amount'; end if;
 if p_primary and exists(select 1 from public.billing_subscriptions where organization_id=p_org and is_primary and status in('incomplete','trialing','active','past_due','grace','paused','suspended')) then
  raise exception 'Organization already has an active primary subscription';
 end if;
 v_trial:=coalesce(p_trial_days,pr.trial_days_override,pl.default_trial_days,0);
 if v_trial>0 then v_end:=v_start+make_interval(days=>v_trial); v_status:='trialing';
 else v_end:=public.calculate_billing_period_end(v_start,pr.billing_interval,pr.interval_count); v_status:='active'; end if;
 v_amount:=round(coalesce(pr.amount_minor,0)::numeric*greatest(p_quantity,1))::bigint;
 insert into public.billing_subscriptions(
  organization_id,billing_customer_id,product_id,plan_id,plan_price_id,provider_account_id,subscription_code,
  external_subscription_id,status,is_primary,quantity,currency,unit_amount_minor,recurring_amount_minor,starts_at,
  trial_starts_at,trial_ends_at,current_period_start,current_period_end,next_billing_at,collection_method,
  default_payment_method_id,tax_behavior,metadata,created_by,updated_by
 ) values(
  p_org,c.id,pl.product_id,pl.id,pr.id,p_provider_account,
  'SUB-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),p_external_subscription,v_status,p_primary,
  greatest(p_quantity,1),pr.currency,pr.amount_minor,v_amount,v_start,
  case when v_trial>0 then v_start end,case when v_trial>0 then v_end end,v_start,v_end,
  case when pr.billing_interval='one_time' then null else v_end end,p_collection,p_payment_method,
  case when pr.tax_inclusive then 'inclusive' else 'exclusive' end,coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) returning * into s;
 insert into public.billing_subscription_items(
  organization_id,subscription_id,item_code,item_type,plan_price_id,quantity,unit_amount_minor,recurring_amount_minor,
  currency,status,metadata,created_by,updated_by
 ) values(s.organization_id,s.id,'BASE_PLAN','base_plan',pr.id,s.quantity,pr.amount_minor,s.recurring_amount_minor,
  s.currency,'active',jsonb_build_object('plan_code',pl.plan_code,'price_code',pr.price_code),auth.uid(),auth.uid());
 if v_trial>0 then
  insert into public.billing_trials(
   organization_id,subscription_id,trial_code,starts_at,ends_at,status,maximum_extension_days,metadata,created_by,updated_by
  ) values(s.organization_id,s.id,'TRIAL-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,16)),
   v_start,v_end,'active',14,jsonb_build_object('plan_code',pl.plan_code),auth.uid(),auth.uid());
 end if;
 perform public.sync_billing_subscription_license(s.id);
 return s;
end $$;

-- 27. Subscription status
create or replace function public.update_billing_subscription_status(
 p_subscription uuid,p_status text,p_reason text default null,p_effective_at timestamptz default now()
) returns public.billing_subscriptions
language plpgsql security definer set search_path='' as $$
declare s public.billing_subscriptions;
begin
 select * into s from public.billing_subscriptions where id=p_subscription for update;
 if not found then raise exception 'Subscription not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(s.organization_id,'billing.manage_subscriptions') then raise exception 'Permission denied'; end if;
 update public.billing_subscriptions set status=p_status,
  paused_at=case when p_status='paused' then coalesce(paused_at,p_effective_at) else paused_at end,
  cancellation_requested_at=case when p_status='cancelled' then coalesce(cancellation_requested_at,p_effective_at) else cancellation_requested_at end,
  cancelled_at=case when p_status='cancelled' then coalesce(cancelled_at,p_effective_at) else cancelled_at end,
  cancellation_reason=case when p_status='cancelled' then p_reason else cancellation_reason end,
  ended_at=case when p_status in('cancelled','expired','failed') then coalesce(ended_at,p_effective_at) else ended_at end,
  updated_by=auth.uid(),updated_at=now()
 where id=p_subscription returning * into s;
 perform public.sync_billing_subscription_license(s.id);
 return s;
end $$;

-- 28. Entitlement lookup
create or replace function public.check_billing_entitlement(p_org uuid,p_code text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s public.billing_subscriptions; d public.billing_entitlement_definitions;
 o public.billing_subscription_entitlement_overrides; pe public.billing_plan_entitlements; result jsonb;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.view')
  and not public.has_organization_permission(p_org,'billing.view_all')
  and not public.has_organization_permission(p_org,'billing.record_usage')
  and not public.has_organization_permission(p_org,'billing.manage_entitlements')
  and not public.has_organization_permission(p_org,'billing.manage_subscriptions') then raise exception 'Permission denied'; end if;
 select * into s from public.billing_subscriptions where organization_id=p_org and is_primary
  and status in('trialing','active','past_due','grace','paused') order by created_at desc limit 1;
 if not found then return jsonb_build_object('allowed',false,'reason','no_active_subscription','entitlement_code',p_code); end if;
 select * into d from public.billing_entitlement_definitions where entitlement_code=p_code and status='active'
  and (organization_id is null or organization_id=p_org)
 order by case when organization_id=p_org then 0 else 1 end limit 1;
 if not found then return jsonb_build_object('allowed',false,'reason','entitlement_not_defined','entitlement_code',p_code); end if;
 select * into o from public.billing_subscription_entitlement_overrides where subscription_id=s.id
  and entitlement_definition_id=d.id and status='active' and valid_from<=now() and (valid_until is null or valid_until>now()) limit 1;
 if found then
  result:=jsonb_build_object('source','subscription_override','allowed',o.enabled,'enabled',o.enabled,'unlimited',o.unlimited,
   'boolean_value',o.boolean_value,'integer_value',o.integer_value,'numeric_value',o.numeric_value,
   'text_value',o.text_value,'json_value',o.json_value,'hard_limit',o.hard_limit,
   'warning_threshold_percentage',o.warning_threshold_percentage);
 else
  select * into pe from public.billing_plan_entitlements where plan_id=s.plan_id and entitlement_definition_id=d.id limit 1;
  if not found then return jsonb_build_object('allowed',false,'reason','not_in_plan','entitlement_code',p_code,'subscription_id',s.id); end if;
  result:=jsonb_build_object('source','plan','allowed',pe.enabled,'enabled',pe.enabled,'unlimited',pe.unlimited,
   'boolean_value',pe.boolean_value,'integer_value',pe.integer_value,'numeric_value',pe.numeric_value,
   'text_value',pe.text_value,'json_value',pe.json_value,'hard_limit',pe.hard_limit,
   'warning_threshold_percentage',pe.warning_threshold_percentage);
 end if;
 return result||jsonb_build_object('entitlement_code',d.entitlement_code,'entitlement_name',d.entitlement_name,
  'entitlement_type',d.entitlement_type,'value_type',d.value_type,'unit',d.unit,'reset_period',d.reset_period,
  'subscription_id',s.id,'plan_id',s.plan_id,'subscription_status',s.status);
end $$;

-- 29. Consume quota
create or replace function public.consume_billing_quota(
 p_org uuid,p_code text,p_quantity numeric default 1,p_idempotency_key text default null,p_metadata jsonb default '{}'
) returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.billing_subscriptions; d public.billing_entitlement_definitions; er jsonb;
 v_allowed numeric; v_unlimited boolean; v_hard boolean; v_warning numeric;
 v_start timestamptz; v_end timestamptz; q public.billing_quota_counters; projected numeric; pct numeric;
begin
 if p_quantity<=0 then raise exception 'Quantity must be positive'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.record_usage') then raise exception 'Permission denied'; end if;
 select * into s from public.billing_subscriptions where organization_id=p_org and is_primary
  and status in('trialing','active','past_due','grace') order by created_at desc limit 1;
 if not found then raise exception 'No active subscription'; end if;
 select * into d from public.billing_entitlement_definitions where entitlement_code=p_code and status='active'
  and (organization_id is null or organization_id=p_org)
 order by case when organization_id=p_org then 0 else 1 end limit 1;
 if not found then raise exception 'Quota entitlement not found'; end if;
 er:=public.check_billing_entitlement(p_org,p_code);
 if not coalesce((er->>'allowed')::boolean,false) then raise exception 'Entitlement not allowed'; end if;
 v_unlimited:=coalesce(nullif(er->>'unlimited','')::boolean,false);
 v_allowed:=coalesce(nullif(er->>'numeric_value','')::numeric,nullif(er->>'integer_value','')::numeric);
 v_hard:=coalesce(nullif(er->>'hard_limit','')::boolean,d.hard_limit_default,true);
 v_warning:=coalesce(nullif(er->>'warning_threshold_percentage','')::numeric,80);
 v_start:=case d.reset_period when 'daily' then date_trunc('day',now()) when 'weekly' then date_trunc('week',now())
  when 'monthly' then date_trunc('month',now()) when 'quarterly' then date_trunc('quarter',now())
  when 'annual' then date_trunc('year',now()) when 'billing_period' then s.current_period_start else s.starts_at end;
 v_end:=case d.reset_period when 'daily' then v_start+interval '1 day' when 'weekly' then v_start+interval '1 week'
  when 'monthly' then v_start+interval '1 month' when 'quarterly' then v_start+interval '3 months'
  when 'annual' then v_start+interval '1 year' when 'billing_period' then s.current_period_end else s.current_period_end end;
 insert into public.billing_quota_counters(
  organization_id,subscription_id,entitlement_definition_id,period_start,period_end,allowed_quantity,
  consumed_quantity,reserved_quantity,unlimited,hard_limit,warning_threshold_percentage,metadata
 ) values(p_org,s.id,d.id,v_start,v_end,v_allowed,0,0,v_unlimited,v_hard,v_warning,
  coalesce(p_metadata,'{}')||jsonb_build_object('last_idempotency_key',p_idempotency_key))
 on conflict(subscription_id,entitlement_definition_id,period_start,period_end) do nothing;
 select * into q from public.billing_quota_counters
 where subscription_id=s.id and entitlement_definition_id=d.id and period_start=v_start and period_end=v_end for update;
 projected:=q.consumed_quantity+q.reserved_quantity+p_quantity;
 if not q.unlimited and q.allowed_quantity is not null and projected>q.allowed_quantity and q.hard_limit then
  raise exception 'Quota exceeded for %. Allowed %, consumed %, requested %',p_code,q.allowed_quantity,q.consumed_quantity,p_quantity;
 end if;
 pct:=case when q.unlimited or q.allowed_quantity is null or q.allowed_quantity=0 then null else projected/q.allowed_quantity*100 end;
 update public.billing_quota_counters set consumed_quantity=consumed_quantity+p_quantity,last_consumed_at=now(),
  warning_emitted_at=case when pct is not null and pct>=v_warning and warning_emitted_at is null then now() else warning_emitted_at end,
  exhausted_at=case when not unlimited and allowed_quantity is not null and projected>=allowed_quantity then coalesce(exhausted_at,now()) else exhausted_at end,
  metadata=metadata||coalesce(p_metadata,'{}')||jsonb_build_object('last_idempotency_key',p_idempotency_key,'last_consumption',p_quantity),
  updated_at=now()
 where id=q.id returning * into q;
 return jsonb_build_object('allowed',true,'entitlement_code',p_code,'subscription_id',s.id,'period_start',q.period_start,
  'period_end',q.period_end,'unlimited',q.unlimited,'allowed_quantity',q.allowed_quantity,
  'consumed_quantity',q.consumed_quantity,'remaining_quantity',q.remaining_quantity,'usage_percentage',pct,'exhausted_at',q.exhausted_at);
end $$;
-- 30. Change subscription plan
create or replace function public.change_billing_subscription_plan(
 p_subscription uuid,p_new_price uuid,p_quantity numeric default null,p_effective_mode text default 'immediate',
 p_proration text default 'create_prorations',p_reason text default null
) returns public.billing_subscription_change_requests
language plpgsql security definer set search_path='' as $$
declare s public.billing_subscriptions; pr public.billing_plan_prices; pl public.billing_plans;
 old_plan public.billing_plans; cr public.billing_subscription_change_requests; effective_ts timestamptz;
begin
 select * into s from public.billing_subscriptions where id=p_subscription for update;
 if not found then raise exception 'Subscription not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(s.organization_id,'billing.manage_subscriptions') then raise exception 'Permission denied'; end if;
 select * into pr from public.billing_plan_prices where id=p_new_price and status='active'
  and (organization_id is null or organization_id=s.organization_id);
 if not found then raise exception 'Requested plan price not found'; end if;
 select * into pl from public.billing_plans where id=pr.plan_id and status='active';
 select * into old_plan from public.billing_plans where id=s.plan_id;
 effective_ts:=case when p_effective_mode='immediate' then now() else s.current_period_end end;
 insert into public.billing_subscription_change_requests(
  organization_id,subscription_id,change_code,change_type,current_plan_id,requested_plan_id,requested_plan_price_id,
  current_quantity,requested_quantity,effective_mode,effective_at,proration_behavior,status,requested_by,metadata
 ) values(
  s.organization_id,s.id,'CHG-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
  case when pl.plan_tier>old_plan.plan_tier then 'upgrade' when pl.plan_tier<old_plan.plan_tier then 'downgrade' else 'price_change' end,
  s.plan_id,pl.id,pr.id,s.quantity,coalesce(p_quantity,s.quantity),p_effective_mode,effective_ts,p_proration,
  case when p_effective_mode='immediate' then 'processing' else 'scheduled' end,auth.uid(),
  jsonb_build_object('reason',p_reason)
 ) returning * into cr;
 if p_effective_mode='immediate' then
  update public.billing_subscriptions set product_id=pl.product_id,plan_id=pl.id,plan_price_id=pr.id,
   quantity=coalesce(p_quantity,quantity),currency=pr.currency,unit_amount_minor=pr.amount_minor,
   recurring_amount_minor=round(coalesce(pr.amount_minor,0)::numeric*coalesce(p_quantity,quantity))::bigint,
   updated_by=auth.uid(),updated_at=now()
  where id=s.id returning * into s;
  update public.billing_subscription_items set plan_price_id=pr.id,quantity=s.quantity,unit_amount_minor=pr.amount_minor,
   recurring_amount_minor=s.recurring_amount_minor,currency=pr.currency,
   metadata=metadata||jsonb_build_object('changed_at',now(),'new_plan_code',pl.plan_code,'new_price_code',pr.price_code),
   updated_by=auth.uid(),updated_at=now()
  where subscription_id=s.id and item_type='base_plan' and status='active';
  update public.billing_subscription_change_requests set status='completed',approved_by=auth.uid(),approved_at=now(),
   completed_at=now(),updated_at=now() where id=cr.id returning * into cr;
  perform public.sync_billing_subscription_license(s.id);
 end if;
 return cr;
end $$;

-- 31. Record usage event
create or replace function public.record_billing_usage_event(
 p_org uuid,p_meter_code text,p_event_id text,p_quantity numeric default 1,p_subscription uuid default null,
 p_customer uuid default null,p_dimension_key text default null,p_dimensions jsonb default '{}',
 p_event_data jsonb default '{}',p_source_type text default null,p_source_id uuid default null,
 p_occurred_at timestamptz default now(),p_idempotency_key text default null,
 p_correlation_id text default null,p_trace_id text default null
) returns public.billing_usage_events
language plpgsql security definer set search_path='' as $$
declare m public.billing_usage_meter_definitions; s public.billing_subscriptions;
 existing public.billing_usage_events; r public.billing_usage_events; entitlement_code text;
begin
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.record_usage') then raise exception 'Permission denied'; end if;
 select * into m from public.billing_usage_meter_definitions where meter_code=p_meter_code and status='active'
  and (organization_id is null or organization_id=p_org)
 order by case when organization_id=p_org then 0 else 1 end limit 1;
 if not found then raise exception 'Active meter not found'; end if;
 if p_subscription is null then
  select * into s from public.billing_subscriptions where organization_id=p_org and is_primary
   and status in('trialing','active','past_due','grace') order by created_at desc limit 1;
 else
  select * into s from public.billing_subscriptions where id=p_subscription and organization_id=p_org;
 end if;
 if not found then raise exception 'Subscription not found for usage event'; end if;
 if p_idempotency_key is not null then
  select * into existing from public.billing_usage_events where organization_id=p_org and idempotency_key=p_idempotency_key limit 1;
  if found then return existing; end if;
 end if;
 insert into public.billing_usage_events(
  organization_id,billing_customer_id,subscription_id,meter_definition_id,event_id,event_name,quantity,
  dimension_key,dimensions,event_data,source_type,source_id,occurred_at,billing_period_start,billing_period_end,
  status,idempotency_key,correlation_id,trace_id
 ) values(
  p_org,coalesce(p_customer,s.billing_customer_id),s.id,m.id,p_event_id,m.event_name,p_quantity,p_dimension_key,
  coalesce(p_dimensions,'{}'),coalesce(p_event_data,'{}'),p_source_type,p_source_id,coalesce(p_occurred_at,now()),
  s.current_period_start,s.current_period_end,'accepted',p_idempotency_key,p_correlation_id,p_trace_id
 ) returning * into r;
 if m.entitlement_definition_id is not null and p_quantity>0 then
  select entitlement_code into entitlement_code from public.billing_entitlement_definitions where id=m.entitlement_definition_id;
  perform public.consume_billing_quota(p_org,entitlement_code,p_quantity,p_idempotency_key,
   jsonb_build_object('usage_event_id',r.id,'meter_code',m.meter_code));
 end if;
 return r;
end $$;

-- 32. Aggregate usage
create or replace function public.aggregate_billing_usage(
 p_subscription uuid,p_meter_code text,p_period_start timestamptz,p_period_end timestamptz,p_finalize boolean default false
) returns public.billing_usage_aggregates
language plpgsql security definer set search_path='' as $$
declare s public.billing_subscriptions; m public.billing_usage_meter_definitions; a public.billing_usage_aggregates;
 v_quantity numeric; v_count bigint; v_charge bigint;
begin
 select * into s from public.billing_subscriptions where id=p_subscription;
 if not found then raise exception 'Subscription not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(s.organization_id,'billing.manage_usage') then raise exception 'Permission denied'; end if;
 select * into m from public.billing_usage_meter_definitions where meter_code=p_meter_code and status='active'
  and (organization_id is null or organization_id=s.organization_id)
 order by case when organization_id=s.organization_id then 0 else 1 end limit 1;
 if not found then raise exception 'Usage meter not found'; end if;
 select case m.aggregation_method
   when 'sum' then coalesce(sum(e.quantity),0)
   when 'count' then count(*)::numeric
   when 'maximum' then coalesce(max(e.quantity),0)
   when 'minimum' then coalesce(min(e.quantity),0)
   when 'last' then coalesce((select e2.quantity from public.billing_usage_events e2
      where e2.subscription_id=s.id and e2.meter_definition_id=m.id and e2.occurred_at>=p_period_start
       and e2.occurred_at<p_period_end and e2.status in('accepted','aggregated')
      order by e2.occurred_at desc limit 1),0)
   when 'unique_count' then count(distinct coalesce(e.dimension_key,e.event_id))::numeric
   else coalesce(sum(e.quantity),0) end,
  count(*)
 into v_quantity,v_count
 from public.billing_usage_events e
 where e.subscription_id=s.id and e.meter_definition_id=m.id and e.occurred_at>=p_period_start
  and e.occurred_at<p_period_end and e.status in('accepted','aggregated');
 v_charge:=case when m.overage_price_minor is null then 0 else
  ceil(greatest(v_quantity-m.included_quantity,0)/greatest(m.overage_package_size,0.000001))::bigint*m.overage_price_minor end;
 insert into public.billing_usage_aggregates(
  organization_id,subscription_id,meter_definition_id,period_start,period_end,aggregated_quantity,
  included_quantity,estimated_charge_minor,aggregation_method,event_count,status,finalized_at,calculation_data
 ) values(
  s.organization_id,s.id,m.id,p_period_start,p_period_end,v_quantity,m.included_quantity,v_charge,
  m.aggregation_method,v_count,case when p_finalize then 'finalized' else 'open' end,
  case when p_finalize then now() end,
  jsonb_build_object('meter_code',m.meter_code,'overage_price_minor',m.overage_price_minor,'overage_package_size',m.overage_package_size)
 ) on conflict(subscription_id,meter_definition_id,period_start,period_end) do update set
  aggregated_quantity=excluded.aggregated_quantity,included_quantity=excluded.included_quantity,
  estimated_charge_minor=excluded.estimated_charge_minor,aggregation_method=excluded.aggregation_method,
  event_count=excluded.event_count,status=excluded.status,finalized_at=excluded.finalized_at,
  calculation_data=excluded.calculation_data,updated_at=now()
 returning * into a;
 update public.billing_usage_events set status='aggregated'
 where subscription_id=s.id and meter_definition_id=m.id and occurred_at>=p_period_start
  and occurred_at<p_period_end and status='accepted';
 return a;
end $$;

-- 33. Generate invoice
create or replace function public.generate_billing_invoice(
 p_subscription uuid,p_invoice_type text default 'subscription',p_due_days integer default 7,
 p_include_usage boolean default true,p_metadata jsonb default '{}'
) returns public.billing_invoices
language plpgsql security definer set search_path='' as $$
declare s public.billing_subscriptions; c public.billing_customers; inv public.billing_invoices; item record;
 line_no integer:=1; invoice_no text;
begin
 select * into s from public.billing_subscriptions where id=p_subscription for update;
 if not found then raise exception 'Subscription not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(s.organization_id,'billing.manage_invoices') then raise exception 'Permission denied'; end if;
 select * into c from public.billing_customers where id=s.billing_customer_id;
 invoice_no:='SS-'||to_char(current_date,'YYYYMM')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 insert into public.billing_invoices(
  organization_id,billing_customer_id,subscription_id,provider_account_id,invoice_number,invoice_type,currency,
  status,billing_period_start,billing_period_end,invoice_date,due_date,tax_behavior,billing_details,metadata,created_by,updated_by
 ) values(
  s.organization_id,c.id,s.id,s.provider_account_id,invoice_no,p_invoice_type,s.currency,'draft',
  s.current_period_start,s.current_period_end,current_date,current_date+greatest(p_due_days,0),s.tax_behavior,
  jsonb_build_object('customer_name',c.customer_name,'legal_name',c.legal_name,'billing_email',c.billing_email,
   'billing_phone',c.billing_phone,'billing_address',c.billing_address,'country_code',c.country_code,'state_code',c.state_code),
  coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) returning * into inv;
 for item in select * from public.billing_subscription_items where subscription_id=s.id and status='active'
  and (ends_at is null or ends_at>s.current_period_start) order by created_at
 loop
  insert into public.billing_invoice_items(
   organization_id,invoice_id,line_number,item_type,item_code,description,subscription_item_id,quantity,
   unit_amount_minor,gross_amount_minor,taxable_minor,line_total_minor,period_start,period_end,metadata
  ) values(
   inv.organization_id,inv.id,line_no,
   case item.item_type when 'base_plan' then 'subscription' when 'metered' then 'usage' else item.item_type end,
   item.item_code,case item.item_type when 'base_plan' then 'SalesSetu subscription'
    when 'addon' then 'SalesSetu add-on' when 'seat' then 'SalesSetu license seats'
    else initcap(replace(item.item_type,'_',' ')) end,
   item.id,item.quantity,coalesce(item.unit_amount_minor,0),item.recurring_amount_minor,
   item.recurring_amount_minor,item.recurring_amount_minor,s.current_period_start,s.current_period_end,item.metadata
  );
  line_no:=line_no+1;
 end loop;
 if p_include_usage then
  for item in select a.*,m.meter_code,m.meter_name,m.unit
   from public.billing_usage_aggregates a join public.billing_usage_meter_definitions m on m.id=a.meter_definition_id
   where a.subscription_id=s.id and a.status='finalized' and a.period_start>=s.current_period_start
    and a.period_end<=s.current_period_end and a.estimated_charge_minor>0 order by a.period_start,m.meter_code
  loop
   insert into public.billing_invoice_items(
    organization_id,invoice_id,line_number,item_type,item_code,description,usage_aggregate_id,quantity,
    unit_amount_minor,gross_amount_minor,taxable_minor,line_total_minor,period_start,period_end,metadata
   ) values(
    inv.organization_id,inv.id,line_no,'usage',item.meter_code,item.meter_name||' usage',item.id,
    item.billable_quantity,case when item.billable_quantity=0 then 0 else round(item.estimated_charge_minor::numeric/item.billable_quantity)::bigint end,
    item.estimated_charge_minor,item.estimated_charge_minor,item.estimated_charge_minor,item.period_start,item.period_end,
    jsonb_build_object('unit',item.unit,'aggregated_quantity',item.aggregated_quantity,
     'included_quantity',item.included_quantity,'billable_quantity',item.billable_quantity)
   );
   line_no:=line_no+1;
  end loop;
 end if;
 return inv;
end $$;

-- 34. Add invoice item
create or replace function public.add_billing_invoice_item(
 p_invoice uuid,p_item_type text,p_description text,p_quantity numeric default 1,p_unit_amount bigint default 0,
 p_discount bigint default 0,p_tax_rate numeric default 0,p_item_code text default null,
 p_period_start timestamptz default null,p_period_end timestamptz default null,p_metadata jsonb default '{}'
) returns public.billing_invoice_items
language plpgsql security definer set search_path='' as $$
declare inv public.billing_invoices; r public.billing_invoice_items; n integer; gross bigint; taxable bigint; tax bigint; total bigint;
begin
 select * into inv from public.billing_invoices where id=p_invoice for update;
 if not found then raise exception 'Invoice not found'; end if;
 if inv.status<>'draft' then raise exception 'Only draft invoice may be edited'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(inv.organization_id,'billing.manage_invoices') then raise exception 'Permission denied'; end if;
 select coalesce(max(line_number),0)+1 into n from public.billing_invoice_items where invoice_id=inv.id;
 gross:=round(p_quantity*p_unit_amount)::bigint; taxable:=greatest(gross-greatest(p_discount,0),0);
 tax:=round(taxable::numeric*coalesce(p_tax_rate,0)/100)::bigint; total:=taxable+tax;
 insert into public.billing_invoice_items(
  organization_id,invoice_id,line_number,item_type,item_code,description,quantity,unit_amount_minor,
  gross_amount_minor,discount_minor,taxable_minor,tax_minor,line_total_minor,tax_rate_percentage,
  period_start,period_end,metadata
 ) values(inv.organization_id,inv.id,n,p_item_type,p_item_code,p_description,p_quantity,p_unit_amount,gross,
  greatest(p_discount,0),taxable,tax,total,p_tax_rate,p_period_start,p_period_end,coalesce(p_metadata,'{}'))
 returning * into r;
 return r;
end $$;

-- 35. Finalize invoice
create or replace function public.finalize_billing_invoice(p_invoice uuid,p_issue_now boolean default true)
returns public.billing_invoices language plpgsql security definer set search_path='' as $$
declare inv public.billing_invoices; totals record;
begin
 select * into inv from public.billing_invoices where id=p_invoice for update;
 if not found then raise exception 'Invoice not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(inv.organization_id,'billing.manage_invoices') then raise exception 'Permission denied'; end if;
 if inv.status<>'draft' then raise exception 'Only draft invoices can be finalized'; end if;
 select coalesce(sum(gross_amount_minor),0) subtotal,coalesce(sum(discount_minor),0) discount,
  coalesce(sum(taxable_minor),0) taxable,coalesce(sum(tax_minor),0) tax,coalesce(sum(line_total_minor),0) total
 into totals from public.billing_invoice_items where invoice_id=inv.id;
 update public.billing_invoices set subtotal_minor=totals.subtotal,discount_minor=totals.discount,
  taxable_minor=totals.taxable,tax_minor=totals.tax,total_minor=totals.total,
  status=case when p_issue_now then 'issued' else 'open' end,finalized_at=now(),
  issued_at=case when p_issue_now then now() else issued_at end,updated_by=auth.uid(),updated_at=now()
 where id=inv.id returning * into inv;
 update public.billing_usage_aggregates set status='invoiced',invoiced_at=now(),updated_at=now()
 where id in(select usage_aggregate_id from public.billing_invoice_items where invoice_id=inv.id and usage_aggregate_id is not null);
 return inv;
end $$;

-- 36. Credits
create or replace function public.grant_billing_credit(
 p_customer uuid,p_amount bigint,p_currency text default 'INR',p_type text default 'grant',p_notes text default null,
 p_expires_at timestamptz default null,p_idempotency_key text default null,p_metadata jsonb default '{}'
) returns public.billing_credit_transactions
language plpgsql security definer set search_path='' as $$
declare c public.billing_customers; a public.billing_credit_accounts; tr public.billing_credit_transactions;
 existing public.billing_credit_transactions; before_balance bigint;
begin
 if p_amount<=0 then raise exception 'Credit amount must be positive'; end if;
 select * into c from public.billing_customers where id=p_customer;
 if not found then raise exception 'Customer not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(c.organization_id,'billing.manage_credits') then raise exception 'Permission denied'; end if;
 if p_idempotency_key is not null then
  select * into existing from public.billing_credit_transactions where organization_id=c.organization_id and idempotency_key=p_idempotency_key limit 1;
  if found then return existing; end if;
 end if;
 insert into public.billing_credit_accounts(organization_id,billing_customer_id,currency,status)
 values(c.organization_id,c.id,p_currency,'active') on conflict(billing_customer_id,currency) do nothing;
 select * into a from public.billing_credit_accounts where billing_customer_id=c.id and currency=p_currency for update;
 before_balance:=a.balance_minor;
 update public.billing_credit_accounts set balance_minor=balance_minor+p_amount,updated_at=now() where id=a.id returning * into a;
 insert into public.billing_credit_transactions(
  organization_id,credit_account_id,transaction_code,transaction_type,amount_minor,balance_before_minor,balance_after_minor,
  expires_at,notes,idempotency_key,metadata,created_by
 ) values(c.organization_id,a.id,'CRT-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),p_type,p_amount,
  before_balance,a.balance_minor,p_expires_at,p_notes,p_idempotency_key,coalesce(p_metadata,'{}'),auth.uid())
 returning * into tr;
 return tr;
end $$;

create or replace function public.apply_billing_credit_to_invoice(p_invoice uuid,p_amount bigint default null)
returns public.billing_invoices language plpgsql security definer set search_path='' as $$
declare inv public.billing_invoices; a public.billing_credit_accounts; apply_amt bigint; before_balance bigint;
begin
 select * into inv from public.billing_invoices where id=p_invoice for update;
 if not found then raise exception 'Invoice not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(inv.organization_id,'billing.manage_credits') then raise exception 'Permission denied'; end if;
 select * into a from public.billing_credit_accounts where billing_customer_id=inv.billing_customer_id
  and currency=inv.currency and status='active' for update;
 if not found then raise exception 'Active credit account not found'; end if;
 apply_amt:=least(coalesce(p_amount,inv.outstanding_minor),inv.outstanding_minor,a.available_minor);
 if apply_amt<=0 then raise exception 'No credit available or no invoice outstanding'; end if;
 before_balance:=a.balance_minor;
 update public.billing_credit_accounts set balance_minor=balance_minor-apply_amt,updated_at=now() where id=a.id returning * into a;
 insert into public.billing_credit_transactions(
  organization_id,credit_account_id,transaction_code,transaction_type,amount_minor,balance_before_minor,balance_after_minor,
  related_entity_type,related_entity_id,notes,metadata,created_by
 ) values(inv.organization_id,a.id,'CRT-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
  'invoice_application',-apply_amt,before_balance,a.balance_minor,'billing_invoice',inv.id,
  'Credit applied to invoice '||inv.invoice_number,'{}',auth.uid());
 update public.billing_invoices set credit_applied_minor=credit_applied_minor+apply_amt,
  status=case when outstanding_minor-apply_amt<=0 then 'paid' else 'partially_paid' end,
  paid_at=case when outstanding_minor-apply_amt<=0 then coalesce(paid_at,now()) else paid_at end,
  updated_by=auth.uid(),updated_at=now()
 where id=inv.id returning * into inv;
 return inv;
end $$;

-- 37. Payment
create or replace function public.record_billing_payment(
 p_org uuid,p_customer uuid,p_amount bigint,p_currency text default 'INR',p_invoice uuid default null,
 p_provider_account uuid default null,p_payment_method uuid default null,p_method_type text default null,
 p_external_payment text default null,p_external_order text default null,p_status text default 'succeeded',
 p_received_at timestamptz default now(),p_idempotency_key text default null,p_metadata jsonb default '{}'
) returns public.billing_payments
language plpgsql security definer set search_path='' as $$
declare pay public.billing_payments; existing public.billing_payments; inv public.billing_invoices; allocation bigint;
begin
 if p_amount<0 then raise exception 'Payment amount cannot be negative'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(p_org,'billing.manage_payments') then raise exception 'Permission denied'; end if;
 if p_idempotency_key is not null then
  select * into existing from public.billing_payments where organization_id=p_org and idempotency_key=p_idempotency_key limit 1;
  if found then return existing; end if;
 end if;
 insert into public.billing_payments(
  organization_id,billing_customer_id,provider_account_id,payment_method_id,payment_code,external_payment_id,
  external_order_id,payment_type,amount_minor,currency,payment_method_type,status,received_at,authorized_at,
  captured_at,idempotency_key,metadata,created_by,updated_by
 ) values(
  p_org,p_customer,p_provider_account,p_payment_method,
  'PAY-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),p_external_payment,p_external_order,
  case when p_invoice is null then 'advance' else 'invoice' end,p_amount,p_currency,p_method_type,p_status,p_received_at,
  case when p_status in('authorized','captured','succeeded') then p_received_at end,
  case when p_status in('captured','succeeded') then p_received_at end,p_idempotency_key,
  coalesce(p_metadata,'{}'),auth.uid(),auth.uid()
 ) returning * into pay;
 if p_invoice is not null and p_status in('captured','succeeded') then
  select * into inv from public.billing_invoices where id=p_invoice and organization_id=p_org and billing_customer_id=p_customer for update;
  if not found then raise exception 'Invoice not found for allocation'; end if;
  allocation:=least(p_amount,inv.outstanding_minor);
  if allocation>0 then
   insert into public.billing_payment_allocations(organization_id,payment_id,invoice_id,allocated_minor,allocation_type,allocated_at,created_by)
   values(p_org,pay.id,inv.id,allocation,'payment',p_received_at,auth.uid());
   update public.billing_invoices set paid_minor=paid_minor+allocation,
    status=case when outstanding_minor-allocation<=0 then 'paid' else 'partially_paid' end,
    paid_at=case when outstanding_minor-allocation<=0 then coalesce(paid_at,p_received_at) else paid_at end,
    updated_by=auth.uid(),updated_at=now()
   where id=inv.id;
  end if;
 end if;
 return pay;
end $$;

-- 38. Refund
create or replace function public.record_billing_refund(
 p_payment uuid,p_amount bigint,p_invoice uuid default null,p_external_refund text default null,
 p_status text default 'succeeded',p_reason text default null,p_metadata jsonb default '{}'
) returns public.billing_refunds
language plpgsql security definer set search_path='' as $$
declare pay public.billing_payments; r public.billing_refunds; refunded bigint;
begin
 select * into pay from public.billing_payments where id=p_payment for update;
 if not found then raise exception 'Payment not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(pay.organization_id,'billing.manage_payments') then raise exception 'Permission denied'; end if;
 if p_amount<=0 then raise exception 'Refund amount must be positive'; end if;
 select coalesce(sum(amount_minor),0) into refunded from public.billing_refunds where payment_id=pay.id and status='succeeded';
 if refunded+p_amount>pay.amount_minor then raise exception 'Refund exceeds payment amount'; end if;
 insert into public.billing_refunds(
  organization_id,payment_id,invoice_id,refund_code,external_refund_id,amount_minor,currency,status,reason,
  requested_by,approved_by,requested_at,approved_at,processed_at,metadata
 ) values(
  pay.organization_id,pay.id,p_invoice,'REF-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
  p_external_refund,p_amount,pay.currency,p_status,p_reason,auth.uid(),
  case when p_status='succeeded' then auth.uid() end,now(),
  case when p_status='succeeded' then now() end,case when p_status='succeeded' then now() end,
  coalesce(p_metadata,'{}')
 ) returning * into r;
 if p_status='succeeded' then
  update public.billing_payments set status=case when refunded+p_amount>=amount_minor then 'refunded' else 'partially_refunded' end,
   updated_by=auth.uid(),updated_at=now() where id=pay.id;
  if p_invoice is not null then
   update public.billing_invoices set refunded_minor=refunded_minor+p_amount,
    status=case when p_amount>=paid_minor then 'refunded' else status end,
    updated_by=auth.uid(),updated_at=now()
   where id=p_invoice and organization_id=pay.organization_id;
  end if;
 end if;
 return r;
end $$;

-- 39. License assignments
create or replace function public.assign_billing_license(
 p_pool uuid,p_assignee_type text,p_user uuid default null,p_reference text default null,
 p_expires_at timestamptz default null,p_metadata jsonb default '{}'
) returns public.billing_license_assignments
language plpgsql security definer set search_path='' as $$
declare pool public.billing_license_pools; a public.billing_license_assignments;
begin
 select * into pool from public.billing_license_pools where id=p_pool for update;
 if not found then raise exception 'License pool not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(pool.organization_id,'billing.manage_licenses') then raise exception 'Permission denied'; end if;
 if pool.status<>'active' then raise exception 'License pool is not active'; end if;
 if not pool.unlimited and pool.assigned_quantity>=coalesce(pool.allocated_quantity,0) then raise exception 'No license seats available'; end if;
 if p_assignee_type='user' and p_user is null then raise exception 'User assignment requires user_id'; end if;
 insert into public.billing_license_assignments(
  organization_id,license_pool_id,assignment_code,assignee_type,user_id,assignee_reference,status,assigned_at,
  expires_at,metadata,assigned_by
 ) values(pool.organization_id,pool.id,'LIC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,18)),
  p_assignee_type,p_user,p_reference,'active',now(),p_expires_at,coalesce(p_metadata,'{}'),auth.uid())
 returning * into a;
 update public.billing_license_pools set assigned_quantity=assigned_quantity+1,updated_by=auth.uid(),updated_at=now() where id=pool.id;
 return a;
end $$;

create or replace function public.revoke_billing_license(p_assignment uuid,p_reason text default null)
returns public.billing_license_assignments language plpgsql security definer set search_path='' as $$
declare a public.billing_license_assignments;
begin
 select * into a from public.billing_license_assignments where id=p_assignment for update;
 if not found then raise exception 'License assignment not found'; end if;
 if auth.role()<>'service_role' and not public.has_organization_permission(a.organization_id,'billing.manage_licenses') then raise exception 'Permission denied'; end if;
 if a.status<>'active' then return a; end if;
 update public.billing_license_assignments set status='revoked',revoked_at=now(),revoked_by=auth.uid(),
  revocation_reason=p_reason,updated_at=now() where id=a.id returning * into a;
 update public.billing_license_pools set assigned_quantity=greatest(assigned_quantity-1,0),updated_by=auth.uid(),updated_at=now()
 where id=a.license_pool_id;
 return a;
end $$;

-- 40. Webhook inbox
create or replace function public.ingest_billing_webhook(
 p_provider_code text,p_provider_event_id text,p_event_type text,p_payload jsonb,p_headers jsonb default '{}',
 p_provider_account uuid default null,p_org uuid default null,p_signature_valid boolean default null,
 p_signature_error text default null,p_correlation_id text default null,p_trace_id text default null
) returns public.billing_webhook_inbox
language plpgsql security definer set search_path='' as $$
declare prov public.billing_providers; w public.billing_webhook_inbox;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may ingest billing webhooks'; end if;
 select * into prov from public.billing_providers where provider_code=p_provider_code;
 if not found then raise exception 'Provider not found'; end if;
 insert into public.billing_webhook_inbox(
  organization_id,provider_id,provider_account_id,provider_event_id,event_type,payload,headers,signature_valid,
  signature_validation_error,status,available_at,correlation_id,trace_id,received_at
 ) values(
  p_org,prov.id,p_provider_account,p_provider_event_id,p_event_type,coalesce(p_payload,'{}'),coalesce(p_headers,'{}'),
  p_signature_valid,p_signature_error,case when p_signature_valid=false then 'failed'
   when p_signature_valid=true then 'validated' else 'received' end,now(),p_correlation_id,p_trace_id,now()
 ) on conflict(provider_id,provider_event_id) do update set
  organization_id=coalesce(excluded.organization_id,public.billing_webhook_inbox.organization_id),
  provider_account_id=coalesce(excluded.provider_account_id,public.billing_webhook_inbox.provider_account_id),
  event_type=excluded.event_type,payload=excluded.payload,headers=excluded.headers,signature_valid=excluded.signature_valid,
  signature_validation_error=excluded.signature_validation_error,
  status=case when public.billing_webhook_inbox.status='processed' then 'processed' else excluded.status end,
  correlation_id=coalesce(excluded.correlation_id,public.billing_webhook_inbox.correlation_id),
  trace_id=coalesce(excluded.trace_id,public.billing_webhook_inbox.trace_id),updated_at=now()
 returning * into w;
 return w;
end $$;

create or replace function public.claim_billing_webhook(p_worker text,p_provider_code text default null,p_lock_seconds integer default 300)
returns public.billing_webhook_inbox
language plpgsql security definer set search_path='' as $$
declare w public.billing_webhook_inbox;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may claim webhooks'; end if;
 select wi.* into w from public.billing_webhook_inbox wi join public.billing_providers p on p.id=wi.provider_id
 where wi.status in('received','validated','failed') and wi.available_at<=now()
  and wi.processing_attempts<wi.maximum_attempts and (p_provider_code is null or p.provider_code=p_provider_code)
 order by wi.received_at for update of wi skip locked limit 1;
 if not found then return null; end if;
 update public.billing_webhook_inbox set status='processing',processing_attempts=processing_attempts+1,
  claimed_at=now(),claimed_by=p_worker,lock_token=gen_random_uuid()::text,
  lock_expires_at=now()+make_interval(secs=>greatest(p_lock_seconds,1)),updated_at=now()
 where id=w.id returning * into w;
 return w;
end $$;

create or replace function public.complete_billing_webhook(
 p_webhook uuid,p_lock_token text,p_status text default 'processed',p_result jsonb default '{}'
) returns public.billing_webhook_inbox
language plpgsql security definer set search_path='' as $$
declare w public.billing_webhook_inbox;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may complete webhooks'; end if;
 select * into w from public.billing_webhook_inbox where id=p_webhook for update;
 if not found then raise exception 'Webhook not found'; end if;
 if w.lock_token is distinct from p_lock_token then raise exception 'Invalid webhook lock token'; end if;
 update public.billing_webhook_inbox set status=p_status,
  processed_at=case when p_status in('processed','ignored') then now() else processed_at end,
  payload=payload||jsonb_build_object('processing_result',coalesce(p_result,'{}')),
  claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
 where id=w.id returning * into w;
 if w.provider_account_id is not null then
  update public.billing_provider_accounts set last_webhook_at=now(),updated_at=now() where id=w.provider_account_id;
 end if;
 return w;
end $$;

create or replace function public.fail_billing_webhook(
 p_webhook uuid,p_lock_token text,p_error_code text,p_error_message text,p_error_data jsonb default '{}'
) returns public.billing_webhook_inbox
language plpgsql security definer set search_path='' as $$
declare w public.billing_webhook_inbox; next_status text; retry_delay integer;
begin
 if auth.role()<>'service_role' then raise exception 'Only service_role may fail webhooks'; end if;
 select * into w from public.billing_webhook_inbox where id=p_webhook for update;
 if not found then raise exception 'Webhook not found'; end if;
 if w.lock_token is distinct from p_lock_token then raise exception 'Invalid webhook lock token'; end if;
 next_status:=case when w.processing_attempts>=w.maximum_attempts then 'dead_lettered' else 'failed' end;
 retry_delay:=least(3600,greatest(30,power(2,greatest(w.processing_attempts,1))::integer*30));
 update public.billing_webhook_inbox set status=next_status,
  available_at=case when next_status='failed' then now()+make_interval(secs=>retry_delay) else available_at end,
  last_error_code=p_error_code,last_error_message=p_error_message,last_error_data=coalesce(p_error_data,'{}'),
  claimed_at=null,claimed_by=null,lock_token=null,lock_expires_at=null,updated_at=now()
 where id=w.id returning * into w;
 insert into public.billing_logs(organization_id,log_level,event_name,message,source_type,source_id,error_code,error_message,log_data,correlation_id,trace_id)
 values(w.organization_id,case when next_status='dead_lettered' then 'critical' else 'error' end,
  'billing_webhook.'||next_status,'Billing webhook processing failed','billing_webhook',w.id,p_error_code,p_error_message,
  coalesce(p_error_data,'{}'),w.correlation_id,w.trace_id);
 return w;
end $$;
-- 41. Domain event triggers
create or replace function public.emit_billing_subscription_events()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.status is not distinct from old.status
  and new.plan_id is not distinct from old.plan_id and new.quantity is not distinct from old.quantity then return new; end if;
 perform public.sync_billing_subscription_license(new.id);
 perform public.publish_billing_event(
  new.organization_id,'billing.subscription.'||new.status,
  jsonb_build_object('subscription_id',new.id,'subscription_code',new.subscription_code,
   'billing_customer_id',new.billing_customer_id,'product_id',new.product_id,'plan_id',new.plan_id,
   'plan_price_id',new.plan_price_id,'status',new.status,'is_primary',new.is_primary,'quantity',new.quantity,
   'currency',new.currency,'recurring_amount_minor',new.recurring_amount_minor,'trial_ends_at',new.trial_ends_at,
   'current_period_start',new.current_period_start,'current_period_end',new.current_period_end,'next_billing_at',new.next_billing_at),
  case when new.status in('past_due','grace','suspended','cancelled') then 'notification_engine'
   when new.status in('active','trialing') then 'automation_engine' else 'analytics' end,
  'billing_subscription',new.id,case when new.status in('past_due','suspended') then 10 else 100 end,
  'billing-subscription:'||new.id::text||':'||new.status||':'||new.updated_at::text,new.id::text,null,now()
 );
 return new;
end $$;
drop trigger if exists billing_subscriptions_emit_events on public.billing_subscriptions;
create trigger billing_subscriptions_emit_events after insert or update on public.billing_subscriptions
for each row execute function public.emit_billing_subscription_events();

create or replace function public.emit_billing_invoice_events()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.status is not distinct from old.status
  and new.outstanding_minor is not distinct from old.outstanding_minor then return new; end if;
 perform public.publish_billing_event(
  new.organization_id,'billing.invoice.'||new.status,
  jsonb_build_object('invoice_id',new.id,'invoice_number',new.invoice_number,
   'billing_customer_id',new.billing_customer_id,'subscription_id',new.subscription_id,'status',new.status,
   'currency',new.currency,'total_minor',new.total_minor,'paid_minor',new.paid_minor,
   'credit_applied_minor',new.credit_applied_minor,'refunded_minor',new.refunded_minor,
   'outstanding_minor',new.outstanding_minor,'invoice_date',new.invoice_date,'due_date',new.due_date),
  case when new.status in('past_due','uncollectible') then 'notification_engine'
   when new.status in('issued','paid','refunded') then 'communication_engine' else 'analytics' end,
  'billing_invoice',new.id,case when new.status='past_due' then 10 else 100 end,
  'billing-invoice:'||new.id::text||':'||new.status||':'||new.updated_at::text,new.id::text,null,now()
 );
 return new;
end $$;
drop trigger if exists billing_invoices_emit_events on public.billing_invoices;
create trigger billing_invoices_emit_events after insert or update on public.billing_invoices
for each row execute function public.emit_billing_invoice_events();

create or replace function public.emit_billing_payment_events()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.status is not distinct from old.status then return new; end if;
 perform public.publish_billing_event(
  new.organization_id,'billing.payment.'||new.status,
  jsonb_build_object('payment_id',new.id,'payment_code',new.payment_code,
   'billing_customer_id',new.billing_customer_id,'status',new.status,'amount_minor',new.amount_minor,
   'currency',new.currency,'external_payment_id',new.external_payment_id,'received_at',new.received_at,
   'failure_code',new.failure_code,'failure_message',new.failure_message),
  case when new.status='failed' then 'notification_engine'
   when new.status in('captured','succeeded','refunded') then 'communication_engine' else 'analytics' end,
  'billing_payment',new.id,case when new.status='failed' then 10 else 100 end,
  'billing-payment:'||new.id::text||':'||new.status||':'||new.updated_at::text,
  coalesce(new.correlation_id,new.id::text),new.trace_id,now()
 );
 return new;
end $$;
drop trigger if exists billing_payments_emit_events on public.billing_payments;
create trigger billing_payments_emit_events after insert or update on public.billing_payments
for each row execute function public.emit_billing_payment_events();

-- 42. Analytics views
create or replace view public.billing_subscription_dashboard with(security_invoker=true) as
select s.organization_id,p.plan_code,p.plan_name,s.status,s.currency,count(*) subscription_count,
 count(*) filter(where s.status='trialing') trialing_count,
 count(*) filter(where s.status='active') active_count,
 count(*) filter(where s.status in('past_due','grace')) delinquent_count,
 count(*) filter(where s.cancel_at_period_end) scheduled_cancellation_count,
 sum(s.recurring_amount_minor) filter(where s.status in('trialing','active','past_due','grace')) recurring_value_minor,
 min(s.next_billing_at) filter(where s.status in('trialing','active','past_due','grace')) next_billing_at,
 max(s.updated_at) latest_update_at
from public.billing_subscriptions s join public.billing_plans p on p.id=s.plan_id
group by s.organization_id,p.plan_code,p.plan_name,s.status,s.currency;

create or replace view public.billing_revenue_dashboard with(security_invoker=true) as
select i.organization_id,i.currency,date_trunc('month',i.invoice_date::timestamptz) revenue_month,
 count(*) invoice_count,sum(i.subtotal_minor) subtotal_minor,sum(i.discount_minor) discount_minor,
 sum(i.tax_minor) tax_minor,sum(i.total_minor) invoiced_minor,sum(i.paid_minor) paid_minor,
 sum(i.credit_applied_minor) credit_applied_minor,sum(i.refunded_minor) refunded_minor,
 sum(i.outstanding_minor) outstanding_minor,count(*) filter(where i.status='paid') paid_invoice_count,
 count(*) filter(where i.status in('past_due','uncollectible')) delinquent_invoice_count
from public.billing_invoices i where i.status not in('draft','void','cancelled','archived')
group by i.organization_id,i.currency,date_trunc('month',i.invoice_date::timestamptz);

create or replace view public.billing_invoice_aging_dashboard with(security_invoker=true) as
select organization_id,currency,count(*) filter(where outstanding_minor>0) outstanding_invoice_count,
 sum(outstanding_minor) filter(where due_date is null or due_date>=current_date) current_minor,
 sum(outstanding_minor) filter(where due_date<current_date and due_date>=current_date-30) overdue_1_30_minor,
 sum(outstanding_minor) filter(where due_date<current_date-30 and due_date>=current_date-60) overdue_31_60_minor,
 sum(outstanding_minor) filter(where due_date<current_date-60 and due_date>=current_date-90) overdue_61_90_minor,
 sum(outstanding_minor) filter(where due_date<current_date-90) overdue_90_plus_minor,
 min(due_date) filter(where outstanding_minor>0) oldest_due_date
from public.billing_invoices
where status in('open','issued','sent','partially_paid','past_due','uncollectible')
group by organization_id,currency;

create or replace view public.billing_usage_dashboard with(security_invoker=true) as
select a.organization_id,a.subscription_id,m.meter_code,m.meter_name,m.unit,a.period_start,a.period_end,a.status,
 a.aggregated_quantity,a.included_quantity,a.billable_quantity,a.estimated_charge_minor,a.event_count,
 round(case when a.included_quantity=0 then null else a.aggregated_quantity/a.included_quantity*100 end,2) included_usage_percentage
from public.billing_usage_aggregates a join public.billing_usage_meter_definitions m on m.id=a.meter_definition_id;

create or replace view public.billing_license_dashboard with(security_invoker=true) as
select p.organization_id,p.subscription_id,p.license_type,p.status,count(*) license_pool_count,
 sum(p.allocated_quantity) allocated_quantity,sum(p.assigned_quantity) assigned_quantity,
 sum(case when p.unlimited then 0 else p.available_quantity end) available_quantity,
 count(*) filter(where p.unlimited) unlimited_pool_count,max(p.updated_at) latest_update_at
from public.billing_license_pools p
group by p.organization_id,p.subscription_id,p.license_type,p.status;

create or replace view public.billing_dunning_dashboard with(security_invoker=true) as
select d.organization_id,d.status,i.currency,count(*) dunning_case_count,sum(i.outstanding_minor) outstanding_minor,
 count(*) filter(where d.next_attempt_at is not null and d.next_attempt_at<=now()) due_attempt_count,
 count(*) filter(where d.status='grace' and d.grace_ends_at is not null and d.grace_ends_at<=now()) expired_grace_count,
 max(d.opened_at) latest_opened_at,min(d.next_attempt_at) next_attempt_at
from public.billing_dunning_cases d join public.billing_invoices i on i.id=d.invoice_id
group by d.organization_id,d.status,i.currency;

create or replace view public.billing_payment_dashboard with(security_invoker=true) as
select organization_id,currency,status,payment_method_type,count(*) payment_count,sum(amount_minor) payment_amount_minor,
 count(*) filter(where status in('captured','succeeded')) successful_count,
 count(*) filter(where status='failed') failed_count,
 round(count(*) filter(where status in('captured','succeeded'))::numeric/nullif(count(*),0)*100,2) success_rate_percentage,
 max(received_at) latest_received_at,max(failed_at) latest_failed_at
from public.billing_payments group by organization_id,currency,status,payment_method_type;

grant select on public.billing_subscription_dashboard,public.billing_revenue_dashboard,
 public.billing_invoice_aging_dashboard,public.billing_usage_dashboard,public.billing_license_dashboard,
 public.billing_dunning_dashboard,public.billing_payment_dashboard to authenticated,service_role;

-- 43. Engine health
create or replace function public.get_billing_engine_health(p_org uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.role()<>'service_role' and (p_org is null or not public.has_organization_permission(p_org,'billing.view_logs')) then raise exception 'Permission denied'; end if;
 return jsonb_build_object(
  'organization_id',p_org,'checked_at',now(),
  'active_provider_accounts',(select count(*) from public.billing_provider_accounts a where a.status='active' and (p_org is null or a.organization_id=p_org)),
  'provider_accounts_in_error',(select count(*) from public.billing_provider_accounts a where a.status in('error','restricted','revoked') and (p_org is null or a.organization_id=p_org)),
  'active_subscriptions',(select count(*) from public.billing_subscriptions s where s.status in('trialing','active') and (p_org is null or s.organization_id=p_org)),
  'delinquent_subscriptions',(select count(*) from public.billing_subscriptions s where s.status in('past_due','grace','suspended') and (p_org is null or s.organization_id=p_org)),
  'trials_ending_7d',(select count(*) from public.billing_subscriptions s where s.status='trialing' and s.trial_ends_at<=now()+interval '7 days' and (p_org is null or s.organization_id=p_org)),
  'renewals_due_7d',(select count(*) from public.billing_subscriptions s where s.status in('active','past_due','grace') and s.next_billing_at<=now()+interval '7 days' and (p_org is null or s.organization_id=p_org)),
  'past_due_invoices',(select count(*) from public.billing_invoices i where i.outstanding_minor>0 and i.due_date<current_date and i.status not in('void','cancelled','paid','refunded','archived') and (p_org is null or i.organization_id=p_org)),
  'outstanding_minor',(select coalesce(sum(i.outstanding_minor),0) from public.billing_invoices i where i.status in('open','issued','sent','partially_paid','past_due','uncollectible') and (p_org is null or i.organization_id=p_org)),
  'failed_payments_24h',(select count(*) from public.billing_payments p where p.status='failed' and p.created_at>=now()-interval '24 hours' and (p_org is null or p.organization_id=p_org)),
  'open_dunning_cases',(select count(*) from public.billing_dunning_cases d where d.status in('open','retrying','grace','suspended') and (p_org is null or d.organization_id=p_org)),
  'exhausted_quotas',(select count(*) from public.billing_quota_counters q where not q.unlimited and q.allowed_quantity is not null and q.consumed_quantity+q.reserved_quantity>=q.allowed_quantity and q.period_end>now() and (p_org is null or q.organization_id=p_org)),
  'license_pools_exhausted',(select count(*) from public.billing_license_pools l where l.status='active' and not l.unlimited and l.available_quantity<=0 and (p_org is null or l.organization_id=p_org)),
  'pending_webhooks',(select count(*) from public.billing_webhook_inbox w where w.status in('received','validated','failed','processing') and (p_org is null or w.organization_id=p_org)),
  'expired_webhook_locks',(select count(*) from public.billing_webhook_inbox w where w.status='processing' and w.lock_expires_at<=now() and (p_org is null or w.organization_id=p_org)),
  'pending_outbox_events',(select count(*) from public.billing_event_outbox e where e.status in('pending','failed') and (p_org is null or e.organization_id=p_org))
 );
end $$;

-- 44. RLS
alter table public.billing_providers enable row level security;
alter table public.billing_provider_accounts enable row level security;
alter table public.billing_products enable row level security;
alter table public.billing_plans enable row level security;
alter table public.billing_plan_prices enable row level security;
alter table public.billing_addons enable row level security;
alter table public.billing_addon_prices enable row level security;
alter table public.billing_entitlement_definitions enable row level security;
alter table public.billing_plan_entitlements enable row level security;
alter table public.billing_customers enable row level security;
alter table public.billing_customer_tax_profiles enable row level security;
alter table public.billing_payment_methods enable row level security;
alter table public.billing_subscriptions enable row level security;
alter table public.billing_subscription_items enable row level security;
alter table public.billing_subscription_change_requests enable row level security;
alter table public.billing_trials enable row level security;
alter table public.billing_subscription_entitlement_overrides enable row level security;
alter table public.billing_usage_meter_definitions enable row level security;
alter table public.billing_usage_events enable row level security;
alter table public.billing_usage_aggregates enable row level security;
alter table public.billing_quota_counters enable row level security;
alter table public.billing_tax_registrations enable row level security;
alter table public.billing_tax_rates enable row level security;
alter table public.billing_discounts enable row level security;
alter table public.billing_coupons enable row level security;
alter table public.billing_coupon_redemptions enable row level security;
alter table public.billing_credit_accounts enable row level security;
alter table public.billing_credit_transactions enable row level security;
alter table public.billing_invoices enable row level security;
alter table public.billing_invoice_items enable row level security;
alter table public.billing_payments enable row level security;
alter table public.billing_payment_allocations enable row level security;
alter table public.billing_refunds enable row level security;
alter table public.billing_dunning_policies enable row level security;
alter table public.billing_dunning_cases enable row level security;
alter table public.billing_dunning_attempts enable row level security;
alter table public.billing_license_pools enable row level security;
alter table public.billing_license_assignments enable row level security;
alter table public.billing_webhook_inbox enable row level security;
alter table public.billing_event_outbox enable row level security;
alter table public.billing_logs enable row level security;

drop policy if exists billing_providers_select_policy on public.billing_providers;
create policy billing_providers_select_policy on public.billing_providers for select to authenticated using(status<>'archived');
drop policy if exists billing_providers_service_policy on public.billing_providers;
create policy billing_providers_service_policy on public.billing_providers for all to service_role using(true) with check(true);

do $$
declare t text;
begin
 foreach t in array array[
  'billing_products','billing_plans','billing_plan_prices','billing_addons','billing_addon_prices',
  'billing_entitlement_definitions','billing_plan_entitlements','billing_usage_meter_definitions','billing_tax_rates','billing_discounts','billing_coupons'
 ] loop
  execute format('drop policy if exists %I_select_policy on public.%I',t,t);
  execute format('create policy %I_select_policy on public.%I for select to authenticated using(
   organization_id is null or public.has_organization_permission(organization_id,''billing.view'')
   or public.has_organization_permission(organization_id,''billing.view_all''))',t,t);
  execute format('drop policy if exists %I_service_policy on public.%I',t,t);
  execute format('create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t);
 end loop;
 foreach t in array array[
  'billing_provider_accounts','billing_customers','billing_customer_tax_profiles',
  'billing_payment_methods','billing_subscriptions','billing_subscription_items','billing_subscription_change_requests',
  'billing_trials','billing_subscription_entitlement_overrides','billing_usage_events','billing_usage_aggregates',
  'billing_quota_counters','billing_tax_registrations','billing_coupon_redemptions','billing_credit_accounts',
  'billing_credit_transactions','billing_invoices','billing_invoice_items','billing_payments','billing_payment_allocations',
  'billing_refunds','billing_dunning_policies','billing_dunning_cases','billing_dunning_attempts','billing_license_pools',
  'billing_license_assignments','billing_webhook_inbox','billing_event_outbox','billing_logs'
 ] loop
  execute format('drop policy if exists %I_select_policy on public.%I',t,t);
  execute format('create policy %I_select_policy on public.%I for select to authenticated using(
   public.has_organization_permission(organization_id,''billing.view'')
   or public.has_organization_permission(organization_id,''billing.view_all''))',t,t);
  execute format('drop policy if exists %I_service_policy on public.%I',t,t);
  execute format('create policy %I_service_policy on public.%I for all to service_role using(true) with check(true)',t,t);
 end loop;
end $$;

drop policy if exists billing_license_assignments_self_select_policy on public.billing_license_assignments;
create policy billing_license_assignments_self_select_policy on public.billing_license_assignments
for select to authenticated using(user_id=auth.uid() or public.has_organization_permission(organization_id,'billing.view')
 or public.has_organization_permission(organization_id,'billing.view_all'));

-- 45. Grants
grant select on
 public.billing_providers,public.billing_provider_accounts,public.billing_products,public.billing_plans,
 public.billing_plan_prices,public.billing_addons,public.billing_addon_prices,public.billing_entitlement_definitions,
 public.billing_plan_entitlements,public.billing_customers,public.billing_customer_tax_profiles,
 public.billing_payment_methods,public.billing_subscriptions,public.billing_subscription_items,
 public.billing_subscription_change_requests,public.billing_trials,public.billing_subscription_entitlement_overrides,
 public.billing_usage_meter_definitions,public.billing_usage_events,public.billing_usage_aggregates,
 public.billing_quota_counters,public.billing_tax_registrations,public.billing_tax_rates,public.billing_discounts,
 public.billing_coupons,public.billing_coupon_redemptions,public.billing_credit_accounts,
 public.billing_credit_transactions,public.billing_invoices,public.billing_invoice_items,public.billing_payments,
 public.billing_payment_allocations,public.billing_refunds,public.billing_dunning_policies,public.billing_dunning_cases,
 public.billing_dunning_attempts,public.billing_license_pools,public.billing_license_assignments,
 public.billing_webhook_inbox,public.billing_event_outbox,public.billing_logs
to authenticated;

grant all on
 public.billing_providers,public.billing_provider_accounts,public.billing_products,public.billing_plans,
 public.billing_plan_prices,public.billing_addons,public.billing_addon_prices,public.billing_entitlement_definitions,
 public.billing_plan_entitlements,public.billing_customers,public.billing_customer_tax_profiles,
 public.billing_payment_methods,public.billing_subscriptions,public.billing_subscription_items,
 public.billing_subscription_change_requests,public.billing_trials,public.billing_subscription_entitlement_overrides,
 public.billing_usage_meter_definitions,public.billing_usage_events,public.billing_usage_aggregates,
 public.billing_quota_counters,public.billing_tax_registrations,public.billing_tax_rates,public.billing_discounts,
 public.billing_coupons,public.billing_coupon_redemptions,public.billing_credit_accounts,
 public.billing_credit_transactions,public.billing_invoices,public.billing_invoice_items,public.billing_payments,
 public.billing_payment_allocations,public.billing_refunds,public.billing_dunning_policies,public.billing_dunning_cases,
 public.billing_dunning_attempts,public.billing_license_pools,public.billing_license_assignments,
 public.billing_webhook_inbox,public.billing_event_outbox,public.billing_logs
to service_role;

do $$
declare r record;
begin
 for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in(
   'calculate_billing_period_end',
   'register_billing_provider_account','create_billing_customer','create_billing_product','create_billing_plan',
   'create_billing_plan_price','set_billing_plan_entitlement','start_billing_subscription',
   'update_billing_subscription_status','change_billing_subscription_plan','check_billing_entitlement',
   'consume_billing_quota','record_billing_usage_event','aggregate_billing_usage','generate_billing_invoice',
   'add_billing_invoice_item','finalize_billing_invoice','grant_billing_credit','apply_billing_credit_to_invoice',
   'record_billing_payment','record_billing_refund','assign_billing_license','revoke_billing_license',
   'get_billing_engine_health'
  )
 loop
  execute format('revoke all on function %s from public',r.signature);
  execute format('grant execute on function %s to authenticated,service_role',r.signature);
 end loop;
 for r in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in('publish_billing_event','sync_billing_subscription_license','ingest_billing_webhook','claim_billing_webhook','complete_billing_webhook','fail_billing_webhook')
 loop
  execute format('revoke all on function %s from public',r.signature);
  execute format('grant execute on function %s to service_role',r.signature);
 end loop;
end $$;

-- 46. Seed Razorpay
insert into public.billing_providers(
 provider_code,provider_name,provider_type,supports_subscriptions,supports_invoices,supports_payments,
 supports_refunds,supports_webhooks,supports_usage_billing,supported_currencies,supported_countries,
 status,is_system_provider,metadata
) values(
 'razorpay','Razorpay','subscription_platform',true,true,true,true,true,false,
 array['INR']::text[],array['IN']::text[],'active',true,jsonb_build_object('seeded_by_migration','032','default_provider',true)
) on conflict(provider_code) do update set provider_name=excluded.provider_name,provider_type=excluded.provider_type,
 supports_subscriptions=excluded.supports_subscriptions,supports_invoices=excluded.supports_invoices,
 supports_payments=excluded.supports_payments,supports_refunds=excluded.supports_refunds,
 supports_webhooks=excluded.supports_webhooks,supported_currencies=excluded.supported_currencies,
 supported_countries=excluded.supported_countries,status='active',updated_at=now();

-- 47. Seed SalesSetu product and plans
insert into public.billing_products(
 organization_id,product_code,product_name,description,product_type,status,is_system_product,tax_code,sac_hsn_code,metadata
)
select null,'salessetu','SalesSetu','AI-powered sales operating system for lead management, qualification, communication and conversion',
 'saas','active',true,'SAAS','998314',jsonb_build_object('seeded_by_migration','032')
where not exists(select 1 from public.billing_products where organization_id is null and product_code='salessetu');

with product_row as(select id from public.billing_products where organization_id is null and product_code='salessetu')
insert into public.billing_plans(
 organization_id,product_id,plan_code,plan_name,description,plan_tier,display_order,plan_type,status,
 is_system_plan,is_public,requires_sales_approval,default_trial_days,metadata
)
select null,product_row.id,v.plan_code,v.plan_name,v.description,v.tier,v.display_order,v.plan_type,'active',
 true,v.is_public,v.sales_approval,v.trial_days,jsonb_build_object('seeded_by_migration','032')
from product_row cross join(values
 ('starter','Starter','Essential lead management and automation for small teams',1,10,'standard',true,false,7),
 ('growth','Growth','Expanded automation, AI calling and team capacity',2,20,'standard',true,false,7),
 ('professional','Professional','Advanced analytics, integrations and higher limits',3,30,'premium',true,false,14),
 ('enterprise','Enterprise','Custom capacity, governance, security and support',4,40,'enterprise',false,true,14)
) v(plan_code,plan_name,description,tier,display_order,plan_type,is_public,sales_approval,trial_days)
where not exists(select 1 from public.billing_plans p where p.organization_id is null and p.product_id=product_row.id and p.plan_code=v.plan_code);

with plans as(
 select p.id,p.plan_code from public.billing_plans p join public.billing_products product on product.id=p.product_id
 where p.organization_id is null and product.organization_id is null and product.product_code='salessetu'
), provider as(select id from public.billing_providers where provider_code='razorpay')
insert into public.billing_plan_prices(
 organization_id,plan_id,provider_id,price_code,price_name,price_type,billing_interval,interval_count,currency,
 amount_minor,tax_inclusive,is_custom_price,status,metadata
)
select null,plans.id,provider.id,v.price_code,v.price_name,'flat',v.billing_interval,1,'INR',
 v.amount_minor,false,v.custom_price,'active',jsonb_build_object('seeded_by_migration','032','list_price',true)
from plans join(values
 ('starter','starter_monthly','Starter Monthly','month',99900::bigint,false),
 ('starter','starter_annual','Starter Annual','year',999000::bigint,false),
 ('growth','growth_monthly','Growth Monthly','month',299900::bigint,false),
 ('growth','growth_annual','Growth Annual','year',2999000::bigint,false),
 ('professional','professional_monthly','Professional Monthly','month',999900::bigint,false),
 ('professional','professional_annual','Professional Annual','year',9999000::bigint,false),
 ('enterprise','enterprise_custom','Enterprise Custom','year',null::bigint,true)
) v(plan_code,price_code,price_name,billing_interval,amount_minor,custom_price) on v.plan_code=plans.plan_code
cross join provider
where not exists(select 1 from public.billing_plan_prices pp where pp.organization_id is null and pp.plan_id=plans.id and pp.price_code=v.price_code);

-- 48. Seed entitlement definitions
insert into public.billing_entitlement_definitions(
 organization_id,entitlement_code,entitlement_name,description,entitlement_type,value_type,unit,reset_period,
 hard_limit_default,status,is_system_entitlement,metadata
)
select null,v.code,v.name,v.description,v.type,v.value_type,v.unit,v.reset_period,v.hard_limit,'active',true,
 jsonb_build_object('seeded_by_migration','032')
from(values
 ('users','Users','Maximum active users','limit','integer','users','none',true),
 ('projects','Projects','Maximum active projects','limit','integer','projects','none',true),
 ('branches','Branches','Maximum active branches','limit','integer','branches','none',true),
 ('leads_monthly','Monthly leads','Lead records processed per month','quota','integer','leads','monthly',true),
 ('ai_calls_monthly','Monthly AI calls','AI qualification calls per month','quota','integer','calls','monthly',true),
 ('whatsapp_messages_monthly','Monthly WhatsApp messages','Automated WhatsApp messages per month','quota','integer','messages','monthly',true),
 ('automation_runs_monthly','Monthly automation runs','Automation executions per month','quota','integer','runs','monthly',true),
 ('storage_gb','Storage','Allocated document and media storage','limit','numeric','GB','none',true),
 ('api_access','API access','Access to SalesSetu public APIs','feature','boolean',null,'none',true),
 ('customer_portal','Customer portal','Controlled customer portal access','feature','boolean',null,'none',true),
 ('advanced_analytics','Advanced analytics','Advanced analytics and BI dashboards','feature','boolean',null,'none',true),
 ('white_label','White label','Custom branding and white-label configuration','feature','boolean',null,'none',true),
 ('priority_support','Priority support','Priority support service level','support_level','text',null,'none',false),
 ('custom_integrations','Custom integrations','Custom integration entitlement','feature','boolean',null,'none',true),
 ('audit_retention_days','Audit retention','Audit log retention period','configuration','integer','days','none',true)
) v(code,name,description,type,value_type,unit,reset_period,hard_limit)
where not exists(select 1 from public.billing_entitlement_definitions d where d.organization_id is null and d.entitlement_code=v.code);

-- 49. Seed plan entitlement matrix
with plans as(
 select p.id plan_id,p.plan_code from public.billing_plans p join public.billing_products product on product.id=p.product_id
 where p.organization_id is null and product.product_code='salessetu'
), defs as(
 select id,entitlement_code from public.billing_entitlement_definitions where organization_id is null
), matrix as(
 select * from(values
 ('starter','users',true,false,3::bigint,null::numeric,null::boolean,null::text),
 ('starter','projects',true,false,3,null,null,null),('starter','branches',true,false,1,null,null,null),
 ('starter','leads_monthly',true,false,1000,null,null,null),('starter','ai_calls_monthly',true,false,100,null,null,null),
 ('starter','whatsapp_messages_monthly',true,false,1000,null,null,null),('starter','automation_runs_monthly',true,false,2000,null,null,null),
 ('starter','storage_gb',true,false,null,5,null,null),('starter','api_access',false,false,null,null,false,null),
 ('starter','customer_portal',true,false,null,null,true,null),('starter','advanced_analytics',false,false,null,null,false,null),
 ('starter','white_label',false,false,null,null,false,null),('starter','priority_support',true,false,null,null,null,'standard'),
 ('starter','custom_integrations',false,false,null,null,false,null),('starter','audit_retention_days',true,false,30,null,null,null),
 ('growth','users',true,false,10,null,null,null),('growth','projects',true,false,10,null,null,null),
 ('growth','branches',true,false,3,null,null,null),('growth','leads_monthly',true,false,5000,null,null,null),
 ('growth','ai_calls_monthly',true,false,750,null,null,null),('growth','whatsapp_messages_monthly',true,false,10000,null,null,null),
 ('growth','automation_runs_monthly',true,false,15000,null,null,null),('growth','storage_gb',true,false,null,25,null,null),
 ('growth','api_access',true,false,null,null,true,null),('growth','customer_portal',true,false,null,null,true,null),
 ('growth','advanced_analytics',true,false,null,null,true,null),('growth','white_label',false,false,null,null,false,null),
 ('growth','priority_support',true,false,null,null,null,'priority'),('growth','custom_integrations',false,false,null,null,false,null),
 ('growth','audit_retention_days',true,false,90,null,null,null),
 ('professional','users',true,false,30,null,null,null),('professional','projects',true,false,30,null,null,null),
 ('professional','branches',true,false,10,null,null,null),('professional','leads_monthly',true,false,25000,null,null,null),
 ('professional','ai_calls_monthly',true,false,5000,null,null,null),('professional','whatsapp_messages_monthly',true,false,50000,null,null,null),
 ('professional','automation_runs_monthly',true,false,100000,null,null,null),('professional','storage_gb',true,false,null,100,null,null),
 ('professional','api_access',true,false,null,null,true,null),('professional','customer_portal',true,false,null,null,true,null),
 ('professional','advanced_analytics',true,false,null,null,true,null),('professional','white_label',true,false,null,null,true,null),
 ('professional','priority_support',true,false,null,null,null,'premium'),('professional','custom_integrations',true,false,null,null,true,null),
 ('professional','audit_retention_days',true,false,365,null,null,null),
 ('enterprise','users',true,true,null,null,null,null),('enterprise','projects',true,true,null,null,null,null),
 ('enterprise','branches',true,true,null,null,null,null),('enterprise','leads_monthly',true,true,null,null,null,null),
 ('enterprise','ai_calls_monthly',true,true,null,null,null,null),('enterprise','whatsapp_messages_monthly',true,true,null,null,null,null),
 ('enterprise','automation_runs_monthly',true,true,null,null,null,null),('enterprise','storage_gb',true,true,null,null,null,null),
 ('enterprise','api_access',true,false,null,null,true,null),('enterprise','customer_portal',true,false,null,null,true,null),
 ('enterprise','advanced_analytics',true,false,null,null,true,null),('enterprise','white_label',true,false,null,null,true,null),
 ('enterprise','priority_support',true,false,null,null,null,'enterprise'),('enterprise','custom_integrations',true,false,null,null,true,null),
 ('enterprise','audit_retention_days',true,false,2555,null,null,null)
 ) m(plan_code,entitlement_code,enabled,unlimited,integer_value,numeric_value,boolean_value,text_value)
)
insert into public.billing_plan_entitlements(
 organization_id,plan_id,entitlement_definition_id,enabled,unlimited,boolean_value,integer_value,numeric_value,
 text_value,hard_limit,warning_threshold_percentage,metadata
)
select null,p.plan_id,d.id,m.enabled,m.unlimited,m.boolean_value,m.integer_value,m.numeric_value,m.text_value,true,80,
 jsonb_build_object('seeded_by_migration','032')
from matrix m join plans p on p.plan_code=m.plan_code join defs d on d.entitlement_code=m.entitlement_code
where not exists(select 1 from public.billing_plan_entitlements pe where pe.plan_id=p.plan_id and pe.entitlement_definition_id=d.id);

-- 50. Seed meters
with product as(select id from public.billing_products where organization_id is null and product_code='salessetu')
insert into public.billing_usage_meter_definitions(
 organization_id,product_id,entitlement_definition_id,meter_code,meter_name,description,event_name,
 quantity_field,aggregation_method,unit,reset_period,included_quantity,status,is_system_meter,metadata
)
select null,product.id,d.id,v.meter_code,v.meter_name,v.description,v.event_name,'quantity','sum',v.unit,
 'billing_period',0,'active',true,jsonb_build_object('seeded_by_migration','032')
from product cross join(values
 ('lead_processed','Lead processing','Leads processed by SalesSetu','billing.lead.processed','leads','leads_monthly'),
 ('ai_call_completed','AI calls','Completed AI qualification calls','billing.ai_call.completed','calls','ai_calls_monthly'),
 ('whatsapp_message_sent','WhatsApp messages','Automated WhatsApp messages sent','billing.whatsapp.sent','messages','whatsapp_messages_monthly'),
 ('automation_run','Automation runs','Automation engine executions','billing.automation.run','runs','automation_runs_monthly')
) v(meter_code,meter_name,description,event_name,unit,entitlement_code)
join public.billing_entitlement_definitions d on d.organization_id is null and d.entitlement_code=v.entitlement_code
where not exists(select 1 from public.billing_usage_meter_definitions m where m.organization_id is null and m.meter_code=v.meter_code);

-- 51. Seed informational India GST rates
insert into public.billing_tax_rates(
 organization_id,tax_code,tax_name,country_code,tax_type,rate_percentage,compound,inclusive,effective_from,status,metadata
)
select null,v.code,v.name,'IN',v.type,v.rate,false,false,date '2017-07-01','active',
 jsonb_build_object('seeded_by_migration','032','informational_default',true)
from(values('GST_CGST_9','CGST 9%','cgst',9.0::numeric),('GST_SGST_9','SGST 9%','sgst',9.0::numeric),
 ('GST_IGST_18','IGST 18%','igst',18.0::numeric)) v(code,name,type,rate)
where not exists(select 1 from public.billing_tax_rates r where r.organization_id is null and r.tax_code=v.code and r.effective_from=date '2017-07-01');

-- 52. Default dunning policy
insert into public.billing_dunning_policies(
 organization_id,policy_code,policy_name,description,grace_period_days,maximum_attempts,retry_schedule_days,
 suspend_after_days,cancel_after_days,send_reminders,reminder_channels,status,configuration,metadata
)
select o.id,'default','Default payment recovery','Default SaaS invoice recovery policy',3,4,array[1,3,5,7],7,30,true,
 array['email','whatsapp','in_app']::text[],'active',
 jsonb_build_object('open_case_on_payment_failure',true),
 jsonb_build_object('seeded_by_migration','032')
from public.organizations o
where not exists(select 1 from public.billing_dunning_policies p where p.organization_id=o.id and p.policy_code='default');

-- 53. Final validation
do $$
declare item text; missing text[]:='{}';
begin
 foreach item in array array[
  'billing_providers','billing_provider_accounts','billing_products','billing_plans','billing_plan_prices',
  'billing_addons','billing_addon_prices','billing_entitlement_definitions','billing_plan_entitlements',
  'billing_customers','billing_customer_tax_profiles','billing_payment_methods','billing_subscriptions',
  'billing_subscription_items','billing_subscription_change_requests','billing_trials',
  'billing_subscription_entitlement_overrides','billing_usage_meter_definitions','billing_usage_events',
  'billing_usage_aggregates','billing_quota_counters','billing_tax_registrations','billing_tax_rates',
  'billing_discounts','billing_coupons','billing_coupon_redemptions','billing_credit_accounts',
  'billing_credit_transactions','billing_invoices','billing_invoice_items','billing_payments',
  'billing_payment_allocations','billing_refunds','billing_dunning_policies','billing_dunning_cases',
  'billing_dunning_attempts','billing_license_pools','billing_license_assignments','billing_webhook_inbox',
  'billing_event_outbox','billing_logs'
 ] loop
  if not exists(select 1 from information_schema.tables where table_schema='public' and table_name=item) then missing:=array_append(missing,'table:'||item); end if;
 end loop;
 foreach item in array array[
  'calculate_billing_period_end','publish_billing_event','sync_billing_subscription_license',
  'register_billing_provider_account','create_billing_customer','create_billing_product','create_billing_plan',
  'create_billing_plan_price','set_billing_plan_entitlement','start_billing_subscription',
  'update_billing_subscription_status','change_billing_subscription_plan','check_billing_entitlement',
  'consume_billing_quota','record_billing_usage_event','aggregate_billing_usage','generate_billing_invoice',
  'add_billing_invoice_item','finalize_billing_invoice','grant_billing_credit','apply_billing_credit_to_invoice',
  'record_billing_payment','record_billing_refund','assign_billing_license','revoke_billing_license',
  'ingest_billing_webhook','claim_billing_webhook','complete_billing_webhook','fail_billing_webhook',
  'get_billing_engine_health'
 ] loop
  if not exists(select 1 from information_schema.routines where routine_schema='public' and routine_name=item) then missing:=array_append(missing,'function:'||item); end if;
 end loop;
 if cardinality(missing)>0 then raise exception '032 migration validation failed. Missing: %',array_to_string(missing,', '); end if;
end $$;

-- 54. Migration audit
insert into public.billing_logs(organization_id,log_level,event_name,message,source_type,log_data)
select o.id,'info','migration.032.completed','Billing, Subscription and Licensing Engine migration 032 completed','migration',
 jsonb_build_object(
  'migration','032_billing_subscription_licensing_engine','completed_at',now(),'default_provider','razorpay',
  'default_currency','INR',
  'seeded_plans',jsonb_build_array(
   jsonb_build_object('plan','starter','monthly_price_minor',99900),
   jsonb_build_object('plan','growth','monthly_price_minor',299900),
   jsonb_build_object('plan','professional','monthly_price_minor',999900),
   jsonb_build_object('plan','enterprise','pricing','custom')
  ),
  'modules',jsonb_build_array(
   'providers','provider_accounts','products','plans','prices','addons','customers','tax_profiles',
   'payment_methods','subscriptions','trials','subscription_changes','entitlements','usage_meters',
   'usage_events','usage_aggregation','quota_enforcement','tax','discounts','coupons','credits',
   'invoices','payments','refunds','dunning','license_pools','license_assignments',
   'provider_webhooks','analytics','health_monitoring','event_outbox'
  )
 )
from public.organizations o
where not exists(select 1 from public.billing_logs l where l.organization_id=o.id and l.event_name='migration.032.completed');

commit;