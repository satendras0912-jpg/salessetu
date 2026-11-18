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
  createAdminClient,
} from "@/lib/supabase/admin";

import {
  cancelCommercialApproval,
  cancelDeal,
  changeDealStatus,
  createDealOSClient,
  createDeal,
  createDealOffer,
  decideCommercialApproval,
  linkDealBooking,
  markDealLost,
  markDealWon,
  putDealOnHold,
  requestCommercialApproval,
  normalizeDealCurrencyCode,
  normalizeDealTimestamp,
  normalizeDealExpectedUpdatedAt,
  updateDeal,
  updateDealOfferStatus,
} from "@/lib/dealos/deal-service";

import {
  DEALOS_PERMISSIONS,
} from "@/lib/dealos/deal-contract";

import {
  getCurrentDealOSAccessContext,
} from "@/lib/dealos/deal-access";

import {
  decideDealConversionRequest,
  requestDealConversion,
} from "@/lib/dealos/deal-conversion-service";

import type {
  DealOSActionState,
  DealOSFieldErrors,
} from "@/types/dealos-actions";

import type {
  ChangeDealStatusValues,
  CreateDealValues,
  DealOSServiceFailure,
  GenericDealStatusTarget,
  MarkDealLostValues,
  PutDealOnHoldValues,
  CancelDealValues,
  LinkDealBookingValues,
  MarkDealWonValues,
  CreateDealOfferValues,
  DealOfferParty,
  DealJsonObject,
  DealOfferStatus,
  UpdateDealOfferStatusValues,
  RequestCommercialApprovalValues,
  DecideCommercialApprovalValues,
  CancelCommercialApprovalValues,
  UpdateDealValues,
} from "@/types/dealos";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type CreateDealParseResult =
  | {
      success: true;
      values: CreateDealValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type UpdateDealParseResult =
  | {
      success: true;
      values: UpdateDealValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type MarkDealLostParseResult =
  | {
      success: true;
      values: MarkDealLostValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type PutDealOnHoldParseResult =
  | {
      success: true;
      values: PutDealOnHoldValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type CancelDealParseResult =
  | {
      success: true;
      values: CancelDealValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type LinkDealBookingParseResult =
  | {
      success: true;
      values: LinkDealBookingValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type MarkDealWonParseResult =
  | {
      success: true;
      values: MarkDealWonValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

type ConfirmBookingAndWinDealParseResult =
  | {
      success: true;
      values: {
        dealId: string;
        bookingId: string;
        expectedUpdatedAt: string;
        paymentReference: string;
        paymentAmount: number;
        paymentMode: string;
        documentStatus: "not_required" | "requested" | "under_review";
        documentName: string;
        confirmationReason: string;
        confirmationNotes: string;
      };
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

type CreateBookingPaymentScheduleParseResult =
  | {
      success: true;
      values: {
        dealId: string;
        bookingId: string;
        dueDate: string;
        amountDue: number;
        paymentType: string;
        notes: string;
      };
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

type RecordBookingSchedulePaymentParseResult =
  | {
      success: true;
      values: {
        dealId: string;
        bookingId: string;
        scheduleId: string;
        amount: number;
        paymentReference: string;
        paymentMode: string;
        paymentDate: string;
        notes: string;
      };
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

type DecideBookingPaymentReceiptParseResult =
  | {
      success: true;
      values: {
        submissionId: string;
        decision: "approved" | "rejected";
        reason: string;
        dealId: string;
      };
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type CreateDealOfferParseResult =
  | {
      success: true;
      values: CreateDealOfferValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type UpdateDealOfferStatusParseResult =
  | {
      success: true;
      values: UpdateDealOfferStatusValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type RequestCommercialApprovalParseResult =
  | {
      success: true;
      values: RequestCommercialApprovalValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type DecideCommercialApprovalParseResult =
  | {
      success: true;
      values: DecideCommercialApprovalValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type CancelCommercialApprovalParseResult =
  | {
      success: true;
      values: CancelCommercialApprovalValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

    type ChangeDealStatusParseResult =
  | {
      success: true;
      values: ChangeDealStatusValues;
    }
  | {
      success: false;
      message: string;
      fieldErrors: DealOSFieldErrors;
    };

const GENERIC_DEAL_STATUS_TARGETS:
  readonly GenericDealStatusTarget[] = [
    "open",
    "negotiation",
    "commercial_review",
    "approved",
    "booking_ready",
  ];

  function isGenericDealStatusTarget(
  value: string,
): value is GenericDealStatusTarget {
  return GENERIC_DEAL_STATUS_TARGETS.some(
    (status) =>
      status === value,
  );
}

function parseOptionalDealJsonObject(
  value: string,
):
  | {
      success: true;
      value:
        | DealJsonObject
        | undefined;
    }
  | {
      success: false;
    } {
  const normalizedValue =
    value.trim();

  if (!normalizedValue) {
    return {
      success: true,
      value: undefined,
    };
  }

  try {
    const parsedValue: unknown =
      JSON.parse(
        normalizedValue,
      );

    if (
      typeof parsedValue !==
        "object" ||
      parsedValue === null ||
      Array.isArray(
        parsedValue,
      )
    ) {
      return {
        success: false,
      };
    }

    return {
      success: true,
      value:
        parsedValue as DealJsonObject,
    };
  } catch {
    return {
      success: false,
    };
  }
}

function isDealOfferParty(
  value: string,
): value is DealOfferParty {
  return (
    value === "customer" ||
    value === "organization"
  );
}

const DEAL_OFFER_STATUS_ACTIONS:
  readonly DealOfferStatus[] = [
    "proposed",
    "countered",
    "accepted",
    "rejected",
    "withdrawn",
    "expired",
  ];

function isDealOfferStatusAction(
  value: string,
): value is DealOfferStatus {
  return DEAL_OFFER_STATUS_ACTIONS.some(
    (status) =>
      status === value,
  );
}

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
  errors: DealOSFieldErrors,
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
  errors: DealOSFieldErrors,
): boolean {
  return Object.values(errors).some(
    (messages) =>
      Array.isArray(messages) &&
      messages.length > 0,
  );
}

function parseCreateDealForm(
  formData: FormData,
): CreateDealParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const leadId =
    normalizeSingleLine(
      getFormString(
        formData,
        "leadId",
      ),
    );

  const siteVisitId =
    normalizeSingleLine(
      getFormString(
        formData,
        "siteVisitId",
      ),
    );

  const inventoryUnitId =
    normalizeSingleLine(
      getFormString(
        formData,
        "inventoryUnitId",
      ),
    );

  const assignedTo =
    normalizeSingleLine(
      getFormString(
        formData,
        "assignedTo",
      ),
    );

  const currencyCode =
    normalizeSingleLine(
      getFormString(
        formData,
        "currencyCode",
      ),
    );

  const bookingProbabilityRaw =
    normalizeSingleLine(
      getFormString(
        formData,
        "bookingProbability",
      ),
    );

  const nextActionAt =
    normalizeSingleLine(
      getFormString(
        formData,
        "nextActionAt",
      ),
    );

  const notes =
    normalizeMultiline(
      getFormString(
        formData,
        "notes",
      ),
    );

  if (
    !UUID_PATTERN.test(
      leadId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "leadId",
      "Select a valid lead.",
    );
  }

  if (
    siteVisitId &&
    !UUID_PATTERN.test(
      siteVisitId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "siteVisitId",
      "Select a valid site visit.",
    );
  }

  if (
    inventoryUnitId &&
    !UUID_PATTERN.test(
      inventoryUnitId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "inventoryUnitId",
      "Select a valid inventory unit.",
    );
  }

  if (
    assignedTo &&
    !UUID_PATTERN.test(
      assignedTo,
    )
  ) {
    addFieldError(
      fieldErrors,
      "assignedTo",
      "Select a valid deal assignee.",
    );
  }

  const cleanCurrencyCode =
    normalizeDealCurrencyCode(
      currencyCode || undefined,
    );

  if (!cleanCurrencyCode) {
    addFieldError(
      fieldErrors,
      "currencyCode",
      "Enter a valid three-letter currency code.",
    );
  }

  let bookingProbability:
    number | null = null;

  if (bookingProbabilityRaw) {
    const parsedProbability =
      Number(
        bookingProbabilityRaw,
      );

    if (
      !Number.isFinite(
        parsedProbability,
      ) ||
      parsedProbability < 0 ||
      parsedProbability > 100
    ) {
      addFieldError(
        fieldErrors,
        "bookingProbability",
        "Booking probability must be between 0 and 100.",
      );
    } else {
      bookingProbability =
        parsedProbability;
    }
  }

  const cleanNextActionAt =
    nextActionAt
      ? normalizeDealTimestamp(
          nextActionAt,
        )
      : null;

  if (
    nextActionAt &&
    !cleanNextActionAt
  ) {
    addFieldError(
      fieldErrors,
      "nextActionAt",
      "Enter a valid next-action date and time.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted deal fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      leadId,

      siteVisitId:
        siteVisitId || null,

      inventoryUnitId:
        inventoryUnitId || null,

      assignedTo:
        assignedTo || null,

      currencyCode:
        cleanCurrencyCode ??
        "INR",

      bookingProbability,

      nextActionAt:
        cleanNextActionAt,

      notes:
        notes || null,
    },
  };
}

function parseUpdateDealForm(
  formData: FormData,
): UpdateDealParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original deal update timestamp is invalid.",
    );
  }

  const hasAssignedTo =
    formData.has(
      "assignedTo",
    );

  const hasBookingProbability =
    formData.has(
      "bookingProbability",
    );

  const hasNextActionAt =
    formData.has(
      "nextActionAt",
    );

  const hasHoldReason =
    formData.has(
      "holdReason",
    );

  const hasNotes =
    formData.has(
      "notes",
    );

  if (
    !hasAssignedTo &&
    !hasBookingProbability &&
    !hasNextActionAt &&
    !hasHoldReason &&
    !hasNotes
  ) {
    return {
      success: false,
      message:
        "No deal changes were provided.",
      fieldErrors,
    };
  }

  const values:
    UpdateDealValues = {
      dealId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",
    };

  if (hasAssignedTo) {
    const assignedTo =
      normalizeSingleLine(
        getFormString(
          formData,
          "assignedTo",
        ),
      );

    if (
      assignedTo &&
      !UUID_PATTERN.test(
        assignedTo,
      )
    ) {
      addFieldError(
        fieldErrors,
        "assignedTo",
        "Select a valid deal assignee.",
      );
    }

    values.assignedTo =
      assignedTo || null;
  }

  if (hasBookingProbability) {
    const rawBookingProbability =
      normalizeSingleLine(
        getFormString(
          formData,
          "bookingProbability",
        ),
      );

    if (!rawBookingProbability) {
      values.bookingProbability =
        null;
    } else {
      const bookingProbability =
        Number(
          rawBookingProbability,
        );

      if (
        !Number.isFinite(
          bookingProbability,
        ) ||
        bookingProbability < 0 ||
        bookingProbability > 100
      ) {
        addFieldError(
          fieldErrors,
          "bookingProbability",
          "Booking probability must be between 0 and 100.",
        );
      } else {
        values.bookingProbability =
          bookingProbability;
      }
    }
  }

  if (hasNextActionAt) {
    const nextActionAt =
      normalizeSingleLine(
        getFormString(
          formData,
          "nextActionAt",
        ),
      );

    const cleanNextActionAt =
      nextActionAt
        ? normalizeDealTimestamp(
            nextActionAt,
          )
        : null;

    if (
      nextActionAt &&
      !cleanNextActionAt
    ) {
      addFieldError(
        fieldErrors,
        "nextActionAt",
        "Enter a valid next-action date and time.",
      );
    }

    values.nextActionAt =
      cleanNextActionAt;
  }

  if (hasHoldReason) {
    const holdReason =
      normalizeMultiline(
        getFormString(
          formData,
          "holdReason",
        ),
      );

    values.holdReason =
      holdReason || null;
  }

  if (hasNotes) {
    const notes =
      normalizeMultiline(
        getFormString(
          formData,
          "notes",
        ),
      );

    values.notes =
      notes || null;
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted deal fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values,
  };
}

function parseChangeDealStatusForm(
  formData: FormData,
): ChangeDealStatusParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const status =
    normalizeSingleLine(
      getFormString(
        formData,
        "status",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original deal update timestamp is invalid.",
    );
  }

  if (
    !isGenericDealStatusTarget(
      status,
    )
  ) {
    addFieldError(
      fieldErrors,
      "status",
      "Select a valid deal status.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted deal status fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",

      status:
        status as GenericDealStatusTarget,
    },
  };
}

function parseMarkDealLostForm(
  formData: FormData,
): MarkDealLostParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const lossReason =
    normalizeMultiline(
      getFormString(
        formData,
        "lossReason",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original deal update timestamp is invalid.",
    );
  }

  if (!lossReason) {
    addFieldError(
      fieldErrors,
      "lossReason",
      "Enter a reason for marking this deal lost.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted deal fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",

      lossReason,
    },
  };
}

function parsePutDealOnHoldForm(
  formData: FormData,
): PutDealOnHoldParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const holdReason =
    normalizeMultiline(
      getFormString(
        formData,
        "holdReason",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original deal update timestamp is invalid.",
    );
  }

  if (!holdReason) {
    addFieldError(
      fieldErrors,
      "holdReason",
      "Enter a reason for putting this deal on hold.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted deal fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",

      holdReason,
    },
  };
}

function parseCancelDealForm(
  formData: FormData,
): CancelDealParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const cancellationReason =
    normalizeMultiline(
      getFormString(
        formData,
        "cancellationReason",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original deal update timestamp is invalid.",
    );
  }

  if (!cancellationReason) {
    addFieldError(
      fieldErrors,
      "cancellationReason",
      "Enter a reason for cancelling this deal.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted deal fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",

      cancellationReason,
    },
  };
}

function parseLinkDealBookingForm(
  formData: FormData,
): LinkDealBookingParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const bookingId =
    normalizeSingleLine(
      getFormString(
        formData,
        "bookingId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (
    !UUID_PATTERN.test(
      bookingId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "bookingId",
      "Select a valid booking.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original deal update timestamp is invalid.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted booking handoff fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,
      bookingId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",
    },
  };
}

function parseMarkDealWonForm(
  formData: FormData,
): MarkDealWonParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original deal update timestamp is invalid.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted deal fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",
    },
  };
}

function parseConfirmBookingAndWinDealForm(
  formData: FormData,
): ConfirmBookingAndWinDealParseResult {
  const fieldErrors: DealOSFieldErrors = {};
  const dealId = normalizeSingleLine(getFormString(formData, "dealId"));
  const bookingId = normalizeSingleLine(getFormString(formData, "bookingId"));
  const expectedUpdatedAt = normalizeDealExpectedUpdatedAt(
    getFormString(formData, "expectedUpdatedAt"),
  );
  const paymentReference = normalizeSingleLine(
    getFormString(formData, "paymentReference"),
  );
  const paymentAmount = Number(getFormString(formData, "paymentAmount"));
  const paymentMode = normalizeSingleLine(getFormString(formData, "paymentMode"));
  const documentStatus = normalizeSingleLine(getFormString(formData, "documentStatus"));
  const documentName = normalizeSingleLine(getFormString(formData, "documentName"));
  const confirmationReason = normalizeMultiline(
    getFormString(formData, "confirmationReason"),
  );
  const confirmationNotes = normalizeMultiline(
    getFormString(formData, "confirmationNotes"),
  );

  if (!UUID_PATTERN.test(dealId)) addFieldError(fieldErrors, "dealId", "Select a valid deal.");
  if (!UUID_PATTERN.test(bookingId)) addFieldError(fieldErrors, "bookingId", "Select a valid booking.");
  if (!expectedUpdatedAt) addFieldError(fieldErrors, "expectedUpdatedAt", "The original deal update timestamp is invalid.");
  if (!paymentReference) addFieldError(fieldErrors, "paymentReference", "Enter the payment reference.");
  if (!Number.isFinite(paymentAmount) || paymentAmount <= 0) addFieldError(fieldErrors, "paymentAmount", "Enter a payment amount greater than zero.");
  if (!paymentMode) addFieldError(fieldErrors, "paymentMode", "Select the payment mode.");
  if (!["not_required", "requested", "under_review"].includes(documentStatus)) addFieldError(fieldErrors, "documentStatus", "Select a valid document status.");
  if (documentStatus !== "not_required" && !documentName) addFieldError(fieldErrors, "documentName", "Enter the document reference.");
  if (confirmationReason.length < 3) addFieldError(fieldErrors, "confirmationReason", "Enter a short confirmation reason.");
  if (confirmationReason.length > 1000) addFieldError(fieldErrors, "confirmationReason", "Reason cannot exceed 1000 characters.");
  if (confirmationNotes.length > 2000) addFieldError(fieldErrors, "confirmationNotes", "Notes cannot exceed 2000 characters.");

  if (hasFieldErrors(fieldErrors)) {
    return { success: false, message: "Please correct the highlighted confirmation fields.", fieldErrors };
  }

  return {
    success: true,
    values: {
      dealId, bookingId, expectedUpdatedAt: expectedUpdatedAt ?? "", paymentReference,
      paymentAmount, paymentMode,
      documentStatus: documentStatus as "not_required" | "requested" | "under_review",
      documentName, confirmationReason, confirmationNotes,
    },
  };
}

function parseCreateBookingPaymentScheduleForm(
  formData: FormData,
): CreateBookingPaymentScheduleParseResult {
  const fieldErrors: DealOSFieldErrors = {};
  const dealId = normalizeSingleLine(getFormString(formData, "dealId"));
  const bookingId = normalizeSingleLine(getFormString(formData, "bookingId"));
  const dueDate = normalizeSingleLine(getFormString(formData, "dueDate"));
  const amountDue = Number(getFormString(formData, "amountDue"));
  const paymentType = normalizeSingleLine(getFormString(formData, "paymentType"));
  const notes = normalizeMultiline(getFormString(formData, "notes"));

  if (!UUID_PATTERN.test(dealId)) addFieldError(fieldErrors, "dealId", "Select a valid deal.");
  if (!UUID_PATTERN.test(bookingId)) addFieldError(fieldErrors, "bookingId", "Select a valid booking.");
  const parsedDueDate = new Date(`${dueDate}T00:00:00Z`);
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(dueDate) ||
    Number.isNaN(parsedDueDate.getTime()) ||
    parsedDueDate.toISOString().slice(0, 10) !== dueDate
  ) {
    addFieldError(fieldErrors, "dueDate", "Choose a valid due date.");
  }
  if (!Number.isFinite(amountDue) || amountDue <= 0) addFieldError(fieldErrors, "amountDue", "Enter a scheduled amount greater than zero.");
  if (!paymentType) addFieldError(fieldErrors, "paymentType", "Choose an installment type.");
  if (notes.length > 1000) addFieldError(fieldErrors, "notes", "Notes cannot exceed 1000 characters.");

  if (hasFieldErrors(fieldErrors)) {
    return { success: false, message: "Please correct the highlighted payment schedule fields.", fieldErrors };
  }

  return { success: true, values: { dealId, bookingId, dueDate, amountDue, paymentType, notes } };
}

function parseRecordBookingSchedulePaymentForm(
  formData: FormData,
): RecordBookingSchedulePaymentParseResult {
  const fieldErrors: DealOSFieldErrors = {};
  const dealId = normalizeSingleLine(getFormString(formData, "dealId"));
  const bookingId = normalizeSingleLine(getFormString(formData, "bookingId"));
  const scheduleId = normalizeSingleLine(getFormString(formData, "scheduleId"));
  const amount = Number(getFormString(formData, "amount"));
  const paymentReference = normalizeSingleLine(getFormString(formData, "paymentReference"));
  const paymentMode = normalizeSingleLine(getFormString(formData, "paymentMode"));
  const paymentDate = normalizeDealTimestamp(getFormString(formData, "paymentDate"));
  const notes = normalizeMultiline(getFormString(formData, "notes"));

  if (!UUID_PATTERN.test(dealId)) addFieldError(fieldErrors, "dealId", "Select a valid deal.");
  if (!UUID_PATTERN.test(bookingId)) addFieldError(fieldErrors, "bookingId", "Select a valid booking.");
  if (!UUID_PATTERN.test(scheduleId)) addFieldError(fieldErrors, "scheduleId", "Select an open installment.");
  if (!Number.isFinite(amount) || amount <= 0) addFieldError(fieldErrors, "amount", "Enter an amount greater than zero.");
  if (!paymentReference) addFieldError(fieldErrors, "paymentReference", "Enter the payment reference.");
  if (!paymentMode) addFieldError(fieldErrors, "paymentMode", "Select the payment mode.");
  if (!paymentDate) addFieldError(fieldErrors, "paymentDate", "Choose a valid payment date and time.");
  if (notes.length > 1000) addFieldError(fieldErrors, "notes", "Notes cannot exceed 1000 characters.");

  if (hasFieldErrors(fieldErrors)) {
    return { success: false, message: "Please correct the highlighted payment fields.", fieldErrors };
  }

  return {
    success: true,
    values: { dealId, bookingId, scheduleId, amount, paymentReference, paymentMode, paymentDate: paymentDate ?? "", notes },
  };
}

function parseDecideBookingPaymentReceiptForm(
  formData: FormData,
): DecideBookingPaymentReceiptParseResult {
  const fieldErrors: DealOSFieldErrors = {};
  const submissionId = normalizeSingleLine(getFormString(formData, "submissionId"));
  const decision = normalizeSingleLine(getFormString(formData, "decision"));
  const reason = normalizeMultiline(getFormString(formData, "reason"));
  const dealId = normalizeSingleLine(getFormString(formData, "dealId"));

  if (!UUID_PATTERN.test(submissionId)) addFieldError(fieldErrors, "submissionId", "Select a valid receipt submission.");
  if (decision !== "approved" && decision !== "rejected") addFieldError(fieldErrors, "decision", "Choose approve or reject.");
  if (reason.length < 3 || reason.length > 1000) addFieldError(fieldErrors, "reason", "Enter a decision reason between 3 and 1000 characters.");
  if (!UUID_PATTERN.test(dealId)) addFieldError(fieldErrors, "dealId", "Select a valid deal.");

  if (hasFieldErrors(fieldErrors)) {
    return { success: false, message: "Please correct the receipt decision fields.", fieldErrors };
  }

  return { success: true, values: { submissionId, decision: decision as "approved" | "rejected", reason, dealId } };
}

function parseCreateDealOfferForm(
  formData: FormData,
): CreateDealOfferParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const offeredByParty =
    normalizeSingleLine(
      getFormString(
        formData,
        "offeredByParty",
      ),
    );

  const offerAmountRaw =
    normalizeSingleLine(
      getFormString(
        formData,
        "offerAmount",
      ),
    );

  const currencyCode =
    normalizeSingleLine(
      getFormString(
        formData,
        "currencyCode",
      ),
    );

  const offerTermsRaw =
    getFormString(
      formData,
      "offerTerms",
    );

  const notes =
    normalizeMultiline(
      getFormString(
        formData,
        "notes",
      ),
    );

  const validUntil =
    normalizeSingleLine(
      getFormString(
        formData,
        "validUntil",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (
    !isDealOfferParty(
      offeredByParty,
    )
  ) {
    addFieldError(
      fieldErrors,
      "offeredByParty",
      "Select a valid offer party.",
    );
  }

  const offerAmount =
    Number(
      offerAmountRaw,
    );

  if (
    !offerAmountRaw ||
    !Number.isFinite(
      offerAmount,
    ) ||
    offerAmount <= 0
  ) {
    addFieldError(
      fieldErrors,
      "offerAmount",
      "Enter a valid offer amount greater than zero.",
    );
  }

  const cleanCurrencyCode =
    normalizeDealCurrencyCode(
      currencyCode || undefined,
    );

  if (!cleanCurrencyCode) {
    addFieldError(
      fieldErrors,
      "currencyCode",
      "Enter a valid three-letter currency code.",
    );
  }

  const offerTermsResult =
    parseOptionalDealJsonObject(
      offerTermsRaw,
    );

  if (!offerTermsResult.success) {
    addFieldError(
      fieldErrors,
      "offerTerms",
      "Enter offer terms as a valid JSON object.",
    );
  }

  const cleanValidUntil =
    validUntil
      ? normalizeDealTimestamp(
          validUntil,
        )
      : null;

  if (
    validUntil &&
    !cleanValidUntil
  ) {
    addFieldError(
      fieldErrors,
      "validUntil",
      "Enter a valid offer expiry date and time.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted offer fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,

      offeredByParty:
        offeredByParty as DealOfferParty,

      offerAmount,

      currencyCode:
        cleanCurrencyCode ??
        "INR",

      offerTerms:
        offerTermsResult.success
          ? offerTermsResult.value
          : undefined,

      notes:
        notes || null,

      validUntil:
        cleanValidUntil,
    },
  };
}

function parseUpdateDealOfferStatusForm(
  formData: FormData,
): UpdateDealOfferStatusParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const offerId =
    normalizeSingleLine(
      getFormString(
        formData,
        "offerId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const status =
    normalizeSingleLine(
      getFormString(
        formData,
        "status",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (
    !UUID_PATTERN.test(
      offerId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "offerId",
      "Select a valid offer.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original offer update timestamp is invalid.",
    );
  }

  if (
    !isDealOfferStatusAction(
      status,
    )
  ) {
    addFieldError(
      fieldErrors,
      "status",
      "Select a valid offer status action.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted offer fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,
      offerId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",

      status:
        status as DealOfferStatus,
    },
  };
}

function parseRequestCommercialApprovalForm(
  formData: FormData,
): RequestCommercialApprovalParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const offerId =
    normalizeSingleLine(
      getFormString(
        formData,
        "offerId",
      ),
    );

  const requestedAmountRaw =
    normalizeSingleLine(
      getFormString(
        formData,
        "requestedAmount",
      ),
    );

  const requestReason =
    normalizeMultiline(
      getFormString(
        formData,
        "requestReason",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (
    offerId &&
    !UUID_PATTERN.test(
      offerId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "offerId",
      "Select a valid offer.",
    );
  }

  const requestedAmount =
    Number(
      requestedAmountRaw,
    );

  if (
    !requestedAmountRaw ||
    !Number.isFinite(
      requestedAmount,
    ) ||
    requestedAmount <= 0
  ) {
    addFieldError(
      fieldErrors,
      "requestedAmount",
      "Enter a valid requested amount greater than zero.",
    );
  }

  if (!requestReason) {
    addFieldError(
      fieldErrors,
      "requestReason",
      "Enter a reason for the commercial approval request.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted commercial approval fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,

      offerId:
        offerId || null,

      requestedAmount,

      requestReason,
    },
  };
}

function parseDecideCommercialApprovalForm(
  formData: FormData,
): DecideCommercialApprovalParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const approvalId =
    normalizeSingleLine(
      getFormString(
        formData,
        "approvalId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  const decision =
    normalizeSingleLine(
      getFormString(
        formData,
        "decision",
      ),
    );

  const decisionNotes =
    normalizeMultiline(
      getFormString(
        formData,
        "decisionNotes",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (
    !UUID_PATTERN.test(
      approvalId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "approvalId",
      "Select a valid commercial approval.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original commercial approval update timestamp is invalid.",
    );
  }

  if (
    decision !== "approved" &&
    decision !== "rejected"
  ) {
    addFieldError(
      fieldErrors,
      "decision",
      "Select a valid commercial approval decision.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted commercial approval fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,
      approvalId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",

      decision:
        decision as
          | "approved"
          | "rejected",

      decisionNotes:
        decisionNotes || null,
    },
  };
}

function parseCancelCommercialApprovalForm(
  formData: FormData,
): CancelCommercialApprovalParseResult {
  const fieldErrors:
    DealOSFieldErrors = {};

  const dealId =
    normalizeSingleLine(
      getFormString(
        formData,
        "dealId",
      ),
    );

  const approvalId =
    normalizeSingleLine(
      getFormString(
        formData,
        "approvalId",
      ),
    );

  const expectedUpdatedAt =
    normalizeDealExpectedUpdatedAt(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    );

  if (
    !UUID_PATTERN.test(
      dealId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "dealId",
      "Select a valid deal.",
    );
  }

  if (
    !UUID_PATTERN.test(
      approvalId,
    )
  ) {
    addFieldError(
      fieldErrors,
      "approvalId",
      "Select a valid commercial approval.",
    );
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original commercial approval update timestamp is invalid.",
    );
  }

  if (
    hasFieldErrors(
      fieldErrors,
    )
  ) {
    return {
      success: false,
      message:
        "Please correct the highlighted commercial approval fields.",
      fieldErrors,
    };
  }

  return {
    success: true,
    values: {
      dealId,
      approvalId,

      expectedUpdatedAt:
        expectedUpdatedAt ?? "",
    },
  };
}

  function createErrorState(
  message: string,
  fieldErrors: DealOSFieldErrors = {},
): DealOSActionState {
  return {
    status: "error",
    message,
    fieldErrors,
  };
}

function mapDealOSActionFailure(
  result: DealOSServiceFailure,
  conflictMessage:
    string | null = null,
): DealOSActionState {
  if (result.code === "conflict") {
    return {
      status: "conflict",
      message: result.message,
      fieldErrors:
        conflictMessage
          ? {
              expectedUpdatedAt: [
                conflictMessage,
              ],
            }
          : {},
    };
  }

  return createErrorState(
    result.message,
  );
}

function revalidateDealOSPaths(
  dealId?: string,
): void {
  revalidatePath(
    "/dashboard",
  );

  revalidatePath(
    "/dashboard/deals",
  );

  if (dealId) {
    revalidatePath(
      `/dashboard/deals/${dealId}`,
    );
  }
}

export async function createDealAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const dealAccessContext =
    await getCurrentDealOSAccessContext();

  if (
    !dealAccessContext ||
    dealAccessContext.organizationId !==
      context.organization?.id ||
    !dealAccessContext.access.canViewDeals ||
    !dealAccessContext.access.canCreateDeal
  ) {
    return createErrorState(
      "You do not have permission to perform this DealOS action.",
    );
  }

  const organizationId =
    dealAccessContext.organizationId.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to create a deal.",
    );
  }

  const parsed =
    parseCreateDealForm(
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

  const result =
    await createDeal(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
    );
  }

  if (!result.dealId) {
    return createErrorState(
      "The deal was created, but its identifier could not be verified. Reload the deals page before trying again.",
    );
  }

  revalidateDealOSPaths(
    result.dealId,
  );

  redirect(
    `/dashboard/deals/${result.dealId}?dealCreated=1`,
    RedirectType.replace,
  );
}

export async function requestDealConversionAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    loginRedirectTo: "/login?next=/dashboard/leads",
    unauthorizedRedirectTo: "/unauthorized",
  });
  const dealAccessContext = await getCurrentDealOSAccessContext();

  if (
    !dealAccessContext ||
    dealAccessContext.organizationId !== context.organization?.id ||
    !dealAccessContext.access.canCreateDeal
  ) {
    return createErrorState(
      "You do not have permission to request a deal conversion.",
    );
  }

  const leadId = normalizeSingleLine(getFormString(formData, "leadId"));
  const siteVisitId = normalizeSingleLine(getFormString(formData, "siteVisitId"));
  const rawNotes = normalizeMultiline(getFormString(formData, "notes"));
  const notes = rawNotes || null;

  if (!UUID_PATTERN.test(leadId) || !UUID_PATTERN.test(siteVisitId)) {
    return createErrorState("Select a valid lead and completed site visit.");
  }

  if (notes && notes.length > 2_000) {
    return createErrorState("Request notes cannot exceed 2,000 characters.");
  }

  const result = await requestDealConversion(leadId, siteVisitId, notes);

  if (!result.ok) {
    return createErrorState(result.message);
  }

  revalidatePath(`/dashboard/leads/${leadId}`);
  revalidatePath("/dashboard/deals");

  return {
    status: "success",
    message: "Deal conversion request sent for owner approval. No deal, reservation, routing or customer notification was created.",
    fieldErrors: {},
  };
}

export async function decideDealConversionRequestAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;
  const { context } = await requirePermissionAccess({
    loginRedirectTo: "/login?next=/dashboard/deals/conversions",
    unauthorizedRedirectTo: "/unauthorized",
  });
  const permissionContext = await getCurrentDealOSAccessContext();
  const requestId = normalizeSingleLine(getFormString(formData, "requestId"));
  const decision = normalizeSingleLine(getFormString(formData, "decision"));
  const reason = normalizeMultiline(getFormString(formData, "reason"));

  if (!context.organization?.id || !permissionContext || !UUID_PATTERN.test(requestId)) {
    return createErrorState("Select a valid deal conversion request.");
  }

  // Database RPC repeats the owner check. This application guard only avoids a
  // misleading submit attempt for users without DealOS access.
  if (!permissionContext.access.canCreateDeal) {
    return createErrorState("You do not have permission to decide deal conversions.");
  }

  if ((decision !== "approved" && decision !== "rejected") || reason.length < 3 || reason.length > 500) {
    return createErrorState("Choose approve or reject and provide a reason between 3 and 500 characters.");
  }

  const result = await decideDealConversionRequest(
    requestId,
    decision,
    reason,
  );

  if (!result.ok) return createErrorState(result.message);

  revalidatePath("/dashboard/deals");
  revalidatePath("/dashboard/deals/conversions");

  return {
    status: "success",
    message: result.dealId
      ? "Owner approval recorded and DealOS deal created. No reservation, routing or customer notification was triggered."
      : "Owner rejection recorded. No deal was created.",
    fieldErrors: {},
    dealId: result.dealId ?? undefined,
  };
}

export async function updateDealAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const requiredPermissions: string[] = [
    DEALOS_PERMISSIONS.viewDeals,
    DEALOS_PERMISSIONS.updateDeal,
  ];

  if (
    formData.has(
      "assignedTo",
    )
  ) {
    requiredPermissions.push(
      DEALOS_PERMISSIONS.assignDeal,
    );
  }

  const { context } =
    await requirePermissionAccess({
      allOf:
        requiredPermissions,

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to update a deal.",
    );
  }

  const parsed =
    parseUpdateDealForm(
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

  const result =
    await updateDeal(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The deal changed after this form was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?dealUpdated=1`,
    RedirectType.replace,
  );
}

export async function changeDealStatusAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.updateDeal,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to change deal status.",
    );
  }

  const parsed =
    parseChangeDealStatusForm(
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

  const result =
    await changeDealStatus(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The deal changed after this status action was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?dealStatusUpdated=1`,
    RedirectType.replace,
  );
}

export async function markDealLostAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.markLost,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to mark a deal lost.",
    );
  }

  const parsed =
    parseMarkDealLostForm(
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

  const result =
    await markDealLost(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The deal changed after this action was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?dealLost=1`,
    RedirectType.replace,
  );
}

export async function putDealOnHoldAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.updateDeal,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to put a deal on hold.",
    );
  }

  const parsed =
    parsePutDealOnHoldForm(
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

  const result =
    await putDealOnHold(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The deal changed after this action was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?dealOnHold=1`,
    RedirectType.replace,
  );
}

export async function cancelDealAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.updateDeal,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to cancel a deal.",
    );
  }

  const parsed =
    parseCancelDealForm(
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

  const result =
    await cancelDeal(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The deal changed after this action was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?dealCancelled=1`,
    RedirectType.replace,
  );
}

export async function linkDealBookingAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.handoffBooking,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to link a booking.",
    );
  }

  const parsed =
    parseLinkDealBookingForm(
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

  const result =
    await linkDealBooking(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The deal changed after this booking handoff was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?bookingLinked=1`,
    RedirectType.replace,
  );
}

