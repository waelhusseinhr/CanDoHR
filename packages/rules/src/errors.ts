export type RuleProblem = { code: string; detail: string };

/** A named rules failure. `status` is 422 when verification or activation is refused. */
export class RulesError extends Error {
  readonly code: string;
  readonly status: number;
  readonly detail: string;
  readonly problems: RuleProblem[];

  constructor(code: string, detail: string, status = 422, problems: RuleProblem[] = []) {
    super(`${code}: ${detail}`);
    this.name = "RulesError";
    this.code = code;
    this.status = status;
    this.detail = detail;
    this.problems = problems;
  }
}
