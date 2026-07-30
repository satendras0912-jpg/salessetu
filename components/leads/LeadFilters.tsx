import Link from "next/link";

import type {
  LeadListFilters,
  LeadSourceSummary,
} from "@/types/leads";

type LeadFiltersProps = {
  filters: LeadListFilters;
  sources: LeadSourceSummary[];
};

const leadStatuses = [
  "new",
  "contacted",
  "qualified",
  "unqualified",
  "site_visit",
  "negotiation",
  "converted",
  "lost",
];

const assignmentStatuses = [
  "unassigned",
  "pending",
  "assigned",
  "accepted",
  "rejected",
  "completed",
];

const validationDecisions = [
  "approved",
  "manual_review",
  "rejected",
  "suppressed",
];

function formatOptionLabel(value: string): string {
  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

export default function LeadFilters({
  filters,
  sources,
}: LeadFiltersProps) {
  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-5 shadow-2xl shadow-black/10">
      <div className="mb-5">
        <h2 className="text-lg font-semibold text-white">
          Search and filters
        </h2>

        <p className="mt-1 text-sm text-slate-400">
          Name, phone, project, source, validation and assignment
          के आधार पर leads खोजें।
        </p>
      </div>

      <form
        action="/dashboard/leads"
        method="get"
        className="grid gap-4 md:grid-cols-2 xl:grid-cols-6"
      >
        <label className="md:col-span-2 xl:col-span-2">
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Search
          </span>

          <input
            type="search"
            name="search"
            defaultValue={filters.search ?? ""}
            placeholder="Name, phone, email, project..."
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20"
          />
        </label>

        <label>
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Lead status
          </span>

          <select
            name="status"
            defaultValue={filters.status ?? ""}
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none focus:border-cyan-500"
          >
            <option value="">All statuses</option>

            {leadStatuses.map((status) => (
              <option key={status} value={status}>
                {formatOptionLabel(status)}
              </option>
            ))}
          </select>
        </label>

        <label>
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Validation
          </span>

          <select
            name="validationDecision"
            defaultValue={filters.validationDecision ?? ""}
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none focus:border-cyan-500"
          >
            <option value="">All decisions</option>

            {validationDecisions.map((decision) => (
              <option key={decision} value={decision}>
                {formatOptionLabel(decision)}
              </option>
            ))}
          </select>
        </label>

        <label>
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Assignment
          </span>

          <select
            name="assignmentStatus"
            defaultValue={filters.assignmentStatus ?? ""}
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none focus:border-cyan-500"
          >
            <option value="">All assignments</option>

            {assignmentStatuses.map((status) => (
              <option key={status} value={status}>
                {formatOptionLabel(status)}
              </option>
            ))}
          </select>
        </label>

        <label>
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Source
          </span>

          <select
            name="sourceId"
            defaultValue={filters.sourceId ?? ""}
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none focus:border-cyan-500"
          >
            <option value="">All sources</option>

            {sources.map((source) => (
              <option key={source.id} value={source.id}>
                {source.name}
              </option>
            ))}
          </select>
        </label>

        <label>
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Rows
          </span>

          <select
            name="pageSize"
            defaultValue={String(filters.pageSize ?? 25)}
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none focus:border-cyan-500"
          >
            <option value="10">10 rows</option>
            <option value="25">25 rows</option>
            <option value="50">50 rows</option>
            <option value="100">100 rows</option>
          </select>
        </label>

        <div className="flex items-end gap-3 md:col-span-2 xl:col-span-5">
          <button
            type="submit"
            className="rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 focus:outline-none focus:ring-2 focus:ring-cyan-300"
          >
            Apply filters
          </button>

          <Link
            href="/dashboard/leads"
            className="rounded-xl border border-slate-700 px-6 py-3 text-sm font-semibold text-slate-300 transition hover:border-slate-500 hover:bg-slate-800 hover:text-white"
          >
            Clear
          </Link>
        </div>
      </form>
    </section>
  );
}