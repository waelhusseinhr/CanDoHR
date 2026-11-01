import { createHash } from "node:crypto";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { RulesError } from "./errors.ts";

export type EditionRecord = {
  path: string;
  sha256: string;
  family: string;
  status: "loaded" | "verify_at_load";
  body: unknown;
};

type Cached = {
  bytes: Buffer;
  body: unknown;
  family: string;
  path: string;
};

export function rulesDirectory(): string {
  return fileURLToPath(new URL("../../../rules/", import.meta.url));
}

export function sha256(bytes: Buffer | string): string {
  return createHash("sha256").update(bytes).digest("hex");
}

export function markedVerifyAtLoad(value: unknown): boolean {
  if (value === "verify_at_load") return true;
  if (Array.isArray(value)) return value.some((item) => markedVerifyAtLoad(item));
  if (typeof value === "object" && value !== null) {
    const record = value as Record<string, unknown>;
    if (record.status === "verify_at_load") return true;
    return Object.values(record).some((item) => markedVerifyAtLoad(item));
  }
  return false;
}

function walkJson(dir: string, acc: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walkJson(path, acc);
    else if (name.endsWith(".json")) acc.push(path);
  }
  return acc;
}

export class EditionStore {
  private readonly byHash = new Map<string, Cached>();

  loadDirectory(root = rulesDirectory()): EditionRecord[] {
    const records: EditionRecord[] = [];
    for (const path of walkJson(root)) {
      const bytes = readFileSync(path);
      const body = JSON.parse(bytes.toString("utf8")) as unknown;
      const hash = sha256(bytes);
      const family = relative(root, path).split(/[/\\]/)[0] ?? "rules";
      const status = markedVerifyAtLoad(body) ? "verify_at_load" : "loaded";
      this.byHash.set(hash, { bytes, body, family, path });
      records.push({ path: relative(root, path), sha256: hash, family, status, body });
    }
    return records;
  }

  /** Calculation reads a pinned edition and checks the hash again after the read. */
  loadForCalculation(hash: string): unknown {
    const row = this.byHash.get(hash);
    if (!row) throw new RulesError("UNKNOWN_EDITION", hash, 404);
    const actual = sha256(row.bytes);
    if (actual !== hash) throw new RulesError("HASH_MISMATCH", `${hash} does not match the stored edition`, 422);
    return structuredClone(row.body);
  }

  /** Test hook: store bytes under a hash that may not match them. */
  remember(claimedHash: string, bytes: Buffer, family = "test"): void {
    this.byHash.set(claimedHash, {
      bytes,
      body: JSON.parse(bytes.toString("utf8")) as unknown,
      family,
      path: "memory",
    });
  }

  activate(hash: string, env: "production" | "sandbox"): void {
    const row = this.byHash.get(hash);
    if (!row) throw new RulesError("UNKNOWN_EDITION", hash, 404);
    this.loadForCalculation(hash);
    if (env === "production" && row.family === "employment-standards" && markedVerifyAtLoad(row.body)) {
      throw new RulesError(
        "VERIFY_AT_LOAD",
        "employment standards still marked verify_at_load cannot be activated in production",
        422,
      );
    }
  }
}