export async function createDealBookingHoldAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [
      DEALOS_PERMISSIONS.viewDeals,
      DEALOS_PERMISSIONS.handoffBooking,
    ],
    loginRedirectTo: "/login?next=/dashboard/deals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    return createErrorState(
      "Only the workspace owner can create a booking hold.",
    );
  }

  const dealId = normalizeSingleLine(getFormString(formData, "dealId"));
  const expectedUpdatedAt = normalizeDealExpectedUpdatedAt(
    getFormString(formData, "expectedUpdatedAt"),
  );
  const expiryInput = normalizeSingleLine(
    getFormString(formData, "expiresAtUtc"),
  );
  const notes = normalizeMultiline(getFormString(formData, "reservationNotes"));
  const fieldErrors: DealOSFieldErrors = {};

  if (!UUID_PATTERN.test(dealId)) {
    addFieldError(fieldErrors, "dealId", "A valid deal is required.");
  }

  if (!expectedUpdatedAt) {
    addFieldError(
      fieldErrors,
      "expectedUpdatedAt",
      "The original deal update timestamp is invalid.",
    );
  }

  const expiresAt = new Date(expiryInput);
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(expiryInput) ||
    Number.isNaN(expiresAt.getTime())
  ) {
    addFieldError(
      fieldErrors,
      "expiresAt",
      "Choose a valid booking-hold expiry in your local time.",
    );
  } else if (expiresAt.getTime() <= Date.now()) {
    addFieldError(
      fieldErrors,
      "expiresAt",
      "Booking-hold expiry must be in the future.",
    );
  }

  if (notes.length < 3 || notes.length > 500) {
    addFieldError(
      fieldErrors,
      "reservationNotes",
      "Hold reason must contain between 3 and 500 characters.",
    );
  }

  if (hasFieldErrors(fieldErrors)) {
    return createErrorState(
      "Please correct the highlighted booking-hold fields.",
      fieldErrors,
    );
  }

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc(
    "create_deal_booking_hold",
    {
      requested_deal_id: dealId,
      requested_expected_updated_at: expectedUpdatedAt,
      requested_expires_at: expiresAt.toISOString(),
      requested_notes: notes,
    },
  );

  if (error) {
    return createErrorState(
      error.message || "The booking hold could not be created.",
    );
  }

  revalidateDealOSPaths(dealId);
  redirect(
    `/dashboard/deals/${dealId}?bookingReservation=1`,
    RedirectType.replace,
  );
}

