import type { LeadInventoryMatchSuggestion } from "@/lib/inventory/lead-inventory-match-service";
import type { LeadInventoryMatchReview } from "@/lib/inventory/lead-inventory-match-review-service";
import { decideLeadInventoryMatchAction } from "@/app/dashboard/leads/[leadId]/inventory-match-actions";

type LeadInventoryMatchSuggestionsProps = {
  leadId: string;
  suggestions: LeadInventoryMatchSuggestion[];
  hasRequirements: boolean;
  reviews: LeadInventoryMatchReview[];
  canReview: boolean;
};

function formatLabel(value: string): string {
  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function formatCurrency(
  amount: number | null,
  currency: string,
): string {
  if (amount === null) {
    return "Price not set";
  }

  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency,
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return `${currency} ${amount.toLocaleString("en-IN")}`;
  }
}

function formatVerificationDate(value: string): string {
  const date = new Date(`${value}T00:00:00.000Z`);

  return Number.isNaN(date.getTime())
    ? value
    : new Intl.DateTimeFormat("en-IN", {
      dateStyle: "medium",
      timeZone: "Asia/Kolkata",
    }).format(date);
}

function formatReviewDate(value: string): string {
  const date = new Date(value);

  return Number.isNaN(date.getTime())
    ? "Recorded"
    : new Intl.DateTimeFormat("en-IN", {
      dateStyle: "medium",
      timeStyle: "short",
      timeZone: "Asia/Kolkata",
    }).format(date);
}

