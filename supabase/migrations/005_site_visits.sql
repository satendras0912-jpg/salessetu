-- =========================================================
-- SalesSetu Enterprise
-- Migration: 005_site_visits
-- Purpose: Site Visit Scheduling and Execution Engine
-- =========================================================

begin;

-- =========================================================
-- 1. SITE VISIT PERMISSIONS
-- =========================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
values
  (
    'site_visits',
    'view',
    'site_visits.view',
    'View site visits'
  ),
  (
    'site_visits',
    'create',
    'site_visits.create',
    'Schedule site visits'
  ),
  (
    'site_visits',
    'update',
    'site_visits.update',
    'Update site-visit information'
  ),
  (
    'site_visits',
    'assign',
    'site_visits.assign',
    'Assign site visits to organization members'
  ),
  (
    'site_visits',
    'check_in',
    'site_visits.check_in',
    'Check in customers and agents for site visits'
  ),
  (
    'site_visits',
    'complete',
    'site_visits.complete',
    'Complete site visits and record outcomes'
  ),
  (
    'site_visits',
    'cancel',
    'site_visits.cancel',
    'Cancel scheduled site visits'
  ),
  (
    'site_visits',
    'delete',
    'site_visits.delete',
    'Delete site-visit records'
  ),
  (
    'site_visits',
    'view_all',
    'site_visits.view_all',
    'View all organization site visits'
  )
on conflict (code) do nothing;

-- Platform and organization administrators receive
-- all site-visit permissions.

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
and p.module = 'site_visits'
on conflict (role_id, permission_id) do nothing;

-- Sales managers receive full operational access.

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
    'site_visits.view',
    'site_visits.create',
    'site_visits.update',
    'site_visits.assign',
    'site_visits.check_in',
    'site_visits.complete',
    'site_visits.cancel',
    'site_visits.delete',
    'site_visits.view_all'
  )
where r.code = 'sales_manager'
on conflict (role_id, permission_id) do nothing;

-- Sales agents manage their normal visit workflow.

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
    'site_visits.view',
    'site_visits.create',
    'site_visits.update',
    'site_visits.check_in',
    'site_visits.complete',
    'site_visits.cancel'
  )
where r.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;

-- Customer-success users receive view access.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code = 'site_visits.view'
where r.code = 'customer_success'
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
  on p.code = 'site_visits.view'
where r.code = 'viewer'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- 2. SITE VISITS
-- =========================================================

