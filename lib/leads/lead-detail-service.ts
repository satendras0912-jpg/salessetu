import "server-only";

import { createClient } from "@/lib/supabase/server";
import type {
  JsonObject,
  LeadActivityItem,
  LeadAiCallAttemptItem,
  LeadAiCallJobItem,
  LeadAiCallTranscriptItem,
  LeadAiQualificationItem,
  LeadAssignmentDetail,
  LeadDetailAccess,
  LeadDetailRecord,
  LeadFollowUpItem,
  LeadSiteVisitItem,
  LeadStatusHistoryItem,
  LeadValidationDetail,
} from "@/types/lead-detail";
import type { LeadSourceSummary } from "@/types/leads";

const DETAIL_RECORD_LIMIT = 100;

type NumericValue = number | string | null;

type LeadDetailRow = {
  id: string;
  organization_id: string;
  lead_source_id: string | null;

  first_name: string | null;
  last_name: string | null;
  full_name: string | null;

  phone: string | null;
  normalized_phone: string | null;
  alternate_phone: string | null;
  email: string | null;
  normalized_email: string | null;
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
  bedrooms: NumericValue;

  budget_min: NumericValue;
  budget_max: NumericValue;
  budget_currency: string;

  possession_timeline: string | null;
  buying_timeline: string | null;
  purpose: string | null;
  financing_required: boolean | null;
  loan_status: string | null;

  qualification_status: string;
  qualification_score: NumericValue;
  qualification_reason: string | null;
  qualification_summary: string | null;
  ai_qualified: boolean;
  ai_provider: string | null;
  ai_model: string | null;
  ai_qualified_at: string | null;

  duplicate_status: string;
  duplicate_of_lead_id: string | null;
  duplicate_confidence: NumericValue;

  fake_status: string;
  fake_score: NumericValue;
  fake_reason: string | null;

  phone_verified: boolean;
  email_verified: boolean;
  whatsapp_verified: boolean;

  consent_status: string;
  consent_source: string | null;
  consent_at: string | null;

  do_not_call: boolean;
  do_not_email: boolean;
  do_not_whatsapp: boolean;

  preferred_language: string;
  preferred_contact_channel: string | null;

  campaign_id: string | null;
  campaign_name: string | null;
  utm_source: string | null;
  utm_medium: string | null;
  utm_campaign: string | null;
  utm_term: string | null;
  utm_content: string | null;

  external_lead_id: string | null;
  external_provider: string | null;
  meta_lead_id: string | null;
  google_lead_id: string | null;

  assigned_to: string | null;
  assigned_at: string | null;
  assignment_status: string;

  first_contacted_at: string | null;
  last_contacted_at: string | null;
  next_follow_up_at: string | null;
  qualified_at: string | null;
  converted_at: string | null;
  lost_at: string | null;
  lost_reason: string | null;

  notes: string | null;
  tags: unknown;
  custom_fields: unknown;
  metadata: unknown;

  created_at: string;
  updated_at: string;
};

type LeadSourceRow = {
  id: string;
  name: string;
  code: string;
  source_type: string;
  provider: string | null;
};

type ValidationRow = {
  id: string | null;
  validation_job_id: string | null;
  status: string | null;
  decision: string | null;

  authenticity_score: NumericValue;
  contactability_score: NumericValue;
  completeness_score: NumericValue;
  intent_score: NumericValue;
  source_quality_score: NumericValue;
  trust_score: NumericValue;
  duplicate_score: NumericValue;
  fraud_score: NumericValue;
  spam_score: NumericValue;

  passed_rule_count: number | null;
  failed_rule_count: number | null;
  warning_rule_count: number | null;
  blocking_rule_count: number | null;

  decision_reasons: unknown;
  risk_factors: unknown;
  quality_factors: unknown;
  duplicate_matches: unknown;
  blacklist_matches: unknown;
  suppression_matches: unknown;

  normalized_phone: string | null;
  normalized_email: string | null;
  detected_country_code: string | null;
  detected_region: string | null;
  detected_city: string | null;

  phone_valid: boolean | null;
  email_valid: boolean | null;
  consent_valid: boolean | null;
  source_valid: boolean | null;

  ai_call_eligibility: string | null;
  ai_call_block_reason: string | null;
  recommended_action: string | null;
  recommended_workflow_code: string | null;
  summary: string | null;

  manually_reviewed: boolean | null;
  review_decision: string | null;
  review_notes: string | null;
  reviewed_at: string | null;

  overridden: boolean | null;
  override_reason: string | null;
  overridden_at: string | null;

  created_at: string | null;
  updated_at: string | null;
};

type AssignmentRow = {
  id: string;
  team_id: string | null;
  agent_profile_id: string | null;
  assigned_user_id: string | null;

  assignment_type: string | null;
  strategy: string | null;
  status: string | null;

  priority: number | null;
  assignment_score: NumericValue;

  assigned_at: string | null;
  acceptance_due_at: string | null;
  response_due_at: string | null;

  accepted_at: string | null;
  rejected_at: string | null;
  first_response_at: string | null;
  completed_at: string | null;
  unassigned_at: string | null;

  reassignment_reason: string | null;
  assignment_reason: string | null;
};

type AgentProfileRow = {
  id: string;
  agent_code: string | null;
  display_name: string | null;
};

type ActivityRow = {
  id: string;
  activity_type: string;
  direction: string | null;
  activity_status: string;
  subject: string | null;
  description: string | null;
  outcome: string | null;
  outcome_code: string | null;
  channel_provider: string | null;
  external_activity_id: string | null;
  duration_seconds: number | null;
  started_at: string | null;
  completed_at: string | null;
  performed_by: string | null;
  is_automated: boolean;
  ai_generated: boolean;
  ai_summary: string | null;
  ai_sentiment: string | null;
  metadata: unknown;
  created_at: string;
};

