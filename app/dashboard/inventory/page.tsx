import Link from "next/link";
import { redirect } from "next/navigation";

import {
  createBuilderAction,
  createInventoryUnitAction,
  createProjectAction,
} from "@/app/dashboard/inventory/actions";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

type RawSearchParams = Record<string, string | string[] | undefined>;

type InventoryPageProps = {
  searchParams: Promise<RawSearchParams>;
};

type BuilderRow = {
  id: string;
  builder_code: string;
  brand_name: string;
  legal_name: string;
  city: string | null;
};

type ProjectRow = {
  id: string;
  project_code: string;
  project_name: string;
  city: string;
  status: string;
  inventory_status: string;
  total_units: number | null;
  available_units: number | null;
  sold_units: number | null;
  base_price_per_sqft: number | null;
};

type InventoryUnitRow = {
  id: string;
  project_id: string;
  inventory_code: string;
  unit_number: string;
  property_type: string;
  unit_status: string;
  sales_status: string;
  current_price: number | null;
  all_inclusive_price: number | null;
  currency: string;
  floor_number: number | null;
  bedrooms: number | null;
  super_area: number | null;
  created_at: string;
};

function getSingleValue(
  value: string | string[] | undefined,
): string {
  return Array.isArray(value) ? value[0] ?? "" : value ?? "";
}

function formatCurrency(
  value: number | null,
  currency = "INR",
): string {
  if (value === null || !Number.isFinite(value)) {
    return "Not set";
  }

  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency,
    maximumFractionDigits: 0,
  }).format(value);
}

function formatUnitStatus(status: string): string {
  return status.replaceAll("_", " ");
}

function statusClass(status: string): string {
  if (status === "available") {
    return "border-emerald-500/50 bg-emerald-500/10 text-emerald-300";
  }

  if (status === "reserved" || status === "token_received") {
    return "border-amber-500/50 bg-amber-500/10 text-amber-300";
  }

  if (status === "booked" || status === "sold") {
    return "border-cyan-500/50 bg-cyan-500/10 text-cyan-300";
  }

  return "border-slate-700 bg-slate-800 text-slate-300";
}

function noticeCopy(created: string): string | null {
  if (created === "builder") {
    return "Builder saved. You can now add a project.";
  }

  if (created === "project") {
    return "Project saved. Add individual units to begin availability tracking.";
  }

  if (created === "unit") {
    return "Unit saved. Project availability totals are refreshed automatically.";
  }

  return null;
}

