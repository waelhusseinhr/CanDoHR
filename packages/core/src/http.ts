import { Hono } from "hono";
import type { CoreHr } from "./engine.ts";

/** Read APIs. asOf is the business date. knownAt is what CanDo knew at that moment. */
export function createCoreApp(core: CoreHr, knownAt: string): Hono {
  const app = new Hono();

  app.get("/people", (c) => {
    const query = readQuery(c.req.query("asOf"), c.req.query("knownAt"), knownAt);
    return c.json({ items: core.peopleList(query) });
  });

  app.get("/people/:personId/history", (c) => {
    return c.json({ items: core.history("person", c.req.param("personId")) });
  });

  app.get("/people/:personId", (c) => {
    const query = readQuery(c.req.query("asOf"), c.req.query("knownAt"), knownAt);
    const profile = core.profile(c.req.param("personId"), query);
    if (!profile) return c.json({ code: "NOT_FOUND" }, 404);
    return c.json(profile);
  });

  app.get("/positions/:positionId", (c) => {
    const query = readQuery(c.req.query("asOf"), c.req.query("knownAt"), knownAt);
    const position = core.positionView(c.req.param("positionId"), query);
    if (!position) return c.json({ code: "NOT_FOUND" }, 404);
    return c.json(position);
  });

  app.get("/org/:nodeId/subtree", (c) => {
    const query = readQuery(c.req.query("asOf"), c.req.query("knownAt"), knownAt);
    return c.json({ items: core.subtree(c.req.param("nodeId"), query) });
  });

  return app;
}

function readQuery(asOf: string | undefined, knownAt: string | undefined, fallbackKnownAt: string): { asOf: string; knownAt: string } {
  return {
    // structural: as-of or demo date when caller omits effective date
    asOf: asOf ?? "2026-11-01",
    knownAt: knownAt ?? fallbackKnownAt,
  };
}