export async function reserveBookingInventoryAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
      ],
      loginRedirectTo: "/login?next=/dashboard/deals",
      unauthorizedRedirectTo: "/unauthorized",
    });

  if (!context.membership?.isOwner) {
    return createErrorState(
      "Only the workspace owner can reserve inventory for a booking.",
    );
  }

  const bookingId = normalizeSingleLine(
    getFormString(formData, "bookingId"),
  );
  const dealId = normalizeSingleLine(
    getFormString(formData, "dealId"),
  );
  const expiryInput = normalizeSingleLine(
    getFormString(formData, "expiresAtUtc"),
  );
  const notes = normalizeMultiline(
    getFormString(formData, "reservationNotes"),
  );
  const fieldErrors: DealOSFieldErrors = {};

  if (!UUID_PATTERN.test(bookingId)) {
    addFieldError(fieldErrors, "bookingId", "A valid booking is required.");
  }

  const expiresAt = new Date(expiryInput);
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(expiryInput) ||
    Number.isNaN(expiresAt.getTime())
  ) {
    addFieldError(
      fieldErrors,
      "expiresAt",
      "Choose a valid reservation expiry in your local time.",
    );
  } else if (expiresAt.getTime() <= Date.now()) {
    addFieldError(fieldErrors, "expiresAt", "Reservation expiry must be in the future.");
  }

  if (notes.length > 1000) {
    addFieldError(fieldErrors, "reservationNotes", "Notes cannot exceed 1000 characters.");
  }

  if (hasFieldErrors(fieldErrors)) {
    return createErrorState(
      "Please correct the highlighted reservation fields.",
      fieldErrors,
    );
  }

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc(
    "reserve_booking_inventory",
    {
      requested_booking_id: bookingId,
      requested_expires_at: expiresAt.toISOString(),
      requested_notes: notes || null,
    },
  );

  if (error) {
    return createErrorState(
      error.message || "The inventory reservation could not be created.",
    );
  }

  revalidateDealOSPaths(dealId);
  redirect(
    `/dashboard/deals/${dealId}?bookingReservation=1`,
    RedirectType.replace,
  );
}

export async function releaseBookingInventoryReservationAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
      ],
      loginRedirectTo: "/login?next=/dashboard/deals",
      unauthorizedRedirectTo: "/unauthorized",
    });

  if (!context.membership?.isOwner) {
    return createErrorState(
      "Only the workspace owner can release a booking inventory reservation.",
    );
  }

  const bookingId = normalizeSingleLine(
    getFormString(formData, "bookingId"),
  );
  const dealId = normalizeSingleLine(
    getFormString(formData, "dealId"),
  );
  const reason = normalizeMultiline(
    getFormString(formData, "releaseReason"),
  );
  const fieldErrors: DealOSFieldErrors = {};

  if (!UUID_PATTERN.test(bookingId)) {
    addFieldError(fieldErrors, "bookingId", "A valid booking is required.");
  }

  if (reason.length < 3) {
    addFieldError(fieldErrors, "releaseReason", "Enter a short release reason.");
  }

  if (reason.length > 1000) {
    addFieldError(fieldErrors, "releaseReason", "Reason cannot exceed 1000 characters.");
  }

  if (hasFieldErrors(fieldErrors)) {
    return createErrorState(
      "Please correct the highlighted release fields.",
      fieldErrors,
    );
  }

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc(
    "release_booking_inventory_reservation",
    {
      requested_booking_id: bookingId,
      requested_reason: reason,
    },
  );

  if (error) {
    return createErrorState(
      error.message || "The inventory reservation could not be released.",
    );
  }

  revalidateDealOSPaths(dealId);
  redirect(
    `/dashboard/deals/${dealId}?bookingReservationReleased=1`,
    RedirectType.replace,
  );
}

