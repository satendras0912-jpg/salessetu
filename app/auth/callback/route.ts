import {
  NextResponse,
  type NextRequest,
} from "next/server";

import { createClient } from "@/lib/supabase/server";

const allowedNextPaths = new Set([
  "/update-password",
]);

function getSafeNextPath(value: string | null) {
  if (value && allowedNextPaths.has(value)) {
    return value;
  }

  return "/update-password";
}

export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);

  const code =
    requestUrl.searchParams.get("code");

  const nextPath = getSafeNextPath(
    requestUrl.searchParams.get("next"),
  );

  if (!code) {
    return NextResponse.redirect(
      new URL(
        "/auth-error?reason=recovery-link-invalid",
        requestUrl.origin,
      ),
    );
  }

  const supabase = await createClient();

  const { error } =
    await supabase.auth.exchangeCodeForSession(
      code,
    );

  if (error) {
    console.error(
      "Password recovery code exchange failed:",
      error.message,
    );

    return NextResponse.redirect(
      new URL(
        "/auth-error?reason=recovery-link-invalid",
        requestUrl.origin,
      ),
    );
  }

  return NextResponse.redirect(
    new URL(nextPath, requestUrl.origin),
  );
}