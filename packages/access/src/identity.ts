import { CanDoError } from "@candohr/shared";
import { Hono } from "hono";
import {
  approveProviderGrant,
  providerCan,
  requestProviderGrant,
  type DirectoryUser,
  type ProviderGrant,
} from "./provider.ts";
import { createScimApp, type ScimDeps } from "./scim.ts";

export interface IdentityDeps {
  scim: ScimDeps;
  users: readonly DirectoryUser[];
  grants: ProviderGrant[];
}

/** SCIM and provider-grant approval. This app does not open a database connection. */
export function createIdentityApp(deps: IdentityDeps): Hono {
  const app = createScimApp(deps.scim);

  app.post("/provider-grants", async (c) => {
    const body = await c.req.json().catch(() => null) as {
      grantId?: string;
      clientTenantId?: string;
      providerTenantId?: string;
      providerUserId?: string;
      capabilities?: string[];
      validFrom?: string;
      validTo?: string;
    } | null;
    if (!body?.grantId || !body.clientTenantId || !body.providerTenantId || !body.providerUserId || !body.capabilities || !body.validFrom || !body.validTo) {
      throw new CanDoError("PROVIDER_GRANT");
    }
    const grant = requestProviderGrant({
      grantId: body.grantId,
      clientTenantId: body.clientTenantId,
      providerTenantId: body.providerTenantId,
      providerUserId: body.providerUserId,
      capabilities: body.capabilities,
      validFrom: body.validFrom,
      validTo: body.validTo,
      users: deps.users,
    });
    deps.grants.push(grant);
    return c.json(grant, 201);
  });

  app.post("/provider-grants/:grantId/approve", async (c) => {
    const body = await c.req.json().catch(() => null) as { approverUserId?: string; approvedAt?: string } | null;
    const grant = deps.grants.find((item) => item.grantId === c.req.param("grantId"));
    const approver = deps.users.find((user) => user.userId === body?.approverUserId);
    if (!grant || !approver || !body?.approvedAt) throw new CanDoError("PROVIDER_GRANT");
    const approved = approveProviderGrant(grant, approver, body.approvedAt);
    const index = deps.grants.findIndex((item) => item.grantId === grant.grantId);
    deps.grants[index] = approved;
    return c.json({
      grant: approved,
      canPrepare: providerCan(deps.grants, approved.clientTenantId, approved.providerUserId, "payroll_prepare", body.approvedAt),
    });
  });

  app.onError((error, c) => {
    const code = error instanceof CanDoError ? error.code : "ERROR";
    const status = code === "PROVIDER_CAPABILITY_UNKNOWN" || code === "PROVIDER_GRANT_NOT_CLIENT" || code === "PROVIDER_USER_UNKNOWN" ? 422 : 400;
    return c.json({ code }, status);
  });

  return app;
}
