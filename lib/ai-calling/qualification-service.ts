import "server-only";

import {
  createAiCallProvider,
} from "./providers/factory";

import type {
  JsonObject,
  JsonValue,
} from "./providers/contract";

import {
  createAdminClient,
} from "@/lib/supabase/admin";

type ProcessQualificationInput = {
  callAttemptId: string;
  providerCallId: string;
  providerConnectionId: string;
};

type CallAttempt = {
  call_job_id: string;
};

type CallJob = {
  qualification_schema_id:
    | string
    | null;
};

type QualificationSchema = {
  schema_name: string;
  status: string;
};

type QualificationQuestion = {
  question_code: string;
  question_text: string;
  question_type: string;
  extraction_instructions:
    | string
    | null;
};

type ProviderConnection = {
  provider_id: string;
  credentials_reference:
    | string
    | null;
};

type Provider = {
  provider_code: string;
  api_base_url: string | null;
  status: string;
};

export type ProcessQualificationResult = {
  processed: boolean;
  skipped: boolean;
  reason: string | null;
};

function mapQuestionType(
  questionType: string,
) {
  switch (questionType) {
    case "number":
    case "currency":
    case "duration":
      return "number";

    case "boolean":
      return "boolean";

    default:
      return "string";
  }
}

function normalizeAnswer(
  answer: JsonValue,
) {
  if (
    typeof answer === "string"
  ) {
    return answer.trim();
  }

  return answer;
}

function buildRawAnswer(
  answer: JsonValue,
) {
  if (answer === null) {
    return null;
  }

  if (
    typeof answer === "string"
  ) {
    return answer.trim() || null;
  }

  return JSON.stringify(answer);
}

