import "server-only";

import { createClient } from "@/lib/supabase/server";

import {
  FOLLOW_UP_TYPES,
  OPERATIONAL_FORM_LIMITS,
  OPERATIONAL_PRIORITIES,
  isOperationalValue,
} from "@/lib/leads/lead-operational-contract";

import type {
  AssignFollowUpValues,
  CompleteFollowUpValues,
  CreateFollowUpValues,
  RescheduleFollowUpValues,
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

type ScopedFollowUpRow = {
  id: string;
  lead_id: string;
  updated_at: string;
};

type FollowUpMutationRow = {
  id?: unknown;
  lead_id?: unknown;
  updated_at?: unknown;
};

type ServerSupabaseClient =
  Awaited<ReturnType<typeof createClient>>;

export type FollowUpTaskServiceErrorCode =
  | "validation"
  | "not_found"
  | "permission_denied"
  | "conflict"
  | "invalid_assignee"
  | "invalid_state"
  | "database_error";

export type FollowUpTaskServiceResult =
  | {
      ok: true;
      taskId: string;
      leadId: string;
      updatedAt: string;
    }
  | {
      ok: false;
      code: FollowUpTaskServiceErrorCode;
      message: string;
    };

type FollowUpOperation =
  | "create"
  | "assign"
  | "complete"
  | "reschedule";

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
): FollowUpTaskServiceResult {
  return {
    ok: false,
    code: "validation",
    message,
  };
}

function normalizeRequiredUuid(
  value: string,
  label: string,
): string | null {
  const normalizedValue =
    value.trim();

  if (
    !normalizedValue ||
    !isValidUuid(normalizedValue)
  ) {
    return null;
  }

  void label;

  return normalizedValue;
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
  operation: FollowUpOperation,
): string {
  switch (operation) {
    case "create":
      return "The follow-up task could not be created.";

    case "assign":
      return "The follow-up task could not be assigned.";

    case "reschedule":
      return "The follow-up task could not be rescheduled.";

    case "complete":
      return "The follow-up task could not be completed.";
  }
}

function getTimeoutMessage(
  operation: FollowUpOperation,
): string {
  switch (operation) {
    case "create":
      return "The request timed out. Reload the lead page to verify whether the follow-up was created before trying again.";

    case "assign":
      return "The request timed out. Reload the lead page to verify the latest follow-up assignment before trying again.";

    case "reschedule":
      return "The request timed out. Reload the lead page to verify the latest follow-up schedule before trying again.";

    case "complete":
      return "The request timed out. Reload the lead page to verify the latest follow-up status before trying again.";
  }
}

