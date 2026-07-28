-- =========================================================
-- SalesSetu Enterprise
-- Migration: 007_customer_success
-- Part 1: Customer Success Data Foundation
-- =========================================================

begin;

-- =========================================================
-- 1. CUSTOMER SUCCESS PERMISSIONS
-- =========================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
values
  (
    'customers',
    'view',
    'customers.view',
    'View customers and customer-success records'
  ),
  (
    'customers',
    'create',
    'customers.create',
    'Create customer records'
  ),
  (
    'customers',
    'update',
    'customers.update',
    'Update customer records'
  ),
  (
    'customers',
    'delete',
    'customers.delete',
    'Delete customer records'
  ),
  (
    'customers',
    'view_all',
    'customers.view_all',
    'View all customers in an organization'
  ),
  (
    'customers',
    'manage_onboarding',
    'customers.manage_onboarding',
    'Manage customer onboarding and checklists'
  ),
  (
    'customers',
    'manage_documents',
    'customers.manage_documents',
    'Manage customer documents'
  ),
  (
    'customers',
    'manage_service_requests',
    'customers.manage_service_requests',
    'Manage customer service requests and complaints'
  ),
  (
    'customers',
    'manage_tasks',
    'customers.manage_tasks',
    'Manage customer-success tasks'
  ),
  (
    'customers',
    'manage_feedback',
    'customers.manage_feedback',
    'Record and manage customer feedback'
  ),
  (
    'customers',
    'manage_referrals',
    'customers.manage_referrals',
    'Manage referrals and referral rewards'
  ),
  (
    'customers',
    'manage_health',
    'customers.manage_health',
    'Manage customer health scores and risk status'
  ),
  (
    'customers',
    'manage_sla',
    'customers.manage_sla',
    'Manage customer-service SLA and escalations'
  )
on conflict (code) do nothing;

-- Platform and organization administrators receive
-- all customer-success permissions.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
cross join public.permissions p
where r.code in (
  'platform_admin',
  'organization_admin'
)
and p.module = 'customers'
on conflict (role_id, permission_id) do nothing;

-- Customer Success role receives operational access.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'customers.view',
    'customers.create',
    'customers.update',
    'customers.view_all',
    'customers.manage_onboarding',
    'customers.manage_documents',
    'customers.manage_service_requests',
    'customers.manage_tasks',
    'customers.manage_feedback',
    'customers.manage_referrals',
    'customers.manage_health',
    'customers.manage_sla'
  )
where r.code = 'customer_success'
on conflict (role_id, permission_id) do nothing;

-- Sales managers can view and update customers.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'customers.view',
    'customers.update',
    'customers.view_all',
    'customers.manage_tasks',
    'customers.manage_feedback',
    'customers.manage_referrals'
  )
where r.code = 'sales_manager'
on conflict (role_id, permission_id) do nothing;

-- Sales agents can view their customers and create tasks.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'customers.view',
    'customers.update',
    'customers.manage_tasks',
    'customers.manage_feedback',
    'customers.manage_referrals'
  )
where r.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;

-- Finance users receive customer and payment-related visibility.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code in (
    'customers.view',
    'customers.view_all',
    'customers.manage_service_requests'
  )
where r.code = 'finance_manager'
on conflict (role_id, permission_id) do nothing;

-- Viewer receives read-only access.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code = 'customers.view'
where r.code = 'viewer'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- 2. CUSTOMERS
-- One customer can originate from a lead and booking.
-- =========================================================

create table public.customers (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid
    references public.leads(id)
    on delete set null,

  booking_id uuid
    references public.bookings(id)
    on delete set null,

  customer_number text not null,

  -- -------------------------------------------------------
  -- Identity
  -- -------------------------------------------------------

  first_name text,
  last_name text,
  full_name text not null,

  phone text,
  normalized_phone text,

  alternate_phone text,
  normalized_alternate_phone text,

  whatsapp_number text,
  normalized_whatsapp_number text,

  email text,
  normalized_email text,

  date_of_birth date,
  anniversary_date date,

  gender text
    check (
      gender is null
      or gender in (
        'male',
        'female',
        'non_binary',
        'prefer_not_to_say',
        'other'
      )
    ),

  preferred_language text not null default 'hi-IN',

  preferred_contact_channel text
    check (
      preferred_contact_channel is null
      or preferred_contact_channel in (
        'phone',
        'whatsapp',
        'email',
        'sms',
        'in_person'
      )
    ),

  -- -------------------------------------------------------
  -- Customer lifecycle
  -- -------------------------------------------------------

  customer_status text not null default 'active'
    check (
      customer_status in (
        'prospective',
        'onboarding',
        'active',
        'at_risk',
        'inactive',
        'churned',
        'archived'
      )
    ),

  customer_stage text not null default 'new_customer'
    check (
      customer_stage in (
        'new_customer',
        'onboarding',
        'documentation',
        'payment_follow_up',
        'service_active',
        'possession_pending',
        'possession_completed',
        'relationship_management',
        'closed'
      )
    ),

  customer_type text not null default 'buyer'
    check (
      customer_type in (
        'buyer',
        'investor',
        'tenant',
        'landlord',
        'channel_partner',
        'referrer',
        'other'
      )
    ),

  onboarding_status text not null default 'not_started'
    check (
      onboarding_status in (
        'not_started',
        'in_progress',
        'blocked',
        'completed',
        'cancelled'
      )
    ),

  onboarding_started_at timestamptz,
  onboarding_completed_at timestamptz,

  -- -------------------------------------------------------
  -- Ownership and assignment
  -- -------------------------------------------------------

  relationship_manager_id uuid
    references auth.users(id)
    on delete set null,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz,

  escalation_manager_id uuid
    references auth.users(id)
    on delete set null,

  -- -------------------------------------------------------
  -- Customer health
  -- -------------------------------------------------------

  health_status text not null default 'unknown'
    check (
      health_status in (
        'unknown',
        'healthy',
        'stable',
        'attention_required',
        'at_risk',
        'critical',
        'churned'
      )
    ),

  health_score numeric(5,2)
    check (
      health_score is null
      or (
        health_score >= 0
        and health_score <= 100
      )
    ),

  risk_reason text,
  risk_detected_at timestamptz,

  last_engagement_at timestamptz,
  next_engagement_at timestamptz,

  -- -------------------------------------------------------
  -- Communication preferences
  -- -------------------------------------------------------

  consent_status text not null default 'unknown'
    check (
      consent_status in (
        'unknown',
        'granted',
        'withdrawn',
        'not_required'
      )
    ),

  consent_at timestamptz,

  do_not_call boolean not null default false,
  do_not_email boolean not null default false,
  do_not_whatsapp boolean not null default false,
  do_not_sms boolean not null default false,

  -- -------------------------------------------------------
  -- Customer value and advocacy
  -- -------------------------------------------------------

  lifetime_value numeric(18,2)
    check (
      lifetime_value is null
      or lifetime_value >= 0
    ),

  referral_count integer not null default 0
    check (referral_count >= 0),

  satisfaction_score numeric(5,2)
    check (
      satisfaction_score is null
      or (
        satisfaction_score >= 0
        and satisfaction_score <= 100
      )
    ),

  nps_score integer
    check (
      nps_score is null
      or (
        nps_score >= 0
        and nps_score <= 10
      )
    ),

  -- -------------------------------------------------------
  -- Flexible data
  -- -------------------------------------------------------

  notes text,

  tags text[] not null default '{}'::text[],

  custom_fields jsonb not null default '{}'::jsonb,

  metadata jsonb not null default '{}'::jsonb,

  -- -------------------------------------------------------
  -- Audit and soft deletion
  -- -------------------------------------------------------

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  deleted_by uuid
    references auth.users(id)
    on delete set null,

  deleted_at timestamptz,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint customers_org_number_unique
    unique (
      organization_id,
      customer_number
    )
);

create index customers_organization_idx
  on public.customers(organization_id);

create index customers_lead_idx
  on public.customers(lead_id)
  where lead_id is not null;

create index customers_booking_idx
  on public.customers(booking_id)
  where booking_id is not null;

create index customers_status_idx
  on public.customers(
    organization_id,
    customer_status,
    created_at desc
  )
  where deleted_at is null;

create index customers_stage_idx
  on public.customers(
    organization_id,
    customer_stage
  )
  where deleted_at is null;

create index customers_manager_idx
  on public.customers(
    organization_id,
    relationship_manager_id,
    customer_status
  )
  where deleted_at is null;

create index customers_health_idx
  on public.customers(
    organization_id,
    health_status,
    health_score
  )
  where deleted_at is null;

create index customers_next_engagement_idx
  on public.customers(
    organization_id,
    next_engagement_at
  )
  where deleted_at is null;

create index customers_normalized_phone_idx
  on public.customers(
    organization_id,
    normalized_phone
  )
  where normalized_phone is not null
    and deleted_at is null;

create index customers_normalized_email_idx
  on public.customers(
    organization_id,
    normalized_email
  )
  where normalized_email is not null
    and deleted_at is null;

create index customers_tags_gin_idx
  on public.customers
  using gin(tags);

create index customers_custom_fields_gin_idx
  on public.customers
  using gin(custom_fields);

create trigger customers_set_updated_at
before update on public.customers
for each row
execute function public.set_updated_at();

-- =========================================================
-- 3. CUSTOMER ADDRESSES
-- =========================================================

