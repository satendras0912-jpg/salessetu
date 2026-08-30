"use client";

import {
  useActionState,
} from "react";

import {
  cancelDealAction,
  linkDealBookingAction,
  markDealLostAction,
  markDealWonAction,
  putDealOnHoldAction,
} from "@/app/dashboard/deals/actions";

import {
  INITIAL_DEALOS_ACTION_STATE,
} from "@/lib/dealos/deal-contract";

import {
  isDealStatusTransitionAllowed,
} from "@/types/dealos";

import type {
  DealOSDataAccess,
  DealSummary,
} from "@/types/dealos";

import type {
  DealOSActionState,
  DealOSFieldErrors,
} from "@/types/dealos-actions";

type DealLifecycleActionsProps = {
  deal: DealSummary;
  access: DealOSDataAccess;
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
      className={`rounded-2xl border px-4 py-3 text-sm leading-6 ${messageClass}`}
    >
      {state.message}
    </div>
  );
}

export default function DealLifecycleActions({
  deal,
  access,
}: DealLifecycleActionsProps) {
  const [
    lostState,
    lostAction,
    isLostPending,
  ] = useActionState(
    markDealLostAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const [
    holdState,
    holdAction,
    isHoldPending,
  ] = useActionState(
    putDealOnHoldAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const [
    cancelState,
    cancelAction,
    isCancelPending,
  ] = useActionState(
    cancelDealAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const [
    bookingState,
    bookingAction,
    isBookingPending,
  ] = useActionState(
    linkDealBookingAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const [
    wonState,
    wonAction,
    isWonPending,
  ] = useActionState(
    markDealWonAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const canPutOnHold =
    access.canUpdateDeal &&
    deal.status !== "on_hold" &&
    isDealStatusTransitionAllowed(
      deal.status,
      "on_hold",
    );

  const canMarkLost =
    access.canMarkLost &&
    deal.status !== "lost" &&
    isDealStatusTransitionAllowed(
      deal.status,
      "lost",
    );

  const canCancelDeal =
    access.canUpdateDeal &&
    deal.status !== "cancelled" &&
    isDealStatusTransitionAllowed(
      deal.status,
      "cancelled",
    );

  const canLinkBooking =
    access.canHandoffBooking &&
    deal.status ===
      "booking_ready";

  const canMarkWon =
    access.canMarkWon &&
    access.canHandoffBooking &&
    deal.status ===
      "booking_ready" &&
    Boolean(
      deal.bookingId,
    );

  const hasAvailableActions =
    canPutOnHold ||
    canMarkLost ||
    canCancelDeal ||
    canLinkBooking ||
    canMarkWon;

  if (!hasAvailableActions) {
    return null;
  }

  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 sm:p-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
          Lifecycle controls
        </p>

        <h3 className="mt-3 text-xl font-semibold text-white">
          Special deal actions
        </h3>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          DealOS lifecycle contract aur
          current permissions ke according
          special actions apply karein.
        </p>
      </header>

      <div className="mt-6 grid gap-5 xl:grid-cols-2">
        {canPutOnHold ? (
          <form
            action={holdAction}
            noValidate
            className="space-y-4 rounded-2xl border border-amber-500/25 bg-amber-500/5 p-5"
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

            <div>
              <p className="text-sm font-semibold text-amber-200">
                Put deal on hold
              </p>

              <p className="mt-1 text-xs leading-5 text-slate-400">
                Temporarily pause this deal
                while preserving its
                commercial history.
              </p>
            </div>

            <ActionMessage
              state={holdState}
            />

            <div>
              <label
                htmlFor="holdReasonAction"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Hold reason
              </label>

              <textarea
                id="holdReasonAction"
                name="holdReason"
                rows={3}
                required
                defaultValue={
                  deal.holdReason ??
                  ""
                }
                aria-invalid={Boolean(
                  holdState.fieldErrors
                    .holdReason,
                )}
                aria-describedby={
                  holdState.fieldErrors
                    .holdReason
                    ? "holdReason-error"
                    : undefined
                }
                className={getInputClass(
                  Boolean(
                    holdState.fieldErrors
                      .holdReason,
                  ),
                )}
              />

              <FieldError
                fieldName="holdReason"
                errors={
                  holdState.fieldErrors
                }
              />
            </div>

            <FieldError
              fieldName="expectedUpdatedAt"
              errors={
                holdState.fieldErrors
              }
            />

            <button
              type="submit"
              disabled={isHoldPending}
              className="inline-flex w-full items-center justify-center rounded-xl bg-amber-300 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-amber-200 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isHoldPending
                ? "Putting on hold..."
                : "Put on hold"}
            </button>
          </form>
        ) : null}

        {canMarkLost ? (
          <form
            action={lostAction}
            noValidate
            className="space-y-4 rounded-2xl border border-red-500/25 bg-red-500/5 p-5"
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

            <div>
              <p className="text-sm font-semibold text-red-200">
                Mark deal lost
              </p>

              <p className="mt-1 text-xs leading-5 text-slate-400">
                Close this opportunity as
                lost with a mandatory reason.
              </p>
            </div>

            <ActionMessage
              state={lostState}
            />

            <div>
              <label
                htmlFor="lossReason"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Loss reason
              </label>

              <textarea
                id="lossReason"
                name="lossReason"
                rows={3}
                required
                aria-invalid={Boolean(
                  lostState.fieldErrors
                    .lossReason,
                )}
                aria-describedby={
                  lostState.fieldErrors
                    .lossReason
                    ? "lossReason-error"
                    : undefined
                }
                className={getInputClass(
                  Boolean(
                    lostState.fieldErrors
                      .lossReason,
                  ),
                )}
              />

              <FieldError
                fieldName="lossReason"
                errors={
                  lostState.fieldErrors
                }
              />
            </div>

            <FieldError
              fieldName="expectedUpdatedAt"
              errors={
                lostState.fieldErrors
              }
            />

            <button
              type="submit"
              disabled={isLostPending}
              className="inline-flex w-full items-center justify-center rounded-xl bg-red-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-red-300 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isLostPending
                ? "Marking lost..."
                : "Mark lost"}
            </button>
          </form>
        ) : null}

        {canCancelDeal ? (
          <form
            action={cancelAction}
            noValidate
            className="space-y-4 rounded-2xl border border-slate-700 bg-slate-950/50 p-5"
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

            <div>
              <p className="text-sm font-semibold text-white">
                Cancel deal
              </p>

              <p className="mt-1 text-xs leading-5 text-slate-400">
                Permanently close this deal
                as cancelled.
              </p>
            </div>

            <ActionMessage
              state={cancelState}
            />

            <div>
              <label
                htmlFor="cancellationReason"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Cancellation reason
              </label>

              <textarea
                id="cancellationReason"
                name="cancellationReason"
                rows={3}
                required
                aria-invalid={Boolean(
                  cancelState.fieldErrors
                    .cancellationReason,
                )}
                aria-describedby={
                  cancelState.fieldErrors
                    .cancellationReason
                    ? "cancellationReason-error"
                    : undefined
                }
                className={getInputClass(
                  Boolean(
                    cancelState.fieldErrors
                      .cancellationReason,
                  ),
                )}
              />

              <FieldError
                fieldName="cancellationReason"
                errors={
                  cancelState.fieldErrors
                }
              />
            </div>

            <FieldError
              fieldName="expectedUpdatedAt"
              errors={
                cancelState.fieldErrors
              }
            />

            <button
              type="submit"
              disabled={isCancelPending}
              className="inline-flex w-full items-center justify-center rounded-xl border border-slate-600 bg-slate-800 px-5 py-3 text-sm font-semibold text-white transition hover:bg-slate-700 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isCancelPending
                ? "Cancelling..."
                : "Cancel deal"}
            </button>
          </form>
        ) : null}

        {canLinkBooking ? (
          <form
            action={bookingAction}
            noValidate
            className="space-y-4 rounded-2xl border border-cyan-500/25 bg-cyan-500/5 p-5"
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

            <div>
              <p className="text-sm font-semibold text-cyan-200">
                Booking handoff
              </p>

              <p className="mt-1 text-xs leading-5 text-slate-400">
                Link the authoritative
                Booking Engine record before
                winning the deal.
              </p>
            </div>

            <ActionMessage
              state={bookingState}
            />

            <div>
              <label
                htmlFor="bookingId"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Booking ID
              </label>

              <input
                id="bookingId"
                name="bookingId"
                type="text"
                required
                defaultValue={
                  deal.bookingId ??
                  ""
                }
                placeholder="Booking UUID"
                autoComplete="off"
                aria-invalid={Boolean(
                  bookingState.fieldErrors
                    .bookingId,
                )}
                aria-describedby={
                  bookingState.fieldErrors
                    .bookingId
                    ? "bookingId-error"
                    : undefined
                }
                className={getInputClass(
                  Boolean(
                    bookingState.fieldErrors
                      .bookingId,
                  ),
                )}
              />

              <FieldError
                fieldName="bookingId"
                errors={
                  bookingState.fieldErrors
                }
              />
            </div>

            <FieldError
              fieldName="expectedUpdatedAt"
              errors={
                bookingState.fieldErrors
              }
            />

            <button
              type="submit"
              disabled={isBookingPending}
              className="inline-flex w-full items-center justify-center rounded-xl bg-cyan-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isBookingPending
                ? "Linking booking..."
                : deal.bookingId
                  ? "Update booking link"
                  : "Link booking"}
            </button>
          </form>
        ) : null}

        {canMarkWon ? (
          <form
            action={wonAction}
            noValidate
            className="space-y-4 rounded-2xl border border-emerald-500/30 bg-emerald-500/5 p-5"
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

            <div>
              <p className="text-sm font-semibold text-emerald-200">
                Mark deal won
              </p>

              <p className="mt-1 text-xs leading-5 text-slate-400">
                Booking is linked. Finalize
                this booking-ready deal as
                won.
              </p>
            </div>

            <ActionMessage
              state={wonState}
            />

            <div className="rounded-xl border border-emerald-500/20 bg-slate-950/50 px-4 py-3">
              <p className="text-xs uppercase tracking-wider text-slate-500">
                Linked booking
              </p>

              <p className="mt-2 break-all font-mono text-sm text-emerald-200">
                {deal.bookingId}
              </p>
            </div>

            <FieldError
              fieldName="expectedUpdatedAt"
              errors={
                wonState.fieldErrors
              }
            />

            <button
              type="submit"
              disabled={isWonPending}
              className="inline-flex w-full items-center justify-center rounded-xl bg-emerald-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-emerald-300 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {isWonPending
                ? "Marking won..."
                : "Mark deal won"}
            </button>
          </form>
        ) : null}
      </div>
    </section>
  );
}