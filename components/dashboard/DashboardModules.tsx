import Link from "next/link";

type DashboardModulesProps = {
  permissionCodes: readonly string[];
  isOwner: boolean;
};

type ModuleCardProps = {
  title: string;
  description: string;
  status: "active" | "upcoming" | "restricted";
  href?: string;
};

function ModuleCard({
  title,
  description,
  status,
  href,
}: ModuleCardProps) {
  const content = (
    <article
      className={[
        "h-full rounded-2xl border p-6 transition",
        status === "active"
          ? "border-cyan-500/40 bg-cyan-500/5 hover:border-cyan-400 hover:bg-cyan-500/10"
          : "border-slate-800 bg-slate-950/60",
      ].join(" ")}
    >
      <h3 className="text-lg font-semibold text-white">
        {title}
      </h3>

      <p className="mt-3 min-h-12 text-sm leading-6 text-slate-400">
        {description}
      </p>

      <div className="mt-5">
        {status === "active" ? (
          <span className="inline-flex rounded-full border border-cyan-500/40 bg-cyan-500/10 px-3 py-1 text-xs font-medium text-cyan-300">
            Open module →
          </span>
        ) : null}

        {status === "upcoming" ? (
          <span className="inline-flex rounded-full border border-slate-700 px-3 py-1 text-xs text-slate-500">
            Upcoming
          </span>
        ) : null}

        {status === "restricted" ? (
          <span className="inline-flex rounded-full border border-red-900/70 bg-red-950/30 px-3 py-1 text-xs text-red-300">
            Restricted
          </span>
        ) : null}
      </div>
    </article>
  );

  if (status === "active" && href) {
    return (
      <Link
        href={href}
        className="block h-full focus:outline-none focus:ring-2 focus:ring-cyan-400 focus:ring-offset-2 focus:ring-offset-slate-950"
      >
        {content}
      </Link>
    );
  }

  return content;
}

export default function DashboardModules({
  permissionCodes,
  isOwner,
}: DashboardModulesProps) {
  const canViewLeads =
    isOwner || permissionCodes.includes("leads.view");

  return (
    <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
      <div>
        <h2 className="text-2xl font-bold text-white">
          Platform modules
        </h2>

        <p className="mt-2 text-sm leading-6 text-slate-400">
          Permission के अनुसार उपलब्ध SalesSetu operational
          modules।
        </p>
      </div>

      <div className="mt-7 grid gap-5 md:grid-cols-2 xl:grid-cols-3">
        <ModuleCard
          title="Lead Operations"
          description="Lead capture, validation, qualification, source tracking और assignment monitoring."
          status={
            canViewLeads ? "active" : "restricted"
          }
          href={
            canViewLeads
              ? "/dashboard/leads"
              : undefined
          }
        />

        <ModuleCard
          title="AI Calling"
          description="Call jobs, campaigns, outcomes और AI qualification results."
          status="upcoming"
        />

        <ModuleCard
          title="Sales Pipeline"
          description="Follow-ups, site visits, bookings और deal progression."
          status="upcoming"
        />
      </div>
    </section>
  );
}