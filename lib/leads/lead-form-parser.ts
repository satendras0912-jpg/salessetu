import {
  LEAD_CONSENT_STATUSES,
  LEAD_CONTACT_CHANNELS,
  LEAD_FORM_LIMITS,
  LEAD_LIFECYCLE_STAGES,
  LEAD_PRIORITIES,
  LEAD_PURPOSES,
  LEAD_STATUSES,
  LEAD_TEMPERATURES,
  LEAD_TRANSACTION_TYPES,
  isAllowedValue,
} from "@/lib/leads/lead-form-contract";

import type {
  LeadFieldErrors,
  LeadFormField,
  LeadFormMode,
  LeadFormValues,
  LeadMutationPayload,
} from "@/types/lead-actions";

export type LeadFormParseSuccess = {
  success: true;
  values: LeadFormValues;
  payload: LeadMutationPayload;
};

export type LeadFormParseFailure = {
  success: false;
  values: LeadFormValues;
  fieldErrors: LeadFieldErrors;
  message: string;
};

export type LeadFormParseResult =
  | LeadFormParseSuccess
  | LeadFormParseFailure;

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const EMAIL_PATTERN =
  /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const COUNTRY_CODE_PATTERN =
  /^\+[1-9]\d{0,3}$/;

function getFormString(
  formData: FormData,
  field: LeadFormField,
): string {
  const value = formData.get(field);

  return typeof value === "string" ? value : "";
}

function normalizeSingleLine(value: string): string {
  return value
    .replace(/\s+/g, " ")
    .trim();
}