export async function markDealWonAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.markWon,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!context.membership?.isOwner) {
    return createErrorState(
      "Only the workspace owner can mark a booking-backed deal won.",
    );
  }

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to mark a deal won.",
    );
  }

  const parsed =
    parseMarkDealWonForm(
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

  const result =
    await markDealWon(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The deal changed after this action was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?dealWon=1`,
    RedirectType.replace,
  );
}

export async function confirmBookingAndWinDealAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [DEALOS_PERMISSIONS.viewDeals, DEALOS_PERMISSIONS.handoffBooking],
    loginRedirectTo: "/login?next=/dashboard/deals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    return createErrorState(
      "Only the workspace owner can confirm a booking and mark a deal won.",
    );
  }

  const parsed = parseConfirmBookingAndWinDealForm(formData);
  if (!parsed.success) {
    return {
      status: "error",
      message: parsed.message,
      fieldErrors: parsed.fieldErrors,
    };
  }

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc("confirm_booking_and_win_deal", {
    requested_deal_id: parsed.values.dealId,
    requested_booking_id: parsed.values.bookingId,
    requested_expected_updated_at: parsed.values.expectedUpdatedAt,
    requested_payment_reference: parsed.values.paymentReference,
    requested_payment_amount: parsed.values.paymentAmount,
    requested_payment_mode: parsed.values.paymentMode,
    requested_document_status: parsed.values.documentStatus,
    requested_document_name: parsed.values.documentName || null,
    requested_confirmation_reason: parsed.values.confirmationReason,
    requested_confirmation_notes: parsed.values.confirmationNotes || null,
  });

  if (error) {
    return createErrorState(
      error.message || "The booking could not be confirmed.",
    );
  }

  revalidateDealOSPaths(parsed.values.dealId);
  redirect(
    `/dashboard/deals/${parsed.values.dealId}?bookingConfirmedAndWon=1`,
    RedirectType.replace,
  );
}

export async function createBookingPaymentScheduleAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [DEALOS_PERMISSIONS.viewDeals, DEALOS_PERMISSIONS.handoffBooking],
    loginRedirectTo: "/login?next=/dashboard/deals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    return createErrorState("Only the workspace owner can manage payment schedules.");
  }

  const parsed = parseCreateBookingPaymentScheduleForm(formData);
  if (!parsed.success) {
    return { status: "error", message: parsed.message, fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc("create_booking_payment_schedule", {
    requested_deal_id: parsed.values.dealId,
    requested_booking_id: parsed.values.bookingId,
    requested_due_date: parsed.values.dueDate,
    requested_amount_due: parsed.values.amountDue,
    requested_payment_type: parsed.values.paymentType,
    requested_notes: parsed.values.notes || null,
  });

  if (error) {
    return createErrorState(error.message || "The payment installment could not be created.");
  }

  revalidateDealOSPaths(parsed.values.dealId);
  redirect(
    `/dashboard/deals/${parsed.values.dealId}?paymentScheduleCreated=1`,
    RedirectType.replace,
  );
}

export async function recordBookingSchedulePaymentAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [DEALOS_PERMISSIONS.viewDeals, DEALOS_PERMISSIONS.handoffBooking],
    loginRedirectTo: "/login?next=/dashboard/deals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    return createErrorState("Only the workspace owner can record scheduled payments.");
  }

  const parsed = parseRecordBookingSchedulePaymentForm(formData);
  if (!parsed.success) {
    return { status: "error", message: parsed.message, fieldErrors: parsed.fieldErrors };
  }

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc("record_booking_schedule_payment", {
    requested_deal_id: parsed.values.dealId,
    requested_booking_id: parsed.values.bookingId,
    requested_schedule_id: parsed.values.scheduleId,
    requested_amount: parsed.values.amount,
    requested_payment_reference: parsed.values.paymentReference,
    requested_payment_mode: parsed.values.paymentMode,
    requested_payment_date: parsed.values.paymentDate,
    requested_notes: parsed.values.notes || null,
  });

  if (error) {
    return createErrorState(error.message || "The scheduled payment could not be recorded.");
  }

  revalidateDealOSPaths(parsed.values.dealId);
  redirect(
    `/dashboard/deals/${parsed.values.dealId}?scheduledPaymentRecorded=1`,
    RedirectType.replace,
  );
}

export async function submitBookingPaymentReceiptAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  await requirePermissionAccess({
    allOf: [DEALOS_PERMISSIONS.viewDeals],
    loginRedirectTo: "/login?next=/dashboard/deals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const parsed = parseRecordBookingSchedulePaymentForm(formData);
  if (!parsed.success) return { status: "error", message: parsed.message, fieldErrors: parsed.fieldErrors };

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc("submit_booking_payment_receipt", {
    requested_deal_id: parsed.values.dealId,
    requested_booking_id: parsed.values.bookingId,
    requested_schedule_id: parsed.values.scheduleId,
    requested_amount: parsed.values.amount,
    requested_payment_reference: parsed.values.paymentReference,
    requested_payment_mode: parsed.values.paymentMode,
    requested_payment_date: parsed.values.paymentDate,
    requested_notes: parsed.values.notes || null,
  });

  if (error) return createErrorState(error.message || "The receipt could not be submitted for approval.");

  revalidateDealOSPaths(parsed.values.dealId);
  revalidatePath("/dashboard/deals/receipt-approvals");
  redirect(`/dashboard/deals/${parsed.values.dealId}?receiptSubmitted=1`, RedirectType.replace);
}

export async function decideBookingPaymentReceiptAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [DEALOS_PERMISSIONS.viewDeals],
    loginRedirectTo: "/login?next=/dashboard/deals/receipt-approvals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) return createErrorState("Only the workspace owner can approve or reject a receipt.");

  const parsed = parseDecideBookingPaymentReceiptForm(formData);
  if (!parsed.success) return { status: "error", message: parsed.message, fieldErrors: parsed.fieldErrors };

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc("decide_booking_payment_receipt", {
    requested_submission_id: parsed.values.submissionId,
    requested_decision: parsed.values.decision,
    requested_reason: parsed.values.reason,
  });

  if (error) return createErrorState(error.message || "The receipt decision could not be recorded.");

  revalidateDealOSPaths(parsed.values.dealId);
  revalidatePath("/dashboard/deals/receipt-approvals");
  redirect(`/dashboard/deals/${parsed.values.dealId}?receiptDecision=${parsed.values.decision}`, RedirectType.replace);
}

export async function updateBookingAgreementChecklistAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [DEALOS_PERMISSIONS.viewDeals],
    loginRedirectTo: "/login?next=/dashboard/deals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const dealId = normalizeSingleLine(getFormString(formData, "dealId"));
  const bookingId = normalizeSingleLine(getFormString(formData, "bookingId"));
  const itemId = normalizeSingleLine(getFormString(formData, "itemId"));
  const status = normalizeSingleLine(getFormString(formData, "status"));
  const dueDate = normalizeSingleLine(getFormString(formData, "dueDate"));
  const notes = normalizeMultiline(getFormString(formData, "notes"));
  const fieldErrors: DealOSFieldErrors = {};

  if (!UUID_PATTERN.test(dealId)) addFieldError(fieldErrors, "dealId", "A valid deal is required.");
  if (!UUID_PATTERN.test(bookingId)) addFieldError(fieldErrors, "bookingId", "A valid booking is required.");
  if (!UUID_PATTERN.test(itemId)) addFieldError(fieldErrors, "itemId", "A valid checklist item is required.");
  if (![
    "not_started", "requested", "submitted", "under_review", "approved", "rejected", "not_required",
  ].includes(status)) addFieldError(fieldErrors, "status", "Choose a valid document status.");
  if (notes.length > 2000) addFieldError(fieldErrors, "notes", "Notes cannot exceed 2000 characters.");
  if (dueDate && !/^\d{4}-\d{2}-\d{2}$/.test(dueDate)) addFieldError(fieldErrors, "dueDate", "Choose a valid due date.");

  if (hasFieldErrors(fieldErrors)) {
    return createErrorState("Please correct the document checklist fields.", fieldErrors);
  }

  if (["approved", "rejected"].includes(status) && !context.membership?.isOwner) {
    return createErrorState("Only the workspace owner can approve or reject a checklist document.");
  }

  const supabase = await createDealOSClient();
  const { error } = await supabase.rpc("update_booking_document_checklist_item", {
    requested_deal_id: dealId,
    requested_booking_id: bookingId,
    requested_item_id: itemId,
    requested_status: status,
    requested_due_date: dueDate || null,
    requested_notes: notes || null,
  });

  if (error) {
    return createErrorState(error.message || "The document checklist could not be updated.");
  }

  revalidateDealOSPaths(dealId);
  redirect(`/dashboard/deals/${dealId}?agreementChecklistUpdated=1`, RedirectType.replace);
}

const BOOKING_DOCUMENT_MIME_TYPES = new Set([
  "application/pdf",
  "image/jpeg",
  "image/png",
]);

function bookingDocumentExtension(mimeType: string): string {
  if (mimeType === "application/pdf") return "pdf";
  if (mimeType === "image/jpeg") return "jpg";
  return "png";
}

export async function uploadBookingDocumentAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [DEALOS_PERMISSIONS.viewDeals],
    loginRedirectTo: "/login?next=/dashboard/deals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const dealId = normalizeSingleLine(getFormString(formData, "dealId"));
  const bookingId = normalizeSingleLine(getFormString(formData, "bookingId"));
  const itemId = normalizeSingleLine(getFormString(formData, "itemId"));
  const selectedFile = formData.get("documentFile");
  const fieldErrors: DealOSFieldErrors = {};

  if (!UUID_PATTERN.test(dealId)) addFieldError(fieldErrors, "dealId", "A valid deal is required.");
  if (!UUID_PATTERN.test(bookingId)) addFieldError(fieldErrors, "bookingId", "A valid booking is required.");
  if (!UUID_PATTERN.test(itemId)) addFieldError(fieldErrors, "itemId", "A valid checklist item is required.");
  if (!(selectedFile instanceof File) || selectedFile.size === 0) {
    addFieldError(fieldErrors, "documentFile", "Choose a document to upload.");
  }

  if (hasFieldErrors(fieldErrors)) {
    return createErrorState("Please correct the document upload fields.", fieldErrors);
  }

  const file = selectedFile as File;
  const originalFilename = normalizeSingleLine(file.name);
  if (!BOOKING_DOCUMENT_MIME_TYPES.has(file.type)) {
    return createErrorState("Only PDF, JPG and PNG files are allowed.");
  }
  if (file.size > 10 * 1024 * 1024) {
    return createErrorState("Documents must be 10 MB or smaller.");
  }
  if (!originalFilename || originalFilename.length > 180) {
    return createErrorState("The document filename must be between 1 and 180 characters.");
  }

  const organizationId = context.organization?.id;
  if (!organizationId) {
    return createErrorState("An active organization is required to upload booking documents.");
  }

  const storagePath = [
    organizationId,
    bookingId,
    itemId,
    `${crypto.randomUUID()}.${bookingDocumentExtension(file.type)}`,
  ].join("/");

  const admin = createAdminClient();
  const { error: uploadError } = await admin.storage
    .from("booking-documents")
    .upload(storagePath, file, {
      contentType: file.type,
      upsert: false,
    });

  if (uploadError) {
    return createErrorState(uploadError.message || "The document could not be uploaded.");
  }

  const supabase = await createDealOSClient();
  const { error: registerError } = await supabase.rpc(
    "register_booking_document_upload",
    {
      requested_deal_id: dealId,
      requested_booking_id: bookingId,
      requested_item_id: itemId,
      requested_storage_path: storagePath,
      requested_original_filename: originalFilename,
      requested_mime_type: file.type,
      requested_byte_size: file.size,
    },
  );

  if (registerError) {
    await admin.storage.from("booking-documents").remove([storagePath]);
    return createErrorState(registerError.message || "The uploaded document could not be registered.");
  }

  revalidateDealOSPaths(dealId);
  redirect(`/dashboard/deals/${dealId}?agreementDocumentUploaded=1`, RedirectType.replace);
}

export async function createDealOfferAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.manageOffers,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to create an offer.",
    );
  }

  const parsed =
    parseCreateDealOfferForm(
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

  const result =
    await createDealOffer(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?offerCreated=1`,
    RedirectType.replace,
  );
}

