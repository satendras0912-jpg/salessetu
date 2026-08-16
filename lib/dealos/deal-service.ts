import { createClient } from "@/lib/supabase/server";

import type {
  CancelDealValues,
  ChangeDealStatusValues,
  CreateDealValues,
  DealOSServiceResult,
  LinkDealBookingValues,
  MarkDealLostValues,
  MarkDealWonValues,
  PutDealOnHoldValues,
  UpdateDealValues,
} from "@/types/dealos";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const CURRENCY_CODE_PATTERN =
  /^[A-Z]{3}$/;

type DatabaseErrorLike = {
  code?: string | null;
  message?: string | null;
  details?: string | null;
  hint?: string | null;
};

export type DealOSOperation =
  | "create"
  | "update"
  | "change_status"
  | "create_offer"
  | "update_offer"
  | "request_approval"
  | "decide_approval"
  | "cancel_approval"
  | "link_booking";

export function normalizeDealOptionalText(
  value: string | null | undefined,
): string | null {
  const normalizedValue =
    value?.trim();

  return normalizedValue
    ? normalizedValue
    : null;
}

export function normalizeDealRequiredUuid(
  value: string,
): string | null {
  const normalizedValue =
    value.trim();

  if (
    !normalizedValue ||
    !UUID_PATTERN.test(
      normalizedValue,
    )
  ) {
    return null;
  }

  return normalizedValue;
}

export function normalizeDealOptionalUuid(
  value: string | null | undefined,
): string | null {
  const normalizedValue =
    normalizeDealOptionalText(value);

  if (!normalizedValue) {
    return null;
  }

  return UUID_PATTERN.test(
    normalizedValue,
  )
    ? normalizedValue
    : null;
}

export function normalizeDealTimestamp(
  value: string,
): string | null {
  const normalizedValue =
    value.trim();

  if (!normalizedValue) {
    return null;
  }

  const parsedValue =
    new Date(normalizedValue);

  if (
    Number.isNaN(
      parsedValue.getTime(),
    )
  ) {
    return null;
  }

  return parsedValue.toISOString();
}

/*
 * IMPORTANT:
 *
 * Optimistic-concurrency timestamps must not be converted with
 * Date.toISOString().
 *
 * PostgreSQL timestamptz can preserve microseconds while JavaScript Date
 * preserves only milliseconds. The original updated_at string must
 * therefore be returned to PostgreSQL unchanged.
 */
export function normalizeDealExpectedUpdatedAt(
  value: string,
): string | null {
  const normalizedValue =
    value.trim();

  if (
    !normalizedValue ||
    Number.isNaN(
      Date.parse(normalizedValue),
    )
  ) {
    return null;
  }

  return normalizedValue;
}

export function normalizeDealCurrencyCode(
  value: string | null | undefined,
): string | null {
  const normalizedValue =
    normalizeDealOptionalText(value)
      ?.toUpperCase() ??
    "INR";

  return CURRENCY_CODE_PATTERN.test(
    normalizedValue,
  )
    ? normalizedValue
    : null;
}

export function createDealValidationFailure(
  message: string,
): DealOSServiceResult {
  return {
    ok: false,
    code: "validation",
    message,
  };
}

