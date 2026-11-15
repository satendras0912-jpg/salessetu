"use client";

import Link from "next/link";
import { useActionState } from "react";

import { decideBookingPaymentReceiptAction } from "@/app/dashboard/deals/actions";
import { INITIAL_DEALOS_ACTION_STATE } from "@/lib/dealos/deal-contract";
import type { BookingPaymentReceiptSubmission } from "@/lib/bookings/payment-receipt-approval-service";

const INPUT = "w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20";

function money(value: number): string { return new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(value); }
function date(value: string): string { return new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Kolkata" }).format(new Date(value)); }
function label(value: string): string { return value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase()); }

function Row({ item }: { item: BookingPaymentReceiptSubmission }) {
  const [state, action, pending] = useActionState(decideBookingPaymentReceiptAction, INITIAL_DEALOS_ACTION_STATE);
  return <article className="rounded-2xl border border-slate-800 bg-slate-900/50 p-5"><div className="flex flex-col justify-between gap-3 sm:flex-row"><div><p className="font-semibold text-white">{money(item.amount)} · {label(item.paymentMode)}</p><p className="mt-1 text-sm text-slate-300">{item.paymentReference} · paid {date(item.paymentDate)}</p><p className="mt-1 text-xs text-slate-500">Submitted {date(item.submittedAt)} · booking {item.bookingId.slice(0, 8)}</p>{item.notes ? <p className="mt-2 text-sm text-slate-400">{item.notes}</p> : null}</div><Link href={`/dashboard/deals/${item.dealId}#payment-schedule`} className="h-fit whitespace-nowrap rounded-xl border border-cyan-500/50 px-4 py-2 text-sm font-semibold text-cyan-300 hover:text-cyan-100">Open booking</Link></div><form action={action} className="mt-5 grid gap-3 lg:grid-cols-[1fr_auto_auto] lg:items-end"><input type="hidden" name="submissionId" value={item.id} /><input type="hidden" name="dealId" value={item.dealId} /><div><label htmlFor={`queue-reason-${item.id}`} className="mb-2 block text-sm text-slate-300">Owner decision reason</label><input id={`queue-reason-${item.id}`} name="reason" required minLength={3} maxLength={1000} className={INPUT} placeholder="Verified against bank / receipt proof" /></div><button type="submit" name="decision" value="approved" disabled={pending} className="rounded-xl bg-emerald-400 px-4 py-3 text-sm font-semibold text-slate-950 disabled:opacity-50">Approve</button><button type="submit" name="decision" value="rejected" disabled={pending} className="rounded-xl border border-red-500/60 px-4 py-3 text-sm font-semibold text-red-200 disabled:opacity-50">Reject</button></form>{state.status !== "idle" && state.message ? <p aria-live="polite" className="mt-3 text-sm text-red-300">{state.message}</p> : null}</article>;
}

export default function ReceiptApprovalQueue({ items }: { items: BookingPaymentReceiptSubmission[] }) {
  return items.length ? <div className="space-y-4">{items.map((item) => <Row key={item.id} item={item} />)}</div> : <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 px-5 py-10 text-center text-sm text-slate-400">No receipt submissions are waiting for owner approval.</div>;
}
