import "server-only";

import { createAdminClient } from "@/lib/supabase/admin";

import {
  createAiCallProvider,
  resolveAiCallSecret,
} from "./providers/factory";

import {
  createBlandWebhookToken,
} from "./webhook-signature";

import type {
  JsonObject,
} from "./providers/contract";

type ClaimedJob = {
  id: string;
  organization_id: string;
  provider_connection_id: string;
  script_template_id: string;
  voice_id: string | null;
  phone_number: string;
  contact_name: string | null;
  language_code: string;
  script_variables: JsonObject;
  call_context: JsonObject;
  metadata: JsonObject;
};

type ProviderConnection = {
  id: string;
  provider_id: string;
  status: string;
  credentials_reference: string | null;
  webhook_secret_reference: string | null;
  outbound_phone_number: string | null;
  default_voice_id: string | null;
  default_language_code: string;
};

type Provider = {
  provider_code: string;
  api_base_url: string | null;
  status: string;
};

type ScriptTemplate = {
  status: string;
  opening_message: string;
  system_prompt: string;
  objection_handling_prompt: string | null;
  closing_prompt: string | null;
  recording_disclosure_text: string | null;
  maximum_call_duration_seconds: number;
  allow_recording: boolean;
};

type Voice = {
  provider_voice_id: string;
  is_active: boolean;
};

type CallAttempt = {
  id: string;
};

export type DispatchNextAiCallInput = {
  workerId: string;
  webhookBaseUrl: string;
  organizationId?: string | null;
  lockMinutes?: number;
};

export type DispatchNextAiCallResult =
  | {
      status: "empty";
    }
  | {
      status: "initiated";
      jobId: string;
      attemptId: string;
      providerCallId: string;
    }
  | {
      status: "failed";
      jobId: string;
      attemptId: string | null;
      message: string;
    };

function interpolateTemplate(
  template: string,
  variables: JsonObject,
) {
  return template.replace(
    /\{\{\s*([a-zA-Z0-9_.-]+)\s*\}\}/g,
    (match, key: string) => {
      const value =
        variables[key];

      if (
        typeof value === "string" ||
        typeof value === "number" ||
        typeof value === "boolean"
      ) {
        return String(value);
      }

      return match;
    },
  );
}

function buildTask(
  script: ScriptTemplate,
  variables: JsonObject,
) {
  const sections = [
    interpolateTemplate(
      script.system_prompt,
      variables,
    ),

    script.recording_disclosure_text
      ? `Recording disclosure:\n${interpolateTemplate(
          script.recording_disclosure_text,
          variables,
        )}`
      : null,

    script.objection_handling_prompt
      ? `Objection handling:\n${interpolateTemplate(
          script.objection_handling_prompt,
          variables,
        )}`
      : null,

    script.closing_prompt
      ? `Closing instructions:\n${interpolateTemplate(
          script.closing_prompt,
          variables,
        )}`
      : null,
  ];

  return sections
    .filter(
      (section): section is string =>
        Boolean(section),
    )
    .join("\n\n");
}

function getErrorMessage(
  error: unknown,
) {
  return error instanceof Error
    ? error.message
    : "Unknown AI calling dispatch error.";
}

function buildWebhookUrl(
  baseUrl: string,
  connectionId: string,
  webhookToken: string,
) {
  const cleanBaseUrl =
    baseUrl.trim();

  if (!cleanBaseUrl) {
    throw new Error(
      "AI calling webhook base URL is required.",
    );
  }

  const webhookUrl =
    new URL(
      `/api/ai-calling/webhooks/bland/${connectionId}`,
      cleanBaseUrl,
    );

  webhookUrl.searchParams.set(
    "token",
    webhookToken,
  );

  return webhookUrl.toString();
}