function getCombinedErrorMessage(
  error: DatabaseErrorLike,
): string {
  return [
    error.code,
    error.message,
    error.details,
    error.hint,
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function isAmbiguousTimeout(
  error: DatabaseErrorLike,
): boolean {
  const normalizedMessage =
    getCombinedErrorMessage(error);

  return (
    normalizedMessage.includes(
      "upstream request timeout",
    ) ||
    normalizedMessage.includes(
      "gateway timeout",
    ) ||
    normalizedMessage.includes(
      "request timeout",
    ) ||
    normalizedMessage.includes(
      "statement timeout",
    ) ||
    normalizedMessage.includes(
      "timed out",
    ) ||
    normalizedMessage.includes(
      "timeout",
    )
  );
}

function getDefaultOperationMessage(
  operation: DealOSOperation,
): string {
  switch (operation) {
    case "create":
      return "The deal could not be created.";

    case "update":
      return "The deal could not be updated.";

    case "change_status":
      return "The deal status could not be changed.";

    case "create_offer":
      return "The deal offer could not be created.";

    case "update_offer":
      return "The deal offer could not be updated.";

    case "request_approval":
      return "The commercial approval request could not be created.";

    case "decide_approval":
      return "The commercial approval decision could not be completed.";

    case "cancel_approval":
      return "The commercial approval request could not be cancelled.";

    case "link_booking":
      return "The booking handoff could not be completed.";
  }
}

function getTimeoutMessage(
  operation: DealOSOperation,
): string {
  switch (operation) {
    case "create":
      return "The request timed out. Reload the lead page to verify whether the deal was created before trying again.";

    case "update":
    case "change_status":
      return "The request timed out. Reload the latest deal state before trying again.";

    case "create_offer":
    case "update_offer":
      return "The request timed out. Reload the deal to verify the latest offer state before trying again.";

    case "request_approval":
    case "decide_approval":
    case "cancel_approval":
      return "The request timed out. Reload the deal to verify the latest commercial approval state before trying again.";

    case "link_booking":
      return "The request timed out. Reload the deal and booking state before trying again.";
  }
}

export function mapDealOSDatabaseError(
  error: DatabaseErrorLike,
  operation: DealOSOperation,
): DealOSServiceResult {
  const databaseMessage =
    error.message?.trim() ||
    getDefaultOperationMessage(
      operation,
    );

  const normalizedMessage =
    getCombinedErrorMessage(error);

  if (isAmbiguousTimeout(error)) {
    return {
      ok: false,
      code: "database_error",
      message:
        getTimeoutMessage(operation),
    };
  }

  if (
    error.code === "42501" ||
    normalizedMessage.includes(
      "permission denied",
    ) ||
    normalizedMessage.includes(
      "permission is required",
    ) ||
    normalizedMessage.includes(
      "permissions are required",
    )
  ) {
    return {
      ok: false,
      code: "permission_denied",
      message:
        "You do not have permission to perform this DealOS action.",
    };
  }

  if (
    error.code === "40001" ||
    error.code === "55P03" ||
    normalizedMessage.includes(
      "changed after the form was opened",
    ) ||
    normalizedMessage.includes(
      "currently being changed by another request",
    ) ||
    normalizedMessage.includes(
      "expected update timestamp",
    ) ||
    normalizedMessage.includes(
      "optimistic concurrency",
    )
  ) {
    return {
      ok: false,
      code: "conflict",
      message:
        "This deal was changed by another user or request. Reload the latest version before trying again.",
    };
  }

  if (
    error.code === "P0002" ||
    normalizedMessage.includes(
      "deal not found",
    ) ||
    normalizedMessage.includes(
      "lead not found",
    ) ||
    normalizedMessage.includes(
      "does not exist",
    ) ||
    normalizedMessage.includes(
      "not found",
    )
  ) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The deal or related record does not exist, is no longer available, or is outside the active organization.",
    };
  }

  if (
    error.code === "23503" ||
    normalizedMessage.includes(
      "deal assignee must be an active organization member",
    ) ||
    normalizedMessage.includes(
      "active organization member",
    ) ||
    normalizedMessage.includes(
      "invalid assignee",
    )
  ) {
    return {
      ok: false,
      code: "invalid_assignee",
      message:
        "The selected deal assignee is not an active member of this organization.",
    };
  }

  if (
    error.code === "23514" ||
    error.code === "22P02" ||
    normalizedMessage.includes(
      "invalid dealos status transition",
    ) ||
    normalizedMessage.includes(
      "invalid deal offer status transition",
    ) ||
    normalizedMessage.includes(
      "terminal deal offers cannot change status",
    ) ||
    normalizedMessage.includes(
      "commercial terms are immutable",
    ) ||
    normalizedMessage.includes(
      "completed commercial approvals cannot change status",
    ) ||
    normalizedMessage.includes(
      "invalid commercial approval status transition",
    ) ||
    normalizedMessage.includes(
      "commercial approval request values are immutable",
    )
  ) {
    return {
      ok: false,
      code: "invalid_state",
      message:
        "The DealOS action is not valid for the record's current state.",
    };
  }

  if (
    error.code === "P0001" &&
    (
      normalizedMessage.includes(
        "must belong to",
      ) ||
      normalizedMessage.includes(
        "does not match",
      ) ||
      normalizedMessage.includes(
        "cannot be linked",
      ) ||
      normalizedMessage.includes(
        "must start as",
      )
    )
  ) {
    return {
      ok: false,
      code: "validation",
      message: databaseMessage,
    };
  }

  return {
    ok: false,
    code: "database_error",
    message: databaseMessage,
  };
}

