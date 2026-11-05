"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { LEAD_FORM_PERMISSIONS } from "@/lib/leads/lead-form-contract";
import { createClient } from "@/lib/supabase/server";

function pageHref(
  leadId: string,
  state: "reviewed" | "error",
  detail: string,
): string {
  const query = new URLSearchParams({
    matchReview: state === "reviewed" ? "1" : "",
    matchReviewDecision: detail,
    matchReviewError: state === "error" ? "1" : "",
  });

  return `/dashboard/leads/${leadId}?${query.toString()}`;
}

export async function decideLeadInventoryMatchAction(
  formData: FormData,
): Promise<void> {
  const leadId = String(formData.get("leadId") ?? "").trim();
  const inventoryUnitId = String(formData.get("inventoryUnitId") ?? "").trim();
  const decision = String(formData.get("decision") ?? "").trim().toLowerCase();
  const reason = String(formData.get("reason") ?? "").trim();
  const notes = String(formData.get("notes") ?? "").trim();

  if (!leadId || !inventoryUnitId) {
    redirect("/dashboard/leads?matchReviewError=1");
  }

  if (!["suitable", "not_suitable"].includes(decision)) {
    redirect(pageHref(leadId, "error", "Select a valid review decision."));
  }

  if (reason.length < 3 || reason.length > 500) {
    redirect(pageHref(leadId, "error", "Reason must contain between 3 and 500 characters."));
  }

  if (notes.length > 2000) {
    redirect(pageHref(leadId, "error", "Notes cannot exceed 2000 characters."));
  }

  await requirePermissionAccess({
    allOf: [
      LEAD_FORM_PERMISSIONS.view,
      "inventory.view",
      "inventory.match_review",
    ],
    loginRedirectTo: `/login?next=/dashboard/leads/${leadId}`,
    unauthorizedRedirectTo: "/unauthorized",
  });

  const supabase = await createClient();
  const { error } = await supabase.rpc(
    "decide_lead_inventory_match_review",
    {
      p_lead_id: leadId,
      p_inventory_unit_id: inventoryUnitId,
      p_decision: decision,
      p_reason: reason,
      p_notes: notes || null,
    },
  );

  if (error) {
    redirect(pageHref(leadId, "error", error.message));
  }

  revalidatePath("/dashboard/leads");
  revalidatePath(`/dashboard/leads/${leadId}`);

  redirect(pageHref(leadId, "reviewed", decision));
}