type StatusHistoryRow = {
  id: string;
  previous_status: string | null;
  new_status: string;
  previous_lifecycle_stage: string | null;
  new_lifecycle_stage: string | null;
  previous_temperature: string | null;
  new_temperature: string | null;
  change_reason: string | null;
  changed_by: string | null;
  metadata: unknown;
  changed_at: string;
};

type FollowUpRow = {
  id: string;
  title: string;
  description: string | null;
  follow_up_type: string;
  status: string;
  priority: string;

  assigned_to: string | null;
  assigned_by: string | null;
  assigned_at: string | null;

  due_at: string;
  reminder_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;

  completion_outcome: string | null;
  completion_notes: string | null;

  attempt_count: number;
  max_attempts: number | null;
  next_retry_at: string | null;

  is_automated: boolean;
  sla_due_at: string | null;
  sla_status: string;
  escalation_level: number;
  escalated_at: string | null;

  metadata: unknown;
  created_at: string;
  updated_at: string;
};

type SiteVisitRow = {
  id: string;
  visit_number: string | null;
  title: string;
  description: string | null;

  visit_type: string;
  project_reference_id: string | null;
  project_name: string;
  developer_name: string | null;
  property_name: string | null;
  property_type: string | null;

  unit_reference: string | null;
  unit_type: string | null;
  tower: string | null;
  floor: string | null;
  unit_number: string | null;

  visit_address: string | null;
  visit_city: string | null;
  visit_state: string | null;
  landmark: string | null;
  location_url: string | null;

  status: string;
  confirmation_status: string;
  priority: string;

  scheduled_start_at: string;
  scheduled_end_at: string | null;
  expected_duration_minutes: number | null;
  timezone: string;

  assigned_agent_id: string | null;
  assigned_at: string | null;

  pickup_required: boolean;
  pickup_address: string | null;
  pickup_time: string | null;

  customer_checked_in_at: string | null;
  agent_checked_in_at: string | null;
  visit_started_at: string | null;
  visit_completed_at: string | null;

  outcome: string | null;
  outcome_summary: string | null;
  customer_feedback: string | null;
  agent_notes: string | null;

  customer_rating: number | null;
  project_rating: number | null;
  probability_of_booking: NumericValue;
  expected_booking_date: string | null;
  expected_booking_value: NumericValue;

  reschedule_count: number;
  cancellation_reason: string | null;
  no_show_party: string | null;

  quoted_price: NumericValue;
  quoted_currency: string;
  discount_discussed: NumericValue;
  payment_plan_discussed: string | null;
  booking_token_discussed: NumericValue;

  amenities_shown: unknown;
  objections: unknown;
  tags: unknown;
  metadata: unknown;

  created_at: string;
  updated_at: string;
};

type AiCallJobRow = {
  id: string;
  campaign_id: string | null;
  status: string;
  priority: number;

  phone_number: string;
  contact_name: string | null;
  language_code: string;

  scheduled_at: string | null;
  expires_at: string | null;

  maximum_attempts: number;
  attempt_count: number;
  next_attempt_at: string | null;

  final_disposition_code: string | null;
  qualification_status: string | null;
  qualification_score: NumericValue;

  consent_status: string | null;
  blocked_reason: string | null;

  queued_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;
  cancellation_reason: string | null;

  result_data: unknown;
  error_data: unknown;
  metadata: unknown;

  created_at: string;
  updated_at: string;
};

type AiCallAttemptRow = {
  id: string;
  call_job_id: string;
  attempt_number: number;
  status: string;
  disposition_code: string | null;

  from_phone_number: string | null;
  to_phone_number: string;

  error_code: string | null;
  error_message: string | null;

  recording_url: string | null;
  recording_duration_seconds: number | null;
  call_duration_seconds: number | null;
  ring_duration_seconds: number | null;

  provider_cost: NumericValue;
  provider_currency: string | null;

  dispatched_at: string | null;
  initiated_at: string | null;
  answered_at: string | null;
  ended_at: string | null;
  completed_at: string | null;

  created_at: string;
};

type AiCallTranscriptRow = {
  id: string;
  call_job_id: string;
  call_attempt_id: string;
  transcript_status: string;
  language_code: string | null;

  raw_transcript: string | null;
  normalized_transcript: string | null;
  summary: string | null;

  sentiment: string | null;
  sentiment_score: NumericValue;
  intent_summary: string | null;
  quality_score: NumericValue;

  objections: unknown;
  commitments: unknown;
  entities: unknown;
  compliance_flags: unknown;

  reviewed_at: string | null;
  review_notes: string | null;

  created_at: string;
};

type AiQualificationRow = {
  id: string;
  call_job_id: string;
  call_attempt_id: string;
  status: string;

  total_score: NumericValue;
  maximum_score: NumericValue;
  normalized_score: NumericValue;

  valid_answer_count: number;
  required_answer_count: number;

  missing_required_questions: unknown;
  disqualifying_reasons: unknown;

  qualification_summary: string | null;
  recommended_action: string | null;
  recommended_followup_at: string | null;
  recommended_agent_id: string | null;

  extracted_profile: unknown;
  scoring_breakdown: unknown;

  model_name: string | null;
  model_version: string | null;

  review_status: string | null;
  review_notes: string | null;
  reviewed_at: string | null;

  created_at: string;
};

