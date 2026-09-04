"use client";

import {
  useActionState,
  useState,
} from "react";

import {
  rescheduleFollowUpAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
} from "@/lib/leads/lead-operational-contract";

import type {
  FollowUpTaskSummary,
  OperationalActionState,
} from "@/types/lead-operational-controls";

type RescheduleFollowUpFormProps = {
  task: FollowUpTaskSummary;
};

const INPUT_CLASS =
  "w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-amber-500 focus:ring-2 focus:ring-amber-500/20 disabled:cursor-not-allowed disabled:opacity-60";

const ERROR_INPUT_CLASS =
  "border-red-500 focus:border-red-400 focus:ring-red-500/20";

function getInputClass(
  hasError: boolean,
): string {
  return [
    INPUT_CLASS,
    hasError
      ? ERROR_INPUT_CLASS
      : "",
  ]
    .filter(Boolean)
    .join(" ");
}

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

export default function RescheduleFollowUpForm({
  task,
}: RescheduleFollowUpFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    rescheduleFollowUpAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  const [
    dueAtLocal,
    setDueAtLocal,
  ] = useState(() =>
    toLocalDateTimeInput(
      task.dueAt,
    ),
  );

  const [
    reminderAtLocal,
    setReminderAtLocal,
  ] = useState(() =>
    toLocalDateTimeInput(
      task.reminderAt,
    ),
  );

  const errors =
    state.fieldErrors;

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-amber-900/60 bg-amber-950/20 p-4"
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
        name="dueAt"
        value={toIsoTimestamp(
          dueAtLocal,
        )}
      />

      <input
        type="hidden"
        name="reminderAt"
        value={toIsoTimestamp(
          reminderAtLocal,
        )}
      />

      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-amber-400">
          Reschedule
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Move this active follow-up to a new due time and record the reason.
        </p>
      </div>

      <ActionMessage state={state} />

      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <label
            htmlFor={`followUpDueAt-${task.id}`}
            className="mb-2 block text-xs font-medium text-slate-300"
          >
            New due date and time
          </label>

          <input
            id={`followUpDueAt-${task.id}`}
            type="datetime-local"
            required
            value={dueAtLocal}
            onChange={(event) => {
              setDueAtLocal(
                event.target.value,
              );
            }}
            disabled={isPending}
            aria-invalid={
              Boolean(errors.dueAt)
            }
            className={getInputClass(
              Boolean(errors.dueAt),
            )}
          />

          <FieldError
            state={state}
            fieldName="dueAt"
          />
        </div>

        <div>
          <label
            htmlFor={`followUpReminderAt-${task.id}`}
            className="mb-2 block text-xs font-medium text-slate-300"
          >
            Reminder date and time
          </label>

          <input
            id={`followUpReminderAt-${task.id}`}
            type="datetime-local"
            value={reminderAtLocal}
            max={dueAtLocal || undefined}
            onChange={(event) => {
              setReminderAtLocal(
                event.target.value,
              );
            }}
            disabled={isPending}
            aria-invalid={
              Boolean(
                errors.reminderAt,
              )
            }
            className={getInputClass(
              Boolean(
                errors.reminderAt,
              ),
            )}
          />

          <p className="mt-2 text-xs leading-5 text-slate-500">
            Optional. Keep it on or before the new due time.
          </p>

          <FieldError
            state={state}
            fieldName="reminderAt"
          />
        </div>
      </div>

      <div>
        <label
          htmlFor={`followUpRescheduleReason-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Reschedule reason
        </label>

        <textarea
          id={`followUpRescheduleReason-${task.id}`}
          name="reason"
          rows={3}
          required
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .reason
          }
          placeholder="Customer requested another date or time."
          disabled={isPending}
          aria-invalid={
            Boolean(errors.reason)
          }
          className={getInputClass(
            Boolean(errors.reason),
          )}
        />

        <FieldError
          state={state}
          fieldName="reason"
        />
      </div>

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex w-full items-center justify-center rounded-xl border border-amber-700 bg-amber-950/60 px-4 py-3 text-sm font-semibold text-amber-200 transition hover:bg-amber-900/60 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Rescheduling..."
          : "Save new schedule"}
      </button>
    </form>
  );
}