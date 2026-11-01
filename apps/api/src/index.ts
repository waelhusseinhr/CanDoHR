import { createApiApp, verifySupabaseJwt } from "@candohr/access";

interface Env {
  SUPABASE_JWKS_URL?: string;
  SUPABASE_JWT_ISSUER?: string;
}

/**
 * The public API. Tenant and roles come from platform.app_user after the JWT is checked.
 * The user directory is empty until the database binding exists. /health still answers.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const app = createApiApp({
      users: [],
      grants: new Map(),
      people: [],
      audits: [],
      batches: [],
      verifyToken: async (token) => {
        if (!env.SUPABASE_JWKS_URL || !env.SUPABASE_JWT_ISSUER) throw new Error("JWT_NOT_CONFIGURED");
        return verifySupabaseJwt(token, env.SUPABASE_JWKS_URL, env.SUPABASE_JWT_ISSUER);
      },
    });
    return app.fetch(request);
  },
};