create table public.customer_addresses (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  address_type text not null default 'residential'
    check (
      address_type in (
        'residential',
        'permanent',
        'correspondence',
        'office',
        'property',
        'other'
      )
    ),

  address_line_1 text not null,
  address_line_2 text,

  landmark text,
  city text not null,
  state text,
  postal_code text,
  country text not null default 'India',

  latitude numeric(10,7)
    check (
      latitude is null
      or (
        latitude >= -90
        and latitude <= 90
      )
    ),

  longitude numeric(10,7)
    check (
      longitude is null
      or (
        longitude >= -180
        and longitude <= 180
      )
    ),

  is_primary boolean not null default false,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

create index customer_addresses_org_idx
  on public.customer_addresses(organization_id);

create index customer_addresses_customer_idx
  on public.customer_addresses(
    customer_id,
    address_type
  );

create unique index customer_addresses_primary_idx
  on public.customer_addresses(customer_id)
  where is_primary = true;

create trigger customer_addresses_set_updated_at
before update on public.customer_addresses
for each row
execute function public.set_updated_at();

-- =========================================================
-- 4. CUSTOMER CONTACTS AND RELATED PERSONS
-- =========================================================

create table public.customer_contacts (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  contact_type text not null
    check (
      contact_type in (
        'spouse',
        'family_member',
        'nominee',
        'co_applicant',
        'legal_representative',
        'financial_advisor',
        'emergency_contact',
        'other'
      )
    ),

  full_name text not null,

  phone text,
  normalized_phone text,

  email text,
  normalized_email text,

  relationship text,

  date_of_birth date,

  is_primary_contact boolean not null default false,

  notes text,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

create index customer_contacts_org_idx
  on public.customer_contacts(organization_id);

create index customer_contacts_customer_idx
  on public.customer_contacts(
    customer_id,
    contact_type
  );

create index customer_contacts_phone_idx
  on public.customer_contacts(
    organization_id,
    normalized_phone
  )
  where normalized_phone is not null;

create trigger customer_contacts_set_updated_at
before update on public.customer_contacts
for each row
execute function public.set_updated_at();

-- =========================================================
-- 5. CUSTOMER DOCUMENTS
-- =========================================================

create table public.customer_documents (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  booking_id uuid
    references public.bookings(id)
    on delete set null,

  document_name text not null,

  document_type text not null,

  document_status text not null default 'requested'
    check (
      document_status in (
        'requested',
        'uploaded',
        'under_review',
        'verified',
        'rejected',
        'expired'
      )
    ),

  storage_bucket text,
  storage_path text,

  mime_type text,

  file_size_bytes bigint
    check (
      file_size_bytes is null
      or file_size_bytes >= 0
    ),

  verified boolean not null default false,

  verified_by uuid
    references auth.users(id)
    on delete set null,

  verified_at timestamptz,

  rejection_reason text,

  uploaded_by uuid
    references auth.users(id)
    on delete set null,

  requested_at timestamptz,

  uploaded_at timestamptz,

  expiry_date date,

  notes text,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

create index customer_documents_org_idx
  on public.customer_documents(organization_id);

create index customer_documents_customer_idx
  on public.customer_documents(
    customer_id,
    created_at desc
  );

create index customer_documents_booking_idx
  on public.customer_documents(booking_id)
  where booking_id is not null;

create index customer_documents_status_idx
  on public.customer_documents(
    organization_id,
    document_status
  );

create trigger customer_documents_set_updated_at
before update on public.customer_documents
for each row
execute function public.set_updated_at();

-- =========================================================
-- 6. CUSTOMER ONBOARDING
-- =========================================================

create table public.customer_onboardings (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  booking_id uuid
    references public.bookings(id)
    on delete set null,

  onboarding_type text not null default 'post_booking'
    check (
      onboarding_type in (
        'post_booking',
        'possession',
        'property_management',
        'tenant',
        'investor',
        'custom'
      )
    ),

  status text not null default 'not_started'
    check (
      status in (
        'not_started',
        'in_progress',
        'blocked',
        'completed',
        'cancelled'
      )
    ),

  progress_percentage numeric(5,2)
    not null default 0
    check (
      progress_percentage >= 0
      and progress_percentage <= 100
    ),

  assigned_to uuid
    references auth.users(id)
    on delete set null,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz,

  started_at timestamptz,

  expected_completion_at timestamptz,

  completed_at timestamptz,

  blocked_reason text,

  completion_notes text,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

create index customer_onboardings_org_idx
  on public.customer_onboardings(organization_id);

create index customer_onboardings_customer_idx
  on public.customer_onboardings(
    customer_id,
    created_at desc
  );

create index customer_onboardings_status_idx
  on public.customer_onboardings(
    organization_id,
    status,
    expected_completion_at
  );

create index customer_onboardings_assignee_idx
  on public.customer_onboardings(
    organization_id,
    assigned_to,
    status
  );

create trigger customer_onboardings_set_updated_at
before update on public.customer_onboardings
for each row
execute function public.set_updated_at();

-- =========================================================
-- 7. ONBOARDING CHECKLIST ITEMS
-- =========================================================

create table public.customer_onboarding_items (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  onboarding_id uuid not null
    references public.customer_onboardings(id)
    on delete cascade,

  parent_item_id uuid
    references public.customer_onboarding_items(id)
    on delete set null,

  item_code text,

  title text not null,

  description text,

  item_type text not null default 'task'
    check (
      item_type in (
        'task',
        'document',
        'payment',
        'call',
        'meeting',
        'verification',
        'approval',
        'other'
      )
    ),

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'in_progress',
        'blocked',
        'completed',
        'skipped',
        'cancelled'
      )
    ),

  priority text not null default 'normal'
    check (
      priority in (
        'low',
        'normal',
        'high',
        'urgent'
      )
    ),

  sequence_number integer
    check (
      sequence_number is null
      or sequence_number >= 0
    ),

  is_required boolean not null default true,

  assigned_to uuid
    references auth.users(id)
    on delete set null,

  due_at timestamptz,

  started_at timestamptz,

  completed_at timestamptz,

  completion_notes text,

  blocked_reason text,

  related_document_id uuid
    references public.customer_documents(id)
    on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint onboarding_items_not_parent_self
    check (
      parent_item_id is null
      or parent_item_id <> id
    ),

  constraint onboarding_items_time_valid
    check (
      started_at is null
      or completed_at is null
      or completed_at >= started_at
    )
);

create index customer_onboarding_items_org_idx
  on public.customer_onboarding_items(organization_id);

create index customer_onboarding_items_onboarding_idx
  on public.customer_onboarding_items(
    onboarding_id,
    sequence_number
  );

create index customer_onboarding_items_assignee_idx
  on public.customer_onboarding_items(
    organization_id,
    assigned_to,
    status,
    due_at
  );

create index customer_onboarding_items_due_idx
  on public.customer_onboarding_items(
    organization_id,
    due_at
  )
  where status in (
    'pending',
    'in_progress',
    'blocked'
  );

create trigger customer_onboarding_items_set_updated_at
before update on public.customer_onboarding_items
for each row
execute function public.set_updated_at();

-- =========================================================
-- 8. SERVICE REQUEST CATEGORIES
-- =========================================================

create table public.customer_service_categories (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  name text not null,

  code text not null,

  description text,

  default_priority text not null default 'normal'
    check (
      default_priority in (
        'low',
        'normal',
        'high',
        'urgent'
      )
    ),

  default_sla_minutes integer
    check (
      default_sla_minutes is null
      or default_sla_minutes > 0
    ),

  escalation_after_minutes integer
    check (
      escalation_after_minutes is null
      or escalation_after_minutes > 0
    ),

  assigned_team text,

  is_active boolean not null default true,

  settings jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint customer_service_categories_org_code_unique
    unique (
      organization_id,
      code
    )
);

create index customer_service_categories_org_idx
  on public.customer_service_categories(organization_id);

create index customer_service_categories_active_idx
  on public.customer_service_categories(
    organization_id,
    is_active
  );

create trigger customer_service_categories_set_updated_at
before update on public.customer_service_categories
for each row
execute function public.set_updated_at();

-- =========================================================
-- 9. CUSTOMER SERVICE REQUESTS
-- =========================================================

create table public.customer_service_requests (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  booking_id uuid
    references public.bookings(id)
    on delete set null,

  category_id uuid
    references public.customer_service_categories(id)
    on delete set null,

  request_number text not null,

  request_type text not null default 'service_request'
    check (
      request_type in (
        'service_request',
        'complaint',
        'query',
        'document_request',
        'payment_query',
        'possession_query',
        'maintenance',
        'legal',
        'technical',
        'other'
      )
    ),

  channel text
    check (
      channel is null
      or channel in (
        'phone',
        'whatsapp',
        'email',
        'portal',
        'mobile_app',
        'in_person',
        'system',
        'other'
      )
    ),

  subject text not null,

  description text,

  status text not null default 'open'
    check (
      status in (
        'open',
        'acknowledged',
        'assigned',
        'in_progress',
        'waiting_for_customer',
        'waiting_for_third_party',
        'resolved',
        'closed',
        'cancelled',
        'reopened'
      )
    ),

  priority text not null default 'normal'
    check (
      priority in (
        'low',
        'normal',
        'high',
        'urgent'
      )
    ),

  assigned_to uuid
    references auth.users(id)
    on delete set null,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz,

  requested_at timestamptz not null default now(),

  acknowledged_at timestamptz,

  first_response_at timestamptz,

  due_at timestamptz,

  resolved_at timestamptz,

  closed_at timestamptz,

  resolution_summary text,

  resolution_code text,

  customer_confirmation_status text
    check (
      customer_confirmation_status is null
      or customer_confirmation_status in (
        'pending',
        'accepted',
        'rejected',
        'not_required'
      )
    ),

  reopened_count integer not null default 0
    check (reopened_count >= 0),

  sla_status text not null default 'not_applicable'
    check (
      sla_status in (
        'not_applicable',
        'within_sla',
        'at_risk',
        'breached',
        'resolved'
      )
    ),

  sla_due_at timestamptz,

  escalation_level integer not null default 0
    check (escalation_level >= 0),

  escalated_to uuid
    references auth.users(id)
    on delete set null,

  escalated_at timestamptz,

  escalation_reason text,

  satisfaction_rating integer
    check (
      satisfaction_rating is null
      or (
        satisfaction_rating >= 1
        and satisfaction_rating <= 5
      )
    ),

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  deleted_by uuid
    references auth.users(id)
    on delete set null,

  deleted_at timestamptz,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint customer_service_requests_org_number_unique
    unique (
      organization_id,
      request_number
    )
);

create index customer_service_requests_org_idx
  on public.customer_service_requests(organization_id);

create index customer_service_requests_customer_idx
  on public.customer_service_requests(
    customer_id,
    created_at desc
  );

create index customer_service_requests_booking_idx
  on public.customer_service_requests(booking_id)
  where booking_id is not null;

create index customer_service_requests_status_idx
  on public.customer_service_requests(
    organization_id,
    status,
    priority,
    created_at desc
  )
  where deleted_at is null;

create index customer_service_requests_assignee_idx
  on public.customer_service_requests(
    organization_id,
    assigned_to,
    status,
    due_at
  )
  where deleted_at is null;

create index customer_service_requests_sla_idx
  on public.customer_service_requests(
    organization_id,
    sla_status,
    sla_due_at
  )
  where deleted_at is null;

create index customer_service_requests_category_idx
  on public.customer_service_requests(
    organization_id,
    category_id
  )
  where deleted_at is null;

create trigger customer_service_requests_set_updated_at
before update on public.customer_service_requests
for each row
execute function public.set_updated_at();

-- =========================================================
-- 10. SERVICE REQUEST COMMENTS AND NOTES
-- =========================================================

create table public.customer_service_request_comments (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  service_request_id uuid not null
    references public.customer_service_requests(id)
    on delete cascade,

  comment_type text not null default 'internal_note'
    check (
      comment_type in (
        'internal_note',
        'customer_message',
        'agent_response',
        'status_update',
        'system_event',
        'resolution_note'
      )
    ),

  message text not null,

  is_internal boolean not null default true,

  attachments jsonb not null default '[]'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now()
);

create index customer_service_request_comments_org_idx
  on public.customer_service_request_comments(organization_id);

create index customer_service_request_comments_request_idx
  on public.customer_service_request_comments(
    service_request_id,
    created_at
  );

-- =========================================================
-- 11. CUSTOMER SUCCESS TASKS
-- =========================================================

create table public.customer_success_tasks (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  service_request_id uuid
    references public.customer_service_requests(id)
    on delete set null,

  onboarding_id uuid
    references public.customer_onboardings(id)
    on delete set null,

  title text not null,

  description text,

  task_type text not null default 'general'
    check (
      task_type in (
        'onboarding',
        'call',
        'whatsapp',
        'email',
        'meeting',
        'document',
        'payment_reminder',
        'service_request',
        'feedback',
        'referral',
        'possession',
        'relationship',
        'general',
        'other'
      )
    ),

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'in_progress',
        'completed',
        'cancelled',
        'overdue',
        'blocked'
      )
    ),

  priority text not null default 'normal'
    check (
      priority in (
        'low',
        'normal',
        'high',
        'urgent'
      )
    ),

  assigned_to uuid
    references auth.users(id)
    on delete set null,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz,

  due_at timestamptz not null,

  reminder_at timestamptz,

  reminder_sent_at timestamptz,

  started_at timestamptz,

  completed_at timestamptz,

  completion_notes text,

  recurrence_rule text,

  is_automated boolean not null default false,

  automation_workflow_id text,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  deleted_by uuid
    references auth.users(id)
    on delete set null,

  deleted_at timestamptz,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint customer_success_tasks_time_valid
    check (
      started_at is null
      or completed_at is null
      or completed_at >= started_at
    ),

  constraint customer_success_tasks_reminder_valid
    check (
      reminder_at is null
      or reminder_at <= due_at
    )
);

