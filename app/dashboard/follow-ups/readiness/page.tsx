import Link from "next/link";

import { GEO_TAG_LABELS } from "@/lib/geo/geo-tag-contract";
import { getGeoReadiness } from "@/lib/geo/geo-readiness-service";

export const dynamic = "force-dynamic";

function worklistHref(geo: string): string {
  return `/dashboard/follow-ups?view=open&owner=unassigned&geo=${geo}&page=1`;
}

export default async function GeoReadinessPage() {
  const {
    rows,
    totalMappedLeads,
    totalMappingRequired,
    totalUnassignedFollowUps,
  } = await getGeoReadiness();

  return (
    <div className="space-y-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          SalesSetu Operations
        </p>
        <h1 className="mt-3 text-3xl font-bold text-white">GEO Readiness</h1>
        <p className="mt-3 max-w-3xl text-slate-400">
          Review mapping coverage and unassigned follow-up backlog by sales area.
          These counts do not activate routing or customer outreach.
        </p>
      </header>

      <section className="grid gap-4 md:grid-cols-3" aria-label="GEO readiness totals">
        <SummaryCard label="Mapped leads" value={totalMappedLeads} tone="cyan" />
        <SummaryCard label="Mapping required" value={totalMappingRequired} tone="amber" />
        <SummaryCard label="Unassigned follow-ups" value={totalUnassignedFollowUps} tone="violet" />
      </section>

      <section className="overflow-x-auto rounded-2xl border border-slate-800">
        <table className="w-full text-left text-sm">
          <caption className="sr-only">Area-by-area GEO readiness</caption>
          <thead className="bg-slate-900 text-slate-400">
            <tr>
              {['GEO area', 'Mapped leads', 'Unassigned follow-ups', 'Action'].map((heading) => (
                <th key={heading} scope="col" className="px-5 py-4">{heading}</th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800">
            {rows.map((row) => {
              const geo = row.geoTag ?? "mapping_required";
              const label = row.geoTag ? GEO_TAG_LABELS[row.geoTag] : "GEO mapping required";
              return (
                <tr key={geo} className="bg-slate-900/40">
                  <th scope="row" className="px-5 py-4 font-semibold text-white">{label}</th>
                  <td className="px-5 py-4 text-slate-200">{row.mappedLeadCount}</td>
                  <td className="px-5 py-4 text-slate-200">{row.unassignedFollowUpCount}</td>
                  <td className="px-5 py-4">
                    <Link className="font-semibold text-cyan-300 hover:text-cyan-100" href={worklistHref(geo)}>
                      Open queue
                    </Link>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </section>

      <section className="rounded-2xl border border-cyan-500/30 bg-cyan-500/5 p-6">
        <h2 className="text-lg font-semibold text-white">Recommended next action</h2>
        <p className="mt-2 text-sm leading-6 text-slate-300">
          Clear the mapping-required backlog first. Then review each unassigned
          area queue before configuring team coverage.
        </p>
        <Link
          href="/dashboard/follow-ups/geo-mapping"
          className="mt-4 inline-flex rounded-xl border border-cyan-400/60 bg-cyan-400/15 px-4 py-2 text-sm font-semibold text-cyan-100 hover:bg-cyan-400/25"
        >
          Open GEO mapping inbox
        </Link>
      </section>
    </div>
  );
}

function SummaryCard({
  label,
  value,
  tone,
}: {
  label: string;
  value: number;
  tone: "cyan" | "amber" | "violet";
}) {
  const styles = {
    cyan: "border-cyan-500/30 bg-cyan-500/5 text-cyan-200",
    amber: "border-amber-500/30 bg-amber-500/5 text-amber-200",
    violet: "border-violet-500/30 bg-violet-500/5 text-violet-200",
  };

  return (
    <article className={`rounded-2xl border p-5 ${styles[tone]}`}>
      <p className="text-sm font-medium">{label}</p>
      <p className="mt-3 text-4xl font-bold text-white">{value}</p>
    </article>
  );
}
