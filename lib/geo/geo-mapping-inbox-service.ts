import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";

import { deriveGeoTag, type GeoTag } from "./geo-tag-contract";

export type GeoMappingLead = {
  id: string;
  name: string;
  preferredLocation: string | null;
  preferredCity: string | null;
  suggestedGeoTag: GeoTag | null;
};

type GeoMappingLeadRow = {
  id: string;
  first_name: string | null;
  last_name: string | null;
  preferred_location: string | null;
  preferred_city: string | null;
};

function leadName(row: GeoMappingLeadRow): string {
  const name = [row.first_name, row.last_name]
    .filter((value): value is string => Boolean(value?.trim()))
    .join(" ");

  return name || "Unnamed lead";
}

export async function getGeoMappingInbox(): Promise<{
  leads: GeoMappingLead[];
}> {
  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/geo-mapping",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;
  if (!organizationId) {
    throw new Error("An active organization is required.");
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("leads")
    .select("id,first_name,last_name,preferred_location,preferred_city")
    .eq("organization_id", organizationId)
    .is("deleted_at", null)
    .is("geo_tag", null)
    .order("created_at", { ascending: false })
    .limit(50);

  if (error) {
    throw new Error("Unable to load GEO mapping inbox. Please try again.");
  }

  return {
    leads: ((data ?? []) as GeoMappingLeadRow[]).map((lead) => ({
      id: lead.id,
      name: leadName(lead),
      preferredLocation: lead.preferred_location,
      preferredCity: lead.preferred_city,
      suggestedGeoTag: deriveGeoTag(
        lead.preferred_location,
        lead.preferred_city,
      ),
    })),
  };
}
