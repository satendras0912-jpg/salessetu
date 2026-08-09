"use client";

import {
  useActionState,
} from "react";

import {
  cancelSiteVisitAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
} from "@/lib/leads/lead-operational-contract";

import type {
  OperationalActionState,
  SiteVisitSummary,
} from "@/types/lead-operational-controls";

type CancelSiteVisitFormProps = {
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

export default function CancelSiteVisitForm({
  visit,
}: CancelSiteVisitFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    cancelSiteVisitAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-red-950/70 bg-red-950/10 p-4"
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
        <p className="text-xs font-semibold uppercase tracking-wider text-red-400">
          Cancellation
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Cancel this visit and preserve the reason in the operational history.
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`siteVisitCancellationReason-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Cancellation reason
        </label>

        <textarea
          id={`siteVisitCancellationReason-${visit.id}`}
          name="reason"
          rows={3}
          required
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .reason
          }
          placeholder="Customer requested rescheduling or visit is no longer required."
          disabled={isPending}
          aria-invalid={
            Boolean(
              state.fieldErrors.reason,
            )
          }
          className="w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-red-500 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="reason"
        />
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex w-full items-center justify-center rounded-xl border border-red-800 bg-red-950/70 px-4 py-3 text-sm font-semibold text-red-200 transition hover:bg-red-900/70 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Cancelling..."
          : "Cancel site visit"}
      </button>
    </form>
  );
}