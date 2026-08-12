begin;

-- ============================================================
-- SalesSetu
-- 045_DealOS_Foundation.sql
--
-- Purpose:
--   Pre-booking commercial orchestration foundation.
--
-- Boundary:
--   Lead / Site Visit / Inventory
--          ↓
--        DealOS
--          ↓
--   Existing Booking Engine
--
-- DealOS owns:
--   - deal lifecycle
--   - negotiation offers / counter-offers
--   - commercial approval
--   - deal status history
--   - booking handoff reference
--
-- DealOS does NOT own:
--   - booking payments
--   - booking documents
--   - booking confirmation
--   - inventory master pricing
-- ============================================================


-- ============================================================
-- 1. DEAL PERMISSIONS
-- ============================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
values
  (
    'deals',
    'view',
    'deals.view',
    'View accessible deals'
  ),
  (
    'deals',
    'view_all',
    'deals.view_all',
    'View all deals in the organization'
  ),
  (
    'deals',
    'create',
    'deals.create',
    'Create deals'
  ),
  (
    'deals',
    'update',
    'deals.update',
    'Update deal information'
  ),
  (
    'deals',
    'assign',
    'deals.assign',
    'Assign deals to organization members'
  ),
  (
    'deals',
    'manage_offers',
    'deals.manage_offers',
    'Manage deal offers and counter-offers'
  ),
  (
    'deals',
    'approve_commercials',
    'deals.approve_commercials',
    'Approve commercial terms and pricing'
  ),
  (
    'deals',
    'mark_won',
    'deals.mark_won',
    'Mark deals as won'
  ),
  (
    'deals',
    'mark_lost',
    'deals.mark_lost',
    'Mark deals as lost'
  ),
  (
    'deals',
    'handoff_booking',
    'deals.handoff_booking',
    'Link and hand off deals to the booking engine'
  ),
  (
    'deals',
    'delete',
    'deals.delete',
    'Soft-delete deals'
  )
on conflict (code) do nothing;


-- Platform and organization administrators receive all DealOS
-- permissions.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.module = 'deals'
where r.code in (
  'platform_admin',
  'organization_admin'
)
on conflict (role_id, permission_id) do nothing;


-- Sales managers operate and supervise the complete commercial
-- workflow, but do not receive soft-delete permission by default.

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
    'deals.view',
    'deals.view_all',
    'deals.create',
    'deals.update',
    'deals.assign',
    'deals.manage_offers',
    'deals.approve_commercials',
    'deals.mark_won',
    'deals.mark_lost',
    'deals.handoff_booking'
  )
where r.code = 'sales_manager'
on conflict (role_id, permission_id) do nothing;


-- Sales agents operate their own deal and negotiation workflow.
-- Elevated commercial approvals / booking handoff remain separated.

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
    'deals.view',
    'deals.create',
    'deals.update',
    'deals.manage_offers'
  )
where r.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;


-- ============================================================
-- 2. ENUMS
-- ============================================================

create type public.deal_status as enum (
  'draft',
  'open',
  'negotiation',
  'commercial_review',
  'approved',
  'booking_ready',
  'won',
  'on_hold',
  'lost',
  'cancelled'
);


create type public.deal_offer_party as enum (
  'customer',
  'organization'
);


create type public.deal_offer_status as enum (
  'draft',
  'proposed',
  'countered',
  'accepted',
  'rejected',
  'withdrawn',
  'expired'
);


create type public.deal_commercial_approval_status as enum (
  'pending',
  'approved',
  'rejected',
  'cancelled'
);


-- ============================================================
-- 3. DEALS
-- ============================================================

create table public.deals (
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

  inventory_unit_id uuid
    references public.inventory_units(id)
    on delete set null,

  booking_id uuid
    references public.bookings(id)
    on delete set null,

  status public.deal_status
    not null
    default 'draft',

  assigned_to uuid,

  currency_code text
    not null
    default 'INR',

  listed_price_snapshot numeric(18,2),

  quoted_price_snapshot numeric(18,2),

  minimum_negotiable_price_snapshot numeric(18,2),

  agreed_price numeric(18,2),

  booking_probability numeric(5,2),

  next_action_at timestamptz,

  hold_reason text,

  loss_reason text,

  cancellation_reason text,

  notes text,

  won_at timestamptz,

  lost_at timestamptz,

  closed_at timestamptz,

  created_by uuid,

  updated_by uuid,

  deleted_by uuid,

  created_at timestamptz
    not null
    default now(),

  updated_at timestamptz
    not null
    default now(),

  deleted_at timestamptz,

  constraint deals_currency_code_check
    check (
      currency_code ~ '^[A-Z]{3}$'
    ),

  constraint deals_listed_price_check
    check (
      listed_price_snapshot is null
      or listed_price_snapshot >= 0
    ),

  constraint deals_quoted_price_check
    check (
      quoted_price_snapshot is null
      or quoted_price_snapshot >= 0
    ),

  constraint deals_minimum_negotiable_price_check
    check (
      minimum_negotiable_price_snapshot is null
      or minimum_negotiable_price_snapshot >= 0
    ),

  constraint deals_agreed_price_check
    check (
      agreed_price is null
      or agreed_price >= 0
    ),

  constraint deals_booking_probability_check
    check (
      booking_probability is null
      or (
        booking_probability >= 0
        and booking_probability <= 100
      )
    ),

  constraint deals_commercial_state_price_check
    check (
      status not in (
        'approved',
        'booking_ready',
        'won'
      )
      or agreed_price is not null
    ),

  constraint deals_won_booking_check
    check (
      status <> 'won'
      or booking_id is not null
    ),

  constraint deals_lost_reason_check
    check (
      status <> 'lost'
      or nullif(btrim(loss_reason), '') is not null
    ),

  constraint deals_cancel_reason_check
    check (
      status <> 'cancelled'
      or nullif(
        btrim(cancellation_reason),
        ''
      ) is not null
    )
);


