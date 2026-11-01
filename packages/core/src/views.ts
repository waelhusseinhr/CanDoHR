export interface PersonListItem {
  id: string;
  preferredName: string;
  title: string;
  orgUnitName: string;
}

export interface AssignmentView {
  id: string;
  type: string;
  status: string;
  primary: boolean;
  fte: string;
  rate: string;
  agreementId: string | null;
  managerName: string | null;
  orgUnitName: string;
  costCentreId: string | null;
}

export interface HistoryEntry {
  label: string;
  date: string;
}

export interface ProfileView {
  id: string;
  legalName: string;
  preferredName: string;
  sinMasked: string | null;
  taxProvince: string | null;
  askWorkLocation: boolean;
  assignments: AssignmentView[];
  history: HistoryEntry[];
}

export interface PositionView {
  id: string;
  title: string;
  status: "vacant" | "filled";
  fteBudget: string;
  holderName: string | null;
  orgUnitName: string;
}

export type ProfileTab = "overview" | "job" | "pay" | "leave" | "documents" | "history";
