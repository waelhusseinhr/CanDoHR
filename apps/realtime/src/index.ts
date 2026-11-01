export default {
  async fetch(): Promise<Response> {
    return new Response(JSON.stringify({ ok: true, service: "candohr-realtime", step: 0 }), {
      headers: { "content-type": "application/json" },
    });
  },
};
