import { isValidSin } from "@candohr/core";

export interface DemoAssignment {
  id: string;
  positionId: string;
  orgUnitPath: string;
  agreementCode: string | null;
  workLocation: string;
  jurisdiction: string;
  funding: string | null;
  schedule: string | null;
  pensionStyle: string | null;
  onReserve: boolean | null;
  section87: boolean;
}

export interface DemoPerson {
  id: string;
  displayName: string;
  /** Luhn-valid digits generated for this demo. Labeled test data. Never a real SIN. */
  testSin: string;
  sinLabel: "TEST_DATA";
  assignments: DemoAssignment[];
}

export interface DemoTenant {
  code: string;
  name: string;
  lightOrgMode: false;
  positionsRequired: true;
  jurisdiction: string;
  people: DemoPerson[];
}

const MUNICIPAL_UNITS = [
  "corporate/finance",
  "corporate/people",
  "community/fire",
  "community/works",
  "library/branches",
] as const;

const MUNICIPAL_AGREEMENTS = ["example", "inside", "outside", "fire"] as const;

function testSin(serial: number): string {
  const body = `8${String(serial).padStart(7, "0")}`;
  let check = 0;
  while (check < 10) {
    const candidate = `${body}${String(check)}`;
    if (isValidSin(candidate)) return candidate;
    check += 1;
  }
  throw new Error("SIN_INVALID");
}

function person(input: {
  code: string;
  serial: number;
  sinSerial: number;
  assignments: DemoAssignment[];
}): DemoPerson {
  const label = String(input.serial).padStart(4, "0");
  return {
    id: `${input.code}-person-${label}`,
    displayName: `Fictional ${input.code} ${label}`,
    testSin: testSin(input.sinSerial),
    sinLabel: "TEST_DATA",
    assignments: input.assignments,
  };
}

function assignment(input: DemoAssignment): DemoAssignment {
  return input;
}

function at<T>(items: readonly T[], index: number): T {
  const value = items[index];
  if (value === undefined) throw new Error("DEMO_INDEX");
  return value;
}

function northernLights(): DemoTenant {
  const people: DemoPerson[] = [];
  let index = 0;
  while (index < 60) {
    const serial = index + 1;
    const province = index % 2 === 0 ? "AB" : "BC";
    const label = String(serial).padStart(4, "0");
    people.push(
      person({
        code: "northern-lights",
        serial,
        sinSerial: serial,
        assignments: [
          assignment({
            id: `northern-lights-assignment-${label}`,
            positionId: `northern-lights-position-${label}`,
            orgUnitPath: "office/programs",
            agreementCode: null,
            workLocation: province,
            jurisdiction: province,
            funding: "grant",
            schedule: null,
            pensionStyle: null,
            onReserve: null,
            section87: false,
          }),
        ],
      }),
    );
    index += 1;
  }
  return {
    code: "northern-lights",
    name: "Northern Lights Non-Profit",
    lightOrgMode: false,
    positionsRequired: true,
    jurisdiction: "AB-BC",
    people,
  };
}

function exampleMunicipality(): DemoTenant {
  const people: DemoPerson[] = [];
  let index = 0;
  while (index < 2400) {
    const serial = index + 1;
    const label = String(serial).padStart(4, "0");
    const unit = at(MUNICIPAL_UNITS, index % MUNICIPAL_UNITS.length);
    const agreement = at(MUNICIPAL_AGREEMENTS, index % MUNICIPAL_AGREEMENTS.length);
    const primary = assignment({
      id: `example-municipality-assignment-${label}`,
      positionId: `example-municipality-position-${label}`,
      orgUnitPath: unit,
      agreementCode: agreement,
      workLocation: "ON",
      jurisdiction: "ON",
      funding: null,
      schedule: index % 50 === 0 ? "platoon" : null,
      pensionStyle: "omers_style",
      onReserve: null,
      section87: false,
    });
    const assignments = [primary];
    if (index % 100 === 0) {
      const secondAgreement = at(MUNICIPAL_AGREEMENTS, (index + 1) % MUNICIPAL_AGREEMENTS.length);
      assignments.push(
        assignment({
          id: `example-municipality-assignment-${label}-b`,
          positionId: `example-municipality-position-${label}-b`,
          orgUnitPath: "library/branches",
          agreementCode: secondAgreement,
          workLocation: "ON",
          jurisdiction: "ON",
          funding: null,
          schedule: null,
          pensionStyle: "omers_style",
          onReserve: null,
          section87: false,
        }),
      );
    }
    people.push(
      person({
        code: "example-municipality",
        serial,
        sinSerial: 10000 + serial,
        assignments,
      }),
    );
    index += 1;
  }
  return {
    code: "example-municipality",
    name: "Example Municipality",
    lightOrgMode: false,
    positionsRequired: true,
    jurisdiction: "ON",
    people,
  };
}

function exampleFirstNation(): DemoTenant {
  const people: DemoPerson[] = [];
  let index = 0;
  while (index < 180) {
    const serial = index + 1;
    const label = String(serial).padStart(4, "0");
    const onReserve = index % 2 === 0;
    people.push(
      person({
        code: "example-first-nation",
        serial,
        sinSerial: 20000 + serial,
        assignments: [
          assignment({
            id: `example-first-nation-assignment-${label}`,
            positionId: `example-first-nation-position-${label}`,
            orgUnitPath: onReserve ? "administration/on-reserve" : "administration/off-reserve",
            agreementCode: null,
            workLocation: onReserve ? "MB-on-reserve" : "MB-off-reserve",
            jurisdiction: "federal",
            funding: null,
            schedule: null,
            pensionStyle: null,
            onReserve,
            section87: onReserve,
          }),
        ],
      }),
    );
    index += 1;
  }
  return {
    code: "example-first-nation",
    name: "Example First Nation",
    lightOrgMode: false,
    positionsRequired: true,
    jurisdiction: "federal",
    people,
  };
}

/** Three fictional tenants from docs/14 §4. Nothing here is written to a database. */
export function buildDemoTenants(): DemoTenant[] {
  return [northernLights(), exampleMunicipality(), exampleFirstNation()];
}

export function demoCatalogue(): { code: string; name: string; employees: number; loadedIntoDatabase: false }[] {
  return buildDemoTenants().map((tenant) => ({
    code: tenant.code,
    name: tenant.name,
    employees: tenant.people.length,
    loadedIntoDatabase: false,
  }));
}
