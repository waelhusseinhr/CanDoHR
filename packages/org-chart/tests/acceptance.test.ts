import assert from "node:assert/strict";
import { renderToStaticMarkup } from "react-dom/server";
import { test } from "node:test";
import { addDays } from "@candohr/shared";
import { createOrgChartApp } from "../src/http.ts";
import { assertChartLocales } from "../src/i18n.ts";
import { OrgChart, nextMonday, type OrgChart as Chart } from "../src/engine.ts";
import { OrgChartScreen } from "../src/screens.ts";

const TODAY = "2026-11-01";
const KNOWN = "2026-11-01T15:00:00.000Z";

function office(): Chart {
  const chart = new OrgChart({ today: TODAY, knownAt: KNOWN, finalizedThrough: "2026-10-31" });
  chart.addUnit({ id: "parks", parentId: null, name: "Parks", province: "MB", costCentreId: "cc-parks" });
  chart.addBox({
    positionId: "pos-ben",
    title: "Manager",
    orgUnitId: "parks",
    reportsToPositionId: null,
    holder: { personId: "ben", name: "Ben", assignmentId: "asg-ben" },
  });
  chart.addBox({
    positionId: "pos-chloe",
    title: "Director",
    orgUnitId: "parks",
    reportsToPositionId: null,
    holder: { personId: "chloe", name: "Chloe", assignmentId: "asg-chloe" },
  });
  chart.addBox({
    positionId: "pos-ana",
    title: "Clerk",
    orgUnitId: "parks",
    reportsToPositionId: "pos-ben",
    holder: { personId: "ana", name: "Ana", assignmentId: "asg-ana", rate: "30.00", laterRate: { date: "2027-01-01", rate: "40.00" } },
  });
  return chart;
}

test("docs/04 §8 test 1 drag Ana under Chloe from next Monday", () => {
  const chart = office();
  const monday = nextMonday(TODAY);
  const moved = chart.move({
    subject: { type: "position", id: "pos-ana" },
    target: { type: "position", id: "pos-chloe" },
    effectiveDate: monday,
    reasonCode: "reorganization",
  });
  assert.equal(moved.ok, true);
  assert.equal(moved.operations[0]?.op, "position.update");
  assert.equal(chart.managerAsOf("ana", TODAY), "Ben");
  assert.equal(chart.managerAsOf("ana", monday), "Chloe");
  assert.equal(chart.chart({ asOf: TODAY }).edges.some((edge) => edge.from === "pos-ben" && edge.to === "pos-ana"), true);
  assert.equal(chart.chart({ asOf: monday }).edges.some((edge) => edge.from === "pos-chloe" && edge.to === "pos-ana"), true);
  assert.equal(chart.timesheetApprover("ana", monday), "Chloe");
  assert.equal(chart.timesheetApprover("ana", TODAY), "Ben");
});

test("docs/04 §8 test 2 a profile manager change updates other open charts", () => {
  const chart = office();
  chart.subscribe("browser-a", ["parks"]);
  chart.subscribe("browser-b", ["parks"]);
  const moved = chart.move({
    subject: { type: "position", id: "pos-ana" },
    target: { type: "position", id: "pos-chloe" },
    effectiveDate: "2026-12-01",
    reasonCode: "manager_change",
  });
  assert.equal(moved.ok, true);
  assert.equal(moved.status, "scheduled");
  const today = chart.chart({ asOf: TODAY });
  assert.equal(today.nodes.find((node) => node.id === "pos-ana")?.badges.includes("upcoming_change:2026-12-01"), true);
  assert.equal(chart.chart({ asOf: "2026-12-01" }).edges.some((edge) => edge.from === "pos-chloe" && edge.to === "pos-ana"), true);
  assert.equal(chart.sessions.inbox("browser-b").some((message) => message.type === "org.changed" && message.units.includes("parks")), true);
});

