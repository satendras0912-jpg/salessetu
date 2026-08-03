import "server-only";

import { createClient } from "@/lib/supabase/server";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

type AssignmentErrorShape = {
  code?: string | null;
  message?: string | null;
};

export type LeadAssignmentServiceResult =
  | {
      ok: true;
    }
  | {
      ok: false;
      code:
        | "validation"
        | "not_found"
        | "permission_denied"
        | "conflict"
        | "capacity_reached"
        | "agent_unavailable"
        | "database_error";
      message: string;
    };

export type ManualLeadAssignmentInput = {
  leadId: string;
  agentProfileId: string;
  teamId?: string | null;
  reason?: string | null;
  overrideCapacity?: boolean;
};

export type ManualLeadUnassignmentInput = {
  leadId: string;
  reason?: string | null;
};

function normalizeOptionalText(
  value: string | null | undefined,
): string | null {
  const normalized = value?.trim();

  return normalized ? normalized : null;
}

function isValidUuid(value: string): boolean {
  return UUID_PATTERN.test(value);
}

function mapAssignmentError(
  error: AssignmentErrorShape,
): LeadAssignmentServiceResult {
  const databaseCode = error.code ?? "";
  const databaseMessage =
    error.message?.trim() || "The assignment request could not be completed.";

  const normalizedMessage = databaseMessage.toLowerCase();

  if (databaseCode === "42501") {
    return {
      ok: false,
      code: "permission_denied",
      message:
        "You do not have permission to change this lead assignment.",
    };
  }

  if (
    databaseCode === "23505" ||
    normalizedMessage.includes("already assigned") ||
    normalizedMessage.includes("active assignment already exists")
  ) {
    return {
      ok: false,
      code: "conflict",
      message:
        "This lead already has an active assignment. Reload the latest lead details before trying again.",
    };
  }

  if (
    normalizedMessage.includes("capacity") ||
    normalizedMessage.includes("maximum open leads") ||
    normalizedMessage.includes("daily assignment limit")
  ) {
    return {
      ok: false,
      code: "capacity_reached",
      message:
        "The selected agent has reached the configured assignment capacity.",
    };
  }

  if (
    normalizedMessage.includes("unavailable") ||
    normalizedMessage.includes("inactive agent") ||
    normalizedMessage.includes("not accepting new leads")
  ) {
    return {
      ok: false,
      code: "agent_unavailable",
      message:
        "The selected agent is currently unavailable for new lead assignments.",
    };
  }

  if (
    databaseCode === "P0002" ||
    normalizedMessage.includes("not found") ||
    normalizedMessage.includes("does not exist")
  ) {
    return {
      ok: false,
      code: "not_found",
      message:
        "The lead, agent profile, or assignment team could not be found.",
    };
  }

  return {
    ok: false,
    code: "database_error",
    message: databaseMessage,
  };
}

export async function manuallyAssignLead(
  input: ManualLeadAssignmentInput,
): Promise<LeadAssignmentServiceResult> {
  const leadId = input.leadId.trim();
  const agentProfileId = input.agentProfileId.trim();
  const teamId = normalizeOptionalText(input.teamId);
  const reason =
    normalizeOptionalText(input.reason) ?? "Manual assignment";

  if (!isValidUuid(leadId)) {
    return {
      ok: false,
      code: "validation",
      message: "A valid lead ID is required.",
    };
  }

  if (!isValidUuid(agentProfileId)) {
    return {
      ok: false,
      code: "validation",
      message: "Select a valid agent before assigning the lead.",
    };
  }

  if (teamId && !isValidUuid(teamId)) {
    return {
      ok: false,
      code: "validation",
      message: "The selected assignment team is invalid.",
    };
  }

  const supabase = await createClient();

  const { error } = await supabase.rpc("manual_assign_lead", {
    requested_lead_id: leadId,
    requested_agent_profile_id: agentProfileId,
    requested_team_id: teamId,
    requested_reason: reason,
    requested_override_capacity: input.overrideCapacity ?? false,
  });

  if (error) {
    return mapAssignmentError(error);
  }

  return {
    ok: true,
  };
}

export async function manuallyUnassignLead(
  input: ManualLeadUnassignmentInput,
): Promise<LeadAssignmentServiceResult> {
  const leadId = input.leadId.trim();
  const reason =
    normalizeOptionalText(input.reason) ?? "Manual unassignment";

  if (!isValidUuid(leadId)) {
    return {
      ok: false,
      code: "validation",
      message: "A valid lead ID is required.",
    };
  }

  const supabase = await createClient();

  const { error } = await supabase.rpc("unassign_lead", {
    requested_lead_id: leadId,
    requested_reason: reason,
  });

  if (error) {
    return mapAssignmentError(error);
  }

  return {
    ok: true,
  };
}