"use client";

import {
  useActionState,
} from "react";

import {
  updateDealAction,
} from "@/app/dashboard/deals/actions";

import {
  INITIAL_DEALOS_ACTION_STATE,
} from "@/lib/dealos/deal-contract";

import type {
  DealSummary,
} from "@/types/dealos";

import type {
  DealOSActionState,
  DealOSFieldErrors,
} from "@/types/dealos-actions";

import type {
  OrganizationMemberOption,
} from "@/types/lead-operational-controls";

type DealUpdateFormProps = {
  deal: DealSummary;

  assigneeOptions:
    OrganizationMemberOption[];

  canAssignDeal: boolean;
};

type FieldErrorProps = {
  fieldName: string;
  errors: DealOSFieldErrors;
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
    hasError
      ? ERROR_INPUT_CLASS
      : "",
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

function toDateTimeLocalValue(
  value: string | null,
): string {
  if (!value) {
    return "";
  }

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime(),
    )
  ) {
    return "";
  }

  const parts =
    new Intl.DateTimeFormat(
      "en-CA",
      {
        timeZone:
          "Asia/Kolkata",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
        hour: "2-digit",
        minute: "2-digit",
        hourCycle: "h23",
      },
    ).formatToParts(
      date,
    );

  const getPart = (
    type: Intl.DateTimeFormatPartTypes,
  ) =>
    parts.find(
      (part) =>
        part.type === type,
    )?.value ?? "";

  return `${getPart("year")}-${getPart("month")}-${getPart("day")}T${getPart("hour")}:${getPart("minute")}`;
}

function toProbabilityValue(
  value:
    | number
    | string
    | null,
): string {
  if (
    value === null
  ) {
    return "";
  }

  const parsed =
    Number(value);

  return Number.isFinite(
    parsed,
  )
    ? String(parsed)
    : "";
}

export default function DealUpdateForm({
  deal,
  assigneeOptions,
  canAssignDeal,
}: DealUpdateFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    updateDealAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const errors =
    state.fieldErrors;

  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 sm:p-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
          Deal operations
        </p>

        <h3 className="mt-3 text-xl font-semibold text-white">
          Update deal details
        </h3>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Assignment, probability, next
          action and operational notes
          update karein.
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
          value={deal.id}
        />

        <input
          type="hidden"
          name="expectedUpdatedAt"
          value={deal.updatedAt}
        />

        <ActionMessage
          state={state}
        />

        <div className="grid gap-5 lg:grid-cols-2">
          {canAssignDeal ? (
            <div>
              <label
                htmlFor="assignedTo"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Assigned user
              </label>

              <select
                id="assignedTo"
                name="assignedTo"
                defaultValue={
                  deal.assignedTo ??
                  ""
                }
                aria-invalid={Boolean(
                  errors.assignedTo,
                )}
                aria-describedby={
                  errors.assignedTo
                    ? "assignedTo-error"
                    : undefined
                }
                className={getInputClass(
                  Boolean(
                    errors.assignedTo,
                  ),
                )}
              >
                <option value="">
                  Unassigned
                </option>

                {assigneeOptions.map(
                  (member) => (
                    <option
                      key={
                        member.userId
                      }
                      value={
                        member.userId
                      }
                    >
                      {
                        member.displayName
                      }
                    </option>
                  ),
                )}
              </select>

              <FieldError
                fieldName="assignedTo"
                errors={errors}
              />
            </div>
          ) : null}

          <div>
            <label
              htmlFor="bookingProbability"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Booking probability
            </label>

            <input
              id="bookingProbability"
              name="bookingProbability"
              type="number"
              min="0"
              max="100"
              step="1"
              defaultValue={
                toProbabilityValue(
                  deal.bookingProbability,
                )
              }
              placeholder="0 - 100"
              aria-invalid={Boolean(
                errors.bookingProbability,
              )}
              aria-describedby={
                errors.bookingProbability
                  ? "bookingProbability-error"
                  : undefined
              }
              className={getInputClass(
                Boolean(
                  errors.bookingProbability,
                ),
              )}
            />

            <FieldError
              fieldName="bookingProbability"
              errors={errors}
            />
          </div>

          <div>
            <label
              htmlFor="nextActionAt"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Next action
            </label>

            <input
              id="nextActionAt"
              name="nextActionAt"
              type="datetime-local"
              defaultValue={
                toDateTimeLocalValue(
                  deal.nextActionAt,
                )
              }
              aria-invalid={Boolean(
                errors.nextActionAt,
              )}
              aria-describedby={
                errors.nextActionAt
                  ? "nextActionAt-error"
                  : undefined
              }
              className={getInputClass(
                Boolean(
                  errors.nextActionAt,
                ),
              )}
            />

            <FieldError
              fieldName="nextActionAt"
              errors={errors}
            />
          </div>
        </div>

        <div>
          <label
            htmlFor="holdReason"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            Hold reason
          </label>

          <textarea
            id="holdReason"
            name="holdReason"
            rows={3}
            defaultValue={
              deal.holdReason ??
              ""
            }
            aria-invalid={Boolean(
              errors.holdReason,
            )}
            aria-describedby={
              errors.holdReason
                ? "holdReason-error"
                : undefined
            }
            className={getInputClass(
              Boolean(
                errors.holdReason,
              ),
            )}
          />

          <FieldError
            fieldName="holdReason"
            errors={errors}
          />
        </div>

        <div>
          <label
            htmlFor="notes"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            Deal notes
          </label>

          <textarea
            id="notes"
            name="notes"
            rows={5}
            defaultValue={
              deal.notes ??
              ""
            }
            aria-invalid={Boolean(
              errors.notes,
            )}
            aria-describedby={
              errors.notes
                ? "notes-error"
                : undefined
            }
            className={getInputClass(
              Boolean(
                errors.notes,
              ),
            )}
          />

          <FieldError
            fieldName="notes"
            errors={errors}
          />
        </div>

        <FieldError
          fieldName="expectedUpdatedAt"
          errors={errors}
        />

        <div className="flex flex-col justify-between gap-4 border-t border-slate-800 pt-5 sm:flex-row sm:items-center">
          <p className="text-xs leading-5 text-slate-500">
            Existing values ko blank
            karke nullable fields clear
            bhi kiye ja sakte hain.
          </p>

          <button
            type="submit"
            disabled={isPending}
            className="inline-flex min-w-44 items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isPending
              ? "Saving..."
              : "Save deal"}
          </button>
        </div>
      </form>
    </section>
  );
}