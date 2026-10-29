import Link from "next/link";

import { GEO_TAG_LABELS, GEO_TAGS } from "@/lib/geo/geo-tag-contract";
import { geoQueueLabel } from "@/lib/follow-ups/worklist-contract";
import { getSiteVisitWorklist } from "@/lib/site-visits/worklist-service";
import { parseSiteVisitWorklistFilters, siteVisitWorklistHref, SITE_VISIT_PAGE_SIZE, SITE_VISIT_VIEWS } from "@/lib/site-visits/worklist-contract";

export const dynamic = "force-dynamic";

const labels = { open: "All open", today: "Today", upcoming: "Upcoming", overdue: "Overdue", completed: "Completed" };
const dateFormat = new Intl.DateTimeFormat("en-IN", { timeZone: "Asia/Kolkata", dateStyle: "medium", timeStyle: "short" });
const control = "rounded-xl border border-slate-700 bg-slate-900 px-4 py-2 text-sm text-slate-200";

export default async function SiteVisitWorklistPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const filters = parseSiteVisitWorklistFilters(await searchParams);
  const result = await getSiteVisitWorklist(filters);
  const totalPages = Math.max(1, Math.ceil(result.total / SITE_VISIT_PAGE_SIZE));

  return <div className="space-y-6">
    <header className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">SalesSetu Operations</p>
        <h1 className="mt-3 text-3xl font-bold text-white">Site Visit Worklist</h1>
        <p className="mt-3 max-w-3xl text-slate-400">GEO-wise property visit calendar and action queue. Open a visit to use the existing check-in, check-out, completion or cancellation controls.</p>
      </div>
      <Link href="/dashboard/follow-ups/insights" className="inline-flex rounded-xl border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-semibold text-cyan-300 hover:border-cyan-400 hover:text-cyan-100">Open follow-up insights</Link>
    </header>

    <nav aria-label="Site visit views" className="flex flex-wrap gap-2">
      {SITE_VISIT_VIEWS.map((view) => <Link key={view} href={siteVisitWorklistHref({ ...filters, view, page: 1 })} aria-current={filters.view === view ? "page" : undefined} className={`${control} transition-colors ${filters.view === view ? "border-cyan-400 bg-cyan-400/15 font-semibold text-cyan-100" : "hover:border-slate-500 hover:bg-slate-800"}`}>{labels[view]}</Link>)}
    </nav>

    <form className="flex flex-wrap items-end gap-3" action="/dashboard/site-visits">
      <input type="hidden" name="view" value={filters.view} />
      <label className="grid gap-2 text-sm text-slate-400">GEO area
        <select name="geo" defaultValue={filters.geo} className={control}>
          <option value="all">All GEO areas</option><option value="mapping_required">GEO mapping required</option>
          {GEO_TAGS.map((tag) => <option key={tag} value={tag}>{GEO_TAG_LABELS[tag]}</option>)}
        </select>
      </label>
      <button className={control} type="submit">Apply filter</button>
      <Link href={siteVisitWorklistHref(filters)} className={control}>Refresh</Link>
    </form>

    <p className="text-sm text-slate-400">{result.total} matching visits · Times in IST · Overdue means the scheduled start time has passed while the visit remains active.</p>
    {result.visits.length === 0 ? <div className="rounded-2xl border border-slate-800 p-8 text-slate-300">No site visits match this view.</div> :
      <section className="overflow-x-auto rounded-2xl border border-slate-800">
        <table className="w-full text-left text-sm">
          <caption className="sr-only">Site visit action queue</caption>
          <thead className="bg-slate-900 text-slate-400"><tr>{["Visit / Lead", "Scheduled (IST)", "Status", "GEO / Assignment", "Action"].map((label) => <th key={label} scope="col" className="px-5 py-4">{label}</th>)}</tr></thead>
          <tbody className="divide-y divide-slate-800">{result.visits.map((visit) => {
            const overdue = visit.status !== "completed" && Date.parse(visit.scheduled_start_at) < Date.parse(result.now);
            return <tr key={visit.id} className="bg-slate-900/40">
              <td className="max-w-sm px-5 py-4"><p className="font-semibold text-white">{visit.title}</p><p className="mt-1 text-slate-400">{[visit.leads.first_name, visit.leads.last_name].filter(Boolean).join(" ") || "Unnamed lead"} · {visit.project_name}</p></td>
              <td className="whitespace-nowrap px-5 py-4"><time dateTime={visit.scheduled_start_at}>{dateFormat.format(new Date(visit.scheduled_start_at))}</time>{overdue ? <p className="mt-1 text-amber-300">Overdue</p> : null}</td>
              <td className="px-5 py-4"><p className="capitalize text-slate-200">{visit.status.replaceAll("_", " ")}</p><p className="mt-1 capitalize text-slate-400">{visit.confirmation_status.replaceAll("_", " ")}</p></td>
              <td className="px-5 py-4"><p>{visit.assigned_agent_id ? "Assigned" : "Unassigned"}</p><p className="mt-1 text-slate-400">{geoQueueLabel(visit.leads.geo_tag, visit.leads.preferred_location, visit.leads.preferred_city)}</p></td>
              <td className="px-5 py-4"><Link className="whitespace-nowrap font-semibold text-cyan-300 hover:text-cyan-100" href={`/dashboard/leads/${visit.lead_id}#site-visit-${visit.id}`}>Open visit actions</Link></td>
            </tr>;
          })}</tbody>
        </table>
      </section>}

    <nav aria-label="Site visit pagination" className="flex items-center justify-between gap-4">
      {filters.page > 1 ? <Link className={control} href={siteVisitWorklistHref(filters, filters.page - 1)}>Previous</Link> : <span />}
      <span className="text-sm text-slate-400">Page {filters.page} of {totalPages}</span>
      {filters.page < totalPages ? <Link className={control} href={siteVisitWorklistHref(filters, filters.page + 1)}>Next</Link> : <span />}
    </nav>
    <p className="text-sm text-slate-500">This worklist does not create visits, assign team members, or send customer communication.</p>
  </div>;
}
