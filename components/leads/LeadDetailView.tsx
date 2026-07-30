import Link from "next/link";

import type {
  LeadDetailAccess,
  LeadDetailRecord,
} from "@/types/lead-detail";

type LeadDetailViewProps = {
  lead: LeadDetailRecord;
  access: LeadDetailAccess;
};

type InformationFieldProps = {
  label: string;
  value: React.ReactNode;
};

type StatusBadgeProps = {
  value: string | null | undefined;
};

function formatLabel(
  value: string | null | undefined,
): string {
  if (!value) {
    return "Not available";
  }

  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (character) =>
      character.toUpperCase(),
    );
}

function formatDate(
  value: string | null | undefined,
): string {
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

function formatCurrency(
  value: number | null,
  currency: string,
): string {
  if (value === null) {
    return "Not specified";
  }

  try {
    return new Intl.NumberFormat("en-GB", {
      style: "currency",
      currency,
      maximumFractionDigits: 0,
    }).format(value);
  } catch {
    return `${currency} ${value.toLocaleString("en-GB")}`;
  }
}

function formatBudget(
  lead: LeadDetailRecord,
): string {
  const minimum =
    lead.budgetMin !== null
      ? formatCurrency(
          lead.budgetMin,
          lead.budgetCurrency,
        )
      : null;

  const maximum =
    lead.budgetMax !== null
      ? formatCurrency(
          lead.budgetMax,
          lead.budgetCurrency,
        )
      : null;

  if (minimum && maximum) {
    return `${minimum} – ${maximum}`;
  }

  return minimum ?? maximum ?? "Not specified";
}

function booleanLabel(
  value: boolean | null | undefined,
): string {
  if (value === null || value === undefined) {
    return "Unknown";
  }

  return value ? "Yes" : "No";
}

function statusClasses(
  value: string | null | undefined,
): string {
  switch (value?.trim().toLowerCase()) {
    case "active":
    case "approved":
    case "accepted":
    case "completed":
    case "converted":
    case "qualified":
    case "valid":
    case "eligible":
    case "passed":
      return "border-emerald-500/30 bg-emerald-500/10 text-emerald-300";

    case "new":
    case "pending":
    case "manual_review":
    case "contacted":
    case "scheduled":
    case "warm":
    case "queued":
      return "border-amber-500/30 bg-amber-500/10 text-amber-300";

    case "assigned":
    case "site_visit":
    case "hot":
    case "in_progress":
    case "answered":
      return "border-cyan-500/30 bg-cyan-500/10 text-cyan-300";

    case "rejected":
    case "lost":
    case "cancelled":
    case "failed":
    case "blocked":
    case "fake":
    case "invalid":
    case "suppressed":
      return "border-red-500/30 bg-red-500/10 text-red-300";

    default:
      return "border-slate-700 bg-slate-800 text-slate-300";
  }
}

function StatusBadge({
  value,
}: StatusBadgeProps) {
  return (
    <span
      className={[
        "inline-flex rounded-full border px-3 py-1 text-xs font-medium",
        statusClasses(value),
      ].join(" ")}
    >
      {formatLabel(value)}
    </span>
  );
}

function InformationField({
  label,
  value,
}: InformationFieldProps) {
  return (
    <div className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5">
      <p className="text-xs font-medium uppercase tracking-wider text-slate-500">
        {label}
      </p>

      <div className="mt-2 break-words text-sm font-medium text-slate-200">
        {value}
      </div>
    </div>
  );
}

function SectionHeader({
  title,
  description,
  count,
}: {
  title: string;
  description?: string;
  count?: number;
}) {
  return (
    <div className="flex flex-col justify-between gap-3 sm:flex-row sm:items-start">
      <div>
        <h2 className="text-xl font-semibold text-white">
          {title}
        </h2>

        {description ? (
          <p className="mt-1 text-sm leading-6 text-slate-400">
            {description}
          </p>
        ) : null}
      </div>

      {count !== undefined ? (
        <span className="w-fit rounded-full border border-slate-700 bg-slate-950 px-3 py-1 text-xs text-slate-300">
          {count}
        </span>
      ) : null}
    </div>
  );
}

function EmptyState({
  message,
}: {
  message: string;
}) {
  return (
    <div className="mt-6 rounded-2xl border border-dashed border-slate-700 bg-slate-950/40 p-8 text-center">
      <p className="text-sm text-slate-400">
        {message}
      </p>
    </div>
  );
}

function RestrictedSection({
  module,
}: {
  module: string;
}) {
  return (
    <div className="mt-6 rounded-2xl border border-red-900/50 bg-red-950/10 p-5">
      <p className="text-sm font-medium text-red-300">
        Restricted section
      </p>

      <p className="mt-2 text-sm leading-6 text-slate-400">
        Your account does not have permission to view{" "}
        {module}.
      </p>
    </div>
  );
}

export default function LeadDetailView({
  lead,
  access,
}: LeadDetailViewProps) {
  const combinedTimeline = [
    ...lead.activities.map((activity) => ({
      id: `activity-${activity.id}`,
      date:
        activity.startedAt ??
        activity.completedAt ??
        activity.createdAt,
      title:
        activity.subject ??
        formatLabel(activity.activityType),
      description:
        activity.description ??
        activity.aiSummary ??
        activity.outcome,
      status: activity.status,
      category: "Activity",
      automated: activity.isAutomated,
    })),

    ...lead.statusHistory.map((history) => ({
      id: `status-${history.id}`,
      date: history.changedAt,
      title: `${formatLabel(
        history.previousStatus,
      )} → ${formatLabel(history.newStatus)}`,
      description:
        history.changeReason ??
        "Lead status was updated.",
      status: history.newStatus,
      category: "Status change",
      automated: false,
    })),
  ]
    .sort(
      (first, second) =>
        new Date(second.date).getTime() -
        new Date(first.date).getTime(),
    )
    .slice(0, 30);

  return (
    <div className="space-y-8">
      {/* Header */}
      <header className="flex flex-col justify-between gap-6 xl:flex-row xl:items-start">
        <div>
          <Link
            href="/dashboard/leads"
            className="inline-flex items-center text-sm font-medium text-cyan-400 transition hover:text-cyan-300"
          >
            ← Back to Lead Operations
          </Link>

          <p className="mt-6 text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            Lead Profile
          </p>

          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
            {lead.fullName}
          </h1>

          <div className="mt-4 flex flex-wrap gap-2">
            <StatusBadge value={lead.leadStatus} />

            <StatusBadge
              value={lead.leadTemperature}
            />

            <StatusBadge value={lead.priority} />

            <StatusBadge
              value={lead.assignmentStatus}
            />
          </div>

          <p className="mt-4 font-mono text-xs text-slate-600">
            {lead.id}
          </p>
        </div>

        <div className="grid min-w-72 grid-cols-2 gap-3">
          <InformationField
            label="Created"
            value={formatDate(lead.createdAt)}
          />

          <InformationField
            label="Last updated"
            value={formatDate(lead.updatedAt)}
          />
        </div>
      </header>

      {/* Metrics */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Qualification
          </p>

          <p className="mt-2 text-2xl font-semibold text-white">
            {lead.qualificationScore ?? "—"}
          </p>

          <p className="mt-1 text-xs text-slate-500">
            {formatLabel(
              lead.qualificationStatus,
            )}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Trust score
          </p>

          <p className="mt-2 text-2xl font-semibold text-cyan-300">
            {lead.validation?.trustScore ?? "—"}
          </p>

          <p className="mt-1 text-xs text-slate-500">
            {formatLabel(
              lead.validation?.decision,
            )}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Follow-ups
          </p>

          <p className="mt-2 text-2xl font-semibold text-white">
            {lead.followUps.length}
          </p>

          <p className="mt-1 text-xs text-slate-500">
            Total tasks
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            Site visits
          </p>

          <p className="mt-2 text-2xl font-semibold text-white">
            {lead.siteVisits.length}
          </p>

          <p className="mt-1 text-xs text-slate-500">
            Visit records
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">
            AI calls
          </p>

          <p className="mt-2 text-2xl font-semibold text-white">
            {lead.aiCalls.length}
          </p>

          <p className="mt-1 text-xs text-slate-500">
            Call jobs
          </p>
        </article>
      </section>

      {/* Contact and requirements */}
      <section className="grid gap-6 xl:grid-cols-2">
        <article className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
          <SectionHeader
            title="Contact information"
            description="Lead identity, communication preferences and verification."
          />

          <div className="mt-6 grid gap-4 sm:grid-cols-2">
            <InformationField
              label="Phone"
              value={lead.phone ?? "Not available"}
            />

            <InformationField
              label="WhatsApp"
              value={
                lead.whatsappNumber ??
                "Not available"
              }
            />

            <InformationField
              label="Email"
              value={lead.email ?? "Not available"}
            />

            <InformationField
              label="Alternate phone"
              value={
                lead.alternatePhone ??
                "Not available"
              }
            />

            <InformationField
              label="Preferred language"
              value={formatLabel(
                lead.preferredLanguage,
              )}
            />

            <InformationField
              label="Preferred channel"
              value={formatLabel(
                lead.preferredContactChannel,
              )}
            />

            <InformationField
              label="Phone verified"
              value={booleanLabel(
                lead.phoneVerified,
              )}
            />

            <InformationField
              label="Email verified"
              value={booleanLabel(
                lead.emailVerified,
              )}
            />
          </div>
        </article>

        <article className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
          <SectionHeader
            title="Property requirement"
            description="Customer requirement, location, budget and buying timeline."
          />

          <div className="mt-6 grid gap-4 sm:grid-cols-2">
            <InformationField
              label="Preferred project"
              value={
                lead.preferredProject ??
                "Not specified"
              }
            />

            <InformationField
              label="Location"
              value={
                lead.preferredLocation ??
                lead.preferredCity ??
                "Not specified"
              }
            />

            <InformationField
              label="Property type"
              value={formatLabel(
                lead.propertyType,
              )}
            />

            <InformationField
              label="Unit type"
              value={formatLabel(lead.unitType)}
            />

            <InformationField
              label="Budget"
              value={formatBudget(lead)}
            />

            <InformationField
              label="Buying timeline"
              value={formatLabel(
                lead.buyingTimeline,
              )}
            />

            <InformationField
              label="Purpose"
              value={formatLabel(lead.purpose)}
            />

            <InformationField
              label="Finance required"
              value={booleanLabel(
                lead.financingRequired,
              )}
            />
          </div>
        </article>
      </section>

      {/* Source and qualification */}
      <section className="grid gap-6 xl:grid-cols-2">
        <article className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
          <SectionHeader
            title="Acquisition source"
            description="Lead source, campaign and attribution information."
          />

          <div className="mt-6 grid gap-4 sm:grid-cols-2">
            <InformationField
              label="Source"
              value={
                lead.source?.name ??
                lead.utmSource ??
                "Unknown"
              }
            />

            <InformationField
              label="Provider"
              value={
                lead.source?.provider ??
                lead.externalProvider ??
                "Not available"
              }
            />

            <InformationField
              label="Campaign"
              value={
                lead.campaignName ??
                lead.utmCampaign ??
                "Not available"
              }
            />

            <InformationField
              label="UTM medium"
              value={
                lead.utmMedium ??
                "Not available"
              }
            />

            <InformationField
              label="External lead ID"
              value={
                lead.externalLeadId ??
                lead.metaLeadId ??
                lead.googleLeadId ??
                "Not available"
              }
            />

            <InformationField
              label="Consent status"
              value={
                <StatusBadge
                  value={lead.consentStatus}
                />
              }
            />
          </div>
        </article>

        <article className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
          <SectionHeader
            title="Qualification"
            description="Current qualification and AI assessment."
          />

          <div className="mt-6 grid gap-4 sm:grid-cols-2">
            <InformationField
              label="Status"
              value={
                <StatusBadge
                  value={
                    lead.qualificationStatus
                  }
                />
              }
            />

            <InformationField
              label="Score"
              value={
                lead.qualificationScore ??
                "Not scored"
              }
            />

            <InformationField
              label="AI qualified"
              value={booleanLabel(
                lead.aiQualified,
              )}
            />

            <InformationField
              label="AI provider"
              value={
                lead.aiProvider ??
                "Not available"
              }
            />
          </div>

          {lead.qualificationSummary ? (
            <div className="mt-4 rounded-2xl border border-slate-800 bg-slate-950/70 p-5">
              <p className="text-xs uppercase tracking-wider text-slate-500">
                Qualification summary
              </p>

              <p className="mt-2 text-sm leading-6 text-slate-300">
                {lead.qualificationSummary}
              </p>
            </div>
          ) : null}
        </article>
      </section>

      {/* Validation */}
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
        <SectionHeader
          title="Lead validation"
          description="Authenticity, contactability, duplicate and fraud assessment."
        />

        {!access.canViewValidation ? (
          <RestrictedSection module="lead validation results" />
        ) : lead.validation ? (
          <>
            <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
              <InformationField
                label="Decision"
                value={
                  <StatusBadge
                    value={lead.validation.decision}
                  />
                }
              />

              <InformationField
                label="Trust"
                value={
                  lead.validation.trustScore ??
                  "Not scored"
                }
              />

              <InformationField
                label="Authenticity"
                value={
                  lead.validation
                    .authenticityScore ??
                  "Not scored"
                }
              />

              <InformationField
                label="Fraud"
                value={
                  lead.validation.fraudScore ??
                  "Not scored"
                }
              />

              <InformationField
                label="Duplicate"
                value={
                  lead.validation
                    .duplicateScore ??
                  "Not scored"
                }
              />
            </div>

            <div className="mt-4 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
              <InformationField
                label="Phone valid"
                value={booleanLabel(
                  lead.validation.phoneValid,
                )}
              />

              <InformationField
                label="Email valid"
                value={booleanLabel(
                  lead.validation.emailValid,
                )}
              />

              <InformationField
                label="Consent valid"
                value={booleanLabel(
                  lead.validation.consentValid,
                )}
              />

              <InformationField
                label="AI call eligibility"
                value={
                  <StatusBadge
                    value={
                      lead.validation
                        .aiCallEligibility
                    }
                  />
                }
              />
            </div>

            {lead.validation.summary ? (
              <div className="mt-4 rounded-2xl border border-slate-800 bg-slate-950/70 p-5">
                <p className="text-sm leading-6 text-slate-300">
                  {lead.validation.summary}
                </p>
              </div>
            ) : null}
          </>
        ) : (
          <EmptyState message="No validation result is available for this lead." />
        )}
      </section>

      {/* Assignment */}
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
        <SectionHeader
          title="Current assignment"
          description="Current agent assignment and response SLA."
        />

        {!access.canViewAssignment ? (
          <RestrictedSection module="lead assignment details" />
        ) : lead.assignment ? (
          <div className="mt-6 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
            <InformationField
              label="Agent"
              value={
                lead.assignment.agentName ??
                lead.assignment.agentCode ??
                "Not available"
              }
            />

            <InformationField
              label="Status"
              value={
                <StatusBadge
                  value={lead.assignment.status}
                />
              }
            />

            <InformationField
              label="Strategy"
              value={formatLabel(
                lead.assignment.strategy,
              )}
            />

            <InformationField
              label="Assigned at"
              value={formatDate(
                lead.assignment.assignedAt,
              )}
            />

            <InformationField
              label="Acceptance due"
              value={formatDate(
                lead.assignment
                  .acceptanceDueAt,
              )}
            />

            <InformationField
              label="Response due"
              value={formatDate(
                lead.assignment.responseDueAt,
              )}
            />

            <InformationField
              label="Assignment score"
              value={
                lead.assignment
                  .assignmentScore ??
                "Not scored"
              }
            />

            <InformationField
              label="First response"
              value={formatDate(
                lead.assignment
                  .firstResponseAt,
              )}
            />
          </div>
        ) : (
          <EmptyState message="This lead is not currently assigned to an agent." />
        )}
      </section>

      {/* Follow-ups */}
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
        <SectionHeader
          title="Follow-ups"
          description="Scheduled and completed follow-up tasks."
          count={lead.followUps.length}
        />

        {!access.canViewFollowUps ? (
          <RestrictedSection module="follow-up tasks" />
        ) : lead.followUps.length > 0 ? (
          <div className="mt-6 space-y-4">
            {lead.followUps
              .slice(0, 20)
              .map((followUp) => (
                <article
                  key={followUp.id}
                  className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5"
                >
                  <div className="flex flex-col justify-between gap-3 sm:flex-row">
                    <div>
                      <h3 className="font-semibold text-white">
                        {followUp.title}
                      </h3>

                      <p className="mt-1 text-sm text-slate-400">
                        {formatLabel(
                          followUp.followUpType,
                        )}{" "}
                        • Due{" "}
                        {formatDate(followUp.dueAt)}
                      </p>
                    </div>

                    <div className="flex gap-2">
                      <StatusBadge
                        value={followUp.status}
                      />

                      <StatusBadge
                        value={followUp.priority}
                      />
                    </div>
                  </div>

                  {followUp.description ? (
                    <p className="mt-4 text-sm leading-6 text-slate-300">
                      {followUp.description}
                    </p>
                  ) : null}

                  {followUp.completionNotes ? (
                    <p className="mt-3 text-sm leading-6 text-emerald-300">
                      {followUp.completionNotes}
                    </p>
                  ) : null}
                </article>
              ))}
          </div>
        ) : (
          <EmptyState message="No follow-up tasks are available." />
        )}
      </section>

      {/* Site visits */}
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
        <SectionHeader
          title="Site visits"
          description="Scheduled and completed project visits."
          count={lead.siteVisits.length}
        />

        {!access.canViewSiteVisits ? (
          <RestrictedSection module="site visit records" />
        ) : lead.siteVisits.length > 0 ? (
          <div className="mt-6 grid gap-4 xl:grid-cols-2">
            {lead.siteVisits
              .slice(0, 12)
              .map((visit) => (
                <article
                  key={visit.id}
                  className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5"
                >
                  <div className="flex justify-between gap-4">
                    <div>
                      <h3 className="font-semibold text-white">
                        {visit.projectName}
                      </h3>

                      <p className="mt-1 text-sm text-slate-500">
                        {visit.title}
                      </p>
                    </div>

                    <StatusBadge
                      value={visit.status}
                    />
                  </div>

                  <div className="mt-4 space-y-2 text-sm text-slate-300">
                    <p>
                      Scheduled:{" "}
                      {formatDate(
                        visit.scheduledStartAt,
                      )}
                    </p>

                    <p>
                      Location:{" "}
                      {visit.visitAddress ??
                        visit.visitCity ??
                        "Not available"}
                    </p>

                    <p>
                      Confirmation:{" "}
                      {formatLabel(
                        visit.confirmationStatus,
                      )}
                    </p>
                  </div>

                  {visit.outcomeSummary ? (
                    <p className="mt-4 text-sm leading-6 text-cyan-300">
                      {visit.outcomeSummary}
                    </p>
                  ) : null}
                </article>
              ))}
          </div>
        ) : (
          <EmptyState message="No site visit record is available." />
        )}
      </section>

      {/* AI calls */}
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
        <SectionHeader
          title="AI calling history"
          description="AI call jobs, attempts, transcripts and qualification results."
          count={lead.aiCalls.length}
        />

        {!access.canViewAiCalls ? (
          <RestrictedSection module="AI call records" />
        ) : lead.aiCalls.length > 0 ? (
          <div className="mt-6 space-y-5">
            {lead.aiCalls
              .slice(0, 10)
              .map((call) => {
                const latestTranscript =
                  call.transcripts[0];

                const latestQualification =
                  call.qualificationResults[0];

                return (
                  <article
                    key={call.id}
                    className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5"
                  >
                    <div className="flex flex-col justify-between gap-3 sm:flex-row">
                      <div>
                        <p className="font-semibold text-white">
                          {call.contactName ??
                            lead.fullName}
                        </p>

                        <p className="mt-1 text-sm text-slate-500">
                          {call.phoneNumber} •{" "}
                          {formatDate(call.createdAt)}
                        </p>
                      </div>

                      <StatusBadge
                        value={call.status}
                      />
                    </div>

                    <div className="mt-4 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                      <InformationField
                        label="Attempts"
                        value={`${call.attemptCount}/${call.maximumAttempts}`}
                      />

                      <InformationField
                        label="Disposition"
                        value={formatLabel(
                          call.finalDispositionCode,
                        )}
                      />

                      <InformationField
                        label="Qualification"
                        value={formatLabel(
                          call.qualificationStatus,
                        )}
                      />

                      <InformationField
                        label="Score"
                        value={
                          call.qualificationScore ??
                          latestQualification?.normalizedScore ??
                          "Not scored"
                        }
                      />
                    </div>

                    {latestTranscript?.summary ? (
                      <div className="mt-4 rounded-xl border border-slate-800 bg-slate-900 p-4">
                        <p className="text-xs uppercase tracking-wider text-slate-500">
                          Call summary
                        </p>

                        <p className="mt-2 text-sm leading-6 text-slate-300">
                          {latestTranscript.summary}
                        </p>
                      </div>
                    ) : null}

                    {latestQualification
                      ?.recommendedAction ? (
                      <p className="mt-4 text-sm text-cyan-300">
                        Recommended action:{" "}
                        {formatLabel(
                          latestQualification
                            .recommendedAction,
                        )}
                      </p>
                    ) : null}
                  </article>
                );
              })}
          </div>
        ) : (
          <EmptyState message="No AI call job has been created for this lead." />
        )}
      </section>

      {/* Combined activity timeline */}
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
        <SectionHeader
          title="Activity timeline"
          description="Recent lead activity and status transitions."
          count={combinedTimeline.length}
        />

        {combinedTimeline.length > 0 ? (
          <div className="mt-6 space-y-4">
            {combinedTimeline.map(
              (timelineItem) => (
                <article
                  key={timelineItem.id}
                  className="relative rounded-2xl border border-slate-800 bg-slate-950/70 p-5 pl-9"
                >
                  <span
                    aria-hidden="true"
                    className="absolute left-4 top-6 h-2.5 w-2.5 rounded-full bg-cyan-400"
                  />

                  <div className="flex flex-col justify-between gap-3 sm:flex-row">
                    <div>
                      <p className="font-medium text-white">
                        {timelineItem.title}
                      </p>

                      <p className="mt-1 text-xs uppercase tracking-wider text-slate-600">
                        {timelineItem.category}
                        {timelineItem.automated
                          ? " • Automated"
                          : ""}
                      </p>
                    </div>

                    <div className="flex items-center gap-3">
                      <StatusBadge
                        value={timelineItem.status}
                      />

                      <span className="text-xs text-slate-500">
                        {formatDate(
                          timelineItem.date,
                        )}
                      </span>
                    </div>
                  </div>

                  {timelineItem.description ? (
                    <p className="mt-3 text-sm leading-6 text-slate-400">
                      {timelineItem.description}
                    </p>
                  ) : null}
                </article>
              ),
            )}
          </div>
        ) : (
          <EmptyState message="No lead activity has been recorded yet." />
        )}
      </section>

      {/* Notes and communication restrictions */}
      <section className="grid gap-6 xl:grid-cols-2">
        <article className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
          <SectionHeader title="Lead notes" />

          <div className="mt-6 rounded-2xl border border-slate-800 bg-slate-950/70 p-5">
            <p className="whitespace-pre-wrap text-sm leading-7 text-slate-300">
              {lead.notes ??
                "No notes have been added."}
            </p>
          </div>
        </article>

        <article className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
          <SectionHeader title="Communication controls" />

          <div className="mt-6 grid gap-4 sm:grid-cols-3">
            <InformationField
              label="Do not call"
              value={booleanLabel(
                lead.doNotCall,
              )}
            />

            <InformationField
              label="Do not email"
              value={booleanLabel(
                lead.doNotEmail,
              )}
            />

            <InformationField
              label="Do not WhatsApp"
              value={booleanLabel(
                lead.doNotWhatsapp,
              )}
            />
          </div>
        </article>
      </section>
    </div>
  );
}