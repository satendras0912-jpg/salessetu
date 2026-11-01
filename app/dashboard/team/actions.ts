"use server";

import { revalidatePath } from "next/cache";

import {
  requirePermissionAccess,
} from "@/lib/auth/access-control";
import {
  createAdminClient,
} from "@/lib/supabase/admin";
import {
  createClient,
} from "@/lib/supabase/server";

import type {
  TeamActionState,
} from "@/lib/team/team-action-contract";

function createErrorState(
  message: string,
  fieldErrors: Record<string, string[]> = {},
): TeamActionState {
  return {
    status: "error",
    message,
    fieldErrors,
  };
}

function normalizeEmail(value: FormDataEntryValue | null): string {
  return String(value ?? "").trim().toLowerCase();
}

function normalizeName(value: FormDataEntryValue | null): string {
  return String(value ?? "").trim().replace(/\s+/g, " ");
}

function getApplicationUrl(): string {
  const configuredUrl =
    process.env.NEXT_PUBLIC_APP_URL?.trim();

  if (configuredUrl) {
    return configuredUrl.replace(/\/+$/, "");
  }

  const productionUrl =
    process.env.VERCEL_PROJECT_PRODUCTION_URL?.trim();

  if (productionUrl) {
    return `https://${productionUrl
      .replace(/^https?:\/\//, "")
      .replace(/\/+$/, "")}`;
  }

  const deploymentUrl = process.env.VERCEL_URL?.trim();

  if (deploymentUrl) {
    return `https://${deploymentUrl
      .replace(/^https?:\/\//, "")
      .replace(/\/+$/, "")}`;
  }

  return "http://localhost:3000";
}

function getOrganizationId(
  organizationId: string | undefined,
): string | null {
  return organizationId?.trim() || null;
}

export async function inviteSalesAgentAction(
  previousState: TeamActionState,
  formData: FormData,
): Promise<TeamActionState> {
  void previousState;

  const displayName = normalizeName(formData.get("displayName"));
  const email = normalizeEmail(formData.get("email"));
  const fieldErrors: Record<string, string[]> = {};

  if (!displayName) {
    fieldErrors.displayName = ["Enter the agent's full name."];
  } else if (displayName.length > 120) {
    fieldErrors.displayName = [
      "Use no more than 120 characters.",
    ];
  }

  if (!email) {
    fieldErrors.email = ["Enter the agent's email address."];
  } else if (
    !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)
  ) {
    fieldErrors.email = ["Enter a valid email address."];
  }

  if (Object.keys(fieldErrors).length > 0) {
    return createErrorState(
      "Check the highlighted fields and try again.",
      fieldErrors,
    );
  }

  const { context } = await requirePermissionAccess({
    allOf: ["organization.manage_members"],
    loginRedirectTo: "/login?next=/dashboard/team",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = getOrganizationId(
    context.organization?.id,
  );

  if (!organizationId) {
    return createErrorState(
      "An active workspace is required to add a sales agent.",
    );
  }

  const supabase = await createClient();
  const {
    data: existingUserId,
    error: lookupError,
  } = await supabase.rpc(
    "find_organization_user_by_email",
    {
      p_organization_id: organizationId,
      p_email: email,
    },
  );

  if (lookupError) {
    console.error(
      "Sales-agent user lookup failed:",
      lookupError.message,
    );

    return createErrorState(
      "The agent account could not be checked. Please try again.",
    );
  }

  let userId = existingUserId as string | null;
  let invitationSent = false;

  if (!userId) {
    try {
      const adminClient = createAdminClient();
      const {
        data: invitation,
        error: invitationError,
      } = await adminClient.auth.admin.inviteUserByEmail(
        email,
        {
          redirectTo:
            `${getApplicationUrl()}` +
            "/auth/callback?next=/dashboard",
          data: {
            display_name: displayName,
          },
        },
      );

      if (invitationError || !invitation.user) {
        console.error(
          "Sales-agent invitation failed:",
          invitationError?.message,
        );

        return createErrorState(
          "The invitation could not be sent. Please verify the email and try again.",
        );
      }

      userId = invitation.user.id;
      invitationSent = true;
    } catch (error) {
      console.error(
        "Sales-agent invitation configuration failed:",
        error,
      );

      return createErrorState(
        "Invitations are not configured yet. Ask the workspace administrator to set the Supabase server key.",
      );
    }
  }

  const { error: provisionError } = await supabase.rpc(
    "upsert_organization_sales_agent",
    {
      p_organization_id: organizationId,
      p_user_id: userId,
      p_display_name: displayName,
    },
  );

  if (provisionError) {
    console.error(
      "Sales-agent provisioning failed:",
      provisionError.message,
    );

    return createErrorState(
      invitationSent
        ? "The invitation was created, but workspace access could not be added. Please contact support before asking the agent to sign in."
        : "The existing account could not be added to this workspace.",
    );
  }

  revalidatePath("/dashboard", "layout");
  revalidatePath("/dashboard/team");

  return {
    status: "success",
    message: invitationSent
      ? `Invitation sent to ${email}. The agent can set a password and sign in from the email.`
      : `${email} has been added to this workspace as a Sales Agent.`,
    fieldErrors: {},
  };
}

export async function setSalesAgentStatusAction(
  previousState: TeamActionState,
  formData: FormData,
): Promise<TeamActionState> {
  void previousState;

  const membershipId = String(
    formData.get("membershipId") ?? "",
  ).trim();
  const nextStatus = String(
    formData.get("nextStatus") ?? "",
  )
    .trim()
    .toLowerCase();

  if (!membershipId) {
    return createErrorState("The sales agent was not found.");
  }

  if (
    nextStatus !== "active" &&
    nextStatus !== "suspended" &&
    nextStatus !== "removed"
  ) {
    return createErrorState("Unsupported team action.");
  }

  const { context } = await requirePermissionAccess({
    allOf: ["organization.manage_members"],
    loginRedirectTo: "/login?next=/dashboard/team",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = getOrganizationId(
    context.organization?.id,
  );

  if (!organizationId) {
    return createErrorState(
      "An active workspace is required to update a sales agent.",
    );
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc(
    "set_organization_sales_agent_status",
    {
      p_organization_id: organizationId,
      p_membership_id: membershipId,
      p_next_status: nextStatus,
    },
  );

  if (error) {
    console.error(
      "Sales-agent status update failed:",
      error.message,
    );

    return createErrorState(
      "The sales-agent access could not be updated. It may already have changed.",
    );
  }

  revalidatePath("/dashboard", "layout");
  revalidatePath("/dashboard/team");

  const messages: Record<string, string> = {
    active: "Sales agent restored. Manual lead routing remains off.",
    suspended:
      "Sales agent suspended. They cannot access this workspace or receive new leads.",
    removed:
      "Sales agent removed from this workspace. Their Auth account and historical records were retained.",
  };

  return {
    status: "success",
    message: messages[nextStatus],
    fieldErrors: {},
  };
}
