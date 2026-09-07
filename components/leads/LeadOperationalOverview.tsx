import AssignFollowUpForm from "@/components/leads/AssignFollowUpForm";
import CompleteFollowUpForm from "@/components/leads/CompleteFollowUpForm";
import CreateFollowUpForm from "@/components/leads/CreateFollowUpForm";
import LeadAssignmentForm from "@/components/leads/LeadAssignmentForm";
import LeadStatusTransitionForm from "@/components/leads/LeadStatusTransitionForm";
import AssignSiteVisitForm from "@/components/leads/AssignSiteVisitForm";
import CancelSiteVisitForm from "@/components/leads/CancelSiteVisitForm";
import CheckInSiteVisitForm from "@/components/leads/CheckInSiteVisitForm";
import CheckOutSiteVisitForm from "@/components/leads/CheckOutSiteVisitForm";
import CompleteSiteVisitForm from "@/components/leads/CompleteSiteVisitForm";
import CreateSiteVisitForm from "@/components/leads/CreateSiteVisitForm";
import RescheduleFollowUpForm from "@/components/leads/RescheduleFollowUpForm";

import {
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  LeadOperationalContext,
} from "@/lib/leads/lead-operational-context-service";

import CancelFollowUpForm from "@/components/leads/CancelFollowUpForm";

import DeleteFollowUpForm from "@/components/leads/DeleteFollowUpForm";

import ManageFollowUpSlaForm from "@/components/leads/ManageFollowUpSlaForm";

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
    return "Not set";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
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

