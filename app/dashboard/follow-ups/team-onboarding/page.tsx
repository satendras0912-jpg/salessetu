import Link from "next/link";
import { redirect } from "next/navigation";

import { saveGeoCoverageOwnerAction } from "./actions";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { GEO_TAG_LABELS } from "@/lib/geo/geo-tag-contract";
import { getGeoCoverageOverview } from "@/lib/geo/geo-coverage-service";
import { createClient } from "@/lib/supabase/server";

type SalesAgent = {
  user_id: string;
  display_name: string | null;
  email: string;
  agent_code: string | null;
  membership_status: string;
  agent_status: string | null;
};

function notice(
  value: string | string[] | undefined,
): string | null {
  const single = Array.isArray(value) ? value[0] : value;
  if (single === "1") return "Manual GEO coverage saved. Auto-routing remains disabled.";
  if (single === "invalid") return "Choose a valid area and active sales agent.";
  if (single === "save") return "Coverage could not be saved. Confirm the database migration is applied and try again.";
  return null;
}

export const dynamic = "force-dynamic";

export default async function GeoTeamOnboardingPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { context } = await requirePermissionAccess({
    allOf: ["organization.manage_members", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/team-onboarding",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    redirect("/unauthorized");
  }

  const organizationId = context.organization?.id;
  if (!organizationId) return null;

  const supabase = await createClient();
  const [overview, agentsResult] = await Promise.all([
    getGeoCoverageOverview(),
    supabase.rpc("list_organization_sales_agents", {
      p_organization_id: organizationId,
    }),
  ]);

  if (agentsResult.error) {
    throw new Error("Sales agents could not be loaded for GEO coverage.");
  }

  const agents = (Array.isArray(agentsResult.data)
    ? agentsResult.data
    : []) as SalesAgent[];
  const activeAgents = agents.filter(
    (agent) =>
      agent.membership_status === "active" &&
      agent.agent_status === "active",
  );
  const message = notice((await searchParams).updated) ?? notice((await searchParams).error);

  return (
    <div className="space-y-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          SalesSetu Operations
        </p>
        <h1 className="mt-3 text-3xl font-bold text-white">GEO Team Coverage</h1>
        <p className="mt-3 max-w-3xl text-slate-400">
          Assign one active SalesSetu agent as the manual owner for each operating area.
          This records responsibility only—new leads and follow-ups stay in the unassigned queue until you deliberately enable routing later.
        </p>
      </header>

      {message ? (
        <div className="rounded-2xl border border-cyan-400/40 bg-cyan-400/10 p-4 text-sm text-cyan-100">
          {message}
        </div>
      ) : null}

      {overview.setupPending ? (
        <section className="rounded-2xl border border-amber-400/40 bg-amber-400/10 p-5 text-sm leading-6 text-amber-100">
          This configuration needs the linked database migration before it can be saved. No routing has been enabled.
        </section>
      ) : null}

      {activeAgents.length === 0 ? (
        <section className="rounded-2xl border border-amber-400/40 bg-amber-400/10 p-6 text-amber-100">
          <h2 className="text-lg font-semibold">No active sales agents available</h2>
          <p className="mt-2 text-sm leading-6">Add or activate a Sales Agent before assigning GEO responsibility.</p>
          <Link href="/dashboard/team" className="mt-4 inline-flex rounded-xl border border-amber-300/50 px-4 py-2 text-sm font-semibold hover:bg-amber-300/10">
            Manage team
          </Link>
        </section>
      ) : (
        <section className="overflow-x-auto rounded-2xl border border-slate-800">
          <table className="w-full text-left text-sm">
            <caption className="sr-only">Manual GEO team coverage configuration</caption>
            <thead className="bg-slate-900 text-slate-400">
              <tr>
                <th scope="col" className="px-5 py-4">Area</th>
                <th scope="col" className="px-5 py-4">Current manual owner</th>
                <th scope="col" className="px-5 py-4">Set responsible agent</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800">
              {overview.queues.map((queue) => (
                <tr key={queue.geoTag} className="bg-slate-900/40">
                  <th scope="row" className="px-5 py-4 font-semibold text-white">
                    {GEO_TAG_LABELS[queue.geoTag]}
                  </th>
                  <td className="px-5 py-4 text-slate-300">
                    {queue.assignmentAgentName ?? "Unassigned manual queue"}
                  </td>
                  <td className="px-5 py-4">
                    <form action={saveGeoCoverageOwnerAction} className="flex min-w-80 items-center gap-2">
                      <input type="hidden" name="geoTag" value={queue.geoTag} />
                      <select
                        name="assigneeUserId"
                        defaultValue={queue.assignmentAgentUserId ?? ""}
                        className="min-w-0 flex-1 rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100"
                      >
                        <option value="">Keep in manual queue</option>
                        {activeAgents.map((agent) => (
                          <option key={agent.user_id} value={agent.user_id}>
                            {[agent.display_name ?? agent.email, agent.agent_code].filter(Boolean).join(" · ")}
                          </option>
                        ))}
                      </select>
                      <button className="rounded-xl border border-cyan-400/60 bg-cyan-400/15 px-3 py-2 font-semibold text-cyan-100 hover:bg-cyan-400/25" type="submit">
                        Save
                      </button>
                    </form>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}

      <section className="rounded-2xl border border-emerald-400/30 bg-emerald-400/10 p-6 text-emerald-100">
        <h2 className="text-lg font-semibold">Pilot safety guard</h2>
        <p className="mt-2 text-sm leading-6">
          Saving a responsibility map never changes task ownership, sends a message, starts a call, or turns on auto-routing. Continue using manual lead assignment during the pilot.
        </p>
      </section>
    </div>
  );
}
