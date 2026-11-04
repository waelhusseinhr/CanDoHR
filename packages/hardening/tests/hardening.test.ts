import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { isValidSin } from "@candohr/core";
import { bucketCountFor } from "@candohr/pay-runs";
import {
  assertScreenLanguages,
  buildDemoTenants,
  checkScreens,
  demoCatalogue,
  disasterRecoveryStatus,
  performanceStatus,
  runPlatformGuards,
  sameResultAcrossConsumers,
  securityStatus,
  syntheticSubjects,
  tamperDrill,
  SUBJECT_COUNT,
} from "../src/index.ts";

const root = fileURLToPath(new URL("../../../", import.meta.url));

test("50,000 subjects in 100 buckets keep one result_sha256 for 1, 4 and 16 partitions", () => {
  const subjects = syntheticSubjects(SUBJECT_COUNT);
  assert.equal(subjects.length, 50000);
  assert.equal(bucketCountFor(subjects.length), 100);
  const check = sameResultAcrossConsumers(subjects, [1, 4, 16]);
  assert.equal(check.buckets, 100);
  assert.equal(check.hashes.length, 3);
  assert.equal(check.identical, true);
  const first = check.hashes[0];
  assert.equal(typeof first, "string");
  assert.equal(first?.length, 64);
  const status = performanceStatus();
  assert.equal(status.k6, "NOT_RUN");
  assert.equal(status.payrollCalculate50k, "NOT_RUN");
  assert.equal(status.computeSize, null);
  assert.equal(status.apiP95Ms, null);
  assert.equal(status.canadianClient, false);
});

test("tamper drill names an edit, a delete, and a reorder, and the other batch still verifies", () => {
  const drill = tamperDrill();
  assert.equal(drill.clean, true);
  assert.equal(drill.arrayReorderStillVerifies, true);
  assert.equal(drill.stagingCopy, false);
  assert.equal(drill.edit.reason, "LEAF");
  assert.equal(drill.edit.auditId, 2);
  assert.equal(drill.edit.batchNo, 1);
  assert.equal(drill.delete.reason, "LEAF_COUNT");
  assert.equal(drill.delete.batchNo, 1);
  assert.equal(drill.reorder.reason, "AUDIT_ID_GAP");
  assert.equal(drill.reorder.auditId, 9);
  assert.equal(drill.reorder.batchNo, 1);
  assert.equal(drill.otherBatchCleanAfterEdit, true);
});

test("i18n completeness and the sample screens", () => {
  assertScreenLanguages();
  const screens = checkScreens(root);
  assert.deepEqual(screens.routes, [
    "/",
    "/org-chart",
    "/people",
    "/people/:personId",
    "/positions",
    "/positions/:positionId",
  ]);
  assert.deepEqual(screens.findings, []);
  assert.equal(screens.axe, "NOT_RUN");
  assert.equal(screens.documentLang, "en-CA");
});

test("platform guards and the security checks that were not run", () => {
  const guards = runPlatformGuards(root);
  assert.equal(guards.ok, true);
  const security = securityStatus(guards.ok);
  assert.equal(security.platformGuards, "PASS");
  assert.equal(security.codeql, "NOT_CONFIGURED");
  assert.equal(security.dependabot, "NOT_CONFIGURED");
  assert.equal(security.secretScanningPushProtection, "NOT_IN_REPO");
  assert.equal(security.zapBaseline, "NOT_RUN");
  assert.equal(security.annualPenTest, "NOT_RUN");
  const recovery = disasterRecoveryStatus();
  assert.equal(recovery.status, "NOT_RUN");
  assert.equal(recovery.region, "ca-west-1");
  assert.equal(recovery.restoreSeconds, null);
});

