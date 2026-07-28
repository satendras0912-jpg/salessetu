-- ============================================================
-- SalesSetu Enterprise
-- Migration 020: Finance & Commission Engine
-- PostgreSQL / Supabase
-- ============================================================
--
-- Dependencies:
--   001_initial_schema.sql
--   002_rbac.sql
--   003_leads.sql
--   006_bookings.sql
--   007_customer_success.sql
--   008_inventory.sql
--   012_assignment_engine.sql
--   013_communication_engine.sql
--   014_automation_execution_engine.sql
--   015_notification_engine.sql
--   016_Audit_Activity_Engine.sql
--   017_Analytics_BI_Engine.sql
--   018_Document_Management_Engine.sql
--   019_Customer_Portal_Engine_v2.sql
--
-- Scope:
--   • Chart of accounts and finance settings
--   • Booking revenue and brokerage receivables
--   • Builder invoices and customer invoices
--   • Commission plans, slabs, accruals and payouts
--   • Agent incentives, clawbacks and adjustments
--   • Payment receipts and reconciliation
--   • Taxes, TDS/GST metadata and settlement tracking
--   • Ledger entries, journal entries and auditability
--   • Financial alerts, event outbox and analytics
--   • RLS, permissions, grants, health checks and validation
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
    ('finance','view','finance.view','View finance records'),
    ('finance','view_all','finance.view_all','View all organization finance records'),
    ('finance','view_sensitive','finance.view_sensitive','View sensitive finance data'),
    ('finance','manage_settings','finance.manage_settings','Manage finance settings'),
    ('finance','manage_accounts','finance.manage_accounts','Manage chart of accounts'),
    ('finance','manage_invoices','finance.manage_invoices','Manage invoices'),
    ('finance','manage_receipts','finance.manage_receipts','Manage receipts'),
    ('finance','manage_commissions','finance.manage_commissions','Manage commission plans and accruals'),
    ('finance','approve_commissions','finance.approve_commissions','Approve commission payouts'),
    ('finance','manage_payouts','finance.manage_payouts','Manage payouts'),
    ('finance','manage_reconciliation','finance.manage_reconciliation','Manage payment reconciliation'),
    ('finance','manage_adjustments','finance.manage_adjustments','Manage financial adjustments'),
    ('finance','export','finance.export','Export finance reports'),
    ('finance','view_logs','finance.view_logs','View finance logs'),
    ('finance','view_analytics','finance.view_analytics','View finance analytics')
) as p(module,action,code,description)
where not exists (
  select 1
  from public.permissions existing
  where existing.code = p.code
);

-- ============================================================
-- 2. FINANCE SETTINGS
-- ============================================================

create table if not exists public.finance_settings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  base_currency text not null default 'INR',
  fiscal_year_start_month integer not null default 4
    check (fiscal_year_start_month between 1 and 12),

  invoice_prefix text not null default 'INV',
  receipt_prefix text not null default 'RCT',
  payout_prefix text not null default 'PAY',
  journal_prefix text not null default 'JRN',

  default_gst_rate numeric(8,4) not null default 18,
  default_tds_rate numeric(8,4) not null default 5,

  gst_enabled boolean not null default true,
  tds_enabled boolean not null default true,

  gstin text,
  pan text,
  legal_name text,
  billing_address jsonb not null default '{}',

  invoice_due_days integer not null default 30,
  commission_lock_days integer not null default 7,
  payout_cycle text not null default 'monthly'
    check (payout_cycle in ('weekly','fortnightly','monthly','quarterly','manual')),

  status text not null default 'active'
    check (status in ('active','inactive')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id)
);

-- ============================================================
-- 3. CHART OF ACCOUNTS
-- ============================================================

create table if not exists public.finance_accounts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  parent_account_id uuid references public.finance_accounts(id) on delete set null,

  account_code text not null,
  account_name text not null,

  account_type text not null
    check (
      account_type in (
        'asset',
        'liability',
        'equity',
        'revenue',
        'expense',
        'contra_asset',
        'contra_revenue'
      )
    ),

  account_subtype text,
  currency text not null default 'INR',

  normal_balance text not null
    check (normal_balance in ('debit','credit')),

  is_control_account boolean not null default false,
  is_system_account boolean not null default false,
  allow_manual_entries boolean not null default true,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,account_code)
);

-- ============================================================
-- 4. BUSINESS PARTIES
-- ============================================================

create table if not exists public.finance_parties (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  party_type text not null
    check (
      party_type in (
        'customer',
        'builder',
        'agent',
        'vendor',
        'organization',
        'employee',
        'other'
      )
    ),

  party_name text not null,
  external_reference text,

  customer_id uuid references public.customers(id) on delete set null,
  user_id uuid references auth.users(id) on delete set null,
  agent_profile_id uuid references public.assignment_agent_profiles(id) on delete set null,

  email text,
  phone text,

  gstin text,
  pan text,
  tax_residency text default 'IN',

  billing_address jsonb not null default '{}',
  bank_details jsonb not null default '{}',

  status text not null default 'active'
    check (status in ('active','inactive','blocked','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists finance_parties_lookup_idx
  on public.finance_parties (
    organization_id,
    party_type,
    status
  );

-- ============================================================
-- 5. INVOICES
-- ============================================================

create table if not exists public.finance_invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  invoice_number text not null,
  invoice_type text not null
    check (
      invoice_type in (
        'customer_invoice',
        'builder_invoice',
        'commission_invoice',
        'credit_note',
        'debit_note',
        'proforma'
      )
    ),

  party_id uuid references public.finance_parties(id) on delete set null,
  booking_id uuid references public.bookings(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,

  invoice_date date not null default current_date,
  due_date date,

  currency text not null default 'INR',

  subtotal numeric(18,2) not null default 0,
  discount_amount numeric(18,2) not null default 0,
  taxable_amount numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  total_amount numeric(18,2) not null default 0,
  paid_amount numeric(18,2) not null default 0,
  outstanding_amount numeric(18,2) generated always as (
    greatest(total_amount - paid_amount,0)
  ) stored,

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'issued',
        'sent',
        'partially_paid',
        'paid',
        'overdue',
        'cancelled',
        'void'
      )
    ),

  tax_details jsonb not null default '{}',
  billing_details jsonb not null default '{}',

  document_id uuid references public.documents(id) on delete set null,

  issued_at timestamptz,
  sent_at timestamptz,
  paid_at timestamptz,
  cancelled_at timestamptz,

  notes text,
  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,invoice_number)
);

create index if not exists finance_invoices_status_idx
  on public.finance_invoices (
    organization_id,
    status,
    due_date
  );

-- ============================================================
-- 6. INVOICE LINE ITEMS
-- ============================================================

