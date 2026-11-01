import type { AttributeMap, ConflictResolution, VersionRow } from "@candohr/shared";

/** Catalogue from docs/03 §4. Modules add operations later through the same list. */
export const OPERATIONS = [
  "person.create",
  "person.update",
  "employment.hire",
  "employment.rehire",
  "employment.terminate",
  "assignment.create",
  "assignment.update",
  "assignment.end",
  "position.create",
  "position.update",
  "position.freeze",
  "position.eliminate",
  "org_unit.create",
  "org_unit.update",
  "org_unit.move",
  "org_unit.close",
  "compensation.set_rate",
  "agreement.activate_version",
  "time.correct",
  "payroll_profile.update",
] as const;

export type OperationName = (typeof OPERATIONS)[number];

export const CHANGE_SET_STATUSES = [
  "draft",
  "validated",
  "pending_approval",
  "approved",
  "scheduled",
  "committed",
  "rejected",
  "cancelled",
] as const;

export type ChangeSetStatus = (typeof CHANGE_SET_STATUSES)[number];

export const SOURCES = [
  "ui_form",
  "org_chart",
  "mass_change",
  "import",
  "api",
  "workflow",
  "assistant_draft",
  "system",
] as const;

export type ChangeSource = (typeof SOURCES)[number];

export const CONSEQUENCE_KINDS = [
  "org_unit",
  "cost_centre",
  "location_province",
  "tax_province",
  "holiday_calendar",
  "agreement",
  "approver",
  "benefits_class",
  "budget",
  "retro",
  "conflict_future_change",
  "task",
] as const;

export type ConsequenceKind = (typeof CONSEQUENCE_KINDS)[number];

/** One proposed write. `targetId` is the OpenAPI shape; the spec examples also use assignmentId and the other ids. */
export interface Operation {
  op: string;
  targetId?: string;
  assignmentId?: string;
  positionId?: string;
  employmentId?: string;
  personId?: string;
  orgUnitId?: string;
  set?: AttributeMap;
  addedByCascade?: boolean;
}

export interface Finding {
  code: string;
  message: string;
  operationIndex?: number;
  field?: string;
}

export interface Consequence {
  kind: ConsequenceKind;
  description: string;
  from?: unknown;
  to?: unknown;
  addedOperation?: Operation;
}

export interface ValidationResult {
  errors: Finding[];
  warnings: Finding[];
  consequences: Consequence[];
}

export interface ApprovalStep {
  step: number;
  role: string;
  assignee: string;
  /** Set when the named approver is away and this task went to their delegate. */
  principalUserId: string | null;
  status: "open" | "approved" | "rejected" | "delegated" | "expired";
  decidedAt: string | null;
  comment?: string;
}

export interface Activity {
  action: string;
  actorId: string;
  principalUserId: string | null;
  delegateUserId: string | null;
  at: string;
}

export interface ChangeSetRecord {
  changeSetId: string;
  number: number;
  tenantId: string;
  kind: string;
  reasonCode: string;
  effectiveDate: string;
  isCorrection?: boolean;
  operations: Operation[];
  baseVersions: Record<string, number>;
  status: ChangeSetStatus;
  source: ChangeSource;
  requestedBy: string;
  requestedAt: string;
  committedAt: string | null;
  comment?: string;
  budgetImpact?: string;
  conflictResolution?: ConflictResolution;
  validation?: ValidationResult;
  approvals: ApprovalStep[];
  approvalMode: "sequential" | "parallel" | "none";
  activity: Activity[];
}

export interface AuditEntry {
  auditId: number;
  action: string;
  subjectType: string;
  subjectId: string;
  changeSetId: string;
  actorId: string;
  before: unknown;
  after: unknown;
  occurredAt: string;
}

/** Envelope from api/events.yaml. Salary, SIN, and banking never appear as values. */
export interface DomainEvent {
  eventId: string;
  type: string;
  version: 1;
  tenantId: string;
  occurredAt: string;
  effectiveDate: string;
  changeSetId: string;
  subject: { type: string; id: string; employmentId?: string; personId?: string };
  changes: Record<string, { from?: unknown; to?: unknown; changed?: boolean }>;
  actor: { type: "user"; id: string };
  subjectKey: string;
  publishedAt: string | null;
}

export interface AssignmentRecord {
  id: string;
  employmentId: string;
  personId: string;
  positionId: string | null;
  version: number;
  versions: VersionRow[];
}

export interface PositionRecord {
  id: string;
  status: "active" | "frozen" | "eliminated" | "vacant";
  version: number;
  orgUnitId: string;
}

export interface EmploymentRecord {
  id: string;
  personId: string;
  status: "active" | "terminated";
  assignmentIds: string[];
}

export interface ProfileRecord {
  assignmentId: string;
  taxProvince: string;
  overridden: boolean;
}

/**
 * In-memory books for tests. Production commit writes the same rows through Hyperdrive
 * with query caching disabled, in one database transaction.
 */
export interface World {
  positions: Record<string, PositionRecord>;
  assignments: Record<string, AssignmentRecord>;
  employments: Record<string, EmploymentRecord>;
  locations: Record<string, { id: string; province: string }>;
  profiles: Record<string, ProfileRecord>;
  people: Record<string, { id: string; attributes: AttributeMap }>;
  orgUnits: Record<string, { id: string; parentId: string | null; status: string }>;
  agreements: Record<string, { id: string; version: string | null }>;
  audits: AuditEntry[];
  outbox: DomainEvent[];
  nextAuditId: number;
}

export interface ApprovalDirectory {
  candidates(role: string, changeSet: ChangeSetRecord): string[];
  onLeave(userId: string): { delegateUserId: string } | null;
  /** True when this person reports to the requester on a different assignment (docs/17 §5.2 rule 4). */
  isSubordinateOnOtherAssignment(approverUserId: string, requesterUserId: string): boolean;
}

export interface ApprovalRoute {
  mode: "sequential" | "parallel";
  matches(changeSet: ChangeSetRecord): boolean;
  steps: { role: string }[];
}
