import type { ReactNode } from "react";

import DashboardSidebar from "@/components/dashboard/DashboardSidebar";
import LogoutButton from "@/components/dashboard/LogoutButton";

type DashboardShellProps = {
  children: ReactNode;
  organizationName: string;
  organizationStatus: string;
  userEmail: string;
  roleLabel: string;
  isOwner: boolean;
  permissionCodes: readonly string[];
};

export default function DashboardShell({
  children,
  organizationName,
  organizationStatus,
  userEmail,
  roleLabel,
  isOwner,
  permissionCodes,
}: DashboardShellProps) {
  return (
    <div className="min-h-screen bg-slate-950 text-white">
      <DashboardSidebar
        organizationName={organizationName}
        userEmail={userEmail}
        roleLabel={roleLabel}
        isOwner={isOwner}
        permissionCodes={permissionCodes}
      />

      <div className="lg:pl-72">
        <header className="border-b border-slate-800 bg-slate-950/95 px-6 py-4 backdrop-blur lg:sticky lg:top-0 lg:z-20">
          <div className="mx-auto flex max-w-7xl items-center justify-between gap-6">
            <div className="min-w-0">
              <p className="truncate text-sm font-semibold text-slate-100">
                {organizationName}
              </p>

              <div className="mt-1 flex items-center gap-2 text-xs text-slate-500">
                <span
                  aria-hidden="true"
                  className="h-2 w-2 rounded-full bg-emerald-400"
                />

                <span className="capitalize">
                  {organizationStatus}
                </span>

                <span aria-hidden="true">•</span>

                <span className="truncate">
                  {userEmail}
                </span>
              </div>
            </div>

            <LogoutButton />
          </div>
        </header>

        <main className="px-4 py-7 sm:px-6 sm:py-8">
          <div className="mx-auto max-w-7xl">
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}