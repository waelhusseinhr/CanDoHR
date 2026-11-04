import { cmp, money, sub, sum } from "@candohr/disbursement";
import { addMonths, shiftDays } from "./dates.ts";
import { RecruitError } from "./errors.ts";
import { cautionCleared, type Acknowledgement, type Caution, type WorkflowRoute } from "./routes.ts";
import { employmentStandard, ruleInt, ruleMoney, type StandardsBundle } from "./standards.ts";

export type PositionSnapshot = {
  id: string;
  status: "vacant" | "frozen" | "filled";
  title: string;
  unitId: string;
  locationId: string;
  agreementId: string | null;
  gradeMin: string;
  gradeMax: string;
  fte: string;
  jurisdiction: string;
};

export type FundingLine = { costCentreId: string; fundingSourceId: string; share: string };

export type RequisitionInput = {
  position: PositionSnapshot;
  typeCode: string;
  typeCategory: "replacement" | "additional_headcount" | "new_position";
  employmentType: string;
  termEnd?: string;
  funding: FundingLine[];
  namedCandidateId?: string;
  postingRequiredByAgreement: boolean;
  exemptionCode?: string;
  knownExemptions: string[];
  commitment: string;
  remainingBudget: string;
  acknowledgement?: Acknowledgement;
  caution?: Caution;
};

export function openRequisition(input: RequisitionInput): {
  prefilled: { title: string; unitId: string; locationId: string; agreementId: string | null; gradeMin: string; gradeMax: string; fte: string };
  funding: FundingLine[];
  employmentType: string;
  termEnd?: string;
  overBudget: boolean;
  changeSet: { operations: { type: string; positionId?: string }[] };
} {
  if (input.position.status === "frozen") throw new RecruitError("POSITION_FROZEN");
  if (input.position.status !== "vacant" && input.typeCategory !== "new_position") throw new RecruitError("POSITION_NOT_VACANT");
  if (input.funding.length === 0) throw new RecruitError("REQUISITION_FUNDING_MISSING");
  const shares = sum(input.funding.map((line) => money(line.share)));
  if (cmp(shares, "100.00") !== 0) throw new RecruitError("REQUISITION_FUNDING_NOT_100");
  if (input.employmentType === "term" && !input.termEnd) throw new RecruitError("INPUT_REQUIRED");
  if (input.exemptionCode && !input.knownExemptions.includes(input.exemptionCode)) throw new RecruitError("POSTING_EXEMPTION_UNKNOWN");
  if (input.namedCandidateId && input.postingRequiredByAgreement && !input.exemptionCode) {
    if (!input.caution || !cautionCleared(input.caution, input.acknowledgement)) throw new RecruitError("CAUTION_NOT_ACKNOWLEDGED");
  }
  const overBudget = cmp(input.commitment, input.remainingBudget) > 0;
  const operations: { type: string; positionId?: string }[] = [];
  if (input.typeCategory === "new_position") operations.push({ type: "position.create" });
  operations.push({ type: "requisition.open", positionId: input.position.id });
  return {
    prefilled: {
      title: input.position.title,
      unitId: input.position.unitId,
      locationId: input.position.locationId,
      agreementId: input.position.agreementId,
      gradeMin: money(input.position.gradeMin),
      gradeMax: money(input.position.gradeMax),
      fte: input.position.fte,
    },
    funding: input.funding,
    employmentType: input.employmentType,
    termEnd: input.termEnd,
    overBudget,
    changeSet: { operations },
  };
}

export function financeRequired(overBudget: boolean, route: WorkflowRoute): void {
  if (overBudget && !route.steps.some((step) => step.capability === "finance")) throw new RecruitError("ROUTE_NOT_FOUND");
}

export type PostingDraft = {
  publicPosting: boolean;
  employerHeadcount: number;
  jurisdiction: string;
  payMin?: string;
  payMax?: string;
  payShown: boolean;
  payBasis: "range" | "incumbents_average" | "market" | "other";
  incumbentCount: number;
  incumbentAverageMin: number;
  incumbentAverageFloor: number;
  vacancyExists: boolean | null;
  requiresCanadianExperience: boolean;
  aiScreeningOn: boolean;
  aiUseStatement?: string;
  questions: { code: string }[];
  frenchRequired: boolean;
  frenchText?: string;
  requisitionApproved: boolean;
  openedOn: string;
  internalDays?: number;
  asOf: string;
  seniorityOrder: "on" | "off";
  seniorityOverride?: Acknowledgement;
  seniorityCaution?: Caution;
  missingRequirement?: "screen_out" | "flag";
};

