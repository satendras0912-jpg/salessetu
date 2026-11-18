"use client";

import { useActionState, useState } from "react";

import {
  updateBookingAgreementChecklistAction,
  uploadBookingDocumentAction,
} from "@/app/dashboard/deals/actions";
import { INITIAL_DEALOS_ACTION_STATE } from "@/lib/dealos/deal-contract";
import type {
  BookingDocumentChecklistAudit,
  BookingDocumentChecklistItem,
  BookingDocumentStatus,
} from "@/lib/bookings/agreement-document-checklist-service";

const INPUT = "w-full rounded-xl border border-slate-700 bg-slate-950 px-3 py-2.5 text-sm text-white outline-none transition focus:border-cyan-400";

const AGENT_STATUSES: BookingDocumentStatus[] = [
  "not_started",
  "requested",
  "submitted",
  "under_review",
  "not_required",
];
const MAX_BOOKING_DOCUMENT_BYTES = 4 * 1024 * 1024;

function label(value: string): string {
  return value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function statusClass(status: string): string {
  if (status === "approved") return "border-emerald-500/40 bg-emerald-500/10 text-emerald-200";
  if (status === "rejected") return "border-red-500/40 bg-red-500/10 text-red-200";
  if (["submitted", "under_review", "requested"].includes(status)) return "border-amber-500/40 bg-amber-500/10 text-amber-200";
  return "border-slate-700 bg-slate-800 text-slate-300";
}

function date(value: string | null): string {
  if (!value) return "—";
  return new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeZone: "Asia/Kolkata" }).format(new Date(`${value}T00:00:00`));
}

function fileSize(value: number): string {
  if (value < 1024 * 1024) return `${Math.max(1, Math.round(value / 1024))} KB`;
  return `${(value / (1024 * 1024)).toFixed(1)} MB`;
}

function ChecklistRow({
  dealId,
  bookingId,
  item,
  isOwner,
}: {
  dealId: string;
  bookingId: string;
  item: BookingDocumentChecklistItem;
  isOwner: boolean;
}) {
  const [state, action, pending] = useActionState(updateBookingAgreementChecklistAction, INITIAL_DEALOS_ACTION_STATE);
  const [uploadState, uploadAction, uploading] = useActionState(uploadBookingDocumentAction, INITIAL_DEALOS_ACTION_STATE);
  const [selectedFileError, setSelectedFileError] = useState("");
  const isOwnerDecision = ["approved", "rejected"].includes(item.status);
  const agentStatusLocked = !isOwner && isOwnerDecision;
  const statuses = isOwner
    ? ["not_started", "requested", "submitted", "under_review", "approved", "rejected", "not_required"]
    : agentStatusLocked
      ? [item.status]
      : AGENT_STATUSES;

  function validateSelectedFile(file: File | undefined): boolean {
    if (!file || file.size <= MAX_BOOKING_DOCUMENT_BYTES) {
      setSelectedFileError("");
      return true;
    }

    setSelectedFileError("This file is larger than 4 MB. Please choose a smaller PDF, JPG or PNG.");
    return false;
  }

  return (
    <article className="rounded-2xl border border-slate-800 bg-slate-950/50 p-5">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <h3 className="font-semibold text-white">{item.itemName}</h3>
            {item.required ? <span className="rounded-full border border-amber-500/40 bg-amber-500/10 px-2.5 py-1 text-xs font-semibold text-amber-200">Required</span> : null}
            {item.requiresOwnerApproval ? <span className="rounded-full border border-cyan-500/40 bg-cyan-500/10 px-2.5 py-1 text-xs font-semibold text-cyan-200">Owner approval</span> : null}
          </div>
          <p className="mt-2 text-sm text-slate-400">Current status: <span className={`ml-1 inline-flex rounded-full border px-2.5 py-1 text-xs font-semibold ${statusClass(item.status)}`}>{label(item.status)}</span></p>
        </div>
        <p className="text-xs text-slate-500">Due {date(item.dueDate)}</p>
      </div>

      <form action={action} className="mt-5 grid gap-3 md:grid-cols-[minmax(0,0.8fr)_minmax(0,1fr)_auto] md:items-end">
        <input type="hidden" name="dealId" value={dealId} />
        <input type="hidden" name="bookingId" value={bookingId} />
        <input type="hidden" name="itemId" value={item.id} />
        <div>
          <label htmlFor={`document-status-${item.id}`} className="mb-2 block text-sm text-slate-300">Document status</label>
          <select id={`document-status-${item.id}`} name="status" defaultValue={item.status} disabled={agentStatusLocked} className={INPUT}>
            {statuses.map((status) => <option key={status} value={status}>{label(status)}</option>)}
          </select>
        </div>
        <div>
          <label htmlFor={`document-due-${item.id}`} className="mb-2 block text-sm text-slate-300">Due date</label>
          <input id={`document-due-${item.id}`} name="dueDate" type="date" defaultValue={item.dueDate ?? ""} className={INPUT} />
        </div>
        <button type="submit" disabled={pending || agentStatusLocked} className="rounded-xl border border-cyan-500/60 px-4 py-3 text-sm font-semibold text-cyan-200 disabled:opacity-50">{pending ? "Saving..." : "Save"}</button>
        <div className="md:col-span-3">
          <label htmlFor={`document-notes-${item.id}`} className="mb-2 block text-sm text-slate-300">Notes <span className="text-slate-500">(audit reason / handover context)</span></label>
          <textarea id={`document-notes-${item.id}`} name="notes" defaultValue={item.notes ?? ""} maxLength={2000} className={`${INPUT} min-h-20`} placeholder="Document details, missing information or approval reason" />
        </div>
      </form>
      {state.status !== "idle" && state.message ? <p aria-live="polite" className="mt-3 text-sm text-red-300">{state.message}</p> : null}

      <section className="mt-5 rounded-xl border border-slate-800 bg-slate-950/70 p-4">
        <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h4 className="text-sm font-semibold text-white">Private document vault</h4>
            <p className="mt-1 text-xs text-slate-400">PDF, JPG or PNG · maximum 4 MB · a new upload replaces the previous review file.</p>
          </div>
          {item.document ? (
            <span className={`inline-flex w-fit rounded-full border px-2.5 py-1 text-xs font-semibold ${statusClass(item.document.reviewStatus)}`}>
              File review: {label(item.document.reviewStatus)}
            </span>
          ) : (
            <span className="inline-flex w-fit rounded-full border border-slate-700 bg-slate-800 px-2.5 py-1 text-xs font-semibold text-slate-300">No file uploaded</span>
          )}
        </div>

        {item.document ? (
          <p className="mt-3 text-sm text-slate-300">
            Current file: {item.document.downloadUrl ? (
              <a className="font-medium text-cyan-300 underline underline-offset-4" href={item.document.downloadUrl} target="_blank" rel="noreferrer">
                {item.document.originalFilename}
              </a>
            ) : item.document.originalFilename} <span className="text-slate-500">({fileSize(item.document.byteSize)})</span>
          </p>
        ) : null}

        <form action={uploadAction} encType="multipart/form-data" onSubmit={(event) => {
          const input = event.currentTarget.elements.namedItem("documentFile");
          const file = input instanceof HTMLInputElement ? input.files?.[0] : undefined;
          if (!validateSelectedFile(file)) event.preventDefault();
        }} className="mt-4 flex flex-col gap-3 sm:flex-row sm:items-end">
          <input type="hidden" name="dealId" value={dealId} />
          <input type="hidden" name="bookingId" value={bookingId} />
          <input type="hidden" name="itemId" value={item.id} />
          <div className="min-w-0 flex-1">
            <label htmlFor={`document-file-${item.id}`} className="mb-2 block text-sm text-slate-300">Upload review file</label>
            <input id={`document-file-${item.id}`} name="documentFile" type="file" accept="application/pdf,image/jpeg,image/png" required onChange={(event) => validateSelectedFile(event.currentTarget.files?.[0])} className="block w-full text-sm text-slate-300 file:mr-4 file:rounded-lg file:border-0 file:bg-slate-800 file:px-3 file:py-2 file:text-sm file:font-semibold file:text-cyan-200 hover:file:bg-slate-700" />
          </div>
          <button type="submit" disabled={uploading} className="rounded-xl border border-cyan-500/60 px-4 py-3 text-sm font-semibold text-cyan-200 disabled:opacity-50">{uploading ? "Uploading..." : "Upload & submit"}</button>
        </form>
        {selectedFileError ? <p aria-live="polite" className="mt-3 text-sm text-red-300">{selectedFileError}</p> : null}
        {uploadState.status !== "idle" && uploadState.message ? <p aria-live="polite" className="mt-3 text-sm text-red-300">{uploadState.message}</p> : null}
      </section>
    </article>
  );
}

