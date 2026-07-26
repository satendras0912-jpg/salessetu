-- ============================================================
-- SalesSetu Enterprise
-- Migration 019: Customer Portal Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   004_followups.sql
--   005_site_visits.sql
--   006_bookings.sql
--   007_customer_success.sql
--   008_inventory.sql
--   010_ai_calling_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--   018_Document_Management_Engine.sql
--
-- Scope:
--   • Secure customer portal accounts and access
--   • Customer dashboards and lifecycle timeline
--   • Booking, payment, site-visit and document visibility
--   • Support tickets and service requests
--   • Family members, co-buyers, nominees and referrals
--   • Project updates, progress media and possession checklist
--   • Notification preferences and communication timeline
--   • Secure portal sessions, invitations and access tokens
--   • Event outbox, analytics, audit and health checks
--   • RLS, permissions, grants and final validation
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ============================================================
-- 1. RBAC PERMISSIONS
-- ============================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
select
  p.module,
  p.action,
  p.code,
  p.description
from (
  values
    ('customer_portal','view','customer_portal.view','View customer portal'),
    ('customer_portal','view_all','customer_portal.view_all','View all customer portals'),
    ('customer_portal','manage_accounts','customer_portal.manage_accounts','Manage customer portal accounts'),
    ('customer_portal','manage_access','customer_portal.manage_access','Manage portal access'),
    ('customer_portal','manage_content','customer_portal.manage_content','Manage portal content'),
    ('customer_portal','manage_updates','customer_portal.manage_updates','Manage project and customer updates'),
    ('customer_portal','manage_support','customer_portal.manage_support','Manage support tickets'),
    ('customer_portal','manage_payments','customer_portal.manage_payments','Manage customer payment visibility'),
    ('customer_portal','manage_documents','customer_portal.manage_documents','Manage customer portal documents'),
    ('customer_portal','manage_referrals','customer_portal.manage_referrals','Manage customer referrals'),
    ('customer_portal','manage_preferences','customer_portal.manage_preferences','Manage customer portal preferences'),
    ('customer_portal','impersonate','customer_portal.impersonate','Impersonate customer portal'),
    ('customer_portal','view_logs','customer_portal.view_logs','View customer portal logs'),
    ('customer_portal','view_analytics','customer_portal.view_analytics','View customer portal analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. CUSTOMER PORTAL ACCOUNTS
-- ============================================================

create table if not exists public.customer_portal_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,

  account_code text not null,
  display_name text not null,
  primary_email text,
  primary_phone text,

  status text not null default 'invited'
    check (
      status in (
        'invited',
        'pending_activation',
        'active',
        'suspended',
        'blocked',
        'closed',
        'archived'
      )
    ),

  preferred_language text not null default 'en',
  timezone text not null default 'Asia/Kolkata',

  last_login_at timestamptz,
  last_activity_at timestamptz,
  activated_at timestamptz,
  suspended_at timestamptz,
  closed_at timestamptz,

  onboarding_completed boolean not null default false,
  terms_accepted boolean not null default false,
  privacy_accepted boolean not null default false,
  marketing_opt_in boolean not null default false,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,customer_id),
  unique (organization_id,account_code)
);

create index if not exists customer_portal_accounts_user_idx
  on public.customer_portal_accounts (
    organization_id,
    user_id,
    status
  );

-- ============================================================
-- 3. PORTAL INVITATIONS
-- ============================================================

create table if not exists public.customer_portal_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,

  invitation_type text not null default 'activation'
    check (
      invitation_type in (
        'activation',
        'password_setup',
        'co_buyer',
        'family_member',
        'nominee',
        'reinvite'
      )
    ),

  token_hash text not null,
  token_prefix text,

  email text,
  phone text,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'sent',
        'opened',
        'accepted',
        'expired',
        'revoked',
        'failed'
      )
    ),

  expires_at timestamptz not null,
  sent_at timestamptz,
  opened_at timestamptz,
  accepted_at timestamptz,
  revoked_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (token_hash)
);

create index if not exists customer_portal_invitations_status_idx
  on public.customer_portal_invitations (
    organization_id,
    status,
    expires_at
  );

-- ============================================================
-- 4. PORTAL SESSIONS
-- ============================================================

create table if not exists public.customer_portal_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,

  session_key text not null,
  status text not null default 'active'
    check (
      status in (
        'active',
        'expired',
        'revoked',
        'logged_out',
        'blocked'
      )
    ),

  ip_address inet,
  user_agent text,
  device_id text,
  device_type text,
  browser text,
  operating_system text,

  started_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz,
  ended_at timestamptz,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (session_key)
);

-- ============================================================
-- 5. PORTAL ACCESS TOKENS
-- ============================================================

create table if not exists public.customer_portal_access_tokens (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,

  token_type text not null
    check (
      token_type in (
        'magic_link',
        'document_access',
        'payment_link',
        'support_link',
        'temporary_access'
      )
    ),

  token_hash text not null,
  token_prefix text,

  scope jsonb not null default '{}',
  status text not null default 'active'
    check (status in ('active','used','expired','revoked')),

  maximum_uses integer default 1,
  use_count integer not null default 0,

  expires_at timestamptz,
  last_used_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (token_hash)
);

-- ============================================================
-- 6. FAMILY MEMBERS / CO-BUYERS / NOMINEES
-- ============================================================

