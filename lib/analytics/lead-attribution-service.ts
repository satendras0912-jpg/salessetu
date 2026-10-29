import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { geoTagLabel } from "@/lib/geo/geo-tag-contract";
import { createClient } from "@/lib/supabase/server";

type AttributionLead = {
  id: string;
  lead_source_id: string | null;
  campaign_name: string | null;
  utm_source: string | null;
  utm_campaign: string | null;
  geo_tag: string | null;
  qualification_status: string | null;
  ai_qualified: boolean;
};

type LeadSource = { id: string; name: string; source_type: string };

export type AttributionRow = {
  label: string;
  leads: number;
  qualified: number;
  followUpReached: number;
  siteVisitReached: number;
  dealReached: number;
  won: number;
};

const PAGE_SIZE = 1000;
const CHUNK_SIZE = 250;

function cleanLabel(value: string | null | undefined, fallback: string) {
  const clean = value?.replace(/\s+/g, " ").trim();
  return clean || fallback;
}

function isQualified(lead: AttributionLead) {
  return lead.ai_qualified || ["qualified", "approved"].includes((lead.qualification_status ?? "").toLowerCase());
}

function chunks<T>(items: readonly T[], size: number): T[][] {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) result.push(items.slice(index, index + size));
  return result;
}

async function getLeadCohort(organizationId: string, startAt: string) {
  const supabase = await createClient();
  const leads: AttributionLead[] = [];
  for (let page = 0; ; page += 1) {
    const start = page * PAGE_SIZE;
    const { data, error } = await supabase.from("leads")
      .select("id,lead_source_id,campaign_name,utm_source,utm_campaign,geo_tag,qualification_status,ai_qualified")
      .eq("organization_id", organizationId).is("deleted_at", null)
      .gte("created_at", startAt).order("id", { ascending: true }).range(start, start + PAGE_SIZE - 1);
    if (error) throw new Error("Unable to load lead attribution. Please try again.");
    const batch = (data ?? []) as unknown as AttributionLead[];
    leads.push(...batch);
    if (batch.length < PAGE_SIZE) return leads;
  }
}

async function getRelatedLeadIds(table: "follow_up_tasks" | "site_visits" | "deals", organizationId: string, leadIds: readonly string[], requiredStatus?: string) {
  if (leadIds.length === 0) return new Set<string>();
  const supabase = await createClient();
  const relatedLeadIds = new Set<string>();
  for (const leadIdChunk of chunks(leadIds, CHUNK_SIZE)) {
    let query = supabase.from(table).select("lead_id")
      .eq("organization_id", organizationId).is("deleted_at", null).in("lead_id", leadIdChunk);
    if (requiredStatus) query = query.eq("status", requiredStatus);
    const { data, error } = await query;
    if (error) throw new Error("Unable to load attribution outcomes. Please try again.");
    for (const row of (data ?? []) as Array<{ lead_id: string }>) relatedLeadIds.add(row.lead_id);
  }
  return relatedLeadIds;
}

function buildRows(
  leads: AttributionLead[],
  labelFor: (lead: AttributionLead) => string,
  qualifiedIds: ReadonlySet<string>,
  followUpLeadIds: ReadonlySet<string>,
  siteVisitLeadIds: ReadonlySet<string>,
  dealLeadIds: ReadonlySet<string>,
  wonLeadIds: ReadonlySet<string>,
) {
  const rows = new Map<string, AttributionRow>();
  for (const lead of leads) {
    const label = labelFor(lead);
    const row = rows.get(label) ?? { label, leads: 0, qualified: 0, followUpReached: 0, siteVisitReached: 0, dealReached: 0, won: 0 };
    row.leads += 1;
    if (qualifiedIds.has(lead.id)) row.qualified += 1;
    if (followUpLeadIds.has(lead.id)) row.followUpReached += 1;
    if (siteVisitLeadIds.has(lead.id)) row.siteVisitReached += 1;
    if (dealLeadIds.has(lead.id)) row.dealReached += 1;
    if (wonLeadIds.has(lead.id)) row.won += 1;
    rows.set(label, row);
  }
  return [...rows.values()].sort((left, right) => right.leads - left.leads || left.label.localeCompare(right.label, "en-IN"));
}

/** Read-only attribution cohort for leads created in the most recent 90 days. */
export async function getLeadAttributionDashboard() {
  const { context } = await requirePermissionAccess({
    allOf: ["dashboard.view", "leads.view", "followups.view", "site_visits.view", "deals.view"],
    loginRedirectTo: "/login?next=/dashboard/analytics/attribution",
    unauthorizedRedirectTo: "/unauthorized",
  });
  const organizationId = context.organization?.id;
  if (!organizationId) throw new Error("An active organization is required.");

  const now = new Date();
  const cohortStart = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000).toISOString();
  const [leads, sources] = await Promise.all([
    getLeadCohort(organizationId, cohortStart),
    (async () => {
      const supabase = await createClient();
      const { data, error } = await supabase.from("lead_sources").select("id,name,source_type").eq("organization_id", organizationId);
      if (error) throw new Error("Unable to load lead sources. Please try again.");
      return (data ?? []) as unknown as LeadSource[];
    })(),
  ]);
  const leadIds = leads.map((lead) => lead.id);
  const [followUpLeadIds, siteVisitLeadIds, dealLeadIds, wonLeadIds] = await Promise.all([
    getRelatedLeadIds("follow_up_tasks", organizationId, leadIds),
    getRelatedLeadIds("site_visits", organizationId, leadIds),
    getRelatedLeadIds("deals", organizationId, leadIds),
    getRelatedLeadIds("deals", organizationId, leadIds, "won"),
  ]);
  const qualifiedIds = new Set(leads.filter(isQualified).map((lead) => lead.id));
  const sourceNames = new Map(sources.map((source) => [source.id, source.name]));
  return {
    cohortStart,
    generatedAt: now.toISOString(),
    totals: {
      leads: leads.length,
      qualified: qualifiedIds.size,
      followUpReached: followUpLeadIds.size,
      siteVisitReached: siteVisitLeadIds.size,
      dealReached: dealLeadIds.size,
      won: wonLeadIds.size,
    },
    bySource: buildRows(leads, (lead) => sourceNames.get(lead.lead_source_id ?? "") ?? cleanLabel(lead.utm_source, "Unattributed"), qualifiedIds, followUpLeadIds, siteVisitLeadIds, dealLeadIds, wonLeadIds),
    byCampaign: buildRows(leads, (lead) => cleanLabel(lead.utm_campaign, cleanLabel(lead.campaign_name, "Unattributed campaign")), qualifiedIds, followUpLeadIds, siteVisitLeadIds, dealLeadIds, wonLeadIds),
    byGeo: buildRows(leads, (lead) => geoTagLabel(lead.geo_tag) ?? "GEO mapping required", qualifiedIds, followUpLeadIds, siteVisitLeadIds, dealLeadIds, wonLeadIds),
  };
}
