import assert from "node:assert/strict";
import { renderToStaticMarkup } from "react-dom/server";
import { test } from "node:test";
import { createMemoryAuthAdmin } from "@candohr/access";
import type { RoleGrant } from "@candohr/access";
import { addDays, CanDoError } from "@candohr/shared";
import { CoreHr } from "../src/engine.ts";
import { createCoreApp } from "../src/http.ts";
import { assertCoreLocales } from "../src/i18n.ts";
import { PeopleList, PersonProfile, PositionList, PositionScreen } from "../src/screens.ts";
import { isValidSin } from "../src/sin.ts";

const NOW = "2026-11-01T15:00:00.000Z";
const TODAY = "2026-11-01";
const QUERY = { asOf: TODAY, knownAt: NOW };

function core(): CoreHr {
  return new CoreHr({ today: TODAY, knownAt: NOW, leadDays: 14 });
}

function office(hr: CoreHr, positionId = "pos-1", fte = "1.00"): void {
  hr.addLocation({ id: "loc-mb", province: "MB", name: "Winnipeg", minimumHourly: "16.00", wageSource: "rules/test-floor" });
  hr.addLocation({ id: "loc-on", province: "ON", name: "Toronto" });
  hr.addJob({ id: "job-1", title: "Clerk", bargainingUnit: "INSIDE" });
  hr.addAgreement({ id: "agr-inside", unitCode: "INSIDE", bridgeWithinDays: 90, challengeDays: 10 });
  hr.addPosition({ id: positionId, orgUnitId: "unit-1", jobId: "job-1", fteBudget: fte, title: "Clerk", managerUserId: "manager-1", mappedCostCentreId: "cc-mapped" });
}

const payroll: RoleGrant = {
  roleCode: "payroll_processor",
  scope: { type: "all" },
  permissions: [{ action: "reveal", fieldClass: "payroll_restricted", entity: "person" }],
};

test("SIN check digit accepts a valid number and rejects a bad one", () => {
  assert.equal(isValidSin("123456782"), true);
  assert.equal(isValidSin("123456789"), false);
});

test("CORE-001 hire fills the position, sets Manitoba tax, and blocks a rate under the floor", async () => {
  const hr = core();
  office(hr);
  const blocked = hr.hire({
    legalName: "Ana Lopez",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "15.00",
    rateBasis: "hourly",
    startDate: "2026-12-01",
  });
  assert.equal(blocked.ok, false);
  assert.equal(blocked.errors[0]?.code, "BELOW_MINIMUM_WAGE");
  assert.equal(blocked.errors[0]?.source, "rules/test-floor");
  assert.equal(hr.events.length, 0);
  assert.equal(hr.positionView("pos-1", { asOf: "2026-12-01", knownAt: NOW })?.status, "vacant");

  const hired = hr.hire({
    legalName: "Ana Lopez",
    preferredName: "Ana",
    email: "ana@example.com",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "20.00",
    rateBasis: "hourly",
    startDate: "2026-12-01",
  });
  assert.equal(hired.ok, true);
  assert.equal(hr.positionView("pos-1", { asOf: "2026-11-30", knownAt: NOW })?.status, "vacant");
  assert.equal(hr.positionView("pos-1", { asOf: "2026-12-01", knownAt: NOW })?.status, "filled");
  assert.ok(hr.events.some((event) => event.type === "employment.hired"));
  assert.ok(hr.events.some((event) => event.type === "position.changed"));
  assert.equal(hr.profile(hired.personId ?? "", { asOf: "2026-12-01", knownAt: NOW })?.taxProvince, "MB");
  assert.ok(hr.tasks.some((task) => task.code === "TD1MB"));
  assert.equal(await hr.runProvisioning("2026-11-16", createMemoryAuthAdmin()), 0);
  assert.equal(await hr.runProvisioning("2026-11-17", createMemoryAuthAdmin()), 1);
});

