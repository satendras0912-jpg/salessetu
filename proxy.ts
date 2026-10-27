import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { recoveryLandingDestination } from "@/lib/auth/recovery-routing";

import { updateSession } from "@/lib/supabase/proxy";

export async function proxy(request: NextRequest) {
  if (request.nextUrl.pathname === "/") {
    const destination = recoveryLandingDestination(request.nextUrl.searchParams);
    if (destination) {
      const response = NextResponse.redirect(new URL(destination, request.url));
      response.headers.set("Cache-Control", "no-store");
      response.headers.set("Referrer-Policy", "no-referrer");
      return response;
    }
  }
  return updateSession(request);
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|robots.txt|sitemap.xml|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
