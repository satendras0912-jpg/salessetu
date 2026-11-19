import { redirect } from "next/navigation";

import DocumentReviewWorklist, {
  type DocumentReviewWorklistView,
} from "@/components/dealos/DocumentReviewWorklist";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import { getBookingDocumentReviewWorklist } from "@/lib/bookings/document-review-worklist-service";

export const dynamic = "force-dynamic";

type DocumentReviewsPageProps = {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
};

function getView(value: string | string[] | undefined): DocumentReviewWorklistView {
  const candidate = Array.isArray(value) ? value[0] : value;

  return candidate === "pending" || candidate === "rejected" || candidate === "due"
    ? candidate
    : "attention";
}

export default async function DocumentReviewsPage({
  searchParams,
}: DocumentReviewsPageProps) {
  const { context } = await requirePermissionAccess({
    allOf: ["deals.view"],
    loginRedirectTo: "/login?next=/dashboard/deals/document-reviews",
    unauthorizedRedirectTo: "/unauthorized",
  });

  if (!context.membership?.isOwner) redirect("/unauthorized");
  if (!context.organization?.id) redirect("/auth-error?reason=organization_context_missing");

  const [items, params] = await Promise.all([
    getBookingDocumentReviewWorklist(context.organization.id),
    searchParams,
  ]);

  return (
    <div className="space-y-8">
      <header className="flex flex-col justify-between gap-5 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">Post-booking compliance</p>
          <h1 className="mt-3 text-3xl font-bold text-white">Document review worklist</h1>
          <p className="mt-3 max-w-3xl text-slate-400">
            Submitted documents, rejections aur due / overdue checklist items ko ek owner queue mein review karein.
          </p>
        </div>
        <div className="rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4">
          <p className="text-xs uppercase tracking-wider text-slate-500">Workspace</p>
          <p className="mt-1 font-semibold text-white">{context.organization.name}</p>
        </div>
      </header>

      <DocumentReviewWorklist items={items} view={getView(params.view)} />
    </div>
  );
}
