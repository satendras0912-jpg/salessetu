import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";
import { indiaDayBounds, OPEN_TASK_STATUSES } from "./worklist-contract";

type SlaAlertTask = {
  id: string;
  lead_id: string;
  title: string;
  due_at: string;
  sla_due_at: string | null;
  status: string;
  sla_status: string;
  priority: string;
  assigned_to: string | null;
  leads: { first_name: string | null; last_name: string | null };
};

function isQueryFailure(error: { message?: string } | null) {
  return Boolean(error);
}

export async function getFollowUpSlaDashboard() {
  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/sla",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    throw new Error("An active organization is required.");
  }

  const supabase = await createClient();
  const now = new Date();
  const bounds = indiaDayBounds(now);
  const active = OPEN_TASK_STATUSES;

  const [
    openResult,
    dueTodayResult,
    overdueResult,
    atRiskResult,
    breachedResult,
    unassignedResult,
    alertsResult,
  ] = await Promise.all([
    supabase.from("follow_up_tasks").select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId).is("deleted_at", null).in("status", active),
    supabase.from("follow_up_tasks").select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId).is("deleted_at", null).in("status", active)
      .gte("due_at", bounds.start).lt("due_at", bounds.end),
    supabase.from("follow_up_tasks").select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId).is("deleted_at", null).eq("status", "overdue"),
    supabase.from("follow_up_tasks").select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId).is("deleted_at", null).in("status", active)
      .eq("sla_status", "at_risk"),
    supabase.from("follow_up_tasks").select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId).is("deleted_at", null).in("status", active)
      .eq("sla_status", "breached"),
    supabase.from("follow_up_tasks").select("id", { count: "exact", head: true })
      .eq("organization_id", organizationId).is("deleted_at", null).in("status", active)
      .is("assigned_to", null),
    supabase.from("follow_up_tasks")
      .select("id,lead_id,title,due_at,sla_due_at,status,sla_status,priority,assigned_to,leads!inner(first_name,last_name)")
      .eq("organization_id", organizationId).eq("leads.organization_id", organizationId)
      .is("deleted_at", null).is("leads.deleted_at", null).in("status", active)
      .or("status.eq.overdue,sla_status.in.(at_risk,breached)")
      .order("sla_due_at", { ascending: true, nullsFirst: false })
      .order("due_at", { ascending: true }).order("id", { ascending: true }).limit(50),
  ]);

  const results = [openResult, dueTodayResult, overdueResult, atRiskResult, breachedResult, unassignedResult, alertsResult];

  if (results.some((result) => isQueryFailure(result.error))) {
    throw new Error("Unable to load SLA alerts. Please try again.");
  }

  return {
    now: now.toISOString(),
    metrics: {
      open: openResult.count ?? 0,
      dueToday: dueTodayResult.count ?? 0,
      overdue: overdueResult.count ?? 0,
      atRisk: atRiskResult.count ?? 0,
      breached: breachedResult.count ?? 0,
      unassigned: unassignedResult.count ?? 0,
    },
    alerts: (alertsResult.data ?? []) as unknown as SlaAlertTask[],
  };
}
