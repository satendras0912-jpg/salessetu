-- =========================================================
-- SalesSetu Enterprise
-- Migration: 003_leads
-- Purpose: Multi-tenant Lead Engine foundation
-- =========================================================

begin;

-- =========================================================
-- 1. LEAD SOURCES
-- =========================================================

create table public.lead_sources (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  name text not null,
  code text not null,

  source_type text not null
    check (
      source_type in (
        'website',
        'landing_page',
        'meta_ads',
        'google_ads',
        'whatsapp',
        'phone_call',
        'walk_in',
        'referral',
        'partner',
        'import',
        'api',
        'manual',
        'other'
      )
    ),

  provider text,
  external_source_id text,

  is_active boolean not null default true,

  settings jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,

  created_by uuid
    references auth.users(id)
    on delete set null,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint lead_sources_org_code_unique
    unique (organization_id, code)
);

create index lead_sources_organization_idx
  on public.lead_sources(organization_id);

create index lead_sources_type_idx
  on public.lead_sources(source_type);

create index lead_sources_active_idx
  on public.lead_sources(organization_id, is_active);

create trigger lead_sources_set_updated_at
before update on public.lead_sources
for each row
execute function public.set_updated_at();

-- =========================================================
-- 2. LEADS
-- =========================================================

create table public.leads (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_source_id uuid
    references public.lead_sources(id)
    on delete set null,

  -- -------------------------------------------------------
  -- Contact identity
  -- -------------------------------------------------------

  first_name text,
  last_name text,
  full_name text,

  phone text,
  normalized_phone text,

  alternate_phone text,
  normalized_alternate_phone text,

  email text,
  normalized_email text,

  whatsapp_number text,
  normalized_whatsapp_number text,

  country_code text not null default '+91',

  -- -------------------------------------------------------
  -- Lead lifecycle
  -- -------------------------------------------------------

  lead_status text not null default 'new'
    check (
      lead_status in (
        'new',
        'contact_attempted',
        'connected',
        'qualified',
        'unqualified',
        'nurturing',
        'site_visit_planned',
        'site_visit_completed',
        'negotiation',
        'booked',
        'lost',
        'duplicate',
        'invalid',
        'archived'
      )
    ),

  lead_temperature text
    check (
      lead_temperature is null
      or lead_temperature in (
        'hot',
        'warm',
        'cold'
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

  lifecycle_stage text not null default 'lead'
    check (
      lifecycle_stage in (
        'lead',
        'prospect',
        'opportunity',
        'customer',
        'lost'
      )
    ),

  -- -------------------------------------------------------
  -- Real-estate requirements
  -- -------------------------------------------------------

  property_type text,
  transaction_type text
    check (
      transaction_type is null
      or transaction_type in (
        'buy',
        'rent',
        'lease',
        'invest'
      )
    ),

  preferred_project text,
  preferred_location text,
  preferred_city text,

  unit_type text,
  bedrooms numeric(4,1),

  budget_min numeric(15,2),
  budget_max numeric(15,2),
  budget_currency text not null default 'INR',

  possession_timeline text,
  buying_timeline text,

  purpose text
    check (
      purpose is null
      or purpose in (
        'self_use',
        'investment',
        'rental_income',
        'business',
        'other'
      )
    ),

  financing_required boolean,
  loan_status text,

  -- -------------------------------------------------------
  -- Lead qualification
  -- -------------------------------------------------------

  qualification_status text not null default 'pending'
    check (
      qualification_status in (
        'pending',
        'in_progress',
        'qualified',
        'partially_qualified',
        'unqualified',
        'failed',
        'manual_review'
      )
    ),

  qualification_score numeric(5,2)
    check (
      qualification_score is null
      or (
        qualification_score >= 0
        and qualification_score <= 100
      )
    ),

  qualification_reason text,
  qualification_summary text,

  ai_qualified boolean not null default false,
  ai_provider text,
  ai_model text,
  ai_qualification_version text,
  ai_qualified_at timestamptz,

  -- -------------------------------------------------------
  -- Duplicate and fake-lead detection
  -- -------------------------------------------------------

  duplicate_status text not null default 'unchecked'
    check (
      duplicate_status in (
        'unchecked',
        'unique',
        'possible_duplicate',
        'confirmed_duplicate',
        'merged',
        'ignored'
      )
    ),

  duplicate_of_lead_id uuid
    references public.leads(id)
    on delete set null,

  duplicate_confidence numeric(5,2)
    check (
      duplicate_confidence is null
      or (
        duplicate_confidence >= 0
        and duplicate_confidence <= 100
      )
    ),

  fake_status text not null default 'unchecked'
    check (
      fake_status in (
        'unchecked',
        'valid',
        'suspicious',
        'fake',
        'manual_review'
      )
    ),

  fake_score numeric(5,2)
    check (
      fake_score is null
      or (
        fake_score >= 0
        and fake_score <= 100
      )
    ),

  fake_reason text,

  phone_verified boolean not null default false,
  email_verified boolean not null default false,
  whatsapp_verified boolean not null default false,

  -- -------------------------------------------------------
  -- Consent and communication
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

  consent_source text,
  consent_at timestamptz,

  do_not_call boolean not null default false,
  do_not_email boolean not null default false,
  do_not_whatsapp boolean not null default false,

  preferred_language text not null default 'hi-IN',
  preferred_contact_channel text
    check (
      preferred_contact_channel is null
      or preferred_contact_channel in (
        'phone',
        'whatsapp',
        'email',
        'sms'
      )
    ),

  -- -------------------------------------------------------
  -- Attribution and UTM tracking
  -- -------------------------------------------------------

  campaign_id text,
  campaign_name text,

  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_term text,
  utm_content text,

  ad_id text,
  adset_id text,
  form_id text,

  landing_page_url text,
  referrer_url text,

  fbclid text,
  gclid text,

  visitor_session_id text,

  -- -------------------------------------------------------
  -- External integration identifiers
  -- -------------------------------------------------------

  external_lead_id text,
  external_provider text,

  meta_lead_id text,
  google_lead_id text,
  whatsapp_contact_id text,

  -- -------------------------------------------------------
  -- Assignment
  -- -------------------------------------------------------

  assigned_to uuid
    references auth.users(id)
    on delete set null,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assigned_at timestamptz,

  assignment_status text not null default 'unassigned'
    check (
      assignment_status in (
        'unassigned',
        'assigned',
        'accepted',
        'rejected',
        'reassigned'
      )
    ),

  -- -------------------------------------------------------
  -- Operational timestamps
  -- -------------------------------------------------------

  first_contacted_at timestamptz,
  last_contacted_at timestamptz,
  next_follow_up_at timestamptz,

  qualified_at timestamptz,
  converted_at timestamptz,
  lost_at timestamptz,

  lost_reason text,

  -- -------------------------------------------------------
  -- Free-form information
  -- -------------------------------------------------------

  notes text,
  tags text[] not null default '{}'::text[],

  custom_fields jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,

  -- -------------------------------------------------------
  -- Audit and soft delete
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

  constraint leads_budget_range_valid
    check (
      budget_min is null
      or budget_max is null
      or budget_max >= budget_min
    ),

  constraint leads_not_duplicate_of_self
    check (
      duplicate_of_lead_id is null
      or duplicate_of_lead_id <> id
    )
);

-- =========================================================
-- 3. LEAD INDEXES
-- =========================================================

create index leads_organization_idx
  on public.leads(organization_id);

create index leads_source_idx
  on public.leads(lead_source_id);

create index leads_status_idx
  on public.leads(organization_id, lead_status);

create index leads_temperature_idx
  on public.leads(organization_id, lead_temperature);

create index leads_priority_idx
  on public.leads(organization_id, priority);

create index leads_qualification_idx
  on public.leads(
    organization_id,
    qualification_status
  );

create index leads_assignment_idx
  on public.leads(
    organization_id,
    assigned_to
  );

create index leads_next_follow_up_idx
  on public.leads(
    organization_id,
    next_follow_up_at
  )
  where deleted_at is null;

create index leads_created_at_idx
  on public.leads(
    organization_id,
    created_at desc
  );

create index leads_normalized_phone_idx
  on public.leads(
    organization_id,
    normalized_phone
  )
  where normalized_phone is not null
    and deleted_at is null;

create index leads_normalized_email_idx
  on public.leads(
    organization_id,
    normalized_email
  )
  where normalized_email is not null
    and deleted_at is null;

create index leads_external_id_idx
  on public.leads(
    organization_id,
    external_provider,
    external_lead_id
  )
  where external_lead_id is not null;

create index leads_duplicate_status_idx
  on public.leads(
    organization_id,
    duplicate_status
  );

create index leads_fake_status_idx
  on public.leads(
    organization_id,
    fake_status
  );

create index leads_active_idx
  on public.leads(
    organization_id,
    lead_status,
    created_at desc
  )
  where deleted_at is null;

create index leads_tags_gin_idx
  on public.leads
  using gin(tags);

create index leads_custom_fields_gin_idx
  on public.leads
  using gin(custom_fields);

-- =========================================================
-- 4. UPDATED-AT TRIGGER
-- =========================================================

create trigger leads_set_updated_at
before update on public.leads
for each row
execute function public.set_updated_at();

-- =========================================================
-- 5. CONTACT NORMALIZATION FUNCTION
-- =========================================================

create or replace function public.normalize_phone(
  input_phone text
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select nullif(
    regexp_replace(
      coalesce(input_phone, ''),
      '[^0-9]',
      '',
      'g'
    ),
    ''
  );
$$;

create or replace function public.normalize_email(
  input_email text
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select nullif(
    lower(trim(coalesce(input_email, ''))),
    ''
  );
$$;

-- =========================================================
-- 6. AUTOMATIC CONTACT NORMALIZATION
-- =========================================================

create or replace function public.set_lead_normalized_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.normalized_phone =
    public.normalize_phone(new.phone);

  new.normalized_alternate_phone =
    public.normalize_phone(new.alternate_phone);

  new.normalized_whatsapp_number =
    public.normalize_phone(new.whatsapp_number);

  new.normalized_email =
    public.normalize_email(new.email);

  if new.full_name is null
    or trim(new.full_name) = '' then

    new.full_name = nullif(
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

  return new;
end;
$$;

create trigger leads_set_normalized_fields
before insert or update of
  phone,
  alternate_phone,
  whatsapp_number,
  email,
  first_name,
  last_name,
  full_name
on public.leads
for each row
execute function public.set_lead_normalized_fields();

-- =========================================================
-- 7. ENABLE RLS
-- Policies will be added in Part 2.
-- =========================================================

alter table public.lead_sources
  enable row level security;

alter table public.leads
  enable row level security;

  -- =========================================================
-- 8. ADDITIONAL LEAD PERMISSIONS
-- =========================================================

insert into public.permissions (
  module,
  action,
  code,
  description
)
values
  (
    'leads',
    'qualify',
    'leads.qualify',
    'Qualify leads manually or through AI'
  ),
  (
    'leads',
    'merge',
    'leads.merge',
    'Merge duplicate lead records'
  ),
  (
    'leads',
    'manage_sources',
    'leads.manage_sources',
    'Create and manage lead sources'
  )
on conflict (code) do nothing;

-- Organization and platform administrators receive
-- all newly added lead permissions.

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
  and p.code in (
    'leads.qualify',
    'leads.merge',
    'leads.manage_sources'
  )
on conflict (role_id, permission_id) do nothing;

-- Sales managers can qualify and merge leads.

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
    'leads.qualify',
    'leads.merge',
    'leads.manage_sources'
  )
where r.code = 'sales_manager'
on conflict (role_id, permission_id) do nothing;

-- Sales agents can qualify leads but cannot merge them
-- or manage lead-source configuration.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code = 'leads.qualify'
where r.code = 'sales_agent'
on conflict (role_id, permission_id) do nothing;

-- Marketing managers can manage lead sources.

insert into public.role_permissions (
  role_id,
  permission_id
)
select
  r.id,
  p.id
from public.roles r
join public.permissions p
  on p.code = 'leads.manage_sources'
where r.code = 'marketing_manager'
on conflict (role_id, permission_id) do nothing;

-- =========================================================
-- 9. LEAD STATUS HISTORY
-- =========================================================

create table public.lead_status_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  previous_status text,

  new_status text not null,

  previous_lifecycle_stage text,

  new_lifecycle_stage text,

  previous_temperature text,

  new_temperature text,

  change_reason text,

  changed_by uuid
    references auth.users(id)
    on delete set null,

  metadata jsonb not null default '{}'::jsonb,

  changed_at timestamptz not null default now()
);

create index lead_status_history_organization_idx
  on public.lead_status_history(organization_id);

create index lead_status_history_lead_idx
  on public.lead_status_history(
    lead_id,
    changed_at desc
  );

create index lead_status_history_status_idx
  on public.lead_status_history(
    organization_id,
    new_status,
    changed_at desc
  );

-- =========================================================
-- 10. LEAD ASSIGNMENT HISTORY
-- =========================================================

create table public.lead_assignment_history (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  previous_assignee_id uuid
    references auth.users(id)
    on delete set null,

  new_assignee_id uuid
    references auth.users(id)
    on delete set null,

  assigned_by uuid
    references auth.users(id)
    on delete set null,

  assignment_type text not null default 'manual'
    check (
      assignment_type in (
        'manual',
        'automatic',
        'round_robin',
        'rule_based',
        'ai_recommended',
        'reassignment',
        'unassignment'
      )
    ),

  assignment_reason text,

  previous_assignment_status text,

  new_assignment_status text,

  metadata jsonb not null default '{}'::jsonb,

  assigned_at timestamptz not null default now()
);

create index lead_assignment_history_organization_idx
  on public.lead_assignment_history(organization_id);

create index lead_assignment_history_lead_idx
  on public.lead_assignment_history(
    lead_id,
    assigned_at desc
  );

create index lead_assignment_history_assignee_idx
  on public.lead_assignment_history(
    organization_id,
    new_assignee_id,
    assigned_at desc
  );

-- =========================================================
-- 11. LEAD DUPLICATE MATCHES
-- Stores potential and confirmed duplicate relationships.
-- =========================================================

create table public.lead_duplicate_matches (
  id uuid primary key default gen_random_uuid(),

  organization_id uuid not null
    references public.organizations(id)
    on delete cascade,

  source_lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  matched_lead_id uuid not null
    references public.leads(id)
    on delete cascade,

  match_type text not null
    check (
      match_type in (
        'phone',
        'alternate_phone',
        'whatsapp',
        'email',
        'external_id',
        'multiple_fields',
        'manual'
      )
    ),

  confidence_score numeric(5,2) not null
    check (
      confidence_score >= 0
      and confidence_score <= 100
    ),

  matched_fields text[] not null default '{}'::text[],

  match_status text not null default 'possible'
    check (
      match_status in (
        'possible',
        'confirmed',
        'rejected',
        'merged',
        'ignored'
      )
    ),

  reviewed_by uuid
    references auth.users(id)
    on delete set null,

  reviewed_at timestamptz,

  review_notes text,

  metadata jsonb not null default '{}'::jsonb,

  created_at timestamptz not null default now(),

  constraint lead_duplicate_matches_not_self
    check (
      source_lead_id <> matched_lead_id
    ),

  constraint lead_duplicate_matches_unique_pair
    unique (
      source_lead_id,
      matched_lead_id
    )
);

create index lead_duplicate_matches_organization_idx
  on public.lead_duplicate_matches(organization_id);

create index lead_duplicate_matches_source_idx
  on public.lead_duplicate_matches(source_lead_id);

create index lead_duplicate_matches_matched_idx
  on public.lead_duplicate_matches(matched_lead_id);

create index lead_duplicate_matches_status_idx
  on public.lead_duplicate_matches(
    organization_id,
    match_status
  );

-- =========================================================
-- 12. ASSIGNEE ORGANIZATION VALIDATION
-- =========================================================

create or replace function public.validate_lead_assignee()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.assigned_to is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.organization_members om
    where om.organization_id = new.organization_id
      and om.user_id = new.assigned_to
      and om.membership_status = 'active'
  ) then
    raise exception
      'Assigned user must be an active member of the lead organization';
  end if;

  return new;
end;
$$;

create trigger leads_validate_assignee
before insert or update of
  organization_id,
  assigned_to
on public.leads
for each row
execute function public.validate_lead_assignee();

-- =========================================================
-- 13. LEAD-SOURCE ORGANIZATION VALIDATION
-- Ensures that a lead cannot use another organization's
-- lead source.
-- =========================================================

create or replace function public.validate_lead_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.lead_source_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.lead_sources ls
    where ls.id = new.lead_source_id
      and ls.organization_id = new.organization_id
      and ls.is_active = true
  ) then
    raise exception
      'Lead source must belong to the lead organization and be active';
  end if;

  return new;
end;
$$;

create trigger leads_validate_source
before insert or update of
  organization_id,
  lead_source_id
on public.leads
for each row
execute function public.validate_lead_source();

-- =========================================================
-- 14. AUTOMATIC ASSIGNMENT FIELDS
-- =========================================================

create or replace function public.set_lead_assignment_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    if new.assigned_to is not null then
      new.assignment_status :=
        case
          when new.assignment_status = 'unassigned'
            then 'assigned'
          else new.assignment_status
        end;

      new.assigned_at :=
        coalesce(new.assigned_at, now());

      new.assigned_by :=
        coalesce(new.assigned_by, auth.uid());
    end if;

    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to then

    if new.assigned_to is null then
      new.assignment_status = 'unassigned';
      new.assigned_at = null;
    else
      new.assignment_status = 'reassigned';
      new.assigned_at = now();
      new.assigned_by =
        coalesce(new.assigned_by, auth.uid());
    end if;

  end if;

  return new;
end;
$$;

create trigger leads_set_assignment_fields
before insert or update of assigned_to
on public.leads
for each row
execute function public.set_lead_assignment_fields();

-- =========================================================
-- 15. STATUS HISTORY TRIGGER
-- =========================================================

create or replace function public.record_lead_status_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    insert into public.lead_status_history (
      organization_id,
      lead_id,
      previous_status,
      new_status,
      previous_lifecycle_stage,
      new_lifecycle_stage,
      previous_temperature,
      new_temperature,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      null,
      new.lead_status,
      null,
      new.lifecycle_stage,
      null,
      new.lead_temperature,
      coalesce(new.created_by, auth.uid())
    );

    return new;
  end if;

  if new.lead_status is distinct from old.lead_status
    or new.lifecycle_stage
      is distinct from old.lifecycle_stage
    or new.lead_temperature
      is distinct from old.lead_temperature then

    insert into public.lead_status_history (
      organization_id,
      lead_id,
      previous_status,
      new_status,
      previous_lifecycle_stage,
      new_lifecycle_stage,
      previous_temperature,
      new_temperature,
      changed_by
    )
    values (
      new.organization_id,
      new.id,
      old.lead_status,
      new.lead_status,
      old.lifecycle_stage,
      new.lifecycle_stage,
      old.lead_temperature,
      new.lead_temperature,
      coalesce(new.updated_by, auth.uid())
    );

  end if;

  return new;
end;
$$;

create trigger leads_record_status_history
after insert or update of
  lead_status,
  lifecycle_stage,
  lead_temperature
on public.leads
for each row
execute function public.record_lead_status_history();

-- =========================================================
-- 16. ASSIGNMENT HISTORY TRIGGER
-- =========================================================

create or replace function public.record_lead_assignment_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then

    if new.assigned_to is not null then

      insert into public.lead_assignment_history (
        organization_id,
        lead_id,
        previous_assignee_id,
        new_assignee_id,
        assigned_by,
        assignment_type,
        previous_assignment_status,
        new_assignment_status
      )
      values (
        new.organization_id,
        new.id,
        null,
        new.assigned_to,
        coalesce(new.assigned_by, auth.uid()),
        'manual',
        null,
        new.assignment_status
      );

    end if;

    return new;
  end if;

  if new.assigned_to is distinct from old.assigned_to then

    insert into public.lead_assignment_history (
      organization_id,
      lead_id,
      previous_assignee_id,
      new_assignee_id,
      assigned_by,
      assignment_type,
      previous_assignment_status,
      new_assignment_status
    )
    values (
      new.organization_id,
      new.id,
      old.assigned_to,
      new.assigned_to,
      coalesce(new.assigned_by, auth.uid()),
      case
        when new.assigned_to is null
          then 'unassignment'
        when old.assigned_to is null
          then 'manual'
        else 'reassignment'
      end,
      old.assignment_status,
      new.assignment_status
    );

  end if;

  return new;
end;
$$;

create trigger leads_record_assignment_history
after insert or update of assigned_to
on public.leads
for each row
execute function public.record_lead_assignment_history();

-- =========================================================
-- 17. DUPLICATE MATCHING FUNCTION
-- Returns potential duplicates visible within the
-- requested organization.
-- =========================================================

create or replace function public.find_lead_duplicates(
  requested_organization_id uuid,
  requested_lead_id uuid default null,
  requested_phone text default null,
  requested_email text default null,
  requested_whatsapp text default null,
  requested_external_provider text default null,
  requested_external_lead_id text default null
)
returns table (
  lead_id uuid,
  full_name text,
  normalized_phone text,
  normalized_email text,
  normalized_whatsapp_number text,
  match_confidence numeric,
  matched_fields text[]
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_organization_permission(
    requested_organization_id,
    'leads.view'
  ) then
    raise exception 'Permission denied';
  end if;

  return query
  with normalized_inputs as (
    select
      public.normalize_phone(requested_phone)
        as phone_value,

      public.normalize_email(requested_email)
        as email_value,

      public.normalize_phone(requested_whatsapp)
        as whatsapp_value
  ),

  candidates as (
    select
      l.id,
      l.full_name,
      l.normalized_phone,
      l.normalized_email,
      l.normalized_whatsapp_number,

      array_remove(
        array[
          case
            when ni.phone_value is not null
              and l.normalized_phone = ni.phone_value
              then 'phone'
          end,

          case
            when ni.email_value is not null
              and l.normalized_email = ni.email_value
              then 'email'
          end,

          case
            when ni.whatsapp_value is not null
              and l.normalized_whatsapp_number =
                ni.whatsapp_value
              then 'whatsapp'
          end,

          case
            when requested_external_lead_id is not null
              and l.external_lead_id =
                requested_external_lead_id
              and l.external_provider is not distinct from
                requested_external_provider
              then 'external_id'
          end
        ],
        null
      ) as fields

    from public.leads l
    cross join normalized_inputs ni

    where l.organization_id =
      requested_organization_id

      and l.deleted_at is null

      and (
        requested_lead_id is null
        or l.id <> requested_lead_id
      )

      and (
        (
          ni.phone_value is not null
          and l.normalized_phone = ni.phone_value
        )
        or (
          ni.email_value is not null
          and l.normalized_email = ni.email_value
        )
        or (
          ni.whatsapp_value is not null
          and l.normalized_whatsapp_number =
            ni.whatsapp_value
        )
        or (
          requested_external_lead_id is not null
          and l.external_lead_id =
            requested_external_lead_id
          and l.external_provider is not distinct from
            requested_external_provider
        )
      )
  )

  select
    c.id,
    c.full_name,
    c.normalized_phone,
    c.normalized_email,
    c.normalized_whatsapp_number,

    least(
      100::numeric,
      case
        when cardinality(c.fields) >= 2
          then 100::numeric
        when 'external_id' = any(c.fields)
          then 100::numeric
        when 'phone' = any(c.fields)
          then 90::numeric
        when 'whatsapp' = any(c.fields)
          then 90::numeric
        when 'email' = any(c.fields)
          then 80::numeric
        else 50::numeric
      end
    ) as match_confidence,

    c.fields

  from candidates c
  order by match_confidence desc;
end;
$$;

revoke all
on function public.find_lead_duplicates(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text
)
from public;

grant execute
on function public.find_lead_duplicates(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text
)
to authenticated;

-- =========================================================
-- 18. ENABLE RLS ON HISTORY AND MATCH TABLES
-- =========================================================

alter table public.lead_status_history
  enable row level security;

alter table public.lead_assignment_history
  enable row level security;

alter table public.lead_duplicate_matches
  enable row level security;

-- =========================================================
-- 19. LEAD-SOURCE RLS POLICIES
-- =========================================================

create policy "Members can view lead sources"
on public.lead_sources
for select
to authenticated
using (
  public.is_organization_member(organization_id)
);

create policy "Authorized users can create lead sources"
on public.lead_sources
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'leads.manage_sources'
  )
);

