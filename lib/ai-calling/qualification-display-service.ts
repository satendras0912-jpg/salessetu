import "server-only";

import {
  createClient,
} from "@/lib/supabase/server";

export type LeadAiQualificationAnswer = {
  id: string;
  questionCode: string;
  questionText: string;
  rawAnswer: string | null;
  normalizedAnswer: unknown;
  confidence: number | null;
  isValid: boolean | null;
  awardedScore: number;
  maximumScore: number;
  validationErrors: unknown[];
  evidenceSegments: unknown[];
};

export type LeadAiQualification = {
  id: string;
  callJobId: string;
  callAttemptId: string;
  status: string;
  totalScore: number;
  maximumScore: number;
  normalizedScore: number;
  validAnswerCount: number;
  requiredAnswerCount: number;
  missingRequiredQuestions: unknown[];
  disqualifyingReasons: unknown[];
  qualificationSummary: string | null;
  recommendedAction: string | null;
  recommendedFollowupAt: string | null;
  extractedProfile: Record<string, unknown>;
  reviewStatus: string | null;
  createdAt: string;
  answers: LeadAiQualificationAnswer[];
};

type QualificationResultRow = {
  id: string;
  call_job_id: string;
  call_attempt_id: string;
  status: string;
  total_score: number | string;
  maximum_score: number | string;
  normalized_score: number | string;
  valid_answer_count: number;
  required_answer_count: number;
  missing_required_questions: unknown;
  disqualifying_reasons: unknown;
  qualification_summary: string | null;
  recommended_action: string | null;
  recommended_followup_at: string | null;
  extracted_profile: unknown;
  review_status: string | null;
  created_at: string;
};

type QualificationResponseRow = {
  id: string;
  qualification_question_id: string;
  question_code: string;
  raw_answer: string | null;
  normalized_answer: unknown;
  confidence: number | string | null;
  is_valid: boolean | null;
  awarded_score: number | string;
  validation_errors: unknown;
  evidence_segments: unknown;
};

type QualificationQuestionRow = {
  id: string;
  question_text: string;
  maximum_score: number | string;
  sequence_number: number;
};

function asNumber(
  value: number | string | null | undefined,
): number {
  const parsed = Number(value);

  return Number.isFinite(parsed)
    ? parsed
    : 0;
}

function asArray(
  value: unknown,
): unknown[] {
  return Array.isArray(value)
    ? value
    : [];
}

function asObject(
  value: unknown,
): Record<string, unknown> {
  if (
    typeof value === "object" &&
    value !== null &&
    !Array.isArray(value)
  ) {
    return value as Record<string, unknown>;
  }

  return {};
}

export async function getLeadAiQualification(
  organizationId: string,
  leadId: string,
): Promise<LeadAiQualification | null> {
  const supabase =
    await createClient();

  const {
    data: resultData,
    error: resultError,
  } = await supabase
    .from(
      "ai_call_qualification_results",
    )
    .select(
      [
        "id",
        "call_job_id",
        "call_attempt_id",
        "status",
        "total_score",
        "maximum_score",
        "normalized_score",
        "valid_answer_count",
        "required_answer_count",
        "missing_required_questions",
        "disqualifying_reasons",
        "qualification_summary",
        "recommended_action",
        "recommended_followup_at",
        "extracted_profile",
        "review_status",
        "created_at",
      ].join(","),
    )
    .eq(
      "organization_id",
      organizationId,
    )
    .eq(
      "lead_id",
      leadId,
    )
    .order(
      "created_at",
      {
        ascending: false,
      },
    )
    .limit(1)
    .maybeSingle();

  if (resultError) {
    throw new Error(
      `Unable to load AI qualification result: ${resultError.message}`,
    );
  }

  if (!resultData) {
    return null;
  }

  const result =
    resultData as unknown as QualificationResultRow;

  const {
    data: responseData,
    error: responseError,
  } = await supabase
    .from(
      "ai_call_qualification_responses",
    )
    .select(
      [
        "id",
        "qualification_question_id",
        "question_code",
        "raw_answer",
        "normalized_answer",
        "confidence",
        "is_valid",
        "awarded_score",
        "validation_errors",
        "evidence_segments",
      ].join(","),
    )
    .eq(
      "organization_id",
      organizationId,
    )
    .eq(
      "call_attempt_id",
      result.call_attempt_id,
    );

  if (responseError) {
    throw new Error(
      `Unable to load AI qualification answers: ${responseError.message}`,
    );
  }

  const responses =
    (responseData ?? []) as unknown as QualificationResponseRow[];

  const questionIds =
    responses.map(
      (response) =>
        response.qualification_question_id,
    );

  let questions: QualificationQuestionRow[] = [];

  if (questionIds.length > 0) {
    const {
      data: questionData,
      error: questionError,
    } = await supabase
      .from(
        "ai_call_qualification_questions",
      )
      .select(
        [
          "id",
          "question_text",
          "maximum_score",
          "sequence_number",
        ].join(","),
      )
      .eq(
        "organization_id",
        organizationId,
      )
      .in(
        "id",
        questionIds,
      );

    if (questionError) {
      throw new Error(
        `Unable to load AI qualification questions: ${questionError.message}`,
      );
    }

    questions =
      (questionData ?? []) as unknown as QualificationQuestionRow[];
  }

  const questionById =
    new Map(
      questions.map(
        (question) => [
          question.id,
          question,
        ],
      ),
    );

  const answers =
    responses
      .map((response) => {
        const question =
          questionById.get(
            response.qualification_question_id,
          );

        return {
          id:
            response.id,

          questionCode:
            response.question_code,

          questionText:
            question?.question_text ??
            response.question_code,

          rawAnswer:
            response.raw_answer,

          normalizedAnswer:
            response.normalized_answer,

          confidence:
            response.confidence === null
              ? null
              : asNumber(
                  response.confidence,
                ),

          isValid:
            response.is_valid,

          awardedScore:
            asNumber(
              response.awarded_score,
            ),

          maximumScore:
            asNumber(
              question?.maximum_score,
            ),

          validationErrors:
            asArray(
              response.validation_errors,
            ),

          evidenceSegments:
            asArray(
              response.evidence_segments,
            ),

          sequenceNumber:
            question?.sequence_number ??
            Number.MAX_SAFE_INTEGER,
        };
      })
      .sort(
        (left, right) =>
          left.sequenceNumber -
          right.sequenceNumber,
      )
      .map(
  ({
    sequenceNumber,
    ...answer
  }) => {
    void sequenceNumber;

    return answer;
  },
);

  return {
    id:
      result.id,

    callJobId:
      result.call_job_id,

    callAttemptId:
      result.call_attempt_id,

    status:
      result.status,

    totalScore:
      asNumber(
        result.total_score,
      ),

    maximumScore:
      asNumber(
        result.maximum_score,
      ),

    normalizedScore:
      asNumber(
        result.normalized_score,
      ),

    validAnswerCount:
      result.valid_answer_count,

    requiredAnswerCount:
      result.required_answer_count,

    missingRequiredQuestions:
      asArray(
        result.missing_required_questions,
      ),

    disqualifyingReasons:
      asArray(
        result.disqualifying_reasons,
      ),

    qualificationSummary:
      result.qualification_summary,

    recommendedAction:
      result.recommended_action,

    recommendedFollowupAt:
      result.recommended_followup_at,

    extractedProfile:
      asObject(
        result.extracted_profile,
      ),

    reviewStatus:
      result.review_status,

    createdAt:
      result.created_at,

    answers,
  };
}