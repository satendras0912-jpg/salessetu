import "server-only";

import { createClient } from "@/lib/supabase/server";

import {
  DEFAULT_OPERATIONAL_TIMEZONE,
  OPERATIONAL_FORM_LIMITS,
  OPERATIONAL_PRIORITIES,
  SITE_VISIT_CHECK_IN_METHODS,
  SITE_VISIT_OUTCOMES,
  SITE_VISIT_PARTIES,
  SITE_VISIT_TYPES,
  isOperationalValue,
} from "@/lib/leads/lead-operational-contract";

import type {
  AssignSiteVisitValues,
  CancelSiteVisitValues,
  CompleteSiteVisitValues,
  CreateSiteVisitValues,
  SiteVisitCheckInValues,
  SiteVisitCheckOutValues,
} from "@/types/lead-operational-controls";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type DatabaseErrorLike = {
  code?: string | null;
  message?: string | null;
  details?: string | null;
  hint?: string | null;
};

type ScopedLeadRow = {
  id: string;
};

type ScopedSiteVisitRow = {
  id: string;
  lead_id: string;
  updated_at: string;
};

type SiteVisitMutationRow = {
  id?: unknown;
  lead_id?: unknown;
  updated_at?: unknown;
};

type ServerSupabaseClient =
  Awaited<ReturnType<typeof createClient>>;

export type SiteVisitServiceErrorCode =
  | "validation"
  | "not_found"
  | "permission_denied"
  | "conflict"
  | "invalid_assignee"
  | "invalid_state"
  | "database_error";

export type SiteVisitServiceResult =
  | {
      ok: true;
      siteVisitId: string;
      leadId: string;
      updatedAt: string;
    }
  | {
      ok: false;
      code: SiteVisitServiceErrorCode;
      message: string;
    };

type SiteVisitOperation =
  | "create"
  | "assign"
  | "check_in"
  | "check_out"
  | "complete"
  | "cancel";

function normalizeOptionalText(
  value: string | null | undefined,
): string | null {
  const normalizedValue =
    value?.trim();

  return normalizedValue
    ? normalizedValue
    : null;
}

function isValidUuid(
  value: string,
): boolean {
  return UUID_PATTERN.test(value);
}

function createValidationFailure(
  message: string,
): SiteVisitServiceResult {
  return {
    ok: false,
    code: "validation",
    message,
  };
}

function normalizeRequiredUuid(
  value: string,
): string | null {
  const normalizedValue =
    value.trim();

  if (
    !normalizedValue ||
    !isValidUuid(normalizedValue)
  ) {
    return null;
  }

  return normalizedValue;
}

function normalizeOptionalUuid(
  value: string | null | undefined,
): string | null {
  const normalizedValue =
    normalizeOptionalText(value);

  if (!normalizedValue) {
    return null;
  }

  return isValidUuid(normalizedValue)
    ? normalizedValue
    : null;
}