function normalizeMultiline(value: string): string {
  return value
    .replace(/\r\n/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .trim();
}

function normalizeEmail(value: string): string {
  return normalizeSingleLine(value).toLowerCase();
}

function normalizeCountryCode(value: string): string {
  const cleanValue = normalizeSingleLine(value);

  if (!cleanValue) {
    return "+91";
  }

  return cleanValue.startsWith("+")
    ? cleanValue
    : `+${cleanValue}`;
}

function normalizePhoneInput(value: string): string {
  return normalizeSingleLine(value);
}

function getPhoneDigitCount(value: string): number {
  return value.replace(/\D/g, "").length;
}

function emptyToNull(value: string): string | null {
  return value.length > 0 ? value : null;
}

function addFieldError(
  errors: LeadFieldErrors,
  field: LeadFormField,
  message: string,
): void {
  const existingErrors = errors[field] ?? [];

  errors[field] = [...existingErrors, message];
}

function validateMaximumLength(
  errors: LeadFieldErrors,
  field: LeadFormField,
  value: string,
  maximumLength: number,
  label: string,
): void {
  if (value.length > maximumLength) {
    addFieldError(
      errors,
      field,
      `${label} must not exceed ${maximumLength} characters.`,
    );
  }
}

function validatePhone(
  errors: LeadFieldErrors,
  field: Extract<
    LeadFormField,
    "phone" | "alternatePhone" | "whatsappNumber"
  >,
  value: string,
  label: string,
): void {
  if (!value) {
    return;
  }

  const digitCount = getPhoneDigitCount(value);

  if (digitCount < 7 || digitCount > 15) {
    addFieldError(
      errors,
      field,
      `${label} must contain between 7 and 15 digits.`,
    );
  }

  if (!/^[+\d\s().-]+$/.test(value)) {
    addFieldError(
      errors,
      field,
      `${label} contains unsupported characters.`,
    );
  }
}

function parseOptionalNumber(
  errors: LeadFieldErrors,
  field: LeadFormField,
  value: string,
  label: string,
  options: {
    integer?: boolean;
    minimum?: number;
    maximum?: number;
  } = {},
): number | null {
  if (!value) {
    return null;
  }

  const parsedValue = Number(value);

  if (!Number.isFinite(parsedValue)) {
    addFieldError(
      errors,
      field,
      `${label} must be a valid number.`,
    );

    return null;
  }

  if (
    options.integer &&
    !Number.isInteger(parsedValue)
  ) {
    addFieldError(
      errors,
      field,
      `${label} must be a whole number.`,
    );
  }

  if (
    options.minimum !== undefined &&
    parsedValue < options.minimum
  ) {
    addFieldError(
      errors,
      field,
      `${label} must be at least ${options.minimum}.`,
    );
  }

  if (
    options.maximum !== undefined &&
    parsedValue > options.maximum
  ) {
    addFieldError(
      errors,
      field,
      `${label} must not exceed ${options.maximum}.`,
    );
  }

  return parsedValue;
}

function parseOptionalBoolean(
  errors: LeadFieldErrors,
  field: LeadFormField,
  value: string,
  label: string,
): boolean | null {
  if (!value) {
    return null;
  }

  if (value === "true") {
    return true;
  }

  if (value === "false") {
    return false;
  }

  addFieldError(
    errors,
    field,
    `${label} must be Yes, No or Not specified.`,
  );

  return null;
}

function parseTags(
  errors: LeadFieldErrors,
  rawValue: string,
): string[] {
  if (!rawValue) {
    return [];
  }

  const candidates = rawValue
    .split(/[,\n]/)
    .map((tag) => normalizeSingleLine(tag))
    .filter(Boolean);

  const uniqueTags: string[] = [];
  const seenTags = new Set<string>();

  for (const tag of candidates) {
    const comparisonKey = tag.toLowerCase();

    if (seenTags.has(comparisonKey)) {
      continue;
    }

    seenTags.add(comparisonKey);
    uniqueTags.push(tag);
  }

  if (uniqueTags.length > LEAD_FORM_LIMITS.tags) {
    addFieldError(
      errors,
      "tags",
      `A maximum of ${LEAD_FORM_LIMITS.tags} tags is allowed.`,
    );
  }

  for (const tag of uniqueTags) {
    if (tag.length > LEAD_FORM_LIMITS.tagLength) {
      addFieldError(
        errors,
        "tags",
        `Each tag must not exceed ${LEAD_FORM_LIMITS.tagLength} characters.`,
      );

      break;
    }
  }

  return uniqueTags.slice(
    0,
    LEAD_FORM_LIMITS.tags,
  );
}

function hasFieldErrors(
  errors: LeadFieldErrors,
): boolean {
  return Object.values(errors).some(
    (messages) =>
      Array.isArray(messages) &&
      messages.length > 0,
  );
}

function buildLeadFormValues(
  formData: FormData,
): LeadFormValues {
  return {
    leadId: normalizeSingleLine(
      getFormString(formData, "leadId"),
    ),

    expectedUpdatedAt: normalizeSingleLine(
      getFormString(
        formData,
        "expectedUpdatedAt",
      ),
    ),

    leadSourceId: normalizeSingleLine(
      getFormString(formData, "leadSourceId"),
    ),

    firstName: normalizeSingleLine(
      getFormString(formData, "firstName"),
    ),

    lastName: normalizeSingleLine(
      getFormString(formData, "lastName"),
    ),

    fullName: normalizeSingleLine(
      getFormString(formData, "fullName"),
    ),

    phone: normalizePhoneInput(
      getFormString(formData, "phone"),
    ),

    alternatePhone: normalizePhoneInput(
      getFormString(formData, "alternatePhone"),
    ),

    email: normalizeEmail(
      getFormString(formData, "email"),
    ),

    whatsappNumber: normalizePhoneInput(
      getFormString(formData, "whatsappNumber"),
    ),

    countryCode: normalizeCountryCode(
      getFormString(formData, "countryCode"),
    ),

    leadStatus: normalizeSingleLine(
      getFormString(formData, "leadStatus"),
    ),

    leadTemperature: normalizeSingleLine(
      getFormString(
        formData,
        "leadTemperature",
      ),
    ),

    priority: normalizeSingleLine(
      getFormString(formData, "priority"),
    ),

    lifecycleStage: normalizeSingleLine(
      getFormString(formData, "lifecycleStage"),
    ),

    propertyType: normalizeSingleLine(
      getFormString(formData, "propertyType"),
    ),

    transactionType: normalizeSingleLine(
      getFormString(formData, "transactionType"),
    ),

    preferredProject: normalizeSingleLine(
      getFormString(
        formData,
        "preferredProject",
      ),
    ),

    preferredLocation: normalizeSingleLine(
      getFormString(
        formData,
        "preferredLocation",
      ),
    ),

    preferredCity: normalizeSingleLine(
      getFormString(formData, "preferredCity"),
    ),

    unitType: normalizeSingleLine(
      getFormString(formData, "unitType"),
    ),

    bedrooms: normalizeSingleLine(
      getFormString(formData, "bedrooms"),
    ),

    budgetMin: normalizeSingleLine(
      getFormString(formData, "budgetMin"),
    ),

    budgetMax: normalizeSingleLine(
      getFormString(formData, "budgetMax"),
    ),

    budgetCurrency:
      normalizeSingleLine(
        getFormString(
          formData,
          "budgetCurrency",
        ),
      ).toUpperCase() || "INR",

    possessionTimeline: normalizeSingleLine(
      getFormString(
        formData,
        "possessionTimeline",
      ),
    ),

    buyingTimeline: normalizeSingleLine(
      getFormString(formData, "buyingTimeline"),
    ),

    purpose: normalizeSingleLine(
      getFormString(formData, "purpose"),
    ),

    financingRequired: normalizeSingleLine(
      getFormString(
        formData,
        "financingRequired",
      ),
    ),

    loanStatus: normalizeSingleLine(
      getFormString(formData, "loanStatus"),
    ),

    consentStatus: normalizeSingleLine(
      getFormString(formData, "consentStatus"),
    ),

    consentSource: normalizeSingleLine(
      getFormString(formData, "consentSource"),
    ),

    preferredLanguage:
      normalizeSingleLine(
        getFormString(
          formData,
          "preferredLanguage",
        ),
      ) || "hi-IN",

    preferredContactChannel:
      normalizeSingleLine(
        getFormString(
          formData,
          "preferredContactChannel",
        ),
      ),

    campaignName: normalizeSingleLine(
      getFormString(formData, "campaignName"),
    ),

    utmSource: normalizeSingleLine(
      getFormString(formData, "utmSource"),
    ),

    utmMedium: normalizeSingleLine(
      getFormString(formData, "utmMedium"),
    ),

    utmCampaign: normalizeSingleLine(
      getFormString(formData, "utmCampaign"),
    ),

    utmTerm: normalizeSingleLine(
      getFormString(formData, "utmTerm"),
    ),

    utmContent: normalizeSingleLine(
      getFormString(formData, "utmContent"),
    ),

    externalLeadId: normalizeSingleLine(
      getFormString(formData, "externalLeadId"),
    ),

    externalProvider: normalizeSingleLine(
      getFormString(
        formData,
        "externalProvider",
      ),
    ),

    notes: normalizeMultiline(
      getFormString(formData, "notes"),
    ),

    tags: normalizeMultiline(
      getFormString(formData, "tags"),
    ),
  };
}

function validateLeadFormValues(
  mode: LeadFormMode,
  values: LeadFormValues,
): {
  errors: LeadFieldErrors;
  bedrooms: number | null;
  budgetMin: number | null;
  budgetMax: number | null;
  financingRequired: boolean | null;
  tags: string[];
} {
  const errors: LeadFieldErrors = {};

  if (mode === "edit") {
    if (!values.leadId) {
      addFieldError(
        errors,
        "leadId",
        "Lead ID is required for editing.",
      );
    } else if (!UUID_PATTERN.test(values.leadId)) {
      addFieldError(
        errors,
        "leadId",
        "Lead ID is not a valid UUID.",
      );
    }

    if (!values.expectedUpdatedAt) {
      addFieldError(
        errors,
        "expectedUpdatedAt",
        "The original update timestamp is required.",
      );
    } else {
      const parsedDate = new Date(
        values.expectedUpdatedAt,
      );

      if (Number.isNaN(parsedDate.getTime())) {
        addFieldError(
          errors,
          "expectedUpdatedAt",
          "The original update timestamp is invalid.",
        );
      }
    }
  }

  if (
    values.leadSourceId &&
    !UUID_PATTERN.test(values.leadSourceId)
  ) {
    addFieldError(
      errors,
      "leadSourceId",
      "Lead source ID is not a valid UUID.",
    );
  }

  if (
    !values.fullName &&
    !values.firstName &&
    !values.lastName
  ) {
    addFieldError(
      errors,
      "fullName",
      "Enter the lead's name.",
    );
  }

  if (
    !values.phone &&
    !values.email &&
    !values.whatsappNumber
  ) {
    addFieldError(
      errors,
      "phone",
      "Provide at least one contact method: phone, email or WhatsApp.",
    );
  }

  validateMaximumLength(
    errors,
    "firstName",
    values.firstName,
    LEAD_FORM_LIMITS.name,
    "First name",
  );

  validateMaximumLength(
    errors,
    "lastName",
    values.lastName,
    LEAD_FORM_LIMITS.name,
    "Last name",
  );

  validateMaximumLength(
    errors,
    "fullName",
    values.fullName,
    LEAD_FORM_LIMITS.name,
    "Full name",
  );

  validateMaximumLength(
    errors,
    "phone",
    values.phone,
    LEAD_FORM_LIMITS.phone,
    "Phone",
  );

  validateMaximumLength(
    errors,
    "alternatePhone",
    values.alternatePhone,
    LEAD_FORM_LIMITS.phone,
    "Alternate phone",
  );

  validateMaximumLength(
    errors,
    "whatsappNumber",
    values.whatsappNumber,
    LEAD_FORM_LIMITS.phone,
    "WhatsApp number",
  );

  validateMaximumLength(
    errors,
    "email",
    values.email,
    LEAD_FORM_LIMITS.email,
    "Email",
  );

  validateMaximumLength(
    errors,
    "notes",
    values.notes,
    LEAD_FORM_LIMITS.notes,
    "Notes",
  );

  validatePhone(
    errors,
    "phone",
    values.phone,
    "Phone",
  );

  validatePhone(
    errors,
    "alternatePhone",
    values.alternatePhone,
    "Alternate phone",
  );

  validatePhone(
    errors,
    "whatsappNumber",
    values.whatsappNumber,
    "WhatsApp number",
  );

  if (
    values.email &&
    !EMAIL_PATTERN.test(values.email)
  ) {
    addFieldError(
      errors,
      "email",
      "Enter a valid email address.",
    );
  }

  if (
    !COUNTRY_CODE_PATTERN.test(values.countryCode)
  ) {
    addFieldError(
      errors,
      "countryCode",
      "Country code must use a format such as +91.",
    );
  }

  if (
    !isAllowedValue(
      values.leadStatus,
      LEAD_STATUSES,
    )
  ) {
    addFieldError(
      errors,
      "leadStatus",
      "Select a valid lead status.",
    );
  }

  if (
    values.leadTemperature &&
    !isAllowedValue(
      values.leadTemperature,
      LEAD_TEMPERATURES,
    )
  ) {
    addFieldError(
      errors,
      "leadTemperature",
      "Select a valid lead temperature.",
    );
  }

  if (
    !isAllowedValue(
      values.priority,
      LEAD_PRIORITIES,
    )
  ) {
    addFieldError(
      errors,
      "priority",
      "Select a valid priority.",
    );
  }

  if (
    !isAllowedValue(
      values.lifecycleStage,
      LEAD_LIFECYCLE_STAGES,
    )
  ) {
    addFieldError(
      errors,
      "lifecycleStage",
      "Select a valid lifecycle stage.",
    );
  }

  if (
    values.transactionType &&
    !isAllowedValue(
      values.transactionType,
      LEAD_TRANSACTION_TYPES,
    )
  ) {
    addFieldError(
      errors,
      "transactionType",
      "Select a valid transaction type.",
    );
  }

  if (
    values.purpose &&
    !isAllowedValue(
      values.purpose,
      LEAD_PURPOSES,
    )
  ) {
    addFieldError(
      errors,
      "purpose",
      "Select a valid buying purpose.",
    );
  }

  if (
    !isAllowedValue(
      values.consentStatus,
      LEAD_CONSENT_STATUSES,
    )
  ) {
    addFieldError(
      errors,
      "consentStatus",
      "Select a valid consent status.",
    );
  }

  if (
    values.preferredContactChannel &&
    !isAllowedValue(
      values.preferredContactChannel,
      LEAD_CONTACT_CHANNELS,
    )
  ) {
    addFieldError(
      errors,
      "preferredContactChannel",
      "Select a valid contact channel.",
    );
  }

  if (!/^[A-Z]{3}$/.test(values.budgetCurrency)) {
    addFieldError(
      errors,
      "budgetCurrency",
      "Currency must be a three-letter ISO code such as INR.",
    );
  }

  const bedrooms = parseOptionalNumber(
    errors,
    "bedrooms",
    values.bedrooms,
    "Bedrooms",
    {
      integer: true,
      minimum: 0,
      maximum: 20,
    },
  );

  const budgetMin = parseOptionalNumber(
    errors,
    "budgetMin",
    values.budgetMin,
    "Minimum budget",
    {
      minimum: 0,
    },
  );

  const budgetMax = parseOptionalNumber(
    errors,
    "budgetMax",
    values.budgetMax,
    "Maximum budget",
    {
      minimum: 0,
    },
  );

  if (
    budgetMin !== null &&
    budgetMax !== null &&
    budgetMin > budgetMax
  ) {
    addFieldError(
      errors,
      "budgetMax",
      "Maximum budget must be greater than or equal to minimum budget.",
    );
  }

  const financingRequired =
    parseOptionalBoolean(
      errors,
      "financingRequired",
      values.financingRequired,
      "Financing required",
    );

  const tags = parseTags(
    errors,
    values.tags,
  );

  const shortTextFields: Array<{
    field: LeadFormField;
    value: string;
    label: string;
  }> = [
    {
      field: "propertyType",
      value: values.propertyType,
      label: "Property type",
    },
    {
      field: "transactionType",
      value: values.transactionType,
      label: "Transaction type",
    },
    {
      field: "preferredCity",
      value: values.preferredCity,
      label: "Preferred city",
    },
    {
      field: "unitType",
      value: values.unitType,
      label: "Unit type",
    },
    {
      field: "buyingTimeline",
      value: values.buyingTimeline,
      label: "Buying timeline",
    },
    {
      field: "possessionTimeline",
      value: values.possessionTimeline,
      label: "Possession timeline",
    },
    {
      field: "loanStatus",
      value: values.loanStatus,
      label: "Loan status",
    },
    {
      field: "consentSource",
      value: values.consentSource,
      label: "Consent source",
    },
    {
      field: "preferredLanguage",
      value: values.preferredLanguage,
      label: "Preferred language",
    },
    {
      field: "externalProvider",
      value: values.externalProvider,
      label: "External provider",
    },
  ];

  for (const item of shortTextFields) {
    validateMaximumLength(
      errors,
      item.field,
      item.value,
      LEAD_FORM_LIMITS.shortText,
      item.label,
    );
  }

  const mediumTextFields: Array<{
    field: LeadFormField;
    value: string;
    label: string;
  }> = [
    {
      field: "preferredProject",
      value: values.preferredProject,
      label: "Preferred project",
    },
    {
      field: "preferredLocation",
      value: values.preferredLocation,
      label: "Preferred location",
    },
    {
      field: "campaignName",
      value: values.campaignName,
      label: "Campaign name",
    },
    {
      field: "externalLeadId",
      value: values.externalLeadId,
      label: "External lead ID",
    },
  ];

  for (const item of mediumTextFields) {
    validateMaximumLength(
      errors,
      item.field,
      item.value,
      LEAD_FORM_LIMITS.mediumText,
      item.label,
    );
  }

  return {
    errors,
    bedrooms,
    budgetMin,
    budgetMax,
    financingRequired,
    tags,
  };
}

function buildPayload(
  values: LeadFormValues,
  parsed: {
    bedrooms: number | null;
    budgetMin: number | null;
    budgetMax: number | null;
    financingRequired: boolean | null;
    tags: string[];
  },
): LeadMutationPayload {
  const generatedFullName =
    values.fullName ||
    [values.firstName, values.lastName]
      .filter(Boolean)
      .join(" ")
      .trim();

  return {
    lead_source_id:
      emptyToNull(values.leadSourceId),

    first_name: emptyToNull(values.firstName),
    last_name: emptyToNull(values.lastName),
    full_name: emptyToNull(generatedFullName),

    phone: emptyToNull(values.phone),
    alternate_phone:
      emptyToNull(values.alternatePhone),
    email: emptyToNull(values.email),
    whatsapp_number:
      emptyToNull(values.whatsappNumber),
    country_code: values.countryCode,

    lead_status: values.leadStatus,
    lead_temperature:
      emptyToNull(values.leadTemperature),
    priority: values.priority,
    lifecycle_stage: values.lifecycleStage,

    property_type:
      emptyToNull(values.propertyType),
    transaction_type:
      emptyToNull(values.transactionType),
    preferred_project:
      emptyToNull(values.preferredProject),
    preferred_location:
      emptyToNull(values.preferredLocation),
    preferred_city:
      emptyToNull(values.preferredCity),
    unit_type: emptyToNull(values.unitType),
    bedrooms: parsed.bedrooms,

    budget_min: parsed.budgetMin,
    budget_max: parsed.budgetMax,
    budget_currency: values.budgetCurrency,

    possession_timeline:
      emptyToNull(values.possessionTimeline),
    buying_timeline:
      emptyToNull(values.buyingTimeline),
    purpose: emptyToNull(values.purpose),
    financing_required:
      parsed.financingRequired,
    loan_status: emptyToNull(values.loanStatus),

    consent_status: values.consentStatus,
    consent_source:
      emptyToNull(values.consentSource),

    preferred_language:
      values.preferredLanguage,
    preferred_contact_channel:
      emptyToNull(
        values.preferredContactChannel,
      ),

    campaign_name:
      emptyToNull(values.campaignName),
    utm_source: emptyToNull(values.utmSource),
    utm_medium: emptyToNull(values.utmMedium),
    utm_campaign:
      emptyToNull(values.utmCampaign),
    utm_term: emptyToNull(values.utmTerm),
    utm_content:
      emptyToNull(values.utmContent),

    external_lead_id:
      emptyToNull(values.externalLeadId),
    external_provider:
      emptyToNull(values.externalProvider),

    notes: emptyToNull(values.notes),
    tags: parsed.tags,
  };
}

export function parseLeadFormData(
  formData: FormData,
  mode: LeadFormMode,
): LeadFormParseResult {
  const values = buildLeadFormValues(formData);

  const validation = validateLeadFormValues(
    mode,
    values,
  );

  if (hasFieldErrors(validation.errors)) {
    return {
      success: false,
      values,
      fieldErrors: validation.errors,
      message:
        "Please correct the highlighted fields and submit the form again.",
    };
  }

  return {
    success: true,
    values,
    payload: buildPayload(values, {
      bedrooms: validation.bedrooms,
      budgetMin: validation.budgetMin,
      budgetMax: validation.budgetMax,
      financingRequired:
        validation.financingRequired,
      tags: validation.tags,
    }),
  };
}