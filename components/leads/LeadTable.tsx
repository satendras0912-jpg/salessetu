import type { LeadListItem } from "@/types/leads";

import Link from "next/link";

type LeadTableProps = {
  leads: LeadListItem[];
};

function normaliseLabel(value: string | null): string {
  if (!value) {
    return "Not available";
  }

  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function statusClass(value: string | null): string {
  switch (value?.toLowerCase()) {
    case "approved":
    case "qualified":
    case "converted":
    case "accepted":
    case "active":
      return "border-emerald-500/30 bg-emerald-500/10 text-emerald-300";

    case "manual_review":
    case "pending":
    case "new":
    case "contacted":
    case "warm":
      return "border-amber-500/30 bg-amber-500/10 text-amber-300";

    case "rejected":
    case "lost":
    case "fake":
    case "blocked":
      return "border-red-500/30 bg-red-500/10 text-red-300";

    case "assigned":
    case "site_visit":
    case "hot":
      return "border-cyan-500/30 bg-cyan-500/10 text-cyan-300";

    default:
      return "border-slate-700 bg-slate-800 text-slate-300";
  }
}

function StatusBadge({
  value,
}: {
  value: string | null;
}) {
  return (
    <span
      className={[
        "inline-flex rounded-full border px-2.5 py-1 text-xs font-medium",
        statusClass(value),
      ].join(" ")}
    >
      {normaliseLabel(value)}
    </span>
  );
}

function formatDate(value: string | null): string {
  if (!value) {
    return "Not available";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Invalid date";
  }

  return new Intl.DateTimeFormat("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Kolkata",
  }).format(date);
}

