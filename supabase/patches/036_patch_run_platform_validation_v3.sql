-- ============================================================
-- SalesSetu Module 036 Runtime Patch
-- Fixes public.run_platform_validation(uuid,text,text)
--
-- Repairs:
--   1. PL/pgSQL record variable / SQL table-alias ambiguity
--      (for example m.id in the component expectation query).
--   2. Invalid unqualified total_checks / passed_checks /
--      failed_checks references in the completion log payload.
--   3. Missing seventh format() argument in the dynamic
--      foreign-key orphan-detection query.
--
-- This patch does not recreate Module 036 tables and does not
-- modify validation history.
-- ============================================================

begin;

create or replace function public.run_platform_validation(
  p_organization_id uuid default null,
  p_profile_code text default 'production',
  p_run_type text default 'manual'
)
returns public.platform_validation_runs
language plpgsql
security definer
set search_path=''
as $$
#variable_conflict use_column
declare
  profile_record public.platform_validation_profiles;
  run_record public.platform_validation_runs;
  m record;e record;d record;f record;a record;q record;fk record;
  passed boolean;exists_flag boolean;safe_path boolean;has_idx boolean;orphan_exists boolean;stale_exists boolean;
  total_weight numeric;awarded_weight numeric;readiness numeric;v_total_checks integer;v_passed_checks integer;v_failed_checks integer;
  v_critical_failures integer;v_high_failures integer;run_status text;config jsonb;
  module_total integer;module_ok integer;rls_total integer;rls_ok integer;fn_total integer;fn_ok integer;integrity_total integer;integrity_ok integer;queue_total integer;queue_ok integer;
  module_score numeric;rls_score numeric;fn_score numeric;integrity_score numeric;queue_score numeric;
