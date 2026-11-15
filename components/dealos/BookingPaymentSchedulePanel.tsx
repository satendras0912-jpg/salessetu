"use client";

import { useActionState } from "react";

import {
  createBookingPaymentScheduleAction,
  recordBookingSchedulePaymentAction,
} from "@/app/dashboard/deals/actions";

import { INITIAL_DEALOS_ACTION_STATE } from "@/lib/dealos/deal-contract";

import type { BookingPaymentSchedule } from "@/lib/bookings/payment-schedule-service";

import type { DealOSActionState, DealOSFieldErrors } from "@/types/dealos-actions";

type BookingPaymentSchedulePanelProps = {
  dealId: string;
  bookingId: string;
  currencyCode: string;
  schedules: BookingPaymentSchedule[];
  isOwner: boolean;
};

const INPUT_CLASS =
  "w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white outline-none transition focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20";

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
  const date = new Date(`${value}T00:00:00`);

  return Number.isNaN(date.getTime())
    ? "—"
    : new Intl.DateTimeFormat("en-IN", {
      dateStyle: "medium",
      timeZone: "Asia/Kolkata",
    }).format(date);
}

function formatLabel(value: string): string {
  return value.replaceAll("_", " ").replace(/\b\w/g, (character) => character.toUpperCase());
}

function statusClass(value: string): string {
  if (value === "paid") return "border-emerald-500/40 bg-emerald-500/10 text-emerald-200";
  if (value === "overdue") return "border-red-500/40 bg-red-500/10 text-red-200";
  if (value === "partially_paid") return "border-amber-500/40 bg-amber-500/10 text-amber-200";
  return "border-slate-700 bg-slate-800 text-slate-300";
}

function FieldError({ fieldName, errors }: { fieldName: string; errors: DealOSFieldErrors }) {
  const messages = errors[fieldName] ?? [];

  return messages.length === 0 ? null : (
    <div className="mt-2 space-y-1">
      {messages.map((message) => <p key={message} className="text-xs text-red-300">{message}</p>)}
    </div>
  );
}

function ActionMessage({ state }: { state: DealOSActionState }) {
  if (state.status === "idle" || !state.message) return null;

  const className = state.status === "success"
    ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-200"
    : "border-red-500/40 bg-red-500/10 text-red-200";

  return <p aria-live="polite" className={`rounded-xl border px-4 py-3 text-sm ${className}`}>{state.message}</p>;
}

