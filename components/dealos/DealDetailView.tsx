import Link from "next/link";

import DealLifecycleActions from "@/components/dealos/DealLifecycleActions";

import DealUpdateForm from "@/components/dealos/DealUpdateForm";

import DealStatusTransitionForm from "@/components/dealos/DealStatusTransitionForm";

import type {
  DealCommercialApprovalSummary,
  DealNumeric,
  DealOfferSummary,
  DealOSDataAccess,
  DealStatusHistorySummary,
  DealSummary,
} from "@/types/dealos";

import type {
  OrganizationMemberOption,
} from "@/types/lead-operational-controls";

type DealDetailViewProps = {
  deal: DealSummary;

  assigneeOptions:
  OrganizationMemberOption[];

  offers: DealOfferSummary[];

  approvals:
    DealCommercialApprovalSummary[];

  statusHistory:
    DealStatusHistorySummary[];

  access: DealOSDataAccess;

  successMessage?:
    | string
    | null;
};

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

function shortId(
  value: string,
): string {
  return value.slice(0, 8);
}

function toNumber(
  value:
    | DealNumeric
    | null,
): number | null {
  if (
    value === null
  ) {
    return null;
  }

  const parsed =
    Number(value);

  return Number.isFinite(
    parsed,
  )
    ? parsed
    : null;
}

function formatCurrency(
  value:
    | DealNumeric
    | null,
  currencyCode: string,
): string {
  const amount =
    toNumber(value);

  if (
    amount === null
  ) {
    return "—";
  }

  try {
    return new Intl.NumberFormat(
      "en-IN",
      {
        style:
          "currency",
        currency:
          currencyCode,
        maximumFractionDigits: 0,
      },
    ).format(
      amount,
    );
  } catch {
    return `${currencyCode} ${amount.toLocaleString(
      "en-IN",
    )}`;
  }
}

function formatProbability(
  value:
    | DealNumeric
    | null,
): string {
  const probability =
    toNumber(value);

  return probability === null
    ? "—"
    : `${probability}%`;
}

function formatDateTime(
  value:
    | string
    | null,
): string {
  if (
    !value
  ) {
    return "—";
  }

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime(),
    )
  ) {
    return "—";
  }

  return new Intl.DateTimeFormat(
    "en-IN",
    {
      dateStyle:
        "medium",
      timeStyle:
        "short",
      timeZone:
        "Asia/Kolkata",
    },
  ).format(date);
}

function getStatusClasses(
  value: string,
): string {
  const normalized =
    value.toLowerCase();

  if (
    normalized.includes(
      "approved",
    ) ||
    normalized.includes(
      "accepted",
    ) ||
    normalized === "won" ||
    normalized ===
      "booking_ready"
  ) {
    return "border-emerald-500/40 bg-emerald-500/10 text-emerald-300";
  }

  if (
    normalized.includes(
      "negotiation",
    ) ||
    normalized.includes(
      "review",
    ) ||
    normalized.includes(
      "pending",
    ) ||
    normalized ===
      "on_hold"
  ) {
    return "border-amber-500/40 bg-amber-500/10 text-amber-300";
  }

  if (
    normalized.includes(
      "rejected",
    ) ||
    normalized.includes(
      "lost",
    ) ||
    normalized.includes(
      "cancelled",
    ) ||
    normalized.includes(
      "expired",
    ) ||
    normalized.includes(
      "withdrawn",
    )
  ) {
    return "border-red-500/40 bg-red-500/10 text-red-300";
  }

  return "border-slate-700 bg-slate-800 text-slate-300";
}

function StatusBadge({
  value,
}: {
  value: string;
}) {
  return (
    <span
      className={`inline-flex rounded-full border px-3 py-1 text-xs font-semibold ${getStatusClasses(
        value,
      )}`}
    >
      {formatLabel(
        value,
      )}
    </span>
  );
}

function DetailItem({
  label,
  children,
}: {
  label: string;
  children:
    React.ReactNode;
}) {
  return (
    <div className="rounded-2xl border border-slate-800 bg-slate-950/60 p-4">
      <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
        {label}
      </dt>

      <dd className="mt-2 break-words text-sm font-medium leading-6 text-slate-200">
        {children}
      </dd>
    </div>
  );
}

function DetailSection({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children:
    React.ReactNode;
}) {
  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <h2 className="text-xl font-semibold text-white">
        {title}
      </h2>

      {description ? (
        <p className="mt-2 text-sm leading-6 text-slate-400">
          {description}
        </p>
      ) : null}

      <div className="mt-7">
        {children}
      </div>
    </section>
  );
}

