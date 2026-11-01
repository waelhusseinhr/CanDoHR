import { CanDoError } from "@candohr/shared";
import { Kysely, sql, type Transaction } from "kysely";
import type { Database } from "./client.ts";

const UUID_TEXT = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export interface TenantContext {
  tenantId: string;
  userId: string;
  /** Role codes for this request. Stored as a comma-separated list in `app.roles` (docs/19 §12). */
  roles: readonly string[];
}

/**
 * One request's database work. Opens a transaction, sets the tenant, the user, and the roles
 * for that transaction only (`SET LOCAL` / `set_config(..., true)`), then commits.
 * A thrown error rolls the transaction back. The settings do not stay on the pooled connection.
 */
export async function withTenant<T>(
  db: Kysely<Database>,
  context: TenantContext,
  work: (trx: Transaction<Database>) => Promise<T>,
): Promise<T> {
  const tenantId = requiredUuid(context.tenantId, "TENANT_ID");
  const userId = requiredUuid(context.userId, "USER_ID");
  const roles = normalizeRoles(context.roles);
  return db.transaction().execute(async (trx) => {
    await sql`select set_config('app.tenant_id', ${tenantId}, true)`.execute(trx);
    await sql`select set_config('app.user_id', ${userId}, true)`.execute(trx);
    await sql`select set_config('app.roles', ${roles.join(",")}, true)`.execute(trx);
    return work(trx);
  });
}

function requiredUuid(value: string, code: string): string {
  if (typeof value !== "string" || !UUID_TEXT.test(value)) {
    throw new CanDoError(code);
  }
  return value.toLowerCase();
}

function normalizeRoles(roles: readonly string[]): string[] {
  if (!Array.isArray(roles)) {
    throw new CanDoError("ROLE_CODE");
  }
  return roles.map((role) => {
    if (typeof role !== "string" || role.length === 0 || role !== role.trim() || /[,\s]/.test(role)) {
      throw new CanDoError("ROLE_CODE");
    }
    return role;
  });
}
