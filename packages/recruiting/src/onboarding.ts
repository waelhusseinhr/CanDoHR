import { shiftDays } from "./dates.ts";
import { RecruitError } from "./errors.ts";
import { employmentStandard, ruleInt, type StandardsBundle } from "./standards.ts";

export type PlanItem = {
  itemCode: string;
  phase: string;
  ownerKind: string;
  dueEvent: string;
  dueOffsetDays: number;
  required: boolean;
  extra: string | null;
  formCode: string | null;
};

export type Extras = Record<string, { enabled: boolean; required: boolean }>;

export function generateTasks(items: PlanItem[], extras: Extras, startDate: string): {
  itemCode: string;
  ownerKind: string;
  dueOn: string | null;
  required: boolean;
  formCode: string | null;
}[] {
  const generated = new Map<string, { itemCode: string; ownerKind: string; dueOn: string | null; required: boolean; formCode: string | null }>();
  for (const item of items) {
    if (item.extra && !extras[item.extra]?.enabled) continue;
    const dueOn = item.dueEvent === "start_date" || item.dueEvent === "contract_signed" ? shiftDays(startDate, item.dueOffsetDays) : null;
    const required = item.required || Boolean(item.extra && extras[item.extra]?.required);
    const existing = generated.get(item.itemCode);
    const task = { itemCode: item.itemCode, ownerKind: item.ownerKind, dueOn, required, formCode: item.formCode };
    if (!existing || (dueOn && (!existing.dueOn || dueOn < existing.dueOn))) generated.set(item.itemCode, task);
  }
  return [...generated.values()];
}

export function legalDue(bundle: StandardsBundle, startDate: string, organizationDue: string): { organizationDue: string; legalDue: string } {
  const rule = employmentStandard(bundle, null, "sin_due");
  const legalDueOn = shiftDays(startDate, ruleInt(rule, "days_after_start"));
  if (organizationDue > legalDueOn) throw new RecruitError("DUE_AFTER_LEGAL_DATE");
  return { organizationDue, legalDue: legalDueOn };
}

export function waiveLegalTask(): never {
  throw new RecruitError("LEGAL_TASK_CANNOT_BE_WAIVED");
}

export function preboardingAccess(asOf: string, startDate: string): { scopes: string[] } {
  if (asOf < startDate) return { scopes: ["preboarding"] };
  return { scopes: ["preboarding", "employee"] };
}

export function section87(answer: boolean, firstPay: string, exemptionRecorded: boolean): {
  hrTaskDue: string | null;
  deductionsContinue: boolean;
} {
  if (!answer) return { hrTaskDue: null, deductionsContinue: true };
  return { hrTaskDue: shiftDays(firstPay, -1), deductionsContinue: !exemptionRecorded };
}

export type Escalation = { ownerReminderDaysBefore: number; managerAfterDaysOverdue: number; hrAfterDaysOverdue: number };

export function escalationLevel(dueOn: string, asOf: string, setting: Escalation, current: number): { level: number; notify: "owner" | "owner_manager" | "hr" } | null {
  let level = 0;
  if (asOf >= shiftDays(dueOn, -setting.ownerReminderDaysBefore)) level = 1;
  if (asOf >= shiftDays(dueOn, setting.managerAfterDaysOverdue)) level = 2;
  if (asOf >= shiftDays(dueOn, setting.hrAfterDaysOverdue)) level = 3;
  if (level <= current) return null;
  const notify = level === 1 ? "owner" : level === 2 ? "owner_manager" : "hr";
  return { level, notify };
}

export type SupportRole = "buddy" | "mentor" | "trainer";

export function addSupporter(input: {
  role: SupportRole;
  supporterId: string;
  hireId: string;
  scopeNote: string;
  from: string;
  to: string;
  buddyEnabled: boolean;
}): { role: SupportRole; supporterId: string; scopeNote: string; from: string; to: string } {
  if (input.supporterId === input.hireId) throw new RecruitError("SUPPORT_SELF");
  if (input.role === "buddy" && !input.buddyEnabled) throw new RecruitError("FEATURE_OFF");
  return { role: input.role, supporterId: input.supporterId, scopeNote: input.scopeNote, from: input.from, to: input.to };
}

export function suggestSupporters(people: { personId: string; unitId: string; locationId: string }[], hire: { personId: string; unitId: string; locationId: string }): { personId: string; reason: "same_org_unit" | "same_location" }[] {
  const suggested = people.filter((person) => person.personId !== hire.personId && (person.unitId === hire.unitId || person.locationId === hire.locationId));
  return suggested
    .map((person) => ({ personId: person.personId, reason: person.unitId === hire.unitId ? "same_org_unit" as const : "same_location" as const }))
    .sort((left, right) => Number(left.reason !== "same_org_unit") - Number(right.reason !== "same_org_unit"));
}

export function completeTask(signedBy: string | undefined): { status: "done"; signedBy: string } {
  if (!signedBy) throw new RecruitError("TASK_COMPLETION_UNSIGNED");
  return { status: "done", signedBy };
}
