import assert from "node:assert/strict";
import { generateKeyPair, exportJWK, SignJWT } from "jose";
import { test } from "node:test";
import { createLocalJWKSet, jwtVerify } from "jose";
import { CanDoError } from "@candohr/shared";
import { createApiApp, type PersonRecord } from "../src/api.ts";
import { formerEmployeeAccess, formerEmployeeUntil } from "../src/former-employee.ts";
import { assertLocalesComplete, formatCad, messageKeys, t } from "../src/i18n.ts";
import { createIdentityApp } from "../src/identity.ts";
import { loadAppUser, subjectFromClaims, type AppUser } from "../src/jwt.ts";
import {
  allows,
  maskSin,
  recordInScope,
  redactForLog,
  revealSin,
  scopeFilterSql,
  stripFields,
  type RoleGrant,
} from "../src/permissions.ts";
import { approveProviderGrant, assertOneClient, providerAudit, providerCan, requestProviderGrant } from "../src/provider.ts";
import { createMemoryAuthAdmin, type ScimAudit } from "../src/scim.ts";
import { sessionStillValid } from "../src/session.ts";

const manager: RoleGrant = {
  roleCode: "manager",
  scope: { type: "direct_reports" },
  permissions: [
    { action: "read", fieldClass: "employment", entity: "person" },
    { action: "read", fieldClass: "public_directory" },
  ],
};

const payroll: RoleGrant = {
  roleCode: "payroll_processor",
  scope: { type: "all" },
  permissions: [
    { action: "read", fieldClass: "employment" },
    { action: "read", fieldClass: "personal" },
    { action: "read", fieldClass: "payroll_restricted" },
    { action: "reveal", fieldClass: "payroll_restricted", entity: "person" },
  ],
};

test("a manager does not receive personal or payroll fields, and a reveal writes an audit reason", () => {
  const record = { personId: "p1", title: "Analyst", homeAddress: "1 Main", sin: "123456789" };
  const classes = { title: "employment" as const, homeAddress: "personal" as const, sin: "payroll_restricted" as const };
  const shown = stripFields(record, classes, new Set(["employment", "public_directory"]));
  assert.deepEqual(shown, { personId: "p1", title: "Analyst" });
  assert.equal("homeAddress" in shown, false);
  assert.equal("sin" in shown, false);
  assert.equal(maskSin("123-456-789"), "*** *** 789");
  assert.throws(() => revealSin({ personId: "p1", sin: "123456789", reason: "year-end", grants: [manager] }), (error: unknown) => error instanceof CanDoError && error.code === "NOT_ALLOWED");
  const revealed = revealSin({ personId: "p1", sin: "123456789", reason: "year-end", grants: [payroll] });
  assert.equal(revealed.sin, "123456789");
  assert.equal(revealed.audit.action, "sensitive.reveal");
  assert.equal(allows([payroll], { action: "reveal", fieldClass: "payroll_restricted", entity: "person" }), true);
});

test("scope SQL keeps the caller's values in parameters", () => {
  const sneaky = "11111111-1111-1111-1111-111111111111' OR true --";
  const filter = scopeFilterSql({ type: "subtree", orgUnitId: sneaky, hierarchyId: "h1" }, "person", "2026-11-01");
  assert.equal(filter.sql.includes(sneaky), false);
  assert.equal(filter.params[0], sneaky);
  assert.equal(filter.sql.includes("core.org_closure"), true);
  assert.equal(recordInScope({ type: "self" }, { personId: "p1" }, { personId: "p2" }), false);
  assert.equal(recordInScope({ type: "direct_reports" }, { personId: "p2", reportsToPersonId: "p1" }, { personId: "p1" }), true);
});

test("logs drop sensitive keys", () => {
  const cleaned = redactForLog({ title: "Analyst", sin: "123456789", bank_account: "001" }) as Record<string, unknown>;
  assert.deepEqual(cleaned, { title: "Analyst" });
});

test("PAY-078: leaving on 15 November 2026 keeps access until 28 February 2028, or 2029 for 24 months", () => {
  assert.equal(formerEmployeeUntil("2026-11-15", 12), "2028-02-28");
  assert.equal(formerEmployeeUntil("2026-11-15", 24), "2029-02-28");
  assert.equal(formerEmployeeAccess({ formerEmployeeUntil: "2028-02-28", today: "2028-02-28", documentKind: "tax_slip", ownRecord: true }), "own_documents");
  assert.equal(formerEmployeeAccess({ formerEmployeeUntil: "2028-02-28", today: "2028-03-01", documentKind: "tax_slip", ownRecord: true }), "denied");
  assert.equal(formerEmployeeAccess({ formerEmployeeUntil: "2028-02-28", today: "2027-01-01", documentKind: "pay_statement", ownRecord: false }), "denied");
});

