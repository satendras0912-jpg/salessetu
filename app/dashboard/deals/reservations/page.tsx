import Link from "next/link";
import { redirect } from "next/navigation";

import ReservationMonitorRefresh from "@/components/dealos/ReservationMonitorRefresh";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type ReservationUnit = {
  unit_number: string;
  unit_status: string;
  sales_status: string;
};

type ReservationBooking = {
  booking_number: string;
  project_name: string;
  booking_status: string;
};

type ReservationRow = {
  id: string;
  inventory_unit_id: string;
  reservation_number: string;
  status: string;
  reserved_at: string;
  expires_at: string | null;
  released_at: string | null;
  release_reason: string | null;
  notes: string | null;
  inventory_units: ReservationUnit | null;
  bookings: ReservationBooking | null;
};

type RawReservationRow = Omit<
  ReservationRow,
  "inventory_units" | "bookings"
> & {
  inventory_units: ReservationUnit | ReservationUnit[] | null;
  bookings: ReservationBooking | ReservationBooking[] | null;
};

type ReservationAlertRow = {
  id: string;
  inventory_reservation_id: string;
  status: string;
  expires_at: string;
  created_at: string;
};

type ReservationEventRow = {
  id: string;
  event_type: string;
  event_reason: string | null;
  occurred_at: string;
  inventory_reservation_id: string;
  bookings: Pick<ReservationBooking, "booking_number"> | null;
};

type RawReservationEventRow = Omit<
  ReservationEventRow,
  "bookings"
> & {
  bookings:
    | Pick<ReservationBooking, "booking_number">
    | Pick<ReservationBooking, "booking_number">[]
    | null;
};

function firstRelatedRow<T>(
  relation: T | T[] | null,
): T | null {
  if (Array.isArray(relation)) {
    return relation[0] ?? null;
  }

  return relation;
}

function formatDateTime(value: string | null): string {
  if (!value) {
    return "Not set";
  }

  return new Intl.DateTimeFormat("en-IN", {
    dateStyle: "medium",
    timeStyle: "short",
    timeZone: "Asia/Kolkata",
  }).format(new Date(value));
}

function relativeDuration(value: string): string {
  const remainingMs = new Date(value).getTime() - Date.now();
  const absoluteMinutes = Math.round(Math.abs(remainingMs) / 60_000);

  if (remainingMs <= 0) {
    return "Expiry processing due";
  }

  if (absoluteMinutes < 60) {
    return `${absoluteMinutes} min remaining`;
  }

  const hours = Math.floor(absoluteMinutes / 60);
  const minutes = absoluteMinutes % 60;

  return `${hours}h ${minutes}m remaining`;
}

function statusClass(status: string): string {
  if (status === "active") {
    return "border-violet-400/50 bg-violet-400/10 text-violet-200";
  }

  if (status === "expired") {
    return "border-amber-400/50 bg-amber-400/10 text-amber-200";
  }

  if (status === "released") {
    return "border-emerald-400/50 bg-emerald-400/10 text-emerald-200";
  }

  if (status === "confirmed") {
    return "border-cyan-400/50 bg-cyan-400/10 text-cyan-200";
  }

  return "border-slate-700 bg-slate-800 text-slate-300";
}

function label(value: string): string {
  return value.replaceAll("_", " ");
}

