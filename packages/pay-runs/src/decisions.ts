import { createHash } from "node:crypto";
import { canonicalize, calculate, resultSha256, type PayResult } from "@candohr/payroll-engine";
import { CanDoError } from "@candohr/shared";
import Decimal from "decimal.js";
import { distributeLargestRemainder, type Share } from "./distribute.ts";

export class PayRunError extends Error {
  readonly code: string;
  readonly blockingRunId: string | undefined;

  constructor(code: string, blockingRunId?: string) {
    super(code);
    this.name = "PayRunError";
    this.code = code;
    this.blockingRunId = blockingRunId;
  }
}

export function approvePayRun(input: { createdBy: string; approver?: string; routeComplete: boolean }): "approved" {
  if (!input.approver) throw new PayRunError("INPUT_REQUIRED");
  if (!input.routeComplete) throw new PayRunError("ROUTE_APPROVALS_MISSING");
  if (input.approver === input.createdBy) throw new PayRunError("SELF_APPROVAL");
  return "approved";
}

export interface HeldEmployee {
  personId: string;
  checkCode: string;
  reason: string;
}

export interface ReviewResult {
  paidPersonIds: string[];
  holds: HeldEmployee[];
}

/** One failed check holds that person. The others stay on this run (PAY-061). */
export function reviewRun(input: {
  personIds: readonly string[];
  failed: readonly { personId: string; checkCode: string; reason: string }[];
}): ReviewResult {
  const held = new Set(input.failed.map((item) => item.personId));
  return {
    paidPersonIds: input.personIds.filter((id) => !held.has(id)),
    holds: input.failed.map((item) => ({ ...item })),
  };
}

export function approveWithHolds(input: { policy: "hold_employee" | "stop_run"; openHolds: number }): "approved" {
  if (input.policy === "stop_run" && input.openHolds > 0) throw new PayRunError("PAY_RUN_HAS_FAILED_CHECKS");
  return "approved";
}

export function offCycleForHold(input: { holdRunId: string; personId: string }): { personId: string; releasedInRunId: string } {
  return { personId: input.personId, releasedInRunId: input.holdRunId };
}

export function finalizeLiveRun(input: { firstLive: boolean; parallelAccepted: boolean; differencesAccepted: boolean }): "finalized" {
  if (input.firstLive && !input.parallelAccepted) throw new PayRunError("PARALLEL_RUN_REQUIRED");
  if (input.parallelAccepted && !input.differencesAccepted) throw new PayRunError("PARALLEL_RUN_REQUIRED");
  return "finalized";
}

export function providerAccess(input: {
  capabilityKnown: boolean;
  clientApproved: boolean;
  approverIsProvider: boolean;
}): "allowed" {
  if (!input.capabilityKnown) throw new PayRunError("PROVIDER_CAPABILITY_UNKNOWN");
  if (input.approverIsProvider) throw new PayRunError("SELF_APPROVAL");
  if (!input.clientApproved) throw new PayRunError("PROVIDER_GRANT_NOT_CLIENT");
  return "allowed";
}

export interface VacationRule {
  id: string;
  scope: Record<string, string>;
  rate: string;
}

export function vacationRuleFor(rules: readonly VacationRule[], facts: Record<string, string>): VacationRule {
  for (const key of Object.keys(facts)) {
    if (facts[key] === "unknown") throw new PayRunError("PAYROLL_SCOPE_UNKNOWN");
  }
  const match = rules.find((rule) => Object.entries(rule.scope).every(([key, value]) => facts[key] === value));
  if (!match) throw new PayRunError("VACATION_PAY_RULE_MISSING");
  return match;
}

export function createPayGroup(input: { prorationMethod?: string }): { prorationMethod: string } {
  if (!input.prorationMethod) throw new PayRunError("SETTING_NOT_SET");
  return { prorationMethod: input.prorationMethod };
}

export interface StarterCode {
  pay_code: string;
  status: string;
  kind?: string;
}

