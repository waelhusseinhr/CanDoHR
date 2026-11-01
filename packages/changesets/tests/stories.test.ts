import assert from "node:assert/strict";
import { test } from "node:test";
import { CanDoError } from "@candohr/shared";
import { transferOverBudgetRoute } from "../src/approval.ts";
import { runCascade, type CascadeRule } from "../src/cascade.ts";
import { commitOperations, visibleRow } from "../src/commit.ts";
import { customerDigest, digestStillInChain, MemoryAnchorStore, type SealBatch } from "../src/digest.ts";
import { MemoryOutboxStore, OutboxRelay, WebhookQueue, type Subscriber } from "../src/outbox.ts";
import { ChangeSetService } from "../src/service.ts";
import { SessionHub } from "../src/session.ts";
import type { ApprovalDirectory, ApprovalRoute, World } from "../src/types.ts";
import { addAssignment, addEmployment, addLocation, addPosition, addProfile, emptyWorld } from "../src/world.ts";

const TENANT = "11111111-1111-1111-1111-111111111111";
const USER = "22222222-2222-2222-2222-222222222222";
const HR = "33333333-3333-3333-3333-333333333333";
const FINANCE = "44444444-4444-4444-4444-444444444444";
const NEXT = "55555555-5555-5555-5555-555555555555";
const DELEGATE = "66666666-6666-6666-6666-666666666666";
const NOW = "2026-11-01T15:00:00.000Z";
const TODAY = "2026-11-01";
const RECORDED = "2020-01-01T00:00:00.000Z";

function service(world: World, extra?: { routes?: ApprovalRoute[]; directory?: ApprovalDirectory; today?: string }): ChangeSetService {
  return new ChangeSetService(world, {
    tenantId: TENANT,
    today: extra?.today ?? TODAY,
    now: () => NOW,
    routes: extra?.routes,
    directory: extra?.directory,
  });
}

function snapshot(world: World): string {
  return JSON.stringify(world);
}

