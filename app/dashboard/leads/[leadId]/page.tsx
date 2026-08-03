import {
  notFound,
  redirect,
} from "next/navigation";

import LeadDetailView from "@/components/leads/LeadDetailView";
import LeadOperationalOverview from "@/components/leads/LeadOperationalOverview";

import {
  requirePermissionAccess,
} from "@/lib/auth/access-control";

import {
  LEAD_FORM_PERMISSIONS,
} from "@/lib/leads/lead-form-contract";

import {
  buildLeadOperationalAccess,
  buildLeadOperationalDataAccess,
} from "@/lib/leads/lead-operational-access";

import {
  getLeadDetail,
} from "@/lib/leads/lead-detail-service";

import {
  getLeadOperationalContext,
} from "@/lib/leads/lead-operational-context-service";

import {
  createClient,
} from "@/lib/supabase/server";

import type {
  LeadDetailAccess,
  LeadDetailRecord,
} from "@/types/lead-detail";

export const dynamic = "force-dynamic";

type RawSearchParams = Record<
  string,
  string | string[] | undefined
>;

type LeadDetailPageProps = {
  params: Promise<{
    leadId: string;
  }>;

  searchParams: Promise<RawSearchParams>;
};

function getSingleValue(
  value: string | string[] | undefined,
): string {
  if (Array.isArray(value)) {
    return value[0] ?? "";
  }

  return value ?? "";
}

function hasPermission(
  permissionCodes: readonly string[],
  requiredPermission: string,
): boolean {
  const normalizedRequiredPermission =
    requiredPermission.trim().toLowerCase();

  return permissionCodes.some(
    (permissionCode) =>
      permissionCode.trim().toLowerCase() ===
      normalizedRequiredPermission,
  );
}

function hasAnyPermission(
  permissionCodes: readonly string[],
  requiredPermissions: readonly string[],
): boolean {
  return requiredPermissions.some(
    (requiredPermission) =>
      hasPermission(
        permissionCodes,
        requiredPermission,
      ),
  );
}

function buildLeadDetailAccess(
  permissionCodes: readonly string[],
  isOwner: boolean,
): LeadDetailAccess {
  const canViewActivities =
    isOwner ||
    hasAnyPermission(permissionCodes, [
      "lead_activities.view",
      "leads.activities.view",
      "activities.view",
    ]);

  const canViewStatusHistory =
    isOwner ||
    hasAnyPermission(permissionCodes, [
      "lead_status_history.view",
      "leads.status_history.view",
      "leads.view_history",
    ]);

  const canViewFollowUps =
    isOwner ||
    hasAnyPermission(permissionCodes, [
      "followups.view",
      "lead_followups.view",
      "leads.followups.view",
    ]);

  const canViewSiteVisits =
    isOwner ||
    hasAnyPermission(permissionCodes, [
      "site_visits.view",
      "leads.site_visits.view",
    ]);

  return {
    canViewActivities,
    canViewStatusHistory,
    canViewFollowUps,
    canViewSiteVisits,

    viewActivities: canViewActivities,
    viewStatusHistory:
      canViewStatusHistory,
    viewFollowUps: canViewFollowUps,
    viewSiteVisits: canViewSiteVisits,

    activities: canViewActivities,
    statusHistory: canViewStatusHistory,
    followUps: canViewFollowUps,
    siteVisits: canViewSiteVisits,
  } as unknown as LeadDetailAccess;
}

function getSuccessMessage(
  searchParams: RawSearchParams,
): string | null {
  const wasCreated =
    getSingleValue(
      searchParams.created,
    ) === "1";

  const wasUpdated =
    getSingleValue(
      searchParams.updated,
    ) === "1";

  const statusWasUpdated =
    getSingleValue(
      searchParams.statusUpdated,
    ) === "1";

  const assignmentWasUpdated =
    getSingleValue(
      searchParams.assignmentUpdated,
    ) === "1";

  const assignmentWasRemoved =
    getSingleValue(
      searchParams.assignmentRemoved,
    ) === "1";

  if (wasCreated) {
    return "Lead created successfully.";
  }

  if (wasUpdated) {
    return "Lead updated successfully.";
  }

  if (statusWasUpdated) {
    return "Lead status updated successfully.";
  }

  if (assignmentWasUpdated) {
    return "Lead assigned successfully.";
  }

  if (assignmentWasRemoved) {
    return "Lead assignment removed successfully.";
  }

  return null;
}