-- One booking belongs to at most one non-deleted deal.

create unique index deals_booking_unique_idx
on public.deals (booking_id)
where
  booking_id is not null
  and deleted_at is null;


create index deals_organization_status_idx
on public.deals (
  organization_id,
  status
)
where deleted_at is null;


create index deals_lead_idx
on public.deals (
  organization_id,
  lead_id
)
where deleted_at is null;


create index deals_site_visit_idx
on public.deals (
  site_visit_id
)
where
  site_visit_id is not null
  and deleted_at is null;


create index deals_inventory_unit_idx
on public.deals (
  inventory_unit_id
)
where
  inventory_unit_id is not null
  and deleted_at is null;


create index deals_assigned_to_idx
on public.deals (
  organization_id,
  assigned_to,
  status
)
where
  assigned_to is not null
  and deleted_at is null;


create index deals_next_action_idx
on public.deals (
  organization_id,
  next_action_at
)
where
  next_action_at is not null
  and deleted_at is null;


-- ============================================================
-- 4. DEAL OFFERS
-- ============================================================

create table public.deal_offers (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  deal_id uuid not null
    references public.deals(id)
    on delete cascade,

  offered_by_party public.deal_offer_party
    not null,

  status public.deal_offer_status
    not null
    default 'draft',

  offer_amount numeric(18,2)
    not null,

  currency_code text
    not null
    default 'INR',

  offer_terms jsonb
    not null
    default '{}'::jsonb,

  notes text,

  valid_until timestamptz,

  responded_at timestamptz,

  created_by uuid,

  created_at timestamptz
    not null
    default now(),

  updated_at timestamptz
    not null
    default now(),

  constraint deal_offers_amount_check
    check (
      offer_amount > 0
    ),

  constraint deal_offers_currency_code_check
    check (
      currency_code ~ '^[A-Z]{3}$'
    ),

  constraint deal_offers_terms_object_check
    check (
      jsonb_typeof(offer_terms) = 'object'
    )
);


create index deal_offers_deal_created_idx
on public.deal_offers (
  deal_id,
  created_at desc
);


create index deal_offers_organization_idx
on public.deal_offers (
  organization_id,
  created_at desc
);


create index deal_offers_status_idx
on public.deal_offers (
  deal_id,
  status
);


-- ============================================================
-- 5. COMMERCIAL APPROVALS
-- ============================================================

create table public.deal_commercial_approvals (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  deal_id uuid not null
    references public.deals(id)
    on delete cascade,

  offer_id uuid
    references public.deal_offers(id)
    on delete set null,

  status public.deal_commercial_approval_status
    not null
    default 'pending',

  requested_amount numeric(18,2)
    not null,

  minimum_negotiable_price_snapshot numeric(18,2),

  request_reason text
    not null,

  decision_notes text,

  requested_by uuid,

  decided_by uuid,

  requested_at timestamptz
    not null
    default now(),

  decided_at timestamptz,

  created_at timestamptz
    not null
    default now(),

  updated_at timestamptz
    not null
    default now(),

  constraint deal_commercial_approvals_amount_check
    check (
      requested_amount > 0
    ),

  constraint deal_commercial_approvals_minimum_price_check
    check (
      minimum_negotiable_price_snapshot is null
      or minimum_negotiable_price_snapshot >= 0
    ),

  constraint deal_commercial_approvals_reason_check
    check (
      nullif(
        btrim(request_reason),
        ''
      ) is not null
    )
);


-- Prevent multiple simultaneous pending commercial approvals for
-- the same deal.

create unique index deal_commercial_approvals_pending_idx
on public.deal_commercial_approvals (
  deal_id
)
where status = 'pending';


create index deal_commercial_approvals_org_idx
on public.deal_commercial_approvals (
  organization_id,
  status,
  requested_at desc
);


-- ============================================================
-- 6. DEAL STATUS HISTORY
-- ============================================================

create table public.deal_status_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  deal_id uuid not null
    references public.deals(id)
    on delete cascade,

  previous_status public.deal_status,

  new_status public.deal_status
    not null,

  change_reason text,

  changed_by uuid,

  metadata jsonb
    not null
    default '{}'::jsonb,

  changed_at timestamptz
    not null
    default now(),

  constraint deal_status_history_metadata_check
    check (
      jsonb_typeof(metadata) = 'object'
    )
);


create index deal_status_history_deal_idx
on public.deal_status_history (
  deal_id,
  changed_at desc
);


create index deal_status_history_org_idx
on public.deal_status_history (
  organization_id,
  changed_at desc
);


-- ============================================================
-- 7. DEAL STATUS TRANSITION CONTRACT
-- ============================================================

