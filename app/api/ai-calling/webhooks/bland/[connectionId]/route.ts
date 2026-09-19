import {
  NextRequest,
  NextResponse,
} from "next/server";

import {
  resolveAiCallSecret,
} from "@/lib/ai-calling/providers/factory";

import type {
  JsonObject,
  JsonValue,
} from "@/lib/ai-calling/providers/contract";

import {
  verifyBlandWebhookSignature,
} from "@/lib/ai-calling/webhook-signature";

import {
  createAdminClient,
} from "@/lib/supabase/admin";

export const runtime =
  "nodejs";

export const dynamic =
  "force-dynamic";

export const maxDuration =
  60;

type RouteContext = {
  params: Promise<{
    connectionId: string;
  }>;
};

type ProviderConnection = {
  id: string;
  status: string;
  webhook_secret_reference:
    | string
    | null;
};

type WebhookEventRecord = {
  id: string;
  call_attempt_id: string | null;
  processing_status: string;
};

type TerminalAttemptStatus =
  | "completed"
  | "failed"
  | "no_answer"
  | "busy"
  | "voicemail";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function readString(
  value: JsonValue | undefined,
) {
  return typeof value === "string"
    ? value.trim()
    : "";
}

function readNumber(
  value: JsonValue | undefined,
) {
  if (
    typeof value === "number" &&
    Number.isFinite(value)
  ) {
    return value;
  }

  if (
    typeof value === "string" &&
    value.trim()
  ) {
    const parsed =
      Number(value);

    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }

  return null;
}

function determineTerminalStatus(
  payload: JsonObject,
): TerminalAttemptStatus {
  const status =
    readString(
      payload.status,
    ).toLowerCase();

  const queueStatus =
    readString(
      payload.queue_status,
    ).toLowerCase();

  const answeredBy =
    readString(
      payload.answered_by,
    ).toLowerCase();

  const dispositionTag =
    readString(
      payload.disposition_tag,
    ).toUpperCase();

  const errorMessage =
    readString(
      payload.error_message,
    );

  if (
    status.includes("busy") ||
    queueStatus.includes("busy") ||
    dispositionTag === "BUSY"
  ) {
    return "busy";
  }

  if (
    status.includes("no_answer") ||
    status.includes("no-answer") ||
    queueStatus.includes("no_answer") ||
    queueStatus.includes("no-answer") ||
    dispositionTag === "NO_ANSWER"
  ) {
    return "no_answer";
  }

  if (
    status.includes("voicemail") ||
    answeredBy.includes("voicemail") ||
    answeredBy.includes("machine")
  ) {
    return "voicemail";
  }

  if (
    payload.completed === true ||
    status === "completed" ||
    status === "complete" ||
    queueStatus === "completed" ||
    queueStatus === "complete"
  ) {
    return "completed";
  }

  if (
    dispositionTag === "FAILED" ||
    dispositionTag === "CANCELED" ||
    errorMessage
  ) {
    return "failed";
  }

  return "failed";
}

function calculateDurationSeconds(
  payload: JsonObject,
) {
  const correctedDuration =
    readNumber(
      payload.corrected_duration,
    );

  if (
    correctedDuration !== null
  ) {
    return Math.max(
      0,
      Math.round(
        correctedDuration,
      ),
    );
  }

  const durationSeconds =
    readNumber(
      payload.call_duration,
    );

  if (
    durationSeconds !== null
  ) {
    return Math.max(
      0,
      Math.round(
        durationSeconds,
      ),
    );
  }

  const callLengthMinutes =
    readNumber(
      payload.call_length,
    );

  if (
    callLengthMinutes !== null
  ) {
    return Math.max(
      0,
      Math.round(
        callLengthMinutes * 60,
      ),
    );
  }

  return null;
}

function createHeaderRecord(
  request: NextRequest,
): JsonObject {
  const headers: JsonObject = {};

  request.headers.forEach(
    (value, key) => {
      if (
        key.toLowerCase() !==
        "authorization"
      ) {
        headers[key] = value;
      }
    },
  );

  return headers;
}