create table if not exists public.finance_invoice_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  invoice_id uuid not null references public.finance_invoices(id) on delete cascade,

  line_number integer not null,
  item_type text not null default 'service'
    check (
      item_type in (
        'service',
        'commission',
        'brokerage',
        'fee',
        'tax',
        'discount',
        'adjustment',
        'other'
      )
    ),

  item_code text,
  description text not null,

  quantity numeric(18,4) not null default 1,
  unit_price numeric(18,2) not null default 0,

  discount_rate numeric(8,4) not null default 0,
  discount_amount numeric(18,2) not null default 0,

  taxable_value numeric(18,2) not null default 0,
  tax_rate numeric(8,4) not null default 0,
  tax_amount numeric(18,2) not null default 0,

  line_total numeric(18,2) not null default 0,

  account_id uuid references public.finance_accounts(id) on delete set null,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (invoice_id,line_number)
);

-- ============================================================
-- 7. PAYMENT RECEIPTS
-- ============================================================

create table if not exists public.finance_payment_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  receipt_number text not null,
  party_id uuid references public.finance_parties(id) on delete set null,
  invoice_id uuid references public.finance_invoices(id) on delete set null,
  booking_id uuid references public.bookings(id) on delete set null,
  customer_id uuid references public.customers(id) on delete set null,

  payment_method text,
  transaction_reference text,
  external_transaction_id text,

  amount numeric(18,2) not null,
  currency text not null default 'INR',

  status text not null default 'received'
    check (
      status in (
        'pending',
        'received',
        'verified',
        'reconciled',
        'failed',
        'reversed',
        'refunded'
      )
    ),

  received_at timestamptz not null default now(),
  verified_at timestamptz,
  reconciled_at timestamptz,

  bank_account_reference text,
  payment_gateway text,

  receipt_document_id uuid references public.documents(id) on delete set null,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,receipt_number)
);

create index if not exists finance_payment_receipts_lookup_idx
  on public.finance_payment_receipts (
    organization_id,
    status,
    received_at desc
  );

-- ============================================================
-- 8. COMMISSION PLANS
-- ============================================================

create table if not exists public.finance_commission_plans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  plan_code text not null,
  plan_name text not null,
  description text,

  applies_to text not null
    check (
      applies_to in (
        'agent',
        'team',
        'manager',
        'channel_partner',
        'referrer',
        'custom'
      )
    ),

  calculation_basis text not null
    check (
      calculation_basis in (
        'booking_value',
        'brokerage_value',
        'collected_revenue',
        'fixed_amount',
        'unit_count',
        'custom'
      )
    ),

  default_rate numeric(10,4),
  fixed_amount numeric(18,2),

  effective_from date not null,
  effective_to date,

  status text not null default 'active'
    check (status in ('draft','active','inactive','archived')),

  clawback_enabled boolean not null default true,
  clawback_window_days integer not null default 90,

  approval_required boolean not null default true,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,plan_code)
);

-- ============================================================
-- 9. COMMISSION SLABS
-- ============================================================

create table if not exists public.finance_commission_slabs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  commission_plan_id uuid not null references public.finance_commission_plans(id) on delete cascade,

  slab_order integer not null,
  minimum_value numeric(18,2) not null default 0,
  maximum_value numeric(18,2),

  rate numeric(10,4),
  fixed_amount numeric(18,2),

  metric_period text default 'booking'
    check (metric_period in ('booking','month','quarter','year','lifetime')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (commission_plan_id,slab_order)
);

-- ============================================================
-- 10. COMMISSION ASSIGNMENTS
-- ============================================================

create table if not exists public.finance_commission_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  commission_plan_id uuid not null references public.finance_commission_plans(id) on delete cascade,

  assignee_type text not null
    check (
      assignee_type in (
        'agent',
        'team',
        'manager',
        'channel_partner',
        'referrer',
        'user'
      )
    ),

  agent_profile_id uuid references public.assignment_agent_profiles(id) on delete cascade,
  team_id uuid references public.assignment_teams(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  external_reference text,

  priority integer not null default 100,

  effective_from date not null,
  effective_to date,

  status text not null default 'active'
    check (status in ('active','inactive','archived')),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 11. COMMISSION ACCRUALS
-- ============================================================

create table if not exists public.finance_commission_accruals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  booking_id uuid not null references public.bookings(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,

  commission_plan_id uuid references public.finance_commission_plans(id) on delete set null,
  commission_assignment_id uuid references public.finance_commission_assignments(id) on delete set null,

  beneficiary_type text not null
    check (
      beneficiary_type in (
        'agent',
        'team',
        'manager',
        'channel_partner',
        'referrer',
        'user'
      )
    ),

  beneficiary_agent_profile_id uuid references public.assignment_agent_profiles(id) on delete set null,
  beneficiary_team_id uuid references public.assignment_teams(id) on delete set null,
  beneficiary_user_id uuid references auth.users(id) on delete set null,
  beneficiary_reference text,

  basis_type text not null,
  basis_amount numeric(18,2) not null default 0,

  commission_rate numeric(10,4),
  gross_commission numeric(18,2) not null default 0,

  tax_withheld numeric(18,2) not null default 0,
  tds_amount numeric(18,2) not null default 0,
  adjustments_amount numeric(18,2) not null default 0,
  clawback_amount numeric(18,2) not null default 0,

  net_commission numeric(18,2) generated always as (
    greatest(
      gross_commission
      - tax_withheld
      - tds_amount
      + adjustments_amount
      - clawback_amount,
      0
    )
  ) stored,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'calculated',
        'locked',
        'approved',
        'partially_paid',
        'paid',
        'clawed_back',
        'cancelled',
        'disputed'
      )
    ),

  accrued_at timestamptz not null default now(),
  lock_at timestamptz,
  approved_at timestamptz,
  paid_at timestamptz,

  approved_by uuid references auth.users(id) on delete set null,

  calculation_data jsonb not null default '{}',
  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists finance_commission_accruals_beneficiary_idx
  on public.finance_commission_accruals (
    organization_id,
    beneficiary_user_id,
    beneficiary_agent_profile_id,
    status
  );

-- ============================================================
-- 12. COMMISSION ADJUSTMENTS
-- ============================================================

create table if not exists public.finance_commission_adjustments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  commission_accrual_id uuid not null references public.finance_commission_accruals(id) on delete cascade,

  adjustment_type text not null
    check (
      adjustment_type in (
        'bonus',
        'penalty',
        'correction',
        'clawback',
        'tax',
        'tds',
        'manual',
        'other'
      )
    ),

  amount numeric(18,2) not null,
  reason text not null,

  status text not null default 'pending'
    check (status in ('pending','approved','rejected','applied','cancelled')),

  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 13. COMMISSION PAYOUTS
-- ============================================================

