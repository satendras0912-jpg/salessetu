-- ============================================================
-- SalesSetu Module 036 Runtime Hardening Patch v2
-- Tenant organization_id index remediation
--
-- Fix in v2:
--   The previous patch used a temporary table. In the Supabase SQL
--   Editor execution path that temporary relation was not available
--   when the later DO block referenced it. This version is completely
--   temp-table-free and performs discovery, creation, validation and
--   audit logging inside one PL/pgSQL block.
--
-- Purpose:
--   Create a valid B-tree index containing organization_id for every
--   public tenant table that currently lacks one.
--
-- Safety:
--   • Existing valid indexes are preserved.
--   • Views and materialized views are excluded.
--   • Child partitions are skipped; partitioned parents are handled.
--   • Deterministic hash-based index names avoid the 63-byte limit.
--   • Any incomplete remediation raises an exception and rolls back.
-- ============================================================

begin;

set local statement_timeout = '0';
set local lock_timeout = '30s';

do $tenant_index_patch$
declare
  target_record record;
  created_count integer := 0;
  remaining_count integer := 0;
  remaining_tables text;
  generated_index_name text;
begin
  -- Discover and remediate each public base/partitioned table that has
  -- organization_id but no valid, ready index containing that column.
  for target_record in
    select
      n.nspname as schema_name,
      c.relname as table_name,
      a.attname as column_name
    from pg_class c
    join pg_namespace n
      on n.oid = c.relnamespace
    join pg_attribute a
      on a.attrelid = c.oid
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and not c.relispartition
      and a.attname = 'organization_id'
      and a.attnum > 0
      and not a.attisdropped
      and not exists (
        select 1
        from pg_index i
        where i.indrelid = c.oid
          and i.indisvalid
          and i.indisready
          and a.attnum = any(i.indkey::smallint[])
      )
    order by c.relname
  loop
    generated_index_name :=
      'idx_ss_org_'
      || left(
           md5(
             target_record.schema_name
             || '.'
             || target_record.table_name
             || '.'
             || target_record.column_name
           ),
           20
         );

    -- Fail loudly on the extremely unlikely case that the deterministic
    -- name already belongs to a different index definition.
    if to_regclass(
         format(
           '%I.%I',
           target_record.schema_name,
           generated_index_name
         )
       ) is not null then
      raise exception
        'Index-name collision: %.% already exists while %.% still lacks an organization_id index',
        target_record.schema_name,
        generated_index_name,
        target_record.schema_name,
        target_record.table_name;
    end if;

    execute format(
      'create index %I on %I.%I using btree (%I)',
      generated_index_name,
      target_record.schema_name,
      target_record.table_name,
      target_record.column_name
    );

    created_count := created_count + 1;
  end loop;

  -- Hard validation after index creation.
  select
    count(*),
    string_agg(
      format('%I.%I', n.nspname, c.relname),
      ', '
      order by c.relname
    )
  into
    remaining_count,
    remaining_tables
  from pg_class c
  join pg_namespace n
    on n.oid = c.relnamespace
  join pg_attribute a
    on a.attrelid = c.oid
  where n.nspname = 'public'
    and c.relkind in ('r', 'p')
    and not c.relispartition
    and a.attname = 'organization_id'
    and a.attnum > 0
    and not a.attisdropped
    and not exists (
      select 1
      from pg_index i
      where i.indrelid = c.oid
        and i.indisvalid
        and i.indisready
        and a.attnum = any(i.indkey::smallint[])
    );

  if remaining_count > 0 then
    raise exception
      'Tenant-index remediation incomplete. % table(s) still lack an organization_id index: %',
      remaining_count,
      coalesce(remaining_tables, 'unknown');
  end if;

  -- Persist a compact audit log when Module 036 logging is available.
  if to_regclass('public.platform_integration_logs') is not null then
    insert into public.platform_integration_logs (
      organization_id,
      log_level,
      event_name,
      message,
      source_type,
      log_data
    )
    values (
      null,
      'info',
      'platform.tenant_indexes.remediated',
      format(
        'Created %s missing organization_id tenant indexes',
        created_count
      ),
      'runtime_patch',
      jsonb_build_object(
        'patch', '036_patch_tenant_organization_indexes_v2',
        'created_indexes', created_count,
        'remaining_without_index', remaining_count,
        'completed_at', now()
      )
    );
  end if;

  raise notice
    'Tenant organization_id index remediation complete. Created indexes: %',
    created_count;
end;
$tenant_index_patch$;

commit;

-- Post-commit confirmation.
with tenant_tables as (
  select
    n.nspname as schema_name,
    c.relname as table_name,
    c.oid as table_oid,
    a.attnum
  from pg_class c
  join pg_namespace n
    on n.oid = c.relnamespace
  join pg_attribute a
    on a.attrelid = c.oid
  where n.nspname = 'public'
    and c.relkind in ('r', 'p')
    and not c.relispartition
    and a.attname = 'organization_id'
    and a.attnum > 0
    and not a.attisdropped
),
index_status as (
  select
    t.schema_name,
    t.table_name,
    exists (
      select 1
      from pg_index i
      where i.indrelid = t.table_oid
        and i.indisvalid
        and i.indisready
        and t.attnum = any(i.indkey::smallint[])
    ) as is_indexed
  from tenant_tables t
)
select
  count(*) as tenant_tables,
  count(*) filter (where is_indexed) as indexed_tenant_tables,
  count(*) filter (where not is_indexed) as remaining_without_index,
  now() as verified_at
from index_status;
