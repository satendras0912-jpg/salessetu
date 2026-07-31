import "server-only";

import { createClient } from "@/lib/supabase/server";

import type {
  LeadFormField,
  LeadFormMode,
  LeadMutationPayload,
} from "@/types/lead-actions";

export type LeadMutationErrorKind =
  | "not_found"
  | "conflict"
  | "invalid_source"
  | "permission_denied"
  | "constraint_violation"
  | "database_error";

export type LeadMutationResult = {
  id: string;
  updatedAt: string;
};

type DatabaseErrorLike = {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
};

type LeadSourceRow = {
  id: string;
  is_active: boolean;
};

type LeadMutationRow = {
  id: string;
  updated_at: string;
};

export class LeadMutationError extends Error {
  readonly kind: LeadMutationErrorKind;
  readonly field?: LeadFormField;

  constructor(
    kind: LeadMutationErrorKind,
    message: string,
    field?: LeadFormField,
  ) {
    super(message);

    this.name = "LeadMutationError";
    this.kind = kind;
    this.field = field;
  }
}

function mapDatabaseError(
  error: DatabaseErrorLike,
): LeadMutationError {
  switch (error.code) {
    case "42501":
      return new LeadMutationError(
        "permission_denied",
        "You do not have permission to perform this lead operation.",
      );

    case "23503":
      return new LeadMutationError(
        "constraint_violation",
        "A referenced record is invalid or is not available in this organization.",
      );

    case "23505":
      return new LeadMutationError(
        "constraint_violation",
        "A lead with the same unique reference already exists.",
      );

    case "23514":
    case "22P02":
      return new LeadMutationError(
        "constraint_violation",
        "One or more lead values violate the database rules.",
      );

    default:
      return new LeadMutationError(
        "database_error",
        "The lead could not be saved because of a database error.",
      );
  }
}

function validateRequiredIdentifier(
  value: string,
  label: string,
): string {
  const normalizedValue = value.trim();

  if (!normalizedValue) {
    throw new LeadMutationError(
      "database_error",
      `${label} is required.`,
    );
  }

  return normalizedValue;
}

async function validateLeadSource(
  organizationId: string,
  sourceId: string | null,
  mode: LeadFormMode,
): Promise<void> {
  if (!sourceId) {
    return;
  }

  const supabase = await createClient();

  const { data, error } = await supabase
    .from("lead_sources")
    .select("id,is_active")
    .eq("organization_id", organizationId)
    .eq("id", sourceId)
    .maybeSingle();

  if (error) {
    throw mapDatabaseError(error);
  }

  if (!data) {
    throw new LeadMutationError(
      "invalid_source",
      "The selected lead source does not belong to this organization.",
      "leadSourceId",
    );
  }

  const source = data as LeadSourceRow;

  if (mode === "create" && !source.is_active) {
    throw new LeadMutationError(
      "invalid_source",
      "The selected lead source is inactive.",
      "leadSourceId",
    );
  }
}

export async function createLeadRecord(
  organizationId: string,
  payload: LeadMutationPayload,
): Promise<LeadMutationResult> {
  const cleanOrganizationId =
    validateRequiredIdentifier(
      organizationId,
      "Organization ID",
    );

  await validateLeadSource(
    cleanOrganizationId,
    payload.lead_source_id,
    "create",
  );

  const supabase = await createClient();

  const { data, error } = await supabase
    .from("leads")
    .insert({
      organization_id: cleanOrganizationId,
      ...payload,
    })
    .select("id,updated_at")
    .single();

  if (error) {
    throw mapDatabaseError(error);
  }

  const createdLead = data as LeadMutationRow;

  return {
    id: createdLead.id,
    updatedAt: createdLead.updated_at,
  };
}

export async function updateLeadRecord(
  organizationId: string,
  leadId: string,
  expectedUpdatedAt: string,
  payload: LeadMutationPayload,
): Promise<LeadMutationResult> {
  const cleanOrganizationId =
    validateRequiredIdentifier(
      organizationId,
      "Organization ID",
    );

  const cleanLeadId = validateRequiredIdentifier(
    leadId,
    "Lead ID",
  );

  const cleanExpectedUpdatedAt =
    validateRequiredIdentifier(
      expectedUpdatedAt,
      "Expected update timestamp",
    );

  await validateLeadSource(
    cleanOrganizationId,
    payload.lead_source_id,
    "edit",
  );

  const supabase = await createClient();

  /*
   * Optimistic concurrency:
   *
   * Update केवल तभी होगा जब database updated_at उस timestamp
   * के बराबर हो जो edit form खोलते समय प्राप्त हुआ था।
   */
  const { data, error } = await supabase
    .from("leads")
    .update(payload)
    .eq("organization_id", cleanOrganizationId)
    .eq("id", cleanLeadId)
    .eq("updated_at", cleanExpectedUpdatedAt)
    .is("deleted_at", null)
    .select("id,updated_at")
    .maybeSingle();

  if (error) {
    throw mapDatabaseError(error);
  }

  if (data) {
    const updatedLead = data as LeadMutationRow;

    return {
      id: updatedLead.id,
      updatedAt: updatedLead.updated_at,
    };
  }

  /*
   * Zero updated rows के दो संभावित कारण:
   *
   * 1. Lead मौजूद नहीं है या delete हो चुकी है।
   * 2. Lead किसी दूसरे user/process ने पहले update कर दी।
   */
  const {
    data: currentLead,
    error: lookupError,
  } = await supabase
    .from("leads")
    .select("id,updated_at")
    .eq("organization_id", cleanOrganizationId)
    .eq("id", cleanLeadId)
    .is("deleted_at", null)
    .maybeSingle();

  if (lookupError) {
    throw mapDatabaseError(lookupError);
  }

  if (!currentLead) {
    throw new LeadMutationError(
      "not_found",
      "The lead does not exist or is no longer available.",
    );
  }

  throw new LeadMutationError(
    "conflict",
    "This lead was changed by another user. Reload the latest version before saving again.",
    "expectedUpdatedAt",
  );
}