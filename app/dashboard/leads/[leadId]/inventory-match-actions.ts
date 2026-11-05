"use server";

import { revalidatePath } from "next/cache";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import type { InventoryMatchReviewActionState } from "@/lib/inventory/lead-inventory-match-review-contract";
import { LEAD_FORM_PERMISSIONS } from "@/lib/leads/lead-form-contract";
import { createClient } from "@/lib/supabase/server";

export async function decideLeadInventoryMatchAction(
  previousState: InventoryMatchReviewActionState,
  formData: FormData,
): Promise<InventoryMatchReviewActionState> {
  void previousState;

  const leadId = String(formData.get("leadId") ?? "").trim();
  const inventoryUnitId = String(formData.get("inventoryUnitId") ?? "").trim();
  const decision = String(formData.get("decision") ?? "").trim().toLowerCase();
  const reason = String(formData.get("reason") ?? "").trim();
  const notes = String(formData.get("notes") ?? "").trim();

  if (!leadId || !inventoryUnitId) {
    return {
      status: "error",
      message: "A valid lead and inventory unit are required.",
    };
  }

  if (!["suitable", "not_suitable"].includes(decision)) {
    return {
      status: "error",
      message: "Select a valid review decision.",
    };
  }

  if (reason.length < 3 || reason.length > 500) {
    return {
      status: "error",
      message: "Reason must contain between 3 and 500 characters.",
    };
  }

  if (notes.length > 2000) {
    return {
      status: "error",
      message: "Notes cannot exceed 2000 characters.",
    };
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

  try {
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
      return {
        status: "error",
        message: `Review was not saved: ${error.message}`,
      };
    }

    revalidatePath("/dashboard/leads");
    revalidatePath(`/dashboard/leads/${leadId}`);

    return {
      status: "success",
      message: decision === "not_suitable"
        ? "Inventory suggestion marked not suitable."
        : "Inventory suggestion marked suitable.",
    };
  } catch (error) {
    console.error("Inventory match review action failed", {
      leadId,
      inventoryUnitId,
      error,
    });

    return {
      status: "error",
      message: "Review could not be saved. No operational records were changed.",
    };
  }
}
