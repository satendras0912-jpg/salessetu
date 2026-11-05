import "server-only";

import { createClient } from "@/lib/supabase/server";

import type { LeadDetailRecord } from "@/types/lead-detail";

type NumericValue = number | string | null;

type InventoryProjectRow = {
  project_code: string | null;
  project_name: string | null;
  city: string | null;
  locality: string | null;
};

type InventoryRow = {
  id: string;
  inventory_code: string;
  unit_number: string;
  property_type: string;
  current_price: NumericValue;
  currency: string;
  bedrooms: NumericValue;
  super_area: NumericValue;
  floor_number: number | null;
  inventory_source: string;
  metadata: unknown;
  projects: InventoryProjectRow | InventoryProjectRow[] | null;
};

export type LeadInventoryMatchSuggestion = {
  inventoryUnitId: string;
  inventoryCode: string;
  unitNumber: string;
  projectCode: string | null;
  projectName: string | null;
  city: string | null;
  locality: string | null;
  propertyType: string;
  bedrooms: number | null;
  superArea: number | null;
  floorNumber: number | null;
  currentPrice: number | null;
  currency: string;
  source: string;
  verificationDate: string;
  score: number;
  matchReasons: string[];
};

function toNumber(value: NumericValue): number | null {
  if (typeof value !== "number" && typeof value !== "string") {
    return null;
  }

  const parsed = Number(value);

  return Number.isFinite(parsed) ? parsed : null;
}

function readTextMetadata(
  value: unknown,
  key: string,
): string | null {
  if (
    !value ||
    typeof value !== "object" ||
    Array.isArray(value)
  ) {
    return null;
  }

  const candidate = (value as Record<string, unknown>)[key];

  return typeof candidate === "string" && candidate.trim()
    ? candidate.trim()
    : null;
}

function normalized(value: string | null | undefined): string {
  return (value ?? "")
    .trim()
    .toLocaleLowerCase("en-IN");
}

function textMatches(
  expected: string | null | undefined,
  actual: string | null | undefined,
): boolean {
  const cleanExpected = normalized(expected);
  const cleanActual = normalized(actual);

  return Boolean(
    cleanExpected &&
    cleanActual &&
    (
      cleanExpected.includes(cleanActual) ||
      cleanActual.includes(cleanExpected)
    ),
  );
}

function hasMatchBasis(lead: LeadDetailRecord): boolean {
  return Boolean(
    lead.preferredProject?.trim() ||
    lead.preferredLocation?.trim() ||
    lead.preferredCity?.trim() ||
    lead.propertyType?.trim() ||
    lead.bedrooms !== null ||
    lead.budgetMin !== null ||
    lead.budgetMax !== null,
  );
}

function buildSuggestion(
  lead: LeadDetailRecord,
  unit: InventoryRow,
): LeadInventoryMatchSuggestion | null {
  const verificationDate = readTextMetadata(
    unit.metadata,
    "verification_date",
  );

  // Only imported/verified availability is surfaced as a recommendation.
  if (!verificationDate) {
    return null;
  }

  const project = Array.isArray(unit.projects)
    ? unit.projects[0] ?? null
    : unit.projects;
  const price = toNumber(unit.current_price);
  const bedrooms = toNumber(unit.bedrooms);
  const superArea = toNumber(unit.super_area);
  const matchReasons: string[] = [];
  let score = 0;

  if (
    textMatches(lead.preferredProject, project?.project_name) ||
    textMatches(lead.preferredProject, project?.project_code)
  ) {
    score += 35;
    matchReasons.push("Preferred project");
  }

  if (textMatches(lead.propertyType, unit.property_type)) {
    score += 20;
    matchReasons.push("Property type");
  }

  if (textMatches(lead.preferredCity, project?.city)) {
    score += 10;
    matchReasons.push("Preferred city");
  }

  if (textMatches(lead.preferredLocation, project?.locality)) {
    score += 10;
    matchReasons.push("Preferred location");
  }

  if (
    lead.bedrooms !== null &&
    bedrooms !== null &&
    lead.bedrooms === bedrooms
  ) {
    score += 10;
    matchReasons.push("Bedroom requirement");
  }

  if (price !== null) {
    const meetsMinimum =
      lead.budgetMin === null || price >= lead.budgetMin;
    const meetsMaximum =
      lead.budgetMax === null || price <= lead.budgetMax;

    if (meetsMinimum && meetsMaximum && (
      lead.budgetMin !== null || lead.budgetMax !== null
    )) {
      score += 15;
      matchReasons.push("Stated budget");
    }
  }

  if (score === 0) {
    return null;
  }

  return {
    inventoryUnitId: unit.id,
    inventoryCode: unit.inventory_code,
    unitNumber: unit.unit_number,
    projectCode: project?.project_code ?? null,
    projectName: project?.project_name ?? null,
    city: project?.city ?? null,
    locality: project?.locality ?? null,
    propertyType: unit.property_type,
    bedrooms,
    superArea,
    floorNumber: unit.floor_number,
    currentPrice: price,
    currency: unit.currency || "INR",
    source: readTextMetadata(unit.metadata, "source") ?? unit.inventory_source,
    verificationDate,
    score,
    matchReasons,
  };
}

export async function getLeadInventoryMatchSuggestions(
  organizationId: string,
  lead: LeadDetailRecord,
): Promise<LeadInventoryMatchSuggestion[]> {
  if (!organizationId.trim() || !hasMatchBasis(lead)) {
    return [];
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("inventory_units")
    .select(`
      id,
      inventory_code,
      unit_number,
      property_type,
      current_price,
      currency,
      bedrooms,
      super_area,
      floor_number,
      inventory_source,
      metadata,
      projects!inner(
        project_code,
        project_name,
        city,
        locality
      )
    `)
    .eq("organization_id", organizationId)
    .eq("unit_status", "available")
    .eq("sales_status", "open")
    .is("deleted_at", null)
    .limit(120);

  if (error) {
    throw new Error(
      `Unable to load verified inventory suggestions: ${error.message}`,
    );
  }

  return (data ?? [])
    .map((row) => buildSuggestion(lead, row as InventoryRow))
    .filter((suggestion): suggestion is LeadInventoryMatchSuggestion =>
      suggestion !== null,
    )
    .sort((first, second) => second.score - first.score)
    .slice(0, 6);
}
