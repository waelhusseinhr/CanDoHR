import { createHash } from "node:crypto";
import { add, cents, isNegative, isZero, RetroError, sub } from "./money.ts";

/** A ratified agreement creates retro requests in batches of this size (docs/06 §6). */
export const RETRO_BATCH_SIZE = 500;

const RETRO_TOUCHES = new Set([
  "rate",
  "agreement",
  "assignment",
  "time",
  "leave",
  "benefits",
  "payroll_profile",
  "province",
]);

export type EligiblePopulation =
  | "active_on_ratification"
  | "active_on_ratification_and_terminated_after_retro_from"
  | "all_employed_in_retro_period"
  | "terminated_on_application"
  | "retirees";

export type PostClosePolicy = "successor" | "fallback" | "suspense";

export interface PayLine {
  payCode: string;
  amount: string;
}

export interface MoneySnapshot {
  lines: readonly PayLine[];
  pensionable: string;
  insurable: string;
  pension: string;
  employerCost: string;
}

export interface ComparedPeriod {
  resultId: string;
  employmentId: string;
  personId: string;
  periodStart: string;
  periodEnd: string;
  originalPayDate: string;
  finalized: boolean;
  source: "stored" | "migrated";
  was: MoneySnapshot;
  should: MoneySnapshot;
}

export interface RetroDifference {
  payCode: string;
  amount: string;
  kind: "earnings" | "pensionable" | "insurable" | "pension" | "employer";
}

export interface RetroRequest {
  personId: string;
  employmentId: string;
  originalResultId: string;
  triggerChangeSetId: string;
  periodStart: string;
  periodEnd: string;
  originalPayDate: string;
  source: "stored" | "migrated";
  status: "queued" | "calculated" | "no_difference" | "overpayment_held" | "approved" | "paid";
  differences: RetroDifference[];
  paidInResultId?: string;
}

export interface EmployeeForRetro {
  personId: string;
  employmentId: string;
  hiredOn: string;
  status: "active" | "terminated" | "retired";
  terminatedOn?: string;
  appliedOn?: string;
  periods: readonly ComparedPeriod[];
}

export interface FundingSource {
  id: string;
  closed: boolean;
  periodFinal: boolean;
  postClosePolicy: PostClosePolicy;
  successorId?: string;
  fallbackId?: string;
}

export interface FunderAdjustment {
  workDate: string;
  amount: string;
  fromSourceId: string;
  toSourceId: string;
  policy: PostClosePolicy;
}

export interface PayableLine {
  payCode: string;
  amount: string;
  workPeriodStart: string;
  workPeriodEnd: string;
  retroOf: string;
  taxMethod: "non_periodic";
  taxYear: number;
  t4Year: number;
}

export interface T1198Letter {
  form: "T1198";
  taxYear: number;
  amount: string;
}

export interface RetroBatch {
  batch: number;
  employeeIds: string[];
  status: "queued" | "calculated";
  cost: string;
}

export interface ProgressView {
  done: number;
  total: number;
  cost: string;
  exceptions: number;
  paid: false;
}

const ZERO_SNAPSHOT: MoneySnapshot = {
  lines: [],
  pensionable: "0.00",
  insurable: "0.00",
  pension: "0.00",
  employerCost: "0.00",
};

export function linesSha256(lines: readonly { payCode: string; amount: string }[]): string {
  const canonical = [...lines]
    .map((line) => ({ payCode: line.payCode, amount: cents(line.amount) }))
    .sort((left, right) => left.payCode.localeCompare(right.payCode) || left.amount.localeCompare(right.amount));
  return createHash("sha256").update(JSON.stringify(canonical)).digest("hex");
}

export function differencesOf(was: MoneySnapshot, should: MoneySnapshot): RetroDifference[] {
  const codes = new Set<string>([...was.lines.map((line) => line.payCode), ...should.lines.map((line) => line.payCode)]);
  const rows: RetroDifference[] = [];
  for (const payCode of [...codes].sort()) {
    const wasAmount = sumCode(was.lines, payCode);
    const shouldAmount = sumCode(should.lines, payCode);
    const amount = sub(shouldAmount, wasAmount);
    if (!isZero(amount)) rows.push({ payCode, amount, kind: "earnings" });
  }
  pushBucket(rows, "PI", was.pensionable, should.pensionable, "pensionable");
  pushBucket(rows, "IE", was.insurable, should.insurable, "insurable");
  pushBucket(rows, "PENSION", was.pension, should.pension, "pension");
  pushBucket(rows, "EMPLOYER", was.employerCost, should.employerCost, "employer");
  return rows;
}

function pushBucket(
  rows: RetroDifference[],
  payCode: string,
  was: string,
  should: string,
  kind: RetroDifference["kind"],
): void {
  const amount = sub(should, was);
  if (!isZero(amount)) rows.push({ payCode, amount, kind });
}