// Keep server client construction centralized for DealOS services.
export async function createDealOSClient() {
  return createClient();
}

type ScopedDealLeadRow = {
  id: string;
};

type DealMutationRow = {
  id?: unknown;
  lead_id?: unknown;
  updated_at?: unknown;
};

type ServerSupabaseClient =
  Awaited<ReturnType<typeof createClient>>;


async function verifyScopedDealLeadExists(
  supabase: ServerSupabaseClient,
  organizationId: string,
  leadId: string,
): Promise<
  | {
      ok: true;
    }
  | {
      ok: false;
      result: DealOSServiceResult;
    }
> {
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
    return {
      ok: false,
      result:
        mapDealOSDatabaseError(
          error,
          "create",
        ),
    };
  }

  if (
    !(
      data as
        | ScopedDealLeadRow
        | null
    )
  ) {
    return {
      ok: false,
      result: {
        ok: false,
        code: "not_found",
        message:
          "The lead does not exist, is no longer available, or is outside the active organization.",
      },
    };
  }

  return {
    ok: true,
  };
}


function getDealMutationPayload(
  data: unknown,
): DealMutationRow | null {
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

  return candidate as
    DealMutationRow;
}


function parseDealMutationResult(
  data: unknown,
  expectedDealId?: string,
  expectedLeadId?: string,
): DealOSServiceResult | null {
  const payload =
    getDealMutationPayload(data);

  if (!payload) {
    return null;
  }

  if (
    typeof payload.id !== "string" ||
    typeof payload.lead_id !== "string" ||
    typeof payload.updated_at !== "string"
  ) {
    return null;
  }

  const dealId =
    payload.id.trim();

  const leadId =
    payload.lead_id.trim();

  const updatedAt =
    payload.updated_at.trim();

  if (
    !dealId ||
    !leadId ||
    !updatedAt ||
    (
      expectedDealId &&
      dealId !== expectedDealId
    ) ||
    (
      expectedLeadId &&
      leadId !== expectedLeadId
    )
  ) {
    return null;
  }

  if (
    Number.isNaN(
      Date.parse(updatedAt),
    )
  ) {
    return null;
  }

  return {
    ok: true,
    dealId,
    updatedAt,
  };
}


