-- ============================================================
-- SalesSetu Module 036
-- Batched Foreign-Key Index Remediation
--
-- Background:
--   production_metadata validation completed with:
--     total_checks       = 4632
--     passed_checks      = 2955
--     failed_checks      = 1677
--     critical_failures  = 0
--     high_failures      = 1677
--     integrity_score    = 33.715
--
-- The extra 2530 production-metadata checks are single-column
-- foreign-key index checks:
--     passed FK checks = 853
--     failed FK checks = 1677
--
-- Purpose:
--   Create leading B-tree indexes for missing single-column
--   foreign-key child columns in controlled batches.
--
-- Usage:
--   1. Run this whole file once.
--   2. Re-run only the final SELECT until remaining_fk_constraints = 0.
--   3. Default batch size is 100. Increase cautiously if desired.
--
-- Safety:
--   • Existing valid/ready leading indexes are preserved.
--   • One index is created per unique table + child column.
--   • Multiple FKs sharing the same child column reuse one index.
--   • Names are deterministic and safely below 63 bytes.
--   • Each batch is atomic: any error rolls back that batch.
-- ============================================================

create or replace function public.remediate_missing_fk_indexes(
  p_batch_size integer default 100
)
returns table (
  created_indexes integer,
  remaining_table_columns integer,
  remaining_fk_constraints integer,
  batch_size integer,
  started_at timestamptz,
  completed_at timestamptz
)
language plpgsql
security invoker
set search_path = pg_catalog
as $function$
declare
  candidate_record record;
  effective_batch_size integer;
  generated_index_name text;
  created_count integer := 0;
  remaining_columns_count integer := 0;
  remaining_constraints_count integer := 0;
  batch_started_at timestamptz := clock_timestamp();