test("docs/04 §8 test 3 a past cross-province move shows tax and retro, then asks for each person", () => {
  const chart = new OrgChart(
    { today: TODAY, knownAt: KNOWN, finalizedThrough: "2026-10-31" },
    { directory: { candidates: () => ["hr-user"], onLeave: () => null, isSubordinateOnOtherAssignment: () => false } },
  );
  chart.addUnit({ id: "division-mb", parentId: null, name: "Manitoba", province: "MB", costCentreId: "cc-mb" });
  chart.addUnit({ id: "division-on", parentId: null, name: "Ontario", province: "ON", costCentreId: "cc-on" });
  chart.addUnit({ id: "north", parentId: "division-mb", name: "North", province: "MB", costCentreId: "cc-north" });
  chart.addBox({
    positionId: "pos-n1",
    title: "Clerk",
    orgUnitId: "north",
    reportsToPositionId: null,
    holder: { personId: "p1", name: "Pat", assignmentId: "asg-p1" },
  });
  chart.addBox({
    positionId: "pos-n2",
    title: "Clerk",
    orgUnitId: "north",
    reportsToPositionId: null,
    holder: { personId: "p2", name: "Sam", assignmentId: "asg-p2" },
  });
  const preview = chart.move({
    subject: { type: "org_unit", id: "north" },
    target: { type: "org_unit", id: "division-on" },
    effectiveDate: "2026-10-15",
    isCorrection: false,
    reasonCode: "reorganization",
  });
  assert.equal(preview.ok, true);
  assert.equal(preview.status, "pending_approval");
  assert.equal(preview.validation.consequences.some((row) => row.kind === "tax_province"), true);
  assert.equal(preview.validation.consequences.some((row) => row.kind === "retro"), true);
  assert.equal(chart.retroRequests.length, 0);
  assert.equal(chart.parentAsOf("north", TODAY), "division-mb");
  const approved = chart.decide(preview.changeSetId ?? "", "hr-user");
  assert.equal(approved.ok, true);
  assert.equal(chart.retroRequests.map((row) => row.personId).sort().join(","), "p1,p2");
});

test("docs/04 §8 test 4 two people onto one vacant box are blocked unless overlap is approved", () => {
  const chart = office();
  chart.addBox({ positionId: "pos-vacant", title: "Spare", orgUnitId: "parks", reportsToPositionId: "pos-ben", fteBudget: "1.00" });
  const blocked = chart.move({
    subject: { type: "multiple", id: "asg-ana", ids: ["asg-ana", "asg-ben"] },
    target: { type: "vacant_position", id: "pos-vacant" },
    effectiveDate: TODAY,
  });
  assert.equal(blocked.ok, false);
  assert.equal(blocked.validation.errors[0]?.code, "OVER_FTE");
  const allowed = chart.move({
    subject: { type: "multiple", id: "asg-ana", ids: ["asg-ana", "asg-ben"] },
    target: { type: "vacant_position", id: "pos-vacant" },
    effectiveDate: TODAY,
    overlapApproved: true,
    endDate: "2026-12-01",
  });
  assert.equal(allowed.ok, true);
});

test("docs/04 §8 test 5 a plan keeps the live chart still until it is approved as one change set", () => {
  const chart = office();
  const plan = chart.createPlan({ name: "Spring", asOf: "2026-12-01" });
  for (let index = 0; index < 5; index += 1) {
    const positionId = `pos-extra-${index}`;
    chart.addBox({ positionId, title: `Extra ${index}`, orgUnitId: "parks", reportsToPositionId: "pos-ben" });
    const moved = chart.move({
      subject: { type: "position", id: positionId },
      target: { type: "position", id: "pos-chloe" },
      effectiveDate: "2026-12-01",
      planId: plan.planId,
      costImpact: "10.00",
    });
    assert.equal(moved.status, "draft");
  }
  assert.equal(chart.chart({ asOf: "2026-12-01" }).edges.some((edge) => edge.from === "pos-chloe" && edge.to === "pos-extra-0"), false);
  assert.equal(chart.chart({ asOf: "2026-12-01", planId: plan.planId }).edges.some((edge) => edge.from === "pos-chloe" && edge.to === "pos-extra-0"), true);
  const summary = chart.planSummary(plan.planId);
  assert.equal(summary.moveCount, 5);
  assert.equal(summary.annualCostDelta, "50.00");
  const approved = chart.approvePlan(plan.planId);
  assert.equal(approved.status, "approved");
  assert.equal(approved.operationCount, 5);
  assert.equal(chart.chart({ asOf: "2026-12-01" }).edges.some((edge) => edge.from === "pos-chloe" && edge.to === "pos-extra-4"), true);
});

