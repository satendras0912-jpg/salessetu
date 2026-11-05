import type { LeadInventoryMatchSuggestion } from "@/lib/inventory/lead-inventory-match-service";

type LeadInventoryMatchSuggestionsProps = {
  suggestions: LeadInventoryMatchSuggestion[];
  hasRequirements: boolean;
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

export default function LeadInventoryMatchSuggestions({
  suggestions,
  hasRequirements,
}: LeadInventoryMatchSuggestionsProps) {
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
          {suggestions.map((suggestion) => (
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
            </article>
          ))}
        </div>
      ) : null}
    </section>
  );
}
