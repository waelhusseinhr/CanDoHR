import { createHash } from "node:crypto";
import { RulesError, selectScopedRule, validate, type ScopeContext, type ScopedRule } from "@candohr/rules";
import { addDays, daysBetween } from "./dates.ts";
import { D, money } from "./decimal.ts";
import { fail } from "./errors.ts";
import { screen, type ScreenLang } from "./text.ts";

export function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

export function importAgreement(input: {
  bytes: Uint8Array;
  registryRef: string | null;
  bargainingUnitIds: readonly string[];
  legalEntityIds: readonly string[];
}): { sha256: string; registryRef: string; bargainingUnitIds: string[]; legalEntityIds: string[] } {
  if (input.bytes.byteLength === 0) fail("INPUT_REQUIRED");
  if (input.registryRef === null || input.registryRef.length === 0) fail("INPUT_REQUIRED");
  if (input.bargainingUnitIds.length === 0 || input.legalEntityIds.length === 0) fail("INPUT_REQUIRED");
  return {
    sha256: sha256(input.bytes),
    registryRef: input.registryRef,
    bargainingUnitIds: [...input.bargainingUnitIds],
    legalEntityIds: [...input.legalEntityIds],
  };
}

export type ProposedRule = {
  id: string;
  article: string;
  quote: string;
  extracted_by: "ai";
  verified: boolean;
};

export function proposeRules(extracted: readonly { id: string; article: string; quote: string }[]): ProposedRule[] {
  return extracted.map((rule) => ({
    id: rule.id,
    article: rule.article,
    quote: rule.quote,
    extracted_by: "ai",
    verified: false,
  }));
}

export function verifyRule<T extends { verified: boolean }>(
  rule: T,
  verifierId: string | null,
  clause: string,
  quote: string,
): T & { verified: true; verifierId: string; clause: string; quote: string } {
  if (verifierId === null || verifierId.length === 0) fail("INPUT_REQUIRED");
  return { ...rule, verified: true, verifierId, clause, quote };
}

export function combinationQuestion(detail: string, lang: ScreenLang): string {
  if (detail === "weekly+holiday") return screen[lang].weeklyHoliday;
  if (detail.includes("second_rest_day") && detail.includes("holiday")) return screen[lang].restDayHoliday;
  return `${screen[lang].unresolved} ${detail}`;
}

export function openCombinations(
  rules: Record<string, unknown>,
  lang: ScreenLang,
): { code: string; detail: string; question: string | null }[] {
  const problems = validate(rules as never);
  return problems
    .filter((problem) => problem.code === "UNRESOLVED_INTERACTION" || problem.code === "INCONSISTENT_INTERACTION")
    .map((problem) => ({
      code: problem.code,
      detail: problem.detail,
      question: problem.code === "UNRESOLVED_INTERACTION" ? combinationQuestion(problem.detail, lang) : null,
    }));
}

export function recordCombinationAnswer(input: { detail: string; article: string | null; by: string | null }): {
  detail: string;
  article: string;
  by: string;
} {
  if (input.article === null || input.article.length === 0 || input.by === null || input.by.length === 0) fail("INPUT_REQUIRED");
  return { detail: input.detail, article: input.article, by: input.by };
}

export function explainPayLine(input: { articles: readonly string[]; sources: readonly string[] }): { text: string } {
  if (input.articles.length === 0) fail("INPUT_REQUIRED");
  return { text: `${input.sources.join(", ")}: ${input.articles.join(", ")}` };
}

export function activateAgreement(input: {
  ruleRows: readonly { verified: boolean }[];
  approverIds: readonly string[];
  agreementRules: Record<string, unknown> | null;
  answers: readonly { detail: string; article: string; by: string }[];
}): { activated: true } {
  for (const row of input.ruleRows) {
    if (!row.verified) fail("UNVERIFIED_RULES");
  }
  const people = new Set(input.approverIds);
  if (people.size < 2) fail("INPUT_REQUIRED");
  if (input.agreementRules !== null) {
    const problems = validate(input.agreementRules as never);
    for (const problem of problems) {
      if (problem.code === "INCONSISTENT_INTERACTION") fail("INCONSISTENT_INTERACTION", problem.detail);
      if (problem.code === "UNRESOLVED_INTERACTION") {
        const answer = input.answers.find((item) => item.detail === problem.detail);
        if (answer === undefined || answer.article.length === 0 || answer.by.length === 0) {
          fail("UNRESOLVED_INTERACTION", problem.detail);
        }
      }
    }
  }
  return { activated: true };
}

