import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const DEFAULT_WEBHOOK_URL =
  "https://automation.salessetu.in/webhook/sales-lead-attribution";

type LeadCapturePayload = {
  name?: unknown;
  phone?: unknown;
  project?: unknown;
  location?: unknown;
  source?: unknown;
  medium?: unknown;
  campaign?: unknown;
  consent?: unknown;
};

function readRequiredText(value: unknown): string | null {
  if (typeof value !== "string") return null;

  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function readOptionalText(value: unknown, fallback: string): string {
  return readRequiredText(value) ?? fallback;
}

export async function POST(request: NextRequest) {
  let body: LeadCapturePayload;

  try {
    body = (await request.json()) as LeadCapturePayload;
  } catch {
    return NextResponse.json(
      { ok: false, error: "Invalid lead submission." },
      { status: 400 },
    );
  }

  const name = readRequiredText(body.name);
  const phone = readRequiredText(body.phone);
  const project = readRequiredText(body.project);
  const location = readRequiredText(body.location);

  if (!name || !phone || !project || !location || body.consent !== true) {
    return NextResponse.json(
      { ok: false, error: "Complete the required fields and consent." },
      { status: 400 },
    );
  }

  const webhookUrl =
    process.env.LEAD_CAPTURE_WEBHOOK_URL?.trim() || DEFAULT_WEBHOOK_URL;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);

  try {
    const upstream = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        name,
        phone,
        project,
        location,
        source: readOptionalText(body.source, "Website"),
        medium: readOptionalText(body.medium, "Organic"),
        campaign: readOptionalText(body.campaign, "Direct"),
        consent: true,
        consent_source: "salessetu_marketing_demo_form",
        consent_captured_at: new Date().toISOString(),
      }),
      redirect: "error",
      signal: controller.signal,
    });

    if (!upstream.ok) {
      return NextResponse.json(
        { ok: false, error: "Lead intake is temporarily unavailable." },
        { status: 502 },
      );
    }
  } catch {
    return NextResponse.json(
      { ok: false, error: "Lead intake is temporarily unavailable." },
      { status: 502 },
    );
  } finally {
    clearTimeout(timeout);
  }

  return NextResponse.json({ ok: true });
}
