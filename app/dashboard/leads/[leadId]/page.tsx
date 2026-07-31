import {
  notFound,
  redirect,
} from "next/navigation";

import LeadDetailView from "@/components/leads/LeadDetailView";

import {
  requirePermissionAccess,
} from "@/lib/auth/access-control";

import {
  LEAD_FORM_PERMISSIONS,
} from "@/lib/leads/lead-form-contract";

import {
  getLeadDetail,
} from "@/lib/leads/lead-detail-service";

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

  /*
   * Multiple property aliases intentionally दिए गए हैं।
   * इससे existing service और component दोनों access
   * object को safely consume कर सकते हैं।
   */
  return {
    canViewActivities,
    canViewStatusHistory,
    canViewFollowUps,
    canViewSiteVisits,

    viewActivities: canViewActivities,
    viewStatusHistory: canViewStatusHistory,
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
    getSingleValue(searchParams.created) === "1";

  const wasUpdated =
    getSingleValue(searchParams.updated) === "1";

  if (wasCreated) {
    return "Lead created successfully.";
  }

  if (wasUpdated) {
    return "Lead updated successfully.";
  }

  return null;
}

export default async function LeadDetailPage({
  params,
  searchParams,
}: LeadDetailPageProps) {
  const { leadId } = await params;

  const cleanLeadId = leadId.trim();

  if (!cleanLeadId) {
    notFound();
  }

  const { context, permissions } =
    await requirePermissionAccess({
      allOf: [LEAD_FORM_PERMISSIONS.view],

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

  const access = buildLeadDetailAccess(
    permissionCodes,
    isOwner,
  );

  /*
   * Existing service दो या तीन arguments ले सकती है।
   * तीसरा access argument JavaScript में optional-safe है।
   */
  const loadLeadDetail =
    getLeadDetail as unknown as (
      organizationId: string,
      leadId: string,
      access: LeadDetailAccess,
    ) => Promise<LeadDetailRecord | null>;

  const lead = await loadLeadDetail(
    organizationId,
    cleanLeadId,
    access,
  );

  if (!lead) {
    notFound();
  }

  const resolvedSearchParams =
    await searchParams;

  const successMessage =
    getSuccessMessage(resolvedSearchParams);

  return (
    <LeadDetailView
      lead={lead}
      access={access}
      canEditLead={canEditLead}
      successMessage={successMessage}
    />
  );
}