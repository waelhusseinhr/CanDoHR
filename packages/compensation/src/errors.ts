export class RewardsError extends Error {
  readonly code: string;

  constructor(code: string, detail?: string) {
    super(detail === undefined ? code : `${code}: ${detail}`);
    this.name = "RewardsError";
    this.code = code;
  }
}

export function fail(code: string, detail?: string): never {
  throw new RewardsError(code, detail);
}
