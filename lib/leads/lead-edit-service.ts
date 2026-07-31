import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { LeadFormValues } from "@/types/lead-actions";
import type { LeadSourceSummary } from "@/types/leads";

type NumericValue = number | string | null;

type LeadEditRow = {
  id: string;
  lead_source_id: string | null;

  first_name: string | null;
  last_name: string | null;
  full_name: string | null;

  phone: string | null;
  alternate_phone: string | null;
  email: string | null;
  whatsapp_number: string | null;
  country_code: string | null;

  lead_status: string;
  lead_temperature: string | null;
  priority: string;
  lifecycle_stage: string;

  property_type: string | null;
  transaction_type: string | null;
  preferred_project: string | null;
  preferred_location: string | null;
  preferred_city: string | null;
  unit_type: string | null;
  bedrooms: NumericValue;

  budget_min: NumericValue;
  budget_max: NumericValue;
  budget_currency: string | null;

  possession_timeline: string | null;
  buying_timeline: string | null;
  purpose: string | null;
  financing_required: boolean | null;
  loan_status: string | null;

  consent_status: string;
  consent_source: string | null;

  preferred_language: string | null;
  preferred_contact_channel: string | null;

  campaign_name: string | null;
  utm_source: string | null;
  utm_medium: string | null;
  utm_campaign: string | null;
  utm_term: string | null;
  utm_content: string | null;

  external_lead_id: string | null;
  external_provider: string | null;

  notes: string | null;
  tags: unknown;

  updated_at: string;
};

type LeadSourceRow = {
  id: string;
  name: string;
  code: string;
  source_type: string;
  provider: string | null;
};

export type LeadEditContext = {
  values: LeadFormValues;
  currentSource: LeadSourceSummary | null;
};

const LEAD_EDIT_SELECT = `
  id,
  lead_source_id,
  first_name,
  last_name,
  full_name,
  phone,
  alternate_phone,
  email,
  whatsapp_number,
  country_code,
  lead_status,
  lead_temperature,
  priority,
  lifecycle_stage,
  property_type,
  transaction_type,
  preferred_project,
  preferred_location,
  preferred_city,
  unit_type,
  bedrooms,
  budget_min,
  budget_max,
  budget_currency,
  possession_timeline,
  buying_timeline,
  purpose,
  financing_required,
  loan_status,
  consent_status,
  consent_source,
  preferred_language,
  preferred_contact_channel,
  campaign_name,
  utm_source,
  utm_medium,
  utm_campaign,
  utm_term,
  utm_content,
  external_lead_id,
  external_provider,
  notes,
  tags,
  updated_at
`;

function valueOrEmpty(
  value: string | null | undefined,
): string {
  return value ?? "";
}

function numberOrEmpty(
  value: NumericValue,
): string {
  if (value === null || value === "") {
    return "";
  }

  const parsedValue = Number(value);

  if (!Number.isFinite(parsedValue)) {
    return "";
  }

  return String(parsedValue);
}

function booleanOrEmpty(
  value: boolean | null,
): string {
  if (value === null) {
    return "";
  }

  return value ? "true" : "false";
}

function tagsToString(
  value: unknown,
): string {
  if (!Array.isArray(value)) {
    return "";
  }

  return value
    .filter(
      (item): item is string =>
        typeof item === "string",
    )
    .map((item) => item.trim())
    .filter(Boolean)
    .join(", ");
}

function mapSource(
  row: LeadSourceRow,
): LeadSourceSummary {
  return {
    id: row.id,
    name: row.name,
    code: row.code,
    sourceType: row.source_type,
    provider: row.provider,
  };
}

