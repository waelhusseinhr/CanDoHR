import { daysBetween } from "./dates.ts";
import { D, money } from "./decimal.ts";
import { fail } from "./errors.ts";
import { screen, type ScreenLang } from "./text.ts";

export function explainPay(trace: readonly (readonly [string, string])[]): { text: string; values: string[] } {
  const parts: string[] = [];
  const values: string[] = [];
  for (const entry of trace) {
    const label = entry[0];
    const value = entry[1];
    values.push(value);
    parts.push(`${label}: ${value}`);
  }
  return { text: parts.join(". "), values };
}

export function compareNet(input: { previous: string; current: string; reasons: readonly string[] }): {
  delta: string;
  direction: "lower" | "higher" | "same";
  text: string;
} {
  const delta = new D(input.current).minus(input.previous);
  if (delta.isZero()) return { delta: money("0"), direction: "same", text: money("0") };
  if (input.reasons.length === 0) fail("INPUT_REQUIRED");
  const direction = delta.isNeg() ? "lower" : "higher";
  const amount = money(delta.abs().toFixed(2));
  return { delta: money(delta.toFixed(2)), direction, text: `${amount} ${input.reasons.join("; ")}` };
}

export function previewConsequences(changeSet: {
  id: string;
  operations: readonly { entity: string; field: string; before: string; after: string }[];
}): { changeSetId: string; consequences: { entity: string; field: string; before: string; after: string }[]; committed: false } {
  return {
    changeSetId: changeSet.id,
    consequences: changeSet.operations.map((operation) => ({
      entity: operation.entity,
      field: operation.field,
      before: operation.before,
      after: operation.after,
    })),
    committed: false,
  };
}

export function preRunChecks(input: {
  people: readonly {
    id: string;
    td1OnFile: boolean;
    rate: string | null;
    minimumWage: string | null;
    net: string | null;
    active: boolean;
    hasPay: boolean;
    bankChanged: boolean;
    payment: string | null;
  }[];
  largePayment: string | null;
}): { id: string; code: string }[] {
  const findings: { id: string; code: string }[] = [];
  for (const person of input.people) {
    if (!person.td1OnFile) findings.push({ id: person.id, code: "MISSING_TD1" });
    if (person.rate !== null) {
      if (person.minimumWage === null) fail("JURISDICTION_RULE_MISSING");
      if (new D(person.rate).lt(person.minimumWage)) findings.push({ id: person.id, code: "BELOW_MINIMUM_WAGE" });
    }
    if (person.net !== null && new D(person.net).isNeg()) findings.push({ id: person.id, code: "NEGATIVE_NET" });
    if (!person.active && person.hasPay) findings.push({ id: person.id, code: "INACTIVE_WITH_PAY" });
    if (person.bankChanged) {
      if (input.largePayment === null || person.payment === null) fail("SETTING_NOT_SET");
      if (new D(person.payment).gte(input.largePayment)) findings.push({ id: person.id, code: "BANK_CHANGE_LARGE_PAYMENT" });
    }
  }
  return findings;
}

