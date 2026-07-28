export type PermissionGrantSource = "owner" | "role";

export type PermissionGrant = {
  id: string;
  code: string;
  module: string;
  action: string;
  description: string | null;
  grantedVia: PermissionGrantSource;
  roleCode: string | null;
};

export type PermissionContext = {
  organizationId: string;
  isOwner: boolean;
  codes: readonly string[];
  grants: readonly PermissionGrant[];
};