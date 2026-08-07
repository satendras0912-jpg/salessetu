"use client";

import {
  useActionState,
} from "react";

import {
  completeFollowUpAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
} from "@/lib/leads/lead-operational-contract";

import type {
  FollowUpTaskSummary,
  OperationalActionState,
} from "@/types/lead-operational-controls";

type CompleteFollowUpFormProps = {
  task: FollowUpTaskSummary;
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
    <div className="mt-2 space-y-1">
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

export default function CompleteFollowUpForm({
  task,
}: CompleteFollowUpFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    completeFollowUpAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-emerald-900/60 bg-emerald-950/20 p-4"
    >
      <input
        type="hidden"
        name="taskId"
        value={task.id}
      />

      <input
        type="hidden"
        name="expectedUpdatedAt"
        value={task.updatedAt}
      />

      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-emerald-400">
          Completion
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Record the customer outcome before closing this follow-up.
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`followUpOutcome-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Outcome
        </label>

        <input
          id={`followUpOutcome-${task.id}`}
          name="outcome"
          type="text"
          required
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .shortText
          }
          placeholder="Connected — customer requested brochure"
          disabled={isPending}
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-emerald-500 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="outcome"
        />
      </div>

      <div>
        <label
          htmlFor={`followUpNotes-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Completion notes
        </label>

        <textarea
          id={`followUpNotes-${task.id}`}
          name="notes"
          rows={3}
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .notes
          }
          placeholder="Add discussion notes and the recommended next step."
          disabled={isPending}
          className="w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-emerald-500 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="notes"
        />
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex w-full items-center justify-center rounded-xl bg-emerald-500 px-4 py-3 text-sm font-semibold text-emerald-950 transition hover:bg-emerald-400 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Completing..."
          : "Complete follow-up"}
      </button>
    </form>
  );
}