export function anomalyChecks(input: {
  varianceThreshold: string | null;
  periods: readonly { id: string; previous: string; current: string }[];
  peerLimit: string | null;
  peers: readonly { id: string; amount: string }[];
  accounts: readonly { personId: string; accountHash: string }[];
}): { code: string; ids: string[] }[] {
  const findings: { code: string; ids: string[] }[] = [];
  if (input.periods.length > 0 && input.varianceThreshold === null) fail("SETTING_NOT_SET");
  const varied: string[] = [];
  for (const period of input.periods) {
    const previous = new D(period.previous);
    if (previous.isZero()) fail("INPUT_REQUIRED");
    const ratio = new D(period.current).minus(previous).abs().div(previous);
    if (input.varianceThreshold !== null && ratio.gt(input.varianceThreshold)) varied.push(period.id);
  }
  if (varied.length > 0) findings.push({ code: "PERIOD_VARIANCE", ids: varied });
  if (input.peers.length > 0 && input.peerLimit === null) fail("SETTING_NOT_SET");
  const outliers: string[] = [];
  if (input.peerLimit !== null) {
    const limit = new D(input.peerLimit);
    for (const peer of input.peers) {
      if (new D(peer.amount).gt(limit)) outliers.push(peer.id);
    }
  }
  if (outliers.length > 0) findings.push({ code: "PEER_OUTLIER", ids: outliers });
  const byHash = new Map<string, string[]>();
  for (const account of input.accounts) {
    const existing = byHash.get(account.accountHash);
    if (existing === undefined) byHash.set(account.accountHash, [account.personId]);
    else existing.push(account.personId);
  }
  const duplicates: string[] = [];
  for (const ids of byHash.values()) {
    if (ids.length > 1) {
      for (const id of ids) duplicates.push(id);
    }
  }
  if (duplicates.length > 0) findings.push({ code: "DUPLICATE_BANK", ids: duplicates });
  return findings;
}

export function reminders(input: {
  asOf: string;
  withinDays: number | null;
  items: readonly { id: string; kind: string; dueOn: string }[];
}): { id: string; kind: string; dueOn: string }[] {
  if (input.withinDays === null) fail("SETTING_NOT_SET");
  const due: { id: string; kind: string; dueOn: string }[] = [];
  for (const item of input.items) {
    const days = daysBetween(input.asOf, item.dueOn);
    if (days >= 0 && days <= input.withinDays) due.push({ id: item.id, kind: item.kind, dueOn: item.dueOn });
  }
  return due;
}

export function dataQuality(input: {
  asOf: string;
  staleDays: number | null;
  fields: readonly { unitId: string; field: string; missing: boolean; updatedOn: string | null; fixForm: string }[];
}): { unitId: string; field: string; fixForm: string; reason: "missing" | "stale" }[] {
  const issues: { unitId: string; field: string; fixForm: string; reason: "missing" | "stale" }[] = [];
  for (const field of input.fields) {
    if (field.missing) {
      issues.push({ unitId: field.unitId, field: field.field, fixForm: field.fixForm, reason: "missing" });
      continue;
    }
    if (field.updatedOn === null) fail("INPUT_REQUIRED");
    if (input.staleDays === null) fail("SETTING_NOT_SET");
    if (daysBetween(field.updatedOn, input.asOf) > input.staleDays) {
      issues.push({ unitId: field.unitId, field: field.field, fixForm: field.fixForm, reason: "stale" });
    }
  }
  return issues;
}

export function smartDefaults(input: {
  nextPeriodStart: string | null;
  locationProvince: string | null;
  agreementId: string | null;
}): { effectiveDate: string; taxProvince: string; agreementId: string } {
  if (input.nextPeriodStart === null || input.locationProvince === null || input.agreementId === null) fail("INPUT_REQUIRED");
  return { effectiveDate: input.nextPeriodStart, taxProvince: input.locationProvince, agreementId: input.agreementId };
}

/** A job description is assembled from the supplied NOC text and requirements. The words are not rewritten. */
export function draftJobDescription(input: {
  lead: string | null;
  duties: readonly string[];
  requirements: readonly string[];
}): { draft: true; source: "template"; text: string } {
  if (input.lead === null || input.lead.length === 0) fail("INPUT_REQUIRED");
  const lines = [input.lead, ...input.duties, ...input.requirements];
  return { draft: true, source: "template", text: lines.join("\n") };
}

export function inclusiveLanguage(input: { text: string; blockedWords: readonly string[] | null }): { flags: string[] } {
  if (input.blockedWords === null) fail("SETTING_NOT_SET");
  const flags: string[] = [];
  const lower = input.text.toLowerCase();
  for (const word of input.blockedWords) {
    if (word.length === 0) continue;
    if (lower.includes(word.toLowerCase())) flags.push(word);
  }
  return { flags };
}

