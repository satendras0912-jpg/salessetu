"use client";

import {
  useActionState,
} from "react";

import {
  manualAssignLeadAction,
  manualUnassignLeadAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  OPERATIONAL_FORM_LIMITS,
} from "@/lib/leads/lead-operational-contract";

import type {
  AssignmentAgentOption,
  AssignmentTeamOption,
  LeadAssignmentSummary,
  OperationalActionState,
} from "@/types/lead-operational-controls";

type LeadAssignmentFormProps = {
  leadId: string;

  agents: AssignmentAgentOption[];
  teams: AssignmentTeamOption[];

  currentAssignment:
    | LeadAssignmentSummary
    | null;

  canManualAssign: boolean;
  canUnassign: boolean;
  canOverrideAssignment: boolean;
};

const INITIAL_ACTION_STATE:
  OperationalActionState = {
    status: "idle",
    message: "",
    fieldErrors: {},
  };

function FieldError({
  state,
  fieldName,
}: {
  state: OperationalActionState;
  fieldName: string;
}) {
  const messages =
    state.fieldErrors[fieldName] ?? [];

  if (messages.length === 0) {
    return null;
  }

  return (
    <div className="mt-2 space-y-1">
      {messages.map(
        (message) => (
          <p
            key={message}
            className="text-sm text-rose-400"
          >
            {message}
          </p>
        ),
      )}
    </div>
  );
}

function ActionMessage({
  state,
}: {
  state: OperationalActionState;
}) {
  if (
    !state.message ||
    state.status === "idle"
  ) {
    return null;
  }

  const className =
    state.status === "conflict"
      ? "border-amber-700/70 bg-amber-950/40 text-amber-200"
      : "border-rose-800/70 bg-rose-950/40 text-rose-200";

  return (
    <div
      className={`rounded-xl border px-4 py-3 text-sm ${className}`}
      role="alert"
    >
      {state.message}
    </div>
  );
}

function formatAgentLabel(
  agent: AssignmentAgentOption,
): string {
  const code = agent.agentCode
    ? ` · ${agent.agentCode}`
    : "";

  return `${agent.displayName}${code}`;
}

function formatTeamLabel(
  team: AssignmentTeamOption,
): string {
  return `${team.name} · ${team.code}`;
}

