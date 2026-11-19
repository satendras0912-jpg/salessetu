-- Owner-facing in-app alert for booking documents submitted by agents.
-- Each current document file can notify the active workspace owner once.

begin;

insert into public.notification_categories (
  organization_id,
  category_code,
  category_name,
  description,
  severity,
  default_channels,
  default_priority,
  is_system_category,
  is_user_configurable
)
values (
  null,
  'booking_document_review',
  'Booking Document Review',
  'Booking document submitted for workspace owner review',
  'warning',
  array['in_app'],
  25,
  true,
  true
)
on conflict do nothing;

create or replace function public.create_booking_document_in_app_notification(
  requested_document_file_id uuid
)
returns public.notification_jobs
language plpgsql
security definer
set search_path = ''
as $function$
declare
  document_record public.booking_document_files;
  item_record public.booking_document_checklist_items;
  owner_membership public.organization_members;
  category_record public.notification_categories;
  existing_job public.notification_jobs;
  notification_job_record public.notification_jobs;
  recipient_record public.notification_recipients;
  eligibility jsonb;
  notification_idempotency_key text;
  notification_body text;
begin
  select *
  into document_record
  from public.booking_document_files
  where id = requested_document_file_id
    and is_current
  for update;

  if not found then
    raise exception 'Current booking document file not found';
  end if;

  select *
  into item_record
  from public.booking_document_checklist_items
  where id = document_record.checklist_item_id
    and organization_id = document_record.organization_id;

  if not found or not item_record.requires_owner_approval then
    return null;
  end if;

  select *
  into owner_membership
  from public.organization_members
  where organization_id = document_record.organization_id
    and membership_status = 'active'
    and is_owner
  limit 1;

  if not found or owner_membership.user_id = document_record.uploaded_by then
    return null;
  end if;

  notification_idempotency_key :=
    'booking_document_review:' || document_record.id::text;

  select *
  into existing_job
  from public.notification_jobs
  where organization_id = document_record.organization_id
    and idempotency_key = notification_idempotency_key
  limit 1;

  if found then
    return existing_job;
  end if;

  select *
  into category_record
  from public.notification_categories
  where category_code = 'booking_document_review'
    and status = 'active'
    and organization_id is null
  limit 1;

  if not found then
    raise exception 'Active booking document review notification category not found';
  end if;

  notification_body :=
    item_record.item_name
    || ' was submitted for Deal '
    || left(document_record.deal_id::text, 8)
    || '. Open the deal to review it.';

  insert into public.notification_jobs (
    organization_id,
    category_id,
    source_module,
    source_type,
    source_id,
    source_reference,
    event_name,
    idempotency_key,
    correlation_id,
    trace_id,
    title,
    body,
    rendered_title,
    rendered_body,
    variables,
    actions,
    deep_link,
    severity,
    priority,
    status,
    recipient_count,
    delivered_count,
    started_at,
    created_by,
    updated_by,
    metadata
  )
  values (
    document_record.organization_id,
    category_record.id,
    'bookings',
    'booking_document_file',
    document_record.id,
    document_record.booking_id::text,
    'booking.document.submitted',
    notification_idempotency_key,
    gen_random_uuid()::text,
    gen_random_uuid()::text,
    'Booking document submitted',
    notification_body,
    'Booking document submitted',
    notification_body,
    jsonb_build_object(
      'booking_id', document_record.booking_id,
      'deal_id', document_record.deal_id,
      'checklist_item_id', item_record.id,
      'item_code', item_record.item_code,
      'filename', document_record.original_filename,
      'uploaded_by', document_record.uploaded_by
    ),
    '[]'::jsonb,
    '/dashboard/deals/' || document_record.deal_id::text || '#agreement-checklist',
    'warning',
    25,
    'processing',
    1,
    0,
    now(),
    document_record.uploaded_by,
    document_record.uploaded_by,
    jsonb_build_object(
      'channel_codes', array['in_app']::text[],
      'category_code', 'booking_document_review',
      'delivery_source', 'booking_document_upload'
    )
  )
  returning * into notification_job_record;

  insert into public.notification_recipients (
    organization_id,
    notification_job_id,
    recipient_type,
    user_id,
    status
  )
  values (
    document_record.organization_id,
    notification_job_record.id,
    'user',
    owner_membership.user_id,
    'pending'
  )
  returning * into recipient_record;

  eligibility := public.check_notification_eligibility(
    document_record.organization_id,
    owner_membership.user_id,
    'booking_document_review',
    'in_app',
    'warning',
    now()
  );

  if coalesce((eligibility ->> 'eligible')::boolean, false) then
    insert into public.notification_delivery_attempts (
      organization_id,
      notification_job_id,
      notification_recipient_id,
      channel_code,
      status,
      attempt_number,
      delivered_at
    )
    values (
      document_record.organization_id,
      notification_job_record.id,
      recipient_record.id,
      'in_app',
      'delivered',
      1,
      now()
    );

    insert into public.notification_inbox (
      organization_id,
      user_id,
      notification_job_id,
      notification_recipient_id,
      title,
      body,
      category_code,
      severity,
      priority,
      deep_link,
      actions,
      metadata
    )
    values (
      document_record.organization_id,
      owner_membership.user_id,
      notification_job_record.id,
      recipient_record.id,
      notification_job_record.rendered_title,
      notification_job_record.rendered_body,
      'booking_document_review',
      notification_job_record.severity,
      notification_job_record.priority,
      notification_job_record.deep_link,
      notification_job_record.actions,
      jsonb_build_object(
        'source_module', 'bookings',
        'source_type', 'booking_document_file',
        'source_id', document_record.id
      )
    );

    update public.notification_recipients
    set status = 'delivered', delivered_at = now()
    where id = recipient_record.id;

    update public.notification_jobs
    set status = 'delivered',
        delivered_count = 1,
        completed_at = now(),
        updated_at = now()
    where id = notification_job_record.id;
  else
    update public.notification_recipients
    set status = 'suppressed',
        suppression_reason = eligibility ->> 'reason'
    where id = recipient_record.id;

    update public.notification_jobs
    set status = 'delivered',
        suppressed_count = 1,
        completed_at = now(),
        updated_at = now()
    where id = notification_job_record.id;
  end if;

  select *
  into notification_job_record
  from public.notification_jobs
  where id = notification_job_record.id;

  return notification_job_record;
end;
$function$;

revoke all on function public.create_booking_document_in_app_notification(uuid)
from public;

grant execute on function public.create_booking_document_in_app_notification(uuid)
to authenticated, service_role;

create or replace function public.notify_owner_of_booking_document_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform public.create_booking_document_in_app_notification(new.id);
  return new;
end;
$function$;

drop trigger if exists booking_document_files_notify_owner_after_insert
on public.booking_document_files;

create trigger booking_document_files_notify_owner_after_insert
after insert on public.booking_document_files
for each row
execute function public.notify_owner_of_booking_document_submission();

select pg_notify('pgrst', 'reload schema');

commit;
