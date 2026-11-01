import type { AttributeMap, VersionRow } from "@candohr/shared";
import type { AssignmentRecord, PositionRecord, World } from "./types.ts";

export function emptyWorld(): World {
  return {
    positions: {},
    assignments: {},
    employments: {},
    locations: {},
    profiles: {},
    people: {},
    orgUnits: {},
    agreements: {},
    audits: [],
    outbox: [],
    nextAuditId: 1,
  };
}

export function addPosition(
  world: World,
  input: { id: string; status?: PositionRecord["status"]; version?: number; orgUnitId: string },
): void {
  world.positions[input.id] = {
    id: input.id,
    status: input.status ?? "active",
    version: input.version ?? 1,
    orgUnitId: input.orgUnitId,
  };
}

export function addEmployment(world: World, input: { id: string; personId: string; assignmentIds?: string[] }): void {
  world.employments[input.id] = {
    id: input.id,
    personId: input.personId,
    status: "active",
    assignmentIds: input.assignmentIds ?? [],
  };
}

export function addLocation(world: World, input: { id: string; province: string }): void {
  world.locations[input.id] = input;
}

export function addProfile(
  world: World,
  input: { assignmentId: string; taxProvince: string; overridden?: boolean },
): void {
  world.profiles[input.assignmentId] = {
    assignmentId: input.assignmentId,
    taxProvince: input.taxProvince,
    overridden: input.overridden ?? false,
  };
}

/**
 * One current assignment slice, plus any later slices (a raise that starts next year).
 * `supersededAt` stays empty: these rows are what the company believes today.
 */
export function addAssignment(
  world: World,
  input: {
    id: string;
    version?: number;
    employmentId: string;
    personId: string;
    positionId: string | null;
    orgUnitId: string;
    locationId?: string | null;
    rate?: string | null;
    status?: string;
    validStart: string;
    validEnd?: string | null;
    recordedAt: string;
    explicitKeys?: readonly string[];
    later?: {
      validStart: string;
      validEnd?: string | null;
      attributes: AttributeMap;
      explicitKeys: readonly string[];
      recordedAt?: string;
    }[];
  },
): AssignmentRecord {
  const attributes: AttributeMap = {
    orgUnitId: input.orgUnitId,
    positionId: input.positionId,
    locationId: input.locationId ?? null,
    rate: input.rate ?? null,
    status: input.status ?? "open",
  };
  const explicit = input.explicitKeys ?? Object.keys(attributes).filter((key) => attributes[key] !== null);
  const versions: VersionRow[] = [
    row(input.id, input.validStart, input.validEnd ?? null, input.recordedAt, attributes, explicit),
  ];
  for (const later of input.later ?? []) {
    versions.push(
      row(input.id, later.validStart, later.validEnd ?? null, later.recordedAt ?? input.recordedAt, later.attributes, later.explicitKeys),
    );
  }
  const record: AssignmentRecord = {
    id: input.id,
    employmentId: input.employmentId,
    personId: input.personId,
    positionId: input.positionId,
    version: input.version ?? 1,
    versions,
  };
  world.assignments[input.id] = record;
  const employment = world.employments[input.employmentId];
  if (employment && !employment.assignmentIds.includes(input.id)) {
    employment.assignmentIds.push(input.id);
  }
  return record;
}

function row(
  entityId: string,
  validStart: string,
  validEnd: string | null,
  recordedAt: string,
  attributes: AttributeMap,
  explicitKeys: readonly string[],
): VersionRow {
  return {
    versionId: crypto.randomUUID(),
    entityId,
    validStart,
    validEnd,
    recordedAt,
    supersededAt: null,
    changeSetId: "seed",
    attributes: { ...attributes },
    explicitKeys: [...explicitKeys],
  };
}