create table if not exists public.customer_portal_related_persons (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,

  relationship_type text not null
    check (
      relationship_type in (
        'co_buyer',
        'family_member',
        'nominee',
        'authorized_representative',
        'witness',
        'other'
      )
    ),

  full_name text not null,
  email text,
  phone text,

  date_of_birth date,
  relationship_name text,

  ownership_percentage numeric(8,4),
  is_primary boolean not null default false,
  can_view_documents boolean not null default false,
  can_view_payments boolean not null default false,
  can_raise_tickets boolean not null default false,

  portal_user_id uuid references auth.users(id) on delete set null,

  status text not null default 'active'
    check (status in ('invited','active','inactive','revoked','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 7. CUSTOMER DASHBOARD CONFIG
-- ============================================================

create table if not exists public.customer_portal_dashboard_configs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,

  layout_config jsonb not null default '{}',
  widget_config jsonb not null default '{}',
  quick_actions jsonb not null default '[]',

  show_booking boolean not null default true,
  show_payments boolean not null default true,
  show_documents boolean not null default true,
  show_site_visits boolean not null default true,
  show_communications boolean not null default true,
  show_support boolean not null default true,
  show_referrals boolean not null default true,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (portal_account_id)
);

-- ============================================================
-- 8. CUSTOMER LIFECYCLE TIMELINE
-- ============================================================

create table if not exists public.customer_portal_timeline_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,

  event_type text not null,
  event_name text not null,
  event_title text not null,
  event_description text,

  source_module text,
  source_type text,
  source_id uuid,
  source_reference text,

  event_status text,
  event_data jsonb not null default '{}',

  visibility text not null default 'customer'
    check (
      visibility in (
        'customer',
        'customer_and_family',
        'internal',
        'restricted'
      )
    ),

  occurred_at timestamptz not null default now(),

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists customer_portal_timeline_lookup_idx
  on public.customer_portal_timeline_events (
    portal_account_id,
    occurred_at desc
  );

-- ============================================================
-- 9. BOOKING SNAPSHOTS
-- ============================================================

create table if not exists public.customer_portal_booking_snapshots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,

  booking_status text,
  project_name text,
  unit_reference text,
  booking_date date,

  booking_amount numeric(18,2),
  total_amount numeric(18,2),
  paid_amount numeric(18,2),
  outstanding_amount numeric(18,2),

  next_payment_due_at timestamptz,
  next_payment_amount numeric(18,2),

  possession_target_date date,
  registration_target_date date,

  snapshot_data jsonb not null default '{}',
  snapshot_at timestamptz not null default now(),

  created_at timestamptz not null default now(),

  unique (portal_account_id,booking_id)
);

-- ============================================================
-- 10. PAYMENT SCHEDULES
-- ============================================================

create table if not exists public.customer_portal_payment_schedules (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,

  installment_number integer not null,
  installment_name text,

  due_date date not null,
  amount_due numeric(18,2) not null default 0,
  amount_paid numeric(18,2) not null default 0,
  outstanding_amount numeric(18,2) generated always as (
    greatest(amount_due - amount_paid,0)
  ) stored,

  status text not null default 'scheduled'
    check (
      status in (
        'scheduled',
        'due',
        'partially_paid',
        'paid',
        'overdue',
        'waived',
        'cancelled'
      )
    ),

  payment_stage text,
  milestone_reference text,

  reminder_days_before integer[] not null default array[7,3,1],

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (booking_id,installment_number)
);

create index if not exists customer_portal_payment_schedules_due_idx
  on public.customer_portal_payment_schedules (
    organization_id,
    status,
    due_date
  );

-- ============================================================
-- 11. PAYMENT TRANSACTIONS
-- ============================================================

create table if not exists public.customer_portal_payment_transactions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,
  payment_schedule_id uuid references public.customer_portal_payment_schedules(id) on delete set null,

  transaction_reference text,
  external_transaction_id text,

  transaction_type text not null default 'payment'
    check (
      transaction_type in (
        'payment',
        'refund',
        'adjustment',
        'waiver',
        'charge',
        'credit'
      )
    ),

  payment_method text,
  amount numeric(18,2) not null,
  currency text not null default 'INR',

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'initiated',
        'processing',
        'successful',
        'failed',
        'cancelled',
        'refunded',
        'partially_refunded'
      )
    ),

  transaction_at timestamptz,
  settled_at timestamptz,

  receipt_document_id uuid references public.documents(id) on delete set null,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,transaction_reference)
);

-- ============================================================
-- 12. CUSTOMER DOCUMENT VISIBILITY
-- ============================================================

create table if not exists public.customer_portal_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  document_id uuid not null references public.documents(id) on delete cascade,

  document_role text not null default 'general'
    check (
      document_role in (
        'general',
        'agreement',
        'booking_form',
        'receipt',
        'kyc',
        'demand_letter',
        'statement',
        'possession',
        'registration',
        'project_update',
        'other'
      )
    ),

  visibility_status text not null default 'visible'
    check (
      visibility_status in (
        'visible',
        'hidden',
        'scheduled',
        'expired',
        'revoked'
      )
    ),

  visible_from timestamptz not null default now(),
  visible_until timestamptz,

  allow_download boolean not null default true,
  allow_preview boolean not null default true,
  requires_acknowledgement boolean not null default false,

  acknowledged_at timestamptz,
  acknowledged_by uuid references auth.users(id) on delete set null,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (portal_account_id,document_id)
);

-- ============================================================
-- 13. SITE VISIT HISTORY
-- ============================================================

create table if not exists public.customer_portal_site_visits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  site_visit_id uuid not null references public.site_visits(id) on delete cascade,

  project_name text,
  visit_status text,
  scheduled_at timestamptz,
  completed_at timestamptz,

  agent_name text,
  notes text,

  customer_feedback text,
  customer_rating integer check (customer_rating between 1 and 5),

  snapshot_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (portal_account_id,site_visit_id)
);

-- ============================================================
-- 14. COMMUNICATION TIMELINE
-- ============================================================

create table if not exists public.customer_portal_communications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,

  communication_message_job_id uuid references public.communication_message_jobs(id) on delete set null,
  ai_call_job_id uuid references public.ai_call_jobs(id) on delete set null,

  channel_code text,
  direction text,
  subject text,
  body_preview text,

  communication_status text,
  communicated_at timestamptz,

  visible_to_customer boolean not null default true,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now()
);

create index if not exists customer_portal_communications_lookup_idx
  on public.customer_portal_communications (
    portal_account_id,
    communicated_at desc
  );

-- ============================================================
-- 15. SUPPORT TICKETS
-- ============================================================

create table if not exists public.customer_portal_support_tickets (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete set null,

  ticket_number text not null,
  category text not null,
  subject text not null,
  description text not null,

  priority text not null default 'normal'
    check (priority in ('low','normal','high','urgent','critical')),

  status text not null default 'open'
    check (
      status in (
        'open',
        'assigned',
        'in_progress',
        'waiting_customer',
        'waiting_internal',
        'resolved',
        'closed',
        'cancelled'
      )
    ),

  assigned_to uuid references auth.users(id) on delete set null,
  assigned_team_id uuid references public.assignment_teams(id) on delete set null,

  sla_due_at timestamptz,
  first_response_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,

  customer_rating integer check (customer_rating between 1 and 5),
  customer_feedback text,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,ticket_number)
);

create index if not exists customer_portal_support_tickets_queue_idx
  on public.customer_portal_support_tickets (
    organization_id,
    status,
    priority,
    sla_due_at
  );

create table if not exists public.customer_portal_support_messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  ticket_id uuid not null references public.customer_portal_support_tickets(id) on delete cascade,

  sender_type text not null
    check (
      sender_type in (
        'customer',
        'agent',
        'system',
        'builder',
        'support'
      )
    ),

  sender_user_id uuid references auth.users(id) on delete set null,
  message_text text not null,

  attachments jsonb not null default '[]',
  is_internal_note boolean not null default false,

  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- ============================================================
-- 16. CUSTOMER REQUESTS
-- ============================================================

