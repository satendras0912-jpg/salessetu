import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";
import {
  indiaDayBounds,
  OPEN_SITE_VISIT_STATUSES,
  SITE_VISIT_PAGE_SIZE,
  type SiteVisitWorklistFilters,
} from "./worklist-contract";

export type SiteVisitWorklistItem = {
  id: string;
  lead_id: string;
  title: string;
  visit_type: string;
  status: string;
  confirmation_status: string;
  priority: string;
  project_name: string;
  visit_city: string | null;
  scheduled_start_at: string;
  assigned_agent_id: string | null;
  leads: {
    first_name: string | null;
    last_name: string | null;
    geo_tag: string | null;
    preferred_location: string | null;
    preferred_city: string | null;
  };
};

export async function getSiteVisitWorklist(filters: SiteVisitWorklistFilters) {
  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "site_visits.view"],
    loginRedirectTo: "/login?next=/dashboard/site-visits",
    unauthorizedRedirectTo: "/unauthorized",
  });
  const organizationId = context.organization?.id;
  if (!organizationId) throw new Error("An active organization is required.");

  const supabase = await createClient();
  const now = new Date();
  const today = indiaDayBounds(now);

  let query = supabase.from("site_visits")
    .select("id,lead_id,title,visit_type,status,confirmation_status,priority,project_name,visit_city,scheduled_start_at,assigned_agent_id,leads!inner(first_name,last_name,geo_tag,preferred_location,preferred_city)", { count: "exact" })
    .eq("organization_id", organizationId)
    .eq("leads.organization_id", organizationId)
    .is("deleted_at", null)
    .is("leads.deleted_at", null);

  query = filters.view === "completed"
    ? query.eq("status", "completed")
    : query.in("status", OPEN_SITE_VISIT_STATUSES);
  if (filters.geo === "mapping_required") query = query.is("leads.geo_tag", null);
  if (filters.geo !== "all" && filters.geo !== "mapping_required") query = query.eq("leads.geo_tag", filters.geo);
  if (filters.view === "today") query = query.gte("scheduled_start_at", today.start).lt("scheduled_start_at", today.end);
  if (filters.view === "upcoming") query = query.gte("scheduled_start_at", today.end);
  if (filters.view === "overdue") query = query.lt("scheduled_start_at", now.toISOString());

  const start = (filters.page - 1) * SITE_VISIT_PAGE_SIZE;
  const { data, error, count } = await query
    .order("scheduled_start_at", { ascending: filters.view !== "completed" })
    .order("id", { ascending: true })
    .range(start, start + SITE_VISIT_PAGE_SIZE - 1);
  if (error) throw new Error("Unable to load site visits. Please try again.");

  return {
    visits: (data ?? []) as unknown as SiteVisitWorklistItem[],
    total: count ?? 0,
    now: now.toISOString(),
  };
}
