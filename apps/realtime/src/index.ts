import { OutboxRelay, SessionHub } from "@candohr/changesets";

export { OutboxRelay, SessionHub };

export default {
  async fetch(): Promise<Response> {
    return Response.json({
      ok: true,
      service: "candohr-realtime",
      step: 4,
      outbox: "waiting-for-hyperdrive",
      live: "identifiers-only",
    });
  },
};