function sumCode(lines: readonly PayLine[], payCode: string): string {
  return lines.filter((line) => line.payCode === payCode).reduce((total, line) => add(total, line.amount), "0.00");
}

export function earningsTotal(differences: readonly RetroDifference[]): string {
  return differences.filter((row) => row.kind === "earnings").reduce((total, row) => add(total, row.amount), "0.00");
}

/** Periods that end before the first CanDo pay date were paid by the old system (ENT-029). */
export function wasPaidSource(periodEnd: string, goLiveDate: string): "stored" | "migrated" {
  return periodEnd < goLiveDate ? "migrated" : "stored";
}

export function dayNumber(windowStart: string, on: string): number {
  const start = Date.parse(`${windowStart}T00:00:00Z`);
  const end = Date.parse(`${on}T00:00:00Z`);
  if (Number.isNaN(start) || Number.isNaN(end)) throw new RetroError("DATE");
  return Math.round((end - start) / 86_400_000) + 1;
}

export function taxYearOf(payDate: string): number {
  const year = Number(payDate.slice(0, 4));
  if (!Number.isInteger(year)) throw new RetroError("DATE");
  return year;
}

/**
 * Who the agreement pays retro to.
 * A former employee inside the application window is included. One who applies after it is not (ENT-024).
 */
export function isEligible(
  person: Pick<EmployeeForRetro, "status" | "hiredOn" | "terminatedOn" | "appliedOn">,
  rule: { eligiblePopulation: EligiblePopulation; retroFrom: string; ratificationDate: string; applicationDays?: number },
): boolean {
  const terminatedAfterRetro = person.status === "terminated" && !!person.terminatedOn && person.terminatedOn > rule.retroFrom;
  const activeOnRatification = person.status === "active" || (!!person.terminatedOn && person.terminatedOn > rule.ratificationDate);
  if (rule.eligiblePopulation === "active_on_ratification") return activeOnRatification;
  if (rule.eligiblePopulation === "active_on_ratification_and_terminated_after_retro_from") {
    return activeOnRatification || terminatedAfterRetro;
  }
  if (rule.eligiblePopulation === "all_employed_in_retro_period") {
    if (person.hiredOn > rule.ratificationDate) return false;
    if (person.status !== "terminated") return true;
    return !!person.terminatedOn && person.terminatedOn >= rule.retroFrom;
  }
  if (rule.eligiblePopulation === "retirees") return person.status === "retired";
  if (!person.appliedOn || rule.applicationDays === undefined) return false;
  return dayNumber(rule.ratificationDate, person.appliedOn) <= rule.applicationDays;
}

function requestForPeriod(period: ComparedPeriod, triggerChangeSetId: string): RetroRequest | undefined {
  if (!period.finalized) return undefined;
  if (period.source === "migrated" && period.was.lines.length === 0 && isZero(period.was.pensionable) && isZero(period.was.insurable)) {
    throw new RetroError("MIGRATED_HISTORY_MISSING");
  }
  const differences = differencesOf(period.was, period.should);
  if (differences.length === 0) return undefined;
  const earnings = earningsTotal(differences);
  return {
    personId: period.personId,
    employmentId: period.employmentId,
    originalResultId: period.resultId,
    triggerChangeSetId,
    periodStart: period.periodStart,
    periodEnd: period.periodEnd,
    originalPayDate: period.originalPayDate,
    source: period.source,
    status: isNegative(earnings) ? "overpayment_held" : "calculated",
    differences,
  };
}

/** A committed past change that touches pay inputs opens one request per finalized period that differs (PAY-020, docs/06 §6). */
export function retroFromChangeSet(input: {
  changeSetId: string;
  effectiveDate: string;
  today: string;
  committed: boolean;
  touches: readonly string[];
  periods: readonly ComparedPeriod[];
}): RetroRequest[] {
  if (!input.committed) return [];
  if (input.effectiveDate >= input.today) return [];
  if (!input.touches.some((touch) => RETRO_TOUCHES.has(touch))) return [];
  const requests: RetroRequest[] = [];
  for (const period of input.periods) {
    if (period.periodEnd < input.effectiveDate) continue;
    const request = requestForPeriod(period, input.changeSetId);
    if (request) requests.push(request);
  }
  return requests;
}

/**
 * A past move into another province, after approval, asks for retro for each person in a finalized period (CORE-022).
 * Before approval the dialog only shows the tax change and that retro will be needed.
 */
