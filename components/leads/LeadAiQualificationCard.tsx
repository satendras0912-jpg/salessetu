import type {
  LeadAiQualification,
} from "@/lib/ai-calling/qualification-display-service";

type LeadAiQualificationCardProps = {
  qualification: LeadAiQualification | null;
};

function formatLabel(
  value: string,
): string {
  return value
    .replaceAll("_", " ")
    .replace(
      /\b\w/g,
      (character) =>
        character.toUpperCase(),
    );
}

function formatDateTime(
  value: string | null,
): string {
  if (!value) {
    return "Not set";
  }

  const date =
    new Date(value);

  if (
    Number.isNaN(
      date.getTime(),
    )
  ) {
    return "Not set";
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

function formatValue(
  value: unknown,
): string {
  if (
    value === null ||
    value === undefined ||
    value === ""
  ) {
    return "Not captured";
  }

  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return String(value);
  }

  if (Array.isArray(value)) {
    if (value.length === 0) {
      return "None";
    }

    return value
      .map(formatValue)
      .join(", ");
  }

  try {
    return JSON.stringify(
      value,
    );
  } catch {
    return "Unavailable";
  }
}

function getStatusClasses(
  status: string,
): string {
  switch (status) {
    case "qualified_hot":
      return "border-rose-700 bg-rose-950/60 text-rose-300";

    case "qualified_warm":
      return "border-amber-700 bg-amber-950/60 text-amber-300";

    case "qualified_cold":
      return "border-cyan-700 bg-cyan-950/60 text-cyan-300";

    case "unqualified":
    case "failed":
      return "border-red-800 bg-red-950/60 text-red-300";

    case "manual_review":
      return "border-violet-700 bg-violet-950/60 text-violet-300";

    default:
      return "border-slate-700 bg-slate-800 text-slate-300";
  }
}

function Metric({
  label,
  value,
}: {
  label: string;
  value: string;
}) {
  return (
    <div className="rounded-2xl border border-slate-800 bg-slate-950/60 p-4">
      <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
        {label}
      </p>

      <p className="mt-2 text-xl font-bold text-white">
        {value}
      </p>
    </div>
  );
}

export default function LeadAiQualificationCard({
  qualification,
}: LeadAiQualificationCardProps) {
  if (!qualification) {
    return (
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          AI Qualification
        </p>

        <h2 className="mt-3 text-2xl font-bold text-white">
          No qualification result yet
        </h2>

        <p className="mt-2 text-sm leading-6 text-slate-400">
          The latest completed AI call qualification
          will appear here after its verified webhook
          is processed.
        </p>
      </section>
    );
  }

  const scoreLabel =
    qualification.maximumScore > 0
      ? `${qualification.totalScore} / ${qualification.maximumScore}`
      : String(
          qualification.totalScore,
        );

  return (
    <section className="space-y-6 rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <header className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            AI Qualification
          </p>

          <h2 className="mt-3 text-2xl font-bold text-white">
            Latest calling assessment
          </h2>

          <p className="mt-2 text-sm text-slate-400">
            Processed{" "}
            {formatDateTime(
              qualification.createdAt,
            )}
          </p>
        </div>

        <span
          className={`inline-flex w-fit rounded-full border px-4 py-2 text-sm font-semibold ${getStatusClasses(
            qualification.status,
          )}`}
        >
          {formatLabel(
            qualification.status,
          )}
        </span>
      </header>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Metric
          label="Score"
          value={scoreLabel}
        />

        <Metric
          label="Normalized"
          value={`${qualification.normalizedScore}%`}
        />

        <Metric
          label="Valid answers"
          value={String(
            qualification.validAnswerCount,
          )}
        />

        <Metric
          label="Required answers"
          value={String(
            qualification.requiredAnswerCount,
          )}
        />
      </div>

      {qualification.qualificationSummary ? (
        <div className="rounded-2xl border border-cyan-900/70 bg-cyan-950/20 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-cyan-400">
            AI summary
          </p>

          <p className="mt-3 text-sm leading-6 text-slate-200">
            {
              qualification.qualificationSummary
            }
          </p>
        </div>
      ) : null}

      {qualification.recommendedAction ? (
        <div>
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            Recommended action
          </p>

          <p className="mt-2 text-sm leading-6 text-slate-200">
            {
              qualification.recommendedAction
            }
          </p>

          {qualification.recommendedFollowupAt ? (
            <p className="mt-2 text-xs text-slate-500">
              Follow-up:{" "}
              {formatDateTime(
                qualification.recommendedFollowupAt,
              )}
            </p>
          ) : null}
        </div>
      ) : null}

      {qualification.missingRequiredQuestions.length > 0 ? (
        <div className="rounded-2xl border border-amber-900/70 bg-amber-950/20 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-amber-400">
            Missing required answers
          </p>

          <p className="mt-3 text-sm text-amber-100">
            {formatValue(
              qualification.missingRequiredQuestions,
            )}
          </p>
        </div>
      ) : null}

      {qualification.disqualifyingReasons.length > 0 ? (
        <div className="rounded-2xl border border-red-900/70 bg-red-950/20 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-red-400">
            Disqualifying reasons
          </p>

          <p className="mt-3 text-sm text-red-100">
            {formatValue(
              qualification.disqualifyingReasons,
            )}
          </p>
        </div>
      ) : null}

      <div>
        <h3 className="text-lg font-semibold text-white">
          Extracted answers
        </h3>

        {qualification.answers.length === 0 ? (
          <p className="mt-3 text-sm text-slate-500">
            No structured answers were captured.
          </p>
        ) : (
          <div className="mt-4 divide-y divide-slate-800 overflow-hidden rounded-2xl border border-slate-800">
            {qualification.answers.map(
              (answer) => (
                <div
                  key={answer.id}
                  className="grid gap-3 bg-slate-950/40 p-5 sm:grid-cols-[1fr_auto]"
                >
                  <div>
                    <p className="text-sm font-semibold text-slate-200">
                      {answer.questionText}
                    </p>

                    <p className="mt-2 text-sm leading-6 text-slate-400">
                      {answer.rawAnswer ??
                        formatValue(
                          answer.normalizedAnswer,
                        )}
                    </p>

                    {answer.confidence !== null ? (
                      <p className="mt-2 text-xs text-slate-600">
                        Confidence:{" "}
                        {Math.round(
                          answer.confidence *
                            100,
                        )}
                        %
                      </p>
                    ) : null}
                  </div>

                  <div className="flex items-start gap-2">
                    <span
                      className={
                        answer.isValid === false
                          ? "rounded-full border border-red-800 bg-red-950/50 px-3 py-1 text-xs font-semibold text-red-300"
                          : "rounded-full border border-emerald-800 bg-emerald-950/50 px-3 py-1 text-xs font-semibold text-emerald-300"
                      }
                    >
                      {answer.isValid === false
                        ? "Invalid"
                        : "Valid"}
                    </span>

                    <span className="rounded-full border border-slate-700 bg-slate-800 px-3 py-1 text-xs font-semibold text-slate-300">
                      {answer.awardedScore} /{" "}
                      {answer.maximumScore}
                    </span>
                  </div>
                </div>
              ),
            )}
          </div>
        )}
      </div>
    </section>
  );
}