export function validatePosting(bundle: StandardsBundle, posting: PostingDraft): PostingDraft {
  if (!posting.requisitionApproved) throw new RecruitError("POSTING_REQUISITION_NOT_APPROVED");
  if (!posting.missingRequirement) throw new RecruitError("SETTING_NOT_SET");
  if (posting.payBasis === "incumbents_average") {
    if (posting.incumbentAverageMin < posting.incumbentAverageFloor) throw new RecruitError("SETTING_BELOW_MINIMUM");
    if (posting.incumbentCount < posting.incumbentAverageMin) throw new RecruitError("INCUMBENT_AVERAGE_UNAVAILABLE");
  }
  if (posting.frenchRequired && !posting.frenchText?.trim()) throw new RecruitError("FRENCH_REQUIRED_FOR_QUEBEC");
  if (posting.seniorityOrder === "off" && posting.seniorityOverride) {
    if (!posting.seniorityCaution || !cautionCleared(posting.seniorityCaution, posting.seniorityOverride)) {
      throw new RecruitError("CAUTION_NOT_ACKNOWLEDGED");
    }
  }
  const rule = employmentStandard(bundle, posting.jurisdiction, "pay_transparency");
  let next = posting;
  if (posting.publicPosting) {
    const appliesAt = typeof rule.applies_to_employers_with === "number" ? rule.applies_to_employers_with : 0;
    const inForce = posting.employerHeadcount >= appliesAt;
    const needsPay = rule.salary_range_in_postings === true || rule.pay_or_range_in_public_postings === true;
    if (inForce && needsPay && (!posting.payShown || !posting.payMin || !posting.payMax)) throw new RecruitError("PAY_NOT_SHOWN");
    if (inForce && posting.payMin && posting.payMax && typeof rule.max_range_width !== "undefined") {
      const width = sub(money(posting.payMax), money(posting.payMin));
      if (cmp(width, ruleMoney(rule, "max_range_width")) > 0) throw new RecruitError("PAY_RANGE_TOO_WIDE");
    }
    if (rule.vacancy_status_stated === true && posting.vacancyExists === null) throw new RecruitError("VACANCY_NOT_STATED");
    if (rule.canadian_experience_requirement_allowed === false && posting.requiresCanadianExperience) {
      throw new RecruitError("CANADIAN_EXPERIENCE_NOT_ALLOWED");
    }
    if (rule.ai_use_disclosed === true && posting.aiScreeningOn && !posting.aiUseStatement) {
      next = { ...posting, aiUseStatement: "ai_use_disclosed" };
    }
  }
  if (rule.pay_history_questions_banned === true) {
    next = { ...next, questions: next.questions.filter((question) => question.code !== "pay_history") };
  }
  return next;
}

export function postingIsInternal(openedOn: string, internalDays: number, asOf: string): boolean {
  return asOf < shiftDays(openedOn, internalDays);
}

export type Candidate = { id: string; name: string; photoRef?: string; seniorityDate: string; score: string; internal: boolean };

export function rankInternal(rule: string, candidates: Candidate[], orderOn: boolean): { id: string; reason: string }[] {
  const ranked = [...candidates].sort((left, right) => {
    const score = cmp(right.score, left.score);
    if (score !== 0) return score;
    if (orderOn && rule === "relatively_equal_then_seniority") return left.seniorityDate.localeCompare(right.seniorityDate);
    return left.id.localeCompare(right.id);
  });
  return ranked.map((candidate, index) => {
    const previous = ranked[index - 1];
    const reason = previous && cmp(previous.score, candidate.score) === 0 && orderOn && rule === "relatively_equal_then_seniority"
      ? "relatively_equal_then_seniority"
      : "assessment_score";
    return { id: candidate.id, reason };
  });
}