test("CORE-002 a second assignment keeps its own manager, agreement and rate, and only one primary", () => {
  const hr = core();
  office(hr);
  hr.addPosition({ id: "pos-2", orgUnitId: "unit-2", jobId: "job-1", fteBudget: "0.50", title: "Casual" });
  const hired = hr.hire({
    legalName: "Sam Roy",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
    managerAssignmentId: null,
    agreementId: "agr-inside",
  });
  assert.equal(hired.ok, true);
  const second = hr.addAssignment({
    personId: hired.personId,
    legalName: "Sam Roy",
    legalEntityId: "legal-1",
    positionId: "pos-2",
    fte: "0.40",
    locationId: "loc-on",
    rate: "22.00",
    rateBasis: "hourly",
    startDate: TODAY,
    assignmentType: "casual_pool",
    primary: false,
    agreementId: "agr-casual",
    managerAssignmentId: hired.assignmentId,
  });
  assert.equal(second.ok, true);
  const profile = hr.profile(hired.personId ?? "", QUERY);
  assert.equal(profile?.assignments.length, 2);
  assert.equal(profile?.assignments.filter((row) => row.primary).length, 1);
  const casual = profile?.assignments.find((row) => row.id === second.assignmentId);
  assert.equal(casual?.rate, "22.00");
  assert.equal(casual?.agreementId, "agr-casual");
  assert.equal(casual?.managerName, "Sam Roy");
  assert.equal(hr.governing(hired.personId ?? "", "benefits", QUERY).length, 2);
  assert.equal(hr.governing(hired.personId ?? "", "directory", QUERY).length, 1);
  assert.equal(hr.governanceTable().some((row) => row.domain === "benefits" && row.rule === "combined"), true);
});

test("CORE-003 rehire keeps the person and bridges service when the agreement says so", () => {
  const hr = core();
  office(hr);
  const hired = hr.hire({
    legalName: "Jo Kim",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: "2026-01-01",
  });
  assert.equal(hired.ok, true);
  const employmentId = hr.history("person", hired.personId ?? "")[1]?.label === "active" ? undefined : undefined;
  void employmentId;
  const employment = hr.history("person", hired.personId ?? "");
  assert.ok(employment.length > 0);
  hr.terminate({ employmentId: findEmployment(hr, hired.personId ?? ""), effectiveDate: "2026-02-01", managerUserId: "manager-1" });
  const again = hr.rehire({
    personId: hired.personId ?? "",
    legalEntityId: "legal-1",
    startDate: "2026-03-01",
    agreementId: "agr-inside",
    positionId: "pos-1",
    locationId: "loc-mb",
    rate: "40000.00",
  });
  assert.equal(again.ok, true);
  assert.equal(again.continuousServiceDate, "2026-01-01");
  assert.equal(hr.peopleList({ asOf: "2026-03-01", knownAt: NOW }).filter((row) => row.id === hired.personId).length, 1);
});

test("CORE-004 SIN is encrypted, masked, and revealed only with a reason", async () => {
  const hr = core();
  office(hr);
  const hired = hr.hire({
    legalName: "Pat Singh",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
  });
  assert.equal(hired.ok, true);
  const personId = hired.personId ?? "";
  assert.equal(await hr.setSin(personId, "123456782"), "*** *** 782");
  const profile = hr.profile(personId, QUERY);
  assert.equal(profile?.sinMasked, "*** *** 782");
  assert.equal(JSON.stringify(profile).includes("123456782"), false);
  await assert.rejects(() => hr.setSin(personId, "123456789"), (error: unknown) => error instanceof CanDoError && error.code === "SIN_INVALID");
  assert.equal(await hr.revealPersonSin(personId, "year-end", [payroll]), "123456782");
  assert.equal(hr.audits[0]?.action, "sensitive.reveal");
  assert.equal(hr.audits[0]?.reason, "year-end");
});

test("CORE-010 a position over the remaining budget warns and routes to finance", () => {
  const hr = core();
  const over = hr.proposePosition({ orgUnitId: "unit-1", midpoint: "80000.00", burden: "20000.00", remainingAnnual: "90000.00" });
  assert.equal(over.warnings[0]?.code, "OVER_BUDGET");
  assert.equal(over.approvals[0]?.role, "finance");
  const under = hr.proposePosition({ orgUnitId: "unit-1", midpoint: "10000.00", burden: "1000.00", remainingAnnual: "90000.00" });
  assert.equal(under.warnings.length, 0);
});

