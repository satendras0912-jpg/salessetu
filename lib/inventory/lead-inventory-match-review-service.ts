import "server-only";

import { createClient } from "@/lib/supabase/server";

export type LeadInventoryMatchReview = {
  inventoryUnitId: string;
  decision: "suitable" | "not_suitable";
  reason: string;
  notes: string | null;
  reviewedAt: string;
};

type ReviewRow = {
  inventory_unit_id: string;
  decision: "suitable" | "not_suitable";
  reason: string;
  notes: string | null;
  reviewed_at: string;
};

export async function getLeadInventoryMatchReviews(
  organizationId: string,
  leadId: string,
): Promise<LeadInventoryMatchReview[]> {
  if (!organizationId.trim() || !leadId.trim()) {
    return [];
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("lead_inventory_match_reviews")
    .select("inventory_unit_id, decision, reason, notes, reviewed_at")
    .eq("organization_id", organizationId)
    .eq("lead_id", leadId)
    .order("reviewed_at", { ascending: false });

  if (error) {
    throw new Error(
      `Unable to load inventory match reviews: ${error.message}`,
    );
  }

  return (data ?? []).map((row) => {
    const review = row as ReviewRow;

    return {
      inventoryUnitId: review.inventory_unit_id,
      decision: review.decision,
      reason: review.reason,
      notes: review.notes,
      reviewedAt: review.reviewed_at,
    };
  });
}
