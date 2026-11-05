import { Kysely, PostgresDialect } from "kysely";
import pg from "pg";

/** Calendar dates stay `YYYY-MM-DD` strings. Timestamps stay UTC ISO strings. */
const DATE_OID = 1082;
const TIMESTAMPTZ_OID = 1184;

let parsersReady = false;

function ensureParsers(): void {
  if (parsersReady) return;
  pg.types.setTypeParser(DATE_OID, (value) => value);
  pg.types.setTypeParser(TIMESTAMPTZ_OID, (value) => new Date(value).toISOString());
  parsersReady = true;
}

export interface Database {
  tenant_note: {
    tenant_id: string;
    note: string;
  };
}

/** A Kysely client over node-postgres. `max` is the pool size. */
export function createDb(connectionString: string, options?: { max?: number }): Kysely<Database> {
  if (typeof connectionString !== "string" || connectionString.length === 0) {
    throw new Error("CONNECTION_STRING");
  }
  ensureParsers();
  const pool = new pg.Pool({
    connectionString,
    // structural: connection pool cap for local dev, not a tenant setting
    max: options?.max ?? 10,
  });
  return new Kysely<Database>({
    dialect: new PostgresDialect({ pool }),
  });
}
