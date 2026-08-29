"use client";

import {
  useActionState,
} from "react";

import {
  changeDealStatusAction,
} from "@/app/dashboard/deals/actions";

import {
  INITIAL_DEALOS_ACTION_STATE,
} from "@/lib/dealos/deal-contract";

import {
  DEAL_STATUS_TRANSITIONS,
} from "@/types/dealos";

import type {
  DealOSActionState,
  DealOSFieldErrors,
} from "@/types/dealos-actions";

import type {
  DealStatus,
  GenericDealStatusTarget,
} from "@/types/dealos";

type DealStatusTransitionFormProps = {
  dealId: string;
  currentStatus: DealStatus;
  updatedAt: string;
};

type FieldErrorProps = {
  fieldName: string;
  errors: DealOSFieldErrors;
};

const GENERIC_STATUS_TARGETS:
  readonly GenericDealStatusTarget[] = [
    "open",
    "negotiation",
    "commercial_review",
    "approved",
    "booking_ready",
  ];

const INPUT_CLASS =
  "w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20";

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

function formatLabel(
  value: string,
): string {
  return value
    .replaceAll("_", " ")
    .replaceAll("-", " ")
    .replace(
      /\b\w/g,
      (character) =>
        character.toUpperCase(),
    );
}

function FieldError({
  fieldName,
  errors,
}: FieldErrorProps) {
  const fieldErrors =
    errors[fieldName] ?? [];

  if (
    fieldErrors.length === 0
  ) {
    return null;
  }

  return (
    <div
      id={`${fieldName}-error`}
      className="mt-2 space-y-1"
    >
      {fieldErrors.map(
        (message) => (
          <p
            key={message}
            className="text-xs leading-5 text-red-300"
          >
            {message}
          </p>
        ),
      )}
    </div>
  );
}

function ActionMessage({
  state,
}: {
  state: DealOSActionState;
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
      : state.status ===
          "conflict"
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

export default function DealStatusTransitionForm({
  dealId,
  currentStatus,
  updatedAt,
}: DealStatusTransitionFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    changeDealStatusAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const errors =
    state.fieldErrors;

  const allowedTargets =
    DEAL_STATUS_TRANSITIONS[
      currentStatus
    ].filter(
      (
        status,
      ): status is GenericDealStatusTarget =>
        GENERIC_STATUS_TARGETS.includes(
          status as GenericDealStatusTarget,
        ),
    );

  if (
    allowedTargets.length === 0
  ) {
    return (
      <section className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 sm:p-6">
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-slate-500">
          Status transition
        </p>

        <h3 className="mt-3 text-xl font-semibold text-white">
          No standard transition available
        </h3>

        <p className="mt-2 text-sm leading-6 text-slate-400">
          This deal has no available generic
          DealOS status transition from its
          current state.
        </p>
      </section>
    );
  }

  return (
    <section className="rounded-2xl border border-cyan-500/30 bg-cyan-500/5 p-5 sm:p-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
          Status transition
        </p>

        <h3 className="mt-3 text-xl font-semibold text-white">
          Move deal through the pipeline
        </h3>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Sirf lifecycle contract ke
          according valid DealOS status
          transition apply karein.
        </p>
      </header>

      <form
        action={formAction}
        noValidate
        className="mt-6 space-y-6"
      >
        <input
          type="hidden"
          name="dealId"
          value={dealId}
        />

        <input
          type="hidden"
          name="expectedUpdatedAt"
          value={updatedAt}
        />

        <ActionMessage
          state={state}
        />

        <div>
          <label
            htmlFor="status"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            New deal status
          </label>

          <select
            id="status"
            name="status"
            defaultValue=""
            required
            aria-invalid={Boolean(
              errors.status,
            )}
            aria-describedby={
              errors.status
                ? "status-error"
                : undefined
            }
            className={getInputClass(
              Boolean(
                errors.status,
              ),
            )}
          >
            <option
              value=""
              disabled
            >
              Select next status
            </option>

            {allowedTargets.map(
              (status) => (
                <option
                  key={status}
                  value={status}
                >
                  {formatLabel(
                    status,
                  )}
                </option>
              ),
            )}
          </select>

          <FieldError
            fieldName="status"
            errors={errors}
          />
        </div>

        <FieldError
          fieldName="expectedUpdatedAt"
          errors={errors}
        />

        <div className="flex flex-col justify-between gap-4 border-t border-slate-800 pt-5 sm:flex-row sm:items-center">
          <div className="text-xs leading-5 text-slate-500">
            <p>
              Current status:{" "}
              <span className="font-medium text-slate-300">
                {formatLabel(
                  currentStatus,
                )}
              </span>
            </p>

            <p>
              Last loaded:{" "}
              <span className="font-medium text-slate-300">
                {new Intl.DateTimeFormat(
                  "en-IN",
                  {
                    dateStyle:
                      "medium",
                    timeStyle:
                      "short",
                    timeZone:
                      "Asia/Kolkata",
                  },
                ).format(
                  new Date(
                    updatedAt,
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
              ? "Updating deal..."
              : "Apply transition"}
          </button>
        </div>
      </form>
    </section>
  );
}