create index customer_success_tasks_org_idx
  on public.customer_success_tasks(organization_id);

create index customer_success_tasks_customer_idx
  on public.customer_success_tasks(
    customer_id,
    due_at
  );

create index customer_success_tasks_assignee_idx
  on public.customer_success_tasks(
    organization_id,
    assigned_to,
    status,
    due_at
  )
  where deleted_at is null;

create index customer_success_tasks_due_idx
  on public.customer_success_tasks(
    organization_id,
    due_at
  )
  where deleted_at is null
    and status in (
      'pending',
      'in_progress',
      'blocked'
    );

create index customer_success_tasks_reminder_idx
  on public.customer_success_tasks(reminder_at)
  where deleted_at is null
    and reminder_sent_at is null
    and status in (
      'pending',
      'in_progress'
    );

create trigger customer_success_tasks_set_updated_at
before update on public.customer_success_tasks
for each row
execute function public.set_updated_at();

-- =========================================================
-- 12. CUSTOMER FEEDBACK
-- =========================================================

create table public.customer_feedback (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  booking_id uuid
    references public.bookings(id)
    on delete set null,

  service_request_id uuid
    references public.customer_service_requests(id)
    on delete set null,

  feedback_type text not null
    check (
      feedback_type in (
        'csat',
        'nps',
        'ces',
        'service_feedback',
        'onboarding_feedback',
        'possession_feedback',
        'agent_feedback',
        'project_feedback',
        'general'
      )
    ),

  channel text
    check (
      channel is null
      or channel in (
        'phone',
        'whatsapp',
        'email',
        'survey',
        'portal',
        'in_person',
        'other'
      )
    ),

  score numeric(5,2),

  rating integer
    check (
      rating is null
      or (
        rating >= 1
        and rating <= 5
      )
    ),

  nps_score integer
    check (
      nps_score is null
      or (
        nps_score >= 0
        and nps_score <= 10
      )
    ),

  sentiment text
    check (
      sentiment is null
      or sentiment in (
        'positive',
        'neutral',
        'negative',
        'mixed',
        'unknown'
      )
    ),

  feedback_text text,

  positive_points text[] not null default '{}'::text[],

  improvement_points text[] not null default '{}'::text[],

  requires_follow_up boolean not null default false,

  follow_up_completed boolean not null default false,

  submitted_at timestamptz not null default now(),

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now()
);

create index customer_feedback_org_idx
  on public.customer_feedback(organization_id);

create index customer_feedback_customer_idx
  on public.customer_feedback(
    customer_id,
    submitted_at desc
  );

create index customer_feedback_type_idx
  on public.customer_feedback(
    organization_id,
    feedback_type,
    submitted_at desc
  );

create index customer_feedback_follow_up_idx
  on public.customer_feedback(
    organization_id,
    requires_follow_up,
    follow_up_completed
  )
  where requires_follow_up = true;

-- =========================================================
-- 13. CUSTOMER REFERRALS
-- =========================================================

create table public.customer_referrals (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  referring_customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  referred_lead_id uuid
    references public.leads(id)
    on delete set null,

  converted_customer_id uuid
    references public.customers(id)
    on delete set null,

  referral_code text,

  referred_name text not null,

  referred_phone text,

  normalized_referred_phone text,

  referred_email text,

  normalized_referred_email text,

  referral_status text not null default 'submitted'
    check (
      referral_status in (
        'submitted',
        'contacted',
        'qualified',
        'site_visit',
        'converted',
        'rejected',
        'duplicate',
        'cancelled'
      )
    ),

  referral_source text,

  reward_status text not null default 'not_applicable'
    check (
      reward_status in (
        'not_applicable',
        'pending',
        'approved',
        'paid',
        'cancelled'
      )
    ),

  reward_type text,

  reward_value numeric(18,2)
    check (
      reward_value is null
      or reward_value >= 0
    ),

  reward_currency text not null default 'INR',

  reward_notes text,

  converted_at timestamptz,

  rewarded_at timestamptz,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now()
);

create index customer_referrals_org_idx
  on public.customer_referrals(organization_id);

create index customer_referrals_customer_idx
  on public.customer_referrals(
    referring_customer_id,
    created_at desc
  );

create index customer_referrals_lead_idx
  on public.customer_referrals(referred_lead_id)
  where referred_lead_id is not null;

create index customer_referrals_status_idx
  on public.customer_referrals(
    organization_id,
    referral_status,
    created_at desc
  );

create index customer_referrals_reward_idx
  on public.customer_referrals(
    organization_id,
    reward_status
  );

create index customer_referrals_phone_idx
  on public.customer_referrals(
    organization_id,
    normalized_referred_phone
  )
  where normalized_referred_phone is not null;

create trigger customer_referrals_set_updated_at
before update on public.customer_referrals
for each row
execute function public.set_updated_at();

-- =========================================================
-- 14. CUSTOMER HEALTH HISTORY
-- =========================================================

create table public.customer_health_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  previous_health_status text,

  new_health_status text not null,

  previous_health_score numeric(5,2),

  new_health_score numeric(5,2),

  reason text,

  signals jsonb not null default '{}'::jsonb,

  calculated_by text not null default 'manual'
    check (
      calculated_by in (
        'manual',
        'rule_engine',
        'ai',
        'system'
      )
    ),

  changed_by uuid
    references auth.users(id)
    on delete set null,

  changed_at timestamptz not null default now()
);

create index customer_health_history_org_idx
  on public.customer_health_history(organization_id);

create index customer_health_history_customer_idx
  on public.customer_health_history(
    customer_id,
    changed_at desc
  );

create index customer_health_history_status_idx
  on public.customer_health_history(
    organization_id,
    new_health_status,
    changed_at desc
  );

-- =========================================================
-- 15. CUSTOMER ACTIVITY TIMELINE
-- =========================================================

create table public.customer_activities (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  customer_id uuid not null
    references public.customers(id)
    on delete cascade,

  booking_id uuid
    references public.bookings(id)
    on delete set null,

  service_request_id uuid
    references public.customer_service_requests(id)
    on delete set null,

  activity_type text not null
    check (
      activity_type in (
        'call',
        'whatsapp',
        'email',
        'sms',
        'meeting',
        'note',
        'document',
        'payment',
        'onboarding',
        'service_request',
        'feedback',
        'referral',
        'health_change',
        'assignment',
        'system_event',
        'other'
      )
    ),

  direction text
    check (
      direction is null
      or direction in (
        'inbound',
        'outbound',
        'internal'
      )
    ),

  status text not null default 'completed'
    check (
      status in (
        'scheduled',
        'in_progress',
        'completed',
        'failed',
        'cancelled'
      )
    ),

  subject text,

  description text,

  outcome text,

  performed_by uuid
    references auth.users(id)
    on delete set null,

  started_at timestamptz,

  completed_at timestamptz,

  is_automated boolean not null default false,

  ai_generated boolean not null default false,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  constraint customer_activities_time_valid
    check (
      started_at is null
      or completed_at is null
      or completed_at >= started_at
    )
);

