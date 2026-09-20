"use server";

import { revalidatePath } from "next/cache";
import {
  redirect,
  RedirectType,
} from "next/navigation";

import {
  requirePermissionAccess,
} from "@/lib/auth/access-control";

import {
  queueLeadAiCall,
} from "@/lib/ai-calling/call-queue-service";

import {
  LEAD_OPERATIONAL_PERMISSIONS,
} from "@/lib/leads/lead-operational-contract";

export type QueueAiCallActionState = {
  status: "idle" | "error";
  message: string | null;
  fieldErrors: {
    leadId?: string[];
    requestToken?: string[];
    confirmation?: string[];
  };
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function readFormValue(
  formData: FormData,
  fieldName: string,
): string {
  const value =
    formData.get(fieldName);

  return typeof value === "string"
    ? value.trim()
    : "";
}

export async function queueLeadAiCallAction(
  previousState:
    QueueAiCallActionState,

  formData: FormData,
): Promise<QueueAiCallActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        "ai_calling.execute",
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return {
      status: "error",
      message:
        "An active organization context is required to queue an AI call.",
      fieldErrors: {},
    };
  }

  const leadId =
    readFormValue(
      formData,
      "leadId",
    );

  const requestToken =
    readFormValue(
      formData,
      "requestToken",
    );

  const confirmation =
    readFormValue(
      formData,
      "confirmation",
    );

  const fieldErrors:
    QueueAiCallActionState["fieldErrors"] =
      {};

  if (!UUID_PATTERN.test(leadId)) {
    fieldErrors.leadId = [
      "A valid lead is required.",
    ];
  }

  if (
    !requestToken ||
    requestToken.length > 200
  ) {
    fieldErrors.requestToken = [
      "A valid request token is required.",
    ];
  }

  if (confirmation !== "confirmed") {
    fieldErrors.confirmation = [
      "Confirm the AI call before continuing.",
    ];
  }

  if (
    Object.keys(fieldErrors).length > 0
  ) {
    return {
      status: "error",
      message:
        "Review the AI call request and try again.",
      fieldErrors,
    };
  }

  let result: {
    callJobId: string;
    status: string;
  };

  try {
    result =
      await queueLeadAiCall({
        organizationId,
        leadId,
        idempotencyKey:
          requestToken,
      });
  } catch (error) {
    return {
      status: "error",
      message:
        error instanceof Error
          ? error.message
          : "Unable to queue the AI call.",
      fieldErrors: {},
    };
  }

  revalidatePath(
    `/dashboard/leads/${leadId}`,
  );

  const status =
    encodeURIComponent(
      result.status,
    );

  redirect(
    `/dashboard/leads/${leadId}?aiCallCreated=1&aiCallStatus=${status}`,
    RedirectType.replace,
  );
}