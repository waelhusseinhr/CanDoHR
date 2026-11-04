import { cmp, money } from "@candohr/disbursement";
import { shiftDays } from "./dates.ts";
import { RecruitError } from "./errors.ts";
import type { WorkflowRoute } from "./routes.ts";

export type Offer = {
  id: string;
  pay: string;
  rangeMin: string;
  rangeMax: string;
  status: "draft" | "approved" | "sent" | "accepted" | "expired";
  approvals: { approverId: string }[];
  accepted: boolean;
  contractSigned: boolean;
  sentOn?: string;
  expiresOn?: string;
  internal: boolean;
  tellSupervisor: boolean;
  movement?: "transfer" | "resignation_rehire";
  conditions: { code: string; consent: boolean; started: boolean }[];
};

export function outsideRange(offer: Pick<Offer, "pay" | "rangeMin" | "rangeMax">): boolean {
  const pay = money(offer.pay);
  return cmp(pay, money(offer.rangeMin)) < 0 || cmp(pay, money(offer.rangeMax)) > 0;
}

export function routeForOffer(offer: Pick<Offer, "pay" | "rangeMin" | "rangeMax">, inside: WorkflowRoute, outside: WorkflowRoute): WorkflowRoute {
  return outsideRange(offer) ? outside : inside;
}

export function renderOfferLetter(template: Record<string, string>, languages: string[]): Record<string, string> {
  const letters: Record<string, string> = {};
  for (const language of languages) {
    const text = template[language];
    if (!text) throw new RecruitError("TRANSLATION_MISSING");
    letters[language] = text;
  }
  return letters;
}

export function changeApprovedTerms(offer: Offer, nextPay: string, reapproval: boolean): Offer {
  if (!reapproval || offer.status === "draft") return { ...offer, pay: money(nextPay) };
  if (money(nextPay) === money(offer.pay)) return offer;
  return { ...offer, pay: money(nextPay), status: "draft", approvals: [] };
}

export function expiryDate(sentOn: string, workingDays: number, isWorkingDay: (iso: string) => boolean): string {
  let left = workingDays;
  let cursor = sentOn;
  while (left > 0) {
    cursor = shiftDays(cursor, 1);
    if (isWorkingDay(cursor)) left -= 1;
  }
  return cursor;
}

export function changeExpiry(actorRole: string, allowedRoles: string[]): void {
  if (!allowedRoles.includes(actorRole)) throw new RecruitError("SETTING_VALUE_NOT_ALLOWED");
}

export function sendOffer(offer: Offer): Offer {
  if (offer.status !== "approved") throw new RecruitError("OFFER_NOT_READY");
  return { ...offer, status: "sent", sentOn: offer.sentOn };
}

export function startCheck(offer: Offer, code: string, consent: boolean): Offer {
  if (offer.status !== "sent" && offer.status !== "accepted") throw new RecruitError("CHECK_BEFORE_CONDITIONAL_OFFER");
  if (!consent) throw new RecruitError("CONSENT_REQUIRED");
  return {
    ...offer,
    conditions: [...offer.conditions.filter((condition) => condition.code !== code), { code, consent: true, started: true }],
  };
}

export function acceptOffer(offer: Offer): Offer {
  if (offer.status !== "sent") throw new RecruitError("OFFER_NOT_SENT");
  const tellSupervisor = offer.internal ? true : offer.tellSupervisor;
  return { ...offer, status: "accepted", accepted: true, tellSupervisor };
}

export function signContract(offer: Offer): Offer {
  if (!offer.accepted) throw new RecruitError("CONTRACT_BEFORE_ACCEPTANCE");
  return { ...offer, contractSigned: true };
}

export function hireChangeSet(offer: Offer, input: {
  personId?: string;
  candidateFields: Record<string, string>;
  positionId: string;
  rate: string;
  startDate: string;
  payGroupId: string;
  movement?: "transfer" | "resignation_rehire";
}): {
  source: "hire";
  operations: { type: string; positionId: string }[];
  personId?: string;
  mapped: Record<string, string>;
  events: { type: string; subjectId: string }[];
} {
  if (!offer.accepted || !offer.contractSigned) throw new RecruitError("HIRE_BEFORE_CONTRACT_SIGNED");
  if (offer.internal && !input.movement && !offer.movement) throw new RecruitError("INPUT_REQUIRED");
  const movement = input.movement === undefined ? offer.movement : input.movement;
  const operations = input.personId
    ? [{ type: "assignment.add", positionId: input.positionId }]
    : [{ type: "employment.hire", positionId: input.positionId }];
  const mapped: Record<string, string> = {
    ...input.candidateFields,
    rate: money(input.rate),
    startDate: input.startDate,
    payGroupId: input.payGroupId,
  };
  if (movement) mapped.movement = movement;
  return {
    source: "hire",
    operations,
    personId: input.personId,
    mapped,
    events: [
      { type: "offer.contract_signed", subjectId: offer.id },
      { type: "employment.hired", subjectId: input.positionId },
    ],
  };
}

export function rehireSignal(record: { signal: string; reason: string; note: string }): { signal: string } {
  return { signal: record.signal };
}

export function messageBatch(reason: string): { reason: string } {
  if (reason.trim() === "") throw new RecruitError("MESSAGE_REASON_REQUIRED");
  return { reason };
}
