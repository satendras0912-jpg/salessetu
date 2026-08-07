"use client";

import {
  useActionState,
} from "react";

import {
  assignFollowUpAction,
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

type AssignFollowUpFormProps = {
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

export default function AssignFollowUpForm({
  task,
  members,
}: AssignFollowUpFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    assignFollowUpAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  return (
    <form
      action={formAction}
      className="space-y-4 rounded-xl border border-slate-800 bg-slate-950/60 p-4"
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
        <p className="text-xs font-semibold uppercase tracking-wider text-cyan-400">
          Assignment
        </p>

        <p className="mt-1 text-xs leading-5 text-slate-500">
          Reassign this follow-up to an active organisation member.
        </p>
      </div>

      <ActionMessage state={state} />

      <div>
        <label
          htmlFor={`followUpAssignee-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Assigned member
        </label>

        <select
          id={`followUpAssignee-${task.id}`}
          name="assignedTo"
          required
          defaultValue={
            task.assignedTo ?? ""
          }
          disabled={
            isPending ||
            members.length === 0
          }
          className="w-full rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 disabled:cursor-not-allowed disabled:opacity-60"
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
            No organisation member is available for assignment.
          </p>
        ) : null}

        <FieldError
          state={state}
          fieldName="assignedTo"
        />
      </div>

      <div>
        <label
          htmlFor={`followUpAssignmentReason-${task.id}`}
          className="mb-2 block text-xs font-medium text-slate-300"
        >
          Assignment reason
        </label>

        <textarea
          id={`followUpAssignmentReason-${task.id}`}
          name="reason"
          rows={3}
          required
          maxLength={
            OPERATIONAL_FORM_LIMITS
              .reason
          }
          defaultValue="Manual follow-up assignment"
          disabled={isPending}
          className="w-full resize-y rounded-xl border border-slate-700 bg-slate-900 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 disabled:cursor-not-allowed disabled:opacity-60"
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
        className="inline-flex w-full items-center justify-center rounded-xl border border-cyan-700 bg-cyan-950/60 px-4 py-3 text-sm font-semibold text-cyan-200 transition hover:bg-cyan-900/60 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isPending
          ? "Assigning..."
          : "Save assignment"}
      </button>
    </form>
  );
}
