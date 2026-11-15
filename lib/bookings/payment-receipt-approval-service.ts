import "server-only";

import { createClient } from "@/lib/supabase/server";

export type BookingPaymentReceiptSubmission = {
  id: string;
  organizationId: string;
  dealId: string;
  bookingId: string;
  scheduleId: string;
  amount: number;
  paymentReference: string;
  paymentMode: string;
  paymentDate: string;
  notes: string | null;
  status: "pending" | "approved" | "rejected";
  submittedAt: string;
  decisionReason: string | null;
};

type ReceiptSubmissionRow = {
  id: string;
  organization_id: string;
  deal_id: string;
  booking_id: string;
  schedule_id: string;
  amount: string | number;
  payment_reference: string;
  payment_mode: string;
  payment_date: string;
  notes: string | null;
  status: "pending" | "approved" | "rejected";
  submitted_at: string;
  decision_reason: string | null;
};

function amount(value: string | number): number {
  const result = Number(value);
  return Number.isFinite(result) ? result : 0;
}

function mapRow(row: ReceiptSubmissionRow): BookingPaymentReceiptSubmission {
  return {
    id: row.id,
    organizationId: row.organization_id,
    dealId: row.deal_id,
    bookingId: row.booking_id,
    scheduleId: row.schedule_id,
    amount: amount(row.amount),
    paymentReference: row.payment_reference,
    paymentMode: row.payment_mode,
    paymentDate: row.payment_date,
    notes: row.notes,
    status: row.status,
    submittedAt: row.submitted_at,
    decisionReason: row.decision_reason,
  };
}

export async function getBookingPaymentReceiptSubmissions(
  organizationId: string,
  bookingId: string | null,
): Promise<BookingPaymentReceiptSubmission[]> {
  if (!bookingId) return [];

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("booking_payment_receipt_submissions")
    .select("id,organization_id,deal_id,booking_id,schedule_id,amount,payment_reference,payment_mode,payment_date,notes,status,submitted_at,decision_reason")
    .eq("organization_id", organizationId)
    .eq("booking_id", bookingId)
    .order("submitted_at", { ascending: false });

  if (error) throw new Error(error.message || "Receipt submissions could not be loaded.");

  return ((data ?? []) as ReceiptSubmissionRow[]).map(mapRow);
}

export async function getPendingBookingPaymentReceiptSubmissions(
  organizationId: string,
): Promise<BookingPaymentReceiptSubmission[]> {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("booking_payment_receipt_submissions")
    .select("id,organization_id,deal_id,booking_id,schedule_id,amount,payment_reference,payment_mode,payment_date,notes,status,submitted_at,decision_reason")
    .eq("organization_id", organizationId)
    .eq("status", "pending")
    .order("submitted_at", { ascending: true });

  if (error) throw new Error(error.message || "Pending receipt submissions could not be loaded.");

  return ((data ?? []) as ReceiptSubmissionRow[]).map(mapRow);
}