export function renewAgreement(
  previous: readonly { id: string; verified: boolean; text: string }[],
  edits: readonly { id: string; text: string }[],
): { rules: { id: string; verified: boolean; text: string }[]; changed: string[] } {
  const changed: string[] = [];
  const rules = previous.map((rule) => {
    const edit = edits.find((item) => item.id === rule.id);
    if (edit !== undefined && edit.text !== rule.text) {
      changed.push(rule.id);
      return { id: rule.id, text: edit.text, verified: false };
    }
    return { id: rule.id, text: rule.text, verified: rule.verified };
  });
  return { rules, changed };
}

export function retroPreview(input: { retroFrom: string | null; lines: readonly { id: string; cost: string }[] }): {
  requestIds: string[];
  total: string;
  applied: false;
} {
  if (input.retroFrom === null) return { requestIds: [], total: money("0"), applied: false };
  let total = new D(0);
  const requestIds: string[] = [];
  for (const line of input.lines) {
    requestIds.push(line.id);
    total = total.plus(line.cost);
  }
  return { requestIds, total: money(total.toFixed(2)), applied: false };
}

export function sandboxCost(people: readonly { id: string; before: string; after: string }[]): {
  lines: { id: string; before: string; after: string; delta: string }[];
  totalDelta: string;
} {
  const lines: { id: string; before: string; after: string; delta: string }[] = [];
  let total = new D(0);
  for (const person of people) {
    const delta = new D(person.after).minus(person.before);
    total = total.plus(delta);
    lines.push({ id: person.id, before: money(person.before), after: money(person.after), delta: money(delta.toFixed(2)) });
  }
  return { lines, totalDelta: money(total.toFixed(2)) };
}

export function resolveScope<T extends ScopedRule>(rules: T[], ctx: ScopeContext, family: string): T | null {
  try {
    return selectScopedRule(rules, ctx, family);
  } catch (error) {
    if (error instanceof RulesError) fail(error.code, error.detail);
    throw error;
  }
}

export function applyPattern(agreementIds: readonly string[]): { agreementId: string; verified: false; activated: false }[] {
  return agreementIds.map((agreementId) => ({ agreementId, verified: false, activated: false }));
}

export function reorgGroupings(
  people: readonly {
    id: string;
    openLayoff: boolean;
    openBumping: boolean;
    openRecall: boolean;
    startedGrouping: string;
    nextGrouping: string;
  }[],
): { id: string; grouping: string }[] {
  return people.map((person) => ({
    id: person.id,
    grouping: person.openLayoff || person.openBumping || person.openRecall ? person.startedGrouping : person.nextGrouping,
  }));
}

export function transferPositions(input: {
  positionIds: readonly string[];
  gridConfirmed: boolean;
  seniorityTerms: string | null;
  effectiveOn: string;
  grievanceIds: readonly string[];
}): { changeSets: number; positionCount: number; duesFrom: string; grievanceIds: string[]; seniorityConverted: boolean } {
  if (!input.gridConfirmed || input.seniorityTerms === null) fail("INPUT_REQUIRED");
  return {
    changeSets: 1,
    positionCount: input.positionIds.length,
    duesFrom: input.effectiveOn,
    grievanceIds: [...input.grievanceIds],
    seniorityConverted: true,
  };
}

export function openGrievance(input: {
  article: string | null;
  stepDays: number | null;
  openedOn: string;
  meetings: readonly string[];
  outcome: string | null;
  documents: readonly string[];
}): { article: string; deadline: string; meetings: string[]; outcome: string | null; documents: string[] } {
  if (input.article === null || input.stepDays === null) fail("INPUT_REQUIRED");
  return {
    article: input.article,
    deadline: addDays(input.openedOn, input.stepDays),
    meetings: [...input.meetings],
    outcome: input.outcome,
    documents: [...input.documents],
  };
}

export function grievanceAlert(input: { role: string; asOf: string; deadline: string; remindDays: number | null }): {
  visible: boolean;
  alert: boolean;
} {
  if (input.role !== "lr") return { visible: false, alert: false };
  if (input.remindDays === null) fail("SETTING_NOT_SET");
  const days = daysBetween(input.asOf, input.deadline);
  return { visible: true, alert: days >= 0 && days <= input.remindDays };
}

export function strikeSchedule(input: { strike: boolean; scheduled: number; required: number | null }): {
  allowed: boolean;
  shortfall: number;
  payrollStopped: boolean;
} {
  if (!input.strike) return { allowed: true, shortfall: 0, payrollStopped: false };
  if (input.required === null) fail("INPUT_REQUIRED");
  if (input.scheduled < input.required) {
    return { allowed: false, shortfall: input.required - input.scheduled, payrollStopped: true };
  }
  return { allowed: true, shortfall: 0, payrollStopped: true };
}
