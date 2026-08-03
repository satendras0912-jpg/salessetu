"use client";

import {
  useActionState,
} from "react";

import {
  transitionLeadStatusAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  LEAD_LIFECYCLE_STAGES,
  LEAD_STATUSES,
  LEAD_TEMPERATURES,
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  LeadOperationalSnapshot,
  OperationalActionState,
  OperationalFieldErrors,
} from "@/types/lead-operational-controls";

type LeadStatusTransitionFormProps = {
  snapshot: LeadOperationalSnapshot;
};

type FieldErrorProps = {
  fieldName: string;
  errors: OperationalFieldErrors;
};

const INPUT_CLASS =
  "w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20";

const ERROR_INPUT_CLASS =
  "border-red-500 focus:border-red-400 focus:ring-red-500/20";

function getInputClass(
  hasError: boolean,
): string {
  return [
    INPUT_CLASS,
    hasError ? ERROR_INPUT_CLASS : "",
  ]
    .filter(Boolean)
    .join(" ");
}

function FieldError({
  fieldName,
  errors,
}: FieldErrorProps) {
  const fieldErrors =
    errors[fieldName] ?? [];

  if (fieldErrors.length === 0) {
    return null;
  }

  return (
    <div
      id={`${fieldName}-error`}
      className="mt-2 space-y-1"
    >
      {fieldErrors.map((message) => (
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

  const messageClass =
    state.status === "success"
      ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-200"
      : state.status === "conflict"
        ? "border-amber-500/40 bg-amber-500/10 text-amber-200"
        : "border-red-500/40 bg-red-500/10 text-red-200";

  return (
    <div
      aria-live="polite"
      className={`rounded-2xl border px-5 py-4 text-sm leading-6 ${messageClass}`}
    >
      {state.message}
    </div>
  );
}

export default function LeadStatusTransitionForm({
  snapshot,
}: LeadStatusTransitionFormProps) {

  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    transitionLeadStatusAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  const errors =
    state.fieldErrors;

  return (
    <section className="rounded-2xl border border-cyan-500/30 bg-cyan-500/5 p-5 sm:p-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
          Status Transition
        </p>

        <h3 className="mt-3 text-xl font-semibold text-white">
          Update lead journey
        </h3>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Lead status, lifecycle stage और
          temperature को controlled operational
          transition के रूप में update करें।
        </p>
      </header>

      <form
        action={formAction}
        noValidate
        className="mt-6 space-y-6"
      >
        <input
          type="hidden"
          name="leadId"
          value={snapshot.leadId}
        />

        <input
          type="hidden"
          name="expectedUpdatedAt"
          value={snapshot.updatedAt}
        />

        <ActionMessage state={state} />

        <div className="grid gap-5 md:grid-cols-2 xl:grid-cols-3">
          <div>
            <label
              htmlFor="leadStatus"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Lead status
            </label>

            <select
              id="leadStatus"
              name="leadStatus"
              defaultValue={
                snapshot.leadStatus
              }
              aria-invalid={
                Boolean(errors.leadStatus)
              }
              aria-describedby={
                errors.leadStatus
                  ? "leadStatus-error"
                  : undefined
              }
              className={getInputClass(
                Boolean(errors.leadStatus),
              )}
            >
              {LEAD_STATUSES.map(
                (status) => (
                  <option
                    key={status}
                    value={status}
                  >
                    {formatOperationalLabel(
                      status,
                    )}
                  </option>
                ),
              )}
            </select>

            <FieldError
              fieldName="leadStatus"
              errors={errors}
            />
          </div>

          <div>
            <label
              htmlFor="lifecycleStage"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Lifecycle stage
            </label>

            <select
              id="lifecycleStage"
              name="lifecycleStage"
              defaultValue={
                snapshot.lifecycleStage
              }
              aria-invalid={
                Boolean(
                  errors.lifecycleStage,
                )
              }
              aria-describedby={
                errors.lifecycleStage
                  ? "lifecycleStage-error"
                  : undefined
              }
              className={getInputClass(
                Boolean(
                  errors.lifecycleStage,
                ),
              )}
            >
              {LEAD_LIFECYCLE_STAGES.map(
                (stage) => (
                  <option
                    key={stage}
                    value={stage}
                  >
                    {formatOperationalLabel(
                      stage,
                    )}
                  </option>
                ),
              )}
            </select>

            <FieldError
              fieldName="lifecycleStage"
              errors={errors}
            />
          </div>

          <div>
            <label
              htmlFor="leadTemperature"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Lead temperature
            </label>

            <select
              id="leadTemperature"
              name="leadTemperature"
              defaultValue={
                snapshot.leadTemperature ??
                ""
              }
              aria-invalid={
                Boolean(
                  errors.leadTemperature,
                )
              }
              aria-describedby={
                errors.leadTemperature
                  ? "leadTemperature-error"
                  : undefined
              }
              className={getInputClass(
                Boolean(
                  errors.leadTemperature,
                ),
              )}
            >
              <option value="">
                Not specified
              </option>

              {LEAD_TEMPERATURES.map(
                (temperature) => (
                  <option
                    key={temperature}
                    value={temperature}
                  >
                    {formatOperationalLabel(
                      temperature,
                    )}
                  </option>
                ),
              )}
            </select>

            <FieldError
              fieldName="leadTemperature"
              errors={errors}
            />
          </div>
        </div>

        <div>
          <label
            htmlFor="reason"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            Transition reason
          </label>

          <textarea
            id="reason"
            name="reason"
            rows={4}
            placeholder="Describe why the lead status is being changed."
            aria-invalid={
              Boolean(errors.reason)
            }
            aria-describedby={
              errors.reason
                ? "reason-error"
                : "reason-helper"
            }
            className={getInputClass(
              Boolean(errors.reason),
            )}
          />

          <p
            id="reason-helper"
            className="mt-2 text-xs leading-5 text-slate-500"
          >
            यह reason lead metadata और operational
            audit context में सुरक्षित रहेगा।
          </p>

          <FieldError
            fieldName="reason"
            errors={errors}
          />
        </div>

        <div className="flex flex-col justify-between gap-4 border-t border-slate-800 pt-5 sm:flex-row sm:items-center">
          <div className="text-xs leading-5 text-slate-500">
            <p>
              Current status:{" "}
              <span className="font-medium text-slate-300">
                {formatOperationalLabel(
                  snapshot.leadStatus,
                )}
              </span>
            </p>

            <p>
              Last loaded:{" "}
              <span className="font-medium text-slate-300">
                {new Intl.DateTimeFormat(
                  "en-IN",
                  {
                    dateStyle: "medium",
                    timeStyle: "short",
                  },
                ).format(
                  new Date(
                    snapshot.updatedAt,
                  ),
                )}
              </span>
            </p>
          </div>

          <button
            type="submit"
            disabled={isPending}
            className="inline-flex min-w-48 items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isPending
              ? "Updating status..."
              : "Apply status transition"}
          </button>
        </div>
      </form>
    </section>
  );
}