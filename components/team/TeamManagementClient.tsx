"use client";

import {
  useActionState,
  useEffect,
  useRef,
} from "react";

import {
  inviteSalesAgentAction,
  setSalesAgentStatusAction,
} from "@/app/dashboard/team/actions";
import {
  INITIAL_TEAM_ACTION_STATE,
  type TeamActionState,
} from "@/lib/team/team-action-contract";

export type ManagedSalesAgent = {
  membership_id: string;
  user_id: string;
  email: string;
  display_name: string | null;
  agent_code: string | null;
  membership_status: string;
  agent_status: string | null;
  availability_status: string | null;
  auto_assignment_enabled: boolean;
  accept_new_leads: boolean;
  invited_at: string | null;
  joined_at: string | null;
};

type TeamManagementClientProps = {
  organizationName: string;
  agents: ManagedSalesAgent[];
};

function ActionMessage({
  state,
}: {
  state: TeamActionState;
}) {
  if (state.status === "idle" || !state.message) {
    return null;
  }

  const className =
    state.status === "success"
      ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-200"
      : "border-red-500/40 bg-red-500/10 text-red-200";

  return (
    <div
      aria-live="polite"
      className={`rounded-2xl border px-4 py-3 text-sm leading-6 ${className}`}
    >
      {state.message}
    </div>
  );
}

function statusLabel(status: string | null): string {
  if (!status) {
    return "Not configured";
  }

  return status.replace(/_/g, " ");
}

function statusClass(status: string | null): string {
  switch (status) {
    case "active":
    case "available":
      return "border-emerald-500/40 bg-emerald-500/10 text-emerald-200";
    case "suspended":
    case "removed":
    case "inactive":
    case "offline":
      return "border-slate-600 bg-slate-800 text-slate-300";
    default:
      return "border-amber-500/40 bg-amber-500/10 text-amber-200";
  }
}

function InviteSalesAgentForm() {
  const formRef = useRef<HTMLFormElement>(null);
  const [state, formAction, isPending] = useActionState(
    inviteSalesAgentAction,
    INITIAL_TEAM_ACTION_STATE,
  );

  useEffect(() => {
    if (state.status === "success") {
      formRef.current?.reset();
    }
  }, [state.status]);

  const fieldClass =
    "mt-2 w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20";

  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.25em] text-cyan-400">
          Add Sales Agent
        </p>

        <h2 className="mt-3 text-2xl font-bold text-white">
          Invite a new teammate
        </h2>

        <p className="mt-2 max-w-2xl text-sm leading-6 text-slate-400">
          This adds only the standard Sales Agent role. The agent
          cannot manage your team, roles, billing, workflows or
          any other workspace. New agents receive the next Employee
          ID automatically and are set to manual lead routing by default.
        </p>
      </div>

      <form
        ref={formRef}
        action={formAction}
        noValidate
        className="mt-6 grid gap-5 md:grid-cols-2"
      >
        <div>
          <label
            htmlFor="displayName"
            className="text-sm font-medium text-slate-300"
          >
            Full name
          </label>

          <input
            id="displayName"
            name="displayName"
            type="text"
            autoComplete="name"
            required
            maxLength={120}
            disabled={isPending}
            aria-invalid={Boolean(
              state.fieldErrors.displayName,
            )}
            className={fieldClass}
            placeholder="e.g. Shweta Singh"
          />

          {state.fieldErrors.displayName?.map((message) => (
            <p
              key={message}
              className="mt-2 text-xs text-red-300"
            >
              {message}
            </p>
          ))}
        </div>

        <div>
          <label
            htmlFor="email"
            className="text-sm font-medium text-slate-300"
          >
            Work email
          </label>

          <input
            id="email"
            name="email"
            type="email"
            autoComplete="email"
            required
            disabled={isPending}
            aria-invalid={Boolean(state.fieldErrors.email)}
            className={fieldClass}
            placeholder="agent@company.com"
          />

          {state.fieldErrors.email?.map((message) => (
            <p
              key={message}
              className="mt-2 text-xs text-red-300"
            >
              {message}
            </p>
          ))}
        </div>

        <div className="md:col-span-2">
          <ActionMessage state={state} />
        </div>

        <div className="md:col-span-2 flex justify-end">
          <button
            type="submit"
            disabled={isPending}
            className="inline-flex min-w-44 items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {isPending ? "Adding agent..." : "Send invitation"}
          </button>
        </div>
      </form>
    </section>
  );
}

