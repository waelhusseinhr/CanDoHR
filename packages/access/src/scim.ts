import { CanDoError } from "@candohr/shared";
import { Hono } from "hono";

export interface AuthUser {
  id: string;
  email: string;
  active: boolean;
  externalId: string | null;
}

/** Supabase Auth admin calls. The identity Worker is the only caller. */
export interface AuthAdmin {
  createUser(input: { email: string; externalId: string | null; active: boolean }): Promise<AuthUser>;
  updateUser(id: string, patch: { email?: string; active?: boolean; externalId?: string | null }): Promise<AuthUser>;
  getUser(id: string): Promise<AuthUser | null>;
}

export interface ScimAudit {
  action: "scim.create" | "scim.update" | "scim.disable";
  subjectId: string;
  email: string;
}

export interface ScimDeps {
  admin: AuthAdmin;
  audits: ScimAudit[];
}

function scimUser(user: AuthUser) {
  return {
    schemas: ["urn:ietf:params:scim:schemas:core:2.0:User"],
    id: user.id,
    userName: user.email,
    externalId: user.externalId,
    active: user.active,
    emails: [{ value: user.email, primary: true }],
  };
}

export function createScimApp(deps: ScimDeps): Hono {
  const app = new Hono();

  app.post("/scim/v2/Users", async (c) => {
    const body = await c.req.json().catch(() => null) as { userName?: string; externalId?: string; active?: boolean } | null;
    if (!body?.userName) throw new CanDoError("SCIM_USER");
    const created = await deps.admin.createUser({
      email: body.userName,
      externalId: body.externalId ?? null,
      active: body.active !== false,
    });
    deps.audits.push({
      action: created.active ? "scim.create" : "scim.disable",
      subjectId: created.id,
      email: created.email,
    });
    return c.json(scimUser(created), 201);
  });

  app.get("/scim/v2/Users/:id", async (c) => {
    const user = await deps.admin.getUser(c.req.param("id"));
    if (!user) return c.json({ status: "404" }, 404);
    return c.json(scimUser(user));
  });

  app.put("/scim/v2/Users/:id", async (c) => {
    const body = await c.req.json().catch(() => null) as { userName?: string; externalId?: string; active?: boolean } | null;
    if (!body) throw new CanDoError("SCIM_USER");
    const updated = await deps.admin.updateUser(c.req.param("id"), {
      email: body.userName,
      externalId: body.externalId,
      active: body.active,
    });
    deps.audits.push({
      action: updated.active ? "scim.update" : "scim.disable",
      subjectId: updated.id,
      email: updated.email,
    });
    return c.json(scimUser(updated));
  });

  app.patch("/scim/v2/Users/:id", async (c) => {
    const body = await c.req.json().catch(() => null) as {
      Operations?: { op?: string; path?: string; value?: unknown }[];
    } | null;
    const replaceActive = body?.Operations?.find(
      (op) => op.op?.toLowerCase() === "replace" && (op.path === "active" || op.value && typeof op.value === "object" && "active" in (op.value as object)),
    );
    let active: boolean | undefined;
    if (replaceActive?.path === "active") active = Boolean(replaceActive.value);
    else if (replaceActive && typeof replaceActive.value === "object" && replaceActive.value && "active" in replaceActive.value) {
      active = Boolean((replaceActive.value as { active: unknown }).active);
    }
    if (active === undefined) throw new CanDoError("SCIM_USER");
    const updated = await deps.admin.updateUser(c.req.param("id"), { active });
    deps.audits.push({
      action: updated.active ? "scim.update" : "scim.disable",
      subjectId: updated.id,
      email: updated.email,
    });
    return c.json(scimUser(updated));
  });

  return app;
}

export function createMemoryAuthAdmin(): AuthAdmin & { users: AuthUser[] } {
  const users: AuthUser[] = [];
  return {
    users,
    async createUser(input) {
      const user: AuthUser = {
        id: `auth-${users.length + 1}`,
        email: input.email,
        active: input.active,
        externalId: input.externalId,
      };
      users.push(user);
      return user;
    },
    async updateUser(id, patch) {
      const user = users.find((item) => item.id === id);
      if (!user) throw new CanDoError("USER_UNKNOWN");
      if (patch.email !== undefined) user.email = patch.email;
      if (patch.active !== undefined) user.active = patch.active;
      if (patch.externalId !== undefined) user.externalId = patch.externalId;
      return user;
    },
    async getUser(id) {
      return users.find((item) => item.id === id) ?? null;
    },
  };
}
