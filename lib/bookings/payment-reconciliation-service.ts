import "server-only";

import { createClient } from "@/lib/supabase/server";

type ScheduleRow = {
  id: string;
  booking_id: string;
  sequence_number: number;
  due_date: string;
  amount_due: string | number;
  amount_received: string | number;
  schedule_status: string;
};

type BookingRow = {
  id: string;
  booking_number: string;
  project_name: string;
  unit_number: string | null;
  booking_currency: string;
  booking_status: string;
  lead_id: string;
};

type DealRow = {
  id: string;
  booking_id: string;
  assigned_to: string | null;
};

type AgentRow = {
  user_id: string;
  agent_code: string | null;
  display_name: string | null;
};

type LeadRow = {
  id: string;
  first_name: string | null;
  last_name: string | null;
};

export type ReconciliationAgingBucket = {
  label: "1–7 days" | "8–30 days" | "31+ days";
  count: number;
  outstanding: number;
};

export type ReconciliationProjectRow = {
  projectName: string;
  scheduled: number;
  received: number;
  outstanding: number;
  openInstallments: number;
};

export type ReconciliationAgentRow = {
  agentName: string;
  agentCode: string | null;
  scheduled: number;
  received: number;
  outstanding: number;
  openInstallments: number;
};

export type ReconciliationBookingRow = {
  bookingId: string;
  bookingNumber: string;
  projectName: string;
  unitNumber: string | null;
  customerName: string;
  dealId: string | null;
  agentName: string;
  currencyCode: string;
  scheduled: number;
  received: number;
  outstanding: number;
  nextDueDate: string | null;
  overdueOutstanding: number;
};

export type PaymentReconciliation = {
  today: string;
  metrics: {
    scheduled: number;
    received: number;
    outstanding: number;
    openInstallments: number;
    overdueInstallments: number;
  };
  aging: ReconciliationAgingBucket[];
  projects: ReconciliationProjectRow[];
  agents: ReconciliationAgentRow[];
  bookings: ReconciliationBookingRow[];
};

