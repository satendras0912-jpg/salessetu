import Link from "next/link";
import { redirect } from "next/navigation";

import DealFilters from "@/components/dealos/DealFilters";
import DealTable from "@/components/dealos/DealTable";

import {
  requirePermissionAccess,
} from "@/lib/auth/access-control";

import {
  DEALOS_PERMISSIONS,
} from "@/lib/dealos/deal-contract";

import {
  getDealAssigneeOptions,
  getDeals,
} from "@/lib/dealos/deal-service";

import {
  DEAL_STATUSES,
} from "@/types/dealos";

import type {
  DealListFilters,
  DealStatus,
} from "@/types/dealos";

export const dynamic =
  "force-dynamic";

type RawSearchParams = Record<
  string,
  string | string[] | undefined
>;

type DealOperationsPageProps = {
  searchParams: Promise<RawSearchParams>;
};

function getSingleValue(
  value:
    | string
    | string[]
    | undefined,
): string {
  if (
    Array.isArray(value)
  ) {
    return value[0] ?? "";
  }

  return value ?? "";
}

function parsePositiveInteger(
  value: string,
  fallback: number,
): number {
  const parsed =
    Number.parseInt(
      value,
      10,
    );

  if (
    !Number.isInteger(
      parsed,
    ) ||
    parsed < 1
  ) {
    return fallback;
  }

  return parsed;
}

function isDealStatus(
  value: string,
): value is DealStatus {
  return (
    DEAL_STATUSES as readonly string[]
  ).includes(value);
}

function createPageHref(
  filters: DealListFilters,
  page: number,
): string {
  const params =
    new URLSearchParams();

  if (
    filters.status
  ) {
    params.set(
      "status",
      filters.status,
    );
  }

  if (
    filters.assignedTo
  ) {
    params.set(
      "assignedTo",
      filters.assignedTo,
    );
  }

  params.set(
    "page",
    String(page),
  );

  params.set(
    "pageSize",
    String(
      filters.pageSize ??
        25,
    ),
  );

  return `/dashboard/deals?${params.toString()}`;
}

