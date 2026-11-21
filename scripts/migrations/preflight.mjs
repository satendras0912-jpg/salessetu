import { readdir, lstat } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const DEFAULT_DIR = resolve(dirname(SCRIPT_PATH), "../../supabase/migrations");
const FILENAME = /^(\d{3}|\d{14})_([A-Za-z0-9_]+)\.sql$/;

export function inspectMigrationFiles(names) {
  const errors = [];
  const versions = new Map();
  const sqlNames = names.filter((name) => name.toLowerCase().endsWith(".sql"));
  for (const name of sqlNames) {
    const match = FILENAME.exec(name);
    if (!match) { errors.push("Invalid migration filename: " + name); continue; }
    const version = match[1];
    if (versions.has(version)) errors.push("Duplicate migration version " + version + ": " + versions.get(version) + " and " + name);
    else versions.set(version, name);
  }
  if (sqlNames.length === 0) errors.push("No SQL migrations found");
  const ordered = [...versions].sort((a, b) => a[0].localeCompare(b[0]));
  return {
    totalFiles: sqlNames.length,
    uniqueVersions: versions.size,
    legacyVersions: ordered.filter(([version]) => version.length === 3).length,
    timestampVersions: ordered.filter(([version]) => version.length === 14).length,
    firstVersion: ordered[0]?.[0] ?? null,
    lastVersion: ordered.at(-1)?.[0] ?? null,
    errors,
  };
}

async function main() {
  const args = process.argv.slice(2);
  const asJson = args.includes("--json");
  const dir = resolve(args.find((arg) => !arg.startsWith("--")) ?? DEFAULT_DIR);
  const names = await readdir(dir);
  const report = inspectMigrationFiles(names);
  for (const name of names.filter((item) => item.toLowerCase().endsWith(".sql"))) {
    const file = await lstat(join(dir, name));
    if (!file.isFile() || file.size === 0) report.errors.push("Not a nonempty regular SQL file: " + name);
  }
  if (asJson) console.log(JSON.stringify({ directory: dir, ...report }, null, 2));
  else {
    console.log("Migration preflight (offline only): " + report.totalFiles + " files, " + report.uniqueVersions + " unique versions");
    console.log("Legacy: " + report.legacyVersions + "; timestamped: " + report.timestampVersions);
    for (const error of report.errors) console.error("ERROR: " + error);
    if (report.errors.length === 0) console.log("PASS: filename versions are unique; no database accessed");
  }
  if (report.errors.length > 0) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === SCRIPT_PATH) {
  main().catch((error) => {
    console.error("Migration preflight failed: " + error.message);
    process.exitCode = 1;
  });
}
