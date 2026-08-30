import {
  LEAD_LIFECYCLE_STAGES,
  LEAD_STATUSES,
  LEAD_TEMPERATURES,
} from "@/lib/leads/lead-form-contract";

import type {
  OperationalActionState,
} from "@/types/lead-operational-controls";

export {
  LEAD_LIFECYCLE_STAGES,
  LEAD_STATUSES,
  LEAD_TEMPERATURES,
};

export const LEAD_OPERATIONAL_PERMISSIONS = {
  viewLeads: "leads.view",
  updateLeadStatus: "leads.update",

  viewAssignments: "assignment.view",
  viewAllAssignments: "assignment.view_all",
  manualAssign: "assignment.manual_assign",
  reassign: "assignment.reassign",
  unassign: "assignment.unassign",
  overrideAssignment: "assignment.override",

  viewFollowUps: "followups.view",
  createFollowUp: "followups.create",
  updateFollowUp: "followups.update",
  assignFollowUp: "followups.assign",
  completeFollowUp: "followups.complete",
  deleteFollowUp: "followups.delete",
  manageFollowUpSla: "followups.manage_sla",

  viewSiteVisits: "site_visits.view",
  viewAllSiteVisits: "site_visits.view_all",
  createSiteVisit: "site_visits.create",
  updateSiteVisit: "site_visits.update",
  assignSiteVisit: "site_visits.assign",
  checkInSiteVisit: "site_visits.check_in",
  completeSiteVisit: "site_visits.complete",
  cancelSiteVisit: "site_visits.cancel",
  deleteSiteVisit: "site_visits.delete",
} as const;

export const ASSIGNMENT_STATUSES = [
  "unassigned",
  "assigned",
  "accepted",
  "rejected",
  "active",
  "completed",
  "reassigned",
  "expired",
  "cancelled",
] as const;

export const FOLLOW_UP_TYPES = [
  "call",
  "whatsapp",
  "email",
  "sms",
  "meeting",
  "site_visit",
  "document",
  "payment",
  "general",
  "other",
] as const;

export const FOLLOW_UP_STATUSES = [
  "pending",
  "in_progress",
  "completed",
  "cancelled",
  "overdue",
  "rescheduled",
  "failed",
] as const;

export const OPERATIONAL_PRIORITIES = [
  "low",
  "normal",
  "high",
  "urgent",
] as const;

export const SITE_VISIT_TYPES = [
  "physical",
  "virtual",
  "video_call",
  "property_showcase",
  "office_meeting",
  "other",
] as const;

export const SITE_VISIT_STATUSES = [
  "draft",
  "scheduled",
  "confirmed",
  "agent_en_route",
  "customer_en_route",
  "checked_in",
  "in_progress",
  "completed",
  "rescheduled",
  "cancelled",
  "no_show",
  "failed",
] as const;

export const SITE_VISIT_CONFIRMATION_STATUSES = [
  "pending",
  "customer_confirmed",
  "agent_confirmed",
  "both_confirmed",
  "declined",
  "not_required",
] as const;

export const SITE_VISIT_OUTCOMES = [
  "interested",
  "highly_interested",
  "considering",
  "follow_up_required",
  "negotiation_started",
  "booking_expected",
  "not_interested",
  "budget_mismatch",
  "location_mismatch",
  "unit_mismatch",
  "postponed",
  "no_show",
  "other",
] as const;

export const SITE_VISIT_PARTIES = [
  "customer",
  "agent",
] as const;

export const SITE_VISIT_CHECK_IN_METHODS = [
  "manual",
  "gps",
  "qr_code",
  "otp",
  "agent_confirmation",
  "system",
] as const;

export const DEFAULT_OPERATIONAL_TIMEZONE =
  "Asia/Kolkata";

export const OPERATIONAL_FORM_LIMITS = {
  title: 200,
  shortText: 250,
  mediumText: 1_000,
  notes: 5_000,
  reason: 1_000,

  probabilityMinimum: 0,
  probabilityMaximum: 100,

  latitudeMinimum: -90,
  latitudeMaximum: 90,

  longitudeMinimum: -180,
  longitudeMaximum: 180,
} as const;

export const INITIAL_OPERATIONAL_ACTION_STATE:
  OperationalActionState = {
    status: "idle",
    message: "",
    fieldErrors: {},
  };

export function formatOperationalLabel(
  value: string,
): string {
  return value
    .replaceAll("_", " ")
    .replaceAll("-", " ")
    .replace(/\b\w/g, (character) =>
      character.toUpperCase(),
    );
}

export function isOperationalValue<
  const TValues extends readonly string[],
>(
  value: string,
  allowedValues: TValues,
): value is TValues[number] {
  return allowedValues.includes(
    value as TValues[number],
  );
}