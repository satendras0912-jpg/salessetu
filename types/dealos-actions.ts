export type DealOSActionStatus =
  | "idle"
  | "success"
  | "error"
  | "conflict";

export type DealOSFieldErrors =
  Partial<Record<string, string[]>>;

export type DealOSActionState = {
  status: DealOSActionStatus;

  message: string;

  fieldErrors: DealOSFieldErrors;

  dealId?: string;
  offerId?: string;
  approvalId?: string;
};