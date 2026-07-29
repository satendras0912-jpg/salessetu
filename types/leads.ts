export type LeadListFilters = {
  search?: string;
  status?: string;
  assignmentStatus?: string;
  validationDecision?: string;
  sourceId?: string;
  page?: number;
  pageSize?: number;
};

export type LeadSourceSummary = {
  id: string;
  name: string;
  code: string;
  sourceType: string;
  provider: string | null;
};

export type LeadValidationSummary = {
  status: string | null;
  decision: string | null;
  trustScore: number | null;
  authenticityScore: number | null;
  contactabilityScore: number | null;
  fraudScore: number | null;
  duplicateScore: number | null;
  spamScore: number | null;
  phoneValid: boolean | null;
  emailValid: boolean | null;
  consentValid: boolean | null;
  aiCallEligibility: string | null;
  aiCallBlockReason: string | null;
  recommendedAction: string | null;
  summary: string | null;
};

export type LeadAssignmentSummary = {
  assignmentId: string;
  status: string | null;
  assignmentType: string | null;
  strategy: string | null;
  agentProfileId: string | null;
  assignedUserId: string | null;
  agentName: string | null;
  agentCode: string | null;
  assignedAt: string | null;
  acceptanceDueAt: string | null;
  responseDueAt: string | null;
};

export type LeadListItem = {
  id: string;
  organizationId: string;

  fullName: string;
  firstName: string | null;
  lastName: string | null;

  phone: string | null;
  email: string | null;
  whatsappNumber: string | null;

  leadStatus: string;
  leadTemperature: string | null;
  priority: string;
  lifecycleStage: string;

  preferredProject: string | null;
  preferredLocation: string | null;
  preferredCity: string | null;
  propertyType: string | null;
  unitType: string | null;

  budgetMin: number | null;
  budgetMax: number | null;
  budgetCurrency: string;

  qualificationStatus: string;
  qualificationScore: number | null;
  aiQualified: boolean;

  duplicateStatus: string;
  duplicateConfidence: number | null;

  fakeStatus: string;
  fakeScore: number | null;

  consentStatus: string;

  campaignName: string | null;
  utmSource: string | null;
  utmMedium: string | null;
  utmCampaign: string | null;

  assignmentStatus: string;
  assignedTo: string | null;
  assignedAt: string | null;
  nextFollowUpAt: string | null;

  createdAt: string;
  updatedAt: string;

  source: LeadSourceSummary | null;
  validation: LeadValidationSummary | null;
  assignment: LeadAssignmentSummary | null;
};

export type LeadListResult = {
  items: LeadListItem[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
};