test("CORE-011 a second full-time holder is blocked unless the overlap is approved", () => {
  const hr = core();
  office(hr);
  const first = hr.hire({
    legalName: "First",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
  });
  assert.equal(first.ok, true);
  const blocked = hr.hire({
    legalName: "Second",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
  });
  assert.equal(blocked.errors[0]?.code, "OVER_FTE");
  const overlap = hr.hire({
    legalName: "Second",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
    assignmentType: "overlap",
    endDate: "2026-12-01",
    overlapApproved: true,
  });
  assert.equal(overlap.ok, true);
});

test("CORE-012 leaving makes the position vacant and asks the manager about backfill", () => {
  const hr = core();
  office(hr);
  const hired = hr.hire({
    legalName: "Casey",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: "2026-01-01",
  });
  hr.terminate({ employmentId: findEmployment(hr, hired.personId ?? ""), effectiveDate: "2026-11-15", managerUserId: "manager-1" });
  assert.equal(hr.positionView("pos-1", { asOf: "2026-11-14", knownAt: NOW })?.status, "filled");
  assert.equal(hr.positionView("pos-1", { asOf: "2026-11-15", knownAt: NOW })?.status, "vacant");
  assert.ok(hr.events.some((event) => event.type === "position.vacated" && event.effectiveDate === "2026-11-15"));
  const task = hr.tasks.find((item) => item.code === "backfill");
  assert.deepEqual(task?.choices, ["backfill", "modify", "eliminate"]);
  assert.equal(task?.assigneeUserId, "manager-1");
});

test("CORE-013 moving a unit is one operation and does not rewrite assignment rows", () => {
  const hr = core();
  hr.addLocation({ id: "loc-mb", province: "MB" });
  hr.addLevelType({ code: "CORP", allowedParentCodes: [] });
  hr.addLevelType({ code: "CLUSTER", allowedParentCodes: ["CORP"] });
  hr.addLevelType({ code: "DIVISION", allowedParentCodes: ["CORP", "CLUSTER"] });
  hr.addLevelType({ code: "SECTION", allowedParentCodes: ["DIVISION", "CLUSTER"] });
  assert.equal(hr.addOrgNode({ id: "corp", hierarchyId: "management", levelCode: "CORP", parentId: null, name: "City", effectiveDate: "2020-01-01" }), null);
  assert.equal(hr.addOrgNode({ id: "cluster", hierarchyId: "management", levelCode: "CLUSTER", parentId: "corp", name: "Cluster", effectiveDate: "2020-01-01" }), null);
  assert.equal(hr.addOrgNode({ id: "division", hierarchyId: "management", levelCode: "DIVISION", parentId: "corp", name: "Division", effectiveDate: "2020-01-01" }), null);
  assert.equal(hr.addOrgNode({ id: "section", hierarchyId: "management", levelCode: "SECTION", parentId: "division", name: "Section", effectiveDate: "2020-01-01" }), null);
  hr.seedHolders({ orgUnitId: "section", count: 3000, locationId: "loc-mb" });
  const before = hr.assignmentCount();
  const chainBefore = hr.reportingChain("person-section-0", QUERY);
  assert.deepEqual(chainBefore, ["section", "division", "corp"]);
  const movesBefore = hr.operations.filter((row) => row.op === "org_unit.move").length;
  assert.equal(hr.moveOrgUnit({ id: "section", newParentId: "cluster", effectiveDate: TODAY }), null);
  assert.equal(hr.assignmentCount(), before);
  assert.equal(hr.operations.filter((row) => row.op === "org_unit.move").length, movesBefore + 1);
  assert.deepEqual(hr.reportingChain("person-section-0", QUERY), ["section", "cluster", "corp"]);
});

