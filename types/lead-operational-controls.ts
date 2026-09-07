import type {
  LeadLifecycleStage,
  LeadStatus,
  LeadTemperature,
} from "@/lib/leads/lead-form-contract";

export type OperationalActionStatus =
  | "idle"
  | "success"
  | "error"
  | "conflict";

export type OperationalFieldErrors =
  Partial<Record<string, string[]>>;

export type OperationalActionState = {
  status: OperationalActionStatus;
  message: string;
  fieldErrors: OperationalFieldErrors;

  leadId?: string;
  assignmentId?: string;
  followUpTaskId?: string;
  siteVisitId?: string;
};

export type LeadOperationalSnapshot = {
  leadId: string;
  updatedAt: string;

  leadStatus: LeadStatus;
  lifecycleStage: LeadLifecycleStage;
  leadTemperature: LeadTemperature | null;

  assignmentStatus: string;
  assignedTo: string | null;
  assignedTeamId: string | null;
};

export type LeadStatusTransitionValues = {
  leadId: string;
  expectedUpdatedAt: string;

  leadStatus: LeadStatus;
  lifecycleStage: LeadLifecycleStage;
  leadTemperature: LeadTemperature | "";

  reason: string;
};

export type AssignmentAgentOption = {
  profileId: string;
  userId: string;

  agentCode: string | null;
  displayName: string;

  status: string;
  availabilityStatus: string;

  currentOpenLeads: number;
  maximumOpenLeads: number;

  acceptNewLeads: boolean;
};

export type AssignmentTeamOption = {
  id: string;
  code: string;
  name: string;

  teamType: string;
  status: string;

  maximumOpenLeads: number | null;
};

export type OrganizationMemberOption = {
  userId: string;
  displayName: string;
  email: string | null;
};

export type LeadAssignmentSummary = {
  id: string;
  leadId: string;

  teamId: string | null;
  agentProfileId: string;
  assignedUserId: string;

  assignmentType: string;
  strategy: string;
  status: string;

  assignmentReason: string | null;
  reassignmentReason: string | null;

  assignedAt: string;
  acceptanceDueAt: string | null;
  responseDueAt: string | null;

  acceptedAt: string | null;
  rejectedAt: string | null;
  firstResponseAt: string | null;
  completedAt: string | null;
  unassignedAt: string | null;

  updatedAt: string;
};

export type ManualAssignmentValues = {
  leadId: string;

  agentProfileId: string;
  teamId: string;

  reason: string;
  overrideCapacity: boolean;
};

export type UnassignLeadValues = {
  leadId: string;
  reason: string;
};

export type AssignmentResponseValues = {
  assignmentId: string;

  response: "accepted" | "rejected";
  notes: string;
};

export type CompleteAssignmentValues = {
  assignmentId: string;
  reason: string;
};

export type FollowUpType =
  | "call"
  | "whatsapp"
  | "email"
  | "sms"
  | "meeting"
  | "site_visit"
  | "document"
  | "payment"
  | "general"
  | "other";

export type FollowUpStatus =
  | "pending"
  | "in_progress"
  | "completed"
  | "cancelled"
  | "overdue"
  | "rescheduled"
  | "failed";

export type FollowUpSlaStatus =
  | "not_applicable"
  | "within_sla"
  | "at_risk"
  | "breached"
  | "resolved";

export type OperationalPriority =
  | "low"
  | "normal"
  | "high"
  | "urgent";

export type FollowUpTaskSummary = {
  id: string;
  leadId: string;

  title: string;
  description: string | null;

  followUpType: FollowUpType;
  status: FollowUpStatus;
  priority: OperationalPriority;

  assignedTo: string | null;

  dueAt: string;
  reminderAt: string | null;

  slaDueAt: string | null;
  slaStatus: FollowUpSlaStatus;

  startedAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;

  completionOutcome: string | null;
  completionNotes: string | null;

  escalationLevel: number;
  escalatedAt: string | null;
  escalatedTo: string | null;

  createdAt: string;
  updatedAt: string;
};

export type CreateFollowUpValues = {
  leadId: string;

  title: string;
  description: string;

  followUpType: FollowUpType;
  priority: OperationalPriority;

  assignedTo: string;

  dueAt: string;
  reminderAt: string;
};

export type AssignFollowUpValues = {
  taskId: string;
  expectedUpdatedAt: string;

  assignedTo: string;
  reason: string;
};