export default function LeadAssignmentForm({
  leadId,
  agents,
  teams,
  currentAssignment,
  canManualAssign,
  canUnassign,
  canOverrideAssignment,
}: LeadAssignmentFormProps) {
  const [
    assignmentState,
    assignmentAction,
    assignmentPending,
  ] = useActionState(
    manualAssignLeadAction,
    INITIAL_ACTION_STATE,
  );

  const [
    unassignmentState,
    unassignmentAction,
    unassignmentPending,
  ] = useActionState(
    manualUnassignLeadAction,
    INITIAL_ACTION_STATE,
  );

  const availableAgents =
    agents.filter(
      (agent) =>
        agent.status === "active" &&
        agent.availabilityStatus ===
          "available" &&
        agent.acceptNewLeads,
    );

  const activeTeams =
    teams.filter(
      (team) =>
        team.status === "active",
    );

  if (
    !currentAssignment &&
    !canManualAssign
  ) {
    return null;
  }

  if (
    currentAssignment &&
    !canUnassign
  ) {
    return null;
  }

  if (!currentAssignment) {
    return (
      <article className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5">
        <header>
          <h3 className="text-lg font-semibold text-white">
            Assign lead
          </h3>

          <p className="mt-2 text-sm leading-6 text-slate-400">
            Select an available agent and,
            optionally, the responsible sales
            team.
          </p>
        </header>

        <form
          action={assignmentAction}
          className="mt-6 space-y-5"
        >
          <input
            type="hidden"
            name="leadId"
            value={leadId}
          />

          <div>
            <label
              htmlFor="agentProfileId"
              className="text-sm font-medium text-slate-300"
            >
              Agent
            </label>

            <select
              id="agentProfileId"
              name="agentProfileId"
              defaultValue=""
              disabled={
                assignmentPending ||
                availableAgents.length === 0
              }
              className="mt-2 w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 disabled:cursor-not-allowed disabled:opacity-60"
            >
              <option value="">
                Select an agent
              </option>

              {availableAgents.map(
                (agent) => (
                  <option
                    key={agent.profileId}
                    value={agent.profileId}
                  >
                    {formatAgentLabel(
                      agent,
                    )}
                  </option>
                ),
              )}
            </select>

            {availableAgents.length ===
            0 ? (
              <p className="mt-2 text-sm text-amber-300">
                No active and available agent
                is currently accepting new
                leads.
              </p>
            ) : null}

            <FieldError
              state={assignmentState}
              fieldName="agentProfileId"
            />
          </div>

          <div>
            <label
              htmlFor="teamId"
              className="text-sm font-medium text-slate-300"
            >
              Team
            </label>

            <select
              id="teamId"
              name="teamId"
              defaultValue=""
              disabled={assignmentPending}
              className="mt-2 w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 disabled:cursor-not-allowed disabled:opacity-60"
            >
              <option value="">
                No specific team
              </option>

              {activeTeams.map(
                (team) => (
                  <option
                    key={team.id}
                    value={team.id}
                  >
                    {formatTeamLabel(
                      team,
                    )}
                  </option>
                ),
              )}
            </select>

            <FieldError
              state={assignmentState}
              fieldName="teamId"
            />
          </div>

          <div>
            <label
              htmlFor="assignmentReason"
              className="text-sm font-medium text-slate-300"
            >
              Assignment reason
            </label>

            <textarea
              id="assignmentReason"
              name="reason"
              rows={3}
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .reason
              }
              defaultValue="Manual lead assignment"
              disabled={assignmentPending}
              className="mt-2 w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 disabled:cursor-not-allowed disabled:opacity-60"
            />

            <FieldError
              state={assignmentState}
              fieldName="reason"
            />
          </div>

          {canOverrideAssignment ? (
            <label className="flex items-start gap-3 rounded-xl border border-slate-800 bg-slate-900/70 p-4">
              <input
                type="checkbox"
                name="overrideCapacity"
                value="true"
                disabled={assignmentPending}
                className="mt-1 h-4 w-4 rounded border-slate-600 bg-slate-900"
              />

              <span>
                <span className="block text-sm font-medium text-slate-200">
                  Override agent capacity
                </span>

                <span className="mt-1 block text-xs leading-5 text-slate-500">
                  Use only when an authorised
                  administrator must bypass
                  assignment capacity limits.
                </span>
              </span>
            </label>
          ) : null}

          <ActionMessage
            state={assignmentState}
          />

          <button
            type="submit"
            disabled={
              assignmentPending ||
              availableAgents.length === 0
            }
            className="inline-flex min-h-11 items-center justify-center rounded-xl bg-cyan-500 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-400 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {assignmentPending
              ? "Assigning..."
              : "Assign lead"}
          </button>
        </form>
      </article>
    );
  }

  return (
    <article className="rounded-2xl border border-rose-900/60 bg-rose-950/20 p-5">
      <header>
        <h3 className="text-lg font-semibold text-white">
          Remove assignment
        </h3>

        <p className="mt-2 text-sm leading-6 text-slate-400">
          This will close the active assignment
          and return the lead to the unassigned
          queue.
        </p>
      </header>

      <form
        action={unassignmentAction}
        className="mt-6 space-y-5"
      >
        <input
          type="hidden"
          name="leadId"
          value={leadId}
        />

        <div>
          <label
            htmlFor="unassignmentReason"
            className="text-sm font-medium text-slate-300"
          >
            Unassignment reason
          </label>

          <textarea
            id="unassignmentReason"
            name="reason"
            rows={3}
            maxLength={
              OPERATIONAL_FORM_LIMITS.reason
            }
            defaultValue="Manual lead unassignment"
            disabled={unassignmentPending}
            className="mt-2 w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-rose-500 disabled:cursor-not-allowed disabled:opacity-60"
          />

          <FieldError
            state={unassignmentState}
            fieldName="reason"
          />
        </div>

        <ActionMessage
          state={unassignmentState}
        />

        <button
          type="submit"
          disabled={unassignmentPending}
          className="inline-flex min-h-11 items-center justify-center rounded-xl border border-rose-700 bg-rose-950/60 px-5 py-3 text-sm font-semibold text-rose-200 transition hover:bg-rose-900/60 disabled:cursor-not-allowed disabled:opacity-60"
        >
          {unassignmentPending
            ? "Removing..."
            : "Remove assignment"}
        </button>
      </form>
    </article>
  );
}