create table public.site_visits (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  follow_up_task_id uuid
    references public.follow_up_tasks(id)
    on delete set null,

  related_activity_id uuid
    references public.lead_activities(id)
    on delete set null,

  -- -------------------------------------------------------
  -- Visit identity
  -- -------------------------------------------------------

  visit_number text,

  title text not null default 'Property Site Visit',

  description text,

  visit_type text not null default 'physical'
    check (
      visit_type in (
        'physical',
        'virtual',
        'video_call',
        'property_showcase',
        'office_meeting',
        'other'
      )
    ),

  -- -------------------------------------------------------
  -- Property/project snapshot
  -- Proper project foreign key will be introduced when
  -- PropertyOS tables are created.
  -- -------------------------------------------------------

  project_reference_id text,

  project_name text not null,

  developer_name text,

  property_name text,

  property_type text,

  unit_reference text,

  unit_type text,

  tower text,

  floor text,

  unit_number text,

  visit_address text,

  visit_city text,

  visit_state text,

  visit_postal_code text,

  landmark text,

  location_url text,

  -- -------------------------------------------------------
  -- GPS-ready coordinates
  -- -------------------------------------------------------

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

  -- -------------------------------------------------------
  -- Visit lifecycle
  -- -------------------------------------------------------

  status text not null default 'scheduled'
    check (
      status in (
        'draft',
        'scheduled',
        'confirmed',
        'agent_en_route',
        'customer_en_route',
        'checked_in',
        'in_progress',
        'completed',
        'rescheduled',
        'cancelled',
        'no_show',
        'failed'
      )
    ),

  confirmation_status text not null default 'pending'
    check (
      confirmation_status in (
        'pending',
        'customer_confirmed',
        'agent_confirmed',
        'both_confirmed',
        'declined',
        'not_required'
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

  -- -------------------------------------------------------
  -- Scheduling
  -- -------------------------------------------------------

  scheduled_start_at timestamptz not null,

  scheduled_end_at timestamptz,

  expected_duration_minutes integer
    check (
      expected_duration_minutes is null
      or expected_duration_minutes > 0
    ),

  timezone text not null default 'Asia/Kolkata',

  reminder_at timestamptz,

  reminder_sent_at timestamptz,

  confirmed_at timestamptz,

  -- -------------------------------------------------------
  -- Assignment
  -- -------------------------------------------------------

  assigned_agent_id uuid
    references auth.users(id)
    on delete set null,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz,

  coordinator_id uuid
    references auth.users(id)
    on delete set null,

  -- -------------------------------------------------------
  -- Transport and logistics
  -- -------------------------------------------------------

  pickup_required boolean not null default false,

  pickup_address text,

  pickup_time timestamptz,

  transport_notes text,

  vehicle_details text,

  -- -------------------------------------------------------
  -- Check-in / check-out
  -- -------------------------------------------------------

  customer_checked_in_at timestamptz,

  agent_checked_in_at timestamptz,

  visit_started_at timestamptz,

  visit_completed_at timestamptz,

  customer_checked_out_at timestamptz,

  agent_checked_out_at timestamptz,

  customer_check_in_latitude numeric(10,7)
    check (
      customer_check_in_latitude is null
      or (
        customer_check_in_latitude >= -90
        and customer_check_in_latitude <= 90
      )
    ),

  customer_check_in_longitude numeric(10,7)
    check (
      customer_check_in_longitude is null
      or (
        customer_check_in_longitude >= -180
        and customer_check_in_longitude <= 180
      )
    ),

  agent_check_in_latitude numeric(10,7)
    check (
      agent_check_in_latitude is null
      or (
        agent_check_in_latitude >= -90
        and agent_check_in_latitude <= 90
      )
    ),

  agent_check_in_longitude numeric(10,7)
    check (
      agent_check_in_longitude is null
      or (
        agent_check_in_longitude >= -180
        and agent_check_in_longitude <= 180
      )
    ),

  check_in_method text
    check (
      check_in_method is null
      or check_in_method in (
        'manual',
        'gps',
        'qr_code',
        'otp',
        'agent_confirmation',
        'system'
      )
    ),

  -- -------------------------------------------------------
  -- Visit outcome
  -- -------------------------------------------------------

  outcome text
    check (
      outcome is null
      or outcome in (
        'interested',
        'highly_interested',
        'considering',
        'follow_up_required',
        'negotiation_started',
        'booking_expected',
        'not_interested',
        'budget_mismatch',
        'location_mismatch',
        'unit_mismatch',
        'postponed',
        'no_show',
        'other'
      )
    ),

  outcome_summary text,

  customer_feedback text,

  agent_notes text,

  customer_rating integer
    check (
      customer_rating is null
      or (
        customer_rating >= 1
        and customer_rating <= 5
      )
    ),

  agent_rating integer
    check (
      agent_rating is null
      or (
        agent_rating >= 1
        and agent_rating <= 5
      )
    ),

  project_rating integer
    check (
      project_rating is null
      or (
        project_rating >= 1
        and project_rating <= 5
      )
    ),

  probability_of_booking numeric(5,2)
    check (
      probability_of_booking is null
      or (
        probability_of_booking >= 0
        and probability_of_booking <= 100
      )
    ),

  expected_booking_date date,

  expected_booking_value numeric(15,2),

  -- -------------------------------------------------------
  -- Reschedule and cancellation
  -- -------------------------------------------------------

  reschedule_count integer not null default 0
    check (reschedule_count >= 0),

  previous_site_visit_id uuid
    references public.site_visits(id)
    on delete set null,

  reschedule_reason text,

  cancelled_at timestamptz,

  cancelled_by uuid
    references auth.users(id)
    on delete set null,

  cancellation_reason text,

  no_show_party text
    check (
      no_show_party is null
      or no_show_party in (
        'customer',
        'agent',
        'developer_representative',
        'both',
        'unknown'
      )
    ),

  -- -------------------------------------------------------
  -- Commercial information
  -- -------------------------------------------------------

  quoted_price numeric(15,2),

  quoted_currency text not null default 'INR',

  discount_discussed numeric(15,2),

  payment_plan_discussed text,

  booking_token_discussed numeric(15,2),

  -- -------------------------------------------------------
  -- Automation and integration
  -- -------------------------------------------------------

  is_automated boolean not null default false,

  automation_workflow_id text,

  external_visit_id text,

  external_provider text,

  meeting_link text,

  calendar_event_id text,

  -- -------------------------------------------------------
  -- Flexible information
  -- -------------------------------------------------------

  documents_shared jsonb not null default '[]'::jsonb,

  amenities_shown text[] not null default '{}'::text[],

  objections text[] not null default '{}'::text[],

  tags text[] not null default '{}'::text[],

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

  constraint site_visits_schedule_valid
    check (
      scheduled_end_at is null
      or scheduled_end_at >= scheduled_start_at
    ),

  constraint site_visits_actual_time_valid
    check (
      visit_started_at is null
      or visit_completed_at is null
      or visit_completed_at >= visit_started_at
    ),

  constraint site_visits_reminder_valid
    check (
      reminder_at is null
      or reminder_at <= scheduled_start_at
    ),

  constraint site_visits_pickup_time_valid
    check (
      pickup_time is null
      or pickup_time <= scheduled_start_at
    ),

  constraint site_visits_not_previous_self
    check (
      previous_site_visit_id is null
      or previous_site_visit_id <> id
    )
);

-- =========================================================
-- 3. SITE VISIT INDEXES
-- =========================================================

create index site_visits_organization_idx
  on public.site_visits(organization_id);

create index site_visits_lead_idx
  on public.site_visits(
    lead_id,
    scheduled_start_at desc
  );

create index site_visits_status_idx
  on public.site_visits(
    organization_id,
    status,
    scheduled_start_at
  )
  where deleted_at is null;

create index site_visits_agent_idx
  on public.site_visits(
    organization_id,
    assigned_agent_id,
    scheduled_start_at
  )
  where deleted_at is null;

create index site_visits_coordinator_idx
  on public.site_visits(
    organization_id,
    coordinator_id,
    scheduled_start_at
  )
  where deleted_at is null;

create index site_visits_schedule_idx
  on public.site_visits(
    organization_id,
    scheduled_start_at,
    scheduled_end_at
  )
  where deleted_at is null;

create index site_visits_upcoming_idx
  on public.site_visits(
    organization_id,
    scheduled_start_at
  )
  where deleted_at is null
    and status in (
      'scheduled',
      'confirmed',
      'agent_en_route',
      'customer_en_route'
    );

create index site_visits_reminder_idx
  on public.site_visits(reminder_at)
  where deleted_at is null
    and reminder_sent_at is null
    and status in (
      'scheduled',
      'confirmed'
    );

create index site_visits_project_idx
  on public.site_visits(
    organization_id,
    project_reference_id
  )
  where project_reference_id is not null
    and deleted_at is null;

create index site_visits_outcome_idx
  on public.site_visits(
    organization_id,
    outcome,
    visit_completed_at desc
  )
  where deleted_at is null;

create index site_visits_external_idx
  on public.site_visits(
    organization_id,
    external_provider,
    external_visit_id
  )
  where external_visit_id is not null;

create index site_visits_tags_gin_idx
  on public.site_visits
  using gin(tags);

create trigger site_visits_set_updated_at
before update on public.site_visits
for each row
execute function public.set_updated_at();

-- =========================================================
-- 4. SITE VISIT ATTENDEES
-- Customer companions, builder representatives and
-- internal organization members.
-- =========================================================

create table public.site_visit_attendees (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  site_visit_id uuid not null
    references public.site_visits(id)
    on delete cascade,

  attendee_type text not null
    check (
      attendee_type in (
        'primary_customer',
        'customer_companion',
        'sales_agent',
        'sales_manager',
        'developer_representative',
        'channel_partner',
        'driver',
        'other'
      )
    ),

  user_id uuid
    references auth.users(id)
    on delete set null,

  full_name text,

  phone text,

  email text,

  relationship_to_customer text,

  attendance_status text not null default 'expected'
    check (
      attendance_status in (
        'expected',
        'confirmed',
        'arrived',
        'absent',
        'cancelled'
      )
    ),

  checked_in_at timestamptz,

  checked_out_at timestamptz,

  notes text,

  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),

  updated_at timestamptz not null default now(),

  constraint site_visit_attendees_identity_present
    check (
      user_id is not null
      or nullif(trim(full_name), '') is not null
    ),

  constraint site_visit_attendees_time_valid
    check (
      checked_in_at is null
      or checked_out_at is null
      or checked_out_at >= checked_in_at
    )
);

create index site_visit_attendees_org_idx
  on public.site_visit_attendees(organization_id);

create index site_visit_attendees_visit_idx
  on public.site_visit_attendees(
    site_visit_id,
    attendee_type
  );

create index site_visit_attendees_user_idx
  on public.site_visit_attendees(
    organization_id,
    user_id
  )
  where user_id is not null;

create trigger site_visit_attendees_set_updated_at
before update on public.site_visit_attendees
for each row
execute function public.set_updated_at();

-- =========================================================
-- 5. VALIDATE LEAD ORGANIZATION
-- =========================================================

create or replace function public.validate_site_visit_lead()
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
      'Lead must belong to the site-visit organization';
  end if;

  return new;
end;
$$;

create trigger site_visits_validate_lead
before insert or update of
  organization_id,
  lead_id
on public.site_visits
for each row
execute function public.validate_site_visit_lead();

-- =========================================================
-- 6. VALIDATE RELATED FOLLOW-UP AND ACTIVITY
-- =========================================================

create or replace function public.validate_site_visit_relations()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.follow_up_task_id is not null
    and not exists (
      select 1
      from public.follow_up_tasks ft
      where ft.id = new.follow_up_task_id
        and ft.organization_id = new.organization_id
        and ft.lead_id = new.lead_id
        and ft.deleted_at is null
    ) then
    raise exception
      'Follow-up task must belong to the same organization and lead';
  end if;

  if new.related_activity_id is not null
    and not exists (
      select 1
      from public.lead_activities la
      where la.id = new.related_activity_id
        and la.organization_id = new.organization_id
        and la.lead_id = new.lead_id
    ) then
    raise exception
      'Related activity must belong to the same organization and lead';
  end if;

  if new.previous_site_visit_id is not null
    and not exists (
      select 1
      from public.site_visits sv
      where sv.id = new.previous_site_visit_id
        and sv.organization_id = new.organization_id
        and sv.lead_id = new.lead_id
        and sv.deleted_at is null
    ) then
    raise exception
      'Previous visit must belong to the same organization and lead';
  end if;

  return new;
end;
$$;

create trigger site_visits_validate_relations
before insert or update of
  organization_id,
  lead_id,
  follow_up_task_id,
  related_activity_id,
  previous_site_visit_id
on public.site_visits
for each row
execute function public.validate_site_visit_relations();

-- =========================================================
-- 7. VALIDATE ASSIGNED USERS
-- =========================================================

create or replace function public.validate_site_visit_users()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.assigned_agent_id is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.assigned_agent_id
        and om.membership_status = 'active'
    ) then
    raise exception
      'Assigned agent must be an active organization member';
  end if;

  if new.coordinator_id is not null
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.coordinator_id
        and om.membership_status = 'active'
    ) then
    raise exception
      'Coordinator must be an active organization member';
  end if;

  return new;