begin
  if not public.platform_is_service_executor() and(
    p_organization_id is null or not public.has_organization_permission(p_organization_id,'platform_validation.run')
  ) then raise exception 'Permission denied'; end if;

  select * into profile_record from public.platform_validation_profiles where profile_code=p_profile_code and status='active';
  if not found then raise exception 'Active platform validation profile % not found',p_profile_code; end if;
  config:=profile_record.configuration;

  insert into public.platform_validation_runs(
    organization_id,profile_id,run_code,run_type,status,requested_by,started_at,configuration_snapshot,correlation_id
  ) values(
    p_organization_id,profile_record.id,'VAL-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,20)),p_run_type,'running',auth.uid(),now(),config,gen_random_uuid()::text
  ) returning * into run_record;

  perform public.sync_platform_component_expectations();
  perform public.refresh_platform_module_status(null);

  -- Module installation and marker status.
  for m in select * from public.platform_module_registry order by module_number loop
    passed:=case when m.lifecycle_status in('compatibility','deprecated','retired') then m.detected_status in('superseded','installed','complete') else m.detected_status in('installed','complete') end;
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'MODULE_'||lpad(m.module_number::text,3,'0'),'module_registry',passed,
      case when m.authority_status='authoritative' then 'critical' else 'medium' end,
      case when m.authority_status='authoritative' then 5 else 1 end,
      format('Module %s (%s) detected as %s',m.module_number,m.module_name,m.detected_status),'module',m.module_code,m.module_number,
      'Install missing required components or verify the migration marker.',
      jsonb_build_object('lifecycle_status',m.lifecycle_status,'authority_status',m.authority_status,'required_components',m.required_component_count,'detected_components',m.detected_component_count,'marker_verified',m.marker_verified));
  end loop;

  -- Required component checks.
  for e in select e.*,m.module_number,m.module_name,m.authority_status,m.lifecycle_status from public.platform_component_expectations e join public.platform_module_registry m on m.id=e.module_id order by m.module_number,e.component_type,e.component_name loop
    exists_flag:=public.platform_component_exists(e.component_type,e.schema_name,e.component_name,e.metadata);
    perform public.platform_add_validation_result(run_record.id,p_organization_id,
      'COMPONENT_'||e.module_number||'_'||upper(e.component_type)||'_'||upper(regexp_replace(e.component_name,'[^a-zA-Z0-9]+','_','g')),
      'component_catalog',exists_flag,
      case when e.required and e.authority_status='authoritative' and e.lifecycle_status='active' then 'critical' when e.required then 'high' else 'low' end,
      case when e.required then 2 else 0.5 end,
      case when exists_flag then format('%s %I.%I exists',e.component_type,e.schema_name,e.component_name) else format('%s %I.%I is missing',e.component_type,e.schema_name,e.component_name) end,
      e.component_type,e.schema_name||'.'||e.component_name,e.module_number,
      'Apply or repair the owning migration before production deployment.',e.metadata);
  end loop;

  -- Dependency checks.
  for d in select c.module_number child_no,c.module_name child_name,p.module_number parent_no,p.module_name parent_name,md.dependency_type,p.detected_status parent_status
    from public.platform_module_dependencies md join public.platform_module_registry c on c.id=md.module_id join public.platform_module_registry p on p.id=md.depends_on_module_id
    order by c.module_number,p.module_number loop
    passed:=d.parent_status in('installed','complete','superseded');
    perform public.platform_add_validation_result(run_record.id,p_organization_id,
      'DEPENDENCY_'||d.child_no||'_'||d.parent_no,'module_dependency',passed,
      case when d.dependency_type='required' then 'critical' when d.dependency_type='recommended' then 'medium' else 'low' end,
      case when d.dependency_type='required' then 2 else 0.5 end,
      format('Module %s depends on module %s (%s): %s',d.child_no,d.parent_no,d.dependency_type,d.parent_status),
      'module_dependency',d.child_no||'->'||d.parent_no,d.child_no,
      'Install or repair the dependency before enabling the dependent module.',jsonb_build_object('dependency_type',d.dependency_type,'parent_status',d.parent_status));
  end loop;

  -- RLS and tenant-index checks for all organization-scoped public tables.
  for q in select c.oid,n.nspname schema_name,c.relname table_name,c.relrowsecurity
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in('r','p')
      and exists(select 1 from pg_attribute at where at.attrelid=c.oid and at.attname='organization_id' and at.attnum>0 and not at.attisdropped)
    order by c.relname loop
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'RLS_'||upper(q.table_name),'tenant_isolation',q.relrowsecurity,
      'critical',3,case when q.relrowsecurity then format('RLS enabled on public.%I',q.table_name) else format('RLS is not enabled on public.%I',q.table_name) end,
      'table','public.'||q.table_name,null,'Enable RLS and create organization-scoped policies.',jsonb_build_object('rls_enabled',q.relrowsecurity));
    select exists(select 1 from pg_index i join pg_attribute at on at.attrelid=i.indrelid and at.attnum=any(i.indkey)
      where i.indrelid=q.oid and at.attname='organization_id') into has_idx;
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'TENANT_INDEX_'||upper(q.table_name),'tenant_index',has_idx,
      'high',1.5,case when has_idx then format('Tenant index exists on public.%I',q.table_name) else format('No index contains organization_id on public.%I',q.table_name) end,
      'table','public.'||q.table_name,null,'Add an index beginning with or containing organization_id.',jsonb_build_object('organization_indexed',has_idx));
  end loop;

  -- SECURITY DEFINER functions must explicitly set search_path.
  for f in select n.nspname schema_name,p.proname function_name,pg_get_function_identity_arguments(p.oid) identity_args,
      exists(select 1 from unnest(coalesce(p.proconfig,array[]::text[])) cfg where cfg like 'search_path=%') safe_search_path
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef=true order by p.proname,identity_args loop
    safe_path:=f.safe_search_path;
    perform public.platform_add_validation_result(run_record.id,p_organization_id,
      'SECURITY_DEFINER_'||upper(regexp_replace(f.function_name||'_'||f.identity_args,'[^a-zA-Z0-9]+','_','g')),
      'function_security',safe_path,'critical',2,
      case when safe_path then format('SECURITY DEFINER function %I.%I has an explicit search_path',f.schema_name,f.function_name)
           else format('SECURITY DEFINER function %I.%I does not set search_path',f.schema_name,f.function_name) end,
      'function',f.schema_name||'.'||f.function_name||'('||f.identity_args||')',null,
      'Recreate the function with SET search_path = '''' and fully-qualified object references.',jsonb_build_object('identity_arguments',f.identity_args));
  end loop;

  -- Single-column FK index and optional orphan checks.
  if coalesce((config->>'check_fk_indexes')::boolean,false) then
    for fk in select con.oid,con.conname,nc.nspname child_schema,cc.relname child_table,ac.attname child_column,
      np.nspname parent_schema,cp.relname parent_table,ap.attname parent_column,cc.oid child_oid
      from pg_constraint con join pg_class cc on cc.oid=con.conrelid join pg_namespace nc on nc.oid=cc.relnamespace
      join pg_class cp on cp.oid=con.confrelid join pg_namespace np on np.oid=cp.relnamespace
      join pg_attribute ac on ac.attrelid=cc.oid and ac.attnum=con.conkey[1]
      join pg_attribute ap on ap.attrelid=cp.oid and ap.attnum=con.confkey[1]
      where con.contype='f' and cardinality(con.conkey)=1 and nc.nspname='public' order by cc.relname,con.conname loop
      select exists(select 1 from pg_index i where i.indrelid=fk.child_oid and fk.child_column=(select attname from pg_attribute where attrelid=i.indrelid and attnum=i.indkey[0])) into has_idx;
      perform public.platform_add_validation_result(run_record.id,p_organization_id,'FK_INDEX_'||upper(fk.conname),'foreign_key_index',has_idx,'high',1,
        case when has_idx then format('Foreign key %I has a leading index',fk.conname) else format('Foreign key %I lacks a leading child-column index',fk.conname) end,
        'constraint',fk.child_schema||'.'||fk.child_table||'.'||fk.conname,null,'Add an index beginning with the foreign-key column.',
        jsonb_build_object('child_column',fk.child_column,'parent_table',fk.parent_schema||'.'||fk.parent_table,'parent_column',fk.parent_column));
      if coalesce((config->>'check_fk_integrity')::boolean,false) then
        execute format('select exists(select 1 from %I.%I c where c.%I is not null and not exists(select 1 from %I.%I p where p.%I=c.%I) limit 1)',
          fk.child_schema,
          fk.child_table,
          fk.child_column,
          fk.parent_schema,
          fk.parent_table,
          fk.parent_column,
          fk.child_column
        ) into orphan_exists;
        perform public.platform_add_validation_result(run_record.id,p_organization_id,'FK_INTEGRITY_'||upper(fk.conname),'referential_integrity',not orphan_exists,'critical',2,
          case when orphan_exists then format('Orphaned rows detected for foreign key %I',fk.conname) else format('No orphaned rows detected for foreign key %I',fk.conname) end,
          'constraint',fk.child_schema||'.'||fk.child_table||'.'||fk.conname,null,'Repair orphaned records and preserve FK enforcement.',jsonb_build_object('orphan_exists',orphan_exists));
      end if;
    end loop;
  end if;

  -- Authority map: exactly one active authoritative module per capability.
  for a in select ea.*,m.module_number,m.detected_status from public.platform_engine_authority ea join public.platform_module_registry m on m.id=ea.authoritative_module_id order by ea.capability_domain loop
    passed:=a.status='active' and a.detected_status in('installed','complete');
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'AUTHORITY_'||upper(a.capability_domain),'engine_authority',passed,'critical',3,
      format('Capability %s authority is module %s with status %s',a.capability_domain,a.module_number,a.detected_status),
      'capability',a.capability_domain,a.module_number,'Install the authoritative module or update the authority map.',
      jsonb_build_object('canonical_namespace',a.canonical_namespace,'legacy_module_ids',a.legacy_module_ids));
  end loop;

  -- End-to-end flow contract components.
  for f in select fc.*,m.module_number from public.platform_flow_contracts fc join public.platform_module_registry m on m.id=fc.module_id where fc.status='active' order by fc.sequence_number loop
    exists_flag:=public.platform_component_exists('table','public',f.authoritative_table,'{}');
    if exists_flag and f.entry_function is not null then exists_flag:=public.platform_component_exists('function','public',f.entry_function,'{}'); end if;
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'FLOW_'||upper(f.stage_code),'e2e_flow_contract',exists_flag,'critical',3,
      case when exists_flag then format('Flow stage %s is executable',f.stage_name) else format('Flow stage %s is missing its authoritative component or function',f.stage_name) end,
      'flow_stage',f.stage_code,f.module_number,'Restore the authoritative table/function declared by the flow contract.',
      jsonb_build_object('sequence',f.sequence_number,'table',f.authoritative_table,'entry_function',f.entry_function,'output_event',f.output_event));
  end loop;

  -- Stale worker locks across every compatible queue table.
  if coalesce((config->>'check_queue_locks')::boolean,true) then
    for q in select c.relname table_name from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relkind in('r','p')
        and exists(select 1 from pg_attribute a1 where a1.attrelid=c.oid and a1.attname='lock_expires_at' and a1.attnum>0 and not a1.attisdropped)
        and exists(select 1 from pg_attribute a2 where a2.attrelid=c.oid and a2.attname='status' and a2.attnum>0 and not a2.attisdropped)
      order by c.relname loop
      execute format('select exists(select 1 from public.%I where lock_expires_at is not null and lock_expires_at<=now() and status in(''claimed'',''processing'',''running'',''locked'',''in_progress'') limit 1)',q.table_name) into stale_exists;
      perform public.platform_add_validation_result(run_record.id,p_organization_id,'STALE_LOCK_'||upper(q.table_name),'queue_health',not stale_exists,'high',1,
        case when stale_exists then format('Stale worker lock detected in public.%I',q.table_name) else format('No stale worker lock detected in public.%I',q.table_name) end,
        'table','public.'||q.table_name,null,'Release expired locks and return eligible work to the retry queue.',jsonb_build_object('stale_lock_exists',stale_exists));
    end loop;
  end if;

  -- Outbox contract checks.
  for q in select c.relname table_name,c.oid from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in('r','p') and c.relname like '%event_outbox%' order by c.relname loop
    passed:=public.platform_column_exists('public',q.table_name,'status') and public.platform_column_exists('public',q.table_name,'available_at')
      and public.platform_column_exists('public',q.table_name,'idempotency_key');
    perform public.platform_add_validation_result(run_record.id,p_organization_id,'OUTBOX_CONTRACT_'||upper(q.table_name),'event_outbox',passed,'high',1.5,
      case when passed then format('Outbox public.%I satisfies status, scheduling and idempotency contract',q.table_name)
           else format('Outbox public.%I is missing status, available_at or idempotency_key',q.table_name) end,
      'table','public.'||q.table_name,null,'Add status, available_at and idempotency_key columns to the outbox contract.',
      jsonb_build_object('status',public.platform_column_exists('public',q.table_name,'status'),'available_at',public.platform_column_exists('public',q.table_name,'available_at'),'idempotency_key',public.platform_column_exists('public',q.table_name,'idempotency_key')));
  end loop;

  select count(*),count(*) filter(where vr.passed),count(*) filter(where not vr.passed),
         count(*) filter(where not vr.passed and vr.severity='critical'),count(*) filter(where not vr.passed and vr.severity='high'),
         coalesce(sum(vr.score_weight),0),coalesce(sum(vr.score_awarded),0)
    into v_total_checks,v_passed_checks,v_failed_checks,v_critical_failures,v_high_failures,total_weight,awarded_weight
  from public.platform_validation_results vr where vr.validation_run_id=run_record.id;
  readiness:=case when total_weight>0 then round((awarded_weight/total_weight)*100,3) else 0 end;
  run_status:=case when v_critical_failures>0 then 'blocked' when v_high_failures>0 then 'degraded' else 'completed' end;

  select count(*),count(*) filter(where vr.passed) into module_total,module_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category='module_registry';
  select count(*),count(*) filter(where vr.passed) into rls_total,rls_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category='tenant_isolation';
  select count(*),count(*) filter(where vr.passed) into fn_total,fn_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category='function_security';
  select count(*),count(*) filter(where vr.passed) into integrity_total,integrity_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category in('referential_integrity','foreign_key_index');
  select count(*),count(*) filter(where vr.passed) into queue_total,queue_ok from public.platform_validation_results vr where vr.validation_run_id=run_record.id and vr.category in('queue_health','event_outbox');
  module_score:=case when module_total>0 then round(module_ok::numeric/module_total*100,3) else 0 end;
  rls_score:=case when rls_total>0 then round(rls_ok::numeric/rls_total*100,3) else 100 end;
  fn_score:=case when fn_total>0 then round(fn_ok::numeric/fn_total*100,3) else 100 end;
  integrity_score:=case when integrity_total>0 then round(integrity_ok::numeric/integrity_total*100,3) else 100 end;
  queue_score:=case when queue_total>0 then round(queue_ok::numeric/queue_total*100,3) else 100 end;

  update public.platform_validation_runs set status=run_status,completed_at=now(),total_checks=v_total_checks,passed_checks=v_passed_checks,
    failed_checks=v_failed_checks,critical_failures=v_critical_failures,high_failures=v_high_failures,readiness_score=readiness,
    summary=jsonb_build_object('module_score',module_score,'tenant_isolation_score',rls_score,'function_security_score',fn_score,
      'integrity_score',integrity_score,'queue_health_score',queue_score),updated_at=now()
  where id=run_record.id returning * into run_record;

  insert into public.platform_readiness_snapshots(
    organization_id,validation_run_id,readiness_status,readiness_score,module_completion_percent,tenant_isolation_score,
    function_security_score,integrity_score,queue_health_score,critical_failures,high_failures,snapshot_data
  ) values(
    p_organization_id,run_record.id,case when v_critical_failures>0 then 'not_ready' when v_high_failures>0 or readiness<95 then 'conditionally_ready' else 'ready' end,
    readiness,module_score,rls_score,fn_score,integrity_score,queue_score,v_critical_failures,v_high_failures,run_record.summary
  );

  if coalesce((config->>'auto_create_issues')::boolean,true) then
    insert into public.platform_integration_issues(
      organization_id,issue_key,check_code,category,severity,title,description,component_type,component_name,module_number,status,
      first_validation_run_id,last_validation_run_id,remediation,metadata
    )
    select p_organization_id,md5(coalesce(p_organization_id::text,'global')||':'||r.check_code||':'||coalesce(r.component_name,'')),
      r.check_code,r.category,r.severity,r.message,r.message,r.component_type,r.component_name,r.module_number,'open',
      run_record.id,run_record.id,r.remediation,r.details
    from public.platform_validation_results r where r.validation_run_id=run_record.id and r.passed=false and r.severity in('critical','high')
    on conflict(issue_key) do update set last_validation_run_id=excluded.last_validation_run_id,last_seen_at=now(),severity=excluded.severity,
      title=excluded.title,description=excluded.description,remediation=excluded.remediation,metadata=public.platform_integration_issues.metadata||excluded.metadata,
      status=case when public.platform_integration_issues.status in('resolved','false_positive') then 'open' else public.platform_integration_issues.status end,updated_at=now();

    update public.platform_integration_issues i set status='resolved',resolved_at=now(),resolution_notes='Automatically resolved by validation run '||run_record.run_code,updated_at=now()
    where i.organization_id is not distinct from p_organization_id and i.status in('open','acknowledged','in_progress')
      and not exists(select 1 from public.platform_validation_results r where r.validation_run_id=run_record.id and r.passed=false
        and i.issue_key=md5(coalesce(p_organization_id::text,'global')||':'||r.check_code||':'||coalesce(r.component_name,'')));
  end if;

  perform public.publish_platform_integration_event(p_organization_id,'platform.validation.'||run_status,
    jsonb_build_object('validation_run_id',run_record.id,'run_code',run_record.run_code,'status',run_status,'readiness_score',readiness,
      'critical_failures',v_critical_failures,'high_failures',v_high_failures),'observability','platform_validation_run',run_record.id,10,
      'platform-validation:'||run_record.id::text,run_record.correlation_id,run_record.trace_id,now());

  insert into public.platform_integration_logs(organization_id,log_level,event_name,message,source_type,source_id,actor_user_id,log_data,correlation_id,trace_id)
  values(p_organization_id,case when run_status='blocked' then 'critical' when run_status='degraded' then 'warning' else 'info' end,
    'platform.validation.'||run_status,'Platform validation completed with readiness score '||readiness,'platform_validation_run',run_record.id,auth.uid(),
    jsonb_build_object('total_checks',v_total_checks,'passed_checks',v_passed_checks,'failed_checks',v_failed_checks,'critical_failures',v_critical_failures,'high_failures',v_high_failures),run_record.correlation_id,run_record.trace_id);
  return run_record;
exception when others then
  if run_record.id is not null then
    update public.platform_validation_runs set status='failed',completed_at=now(),error_message=sqlerrm,updated_at=now() where id=run_record.id returning * into run_record;
    insert into public.platform_integration_logs(organization_id,log_level,event_name,message,source_type,source_id,error_code,error_message,log_data)
    values(p_organization_id,'error','platform.validation.failed','Platform validation execution failed','platform_validation_run',run_record.id,sqlstate,sqlerrm,'{}');
  end if;
  raise;
end $$;

do $validation$
declare
  function_oid oid;
  function_source text;
begin
  select p.oid
  into function_oid
  from pg_proc p
  join pg_namespace n
    on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'run_platform_validation'
    and pg_get_function_identity_arguments(p.oid) = 'p_organization_id uuid, p_profile_code text, p_run_type text'
  limit 1;

  if function_oid is null then
    raise exception
      'Patch validation failed: public.run_platform_validation(uuid,text,text) was not found';
  end if;

  select pg_get_functiondef(function_oid)
  into function_source;

  if position('#variable_conflict use_column' in function_source) = 0 then
    raise exception
      'Patch validation failed: variable-conflict directive is missing';
  end if;

  if function_source ~
     'jsonb_build_object\(''total_checks'',total_checks,''passed_checks'',passed_checks,''failed_checks'',failed_checks' then
    raise exception
      'Patch validation failed: unqualified summary counters remain';
  end if;

  if function_source !~
     'fk[.]parent_column[[:space:]]*,[[:space:]]*fk[.]child_column[[:space:]]*\)[[:space:]]+into[[:space:]]+orphan_exists' then
    raise exception
      'Patch validation failed: foreign-key integrity format argument list is not corrected';
  end if;
end;
$validation$;

commit;

select
  'public.run_platform_validation patched successfully'::text as status,
  now() as patched_at;
