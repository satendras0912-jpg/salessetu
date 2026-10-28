import { readFileSync } from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";

test("SLA dashboard preserves active-task, tenant and alert constraints", () => {
  const service = readFileSync(new URL("../../lib/follow-ups/sla-dashboard-service.ts", import.meta.url), "utf8");
  const page = readFileSync(new URL("../../app/dashboard/follow-ups/sla/page.tsx", import.meta.url), "utf8");
  assert.match(service, /allOf: \["leads\.view", "followups\.view"\]/);
  assert.match(service, /in\("status", active\)/);
  assert.match(service, /eq\("organization_id", organizationId\)/);
  assert.match(service, /eq\("leads\.organization_id", organizationId\)/);
  assert.match(service, /status\.eq\.overdue,sla_status\.in\.\(at_risk,breached\)/);
  assert.match(page, /Completed, cancelled and failed tasks are excluded/);
  assert.match(page, /Open task actions/);
});
