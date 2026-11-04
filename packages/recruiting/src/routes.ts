import { RecruitError } from "./errors.ts";

export type RouteStep = {
  capability: string;
  mode: "any" | "all";
  approvers: string[];
  escalateTo?: string;
};

export type WorkflowRoute = {
  id: string;
  kind: string;
  priority: number;
  conditions: Record<string, string | number | boolean>;
  steps: RouteStep[];
};

export type Approval = { step: number; approverId: string };

export function routeFor(
  routes: WorkflowRoute[],
  kind: string,
  facts: Record<string, string | number | boolean | null | undefined>,
): WorkflowRoute {
  const candidates = routes.filter((route) => route.kind === kind).sort((left, right) => left.priority - right.priority);
  if (candidates.length === 0) throw new RecruitError("ROUTE_NOT_FOUND");
  for (const route of candidates) {
    let matched = true;
    for (const [key, expected] of Object.entries(route.conditions)) {
      if (facts[key] === undefined || facts[key] === null) throw new RecruitError("ROUTE_FACT_MISSING");
      if (facts[key] !== expected) {
        matched = false;
        break;
      }
    }
    if (matched) return route;
  }
  throw new RecruitError("ROUTE_NOT_FOUND");
}

export function recordApproval(route: WorkflowRoute, approvals: Approval[], requesterId: string, approverId: string, step: number): Approval[] {
  if (approverId === requesterId) throw new RecruitError("SELF_APPROVAL");
  const definition = route.steps[step];
  if (!definition || !definition.approvers.includes(approverId)) throw new RecruitError("ROUTE_APPROVALS_MISSING");
  if (approvals.some((approval) => approval.step === step && approval.approverId === approverId)) return approvals;
  return [...approvals, { step, approverId }];
}

export function routeComplete(route: WorkflowRoute, approvals: Approval[]): boolean {
  return route.steps.every((step, index) => {
    const decided = approvals.filter((approval) => approval.step === index);
    if (step.mode === "any") return decided.length > 0;
    return step.approvers.every((approverId) => decided.some((approval) => approval.approverId === approverId));
  });
}

export function escalateUndecided(step: RouteStep, decided: boolean, asOf: string, dueOn: string): { escalated: boolean; to?: string } {
  if (decided || asOf <= dueOn) return { escalated: false };
  return { escalated: true, to: step.escalateTo };
}

export type Caution = { code: string; textShown: string; needsReason: boolean; needsApproval: boolean };

export type Acknowledgement = {
  cautionCode: string;
  subjectType: string;
  subjectId: string;
  textShown: string;
  reason: string;
  acknowledgedBy: string;
  approvedBy?: string;
};

export function acknowledgeCaution(caution: Caution, existing: Acknowledgement[], input: Omit<Acknowledgement, "textShown" | "cautionCode">): Acknowledgement {
  const prior = existing.find((row) => row.cautionCode === caution.code && row.subjectType === input.subjectType && row.subjectId === input.subjectId);
  if (prior) throw new RecruitError("CAUTION_ACK_IMMUTABLE");
  if (caution.needsReason && input.reason.trim() === "") throw new RecruitError("CAUTION_REASON_REQUIRED");
  return { ...input, cautionCode: caution.code, textShown: caution.textShown };
}

export function approveCaution(acknowledgement: Acknowledgement, approverId: string): Acknowledgement {
  if (approverId === acknowledgement.acknowledgedBy) throw new RecruitError("SELF_APPROVAL");
  return { ...acknowledgement, approvedBy: approverId };
}

export function cautionCleared(caution: Caution, acknowledgement: Acknowledgement | undefined): boolean {
  if (!acknowledgement) return false;
  if (caution.needsReason && acknowledgement.reason.trim() === "") return false;
  if (caution.needsApproval && !acknowledgement.approvedBy) return false;
  return acknowledgement.textShown === caution.textShown;
}
