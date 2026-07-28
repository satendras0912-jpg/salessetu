"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

type DashboardSidebarProps = {
  organizationName: string;
  userEmail: string;
  roleLabel: string;
  isOwner: boolean;
  permissionCodes: readonly string[];
};

type NavigationItem = {
  label: string;
  description: string;
  href: string;
  requiredPermissions: readonly string[];
  exactMatch?: boolean;
};

const navigationItems: readonly NavigationItem[] = [
  {
    label: "Overview",
    description: "Workspace summary",
    href: "/dashboard",
    requiredPermissions: ["dashboard.view"],
    exactMatch: true,
  },
  {
    label: "Organization Context",
    description: "Membership and role details",
    href: "/dashboard/context",
    requiredPermissions: [
      "dashboard.context.read",
    ],
  },
];

function normalizePermissionCode(
  value: string,
): string {
  return value.trim().toLowerCase();
}

export default function DashboardSidebar({
  organizationName,
  userEmail,
  roleLabel,
  isOwner,
  permissionCodes,
}: DashboardSidebarProps) {
  const pathname = usePathname();

  const permissionSet = new Set(
    permissionCodes
      .map(normalizePermissionCode)
      .filter(Boolean),
  );

  const visibleNavigationItems =
    navigationItems.filter((item) =>
      item.requiredPermissions.every(
        (permissionCode) =>
          permissionSet.has(
            normalizePermissionCode(
              permissionCode,
            ),
          ),
      ),
    );

  return (
    <aside className="border-slate-800 bg-slate-900 lg:fixed lg:inset-y-0 lg:left-0 lg:z-30 lg:w-72 lg:border-r">
      <div className="flex min-h-full flex-col">
        <div className="border-b border-slate-800 px-6 py-7">
          <p className="text-xs font-semibold uppercase tracking-[0.3em] text-cyan-400">
            SalesSetu
          </p>

          <h1 className="mt-3 text-2xl font-bold text-white">
            Enterprise Console
          </h1>
        </div>

        <div className="border-b border-slate-800 px-6 py-6">
          <p className="text-xs font-medium uppercase tracking-wider text-slate-500">
            Active workspace
          </p>

          <p className="mt-3 truncate text-lg font-semibold text-slate-100">
            {organizationName}
          </p>

          <div className="mt-4 flex flex-wrap gap-2">
            <span className="rounded-full border border-cyan-700 bg-cyan-950/60 px-3 py-1 text-xs font-medium text-cyan-300">
              {roleLabel}
            </span>

            {isOwner ? (
              <span className="rounded-full border border-amber-700 bg-amber-950/40 px-3 py-1 text-xs font-medium text-amber-300">
                Owner
              </span>
            ) : null}
          </div>
        </div>

        <nav
          aria-label="Dashboard navigation"
          className="flex-1 space-y-2 px-4 py-5"
        >
          {visibleNavigationItems.map(
            (item) => {
              const isActive =
                item.exactMatch
                  ? pathname === item.href
                  : pathname === item.href ||
                    pathname.startsWith(
                      `${item.href}/`,
                    );

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  aria-current={
                    isActive
                      ? "page"
                      : undefined
                  }
                  className={`block rounded-2xl border px-4 py-4 transition ${
                    isActive
                      ? "border-cyan-700 bg-cyan-950/50"
                      : "border-transparent hover:border-slate-700 hover:bg-slate-800/70"
                  }`}
                >
                  <span
                    className={`block font-semibold ${
                      isActive
                        ? "text-cyan-100"
                        : "text-slate-200"
                    }`}
                  >
                    {item.label}
                  </span>

                  <span
                    className={`mt-1 block text-sm ${
                      isActive
                        ? "text-cyan-400"
                        : "text-slate-500"
                    }`}
                  >
                    {item.description}
                  </span>
                </Link>
              );
            },
          )}

          {visibleNavigationItems.length ===
          0 ? (
            <div className="rounded-2xl border border-slate-800 bg-slate-950/50 px-4 py-4">
              <p className="text-sm font-medium text-slate-300">
                No accessible modules
              </p>

              <p className="mt-1 text-xs leading-5 text-slate-500">
                Your account currently has no
                dashboard module permissions.
              </p>
            </div>
          ) : null}
        </nav>

        <div className="border-t border-slate-800 px-6 py-6">
          <p className="text-xs font-medium uppercase tracking-wider text-slate-500">
            Signed in as
          </p>

          <p className="mt-2 truncate text-sm text-slate-200">
            {userEmail}
          </p>
        </div>
      </div>
    </aside>
  );
}