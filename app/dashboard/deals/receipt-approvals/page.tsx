import { redirect } from "next/navigation";

import ReceiptApprovalQueue from "@/components/dealos/ReceiptApprovalQueue";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import { getPendingBookingPaymentReceiptSubmissions } from "@/lib/bookings/payment-receipt-approval-service";

export const dynamic = "force-dynamic";

export default async function ReceiptApprovalsPage() {
  const { context } = await requirePermissionAccess({
    allOf: ["deals.view"],
    loginRedirectTo: "/login?next=/dashboard/deals/receipt-approvals",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) redirect("/unauthorized");
  if (!context.organization?.id) redirect("/auth-error?reason=organization_context_missing");

  const submissions = await getPendingBookingPaymentReceiptSubmissions(context.organization.id);

  return <div className="space-y-8"><header><p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">Post-sale collections</p><h1 className="mt-3 text-3xl font-bold text-white">Receipt approval queue</h1><p className="mt-3 max-w-3xl text-slate-400">Only owner approval creates a paid booking-ledger entry and updates collection reconciliation. Rejecting a submission leaves all financial totals unchanged.</p></header><section aria-label="Pending receipt approvals"><div className="mb-4 flex items-center justify-between"><h2 className="text-lg font-semibold text-white">Pending receipts</h2><span className="rounded-full border border-amber-500/40 px-3 py-1 text-sm font-semibold text-amber-200">{submissions.length} awaiting review</span></div><ReceiptApprovalQueue items={submissions} /></section></div>;
}
