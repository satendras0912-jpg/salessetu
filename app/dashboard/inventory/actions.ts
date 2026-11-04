"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";

function readText(formData: FormData, key: string, maxLength = 240): string {
  const value = formData.get(key);

  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, maxLength);
}

function readOptionalNumber(formData: FormData, key: string): number | null {
  const value = readText(formData, key, 40);

  if (!value) {
    return null;
  }

  const parsed = Number(value);

  return Number.isFinite(parsed) && parsed >= 0 ? parsed : null;
}

function inventoryRedirect(params: Record<string, string>): never {
  const searchParams = new URLSearchParams(params);

  redirect(`/dashboard/inventory?${searchParams.toString()}`);
}

function inputError(message: string): never {
  inventoryRedirect({
    error: message,
  });
}

export async function createBuilderAction(formData: FormData): Promise<void> {
  const { context } = await requirePermissionAccess({
    allOf: [
      "inventory.view",
      "inventory.manage_builders",
    ],
    loginRedirectTo: "/login?next=/dashboard/inventory",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    inputError("Active organization context is required.");
  }

  const builderCode = readText(formData, "builderCode", 64).toUpperCase();
  const legalName = readText(formData, "legalName");
  const brandName = readText(formData, "brandName");
  const city = readText(formData, "city", 120);

  if (!builderCode || !legalName || !brandName) {
    inputError("Builder code, legal name and brand name are required.");
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("builders")
    .insert({
      organization_id: organizationId,
      builder_code: builderCode,
      legal_name: legalName,
      brand_name: brandName,
      city: city || null,
      status: "active",
    });

  if (error) {
    inputError("Builder could not be saved. Check that the code is unique.");
  }

  revalidatePath("/dashboard/inventory");
  inventoryRedirect({
    created: "builder",
  });
}

export async function createProjectAction(formData: FormData): Promise<void> {
  const { context } = await requirePermissionAccess({
    allOf: [
      "inventory.view",
      "inventory.manage_projects",
    ],
    loginRedirectTo: "/login?next=/dashboard/inventory",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    inputError("Active organization context is required.");
  }

  const builderId = readText(formData, "builderId", 64);
  const projectCode = readText(formData, "projectCode", 64).toUpperCase();
  const projectName = readText(formData, "projectName");
  const city = readText(formData, "city", 120);
  const basePricePerSqft = readOptionalNumber(formData, "basePricePerSqft");

  if (!builderId || !projectCode || !projectName || !city) {
    inputError("Builder, project code, project name and city are required.");
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("projects")
    .insert({
      organization_id: organizationId,
      builder_id: builderId,
      project_code: projectCode,
      project_name: projectName,
      project_type: "residential",
      development_type: "under_construction",
      status: "active",
      inventory_status: "not_released",
      city,
      base_price_per_sqft: basePricePerSqft,
    });

  if (error) {
    inputError("Project could not be saved. Check the project code and builder.");
  }

  revalidatePath("/dashboard/inventory");
  inventoryRedirect({
    created: "project",
  });
}

export async function createInventoryUnitAction(formData: FormData): Promise<void> {
  const { context } = await requirePermissionAccess({
    allOf: [
      "inventory.view",
      "inventory.create",
    ],
    loginRedirectTo: "/login?next=/dashboard/inventory",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    inputError("Active organization context is required.");
  }

  const projectId = readText(formData, "projectId", 64);
  const inventoryCode = readText(formData, "inventoryCode", 64).toUpperCase();
  const unitNumber = readText(formData, "unitNumber", 64);
  const unitStatus = readText(formData, "unitStatus", 40);
  const propertyType = readText(formData, "propertyType", 40);
  const currentPrice = readOptionalNumber(formData, "currentPrice");
  const floorNumber = readOptionalNumber(formData, "floorNumber");
  const bedrooms = readOptionalNumber(formData, "bedrooms");
  const superArea = readOptionalNumber(formData, "superArea");

  const allowedStatuses = new Set([
    "not_released",
    "available",
    "management_hold",
  ]);

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

  if (
    !projectId ||
    !inventoryCode ||
    !unitNumber ||
    !allowedStatuses.has(unitStatus) ||
    !allowedPropertyTypes.has(propertyType)
  ) {
    inputError("Project, inventory code, unit number, valid type and status are required.");
  }

  const supabase = await createClient();
  const { error } = await supabase
    .from("inventory_units")
    .insert({
      organization_id: organizationId,
      project_id: projectId,
      inventory_code: inventoryCode,
      unit_number: unitNumber,
      property_type: propertyType,
      unit_status: unitStatus,
      sales_status: unitStatus === "available" ? "open" : "on_hold",
      current_price: currentPrice,
      floor_number: floorNumber,
      bedrooms,
      super_area: superArea,
      currency: "INR",
      inventory_source: "manual",
    });

  if (error) {
    inputError("Unit could not be saved. Check that its code and number are unique.");
  }

  revalidatePath("/dashboard/inventory");
  inventoryRedirect({
    created: "unit",
  });
}
