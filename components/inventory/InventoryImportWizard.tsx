"use client";

import {
  useActionState,
  useMemo,
  useState,
} from "react";
import type { ChangeEvent } from "react";

import {
  importInventoryUnitsAction,
  INITIAL_INVENTORY_IMPORT_STATE,
} from "@/app/dashboard/inventory/import/actions";

type CsvRow = Record<string, string>;

type ParsedImportRow = {
  projectCode: string;
  inventoryCode: string;
  unitNumber: string;
  propertyType: string;
  unitStatus: string;
  currentPrice: number | null;
  floorNumber: number | null;
  bedrooms: number | null;
  superArea: number | null;
  source: string;
  verificationDate: string;
  publicationStatus: string;
};

type PreviewIssue = {
  row: number;
  message: string;
};

const REQUIRED_HEADERS = [
  "project_code",
  "inventory_code",
  "unit_number",
  "property_type",
  "unit_status",
  "source",
  "verification_date",
  "publication_status",
] as const;

const VALID_PROPERTY_TYPES = new Set([
  "apartment",
  "villa",
  "duplex",
  "penthouse",
  "studio",
  "plot",
  "shop",
  "office",
  "warehouse",
  "farmhouse",
  "floor",
  "other",
]);

const VALID_STATUSES = new Set([
  "not_released",
  "available",
  "management_hold",
]);

const VALID_PUBLICATION_STATUSES = new Set([
  "internal",
  "approved",
  "not_for_publication",
]);

function parseCsvLine(line: string): string[] {
  const values: string[] = [];
  let current = "";
  let inQuotes = false;

  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];

    if (character === "\"") {
      if (inQuotes && line[index + 1] === "\"") {
        current += "\"";
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (character === "," && !inQuotes) {
      values.push(current.trim());
      current = "";
    } else {
      current += character;
    }
  }

  values.push(current.trim());

  return values;
}

function parseCsv(csv: string): {
  rows: CsvRow[];
  headers: string[];
} {
  const lines = csv
    .replace(/^\uFEFF/, "")
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0);

  if (lines.length < 2) {
    return {
      rows: [],
      headers: [],
    };
  }

  const headers = parseCsvLine(lines[0]).map((header) =>
    header.trim().toLowerCase(),
  );

  const rows = lines.slice(1).map((line) => {
    const cells = parseCsvLine(line);
    const row: CsvRow = {};

    headers.forEach((header, index) => {
      row[header] = cells[index] ?? "";
    });

    return row;
  });

  return {
    rows,
    headers,
  };
}

function toOptionalNumber(value: string): number | null {
  const normalized = value.trim();

  if (!normalized) {
    return null;
  }

  const parsed = Number(normalized.replaceAll(",", ""));

  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function clean(value: string): string {
  return value.trim();
}

function normalizeRow(row: CsvRow): ParsedImportRow {
  return {
    projectCode: clean(row.project_code).toUpperCase(),
    inventoryCode: clean(row.inventory_code).toUpperCase(),
    unitNumber: clean(row.unit_number).toUpperCase(),
    propertyType: clean(row.property_type).toLowerCase(),
    unitStatus: clean(row.unit_status).toLowerCase(),
    currentPrice: toOptionalNumber(row.current_price ?? ""),
    floorNumber: toOptionalNumber(row.floor_number ?? ""),
    bedrooms: toOptionalNumber(row.bedrooms ?? ""),
    superArea: toOptionalNumber(row.super_area ?? ""),
    source: clean(row.source),
    verificationDate: clean(row.verification_date),
    publicationStatus: clean(row.publication_status).toLowerCase(),
  };
}

function isValidDate(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(`${value}T00:00:00.000Z`));
}

