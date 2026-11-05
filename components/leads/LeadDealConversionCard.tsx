"use client";

import Link from "next/link";

import {
  useActionState,
} from "react";

import {
  requestDealConversionAction,
} from "@/app/dashboard/deals/actions";

import {
  INITIAL_DEALOS_ACTION_STATE,
} from "@/lib/dealos/deal-contract";

import type {
  LeadSiteVisitItem,
} from "@/types/lead-detail";

type LeadDealConversionCardProps = {
  leadId: string;
  siteVisits: LeadSiteVisitItem[];
  canCreateDeal: boolean;
  isEligibleForConversion: boolean;
  eligibilityMessage: string;
};

function isCompletedVisit(
  visit: LeadSiteVisitItem,
): boolean {
  return visit.status.trim().toLowerCase() === "completed";
}

function formatVisit(
  visit: LeadSiteVisitItem,
): string {
  const project =
    visit.projectName?.trim() ||
    "Site visit";

  const completedAt =
    visit.visitCompletedAt
      ? new Intl.DateTimeFormat(
          "en-IN",
          {
            dateStyle: "medium",
            timeStyle: "short",
            timeZone: "Asia/Kolkata",
          },
        ).format(
          new Date(
            visit.visitCompletedAt,
          ),
        )
      : "Completed";

  return `${project} — ${completedAt}`;
}

export default function LeadDealConversionCard({
  leadId,
  siteVisits,
  canCreateDeal,
  isEligibleForConversion,
  eligibilityMessage,
}: LeadDealConversionCardProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    requestDealConversionAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const completedVisits =
    siteVisits.filter(
      isCompletedVisit,
    );

  const canSubmit =
    canCreateDeal &&
    isEligibleForConversion &&
    completedVisits.length > 0;

  const guidance =
    !canCreateDeal
      ? "You do not have permission to create deals for this workspace."
      : !isEligibleForConversion
        ? eligibilityMessage
        : completedVisits.length === 0
          ? "Complete a site visit before creating a deal."
          : eligibilityMessage;

  return (
    <section className="rounded-3xl border border-cyan-500/30 bg-cyan-500/5 p-6 sm:p-8">
      <p className="text-xs font-semibold uppercase tracking-[0.3em] text-cyan-400">
        Deal conversion
      </p>

      <h2 className="mt-3 text-2xl font-semibold text-white">
        Request Match-to-Deal approval
      </h2>

      <p className="mt-3 max-w-3xl text-sm leading-6 text-slate-300">
        A suitable manual inventory match, approved validation and completed site
        visit are required. The workspace owner must approve before DealOS creates
        a deal. This does not reserve inventory, route work or notify a customer.
      </p>

      <div className="mt-5 rounded-2xl border border-slate-700 bg-slate-950/50 px-4 py-3 text-sm leading-6 text-slate-300">
        {guidance}
      </div>

      {canSubmit ? (
        <form
          action={formAction}
          className="mt-6 space-y-5"
        >
          <input
            type="hidden"
            name="leadId"
            value={leadId}
          />

          <div>
            <label
              htmlFor="dealSiteVisitId"
              className="mb-2 block text-sm font-medium text-slate-200"
            >
              Completed site visit
            </label>

            <select
              id="dealSiteVisitId"
              name="siteVisitId"
              required
              defaultValue=""
              className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20"
            >
              <option
                value=""
                disabled
              >
                Select completed visit
              </option>

              {completedVisits.map(
                (visit) => (
                  <option
                    key={visit.id}
                    value={visit.id}
                  >
                    {formatVisit(visit)}
                  </option>
                ),
              )}
            </select>
          </div>

          <div>
            <label
              htmlFor="dealConversionNotes"
              className="mb-2 block text-sm font-medium text-slate-200"
            >
              Request context (optional)
            </label>
            <textarea
              id="dealConversionNotes"
              name="notes"
              maxLength={2000}
              rows={3}
              placeholder="Why should the owner approve this deal conversion?"
              className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20"
            />
          </div>

          {state.status !== "idle" &&
          state.message ? (
            <p
              aria-live="polite"
              className={
                state.status === "success"
                  ? "text-sm text-emerald-300"
                  : "text-sm text-red-300"
              }
            >
              {state.message}
            </p>
          ) : null}

          <button
            type="submit"
            disabled={isPending}
            className="inline-flex min-w-48 items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isPending
              ? "Sending request..."
              : "Request owner approval"}
          </button>
        </form>
      ) : (
        <Link
          href={
            isEligibleForConversion
              ? "/dashboard/site-visits"
              : "/dashboard/lead-validation"
          }
          className="mt-6 inline-flex rounded-xl border border-cyan-400/50 px-5 py-3 text-sm font-semibold text-cyan-200 transition hover:border-cyan-300 hover:text-white"
        >
          {isEligibleForConversion
            ? "Open Site Visits"
            : "Open Lead Validation"}
        </Link>
      )}
    </section>
  );
}