end;
$$;

create trigger site_visits_validate_users
before insert or update of
  organization_id,
  assigned_agent_id,
  coordinator_id
on public.site_visits
for each row
execute function public.validate_site_visit_users();

-- =========================================================
-- 8. VALIDATE ATTENDEE ORGANIZATION
-- =========================================================

create or replace function public.validate_site_visit_attendee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1
    from public.site_visits sv
    where sv.id = new.site_visit_id
      and sv.organization_id = new.organization_id
      and sv.deleted_at is null
  ) then
    raise exception
      'Site visit must belong to attendee organization';
  end if;

  if new.user_id is not null
    and new.attendee_type in (
      'sales_agent',
      'sales_manager'
    )
    and not exists (
      select 1
      from public.organization_members om
      where om.organization_id = new.organization_id
        and om.user_id = new.user_id
        and om.membership_status = 'active'
    ) then
    raise exception
      'Internal attendee must be an active organization member';
  end if;

  return new;
end;
$$;

create trigger site_visit_attendees_validate
before insert or update of
  organization_id,
  site_visit_id,
  user_id,
  attendee_type
on public.site_visit_attendees
for each row
execute function public.validate_site_visit_attendee();

-- =========================================================
-- 9. AUTOMATIC SITE-VISIT SYSTEM FIELDS
-- =========================================================