create or replace function
public.is_deal_status_transition_allowed(
  previous_status public.deal_status,
  requested_status public.deal_status
)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select
    case
      when previous_status = requested_status
        then true

      when previous_status = 'draft'
        and requested_status in (
          'open',
          'negotiation',
          'commercial_review',
          'approved',
          'on_hold',
          'lost',
          'cancelled'
        )
        then true

      when previous_status = 'open'
        and requested_status in (
          'negotiation',
          'commercial_review',
          'approved',
          'on_hold',
          'lost',
          'cancelled'
        )
        then true

      when previous_status = 'negotiation'
        and requested_status in (
          'commercial_review',
          'approved',
          'on_hold',
          'lost',
          'cancelled'
        )
        then true

      when previous_status = 'commercial_review'
        and requested_status in (
          'negotiation',
          'approved',
          'on_hold',
          'lost',
          'cancelled'
        )
        then true

      when previous_status = 'approved'
        and requested_status in (
          'negotiation',
          'commercial_review',
          'booking_ready',
          'on_hold',
          'lost',
          'cancelled'
        )
        then true

      when previous_status = 'booking_ready'
        and requested_status in (
          'negotiation',
          'commercial_review',
          'approved',
          'won',
          'on_hold',
          'lost',
          'cancelled'
        )
        then true

      when previous_status = 'on_hold'
        and requested_status in (
          'open',
          'negotiation',
          'commercial_review',
          'approved',
          'booking_ready',
          'lost',
          'cancelled'
        )
        then true

      else false
    end;
$function$;


-- ============================================================
-- 8. DEAL VALIDATION + SYSTEM FIELDS
-- ============================================================

create or replace function
public.prepare_deal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := auth.uid();

  inventory_listed_price numeric(18,2);
  inventory_minimum_price numeric(18,2);

  site_visit_quoted_price numeric(18,2);
