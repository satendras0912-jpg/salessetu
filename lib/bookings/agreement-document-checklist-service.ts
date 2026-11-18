import "server-only";

import { createClient } from "@/lib/supabase/server";

export const BOOKING_DOCUMENT_STATUSES = [
  "not_started",
  "requested",
  "submitted",
  "under_review",
  "approved",
  "rejected",
  "not_required",
] as const;

export type BookingDocumentStatus =
  (typeof BOOKING_DOCUMENT_STATUSES)[number];

export type BookingDocumentChecklistItem = {
  id: string;
  bookingId: string;
  dealId: string;
  itemCode: string;
  itemName: string;
  required: boolean;
  requiresOwnerApproval: boolean;
  status: BookingDocumentStatus;
  dueDate: string | null;
  notes: string | null;
  updatedAt: string;
  reviewedAt: string | null;
  document: BookingDocumentFile | null;
};

export type BookingDocumentFile = {
  id: string;
  originalFilename: string;
  mimeType: string;
  byteSize: number;
  reviewStatus: "pending" | "approved" | "rejected";
  uploadedAt: string;
  downloadUrl: string | null;
};

export type BookingDocumentChecklistAudit = {
  id: string;
  checklistItemId: string;
  action: string;
  fromStatus: string | null;
  toStatus: string;
  reason: string | null;
  performedAt: string;
};

type ChecklistRow = {
  id: string;
  booking_id: string;
  deal_id: string;
  item_code: string;
  item_name: string;
  required: boolean;
  requires_owner_approval: boolean;
  status: BookingDocumentStatus;
  due_date: string | null;
  notes: string | null;
  updated_at: string;
  reviewed_at: string | null;
};

type DocumentFileRow = {
  id: string;
  checklist_item_id: string;
  storage_path: string;
  original_filename: string;
  mime_type: string;
  byte_size: number;
  review_status: "pending" | "approved" | "rejected";
  uploaded_at: string;
};

type AuditRow = {
  id: string;
  checklist_item_id: string;
  action: string;
  from_status: string | null;
  to_status: string;
  reason: string | null;
  performed_at: string;
};

function toItem(
  row: ChecklistRow,
  document: BookingDocumentFile | null,
): BookingDocumentChecklistItem {
  return {
    id: row.id,
    bookingId: row.booking_id,
    dealId: row.deal_id,
    itemCode: row.item_code,
    itemName: row.item_name,
    required: row.required,
    requiresOwnerApproval: row.requires_owner_approval,
    status: row.status,
    dueDate: row.due_date,
    notes: row.notes,
    updatedAt: row.updated_at,
    reviewedAt: row.reviewed_at,
    document,
  };
}

function toAudit(row: AuditRow): BookingDocumentChecklistAudit {
  return {
    id: row.id,
    checklistItemId: row.checklist_item_id,
    action: row.action,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason,
    performedAt: row.performed_at,
  };
}

export async function getBookingAgreementChecklist(
  dealId: string,
  bookingId: string | null,
): Promise<{
  ok: true;
  items: BookingDocumentChecklistItem[];
  audit: BookingDocumentChecklistAudit[];
} | {
  ok: false;
  message: string;
}> {
  if (!bookingId) {
    return { ok: true, items: [], audit: [] };
  }

  const supabase = await createClient();
  const { error: ensureError } = await supabase.rpc(
    "ensure_booking_document_checklist",
    {
      requested_deal_id: dealId,
      requested_booking_id: bookingId,
    },
  );

  if (ensureError) {
    return {
      ok: false,
      message: ensureError.message || "Agreement checklist could not be prepared.",
    };
  }

  const [itemsResult, auditResult] = await Promise.all([
    supabase
      .from("booking_document_checklist_items")
      .select("id, booking_id, deal_id, item_code, item_name, required, requires_owner_approval, status, due_date, notes, updated_at, reviewed_at")
      .eq("booking_id", bookingId)
      .order("created_at", { ascending: true }),
    supabase
      .from("booking_document_checklist_audit")
      .select("id, checklist_item_id, action, from_status, to_status, reason, performed_at")
      .eq("booking_id", bookingId)
      .order("performed_at", { ascending: false })
      .limit(20),
  ]);

  if (itemsResult.error || auditResult.error) {
    return {
      ok: false,
      message: itemsResult.error?.message || auditResult.error?.message || "Agreement checklist could not be loaded.",
    };
  }

  const checklistRows = (itemsResult.data ?? []) as ChecklistRow[];
  const itemIds = checklistRows.map((item) => item.id);
  const filesResult = itemIds.length
    ? await supabase
      .from("booking_document_files")
      .select("id, checklist_item_id, storage_path, original_filename, mime_type, byte_size, review_status, uploaded_at")
      .in("checklist_item_id", itemIds)
      .eq("is_current", true)
    : { data: [] as DocumentFileRow[], error: null };

  if (filesResult.error) {
    return {
      ok: false,
      message: filesResult.error.message || "Booking documents could not be loaded.",
    };
  }

  const fileRows = (filesResult.data ?? []) as DocumentFileRow[];
  const fileEntries = await Promise.all(
    fileRows.map(async (file) => {
      const { data } = await supabase.storage
        .from("booking-documents")
        .createSignedUrl(file.storage_path, 600);

      return [
        file.checklist_item_id,
        {
          id: file.id,
          originalFilename: file.original_filename,
          mimeType: file.mime_type,
          byteSize: file.byte_size,
          reviewStatus: file.review_status,
          uploadedAt: file.uploaded_at,
          downloadUrl: data?.signedUrl ?? null,
        } satisfies BookingDocumentFile,
      ] as const;
    }),
  );
  const filesByItemId = new Map(fileEntries);

  return {
    ok: true,
    items: checklistRows.map((item) => toItem(item, filesByItemId.get(item.id) ?? null)),
    audit: ((auditResult.data ?? []) as AuditRow[]).map(toAudit),
  };
}