create table if not exists public.customer_portal_service_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete set null,

  request_type text not null,
  request_title text not null,
  request_description text,

  status text not null default 'submitted'
    check (
      status in (
        'draft',
        'submitted',
        'under_review',
        'approved',
        'rejected',
        'processing',
        'completed',
        'cancelled'
      )
    ),

  requested_data jsonb not null default '{}',
  response_data jsonb not null default '{}',

  assigned_to uuid references auth.users(id) on delete set null,

  submitted_at timestamptz,
  completed_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 17. PROJECT UPDATES
-- ============================================================

create table if not exists public.customer_portal_project_updates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  project_id uuid,
  project_key text,
  project_name text not null,

  update_type text not null
    check (
      update_type in (
        'construction',
        'approval',
        'payment',
        'possession',
        'registration',
        'amenity',
        'maintenance',
        'announcement',
        'other'
      )
    ),

  title text not null,
  summary text,
  content text,

  progress_percentage numeric(8,4),
  milestone_date date,

  visibility text not null default 'customers'
    check (visibility in ('customers','specific_bookings','specific_customers','public','internal')),

  status text not null default 'draft'
    check (status in ('draft','scheduled','published','archived')),

  publish_at timestamptz,
  published_at timestamptz,
  expires_at timestamptz,

  media jsonb not null default '[]',
  linked_document_ids uuid[] not null default '{}',

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.customer_portal_project_update_audience (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_update_id uuid not null references public.customer_portal_project_updates(id) on delete cascade,

  portal_account_id uuid references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete cascade,
  booking_id uuid references public.bookings(id) on delete cascade,

  read_at timestamptz,
  acknowledged_at timestamptz,

  created_at timestamptz not null default now(),

  unique (project_update_id,portal_account_id,booking_id)
);

-- ============================================================
-- 18. POSSESSION CHECKLIST
-- ============================================================

create table if not exists public.customer_portal_possession_checklists (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  booking_id uuid not null references public.bookings(id) on delete cascade,

  checklist_name text not null default 'Possession Checklist',

  status text not null default 'not_started'
    check (
      status in (
        'not_started',
        'in_progress',
        'ready',
        'completed',
        'blocked',
        'cancelled'
      )
    ),

  target_possession_date date,
  actual_possession_date date,

  completion_percentage numeric(8,4) not null default 0,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (portal_account_id,booking_id)
);

create table if not exists public.customer_portal_possession_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  checklist_id uuid not null references public.customer_portal_possession_checklists(id) on delete cascade,

  item_order integer not null,
  item_code text not null,
  item_name text not null,
  description text,

  required boolean not null default true,
  status text not null default 'pending'
    check (
      status in (
        'pending',
        'submitted',
        'verified',
        'completed',
        'waived',
        'blocked'
      )
    ),

  due_at timestamptz,
  completed_at timestamptz,

  required_document_category text,
  linked_document_id uuid references public.documents(id) on delete set null,

  notes text,
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (checklist_id,item_code),
  unique (checklist_id,item_order)
);

-- ============================================================
-- 19. REFERRAL MANAGEMENT
-- ============================================================

create table if not exists public.customer_portal_referrals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,

  referral_code text not null,

  referred_name text not null,
  referred_email text,
  referred_phone text,

  project_interest text,
  budget_range text,

  status text not null default 'submitted'
    check (
      status in (
        'submitted',
        'contacted',
        'qualified',
        'converted',
        'rejected',
        'duplicate',
        'cancelled'
      )
    ),

  created_lead_id uuid references public.leads(id) on delete set null,
  converted_booking_id uuid references public.bookings(id) on delete set null,

  reward_status text not null default 'not_applicable'
    check (
      reward_status in (
        'not_applicable',
        'pending',
        'approved',
        'paid',
        'rejected'
      )
    ),

  reward_amount numeric(18,2),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,referral_code)
);

-- ============================================================
-- 20. PORTAL PREFERENCES
-- ============================================================

create table if not exists public.customer_portal_preferences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  portal_account_id uuid not null references public.customer_portal_accounts(id) on delete cascade,

  preferred_language text not null default 'en',
  timezone text not null default 'Asia/Kolkata',

  email_notifications boolean not null default true,
  sms_notifications boolean not null default true,
  whatsapp_notifications boolean not null default true,
  push_notifications boolean not null default true,
  in_app_notifications boolean not null default true,

  payment_reminders boolean not null default true,
  project_updates boolean not null default true,
  document_updates boolean not null default true,
  support_updates boolean not null default true,
  marketing_updates boolean not null default false,

  quiet_hours_enabled boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (portal_account_id)
);

-- ============================================================
-- 21. EVENT OUTBOX AND LOGS
-- ============================================================

create table if not exists public.customer_portal_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  portal_account_id uuid references public.customer_portal_accounts(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,

  event_name text not null,

  destination text not null default 'internal'
    check (
      destination in (
        'internal',
        'automation_engine',
        'workflow_engine',
        'notification_engine',
        'communication_engine',
        'n8n',
        'analytics',
        'audit'
      )
    ),

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'claimed',
        'processing',
        'delivered',
        'failed',
        'cancelled',
        'dead_lettered'
      )
    ),

  priority integer not null default 100,
  idempotency_key text,
  correlation_id text,
  trace_id text,

  payload jsonb not null default '{}',
  headers jsonb not null default '{}',

  available_at timestamptz not null default now(),

  claimed_at timestamptz,
  claimed_by text,
  lock_token text,
  lock_expires_at timestamptz,

  delivery_attempts integer not null default 0,
  maximum_attempts integer not null default 10,

  delivered_at timestamptz,

  last_error_code text,
  last_error_message text,
  last_error_data jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists customer_portal_event_outbox_idempotency_idx
  on public.customer_portal_event_outbox (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists customer_portal_event_outbox_queue_idx
  on public.customer_portal_event_outbox (
    status,
    available_at,
    priority,
    created_at
  )
  where status in ('pending','failed');

create table if not exists public.customer_portal_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  portal_account_id uuid references public.customer_portal_accounts(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,
  support_ticket_id uuid references public.customer_portal_support_tickets(id) on delete set null,

  log_level text not null default 'info'
    check (log_level in ('debug','info','warning','error','critical')),

  event_name text,
  message text,

  error_code text,
  error_message text,
  log_data jsonb not null default '{}',

  correlation_id text,
  trace_id text,

  created_at timestamptz not null default now()
);

create index if not exists customer_portal_logs_org_created_idx
  on public.customer_portal_logs (
    organization_id,
    created_at desc
  );

-- ============================================================
-- 22. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'customer_portal_accounts',
    'customer_portal_invitations',
    'customer_portal_sessions',
    'customer_portal_access_tokens',
    'customer_portal_related_persons',
    'customer_portal_dashboard_configs',
    'customer_portal_booking_snapshots',
    'customer_portal_payment_schedules',
    'customer_portal_payment_transactions',
    'customer_portal_documents',
    'customer_portal_site_visits',
    'customer_portal_support_tickets',
    'customer_portal_service_requests',
    'customer_portal_project_updates',
    'customer_portal_possession_checklists',
    'customer_portal_referrals',
    'customer_portal_preferences',
    'customer_portal_event_outbox'
  ]
  loop
    execute format(
      'drop trigger if exists %I_set_updated_at on public.%I',
      target_table,target_table
    );

    execute format(
      'create trigger %I_set_updated_at
       before update on public.%I
       for each row
       execute function public.set_updated_at()',
      target_table,target_table
    );
  end loop;
