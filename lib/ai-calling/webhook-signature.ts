import "server-only";

import {
  createHmac,
  timingSafeEqual,
} from "node:crypto";

const SHA256_HEX_PATTERN =
  /^[a-f0-9]{64}$/i;

function normalizeSignature(
  signature: string,
) {
  const cleanSignature =
    signature.trim();

  if (
    cleanSignature
      .toLowerCase()
      .startsWith("sha256=")
  ) {
    return cleanSignature.slice(
      "sha256=".length,
    );
  }

  return cleanSignature;
}

export function verifyBlandWebhookSignature(
  rawBody: string,
  providedSignature: string | null,
  webhookSecret: string,
) {
  if (
    !providedSignature ||
    !webhookSecret
  ) {
    return false;
  }

  const normalizedSignature =
    normalizeSignature(
      providedSignature,
    );

  if (
    !SHA256_HEX_PATTERN.test(
      normalizedSignature,
    )
  ) {
    return false;
  }

  const expectedSignature =
    createHmac(
      "sha256",
      webhookSecret,
    )
      .update(rawBody)
      .digest("hex");

  const providedBuffer =
    Buffer.from(
      normalizedSignature,
      "hex",
    );

  const expectedBuffer =
    Buffer.from(
      expectedSignature,
      "hex",
    );

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