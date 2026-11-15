import {
  notFound,
  redirect,
} from "next/navigation";

import DealDetailView from "@/components/dealos/DealDetailView";

import {
  getBookingPaymentSchedules,
} from "@/lib/bookings/payment-schedule-service";

import {
  getBookingPaymentReceiptSubmissions,
} from "@/lib/bookings/payment-receipt-approval-service";

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
      searchParams.bookingReservation,
    ) === "1"
  ) {
    return "Inventory reserved for this draft booking. No payment, customer, routing or notification was created.";
  }

  if (
    getSingleValue(
      searchParams.bookingReservationReleased,
    ) === "1"
  ) {
    return "Booking inventory reservation released successfully.";
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
      searchParams.bookingConfirmedAndWon,
    ) === "1"
  ) {
    return "Booking confirmed, payment/document reference recorded, unit booked and deal marked as won.";
  }

  if (
    getSingleValue(
      searchParams.paymentScheduleCreated,
    ) === "1"
  ) {
    return "Payment installment added successfully.";
  }

  if (
    getSingleValue(
      searchParams.scheduledPaymentRecorded,
    ) === "1"
  ) {
    return "Scheduled payment recorded successfully.";
  }

  if (getSingleValue(searchParams.receiptSubmitted) === "1") {
    return "Receipt submitted for owner approval. It has not changed the received total.";
  }

  if (getSingleValue(searchParams.receiptDecision) === "approved") {
    return "Receipt approved and recorded in the payment ledger.";
  }

  if (getSingleValue(searchParams.receiptDecision) === "rejected") {
    return "Receipt rejected. The payment ledger and totals remain unchanged.";
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
    paymentSchedulesResult,
    paymentReceiptSubmissions,
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

    getBookingPaymentSchedules(
      organizationId,
      dealResult.data.bookingId,
    ),

    getBookingPaymentReceiptSubmissions(
      organizationId,
      dealResult.data.bookingId,
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

  if (!paymentSchedulesResult.ok) {
    throw new Error(
      paymentSchedulesResult.message,
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
      paymentSchedules={
        paymentSchedulesResult.data
      }
      paymentReceiptSubmissions={
        paymentReceiptSubmissions
      }
      access={access}
      isOwner={Boolean(context.membership?.isOwner)}
      currentUserId={
  context.user.id
}
      successMessage={
        successMessage
      }
    />
  );
}