export async function processAiCallQualification(
  input: ProcessQualificationInput,
): Promise<ProcessQualificationResult> {
  const admin =
    createAdminClient();

  const {
    data: existingResult,
    error: existingResultError,
  } = await admin
    .from(
      "ai_call_qualification_results",
    )
    .select("id")
    .eq(
      "call_attempt_id",
      input.callAttemptId,
    )
    .maybeSingle();

  if (existingResultError) {
    throw new Error(
      `Unable to check qualification result: ${existingResultError.message}`,
    );
  }

  if (existingResult) {
    return {
      processed: false,
      skipped: true,
      reason:
        "Qualification was already calculated.",
    };
  }

  const {
    data: attemptData,
    error: attemptError,
  } = await admin
    .from("ai_call_attempts")
    .select("call_job_id")
    .eq("id", input.callAttemptId)
    .single();

  if (
    attemptError ||
    !attemptData
  ) {
    throw new Error(
      attemptError?.message ||
        "AI call attempt was not found.",
    );
  }

  const attempt =
    attemptData as unknown as CallAttempt;

  const {
    data: jobData,
    error: jobError,
  } = await admin
    .from("ai_call_jobs")
    .select(
      "qualification_schema_id",
    )
    .eq("id", attempt.call_job_id)
    .single();

  if (
    jobError ||
    !jobData
  ) {
    throw new Error(
      jobError?.message ||
        "AI call job was not found.",
    );
  }

  const job =
    jobData as unknown as CallJob;

  if (
    !job.qualification_schema_id
  ) {
    return {
      processed: false,
      skipped: true,
      reason:
        "Call job has no qualification schema.",
    };
  }

  const [
    schemaResponse,
    questionsResponse,
    connectionResponse,
  ] = await Promise.all([
    admin
      .from(
        "ai_call_qualification_schemas",
      )
      .select("schema_name,status")
      .eq(
        "id",
        job.qualification_schema_id,
      )
      .single(),

    admin
      .from(
        "ai_call_qualification_questions",
      )
      .select(
        [
          "question_code",
          "question_text",
          "question_type",
          "extraction_instructions",
        ].join(","),
      )
      .eq(
        "qualification_schema_id",
        job.qualification_schema_id,
      )
      .order(
        "sequence_number",
        {
          ascending: true,
        },
      ),

    admin
      .from(
        "ai_call_provider_connections",
      )
      .select(
        [
          "provider_id",
          "credentials_reference",
        ].join(","),
      )
      .eq(
        "id",
        input.providerConnectionId,
      )
      .single(),
  ]);

  if (
    schemaResponse.error ||
    !schemaResponse.data
  ) {
    throw new Error(
      schemaResponse.error?.message ||
        "Qualification schema was not found.",
    );
  }

  const schema =
    schemaResponse.data as unknown as QualificationSchema;

  if (schema.status !== "active") {
    return {
      processed: false,
      skipped: true,
      reason:
        "Qualification schema is inactive.",
    };
  }

  if (questionsResponse.error) {
    throw new Error(
      `Unable to load qualification questions: ${questionsResponse.error.message}`,
    );
  }

  const questions =
    (questionsResponse.data ??
      []) as unknown as QualificationQuestion[];

  if (questions.length === 0) {
    return {
      processed: false,
      skipped: true,
      reason:
        "Qualification schema has no questions.",
    };
  }

  if (
    connectionResponse.error ||
    !connectionResponse.data
  ) {
    throw new Error(
      connectionResponse.error
        ?.message ||
        "Provider connection was not found.",
    );
  }

  const connection =
    connectionResponse.data as unknown as ProviderConnection;

  const {
    data: providerData,
    error: providerError,
  } = await admin
    .from("ai_call_providers")
    .select(
      "provider_code,api_base_url,status",
    )
    .eq(
      "id",
      connection.provider_id,
    )
    .single();

  if (
    providerError ||
    !providerData
  ) {
    throw new Error(
      providerError?.message ||
        "AI calling provider was not found.",
    );
  }

  const provider =
    providerData as unknown as Provider;

  if (provider.status !== "active") {
    throw new Error(
      "AI calling provider is inactive.",
    );
  }

  const adapter =
    createAiCallProvider({
      providerCode:
        provider.provider_code,

      credentialsReference:
        connection.credentials_reference,

      apiBaseUrl:
        provider.api_base_url,
    });

  const analysis =
    await adapter.analyzeCall({
      providerCallId:
        input.providerCallId,

      goal:
        `Extract accurate answers for the ${schema.schema_name} qualification process.`,

      questions:
        questions.map(
          (question) => ({
            questionCode:
              question.question_code,

            questionText:
              question
                .extraction_instructions
                ? `${question.question_text} ${question.extraction_instructions}`
                : question.question_text,

            expectedAnswerType:
              mapQuestionType(
                question.question_type,
              ),
          }),
        ),
    });

  const responses: JsonObject[] =
    questions.map(
      (
        question,
        index,
      ) => {
        const answer =
          analysis.answers[index] ??
          null;

        return {
          question_code:
            question.question_code,

          raw_answer:
            buildRawAnswer(answer),

          normalized_answer:
            normalizeAnswer(answer),

          confidence:
            answer === null
              ? 0
              : 1,

          evidence_segments: [],

          metadata: {
            provider:
              provider.provider_code,

            credits_used:
              analysis.creditsUsed,
          },
        };
      },
    );

  const {
    error: responseError,
  } = await admin.rpc(
    "upsert_ai_call_qualification_responses",
    {
      requested_call_attempt_id:
        input.callAttemptId,

      requested_responses:
        responses,
    },
  );

  if (responseError) {
    throw new Error(
      `Unable to save qualification responses: ${responseError.message}`,
    );
  }

  const {
    error: calculationError,
  } = await admin.rpc(
    "calculate_ai_call_qualification",
    {
      requested_call_attempt_id:
        input.callAttemptId,
    },
  );

  if (calculationError) {
    throw new Error(
      `Unable to calculate qualification result: ${calculationError.message}`,
    );
  }

  return {
    processed: true,
    skipped: false,
    reason: null,
  };
}