create index customer_activities_org_idx
  on public.customer_activities(organization_id);

create index customer_activities_customer_idx
  on public.customer_activities(
    customer_id,
    created_at desc
  );

create index customer_activities_type_idx
  on public.customer_activities(
    organization_id,
    activity_type,
    created_at desc
  );

create index customer_activities_performed_by_idx
  on public.customer_activities(
    organization_id,
    performed_by,
    created_at desc
  );

-- =========================================================
-- 16. ENABLE RLS
-- Policies will be added in Part 2.
-- =========================================================

alter table public.customers
  enable row level security;

alter table public.customer_addresses
  enable row level security;

alter table public.customer_contacts
  enable row level security;

alter table public.customer_documents
  enable row level security;

alter table public.customer_onboardings
  enable row level security;

alter table public.customer_onboarding_items
  enable row level security;

alter table public.customer_service_categories
  enable row level security;

alter table public.customer_service_requests
  enable row level security;

alter table public.customer_service_request_comments
  enable row level security;

alter table public.customer_success_tasks
  enable row level security;

alter table public.customer_feedback
  enable row level security;

alter table public.customer_referrals
  enable row level security;

alter table public.customer_health_history
  enable row level security;

alter table public.customer_activities
  enable row level security;

  -- =========================================================
-- SalesSetu Enterprise
-- Migration: 007_customer_success
-- Part 2: Validation, automation, lifecycle, SLA and RLS
-- =========================================================

-- =========================================================
-- 17. SERVICE REQUEST STATUS HISTORY
-- =========================================================

create table public.customer_service_request_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  service_request_id uuid not null
    references public.customer_service_requests(id)
    on delete cascade,

  previous_status text,
  new_status text not null,

  previous_assignee_id uuid
    references auth.users(id)
    on delete set null,

  new_assignee_id uuid
    references auth.users(id)
    on delete set null,

  previous_priority text,
  new_priority text,

  previous_sla_status text,
  new_sla_status text,

  change_type text not null default 'status_change'
    check (
      change_type in (
        'created',
        'status_change',
        'assignment',
        'priority_change',
        'sla_change',
        'escalation',
        'resolution',
        'reopen',
        'other'
      )
    ),

  change_reason text,

  changed_by uuid
    references auth.users(id)
    on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  changed_at timestamptz not null default now()
);

create index customer_service_request_history_org_idx
  on public.customer_service_request_history(organization_id);

create index customer_service_request_history_request_idx
  on public.customer_service_request_history(
    service_request_id,
    changed_at desc
  );

create index customer_service_request_history_status_idx
  on public.customer_service_request_history(
    organization_id,
    new_status,
    changed_at desc
  );

alter table public.customer_service_request_history
  enable row level security;

-- =========================================================
-- 18. CUSTOMER CONTACT NORMALIZATION
-- =========================================================

create or replace function public.set_customer_normalized_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.normalized_phone :=
    public.normalize_phone(new.phone);

  new.normalized_alternate_phone :=
    public.normalize_phone(new.alternate_phone);

  new.normalized_whatsapp_number :=
    public.normalize_phone(new.whatsapp_number);

  new.normalized_email :=
    public.normalize_email(new.email);

  if new.full_name is null
    or trim(new.full_name) = '' then

    new.full_name := nullif(
      trim(
        concat_ws(
          ' ',
          new.first_name,
          new.last_name
        )
      ),
      ''
    );

  end if;

  if new.full_name is null then
    raise exception 'Customer full name is required';
  end if;

  return new;
end;
$$;

create trigger customers_set_normalized_fields
before insert or update of
  first_name,
  last_name,
  full_name,
  phone,
  alternate_phone,
  whatsapp_number,
  email
on public.customers
for each row
execute function public.set_customer_normalized_fields();

create or replace function public.set_customer_contact_normalized_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.normalized_phone :=
    public.normalize_phone(new.phone);

  new.normalized_email :=
    public.normalize_email(new.email);

  return new;
end;
$$;

create trigger customer_contacts_set_normalized_fields
before insert or update of
  phone,
  email
on public.customer_contacts
for each row
execute function public.set_customer_contact_normalized_fields();

create or replace function public.set_customer_referral_normalized_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.normalized_referred_phone :=
    public.normalize_phone(new.referred_phone);

  new.normalized_referred_email :=
    public.normalize_email(new.referred_email);

  return new;
end;
$$;

create trigger customer_referrals_set_normalized_fields
before insert or update of
  referred_phone,
  referred_email
on public.customer_referrals
for each row
execute function public.set_customer_referral_normalized_fields();

-- =========================================================
-- 19. VALIDATE CUSTOMER RELATIONS
-- =========================================================

create or replace function public.validate_customer_relations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.lead_id is not null
    and not exists (
      select 1
      from public.leads l
      where l.id = new.lead_id
        and l.organization_id = new.organization_id
        and l.deleted_at is null
    ) then

    raise exception
      'Lead must belong to the customer organization';

  end if;

  if new.booking_id is not null
    and not exists (
      select 1
      from public.bookings b
      where b.id = new.booking_id
        and b.organization_id = new.organization_id
        and (
          new.lead_id is null
          or b.lead_id = new.lead_id
        )
    ) then

    raise exception
      'Booking must belong to the customer organization';

  end if;

  if new.relationship_manager_id is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.relationship_manager_id
        and om.membership_status = 'active'
    ) then

    raise exception
      'Relationship manager must be an active organization member';

  end if;

  if new.escalation_manager_id is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.escalation_manager_id
        and om.membership_status = 'active'
    ) then

    raise exception
      'Escalation manager must be an active organization member';

  end if;

  return new;
end;
$$;

create trigger customers_validate_relations
before insert or update of
  organization_id,
  lead_id,
  booking_id,
  relationship_manager_id,
  escalation_manager_id
on public.customers
for each row
execute function public.validate_customer_relations();

-- =========================================================
-- 20. GENERIC CUSTOMER CHILD VALIDATION
-- =========================================================

create or replace function public.validate_customer_child()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.customers c
    where c.id = new.customer_id
      and c.organization_id = new.organization_id
      and c.deleted_at is null
  ) then

    raise exception
      'Customer must belong to the same organization';

  end if;

  return new;
end;
$$;

create trigger customer_addresses_validate_customer
before insert or update of
  organization_id,
  customer_id
on public.customer_addresses
for each row
execute function public.validate_customer_child();

create trigger customer_contacts_validate_customer
before insert or update of
  organization_id,
  customer_id
on public.customer_contacts
for each row
execute function public.validate_customer_child();

create trigger customer_documents_validate_customer
before insert or update of
  organization_id,
  customer_id
on public.customer_documents
for each row
execute function public.validate_customer_child();

create trigger customer_onboardings_validate_customer
before insert or update of
  organization_id,
  customer_id
on public.customer_onboardings
for each row
execute function public.validate_customer_child();

create trigger customer_service_requests_validate_customer
before insert or update of
  organization_id,
  customer_id
on public.customer_service_requests
for each row
execute function public.validate_customer_child();

create trigger customer_success_tasks_validate_customer
before insert or update of
  organization_id,
  customer_id
on public.customer_success_tasks
for each row
execute function public.validate_customer_child();

create trigger customer_feedback_validate_customer
before insert or update of
  organization_id,
  customer_id
on public.customer_feedback
for each row
execute function public.validate_customer_child();

create trigger customer_activities_validate_customer
before insert or update of
  organization_id,
  customer_id
on public.customer_activities
for each row
execute function public.validate_customer_child();

-- =========================================================
-- 21. VALIDATE BOOKING LINKS
-- =========================================================

create or replace function public.validate_customer_booking_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.booking_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.bookings b
    where b.id = new.booking_id
      and b.organization_id = new.organization_id
  ) then

    raise exception
      'Booking must belong to the same organization';

  end if;

  return new;
end;
$$;

create trigger customer_documents_validate_booking
before insert or update of
  organization_id,
  booking_id
on public.customer_documents
for each row
execute function public.validate_customer_booking_link();

create trigger customer_onboardings_validate_booking
before insert or update of
  organization_id,
  booking_id
on public.customer_onboardings
for each row
execute function public.validate_customer_booking_link();

create trigger customer_service_requests_validate_booking
before insert or update of
  organization_id,
  booking_id
on public.customer_service_requests
for each row
execute function public.validate_customer_booking_link();

create trigger customer_feedback_validate_booking
before insert or update of
  organization_id,
  booking_id
on public.customer_feedback
for each row
execute function public.validate_customer_booking_link();

-- =========================================================
-- 22. VALIDATE ACTIVE ORGANIZATION USERS
-- =========================================================

