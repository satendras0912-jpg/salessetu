"use client";

import {
  useActionState,
  useState,
} from "react";

import {
  manageFollowUpSlaAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  FollowUpTaskSummary,
  OperationalActionState,
} from "@/types/lead-operational-controls";

type ManageFollowUpSlaFormProps = {
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

function toIsoTimestamp(
  localValue: string,
): string {
  if (!localValue) {
    return "";
  }

  const parsedDate =
    new Date(localValue);

  if (
    Number.isNaN(
      parsedDate.getTime(),
    )
  ) {
    return "";
  }

  return parsedDate.toISOString();
}

function toLocalDateTimeInput(
  timestamp: string | null,
): string {
  if (!timestamp) {
    return "";
  }

  const parsedDate =
    new Date(timestamp);

  if (
    Number.isNaN(
      parsedDate.getTime(),
    )
  ) {
    return "";
  }

  const timezoneOffset =
    parsedDate.getTimezoneOffset() *
    60_000;

  return new Date(
    parsedDate.getTime() -
      timezoneOffset,
  )
    .toISOString()
    .slice(0, 16);
}

export default function ManageFollowUpSlaForm({
  task,
}: ManageFollowUpSlaFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    manageFollowUpSlaAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  const [
    slaDueAtLocal,
    setSlaDueAtLocal,
  ] = useState(() =>
    toLocalDateTimeInput(
      task.slaDueAt,
    ),
  );

  const errors =
    state.fieldErrors;

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-violet-900/60 bg-violet-950/20 p-4"
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

      <input
        type="hidden"
        name="slaDueAt"
        value={toIsoTimestamp(
          slaDueAtLocal,
        )}
      />

      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-violet-300">
          SLA control
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Set or update the response deadline. Clear the date field to remove SLA tracking from this follow-up.
        </p>
      </div>

      <div className="rounded-xl border border-violet-900/50 bg-slate-950/40 px-4 py-3">
        <p className="text-xs uppercase tracking-wider text-slate-500">
          Current SLA status
        </p>

        <p className="mt-1 text-sm font-medium text-violet-200">
          {formatOperationalLabel(
            task.slaStatus,
          )}
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`followUpSlaDueAt-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          SLA deadline
        </label>

        <input
          id={`followUpSlaDueAt-${task.id}`}
          type="datetime-local"
          value={slaDueAtLocal}
          onChange={(event) => {
            setSlaDueAtLocal(
              event.target.value,
            );
          }}
          disabled={isPending}
          aria-invalid={
            Boolean(errors.slaDueAt)
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-violet-500 focus:ring-2 focus:ring-violet-500/20 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <p className="mt-2 text-xs leading-5 text-slate-500">
          Leaving this field empty will clear the SLA deadline.
        </p>

        <FieldError
          state={state}
          fieldName="slaDueAt"
        />
      </div>

      <div>
        <label
          htmlFor={`followUpSlaReason-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          SLA change reason
        </label>

        <textarea
          id={`followUpSlaReason-${task.id}`}
          name="reason"
          rows={3}
          required
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .reason
          }
          placeholder="Priority lead requires a monitored response deadline."
          disabled={isPending}
          aria-invalid={
            Boolean(errors.reason)
          }
          className="w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-violet-500 focus:ring-2 focus:ring-violet-500/20 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="reason"
        />
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex w-full items-center justify-center rounded-xl border border-violet-700 bg-violet-950/70 px-4 py-3 text-sm font-semibold text-violet-200 transition hover:bg-violet-900/70 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Saving SLA..."
          : "Save SLA"}
      </button>
    </form>
  );
}