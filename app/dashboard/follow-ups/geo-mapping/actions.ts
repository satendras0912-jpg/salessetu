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

export async function saveLeadGeoTagAction(
  formData: FormData,
): Promise<void> {
  const leadId = value(formData, "leadId");
  const geoTag = value(formData, "geoTag");

  if (!UUID_PATTERN.test(leadId) || !isGeoTag(geoTag)) {
    redirect("/dashboard/follow-ups/geo-mapping?error=invalid");
  }

  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "leads.update", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/geo-mapping",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;
  if (!organizationId) {
    redirect("/auth-error?reason=organization_context_missing");
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leads")
    .update({ geo_tag: geoTag })
    .eq("id", leadId)
    .eq("organization_id", organizationId)
    .is("deleted_at", null)
    .is("geo_tag", null)
    .select("id")
    .maybeSingle();

  if (error || !data) {
    redirect("/dashboard/follow-ups/geo-mapping?error=changed");
  }

  revalidatePath("/dashboard/follow-ups");
  revalidatePath("/dashboard/follow-ups/geo-mapping");
  revalidatePath(`/dashboard/leads/${leadId}`);
  redirect("/dashboard/follow-ups/geo-mapping?updated=1");
}
