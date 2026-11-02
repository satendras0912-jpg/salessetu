import { GEO_TAGS, type GeoTag } from "@/lib/geo/geo-tag-contract";
import { indiaDayBounds } from "@/lib/follow-ups/worklist-contract";

export const SITE_VISIT_VIEWS = ["open", "today", "upcoming", "overdue", "completed"] as const;
export const SITE_VISIT_GEO_FILTERS = ["all", "mapping_required", ...GEO_TAGS] as const;
export const OPEN_SITE_VISIT_STATUSES = [
  "draft", "scheduled", "confirmed", "agent_en_route", "customer_en_route", "checked_in", "in_progress", "rescheduled",
] as const;
export const SITE_VISIT_PAGE_SIZE = 25;

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export type SiteVisitView = typeof SITE_VISIT_VIEWS[number];
export type SiteVisitGeoFilter = "all" | "mapping_required" | GeoTag;
export type SiteVisitAgentFilter = "all" | "unassigned" | string;
export type SiteVisitWorklistFilters = {
  view: SiteVisitView;
  geo: SiteVisitGeoFilter;
  agent: SiteVisitAgentFilter;
  page: number;
};

export function parseSiteVisitWorklistFilters(params: Record<string, string | string[] | undefined>): SiteVisitWorklistFilters {
  const single = (value: string | string[] | undefined) => Array.isArray(value) ? value[0] : value;
  const rawView = single(params.view);
  const rawGeo = single(params.geo);
  const rawAgent = single(params.agent);
  const rawPage = single(params.page) ?? "1";
  const page = /^\d+$/.test(rawPage) ? Number(rawPage) : 1;
  return {
    view: SITE_VISIT_VIEWS.includes(rawView as SiteVisitView) ? rawView as SiteVisitView : "open",
    geo: SITE_VISIT_GEO_FILTERS.includes(rawGeo as SiteVisitGeoFilter) ? rawGeo as SiteVisitGeoFilter : "all",
    agent: rawAgent === "unassigned" ? "unassigned" : UUID_PATTERN.test(rawAgent ?? "") ? rawAgent as string : "all",
    page: Number.isSafeInteger(page) && page > 0 && page <= 100000 ? page : 1,
  };
}

export function siteVisitWorklistHref(filters: SiteVisitWorklistFilters, page = filters.page) {
  return `/dashboard/site-visits?${new URLSearchParams({ view: filters.view, geo: filters.geo, agent: filters.agent, page: String(page) })}`;
}

export { indiaDayBounds };