create or replace function public.is_active_organization_user(
  requested_organization_id uuid,
  requested_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    requested_user_id is not null
    and exists (
      select 1
      from public.organization_members om
      where om.organization_id =
        requested_organization_id
        and om.user_id = requested_user_id
        and om.membership_status = 'active'
    );
$$;

revoke all
on function public.is_active_organization_user(uuid, uuid)
from public;

create or replace function public.validate_customer_assignment_users()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.assigned_to is not null
    and not public.is_active_organization_user(
      new.organization_id,
      new.assigned_to
    ) then

    raise exception
      'Assigned user must be an active organization member';

  end if;

  return new;
end;
$$;

create trigger customer_onboardings_validate_assignee
before insert or update of
  organization_id,
  assigned_to
on public.customer_onboardings
for each row
execute function public.validate_customer_assignment_users();

create trigger customer_onboarding_items_validate_assignee
before insert or update of
  organization_id,
  assigned_to
on public.customer_onboarding_items
for each row
execute function public.validate_customer_assignment_users();

create trigger customer_service_requests_validate_assignee
before insert or update of
  organization_id,
  assigned_to
on public.customer_service_requests
for each row
execute function public.validate_customer_assignment_users();

create trigger customer_success_tasks_validate_assignee
before insert or update of
  organization_id,
  assigned_to
on public.customer_success_tasks
for each row
execute function public.validate_customer_assignment_users();

-- =========================================================
-- 23. VALIDATE ONBOARDING ITEM RELATIONS
-- =========================================================

create or replace function public.validate_customer_onboarding_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.customer_onboardings co
    where co.id = new.onboarding_id
      and co.organization_id = new.organization_id
  ) then

    raise exception
      'Onboarding must belong to the same organization';

  end if;

  if new.parent_item_id is not null
    and not exists (
      select 1
      from public.customer_onboarding_items coi
      where coi.id = new.parent_item_id
        and coi.onboarding_id = new.onboarding_id
        and coi.organization_id = new.organization_id
    ) then

    raise exception
      'Parent onboarding item must belong to the same onboarding';

  end if;

  if new.related_document_id is not null
    and not exists (
      select 1
      from public.customer_documents cd
      join public.customer_onboardings co
        on co.id = new.onboarding_id
      where cd.id = new.related_document_id
        and cd.organization_id = new.organization_id
        and cd.customer_id = co.customer_id
    ) then

    raise exception
      'Related document must belong to the onboarding customer';

  end if;

  return new;
end;
$$;

create trigger customer_onboarding_items_validate
before insert or update of
  organization_id,
  onboarding_id,
  parent_item_id,
  related_document_id
on public.customer_onboarding_items
for each row
execute function public.validate_customer_onboarding_item();

-- =========================================================
-- 24. VALIDATE SERVICE REQUEST RELATIONS
-- =========================================================

create or replace function public.validate_service_request_relations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.category_id is not null
    and not exists (
      select 1
      from public.customer_service_categories csc
      where csc.id = new.category_id
        and csc.organization_id = new.organization_id
        and csc.is_active = true
    ) then

    raise exception
      'Service category must belong to the same organization';

  end if;

  if new.escalated_to is not null
    and not public.is_active_organization_user(
      new.organization_id,
      new.escalated_to
    ) then

    raise exception
      'Escalation user must be an active organization member';

  end if;

  return new;
end;
$$;

create trigger customer_service_requests_validate_relations
before insert or update of
  organization_id,
  category_id,
  escalated_to
on public.customer_service_requests
for each row
execute function public.validate_service_request_relations();

create or replace function public.validate_service_request_comment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.customer_service_requests csr
    where csr.id = new.service_request_id
      and csr.organization_id = new.organization_id
      and csr.deleted_at is null
  ) then

    raise exception
      'Service request must belong to the same organization';

  end if;

  return new;
end;
$$;

create trigger customer_service_request_comments_validate
before insert or update of
  organization_id,
  service_request_id
on public.customer_service_request_comments
for each row
execute function public.validate_service_request_comment();

-- =========================================================
-- 25. CUSTOMER SYSTEM FIELDS
-- =========================================================

create or replace function public.set_customer_system_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    new.created_by :=
      coalesce(new.created_by, auth.uid());

    if new.relationship_manager_id is not null then
      new.assigned_at :=
        coalesce(new.assigned_at, now());

      new.assigned_by :=
        coalesce(new.assigned_by, auth.uid());
    end if;

    if new.onboarding_status = 'in_progress' then
      new.onboarding_started_at :=
        coalesce(new.onboarding_started_at, now());
    end if;

    if new.onboarding_status = 'completed' then
      new.onboarding_completed_at :=
        coalesce(new.onboarding_completed_at, now());
    end if;

    return new;
  end if;

  new.updated_by :=
    coalesce(new.updated_by, auth.uid());

  if new.relationship_manager_id
    is distinct from old.relationship_manager_id then

    new.assigned_at :=
      case
        when new.relationship_manager_id is null
          then null
        else now()
      end;

    new.assigned_by :=
      coalesce(new.assigned_by, auth.uid());

  end if;

  if new.onboarding_status
    is distinct from old.onboarding_status then

    if new.onboarding_status = 'in_progress' then
      new.onboarding_started_at :=
        coalesce(new.onboarding_started_at, now());
    end if;

    if new.onboarding_status = 'completed' then
      new.onboarding_completed_at :=
        coalesce(new.onboarding_completed_at, now());
    end if;

  end if;

  if new.health_status in (
    'at_risk',
    'critical'
  )
    and old.health_status is distinct from new.health_status then

    new.risk_detected_at :=
      coalesce(new.risk_detected_at, now());

  end if;

  return new;
end;
$$;

create trigger customers_set_system_fields
before insert or update of
  relationship_manager_id,
  onboarding_status,
  health_status
on public.customers
for each row
execute function public.set_customer_system_fields();

-- =========================================================
-- 26. DOCUMENT SYSTEM FIELDS
-- =========================================================

create or replace function public.set_customer_document_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.uploaded_by :=
      coalesce(new.uploaded_by, auth.uid());

    if new.document_status = 'requested' then
      new.requested_at :=
        coalesce(new.requested_at, now());
    end if;

    if new.document_status in (
      'uploaded',
      'under_review',
      'verified'
    ) then
      new.uploaded_at :=
        coalesce(new.uploaded_at, now());
    end if;
  end if;

  if new.verified = true
    or new.document_status = 'verified' then

    new.verified := true;
    new.document_status := 'verified';
    new.verified_at :=
      coalesce(new.verified_at, now());
    new.verified_by :=
      coalesce(new.verified_by, auth.uid());

  elsif new.document_status = 'rejected' then

    new.verified := false;
    new.verified_at := null;

  end if;

  return new;
end;
$$;

create trigger customer_documents_set_system_fields
before insert or update of
  document_status,
  verified
on public.customer_documents
for each row
execute function public.set_customer_document_fields();

-- =========================================================
-- 27. ONBOARDING SYSTEM FIELDS
-- =========================================================

create or replace function public.set_customer_onboarding_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    new.created_by :=
      coalesce(new.created_by, auth.uid());

    if new.assigned_to is not null then
      new.assigned_at :=
        coalesce(new.assigned_at, now());

      new.assigned_by :=
        coalesce(new.assigned_by, auth.uid());
    end if;

    if new.status = 'in_progress' then
      new.started_at :=
        coalesce(new.started_at, now());
    end if;

    if new.status = 'completed' then
      new.completed_at :=
        coalesce(new.completed_at, now());

      new.progress_percentage := 100;
    end if;

    return new;
  end if;

  new.updated_by :=
    coalesce(new.updated_by, auth.uid());

  if new.assigned_to is distinct from old.assigned_to then
    new.assigned_at :=
      case
        when new.assigned_to is null
          then null
        else now()
      end;

    new.assigned_by :=
      coalesce(new.assigned_by, auth.uid());
  end if;

  if new.status is distinct from old.status then

    if new.status = 'in_progress' then
      new.started_at :=
        coalesce(new.started_at, now());
    end if;

    if new.status = 'completed' then
      new.completed_at :=
        coalesce(new.completed_at, now());

      new.progress_percentage := 100;
    end if;

  end if;

  return new;
end;
$$;

create trigger customer_onboardings_set_system_fields
before insert or update of
  status,
  assigned_to
on public.customer_onboardings
for each row
execute function public.set_customer_onboarding_fields();

-- =========================================================
-- 28. ONBOARDING ITEM SYSTEM FIELDS
-- =========================================================

create or replace function public.set_customer_onboarding_item_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by :=
      coalesce(new.created_by, auth.uid());

    if new.status = 'in_progress' then
      new.started_at :=
        coalesce(new.started_at, now());
    end if;

    if new.status = 'completed' then
      new.completed_at :=
        coalesce(new.completed_at, now());
    end if;

    return new;
  end if;

  new.updated_by :=
    coalesce(new.updated_by, auth.uid());

  if new.status is distinct from old.status then

    if new.status = 'in_progress' then
      new.started_at :=
        coalesce(new.started_at, now());
    end if;

    if new.status = 'completed' then
      new.completed_at :=
        coalesce(new.completed_at, now());
    end if;

  end if;

  return new;
end;
$$;

create trigger customer_onboarding_items_set_system_fields
before insert or update of status
on public.customer_onboarding_items
for each row
execute function public.set_customer_onboarding_item_fields();

-- =========================================================
-- 29. REFRESH ONBOARDING PROGRESS
-- =========================================================

