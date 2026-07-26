-- =========================================================
-- SalesSetu Enterprise
-- Migration: 006_bookings
-- Purpose: Booking, documents and payment engine
-- =========================================================

begin;

-- =========================================================
-- 1. ENUM TYPES
-- =========================================================

create type public.booking_status as enum (
  'draft',
  'token_paid',
  'application_submitted',
  'documents_pending',
  'documents_verified',
  'loan_processing',
  'loan_approved',
  'agreement_signed',
  'payment_pending',
  'confirmed',
  'cancelled',
  'refunded'
);

create type public.booking_payment_status as enum (
  'pending',
  'partial',
  'paid',
  'failed',
  'refunded'
);

-- =========================================================
-- 2. BOOKING PERMISSIONS
-- =========================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
values
  (
    'bookings',
    'view',
    'bookings.view',
    'View bookings and associated records'
  ),
  (
    'bookings',
    'create',
    'bookings.create',
    'Create bookings'
  ),
  (
    'bookings',
    'update',
    'bookings.update',
    'Update booking information'
  ),
  (
    'bookings',
    'confirm',
    'bookings.confirm',
    'Confirm bookings'
  ),
  (
    'bookings',
    'cancel',
    'bookings.cancel',
    'Cancel bookings'
  ),
  (
    'bookings',
    'manage_documents',
    'bookings.manage_documents',
    'Upload and verify booking documents'
  ),
  (
    'bookings',
    'manage_payments',
    'bookings.manage_payments',
    'Create and update booking payments'
  ),
  (
    'bookings',
    'delete',
    'bookings.delete',
    'Delete booking records'
  ),
  (
    'bookings',
    'view_all',
    'bookings.view_all',
    'View all organization bookings'
  )
on conflict (code) do nothing;

-- Platform and Organization Admin

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
and p.module = 'bookings'
on conflict (role_id, permission_id) do nothing;

-- Sales Manager

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
    'bookings.view',
    'bookings.create',
    'bookings.update',
    'bookings.confirm',
    'bookings.cancel',
    'bookings.manage_documents',
    'bookings.manage_payments',
    'bookings.view_all'
  )
where r.code = 'sales_manager'
on conflict (role_id, permission_id) do nothing;

-- Sales Agent

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
    'bookings.view',
    'bookings.create',
    'bookings.update',
    'bookings.manage_documents'
  )
where r.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;

-- Finance Manager

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
    'bookings.view',
    'bookings.manage_payments',
    'bookings.view_all'
  )
where r.code = 'finance_manager'
on conflict (role_id, permission_id) do nothing;

-- Customer Success

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
    'bookings.view',
    'bookings.manage_documents'
  )
where r.code = 'customer_success'
on conflict (role_id, permission_id) do nothing;

-- Viewer

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code = 'bookings.view'
where r.code = 'viewer'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- 3. BOOKINGS
-- =========================================================

create table public.bookings (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete restrict,

  site_visit_id uuid
    references public.site_visits(id)
    on delete set null,

  booking_number text not null,

  project_reference_id text,
  project_name text not null,
  developer_name text,

  property_type text,
  unit_type text,
  unit_number text,
  tower text,
  floor text,

  booking_amount numeric(18,2)
    check (
      booking_amount is null
      or booking_amount >= 0
    ),

  unit_price numeric(18,2)
    check (
      unit_price is null
      or unit_price >= 0
    ),

  booking_currency text not null default 'INR',

  payment_status public.booking_payment_status
    not null default 'pending',

  booking_status public.booking_status
    not null default 'draft',

  booked_by uuid
    references auth.users(id)
    on delete set null,

  booked_at timestamptz,

  expected_agreement_date date,
  expected_possession_date date,

  payment_plan text,
  finance_required boolean,
  loan_provider text,
  loan_reference text,

  cancellation_reason text,
  cancelled_at timestamptz,
  cancelled_by uuid
    references auth.users(id)
    on delete set null,

  refund_amount numeric(18,2)
    check (
      refund_amount is null
      or refund_amount >= 0
    ),

  remarks text,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  updated_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint bookings_org_number_unique
    unique (organization_id, booking_number)
);

