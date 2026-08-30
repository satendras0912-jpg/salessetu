import Link from "next/link";

import type {
  DealNumeric,
  DealSummary,
} from "@/types/dealos";

type DealTableProps = {
  deals: DealSummary[];
};

function normalizeLabel(
  value: string | null,
): string {
  if (!value) {
    return "Not available";
  }

  return value
    .replaceAll("_", " ")
    .replace(
      /\b\w/g,
      (character) =>
        character.toUpperCase(),
    );
}

function statusClass(
  value: string,
): string {
  switch (
    value.toLowerCase()
  ) {
    case "won":
    case "approved":
    case "booking_ready":
      return "border-emerald-500/30 bg-emerald-500/10 text-emerald-300";

    case "negotiation":
    case "commercial_review":
    case "on_hold":
      return "border-amber-500/30 bg-amber-500/10 text-amber-300";

    case "lost":
    case "cancelled":
      return "border-red-500/30 bg-red-500/10 text-red-300";

    case "open":
      return "border-cyan-500/30 bg-cyan-500/10 text-cyan-300";

    default:
      return "border-slate-700 bg-slate-800 text-slate-300";
  }
}

function StatusBadge({
  value,
}: {
  value: string;
}) {
  return (
    <span
      className={[
        "inline-flex rounded-full border px-2.5 py-1 text-xs font-medium",
        statusClass(value),
      ].join(" ")}
    >
      {normalizeLabel(value)}
    </span>
  );
}

function formatDate(
  value: string | null,
): string {
  if (!value) {
    return "Not scheduled";
  }

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime(),
    )
  ) {
    return "Invalid date";
  }

  return new Intl.DateTimeFormat(
    "en-IN",
    {
      dateStyle: "medium",
      timeStyle: "short",
      timeZone: "Asia/Kolkata",
    },
  ).format(date);
}

function toFiniteNumber(
  value: DealNumeric | null,
): number | null {
  if (value === null) {
    return null;
  }

  const parsedValue =
    typeof value === "number"
      ? value
      : Number(value);

  return Number.isFinite(
    parsedValue,
  )
    ? parsedValue
    : null;
}

function formatMoney(
  value: DealNumeric | null,
  currencyCode: string,
): string {
  const amount =
    toFiniteNumber(value);

  if (amount === null) {
    return "Not available";
  }

  try {
    return new Intl.NumberFormat(
      "en-IN",
      {
        style: "currency",
        currency:
          currencyCode,
        maximumFractionDigits: 0,
      },
    ).format(amount);
  } catch {
    return `${currencyCode} ${amount.toLocaleString(
      "en-IN",
    )}`;
  }
}

function formatProbability(
  value: DealNumeric | null,
): string {
  const probability =
    toFiniteNumber(value);

  if (probability === null) {
    return "Not set";
  }

  return `${probability}%`;
}

function shortId(
  value: string,
): string {
  return value.slice(
    0,
    8,
  );
}

