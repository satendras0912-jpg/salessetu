// ============================================================
// SalesSetu DealOS
// Shared application-layer contracts
// ============================================================

export const DEAL_STATUSES = [
  "draft",
  "open",
  "negotiation",
  "commercial_review",
  "approved",
  "booking_ready",
  "won",
  "on_hold",
  "lost",
  "cancelled",
] as const;

export type DealStatus =
  (typeof DEAL_STATUSES)[number];

  export const DEAL_STATUS_TRANSITIONS: Readonly<
  Record<DealStatus, readonly DealStatus[]>
> = {
  draft: [
    "open",
    "negotiation",
    "commercial_review",
    "approved",
    "on_hold",
    "lost",
    "cancelled",
  ],

  open: [
    "negotiation",
    "commercial_review",
    "approved",
    "on_hold",
    "lost",
    "cancelled",
  ],

  negotiation: [
    "commercial_review",
    "approved",
    "on_hold",
    "lost",
    "cancelled",
  ],

  commercial_review: [
    "negotiation",
    "approved",
    "on_hold",
    "lost",
    "cancelled",
  ],

  approved: [
    "negotiation",
    "commercial_review",
    "booking_ready",
    "on_hold",
    "lost",
    "cancelled",
  ],

  booking_ready: [
    "negotiation",
    "commercial_review",
    "approved",
    "won",
    "on_hold",
    "lost",
    "cancelled",
  ],

  won: [],

  on_hold: [
    "open",
    "negotiation",
    "commercial_review",
    "approved",
    "booking_ready",
    "lost",
    "cancelled",
  ],

  lost: [],

  cancelled: [],
};


export function isDealStatusTransitionAllowed(
  currentStatus: DealStatus,
  requestedStatus: DealStatus,
): boolean {
  if (currentStatus === requestedStatus) {
    return true;
  }

  return DEAL_STATUS_TRANSITIONS[currentStatus].includes(
    requestedStatus,
  );
}


export const DEAL_OFFER_PARTIES = [
  "customer",
  "organization",
] as const;

export type DealOfferParty =
  (typeof DEAL_OFFER_PARTIES)[number];


export const DEAL_OFFER_STATUSES = [
  "draft",
  "proposed",
  "countered",
  "accepted",
  "rejected",
  "withdrawn",
  "expired",
] as const;

export type DealOfferStatus =
  (typeof DEAL_OFFER_STATUSES)[number];


export const DEAL_COMMERCIAL_APPROVAL_STATUSES = [
  "pending",
  "approved",
  "rejected",
  "cancelled",
] as const;

export type DealCommercialApprovalStatus =
  (typeof DEAL_COMMERCIAL_APPROVAL_STATUSES)[number];


// PostgreSQL numeric values can be returned by PostgREST as
// either number-like or string-like values depending on the
// client/serialization path.
//
// Keeping the raw contract flexible prevents accidental
// precision assumptions inside the data-access layer.
export type DealNumeric =
  | number
  | string;


// JSONB commercial terms / metadata.
export type DealJsonObject =
  Record<string, unknown>;


// ============================================================
// RAW DATABASE ROW CONTRACTS
// ============================================================

export type DealRow = {
  id: string;

  organization_id: string;
  lead_id: string;

  site_visit_id: string | null;
  inventory_unit_id: string | null;
  booking_id: string | null;

  status: DealStatus;

  assigned_to: string | null;

  currency_code: string;

  listed_price_snapshot:
    | DealNumeric
    | null;

  quoted_price_snapshot:
    | DealNumeric
    | null;

  minimum_negotiable_price_snapshot:
    | DealNumeric
    | null;

  agreed_price:
    | DealNumeric
    | null;

  booking_probability:
    | DealNumeric
    | null;

  next_action_at: string | null;

  hold_reason: string | null;
  loss_reason: string | null;
  cancellation_reason: string | null;

  notes: string | null;

  won_at: string | null;
  lost_at: string | null;
  closed_at: string | null;

  created_by: string | null;
  updated_by: string | null;
  deleted_by: string | null;

  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};


export type DealOfferRow = {
  id: string;

  organization_id: string;
  deal_id: string;

  offered_by_party: DealOfferParty;

  status: DealOfferStatus;

  offer_amount: DealNumeric;

  currency_code: string;

  offer_terms: DealJsonObject;

  notes: string | null;

  valid_until: string | null;
  responded_at: string | null;

  created_by: string | null;

  created_at: string;
  updated_at: string;
};


export type DealCommercialApprovalRow = {
  id: string;

  organization_id: string;
  deal_id: string;
  offer_id: string | null;

  status: DealCommercialApprovalStatus;

  requested_amount: DealNumeric;

  minimum_negotiable_price_snapshot:
    | DealNumeric
    | null;

  request_reason: string;

  decision_notes: string | null;

  requested_by: string | null;
  decided_by: string | null;

  requested_at: string;
  decided_at: string | null;

  created_at: string;
  updated_at: string;
};


export type DealStatusHistoryRow = {
  id: string;

  organization_id: string;
  deal_id: string;

  previous_status:
    | DealStatus
    | null;

  new_status: DealStatus;

  change_reason: string | null;

  changed_by: string | null;

  metadata: DealJsonObject;

  changed_at: string;
};


// ============================================================
// APPLICATION READ MODELS
// ============================================================

