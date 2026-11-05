"use client";

import { useActionState } from "react";
import { decideDealConversionRequestAction } from "@/app/dashboard/deals/actions";
import { INITIAL_DEALOS_ACTION_STATE } from "@/lib/dealos/deal-contract";
import type { PendingDealConversionRequest } from "@/lib/dealos/deal-conversion-service";

export default function DealConversionApprovalQueue({ requests }: { requests: PendingDealConversionRequest[] }) {
  if (!requests.length) return <p className="rounded-2xl border border-slate-800 bg-slate-950/60 p-5 text-sm text-slate-400">No pending owner approvals.</p>;

  return <div className="space-y-5">{requests.map((request) => <RequestCard key={request.id} request={request} />)}</div>;
}

function RequestCard({ request }: { request: PendingDealConversionRequest }) {
  const [state, action, pending] = useActionState(decideDealConversionRequestAction, INITIAL_DEALOS_ACTION_STATE);
  return <form action={action} className="rounded-2xl border border-amber-400/30 bg-amber-400/5 p-5">
    <input type="hidden" name="requestId" value={request.id} />
    <p className="font-semibold text-white">Lead conversion request</p>
    <dl className="mt-3 grid gap-2 text-sm text-slate-300 sm:grid-cols-2">
      <div><dt className="text-slate-500">Lead</dt><dd>{request.leadId}</dd></div>
      <div><dt className="text-slate-500">Matched inventory</dt><dd>{request.inventoryUnitId}</dd></div>
      <div><dt className="text-slate-500">Completed visit</dt><dd>{request.siteVisitId}</dd></div>
      <div><dt className="text-slate-500">Requested</dt><dd>{new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Kolkata" }).format(new Date(request.requestedAt))}</dd></div>
    </dl>
    {request.notes ? <p className="mt-4 rounded-xl bg-slate-950/60 p-3 text-sm text-slate-300">{request.notes}</p> : null}
    <label className="mt-4 block text-sm font-medium text-slate-200">Owner decision reason
      <textarea required name="reason" minLength={3} maxLength={500} rows={3} className="mt-2 w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white" placeholder="Why should this conversion be approved or rejected?" />
    </label>
    {state.status !== "idle" && state.message ? <p className={state.status === "success" ? "mt-3 text-sm text-emerald-300" : "mt-3 text-sm text-red-300"}>{state.message}</p> : null}
    <div className="mt-4 flex gap-3">
      <button disabled={pending} name="decision" value="approved" className="rounded-xl bg-emerald-400 px-4 py-2 text-sm font-semibold text-slate-950 disabled:opacity-60">Approve & create deal</button>
      <button disabled={pending} name="decision" value="rejected" className="rounded-xl border border-rose-400/60 px-4 py-2 text-sm font-semibold text-rose-200 disabled:opacity-60">Reject request</button>
    </div>
  </form>;
}
