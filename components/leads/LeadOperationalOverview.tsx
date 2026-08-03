import LeadAssignmentForm from "@/components/leads/LeadAssignmentForm";
import LeadStatusTransitionForm from "@/components/leads/LeadStatusTransitionForm";

import {
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  LeadOperationalContext,
} from "@/lib/leads/lead-operational-context-service";

import type {
  LeadOperationalAccess,
} from "@/types/lead-operational-access";

type LeadOperationalOverviewProps = {
  context: LeadOperationalContext;
  access: LeadOperationalAccess;
};

function formatDateTime(
  value: string | null,
): string {
  if (!value) {
    return "—";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return "—";
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

function StatusBadge({
  value,
}: {
  value: string;
}) {
  return (
    <span className="inline-flex rounded-full border border-slate-700 bg-slate-800 px-3 py-1 text-xs font-semibold text-slate-300">
      {formatOperationalLabel(value)}
    </span>
  );
}

function ActionBadge({
  label,
  allowed,
}: {
  label: string;
  allowed: boolean;
}) {
  return (
    <span
      className={
        allowed
          ? "inline-flex rounded-full border border-emerald-800 bg-emerald-950/50 px-3 py-1 text-xs font-semibold text-emerald-300"
          : "inline-flex rounded-full border border-slate-800 bg-slate-900 px-3 py-1 text-xs font-semibold text-slate-600"
      }
    >
      {label}
    </span>
  );
}

export default function LeadOperationalOverview({
  context,
  access,
}: LeadOperationalOverviewProps) {
  const {
    snapshot,
    currentAssignment,
    followUps,
    siteVisits,
    agents,
    teams,
    members,
  } = context;

  const assignedMember =
    currentAssignment
      ? members.find(
          (member) =>
            member.userId ===
            currentAssignment.assignedUserId,
        )
      : null;

  const assignedAgent =
    currentAssignment
      ? agents.find(
          (agent) =>
            agent.profileId ===
            currentAssignment.agentProfileId,
        )
      : null;

  const assignedTeam =
    currentAssignment?.teamId
      ? teams.find(
          (team) =>
            team.id ===
            currentAssignment.teamId,
        )
      : null;

  const assignedDisplayName =
    assignedMember?.displayName ??
    assignedAgent?.displayName ??
    null;

  const assignmentFormKey =
    currentAssignment?.id ??
    `unassigned-${snapshot.updatedAt}`;

  return (
    <section className="space-y-6 rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          Operational Controls
        </p>

        <h2 className="mt-3 text-2xl font-bold text-white">
          Lead execution workspace
        </h2>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Permission-aware assignment, status-transition,
          follow-up and site-visit operations for this lead.
        </p>
      </header>

      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <article className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            Lead status
          </p>

          <div className="mt-3">
            <StatusBadge
              value={snapshot.leadStatus}
            />
          </div>

          <p className="mt-3 text-sm text-slate-400">
            {formatOperationalLabel(
              snapshot.lifecycleStage,
            )}
          </p>

          <p className="mt-1 text-xs text-slate-500">
            {snapshot.leadTemperature
              ? formatOperationalLabel(
                  snapshot.leadTemperature,
                )
              : "No temperature assigned"}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            Assignment
          </p>

          <p className="mt-3 text-xl font-semibold text-white">
            {currentAssignment
              ? assignedDisplayName ??
                "Assigned agent"
              : "Unassigned"}
          </p>

          <p className="mt-2 text-sm text-slate-500">
            {currentAssignment
              ? formatOperationalLabel(
                  currentAssignment.status,
                )
              : "No active assignment"}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            Follow-ups
          </p>

          <p className="mt-3 text-3xl font-bold text-white">
            {followUps.length}
          </p>

          <p className="mt-2 text-sm text-slate-500">
            Loaded follow-up tasks
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
          <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
            Site visits
          </p>

          <p className="mt-3 text-3xl font-bold text-white">
            {siteVisits.length}
          </p>

          <p className="mt-2 text-sm text-slate-500">
            Loaded visit records
          </p>
        </article>
      </div>

      <div className="grid gap-6 xl:grid-cols-3">
        {access.canViewAssignments ? (
          <article className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
            <h3 className="text-lg font-semibold text-white">
              Current assignment
            </h3>

            {currentAssignment ? (
              <dl className="mt-5 space-y-4 text-sm">
                <div>
                  <dt className="text-slate-500">
                    Agent
                  </dt>

                  <dd className="mt-1 font-medium text-slate-200">
                    {assignedDisplayName ??
                      currentAssignment.assignedUserId}
                  </dd>
                </div>

                <div>
                  <dt className="text-slate-500">
                    Agent code
                  </dt>

                  <dd className="mt-1 font-medium text-slate-200">
                    {assignedAgent?.agentCode ?? "—"}
                  </dd>
                </div>

                <div>
                  <dt className="text-slate-500">
                    Team
                  </dt>

                  <dd className="mt-1 font-medium text-slate-200">
                    {assignedTeam?.name ?? "—"}
                  </dd>
                </div>

                <div>
                  <dt className="text-slate-500">
                    Assigned at
                  </dt>

                  <dd className="mt-1 font-medium text-slate-200">
                    {formatDateTime(
                      currentAssignment.assignedAt,
                    )}
                  </dd>
                </div>

                <div>
                  <dt className="text-slate-500">
                    Status
                  </dt>

                  <dd className="mt-2">
                    <StatusBadge
                      value={
                        currentAssignment.status
                      }
                    />
                  </dd>
                </div>
              </dl>
            ) : (
              <p className="mt-5 text-sm text-slate-500">
                No active assignment exists.
              </p>
            )}

            <div className="mt-6 flex flex-wrap gap-2">
              <ActionBadge
                label="Manual assign"
                allowed={access.canManualAssign}
              />

              <ActionBadge
                label="Reassign"
                allowed={access.canReassign}
              />

              <ActionBadge
                label="Unassign"
                allowed={access.canUnassign}
              />

              <ActionBadge
                label="Override"
                allowed={
                  access.canOverrideAssignment
                }
              />

              <ActionBadge
                label="Respond"
                allowed={
                  access.canRespondToAssignment
                }
              />

              <ActionBadge
                label="First response"
                allowed={
                  access
                    .canMarkAssignmentFirstResponse
                }
              />

              <ActionBadge
                label="Complete"
                allowed={
                  access.canCompleteAssignment
                }
              />
            </div>
          </article>
        ) : null}

        {access.canViewFollowUps ? (
          <article className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
            <div className="flex items-center justify-between gap-4">
              <h3 className="text-lg font-semibold text-white">
                Follow-ups
              </h3>

              <ActionBadge
                label="Create"
                allowed={access.canCreateFollowUp}
              />
            </div>

            {followUps.length > 0 ? (
              <div className="mt-5 space-y-3">
                {followUps
                  .slice(0, 5)
                  .map((task) => (
                    <div
                      key={task.id}
                      className="rounded-xl border border-slate-800 bg-slate-900/60 p-4"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <p className="font-medium text-slate-200">
                          {task.title}
                        </p>

                        <StatusBadge
                          value={task.status}
                        />
                      </div>
                    </div>
                  ))}
              </div>
            ) : (
              <p className="mt-5 text-sm text-slate-500">
                No follow-up task is recorded.
              </p>
            )}

            <div className="mt-6 flex flex-wrap gap-2">
              <ActionBadge
                label="Update"
                allowed={access.canUpdateFollowUp}
              />

              <ActionBadge
                label="Assign"
                allowed={access.canAssignFollowUp}
              />

              <ActionBadge
                label="Complete"
                allowed={access.canCompleteFollowUp}
              />

              <ActionBadge
                label="Delete"
                allowed={access.canDeleteFollowUp}
              />
            </div>
          </article>
        ) : null}

        {access.canViewSiteVisits ? (
          <article className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
            <div className="flex items-center justify-between gap-4">
              <h3 className="text-lg font-semibold text-white">
                Site visits
              </h3>

              <ActionBadge
                label="Create"
                allowed={access.canCreateSiteVisit}
              />
            </div>

            {siteVisits.length > 0 ? (
              <div className="mt-5 space-y-3">
                {siteVisits
                  .slice(0, 5)
                  .map((visit) => (
                    <div
                      key={visit.id}
                      className="rounded-xl border border-slate-800 bg-slate-900/60 p-4"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <p className="font-medium text-slate-200">
                          {visit.title}
                        </p>

                        <StatusBadge
                          value={visit.status}
                        />
                      </div>

                      <p className="mt-2 text-xs text-slate-500">
                        {formatDateTime(
                          visit.scheduledStartAt,
                        )}
                      </p>
                    </div>
                  ))}
              </div>
            ) : (
              <p className="mt-5 text-sm text-slate-500">
                No site visit is recorded.
              </p>
            )}

            <div className="mt-6 flex flex-wrap gap-2">
              <ActionBadge
                label="Update"
                allowed={access.canUpdateSiteVisit}
              />

              <ActionBadge
                label="Assign"
                allowed={access.canAssignSiteVisit}
              />

              <ActionBadge
                label="Check in"
                allowed={
                  access.canCheckInSiteVisit
                }
              />

              <ActionBadge
                label="Complete"
                allowed={
                  access.canCompleteSiteVisit
                }
              />

              <ActionBadge
                label="Cancel"
                allowed={
                  access.canCancelSiteVisit
                }
              />

              <ActionBadge
                label="Delete"
                allowed={
                  access.canDeleteSiteVisit
                }
              />
            </div>
          </article>
        ) : null}
      </div>

      {access.canViewAssignments &&
      (access.canManualAssign ||
        access.canUnassign) ? (
        <LeadAssignmentForm
          key={assignmentFormKey}
          leadId={snapshot.leadId}
          agents={agents}
          teams={teams}
          currentAssignment={
            currentAssignment
          }
          canManualAssign={
            access.canManualAssign
          }
          canUnassign={
            access.canUnassign
          }
          canOverrideAssignment={
            access.canOverrideAssignment
          }
        />
      ) : null}

      {access.canTransitionLeadStatus ? (
        <LeadStatusTransitionForm
          key={snapshot.updatedAt}
          snapshot={snapshot}
        />
      ) : null}
    </section>
  );
}