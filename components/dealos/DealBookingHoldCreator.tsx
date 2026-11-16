"use client";

import {
  useActionState,
  useRef,
} from "react";

import {
  createDealBookingHoldAction,
} from "@/app/dashboard/deals/actions";

import {
  INITIAL_DEALOS_ACTION_STATE,
} from "@/lib/dealos/deal-contract";

type DealBookingHoldCreatorProps = {
  dealId: string;
  updatedAt: string;
  status: string;
  bookingId: string | null;
  isOwner: boolean;
};

function getInputClass(hasError: boolean): string {
  return [
    "w-full rounded-xl border bg-slate-950 px-4 py-3 text-sm text-white outline-none transition focus:border-amber-400 focus:ring-2 focus:ring-amber-400/20",
    hasError
      ? "border-red-500"
      : "border-slate-700",
  ].join(" ");
}

export default function DealBookingHoldCreator({
  dealId,
  updatedAt,
  status,
  bookingId,
  isOwner,
}: DealBookingHoldCreatorProps) {
  const expiryInputRef =
    useRef<HTMLInputElement>(null);
  const expiryUtcInputRef =
    useRef<HTMLInputElement>(null);

  const [
    state,
    action,
    pending,
  ] = useActionState(
    createDealBookingHoldAction,
    INITIAL_DEALOS_ACTION_STATE,
  );

  if (
    !isOwner ||
    status !== "booking_ready" ||
    bookingId
  ) {
    return null;
  }

  function serializeExpiry(): void {
    const source = expiryInputRef.current?.value ?? "";
    const target = expiryUtcInputRef.current;

    if (!target) {
      return;
    }

    const value = new Date(source);
    target.value =
      source && !Number.isNaN(value.getTime())
        ? value.toISOString()
        : "";
  }

  return (
    <section className="rounded-2xl border border-amber-500/30 bg-amber-500/5 p-5 sm:p-6">
      <header>
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-amber-300">
          Owner control
        </p>
        <h3 className="mt-3 text-xl font-semibold text-white">
          Create temporary booking hold
        </h3>
        <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
          Creates a draft Booking Engine record, reserves this deal&apos;s selected
          unit until expiry, and links the booking to this deal in one atomic step.
          No payment, customer contact, routing, or notification is created.
        </p>
      </header>

      <form
        action={action}
        onSubmit={serializeExpiry}
        noValidate
        className="mt-5 grid gap-4 rounded-xl border border-amber-500/20 bg-slate-950/45 p-4 lg:grid-cols-2"
      >
        <input type="hidden" name="dealId" value={dealId} />
        <input
          type="hidden"
          name="expectedUpdatedAt"
          value={updatedAt}
        />
        <input
          ref={expiryUtcInputRef}
          type="hidden"
          name="expiresAtUtc"
        />

        <div>
          <label
            htmlFor="bookingHoldExpiry"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            Hold expiry
          </label>
          <input
            id="bookingHoldExpiry"
            ref={expiryInputRef}
            name="expiresAt"
            type="datetime-local"
            required
            aria-invalid={Boolean(state.fieldErrors.expiresAt)}
            className={getInputClass(Boolean(state.fieldErrors.expiresAt))}
          />
          <p className="mt-2 text-xs text-slate-500">
            Maximum 72 hours from now.
          </p>
          {state.fieldErrors.expiresAt?.map((error) => (
            <p key={error} className="mt-2 text-xs text-red-300">
              {error}
            </p>
          ))}
        </div>

        <div>
          <label
            htmlFor="bookingHoldReason"
            className="mb-2 block text-sm font-medium text-slate-300"
          >
            Hold reason
          </label>
          <textarea
            id="bookingHoldReason"
            name="reservationNotes"
            required
            minLength={3}
            maxLength={500}
            rows={4}
            placeholder="Why is this temporary hold needed?"
            aria-invalid={Boolean(state.fieldErrors.reservationNotes)}
            className={getInputClass(Boolean(state.fieldErrors.reservationNotes))}
          />
          {state.fieldErrors.reservationNotes?.map((error) => (
            <p key={error} className="mt-2 text-xs text-red-300">
              {error}
            </p>
          ))}
        </div>

        {state.message ? (
          <p
            aria-live="polite"
            className="lg:col-span-2 text-sm text-amber-100"
          >
            {state.message}
          </p>
        ) : null}

        <button
          type="submit"
          disabled={pending}
          className="inline-flex w-full items-center justify-center rounded-xl bg-amber-300 px-5 py-3 text-sm font-semibold text-slate-950 transition hover:bg-amber-200 disabled:cursor-not-allowed disabled:opacity-60 lg:col-span-2"
        >
          {pending
            ? "Creating booking hold..."
            : "Create booking hold"}
        </button>
      </form>
    </section>
  );
}
