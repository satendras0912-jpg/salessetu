import type {
  LeadAssignmentSummary,
  LeadSourceSummary,
} from "@/types/leads";

export type JsonObject = Record<string, unknown>;

export type LeadDetailAccess = {
  canViewValidation: boolean;
  canViewAssignment: boolean;
  canViewFollowUps: boolean;
  canViewSiteVisits: boolean;
  canViewAiCalls: boolean;
};

export type LeadValidationDetail = {
  id: string | null;
  validationJobId: string | null;
  status: string | null;
  decision: string | null;

  authenticityScore: number | null;
  contactabilityScore: number | null;
  completenessScore: number | null;
  intentScore: number | null;
  sourceQualityScore: number | null;
  trustScore: number | null;
  duplicateScore: number | null;
  fraudScore: number | null;
  spamScore: number | null;

  passedRuleCount: number | null;
  failedRuleCount: number | null;
  warningRuleCount: number | null;
  blockingRuleCount: number | null;

  decisionReasons: unknown[];
  riskFactors: unknown[];
  qualityFactors: unknown[];
  duplicateMatches: unknown[];
  blacklistMatches: unknown[];
  suppressionMatches: unknown[];

  normalizedPhone: string | null;
  normalizedEmail: string | null;
  detectedCountryCode: string | null;
  detectedRegion: string | null;
  detectedCity: string | null;

  phoneValid: boolean | null;
  emailValid: boolean | null;
  consentValid: boolean | null;
  sourceValid: boolean | null;

  aiCallEligibility: string | null;
  aiCallBlockReason: string | null;
  recommendedAction: string | null;
  recommendedWorkflowCode: string | null;
  summary: string | null;

  manuallyReviewed: boolean;
  reviewDecision: string | null;
  reviewNotes: string | null;
  reviewedAt: string | null;

  overridden: boolean;
  overrideReason: string | null;
  overriddenAt: string | null;

  createdAt: string | null;
  updatedAt: string | null;
};

export type LeadAssignmentDetail =
  LeadAssignmentSummary & {
    teamId: string | null;
    priority: number | null;
    assignmentScore: number | null;
    acceptedAt: string | null;
    rejectedAt: string | null;
    firstResponseAt: string | null;
    completedAt: string | null;
    unassignedAt: string | null;
    reassignmentReason: string | null;
    assignmentReason: string | null;
  };

export type LeadActivityItem = {
  id: string;
  activityType: string;
  direction: string | null;
  status: string;
  subject: string | null;
  description: string | null;
  outcome: string | null;
  outcomeCode: string | null;
  channelProvider: string | null;
  externalActivityId: string | null;
  durationSeconds: number | null;
  startedAt: string | null;
  completedAt: string | null;
  performedBy: string | null;
  isAutomated: boolean;
  aiGenerated: boolean;
  aiSummary: string | null;
  aiSentiment: string | null;
  metadata: JsonObject;
  createdAt: string;
};

export type LeadStatusHistoryItem = {
  id: string;
  previousStatus: string | null;
  newStatus: string;
  previousLifecycleStage: string | null;
  newLifecycleStage: string | null;
  previousTemperature: string | null;
  newTemperature: string | null;
  changeReason: string | null;
  changedBy: string | null;
  metadata: JsonObject;
  changedAt: string;
};

export type LeadFollowUpItem = {
  id: string;
  title: string;
  description: string | null;
  followUpType: string;
  status: string;
  priority: string;

  assignedTo: string | null;
  assignedBy: string | null;
  assignedAt: string | null;

  dueAt: string;
  reminderAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;

  completionOutcome: string | null;
  completionNotes: string | null;

  attemptCount: number;
  maximumAttempts: number | null;
  nextRetryAt: string | null;

  isAutomated: boolean;
  slaDueAt: string | null;
  slaStatus: string;
  escalationLevel: number;
  escalatedAt: string | null;

  metadata: JsonObject;
  createdAt: string;
  updatedAt: string;
};

