"use client";

import {
  useActionState,
} from "react";

import {
  cancelCommercialApprovalAction,
  createDealOfferAction,
  decideCommercialApprovalAction,
  requestCommercialApprovalAction,
  updateDealOfferStatusAction,
} from "@/app/dashboard/deals/actions";

import {
  INITIAL_DEALOS_ACTION_STATE,
} from "@/lib/dealos/deal-contract";

import type {
  DealCommercialApprovalSummary,
  DealOfferStatus,
  DealOfferSummary,
  DealOSDataAccess,
  DealSummary,
} from "@/types/dealos";

import type {
  DealOSActionState,
  DealOSFieldErrors,
} from "@/types/dealos-actions";

type DealCommercialActionsProps = {
  deal: DealSummary;
  offers: DealOfferSummary[];
  approvals: DealCommercialApprovalSummary[];
  access: DealOSDataAccess;
  currentUserId: string;
};

type FieldErrorProps = {
  fieldName: string;
  errors: DealOSFieldErrors;
};

const INPUT_CLASS =
  "w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20";

const ERROR_INPUT_CLASS =
  "border-red-500 focus:border-red-400 focus:ring-red-500/20";

const TERMINAL_DEAL_STATUSES = [
  "won",
  "lost",
  "cancelled",
] as const;

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
      className={`rounded-2xl border px-4 py-3 text-sm leading-6 ${messageClass}`}
    >
      {state.message}
    </div>
  );
}

function getOfferStatusTargets(
  status: DealOfferStatus,
): DealOfferStatus[] {
  switch (status) {
    case "draft":
      return [
        "proposed",
        "withdrawn",
      ];

    case "proposed":
      return [
        "countered",
        "accepted",
        "rejected",
        "withdrawn",
        "expired",
      ];

    case "countered":
    case "accepted":
    case "rejected":
    case "withdrawn":
    case "expired":
      return [];

    default:
      return [];
  }
}

function OfferStatusActionForm({
  dealId,
  offer,
}: {
  dealId: string;
  offer: DealOfferSummary;
}) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    updateDealOfferStatusAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const targets =
    getOfferStatusTargets(
      offer.status,
    );

  if (
    targets.length === 0
  ) {
    return null;
  }

  return (
    <form
      action={formAction}
      noValidate
      className="mt-4 space-y-4 rounded-xl border border-slate-800 bg-slate-950/60 p-4"
    >
      <input
        type="hidden"
        name="dealId"
        value={dealId}
      />

      <input
        type="hidden"
        name="offerId"
        value={offer.id}
      />

      <input
        type="hidden"
        name="expectedUpdatedAt"
        value={offer.updatedAt}
      />

      <ActionMessage
        state={state}
      />

      <div>
        <label
          htmlFor={`offer-status-${offer.id}`}
          className="mb-2 block text-sm font-medium text-slate-300"
        >
          Offer status action
        </label>

        <select
          id={`offer-status-${offer.id}`}
          name="status"
          defaultValue=""
          required
          aria-invalid={Boolean(
            state.fieldErrors.status,
          )}
          aria-describedby={
            state.fieldErrors.status
              ? `offer-status-${offer.id}-error`
              : undefined
          }
          className={getInputClass(
            Boolean(
              state.fieldErrors.status,
            ),
          )}
        >
          <option
            value=""
            disabled
          >
            Select action
          </option>

          {targets.map(
            (target) => (
              <option
                key={target}
                value={target}
              >
                {formatLabel(
                  target,
                )}
              </option>
            ),
          )}
        </select>

        {state.fieldErrors.status ? (
          <div
            id={`offer-status-${offer.id}-error`}
            className="mt-2 space-y-1"
          >
            {state.fieldErrors.status.map(
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
        ) : null}
      </div>

      <FieldError
        fieldName="expectedUpdatedAt"
        errors={state.fieldErrors}
      />

      <button
        type="submit"
        disabled={isPending}
        className="inline-flex w-full items-center justify-center rounded-xl border border-cyan-500/40 bg-cyan-500/10 px-4 py-3 text-sm font-semibold text-cyan-200 transition hover:bg-cyan-500/20 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Updating offer..."
          : "Apply offer action"}
      </button>
    </form>
  );
}