create index bookings_organization_idx
  on public.bookings(organization_id);

create index bookings_lead_idx
  on public.bookings(
    lead_id,
    created_at desc
  );

create index bookings_site_visit_idx
  on public.bookings(site_visit_id)
  where site_visit_id is not null;

create index bookings_status_idx
  on public.bookings(
    organization_id,
    booking_status,
    created_at desc
  );

create index bookings_payment_status_idx
  on public.bookings(
    organization_id,
    payment_status,
    created_at desc
  );

create index bookings_booked_by_idx
  on public.bookings(
    organization_id,
    booked_by,
    created_at desc
  );

create trigger bookings_set_updated_at
before update on public.bookings
for each row
execute function public.set_updated_at();

-- =========================================================
-- 4. BOOKING DOCUMENTS
-- =========================================================

create table public.booking_documents (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  booking_id uuid not null
    references public.bookings(id)
    on delete cascade,

  document_name text not null,

  document_type text not null,

  document_status text not null default 'uploaded'
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

  expiry_date date,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index booking_documents_organization_idx
  on public.booking_documents(organization_id);

create index booking_documents_booking_idx
  on public.booking_documents(
    booking_id,
    created_at desc
  );

create index booking_documents_status_idx
  on public.booking_documents(
    organization_id,
    document_status
  );

create index booking_documents_verified_idx
  on public.booking_documents(
    organization_id,
    verified
  );

create trigger booking_documents_set_updated_at
before update on public.booking_documents
for each row
execute function public.set_updated_at();

-- =========================================================
-- 5. BOOKING PAYMENTS
-- =========================================================

create table public.booking_payments (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  booking_id uuid not null
    references public.bookings(id)
    on delete cascade,

  payment_type text not null default 'other'
    check (
      payment_type in (
        'token',
        'booking_amount',
        'installment',
        'stamp_duty',
        'registration',
        'maintenance',
        'club_charge',
        'parking',
        'tax',
        'refund',
        'other'
      )
    ),

  amount numeric(18,2) not null
    check (amount > 0),

  currency text not null default 'INR',

  payment_mode text
    check (
      payment_mode is null
      or payment_mode in (
        'cash',
        'cheque',
        'bank_transfer',
        'upi',
        'credit_card',
        'debit_card',
        'payment_gateway',
        'loan_disbursement',
        'other'
      )
    ),

  payment_reference text,

  gateway_provider text,
  gateway_transaction_id text,

  payment_date timestamptz,

  payment_status public.booking_payment_status
    not null default 'pending',

  failure_reason text,

  refund_reference text,
  refunded_at timestamptz,

  receipt_number text,
  receipt_url text,

  remarks text,

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

create index booking_payments_organization_idx
  on public.booking_payments(organization_id);

create index booking_payments_booking_idx
  on public.booking_payments(
    booking_id,
    created_at desc
  );

create index booking_payments_status_idx
  on public.booking_payments(
    organization_id,
    payment_status,
    payment_date
  );

create index booking_payments_reference_idx
  on public.booking_payments(
    organization_id,
    payment_reference
  )
  where payment_reference is not null;

create index booking_payments_gateway_idx
  on public.booking_payments(
    gateway_provider,
    gateway_transaction_id
  )
  where gateway_transaction_id is not null;

create trigger booking_payments_set_updated_at
before update on public.booking_payments
for each row
execute function public.set_updated_at();

-- =========================================================
-- 6. BOOKING STATUS HISTORY
-- =========================================================

create table public.booking_status_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  booking_id uuid not null
    references public.bookings(id)
    on delete cascade,

  previous_status public.booking_status,

  new_status public.booking_status not null,

  previous_payment_status public.booking_payment_status,

  new_payment_status public.booking_payment_status,

  change_reason text,

  changed_by uuid
    references auth.users(id)
    on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  changed_at timestamptz not null default now()
);

create index booking_status_history_organization_idx
  on public.booking_status_history(organization_id);

create index booking_status_history_booking_idx
  on public.booking_status_history(
    booking_id,
    changed_at desc
  );

create index booking_status_history_status_idx
  on public.booking_status_history(
    organization_id,
    new_status,
    changed_at desc
  );

-- =========================================================
-- 7. VALIDATE BOOKING RELATIONS
-- =========================================================

create or replace function public.validate_booking_relations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.leads l
    where l.id = new.lead_id
      and l.organization_id = new.organization_id
      and l.deleted_at is null
  ) then
    raise exception
      'Lead must belong to the booking organization';
  end if;

  if new.site_visit_id is not null
    and not exists (
      select 1
      from public.site_visits sv
      where sv.id = new.site_visit_id
        and sv.organization_id = new.organization_id
        and sv.lead_id = new.lead_id
        and sv.deleted_at is null
    ) then
    raise exception
      'Site visit must belong to the same organization and lead';
  end if;

  if new.booked_by is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.booked_by
        and om.membership_status = 'active'
    ) then
    raise exception
      'Booked-by user must be an active organization member';
  end if;

  return new;