export type LeadSiteVisitItem = {
  id: string;
  visitNumber: string | null;
  title: string;
  description: string | null;

  visitType: string;
  projectReferenceId: string | null;
  projectName: string;
  developerName: string | null;
  propertyName: string | null;
  propertyType: string | null;

  unitReference: string | null;
  unitType: string | null;
  tower: string | null;
  floor: string | null;
  unitNumber: string | null;

  visitAddress: string | null;
  visitCity: string | null;
  visitState: string | null;
  landmark: string | null;
  locationUrl: string | null;

  status: string;
  confirmationStatus: string;
  priority: string;

  scheduledStartAt: string;
  scheduledEndAt: string | null;
  expectedDurationMinutes: number | null;
  timezone: string;

  assignedAgentId: string | null;
  assignedAt: string | null;

  pickupRequired: boolean;
  pickupAddress: string | null;
  pickupTime: string | null;

  customerCheckedInAt: string | null;
  agentCheckedInAt: string | null;
  visitStartedAt: string | null;
  visitCompletedAt: string | null;

  outcome: string | null;
  outcomeSummary: string | null;
  customerFeedback: string | null;
  agentNotes: string | null;

  customerRating: number | null;
  projectRating: number | null;
  probabilityOfBooking: number | null;
  expectedBookingDate: string | null;
  expectedBookingValue: number | null;

  rescheduleCount: number;
  cancellationReason: string | null;
  noShowParty: string | null;

  quotedPrice: number | null;
  quotedCurrency: string;
  discountDiscussed: number | null;
  paymentPlanDiscussed: string | null;
  bookingTokenDiscussed: number | null;

  amenitiesShown: string[];
  objections: string[];
  tags: string[];
  metadata: JsonObject;

  createdAt: string;
  updatedAt: string;
};

export type LeadAiCallAttemptItem = {
  id: string;
  callJobId: string;
  attemptNumber: number;
  status: string;
  dispositionCode: string | null;

  fromPhoneNumber: string | null;
  toPhoneNumber: string;

  errorCode: string | null;
  errorMessage: string | null;

  recordingUrl: string | null;
  recordingDurationSeconds: number | null;
  callDurationSeconds: number | null;
  ringDurationSeconds: number | null;

  providerCost: number | null;
  providerCurrency: string | null;

  dispatchedAt: string | null;
  initiatedAt: string | null;
  answeredAt: string | null;
  endedAt: string | null;
  completedAt: string | null;

  createdAt: string;
};

export type LeadAiCallTranscriptItem = {
  id: string;
  callJobId: string;
  callAttemptId: string;
  transcriptStatus: string;
  languageCode: string | null;

  rawTranscript: string | null;
  normalizedTranscript: string | null;
  summary: string | null;

  sentiment: string | null;
  sentimentScore: number | null;
  intentSummary: string | null;
  qualityScore: number | null;

  objections: unknown[];
  commitments: unknown[];
  entities: JsonObject;
  complianceFlags: unknown[];

  reviewedAt: string | null;
  reviewNotes: string | null;
  createdAt: string;
};

export type LeadAiQualificationItem = {
  id: string;
  callJobId: string;
  callAttemptId: string;
  status: string;

  totalScore: number;
  maximumScore: number;
  normalizedScore: number;

  validAnswerCount: number;
  requiredAnswerCount: number;

  missingRequiredQuestions: unknown[];
  disqualifyingReasons: unknown[];

  qualificationSummary: string | null;
  recommendedAction: string | null;
  recommendedFollowUpAt: string | null;
  recommendedAgentId: string | null;

  extractedProfile: JsonObject;
  scoringBreakdown: JsonObject;

  modelName: string | null;
  modelVersion: string | null;

  reviewStatus: string | null;
  reviewNotes: string | null;
  reviewedAt: string | null;

  createdAt: string;
};

