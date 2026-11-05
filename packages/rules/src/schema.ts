import { readFileSync } from "node:fs";
import { join } from "node:path";
import Ajv2020 from "ajv/dist/2020.js";
import { rulesDirectory } from "./editions.ts";
import { RulesError } from "./errors.ts";

export function validateAgreementDocument(document: unknown, schema?: unknown): void {
  const loaded =
    schema ??
    JSON.parse(readFileSync(join(rulesDirectory(), "agreements/agreement.schema.json"), "utf8"));
  const ajv = new Ajv2020({ allErrors: true, strict: false, logger: false });
  const validate = ajv.compile(loaded as object);
  if (!validate(document)) {
    const detail = (validate.errors ?? [])
      // structural: optional value absent; empty string for typing
      .map((error) => `${error.instancePath || "/"} ${error.message ?? ""}`)
      .join("; ");
    // structural: JSON Schema validation message formatting
    throw new RulesError("SCHEMA_INVALID", detail || "agreement document does not match the schema", 422);
  }
}
