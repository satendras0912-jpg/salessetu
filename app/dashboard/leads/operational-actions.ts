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
  manuallyAssignLead,
  manuallyUnassignLead,
  type LeadAssignmentServiceResult,
} from "@/lib/leads/lead-assignment-service";

import {
  assignFollowUpTask,
  completeFollowUpTask,
  createFollowUpTask,
  type FollowUpTaskServiceResult,
} from "@/lib/leads/follow-up-task-service";

import {
  assignSiteVisit,
  cancelSiteVisit,
  checkInSiteVisit,
  checkOutSiteVisit,
  completeSiteVisit,
  createSiteVisit,
  type SiteVisitServiceResult,
} from "@/lib/leads/site-visit-service";

import {
  FOLLOW_UP_TYPES,
  LEAD_LIFECYCLE_STAGES,
  LEAD_OPERATIONAL_PERMISSIONS,
  LEAD_STATUSES,
  LEAD_TEMPERATURES,
  OPERATIONAL_FORM_LIMITS,
  OPERATIONAL_PRIORITIES,
  isOperationalValue,
  SITE_VISIT_CHECK_IN_METHODS,
SITE_VISIT_OUTCOMES,
SITE_VISIT_PARTIES,
SITE_VISIT_TYPES,
} from "@/lib/leads/lead-operational-contract";

import {
  LeadStatusTransitionError,
  transitionLeadStatusRecord,
} from "@/lib/leads/lead-status-transition-service";

