import assert from "node:assert/strict";
import { test } from "node:test";
import { transferOverBudgetRoute } from "../src/approval.ts";
import { createChangeSetApp } from "../src/http.ts";
import { ChangeSetService } from "../src/service.ts";
import { addAssignment, emptyWorld } from "../src/world.ts";

const TENANT = "11111111-1111-1111-1111-111111111111";
const USER = "22222222-2222-2222-2222-222222222222";
const HR = "33333333-3333-3333-3333-333333333333";
const NOW = "2026-11-01T15:00:00.000Z";
const TODAY = "2026-11-01";
const RECORDED = "2020-01-01T00:00:00.000Z";

function appFor(seed?: (books: ChangeSetService) => void) {
  const world = emptyWorld();
  const assignmentId = "aaaaaaaa-0000-0000-0000-000000000091";
  addAssignment(world, {
    id: assignmentId,
    version: 8,
    employmentId: "employment-1",
    personId: "person-1",
    positionId: null,
    orgUnitId: "unit-a",
    validStart: TODAY,
    recordedAt: RECORDED,
  });
  const books = new ChangeSetService(world, {
    tenantId: TENANT,
    today: TODAY,
    now: () => NOW,
    routes: [transferOverBudgetRoute()],
    directory: {
      candidates(role) {
        if (role === "hrbp") return [HR];
        if (role === "finance") return [HR];
        return [];
      },
      onLeave: () => null,
      isSubordinateOnOtherAssignment: () => false,
    },
  });
  seed?.(books);
  return { app: createChangeSetApp(books), assignmentId, books };
}

test("change-set endpoints match the OpenAPI contract", async () => {
  const { app, assignmentId } = appFor();
  const body = {
    kind: "transfer",
    reasonCode: "REORG",
    effectiveDate: TODAY,
    operations: [{ op: "assignment.update", targetId: assignmentId, set: { orgUnitId: "unit-b" } }],
  };
  const created = await app.request("/change-sets", {
    method: "POST",
    headers: { "content-type": "application/json", "x-user-id": USER, "Idempotency-Key": "same-key" },
    body: JSON.stringify(body),
  });
  assert.equal(created.status, 201);
  const draft = (await created.json()) as Record<string, unknown>;
  for (const key of ["changeSetId", "number", "status", "source", "requestedBy", "requestedAt", "kind", "reasonCode", "effectiveDate", "operations"]) {
    assert.ok(draft[key] !== undefined && draft[key] !== null, key);
  }
  assert.equal(draft.status, "draft");
  assert.equal(draft.requestedBy, USER);
  const replay = await app.request("/change-sets", {
    method: "POST",
    headers: { "content-type": "application/json", "x-user-id": USER, "Idempotency-Key": "same-key" },
    body: JSON.stringify(body),
  });
  assert.equal(replay.status, 201);
  const again = (await replay.json()) as { changeSetId: string };
  assert.equal(again.changeSetId, draft.changeSetId);

  const page = await app.request("/change-sets");
  assert.equal(page.status, 200);
  const listed = (await page.json()) as { items: { changeSetId: string }[]; nextCursor: string | null };
  assert.equal(listed.items.length, 1);
  assert.equal(listed.nextCursor, null);

  const got = await app.request(`/change-sets/${draft.changeSetId as string}`);
  assert.equal(got.status, 200);

  const missing = await app.request("/change-sets/00000000-0000-0000-0000-000000000000");
  assert.equal(missing.status, 404);
  assert.match(missing.headers.get("content-type") ?? "", /application\/problem\+json/);
  const problem = (await missing.json()) as { type: string; title: string; status: number; code: string };
  assert.equal(problem.status, 404);
  assert.equal(problem.code, "NOT_FOUND");
  assert.ok(problem.type);
  assert.ok(problem.title);

  const validated = await app.request(`/change-sets/${draft.changeSetId as string}/validate`, { method: "POST" });
  assert.equal(validated.status, 200);
  const result = (await validated.json()) as { errors: unknown[]; warnings: unknown[]; consequences: unknown[] };
  assert.ok(Array.isArray(result.errors));
  assert.ok(Array.isArray(result.warnings));
  assert.ok(Array.isArray(result.consequences));

  const conflict = await app.request("/change-sets", {
    method: "POST",
    headers: { "content-type": "application/json", "x-user-id": USER },
    body: JSON.stringify({
      ...body,
      baseVersions: { [`assignment:${assignmentId}`]: 7 },
    }),
  });
  const conflictBody = (await conflict.json()) as { changeSetId: string };
  const submitted = await app.request(`/change-sets/${conflictBody.changeSetId}/submit`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ acknowledgedWarnings: [], comment: "ok" }),
  });
  assert.equal(submitted.status, 409);
  assert.match(submitted.headers.get("content-type") ?? "", /application\/problem\+json/);
  const version = (await submitted.json()) as { code: string; current: Record<string, number> };
  assert.equal(version.code, "VERSION_CONFLICT");
  assert.equal(version.current[`assignment:${assignmentId}`], 8);

  const approval = await app.request("/change-sets", {
    method: "POST",
    headers: { "content-type": "application/json", "x-user-id": USER },
    body: JSON.stringify({ ...body, budgetImpact: "10000.01" }),
  });
  const approvalBody = (await approval.json()) as { changeSetId: string };
  const pending = await app.request(`/change-sets/${approvalBody.changeSetId}/submit`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({}),
  });
  assert.equal(pending.status, 200);
  const decision = await app.request(`/change-sets/${approvalBody.changeSetId}/decision`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-user-id": USER },
    body: JSON.stringify({ decision: "approve", comment: "mine" }),
  });
  assert.equal(decision.status, 403);
  assert.match(decision.headers.get("content-type") ?? "", /application\/problem\+json/);
  const blocked = (await decision.json()) as { code: string };
  assert.equal(blocked.code, "SELF_APPROVAL_BLOCKED");
});
