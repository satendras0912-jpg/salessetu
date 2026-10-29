import Link from "next/link";

import { getLeadAttributionDashboard, type AttributionRow } from "@/lib/analytics/lead-attribution-service";

export const dynamic = "force-dynamic";

function percentage(numerator: number, denominator: number) {
  if (!denominator) return "—";
  return `${Math.round((numerator / denominator) * 100)}%`;
}

function AttributionTable({ title, rows }: { title: string; rows: AttributionRow[] }) {
  return <section className="overflow-x-auto rounded-2xl border border-slate-800">
    <div className="border-b border-slate-800 bg-slate-900/70 px-5 py-4"><h2 className="font-semibold text-white">{title}</h2><p className="mt-1 text-sm text-slate-400">Each outcome is a distinct lead in the 90-day cohort, not a count of activities.</p></div>
    {rows.length === 0 ? <p className="p-6 text-sm text-slate-300">No lead attribution data in this cohort.</p> : <table className="w-full text-left text-sm">
      <caption className="sr-only">{title}</caption>
      <thead className="bg-slate-950/70 text-slate-400"><tr>{["Attribution", "Leads", "Qualified", "Follow-up", "Site visit", "Deal", "Won", "Lead → won"].map((label) => <th key={label} scope="col" className="px-5 py-4">{label}</th>)}</tr></thead>
      <tbody className="divide-y divide-slate-800">{rows.slice(0, 12).map((row) => <tr key={row.label} className="bg-slate-900/40">
        <th scope="row" className="max-w-xs px-5 py-4 font-semibold text-white">{row.label}</th><td className="px-5 py-4">{row.leads}</td><td className="px-5 py-4">{row.qualified}</td><td className="px-5 py-4">{row.followUpReached}</td><td className="px-5 py-4">{row.siteVisitReached}</td><td className="px-5 py-4">{row.dealReached}</td><td className="px-5 py-4 font-semibold text-emerald-200">{row.won}</td><td className="px-5 py-4 text-cyan-200">{percentage(row.won, row.leads)}</td>
      </tr>)}</tbody>
    </table>}
  </section>;
}

export default async function LeadAttributionPage() {
  const result = await getLeadAttributionDashboard();
  const periodStart = new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "Asia/Kolkata" }).format(new Date(result.cohortStart));
  const cards = [["Leads", result.totals.leads, "text-white"], ["Qualified", result.totals.qualified, "text-cyan-200"], ["Follow-up reached", result.totals.followUpReached, "text-violet-200"], ["Site visit reached", result.totals.siteVisitReached, "text-amber-200"], ["Deals", result.totals.dealReached, "text-orange-200"], ["Won", result.totals.won, "text-emerald-200"]] as const;
  return <div className="space-y-8">
    <header className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between"><div><p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">SalesSetu Analytics</p><h1 className="mt-3 text-3xl font-bold text-white">Lead Source & Conversion Attribution</h1><p className="mt-3 max-w-3xl text-slate-400">Read-only marketing-to-revenue visibility for leads created since {periodStart}. Attribution is scoped to the active organization.</p></div><Link href="/dashboard/leads" className="inline-flex rounded-xl border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-semibold text-cyan-300 hover:border-cyan-400 hover:text-cyan-100">Open lead operations</Link></header>
    <section aria-label="Attribution totals" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">{cards.map(([label, value, color]) => <article key={label} className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5"><p className="text-sm text-slate-400">{label}</p><p className={`mt-2 text-3xl font-bold ${color}`}>{value}</p></article>)}</section>
    <AttributionTable title="By source" rows={result.bySource} />
    <AttributionTable title="By campaign" rows={result.byCampaign} />
    <AttributionTable title="By GEO area" rows={result.byGeo} />
    <p className="text-sm text-slate-500">No advertising platform, routing, assignment, or customer communication action is performed by this dashboard.</p>
  </div>;
}
