"use client";

type ExportRow = {
  bookingNumber: string;
  projectName: string;
  unitNumber: string | null;
  customerName: string;
  agentName: string;
  currencyCode: string;
  scheduled: number;
  received: number;
  outstanding: number;
  nextDueDate: string | null;
  overdueOutstanding: number;
};

function escapeCsv(value: string | number | null): string {
  const text = String(value ?? "");

  return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
}

export default function PaymentReconciliationExport({ rows, reportDate }: { rows: ExportRow[]; reportDate: string }) {
  function downloadCsv() {
    const headings = ["Booking", "Project", "Unit", "Customer", "Agent", "Currency", "Scheduled", "Received", "Outstanding", "Next due", "Overdue outstanding"];
    const records = rows.map((row) => [
      row.bookingNumber, row.projectName, row.unitNumber, row.customerName, row.agentName,
      row.currencyCode, row.scheduled, row.received, row.outstanding, row.nextDueDate, row.overdueOutstanding,
    ].map(escapeCsv).join(","));
    const csv = [headings.join(","), ...records].join("\n");
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `payment-reconciliation-${reportDate}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  return <button type="button" onClick={downloadCsv} disabled={rows.length === 0} className="rounded-xl border border-cyan-400/60 bg-cyan-400/10 px-4 py-2 text-sm font-semibold text-cyan-200 hover:bg-cyan-400/20 disabled:cursor-not-allowed disabled:opacity-50">Export reconciliation CSV</button>;
}
