import Link from "next/link";
import { redirect } from "next/navigation";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { LEAD_FORM_PERMISSIONS } from "@/lib/leads/lead-form-contract";
import {
  getManualValidationQueue,
  type ManualValidationQueueFilter,
} from "@/lib/leads/manual-validation-service";

import {
  decideManualLeadValidationAction,
} from "./actions";

export const dynamic = "force-dynamic";

const REVIEW_PERMISSION = "lead_validation.review";

type RawSearchParams = Record<
  string,
  string | string[] | undefined
>;

type ManualLeadValidationPageProps = {
  searchParams: Promise<RawSearchParams>;
};

function oneValue(
  value: string | string[] | undefined,
): string {
  return Array.isArray(value)
    ? value[0] ?? ""
    : value ?? "";
}

function queueFilter(value: string): ManualValidationQueueFilter {
  if (
    value === "approved" ||
    value === "hold" ||
    value === "rejected" ||
    value === "all"
  ) {
    return value;
  }

  return "pending";
}

function labelForDecision(
  decision: "approved" | "hold" | "rejected",
): string {
  return {
    approved: "Approved",
    hold: "On hold",
    rejected: "Rejected",
  }[decision];
}

function badgeClass(
  decision: "approved" | "hold" | "rejected" | "pending",
): string {
  return {
    approved:
      "border-emerald-500/50 bg-emerald-500/10 text-emerald-300",
    hold:
      "border-amber-500/50 bg-amber-500/10 text-amber-300",
    rejected:
      "border-rose-500/50 bg-rose-500/10 text-rose-300",
    pending:
      "border-slate-500/50 bg-slate-500/10 text-slate-300",
  }[decision];
}

