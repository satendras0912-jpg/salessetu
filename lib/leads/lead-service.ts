import "server-only";

import { createClient } from "@/lib/supabase/server";
import type {
  LeadAssignmentSummary,
  LeadListFilters,
  LeadListItem,
  LeadListResult,
  LeadSourceSummary,
  LeadValidationSummary,
} from "@/types/leads";

type LeadRow = {
  id: string;
  organization_id: string;
  lead_source_id: string | null;

  first_name: string | null;
  last_name: string | null;
  full_name: string | null;

  phone: string | null;
  email: string | null;
  whatsapp_number: string | null;

  lead_status: string;
  lead_temperature: string | null;
  priority: string;
  lifecycle_stage: string;

  property_type: string | null;
  preferred_project: string | null;
  preferred_location: string | null;
  preferred_city: string | null;
  unit_type: string | null;

  budget_min: number | string | null;
  budget_max: number | string | null;
  budget_currency: string;

  qualification_status: string;
  qualification_score: number | string | null;
  ai_qualified: boolean;

  duplicate_status: string;
  duplicate_confidence: number | string | null;

  fake_status: string;
  fake_score: number | string | null;

  consent_status: string;

  campaign_name: string | null;
  utm_source: string | null;
  utm_medium: string | null;
  utm_campaign: string | null;

  assignment_status: string;
  assigned_to: string | null;
  assigned_at: string | null;
  next_follow_up_at: string | null;

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
  lead_id: string;
  status: string | null;
  decision: string | null;
  trust_score: number | string | null;
  authenticity_score: number | string | null;
  contactability_score: number | string | null;
  fraud_score: number | string | null;
  duplicate_score: number | string | null;
  spam_score: number | string | null;
  phone_valid: boolean | null;
  email_valid: boolean | null;
  consent_valid: boolean | null;
  ai_call_eligibility: string | null;
  ai_call_block_reason: string | null;
  recommended_action: string | null;
  summary: string | null;
};

type AssignmentRow = {
  id: string;
  lead_id: string;
  agent_profile_id: string | null;
  assigned_user_id: string | null;
  assignment_type: string | null;
  strategy: string | null;
  status: string | null;
  assigned_at: string | null;
  acceptance_due_at: string | null;
  response_due_at: string | null;
};

type AgentProfileRow = {
  id: string;
  agent_code: string;
  display_name: string;
};

const LEAD_SELECT = `
  id,
  organization_id,
  lead_source_id,
  first_name,
  last_name,
  full_name,
  phone,
  email,
  whatsapp_number,
  lead_status,
  lead_temperature,
  priority,
  lifecycle_stage,
  property_type,
  preferred_project,
  preferred_location,
  preferred_city,
  unit_type,
  budget_min,
  budget_max,
  budget_currency,
  qualification_status,
  qualification_score,
  ai_qualified,
  duplicate_status,
  duplicate_confidence,
  fake_status,
  fake_score,
  consent_status,
  campaign_name,
  utm_source,
  utm_medium,
  utm_campaign,
  assignment_status,
  assigned_to,
  assigned_at,
  next_follow_up_at,
  created_at,
  updated_at
`;

function toNumber(value: number | string | null): number | null {
  if (value === null || value === "") {
    return null;
  }

  const parsed = Number(value);

  return Number.isFinite(parsed) ? parsed : null;
}

function clampInteger(
  value: number | undefined,
  minimum: number,
  maximum: number,
  fallback: number,
): number {
  if (!Number.isInteger(value)) {
    return fallback;
  }

  return Math.min(Math.max(value as number, minimum), maximum);
}

