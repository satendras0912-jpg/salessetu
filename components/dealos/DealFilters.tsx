import Link from "next/link";

import {
  DEAL_STATUSES,
} from "@/types/dealos";

import type {
  DealListFilters,
} from "@/types/dealos";

import type {
  OrganizationMemberOption,
} from "@/types/lead-operational-controls";

type DealFiltersProps = {
  filters: DealListFilters;
  assignees: OrganizationMemberOption[];
};

function formatOptionLabel(
  value: string,
): string {
  return value
    .replaceAll("_", " ")
    .replace(
      /\b\w/g,
      (character) =>
        character.toUpperCase(),
    );
}

export default function DealFilters({
  filters,
  assignees,
}: DealFiltersProps) {
  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-5 shadow-2xl shadow-black/10">
      <div className="mb-5">
        <h2 className="text-lg font-semibold text-white">
          Deal filters
        </h2>

        <p className="mt-1 text-sm text-slate-400">
          Deal status aur assigned user ke basis par
          DealOS pipeline filter karein.
        </p>
      </div>

      <form
  key={[
    filters.status ?? "",
    filters.assignedTo ?? "",
    filters.pageSize ?? 25,
  ].join(":")}
  action="/dashboard/deals"
  method="get"
        className="grid gap-4 md:grid-cols-2 xl:grid-cols-4"
      >
        <label>
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Deal status
          </span>

          <select
            name="status"
            defaultValue={
              filters.status ?? ""
            }
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none focus:border-cyan-500"
          >
            <option value="">
              All statuses
            </option>

            {DEAL_STATUSES.map(
              (status) => (
                <option
                  key={status}
                  value={status}
                >
                  {formatOptionLabel(
                    status,
                  )}
                </option>
              ),
            )}
          </select>
        </label>

        <label>
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Assigned to
          </span>

          <select
            name="assignedTo"
            defaultValue={
              filters.assignedTo ?? ""
            }
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none focus:border-cyan-500"
          >
            <option value="">
              All assignees
            </option>

            {assignees.map(
              (assignee) => (
                <option
                  key={
                    assignee.userId
                  }
                  value={
                    assignee.userId
                  }
                >
                  {
                    assignee.displayName
                  }
                </option>
              ),
            )}
          </select>
        </label>

        <label>
          <span className="mb-2 block text-sm font-medium text-slate-300">
            Rows
          </span>

          <select
            name="pageSize"
            defaultValue={String(
              filters.pageSize ?? 25,
            )}
            className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none focus:border-cyan-500"
          >
            <option value="10">
              10 rows
            </option>

            <option value="25">
              25 rows
            </option>

            <option value="50">
              50 rows
            </option>

            <option value="100">
              100 rows
            </option>
          </select>
        </label>

        <div className="flex items-end gap-3">
          <button
            type="submit"
            className="rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 focus:outline-none focus:ring-2 focus:ring-cyan-300"
          >
            Apply filters
          </button>

          <Link
            href="/dashboard/deals"
            className="rounded-xl border border-slate-700 px-6 py-3 text-sm font-semibold text-slate-300 transition hover:border-slate-500 hover:bg-slate-800 hover:text-white"
          >
            Clear
          </Link>
        </div>
      </form>
    </section>
  );
}