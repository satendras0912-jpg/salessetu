import "server-only";

import type {
  AiCallProviderAdapter,
  DispatchAiCallInput,
  DispatchAiCallResult,
  JsonObject,
} from "./contract";

const DEFAULT_API_BASE_URL =
  "https://api.bland.ai/v1";

const DEFAULT_TIMEOUT_MS = 30_000;

type BlandAiProviderOptions = {
  apiKey: string;
  apiBaseUrl?: string;
  requestTimeoutMs?: number;
};

export class BlandAiProviderError extends Error {
  readonly httpStatus: number | null;
  readonly providerResponse: JsonObject | null;

  constructor(
    message: string,
    httpStatus: number | null,
    providerResponse: JsonObject | null,
  ) {
    super(message);

    this.name = "BlandAiProviderError";
    this.httpStatus = httpStatus;
    this.providerResponse = providerResponse;
  }
}

function normalizeBaseUrl(
  apiBaseUrl: string,
) {
  return apiBaseUrl
    .trim()
    .replace(/\/+$/, "");
}

function mapLanguageCode(
  languageCode: string,
) {
  const normalized =
    languageCode
      .trim()
      .toLowerCase();

  if (
    normalized === "hi-in" ||
    normalized === "en-in" ||
    normalized === "hinglish"
  ) {
    return "fluent";
  }

  return languageCode.trim();
}

function parseProviderResponse(
  rawBody: string,
): JsonObject {
  if (!rawBody) {
    return {};
  }

  try {
    const parsed: unknown =
      JSON.parse(rawBody);

    if (
      typeof parsed === "object" &&
      parsed !== null &&
      !Array.isArray(parsed)
    ) {
      return parsed as JsonObject;
    }

    return {
      response:
        JSON.stringify(parsed) ??
        "null",
    };
  } catch {
    return {
      raw_response:
        rawBody,
    };
  }
}

function readString(
  value: unknown,
) {
  return typeof value === "string"
    ? value.trim()
    : "";
}

export class BlandAiProviderAdapter
  implements AiCallProviderAdapter {
  readonly providerCode =
    "bland_ai";

  private readonly apiKey: string;
  private readonly apiBaseUrl: string;
  private readonly requestTimeoutMs: number;

  constructor(
    options: BlandAiProviderOptions,
  ) {
    const apiKey =
      options.apiKey.trim();

    if (!apiKey) {
      throw new Error(
        "Bland AI API key is required.",
      );
    }

    this.apiKey = apiKey;

    this.apiBaseUrl =
      normalizeBaseUrl(
        options.apiBaseUrl ??
          DEFAULT_API_BASE_URL,
      );

    this.requestTimeoutMs =
      options.requestTimeoutMs ??
      DEFAULT_TIMEOUT_MS;
  }

  async dispatchCall(
    input: DispatchAiCallInput,
  ): Promise<DispatchAiCallResult> {
    const controller =
      new AbortController();

    const timeoutId =
      setTimeout(
        () => controller.abort(),
        this.requestTimeoutMs,
      );

    const requestData: JsonObject = {
      ...(input.requestData ?? {}),
      salessetu_job_id:
        input.jobId,
      salessetu_attempt_id:
        input.attemptId,
    };

    const metadata: JsonObject = {
      ...(input.metadata ?? {}),
      salessetu_job_id:
        input.jobId,
      salessetu_attempt_id:
        input.attemptId,
    };

    const payload: JsonObject = {
      phone_number:
        input.phoneNumber,

      task:
        input.task,

      language:
        mapLanguageCode(
          input.languageCode,
        ),

      max_duration:
        input.maximumDurationSeconds,

      record:
        input.recordCall,

      webhook:
        input.webhookUrl,

      request_data:
        requestData,

      metadata,
    };

    if (input.fromPhoneNumber) {
      payload.from =
        input.fromPhoneNumber;
    }

    if (input.voiceId) {
      payload.voice =
        input.voiceId;
    }

    if (input.firstSentence) {
      payload.first_sentence =
        input.firstSentence;
    }

    let response: Response;

    try {
      response = await fetch(
        `${this.apiBaseUrl}/calls`,
        {
          method: "POST",

          headers: {
            authorization:
              `Bearer ${this.apiKey}`,

            "content-type":
              "application/json",
          },

          body:
            JSON.stringify(payload),

          cache:
            "no-store",

          signal:
            controller.signal,
        },
      );
    } catch (error) {
      if (
        error instanceof Error &&
        error.name === "AbortError"
      ) {
        throw new BlandAiProviderError(
          "Bland AI did not respond before the dispatch timeout.",
          null,
          null,
        );
      }

      throw new BlandAiProviderError(
        error instanceof Error
          ? `Bland AI request failed: ${error.message}`
          : "Bland AI request failed.",
        null,
        null,
      );
    } finally {
      clearTimeout(timeoutId);
    }

    const rawBody =
      await response.text();

    const providerResponse =
      parseProviderResponse(
        rawBody,
      );

    const providerStatus =
      readString(
        providerResponse.status,
      );

    const providerCallId =
      readString(
        providerResponse.call_id,
      );

    if (
      !response.ok ||
      providerStatus !== "success" ||
      !providerCallId
    ) {
      const providerMessage =
        readString(
          providerResponse.message,
        );

      throw new BlandAiProviderError(
        providerMessage ||
          `Bland AI rejected the call request with HTTP ${response.status}.`,
        response.status,
        providerResponse,
      );
    }

    return {
      providerCallId,
      providerResponse,
    };
  }
}