test("PAY-065: unknown capability, approval, and the approved period", () => {
  const users = [
    { userId: "provider-user", tenantId: "provider" },
    { userId: "client-admin", tenantId: "client" },
  ];
  assert.throws(
    () => requestProviderGrant({
      grantId: "g1",
      clientTenantId: "client",
      providerTenantId: "provider",
      providerUserId: "provider-user",
      capabilities: ["payroll_prepare", "everything"],
      validFrom: "2026-11-01",
      validTo: "2027-11-01",
      users,
    }),
    (error: unknown) => error instanceof CanDoError && error.code === "PROVIDER_CAPABILITY_UNKNOWN",
  );
  const grant = requestProviderGrant({
    grantId: "g1",
    clientTenantId: "client",
    providerTenantId: "provider",
    providerUserId: "provider-user",
    capabilities: ["payroll_prepare", "payroll_files", "reports"],
    validFrom: "2026-11-01",
    validTo: "2027-11-01",
    users,
  });
  assert.equal(providerCan([grant], "client", "provider-user", "payroll_prepare", "2026-12-01"), false);
  assert.throws(
    () => approveProviderGrant(grant, users[0]!, "2026-11-02"),
    (error: unknown) => error instanceof CanDoError && error.code === "PROVIDER_GRANT_NOT_CLIENT",
  );
  const approved = approveProviderGrant(grant, users[1]!, "2026-11-02");
  assert.equal(providerCan([approved], "client", "provider-user", "payroll_prepare", "2026-12-01"), true);
  assert.equal(providerCan([approved], "client", "provider-user", "payroll_approve", "2026-12-01"), false);
  assert.equal(providerCan([approved], "client", "provider-user", "payroll_prepare", "2027-12-01"), false);
  const audit = providerAudit({
    clientTenantId: "client",
    providerUserId: "provider-user",
    providerTenantId: "provider",
    action: "payroll.prepare",
    subjectType: "pay_run",
    subjectId: "run-1",
  });
  assert.equal(audit.tenantId, "client");
  assert.equal(audit.actorId, "provider-user");
  assert.equal(audit.providerTenantId, "provider");
  assert.throws(() => assertOneClient({ tenantId: "other", userId: "provider-user", providerTenantId: "provider" }, "client"));
});

test("French and English strings match, and money uses the Canadian French example", () => {
  assertLocalesComplete();
  for (const key of messageKeys()) {
    assert.ok(t("fr-CA", key).length > 0);
    assert.notEqual(t("en-CA", key), "");
  }
  assert.equal(formatCad("fr-CA", "1234.56"), "1 234,56 $");
  assert.equal(formatCad("en-CA", "1234.56"), "$1,234.56");
});

test("the user directory ignores user metadata", () => {
  const users: AppUser[] = [{
    userId: "u1",
    tenantId: "tenant-b",
    idpSubject: "sub-1",
    email: "a@example.test",
    locale: "en-CA",
    status: "active",
    personId: "p1",
    formerEmployeeUntil: null,
    roleCodes: ["manager"],
  }];
  const sub = subjectFromClaims({ sub: "sub-1", user_metadata: { tenant_id: "tenant-a", role: "tenant_admin" } });
  assert.equal(loadAppUser(sub, users).tenantId, "tenant-b");
});

test("a Supabase JWT verifies against the project signing key", async () => {
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  const jwk = await exportJWK(publicKey);
  jwk.alg = "RS256";
  jwk.kid = "test-key";
  const jwks = createLocalJWKSet({ keys: [jwk] });
  const token = await new SignJWT({ user_metadata: { tenant_id: "forged" } })
    .setProtectedHeader({ alg: "RS256", kid: "test-key" })
    .setSubject("sub-1")
    .setIssuer("https://lasowjpgxlxijpaeezxe.supabase.co/auth/v1")
    .setAudience("authenticated")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);
  const { payload } = await jwtVerify(token, jwks, {
    issuer: "https://lasowjpgxlxijpaeezxe.supabase.co/auth/v1",
    audience: "authenticated",
  });
  assert.equal(subjectFromClaims(payload), "sub-1");
  assert.equal(typeof payload.user_metadata, "object");
});

function person(tenantId: string, personId: string): PersonRecord {
  return {
    tenantId,
    personId,
    title: "Analyst",
    homeAddress: "1 Main",
    sin: "123456789",
    orgUnitId: "unit",
    reportsToPersonId: "manager-person",
  };
}