function formatMoney(
  amount: number | null,
  currency: string,
): string | null {
  if (amount === null) {
    return null;
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

function formatBudget(lead: LeadListItem): string {
  const minimum = formatMoney(
    lead.budgetMin,
    lead.budgetCurrency,
  );

  const maximum = formatMoney(
    lead.budgetMax,
    lead.budgetCurrency,
  );

  if (minimum && maximum) {
    return `${minimum} – ${maximum}`;
  }

  return minimum ?? maximum ?? "Not specified";
}

function getSourceLabel(lead: LeadListItem): string {
  return (
    lead.source?.name ??
    lead.utmSource ??
    lead.campaignName ??
    "Unknown source"
  );
}

function getAgentLabel(lead: LeadListItem): string {
  return (
    lead.assignment?.agentName ??
    lead.assignment?.agentCode ??
    (lead.assignedTo ? "Assigned user" : "Not assigned")
  );
}

export default function LeadTable({
  leads,
}: LeadTableProps) {
  if (leads.length === 0) {
    return (
      <section className="rounded-3xl border border-dashed border-slate-700 bg-slate-900/40 px-6 py-20 text-center">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-slate-800 text-2xl">
          ⌕
        </div>

        <h2 className="mt-5 text-xl font-semibold text-white">
          No leads found
        </h2>

        <p className="mx-auto mt-2 max-w-lg text-sm leading-6 text-slate-400">
          Current filters के अनुसार कोई lead उपलब्ध नहीं है।
          Filters clear करें या lead capture होने के बाद दोबारा देखें।
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
              <th className="px-5 py-4 font-medium">Lead</th>
              <th className="px-5 py-4 font-medium">Contact</th>
              <th className="px-5 py-4 font-medium">Requirement</th>
              <th className="px-5 py-4 font-medium">Status</th>
              <th className="px-5 py-4 font-medium">Validation</th>
              <th className="px-5 py-4 font-medium">Assignment</th>
              <th className="px-5 py-4 font-medium">Source</th>
              <th className="px-5 py-4 font-medium">Created</th>
            </tr>
          </thead>

          <tbody className="divide-y divide-slate-800">
            {leads.map((lead) => {
              const validationDecision =
                lead.validation?.decision ?? "not_validated";

              const assignmentStatus =
                lead.assignment?.status ??
                lead.assignmentStatus;

              return (
                <tr
                  key={lead.id}
                  className="align-top transition hover:bg-slate-800/40"
                >
                  <td className="px-5 py-5">
                    <Link
  href={`/dashboard/leads/${lead.id}`}
  className="block max-w-56 truncate font-semibold text-white transition hover:text-cyan-300"
>
  {lead.fullName}
</Link>

                    <p className="mt-1 font-mono text-xs text-slate-600">
                      {lead.id.slice(0, 8)}
                    </p>

                    <div className="mt-3 flex flex-wrap gap-2">
                      {lead.leadTemperature ? (
                        <StatusBadge
                          value={lead.leadTemperature}
                        />
                      ) : null}

                      {lead.priority !== "normal" ? (
                        <StatusBadge value={lead.priority} />
                      ) : null}
                    </div>
                  </td>

                  <td className="px-5 py-5">
                    <div className="max-w-60 space-y-1 text-sm">
                      <p className="text-slate-200">
                        {lead.phone ?? "No phone"}
                      </p>

                      <p className="truncate text-slate-500">
                        {lead.email ?? "No email"}
                      </p>

                      {lead.whatsappNumber ? (
                        <p className="text-xs text-emerald-400">
                          WhatsApp: {lead.whatsappNumber}
                        </p>
                      ) : null}
                    </div>
                  </td>

                  <td className="px-5 py-5">
                    <div className="max-w-64 space-y-1 text-sm">
                      <p className="font-medium text-slate-200">
                        {lead.preferredProject ??
                          lead.propertyType ??
                          "Project not specified"}
                      </p>

                      <p className="text-slate-500">
                        {lead.preferredLocation ??
                          lead.preferredCity ??
                          "Location not specified"}
                      </p>

                      <p className="mt-2 text-xs font-medium text-cyan-300">
                        {formatBudget(lead)}
                      </p>
                    </div>
                  </td>

                  <td className="px-5 py-5">
                    <div className="space-y-2">
                      <StatusBadge value={lead.leadStatus} />

                      <p className="text-xs text-slate-500">
                        Qualification:{" "}
                        {normaliseLabel(
                          lead.qualificationStatus,
                        )}
                      </p>

                      {lead.qualificationScore !== null ? (
                        <p className="text-xs text-slate-500">
                          Score: {lead.qualificationScore}
                        </p>
                      ) : null}
                    </div>
                  </td>

                  <td className="px-5 py-5">
                    <div className="max-w-56 space-y-2">
                      <StatusBadge
                        value={validationDecision}
                      />

                      {lead.validation?.trustScore !== null &&
                      lead.validation?.trustScore !==
                        undefined ? (
                        <p className="text-xs text-slate-500">
                          Trust score:{" "}
                          {lead.validation.trustScore}
                        </p>
                      ) : null}

                      {lead.validation?.recommendedAction ? (
                        <p className="text-xs text-slate-400">
                          {normaliseLabel(
                            lead.validation.recommendedAction,
                          )}
                        </p>
                      ) : null}

                      {lead.fakeStatus !== "unchecked" ? (
                        <p className="text-xs text-red-300">
                          Fake status:{" "}
                          {normaliseLabel(lead.fakeStatus)}
                        </p>
                      ) : null}
                    </div>
                  </td>

                  <td className="px-5 py-5">
                    <div className="max-w-56 space-y-2">
                      <StatusBadge value={assignmentStatus} />

                      <p className="text-sm text-slate-300">
                        {getAgentLabel(lead)}
                      </p>

                      {lead.assignment?.assignedAt ??
                      lead.assignedAt ? (
                        <p className="text-xs text-slate-500">
                          {formatDate(
                            lead.assignment?.assignedAt ??
                              lead.assignedAt,
                          )}
                        </p>
                      ) : null}
                    </div>
                  </td>

                  <td className="px-5 py-5">
                    <div className="max-w-52 space-y-1">
                      <p className="font-medium text-slate-200">
                        {getSourceLabel(lead)}
                      </p>

                      {lead.campaignName ? (
                        <p className="truncate text-xs text-slate-500">
                          {lead.campaignName}
                        </p>
                      ) : null}

                      {lead.utmMedium ? (
                        <p className="text-xs text-slate-600">
                          {lead.utmMedium}
                        </p>
                      ) : null}
                    </div>
                  </td>

                  <td className="px-5 py-5">
                    <p className="min-w-36 text-sm text-slate-300">
                      {formatDate(lead.createdAt)}
                    </p>

                    {lead.nextFollowUpAt ? (
                      <p className="mt-2 text-xs text-amber-300">
                        Follow-up:{" "}
                        {formatDate(lead.nextFollowUpAt)}
                      </p>
                    ) : null}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}