-- Supabase-native scheduler for the AI calling pilot.
-- The schedule is deliberately safe to deploy: it is disabled and has no
-- organization or Vault secret until a human explicitly configures them.

create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

create table if not exists public.ai_call_dispatch_scheduler_settings (
  id boolean primary key default true check (id),
  enabled boolean not null default false,
  organization_id uuid,
  endpoint_url text not null default 'https://www.salessetu.in/api/ai-calling/dispatch',
  timezone text not null default 'Asia/Kolkata',
  start_hour smallint not null default 9 check (start_hour between 0 and 23),
  end_hour smallint not null default 20 check (end_hour between 0 and 23),
  lock_minutes smallint not null default 10 check (lock_minutes between 1 and 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ai_call_dispatch_scheduler_settings enable row level security;

insert into public.ai_call_dispatch_scheduler_settings (id, enabled)
values (true, false)
on conflict (id) do nothing;

create or replace function public.enqueue_ai_call_dispatch()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  config public.ai_call_dispatch_scheduler_settings%rowtype;
  dispatch_secret text;
  request_id bigint;
  local_hour integer;
begin
  select * into config
  from public.ai_call_dispatch_scheduler_settings
  where id = true;

  if not found or config.enabled is not true then
    return jsonb_build_object('status', 'disabled');
  end if;

  if config.organization_id is null then
    return jsonb_build_object('status', 'unconfigured');
  end if;

  local_hour := extract(hour from now() at time zone config.timezone);
  if config.start_hour <= config.end_hour then
    if local_hour < config.start_hour or local_hour >= config.end_hour then
      return jsonb_build_object('status', 'outside_calling_window');
    end if;
  elsif local_hour < config.start_hour and local_hour >= config.end_hour then
    return jsonb_build_object('status', 'outside_calling_window');
  end if;

  select decrypted_secret into dispatch_secret
  from vault.decrypted_secrets
  where name = 'ai_call_dispatch_secret'
  limit 1;

  if dispatch_secret is null or length(dispatch_secret) < 32 then
    return jsonb_build_object('status', 'secret_unavailable');
  end if;

  select net.http_post(
    url := config.endpoint_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || dispatch_secret,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'organizationId', config.organization_id,
      'workerId', 'supabase-cron',
      'lockMinutes', config.lock_minutes
    ),
    timeout_milliseconds := 10000
  ) into request_id;

  update public.ai_call_dispatch_scheduler_settings
  set updated_at = now()
  where id = true;

  return jsonb_build_object('status', 'enqueued', 'request_id', request_id);
exception
  when others then
    -- Do not surface request bodies, authentication material or provider data.
    return jsonb_build_object('status', 'request_failed');
end;
$$;

revoke all on function public.enqueue_ai_call_dispatch() from public;

select cron.schedule(
  'ai-call-dispatch-scheduler',
  '*/5 * * * *',
  $$select public.enqueue_ai_call_dispatch();$$
)
where not exists (
  select 1 from cron.job where jobname = 'ai-call-dispatch-scheduler'
);
