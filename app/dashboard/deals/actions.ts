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
  cancelCommercialApproval,
  cancelDeal,
  changeDealStatus,
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
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
        DEALOS_PERMISSIONS.createDeal,
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