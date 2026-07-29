import Link from "next/link";

export default function LeadNotFound() {
  return (
    <section className="rounded-3xl border border-amber-900/60 bg-amber-950/10 p-8">
      <p className="text-sm font-semibold uppercase tracking-[0.25em] text-amber-400">
        Lead Operations
      </p>

      <h1 className="mt-3 text-3xl font-bold text-white">
        Lead not found
      </h1>

      <p className="mt-4 max-w-2xl text-sm leading-7 text-slate-400">
        The requested lead does not exist, has been deleted
        or is not accessible within the current organisation.
      </p>

      <Link
        href="/dashboard/leads"
        className="mt-7 inline-flex rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300"
      >
        Return to Lead Operations
      </Link>
    </section>
  );
}