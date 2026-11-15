import Link from "next/link";
import { redirect } from "next/navigation";

import PaymentReconciliationExport from "@/components/dealos/PaymentReconciliationExport";
import PaymentReconciliationRefresh from "@/components/dealos/PaymentReconciliationRefresh";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import { getPaymentReconciliation } from "@/lib/bookings/payment-reconciliation-service";

export const dynamic = "force-dynamic";

function currency(value: number, code = "INR"): string {
  try {
    return new Intl.NumberFormat("en-IN", { style: "currency", currency: code, maximumFractionDigits: 0 }).format(value);
  } catch {
    return `${code} ${value.toLocaleString("en-IN")}`;
  }
}

function date(value: string | null): string {
  if (!value) return "—";

  return new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "Asia/Kolkata" }).format(new Date(`${value}T00:00:00`));
}

export default async function PaymentReconciliationPage() {
  const { context } = await requirePermissionAccess({
    allOf: ["deals.view"],
    loginRedirectTo: "/login?next=/dashboard/deals/reconciliation",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) redirect("/unauthorized");
  if (!context.organization?.id) redirect("/auth-error?reason=organization_context_missing");

  const report = await getPaymentReconciliation(context.organization.id);

  return <div className="space-y-8">
    <header className="flex flex-col justify-between gap-5 xl:flex-row xl:items-end">
      <div>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">Post-sale collections</p>
        <h1 className="mt-3 text-3xl font-bold text-white">Collection Reconciliation</h1>
        <p className="mt-3 max-w-3xl text-slate-400">Confirmed booking schedules, receipts and aging ko ek owner-only audit view mein reconcile karein. Is page se koi payment, follow-up ya customer notification create nahi hota.</p>
      </div>
      <div className="flex flex-wrap items-center gap-3 xl:justify-end">
        <PaymentReconciliationRefresh />
        <PaymentReconciliationExport rows={report.bookings} reportDate={report.today} />
        <Link href="/dashboard/deals/collections" className="rounded-xl border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-semibold text-cyan-300 hover:border-cyan-400 hover:text-cyan-100">Payment due alerts</Link>
      </div>
    </header>

    <section aria-label="Collection reconciliation summary" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
      {[
        ["Scheduled", currency(report.metrics.scheduled), "text-white"],
        ["Received", currency(report.metrics.received), "text-emerald-300"],
        ["Outstanding", currency(report.metrics.outstanding), "text-amber-300"],
        ["Open installments", String(report.metrics.openInstallments), "text-cyan-200"],
        ["Overdue installments", String(report.metrics.overdueInstallments), "text-red-300"],
      ].map(([label, value, colour]) => <article key={label} className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5"><p className="text-sm text-slate-400">{label}</p><p className={`mt-2 text-3xl font-bold ${colour}`}>{value}</p></article>)}
    </section>

    <section className="rounded-2xl border border-slate-800 bg-slate-900/50 p-5">
      <div className="flex flex-col justify-between gap-2 sm:flex-row sm:items-end"><div><h2 className="text-lg font-semibold text-white">Overdue aging</h2><p className="mt-1 text-sm text-slate-400">Only unpaid portions of confirmed-booking schedules are included. As of {date(report.today)}.</p></div><p className="text-sm text-slate-500">No collection actions are triggered from this report.</p></div>
      <div className="mt-5 grid gap-3 md:grid-cols-3">{report.aging.map((bucket) => <article key={bucket.label} className="rounded-xl border border-slate-800 bg-slate-950/50 p-4"><p className="text-sm text-slate-400">{bucket.label} overdue</p><p className="mt-2 text-2xl font-bold text-red-300">{currency(bucket.outstanding)}</p><p className="mt-1 text-sm text-slate-500">{bucket.count} installment{bucket.count === 1 ? "" : "s"}</p></article>)}</div>
    </section>

    <div className="grid gap-8 2xl:grid-cols-2">
      <section className="overflow-x-auto rounded-2xl border border-slate-800"><div className="border-b border-slate-800 bg-slate-900/70 px-5 py-4"><h2 className="font-semibold text-white">Project reconciliation</h2></div><table className="w-full text-left text-sm"><caption className="sr-only">Project reconciliation</caption><thead className="bg-slate-950/70 text-slate-400"><tr>{["Project", "Scheduled", "Received", "Outstanding", "Open"].map((value) => <th key={value} scope="col" className="px-5 py-3">{value}</th>)}</tr></thead><tbody className="divide-y divide-slate-800">{report.projects.length ? report.projects.map((row) => <tr key={row.projectName} className="bg-slate-900/40"><td className="px-5 py-4 font-medium text-white">{row.projectName}</td><td className="px-5 py-4 text-slate-300">{currency(row.scheduled)}</td><td className="px-5 py-4 text-emerald-300">{currency(row.received)}</td><td className="px-5 py-4 text-amber-300">{currency(row.outstanding)}</td><td className="px-5 py-4 text-slate-300">{row.openInstallments}</td></tr>) : <tr><td colSpan={5} className="px-5 py-8 text-slate-400">No confirmed-booking payment schedules yet.</td></tr>}</tbody></table></section>
      <section className="overflow-x-auto rounded-2xl border border-slate-800"><div className="border-b border-slate-800 bg-slate-900/70 px-5 py-4"><h2 className="font-semibold text-white">Agent reconciliation</h2></div><table className="w-full text-left text-sm"><caption className="sr-only">Agent reconciliation</caption><thead className="bg-slate-950/70 text-slate-400"><tr>{["Agent", "Scheduled", "Received", "Outstanding", "Open"].map((value) => <th key={value} scope="col" className="px-5 py-3">{value}</th>)}</tr></thead><tbody className="divide-y divide-slate-800">{report.agents.length ? report.agents.map((row) => <tr key={`${row.agentCode ?? "unassigned"}-${row.agentName}`} className="bg-slate-900/40"><td className="px-5 py-4"><p className="font-medium text-white">{row.agentName}</p>{row.agentCode ? <p className="mt-1 text-xs text-slate-500">{row.agentCode}</p> : null}</td><td className="px-5 py-4 text-slate-300">{currency(row.scheduled)}</td><td className="px-5 py-4 text-emerald-300">{currency(row.received)}</td><td className="px-5 py-4 text-amber-300">{currency(row.outstanding)}</td><td className="px-5 py-4 text-slate-300">{row.openInstallments}</td></tr>) : <tr><td colSpan={5} className="px-5 py-8 text-slate-400">No confirmed-booking payment schedules yet.</td></tr>}</tbody></table></section>
    </div>

    <section className="overflow-x-auto rounded-2xl border border-slate-800"><div className="border-b border-slate-800 bg-slate-900/70 px-5 py-4"><h2 className="font-semibold text-white">Booking payment ledger</h2><p className="mt-1 text-sm text-slate-400">Latest 100 confirmed bookings with payment schedules.</p></div><table className="w-full text-left text-sm"><caption className="sr-only">Booking payment ledger</caption><thead className="bg-slate-950/70 text-slate-400"><tr>{["Booking / customer", "Agent", "Scheduled", "Received", "Outstanding", "Next due", "Action"].map((value) => <th key={value} scope="col" className="px-5 py-3">{value}</th>)}</tr></thead><tbody className="divide-y divide-slate-800">{report.bookings.length ? report.bookings.map((row) => <tr key={row.bookingId} className="bg-slate-900/40"><td className="px-5 py-4"><p className="font-medium text-white">{row.bookingNumber} · {row.projectName}</p><p className="mt-1 text-slate-400">{row.customerName}{row.unitNumber ? ` · Unit ${row.unitNumber}` : ""}</p></td><td className="px-5 py-4 text-slate-300">{row.agentName}</td><td className="px-5 py-4 text-slate-300">{currency(row.scheduled, row.currencyCode)}</td><td className="px-5 py-4 text-emerald-300">{currency(row.received, row.currencyCode)}</td><td className="px-5 py-4"><p className="font-semibold text-amber-300">{currency(row.outstanding, row.currencyCode)}</p>{row.overdueOutstanding > 0 ? <p className="mt-1 text-xs text-red-300">Overdue {currency(row.overdueOutstanding, row.currencyCode)}</p> : null}</td><td className="whitespace-nowrap px-5 py-4 text-slate-300">{date(row.nextDueDate)}</td><td className="px-5 py-4">{row.dealId ? <Link href={`/dashboard/deals/${row.dealId}#payment-schedule`} className="whitespace-nowrap font-semibold text-cyan-300 hover:text-cyan-100">Open payment ledger</Link> : <span className="text-slate-500">Deal unavailable</span>}</td></tr>) : <tr><td colSpan={7} className="px-5 py-8 text-slate-400">No confirmed-booking payment schedules yet.</td></tr>}</tbody></table></section>
    <p className="text-sm text-slate-500">Owner-only report. Scheduled and received totals use the audited payment-schedule ledger; cancellation rows are excluded.</p>
  </div>;
}
