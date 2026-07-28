import Link from "next/link";

import { requireDashboardAccess } from "@/lib/auth/access-control";

export default async function DashboardPage() {
  const context = await requireDashboardAccess();

  const organization = context.organization;
  const membership = context.membership;

  return (
    <div className="space-y-8">
      <section>
        <p className="text-sm font-semibold uppercase tracking-[0.25em] text-cyan-400">
          SalesSetu Enterprise
        </p>

        <h1 className="mt-3 text-3xl font-bold tracking-tight md:text-4xl">
          Platform Dashboard
        </h1>

        <p className="mt-3 max-w-3xl leading-7 text-slate-400">
          Your authenticated SalesSetu organization workspace is active and
          protected through server-side membership and role validation.
        </p>
      </section>

      <section className="grid gap-5 md:grid-cols-2 xl:grid-cols-4">
        <DashboardMetric
          label="Authentication"
          value="Active"
          description="Server session verified"
          valueClassName="text-emerald-400"
        />

        <DashboardMetric
          label="Organization"
          value={organization?.name ?? "Unavailable"}
          description={organization?.slug ?? "No workspace slug"}
        />

        <DashboardMetric
          label="Membership"
          value={membership?.membershipStatus ?? "Unknown"}
          description={
            membership?.isOwner
              ? "Workspace owner"
              : "Organization member"
          }
          valueClassName="capitalize text-cyan-300"
        />

        <DashboardMetric
          label="Assigned roles"
          value={String(context.roles.length)}
          description={
            context.roles[0]?.name ??
            (membership?.isOwner ? "Owner access active" : "No explicit role")
          }
        />
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900 p-6 md:p-8">
        <div className="flex flex-col justify-between gap-6 md:flex-row md:items-center">
          <div>
            <h2 className="text-xl font-semibold">
              Enterprise foundation status
            </h2>

            <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
              Authentication, organization membership, role resolution and
              protected dashboard routing are operational.
            </p>
          </div>

          <Link
            href="/dashboard/context"
            className="inline-flex items-center justify-center rounded-xl bg-cyan-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300"
          >
            View organization context
          </Link>
        </div>

        <div className="mt-8 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
          <StatusItem label="Supabase SSR" status="Operational" />
          <StatusItem label="Authentication guard" status="Operational" />
          <StatusItem label="Organization context" status="Operational" />
          <StatusItem label="RBAC foundation" status="Operational" />
        </div>
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900 p-6 md:p-8">
        <h2 className="text-xl font-semibold">Next platform modules</h2>

        <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          <ModulePlaceholder
            title="Lead Operations"
            description="Lead capture, validation, qualification and assignment."
          />

          <ModulePlaceholder
            title="AI Calling"
            description="Call jobs, campaigns, outcomes and qualification results."
          />

          <ModulePlaceholder
            title="Sales Pipeline"
            description="Follow-ups, site visits, bookings and deal progression."
          />
        </div>
      </section>
    </div>
  );
}

type DashboardMetricProps = {
  label: string;
  value: string;
  description: string;
  valueClassName?: string;
};

function DashboardMetric({
  label,
  value,
  description,
  valueClassName = "text-white",
}: DashboardMetricProps) {
  return (
    <article className="rounded-2xl border border-slate-800 bg-slate-900 p-5">
      <p className="text-sm text-slate-500">{label}</p>

      <p
        className={[
          "mt-3 truncate text-xl font-semibold",
          valueClassName,
        ].join(" ")}
      >
        {value}
      </p>

      <p className="mt-2 truncate text-xs text-slate-500">
        {description}
      </p>
    </article>
  );
}

type StatusItemProps = {
  label: string;
  status: string;
};

function StatusItem({ label, status }: StatusItemProps) {
  return (
    <div className="rounded-xl border border-slate-800 bg-slate-950 p-4">
      <div className="flex items-center gap-2">
        <span
          aria-hidden="true"
          className="h-2 w-2 rounded-full bg-emerald-400"
        />

        <span className="text-sm font-medium text-slate-200">
          {label}
        </span>
      </div>

      <p className="mt-2 text-xs text-emerald-400">{status}</p>
    </div>
  );
}

type ModulePlaceholderProps = {
  title: string;
  description: string;
};

function ModulePlaceholder({
  title,
  description,
}: ModulePlaceholderProps) {
  return (
    <article className="rounded-2xl border border-slate-800 bg-slate-950 p-5">
      <p className="font-semibold text-slate-100">{title}</p>

      <p className="mt-2 text-sm leading-6 text-slate-500">
        {description}
      </p>

      <span className="mt-4 inline-flex rounded-full border border-slate-800 px-3 py-1 text-xs text-slate-500">
        Upcoming
      </span>
    </article>
  );
}