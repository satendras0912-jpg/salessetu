begin;

-- ============================================================
-- SalesSetu
-- Migration 044
-- Site Visit → Lead State Reconciliation
--
-- Fixes:
-- 1. Cancelled site visits recalculate aggregate lead status.
-- 2. Positive completed-site-visit outcomes can promote
--    a cold lead to warm.
-- 3. Existing hot leads are never downgraded to warm.
-- 4. Terminal lead states remain protected.
-- ============================================================

create or replace function public.sync_lead_from_site_visit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  has_active_site_visit boolean := false;
  has_completed_site_visit boolean := false;
begin

  -- ----------------------------------------------------------
  -- INSERT
  --
  -- Creating a site visit moves the lead into the
  -- site-visit-planned operational stage, except terminal leads.
  -- ----------------------------------------------------------

  if tg_op = 'INSERT' then

    update public.leads
    set
      lead_status =
        case
          when lead_status in (
            'booked',
            'lost',
            'archived'
          )
            then lead_status
          else 'site_visit_planned'
        end,

      lifecycle_stage =
        case
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


  -- ----------------------------------------------------------
  -- UPDATE with no status transition
  -- ----------------------------------------------------------

  if new.status is not distinct from old.status then
    return new;
  end if;


  -- ----------------------------------------------------------
  -- COMPLETED
  -- ----------------------------------------------------------

  if new.status = 'completed' then

    update public.leads
    set
      lead_status =
        case
          when lead_status in (
            'booked',
            'lost',
            'archived'
          )
            then lead_status
          else 'site_visit_completed'
        end,

      lead_temperature =
        case

          -- Strong commercial intent → Hot
          when new.outcome in (
            'highly_interested',
            'negotiation_started',
            'booking_expected'
          )
            then 'hot'


          -- Positive intent → minimum Warm.
          -- Never downgrade an already Hot lead.
          when new.outcome in (
            'interested',
            'considering',
            'follow_up_required'
          )
            then
              case
                when lead_temperature = 'hot'
                  then 'hot'
                else 'warm'
              end


          -- Negative commercial outcome → Cold
          when new.outcome in (
            'not_interested',
            'budget_mismatch',
            'location_mismatch',
            'unit_mismatch'
          )
            then 'cold'


          -- Neutral/other outcomes preserve current temperature.
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


  -- ----------------------------------------------------------
  -- ACTIVE / PLANNED SITE VISIT
  -- ----------------------------------------------------------

  elsif new.status in (
    'scheduled',
    'confirmed',
    'rescheduled',
    'agent_en_route',
    'customer_en_route',
    'checked_in',
    'in_progress'
  ) then

    update public.leads
    set
      lead_status =
        case
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


  -- ----------------------------------------------------------
  -- CANCELLED
  --
  -- A cancellation must not blindly leave the parent lead in
  -- site_visit_planned.
  --
  -- Priority:
  -- 1. Terminal lead → preserve.
  -- 2. Another active visit exists → site_visit_planned.
  -- 3. No active visit but completed visit exists
  --      → site_visit_completed.
  -- 4. Otherwise preserve current lead status because there is
  --    no universally safe predecessor status to infer.
  -- ----------------------------------------------------------

  elsif new.status = 'cancelled' then

    select exists (
      select 1
      from public.site_visits sv
      where sv.organization_id = new.organization_id
        and sv.lead_id = new.lead_id
        and sv.deleted_at is null
        and sv.status in (
          'draft',
          'scheduled',
          'confirmed',
          'agent_en_route',
          'customer_en_route',
          'checked_in',
          'in_progress',
          'rescheduled'
        )
    )
    into has_active_site_visit;


    select exists (
      select 1
      from public.site_visits sv
      where sv.organization_id = new.organization_id
        and sv.lead_id = new.lead_id
        and sv.deleted_at is null
        and sv.status = 'completed'
    )
    into has_completed_site_visit;


    update public.leads
    set
      lead_status =
        case

          when lead_status in (
            'booked',
            'lost',
            'archived'
          )
            then lead_status

          when has_active_site_visit
            then 'site_visit_planned'

          when has_completed_site_visit
            then 'site_visit_completed'

          else lead_status

        end,

      updated_at = now()

    where id = new.lead_id
      and organization_id = new.organization_id
      and deleted_at is null;

  end if;


  return new;

end;
$function$;

commit;