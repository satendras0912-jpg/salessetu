import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";

export type AttributionRow = {
  label: string;
  leads: number;
  qualified: number;
  followUpReached: number;
  siteVisitReached: number;
  dealReached: number;
  won: number;
};

type AttributionRpcRow = {
  dimension: "source" | "campaign" | "geo";
  label: string;
  lead_count: number | string;
  qualified_count: number | string;
  follow_up_count: number | string;
  site_visit_count: number | string;
  deal_count: number | string;
  won_count: number | string;
};

const numberValue = (value: number | string) => Number.isFinite(Number(value)) ? Number(value) : 0;

function mapRow(row: AttributionRpcRow): AttributionRow {
  return { label: row.label, leads: numberValue(row.lead_count), qualified: numberValue(row.qualified_count), followUpReached: numberValue(row.follow_up_count), siteVisitReached: numberValue(row.site_visit_count), dealReached: numberValue(row.deal_count), won: numberValue(row.won_count) };
}

/** The database performs a single permission-checked aggregate, avoiding application-side scans as a tenant grows. */
export async function getLeadAttributionDashboard() {
  const { context } = await requirePermissionAccess({
    allOf: ["dashboard.view", "leads.view", "followups.view", "site_visits.view", "deals.view"],
    loginRedirectTo: "/login?next=/dashboard/analytics/attribution",
    unauthorizedRedirectTo: "/unauthorized",
  });
  const organizationId = context.organization?.id;
  if (!organizationId) throw new Error("An active organization is required.");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_lead_attribution_dashboard", { requested_organization_id: organizationId, requested_days: 90 });
  if (error) throw new Error("Unable to load lead attribution. Please try again.");
  const rows = (data ?? []) as unknown as AttributionRpcRow[];
  const byDimension = (dimension: AttributionRpcRow["dimension"]) => rows.filter((row) => row.dimension === dimension).map(mapRow);
  const bySource = byDimension("source");
  const totals = bySource.reduce((summary, row) => ({ leads: summary.leads + row.leads, qualified: summary.qualified + row.qualified, followUpReached: summary.followUpReached + row.followUpReached, siteVisitReached: summary.siteVisitReached + row.siteVisitReached, dealReached: summary.dealReached + row.dealReached, won: summary.won + row.won }), { leads: 0, qualified: 0, followUpReached: 0, siteVisitReached: 0, dealReached: 0, won: 0 });
  return { cohortStart: new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString(), generatedAt: new Date().toISOString(), totals, bySource, byCampaign: byDimension("campaign"), byGeo: byDimension("geo") };
}