begin

  -- ----------------------------------------------------------
  -- Tenant / lead integrity
  -- ----------------------------------------------------------

  if not exists (
    select 1
    from public.leads l
    where l.id = new.lead_id
      and l.organization_id = new.organization_id
  ) then
    raise exception
      'Deal lead must belong to the deal organization'
      using errcode = 'P0001';
  end if;


  -- ----------------------------------------------------------
  -- Site visit integrity
  -- ----------------------------------------------------------

  if new.site_visit_id is not null then

    if not exists (
      select 1
      from public.site_visits sv
      where sv.id = new.site_visit_id
        and sv.organization_id = new.organization_id
        and sv.lead_id = new.lead_id
        and sv.deleted_at is null
    ) then
      raise exception
        'Deal site visit must belong to the same organization and lead'
        using errcode = 'P0001';
    end if;

  end if;


  -- ----------------------------------------------------------
  -- Inventory integrity
  -- ----------------------------------------------------------

  if new.inventory_unit_id is not null then

    if not exists (
      select 1
      from public.inventory_units iu
      where iu.id = new.inventory_unit_id
        and iu.organization_id = new.organization_id
        and iu.deleted_at is null
    ) then
      raise exception
        'Deal inventory unit must belong to the deal organization'
        using errcode = 'P0001';
    end if;

  end if;


  -- ----------------------------------------------------------
  -- Booking handoff integrity
  -- ----------------------------------------------------------

  if new.booking_id is not null then

    if not exists (
      select 1
      from public.bookings b
      where b.id = new.booking_id
        and b.organization_id = new.organization_id
        and b.lead_id = new.lead_id
    ) then
      raise exception
        'Deal booking must belong to the same organization and lead'
        using errcode = 'P0001';
    end if;


    if new.site_visit_id is not null
      and exists (
        select 1
        from public.bookings b
        where b.id = new.booking_id
          and b.site_visit_id is not null
          and b.site_visit_id <> new.site_visit_id
      )
    then
      raise exception
        'Deal booking site visit does not match the deal site visit'
        using errcode = 'P0001';
    end if;


    if new.inventory_unit_id is not null
      and exists (
        select 1
        from public.bookings b
        where b.id = new.booking_id
          and b.inventory_unit_id is not null
          and b.inventory_unit_id <> new.inventory_unit_id
      )
    then
      raise exception
        'Deal booking inventory unit does not match the deal inventory unit'
        using errcode = 'P0001';
    end if;


    if new.status = 'won'
      and exists (
        select 1
        from public.bookings b
        where b.id = new.booking_id
          and b.booking_status = 'cancelled'
      )
    then
      raise exception
        'A cancelled booking cannot be linked to a won deal'
        using errcode = 'P0001';
    end if;

  end if;


  -- ----------------------------------------------------------
  -- Assignment integrity
  -- ----------------------------------------------------------

  if new.assigned_to is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.assigned_to
        and om.membership_status = 'active'
    )
  then
    raise exception
      'Deal assignee must be an active organization member'
      using errcode = 'P0001';
  end if;


  -- ----------------------------------------------------------
  -- INSERT permissions / ownership
  -- ----------------------------------------------------------

  if tg_op = 'INSERT' then

    new.created_by :=
      coalesce(
        new.created_by,
        actor
      );

    new.updated_by :=
      coalesce(
        new.updated_by,
        actor
      );

    new.created_at :=
      coalesce(
        new.created_at,
        now()
      );

    new.updated_at := now();


    if actor is not null
      and new.assigned_to is not null
      and new.assigned_to <> actor
      and not public.has_organization_permission(
        new.organization_id,
        'deals.assign'
      )
    then
      raise exception
        'deals.assign permission is required to assign a deal to another user'
        using errcode = 'P0001';
    end if;


    if actor is not null
      and new.agreed_price is not null
      and not public.has_organization_permission(
        new.organization_id,
        'deals.approve_commercials'
      )
    then
      raise exception
        'deals.approve_commercials permission is required to set an agreed price directly'
        using errcode = 'P0001';
    end if;


    if actor is not null
      and new.booking_id is not null
      and not public.has_organization_permission(
        new.organization_id,
        'deals.handoff_booking'
      )
    then
      raise exception
        'deals.handoff_booking permission is required to link a booking'
        using errcode = 'P0001';
    end if;


    if actor is not null
      and new.status in (
        'approved',
        'booking_ready'
      )
      and not public.has_organization_permission(
        new.organization_id,
        'deals.approve_commercials'
      )
    then
      raise exception
        'deals.approve_commercials permission is required for this deal state'
        using errcode = 'P0001';
    end if;


    if actor is not null
      and new.status = 'won'
      and (
        not public.has_organization_permission(
          new.organization_id,
          'deals.mark_won'
        )
        or not public.has_organization_permission(
          new.organization_id,
          'deals.handoff_booking'
        )
      )
    then
      raise exception
        'deals.mark_won and deals.handoff_booking permissions are required to create a won deal'
        using errcode = 'P0001';
    end if;


    if actor is not null
      and new.status = 'lost'
      and not public.has_organization_permission(
        new.organization_id,
        'deals.mark_lost'
      )
    then
      raise exception
        'deals.mark_lost permission is required to create a lost deal'
        using errcode = 'P0001';
    end if;

  end if;


  -- ----------------------------------------------------------
  -- UPDATE privilege guards
  --
  -- pg_trigger_depth() > 1 represents an internal DealOS trigger
  -- update, for example accepted-offer or approval propagation.
  -- ----------------------------------------------------------

  if tg_op = 'UPDATE'
    and pg_trigger_depth() <= 1
  then

    if new.assigned_to is distinct from old.assigned_to
      and actor is not null
      and not public.has_organization_permission(
        new.organization_id,
        'deals.assign'
      )
    then
      raise exception
        'deals.assign permission is required to change deal assignment'
        using errcode = 'P0001';
    end if;


    if new.booking_id is distinct from old.booking_id
      and actor is not null
      and not public.has_organization_permission(
        new.organization_id,
        'deals.handoff_booking'
      )
    then
      raise exception
        'deals.handoff_booking permission is required to change booking handoff'
        using errcode = 'P0001';
    end if;


    if (
      new.listed_price_snapshot
        is distinct from old.listed_price_snapshot
      or new.quoted_price_snapshot
        is distinct from old.quoted_price_snapshot
      or new.minimum_negotiable_price_snapshot
        is distinct from old.minimum_negotiable_price_snapshot
      or new.agreed_price
        is distinct from old.agreed_price
    )
      and actor is not null
      and not public.has_organization_permission(
        new.organization_id,
        'deals.approve_commercials'
      )
    then
      raise exception
        'Direct commercial value changes require deals.approve_commercials permission'
        using errcode = 'P0001';
    end if;


    if new.deleted_at is distinct from old.deleted_at
      and actor is not null
      and not public.has_organization_permission(
        new.organization_id,
        'deals.delete'
      )
    then
      raise exception
        'deals.delete permission is required to change deal deletion state'
        using errcode = 'P0001';
    end if;


    if new.status is distinct from old.status then

      if not public.is_deal_status_transition_allowed(
        old.status,
        new.status
      ) then
        raise exception
          'Invalid DealOS status transition: % -> %',
          old.status,
          new.status
          using errcode = 'P0001';
      end if;


      if new.status in (
        'approved',
        'booking_ready'
      )
        and actor is not null
        and not public.has_organization_permission(
          new.organization_id,
          'deals.approve_commercials'
        )
      then
        raise exception
          'deals.approve_commercials permission is required for this deal transition'
          using errcode = 'P0001';
      end if;


      if new.status = 'won'
        and actor is not null
        and (
          not public.has_organization_permission(
            new.organization_id,
            'deals.mark_won'
          )
          or not public.has_organization_permission(
            new.organization_id,
            'deals.handoff_booking'
          )
        )
      then
        raise exception
          'deals.mark_won and deals.handoff_booking permissions are required to mark a deal won'
          using errcode = 'P0001';
      end if;


      if new.status = 'lost'
        and actor is not null
        and not public.has_organization_permission(
          new.organization_id,
          'deals.mark_lost'
        )
      then
        raise exception
          'deals.mark_lost permission is required to mark a deal lost'
          using errcode = 'P0001';
      end if;

    end if;

  end if;


  -- ----------------------------------------------------------
  -- Inventory price snapshots
  --
  -- Inventory remains the pricing source-of-truth.
  -- DealOS stores the commercial snapshot used by negotiation.
  -- ----------------------------------------------------------

  if new.inventory_unit_id is not null
    and (
      tg_op = 'INSERT'
      or new.inventory_unit_id
        is distinct from old.inventory_unit_id
    )
  then

    select
      coalesce(
        iu.all_inclusive_price,
        iu.current_price,
        iu.base_price
      ),
      iu.minimum_negotiable_price
    into
      inventory_listed_price,
      inventory_minimum_price
    from public.inventory_units iu
    where iu.id = new.inventory_unit_id
      and iu.organization_id = new.organization_id
      and iu.deleted_at is null;


    if tg_op = 'INSERT' then

      new.listed_price_snapshot :=
        coalesce(
          new.listed_price_snapshot,
          inventory_listed_price
        );

      new.minimum_negotiable_price_snapshot :=
        coalesce(
          new.minimum_negotiable_price_snapshot,
          inventory_minimum_price
        );

    else

      new.listed_price_snapshot :=
        inventory_listed_price;

      new.minimum_negotiable_price_snapshot :=
        inventory_minimum_price;

    end if;

  end if;


  -- ----------------------------------------------------------
  -- Site Visit quoted-price snapshot
  -- ----------------------------------------------------------

  if new.site_visit_id is not null
    and (
      tg_op = 'INSERT'
      or new.site_visit_id
        is distinct from old.site_visit_id
    )
  then

    select
      sv.quoted_price
    into
      site_visit_quoted_price
    from public.site_visits sv
    where sv.id = new.site_visit_id
      and sv.organization_id = new.organization_id
      and sv.lead_id = new.lead_id
      and sv.deleted_at is null;


    if tg_op = 'INSERT' then

      new.quoted_price_snapshot :=
        coalesce(
          new.quoted_price_snapshot,
          site_visit_quoted_price
        );

    else

      new.quoted_price_snapshot :=
        site_visit_quoted_price;

    end if;

  end if;


  -- ----------------------------------------------------------
  -- System fields
  -- ----------------------------------------------------------

  if tg_op = 'UPDATE' then

    new.updated_by :=
      coalesce(
        actor,
        new.updated_by
      );

    new.updated_at := now();

  end if;


  if new.status = 'won' then

    new.won_at :=
      coalesce(
        new.won_at,
        now()
      );

    new.closed_at :=
      coalesce(
        new.closed_at,
        now()
      );

  elsif new.status = 'lost' then

    new.lost_at :=
      coalesce(
        new.lost_at,
        now()
      );

    new.closed_at :=
      coalesce(
        new.closed_at,
        now()
      );

  elsif new.status = 'cancelled' then

    new.closed_at :=
      coalesce(
        new.closed_at,
        now()
      );

  end if;


  if new.deleted_at is not null
    and (
      tg_op = 'INSERT'
      or new.deleted_at
        is distinct from old.deleted_at
    )
  then

    new.deleted_by :=
      coalesce(
        new.deleted_by,
        actor
      );

  end if;


  return new;

