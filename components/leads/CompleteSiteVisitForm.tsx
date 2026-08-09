"use client";

import {
  useActionState,
} from "react";

import {
  completeSiteVisitAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
  SITE_VISIT_OUTCOMES,
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  OperationalActionState,
  SiteVisitSummary,
} from "@/types/lead-operational-controls";

type CompleteSiteVisitFormProps = {
  visit: SiteVisitSummary;
};

function FieldError({
  state,
  fieldName,
}: {
  state: OperationalActionState;
  fieldName: string;
}) {
  const messages =
    state.fieldErrors[fieldName] ?? [];

  if (messages.length === 0) {
    return null;
  }

  return (
    <div
      id={`${fieldName}-error`}
      className="mt-2 space-y-1"
    >
      {messages.map((message) => (
        <p
          key={message}
          className="text-xs leading-5 text-red-300"
        >
          {message}
        </p>
      ))}
    </div>
  );
}

function ActionMessage({
  state,
}: {
  state: OperationalActionState;
}) {
  if (
    state.status === "idle" ||
    !state.message
  ) {
    return null;
  }

  const className =
    state.status === "conflict"
      ? "border-amber-500/40 bg-amber-500/10 text-amber-200"
      : "border-red-500/40 bg-red-500/10 text-red-200";

  return (
    <div
      aria-live="polite"
      className={`rounded-xl border px-4 py-3 text-xs leading-5 ${className}`}
    >
      {state.message}
    </div>
  );
}

export default function CompleteSiteVisitForm({
  visit,
}: CompleteSiteVisitFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    completeSiteVisitAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  const errors =
    state.fieldErrors;

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-slate-800 bg-slate-950/60 p-4"
    >
      <input
        type="hidden"
        name="siteVisitId"
        value={visit.id}
      />

      <input
        type="hidden"
        name="expectedUpdatedAt"
        value={visit.updatedAt}
      />

      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-emerald-400">
          Completion
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Record the commercial outcome before closing this site visit.
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`siteVisitOutcome-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Outcome
        </label>

        <select
          id={`siteVisitOutcome-${visit.id}`}
          name="outcome"
          defaultValue=""
          required
          disabled={isPending}
          aria-invalid={
            Boolean(errors.outcome)
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-emerald-500 disabled:cursor-not-allowed disabled:opacity-60"
        >
          <option
            value=""
            disabled
          >
            Select outcome
          </option>

          {SITE_VISIT_OUTCOMES.map(
            (outcome) => (
              <option
                key={outcome}
                value={outcome}
              >
                {formatOperationalLabel(
                  outcome,
                )}
              </option>
            ),
          )}
        </select>

        <FieldError
          state={state}
          fieldName="outcome"
        />
      </div>

      <div>
        <label
          htmlFor={`siteVisitOutcomeSummary-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Outcome summary
        </label>

        <textarea
          id={`siteVisitOutcomeSummary-${visit.id}`}
          name="outcomeSummary"
          rows={3}
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .mediumText
          }
          placeholder="Summarise customer interest, objections and next commitment."
          disabled={isPending}
          aria-invalid={
            Boolean(
              errors.outcomeSummary,
            )
          }
          className="w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-emerald-500 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="outcomeSummary"
        />
      </div>

      <div>
        <label
          htmlFor={`siteVisitProbability-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Booking probability (%)
        </label>

        <input
          id={`siteVisitProbability-${visit.id}`}
          name="probabilityOfBooking"
          type="number"
          min={
            OPERATIONAL_FORM_LIMITS
              .probabilityMinimum
          }
          max={
            OPERATIONAL_FORM_LIMITS
              .probabilityMaximum
          }
          step="1"
          placeholder="70"
          disabled={isPending}
          aria-invalid={
            Boolean(
              errors.probabilityOfBooking,
            )
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-emerald-500 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="probabilityOfBooking"
        />
      </div>

      <div>
        <label
          htmlFor={`siteVisitAgentNotes-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Agent notes
        </label>

        <textarea
          id={`siteVisitAgentNotes-${visit.id}`}
          name="agentNotes"
          rows={4}
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .notes
          }
          placeholder="Add observations, negotiation notes and recommended next action."
          disabled={isPending}
          aria-invalid={
            Boolean(errors.agentNotes)
          }
          className="w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-emerald-500 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="agentNotes"
        />
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex w-full items-center justify-center rounded-xl bg-emerald-500 px-4 py-3 text-sm font-semibold text-emerald-950 transition hover:bg-emerald-400 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Completing..."
          : "Complete site visit"}
      </button>
    </form>
  );
}