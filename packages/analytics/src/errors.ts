export class AnalyticsError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, detail?: string, status?: number) {
    super(detail === undefined ? code : `${code}: ${detail}`);
    this.name = "AnalyticsError";
    this.code = code;
    this.status = status === undefined ? 422 : status;
  }
}

export function fail(code: string, detail?: string, status?: number): never {
  throw new AnalyticsError(code, detail, status);
}