function isTerminalFollowUpStatus(
  status: string,
): boolean {
  return [
    "completed",
    "cancelled",
    "failed",
  ].includes(status);
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

function isTerminalSiteVisitStatus(
  status: string,
): boolean {
  return [
    "completed",
    "cancelled",
    "no_show",
    "failed",
  ].includes(status);
}

function canCheckInSiteVisitStatus(
  status: string,
): boolean {
  return [
    "scheduled",
    "confirmed",
    "agent_en_route",
    "customer_en_route",
    "rescheduled",
    "checked_in",
    "in_progress",
  ].includes(status);
}

function canCheckOutSiteVisitStatus(
  status: string,
): boolean {
  return [
    "checked_in",
    "in_progress",
  ].includes(status);
}

function canCompleteSiteVisitStatus(
  status: string,
): boolean {
  return [
    "scheduled",
    "confirmed",
    "agent_en_route",
    "customer_en_route",
    "rescheduled",
    "checked_in",
    "in_progress",
  ].includes(status);
}

function canCancelSiteVisitStatus(
  status: string,
): boolean {
  return ![
    "completed",
    "cancelled",
    "no_show",
    "failed",
  ].includes(status);
}

function canAssignSiteVisitStatus(
  status: string,
): boolean {
  return ![
    "completed",
    "cancelled",
    "no_show",
    "failed",
  ].includes(status);
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

  const activeFollowUps =
    followUps.filter(
      (task) =>
        !isTerminalFollowUpStatus(
          task.status,
        ),
    );

  const nextFollowUp =
    activeFollowUps[0] ?? null;

  const defaultFollowUpAssignee =
    currentAssignment &&
    members.some(
      (member) =>
        member.userId ===
        currentAssignment.assignedUserId,
    )
      ? currentAssignment.assignedUserId
      : null;

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
                    {assignedAgent?.agentCode ?? "â€”"}
                  </dd>
                </div>

                <div>
                  <dt className="text-slate-500">
                    Team
                  </dt>

                  <dd className="mt-1 font-medium text-slate-200">
                    {assignedTeam?.name ?? "â€”"}
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

            <p className="mt-5 text-3xl font-bold text-white">
              {followUps.length}
            </p>

            <p className="mt-2 text-sm text-slate-500">
              {activeFollowUps.length} active task
              {activeFollowUps.length === 1
                ? ""
                : "s"}
            </p>

            <div className="mt-5 rounded-xl border border-slate-800 bg-slate-900/60 p-4">
              <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">
                Next due
              </p>

              <p className="mt-2 text-sm font-medium text-slate-200">
                {nextFollowUp
                  ? nextFollowUp.title
                  : "No active follow-up"}
              </p>

              <p className="mt-1 text-xs text-slate-500">
                {nextFollowUp
                  ? formatDateTime(
                      nextFollowUp.dueAt,
                    )
                  : "Not set"}
              </p>
            </div>

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

      {access.canViewFollowUps ? (
        <section className="space-y-6 rounded-2xl border border-slate-800 bg-slate-950/40 p-5 sm:p-6">
          <header className="flex flex-col justify-between gap-4 lg:flex-row lg:items-start">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
                Follow-up workspace
              </p>

              <h3 className="mt-3 text-xl font-semibold text-white">
                Customer action queue
              </h3>

              <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
                Create, assign, reschedule, complete and cancel lead follow-ups
                through permission-controlled server actions.
              </p>
            </div>

            <div className="flex flex-wrap gap-2">
              <ActionBadge
                label="Create"
                allowed={access.canCreateFollowUp}
              />

              <ActionBadge
                label="Assign"
                allowed={access.canAssignFollowUp}
              />

              <ActionBadge
                label="Reschedule"
                allowed={access.canUpdateFollowUp}
              />

              <ActionBadge
                label="Complete"
                allowed={access.canCompleteFollowUp}
              />

              <ActionBadge
                label="Cancel"
                allowed={access.canUpdateFollowUp}
              />

              <ActionBadge
                label="SLA"
                allowed={access.canManageFollowUpSla}
              />

              <ActionBadge
                label="Delete"
                allowed={access.canDeleteFollowUp}
              />
            </div>
          </header>

          {access.canCreateFollowUp ? (
            <CreateFollowUpForm
              key={`create-follow-up-${snapshot.updatedAt}`}
              leadId={snapshot.leadId}
              members={members}
              defaultAssignedTo={
                defaultFollowUpAssignee
              }
            />
          ) : null}

          {followUps.length > 0 ? (
            <div className="space-y-5">
              {followUps.map((task) => {
                const taskAssignedMember =
                  task.assignedTo
                    ? members.find(
                        (member) =>
                          member.userId ===
                          task.assignedTo,
                      ) ?? null
                    : null;

                const terminalTask =
                  isTerminalFollowUpStatus(
                    task.status,
                  );

                return (
                  <article
                    key={task.id}
                    className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5"
                  >
                    <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <StatusBadge
                            value={task.status}
                          />

                          <span className="inline-flex rounded-full border border-slate-800 bg-slate-950 px-3 py-1 text-xs font-semibold text-slate-400">
                            {formatOperationalLabel(
                              task.priority,
                            )}
                          </span>
                        </div>

                        <h4 className="mt-3 text-lg font-semibold text-white">
                          {task.title}
                        </h4>

                        {task.description ? (
                          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
                            {task.description}
                          </p>
                        ) : null}
                      </div>

                      <p className="text-xs leading-5 text-slate-500">
                        Updated{" "}
                        {formatDateTime(
                          task.updatedAt,
                        )}
                      </p>
                    </div>

                    <dl className="mt-5 grid gap-4 rounded-xl border border-slate-800 bg-slate-950/50 p-4 text-sm sm:grid-cols-2 xl:grid-cols-5">
                      <div>
                        <dt className="text-xs uppercase tracking-wider text-slate-500">
                          Type
                        </dt>

                        <dd className="mt-1 font-medium text-slate-200">
                          {formatOperationalLabel(
                            task.followUpType,
                          )}
                        </dd>
                      </div>

                      <div>
                        <dt className="text-xs uppercase tracking-wider text-slate-500">
                          Due
                        </dt>

                        <dd className="mt-1 font-medium text-slate-200">
                          {formatDateTime(
                            task.dueAt,
                          )}
                        </dd>
                      </div>

                      <div>
                        <dt className="text-xs uppercase tracking-wider text-slate-500">
                          Reminder
                        </dt>

                        <dd className="mt-1 font-medium text-slate-200">
                          {formatDateTime(
                            task.reminderAt,
                          )}
                        </dd>
                      </div>

                      <div>
                        <dt className="text-xs uppercase tracking-wider text-slate-500">
                          Assigned to
                        </dt>

                        <dd className="mt-1 font-medium text-slate-200">
                          {taskAssignedMember
                            ?.displayName ??
                            task.assignedTo ??
                            "Unassigned"}
                        </dd>
                      </div>

                      <div>
                        <dt className="text-xs uppercase tracking-wider text-slate-500">
                          Escalation
                        </dt>

                        <dd className="mt-1 font-medium text-slate-200">
                          Level{" "}
                          {task.escalationLevel}
                        </dd>
                      </div>
                    </dl>

                    <div className="mt-4 grid gap-4 rounded-xl border border-violet-900/50 bg-violet-950/20 p-4 text-sm sm:grid-cols-2">
  <div>
    <p className="text-xs uppercase tracking-wider text-slate-500">
      SLA status
    </p>

    <p className="mt-1 font-medium text-violet-200">
      {formatOperationalLabel(
        task.slaStatus,
      )}
    </p>
  </div>

  <div>
    <p className="text-xs uppercase tracking-wider text-slate-500">
      SLA deadline
    </p>

    <p className="mt-1 font-medium text-slate-200">
      {formatDateTime(
        task.slaDueAt,
      )}
    </p>
  </div>
</div>

                    {task.completionOutcome ? (
                      <div className="mt-4 rounded-xl border border-emerald-900/60 bg-emerald-950/20 p-4">
                        <p className="text-xs font-semibold uppercase tracking-wider text-emerald-400">
                          Completion outcome
                        </p>

                        <p className="mt-2 text-sm font-medium text-emerald-100">
                          {task.completionOutcome}
                        </p>

                        {task.completionNotes ? (
                          <p className="mt-2 text-sm leading-6 text-slate-400">
                            {task.completionNotes}
                          </p>
                        ) : null}
                      </div>
                    ) : null}

                    {!terminalTask &&
                    (access.canAssignFollowUp ||
                      access.canUpdateFollowUp ||
                        access.canCompleteFollowUp) ? (
                      <div className="mt-5 grid gap-4 xl:grid-cols-3">
                        {access.canAssignFollowUp ? (
                          <AssignFollowUpForm
                            key={`assign-${task.id}-${task.updatedAt}`}
                            task={task}
                            members={members}
                          />
                        ) : null}

                        {access.canUpdateFollowUp ? (
                            <RescheduleFollowUpForm
                              key={`reschedule-${task.id}-${task.updatedAt}`}
                              task={task}
                            />
                          ) : null}

                        {access.canCompleteFollowUp ? (
                          <CompleteFollowUpForm
                            key={`complete-${task.id}-${task.updatedAt}`}
                            task={task}
                          />
                        ) : null}

                          {access.canUpdateFollowUp ? (
                            <div className="xl:col-span-3">
                              <CancelFollowUpForm
                                key={`cancel-${task.id}-${task.updatedAt}`}
                                task={task}
                              />
                            </div>
                          ) : null}
                      </div>
                    ) : null}

                    {access.canManageFollowUpSla &&
                      !terminalTask ? (
                        <div className="mt-5">
                          <ManageFollowUpSlaForm
                            key={`sla-${task.id}-${task.updatedAt}`}
                            task={task}
                          />
                        </div>
                    ) : null}

                    {access.canDeleteFollowUp ? (
                      <div className="mt-5">
                        <DeleteFollowUpForm
                          key={`delete-${task.id}-${task.updatedAt}`}
                          task={task}
                        />
                      </div>
                    ) : null}
                  </article>
                );
              })}
            </div>
          ) : (
            <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 p-8 text-center">
              <p className="text-sm font-medium text-slate-300">
                No follow-up task is recorded.
              </p>

              <p className="mt-2 text-xs leading-5 text-slate-500">
                Create the first task to establish the lead&apos;s next
                customer action.
              </p>
            </div>
          )}
        </section>
      ) : null}

        {access.canViewSiteVisits ? (
    <section className="space-y-6 rounded-2xl border border-slate-800 bg-slate-950/40 p-5 sm:p-6">
      <header className="flex flex-col justify-between gap-4 lg:flex-row lg:items-start">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
            Site visit workspace
          </p>

          <h3 className="mt-3 text-xl font-semibold text-white">
            Customer visit execution
          </h3>

          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
            Schedule, assign, check in, check out, complete and cancel
            customer site visits from one operational workspace.
          </p>
        </div>

        <div className="flex flex-wrap gap-2">
          <ActionBadge
            label="Create"
            allowed={
              access.canCreateSiteVisit
            }
          />

          <ActionBadge
            label="Assign"
            allowed={
              access.canAssignSiteVisit
            }
          />

          <ActionBadge
            label="Check in"
            allowed={
              access.canCheckInSiteVisit
            }
          />

              <ActionBadge
                label="Check out"
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
        </div>
      </header>

      {access.canCreateSiteVisit ? (
        <CreateSiteVisitForm
          key={`create-site-visit-${snapshot.updatedAt}`}
          leadId={snapshot.leadId}
          members={members}
        />
      ) : null}
            {siteVisits.length > 0 ? (
        <div className="space-y-5">
          {siteVisits.map((visit) => {
            const assignedVisitMember =
              visit.assignedAgentId
                ? members.find(
                    (member) =>
                      member.userId ===
                      visit.assignedAgentId,
                  ) ?? null
                : null;

            const coordinatorMember =
              visit.coordinatorId
                ? members.find(
                    (member) =>
                      member.userId ===
                      visit.coordinatorId,
                  ) ?? null
                : null;

            const terminalVisit =
              isTerminalSiteVisitStatus(
                visit.status,
              );

            const canAssignVisit =
              access.canAssignSiteVisit &&
              canAssignSiteVisitStatus(
                visit.status,
              );

            const canCheckInVisit =
              access.canCheckInSiteVisit &&
              canCheckInSiteVisitStatus(
                visit.status,
              );

            const canCheckOutVisit =
              access.canCheckInSiteVisit &&
              canCheckOutSiteVisitStatus(
                visit.status,
              );

            const canCompleteVisit =
              access.canCompleteSiteVisit &&
              canCompleteSiteVisitStatus(
                visit.status,
              );

            const canCancelVisit =
              access.canCancelSiteVisit &&
              canCancelSiteVisitStatus(
                visit.status,
              );

            return (
              <article
                key={visit.id}
                className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5"
              >
                <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
                  <div>
                    <div className="flex flex-wrap items-center gap-2">
                      <StatusBadge
                        value={visit.status}
                      />

                      <span className="inline-flex rounded-full border border-slate-800 bg-slate-950 px-3 py-1 text-xs font-semibold text-slate-400">
                        {formatOperationalLabel(
                          visit.priority,
                        )}
                      </span>

                      {terminalVisit ? (
                        <span className="inline-flex rounded-full border border-slate-700 bg-slate-950 px-3 py-1 text-xs font-semibold text-slate-500">
                          Closed state
                        </span>
                      ) : null}
                    </div>

                    <h4 className="mt-3 text-lg font-semibold text-white">
                      {visit.title}
                    </h4>

                    {visit.description ? (
                      <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
                        {visit.description}
                      </p>
                    ) : null}
                  </div>

                  <p className="text-xs leading-5 text-slate-500">
                    Updated{" "}
                    {formatDateTime(
                      visit.updatedAt,
                    )}
                  </p>
                </div>

                <dl className="mt-5 grid gap-4 rounded-xl border border-slate-800 bg-slate-950/50 p-4 text-sm sm:grid-cols-2 xl:grid-cols-5">
                  <div>
                    <dt className="text-xs uppercase tracking-wider text-slate-500">
                      Type
                    </dt>

                    <dd className="mt-1 font-medium text-slate-200">
                      {formatOperationalLabel(
                        visit.visitType,
                      )}
                    </dd>
                  </div>

                  <div>
                    <dt className="text-xs uppercase tracking-wider text-slate-500">
                      Scheduled
                    </dt>

                    <dd className="mt-1 font-medium text-slate-200">
                      {formatDateTime(
                        visit.scheduledStartAt,
                      )}
                    </dd>
                  </div>

                  <div>
                    <dt className="text-xs uppercase tracking-wider text-slate-500">
                      Project
                    </dt>

                    <dd className="mt-1 font-medium text-slate-200">
                      {visit.projectName}
                    </dd>
                  </div>

                  <div>
                    <dt className="text-xs uppercase tracking-wider text-slate-500">
                      Agent
                    </dt>

                    <dd className="mt-1 font-medium text-slate-200">
                      {assignedVisitMember
                        ?.displayName ??
                        visit.assignedAgentId ??
                        "Unassigned"}
                    </dd>
                  </div>

                  <div>
                    <dt className="text-xs uppercase tracking-wider text-slate-500">
                      Coordinator
                    </dt>

                    <dd className="mt-1 font-medium text-slate-200">
                      {coordinatorMember
                        ?.displayName ??
                        visit.coordinatorId ??
                        "Not assigned"}
                    </dd>
                  </div>
                </dl>
                            {canAssignVisit ||
            canCheckInVisit ||
            canCheckOutVisit ||
            canCompleteVisit ||
            canCancelVisit ? (
              <div className="mt-5 grid gap-4 xl:grid-cols-2">
                {canAssignVisit ? (
                  <AssignSiteVisitForm
                    key={`assign-site-visit-${visit.id}-${visit.updatedAt}`}
                    visit={visit}
                    members={members}
                  />
                ) : null}

                {canCheckInVisit ? (
                  <CheckInSiteVisitForm
                    key={`check-in-site-visit-${visit.id}-${visit.updatedAt}`}
                    visit={visit}
                  />
                ) : null}

                {canCheckOutVisit ? (
                  <CheckOutSiteVisitForm
                    key={`check-out-site-visit-${visit.id}-${visit.updatedAt}`}
                    visit={visit}
                  />
                ) : null}

                {canCompleteVisit ? (
                  <CompleteSiteVisitForm
                    key={`complete-site-visit-${visit.id}-${visit.updatedAt}`}
                    visit={visit}
                  />
                ) : null}

                {canCancelVisit ? (
                  <CancelSiteVisitForm
                    key={`cancel-site-visit-${visit.id}-${visit.updatedAt}`}
                    visit={visit}
                  />
                ) : null}
              </div>
            ) : null}
              </article>
            );
          })}
        </div>
      ) : (
        <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 p-8 text-center">
          <p className="text-sm font-medium text-slate-300">
            No site visit is recorded.
          </p>

          <p className="mt-2 text-xs leading-5 text-slate-500">
            Create the first visit to start the customer visit lifecycle.
          </p>
        </div>
      )}
    </section>
  ) : null}

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