export function loadStarterCodes(codes: readonly StarterCode[]): { copied: StarterCode[]; forPayroll: StarterCode[] } {
  return {
    copied: codes.filter((code) => code.status === "verified"),
    forPayroll: codes.filter((code) => code.status !== "verified"),
  };
}

export function stackPremiums(input: { combined: boolean }): "ok" | HeldEmployee {
  if (!input.combined) {
    return { personId: "subject", checkCode: "UNRESOLVED_INTERACTION", reason: "Premiums do not combine" };
  }
  return "ok";
}

export function activateGarnishment(input: { confirmed: boolean }): "active" {
  if (!input.confirmed) throw new PayRunError("GARNISHMENT_NOT_CONFIRMED");
  return "active";
}

export function approveVoluntaryDeduction(input: { kind: string; employeeId: string; approverId: string }): "approved" {
  if (input.kind !== "deduction") throw new PayRunError("PAY_CODE_NOT_DEDUCTION");
  if (input.approverId === input.employeeId) throw new PayRunError("SELF_APPROVAL");
  return "approved";
}

export function saveDeductionCode(input: { shortfall?: string }): "saved" {
  if (!input.shortfall) throw new PayRunError("INPUT_REQUIRED");
  return "saved";
}

export function writeOffArrears(input: { reason?: string }): "written_off" {
  if (!input.reason) throw new PayRunError("INPUT_REQUIRED");
  return "written_off";
}

export interface PostTaxDeduction {
  code: string;
  amount: string;
  /** Statutory, then support, then other garnishments, then the organization's own order (PAY-030). */
  rank: "statutory" | "support" | "garnishment" | "organization";
  shortfall: "spread" | "drop";
  spreadPeriods?: number;
}

const DEDUCTION_RANK: Record<PostTaxDeduction["rank"], number> = {
  statutory: 0,
  support: 1,
  garnishment: 2,
  organization: 3,
};

export interface DeductionOutcome {
  net: string;
  taken: { code: string; amount: string }[];
  arrears: { code: string; amount: string; periods: number }[];
}

