import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { OPEN_TASK_STATUSES } from "@/lib/follow-ups/worklist-contract";
import { createClient } from "@/lib/supabase/server";

import { GEO_TAGS, type GeoTag } from "./geo-tag-contract";

export type GeoReadinessRow = {
  geoTag: GeoTag | null;
  mappedLeadCount: number;
  unassignedFollowUpCount: number;
};

async function countLeads(
  supabase: Awaited<ReturnType<typeof createClient>>,
  organizationId: string,
  geoTag: GeoTag | null,
): Promise<number> {
  let query = supabase
    .from("leads")
    .select("id", { count: "exact", head: true })
    .eq("organization_id", organizationId)
    .is("deleted_at", null);

  query = geoTag
    ? query.eq("geo_tag", geoTag)
    : query.is("geo_tag", null);

  const { count, error } = await query;
  if (error) throw new Error("Unable to load GEO lead readiness.");
  return count ?? 0;
}

async function countUnassignedFollowUps(
  supabase: Awaited<ReturnType<typeof createClient>>,
  organizationId: string,
  geoTag: GeoTag | null,
): Promise<number> {
  let query = supabase
    .from("follow_up_tasks")
    .select("id,leads!inner(geo_tag)", { count: "exact", head: true })
    .eq("organization_id", organizationId)
    .eq("leads.organization_id", organizationId)
    .is("deleted_at", null)
    .is("leads.deleted_at", null)
    .is("assigned_to", null)
    .in("status", OPEN_TASK_STATUSES);

  query = geoTag
    ? query.eq("leads.geo_tag", geoTag)
    : query.is("leads.geo_tag", null);

  const { count, error } = await query;
  if (error) throw new Error("Unable to load GEO follow-up readiness.");
  return count ?? 0;
}

export async function getGeoReadiness(): Promise<{
  rows: GeoReadinessRow[];
  totalMappedLeads: number;
  totalMappingRequired: number;
  totalUnassignedFollowUps: number;
}> {
  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/readiness",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;
  if (!organizationId) throw new Error("An active organization is required.");

  const supabase = await createClient();
  const tags: Array<GeoTag | null> = [...GEO_TAGS, null];
  const rows = await Promise.all(tags.map(async (geoTag) => ({
    geoTag,
    mappedLeadCount: await countLeads(supabase, organizationId, geoTag),
    unassignedFollowUpCount: await countUnassignedFollowUps(
      supabase,
      organizationId,
      geoTag,
    ),
  })));

  const mappedRows = rows.filter((row) => row.geoTag !== null);
  return {
    rows,
    totalMappedLeads: mappedRows.reduce((sum, row) => sum + row.mappedLeadCount, 0),
    totalMappingRequired: rows.find((row) => row.geoTag === null)?.mappedLeadCount ?? 0,
    totalUnassignedFollowUps: rows.reduce(
      (sum, row) => sum + row.unassignedFollowUpCount,
      0,
    ),
  };
}
