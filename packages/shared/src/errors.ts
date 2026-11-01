/** A named failure from shared foundations. `code` is the stable part; the message is the same word. */
export class CanDoError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "CanDoError";
    this.code = code;
  }
}
