-- Preserve the installed qualification function exported on 2026-10-05.
-- Requires the existing AI calling schema and function; preserves existing grants.
-- Includes required-answer review and customer-preference recommendations.
-- Does not include customer data corrections or calling/extraction prompt updates.

BEGIN;
SET LOCAL search_path = public, pg_catalog;

DO $migration$
BEGIN
  IF to_regprocedure('public.calculate_ai_call_qualification(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Existing AI calling qualification function is required before this migration';
  END IF;
END;
$migration$;

CREATE OR REPLACE FUNCTION public.calculate_ai_call_qualification(requested_call_attempt_id uuid)
 RETURNS ai_call_qualification_results
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target_attempt public.ai_call_attempts;
  target_job public.ai_call_jobs;
  target_schema public.ai_call_qualification_schemas;
  total_score_value numeric(8,2);
  maximum_score_value numeric(8,2);
  normalized_score_value numeric(8,2);
  valid_count integer;
  required_count integer;
  missing_questions jsonb;
  disqualifying jsonb;
  final_status text;
  created_result public.ai_call_qualification_results;
begin
  select *
  into target_attempt
  from public.ai_call_attempts attempt
  where attempt.id = requested_call_attempt_id;

  if not found then
    raise exception 'AI call attempt not found';
  end if;

  select *
  into target_job
  from public.ai_call_jobs job
  where job.id = target_attempt.call_job_id;

  if target_job.qualification_schema_id is null then
    raise exception 'Call job has no qualification schema';
  end if;

  select *
  into target_schema
  from public.ai_call_qualification_schemas schema_record
  where schema_record.id = target_job.qualification_schema_id;

  select
    coalesce(sum(response.awarded_score), 0),
    coalesce(sum(question.maximum_score), 0),
    count(*) filter (where response.is_valid = true),
    count(*) filter (where question.is_required = true),
    coalesce(
      jsonb_agg(question.question_code)
        filter (
          where question.is_required = true
            and coalesce(response.is_valid, false) = false
        ),
      '[]'::jsonb
    ),
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'question_code', question.question_code,
          'answer', response.normalized_answer
        )
      ) filter (
        where response.normalized_answer is not null
          and question.disqualifying_values @> jsonb_build_array(response.normalized_answer)
      ),
      '[]'::jsonb
    )
  into
    total_score_value,
    maximum_score_value,
    valid_count,
    required_count,
    missing_questions,
    disqualifying
  from public.ai_call_qualification_questions question
  left join public.ai_call_qualification_responses response
    on response.qualification_question_id = question.id
   and response.call_attempt_id = target_attempt.id
  where question.qualification_schema_id = target_schema.id;

  normalized_score_value :=
    case
      when maximum_score_value > 0
        then round((total_score_value / maximum_score_value) * 100, 2)
      else 0
    end;

  final_status :=
    case
      when jsonb_array_length(disqualifying) > 0 then 'unqualified'
      when jsonb_array_length(missing_questions) > 0 or valid_count < target_schema.minimum_valid_answers then 'manual_review'
      when normalized_score_value >= target_schema.hot_threshold then 'qualified_hot'
      when normalized_score_value >= target_schema.warm_threshold then 'qualified_warm'
      else 'qualified_cold'
    end;

  insert into public.ai_call_qualification_results (
    organization_id,
    call_job_id,
    call_attempt_id,
    qualification_schema_id,
    lead_id,
    status,
    total_score,
    maximum_score,
    normalized_score,
    valid_answer_count,
    required_answer_count,
    missing_required_questions,
    disqualifying_reasons,
    qualification_summary,
    recommended_action,
    extracted_profile,
    scoring_breakdown
  )
  values (
    target_attempt.organization_id,
    target_job.id,
    target_attempt.id,
    target_schema.id,
    target_job.lead_id,
    final_status,
    total_score_value,
    maximum_score_value,
    normalized_score_value,
    valid_count,
    required_count,
    missing_questions,
    disqualifying,
    'AI call qualification completed with score ' || normalized_score_value::text,

case
  -- CUSTOMER_NEXT_ACTION_V1
  when final_status = 'unqualified'
    then 'close_or_suppress'
  when final_status = 'manual_review'
    then 'manual_review'
  else coalesce(
    (
      select case response.normalized_answer #>> '{}'
        when 'site_visit'
          then 'assign_agent_and_schedule_site_visit'
        when 'agent_callback'
          then 'agent_callback_and_nurture'
        when 'send_details'
          then 'send_details'
        when 'not_now'
          then 'manual_review'
        when 'not_interested'
          then 'close_or_suppress'
        when 'do_not_call'
          then 'close_or_suppress'
        else 'manual_review'
      end
      from public.ai_call_qualification_responses response
      where response.call_attempt_id = target_attempt.id
        and response.qualification_schema_id = target_schema.id
        and response.question_code = 'site_visit_interest'
        and response.is_valid = true
    ),
    'manual_review'
  )
end
,
    '{}'::jsonb,
    jsonb_build_object(
      'total_score', total_score_value,
      'maximum_score', maximum_score_value,
      'normalized_score', normalized_score_value
    )
  )
  on conflict (call_attempt_id)
  do update set
    status = excluded.status,
    total_score = excluded.total_score,
    maximum_score = excluded.maximum_score,
    normalized_score = excluded.normalized_score,
    valid_answer_count = excluded.valid_answer_count,
    required_answer_count = excluded.required_answer_count,
    missing_required_questions = excluded.missing_required_questions,
    disqualifying_reasons = excluded.disqualifying_reasons,
    qualification_summary = excluded.qualification_summary,
    recommended_action = excluded.recommended_action,
    scoring_breakdown = excluded.scoring_breakdown,
    updated_at = now()
  returning *
  into created_result;

  update public.ai_call_jobs
  set
    qualification_status = final_status,
    qualification_score = normalized_score_value,
    final_disposition_code = case final_status
      when 'qualified_hot' then 'qualified_hot'
      when 'qualified_warm' then 'qualified_warm'
      when 'qualified_cold' then 'qualified_cold'
      when 'unqualified' then 'connected_not_interested'
      else final_disposition_code
    end,
    updated_at = now()
  where id = target_job.id;

  return created_result;
end;
$function$;

COMMIT;
