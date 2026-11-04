export class TalentError extends Error {
  readonly code: string;

  constructor(code: string, detail?: string) {
    super(detail === undefined ? code : `${code}: ${detail}`);
    this.name = "TalentError";
    this.code = code;
  }
}

export function fail(code: string, detail?: string): never {
  throw new TalentError(code, detail);
}