create or replace function public.refresh_customer_onboarding_progress(
  requested_onboarding_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  required_count integer;
  completed_count integer;
  blocked_count integer;
  calculated_progress numeric(5,2);
  calculated_status text;
begin
  select
    count(*) filter (
      where coi.is_required = true
        and coi.status <> 'cancelled'
    ),
    count(*) filter (
      where coi.is_required = true
        and coi.status in (
          'completed',
          'skipped'
        )
    ),
    count(*) filter (
      where coi.status = 'blocked'
    )
  into
    required_count,
    completed_count,
    blocked_count
  from public.customer_onboarding_items coi
  where coi.onboarding_id =
    requested_onboarding_id;

  calculated_progress :=
    case
      when required_count = 0
        then 0
      else round(
        (
          completed_count::numeric
          / required_count::numeric
        ) * 100,
        2
      )
    end;

  calculated_status :=
    case
      when required_count > 0
        and completed_count >= required_count
        then 'completed'

      when blocked_count > 0
        then 'blocked'

      when completed_count > 0
        then 'in_progress'

      else 'not_started'
    end;

  update public.customer_onboardings
  set
    progress_percentage = calculated_progress,
    status = calculated_status,
    started_at = case
      when calculated_status in (
        'in_progress',
        'blocked',
        'completed'
      )
        then coalesce(started_at, now())
      else started_at
    end,
    completed_at = case
      when calculated_status = 'completed'
        then coalesce(completed_at, now())
      else null
    end,
    updated_at = now()
  where id = requested_onboarding_id;
end;
$$;

revoke all
on function public.refresh_customer_onboarding_progress(uuid)
from public;

create or replace function public.trigger_refresh_customer_onboarding()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then

    perform public.refresh_customer_onboarding_progress(
      old.onboarding_id
    );

    return old;
  end if;

  perform public.refresh_customer_onboarding_progress(
    new.onboarding_id
  );

  if tg_op = 'UPDATE'
    and old.onboarding_id
      is distinct from new.onboarding_id then

    perform public.refresh_customer_onboarding_progress(
      old.onboarding_id
    );

  end if;

  return new;
end;
$$;

create trigger customer_onboarding_items_refresh_parent
after insert or update of
  onboarding_id,
  status,
  is_required
or delete
on public.customer_onboarding_items
for each row
execute function public.trigger_refresh_customer_onboarding();

-- =========================================================
-- 30. SYNC CUSTOMER ONBOARDING STATUS
-- =========================================================

create or replace function public.sync_customer_from_onboarding()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.customers
  set
    onboarding_status = new.status,

    onboarding_started_at = case
      when new.started_at is not null
        then coalesce(
          onboarding_started_at,
          new.started_at
        )
      else onboarding_started_at
    end,

    onboarding_completed_at = case
      when new.status = 'completed'
        then coalesce(
          onboarding_completed_at,
          new.completed_at,
          now()
        )
      else onboarding_completed_at
    end,

    customer_stage = case
      when new.status = 'completed'
        and customer_stage in (
          'new_customer',
          'onboarding',
          'documentation'
        )
        then 'service_active'

      when new.status in (
        'in_progress',
        'blocked'
      )
        then 'onboarding'

      else customer_stage
    end,

    updated_at = now()

  where id = new.customer_id
    and organization_id = new.organization_id
    and deleted_at is null;

  return new;
end;
$$;

create trigger customer_onboardings_sync_customer
after insert or update of
  status,
  started_at,
  completed_at
on public.customer_onboardings
for each row
execute function public.sync_customer_from_onboarding();

-- =========================================================
-- 31. SERVICE REQUEST SYSTEM FIELDS
-- =========================================================

create or replace function public.set_service_request_system_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  category_sla_minutes integer;
begin
  if tg_op = 'INSERT' then

    new.created_by :=
      coalesce(new.created_by, auth.uid());

    if new.category_id is not null then
      select csc.default_sla_minutes
      into category_sla_minutes
      from public.customer_service_categories csc
      where csc.id = new.category_id;

      if new.sla_due_at is null
        and category_sla_minutes is not null then

        new.sla_due_at :=
          new.requested_at
          + make_interval(
              mins => category_sla_minutes
            );

        new.sla_status := 'within_sla';

      end if;
    end if;

    if new.assigned_to is not null then
      new.assigned_at :=
        coalesce(new.assigned_at, now());

      new.assigned_by :=
        coalesce(new.assigned_by, auth.uid());

      if new.status = 'open' then
        new.status := 'assigned';
      end if;
    end if;

    return new;
  end if;

  new.updated_by :=
    coalesce(new.updated_by, auth.uid());

  if new.assigned_to is distinct from old.assigned_to then

    new.assigned_at :=
      case
        when new.assigned_to is null
          then null
        else now()
      end;

    new.assigned_by :=
      coalesce(new.assigned_by, auth.uid());

    if new.assigned_to is not null
      and new.status = 'open' then
      new.status := 'assigned';
    end if;

  end if;

  if new.status is distinct from old.status then

    if new.status = 'acknowledged' then
      new.acknowledged_at :=
        coalesce(new.acknowledged_at, now());
    end if;

    if new.status = 'in_progress'
      and new.first_response_at is null then
      new.first_response_at := now();
    end if;

    if new.status = 'resolved' then
      new.resolved_at :=
        coalesce(new.resolved_at, now());

      new.sla_status :=
        case
          when new.sla_due_at is null
            then 'not_applicable'
          when now() <= new.sla_due_at
            then 'resolved'
          else 'breached'
        end;
    end if;

    if new.status = 'closed' then
      new.closed_at :=
        coalesce(new.closed_at, now());
    end if;

    if new.status = 'reopened'
      and old.status is distinct from 'reopened' then
      new.reopened_count :=
        coalesce(old.reopened_count, 0) + 1;
    end if;

  end if;

  return new;
end;
$$;

create trigger customer_service_requests_set_system_fields
before insert or update of
  status,
  assigned_to,
  category_id
on public.customer_service_requests
for each row
execute function public.set_service_request_system_fields();

-- =========================================================
-- 32. SERVICE REQUEST HISTORY
-- =========================================================

create or replace function public.record_service_request_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  detected_change_type text;
begin
  if tg_op = 'INSERT' then

    insert into public.customer_service_request_history (
      organization_id,
      service_request_id,
      previous_status,
      new_status,
      previous_assignee_id,
      new_assignee_id,
      previous_priority,
      new_priority,
      previous_sla_status,
      new_sla_status,
      change_type,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      null,
      new.status,
      null,
      new.assigned_to,
      null,
      new.priority,
      null,
      new.sla_status,
      'created',
      coalesce(new.created_by, auth.uid())
    );

    return new;
  end if;

  if new.status is distinct from old.status
    or new.assigned_to is distinct from old.assigned_to
    or new.priority is distinct from old.priority
    or new.sla_status is distinct from old.sla_status
    or new.escalation_level
      is distinct from old.escalation_level then

    detected_change_type :=
      case
        when new.escalation_level >
          old.escalation_level
          then 'escalation'

        when new.status = 'resolved'
          then 'resolution'

        when new.status = 'reopened'
          then 'reopen'

        when new.assigned_to
          is distinct from old.assigned_to
          then 'assignment'

        when new.priority
          is distinct from old.priority
          then 'priority_change'

        when new.sla_status
          is distinct from old.sla_status
          then 'sla_change'

        else 'status_change'
      end;

    insert into public.customer_service_request_history (
      organization_id,
      service_request_id,
      previous_status,
      new_status,
      previous_assignee_id,
      new_assignee_id,
      previous_priority,
      new_priority,
      previous_sla_status,
      new_sla_status,
      change_type,
      change_reason,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      old.status,
      new.status,
      old.assigned_to,
      new.assigned_to,
      old.priority,
      new.priority,
      old.sla_status,
      new.sla_status,
      detected_change_type,
      coalesce(
        new.escalation_reason,
        new.resolution_summary
      ),
      coalesce(new.updated_by, auth.uid())
    );

  end if;

  return new;
end;
$$;

create trigger customer_service_requests_record_history
after insert or update of
  status,
  assigned_to,
  priority,
  sla_status,
  escalation_level
on public.customer_service_requests
for each row
execute function public.record_service_request_history();

-- =========================================================
-- 33. SUCCESS TASK SYSTEM FIELDS
-- =========================================================

create or replace function public.set_customer_success_task_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    new.created_by :=
      coalesce(new.created_by, auth.uid());

    if new.assigned_to is not null then
      new.assigned_at :=
        coalesce(new.assigned_at, now());

      new.assigned_by :=
        coalesce(new.assigned_by, auth.uid());
    end if;

    if new.status = 'in_progress' then
      new.started_at :=
        coalesce(new.started_at, now());
    end if;

    if new.status = 'completed' then
      new.completed_at :=
        coalesce(new.completed_at, now());
    end if;

    return new;
  end if;

  new.updated_by :=
    coalesce(new.updated_by, auth.uid());

  if new.assigned_to is distinct from old.assigned_to then

    new.assigned_at :=
      case
        when new.assigned_to is null
          then null
        else now()
      end;

    new.assigned_by :=
      coalesce(new.assigned_by, auth.uid());

  end if;

  if new.status is distinct from old.status then

    if new.status = 'in_progress' then
      new.started_at :=
        coalesce(new.started_at, now());
    end if;

    if new.status = 'completed' then
      new.completed_at :=
        coalesce(new.completed_at, now());
    end if;

  end if;

  return new;
end;
$$;

create trigger customer_success_tasks_set_system_fields
before insert or update of
  status,
  assigned_to
on public.customer_success_tasks
for each row
execute function public.set_customer_success_task_fields();

-- =========================================================
-- 34. CUSTOMER HEALTH HISTORY
-- =========================================================

create or replace function public.record_customer_health_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    insert into public.customer_health_history (
      organization_id,
      customer_id,
      previous_health_status,
      new_health_status,
      previous_health_score,
      new_health_score,
      reason,
      calculated_by,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      null,
      new.health_status,
      null,
      new.health_score,
      new.risk_reason,
      'manual',
      coalesce(new.created_by, auth.uid())
    );

    return new;
  end if;

  if new.health_status is distinct from old.health_status
    or new.health_score is distinct from old.health_score then

    insert into public.customer_health_history (
      organization_id,
      customer_id,
      previous_health_status,
      new_health_status,
      previous_health_score,
      new_health_score,
      reason,
      calculated_by,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      old.health_status,
      new.health_status,
      old.health_score,
      new.health_score,
      new.risk_reason,
      'manual',
      coalesce(new.updated_by, auth.uid())
    );

  end if;

  return new;
end;
$$;

create trigger customers_record_health_history
after insert or update of
  health_status,
  health_score
on public.customers
for each row
execute function public.record_customer_health_history();

-- =========================================================
-- 35. CALCULATE CUSTOMER HEALTH
-- =========================================================

create or replace function public.calculate_customer_health(
  requested_customer_id uuid
)
returns public.customers
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_customer public.customers;
  open_requests integer;
  breached_requests integer;
  overdue_tasks integer;
  recent_negative_feedback integer;
  calculated_score numeric(5,2);
  calculated_status text;
  calculated_reason text;
begin
  select *
  into target_customer
  from public.customers
  where id = requested_customer_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Customer not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      target_customer.organization_id,
      'customers.manage_health'
    ) then

    raise exception 'Permission denied';

  end if;

  select count(*)
  into open_requests
  from public.customer_service_requests csr
  where csr.customer_id = requested_customer_id
    and csr.deleted_at is null
    and csr.status not in (
      'resolved',
      'closed',
      'cancelled'
    );

  select count(*)
  into breached_requests
  from public.customer_service_requests csr
  where csr.customer_id = requested_customer_id
    and csr.deleted_at is null
    and csr.sla_status = 'breached';

  select count(*)
  into overdue_tasks
  from public.customer_success_tasks cst
  where cst.customer_id = requested_customer_id
    and cst.deleted_at is null
    and (
      cst.status = 'overdue'
      or (
        cst.status in (
          'pending',
          'in_progress',
          'blocked'
        )
        and cst.due_at < now()
      )
    );

  select count(*)
  into recent_negative_feedback
  from public.customer_feedback cf
  where cf.customer_id = requested_customer_id
    and cf.submitted_at >=
      now() - interval '90 days'
    and (
      cf.sentiment = 'negative'
      or cf.rating <= 2
      or cf.nps_score <= 6
    );

  calculated_score :=
    greatest(
      0::numeric,
      least(
        100::numeric,
        100
        - (open_requests * 5)
        - (breached_requests * 15)
        - (overdue_tasks * 8)
        - (recent_negative_feedback * 12)
      )
    );

  calculated_status :=
    case
      when calculated_score >= 80
        then 'healthy'
      when calculated_score >= 60
        then 'stable'
      when calculated_score >= 40
        then 'attention_required'
      when calculated_score >= 20
        then 'at_risk'
      else 'critical'
    end;

  calculated_reason :=
    concat_ws(
      '; ',
      case
        when open_requests > 0
          then open_requests || ' open service requests'
      end,
      case
        when breached_requests > 0
          then breached_requests || ' SLA breaches'
      end,
      case
        when overdue_tasks > 0
          then overdue_tasks || ' overdue tasks'
      end,
      case
        when recent_negative_feedback > 0
          then recent_negative_feedback ||
            ' recent negative feedback records'
      end
    );

  update public.customers
  set
    health_score = calculated_score,
    health_status = calculated_status,
    risk_reason = nullif(
      calculated_reason,
      ''
    ),
    risk_detected_at = case
      when calculated_status in (
        'at_risk',
        'critical'
      )
        then coalesce(risk_detected_at, now())
      else null
    end,
    updated_by = auth.uid(),
    updated_at = now()
  where id = requested_customer_id
  returning *
  into target_customer;

  insert into public.customer_health_history (
    organization_id,
    customer_id,
    previous_health_status,
    new_health_status,
    previous_health_score,
    new_health_score,
    reason,
    calculated_by,
    changed_by
  )
  values (
    target_customer.organization_id,
    target_customer.id,
    null,
    target_customer.health_status,
    null,
    target_customer.health_score,
    target_customer.risk_reason,
    'rule_engine',
    auth.uid()
  );

  return target_customer;