function ApprovalActionPanel({
  dealId,
  approval,
  access,
  currentUserId,
}: {
  dealId: string;
  approval: DealCommercialApprovalSummary;
  access: DealOSDataAccess;
  currentUserId: string;
}) {
  const [
    decisionState,
    decisionAction,
    isDecisionPending,
  ] = useActionState(
    decideCommercialApprovalAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const [
    cancelState,
    cancelAction,
    isCancelPending,
  ] = useActionState(
    cancelCommercialApprovalAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  if (
    approval.status !== "pending"
  ) {
    return null;
  }

  const canDecide =
    access.canApproveCommercials;

  const canCancel =
    access.canApproveCommercials ||
    approval.requestedBy ===
      currentUserId;

  if (
    !canDecide &&
    !canCancel
  ) {
    return null;
  }

  return (
    <div className="mt-4 grid gap-4 lg:grid-cols-2">
      {canDecide ? (
        <form
          action={decisionAction}
          noValidate
          className="space-y-4 rounded-xl border border-emerald-500/20 bg-emerald-500/5 p-4"
        >
          <input
            type="hidden"
            name="dealId"
            value={dealId}
          />

          <input
            type="hidden"
            name="approvalId"
            value={approval.id}
          />

          <input
            type="hidden"
            name="expectedUpdatedAt"
            value={approval.updatedAt}
          />

          <ActionMessage
            state={decisionState}
          />

          <div>
            <label
              htmlFor={`approval-decision-${approval.id}`}
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Decision
            </label>

            <select
              id={`approval-decision-${approval.id}`}
              name="decision"
              defaultValue=""
              required
              aria-invalid={Boolean(
                decisionState
                  .fieldErrors
                  .decision,
              )}
              className={getInputClass(
                Boolean(
                  decisionState
                    .fieldErrors
                    .decision,
                ),
              )}
            >
              <option
                value=""
                disabled
              >
                Select decision
              </option>

              <option value="approved">
                Approve
              </option>

              <option value="rejected">
                Reject
              </option>
            </select>

            <FieldError
              fieldName="decision"
              errors={
                decisionState.fieldErrors
              }
            />
          </div>

          <div>
            <label
              htmlFor={`decision-notes-${approval.id}`}
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Decision notes
            </label>

            <textarea
              id={`decision-notes-${approval.id}`}
              name="decisionNotes"
              rows={3}
              className={INPUT_CLASS}
            />
          </div>

          <FieldError
            fieldName="expectedUpdatedAt"
            errors={
              decisionState.fieldErrors
            }
          />

          <button
            type="submit"
            disabled={
              isDecisionPending
            }
            className="inline-flex w-full items-center justify-center rounded-xl bg-emerald-400 px-4 py-3 text-sm font-semibold text-slate-950 transition hover:bg-emerald-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isDecisionPending
              ? "Saving decision..."
              : "Save decision"}
          </button>
        </form>
      ) : null}

      {canCancel ? (
        <form
          action={cancelAction}
          noValidate
          className="space-y-4 rounded-xl border border-amber-500/20 bg-amber-500/5 p-4"
        >
          <input
            type="hidden"
            name="dealId"
            value={dealId}
          />

          <input
            type="hidden"
            name="approvalId"
            value={approval.id}
          />

          <input
            type="hidden"
            name="expectedUpdatedAt"
            value={approval.updatedAt}
          />

          <ActionMessage
            state={cancelState}
          />

          <div>
            <p className="text-sm font-semibold text-amber-200">
              Cancel request
            </p>

            <p className="mt-2 text-xs leading-5 text-slate-400">
              Pending commercial approval ko
              cancel karein. Request history
              audit ledger me retained rahegi.
            </p>
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
            className="inline-flex w-full items-center justify-center rounded-xl border border-amber-400/40 bg-amber-400/10 px-4 py-3 text-sm font-semibold text-amber-200 transition hover:bg-amber-400/20 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isCancelPending
              ? "Cancelling request..."
              : "Cancel approval request"}
          </button>
        </form>
      ) : null}
    </div>
  );
}

