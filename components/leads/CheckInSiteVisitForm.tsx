"use client";

import {
  useActionState,
} from "react";

import {
  checkInSiteVisitAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  SITE_VISIT_CHECK_IN_METHODS,
  SITE_VISIT_PARTIES,
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  OperationalActionState,
  SiteVisitSummary,
} from "@/types/lead-operational-controls";

type CheckInSiteVisitFormProps = {
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

export default function CheckInSiteVisitForm({
  visit,
}: CheckInSiteVisitFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    checkInSiteVisitAction,
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
        <p className="text-xs font-semibold uppercase tracking-wider text-amber-400">
          Check in
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Record customer or agent arrival at the site visit.
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`siteVisitCheckInParty-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Party
        </label>

        <select
          id={`siteVisitCheckInParty-${visit.id}`}
          name="party"
          defaultValue="customer"
          disabled={isPending}
          aria-invalid={
            Boolean(errors.party)
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-amber-500 disabled:cursor-not-allowed disabled:opacity-60"
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

      <div>
        <label
          htmlFor={`siteVisitCheckInMethod-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Check-in method
        </label>

        <select
          id={`siteVisitCheckInMethod-${visit.id}`}
          name="method"
          defaultValue="manual"
          disabled={isPending}
          aria-invalid={
            Boolean(errors.method)
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-amber-500 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {SITE_VISIT_CHECK_IN_METHODS.map(
            (method) => (
              <option
                key={method}
                value={method}
              >
                {formatOperationalLabel(
                  method,
                )}
              </option>
            ),
          )}
        </select>

        <FieldError
          state={state}
          fieldName="method"
        />
      </div>

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label
            htmlFor={`siteVisitLatitude-${visit.id}`}
            className="mb-2 block text-xs font-medium text-slate-300"
          >
            Latitude
          </label>

          <input
            id={`siteVisitLatitude-${visit.id}`}
            name="latitude"
            type="number"
            step="any"
            min="-90"
            max="90"
            placeholder="28.5355"
            disabled={isPending}
            aria-invalid={
              Boolean(errors.latitude)
            }
            className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-amber-500 disabled:cursor-not-allowed disabled:opacity-60"
          />

          <FieldError
            state={state}
            fieldName="latitude"
          />
        </div>

        <div>
          <label
            htmlFor={`siteVisitLongitude-${visit.id}`}
            className="mb-2 block text-xs font-medium text-slate-300"
          >
            Longitude
          </label>

          <input
            id={`siteVisitLongitude-${visit.id}`}
            name="longitude"
            type="number"
            step="any"
            min="-180"
            max="180"
            placeholder="77.3910"
            disabled={isPending}
            aria-invalid={
              Boolean(errors.longitude)
            }
            className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-amber-500 disabled:cursor-not-allowed disabled:opacity-60"
          />

          <FieldError
            state={state}
            fieldName="longitude"
          />
        </div>
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex w-full items-center justify-center rounded-xl bg-amber-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-amber-300 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Checking in..."
          : "Record check-in"}
      </button>
    </form>
  );
}