export default async function ReservationMonitoringPage() {
  const { context } = await requirePermissionAccess({
    allOf: ["inventory.view"],
    loginRedirectTo: "/login?next=/dashboard/deals/reservations",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) {
    redirect("/unauthorized");
  }

  const organizationId = context.organization?.id;

  if (!organizationId) {
    redirect("/auth-error?reason=organization_context_missing");
  }

  const supabase = await createClient();

  const [
    reservationsResponse,
    alertsResponse,
    eventsResponse,
  ] = await Promise.all([
    supabase
      .from("inventory_reservations")
      .select("id,inventory_unit_id,reservation_number,status,reserved_at,expires_at,released_at,release_reason,notes,inventory_units(unit_number,unit_status,sales_status),bookings(booking_number,project_name,booking_status)")
      .eq("organization_id", organizationId)
      .eq("reservation_type", "booking_hold")
      .order("reserved_at", { ascending: false })
      .limit(100),
    supabase
      .from("booking_reservation_alerts")
      .select("id,inventory_reservation_id,status,expires_at,created_at")
      .eq("organization_id", organizationId)
      .eq("status", "open")
      .order("expires_at", { ascending: true })
      .limit(25),
    supabase
      .from("booking_reservation_events")
      .select("id,event_type,event_reason,occurred_at,inventory_reservation_id,bookings(booking_number)")
      .eq("organization_id", organizationId)
      .order("occurred_at", { ascending: false })
      .limit(20),
  ]);

  if (
    reservationsResponse.error ||
    alertsResponse.error ||
    eventsResponse.error
  ) {
    throw new Error(
      "Reservation monitoring could not be loaded. Apply the reservation monitoring migration and verify owner access.",
    );
  }

  const reservations = (
    (reservationsResponse.data ?? []) as RawReservationRow[]
  ).map((reservation) => ({
    ...reservation,
    inventory_units: firstRelatedRow(reservation.inventory_units),
    bookings: firstRelatedRow(reservation.bookings),
  }));
  const alerts = (alertsResponse.data ?? []) as ReservationAlertRow[];
  const events = (
    (eventsResponse.data ?? []) as RawReservationEventRow[]
  ).map((event) => ({
    ...event,
    bookings: firstRelatedRow(event.bookings),
  }));
  const activeReservations = reservations.filter(
    (reservation) => reservation.status === "active",
  );
  const activeUnitIds = new Set(
    activeReservations.map((reservation) => reservation.inventory_unit_id),
  );
  const releasedToday = reservations.filter(
    (reservation) =>
      ["expired", "released"].includes(reservation.status) &&
      reservation.released_at &&
      new Date(reservation.released_at).toDateString() === new Date().toDateString(),
  );
  const reconciliationIssues = reservations.filter((reservation) => {
    if (!['expired', 'released'].includes(reservation.status)) {
      return false;
    }

    if (activeUnitIds.has(reservation.inventory_unit_id)) {
      return false;
    }

    const unit = reservation.inventory_units;

    return unit?.unit_status !== "available" || unit.sales_status !== "open";
  });
  const reservationById = new Map(
    reservations.map((reservation) => [reservation.id, reservation]),
  );

  return (
    <div className="space-y-8">
      <header className="flex flex-col justify-between gap-6 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            Booking control
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
            Reservation Monitoring &amp; Alerts
          </h1>
          <p className="mt-3 max-w-3xl text-base leading-7 text-slate-400">
            Active booking holds, pre-expiry owner alerts, release audit aur unit reconciliation ko ek jagah monitor karein.
          </p>
          <div className="mt-4">
            <ReservationMonitorRefresh organizationId={organizationId} />
          </div>
        </div>

        <Link
          href="/dashboard/deals"
          className="inline-flex items-center justify-center rounded-xl border border-slate-700 px-5 py-3 text-sm font-semibold text-slate-100 transition hover:border-cyan-400 hover:text-cyan-200"
        >
          Back to deals
        </Link>
      </header>

      <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        {[
          ["Active holds", activeReservations.length, "violet"],
          ["Expiring within 30 min", alerts.length, "amber"],
          ["Released today", releasedToday.length, "emerald"],
          ["Reconciliation issues", reconciliationIssues.length, reconciliationIssues.length ? "rose" : "emerald"],
        ].map(([title, count, tone]) => (
          <article
            key={String(title)}
            className={[
              "rounded-2xl border bg-slate-900 p-5",
              tone === "rose" ? "border-rose-500/40" : "border-slate-800",
            ].join(" ")}
          >
            <p className="text-sm text-slate-400">{title}</p>
            <p className={[
              "mt-3 text-4xl font-bold",
              tone === "amber" ? "text-amber-300" : tone === "emerald" ? "text-emerald-300" : tone === "rose" ? "text-rose-300" : "text-violet-300",
            ].join(" ")}>{count}</p>
          </article>
        ))}
      </section>

      <section className="rounded-2xl border border-amber-500/30 bg-amber-500/5 p-6">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="text-xl font-semibold text-amber-100">Owner alerts</h2>
            <p className="mt-1 text-sm text-slate-400">Alerts are created once a booking hold enters its final 30 minutes.</p>
          </div>
          <span className="rounded-full border border-amber-400/50 px-3 py-1 text-xs font-semibold text-amber-200">Owner only</span>
        </div>

        {alerts.length ? (
          <ul className="mt-5 divide-y divide-amber-500/15 rounded-xl border border-amber-500/20 bg-slate-950/40">
            {alerts.map((alert) => {
              const reservation = reservationById.get(alert.inventory_reservation_id);
              return (
                <li key={alert.id} className="flex flex-col gap-2 px-4 py-4 sm:flex-row sm:items-center sm:justify-between">
                  <div>
                    <p className="font-semibold text-white">
                      {reservation?.inventory_units?.unit_number ?? "Inventory unit"} · {reservation?.bookings?.project_name ?? "Booking hold"}
                    </p>
                    <p className="mt-1 text-sm text-slate-400">
                      {reservation?.bookings?.booking_number ?? reservation?.reservation_number ?? "Reservation"} expires {formatDateTime(alert.expires_at)}
                    </p>
                  </div>
                  <span className="font-semibold text-amber-200">{relativeDuration(alert.expires_at)}</span>
                </li>
              );
            })}
          </ul>
        ) : (
          <p className="mt-5 rounded-xl border border-slate-800 bg-slate-950/40 px-4 py-5 text-sm text-slate-400">
            No booking hold is inside the 30-minute alert window.
          </p>
        )}
      </section>

      <section className="rounded-2xl border border-slate-800 bg-slate-900 p-6">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h2 className="text-xl font-semibold text-white">Active booking holds</h2>
            <p className="mt-1 text-sm text-slate-400">Expiry is processed automatically; release remains owner-controlled while a hold is active.</p>
          </div>
          <span className="text-sm text-slate-500">{activeReservations.length} active</span>
        </div>

        {activeReservations.length ? (
          <div className="mt-5 overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="border-b border-slate-800 text-xs uppercase tracking-wider text-slate-500">
                <tr>
                  <th className="px-3 py-3">Unit</th>
                  <th className="px-3 py-3">Booking</th>
                  <th className="px-3 py-3">Expiry</th>
                  <th className="px-3 py-3">State</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800">
                {activeReservations.map((reservation) => (
                  <tr key={reservation.id}>
                    <td className="px-3 py-4">
                      <p className="font-semibold text-white">{reservation.inventory_units?.unit_number ?? "Unavailable"}</p>
                      <p className="mt-1 text-xs text-slate-500">{reservation.bookings?.project_name ?? "Project not set"}</p>
                    </td>
                    <td className="px-3 py-4 text-slate-300">{reservation.bookings?.booking_number ?? reservation.reservation_number}</td>
                    <td className="px-3 py-4">
                      <p className="text-slate-200">{formatDateTime(reservation.expires_at)}</p>
                      {reservation.expires_at ? <p className="mt-1 text-xs text-amber-200">{relativeDuration(reservation.expires_at)}</p> : null}
                    </td>
                    <td className="px-3 py-4"><span className={`rounded-full border px-3 py-1 text-xs font-semibold ${statusClass(reservation.status)}`}>{label(reservation.status)}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className="mt-5 text-sm text-slate-400">There are no active booking holds.</p>
        )}
      </section>

      <section className="grid gap-6 xl:grid-cols-2">
        <article className="rounded-2xl border border-slate-800 bg-slate-900 p-6">
          <h2 className="text-xl font-semibold text-white">Unit reconciliation</h2>
          <p className="mt-1 text-sm text-slate-400">Expired or released holds must return the unit to available / open unless another active hold exists.</p>
          {reconciliationIssues.length ? (
            <ul className="mt-5 space-y-3">
              {reconciliationIssues.map((reservation) => (
                <li key={reservation.id} className="rounded-xl border border-rose-500/30 bg-rose-500/5 p-4">
                  <p className="font-semibold text-rose-100">{reservation.inventory_units?.unit_number ?? "Inventory unit"} needs review</p>
                  <p className="mt-1 text-sm text-slate-300">Hold is {reservation.status}, but unit is {reservation.inventory_units?.unit_status ?? "unknown"} / {reservation.inventory_units?.sales_status ?? "unknown"}.</p>
                </li>
              ))}
            </ul>
          ) : (
            <p className="mt-5 rounded-xl border border-emerald-500/25 bg-emerald-500/5 px-4 py-5 text-sm text-emerald-200">All released and expired booking holds reconcile with current unit availability.</p>
          )}
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900 p-6">
          <h2 className="text-xl font-semibold text-white">Release audit</h2>
          <p className="mt-1 text-sm text-slate-400">Latest reservation lifecycle events for this workspace.</p>
          {events.length ? (
            <ul className="mt-5 space-y-3">
              {events.map((event) => (
                <li key={event.id} className="rounded-xl border border-slate-800 bg-slate-950/40 p-4">
                  <div className="flex items-center justify-between gap-3">
                    <p className="font-semibold text-white">{label(event.event_type)}</p>
                    <time className="text-xs text-slate-500">{formatDateTime(event.occurred_at)}</time>
                  </div>
                  <p className="mt-1 text-sm text-slate-300">{event.bookings?.booking_number ?? "Booking"}{event.event_reason ? ` · ${event.event_reason}` : ""}</p>
                </li>
              ))}
            </ul>
          ) : (
            <p className="mt-5 text-sm text-slate-400">No reservation audit events yet.</p>
          )}
        </article>
      </section>
    </div>
  );
}
