"use client";

import {
  useActionState,
  useState,
} from "react";

import {
  createSiteVisitAction,
} from "@/app/dashboard/leads/operational-actions";

import {
  DEFAULT_OPERATIONAL_TIMEZONE,
  INITIAL_OPERATIONAL_ACTION_STATE,
  OPERATIONAL_FORM_LIMITS,
  OPERATIONAL_PRIORITIES,
  SITE_VISIT_TYPES,
  formatOperationalLabel,
} from "@/lib/leads/lead-operational-contract";

import type {
  OperationalActionState,
  OrganizationMemberOption,
} from "@/types/lead-operational-controls";

type CreateSiteVisitFormProps = {
  leadId: string;
  members: OrganizationMemberOption[];
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

export default function CreateSiteVisitForm({
  leadId,
  members,
}: CreateSiteVisitFormProps) {
  const [
    state,
    formAction,
    isPending,
  ] = useActionState(
    createSiteVisitAction,
    INITIAL_OPERATIONAL_ACTION_STATE,
  );

  const [
    scheduledStartAtLocal,
    setScheduledStartAtLocal,
  ] = useState("");

  const [
    scheduledEndAtLocal,
    setScheduledEndAtLocal,
  ] = useState("");

  const [
    reminderAtLocal,
    setReminderAtLocal,
  ] = useState("");

  const [
    pickupRequired,
    setPickupRequired,
  ] = useState(false);

  const [
    pickupTimeLocal,
    setPickupTimeLocal,
  ] = useState("");

  const errors =
    state.fieldErrors;

      return (
    <section className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5 sm:p-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
          New site visit
        </p>

        <h3 className="mt-3 text-xl font-semibold text-white">
          Schedule a customer site visit
        </h3>

        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Record the project, schedule, responsible team and visit logistics.
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
          name="scheduledStartAt"
          value={toIsoTimestamp(
            scheduledStartAtLocal,
          )}
        />

        <input
          type="hidden"
          name="scheduledEndAt"
          value={toIsoTimestamp(
            scheduledEndAtLocal,
          )}
        />

        <input
          type="hidden"
          name="reminderAt"
          value={toIsoTimestamp(
            reminderAtLocal,
          )}
        />

        <input
          type="hidden"
          name="pickupTime"
          value={toIsoTimestamp(
            pickupTimeLocal,
          )}
        />

        <input
          type="hidden"
          name="timezone"
          value={
            DEFAULT_OPERATIONAL_TIMEZONE
          }
        />

        <ActionMessage state={state} />

                <div className="grid gap-5 md:grid-cols-2">
          <div>
            <label
              htmlFor="siteVisitTitle"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Visit title
            </label>

            <input
              id="siteVisitTitle"
              name="title"
              type="text"
              required
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .title
              }
              placeholder="Site visit for shortlisted project"
              disabled={isPending}
              aria-invalid={
                Boolean(errors.title)
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
              htmlFor="siteVisitType"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Visit type
            </label>

            <select
              id="siteVisitType"
              name="visitType"
              defaultValue="physical"
              disabled={isPending}
              aria-invalid={
                Boolean(errors.visitType)
              }
              className={getInputClass(
                Boolean(errors.visitType),
              )}
            >
              {SITE_VISIT_TYPES.map(
                (visitType) => (
                  <option
                    key={visitType}
                    value={visitType}
                  >
                    {formatOperationalLabel(
                      visitType,
                    )}
                  </option>
                ),
              )}
            </select>

            <FieldError
              state={state}
              fieldName="visitType"
            />
          </div>

          <div>
            <label
              htmlFor="siteVisitPriority"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Priority
            </label>

            <select
              id="siteVisitPriority"
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
              htmlFor="siteVisitProjectName"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Project name
            </label>

            <input
              id="siteVisitProjectName"
              name="projectName"
              type="text"
              required
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .shortText
              }
              placeholder="Project name"
              disabled={isPending}
              aria-invalid={
                Boolean(
                  errors.projectName,
                )
              }
              className={getInputClass(
                Boolean(
                  errors.projectName,
                ),
              )}
            />

            <FieldError
              state={state}
              fieldName="projectName"
            />
          </div>
        </div>

                <div>
          <label
            htmlFor="siteVisitDescription"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            Description
          </label>

          <textarea
            id="siteVisitDescription"
            name="description"
            rows={4}
            maxLength={
              OPERATIONAL_FORM_LIMITS
                .mediumText
            }
            placeholder="Add customer requirements, visit purpose or important context."
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

        <div className="grid gap-5 md:grid-cols-3">
          <div>
            <label
              htmlFor="siteVisitDeveloperName"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Developer name
            </label>

            <input
              id="siteVisitDeveloperName"
              name="developerName"
              type="text"
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .shortText
              }
              placeholder="Developer name"
              disabled={isPending}
              aria-invalid={
                Boolean(
                  errors.developerName,
                )
              }
              className={getInputClass(
                Boolean(
                  errors.developerName,
                ),
              )}
            />

            <FieldError
              state={state}
              fieldName="developerName"
            />
          </div>

          <div>
            <label
              htmlFor="siteVisitPropertyName"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Property / tower
            </label>

            <input
              id="siteVisitPropertyName"
              name="propertyName"
              type="text"
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .shortText
              }
              placeholder="Tower or property name"
              disabled={isPending}
              aria-invalid={
                Boolean(
                  errors.propertyName,
                )
              }
              className={getInputClass(
                Boolean(
                  errors.propertyName,
                ),
              )}
            />

            <FieldError
              state={state}
              fieldName="propertyName"
            />
          </div>

          <div>
            <label
              htmlFor="siteVisitUnitType"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Unit type
            </label>

            <input
              id="siteVisitUnitType"
              name="unitType"
              type="text"
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .shortText
              }
              placeholder="3 BHK, Villa, Plot"
              disabled={isPending}
              aria-invalid={
                Boolean(errors.unitType)
              }
              className={getInputClass(
                Boolean(errors.unitType),
              )}
            />

            <FieldError
              state={state}
              fieldName="unitType"
            />
          </div>
        </div>

                <div className="grid gap-5 md:grid-cols-2">
          <div>
            <label
              htmlFor="siteVisitCity"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Visit city
            </label>

            <input
              id="siteVisitCity"
              name="visitCity"
              type="text"
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .shortText
              }
              placeholder="Greater Noida"
              disabled={isPending}
              aria-invalid={
                Boolean(errors.visitCity)
              }
              className={getInputClass(
                Boolean(errors.visitCity),
              )}
            />

            <FieldError
              state={state}
              fieldName="visitCity"
            />
          </div>

          <div>
            <label
              htmlFor="siteVisitLocationUrl"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Location URL
            </label>

            <input
              id="siteVisitLocationUrl"
              name="locationUrl"
              type="url"
              maxLength={
                OPERATIONAL_FORM_LIMITS
                  .mediumText
              }
              placeholder="https://maps.google.com/..."
              disabled={isPending}
              aria-invalid={
                Boolean(errors.locationUrl)
              }
              className={getInputClass(
                Boolean(errors.locationUrl),
              )}
            />

            <FieldError
              state={state}
              fieldName="locationUrl"
            />
          </div>
        </div>

        <div>
          <label
            htmlFor="siteVisitAddress"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            Visit address
          </label>

          <textarea
            id="siteVisitAddress"
            name="visitAddress"
            rows={3}
            maxLength={
              OPERATIONAL_FORM_LIMITS
                .mediumText
            }
            placeholder="Site office, project address or meeting point."
            disabled={isPending}
            aria-invalid={
              Boolean(errors.visitAddress)
            }
            className={getInputClass(
              Boolean(errors.visitAddress),
            )}
          />

          <FieldError
            state={state}
            fieldName="visitAddress"
          />
        </div>

                <div className="grid gap-5 md:grid-cols-3">
          <div>
            <label
              htmlFor="siteVisitScheduledStartAt"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Start date and time
            </label>

            <input
              id="siteVisitScheduledStartAt"
              type="datetime-local"
              required
              value={scheduledStartAtLocal}
              onChange={(event) => {
                setScheduledStartAtLocal(
                  event.target.value,
                );
              }}
              disabled={isPending}
              aria-invalid={
                Boolean(
                  errors.scheduledStartAt,
                )
              }
              className={getInputClass(
                Boolean(
                  errors.scheduledStartAt,
                ),
              )}
            />

            <FieldError
              state={state}
              fieldName="scheduledStartAt"
            />
          </div>

          <div>
            <label
              htmlFor="siteVisitScheduledEndAt"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              End date and time
            </label>

            <input
              id="siteVisitScheduledEndAt"
              type="datetime-local"
              value={scheduledEndAtLocal}
              min={
                scheduledStartAtLocal ||
                undefined
              }
              onChange={(event) => {
                setScheduledEndAtLocal(
                  event.target.value,
                );
              }}
              disabled={isPending}
              aria-invalid={
                Boolean(
                  errors.scheduledEndAt,
                )
              }
              className={getInputClass(
                Boolean(
                  errors.scheduledEndAt,
                ),
              )}
            />

            <FieldError
              state={state}
              fieldName="scheduledEndAt"
            />
          </div>

          <div>
            <label
              htmlFor="siteVisitReminderAt"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Reminder
            </label>

            <input
              id="siteVisitReminderAt"
              type="datetime-local"
              value={reminderAtLocal}
              max={
                scheduledStartAtLocal ||
                undefined
              }
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
              Optional. Keep the reminder on or before the visit start time.
            </p>

            <FieldError
              state={state}
              fieldName="reminderAt"
            />
          </div>
        </div>

                <div className="grid gap-5 md:grid-cols-2">
          <div>
            <label
              htmlFor="siteVisitAssignedAgent"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Assigned agent
            </label>

            <select
              id="siteVisitAssignedAgent"
              name="assignedAgentId"
              defaultValue=""
              disabled={
                isPending ||
                members.length === 0
              }
              aria-invalid={
                Boolean(
                  errors.assignedAgentId,
                )
              }
              className={getInputClass(
                Boolean(
                  errors.assignedAgentId,
                ),
              )}
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
              htmlFor="siteVisitCoordinator"
              className="mb-2 block text-sm font-medium text-slate-300"
            >
              Coordinator
            </label>

            <select
              id="siteVisitCoordinator"
              name="coordinatorId"
              defaultValue=""
              disabled={
                isPending ||
                members.length === 0
              }
              aria-invalid={
                Boolean(
                  errors.coordinatorId,
                )
              }
              className={getInputClass(
                Boolean(
                  errors.coordinatorId,
                ),
              )}
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
        </div>

        {members.length === 0 ? (
          <p className="text-xs leading-5 text-amber-300">
            No organisation member is currently available for site visit assignment.
          </p>
        ) : null}

                <div className="rounded-2xl border border-slate-800 bg-slate-900/40 p-5">
          <label className="flex items-start gap-3">
            <input
              type="checkbox"
              name="pickupRequired"
              checked={pickupRequired}
              onChange={(event) => {
                setPickupRequired(
                  event.target.checked,
                );
              }}
              disabled={isPending}
              className="mt-1 h-4 w-4 rounded border-slate-600 bg-slate-950 text-cyan-400 focus:ring-cyan-500"
            />

            <span>
              <span className="block text-sm font-medium text-slate-200">
                Pickup required
              </span>

              <span className="mt-1 block text-xs leading-5 text-slate-500">
                Enable this when customer transport or pickup coordination is required.
              </span>
            </span>
          </label>

          {pickupRequired ? (
            <div className="mt-5 space-y-5">
              <div className="grid gap-5 md:grid-cols-2">
                <div>
                  <label
                    htmlFor="siteVisitPickupTime"
                    className="mb-2 block text-sm font-medium text-slate-300"
                  >
                    Pickup date and time
                  </label>

                  <input
                    id="siteVisitPickupTime"
                    type="datetime-local"
                    value={pickupTimeLocal}
                    max={
                      scheduledStartAtLocal ||
                      undefined
                    }
                    onChange={(event) => {
                      setPickupTimeLocal(
                        event.target.value,
                      );
                    }}
                    disabled={isPending}
                    aria-invalid={
                      Boolean(
                        errors.pickupTime,
                      )
                    }
                    className={getInputClass(
                      Boolean(
                        errors.pickupTime,
                      ),
                    )}
                  />

                  <FieldError
                    state={state}
                    fieldName="pickupTime"
                  />
                </div>

                <div>
                  <label
                    htmlFor="siteVisitPickupAddress"
                    className="mb-2 block text-sm font-medium text-slate-300"
                  >
                    Pickup address
                  </label>

                  <textarea
                    id="siteVisitPickupAddress"
                    name="pickupAddress"
                    rows={3}
                    maxLength={
                      OPERATIONAL_FORM_LIMITS
                        .mediumText
                    }
                    placeholder="Customer pickup point or address."
                    disabled={isPending}
                    aria-invalid={
                      Boolean(
                        errors.pickupAddress,
                      )
                    }
                    className={getInputClass(
                      Boolean(
                        errors.pickupAddress,
                      ),
                    )}
                  />

                  <FieldError
                    state={state}
                    fieldName="pickupAddress"
                  />
                </div>
              </div>

              <div>
                <label
                  htmlFor="siteVisitTransportNotes"
                  className="mb-2 block text-sm font-medium text-slate-300"
                >
                  Transport notes
                </label>

                <textarea
                  id="siteVisitTransportNotes"
                  name="transportNotes"
                  rows={3}
                  maxLength={
                    OPERATIONAL_FORM_LIMITS
                      .notes
                  }
                  placeholder="Vehicle, driver, customer preference or transport instructions."
                  disabled={isPending}
                  aria-invalid={
                    Boolean(
                      errors.transportNotes,
                    )
                  }
                  className={getInputClass(
                    Boolean(
                      errors.transportNotes,
                    ),
                  )}
                />

                <FieldError
                  state={state}
                  fieldName="transportNotes"
                />
              </div>
            </div>
          ) : null}
        </div>

                <div className="flex justify-end border-t border-slate-800 pt-5">
          <button
            type="submit"
            disabled={isPending}
            className="inline-flex min-w-44 items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isPending
              ? "Creating site visit..."
              : "Create site visit"}
          </button>
        </div>
      </form>
    </section>
  );
}