import Link from "next/link";

import { GEO_TAG_LABELS } from "@/lib/geo/geo-tag-contract";
import { getGeoRoutingSimulation } from "@/lib/geo/geo-routing-simulator-service";

export const dynamic = "force-dynamic";

export default async function GeoRoutingSimulatorPage() {
  const simulations = await getGeoRoutingSimulation();
  return <div className="space-y-8">
    <header>
      <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">SalesSetu Operations</p>
      <h1 className="mt-3 text-3xl font-bold text-white">GEO Routing Simulator</h1>
      <p className="mt-3 max-w-3xl text-slate-400">Read-only dry run for unassigned follow-ups. Suggested seats are placeholders and no task is assigned by this page.</p>
    </header>
    <div className="rounded-2xl border border-amber-400/35 bg-amber-400/10 p-5 text-sm leading-6 text-amber-100">Simulation only: coverage seats are examples, routing remains blocked until actual members are onboarded and an area pilot is approved.</div>
    {simulations.length === 0 ? <section className="rounded-2xl border border-slate-800 p-7 text-slate-300">No open unassigned follow-ups are available to simulate.</section> : <section className="overflow-x-auto rounded-2xl border border-slate-800"><table className="w-full text-left text-sm"><caption className="sr-only">GEO routing simulation</caption><thead className="bg-slate-900 text-slate-400"><tr>{["Task / Lead", "GEO", "Suggested seat", "Eligibility", "Action"].map(h => <th key={h} scope="col" className="px-5 py-4">{h}</th>)}</tr></thead><tbody className="divide-y divide-slate-800">{simulations.map(item => <tr key={item.taskId} className="bg-slate-900/40"><td className="px-5 py-4"><p className="font-semibold text-white">{item.taskTitle}</p><p className="mt-1 text-slate-400">{item.leadName}</p></td><td className="px-5 py-4 text-slate-200">{item.geoTag ? GEO_TAG_LABELS[item.geoTag] : "Mapping required"}</td><td className="px-5 py-4 text-slate-200">{item.suggestedSeat ?? "No safe suggestion"}</td><td className="px-5 py-4 text-amber-200">Blocked — dry run</td><td className="px-5 py-4"><Link className="font-semibold text-cyan-300 hover:text-cyan-100" href={`/dashboard/leads/${item.leadId}#follow-up-task-${item.taskId}`}>Open task</Link></td></tr>)}</tbody></table></section>}
    <Link href="/dashboard/follow-ups/team-onboarding" className="inline-flex rounded-xl border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 hover:bg-slate-800">Review example team plan</Link>
  </div>;
}
