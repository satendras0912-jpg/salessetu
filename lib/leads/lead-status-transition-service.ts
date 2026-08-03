import "server-only";

import { createClient } from "@/lib/supabase/server";

import type {
  LeadStatusTransitionValues,
} from "@/types/lead-operational-controls";

export type LeadStatusTransitionErrorKind =
  | "not_found"
  | "conflict"
  | "permission_denied"
  | "invalid_transition"
  | "database_error";

export type LeadStatusTransitionResult = {
  leadId: string;
  updatedAt: string;
};

type DatabaseErrorLike = {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
};

type ScopedLeadRow = {
  id: string;
};

type TransitionRpcPayload = {
  lead_id?: unknown;
  updated_at?: unknown;

  lead_status?: unknown;
  lifecycle_stage?: unknown;
  lead_temperature?: unknown;
};

type ServerSupabaseClient =
  Awaited<ReturnType<typeof createClient>>;

export class LeadStatusTransitionError
  extends Error {
  readonly kind:
    LeadStatusTransitionErrorKind;

  constructor(
    kind: LeadStatusTransitionErrorKind,
    message: string,
  ) {
    super(message);

    this.name =
      "LeadStatusTransitionError";

    this.kind = kind;
  }
}

function normalizeIdentifier(
  value: string,
  label: string,
): string {
  const normalizedValue =
    value.trim();

  if (!normalizedValue) {
    throw new LeadStatusTransitionError(
      "database_error",
      `${label} is required.`,
    );
  }

  return normalizedValue;
}