import type {
  AssignFollowUpValues,
  CompleteFollowUpValues,
  CreateFollowUpValues,
  AssignSiteVisitValues,
CancelSiteVisitValues,
CompleteSiteVisitValues,
CreateSiteVisitValues,
SiteVisitCheckInValues,
SiteVisitCheckOutValues,
  LeadStatusTransitionValues,
  OperationalActionState,
  OperationalFieldErrors,
} from "@/types/lead-operational-controls";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type StatusTransitionParseResult =
  | {
      success: true;
      values: LeadStatusTransitionValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type ManualAssignmentValues = {
  leadId: string;
  agentProfileId: string;
  teamId: string | null;
  reason: string;
  overrideCapacity: boolean;
};

type ManualAssignmentParseResult =
  | {
      success: true;
      values: ManualAssignmentValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type ManualUnassignmentValues = {
  leadId: string;
  reason: string;
};

type ManualUnassignmentParseResult =
  | {
      success: true;
      values: ManualUnassignmentValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type CreateFollowUpParseResult =
  | {
      success: true;
      values: CreateFollowUpValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type AssignFollowUpParseResult =
  | {
      success: true;
      values: AssignFollowUpValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type CompleteFollowUpParseResult =
  | {
      success: true;
      values: CompleteFollowUpValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

    type CreateSiteVisitParseResult =
  | {
      success: true;
      values: CreateSiteVisitValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type AssignSiteVisitParseResult =
  | {
      success: true;
      values: AssignSiteVisitValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type CheckInSiteVisitParseResult =
  | {
      success: true;
      values: SiteVisitCheckInValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type CheckOutSiteVisitParseResult =
  | {
      success: true;
      values: SiteVisitCheckOutValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type CompleteSiteVisitParseResult =
  | {
      success: true;
      values: CompleteSiteVisitValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type CancelSiteVisitParseResult =
  | {
      success: true;
      values: CancelSiteVisitValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: OperationalFieldErrors;
    };

type AssignmentFailureResult = Extract<
  LeadAssignmentServiceResult,
  {
    ok: false;
  }
>;

type FollowUpFailureResult = Extract<
  FollowUpTaskServiceResult,
  {
    ok: false;
  }
>;

type SiteVisitFailureResult = Extract<
  SiteVisitServiceResult,
  {
    ok: false;
  }
>;

function getFormString(
  formData: FormData,
  fieldName: string,
): string {
  const value =
    formData.get(fieldName);

  return typeof value === "string"
    ? value
    : "";
}

function getFormBoolean(
  formData: FormData,
  fieldName: string,
): boolean {
  const value =
    getFormString(
      formData,
      fieldName,
    )
      .trim()
      .toLowerCase();

  return [
    "1",
    "true",
    "on",
    "yes",
  ].includes(value);
}

function normalizeSingleLine(
  value: string,
): string {
  return value
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeMultiline(
  value: string,
): string {
  return value
    .replace(/\r\n/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .trim();
}

function addFieldError(
  errors: OperationalFieldErrors,
  fieldName: string,
  message: string,
): void {
  const existingErrors =
    errors[fieldName] ?? [];

  errors[fieldName] = [
    ...existingErrors,
    message,
  ];
}

function hasFieldErrors(
  errors: OperationalFieldErrors,
): boolean {
  return Object.values(errors).some(
    (messages) =>
      Array.isArray(messages) &&
      messages.length > 0,
  );
}

function createErrorState(
  message: string,
  fieldErrors:
    OperationalFieldErrors = {},
): OperationalActionState {
  return {
    status: "error",
    message,
    fieldErrors,
  };
}

function parseStatusTransitionForm(
  formData: FormData,
): StatusTransitionParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const leadId =
    normalizeSingleLine(
      getFormString(
        formData,
        "leadId",
      ),
    );

  const expectedUpdatedAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const leadStatus =
    normalizeSingleLine(
      getFormString(
        formData,
        "leadStatus",
      ),
    );

  const lifecycleStage =
    normalizeSingleLine(
      getFormString(
        formData,
        "lifecycleStage",
      ),
    );

  const leadTemperature =
    normalizeSingleLine(
      getFormString(
        formData,
        "leadTemperature",
      ),
    );

  const reason =
    normalizeMultiline(
      getFormString(
        formData,
        "reason",
      ),
    );

  if (!leadId) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(leadId)
  ) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is not a valid UUID.",
    );
  }

  if (!expectedUpdatedAt) {

    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is required.",
    );
  } else {
    const parsedTimestamp =
      new Date(expectedUpdatedAt);

    if (
      Number.isNaN(
        parsedTimestamp.getTime(),
      )
    ) {
      addFieldError(
        fieldErrors,
        "expectedUpdatedAt",
        "The original update timestamp is invalid.",
      );
    }
  }

  if (
    !isOperationalValue(
      leadStatus,
      LEAD_STATUSES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "leadStatus",
      "Select a valid lead status.",
    );
  }

  if (
    !isOperationalValue(
      lifecycleStage,
      LEAD_LIFECYCLE_STAGES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "lifecycleStage",
      "Select a valid lifecycle stage.",
    );
  }

  if (
    leadTemperature &&
    !isOperationalValue(
      leadTemperature,
      LEAD_TEMPERATURES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "leadTemperature",
      "Select a valid lead temperature.",
    );
  }

  if (!reason) {
    addFieldError(
      fieldErrors,
      "reason",
      "Enter a reason for this status transition.",
    );
  } else if (
    reason.length >
    OPERATIONAL_FORM_LIMITS.reason
  ) {
    addFieldError(
      fieldErrors,
      "reason",
      `Reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted status-transition fields.",
      fieldErrors,
    };
  }

  return {
    success: true,

    values: {
      leadId,
      expectedUpdatedAt,

      leadStatus:
        leadStatus as LeadStatusTransitionValues["leadStatus"],

      lifecycleStage:
        lifecycleStage as LeadStatusTransitionValues["lifecycleStage"],

      leadTemperature:
        leadTemperature as LeadStatusTransitionValues["leadTemperature"],

      reason,
    },
  };
}

function parseManualAssignmentForm(
  formData: FormData,
): ManualAssignmentParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const leadId =
    normalizeSingleLine(
      getFormString(
        formData,
        "leadId",
      ),
    );

  const agentProfileId =
    normalizeSingleLine(
      getFormString(
        formData,
        "agentProfileId",
      ),
    );

  const normalizedTeamId =
    normalizeSingleLine(
      getFormString(
        formData,
        "teamId",
      ),
    );

  const reason =
    normalizeMultiline(
      getFormString(
        formData,
        "reason",
      ),
    );

  const overrideCapacity =
    getFormBoolean(
      formData,
      "overrideCapacity",
    );

  if (!leadId) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(leadId)
  ) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is not a valid UUID.",
    );
  }

  if (!agentProfileId) {
    addFieldError(
      fieldErrors,
      "agentProfileId",
      "Select an agent for this lead.",
    );
  } else if (
    !UUID_PATTERN.test(
      agentProfileId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "agentProfileId",
      "The selected agent profile is invalid.",
    );
  }

  if (
    normalizedTeamId &&
    !UUID_PATTERN.test(
      normalizedTeamId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "teamId",
      "The selected assignment team is invalid.",
    );
  }

  if (!reason) {
    addFieldError(
      fieldErrors,
      "reason",
      "Enter a reason for assigning this lead.",
    );
  } else if (
    reason.length >
    OPERATIONAL_FORM_LIMITS.reason
  ) {
    addFieldError(
      fieldErrors,
      "reason",
      `Reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted assignment fields.",
      fieldErrors,
    };
  }

  return {
    success: true,

    values: {
      leadId,
      agentProfileId,

      teamId:
        normalizedTeamId || null,

      reason,
      overrideCapacity,
    },
  };
}

function parseManualUnassignmentForm(
  formData: FormData,
): ManualUnassignmentParseResult {
  const fieldErrors:

    OperationalFieldErrors = {};

  const leadId =
    normalizeSingleLine(
      getFormString(
        formData,
        "leadId",
      ),
    );

  const reason =
    normalizeMultiline(
      getFormString(
        formData,
        "reason",
      ),
    );

  if (!leadId) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(leadId)
  ) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is not a valid UUID.",
    );
  }

  if (!reason) {
    addFieldError(
      fieldErrors,
      "reason",
      "Enter a reason for removing this assignment.",
    );
  } else if (
    reason.length >
    OPERATIONAL_FORM_LIMITS.reason
  ) {
    addFieldError(
      fieldErrors,
      "reason",
      `Reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted unassignment fields.",
      fieldErrors,
    };
  }

  return {
    success: true,

    values: {
      leadId,
      reason,
    },
  };
}

function parseCreateFollowUpForm(
  formData: FormData,
): CreateFollowUpParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const leadId =
    normalizeSingleLine(
      getFormString(
        formData,
        "leadId",
      ),
    );

  const title =
    normalizeSingleLine(
      getFormString(
        formData,
        "title",
      ),
    );

  const description =
    normalizeMultiline(
      getFormString(
        formData,
        "description",
      ),
    );

  const followUpType =
    normalizeSingleLine(
      getFormString(
        formData,
        "followUpType",
      ),
    );

  const priority =
    normalizeSingleLine(
      getFormString(
        formData,
        "priority",
      ),
    );

  const assignedTo =
    normalizeSingleLine(
      getFormString(
        formData,
        "assignedTo",
      ),
    );

  const dueAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "dueAt",
      ),
    );

  const reminderAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "reminderAt",
      ),
    );

  if (!leadId) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(leadId)
  ) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is not a valid UUID.",
    );
  }

  if (!title) {
    addFieldError(
      fieldErrors,
      "title",
      "Enter a title for this follow-up.",
    );
  } else if (
    title.length >
    OPERATIONAL_FORM_LIMITS.title
  ) {
    addFieldError(
      fieldErrors,
      "title",
      `Title must not exceed ${OPERATIONAL_FORM_LIMITS.title} characters.`,
    );
  }

  if (
    description.length >
    OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    addFieldError(
      fieldErrors,
      "description",
      `Description must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (
    !isOperationalValue(
      followUpType,
      FOLLOW_UP_TYPES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "followUpType",
      "Select a valid follow-up type.",
    );
  }

  if (
    !isOperationalValue(
      priority,
      OPERATIONAL_PRIORITIES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "priority",
      "Select a valid follow-up priority.",
    );
  }

  if (
    assignedTo &&
    !UUID_PATTERN.test(assignedTo)
  ) {
    addFieldError(
      fieldErrors,
      "assignedTo",
      "The selected assignee is invalid.",
    );
  }

  let parsedDueAt:
    Date | null = null;

  if (!dueAt) {
    addFieldError(
      fieldErrors,
      "dueAt",
      "Select a due date and time.",
    );
  } else {
    parsedDueAt =
      new Date(dueAt);

    if (
      Number.isNaN(
        parsedDueAt.getTime(),
      )
    ) {
      parsedDueAt = null;

      addFieldError(
        fieldErrors,
        "dueAt",
        "The due date and time are invalid.",
      );
    }
  }

  if (reminderAt) {
    const parsedReminderAt =
      new Date(reminderAt);

    if (
      Number.isNaN(
        parsedReminderAt.getTime(),
      )
    ) {
      addFieldError(
        fieldErrors,
        "reminderAt",
        "The reminder date and time are invalid.",
      );
    } else if (
      parsedDueAt &&
      parsedReminderAt.getTime() >
        parsedDueAt.getTime()
    ) {
      addFieldError(
        fieldErrors,
        "reminderAt",
        "The reminder must be on or before the due time.",
      );
    }
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted follow-up fields.",
      fieldErrors,
    };
  }

  return {
    success: true,

    values: {
      leadId,
      title,
      description,

      followUpType:
        followUpType as
          CreateFollowUpValues["followUpType"],

      priority:
        priority as
          CreateFollowUpValues["priority"],

      assignedTo,
      dueAt,
      reminderAt,
    },
  };
}

function parseAssignFollowUpForm(
  formData: FormData,
): AssignFollowUpParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const taskId =
    normalizeSingleLine(
      getFormString(
        formData,
        "taskId",
      ),
    );

  const expectedUpdatedAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const assignedTo =
    normalizeSingleLine(
      getFormString(
        formData,
        "assignedTo",
      ),
    );

  const reason =
    normalizeMultiline(
      getFormString(
        formData,
        "reason",
      ),
    );

  if (!taskId) {
    addFieldError(
      fieldErrors,
      "taskId",
      "Follow-up task ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(taskId)
  ) {
    addFieldError(
      fieldErrors,
      "taskId",
      "The follow-up task ID is invalid.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is required.",
    );
  } else {
    const parsedTimestamp =
      new Date(expectedUpdatedAt);

    if (
      Number.isNaN(
        parsedTimestamp.getTime(),
      )
    ) {
      addFieldError(
        fieldErrors,
        "expectedUpdatedAt",
        "The original update timestamp is invalid.",
      );
    }
  }

  if (!assignedTo) {
    addFieldError(
      fieldErrors,
      "assignedTo",
      "Select an organization member.",
    );
  } else if (
    !UUID_PATTERN.test(assignedTo)
  ) {
    addFieldError(
      fieldErrors,
      "assignedTo",
      "The selected assignee is invalid.",
    );
  }

  if (!reason) {
    addFieldError(
      fieldErrors,
      "reason",
      "Enter a reason for assigning this follow-up.",
    );
  } else if (
    reason.length >
    OPERATIONAL_FORM_LIMITS.reason
  ) {
    addFieldError(
      fieldErrors,
      "reason",
      `Reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted follow-up assignment fields.",
      fieldErrors,
    };
  }

  return {
    success: true,

    values: {
      taskId,
      expectedUpdatedAt,
      assignedTo,
      reason,
    },
  };
}

function parseCompleteFollowUpForm(
  formData: FormData,
): CompleteFollowUpParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const taskId =
    normalizeSingleLine(
      getFormString(
        formData,
        "taskId",
      ),
    );

  const expectedUpdatedAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const outcome =
    normalizeSingleLine(
      getFormString(
        formData,
        "outcome",
      ),
    );

  const notes =
    normalizeMultiline(
      getFormString(
        formData,
        "notes",
      ),
    );

  if (!taskId) {
    addFieldError(
      fieldErrors,
      "taskId",
      "Follow-up task ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(taskId)
  ) {
    addFieldError(
      fieldErrors,
      "taskId",
      "The follow-up task ID is invalid.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is required.",
    );
  } else {
    const parsedTimestamp =
      new Date(expectedUpdatedAt);

    if (
      Number.isNaN(
        parsedTimestamp.getTime(),
      )
    ) {
      addFieldError(
        fieldErrors,
        "expectedUpdatedAt",
        "The original update timestamp is invalid.",
      );
    }
  }

  if (!outcome) {
    addFieldError(
      fieldErrors,
      "outcome",
      "Enter the outcome of this follow-up.",
    );
  } else if (
    outcome.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    addFieldError(
      fieldErrors,
      "outcome",
      `Outcome must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    notes.length >
    OPERATIONAL_FORM_LIMITS.notes
  ) {
    addFieldError(
      fieldErrors,
      "notes",
      `Notes must not exceed ${OPERATIONAL_FORM_LIMITS.notes} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted follow-up completion fields.",
      fieldErrors,
    };
  }

  return {
    success: true,

    values: {
      taskId,
      expectedUpdatedAt,
      outcome,
      notes,
    },
  };
}

function parseCreateSiteVisitForm(
  formData: FormData,
): CreateSiteVisitParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const leadId =
    normalizeSingleLine(
      getFormString(
        formData,
        "leadId",
      ),
    );

  const title =
    normalizeSingleLine(
      getFormString(
        formData,
        "title",
      ),
    );

  const description =
    normalizeMultiline(
      getFormString(
        formData,
        "description",
      ),
    );

  const visitType =
    normalizeSingleLine(
      getFormString(
        formData,
        "visitType",
      ),
    );

  const priority =
    normalizeSingleLine(
      getFormString(
        formData,
        "priority",
      ),
    );

  const projectName =
    normalizeSingleLine(
      getFormString(
        formData,
        "projectName",
      ),
    );

  const developerName =
    normalizeSingleLine(
      getFormString(
        formData,
        "developerName",
      ),
    );

  const propertyName =
    normalizeSingleLine(
      getFormString(
        formData,
        "propertyName",
      ),
    );

  const unitType =
    normalizeSingleLine(
      getFormString(
        formData,
        "unitType",
      ),
    );

  const visitAddress =
    normalizeMultiline(
      getFormString(
        formData,
        "visitAddress",
      ),
    );

  const visitCity =
    normalizeSingleLine(
      getFormString(
        formData,
        "visitCity",
      ),
    );

  const locationUrl =
    normalizeSingleLine(
      getFormString(
        formData,
        "locationUrl",
      ),
    );

  const scheduledStartAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "scheduledStartAt",
      ),
    );

  const scheduledEndAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "scheduledEndAt",
      ),
    );

  const timezone =
    normalizeSingleLine(
      getFormString(
        formData,
        "timezone",
      ),
    );

  const assignedAgentId =
    normalizeSingleLine(
      getFormString(
        formData,
        "assignedAgentId",
      ),
    );

  const coordinatorId =
    normalizeSingleLine(
      getFormString(
        formData,
        "coordinatorId",
      ),
    );

  const reminderAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "reminderAt",
      ),
    );

  const pickupRequired =
    getFormBoolean(
      formData,
      "pickupRequired",
    );

  const pickupAddress =
    normalizeMultiline(
      getFormString(
        formData,
        "pickupAddress",
      ),
    );

  const pickupTime =
    normalizeSingleLine(
      getFormString(
        formData,
        "pickupTime",
      ),
    );

  const transportNotes =
    normalizeMultiline(
      getFormString(
        formData,
        "transportNotes",
      ),
    );

  if (!leadId) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(leadId)
  ) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Lead ID is not a valid UUID.",
    );
  }

  if (!title) {
    addFieldError(
      fieldErrors,
      "title",
      "Enter a title for this site visit.",
    );
  } else if (
    title.length >
    OPERATIONAL_FORM_LIMITS.title
  ) {
    addFieldError(
      fieldErrors,
      "title",
      `Title must not exceed ${OPERATIONAL_FORM_LIMITS.title} characters.`,
    );
  }

  if (
    description.length >
    OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    addFieldError(
      fieldErrors,
      "description",
      `Description must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (
    !isOperationalValue(
      visitType,
      SITE_VISIT_TYPES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "visitType",
      "Select a valid site visit type.",
    );
  }

  if (
    !isOperationalValue(
      priority,
      OPERATIONAL_PRIORITIES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "priority",
      "Select a valid site visit priority.",
    );
  }

  if (!projectName) {
    addFieldError(
      fieldErrors,
      "projectName",
      "Enter the project name.",
    );
  } else if (
    projectName.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    addFieldError(
      fieldErrors,
      "projectName",
      `Project name must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    developerName.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    addFieldError(
      fieldErrors,
      "developerName",
      `Developer name must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    propertyName.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    addFieldError(
      fieldErrors,
      "propertyName",
      `Property name must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    unitType.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    addFieldError(
      fieldErrors,
      "unitType",
      `Unit type must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    visitAddress.length >
    OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    addFieldError(
      fieldErrors,
      "visitAddress",
      `Visit address must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (
    visitCity.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    addFieldError(
      fieldErrors,
      "visitCity",
      `Visit city must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (
    locationUrl.length >
    OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    addFieldError(
      fieldErrors,
      "locationUrl",
      `Location URL must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (
    assignedAgentId &&
    !UUID_PATTERN.test(
      assignedAgentId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "assignedAgentId",
      "The selected site visit agent is invalid.",
    );
  }

  if (
    coordinatorId &&
    !UUID_PATTERN.test(
      coordinatorId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "coordinatorId",
      "The selected site visit coordinator is invalid.",
    );
  }

  let parsedStartAt:
    Date | null = null;

  if (!scheduledStartAt) {
    addFieldError(
      fieldErrors,
      "scheduledStartAt",
      "Select a site visit start date and time.",
    );
  } else {
    parsedStartAt =
      new Date(
        scheduledStartAt,
      );

    if (
      Number.isNaN(
        parsedStartAt.getTime(),
      )
    ) {
      parsedStartAt = null;

      addFieldError(
        fieldErrors,
        "scheduledStartAt",
        "The site visit start date and time are invalid.",
      );
    }
  }

  if (scheduledEndAt) {
    const parsedEndAt =
      new Date(
        scheduledEndAt,
      );

    if (
      Number.isNaN(
        parsedEndAt.getTime(),
      )
    ) {
      addFieldError(
        fieldErrors,
        "scheduledEndAt",
        "The site visit end date and time are invalid.",
      );
    } else if (
      parsedStartAt &&
      parsedEndAt.getTime() <
        parsedStartAt.getTime()
    ) {
      addFieldError(
        fieldErrors,
        "scheduledEndAt",
        "The site visit end time cannot be before the start time.",
      );
    }
  }

  if (
    timezone.length >
    OPERATIONAL_FORM_LIMITS.shortText
  ) {
    addFieldError(
      fieldErrors,
      "timezone",
      `Timezone must not exceed ${OPERATIONAL_FORM_LIMITS.shortText} characters.`,
    );
  }

  if (reminderAt) {
    const parsedReminderAt =
      new Date(
        reminderAt,
      );

    if (
      Number.isNaN(
        parsedReminderAt.getTime(),
      )
    ) {
      addFieldError(
        fieldErrors,
        "reminderAt",
        "The reminder date and time are invalid.",
      );
    } else if (
      parsedStartAt &&
      parsedReminderAt.getTime() >
        parsedStartAt.getTime()
    ) {
      addFieldError(
        fieldErrors,
        "reminderAt",
        "The reminder must be on or before the site visit start time.",
      );
    }
  }

  if (
    pickupAddress.length >
    OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    addFieldError(
      fieldErrors,
      "pickupAddress",
      `Pickup address must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (pickupTime) {
    const parsedPickupTime =
      new Date(
        pickupTime,
      );

    if (
      Number.isNaN(
        parsedPickupTime.getTime(),
      )
    ) {
      addFieldError(
        fieldErrors,
        "pickupTime",
        "The pickup date and time are invalid.",
      );
    } else if (
      parsedStartAt &&
      parsedPickupTime.getTime() >
        parsedStartAt.getTime()
    ) {
      addFieldError(
        fieldErrors,
        "pickupTime",
        "Pickup time must be on or before the site visit start time.",
      );
    }
  }

  if (
    transportNotes.length >
    OPERATIONAL_FORM_LIMITS.notes
  ) {
    addFieldError(
      fieldErrors,
      "transportNotes",
      `Transport notes must not exceed ${OPERATIONAL_FORM_LIMITS.notes} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted site visit fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      leadId,
      title,
      description,

      visitType:
        visitType as
          CreateSiteVisitValues["visitType"],

      priority:
        priority as
          CreateSiteVisitValues["priority"],

      projectName,
      developerName,
      propertyName,
      unitType,

      visitAddress,
      visitCity,
      locationUrl,

      scheduledStartAt,
      scheduledEndAt,
      timezone,

      assignedAgentId,
      coordinatorId,

      reminderAt,

      pickupRequired,
      pickupAddress,
      pickupTime,
      transportNotes,
    },
  };
}

function parseAssignSiteVisitForm(
  formData: FormData,
): AssignSiteVisitParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const siteVisitId =
    normalizeSingleLine(
      getFormString(
        formData,
        "siteVisitId",
      ),
    );

  const expectedUpdatedAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const assignedAgentId =
    normalizeSingleLine(
      getFormString(
        formData,
        "assignedAgentId",
      ),
    );

  const coordinatorId =
    normalizeSingleLine(
      getFormString(
        formData,
        "coordinatorId",
      ),
    );

  const reason =
    normalizeMultiline(
      getFormString(
        formData,
        "reason",
      ),
    );

  if (!siteVisitId) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "Site visit ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(siteVisitId)
  ) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "The site visit ID is invalid.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is required.",
    );
  } else {
    const parsedTimestamp =
      new Date(expectedUpdatedAt);

    if (
      Number.isNaN(
        parsedTimestamp.getTime(),
      )
    ) {
      addFieldError(
        fieldErrors,
        "expectedUpdatedAt",
        "The original update timestamp is invalid.",
      );
    }
  }

  if (
    assignedAgentId &&
    !UUID_PATTERN.test(
      assignedAgentId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "assignedAgentId",
      "The selected site visit agent is invalid.",
    );
  }

  if (
    coordinatorId &&
    !UUID_PATTERN.test(
      coordinatorId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "coordinatorId",
      "The selected site visit coordinator is invalid.",
    );
  }

  if (
    reason.length >
    OPERATIONAL_FORM_LIMITS.reason
  ) {
    addFieldError(
      fieldErrors,
      "reason",
      `Reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted site visit assignment fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      siteVisitId,
      expectedUpdatedAt,
      assignedAgentId,
      coordinatorId,
      reason,
    },
  };
}

function parseCheckInSiteVisitForm(
  formData: FormData,
): CheckInSiteVisitParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const siteVisitId =
    normalizeSingleLine(
      getFormString(
        formData,
        "siteVisitId",
      ),
    );

  const expectedUpdatedAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const party =
    normalizeSingleLine(
      getFormString(
        formData,
        "party",
      ),
    );

  const latitude =
    normalizeSingleLine(
      getFormString(
        formData,
        "latitude",
      ),
    );

  const longitude =
    normalizeSingleLine(
      getFormString(
        formData,
        "longitude",
      ),
    );

  const method =
    normalizeSingleLine(
      getFormString(
        formData,
        "method",
      ),
    );

  if (!siteVisitId) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "Site visit ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(siteVisitId)
  ) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "The site visit ID is invalid.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is required.",
    );
  } else if (
    Number.isNaN(
      Date.parse(expectedUpdatedAt),
    )
  ) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is invalid.",
    );
  }

  if (
    !isOperationalValue(
      party,
      SITE_VISIT_PARTIES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "party",
      "Select a valid check-in party.",
    );
  }

  if (
    !isOperationalValue(
      method,
      SITE_VISIT_CHECK_IN_METHODS,
    )
  ) {
    addFieldError(
      fieldErrors,
      "method",
      "Select a valid check-in method.",
    );
  }

  if (latitude) {
    const parsedLatitude =
      Number(latitude);

    if (
      !Number.isFinite(
        parsedLatitude,
      )
    ) {
      addFieldError(
        fieldErrors,
        "latitude",
        "Enter a valid latitude.",
      );
    } else if (
      parsedLatitude <
        OPERATIONAL_FORM_LIMITS.latitudeMinimum ||
      parsedLatitude >
        OPERATIONAL_FORM_LIMITS.latitudeMaximum
    ) {
      addFieldError(
        fieldErrors,
        "latitude",
        `Latitude must be between ${OPERATIONAL_FORM_LIMITS.latitudeMinimum} and ${OPERATIONAL_FORM_LIMITS.latitudeMaximum}.`,
      );
    }
  }

  if (longitude) {
    const parsedLongitude =
      Number(longitude);

    if (
      !Number.isFinite(
        parsedLongitude,
      )
    ) {
      addFieldError(
        fieldErrors,
        "longitude",
        "Enter a valid longitude.",
      );
    } else if (
      parsedLongitude <
        OPERATIONAL_FORM_LIMITS.longitudeMinimum ||
      parsedLongitude >
        OPERATIONAL_FORM_LIMITS.longitudeMaximum
    ) {
      addFieldError(
        fieldErrors,
        "longitude",
        `Longitude must be between ${OPERATIONAL_FORM_LIMITS.longitudeMinimum} and ${OPERATIONAL_FORM_LIMITS.longitudeMaximum}.`,
      );
    }
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted site visit check-in fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      siteVisitId,
      expectedUpdatedAt,

      party:
        party as
          SiteVisitCheckInValues["party"],

      latitude,
      longitude,

      method:
        method as
          SiteVisitCheckInValues["method"],
    },
  };
}

function parseCheckOutSiteVisitForm(
  formData: FormData,
): CheckOutSiteVisitParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const siteVisitId =
    normalizeSingleLine(
      getFormString(
        formData,
        "siteVisitId",
      ),
    );

  const expectedUpdatedAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const party =
    normalizeSingleLine(
      getFormString(
        formData,
        "party",
      ),
    );

  if (!siteVisitId) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "Site visit ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(siteVisitId)
  ) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "The site visit ID is invalid.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is required.",
    );
  } else if (
    Number.isNaN(
      Date.parse(expectedUpdatedAt),
    )
  ) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is invalid.",
    );
  }

  if (
    !isOperationalValue(
      party,
      SITE_VISIT_PARTIES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "party",
      "Select a valid check-out party.",
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted site visit check-out fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      siteVisitId,
      expectedUpdatedAt,

      party:
        party as
          SiteVisitCheckOutValues["party"],
    },
  };
}

function parseCompleteSiteVisitForm(
  formData: FormData,
): CompleteSiteVisitParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const siteVisitId =
    normalizeSingleLine(
      getFormString(
        formData,
        "siteVisitId",
      ),
    );

  const expectedUpdatedAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const outcome =
    normalizeSingleLine(
      getFormString(
        formData,
        "outcome",
      ),
    );

  const outcomeSummary =
    normalizeMultiline(
      getFormString(
        formData,
        "outcomeSummary",
      ),
    );

  const probabilityOfBooking =
    normalizeSingleLine(
      getFormString(
        formData,
        "probabilityOfBooking",
      ),
    );

  const agentNotes =
    normalizeMultiline(
      getFormString(
        formData,
        "agentNotes",
      ),
    );

  if (!siteVisitId) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "Site visit ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(siteVisitId)
  ) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "The site visit ID is invalid.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is required.",
    );
  } else if (
    Number.isNaN(
      Date.parse(expectedUpdatedAt),
    )
  ) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is invalid.",
    );
  }

  if (
    !isOperationalValue(
      outcome,
      SITE_VISIT_OUTCOMES,
    )
  ) {
    addFieldError(
      fieldErrors,
      "outcome",
      "Select a valid site visit outcome.",
    );
  }

  if (
    outcomeSummary.length >
    OPERATIONAL_FORM_LIMITS.mediumText
  ) {
    addFieldError(
      fieldErrors,
      "outcomeSummary",
      `Outcome summary must not exceed ${OPERATIONAL_FORM_LIMITS.mediumText} characters.`,
    );
  }

  if (probabilityOfBooking) {
    const parsedProbability =
      Number(
        probabilityOfBooking,
      );

    if (
      !Number.isFinite(
        parsedProbability,
      )
    ) {
      addFieldError(
        fieldErrors,
        "probabilityOfBooking",
        "Enter a valid probability of booking.",
      );
    } else if (
      parsedProbability <
        OPERATIONAL_FORM_LIMITS.probabilityMinimum ||
      parsedProbability >
        OPERATIONAL_FORM_LIMITS.probabilityMaximum
    ) {
      addFieldError(
        fieldErrors,
        "probabilityOfBooking",
        `Probability of booking must be between ${OPERATIONAL_FORM_LIMITS.probabilityMinimum} and ${OPERATIONAL_FORM_LIMITS.probabilityMaximum}.`,
      );
    }
  }

  if (
    agentNotes.length >
    OPERATIONAL_FORM_LIMITS.notes
  ) {
    addFieldError(
      fieldErrors,
      "agentNotes",
      `Agent notes must not exceed ${OPERATIONAL_FORM_LIMITS.notes} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted site visit completion fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      siteVisitId,
      expectedUpdatedAt,

      outcome:
        outcome as
          CompleteSiteVisitValues["outcome"],

      outcomeSummary,
      probabilityOfBooking,
      agentNotes,
    },
  };
}

function parseCancelSiteVisitForm(
  formData: FormData,
): CancelSiteVisitParseResult {
  const fieldErrors:
    OperationalFieldErrors = {};

  const siteVisitId =
    normalizeSingleLine(
      getFormString(
        formData,
        "siteVisitId",
      ),
    );

  const expectedUpdatedAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const reason =
    normalizeMultiline(
      getFormString(
        formData,
        "reason",
      ),
    );

  if (!siteVisitId) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "Site visit ID is required.",
    );
  } else if (
    !UUID_PATTERN.test(siteVisitId)
  ) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "The site visit ID is invalid.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is required.",
    );
  } else if (
    Number.isNaN(
      Date.parse(expectedUpdatedAt),
    )
  ) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original update timestamp is invalid.",
    );
  }

  if (!reason) {
    addFieldError(
      fieldErrors,
      "reason",
      "Enter a cancellation reason.",
    );
  } else if (
    reason.length >
    OPERATIONAL_FORM_LIMITS.reason
  ) {
    addFieldError(
      fieldErrors,
      "reason",
      `Reason must not exceed ${OPERATIONAL_FORM_LIMITS.reason} characters.`,
    );
  }

  if (
    hasFieldErrors(fieldErrors)
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted site visit cancellation fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      siteVisitId,
      expectedUpdatedAt,
      reason,
    },
  };
}

function mapTransitionError(
  error: unknown,
): OperationalActionState {
  if (
    !(
      error instanceof
      LeadStatusTransitionError
    )
  ) {
    console.error(
      "Unexpected lead status transition error:",
      error,
    );

    return createErrorState(
      "The lead status could not be changed. Please try again.",
    );
  }

  switch (error.kind) {
    case "conflict":
      return {
        status: "conflict",
        message: error.message,

        fieldErrors: {
          expectedUpdatedAt: [
            "The lead has changed since this page was loaded.",
          ],
        },
      };

    case "not_found":
      return createErrorState(
        error.message,
        {
          leadId: [
            error.message,
          ],
        },
      );

    case "permission_denied":
      return createErrorState(
        error.message,
      );

    case "invalid_transition":
      return createErrorState(
        error.message,
      );

    case "database_error":
    default:
      console.error(
        "Lead status transition database error:",
        error,
      );

      return createErrorState(
        error.message,
      );
  }
}

function mapAssignmentFailure(
  result: AssignmentFailureResult,
): OperationalActionState {
  switch (result.code) {
    case "conflict":
      return {
        status: "conflict",
        message: result.message,
        fieldErrors: {},
      };

    case "not_found":
      return createErrorState(
        result.message,
        {
          leadId: [
            result.message,
          ],
        },
      );

    case "capacity_reached":
      return createErrorState(
        result.message,
        {
          agentProfileId: [
            result.message,
          ],
        },
      );

    case "agent_unavailable":
      return createErrorState(
        result.message,
        {
          agentProfileId: [
            result.message,
          ],
        },
      );

    case "validation":
      return createErrorState(
        result.message,
      );

    case "permission_denied":
      return createErrorState(
        result.message,
      );

    case "database_error":
    default:
      console.error(
        "Lead assignment database error:",
        result,
      );

      return createErrorState(
        result.message,
      );
  }
}

function mapFollowUpFailure(
  result: FollowUpFailureResult,
  operation:
    | "create"
    | "assign"
    | "complete",
): OperationalActionState {
  switch (result.code) {
    case "conflict":
      return {
        status: "conflict",
        message: result.message,

        fieldErrors: {
          expectedUpdatedAt: [
            "The follow-up changed after this form was opened.",
          ],
        },
      };

    case "not_found":
      return createErrorState(
        result.message,
        operation === "create"
          ? {
              leadId: [
                result.message,
              ],
            }
          : {
              taskId: [
                result.message,
              ],
            },
      );

    case "invalid_assignee":
      return createErrorState(
        result.message,
        {
          assignedTo: [
            result.message,
          ],
        },
      );

    case "validation":
      return createErrorState(
        result.message,
      );

    case "permission_denied":
      return createErrorState(
        result.message,
      );

    case "invalid_state":
      return createErrorState(
        result.message,
      );

    case "database_error":
    default:
      console.error(
        "Follow-up task database error:",
        {
          operation,
          result,
        },
      );

      return createErrorState(
        result.message,
      );
  }
}

function mapSiteVisitFailure(
  result: SiteVisitFailureResult,
  operation: SiteVisitOperation,
): OperationalActionState {
  switch (result.code) {
    case "conflict":
      return {
        status: "conflict",
        message: result.message,
        fieldErrors: {
          expectedUpdatedAt: [
            "The site visit changed after this form was opened.",
          ],
        },
      };

    case "not_found":
      return createErrorState(
        result.message,
        operation === "create"
          ? {
              leadId: [
                result.message,
              ],
            }
          : {
              siteVisitId: [
                result.message,
              ],
            },
      );

    case "invalid_assignee":
      return createErrorState(
        result.message,
        {
          assignedAgentId: [
            result.message,
          ],
          coordinatorId: [
            result.message,
          ],
        },
      );

    case "validation":
      return createErrorState(
        result.message,
      );

    case "permission_denied":
      return createErrorState(
        result.message,
      );

    case "invalid_state":
      return createErrorState(
        result.message,
      );

    case "database_error":
    default:
      console.error(
        "Site visit database error:",
        {
          operation,
          result,
        },
      );

      return createErrorState(
        result.message,
      );
  }
}

type SiteVisitOperation =
  | "create"
  | "assign"
  | "check_in"
  | "check_out"
  | "complete"
  | "cancel";

function revalidateLeadOperationalPaths(
  leadId: string,
): void {
  revalidatePath(
    "/dashboard",
  );

  revalidatePath(
    "/dashboard/leads",
  );

  revalidatePath(
    `/dashboard/leads/${leadId}`,
  );
}

export async function transitionLeadStatusAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .updateLeadStatus,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to change lead status.",
    );
  }

  const parsed =
    parseStatusTransitionForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  let transitionResult: {
    leadId: string;
    updatedAt: string;
  };

  try {
    transitionResult =
      await transitionLeadStatusRecord(
        organizationId,
        parsed.values,
      );
  } catch (error) {
    return mapTransitionError(
      error,
    );
  }

  revalidateLeadOperationalPaths(
    transitionResult.leadId,
  );

  redirect(
    `/dashboard/leads/${transitionResult.leadId}?statusUpdated=1`,
    RedirectType.replace,
  );
}

export async function manualAssignLeadAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseManualAssignmentForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const requiredPermissions: string[] = [
    LEAD_OPERATIONAL_PERMISSIONS
      .viewLeads,

    LEAD_OPERATIONAL_PERMISSIONS
      .manualAssign,
  ];

  if (
    parsed.values.overrideCapacity
  ) {
    requiredPermissions.push(
      LEAD_OPERATIONAL_PERMISSIONS
        .overrideAssignment,
    );
  }

  const { context } =
    await requirePermissionAccess({
      allOf:
        requiredPermissions,

      loginRedirectTo:
        `/login?next=/dashboard/leads/${parsed.values.leadId}`,

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to assign this lead.",
    );
  }

  const assignmentResult =
    await manuallyAssignLead({
      leadId:
        parsed.values.leadId,

      agentProfileId:
        parsed.values.agentProfileId,

      teamId:
        parsed.values.teamId,

      reason:
        parsed.values.reason,

      overrideCapacity:
        parsed.values.overrideCapacity,
    });

  if (!assignmentResult.ok) {
    return mapAssignmentFailure(
      assignmentResult,
    );
  }

  revalidateLeadOperationalPaths(
    parsed.values.leadId,
  );

  redirect(
    `/dashboard/leads/${parsed.values.leadId}?assignmentUpdated=1`,
    RedirectType.replace,
  );
}

export async function manualUnassignLeadAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseManualUnassignmentForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .unassign,
      ],

      loginRedirectTo:
        `/login?next=/dashboard/leads/${parsed.values.leadId}`,

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to remove this assignment.",
    );
  }

  const unassignmentResult =
    await manuallyUnassignLead({
      leadId:
        parsed.values.leadId,

      reason:
        parsed.values.reason,
    });

  if (!unassignmentResult.ok) {
    return mapAssignmentFailure(
      unassignmentResult,
    );
  }

  revalidateLeadOperationalPaths(
    parsed.values.leadId,
  );

  redirect(
    `/dashboard/leads/${parsed.values.leadId}?assignmentRemoved=1`,
    RedirectType.replace,
  );
}

export async function createFollowUpAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseCreateFollowUpForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .createFollowUp,
      ],

      loginRedirectTo:
        `/login?next=/dashboard/leads/${parsed.values.leadId}`,

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to create a follow-up.",
    );
  }

  const result =
    await createFollowUpTask(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapFollowUpFailure(
      result,
      "create",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?followUpCreated=1`,
    RedirectType.replace,
  );
}

