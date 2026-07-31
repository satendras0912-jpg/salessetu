import Link from "next/link";

import type { ReactNode } from "react";

import type {
  LeadDetailAccess,
  LeadDetailRecord,
} from "@/types/lead-detail";

type LeadDetailViewProps = {
  lead: LeadDetailRecord;
  access: LeadDetailAccess;
  canEditLead: boolean;
  successMessage?: string | null;
};

type UnknownRecord = Record<string, unknown>;

type DetailItem = {
  label: string;
  value: ReactNode;
};

type DetailSectionProps = {
  title: string;
  description?: string;
  children: ReactNode;
};

type DetailGridProps = {
  items: DetailItem[];
};

type TimelineSectionProps = {
  title: string;
  description: string;
  entries: unknown[];
  emptyMessage: string;
};

const EMPTY_RECORD: UnknownRecord = {};

function toRecord(
  value: unknown,
): UnknownRecord | null {
  if (
    typeof value !== "object" ||
    value === null ||
    Array.isArray(value)
  ) {
    return null;
  }

  return value as UnknownRecord;
}

function toArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function readValue(
  record: UnknownRecord,
  keys: readonly string[],
): unknown {
  for (const key of keys) {
    const value = record[key];

    if (
      value !== undefined &&
      value !== null &&
      value !== ""
    ) {
      return value;
    }
  }

  return null;
}

function readText(
  record: UnknownRecord,
  keys: readonly string[],
  fallback = "—",
): string {
  const value = readValue(record, keys);

  if (value === null) {
    return fallback;
  }

  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return String(value);
  }

  return fallback;
}

function readNullableText(
  record: UnknownRecord,
  keys: readonly string[],
): string | null {
  const value = readValue(record, keys);

  if (
    typeof value === "string" ||
    typeof value === "number"
  ) {
    const text = String(value).trim();

    return text || null;
  }

  return null;
}

function readNumber(
  record: UnknownRecord,
  keys: readonly string[],
): number | null {
  const value = readValue(record, keys);

  if (
    typeof value !== "string" &&
    typeof value !== "number"
  ) {
    return null;
  }

  const parsed = Number(value);

  return Number.isFinite(parsed)
    ? parsed
    : null;
}

function readBoolean(
  record: UnknownRecord,
  keys: readonly string[],
): boolean | null {
  const value = readValue(record, keys);

  if (typeof value === "boolean") {
    return value;
  }

  if (value === "true" || value === 1) {
    return true;
  }

  if (value === "false" || value === 0) {
    return false;
  }

  return null;
}

function formatLabel(value: string): string {
  return value
    .replaceAll("_", " ")
    .replaceAll("-", " ")
    .replace(/\b\w/g, (character) =>
      character.toUpperCase(),
    );
}

function formatDateTime(
  value: unknown,
): string {
  if (
    typeof value !== "string" &&
    !(value instanceof Date)
  ) {
    return "—";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "—";
  }

  return new Intl.DateTimeFormat("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function formatBoolean(
  value: boolean | null,
): string {
  if (value === null) {
    return "—";
  }

  return value ? "Yes" : "No";
}

function formatCurrency(
  amount: number | null,
  currency: string,
): string {
  if (amount === null) {
    return "—";
  }

  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency,
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return `${currency} ${amount.toLocaleString(
      "en-IN",
    )}`;
  }
}

function formatBudgetRange(
  minimum: number | null,
  maximum: number | null,
  currency: string,
): string {
  if (minimum === null && maximum === null) {
    return "—";
  }

  if (minimum !== null && maximum !== null) {
    return `${formatCurrency(
      minimum,
      currency,
    )} – ${formatCurrency(maximum, currency)}`;
  }

  if (minimum !== null) {
    return `From ${formatCurrency(
      minimum,
      currency,
    )}`;
  }

  return `Up to ${formatCurrency(
    maximum,
    currency,
  )}`;
}

function formatTags(value: unknown): string[] {
  if (Array.isArray(value)) {
    return value
      .filter(
        (item): item is string =>
          typeof item === "string",
      )
      .map((item) => item.trim())
      .filter(Boolean);
  }

  if (typeof value === "string") {
    return value
      .split(/[,\n]/)
      .map((item) => item.trim())
      .filter(Boolean);
  }

  return [];
}

