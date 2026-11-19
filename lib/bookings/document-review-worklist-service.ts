import "server-only";

import { createClient } from "@/lib/supabase/server";
import type { BookingDocumentStatus } from "@/lib/bookings/agreement-document-checklist-service";

export type BookingDocumentReviewWorklistItem = {
  id: string;
  dealId: string;
  bookingId: string;
  itemCode: string;
  itemName: string;
  status: BookingDocumentStatus;
  dueDate: string | null;
  notes: string | null;
  updatedAt: string;
  dealStatus: string;
  assignedTo: string | null;
};

type ChecklistRow = {
  id: string;
  deal_id: string;
  booking_id: string;
  item_code: string;
  item_name: string;
  status: BookingDocumentStatus;
  due_date: string | null;
  notes: string | null;
  updated_at: string;
};

type DealRow = {
  id: string;
  status: string;
  assigned_to: string | null;
};

function toItem(
  row: ChecklistRow,
  deal: DealRow | undefined,
): BookingDocumentReviewWorklistItem {
  return {
    id: row.id,
    dealId: row.deal_id,
    bookingId: row.booking_id,
    itemCode: row.item_code,
    itemName: row.item_name,
    status: row.status,
    dueDate: row.due_date,
    notes: row.notes,
    updatedAt: row.updated_at,
    dealStatus: deal?.status ?? "unknown",
    assignedTo: deal?.assigned_to ?? null,
  };
}

export async function getBookingDocumentReviewWorklist(
  organizationId: string,
): Promise<BookingDocumentReviewWorklistItem[]> {
  const supabase = await createClient();
  const { data: checklistData, error: checklistError } = await supabase
    .from("booking_document_checklist_items")
    .select("id,deal_id,booking_id,item_code,item_name,status,due_date,notes,updated_at")
    .eq("organization_id", organizationId)
    .in("status", ["not_started", "requested", "submitted", "under_review", "rejected"])
    .limit(500);

  if (checklistError) {
    throw new Error(checklistError.message || "Document review worklist could not be loaded.");
  }

  const checklistRows = (checklistData ?? []) as ChecklistRow[];
  const dealIds = [...new Set(checklistRows.map((item) => item.deal_id))];

  if (!dealIds.length) {
    return [];
  }

  const { data: dealData, error: dealError } = await supabase
    .from("deals")
    .select("id,status,assigned_to")
    .eq("organization_id", organizationId)
    .in("id", dealIds)
    .is("deleted_at", null);

  if (dealError) {
    throw new Error(dealError.message || "Related deals could not be loaded.");
  }

  const dealsById = new Map(
    ((dealData ?? []) as DealRow[]).map((deal) => [deal.id, deal]),
  );

  return checklistRows
    .filter((item) => dealsById.has(item.deal_id))
    .map((item) => toItem(item, dealsById.get(item.deal_id)))
    .sort((left, right) => {
      const leftDue = left.dueDate ?? "9999-12-31";
      const rightDue = right.dueDate ?? "9999-12-31";

      return leftDue.localeCompare(rightDue) || left.updatedAt.localeCompare(right.updatedAt);
    });
}