export async function assignFollowUpAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseAssignFollowUpForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .assignFollowUp,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to assign a follow-up.",
    );
  }

  const result =
    await assignFollowUpTask(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapFollowUpFailure(
      result,
      "assign",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?followUpAssigned=1`,
    RedirectType.replace,
  );
}

export async function completeFollowUpAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseCompleteFollowUpForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .completeFollowUp,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to complete a follow-up.",
    );
  }

  const result =
    await completeFollowUpTask(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapFollowUpFailure(
      result,
      "complete",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?followUpCompleted=1`,
    RedirectType.replace,
  );
}

export async function createSiteVisitAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseCreateSiteVisitForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .createSiteVisit,
      ],

      loginRedirectTo:
        `/login?next=/dashboard/leads/${parsed.values.leadId}`,

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to create a site visit.",
    );
  }

  const result =
    await createSiteVisit(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapSiteVisitFailure(
      result,
      "create",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?siteVisitCreated=1`,
    RedirectType.replace,
  );
}

export async function assignSiteVisitAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseAssignSiteVisitForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .assignSiteVisit,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to assign a site visit.",
    );
  }

  const result =
    await assignSiteVisit(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapSiteVisitFailure(
      result,
      "assign",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?siteVisitAssigned=1`,
    RedirectType.replace,
  );
}

