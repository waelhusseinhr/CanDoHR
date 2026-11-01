import Decimal from "decimal.js";
import { CanDoError } from "./errors.ts";

// 28 significant digits for intermediate math (docs/02). Stored money is NUMERIC(14,2):
// 12 digits before the decimal point and 2 after. Never a JavaScript number.
Decimal.set({ precision: 28, rounding: Decimal.ROUND_HALF_EVEN });

const MONEY_TEXT = /^-?(?:0|[1-9]\d{0,11})(?:\.\d{1,2})?$/;
const FACTOR_TEXT = /^-?(?:0|[1-9]\d*)(?:\.\d+)?$/;
const MAX_ABS = new Decimal("1000000000000");

/**
 * An amount of money. Create one with `Money.parse` from a two-decimal string.
 * Arithmetic stays in decimal.js and comes back out as a two-decimal string.
 */
export class Money {
  readonly #cents: Decimal;

  private constructor(cents: Decimal) {
    this.#cents = cents;
  }

  /** Accepts "72000", "72000.5", or "72000.50". Rejects numbers, extra decimals, and values that do not fit NUMERIC(14,2). */
  static parse(input: string): Money {
    if (typeof input !== "string" || !MONEY_TEXT.test(input)) {
      throw new CanDoError("MONEY_FORMAT");
    }
    return Money.#from(new Decimal(input));
  }

  plus(other: Money): Money {
    return Money.#from(this.#cents.plus(other.#cents));
  }

  minus(other: Money): Money {
    return Money.#from(this.#cents.minus(other.#cents));
  }

  /** `factor` is a decimal string such as "1.5", not a JavaScript number. The result is rounded to cents. */
  times(factor: string): Money {
    if (typeof factor !== "string" || !FACTOR_TEXT.test(factor)) {
      throw new CanDoError("MONEY_FORMAT");
    }
    return Money.#from(this.#cents.times(factor));
  }

  equals(other: Money): boolean {
    return this.#cents.eq(other.#cents);
  }

  /** Always two digits after the decimal point, such as "10.50". */
  toString(): string {
    return this.#cents.toFixed(2);
  }

  /** Blocks `Number(money)` and `+money`, which would turn the amount into a float. */
  valueOf(): never {
    throw new CanDoError("MONEY_NUMBER");
  }

  static #from(value: Decimal): Money {
    const quantized = value.toDecimalPlaces(2, Decimal.ROUND_HALF_EVEN);
    if (quantized.abs().gte(MAX_ABS)) {
      throw new CanDoError("MONEY_OVERFLOW");
    }
    if (quantized.isZero()) {
      return new Money(new Decimal(0));
    }
    return new Money(quantized);
  }
}