function normalizeTimestamp(
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
 * Do not pass optimistic-concurrency timestamps through
 * Date.toISOString().
 *
 * PostgreSQL timestamptz can preserve microseconds while JavaScript Date
 * only preserves milliseconds. The original updated_at string must therefore
 * be sent back to PostgreSQL unchanged.
 */
function normalizeExpectedUpdatedAt(
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

function normalizeOptionalNumber(
  value: string | null | undefined,
): number | null {
  const normalizedValue =
    normalizeOptionalText(value);

  if (!normalizedValue) {
    return null;
  }

  const parsedValue =
    Number(normalizedValue);

  return Number.isFinite(parsedValue)
    ? parsedValue
    : null;
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
  operation: SiteVisitOperation,
): string {
  switch (operation) {
    case "create":
      return "The site visit could not be created.";

    case "assign":
      return "The site visit could not be assigned.";

    case "check_in":
      return "The site visit check-in could not be completed.";

    case "check_out":
      return "The site visit check-out could not be completed.";

    case "complete":
      return "The site visit could not be completed.";

    case "cancel":
      return "The site visit could not be cancelled.";
  }
}

function getTimeoutMessage(
  operation: SiteVisitOperation,
): string {
  switch (operation) {
    case "create":
      return "The request timed out. Reload the lead page to verify whether the site visit was created before trying again.";

    case "assign":
      return "The request timed out. Reload the lead page to verify the latest site visit assignment before trying again.";

    case "check_in":
      return "The request timed out. Reload the lead page to verify the latest site visit check-in state before trying again.";

    case "check_out":
      return "The request timed out. Reload the lead page to verify the latest site visit check-out state before trying again.";

    case "complete":
      return "The request timed out. Reload the lead page to verify the latest site visit status before trying again.";

    case "cancel":
      return "The request timed out. Reload the lead page to verify the latest site visit status before trying again.";
  }
}

function mapDatabaseError(
  error: DatabaseErrorLike,
  operation: SiteVisitOperation,
): SiteVisitServiceResult {
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
    )
  ) {
    return {
      ok: false,
      code: "permission_denied",
      message:
        "You do not have permission to perform this site visit action.",
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
        "This site visit was changed by another user or request. Reload the latest version before trying again.",
    };
  }

  if (
    error.code === "P0002" ||
    normalizedMessage.includes(
      "site visit not found",
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
        "The lead or site visit does not exist, is no longer available, or is outside the active organization.",
    };
  }

  if (
    error.code === "23503" ||
    normalizedMessage.includes(
      "active organization member",
    ) ||
    normalizedMessage.includes(
      "assigned agent",
    ) ||
    normalizedMessage.includes(
      "coordinator",
    ) ||
    normalizedMessage.includes(
      "invalid assignee",
    )
  ) {
    return {
      ok: false,
      code: "invalid_assignee",
      message:
        "The selected agent or coordinator is not an active member of this organization.",
    };
  }

  if (
  normalizedMessage.includes(
    "invalid site visit outcome",
  )
) {
  return {
    ok: false,
    code: "validation",
    message:
      "Select a valid site visit outcome.",
  };
}

if (
  error.code === "23514" ||
  error.code === "22P02" ||
  normalizedMessage.includes(
    "cannot be assigned",
  ) ||
  normalizedMessage.includes(
    "cannot be checked in",
  ) ||
  normalizedMessage.includes(
    "cannot be checked out",
  ) ||
  normalizedMessage.includes(
    "cannot be completed",
  ) ||
  normalizedMessage.includes(
    "cannot be cancelled",
  ) ||
  normalizedMessage.includes(
    "already completed",
  ) ||
  normalizedMessage.includes(
    "already cancelled",
  ) ||
  normalizedMessage.includes(
    "must be checked in",
  ) ||
  normalizedMessage.includes(
    "invalid check-in method",
  ) ||
  normalizedMessage.includes(
    "invalid latitude",
  ) ||
  normalizedMessage.includes(
    "invalid longitude",
  ) ||
  normalizedMessage.includes(
    "probability of booking",
  ) ||
  normalizedMessage.includes(
    "invalid status",
  )
) {
  return {
    ok: false,
    code: "invalid_state",
    message:
      "The site visit action is not valid for the visit's current state.",
  };
}

  return {
    ok: false,
    code: "database_error",
    message: databaseMessage,
  };
}

