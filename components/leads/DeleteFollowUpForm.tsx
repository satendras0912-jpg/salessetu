"use client";

import {
  useActionState,
} from "react";

import {
  deleteFollowUpAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
} from "@/lib/leads/lead-operational-contract";

import type {
  FollowUpTaskSummary,
  OperationalActionState,
} from "@/types/lead-operational-controls";

type DeleteFollowUpFormProps = {
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

export default function DeleteFollowUpForm({
  task,
}: DeleteFollowUpFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    deleteFollowUpAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-red-950/80 bg-red-950/15 p-4"
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
        <p className="text-xs font-semibold uppercase tracking-wider text-red-400">
          Delete record
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Remove this follow-up from operational views while retaining its audit metadata. Use this only for duplicate, test or invalid records.
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`followUpDeletionReason-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Deletion reason
        </label>

        <textarea
          id={`followUpDeletionReason-${task.id}`}
          name="reason"
          rows={3}
          required
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .reason
          }
          placeholder="Duplicate, test or invalid follow-up record."
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
        className="inline-flex w-full items-center justify-center rounded-xl border border-red-700 bg-red-950 px-4 py-3 text-sm font-semibold text-red-200 transition hover:bg-red-900 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Deleting..."
          : "Delete follow-up"}
      </button>
    </form>
  );
}