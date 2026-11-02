-- =========================================================
-- SalesSetu Enterprise
-- Fix ambiguous status reference in lead capture retry worker.
-- =========================================================

begin;

create or replace function public.retry_lead_capture_intakes(
  p_limit integer default 25
)
returns table (
  intake_id uuid,
  processing_status text,
  processed_lead_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  intake_id_value uuid;
  result jsonb;
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only service_role may retry lead capture intake';
  end if;

  for intake_id_value in
    select intake.id
    from public.lead_capture_intake as intake
    where intake.processing_status in ('pending', 'retryable')
      and intake.processed_lead_id is null
      and (
        intake.retry_after is null
        or intake.retry_after <= now()
      )
    order by intake.received_at asc
    limit greatest(1, least(coalesce(p_limit, 25), 100))
    for update skip locked
  loop
    result := public.attempt_lead_capture_intake(intake_id_value);

    return query
    select
      intake_id_value,
      result ->> 'status',
      nullif(result ->> 'lead_id', '')::uuid;
  end loop;
end;
$$;

revoke all
on function public.retry_lead_capture_intakes(integer)
from public;

grant execute
on function public.retry_lead_capture_intakes(integer)
to service_role;

commit;