end;
$$;

revoke all
on function public.calculate_customer_health(uuid)
from public;

grant execute
on function public.calculate_customer_health(uuid)
to authenticated;

grant execute
on function public.calculate_customer_health(uuid)
to service_role;

-- =========================================================
-- 36. CUSTOMER FEEDBACK SYNCHRONIZATION
-- =========================================================

create or replace function public.sync_customer_from_feedback()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  average_rating numeric(5,2);
  latest_nps integer;
begin
  select
    round(avg(cf.rating)::numeric, 2)
  into average_rating
  from public.customer_feedback cf
  where cf.customer_id = new.customer_id
    and cf.rating is not null;

  select cf.nps_score
  into latest_nps
  from public.customer_feedback cf
  where cf.customer_id = new.customer_id
    and cf.nps_score is not null
  order by cf.submitted_at desc
  limit 1;

  update public.customers
  set
    satisfaction_score = case
      when average_rating is null
        then satisfaction_score
      else round(
        (average_rating / 5) * 100,
        2
      )
    end,

    nps_score = coalesce(
      latest_nps,
      nps_score
    ),

    last_engagement_at = greatest(
      coalesce(
        last_engagement_at,
        '-infinity'::timestamptz
      ),
      new.submitted_at
    ),

    updated_at = now()

  where id = new.customer_id
    and organization_id = new.organization_id
    and deleted_at is null;

  return new;
end;
$$;

create trigger customer_feedback_sync_customer
after insert or update of
  rating,
  nps_score,
  sentiment,
  submitted_at
on public.customer_feedback
for each row
execute function public.sync_customer_from_feedback();

-- =========================================================
-- 37. REFERRAL SYNCHRONIZATION
-- =========================================================

create or replace function public.sync_customer_referral_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_customer_id uuid;
begin
  if tg_op = 'DELETE' then
    target_customer_id :=
      old.referring_customer_id;
  else
    target_customer_id :=
      new.referring_customer_id;
  end if;

  update public.customers
  set
    referral_count = (
      select count(*)
      from public.customer_referrals cr
      where cr.referring_customer_id =
        target_customer_id
        and cr.referral_status <>
          'cancelled'
    ),
    updated_at = now()
  where id = target_customer_id;

  if tg_op = 'UPDATE'
    and old.referring_customer_id
      is distinct from new.referring_customer_id then

    update public.customers
    set
      referral_count = (
        select count(*)
        from public.customer_referrals cr
        where cr.referring_customer_id =
          old.referring_customer_id
          and cr.referral_status <>
            'cancelled'
      ),
      updated_at = now()
    where id = old.referring_customer_id;

  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create trigger customer_referrals_sync_customer
after insert or update of
  referring_customer_id,
  referral_status
or delete
on public.customer_referrals
for each row
execute function public.sync_customer_referral_count();

-- =========================================================
-- 38. CREATE CUSTOMER FROM BOOKING
-- =========================================================

create or replace function public.create_customer_from_booking(
  requested_booking_id uuid,
  requested_customer_number text,
  requested_relationship_manager_id uuid default null
)
returns public.customers
language plpgsql
security definer
set search_path = ''
as $$
declare
  source_booking public.bookings;
  source_lead public.leads;
  created_customer public.customers;
begin
  select *
  into source_booking
  from public.bookings
  where id = requested_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      source_booking.organization_id,
      'customers.create'
    ) then

    raise exception 'Permission denied';

  end if;

  select *
  into source_lead
  from public.leads
  where id = source_booking.lead_id
    and organization_id =
      source_booking.organization_id
    and deleted_at is null;

  if not found then
    raise exception 'Booking lead not found';
  end if;

  select *
  into created_customer
  from public.customers c
  where c.organization_id =
    source_booking.organization_id
    and c.booking_id = source_booking.id
    and c.deleted_at is null
  limit 1;

  if found then
    return created_customer;
  end if;

  insert into public.customers (
    organization_id,
    lead_id,
    booking_id,
    customer_number,
    first_name,
    last_name,
    full_name,
    phone,
    alternate_phone,
    whatsapp_number,
    email,
    preferred_language,
    preferred_contact_channel,
    customer_status,
    customer_stage,
    customer_type,
    onboarding_status,
    relationship_manager_id,
    assigned_by,
    assigned_at,
    consent_status,
    consent_at,
    tags,
    metadata,
    created_by
  )
  values (
    source_booking.organization_id,
    source_booking.lead_id,
    source_booking.id,
    requested_customer_number,
    source_lead.first_name,
    source_lead.last_name,
    coalesce(
      source_lead.full_name,
      concat_ws(
        ' ',
        source_lead.first_name,
        source_lead.last_name
      )
    ),
    source_lead.phone,
    source_lead.alternate_phone,
    source_lead.whatsapp_number,
    source_lead.email,
    source_lead.preferred_language,
    source_lead.preferred_contact_channel,
    'onboarding',
    'new_customer',
    case
      when source_lead.purpose = 'investment'
        then 'investor'
      else 'buyer'
    end,
    'not_started',
    coalesce(
      requested_relationship_manager_id,
      source_booking.booked_by
    ),
    auth.uid(),
    now(),
    source_lead.consent_status,
    source_lead.consent_at,
    source_lead.tags,
    jsonb_build_object(
      'source',
      'booking',
      'booking_number',
      source_booking.booking_number,
      'project_name',
      source_booking.project_name
    ),
    auth.uid()
  )
  returning *
  into created_customer;

  insert into public.customer_activities (
    organization_id,
    customer_id,
    booking_id,
    activity_type,
    direction,
    status,
    subject,
    description,
    performed_by,
    completed_at,
    is_automated,
    metadata,
    created_by
  )
  values (
    created_customer.organization_id,
    created_customer.id,
    source_booking.id,
    'system_event',
    'internal',
    'completed',
    'Customer created from booking',
    concat(
      'Customer converted from booking ',
      source_booking.booking_number
    ),
    auth.uid(),
    now(),
    true,
    jsonb_build_object(
      'booking_id',
      source_booking.id,
      'lead_id',
      source_booking.lead_id
    ),
    auth.uid()
  );

  return created_customer;
end;
$$;

revoke all
on function public.create_customer_from_booking(
  uuid,
  text,
  uuid
)
from public;

grant execute
on function public.create_customer_from_booking(
  uuid,
  text,
  uuid
)
to authenticated;

grant execute
on function public.create_customer_from_booking(
  uuid,
  text,
  uuid
)
to service_role;

-- =========================================================
-- 39. PROCESS OVERDUE CUSTOMER-SUCCESS RECORDS
-- =========================================================

