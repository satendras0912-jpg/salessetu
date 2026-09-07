import "server-only";

import { createClient } from "@/lib/supabase/server";

import type {
  LeadOperationalDataAccess,
} from "@/types/lead-operational-access";

import type {
  AssignmentAgentOption,
  AssignmentTeamOption,
  FollowUpTaskSummary,
  LeadAssignmentSummary,
  LeadOperationalSnapshot,
  OrganizationMemberOption,
  SiteVisitSummary,
} from "@/types/lead-operational-controls";

type LeadOperationalRow = {
  id: string;
  updated_at: string;

  lead_status: string;
  lifecycle_stage: string;
  lead_temperature: string | null;

  assignment_status: string;
  assigned_to: string | null;
  assigned_team_id: string | null;
};

type AssignmentAgentRow = {
  id: string;
  user_id: string;

  agent_code: string | null;
  display_name: string | null;

  status: string;
  availability_status: string;

  current_open_leads: number | string;
  maximum_open_leads: number | string;

  accept_new_leads: boolean;
};

type AssignmentTeamRow = {
  id: string;

  team_code: string;
  team_name: string;

  team_type: string;
  status: string;

  maximum_open_leads: number | string | null;
};

type LeadAssignmentRow = {
  id: string;
  lead_id: string;

  team_id: string | null;
  agent_profile_id: string;
  assigned_user_id: string;

  assignment_type: string;
  strategy: string;
  status: string;

  assignment_reason: string | null;
  reassignment_reason: string | null;

  assigned_at: string;
  acceptance_due_at: string | null;
  response_due_at: string | null;

  accepted_at: string | null;
  rejected_at: string | null;
  first_response_at: string | null;
  completed_at: string | null;
  unassigned_at: string | null;

  updated_at: string;
};

type FollowUpTaskRow = {
  id: string;
  lead_id: string;

  title: string;
  description: string | null;

  follow_up_type: string;
  status: string;
  priority: string;

  assigned_to: string | null;

  due_at: string;
  reminder_at: string | null;

  sla_due_at: string | null;
  sla_status: string;

  started_at: string | null;
  completed_at: string | null;
  cancelled_at: string | null;

  completion_outcome: string | null;
  completion_notes: string | null;

  escalation_level: number | string;
  escalated_at: string | null;
  escalated_to: string | null;

  created_at: string;
  updated_at: string;
};

type SiteVisitRow = {
  id: string;
  lead_id: string;

  title: string;
  description: string | null;

  visit_type: string;
  status: string;
  confirmation_status: string;
  priority: string;

  project_name: string;
  developer_name: string | null;
  property_name: string | null;
  unit_type: string | null;

  visit_address: string | null;
  visit_city: string | null;
  location_url: string | null;

  scheduled_start_at: string;
  scheduled_end_at: string | null;
  timezone: string;

  assigned_agent_id: string | null;
  coordinator_id: string | null;

  customer_checked_in_at: string | null;
  agent_checked_in_at: string | null;
  customer_checked_out_at: string | null;
  agent_checked_out_at: string | null;

  outcome: string | null;
  outcome_summary: string | null;
  agent_notes: string | null;

  probability_of_booking:
    | number
    | string
    | null;

  cancellation_reason: string | null;

  created_at: string;
  updated_at: string;
};

export type LeadOperationalContext = {
  snapshot: LeadOperationalSnapshot;

  agents: AssignmentAgentOption[];
  teams: AssignmentTeamOption[];
  members: OrganizationMemberOption[];

  currentAssignment: LeadAssignmentSummary | null;

  followUps: FollowUpTaskSummary[];
  siteVisits: SiteVisitSummary[];
};

const LEAD_OPERATIONAL_SELECT = `
  id,
  updated_at,
  lead_status,
  lifecycle_stage,
  lead_temperature,
  assignment_status,
  assigned_to,
  assigned_team_id
`;

const ASSIGNMENT_AGENT_SELECT = `
  id,
  user_id,
  agent_code,
  display_name,
  status,
  availability_status,
  current_open_leads,
  maximum_open_leads,
  accept_new_leads
`;

const ASSIGNMENT_TEAM_SELECT = `
  id,
  team_code,
  team_name,
  team_type,
  status,
  maximum_open_leads
`;

const LEAD_ASSIGNMENT_SELECT = `
  id,
  lead_id,
  team_id,
  agent_profile_id,
  assigned_user_id,
  assignment_type,
  strategy,
  status,
  assignment_reason,
  reassignment_reason,
  assigned_at,
  acceptance_due_at,
  response_due_at,
  accepted_at,
  rejected_at,
  first_response_at,
  completed_at,
  unassigned_at,
  updated_at
`;

