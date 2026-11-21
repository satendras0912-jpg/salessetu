import test from "node:test";
import assert from "node:assert/strict";
import { readdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { inspectMigrationFiles } from "./preflight.mjs";

test("repository migration versions are unique after the filename-only fix", async () => {
  const directory = fileURLToPath(new URL("../../supabase/migrations/", import.meta.url));
  const names = await readdir(directory);
  const report = inspectMigrationFiles(names);
  assert.deepEqual(report.errors, []);
  assert.equal(report.totalFiles, report.uniqueVersions);
  assert.ok(report.totalFiles >= 103);
  assert.ok(names.includes("20261102100000_lead_capture_reliability_guard.sql"));
  assert.ok(names.includes("20261102100100_owner_effective_permissions.sql"));
  assert.ok(!names.includes("20261102100000_owner_effective_permissions.sql"));
});

test("duplicates are rejected", () => {
  const report = inspectMigrationFiles(["20261102100000_a.sql", "20261102100000_b.sql"]);
  assert.match(report.errors.join("\n"), /Duplicate migration version 20261102100000/);
});

test("legacy and timestamped migration versions are allowed", () => {
  const report = inspectMigrationFiles(["001_initial.sql", "045_deals.sql", "20261102100100_permissions.sql"]);
  assert.equal(report.uniqueVersions, 3);
  assert.equal(report.legacyVersions, 2);
  assert.equal(report.timestampVersions, 1);
  assert.deepEqual(report.errors, []);
});

test("empty and malformed inventories are rejected", () => {
  assert.ok(inspectMigrationFiles([]).errors.length);
  assert.ok(inspectMigrationFiles(["20261102_short.sql"]).errors.length);
});
