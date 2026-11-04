import { addDays, money } from "@candohr/disbursement";
import { YearEndError } from "./errors.ts";

export type RoePeriod = { number: number; amount: string };

export type RoeDraft = {
  payrollAccount: string;
  payPeriodType: string;
  sin: string;
  firstName: string;
  lastName: string;
  addressLine1: string;
  addressLine2: string;
  postalCode: string;
  firstDay: string;
  lastDayPaid: string;
  finalPayPeriodEnd: string;
  insurableHours: string;
  periods: readonly RoePeriod[];
  reasonCode: string;
  contactFirstName: string;
  contactLastName: string;
  contactArea: string;
  contactPhone: string;
  dueDate: string;
  recallCode: "Y" | "N" | "U";
};

export function roeDueDate(payPeriodEnd: string, deadlineDays: number): string {
  if (!Number.isInteger(deadlineDays) || deadlineDays < 0) throw new YearEndError("DATE");
  return addDays(payPeriodEnd, deadlineDays);
}

export function prepareRoe(input: {
  payrollAccount: string;
  payPeriodType: string;
  sin: string;
  firstName: string;
  lastName: string;
  addressLine1: string;
  addressLine2: string;
  postalCode: string;
  firstDay: string;
  lastDayPaid: string;
  finalPayPeriodEnd: string;
  insurableHours: string;
  periods: readonly RoePeriod[];
  separationReason: string;
  reasonMap: Readonly<Record<string, string>>;
  contactFirstName: string;
  contactLastName: string;
  contactArea: string;
  contactPhone: string;
  deadlineDays: number;
  recallCode?: "Y" | "N" | "U";
}): RoeDraft {
  const reasonCode = input.reasonMap[input.separationReason];
  if (!reasonCode) throw new YearEndError("REASON_UNMAPPED");
  if (input.periods.length === 0) throw new YearEndError("INPUT_REQUIRED");
  return {
    payrollAccount: input.payrollAccount,
    payPeriodType: input.payPeriodType,
    sin: input.sin,
    firstName: input.firstName,
    lastName: input.lastName,
    addressLine1: input.addressLine1,
    addressLine2: input.addressLine2,
    postalCode: input.postalCode,
    firstDay: input.firstDay,
    lastDayPaid: input.lastDayPaid,
    finalPayPeriodEnd: input.finalPayPeriodEnd,
    insurableHours: input.insurableHours,
    periods: input.periods.map((period) => ({ number: period.number, amount: money(period.amount) })),
    reasonCode,
    contactFirstName: input.contactFirstName,
    contactLastName: input.contactLastName,
    contactArea: input.contactArea,
    contactPhone: input.contactPhone,
    dueDate: roeDueDate(input.finalPayPeriodEnd, input.deadlineDays),
    recallCode: input.recallCode ?? "N",
  };
}

function esc(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

/** The extract file is built only after HR has reviewed the reason and the comments. */
export function buildRoeFile(
  draft: RoeDraft,
  review: { reviewedBy: string; reviewedAt: string } | null,
): string {
  if (!review || review.reviewedBy.trim() === "" || review.reviewedAt.trim() === "") {
    throw new YearEndError("ROE_NOT_REVIEWED");
  }
  const periods = draft.periods
    .map((period) => `<PP nbr="${period.number}"><AMT>${esc(period.amount)}</AMT></PP>`)
    .join("");
  return [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<ROEHEADER FileVersion="W-2.0" SoftwareVendor="CanDo HR" ProductName="CanDoHR">`,
    `<ROE PrintingLanguage="E" Issue="S">`,
    `<B5>${esc(draft.payrollAccount)}</B5>`,
    `<B6>${esc(draft.payPeriodType)}</B6>`,
    `<B8>${esc(draft.sin)}</B8>`,
    `<B9><FN>${esc(draft.firstName)}</FN><LN>${esc(draft.lastName)}</LN><A1>${esc(draft.addressLine1)}</A1><A2>${esc(draft.addressLine2)}</A2><PC>${esc(draft.postalCode)}</PC></B9>`,
    `<B10>${esc(draft.firstDay)}</B10>`,
    `<B11>${esc(draft.lastDayPaid)}</B11>`,
    `<B12>${esc(draft.finalPayPeriodEnd)}</B12>`,
    `<B14><CD>${draft.recallCode}</CD></B14>`,
    `<B15A>${esc(draft.insurableHours)}</B15A>`,
    `<B15C>${periods}</B15C>`,
    `<B16><CD>${esc(draft.reasonCode)}</CD><FN>${esc(draft.contactFirstName)}</FN><LN>${esc(draft.contactLastName)}</LN><AC>${esc(draft.contactArea)}</AC><TEL>${esc(draft.contactPhone)}</TEL></B16>`,
    `</ROE>`,
    `</ROEHEADER>`,
    ``,
  ].join("\n");
}

export function trackRoeDeadlines(
  items: readonly { id: string; dueDate: string; filed: boolean }[],
  today: string,
): { id: string; status: "filed" | "due" | "overdue" }[] {
  return items.map((item) => {
    if (item.filed) return { id: item.id, status: "filed" };
    return { id: item.id, status: today > item.dueDate ? "overdue" : "due" };
  });
}

export type ActiveAssignment = {
  assignmentId: string;
  personId: string;
  payrollAccountId: string;
  leavePlanId: string;
  positionId: string;
  nextEarningsDate: string;
};

/**
 * An ROE is issued per payroll account. It is not issued while earnings continue
 * on that account inside the caller's interruption window. Another account is left alone.
 */
export function assignmentEndRoes(input: {
  interruptionDays: number;
  ended: ActiveAssignment & { endDate: string };
  remaining: readonly ActiveAssignment[];
  positionHolders: readonly { positionId: string; assignmentId: string }[];
}): {
  roes: { personId: string; payrollAccountId: string }[];
  leaveSettles: boolean;
  benefitsReevaluated: true;
  positionVacated: boolean;
} {
  if (!Number.isInteger(input.interruptionDays) || input.interruptionDays < 0) throw new YearEndError("DATE");
  const limit = addDays(input.ended.endDate, input.interruptionDays);
  const sameAccountContinues = input.remaining.some(
    (assignment) =>
      assignment.personId === input.ended.personId &&
      assignment.payrollAccountId === input.ended.payrollAccountId &&
      assignment.nextEarningsDate <= limit,
  );
  const roes = sameAccountContinues
    ? []
    : [{ personId: input.ended.personId, payrollAccountId: input.ended.payrollAccountId }];
  const leaveSettles = !input.remaining.some(
    (assignment) => assignment.personId === input.ended.personId && assignment.leavePlanId === input.ended.leavePlanId,
  );
  const stillHeld = input.positionHolders.some(
    (holder) => holder.positionId === input.ended.positionId && holder.assignmentId !== input.ended.assignmentId,
  );
  return { roes, leaveSettles, benefitsReevaluated: true, positionVacated: !stillHeld };
}