function isAmbiguousTimeout(
  error: DatabaseErrorLike,
): boolean {
  const combinedMessage = [
    error.code,
    error.message,
    error.details,
    error.hint,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  return (
    combinedMessage.includes(
      "upstream request timeout",
    ) ||
    combinedMessage.includes(
      "gateway timeout",
    ) ||
    combinedMessage.includes(
      "request timeout",
    ) ||
    combinedMessage.includes(
      "statement timeout",
    ) ||
    combinedMessage.includes(
      "timed out",
    ) ||
    combinedMessage.includes(
      "timeout",
    )
  );
}

function mapDatabaseError(
  error: DatabaseErrorLike,
): LeadStatusTransitionError {
  const message =
    error.message?.trim() ||
    "The lead status could not be changed.";

  const normalizedMessage = [
    error.message,
    error.details,
    error.hint,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  /*
   * Optimistic-concurrency conflict या
   * lock-safe RPC का fast lock conflict.
   */
  if (
    error.code === "40001" ||
    normalizedMessage.includes(
      "changed after the form was opened",
    ) ||
    normalizedMessage.includes(
      "currently being changed by another request",
    )
  ) {
    return new LeadStatusTransitionError(
      "conflict",
      "This lead was changed by another user or request. Reload the latest version before changing its status.",
    );
  }

  /*
   * Database-side permission rejection.
   */
  if (
    error.code === "42501" ||
    normalizedMessage.includes(
      "permission denied",
    )
  ) {
    return new LeadStatusTransitionError(
      "permission_denied",
      "You do not have permission to change this lead's status.",
    );
  }

  /*
   * Lead missing, deleted या current organisation
   * के भीतर accessible नहीं है.
   */
  if (
    normalizedMessage.includes(
      "lead not found",
    )
  ) {
    return new LeadStatusTransitionError(
      "not_found",
      "The lead does not exist or is no longer available.",
    );
  }

  /*
   * PostgreSQL CHECK constraint या invalid
   * enum-like operational value.
   */
  if (
    error.code === "23514" ||
    error.code === "22P02" ||
    normalizedMessage.includes(
      "invalid lead status",
    ) ||
    normalizedMessage.includes(
      "invalid lifecycle stage",
    ) ||
    normalizedMessage.includes(
      "invalid lead temperature",
    )
  ) {
    return new LeadStatusTransitionError(
      "invalid_transition",
      "One or more status-transition values are invalid.",
    );
  }

  /*
   * Timeout पर automatic retry, polling या
   * reconciliation query नहीं चलाई जाएगी.
   *
   * User page reload करके committed state verify करेगा.
   */
  if (isAmbiguousTimeout(error)) {
    return new LeadStatusTransitionError(
      "database_error",
      "The request timed out. Reload the page to verify the latest lead status before trying again.",
    );
  }

  return new LeadStatusTransitionError(
    "database_error",
    message,
  );
}

async function verifyScopedLeadExists(
  supabase: ServerSupabaseClient,
  organizationId: string,
  leadId: string,
): Promise<boolean> {
  const {
    data,
    error,
  } = await supabase
    .from("leads")
    .select("id")
    .eq(
      "organization_id",
      organizationId,
    )
    .eq(
      "id",
      leadId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (error) {
    throw mapDatabaseError(
      error,
    );
  }

  return Boolean(
    data as ScopedLeadRow | null,
  );
}

function getRpcPayload(
  data: unknown,
): TransitionRpcPayload | null {
  /*
   * JSONB-returning RPC सामान्यतः object देती है.
   * कुछ response configurations में single-item
   * array भी मिल सकती है.
   */
  const candidate =
    Array.isArray(data)
      ? data[0]
      : data;

  if (
    typeof candidate !== "object" ||
    candidate === null
  ) {
    return null;
  }

  return candidate as TransitionRpcPayload;
}

function parseRpcResult(
  data: unknown,
  expectedLeadId: string,
): LeadStatusTransitionResult | null {
  const payload =
    getRpcPayload(data);

  if (!payload) {
    return null;
  }

  if (
    typeof payload.lead_id !== "string" ||
    typeof payload.updated_at !== "string"
  ) {
    return null;
  }

  const returnedLeadId =
    payload.lead_id.trim();

  const returnedUpdatedAt =
    payload.updated_at.trim();

  if (
    returnedLeadId !== expectedLeadId ||
    !returnedUpdatedAt
  ) {
    return null;
  }

  const parsedUpdatedAt =
    new Date(returnedUpdatedAt);

  if (
    Number.isNaN(
      parsedUpdatedAt.getTime(),
    )
  ) {
    return null;
  }

  return {
    leadId:
      returnedLeadId,

    updatedAt:
      returnedUpdatedAt,
  };
}

export async function transitionLeadStatusRecord(
  organizationId: string,
  values: LeadStatusTransitionValues,
): Promise<LeadStatusTransitionResult> {
  const cleanOrganizationId =
    normalizeIdentifier(
      organizationId,
      "Organization ID",
    );

  const cleanLeadId =
    normalizeIdentifier(
      values.leadId,
      "Lead ID",
    );

  const cleanExpectedUpdatedAt =
    normalizeIdentifier(
      values.expectedUpdatedAt,
      "Expected update timestamp",
    );

  const normalizedValues:
    LeadStatusTransitionValues = {
      ...values,

      leadId:
        cleanLeadId,

      expectedUpdatedAt:
        cleanExpectedUpdatedAt,

      leadStatus:
        values.leadStatus,

      lifecycleStage:
        values.lifecycleStage,

      leadTemperature:
        values.leadTemperature.trim() as
          LeadStatusTransitionValues["leadTemperature"],

      reason:
        values.reason.trim(),
    };

  const supabase =
    await createClient();

  /*
   * Query 1:
   * Organisation-scoped lookup.
   *
   * Browser से organisation ID स्वीकार नहीं की जाती.
   * यह cross-organisation lead ID को RPC call से पहले
   * reject करती है.
   */
  const scopedLeadExists =
    await verifyScopedLeadExists(
      supabase,
      cleanOrganizationId,
      cleanLeadId,
    );

  if (!scopedLeadExists) {
    throw new LeadStatusTransitionError(
      "not_found",
      "The lead does not exist or is no longer available.",
    );
  }

  /*
   * Query 2:
   * एकमात्र mutation RPC.
   *
   * इसमें:
   * - optimistic concurrency
   * - short lock timeout
   * - permission validation
   * - compact JSONB response
   *
   * database स्तर पर handled हैं.
   */
  const {
    data: transitionData,
    error: transitionError,
  } = await supabase.rpc(
    "transition_lead_status_v2",
    {
      requested_lead_id:
        cleanLeadId,

      requested_status:
        normalizedValues.leadStatus,

      requested_lifecycle_stage:
        normalizedValues.lifecycleStage,

      requested_temperature:
        normalizedValues.leadTemperature,

      requested_reason:
        normalizedValues.reason,

      requested_expected_updated_at:
        cleanExpectedUpdatedAt,
    },
  );

  if (transitionError) {
    /*
     * कोई automatic retry नहीं.
     * कोई polling नहीं.
     * कोई reconciliation SELECT नहीं.
     *
     * इससे timeout के समय database पर repeated load
     * और duplicate mutation risk नहीं बढ़ेगा.
     */
    throw mapDatabaseError(
      transitionError,
    );
  }

  const rpcResult =
    parseRpcResult(
      transitionData,
      cleanLeadId,
    );

  if (!rpcResult) {
    /*
     * Unexpected response पर भी database को दोबारा
     * read नहीं किया जाएगा. User reload करके state
     * verify करेगा.
     */
    throw new LeadStatusTransitionError(
      "database_error",
      "The status transition completed, but its response could not be verified. Reload the page to check the latest lead status.",
    );
  }

  return rpcResult;
}