export const WORKLIST_VIEWS = ["open", "overdue", "today", "upcoming", "completed"] as const;
export const WORKLIST_OWNERS = ["all", "mine", "unassigned"] as const;
export const OPEN_TASK_STATUSES = ["pending", "in_progress", "overdue", "rescheduled"];
export type WorklistView = typeof WORKLIST_VIEWS[number];
export type WorklistOwner = typeof WORKLIST_OWNERS[number];
export type WorklistFilters = { view: WorklistView; owner: WorklistOwner; page: number };
export const PAGE_SIZE = 25;

export function parseWorklistFilters(params: Record<string, string | string[] | undefined>): WorklistFilters {
  const single = (value: string | string[] | undefined) => Array.isArray(value) ? value[0] : value;
  const view = single(params.view);
  const owner = single(params.owner);
  const rawPage = single(params.page) ?? "1";
  const page = /^\d+$/.test(rawPage) ? Number(rawPage) : 1;
  return {
    view: WORKLIST_VIEWS.includes(view as WorklistView) ? view as WorklistView : "open",
    owner: WORKLIST_OWNERS.includes(owner as WorklistOwner) ? owner as WorklistOwner : "all",
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
  return `/dashboard/follow-ups?${new URLSearchParams({ view: filters.view, owner: filters.owner, page: String(page) })}`;
}
