import Link from "next/link";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { GEO_TAGS } from "@/lib/geo/geo-tag-contract";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type ChecklistStep = {
  title: string;
  description: string;
  href: string;
  action: string;
  complete: boolean;
};

export default async function PilotLaunchPage() {
  const { context } = await requirePermissionAccess({
    allOf: ["dashboard.view"],
    loginRedirectTo: "/login?next=/dashboard/pilot-launch",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    return null;
  }

  const supabase = await createClient();
  const [agentsResult, projectsResult, inventoryResult, leadsResult, coverageResult] =
    await Promise.all([
      supabase.rpc("list_organization_sales_agents", {
        p_organization_id: organizationId,
      }),
      supabase
        .from("projects")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .is("deleted_at", null),
      supabase
        .from("inventory_units")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .is("deleted_at", null),
      supabase
        .from("leads")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .is("deleted_at", null),
      supabase
        .from("geo_coverage_queues")
        .select("id", { count: "exact", head: true })
        .eq("organization_id", organizationId)
        .eq("status", "active")
        .eq("auto_assignment_enabled", false)
        .not("assignment_agent_profile_id", "is", null),
    ]);

  const activeAgents = Array.isArray(agentsResult.data)
    ? agentsResult.data.filter((agent) => agent.status !== "removed").length
    : 0;
  const projectCount = projectsResult.count ?? 0;
  const inventoryCount = inventoryResult.count ?? 0;
  const leadCount = leadsResult.count ?? 0;
  const configuredCoverageCount = coverageResult.error
    ? 0
    : coverageResult.count ?? 0;

  const steps: ChecklistStep[] = [
    {
      title: "Invite the pilot sales team",
      description:
        "Add the owner and sales agents who will work the pilot. Roles and access remain tenant-scoped.",
      href: "/dashboard/team",
      action: "Manage team",
      complete: activeAgents > 0,
    },
    {
      title: "Add a project and available inventory",
      description:
        "Create the project first, then add or import the units the team can actually sell.",
      href: "/dashboard/inventory",
      action: "Set up inventory",
      complete: projectCount > 0 && inventoryCount > 0,
    },
    {
      title: "Check follow-up SLA and coverage",
      description:
        "Review overdue rules, map each operating area to a responsible team member, and keep routing manual for the pilot.",
      href: "/dashboard/follow-ups/team-onboarding",
      action: "Configure coverage",
      complete: configuredCoverageCount === GEO_TAGS.length,
    },
    {
      title: "Run a controlled test enquiry",
      description:
        "Submit one consented test from the public demo form, validate it, then confirm the manual assignment and follow-up flow.",
      href: "/?utm_source=pilot-onboarding&utm_medium=qa&utm_campaign=tenant-readiness#demo",
      action: "Open test form",
      complete: leadCount > 0,
    },
  ];

  const completedCount = steps.filter((step) => step.complete).length;
  const organizationName =
    context.organization?.name ?? "This workspace";

  return (
    <div className="space-y-8">
      <header className="flex flex-col gap-5 xl:flex-row xl:items-end xl:justify-between">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            Pilot onboarding
          </p>
          <h1 className="mt-3 text-3xl font-bold tracking-tight text-white sm:text-4xl">
            Launch {organizationName} safely
          </h1>
          <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-400">
            A reusable owner checklist for getting a new SalesSetu tenant ready.
            It does not create customers, send messages, or auto-assign leads.
          </p>
        </div>

        <div className="rounded-2xl border border-cyan-400/30 bg-cyan-400/10 px-5 py-4 text-sm text-cyan-100">
          <span className="font-semibold">{completedCount}/4 setup signals found</span>
          <p className="mt-1 text-cyan-200/75">Complete the open steps before real lead intake.</p>
        </div>
      </header>

      <section className="grid gap-4 md:grid-cols-3">
        {[
          ["Active sales agents", activeAgents],
          ["Projects configured", projectCount],
          ["Available inventory records", inventoryCount],
        ].map(([label, value]) => (
          <article
            key={label as string}
            className="rounded-2xl border border-slate-800 bg-slate-900/70 p-6"
          >
            <p className="text-sm text-slate-500">{label}</p>
            <p className="mt-3 text-3xl font-bold text-white">{value}</p>
          </article>
        ))}
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-5 sm:p-7">
        <div className="flex flex-col gap-2 border-b border-slate-800 pb-5">
          <h2 className="text-xl font-bold text-white">Pilot launch checklist</h2>
          <p className="text-sm text-slate-400">
            Use this sequence for every broker or builder pilot. Each link opens an existing protected SalesSetu workflow.
          </p>
        </div>

        <ol className="mt-2 divide-y divide-slate-800">
          {steps.map((step, index) => (
            <li key={step.title} className="flex flex-col gap-4 py-6 lg:flex-row lg:items-center lg:justify-between">
              <div className="flex gap-4">
                <span
                  aria-label={step.complete ? "Complete" : "Pending"}
                  className={[
                    "flex h-8 w-8 shrink-0 items-center justify-center rounded-full border text-sm font-bold",
                    step.complete
                      ? "border-emerald-400/50 bg-emerald-400/10 text-emerald-300"
                      : "border-slate-700 bg-slate-950 text-slate-400",
                  ].join(" ")}
                >
                  {step.complete ? "✓" : index + 1}
                </span>
                <div>
                  <h3 className="font-semibold text-white">{step.title}</h3>
                  <p className="mt-1 max-w-2xl text-sm leading-6 text-slate-400">
                    {step.description}
                  </p>
                </div>
              </div>

              <Link
                href={step.href}
                className="inline-flex shrink-0 items-center justify-center rounded-xl border border-cyan-400/40 px-4 py-2.5 text-sm font-semibold text-cyan-200 transition hover:border-cyan-300 hover:bg-cyan-400/10"
              >
                {step.action}
              </Link>
            </li>
          ))}
        </ol>
      </section>

      <section className="rounded-2xl border border-amber-400/30 bg-amber-400/10 p-5 text-sm leading-6 text-amber-100">
        <span className="font-semibold">Go-live guard:</span> real lead routing stays manual until the workspace owner verifies the test enquiry, validation decision, assignment, and follow-up completion.
      </section>
    </div>
  );
}
