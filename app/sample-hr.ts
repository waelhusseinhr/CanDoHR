import type { PersonListItem, PositionView, ProfileTab, ProfileView } from "@candohr/core/screens";

/** Sample records for the screens. The database is not connected. */
export const SAMPLE_PEOPLE: readonly PersonListItem[] = [
  { id: "ana", preferredName: "Ana Lopez", title: "Clerk", orgUnitName: "Recreation" },
  { id: "sam", preferredName: "Sam Roy", title: "Clerk", orgUnitName: "Recreation" },
];

export const SAMPLE_PROFILES: Readonly<Record<string, ProfileView>> = {
  ana: {
    id: "ana",
    legalName: "Ana Lopez",
    preferredName: "Ana Lopez",
    sinMasked: "*** *** 782",
    taxProvince: "MB",
    askWorkLocation: false,
    assignments: [
      {
        id: "asg-ana",
        type: "regular",
        status: "active",
        primary: true,
        fte: "1.00",
        rate: "20.00",
        agreementId: "Inside",
        managerName: "Sam Roy",
        orgUnitName: "Recreation",
        costCentreId: null,
      },
    ],
    history: [{ label: "active", date: "2026-12-01" }],
  },
  sam: {
    id: "sam",
    legalName: "Sam Roy",
    preferredName: "Sam Roy",
    sinMasked: null,
    taxProvince: "MB",
    askWorkLocation: false,
    assignments: [
      {
        id: "asg-sam",
        type: "regular",
        status: "active",
        primary: true,
        fte: "1.00",
        rate: "30.00",
        agreementId: "Inside",
        managerName: null,
        orgUnitName: "Recreation",
        costCentreId: null,
      },
    ],
    history: [{ label: "active", date: "2026-01-01" }],
  },
};

export const SAMPLE_POSITIONS: readonly PositionView[] = [
  {
    id: "clerk",
    title: "Clerk",
    status: "filled",
    fteBudget: "1.00",
    holderName: "Ana Lopez",
    orgUnitName: "Recreation",
  },
  {
    id: "casual",
    title: "Casual",
    status: "vacant",
    fteBudget: "0.50",
    holderName: null,
    orgUnitName: "Recreation",
  },
];

export function profileTab(value: string | undefined): ProfileTab {
  if (value === "job" || value === "pay" || value === "leave" || value === "documents" || value === "history") return value;
  return "overview";
}
