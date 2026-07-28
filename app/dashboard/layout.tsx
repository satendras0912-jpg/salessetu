import type { ReactNode } from "react";

import DashboardShell from "@/components/dashboard/DashboardShell";
import { requirePermissionAccess } from "@/lib/auth/access-control";

type DashboardLayoutProps = {
  children: ReactNode;
};

export default async function DashboardLayout({
  children,
}: DashboardLayoutProps) {
  const { context, permissions } =
    await requirePermissionAccess({
      allOf: ["dashboard.view"],
      loginRedirectTo: "/login?next=/dashboard",
      unauthorizedRedirectTo: "/unauthorized",
    });

  const organizationName =
    context.organization?.name ?? "SalesSetu Workspace";

  const organizationStatus =
    context.organization?.status ?? "unknown";

  const userEmail =
    context.user.email ?? "Email unavailable";

  const primaryRole =
    context.roles[0]?.name ??
    (context.membership?.isOwner
      ? "Workspace Owner"
      : "Organization Member");

  return (
    <DashboardShell
      organizationName={organizationName}
      organizationStatus={organizationStatus}
      userEmail={userEmail}
      roleLabel={primaryRole}
      isOwner={Boolean(context.membership?.isOwner)}
      permissionCodes={permissions.codes}
    >
      {children}
    </DashboardShell>
  );
}