end;
$function$;


create trigger deals_prepare
before insert or update
on public.deals
for each row
execute function public.prepare_deal();


-- ============================================================
-- 9. OFFER VALIDATION / IMMUTABILITY
-- ============================================================

create or replace function
public.prepare_deal_offer()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin

  if not exists (
    select 1
    from public.deals d
    where d.id = new.deal_id
      and d.organization_id = new.organization_id
      and d.deleted_at is null
  ) then
    raise exception
      'Deal offer must belong to an active deal in the same organization'
      using errcode = 'P0001';
  end if;


  if tg_op = 'INSERT' then

    if new.status not in (
      'draft',
      'proposed'
    ) then
      raise exception
        'New deal offers must start as draft or proposed'
        using errcode = 'P0001';
    end if;

    new.created_by :=
      coalesce(
        new.created_by,
        auth.uid()
      );

    new.created_at :=
      coalesce(
        new.created_at,
        now()
      );

    new.updated_at := now();

    return new;

  end if;


  -- Commercial offer content is immutable after creation.
  -- Only workflow status / response timestamp may change.

  if new.organization_id
      is distinct from old.organization_id
    or new.deal_id
      is distinct from old.deal_id
    or new.offered_by_party
      is distinct from old.offered_by_party
    or new.offer_amount
      is distinct from old.offer_amount
    or new.currency_code
      is distinct from old.currency_code
    or new.offer_terms
      is distinct from old.offer_terms
    or new.notes
      is distinct from old.notes
    or new.valid_until
      is distinct from old.valid_until
    or new.created_by
      is distinct from old.created_by
    or new.created_at
      is distinct from old.created_at
  then
    raise exception
      'Deal offer commercial terms are immutable; create a counter-offer instead'
      using errcode = 'P0001';
  end if;


  if new.status is distinct from old.status then

    if old.status = 'draft'
      and new.status not in (
        'proposed',
        'withdrawn'
      )
    then
      raise exception
        'Invalid deal offer status transition'
        using errcode = 'P0001';

    elsif old.status = 'proposed'
      and new.status not in (
        'countered',
        'accepted',
        'rejected',
        'withdrawn',
        'expired'
      )
    then
      raise exception
        'Invalid deal offer status transition'
        using errcode = 'P0001';

    elsif old.status in (
      'countered',
      'accepted',
      'rejected',
      'withdrawn',
      'expired'
    )
    then
      raise exception
        'Terminal deal offers cannot change status'
        using errcode = 'P0001';

    end if;


    if new.status in (
      'countered',
      'accepted',
      'rejected',
      'withdrawn',
      'expired'
    ) then
      new.responded_at :=
        coalesce(
          new.responded_at,
          now()
        );
    end if;

  end if;


  new.updated_at := now();

  return new;

end;
$function$;


create trigger deal_offers_prepare
before insert or update
on public.deal_offers
for each row
execute function public.prepare_deal_offer();


-- ============================================================
-- 10. OFFER → DEAL EFFECTS
-- ============================================================