function validateRows(rows: ParsedImportRow[]): PreviewIssue[] {
  const issues: PreviewIssue[] = [];
  const inventoryCodeRows = new Map<string, number>();
  const projectUnitRows = new Map<string, number>();

  rows.forEach((row, index) => {
    const rowNumber = index + 2;

    if (
      !row.projectCode ||
      !row.inventoryCode ||
      !row.unitNumber ||
      !row.source ||
      !row.verificationDate
    ) {
      issues.push({
        row: rowNumber,
        message: "Required identity or verification field is missing.",
      });
    }

    if (!VALID_PROPERTY_TYPES.has(row.propertyType)) {
      issues.push({
        row: rowNumber,
        message: "Property type is not supported.",
      });
    }

    if (!VALID_STATUSES.has(row.unitStatus)) {
      issues.push({
        row: rowNumber,
        message: "Status must be available, not_released or management_hold.",
      });
    }

    if (!VALID_PUBLICATION_STATUSES.has(row.publicationStatus)) {
      issues.push({
        row: rowNumber,
        message: "Publication status must be internal, approved or not_for_publication.",
      });
    }

    if (!isValidDate(row.verificationDate)) {
      issues.push({
        row: rowNumber,
        message: "Verification date must use YYYY-MM-DD.",
      });
    }

    const priorInventoryRow = inventoryCodeRows.get(row.inventoryCode);

    if (priorInventoryRow) {
      issues.push({
        row: rowNumber,
        message: `Inventory code duplicates CSV row ${priorInventoryRow}.`,
      });
    } else if (row.inventoryCode) {
      inventoryCodeRows.set(row.inventoryCode, rowNumber);
    }

    const projectUnitKey = `${row.projectCode}::${row.unitNumber}`;
    const priorProjectUnitRow = projectUnitRows.get(projectUnitKey);

    if (priorProjectUnitRow) {
      issues.push({
        row: rowNumber,
        message: `Project and unit duplicate CSV row ${priorProjectUnitRow}.`,
      });
    } else if (row.projectCode && row.unitNumber) {
      projectUnitRows.set(projectUnitKey, rowNumber);
    }
  });

  return issues;
}