test("CORE-014 switching on position mode keeps the same reporting lines", () => {
  const hr = core();
  hr.addLocation({ id: "loc-mb", province: "MB" });
  hr.mode = "light";
  hr.seedHolders({ orgUnitId: "unit-1", count: 2, locationId: "loc-mb" });
  hr.linkManager("assignment-person-unit-1-1", "assignment-person-unit-1-0");
  const { before, after } = hr.enablePositionMode();
  assert.deepEqual(after.sort(), before.sort());
  assert.equal(hr.mode, "position");
});

test("CORE-030 the agreement follows the bargaining unit, and an exclusion needs a reason", () => {
  const hr = core();
  office(hr);
  const hired = hr.hire({
    legalName: "Riley",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
  });
  assert.equal(hr.profile(hired.personId ?? "", QUERY)?.assignments[0]?.agreementId, "agr-inside");
  const excluded = hr.hire({
    legalName: "Other",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "0.20",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
    excluded: true,
  });
  assert.equal(excluded.errors.some((error) => error.code === "AGREEMENT_EXCLUSION_REASON"), true);
});

test("CORE-031 seniority ties break on hire date and then lot, and the list records the challenge end", () => {
  const hr = core();
  hr.addAgreement({ id: "agr-inside", unitCode: "INSIDE", challengeDays: 14 });
  const published = hr.publishSeniority({
    agreementId: "agr-inside",
    postingDate: "2026-11-01",
    rows: [
      { personId: "b", seniorityDate: "2020-01-01", hireDate: "2019-05-01", lot: "2" },
      { personId: "a", seniorityDate: "2020-01-01", hireDate: "2019-05-01", lot: "1" },
      { personId: "c", seniorityDate: "2019-01-01", hireDate: "2018-01-01", lot: "9" },
    ],
  });
  assert.deepEqual(published.order, ["c", "a", "b"]);
  assert.equal(published.challengeEnds, "2026-11-15");
  assert.equal(hr.publishedLists[0]?.postingDate, "2026-11-01");
});

test("CORE-040 moving house asks about the work location and does not change tax province by itself", () => {
  const hr = core();
  office(hr);
  const hired = hr.hire({
    legalName: "Noor",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
  });
  const personId = hired.personId ?? "";
  hr.setAddress({ personId, province: "MB" });
  const asked = hr.setAddress({ personId, province: "ON" });
  assert.equal(asked.askWorkLocation, true);
  assert.equal(asked.taxProvince, "MB");
  const moved = hr.setAddress({ personId, province: "QC", workLocationChanged: true, newLocationId: "loc-on" });
  assert.equal(moved.taxProvince, "ON");
  const override = hr.setAddress({ personId, province: "ON", hrOverride: { province: "MB", reason: "lives in Ontario, works in Manitoba" } });
  assert.equal(override.taxProvince, "MB");
});

test("CORE-041 a legal name waits for a document and HR, and a preferred name is immediate", () => {
  const hr = core();
  office(hr);
  const hired = hr.hire({
    legalName: "Alex Martin",
    preferredName: "Alex",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: TODAY,
  });
  const personId = hired.personId ?? "";
  hr.setPreferredName(personId, "Al");
  assert.equal(hr.profile(personId, QUERY)?.preferredName, "Al");
  assert.equal(hr.profile(personId, QUERY)?.legalName, "Alex Martin");
  assert.equal(hr.requestLegalName({ personId, legalName: "Alexandra Martin" })?.code, "LEGAL_NAME_EVIDENCE");
  assert.equal(hr.requestLegalName({ personId, legalName: "Alexandra Martin", documentId: "doc-1" }), null);
  assert.equal(hr.profile(personId, QUERY)?.legalName, "Alex Martin");
  assert.equal(hr.approvals.some((row) => row.role === "hr"), true);
  hr.approveLegalName(personId);
  assert.equal(hr.profile(personId, QUERY)?.legalName, "Alexandra Martin");
});

