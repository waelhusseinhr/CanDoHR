import { CanDoError } from "@candohr/shared";

export const FIELD_CLASSES = [
  "public_directory",
  "employment",
  "personal",
  "compensation",
  "payroll_restricted",
  "health_accommodation",
  "self_identification",
  "investigation",
] as const;

export type FieldClass = (typeof FIELD_CLASSES)[number];

export const ACTIONS = ["read", "propose", "approve", "export", "reveal", "configure"] as const;
export type Action = (typeof ACTIONS)[number];

export interface Permission {
  action: Action;
  fieldClass: FieldClass;
  entity?: string;
}

export type Scope =
  | { type: "self" }
  | { type: "direct_reports" }
  | { type: "subtree"; orgUnitId: string; hierarchyId: string }
  | { type: "org_units"; orgUnitIds: string[]; hierarchyId: string }
  | { type: "legal_entities"; ids: string[] }
  | { type: "payroll_accounts"; ids: string[] }
  | { type: "bargaining_units"; ids: string[] }
  | { type: "agreements"; ids: string[] }
  | { type: "funding_sources"; ids: string[] }
  | { type: "locations"; ids: string[] }
  | { type: "all" };

export interface RoleGrant {
  roleCode: string;
  scope: Scope;
  permissions: readonly Permission[];
}

export interface AccessRequest {
  action: Action;
  fieldClass: FieldClass;
  entity?: string;
}

/** True when one of the user's grants allows the action on that field class. */
export function allows(grants: readonly RoleGrant[], request: AccessRequest): boolean {
  return grants.some((grant) =>
    grant.permissions.some(
      (permission) =>
        permission.action === request.action &&
        permission.fieldClass === request.fieldClass &&
        (permission.entity === undefined || request.entity === undefined || permission.entity === request.entity),
    ),
  );
}

export function allowedFieldClasses(grants: readonly RoleGrant[], action: Action): Set<FieldClass> {
  const allowed = new Set<FieldClass>();
  for (const grant of grants) {
    for (const permission of grant.permissions) {
      if (permission.action === action) allowed.add(permission.fieldClass);
    }
  }
  return allowed;
}

/**
 * Drops fields the caller cannot see. A removed field is absent, not null.
 * Fields with no class stay, so identifiers needed to talk about the row remain.
 */
export function stripFields<T extends Record<string, unknown>>(
  record: T,
  fieldClasses: Readonly<Record<string, FieldClass>>,
  allowed: ReadonlySet<FieldClass>,
): Partial<T> {
  const out: Partial<T> = {};
  for (const key of Object.keys(record) as (keyof T)[]) {
    const fieldClass = fieldClasses[key as string];
    if (fieldClass && !allowed.has(fieldClass)) continue;
    out[key] = record[key];
  }
  return out;
}

export interface ScopedRecord {
  personId: string;
  orgUnitId?: string | null;
  legalEntityId?: string | null;
  reportsToPersonId?: string | null;
  payrollAccountId?: string | null;
  bargainingUnitId?: string | null;
  agreementId?: string | null;
  fundingSourceId?: string | null;
  locationId?: string | null;
  /** Org units that contain this record, used when the closure table is not in the test. */
  ancestorOrgUnitIds?: readonly string[];
}

export interface ScopeViewer {
  personId: string | null;
}

export function recordInScope(scope: Scope, record: ScopedRecord, viewer: ScopeViewer): boolean {
  switch (scope.type) {
    case "all":
      return true;
    case "self":
      return viewer.personId !== null && record.personId === viewer.personId;
    case "direct_reports":
      return viewer.personId !== null && record.reportsToPersonId === viewer.personId;
    case "subtree":
      return (record.ancestorOrgUnitIds ?? []).includes(scope.orgUnitId) || record.orgUnitId === scope.orgUnitId;
    case "org_units":
      return record.orgUnitId != null && scope.orgUnitIds.includes(record.orgUnitId);
    case "legal_entities":
      return record.legalEntityId != null && scope.ids.includes(record.legalEntityId);
    case "payroll_accounts":
      return record.payrollAccountId != null && scope.ids.includes(record.payrollAccountId);
    case "bargaining_units":
      return record.bargainingUnitId != null && scope.ids.includes(record.bargainingUnitId);
    case "agreements":
      return record.agreementId != null && scope.ids.includes(record.agreementId);
    case "funding_sources":
      return record.fundingSourceId != null && scope.ids.includes(record.fundingSourceId);
    case "locations":
      return record.locationId != null && scope.ids.includes(record.locationId);
    default:
      return false;
  }
}

