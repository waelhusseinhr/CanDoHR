import assert from "node:assert/strict";
import test from "node:test";
import { CanDoError, connectionStringFromHyperdrive, withTenant, createDb } from "../src/index.ts";

test("Hyperdrive helper returns the binding string and does not turn caching on", () => {
  const connectionString = "postgresql://cando_app@example.invalid:5432/postgres";
  assert.equal(connectionStringFromHyperdrive({ connectionString }), connectionString);
  assert.throws(() => connectionStringFromHyperdrive({ connectionString: "" }), (error: CanDoError) => error.code === "HYPERDRIVE_CONNECTION");
});

test("withTenant rejects a tenant id that is not a uuid before it touches the database", async () => {
  const db = createDb("postgresql://invalid.example/candohr");
  await assert.rejects(
    () =>
      withTenant(
        db,
        { tenantId: "not-a-uuid", userId: "00000000-0000-4000-8000-000000000002", roles: [] },
        async () => "nope",
      ),
    (error: CanDoError) => error.code === "TENANT_ID",
  );
  await assert.rejects(
    () =>
      withTenant(
        db,
        { tenantId: "00000000-0000-4000-8000-000000000001", userId: "00000000-0000-4000-8000-000000000002", roles: ["bad,role"] },
        async () => "nope",
      ),
    (error: CanDoError) => error.code === "ROLE_CODE",
  );
  await db.destroy();
});