function sanitiseSearchTerm(value: string): string {
  return value
    .trim()
    .replace(/[,%()"'\\]/g, " ")
    .replace(/\s+/g, " ")
    .slice(0, 100);
}

function getDisplayName(row: LeadRow): string {
  const explicitName = row.full_name?.trim();

  if (explicitName) {
    return explicitName;
  }

  const generatedName = [row.first_name, row.last_name]
    .filter((part): part is string => Boolean(part?.trim()))
    .join(" ")
    .trim();

  return generatedName || "Unnamed Lead";
}

function mapSource(row: LeadSourceRow): LeadSourceSummary {
  return {
    id: row.id,
    name: row.name,
    code: row.code,
    sourceType: row.source_type,
    provider: row.provider,
  };
}

function mapValidation(row: ValidationRow): LeadValidationSummary {
  return {
    status: row.status,
    decision: row.decision,
    trustScore: toNumber(row.trust_score),
    authenticityScore: toNumber(row.authenticity_score),
    contactabilityScore: toNumber(row.contactability_score),
    fraudScore: toNumber(row.fraud_score),
    duplicateScore: toNumber(row.duplicate_score),
    spamScore: toNumber(row.spam_score),
    phoneValid: row.phone_valid,
    emailValid: row.email_valid,
    consentValid: row.consent_valid,
    aiCallEligibility: row.ai_call_eligibility,
    aiCallBlockReason: row.ai_call_block_reason,
    recommendedAction: row.recommended_action,
    summary: row.summary,
  };
}

function mapAssignment(
  row: AssignmentRow,
  agent: AgentProfileRow | null,
): LeadAssignmentSummary {
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
  };
}

export async function getLeadList(
  organizationId: string,
  filters: LeadListFilters = {},
): Promise<LeadListResult> {
  const supabase = await createClient();

  const page = clampInteger(filters.page, 1, 100_000, 1);
  const pageSize = clampInteger(filters.pageSize, 10, 100, 25);

  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  let validationLeadIds: string[] | null = null;

  if (filters.validationDecision?.trim()) {
    const { data, error } = await supabase
      .from("lead_validation_latest_results")
      .select("lead_id")
      .eq("organization_id", organizationId)
      .eq("decision", filters.validationDecision.trim());

    if (error) {
      throw new Error(
        `Unable to filter leads by validation decision: ${error.message}`,
      );
    }

    validationLeadIds = Array.from(
      new Set(
        ((data ?? []) as Array<{ lead_id: string | null }>)
          .map((row) => row.lead_id)
          .filter((leadId): leadId is string => Boolean(leadId)),
      ),
    );

    if (validationLeadIds.length === 0) {
      return {
        items: [],
        total: 0,
        page,
        pageSize,
        totalPages: 0,
      };
    }
  }

  let query = supabase
    .from("leads")
    .select(LEAD_SELECT, {
      count: "exact",
    })
    .eq("organization_id", organizationId)
    .is("deleted_at", null)
    .order("created_at", {
      ascending: false,
    });

  const search = sanitiseSearchTerm(filters.search ?? "");

  if (search) {
    query = query.or(
      [
        `full_name.ilike.%${search}%`,
        `first_name.ilike.%${search}%`,
        `last_name.ilike.%${search}%`,
        `phone.ilike.%${search}%`,
        `normalized_phone.ilike.%${search}%`,
        `email.ilike.%${search}%`,
        `preferred_project.ilike.%${search}%`,
        `preferred_location.ilike.%${search}%`,
      ].join(","),
    );
  }

  if (filters.status?.trim()) {
    query = query.eq("lead_status", filters.status.trim());
  }

  if (filters.assignmentStatus?.trim()) {
    query = query.eq(
      "assignment_status",
      filters.assignmentStatus.trim(),
    );
  }

  if (filters.sourceId?.trim()) {
    query = query.eq("lead_source_id", filters.sourceId.trim());
  }

  if (validationLeadIds) {
    query = query.in("id", validationLeadIds);
  }

  const {
    data: leadData,
    error: leadError,
    count,
  } = await query.range(from, to);

  if (leadError) {
    throw new Error(`Unable to load leads: ${leadError.message}`);
  }

  const leadRows = (leadData ?? []) as LeadRow[];

  if (leadRows.length === 0) {
    return {
      items: [],
      total: count ?? 0,
      page,
      pageSize,
      totalPages: 0,
    };
  }

  const leadIds = leadRows.map((lead) => lead.id);

  const sourceIds = Array.from(
    new Set(
      leadRows
        .map((lead) => lead.lead_source_id)
        .filter((sourceId): sourceId is string => Boolean(sourceId)),
    ),
  );

  const sourcePromise =
    sourceIds.length > 0
      ? supabase
          .from("lead_sources")
          .select("id,name,code,source_type,provider")
          .eq("organization_id", organizationId)
          .in("id", sourceIds)
      : Promise.resolve({
          data: [] as LeadSourceRow[],
          error: null,
        });

  const validationPromise = supabase
    .from("lead_validation_latest_results")
    .select(
      `
        lead_id,
        status,
        decision,
        trust_score,
        authenticity_score,
        contactability_score,
        fraud_score,
        duplicate_score,
        spam_score,
        phone_valid,
        email_valid,
        consent_valid,
        ai_call_eligibility,
        ai_call_block_reason,
        recommended_action,
        summary
      `,
    )
    .eq("organization_id", organizationId)
    .in("lead_id", leadIds);

  const assignmentPromise = supabase
    .from("assignment_latest_active")
    .select(
      `
        id,
        lead_id,
        agent_profile_id,
        assigned_user_id,
        assignment_type,
        strategy,
        status,
        assigned_at,
        acceptance_due_at,
        response_due_at
      `,
    )
    .eq("organization_id", organizationId)
    .in("lead_id", leadIds);

  const [
    sourceResult,
    validationResult,
    assignmentResult,
  ] = await Promise.all([
    sourcePromise,
    validationPromise,
    assignmentPromise,
  ]);

  if (sourceResult.error) {
    throw new Error(
      `Unable to load lead sources: ${sourceResult.error.message}`,
    );
  }

  if (validationResult.error) {
    throw new Error(
      `Unable to load validation results: ${validationResult.error.message}`,
    );
  }

  if (assignmentResult.error) {
    throw new Error(
      `Unable to load lead assignments: ${assignmentResult.error.message}`,
    );
  }

  const sourceRows = (sourceResult.data ?? []) as LeadSourceRow[];
  const validationRows = (validationResult.data ?? []) as ValidationRow[];
  const assignmentRows = (assignmentResult.data ?? []) as AssignmentRow[];

  const agentProfileIds = Array.from(
    new Set(
      assignmentRows
        .map((assignment) => assignment.agent_profile_id)
        .filter((agentId): agentId is string => Boolean(agentId)),
    ),
  );

  let agentRows: AgentProfileRow[] = [];

  if (agentProfileIds.length > 0) {
    const { data, error } = await supabase
      .from("assignment_agent_profiles")
      .select("id,agent_code,display_name")
      .eq("organization_id", organizationId)
      .in("id", agentProfileIds);

    if (error) {
      throw new Error(
        `Unable to load assignment agents: ${error.message}`,
      );
    }

    agentRows = (data ?? []) as AgentProfileRow[];
  }

  const sourceById = new Map(
    sourceRows.map((source) => [source.id, source]),
  );

  const validationByLeadId = new Map(
    validationRows.map((validation) => [
      validation.lead_id,
      validation,
    ]),
  );

  const assignmentByLeadId = new Map(
    assignmentRows.map((assignment) => [
      assignment.lead_id,
      assignment,
    ]),
  );

  const agentById = new Map(
    agentRows.map((agent) => [agent.id, agent]),
  );

  const items: LeadListItem[] = leadRows.map((lead) => {
    const source = lead.lead_source_id
      ? sourceById.get(lead.lead_source_id) ?? null
      : null;

    const validation =
      validationByLeadId.get(lead.id) ?? null;

    const assignment =
      assignmentByLeadId.get(lead.id) ?? null;

    const agent =
      assignment?.agent_profile_id
        ? agentById.get(assignment.agent_profile_id) ?? null
        : null;

    return {
      id: lead.id,
      organizationId: lead.organization_id,

      fullName: getDisplayName(lead),
      firstName: lead.first_name,
      lastName: lead.last_name,

      phone: lead.phone,
      email: lead.email,
      whatsappNumber: lead.whatsapp_number,

      leadStatus: lead.lead_status,
      leadTemperature: lead.lead_temperature,
      priority: lead.priority,
      lifecycleStage: lead.lifecycle_stage,

      preferredProject: lead.preferred_project,
      preferredLocation: lead.preferred_location,
      preferredCity: lead.preferred_city,
      propertyType: lead.property_type,
      unitType: lead.unit_type,

      budgetMin: toNumber(lead.budget_min),
      budgetMax: toNumber(lead.budget_max),
      budgetCurrency: lead.budget_currency,

      qualificationStatus: lead.qualification_status,
      qualificationScore: toNumber(lead.qualification_score),
      aiQualified: lead.ai_qualified,

      duplicateStatus: lead.duplicate_status,
      duplicateConfidence: toNumber(
        lead.duplicate_confidence,
      ),

      fakeStatus: lead.fake_status,
      fakeScore: toNumber(lead.fake_score),

      consentStatus: lead.consent_status,

      campaignName: lead.campaign_name,
      utmSource: lead.utm_source,
      utmMedium: lead.utm_medium,
      utmCampaign: lead.utm_campaign,

      assignmentStatus: lead.assignment_status,
      assignedTo: lead.assigned_to,
      assignedAt: lead.assigned_at,
      nextFollowUpAt: lead.next_follow_up_at,

      createdAt: lead.created_at,
      updatedAt: lead.updated_at,

      source: source ? mapSource(source) : null,
      validation: validation
        ? mapValidation(validation)
        : null,
      assignment: assignment
        ? mapAssignment(assignment, agent)
        : null,
    };
  });

  const total = count ?? 0;

  return {
    items,
    total,
    page,
    pageSize,
    totalPages:
      total === 0 ? 0 : Math.ceil(total / pageSize),
  };
}

export async function getLeadSources(
  organizationId: string,
): Promise<LeadSourceSummary[]> {
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("lead_sources")
    .select("id,name,code,source_type,provider")
    .eq("organization_id", organizationId)
    .eq("is_active", true)
    .order("name", {
      ascending: true,
    });

  if (error) {
    throw new Error(
      `Unable to load lead sources: ${error.message}`,
    );
  }

  return ((data ?? []) as LeadSourceRow[]).map(mapSource);
}