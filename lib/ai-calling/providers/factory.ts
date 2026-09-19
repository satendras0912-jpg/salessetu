import "server-only";

import { BlandAiProviderAdapter } from "./bland";

import type {
  AiCallProviderAdapter,
} from "./contract";

const SECRET_REFERENCE_PATTERN =
  /^AI_CALL_[A-Z0-9_]+$/;

export type CreateAiCallProviderInput = {
  providerCode: string;
  credentialsReference: string | null;
  apiBaseUrl?: string | null;
};

export class AiCallProviderConfigurationError
  extends Error {
  constructor(message: string) {
    super(message);

    this.name =
      "AiCallProviderConfigurationError";
  }
}

export function resolveAiCallSecret(
  reference: string | null,
) {
  const cleanReference =
    reference?.trim() ?? "";

  if (!cleanReference) {
    throw new AiCallProviderConfigurationError(
      "AI calling credentials reference is missing.",
    );
  }

  if (
    !SECRET_REFERENCE_PATTERN.test(
      cleanReference,
    )
  ) {
    throw new AiCallProviderConfigurationError(
      "AI calling credentials reference is invalid.",
    );
  }

  const secret =
    process.env[cleanReference]?.trim();

  if (!secret) {
    throw new AiCallProviderConfigurationError(
      `Server secret ${cleanReference} is missing.`,
    );
  }

  return secret;
}

export function createAiCallProvider(
  input: CreateAiCallProviderInput,
): AiCallProviderAdapter {
  const providerCode =
    input.providerCode
      .trim()
      .toLowerCase();

  switch (providerCode) {
    case "bland_ai": {
      const apiKey =
        resolveAiCallSecret(
          input.credentialsReference,
        );

      return new BlandAiProviderAdapter({
        apiKey,

        apiBaseUrl:
          input.apiBaseUrl?.trim() ||
          undefined,
      });
    }

    default:
      throw new AiCallProviderConfigurationError(
        `AI calling provider ${providerCode || "unknown"} is not supported.`,
      );
  }
}