export async function POST(
  request: NextRequest,
  context: RouteContext,
) {
  const {
    connectionId,
  } = await context.params;

  if (
    !UUID_PATTERN.test(
      connectionId,
    )
  ) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Invalid provider connection.",
      },
      {
        status: 400,
      },
    );
  }

  const rawBody =
    await request.text();

  if (!rawBody.trim()) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Webhook body is required.",
      },
      {
        status: 400,
      },
    );
  }

  const admin =
    createAdminClient();

  const {
    data: connectionData,
    error: connectionError,
  } = await admin
    .from(
      "ai_call_provider_connections",
    )
    .select(
      [
        "id",
        "status",
        "webhook_secret_reference",
      ].join(","),
    )
    .eq(
      "id",
      connectionId,
    )
    .single();

  if (
    connectionError ||
    !connectionData
  ) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Provider connection was not found.",
      },
      {
        status: 404,
      },
    );
  }

  const connection =
    connectionData as unknown as ProviderConnection;

  if (
    connection.status !== "active"
  ) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Provider connection is inactive.",
      },
      {
        status: 409,
      },
    );
  }

  let webhookSecret: string;

  try {
    webhookSecret =
      resolveAiCallSecret(
        connection
          .webhook_secret_reference,
      );
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Webhook verification is not configured.",
      },
      {
        status: 503,
      },
    );
  }

  const signature =
    request.headers.get(
      "x-webhook-signature",
    );

  const signatureValid =
    verifyBlandWebhookSignature(
      rawBody,
      signature,
      webhookSecret,
    );

  if (!signatureValid) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Invalid webhook signature.",
      },
      {
        status: 401,
      },
    );
  }

  let payload: JsonObject;

  try {
    const parsed: unknown =
      JSON.parse(rawBody);

    if (
      typeof parsed !== "object" ||
      parsed === null ||
      Array.isArray(parsed)
    ) {
      throw new Error(
        "Webhook payload must be an object.",
      );
    }

    payload =
      parsed as JsonObject;
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Invalid webhook JSON.",
      },
      {
        status: 400,
      },
    );
  }

  const providerCallId =
    readString(
      payload.call_id,
    ) ||
    readString(
      payload.c_id,
    );

  if (!providerCallId) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Webhook call ID is missing.",
      },
      {
        status: 400,
      },
    );
  }

  const terminalStatus =
    determineTerminalStatus(
      payload,
    );

  const eventType =
    `call.${terminalStatus}`;

  const providerEventId =
    readString(
      payload.event_id,
    ) ||
    [
      providerCallId,
      eventType,
      readString(
        payload.end_at,
      ) ||
        readString(
          payload.status,
        ) ||
        "final",
    ].join(":");

  const eventTimestamp =
    readString(
      payload.end_at,
    ) ||
    readString(
      payload.created_at,
    ) ||
    null;

  const {
    data: webhookEventData,
    error: ingestError,
  } = await admin.rpc(
    "ingest_ai_call_webhook_event",
    {
      requested_provider_connection_id:
        connection.id,

      requested_event_type:
        eventType,

      requested_payload:
        payload,

      requested_headers:
        createHeaderRecord(
          request,
        ),

      requested_provider_event_id:
        providerEventId,

      requested_provider_call_id:
        providerCallId,

      requested_event_timestamp:
        eventTimestamp,

      requested_signature_valid:
        true,
    },
  );

  if (
    ingestError ||
    !webhookEventData
  ) {
    return NextResponse.json(
      {
        ok: false,
        error:
          ingestError?.message ??
          "Webhook could not be ingested.",
      },
      {
        status: 500,
      },
    );
  }

  const webhookEvent =
    webhookEventData as unknown as WebhookEventRecord;

  if (
    webhookEvent.processing_status ===
      "processed" ||
    webhookEvent.processing_status ===
      "ignored"
  ) {
    return NextResponse.json({
      ok: true,
      duplicate: true,
      eventId:
        webhookEvent.id,
    });
  }

  const {
    data: claimedEventData,
    error: claimEventError,
  } = await admin
    .from(
      "ai_call_webhook_events",
    )
    .update({
      processing_status:
        "processing",
    })
    .eq(
      "id",
      webhookEvent.id,
    )
    .in(
      "processing_status",
      [
        "received",
        "failed",
      ],
    )
    .select("id")
    .maybeSingle();

  if (claimEventError) {
    return NextResponse.json(
      {
        ok: false,
        error:
          claimEventError.message,
      },
      {
        status: 500,
      },
    );
  }

  if (!claimedEventData) {
    return NextResponse.json({
      ok: true,
      duplicate: true,
      eventId:
        webhookEvent.id,
    });
  }

  if (
    !webhookEvent.call_attempt_id
  ) {
    await admin
      .from(
        "ai_call_webhook_events",
      )
      .update({
        processing_status:
          "ignored",

        processed_at:
          new Date().toISOString(),

        error_message:
          "No matching AI call attempt was found.",
      })
      .eq(
        "id",
        webhookEvent.id,
      );

    return NextResponse.json(
      {
        ok: true,
        ignored: true,
        eventId:
          webhookEvent.id,
      },
      {
        status: 202,
      },
    );
  }

  const errorMessage =
    readString(
      payload.error_message,
    ) || null;

  const providerCurrency =
    readString(
      payload.currency,
    ) || null;

  const recordingUrl =
    readString(
      payload.recording_url,
    ) || null;

  const resultData: JsonObject = {
    summary:
      readString(
        payload.summary,
      ) || null,

    answered_by:
      readString(
        payload.answered_by,
      ) || null,

    disposition_tag:
      readString(
        payload.disposition_tag,
      ) || null,

    call_ended_by:
      readString(
        payload.call_ended_by,
      ) || null,

    concatenated_transcript:
      readString(
        payload.concatenated_transcript,
      ) || null,
  };

    const rawTranscript =
    readString(
      payload.concatenated_transcript,
    );

  const transcriptSegments =
    Array.isArray(
      payload.transcripts,
    )
      ? payload.transcripts
      : [];

  const correctedTranscript =
    Array.isArray(
      payload.corrected_transcript,
    )
      ? payload.corrected_transcript
      : [];

  const variablesValue =
    payload.variables;

  const webhookVariables =
    typeof variablesValue ===
      "object" &&
    variablesValue !== null &&
    !Array.isArray(
      variablesValue,
    )
      ? variablesValue
      : {};

  const languageCode =
    readString(
      payload.language,
    ) ||
    readString(
      webhookVariables.language,
    ) ||
    null;

  if (
    rawTranscript ||
    transcriptSegments.length > 0 ||
    correctedTranscript.length > 0
  ) {
    const providerTranscript: JsonObject = {
      transcripts:
        transcriptSegments,

      corrected_transcript:
        correctedTranscript,
    };

    const entities =
      typeof payload.entities ===
        "object" &&
      payload.entities !== null &&
      !Array.isArray(
        payload.entities,
      )
        ? payload.entities
        : {};

    const objections =
      Array.isArray(
        payload.objections,
      )
        ? payload.objections
        : [];

    const commitments =
      Array.isArray(
        payload.commitments,
      )
        ? payload.commitments
        : [];

    const {
      error: transcriptError,
    } = await admin.rpc(
      "upsert_ai_call_transcript",
      {
        requested_call_attempt_id:
          webhookEvent.call_attempt_id,

        requested_raw_transcript:
          rawTranscript,

        requested_provider_transcript:
          providerTranscript,

        requested_language_code:
          languageCode,

        requested_summary:
          readString(
            payload.summary,
          ) || null,

        requested_sentiment:
          readString(
            payload.sentiment,
          ) || null,

        requested_sentiment_score:
          readNumber(
            payload.sentiment_score,
          ),

        requested_entities:
          entities,

        requested_objections:
          objections,

        requested_commitments:
          commitments,
      },
    );

    if (transcriptError) {
      await admin
        .from(
          "ai_call_webhook_events",
        )
        .update({
          processing_status:
            "failed",

          error_message:
            transcriptError.message,
        })
        .eq(
          "id",
          webhookEvent.id,
        );

      return NextResponse.json(
        {
          ok: false,
          error:
            transcriptError.message,
        },
        {
          status: 500,
        },
      );
    }
  }

  const {
    error: completionError,
  } = await admin.rpc(
    "complete_ai_call_attempt",
    {
      requested_call_attempt_id:
        webhookEvent.call_attempt_id,

      requested_status:
        terminalStatus,

      requested_disposition_code:
        terminalStatus ===
        "failed"
          ? "provider_failure"
          : null,

      requested_call_duration_seconds:
        calculateDurationSeconds(
          payload,
        ),

      requested_recording_url:
        recordingUrl,

      requested_provider_cost:
        readNumber(
          payload.price,
        ),

      requested_provider_currency:
        providerCurrency,

      requested_result_data:
        resultData,

      requested_error_code:
        terminalStatus ===
        "failed"
          ? "provider_call_failed"
          : null,

      requested_error_message:
        errorMessage,

      requested_error_data:
        terminalStatus ===
        "failed"
          ? {
              provider_status:
                readString(
                  payload.status,
                ) || null,

              queue_status:
                readString(
                  payload.queue_status,
                ) || null,
            }
          : {},
    },
  );

  if (completionError) {
    await admin
      .from(
        "ai_call_webhook_events",
      )
      .update({
        processing_status:
          "failed",

        error_message:
          completionError.message,
      })
      .eq(
        "id",
        webhookEvent.id,
      );

    return NextResponse.json(
      {
        ok: false,
        error:
          completionError.message,
      },
      {
        status: 500,
      },
    );
  }

  const {
    error: processedError,
  } = await admin
    .from(
      "ai_call_webhook_events",
    )
    .update({
      processing_status:
        "processed",

      processed_at:
        new Date().toISOString(),

      error_message:
        null,
    })
    .eq(
      "id",
      webhookEvent.id,
    );

  if (processedError) {
    return NextResponse.json(
      {
        ok: false,
        error:
          processedError.message,
      },
      {
        status: 500,
      },
    );
  }

  return NextResponse.json({
    ok: true,
    eventId:
      webhookEvent.id,
    callId:
      providerCallId,
    status:
      terminalStatus,
  });
}