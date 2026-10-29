import Link from "next/link";

import {
  GEO_TAG_LABELS,
  geoCoverageQueueLabel,
  geoCoverageStatusLabel,
} from "@/lib/geo/geo-coverage-contract";
import { getGeoCoverageOverview } from "@/lib/geo/geo-coverage-service";

export const dynamic = "force-dynamic";

function statusClass(status: string): string {
  if (status === "active") {
    return "border-emerald-400/50 bg-emerald-400/10 text-emerald-100";
  }

  if (status === "paused") {
    return "border-amber-400/50 bg-amber-400/10 text-amber-100";
  }

  return "border-slate-600 bg-slate-800 text-slate-200";
}

export default async function GeoCoveragePage() {
  const { queues, setupPending } = await getGeoCoverageOverview();

  return (
    <div className="space-y-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          SalesSetu Operations
        </p>
        <h1 className="mt-3 text-3xl font-bold text-white">
          GEO Coverage
        </h1>
        <p className="mt-3 max-w-3xl text-slate-400">
          Area-wise follow-up queues are ready for team coverage. New tasks remain
          unassigned until a team is deliberately mapped and routing is activated.
        </p>
        <Link href="/dashboard/follow-ups/readiness" className="mt-4 inline-flex rounded-xl border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 hover:bg-slate-800">
          View GEO readiness
        </Link>
        <Link href="/dashboard/follow-ups/team-onboarding" className="ml-3 mt-4 inline-flex rounded-xl border border-violet-400/50 bg-violet-400/10 px-4 py-2 text-sm font-semibold text-violet-100 hover:bg-violet-400/20">
          View example team plan
        </Link>
      </header>

      {setupPending ? (
        <div className="rounded-2xl border border-amber-400/40 bg-amber-400/10 p-5 text-sm text-amber-100">
          Coverage records are waiting for the database setup. The worklist remains
          safe in unassigned-queue mode until that setup is applied.
        </div>
      ) : null}

      <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-3" aria-label="GEO coverage queues">
        {queues.map((queue) => (
          <article
            key={queue.geoTag}
            className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
          >
            <div className="flex items-start justify-between gap-3">
              <h2 className="text-lg font-semibold text-white">
                {GEO_TAG_LABELS[queue.geoTag]}
              </h2>
              <span className={`rounded-full border px-3 py-1 text-xs font-semibold ${statusClass(queue.status)}`}>
                {geoCoverageStatusLabel(queue.status)}
              </span>
            </div>
            <p className="mt-4 text-sm font-medium text-slate-200">
              {geoCoverageQueueLabel(queue)}
            </p>
            <p className="mt-2 text-sm leading-6 text-slate-400">
              {queue.autoAssignmentEnabled
                ? "Auto-routing is active for this coverage queue."
                : "Auto-routing is disabled. Add the responsible team and activate routing only when members are ready."}
            </p>
          </article>
        ))}
      </section>

      <section className="rounded-2xl border border-cyan-500/30 bg-cyan-500/5 p-6">
        <h2 className="text-lg font-semibold text-white">Current operating rule</h2>
        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-300">
          Until team members are added, every GEO queue stays in draft and routes
          follow-ups to the unassigned team queue for human review. No scheduler,
          call, message, or customer outreach is enabled here.
        </p>
        <Link
          href="/dashboard/follow-ups/geo-mapping"
          className="mt-4 inline-flex rounded-xl border border-cyan-400/60 bg-cyan-400/15 px-4 py-2 text-sm font-semibold text-cyan-100 transition hover:bg-cyan-400/25"
        >
          Open GEO mapping inbox
        </Link>
      </section>
    </div>
  );
}
