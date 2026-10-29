import {
  GEO_TAG_LABELS,
  GEO_TAGS,
  type GeoTag,
} from "@/lib/geo/geo-tag-contract";

export const GEO_COVERAGE_STATUSES = [
  "draft",
  "active",
  "paused",
] as const;

export type GeoCoverageStatus =
  (typeof GEO_COVERAGE_STATUSES)[number];

export type GeoCoverageQueue = {
  geoTag: GeoTag;
  status: GeoCoverageStatus;
  assignmentTeamName: string | null;
  autoAssignmentEnabled: boolean;
};

export function defaultGeoCoverageQueues(): GeoCoverageQueue[] {
  return GEO_TAGS.map((geoTag) => ({
    geoTag,
    status: "draft",
    assignmentTeamName: null,
    autoAssignmentEnabled: false,
  }));
}

export function geoCoverageStatusLabel(
  status: GeoCoverageStatus,
): string {
  if (status === "active") return "Active";
  if (status === "paused") return "Paused";
  return "Draft";
}

export function geoCoverageQueueLabel(
  queue: GeoCoverageQueue,
): string {
  return queue.assignmentTeamName
    ? queue.assignmentTeamName
    : "Unassigned team queue";
}

export { GEO_TAG_LABELS };