function mapDatabaseError(
  error: DatabaseErrorLike,
  operation: FollowUpOperation,
): FollowUpTaskServiceResult {
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
        "You do not have permission to perform this follow-up action.",
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
        "This follow-up was changed by another user or request. Reload the latest version before trying again.",
    };
  }

  if (
    error.code === "P0002" ||
    normalizedMessage.includes(
      "follow-up task not found",
    ) ||
    normalizedMessage.includes(
      "follow up task not found",
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
        "The lead or follow-up task does not exist, is no longer available, or is outside the active organization.",
    };
  }

  if (
    error.code === "23503" ||
    normalizedMessage.includes(
      "active organization member",
    ) ||
    normalizedMessage.includes(
      "assigned user",
    ) ||
    normalizedMessage.includes(
      "invalid assignee",
    )
  ) {
    return {
      ok: false,
      code: "invalid_assignee",
      message:
        "The selected assignee is not an active member of this organization.",
    };
  }

  if (
    error.code === "23514" ||
    error.code === "22P02" ||
    normalizedMessage.includes(
      "invalid follow-up",
    ) ||
    normalizedMessage.includes(
      "invalid follow up",
    ) ||
    normalizedMessage.includes(
      "already completed",
    ) ||
    normalizedMessage.includes(
      "already cancelled",
    ) ||
    normalizedMessage.includes(
      "cannot be rescheduled",
    ) ||
    normalizedMessage.includes(
      "cannot be completed",
    ) ||
    normalizedMessage.includes(
      "invalid status",
    )
  ) {
    return {
      ok: false,
      code: "invalid_state",
      message:
        "The follow-up action is not valid for the task's current state.",
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
      result: FollowUpTaskServiceResult;
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

async function loadScopedFollowUpTask(
  supabase: ServerSupabaseClient,
  organizationId: string,
  taskId: string,
  operation: FollowUpOperation,
): Promise<
  | {
      ok: true;
      row: ScopedFollowUpRow;
    }
  | {
      ok: false;
      result: FollowUpTaskServiceResult;
    }
> {
  const {
    data,
    error,
  } = await supabase
    .from("follow_up_tasks")
    .select(
      "id, lead_id, updated_at",
    )
    .eq(
      "organization_id",
      organizationId,
    )
    .eq(
      "id",
      taskId,
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
      | ScopedFollowUpRow
      | null;

  if (!row) {
    return {
      ok: false,
      result: {
        ok: false,
        code: "not_found",
        message:
          "The follow-up task does not exist, is no longer available, or is outside the active organization.",
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
): FollowUpMutationRow | null {
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
    FollowUpMutationRow;
}

function parseMutationResult(
  data: unknown,
  expectedTaskId?: string,
  expectedLeadId?: string,
): FollowUpTaskServiceResult | null {
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

  const taskId =
    payload.id.trim();

  const leadId =
    payload.lead_id.trim();

  const updatedAt =
    payload.updated_at.trim();

  if (
    !taskId ||
    !leadId ||
    !updatedAt ||
    (
      expectedTaskId &&
      taskId !== expectedTaskId
    ) ||
    (
      expectedLeadId &&
      leadId !== expectedLeadId
    )
  ) {
    return null;
  }

  const parsedUpdatedAt =
    new Date(updatedAt);

  if (
    Number.isNaN(
      parsedUpdatedAt.getTime(),
    )
  ) {
    return null;
  }

  return {
    ok: true,
    taskId,
    leadId,
    updatedAt,
  };
}

export async function createFollowUpTask(
  organizationId: string,
  values: CreateFollowUpValues,
): Promise<FollowUpTaskServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
      "Organization ID",
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to create a follow-up.",
    );
  }

  const cleanLeadId =
    normalizeRequiredUuid(
      values.leadId,
      "Lead ID",
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
      "Enter a title for the follow-up.",
    );
  }

  if (
    cleanTitle.length >
    OPERATIONAL_FORM_LIMITS.title
  ) {
    return createValidationFailure(
      `Follow-up title must not exceed ${OPERATIONAL_FORM_LIMITS.title} characters.`,
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
      `Follow-up description must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (
    !isOperationalValue(
      values.followUpType,
      FOLLOW_UP_TYPES,
    )
  ) {
    return createValidationFailure(
      "Select a valid follow-up type.",
    );
  }

  if (
    !isOperationalValue(
      values.priority,
      OPERATIONAL_PRIORITIES,
    )
  ) {
    return createValidationFailure(
      "Select a valid follow-up priority.",
    );
  }

  const cleanAssignedTo =
    normalizeOptionalText(
      values.assignedTo,
    );

  if (
    cleanAssignedTo &&
    !isValidUuid(cleanAssignedTo)
  ) {
    return createValidationFailure(
      "The selected follow-up assignee is invalid.",
    );
  }

  const cleanDueAt =
    normalizeTimestamp(
      values.dueAt,
    );

  if (!cleanDueAt) {
    return createValidationFailure(
      "Enter a valid follow-up due date and time.",
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
    new Date(cleanReminderAt).getTime() >
      new Date(cleanDueAt).getTime()
  ) {
    return createValidationFailure(
      "The reminder must be scheduled on or before the follow-up due time.",
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
    .from("follow_up_tasks")
    .insert({
      organization_id:
        cleanOrganizationId,

      lead_id:
        cleanLeadId,

      title:
        cleanTitle,

      description:
        cleanDescription,

      follow_up_type:
        values.followUpType,

      priority:
        values.priority,

      assigned_to:
        cleanAssignedTo,

      due_at:
        cleanDueAt,

      reminder_at:
        cleanReminderAt,
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
        "The follow-up may have been created, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

export async function assignFollowUpTask(
  organizationId: string,
  values: AssignFollowUpValues,
): Promise<FollowUpTaskServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
      "Organization ID",
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to assign a follow-up.",
    );
  }

  const cleanTaskId =
    normalizeRequiredUuid(
      values.taskId,
      "Follow-up task ID",
    );

  if (!cleanTaskId) {
    return createValidationFailure(
      "A valid follow-up task ID is required.",
    );
  }

  const cleanAssignedTo =
    normalizeRequiredUuid(
      values.assignedTo,
      "Assignee ID",
    );

  if (!cleanAssignedTo) {
    return createValidationFailure(
      "Select a valid organization member for this follow-up.",
    );
  }

  /*
   * IMPORTANT:
   * Do not convert expectedUpdatedAt through Date.toISOString().
   *
   * PostgreSQL timestamptz can contain microseconds, while JavaScript Date
   * only preserves milliseconds. Converting here would change values such as:
   *
   *   2026-08-07T12:57:53.423901+00:00
   *
   * into:
   *
   *   2026-08-07T12:57:53.423Z
   *
   * and cause a false optimistic-concurrency conflict.
   */
  const cleanExpectedUpdatedAt =
    values.expectedUpdatedAt.trim();

  if (
    !cleanExpectedUpdatedAt ||
    Number.isNaN(
      Date.parse(cleanExpectedUpdatedAt),
    )
  ) {
    return createValidationFailure(
      "The original follow-up update timestamp is invalid.",
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

  const scopedTaskResult =
    await loadScopedFollowUpTask(
      supabase,
      cleanOrganizationId,
      cleanTaskId,
      "assign",
    );

  if (!scopedTaskResult.ok) {
    return scopedTaskResult.result;
  }

  const {
    data,
    error,
  } = await supabase.rpc(
    "assign_follow_up_task",
    {
      requested_task_id:
        cleanTaskId,

      requested_assigned_to:
        cleanAssignedTo,

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
      cleanTaskId,
      scopedTaskResult.row.lead_id,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The follow-up assignment may have changed, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

export async function rescheduleFollowUpTask(
  organizationId: string,
  values: RescheduleFollowUpValues,
): Promise<FollowUpTaskServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
      "Organization ID",
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to reschedule a follow-up.",
    );
  }

  const cleanTaskId =
    normalizeRequiredUuid(
      values.taskId,
      "Follow-up task ID",
    );

  if (!cleanTaskId) {
    return createValidationFailure(
      "A valid follow-up task ID is required.",
    );
  }

  /*
   * Preserve the original PostgreSQL timestamp text so
   * microsecond precision is not lost before the RPC call.
   */
  const cleanExpectedUpdatedAt =
    values.expectedUpdatedAt.trim();

  if (
    !cleanExpectedUpdatedAt ||
    Number.isNaN(
      Date.parse(cleanExpectedUpdatedAt),
    )
  ) {
    return createValidationFailure(
      "The original follow-up update timestamp is invalid.",
    );
  }

  const cleanDueAt =
    normalizeTimestamp(
      values.dueAt,
    );

  if (!cleanDueAt) {
    return createValidationFailure(
      "Enter a valid follow-up due date and time.",
    );
  }

  if (
    new Date(cleanDueAt).getTime() <=
    Date.now()
  ) {
    return createValidationFailure(
      "The rescheduled due time must be in the future.",
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
    new Date(cleanReminderAt).getTime() >
      new Date(cleanDueAt).getTime()
  ) {
    return createValidationFailure(
      "The reminder must be scheduled on or before the follow-up due time.",
    );
  }

  const cleanReason =
    values.reason
      .replace(/\s+/g, " ")
      .trim();

  if (!cleanReason) {
    return createValidationFailure(
      "Enter a reason for rescheduling this follow-up.",
    );
  }

  if (
    cleanReason.length >
    OPERATIONAL_FORM_LIMITS.reason
  ) {
    return createValidationFailure(
      `Reschedule reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  const supabase =
    await createClient();

  const scopedTaskResult =
    await loadScopedFollowUpTask(
      supabase,
      cleanOrganizationId,
      cleanTaskId,
      "reschedule",
    );

  if (!scopedTaskResult.ok) {
    return scopedTaskResult.result;
  }

  const {
    data,
    error,
  } = await supabase.rpc(
    "reschedule_follow_up_task",
    {
      requested_task_id:
        cleanTaskId,

      requested_due_at:
        cleanDueAt,

      requested_reminder_at:
        cleanReminderAt,

      requested_reason:
        cleanReason,

      requested_expected_updated_at:
        cleanExpectedUpdatedAt,
    },
  );

  if (error) {
    return mapDatabaseError(
      error,
      "reschedule",
    );
  }

  const result =
    parseMutationResult(
      data,
      cleanTaskId,
      scopedTaskResult.row.lead_id,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The follow-up may have been rescheduled, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}

export async function completeFollowUpTask(
  organizationId: string,
  values: CompleteFollowUpValues,
): Promise<FollowUpTaskServiceResult> {
  const cleanOrganizationId =
    normalizeRequiredUuid(
      organizationId,
      "Organization ID",
    );

  if (!cleanOrganizationId) {
    return createValidationFailure(
      "An active organization context is required to complete a follow-up.",
    );
  }

  const cleanTaskId =
    normalizeRequiredUuid(
      values.taskId,
      "Follow-up task ID",
    );

  if (!cleanTaskId) {
    return createValidationFailure(
      "A valid follow-up task ID is required.",
    );
  }

  const cleanExpectedUpdatedAt =
  values.expectedUpdatedAt.trim();

if (
  !cleanExpectedUpdatedAt ||
  Number.isNaN(
    Date.parse(cleanExpectedUpdatedAt),
  )
) {
  return createValidationFailure(
    "The original follow-up update timestamp is invalid.",
  );
}

  const cleanOutcome =
    values.outcome
      .replace(/\s+/g, " ")
      .trim();

  if (!cleanOutcome) {
    return createValidationFailure(
      "Enter the outcome of this follow-up.",
    );
  }

  if (
    cleanOutcome.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    return createValidationFailure(
      `Follow-up outcome must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  const cleanNotes =
    normalizeOptionalText(
      values.notes,
    );

  if (
    cleanNotes &&
    cleanNotes.length >
      OPERATIONAL_FORM_LIMITS.notes
  ) {
    return createValidationFailure(
      `Completion notes must not exceed ${OPERATIONAL_FORM_LIMITS.notes} characters.`,
    );
  }

  const supabase =
    await createClient();

  const scopedTaskResult =
    await loadScopedFollowUpTask(
      supabase,
      cleanOrganizationId,
      cleanTaskId,
      "complete",
    );

  if (!scopedTaskResult.ok) {
    return scopedTaskResult.result;
  }

  const {
    data,
    error,
  } = await supabase.rpc(
    "complete_follow_up_task",
    {
      requested_task_id:
        cleanTaskId,

      requested_outcome:
        cleanOutcome,

      requested_notes:
        cleanNotes,

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
      cleanTaskId,
      scopedTaskResult.row.lead_id,
    );

  if (!result) {
    return {
      ok: false,
      code: "database_error",
      message:
        "The follow-up may have been completed, but its response could not be verified. Reload the lead page before trying again.",
    };
  }

  return result;
}