export async function createDeal(
  organizationId: string,
  values: CreateDealValues,
): Promise<DealOSServiceResult> {
  const cleanOrganizationId =
    normalizeDealRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createDealValidationFailure(
      "An active organization context is required to create a deal.",
    );
  }

  const cleanLeadId =
    normalizeDealRequiredUuid(
      values.leadId,
    );

  if (!cleanLeadId) {
    return createDealValidationFailure(
      "A valid lead ID is required.",
    );
  }

  const rawSiteVisitId =
    normalizeDealOptionalText(
      values.siteVisitId,
    );

  const cleanSiteVisitId =
    rawSiteVisitId
      ? normalizeDealOptionalUuid(
          rawSiteVisitId,
        )
      : null;

  if (
    rawSiteVisitId &&
    !cleanSiteVisitId
  ) {
    return createDealValidationFailure(
      "The selected site visit is invalid.",
    );
  }

  const rawInventoryUnitId =
    normalizeDealOptionalText(
      values.inventoryUnitId,
    );

  const cleanInventoryUnitId =
    rawInventoryUnitId
      ? normalizeDealOptionalUuid(
          rawInventoryUnitId,
        )
      : null;

  if (
    rawInventoryUnitId &&
    !cleanInventoryUnitId
  ) {
    return createDealValidationFailure(
      "The selected inventory unit is invalid.",
    );
  }

  const rawAssignedTo =
    normalizeDealOptionalText(
      values.assignedTo,
    );

  const cleanAssignedTo =
    rawAssignedTo
      ? normalizeDealOptionalUuid(
          rawAssignedTo,
        )
      : null;

  if (
    rawAssignedTo &&
    !cleanAssignedTo
  ) {
    return createDealValidationFailure(
      "The selected deal assignee is invalid.",
    );
  }

  const cleanCurrencyCode =
    normalizeDealCurrencyCode(
      values.currencyCode,
    );

  if (!cleanCurrencyCode) {
    return createDealValidationFailure(
      "Enter a valid three-letter currency code.",
    );
  }

  const cleanBookingProbability =
    values.bookingProbability ??
    null;

  if (
    cleanBookingProbability !== null &&
    (
      !Number.isFinite(
        cleanBookingProbability,
      ) ||
      cleanBookingProbability < 0 ||
      cleanBookingProbability > 100
    )
  ) {
    return createDealValidationFailure(
      "Booking probability must be between 0 and 100.",
    );
  }

  const rawNextActionAt =
    normalizeDealOptionalText(
      values.nextActionAt,
    );

  const cleanNextActionAt =
    rawNextActionAt
      ? normalizeDealTimestamp(
          rawNextActionAt,
        )
      : null;

  if (
    rawNextActionAt &&
    !cleanNextActionAt
  ) {
    return createDealValidationFailure(
      "Enter a valid next-action date and time.",
    );
  }

  const cleanNotes =
    normalizeDealOptionalText(
      values.notes,
    );

  const supabase =
    await createDealOSClient();

  const scopedLeadResult =
    await verifyScopedDealLeadExists(
      supabase,
      cleanOrganizationId,
      cleanLeadId,
    );

  if (!scopedLeadResult.ok) {
    return scopedLeadResult.result;
  }

  const {
    data,
    error,
  } = await supabase
    .from("deals")
    .insert({
      organization_id:
        cleanOrganizationId,

      lead_id:
        cleanLeadId,

      site_visit_id:
        cleanSiteVisitId,

      inventory_unit_id:
        cleanInventoryUnitId,

      assigned_to:
        cleanAssignedTo,

      currency_code:
        cleanCurrencyCode,

      booking_probability:
        cleanBookingProbability,

      next_action_at:
        cleanNextActionAt,

      notes:
        cleanNotes,
    })
    .select(
      "id, lead_id, updated_at",
    )
    .single();

  if (error) {
    return mapDealOSDatabaseError(
      error,
      "create",
    );
  }

  const result =
    parseDealMutationResult(
      data,
      undefined,
      cleanLeadId,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The deal may have been created, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

type UpdateDealPayload = {
  assigned_to?: string | null;
  booking_probability?: number | null;
  next_action_at?: string | null;
  hold_reason?: string | null;
  notes?: string | null;
};


export async function updateDeal(
  organizationId: string,
  values: UpdateDealValues,
): Promise<DealOSServiceResult> {
  const cleanOrganizationId =
    normalizeDealRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createDealValidationFailure(
      "An active organization context is required to update a deal.",
    );
  }

  const cleanDealId =
    normalizeDealRequiredUuid(
      values.dealId,
    );

  if (!cleanDealId) {
    return createDealValidationFailure(
      "A valid deal ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createDealValidationFailure(
      "The original deal update timestamp is invalid.",
    );
  }

  const payload: UpdateDealPayload = {};

  if (values.assignedTo !== undefined) {
    const rawAssignedTo =
      normalizeDealOptionalText(
        values.assignedTo,
      );

    const cleanAssignedTo =
      rawAssignedTo
        ? normalizeDealOptionalUuid(
            rawAssignedTo,
          )
        : null;

    if (
      rawAssignedTo &&
      !cleanAssignedTo
    ) {
      return createDealValidationFailure(
        "The selected deal assignee is invalid.",
      );
    }

    payload.assigned_to =
      cleanAssignedTo;
  }

  if (
    values.bookingProbability !==
    undefined
  ) {
    const cleanBookingProbability =
      values.bookingProbability;

    if (
      cleanBookingProbability !== null &&
      (
        !Number.isFinite(
          cleanBookingProbability,
        ) ||
        cleanBookingProbability < 0 ||
        cleanBookingProbability > 100
      )
    ) {
      return createDealValidationFailure(
        "Booking probability must be between 0 and 100.",
      );
    }

    payload.booking_probability =
      cleanBookingProbability;
  }

  if (
    values.nextActionAt !== undefined
  ) {
    const rawNextActionAt =
      normalizeDealOptionalText(
        values.nextActionAt,
      );

    const cleanNextActionAt =
      rawNextActionAt
        ? normalizeDealTimestamp(
            rawNextActionAt,
          )
        : null;

    if (
      rawNextActionAt &&
      !cleanNextActionAt
    ) {
      return createDealValidationFailure(
        "Enter a valid next-action date and time.",
      );
    }

    payload.next_action_at =
      cleanNextActionAt;
  }

  if (values.holdReason !== undefined) {
    payload.hold_reason =
      normalizeDealOptionalText(
        values.holdReason,
      );
  }

  if (values.notes !== undefined) {
    payload.notes =
      normalizeDealOptionalText(
        values.notes,
      );
  }

  if (
    Object.keys(payload).length === 0
  ) {
    return createDealValidationFailure(
      "No deal changes were provided.",
    );
  }

  const supabase =
    await createDealOSClient();

  const {
    data,
    error,
  } = await supabase
    .from("deals")
    .update(payload)
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .eq(
      "updated_at",
      cleanExpectedUpdatedAt,
    )
    .is(
      "deleted_at",
      null,
    )
    .select(
      "id, lead_id, updated_at",
    )
    .maybeSingle();

  if (error) {
    return mapDealOSDatabaseError(
      error,
      "update",
    );
  }

  if (data) {
    const result =
      parseDealMutationResult(
        data,
        cleanDealId,
      );

    if (!result) {
      return {
        ok: false,
        code: "database_error",
        message:
          "The deal may have been updated, but its response could not be verified. Reload the latest deal before trying again.",
      };
    }

    return result;
  }

  /*
   * Zero updated rows means either:
   *
   * 1. The deal no longer exists / is not accessible.
   * 2. updated_at changed after the form was opened.
   */
  const {
    data: currentDeal,
    error: lookupError,
  } = await supabase
    .from("deals")
    .select("id")
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (lookupError) {
    return mapDealOSDatabaseError(
      lookupError,
      "update",
    );
  }

  if (!currentDeal) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The deal does not exist, is no longer available, or is outside the active organization.",
    };
  }

  return {
    ok: false,
    code: "conflict",
    message:
      "This deal was changed by another user or request. Reload the latest version before trying again.",
  };
}