export function postingAiDisclosure(input: {
  disclosureRequired: boolean | null;
  usesAiScreening: boolean;
  disclosed: boolean;
}): { ok: true } {
  if (input.disclosureRequired === null) fail("SETTING_NOT_SET");
  if (input.disclosureRequired && input.usesAiScreening && !input.disclosed) fail("INPUT_REQUIRED");
  return { ok: true };
}

export function enrolmentAnswer(input: {
  enabled: boolean;
  booklet: readonly { section: string; text: string }[];
  topic: string;
  asksForRecommendation: boolean;
  lang: ScreenLang;
}): { enabled: boolean; section: string | null; text: string | null; recommends: false } {
  if (!input.enabled) return { enabled: false, section: null, text: null, recommends: false };
  if (input.asksForRecommendation) {
    return { enabled: true, section: null, text: screen[input.lang].noRecommendation, recommends: false };
  }
  let found: { section: string; text: string } | null = null;
  for (const section of input.booklet) {
    if (section.section === input.topic || section.text.includes(input.topic)) found = section;
  }
  if (found === null) return { enabled: true, section: null, text: screen[input.lang].bookletGap, recommends: false };
  return { enabled: true, section: found.section, text: found.text, recommends: false };
}

export function writingHelp(input: {
  enabled: boolean;
  text: string;
  blockedWords: readonly string[] | null;
  asksForRating: boolean;
  asksToEndEmployment: boolean;
  lang: ScreenLang;
}): { ai: true; editable: true; visibleToEmployee: true; text: string; flags: string[]; note: string } {
  if (!input.enabled) fail("FEATURE_OFF");
  if (input.asksForRating || input.asksToEndEmployment) fail("INPUT_REQUIRED");
  const flags = inclusiveLanguage({ text: input.text, blockedWords: input.blockedWords }).flags;
  return {
    ai: true,
    editable: true,
    visibleToEmployee: true,
    text: input.text,
    flags,
    note: screen[input.lang].aiSuggestion,
  };
}

/** Ranking codes from duties stays off. Title search does not write a job description. */
export function rankCodesFromDuties(): never {
  fail("FEATURE_OFF");
}

export function titleSearch(input: { query: string | null; titles: readonly { code: string; title: string }[] }): {
  code: string;
  title: string;
}[] {
  if (input.query === null || input.query.length === 0) fail("INPUT_REQUIRED");
  const query = input.query.toLowerCase();
  const matches: { code: string; title: string }[] = [];
  for (const item of input.titles) {
    if (item.title.toLowerCase().includes(query)) matches.push({ code: item.code, title: item.title });
  }
  return matches;
}

export function forecast(input: { inputs: readonly { name: string; amount: string }[] }): {
  estimate: true;
  inputs: { name: string; amount: string }[];
  total: string;
} {
  if (input.inputs.length === 0) fail("INPUT_REQUIRED");
  let total = new D(0);
  const inputs: { name: string; amount: string }[] = [];
  for (const item of input.inputs) {
    inputs.push({ name: item.name, amount: money(item.amount) });
    total = total.plus(item.amount);
  }
  return { estimate: true, inputs, total: money(total.toFixed(2)) };
}

export function proposeAgreementRule(input: { article: string | null; quote: string | null }): {
  article: string;
  quote: string;
  extracted_by: "ai";
  verified: false;
} {
  if (input.article === null || input.article.length === 0 || input.quote === null || input.quote.length === 0) fail("INPUT_REQUIRED");
  return { article: input.article, quote: input.quote, extracted_by: "ai", verified: false };
}

export function draftFromTemplate(input: { template: string | null; slots: Readonly<Record<string, string>> }): {
  text: string;
  draft: true;
} {
  if (input.template === null || input.template.length === 0) fail("INPUT_REQUIRED");
  let text = input.template;
  for (const [key, value] of Object.entries(input.slots)) text = text.replaceAll(`{${key}}`, value);
  return { text, draft: true };
}
