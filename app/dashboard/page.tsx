import Link from "next/link";

import DashboardModules from "@/components/dashboard/DashboardModules";
import { requirePermissionAccess } from "@/lib/auth/access-control";

function extractCodesFromCollection(
  collection: unknown,
): string[] {
  const items =
    collection instanceof Set
      ? Array.from(collection)
      : Array.isArray(collection)
        ? collection
        : [];

  return items.flatMap((item) => {
    if (typeof item === "string") {
      return [item];
    }

    if (
      item !== null &&
      typeof item === "object" &&
      "code" in item
    ) {
      const code = (
        item as {
          code?: unknown;
        }
      ).code;

      return typeof code === "string" ? [code] : [];
    }

    return [];
  });
}

function extractPermissionCodes(
  permissionContext: unknown,
): string[] {
  const directCodes =
    extractCodesFromCollection(permissionContext);

  if (directCodes.length > 0) {
    return Array.from(new Set(directCodes));
  }

  if (
    permissionContext === null ||
    typeof permissionContext !== "object"
  ) {
    return [];
  }

  const context = permissionContext as Record<
    string,
    unknown
  >;

  const possibleCollections: unknown[] = [
    context.codes,
    context.permissionCodes,
    context.permissions,
    context.effectivePermissions,
    context.items,
  ];

  for (const collection of possibleCollections) {
    const codes = extractCodesFromCollection(collection);

    if (codes.length > 0) {
      return Array.from(new Set(codes));
    }
  }

  return [];
}

export default async function DashboardPage() {
  const { context, permissions } =
    await requirePermissionAccess({
      allOf: ["dashboard.view"],
      loginRedirectTo: "/login?next=/dashboard",
      unauthorizedRedirectTo: "/unauthorized",
    });

  const permissionCodes =
    extractPermissionCodes(permissions);

  const organization = context.organization;
  const membership = context.membership;
  const roles = context.roles ?? [];

  const organizationName =
    organization?.name ?? "SalesSetu Workspace";

  const organizationSlug =
    organization?.slug ?? "workspace";

  const organizationStatus =
    organization?.status ?? "active";

  const userEmail =
    context.user.email ?? "Unknown user";

  const isOwner = Boolean(membership?.isOwner);

  const primaryRole =
    roles[0]?.name ??
    roles[0]?.code ??
    "Workspace Member";

  return (
    <div className="space-y-9">
      {/* Page heading */}
      <header className="flex flex-col justify-between gap-6 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            SalesSetu Enterprise
          </p>

          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white sm:text-5xl">
            Platform Dashboard
          </h1>

          <p className="mt-4 max-w-3xl text-base leading-7 text-slate-400">
            Your authenticated SalesSetu organization
            workspace is active and protected through
            server-side membership, role and permission
            validation.
          </p>
        </div>

        <Link
          href="/dashboard/context"
          className="inline-flex w-fit items-center justify-center rounded-xl bg-cyan-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-cyan-300 focus:outline-none focus:ring-2 focus:ring-cyan-300"
        >
          View organization context
        </Link>
      </header>

      {/* Workspace summary */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-6">
          <p className="text-sm text-slate-500">
            Authentication
          </p>

          <p className="mt-3 text-2xl font-bold text-emerald-300">
            Active
          </p>

          <p className="mt-2 text-sm text-slate-500">
            Server session verified
          </p>
        </article>

        <article className="min-w-0 rounded-2xl border border-slate-800 bg-slate-900/70 p-6">
          <p className="text-sm text-slate-500">
            Organization
          </p>

          <p className="mt-3 truncate text-2xl font-bold text-white">
            {organizationName}
          </p>

          <p className="mt-2 truncate text-sm text-slate-500">
            {organizationSlug}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-6">
          <p className="text-sm text-slate-500">
            Membership
          </p>

          <p className="mt-3 text-2xl font-bold text-cyan-300">
            Active
          </p>

          <p className="mt-2 text-sm text-slate-500">
            {isOwner
              ? "Workspace owner"
              : "Organization member"}
          </p>
        </article>

        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-6">
          <p className="text-sm text-slate-500">
            Assigned roles
          </p>

          <p className="mt-3 text-2xl font-bold text-white">
            {roles.length}
          </p>

          <p className="mt-2 truncate text-sm text-slate-500">
            {primaryRole}
          </p>
        </article>
      </section>

      {/* Enterprise foundation */}
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
        <div className="flex flex-col justify-between gap-5 xl:flex-row xl:items-center">
          <div>
            <h2 className="text-2xl font-bold text-white">
              Enterprise foundation status
            </h2>

            <p className="mt-2 max-w-3xl text-sm leading-6 text-slate-400">
              Authentication, organization membership,
              role resolution, permission evaluation and
              protected dashboard routing are operational.
            </p>
          </div>

          <span className="w-fit rounded-full border border-emerald-500/40 bg-emerald-500/10 px-4 py-2 text-sm font-medium capitalize text-emerald-300">
            {organizationStatus}
          </span>
        </div>

        <div className="mt-7 grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
          {[
            "Supabase SSR",
            "Authentication guard",
            "Organization context",
            "RBAC foundation",
          ].map((item) => (
            <article
              key={item}
              className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5"
            >
              <div className="flex items-center gap-3">
                <span
                  aria-hidden="true"
                  className="h-2.5 w-2.5 rounded-full bg-emerald-400"
                />

                <p className="font-medium text-slate-200">
                  {item}
                </p>
              </div>

              <p className="mt-3 text-sm text-emerald-400">
                Operational
              </p>
            </article>
          ))}
        </div>
      </section>

      {/* Permission-aware platform modules */}
      <DashboardModules
        permissionCodes={permissionCodes}
        isOwner={isOwner}
      />

      {/* Current session */}
      <section className="rounded-3xl border border-slate-800 bg-slate-900/70 p-6 sm:p-8">
        <h2 className="text-xl font-bold text-white">
          Current session
        </h2>

        <div className="mt-6 grid gap-4 md:grid-cols-3">
          <article className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5">
            <p className="text-xs uppercase tracking-wider text-slate-500">
              Signed-in user
            </p>

            <p className="mt-2 break-all text-sm font-medium text-slate-200">
              {userEmail}
            </p>
          </article>

          <article className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5">
            <p className="text-xs uppercase tracking-wider text-slate-500">
              Primary role
            </p>

            <p className="mt-2 text-sm font-medium text-slate-200">
              {primaryRole}
            </p>
          </article>

          <article className="rounded-2xl border border-slate-800 bg-slate-950/70 p-5">
            <p className="text-xs uppercase tracking-wider text-slate-500">
              Effective permissions
            </p>

            <p className="mt-2 text-sm font-medium text-cyan-300">
              {permissionCodes.length.toLocaleString(
                "en-IN",
              )}
            </p>
          </article>
        </div>
      </section>
    </div>
  );
}