export async function changeDealStatus(
  organizationId: string,
  values: ChangeDealStatusValues,
): Promise<DealOSServiceResult> {
  const cleanOrganizationId =
    normalizeDealRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createDealValidationFailure(
      "An active organization context is required to change deal status.",
    );
  }

  const cleanDealId =
    normalizeDealRequiredUuid(
      values.dealId,
    );

  if (!cleanDealId) {
    return createDealValidationFailure(
      "A valid deal ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createDealValidationFailure(
      "The original deal update timestamp is invalid.",
    );
  }

  const supabase =
    await createDealOSClient();

  const {
    data,
    error,
  } = await supabase
    .from("deals")
    .update({
      status: values.status,
    })
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .eq(
      "updated_at",
      cleanExpectedUpdatedAt,
    )
    .is(
      "deleted_at",
      null,
    )
    .select(
      "id, lead_id, updated_at",
    )
    .maybeSingle();

  if (error) {
    return mapDealOSDatabaseError(
      error,
      "change_status",
    );
  }

  if (data) {
    const result =
      parseDealMutationResult(
        data,
        cleanDealId,
      );

    if (!result) {
      return {
        ok: false,
        code: "database_error",
        message:
          "The deal status may have changed, but its response could not be verified. Reload the latest deal before trying again.",
      };
    }

    return result;
  }

  /*
   * Zero updated rows means either:
   *
   * 1. Deal no longer exists / is outside active scope.
   * 2. updated_at changed after the action was opened.
   */
  const {
    data: currentDeal,
    error: lookupError,
  } = await supabase
    .from("deals")
    .select("id")
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (lookupError) {
    return mapDealOSDatabaseError(
      lookupError,
      "change_status",
    );
  }

  if (!currentDeal) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The deal does not exist, is no longer available, or is outside the active organization.",
    };
  }

  return {
    ok: false,
    code: "conflict",
    message:
      "This deal was changed by another user or request. Reload the latest version before trying again.",
  };
}