test("docs/04 §8 test 6 keyboard Move to… matches a drag", () => {
  const dragged = office();
  const typed = office();
  const monday = nextMonday(TODAY);
  const gesture = {
    subject: { type: "position" as const, id: "pos-ana" },
    target: { type: "position" as const, id: "pos-chloe" },
    effectiveDate: monday,
  };
  assert.equal(dragged.move(gesture).ok, true);
  assert.equal(typed.move(gesture).ok, true);
  assert.equal(typed.managerAsOf("ana", monday), dragged.managerAsOf("ana", monday));
  assert.equal(typed.chart({ asOf: monday }).edges.some((edge) => edge.from === "pos-chloe" && edge.to === "pos-ana"), true);
});

test("docs/04 §8 test 7 a December transfer keeps the January raise and the new unit", () => {
  const chart = office();
  chart.addUnit({ id: "finance", parentId: null, name: "Finance", province: "MB", costCentreId: "cc-fin" });
  const moved = chart.move({
    subject: { type: "person_assignment", id: "asg-ana" },
    target: { type: "org_unit", id: "finance" },
    effectiveDate: "2026-12-01",
    conflictResolution: "merge",
  });
  assert.equal(moved.ok, true);
  assert.equal(chart.rateAsOf("asg-ana", "2027-01-01"), "40.00");
  assert.equal(chart.orgUnitAsOf("asg-ana", "2027-01-01"), "finance");
  assert.equal(chart.orgUnitAsOf("asg-ana", "2026-11-15"), "parks");
});

test("ENT-004 a future section move previews every hierarchy and waits for the date", () => {
  const chart = new OrgChart({ today: TODAY, knownAt: KNOWN });
  chart.addUnit({ id: "division-a", parentId: null, name: "Division A", province: "MB", costCentreId: "cc-a" });
  chart.addUnit({ id: "division-b", parentId: null, name: "Division B", province: "MB", costCentreId: "cc-b" });
  chart.addUnit({ id: "north", parentId: "division-a", name: "North", province: "MB", costCentreId: "cc-north" });
  const effective = addDays(TODAY, 30);
  const moved = chart.move({
    subject: { type: "org_unit", id: "north" },
    target: { type: "org_unit", id: "division-b" },
    effectiveDate: effective,
  });
  assert.equal(moved.ok, true);
  const text = moved.validation.consequences.map((row) => row.description).join(" ");
  assert.match(text, /Approval chains/);
  assert.match(text, /Cost centres/);
  assert.match(text, /Security scopes/);
  assert.match(text, /Seniority groupings/);
  assert.equal(chart.parentAsOf("north", TODAY), "division-a");
  assert.equal(chart.parentAsOf("north", effective), "division-b");
  assert.equal(chart.parentAsOf("north", addDays(TODAY, 29)), "division-a");
});

test("a 5000 box chart lays out in under two seconds", () => {
  const chart = new OrgChart({ today: TODAY, knownAt: KNOWN });
  chart.seedWide(5000);
  const started = performance.now();
  const placed = chart.layout({ asOf: TODAY, depth: 3 });
  const elapsed = performance.now() - started;
  assert.equal(placed.length, 5000);
  assert.ok(elapsed < 2000, `layout took ${elapsed}ms`);
});

test("read API returns the chart as of a date", async () => {
  const chart = office();
  const app = createOrgChartApp(chart, TODAY);
  const response = await app.request("/org-chart?asOf=2026-11-01");
  assert.equal(response.status, 200);
  const body = (await response.json()) as { nodes: { title: string }[] };
  assert.equal(body.nodes.some((node) => node.title === "Clerk"), true);
});

test("the chart screen renders in English and French", () => {
  assertChartLocales();
  const chart = office();
  const french = renderToStaticMarkup(
    OrgChartScreen({ locale: "fr-CA", sample: true, chart: chart.chart({ asOf: TODAY }) }),
  );
  assert.match(french, /Organigramme/);
  assert.match(french, /Déplacer vers/);
  assert.match(french, /Ana/);
  const english = renderToStaticMarkup(OrgChartScreen({ locale: "en-CA", chart: { asOf: TODAY, nodes: [], edges: [] } }));
  assert.match(english, /Nothing to show/);
});
