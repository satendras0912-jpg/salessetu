-- Disposable staging database only. All calls use invalid synthetic inputs.
begin;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.role', '', true);
do $$
declare caught text;
begin
  begin
    perform public.ingest_lead_capture_intake('{}'::jsonb);
    raise exception 'Expected null-role rejection';
  exception when others then
    caught := sqlerrm;
    if caught <> 'Only service_role may ingest lead capture intake' then raise; end if;
  end;
  begin
    perform public.attempt_lead_capture_intake('00000000-0000-0000-0000-000000000000'::uuid);
    raise exception 'Expected null-role rejection';
  exception when others then
    caught := sqlerrm;
    if caught <> 'Only service_role may process lead capture intake' then raise; end if;
  end;
end $$;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.role', 'service_role', true);
do $$
declare caught text;
begin
  begin
    perform public.ingest_lead_capture_intake('{}'::jsonb);
    raise exception 'Expected input validation rejection';
  exception when others then
    caught := sqlerrm;
    if caught <> 'A lead capture route key is required' then raise; end if;
  end;
  begin
    perform public.attempt_lead_capture_intake('00000000-0000-0000-0000-000000000000'::uuid);
    raise exception 'Expected missing intake rejection';
  exception when others then
    caught := sqlerrm;
    if caught <> 'Lead capture intake record not found' then raise; end if;
  end;
end $$;
rollback;