export async function markDealLost(
  organizationId: string,
  values: MarkDealLostValues,
): Promise<DealOSServiceResult> {
  const cleanOrganizationId =
    normalizeDealRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createDealValidationFailure(
      "An active organization context is required to mark a deal lost.",
    );
  }

  const cleanDealId =
    normalizeDealRequiredUuid(
      values.dealId,
    );

  if (!cleanDealId) {
    return createDealValidationFailure(
      "A valid deal ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createDealValidationFailure(
      "The original deal update timestamp is invalid.",
    );
  }

  const cleanLossReason =
    normalizeDealOptionalText(
      values.lossReason,
    );

  if (!cleanLossReason) {
    return createDealValidationFailure(
      "Enter a reason for marking this deal lost.",
    );
  }

  const supabase =
    await createDealOSClient();

  const {
    data,
    error,
  } = await supabase
    .from("deals")
    .update({
      status: "lost",
      loss_reason: cleanLossReason,
    })
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .eq(
      "updated_at",
      cleanExpectedUpdatedAt,
    )
    .is(
      "deleted_at",
      null,
    )
    .select(
      "id, lead_id, updated_at",
    )
    .maybeSingle();

  if (error) {
    return mapDealOSDatabaseError(
      error,
      "change_status",
    );
  }

  if (data) {
    const result =
      parseDealMutationResult(
        data,
        cleanDealId,
      );

    if (!result) {
      return {
        ok: false,
        code: "database_error",
        message:
          "The deal may have been marked lost, but its response could not be verified. Reload the latest deal before trying again.",
      };
    }

    return result;
  }

  const {
    data: currentDeal,
    error: lookupError,
  } = await supabase
    .from("deals")
    .select("id")
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (lookupError) {
    return mapDealOSDatabaseError(
      lookupError,
      "change_status",
    );
  }

  if (!currentDeal) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The deal does not exist, is no longer available, or is outside the active organization.",
    };
  }

  return {
    ok: false,
    code: "conflict",
    message:
      "This deal was changed by another user or request. Reload the latest version before trying again.",
  };
}

export async function putDealOnHold(
  organizationId: string,
  values: PutDealOnHoldValues,
): Promise<DealOSServiceResult> {
  const cleanOrganizationId =
    normalizeDealRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createDealValidationFailure(
      "An active organization context is required to put a deal on hold.",
    );
  }

  const cleanDealId =
    normalizeDealRequiredUuid(
      values.dealId,
    );

  if (!cleanDealId) {
    return createDealValidationFailure(
      "A valid deal ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createDealValidationFailure(
      "The original deal update timestamp is invalid.",
    );
  }

  const cleanHoldReason =
    normalizeDealOptionalText(
      values.holdReason,
    );

  if (!cleanHoldReason) {
    return createDealValidationFailure(
      "Enter a reason for putting this deal on hold.",
    );
  }

  const supabase =
    await createDealOSClient();

  const {
    data,
    error,
  } = await supabase
    .from("deals")
    .update({
      status: "on_hold",
      hold_reason: cleanHoldReason,
    })
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .eq(
      "updated_at",
      cleanExpectedUpdatedAt,
    )
    .is(
      "deleted_at",
      null,
    )
    .select(
      "id, lead_id, updated_at",
    )
    .maybeSingle();

  if (error) {
    return mapDealOSDatabaseError(
      error,
      "change_status",
    );
  }

  if (data) {
    const result =
      parseDealMutationResult(
        data,
        cleanDealId,
      );

    if (!result) {
      return {
        ok: false,
        code: "database_error",
        message:
          "The deal may have been put on hold, but its response could not be verified. Reload the latest deal before trying again.",
      };
    }

    return result;
  }

  const {
    data: currentDeal,
    error: lookupError,
  } = await supabase
    .from("deals")
    .select("id")
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (lookupError) {
    return mapDealOSDatabaseError(
      lookupError,
      "change_status",
    );
  }

  if (!currentDeal) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The deal does not exist, is no longer available, or is outside the active organization.",
    };
  }

  return {
    ok: false,
    code: "conflict",
    message:
      "This deal was changed by another user or request. Reload the latest version before trying again.",
  };
}