end;
$$;

create trigger bookings_validate_relations
before insert or update of
  organization_id,
  lead_id,
  site_visit_id,
  booked_by
on public.bookings
for each row
execute function public.validate_booking_relations();

-- =========================================================
-- 8. VALIDATE BOOKING DOCUMENT
-- =========================================================

create or replace function public.validate_booking_document()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.bookings b
    where b.id = new.booking_id
      and b.organization_id = new.organization_id
  ) then
    raise exception
      'Document must belong to the booking organization';
  end if;

  if new.uploaded_by is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.uploaded_by
        and om.membership_status = 'active'
    ) then
    raise exception
      'Document uploader must be an active organization member';
  end if;

  if new.verified_by is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.verified_by
        and om.membership_status = 'active'
    ) then
    raise exception
      'Document verifier must be an active organization member';
  end if;

  return new;
end;
$$;

create trigger booking_documents_validate
before insert or update of
  organization_id,
  booking_id,
  uploaded_by,
  verified_by
on public.booking_documents
for each row
execute function public.validate_booking_document();

-- =========================================================
-- 9. VALIDATE BOOKING PAYMENT
-- =========================================================

create or replace function public.validate_booking_payment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.bookings b
    where b.id = new.booking_id
      and b.organization_id = new.organization_id
  ) then
    raise exception
      'Payment must belong to the booking organization';
  end if;

  if new.created_by is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.created_by
        and om.membership_status = 'active'
    ) then
    raise exception
      'Payment creator must be an active organization member';
  end if;

  return new;
end;
$$;

create trigger booking_payments_validate
before insert or update of
  organization_id,
  booking_id,
  created_by
on public.booking_payments
for each row
execute function public.validate_booking_payment();

-- =========================================================
-- 10. BOOKING SYSTEM FIELDS
-- =========================================================

create or replace function public.set_booking_system_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.booked_by :=
      coalesce(new.booked_by, auth.uid());

    new.created_by :=
      coalesce(new.created_by, auth.uid());

    if new.booking_status <> 'draft'
      and new.booked_at is null then
      new.booked_at := now();
    end if;

    return new;
  end if;

  new.updated_by :=
    coalesce(new.updated_by, auth.uid());

  if new.booking_status is distinct from old.booking_status then

    if new.booking_status in (
      'token_paid',
      'application_submitted',
      'confirmed'
    )
      and new.booked_at is null then
      new.booked_at := now();
    end if;

    if new.booking_status = 'cancelled' then
      new.cancelled_at :=
        coalesce(new.cancelled_at, now());

      new.cancelled_by :=
        coalesce(new.cancelled_by, auth.uid());
    end if;

  end if;

  return new;
end;
$$;

create trigger bookings_set_system_fields
before insert or update of booking_status
on public.bookings
for each row
execute function public.set_booking_system_fields();

