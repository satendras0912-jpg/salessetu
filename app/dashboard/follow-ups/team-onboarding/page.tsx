import Link from "next/link";

import { GEO_TAG_LABELS } from "@/lib/geo/geo-tag-contract";
import { SAMPLE_GEO_TEAM_SEATS } from "@/lib/geo/geo-team-onboarding-contract";

export default function GeoTeamOnboardingPage() {
  return (
    <div className="space-y-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          SalesSetu Operations
        </p>
        <h1 className="mt-3 text-3xl font-bold text-white">GEO Team Onboarding</h1>
        <p className="mt-3 max-w-3xl text-slate-400">
          Example coverage plan for this tenant. These are placeholders only—no
          user account, assignment, task ownership, or auto-routing is created.
        </p>
      </header>

      <section className="grid gap-4 md:grid-cols-2" aria-label="Sample GEO team seats">
        {SAMPLE_GEO_TEAM_SEATS.map((seat) => (
          <article key={seat.code} className="rounded-2xl border border-slate-800 bg-slate-900 p-6">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-lg font-semibold text-white">{seat.code}</h2>
              <span className="rounded-full border border-violet-400/50 bg-violet-400/10 px-3 py-1 text-xs font-semibold text-violet-100">
                {seat.role}
              </span>
            </div>
            <p className="mt-4 text-sm leading-6 text-slate-400">{seat.purpose}</p>
            <div className="mt-4 flex flex-wrap gap-2">
              {seat.coverage.map((geo) => (
                <span key={geo} className="rounded-full border border-slate-700 bg-slate-950 px-3 py-1 text-xs text-slate-200">
                  {GEO_TAG_LABELS[geo]}
                </span>
              ))}
            </div>
          </article>
        ))}
      </section>

      <section className="rounded-2xl border border-amber-400/35 bg-amber-400/10 p-6 text-amber-100">
        <h2 className="text-lg font-semibold">Before activating a real team</h2>
        <p className="mt-2 text-sm leading-6">
          Replace each placeholder with an invited SalesSetu member, verify their
          area coverage, and perform manual assignment checks. Auto-routing stays
          off until you explicitly approve an area-by-area pilot.
        </p>
        <Link href="/dashboard/follow-ups/readiness" className="mt-4 inline-flex rounded-xl border border-amber-300/50 px-4 py-2 text-sm font-semibold hover:bg-amber-300/10">
          Review GEO readiness
        </Link>
      </section>
    </div>
  );
}
