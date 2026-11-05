"use client";

import {
  useActionState,
  useEffect,
} from "react";
import { useRouter } from "next/navigation";

import {
  decideLeadInventoryMatchAction,
  INITIAL_INVENTORY_MATCH_REVIEW_STATE,
} from "@/app/dashboard/leads/[leadId]/inventory-match-actions";

type InventoryMatchReviewFormProps = {
  leadId: string;
  inventoryUnitId: string;
  inventoryCode: string;
  initialReason: string;
  initialNotes: string;
};

export default function InventoryMatchReviewForm({
  leadId,
  inventoryUnitId,
  inventoryCode,
  initialReason,
  initialNotes,
}: InventoryMatchReviewFormProps) {
  const router = useRouter();
  const [state, formAction, isPending] = useActionState(
    decideLeadInventoryMatchAction,
    INITIAL_INVENTORY_MATCH_REVIEW_STATE,
  );

  useEffect(() => {
    if (state.status === "success") {
      router.refresh();
    }
  }, [router, state.status]);

  return (
    <form action={formAction} className="mt-4 space-y-3">
      <input name="leadId" type="hidden" value={leadId} />
      <input name="inventoryUnitId" type="hidden" value={inventoryUnitId} />
      <input
        aria-label={`Review reason for ${inventoryCode}`}
        className="w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white outline-none placeholder:text-slate-600 focus:border-cyan-400"
        defaultValue={initialReason}
        disabled={isPending}
        maxLength={500}
        minLength={3}
        name="reason"
        placeholder="Why is this unit suitable or not suitable?"
        required
      />
      <textarea
        aria-label={`Internal review note for ${inventoryCode}`}
        className="min-h-20 w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-white outline-none placeholder:text-slate-600 focus:border-cyan-400"
        defaultValue={initialNotes}
        disabled={isPending}
        maxLength={2000}
        name="notes"
        placeholder="Internal note (optional)"
      />
      {state.message ? (
        <p
          role="status"
          className={
            state.status === "success"
              ? "text-sm text-emerald-300"
              : "text-sm text-rose-300"
          }
        >
          {state.message}
        </p>
      ) : null}
      <div className="flex flex-wrap gap-3">
        <button
          className="rounded-xl bg-emerald-500 px-4 py-2 text-sm font-semibold text-slate-950 transition hover:bg-emerald-400 disabled:cursor-not-allowed disabled:opacity-50"
          disabled={isPending}
          name="decision"
          type="submit"
          value="suitable"
        >
          {isPending ? "Saving review..." : "Suitable"}
        </button>
        <button
          className="rounded-xl border border-amber-500/70 px-4 py-2 text-sm font-semibold text-amber-200 transition hover:bg-amber-500/10 disabled:cursor-not-allowed disabled:opacity-50"
          disabled={isPending}
          name="decision"
          type="submit"
          value="not_suitable"
        >
          Not suitable
        </button>
      </div>
    </form>
  );
}
