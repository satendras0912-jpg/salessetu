import Link from "next/link";

import { GEO_TAG_LABELS } from "@/lib/geo/geo-tag-contract";
import { getFollowUpInsights, type GeoFollowUpInsight } from "@/lib/follow-ups/insights-service";

export const dynamic = "force-dynamic";

const metricCards = [
  ["Active tasks", "active", "text-white", "/dashboard/follow-ups?view=open&owner=all&geo=all&page=1"],
  ["Due today", "dueToday", "text-cyan-200", "/dashboard/follow-ups?view=today&owner=all&geo=all&page=1"],
  ["Overdue", "overdue", "text-amber-300", "/dashboard/follow-ups?view=overdue&owner=all&geo=all&page=1"],
  ["Unassigned", "unassigned", "text-violet-200", "/dashboard/follow-ups?view=open&owner=unassigned&geo=all&page=1"],
  ["Completed (7 days)", "completedLast7Days", "text-emerald-200", "/dashboard/follow-ups?view=completed&owner=all&geo=all&page=1"],
] as const;

function queueHref(row: GeoFollowUpInsight): string {
  const geo = row.geoTag ?? "mapping_required";
  if (row.overdue > 0) return `/dashboard/follow-ups?view=overdue&owner=all&geo=${geo}&page=1`;
  if (row.unassigned > 0) return `/dashboard/follow-ups?view=open&owner=unassigned&geo=${geo}&page=1`;
  return `/dashboard/follow-ups?view=open&owner=all&geo=${geo}&page=1`;
}

function queueLabel(row: GeoFollowUpInsight): string {
  if (row.overdue > 0) return "Review overdue";
  if (row.unassigned > 0) return "Review unassigned";
  return "Open queue";
}

export default async function FollowUpInsightsPage() {
  const result = await getFollowUpInsights();

  return <div className="space-y-8">
    <header className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">SalesSetu Operations</p>
        <h1 className="mt-3 text-3xl font-bold text-white">Follow-up Insights</h1>
        <p className="mt-3 max-w-3xl text-slate-400">Read-only workload visibility by GEO area. Use it to clear overdue work and review queues before any future routing is enabled.</p>
      </div>
      <Link href="/dashboard/follow-ups/sla" className="inline-flex rounded-xl border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-semibold text-cyan-300 hover:border-cyan-400 hover:text-cyan-100">Open SLA alerts</Link>
    </header>

    <section aria-label="Follow-up workload summary" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
      {metricCards.map(([label, key, color, href]) => <Link key={key} href={href} className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 transition hover:border-cyan-400/50 hover:bg-slate-900">
        <p className="text-sm text-slate-400">{label}</p>
        <p className={`mt-2 text-3xl font-bold ${color}`}>{result.metrics[key]}</p>
        <p className="mt-3 text-xs font-semibold text-cyan-300">Open filtered worklist</p>
      </Link>)}
    </section>

    <section className="overflow-x-auto rounded-2xl border border-slate-800">
      <div className="border-b border-slate-800 bg-slate-900/70 px-5 py-4">
        <h2 className="font-semibold text-white">GEO workload</h2>
        <p className="mt-1 text-sm text-slate-400">Active tasks include pending, in-progress, overdue and rescheduled tasks. Overdue uses the current due time.</p>
      </div>
      <table className="w-full text-left text-sm">
        <caption className="sr-only">Follow-up workload by GEO area</caption>
        <thead className="bg-slate-950/70 text-slate-400"><tr>{["GEO area", "Active", "Overdue", "Unassigned", "Priority action"].map((label) => <th key={label} scope="col" className="px-5 py-4">{label}</th>)}</tr></thead>
        <tbody className="divide-y divide-slate-800">
          {result.geoRows.map((row) => <tr key={row.geoTag ?? "mapping_required"} className="bg-slate-900/40">
            <th scope="row" className="px-5 py-4 font-semibold text-white">{row.geoTag ? GEO_TAG_LABELS[row.geoTag] : "GEO mapping required"}</th>
            <td className="px-5 py-4 text-slate-200">{row.active}</td>
            <td className={`px-5 py-4 font-semibold ${row.overdue ? "text-amber-300" : "text-slate-300"}`}>{row.overdue}</td>
            <td className={`px-5 py-4 font-semibold ${row.unassigned ? "text-violet-200" : "text-slate-300"}`}>{row.unassigned}</td>
            <td className="px-5 py-4"><Link className="whitespace-nowrap font-semibold text-cyan-300 hover:text-cyan-100" href={queueHref(row)}>{queueLabel(row)}</Link></td>
          </tr>)}
        </tbody>
      </table>
    </section>

    <p className="text-sm text-slate-500">Completed (7 days) is based on the completion timestamp. This module does not assign tasks, enable GEO routing, or contact customers.</p>
  </div>;
}