create or replace function public.set_site_visit_system_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    if new.assigned_agent_id is not null then
      new.assigned_at :=
        coalesce(new.assigned_at, now());

      new.assigned_by :=
        coalesce(new.assigned_by, auth.uid());
    end if;

    if new.status = 'confirmed' then
      new.confirmed_at :=
        coalesce(new.confirmed_at, now());
    end if;

    return new;
  end if;

  if new.assigned_agent_id
    is distinct from old.assigned_agent_id then

    new.assigned_at :=
      case
        when new.assigned_agent_id is null
          then null
        else now()
      end;

    new.assigned_by :=
      coalesce(new.assigned_by, auth.uid());
  end if;

  if new.status is distinct from old.status then

    if new.status = 'confirmed' then
      new.confirmed_at :=
        coalesce(new.confirmed_at, now());
    end if;

    if new.status = 'checked_in' then
      new.customer_checked_in_at :=
        coalesce(
          new.customer_checked_in_at,
          now()
        );
    end if;

    if new.status = 'in_progress' then
      new.visit_started_at :=
        coalesce(new.visit_started_at, now());
    end if;

    if new.status = 'completed' then
      new.visit_completed_at :=
        coalesce(new.visit_completed_at, now());
    end if;

    if new.status = 'cancelled' then
      new.cancelled_at :=
        coalesce(new.cancelled_at, now());

      new.cancelled_by :=
        coalesce(new.cancelled_by, auth.uid());
    end if;

  end if;

  return new;
end;
$$;

create trigger site_visits_set_system_fields
before insert or update of
  assigned_agent_id,
  status
on public.site_visits
for each row
execute function public.set_site_visit_system_fields();

-- =========================================================
-- 10. ENABLE ROW LEVEL SECURITY
-- Policies and history tables will be added in Part 2.
-- =========================================================

alter table public.site_visits
  enable row level security;

alter table public.site_visit_attendees
  enable row level security;

  -- =========================================================
-- 11. SITE-VISIT STATUS HISTORY
-- =========================================================

