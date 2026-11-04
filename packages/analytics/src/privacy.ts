import { addDays, addYears } from "./dates.ts";
import { D, fixed, money } from "./decimal.ts";
import { fail } from "./errors.ts";
import { suppressGroups } from "./reports.ts";
import { sameTenant } from "./routes.ts";
import { screen, type ScreenLang } from "./text.ts";

export function openAccessRequest(input: {
  receivedOn: string;
  dueDays: number | null;
  fields: readonly { name: string; value: string; redact: boolean }[];
  lang: ScreenLang;
}): { dueOn: string; fields: { name: string; value: string }[] } {
  if (input.dueDays === null) fail("JURISDICTION_RULE_MISSING");
  const fields = input.fields.map((field) => ({
    name: field.name,
    value: field.redact ? screen[input.lang].redacted : field.value,
  }));
  return { dueOn: addDays(input.receivedOn, input.dueDays), fields };
}

/** Delivery log stores identifiers only. */
export function deliverAccess(input: { requestId: string; fieldNames: readonly string[] }): { requestId: string; fields: string[] } {
  return { requestId: input.requestId, fields: [...input.fieldNames] };
}

export function retentionRun(input: {
  rule: { status: string; payroll_records_years: number | null };
  asOf: string;
  records: readonly { id: string; on: string; taxYearEnd: string; legalHold: boolean }[];
}): { destroy: string[]; blocked: string | null; preview: string[] } {
  if (input.rule.payroll_records_years === null) fail("JURISDICTION_RULE_MISSING");
  const preview: string[] = [];
  for (const record of input.records) {
    if (record.legalHold) continue;
    const sunset = addYears(record.taxYearEnd, input.rule.payroll_records_years);
    if (record.on > sunset) preview.push(record.id);
  }
  if (input.rule.status === "verify_at_load") return { destroy: [], blocked: "RULE_NOT_VERIFIED", preview };
  return { destroy: preview, blocked: null, preview };
}

export function moveOutsideQuebec(input: { quebecResidents: boolean; piaRecorded: boolean }): { allowed: true } {
  if (input.quebecResidents && !input.piaRecorded) fail("INPUT_REQUIRED", "privacy impact assessment");
  return { allowed: true };
}

export function logIncident(input: { id: string; on: string }): { id: string; on: string } {
  return { id: input.id, on: input.on };
}

export type TenantStore = { dedicated: boolean; supportGranted: boolean; rows: readonly { id: string }[] };

export function setDedicatedDatabase(store: TenantStore): TenantStore {
  return { dedicated: true, supportGranted: store.supportGranted, rows: store.rows };
}

export function grantSupport(store: TenantStore): TenantStore {
  return { dedicated: store.dedicated, supportGranted: true, rows: store.rows };
}

export function revokeSupport(store: TenantStore): TenantStore {
  return { dedicated: store.dedicated, supportGranted: false, rows: store.rows };
}

export function exportTenant(store: TenantStore, asSupport: boolean): { id: string }[] {
  if (asSupport && !store.supportGranted) return [];
  return store.rows.map((row) => ({ id: row.id }));
}

export function recordSelfId(input: { consentVersion: string | null; categories: readonly string[] }): {
  encrypted: true;
  categories: string[];
} {
  if (input.consentVersion === null || input.consentVersion.length === 0) fail("INPUT_REQUIRED");
  return { encrypted: true, categories: [...input.categories] };
}

export function equityAggregate(input: { cells: readonly { id: string; count: number }[]; minimum: number }): {
  shown: string[];
  suppressed: string[];
} {
  return suppressGroups(input.cells, input.minimum);
}

export function managerEquityView(): { people: [] } {
  return { people: [] };
}

export function accommodationView(input: { role: string; medical: string; limitations: string; measures: string }): {
  medical?: string;
  limitations: string;
  measures: string;
} {
  if (input.role === "manager") return { limitations: input.limitations, measures: input.measures };
  if (input.role === "hr") return { medical: input.medical, limitations: input.limitations, measures: input.measures };
  fail("INPUT_REQUIRED");
}

export function attendanceTotal(absences: readonly { days: string; accommodationRelated: boolean }[]): string {
  let total = new D(0);
  for (const row of absences) {
    if (row.accommodationRelated) continue;
    total = total.plus(row.days);
  }
  return fixed(total, 2);
}

export function recordIncident(input: {
  facts: string;
  medical: string | null;
  role: string;
  on: string;
  notifyDays: number | null;
  ruleStatus: string | null;
  lostTime: boolean;
  topUpRule: string | null;
  topUpAmount: string | null;
}): {
  facts: string;
  medical: string | null;
  deadline: string | null;
  deadlineStatus: string | null;
  topUpRule: string | null;
  topUpAmount: string | null;
} {
  if (input.lostTime && (input.topUpRule === null || input.topUpAmount === null)) fail("INPUT_REQUIRED");
  const unverified = input.notifyDays === null || input.ruleStatus === "verify_at_load";
  let deadline: string | null = null;
  if (!unverified && input.notifyDays !== null) deadline = addDays(input.on, input.notifyDays);
  return {
    facts: input.facts,
    medical: input.role === "manager" ? null : input.medical,
    deadline,
    deadlineStatus: unverified ? "RULE_NOT_VERIFIED" : null,
    topUpRule: input.lostTime ? input.topUpRule : null,
    topUpAmount: input.lostTime && input.topUpAmount !== null ? money(input.topUpAmount) : null,
  };
}

export function funderView(input: { source: string; lines: readonly { source: string; amount: string }[] }): {
  source: string;
  amount: string;
}[] {
  const out: { source: string; amount: string }[] = [];
  for (const line of input.lines) {
    if (line.source !== input.source) continue;
    out.push({ source: line.source, amount: money(line.amount) });
  }
  return out;
}

export function readAnalytics<T>(recordTenant: string, readerTenant: string, rows: readonly T[]): T[] {
  return sameTenant(recordTenant, readerTenant, rows);
}
