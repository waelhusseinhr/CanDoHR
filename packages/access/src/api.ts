import { leafHash, proofFor, toHex, type SealedBatch } from "@candohr/audit";
import { CanDoError } from "@candohr/shared";
import { Hono, type Context, type Next } from "hono";
import { formerEmployeeAccess } from "./former-employee.ts";
import { loadAppUser, subjectFromClaims, type AppUser } from "./jwt.ts";
import { t, type Locale } from "./i18n.ts";
import {
  allowedFieldClasses,
  recordInScope,
  revealSin,
  stripFields,
  type FieldClass,
  type RoleGrant,
  type ScopedRecord,
} from "./permissions.ts";
import { sessionStillValid } from "./session.ts";

export interface PersonRecord extends ScopedRecord {
  tenantId: string;
  title: string;
  homeAddress: string;
  sin: string;
}

export interface StoredAudit {
  tenantId: string;
  audit_id: number;
  occurred_at: string;
  actor_type: string;
  actor_id: string;
  on_behalf_of: string | null;
  action: string;
  subject_type: string;
  subject_id: string;
  change_set_id: string | null;
  before: unknown;
  after: unknown;
  reason: string | null;
  ip?: string | null;
  leaf_hash: string;
  batchNo: number | null;
}

const FIELD_CLASSES: Record<string, FieldClass> = {
  title: "employment",
  homeAddress: "personal",
  sin: "payroll_restricted",
};

export interface ApiDeps {
  users: readonly AppUser[];
  grants: ReadonlyMap<string, readonly RoleGrant[]>;
  people: readonly PersonRecord[];
  audits: StoredAudit[];
  batches: readonly SealedBatch[];
  /** Test and production both pass a verified subject. The token's user metadata is ignored. */
  verifyToken: (token: string) => Promise<{ sub: string; issuedAtMs?: number; lastActivityAtMs?: number; user_metadata?: unknown }>;
  nowMs?: number;
}

type ApiEnv = { Variables: { user: AppUser } };

function localeOf(user: AppUser): Locale {
  return user.locale;
}