export default function DealTable({
  deals,
}: DealTableProps) {
  if (deals.length === 0) {
    return (
      <section className="rounded-3xl border border-dashed border-slate-700 bg-slate-900/40 px-6 py-20 text-center">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-slate-800 text-2xl">
          D
        </div>

        <h2 className="mt-5 text-xl font-semibold text-white">
          No deals found
        </h2>

        <p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-slate-400">
          No DealOS records match the current filters.
          Clear the filters or create a deal from an eligible lead.
        </p>
      </section>
    );
  }

  return (
    <section className="overflow-hidden rounded-3xl border border-slate-800 bg-slate-900/70">
      <div className="overflow-x-auto">
        <table className="min-w-[1280px] w-full border-collapse text-left">
          <thead className="border-b border-slate-800 bg-slate-950/70">
            <tr className="text-xs uppercase tracking-wider text-slate-500">
              <th className="px-5 py-4 font-medium">
                Deal
              </th>

              <th className="px-5 py-4 font-medium">
                Status
              </th>

              <th className="px-5 py-4 font-medium">
                Commercial
              </th>

              <th className="px-5 py-4 font-medium">
                Probability
              </th>

              <th className="px-5 py-4 font-medium">
                Assignment
              </th>

              <th className="px-5 py-4 font-medium">
                Next action
              </th>

              <th className="px-5 py-4 font-medium">
                Booking
              </th>

              <th className="px-5 py-4 font-medium">
                Created
              </th>
            </tr>
          </thead>

          <tbody className="divide-y divide-slate-800">
            {deals.map(
              (deal) => (
                <tr
                  key={deal.id}
                  className="align-top transition hover:bg-slate-800/40"
                >
                  <td className="px-5 py-5">
                    <Link
                      href={`/dashboard/deals/${deal.id}`}
                      className="font-semibold text-white transition hover:text-cyan-300"
                    >
                      Deal{" "}
                      {shortId(
                        deal.id,
                      )}
                    </Link>

                    <p className="mt-2 text-xs text-slate-500">
                      Lead
                    </p>

                    <Link
                      href={`/dashboard/leads/${deal.leadId}`}
                      className="font-mono text-xs text-cyan-300 transition hover:text-cyan-200"
                    >
                      {shortId(
                        deal.leadId,
                      )}
                    </Link>
                  </td>

                  <td className="px-5 py-5">
                    <StatusBadge
                      value={
                        deal.status
                      }
                    />
                  </td>

                  <td className="px-5 py-5">
                    <div className="min-w-48 space-y-1 text-sm">
                      <p className="font-medium text-slate-200">
                        Agreed:{" "}
                        {formatMoney(
                          deal.agreedPrice,
                          deal.currencyCode,
                        )}
                      </p>

                      <p className="text-xs text-slate-500">
                        Quoted:{" "}
                        {formatMoney(
                          deal.quotedPriceSnapshot,
                          deal.currencyCode,
                        )}
                      </p>

                      <p className="text-xs text-slate-600">
                        Listed:{" "}
                        {formatMoney(
                          deal.listedPriceSnapshot,
                          deal.currencyCode,
                        )}
                      </p>
                    </div>
                  </td>

                  <td className="px-5 py-5">
                    <p className="text-sm font-semibold text-slate-200">
                      {formatProbability(
                        deal.bookingProbability,
                      )}
                    </p>
                  </td>

                  <td className="px-5 py-5">
                    {deal.assignedTo ? (
                      <div>
                        <p className="text-sm text-slate-300">
                          Assigned
                        </p>

                        <p className="mt-1 font-mono text-xs text-slate-500">
                          {shortId(
                            deal.assignedTo,
                          )}
                        </p>
                      </div>
                    ) : (
                      <span className="text-sm text-slate-500">
                        Unassigned
                      </span>
                    )}
                  </td>

                  <td className="px-5 py-5">
                    <p className="min-w-40 text-sm text-slate-300">
                      {formatDate(
                        deal.nextActionAt,
                      )}
                    </p>
                  </td>

                  <td className="px-5 py-5">
                    {deal.bookingId ? (
                      <div>
                        <p className="text-sm font-medium text-emerald-300">
                          Linked
                        </p>

                        <p className="mt-1 font-mono text-xs text-slate-500">
                          {shortId(
                            deal.bookingId,
                          )}
                        </p>
                      </div>
                    ) : (
                      <span className="text-sm text-slate-500">
                        Not linked
                      </span>
                    )}
                  </td>

                  <td className="px-5 py-5">
                    <p className="min-w-40 text-sm text-slate-300">
                      {formatDate(
                        deal.createdAt,
                      )}
                    </p>

                    <p className="mt-2 text-xs text-slate-600">
                      Updated{" "}
                      {formatDate(
                        deal.updatedAt,
                      )}
                    </p>
                  </td>
                </tr>
              ),
            )}
          </tbody>
        </table>
      </div>
    </section>
  );
}