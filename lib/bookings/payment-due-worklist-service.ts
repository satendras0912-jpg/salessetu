import "server-only";

import { createClient } from "@/lib/supabase/server";

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
};

type BookingRow = {
  id: string;
  booking_number: string;
  project_name: string;
  unit_number: string | null;
  booking_currency: string;
  booking_status: string;
  payment_status: string;
  lead_id: string;
};

type DealRow = {
  id: string;
  booking_id: string;
  status: string;
};

type LeadRow = {
  id: string;
  first_name: string | null;
  last_name: string | null;
  phone: string | null;
};

export type PaymentDueWorklistItem = {
  scheduleId: string;
  dealId: string | null;
  bookingId: string;
  bookingNumber: string;
  projectName: string;
  unitNumber: string | null;
  customerName: string;
  customerPhone: string | null;
  currencyCode: string;
  sequenceNumber: number;
  paymentType: string;
  dueDate: string;
  amountDue: number;
  amountReceived: number;
  outstanding: number;
  effectiveStatus: "pending" | "partially_paid" | "overdue";
  notes: string | null;
};

export type PaymentDueWorklist = {
  items: PaymentDueWorklistItem[];
  metrics: {
    open: number;
    overdue: number;
    dueToday: number;
    dueNextSevenDays: number;
    outstanding: number;
  };
  today: string;
};

function toAmount(value: string | number): number {
  const parsed = Number(value);

  return Number.isFinite(parsed) ? parsed : 0;
}

function getKolkataDate(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));

  return `${values.year}-${values.month}-${values.day}`;
}

function addDays(date: string, days: number): string {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);

  return value.toISOString().slice(0, 10);
}

function customerName(lead: LeadRow | undefined): string {
  const name = [lead?.first_name, lead?.last_name]
    .filter(Boolean)
    .join(" ")
    .trim();

  return name || "Unnamed customer";
}

export async function getPaymentDueWorklist(
  organizationId: string,
): Promise<PaymentDueWorklist> {
  const supabase = await createClient();
  const { data: schedulesData, error: schedulesError } = await supabase
    .from("booking_payment_schedules")
    .select("id,booking_id,sequence_number,payment_type,due_date,amount_due,amount_received,schedule_status,notes")
    .eq("organization_id", organizationId)
    .in("schedule_status", ["pending", "partially_paid"])
    .order("due_date", { ascending: true })
    .order("sequence_number", { ascending: true })
    .limit(250);

  if (schedulesError) {
    throw new Error(
      schedulesError.message || "Payment due worklist could not be loaded.",
    );
  }

  const schedules = (schedulesData ?? []) as ScheduleRow[];
  const bookingIds = [...new Set(schedules.map((schedule) => schedule.booking_id))];
  const today = getKolkataDate();

  if (bookingIds.length === 0) {
    return {
      items: [],
      metrics: { open: 0, overdue: 0, dueToday: 0, dueNextSevenDays: 0, outstanding: 0 },
      today,
    };
  }

  const { data: bookingsData, error: bookingsError } = await supabase
    .from("bookings")
    .select("id,booking_number,project_name,unit_number,booking_currency,booking_status,payment_status,lead_id")
    .eq("organization_id", organizationId)
    .in("id", bookingIds);

  if (bookingsError) {
    throw new Error(bookingsError.message || "Bookings could not be loaded.");
  }

  const bookings = (bookingsData ?? []) as BookingRow[];
  const leadIds = [...new Set(bookings.map((booking) => booking.lead_id))];
  const [{ data: dealsData, error: dealsError }, { data: leadsData, error: leadsError }] = await Promise.all([
    supabase
      .from("deals")
      .select("id,booking_id,status")
      .eq("organization_id", organizationId)
      .in("booking_id", bookingIds)
      .is("deleted_at", null),
    supabase
      .from("leads")
      .select("id,first_name,last_name,phone")
      .eq("organization_id", organizationId)
      .in("id", leadIds),
  ]);

  if (dealsError || leadsError) {
    throw new Error(
      dealsError?.message || leadsError?.message || "Collection relationships could not be loaded.",
    );
  }

  const bookingsById = new Map(bookings.map((booking) => [booking.id, booking]));
  const dealsByBookingId = new Map(
    ((dealsData ?? []) as DealRow[]).map((deal) => [deal.booking_id, deal]),
  );
  const leadsById = new Map(
    ((leadsData ?? []) as LeadRow[]).map((lead) => [lead.id, lead]),
  );

  const items = schedules.flatMap((schedule) => {
    const booking = bookingsById.get(schedule.booking_id);

    if (!booking || booking.booking_status !== "confirmed") {
      return [];
    }

    const outstanding = Math.max(
      toAmount(schedule.amount_due) - toAmount(schedule.amount_received),
      0,
    );

    if (outstanding === 0) {
      return [];
    }

    const effectiveStatus = schedule.due_date < today
      ? "overdue"
      : schedule.schedule_status === "partially_paid"
        ? "partially_paid"
        : "pending";
    const deal = dealsByBookingId.get(schedule.booking_id);

    return [{
      scheduleId: schedule.id,
      dealId: deal?.id ?? null,
      bookingId: booking.id,
      bookingNumber: booking.booking_number,
      projectName: booking.project_name,
      unitNumber: booking.unit_number,
      customerName: customerName(leadsById.get(booking.lead_id)),
      customerPhone: leadsById.get(booking.lead_id)?.phone ?? null,
      currencyCode: booking.booking_currency,
      sequenceNumber: schedule.sequence_number,
      paymentType: schedule.payment_type,
      dueDate: schedule.due_date,
      amountDue: toAmount(schedule.amount_due),
      amountReceived: toAmount(schedule.amount_received),
      outstanding,
      effectiveStatus,
      notes: schedule.notes,
    } satisfies PaymentDueWorklistItem];
  });
  const nextSevenDays = addDays(today, 7);

  return {
    items,
    metrics: {
      open: items.length,
      overdue: items.filter((item) => item.effectiveStatus === "overdue").length,
      dueToday: items.filter((item) => item.dueDate === today).length,
      dueNextSevenDays: items.filter(
        (item) => item.dueDate >= today && item.dueDate <= nextSevenDays,
      ).length,
      outstanding: items.reduce((total, item) => total + item.outstanding, 0),
    },
    today,
  };
}