create table public.site_visit_status_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  site_visit_id uuid not null
    references public.site_visits(id)
    on delete cascade,

  previous_status text,
  new_status text not null,

  previous_agent_id uuid
    references auth.users(id)
    on delete set null,

  new_agent_id uuid
    references auth.users(id)
    on delete set null,

  previous_scheduled_start_at timestamptz,
  new_scheduled_start_at timestamptz,

  change_type text not null default 'status_change'
    check (
      change_type in (
        'created',
        'status_change',
        'assignment',
        'reschedule',
        'confirmation',
        'check_in',
        'check_out',
        'completion',
        'cancellation',
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

create index site_visit_status_history_org_idx
  on public.site_visit_status_history(organization_id);

create index site_visit_status_history_visit_idx
  on public.site_visit_status_history(
    site_visit_id,
    changed_at desc
  );

create index site_visit_status_history_status_idx
  on public.site_visit_status_history(
    organization_id,
    new_status,
    changed_at desc
  );

-- =========================================================
-- 12. SITE-VISIT RESCHEDULE HISTORY
-- =========================================================

create table public.site_visit_reschedule_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  site_visit_id uuid not null
    references public.site_visits(id)
    on delete cascade,

  previous_start_at timestamptz not null,
  previous_end_at timestamptz,

  new_start_at timestamptz not null,
  new_end_at timestamptz,

  reason text,

  rescheduled_by uuid
    references auth.users(id)
    on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  rescheduled_at timestamptz not null default now(),

  constraint site_visit_reschedule_new_schedule_valid
    check (
      new_end_at is null
      or new_end_at >= new_start_at
    )
);

create index site_visit_reschedule_history_org_idx
  on public.site_visit_reschedule_history(organization_id);

create index site_visit_reschedule_history_visit_idx
  on public.site_visit_reschedule_history(
    site_visit_id,
    rescheduled_at desc
  );

-- =========================================================
-- 13. STATUS AND SCHEDULE HISTORY TRIGGER
-- =========================================================

create or replace function public.record_site_visit_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  detected_change_type text;
begin
  if tg_op = 'INSERT' then

    insert into public.site_visit_status_history (
      organization_id,
      site_visit_id,
      previous_status,
      new_status,
      previous_agent_id,
      new_agent_id,
      previous_scheduled_start_at,
      new_scheduled_start_at,
      change_type,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      null,
      new.status,
      null,
      new.assigned_agent_id,
      null,
      new.scheduled_start_at,
      'created',
      coalesce(new.created_by, auth.uid())
    );

    return new;
  end if;

  if new.scheduled_start_at
    is distinct from old.scheduled_start_at
    or new.scheduled_end_at
      is distinct from old.scheduled_end_at then

    insert into public.site_visit_reschedule_history (
      organization_id,
      site_visit_id,
      previous_start_at,
      previous_end_at,
      new_start_at,
      new_end_at,
      reason,
      rescheduled_by
    )
    values (
      new.organization_id,
      new.id,
      old.scheduled_start_at,
      old.scheduled_end_at,
      new.scheduled_start_at,
      new.scheduled_end_at,
      new.reschedule_reason,
      coalesce(new.updated_by, auth.uid())
    );

    new.reschedule_count :=
      coalesce(old.reschedule_count, 0) + 1;

  end if;

  if new.status is distinct from old.status
    or new.assigned_agent_id
      is distinct from old.assigned_agent_id
    or new.scheduled_start_at
      is distinct from old.scheduled_start_at
    or new.confirmation_status
      is distinct from old.confirmation_status then

    detected_change_type :=
      case
        when new.scheduled_start_at
          is distinct from old.scheduled_start_at
          then 'reschedule'

        when new.assigned_agent_id
          is distinct from old.assigned_agent_id
          then 'assignment'

        when new.confirmation_status
          is distinct from old.confirmation_status
          then 'confirmation'

        when new.status = 'checked_in'
          then 'check_in'

        when new.status = 'completed'
          then 'completion'

        when new.status = 'cancelled'
          then 'cancellation'

        else 'status_change'
      end;

    insert into public.site_visit_status_history (
      organization_id,
      site_visit_id,
      previous_status,
      new_status,
      previous_agent_id,
      new_agent_id,
      previous_scheduled_start_at,
      new_scheduled_start_at,
      change_type,
      change_reason,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      old.status,
      new.status,
      old.assigned_agent_id,
      new.assigned_agent_id,
      old.scheduled_start_at,
      new.scheduled_start_at,
      detected_change_type,
      coalesce(
        new.reschedule_reason,
        new.cancellation_reason
      ),
      coalesce(new.updated_by, auth.uid())
    );

  end if;

  return new;
end;
$$;

create trigger site_visits_record_history
before insert or update of
  status,
  assigned_agent_id,
  scheduled_start_at,
  scheduled_end_at,
  confirmation_status
on public.site_visits
for each row
execute function public.record_site_visit_history();

-- =========================================================
-- 14. CREATE LEAD ACTIVITY FOR VISIT EVENTS
-- =========================================================

create or replace function public.create_site_visit_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  generated_subject text;
  generated_description text;
  generated_activity_status text;
begin
  if tg_op = 'INSERT' then

    insert into public.lead_activities (
      organization_id,
      lead_id,
      activity_type,
      direction,
      activity_status,
      subject,
      description,
      started_at,
      performed_by,
      is_automated,
      metadata,
      created_by
    )
    values (
      new.organization_id,
      new.lead_id,
      'site_visit',
      'internal',
      'scheduled',
      'Site visit scheduled',
      concat(
        new.project_name,
        ' — ',
        new.scheduled_start_at
      ),
      new.scheduled_start_at,
      new.assigned_agent_id,
      new.is_automated,
      jsonb_build_object(
        'site_visit_id',
        new.id,
        'project_name',
        new.project_name,
        'visit_number',
        new.visit_number
      ),
      coalesce(new.created_by, auth.uid())
    );

    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  generated_subject :=
    case new.status
      when 'confirmed'
        then 'Site visit confirmed'
      when 'checked_in'
        then 'Customer checked in'
      when 'in_progress'
        then 'Site visit started'
      when 'completed'
        then 'Site visit completed'
      when 'cancelled'
        then 'Site visit cancelled'
      when 'no_show'
        then 'Site visit marked no-show'
      when 'rescheduled'
        then 'Site visit rescheduled'
      else 'Site visit updated'
    end;

  generated_description :=
    case
      when new.status = 'completed'
        then coalesce(
          new.outcome_summary,
          new.agent_notes,
          'Site visit completed'
        )
      when new.status = 'cancelled'
        then coalesce(
          new.cancellation_reason,
          'Site visit cancelled'
        )
      when new.status = 'no_show'
        then concat(
          'No-show party: ',
          coalesce(new.no_show_party, 'unknown')
        )
      else concat(
        new.project_name,
        ' — status changed to ',
        new.status
      )
    end;

  generated_activity_status :=
    case
      when new.status = 'cancelled'
        then 'cancelled'
      when new.status = 'no_show'
        then 'no_response'
      when new.status = 'completed'
        then 'completed'
      when new.status = 'in_progress'
        then 'in_progress'
      else 'scheduled'
    end;

  insert into public.lead_activities (
    organization_id,
    lead_id,
    activity_type,
    direction,
    activity_status,
    subject,
    description,
    outcome,
    started_at,
    completed_at,
    performed_by,
    is_automated,
    metadata,
    created_by
  )
  values (
    new.organization_id,
    new.lead_id,
    'site_visit',
    'internal',
    generated_activity_status,
    generated_subject,
    generated_description,
    new.outcome,
    coalesce(
      new.visit_started_at,
      new.scheduled_start_at
    ),
    new.visit_completed_at,
    new.assigned_agent_id,
    new.is_automated,
    jsonb_build_object(
      'site_visit_id',
      new.id,
      'project_name',
      new.project_name,
      'visit_status',
      new.status
    ),
    coalesce(new.updated_by, auth.uid())
  );

  return new;
end;
$$;

create trigger site_visits_create_activity
after insert or update of status
on public.site_visits
for each row
execute function public.create_site_visit_activity();

-- =========================================================
-- 15. SYNCHRONIZE LEAD LIFECYCLE
-- =========================================================

create or replace function public.sync_lead_from_site_visit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    update public.leads
    set
      lead_status = case
        when lead_status in (
          'booked',
          'lost',
          'archived'
        )
          then lead_status
        else 'site_visit_planned'
      end,
      lifecycle_stage = case
        when lifecycle_stage = 'customer'
          then lifecycle_stage
        else 'opportunity'
      end,
      updated_at = now()
    where id = new.lead_id
      and organization_id = new.organization_id
      and deleted_at is null;

    return new;
  end if;

  if new.status is not distinct from old.status then
    return new;
  end if;

  if new.status = 'completed' then

    update public.leads
    set
      lead_status = case
        when lead_status in (
          'booked',
          'lost',
          'archived'
        )
          then lead_status
        else 'site_visit_completed'
      end,

      lead_temperature = case
        when new.outcome in (
          'highly_interested',
          'negotiation_started',
          'booking_expected'
        )
          then 'hot'

        when new.outcome in (
          'interested',
          'considering',
          'follow_up_required'
        )
          then coalesce(
            lead_temperature,
            'warm'
          )

        when new.outcome in (
          'not_interested',
          'budget_mismatch',
          'location_mismatch',
          'unit_mismatch'
        )
          then 'cold'

        else lead_temperature
      end,

      qualification_score =
        case
          when new.probability_of_booking is not null
            then new.probability_of_booking
          else qualification_score
        end,

      updated_at = now()

    where id = new.lead_id
      and organization_id = new.organization_id
      and deleted_at is null;

  elsif new.status in (
    'scheduled',
    'confirmed',
    'rescheduled'
  ) then

    update public.leads
    set
      lead_status = case
        when lead_status in (
          'booked',
          'lost',
          'archived'
        )
          then lead_status
        else 'site_visit_planned'
      end,
      updated_at = now()
    where id = new.lead_id
      and organization_id = new.organization_id
      and deleted_at is null;

  end if;

  return new;
end;
$$;

create trigger site_visits_sync_lead
after insert or update of status
on public.site_visits
for each row
execute function public.sync_lead_from_site_visit();

-- =========================================================
-- 16. CHECK-IN FUNCTION
-- =========================================================

create or replace function public.check_in_site_visit(
  requested_site_visit_id uuid,
  requested_party text,
  requested_latitude numeric default null,
  requested_longitude numeric default null,
  requested_method text default 'manual'
)
returns public.site_visits
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_visit public.site_visits;
begin
  select *
  into target_visit
  from public.site_visits
  where id = requested_site_visit_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Site visit not found';
  end if;

  if not public.has_organization_permission(
    target_visit.organization_id,
    'site_visits.check_in'
  ) then
    raise exception 'Permission denied';
  end if;

  if requested_party not in (
    'customer',
    'agent'
  ) then
    raise exception
      'Check-in party must be customer or agent';
  end if;

  if requested_latitude is not null
    and (
      requested_latitude < -90
      or requested_latitude > 90
    ) then
    raise exception 'Invalid latitude';
  end if;

  if requested_longitude is not null
    and (
      requested_longitude < -180
      or requested_longitude > 180
    ) then
    raise exception 'Invalid longitude';
  end if;

  update public.site_visits
  set
    customer_checked_in_at = case
      when requested_party = 'customer'
        then coalesce(
          customer_checked_in_at,
          now()
        )
      else customer_checked_in_at
    end,

    agent_checked_in_at = case
      when requested_party = 'agent'
        then coalesce(
          agent_checked_in_at,
          now()
        )
      else agent_checked_in_at
    end,

    customer_check_in_latitude = case
      when requested_party = 'customer'
        then requested_latitude
      else customer_check_in_latitude
    end,

    customer_check_in_longitude = case
      when requested_party = 'customer'
        then requested_longitude
      else customer_check_in_longitude
    end,

    agent_check_in_latitude = case
      when requested_party = 'agent'
        then requested_latitude
      else agent_check_in_latitude
    end,

    agent_check_in_longitude = case
      when requested_party = 'agent'
        then requested_longitude
      else agent_check_in_longitude
    end,

    check_in_method = requested_method,

    status = case
      when status in (
        'scheduled',
        'confirmed',
        'agent_en_route',
        'customer_en_route'
      )
        then 'checked_in'
      else status
    end,

    updated_by = auth.uid(),
    updated_at = now()

  where id = requested_site_visit_id

  returning *
  into target_visit;

  return target_visit;
end;
$$;

revoke all
on function public.check_in_site_visit(
  uuid,
  text,
  numeric,
  numeric,
  text
)
from public;

grant execute
on function public.check_in_site_visit(
  uuid,
  text,
  numeric,
  numeric,
  text
)
to authenticated;

-- =========================================================
-- 17. CHECK-OUT FUNCTION
-- =========================================================

create or replace function public.check_out_site_visit(
  requested_site_visit_id uuid,
  requested_party text
)
returns public.site_visits
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_visit public.site_visits;
begin
  select *
  into target_visit
  from public.site_visits
  where id = requested_site_visit_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Site visit not found';
  end if;

  if not public.has_organization_permission(
    target_visit.organization_id,
    'site_visits.check_in'
  ) then
    raise exception 'Permission denied';
  end if;

  if requested_party not in (
    'customer',
    'agent'
  ) then
    raise exception
      'Check-out party must be customer or agent';
  end if;

  update public.site_visits
  set
    customer_checked_out_at = case
      when requested_party = 'customer'
        then coalesce(
          customer_checked_out_at,
          now()
        )
      else customer_checked_out_at
    end,

    agent_checked_out_at = case
      when requested_party = 'agent'
        then coalesce(
          agent_checked_out_at,
          now()
        )
      else agent_checked_out_at
    end,

    updated_by = auth.uid(),
    updated_at = now()

  where id = requested_site_visit_id

  returning *
  into target_visit;

  return target_visit;
end;
$$;

revoke all
on function public.check_out_site_visit(uuid, text)
from public;

grant execute
on function public.check_out_site_visit(uuid, text)
to authenticated;

-- =========================================================
-- 18. COMPLETE SITE VISIT FUNCTION
-- =========================================================

create or replace function public.complete_site_visit(
  requested_site_visit_id uuid,
  requested_outcome text,
  requested_outcome_summary text default null,
  requested_probability_of_booking numeric default null,
  requested_agent_notes text default null
)
returns public.site_visits
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_visit public.site_visits;
begin
  select *
  into target_visit
  from public.site_visits
  where id = requested_site_visit_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Site visit not found';
  end if;

  if not public.has_organization_permission(
    target_visit.organization_id,
    'site_visits.complete'
  ) then
    raise exception 'Permission denied';
  end if;

  if requested_probability_of_booking is not null
    and (
      requested_probability_of_booking < 0
      or requested_probability_of_booking > 100
    ) then
    raise exception
      'Probability of booking must be between 0 and 100';
  end if;

  update public.site_visits
  set
    status = 'completed',
    outcome = requested_outcome,
    outcome_summary = requested_outcome_summary,
    probability_of_booking =
      requested_probability_of_booking,
    agent_notes = requested_agent_notes,
    visit_completed_at =
      coalesce(visit_completed_at, now()),
    updated_by = auth.uid(),
    updated_at = now()

  where id = requested_site_visit_id

  returning *
  into target_visit;

  return target_visit;
end;
$$;

revoke all
on function public.complete_site_visit(
  uuid,
  text,
  text,
  numeric,
  text
)
from public;

grant execute
on function public.complete_site_visit(
  uuid,
  text,
  text,
  numeric,
  text
)
to authenticated;

-- =========================================================
-- 19. SITE-VISIT DASHBOARD
-- =========================================================

create or replace function public.get_site_visit_dashboard(
  requested_organization_id uuid,
  requested_agent_id uuid default null
)
returns table (
  total_upcoming bigint,
  scheduled_today bigint,
  completed_today bigint,
  cancelled_today bigint,
  no_show_today bigint,
  highly_interested bigint,
  booking_expected bigint,
  unassigned bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_organization_permission(
    requested_organization_id,
    'site_visits.view'
  ) then
    raise exception 'Permission denied';
  end if;

  return query
  select
    count(*) filter (
      where sv.status in (
        'scheduled',
        'confirmed',
        'agent_en_route',
        'customer_en_route',
        'checked_in',
        'in_progress'
      )
      and sv.scheduled_start_at >= now()
    ) as total_upcoming,

    count(*) filter (
      where sv.scheduled_start_at >=
        date_trunc('day', now())
      and sv.scheduled_start_at <
        date_trunc('day', now()) + interval '1 day'
      and sv.status not in (
        'cancelled',
        'failed'
      )
    ) as scheduled_today,

    count(*) filter (
      where sv.status = 'completed'
      and sv.visit_completed_at >=
        date_trunc('day', now())
      and sv.visit_completed_at <
        date_trunc('day', now()) + interval '1 day'
    ) as completed_today,

    count(*) filter (
      where sv.status = 'cancelled'
      and sv.cancelled_at >=
        date_trunc('day', now())
      and sv.cancelled_at <
        date_trunc('day', now()) + interval '1 day'
    ) as cancelled_today,

    count(*) filter (
      where sv.status = 'no_show'
      and sv.scheduled_start_at >=
        date_trunc('day', now())
      and sv.scheduled_start_at <
        date_trunc('day', now()) + interval '1 day'
    ) as no_show_today,

    count(*) filter (
      where sv.outcome = 'highly_interested'
    ) as highly_interested,

    count(*) filter (
      where sv.outcome = 'booking_expected'
    ) as booking_expected,

    count(*) filter (
      where sv.assigned_agent_id is null
      and sv.status in (
        'draft',
        'scheduled',
        'confirmed'
      )
    ) as unassigned

  from public.site_visits sv

  where sv.organization_id =
    requested_organization_id

    and sv.deleted_at is null

    and (
      requested_agent_id is null
      or sv.assigned_agent_id =
        requested_agent_id
    );
end;
$$;

revoke all
on function public.get_site_visit_dashboard(uuid, uuid)
from public;

grant execute
on function public.get_site_visit_dashboard(uuid, uuid)
to authenticated;

-- =========================================================
-- 20. ENABLE RLS ON HISTORY TABLES
-- =========================================================

alter table public.site_visit_status_history
  enable row level security;

alter table public.site_visit_reschedule_history
  enable row level security;

-- =========================================================
-- 21. SITE-VISIT RLS POLICIES
-- =========================================================

create policy "Authorized users can view site visits"
on public.site_visits
for select
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'site_visits.view'
  )
  and (
    public.has_organization_permission(
      organization_id,
      'site_visits.view_all'
    )
    or assigned_agent_id = (select auth.uid())
    or created_by = (select auth.uid())
    or coordinator_id = (select auth.uid())
  )
);

create policy "Authorized users can create site visits"
on public.site_visits
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'site_visits.create'
  )
);

create policy "Authorized users can update site visits"
on public.site_visits
for update
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'site_visits.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'site_visits.update'
  )
);

create policy "Authorized users can delete site visits"
on public.site_visits
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'site_visits.delete'
  )
);

-- =========================================================
-- 22. ATTENDEE RLS POLICIES
-- =========================================================

create policy "Authorized users can view visit attendees"
on public.site_visit_attendees
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'site_visits.view'
  )
);

create policy "Authorized users can create visit attendees"
on public.site_visit_attendees
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'site_visits.update'
  )
);

create policy "Authorized users can update visit attendees"
on public.site_visit_attendees
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'site_visits.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'site_visits.update'
  )
);

create policy "Authorized users can delete visit attendees"
on public.site_visit_attendees
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'site_visits.delete'
  )
);

-- =========================================================
-- 23. HISTORY RLS POLICIES
-- =========================================================

create policy "Authorized users can view visit history"
on public.site_visit_status_history
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'site_visits.view'
  )
);

create policy "Authorized users can view reschedule history"
on public.site_visit_reschedule_history
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'site_visits.view'
  )
);

commit;