function readMemberEmail(
  member: unknown,
): string | null {
  if (
    typeof member !== "object" ||
    member === null ||
    Array.isArray(member)
  ) {
    return null;
  }

  const email = (
    member as Record<string, unknown>
  ).email;

  if (typeof email !== "string") {
    return null;
  }

  const normalizedEmail = email.trim();

  return normalizedEmail || null;
}

export default async function LeadDetailPage({
  params,
  searchParams,
}: LeadDetailPageProps) {
  const { leadId } = await params;

  const cleanLeadId =
    leadId.trim();

  if (!cleanLeadId) {
    notFound();
  }

  const { context, permissions } =
    await requirePermissionAccess({
      allOf: [
        LEAD_FORM_PERMISSIONS.view,
      ],

      loginRedirectTo:
        `/login?next=/dashboard/leads/${cleanLeadId}`,

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id;

  if (!organizationId) {
    redirect(
      "/auth-error?reason=organization_context_missing",
    );
  }

  const permissionCodes =
    permissions.codes ?? [];

  const isOwner = Boolean(
    context.membership?.isOwner,
  );

  const canEditLead =
    isOwner ||
    hasPermission(
      permissionCodes,
      LEAD_FORM_PERMISSIONS.update,
    );

  const detailAccess =
    buildLeadDetailAccess(
      permissionCodes,
      isOwner,
    );

  const operationalDataAccess =
    buildLeadOperationalDataAccess({
      permissionCodes,
      isOwner,
    });

  const supabase =
    await createClient();

  const {
    data: authData,
    error: authError,
  } = await supabase.auth.getUser();

  if (
    authError ||
    !authData.user
  ) {
    redirect(
      `/login?next=/dashboard/leads/${cleanLeadId}`,
    );
  }

  const loadLeadDetail =
    getLeadDetail as unknown as (
      organizationId: string,
      leadId: string,
      access: LeadDetailAccess,
    ) => Promise<LeadDetailRecord | null>;

  const [
    lead,
    operationalContext,
  ] = await Promise.all([
    loadLeadDetail(
      organizationId,
      cleanLeadId,
      detailAccess,
    ),

    getLeadOperationalContext(
      organizationId,
      cleanLeadId,
      operationalDataAccess,
    ),
  ]);

  if (
    !lead ||
    !operationalContext
  ) {
    notFound();
  }

  const operationalAccess =
    buildLeadOperationalAccess({
      permissionCodes,
      isOwner,

      currentUserId:
        authData.user.id,

      currentAssignment:
        operationalContext.currentAssignment,
    });

  const activeAssignment =
    operationalContext.currentAssignment;

  const activeAssignmentMember =
    activeAssignment
      ? operationalContext.members.find(
          (member) =>
            member.userId ===
            activeAssignment.assignedUserId,
        ) ?? null
      : null;

  const activeAssignmentAgent =
    activeAssignment
      ? operationalContext.agents.find(
          (agent) =>
            agent.profileId ===
            activeAssignment.agentProfileId,
        ) ?? null
      : null;

  const activeAssignmentTeam =
    activeAssignment?.teamId
      ? operationalContext.teams.find(
          (team) =>
            team.id ===
            activeAssignment.teamId,
        ) ?? null
      : null;

    const assignmentEmail =
    readMemberEmail(
      activeAssignmentMember,
    );

  const activeAssignmentEmail =
    assignmentEmail ??
    (
      activeAssignment?.assignedUserId ===
      authData.user.id
        ? authData.user.email ?? null
        : null
    );

  const leadDetailAssignment =
    activeAssignment
      ? {
          assignedToName:
            activeAssignmentMember
              ?.displayName ??
            activeAssignmentAgent
              ?.displayName ??
            activeAssignment
              .assignedUserId,

          assignedToEmail:
            activeAssignmentEmail,

          agentEmail:
            activeAssignmentEmail,

          teamName:
            activeAssignmentTeam?.name ??
            null,

          teamCode:
            activeAssignmentTeam?.code ??
            null,

          status:
            activeAssignment.status,

          assignmentStatus:
            activeAssignment.status,

          assignedAt:
            activeAssignment.assignedAt,
        }
      : null;

  const resolvedSearchParams =
    await searchParams;

  const successMessage =
    getSuccessMessage(
      resolvedSearchParams,
    );

  return (
    <div className="space-y-8">
      <LeadDetailView
        lead={lead}
        access={detailAccess}
        canEditLead={canEditLead}
        successMessage={successMessage}
        currentAssignment={
          leadDetailAssignment
        }
      />

      <LeadOperationalOverview
        context={operationalContext}
        access={operationalAccess}
      />
    </div>
  );
}