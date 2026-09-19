import {
  randomUUID,
  timingSafeEqual,
} from "node:crypto";

import {
  NextRequest,
  NextResponse,
} from "next/server";

import {
  dispatchNextAiCall,
} from "@/lib/ai-calling/dispatch-service";

export const runtime =
  "nodejs";

export const dynamic =
  "force-dynamic";

export const maxDuration =
  60;

type DispatchRequestBody = {
  organizationId?: unknown;
  workerId?: unknown;
  lockMinutes?: unknown;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function secretsMatch(
  provided: string,
  expected: string,
) {
  const providedBuffer =
    Buffer.from(provided);

  const expectedBuffer =
    Buffer.from(expected);

  if (
    providedBuffer.length !==
    expectedBuffer.length
  ) {
    return false;
  }

  return timingSafeEqual(
    providedBuffer,
    expectedBuffer,
  );
}

function readBearerToken(
  request: NextRequest,
) {
  const authorization =
    request.headers.get(
      "authorization",
    );

  if (
    !authorization ||
    !authorization.startsWith(
      "Bearer ",
    )
  ) {
    return null;
  }

  return authorization
    .slice("Bearer ".length)
    .trim();
}

async function readRequestBody(
  request: NextRequest,
): Promise<DispatchRequestBody> {
  const rawBody =
    await request.text();

  if (!rawBody.trim()) {
    return {};
  }

  const parsed: unknown =
    JSON.parse(rawBody);

  if (
    typeof parsed !== "object" ||
    parsed === null ||
    Array.isArray(parsed)
  ) {
    throw new Error(
      "Request body must be a JSON object.",
    );
  }

  return parsed as DispatchRequestBody;
}

export async function POST(
  request: NextRequest,
) {
  const expectedSecret =
    process.env
      .AI_CALL_DISPATCH_SECRET
      ?.trim();

  if (
    !expectedSecret ||
    expectedSecret.length < 32
  ) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "AI calling dispatch is not configured.",
      },
      {
        status: 503,
      },
    );
  }

  const providedSecret =
    readBearerToken(request);

  if (
    !providedSecret ||
    !secretsMatch(
      providedSecret,
      expectedSecret,
    )
  ) {
    return NextResponse.json(
      {
        ok: false,
        error: "Unauthorized.",
      },
      {
        status: 401,
      },
    );
  }

  let body: DispatchRequestBody;

  try {
    body =
      await readRequestBody(request);
  } catch {
    return NextResponse.json(
      {
        ok: false,
        error:
          "Invalid JSON request body.",
      },
      {
        status: 400,
      },
    );
  }

  const organizationId =
    typeof body.organizationId ===
      "string"
      ? body.organizationId.trim()
      : null;

  if (
    organizationId &&
    !UUID_PATTERN.test(
      organizationId,
    )
  ) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "organizationId must be a valid UUID.",
      },
      {
        status: 400,
      },
    );
  }

  const requestedWorkerId =
    typeof body.workerId === "string"
      ? body.workerId.trim()
      : "";

  const workerId =
    requestedWorkerId ||
    `salessetu-api-${randomUUID()}`;

  const requestedLockMinutes =
    typeof body.lockMinutes ===
      "number"
      ? body.lockMinutes
      : 10;

  if (
    !Number.isInteger(
      requestedLockMinutes,
    ) ||
    requestedLockMinutes < 1 ||
    requestedLockMinutes > 60
  ) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "lockMinutes must be an integer between 1 and 60.",
      },
      {
        status: 400,
      },
    );
  }

  const webhookBaseUrl =
    process.env
      .AI_CALL_WEBHOOK_BASE_URL
      ?.trim() ||
    process.env
      .NEXT_PUBLIC_APP_URL
      ?.trim();

  if (!webhookBaseUrl) {
    return NextResponse.json(
      {
        ok: false,
        error:
          "AI calling webhook base URL is not configured.",
      },
      {
        status: 503,
      },
    );
  }

  try {
    const result =
      await dispatchNextAiCall({
        workerId,
        webhookBaseUrl,
        organizationId,
        lockMinutes:
          requestedLockMinutes,
      });

    if (
      result.status === "failed"
    ) {
      return NextResponse.json(
        {
          ok: false,
          result,
        },
        {
          status: 502,
        },
      );
    }

    return NextResponse.json(
      {
        ok: true,
        result,
      },
      {
        status:
          result.status ===
          "initiated"
            ? 202
            : 200,
      },
    );
  } catch (error) {
    return NextResponse.json(
      {
        ok: false,
        error:
          error instanceof Error
            ? error.message
            : "AI call dispatch failed.",
      },
      {
        status: 500,
      },
    );
  }
}