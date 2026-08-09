"use client";

import {
  useActionState,
} from "react";

import {
  checkOutSiteVisitAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  SITE_VISIT_PARTIES,
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  OperationalActionState,
  SiteVisitSummary,
} from "@/types/lead-operational-controls";

type CheckOutSiteVisitFormProps = {
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

export default function CheckOutSiteVisitForm({
  visit,
}: CheckOutSiteVisitFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    checkOutSiteVisitAction,
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
        <p className="text-xs font-semibold uppercase tracking-wider text-violet-400">
          Check out
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Record when the customer or agent leaves the site visit.
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`siteVisitCheckOutParty-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Party
        </label>

        <select
          id={`siteVisitCheckOutParty-${visit.id}`}
          name="party"
          defaultValue="customer"
          disabled={isPending}
          aria-invalid={
            Boolean(errors.party)
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-violet-500 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {SITE_VISIT_PARTIES.map(
            (party) => (
              <option
                key={party}
                value={party}
              >
                {formatOperationalLabel(
                  party,
                )}
              </option>
            ),
          )}
        </select>

        <FieldError
          state={state}
          fieldName="party"
        />
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex w-full items-center justify-center rounded-xl bg-violet-500 px-4 py-3 text-sm font-semibold text-white transition hover:bg-violet-400 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Checking out..."
          : "Record check-out"}
      </button>
    </form>
  );
}