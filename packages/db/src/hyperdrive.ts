import { CanDoError } from "@candohr/shared";

/**
 * The Postgres connection string from a Hyperdrive binding.
 * The Hyperdrive configuration itself must be created with query caching disabled.
 * Caching would serve stale as-of reads and could keep personal data in Cloudflare's cache (docs/02).
 */
export function connectionStringFromHyperdrive(hyperdrive: { connectionString: string }): string {
  if (typeof hyperdrive?.connectionString !== "string" || hyperdrive.connectionString.length === 0) {
    throw new CanDoError("HYPERDRIVE_CONNECTION");
  }
  return hyperdrive.connectionString;
}
