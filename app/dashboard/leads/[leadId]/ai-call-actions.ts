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

import {
  createClient,
} from "@/lib/supabase/server";

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

export type RegisterAiCallConsentState = {
  status: "idle" | "error" | "success";
  message: string | null;
};

export async function registerLeadAiCallConsentAction(
  previousState: RegisterAiCallConsentState,
  formData: FormData,
): Promise<RegisterAiCallConsentState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [
      LEAD_OPERATIONAL_PERMISSIONS.viewLeads,
      "ai_calling.manage_consent",
    ],
    loginRedirectTo: "/login?next=/dashboard/leads",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id?.trim();
  const leadId = readFormValue(formData, "leadId");
  const confirmation = readFormValue(formData, "consentConfirmation");
  const source = readFormValue(formData, "consentSource");
  const evidence = readFormValue(formData, "consentEvidence");

  if (!organizationId || !UUID_PATTERN.test(leadId)) {
    return {
      status: "error",
      message: "A valid lead and active organization are required.",
    };
  }

  if (confirmation !== "confirmed") {
    return {
      status: "error",
      message: "Confirm that the recipient actually granted AI-call consent.",
    };
  }

  if (!["lead_form", "website", "whatsapp", "verbal", "written"].includes(source)) {
    return {
      status: "error",
      message: "Select how consent was received.",
    };
  }

  if (evidence.length < 10 || evidence.length > 2000) {
    return {
      status: "error",
      message: "Describe when and how consent was received (10–2000 characters).",
    };
  }

  const supabase = await createClient();

  const { data: lead, error: leadError } = await supabase
    .from("leads")
    .select("id, phone, normalized_phone")
    .eq("id", leadId)
    .eq("organization_id", organizationId)
    .single();

  if (leadError || !lead) {
    return {
      status: "error",
      message: "The selected lead could not be loaded.",
    };
  }

  const phoneNumber =
    lead.normalized_phone?.trim() || lead.phone?.trim();

  if (!phoneNumber) {
    return {
      status: "error",
      message: "This lead does not have a callable phone number.",
    };
  }

  const { error } = await supabase.rpc(
    "register_ai_call_consent",
    {
      requested_organization_id: organizationId,
      requested_phone_number: phoneNumber,
      requested_consent_status: "granted",
      requested_lead_id: leadId,
      requested_consent_type: "outbound_ai_call",
      requested_consent_source: source,
      requested_consent_text: evidence,
      requested_evidence_data: {
        captured_via: "lead_detail_consent_form",
        operator_attested: true,
        attestation_version: "outbound-ai-call-v1",
      },
    },
  );

  if (error) {
    return {
      status: "error",
      message: `Unable to save AI-call consent: ${error.message}`,
    };
  }

  revalidatePath(`/dashboard/leads/${leadId}`);

  return {
    status: "success",
    message:
      "AI-call consent recorded. No call was queued. Existing blocked jobs remain unchanged.",
  };
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