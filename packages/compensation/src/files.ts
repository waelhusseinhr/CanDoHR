import { dec, moneyStr } from "./decimal.ts";
import { fail } from "./errors.ts";

export type EnrolmentRow = {
  personId: string;
  planCode: string;
  planKind: string;
  action: string;
  effective: string;
  waiting: boolean;
  cobOrderSet: boolean;
};

export function carrierEnrolmentFile(rows: EnrolmentRow[]): { body: string; excluded: { personId: string; planKind: string; code: string }[] } {
  const kinds = new Map<string, number>();
  for (const row of rows) {
    const key = `${row.personId}\u0000${row.planKind}`;
    const current = kinds.get(key);
    kinds.set(key, current === undefined ? 1 : current + 1);
  }
  const excluded: { personId: string; planKind: string; code: string }[] = [];
  const lines = ["CANDO-CARRIER-ENROLMENT v1"];
  const sorted = [...rows].sort((a, b) => (a.personId < b.personId ? -1 : a.personId > b.personId ? 1 : a.planCode < b.planCode ? -1 : 1));
  for (const row of sorted) {
    const count = kinds.get(`${row.personId}\u0000${row.planKind}`);
    if (count !== undefined && count > 1 && !row.cobOrderSet) {
      excluded.push({ personId: row.personId, planKind: row.planKind, code: "COB_ORDER_NOT_SET" });
      continue;
    }
    if (row.waiting) {
      excluded.push({ personId: row.personId, planKind: row.planKind, code: "WAITING" });
      continue;
    }
    lines.push([row.personId, row.planCode, row.action, row.effective].join("|"));
  }
  return { body: `${lines.join("\n")}\n`, excluded };
}

export function acknowledgementTasks(errors: { personId: string; message: string }[]): { personId: string; message: string }[] {
  return errors.map((error) => ({ personId: error.personId, message: error.message }));
}

export type RemitLine = { personId: string; hours: string; rate: string };

export function pensionRemittance(layout: string, lines: RemitLine[]): string {
  if (!layout) fail("INPUT_REQUIRED", "layout");
  const out = [`CANDO-PENSION ${layout}`];
  const sorted = [...lines].sort((a, b) => (a.personId < b.personId ? -1 : a.personId > b.personId ? 1 : 0));
  for (const line of sorted) {
    if (!line.rate) fail("INPUT_REQUIRED", "rate");
    const amount = moneyStr(dec(line.hours).mul(dec(line.rate)));
    out.push([line.personId, line.hours, line.rate, amount].join("|"));
  }
  return `${out.join("\n")}\n`;
}