export type RescheduleFollowUpValues = {
  taskId: string;
  expectedUpdatedAt: string;

  dueAt: string;
  reminderAt: string;
  reason: string;
};

export type CancelFollowUpValues = {
  taskId: string;
  expectedUpdatedAt: string;

  reason: string;
};

export type DeleteFollowUpValues = {
  taskId: string;
  expectedUpdatedAt: string;

  reason: string;
};

export type ManageFollowUpSlaValues = {
  taskId: string;
  expectedUpdatedAt: string;

  slaDueAt: string;
  reason: string;
};

export type CompleteFollowUpValues = {
  taskId: string;
  expectedUpdatedAt: string;

  outcome: string;
  notes: string;
};

export type SiteVisitType =
  | "physical"
  | "virtual"
  | "video_call"
  | "property_showcase"
  | "office_meeting"
  | "other";

export type SiteVisitStatus =
  | "draft"
  | "scheduled"
  | "confirmed"
  | "agent_en_route"
  | "customer_en_route"
  | "checked_in"
  | "in_progress"
  | "completed"
  | "rescheduled"
  | "cancelled"
  | "no_show"
  | "failed";

export type SiteVisitConfirmationStatus =
  | "pending"
  | "customer_confirmed"
  | "agent_confirmed"
  | "both_confirmed"
  | "declined"
  | "not_required";

export type SiteVisitOutcome =
  | "interested"
  | "highly_interested"
  | "considering"
  | "follow_up_required"
  | "negotiation_started"
  | "booking_expected"
  | "not_interested"
  | "budget_mismatch"
  | "location_mismatch"
  | "unit_mismatch"
  | "postponed"
  | "no_show"
  | "other";

export type SiteVisitParty =
  | "customer"
  | "agent";

export type SiteVisitCheckInMethod =
  | "manual"
  | "gps"
  | "qr_code"
  | "otp"
  | "agent_confirmation"
  | "system";

export type SiteVisitSummary = {
  id: string;
  leadId: string;

  title: string;
  description: string | null;

  visitType: SiteVisitType;
  status: SiteVisitStatus;
  confirmationStatus: SiteVisitConfirmationStatus;
  priority: OperationalPriority;

  projectName: string;
  developerName: string | null;
  propertyName: string | null;
  unitType: string | null;

  visitAddress: string | null;
  visitCity: string | null;
  locationUrl: string | null;

  scheduledStartAt: string;
  scheduledEndAt: string | null;
  timezone: string;

  assignedAgentId: string | null;
  coordinatorId: string | null;

  customerCheckedInAt: string | null;
  agentCheckedInAt: string | null;
  customerCheckedOutAt: string | null;
  agentCheckedOutAt: string | null;

  outcome: SiteVisitOutcome | null;
  outcomeSummary: string | null;
  agentNotes: string | null;
  probabilityOfBooking: number | null;

  cancellationReason: string | null;

  createdAt: string;
  updatedAt: string;
};

export type CreateSiteVisitValues = {
  leadId: string;

  title: string;
  description: string;

  visitType: SiteVisitType;
  priority: OperationalPriority;

  projectName: string;
  developerName: string;
  propertyName: string;
  unitType: string;

  visitAddress: string;
  visitCity: string;
  locationUrl: string;

  scheduledStartAt: string;
  scheduledEndAt: string;
  timezone: string;

  assignedAgentId: string;
  coordinatorId: string;

  reminderAt: string;

  pickupRequired: boolean;
  pickupAddress: string;
  pickupTime: string;
  transportNotes: string;
};

export type AssignSiteVisitValues = {
  siteVisitId: string;
  expectedUpdatedAt: string;

  assignedAgentId: string;
  coordinatorId: string;

  reason: string;
};

export type SiteVisitCheckInValues = {
  siteVisitId: string;
  expectedUpdatedAt: string;

  party: SiteVisitParty;
  latitude: string;
  longitude: string;

  method: SiteVisitCheckInMethod;
};

export type SiteVisitCheckOutValues = {
  siteVisitId: string;
  expectedUpdatedAt: string;

  party: SiteVisitParty;
};

export type CompleteSiteVisitValues = {
  siteVisitId: string;
  expectedUpdatedAt: string;

  outcome: SiteVisitOutcome;
  outcomeSummary: string;

  probabilityOfBooking: string;
  agentNotes: string;
};

export type CancelSiteVisitValues = {
  siteVisitId: string;
  expectedUpdatedAt: string;

  reason: string;
};