const FOLLOW_UP_SELECT = `
  id,
  lead_id,
  title,
  description,
  follow_up_type,
  status,
  priority,
  assigned_to,
  due_at,
  reminder_at,
  sla_due_at,
  sla_status,
  started_at,
  completed_at,
  cancelled_at,
  completion_outcome,
  completion_notes,
  escalation_level,
  escalated_at,
  escalated_to,
  created_at,
  updated_at
`;

const SITE_VISIT_SELECT = `
  id,
  lead_id,
  title,
  description,
  visit_type,
  status,
  confirmation_status,
  priority,
  project_name,
  developer_name,
  property_name,
  unit_type,
  visit_address,
  visit_city,
  location_url,
  scheduled_start_at,
  scheduled_end_at,
  timezone,
  assigned_agent_id,
  coordinator_id,
  customer_checked_in_at,
  agent_checked_in_at,
  customer_checked_out_at,
  agent_checked_out_at,
  outcome,
  outcome_summary,
  agent_notes,
  probability_of_booking,
  cancellation_reason,
  created_at,
  updated_at
`;

function normalizeIdentifier(
  value: string,
): string {
  return value.trim();
}

function toFiniteNumber(
  value: number | string | null | undefined,
  fallback = 0,
): number {
  if (
    value === null ||
    value === undefined ||
    value === ""
  ) {
    return fallback;
  }

  const parsedValue = Number(value);

  return Number.isFinite(parsedValue)
    ? parsedValue
    : fallback;
}

function toNullableNumber(
  value: number | string | null,
): number | null {
  if (value === null || value === "") {
    return null;
  }

  const parsedValue = Number(value);

  return Number.isFinite(parsedValue)
    ? parsedValue
    : null;
}

function getAgentDisplayName(
  row: AssignmentAgentRow,
): string {
  const displayName = row.display_name?.trim();

  if (displayName) {
    return displayName;
  }

  const agentCode = row.agent_code?.trim();

  if (agentCode) {
    return agentCode;
  }

  return `Agent ${row.user_id.slice(0, 8)}`;
}

function mapLeadSnapshot(
  row: LeadOperationalRow,
): LeadOperationalSnapshot {
  return {
    leadId: row.id,
    updatedAt: row.updated_at,

    leadStatus:
      row.lead_status as LeadOperationalSnapshot["leadStatus"],

    lifecycleStage:
      row.lifecycle_stage as LeadOperationalSnapshot["lifecycleStage"],

    leadTemperature:
      row.lead_temperature as LeadOperationalSnapshot["leadTemperature"],

    assignmentStatus:
      row.assignment_status,

    assignedTo:
      row.assigned_to,

    assignedTeamId:
      row.assigned_team_id,
  };
}

function mapAssignmentAgent(
  row: AssignmentAgentRow,
): AssignmentAgentOption {
  return {
    profileId: row.id,
    userId: row.user_id,

    agentCode: row.agent_code,
    displayName: getAgentDisplayName(row),

    status: row.status,
    availabilityStatus:
      row.availability_status,

    currentOpenLeads: toFiniteNumber(
      row.current_open_leads,
    ),

    maximumOpenLeads: toFiniteNumber(
      row.maximum_open_leads,
    ),

    acceptNewLeads:
      row.accept_new_leads,
  };
}

function mapAssignmentTeam(
  row: AssignmentTeamRow,
): AssignmentTeamOption {
  return {
    id: row.id,
    code: row.team_code,
    name: row.team_name,

    teamType: row.team_type,
    status: row.status,

    maximumOpenLeads:
      row.maximum_open_leads === null
        ? null
        : toFiniteNumber(
            row.maximum_open_leads,
          ),
  };
}

function mapOrganizationMembers(
  agents: AssignmentAgentOption[],
): OrganizationMemberOption[] {
  const members = new Map<
    string,
    OrganizationMemberOption
  >();

  for (const agent of agents) {
    if (members.has(agent.userId)) {
      continue;
    }

    members.set(agent.userId, {
      userId: agent.userId,
      displayName: agent.displayName,
      email: null,
    });
  }

  return Array.from(members.values()).sort(
    (leftMember, rightMember) =>
      leftMember.displayName.localeCompare(
        rightMember.displayName,
        "en-IN",
      ),
  );
}

