"use client";

import {
  useActionState,
} from "react";

import {
  escalateFollowUpAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
} from "@/lib/leads/lead-operational-contract";

import type {
  FollowUpTaskSummary,
  OperationalActionState,
  OrganizationMemberOption,
} from "@/types/lead-operational-controls";

type EscalateFollowUpFormProps = {
  task: FollowUpTaskSummary;
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
    <div className="mt-2 space-y-1">
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

export default function EscalateFollowUpForm({
  task,
  members,
}: EscalateFollowUpFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    escalateFollowUpAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-orange-900/60 bg-orange-950/20 p-4"
    >
      <input
        type="hidden"
        name="taskId"
        value={task.id}
      />

      <input
        type="hidden"
        name="expectedUpdatedAt"
        value={task.updatedAt}
      />

      <div>
        <p className="text-xs font-semibold uppercase tracking-wider text-orange-400">
          Escalation
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Escalate this active follow-up to an organisation member and record the reason.
        </p>

        <p className="mt-2 text-xs font-medium text-orange-200">
          Current level{" "}
          {task.escalationLevel}
          {" → "}
          next level{" "}
          {task.escalationLevel + 1}
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`followUpEscalatedTo-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Escalate to
        </label>

        <select
          id={`followUpEscalatedTo-${task.id}`}
          name="escalatedTo"
          required
          defaultValue={
            task.escalatedTo ?? ""
          }
          disabled={
            isPending ||
            members.length === 0
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-orange-500 disabled:cursor-not-allowed disabled:opacity-60"
        >
          <option value="">
            Select a member
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

        {members.length === 0 ? (
          <p className="mt-2 text-xs leading-5 text-amber-300">
            No organisation member is available for escalation.
          </p>
        ) : null}

        <FieldError
          state={state}
          fieldName="escalatedTo"
        />
      </div>

      <div>
        <label
          htmlFor={`followUpEscalationReason-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Escalation reason
        </label>

        <textarea
          id={`followUpEscalationReason-${task.id}`}
          name="reason"
          rows={3}
          required
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .reason
          }
          placeholder="Explain why this follow-up requires escalation."
          disabled={isPending}
          className="w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-orange-500 disabled:cursor-not-allowed disabled:opacity-60"
        />

        <FieldError
          state={state}
          fieldName="reason"
        />
      </div>

      <button
        type="submit"
        disabled={
          isPending ||
          members.length === 0
        }
        className="inline-flex w-full items-center justify-center rounded-xl border border-orange-700 bg-orange-950/60 px-4 py-3 text-sm font-semibold text-orange-200 transition hover:bg-orange-900/60 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Escalating..."
          : "Escalate follow-up"}
      </button>
    </form>
  );
}