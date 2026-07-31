export type LeadFormMode = "create" | "edit";

export type LeadFormValues = {
  leadId: string;
  expectedUpdatedAt: string;

  leadSourceId: string;

  firstName: string;
  lastName: string;
  fullName: string;

  phone: string;
  alternatePhone: string;
  email: string;
  whatsappNumber: string;
  countryCode: string;

  leadStatus: string;
  leadTemperature: string;
  priority: string;
  lifecycleStage: string;

  propertyType: string;
  transactionType: string;
  preferredProject: string;
  preferredLocation: string;
  preferredCity: string;
  unitType: string;
  bedrooms: string;

  budgetMin: string;
  budgetMax: string;
  budgetCurrency: string;

  possessionTimeline: string;
  buyingTimeline: string;
  purpose: string;
  financingRequired: string;
  loanStatus: string;

  consentStatus: string;
  consentSource: string;

  preferredLanguage: string;
  preferredContactChannel: string;

  campaignName: string;
  utmSource: string;
  utmMedium: string;
  utmCampaign: string;
  utmTerm: string;
  utmContent: string;

  externalLeadId: string;
  externalProvider: string;

  notes: string;
  tags: string;
};

export type LeadFormField = keyof LeadFormValues;

export type LeadFieldErrors = Partial<
  Record<LeadFormField, string[]>
>;

export type LeadActionStatus =
  | "idle"
  | "error"
  | "success"
  | "conflict";

export type LeadActionState = {
  status: LeadActionStatus;
  message: string;
  fieldErrors: LeadFieldErrors;
  leadId?: string;
};

export type LeadMutationPayload = {
  lead_source_id: string | null;

  first_name: string | null;
  last_name: string | null;
  full_name: string | null;

  phone: string | null;
  alternate_phone: string | null;
  email: string | null;
  whatsapp_number: string | null;
  country_code: string;

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
  bedrooms: number | null;

  budget_min: number | null;
  budget_max: number | null;
  budget_currency: string;

  possession_timeline: string | null;
  buying_timeline: string | null;
  purpose: string | null;
  financing_required: boolean | null;
  loan_status: string | null;

  consent_status: string;
  consent_source: string | null;

  preferred_language: string;
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
  tags: string[];
};

export type CreateLeadCommand = {
  payload: LeadMutationPayload;
};

export type UpdateLeadCommand = {
  leadId: string;
  expectedUpdatedAt: string;
  payload: LeadMutationPayload;
};

export const INITIAL_LEAD_ACTION_STATE: LeadActionState = {
  status: "idle",
  message: "",
  fieldErrors: {},
};