const LEAD_DETAIL_SELECT = `
  id,
  organization_id,
  lead_source_id,
  first_name,
  last_name,
  full_name,
  phone,
  normalized_phone,
  alternate_phone,
  email,
  normalized_email,
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
  qualification_status,
  qualification_score,
  qualification_reason,
  qualification_summary,
  ai_qualified,
  ai_provider,
  ai_model,
  ai_qualified_at,
  duplicate_status,
  duplicate_of_lead_id,
  duplicate_confidence,
  fake_status,
  fake_score,
  fake_reason,
  phone_verified,
  email_verified,
  whatsapp_verified,
  consent_status,
  consent_source,
  consent_at,
  do_not_call,
  do_not_email,
  do_not_whatsapp,
  preferred_language,
  preferred_contact_channel,
  campaign_id,
  campaign_name,
  utm_source,
  utm_medium,
  utm_campaign,
  utm_term,
  utm_content,
  external_lead_id,
  external_provider,
  meta_lead_id,
  google_lead_id,
  assigned_to,
  assigned_at,
  assignment_status,
  first_contacted_at,
  last_contacted_at,
  next_follow_up_at,
  qualified_at,
  converted_at,
  lost_at,
  lost_reason,
  notes,
  tags,
  custom_fields,
  metadata,
  created_at,
  updated_at
`;

function toNumber(value: NumericValue): number | null {
  if (value === null || value === "") {
    return null;
  }

  const parsed = Number(value);

  return Number.isFinite(parsed) ? parsed : null;
}

function toJsonObject(value: unknown): JsonObject {
  if (
    value !== null &&
    typeof value === "object" &&
    !Array.isArray(value)
  ) {
    return value as JsonObject;
  }

  return {};
}

function toUnknownArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function toStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(
    (item): item is string => typeof item === "string",
  );
}

function getLeadDisplayName(row: LeadDetailRow): string {
  const fullName = row.full_name?.trim();

  if (fullName) {
    return fullName;
  }

  const generatedName = [
    row.first_name?.trim(),
    row.last_name?.trim(),
  ]
    .filter(
      (part): part is string =>
        typeof part === "string" && part.length > 0,
    )
    .join(" ");

  return generatedName || "Unnamed Lead";
}

