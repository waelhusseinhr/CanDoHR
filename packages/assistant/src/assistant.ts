import { explainPay } from "./helpers.ts";
import { fail } from "./errors.ts";
import { screen, type ScreenLang } from "./text.ts";

/** The only tools the assistant may call. There is no job-description tool. */
export const TOOLS = [
  "search_people",
  "get_record",
  "org_chart_as_of",
  "explain_pay_result",
  "resolve_rules",
  "draft_change_set",
  "search_documents",
  "run_report",
] as const;

export type ToolName = (typeof TOOLS)[number];

export type Endpoint = { region: string; trainsOnCustomerData: boolean };

export function assistantPanel(input: {
  assistantEnabled: boolean;
  residency: string;
  endpoints: readonly Endpoint[];
}): { enabled: boolean } {
  if (!input.assistantEnabled) return { enabled: false };
  let compliant = false;
  for (const endpoint of input.endpoints) {
    if (endpoint.region === input.residency && !endpoint.trainsOnCustomerData) compliant = true;
  }
  return { enabled: compliant };
}

export type ApiResult = { access: "denied" } | { access: "ok"; body: Record<string, unknown> };

export type Api = {
  call: (tool: ToolName, args: Record<string, unknown>, token: string) => ApiResult;
};

export type TurnLog = { tool: string; recordIds: string[] };

function recordIds(args: Record<string, unknown>): string[] {
  const ids: string[] = [];
  if (typeof args.recordId === "string") ids.push(args.recordId);
  if (Array.isArray(args.recordIds)) {
    for (const id of args.recordIds) {
      if (typeof id === "string") ids.push(id);
    }
  }
  return ids;
}

export function searchDocuments(input: {
  documents: readonly { id: string; text: string; permitted: boolean }[];
  query: string;
}): { id: string; text: string }[] {
  const allowed: { id: string; text: string }[] = [];
  for (const document of input.documents) {
    if (document.permitted) allowed.push({ id: document.id, text: document.text });
  }
  const terms = input.query.split(" ").filter((term) => term.length > 0);
  const ranked: { id: string; text: string; score: number }[] = [];
  for (const document of allowed) {
    let score = 0;
    for (const term of terms) {
      if (document.text.includes(term)) score += 1;
    }
    if (score > 0) ranked.push({ id: document.id, text: document.text, score });
  }
  ranked.sort((left, right) => right.score - left.score);
  return ranked.map((document) => ({ id: document.id, text: document.text }));
}

type Clause = { article: string; topic: string; quote: string; verified: boolean };

function clausesOf(body: Record<string, unknown>): Clause[] {
  if (!Array.isArray(body.clauses)) return [];
  const clauses: Clause[] = [];
  for (const item of body.clauses) {
    if (typeof item !== "object" || item === null) continue;
    const clause = item as Record<string, unknown>;
    if (typeof clause.article !== "string" || typeof clause.topic !== "string" || typeof clause.quote !== "string") continue;
    clauses.push({
      article: clause.article,
      topic: clause.topic,
      quote: clause.quote,
      verified: clause.verified === true,
    });
  }
  return clauses;
}

function documentsOf(body: Record<string, unknown>): { id: string; text: string; permitted: boolean }[] {
  if (!Array.isArray(body.documents)) return [];
  const documents: { id: string; text: string; permitted: boolean }[] = [];
  for (const item of body.documents) {
    if (typeof item !== "object" || item === null) continue;
    const document = item as Record<string, unknown>;
    if (typeof document.id !== "string" || typeof document.text !== "string") continue;
    documents.push({ id: document.id, text: document.text, permitted: document.permitted === true });
  }
  return documents;
}

export function runTool(input: {
  panelEnabled: boolean;
  token: string | null;
  tool: ToolName;
  args: Record<string, unknown>;
  api: Api;
  lang: ScreenLang;
}): {
  answer: string;
  cited: unknown;
  committed: false;
  modelCalled: false;
  log: TurnLog;
} {
  if (!input.panelEnabled) fail("ASSISTANT_OFF");
  if (input.token === null || input.token.length === 0) fail("INPUT_REQUIRED");
  if (!TOOLS.includes(input.tool)) fail("INPUT_REQUIRED");
  const result = input.api.call(input.tool, input.args, input.token);
  const log = { tool: input.tool, recordIds: recordIds(input.args) };
  if (result.access === "denied") {
    return { answer: screen[input.lang].cannotAccess, cited: null, committed: false, modelCalled: false, log };
  }
  if (input.tool === "explain_pay_result") {
    const trace = Array.isArray(result.body.trace) ? (result.body.trace as [string, string][]) : [];
    const explained = explainPay(trace);
    return { answer: explained.text, cited: explained.values, committed: false, modelCalled: false, log };
  }
  if (input.tool === "resolve_rules") {
    const topic = typeof input.args.topic === "string" ? input.args.topic : "";
    let match: Clause | null = null;
    for (const clause of clausesOf(result.body)) {
      if (clause.verified && clause.topic === topic) match = clause;
    }
    if (match === null) {
      return { answer: screen[input.lang].notCovered, cited: null, committed: false, modelCalled: false, log };
    }
    return {
      answer: `${match.article}: ${match.quote}`,
      cited: { article: match.article, quote: match.quote },
      committed: false,
      modelCalled: false,
      log,
    };
  }
  if (input.tool === "draft_change_set") {
    return {
      answer: screen[input.lang].draft,
      cited: result.body,
      committed: false,
      modelCalled: false,
      log,
    };
  }
  if (input.tool === "search_documents") {
    const query = typeof input.args.query === "string" ? input.args.query : "";
    const found = searchDocuments({ documents: documentsOf(result.body), query });
    return { answer: found.map((document) => document.id).join(", "), cited: found, committed: false, modelCalled: false, log };
  }
  return { answer: screen[input.lang].draft, cited: result.body, committed: false, modelCalled: false, log };
}