create or replace function public.process_customer_success_overdue(
  requested_organization_id uuid default null
)
returns table (
  overdue_task_count integer,
  service_request_breach_count integer,
  service_request_at_risk_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  updated_task_count integer := 0;
  updated_breach_count integer := 0;
  updated_at_risk_count integer := 0;
begin
  if auth.role() <> 'service_role'
    and requested_organization_id is null then

    raise exception
      'Organization ID is required';

  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'customers.manage_sla'
    ) then

    raise exception 'Permission denied';

  end if;

  update public.customer_success_tasks
  set
    status = 'overdue',
    updated_at = now()
  where deleted_at is null
    and status in (
      'pending',
      'in_progress',
      'blocked'
    )
    and due_at < now()
    and (
      requested_organization_id is null
      or organization_id =
        requested_organization_id
    );

  get diagnostics updated_task_count = row_count;

  update public.customer_service_requests
  set
    sla_status = 'breached',
    updated_at = now()
  where deleted_at is null
    and status not in (
      'resolved',
      'closed',
      'cancelled'
    )
    and sla_due_at is not null
    and sla_due_at < now()
    and sla_status <> 'breached'
    and (
      requested_organization_id is null
      or organization_id =
        requested_organization_id
    );

  get diagnostics updated_breach_count = row_count;

  update public.customer_service_requests
  set
    sla_status = 'at_risk',
    updated_at = now()
  where deleted_at is null
    and status not in (
      'resolved',
      'closed',
      'cancelled'
    )
    and sla_due_at is not null
    and sla_due_at >= now()
    and sla_due_at <=
      now() + interval '30 minutes'
    and sla_status not in (
      'at_risk',
      'breached'
    )
    and (
      requested_organization_id is null
      or organization_id =
        requested_organization_id
    );

  get diagnostics updated_at_risk_count = row_count;

  return query
  select
    updated_task_count,
    updated_breach_count,
    updated_at_risk_count;
end;
$$;

revoke all
on function public.process_customer_success_overdue(uuid)
from public;

grant execute
on function public.process_customer_success_overdue(uuid)
to authenticated;

grant execute
on function public.process_customer_success_overdue(uuid)
to service_role;

-- =========================================================
-- 40. ESCALATE SERVICE REQUEST
-- =========================================================

create or replace function public.escalate_customer_service_request(
  requested_service_request_id uuid,
  requested_escalated_to uuid,
  requested_reason text
)
returns public.customer_service_requests
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_request public.customer_service_requests;
begin
  select *
  into target_request
  from public.customer_service_requests
  where id = requested_service_request_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Service request not found';
  end if;

  if not public.has_organization_permission(
    target_request.organization_id,
    'customers.manage_sla'
  ) then
    raise exception 'Permission denied';
  end if;

  if not public.is_active_organization_user(
    target_request.organization_id,
    requested_escalated_to
  ) then
    raise exception
      'Escalation user must be an active organization member';
  end if;

  update public.customer_service_requests
  set
    escalation_level =
      escalation_level + 1,
    escalated_to =
      requested_escalated_to,
    escalated_at = now(),
    escalation_reason =
      requested_reason,
    sla_status = case
      when sla_status = 'not_applicable'
        then sla_status
      else 'at_risk'
    end,
    updated_by = auth.uid(),
    updated_at = now()
  where id = requested_service_request_id
  returning *
  into target_request;

  return target_request;
end;
$$;

revoke all
on function public.escalate_customer_service_request(
  uuid,
  uuid,
  text
)
from public;

grant execute
on function public.escalate_customer_service_request(
  uuid,
  uuid,
  text
)
to authenticated;

-- =========================================================
-- 41. CUSTOMER-SUCCESS DASHBOARD
-- =========================================================

create or replace function public.get_customer_success_dashboard(
  requested_organization_id uuid,
  requested_manager_id uuid default null
)
returns table (
  total_customers bigint,
  onboarding_customers bigint,
  active_customers bigint,
  at_risk_customers bigint,
  critical_customers bigint,
  open_service_requests bigint,
  sla_breached_requests bigint,
  overdue_tasks bigint,
  pending_referral_rewards bigint,
  average_health_score numeric,
  average_satisfaction_score numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_organization_permission(
    requested_organization_id,
    'customers.view'
  ) then
    raise exception 'Permission denied';
  end if;

  return query
  with filtered_customers as (
    select c.*
    from public.customers c
    where c.organization_id =
      requested_organization_id
      and c.deleted_at is null
      and (
        requested_manager_id is null
        or c.relationship_manager_id =
          requested_manager_id
      )
  )
  select
    count(*) as total_customers,

    count(*) filter (
      where fc.onboarding_status in (
        'not_started',
        'in_progress',
        'blocked'
      )
    ) as onboarding_customers,

    count(*) filter (
      where fc.customer_status = 'active'
    ) as active_customers,

    count(*) filter (
      where fc.health_status = 'at_risk'
    ) as at_risk_customers,

    count(*) filter (
      where fc.health_status = 'critical'
    ) as critical_customers,

    (
      select count(*)
      from public.customer_service_requests csr
      join filtered_customers c
        on c.id = csr.customer_id
      where csr.deleted_at is null
        and csr.status not in (
          'resolved',
          'closed',
          'cancelled'
        )
    ) as open_service_requests,

    (
      select count(*)
      from public.customer_service_requests csr
      join filtered_customers c
        on c.id = csr.customer_id
      where csr.deleted_at is null
        and csr.sla_status = 'breached'
    ) as sla_breached_requests,

    (
      select count(*)
      from public.customer_success_tasks cst
      join filtered_customers c
        on c.id = cst.customer_id
      where cst.deleted_at is null
        and (
          cst.status = 'overdue'
          or (
            cst.status in (
              'pending',
              'in_progress',
              'blocked'
            )
            and cst.due_at < now()
          )
        )
    ) as overdue_tasks,

    (
      select count(*)
      from public.customer_referrals cr
      join filtered_customers c
        on c.id =
          cr.referring_customer_id
      where cr.reward_status in (
        'pending',
        'approved'
      )
    ) as pending_referral_rewards,

    round(
      avg(fc.health_score)::numeric,
      2
    ) as average_health_score,

    round(
      avg(fc.satisfaction_score)::numeric,
      2
    ) as average_satisfaction_score

  from filtered_customers fc;
end;
$$;

revoke all
on function public.get_customer_success_dashboard(uuid, uuid)
from public;

grant execute
on function public.get_customer_success_dashboard(uuid, uuid)
to authenticated;

-- =========================================================
-- 42. CUSTOMER RLS POLICIES
-- =========================================================

create policy "Authorized users can view customers"
on public.customers
for select
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'customers.view'
  )
  and (
    public.has_organization_permission(
      organization_id,
      'customers.view_all'
    )
    or relationship_manager_id =
      (select auth.uid())
    or created_by =
      (select auth.uid())
  )
);

create policy "Authorized users can create customers"
on public.customers
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'customers.create'
  )
);

create policy "Authorized users can update customers"
on public.customers
for update
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'customers.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.update'
  )
);

create policy "Authorized users can delete customers"
on public.customers
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.delete'
  )
);

-- =========================================================
-- 43. ADDRESS AND CONTACT RLS
-- =========================================================

create policy "Authorized users can view customer addresses"
on public.customer_addresses
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage customer addresses"
on public.customer_addresses
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.update'
  )
);

create policy "Authorized users can view customer contacts"
on public.customer_contacts
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage customer contacts"
on public.customer_contacts
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.update'
  )
);

-- =========================================================
-- 44. CUSTOMER DOCUMENT RLS
-- =========================================================

create policy "Authorized users can view customer documents"
on public.customer_documents
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage customer documents"
on public.customer_documents
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_documents'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_documents'
  )
);

-- =========================================================
-- 45. ONBOARDING RLS
-- =========================================================

create policy "Authorized users can view customer onboardings"
on public.customer_onboardings
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage customer onboardings"
on public.customer_onboardings
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_onboarding'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_onboarding'
  )
);

create policy "Authorized users can view onboarding items"
on public.customer_onboarding_items
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage onboarding items"
on public.customer_onboarding_items
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_onboarding'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_onboarding'
  )
);

-- =========================================================
-- 46. SERVICE CATEGORY RLS
-- =========================================================

create policy "Authorized users can view service categories"
on public.customer_service_categories
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage service categories"
on public.customer_service_categories
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_sla'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_sla'
  )
);

-- =========================================================
-- 47. SERVICE REQUEST RLS
-- =========================================================

create policy "Authorized users can view service requests"
on public.customer_service_requests
for select
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can create service requests"
on public.customer_service_requests
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_service_requests'
  )
);

create policy "Authorized users can update service requests"
on public.customer_service_requests
for update
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'customers.manage_service_requests'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_service_requests'
  )
);

create policy "Authorized users can delete service requests"
on public.customer_service_requests
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_service_requests'
  )
);

create policy "Authorized users can view service comments"
on public.customer_service_request_comments
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage service comments"
on public.customer_service_request_comments
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_service_requests'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_service_requests'
  )
);

create policy "Authorized users can view service history"
on public.customer_service_request_history
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

-- =========================================================
-- 48. CUSTOMER SUCCESS TASK RLS
-- =========================================================

create policy "Authorized users can view customer success tasks"
on public.customer_success_tasks
for select
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage customer success tasks"
on public.customer_success_tasks
for all
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'customers.manage_tasks'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_tasks'
  )
);

-- =========================================================
-- 49. FEEDBACK RLS
-- =========================================================

create policy "Authorized users can view customer feedback"
on public.customer_feedback
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage customer feedback"
on public.customer_feedback
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_feedback'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_feedback'
  )
);

-- =========================================================
-- 50. REFERRAL RLS
-- =========================================================

create policy "Authorized users can view customer referrals"
on public.customer_referrals
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can manage customer referrals"
on public.customer_referrals
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_referrals'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_referrals'
  )
);

-- =========================================================
-- 51. CUSTOMER HEALTH RLS
-- =========================================================

create policy "Authorized users can view customer health history"
on public.customer_health_history
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

-- =========================================================
-- 52. CUSTOMER ACTIVITY RLS
-- =========================================================

create policy "Authorized users can view customer activities"
on public.customer_activities
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.view'
  )
);

create policy "Authorized users can create customer activities"
on public.customer_activities
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_tasks'
  )
  or public.has_organization_permission(
    organization_id,
    'customers.manage_service_requests'
  )
);

create policy "Authorized users can update customer activities"
on public.customer_activities
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_tasks'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'customers.manage_tasks'
  )
);

create policy "Authorized users can delete customer activities"
on public.customer_activities
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'customers.manage_tasks'
  )
);

commit;