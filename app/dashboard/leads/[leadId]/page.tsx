import { notFound, redirect } from "next/navigation";

import LeadDetailView from "@/components/leads/LeadDetailView";
import { requirePermissionAccess } from "@/lib/auth/access-control";
import { getLeadDetail } from "@/lib/leads/lead-detail-service";
import type { LeadDetailAccess } from "@/types/lead-detail";

export const dynamic = "force-dynamic";

type LeadDetailPageProps = {
  params: Promise<{
    leadId: string;
  }>;
};

function hasPermission(
  permissionCodes: readonly string[],
  permissionCode: string,
): boolean {
  const requiredPermission =
    permissionCode.trim().toLowerCase();

  return permissionCodes.some(
    (grantedPermission) =>
      grantedPermission.trim().toLowerCase() ===
      requiredPermission,
  );
}

export default async function LeadDetailPage({
  params,
}: LeadDetailPageProps) {
  const { leadId } = await params;

  const { context, permissions } =
    await requirePermissionAccess({
      allOf: ["leads.view"],
      loginRedirectTo:
        "/login?next=/dashboard/leads",
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

  const access: LeadDetailAccess = {
    canViewValidation: hasPermission(
      permissions.codes,
      "lead_validation.view",
    ),

    canViewAssignment: hasPermission(
      permissions.codes,
      "assignment.view",
    ),

    canViewFollowUps: hasPermission(
      permissions.codes,
      "followups.view",
    ),

    canViewSiteVisits: hasPermission(
      permissions.codes,
      "site_visits.view",
    ),

    canViewAiCalls: hasPermission(
      permissions.codes,
      "ai_calling.view",
    ),
  };

  const lead = await getLeadDetail(
    organizationId,
    leadId,
    access,
  );

  if (!lead) {
    notFound();
  }

  return (
    <LeadDetailView
      lead={lead}
      access={access}
    />
  );
}