test("tenant B's list endpoints do not show tenant A's people", async () => {
  const users: AppUser[] = [
    { userId: "ua", tenantId: "A", idpSubject: "a", email: "a@example.test", locale: "en-CA", status: "active", personId: "pa", formerEmployeeUntil: null, roleCodes: ["hr_admin"] },
    { userId: "ub", tenantId: "B", idpSubject: "b", email: "b@example.test", locale: "fr-CA", status: "active", personId: "pb", formerEmployeeUntil: null, roleCodes: ["hr_admin"] },
  ];
  const grants = new Map<string, RoleGrant[]>([
    ["ua", [{ roleCode: "hr_admin", scope: { type: "all" }, permissions: [{ action: "read", fieldClass: "employment" }] }]],
    ["ub", [{ roleCode: "hr_admin", scope: { type: "all" }, permissions: [{ action: "read", fieldClass: "employment" }] }]],
  ]);
  const app = createApiApp({
    users,
    grants,
    people: [person("A", "pa")],
    audits: [],
    batches: [],
    verifyToken: async (token) => ({ sub: token }),
  });
  const people = await app.request("/people", { headers: { authorization: "Bearer b" } });
  assert.equal(people.status, 200);
  assert.deepEqual(await people.json(), []);
  const jobs = await app.request("/employments", { headers: { authorization: "Bearer b" } });
  assert.deepEqual(await jobs.json(), []);
  const own = await app.request("/people", { headers: { authorization: "Bearer a" } });
  const body = await own.json() as Record<string, unknown>[];
  assert.equal(body.length, 1);
  assert.equal("homeAddress" in (body[0] ?? {}), false);
});

test("SCIM creates, updates and disables a user", async () => {
  const admin = createMemoryAuthAdmin();
  const audits: ScimAudit[] = [];
  const app = createIdentityApp({ scim: { admin, audits }, users: [], grants: [] });
  const created = await app.request("/scim/v2/Users", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ userName: "ada@example.test", externalId: "ada", active: true }),
  });
  assert.equal(created.status, 201);
  const createdBody = await created.json() as { id: string; active: boolean };
  assert.equal(createdBody.active, true);
  const patched = await app.request(`/scim/v2/Users/${createdBody.id}`, {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ Operations: [{ op: "replace", path: "active", value: false }] }),
  });
  assert.equal(patched.status, 200);
  const patchedBody = await patched.json() as { active: boolean };
  assert.equal(patchedBody.active, false);
  assert.equal(audits.some((item) => item.action === "scim.disable"), true);
  const updated = await app.request(`/scim/v2/Users/${createdBody.id}`, {
    method: "PUT",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ userName: "ada@example.test", active: true }),
  });
  assert.equal((await updated.json() as { active: boolean }).active, true);
});

test("the identity app refuses a provider who approves their own grant", async () => {
  const admin = createMemoryAuthAdmin();
  const users = [
    { userId: "provider-user", tenantId: "provider" },
    { userId: "client-admin", tenantId: "client" },
  ];
  const app = createIdentityApp({ scim: { admin, audits: [] }, users, grants: [] });
  const requested = await app.request("/provider-grants", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      grantId: "g1",
      clientTenantId: "client",
      providerTenantId: "provider",
      providerUserId: "provider-user",
      capabilities: ["payroll_prepare"],
      validFrom: "2026-11-01",
      validTo: "2027-11-01",
    }),
  });
  assert.equal(requested.status, 201);
  const denied = await app.request("/provider-grants/g1/approve", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ approverUserId: "provider-user", approvedAt: "2026-11-02" }),
  });
  assert.equal(denied.status, 422);
  assert.equal((await denied.json() as { code: string }).code, "PROVIDER_GRANT_NOT_CLIENT");
});

test("a privileged session ends after 30 idle minutes and every session ends after 8 hours", () => {
  const start = Date.parse("2026-11-01T12:00:00Z");
  assert.equal(sessionStillValid({ issuedAtMs: start, lastActivityAtMs: start, nowMs: start + 31 * 60 * 1000, privileged: true }), false);
  assert.equal(sessionStillValid({ issuedAtMs: start, lastActivityAtMs: start, nowMs: start + 31 * 60 * 1000, privileged: false }), true);
  assert.equal(sessionStillValid({ issuedAtMs: start, lastActivityAtMs: start + 7 * 60 * 60 * 1000, nowMs: start + 8 * 60 * 60 * 1000, privileged: false }), false);
});