create or replace function
public.apply_deal_offer_effects()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin

  -- A newly proposed offer means the negotiation has started.
  -- Previous still-open proposed offers become countered.

  if new.status = 'proposed'
    and (
      tg_op = 'INSERT'
      or new.status is distinct from old.status
    )
  then

    update public.deal_offers
    set
      status = 'countered',
      responded_at =
        coalesce(
          responded_at,
          now()
        ),
      updated_at = now()
    where deal_id = new.deal_id
      and id <> new.id
      and status = 'proposed';


    update public.deals
    set
      status = 'negotiation',
      updated_at = now()
    where id = new.deal_id
      and deleted_at is null
      and status in (
        'draft',
        'open'
      );

  end if;


  -- Accepted commercial offer becomes the agreed commercial
  -- value.
  --
  -- If the accepted amount is below the frozen minimum
  -- negotiable price, move to commercial review.
  --
  -- Otherwise it can be commercially approved automatically.

  if new.status = 'accepted'
    and (
      tg_op = 'INSERT'
      or new.status is distinct from old.status
    )
  then

    update public.deals d
    set
      agreed_price = new.offer_amount,

      status =
        case
          when
            d.minimum_negotiable_price_snapshot is null
            or new.offer_amount
              >= d.minimum_negotiable_price_snapshot
          then 'approved'::public.deal_status

          else 'commercial_review'::public.deal_status
        end,

      updated_at = now()

    where d.id = new.deal_id
      and d.deleted_at is null
      and d.status not in (
        'won',
        'lost',
        'cancelled'
      );

  end if;


  return new;

end;
$function$;


create trigger deal_offers_apply_effects
after insert or update of status
on public.deal_offers
for each row
execute function public.apply_deal_offer_effects();


-- ============================================================
-- 11. COMMERCIAL APPROVAL VALIDATION
-- ============================================================

create or replace function
public.prepare_deal_commercial_approval()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  deal_minimum_price numeric(18,2);
begin

  if not exists (
    select 1
    from public.deals d
    where d.id = new.deal_id
      and d.organization_id = new.organization_id
      and d.deleted_at is null
  ) then
    raise exception
      'Commercial approval must belong to an active deal in the same organization'
      using errcode = 'P0001';
  end if;


  if new.offer_id is not null
    and not exists (
      select 1
      from public.deal_offers o
      where o.id = new.offer_id
        and o.deal_id = new.deal_id
        and o.organization_id = new.organization_id
    )
  then
    raise exception
      'Commercial approval offer must belong to the same deal'
      using errcode = 'P0001';
  end if;


  if tg_op = 'INSERT' then

    if new.status <> 'pending' then
      raise exception
        'New commercial approval requests must start as pending'
        using errcode = 'P0001';
    end if;


    select
      d.minimum_negotiable_price_snapshot
    into
      deal_minimum_price
    from public.deals d
    where d.id = new.deal_id;


    new.minimum_negotiable_price_snapshot :=
      coalesce(
        new.minimum_negotiable_price_snapshot,
        deal_minimum_price
      );


    new.requested_by :=
      coalesce(
        new.requested_by,
        auth.uid()
      );

    new.requested_at :=
      coalesce(
        new.requested_at,
        now()
      );

    new.created_at :=
      coalesce(
        new.created_at,
        now()
      );

    new.updated_at := now();

    return new;

  end if;


  -- Request context is immutable after submission.

  if new.organization_id
      is distinct from old.organization_id
    or new.deal_id
      is distinct from old.deal_id
    or new.offer_id
      is distinct from old.offer_id
    or new.requested_amount
      is distinct from old.requested_amount
    or new.minimum_negotiable_price_snapshot
      is distinct from old.minimum_negotiable_price_snapshot
    or new.request_reason
      is distinct from old.request_reason
    or new.requested_by
      is distinct from old.requested_by
    or new.requested_at
      is distinct from old.requested_at
    or new.created_at
      is distinct from old.created_at
  then
    raise exception
      'Commercial approval request values are immutable'
      using errcode = 'P0001';
  end if;


  if new.status is distinct from old.status then

    if old.status <> 'pending' then
      raise exception
        'Completed commercial approvals cannot change status'
        using errcode = 'P0001';
    end if;


    if new.status not in (
      'approved',
      'rejected',
      'cancelled'
    ) then
      raise exception
        'Invalid commercial approval status transition'
        using errcode = 'P0001';
    end if;


    new.decided_by :=
      coalesce(
        new.decided_by,
        auth.uid()
      );

    new.decided_at :=
      coalesce(
        new.decided_at,
        now()
      );

  end if;


  new.updated_at := now();

  return new;

end;
$function$;


create trigger deal_commercial_approvals_prepare
before insert or update
on public.deal_commercial_approvals
for each row
execute function public.prepare_deal_commercial_approval();


-- ============================================================
-- 12. APPROVAL → DEAL EFFECTS
-- ============================================================

create or replace function
public.apply_deal_commercial_approval_effects()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin

  -- Pending approval moves the deal into commercial review.

  if tg_op = 'INSERT'
    and new.status = 'pending'
  then

    update public.deals
    set
      status = 'commercial_review',
      updated_at = now()
    where id = new.deal_id
      and deleted_at is null
      and status in (
        'draft',
        'open',
        'negotiation',
        'approved',
        'booking_ready',
        'on_hold'
      );

  end if;


  if tg_op = 'UPDATE'
    and new.status is distinct from old.status
  then

    if new.status = 'approved' then

      update public.deals
      set
        agreed_price = new.requested_amount,
        status = 'approved',
        updated_at = now()
      where id = new.deal_id
        and deleted_at is null
        and status not in (
          'won',
          'lost',
          'cancelled'
        );


    elsif new.status in (
      'rejected',
      'cancelled'
    ) then

      update public.deals
      set
        status = 'negotiation',
        updated_at = now()
      where id = new.deal_id
        and deleted_at is null
        and status = 'commercial_review';

    end if;

  end if;


  return new;

