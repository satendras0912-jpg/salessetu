import {
  notFound,
  redirect,
} from "next/navigation";

import DealDetailView from "@/components/dealos/DealDetailView";

import {
  requirePermissionAccess,
} from "@/lib/auth/access-control";

import {
  buildDealOSDataAccess,
} from "@/lib/dealos/deal-access";

import {
  DEALOS_PERMISSIONS,
} from "@/lib/dealos/deal-contract";

import {
  getDealAssigneeOptions,
  getDealById,
  getDealCommercialApprovals,
  getDealOffers,
  getDealStatusHistory,
  normalizeDealRequiredUuid,
} from "@/lib/dealos/deal-service";

export const dynamic = "force-dynamic";

type RawSearchParams = Record<
  string,
  string | string[] | undefined
>;

type DealDetailPageProps = {
  params: Promise<{
    dealId: string;
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

function getSuccessMessage(
  searchParams: RawSearchParams,
): string | null {
  if (
    getSingleValue(
      searchParams.dealCreated,
    ) === "1"
  ) {
    return "Deal created successfully.";
  }

  if (
    getSingleValue(
      searchParams.dealUpdated,
    ) === "1"
  ) {
    return "Deal updated successfully.";
  }

  if (
    getSingleValue(
      searchParams.dealStatusUpdated,
    ) === "1"
  ) {
    return "Deal status updated successfully.";
  }

  if (
    getSingleValue(
      searchParams.dealLost,
    ) === "1"
  ) {
    return "Deal marked as lost.";
  }

  if (
    getSingleValue(
      searchParams.dealOnHold,
    ) === "1"
  ) {
    return "Deal placed on hold.";
  }

  if (
    getSingleValue(
      searchParams.dealCancelled,
    ) === "1"
  ) {
    return "Deal cancelled successfully.";
  }

  if (
    getSingleValue(
      searchParams.bookingLinked,
    ) === "1"
  ) {
    return "Booking linked successfully.";
  }

  if (
    getSingleValue(
      searchParams.dealWon,
    ) === "1"
  ) {
    return "Deal marked as won.";
  }

  if (
    getSingleValue(
      searchParams.offerCreated,
    ) === "1"
  ) {
    return "Deal offer created successfully.";
  }

  if (
    getSingleValue(
      searchParams.offerUpdated,
    ) === "1"
  ) {
    return "Deal offer updated successfully.";
  }

  if (
    getSingleValue(
      searchParams.commercialApprovalRequested,
    ) === "1"
  ) {
    return "Commercial approval requested successfully.";
  }

  if (
    getSingleValue(
      searchParams.commercialApprovalDecided,
    ) === "1"
  ) {
    return "Commercial approval decision recorded.";
  }

  if (
    getSingleValue(
      searchParams.commercialApprovalCancelled,
    ) === "1"
  ) {
    return "Commercial approval request cancelled.";
  }

  return null;
}

export default async function DealDetailPage({
  params,
  searchParams,
}: DealDetailPageProps) {
  const {
    dealId,
  } = await params;

  const cleanDealId =
    normalizeDealRequiredUuid(
      dealId,
    );

  if (!cleanDealId) {
    notFound();
  }

  const {
    context,
    permissions,
  } =
    await requirePermissionAccess({
      allOf: [
        DEALOS_PERMISSIONS.viewDeals,
      ],

      loginRedirectTo:
        `/login?next=/dashboard/deals/${cleanDealId}`,

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

  const access =
    buildDealOSDataAccess({
      permissionCodes:
        permissions.codes ?? [],

      isOwner:
        Boolean(
          context.membership?.isOwner,
        ),
    });

  const dealResult =
    await getDealById(
      organizationId,
      cleanDealId,
    );

  if (
    !dealResult.ok
  ) {
    if (
      dealResult.code ===
      "not_found"
    ) {
      notFound();
    }

    throw new Error(
      dealResult.message,
    );
  }

  const assigneeOptionsResult =
  access.canAssignDeal
    ? await getDealAssigneeOptions(
        organizationId,
      )
    : {
        ok: true as const,
        data: [],
      };

      if (!assigneeOptionsResult.ok) {
  throw new Error(
    assigneeOptionsResult.message,
  );
}

  const [
    offersResult,
    approvalsResult,
    statusHistoryResult,
  ] = await Promise.all([
    getDealOffers(
      organizationId,
      cleanDealId,
    ),

    getDealCommercialApprovals(
      organizationId,
      cleanDealId,
    ),

    getDealStatusHistory(
      organizationId,
      cleanDealId,
    ),
  ]);

  if (!offersResult.ok) {
    throw new Error(
      offersResult.message,
    );
  }

  if (!approvalsResult.ok) {
    throw new Error(
      approvalsResult.message,
    );
  }

  if (!statusHistoryResult.ok) {
    throw new Error(
      statusHistoryResult.message,
    );
  }

  const resolvedSearchParams =
    await searchParams;

  const successMessage =
    getSuccessMessage(
      resolvedSearchParams,
    );

  return (
    <DealDetailView
      deal={
        dealResult.data
      }
      assigneeOptions={
  assigneeOptionsResult.data
}
      offers={
        offersResult.data
      }
      approvals={
        approvalsResult.data
      }
      statusHistory={
        statusHistoryResult.data
      }
      access={access}
      currentUserId={
  context.user.id
}
      successMessage={
        successMessage
      }
    />
  );
}