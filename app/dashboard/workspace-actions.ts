"use server";

import { revalidatePath } from "next/cache";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

import {
  ACTIVE_ORGANIZATION_COOKIE,
  ACTIVE_ORGANIZATION_COOKIE_MAX_AGE,
} from "@/lib/auth/current-context";
import { createClient } from "@/lib/supabase/server";

export async function switchWorkspace(
  formData: FormData,
): Promise<void> {
  const organizationId = String(
    formData.get("organizationId") ?? "",
  ).trim();

  if (!organizationId) {
    redirect("/dashboard/context");
  }

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login?next=/dashboard");
  }

  const { data: membership, error } = await supabase
    .from("organization_members")
    .select("id")
    .eq("organization_id", organizationId)
    .eq("user_id", user.id)
    .eq("membership_status", "active")
    .maybeSingle();

  if (error || !membership) {
    redirect("/unauthorized");
  }

  const cookieStore = await cookies();

  cookieStore.set(ACTIVE_ORGANIZATION_COOKIE, organizationId, {
    httpOnly: true,
    maxAge: ACTIVE_ORGANIZATION_COOKIE_MAX_AGE,
    path: "/",
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
  });

  revalidatePath("/dashboard", "layout");
  redirect("/dashboard");
}
