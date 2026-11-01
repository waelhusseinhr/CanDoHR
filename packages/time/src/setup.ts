import { TimeError } from "./money.ts";

export function recordAveraging(input: {
  positionId: string;
  kind: "written_agreement" | "permit" | "collective_agreement";
  documentId?: string;
  agreementName?: string;
  endDate?: string;
  alreadyCovered?: boolean;
}): { positionId: string; kind: string; endDate?: string } {
  if (input.alreadyCovered) throw new TimeError("AVERAGING_CONFLICT");
  const collective = input.kind === "collective_agreement";
  if (!collective && !input.documentId) throw new TimeError("INPUT_REQUIRED");
  if (!collective && !input.endDate) throw new TimeError("INPUT_REQUIRED");
  if (collective && !input.agreementName) throw new TimeError("INPUT_REQUIRED");
  return { positionId: input.positionId, kind: input.kind, endDate: input.endDate };
}

export function recordExemption(input: {
  jurisdiction: string;
  code: string;
  legalBasis?: string;
  reason?: string;
  catalogue: Record<string, string[]>;
}): {
  code: string;
  legalBasis: string;
  reason: string;
} {
  const list = input.catalogue[input.jurisdiction];
  if (!list || !list.includes(input.code)) throw new TimeError("JURISDICTION_RULE_MISSING");
  if (!input.legalBasis || !input.reason) throw new TimeError("INPUT_REQUIRED");
  return { code: input.code, legalBasis: input.legalBasis, reason: input.reason };
}

export function recordingMethodFor(input: {
  orgRule?: "punches" | "timesheet" | "exceptions";
  payBasis?: "hourly" | "daily" | "salary";
}): "punches" | "timesheet" | "exceptions" {
  if (input.orgRule) return input.orgRule;
  if (input.payBasis === "hourly" || input.payBasis === "daily") return "punches";
  if (input.payBasis === "salary") return "exceptions";
  throw new TimeError("INPUT_REQUIRED");
}
