-- ============================================================
-- 56. AI CALL QUALIFICATION RESPONSE PROCESSING
-- ============================================================

create or replace function public.upsert_ai_call_qualification_responses(
  requested_call_attempt_id uuid,
  requested_responses jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_attempt public.ai_call_attempts;
  target_job public.ai_call_jobs;
  target_question public.ai_call_qualification_questions;

  response_item jsonb;
  normalized_answer_value jsonb;
  normalized_answer_text text;
  raw_answer_value text;
  confidence_value numeric(8,4);
  evidence_value jsonb;
  validation_errors_value jsonb;
  awarded_score_value numeric(8,2);
  is_valid_value boolean;

  processed_count integer := 0;
  valid_count integer := 0;
  invalid_count integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role'
    and not public.has_organization_permission(
      (
        select attempt.organization_id
        from public.ai_call_attempts attempt
        where attempt.id = requested_call_attempt_id
      ),
      'ai_calling.manage_qualification'
    )
  then
    raise exception 'Permission denied';
  end if;

  select *
  into target_attempt
  from public.ai_call_attempts attempt
  where attempt.id = requested_call_attempt_id
  for update;

  if not found then
    raise exception 'AI call attempt not found';
  end if;

  select *
  into target_job
  from public.ai_call_jobs job
  where job.id = target_attempt.call_job_id;

  if not found then
    raise exception 'AI call job not found';
  end if;

  if target_job.qualification_schema_id is null then
    raise exception 'Call job has no qualification schema';
  end if;

  if requested_responses is null
    or jsonb_typeof(requested_responses) <> 'array'
  then
    raise exception 'Qualification responses must be a JSON array';
  end if;

  for response_item in
    select value
    from jsonb_array_elements(requested_responses)
  loop
    if coalesce(response_item ->> 'question_code', '') = '' then
      raise exception 'Qualification response question_code is required';
    end if;

    select *
    into target_question
    from public.ai_call_qualification_questions question
    where question.qualification_schema_id =
      target_job.qualification_schema_id
      and question.question_code =
        response_item ->> 'question_code';

    if not found then
      raise exception
        'Unknown qualification question code: %',
        response_item ->> 'question_code';
    end if;

    normalized_answer_value :=
      case
        when response_item ? 'normalized_answer'
          then response_item -> 'normalized_answer'
        else 'null'::jsonb
      end;

    normalized_answer_text :=
      normalized_answer_value #>> '{}';

    raw_answer_value :=
      coalesce(
        nullif(response_item ->> 'raw_answer', ''),
        normalized_answer_text
      );

    confidence_value :=
      case
        when coalesce(response_item ->> 'confidence', '')
          ~ '^[0-9]+([.][0-9]+)?$'
        then least(
          1,
          greatest(
            0,
            (response_item ->> 'confidence')::numeric
          )
        )
        else null
      end;

    evidence_value :=
      case
        when jsonb_typeof(
          response_item -> 'evidence_segments'
        ) = 'array'
        then response_item -> 'evidence_segments'
        else '[]'::jsonb
      end;

    is_valid_value :=
      normalized_answer_text is not null
      and (
        not (
          target_question.validation_rules
          ? 'allowed_values'
        )
        or coalesce(
          target_question.validation_rules
            -> 'allowed_values',
          '[]'::jsonb
        ) @> jsonb_build_array(
          normalized_answer_value
        )
      );

    validation_errors_value :=
      case
        when normalized_answer_text is null
          then jsonb_build_array(
            'answer_missing'
          )
        when not is_valid_value
          then jsonb_build_array(
            'answer_not_allowed'
          )
        else '[]'::jsonb
      end;

    awarded_score_value :=
      case
        when is_valid_value then
          least(
            target_question.maximum_score,
            greatest(
              0,
              coalesce(
                (
                  target_question.scoring_rules
                  ->> normalized_answer_text
                )::numeric,
                0
              )
            )
          )
        else 0
      end;

    insert into public.ai_call_qualification_responses (
      organization_id,
      call_job_id,
      call_attempt_id,
      qualification_schema_id,
      qualification_question_id,
      question_code,
      raw_answer,
      normalized_answer,
      confidence,
      is_valid,
      validation_errors,
      awarded_score,
      evidence_segments,
      metadata
    )
    values (
      target_attempt.organization_id,
      target_job.id,
      target_attempt.id,
      target_job.qualification_schema_id,
      target_question.id,
      target_question.question_code,
      raw_answer_value,
      normalized_answer_value,
      confidence_value,
      is_valid_value,
      validation_errors_value,
      awarded_score_value,
      evidence_value,
      jsonb_build_object(
        'source', 'bland_post_call_analysis',
        'processed_at', now()
      )
    )
    on conflict (
      call_attempt_id,
      qualification_question_id
    )
    do update set
      raw_answer = excluded.raw_answer,
      normalized_answer =
        excluded.normalized_answer,
      confidence = excluded.confidence,
      is_valid = excluded.is_valid,
      validation_errors =
        excluded.validation_errors,
      awarded_score =
        excluded.awarded_score,
      evidence_segments =
        excluded.evidence_segments,
      metadata =
        ai_call_qualification_responses.metadata
        || excluded.metadata,
      updated_at = now()
    where
      ai_call_qualification_responses
        .manually_overridden = false;

    processed_count := processed_count + 1;

    if is_valid_value then
      valid_count := valid_count + 1;
    else
      invalid_count := invalid_count + 1;
    end if;
  end loop;

  return jsonb_build_object(
    'call_attempt_id',
      target_attempt.id,
    'qualification_schema_id',
      target_job.qualification_schema_id,
    'processed_count',
      processed_count,
    'valid_count',
      valid_count,
    'invalid_count',
      invalid_count
  );
end;
$$;

revoke all on function
  public.upsert_ai_call_qualification_responses(
    uuid,
    jsonb
  )
from public;

grant execute on function
  public.upsert_ai_call_qualification_responses(
    uuid,
    jsonb
  )
to authenticated, service_role;