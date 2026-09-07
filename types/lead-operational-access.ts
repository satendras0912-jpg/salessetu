import type {
  LeadAssignmentSummary,
} from "@/types/lead-operational-controls";

export type LeadOperationalDataAccess = {
  canViewAssignments: boolean;
  canViewFollowUps: boolean;
  canViewSiteVisits: boolean;
};

export type LeadOperationalAccess =
  LeadOperationalDataAccess & {
    canTransitionLeadStatus: boolean;

    canManualAssign: boolean;
    canReassign: boolean;
    canUnassign: boolean;
    canOverrideAssignment: boolean;

    canRespondToAssignment: boolean;
    canMarkAssignmentFirstResponse: boolean;
    canCompleteAssignment: boolean;

    canCreateFollowUp: boolean;
    canUpdateFollowUp: boolean;
    canAssignFollowUp: boolean;
    canCompleteFollowUp: boolean;
    canDeleteFollowUp: boolean;
    canManageFollowUpSla: boolean;

    canCreateSiteVisit: boolean;
    canUpdateSiteVisit: boolean;
    canAssignSiteVisit: boolean;
    canCheckInSiteVisit: boolean;
    canCompleteSiteVisit: boolean;
    canCancelSiteVisit: boolean;
    canDeleteSiteVisit: boolean;
  };

export type BuildLeadOperationalAccessInput = {
  permissionCodes: readonly string[];
  isOwner: boolean;

  currentUserId: string | null;

  currentAssignment:
    | LeadAssignmentSummary
    | null;
};