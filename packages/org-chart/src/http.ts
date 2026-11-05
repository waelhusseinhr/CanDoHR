import { Hono } from "hono";
import type { MoveInput, OrgChart } from "./engine.ts";

/** Chart reads. asOf is the business date. Nothing here is cached. */
export function createOrgChartApp(chart: OrgChart, today: string): Hono {
  const app = new Hono();

  app.get("/org-chart", (c) => {
    const asOf = c.req.query("asOf") ?? today;
    // structural: org-chart query default depth for demos
    const depth = Number(c.req.query("depth") ?? "3");
    const rootId = c.req.query("rootId") ?? undefined;
    const planId = c.req.query("planId") ?? undefined;
    const hierarchyId = c.req.query("hierarchyId") ?? undefined;
    return c.json(chart.chart({ asOf, depth: Number.isFinite(depth) ? depth : 3, rootId, planId, hierarchyId }));
  });

  app.post("/org-chart/moves", async (c) => {
    const body = (await c.req.json()) as MoveInput;
    const result = chart.move(body);
    return c.json(
      {
        changeSet: result.changeSetId ? { changeSetId: result.changeSetId, status: result.status, operations: result.operations } : null,
        validation: result.validation,
        interpretations: result.interpretations,
      },
      result.ok && result.changeSetId ? 201 : result.ok ? 200 : 422,
    );
  });

  app.post("/plans", async (c) => {
    const body = (await c.req.json()) as { name: string; asOf: string; members?: string[] };
    return c.json(chart.createPlan(body), 201);
  });

  app.post("/plans/:planId/submit", (c) => {
    return c.json(chart.approvePlan(c.req.param("planId")));
  });

  return app;
}
