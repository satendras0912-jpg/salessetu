import "server-only";

import { createClient } from "@/lib/supabase/server";

export type BookingPaymentSchedule = {
  id: string;
  bookingId: string;
  sequenceNumber: number;
  paymentType: string;
  dueDate: string;
  amountDue: number;
  amountReceived: number;
  scheduleStatus: string;
  notes: string | null;
  paidAt: string | null;
};

type ScheduleRow = {
  id: string;
  booking_id: string;
  sequence_number: number;
  payment_type: string;
  due_date: string;
  amount_due: string | number;
  amount_received: string | number;
  schedule_status: string;
  notes: string | null;
  paid_at: string | null;
};

type PaymentScheduleReadResult =
  | { ok: true; data: BookingPaymentSchedule[] }
  | { ok: false; message: string };

function toAmount(value: string | number): number {
  const parsed = Number(value);

  return Number.isFinite(parsed) ? parsed : 0;
}

function getEffectiveScheduleStatus(
  scheduleStatus: string,
  dueDate: string,
): string {
  if (
    (scheduleStatus === "pending" || scheduleStatus === "partially_paid") &&
    dueDate < new Date().toISOString().slice(0, 10)
  ) {
    return "overdue";
  }

  return scheduleStatus;
}

function toSummary(row: ScheduleRow): BookingPaymentSchedule {
  return {
    id: row.id,
    bookingId: row.booking_id,
    sequenceNumber: row.sequence_number,
    paymentType: row.payment_type,
    dueDate: row.due_date,
    amountDue: toAmount(row.amount_due),
    amountReceived: toAmount(row.amount_received),
    scheduleStatus: getEffectiveScheduleStatus(
      row.schedule_status,
      row.due_date,
    ),
    notes: row.notes,
    paidAt: row.paid_at,
  };
}

export async function getBookingPaymentSchedules(
  organizationId: string,
  bookingId: string | null,
): Promise<PaymentScheduleReadResult> {
  if (!bookingId) {
    return { ok: true, data: [] };
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("booking_payment_schedules")
    .select(
      "id, booking_id, sequence_number, payment_type, due_date, amount_due, amount_received, schedule_status, notes, paid_at",
    )
    .eq("organization_id", organizationId)
    .eq("booking_id", bookingId)
    .order("due_date", { ascending: true })
    .order("sequence_number", { ascending: true });

  if (error) {
    return {
      ok: false,
      message: error.message || "Booking payment schedules could not be loaded.",
    };
  }

  return {
    ok: true,
    data: ((data ?? []) as ScheduleRow[]).map(toSummary),
  };
}
