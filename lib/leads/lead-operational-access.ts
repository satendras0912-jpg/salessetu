import "server-only";

import {
  hasAnyPermissionCode,
  hasPermissionCode,
} from "@/lib/auth/permission-utils";

import {
  LEAD_OPERATIONAL_PERMISSIONS,
} from "@/lib/leads/lead-operational-contract";

import type {
  BuildLeadOperationalAccessInput,
  LeadOperationalAccess,
  LeadOperationalDataAccess,
} from "@/types/lead-operational-access";

type BaseAccessInput = {
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

function hasAnyAccess(
  permissionCodes: readonly string[],
  isOwner: boolean,
  permissionCodesToCheck: readonly string[],
): boolean {
  return (
    isOwner ||
    hasAnyPermissionCode(
      permissionCodes,
      permissionCodesToCheck,
    )
  );
}

export function buildLeadOperationalDataAccess({
  permissionCodes,
  isOwner,
}: BaseAccessInput): LeadOperationalDataAccess {
  const canViewAssignments =
    hasAnyAccess(
      permissionCodes,
      isOwner,
      [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewAssignments,

        LEAD_OPERATIONAL_PERMISSIONS
          .viewAllAssignments,

        LEAD_OPERATIONAL_PERMISSIONS
          .manualAssign,

        LEAD_OPERATIONAL_PERMISSIONS
          .reassign,

        LEAD_OPERATIONAL_PERMISSIONS
          .unassign,

        LEAD_OPERATIONAL_PERMISSIONS
          .overrideAssignment,
      ],
    );

  const canViewFollowUps =
    hasAnyAccess(
      permissionCodes,
      isOwner,
      [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewFollowUps,

        LEAD_OPERATIONAL_PERMISSIONS
          .createFollowUp,

        LEAD_OPERATIONAL_PERMISSIONS
          .updateFollowUp,

        LEAD_OPERATIONAL_PERMISSIONS
          .assignFollowUp,

        LEAD_OPERATIONAL_PERMISSIONS
          .completeFollowUp,

        LEAD_OPERATIONAL_PERMISSIONS
          .deleteFollowUp,

        LEAD_OPERATIONAL_PERMISSIONS
          .manageFollowUpSla,
      ],
    );

  const canViewSiteVisits =
    hasAnyAccess(
      permissionCodes,
      isOwner,
      [
        LEAD_OPERATIONAL_PERMISSIONS
          .viewSiteVisits,

        LEAD_OPERATIONAL_PERMISSIONS
          .viewAllSiteVisits,

        LEAD_OPERATIONAL_PERMISSIONS
          .createSiteVisit,

        LEAD_OPERATIONAL_PERMISSIONS
          .updateSiteVisit,

        LEAD_OPERATIONAL_PERMISSIONS
          .assignSiteVisit,

        LEAD_OPERATIONAL_PERMISSIONS
          .checkInSiteVisit,

        LEAD_OPERATIONAL_PERMISSIONS
          .completeSiteVisit,

        LEAD_OPERATIONAL_PERMISSIONS
          .cancelSiteVisit,

        LEAD_OPERATIONAL_PERMISSIONS
          .deleteSiteVisit,
      ],
    );

  return {
    canViewAssignments,
    canViewFollowUps,
    canViewSiteVisits,
  };
}

export function buildLeadOperationalAccess({
  permissionCodes,
  isOwner,
  currentUserId,
  currentAssignment,
}: BuildLeadOperationalAccessInput): LeadOperationalAccess {
  const dataAccess =
    buildLeadOperationalDataAccess({
      permissionCodes,
      isOwner,
    });

  const canOverrideAssignment =
    hasAccess(
      permissionCodes,
      isOwner,
      LEAD_OPERATIONAL_PERMISSIONS
        .overrideAssignment,
    );

  const assignmentBelongsToCurrentUser =
    Boolean(currentUserId) &&
    currentAssignment?.assignedUserId ===
      currentUserId;

  const canActOnCurrentAssignment =
    Boolean(currentAssignment) &&
    (
      isOwner ||
      canOverrideAssignment ||
      assignmentBelongsToCurrentUser
    );

  const assignmentStatus =
    currentAssignment?.status ?? "";

  const canRespondToAssignment =
    canActOnCurrentAssignment &&
    assignmentStatus === "assigned";

  const canMarkAssignmentFirstResponse =
    canActOnCurrentAssignment &&
    ["accepted", "active"].includes(
      assignmentStatus,
    ) &&
    !currentAssignment?.firstResponseAt;

  const canCompleteAssignment =
    canActOnCurrentAssignment &&
    ["accepted", "active"].includes(
      assignmentStatus,
    );

  return {
    ...dataAccess,

    canTransitionLeadStatus:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .updateLeadStatus,
      ),

    canManualAssign:
      !currentAssignment &&
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .manualAssign,
      ),

    canReassign:
      Boolean(currentAssignment) &&
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .reassign,
      ),

    canUnassign:
      Boolean(currentAssignment) &&
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .unassign,
      ),

    canOverrideAssignment,

    canRespondToAssignment,

    canMarkAssignmentFirstResponse,

    canCompleteAssignment,

    canCreateFollowUp:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .createFollowUp,
      ),

    canUpdateFollowUp:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .updateFollowUp,
      ),

    canAssignFollowUp:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .assignFollowUp,
      ),

    canCompleteFollowUp:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .completeFollowUp,
      ),

    canDeleteFollowUp:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .deleteFollowUp,
      ),

    canManageFollowUpSla:
      hasAccess(
    permissionCodes,
    isOwner,
    LEAD_OPERATIONAL_PERMISSIONS
      .manageFollowUpSla,
      ),

    canCreateSiteVisit:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .createSiteVisit,
      ),

    canUpdateSiteVisit:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .updateSiteVisit,
      ),

    canAssignSiteVisit:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .assignSiteVisit,
      ),

    canCheckInSiteVisit:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .checkInSiteVisit,
      ),

    canCompleteSiteVisit:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .completeSiteVisit,
      ),

    canCancelSiteVisit:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .cancelSiteVisit,
      ),

    canDeleteSiteVisit:
      hasAccess(
        permissionCodes,
        isOwner,
        LEAD_OPERATIONAL_PERMISSIONS
          .deleteSiteVisit,
      ),
  };
}