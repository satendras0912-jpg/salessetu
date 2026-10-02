import { timingSafeEqual } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";

import { createAdminClient } from "@/lib/supabase/admin";
import {
  processAiCallQualification,
} from "@/lib/ai-calling/qualification-service";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

// Recovery is restricted to the completed test call.
const RECOVERY_ATTEMPT_ID =
  "136b44a7-6091-43a8-8966-0127f2aa6752";

export async function POST(request: NextRequest) {
  const expected =
    process.env.AI_CALL_DISPATCH_SECRET?.trim();

  if (!expected || expected.length < 32) {
    return NextResponse.json(
      { ok: false, error: "Recovery is not configured." },
      { status: 503 },
    );
  }

  const authorization =
    request.headers.get("authorization") ?? "";

  const provided = authorization.startsWith("Bearer ")
    ? authorization.slice(7).trim()
    : "";

  const providedBuffer = Buffer.from(provided);
  const expectedBuffer = Buffer.from(expected);

  if (
    providedBuffer.length !== expectedBuffer.length ||
    !timingSafeEqual(providedBuffer, expectedBuffer)
  ) {
    return NextResponse.json(
      { ok: false, error: "Unauthorized." },
      { status: 401 },
    );
  }

  let body: unknown;

  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { ok: false, error: "Invalid JSON." },
      { status: 400 },
    );
  }

  if (
    typeof body !== "object" ||
    body === null ||
    !("callAttemptId" in body) ||
    body.callAttemptId !== RECOVERY_ATTEMPT_ID
  ) {
    return NextResponse.json(
      { ok: false, error: "This recovery attempt is not allowed." },
      { status: 400 },
    );
  }

  try {
    const admin = createAdminClient();

    const { data: attempt, error: attemptError } = await admin
      .from("ai_call_attempts")
      .select("id, call_job_id, provider_call_id, status")
      .eq("id", RECOVERY_ATTEMPT_ID)
      .single();

    if (attemptError || !attempt) {
      return NextResponse.json(
        { ok: false, error: "Unable to load the call attempt." },
        { status: 500 },
      );
    }

    if (
      attempt.status !== "completed" ||
      !attempt.provider_call_id
    ) {
      return NextResponse.json(
        {
          ok: false,
          error: "Recovery requires a completed call with a provider call ID.",
        },
        { status: 409 },
      );
    }

    const { data: job, error: jobError } = await admin
      .from("ai_call_jobs")
      .select("provider_connection_id")
      .eq("id", attempt.call_job_id)
      .single();

    if (jobError || !job?.provider_connection_id) {
      return NextResponse.json(
        { ok: false, error: "Unable to load the provider connection." },
        { status: 500 },
      );
    }

    const result = await processAiCallQualification({
      callAttemptId: attempt.id,
      providerCallId: attempt.provider_call_id,
      providerConnectionId: job.provider_connection_id,
      forceReprocess: true,
    });

    return NextResponse.json({ ok: true, result });
  } catch {
    return NextResponse.json(
      { ok: false, error: "Qualification reprocessing failed." },
      { status: 500 },
    );
  }
}