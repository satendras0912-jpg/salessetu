import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import ts from "typescript";

const source = readFileSync(
  new URL(
    "../../lib/ai-calling/post-call-routing.ts",
    import.meta.url,
  ),
  "utf8",
);

const compiled = ts.transpileModule(
  source,
  {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
  },
).outputText;

const exports = {};
vm.runInNewContext(
  compiled,
  {
    exports,
  },
);

const {
  getPostCallRoutingPlan,
} = exports;

test(
  "details-first qualification creates a safe internal clarification task",
  () => {
    assert.deepEqual(
      getPostCallRoutingPlan({
        qualificationStatus: "manual_review",
        recommendedAction: "send_details",
      }),
      {
        createTask: true,
        title: "Share requested details and confirm BHK preference",
        followUpType: "general",
        priority: "high",
        dueInMinutes: 15,
      },
    );
  },
);

test(
  "explicit site-visit interest creates a task, not an appointment",
  () => {
    assert.deepEqual(
      getPostCallRoutingPlan({
        qualificationStatus: "qualified_hot",
        recommendedAction:
          "assign_agent_and_schedule_site_visit",
      }),
      {
        createTask: true,
        title: "Confirm site visit and assign a representative",
        followUpType: "site_visit",
        priority: "high",
        dueInMinutes: 15,
      },
    );
  },
);

test(
  "hot callback qualification creates a human callback task",
  () => {
    assert.deepEqual(
      getPostCallRoutingPlan({
        qualificationStatus: "qualified_hot",
        recommendedAction:
          "agent_callback_and_nurture",
      }),
      {
        createTask: true,
        title: "Call qualified lead and confirm next step",
        followUpType: "call",
        priority: "high",
        dueInMinutes: 15,
      },
    );
  },
);

test(
  "unqualified or suppressed leads do not receive a task",
  () => {
    const byStatus = getPostCallRoutingPlan({
      qualificationStatus: "unqualified",
      recommendedAction: null,
    });

    const byAction = getPostCallRoutingPlan({
      qualificationStatus: "qualified_cold",
      recommendedAction: "close_or_suppress",
    });

    assert.equal(byStatus.createTask, false);
    assert.equal(byAction.createTask, false);
  },
);

test(
  "routing implementation remains internal and idempotent",
  () => {
    const serviceSource = readFileSync(
      new URL(
        "../../lib/ai-calling/post-call-routing-service.ts",
        import.meta.url,
      ),
      "utf8",
    );

    assert.match(
      serviceSource,
      /AI post-call routing/,
    );
    assert.match(
      serviceSource,
      /create_follow_up_task/,
    );
    assert.doesNotMatch(
      serviceSource,
      /queueLeadAiCall|dispatchNextAiCall|sendWhatsApp|createSiteVisit/,
    );
  },
);