end;
$$;

-- ============================================================
-- 23. CREATE PORTAL ACCOUNT
-- ============================================================

create or replace function public.create_customer_portal_account(
  requested_organization_id uuid,
  requested_customer_id uuid,
  requested_display_name text,
  requested_email text default null,
  requested_phone text default null,
  requested_preferred_language text default 'en',
  requested_timezone text default 'Asia/Kolkata',
  requested_metadata jsonb default '{}'::jsonb
)
returns public.customer_portal_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_record public.customer_portal_accounts;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'customer_portal.manage_accounts'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.customer_portal_accounts (
    organization_id,
    customer_id,
    account_code,
    display_name,
    primary_email,
    primary_phone,
    status,
    preferred_language,
    timezone,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    requested_customer_id,
    'CPA-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
    requested_display_name,
    requested_email,
    requested_phone,
    'invited',
    requested_preferred_language,
    requested_timezone,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  on conflict (organization_id,customer_id)
  do update set
    display_name = excluded.display_name,
    primary_email = coalesce(excluded.primary_email,customer_portal_accounts.primary_email),
    primary_phone = coalesce(excluded.primary_phone,customer_portal_accounts.primary_phone),
    updated_by = auth.uid(),
    updated_at = now()
  returning * into account_record;

  insert into public.customer_portal_preferences (
    organization_id,
    portal_account_id,
    preferred_language,
    timezone
  )
  values (
    account_record.organization_id,
    account_record.id,
    account_record.preferred_language,
    account_record.timezone
  )
  on conflict (portal_account_id)
  do nothing;

  insert into public.customer_portal_dashboard_configs (
    organization_id,
    portal_account_id
  )
  values (
    account_record.organization_id,
    account_record.id
  )
  on conflict (portal_account_id)
  do nothing;

  return account_record;
end;
$$;

revoke all
on function public.create_customer_portal_account(
  uuid,uuid,text,text,text,text,text,jsonb
)
from public;

grant execute
on function public.create_customer_portal_account(
  uuid,uuid,text,text,text,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 24. CREATE PORTAL INVITATION
-- ============================================================

create or replace function public.create_customer_portal_invitation(
  requested_portal_account_id uuid,
  requested_invitation_type text default 'activation',
  requested_email text default null,
  requested_phone text default null,
  requested_expires_at timestamptz default now() + interval '72 hours',
  requested_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_record public.customer_portal_accounts;
  raw_token text := replace(gen_random_uuid()::text,'-','')
    || replace(gen_random_uuid()::text,'-','');
  token_hash_value text;
  invitation_record public.customer_portal_invitations;
begin
  select *
  into account_record
  from public.customer_portal_accounts
  where id = requested_portal_account_id;

  if not found then
    raise exception 'Customer portal account not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      account_record.organization_id,
      'customer_portal.manage_access'
    ) then
    raise exception 'Permission denied';
  end if;

  token_hash_value := encode(
    digest(raw_token,'sha256'),
    'hex'
  );

  insert into public.customer_portal_invitations (
    organization_id,
    portal_account_id,
    invitation_type,
    token_hash,
    token_prefix,
    email,
    phone,
    status,
    expires_at,
    metadata,
    created_by
  )
  values (
    account_record.organization_id,
    account_record.id,
    requested_invitation_type,
    token_hash_value,
    left(raw_token,8),
    coalesce(requested_email,account_record.primary_email),
    coalesce(requested_phone,account_record.primary_phone),
    'pending',
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid()
  )
  returning * into invitation_record;

  return jsonb_build_object(
    'invitation_id',invitation_record.id,
    'token',raw_token,
    'expires_at',invitation_record.expires_at,
    'email',invitation_record.email,
    'phone',invitation_record.phone
  );
end;
$$;

revoke all
on function public.create_customer_portal_invitation(
  uuid,text,text,text,timestamptz,jsonb
)
from public;

grant execute
on function public.create_customer_portal_invitation(
  uuid,text,text,text,timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 25. ACCEPT PORTAL INVITATION
-- ============================================================

create or replace function public.accept_customer_portal_invitation(
  requested_token text,
  requested_user_id uuid
)
returns public.customer_portal_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  token_hash_value text;
  invitation_record public.customer_portal_invitations;
  account_record public.customer_portal_accounts;
begin
  token_hash_value := encode(
    digest(requested_token,'sha256'),
    'hex'
  );

  select *
  into invitation_record
  from public.customer_portal_invitations
  where token_hash = token_hash_value
  for update;

  if not found then
    raise exception 'Invalid portal invitation token';
  end if;

  if invitation_record.status not in ('pending','sent','opened')
    or invitation_record.expires_at <= now() then
    raise exception 'Portal invitation expired or unavailable';
  end if;

  update public.customer_portal_accounts
  set
    user_id = requested_user_id,
    status = 'active',
    activated_at = coalesce(activated_at,now()),
    updated_at = now()
  where id = invitation_record.portal_account_id
  returning * into account_record;

  update public.customer_portal_invitations
  set
    status = 'accepted',
    accepted_at = now(),
    updated_at = now()
  where id = invitation_record.id;

  return account_record;
end;
$$;

revoke all
on function public.accept_customer_portal_invitation(text,uuid)
from public;

grant execute
on function public.accept_customer_portal_invitation(text,uuid)
to anon,authenticated,service_role;

-- ============================================================
-- 26. REGISTER PORTAL SESSION
-- ============================================================

create or replace function public.register_customer_portal_session(
  requested_portal_account_id uuid,
  requested_session_key text,
  requested_ip_address inet default null,
  requested_user_agent text default null,
  requested_device_id text default null,
  requested_device_type text default null,
  requested_browser text default null,
  requested_operating_system text default null,
  requested_expires_at timestamptz default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.customer_portal_sessions
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_record public.customer_portal_accounts;
  session_record public.customer_portal_sessions;
begin
  select *
  into account_record
  from public.customer_portal_accounts
  where id = requested_portal_account_id
    and status = 'active';

  if not found then
    raise exception 'Active portal account not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from account_record.user_id then
    raise exception 'Permission denied';
  end if;

  insert into public.customer_portal_sessions (
    organization_id,
    portal_account_id,
    user_id,
    session_key,
    status,
    ip_address,
    user_agent,
    device_id,
    device_type,
    browser,
    operating_system,
    expires_at,
    metadata
  )
  values (
    account_record.organization_id,
    account_record.id,
    account_record.user_id,
    requested_session_key,
    'active',
    requested_ip_address,
    requested_user_agent,
    requested_device_id,
    requested_device_type,
    requested_browser,
    requested_operating_system,
    requested_expires_at,
    coalesce(requested_metadata,'{}'::jsonb)
  )
  on conflict (session_key)
  do update set
    status = 'active',
    last_seen_at = now(),
    ip_address = excluded.ip_address,
    user_agent = excluded.user_agent,
    device_id = excluded.device_id,
    updated_at = now()
  returning * into session_record;

  update public.customer_portal_accounts
  set
    last_login_at = now(),
    last_activity_at = now(),
    updated_at = now()
  where id = account_record.id;

  return session_record;
end;
$$;

revoke all
on function public.register_customer_portal_session(
  uuid,text,inet,text,text,text,text,text,timestamptz,jsonb
)
from public;

grant execute
on function public.register_customer_portal_session(
  uuid,text,inet,text,text,text,text,text,timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 27. CREATE SUPPORT TICKET
-- ============================================================

create or replace function public.create_customer_portal_support_ticket(
  requested_portal_account_id uuid,
  requested_category text,
  requested_subject text,
  requested_description text,
  requested_priority text default 'normal',
  requested_booking_id uuid default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.customer_portal_support_tickets
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_record public.customer_portal_accounts;
  ticket_record public.customer_portal_support_tickets;
begin
  select *
  into account_record
  from public.customer_portal_accounts
  where id = requested_portal_account_id
    and status = 'active';

  if not found then
    raise exception 'Active customer portal account not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from account_record.user_id
    and not public.has_organization_permission(
      account_record.organization_id,
      'customer_portal.manage_support'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.customer_portal_support_tickets (
    organization_id,
    portal_account_id,
    customer_id,
    booking_id,
    ticket_number,
    category,
    subject,
    description,
    priority,
    status,
    sla_due_at,
    metadata,
    created_by,
    updated_by
  )
  values (
    account_record.organization_id,
    account_record.id,
    account_record.customer_id,
    requested_booking_id,
    'TKT-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
    requested_category,
    requested_subject,
    requested_description,
    requested_priority,
    'open',
    now() + case requested_priority
      when 'critical' then interval '1 hour'
      when 'urgent' then interval '4 hours'
      when 'high' then interval '8 hours'
      else interval '24 hours'
    end,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  returning * into ticket_record;

  return ticket_record;
end;
$$;

revoke all
on function public.create_customer_portal_support_ticket(
  uuid,text,text,text,text,uuid,jsonb
)
from public;

grant execute
on function public.create_customer_portal_support_ticket(
  uuid,text,text,text,text,uuid,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 28. ADD SUPPORT MESSAGE
-- ============================================================

create or replace function public.add_customer_portal_support_message(
  requested_ticket_id uuid,
  requested_message_text text,
  requested_sender_type text default 'customer',
  requested_attachments jsonb default '[]'::jsonb,
  requested_internal_note boolean default false
)
returns public.customer_portal_support_messages
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket_record public.customer_portal_support_tickets;
  account_record public.customer_portal_accounts;
  message_record public.customer_portal_support_messages;
begin
  select *
  into ticket_record
  from public.customer_portal_support_tickets
  where id = requested_ticket_id;

  if not found then
    raise exception 'Support ticket not found';
  end if;

  select *
  into account_record
  from public.customer_portal_accounts
  where id = ticket_record.portal_account_id;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from account_record.user_id
    and not public.has_organization_permission(
      ticket_record.organization_id,
      'customer_portal.manage_support'
    ) then
    raise exception 'Permission denied';
  end if;

  if requested_internal_note
    and auth.uid() is not distinct from account_record.user_id then
    raise exception 'Customer cannot create internal support notes';
  end if;

  insert into public.customer_portal_support_messages (
    organization_id,
    ticket_id,
    sender_type,
    sender_user_id,
    message_text,
    attachments,
    is_internal_note
  )
  values (
    ticket_record.organization_id,
    ticket_record.id,
    requested_sender_type,
    auth.uid(),
    requested_message_text,
    coalesce(requested_attachments,'[]'::jsonb),
    requested_internal_note
  )
  returning * into message_record;

  update public.customer_portal_support_tickets
  set
    status = case
      when requested_sender_type = 'customer' then 'waiting_internal'
      else 'waiting_customer'
    end,
    first_response_at = case
      when requested_sender_type <> 'customer'
        then coalesce(first_response_at,now())
      else first_response_at
    end,
    updated_at = now()
  where id = ticket_record.id;

  return message_record;
end;
$$;

revoke all
on function public.add_customer_portal_support_message(
  uuid,text,text,jsonb,boolean
)
from public;

grant execute
on function public.add_customer_portal_support_message(
  uuid,text,text,jsonb,boolean
)
to authenticated,service_role;

-- ============================================================
-- 29. SUBMIT REFERRAL
-- ============================================================

create or replace function public.submit_customer_portal_referral(
  requested_portal_account_id uuid,
  requested_referred_name text,
  requested_referred_email text default null,
  requested_referred_phone text default null,
  requested_project_interest text default null,
  requested_budget_range text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.customer_portal_referrals
language plpgsql
security definer
set search_path = ''
as $$
declare
  account_record public.customer_portal_accounts;
  referral_record public.customer_portal_referrals;
begin
  select *
  into account_record
  from public.customer_portal_accounts
  where id = requested_portal_account_id
    and status = 'active';

  if not found then
    raise exception 'Active customer portal account not found';
  end if;

  if auth.role() <> 'service_role'
    and auth.uid() is distinct from account_record.user_id
    and not public.has_organization_permission(
      account_record.organization_id,
      'customer_portal.manage_referrals'
    ) then
    raise exception 'Permission denied';
  end if;

  insert into public.customer_portal_referrals (
    organization_id,
    portal_account_id,
    customer_id,
    referral_code,
    referred_name,
    referred_email,
    referred_phone,
    project_interest,
    budget_range,
    status,
    metadata
  )
  values (
    account_record.organization_id,
    account_record.id,
    account_record.customer_id,
    'REF-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
    requested_referred_name,
    requested_referred_email,
    requested_referred_phone,
    requested_project_interest,
    requested_budget_range,
    'submitted',
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into referral_record;

  return referral_record;
end;
$$;

revoke all
on function public.submit_customer_portal_referral(
  uuid,text,text,text,text,text,jsonb
)
from public;

grant execute
on function public.submit_customer_portal_referral(
  uuid,text,text,text,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 30. PUBLISH PORTAL EVENT
-- ============================================================

create or replace function public.publish_customer_portal_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_portal_account_id uuid default null,
  requested_customer_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.customer_portal_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.customer_portal_event_outbox;
  created_event public.customer_portal_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.customer_portal_event_outbox e
    where e.organization_id = requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.customer_portal_event_outbox (
    organization_id,
    portal_account_id,
    customer_id,
    event_name,
    destination,
    status,
    priority,
    idempotency_key,
    correlation_id,
    trace_id,
    payload,
    available_at
  )
  values (
    requested_organization_id,
    requested_portal_account_id,
    requested_customer_id,
    requested_event_name,
    requested_destination,
    'pending',
    requested_priority,
    requested_idempotency_key,
    requested_correlation_id,
    requested_trace_id,
    coalesce(requested_payload,'{}'::jsonb),
    coalesce(requested_available_at,now())
  )
  returning * into created_event;

  return created_event;
end;
$$;

revoke all
on function public.publish_customer_portal_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_customer_portal_event(
  uuid,text,jsonb,text,uuid,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 31. SUPPORT TICKET EVENT TRIGGER
-- ============================================================

create or replace function public.emit_customer_portal_ticket_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload_data jsonb;
begin
  if tg_op = 'UPDATE'
    and new.status is not distinct from old.status
    and new.assigned_to is not distinct from old.assigned_to then
    return new;
  end if;

  payload_data := jsonb_build_object(
    'organization_id',new.organization_id,
    'portal_account_id',new.portal_account_id,
    'customer_id',new.customer_id,
    'ticket_id',new.id,
    'ticket_number',new.ticket_number,
    'category',new.category,
    'subject',new.subject,
    'priority',new.priority,
    'status',new.status,
    'assigned_to',new.assigned_to,
    'sla_due_at',new.sla_due_at
  );

  perform public.publish_customer_portal_event(
    new.organization_id,
    'customer_portal.ticket.' || new.status,
    payload_data,
    'notification_engine',
    new.portal_account_id,
    new.customer_id,
    case
      when new.priority in ('critical','urgent') then 10
      else 50
    end,
    'portal-ticket-notification:' || new.id::text || ':' || new.status,
    new.id::text,
    null,
    now()
  );

  perform public.publish_customer_portal_event(
    new.organization_id,
    'customer_portal.ticket.' || new.status,
    payload_data,
    'automation_engine',
    new.portal_account_id,
    new.customer_id,
    50,
    'portal-ticket-automation:' || new.id::text || ':' || new.status,
    new.id::text,
    null,
    now()
  );

  return new;
end;
$$;

drop trigger if exists customer_portal_support_tickets_emit_events
on public.customer_portal_support_tickets;

create trigger customer_portal_support_tickets_emit_events
after insert or update
on public.customer_portal_support_tickets
for each row
execute function public.emit_customer_portal_ticket_events();

-- ============================================================
-- 32. DASHBOARD VIEWS
-- ============================================================

create or replace view public.customer_portal_account_dashboard
with (security_invoker = true)
as
select
  a.organization_id,
  a.id as portal_account_id,
  a.customer_id,
  a.user_id,
  a.display_name,
  a.status,

  (select count(*)
   from public.customer_portal_booking_snapshots b
   where b.portal_account_id = a.id) as booking_count,

  (select coalesce(sum(p.amount_due),0)
   from public.customer_portal_payment_schedules p
   where p.portal_account_id = a.id) as total_payment_due,

  (select coalesce(sum(p.amount_paid),0)
   from public.customer_portal_payment_schedules p
   where p.portal_account_id = a.id) as total_payment_paid,

  (select coalesce(sum(p.outstanding_amount),0)
   from public.customer_portal_payment_schedules p
   where p.portal_account_id = a.id) as total_outstanding,

  (select count(*)
   from public.customer_portal_documents d
   where d.portal_account_id = a.id
     and d.visibility_status = 'visible') as visible_documents,

  (select count(*)
   from public.customer_portal_support_tickets t
   where t.portal_account_id = a.id
     and t.status not in ('resolved','closed','cancelled')) as open_support_tickets,

  (select count(*)
   from public.customer_portal_project_update_audience u
   where u.portal_account_id = a.id
     and u.read_at is null) as unread_project_updates,

  (select count(*)
   from public.notification_inbox i
   where i.user_id = a.user_id
     and i.status = 'unread') as unread_notifications,

  a.last_login_at,
  a.last_activity_at

from public.customer_portal_accounts a;

create or replace view public.customer_portal_payment_dashboard
with (security_invoker = true)
as
select
  organization_id,
  portal_account_id,
  booking_id,

  count(*) as installment_count,

  coalesce(sum(amount_due),0) as total_due,
  coalesce(sum(amount_paid),0) as total_paid,
  coalesce(sum(outstanding_amount),0) as outstanding_amount,

  count(*) filter (
    where status = 'overdue'
  ) as overdue_installments,

  min(due_date) filter (
    where status in ('scheduled','due','partially_paid','overdue')
  ) as next_due_date

from public.customer_portal_payment_schedules
group by
  organization_id,
  portal_account_id,
  booking_id;

create or replace view public.customer_portal_support_dashboard
with (security_invoker = true)
as
select
  organization_id,

  count(*) as total_tickets,

  count(*) filter (
    where status in ('open','assigned','in_progress','waiting_internal','waiting_customer')
  ) as open_tickets,

  count(*) filter (
    where status = 'resolved'
  ) as resolved_tickets,

  count(*) filter (
    where sla_due_at < now()
      and status not in ('resolved','closed','cancelled')
  ) as sla_breached_tickets,

  round(
    avg(
      extract(
        epoch from (
          coalesce(first_response_at,now()) - created_at
        )
      ) / 60
    ) filter (
      where first_response_at is not null
    ),
    2
  ) as average_first_response_minutes,

  round(avg(customer_rating),2) as average_customer_rating

from public.customer_portal_support_tickets
group by organization_id;

create or replace view public.customer_portal_engagement_dashboard
with (security_invoker = true)
as
select
  a.organization_id,

  count(*) as total_accounts,

  count(*) filter (
    where a.status = 'active'
  ) as active_accounts,

  count(*) filter (
    where a.last_login_at >= now() - interval '30 days'
  ) as active_30_days,

  count(*) filter (
    where a.onboarding_completed = true
  ) as onboarding_completed_accounts,

  count(s.id) as total_sessions,

  round(
    count(*) filter (
      where a.last_login_at >= now() - interval '30 days'
    )::numeric
    / nullif(count(*),0) * 100,
    2
  ) as monthly_active_rate

from public.customer_portal_accounts a
left join public.customer_portal_sessions s
  on s.portal_account_id = a.id
group by a.organization_id;

grant select
on
  public.customer_portal_account_dashboard,
  public.customer_portal_payment_dashboard,
  public.customer_portal_support_dashboard,
  public.customer_portal_engagement_dashboard
to authenticated,service_role;

-- ============================================================
-- 33. HEALTH CHECK
-- ============================================================

create or replace function public.get_customer_portal_engine_health(
  requested_organization_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role'
    and (
      requested_organization_id is null
      or not public.has_organization_permission(
        requested_organization_id,
        'customer_portal.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'active_accounts',(
      select count(*)
      from public.customer_portal_accounts a
      where a.status = 'active'
        and (
          requested_organization_id is null
          or a.organization_id = requested_organization_id
        )
    ),

    'pending_invitations',(
      select count(*)
      from public.customer_portal_invitations i
      where i.status in ('pending','sent','opened')
        and i.expires_at > now()
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'active_sessions',(
      select count(*)
      from public.customer_portal_sessions s
      where s.status = 'active'
        and (
          requested_organization_id is null
          or s.organization_id = requested_organization_id
        )
    ),

    'open_support_tickets',(
      select count(*)
      from public.customer_portal_support_tickets t
      where t.status in ('open','assigned','in_progress','waiting_internal','waiting_customer')
        and (
          requested_organization_id is null
          or t.organization_id = requested_organization_id
        )
    ),

    'overdue_payments',(
      select count(*)
      from public.customer_portal_payment_schedules p
      where p.status = 'overdue'
        and (
          requested_organization_id is null
          or p.organization_id = requested_organization_id
        )
    ),

    'pending_service_requests',(
      select count(*)
      from public.customer_portal_service_requests r
      where r.status in ('submitted','under_review','processing')
        and (
          requested_organization_id is null
          or r.organization_id = requested_organization_id
        )
    ),

    'pending_possession_items',(
      select count(*)
      from public.customer_portal_possession_items i
      where i.status in ('pending','submitted','blocked')
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.customer_portal_event_outbox e
      where e.status in ('pending','failed')
        and (
          requested_organization_id is null
          or e.organization_id = requested_organization_id
        )
    )
  );
end;
$$;

revoke all
on function public.get_customer_portal_engine_health(uuid)
from public;

grant execute
on function public.get_customer_portal_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 34. RLS
-- ============================================================

alter table public.customer_portal_accounts enable row level security;
alter table public.customer_portal_invitations enable row level security;
alter table public.customer_portal_sessions enable row level security;
alter table public.customer_portal_access_tokens enable row level security;
alter table public.customer_portal_related_persons enable row level security;
alter table public.customer_portal_dashboard_configs enable row level security;
alter table public.customer_portal_timeline_events enable row level security;
alter table public.customer_portal_booking_snapshots enable row level security;
alter table public.customer_portal_payment_schedules enable row level security;
alter table public.customer_portal_payment_transactions enable row level security;
alter table public.customer_portal_documents enable row level security;
alter table public.customer_portal_site_visits enable row level security;
alter table public.customer_portal_communications enable row level security;
alter table public.customer_portal_support_tickets enable row level security;
alter table public.customer_portal_support_messages enable row level security;
alter table public.customer_portal_service_requests enable row level security;
alter table public.customer_portal_project_updates enable row level security;
alter table public.customer_portal_project_update_audience enable row level security;
alter table public.customer_portal_possession_checklists enable row level security;
alter table public.customer_portal_possession_items enable row level security;
alter table public.customer_portal_referrals enable row level security;
alter table public.customer_portal_preferences enable row level security;
alter table public.customer_portal_event_outbox enable row level security;
alter table public.customer_portal_logs enable row level security;

drop policy if exists customer_portal_accounts_self_select
on public.customer_portal_accounts;

create policy customer_portal_accounts_self_select
on public.customer_portal_accounts
for select
to authenticated
using (
  user_id = auth.uid()
  or public.has_organization_permission(
    organization_id,
    'customer_portal.view_all'
  )
);

drop policy if exists customer_portal_accounts_service
on public.customer_portal_accounts;

create policy customer_portal_accounts_service
on public.customer_portal_accounts
for all
to service_role
using (true)
with check (true);

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'customer_portal_invitations',
    'customer_portal_sessions',
    'customer_portal_access_tokens',
    'customer_portal_related_persons',
    'customer_portal_dashboard_configs',
    'customer_portal_timeline_events',
    'customer_portal_booking_snapshots',
    'customer_portal_payment_schedules',
    'customer_portal_payment_transactions',
    'customer_portal_documents',
    'customer_portal_site_visits',
    'customer_portal_communications',
    'customer_portal_support_tickets',
    'customer_portal_service_requests',
    'customer_portal_project_update_audience',
    'customer_portal_possession_checklists',
    'customer_portal_referrals',
    'customer_portal_preferences',
    'customer_portal_event_outbox',
    'customer_portal_logs'
  ]
  loop
    execute format(
      'drop policy if exists %I_select_policy on public.%I',
      target_table,target_table
    );

    execute format(
      'create policy %I_select_policy
       on public.%I
       for select
       to authenticated
       using (
         exists (
           select 1
           from public.customer_portal_accounts a
           where a.id = %I.portal_account_id
             and a.user_id = auth.uid()
         )
         or public.has_organization_permission(
           organization_id,
           ''customer_portal.view_all''
         )
       )',
      target_table,target_table,target_table
    );

    execute format(
      'drop policy if exists %I_service_policy on public.%I',
      target_table,target_table
    );

    execute format(
      'create policy %I_service_policy
       on public.%I
       for all
       to service_role
       using (true)
       with check (true)',
      target_table,target_table
    );
  end loop;
end;
$$;

-- Child-table RLS: support messages inherit portal ownership through ticket.
drop policy if exists customer_portal_support_messages_select_policy
on public.customer_portal_support_messages;

create policy customer_portal_support_messages_select_policy
on public.customer_portal_support_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.customer_portal_support_tickets t
    join public.customer_portal_accounts a
      on a.id = t.portal_account_id
    where t.id = customer_portal_support_messages.ticket_id
      and a.user_id = auth.uid()
      and (
        customer_portal_support_messages.is_internal_note = false
        or public.has_organization_permission(
          customer_portal_support_messages.organization_id,
          'customer_portal.manage_support'
        )
      )
  )
  or public.has_organization_permission(
    organization_id,
    'customer_portal.view_all'
  )
);

drop policy if exists customer_portal_support_messages_service_policy
on public.customer_portal_support_messages;

create policy customer_portal_support_messages_service_policy
on public.customer_portal_support_messages
for all
to service_role
using (true)
with check (true);

-- Child-table RLS: possession items inherit portal ownership through checklist.
drop policy if exists customer_portal_possession_items_select_policy
on public.customer_portal_possession_items;

create policy customer_portal_possession_items_select_policy
on public.customer_portal_possession_items
for select
to authenticated
using (
  exists (
    select 1
    from public.customer_portal_possession_checklists c
    join public.customer_portal_accounts a
      on a.id = c.portal_account_id
    where c.id = customer_portal_possession_items.checklist_id
      and a.user_id = auth.uid()
  )
  or public.has_organization_permission(
    organization_id,
    'customer_portal.view_all'
  )
);

drop policy if exists customer_portal_possession_items_service_policy
on public.customer_portal_possession_items;

create policy customer_portal_possession_items_service_policy
on public.customer_portal_possession_items
for all
to service_role
using (true)
with check (true);

drop policy if exists customer_portal_project_updates_select
on public.customer_portal_project_updates;

create policy customer_portal_project_updates_select
on public.customer_portal_project_updates
for select
to authenticated
using (
  status = 'published'
  or public.has_organization_permission(
    organization_id,
    'customer_portal.view_all'
  )
);

drop policy if exists customer_portal_project_updates_service
on public.customer_portal_project_updates;

create policy customer_portal_project_updates_service
on public.customer_portal_project_updates
for all
to service_role
using (true)
with check (true);

drop policy if exists customer_portal_support_tickets_customer_write
on public.customer_portal_support_tickets;

create policy customer_portal_support_tickets_customer_write
on public.customer_portal_support_tickets
for insert
to authenticated
with check (
  exists (
    select 1
    from public.customer_portal_accounts a
    where a.id = portal_account_id
      and a.user_id = auth.uid()
  )
  or public.has_organization_permission(
    organization_id,
    'customer_portal.manage_support'
  )
);

drop policy if exists customer_portal_referrals_customer_write
on public.customer_portal_referrals;

create policy customer_portal_referrals_customer_write
on public.customer_portal_referrals
for insert
to authenticated
with check (
  exists (
    select 1
    from public.customer_portal_accounts a
    where a.id = portal_account_id
      and a.user_id = auth.uid()
  )
  or public.has_organization_permission(
    organization_id,
    'customer_portal.manage_referrals'
  )
);

-- ============================================================
-- 35. GRANTS
-- ============================================================

grant select
on
  public.customer_portal_accounts,
  public.customer_portal_invitations,
  public.customer_portal_sessions,
  public.customer_portal_access_tokens,
  public.customer_portal_related_persons,
  public.customer_portal_dashboard_configs,
  public.customer_portal_timeline_events,
  public.customer_portal_booking_snapshots,
  public.customer_portal_payment_schedules,
  public.customer_portal_payment_transactions,
  public.customer_portal_documents,
  public.customer_portal_site_visits,
  public.customer_portal_communications,
  public.customer_portal_support_tickets,
  public.customer_portal_support_messages,
  public.customer_portal_service_requests,
  public.customer_portal_project_updates,
  public.customer_portal_project_update_audience,
  public.customer_portal_possession_checklists,
  public.customer_portal_possession_items,
  public.customer_portal_referrals,
  public.customer_portal_preferences,
  public.customer_portal_event_outbox,
  public.customer_portal_logs
to authenticated;

grant insert,update
on
  public.customer_portal_support_tickets,
  public.customer_portal_support_messages,
  public.customer_portal_service_requests,
  public.customer_portal_referrals,
  public.customer_portal_preferences,
  public.customer_portal_project_update_audience,
  public.customer_portal_possession_items
to authenticated;

grant all
on
  public.customer_portal_accounts,
  public.customer_portal_invitations,
  public.customer_portal_sessions,
  public.customer_portal_access_tokens,
  public.customer_portal_related_persons,
  public.customer_portal_dashboard_configs,
  public.customer_portal_timeline_events,
  public.customer_portal_booking_snapshots,
  public.customer_portal_payment_schedules,
  public.customer_portal_payment_transactions,
  public.customer_portal_documents,
  public.customer_portal_site_visits,
  public.customer_portal_communications,
  public.customer_portal_support_tickets,
  public.customer_portal_support_messages,
  public.customer_portal_service_requests,
  public.customer_portal_project_updates,
  public.customer_portal_project_update_audience,
  public.customer_portal_possession_checklists,
  public.customer_portal_possession_items,
  public.customer_portal_referrals,
  public.customer_portal_preferences,
  public.customer_portal_event_outbox,
  public.customer_portal_logs
to service_role;

-- ============================================================
-- 36. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'customer_portal_accounts',
    'customer_portal_invitations',
    'customer_portal_sessions',
    'customer_portal_access_tokens',
    'customer_portal_related_persons',
    'customer_portal_dashboard_configs',
    'customer_portal_timeline_events',
    'customer_portal_booking_snapshots',
    'customer_portal_payment_schedules',
    'customer_portal_payment_transactions',
    'customer_portal_documents',
    'customer_portal_site_visits',
    'customer_portal_communications',
    'customer_portal_support_tickets',
    'customer_portal_service_requests',
    'customer_portal_project_updates',
    'customer_portal_project_update_audience',
    'customer_portal_possession_checklists',
    'customer_portal_referrals',
    'customer_portal_preferences',
    'customer_portal_event_outbox',
    'customer_portal_logs'
  ]
  loop
    if not exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = item
    ) then
      missing_items := array_append(
        missing_items,
        'table:' || item
      );
    end if;
  end loop;

  foreach item in array array[
    'create_customer_portal_account',
    'create_customer_portal_invitation',
    'accept_customer_portal_invitation',
    'register_customer_portal_session',
    'create_customer_portal_support_ticket',
    'add_customer_portal_support_message',
    'submit_customer_portal_referral',
    'publish_customer_portal_event',
    'get_customer_portal_engine_health'
  ]
  loop
    if not exists (
      select 1
      from information_schema.routines
      where routine_schema = 'public'
        and routine_name = item
    ) then
      missing_items := array_append(
        missing_items,
        'function:' || item
      );
    end if;
  end loop;

  if cardinality(missing_items) > 0 then
    raise exception
      '019 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 37. MIGRATION AUDIT
-- ============================================================

insert into public.customer_portal_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.019.completed',
  'Customer Portal Engine migration 019 completed',
  jsonb_build_object(
    'migration',
    '019_customer_portal_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'portal_accounts',
      'invitations',
      'sessions',
      'access_tokens',
      'related_persons',
      'dashboard',
      'timeline',
      'booking_snapshots',
      'payment_schedules',
      'payment_transactions',
      'documents',
      'site_visits',
      'communications',
      'support_tickets',
      'service_requests',
      'project_updates',
      'possession_checklist',
      'referrals',
      'preferences',
      'event_outbox',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.customer_portal_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.019.completed'
);

commit;