/** Tax is already out. Then support, then the organization's order. Never below the protected minimum (PAY-075). */
export function applyPostTaxDeductions(input: {
  netAfterTax: string;
  protectedMinimum: string;
  deductions: readonly PostTaxDeduction[];
}): DeductionOutcome {
  const order = [...input.deductions].sort((a, b) => DEDUCTION_RANK[a.rank] - DEDUCTION_RANK[b.rank]);
  let available = Number(input.netAfterTax) - Number(input.protectedMinimum);
  if (available < 0) available = 0;
  const taken: DeductionOutcome["taken"] = [];
  const arrears: DeductionOutcome["arrears"] = [];
  for (const item of order) {
    const want = Number(item.amount);
    const fullFits = want <= round2(available) + 0.001;
    const pay = item.shortfall === "drop" && !fullFits ? 0 : Math.min(want, round2(available));
    taken.push({ code: item.code, amount: pay.toFixed(2) });
    const short = round2(want - pay);
    if (short > 0 && item.shortfall === "spread") {
      // structural: nullish coalescing for optional input in tests or adapters
      arrears.push({ code: item.code, amount: short.toFixed(2), periods: item.spreadPeriods ?? 1 });
    }
    available = round2(available - pay);
  }
  const net = round2(Number(input.protectedMinimum) + available);
  return { net: net.toFixed(2), taken, arrears };
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

export function recoverAdvance(input: { authorized?: string; alreadyRecovered: string; amount: string }): "ok" {
  if (!input.authorized) throw new PayRunError("RECOVERY_NOT_AUTHORIZED");
  if (Number(input.alreadyRecovered) + Number(input.amount) > Number(input.authorized) + 0.001) {
    throw new PayRunError("RECOVERY_ABOVE_AUTHORIZED");
  }
  return "ok";
}

export function saveOneTimePayment(input: { positionCount: number; positionId?: string }): "saved" {
  if (input.positionCount > 1 && !input.positionId) throw new PayRunError("INPUT_REQUIRED");
  return "saved";
}

export function changeStatutoryEdition(input: { status: string; contentChanged: boolean; editionId: string; source: string }): {
  editionId: string;
  source: string;
} {
  if (input.contentChanged && ["tested", "active", "retired"].includes(input.status)) {
    throw new PayRunError("STATUTORY_EDITION_LOCKED");
  }
  return { editionId: input.editionId, source: input.source };
}

export interface Lease {
  payRunId: string;
  payrollAccountId: string;
  personId: string;
  released: boolean;
  simulation: boolean;
}

/** A second open run for the same person and payroll account is refused and names the blocking run (docs/06 §9). */
export function leaseSubjects(open: readonly Lease[], request: { payRunId: string; simulation: boolean; subjects: readonly { payrollAccountId: string; personId: string }[] }): Lease[] {
  if (request.simulation) return [];
  for (const subject of request.subjects) {
    const blocking = open.find(
      (lease) =>
        !lease.released &&
        !lease.simulation &&
        lease.payRunId !== request.payRunId &&
        lease.payrollAccountId === subject.payrollAccountId &&
        lease.personId === subject.personId,
    );
    if (blocking) throw new PayRunError("SUBJECT_IN_OPEN_RUN", blocking.payRunId);
  }
  return request.subjects.map((subject) => ({
    payRunId: request.payRunId,
    payrollAccountId: subject.payrollAccountId,
    personId: subject.personId,
    released: false,
    simulation: false,
  }));
}

export function pinInputs(inputs: unknown): { inputsKnownAt: string; snapshotSha256: string } {
  return {
    inputsKnownAt: new Date().toISOString(),
    snapshotSha256: createHash("sha256").update(canonicalize(inputs)).digest("hex"),
  };
}

export function paySubject(input: Record<string, unknown>): { hash: string; result: PayResult } {
  const result = calculate(input);
  return { hash: resultSha256(result), result };
}

/** YTD is kept per person and payroll account. Two accounts do not share maximums (ENT-018). */
export function ytdAmount(rows: readonly { personId: string; payrollAccountId: string; code: string; amount: string }[], personId: string, payrollAccountId: string, code: string): string {
  const total = rows
    .filter((row) => row.personId === personId && row.payrollAccountId === payrollAccountId && row.code === code)
    .reduce((sum, row) => sum + Number(row.amount), 0);
  return total.toFixed(2);
}

export function excludeCoveredDays(days: readonly string[], cutover: string): string[] {
  return days.filter((day) => day >= cutover);
}

export function reconcileOpening(imported: readonly { amount: string }[], stated: string): "reconciled" {
  const total = imported.reduce((sum, row) => sum + Number(row.amount), 0);
  if (Math.abs(total - Number(stated)) > 0.001) throw new CanDoError("YTD_NOT_RECONCILED");
  return "reconciled";
}

export function segmentDays(days: readonly { date: string; rate: string; positionId: string }[]): { start: string; end: string; rate: string; positionId: string }[] {
  const sorted = [...days].sort((a, b) => a.date.localeCompare(b.date));
  const segments: { start: string; end: string; rate: string; positionId: string }[] = [];
  for (const day of sorted) {
    const last = segments[segments.length - 1];
    if (last && last.rate === day.rate && last.positionId === day.positionId) last.end = day.date;
    else segments.push({ start: day.date, end: day.date, rate: day.rate, positionId: day.positionId });
  }
  return segments;
}

export function taxMethodFor(runType: string, requested: "auto" | "periodic" | "non_periodic" = "auto"): "periodic" | "non_periodic" {
  if (requested !== "auto") return requested;
  if (runType === "bonus" || runType === "retro") return "non_periodic";
  return "periodic";
}

export function explain(result: PayResult): PayResult["trace"] {
  return result.trace;
}

const LIVE_STEPS = ["draft", "inputs_locked", "calculated", "reviewed", "approved", "finalized"] as const;

/** The story path. Approval still needs a complete route and a different person (PAY-010). */
export function advancePayRun(input: {
  status: (typeof LIVE_STEPS)[number];
  to: (typeof LIVE_STEPS)[number];
  createdBy: string;
  approver?: string;
  routeComplete: boolean;
}): (typeof LIVE_STEPS)[number] {
  const from = LIVE_STEPS.indexOf(input.status);
  const to = LIVE_STEPS.indexOf(input.to);
  if (from < 0 || to !== from + 1) throw new PayRunError("INPUT_REQUIRED");
  if (input.to === "approved" || input.to === "finalized") {
    approvePayRun({ createdBy: input.createdBy, approver: input.approver, routeComplete: input.routeComplete });
  }
  return input.to;
}

export function controlTotals(results: readonly { gross: string; net: string }[]): { employees: number; gross: string; net: string } {
  const gross = results.reduce((sum, row) => sum.plus(row.gross), new Decimal(0));
  const net = results.reduce((sum, row) => sum.plus(row.net), new Decimal(0));
  return { employees: results.length, gross: gross.toFixed(2), net: net.toFixed(2) };
}

/** Hours times the rate in force that day. Money stays in cents (PAY-011). */
export function dayEarnings(hours: string, rate: string): string {
  return new Decimal(hours).times(rate).toDecimalPlaces(2, Decimal.ROUND_HALF_UP).toFixed(2);
}

export function taxYearOf(payDate: string): number {
  return Number(payDate.slice(0, 4));
}

/** Fiscal year is the calendar year of the year-end month that contains the day (PAY-014). */
export function fiscalYearOf(iso: string, yearEndMonth: number): number {
  const year = Number(iso.slice(0, 4));
  const month = Number(iso.slice(5, 7));
  return month <= yearEndMonth ? year : year + 1;
}

export function fiscalShares(amount: string, days: readonly { date: string }[], yearEndMonth: number): Share[] {
  const counts = new Map<string, number>();
  for (const day of days) {
    const key = String(fiscalYearOf(day.date, yearEndMonth));
    // structural: missing numeric coalesces to zero for arithmetic
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const weights = [...counts.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([key, weight]) => ({ key, weight: String(weight) }));
  return distributeLargestRemainder(amount, weights);
}

/** A preview stores nothing and takes no lease (PAY-016). */
export function simulatePay(input: Record<string, unknown>): { result: PayResult; ytdWritten: false; leases: [] } {
  return { result: calculate(input), ytdWritten: false, leases: [] };
}

/** YTD moves only when the run is finalized (PAY-018). */
export function ytdWritesOn(status: string): boolean {
  return status === "finalized";
}

export function draftWarnings(
  open: readonly Lease[],
  subjects: readonly { payrollAccountId: string; personId: string }[],
): { code: "SUBJECT_IN_OPEN_RUN"; blockingRunId: string; personId: string }[] {
  const warnings = [];
  for (const subject of subjects) {
    const blocking = open.find(
      (lease) =>
        !lease.released &&
        !lease.simulation &&
        lease.payrollAccountId === subject.payrollAccountId &&
        lease.personId === subject.personId,
    );
    if (blocking) warnings.push({ code: "SUBJECT_IN_OPEN_RUN" as const, blockingRunId: blocking.payRunId, personId: subject.personId });
  }
  return warnings;
}

export function assertRulePin(pinnedHash: string, loadedHash: string): void {
  if (pinnedHash !== loadedHash) throw new PayRunError("RULE_HASH_MISMATCH");
}

export function statementRange(bucket: number, perBucket: number): { start: number; end: number } {
  if (bucket < 0 || perBucket < 1) throw new PayRunError("INPUT_REQUIRED");
  const start = bucket * perBucket + 1;
  return { start, end: start + perBucket - 1 };
}
