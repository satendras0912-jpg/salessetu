import "server-only";

import { requirePermissionAccess } from "@/lib/auth/access-control";
import { createClient } from "@/lib/supabase/server";

import {
  defaultGeoCoverageQueues,
  type GeoCoverageQueue,
  type GeoCoverageStatus,
} from "./geo-coverage-contract";
import {
  isGeoTag,
  type GeoTag,
} from "./geo-tag-contract";

type CoverageRow = {
  geo_tag: string;
  status: string;
  auto_assignment_enabled: boolean;
  assignment_teams: { team_name: string | null } | null;
};

function isCoverageStatus(value: string): value is GeoCoverageStatus {
  return ["draft", "active", "paused"].includes(value);
}

function isMissingCoverageRelation(message: string | undefined): boolean {
  const normalized = message?.toLowerCase() ?? "";
  return normalized.includes("geo_coverage_queues") && (
    normalized.includes("could not find") ||
    normalized.includes("does not exist")
  );
}

export async function getGeoCoverageOverview(): Promise<{
  queues: GeoCoverageQueue[];
  setupPending: boolean;
}> {
  const { context } = await requirePermissionAccess({
    allOf: ["leads.view", "followups.view"],
    loginRedirectTo: "/login?next=/dashboard/follow-ups/coverage",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;
  if (!organizationId) {
    throw new Error("An active organization is required.");
  }

  const supabase = await createClient();
  const { data, error } = await supabase
    .from("geo_coverage_queues")
    .select("geo_tag,status,auto_assignment_enabled,assignment_teams(team_name)")
    .eq("organization_id", organizationId);

  if (error) {
    if (isMissingCoverageRelation(error.message)) {
      return { queues: defaultGeoCoverageQueues(), setupPending: true };
    }

    throw new Error("Unable to load GEO coverage. Please try again.");
  }

  const queueByTag = new Map<GeoTag, GeoCoverageQueue>();
  for (const row of (data ?? []) as unknown as CoverageRow[]) {
    if (!isGeoTag(row.geo_tag) || !isCoverageStatus(row.status)) continue;

    queueByTag.set(row.geo_tag, {
      geoTag: row.geo_tag,
      status: row.status,
      assignmentTeamName: row.assignment_teams?.team_name ?? null,
      autoAssignmentEnabled: row.auto_assignment_enabled === true,
    });
  }

  return {
    queues: defaultGeoCoverageQueues().map(
      (defaultQueue) => queueByTag.get(defaultQueue.geoTag) ?? defaultQueue,
    ),
    setupPending: false,
  };
}
