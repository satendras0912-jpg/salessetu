import Link from "next/link";
import { redirect } from "next/navigation";

import LeadFilters from "@/components/leads/LeadFilters";
import LeadTable from "@/components/leads/LeadTable";

import { requirePermissionAccess } from "@/lib/auth/access-control";

import {
  LEAD_FORM_PERMISSIONS,
} from "@/lib/leads/lead-form-contract";

import {
  getLeadList,
  getLeadSources,
} from "@/lib/leads/lead-service";

import type { LeadListFilters } from "@/types/leads";

export const dynamic = "force-dynamic";

type RawSearchParams = Record<
  string,
  string | string[] | undefined
>;

type LeadOperationsPageProps = {
  searchParams: Promise<RawSearchParams>;
};

function getSingleValue(
  value: string | string[] | undefined,
): string {
  if (Array.isArray(value)) {
    return value[0] ?? "";
  }

  return value ?? "";
}

function parsePositiveInteger(
  value: string,
  fallback: number,
): number {
  const parsed = Number.parseInt(value, 10);

  if (!Number.isInteger(parsed) || parsed < 1) {
    return fallback;
  }

  return parsed;
}

function hasPermission(
  permissionCodes: readonly string[],
  requiredPermission: string,
): boolean {
  const normalizedRequiredPermission =
    requiredPermission.trim().toLowerCase();

  return permissionCodes.some(
    (permissionCode) =>
      permissionCode.trim().toLowerCase() ===
      normalizedRequiredPermission,
  );
}

function createPageHref(
  filters: LeadListFilters,
  page: number,
): string {
  const params = new URLSearchParams();

  if (filters.search) {
    params.set("search", filters.search);
  }

  if (filters.status) {
    params.set("status", filters.status);
  }

  if (filters.assignmentStatus) {
    params.set(
      "assignmentStatus",
      filters.assignmentStatus,
    );
  }

  if (filters.validationDecision) {
    params.set(
      "validationDecision",
      filters.validationDecision,
    );
  }

  if (filters.sourceId) {
    params.set("sourceId", filters.sourceId);
  }

  params.set("page", String(page));
  params.set(
    "pageSize",
    String(filters.pageSize ?? 25),
  );

  return `/dashboard/leads?${params.toString()}`;
}

export default async function LeadOperationsPage({
  searchParams,
}: LeadOperationsPageProps) {
  const { context, permissions } =
    await requirePermissionAccess({
      allOf: [LEAD_FORM_PERMISSIONS.view],

      loginRedirectTo:
        "/login?next=/dashboard/leads",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id;

  if (!organizationId) {
    redirect(
      "/auth-error?reason=organization_context_missing",
    );
  }

  const isOwner = Boolean(
    context.membership?.isOwner,
  );

  const canCreateLead =
    isOwner ||
    hasPermission(
      permissions.codes,
      LEAD_FORM_PERMISSIONS.create,
    );

  const rawParams = await searchParams;

  const filters: LeadListFilters = {
    search:
      getSingleValue(rawParams.search).trim() ||
      undefined,

    status:
      getSingleValue(rawParams.status).trim() ||
      undefined,

    assignmentStatus:
      getSingleValue(
        rawParams.assignmentStatus,
      ).trim() || undefined,

    validationDecision:
      getSingleValue(
        rawParams.validationDecision,
      ).trim() || undefined,

    sourceId:
      getSingleValue(rawParams.sourceId).trim() ||
      undefined,

    page: parsePositiveInteger(
      getSingleValue(rawParams.page),
      1,
    ),

    pageSize: parsePositiveInteger(
      getSingleValue(rawParams.pageSize),
      25,
    ),
  };

  const [result, sources] = await Promise.all([
    getLeadList(organizationId, filters),
    getLeadSources(organizationId),
  ]);

  const currentPageCount = result.items.length;

  const approvedCount = result.items.filter(
    (lead) =>
      lead.validation?.decision === "approved",
  ).length;

  const manualReviewCount = result.items.filter(
    (lead) =>
      lead.validation?.decision ===
      "manual_review",
  ).length;

  const unassignedCount = result.items.filter(
    (lead) => {
      const assignmentStatus =
        lead.assignment?.status ??
        lead.assignmentStatus;

      return (
        !lead.assignment ||
        assignmentStatus === "unassigned"
      );
    },
  ).length;

  const firstVisibleLead =
    result.total === 0
      ? 0
      : (result.page - 1) * result.pageSize + 1;

  const lastVisibleLead = Math.min(
    result.page * result.pageSize,
    result.total,
  );

  return (
    <div className="space-y-8">
      {/* Page heading */}
      <header className="flex flex-col justify-between gap-6 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            SalesSetu Enterprise
          </p>

          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
            Lead Operations
          </h1>

          <p className="mt-3 max-w-3xl text-base leading-7 text-slate-400">
            Captured leads, validation status, source,
            qualification और current assignment को एक
            जगह monitor करें।
          </p>
        </div>

        <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
          {canCreateLead ? (
            <Link
              href="/dashboard/leads/new"
              className="inline-flex items-center justify-center rounded-xl bg-cyan-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 focus:outline-none focus:ring-2 focus:ring-cyan-300"
            >
              Create lead
            </Link>
          ) : null}

          <div className="rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4">
            <p className="text-xs uppercase tracking-wider text-slate-500">
              Organization
            </p>

            <p className="mt-1 font-semibold text-white">
              {context.organization?.name ??
                "SalesSetu Workspace"}
            </p>
          </div>
        </div>
      </header>

      {/* Summary cards */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Total leads
          </p>

          <p className="mt-2 text-3xl font-bold text-white">
            {result.total.toLocaleString("en-IN")}
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
            Approved on page
          </p>

          <p className="mt-2 text-3xl font-bold text-emerald-300">
            {approvedCount.toLocaleString("en-IN")}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Review / unassigned
          </p>

          <p className="mt-2 text-3xl font-bold text-amber-300">
            {manualReviewCount} / {unassignedCount}
          </p>
        </article>
      </section>

      {/* Search and filters */}
      <LeadFilters
        filters={filters}
        sources={sources}
      />

      {/* Result summary */}
      <div className="flex flex-col justify-between gap-3 text-sm text-slate-500 sm:flex-row sm:items-center">
        <p>
          Showing{" "}
          <span className="font-medium text-slate-300">
            {firstVisibleLead}–{lastVisibleLead}
          </span>{" "}
          of{" "}
          <span className="font-medium text-slate-300">
            {result.total.toLocaleString("en-IN")}
          </span>{" "}
          leads
        </p>

        <p>
          Page{" "}
          <span className="font-medium text-slate-300">
            {result.totalPages === 0
              ? 0
              : result.page}
          </span>{" "}
          of{" "}
          <span className="font-medium text-slate-300">
            {result.totalPages}
          </span>
        </p>
      </div>

      {/* Lead table */}
      <LeadTable leads={result.items} />

      {/* Pagination */}
      {result.totalPages > 1 ? (
        <nav
          aria-label="Lead pagination"
          className="flex items-center justify-between rounded-2xl border border-slate-800 bg-slate-900/70 p-4"
        >
          {result.page > 1 ? (
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
            Page {result.page} of{" "}
            {result.totalPages}
          </span>

          {result.page < result.totalPages ? (
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