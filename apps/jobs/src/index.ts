export default {
  async fetch(): Promise<Response> {
    return new Response(JSON.stringify({ ok: true, service: "candohr-jobs", step: 0 }), {
      headers: { "content-type": "application/json" },
    });
  },
};
