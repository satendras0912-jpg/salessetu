"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { LEAD_FORM_PERMISSIONS } from "@/lib/leads/lead-form-contract";
import { createClient } from "@/lib/supabase/server";

const REVIEW_PERMISSION = "lead_validation.review";

function pageHref(
  state: "updated" | "error",
  detail: string,
): string {
  const query = new URLSearchParams({
    [state]: detail,
  });

  return `/dashboard/lead-validation?${query.toString()}`;
}

export async function decideManualLeadValidationAction(
  formData: FormData,
): Promise<void> {
  const leadId = String(formData.get("leadId") ?? "").trim();
  const decision = String(formData.get("decision") ?? "")
    .trim()
    .toLowerCase();
  const reason = String(formData.get("reason") ?? "").trim();
  const notes = String(formData.get("notes") ?? "").trim();

  if (!leadId || !["approved", "hold", "rejected"].includes(decision)) {
    redirect(pageHref("error", "Please select a valid lead decision."));
  }

  if (reason.length < 3 || reason.length > 500) {
    redirect(
      pageHref(
        "error",
        "Reason must contain between 3 and 500 characters.",
      ),
    );
  }

  if (notes.length > 2000) {
    redirect(
      pageHref(
        "error",
        "Notes cannot exceed 2000 characters.",
      ),
    );
  }

  const { context } = await requirePermissionAccess({
    allOf: [
      LEAD_FORM_PERMISSIONS.view,
      REVIEW_PERMISSION,
    ],

    loginRedirectTo: "/login?next=/dashboard/lead-validation",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    redirect(
      pageHref(
        "error",
        "An active organization context is required.",
      ),
    );
  }

  const supabase = await createClient();

  const { error } = await supabase.rpc(
    "decide_manual_lead_validation",
    {
      p_lead_id: leadId,
      p_decision: decision,
      p_reason: reason,
      p_notes: notes || null,
    },
  );

  if (error) {
    redirect(
      pageHref(
        "error",
        `Decision was not saved: ${error.message}`,
      ),
    );
  }

  revalidatePath("/dashboard/lead-validation");
  revalidatePath("/dashboard/leads");
  revalidatePath(`/dashboard/leads/${leadId}`);

  redirect(pageHref("updated", decision));
}


export async function grantManualLeadValidationOverrideAction(
  formData: FormData,
): Promise<void> {
  const leadId = String(formData.get("leadId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const notes = String(formData.get("notes") ?? "").trim();

  if (!leadId || reason.length < 3 || reason.length > 500) {
    redirect(
      pageHref(
        "error",
        "Override reason must contain between 3 and 500 characters.",
      ),
    );
  }

  if (notes.length > 2000) {
    redirect(pageHref("error", "Override notes cannot exceed 2000 characters."));
  }

  const { context } = await requirePermissionAccess({
    allOf: [
      LEAD_FORM_PERMISSIONS.view,
      REVIEW_PERMISSION,
    ],
    loginRedirectTo: "/login?next=/dashboard/lead-validation",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    redirect(
      pageHref(
        "error",
        "Only the workspace owner can grant an override.",
      ),
    );
  }

  const supabase = await createClient();

  const { error } = await supabase.rpc(
    "grant_manual_lead_validation_override",
    {
      p_lead_id: leadId,
      p_override_reason: reason,
      p_notes: notes || null,
    },
  );

  if (error) {
    redirect(
      pageHref(
        "error",
        `Override was not saved: ${error.message}`,
      ),
    );
  }

  revalidatePath("/dashboard/lead-validation");
  revalidatePath("/dashboard/leads");
  revalidatePath(`/dashboard/leads/${leadId}`);

  redirect(pageHref("updated", "owner override"));
}


export async function revokeManualLeadValidationOverrideAction(
  formData: FormData,
): Promise<void> {
  const leadId = String(formData.get("leadId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();

  if (!leadId || reason.length < 3 || reason.length > 500) {
    redirect(
      pageHref(
        "error",
        "Revoke reason must contain between 3 and 500 characters.",
      ),
    );
  }

  const { context } = await requirePermissionAccess({
    allOf: [
      LEAD_FORM_PERMISSIONS.view,
      REVIEW_PERMISSION,
    ],
    loginRedirectTo: "/login?next=/dashboard/lead-validation",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    redirect(
      pageHref(
        "error",
        "Only the workspace owner can revoke an override.",
      ),
    );
  }

  const supabase = await createClient();

  const { error } = await supabase.rpc(
    "revoke_manual_lead_validation_override",
    {
      p_lead_id: leadId,
      p_revoke_reason: reason,
    },
  );

  if (error) {
    redirect(
      pageHref(
        "error",
        `Override was not revoked: ${error.message}`,
      ),
    );
  }

  revalidatePath("/dashboard/lead-validation");
  revalidatePath("/dashboard/leads");
  revalidatePath(`/dashboard/leads/${leadId}`);

  redirect(pageHref("updated", "owner override revoked"));
}