end;
$function$;


create trigger deal_commercial_approvals_apply_effects
after insert or update of status
on public.deal_commercial_approvals
for each row
execute function
  public.apply_deal_commercial_approval_effects();


-- ============================================================
-- 13. DEAL STATUS HISTORY
-- ============================================================

create or replace function
public.record_deal_status_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  generated_reason text;
begin

  generated_reason :=
    case
      when new.status = 'lost'
        then new.loss_reason

      when new.status = 'on_hold'
        then new.hold_reason

      when new.status = 'cancelled'
        then new.cancellation_reason

      else null
    end;


  if tg_op = 'INSERT' then

    insert into public.deal_status_history (
      organization_id,
      deal_id,
      previous_status,
      new_status,
      change_reason,
      changed_by,
      metadata
    )
    values (
      new.organization_id,
      new.id,
      null,
      new.status,
      generated_reason,
      coalesce(
        new.created_by,
        auth.uid()
      ),
      jsonb_build_object(
        'event',
        'deal_created'
      )
    );

    return new;

  end if;


  if new.status is distinct from old.status then

    insert into public.deal_status_history (
      organization_id,
      deal_id,
      previous_status,
      new_status,
      change_reason,
      changed_by,
      metadata
    )
    values (
      new.organization_id,
      new.id,
      old.status,
      new.status,
      generated_reason,
      coalesce(
        new.updated_by,
        auth.uid()
      ),
      jsonb_build_object(
        'booking_id',
        new.booking_id,
        'inventory_unit_id',
        new.inventory_unit_id,
        'site_visit_id',
        new.site_visit_id
      )
    );

  end if;


  return new;

end;
$function$;


create trigger deals_record_status_history
after insert or update of status
on public.deals
for each row
execute function public.record_deal_status_history();


-- ============================================================
-- 14. SAFE LEAD SYNCHRONIZATION
--
-- Active DealOS states move the parent lead into negotiation.
--
-- Won state is intentionally not written here:
-- existing Booking Engine remains authoritative for booked /
-- customer lifecycle state.
--
-- When the final active deal is lost/cancelled/deleted, a
-- completed site visit can safely restore site_visit_completed.
-- ============================================================

create or replace function
public.sync_lead_from_deal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  active_deal_exists boolean;
  completed_site_visit_exists boolean;
begin

  -- Booking Engine owns the final won/booked state.

  if new.status = 'won'
    and new.deleted_at is null
  then
    return new;
  end if;


  -- Active commercial workflow.

  if new.deleted_at is null
    and new.status in (
      'open',
      'negotiation',
      'commercial_review',
      'approved',
      'booking_ready',
      'on_hold'
    )
  then

    update public.leads
    set
      lead_status = 'negotiation',
      lifecycle_stage = 'opportunity',
      updated_at = now()
    where id = new.lead_id
      and organization_id = new.organization_id
      and lead_status <> 'booked';

    return new;

  end if;


  -- Terminal / deleted deal reconciliation.

  if new.deleted_at is not null
    or new.status in (
      'lost',
      'cancelled'
    )
  then

    select exists (
      select 1
      from public.deals d
      where d.organization_id = new.organization_id
        and d.lead_id = new.lead_id
        and d.id <> new.id
        and d.deleted_at is null
        and d.status in (
          'open',
          'negotiation',
          'commercial_review',
          'approved',
          'booking_ready',
          'on_hold'
        )
    )
    into active_deal_exists;


    if active_deal_exists then
      return new;
    end if;


    select exists (
      select 1
      from public.site_visits sv
      where sv.organization_id = new.organization_id
        and sv.lead_id = new.lead_id
        and sv.deleted_at is null
        and sv.status = 'completed'
    )
    into completed_site_visit_exists;


    if completed_site_visit_exists then

      update public.leads
      set
        lead_status = 'site_visit_completed',
        lifecycle_stage = 'opportunity',
        updated_at = now()
      where id = new.lead_id
        and organization_id = new.organization_id
        and lead_status <> 'booked';

    end if;

  end if;


  return new;

end;
$function$;


create trigger deals_sync_lead
after insert or update of
  status,
  deleted_at
on public.deals
for each row
execute function public.sync_lead_from_deal();


-- ============================================================
-- 15. DEAL ACCESS HELPER
--
-- SECURITY DEFINER avoids recursive child-table RLS lookups while
-- still enforcing organization permission and ownership.
-- ============================================================

create or replace function
public.can_access_deal(
  requested_deal_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1
    from public.deals d
    where d.id = requested_deal_id
      and d.deleted_at is null
      and public.has_organization_permission(
        d.organization_id,
        'deals.view'
      )
      and (
        public.has_organization_permission(
          d.organization_id,
          'deals.view_all'
        )
        or d.assigned_to = auth.uid()
        or d.created_by = auth.uid()
      )
  );
$function$;


revoke all
on function public.can_access_deal(uuid)
from public;


grant execute
on function public.can_access_deal(uuid)
to authenticated;


-- ============================================================
-- 16. ROW LEVEL SECURITY
-- ============================================================

alter table public.deals
  enable row level security;

alter table public.deal_offers
  enable row level security;

alter table public.deal_commercial_approvals
  enable row level security;

alter table public.deal_status_history
  enable row level security;


-- ------------------------------------------------------------
-- Deals
-- ------------------------------------------------------------

create policy "Authorized users can view deals"
on public.deals
for select
to authenticated
using (
  public.can_access_deal(id)
);