function amount(value: string | number): number {
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

function daysOverdue(dueDate: string, today: string): number {
  const due = Date.parse(`${dueDate}T00:00:00Z`);
  const current = Date.parse(`${today}T00:00:00Z`);

  return Math.max(0, Math.floor((current - due) / 86_400_000));
}

function nameForLead(lead: LeadRow | undefined): string {
  return [lead?.first_name, lead?.last_name].filter(Boolean).join(" ").trim() || "Unnamed customer";
}

function emptyReconciliation(today: string): PaymentReconciliation {
  return {
    today,
    metrics: { scheduled: 0, received: 0, outstanding: 0, openInstallments: 0, overdueInstallments: 0 },
    aging: [
      { label: "1–7 days", count: 0, outstanding: 0 },
      { label: "8–30 days", count: 0, outstanding: 0 },
      { label: "31+ days", count: 0, outstanding: 0 },
    ],
    projects: [],
    agents: [],
    bookings: [],
  };
}

export async function getPaymentReconciliation(
  organizationId: string,
): Promise<PaymentReconciliation> {
  const supabase = await createClient();
  const today = getKolkataDate();
  const { data: schedulesData, error: schedulesError } = await supabase
    .from("booking_payment_schedules")
    .select("id,booking_id,sequence_number,due_date,amount_due,amount_received,schedule_status")
    .eq("organization_id", organizationId)
    .neq("schedule_status", "cancelled")
    .order("due_date", { ascending: true })
    .order("sequence_number", { ascending: true })
    .limit(1000);

  if (schedulesError) {
    throw new Error(schedulesError.message || "Payment reconciliation could not be loaded.");
  }

  const schedules = (schedulesData ?? []) as ScheduleRow[];
  const bookingIds = [...new Set(schedules.map((schedule) => schedule.booking_id))];

  if (bookingIds.length === 0) return emptyReconciliation(today);

  const { data: bookingsData, error: bookingsError } = await supabase
    .from("bookings")
    .select("id,booking_number,project_name,unit_number,booking_currency,booking_status,lead_id")
    .eq("organization_id", organizationId)
    .eq("booking_status", "confirmed")
    .in("id", bookingIds);

  if (bookingsError) throw new Error(bookingsError.message || "Bookings could not be loaded.");

  const bookings = (bookingsData ?? []) as BookingRow[];
  const confirmedBookingIds = bookings.map((booking) => booking.id);
  if (confirmedBookingIds.length === 0) return emptyReconciliation(today);

  const leadIds = [...new Set(bookings.map((booking) => booking.lead_id))];
  const [{ data: dealsData, error: dealsError }, { data: agentsData, error: agentsError }, { data: leadsData, error: leadsError }] = await Promise.all([
    supabase.from("deals").select("id,booking_id,assigned_to").eq("organization_id", organizationId).in("booking_id", confirmedBookingIds).is("deleted_at", null),
    supabase.from("assignment_agent_profiles").select("user_id,agent_code,display_name").eq("organization_id", organizationId),
    supabase.from("leads").select("id,first_name,last_name").eq("organization_id", organizationId).in("id", leadIds),
  ]);

  if (dealsError || agentsError || leadsError) {
    throw new Error(dealsError?.message || agentsError?.message || leadsError?.message || "Collection relationships could not be loaded.");
  }

  const bookingsById = new Map(bookings.map((booking) => [booking.id, booking]));
  const dealsByBooking = new Map(((dealsData ?? []) as DealRow[]).map((deal) => [deal.booking_id, deal]));
  const agentsByUser = new Map(((agentsData ?? []) as AgentRow[]).map((agent) => [agent.user_id, agent]));
  const leadsById = new Map(((leadsData ?? []) as LeadRow[]).map((lead) => [lead.id, lead]));
  const schedulesByBooking = new Map<string, ScheduleRow[]>();

  for (const schedule of schedules) {
    if (!bookingsById.has(schedule.booking_id)) continue;
    const existing = schedulesByBooking.get(schedule.booking_id) ?? [];
    existing.push(schedule);
    schedulesByBooking.set(schedule.booking_id, existing);
  }

  const projectRows = new Map<string, ReconciliationProjectRow>();
  const agentRows = new Map<string, ReconciliationAgentRow>();
  const aging = emptyReconciliation(today).aging;
  const bookingRows: ReconciliationBookingRow[] = [];
  let scheduled = 0;
  let received = 0;
  let outstanding = 0;
  let openInstallments = 0;
  let overdueInstallments = 0;

  for (const booking of bookings) {
    const bookingSchedules = schedulesByBooking.get(booking.id) ?? [];
    if (bookingSchedules.length === 0) continue;

    const deal = dealsByBooking.get(booking.id);
    const agent = deal?.assigned_to ? agentsByUser.get(deal.assigned_to) : undefined;
    const agentName = agent?.display_name || (deal?.assigned_to ? "Unavailable team member" : "Unassigned");
    const bookingScheduled = bookingSchedules.reduce((total, schedule) => total + amount(schedule.amount_due), 0);
    const bookingReceived = bookingSchedules.reduce((total, schedule) => total + amount(schedule.amount_received), 0);
    const bookingOutstanding = Math.max(bookingScheduled - bookingReceived, 0);
    const openSchedules = bookingSchedules.filter((schedule) => amount(schedule.amount_due) > amount(schedule.amount_received));
    const nextDueDate = openSchedules.map((schedule) => schedule.due_date).sort()[0] ?? null;
    const bookingOverdue = openSchedules.filter((schedule) => schedule.due_date < today).reduce((total, schedule) => total + amount(schedule.amount_due) - amount(schedule.amount_received), 0);

    scheduled += bookingScheduled;
    received += bookingReceived;
    outstanding += bookingOutstanding;
    openInstallments += openSchedules.length;

    for (const schedule of openSchedules) {
      if (schedule.due_date >= today) continue;
      overdueInstallments += 1;
      const scheduleOutstanding = Math.max(amount(schedule.amount_due) - amount(schedule.amount_received), 0);
      const overdueDays = daysOverdue(schedule.due_date, today);
      const bucket = overdueDays <= 7 ? aging[0] : overdueDays <= 30 ? aging[1] : aging[2];
      bucket.count += 1;
      bucket.outstanding += scheduleOutstanding;
    }

    const project = projectRows.get(booking.project_name) ?? {
      projectName: booking.project_name,
      scheduled: 0,
      received: 0,
      outstanding: 0,
      openInstallments: 0,
    };
    project.scheduled += bookingScheduled;
    project.received += bookingReceived;
    project.outstanding += bookingOutstanding;
    project.openInstallments += openSchedules.length;
    projectRows.set(booking.project_name, project);

    const agentKey = deal?.assigned_to ?? "unassigned";
    const agentRow = agentRows.get(agentKey) ?? {
      agentName,
      agentCode: agent?.agent_code ?? null,
      scheduled: 0,
      received: 0,
      outstanding: 0,
      openInstallments: 0,
    };
    agentRow.scheduled += bookingScheduled;
    agentRow.received += bookingReceived;
    agentRow.outstanding += bookingOutstanding;
    agentRow.openInstallments += openSchedules.length;
    agentRows.set(agentKey, agentRow);

    bookingRows.push({
      bookingId: booking.id,
      bookingNumber: booking.booking_number,
      projectName: booking.project_name,
      unitNumber: booking.unit_number,
      customerName: nameForLead(leadsById.get(booking.lead_id)),
      dealId: deal?.id ?? null,
      agentName,
      currencyCode: booking.booking_currency,
      scheduled: bookingScheduled,
      received: bookingReceived,
      outstanding: bookingOutstanding,
      nextDueDate,
      overdueOutstanding: bookingOverdue,
    });
  }

  return {
    today,
    metrics: { scheduled, received, outstanding, openInstallments, overdueInstallments },
    aging,
    projects: [...projectRows.values()].sort((left, right) => right.outstanding - left.outstanding || left.projectName.localeCompare(right.projectName)),
    agents: [...agentRows.values()].sort((left, right) => right.outstanding - left.outstanding || left.agentName.localeCompare(right.agentName)),
    bookings: bookingRows.sort((left, right) => right.outstanding - left.outstanding || (left.nextDueDate ?? "9999-12-31").localeCompare(right.nextDueDate ?? "9999-12-31")).slice(0, 100),
  };
}
