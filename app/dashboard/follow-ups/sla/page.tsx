import Link from "next/link";

import { getFollowUpSlaDashboard } from "@/lib/follow-ups/sla-dashboard-service";

export const dynamic = "force-dynamic";

const dateFormat = new Intl.DateTimeFormat("en-IN", {
  timeZone: "Asia/Kolkata",
  dateStyle: "medium",
  timeStyle: "short",
});

const metricCards = [
  ["Open tasks", "open", "text-white"],
  ["Due today", "dueToday", "text-cyan-200"],
  ["Overdue", "overdue", "text-amber-300"],
  ["At risk", "atRisk", "text-orange-300"],
  ["SLA breached", "breached", "text-rose-300"],
  ["Unassigned", "unassigned", "text-violet-300"],
] as const;

function alertLabel(status: string, slaStatus: string) {
  if (slaStatus === "breached") return "SLA breached";
  if (slaStatus === "at_risk") return "SLA at risk";
  return status === "overdue" ? "Overdue" : "Needs attention";
}

export default async function FollowUpSlaDashboardPage() {
  const result = await getFollowUpSlaDashboard();

  return <div className="space-y-6">
    <header className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">SalesSetu Operations</p>
        <h1 className="mt-3 text-3xl font-bold text-white">Follow-up SLA Alerts</h1>
        <p className="mt-3 max-w-3xl text-slate-400">Manager visibility for active callbacks and site-visit next steps. Completed, cancelled and failed tasks are excluded.</p>
      </div>
      <Link href="/dashboard/follow-ups" className="inline-flex rounded-xl border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-semibold text-cyan-300 hover:border-cyan-400 hover:text-cyan-100">Open worklist</Link>
    </header>

    <section aria-label="SLA summary" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
      {metricCards.map(([label, key, color]) => <article key={key} className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
        <p className="text-sm text-slate-400">{label}</p>
        <p className={"mt-2 text-3xl font-bold " + color}>{result.metrics[key]}</p>
      </article>)}
    </section>

    <section className="overflow-x-auto rounded-2xl border border-slate-800">
      <div className="border-b border-slate-800 bg-slate-900/70 px-5 py-4">
        <h2 className="font-semibold text-white">Action queue</h2>
        <p className="mt-1 text-sm text-slate-400">Sorted by SLA deadline, then due time. Times in IST.</p>
      </div>
      {result.alerts.length === 0 ? <div className="p-8 text-slate-300">No overdue, at-risk or breached active follow-ups.</div> :
        <table className="w-full text-left text-sm">
          <caption className="sr-only">Active follow-up SLA alerts</caption>
          <thead className="bg-slate-950/70 text-slate-400"><tr>{["Alert", "Task / Lead", "SLA deadline", "Due", "Assignment", "Action"].map((label) => <th key={label} scope="col" className="px-5 py-4">{label}</th>)}</tr></thead>
          <tbody className="divide-y divide-slate-800">{result.alerts.map((task) => <tr key={task.id} className="bg-slate-900/40">
            <td className="whitespace-nowrap px-5 py-4 font-semibold text-amber-300">{alertLabel(task.status, task.sla_status)}</td>
            <td className="max-w-sm px-5 py-4"><p className="font-semibold text-white">{task.title}</p><p className="mt-1 text-slate-400">{[task.leads.first_name, task.leads.last_name].filter(Boolean).join(" ") || "Unnamed lead"} · {task.priority}</p></td>
            <td className="whitespace-nowrap px-5 py-4">{task.sla_due_at ? <time dateTime={task.sla_due_at}>{dateFormat.format(new Date(task.sla_due_at))}</time> : "Not set"}</td>
            <td className="whitespace-nowrap px-5 py-4"><time dateTime={task.due_at}>{dateFormat.format(new Date(task.due_at))}</time></td>
            <td className="px-5 py-4">{task.assigned_to ? "Assigned" : "Unassigned"}</td>
            <td className="px-5 py-4"><Link className="whitespace-nowrap font-semibold text-cyan-300 hover:text-cyan-100" href={`/dashboard/leads/${task.lead_id}#follow-up-task-${task.id}`}>Open task actions</Link></td>
          </tr>)}</tbody>
        </table>}
    </section>
    <p className="text-sm text-slate-500">Status changes are set by the existing five-minute overdue processor. This dashboard does not bypass follow-up assignment, rescheduling or completion controls.</p>
  </div>;
}
