import { CanDoError } from "@candohr/shared";

/** Canadian SIN check digit. The number itself is never hard-coded here. */
export function isValidSin(value: string): boolean {
  const digits = value.replace(/\D/g, "");
  if (!/^\d{9}$/.test(digits)) return false;
  let sum = 0;
  // structural: loop index or iteration bound, not a business default
  for (let index = 0; index < 9; index += 1) {
    let digit = Number(digits[8 - index]);
    if (index % 2 === 1) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
  }
  return sum % 10 === 0;
}

export function assertSin(value: string): string {
  const digits = value.replace(/\D/g, "");
  if (!isValidSin(digits)) throw new CanDoError("SIN_INVALID");
  return digits;
}
