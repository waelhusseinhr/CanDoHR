import { addMonths, daysBetween, lastDay } from "./dates.ts";
import { D } from "./decimal.ts";
import { fail } from "./errors.ts";
import { completeRoute, sameTenant, type Approval } from "./routes.ts";
import { screen, type ScreenLang } from "./text.ts";

export type DueRule = { month: number; day: number | string };

export type ReportRule = {
  min_employees?: number | null;
  due?: DueRule;
  first_year?: number;
  form_status: string;
  cite?: string;
  source_data?: string;
  who?: string;
};

export function filingDue(entry: { due?: DueRule; form_status: string }, year: number): string {
  if (entry.due === undefined) fail("RULE_NOT_VERIFIED");
  if (entry.due.day === "last") return lastDay(year, entry.due.month);
  if (typeof entry.due.day !== "number") fail("RULE_NOT_VERIFIED");
  const month = String(entry.due.month).padStart(2, "0");
  const day = String(entry.due.day).padStart(2, "0");
  return `${String(year)}-${month}-${day}`;
}

/** Filing a statutory form is refused while the entry is still check-before-use. No form is built from memory. */
export function fileStatutoryReport(entry: { form_status: string }): never {
  if (entry.form_status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  fail("RULE_NOT_VERIFIED");
}

export function bcPayTransparency(input: { report: ReportRule; employeeCount: number; asOf: string }): {
  produced: boolean;
  dueOn: string | null;
  filed: false;
} {
  if (input.report.min_employees == null || input.report.due === undefined) fail("RULE_NOT_VERIFIED");
  const year = Number(input.asOf.slice(0, 4));
  const countOk = input.employeeCount >= input.report.min_employees;
  const yearOk = input.report.first_year === undefined || year >= input.report.first_year;
  if (!countOk || !yearOk) return { produced: false, dueOn: null, filed: false };
  let dueOn = filingDue(input.report, year);
  if (dueOn < input.asOf) dueOn = filingDue(input.report, year + 1);
  return { produced: true, dueOn, filed: false };
}

export function federalEquityReports(input: {
  reports: Record<string, { form_status: string }>;
  federallyRegulated: boolean;
}): { code: string; filed: false; formStatus: string }[] {
  if (!input.federallyRegulated) return [];
  const codes = ["FED_PAY_EQUITY", "FED_EMPLOYMENT_EQUITY"];
  const out: { code: string; filed: false; formStatus: string }[] = [];
  for (const code of codes) {
    const report = input.reports[code];
    if (report === undefined) fail("RULE_NOT_VERIFIED", code);
    out.push({ code, filed: false, formStatus: report.form_status });
  }
  return out;
}

export function statutoryCatalogue(input: {
  reports: Record<string, { cite?: string; form_status?: string; source_data?: string }>;
  statutes: Record<string, { cite?: string; status?: string; basis?: string }>;
}): { code: string; cite: string; status: string; source: string }[] {
  const out: { code: string; cite: string; status: string; source: string }[] = [];
  for (const [code, report] of Object.entries(input.reports)) {
    if (report.cite === undefined || report.form_status === undefined || report.source_data === undefined) {
      fail("RULE_NOT_VERIFIED", code);
    }
    out.push({ code, cite: report.cite, status: report.form_status, source: report.source_data });
  }
  for (const [code, statute] of Object.entries(input.statutes)) {
    if (statute.cite === undefined || statute.status === undefined || statute.basis === undefined) {
      fail("RULE_NOT_VERIFIED", code);
    }
    out.push({ code, cite: statute.cite, status: statute.status, source: statute.basis });
  }
  return out;
}

export function complianceCalendar(input: {
  entityId: string;
  year: number;
  asOf: string;
  remindDaysBefore: number | null;
  ownerId: string | null;
  entries: readonly { code: string; due?: DueRule; form_status: string }[];
}): {
  entityId: string;
  items: { code: string; dueOn: string | null; ownerId: string; remind: boolean; blocked: string | null }[];
} {
  if (input.ownerId === null) fail("INPUT_REQUIRED");
  if (input.remindDaysBefore === null) fail("SETTING_NOT_SET");
  const items: { code: string; dueOn: string | null; ownerId: string; remind: boolean; blocked: string | null }[] = [];
  for (const entry of input.entries) {
    if (entry.due === undefined) {
      items.push({ code: entry.code, dueOn: null, ownerId: input.ownerId, remind: false, blocked: "RULE_NOT_VERIFIED" });
      continue;
    }
    const dueOn = filingDue(entry, input.year);
    const daysUntil = daysBetween(input.asOf, dueOn);
    const remind = daysUntil > 0 && daysUntil <= input.remindDaysBefore;
    items.push({ code: entry.code, dueOn, ownerId: input.ownerId, remind, blocked: null });
  }
  return { entityId: input.entityId, items };
}

/** Cells under the minimum are hidden. Exactly one hidden cell also hides the smallest remaining cell. */
export function suppressGroups(
  cells: readonly { id: string; count: number }[],
  minimum: number,
): { shown: string[]; suppressed: string[] } {
  const suppressed: { id: string; count: number }[] = [];
  const shown: { id: string; count: number }[] = [];
  for (const cell of cells) {
    if (cell.count < minimum) suppressed.push(cell);
    else shown.push(cell);
  }
  if (suppressed.length === 1 && shown.length > 0) {
    let smallest = shown[0];
    for (const cell of shown) {
      if (cell.count < smallest.count) smallest = cell;
    }
    return {
      shown: shown.filter((cell) => cell.id !== smallest.id).map((cell) => cell.id),
      suppressed: [...suppressed.map((cell) => cell.id), smallest.id],
    };
  }
  return { shown: shown.map((cell) => cell.id), suppressed: suppressed.map((cell) => cell.id) };
}

export function payGapReport(input: {
  floor: number | null;
  minimumFloor: number | null;
  allowed: readonly string[];
  groups: readonly { id: string; category: string; count: number; consented: boolean }[];
}): { id: string; hidden: boolean }[] {
  if (input.floor === null || input.minimumFloor === null) fail("SETTING_NOT_SET");
  if (input.floor < input.minimumFloor) fail("SETTING_BELOW_MINIMUM");
  const out: { id: string; hidden: boolean }[] = [];
  for (const group of input.groups) {
    if (!input.allowed.includes(group.category)) fail("LIST_VALUE_UNKNOWN", group.category);
    out.push({ id: group.id, hidden: !group.consented || group.count < input.floor });
  }
  return out;
}

export type DisclosurePerson = { id: string; paid: string; inPopulation?: boolean };

export type DisclosureStatute = { threshold: number | null; status: string };

export function draftSalaryDisclosure(input: {
  statute: DisclosureStatute;
  people: readonly DisclosurePerson[];
  publish: boolean;
  preparerId?: string;
  route?: { steps: readonly { role: string }[]; approvals: readonly Approval[] };
}): { listed: string[]; published: boolean } {
  const listed = disclosureList(input.statute, input.people);
  if (!input.publish) return { listed, published: false };
  if (input.preparerId === undefined || input.route === undefined) fail("INPUT_REQUIRED");
  if (input.route.steps.length === 0) fail("INPUT_REQUIRED");
  for (const approval of input.route.approvals) {
    if (approval.approverId === input.preparerId) fail("SELF_APPROVAL");
  }
  for (const role of ["hr", "finance"]) {
    const stepped = input.route.steps.some((step) => step.role === role);
    const approved = input.route.approvals.some((approval) => approval.role === role);
    if (!stepped || !approved) fail("DISCLOSURE_NOT_APPROVED");
  }
  completeRoute({
    steps: input.route.steps,
    approvals: input.route.approvals,
    blockedApproverIds: [input.preparerId],
  });
  if (input.statute.status === "verify_at_load") fail("RULE_NOT_VERIFIED");
  return { listed, published: true };
}

function disclosureList(statute: DisclosureStatute, people: readonly DisclosurePerson[]): string[] {
  const listed: string[] = [];
  if (statute.threshold === null) {
    for (const person of people) {
      if (person.inPopulation === undefined) fail("INPUT_REQUIRED");
      if (person.inPopulation) listed.push(person.id);
    }
    return listed;
  }
  const threshold = new D(String(statute.threshold));
  for (const person of people) {
    if (new D(person.paid).gte(threshold)) listed.push(person.id);
  }
  return listed;
}

export type ReportField = { name: string; value: string; access: "allow" | "deny" | "mask" };

export function buildReport(input: { fields: readonly ReportField[]; readable: readonly string[]; lang: ScreenLang }): {
  columns: { name: string; value: string }[];
} {
  const columns: { name: string; value: string }[] = [];
  for (const field of input.fields) {
    if (field.access === "deny") continue;
    if (!input.readable.includes(field.name)) continue;
    if (field.access === "mask") columns.push({ name: field.name, value: screen[input.lang].masked });
    else columns.push({ name: field.name, value: field.value });
  }
  return { columns };
}

export function biExport(input: {
  recordTenant: string;
  readerTenant: string;
  rows: readonly { fields: readonly ReportField[] }[];
  readable: readonly string[];
  lang: ScreenLang;
}): { columns: { name: string; value: string }[] }[] {
  const rows = sameTenant(input.recordTenant, input.readerTenant, input.rows);
  return rows.map((row) => buildReport({ fields: row.fields, readable: input.readable, lang: input.lang }));
}

/** Factors are supplied by the caller. This function does not compute a model score. */
export function explainRisk(input: { factors: readonly string[] | null }): { factors: string[]; modelScore: null } {
  if (input.factors === null) fail("INPUT_REQUIRED");
  return { factors: input.factors.slice(), modelScore: null };
}

export function applyEmploymentDecision(input: {
  humanReviewed: boolean;
  reviewEveryMonths: number | null;
  lastTestOn: string | null;
  asOf: string;
}): { decidedByPerson: true } {
  if (!input.humanReviewed) fail("INPUT_REQUIRED");
  if (input.reviewEveryMonths === null) fail("SETTING_NOT_SET");
  if (input.lastTestOn === null) fail("INPUT_REQUIRED");
  const due = addMonths(input.lastTestOn, input.reviewEveryMonths);
  if (input.asOf > due) fail("INPUT_REQUIRED", "disparate impact review");
  return { decidedByPerson: true };
}