export function provinceMoveRetro(input: {
  changeSetId: string;
  effectiveDate: string;
  today: string;
  fromProvince: string;
  toProvince: string;
  approved: boolean;
  employees: readonly { personId: string; employmentId: string; resultId: string; periodStart: string; periodEnd: string }[];
}): { taxProvinceChange: boolean; retroEstimate: boolean; requests: RetroRequest[] } {
  const taxProvinceChange = input.fromProvince !== input.toProvince;
  const pastFinalized = input.effectiveDate < input.today && input.employees.length > 0;
  const retroEstimate = taxProvinceChange && pastFinalized;
  if (!input.approved || !retroEstimate) return { taxProvinceChange, retroEstimate, requests: [] };
  return {
    taxProvinceChange,
    retroEstimate,
    requests: input.employees.map((employee) => ({
      personId: employee.personId,
      employmentId: employee.employmentId,
      originalResultId: employee.resultId,
      triggerChangeSetId: input.changeSetId,
      periodStart: employee.periodStart,
      periodEnd: employee.periodEnd,
      originalPayDate: employee.periodEnd,
      source: "stored" as const,
      status: "queued" as const,
      differences: [],
    })),
  };
}

/** After a locked run is finalized, a newer edition or agreement creates retro where the result would change (docs/06 §8). */
export function retroAfterRuleActivation(input: {
  finalized: boolean;
  coversLockedPeriod: boolean;
  pinnedHashes: readonly string[];
  activatedHash: string;
  resultDiffers: boolean;
}): boolean {
  if (!input.finalized || !input.coversLockedPeriod || !input.resultDiffers) return false;
  return !input.pinnedHashes.includes(input.activatedHash);
}

/** Edits after the lock do not change that run. They become retro only once it is finalized (docs/06 §10 test 11). */
export function changeAfterLock(input: {
  inputsKnownAt: string;
  committedAt: string;
  affectsWorkPeriod: boolean;
  touches: readonly string[];
  finalized: boolean;
}): { resultsUnchanged: true; retroAfterFinalization: boolean } {
  const later = input.committedAt > input.inputsKnownAt;
  const relevant = later && input.affectsWorkPeriod && input.touches.some((touch) => RETRO_TOUCHES.has(touch));
  return { resultsUnchanged: true, retroAfterFinalization: relevant && input.finalized };
}

export function retroFromAgreement(input: {
  changeSetId: string;
  retroFrom: string;
  ratificationDate: string;
  eligiblePopulation: EligiblePopulation;
  applicationDays?: number;
  employees: readonly EmployeeForRetro[];
}): RetroRequest[] {
  const rule = {
    eligiblePopulation: input.eligiblePopulation,
    retroFrom: input.retroFrom,
    ratificationDate: input.ratificationDate,
    applicationDays: input.applicationDays,
  };
  const requests: RetroRequest[] = [];
  for (const employee of input.employees) {
    if (!isEligible(employee, rule)) continue;
    for (const period of employee.periods) {
      if (period.periodEnd < input.retroFrom) continue;
      const request = requestForPeriod(period, input.changeSetId);
      if (request) requests.push(request);
    }
  }
  return requests;
}

export function planBatches(employeeIds: readonly string[], size = RETRO_BATCH_SIZE): RetroBatch[] {
  if (size !== RETRO_BATCH_SIZE) throw new RetroError("BATCH_SIZE");
  const batches: RetroBatch[] = [];
  for (let index = 0; index < employeeIds.length; index += size) {
    batches.push({
      batch: batches.length,
      employeeIds: employeeIds.slice(index, index + size),
      status: "queued",
      cost: "0.00",
    });
  }
  return batches;
}

/** One queue message per batch. A batch that is already calculated is not written again. */
export function processBatch(batches: readonly RetroBatch[], batch: number, cost: string): { batches: RetroBatch[]; wrote: boolean } {
  const next = batches.map((row) => ({ ...row, employeeIds: [...row.employeeIds] }));
  const found = next.find((row) => row.batch === batch);
  if (!found) throw new RetroError("BATCH_NOT_FOUND");
  if (found.status === "calculated") return { batches: next, wrote: false };
  found.status = "calculated";
  found.cost = cents(cost);
  return { batches: next, wrote: true };
}

export function progressView(input: { batches: readonly RetroBatch[]; totalEmployees: number; exceptions: number }): ProgressView {
  const done = input.batches.filter((batch) => batch.status === "calculated").reduce((total, batch) => total + batch.employeeIds.length, 0);
  const cost = input.batches.reduce((total, batch) => add(total, batch.cost), "0.00");
  return { done, total: input.totalEmployees, cost, exceptions: input.exceptions, paid: false };
}

/**
 * Retro earnings are paid as non-periodic lines, taxed in the year of the pay date (docs/06 §6).
 * Nothing is paid until the retro run is approved (PAY-021).
 */
