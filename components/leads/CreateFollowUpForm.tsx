"use client";

import {
  useActionState,
  useState,
} from "react";

import {
  createFollowUpAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  FOLLOW_UP_TYPES,
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
  OPERATIONAL_PRIORITIES,
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  OperationalActionState,
  OrganizationMemberOption,
} from "@/types/lead-operational-controls";

type CreateFollowUpFormProps = {
  leadId: string;
  members: OrganizationMemberOption[];
  defaultAssignedTo?: string | null;
};

const INPUT_CLASS =
  "w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20 disabled:cursor-not-allowed disabled:opacity-60";

const ERROR_INPUT_CLASS =
  "border-red-500 focus:border-red-400 focus:ring-red-500/20";

function getInputClass(
  hasError: boolean,
): string {
  return [
    INPUT_CLASS,
    hasError
      ? ERROR_INPUT_CLASS
      : "",
  ]
    .filter(Boolean)
    .join(" ");
}

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
      className={`rounded-2xl border px-5 py-4 text-sm leading-6 ${className}`}
    >
      {state.message}
    </div>
  );
}

function toIsoTimestamp(
  localValue: string,
): string {
  if (!localValue) {
    return "";
  }

  const parsedDate =
    new Date(localValue);

  if (
    Number.isNaN(
      parsedDate.getTime(),
    )
  ) {
    return "";
  }

  return parsedDate.toISOString();
}

function formatMemberLabel(
  member: OrganizationMemberOption,
): string {
  return (
    member.displayName?.trim() ||
    member.userId
  );
}

export default function CreateFollowUpForm({
  leadId,
  members,
  defaultAssignedTo = null,
}: CreateFollowUpFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    createFollowUpAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  const [
    dueAtLocal,
    setDueAtLocal,
  ] = useState("");

  const [
    reminderAtLocal,
    setReminderAtLocal,
  ] = useState("");

  const errors =
    state.fieldErrors;

  return (
    <section className="rounded-2xl border border-cyan-500/30 bg-cyan-500/5 p-5 sm:p-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
          New follow-up
        </p>

        <h3 className="mt-3 text-xl font-semibold text-white">
          Schedule the next customer action
        </h3>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Add a due time, channel, priority and responsible
          organisation member. Local date-time values are converted
          into ISO timestamps before submission.
        </p>
      </header>

      <form
        action={formAction}
        className="mt-6 space-y-6"
      >
        <input
          type="hidden"
          name="leadId"
          value={leadId}
        />

        <input
          type="hidden"
          name="dueAt"
          value={toIsoTimestamp(
            dueAtLocal,
          )}
        />

        <input
          type="hidden"
          name="reminderAt"
          value={toIsoTimestamp(
            reminderAtLocal,
          )}
        />

        <ActionMessage state={state} />

        <div className="grid gap-5 md:grid-cols-2">
          <div>
            <label
              htmlFor="followUpTitle"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Title
            </label>

            <input
              id="followUpTitle"
              name="title"
              type="text"
              required
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .title
              }
              placeholder="Call customer about shortlisted property"
              disabled={isPending}
              aria-invalid={
                Boolean(errors.title)
              }
              aria-describedby={
                errors.title
                  ? "title-error"
                  : undefined
              }
              className={getInputClass(
                Boolean(errors.title),
              )}
            />

            <FieldError
              state={state}
              fieldName="title"
            />
          </div>

          <div>
            <label
              htmlFor="followUpType"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Follow-up type
            </label>

            <select
              id="followUpType"
              name="followUpType"
              defaultValue="call"
              disabled={isPending}
              aria-invalid={
                Boolean(
                  errors.followUpType,
                )
              }
              className={getInputClass(
                Boolean(
                  errors.followUpType,
                ),
              )}
            >
              {FOLLOW_UP_TYPES.map(
                (followUpType) => (
                  <option
                    key={followUpType}
                    value={followUpType}
                  >
                    {formatOperationalLabel(
                      followUpType,
                    )}
                  </option>
                ),
              )}
            </select>

            <FieldError
              state={state}
              fieldName="followUpType"
            />
          </div>

          <div>
            <label
              htmlFor="followUpPriority"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Priority
            </label>

            <select
              id="followUpPriority"
              name="priority"
              defaultValue="normal"
              disabled={isPending}
              aria-invalid={
                Boolean(errors.priority)
              }
              className={getInputClass(
                Boolean(errors.priority),
              )}
            >
              {OPERATIONAL_PRIORITIES.map(
                (priority) => (
                  <option
                    key={priority}
                    value={priority}
                  >
                    {formatOperationalLabel(
                      priority,
                    )}
                  </option>
                ),
              )}
            </select>

            <FieldError
              state={state}
              fieldName="priority"
            />
          </div>

          <div>
            <label
              htmlFor="followUpAssignedTo"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Assigned member
            </label>

            <select
              id="followUpAssignedTo"
              name="assignedTo"
              defaultValue={
                defaultAssignedTo ?? ""
              }
              disabled={isPending}
              aria-invalid={
                Boolean(errors.assignedTo)
              }
              className={getInputClass(
                Boolean(errors.assignedTo),
              )}
            >
              <option value="">
                Leave unassigned
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
              fieldName="assignedTo"
            />
          </div>

          <div>
            <label
              htmlFor="followUpDueAtLocal"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Due date and time
            </label>

            <input
              id="followUpDueAtLocal"
              type="datetime-local"
              required
              value={dueAtLocal}
              onChange={(event) => {
                setDueAtLocal(
                  event.target.value,
                );
              }}
              disabled={isPending}
              aria-invalid={
                Boolean(errors.dueAt)
              }
              className={getInputClass(
                Boolean(errors.dueAt),
              )}
            />

            <FieldError
              state={state}
              fieldName="dueAt"
            />
          </div>

          <div>
            <label
              htmlFor="followUpReminderAtLocal"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Reminder date and time
            </label>

            <input
              id="followUpReminderAtLocal"
              type="datetime-local"
              value={reminderAtLocal}
              max={dueAtLocal || undefined}
              onChange={(event) => {
                setReminderAtLocal(
                  event.target.value,
                );
              }}
              disabled={isPending}
              aria-invalid={
                Boolean(errors.reminderAt)
              }
              className={getInputClass(
                Boolean(errors.reminderAt),
              )}
            />

            <p className="mt-2 text-xs leading-5 text-slate-500">
              Optional. Keep it on or before the follow-up due time.
            </p>

            <FieldError
              state={state}
              fieldName="reminderAt"
            />
          </div>
        </div>

        <div>
          <label
            htmlFor="followUpDescription"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            Description
          </label>

          <textarea
            id="followUpDescription"
            name="description"
            rows={4}
            maxLength={
              OPERATIONAL_FORM_LIMITS
                .mediumText
            }
            placeholder="Add context, customer commitment or the next discussion point."
            disabled={isPending}
            aria-invalid={
              Boolean(errors.description)
            }
            className={getInputClass(
              Boolean(errors.description),
            )}
          />

          <FieldError
            state={state}
            fieldName="description"
          />
        </div>

        <div className="flex justify-end border-t border-slate-800 pt-5">
          <button
            type="submit"
            disabled={isPending}
            className="inline-flex min-w-44 items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isPending
              ? "Creating follow-up..."
              : "Create follow-up"}
          </button>
        </div>
      </form>
    </section>
  );
}