test("ENT-001 a section can sit under a cluster only when the level allows it", () => {
  const hr = core();
  hr.addLevelType({ code: "CORP", allowedParentCodes: [] });
  hr.addLevelType({ code: "CLUSTER", allowedParentCodes: ["CORP"] });
  hr.addLevelType({ code: "SECTION", allowedParentCodes: ["DIVISION"] });
  hr.addOrgNode({ id: "corp", hierarchyId: "management", levelCode: "CORP", parentId: null, name: "City", effectiveDate: "2020-01-01" });
  hr.addOrgNode({ id: "cluster", hierarchyId: "management", levelCode: "CLUSTER", parentId: "corp", name: "Cluster", effectiveDate: "2020-01-01" });
  assert.equal(
    hr.addOrgNode({ id: "section", hierarchyId: "management", levelCode: "SECTION", parentId: "cluster", name: "Section", effectiveDate: "2020-01-01" })?.code,
    "LEVEL_NOT_ALLOWED",
  );
  hr.addLevelType({ code: "SECTION", allowedParentCodes: ["CLUSTER"] });
  assert.equal(
    hr.addOrgNode({ id: "section", hierarchyId: "management", levelCode: "SECTION", parentId: "cluster", name: "Section", effectiveDate: "2020-01-01" }),
    null,
  );
});

test("ENT-002 a cost centre override needs a reason and applies from its date", () => {
  const hr = core();
  office(hr);
  assert.equal(hr.overrideCostCentre({ positionId: "pos-1", costCentreId: "cc-new", effectiveDate: TODAY })?.code, "COST_CENTRE_REASON");
  assert.equal(hr.overrideCostCentre({ positionId: "pos-1", costCentreId: "cc-new", reason: "grant", effectiveDate: "2026-12-01" }), null);
  assert.equal(hr.glCostCentre("pos-1", "2026-11-01", NOW), "cc-mapped");
  assert.equal(hr.glCostCentre("pos-1", "2026-12-01", NOW), "cc-new");
});

test("ENT-003 the subtree as of a past date and a future date comes from the closure table", async () => {
  const hr = core();
  hr.addLevelType({ code: "DIVISION", allowedParentCodes: [] });
  hr.addLevelType({ code: "UNIT", allowedParentCodes: ["DIVISION"] });
  hr.addOrgNode({ id: "recreation", hierarchyId: "management", levelCode: "DIVISION", parentId: null, name: "Recreation", effectiveDate: "2020-01-01" });
  hr.addOrgNode({ id: "pool", hierarchyId: "management", levelCode: "UNIT", parentId: "recreation", name: "Pool", effectiveDate: "2020-01-01" });
  hr.addOrgNode({ id: "arena", hierarchyId: "management", levelCode: "UNIT", parentId: "recreation", name: "Arena", effectiveDate: "2026-12-01" });
  const past = hr.subtree("recreation", { asOf: "2026-06-01", knownAt: NOW }).sort();
  const future = hr.subtree("recreation", { asOf: "2027-01-01", knownAt: NOW }).sort();
  assert.deepEqual(past, ["pool"]);
  assert.deepEqual(future, ["arena", "pool"]);
  const app = createCoreApp(hr, NOW);
  const response = await app.request("/org/recreation/subtree?asOf=2026-06-01&knownAt=" + NOW);
  assert.equal(response.status, 200);
  const body = (await response.json()) as { items: string[] };
  assert.deepEqual(body.items.sort(), ["pool"]);
});

test("ENT-011 an acting assignment suspends the home job and the home job returns on the end date", () => {
  const hr = core();
  office(hr);
  hr.addPosition({ id: "pos-acting", orgUnitId: "unit-2", fteBudget: "1.00", title: "Lead", mappedCostCentreId: "cc-home" });
  const hired = hr.hire({
    legalName: "Jordan",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: "2026-01-01",
  });
  const end = addDays("2026-11-02", 70);
  const acting = hr.startActing({
    homeAssignmentId: hired.assignmentId ?? "",
    positionId: "pos-acting",
    rate: "40.00",
    costCentreId: "cc-acting",
    startDate: "2026-11-02",
    endDate: end,
  });
  const during = hr.profile(hired.personId ?? "", { asOf: "2026-12-01", knownAt: NOW });
  const home = during?.assignments.find((row) => row.id === hired.assignmentId);
  const cover = during?.assignments.find((row) => row.id === acting.actingAssignmentId);
  assert.equal(home?.status, "suspended_for_acting");
  assert.equal(cover?.status, "active");
  assert.equal(cover?.rate, "40.00");
  assert.equal(cover?.costCentreId, "cc-acting");
  const after = hr.profile(hired.personId ?? "", { asOf: end, knownAt: NOW });
  assert.equal(after?.assignments.find((row) => row.id === hired.assignmentId)?.status, "active");
  assert.equal(after?.assignments.find((row) => row.id === acting.actingAssignmentId)?.status, "ended");
});

