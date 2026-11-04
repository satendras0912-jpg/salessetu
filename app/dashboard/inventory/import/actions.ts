"use server";

import { revalidatePath } from "next/cache";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";

export type InventoryImportActionState = {
  status: "idle" | "error" | "success";
  message: string;
  importedCount: number;
};

export const INITIAL_INVENTORY_IMPORT_STATE: InventoryImportActionState = {
  status: "idle",
  message: "",
  importedCount: 0,
};

type ImportRow = {
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

const allowedPropertyTypes = new Set([
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

const allowedStatuses = new Set([
  "not_released",
  "available",
  "management_hold",
]);

const allowedPublicationStatuses = new Set([
  "internal",
  "approved",
  "not_for_publication",
]);

function actionError(message: string): InventoryImportActionState {
  return {
    status: "error",
    message,
    importedCount: 0,
  };
}

function cleanText(value: unknown, maxLength = 240): string {
  return typeof value === "string"
    ? value.trim().slice(0, maxLength)
    : "";
}

function parseOptionalNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  if (typeof value !== "number" && typeof value !== "string") {
    return null;
  }

  const parsed = Number(value);

  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function isIsoDate(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(`${value}T00:00:00.000Z`));
}

function normalizeRow(value: unknown): ImportRow | null {
  if (!value || typeof value !== "object") {
    return null;
  }

  const raw = value as Record<string, unknown>;
  const projectCode = cleanText(raw.projectCode, 64).toUpperCase();
  const inventoryCode = cleanText(raw.inventoryCode, 64).toUpperCase();
  const unitNumber = cleanText(raw.unitNumber, 64).toUpperCase();
  const propertyType = cleanText(raw.propertyType, 40).toLowerCase();
  const unitStatus = cleanText(raw.unitStatus, 40).toLowerCase();
  const source = cleanText(raw.source, 120);
  const verificationDate = cleanText(raw.verificationDate, 10);
  const publicationStatus = cleanText(
    raw.publicationStatus,
    40,
  ).toLowerCase();

  const currentPrice = parseOptionalNumber(raw.currentPrice);
  const floorNumber = parseOptionalNumber(raw.floorNumber);
  const bedrooms = parseOptionalNumber(raw.bedrooms);
  const superArea = parseOptionalNumber(raw.superArea);

  if (
    !projectCode ||
    !inventoryCode ||
    !unitNumber ||
    !allowedPropertyTypes.has(propertyType) ||
    !allowedStatuses.has(unitStatus) ||
    !source ||
    !isIsoDate(verificationDate) ||
    !allowedPublicationStatuses.has(publicationStatus)
  ) {
    return null;
  }

  return {
    projectCode,
    inventoryCode,
    unitNumber,
    propertyType,
    unitStatus,
    currentPrice,
    floorNumber,
    bedrooms,
    superArea,
    source,
    verificationDate,
    publicationStatus,
  };
}

function findDuplicateValues(values: readonly string[]): string[] {
  const seen = new Set<string>();
  const duplicates = new Set<string>();

  for (const value of values) {
    if (seen.has(value)) {
      duplicates.add(value);
    }

    seen.add(value);
  }

  return [...duplicates];
}

export async function importInventoryUnitsAction(
  previousState: InventoryImportActionState,
  formData: FormData,
): Promise<InventoryImportActionState> {
  void previousState;

  const { context } = await requirePermissionAccess({
    allOf: [
      "inventory.view",
      "inventory.create",
    ],
    loginRedirectTo: "/login?next=/dashboard/inventory/import",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    return actionError(
      "An active organization context is required for import.",
    );
  }

  if (formData.get("confirmImport") !== "yes") {
    return actionError(
      "Review the preview and confirm the safe import before continuing.",
    );
  }

  const payload = formData.get("payload");

  if (typeof payload !== "string" || payload.length === 0) {
    return actionError("Choose a valid CSV file before importing.");
  }

  let parsedPayload: unknown;

  try {
    parsedPayload = JSON.parse(payload);
  } catch {
    return actionError("The import preview payload is invalid. Reload the CSV.");
  }

  if (!Array.isArray(parsedPayload) || parsedPayload.length === 0) {
    return actionError("The CSV does not contain any import rows.");
  }

  if (parsedPayload.length > 500) {
    return actionError(
      "Maximum 500 units can be imported in one controlled batch.",
    );
  }

  const rows = parsedPayload.map(normalizeRow);

  if (rows.some((row) => row === null)) {
    return actionError(
      "One or more rows have invalid required fields, status, source, verification date or publication status.",
    );
  }

  const safeRows = rows as ImportRow[];
  const duplicateCodes = findDuplicateValues(
    safeRows.map((row) => row.inventoryCode),
  );

  const duplicateProjectUnits = findDuplicateValues(
    safeRows.map((row) => `${row.projectCode}::${row.unitNumber}`),
  );

  if (duplicateCodes.length > 0 || duplicateProjectUnits.length > 0) {
    const examples = [
      ...duplicateCodes.slice(0, 3),
      ...duplicateProjectUnits.slice(0, 3),
    ];

    return actionError(
      `Duplicate rows found in this CSV: ${examples.join(", ")}.`,
    );
  }

  const supabase = await createClient();
  const projectCodes = [...new Set(safeRows.map((row) => row.projectCode))];

  const { data: projects, error: projectsError } = await supabase
    .from("projects")
    .select("id,project_code")
    .eq("organization_id", organizationId)
    .is("deleted_at", null)
    .in("project_code", projectCodes);

  if (projectsError) {
    return actionError("Projects could not be verified for this workspace.");
  }

  const projectIdByCode = new Map(
    (projects ?? []).map((project) => [
      String(project.project_code).toUpperCase(),
      String(project.id),
    ]),
  );

  const missingProjectCodes = projectCodes.filter(
    (projectCode) => !projectIdByCode.has(projectCode),
  );

  if (missingProjectCodes.length > 0) {
    return actionError(
      `Create these projects first: ${missingProjectCodes.slice(0, 5).join(", ")}.`,
    );
  }

  const inventoryCodes = safeRows.map((row) => row.inventoryCode);
  const unitNumbers = safeRows.map((row) => row.unitNumber);

  const [
    inventoryCodeResponse,
    unitNumberResponse,
  ] = await Promise.all([
    supabase
      .from("inventory_units")
      .select("inventory_code")
      .eq("organization_id", organizationId)
      .is("deleted_at", null)
      .in("inventory_code", inventoryCodes),
    supabase
      .from("inventory_units")
      .select("project_id,unit_number")
      .eq("organization_id", organizationId)
      .is("deleted_at", null)
      .in("unit_number", unitNumbers),
  ]);

  if (inventoryCodeResponse.error || unitNumberResponse.error) {
    return actionError("Existing inventory could not be checked safely.");
  }

  const existingCodes = new Set(
    (inventoryCodeResponse.data ?? []).map((row) =>
      String(row.inventory_code).toUpperCase(),
    ),
  );

  const existingProjectUnits = new Set(
    (unitNumberResponse.data ?? []).map((row) =>
      `${String(row.project_id)}::${String(row.unit_number).toUpperCase()}`,
    ),
  );

  const existingDuplicates = safeRows.filter((row) => {
    const projectId = projectIdByCode.get(row.projectCode);

    return (
      existingCodes.has(row.inventoryCode) ||
      (projectId
        ? existingProjectUnits.has(`${projectId}::${row.unitNumber}`)
        : false)
    );
  });

  if (existingDuplicates.length > 0) {
    return actionError(
      `Import stopped: ${existingDuplicates.length} unit code or project/unit combination already exists. No rows were saved.`,
    );
  }

  const importBatchId = crypto.randomUUID();

  const { error: insertError } = await supabase
    .from("inventory_units")
    .insert(
      safeRows.map((row) => ({
        organization_id: organizationId,
        project_id: projectIdByCode.get(row.projectCode),
        inventory_code: row.inventoryCode,
        unit_number: row.unitNumber,
        property_type: row.propertyType,
        unit_status: row.unitStatus,
        sales_status:
          row.unitStatus === "available" ? "open" : "on_hold",
        current_price: row.currentPrice,
        floor_number: row.floorNumber,
        bedrooms: row.bedrooms,
        super_area: row.superArea,
        currency: "INR",
        inventory_source: "csv_import",
        metadata: {
          import_batch_id: importBatchId,
          source: row.source,
          verification_date: row.verificationDate,
          publication_status: row.publicationStatus,
        },
      })),
    );

  if (insertError) {
    return actionError(
      "Import could not be completed. No inventory rows were confirmed.",
    );
  }

  revalidatePath("/dashboard/inventory");
  revalidatePath("/dashboard/inventory/import");

  return {
    status: "success",
    message: `${safeRows.length} units imported with source and verification metadata.`,
    importedCount: safeRows.length,
  };
}
