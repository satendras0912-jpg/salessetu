import Link from "next/link";

import { saveLeadGeoTagAction } from "./actions";

import {
  GEO_TAG_LABELS,
  GEO_TAGS,
} from "@/lib/geo/geo-tag-contract";
import { getGeoMappingInbox } from "@/lib/geo/geo-mapping-inbox-service";

export const dynamic = "force-dynamic";

function notice(
  value: string | string[] | undefined,
): string | null {
  const single = Array.isArray(value) ? value[0] : value;
  if (single === "1") return "GEO area saved. The lead is ready for future area routing.";
  if (single === "invalid") return "Choose a valid GEO area and try again.";
  if (single === "changed") return "This lead was changed or is no longer awaiting GEO mapping. Reload the inbox.";
  return null;
}

export default async function GeoMappingInboxPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { leads } = await getGeoMappingInbox();
  const message = notice((await searchParams).updated) ?? notice((await searchParams).error);

  return (
    <div className="space-y-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          SalesSetu Operations
        </p>
        <h1 className="mt-3 text-3xl font-bold text-white">GEO Mapping Inbox</h1>
        <p className="mt-3 max-w-3xl text-slate-400">
          Tag existing leads that are waiting for an area. This updates only the
          lead&apos;s GEO label; it does not assign an owner or start customer outreach.
        </p>
      </header>

      {message ? (
        <div className="rounded-2xl border border-cyan-400/40 bg-cyan-400/10 p-4 text-sm text-cyan-100">
          {message}
        </div>
      ) : null}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-slate-400">
          {leads.length} lead{leads.length === 1 ? "" : "s"} awaiting GEO mapping
          {leads.length === 50 ? " (showing the newest 50)" : ""}.
        </p>
        <Link
          href="/dashboard/follow-ups/coverage"
          className="rounded-xl border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 hover:bg-slate-800"
        >
          View GEO coverage
        </Link>
      </div>

      {leads.length === 0 ? (
        <section className="rounded-2xl border border-emerald-500/40 bg-emerald-500/10 p-7 text-emerald-100">
          All currently visible active leads have a GEO tag. New untagged leads
          will appear here for manual review.
        </section>
      ) : (
        <section className="overflow-x-auto rounded-2xl border border-slate-800">
          <table className="w-full text-left text-sm">
            <caption className="sr-only">Leads awaiting GEO mapping</caption>
            <thead className="bg-slate-900 text-slate-400">
              <tr>
                {['Lead', 'Location provided', 'Suggested area', 'Set GEO area'].map((heading) => (
                  <th key={heading} scope="col" className="px-5 py-4">{heading}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800">
              {leads.map((lead) => (
                <tr key={lead.id} className="bg-slate-900/40">
                  <td className="px-5 py-4">
                    <Link className="font-semibold text-white hover:text-cyan-200" href={`/dashboard/leads/${lead.id}`}>
                      {lead.name}
                    </Link>
                  </td>
                  <td className="px-5 py-4 text-slate-300">
                    {[lead.preferredLocation, lead.preferredCity].filter(Boolean).join(" · ") || "No location provided"}
                  </td>
                  <td className="px-5 py-4 text-slate-300">
                    {lead.suggestedGeoTag ? GEO_TAG_LABELS[lead.suggestedGeoTag] : "No safe suggestion"}
                  </td>
                  <td className="px-5 py-4">
                    <form action={saveLeadGeoTagAction} className="flex min-w-72 items-center gap-2">
                      <input type="hidden" name="leadId" value={lead.id} />
                      <select
                        name="geoTag"
                        required
                        defaultValue={lead.suggestedGeoTag ?? ""}
                        className="min-w-0 flex-1 rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100"
                      >
                        <option value="" disabled>Choose area</option>
                        {GEO_TAGS.map((tag) => (
                          <option key={tag} value={tag}>{GEO_TAG_LABELS[tag]}</option>
                        ))}
                      </select>
                      <button className="rounded-xl border border-cyan-400/60 bg-cyan-400/15 px-3 py-2 font-semibold text-cyan-100 hover:bg-cyan-400/25" type="submit">
                        Save
                      </button>
                    </form>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}
    </div>
  );
}