-- =========================================================
-- 11. DOCUMENT SYSTEM FIELDS
-- =========================================================

create or replace function public.set_booking_document_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.verified = true then
    new.document_status := 'verified';
    new.verified_at :=
      coalesce(new.verified_at, now());
    new.verified_by :=
      coalesce(new.verified_by, auth.uid());
  elsif new.document_status = 'rejected' then
    new.verified := false;
    new.verified_at := null;
  end if;

  if tg_op = 'INSERT' then
    new.uploaded_by :=
      coalesce(new.uploaded_by, auth.uid());
  end if;

  return new;
end;
$$;

create trigger booking_documents_set_system_fields
before insert or update of
  verified,
  document_status
on public.booking_documents
for each row
execute function public.set_booking_document_fields();

-- =========================================================
-- 12. BOOKING STATUS HISTORY
-- =========================================================

create or replace function public.record_booking_status_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    insert into public.booking_status_history (
      organization_id,
      booking_id,
      previous_status,
      new_status,
      previous_payment_status,
      new_payment_status,
      change_reason,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      null,
      new.booking_status,
      null,
      new.payment_status,
      'Booking created',
      coalesce(new.created_by, new.booked_by, auth.uid())
    );

    return new;
  end if;

  if new.booking_status is distinct from old.booking_status
    or new.payment_status is distinct from old.payment_status then

    insert into public.booking_status_history (
      organization_id,
      booking_id,
      previous_status,
      new_status,
      previous_payment_status,
      new_payment_status,
      change_reason,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      old.booking_status,
      new.booking_status,
      old.payment_status,
      new.payment_status,
      new.remarks,
      coalesce(new.updated_by, auth.uid())
    );

  end if;

  return new;
end;
$$;

create trigger bookings_record_status_history
after insert or update of
  booking_status,
  payment_status
on public.bookings
for each row
execute function public.record_booking_status_history();

-- =========================================================
-- 13. REFRESH BOOKING PAYMENT STATUS
-- =========================================================

