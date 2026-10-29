begin;

create or replace function public.get_lead_attribution_dashboard(requested_organization_id uuid, requested_days integer default 90)
returns table (dimension text, label text, lead_count bigint, qualified_count bigint, follow_up_count bigint, site_visit_count bigint, deal_count bigint, won_count bigint)
language plpgsql stable security definer set search_path = ''
as $function$
begin
  if requested_organization_id is null then raise exception 'An active organization is required'; end if;
  if requested_days < 1 or requested_days > 365 then raise exception 'Attribution period must be between 1 and 365 days'; end if;
  if auth.role() <> 'service_role' and (
    not public.has_organization_permission(requested_organization_id, 'dashboard.view') or
    not public.has_organization_permission(requested_organization_id, 'leads.view') or
    not public.has_organization_permission(requested_organization_id, 'followups.view') or
    not public.has_organization_permission(requested_organization_id, 'site_visits.view') or
    not public.has_organization_permission(requested_organization_id, 'deals.view')
  ) then raise exception 'Permission denied'; end if;
  return query
  with cohort as (
    select lead.id,
      coalesce(nullif(regexp_replace(lead_source.name, '[[:space:]]+', ' ', 'g'), ''), nullif(regexp_replace(lead.utm_source, '[[:space:]]+', ' ', 'g'), ''), 'Unattributed') as source_label,
      coalesce(nullif(regexp_replace(lead.utm_campaign, '[[:space:]]+', ' ', 'g'), ''), nullif(regexp_replace(lead.campaign_name, '[[:space:]]+', ' ', 'g'), ''), 'Unattributed campaign') as campaign_label,
      case lead.geo_tag when 'noida' then 'Noida' when 'greater_noida' then 'Greater Noida' when 'greater_noida_west' then 'Greater Noida West' when 'siddharth_vihar' then 'Siddharth Vihar' when 'wave_city' then 'Wave City' when 'raj_nagar_extension' then 'Raj Nagar Extension' when 'ghaziabad' then 'Ghaziabad' else 'GEO mapping required' end as geo_label,
      lead.ai_qualified or lower(coalesce(lead.qualification_status, '')) in ('qualified', 'approved') as is_qualified,
      exists (select 1 from public.follow_up_tasks task where task.organization_id = requested_organization_id and task.lead_id = lead.id and task.deleted_at is null) as reached_follow_up,
      exists (select 1 from public.site_visits visit where visit.organization_id = requested_organization_id and visit.lead_id = lead.id and visit.deleted_at is null) as reached_site_visit,
      exists (select 1 from public.deals deal where deal.organization_id = requested_organization_id and deal.lead_id = lead.id and deal.deleted_at is null) as reached_deal,
      exists (select 1 from public.deals deal where deal.organization_id = requested_organization_id and deal.lead_id = lead.id and deal.deleted_at is null and deal.status = 'won') as reached_won
    from public.leads lead left join public.lead_sources lead_source on lead_source.id = lead.lead_source_id and lead_source.organization_id = requested_organization_id
    where lead.organization_id = requested_organization_id and lead.deleted_at is null and lead.created_at >= now() - make_interval(days => requested_days)
  ), grouped as (
    select 'source'::text as group_dimension, source_label as group_label, * from cohort
    union all select 'campaign'::text, campaign_label, * from cohort
    union all select 'geo'::text, geo_label, * from cohort
  )
  select group_dimension as dimension, group_label as label, count(*)::bigint as lead_count, count(*) filter (where is_qualified)::bigint as qualified_count, count(*) filter (where reached_follow_up)::bigint as follow_up_count, count(*) filter (where reached_site_visit)::bigint as site_visit_count, count(*) filter (where reached_deal)::bigint as deal_count, count(*) filter (where reached_won)::bigint as won_count
  from grouped group by group_dimension, group_label order by group_dimension, lead_count desc, group_label asc;
end;
$function$;

revoke all on function public.get_lead_attribution_dashboard(uuid, integer) from public;
grant execute on function public.get_lead_attribution_dashboard(uuid, integer) to authenticated, service_role;

commit;
