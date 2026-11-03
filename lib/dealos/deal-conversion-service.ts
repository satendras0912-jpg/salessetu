import "server-only";

import {
  createClient,
} from "@/lib/supabase/server";

export type DealConversionEligibility = {
  isEligible: boolean;
  message: string;
};

type DealConversionEligibilityRow = {
  is_eligible: boolean;
  message: string;
};

export async function getDealConversionEligibility(
  leadId: string,
): Promise<DealConversionEligibility> {
  const supabase =
    await createClient();

  const {
    data,
    error,
  } = await supabase.rpc(
    "get_deal_conversion_eligibility",
    {
      requested_lead_id: leadId,
    },
  );

  if (error) {
    return {
      isEligible: false,
      message:
        "Deal conversion eligibility could not be loaded. Refresh the lead and try again.",
    };
  }

  const row =
    (
      data as
        | DealConversionEligibilityRow[]
        | null
    )?.[0];

  if (!row) {
    return {
      isEligible: false,
      message:
        "Deal conversion eligibility could not be verified.",
    };
  }

  return {
    isEligible:
      row.is_eligible === true,
    message:
      row.message ||
      "Deal conversion eligibility could not be verified.",
  };
}
