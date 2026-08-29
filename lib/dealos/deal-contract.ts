import type {
  DealOSActionState,
} from "@/types/dealos-actions";

export const DEALOS_PERMISSIONS = {
  viewDeals: "deals.view",
  viewAllDeals: "deals.view_all",

  createDeal: "deals.create",
  updateDeal: "deals.update",
  assignDeal: "deals.assign",

  manageOffers: "deals.manage_offers",
  approveCommercials:
    "deals.approve_commercials",

  markWon: "deals.mark_won",
  markLost: "deals.mark_lost",

  handoffBooking:
    "deals.handoff_booking",

  deleteDeal: "deals.delete",
} as const;

export const INITIAL_DEALOS_ACTION_STATE:
  DealOSActionState = {
    status: "idle",
    message: "",
    fieldErrors: {},
  };