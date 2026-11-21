"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { isGeoTag } from "@/lib/geo/geo-tag-contract";
import { createClient } from "@/lib/supabase/server";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function value(formData: FormData, key: string): string {
  const raw = formData.get(key);
  return typeof raw === "string" ? raw.trim() : "";
}

export async function saveGeoCoverageOwnerAction(
  formData: FormData,
): Promise<void> {
  const geoTag = value(formData, "geoTag");
  const assigneeUserId = value(formData, "assigneeUserId");

  if (!isGeoTag(geoTag) || (assigneeUserId && !UUID_PATTERN.test(assigneeUserId))) {
    redirect("/dashboard/follow-ups/team-onboarding?error=invalid");
  }

  const { context } = await requirePermissionAccess({
    allOf: ["organization.manage_members", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/team-onboarding",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    redirect("/unauthorized");
  }

  const organizationId = context.organization?.id;
  if (!organizationId) {
    redirect("/auth-error?reason=organization_context_missing");
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("configure_geo_coverage_assignment", {
    p_organization_id: organizationId,
    p_geo_tag: geoTag,
    p_assignee_user_id: assigneeUserId || null,
  });

  if (error) {
    console.error("GEO coverage save failed:", error.message);
    redirect("/dashboard/follow-ups/team-onboarding?error=save");
  }

  revalidatePath("/dashboard/pilot-launch");
  revalidatePath("/dashboard/follow-ups/coverage");
  revalidatePath("/dashboard/follow-ups/readiness");
  revalidatePath("/dashboard/follow-ups/team-onboarding");
  redirect("/dashboard/follow-ups/team-onboarding?updated=1");
}
