import Link from "next/link";
import { getFollowUpWorklist } from "@/lib/follow-ups/worklist-service";
import { parseWorklistFilters, worklistHref, PAGE_SIZE, WORKLIST_VIEWS } from "@/lib/follow-ups/worklist-contract";

export const dynamic = "force-dynamic";
const viewLabels = { open: "All open", overdue: "Overdue", today: "Due today", upcoming: "Upcoming", completed: "Completed" };
const dateFormat = new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", dateStyle: "medium", timeStyle: "short" });
const control = "rounded-xl border border-slate-700 bg-slate-900 px-4 py-2 text-sm text-slate-200";

export default async function FollowUpWorklistPage({ searchParams }: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const filters = parseWorklistFilters(await searchParams);
  const result = await getFollowUpWorklist(filters);
  const totalPages = Math.max(1, Math.ceil(result.total / PAGE_SIZE));
  return <div className="space-y-6">
    <header>
      <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">SalesSetu Operations</p>
      <h1 className="mt-3 text-3xl font-bold text-white">Follow-up Worklist</h1>
      <p className="mt-3 text-slate-400">Prioritize customer callbacks, project details and next steps across your accessible leads.</p>
    </header>
    <nav aria-label="Follow-up views" className="flex flex-wrap gap-2">
      {WORKLIST_VIEWS.map(view => <Link key={view} href={worklistHref({ ...filters, view, page: 1 })}
        aria-current={filters.view === view ? "page" : undefined}
        className={`${control} ${filters.view === view ? "border-cyan-500 text-cyan-300" : ""}`}>
        {viewLabels[view]}
      </Link>)}
    </nav>
    <form className="flex flex-wrap items-end gap-3" action="/dashboard/follow-ups">
      <input type="hidden" name="view" value={filters.view} />
      <label className="grid gap-2 text-sm text-slate-400">Assignment
        <select name="owner" defaultValue={filters.owner} className={control}>
          <option value="all">All accessible tasks</option><option value="mine">Assigned to me</option><option value="unassigned">Unassigned</option>
        </select>
      </label>
      <button className={control} type="submit">Apply filter</button>
      <Link href={worklistHref(filters)} className={control}>Refresh</Link>
    </form>
    <p className="text-sm text-slate-400">{result.total} matching tasks · Times in IST · Overdue means the due time has passed. Due today includes overdue tasks from today.</p>
    {result.tasks.length === 0 ? <div className="rounded-2xl border border-slate-800 p-8 text-slate-300">
      <p>{result.total ? "No tasks on this page." : "No follow-ups match this view."}</p>
      <Link className="mt-3 inline-block text-cyan-300" href={result.total ? worklistHref(filters, 1) : "/dashboard/leads"}>
        {result.total ? "Go to first page" : "Open leads to create a follow-up"}
      </Link>
    </div> : <div className="overflow-x-auto rounded-2xl border border-slate-800">
      <table className="w-full text-left text-sm">
        <caption className="sr-only">{viewLabels[filters.view]} follow-up tasks</caption>
        <thead className="bg-slate-900 text-slate-400"><tr>{["Task / Lead", "Due (IST)", "Status / Priority", "Assignment", "Action"].map(label => <th key={label} scope="col" className="px-5 py-4">{label}</th>)}</tr></thead>
        <tbody className="divide-y divide-slate-800">{result.tasks.map(task => {
          const overdue = task.status !== "completed" && Date.parse(task.due_at) < Date.parse(result.now);
          return <tr key={task.id} className="bg-slate-900/40">
            <td className="max-w-sm px-5 py-4"><p className="break-words font-semibold text-white">{task.title}</p><p className="mt-1 text-slate-400">{[task.leads.first_name, task.leads.last_name].filter(Boolean).join(" ") || "Unnamed lead"} · {task.follow_up_type.replaceAll("_", " ")}</p></td>
            <td className="whitespace-nowrap px-5 py-4"><time dateTime={task.due_at}>{dateFormat.format(new Date(task.due_at))}</time>{overdue && <p className="mt-1 text-amber-300">Overdue</p>}</td>
            <td className="px-5 py-4"><p className="capitalize">{task.status.replaceAll("_", " ")}</p><p className="mt-1 capitalize text-slate-400">{task.priority}</p></td>
            <td className="px-5 py-4">{!task.assigned_to ? "Unassigned" : task.assigned_to === result.currentUserId ? "You" : "Team member"}</td>
            <td className="px-5 py-4"><Link className="whitespace-nowrap font-semibold text-cyan-300" href={`/dashboard/leads/${task.lead_id}`}>Open lead</Link></td>
          </tr>;
        })}</tbody>
      </table>
    </div>}
    <nav aria-label="Follow-up pagination" className="flex items-center justify-between gap-4">
      {filters.page > 1 ? <Link className={control} href={worklistHref(filters, filters.page - 1)}>Previous</Link> : <span />}
      <span className="text-sm text-slate-400">Page {filters.page} of {totalPages}</span>
      {filters.page < totalPages ? <Link className={control} href={worklistHref(filters, filters.page + 1)}>Next</Link> : <span />}
    </nav>
    <p className="text-sm text-slate-500">Open a lead to complete, reschedule or assign a follow-up using your existing permissions.</p>
  </div>;
}
