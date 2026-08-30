export function hasPermissionCode(
  permissionCodes: readonly string[],
  requiredPermission: string,
): boolean {
  const normalizedRequiredPermission =
    requiredPermission
      .trim()
      .toLowerCase();

  return permissionCodes.some(
    (permissionCode) =>
      permissionCode
        .trim()
        .toLowerCase() ===
      normalizedRequiredPermission,
  );
}

export function hasAnyPermissionCode(
  permissionCodes: readonly string[],
  requiredPermissions: readonly string[],
): boolean {
  return requiredPermissions.some(
    (requiredPermission) =>
      hasPermissionCode(
        permissionCodes,
        requiredPermission,
      ),
  );
}
