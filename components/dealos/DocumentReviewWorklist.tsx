import Link from "next/link";

import type { BookingDocumentReviewWorklistItem } from "@/lib/bookings/document-review-worklist-service";

export type DocumentReviewWorklistView = "attention" | "pending" | "rejected" | "due";

const STATUS_LABEL: Record<string, string> = {
  not_started: "Not started",
  requested: "Requested",
  submitted: "Submitted",
  under_review: "Under review",
  rejected: "Rejected",
};

function formatDate(value: string | null): string {
  if (!value) return "No due date";

  return new Intl.DateTimeFormat("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    timeZone: "Asia/Kolkata",
  }).format(new Date(`${value}T00:00:00+05:30`));
}

function dateKey(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Kolkata",
  }).format(date);
}

function isDueWithinSevenDays(item: BookingDocumentReviewWorklistItem): boolean {
  if (!item.dueDate) return false;

  const today = new Date();
  const end = new Date(today);
  end.setDate(end.getDate() + 7);

  return item.dueDate <= dateKey(end);
}

function isPendingReview(item: BookingDocumentReviewWorklistItem): boolean {
  return item.status === "submitted" || item.status === "under_review";
}

function badgeClass(status: string): string {
  if (status === "rejected") return "border-red-500/50 bg-red-500/10 text-red-200";
  if (status === "submitted" || status === "under_review") return "border-amber-500/50 bg-amber-500/10 text-amber-200";
  return "border-slate-600 bg-slate-800 text-slate-300";
}

function getVisibleItems(
  items: BookingDocumentReviewWorklistItem[],
  view: DocumentReviewWorklistView,
): BookingDocumentReviewWorklistItem[] {
  if (view === "pending") return items.filter(isPendingReview);
  if (view === "rejected") return items.filter((item) => item.status === "rejected");
  if (view === "due") return items.filter(isDueWithinSevenDays);

  return items.filter((item) => isPendingReview(item) || item.status === "rejected" || isDueWithinSevenDays(item));
}

function WorklistLink({
  label,
  count,
  selected,
  href,
}: {
  label: string;
  count: number;
  selected: boolean;
  href: string;
}) {
  return (
    <Link
      href={href}
      className={[
        "rounded-xl border px-4 py-3 text-sm font-semibold transition",
        selected
          ? "border-cyan-400 bg-cyan-400/10 text-cyan-200"
          : "border-slate-700 bg-slate-900 text-slate-300 hover:border-slate-500 hover:text-white",
      ].join(" ")}
    >
      {label} <span className="ml-1 text-xs opacity-75">{count}</span>
    </Link>
  );
}

export default function DocumentReviewWorklist({
  items,
  view,
}: {
  items: BookingDocumentReviewWorklistItem[];
  view: DocumentReviewWorklistView;
}) {
  const pendingCount = items.filter(isPendingReview).length;
  const rejectedCount = items.filter((item) => item.status === "rejected").length;
  const dueCount = items.filter(isDueWithinSevenDays).length;
  const visibleItems = getVisibleItems(items, view);
  const attentionCount = getVisibleItems(items, "attention").length;

  return (
    <section aria-label="Booking document review worklist" className="space-y-5">
      <nav aria-label="Document review filters" className="flex flex-wrap gap-3">
        <WorklistLink label="All attention" count={attentionCount} selected={view === "attention"} href="/dashboard/deals/document-reviews" />
        <WorklistLink label="Pending review" count={pendingCount} selected={view === "pending"} href="/dashboard/deals/document-reviews?view=pending" />
        <WorklistLink label="Rejected" count={rejectedCount} selected={view === "rejected"} href="/dashboard/deals/document-reviews?view=rejected" />
        <WorklistLink label="Due / overdue" count={dueCount} selected={view === "due"} href="/dashboard/deals/document-reviews?view=due" />
      </nav>

      {visibleItems.length ? (
        <div className="space-y-4">
          {visibleItems.map((item) => (
            <article key={item.id} className="rounded-2xl border border-slate-800 bg-slate-900/60 p-5">
              <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="font-semibold text-white">{item.itemName}</h2>
                    <span className={`rounded-full border px-3 py-1 text-xs font-semibold ${badgeClass(item.status)}`}>
                      {STATUS_LABEL[item.status] ?? item.status}
                    </span>
                    {isDueWithinSevenDays(item) ? (
                      <span className="rounded-full border border-violet-500/50 bg-violet-500/10 px-3 py-1 text-xs font-semibold text-violet-200">
                        Due {formatDate(item.dueDate)}
                      </span>
                    ) : null}
                  </div>
                  <p className="mt-2 text-sm text-slate-400">
                    Deal {item.dealId.slice(0, 8)} · Booking {item.bookingId.slice(0, 8)} · {item.dealStatus.replaceAll("_", " ")}
                  </p>
                  {item.notes ? <p className="mt-3 text-sm leading-6 text-slate-300">{item.notes}</p> : null}
                </div>
                <Link
                  href={`/dashboard/deals/${item.dealId}#agreement-checklist`}
                  className="shrink-0 rounded-xl border border-cyan-500/60 px-4 py-2.5 text-sm font-semibold text-cyan-300 transition hover:bg-cyan-500/10 hover:text-cyan-100"
                >
                  Open deal review
                </Link>
              </div>
            </article>
          ))}
        </div>
      ) : (
        <div className="rounded-2xl border border-dashed border-slate-700 bg-slate-900/40 px-5 py-12 text-center">
          <p className="font-medium text-slate-200">No documents need attention in this view.</p>
          <p className="mt-2 text-sm text-slate-500">Submitted, rejected and due-soon booking documents will appear here.</p>
        </div>
      )}
    </section>
  );
}
