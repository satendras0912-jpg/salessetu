import "server-only";

import {
  createClient,
} from "@/lib/supabase/server";

export type DealConversionEligibility = {
  isEligible: boolean;
  message: string;
};

export type DealConversionRequestResult =
  | { ok: true; requestId: string }
  | { ok: false; message: string };

type DealConversionEligibilityRow = {
  is_eligible: boolean;
  message: string;
};

export async function getDealConversionEligibility(
  leadId: string,
): Promise<DealConversionEligibility> {
  const supabase =
    await createClient();

  const {
    data,
    error,
  } = await supabase.rpc(
    "get_deal_conversion_eligibility",
    {
      requested_lead_id: leadId,
    },
  );

  if (error) {
    return {
      isEligible: false,
      message:
        "Deal conversion eligibility could not be loaded. Refresh the lead and try again.",
    };
  }

  const row =
    (
      data as
        | DealConversionEligibilityRow[]
        | null
    )?.[0];

  if (!row) {
    return {
      isEligible: false,
      message:
        "Deal conversion eligibility could not be verified.",
    };
  }

  return {
    isEligible:
      row.is_eligible === true,
    message:
      row.message ||
      "Deal conversion eligibility could not be verified.",
  };
}

export async function requestDealConversion(
  leadId: string,
  siteVisitId: string,
  notes: string | null,
): Promise<DealConversionRequestResult> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "request_deal_conversion",
    {
      requested_lead_id: leadId,
      requested_site_visit_id: siteVisitId,
      requested_notes: notes,
    },
  );

  if (error) {
    return {
      ok: false,
      message: error.message || "The owner approval request could not be created.",
    };
  }

  const row = (Array.isArray(data) ? data[0] : data) as { id?: unknown } | null;

  if (!row || typeof row.id !== "string" || !row.id.trim()) {
    return {
      ok: false,
      message: "The owner approval request could not be verified. Refresh before trying again.",
    };
  }

  return { ok: true, requestId: row.id };
}

export type PendingDealConversionRequest = {
  id: string;
  leadId: string;
  siteVisitId: string;
  inventoryUnitId: string;
  notes: string | null;
  requestedAt: string;
};

export async function getPendingDealConversionRequests(
  organizationId: string,
): Promise<PendingDealConversionRequest[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("deal_conversion_requests")
    .select("id, lead_id, site_visit_id, inventory_unit_id, request_notes, requested_at")
    .eq("organization_id", organizationId)
    .eq("status", "pending")
    .order("requested_at", { ascending: true });

  if (error) return [];

  return (data ?? []).flatMap((row) => {
    if (
      typeof row.id !== "string" ||
      typeof row.lead_id !== "string" ||
      typeof row.site_visit_id !== "string" ||
      typeof row.inventory_unit_id !== "string" ||
      typeof row.requested_at !== "string"
    ) return [];
    return [{
      id: row.id,
      leadId: row.lead_id,
      siteVisitId: row.site_visit_id,
      inventoryUnitId: row.inventory_unit_id,
      notes: typeof row.request_notes === "string" ? row.request_notes : null,
      requestedAt: row.requested_at,
    }];
  });
}

export async function decideDealConversionRequest(
  requestId: string,
  decision: "approved" | "rejected",
  reason: string,
): Promise<{ ok: true; dealId: string | null } | { ok: false; message: string }> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("decide_deal_conversion_request", {
    requested_request_id: requestId,
    requested_decision: decision,
    requested_reason: reason,
  });
  if (error) return { ok: false, message: error.message || "The owner decision could not be saved." };
  const row = (Array.isArray(data) ? data[0] : data) as { deal_id?: unknown } | null;
  return { ok: true, dealId: row && typeof row.deal_id === "string" ? row.deal_id : null };
}