create table if not exists public.finance_commission_payouts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  payout_number text not null,

  beneficiary_type text not null,
  beneficiary_agent_profile_id uuid references public.assignment_agent_profiles(id) on delete set null,
  beneficiary_team_id uuid references public.assignment_teams(id) on delete set null,
  beneficiary_user_id uuid references auth.users(id) on delete set null,
  beneficiary_reference text,

  period_start date,
  period_end date,

  gross_amount numeric(18,2) not null default 0,
  deduction_amount numeric(18,2) not null default 0,
  tds_amount numeric(18,2) not null default 0,
  net_amount numeric(18,2) not null default 0,

  currency text not null default 'INR',

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'pending_approval',
        'approved',
        'processing',
        'paid',
        'failed',
        'cancelled',
        'reversed'
      )
    ),

  payment_method text,
  bank_reference text,
  external_transaction_id text,

  approved_by uuid references auth.users(id) on delete set null,
  approved_at timestamptz,
  processed_at timestamptz,
  paid_at timestamptz,

  payout_document_id uuid references public.documents(id) on delete set null,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,payout_number)
);

create table if not exists public.finance_commission_payout_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  payout_id uuid not null references public.finance_commission_payouts(id) on delete cascade,
  commission_accrual_id uuid not null references public.finance_commission_accruals(id) on delete restrict,

  gross_amount numeric(18,2) not null default 0,
  deduction_amount numeric(18,2) not null default 0,
  tds_amount numeric(18,2) not null default 0,
  net_amount numeric(18,2) not null default 0,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  unique (payout_id,commission_accrual_id)
);

-- ============================================================
-- 14. BUILDER RECEIVABLES
-- ============================================================

create table if not exists public.finance_builder_receivables (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  booking_id uuid not null references public.bookings(id) on delete cascade,
  builder_party_id uuid references public.finance_parties(id) on delete set null,

  project_reference text,
  unit_reference text,

  brokerage_rate numeric(10,4),
  brokerage_amount numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  total_receivable numeric(18,2) not null default 0,
  received_amount numeric(18,2) not null default 0,

  outstanding_amount numeric(18,2) generated always as (
    greatest(total_receivable - received_amount,0)
  ) stored,

  due_date date,

  status text not null default 'pending'
    check (
      status in (
        'pending',
        'invoiced',
        'partially_received',
        'received',
        'overdue',
        'disputed',
        'cancelled',
        'written_off'
      )
    ),

  invoice_id uuid references public.finance_invoices(id) on delete set null,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,booking_id)
);

-- ============================================================
-- 15. RECONCILIATION
-- ============================================================

create table if not exists public.finance_reconciliation_batches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  batch_code text not null,
  batch_type text not null
    check (
      batch_type in (
        'bank_statement',
        'payment_gateway',
        'builder_receipt',
        'commission_payout',
        'customer_payment',
        'custom'
      )
    ),

  period_start date,
  period_end date,

  status text not null default 'draft'
    check (
      status in (
        'draft',
        'imported',
        'matching',
        'partially_matched',
        'reconciled',
        'failed',
        'cancelled'
      )
    ),

  total_records integer not null default 0,
  matched_records integer not null default 0,
  unmatched_records integer not null default 0,

  total_amount numeric(18,2) not null default 0,
  matched_amount numeric(18,2) not null default 0,
  unmatched_amount numeric(18,2) not null default 0,

  source_document_id uuid references public.documents(id) on delete set null,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,batch_code)
);

create table if not exists public.finance_reconciliation_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  reconciliation_batch_id uuid not null references public.finance_reconciliation_batches(id) on delete cascade,

  external_reference text,
  transaction_date date,
  description text,
  amount numeric(18,2) not null,

  matched_entity_type text,
  matched_entity_id uuid,
  confidence_score numeric(8,4),

  status text not null default 'unmatched'
    check (
      status in (
        'unmatched',
        'suggested',
        'matched',
        'ignored',
        'disputed'
      )
    ),

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 16. JOURNALS AND LEDGER
-- ============================================================

create table if not exists public.finance_journals (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  journal_number text not null,
  journal_date date not null default current_date,

  source_module text,
  source_type text,
  source_id uuid,
  source_reference text,

  description text,

  status text not null default 'draft'
    check (status in ('draft','posted','reversed','void')),

  total_debit numeric(18,2) not null default 0,
  total_credit numeric(18,2) not null default 0,

  posted_by uuid references auth.users(id) on delete set null,
  posted_at timestamptz,

  reversed_by uuid references auth.users(id) on delete set null,
  reversed_at timestamptz,

  metadata jsonb not null default '{}',

  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (organization_id,journal_number)
);

create table if not exists public.finance_ledger_entries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  journal_id uuid not null references public.finance_journals(id) on delete cascade,

  line_number integer not null,
  account_id uuid not null references public.finance_accounts(id) on delete restrict,
  party_id uuid references public.finance_parties(id) on delete set null,

  entry_date date not null,
  description text,

  debit_amount numeric(18,2) not null default 0,
  credit_amount numeric(18,2) not null default 0,

  currency text not null default 'INR',

  source_type text,
  source_id uuid,

  metadata jsonb not null default '{}',

  created_at timestamptz not null default now(),

  check (
    (debit_amount > 0 and credit_amount = 0)
    or (credit_amount > 0 and debit_amount = 0)
  ),

  unique (journal_id,line_number)
);

-- ============================================================
-- 17. FINANCE EVENT OUTBOX AND LOGS
-- ============================================================