export default function DealDetailView({
  deal,
  offers,
  assigneeOptions,
  approvals,
  statusHistory,
  access,
  successMessage,
}: DealDetailViewProps) {
  return (
    <div className="space-y-8">
      {successMessage ? (
        <div className="rounded-2xl border border-emerald-500/40 bg-emerald-500/10 px-5 py-4 text-sm font-medium text-emerald-200">
          {successMessage}
        </div>
      ) : null}

      <header className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
        <Link
          href="/dashboard/deals"
          className="text-sm font-semibold text-cyan-400 transition hover:text-cyan-300"
        >
          ← Back to deals
        </Link>

        <div className="mt-5 flex flex-col justify-between gap-6 xl:flex-row xl:items-start">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-cyan-400">
              DealOS
            </p>

            <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
              Deal{" "}
              {shortId(
                deal.id,
              )}
            </h1>

            <div className="mt-5 flex flex-wrap gap-2">
              <StatusBadge
                value={
                  deal.status
                }
              />
            </div>
          </div>

          <div className="rounded-2xl border border-slate-800 bg-slate-950/60 px-5 py-4">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              Deal ID
            </p>

            <p className="mt-2 max-w-72 break-all font-mono text-xs text-slate-300">
              {deal.id}
            </p>
          </div>
        </div>
      </header>

      <DetailSection
        title="Commercial snapshot"
        description="Current commercial position and booking probability."
      >
        <dl className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
          <DetailItem label="Listed price">
            {formatCurrency(
              deal.listedPriceSnapshot,
              deal.currencyCode,
            )}
          </DetailItem>

          <DetailItem label="Quoted price">
            {formatCurrency(
              deal.quotedPriceSnapshot,
              deal.currencyCode,
            )}
          </DetailItem>

          <DetailItem label="Minimum negotiable">
            {formatCurrency(
              deal.minimumNegotiablePriceSnapshot,
              deal.currencyCode,
            )}
          </DetailItem>

          <DetailItem label="Agreed price">
            {formatCurrency(
              deal.agreedPrice,
              deal.currencyCode,
            )}
          </DetailItem>

          <DetailItem label="Booking probability">
            {formatProbability(
              deal.bookingProbability,
            )}
          </DetailItem>

          <DetailItem label="Next action">
            {formatDateTime(
              deal.nextActionAt,
            )}
          </DetailItem>
        </dl>
      </DetailSection>

      <DetailSection
        title="Deal relationships"
        description="Lead, inventory, site visit, assignment and booking linkage."
      >
        <dl className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
          <DetailItem label="Lead">
            <Link
              href={`/dashboard/leads/${deal.leadId}`}
              className="font-mono text-cyan-300 transition hover:text-cyan-200"
            >
              {deal.leadId}
            </Link>
          </DetailItem>

          <DetailItem label="Assigned user">
            {deal.assignedTo ??
              "—"}
          </DetailItem>

          <DetailItem label="Site visit">
            {deal.siteVisitId ??
              "—"}
          </DetailItem>

          <DetailItem label="Inventory unit">
            {deal.inventoryUnitId ??
              "—"}
          </DetailItem>

          <DetailItem label="Booking">
            {deal.bookingId ??
              "—"}
          </DetailItem>

          <DetailItem label="Currency">
            {deal.currencyCode}
          </DetailItem>
        </dl>
      </DetailSection>

      {access.canUpdateDeal ? (
  <DealUpdateForm
    deal={deal}
    assigneeOptions={
      assigneeOptions
    }
    canAssignDeal={
      access.canAssignDeal
    }
  />
) : null}

      {access.canUpdateDeal ? (
        <DealStatusTransitionForm
          dealId={deal.id}
          currentStatus={
            deal.status
          }
          updatedAt={
            deal.updatedAt
          }
        />
      ) : null}

      <DealLifecycleActions
  deal={deal}
  access={access}
/>

      <DetailSection
        title="Offers"
        description="Commercial proposals recorded against this deal."
      >
        {offers.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-950/40 px-5 py-8 text-center text-sm text-slate-500">
            No offers have been recorded.
          </div>
        ) : (
          <div className="space-y-4">
            {offers.map(
              (offer) => (
                <article
                  key={
                    offer.id
                  }
                  className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5"
                >
                  <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
                    <div>
                      <div className="flex flex-wrap items-center gap-3">
                        <StatusBadge
                          value={
                            offer.status
                          }
                        />

                        <span className="text-xs text-slate-500">
                          {formatLabel(
                            offer.offeredByParty,
                          )}
                        </span>
                      </div>

                      <p className="mt-4 text-2xl font-bold text-white">
                        {formatCurrency(
                          offer.offerAmount,
                          offer.currencyCode,
                        )}
                      </p>

                      {offer.notes ? (
                        <p className="mt-3 whitespace-pre-wrap text-sm leading-6 text-slate-400">
                          {
                            offer.notes
                          }
                        </p>
                      ) : null}
                    </div>

                    <div className="text-xs leading-5 text-slate-500">
                      <p>
                        Created:{" "}
                        {formatDateTime(
                          offer.createdAt,
                        )}
                      </p>

                      <p>
                        Valid until:{" "}
                        {formatDateTime(
                          offer.validUntil,
                        )}
                      </p>
                    </div>
                  </div>
                </article>
              ),
            )}
          </div>
        )}
      </DetailSection>

      <DetailSection
        title="Commercial approvals"
        description="Commercial exception requests and approval decisions."
      >
        {approvals.length ===
        0 ? (
          <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-950/40 px-5 py-8 text-center text-sm text-slate-500">
            No commercial approval request is recorded.
          </div>
        ) : (
          <div className="space-y-4">
            {approvals.map(
              (approval) => (
                <article
                  key={
                    approval.id
                  }
                  className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5"
                >
                  <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
                    <div>
                      <StatusBadge
                        value={
                          approval.status
                        }
                      />

                      <p className="mt-4 text-2xl font-bold text-white">
                        {formatCurrency(
                          approval.requestedAmount,
                          deal.currencyCode,
                        )}
                      </p>

                      <p className="mt-3 text-sm leading-6 text-slate-400">
                        {
                          approval.requestReason
                        }
                      </p>

                      {approval.decisionNotes ? (
                        <p className="mt-3 text-sm leading-6 text-slate-300">
                          Decision:{" "}
                          {
                            approval.decisionNotes
                          }
                        </p>
                      ) : null}
                    </div>

                    <div className="text-xs leading-5 text-slate-500">
                      <p>
                        Requested:{" "}
                        {formatDateTime(
                          approval.requestedAt,
                        )}
                      </p>

                      <p>
                        Decided:{" "}
                        {formatDateTime(
                          approval.decidedAt,
                        )}
                      </p>
                    </div>
                  </div>
                </article>
              ),
            )}
          </div>
        )}
      </DetailSection>

      <DetailSection
        title="Status history"
        description="Deal lifecycle transitions recorded by DealOS."
      >
        {statusHistory.length ===
        0 ? (
          <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-950/40 px-5 py-8 text-center text-sm text-slate-500">
            No deal status history is available.
          </div>
        ) : (
          <div className="space-y-4">
            {statusHistory.map(
              (entry) => (
                <article
                  key={
                    entry.id
                  }
                  className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5"
                >
                  <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        {entry.previousStatus ? (
                          <>
                            <StatusBadge
                              value={
                                entry.previousStatus
                              }
                            />

                            <span className="text-slate-500">
                              →
                            </span>
                          </>
                        ) : null}

                        <StatusBadge
                          value={
                            entry.newStatus
                          }
                        />
                      </div>

                      {entry.changeReason ? (
                        <p className="mt-3 text-sm leading-6 text-slate-400">
                          {
                            entry.changeReason
                          }
                        </p>
                      ) : null}
                    </div>

                    <time className="text-xs text-slate-500">
                      {formatDateTime(
                        entry.changedAt,
                      )}
                    </time>
                  </div>
                </article>
              ),
            )}
          </div>
        )}
      </DetailSection>

      <DetailSection
        title="Notes and close state"
      >
        <dl className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
          <DetailItem label="Hold reason">
            {deal.holdReason ??
              "—"}
          </DetailItem>

          <DetailItem label="Loss reason">
            {deal.lossReason ??
              "—"}
          </DetailItem>

          <DetailItem label="Cancellation reason">
            {deal.cancellationReason ??
              "—"}
          </DetailItem>

          <DetailItem label="Won at">
            {formatDateTime(
              deal.wonAt,
            )}
          </DetailItem>

          <DetailItem label="Lost at">
            {formatDateTime(
              deal.lostAt,
            )}
          </DetailItem>

          <DetailItem label="Closed at">
            {formatDateTime(
              deal.closedAt,
            )}
          </DetailItem>
        </dl>

        <div className="mt-5 rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            Notes
          </p>

          <p className="mt-3 whitespace-pre-wrap text-sm leading-7 text-slate-300">
            {deal.notes ??
              "No notes recorded."}
          </p>
        </div>
      </DetailSection>

      <DetailSection title="System information">
        <dl className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
          <DetailItem label="Created at">
            {formatDateTime(
              deal.createdAt,
            )}
          </DetailItem>

          <DetailItem label="Last updated">
            {formatDateTime(
              deal.updatedAt,
            )}
          </DetailItem>

          <DetailItem label="Organization">
            {deal.organizationId}
          </DetailItem>
        </dl>
      </DetailSection>
    </div>
  );
}