create policy "Authorized users can create deals"
on public.deals
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'deals.create'
  )
);


create policy "Authorized users can update deals"
on public.deals
for update
to authenticated
using (
  public.can_access_deal(id)
  and public.has_organization_permission(
    organization_id,
    'deals.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'deals.update'
  )
);


-- No authenticated hard-delete policy is intentionally created.
-- deals.delete is used by the application for audited soft-delete.


-- ------------------------------------------------------------
-- Deal offers
-- ------------------------------------------------------------

create policy "Authorized users can view deal offers"
on public.deal_offers
for select
to authenticated
using (
  public.can_access_deal(deal_id)
);


create policy "Authorized users can create deal offers"
on public.deal_offers
for insert
to authenticated
with check (
  public.can_access_deal(deal_id)
  and public.has_organization_permission(
    organization_id,
    'deals.manage_offers'
  )
);


create policy "Authorized users can update deal offers"
on public.deal_offers
for update
to authenticated
using (
  public.can_access_deal(deal_id)
  and public.has_organization_permission(
    organization_id,
    'deals.manage_offers'
  )
)
with check (
  public.can_access_deal(deal_id)
  and public.has_organization_permission(
    organization_id,
    'deals.manage_offers'
  )
);


-- Offer rows are an audit ledger: no authenticated DELETE policy.


-- ------------------------------------------------------------
-- Commercial approvals
-- ------------------------------------------------------------

create policy "Authorized users can view commercial approvals"
on public.deal_commercial_approvals
for select
to authenticated
using (
  public.can_access_deal(deal_id)
);


create policy "Authorized users can request commercial approval"
on public.deal_commercial_approvals
for insert
to authenticated
with check (
  public.can_access_deal(deal_id)
  and (
    public.has_organization_permission(
      organization_id,
      'deals.manage_offers'
    )
    or public.has_organization_permission(
      organization_id,
      'deals.approve_commercials'
    )
  )
);


create policy "Commercial approvers can decide requests"
on public.deal_commercial_approvals
for update
to authenticated
using (
  public.can_access_deal(deal_id)
  and public.has_organization_permission(
    organization_id,
    'deals.approve_commercials'
  )
)
with check (
  public.can_access_deal(deal_id)
  and public.has_organization_permission(
    organization_id,
    'deals.approve_commercials'
  )
);


create policy "Requesters can cancel pending commercial approvals"
on public.deal_commercial_approvals
for update
to authenticated
using (
  public.can_access_deal(deal_id)
  and requested_by = auth.uid()
  and status = 'pending'
)
with check (
  public.can_access_deal(deal_id)
  and requested_by = auth.uid()
  and status = 'cancelled'
);


-- No authenticated DELETE policy: approval history is retained.


-- ------------------------------------------------------------
-- Deal status history
-- ------------------------------------------------------------

create policy "Authorized users can view deal status history"
on public.deal_status_history
for select
to authenticated
using (
  public.can_access_deal(deal_id)
);


-- Status history is trigger-written only.
-- No authenticated INSERT / UPDATE / DELETE policies.


-- ============================================================
-- 17. EXPLICIT TABLE PRIVILEGES
-- ============================================================

revoke all
on table public.deals
from anon;

revoke all
on table public.deal_offers
from anon;

revoke all
on table public.deal_commercial_approvals
from anon;

revoke all
on table public.deal_status_history
from anon;


grant
  select,
  insert,
  update
on table public.deals
to authenticated;


grant
  select,
  insert,
  update
on table public.deal_offers
to authenticated;


grant
  select,
  insert,
  update
on table public.deal_commercial_approvals
to authenticated;


grant select
on table public.deal_status_history
to authenticated;


grant usage
on type public.deal_status
to authenticated;

grant usage
on type public.deal_offer_party
to authenticated;

grant usage
on type public.deal_offer_status
to authenticated;

grant usage
on type public.deal_commercial_approval_status
to authenticated;


grant all
on table public.deals
to service_role;

grant all
on table public.deal_offers
to service_role;

grant all
on table public.deal_commercial_approvals
to service_role;

grant all
on table public.deal_status_history
to service_role;


grant usage
on type public.deal_status
to service_role;

grant usage
on type public.deal_offer_party
to service_role;

grant usage
on type public.deal_offer_status
to service_role;

grant usage
on type public.deal_commercial_approval_status
to service_role;


grant execute
on function public.can_access_deal(uuid)
to service_role;


-- ============================================================
-- 18. COMMENTS
-- ============================================================

comment on table public.deals is
'DealOS pre-booking commercial lifecycle. Booking Engine remains the downstream transactional system of record.';


comment on table public.deal_offers is
'Immutable commercial offer and counter-offer ledger for DealOS negotiations.';


comment on table public.deal_commercial_approvals is
'Commercial exception and pricing approval workflow for DealOS.';


comment on table public.deal_status_history is
'Auditable DealOS status-transition history.';


comment on column public.deals.listed_price_snapshot is
'Inventory listed/commercial price snapshot captured for negotiation context.';


comment on column public.deals.minimum_negotiable_price_snapshot is
'Inventory minimum-negotiable-price snapshot captured when the inventory unit is attached to the deal.';


comment on column public.deals.booking_id is
'Downstream Booking Engine record linked during successful DealOS handoff.';


-- ============================================================
-- 19. POSTGREST SCHEMA RELOAD
-- ============================================================

select pg_notify(
  'pgrst',
  'reload schema'
);


commit;