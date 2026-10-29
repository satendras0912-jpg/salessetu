import type { GeoTag } from "./geo-tag-contract";

export type SampleGeoTeamSeat = {
  code: string;
  role: "Team Lead" | "Sales Executive";
  coverage: GeoTag[];
  purpose: string;
};

/**
 * A tenant-safe planning template only. These are not user accounts, agent
 * profiles, or routing rules; the real people are added later by an owner.
 */
export const SAMPLE_GEO_TEAM_SEATS: SampleGeoTeamSeat[] = [
  {
    code: "GEO-LEAD-01",
    role: "Team Lead",
    coverage: ["noida", "greater_noida"],
    purpose: "Coverage review, handoff approval and escalation.",
  },
  {
    code: "GEO-SALES-01",
    role: "Sales Executive",
    coverage: ["greater_noida_west", "siddharth_vihar"],
    purpose: "New enquiry qualification and follow-up ownership.",
  },
  {
    code: "GEO-SALES-02",
    role: "Sales Executive",
    coverage: ["wave_city", "raj_nagar_extension"],
    purpose: "Project matching and site-visit coordination.",
  },
  {
    code: "GEO-SALES-03",
    role: "Sales Executive",
    coverage: ["ghaziabad"],
    purpose: "Overflow and city-wide follow-up coverage.",
  },
];