create policy "Authorized users can update lead sources"
on public.lead_sources
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.manage_sources'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'leads.manage_sources'
  )
);

create policy "Authorized users can delete lead sources"
on public.lead_sources
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.manage_sources'
  )
);

-- =========================================================
-- 20. LEAD RLS POLICIES
-- =========================================================

create policy "Authorized users can view leads"
on public.leads
for select
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'leads.view'
  )
);

create policy "Authorized users can create leads"
on public.leads
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'leads.create'
  )
);

create policy "Authorized users can update leads"
on public.leads
for update
to authenticated
using (
  deleted_at is null
  and public.has_organization_permission(
    organization_id,
    'leads.update'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'leads.update'
  )
);

create policy "Authorized users can delete leads"
on public.leads
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.delete'
  )
);

-- =========================================================
-- 21. LEAD STATUS-HISTORY RLS
-- History is system-written. Authenticated users receive
-- read access only through organization permission.
-- =========================================================

create policy "Authorized users can view lead status history"
on public.lead_status_history
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.view'
  )
);

-- =========================================================
-- 22. ASSIGNMENT-HISTORY RLS
-- =========================================================

create policy "Authorized users can view assignment history"
on public.lead_assignment_history
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.view'
  )
);

-- =========================================================
-- 23. DUPLICATE-MATCH RLS
-- =========================================================

create policy "Authorized users can view duplicate matches"
on public.lead_duplicate_matches
for select
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.view'
  )
);

create policy "Authorized users can create duplicate matches"
on public.lead_duplicate_matches
for insert
to authenticated
with check (
  public.has_organization_permission(
    organization_id,
    'leads.merge'
  )
);

create policy "Authorized users can update duplicate matches"
on public.lead_duplicate_matches
for update
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.merge'
  )
)
with check (
  public.has_organization_permission(
    organization_id,
    'leads.merge'
  )
);

create policy "Authorized users can delete duplicate matches"
on public.lead_duplicate_matches
for delete
to authenticated
using (
  public.has_organization_permission(
    organization_id,
    'leads.merge'
  )
);

commit;