function mapLeadAssignment(
  row: LeadAssignmentRow,
): LeadAssignmentSummary {
  return {
    id: row.id,
    leadId: row.lead_id,

    teamId: row.team_id,
    agentProfileId:
      row.agent_profile_id,
    assignedUserId:
      row.assigned_user_id,

    assignmentType:
      row.assignment_type,
    strategy: row.strategy,
    status: row.status,

    assignmentReason:
      row.assignment_reason,

    reassignmentReason:
      row.reassignment_reason,

    assignedAt:
      row.assigned_at,

    acceptanceDueAt:
      row.acceptance_due_at,

    responseDueAt:
      row.response_due_at,

    acceptedAt:
      row.accepted_at,

    rejectedAt:
      row.rejected_at,

    firstResponseAt:
      row.first_response_at,

    completedAt:
      row.completed_at,

    unassignedAt:
      row.unassigned_at,

    updatedAt:
      row.updated_at,
  };
}

function mapFollowUpTask(
  row: FollowUpTaskRow,
): FollowUpTaskSummary {
  return {
    id: row.id,
    leadId: row.lead_id,

    title: row.title,
    description: row.description,

    followUpType:
      row.follow_up_type as FollowUpTaskSummary["followUpType"],

    status:
      row.status as FollowUpTaskSummary["status"],

    priority:
      row.priority as FollowUpTaskSummary["priority"],

    assignedTo:
      row.assigned_to,

    dueAt:
      row.due_at,

    reminderAt:
      row.reminder_at,

    slaDueAt:
      row.sla_due_at,

    slaStatus:
      row.sla_status as FollowUpTaskSummary["slaStatus"],

    startedAt:
      row.started_at,

    completedAt:
      row.completed_at,

    cancelledAt:
      row.cancelled_at,

    completionOutcome:
      row.completion_outcome,

    completionNotes:
      row.completion_notes,

    escalationLevel: toFiniteNumber(
      row.escalation_level,
    ),

    escalatedAt:
      row.escalated_at,

    escalatedTo:
      row.escalated_to,

    createdAt:
      row.created_at,

    updatedAt:
      row.updated_at,
  };
}

function mapSiteVisit(
  row: SiteVisitRow,
): SiteVisitSummary {
  return {
    id: row.id,
    leadId: row.lead_id,

    title: row.title,
    description: row.description,

    visitType:
      row.visit_type as SiteVisitSummary["visitType"],

    status:
      row.status as SiteVisitSummary["status"],

    confirmationStatus:
      row.confirmation_status as SiteVisitSummary["confirmationStatus"],

    priority:
      row.priority as SiteVisitSummary["priority"],

    projectName:
      row.project_name,

    developerName:
      row.developer_name,

    propertyName:
      row.property_name,

    unitType:
      row.unit_type,

    visitAddress:
      row.visit_address,

    visitCity:
      row.visit_city,

    locationUrl:
      row.location_url,

    scheduledStartAt:
      row.scheduled_start_at,

    scheduledEndAt:
      row.scheduled_end_at,

    timezone:
      row.timezone,

    assignedAgentId:
      row.assigned_agent_id,

    coordinatorId:
      row.coordinator_id,

    customerCheckedInAt:
      row.customer_checked_in_at,

    agentCheckedInAt:
      row.agent_checked_in_at,

    customerCheckedOutAt:
      row.customer_checked_out_at,

    agentCheckedOutAt:
      row.agent_checked_out_at,

    outcome:
      row.outcome as SiteVisitSummary["outcome"],

    outcomeSummary:
      row.outcome_summary,

    agentNotes:
      row.agent_notes,

    probabilityOfBooking:
      toNullableNumber(
        row.probability_of_booking,
      ),

    cancellationReason:
      row.cancellation_reason,

    createdAt:
      row.created_at,

    updatedAt:
      row.updated_at,
  };
}

