export class AssistantError extends Error {
  readonly code: string;
  readonly status: number;

  constructor(code: string, detail?: string, status?: number) {
    super(detail === undefined ? code : `${code}: ${detail}`);
    this.name = "AssistantError";
    this.code = code;
    this.status = status === undefined ? 422 : status;
  }
}

export function fail(code: string, detail?: string, status?: number): never {
  throw new AssistantError(code, detail, status);
}