create table if not exists public.finance_event_outbox (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

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

  source_type text,
  source_id uuid,

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

create unique index if not exists finance_event_outbox_idempotency_idx
  on public.finance_event_outbox (
    organization_id,
    idempotency_key
  )
  where idempotency_key is not null;

create index if not exists finance_event_outbox_queue_idx
  on public.finance_event_outbox (
    status,
    available_at,
    priority,
    created_at
  )
  where status in ('pending','failed');

create table if not exists public.finance_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,

  invoice_id uuid references public.finance_invoices(id) on delete set null,
  receipt_id uuid references public.finance_payment_receipts(id) on delete set null,
  commission_accrual_id uuid references public.finance_commission_accruals(id) on delete set null,
  payout_id uuid references public.finance_commission_payouts(id) on delete set null,

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

-- ============================================================
-- 18. UPDATED_AT TRIGGERS
-- ============================================================

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'finance_settings',
    'finance_accounts',
    'finance_parties',
    'finance_invoices',
    'finance_payment_receipts',
    'finance_commission_plans',
    'finance_commission_assignments',
    'finance_commission_accruals',
    'finance_commission_adjustments',
    'finance_commission_payouts',
    'finance_builder_receivables',
    'finance_reconciliation_batches',
    'finance_reconciliation_items',
    'finance_journals',
    'finance_event_outbox'
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
-- 19. CREATE INVOICE
-- ============================================================

create or replace function public.create_finance_invoice(
  requested_organization_id uuid,
  requested_invoice_type text,
  requested_party_id uuid default null,
  requested_booking_id uuid default null,
  requested_customer_id uuid default null,
  requested_invoice_date date default current_date,
  requested_due_date date default null,
  requested_currency text default 'INR',
  requested_notes text default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.finance_invoices
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings_record public.finance_settings;
  invoice_record public.finance_invoices;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'finance.manage_invoices'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into settings_record
  from public.finance_settings
  where organization_id = requested_organization_id;

  insert into public.finance_invoices (
    organization_id,
    invoice_number,
    invoice_type,
    party_id,
    booking_id,
    customer_id,
    invoice_date,
    due_date,
    currency,
    status,
    notes,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    coalesce(settings_record.invoice_prefix,'INV')
      || '-'
      || to_char(now(),'YYYYMMDD')
      || '-'
      || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    requested_invoice_type,
    requested_party_id,
    requested_booking_id,
    requested_customer_id,
    requested_invoice_date,
    coalesce(
      requested_due_date,
      requested_invoice_date
        + coalesce(settings_record.invoice_due_days,30)
    ),
    requested_currency,
    'draft',
    requested_notes,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  returning * into invoice_record;

  return invoice_record;
end;
$$;

revoke all
on function public.create_finance_invoice(
  uuid,text,uuid,uuid,uuid,date,date,text,text,jsonb
)
from public;

grant execute
on function public.create_finance_invoice(
  uuid,text,uuid,uuid,uuid,date,date,text,text,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 20. RECALCULATE INVOICE
-- ============================================================

create or replace function public.recalculate_finance_invoice(
  requested_invoice_id uuid
)
returns public.finance_invoices
language plpgsql
security definer
set search_path = ''
as $$
declare
  invoice_record public.finance_invoices;
begin
  select *
  into invoice_record
  from public.finance_invoices
  where id = requested_invoice_id
  for update;

  if not found then
    raise exception 'Finance invoice not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      invoice_record.organization_id,
      'finance.manage_invoices'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.finance_invoices
  set
    subtotal = coalesce((
      select sum(quantity * unit_price)
      from public.finance_invoice_items
      where invoice_id = requested_invoice_id
    ),0),
    discount_amount = coalesce((
      select sum(discount_amount)
      from public.finance_invoice_items
      where invoice_id = requested_invoice_id
    ),0),
    taxable_amount = coalesce((
      select sum(taxable_value)
      from public.finance_invoice_items
      where invoice_id = requested_invoice_id
    ),0),
    tax_amount = coalesce((
      select sum(tax_amount)
      from public.finance_invoice_items
      where invoice_id = requested_invoice_id
    ),0),
    total_amount = coalesce((
      select sum(line_total)
      from public.finance_invoice_items
      where invoice_id = requested_invoice_id
    ),0),
    status = case
      when status = 'draft' then 'draft'
      when paid_amount <= 0 then 'issued'
      when paid_amount < coalesce((
        select sum(line_total)
        from public.finance_invoice_items
        where invoice_id = requested_invoice_id
      ),0) then 'partially_paid'
      else 'paid'
    end,
    updated_at = now()
  where id = requested_invoice_id
  returning * into invoice_record;

  return invoice_record;
end;
$$;

revoke all
on function public.recalculate_finance_invoice(uuid)
from public;

grant execute
on function public.recalculate_finance_invoice(uuid)
to authenticated,service_role;

-- ============================================================
-- 21. RECORD PAYMENT RECEIPT
-- ============================================================

create or replace function public.record_finance_payment_receipt(
  requested_organization_id uuid,
  requested_amount numeric,
  requested_party_id uuid default null,
  requested_invoice_id uuid default null,
  requested_booking_id uuid default null,
  requested_customer_id uuid default null,
  requested_payment_method text default null,
  requested_transaction_reference text default null,
  requested_external_transaction_id text default null,
  requested_received_at timestamptz default now(),
  requested_metadata jsonb default '{}'::jsonb
)
returns public.finance_payment_receipts
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings_record public.finance_settings;
  receipt_record public.finance_payment_receipts;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'finance.manage_receipts'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into settings_record
  from public.finance_settings
  where organization_id = requested_organization_id;

  insert into public.finance_payment_receipts (
    organization_id,
    receipt_number,
    party_id,
    invoice_id,
    booking_id,
    customer_id,
    payment_method,
    transaction_reference,
    external_transaction_id,
    amount,
    status,
    received_at,
    metadata,
    created_by,
    updated_by
  )
  values (
    requested_organization_id,
    coalesce(settings_record.receipt_prefix,'RCT')
      || '-'
      || to_char(now(),'YYYYMMDD')
      || '-'
      || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    requested_party_id,
    requested_invoice_id,
    requested_booking_id,
    requested_customer_id,
    requested_payment_method,
    requested_transaction_reference,
    requested_external_transaction_id,
    requested_amount,
    'received',
    requested_received_at,
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  )
  returning * into receipt_record;

  if requested_invoice_id is not null then
    update public.finance_invoices
    set
      paid_amount = paid_amount + requested_amount,
      status = case
        when paid_amount + requested_amount >= total_amount then 'paid'
        else 'partially_paid'
      end,
      paid_at = case
        when paid_amount + requested_amount >= total_amount then now()
        else paid_at
      end,
      updated_at = now()
    where id = requested_invoice_id;
  end if;

  return receipt_record;
end;
$$;

revoke all
on function public.record_finance_payment_receipt(
  uuid,numeric,uuid,uuid,uuid,uuid,text,text,text,timestamptz,jsonb
)
from public;

grant execute
on function public.record_finance_payment_receipt(
  uuid,numeric,uuid,uuid,uuid,uuid,text,text,text,timestamptz,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 22. CALCULATE COMMISSION ACCRUAL
-- ============================================================

create or replace function public.calculate_finance_commission_accrual(
  requested_organization_id uuid,
  requested_booking_id uuid,
  requested_beneficiary_type text,
  requested_beneficiary_agent_profile_id uuid default null,
  requested_beneficiary_team_id uuid default null,
  requested_beneficiary_user_id uuid default null,
  requested_beneficiary_reference text default null,
  requested_commission_plan_id uuid default null,
  requested_basis_amount numeric default null,
  requested_metadata jsonb default '{}'::jsonb
)
returns public.finance_commission_accruals
language plpgsql
security definer
set search_path = ''
as $$
declare
  booking_record public.bookings;
  plan_record public.finance_commission_plans;
  slab_record public.finance_commission_slabs;
  basis_amount_value numeric;
  rate_value numeric;
  fixed_amount_value numeric;
  gross_value numeric;
  tds_rate_value numeric;
  settings_record public.finance_settings;
  accrual_record public.finance_commission_accruals;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'finance.manage_commissions'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into booking_record
  from public.bookings
  where id = requested_booking_id
    and organization_id = requested_organization_id;

  if not found then
    raise exception 'Booking not found';
  end if;

  if requested_commission_plan_id is not null then
    select *
    into plan_record
    from public.finance_commission_plans
    where id = requested_commission_plan_id
      and organization_id = requested_organization_id
      and status = 'active';
  end if;

  basis_amount_value := coalesce(
    requested_basis_amount,
    nullif(to_jsonb(booking_record)->>'booking_amount','')::numeric,
    nullif(to_jsonb(booking_record)->>'amount','')::numeric,
    nullif(to_jsonb(booking_record)->>'total_amount','')::numeric,
    0
  );

  if plan_record.id is not null then
    select *
    into slab_record
    from public.finance_commission_slabs s
    where s.commission_plan_id = plan_record.id
      and basis_amount_value >= s.minimum_value
      and (
        s.maximum_value is null
        or basis_amount_value <= s.maximum_value
      )
    order by s.slab_order
    limit 1;
  end if;

  rate_value := coalesce(
    slab_record.rate,
    plan_record.default_rate,
    0
  );

  fixed_amount_value := coalesce(
    slab_record.fixed_amount,
    plan_record.fixed_amount,
    0
  );

  gross_value := case
    when fixed_amount_value > 0 then fixed_amount_value
    else round(basis_amount_value * rate_value / 100,2)
  end;

  select *
  into settings_record
  from public.finance_settings
  where organization_id = requested_organization_id;

  tds_rate_value := case
    when coalesce(settings_record.tds_enabled,true)
      then coalesce(settings_record.default_tds_rate,5)
    else 0
  end;

  insert into public.finance_commission_accruals (
    organization_id,
    booking_id,
    lead_id,
    commission_plan_id,
    beneficiary_type,
    beneficiary_agent_profile_id,
    beneficiary_team_id,
    beneficiary_user_id,
    beneficiary_reference,
    basis_type,
    basis_amount,
    commission_rate,
    gross_commission,
    tds_amount,
    status,
    accrued_at,
    lock_at,
    calculation_data,
    metadata
  )
  values (
    requested_organization_id,
    requested_booking_id,
    nullif(to_jsonb(booking_record)->>'lead_id','')::uuid,
    requested_commission_plan_id,
    requested_beneficiary_type,
    requested_beneficiary_agent_profile_id,
    requested_beneficiary_team_id,
    requested_beneficiary_user_id,
    requested_beneficiary_reference,
    coalesce(plan_record.calculation_basis,'booking_value'),
    basis_amount_value,
    rate_value,
    gross_value,
    round(gross_value * tds_rate_value / 100,2),
    'calculated',
    now(),
    now() + make_interval(
      days => coalesce(settings_record.commission_lock_days,7)
    ),
    jsonb_build_object(
      'plan_code',plan_record.plan_code,
      'slab_id',slab_record.id,
      'tds_rate',tds_rate_value
    ),
    coalesce(requested_metadata,'{}'::jsonb)
  )
  returning * into accrual_record;

  return accrual_record;
end;
$$;

revoke all
on function public.calculate_finance_commission_accrual(
  uuid,uuid,text,uuid,uuid,uuid,text,uuid,numeric,jsonb
)
from public;

grant execute
on function public.calculate_finance_commission_accrual(
  uuid,uuid,text,uuid,uuid,uuid,text,uuid,numeric,jsonb
)
to authenticated,service_role;

-- ============================================================
-- 23. APPROVE COMMISSION ACCRUAL
-- ============================================================

create or replace function public.approve_finance_commission_accrual(
  requested_accrual_id uuid
)
returns public.finance_commission_accruals
language plpgsql
security definer
set search_path = ''
as $$
declare
  accrual_record public.finance_commission_accruals;
begin
  select *
  into accrual_record
  from public.finance_commission_accruals
  where id = requested_accrual_id
  for update;

  if not found then
    raise exception 'Commission accrual not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      accrual_record.organization_id,
      'finance.approve_commissions'
    ) then
    raise exception 'Permission denied';
  end if;

  if accrual_record.status not in ('calculated','locked','disputed') then
    raise exception 'Commission accrual is not eligible for approval';
  end if;

  update public.finance_commission_accruals
  set
    status = 'approved',
    approved_by = auth.uid(),
    approved_at = now(),
    updated_at = now()
  where id = requested_accrual_id
  returning * into accrual_record;

  return accrual_record;
end;
$$;

revoke all
on function public.approve_finance_commission_accrual(uuid)
from public;

grant execute
on function public.approve_finance_commission_accrual(uuid)
to authenticated,service_role;

-- ============================================================
-- 24. CREATE COMMISSION PAYOUT
-- ============================================================

create or replace function public.create_finance_commission_payout(
  requested_organization_id uuid,
  requested_beneficiary_type text,
  requested_beneficiary_agent_profile_id uuid default null,
  requested_beneficiary_team_id uuid default null,
  requested_beneficiary_user_id uuid default null,
  requested_beneficiary_reference text default null,
  requested_period_start date default null,
  requested_period_end date default null,
  requested_accrual_ids uuid[] default '{}',
  requested_metadata jsonb default '{}'::jsonb
)
returns public.finance_commission_payouts
language plpgsql
security definer
set search_path = ''
as $$
declare
  settings_record public.finance_settings;
  payout_record public.finance_commission_payouts;
begin
  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      requested_organization_id,
      'finance.manage_payouts'
    ) then
    raise exception 'Permission denied';
  end if;

  select *
  into settings_record
  from public.finance_settings
  where organization_id = requested_organization_id;

  insert into public.finance_commission_payouts (
    organization_id,
    payout_number,
    beneficiary_type,
    beneficiary_agent_profile_id,
    beneficiary_team_id,
    beneficiary_user_id,
    beneficiary_reference,
    period_start,
    period_end,
    gross_amount,
    deduction_amount,
    tds_amount,
    net_amount,
    status,
    metadata,
    created_by,
    updated_by
  )
  select
    requested_organization_id,
    coalesce(settings_record.payout_prefix,'PAY')
      || '-'
      || to_char(now(),'YYYYMMDD')
      || '-'
      || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),
    requested_beneficiary_type,
    requested_beneficiary_agent_profile_id,
    requested_beneficiary_team_id,
    requested_beneficiary_user_id,
    requested_beneficiary_reference,
    requested_period_start,
    requested_period_end,
    coalesce(sum(a.gross_commission),0),
    coalesce(sum(a.tax_withheld + a.clawback_amount - a.adjustments_amount),0),
    coalesce(sum(a.tds_amount),0),
    coalesce(sum(a.net_commission),0),
    'pending_approval',
    coalesce(requested_metadata,'{}'::jsonb),
    auth.uid(),
    auth.uid()
  from public.finance_commission_accruals a
  where a.organization_id = requested_organization_id
    and a.id = any(requested_accrual_ids)
    and a.status = 'approved'
  returning * into payout_record;

  insert into public.finance_commission_payout_items (
    organization_id,
    payout_id,
    commission_accrual_id,
    gross_amount,
    deduction_amount,
    tds_amount,
    net_amount
  )
  select
    requested_organization_id,
    payout_record.id,
    a.id,
    a.gross_commission,
    a.tax_withheld + a.clawback_amount - a.adjustments_amount,
    a.tds_amount,
    a.net_commission
  from public.finance_commission_accruals a
  where a.organization_id = requested_organization_id
    and a.id = any(requested_accrual_ids)
    and a.status = 'approved';

  return payout_record;
end;
$$;

revoke all
on function public.create_finance_commission_payout(
  uuid,text,uuid,uuid,uuid,text,date,date,uuid[],jsonb
)
from public;

grant execute
on function public.create_finance_commission_payout(
  uuid,text,uuid,uuid,uuid,text,date,date,uuid[],jsonb
)
to authenticated,service_role;

-- ============================================================
-- 25. MARK PAYOUT PAID
-- ============================================================

create or replace function public.mark_finance_payout_paid(
  requested_payout_id uuid,
  requested_payment_method text,
  requested_bank_reference text default null,
  requested_external_transaction_id text default null
)
returns public.finance_commission_payouts
language plpgsql
security definer
set search_path = ''
as $$
declare
  payout_record public.finance_commission_payouts;
begin
  select *
  into payout_record
  from public.finance_commission_payouts
  where id = requested_payout_id
  for update;

  if not found then
    raise exception 'Commission payout not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      payout_record.organization_id,
      'finance.manage_payouts'
    ) then
    raise exception 'Permission denied';
  end if;

  update public.finance_commission_payouts
  set
    status = 'paid',
    payment_method = requested_payment_method,
    bank_reference = requested_bank_reference,
    external_transaction_id = requested_external_transaction_id,
    processed_at = coalesce(processed_at,now()),
    paid_at = now(),
    updated_at = now()
  where id = requested_payout_id
  returning * into payout_record;

  update public.finance_commission_accruals a
  set
    status = 'paid',
    paid_at = now(),
    updated_at = now()
  where exists (
    select 1
    from public.finance_commission_payout_items i
    where i.payout_id = requested_payout_id
      and i.commission_accrual_id = a.id
  );

  return payout_record;
end;
$$;

revoke all
on function public.mark_finance_payout_paid(uuid,text,text,text)
from public;

grant execute
on function public.mark_finance_payout_paid(uuid,text,text,text)
to authenticated,service_role;

-- ============================================================
-- 26. POST JOURNAL
-- ============================================================

create or replace function public.post_finance_journal(
  requested_journal_id uuid
)
returns public.finance_journals
language plpgsql
security definer
set search_path = ''
as $$
declare
  journal_record public.finance_journals;
  debit_value numeric;
  credit_value numeric;
begin
  select *
  into journal_record
  from public.finance_journals
  where id = requested_journal_id
  for update;

  if not found then
    raise exception 'Finance journal not found';
  end if;

  if auth.role() <> 'service_role'
    and not public.has_organization_permission(
      journal_record.organization_id,
      'finance.manage_accounts'
    ) then
    raise exception 'Permission denied';
  end if;

  select
    coalesce(sum(debit_amount),0),
    coalesce(sum(credit_amount),0)
  into debit_value,credit_value
  from public.finance_ledger_entries
  where journal_id = requested_journal_id;

  if debit_value <> credit_value then
    raise exception 'Journal is not balanced';
  end if;

  update public.finance_journals
  set
    total_debit = debit_value,
    total_credit = credit_value,
    status = 'posted',
    posted_by = auth.uid(),
    posted_at = now(),
    updated_at = now()
  where id = requested_journal_id
  returning * into journal_record;

  return journal_record;
end;
$$;

revoke all
on function public.post_finance_journal(uuid)
from public;

grant execute
on function public.post_finance_journal(uuid)
to authenticated,service_role;

-- ============================================================
-- 27. PUBLISH FINANCE EVENT
-- ============================================================

create or replace function public.publish_finance_event(
  requested_organization_id uuid,
  requested_event_name text,
  requested_payload jsonb default '{}'::jsonb,
  requested_destination text default 'internal',
  requested_source_type text default null,
  requested_source_id uuid default null,
  requested_priority integer default 100,
  requested_idempotency_key text default null,
  requested_correlation_id text default null,
  requested_trace_id text default null,
  requested_available_at timestamptz default now()
)
returns public.finance_event_outbox
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_event public.finance_event_outbox;
  created_event public.finance_event_outbox;
begin
  if requested_idempotency_key is not null then
    select *
    into existing_event
    from public.finance_event_outbox e
    where e.organization_id = requested_organization_id
      and e.idempotency_key = requested_idempotency_key
    limit 1;

    if found then
      return existing_event;
    end if;
  end if;

  insert into public.finance_event_outbox (
    organization_id,
    event_name,
    destination,
    source_type,
    source_id,
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
    requested_event_name,
    requested_destination,
    requested_source_type,
    requested_source_id,
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
on function public.publish_finance_event(
  uuid,text,jsonb,text,text,uuid,integer,text,text,text,timestamptz
)
from public;

grant execute
on function public.publish_finance_event(
  uuid,text,jsonb,text,text,uuid,integer,text,text,text,timestamptz
)
to authenticated,service_role;

-- ============================================================
-- 28. PAYOUT EVENT TRIGGER
-- ============================================================

create or replace function public.emit_finance_payout_events()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  payload_data jsonb;
begin
  if tg_op = 'UPDATE'
    and new.status is not distinct from old.status then
    return new;
  end if;

  payload_data := jsonb_build_object(
    'organization_id',new.organization_id,
    'payout_id',new.id,
    'payout_number',new.payout_number,
    'beneficiary_type',new.beneficiary_type,
    'beneficiary_user_id',new.beneficiary_user_id,
    'beneficiary_agent_profile_id',new.beneficiary_agent_profile_id,
    'net_amount',new.net_amount,
    'status',new.status
  );

  perform public.publish_finance_event(
    new.organization_id,
    'finance.payout.' || new.status,
    payload_data,
    'notification_engine',
    'commission_payout',
    new.id,
    case when new.status = 'failed' then 10 else 50 end,
    'finance-payout-notification:' || new.id::text || ':' || new.status,
    new.id::text,
    null,
    now()
  );

  perform public.publish_finance_event(
    new.organization_id,
    'finance.payout.' || new.status,
    payload_data,
    'automation_engine',
    'commission_payout',
    new.id,
    50,
    'finance-payout-automation:' || new.id::text || ':' || new.status,
    new.id::text,
    null,
    now()
  );

  return new;
end;
$$;

drop trigger if exists finance_commission_payouts_emit_events
on public.finance_commission_payouts;

create trigger finance_commission_payouts_emit_events
after insert or update
on public.finance_commission_payouts
for each row
execute function public.emit_finance_payout_events();

-- ============================================================
-- 29. ANALYTICS VIEWS
-- ============================================================

create or replace view public.finance_executive_dashboard
with (security_invoker = true)
as
select
  o.id as organization_id,

  (select coalesce(sum(i.total_amount),0)
   from public.finance_invoices i
   where i.organization_id = o.id
     and i.status not in ('cancelled','void')) as invoiced_revenue,

  (select coalesce(sum(r.amount),0)
   from public.finance_payment_receipts r
   where r.organization_id = o.id
     and r.status in ('received','verified','reconciled')) as cash_received,

  (select coalesce(sum(i.outstanding_amount),0)
   from public.finance_invoices i
   where i.organization_id = o.id
     and i.status in ('issued','sent','partially_paid','overdue')) as invoice_outstanding,

  (select coalesce(sum(b.outstanding_amount),0)
   from public.finance_builder_receivables b
   where b.organization_id = o.id
     and b.status not in ('received','cancelled','written_off')) as builder_receivables_outstanding,

  (select coalesce(sum(a.net_commission),0)
   from public.finance_commission_accruals a
   where a.organization_id = o.id
     and a.status in ('approved','partially_paid')) as commission_payable,

  (select coalesce(sum(p.net_amount),0)
   from public.finance_commission_payouts p
   where p.organization_id = o.id
     and p.status = 'paid') as commission_paid,

  (select count(*)
   from public.finance_invoices i
   where i.organization_id = o.id
     and i.status = 'overdue') as overdue_invoices,

  now() as refreshed_at

from public.organizations o;

create or replace view public.finance_commission_dashboard
with (security_invoker = true)
as
select
  organization_id,
  beneficiary_type,
  beneficiary_agent_profile_id,
  beneficiary_team_id,
  beneficiary_user_id,
  beneficiary_reference,

  count(*) as accrual_count,

  coalesce(sum(gross_commission),0) as gross_commission,
  coalesce(sum(tds_amount),0) as tds_amount,
  coalesce(sum(clawback_amount),0) as clawback_amount,
  coalesce(sum(adjustments_amount),0) as adjustments_amount,
  coalesce(sum(net_commission),0) as net_commission,

  coalesce(sum(net_commission) filter (
    where status = 'paid'
  ),0) as paid_commission,

  coalesce(sum(net_commission) filter (
    where status in ('approved','partially_paid')
  ),0) as payable_commission

from public.finance_commission_accruals
group by
  organization_id,
  beneficiary_type,
  beneficiary_agent_profile_id,
  beneficiary_team_id,
  beneficiary_user_id,
  beneficiary_reference;

create or replace view public.finance_receivables_dashboard
with (security_invoker = true)
as
select
  organization_id,

  count(*) as receivable_count,
  coalesce(sum(total_receivable),0) as total_receivable,
  coalesce(sum(received_amount),0) as received_amount,
  coalesce(sum(outstanding_amount),0) as outstanding_amount,

  count(*) filter (
    where status = 'overdue'
  ) as overdue_count,

  coalesce(sum(outstanding_amount) filter (
    where status = 'overdue'
  ),0) as overdue_amount

from public.finance_builder_receivables
group by organization_id;

create or replace view public.finance_reconciliation_dashboard
with (security_invoker = true)
as
select
  organization_id,

  count(*) as batch_count,
  coalesce(sum(total_records),0) as total_records,
  coalesce(sum(matched_records),0) as matched_records,
  coalesce(sum(unmatched_records),0) as unmatched_records,

  coalesce(sum(total_amount),0) as total_amount,
  coalesce(sum(matched_amount),0) as matched_amount,
  coalesce(sum(unmatched_amount),0) as unmatched_amount,

  round(
    coalesce(sum(matched_records),0)::numeric
    / nullif(coalesce(sum(total_records),0),0) * 100,
    2
  ) as reconciliation_rate

from public.finance_reconciliation_batches
group by organization_id;

grant select
on
  public.finance_executive_dashboard,
  public.finance_commission_dashboard,
  public.finance_receivables_dashboard,
  public.finance_reconciliation_dashboard
to authenticated,service_role;

-- ============================================================
-- 30. HEALTH CHECK
-- ============================================================

create or replace function public.get_finance_engine_health(
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
        'finance.view_logs'
      )
    ) then
    raise exception 'Permission denied';
  end if;

  return jsonb_build_object(
    'organization_id',requested_organization_id,
    'checked_at',now(),

    'draft_invoices',(
      select count(*)
      from public.finance_invoices i
      where i.status = 'draft'
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'overdue_invoices',(
      select count(*)
      from public.finance_invoices i
      where i.status = 'overdue'
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'unreconciled_receipts',(
      select count(*)
      from public.finance_payment_receipts r
      where r.status in ('received','verified')
        and (
          requested_organization_id is null
          or r.organization_id = requested_organization_id
        )
    ),

    'pending_commission_approvals',(
      select count(*)
      from public.finance_commission_accruals a
      where a.status in ('calculated','locked','disputed')
        and (
          requested_organization_id is null
          or a.organization_id = requested_organization_id
        )
    ),

    'pending_payouts',(
      select count(*)
      from public.finance_commission_payouts p
      where p.status in ('pending_approval','approved','processing')
        and (
          requested_organization_id is null
          or p.organization_id = requested_organization_id
        )
    ),

    'unmatched_reconciliation_items',(
      select count(*)
      from public.finance_reconciliation_items i
      where i.status in ('unmatched','suggested','disputed')
        and (
          requested_organization_id is null
          or i.organization_id = requested_organization_id
        )
    ),

    'pending_outbox_events',(
      select count(*)
      from public.finance_event_outbox e
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
on function public.get_finance_engine_health(uuid)
from public;

grant execute
on function public.get_finance_engine_health(uuid)
to authenticated,service_role;

-- ============================================================
-- 31. RLS
-- ============================================================

alter table public.finance_settings enable row level security;
alter table public.finance_accounts enable row level security;
alter table public.finance_parties enable row level security;
alter table public.finance_invoices enable row level security;
alter table public.finance_invoice_items enable row level security;
alter table public.finance_payment_receipts enable row level security;
alter table public.finance_commission_plans enable row level security;
alter table public.finance_commission_slabs enable row level security;
alter table public.finance_commission_assignments enable row level security;
alter table public.finance_commission_accruals enable row level security;
alter table public.finance_commission_adjustments enable row level security;
alter table public.finance_commission_payouts enable row level security;
alter table public.finance_commission_payout_items enable row level security;
alter table public.finance_builder_receivables enable row level security;
alter table public.finance_reconciliation_batches enable row level security;
alter table public.finance_reconciliation_items enable row level security;
alter table public.finance_journals enable row level security;
alter table public.finance_ledger_entries enable row level security;
alter table public.finance_event_outbox enable row level security;
alter table public.finance_logs enable row level security;

do $$
declare
  target_table text;
begin
  foreach target_table in array array[
    'finance_settings',
    'finance_accounts',
    'finance_parties',
    'finance_invoices',
    'finance_invoice_items',
    'finance_payment_receipts',
    'finance_commission_plans',
    'finance_commission_slabs',
    'finance_commission_assignments',
    'finance_commission_accruals',
    'finance_commission_adjustments',
    'finance_commission_payouts',
    'finance_commission_payout_items',
    'finance_builder_receivables',
    'finance_reconciliation_batches',
    'finance_reconciliation_items',
    'finance_journals',
    'finance_ledger_entries',
    'finance_event_outbox',
    'finance_logs'
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
         public.has_organization_permission(
           organization_id,
           ''finance.view''
         )
         or public.has_organization_permission(
           organization_id,
           ''finance.view_all''
         )
       )',
      target_table,target_table
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

drop policy if exists finance_settings_write_policy
on public.finance_settings;

create policy finance_settings_write_policy
on public.finance_settings
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'finance.manage_settings'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'finance.manage_settings'
  )
);

drop policy if exists finance_invoices_write_policy
on public.finance_invoices;

create policy finance_invoices_write_policy
on public.finance_invoices
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'finance.manage_invoices'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'finance.manage_invoices'
  )
);

drop policy if exists finance_commission_accruals_write_policy
on public.finance_commission_accruals;

create policy finance_commission_accruals_write_policy
on public.finance_commission_accruals
for all
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'finance.manage_commissions'
  )
  or public.has_organization_permission(
    organization_id,
    'finance.approve_commissions'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'finance.manage_commissions'
  )
  or public.has_organization_permission(
    organization_id,
    'finance.approve_commissions'
  )
);