export function visibleToReviewer(candidate: Candidate, blind: boolean): { name?: string; photoRef?: string } {
  if (blind) return {};
  return { name: candidate.name, photoRef: candidate.photoRef };
}

export function applyWithoutAccount(contact: { email?: string; phone?: string }): { account: false; email?: string; phone?: string } {
  if (!contact.email?.trim() && !contact.phone?.trim()) throw new RecruitError("CANDIDATE_CONTACT_REQUIRED");
  return { account: false, email: contact.email, phone: contact.phone };
}

export function storeMatchScore(aiEnabled: boolean, score: string | undefined, reasons: string[] | undefined): void {
  if (score === undefined) return;
  if (!aiEnabled) throw new RecruitError("MATCH_SUGGESTIONS_OFF");
  if (!reasons || reasons.length === 0) throw new RecruitError("MATCH_WITHOUT_REASONS");
}

export function decideApplication(input: {
  outcome: "advanced" | "rejected" | "screened_out";
  decidedByKind: "person" | "requirement_rule";
  decidedBy?: string;
  decidedOn: string;
  missingRequirements: string[];
  missingRequirement: "screen_out" | "flag";
}): void {
  if (!input.decidedOn || (input.decidedByKind === "person" && !input.decidedBy)) throw new RecruitError("APPLICATION_DECISION_UNSIGNED");
  if (input.decidedByKind === "requirement_rule") {
    if (!(input.outcome === "screened_out" && input.missingRequirement === "screen_out" && input.missingRequirements.length > 0)) {
      throw new RecruitError("REQUIREMENT_RULE_NOT_ALLOWED");
    }
  }
}

export function outcomeNotice(bundle: StandardsBundle, jurisdiction: string, lastInterview: string, asOf: string, riskDays: number): { dueOn: string; atRisk: boolean } {
  const rule = employmentStandard(bundle, jurisdiction, "pay_transparency");
  const days = ruleInt(rule, "applicant_outcome_notice_days");
  const dueOn = shiftDays(lastInterview, days);
  return { dueOn, atRisk: asOf >= shiftDays(dueOn, -riskDays) };
}

export function retentionUntil(bundle: StandardsBundle, input: {
  jurisdiction: string;
  decidedOn: string;
  postingClosedOn?: string;
  organizationMonths: number;
}): string {
  const rule = employmentStandard(bundle, input.jurisdiction, "candidate_records_retention");
  const months = ruleInt(rule, "months");
  const from = rule.from === "posting_closed" ? input.postingClosedOn : input.decidedOn;
  if (!from) throw new RecruitError("INPUT_REQUIRED");
  const legal = shiftDays(addMonthsSafe(from, months), 0);
  const organization = addMonthsSafe(input.decidedOn, input.organizationMonths);
  return legal > organization ? legal : organization;
}

function addMonthsSafe(iso: string, months: number): string {
  return months === 0 ? iso : addMonths(iso, months);
}

export function unionNoticeReminder(required: boolean, notified: boolean): { remind: boolean } {
  return { remind: required && !notified };
}

export type InterviewScore = { panelistId: string; submitted: boolean; value: string };

export function submitScore(scores: InterviewScore[], panelistId: string, value: string): InterviewScore[] {
  if (scores.some((score) => score.panelistId === panelistId && score.submitted)) throw new RecruitError("SCORE_LOCKED");
  return [...scores.filter((score) => score.panelistId !== panelistId), { panelistId, submitted: true, value }];
}

export function scoresVisibleTo(scores: InterviewScore[], panelistId: string): InterviewScore[] {
  const mine = scores.find((score) => score.panelistId === panelistId);
  if (!mine?.submitted) return scores.filter((score) => score.panelistId === panelistId);
  return scores;
}

export function assertInterviewsScored(scoring: string | undefined, interviews: { scores: InterviewScore[] }[]): void {
  if (!scoring) throw new RecruitError("SETTING_NOT_SET");
  if (scoring !== "every_interview") return;
  if (interviews.some((interview) => interview.scores.length === 0 || interview.scores.some((score) => !score.submitted))) {
    throw new RecruitError("INTERVIEW_SCORE_REQUIRED");
  }
}
