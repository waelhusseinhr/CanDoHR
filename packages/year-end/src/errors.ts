export class YearEndError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "YearEndError";
    this.code = code;
  }
}