export interface ScopeSql {
  sql: string;
  params: readonly unknown[];
}

/**
 * Scope filter for a list query. Values stay in `params`.
 * The caller still sets `app.tenant_id` so row-level security applies first.
 */
export function scopeFilterSql(scope: Scope, viewerPersonId: string | null, asOf: string): ScopeSql {
  switch (scope.type) {
    case "all":
      return { sql: "TRUE", params: [] };
    case "self":
      return { sql: "person_id = $1", params: [viewerPersonId] };
    case "direct_reports":
      return {
        sql: `EXISTS (
          SELECT 1 FROM core.assignment_version report
          JOIN core.assignment ra ON ra.assignment_id = report.assignment_id AND ra.tenant_id = report.tenant_id
          JOIN core.employment re ON re.employment_id = ra.employment_id AND re.tenant_id = ra.tenant_id
          WHERE re.person_id = person_id
            AND report.reports_to_position_id = $1
            AND upper_inf(report.sys_period)
            AND report.valid_period @> $2::date
        )`,
        params: [viewerPersonId, asOf],
      };
    case "subtree":
      return {
        sql: `org_unit_id IN (
          SELECT descendant_id FROM core.org_closure
          WHERE ancestor_id = $1 AND hierarchy_id = $2 AND valid_period @> $3::date
            AND tenant_id = current_setting('app.tenant_id', true)::uuid
        )`,
        params: [scope.orgUnitId, scope.hierarchyId, asOf],
      };
    case "org_units":
      return { sql: "org_unit_id = ANY($1::uuid[])", params: [scope.orgUnitIds] };
    case "legal_entities":
      return { sql: "legal_entity_id = ANY($1::uuid[])", params: [scope.ids] };
    case "payroll_accounts":
      return { sql: "payroll_account_id = ANY($1::uuid[])", params: [scope.ids] };
    case "bargaining_units":
      return { sql: "bargaining_unit_id = ANY($1::uuid[])", params: [scope.ids] };
    case "agreements":
      return { sql: "agreement_id = ANY($1::uuid[])", params: [scope.ids] };
    case "funding_sources":
      return { sql: "funding_source_id = ANY($1::uuid[])", params: [scope.ids] };
    case "locations":
      return { sql: "location_id = ANY($1::uuid[])", params: [scope.ids] };
    default:
      return { sql: "FALSE", params: [] };
  }
}

const SIN_DIGITS = /^(\d{3})(\d{3})(\d{3})$/;

export function maskSin(sin: string): string {
  const digits = sin.replace(/\D/g, "");
  const match = SIN_DIGITS.exec(digits);
  if (!match) throw new CanDoError("SIN");
  return `*** *** ${match[3]}`;
}

export interface RevealAudit {
  action: "sensitive.reveal";
  reason: string;
  subjectType: "person";
  subjectId: string;
  field: "sin";
}

/** Returns the full SIN once. The caller writes the audit row and does not log the value. */
export function revealSin(input: {
  personId: string;
  sin: string;
  reason: string;
  grants: readonly RoleGrant[];
}): { sin: string; audit: RevealAudit } {
  if (input.reason.trim() === "") throw new CanDoError("REASON_REQUIRED");
  if (!allows(input.grants, { action: "reveal", fieldClass: "payroll_restricted", entity: "person" })) {
    throw new CanDoError("NOT_ALLOWED");
  }
  return {
    sin: input.sin,
    audit: {
      action: "sensitive.reveal",
      reason: input.reason.trim(),
      subjectType: "person",
      subjectId: input.personId,
      field: "sin",
    },
  };
}

const SENSITIVE_KEY = /sin|bank|garnish|health|self_identification|date_of_birth/i;

/** Removes known sensitive keys before anything is written to a log. */
export function redactForLog(value: unknown): unknown {
  if (Array.isArray(value)) return value.map((item) => redactForLog(item));
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value)) {
      if (SENSITIVE_KEY.test(key)) continue;
      out[key] = redactForLog(item);
    }
    return out;
  }
  return value;
}
