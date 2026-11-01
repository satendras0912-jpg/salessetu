import type { ReactNode } from "react";

import DashboardShell from "@/components/dashboard/DashboardShell";
import type { DashboardNotification } from "@/components/dashboard/NotificationInbox";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";

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

  let notifications: DashboardNotification[] = [];

  if (context.organization?.id) {
    const supabase = await createClient();

    const { data, error } = await supabase
      .from("notification_inbox")
      .select(
        "id, title, body, deep_link, severity, status, created_at",
      )
      .eq("organization_id", context.organization.id)
      .eq("user_id", context.user.id)
      .in("status", ["unread", "read"])
      .order("created_at", { ascending: false })
      .limit(8);

    if (!error) {
      notifications = (data ?? []).map((item) => ({
        id: item.id,
        title: item.title,
        body: item.body,
        deepLink: item.deep_link,
        severity: item.severity as DashboardNotification["severity"],
        status: item.status as DashboardNotification["status"],
        createdAt: item.created_at,
      }));
    }
  }

  return (
    <DashboardShell
      organizationName={organizationName}
      organizationStatus={organizationStatus}
      userEmail={userEmail}
      roleLabel={primaryRole}
      isOwner={Boolean(context.membership?.isOwner)}
      permissionCodes={permissions.codes}
      organizationId={context.organization?.id ?? null}
      availableOrganizations={context.availableOrganizations}
      notifications={notifications}
    >
      {children}
    </DashboardShell>
  );
}