export async function updateDealOfferStatusAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.manageOffers,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to update an offer.",
    );
  }

  const parsed =
    parseUpdateDealOfferStatusForm(
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

  const result =
    await updateDealOfferStatus(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The offer changed after this action was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?offerUpdated=1`,
    RedirectType.replace,
  );
}

export async function requestCommercialApprovalAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
      ],

      anyOf: [
        DEALOS_PERMISSIONS.manageOffers,
        DEALOS_PERMISSIONS.approveCommercials,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to request commercial approval.",
    );
  }

  const parsed =
    parseRequestCommercialApprovalForm(
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

  const result =
    await requestCommercialApproval(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?commercialApprovalRequested=1`,
    RedirectType.replace,
  );
}

export async function decideCommercialApprovalAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.approveCommercials,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to decide commercial approval.",
    );
  }

  const parsed =
    parseDecideCommercialApprovalForm(
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

  const result =
    await decideCommercialApproval(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The commercial approval changed after this action was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?commercialApprovalDecided=1`,
    RedirectType.replace,
  );
}

export async function cancelCommercialApprovalAction(
  previousState: DealOSActionState,
  formData: FormData,
): Promise<DealOSActionState> {
  void previousState;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/deals",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id?.trim();

  if (!organizationId) {
    return createErrorState(
      "An active organization context is required to cancel commercial approval.",
    );
  }

  const parsed =
    parseCancelCommercialApprovalForm(
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

  const result =
    await cancelCommercialApproval(
      organizationId,
      parsed.values,
    );

  if (!result.ok) {
    return mapDealOSActionFailure(
      result,
      "The commercial approval changed after this action was opened.",
    );
  }

  const dealId =
    result.dealId ??
    parsed.values.dealId;

  revalidateDealOSPaths(
    dealId,
  );

  redirect(
    `/dashboard/deals/${dealId}?commercialApprovalCancelled=1`,
    RedirectType.replace,
  );
}