export async function cancelDeal(
  organizationId: string,
  values: CancelDealValues,
): Promise<DealOSServiceResult> {
  const cleanOrganizationId =
    normalizeDealRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createDealValidationFailure(
      "An active organization context is required to cancel a deal.",
    );
  }

  const cleanDealId =
    normalizeDealRequiredUuid(
      values.dealId,
    );

  if (!cleanDealId) {
    return createDealValidationFailure(
      "A valid deal ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createDealValidationFailure(
      "The original deal update timestamp is invalid.",
    );
  }

  const cleanCancellationReason =
    normalizeDealOptionalText(
      values.cancellationReason,
    );

  if (!cleanCancellationReason) {
    return createDealValidationFailure(
      "Enter a reason for cancelling this deal.",
    );
  }

  const supabase =
    await createDealOSClient();

  const {
    data,
    error,
  } = await supabase
    .from("deals")
    .update({
      status: "cancelled",
      cancellation_reason:
        cleanCancellationReason,
    })
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .eq(
      "updated_at",
      cleanExpectedUpdatedAt,
    )
    .is(
      "deleted_at",
      null,
    )
    .select(
      "id, lead_id, updated_at",
    )
    .maybeSingle();

  if (error) {
    return mapDealOSDatabaseError(
      error,
      "change_status",
    );
  }

  if (data) {
    const result =
      parseDealMutationResult(
        data,
        cleanDealId,
      );

    if (!result) {
      return {
        ok: false,
        code: "database_error",
        message:
          "The deal may have been cancelled, but its response could not be verified. Reload the latest deal before trying again.",
      };
    }

    return result;
  }

  const {
    data: currentDeal,
    error: lookupError,
  } = await supabase
    .from("deals")
    .select("id")
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (lookupError) {
    return mapDealOSDatabaseError(
      lookupError,
      "change_status",
    );
  }

  if (!currentDeal) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The deal does not exist, is no longer available, or is outside the active organization.",
    };
  }

  return {
    ok: false,
    code: "conflict",
    message:
      "This deal was changed by another user or request. Reload the latest version before trying again.",
  };
}

export async function linkDealBooking(
  organizationId: string,
  values: LinkDealBookingValues,
): Promise<DealOSServiceResult> {
  const cleanOrganizationId =
    normalizeDealRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createDealValidationFailure(
      "An active organization context is required to link a booking.",
    );
  }

  const cleanDealId =
    normalizeDealRequiredUuid(
      values.dealId,
    );

  if (!cleanDealId) {
    return createDealValidationFailure(
      "A valid deal ID is required.",
    );
  }

  const cleanBookingId =
    normalizeDealRequiredUuid(
      values.bookingId,
    );

  if (!cleanBookingId) {
    return createDealValidationFailure(
      "A valid booking ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createDealValidationFailure(
      "The original deal update timestamp is invalid.",
    );
  }

  const supabase =
    await createDealOSClient();

  /*
   * Booking handoff is intentionally restricted to the
   * booking_ready state at the application layer.
   *
   * PostgreSQL remains authoritative for organization,
   * lead, site-visit, inventory and permission integrity.
   */
  const {
    data,
    error,
  } = await supabase
    .from("deals")
    .update({
      booking_id:
        cleanBookingId,
    })
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .eq(
      "status",
      "booking_ready",
    )
    .eq(
      "updated_at",
      cleanExpectedUpdatedAt,
    )
    .is(
      "deleted_at",
      null,
    )
    .select(
      "id, lead_id, updated_at",
    )
    .maybeSingle();

  if (error) {
    return mapDealOSDatabaseError(
      error,
      "link_booking",
    );
  }

  if (data) {
    const result =
      parseDealMutationResult(
        data,
        cleanDealId,
      );

    if (!result) {
      return {
        ok: false,
        code: "database_error",
        message:
          "The booking may have been linked, but its response could not be verified. Reload the latest deal before trying again.",
      };
    }

    return result;
  }

  /*
   * Zero updated rows can mean:
   *
   * 1. Deal no longer exists / is outside active scope.
   * 2. Deal is not currently booking_ready.
   * 3. updated_at changed after the handoff action opened.
   */
  const {
    data: currentDeal,
    error: lookupError,
  } = await supabase
    .from("deals")
    .select(
      "id, status",
    )
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (lookupError) {
    return mapDealOSDatabaseError(
      lookupError,
      "link_booking",
    );
  }

  if (!currentDeal) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The deal does not exist, is no longer available, or is outside the active organization.",
    };
  }

  const scopedDeal =
    currentDeal as {
      id: string;
      status: string;
    };

  if (
    scopedDeal.status !==
    "booking_ready"
  ) {
    return {
      ok: false,
      code: "invalid_state",
      message:
        "A booking can only be linked when the deal is booking ready.",
    };
  }

  return {
    ok: false,
    code: "conflict",
    message:
      "This deal was changed by another user or request. Reload the latest version before trying again.",
  };
}