function SalesAgentActions({
  agent,
}: {
  agent: ManagedSalesAgent;
}) {
  const [state, formAction, isPending] = useActionState(
    setSalesAgentStatusAction,
    INITIAL_TEAM_ACTION_STATE,
  );

  const isActive = agent.membership_status === "active";
  const isRemoved = agent.membership_status === "removed";

  const buttonClass =
    "rounded-xl border px-3 py-2 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-60";

  return (
    <div className="space-y-3">
      <form
        action={formAction}
        onSubmit={(event) => {
          const formData = new FormData(event.currentTarget);
          const nextStatus = formData.get("nextStatus");

          if (
            nextStatus === "removed" &&
            !window.confirm(
              `Remove ${agent.display_name ?? agent.email} from this workspace? Their Auth account and history will be retained.`,
            )
          ) {
            event.preventDefault();
          }
        }}
        className="flex flex-wrap gap-2"
      >
        <input
          type="hidden"
          name="membershipId"
          value={agent.membership_id}
        />

        {isActive ? (
          <button
            type="submit"
            name="nextStatus"
            value="suspended"
            disabled={isPending}
            className={`${buttonClass} border-amber-500/50 text-amber-200 hover:bg-amber-500/10`}
          >
            Suspend
          </button>
        ) : !isRemoved ? (
          <button
            type="submit"
            name="nextStatus"
            value="active"
            disabled={isPending}
            className={`${buttonClass} border-emerald-500/50 text-emerald-200 hover:bg-emerald-500/10`}
          >
            Restore
          </button>
        ) : (
          <button
            type="submit"
            name="nextStatus"
            value="active"
            disabled={isPending}
            className={`${buttonClass} border-emerald-500/50 text-emerald-200 hover:bg-emerald-500/10`}
          >
            Add back
          </button>
        )}

        {!isRemoved ? (
          <button
            type="submit"
            name="nextStatus"
            value="removed"
            disabled={isPending}
            className={`${buttonClass} border-red-500/50 text-red-200 hover:bg-red-500/10`}
          >
            Remove
          </button>
        ) : null}
      </form>

      <ActionMessage state={state} />
    </div>
  );
}

export default function TeamManagementClient({
  organizationName,
  agents,
}: TeamManagementClientProps) {
  const activeCount = agents.filter(
    (agent) => agent.membership_status === "active",
  ).length;

  return (
    <div className="space-y-8">
      <header className="flex flex-col justify-between gap-5 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            Team Management
          </p>

          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white sm:text-5xl">
            Sales agents
          </h1>

          <p className="mt-4 max-w-3xl text-base leading-7 text-slate-400">
            Manage the Sales Agent team for {organizationName}.
            Changes are limited to this workspace and never affect
            any other channel partner.
          </p>
        </div>

        <div className="rounded-2xl border border-emerald-500/30 bg-emerald-500/10 px-5 py-4">
          <p className="text-xs uppercase tracking-wider text-emerald-300">
            Active agents
          </p>

          <p className="mt-1 text-2xl font-bold text-white">
            {activeCount}
          </p>
        </div>
      </header>

      <InviteSalesAgentForm />

      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
        <div>
          <h2 className="text-2xl font-bold text-white">
            Your Sales Agent team
          </h2>

          <p className="mt-2 text-sm leading-6 text-slate-400">
            Suspend stops workspace access temporarily. Remove
            revokes this workspace only; the person’s Auth account
            and historical sales records are not deleted.
          </p>
        </div>

        {agents.length === 0 ? (
          <div className="mt-6 rounded-2xl border border-dashed border-slate-700 bg-slate-950/60 p-8 text-center text-sm text-slate-400">
            No Sales Agents have been added to this workspace yet.
          </div>
        ) : (
          <div className="mt-6 space-y-4">
            {agents.map((agent) => (
              <article
                key={agent.membership_id}
                className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5"
              >
                <div className="flex flex-col gap-5 xl:flex-row xl:items-start xl:justify-between">
                  <div className="min-w-0">
                    <h3 className="text-lg font-semibold text-white">
                      {agent.display_name ?? "Unnamed Sales Agent"}
                    </h3>

                    <p className="mt-1 break-all text-sm text-slate-400">
                      {agent.email}
                    </p>

                    <div className="mt-4 flex flex-wrap gap-2">
                      <span
                        className={`rounded-full border px-3 py-1 text-xs font-medium capitalize ${statusClass(
                          agent.membership_status,
                        )}`}
                      >
                        Workspace: {statusLabel(agent.membership_status)}
                      </span>

                      <span
                        className={`rounded-full border px-3 py-1 text-xs font-medium capitalize ${statusClass(
                          agent.agent_status,
                        )}`}
                      >
                        Agent: {statusLabel(agent.agent_status)}
                      </span>

                      <span className="rounded-full border border-slate-700 bg-slate-900 px-3 py-1 text-xs font-medium capitalize text-slate-300">
                        Routing: {agent.auto_assignment_enabled ? "Auto" : "Manual"}
                      </span>
                    </div>

                    <p className="mt-4 text-xs text-slate-500">
                      Employee ID: {agent.agent_code ?? "Pending"}
                    </p>
                  </div>

                  <SalesAgentActions agent={agent} />
                </div>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