function mapLeadToFormValues(
  row: LeadEditRow,
): LeadFormValues {
  return {
    leadId: row.id,
    expectedUpdatedAt: row.updated_at,

    leadSourceId: valueOrEmpty(
      row.lead_source_id,
    ),

    firstName: valueOrEmpty(
      row.first_name,
    ),

    lastName: valueOrEmpty(
      row.last_name,
    ),

    /*
     * Edit form में display name blank रहेगा।
     *
     * Save के समय parser firstName + lastName से
     * नया full_name automatically बनाएगा।
     *
     * User custom display name चाहता है तो वह इस
     * field में manually लिख सकता है।
     */
    fullName: "",

    phone: valueOrEmpty(
      row.phone,
    ),

    alternatePhone: valueOrEmpty(
      row.alternate_phone,
    ),

    email: valueOrEmpty(
      row.email,
    ),

    whatsappNumber: valueOrEmpty(
      row.whatsapp_number,
    ),

    countryCode:
      valueOrEmpty(row.country_code) ||
      "+91",

    leadStatus: row.lead_status,

    leadTemperature: valueOrEmpty(
      row.lead_temperature,
    ),

    priority: row.priority,

    lifecycleStage:
      row.lifecycle_stage,

    propertyType: valueOrEmpty(
      row.property_type,
    ),

    transactionType: valueOrEmpty(
      row.transaction_type,
    ),

    preferredProject: valueOrEmpty(
      row.preferred_project,
    ),

    preferredLocation: valueOrEmpty(
      row.preferred_location,
    ),

    preferredCity: valueOrEmpty(
      row.preferred_city,
    ),

    unitType: valueOrEmpty(
      row.unit_type,
    ),

    bedrooms: numberOrEmpty(
      row.bedrooms,
    ),

    budgetMin: numberOrEmpty(
      row.budget_min,
    ),

    budgetMax: numberOrEmpty(
      row.budget_max,
    ),

    budgetCurrency:
      valueOrEmpty(row.budget_currency) ||
      "INR",

    possessionTimeline: valueOrEmpty(
      row.possession_timeline,
    ),

    buyingTimeline: valueOrEmpty(
      row.buying_timeline,
    ),

    purpose: valueOrEmpty(
      row.purpose,
    ),

    financingRequired: booleanOrEmpty(
      row.financing_required,
    ),

    loanStatus: valueOrEmpty(
      row.loan_status,
    ),

    consentStatus:
      row.consent_status,

    consentSource: valueOrEmpty(
      row.consent_source,
    ),

    preferredLanguage:
      valueOrEmpty(
        row.preferred_language,
      ) || "hi-IN",

    preferredContactChannel:
      valueOrEmpty(
        row.preferred_contact_channel,
      ),

    campaignName: valueOrEmpty(
      row.campaign_name,
    ),

    utmSource: valueOrEmpty(
      row.utm_source,
    ),

    utmMedium: valueOrEmpty(
      row.utm_medium,
    ),

    utmCampaign: valueOrEmpty(
      row.utm_campaign,
    ),

    utmTerm: valueOrEmpty(
      row.utm_term,
    ),

    utmContent: valueOrEmpty(
      row.utm_content,
    ),

    externalLeadId: valueOrEmpty(
      row.external_lead_id,
    ),

    externalProvider: valueOrEmpty(
      row.external_provider,
    ),

    notes: valueOrEmpty(
      row.notes,
    ),

    tags: tagsToString(
      row.tags,
    ),
  };
}

export async function getLeadEditContext(
  organizationId: string,
  leadId: string,
): Promise<LeadEditContext | null> {
  const cleanOrganizationId =
    organizationId.trim();

  const cleanLeadId =
    leadId.trim();

  if (
    !cleanOrganizationId ||
    !cleanLeadId
  ) {
    return null;
  }

  const supabase =
    await createClient();

  const {
    data,
    error,
  } = await supabase
    .from("leads")
    .select(LEAD_EDIT_SELECT)
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq(
      "id",
      cleanLeadId,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (error) {
    throw new Error(
      `Unable to load lead edit data: ${error.message}`,
    );
  }

  if (!data) {
    return null;
  }

  const lead =
    data as LeadEditRow;

  let currentSource:
    | LeadSourceSummary
    | null = null;

  if (lead.lead_source_id) {
    const sourceResult =
      await supabase
        .from("lead_sources")
        .select(
          `
            id,
            name,
            code,
            source_type,
            provider
          `,
        )
        .eq(
          "organization_id",
          cleanOrganizationId,
        )
        .eq(
          "id",
          lead.lead_source_id,
        )
        .maybeSingle();

    if (sourceResult.error) {
      throw new Error(
        `Unable to load current lead source: ${sourceResult.error.message}`,
      );
    }

    currentSource =
      sourceResult.data
        ? mapSource(
            sourceResult.data as LeadSourceRow,
          )
        : null;
  }

  return {
    values:
      mapLeadToFormValues(lead),

    currentSource,
  };
}