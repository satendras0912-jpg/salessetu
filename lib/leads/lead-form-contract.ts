import type { LeadFormValues } from "@/types/lead-actions";

export const LEAD_STATUSES = [
  "new",
  "contact_attempted",
  "connected",
  "qualified",
  "unqualified",
  "nurturing",
  "site_visit_planned",
  "site_visit_completed",
  "negotiation",
  "booked",
  "lost",
  "duplicate",
  "invalid",
  "archived",
] as const;

export const LEAD_TEMPERATURES = [
  "hot",
  "warm",
  "cold",
] as const;

export const LEAD_PRIORITIES = [
  "low",
  "normal",
  "high",
  "urgent",
] as const;

export const LEAD_LIFECYCLE_STAGES = [
  "lead",
  "prospect",
  "opportunity",
  "customer",
  "lost",
] as const;

export const LEAD_TRANSACTION_TYPES = [
  "buy",
  "rent",
  "lease",
  "invest",
] as const;

export const LEAD_PURPOSES = [
  "self_use",
  "investment",
  "rental_income",
  "business",
  "other",
] as const;

export const LEAD_CONSENT_STATUSES = [
  "unknown",
  "granted",
  "withdrawn",
  "not_required",
] as const;

export const LEAD_CONTACT_CHANNELS = [
  "phone",
  "whatsapp",
  "email",
  "sms",
] as const;

export const LEAD_QUALIFICATION_STATUSES = [
  "pending",
  "in_progress",
  "qualified",
  "partially_qualified",
  "unqualified",
  "failed",
  "manual_review",
] as const;

export const LEAD_ASSIGNMENT_STATUSES = [
  "unassigned",
  "assigned",
  "accepted",
  "rejected",
  "reassigned",
] as const;

export const LEAD_DUPLICATE_STATUSES = [
  "unchecked",
  "unique",
  "possible_duplicate",
  "confirmed_duplicate",
  "merged",
  "ignored",
] as const;

export const LEAD_FAKE_STATUSES = [
  "unchecked",
  "valid",
  "suspicious",
  "fake",
  "manual_review",
] as const;

export const LEAD_SOURCE_TYPES = [
  "website",
  "landing_page",
  "meta_ads",
  "google_ads",
  "whatsapp",
  "phone_call",
  "walk_in",
  "referral",
  "partner",
  "import",
  "api",
  "manual",
  "other",
] as const;

export type LeadStatus =
  (typeof LEAD_STATUSES)[number];

export type LeadTemperature =
  (typeof LEAD_TEMPERATURES)[number];

export type LeadPriority =
  (typeof LEAD_PRIORITIES)[number];

export type LeadLifecycleStage =
  (typeof LEAD_LIFECYCLE_STAGES)[number];

export type LeadTransactionType =
  (typeof LEAD_TRANSACTION_TYPES)[number];

export type LeadPurpose =
  (typeof LEAD_PURPOSES)[number];

export type LeadConsentStatus =
  (typeof LEAD_CONSENT_STATUSES)[number];

export type LeadContactChannel =
  (typeof LEAD_CONTACT_CHANNELS)[number];

export const DEFAULT_LEAD_FORM_VALUES: LeadFormValues = {
  leadId: "",
  expectedUpdatedAt: "",

  leadSourceId: "",

  firstName: "",
  lastName: "",
  fullName: "",

  phone: "",
  alternatePhone: "",
  email: "",
  whatsappNumber: "",
  countryCode: "+91",

  leadStatus: "new",
  leadTemperature: "",
  priority: "normal",
  lifecycleStage: "lead",

  propertyType: "",
  transactionType: "",
  preferredProject: "",
  preferredLocation: "",
  preferredCity: "",
  unitType: "",
  bedrooms: "",

  budgetMin: "",
  budgetMax: "",
  budgetCurrency: "INR",

  possessionTimeline: "",
  buyingTimeline: "",
  purpose: "",
  financingRequired: "",
  loanStatus: "",

  consentStatus: "unknown",
  consentSource: "",

  preferredLanguage: "hi-IN",
  preferredContactChannel: "",

  campaignName: "",
  utmSource: "",
  utmMedium: "",
  utmCampaign: "",
  utmTerm: "",
  utmContent: "",

  externalLeadId: "",
  externalProvider: "",

  notes: "",
  tags: "",
};

export const LEAD_FORM_LIMITS = {
  name: 200,
  phone: 30,
  email: 320,
  shortText: 200,
  mediumText: 500,
  notes: 5_000,
  tags: 25,
  tagLength: 60,
} as const;

export const LEAD_FORM_PERMISSIONS = {
  create: "leads.create",
  update: "leads.update",
  view: "leads.view",
  assign: "leads.assign",
  qualify: "leads.qualify",
  delete: "leads.delete",
  manageSources: "leads.manage_sources",
} as const;

export const SYSTEM_MANAGED_LEAD_FIELDS = [
  "organization_id",

  "normalized_phone",
  "normalized_alternate_phone",
  "normalized_email",
  "normalized_whatsapp_number",

  "qualification_status",
  "qualification_score",
  "qualification_reason",
  "qualification_summary",

  "ai_qualified",
  "ai_provider",
  "ai_model",
  "ai_qualification_version",
  "ai_qualified_at",

  "duplicate_status",
  "duplicate_of_lead_id",
  "duplicate_confidence",

  "fake_status",
  "fake_score",
  "fake_reason",

  "phone_verified",
  "email_verified",
  "whatsapp_verified",

  "assigned_to",
  "assigned_by",
  "assigned_at",
  "assignment_status",
  "assigned_team_id",
  "assignment_due_at",
  "assignment_metadata",

  "first_contacted_at",
  "last_contacted_at",
  "next_follow_up_at",
  "qualified_at",
  "converted_at",
  "lost_at",

  "created_by",
  "updated_by",
  "deleted_by",
  "deleted_at",
  "created_at",
  "updated_at",
] as const;

export function formatLeadOptionLabel(
  value: string,
): string {
  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (character) =>
      character.toUpperCase(),
    );
}

export function isAllowedValue<
  const TValues extends readonly string[],
>(
  value: string,
  allowedValues: TValues,
): value is TValues[number] {
  return allowedValues.includes(
    value as TValues[number],
  );
}