export type DealSummary = {
  id: string;

  organizationId: string;
  leadId: string;

  siteVisitId: string | null;
  inventoryUnitId: string | null;
  bookingId: string | null;

  status: DealStatus;

  assignedTo: string | null;

  currencyCode: string;

  listedPriceSnapshot:
    | DealNumeric
    | null;

  quotedPriceSnapshot:
    | DealNumeric
    | null;

  minimumNegotiablePriceSnapshot:
    | DealNumeric
    | null;

  agreedPrice:
    | DealNumeric
    | null;

  bookingProbability:
    | DealNumeric
    | null;

  nextActionAt: string | null;

  holdReason: string | null;
  lossReason: string | null;
  cancellationReason: string | null;

  notes: string | null;

  wonAt: string | null;
  lostAt: string | null;
  closedAt: string | null;

  createdAt: string;
  updatedAt: string;
};


export type DealOfferSummary = {
  id: string;
  dealId: string;

  offeredByParty: DealOfferParty;

  status: DealOfferStatus;

  offerAmount: DealNumeric;

  currencyCode: string;

  offerTerms: DealJsonObject;

  notes: string | null;

  validUntil: string | null;
  respondedAt: string | null;

  createdAt: string;
  updatedAt: string;
};


export type DealCommercialApprovalSummary = {
  id: string;
  dealId: string;
  offerId: string | null;

  status: DealCommercialApprovalStatus;

  requestedAmount: DealNumeric;

  minimumNegotiablePriceSnapshot:
    | DealNumeric
    | null;

  requestReason: string;

  decisionNotes: string | null;

  requestedBy: string | null;
  decidedBy: string | null;

  requestedAt: string;
  decidedAt: string | null;

  createdAt: string;
  updatedAt: string;
};


export type DealStatusHistorySummary = {
  id: string;
  dealId: string;

  previousStatus:
    | DealStatus
    | null;

  newStatus: DealStatus;

  changeReason: string | null;

  changedBy: string | null;

  metadata: DealJsonObject;

  changedAt: string;
};


// ============================================================
// MUTATION INPUT CONTRACTS
// ============================================================

export type CreateDealValues = {
  leadId: string;

  siteVisitId?: string | null;
  inventoryUnitId?: string | null;

  assignedTo?: string | null;

  currencyCode?: string;

  bookingProbability?:
    | number
    | null;

  nextActionAt?: string | null;

  notes?: string | null;
};


export type UpdateDealValues = {
  dealId: string;

  expectedUpdatedAt: string;

  assignedTo?: string | null;

  bookingProbability?:
    | number
    | null;

  nextActionAt?: string | null;

  holdReason?: string | null;

  notes?: string | null;
};


export type CreateDealOfferValues = {
  dealId: string;

  offeredByParty: DealOfferParty;

  offerAmount: number;

  currencyCode?: string;

  offerTerms?: DealJsonObject;

  notes?: string | null;

  validUntil?: string | null;
};


export type UpdateDealOfferStatusValues = {
  dealId: string;
  offerId: string;

  expectedUpdatedAt: string;

  status: DealOfferStatus;
};


export type RequestCommercialApprovalValues = {
  dealId: string;

  offerId?: string | null;

  requestedAmount: number;

  requestReason: string;
};


export type DecideCommercialApprovalValues = {
  dealId: string;
  approvalId: string;

  expectedUpdatedAt: string;

  decision:
    | "approved"
    | "rejected";

  decisionNotes?: string | null;
};


export type CancelCommercialApprovalValues = {
  dealId: string;
  approvalId: string;

  expectedUpdatedAt: string;
};


export type GenericDealStatusTarget =
  | "open"
  | "negotiation"
  | "commercial_review"
  | "approved"
  | "booking_ready";


export type ChangeDealStatusValues = {
  dealId: string;

  expectedUpdatedAt: string;

  status: GenericDealStatusTarget;
};


export type MarkDealLostValues = {
  dealId: string;

  expectedUpdatedAt: string;

  lossReason: string;
};


export type PutDealOnHoldValues = {
  dealId: string;

  expectedUpdatedAt: string;

  holdReason: string;
};


export type CancelDealValues = {
  dealId: string;

  expectedUpdatedAt: string;

  cancellationReason: string;
};


export type LinkDealBookingValues = {
  dealId: string;

  expectedUpdatedAt: string;

  bookingId: string;
};


export type MarkDealWonValues = {
  dealId: string;

  expectedUpdatedAt: string;
};


// ============================================================
// DATA ACCESS / PERMISSIONS
// ============================================================

export type DealOSDataAccess = {
  canViewDeals: boolean;
  canViewAllDeals: boolean;

  canCreateDeal: boolean;
  canUpdateDeal: boolean;
  canAssignDeal: boolean;

  canManageOffers: boolean;
  canApproveCommercials: boolean;

  canMarkWon: boolean;
  canMarkLost: boolean;

  canHandoffBooking: boolean;

  canDeleteDeal: boolean;
};


// ============================================================
// SERVICE RESULT CONTRACT
// ============================================================

export type DealOSServiceErrorCode =
  | "validation"
  | "not_found"
  | "permission_denied"
  | "conflict"
  | "invalid_state"
  | "invalid_assignee"
  | "database_error";


export type DealOSServiceSuccess = {
  ok: true;

  dealId?: string;

  offerId?: string;

  approvalId?: string;

  updatedAt?: string;
};


export type DealOSServiceFailure = {
  ok: false;

  code: DealOSServiceErrorCode;

  message: string;
};


export type DealOSServiceResult =
  | DealOSServiceSuccess
  | DealOSServiceFailure;

  export type DealOSReadSuccess<T> = {
  ok: true;
  data: T;
};


export type DealOSReadResult<T> =
  | DealOSReadSuccess<T>
  | DealOSServiceFailure;