export default function DealCommercialActions({
  deal,
  offers,
  approvals,
  access,
  currentUserId,
}: DealCommercialActionsProps) {
  const [
    offerState,
    offerAction,
    isOfferPending,
  ] = useActionState(
    createDealOfferAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const [
    approvalState,
    approvalAction,
    isApprovalPending,
  ] = useActionState(
    requestCommercialApprovalAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const isTerminalDeal =
    TERMINAL_DEAL_STATUSES.includes(
      deal.status as
        (typeof TERMINAL_DEAL_STATUSES)[number],
    );

  const canManageOffers =
    access.canManageOffers &&
    !isTerminalDeal;

  const canRequestApproval =
    (
      access.canManageOffers ||
      access.canApproveCommercials
    ) &&
    !isTerminalDeal;

  const hasOfferActions =
    canManageOffers &&
    offers.some(
      (offer) =>
        getOfferStatusTargets(
          offer.status,
        ).length > 0,
    );

  const hasApprovalActions =
    approvals.some(
      (approval) =>
        approval.status ===
          "pending" &&
        (
          access.canApproveCommercials ||
          approval.requestedBy ===
            currentUserId
        ),
    );

  if (
    !canManageOffers &&
    !canRequestApproval &&
    !hasApprovalActions
  ) {
    return null;
  }

  return (
    <section className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 sm:p-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
          Commercial operations
        </p>

        <h3 className="mt-3 text-xl font-semibold text-white">
          Offers and approvals
        </h3>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Commercial proposal lifecycle,
          approval requests aur approval
          decisions ko DealOS permissions ke
          according manage karein.
        </p>
      </header>

      {canManageOffers ? (
        <form
          action={offerAction}
          noValidate
          className="mt-6 space-y-5 rounded-2xl border border-cyan-500/20 bg-cyan-500/5 p-5"
        >
          <input
            type="hidden"
            name="dealId"
            value={deal.id}
          />

          <div>
            <p className="text-sm font-semibold text-cyan-200">
              Create commercial offer
            </p>

            <p className="mt-1 text-xs leading-5 text-slate-400">
              New offer directly proposed
              status me create hoga.
            </p>
          </div>

          <ActionMessage
            state={offerState}
          />

          <div className="grid gap-4 md:grid-cols-2">
            <div>
              <label
                htmlFor="offeredByParty"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Offered by
              </label>

              <select
                id="offeredByParty"
                name="offeredByParty"
                defaultValue=""
                required
                className={getInputClass(
                  Boolean(
                    offerState
                      .fieldErrors
                      .offeredByParty,
                  ),
                )}
              >
                <option
                  value=""
                  disabled
                >
                  Select party
                </option>

                <option value="customer">
                  Customer
                </option>

                <option value="organization">
                  Organization
                </option>
              </select>

              <FieldError
                fieldName="offeredByParty"
                errors={
                  offerState.fieldErrors
                }
              />
            </div>

            <div>
              <label
                htmlFor="offerAmount"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Offer amount
              </label>

              <input
                id="offerAmount"
                name="offerAmount"
                type="number"
                min="0.01"
                step="0.01"
                required
                className={getInputClass(
                  Boolean(
                    offerState
                      .fieldErrors
                      .offerAmount,
                  ),
                )}
              />

              <FieldError
                fieldName="offerAmount"
                errors={
                  offerState.fieldErrors
                }
              />
            </div>

            <div>
              <label
                htmlFor="currencyCode"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Currency
              </label>

              <input
                id="currencyCode"
                name="currencyCode"
                type="text"
                maxLength={3}
                defaultValue={
                  deal.currencyCode
                }
                required
                className={getInputClass(
                  Boolean(
                    offerState
                      .fieldErrors
                      .currencyCode,
                  ),
                )}
              />

              <FieldError
                fieldName="currencyCode"
                errors={
                  offerState.fieldErrors
                }
              />
            </div>

            <div>
              <label
                htmlFor="validUntil"
                className="mb-2 block text-sm font-medium text-slate-300"
              >
                Valid until
              </label>

              <input
                id="validUntil"
                name="validUntil"
                type="datetime-local"
                className={getInputClass(
                  Boolean(
                    offerState
                      .fieldErrors
                      .validUntil,
                  ),
                )}
              />

              <FieldError
                fieldName="validUntil"
                errors={
                  offerState.fieldErrors
                }
              />
            </div>
          </div>

          <div>
            <label
              htmlFor="offerTerms"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Offer terms JSON
            </label>

            <textarea
              id="offerTerms"
              name="offerTerms"
              rows={4}
              defaultValue="{}"
              className={getInputClass(
                Boolean(
                  offerState
                    .fieldErrors
                    .offerTerms,
                ),
              )}
            />

            <p className="mt-2 text-xs text-slate-500">
              Valid JSON object use karein,
              for example:{" "}
              {'{"paymentPlan":"CLP"}'}
            </p>

            <FieldError
              fieldName="offerTerms"
              errors={
                offerState.fieldErrors
              }
            />
          </div>

          <div>
            <label
              htmlFor="offerNotes"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Notes
            </label>

            <textarea
              id="offerNotes"
              name="notes"
              rows={3}
              className={INPUT_CLASS}
            />
          </div>

          <button
            type="submit"
            disabled={isOfferPending}
            className="inline-flex w-full items-center justify-center rounded-xl bg-cyan-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {isOfferPending
              ? "Creating offer..."
              : "Create offer"}
          </button>
        </form>
      ) : null}

      {hasOfferActions ? (
        <div className="mt-6 space-y-4">
          <h4 className="text-sm font-semibold text-white">
            Offer lifecycle actions
          </h4>

          {offers.map(
            (offer) => (
              <OfferStatusActionForm
                key={offer.id}
                dealId={deal.id}
                offer={offer}
              />
            ),
          )}
        </div>
      ) : null}

      {canRequestApproval ? (
        <form
          action={approvalAction}
          noValidate
          className="mt-6 space-y-5 rounded-2xl border border-violet-500/20 bg-violet-500/5 p-5"
        >
          <input
            type="hidden"
            name="dealId"
            value={deal.id}
          />

          <div>
            <p className="text-sm font-semibold text-violet-200">
              Request commercial approval
            </p>

            <p className="mt-1 text-xs leading-5 text-slate-400">
              Pricing exception ya commercial
              deviation ke liye approval
              request create karein.
            </p>
          </div>

          <ActionMessage
            state={approvalState}
          />

          <div>
            <label
              htmlFor="approvalOfferId"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Linked offer
            </label>

            <select
              id="approvalOfferId"
              name="offerId"
              defaultValue=""
              className={getInputClass(
                Boolean(
                  approvalState
                    .fieldErrors
                    .offerId,
                ),
              )}
            >
              <option value="">
                No linked offer
              </option>

              {offers.map(
                (offer) => (
                  <option
                    key={offer.id}
                    value={offer.id}
                  >
                    {formatLabel(
                      offer.offeredByParty,
                    )}{" "}
                    — {offer.offerAmount}{" "}
                    {offer.currencyCode}
                  </option>
                ),
              )}
            </select>

            <FieldError
              fieldName="offerId"
              errors={
                approvalState.fieldErrors
              }
            />
          </div>

          <div>
            <label
              htmlFor="requestedAmount"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Requested amount
            </label>

            <input
              id="requestedAmount"
              name="requestedAmount"
              type="number"
              min="0.01"
              step="0.01"
              required
              className={getInputClass(
                Boolean(
                  approvalState
                    .fieldErrors
                    .requestedAmount,
                ),
              )}
            />

            <FieldError
              fieldName="requestedAmount"
              errors={
                approvalState.fieldErrors
              }
            />
          </div>

          <div>
            <label
              htmlFor="requestReason"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Approval reason
            </label>

            <textarea
              id="requestReason"
              name="requestReason"
              rows={4}
              required
              className={getInputClass(
                Boolean(
                  approvalState
                    .fieldErrors
                    .requestReason,
                ),
              )}
            />

            <FieldError
              fieldName="requestReason"
              errors={
                approvalState.fieldErrors
              }
            />
          </div>

          <button
            type="submit"
            disabled={
              isApprovalPending
            }
            className="inline-flex w-full items-center justify-center rounded-xl bg-violet-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-violet-300 disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {isApprovalPending
              ? "Requesting approval..."
              : "Request approval"}
          </button>
        </form>
      ) : null}

      {hasApprovalActions ? (
        <div className="mt-6 space-y-4">
          <h4 className="text-sm font-semibold text-white">
            Pending approval actions
          </h4>

          {approvals.map(
            (approval) => (
              <ApprovalActionPanel
                key={approval.id}
                dealId={deal.id}
                approval={approval}
                access={access}
                currentUserId={
                  currentUserId
                }
              />
            ),
          )}
        </div>
      ) : null}
    </section>
  );
}