export async function dispatchNextAiCall(
  input: DispatchNextAiCallInput,
): Promise<DispatchNextAiCallResult> {
  const workerId =
    input.workerId.trim();

  if (!workerId) {
    throw new Error(
      "AI calling worker ID is required.",
    );
  }

  const admin =
    createAdminClient();

  const {
    data: claimedJobData,
    error: claimError,
  } = await admin.rpc(
    "claim_ai_call_job",
    {
      requested_worker_id:
        workerId,

      requested_organization_id:
        input.organizationId ?? null,

      requested_lock_minutes:
        input.lockMinutes ?? 10,
    },
  );

  if (claimError) {
    throw new Error(
      `Unable to claim AI call job: ${claimError.message}`,
    );
  }

  if (!claimedJobData) {
    return {
      status: "empty",
    };
  }

  const job =
  claimedJobData as unknown as ClaimedJob;

  let attemptId: string | null =
    null;

  try {
    const [
      connectionResult,
      scriptResult,
    ] = await Promise.all([
      admin
        .from(
          "ai_call_provider_connections",
        )
        .select(
          [
            "id",
            "provider_id",
            "status",
            "credentials_reference",
            "webhook_secret_reference",
            "outbound_phone_number",
            "default_voice_id",
            "default_language_code",
          ].join(","),
        )
        .eq(
          "id",
          job.provider_connection_id,
        )
        .single(),

      admin
        .from(
          "ai_call_script_templates",
        )
        .select(
          [
            "status",
            "opening_message",
            "system_prompt",
            "objection_handling_prompt",
            "closing_prompt",
            "recording_disclosure_text",
            "maximum_call_duration_seconds",
            "allow_recording",
          ].join(","),
        )
        .eq(
          "id",
          job.script_template_id,
        )
        .single(),
    ]);

    if (connectionResult.error) {
      throw new Error(
        `Unable to load provider connection: ${connectionResult.error.message}`,
      );
    }

    if (scriptResult.error) {
      throw new Error(
        `Unable to load calling script: ${scriptResult.error.message}`,
      );
    }

    const connection =
        connectionResult.data as unknown as ProviderConnection;

    const script =
    scriptResult.data as unknown as ScriptTemplate;

    if (connection.status !== "active") {
      throw new Error(
        "AI calling provider connection is not active.",
      );
    }

    if (script.status !== "active") {
      throw new Error(
        "AI calling script template is not active.",
      );
    }

    const {
      data: providerData,
      error: providerError,
    } = await admin
      .from("ai_call_providers")
      .select(
        "provider_code, api_base_url, status",
      )
      .eq(
        "id",
        connection.provider_id,
      )
      .single();

    if (providerError) {
      throw new Error(
        `Unable to load AI calling provider: ${providerError.message}`,
      );
    }

    const provider =
        providerData as unknown as Provider;

    if (provider.status !== "active") {
      throw new Error(
        "AI calling provider is not active.",
      );
    }

    let providerVoiceId =
      connection.default_voice_id;

    if (job.voice_id) {
      const {
        data: voiceData,
        error: voiceError,
      } = await admin
        .from("ai_call_voices")
        .select(
          "provider_voice_id, is_active",
        )
        .eq(
          "id",
          job.voice_id,
        )
        .single();

      if (voiceError) {
        throw new Error(
          `Unable to load AI calling voice: ${voiceError.message}`,
        );
      }

      const voice =
          voiceData as unknown as Voice;

      if (!voice.is_active) {
        throw new Error(
          "Selected AI calling voice is inactive.",
        );
      }

      providerVoiceId =
        voice.provider_voice_id;
    }

    const variables: JsonObject = {
      ...job.script_variables,

      contact_name:
        job.contact_name ?? "",

      phone_number:
        job.phone_number,
    };

    const task =
      buildTask(
        script,
        variables,
      );

    const firstSentence =
      interpolateTemplate(
        script.opening_message,
        variables,
      );

        const webhookSecret =
      resolveAiCallSecret(
        connection
          .webhook_secret_reference,
      );

    const webhookToken =
      createBlandWebhookToken(
        connection.id,
        webhookSecret,
      );

    const webhookUrl =
      buildWebhookUrl(
        input.webhookBaseUrl,
        connection.id,
        webhookToken,
      );

    const providerRequest: JsonObject = {
      provider_code:
        provider.provider_code,

      phone_number:
        job.phone_number,

      from_phone_number:
        connection.outbound_phone_number,

      voice_id:
        providerVoiceId,

      language_code:
        job.language_code ||
        connection.default_language_code,

      webhook_url:
        webhookUrl,

      maximum_duration_seconds:
        script.maximum_call_duration_seconds,

      record_call:
        script.allow_recording,
    };

    const {
      data: attemptData,
      error: attemptError,
    } = await admin.rpc(
      "start_ai_call_attempt",
      {
        requested_call_job_id:
          job.id,

        requested_provider_request:
          providerRequest,

        requested_from_phone_number:
          connection.outbound_phone_number,
      },
    );

    if (attemptError) {
      throw new Error(
        `Unable to start AI call attempt: ${attemptError.message}`,
      );
    }

    const attempt =
        attemptData as unknown as CallAttempt;

    attemptId =
      attempt.id;

    const adapter =
      createAiCallProvider({
        providerCode:
          provider.provider_code,

        credentialsReference:
          connection.credentials_reference,

        apiBaseUrl:
          provider.api_base_url,
      });

    const dispatchResult =
      await adapter.dispatchCall({
        attemptId:
          attempt.id,

        jobId:
          job.id,

        phoneNumber:
          job.phone_number,

        fromPhoneNumber:
          connection.outbound_phone_number,

        voiceId:
          providerVoiceId,

        languageCode:
          job.language_code ||
          connection.default_language_code,

        task,

        firstSentence,

        maximumDurationSeconds:
          script.maximum_call_duration_seconds,

        webhookUrl,

        recordCall:
          script.allow_recording,

        requestData: {
          ...variables,
          ...job.call_context,
        },

        metadata: {
          ...job.metadata,

          organization_id:
            job.organization_id,

          provider_connection_id:
            connection.id,
        },
      });

    const {
      error: initiatedError,
    } = await admin.rpc(
      "mark_ai_call_initiated",
      {
        requested_call_attempt_id:
          attempt.id,

        requested_provider_call_id:
          dispatchResult.providerCallId,

        requested_provider_response:
          dispatchResult.providerResponse,

        requested_provider_batch_id:
          null,
      },
    );

    if (initiatedError) {
      throw new Error(
        `Bland call started, but initiation could not be recorded: ${initiatedError.message}`,
      );
    }

    return {
      status: "initiated",
      jobId: job.id,
      attemptId: attempt.id,
      providerCallId:
        dispatchResult.providerCallId,
    };
    } catch (error) {
    let message =
      getErrorMessage(error);

    if (!attemptId) {
      const {
        data: existingAttemptData,
        error: existingAttemptError,
      } = await admin
        .from("ai_call_attempts")
        .select("id")
        .eq(
          "call_job_id",
          job.id,
        )
        .eq(
          "status",
          "dispatching",
        )
        .order(
          "attempt_number",
          {
            ascending: false,
          },
        )
        .limit(1)
        .maybeSingle();

      if (
        !existingAttemptError &&
        existingAttemptData
      ) {
        const existingAttempt =
          existingAttemptData as unknown as CallAttempt;

        attemptId =
          existingAttempt.id;
      }
    }

    if (!attemptId) {
      const {
        data: fallbackAttemptData,
        error: fallbackAttemptError,
      } = await admin.rpc(
        "start_ai_call_attempt",
        {
          requested_call_job_id:
            job.id,

          requested_provider_request: {
            dispatch_failed_before_provider:
              true,

            worker_id:
              workerId,
          },

          requested_from_phone_number:
            null,
        },
      );

      if (
        !fallbackAttemptError &&
        fallbackAttemptData
      ) {
        const fallbackAttempt =
          fallbackAttemptData as unknown as CallAttempt;

        attemptId =
          fallbackAttempt.id;
      } else if (fallbackAttemptError) {
        message =
          `${message} Attempt recovery failed: ${fallbackAttemptError.message}`;
      }
    }

    if (attemptId) {
      const {
        error: completionError,
      } = await admin.rpc(
        "complete_ai_call_attempt",
        {
          requested_call_attempt_id:
            attemptId,

          requested_status:
            "failed",

          requested_disposition_code:
            "provider_failure",

          requested_call_duration_seconds:
            null,

          requested_recording_url:
            null,

          requested_provider_cost:
            null,

          requested_provider_currency:
            null,

          requested_result_data:
            {},

          requested_error_code:
            "dispatch_failed",

          requested_error_message:
            message,

          requested_error_data: {
            worker_id:
              workerId,
          },
        },
      );

      if (completionError) {
        message =
          `${message} Database failure recording also failed: ${completionError.message}`;
      }
    }

    return {
      status: "failed",
      jobId: job.id,
      attemptId,
      message,
    };
  }
}