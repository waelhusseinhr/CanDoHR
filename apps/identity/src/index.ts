import { createIdentityApp, type AuthAdmin, type AuthUser } from "@candohr/access";

interface Env {
  /** Auth admin key. This Worker is the only place it is read. There is no database binding. */
  SUPABASE_SERVICE_ROLE_KEY?: string;
  SUPABASE_URL?: string;
}

/**
 * Calls Supabase Auth admin. The key stays in this Worker.
 * A database password is not used here.
 */
export function supabaseAuthAdmin(url: string, serviceRoleKey: string): AuthAdmin {
  const endpoint = `${url.replace(/\/$/, "")}/auth/v1/admin/users`;
  const headers = {
    authorization: `Bearer ${serviceRoleKey}`,
    apikey: serviceRoleKey,
    "content-type": "application/json",
  };
  return {
    async createUser(input) {
      const response = await fetch(endpoint, {
        method: "POST",
        headers,
        body: JSON.stringify({ email: input.email, email_confirm: true, user_metadata: { external_id: input.externalId }, ban_duration: input.active ? "none" : "876000h" }),
      });
      if (!response.ok) throw new Error("SCIM_AUTH");
      const body = await response.json() as { id: string; email?: string };
      return { id: body.id, email: body.email ?? input.email, active: input.active, externalId: input.externalId };
    },
    async updateUser(id, patch) {
      const response = await fetch(`${endpoint}/${id}`, {
        method: "PUT",
        headers,
        body: JSON.stringify({
          email: patch.email,
          ban_duration: patch.active === false ? "876000h" : "none",
        }),
      });
      if (!response.ok) throw new Error("SCIM_AUTH");
      const body = await response.json() as { id: string; email?: string; banned_until?: string | null };
      const user: AuthUser = {
        id: body.id,
        email: body.email ?? patch.email ?? "",
        active: patch.active ?? !body.banned_until,
        externalId: patch.externalId ?? null,
      };
      return user;
    },
    async getUser(id) {
      const response = await fetch(`${endpoint}/${id}`, { headers });
      if (response.status === 404) return null;
      if (!response.ok) throw new Error("SCIM_AUTH");
      const body = await response.json() as { id: string; email?: string; banned_until?: string | null };
      return { id: body.id, email: body.email ?? "", active: !body.banned_until, externalId: null };
    },
  };
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) {
      return Response.json({ ok: false, service: "candohr-identity", code: "AUTH_ADMIN_NOT_CONFIGURED" }, { status: 503 });
    }
    const admin = supabaseAuthAdmin(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY);
    const app = createIdentityApp({ scim: { admin, audits: [] }, users: [], grants: [] });
    return app.fetch(request);
  },
};