export function createApiApp(deps: ApiDeps): Hono<ApiEnv> {
  const app = new Hono<ApiEnv>();

  app.get("/health", (c) => c.json({ ok: true, service: "candohr-api", step: 3 }));

  app.use("/people", attachUser(deps));
  app.use("/people/*", attachUser(deps));
  app.use("/employments", attachUser(deps));
  app.use("/me/*", attachUser(deps));
  app.use("/audit/*", attachUser(deps));

  app.get("/people", (c) => {
    const user = c.get("user");
    if (user.formerEmployeeUntil) {
      return c.json({ code: "FORMER_EMPLOYEE_LIMITED", message: t(localeOf(user), "former.limited") }, 403);
    }
    const grants = deps.grants.get(user.userId) ?? [];
    const allowed = allowedFieldClasses(grants, "read");
    const rows = deps.people.filter((person) => person.tenantId === user.tenantId && grants.some((grant) => recordInScope(grant.scope, person, { personId: user.personId })));
    return c.json(rows.map((person) => stripFields({ ...person }, FIELD_CLASSES, allowed)));
  });

  app.get("/employments", (c) => {
    const user = c.get("user");
    const rows = deps.people.filter((person) => person.tenantId === user.tenantId);
    return c.json(rows.map((person) => ({ personId: person.personId, title: person.title })));
  });

  app.post("/people/:personId/sin/reveal", async (c) => {
    const user = c.get("user");
    const body = await c.req.json().catch(() => null) as { reason?: string } | null;
    const person = deps.people.find((item) => item.personId === c.req.param("personId") && item.tenantId === user.tenantId);
    if (!person) return c.json({ code: "NOT_FOUND" }, 404);
    try {
      const revealed = revealSin({
        personId: person.personId,
        sin: person.sin,
        reason: body?.reason ?? "",
        grants: deps.grants.get(user.userId) ?? [],
      });
      const occurredAt = new Date(deps.nowMs ?? Date.now()).toISOString();
      const auditId = deps.audits.length + 1;
      const material = {
        tenant_id: user.tenantId,
        audit_id: auditId,
        occurred_at: occurredAt,
        actor_type: "user",
        actor_id: user.userId,
        on_behalf_of: null,
        action: revealed.audit.action,
        subject_type: "person",
        subject_id: person.personId,
        change_set_id: null,
        before: null,
        after: { field: revealed.audit.field },
        reason: revealed.audit.reason,
      };
      deps.audits.push({
        tenantId: user.tenantId,
        ...material,
        ip: null,
        leaf_hash: toHex(leafHash(material)),
        batchNo: null,
      });
      return c.json({ sin: revealed.sin });
    } catch (error) {
      const code = error instanceof CanDoError ? error.code : "NOT_ALLOWED";
      return c.json({ code, message: t(localeOf(user), "permission.denied") }, 403);
    }
  });

  app.get("/me/documents", (c) => {
    const user = c.get("user");
    const today = new Date(deps.nowMs ?? Date.now()).toISOString().slice(0, 10);
    const access = formerEmployeeAccess({
      formerEmployeeUntil: user.formerEmployeeUntil,
      today,
      documentKind: "pay_statement",
      ownRecord: true,
    });
    if (access === "denied") return c.json({ code: "FORMER_EMPLOYEE_ENDED", message: t(localeOf(user), "session.ended") }, 403);
    return c.json({ documents: ["pay_statement", "tax_slip", "roe"] });
  });

  app.get("/audit/entries/:auditId/proof", (c) => {
    const user = c.get("user");
    const auditId = Number(c.req.param("auditId"));
    const row = deps.audits.find((item) => item.audit_id === auditId && item.tenantId === user.tenantId);
    if (!row || row.batchNo == null) return c.json({ code: "NOT_SEALED" }, 409);
    const batch = deps.batches.find((item) => item.batchNo === row.batchNo && item.tenantId === user.tenantId);
    if (!batch) return c.json({ code: "NOT_SEALED" }, 409);
    const rows = deps.audits.filter((item) => item.batchNo === batch.batchNo && item.tenantId === user.tenantId);
    const asRow = (item: StoredAudit) => ({
      tenant_id: item.tenantId,
      audit_id: item.audit_id,
      occurred_at: item.occurred_at,
      actor_type: item.actor_type,
      actor_id: item.actor_id,
      on_behalf_of: item.on_behalf_of,
      action: item.action,
      subject_type: item.subject_type,
      subject_id: item.subject_id,
      change_set_id: item.change_set_id,
      before: item.before,
      after: item.after,
      reason: item.reason,
      leaf_hash: item.leaf_hash,
    });
    const proof = proofFor(asRow(row), batch, rows.map(asRow));
    return c.json({
      title: t(localeOf(user), "audit.proof"),
      auditId: proof.auditId,
      leafHash: proof.leafHash,
      batch: proof.batch,
      auditPath: proof.auditPath,
      batchHash: proof.batchHash,
      signature: proof.signature,
      signingKeyId: proof.signingKeyId,
    });
  });

  app.onError((error, c) => {
    const code = error instanceof CanDoError ? error.code : "ERROR";
    const status = code === "USER_UNKNOWN" || code === "JWT_SUBJECT" || code === "USER_DISABLED" ? 401 : 400;
    return c.json({ code }, status);
  });

  return app;
}

function attachUser(deps: ApiDeps) {
  return async (c: Context<ApiEnv>, next: Next) => {
    const header = c.req.header("authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) return c.json({ code: "JWT_SUBJECT" }, 401);
    let verified: { sub: string; issuedAtMs?: number; lastActivityAtMs?: number; user_metadata?: unknown };
    try {
      verified = await deps.verifyToken(token);
    } catch {
      return c.json({ code: "JWT_SUBJECT" }, 401);
    }
    const sub = subjectFromClaims(verified);
    let user: AppUser;
    try {
      user = loadAppUser(sub, deps.users);
    } catch (error) {
      const code = error instanceof CanDoError ? error.code : "USER_UNKNOWN";
      return c.json({ code }, 401);
    }
    const privileged = user.roleCodes.some((role) => role === "hr_admin" || role === "payroll_processor" || role === "finance" || role === "tenant_admin");
    const now = deps.nowMs ?? Date.now();
    const issuedAtMs = verified.issuedAtMs ?? now;
    const lastActivityAtMs = verified.lastActivityAtMs ?? now;
    if (!sessionStillValid({ issuedAtMs, lastActivityAtMs, nowMs: now, privileged })) {
      return c.json({ code: "SESSION_ENDED", message: t(user.locale, "session.ended") }, 401);
    }
    c.set("user", user);
    await next();
  };
}