-- ============================================================
-- 32. GRANTS
-- ============================================================

grant select
on
  public.finance_settings,
  public.finance_accounts,
  public.finance_parties,
  public.finance_invoices,
  public.finance_invoice_items,
  public.finance_payment_receipts,
  public.finance_commission_plans,
  public.finance_commission_slabs,
  public.finance_commission_assignments,
  public.finance_commission_accruals,
  public.finance_commission_adjustments,
  public.finance_commission_payouts,
  public.finance_commission_payout_items,
  public.finance_builder_receivables,
  public.finance_reconciliation_batches,
  public.finance_reconciliation_items,
  public.finance_journals,
  public.finance_ledger_entries,
  public.finance_event_outbox,
  public.finance_logs
to authenticated;

grant insert,update,delete
on
  public.finance_settings,
  public.finance_accounts,
  public.finance_parties,
  public.finance_invoices,
  public.finance_invoice_items,
  public.finance_payment_receipts,
  public.finance_commission_plans,
  public.finance_commission_slabs,
  public.finance_commission_assignments,
  public.finance_commission_accruals,
  public.finance_commission_adjustments,
  public.finance_commission_payouts,
  public.finance_commission_payout_items,
  public.finance_builder_receivables,
  public.finance_reconciliation_batches,
  public.finance_reconciliation_items,
  public.finance_journals,
  public.finance_ledger_entries
