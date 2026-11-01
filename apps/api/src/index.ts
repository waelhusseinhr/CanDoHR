import { Hono } from "hono";

const app = new Hono();

app.get("/health", (c) => c.json({ ok: true, service: "candohr-api", step: 0 }));

export default app;