export default function InventoryImportWizard() {
  const [rows, setRows] = useState<ParsedImportRow[]>([]);
  const [issues, setIssues] = useState<PreviewIssue[]>([]);
  const [fileName, setFileName] = useState("");
  const [fileError, setFileError] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [state, formAction, isPending] = useActionState(
    importInventoryUnitsAction,
    INITIAL_INVENTORY_IMPORT_STATE,
  );

  const previewRows = useMemo(
    () => rows.slice(0, 8),
    [rows],
  );

  const canSubmit =
    rows.length > 0 &&
    rows.length <= 500 &&
    issues.length === 0 &&
    confirmed &&
    !isPending;

  function handleFileChange(
    event: ChangeEvent<HTMLInputElement>,
  ) {
    const file = event.target.files?.[0];

    setRows([]);
    setIssues([]);
    setConfirmed(false);
    setFileError("");
    setFileName(file?.name ?? "");

    if (!file) {
      return;
    }

    if (!file.name.toLowerCase().endsWith(".csv")) {
      setFileError("Upload a CSV file only.");
      return;
    }

    if (file.size > 250 * 1024) {
      setFileError("CSV must be 250 KB or smaller.");
      return;
    }

    const reader = new FileReader();

    reader.onload = () => {
      const result = typeof reader.result === "string"
        ? reader.result
        : "";

      const parsed = parseCsv(result);
      const missingHeaders = REQUIRED_HEADERS.filter(
        (header) => !parsed.headers.includes(header),
      );

      if (missingHeaders.length > 0) {
        setFileError(
          `Missing required columns: ${missingHeaders.join(", ")}.`,
        );
        return;
      }

      const normalizedRows = parsed.rows.map(normalizeRow);

      if (normalizedRows.length === 0) {
        setFileError("CSV has no data rows.");
        return;
      }

      if (normalizedRows.length > 500) {
        setFileError("Maximum 500 units can be validated in one batch.");
        return;
      }

      setRows(normalizedRows);
      setIssues(validateRows(normalizedRows));
    };

    reader.onerror = () => {
      setFileError("CSV could not be read.");
    };

    reader.readAsText(file);
  }

  return (
    <section className="space-y-6">
      <form
        action={formAction}
        className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6"
      >
        <input
          type="hidden"
          name="payload"
          value={JSON.stringify(rows)}
        />

        <div className="flex flex-col justify-between gap-4 md:flex-row md:items-end">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
              Controlled CSV import
            </p>
            <h2 className="mt-2 text-2xl font-bold text-white">
              Validate before saving
            </h2>
            <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
              The file stays in your browser until this final import is
              confirmed. The server then rechecks tenant projects and existing
              inventory before any units are saved.
            </p>
          </div>

          <a
            href="/templates/inventory-import-template.csv"
            download
            className="rounded-xl border border-cyan-500/50 px-4 py-3 text-center text-sm font-semibold text-cyan-300 transition hover:bg-cyan-500/10"
          >
            Download CSV template
          </a>
        </div>

        <div className="mt-6 rounded-2xl border border-dashed border-slate-700 bg-slate-950/50 p-5">
          <label
            htmlFor="inventory-import-file"
            className="block text-sm font-semibold text-white"
          >
            Choose verified inventory CSV
          </label>
          <p className="mt-1 text-sm text-slate-500">
            Maximum 500 rows / 250 KB. Required: project, unit identity, source,
            verification date and publication status.
          </p>
          <input
            id="inventory-import-file"
            type="file"
            accept=".csv,text/csv"
            onChange={handleFileChange}
            className="mt-4 block w-full text-sm text-slate-300 file:mr-4 file:rounded-lg file:border-0 file:bg-cyan-400 file:px-4 file:py-2 file:font-semibold file:text-slate-950"
          />
          {fileName ? (
            <p className="mt-3 text-sm text-slate-400">
              Selected: {fileName}
            </p>
          ) : null}
          {fileError ? (
            <p className="mt-3 text-sm text-rose-300">
              {fileError}
            </p>
          ) : null}
        </div>

        {rows.length > 0 ? (
          <div className="mt-6 grid gap-4 md:grid-cols-3">
            <article className="rounded-2xl border border-slate-800 bg-slate-950/50 p-4">
              <p className="text-sm text-slate-500">Rows ready</p>
              <p className="mt-1 text-2xl font-bold text-white">{rows.length}</p>
            </article>
            <article className="rounded-2xl border border-slate-800 bg-slate-950/50 p-4">
              <p className="text-sm text-slate-500">Validation issues</p>
              <p className="mt-1 text-2xl font-bold text-amber-300">{issues.length}</p>
            </article>
            <article className="rounded-2xl border border-slate-800 bg-slate-950/50 p-4">
              <p className="text-sm text-slate-500">Import mode</p>
              <p className="mt-1 text-sm font-semibold text-cyan-300">
                Add only · existing units blocked
              </p>
            </article>
          </div>
        ) : null}

        {issues.length > 0 ? (
          <div className="mt-6 rounded-2xl border border-rose-500/40 bg-rose-500/10 p-5">
            <h3 className="font-semibold text-rose-200">
              Fix these CSV issues before import
            </h3>
            <ul className="mt-3 space-y-1 text-sm text-rose-100">
              {issues.slice(0, 8).map((issue) => (
                <li key={`${issue.row}-${issue.message}`}>
                  Row {issue.row}: {issue.message}
                </li>
              ))}
            </ul>
            {issues.length > 8 ? (
              <p className="mt-3 text-sm text-rose-200">
                Plus {issues.length - 8} more issues.
              </p>
            ) : null}
          </div>
        ) : null}

        {previewRows.length > 0 ? (
          <div className="mt-6 overflow-x-auto rounded-2xl border border-slate-800">
            <table className="min-w-[900px] divide-y divide-slate-800 text-left text-sm">
              <thead className="bg-slate-950/70 text-xs uppercase tracking-wider text-slate-500">
                <tr>
                  <th className="px-4 py-3">Project</th>
                  <th className="px-4 py-3">Unit</th>
                  <th className="px-4 py-3">Type</th>
                  <th className="px-4 py-3">Price</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3">Verified</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800">
                {previewRows.map((row) => (
                  <tr key={`${row.projectCode}-${row.inventoryCode}`}>
                    <td className="px-4 py-3 text-slate-300">
                      {row.projectCode}
                    </td>
                    <td className="px-4 py-3 text-white">
                      {row.unitNumber}
                      <span className="ml-2 text-xs text-slate-500">
                        {row.inventoryCode}
                      </span>
                    </td>
                    <td className="px-4 py-3 capitalize text-slate-300">
                      {row.propertyType}
                    </td>
                    <td className="px-4 py-3 text-slate-300">
                      {row.currentPrice
                        ? `₹${row.currentPrice.toLocaleString("en-IN")}`
                        : "Not set"}
                    </td>
                    <td className="px-4 py-3 capitalize text-slate-300">
                      {row.unitStatus.replaceAll("_", " ")}
                    </td>
                    <td className="px-4 py-3 text-slate-300">
                      {row.verificationDate}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : null}

        {state.status !== "idle" ? (
          <p
            className={[
              "mt-6 rounded-2xl border px-5 py-4 text-sm",
              state.status === "success"
                ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-200"
                : "border-rose-500/40 bg-rose-500/10 text-rose-200",
            ].join(" ")}
          >
            {state.message}
          </p>
        ) : null}

        <label className="mt-6 flex items-start gap-3 rounded-2xl border border-amber-500/30 bg-amber-500/5 p-4 text-sm text-slate-300">
          <input
            type="checkbox"
            name="confirmImport"
            value="yes"
            checked={confirmed}
            onChange={(event) => setConfirmed(event.target.checked)}
            disabled={rows.length === 0 || issues.length > 0}
            className="mt-0.5 size-4 accent-cyan-400"
          />
          <span>
            I reviewed the preview. This will add only verified units to the
            active Kavyarpit workspace; existing inventory will never be
            overwritten by this import.
          </span>
        </label>

        <button
          type="submit"
          disabled={!canSubmit}
          className="mt-5 rounded-xl bg-cyan-400 px-5 py-3 text-sm font-bold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-40"
        >
          {isPending ? "Importing safely…" : "Confirm and import units"}
        </button>
      </form>
    </section>
  );
}