export default function BookingPaymentSchedulePanel({
  dealId,
  bookingId,
  currencyCode,
  schedules,
  isOwner,
}: BookingPaymentSchedulePanelProps) {
  const [createState, createAction, isCreatePending] = useActionState(
    createBookingPaymentScheduleAction,
    INITIAL_DEALOS_ACTION_STATE,
  );
  const [recordState, recordAction, isRecordPending] = useActionState(
    recordBookingSchedulePaymentAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  const totalDue = schedules.reduce((total, schedule) => total + schedule.amountDue, 0);
  const totalReceived = schedules.reduce((total, schedule) => total + schedule.amountReceived, 0);
  const outstanding = Math.max(totalDue - totalReceived, 0);
  const openSchedules = schedules.filter((schedule) => !["paid", "cancelled"].includes(schedule.scheduleStatus));

  return (
    <section className="rounded-3xl border border-cyan-500/25 bg-cyan-500/5 p-6 sm:p-8">
      <div className="flex flex-col justify-between gap-4 sm:flex-row sm:items-start">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-300">Post-sale collections</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">Payment schedule & outstanding</h2>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
            Confirmed booking ke installments, received amount aur remaining collection ko ek audited owner view mein track karein.
          </p>
        </div>
        <span className="rounded-full border border-cyan-400/40 px-3 py-1 text-xs font-semibold text-cyan-200">Booking {bookingId.slice(0, 8)}</span>
      </div>

      <dl className="mt-7 grid gap-4 sm:grid-cols-3">
        <div className="rounded-2xl border border-slate-800 bg-slate-950/70 p-4"><dt className="text-xs uppercase tracking-wider text-slate-500">Scheduled</dt><dd className="mt-2 text-2xl font-bold text-white">{formatCurrency(totalDue, currencyCode)}</dd></div>
        <div className="rounded-2xl border border-slate-800 bg-slate-950/70 p-4"><dt className="text-xs uppercase tracking-wider text-slate-500">Received</dt><dd className="mt-2 text-2xl font-bold text-emerald-300">{formatCurrency(totalReceived, currencyCode)}</dd></div>
        <div className="rounded-2xl border border-slate-800 bg-slate-950/70 p-4"><dt className="text-xs uppercase tracking-wider text-slate-500">Outstanding</dt><dd className="mt-2 text-2xl font-bold text-amber-300">{formatCurrency(outstanding, currencyCode)}</dd></div>
      </dl>

      {schedules.length === 0 ? (
        <div className="mt-6 rounded-2xl border border-dashed border-slate-700 bg-slate-950/40 px-5 py-8 text-center text-sm text-slate-400">No payment installments have been scheduled yet.</div>
      ) : (
        <div className="mt-6 overflow-x-auto rounded-2xl border border-slate-800">
          <table className="min-w-full text-left text-sm">
            <thead className="bg-slate-950/80 text-xs uppercase tracking-wider text-slate-500"><tr><th className="px-4 py-3">Installment</th><th className="px-4 py-3">Due</th><th className="px-4 py-3">Due amount</th><th className="px-4 py-3">Received</th><th className="px-4 py-3">Outstanding</th><th className="px-4 py-3">Status</th></tr></thead>
            <tbody className="divide-y divide-slate-800 bg-slate-950/40">
              {schedules.map((schedule) => <tr key={schedule.id}><td className="px-4 py-4"><p className="font-semibold text-slate-200">#{schedule.sequenceNumber} · {formatLabel(schedule.paymentType)}</p>{schedule.notes ? <p className="mt-1 max-w-xs text-xs text-slate-500">{schedule.notes}</p> : null}</td><td className="px-4 py-4 text-slate-300">{formatDate(schedule.dueDate)}</td><td className="px-4 py-4 text-slate-200">{formatCurrency(schedule.amountDue, currencyCode)}</td><td className="px-4 py-4 text-emerald-300">{formatCurrency(schedule.amountReceived, currencyCode)}</td><td className="px-4 py-4 text-amber-300">{formatCurrency(Math.max(schedule.amountDue - schedule.amountReceived, 0), currencyCode)}</td><td className="px-4 py-4"><span className={`inline-flex rounded-full border px-3 py-1 text-xs font-semibold ${statusClass(schedule.scheduleStatus)}`}>{formatLabel(schedule.scheduleStatus)}</span></td></tr>)}
            </tbody>
          </table>
        </div>
      )}

      {isOwner ? (
        <div className="mt-7 grid gap-6 xl:grid-cols-2">
          <form action={createAction} noValidate className="space-y-4 rounded-2xl border border-cyan-500/25 bg-slate-950/50 p-5">
            <input type="hidden" name="dealId" value={dealId} /><input type="hidden" name="bookingId" value={bookingId} />
            <div><h3 className="font-semibold text-white">Add installment</h3><p className="mt-1 text-xs leading-5 text-slate-400">Schedule banne se payment collect nahi hota.</p></div>
            <div className="grid gap-4 sm:grid-cols-2"><div><label htmlFor="scheduleDueDate" className="mb-2 block text-sm text-slate-300">Due date</label><input id="scheduleDueDate" name="dueDate" type="date" required className={INPUT_CLASS} /><FieldError fieldName="dueDate" errors={createState.fieldErrors} /></div><div><label htmlFor="scheduleAmountDue" className="mb-2 block text-sm text-slate-300">Amount due</label><input id="scheduleAmountDue" name="amountDue" type="number" min="0.01" step="0.01" required className={INPUT_CLASS} placeholder="0.00" /><FieldError fieldName="amountDue" errors={createState.fieldErrors} /></div></div>
            <div><label htmlFor="schedulePaymentType" className="mb-2 block text-sm text-slate-300">Installment type</label><select id="schedulePaymentType" name="paymentType" defaultValue="installment" className={INPUT_CLASS}><option value="installment">Installment</option><option value="booking_amount">Booking amount</option><option value="registration">Registration</option><option value="stamp_duty">Stamp duty</option><option value="maintenance">Maintenance</option><option value="club_charge">Club charge</option><option value="parking">Parking</option><option value="tax">Tax</option><option value="other">Other</option></select></div>
            <div><label htmlFor="scheduleNotes" className="mb-2 block text-sm text-slate-300">Notes <span className="text-slate-500">(optional)</span></label><textarea id="scheduleNotes" name="notes" maxLength={1000} className={INPUT_CLASS} placeholder="Payment plan or collection context" /></div>
            <FieldError fieldName="dealId" errors={createState.fieldErrors} /><ActionMessage state={createState} />
            <button type="submit" disabled={isCreatePending} className="rounded-xl bg-cyan-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-60">{isCreatePending ? "Scheduling..." : "Add payment installment"}</button>
          </form>

          <form action={recordAction} noValidate className="space-y-4 rounded-2xl border border-emerald-500/25 bg-slate-950/50 p-5">
            <input type="hidden" name="dealId" value={dealId} /><input type="hidden" name="bookingId" value={bookingId} />
            <div><h3 className="font-semibold text-white">Record received payment</h3><p className="mt-1 text-xs leading-5 text-slate-400">Receipt reference ke saath booking payment ledger mein payment record hoga.</p></div>
            <div><label htmlFor="scheduleId" className="mb-2 block text-sm text-slate-300">Open installment</label><select id="scheduleId" name="scheduleId" required defaultValue="" className={INPUT_CLASS}><option value="" disabled>Select installment</option>{openSchedules.map((schedule) => <option key={schedule.id} value={schedule.id}>#{schedule.sequenceNumber} · {formatLabel(schedule.paymentType)} · {formatCurrency(Math.max(schedule.amountDue - schedule.amountReceived, 0), currencyCode)} remaining</option>)}</select><FieldError fieldName="scheduleId" errors={recordState.fieldErrors} /></div>
            <div className="grid gap-4 sm:grid-cols-2"><div><label htmlFor="receivedAmount" className="mb-2 block text-sm text-slate-300">Amount received</label><input id="receivedAmount" name="amount" type="number" min="0.01" step="0.01" required className={INPUT_CLASS} placeholder="0.00" /><FieldError fieldName="amount" errors={recordState.fieldErrors} /></div><div><label htmlFor="receivedPaymentDate" className="mb-2 block text-sm text-slate-300">Payment date & time</label><input id="receivedPaymentDate" name="paymentDate" type="datetime-local" required className={INPUT_CLASS} /><FieldError fieldName="paymentDate" errors={recordState.fieldErrors} /></div></div>
            <div className="grid gap-4 sm:grid-cols-2"><div><label htmlFor="receivedReference" className="mb-2 block text-sm text-slate-300">Payment reference</label><input id="receivedReference" name="paymentReference" required maxLength={200} className={INPUT_CLASS} placeholder="UPI / bank / receipt reference" /><FieldError fieldName="paymentReference" errors={recordState.fieldErrors} /></div><div><label htmlFor="receivedMode" className="mb-2 block text-sm text-slate-300">Payment mode</label><select id="receivedMode" name="paymentMode" required defaultValue="" className={INPUT_CLASS}><option value="" disabled>Select mode</option><option value="upi">UPI</option><option value="bank_transfer">Bank transfer</option><option value="cheque">Cheque</option><option value="payment_gateway">Payment gateway</option><option value="cash">Cash</option><option value="loan_disbursement">Loan disbursement</option><option value="other">Other</option></select><FieldError fieldName="paymentMode" errors={recordState.fieldErrors} /></div></div>
            <div><label htmlFor="receivedNotes" className="mb-2 block text-sm text-slate-300">Notes <span className="text-slate-500">(optional)</span></label><textarea id="receivedNotes" name="notes" maxLength={1000} className={INPUT_CLASS} placeholder="Collection or receipt context" /></div>
            <ActionMessage state={recordState} />
            <button type="submit" disabled={isRecordPending || openSchedules.length === 0} className="rounded-xl bg-emerald-400 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-emerald-300 disabled:cursor-not-allowed disabled:opacity-60">{isRecordPending ? "Recording..." : "Record scheduled payment"}</button>
          </form>
        </div>
      ) : null}
    </section>
  );
}
