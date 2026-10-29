import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { OPEN_TASK_STATUSES } from "@/lib/follow-ups/worklist-contract";
import { createClient } from "@/lib/supabase/server";

import { SAMPLE_GEO_TEAM_SEATS } from "./geo-team-onboarding-contract";
import { deriveGeoTag, type GeoTag } from "./geo-tag-contract";

type TaskRow = {
  id: string;
  lead_id: string;
  title: string;
  due_at: string;
  leads: {
    first_name: string | null;
    last_name: string | null;
    geo_tag: string | null;
    preferred_location: string | null;
    preferred_city: string | null;
  };
};

export type RoutingSimulation = {
  taskId: string;
  leadId: string;
  taskTitle: string;
  leadName: string;
  geoTag: GeoTag | null;
  suggestedSeat: string | null;
};

function seatFor(geoTag: GeoTag | null): string | null {
  if (!geoTag) return null;
  return SAMPLE_GEO_TEAM_SEATS.find((seat) => seat.coverage.includes(geoTag))?.code ?? null;
}

export async function getGeoRoutingSimulation(): Promise<RoutingSimulation[]> {
  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/routing-simulator",
    unauthorizedRedirectTo: "/unauthorized",
  });
  const organizationId = context.organization?.id;
  if (!organizationId) throw new Error("An active organization is required.");

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("follow_up_tasks")
    .select("id,lead_id,title,due_at,leads!inner(first_name,last_name,geo_tag,preferred_location,preferred_city)")
    .eq("organization_id", organizationId)
    .eq("leads.organization_id", organizationId)
    .is("deleted_at", null)
    .is("leads.deleted_at", null)
    .is("assigned_to", null)
    .in("status", OPEN_TASK_STATUSES)
    .order("due_at", { ascending: true })
    .limit(50);

  if (error) throw new Error("Unable to load routing simulation.");

  return ((data ?? []) as unknown as TaskRow[]).map((task) => {
    const geoTag = (task.leads.geo_tag as GeoTag | null) ?? deriveGeoTag(
      task.leads.preferred_location,
      task.leads.preferred_city,
    );
    const leadName = [task.leads.first_name, task.leads.last_name]
      .filter(Boolean)
      .join(" ") || "Unnamed lead";
    return {
      taskId: task.id,
      leadId: task.lead_id,
      taskTitle: task.title,
      leadName,
      geoTag,
      suggestedSeat: seatFor(geoTag),
    };
  });
}