function mapLeadSource(
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

function mapValidation(
  row: ValidationRow,
): LeadValidationDetail {
  return {
    id: row.id,
    validationJobId: row.validation_job_id,
    status: row.status,
    decision: row.decision,

    authenticityScore: toNumber(
      row.authenticity_score,
    ),
    contactabilityScore: toNumber(
      row.contactability_score,
    ),
    completenessScore: toNumber(
      row.completeness_score,
    ),
    intentScore: toNumber(row.intent_score),
    sourceQualityScore: toNumber(
      row.source_quality_score,
    ),
    trustScore: toNumber(row.trust_score),
    duplicateScore: toNumber(row.duplicate_score),
    fraudScore: toNumber(row.fraud_score),
    spamScore: toNumber(row.spam_score),

    passedRuleCount: row.passed_rule_count,
    failedRuleCount: row.failed_rule_count,
    warningRuleCount: row.warning_rule_count,
    blockingRuleCount: row.blocking_rule_count,

    decisionReasons: toUnknownArray(
      row.decision_reasons,
    ),
    riskFactors: toUnknownArray(row.risk_factors),
    qualityFactors: toUnknownArray(
      row.quality_factors,
    ),
    duplicateMatches: toUnknownArray(
      row.duplicate_matches,
    ),
    blacklistMatches: toUnknownArray(
      row.blacklist_matches,
    ),
    suppressionMatches: toUnknownArray(
      row.suppression_matches,
    ),

    normalizedPhone: row.normalized_phone,
    normalizedEmail: row.normalized_email,
    detectedCountryCode: row.detected_country_code,
    detectedRegion: row.detected_region,
    detectedCity: row.detected_city,

    phoneValid: row.phone_valid,
    emailValid: row.email_valid,
    consentValid: row.consent_valid,
    sourceValid: row.source_valid,

    aiCallEligibility: row.ai_call_eligibility,
    aiCallBlockReason: row.ai_call_block_reason,
    recommendedAction: row.recommended_action,
    recommendedWorkflowCode:
      row.recommended_workflow_code,
    summary: row.summary,

    manuallyReviewed:
      row.manually_reviewed ?? false,
    reviewDecision: row.review_decision,
    reviewNotes: row.review_notes,
    reviewedAt: row.reviewed_at,

    overridden: row.overridden ?? false,
    overrideReason: row.override_reason,
    overriddenAt: row.overridden_at,

    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapAssignment(
  row: AssignmentRow,
  agent: AgentProfileRow | null,
): LeadAssignmentDetail {
  return {
    assignmentId: row.id,
    status: row.status,
    assignmentType: row.assignment_type,
    strategy: row.strategy,
    agentProfileId: row.agent_profile_id,
    assignedUserId: row.assigned_user_id,
    agentName: agent?.display_name ?? null,
    agentCode: agent?.agent_code ?? null,
    assignedAt: row.assigned_at,
    acceptanceDueAt: row.acceptance_due_at,
    responseDueAt: row.response_due_at,

    teamId: row.team_id,
    priority: row.priority,
    assignmentScore: toNumber(
      row.assignment_score,
    ),
    acceptedAt: row.accepted_at,
    rejectedAt: row.rejected_at,
    firstResponseAt: row.first_response_at,
    completedAt: row.completed_at,
    unassignedAt: row.unassigned_at,
    reassignmentReason: row.reassignment_reason,
    assignmentReason: row.assignment_reason,
  };
}

function mapActivity(
  row: ActivityRow,
): LeadActivityItem {
  return {
    id: row.id,
    activityType: row.activity_type,
    direction: row.direction,
    status: row.activity_status,
    subject: row.subject,
    description: row.description,
    outcome: row.outcome,
    outcomeCode: row.outcome_code,
    channelProvider: row.channel_provider,
    externalActivityId: row.external_activity_id,
    durationSeconds: row.duration_seconds,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    performedBy: row.performed_by,
    isAutomated: row.is_automated,
    aiGenerated: row.ai_generated,
    aiSummary: row.ai_summary,
    aiSentiment: row.ai_sentiment,
    metadata: toJsonObject(row.metadata),
    createdAt: row.created_at,
  };
}

function mapStatusHistory(
  row: StatusHistoryRow,
): LeadStatusHistoryItem {
  return {
    id: row.id,
    previousStatus: row.previous_status,
    newStatus: row.new_status,
    previousLifecycleStage:
      row.previous_lifecycle_stage,
    newLifecycleStage: row.new_lifecycle_stage,
    previousTemperature: row.previous_temperature,
    newTemperature: row.new_temperature,
    changeReason: row.change_reason,
    changedBy: row.changed_by,
    metadata: toJsonObject(row.metadata),
    changedAt: row.changed_at,
  };
}

function mapFollowUp(
  row: FollowUpRow,
): LeadFollowUpItem {
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    followUpType: row.follow_up_type,
    status: row.status,
    priority: row.priority,

    assignedTo: row.assigned_to,
    assignedBy: row.assigned_by,
    assignedAt: row.assigned_at,

    dueAt: row.due_at,
    reminderAt: row.reminder_at,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    cancelledAt: row.cancelled_at,

    completionOutcome: row.completion_outcome,
    completionNotes: row.completion_notes,

    attemptCount: row.attempt_count,
    maximumAttempts: row.max_attempts,
    nextRetryAt: row.next_retry_at,

    isAutomated: row.is_automated,
    slaDueAt: row.sla_due_at,
    slaStatus: row.sla_status,
    escalationLevel: row.escalation_level,
    escalatedAt: row.escalated_at,

    metadata: toJsonObject(row.metadata),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapSiteVisit(
  row: SiteVisitRow,
): LeadSiteVisitItem {
  return {
    id: row.id,
    visitNumber: row.visit_number,
    title: row.title,
    description: row.description,

    visitType: row.visit_type,
    projectReferenceId: row.project_reference_id,
    projectName: row.project_name,
    developerName: row.developer_name,
    propertyName: row.property_name,
    propertyType: row.property_type,

    unitReference: row.unit_reference,
    unitType: row.unit_type,
    tower: row.tower,
    floor: row.floor,
    unitNumber: row.unit_number,

    visitAddress: row.visit_address,
    visitCity: row.visit_city,
    visitState: row.visit_state,
    landmark: row.landmark,
    locationUrl: row.location_url,

    status: row.status,
    confirmationStatus: row.confirmation_status,
    priority: row.priority,

    scheduledStartAt: row.scheduled_start_at,
    scheduledEndAt: row.scheduled_end_at,
    expectedDurationMinutes:
      row.expected_duration_minutes,
    timezone: row.timezone,

    assignedAgentId: row.assigned_agent_id,
    assignedAt: row.assigned_at,

    pickupRequired: row.pickup_required,
    pickupAddress: row.pickup_address,
    pickupTime: row.pickup_time,

    customerCheckedInAt:
      row.customer_checked_in_at,
    agentCheckedInAt: row.agent_checked_in_at,
    visitStartedAt: row.visit_started_at,
    visitCompletedAt: row.visit_completed_at,

    outcome: row.outcome,
    outcomeSummary: row.outcome_summary,
    customerFeedback: row.customer_feedback,
    agentNotes: row.agent_notes,

    customerRating: row.customer_rating,
    projectRating: row.project_rating,
    probabilityOfBooking: toNumber(
      row.probability_of_booking,
    ),
    expectedBookingDate:
      row.expected_booking_date,
    expectedBookingValue: toNumber(
      row.expected_booking_value,
    ),

    rescheduleCount: row.reschedule_count,
    cancellationReason: row.cancellation_reason,
    noShowParty: row.no_show_party,

    quotedPrice: toNumber(row.quoted_price),
    quotedCurrency: row.quoted_currency,
    discountDiscussed: toNumber(
      row.discount_discussed,
    ),
    paymentPlanDiscussed:
      row.payment_plan_discussed,
    bookingTokenDiscussed: toNumber(
      row.booking_token_discussed,
    ),

    amenitiesShown: toStringArray(
      row.amenities_shown,
    ),
    objections: toStringArray(row.objections),
    tags: toStringArray(row.tags),
    metadata: toJsonObject(row.metadata),

    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapAiCallAttempt(
  row: AiCallAttemptRow,
): LeadAiCallAttemptItem {
  return {
    id: row.id,
    callJobId: row.call_job_id,
    attemptNumber: row.attempt_number,
    status: row.status,
    dispositionCode: row.disposition_code,

    fromPhoneNumber: row.from_phone_number,
    toPhoneNumber: row.to_phone_number,

    errorCode: row.error_code,
    errorMessage: row.error_message,

    recordingUrl: row.recording_url,
    recordingDurationSeconds:
      row.recording_duration_seconds,
    callDurationSeconds: row.call_duration_seconds,
    ringDurationSeconds: row.ring_duration_seconds,

    providerCost: toNumber(row.provider_cost),
    providerCurrency: row.provider_currency,

    dispatchedAt: row.dispatched_at,
    initiatedAt: row.initiated_at,
    answeredAt: row.answered_at,
    endedAt: row.ended_at,
    completedAt: row.completed_at,

    createdAt: row.created_at,
  };
}

function mapAiTranscript(
  row: AiCallTranscriptRow,
): LeadAiCallTranscriptItem {
  return {
    id: row.id,
    callJobId: row.call_job_id,
    callAttemptId: row.call_attempt_id,
    transcriptStatus: row.transcript_status,
    languageCode: row.language_code,

    rawTranscript: row.raw_transcript,
    normalizedTranscript:
      row.normalized_transcript,
    summary: row.summary,

    sentiment: row.sentiment,
    sentimentScore: toNumber(row.sentiment_score),
    intentSummary: row.intent_summary,
    qualityScore: toNumber(row.quality_score),

    objections: toUnknownArray(row.objections),
    commitments: toUnknownArray(row.commitments),
    entities: toJsonObject(row.entities),
    complianceFlags: toUnknownArray(
      row.compliance_flags,
    ),

    reviewedAt: row.reviewed_at,
    reviewNotes: row.review_notes,
    createdAt: row.created_at,
  };
}

function mapAiQualification(
  row: AiQualificationRow,
): LeadAiQualificationItem {
  return {
    id: row.id,
    callJobId: row.call_job_id,
    callAttemptId: row.call_attempt_id,
    status: row.status,

    totalScore: toNumber(row.total_score) ?? 0,
    maximumScore:
      toNumber(row.maximum_score) ?? 0,
    normalizedScore:
      toNumber(row.normalized_score) ?? 0,

    validAnswerCount: row.valid_answer_count,
    requiredAnswerCount: row.required_answer_count,

    missingRequiredQuestions: toUnknownArray(
      row.missing_required_questions,
    ),
    disqualifyingReasons: toUnknownArray(
      row.disqualifying_reasons,
    ),

    qualificationSummary:
      row.qualification_summary,
    recommendedAction: row.recommended_action,
    recommendedFollowUpAt:
      row.recommended_followup_at,
    recommendedAgentId:
      row.recommended_agent_id,

    extractedProfile: toJsonObject(
      row.extracted_profile,
    ),
    scoringBreakdown: toJsonObject(
      row.scoring_breakdown,
    ),

    modelName: row.model_name,
    modelVersion: row.model_version,

    reviewStatus: row.review_status,
    reviewNotes: row.review_notes,
    reviewedAt: row.reviewed_at,

    createdAt: row.created_at,
  };
}

async function loadLeadSource(
  organizationId: string,
  sourceId: string | null,
): Promise<LeadSourceSummary | null> {
  if (!sourceId) {
    return null;
  }

  const supabase = await createClient();

  const { data, error } = await supabase
    .from("lead_sources")
    .select("id,name,code,source_type,provider")
    .eq("organization_id", organizationId)
    .eq("id", sourceId)
    .maybeSingle();

  if (error) {
    throw new Error(
      `Unable to load lead source: ${error.message}`,
    );
  }

  return data
    ? mapLeadSource(data as LeadSourceRow)
    : null;
}

async function loadValidation(
  organizationId: string,
  leadId: string,
): Promise<LeadValidationDetail | null> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("lead_validation_latest_results")
    .select(`
      id,
      validation_job_id,
      status,
      decision,
      authenticity_score,
      contactability_score,
      completeness_score,
      intent_score,
      source_quality_score,
      trust_score,
      duplicate_score,
      fraud_score,
      spam_score,
      passed_rule_count,
      failed_rule_count,
      warning_rule_count,
      blocking_rule_count,
      decision_reasons,
      risk_factors,
      quality_factors,
      duplicate_matches,
      blacklist_matches,
      suppression_matches,
      normalized_phone,
      normalized_email,
      detected_country_code,
      detected_region,
      detected_city,
      phone_valid,
      email_valid,
      consent_valid,
      source_valid,
      ai_call_eligibility,
      ai_call_block_reason,
      recommended_action,
      recommended_workflow_code,
      summary,
      manually_reviewed,
      review_decision,
      review_notes,
      reviewed_at,
      overridden,
      override_reason,
      overridden_at,
      created_at,
      updated_at
    `)
    .eq("organization_id", organizationId)
    .eq("lead_id", leadId)
    .order("created_at", {
      ascending: false,
      nullsFirst: false,
    })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(
      `Unable to load lead validation: ${error.message}`,
    );
  }

  return data
    ? mapValidation(data as ValidationRow)
    : null;
}

async function loadAssignment(
  organizationId: string,
  leadId: string,
): Promise<LeadAssignmentDetail | null> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("assignment_latest_active")
    .select(`
      id,
      team_id,
      agent_profile_id,
      assigned_user_id,
      assignment_type,
      strategy,
      status,
      priority,
      assignment_score,
      assigned_at,
      acceptance_due_at,
      response_due_at,
      accepted_at,
      rejected_at,
      first_response_at,
      completed_at,
      unassigned_at,
      reassignment_reason,
      assignment_reason
    `)
    .eq("organization_id", organizationId)
    .eq("lead_id", leadId)
    .order("assigned_at", {
      ascending: false,
      nullsFirst: false,
    })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(
      `Unable to load lead assignment: ${error.message}`,
    );
  }

  if (!data) {
    return null;
  }

  const assignment = data as AssignmentRow;

  let agent: AgentProfileRow | null = null;

  if (assignment.agent_profile_id) {
    const agentResult = await supabase
      .from("assignment_agent_profiles")
      .select("id,agent_code,display_name")
      .eq("organization_id", organizationId)
      .eq("id", assignment.agent_profile_id)
      .maybeSingle();

    if (agentResult.error) {
      throw new Error(
        `Unable to load assigned agent: ${agentResult.error.message}`,
      );
    }

    agent = agentResult.data
      ? (agentResult.data as AgentProfileRow)
      : null;
  }

  return mapAssignment(assignment, agent);
}

async function loadActivities(
  organizationId: string,
  leadId: string,
): Promise<LeadActivityItem[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("lead_activities")
    .select(`
      id,
      activity_type,
      direction,
      activity_status,
      subject,
      description,
      outcome,
      outcome_code,
      channel_provider,
      external_activity_id,
      duration_seconds,
      started_at,
      completed_at,
      performed_by,
      is_automated,
      ai_generated,
      ai_summary,
      ai_sentiment,
      metadata,
      created_at
    `)
    .eq("organization_id", organizationId)
    .eq("lead_id", leadId)
    .order("created_at", {
      ascending: false,
    })
    .limit(DETAIL_RECORD_LIMIT);

  if (error) {
    throw new Error(
      `Unable to load lead activities: ${error.message}`,
    );
  }

  return ((data ?? []) as ActivityRow[]).map(
    mapActivity,
  );
}

async function loadStatusHistory(
  organizationId: string,
  leadId: string,
): Promise<LeadStatusHistoryItem[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("lead_status_history")
    .select(`
      id,
      previous_status,
      new_status,
      previous_lifecycle_stage,
      new_lifecycle_stage,
      previous_temperature,
      new_temperature,
      change_reason,
      changed_by,
      metadata,
      changed_at
    `)
    .eq("organization_id", organizationId)
    .eq("lead_id", leadId)
    .order("changed_at", {
      ascending: false,
    })
    .limit(DETAIL_RECORD_LIMIT);

  if (error) {
    throw new Error(
      `Unable to load lead status history: ${error.message}`,
    );
  }

  return ((data ?? []) as StatusHistoryRow[]).map(
    mapStatusHistory,
  );
}

async function loadFollowUps(
  organizationId: string,
  leadId: string,
): Promise<LeadFollowUpItem[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("follow_up_tasks")
    .select(`
      id,
      title,
      description,
      follow_up_type,
      status,
      priority,
      assigned_to,
      assigned_by,
      assigned_at,
      due_at,
      reminder_at,
      started_at,
      completed_at,
      cancelled_at,
      completion_outcome,
      completion_notes,
      attempt_count,
      max_attempts,
      next_retry_at,
      is_automated,
      sla_due_at,
      sla_status,
      escalation_level,
      escalated_at,
      metadata,
      created_at,
      updated_at
    `)
    .eq("organization_id", organizationId)
    .eq("lead_id", leadId)
    .is("deleted_at", null)
    .order("due_at", {
      ascending: false,
    })
    .limit(DETAIL_RECORD_LIMIT);

  if (error) {
    throw new Error(
      `Unable to load follow-ups: ${error.message}`,
    );
  }

  return ((data ?? []) as FollowUpRow[]).map(
    mapFollowUp,
  );
}

async function loadSiteVisits(
  organizationId: string,
  leadId: string,
): Promise<LeadSiteVisitItem[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("site_visits")
    .select(`
      id,
      visit_number,
      title,
      description,
      visit_type,
      project_reference_id,
      project_name,
      developer_name,
      property_name,
      property_type,
      unit_reference,
      unit_type,
      tower,
      floor,
      unit_number,
      visit_address,
      visit_city,
      visit_state,
      landmark,
      location_url,
      status,
      confirmation_status,
      priority,
      scheduled_start_at,
      scheduled_end_at,
      expected_duration_minutes,
      timezone,
      assigned_agent_id,
      assigned_at,
      pickup_required,
      pickup_address,
      pickup_time,
      customer_checked_in_at,
      agent_checked_in_at,
      visit_started_at,
      visit_completed_at,
      outcome,
      outcome_summary,
      customer_feedback,
      agent_notes,
      customer_rating,
      project_rating,
      probability_of_booking,
      expected_booking_date,
      expected_booking_value,
      reschedule_count,
      cancellation_reason,
      no_show_party,
      quoted_price,
      quoted_currency,
      discount_discussed,
      payment_plan_discussed,
      booking_token_discussed,
      amenities_shown,
      objections,
      tags,
      metadata,
      created_at,
      updated_at
    `)
    .eq("organization_id", organizationId)
    .eq("lead_id", leadId)
    .is("deleted_at", null)
    .order("scheduled_start_at", {
      ascending: false,
    })
    .limit(DETAIL_RECORD_LIMIT);

  if (error) {
    throw new Error(
      `Unable to load site visits: ${error.message}`,
    );
  }

  return ((data ?? []) as SiteVisitRow[]).map(
    mapSiteVisit,
  );
}

async function loadAiCalls(
  organizationId: string,
  leadId: string,
): Promise<LeadAiCallJobItem[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("ai_call_jobs")
    .select(`
      id,
      campaign_id,
      status,
      priority,
      phone_number,
      contact_name,
      language_code,
      scheduled_at,
      expires_at,
      maximum_attempts,
      attempt_count,
      next_attempt_at,
      final_disposition_code,
      qualification_status,
      qualification_score,
      consent_status,
      blocked_reason,
      queued_at,
      started_at,
      completed_at,
      cancelled_at,
      cancellation_reason,
      result_data,
      error_data,
      metadata,
      created_at,
      updated_at
    `)
    .eq("organization_id", organizationId)
    .eq("lead_id", leadId)
    .order("created_at", {
      ascending: false,
    })
    .limit(DETAIL_RECORD_LIMIT);

  if (error) {
    throw new Error(
      `Unable to load AI call jobs: ${error.message}`,
    );
  }

  const jobRows = (data ?? []) as AiCallJobRow[];

  if (jobRows.length === 0) {
    return [];
  }

  const callJobIds = jobRows.map((job) => job.id);

  const [
    attemptsResult,
    transcriptsResult,
    qualificationResult,
  ] = await Promise.all([
    supabase
      .from("ai_call_attempts")
      .select(`
        id,
        call_job_id,
        attempt_number,
        status,
        disposition_code,
        from_phone_number,
        to_phone_number,
        error_code,
        error_message,
        recording_url,
        recording_duration_seconds,
        call_duration_seconds,
        ring_duration_seconds,
        provider_cost,
        provider_currency,
        dispatched_at,
        initiated_at,
        answered_at,
        ended_at,
        completed_at,
        created_at
      `)
      .eq("organization_id", organizationId)
      .in("call_job_id", callJobIds)
      .order("attempt_number", {
        ascending: false,
      }),

    supabase
      .from("ai_call_transcripts")
      .select(`
        id,
        call_job_id,
        call_attempt_id,
        transcript_status,
        language_code,
        raw_transcript,
        normalized_transcript,
        summary,
        sentiment,
        sentiment_score,
        intent_summary,
        quality_score,
        objections,
        commitments,
        entities,
        compliance_flags,
        reviewed_at,
        review_notes,
        created_at
      `)
      .eq("organization_id", organizationId)
      .in("call_job_id", callJobIds)
      .order("created_at", {
        ascending: false,
      }),

    supabase
      .from("ai_call_qualification_results")
      .select(`
        id,
        call_job_id,
        call_attempt_id,
        status,
        total_score,
        maximum_score,
        normalized_score,
        valid_answer_count,
        required_answer_count,
        missing_required_questions,
        disqualifying_reasons,
        qualification_summary,
        recommended_action,
        recommended_followup_at,
        recommended_agent_id,
        extracted_profile,
        scoring_breakdown,
        model_name,
        model_version,
        review_status,
        review_notes,
        reviewed_at,
        created_at
      `)
      .eq("organization_id", organizationId)
      .in("call_job_id", callJobIds)
      .order("created_at", {
        ascending: false,
      }),
  ]);

  if (attemptsResult.error) {
    throw new Error(
      `Unable to load AI call attempts: ${attemptsResult.error.message}`,
    );
  }

  if (transcriptsResult.error) {
    throw new Error(
      `Unable to load AI call transcripts: ${transcriptsResult.error.message}`,
    );
  }

  if (qualificationResult.error) {
    throw new Error(
      `Unable to load AI qualification results: ${qualificationResult.error.message}`,
    );
  }

  const attemptRows =
    (attemptsResult.data ?? []) as AiCallAttemptRow[];

  const transcriptRows =
    (transcriptsResult.data ??
      []) as AiCallTranscriptRow[];

  const qualificationRows =
    (qualificationResult.data ??
      []) as AiQualificationRow[];

  const attemptsByJobId = new Map<
    string,
    LeadAiCallAttemptItem[]
  >();

  const transcriptsByJobId = new Map<
    string,
    LeadAiCallTranscriptItem[]
  >();

  const qualificationsByJobId = new Map<
    string,
    LeadAiQualificationItem[]
  >();

  for (const row of attemptRows) {
    const mapped = mapAiCallAttempt(row);
    const existing =
      attemptsByJobId.get(row.call_job_id) ?? [];

    existing.push(mapped);
    attemptsByJobId.set(row.call_job_id, existing);
  }

  for (const row of transcriptRows) {
    const mapped = mapAiTranscript(row);
    const existing =
      transcriptsByJobId.get(row.call_job_id) ?? [];

    existing.push(mapped);
    transcriptsByJobId.set(
      row.call_job_id,
      existing,
    );
  }

  for (const row of qualificationRows) {
    const mapped = mapAiQualification(row);
    const existing =
      qualificationsByJobId.get(row.call_job_id) ??
      [];

    existing.push(mapped);
    qualificationsByJobId.set(
      row.call_job_id,
      existing,
    );
  }

  return jobRows.map((job) => ({
    id: job.id,
    campaignId: job.campaign_id,
    status: job.status,
    priority: job.priority,

    phoneNumber: job.phone_number,
    contactName: job.contact_name,
    languageCode: job.language_code,

    scheduledAt: job.scheduled_at,
    expiresAt: job.expires_at,

    maximumAttempts: job.maximum_attempts,
    attemptCount: job.attempt_count,
    nextAttemptAt: job.next_attempt_at,

    finalDispositionCode:
      job.final_disposition_code,
    qualificationStatus:
      job.qualification_status,
    qualificationScore: toNumber(
      job.qualification_score,
    ),

    consentStatus: job.consent_status,
    blockedReason: job.blocked_reason,

    queuedAt: job.queued_at,
    startedAt: job.started_at,
    completedAt: job.completed_at,
    cancelledAt: job.cancelled_at,
    cancellationReason:
      job.cancellation_reason,

    resultData: toJsonObject(job.result_data),
    errorData: toJsonObject(job.error_data),
    metadata: toJsonObject(job.metadata),

    attempts: attemptsByJobId.get(job.id) ?? [],
    transcripts:
      transcriptsByJobId.get(job.id) ?? [],
    qualificationResults:
      qualificationsByJobId.get(job.id) ?? [],

    createdAt: job.created_at,
    updatedAt: job.updated_at,
  }));
}

export async function getLeadDetail(
  organizationId: string,
  leadId: string,
  access: LeadDetailAccess,
): Promise<LeadDetailRecord | null> {
  const cleanOrganizationId = organizationId.trim();
  const cleanLeadId = leadId.trim();

  if (!cleanOrganizationId) {
    throw new Error(
      "Organization ID is required to load lead details.",
    );
  }

  if (!cleanLeadId) {
    throw new Error(
      "Lead ID is required to load lead details.",
    );
  }

  const supabase = await createClient();

  const { data, error } = await supabase
    .from("leads")
    .select(LEAD_DETAIL_SELECT)
    .eq("organization_id", cleanOrganizationId)
    .eq("id", cleanLeadId)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) {
    throw new Error(
      `Unable to load lead details: ${error.message}`,
    );
  }

  if (!data) {
    return null;
  }

  const lead = data as LeadDetailRow;

  const [
    source,
    validation,
    assignment,
    activities,
    statusHistory,
    followUps,
    siteVisits,
    aiCalls,
  ] = await Promise.all([
    loadLeadSource(
      cleanOrganizationId,
      lead.lead_source_id,
    ),

    access.canViewValidation
      ? loadValidation(
          cleanOrganizationId,
          cleanLeadId,
        )
      : Promise.resolve(null),

    access.canViewAssignment
      ? loadAssignment(
          cleanOrganizationId,
          cleanLeadId,
        )
      : Promise.resolve(null),

    loadActivities(
      cleanOrganizationId,
      cleanLeadId,
    ),

    loadStatusHistory(
      cleanOrganizationId,
      cleanLeadId,
    ),

    access.canViewFollowUps
      ? loadFollowUps(
          cleanOrganizationId,
          cleanLeadId,
        )
      : Promise.resolve([] as LeadFollowUpItem[]),

    access.canViewSiteVisits
      ? loadSiteVisits(
          cleanOrganizationId,
          cleanLeadId,
        )
      : Promise.resolve([] as LeadSiteVisitItem[]),

    access.canViewAiCalls
      ? loadAiCalls(
          cleanOrganizationId,
          cleanLeadId,
        )
      : Promise.resolve([] as LeadAiCallJobItem[]),
  ]);

  return {
    id: lead.id,
    organizationId: lead.organization_id,
    leadSourceId: lead.lead_source_id,

    firstName: lead.first_name,
    lastName: lead.last_name,
    fullName: getLeadDisplayName(lead),

    phone: lead.phone,
    normalizedPhone: lead.normalized_phone,
    alternatePhone: lead.alternate_phone,
    email: lead.email,
    normalizedEmail: lead.normalized_email,
    whatsappNumber: lead.whatsapp_number,
    countryCode: lead.country_code,

    leadStatus: lead.lead_status,
    leadTemperature: lead.lead_temperature,
    priority: lead.priority,
    lifecycleStage: lead.lifecycle_stage,

    propertyType: lead.property_type,
    transactionType: lead.transaction_type,
    preferredProject: lead.preferred_project,
    preferredLocation: lead.preferred_location,
    preferredCity: lead.preferred_city,
    unitType: lead.unit_type,
    bedrooms: toNumber(lead.bedrooms),

    budgetMin: toNumber(lead.budget_min),
    budgetMax: toNumber(lead.budget_max),
    budgetCurrency: lead.budget_currency,

    possessionTimeline:
      lead.possession_timeline,
    buyingTimeline: lead.buying_timeline,
    purpose: lead.purpose,
    financingRequired:
      lead.financing_required,
    loanStatus: lead.loan_status,

    qualificationStatus:
      lead.qualification_status,
    qualificationScore: toNumber(
      lead.qualification_score,
    ),
    qualificationReason:
      lead.qualification_reason,
    qualificationSummary:
      lead.qualification_summary,
    aiQualified: lead.ai_qualified,
    aiProvider: lead.ai_provider,
    aiModel: lead.ai_model,
    aiQualifiedAt: lead.ai_qualified_at,

    duplicateStatus: lead.duplicate_status,
    duplicateOfLeadId:
      lead.duplicate_of_lead_id,
    duplicateConfidence: toNumber(
      lead.duplicate_confidence,
    ),

    fakeStatus: lead.fake_status,
    fakeScore: toNumber(lead.fake_score),
    fakeReason: lead.fake_reason,

    phoneVerified: lead.phone_verified,
    emailVerified: lead.email_verified,
    whatsappVerified:
      lead.whatsapp_verified,

    consentStatus: lead.consent_status,
    consentSource: lead.consent_source,
    consentAt: lead.consent_at,

    doNotCall: lead.do_not_call,
    doNotEmail: lead.do_not_email,
    doNotWhatsapp: lead.do_not_whatsapp,

    preferredLanguage:
      lead.preferred_language,
    preferredContactChannel:
      lead.preferred_contact_channel,

    campaignId: lead.campaign_id,
    campaignName: lead.campaign_name,
    utmSource: lead.utm_source,
    utmMedium: lead.utm_medium,
    utmCampaign: lead.utm_campaign,
    utmTerm: lead.utm_term,
    utmContent: lead.utm_content,

    externalLeadId: lead.external_lead_id,
    externalProvider:
      lead.external_provider,
    metaLeadId: lead.meta_lead_id,
    googleLeadId: lead.google_lead_id,

    assignedTo: lead.assigned_to,
    assignedAt: lead.assigned_at,
    assignmentStatus:
      lead.assignment_status,

    firstContactedAt:
      lead.first_contacted_at,
    lastContactedAt:
      lead.last_contacted_at,
    nextFollowUpAt:
      lead.next_follow_up_at,
    qualifiedAt: lead.qualified_at,
    convertedAt: lead.converted_at,
    lostAt: lead.lost_at,
    lostReason: lead.lost_reason,

    notes: lead.notes,
    tags: toStringArray(lead.tags),
    customFields: toJsonObject(
      lead.custom_fields,
    ),
    metadata: toJsonObject(lead.metadata),

    source,
    validation,
    assignment,

    activities,
    statusHistory,
    followUps,
    siteVisits,
    aiCalls,

    createdAt: lead.created_at,
    updatedAt: lead.updated_at,
  };
}