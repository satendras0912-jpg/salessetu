import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { GEO_TAGS, type GeoTag } from "@/lib/geo/geo-tag-contract";
import { createClient } from "@/lib/supabase/server";
import { indiaDayBounds, OPEN_TASK_STATUSES } from "./worklist-contract";

export type FollowUpInsightMetrics = {
  active: number;
  dueToday: number;
  overdue: number;
  unassigned: number;
  completedLast7Days: number;
};

export type GeoFollowUpInsight = {
  geoTag: GeoTag | null;
  active: number;
  overdue: number;
  unassigned: number;
};

function failed(result: { error: unknown }) {
  return Boolean(result.error);
}

/**
 * Read-only manager view of the active follow-up workload. Every query keeps
 * both task and joined lead records scoped to the active organization; this is
 * important because GEO tags live on leads while task ownership lives here.
 */
export async function getFollowUpInsights() {
  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/insights",
    unauthorizedRedirectTo: "/unauthorized",
  });
  const organizationId = context.organization?.id;
  if (!organizationId) throw new Error("An active organization is required.");

  const supabase = await createClient();
  const now = new Date();
  const today = indiaDayBounds(now);
  const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();

  const baseActive = () => supabase.from("follow_up_tasks")
    .select("id", { count: "exact", head: true })
    .eq("organization_id", organizationId)
    .is("deleted_at", null)
    .in("status", OPEN_TASK_STATUSES);

  const byGeo = (geoTag: GeoTag | null, filter: "active" | "overdue" | "unassigned") => {
    let query = supabase.from("follow_up_tasks")
      .select("id,leads!inner(geo_tag)", { count: "exact", head: true })
      .eq("organization_id", organizationId)
      .eq("leads.organization_id", organizationId)
      .is("deleted_at", null)
      .is("leads.deleted_at", null)
      .in("status", OPEN_TASK_STATUSES);
    query = geoTag ? query.eq("leads.geo_tag", geoTag) : query.is("leads.geo_tag", null);
    if (filter === "overdue") query = query.lt("due_at", now.toISOString());
    if (filter === "unassigned") query = query.is("assigned_to", null);
    return query;
  };

  const [activeResult, dueTodayResult, overdueResult, unassignedResult, completedResult, ...geoResults] = await Promise.all([
    baseActive(),
    baseActive().gte("due_at", today.start).lt("due_at", today.end),
    baseActive().lt("due_at", now.toISOString()),
    baseActive().is("assigned_to", null),
    supabase.from("follow_up_tasks").select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId).is("deleted_at", null)
      .eq("status", "completed").gte("completed_at", sevenDaysAgo),
    ...[...GEO_TAGS, null].flatMap((geoTag) => [
      byGeo(geoTag, "active"),
      byGeo(geoTag, "overdue"),
      byGeo(geoTag, "unassigned"),
    ]),
  ]);

  const results = [activeResult, dueTodayResult, overdueResult, unassignedResult, completedResult, ...geoResults];
  if (results.some(failed)) throw new Error("Unable to load follow-up insights. Please try again.");

  const geoTags = [...GEO_TAGS, null] as const;
  const geoRows: GeoFollowUpInsight[] = geoTags.map((geoTag, index) => {
    const offset = index * 3;
    return {
      geoTag,
      active: geoResults[offset].count ?? 0,
      overdue: geoResults[offset + 1].count ?? 0,
      unassigned: geoResults[offset + 2].count ?? 0,
    };
  });

  return {
    generatedAt: now.toISOString(),
    metrics: {
      active: activeResult.count ?? 0,
      dueToday: dueTodayResult.count ?? 0,
      overdue: overdueResult.count ?? 0,
      unassigned: unassignedResult.count ?? 0,
      completedLast7Days: completedResult.count ?? 0,
    } satisfies FollowUpInsightMetrics,
    geoRows,
  };
}
