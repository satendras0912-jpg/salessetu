-- Canonical GEO tag used by follow-up queues and future agent-coverage rules.
-- Free-text city/location remain intact as the original customer preference.
alter table public.leads
  add column if not exists geo_tag text;

create index if not exists leads_organization_geo_tag_idx
  on public.leads (organization_id, geo_tag)
  where deleted_at is null;

comment on column public.leads.geo_tag is
  'Canonical sales-coverage GEO code. Null means manual GEO mapping is required.';

-- One-time conservative backfill for the current initial market list. Existing
-- explicit values are never replaced, and unknown locations stay null.
update public.leads
set geo_tag = case
  when lower(concat_ws(' ', preferred_location, preferred_city)) ~ '(greater[[:space:]]*noida[[:space:]]*(west|w)|noida[[:space:]]*extension)' then 'greater_noida_west'
  when lower(concat_ws(' ', preferred_location, preferred_city)) ~ 'siddharth[[:space:]]*vihar' then 'siddharth_vihar'
  when lower(concat_ws(' ', preferred_location, preferred_city)) ~ 'wave[[:space:]]*city' then 'wave_city'
  when lower(concat_ws(' ', preferred_location, preferred_city)) ~ 'raj[[:space:]]*nagar[[:space:]]*extension' then 'raj_nagar_extension'
  when lower(concat_ws(' ', preferred_location, preferred_city)) ~ 'greater[[:space:]]*noida' then 'greater_noida'
  when lower(concat_ws(' ', preferred_location, preferred_city)) ~ 'noida' then 'noida'
  when lower(concat_ws(' ', preferred_location, preferred_city)) ~ 'ghaziabad' then 'ghaziabad'
  else null
end
where geo_tag is null;
