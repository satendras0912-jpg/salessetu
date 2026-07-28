import { redirect } from "next/navigation";

import { getCurrentUserContext } from "@/lib/auth/current-context";
import {
  getCurrentPermissionContext,
  hasAllPermissions,
  hasAnyPermission,
} from "@/lib/auth/permissions";
import type { PermissionContext } from "@/types/permissions";

type CurrentUserContext = NonNullable<
  Awaited<ReturnType<typeof getCurrentUserContext>>
>;

function normalizeCode(value: unknown): string {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().toLowerCase();
}

function organizationIsActive(
  context: CurrentUserContext,
): boolean {
  return normalizeCode(context.organization?.status) === "active";
}

function membershipIsActive(
  context: CurrentUserContext,
): boolean {
  return (
    normalizeCode(
      context.membership?.membershipStatus,
    ) === "active"
  );
}

function userIsPlatformAdmin(
  context: CurrentUserContext,
): boolean {
  return context.roles.some(
    (role) =>
      normalizeCode(role.code) === "platform_admin",
  );
}

/**
 * Legacy dashboard guard.
 *
 * इसे अभी रखा जा रहा है ताकि जिन routes में
 * requireDashboardAccess() पहले से इस्तेमाल हो रहा है,
 * वे break न हों।
 */
export async function requireDashboardAccess(): Promise<CurrentUserContext> {
  const context = await getCurrentUserContext();

  if (!context) {
    redirect("/login?next=/dashboard");
  }

  const organization = context.organization;
  const membership = context.membership;

  if (
    !organization ||
    !membership ||
    !organizationIsActive(context) ||
    !membershipIsActive(context)
  ) {
    redirect("/unauthorized");
  }

  const isOwner = Boolean(membership.isOwner);
  const isPlatformAdmin = userIsPlatformAdmin(context);

  if (!isOwner && !isPlatformAdmin) {
    redirect("/unauthorized");
  }

  return context;
}

export type PermissionAccessOptions = {
  /**
   * User के पास ये सभी permission codes होने चाहिए।
   *
   * Example:
   * allOf: ["dashboard.view", "leads.read"]
   */
  allOf?: readonly string[];

  /**
   * User के पास इनमें से कम-से-कम एक permission होनी चाहिए।
   *
   * Example:
   * anyOf: ["leads.assign", "leads.manage"]
   */
  anyOf?: readonly string[];

  /**
   * Authenticated session न मिलने पर destination।
   */
  loginRedirectTo?: string;

  /**
   * Active membership या required permission न मिलने पर destination।
   */
  unauthorizedRedirectTo?: string;
};

export type AuthorizedPermissionAccess = {
  context: CurrentUserContext;
  permissions: PermissionContext;
};

/**
 * Current user, active organization membership और
 * database-backed permissions verify करता है।
 */
export async function requirePermissionAccess(
  options: PermissionAccessOptions = {},
): Promise<AuthorizedPermissionAccess> {
  const {
    allOf = [],
    anyOf = [],
    loginRedirectTo = "/login?next=/dashboard",
    unauthorizedRedirectTo = "/unauthorized",
  } = options;

  const context = await getCurrentUserContext();

  if (!context) {
    redirect(loginRedirectTo);
  }

  const organization = context.organization;
  const membership = context.membership;

  if (
    !organization ||
    !membership ||
    !organizationIsActive(context) ||
    !membershipIsActive(context)
  ) {
    redirect(unauthorizedRedirectTo);
  }

  const permissions =
    await getCurrentPermissionContext();

  /*
   * Permission context उसी active organization का होना चाहिए
   * जो current user context में resolve हुई है।
   */
  if (
    !permissions ||
    permissions.organizationId !== organization.id
  ) {
    redirect(unauthorizedRedirectTo);
  }

  const allPermissionsAllowed =
    allOf.length === 0 ||
    hasAllPermissions(permissions, allOf);

  const anyPermissionAllowed =
    anyOf.length === 0 ||
    hasAnyPermission(permissions, anyOf);

  if (
    !allPermissionsAllowed ||
    !anyPermissionAllowed
  ) {
    redirect(unauthorizedRedirectTo);
  }

  return {
    context,
    permissions,
  };
}

/**
 * Single permission route guard.
 *
 * Example:
 * const { context } =
 *   await requirePermission("dashboard.view");
 */
export async function requirePermission(
  permissionCode: string,
): Promise<AuthorizedPermissionAccess> {
  return requirePermissionAccess({
    allOf: [permissionCode],
  });
}