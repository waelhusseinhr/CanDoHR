import { addDays, DisbursementError, money, mul, sum } from "./money.ts";

export type RemitterType = "quarterly" | "regular" | "accelerated_1" | "accelerated_2";

export type DeductionParts = {
  employeeCpp: string;
  employerCpp: string;
  employeeEi: string;
  employerEi: string;
  tax: string;
};

export type EmploymentStatus = "current" | "former" | "leave" | "laid_off";
export type DocumentKind = "pay_statement" | "tax_slip";
export type DeliveryChoice = "electronic" | "email" | "paper" | null;

function isoDate(year: number, monthIndex: number, day: number): string {
  return new Date(Date.UTC(year, monthIndex, day)).toISOString().slice(0, 10);
}

function partsOf(iso: string): { year: number; month: number; day: number } {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) throw new DisbursementError("DATE");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const utc = new Date(Date.UTC(year, month - 1, day));
  if (utc.getUTCFullYear() !== year || utc.getUTCMonth() !== month - 1 || utc.getUTCDate() !== day) {
    throw new DisbursementError("DATE");
  }
  return { year, month, day };
}

function isWeekend(iso: string): boolean {
  const day = new Date(`${iso}T00:00:00Z`).getUTCDay();
  return day === 0 || day === 6;
}

function workingDaysAfter(iso: string, count: number, holidays: readonly string[]): string {
  let cursor = iso;
  let left = count;
  while (left > 0) {
    cursor = addDays(cursor, 1);
    if (!isWeekend(cursor) && !holidays.includes(cursor)) left -= 1;
  }
  return cursor;
}

function acceleratedPeriodEnd(payDate: string): string {
  const { year, month, day } = partsOf(payDate);
  const last = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const endDay = day <= 7 ? 7 : day <= 14 ? 14 : day <= 21 ? 21 : last;
  return `${payDate.slice(0, 8)}${String(endDay).padStart(2, "0")}`;
}

export function remittanceDueDate(remitterType: RemitterType, payDate: string, holidays: readonly string[] = []): string {
  const { year, month, day } = partsOf(payDate);
  if (remitterType === "quarterly") {
    const quarterEndMonth = Math.ceil(month / 3) * 3;
    return isoDate(year, quarterEndMonth, 15);
  }
  if (remitterType === "regular") return isoDate(year, month, 15);
  if (remitterType === "accelerated_1") {
    if (day <= 15) return `${payDate.slice(0, 8)}25`;
    return isoDate(year, month, 10);
  }
  if (remitterType === "accelerated_2") return workingDaysAfter(acceleratedPeriodEnd(payDate), 3, holidays);
  throw new DisbursementError("REMITTER");
}

export function sourceDeductionRemittance(input: {
  remitterType: RemitterType;
  payDate: string;
  amount?: string;
  parts?: DeductionParts;
  holidays?: readonly string[];
}): { payee: "CRA"; amount: string; dueDate: string } {
  let amount: string;
  if (input.amount !== undefined) amount = money(input.amount);
  else if (input.parts) {
    amount = sum([input.parts.employeeCpp, input.parts.employerCpp, input.parts.employeeEi, input.parts.employerEi, input.parts.tax]);
  } else throw new DisbursementError("INPUT_REQUIRED");
  return {
    payee: "CRA",
    amount,
    dueDate: remittanceDueDate(input.remitterType, input.payDate, input.holidays ?? []),
  };
}

export function remittanceReminders(input: {
  payee: string;
  amount: string;
  dueDate: string;
  reminderDays: readonly number[];
  paid: boolean;
}): { on: string; payee: string; amount: string; dueDate: string }[] {
  if (input.paid) return [];
  const amount = money(input.amount);
  return [...input.reminderDays]
    .sort((left, right) => right - left)
    .map((days) => ({
      on: addDays(input.dueDate, -days),
      payee: input.payee,
      amount,
      dueDate: input.dueDate,
    }));
}

export function territorialPayrollTax(input: { province: string; gross: string; rate: string }): {
  code: "NU_PAYROLL_TAX" | "NT_PAYROLL_TAX" | null;
  amount: string;
  onT4: false;
  t4Boxes: readonly [];
} {
  const gross = money(input.gross);
  if (typeof input.rate !== "string" || input.rate.trim() === "") throw new DisbursementError("MONEY");
  if (input.province !== "NU" && input.province !== "NT") {
    return { code: null, amount: "0.00", onT4: false, t4Boxes: [] };
  }
  return {
    code: input.province === "NU" ? "NU_PAYROLL_TAX" : "NT_PAYROLL_TAX",
    amount: mul(gross, input.rate),
    onT4: false,
    t4Boxes: [],
  };
}

export function deliveryFor(input: {
  status: EmploymentStatus;
  kind: DocumentKind;
  choice: DeliveryChoice;
}): { method: "portal" | "print"; mayEmail: boolean } {
  if (input.kind !== "pay_statement" && input.kind !== "tax_slip") throw new DisbursementError("DOCUMENT");
  if (input.choice === "paper") return { method: "print", mayEmail: false };
  if (input.choice === "electronic" || input.choice === "email") {
    return { method: "portal", mayEmail: input.choice === "email" };
  }
  if (input.status === "current") return { method: "portal", mayEmail: false };
  return { method: "print", mayEmail: false };
}
