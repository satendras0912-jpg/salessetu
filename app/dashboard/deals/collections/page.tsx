import Link from "next/link";
import { redirect } from "next/navigation";

import PaymentCollectionsRefresh from "@/components/dealos/PaymentCollectionsRefresh";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import {
  getPaymentDueWorklist,
  type PaymentDueWorklistItem,
} from "@/lib/bookings/payment-due-worklist-service";

export const dynamic = "force-dynamic";

function formatCurrency(value: number, currencyCode: string): string {
  try {
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: currencyCode,
      maximumFractionDigits: 0,
    }).format(value);
  } catch {
    return `${currencyCode} ${value.toLocaleString("en-IN")}`;
  }
}

function formatDate(value: string): string {
  return new Intl.DateTimeFormat("en-IN", {
    dateStyle: "medium",
    timeZone: "Asia/Kolkata",
  }).format(new Date(`${value}T00:00:00`));
}

function label(value: string): string {
  return value.replaceAll("_", " ").replace(/\b\w/g, (character) => character.toUpperCase());
}

function statusClass(status: PaymentDueWorklistItem["effectiveStatus"]): string {
  if (status === "overdue") return "border-red-500/40 bg-red-500/10 text-red-200";
  if (status === "partially_paid") return "border-amber-500/40 bg-amber-500/10 text-amber-200";
  return "border-cyan-500/40 bg-cyan-500/10 text-cyan-200";
}

export default async function PaymentCollectionsWorklistPage() {
  const { context } = await requirePermissionAccess({
    allOf: ["deals.view"],
    loginRedirectTo: "/login?next=/dashboard/deals/collections",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    redirect("/unauthorized");
  }

  const organizationId = context.organization?.id;

  if (!organizationId) {
    redirect("/auth-error?reason=organization_context_missing");
  }

  const worklist = await getPaymentDueWorklist(organizationId);
  const leadCurrency = worklist.items[0]?.currencyCode ?? "INR";

  return (
    <div className="space-y-8">
      <header className="flex flex-col justify-between gap-5 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">Post-sale collections</p>
          <h1 className="mt-3 text-3xl font-bold text-white">Payment Due Alerts</h1>
          <p className="mt-3 max-w-3xl text-slate-400">Confirmed bookings ke pending aur partially-paid installments ko owner priority ke saath track karein. Payment status change yahan nahi hota—deal detail mein audited receipt record karein.</p>
        </div>
        <div className="flex flex-col items-start gap-3 xl:items-end">
          <PaymentCollectionsRefresh />
          <Link href="/dashboard/deals" className="inline-flex rounded-xl border border-slate-700 bg-slate-900 px-4 py-2 text-sm font-semibold text-cyan-300 hover:border-cyan-400 hover:text-cyan-100">Back to deals</Link>
        </div>
      </header>

      <section aria-label="Payment due summary" className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
        {[
          ["Open installments", String(worklist.metrics.open), "text-white"],
          ["Overdue", String(worklist.metrics.overdue), "text-red-300"],
          ["Due today", String(worklist.metrics.dueToday), "text-amber-300"],
          ["Next 7 days", String(worklist.metrics.dueNextSevenDays), "text-cyan-200"],
          ["Outstanding", formatCurrency(worklist.metrics.outstanding, leadCurrency), "text-emerald-300"],
        ].map(([labelText, value, colour]) => <article key={labelText} className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5"><p className="text-sm text-slate-400">{labelText}</p><p className={`mt-2 text-3xl font-bold ${colour}`}>{value}</p></article>)}
      </section>

      <section className="overflow-x-auto rounded-2xl border border-slate-800">
        <div className="border-b border-slate-800 bg-slate-900/70 px-5 py-4"><h2 className="font-semibold text-white">Collection action queue</h2><p className="mt-1 text-sm text-slate-400">Overdue items first, then due date. Today: {formatDate(worklist.today)}.</p></div>
        {worklist.items.length === 0 ? <div className="p-8 text-slate-300">No open payment installments. All confirmed-booking schedules are settled or not yet scheduled.</div> : <table className="w-full text-left text-sm"><caption className="sr-only">Payment due worklist</caption><thead className="bg-slate-950/70 text-slate-400"><tr>{["Status", "Booking / customer", "Installment", "Due", "Outstanding", "Action"].map((column) => <th key={column} scope="col" className="px-5 py-4">{column}</th>)}</tr></thead><tbody className="divide-y divide-slate-800">{worklist.items.map((item) => <tr key={item.scheduleId} className="bg-slate-900/40"><td className="px-5 py-4"><span className={`inline-flex rounded-full border px-3 py-1 text-xs font-semibold ${statusClass(item.effectiveStatus)}`}>{label(item.effectiveStatus)}</span></td><td className="px-5 py-4"><p className="font-semibold text-white">{item.bookingNumber} · {item.projectName}</p><p className="mt-1 text-slate-400">{item.customerName}{item.customerPhone ? ` · ${item.customerPhone}` : ""}{item.unitNumber ? ` · Unit ${item.unitNumber}` : ""}</p></td><td className="px-5 py-4"><p className="font-medium text-slate-200">#{item.sequenceNumber} · {label(item.paymentType)}</p>{item.notes ? <p className="mt-1 max-w-xs text-xs text-slate-500">{item.notes}</p> : null}</td><td className="whitespace-nowrap px-5 py-4 text-slate-200"><time dateTime={item.dueDate}>{formatDate(item.dueDate)}</time></td><td className="whitespace-nowrap px-5 py-4"><p className="font-semibold text-amber-300">{formatCurrency(item.outstanding, item.currencyCode)}</p><p className="mt-1 text-xs text-slate-500">Received {formatCurrency(item.amountReceived, item.currencyCode)} / {formatCurrency(item.amountDue, item.currencyCode)}</p></td><td className="px-5 py-4">{item.dealId ? <Link href={`/dashboard/deals/${item.dealId}#payment-schedule`} className="whitespace-nowrap font-semibold text-cyan-300 hover:text-cyan-100">Record receipt</Link> : <span className="text-slate-500">Deal unavailable</span>}</td></tr>)}</tbody></table>}
      </section>
      <p className="text-sm text-slate-500">Owner-only view. Scheduling and receipt entries retain their existing audit controls; this worklist does not send customer notifications or create follow-up tasks automatically.</p>
    </div>
  );
}
