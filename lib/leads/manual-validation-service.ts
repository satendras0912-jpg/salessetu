import { createClient } from "@/lib/supabase/server";

export type ManualValidationDecision =
  | "approved"
  | "hold"
  | "rejected";

export type ManualValidationQueueFilter =
  | "pending"
  | ManualValidationDecision
  | "all";

export type ManualValidationQueueItem = {
  id: string;
  fullName: string;
  phone: string | null;
  email: string | null;
  preferredProject: string | null;
  preferredLocation: string | null;
  source: string | null;
  priority: string;
  createdAt: string;
  qualificationStatus: string;
  review: {
    decision: ManualValidationDecision;
    reason: string;
    notes: string | null;
    reviewedAt: string;
  } | null;
};

type LeadRow = {
  id: string;
  full_name: string | null;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
  email: string | null;
  preferred_project: string | null;
  preferred_location: string | null;
  priority: string | null;
  qualification_status: string | null;
  created_at: string;
  lead_sources: { name: string | null } | null;
};

type ReviewRow = {
  lead_id: string;
  decision: ManualValidationDecision;
  reason: string;
  notes: string | null;
  reviewed_at: string;
};

function leadName(lead: LeadRow): string {
  const explicitName = lead.full_name?.trim();

  if (explicitName) {
    return explicitName;
  }

  return [lead.first_name, lead.last_name]
    .filter((value): value is string => Boolean(value?.trim()))
    .join(" ")
    .trim() || "Unnamed lead";
}

export async function getManualValidationQueue(
  organizationId: string,
  filter: ManualValidationQueueFilter = "pending",
): Promise<ManualValidationQueueItem[]> {
  const supabase = await createClient();

  const { data: leadData, error: leadError } = await supabase
    .from("leads")
    .select(
      "id,full_name,first_name,last_name,phone,email,preferred_project,preferred_location,priority,qualification_status,created_at,lead_sources(name)",
    )
    .eq("organization_id", organizationId)
    .is("deleted_at", null)
    .neq("lead_status", "archived")
    .order("created_at", { ascending: false })
    .limit(100);

  if (leadError) {
    throw new Error(
      `Unable to load manual validation queue: ${leadError.message}`,
    );
  }

  const leads = (leadData ?? []) as unknown as LeadRow[];
  const leadIds = leads.map((lead) => lead.id);

  if (leadIds.length === 0) {
    return [];
  }

  const { data: reviewData, error: reviewError } = await supabase
    .from("lead_manual_validation_reviews")
    .select("lead_id,decision,reason,notes,reviewed_at")
    .eq("organization_id", organizationId)
    .in("lead_id", leadIds);

  if (reviewError) {
    throw new Error(
      `Unable to load manual validation decisions: ${reviewError.message}`,
    );
  }

  const reviewsByLeadId = new Map(
    ((reviewData ?? []) as unknown as ReviewRow[]).map(
      (review) => [review.lead_id, review] as const,
    ),
  );

  return leads
    .map((lead) => {
      const review = reviewsByLeadId.get(lead.id) ?? null;

      return {
        id: lead.id,
        fullName: leadName(lead),
        phone: lead.phone,
        email: lead.email,
        preferredProject: lead.preferred_project,
        preferredLocation: lead.preferred_location,
        source: lead.lead_sources?.name ?? null,
        priority: lead.priority ?? "normal",
        createdAt: lead.created_at,
        qualificationStatus:
          lead.qualification_status ?? "pending",
        review: review
          ? {
              decision: review.decision,
              reason: review.reason,
              notes: review.notes,
              reviewedAt: review.reviewed_at,
            }
          : null,
      } satisfies ManualValidationQueueItem;
    })
    .filter((lead) => {
      if (filter === "all") {
        return true;
      }

      if (filter === "pending") {
        return !lead.review || lead.review.decision === "hold";
      }

      return lead.review?.decision === filter;
    });
}