to authenticated;

grant all
on
  public.finance_settings,
  public.finance_accounts,
  public.finance_parties,
  public.finance_invoices,
  public.finance_invoice_items,
  public.finance_payment_receipts,
  public.finance_commission_plans,
  public.finance_commission_slabs,
  public.finance_commission_assignments,
  public.finance_commission_accruals,
  public.finance_commission_adjustments,
  public.finance_commission_payouts,
  public.finance_commission_payout_items,
  public.finance_builder_receivables,
  public.finance_reconciliation_batches,
  public.finance_reconciliation_items,
  public.finance_journals,
  public.finance_ledger_entries,
  public.finance_event_outbox,
  public.finance_logs
to service_role;

-- ============================================================
-- 33. FINAL VALIDATION
-- ============================================================

do $$
declare
  item text;
  missing_items text[] := '{}';
begin
  foreach item in array array[
    'finance_settings',
    'finance_accounts',
    'finance_parties',
    'finance_invoices',
    'finance_invoice_items',
    'finance_payment_receipts',
    'finance_commission_plans',
    'finance_commission_slabs',
    'finance_commission_assignments',
    'finance_commission_accruals',
    'finance_commission_adjustments',
    'finance_commission_payouts',
    'finance_commission_payout_items',
    'finance_builder_receivables',
    'finance_reconciliation_batches',
    'finance_reconciliation_items',
    'finance_journals',
    'finance_ledger_entries',
    'finance_event_outbox',
    'finance_logs'
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
    'create_finance_invoice',
    'recalculate_finance_invoice',
    'record_finance_payment_receipt',
    'calculate_finance_commission_accrual',
    'approve_finance_commission_accrual',
    'create_finance_commission_payout',
    'mark_finance_payout_paid',
    'post_finance_journal',
    'publish_finance_event',
    'get_finance_engine_health'
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
      '020 migration validation failed. Missing: %',
      array_to_string(missing_items,', ');
  end if;
end;
$$;

-- ============================================================
-- 34. MIGRATION AUDIT
-- ============================================================

insert into public.finance_logs (
  organization_id,
  log_level,
  event_name,
  message,
  log_data
)
select
  o.id,
  'info',
  'migration.020.completed',
  'Finance & Commission Engine migration 020 completed',
  jsonb_build_object(
    'migration',
    '020_finance_commission_engine',
    'completed_at',
    now(),
    'modules',
    jsonb_build_array(
      'settings',
      'chart_of_accounts',
      'parties',
      'invoices',
      'invoice_items',
      'receipts',
      'commission_plans',
      'commission_slabs',
      'commission_accruals',
      'adjustments',
      'payouts',
      'builder_receivables',
      'reconciliation',
      'journals',
      'ledger',
      'event_outbox',
      'analytics'
    )
  )
from public.organizations o
where not exists (
  select 1
  from public.finance_logs l
  where l.organization_id = o.id
    and l.event_name = 'migration.020.completed'
);

commit;