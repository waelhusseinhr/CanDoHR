import { createHash } from "node:crypto";
import { RulesError, type RuleProblem } from "./errors.ts";
import { canonicalize } from "./canonical.ts";
import { validate } from "./stacking.ts";

export type StoredVersion = {
  id: string;
  body: unknown;
  rules: Record<string, unknown>;
  contentSha256: string;
  status: "draft" | "verified" | "active";
};

function hashText(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export class AgreementLibrary {
  private readonly byId = new Map<string, StoredVersion>();
  private readonly byHash = new Map<string, string>();

  save(version: Record<string, unknown>): { id: string; contentSha256: string } {
    const rules = isRecord(version.rules) ? version.rules : version;
    // structural: nullish coalescing for optional input in tests or adapters
    const id = String(version.id ?? `${String(version.agreementId ?? "agreement")}:${String(version.version ?? "1")}`);
    const existing = this.byId.get(id);
    if (existing && existing.status !== "draft") {
      throw new RulesError("IMMUTABLE", "a verified agreement version cannot change", 422);
    }
    const contentSha256 = hashText(canonicalize(version));
    const stored: StoredVersion = {
      id,
      body: structuredClone(version),
      rules: structuredClone(rules),
      contentSha256,
      status: "draft",
    };
    this.byId.set(id, stored);
    this.byHash.set(contentSha256, id);
    return { id, contentSha256 };
  }

  /** Verification lists every open combination. Any problem refuses the version. */
  verify(id: string): RuleProblem[] {
    const row = this.require(id);
    const problems = validate(row.rules);
    if (problems.length > 0) {
      throw new RulesError(problems[0].code, problems.map((problem) => problem.detail).join("; "), 422, problems);
    }
    if (row.status === "draft") row.status = "verified";
    return problems;
  }

  activate(id: string): void {
    this.verify(id);
    const row = this.require(id);
    row.status = "active";
  }

  loadByHash(hash: string): unknown {
    const id = this.byHash.get(hash);
    if (!id) throw new RulesError("UNKNOWN_VERSION", hash, 404);
    const row = this.require(id);
    const actual = hashText(canonicalize(row.body));
    if (actual !== hash) throw new RulesError("HASH_MISMATCH", "agreement content_sha256 does not match", 422);
    return structuredClone(row.body);
  }

  get(id: string): StoredVersion {
    return this.require(id);
  }

  private require(id: string): StoredVersion {
    const row = this.byId.get(id);
    if (!row) throw new RulesError("UNKNOWN_VERSION", id, 404);
    return row;
  }
}
