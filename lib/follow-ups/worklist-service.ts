import "server-only";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";
import { indiaDayBounds, OPEN_TASK_STATUSES, PAGE_SIZE, type WorklistFilters } from "./worklist-contract";

export type WorklistTask = {
  id: string; lead_id: string; title: string; follow_up_type: string;
  status: string; priority: string; due_at: string; assigned_to: string | null;
  leads: { first_name: string | null; last_name: string | null };
};

export async function getFollowUpWorklist(filters: WorklistFilters) {
  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups",
    unauthorizedRedirectTo: "/unauthorized",
  });
  const organizationId = context.organization?.id;
  if (!organizationId) throw new Error("An active organization is required.");
  const supabase = await createClient();
  const now = new Date();
  const bounds = indiaDayBounds(now);
  // Signed-in client preserves RLS; both sides of the join are tenant-scoped.
  let query = supabase.from("follow_up_tasks")
    .select("id,lead_id,title,follow_up_type,status,priority,due_at,assigned_to,leads!inner(first_name,last_name)", { count: "exact" })
    .eq("organization_id", organizationId)
    .eq("leads.organization_id", organizationId)
    .is("deleted_at", null)
    .is("leads.deleted_at", null);
  query = filters.view === "completed"
    ? query.eq("status", "completed")
    : query.in("status", OPEN_TASK_STATUSES);
  if (filters.owner === "mine") query = query.eq("assigned_to", context.user.id);
  if (filters.owner === "unassigned") query = query.is("assigned_to", null);
  if (filters.view === "overdue") query = query.lt("due_at", now.toISOString());
  if (filters.view === "today") query = query.gte("due_at", bounds.start).lt("due_at", bounds.end);
  if (filters.view === "upcoming") query = query.gte("due_at", bounds.end);
  const start = (filters.page - 1) * PAGE_SIZE;
  const { data, error, count } = await query
    .order("due_at", { ascending: filters.view !== "completed" })
    .order("id", { ascending: true }).range(start, start + PAGE_SIZE - 1);
  if (error) throw new Error("Unable to load follow-ups. Please try again.");
  return { tasks: (data ?? []) as unknown as WorklistTask[], total: count ?? 0, currentUserId: context.user.id, now: now.toISOString() };
}