test("Northern Lights, Example Municipality, and Example First Nation stay in memory", () => {
  const tenants = buildDemoTenants();
  assert.equal(tenants.length, 3);
  const catalogue = JSON.parse(readFileSync(`${root}/supabase/seeds/demo/catalogue.json`, "utf8")) as {
    loadedIntoDatabase: boolean;
    tenants: { code: string; employees: number }[];
  };
  assert.equal(catalogue.loadedIntoDatabase, false);
  const summary = demoCatalogue();
  assert.equal(summary.length, 3);
  for (const row of summary) assert.equal(row.loadedIntoDatabase, false);

  const northern = tenants.find((tenant) => tenant.code === "northern-lights");
  const city = tenants.find((tenant) => tenant.code === "example-municipality");
  const nation = tenants.find((tenant) => tenant.code === "example-first-nation");
  if (!northern || !city || !nation) throw new Error("DEMO_TENANT");

  assert.equal(northern.name, "Northern Lights Non-Profit");
  assert.equal(northern.people.length, 60);
  assert.equal(northern.lightOrgMode, false);
  assert.equal(northern.positionsRequired, true);
  const provinces = new Set(northern.people.map((person) => person.assignments[0]?.workLocation));
  assert.equal(provinces.has("AB"), true);
  assert.equal(provinces.has("BC"), true);
  for (const person of northern.people) {
    for (const job of person.assignments) {
      if (job.funding !== "grant") throw new Error("DEMO_GRANT");
      if (!job.positionId) throw new Error("DEMO_POSITION");
    }
  }

  assert.equal(city.name, "Example Municipality");
  assert.equal(city.people.length, 2400);
  assert.equal(city.jurisdiction, "ON");
  const agreements = new Set<string>();
  const roots = new Set<string>();
  let several = 0;
  let platoon = 0;
  for (const person of city.people) {
    if (person.assignments.length > 1) several += 1;
    for (const job of person.assignments) {
      if (job.agreementCode) agreements.add(job.agreementCode);
      const top = job.orgUnitPath.split("/")[0];
      if (top) roots.add(top);
      if (job.schedule === "platoon") platoon += 1;
      if (job.pensionStyle !== "omers_style") throw new Error("DEMO_PENSION");
      if (job.jurisdiction !== "ON") throw new Error("DEMO_JURISDICTION");
    }
  }
  assert.equal(agreements.has("example"), true);
  assert.equal(agreements.size, 4);
  assert.equal(roots.size >= 3, true);
  assert.equal(several > 0, true);
  assert.equal(platoon > 0, true);

  assert.equal(nation.name, "Example First Nation");
  assert.equal(nation.people.length, 180);
  assert.equal(nation.jurisdiction, "federal");
  let onReserve = 0;
  let offReserve = 0;
  for (const person of nation.people) {
    for (const job of person.assignments) {
      if (job.jurisdiction !== "federal") throw new Error("DEMO_FEDERAL");
      if (job.onReserve === true) {
        onReserve += 1;
        if (job.section87 !== true) throw new Error("DEMO_S87");
        if (job.workLocation !== "MB-on-reserve") throw new Error("DEMO_RESERVE");
      } else {
        offReserve += 1;
        if (job.section87 !== false) throw new Error("DEMO_S87");
        if (job.workLocation !== "MB-off-reserve") throw new Error("DEMO_RESERVE");
      }
    }
  }
  assert.equal(onReserve + offReserve, 180);

  const seen = new Set<string>();
  for (const tenant of tenants) {
    for (const person of tenant.people) {
      if (person.sinLabel !== "TEST_DATA") throw new Error("DEMO_SIN_LABEL");
      if (!person.displayName.startsWith("Fictional ")) throw new Error("DEMO_NAME");
      if (!isValidSin(person.testSin)) throw new Error("DEMO_SIN");
      if (!person.testSin.startsWith("8")) throw new Error("DEMO_SIN");
      if (seen.has(person.testSin)) throw new Error("DEMO_SIN_DUP");
      seen.add(person.testSin);
    }
  }

  const listed = new Map(catalogue.tenants.map((tenant) => [tenant.code, tenant.employees]));
  for (const tenant of tenants) {
    if (listed.get(tenant.code) !== tenant.people.length) throw new Error("DEMO_CATALOGUE");
  }
});
