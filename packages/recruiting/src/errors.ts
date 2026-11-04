export class RecruitError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "RecruitError";
    this.code = code;
  }
}