async function verifyScopedLeadExists(
  supabase: ServerSupabaseClient,
  organizationId: string,
  leadId: string,
): Promise<
  | {
      ok: true;
    }
  | {
      ok: false;
      result: SiteVisitServiceResult;
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
        mapDatabaseError(
          error,
          "create",
        ),
    };
  }

  if (
    !(
      data as ScopedLeadRow | null
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

async function loadScopedSiteVisit(
  supabase: ServerSupabaseClient,
  organizationId: string,
  siteVisitId: string,
  operation: SiteVisitOperation,
): Promise<
  | {
      ok: true;
      row: ScopedSiteVisitRow;
    }
  | {
      ok: false;
      result: SiteVisitServiceResult;
    }
> {
  const {
    data,
    error,
  } = await supabase
    .from("site_visits")
    .select(
      "id, lead_id, updated_at",
    )
    .eq(
      "organization_id",
      organizationId,
    )
    .eq(
      "id",
      siteVisitId,
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
        mapDatabaseError(
          error,
          operation,
        ),
    };
  }

  const row =
    data as
      | ScopedSiteVisitRow
      | null;

  if (!row) {
    return {
      ok: false,
      result: {
        ok: false,
        code: "not_found",
        message:
          "The site visit does not exist, is no longer available, or is outside the active organization.",
      },
    };
  }

  return {
    ok: true,
    row,
  };
}

function getMutationPayload(
  data: unknown,
): SiteVisitMutationRow | null {
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
    SiteVisitMutationRow;
}

function parseMutationResult(
  data: unknown,
  expectedSiteVisitId?: string,
  expectedLeadId?: string,
): SiteVisitServiceResult | null {
  const payload =
    getMutationPayload(data);

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

  const siteVisitId =
    payload.id.trim();

  const leadId =
    payload.lead_id.trim();

  const updatedAt =
    payload.updated_at.trim();

  if (
    !siteVisitId ||
    !leadId ||
    !updatedAt ||
    (
      expectedSiteVisitId &&
      siteVisitId !== expectedSiteVisitId
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
    siteVisitId,
    leadId,
    updatedAt,
  };
}

export async function createSiteVisit(
  organizationId: string,
  values: CreateSiteVisitValues,
): Promise<SiteVisitServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to create a site visit.",
    );
  }

  const cleanLeadId =
    normalizeRequiredUuid(
      values.leadId,
    );

  if (!cleanLeadId) {
    return createValidationFailure(
      "A valid lead ID is required.",
    );
  }

  const cleanTitle =
    values.title
      .replace(/\s+/g, " ")
      .trim();

  if (!cleanTitle) {
    return createValidationFailure(
      "Enter a title for the site visit.",
    );
  }

  if (
    cleanTitle.length >
    OPERATIONAL_FORM_LIMITS.title
  ) {
    return createValidationFailure(
      `Site visit title must not exceed ${OPERATIONAL_FORM_LIMITS.title} characters.`,
    );
  }

  const cleanDescription =
    normalizeOptionalText(
      values.description,
    );

  if (
    cleanDescription &&
    cleanDescription.length >
      OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    return createValidationFailure(
      `Site visit description must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (
    !isOperationalValue(
      values.visitType,
      SITE_VISIT_TYPES,
    )
  ) {
    return createValidationFailure(
      "Select a valid site visit type.",
    );
  }

  if (
    !isOperationalValue(
      values.priority,
      OPERATIONAL_PRIORITIES,
    )
  ) {
    return createValidationFailure(
      "Select a valid site visit priority.",
    );
  }

  const cleanProjectName =
    values.projectName
      .replace(/\s+/g, " ")
      .trim();

  if (!cleanProjectName) {
    return createValidationFailure(
      "Enter the project name.",
    );
  }

  if (
    cleanProjectName.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    return createValidationFailure(
      `Project name must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  const cleanDeveloperName =
    normalizeOptionalText(
      values.developerName,
    );

  const cleanPropertyName =
    normalizeOptionalText(
      values.propertyName,
    );

  const cleanUnitType =
    normalizeOptionalText(
      values.unitType,
    );

  const cleanVisitAddress =
    normalizeOptionalText(
      values.visitAddress,
    );

  const cleanVisitCity =
    normalizeOptionalText(
      values.visitCity,
    );

  const cleanLocationUrl =
    normalizeOptionalText(
      values.locationUrl,
    );

  if (
    cleanDeveloperName &&
    cleanDeveloperName.length >
      OPERATIONAL_FORM_LIMITS.shortText
  ) {
    return createValidationFailure(
      `Developer name must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    cleanPropertyName &&
    cleanPropertyName.length >
      OPERATIONAL_FORM_LIMITS.shortText
  ) {
    return createValidationFailure(
      `Property name must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    cleanUnitType &&
    cleanUnitType.length >
      OPERATIONAL_FORM_LIMITS.shortText
  ) {
    return createValidationFailure(
      `Unit type must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    cleanVisitAddress &&
    cleanVisitAddress.length >
      OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    return createValidationFailure(
      `Visit address must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (
    cleanVisitCity &&
    cleanVisitCity.length >
      OPERATIONAL_FORM_LIMITS.shortText
  ) {
    return createValidationFailure(
      `Visit city must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    cleanLocationUrl &&
    cleanLocationUrl.length >
      OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    return createValidationFailure(
      `Location URL must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  const cleanScheduledStartAt =
    normalizeTimestamp(
      values.scheduledStartAt,
    );

  if (!cleanScheduledStartAt) {
    return createValidationFailure(
      "Enter a valid site visit start date and time.",
    );
  }

  const rawScheduledEndAt =
    normalizeOptionalText(
      values.scheduledEndAt,
    );

  const cleanScheduledEndAt =
    rawScheduledEndAt
      ? normalizeTimestamp(
          rawScheduledEndAt,
        )
      : null;

  if (
    rawScheduledEndAt &&
    !cleanScheduledEndAt
  ) {
    return createValidationFailure(
      "Enter a valid site visit end date and time.",
    );
  }

  if (
    cleanScheduledEndAt &&
    new Date(
      cleanScheduledEndAt,
    ).getTime() <
      new Date(
        cleanScheduledStartAt,
      ).getTime()
  ) {
    return createValidationFailure(
      "The site visit end time cannot be before the start time.",
    );
  }

  const cleanTimezone =
    normalizeOptionalText(
      values.timezone,
    ) ||
    DEFAULT_OPERATIONAL_TIMEZONE;

  if (
    cleanTimezone.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    return createValidationFailure(
      `Timezone must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  const rawAssignedAgentId =
    normalizeOptionalText(
      values.assignedAgentId,
    );

  const cleanAssignedAgentId =
    rawAssignedAgentId
      ? normalizeOptionalUuid(
          rawAssignedAgentId,
        )
      : null;

  if (
    rawAssignedAgentId &&
    !cleanAssignedAgentId
  ) {
    return createValidationFailure(
      "The selected site visit agent is invalid.",
    );
  }

  const rawCoordinatorId =
    normalizeOptionalText(
      values.coordinatorId,
    );

  const cleanCoordinatorId =
    rawCoordinatorId
      ? normalizeOptionalUuid(
          rawCoordinatorId,
        )
      : null;

  if (
    rawCoordinatorId &&
    !cleanCoordinatorId
  ) {
    return createValidationFailure(
      "The selected site visit coordinator is invalid.",
    );
  }

  const rawReminderAt =
    normalizeOptionalText(
      values.reminderAt,
    );

  const cleanReminderAt =
    rawReminderAt
      ? normalizeTimestamp(
          rawReminderAt,
        )
      : null;

  if (
    rawReminderAt &&
    !cleanReminderAt
  ) {
    return createValidationFailure(
      "Enter a valid reminder date and time.",
    );
  }

  if (
    cleanReminderAt &&
    new Date(
      cleanReminderAt,
    ).getTime() >
      new Date(
        cleanScheduledStartAt,
      ).getTime()
  ) {
    return createValidationFailure(
      "The reminder must be scheduled on or before the site visit start time.",
    );
  }

  const cleanPickupAddress =
    normalizeOptionalText(
      values.pickupAddress,
    );

  if (
    cleanPickupAddress &&
    cleanPickupAddress.length >
      OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    return createValidationFailure(
      `Pickup address must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  const rawPickupTime =
    normalizeOptionalText(
      values.pickupTime,
    );

  const cleanPickupTime =
    rawPickupTime
      ? normalizeTimestamp(
          rawPickupTime,
        )
      : null;

  if (
    rawPickupTime &&
    !cleanPickupTime
  ) {
    return createValidationFailure(
      "Enter a valid pickup date and time.",
    );
  }

  if (
    cleanPickupTime &&
    new Date(
      cleanPickupTime,
    ).getTime() >
      new Date(
        cleanScheduledStartAt,
      ).getTime()
  ) {
    return createValidationFailure(
      "Pickup time must be on or before the site visit start time.",
    );
  }

  const cleanTransportNotes =
    normalizeOptionalText(
      values.transportNotes,
    );

  if (
    cleanTransportNotes &&
    cleanTransportNotes.length >
      OPERATIONAL_FORM_LIMITS.notes
  ) {
    return createValidationFailure(
      `Transport notes must not exceed ${OPERATIONAL_FORM_LIMITS.notes} characters.`,
    );
  }

  const supabase =
    await createClient();

  const scopedLeadResult =
    await verifyScopedLeadExists(
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
    .from("site_visits")
    .insert({
      organization_id:
        cleanOrganizationId,

      lead_id:
        cleanLeadId,

      title:
        cleanTitle,

      description:
        cleanDescription,

      visit_type:
        values.visitType,

      priority:
        values.priority,

      project_name:
        cleanProjectName,

      developer_name:
        cleanDeveloperName,

      property_name:
        cleanPropertyName,

      unit_type:
        cleanUnitType,

      visit_address:
        cleanVisitAddress,

      visit_city:
        cleanVisitCity,

      location_url:
        cleanLocationUrl,

      scheduled_start_at:
        cleanScheduledStartAt,

      scheduled_end_at:
        cleanScheduledEndAt,

      timezone:
        cleanTimezone,

      assigned_agent_id:
        cleanAssignedAgentId,

      coordinator_id:
        cleanCoordinatorId,

      reminder_at:
        cleanReminderAt,

      pickup_required:
        values.pickupRequired,

      pickup_address:
        cleanPickupAddress,

      pickup_time:
        cleanPickupTime,

      transport_notes:
        cleanTransportNotes,
    })
    .select(
      "id, lead_id, updated_at",
    )
    .single();

  if (error) {
    return mapDatabaseError(
      error,
      "create",
    );
  }

  const result =
    parseMutationResult(
      data,
      undefined,
      cleanLeadId,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The site visit may have been created, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

export async function assignSiteVisit(
  organizationId: string,
  values: AssignSiteVisitValues,
): Promise<SiteVisitServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to assign a site visit.",
    );
  }

  const cleanSiteVisitId =
    normalizeRequiredUuid(
      values.siteVisitId,
    );

  if (!cleanSiteVisitId) {
    return createValidationFailure(
      "A valid site visit ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createValidationFailure(
      "The original site visit update timestamp is invalid.",
    );
  }

  const rawAssignedAgentId =
    normalizeOptionalText(
      values.assignedAgentId,
    );

  const cleanAssignedAgentId =
    rawAssignedAgentId
      ? normalizeOptionalUuid(
          rawAssignedAgentId,
        )
      : null;

  if (
    rawAssignedAgentId &&
    !cleanAssignedAgentId
  ) {
    return createValidationFailure(
      "The selected site visit agent is invalid.",
    );
  }

  const rawCoordinatorId =
    normalizeOptionalText(
      values.coordinatorId,
    );

  const cleanCoordinatorId =
    rawCoordinatorId
      ? normalizeOptionalUuid(
          rawCoordinatorId,
        )
      : null;

  if (
    rawCoordinatorId &&
    !cleanCoordinatorId
  ) {
    return createValidationFailure(
      "The selected site visit coordinator is invalid.",
    );
  }

  const cleanReason =
    normalizeOptionalText(
      values.reason,
    );

  if (
    cleanReason &&
    cleanReason.length >
      OPERATIONAL_FORM_LIMITS.reason
  ) {
    return createValidationFailure(
      `Assignment reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  const supabase =
    await createClient();

  const scopedVisitResult =
    await loadScopedSiteVisit(
      supabase,
      cleanOrganizationId,
      cleanSiteVisitId,
      "assign",
    );

  if (!scopedVisitResult.ok) {
    return scopedVisitResult.result;
  }

  const {
    data,
    error,
  } = await supabase.rpc(
    "assign_site_visit",
    {
      requested_site_visit_id:
        cleanSiteVisitId,

      requested_agent_id:
        cleanAssignedAgentId,

      requested_coordinator_id:
        cleanCoordinatorId,

      requested_reason:
        cleanReason,

      requested_expected_updated_at:
        cleanExpectedUpdatedAt,
    },
  );

  if (error) {
    return mapDatabaseError(
      error,
      "assign",
    );
  }

  const result =
    parseMutationResult(
      data,
      cleanSiteVisitId,
      scopedVisitResult.row.lead_id,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The site visit assignment may have changed, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

export async function checkInSiteVisit(
  organizationId: string,
  values: SiteVisitCheckInValues,
): Promise<SiteVisitServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to check in a site visit.",
    );
  }

  const cleanSiteVisitId =
    normalizeRequiredUuid(
      values.siteVisitId,
    );

  if (!cleanSiteVisitId) {
    return createValidationFailure(
      "A valid site visit ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createValidationFailure(
      "The original site visit update timestamp is invalid.",
    );
  }

  if (
    !isOperationalValue(
      values.party,
      SITE_VISIT_PARTIES,
    )
  ) {
    return createValidationFailure(
      "Select a valid check-in party.",
    );
  }

  if (
    !isOperationalValue(
      values.method,
      SITE_VISIT_CHECK_IN_METHODS,
    )
  ) {
    return createValidationFailure(
      "Select a valid check-in method.",
    );
  }

  const rawLatitude =
    normalizeOptionalText(
      values.latitude,
    );

  const cleanLatitude =
    rawLatitude
      ? normalizeOptionalNumber(
          rawLatitude,
        )
      : null;

  if (
    rawLatitude &&
    cleanLatitude === null
  ) {
    return createValidationFailure(
      "Enter a valid latitude.",
    );
  }

  if (
    cleanLatitude !== null &&
    (
      cleanLatitude <
        OPERATIONAL_FORM_LIMITS.latitudeMinimum ||
      cleanLatitude >
        OPERATIONAL_FORM_LIMITS.latitudeMaximum
    )
  ) {
    return createValidationFailure(
      `Latitude must be between ${OPERATIONAL_FORM_LIMITS.latitudeMinimum} and ${OPERATIONAL_FORM_LIMITS.latitudeMaximum}.`,
    );
  }

  const rawLongitude =
    normalizeOptionalText(
      values.longitude,
    );

  const cleanLongitude =
    rawLongitude
      ? normalizeOptionalNumber(
          rawLongitude,
        )
      : null;

  if (
    rawLongitude &&
    cleanLongitude === null
  ) {
    return createValidationFailure(
      "Enter a valid longitude.",
    );
  }

  if (
    cleanLongitude !== null &&
    (
      cleanLongitude <
        OPERATIONAL_FORM_LIMITS.longitudeMinimum ||
      cleanLongitude >
        OPERATIONAL_FORM_LIMITS.longitudeMaximum
    )
  ) {
    return createValidationFailure(
      `Longitude must be between ${OPERATIONAL_FORM_LIMITS.longitudeMinimum} and ${OPERATIONAL_FORM_LIMITS.longitudeMaximum}.`,
    );
  }

  const supabase =
    await createClient();

  const scopedVisitResult =
    await loadScopedSiteVisit(
      supabase,
      cleanOrganizationId,
      cleanSiteVisitId,
      "check_in",
    );

  if (!scopedVisitResult.ok) {
    return scopedVisitResult.result;
  }

  const {
    data,
    error,
  } = await supabase.rpc(
    "check_in_site_visit",
    {
      requested_site_visit_id:
        cleanSiteVisitId,

      requested_party:
        values.party,

      requested_latitude:
        cleanLatitude,

      requested_longitude:
        cleanLongitude,

      requested_method:
        values.method,

      requested_expected_updated_at:
        cleanExpectedUpdatedAt,
    },
  );

  if (error) {
    return mapDatabaseError(
      error,
      "check_in",
    );
  }

  const result =
    parseMutationResult(
      data,
      cleanSiteVisitId,
      scopedVisitResult.row.lead_id,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The site visit check-in may have changed, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

export async function checkOutSiteVisit(
  organizationId: string,
  values: SiteVisitCheckOutValues,
): Promise<SiteVisitServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to check out a site visit.",
    );
  }

  const cleanSiteVisitId =
    normalizeRequiredUuid(
      values.siteVisitId,
    );

  if (!cleanSiteVisitId) {
    return createValidationFailure(
      "A valid site visit ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createValidationFailure(
      "The original site visit update timestamp is invalid.",
    );
  }

  if (
    !isOperationalValue(
      values.party,
      SITE_VISIT_PARTIES,
    )
  ) {
    return createValidationFailure(
      "Select a valid check-out party.",
    );
  }

  const supabase =
    await createClient();

  const scopedVisitResult =
    await loadScopedSiteVisit(
      supabase,
      cleanOrganizationId,
      cleanSiteVisitId,
      "check_out",
    );

  if (!scopedVisitResult.ok) {
    return scopedVisitResult.result;
  }

  const {
    data,
    error,
  } = await supabase.rpc(
    "check_out_site_visit",
    {
      requested_site_visit_id:
        cleanSiteVisitId,

      requested_party:
        values.party,

      requested_expected_updated_at:
        cleanExpectedUpdatedAt,
    },
  );

  if (error) {
    return mapDatabaseError(
      error,
      "check_out",
    );
  }

  const result =
    parseMutationResult(
      data,
      cleanSiteVisitId,
      scopedVisitResult.row.lead_id,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The site visit check-out may have changed, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

export async function completeSiteVisit(
  organizationId: string,
  values: CompleteSiteVisitValues,
): Promise<SiteVisitServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to complete a site visit.",
    );
  }

  const cleanSiteVisitId =
    normalizeRequiredUuid(
      values.siteVisitId,
    );

  if (!cleanSiteVisitId) {
    return createValidationFailure(
      "A valid site visit ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createValidationFailure(
      "The original site visit update timestamp is invalid.",
    );
  }

  if (
    !isOperationalValue(
      values.outcome,
      SITE_VISIT_OUTCOMES,
    )
  ) {
    return createValidationFailure(
      "Select a valid site visit outcome.",
    );
  }

  const cleanOutcomeSummary =
    normalizeOptionalText(
      values.outcomeSummary,
    );

  if (
    cleanOutcomeSummary &&
    cleanOutcomeSummary.length >
      OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    return createValidationFailure(
      `Outcome summary must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  const rawProbability =
    normalizeOptionalText(
      values.probabilityOfBooking,
    );

  const cleanProbability =
    rawProbability
      ? normalizeOptionalNumber(
          rawProbability,
        )
      : null;

  if (
    rawProbability &&
    cleanProbability === null
  ) {
    return createValidationFailure(
      "Enter a valid probability of booking.",
    );
  }

  if (
    cleanProbability !== null &&
    (
      cleanProbability <
        OPERATIONAL_FORM_LIMITS.probabilityMinimum ||
      cleanProbability >
        OPERATIONAL_FORM_LIMITS.probabilityMaximum
    )
  ) {
    return createValidationFailure(
      `Probability of booking must be between ${OPERATIONAL_FORM_LIMITS.probabilityMinimum} and ${OPERATIONAL_FORM_LIMITS.probabilityMaximum}.`,
    );
  }

  const cleanAgentNotes =
    normalizeOptionalText(
      values.agentNotes,
    );

  if (
    cleanAgentNotes &&
    cleanAgentNotes.length >
      OPERATIONAL_FORM_LIMITS.notes
  ) {
    return createValidationFailure(
      `Agent notes must not exceed ${OPERATIONAL_FORM_LIMITS.notes} characters.`,
    );
  }

  const supabase =
    await createClient();

  const scopedVisitResult =
    await loadScopedSiteVisit(
      supabase,
      cleanOrganizationId,
      cleanSiteVisitId,
      "complete",
    );

  if (!scopedVisitResult.ok) {
    return scopedVisitResult.result;
  }

  const {
    data,
    error,
  } = await supabase.rpc(
    "complete_site_visit",
    {
      requested_site_visit_id:
        cleanSiteVisitId,

      requested_outcome:
        values.outcome,

      requested_outcome_summary:
        cleanOutcomeSummary,

      requested_probability_of_booking:
        cleanProbability,

      requested_agent_notes:
        cleanAgentNotes,

      requested_expected_updated_at:
        cleanExpectedUpdatedAt,
    },
  );

  if (error) {
    return mapDatabaseError(
      error,
      "complete",
    );
  }

  const result =
    parseMutationResult(
      data,
      cleanSiteVisitId,
      scopedVisitResult.row.lead_id,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The site visit completion may have changed, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

export async function cancelSiteVisit(
  organizationId: string,
  values: CancelSiteVisitValues,
): Promise<SiteVisitServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to cancel a site visit.",
    );
  }

  const cleanSiteVisitId =
    normalizeRequiredUuid(
      values.siteVisitId,
    );

  if (!cleanSiteVisitId) {
    return createValidationFailure(
      "A valid site visit ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
    normalizeExpectedUpdatedAt(
      values.expectedUpdatedAt,
    );

  if (!cleanExpectedUpdatedAt) {
    return createValidationFailure(
      "The original site visit update timestamp is invalid.",
    );
  }

  const cleanReason =
    normalizeOptionalText(
      values.reason,
    );

  if (!cleanReason) {
    return createValidationFailure(
      "Enter a cancellation reason.",
    );
  }

  if (
    cleanReason.length >
      OPERATIONAL_FORM_LIMITS.reason
  ) {
    return createValidationFailure(
      `Cancellation reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  const supabase =
    await createClient();

  const scopedVisitResult =
    await loadScopedSiteVisit(
      supabase,
      cleanOrganizationId,
      cleanSiteVisitId,
      "cancel",
    );

  if (!scopedVisitResult.ok) {
    return scopedVisitResult.result;
  }

  const {
    data,
    error,
  } = await supabase.rpc(
    "cancel_site_visit",
    {
      requested_site_visit_id:
        cleanSiteVisitId,

      requested_reason:
        cleanReason,

      requested_expected_updated_at:
        cleanExpectedUpdatedAt,
    },
  );

  if (error) {
    return mapDatabaseError(
      error,
      "cancel",
    );
  }

  const result =
    parseMutationResult(
      data,
      cleanSiteVisitId,
      scopedVisitResult.row.lead_id,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The site visit cancellation may have changed, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}