create or replace function public.refresh_booking_payment_status(
  requested_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  booking_total numeric(18,2);
  paid_total numeric(18,2);
  paid_count integer;
  failed_count integer;
  refunded_count integer;
  total_payment_count integer;

  calculated_status public.booking_payment_status;
begin
  select b.booking_amount
  into booking_total
  from public.bookings b
  where b.id = requested_booking_id;

  if not found then
    return;
  end if;

  select
    coalesce(
      sum(bp.amount)
        filter (
          where bp.payment_status = 'paid'
        ),
      0
    ),

    count(*) filter (
      where bp.payment_status = 'paid'
    ),

    count(*) filter (
      where bp.payment_status = 'failed'
    ),

    count(*) filter (
      where bp.payment_status = 'refunded'
    ),

    count(*)

  into
    paid_total,
    paid_count,
    failed_count,
    refunded_count,
    total_payment_count

  from public.booking_payments bp
  where bp.booking_id = requested_booking_id;

  calculated_status :=
    case
      when total_payment_count > 0
        and refunded_count = total_payment_count
        then 'refunded'::public.booking_payment_status

      when booking_total is not null
        and booking_total > 0
        and paid_total >= booking_total
        then 'paid'::public.booking_payment_status

      when paid_total > 0
        then 'partial'::public.booking_payment_status

      when failed_count > 0
        and paid_count = 0
        then 'failed'::public.booking_payment_status

      else 'pending'::public.booking_payment_status
    end;

  update public.bookings
  set
    payment_status = calculated_status,

    booking_status = case
      when calculated_status = 'paid'
        and booking_status in (
          'draft',
          'token_paid',
          'payment_pending'
        )
        then 'confirmed'::public.booking_status

      when calculated_status = 'partial'
        and booking_status = 'draft'
        then 'token_paid'::public.booking_status

      else booking_status
    end,

    updated_at = now()

  where id = requested_booking_id;
end;
$$;

revoke all
on function public.refresh_booking_payment_status(uuid)
from public;

create or replace function public.trigger_refresh_booking_payment_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_booking_payment_status(
      old.booking_id
    );

    return old;
  end if;

  perform public.refresh_booking_payment_status(
    new.booking_id
  );

  if tg_op = 'UPDATE'
    and old.booking_id is distinct from new.booking_id then

    perform public.refresh_booking_payment_status(
      old.booking_id
    );

  end if;

  return new;
end;
$$;

create trigger booking_payments_refresh_booking
after insert or update of
  amount,
  payment_status,
  booking_id
or delete
on public.booking_payments
for each row
execute function public.trigger_refresh_booking_payment_status();

-- =========================================================
-- 14. REFRESH DOCUMENT STATUS
-- =========================================================

create or replace function public.refresh_booking_document_status(
  requested_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  total_documents integer;
  verified_documents integer;
begin
  select
    count(*),
    count(*) filter (
      where bd.verified = true
    )
  into
    total_documents,
    verified_documents
  from public.booking_documents bd
  where bd.booking_id = requested_booking_id;

  update public.bookings
  set
    booking_status = case
      when total_documents = 0
        and booking_status = 'application_submitted'
        then 'documents_pending'::public.booking_status

      when total_documents > 0
        and verified_documents = total_documents
        and booking_status in (
          'application_submitted',
          'documents_pending'
        )
        then 'documents_verified'::public.booking_status

      when total_documents > 0
        and verified_documents < total_documents
        and booking_status = 'application_submitted'
        then 'documents_pending'::public.booking_status

      else booking_status
    end,

    updated_at = now()

  where id = requested_booking_id;
end;
$$;

revoke all
on function public.refresh_booking_document_status(uuid)
from public;

create or replace function public.trigger_refresh_booking_document_status()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_booking_document_status(
      old.booking_id
    );

    return old;
  end if;

  perform public.refresh_booking_document_status(
    new.booking_id
  );

  if tg_op = 'UPDATE'
    and old.booking_id is distinct from new.booking_id then

    perform public.refresh_booking_document_status(
      old.booking_id
    );

  end if;

  return new;
end;
$$;

create trigger booking_documents_refresh_booking
after insert or update of
  booking_id,
  verified,
  document_status
or delete
on public.booking_documents
for each row
execute function public.trigger_refresh_booking_document_status();

-- =========================================================
-- 15. SYNC LEAD FROM BOOKING
-- =========================================================

create or replace function public.sync_lead_from_booking()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.booking_status in (
    'token_paid',
    'application_submitted',
    'documents_pending',
    'documents_verified',
    'loan_processing',
    'loan_approved',
    'agreement_signed',
    'payment_pending',
    'confirmed'
  ) then

    update public.leads
    set
      lead_status = 'booked',
      lifecycle_stage = 'customer',
      lead_temperature = 'hot',
      converted_at = coalesce(converted_at, now()),
      updated_at = now()
    where id = new.lead_id
      and organization_id = new.organization_id
      and deleted_at is null;

  elsif new.booking_status = 'cancelled' then

    update public.leads
    set
      lead_status = case
        when lead_status = 'booked'
          then 'negotiation'
        else lead_status
      end,

      lifecycle_stage = case
        when lifecycle_stage = 'customer'
          then 'opportunity'
        else lifecycle_stage
      end,

      updated_at = now()
    where id = new.lead_id
      and organization_id = new.organization_id
      and deleted_at is null;

  end if;

  return new;
end;
$$;

create trigger bookings_sync_lead
after insert or update of booking_status
on public.bookings
for each row
execute function public.sync_lead_from_booking();

-- =========================================================
-- 16. CREATE BOOKING ACTIVITY
-- =========================================================

create or replace function public.create_booking_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_subject text;
  generated_description text;
begin
  if tg_op = 'INSERT' then

    generated_subject := 'Booking created';

    generated_description :=
      concat(
        new.project_name,
        case
          when new.unit_number is not null
            then concat(' — Unit ', new.unit_number)
          else ''
        end
      );

  else

    if new.booking_status is not distinct from old.booking_status then
      return new;
    end if;

    generated_subject :=
      case new.booking_status
        when 'token_paid'
          then 'Booking token received'
        when 'application_submitted'
          then 'Booking application submitted'
        when 'documents_pending'
          then 'Booking documents pending'
        when 'documents_verified'
          then 'Booking documents verified'
        when 'loan_processing'
          then 'Loan processing started'
        when 'loan_approved'
          then 'Booking loan approved'
        when 'agreement_signed'
          then 'Booking agreement signed'
        when 'payment_pending'
          then 'Booking payment pending'
        when 'confirmed'
          then 'Booking confirmed'
        when 'cancelled'
          then 'Booking cancelled'
        when 'refunded'
          then 'Booking refunded'
        else 'Booking status updated'
      end;

    generated_description :=
      concat(
        'Booking ',
        new.booking_number,
        ' status changed to ',
        new.booking_status
      );

  end if;

  insert into public.lead_activities (
    organization_id,
    lead_id,
    activity_type,
    direction,
    activity_status,
    subject,
    description,
    outcome,
    completed_at,
    performed_by,
    is_automated,
    metadata,
    created_by
  )
  values (
    new.organization_id,
    new.lead_id,
    'system_event',
    'internal',
    'completed',
    generated_subject,
    generated_description,
    new.booking_status::text,
    now(),
    new.booked_by,
    true,
    jsonb_build_object(
      'booking_id',
      new.id,
      'booking_number',
      new.booking_number,
      'booking_status',
      new.booking_status,
      'payment_status',
      new.payment_status
    ),
    coalesce(
      new.updated_by,
      new.created_by,
      new.booked_by,
      auth.uid()
    )
  );

  return new;
end;
$$;

create trigger bookings_create_activity
after insert or update of booking_status
on public.bookings
for each row
execute function public.create_booking_activity();

-- =========================================================
-- 17. CONFIRM BOOKING FUNCTION
-- =========================================================

create or replace function public.confirm_booking(
  requested_booking_id uuid,
  requested_notes text default null
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_booking public.bookings;
begin
  select *
  into target_booking
  from public.bookings
  where id = requested_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;

  if not public.has_organization_permission(
    target_booking.organization_id,
    'bookings.confirm'
  ) then
    raise exception 'Permission denied';
  end if;

  update public.bookings
  set
    booking_status = 'confirmed',
    booked_at = coalesce(booked_at, now()),
    remarks = coalesce(requested_notes, remarks),
    updated_by = auth.uid(),
    updated_at = now()
  where id = requested_booking_id
  returning *
  into target_booking;

  return target_booking;
end;
$$;

revoke all
on function public.confirm_booking(uuid, text)
from public;

grant execute
on function public.confirm_booking(uuid, text)
to authenticated;

-- =========================================================
-- 18. CANCEL BOOKING FUNCTION
-- =========================================================

create or replace function public.cancel_booking(
  requested_booking_id uuid,
  requested_reason text
)
returns public.bookings
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_booking public.bookings;
begin
  select *
  into target_booking
  from public.bookings
  where id = requested_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;

  if not public.has_organization_permission(
    target_booking.organization_id,
    'bookings.cancel'
  ) then
    raise exception 'Permission denied';
  end if;

  update public.bookings
  set
    booking_status = 'cancelled',
    cancellation_reason = requested_reason,
    cancelled_at = now(),
    cancelled_by = auth.uid(),
    updated_by = auth.uid(),
    updated_at = now()
  where id = requested_booking_id
  returning *
  into target_booking;

  return target_booking;
end;
$$;

revoke all
on function public.cancel_booking(uuid, text)
from public;

grant execute
on function public.cancel_booking(uuid, text)
to authenticated;

-- =========================================================
-- 19. BOOKING DASHBOARD
-- =========================================================

create or replace function public.get_booking_dashboard(
  requested_organization_id uuid,
  requested_booked_by uuid default null
)
returns table (
  total_bookings bigint,
  draft_bookings bigint,
  confirmed_bookings bigint,
  cancelled_bookings bigint,
  payment_pending bigint,
  documents_pending bigint,
  total_booking_value numeric,
  total_paid_value numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_organization_permission(
    requested_organization_id,
    'bookings.view'
  ) then
    raise exception 'Permission denied';
  end if;

  return query

  with filtered_bookings as (
    select b.*
    from public.bookings b
    where b.organization_id =
      requested_organization_id
      and (
        requested_booked_by is null
        or b.booked_by = requested_booked_by
      )
  ),

  paid_summary as (
    select
      coalesce(sum(bp.amount), 0) as total_paid
    from public.booking_payments bp
    join filtered_bookings fb
      on fb.id = bp.booking_id
    where bp.payment_status = 'paid'
  )

  select
    count(*) as total_bookings,

    count(*) filter (
      where fb.booking_status = 'draft'
    ) as draft_bookings,

    count(*) filter (
      where fb.booking_status = 'confirmed'
    ) as confirmed_bookings,

    count(*) filter (
      where fb.booking_status = 'cancelled'
    ) as cancelled_bookings,

    count(*) filter (
      where fb.payment_status in (
        'pending',
        'partial',
        'failed'
      )
    ) as payment_pending,

    count(*) filter (
      where fb.booking_status = 'documents_pending'
    ) as documents_pending,

    coalesce(sum(fb.booking_amount), 0)
      as total_booking_value,

    ps.total_paid
      as total_paid_value

  from filtered_bookings fb
  cross join paid_summary ps
  group by ps.total_paid;
end;
$$;

revoke all
on function public.get_booking_dashboard(uuid, uuid)
from public;

grant execute
on function public.get_booking_dashboard(uuid, uuid)
to authenticated;

-- =========================================================
-- 20. ENABLE RLS
-- =========================================================

alter table public.bookings
  enable row level security;

alter table public.booking_documents
  enable row level security;

alter table public.booking_payments
  enable row level security;

alter table public.booking_status_history
  enable row level security;

-- =========================================================
-- 21. BOOKINGS RLS
-- =========================================================

create policy "Authorized users can view bookings"
on public.bookings
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.view'
  )
  and (
    public.has_organization_permission(
      organization_id,
      'bookings.view_all'
    )
    or booked_by = (select auth.uid())
    or created_by = (select auth.uid())
  )
);

create policy "Authorized users can create bookings"
on public.bookings
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'bookings.create'
  )
);