export async function markDealWon(
  organizationId: string,
  values: MarkDealWonValues,
): Promise<DealOSServiceResult> {
  const cleanOrganizationId =
    normalizeDealRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createDealValidationFailure(
      "An active organization context is required to mark a deal won.",
    );
  }

  const cleanDealId =
    normalizeDealRequiredUuid(
      values.dealId,
    );

  if (!cleanDealId) {
    return createDealValidationFailure(
      "A valid deal ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createDealValidationFailure(
      "The original deal update timestamp is invalid.",
    );
  }

  const supabase =
    await createDealOSClient();

  /*
   * Winning a deal is deliberately restricted to:
   *
   * - booking_ready status
   * - an already-linked booking
   * - the exact updated_at version opened by the user
   *
   * PostgreSQL remains authoritative for booking integrity,
   * commercial requirements and permissions.
   */
  const {
    data,
    error,
  } = await supabase
    .from("deals")
    .update({
      status: "won",
    })
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .eq(
      "status",
      "booking_ready",
    )
    .not(
      "booking_id",
      "is",
      null,
    )
    .eq(
      "updated_at",
      cleanExpectedUpdatedAt,
    )
    .is(
      "deleted_at",
      null,
    )
    .select(
      "id, lead_id, updated_at",
    )
    .maybeSingle();

  if (error) {
    return mapDealOSDatabaseError(
      error,
      "change_status",
    );
  }

  if (data) {
    const result =
      parseDealMutationResult(
        data,
        cleanDealId,
      );

    if (!result) {
      return {
        ok: false,
        code: "database_error",
        message:
          "The deal may have been marked won, but its response could not be verified. Reload the latest deal before trying again.",
      };
    }

    return result;
  }

  const {
    data: currentDeal,
    error: lookupError,
  } = await supabase
    .from("deals")
    .select(
      "id, status, booking_id",
    )
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanDealId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (lookupError) {
    return mapDealOSDatabaseError(
      lookupError,
      "change_status",
    );
  }

  if (!currentDeal) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The deal does not exist, is no longer available, or is outside the active organization.",
    };
  }

  const scopedDeal =
    currentDeal as {
      id: string;
      status: string;
      booking_id: string | null;
    };

  if (
    scopedDeal.status !==
    "booking_ready"
  ) {
    return {
      ok: false,
      code: "invalid_state",
      message:
        "Only a booking-ready deal can be marked won.",
    };
  }

  if (!scopedDeal.booking_id) {
    return {
      ok: false,
      code: "invalid_state",
      message:
        "Link the Booking Engine record before marking this deal won.",
    };
  }

  return {
    ok: false,
    code: "conflict",
    message:
      "This deal was changed by another user or request. Reload the latest version before trying again.",
  };
}