export default async function InventoryDashboardPage({
  searchParams,
}: InventoryPageProps) {
  const { context } = await requirePermissionAccess({
    allOf: ["inventory.view"],
    loginRedirectTo: "/login?next=/dashboard/inventory",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    redirect("/auth-error?reason=organization_context_missing");
  }

  const rawParams = await searchParams;
  const requestedProjectId = getSingleValue(rawParams.projectId).trim();
  const requestedStatus = getSingleValue(rawParams.status).trim();
  const createdNotice = noticeCopy(getSingleValue(rawParams.created).trim());
  const errorNotice = getSingleValue(rawParams.error).trim();

  const supabase = await createClient();

  const [
    buildersResponse,
    projectsResponse,
    unitsResponse,
  ] = await Promise.all([
    supabase
      .from("builders")
      .select("id,builder_code,brand_name,legal_name,city")
      .eq("organization_id", organizationId)
      .is("deleted_at", null)
      .order("brand_name"),
    supabase
      .from("projects")
      .select("id,project_code,project_name,city,status,inventory_status,total_units,available_units,sold_units,base_price_per_sqft")
      .eq("organization_id", organizationId)
      .is("deleted_at", null)
      .order("project_name"),
    supabase
      .from("inventory_units")
      .select("id,project_id,inventory_code,unit_number,property_type,unit_status,sales_status,current_price,all_inclusive_price,currency,floor_number,bedrooms,super_area,created_at")
      .eq("organization_id", organizationId)
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .limit(500),
  ]);

  if (
    buildersResponse.error ||
    projectsResponse.error ||
    unitsResponse.error
  ) {
    throw new Error(
      "Inventory data could not be loaded. Verify the inventory migration and workspace permissions.",
    );
  }

  const builders = (buildersResponse.data ?? []) as BuilderRow[];
  const projects = (projectsResponse.data ?? []) as ProjectRow[];
  const units = (unitsResponse.data ?? []) as InventoryUnitRow[];
  const projectById = new Map(
    projects.map((project) => [project.id, project]),
  );

  const allowedStatuses = new Set([
    "",
    "not_released",
    "available",
    "reserved",
    "blocked",
    "token_received",
    "booked",
    "sold",
    "management_hold",
    "unavailable",
  ]);

  const visibleUnits = units.filter((unit) => {
    const matchesProject =
      !requestedProjectId ||
      unit.project_id === requestedProjectId;

    const matchesStatus =
      !requestedStatus ||
      unit.unit_status === requestedStatus;

    return matchesProject && matchesStatus;
  });

  const availableUnits = units.filter(
    (unit) => unit.unit_status === "available",
  );

  const reservedUnits = units.filter((unit) =>
    ["reserved", "token_received"].includes(unit.unit_status),
  );

  const soldUnits = units.filter((unit) =>
    ["booked", "sold"].includes(unit.unit_status),
  );

  const availableValue = availableUnits.reduce(
    (total, unit) =>
      total + (unit.current_price ?? unit.all_inclusive_price ?? 0),
    0,
  );

  const showForms =
    context.membership?.isOwner ||
    true;

  return (
    <div className="space-y-8">
      <header className="flex flex-col justify-between gap-6 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            PropertyOS
          </p>

          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
            Inventory &amp; Availability
          </h1>

          <p className="mt-3 max-w-3xl text-base leading-7 text-slate-400">
            Builder, project aur unit-level stock ko ek jagah maintain karein.
            Deal banate waqt sirf current availability par kaam karein.
          </p>
        </div>

        <div className="rounded-2xl border border-slate-800 bg-slate-900 px-5 py-4">
          <p className="text-xs uppercase tracking-wider text-slate-500">
            Active workspace
          </p>

          <p className="mt-1 font-semibold text-white">
            {context.organization?.name ?? "SalesSetu Workspace"}
          </p>
        </div>
      </header>

      {createdNotice ? (
        <p className="rounded-2xl border border-emerald-500/40 bg-emerald-500/10 px-5 py-4 text-sm text-emerald-200">
          {createdNotice}
        </p>
      ) : null}

      {errorNotice ? (
        <p className="rounded-2xl border border-rose-500/40 bg-rose-500/10 px-5 py-4 text-sm text-rose-200">
          {errorNotice}
        </p>
      ) : null}

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">Units tracked</p>
          <p className="mt-2 text-3xl font-bold text-white">
            {units.length.toLocaleString("en-IN")}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">Available now</p>
          <p className="mt-2 text-3xl font-bold text-emerald-300">
            {availableUnits.length.toLocaleString("en-IN")}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">Reserved / token</p>
          <p className="mt-2 text-3xl font-bold text-amber-300">
            {reservedUnits.length.toLocaleString("en-IN")}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="text-sm text-slate-500">Available inventory value</p>
          <p className="mt-2 text-2xl font-bold text-cyan-300">
            {formatCurrency(availableValue)}
          </p>
        </article>
      </section>

      {showForms ? (
        <section className="grid gap-6 xl:grid-cols-3">
          <form
            action={createBuilderAction}
            className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6"
          >
            <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
              Step 1
            </p>
            <h2 className="mt-2 text-xl font-bold text-white">
              Add builder
            </h2>

            <div className="mt-5 space-y-3">
              <input
                required
                name="builderCode"
                placeholder="Builder code, e.g. SKA"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                required
                name="legalName"
                placeholder="Legal name"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                required
                name="brandName"
                placeholder="Brand name"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                name="city"
                placeholder="Primary city (optional)"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
            </div>

            <button
              type="submit"
              className="mt-5 w-full rounded-xl bg-cyan-400 px-4 py-3 text-sm font-bold text-slate-950 transition hover:bg-cyan-300"
            >
              Save builder
            </button>
          </form>

          <form
            action={createProjectAction}
            className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6"
          >
            <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
              Step 2
            </p>
            <h2 className="mt-2 text-xl font-bold text-white">
              Add project
            </h2>

            <div className="mt-5 space-y-3">
              <select
                required
                name="builderId"
                defaultValue=""
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white"
              >
                <option value="" disabled>
                  Select builder
                </option>
                {builders.map((builder) => (
                  <option key={builder.id} value={builder.id}>
                    {builder.brand_name} · {builder.builder_code}
                  </option>
                ))}
              </select>
              <input
                required
                name="projectCode"
                placeholder="Project code, e.g. CALISTO"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                required
                name="projectName"
                placeholder="Project name"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                required
                name="city"
                placeholder="City"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                inputMode="decimal"
                name="basePricePerSqft"
                placeholder="Base price / sq ft (optional)"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
            </div>

            <button
              type="submit"
              disabled={builders.length === 0}
              className="mt-5 w-full rounded-xl bg-cyan-400 px-4 py-3 text-sm font-bold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-40"
            >
              Save project
            </button>
          </form>

          <form
            action={createInventoryUnitAction}
            className="rounded-3xl border border-cyan-500/40 bg-slate-900/70 p-6"
          >
            <p className="text-xs font-semibold uppercase tracking-[0.25em] text-cyan-400">
              Step 3
            </p>
            <h2 className="mt-2 text-xl font-bold text-white">
              Add unit
            </h2>

            <div className="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-1">
              <select
                required
                name="projectId"
                defaultValue=""
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white"
              >
                <option value="" disabled>
                  Select project
                </option>
                {projects.map((project) => (
                  <option key={project.id} value={project.id}>
                    {project.project_name}
                  </option>
                ))}
              </select>
              <input
                required
                name="inventoryCode"
                placeholder="Inventory code"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                required
                name="unitNumber"
                placeholder="Unit number"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <select
                required
                name="propertyType"
                defaultValue="apartment"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white"
              >
                <option value="apartment">Apartment</option>
                <option value="villa">Villa</option>
                <option value="plot">Plot</option>
                <option value="shop">Shop</option>
                <option value="office">Office</option>
                <option value="other">Other</option>
              </select>
              <select
                required
                name="unitStatus"
                defaultValue="available"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white"
              >
                <option value="available">Available</option>
                <option value="not_released">Not released</option>
                <option value="management_hold">Management hold</option>
              </select>
              <input
                inputMode="decimal"
                name="currentPrice"
                placeholder="Current price (optional)"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                inputMode="numeric"
                name="floorNumber"
                placeholder="Floor (optional)"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                inputMode="decimal"
                name="bedrooms"
                placeholder="Bedrooms (optional)"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
              <input
                inputMode="decimal"
                name="superArea"
                placeholder="Super area sq ft (optional)"
                className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white placeholder:text-slate-600"
              />
            </div>

            <button
              type="submit"
              disabled={projects.length === 0}
              className="mt-5 w-full rounded-xl bg-cyan-400 px-4 py-3 text-sm font-bold text-slate-950 transition hover:bg-cyan-300 disabled:cursor-not-allowed disabled:opacity-40"
            >
              Save unit
            </button>
          </form>
        </section>
      ) : null}

      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
        <div className="flex flex-col justify-between gap-4 md:flex-row md:items-end">
          <div>
            <h2 className="text-2xl font-bold text-white">
              Availability dashboard
            </h2>
            <p className="mt-2 text-sm text-slate-400">
              Available stock can be selected during deal conversion. Reserve,
              booking aur sold status remain audit-controlled.
            </p>
          </div>

          <Link
            href="/dashboard/deals"
            className="rounded-xl border border-cyan-500/50 px-4 py-3 text-sm font-semibold text-cyan-300 transition hover:bg-cyan-500/10"
          >
            Open Deal Operations
          </Link>
        </div>

        <form
          action="/dashboard/inventory"
          method="get"
          className="mt-6 grid gap-3 md:grid-cols-3"
        >
          <select
            name="projectId"
            defaultValue={requestedProjectId}
            className="rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white"
          >
            <option value="">All projects</option>
            {projects.map((project) => (
              <option key={project.id} value={project.id}>
                {project.project_name} · {project.city}
              </option>
            ))}
          </select>

          <select
            name="status"
            defaultValue={allowedStatuses.has(requestedStatus) ? requestedStatus : ""}
            className="rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-sm text-white"
          >
            <option value="">All availability</option>
            <option value="available">Available</option>
            <option value="not_released">Not released</option>
            <option value="reserved">Reserved</option>
            <option value="token_received">Token received</option>
            <option value="booked">Booked</option>
            <option value="sold">Sold</option>
            <option value="management_hold">Management hold</option>
          </select>

          <button
            type="submit"
            className="rounded-xl border border-slate-600 px-4 py-3 text-sm font-semibold text-slate-200 transition hover:border-cyan-500 hover:text-cyan-300"
          >
            Apply filter
          </button>
        </form>

        <div className="mt-6 overflow-x-auto rounded-2xl border border-slate-800">
          <table className="min-w-[1000px] divide-y divide-slate-800 text-left text-sm">
            <thead className="bg-slate-950/70 text-xs uppercase tracking-wider text-slate-500">
              <tr>
                <th className="px-5 py-4">Project / unit</th>
                <th className="px-5 py-4">Type</th>
                <th className="px-5 py-4">Configuration</th>
                <th className="px-5 py-4">Price</th>
                <th className="px-5 py-4">Availability</th>
                <th className="px-5 py-4">Sales</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800">
              {visibleUnits.map((unit) => {
                const project = projectById.get(unit.project_id);

                return (
                  <tr key={unit.id} className="bg-slate-900/30">
                    <td className="px-5 py-5">
                      <p className="font-semibold text-white">
                        {unit.unit_number}
                      </p>
                      <p className="mt-1 text-slate-400">
                        {project?.project_name ?? "Project unavailable"}
                      </p>
                      <p className="mt-1 text-xs text-slate-600">
                        {unit.inventory_code}
                      </p>
                    </td>
                    <td className="px-5 py-5 capitalize text-slate-300">
                      {unit.property_type}
                    </td>
                    <td className="px-5 py-5 text-slate-300">
                      <p>{unit.bedrooms ? `${unit.bedrooms} BHK` : "Not set"}</p>
                      <p className="mt-1 text-slate-500">
                        {unit.super_area
                          ? `${unit.super_area.toLocaleString("en-IN")} sq ft`
                          : "Area not set"}
                      </p>
                    </td>
                    <td className="px-5 py-5 font-medium text-white">
                      {formatCurrency(
                        unit.current_price ?? unit.all_inclusive_price,
                        unit.currency,
                      )}
                    </td>
                    <td className="px-5 py-5">
                      <span className={`inline-flex rounded-full border px-3 py-1 text-xs font-semibold capitalize ${statusClass(unit.unit_status)}`}>
                        {formatUnitStatus(unit.unit_status)}
                      </span>
                    </td>
                    <td className="px-5 py-5 capitalize text-slate-300">
                      {formatUnitStatus(unit.sales_status)}
                    </td>
                  </tr>
                );
              })}
              {visibleUnits.length === 0 ? (
                <tr>
                  <td
                    colSpan={6}
                    className="px-5 py-12 text-center text-slate-500"
                  >
                    No inventory units match this view. Add a builder, project
                    and unit above to start tracking availability.
                  </td>
                </tr>
              ) : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6">
        <h2 className="text-xl font-bold text-white">Project readiness</h2>
        <div className="mt-5 grid gap-4 lg:grid-cols-2">
          {projects.map((project) => (
            <article
              key={project.id}
              className="rounded-2xl border border-slate-800 bg-slate-950/40 p-5"
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <p className="font-semibold text-white">
                    {project.project_name}
                  </p>
                  <p className="mt-1 text-sm text-slate-500">
                    {project.project_code} · {project.city}
                  </p>
                </div>
                <span className={`rounded-full border px-3 py-1 text-xs font-semibold ${statusClass(project.inventory_status === "limited" ? "reserved" : project.inventory_status)}`}>
                  {formatUnitStatus(project.inventory_status)}
                </span>
              </div>

              <div className="mt-5 grid grid-cols-3 gap-3 text-sm">
                <div>
                  <p className="text-slate-500">Tracked</p>
                  <p className="mt-1 font-semibold text-white">
                    {project.total_units ?? 0}
                  </p>
                </div>
                <div>
                  <p className="text-slate-500">Available</p>
                  <p className="mt-1 font-semibold text-emerald-300">
                    {project.available_units ?? 0}
                  </p>
                </div>
                <div>
                  <p className="text-slate-500">Booked / sold</p>
                  <p className="mt-1 font-semibold text-cyan-300">
                    {project.sold_units ?? 0}
                  </p>
                </div>
              </div>
            </article>
          ))}
          {projects.length === 0 ? (
            <p className="text-sm text-slate-500">
              No projects added yet.
            </p>
          ) : null}
        </div>
      </section>
    </div>
  );
}