test("read APIs honour asOf and knownAt and return history", async () => {
  const hr = core();
  office(hr);
  const hired = hr.hire({
    legalName: "History",
    legalEntityId: "legal-1",
    positionId: "pos-1",
    fte: "1.00",
    locationId: "loc-mb",
    rate: "30.00",
    rateBasis: "hourly",
    startDate: "2026-12-01",
  });
  const app = createCoreApp(hr, NOW);
  const later = await app.request(`/positions/pos-1?asOf=2026-12-01&knownAt=${NOW}`);
  assert.equal(later.status, 200);
  assert.equal(((await later.json()) as { status: string }).status, "filled");
  const earlier = await app.request("/positions/pos-1?asOf=2026-11-01&knownAt=" + NOW);
  assert.equal(((await earlier.json()) as { status: string }).status, "vacant");
  const history = await app.request(`/people/${hired.personId}/history`);
  assert.equal(history.status, 200);
  const missing = await app.request("/people/missing");
  assert.equal(missing.status, 404);
});

test("people, profile and position screens render in English and French", () => {
  assertCoreLocales();
  const people = renderToStaticMarkup(
    PeopleList({
      locale: "fr-CA",
      sample: true,
      people: [{ id: "p1", preferredName: "Ana", title: "Clerk", orgUnitName: "Recreation" }],
    }),
  );
  assert.match(people, /Personnes/);
  assert.match(people, /exemples/);
  assert.match(people, /Ana/);
  const empty = renderToStaticMarkup(PeopleList({ locale: "en-CA", people: [] }));
  assert.match(empty, /No people to show/);
  const profile = renderToStaticMarkup(
    PersonProfile({
      locale: "fr-CA",
      tab: "job",
      profile: {
        id: "p1",
        legalName: "Ana Lopez",
        preferredName: "Ana",
        sinMasked: null,
        taxProvince: "MB",
        askWorkLocation: false,
        assignments: [
          {
            id: "a1",
            type: "regular",
            status: "active",
            primary: true,
            fte: "1.00",
            rate: "20.00",
            agreementId: "agr-inside",
            managerName: "Sam",
            orgUnitName: "Recreation",
            costCentreId: null,
          },
        ],
        history: [{ label: "active", date: "2026-01-01" }],
      },
    }),
  );
  assert.match(profile, /Poste et affectations/);
  assert.match(profile, /Gestionnaire/);
  const position = renderToStaticMarkup(
    PositionScreen({
      locale: "en-CA",
      position: { id: "pos-1", title: "Clerk", status: "vacant", fteBudget: "1.00", holderName: null, orgUnitName: "Recreation" },
    }),
  );
  assert.match(position, /Vacant/);
  assert.match(position, /FTE/);
  const positions = renderToStaticMarkup(PositionList({ locale: "fr-CA", sample: true, positions: [] }));
  assert.match(positions, /Postes/);
  assert.match(positions, /Aucun poste/);
});

function findEmployment(hr: CoreHr, personId: string): string {
  const history = hr.history("person", personId);
  assert.ok(history.length > 0);
  const profile = hr.profile(personId, { asOf: "2026-01-15", knownAt: NOW });
  const id = profile?.assignments[0]?.id;
  assert.ok(id);
  const employmentId = (hr as unknown as { employments: { id: string; personId: string }[] }).employments?.find((row) => row.personId === personId)?.id;
  if (employmentId) return employmentId;
  throw new Error("employment not visible");
}