export async function checkInSiteVisitAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseCheckInSiteVisitForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .checkInSiteVisit,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to check in a site visit.",
    );
  }

  const result =
    await checkInSiteVisit(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapSiteVisitFailure(
      result,
      "check_in",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?siteVisitCheckedIn=1`,
    RedirectType.replace,
  );
}

export async function checkOutSiteVisitAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseCheckOutSiteVisitForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .checkInSiteVisit,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to check out a site visit.",
    );
  }

  const result =
    await checkOutSiteVisit(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapSiteVisitFailure(
      result,
      "check_out",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?siteVisitCheckedOut=1`,
    RedirectType.replace,
  );
}

export async function completeSiteVisitAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseCompleteSiteVisitForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .completeSiteVisit,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to complete a site visit.",
    );
  }

  const result =
    await completeSiteVisit(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapSiteVisitFailure(
      result,
      "complete",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?siteVisitCompleted=1`,
    RedirectType.replace,
  );
}

export async function cancelSiteVisitAction(
  previousState:
    OperationalActionState,

  formData: FormData,
): Promise<OperationalActionState> {
  void previousState;

  const parsed =
    parseCancelSiteVisitForm(
      formData,
    );

  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors:
        parsed.fieldErrors,
    };
  }

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewLeads,

        LEAD_OPERATIONAL_PERMISSIONS
          .cancelSiteVisit,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to cancel a site visit.",
    );
  }

  const result =
    await cancelSiteVisit(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapSiteVisitFailure(
      result,
      "cancel",
    );
  }

  revalidateLeadOperationalPaths(
    result.leadId,
  );

  redirect(
    `/dashboard/leads/${result.leadId}?siteVisitCancelled=1`,
    RedirectType.replace,
  );
}