import "server-only";

import {
  hasPermissionCode,
} from "@/lib/auth/permission-utils";

import {
  DEALOS_PERMISSIONS,
} from "@/lib/dealos/deal-contract";

import {
  getCurrentPermissionContext,
} from "@/lib/auth/permissions";

import type {
  DealOSDataAccess,
} from "@/types/dealos";

type DealOSAccessInput = {
  permissionCodes: readonly string[];
  isOwner: boolean;
};

function hasAccess(
  permissionCodes: readonly string[],
  isOwner: boolean,
  permissionCode: string,
): boolean {
  return (
    isOwner ||
    hasPermissionCode(
      permissionCodes,
      permissionCode,
    )
  );
}

export function buildDealOSDataAccess({
  permissionCodes,
  isOwner,
}: DealOSAccessInput): DealOSDataAccess {
  return {
    canViewDeals:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.viewDeals,
      ),

    canViewAllDeals:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.viewAllDeals,
      ),

    canCreateDeal:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.createDeal,
      ),

    canUpdateDeal:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.updateDeal,
      ),

    canAssignDeal:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.assignDeal,
      ),

    canManageOffers:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.manageOffers,
      ),

    canApproveCommercials:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.approveCommercials,
      ),

    canMarkWon:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.markWon,
      ),

    canMarkLost:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.markLost,
      ),

    canHandoffBooking:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.handoffBooking,
      ),

    canDeleteDeal:
      hasAccess(
        permissionCodes,
        isOwner,
        DEALOS_PERMISSIONS.deleteDeal,
      ),
  };
}

export async function getCurrentDealOSAccessContext(): Promise<{
  organizationId: string;
  access: DealOSDataAccess;
} | null> {
  const permissionContext =
    await getCurrentPermissionContext();

  if (!permissionContext) {
    return null;
  }

  return {
    organizationId:
      permissionContext.organizationId,

    access:
      buildDealOSDataAccess({
        permissionCodes:
          permissionContext.codes,

        isOwner:
          permissionContext.isOwner,
      }),
  };
}