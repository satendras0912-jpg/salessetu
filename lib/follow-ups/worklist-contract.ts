import { deriveGeoTag, GEO_TAGS, geoTagLabel, type GeoTag } from "@/lib/geo/geo-tag-contract";

export const WORKLIST_VIEWS = ["open", "overdue", "today", "upcoming", "completed"] as const;
export const WORKLIST_OWNERS = ["all", "mine", "unassigned"] as const;
export const WORKLIST_GEO_FILTERS = ["all", "mapping_required", ...GEO_TAGS] as const;
export const OPEN_TASK_STATUSES = ["pending", "in_progress", "overdue", "rescheduled"];
export type WorklistView = typeof WORKLIST_VIEWS[number];
export type WorklistOwner = typeof WORKLIST_OWNERS[number];
export type WorklistGeoFilter = "all" | "mapping_required" | GeoTag;
export type WorklistFilters = { view: WorklistView; owner: WorklistOwner; geo: WorklistGeoFilter; page: number };
export const PAGE_SIZE = 25;

export function parseWorklistFilters(params: Record<string, string | string[] | undefined>): WorklistFilters {
  const single = (value: string | string[] | undefined) => Array.isArray(value) ? value[0] : value;
  const view = single(params.view);
  const owner = single(params.owner);
  const geo = single(params.geo);
  const rawPage = single(params.page) ?? "1";
  const page = /^\d+$/.test(rawPage) ? Number(rawPage) : 1;
  return {
    view: WORKLIST_VIEWS.includes(view as WorklistView) ? view as WorklistView : "open",
    owner: WORKLIST_OWNERS.includes(owner as WorklistOwner) ? owner as WorklistOwner : "all",
    geo: WORKLIST_GEO_FILTERS.includes(geo as WorklistGeoFilter) ? geo as WorklistGeoFilter : "all",
    page: Number.isSafeInteger(page) && page > 0 && page <= 100000 ? page : 1,
  };
}

// The worklist explicitly displays India time, including its day boundaries.
export function indiaDayBounds(now: Date) {
  const offset = 330 * 60 * 1000;
  const local = new Date(now.getTime() + offset);
  const start = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate()) - offset;
  return { start: new Date(start).toISOString(), end: new Date(start + 86400000).toISOString() };
}

export function worklistHref(filters: WorklistFilters, page = filters.page) {
  return `/dashboard/follow-ups?${new URLSearchParams({ view: filters.view, owner: filters.owner, geo: filters.geo, page: String(page) })}`;
}

/**
 * A follow-up stays in a human-owned queue until a GEO coverage rule assigns it.
 * Keep the label derived from lead data for now so no fallback task is hidden when
 * coverage members have not yet been configured.
 */
export function geoQueueLabel(geoTag: string | null | undefined, location: string | null | undefined, city: string | null | undefined) {
  const canonical = geoTagLabel(geoTag) ?? geoTagLabel(deriveGeoTag(location, city));
  if (canonical) return `GEO: ${canonical}`;
  const clean = (value: string | null | undefined) => value?.replace(/\s+/g, " ").trim() || null;
  const locality = clean(location);
  const areaCity = clean(city);
  if (locality && areaCity && locality.toLocaleLowerCase() !== areaCity.toLocaleLowerCase()) {
    return `GEO: ${locality} · ${areaCity}`;
  }
  if (locality || areaCity) return `GEO: ${locality ?? areaCity}`;
  return "GEO: mapping required";
}
