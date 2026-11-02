import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";
import {
  indiaDayBounds,
  OPEN_SITE_VISIT_STATUSES,
  SITE_VISIT_PAGE_SIZE,
  type SiteVisitWorklistFilters,
} from "./worklist-contract";

type AssignmentAgentRow = {
  user_id: string;
  agent_code: string | null;
  display_name: string | null;
};

export type SiteVisitWorklistAgent = {
  userId: string;
  displayName: string;
  agentCode: string | null;
};

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
  assigned_agent_name: string | null;
  leads: {
    first_name: string | null;
    last_name: string | null;
    geo_tag: string | null;
    preferred_location: string | null;
    preferred_city: string | null;
  };
};

function getAgentDisplayName(row: AssignmentAgentRow) {
  return row.display_name?.trim() || row.agent_code?.trim() || `Agent ${row.user_id.slice(0, 8)}`;
}

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
  if (filters.agent === "unassigned") query = query.is("assigned_agent_id", null);
  if (filters.agent !== "all" && filters.agent !== "unassigned") query = query.eq("assigned_agent_id", filters.agent);
  if (filters.view === "today") query = query.gte("scheduled_start_at", today.start).lt("scheduled_start_at", today.end);
  if (filters.view === "upcoming") query = query.gte("scheduled_start_at", today.end);
  if (filters.view === "overdue") query = query.lt("scheduled_start_at", now.toISOString());

  const start = (filters.page - 1) * SITE_VISIT_PAGE_SIZE;
  const [visitResult, agentResult] = await Promise.all([
    query
      .order("scheduled_start_at", { ascending: filters.view !== "completed" })
      .order("id", { ascending: true })
      .range(start, start + SITE_VISIT_PAGE_SIZE - 1),
    supabase
      .from("assignment_agent_profiles")
      .select("user_id,agent_code,display_name")
      .eq("organization_id", organizationId)
      .eq("status", "active")
      .order("display_name", { ascending: true, nullsFirst: false }),
  ]);
  if (visitResult.error) throw new Error("Unable to load site visits. Please try again.");
  if (agentResult.error) throw new Error("Unable to load active agents. Please try again.");

  const agents = ((agentResult.data ?? []) as unknown as AssignmentAgentRow[])
    .map((row) => ({
      userId: row.user_id,
      displayName: getAgentDisplayName(row),
      agentCode: row.agent_code,
    }))
    .sort((left, right) => left.displayName.localeCompare(right.displayName, "en-IN"));
  const agentNames = new Map(agents.map((agent) => [agent.userId, agent.displayName]));
  const visits = ((visitResult.data ?? []) as unknown as Omit<SiteVisitWorklistItem, "assigned_agent_name">[])
    .map((visit) => ({
      ...visit,
      assigned_agent_name: visit.assigned_agent_id
        ? agentNames.get(visit.assigned_agent_id) ?? "Unavailable agent"
        : null,
    }));

  return {
    visits,
    agents,
    total: visitResult.count ?? 0,
    now: now.toISOString(),
  };
}