function getStatusClasses(
  value: string,
): string {
  const normalizedValue = value.toLowerCase();

  if (
    normalizedValue.includes("approved") ||
    normalizedValue.includes("qualified") ||
    normalizedValue.includes("booked") ||
    normalizedValue.includes("completed") ||
    normalizedValue.includes("active") ||
    normalizedValue === "hot"
  ) {
    return "border-emerald-500/40 bg-emerald-500/10 text-emerald-300";
  }

  if (
    normalizedValue.includes("review") ||
    normalizedValue.includes("pending") ||
    normalizedValue.includes("planned") ||
    normalizedValue.includes("warm") ||
    normalizedValue.includes("nurturing")
  ) {
    return "border-amber-500/40 bg-amber-500/10 text-amber-300";
  }

  if (
    normalizedValue.includes("rejected") ||
    normalizedValue.includes("invalid") ||
    normalizedValue.includes("fake") ||
    normalizedValue.includes("lost") ||
    normalizedValue.includes("failed") ||
    normalizedValue.includes("duplicate")
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
  if (!value || value === "—") {
    return <span className="text-slate-500">—</span>;
  }

  return (
    <span
      className={`inline-flex rounded-full border px-3 py-1 text-xs font-semibold ${getStatusClasses(
        value,
      )}`}
    >
      {formatLabel(value)}
    </span>
  );
}

function DetailSection({
  title,
  description,
  children,
}: DetailSectionProps) {
  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <div>
        <h2 className="text-xl font-semibold text-white">
          {title}
        </h2>

        {description ? (
          <p className="mt-2 text-sm leading-6 text-slate-400">
            {description}
          </p>
        ) : null}
      </div>

      <div className="mt-7">{children}</div>
    </section>
  );
}

function DetailGrid({
  items,
}: DetailGridProps) {
  return (
    <dl className="grid gap-5 sm:grid-cols-2 xl:grid-cols-3">
      {items.map((item) => (
        <div
          key={item.label}
          className="rounded-2xl border border-slate-800 bg-slate-950/60 p-4"
        >
          <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            {item.label}
          </dt>

          <dd className="mt-2 break-words text-sm font-medium leading-6 text-slate-200">
            {item.value}
          </dd>
        </div>
      ))}
    </dl>
  );
}

function TimelineSection({
  title,
  description,
  entries,
  emptyMessage,
}: TimelineSectionProps) {
  return (
    <DetailSection
      title={title}
      description={description}
    >
      {entries.length === 0 ? (
        <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-950/40 px-5 py-8 text-center text-sm text-slate-500">
          {emptyMessage}
        </div>
      ) : (
        <div className="space-y-4">
          {entries.map((entry, index) => {
            const item =
              toRecord(entry) ?? EMPTY_RECORD;

            const entryTitle = readText(
              item,
              [
                "title",
                "activityType",
                "activity_type",
                "action",
                "status",
                "eventType",
                "event_type",
                "type",
              ],
              "Activity",
            );

            const descriptionText =
              readText(
                item,
                [
                  "description",
                  "summary",
                  "notes",
                  "note",
                  "comments",
                  "reason",
                  "outcome",
                ],
                "No additional details.",
              );

            const actorName = readText(
              item,
              [
                "performedByName",
                "performed_by_name",
                "createdByName",
                "created_by_name",
                "userName",
                "user_name",
                "agentName",
                "agent_name",
              ],
              "",
            );

            const timestamp = readValue(
              item,
              [
                "createdAt",
                "created_at",
                "performedAt",
                "performed_at",
                "updatedAt",
                "updated_at",
                "scheduledAt",
                "scheduled_at",
                "visitDate",
                "visit_date",
              ],
            );

            return (
              <article
                key={`${entryTitle}-${index}`}
                className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5"
              >
                <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
                  <div>
                    <h3 className="font-semibold text-white">
                      {formatLabel(entryTitle)}
                    </h3>

                    <p className="mt-2 text-sm leading-6 text-slate-400">
                      {descriptionText}
                    </p>
                  </div>

                  <time className="shrink-0 text-xs text-slate-500">
                    {formatDateTime(timestamp)}
                  </time>
                </div>

                {actorName ? (
                  <p className="mt-3 text-xs text-slate-500">
                    By {actorName}
                  </p>
                ) : null}
              </article>
            );
          })}
        </div>
      )}
    </DetailSection>
  );
}