export type LeadAiCallJobItem = {
  id: string;
  campaignId: string | null;
  status: string;
  priority: number;

  phoneNumber: string;
  contactName: string | null;
  languageCode: string;

  scheduledAt: string | null;
  expiresAt: string | null;

  maximumAttempts: number;
  attemptCount: number;
  nextAttemptAt: string | null;

  finalDispositionCode: string | null;
  qualificationStatus: string | null;
  qualificationScore: number | null;

  consentStatus: string | null;
  blockedReason: string | null;

  queuedAt: string | null;
  startedAt: string | null;
  completedAt: string | null;
  cancelledAt: string | null;
  cancellationReason: string | null;

  resultData: JsonObject;
  errorData: JsonObject;
  metadata: JsonObject;

  attempts: LeadAiCallAttemptItem[];
  transcripts: LeadAiCallTranscriptItem[];
  qualificationResults: LeadAiQualificationItem[];

  createdAt: string;
  updatedAt: string;
};

export type LeadDetailRecord = {
  id: string;
  organizationId: string;
  leadSourceId: string | null;

  firstName: string | null;
  lastName: string | null;
  fullName: string;

  phone: string | null;
  normalizedPhone: string | null;
  alternatePhone: string | null;
  email: string | null;
  normalizedEmail: string | null;
  whatsappNumber: string | null;
  countryCode: string;

  leadStatus: string;
  leadTemperature: string | null;
  priority: string;
  lifecycleStage: string;

  propertyType: string | null;
  transactionType: string | null;
  preferredProject: string | null;
  preferredLocation: string | null;
  preferredCity: string | null;
  unitType: string | null;
  bedrooms: number | null;

  budgetMin: number | null;
  budgetMax: number | null;
  budgetCurrency: string;

  possessionTimeline: string | null;
  buyingTimeline: string | null;
  purpose: string | null;
  financingRequired: boolean | null;
  loanStatus: string | null;

  qualificationStatus: string;
  qualificationScore: number | null;
  qualificationReason: string | null;
  qualificationSummary: string | null;
  aiQualified: boolean;
  aiProvider: string | null;
  aiModel: string | null;
  aiQualifiedAt: string | null;

  duplicateStatus: string;
  duplicateOfLeadId: string | null;
  duplicateConfidence: number | null;

  fakeStatus: string;
  fakeScore: number | null;
  fakeReason: string | null;

  phoneVerified: boolean;
  emailVerified: boolean;
  whatsappVerified: boolean;

  consentStatus: string;
  consentSource: string | null;
  consentAt: string | null;

  doNotCall: boolean;
  doNotEmail: boolean;
  doNotWhatsapp: boolean;

  preferredLanguage: string;
  preferredContactChannel: string | null;

  campaignId: string | null;
  campaignName: string | null;
  utmSource: string | null;
  utmMedium: string | null;
  utmCampaign: string | null;
  utmTerm: string | null;
  utmContent: string | null;

  externalLeadId: string | null;
  externalProvider: string | null;
  metaLeadId: string | null;
  googleLeadId: string | null;

  assignedTo: string | null;
  assignedAt: string | null;
  assignmentStatus: string;

  firstContactedAt: string | null;
  lastContactedAt: string | null;
  nextFollowUpAt: string | null;
  qualifiedAt: string | null;
  convertedAt: string | null;
  lostAt: string | null;
  lostReason: string | null;

  notes: string | null;
  tags: string[];
  customFields: JsonObject;
  metadata: JsonObject;

  source: LeadSourceSummary | null;
  validation: LeadValidationDetail | null;
  assignment: LeadAssignmentDetail | null;

  activities: LeadActivityItem[];
  statusHistory: LeadStatusHistoryItem[];
  followUps: LeadFollowUpItem[];
  siteVisits: LeadSiteVisitItem[];
  aiCalls: LeadAiCallJobItem[];

  createdAt: string;
  updatedAt: string;
};