export default function BookingAgreementChecklistPanel({
  dealId,
  bookingId,
  items,
  audit,
  isOwner,
}: {
  dealId: string;
  bookingId: string;
  items: BookingDocumentChecklistItem[];
  audit: BookingDocumentChecklistAudit[];
  isOwner: boolean;
}) {
  const required = items.filter((item) => item.required && item.status !== "not_required");
  const approved = required.filter((item) => item.status === "approved").length;
  const agreement = items.find((item) => item.itemCode === "agreement");

  return (
    <section id="agreement-checklist" className="rounded-3xl border border-violet-500/30 bg-violet-500/5 p-6 sm:p-8">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-[0.25em] text-violet-300">Post-booking compliance</p>
          <h2 className="mt-2 text-2xl font-semibold text-white">Agreement & document checklist</h2>
          <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">Buyer KYC, booking form, allotment letter aur agreement ek jagah track hote hain. Final approval sirf workspace owner complete karta hai.</p>
        </div>
        <div className="rounded-2xl border border-violet-400/30 bg-slate-950/50 px-4 py-3 text-sm text-violet-100">
          {approved}/{required.length} required approved
          <p className="mt-1 text-xs text-slate-400">Agreement: {agreement ? label(agreement.status) : "Pending"}</p>
        </div>
      </div>

      <div className="mt-7 space-y-4">
        {items.map((item) => <ChecklistRow key={item.id} dealId={dealId} bookingId={bookingId} item={item} isOwner={isOwner} />)}
      </div>

      <div className="mt-7 rounded-2xl border border-slate-800 bg-slate-950/50 p-5">
        <h3 className="font-semibold text-white">Audit trail</h3>
        {audit.length ? <ol className="mt-4 space-y-3 text-sm text-slate-300">{audit.slice(0, 8).map((entry) => <li key={entry.id} className="border-l-2 border-violet-500/40 pl-3"><span className="font-medium text-white">{label(entry.action)}</span> · {entry.fromStatus ? `${label(entry.fromStatus)} → ` : ""}{label(entry.toStatus)}{entry.reason ? ` — ${entry.reason}` : ""}<span className="ml-2 text-xs text-slate-500">{new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Kolkata" }).format(new Date(entry.performedAt))}</span></li>)}</ol> : <p className="mt-3 text-sm text-slate-500">No document actions have been recorded yet.</p>}
      </div>
    </section>
  );
}
