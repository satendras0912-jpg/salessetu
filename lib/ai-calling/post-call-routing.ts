export type PostCallRoutingInput = {
  qualificationStatus: string;
  recommendedAction: string | null;
};

export type PostCallRoutingPlan =
  | {
      createTask: false;
      reason: string;
    }
  | {
      createTask: true;
      title: string;
      followUpType: "call" | "site_visit" | "general";
      priority: "low" | "normal" | "high";
      dueInMinutes: number;
    };

function createTaskPlan(
  title: string,
  followUpType: "call" | "site_visit" | "general",
  priority: "low" | "normal" | "high",
  dueInMinutes: number,
): PostCallRoutingPlan {
  return {
    createTask: true,
    title,
    followUpType,
    priority,
    dueInMinutes,
  };
}

/**
 * Converts the persisted qualification decision into an internal task only.
 *
 * This intentionally does not queue another AI call, send a customer message,
 * create an appointment, or change lead ownership. Those actions remain human
 * decisions after the task is reviewed.
 */
export function getPostCallRoutingPlan(
  input: PostCallRoutingInput,
): PostCallRoutingPlan {
  const status =
    input.qualificationStatus.trim().toLowerCase();

  const action =
    input.recommendedAction?.trim().toLowerCase() ?? "";

  if (
    action === "close_or_suppress" ||
    status === "unqualified"
  ) {
    return {
      createTask: false,
      reason: "The qualification is not eligible for a follow-up task.",
    };
  }

  switch (action) {
    case "assign_agent_and_schedule_site_visit":
      return createTaskPlan(
        "Confirm site visit and assign a representative",
        "site_visit",
        "high",
        15,
      );

    case "agent_callback_and_nurture":
      return createTaskPlan(
        "Call qualified lead and confirm next step",
        "call",
        "high",
        15,
      );

    case "send_details":
      return createTaskPlan(
        "Share requested details and confirm BHK preference",
        "general",
        "high",
        15,
      );

    case "manual_review":
      return createTaskPlan(
        "Review AI call and clarify missing preferences",
        "general",
        "high",
        15,
      );
  }

  switch (status) {
    case "qualified_hot":
      return createTaskPlan(
        "Contact qualified lead and confirm next step",
        "call",
        "high",
        15,
      );

    case "qualified_warm":
      return createTaskPlan(
        "Review qualified lead and set next step",
        "general",
        "normal",
        240,
      );

    case "qualified_cold":
      return createTaskPlan(
        "Review cold qualification for nurture eligibility",
        "general",
        "low",
        1_440,
      );

    default:
      return createTaskPlan(
        "Review AI call qualification",
        "general",
        "high",
        15,
      );
  }
}
