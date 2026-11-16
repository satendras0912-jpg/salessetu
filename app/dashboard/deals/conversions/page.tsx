import { redirect } from "next/navigation";
import DealConversionApprovalQueue from "@/components/dealos/DealConversionApprovalQueue";
import { getCurrentPermissionContext } from "@/lib/auth/permissions";
import { getPendingDealConversionRequests } from "@/lib/dealos/deal-conversion-service";

export const dynamic = "force-dynamic";

export default async function DealConversionApprovalsPage() {
  const context = await getCurrentPermissionContext();
  if (!context?.isOwner) redirect("/unauthorized");
  const requests = await getPendingDealConversionRequests(context.organizationId);
  return <div className="space-y-6">
    <header><p className="text-xs font-semibold uppercase tracking-[0.3em] text-cyan-400">Owner controls</p><h1 className="mt-3 text-3xl font-semibold text-white">Match-to-Deal approvals</h1><p className="mt-3 max-w-3xl text-sm leading-6 text-slate-300">Approve only a suitable manual inventory match after lead validation and a completed site visit. Approval creates a DealOS deal only; it never reserves inventory, changes routing, or contacts the customer.</p></header>
    <DealConversionApprovalQueue requests={requests} />
  </div>;
}
