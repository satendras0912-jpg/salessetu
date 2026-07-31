"use server";

import { revalidatePath } from "next/cache";

import { requirePermissionAccess } from "@/lib/auth/access-control";

import {
  LEAD_FORM_PERMISSIONS,
} from "@/lib/leads/lead-form-contract";

import {
  parseLeadFormData,
} from "@/lib/leads/lead-form-parser";

import {
  createLeadRecord,
  LeadMutationError,
  updateLeadRecord,
} from "@/lib/leads/lead-mutation-service";

import type {
  LeadActionState,
  LeadFieldErrors,
} from "@/types/lead-actions";

function createActionErrorState(
  message: string,
  fieldErrors: LeadFieldErrors = {},
): LeadActionState {
  return {
    status: "error",
    message,
    fieldErrors,
  };
}

function mapMutationErrorToActionState(
  error: unknown,
): LeadActionState {
  if (!(error instanceof LeadMutationError)) {
    console.error(
      "Unexpected lead mutation error:",
      error,
    );

    return createActionErrorState(
      "The lead could not be saved. Please try again.",
    );
  }

  switch (error.kind) {
    case "conflict":
      return {
        status: "conflict",
        message: error.message,
        fieldErrors: {
          expectedUpdatedAt: [
            "The lead has changed since this form was opened.",
          ],
        },
      };

    case "invalid_source":
      return createActionErrorState(
        error.message,
        {
          leadSourceId: [error.message],
        },
      );

    case "not_found":
      return createActionErrorState(
        error.message,
        {
          leadId: [error.message],
        },
      );

    case "permission_denied":
      return createActionErrorState(
        error.message,
      );

    case "constraint_violation":
      return createActionErrorState(
        error.message,
      );

    case "database_error":
    default:
      console.error(
        "Lead database mutation error:",
        error,
      );

      return createActionErrorState(
        error.message,
      );
  }
}

function getOrganizationId(
  organizationId: string | undefined,
): string | null {
  const normalizedOrganizationId =
    organizationId?.trim();

  return normalizedOrganizationId || null;
}

export async function createLeadAction(
  previousState: LeadActionState,
  formData: FormData,
): Promise<LeadActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_FORM_PERMISSIONS.view,
        LEAD_FORM_PERMISSIONS.create,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads/new",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId = getOrganizationId(
    context.organization?.id,
  );

  if (!organizationId) {
    return createActionErrorState(
      "An active organization context is required to create a lead.",
    );
  }

  const parsed = parseLeadFormData(
    formData,
    "create",
  );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors: parsed.fieldErrors,
    };
  }

  try {
    const createdLead = await createLeadRecord(
      organizationId,
      parsed.payload,
    );

    revalidatePath("/dashboard");
    revalidatePath("/dashboard/leads");
    revalidatePath(
      `/dashboard/leads/${createdLead.id}`,
    );

    return {
      status: "success",
      message: "Lead created successfully.",
      fieldErrors: {},
      leadId: createdLead.id,
    };
  } catch (error) {
    return mapMutationErrorToActionState(error);
  }
}

export async function updateLeadAction(
  previousState: LeadActionState,
  formData: FormData,
): Promise<LeadActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_FORM_PERMISSIONS.view,
        LEAD_FORM_PERMISSIONS.update,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId = getOrganizationId(
    context.organization?.id,
  );

  if (!organizationId) {
    return createActionErrorState(
      "An active organization context is required to update a lead.",
    );
  }

  const parsed = parseLeadFormData(
    formData,
    "edit",
  );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors: parsed.fieldErrors,
    };
  }

  try {
    const updatedLead = await updateLeadRecord(
      organizationId,
      parsed.values.leadId,
      parsed.values.expectedUpdatedAt,
      parsed.payload,
    );

    revalidatePath("/dashboard");
    revalidatePath("/dashboard/leads");
    revalidatePath(
      `/dashboard/leads/${updatedLead.id}`,
    );

    return {
      status: "success",
      message: "Lead updated successfully.",
      fieldErrors: {},
      leadId: updatedLead.id,
    };
  } catch (error) {
    return mapMutationErrorToActionState(error);
  }
}