begin
  effective_batch_size := greatest(1, least(coalesce(p_batch_size, 100), 500));

  -- Avoid dashboard-side statement timeout while preserving caller ownership.
  perform set_config('statement_timeout', '0', true);
  perform set_config('lock_timeout', '30s', true);

  for candidate_record in
    with fk_candidates as (
      select distinct
        child_class.oid as child_oid,
        child_namespace.nspname as child_schema,
        child_class.relname as child_table,
        child_attribute.attname as child_column,
        child_attribute.attnum as child_attnum
      from pg_constraint constraint_row
      join pg_class child_class
        on child_class.oid = constraint_row.conrelid
      join pg_namespace child_namespace
        on child_namespace.oid = child_class.relnamespace
      join pg_attribute child_attribute
        on child_attribute.attrelid = child_class.oid
       and child_attribute.attnum = constraint_row.conkey[1]
      where constraint_row.contype = 'f'
        and cardinality(constraint_row.conkey) = 1
        and child_namespace.nspname = 'public'
        and child_class.relkind in ('r', 'p')
        and child_attribute.attnum > 0
        and not child_attribute.attisdropped
        and not exists (
          select 1
          from pg_index index_row
          where index_row.indrelid = child_class.oid
            and index_row.indisvalid
            and index_row.indisready
            and index_row.indnkeyatts >= 1
            and index_row.indkey[0] = child_attribute.attnum
        )
    )
    select
      fk_candidates.child_oid,
      fk_candidates.child_schema,
      fk_candidates.child_table,
      fk_candidates.child_column,
      fk_candidates.child_attnum
    from fk_candidates
    order by
      fk_candidates.child_schema,
      fk_candidates.child_table,
      fk_candidates.child_column
    limit effective_batch_size
  loop
    generated_index_name :=
      'idx_ss_fk_'
      || md5(
           candidate_record.child_schema
           || '.'
           || candidate_record.child_table
           || '.'
           || candidate_record.child_column
         );

    -- A deterministic name collision is practically impossible, but do not
    -- silently reuse an unrelated index if one somehow exists.
    if to_regclass(
         format(
           '%I.%I',
           candidate_record.child_schema,
           generated_index_name
         )
       ) is not null then
      raise exception
        'Index-name collision: %.% already exists while %.%.% still lacks a leading FK index',
        candidate_record.child_schema,
        generated_index_name,
        candidate_record.child_schema,
        candidate_record.child_table,
        candidate_record.child_column;
    end if;

    execute format(
      'create index %I on %I.%I using btree (%I)',
      generated_index_name,
      candidate_record.child_schema,
      candidate_record.child_table,
      candidate_record.child_column
    );

    created_count := created_count + 1;
  end loop;

  -- Count remaining unique table-column targets.
  with remaining_columns as (
    select distinct
      child_class.oid as child_oid,
      child_attribute.attnum as child_attnum
    from pg_constraint constraint_row
    join pg_class child_class
      on child_class.oid = constraint_row.conrelid
    join pg_namespace child_namespace
      on child_namespace.oid = child_class.relnamespace
    join pg_attribute child_attribute
      on child_attribute.attrelid = child_class.oid
     and child_attribute.attnum = constraint_row.conkey[1]
    where constraint_row.contype = 'f'
      and cardinality(constraint_row.conkey) = 1
      and child_namespace.nspname = 'public'
      and child_class.relkind in ('r', 'p')
      and child_attribute.attnum > 0
      and not child_attribute.attisdropped
      and not exists (
        select 1
        from pg_index index_row
        where index_row.indrelid = child_class.oid
          and index_row.indisvalid
          and index_row.indisready
          and index_row.indnkeyatts >= 1
          and index_row.indkey[0] = child_attribute.attnum
      )
  )
  select count(*)
  into remaining_columns_count
  from remaining_columns;

  -- Count remaining FK constraints exactly as Module 036 validates them.
  select count(*)
  into remaining_constraints_count
  from pg_constraint constraint_row
  join pg_class child_class
    on child_class.oid = constraint_row.conrelid
  join pg_namespace child_namespace
    on child_namespace.oid = child_class.relnamespace
  join pg_attribute child_attribute
    on child_attribute.attrelid = child_class.oid
   and child_attribute.attnum = constraint_row.conkey[1]
  where constraint_row.contype = 'f'
    and cardinality(constraint_row.conkey) = 1
    and child_namespace.nspname = 'public'
    and child_class.relkind in ('r', 'p')
    and child_attribute.attnum > 0
    and not child_attribute.attisdropped
    and not exists (
      select 1
      from pg_index index_row
      where index_row.indrelid = child_class.oid
        and index_row.indisvalid
        and index_row.indisready
        and index_row.indnkeyatts >= 1
        and index_row.indkey[0] = child_attribute.attnum
    );

  -- Optional audit log.
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
      'platform.fk_indexes.batch_remediated',
      format(
        'Created %s foreign-key indexes; %s FK constraints remain',
        created_count,
        remaining_constraints_count
      ),
      'runtime_patch',
      jsonb_build_object(
        'patch', '036_fk_index_batch_remediation',
        'created_indexes', created_count,
        'remaining_table_columns', remaining_columns_count,
        'remaining_fk_constraints', remaining_constraints_count,
        'batch_size', effective_batch_size,
        'started_at', batch_started_at,
        'completed_at', clock_timestamp()
      )
    );
  end if;

  return query
  select
    created_count,
    remaining_columns_count,
    remaining_constraints_count,
    effective_batch_size,
    batch_started_at,
    clock_timestamp();
end;
$function$;

comment on function public.remediate_missing_fk_indexes(integer) is
  'Creates missing leading indexes for public single-column foreign-key child columns in controlled batches.';

grant execute
on function public.remediate_missing_fk_indexes(integer)
to service_role;

-- ============================================================
-- RUN ONE BATCH
-- Re-run this SELECT until remaining_fk_constraints = 0.
-- ============================================================

select *
from public.remediate_missing_fk_indexes(100);