test("PLAT-001 validate returns errors, warnings, and consequences and writes nothing", () => {
  const world = emptyWorld();
  const assignmentId = "aaaaaaaa-0000-0000-0000-000000000001";
  addAssignment(world, {
    id: assignmentId,
    employmentId: "employment-1",
    personId: "person-1",
    positionId: "position-1",
    orgUnitId: "unit-a",
    validStart: "2026-01-01",
    recordedAt: RECORDED,
  });
  const books = service(world);
  const before = snapshot(books.books);
  const created = books.create(
    {
      kind: "transfer",
      reasonCode: "REORG",
      effectiveDate: TODAY,
      operations: [{ op: "assignment.update", assignmentId, set: { orgUnitId: "unit-b" } }],
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const validated = books.validate(created.body.changeSetId);
  assert.equal(validated.ok, true);
  if (!validated.ok) return;
  assert.ok(Array.isArray(validated.body.errors));
  assert.ok(Array.isArray(validated.body.warnings));
  assert.ok(Array.isArray(validated.body.consequences));
  assert.equal(validated.body.errors.length, 0);
  assert.equal(snapshot(books.books), before);
});

test("PLAT-001 a frozen position returns POSITION_FROZEN", () => {
  const world = emptyWorld();
  const positionId = "bbbbbbbb-0000-0000-0000-000000000001";
  const assignmentId = "aaaaaaaa-0000-0000-0000-000000000002";
  addPosition(world, { id: positionId, status: "frozen", orgUnitId: "unit-a" });
  addAssignment(world, {
    id: assignmentId,
    employmentId: "employment-1",
    personId: "person-1",
    positionId,
    orgUnitId: "unit-a",
    validStart: "2026-01-01",
    recordedAt: RECORDED,
  });
  const books = service(world);
  const created = books.create(
    {
      kind: "transfer",
      reasonCode: "REORG",
      effectiveDate: TODAY,
      operations: [{ op: "assignment.update", assignmentId, set: { orgUnitId: "unit-b" } }],
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const validated = books.validate(created.body.changeSetId);
  assert.equal(validated.ok, true);
  if (!validated.ok) return;
  assert.ok(validated.body.errors.some((error) => error.code === "POSITION_FROZEN"));
  assert.equal(books.books.audits.length, 0);
});

test("PLAT-001 submit of a stale version returns 409 VERSION_CONFLICT and the current state", () => {
  const world = emptyWorld();
  const assignmentId = "aaaaaaaa-0000-0000-0000-000000000003";
  addAssignment(world, {
    id: assignmentId,
    version: 8,
    employmentId: "employment-1",
    personId: "person-1",
    positionId: null,
    orgUnitId: "unit-a",
    validStart: "2026-01-01",
    recordedAt: RECORDED,
  });
  const books = service(world);
  const created = books.create(
    {
      kind: "transfer",
      reasonCode: "REORG",
      effectiveDate: TODAY,
      operations: [{ op: "assignment.update", targetId: assignmentId, set: { orgUnitId: "unit-b" } }],
      baseVersions: { [`assignment:${assignmentId}`]: 7 },
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const submitted = books.submit(created.body.changeSetId, {});
  assert.equal(submitted.ok, false);
  if (submitted.ok) return;
  assert.equal(submitted.status, 409);
  assert.equal(submitted.code, "VERSION_CONFLICT");
  assert.equal(submitted.current?.[`assignment:${assignmentId}`], 8);
  assert.equal(books.books.audits.length, 0);
});

test("PLAT-002 a failing third operation writes no versions, audits, or outbox events", () => {
  const world = emptyWorld();
  const first = "aaaaaaaa-0000-0000-0000-000000000011";
  const second = "aaaaaaaa-0000-0000-0000-000000000012";
  for (const id of [first, second]) {
    addAssignment(world, {
      id,
      employmentId: "employment-1",
      personId: "person-1",
      positionId: null,
      orgUnitId: "unit-a",
      validStart: TODAY,
      recordedAt: RECORDED,
    });
  }
  const before = snapshot(world);
  const result = commitOperations({
    world,
    operations: [
      { op: "assignment.update", assignmentId: first, set: { orgUnitId: "unit-b" } },
      { op: "assignment.update", assignmentId: second, set: { orgUnitId: "unit-c" } },
      { op: "assignment.update", assignmentId: "aaaaaaaa-0000-0000-0000-000000000099", set: { orgUnitId: "unit-d" } },
    ],
    changeSetId: "cccccccc-0000-0000-0000-000000000001",
    tenantId: TENANT,
    actorId: USER,
    effectiveDate: TODAY,
    knownAt: NOW,
    isCorrection: false,
    choiceMissing: false,
    today: TODAY,
  });
  assert.equal(result.error?.code, "ASSIGNMENT_UNKNOWN");
  assert.equal(snapshot(result.world), before);
  assert.equal(result.audits.length, 0);
  assert.equal(result.outbox.length, 0);
  assert.equal(world.audits.length, 0);
});

test("PLAT-002 a successful commit writes versions, one audit per operation, and one event per subject", () => {
  const world = emptyWorld();
  const ids = [
    "aaaaaaaa-0000-0000-0000-000000000021",
    "aaaaaaaa-0000-0000-0000-000000000022",
    "aaaaaaaa-0000-0000-0000-000000000023",
  ];
  for (const id of ids) {
    addAssignment(world, {
      id,
      employmentId: "employment-1",
      personId: "person-1",
      positionId: null,
      orgUnitId: "unit-a",
      validStart: TODAY,
      recordedAt: RECORDED,
    });
  }
  const changeSetId = "cccccccc-0000-0000-0000-000000000002";
  const result = commitOperations({
    world,
    operations: ids.map((assignmentId) => ({ op: "assignment.update", assignmentId, set: { orgUnitId: "unit-b" } })),
    changeSetId,
    tenantId: TENANT,
    actorId: USER,
    effectiveDate: TODAY,
    knownAt: NOW,
    isCorrection: false,
    choiceMissing: false,
    today: TODAY,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.audits.length, 3);
  assert.equal(result.outbox.length, 3);
  for (const id of ids) {
    const rows = result.world.assignments[id]?.versions ?? [];
    const opened = rows.filter((row) => row.supersededAt === null);
    const closed = rows.filter((row) => row.supersededAt !== null);
    assert.equal(opened.length, 1);
    assert.equal(opened[0]?.changeSetId, changeSetId);
    assert.ok(closed.length >= 1);
    assert.ok(closed.every((row) => row.supersededAt !== null));
  }
});

test("PLAT-003 a past date must choose new change or correction", () => {
  const world = seededPast();
  const books = service(world);
  const created = books.create(
    {
      kind: "data_change",
      reasonCode: "FIX",
      effectiveDate: "2026-04-01",
      operations: [{ op: "compensation.set_rate", assignmentId: pastAssignment, set: { rate: "72000.00" } }],
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const validated = books.validate(created.body.changeSetId);
  assert.equal(validated.ok, true);
  if (!validated.ok) return;
  assert.ok(validated.body.errors.some((error) => error.code === "MUST_CHOOSE_CHANGE_OR_CORRECTION"));
});

test("PLAT-003 a correction keeps the old row readable and the same valid time", () => {
  const world = seededPast();
  const books = service(world);
  const created = books.create(
    {
      kind: "data_change",
      reasonCode: "FIX",
      effectiveDate: "2026-04-01",
      isCorrection: true,
      operations: [{ op: "compensation.set_rate", assignmentId: pastAssignment, set: { rate: "72000.00" } }],
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const submitted = books.submit(created.body.changeSetId, { isCorrection: true });
  assert.equal(submitted.ok, true);
  if (!submitted.ok) return;
  const versions = books.books.assignments[pastAssignment]?.versions ?? [];
  const before = visibleRow(versions, pastAssignment, "2026-06-01", "2026-11-01T14:00:00.000Z");
  const after = visibleRow(versions, pastAssignment, "2026-06-01", NOW);
  assert.equal(before?.attributes.rate, "27000.00");
  assert.equal(after?.attributes.rate, "72000.00");
  assert.equal(after?.validStart, before?.validStart);
  assert.equal(after?.validEnd, before?.validEnd);
  assert.equal(JSON.stringify(books.books.outbox).includes("72000"), false);
});

test("PLAT-004 a transfer keeps a future raise, carries the new org unit, and does not warn", () => {
  const world = emptyWorld();
  const assignmentId = "aaaaaaaa-0000-0000-0000-000000000031";
  addAssignment(world, {
    id: assignmentId,
    employmentId: "employment-1",
    personId: "person-1",
    positionId: null,
    orgUnitId: "unit-old",
    rate: "50000.00",
    validStart: "2026-01-01",
    validEnd: "2027-01-01",
    recordedAt: RECORDED,
    explicitKeys: ["orgUnitId", "rate"],
    later: [
      {
        validStart: "2027-01-01",
        attributes: { orgUnitId: "unit-old", rate: "55000.00", status: "open", positionId: null, locationId: null },
        explicitKeys: ["rate"],
      },
    ],
  });
  const books = service(world);
  const created = books.create(
    {
      kind: "transfer",
      reasonCode: "REORG",
      effectiveDate: "2026-12-01",
      operations: [{ op: "assignment.update", assignmentId, set: { orgUnitId: "unit-new" } }],
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const validated = books.validate(created.body.changeSetId);
  assert.equal(validated.ok, true);
  if (!validated.ok) return;
  assert.equal(validated.body.warnings.length, 0);
  const submitted = books.submit(created.body.changeSetId, {});
  assert.equal(submitted.ok, true);
  if (!submitted.ok) return;
  assert.equal(submitted.body.status, "scheduled");
  const versions = books.books.assignments[assignmentId]?.versions ?? [];
  const january = visibleRow(versions, assignmentId, "2027-01-01", NOW);
  const december = visibleRow(versions, assignmentId, "2026-12-15", NOW);
  assert.equal(january?.attributes.rate, "55000.00");
  assert.equal(january?.attributes.orgUnitId, "unit-new");
  assert.equal(december?.attributes.orgUnitId, "unit-new");
  assert.equal(december?.attributes.rate, "50000.00");
});

test("PLAT-004 a different future rate warns FUTURE_CONFLICT and waits for keep, replace, or merge", () => {
  const world = futureRateWorld();
  const books = service(world);
  const created = books.create(
    {
      kind: "compensation",
      reasonCode: "MARKET",
      effectiveDate: "2026-12-01",
      operations: [{ op: "compensation.set_rate", assignmentId: futureAssignment, set: { rate: "60000.00" } }],
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const validated = books.validate(created.body.changeSetId);
  assert.equal(validated.ok, true);
  if (!validated.ok) return;
  assert.ok(validated.body.warnings.some((warning) => warning.code === "FUTURE_CONFLICT"));
  const blocked = books.submit(created.body.changeSetId, { acknowledgedWarnings: ["FUTURE_CONFLICT"] });
  assert.equal(blocked.ok, false);
  if (blocked.ok) return;
  assert.equal(blocked.code, "FUTURE_CONFLICT");
  const kept = books.submit(created.body.changeSetId, {
    acknowledgedWarnings: ["FUTURE_CONFLICT"],
    conflictResolution: "keep",
  });
  assert.equal(kept.ok, true);
  const versions = books.books.assignments[futureAssignment]?.versions ?? [];
  assert.equal(visibleRow(versions, futureAssignment, "2027-01-01", NOW)?.attributes.rate, "55000.00");
  assert.equal(visibleRow(versions, futureAssignment, "2026-12-15", NOW)?.attributes.rate, "60000.00");
});

test("PLAT-005 a transfer over $10,000 is approved by HR and then finance", () => {
  const { books, id } = approvalSet({
    hr: [HR],
    finance: [FINANCE],
  });
  const created = books.get(id);
  assert.equal(created.ok, true);
  if (!created.ok) return;
  assert.equal(created.body.status, "pending_approval");
  assert.deepEqual(
    created.body.approvals.map((step) => step.role),
    ["hrbp", "finance"],
  );
  assert.equal(created.body.approvals[0]?.step, 1);
  assert.equal(created.body.approvals[1]?.step, 2);
  const early = books.decide(id, FINANCE, { decision: "approve" });
  assert.equal(early.ok, false);
  const hr = books.decide(id, HR, { decision: "approve" });
  assert.equal(hr.ok, true);
  if (!hr.ok) return;
  assert.equal(hr.body.status, "pending_approval");
  const finance = books.decide(id, FINANCE, { decision: "approve" });
  assert.equal(finance.ok, true);
  if (!finance.ok) return;
  assert.equal(finance.body.status, "committed");
  assert.equal(books.books.audits.length > 0, true);
});

test("PLAT-005 the requester's own step is skipped and self-approval is blocked", () => {
  const { books, id } = approvalSet({ hr: [USER, HR], finance: [FINANCE] });
  const row = books.get(id);
  assert.equal(row.ok, true);
  if (!row.ok) return;
  assert.equal(row.body.approvals[0]?.assignee, HR);
  const self = books.decide(id, USER, { decision: "approve" });
  assert.equal(self.ok, false);
  if (self.ok) return;
  assert.equal(self.status, 403);
  assert.equal(self.code, "SELF_APPROVAL_BLOCKED");
});

test("PLAT-005 an approver on leave sends the task to the delegate and the audit names both", () => {
  const { books, id } = approvalSet({
    hr: [HR],
    finance: [FINANCE],
    leave: { [HR]: DELEGATE },
  });
  const row = books.get(id);
  assert.equal(row.ok, true);
  if (!row.ok) return;
  assert.equal(row.body.approvals[0]?.assignee, DELEGATE);
  assert.equal(row.body.approvals[0]?.principalUserId, HR);
  const named = row.body.activity.find((entry) => entry.action === "approval.delegated");
  assert.equal(named?.principalUserId, HR);
  assert.equal(named?.delegateUserId, DELEGATE);
  assert.equal(books.decide(id, HR, { decision: "approve" }).ok, false);
  assert.equal(books.decide(id, DELEGATE, { decision: "approve" }).ok, true);
});

test("ENT-007 a manager who is also the requester's subordinate cannot approve", () => {
  const { books, id } = approvalSet({
    hr: [HR, NEXT],
    finance: [FINANCE],
    subordinate: [HR, USER],
  });
  const row = books.get(id);
  assert.equal(row.ok, true);
  if (!row.ok) return;
  assert.equal(row.body.approvals[0]?.assignee, NEXT);
  assert.equal(books.decide(id, HR, { decision: "approve" }).ok, false);
  assert.equal(books.decide(id, NEXT, { decision: "approve" }).ok, true);
});

test("approval steps can also run in parallel", () => {
  const world = emptyWorld();
  const assignmentId = "aaaaaaaa-0000-0000-0000-000000000041";
  addAssignment(world, {
    id: assignmentId,
    employmentId: "employment-1",
    personId: "person-1",
    positionId: null,
    orgUnitId: "unit-a",
    validStart: TODAY,
    recordedAt: RECORDED,
  });
  const parallel: ApprovalRoute = {
    mode: "parallel",
    matches: (changeSet) => changeSet.kind === "policy",
    steps: [{ role: "hrbp" }, { role: "finance" }],
  };
  const books = service(world, {
    routes: [parallel],
    directory: directory({ hrbp: [HR], finance: [FINANCE] }),
  });
  const created = books.create(
    {
      kind: "policy",
      reasonCode: "POLICY",
      effectiveDate: TODAY,
      operations: [{ op: "assignment.update", assignmentId, set: { orgUnitId: "unit-b" } }],
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) return;
  const submitted = books.submit(created.body.changeSetId, {});
  assert.equal(submitted.ok, true);
  const financeFirst = books.decide(created.body.changeSetId, FINANCE, { decision: "approve" });
  assert.equal(financeFirst.ok, true);
  if (!financeFirst.ok) return;
  assert.equal(financeFirst.body.status, "pending_approval");
  const hr = books.decide(created.body.changeSetId, HR, { decision: "approve" });
  assert.equal(hr.ok, true);
  if (!hr.ok) return;
  assert.equal(hr.body.status, "committed");
});

test("cascade adds the end of each open assignment and stops, and a loop fails closed", () => {
  const world = emptyWorld();
  const employmentId = "eeeeeeee-0000-0000-0000-000000000001";
  const assignmentId = "aaaaaaaa-0000-0000-0000-000000000051";
  const positionId = "bbbbbbbb-0000-0000-0000-000000000051";
  addEmployment(world, { id: employmentId, personId: "person-1" });
  addPosition(world, { id: positionId, orgUnitId: "unit-a" });
  addAssignment(world, {
    id: assignmentId,
    employmentId,
    personId: "person-1",
    positionId,
    orgUnitId: "unit-a",
    validStart: "2026-01-01",
    recordedAt: RECORDED,
  });
  const outcome = runCascade(world, [{ op: "employment.terminate", employmentId }]);
  const added = outcome.operations.find((op) => op.op === "assignment.end");
  assert.ok(added?.addedByCascade);
  assert.ok(outcome.consequences.some((item) => item.addedOperation?.op === "assignment.end"));
  assert.equal(world.audits.length, 0);
  const loop: CascadeRule = {
    id: "loop",
    apply() {
      return {
        operations: [{ op: "assignment.update", targetId: crypto.randomUUID(), set: { orgUnitId: "x" } }],
        warnings: [],
        consequences: [],
      };
    },
  };
  assert.throws(
    () => runCascade(emptyWorld(), [{ op: "assignment.update", targetId: assignmentId, set: { orgUnitId: "y" } }], [loop]),
    (error: unknown) => error instanceof CanDoError && error.code === "CASCADE_DID_NOT_SETTLE",
  );
});

test("cascade updates tax province when the location changes and it was not overridden", () => {
  const world = emptyWorld();
  const assignmentId = "aaaaaaaa-0000-0000-0000-000000000061";
  addLocation(world, { id: "location-mb", province: "MB" });
  addProfile(world, { assignmentId, taxProvince: "ON" });
  const outcome = runCascade(world, [
    { op: "assignment.update", assignmentId, set: { locationId: "location-mb" } },
  ]);
  assert.ok(outcome.operations.some((op) => op.op === "payroll_profile.update" && op.set?.taxProvince === "MB"));
  assert.ok(outcome.consequences.some((item) => item.kind === "tax_province" && item.to === "MB"));
  addProfile(world, { assignmentId, taxProvince: "ON", overridden: true });
  const held = runCascade(world, [{ op: "assignment.update", assignmentId, set: { locationId: "location-mb" } }]);
  assert.equal(held.operations.some((op) => op.op === "payroll_profile.update"), false);
});

test("PLAT-016 the daily digest records the latest seal and a kept copy still sits in the chain", () => {
  const tenantId = TENANT;
  const batches: SealBatch[] = [
    batch(1, "hash-1", "hash-0", "2026-10-02T12:00:00.000Z"),
    batch(2, "hash-2", "hash-1", "2026-10-03T12:00:00.000Z"),
    batch(3, "hash-3", "hash-2", "2026-11-01T12:00:00.000Z"),
  ];
  const kept = customerDigest({ batches: batches.slice(0, 1), tenantId, now: "2026-10-02T12:15:00.000Z" });
  assert.equal(kept.digest.batchNo, 1);
  assert.equal(kept.digest.batchHash, "hash-1");
  assert.equal(kept.digest.signature, "sig-1");
  assert.equal(kept.digest.sentAt, "2026-10-02T12:15:00.000Z");
  const anchor = new MemoryAnchorStore();
  const today = customerDigest({
    batches,
    tenantId,
    now: "2026-11-01T12:15:00.000Z",
    dedicated: true,
    anchor,
  });
  assert.equal(today.digest.batchNo, 3);
  assert.equal(today.anchorWritten, true);
  assert.equal(anchor.get(tenantId)?.signature, "sig-3");
  assert.equal(digestStillInChain(kept.digest, batches), true);
});

test("PLAT-020 a subscriber that fails twice then succeeds applies the event once", () => {
  const store = new MemoryOutboxStore();
  store.add({
    eventId: "event-1",
    subjectKey: "assignment:1",
    type: "assignment.changed",
    payload: { eventId: "event-1", type: "assignment.changed" },
    createdAt: "2026-11-01T15:00:00.000Z",
  });
  let attempts = 0;
  const applied: string[] = [];
  const subscriber: Subscriber = {
    name: "payroll",
    handle(message) {
      attempts += 1;
      if (attempts < 3) throw new Error("not yet");
      if (applied.includes(message.eventId)) return;
      applied.push(message.eventId);
    },
  };
  const relay = new OutboxRelay(store, [subscriber], new WebhookQueue());
  relay.alarm(NOW);
  relay.alarm(NOW);
  relay.alarm(NOW);
  assert.equal(attempts, 3);
  assert.deepEqual(applied, ["event-1"]);
  assert.equal(store.rows[0]?.publishedAt, NOW);
});

test("PLAT-020 ten failures dead-letter the event and replay clears it", () => {
  const store = new MemoryOutboxStore();
  store.add({
    eventId: "event-dead",
    subjectKey: "assignment:1",
    type: "assignment.changed",
    payload: { eventId: "event-dead" },
    createdAt: "2026-11-01T15:00:00.000Z",
  });
  let attempts = 0;
  const relay = new OutboxRelay(
    store,
    [{ name: "payroll", handle() { attempts += 1; throw new Error("down"); } }],
    new WebhookQueue(),
  );
  for (let n = 0; n < 10; n += 1) relay.alarm(NOW);
  assert.equal(attempts, 10);
  assert.equal(store.rows[0]?.dead, true);
  relay.alarm(NOW);
  assert.equal(attempts, 10);
  store.replay("event-dead");
  relay.alarm(NOW);
  assert.equal(attempts, 11);
});

test("an event is delivered once when the relay restarts after the subscriber and before published_at", () => {
  const store = new MemoryOutboxStore();
  store.add({
    eventId: "event-a",
    subjectKey: "assignment:1",
    type: "assignment.changed",
    payload: { eventId: "event-a", salary: "90000.00" },
    createdAt: "2026-11-01T15:00:00.000Z",
  });
  store.add({
    eventId: "event-b",
    subjectKey: "assignment:1",
    type: "assignment.changed",
    payload: { eventId: "event-b" },
    createdAt: "2026-11-01T15:01:00.000Z",
  });
  const applied: string[] = [];
  const webhooks = new WebhookQueue();
  const relay = new OutboxRelay(
    store,
    [{
      name: "payroll",
      handle(message) {
        if (!applied.includes(message.eventId)) applied.push(message.eventId);
      },
    }],
    webhooks,
  );
  relay.failOnceBeforePublish();
  assert.throws(() => relay.alarm(NOW), /RELAY_RESTART/);
  assert.deepEqual(applied, ["event-a"]);
  assert.equal(store.rows[0]?.publishedAt, null);
  relay.alarm(NOW);
  assert.deepEqual(applied, ["event-a", "event-b"]);
  assert.equal(store.rows[0]?.publishedAt, NOW);
  assert.equal(store.rows[1]?.publishedAt, NOW);
  assert.equal(JSON.stringify(webhooks.messages).includes("90000"), false);
  assert.equal((webhooks.messages[0]?.salary as { changed?: boolean }).changed, true);
});

test("events for one subject stay in order when an earlier one fails", () => {
  const store = new MemoryOutboxStore();
  store.add({ eventId: "a1", subjectKey: "assignment:1", type: "assignment.changed", payload: {}, createdAt: "2026-11-01T15:00:00.000Z" });
  store.add({ eventId: "b1", subjectKey: "assignment:2", type: "assignment.changed", payload: {}, createdAt: "2026-11-01T15:01:00.000Z" });
  store.add({ eventId: "a2", subjectKey: "assignment:1", type: "assignment.changed", payload: {}, createdAt: "2026-11-01T15:02:00.000Z" });
  const seen: string[] = [];
  const relay = new OutboxRelay(
    store,
    [{
      name: "payroll",
      handle(message) {
        if (message.eventId === "a1") throw new Error("a1 down");
        seen.push(message.eventId);
      },
    }],
    new WebhookQueue(),
  );
  relay.alarm(NOW);
  assert.deepEqual(seen, ["b1"]);
  assert.equal(store.rows[2]?.publishedAt, null);
});

test("PLAT-021 two sessions on the same unit refresh, and a person who cannot see it gets nothing", () => {
  const hub = new SessionHub();
  const allow = () => true;
  hub.subscribe({ sessionId: "browser-1", userId: USER, units: ["unit-a"], canSee: allow });
  hub.subscribe({ sessionId: "browser-2", userId: HR, units: ["unit-a"], canSee: allow });
  hub.subscribe({ sessionId: "browser-3", userId: FINANCE, units: ["unit-a"], canSee: () => false });
  hub.publish({ type: "org.changed", asOf: TODAY, units: ["unit-a"], salary: "1.00", personName: "Ana" });
  const first = hub.inbox("browser-1");
  const second = hub.inbox("browser-2");
  assert.equal(first.length, 1);
  assert.equal(second.length, 1);
  assert.deepEqual(Object.keys(first[0] ?? {}).sort(), ["asOf", "type", "units"]);
  assert.equal(hub.inbox("browser-3").length, 0);
  assert.equal(JSON.stringify(first).includes("Ana"), false);
});

const pastAssignment = "aaaaaaaa-0000-0000-0000-000000000071";
const futureAssignment = "aaaaaaaa-0000-0000-0000-000000000081";

function seededPast(): World {
  const world = emptyWorld();
  addAssignment(world, {
    id: pastAssignment,
    employmentId: "employment-1",
    personId: "person-1",
    positionId: null,
    orgUnitId: "unit-a",
    rate: "27000.00",
    validStart: "2026-04-01",
    recordedAt: RECORDED,
    explicitKeys: ["rate", "orgUnitId"],
  });
  return world;
}

function futureRateWorld(): World {
  const world = emptyWorld();
  addAssignment(world, {
    id: futureAssignment,
    employmentId: "employment-1",
    personId: "person-1",
    positionId: null,
    orgUnitId: "unit-old",
    rate: "50000.00",
    validStart: "2026-01-01",
    validEnd: "2027-01-01",
    recordedAt: RECORDED,
    explicitKeys: ["orgUnitId", "rate"],
    later: [
      {
        validStart: "2027-01-01",
        attributes: { orgUnitId: "unit-old", rate: "55000.00", status: "open", positionId: null, locationId: null },
        explicitKeys: ["rate"],
      },
    ],
  });
  return world;
}

function approvalSet(input: {
  hr: string[];
  finance: string[];
  leave?: Record<string, string>;
  subordinate?: [string, string];
}): { books: ChangeSetService; id: string } {
  const world = emptyWorld();
  const assignmentId = crypto.randomUUID();
  addAssignment(world, {
    id: assignmentId,
    employmentId: "employment-1",
    personId: "person-1",
    positionId: null,
    orgUnitId: "unit-a",
    validStart: TODAY,
    recordedAt: RECORDED,
  });
  const books = service(world, {
    routes: [transferOverBudgetRoute()],
    directory: directory({ hrbp: input.hr, finance: input.finance }, { leave: input.leave, subordinate: input.subordinate }),
  });
  const created = books.create(
    {
      kind: "transfer",
      reasonCode: "REORG",
      effectiveDate: TODAY,
      budgetImpact: "10000.01",
      operations: [{ op: "assignment.update", assignmentId, set: { orgUnitId: "unit-b" } }],
    },
    USER,
  );
  assert.equal(created.ok, true);
  if (!created.ok) throw new Error("create failed");
  const submitted = books.submit(created.body.changeSetId, {});
  assert.equal(submitted.ok, true);
  if (!submitted.ok) throw new Error("submit failed");
  return { books, id: created.body.changeSetId };
}

function directory(
  candidates: Record<string, string[]>,
  options?: { leave?: Record<string, string>; subordinate?: [string, string] },
): ApprovalDirectory {
  return {
    candidates(role) {
      return candidates[role] ?? [];
    },
    onLeave(userId) {
      const delegateUserId = options?.leave?.[userId];
      return delegateUserId ? { delegateUserId } : null;
    },
    isSubordinateOnOtherAssignment(approverUserId, requesterUserId) {
      const pair = options?.subordinate;
      return pair?.[0] === approverUserId && pair?.[1] === requesterUserId;
    },
  };
}

function batch(batchNo: number, batchHash: string, prevBatchHash: string, sealedAt: string): SealBatch {
  return {
    tenantId: TENANT,
    batchNo,
    batchHash,
    prevBatchHash,
    signature: `sig-${batchNo}`,
    sealedAt,
  };
}
