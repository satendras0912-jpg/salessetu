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
  href: string;
  label: string;
  description: string;
  permission?: string;
  exact?: boolean;
};

const navigationItems: NavigationItem[] = [
  {
    href: "/dashboard",
    label: "Overview",
    description: "Workspace summary",
    permission: "dashboard.view",
    exact: true,
  },
  {
    href: "/dashboard/leads",
    label: "Lead Operations",
    description: "Validation and assignment",
    permission: "leads.view",
  },
  {
    href: "/dashboard/context",
    label: "Organization Context",
    description: "Membership and role details",
    permission: "dashboard.context.read",
  },
];

function isNavigationItemActive(
  pathname: string,
  item: NavigationItem,
): boolean {
  if (item.exact) {
    return pathname === item.href;
  }

  return (
    pathname === item.href ||
    pathname.startsWith(`${item.href}/`)
  );
}

function NavigationLink({
  item,
  pathname,
}: {
  item: NavigationItem;
  pathname: string;
}) {
  const active = isNavigationItemActive(pathname, item);

  return (
    <Link
      href={item.href}
      aria-current={active ? "page" : undefined}
      className={[
        "block rounded-2xl border px-5 py-4 transition",
        active
          ? "border-cyan-500/60 bg-cyan-500/10 text-white"
          : "border-transparent text-slate-300 hover:border-slate-700 hover:bg-slate-900 hover:text-white",
      ].join(" ")}
    >
      <span className="block font-semibold">
        {item.label}
      </span>

      <span
        className={[
          "mt-1 block text-sm",
          active ? "text-cyan-300" : "text-slate-500",
        ].join(" ")}
      >
        {item.description}
      </span>
    </Link>
  );
}

export default function DashboardSidebar({
  organizationName,
  userEmail,
  roleLabel,
  isOwner,
  permissionCodes,
}: DashboardSidebarProps) {
  const pathname = usePathname();

  const canAccess = (item: NavigationItem): boolean => {
    if (isOwner || !item.permission) {
      return true;
    }

    return permissionCodes.includes(item.permission);
  };

  const visibleNavigationItems =
    navigationItems.filter(canAccess);

  return (
    <>
      {/* Desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-72 flex-col border-r border-slate-800 bg-slate-900 lg:flex">
        <div className="border-b border-slate-800 px-6 py-7">
          <p className="text-sm font-bold uppercase tracking-[0.3em] text-cyan-400">
            SalesSetu
          </p>

          <h2 className="mt-3 text-2xl font-bold text-white">
            Enterprise Console
          </h2>
        </div>

        <div className="border-b border-slate-800 px-6 py-6">
          <p className="text-xs uppercase tracking-wider text-slate-500">
            Active workspace
          </p>

          <p className="mt-3 truncate text-lg font-semibold text-white">
            {organizationName}
          </p>

          <div className="mt-4 flex flex-wrap gap-2">
            <span className="rounded-full border border-cyan-500/50 bg-cyan-500/10 px-3 py-1 text-xs font-medium text-cyan-300">
              {roleLabel}
            </span>

            {isOwner ? (
              <span className="rounded-full border border-amber-500/50 bg-amber-500/10 px-3 py-1 text-xs font-medium text-amber-300">
                Owner
              </span>
            ) : null}
          </div>
        </div>

        <nav
          aria-label="Dashboard navigation"
          className="flex-1 space-y-2 overflow-y-auto px-4 py-5"
        >
          {visibleNavigationItems.map((item) => (
            <NavigationLink
              key={item.href}
              item={item}
              pathname={pathname}
            />
          ))}
        </nav>

        <div className="border-t border-slate-800 px-6 py-6">
          <p className="text-xs uppercase tracking-wider text-slate-500">
            Signed in as
          </p>

          <p className="mt-2 truncate text-sm font-medium text-slate-200">
            {userEmail}
          </p>
        </div>
      </aside>

      {/* Mobile navigation */}
      <section className="border-b border-slate-800 bg-slate-900 px-4 py-4 lg:hidden">
        <div>
          <p className="text-xs font-bold uppercase tracking-[0.25em] text-cyan-400">
            SalesSetu Enterprise
          </p>

          <p className="mt-1 truncate font-semibold text-white">
            {organizationName}
          </p>
        </div>

        <nav
          aria-label="Mobile dashboard navigation"
          className="mt-4 flex gap-2 overflow-x-auto pb-1"
        >
          {visibleNavigationItems.map((item) => {
            const active = isNavigationItemActive(
              pathname,
              item,
            );

            return (
              <Link
                key={item.href}
                href={item.href}
                aria-current={active ? "page" : undefined}
                className={[
                  "shrink-0 rounded-xl border px-4 py-2 text-sm font-medium transition",
                  active
                    ? "border-cyan-500 bg-cyan-500/10 text-cyan-300"
                    : "border-slate-700 text-slate-300 hover:border-slate-500",
                ].join(" ")}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>
      </section>
    </>
  );
}