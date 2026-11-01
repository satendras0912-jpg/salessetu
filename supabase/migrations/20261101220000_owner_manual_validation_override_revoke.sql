-- =========================================================
-- SalesSetu Enterprise
-- Owner override revoke control and per-lead audit
-- =========================================================

begin;

create or replace function public.revoke_manual_lead_validation_override(
  p_lead_id uuid,
  p_revoke_reason text
)
returns public.lead_manual_validation_overrides
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_lead public.leads;
  override_record public.lead_manual_validation_overrides;
  normalized_reason text := btrim(coalesce(p_revoke_reason, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if char_length(normalized_reason) < 3
    or char_length(normalized_reason) > 500 then
    raise exception
      'Revoke reason must contain between 3 and 500 characters';
  end if;

  select *
  into target_lead
  from public.leads lead
  where lead.id = p_lead_id
    and lead.deleted_at is null
  for update;

  if not found then
    raise exception 'Lead not found';
  end if;

  if not exists (
    select 1
    from public.organization_members member
    where member.organization_id = target_lead.organization_id
      and member.user_id = auth.uid()
      and member.membership_status = 'active'
      and member.is_owner = true
  ) then
    raise exception
      'Only the workspace owner can revoke an override';
  end if;

  select *
  into override_record
  from public.lead_manual_validation_overrides override
  where override.organization_id = target_lead.organization_id
    and override.lead_id = target_lead.id
    and override.status = 'active'
  for update;

  if not found then
    raise exception 'No active owner override exists for this lead';
  end if;

  update public.lead_manual_validation_overrides
  set
    status = 'revoked',
    revoked_by = auth.uid(),
    revoked_at = now(),
    revoke_reason = normalized_reason,
    updated_at = now()
  where id = override_record.id
  returning *
  into override_record;

  return override_record;
end;
$$;

revoke all
on function public.revoke_manual_lead_validation_override(uuid,text)
from public;

grant execute
on function public.revoke_manual_lead_validation_override(uuid,text)
to authenticated, service_role;

commit;
