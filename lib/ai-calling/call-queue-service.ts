import {
  createClient,
} from "@/lib/supabase/server";

export type QueueLeadAiCallInput = {
  organizationId: string;
  leadId: string;
  idempotencyKey: string;
};

export type QueueLeadAiCallResult = {
  callJobId: string;
  status: string;
};

type ActiveConfiguration = {
  providerConnectionId: string;
  scriptTemplateId: string;
  qualificationSchemaId: string;
};

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function requireUuid(
  value: string,
  label: string,
): string {
  const normalized = value.trim();

  if (!UUID_PATTERN.test(normalized)) {
    throw new Error(`${label} is invalid.`);
  }

  return normalized;
}

async function getActiveConfiguration(): Promise<ActiveConfiguration> {
  const supabase = await createClient();

  const [
    connectionResult,
    scriptResult,
    schemaResult,
  ] = await Promise.all([
    supabase
      .from("ai_call_provider_connections")
      .select("id")
      .eq("status", "active")
      .limit(2),

    supabase
      .from("ai_call_script_templates")
      .select("id")
      .eq("status", "active")
      .eq("script_type", "qualification")
      .limit(2),

    supabase
      .from("ai_call_qualification_schemas")
      .select("id")
      .eq("status", "active")
      .limit(2),
  ]);

  if (connectionResult.error) {
    throw new Error(
      `Unable to load AI provider connection: ${connectionResult.error.message}`,
    );
  }

  if (scriptResult.error) {
    throw new Error(
      `Unable to load AI call script: ${scriptResult.error.message}`,
    );
  }

  if (schemaResult.error) {
    throw new Error(
      `Unable to load qualification schema: ${schemaResult.error.message}`,
    );
  }

  if (connectionResult.data.length !== 1) {
    throw new Error(
      "Exactly one active AI provider connection is required.",
    );
  }

  if (scriptResult.data.length !== 1) {
    throw new Error(
      "Exactly one active qualification script is required.",
    );
  }

  if (schemaResult.data.length !== 1) {
    throw new Error(
      "Exactly one active qualification schema is required.",
    );
  }

  return {
    providerConnectionId:
      connectionResult.data[0].id,

    scriptTemplateId:
      scriptResult.data[0].id,

    qualificationSchemaId:
      schemaResult.data[0].id,
  };
}

export async function queueLeadAiCall(
  input: QueueLeadAiCallInput,
): Promise<QueueLeadAiCallResult> {
  const organizationId =
    requireUuid(
      input.organizationId,
      "Organization ID",
    );

  const leadId =
    requireUuid(
      input.leadId,
      "Lead ID",
    );

  const idempotencyKey =
    input.idempotencyKey.trim();

  if (
    !idempotencyKey ||
    idempotencyKey.length > 200
  ) {
    throw new Error(
      "A valid AI call request token is required.",
    );
  }

  const supabase = await createClient();

  const {
    data: lead,
    error: leadError,
  } = await supabase
    .from("leads")
    .select(`
      id,
      organization_id,
      first_name,
      last_name,
      phone,
      normalized_phone
    `)
    .eq("id", leadId)
    .eq(
      "organization_id",
      organizationId,
    )
    .single();

  if (leadError || !lead) {
    throw new Error(
      "The selected lead could not be loaded.",
    );
  }

  const phoneNumber =
    lead.normalized_phone?.trim() ||
    lead.phone?.trim();

  if (!phoneNumber) {
    throw new Error(
      "This lead does not have a callable phone number.",
    );
  }

  const contactName =
    [
      lead.first_name,
      lead.last_name,
    ]
      .filter(
        (
          value,
        ): value is string =>
          typeof value === "string" &&
          value.trim().length > 0,
      )
      .map((value) => value.trim())
      .join(" ") || null;

  const configuration =
    await getActiveConfiguration();

  const {
    data,
    error,
  } = await supabase.rpc(
    "create_ai_call_job",
    {
      requested_organization_id:
        organizationId,

      requested_phone_number:
        phoneNumber,

      requested_lead_id:
        leadId,

      requested_campaign_id:
        null,

      requested_provider_connection_id:
        configuration
          .providerConnectionId,

      requested_script_template_id:
        configuration
          .scriptTemplateId,

      requested_qualification_schema_id:
        configuration
          .qualificationSchemaId,

      requested_voice_id:
        null,

      requested_contact_name:
        contactName,

      requested_language_code:
        "hi-IN",

      requested_scheduled_at:
        null,

      requested_script_variables: {
        lead_id: leadId,
        contact_name: contactName,
      },

      requested_call_context: {
        source: "lead_detail",
        requested_via:
          "manual_confirmation",
      },

      requested_source_type:
        "manual",

      requested_source_reference:
        leadId,

      requested_idempotency_key:
        idempotencyKey,

      requested_priority:
        100,
    },
  );

  if (error) {
    throw new Error(
      `Unable to queue AI call: ${error.message}`,
    );
  }

  const returnedJob =
    Array.isArray(data)
      ? data[0]
      : data;

  if (
    !returnedJob ||
    typeof returnedJob !== "object"
  ) {
    throw new Error(
      "AI call job was not returned after queueing.",
    );
  }

  const jobId =
    "id" in returnedJob &&
    typeof returnedJob.id === "string"
      ? returnedJob.id
      : null;

  const status =
    "status" in returnedJob &&
    typeof returnedJob.status === "string"
      ? returnedJob.status
      : null;

  if (!jobId || !status) {
    throw new Error(
      "AI call job returned an invalid response.",
    );
  }

  return {
    callJobId: jobId,
    status,
  };
}