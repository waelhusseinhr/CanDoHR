export class OffboardingError extends Error {
  readonly code: string;

  constructor(code: string, detail?: string) {
    super(detail === undefined ? code : `${code}: ${detail}`);
    this.name = "OffboardingError";
    this.code = code;
  }
}

export function fail(code: string, detail?: string): never {
  throw new OffboardingError(code, detail);
}
