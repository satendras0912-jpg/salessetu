export type InventoryMatchReviewActionState = {
  status: "idle" | "error" | "success";
  message: string | null;
};

export const INITIAL_INVENTORY_MATCH_REVIEW_STATE: InventoryMatchReviewActionState = {
  status: "idle",
  message: null,
};
