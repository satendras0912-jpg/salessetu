import { cache } from "react";

import { getCurrentUserContext } from "@/lib/auth/current-context";
import { createClient } from "@/lib/supabase/server";
import type {
  PermissionContext,
  PermissionGrant,
  PermissionGrantSource,
} from "@/types/permissions";

/**
 * PostgreSQL RPC से मिलने वाली raw row.
 *
 * SQL function:
 * public.get_my_organization_permissions(uuid)
 */
type PermissionRpcRow = {
  permission_id: string;
  permission_code: string;
  permission_module: string;
  permission_action: string;
  permission_description: string | null;
  granted_via: string;
  role_code: string | null;
};

/**
 * Permission codes हमेशा normalized form में compare होंगे.
 *
 * Example:
 * " Dashboard.View " → "dashboard.view"
 */
function normalizePermissionCode(
  permissionCode: string | null | undefined,
): string {
  return permissionCode?.trim().toLowerCase() ?? "";
}

/**
 * Database value को strict application type में convert करता है.
 */
function normalizeGrantSource(
  grantSource: string | null | undefined,
): PermissionGrantSource {
  return grantSource?.trim().toLowerCase() === "owner"
    ? "owner"
    : "role";
}

/**
 * Current authenticated user के लिए effective organization
 * permissions database से load करता है.
 */
async function loadCurrentPermissionContext(): Promise<PermissionContext | null> {
  const userContext = await getCurrentUserContext();

  if (!userContext) {
    return null;
  }

  const organizationId = userContext.organization?.id;
  const membership = userContext.membership;

  if (!organizationId || !membership) {
    return null;
  }

  const supabase = await createClient();

  const { data, error } = await supabase.rpc(
    "get_my_organization_permissions",
    {
      p_organization_id: organizationId,
    },
  );

  if (error) {
    throw new Error(
      [
        "Unable to load organization permissions.",
        `Organization: ${organizationId}`,
        `Database message: ${error.message}`,
      ].join(" "),
    );
  }

  const rows = (data ?? []) as PermissionRpcRow[];

  const grants: PermissionGrant[] = rows
    .map((row) => {
      const code = normalizePermissionCode(
        row.permission_code,
      );

      return {
        id: row.permission_id,
        code,
        module: row.permission_module,
        action: row.permission_action,
        description: row.permission_description,
        grantedVia: normalizeGrantSource(
          row.granted_via,
        ),
        roleCode: row.role_code,
      };
    })
    .filter((grant) => Boolean(grant.code));

  /**
   * एक permission owner और role दोनों के माध्यम से मिल सकती है.
   * इसलिए effective codes को deduplicate किया जाता है.
   */
  const codes = Array.from(
    new Set(grants.map((grant) => grant.code)),
  ).sort();

  return {
    organizationId,
    isOwner: Boolean(membership.isOwner),
    codes,
    grants,
  };
}

/**
 * एक ही Server Component render cycle में permission RPC को
 * बार-बार execute होने से रोकता है.
 */
export const getCurrentPermissionContext = cache(
  loadCurrentPermissionContext,
);

/**
 * Single permission check.
 */
export function hasPermission(
  permissionContext: PermissionContext,
  permissionCode: string,
): boolean {
  const normalizedRequiredCode =
    normalizePermissionCode(permissionCode);

  if (!normalizedRequiredCode) {
    return false;
  }

  return permissionContext.codes.some(
    (grantedCode) =>
      normalizePermissionCode(grantedCode) ===
      normalizedRequiredCode,
  );
}

/**
 * User के पास दी गई सभी permissions होनी चाहिए.
 *
 * Empty array को valid माना जाता है.
 */
export function hasAllPermissions(
  permissionContext: PermissionContext,
  permissionCodes: readonly string[],
): boolean {
  return permissionCodes.every((permissionCode) =>
    hasPermission(
      permissionContext,
      permissionCode,
    ),
  );
}

/**
 * User के पास दी गई permissions में से कम-से-कम एक होनी चाहिए.
 *
 * Empty array को false माना जाता है.
 */
export function hasAnyPermission(
  permissionContext: PermissionContext,
  permissionCodes: readonly string[],
): boolean {
  if (permissionCodes.length === 0) {
    return false;
  }

  return permissionCodes.some((permissionCode) =>
    hasPermission(
      permissionContext,
      permissionCode,
    ),
  );
}