create policy "Authorized users can update bookings"
on public.bookings
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'bookings.update'
  )
);

create policy "Authorized users can delete bookings"
on public.bookings
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.delete'
  )
);

-- =========================================================
-- 22. BOOKING DOCUMENT RLS
-- =========================================================

create policy "Authorized users can view booking documents"
on public.booking_documents
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.view'
  )
);

create policy "Authorized users can create booking documents"
on public.booking_documents
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'bookings.manage_documents'
  )
);

create policy "Authorized users can update booking documents"
on public.booking_documents
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.manage_documents'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'bookings.manage_documents'
  )
);

create policy "Authorized users can delete booking documents"
on public.booking_documents
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.manage_documents'
  )
);

-- =========================================================
-- 23. BOOKING PAYMENT RLS
-- =========================================================

create policy "Authorized users can view booking payments"
on public.booking_payments
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.view'
  )
);

create policy "Authorized users can create booking payments"
on public.booking_payments
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'bookings.manage_payments'
  )
);

create policy "Authorized users can update booking payments"
on public.booking_payments
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.manage_payments'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'bookings.manage_payments'
  )
);

create policy "Authorized users can delete booking payments"
on public.booking_payments
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.manage_payments'
  )
);

-- =========================================================
-- 24. BOOKING HISTORY RLS
-- =========================================================

create policy "Authorized users can view booking history"
on public.booking_status_history
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'bookings.view'
  )
);

commit;