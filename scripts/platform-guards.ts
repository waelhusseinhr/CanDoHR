/**
 * Platform guards from docs/14-testing-and-quality.md §1.
 * Static checks until Hyperdrive configs and Worker bindings exist in repo.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

const root = join(import.meta.dirname, "..");
let failed = 0;

function fail(message: string): void {
  console.error(`platform-guards: ${message}`);
  failed += 1;
}

function read(path: string): string {
  return readFileSync(join(root, path), "utf8");
}

function walk(dir: string, acc: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, acc);
    else acc.push(p);
  }
  return acc;
}

// No CanDo schema exposed through Supabase Data API (config checked in Step 1 migrations too).
try {
  const config = read("supabase/config.toml");
  if (/schemas\s*=\s*\[[^\]]*"(platform|core|ref)"/m.test(config)) {
    fail("supabase/config.toml must not expose CanDo schemas in api.schemas");
  }
} catch {
  fail("missing supabase/config.toml");
}

// service_role only on identity Worker.
for (const app of ["api", "jobs", "realtime", "web"]) {
  const dir = join(root, "apps", app);
  try {
    for (const file of walk(dir)) {
      const rel = relative(root, file);
      if (!/\.(ts|tsx|jsonc?|md)$/.test(file)) continue;
      const text = readFileSync(file, "utf8");
      if (/service_role|SUPABASE_SERVICE_ROLE/i.test(text)) {
        fail(`${rel} must not reference service_role (identity Worker only)`);
      }
    }
  } catch {
    /* app may not exist yet */
  }
}

// Hyperdrive bindings must document caching disabled (when present).
for (const file of walk(join(root, "apps"))) {
  if (!file.endsWith("wrangler.jsonc") && !file.endsWith("wrangler.toml")) continue;
  const text = readFileSync(file, "utf8");
  if (/hyperdrive/i.test(text) && !/caching-disabled|caching disabled/i.test(text)) {
    fail(`${relative(root, file)}: document Hyperdrive with caching disabled when adding bindings`);
  }
}

if (failed > 0) {
  process.exit(1);
}
console.log("platform-guards: ok");
