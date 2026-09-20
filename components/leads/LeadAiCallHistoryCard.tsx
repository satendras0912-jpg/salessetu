import type {
  LeadAiCallJobItem,
} from "@/types/lead-detail";

type LeadAiCallHistoryCardProps = {
  calls: LeadAiCallJobItem[];
};

function formatLabel(value: string | null) {
  if (!value) {
    return "Not available";
  }

  return value
    .replaceAll("_", " ")
    .replace(/\b\w/g, (character) =>
      character.toUpperCase(),
    );
}

function formatDateTime(value: string | null) {
  if (!value) {
    return "Not available";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "Not available";
  }

  return new Intl.DateTimeFormat("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Kolkata",
  }).format(date);
}

function formatDuration(
  value: number | null,
) {
  if (
    value === null ||
    !Number.isFinite(value) ||
    value < 0
  ) {
    return "Not available";
  }

  const totalSeconds =
    Math.round(value);

  const minutes =
    Math.floor(totalSeconds / 60);

  const seconds =
    totalSeconds % 60;

  if (minutes === 0) {
    return `${seconds}s`;
  }

  return `${minutes}m ${seconds}s`;
}

function formatCost(
  value: number | null,
  currency: string | null,
) {
  if (
    value === null ||
    !Number.isFinite(value)
  ) {
    return "Not available";
  }

  if (!currency) {
    return value.toFixed(2);
  }

  try {
    return new Intl.NumberFormat(
      "en-IN",
      {
        style: "currency",
        currency:
          currency.toUpperCase(),
        maximumFractionDigits: 4,
      },
    ).format(value);
  } catch {
    return `${value.toFixed(2)} ${currency.toUpperCase()}`;
  }
}

function maskPhoneNumber(value: string) {
  const cleanValue =
    value.trim();

  if (cleanValue.length <= 4) {
    return cleanValue;
  }

  return `${"*".repeat(
    Math.max(
      cleanValue.length - 4,
      4,
    ),
  )}${cleanValue.slice(-4)}`;
}

function getStatusClasses(status: string) {
  switch (status.toLowerCase()) {
    case "completed":
    case "answered":
      return "border-emerald-800 bg-emerald-950/50 text-emerald-300";

    case "failed":
    case "cancelled":
      return "border-rose-800 bg-rose-950/50 text-rose-300";

    case "busy":
    case "no_answer":
    case "voicemail":
      return "border-amber-800 bg-amber-950/50 text-amber-300";

    default:
      return "border-slate-700 bg-slate-800 text-slate-300";
  }
}

export default function LeadAiCallHistoryCard({
  calls,
}: LeadAiCallHistoryCardProps) {
  return (
    <section className="space-y-6 rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          AI Call History
        </p>

        <h2 className="mt-3 text-2xl font-bold text-white">
          Customer calling timeline
        </h2>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Call outcomes, duration, cost,
          recordings and transcript insights for
          this lead.
        </p>
      </header>

      {calls.length === 0 ? (
        <div className="rounded-2xl border border-slate-800 bg-slate-950/50 p-5">
          <h3 className="font-semibold text-white">
            No AI calls yet
          </h3>

          <p className="mt-2 text-sm leading-6 text-slate-400">
            AI call attempts will appear here after
            a calling job is created for this lead.
          </p>
        </div>
      ) : (
        <div className="space-y-4">
          {calls.map((call) => {
            const latestAttempt =
              call.attempts[0] ?? null;

            const latestTranscript =
              call.transcripts[0] ?? null;

            const status =
              latestAttempt?.status ||
              call.status;

            const disposition =
              latestAttempt
                ?.dispositionCode ||
              call.finalDispositionCode;

            const occurredAt =
              latestAttempt?.completedAt ||
              latestAttempt?.endedAt ||
              latestAttempt?.initiatedAt ||
              latestAttempt?.dispatchedAt ||
              call.completedAt ||
              call.startedAt ||
              call.queuedAt ||
              call.createdAt;

            return (
              <article
                key={call.id}
                className="rounded-2xl border border-slate-800 bg-slate-950/50 p-5"
              >
                <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <span
                        className={`inline-flex rounded-full border px-3 py-1 text-xs font-semibold ${getStatusClasses(
                          status,
                        )}`}
                      >
                        {formatLabel(status)}
                      </span>

                      {disposition ? (
                        <span className="inline-flex rounded-full border border-slate-700 bg-slate-900 px-3 py-1 text-xs font-semibold text-slate-300">
                          {formatLabel(
                            disposition,
                          )}
                        </span>
                      ) : null}
                    </div>

                    <p className="mt-3 text-sm font-semibold text-white">
                      {formatDateTime(
                        occurredAt,
                      )}
                    </p>

                    <p className="mt-1 text-xs text-slate-500">
                      To{" "}
                      {maskPhoneNumber(
                        latestAttempt
                          ?.toPhoneNumber ||
                          call.phoneNumber,
                      )}
                    </p>
                  </div>

                  <p className="text-xs font-medium text-slate-500">
                    Attempt{" "}
                    {latestAttempt
                      ?.attemptNumber ??
                      call.attemptCount}
                    {" / "}
                    {call.maximumAttempts}
                  </p>
                </div>

                <dl className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4">
                    <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                      Duration
                    </dt>

                    <dd className="mt-2 text-sm font-semibold text-white">
                      {formatDuration(
                        latestAttempt
                          ?.callDurationSeconds ??
                          null,
                      )}
                    </dd>
                  </div>

                  <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4">
                    <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                      Cost
                    </dt>

                    <dd className="mt-2 text-sm font-semibold text-white">
                      {formatCost(
                        latestAttempt
                          ?.providerCost ??
                          null,
                        latestAttempt
                          ?.providerCurrency ??
                          null,
                      )}
                    </dd>
                  </div>

                  <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4">
                    <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                      Sentiment
                    </dt>

                    <dd className="mt-2 text-sm font-semibold text-white">
                      {formatLabel(
                        latestTranscript
                          ?.sentiment ??
                          null,
                      )}
                    </dd>
                  </div>

                  <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4">
                    <dt className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                      Recording
                    </dt>

                    <dd className="mt-2 text-sm font-semibold">
                      {latestAttempt
                        ?.recordingUrl ? (
                        <a
                          href={
                            latestAttempt.recordingUrl
                          }
                          target="_blank"
                          rel="noreferrer"
                          className="text-cyan-300 hover:text-cyan-200"
                        >
                          Open recording
                        </a>
                      ) : (
                        <span className="text-slate-400">
                          Not available
                        </span>
                      )}
                    </dd>
                  </div>
                </dl>

                {latestTranscript?.summary ? (
                  <div className="mt-4 rounded-xl border border-slate-800 bg-slate-900/60 p-4">
                    <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                      Call summary
                    </p>

                    <p className="mt-2 text-sm leading-6 text-slate-300">
                      {latestTranscript.summary}
                    </p>
                  </div>
                ) : null}

                {latestAttempt?.errorMessage ? (
                  <div className="mt-4 rounded-xl border border-rose-900/70 bg-rose-950/30 p-4">
                    <p className="text-xs font-semibold uppercase tracking-wider text-rose-400">
                      Call error
                    </p>

                    <p className="mt-2 text-sm leading-6 text-rose-200">
                      {latestAttempt.errorMessage}
                    </p>
                  </div>
                ) : null}
              </article>
            );
          })}
        </div>
      )}
    </section>
  );
}