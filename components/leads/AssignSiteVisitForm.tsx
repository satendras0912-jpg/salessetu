"use client";

import {
  useActionState,
} from "react";

import {
  assignSiteVisitAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
} from "@/lib/leads/lead-operational-contract";

import type {
  OperationalActionState,
  OrganizationMemberOption,
  SiteVisitSummary,
} from "@/types/lead-operational-controls";

type AssignSiteVisitFormProps = {
  visit: SiteVisitSummary;
  members: OrganizationMemberOption[];
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
    <div
      id={`${fieldName}-error`}
      className="mt-2 space-y-1"
    >
      {messages.map((message) => (
        <p
          key={message}
          className="text-xs leading-5 text-red-300"
        >
          {message}
        </p>
      ))}
    </div>
  );
}

function ActionMessage({
  state,
}: {
  state: OperationalActionState;
}) {
  if (
    state.status === "idle" ||
    !state.message
  ) {
    return null;
  }

  const className =
    state.status === "conflict"
      ? "border-amber-500/40 bg-amber-500/10 text-amber-200"
      : "border-red-500/40 bg-red-500/10 text-red-200";

  return (
    <div
      aria-live="polite"
      className={`rounded-xl border px-4 py-3 text-xs leading-5 ${className}`}
    >
      {state.message}
    </div>
  );
}

function formatMemberLabel(
  member: OrganizationMemberOption,
): string {
  return (
    member.displayName?.trim() ||
    member.userId
  );
}

export default function AssignSiteVisitForm({
  visit,
  members,
}: AssignSiteVisitFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    assignSiteVisitAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-slate-800 bg-slate-950/60 p-4"
    >
      <input
        type="hidden"
        name="siteVisitId"
        value={visit.id}
      />

      <input
        type="hidden"
        name="expectedUpdatedAt"
        value={visit.updatedAt}
      />

      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-cyan-400">
          Assignment
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Assign the visit agent and optional coordinator.
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`siteVisitAgent-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Assigned agent
        </label>

        <select
          id={`siteVisitAgent-${visit.id}`}
          name="assignedAgentId"
          defaultValue={
            visit.assignedAgentId ?? ""
          }
          disabled={
            isPending ||
            members.length === 0
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 disabled:cursor-not-allowed disabled:opacity-60"
        >
          <option value="">
            Leave agent unassigned
          </option>

          {members.map((member) => (
            <option
              key={member.userId}
              value={member.userId}
            >
              {formatMemberLabel(
                member,
              )}
            </option>
          ))}
        </select>

        <FieldError
          state={state}
          fieldName="assignedAgentId"
        />
      </div>

      <div>
        <label
          htmlFor={`siteVisitCoordinator-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Coordinator
        </label>

        <select
          id={`siteVisitCoordinator-${visit.id}`}
          name="coordinatorId"
          defaultValue={
            visit.coordinatorId ?? ""
          }
          disabled={
            isPending ||
            members.length === 0
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 disabled:cursor-not-allowed disabled:opacity-60"
        >
          <option value="">
            No coordinator
          </option>

          {members.map((member) => (
            <option
              key={member.userId}
              value={member.userId}
            >
              {formatMemberLabel(
                member,
              )}
            </option>
          ))}
        </select>

        <FieldError
          state={state}
          fieldName="coordinatorId"
        />
      </div>

      <div>
        <label
          htmlFor={`siteVisitAssignmentReason-${visit.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Assignment reason
        </label>

        <textarea
          id={`siteVisitAssignmentReason-${visit.id}`}
          name="reason"
          rows={3}
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .reason
          }
          defaultValue="Manual site visit assignment"
          disabled={isPending}
          className="w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="reason"
        />
      </div>

      {members.length === 0 ? (
        <p className="text-xs leading-5 text-amber-300">
          No organisation member is available for assignment.
        </p>
      ) : null}

      <button
        type="submit"
        disabled={
          isPending ||
          members.length === 0
        }
        className="inline-flex w-full items-center justify-center rounded-xl border border-cyan-700 bg-cyan-950/60 px-4 py-3 text-sm font-semibold text-cyan-200 transition hover:bg-cyan-900/60 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Assigning..."
          : "Save assignment"}
      </button>
    </form>
  );
}