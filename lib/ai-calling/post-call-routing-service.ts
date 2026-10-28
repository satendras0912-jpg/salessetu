import "server-only";

import {
  getPostCallRoutingPlan,
} from "./post-call-routing";

import {
  createAdminClient,
} from "@/lib/supabase/admin";

type QualificationRoutingRow = {
  organization_id: string;
  lead_id: string;
  status: string;
  recommended_action: string | null;
  recommended_followup_at: string | null;
};

type LeadRoutingRow = {
  assigned_to: string | null;
};

type ExistingTaskRow = {
  id: string;
};

type CreatedTaskRow = {
  id: string;
};

export type PostCallRoutingResult = {
  processed: boolean;
  taskId: string | null;
  reason: string;
};

function getDueAt(
  recommendedFollowupAt: string | null,
  dueInMinutes: number,
): string {
  if (recommendedFollowupAt) {
    const recommendedAt =
      new Date(recommendedFollowupAt);

    if (
      !Number.isNaN(
        recommendedAt.getTime(),
      ) &&
      recommendedAt.getTime() >
        Date.now()
    ) {
      return recommendedAt.toISOString();
    }
  }

  return new Date(
    Date.now() +
      dueInMinutes * 60_000,
  ).toISOString();
}

function getCreatedTaskId(
  value: unknown,
): string | null {
  const record =
    Array.isArray(value)
      ? value[0]
      : value;

  if (
    typeof record !== "object" ||
    record === null ||
    !("id" in record) ||
    typeof record.id !== "string"
  ) {
    return null;
  }

  return record.id;
}

/**
 * Adds one idempotent internal task after a persisted AI qualification.
 *
 * It creates no outbound call, message, appointment, notification, or owner
 * assignment. A current lead owner is merely retained as the task assignee.
 */
export async function routeAiCallQualification(
  callAttemptId: string,
): Promise<PostCallRoutingResult> {
  const admin =
    createAdminClient();

  const {
    data: qualificationData,
    error: qualificationError,
  } = await admin
    .from("ai_call_qualification_results")
    .select(
      [
        "organization_id",
        "lead_id",
        "status",
        "recommended_action",
        "recommended_followup_at",
      ].join(","),
    )
    .eq(
      "call_attempt_id",
      callAttemptId,
    )
    .maybeSingle();

  if (qualificationError) {
    throw new Error(
      `Unable to load AI qualification for routing: ${qualificationError.message}`,
    );
  }

  if (!qualificationData) {
    return {
      processed: false,
      taskId: null,
      reason: "No persisted qualification is available for routing.",
    };
  }

  const qualification =
    qualificationData as unknown as QualificationRoutingRow;

  const plan =
    getPostCallRoutingPlan({
      qualificationStatus:
        qualification.status,

      recommendedAction:
        qualification.recommended_action,
    });

  if (!plan.createTask) {
    return {
      processed: false,
      taskId: null,
      reason: plan.reason,
    };
  }

  const {
    data: leadData,
    error: leadError,
  } = await admin
    .from("leads")
    .select("assigned_to")
    .eq(
      "organization_id",
      qualification.organization_id,
    )
    .eq(
      "id",
      qualification.lead_id,
    )
    .is(
      "deleted_at",
      null,
    )
    .maybeSingle();

  if (leadError) {
    throw new Error(
      `Unable to load lead for post-call routing: ${leadError.message}`,
    );
  }

  if (!leadData) {
    return {
      processed: false,
      taskId: null,
      reason: "The qualified lead is no longer available for routing.",
    };
  }

  const existingMarker =
    `[AI post-call routing: ${callAttemptId}]`;

  const {
    data: existingTaskData,
    error: existingTaskError,
  } = await admin
    .from("follow_up_tasks")
    .select("id")
    .eq(
      "organization_id",
      qualification.organization_id,
    )
    .eq(
      "lead_id",
      qualification.lead_id,
    )
    .like(
      "description",
      `%${existingMarker}%`,
    )
    .is(
      "deleted_at",
      null,
    )
    .limit(1)
    .maybeSingle();

  if (existingTaskError) {
    throw new Error(
      `Unable to check existing post-call route: ${existingTaskError.message}`,
    );
  }

  if (existingTaskData) {
    return {
      processed: false,
      taskId:
        (
          existingTaskData as
            unknown as ExistingTaskRow
        ).id,

      reason: "An internal post-call task already exists.",
    };
  }

  const lead =
    leadData as unknown as LeadRoutingRow;

  const description = [
    existingMarker,
    "Created from the verified AI-call qualification.",
    `Recommended action: ${qualification.recommended_action ?? "review"}.`,
    "Internal action only; do not auto-redial, message, or book a visit from this task.",
  ].join(" ");

  const {
    data: createdTaskData,
    error: createTaskError,
  } = await admin.rpc(
    "create_follow_up_task",
    {
      requested_lead_id:
        qualification.lead_id,

      requested_title:
        plan.title,

      requested_description:
        description,

      requested_follow_up_type:
        plan.followUpType,

      requested_priority:
        plan.priority,

      requested_assigned_to:
        lead.assigned_to,

      requested_due_at:
        getDueAt(
          qualification.recommended_followup_at,
          plan.dueInMinutes,
        ),

      requested_reminder_at:
        null,
    },
  );

  if (createTaskError) {
    throw new Error(
      `Unable to create post-call follow-up task: ${createTaskError.message}`,
    );
  }

  const taskId =
    getCreatedTaskId(
      createdTaskData,
    );

  if (!taskId) {
    throw new Error(
      "Post-call follow-up task was created, but its ID could not be verified.",
    );
  }

  return {
    processed: true,
    taskId,
    reason: "An internal post-call task was created.",
  };
}