export default async function ManualLeadValidationPage({
  searchParams,
}: ManualLeadValidationPageProps) {
  const { context } = await requirePermissionAccess({
    allOf: [
      LEAD_FORM_PERMISSIONS.view,
      REVIEW_PERMISSION,
    ],

    loginRedirectTo: "/login?next=/dashboard/lead-validation",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    redirect("/auth-error?reason=organization_context_missing");
  }

  const params = await searchParams;
  const filter = queueFilter(oneValue(params.queue));
  const updated = oneValue(params.updated);
  const error = oneValue(params.error);

  const allItems = await getManualValidationQueue(
    organizationId,
    "all",
  );

  const items = allItems.filter((item) => {
    if (filter === "all") {
      return true;
    }

    if (filter === "pending") {
      return !item.review || item.review.decision === "hold";
    }

    return item.review?.decision === filter;
  });

  const pendingCount = allItems.filter(
    (item) => !item.review || item.review.decision === "hold",
  ).length;
  const approvedCount = allItems.filter(
    (item) => item.review?.decision === "approved",
  ).length;
  const rejectedCount = allItems.filter(
    (item) => item.review?.decision === "rejected",
  ).length;

  return (
    <div className="space-y-8">
      <header className="flex flex-col justify-between gap-5 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            SalesSetu Enterprise
          </p>

          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
            Lead Validation Queue
          </h1>

          <p className="mt-3 max-w-3xl text-base leading-7 text-slate-400">
            Every qualification decision is manual, tenant-scoped and
            auditable. This queue never assigns or routes a lead automatically.
          </p>
        </div>

        <Link
          href="/dashboard/leads"
          className="inline-flex items-center justify-center rounded-xl border border-slate-700 px-5 py-3 font-semibold text-slate-200 transition hover:border-cyan-500 hover:text-cyan-300"
        >
          Back to leads
        </Link>
      </header>

      {updated ? (
        <p className="rounded-2xl border border-emerald-500/40 bg-emerald-500/10 px-5 py-4 text-sm font-medium text-emerald-300">
          Manual validation decision saved: {updated}.
          Assignment and routing remain unchanged.
        </p>
      ) : null}

      {error ? (
        <p className="rounded-2xl border border-rose-500/40 bg-rose-500/10 px-5 py-4 text-sm font-medium text-rose-300">
          {error}
        </p>
      ) : null}

      <section className="grid gap-4 md:grid-cols-3">
        {[
          ["Needs review", pendingCount, "pending"],
          ["Approved", approvedCount, "approved"],
          ["Rejected", rejectedCount, "rejected"],
        ].map(([label, count, value]) => (
          <Link
            key={String(value)}
            href={`/dashboard/lead-validation?queue=${value}`}
            className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 transition hover:border-cyan-500/50"
          >
            <p className="text-sm text-slate-400">{label}</p>
            <p className="mt-2 text-3xl font-bold text-white">{count}</p>
          </Link>
        ))}
      </section>

      <section className="flex flex-wrap gap-3">
        {[
          ["pending", "Needs review"],
          ["approved", "Approved"],
          ["hold", "On hold"],
          ["rejected", "Rejected"],
          ["all", "All leads"],
        ].map(([value, label]) => (
          <Link
            key={value}
            href={`/dashboard/lead-validation?queue=${value}`}
            className={[
              "rounded-xl border px-4 py-2 text-sm font-semibold transition",
              filter === value
                ? "border-cyan-500 bg-cyan-500/10 text-cyan-300"
                : "border-slate-700 text-slate-300 hover:border-slate-500",
            ].join(" ")}
          >
            {label}
          </Link>
        ))}
      </section>

      <section className="space-y-5">
        {items.length === 0 ? (
          <div className="rounded-2xl border border-slate-800 bg-slate-900/70 p-8 text-slate-400">
            No leads match this view.
          </div>
        ) : (
          items.map((lead) => {
            const currentDecision = lead.review?.decision ?? "pending";

            return (
              <article
                key={lead.id}
                className="rounded-2xl border border-slate-800 bg-slate-900/70 p-6"
              >
                <div className="flex flex-col justify-between gap-4 lg:flex-row">
                  <div>
                    <div className="flex flex-wrap items-center gap-3">
                      <Link
                        href={`/dashboard/leads/${lead.id}`}
                        className="text-xl font-bold text-white hover:text-cyan-300"
                      >
                        {lead.fullName}
                      </Link>

                      <span
                        className={[
                          "rounded-full border px-3 py-1 text-xs font-semibold",
                          badgeClass(currentDecision),
                        ].join(" ")}
                      >
                        {currentDecision === "pending"
                          ? "Needs review"
                          : labelForDecision(currentDecision)}
                      </span>
                    </div>

                    <p className="mt-3 text-sm text-slate-400">
                      {[lead.phone, lead.email]
                        .filter(Boolean)
                        .join(" · ") || "No contact details"}
                    </p>

                    <p className="mt-2 text-sm text-slate-500">
                      {[lead.preferredProject, lead.preferredLocation, lead.source]
                        .filter(Boolean)
                        .join(" · ") || "Requirement details not specified"}
                    </p>

                    {lead.review ? (
                      <div className="mt-4 rounded-xl border border-slate-800 bg-slate-950/50 p-4 text-sm">
                        <p className="font-medium text-slate-200">
                          Last decision: {labelForDecision(lead.review.decision)}
                        </p>
                        <p className="mt-1 text-slate-400">
                          {lead.review.reason}
                        </p>
                        {lead.review.notes ? (
                          <p className="mt-1 text-slate-500">
                            {lead.review.notes}
                          </p>
                        ) : null}
                      </div>
                    ) : null}
                  </div>

                  <form
                    action={decideManualLeadValidationAction}
                    className="w-full space-y-3 lg:max-w-lg"
                  >
                    <input type="hidden" name="leadId" value={lead.id} />

                    <label className="block text-sm font-medium text-slate-300">
                      Decision reason
                      <input
                        required
                        minLength={3}
                        maxLength={500}
                        name="reason"
                        placeholder="Why is this decision being made?"
                        className="mt-2 w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500"
                      />
                    </label>

                    <label className="block text-sm font-medium text-slate-300">
                      Notes <span className="text-slate-500">(optional)</span>
                      <textarea
                        name="notes"
                        maxLength={2000}
                        rows={2}
                        placeholder="Context for the next reviewer or agent"
                        className="mt-2 w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500"
                      />
                    </label>

                    <div className="flex flex-wrap gap-2">
                      <button
                        type="submit"
                        name="decision"
                        value="approved"
                        className="rounded-xl bg-emerald-500 px-4 py-2 font-semibold text-slate-950 transition hover:bg-emerald-400"
                      >
                        Approve
                      </button>
                      <button
                        type="submit"
                        name="decision"
                        value="hold"
                        className="rounded-xl border border-amber-500/60 px-4 py-2 font-semibold text-amber-300 transition hover:bg-amber-500/10"
                      >
                        Hold
                      </button>
                      <button
                        type="submit"
                        name="decision"
                        value="rejected"
                        className="rounded-xl border border-rose-500/60 px-4 py-2 font-semibold text-rose-300 transition hover:bg-rose-500/10"
                      >
                        Reject
                      </button>
                    </div>

                    <p className="text-xs leading-5 text-slate-500">
                      This records a qualification decision only. It does not
                      create an assignment, route a lead or notify a customer.
                    </p>
                  </form>
                </div>
              </article>
            );
          })
        )}
      </section>
    </div>
  );
}