async function loadAssignmentData(
  organizationId: string,
  leadId: string,
): Promise<{
  agents: AssignmentAgentOption[];
  teams: AssignmentTeamOption[];
  members: OrganizationMemberOption[];
  currentAssignment:
    | LeadAssignmentSummary
    | null;
}> {
  const supabase =
    await createClient();

  const [
    agentResult,
    teamResult,
    assignmentResult,
  ] = await Promise.all([
    supabase
      .from("assignment_agent_profiles")
      .select(ASSIGNMENT_AGENT_SELECT)
      .eq(
        "organization_id",
        organizationId,
      )
      .eq("status", "active")
      .order("display_name", {
        ascending: true,
        nullsFirst: false,
      }),

    supabase
      .from("assignment_teams")
      .select(ASSIGNMENT_TEAM_SELECT)
      .eq(
        "organization_id",
        organizationId,
      )
      .eq("status", "active")
      .order("team_name", {
        ascending: true,
      }),

    supabase
      .from("lead_assignments")
      .select(LEAD_ASSIGNMENT_SELECT)
      .eq(
        "organization_id",
        organizationId,
      )
      .eq("lead_id", leadId)
      .in("status", [
        "assigned",
        "accepted",
        "active",
      ])
      .order("assigned_at", {
        ascending: false,
      })
      .limit(1)
      .maybeSingle(),
  ]);

  if (agentResult.error) {
    throw new Error(
      `Unable to load assignment agents: ${agentResult.error.message}`,
    );
  }

  if (teamResult.error) {
    throw new Error(
      `Unable to load assignment teams: ${teamResult.error.message}`,
    );
  }

  if (assignmentResult.error) {
    throw new Error(
      `Unable to load current assignment: ${assignmentResult.error.message}`,
    );
  }

  const agentRows =
    (agentResult.data ??
      []) as unknown as AssignmentAgentRow[];

  const teamRows =
    (teamResult.data ??
      []) as unknown as AssignmentTeamRow[];

  const agents = agentRows
    .map(mapAssignmentAgent)
    .sort(
      (leftAgent, rightAgent) =>
        leftAgent.displayName.localeCompare(
          rightAgent.displayName,
          "en-IN",
        ),
    );

  const teams = teamRows.map(
    mapAssignmentTeam,
  );

  const currentAssignment =
    assignmentResult.data
      ? mapLeadAssignment(
          assignmentResult.data as unknown as LeadAssignmentRow,
        )
      : null;

  return {
    agents,
    teams,
    members:
      mapOrganizationMembers(agents),
    currentAssignment,
  };
}

async function loadFollowUps(
  organizationId: string,
  leadId: string,
): Promise<FollowUpTaskSummary[]> {
  const supabase =
    await createClient();

  const { data, error } =
    await supabase
      .from("follow_up_tasks")
      .select(FOLLOW_UP_SELECT)
      .eq(
        "organization_id",
        organizationId,
      )
      .eq("lead_id", leadId)
      .is("deleted_at", null)
      .order("due_at", {
        ascending: true,
      })
      .limit(50);

  if (error) {
    throw new Error(
      `Unable to load follow-up tasks: ${error.message}`,
    );
  }

  return (
    (data ??
      []) as unknown as FollowUpTaskRow[]
  ).map(mapFollowUpTask);
}

async function loadSiteVisits(
  organizationId: string,
  leadId: string,
): Promise<SiteVisitSummary[]> {
  const supabase =
    await createClient();

  const { data, error } =
    await supabase
      .from("site_visits")
      .select(SITE_VISIT_SELECT)
      .eq(
        "organization_id",
        organizationId,
      )
      .eq("lead_id", leadId)
      .is("deleted_at", null)
      .order("scheduled_start_at", {
        ascending: false,
      })
      .limit(50);

  if (error) {
    throw new Error(
      `Unable to load site visits: ${error.message}`,
    );
  }

  return (
    (data ??
      []) as unknown as SiteVisitRow[]
  ).map(mapSiteVisit);
}

export async function getLeadOperationalContext(
  organizationId: string,
  leadId: string,
  access: LeadOperationalDataAccess,
): Promise<LeadOperationalContext | null> {
  const cleanOrganizationId =
    normalizeIdentifier(organizationId);

  const cleanLeadId =
    normalizeIdentifier(leadId);

  if (
    !cleanOrganizationId ||
    !cleanLeadId
  ) {
    return null;
  }

  const supabase =
    await createClient();

  const {
    data: leadData,
    error: leadError,
  } = await supabase
    .from("leads")
    .select(LEAD_OPERATIONAL_SELECT)
    .eq(
      "organization_id",
      cleanOrganizationId,
    )
    .eq("id", cleanLeadId)
    .is("deleted_at", null)
    .maybeSingle();

  if (leadError) {
    throw new Error(
      `Unable to load lead operational snapshot: ${leadError.message}`,
    );
  }

  if (!leadData) {
    return null;
  }

  const [
    assignmentData,
    followUps,
    siteVisits,
  ] = await Promise.all([
    access.canViewAssignments
      ? loadAssignmentData(
          cleanOrganizationId,
          cleanLeadId,
        )
      : Promise.resolve({
          agents: [],
          teams: [],
          members: [],
          currentAssignment: null,
        }),

    access.canViewFollowUps
      ? loadFollowUps(
          cleanOrganizationId,
          cleanLeadId,
        )
      : Promise.resolve([]),

    access.canViewSiteVisits
      ? loadSiteVisits(
          cleanOrganizationId,
          cleanLeadId,
        )
      : Promise.resolve([]),
  ]);

  return {
    snapshot: mapLeadSnapshot(
      leadData as unknown as LeadOperationalRow,
    ),

    agents:
      assignmentData.agents,

    teams:
      assignmentData.teams,

    members:
      assignmentData.members,

    currentAssignment:
      assignmentData.currentAssignment,

    followUps,
    siteVisits,
  };
}