export default function LeadInventoryMatchSuggestions({
  leadId,
  suggestions,
  hasRequirements,
  reviews,
  canReview,
}: LeadInventoryMatchSuggestionsProps) {
  const reviewsByInventoryUnitId = new Map(
    reviews.map((review) => [review.inventoryUnitId, review]),
  );

  return (
    <section className="rounded-3xl border border-cyan-500/25 bg-slate-900/70 p-6 sm:p-8">
      <header className="flex flex-col justify-between gap-4 md:flex-row md:items-start">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            Inventory suggestions
          </p>
          <h2 className="mt-3 text-2xl font-bold text-white">
            Verified availability matched to this lead
          </h2>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
            Ranking is based on the lead&apos;s recorded project, location,
            property type, bedroom and budget requirements. This is read-only:
            it does not assign, reserve, route, notify or contact anyone.
          </p>
        </div>

        <span className="inline-flex w-fit rounded-full border border-cyan-500/40 bg-cyan-500/10 px-3 py-1 text-xs font-semibold text-cyan-200">
          Manual review required
        </span>
      </header>

      {!hasRequirements ? (
        <p className="mt-6 rounded-2xl border border-amber-500/30 bg-amber-500/5 px-5 py-4 text-sm leading-6 text-amber-100">
          Add the lead&apos;s project, location, property type, bedroom or budget
          requirement to generate relevant suggestions.
        </p>
      ) : null}

      {hasRequirements && suggestions.length === 0 ? (
        <p className="mt-6 rounded-2xl border border-slate-800 bg-slate-950/50 px-5 py-4 text-sm leading-6 text-slate-400">
          No verified available units match the currently recorded requirements.
          Inventory is never inferred or created by this view.
        </p>
      ) : null}

      {suggestions.length > 0 ? (
        <div className="mt-6 grid gap-4 xl:grid-cols-2">
          {suggestions.map((suggestion) => {
            const review = reviewsByInventoryUnitId.get(
              suggestion.inventoryUnitId,
            );

            return (
              <article
                key={suggestion.inventoryUnitId}
                className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5"
              >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="font-semibold text-white">
                    {suggestion.projectName ?? suggestion.projectCode ?? "Project"}
                  </p>
                  <p className="mt-1 text-sm text-slate-400">
                    Unit {suggestion.unitNumber} · {suggestion.inventoryCode}
                  </p>
                </div>
                <span className="rounded-full border border-cyan-500/40 bg-cyan-500/10 px-3 py-1 text-sm font-bold text-cyan-200">
                  {suggestion.score}% match
                </span>
              </div>

              <dl className="mt-5 grid grid-cols-2 gap-x-4 gap-y-4 text-sm">
                <div>
                  <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                    Unit
                  </dt>
                  <dd className="mt-1 text-slate-200">
                    {formatLabel(suggestion.propertyType)}
                    {suggestion.bedrooms !== null
                      ? ` · ${suggestion.bedrooms} BHK`
                      : ""}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                    Price
                  </dt>
                  <dd className="mt-1 text-slate-200">
                    {formatCurrency(suggestion.currentPrice, suggestion.currency)}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                    Location
                  </dt>
                  <dd className="mt-1 text-slate-200">
                    {[suggestion.locality, suggestion.city]
                      .filter(Boolean)
                      .join(", ") || "Not recorded"}
                  </dd>
                </div>
                <div>
                  <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                    Verified
                  </dt>
                  <dd className="mt-1 text-slate-200">
                    {formatVerificationDate(suggestion.verificationDate)}
                  </dd>
                </div>
              </dl>

                <div className="mt-5 border-t border-slate-800 pt-4">
                <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                  Why it matched
                </p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {suggestion.matchReasons.map((reason) => (
                    <span
                      key={reason}
                      className="rounded-full border border-slate-700 bg-slate-900 px-3 py-1 text-xs text-slate-300"
                    >
                      {reason}
                    </span>
                  ))}
                </div>
                <p className="mt-3 text-xs text-slate-500">
                  Source: {suggestion.source} · Manual follow-up only
                </p>
                </div>

                <div className="mt-5 border-t border-slate-800 pt-4">
                  <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                    Manual match review
                  </p>
                  <p className="mt-2 text-xs leading-5 text-slate-500">
                    Internal audit only. This does not assign a lead, reserve a
                    unit, route work, create an alert or contact a customer.
                  </p>

                  {review ? (
                    <div className="mt-3 rounded-xl border border-slate-700 bg-slate-900/70 p-3 text-sm">
                      <p className="font-semibold text-slate-100">
                        {review.decision === "suitable"
                          ? "Marked suitable"
                          : "Marked not suitable"}
                      </p>
                      <p className="mt-1 text-slate-300">{review.reason}</p>
                      {review.notes ? (
                        <p className="mt-1 text-slate-400">{review.notes}</p>
                      ) : null}
                      <p className="mt-2 text-xs text-slate-500">
                        Recorded {formatReviewDate(review.reviewedAt)}
                      </p>
                    </div>
                  ) : null}

                  {canReview ? (
                    <form
                      action={decideLeadInventoryMatchAction}
                      className="mt-4 space-y-3"
                    >
                      <input name="leadId" type="hidden" value={leadId} />
                      <input
                        name="inventoryUnitId"
                        type="hidden"
                        value={suggestion.inventoryUnitId}
                      />
                      <input
                        aria-label={`Review reason for ${suggestion.inventoryCode}`}
                        className="w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white outline-none placeholder:text-slate-600 focus:border-cyan-400"
                        defaultValue={review?.reason ?? ""}
                        maxLength={500}
                        minLength={3}
                        name="reason"
                        placeholder="Why is this unit suitable or not suitable?"
                        required
                      />
                      <textarea
                        aria-label={`Internal review note for ${suggestion.inventoryCode}`}
                        className="min-h-20 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white outline-none placeholder:text-slate-600 focus:border-cyan-400"
                        defaultValue={review?.notes ?? ""}
                        maxLength={2000}
                        name="notes"
                        placeholder="Internal note (optional)"
                      />
                      <div className="flex flex-wrap gap-3">
                        <button
                          className="rounded-xl bg-emerald-500 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-emerald-400"
                          name="decision"
                          type="submit"
                          value="suitable"
                        >
                          Suitable
                        </button>
                        <button
                          className="rounded-xl border border-amber-500/70 px-4 py-2 text-sm font-semibold text-amber-200 transition hover:bg-amber-500/10"
                          name="decision"
                          type="submit"
                          value="not_suitable"
                        >
                          Not suitable
                        </button>
                      </div>
                    </form>
                  ) : (
                    <p className="mt-3 text-sm text-slate-500">
                      You have view access, but not permission to record a
                      manual match review.
                    </p>
                  )}
                </div>
              </article>
            );
          })}
        </div>
      ) : null}
    </section>
  );
}
