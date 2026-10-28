export const RECOVERY_ERROR_PATH = "/auth-error?reason=recovery-link-invalid";

export function recoveryLandingDestination(params: URLSearchParams): string | null {
  if (params.has("error") || params.has("error_code")) return RECOVERY_ERROR_PATH;
  const code = params.get("code");
  if (code) return `/auth/callback?${new URLSearchParams({ code, next: "/update-password" })}`;
  return null;
}

export function validRecoveryHash(value: unknown): value is string {
  return typeof value === "string" && /^(?:pkce_)?[a-f0-9]{32,128}$/i.test(value);
}