function isAccessAllowed(
  access: UnknownRecord,
  keys: readonly string[],
): boolean {
  let foundBoolean = false;

  for (const key of keys) {
    const value = access[key];

    if (typeof value === "boolean") {
      foundBoolean = true;

      if (value) {
        return true;
      }
    }
  }

  return !foundBoolean;
}

export default function LeadDetailView({
  lead,
  access,
  canEditLead,
  successMessage,
}: LeadDetailViewProps) {
  const leadRecord =
    lead as unknown as UnknownRecord;

  const accessRecord =
    access as unknown as UnknownRecord;

  const source =
    toRecord(
      readValue(leadRecord, [
        "source",
        "leadSource",
        "lead_source",
      ]),
    ) ?? EMPTY_RECORD;

  const assignment =
    toRecord(
      readValue(leadRecord, [
        "assignment",
        "currentAssignment",
        "current_assignment",
      ]),
    ) ?? EMPTY_RECORD;

  const qualification =
    toRecord(
      readValue(leadRecord, [
        "qualification",
        "leadQualification",
        "lead_qualification",
      ]),
    ) ?? EMPTY_RECORD;

  const validation =
    toRecord(
      readValue(leadRecord, [
        "validation",
        "leadValidation",
        "lead_validation",
      ]),
    ) ?? EMPTY_RECORD;

  const leadId = readText(
    leadRecord,
    ["id"],
    "",
  );

  const firstName = readNullableText(
    leadRecord,
    ["firstName", "first_name"],
  );

  const lastName = readNullableText(
    leadRecord,
    ["lastName", "last_name"],
  );

  const generatedName = [
    firstName,
    lastName,
  ]
    .filter(Boolean)
    .join(" ");

  const displayName =
    readNullableText(leadRecord, [
      "fullName",
      "full_name",
      "name",
    ]) ||
    generatedName ||
    "Unnamed Lead";

  const status = readText(
    leadRecord,
    ["leadStatus", "lead_status", "status"],
    "new",
  );

  const temperature = readText(
    leadRecord,
    [
      "leadTemperature",
      "lead_temperature",
      "temperature",
    ],
    "—",
  );

  const priority = readText(
    leadRecord,
    ["priority"],
    "normal",
  );

  const lifecycleStage = readText(
    leadRecord,
    [
      "lifecycleStage",
      "lifecycle_stage",
    ],
    "lead",
  );

  const currency = readText(
    leadRecord,
    [
      "budgetCurrency",
      "budget_currency",
    ],
    "INR",
  );

  const budgetMinimum = readNumber(
    leadRecord,
    ["budgetMin", "budget_min"],
  );

  const budgetMaximum = readNumber(
    leadRecord,
    ["budgetMax", "budget_max"],
  );

  const tags = formatTags(
    readValue(leadRecord, ["tags"]),
  );

  const activities = toArray(
    readValue(leadRecord, [
      "activities",
      "leadActivities",
      "lead_activities",
    ]),
  );

  const statusHistory = toArray(
    readValue(leadRecord, [
      "statusHistory",
      "status_history",
      "leadStatusHistory",
      "lead_status_history",
    ]),
  );

  const followUps = toArray(
    readValue(leadRecord, [
      "followUps",
      "follow_ups",
      "followups",
    ]),
  );

  const siteVisits = toArray(
    readValue(leadRecord, [
      "siteVisits",
      "site_visits",
    ]),
  );

  const canViewActivities =
    isAccessAllowed(accessRecord, [
      "canViewActivities",
      "viewActivities",
      "activities",
    ]);

  const canViewStatusHistory =
    isAccessAllowed(accessRecord, [
      "canViewStatusHistory",
      "viewStatusHistory",
      "statusHistory",
    ]);

  const canViewFollowUps =
    isAccessAllowed(accessRecord, [
      "canViewFollowUps",
      "viewFollowUps",
      "followUps",
    ]);

  const canViewSiteVisits =
    isAccessAllowed(accessRecord, [
      "canViewSiteVisits",
      "viewSiteVisits",
      "siteVisits",
    ]);

  return (
    <div className="space-y-8">
      {successMessage ? (
        <div className="rounded-2xl border border-emerald-500/40 bg-emerald-500/10 px-5 py-4 text-sm font-medium text-emerald-200">
          {successMessage}
        </div>
      ) : null}

      <header className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
        <div className="flex flex-col justify-between gap-6 xl:flex-row xl:items-start">
          <div>
            <Link
              href="/dashboard/leads"
              className="inline-flex text-sm font-semibold text-cyan-400 transition hover:text-cyan-300"
            >
              ← Back to leads
            </Link>

            <p className="mt-6 text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
              Lead Detail
            </p>

            <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
              {displayName}
            </h1>

            <div className="mt-5 flex flex-wrap gap-2">
              <StatusBadge value={status} />

              {temperature !== "—" ? (
                <StatusBadge value={temperature} />
              ) : null}

              <StatusBadge value={priority} />

              <StatusBadge
                value={lifecycleStage}
              />
            </div>
          </div>

          <div className="flex flex-col gap-3 sm:flex-row xl:flex-col">
            {canEditLead && leadId ? (
              <Link
                href={`/dashboard/leads/${leadId}/edit`}
                className="inline-flex items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 focus:outline-none focus:ring-2 focus:ring-cyan-300"
              >
                Edit lead
              </Link>
            ) : null}

            <div className="rounded-2xl border border-slate-800 bg-slate-950/60 px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                Lead ID
              </p>

              <p className="mt-2 max-w-72 break-all font-mono text-xs text-slate-300">
                {leadId || "—"}
              </p>
            </div>
          </div>
        </div>
      </header>

      <DetailSection
        title="Contact information"
        description="Customer identity and available communication channels."
      >
        <DetailGrid
          items={[
            {
              label: "First name",
              value:
                firstName ?? "—",
            },
            {
              label: "Last name",
              value:
                lastName ?? "—",
            },
            {
              label: "Phone",
              value: readText(leadRecord, [
                "phone",
                "mobile",
              ]),
            },
            {
              label: "Alternate phone",
              value: readText(leadRecord, [
                "alternatePhone",
                "alternate_phone",
              ]),
            },
            {
              label: "WhatsApp",
              value: readText(leadRecord, [
                "whatsappNumber",
                "whatsapp_number",
              ]),
            },
            {
              label: "Email",
              value: readText(leadRecord, [
                "email",
              ]),
            },
            {
              label: "Preferred language",
              value: readText(leadRecord, [
                "preferredLanguage",
                "preferred_language",
              ]),
            },
            {
              label: "Preferred channel",
              value: formatLabel(
                readText(leadRecord, [
                  "preferredContactChannel",
                  "preferred_contact_channel",
                ]),
              ),
            },
          ]}
        />
      </DetailSection>

      <DetailSection
        title="Property requirement"
        description="Customer property preference, budget and purchase intent."
      >
        <DetailGrid
          items={[
            {
              label: "Property type",
              value: readText(leadRecord, [
                "propertyType",
                "property_type",
              ]),
            },
            {
              label: "Transaction type",
              value: formatLabel(
                readText(leadRecord, [
                  "transactionType",
                  "transaction_type",
                ]),
              ),
            },
            {
              label: "Preferred project",
              value: readText(leadRecord, [
                "preferredProject",
                "preferred_project",
              ]),
            },
            {
              label: "Preferred location",
              value: readText(leadRecord, [
                "preferredLocation",
                "preferred_location",
              ]),
            },
            {
              label: "Preferred city",
              value: readText(leadRecord, [
                "preferredCity",
                "preferred_city",
              ]),
            },
            {
              label: "Unit type",
              value: readText(leadRecord, [
                "unitType",
                "unit_type",
              ]),
            },
            {
              label: "Bedrooms",
              value: readText(leadRecord, [
                "bedrooms",
              ]),
            },
            {
              label: "Budget",
              value: formatBudgetRange(
                budgetMinimum,
                budgetMaximum,
                currency,
              ),
            },
            {
              label: "Buying timeline",
              value: readText(leadRecord, [
                "buyingTimeline",
                "buying_timeline",
              ]),
            },
            {
              label: "Possession timeline",
              value: readText(leadRecord, [
                "possessionTimeline",
                "possession_timeline",
              ]),
            },
            {
              label: "Purpose",
              value: formatLabel(
                readText(leadRecord, [
                  "purpose",
                ]),
              ),
            },
            {
              label: "Financing required",
              value: formatBoolean(
                readBoolean(leadRecord, [
                  "financingRequired",
                  "financing_required",
                ]),
              ),
            },
            {
              label: "Loan status",
              value: readText(leadRecord, [
                "loanStatus",
                "loan_status",
              ]),
            },
          ]}
        />
      </DetailSection>

      <DetailSection
        title="Source and attribution"
        description="Lead acquisition source and marketing campaign information."
      >
        <DetailGrid
          items={[
            {
              label: "Source",
              value:
                readText(
                  source,
                  ["name"],
                  "",
                ) ||
                readText(leadRecord, [
                  "sourceName",
                  "source_name",
                ]),
            },
            {
              label: "Source code",
              value: readText(source, [
                "code",
              ]),
            },
            {
              label: "Source type",
              value: formatLabel(
                readText(source, [
                  "sourceType",
                  "source_type",
                ]),
              ),
            },
            {
              label: "Provider",
              value:
                readText(
                  source,
                  ["provider"],
                  "",
                ) ||
                readText(leadRecord, [
                  "externalProvider",
                  "external_provider",
                ]),
            },
            {
              label: "Campaign",
              value: readText(leadRecord, [
                "campaignName",
                "campaign_name",
              ]),
            },
            {
              label: "UTM source",
              value: readText(leadRecord, [
                "utmSource",
                "utm_source",
              ]),
            },
            {
              label: "UTM medium",
              value: readText(leadRecord, [
                "utmMedium",
                "utm_medium",
              ]),
            },
            {
              label: "UTM campaign",
              value: readText(leadRecord, [
                "utmCampaign",
                "utm_campaign",
              ]),
            },
            {
              label: "External lead ID",
              value: readText(leadRecord, [
                "externalLeadId",
                "external_lead_id",
              ]),
            },
          ]}
        />
      </DetailSection>

      <DetailSection
        title="Qualification and validation"
        description="System-managed lead quality, duplicate and verification state."
      >
        <DetailGrid
          items={[
            {
              label: "Qualification status",
              value: (
                <StatusBadge
                  value={
                    readText(
                      qualification,
                      ["status"],
                      "",
                    ) ||
                    readText(leadRecord, [
                      "qualificationStatus",
                      "qualification_status",
                    ])
                  }
                />
              ),
            },
            {
              label: "Qualification score",
              value:
                readText(
                  qualification,
                  ["score"],
                  "",
                ) ||
                readText(leadRecord, [
                  "qualificationScore",
                  "qualification_score",
                ]),
            },
            {
              label: "Validation decision",
              value: (
                <StatusBadge
                  value={
                    readText(
                      validation,
                      ["decision"],
                      "",
                    ) ||
                    readText(leadRecord, [
                      "validationDecision",
                      "validation_decision",
                    ])
                  }
                />
              ),
            },
            {
              label: "Duplicate status",
              value: (
                <StatusBadge
                  value={readText(leadRecord, [
                    "duplicateStatus",
                    "duplicate_status",
                  ])}
                />
              ),
            },
            {
              label: "Fake status",
              value: (
                <StatusBadge
                  value={readText(leadRecord, [
                    "fakeStatus",
                    "fake_status",
                  ])}
                />
              ),
            },
            {
              label: "AI qualified",
              value: formatBoolean(
                readBoolean(leadRecord, [
                  "aiQualified",
                  "ai_qualified",
                ]),
              ),
            },
            {
              label: "Phone verified",
              value: formatBoolean(
                readBoolean(leadRecord, [
                  "phoneVerified",
                  "phone_verified",
                ]),
              ),
            },
            {
              label: "Email verified",
              value: formatBoolean(
                readBoolean(leadRecord, [
                  "emailVerified",
                  "email_verified",
                ]),
              ),
            },
            {
              label: "WhatsApp verified",
              value: formatBoolean(
                readBoolean(leadRecord, [
                  "whatsappVerified",
                  "whatsapp_verified",
                ]),
              ),
            },
            {
              label: "Consent status",
              value: (
                <StatusBadge
                  value={readText(leadRecord, [
                    "consentStatus",
                    "consent_status",
                  ])}
                />
              ),
            },
            {
              label: "Consent source",
              value: readText(leadRecord, [
                "consentSource",
                "consent_source",
              ]),
            },
          ]}
        />
      </DetailSection>

      <DetailSection
        title="Assignment"
        description="Current ownership and lead-response responsibility."
      >
        <DetailGrid
          items={[
            {
              label: "Assigned agent",
              value:
                readText(
                  assignment,
                  [
                    "assignedToName",
                    "assigned_to_name",
                    "agentName",
                    "agent_name",
                    "name",
                  ],
                  "",
                ) ||
                readText(leadRecord, [
                  "assignedToName",
                  "assigned_to_name",
                ]),
            },
            {
              label: "Agent email",
              value: readText(assignment, [
                "assignedToEmail",
                "assigned_to_email",
                "agentEmail",
                "agent_email",
                "email",
              ]),
            },
            {
              label: "Assignment status",
              value: (
                <StatusBadge
                  value={
                    readText(
                      assignment,
                      ["status"],
                      "",
                    ) ||
                    readText(leadRecord, [
                      "assignmentStatus",
                      "assignment_status",
                    ])
                  }
                />
              ),
            },
            {
              label: "Assigned at",
              value: formatDateTime(
                readValue(assignment, [
                  "assignedAt",
                  "assigned_at",
                ]) ??
                  readValue(leadRecord, [
                    "assignedAt",
                    "assigned_at",
                  ]),
              ),
            },
            {
              label: "Assignment due",
              value: formatDateTime(
                readValue(assignment, [
                  "dueAt",
                  "due_at",
                  "assignmentDueAt",
                  "assignment_due_at",
                ]) ??
                  readValue(leadRecord, [
                    "assignmentDueAt",
                    "assignment_due_at",
                  ]),
              ),
            },
            {
              label: "Team",
              value: readText(assignment, [
                "teamName",
                "team_name",
              ]),
            },
          ]}
        />
      </DetailSection>

      <DetailSection
        title="Notes and tags"
        description="Internal sales information associated with this lead."
      >
        <div className="space-y-6">
          <div className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              Notes
            </p>

            <p className="mt-3 whitespace-pre-wrap text-sm leading-7 text-slate-300">
              {readText(leadRecord, ["notes"])}
            </p>
          </div>

          <div>
            <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
              Tags
            </p>

            {tags.length > 0 ? (
              <div className="mt-3 flex flex-wrap gap-2">
                {tags.map((tag) => (
                  <span
                    key={tag}
                    className="rounded-full border border-cyan-500/30 bg-cyan-500/10 px-3 py-1 text-xs font-medium text-cyan-300"
                  >
                    {tag}
                  </span>
                ))}
              </div>
            ) : (
              <p className="mt-3 text-sm text-slate-500">
                No tags added.
              </p>
            )}
          </div>
        </div>
      </DetailSection>

      {canViewActivities ? (
        <TimelineSection
          title="Recent activity"
          description="Calls, messages, notes and operational activity recorded against this lead."
          entries={activities}
          emptyMessage="No lead activity has been recorded."
        />
      ) : null}

      {canViewStatusHistory ? (
        <TimelineSection
          title="Status history"
          description="Previous lead statuses and lifecycle changes."
          entries={statusHistory}
          emptyMessage="No status history is available."
        />
      ) : null}

      {canViewFollowUps ? (
        <TimelineSection
          title="Follow-ups"
          description="Scheduled and completed customer follow-up actions."
          entries={followUps}
          emptyMessage="No follow-up is currently recorded."
        />
      ) : null}

      {canViewSiteVisits ? (
        <TimelineSection
          title="Site visits"
          description="Site-visit schedule, current status and visit outcome."
          entries={siteVisits}
          emptyMessage="No site visit has been scheduled."
        />
      ) : null}

      <DetailSection title="System information">
        <DetailGrid
          items={[
            {
              label: "Created at",
              value: formatDateTime(
                readValue(leadRecord, [
                  "createdAt",
                  "created_at",
                ]),
              ),
            },
            {
              label: "Last updated",
              value: formatDateTime(
                readValue(leadRecord, [
                  "updatedAt",
                  "updated_at",
                ]),
              ),
            },
            {
              label: "First contacted",
              value: formatDateTime(
                readValue(leadRecord, [
                  "firstContactedAt",
                  "first_contacted_at",
                ]),
              ),
            },
            {
              label: "Last contacted",
              value: formatDateTime(
                readValue(leadRecord, [
                  "lastContactedAt",
                  "last_contacted_at",
                ]),
              ),
            },
            {
              label: "Next follow-up",
              value: formatDateTime(
                readValue(leadRecord, [
                  "nextFollowUpAt",
                  "next_follow_up_at",
                ]),
              ),
            },
          ]}
        />
      </DetailSection>
    </div>
  );
}