export default async function DealOperationsPage({
  searchParams,
}: DealOperationsPageProps) {
  const {
    context,
  } =
    await requirePermissionAccess(
      {
        allOf: [
          DEALOS_PERMISSIONS.viewDeals,
        ],

        loginRedirectTo:
          "/login?next=/dashboard/deals",

        unauthorizedRedirectTo:
          "/unauthorized",
      },
    );

  const organizationId =
    context.organization?.id;

  if (
    !organizationId
  ) {
    redirect(
      "/auth-error?reason=organization_context_missing",
    );
  }

  const rawParams =
    await searchParams;

  const rawStatus =
    getSingleValue(
      rawParams.status,
    ).trim();

  const filters: DealListFilters =
    {
      status:
        rawStatus &&
        isDealStatus(
          rawStatus,
        )
          ? rawStatus
          : undefined,

      assignedTo:
        getSingleValue(
          rawParams.assignedTo,
        ).trim() ||
        undefined,

      page:
        parsePositiveInteger(
          getSingleValue(
            rawParams.page,
          ),
          1,
        ),

      pageSize:
        parsePositiveInteger(
          getSingleValue(
            rawParams.pageSize,
          ),
          25,
        ),
    };

  const [
    dealsResult,
    assigneeResult,
  ] = await Promise.all([
    getDeals(
      organizationId,
      filters,
    ),

    getDealAssigneeOptions(
      organizationId,
    ),
  ]);

  if (
    !dealsResult.ok
  ) {
    throw new Error(
      dealsResult.message,
    );
  }

  if (
    !assigneeResult.ok
  ) {
    throw new Error(
      assigneeResult.message,
    );
  }

  const result =
    dealsResult.data;

  const assignees =
    assigneeResult.data;

  const currentPageCount =
    result.items.length;

  const negotiationCount =
    result.items.filter(
      (deal) =>
        deal.status ===
          "negotiation" ||
        deal.status ===
          "commercial_review",
    ).length;

  const closingCount =
    result.items.filter(
      (deal) =>
        deal.status ===
          "booking_ready" ||
        deal.status ===
          "won",
    ).length;

  const firstVisibleDeal =
    result.total === 0
      ? 0
      : (result.page - 1) *
          result.pageSize +
        1;

  const lastVisibleDeal =
    Math.min(
      result.page *
        result.pageSize,
      result.total,
    );

  return (
    <div className="space-y-8">
      <header className="flex flex-col justify-between gap-6 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            SalesSetu Enterprise
          </p>

          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
            Deal Operations
          </h1>

          <p className="mt-3 max-w-3xl text-base leading-7 text-slate-400">
            Commercial negotiation,
            approvals, booking
            readiness aur deal
            progression ko ek jagah
            monitor karein.
          </p>
        </div>

        <div className="rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4">
          <p className="text-xs uppercase tracking-wider text-slate-500">
            Organization
          </p>

          <p className="mt-1 font-semibold text-white">
            {context.organization
              ?.name ??
              "SalesSetu Workspace"}
          </p>
        </div>
      </header>

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Total deals
          </p>

          <p className="mt-2 text-3xl font-bold text-white">
            {result.total.toLocaleString(
              "en-IN",
            )}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Current page
          </p>

          <p className="mt-2 text-3xl font-bold text-cyan-300">
            {currentPageCount.toLocaleString(
              "en-IN",
            )}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Negotiation / review
          </p>

          <p className="mt-2 text-3xl font-bold text-amber-300">
            {negotiationCount.toLocaleString(
              "en-IN",
            )}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Booking ready / won
          </p>

          <p className="mt-2 text-3xl font-bold text-emerald-300">
            {closingCount.toLocaleString(
              "en-IN",
            )}
          </p>
        </article>
      </section>

      <DealFilters
        filters={filters}
        assignees={
          assignees
        }
      />

      <div className="flex flex-col justify-between gap-3 text-sm text-slate-500 sm:flex-row sm:items-center">
        <p>
          Showing{" "}
          <span className="font-medium text-slate-300">
            {firstVisibleDeal}
            {"–"}
            {lastVisibleDeal}
          </span>{" "}
          of{" "}
          <span className="font-medium text-slate-300">
            {result.total.toLocaleString(
              "en-IN",
            )}
          </span>{" "}
          deals
        </p>

        <p>
          Page{" "}
          <span className="font-medium text-slate-300">
            {result.totalPages === 0
              ? 1
              : result.page}
          </span>{" "}
          of{" "}
          <span className="font-medium text-slate-300">
            {Math.max(result.totalPages, 1)}
          </span>
        </p>
      </div>

      <DealTable
        deals={
          result.items
        }
      />

      {result.totalPages >
      1 ? (
        <nav
          aria-label="Deal pagination"
          className="flex items-center justify-between rounded-2xl border border-slate-800 bg-slate-900/70 p-4"
        >
          {result.page >
          1 ? (
            <Link
              href={createPageHref(
                filters,
                result.page - 1,
              )}
              className="rounded-xl border border-slate-700 px-5 py-2.5 text-sm font-semibold text-slate-300 transition hover:border-cyan-500 hover:text-cyan-300"
            >
              Previous
            </Link>
          ) : (
            <span className="cursor-not-allowed rounded-xl border border-slate-800 px-5 py-2.5 text-sm text-slate-700">
              Previous
            </span>
          )}

          <span className="text-sm text-slate-400">
            Page{" "}
            {result.page} of{" "}
            {
              result.totalPages
            }
          </span>

          {result.page <
          result.totalPages ? (
            <Link
              href={createPageHref(
                filters,
                result.page + 1,
              )}
              className="rounded-xl border border-slate-700 px-5 py-2.5 text-sm font-semibold text-slate-300 transition hover:border-cyan-500 hover:text-cyan-300"
            >
              Next
            </Link>
          ) : (
            <span className="cursor-not-allowed rounded-xl border border-slate-800 px-5 py-2.5 text-sm text-slate-700">
              Next
            </span>
          )}
        </nav>
      ) : null}
    </div>
  );
}