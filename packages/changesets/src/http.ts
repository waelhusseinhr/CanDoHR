import { Hono } from "hono";
import type { ChangeSetService, CreateInput } from "./service.ts";
import type { ChangeSetRecord, ValidationResult } from "./types.ts";

/** HTTP shape from api/openapi.yaml. Paths are /change-sets (the server base adds /v1). */
export function createChangeSetApp(service: ChangeSetService): Hono {
  const app = new Hono();

  app.post("/change-sets", async (c) => {
    const body = (await c.req.json()) as CreateInput;
    // structural: optional value absent; empty string for typing
    const userId = c.req.header("x-user-id") ?? "";
    if (!userId) return problem(c, 400, "REQUESTED_BY", "Say who is making this change.");
    const result = service.create(body, userId, c.req.header("Idempotency-Key") ?? undefined);
    if (!result.ok) return problem(c, result.status, result.code, result.detail, result.current);
    return c.json(toJson(result.body), 201);
  });

  app.get("/change-sets", (c) => {
    const page = service.list(c.req.query("status"));
    return c.json({ items: page.items.map(toJson), nextCursor: page.nextCursor });
  });

  app.get("/change-sets/:changeSetId", (c) => {
    const result = service.get(c.req.param("changeSetId"));
    if (!result.ok) return problem(c, result.status, result.code, result.detail);
    return c.json(toJson(result.body));
  });

  app.post("/change-sets/:changeSetId/validate", (c) => {
    const result = service.validate(c.req.param("changeSetId"));
    if (!result.ok) return problem(c, result.status, result.code, result.detail, result.current);
    return c.json(result.body satisfies ValidationResult);
  });

  app.post("/change-sets/:changeSetId/submit", async (c) => {
    const text = await c.req.text();
    const body = text ? (JSON.parse(text) as { acknowledgedWarnings?: string[]; comment?: string; isCorrection?: boolean; conflictResolution?: "keep" | "replace" | "merge" }) : {};
    const result = service.submit(c.req.param("changeSetId"), body);
    if (!result.ok) return problem(c, result.status, result.code, result.detail, result.current);
    return c.json(toJson(result.body));
  });

  app.post("/change-sets/:changeSetId/decision", async (c) => {
    // structural: optional value absent; empty string for typing
    const userId = c.req.header("x-user-id") ?? "";
    const body = (await c.req.json()) as { decision?: string; comment?: string };
    const result = service.decide(c.req.param("changeSetId"), userId, body);
    if (!result.ok) return problem(c, result.status, result.code, result.detail, result.current);
    return c.json(toJson(result.body));
  });

  return app;
}

function toJson(row: ChangeSetRecord) {
  return {
    changeSetId: row.changeSetId,
    number: row.number,
    kind: row.kind,
    reasonCode: row.reasonCode,
    effectiveDate: row.effectiveDate,
    // structural: nullish coalescing for optional input in tests or adapters
    isCorrection: row.isCorrection ?? false,
    operations: row.operations,
    baseVersions: row.baseVersions,
    status: row.status,
    source: row.source,
    requestedBy: row.requestedBy,
    requestedAt: row.requestedAt,
    committedAt: row.committedAt,
    comment: row.comment,
    budgetImpact: row.budgetImpact,
    validation: row.validation,
    approvals: row.approvals.map((step) => ({
      step: step.step,
      assignee: step.assignee,
      status: step.status,
      decidedAt: step.decidedAt,
      role: step.role,
      principalUserId: step.principalUserId,
    })),
  };
}

function problem(
  c: { json: (body: unknown, status?: number) => Response },
  status: number,
  code: string,
  detail: string,
  current?: Record<string, number>,
): Response {
  return new Response(
    JSON.stringify({
      type: "about:blank",
      title: code,
      status,
      detail,
      code,
      current,
    }),
    { status, headers: { "content-type": "application/problem+json" } },
  );
}