export function payRetro(input: {
  requests: readonly RetroRequest[];
  approved: boolean;
  payDate: string;
  runId: string;
  qualifiesForT1198: boolean;
}): { lines: PayableLine[]; requests: RetroRequest[]; letter?: T1198Letter } {
  if (!input.approved) throw new RetroError("RETRO_RUN_NOT_APPROVED");
  const taxYear = taxYearOf(input.payDate);
  const lines: PayableLine[] = [];
  let priorYear = "0.00";
  const requests = input.requests.map((request) => {
    if (request.status === "overpayment_held" || request.status === "paid" || request.status === "no_difference") return request;
    for (const difference of request.differences) {
      if (difference.kind !== "earnings" || isNegative(difference.amount) || isZero(difference.amount)) continue;
      if (taxYearOf(request.originalPayDate) < taxYear) priorYear = add(priorYear, difference.amount);
      lines.push({
        payCode: difference.payCode,
        amount: difference.amount,
        workPeriodStart: request.periodStart,
        workPeriodEnd: request.periodEnd,
        retroOf: request.originalResultId,
        taxMethod: "non_periodic",
        taxYear,
        t4Year: taxYear,
      });
    }
    return { ...request, status: "paid" as const, paidInResultId: input.runId };
  });
  const letter =
    input.qualifiesForT1198 && compareAtLeast(priorYear, "3000.00")
      ? { form: "T1198" as const, taxYear, amount: priorYear }
      : undefined;
  return { lines, requests, letter };
}

function compareAtLeast(value: string, floor: string): boolean {
  return !isNegative(sub(value, floor));
}

/** A closed grant is charged to the successor, the fallback, or suspense, and listed on the funder report (ENT-014). */
export function chargeRetro(input: { amount: string; workDate: string; source: FundingSource }): {
  fundingSourceId: string;
  adjustment: FunderAdjustment | null;
} {
  const amount = cents(input.amount);
  if (!input.source.closed && !input.source.periodFinal) {
    return { fundingSourceId: input.source.id, adjustment: null };
  }
  const policy = input.source.postClosePolicy;
  const toSourceId = policy === "successor" ? input.source.successorId : policy === "fallback" ? input.source.fallbackId : "suspense";
  if (!toSourceId) throw new RetroError(policy === "successor" ? "SUCCESSOR_REQUIRED" : "FALLBACK_REQUIRED");
  return {
    fundingSourceId: toSourceId,
    adjustment: {
      workDate: input.workDate,
      amount,
      fromSourceId: input.source.id,
      toSourceId,
      policy,
    },
  };
}

export interface Reversal {
  reversesResultId: string;
  lines: PayLine[];
  ytd: { code: string; amount: string }[];
  gl: { glAccount: string; amount: string }[];
  runType: "reversal";
}

/** Reversal of a finalized off-cycle payment negates the result, restores YTD, and reverses the GL (PAY-022). */
export function reverseResult(input: {
  resultId: string;
  lines: readonly PayLine[];
  ytd: readonly { code: string; amount: string }[];
  gl: readonly { glAccount: string; amount: string }[];
}): Reversal {
  return {
    reversesResultId: input.resultId,
    runType: "reversal",
    lines: input.lines.map((line) => ({ payCode: line.payCode, amount: sub("0.00", line.amount) })),
    ytd: input.ytd.map((row) => ({ code: row.code, amount: sub("0.00", row.amount) })),
    gl: input.gl.map((row) => ({ glAccount: row.glAccount, amount: sub("0.00", row.amount) })),
  };
}

export interface ReplaySampleItem {
  resultId: string;
  rulesAffected: boolean;
}

/** At least 0.5% of yesterday's results, plus every result touched by a new rule (PAY-053). */
export function replaySample(
  results: readonly ReplaySampleItem[],
  pick: (ids: readonly string[], count: number) => readonly string[],
): string[] {
  const count = Math.ceil(results.length * 0.005);
  const chosen = new Set(pick(results.map((row) => row.resultId), count));
  for (const row of results) if (row.rulesAffected) chosen.add(row.resultId);
  return [...chosen];
}

export interface ReplayAlert {
  ok: false;
  severity: 1;
  resultId: string;
  engineVersion: string;
  changed: false;
}

/** A mismatched replay blocks that engine version. It does not change the stored result (docs/06 §10 test 15). */
export function compareReplay(input: {
  resultId: string;
  storedSha: string;
  replaySha: string;
  engineVersion: string;
  blocked: ReadonlySet<string>;
}): { ok: true } | ReplayAlert {
  if (input.blocked.has(input.engineVersion)) throw new RetroError("ENGINE_VERSION_BLOCKED");
  if (input.storedSha === input.replaySha) return { ok: true };
  return { ok: false, severity: 1, resultId: input.resultId, engineVersion: input.engineVersion, changed: false };
}

export function blockEngine(blocked: ReadonlySet<string>, version: string): Set<string> {
  const next = new Set(blocked);
  next.add(version);
  return next;
}

export function emptySnapshot(lines: readonly PayLine[] = []): MoneySnapshot {
  return { ...ZERO_SNAPSHOT, lines };
}
