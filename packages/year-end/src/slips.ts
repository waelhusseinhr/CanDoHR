import { add, cmp, money, sub } from "@candohr/disbursement";
import { YearEndError } from "./errors.ts";

export type ReportCode = "O" | "A";

export type Transmitter = {
  businessNumber: string;
  language: "E" | "F";
  country: string;
  contactName: string;
  areaCode: string;
  phone: string;
  email: string;
  name?: string;
  submissionId?: string;
};

export type T4SlipInput = {
  surname: string;
  givenName?: string;
  sin: string;
  payrollAccount: string;
  province: string;
  cppExempt?: "0" | "1";
  eiExempt?: "0" | "1";
  employmentIncome?: string;
  cpp?: string;
  ei?: string;
  tax?: string;
  pensionable: string;
  insurable: string;
};

export type T4ASlipInput = {
  surname?: string;
  givenName?: string;
  sin: string;
  recipientBn: string;
  payrollAccount: string;
  otherIncome?: string;
  tax?: string;
};

function esc(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function tag(name: string, value: string | null | undefined): string | null {
  if (value === null || value === undefined || value === "") return null;
  return `<${name}>${esc(value)}</${name}>`;
}

function group(name: string, children: (string | null)[]): string | null {
  const body = children.filter((child): child is string => child !== null);
  if (body.length === 0) return null;
  return `<${name}>${body.join("")}</${name}>`;
}

function amount(value: string | undefined): string | null {
  if (value === undefined) return null;
  const fixed = money(value);
  if (fixed === "0.00") return null;
  return fixed;
}

function transmitterXml(input: Transmitter, summaryCount: number): string {
  const block = group("T619", [
    group("TransmitterAccountNumber", [tag("bn15", input.businessNumber)]),
    tag("sbmt_ref_id", input.submissionId),
    tag("summ_cnt", String(summaryCount)),
    tag("lang_cd", input.language),
    input.name ? group("TransmitterName", [tag("l1_nm", input.name)]) : null,
    tag("TransmitterCountryCode", input.country),
    group("CNTC", [
      tag("cntc_nm", input.contactName),
      tag("cntc_area_cd", input.areaCode),
      tag("cntc_phn_nbr", input.phone),
      tag("cntc_email_area", input.email),
    ]),
  ]);
  if (!block) throw new YearEndError("INPUT_REQUIRED");
  return block;
}

function t4Slip(slip: T4SlipInput, report: ReportCode): string {
  const income = amount(slip.employmentIncome);
  const cpp = amount(slip.cpp);
  const ei = amount(slip.ei);
  const tax = amount(slip.tax);
  const block = group("T4Slip", [
    group("EMPE_NM", [tag("snm", slip.surname), tag("gvn_nm", slip.givenName)]),
    tag("sin", slip.sin),
    tag("bn", slip.payrollAccount),
    tag("cpp_qpp_xmpt_cd", slip.cppExempt ?? "0"),
    tag("ei_xmpt_cd", slip.eiExempt ?? "0"),
    tag("rpt_tcd", report),
    tag("empt_prov_cd", slip.province),
    group("T4_AMT", [
      income ? tag("empt_incamt", income) : null,
      cpp ? tag("cpp_cntrb_amt", cpp) : null,
      ei ? tag("empe_eip_amt", ei) : null,
      tax ? tag("itx_ddct_amt", tax) : null,
      tag("ei_insu_ern_amt", money(slip.insurable)),
      tag("cpp_qpp_ern_amt", money(slip.pensionable)),
    ]),
  ]);
  if (!block) throw new YearEndError("INPUT_REQUIRED");
  return block;
}

function sumField(slips: readonly T4SlipInput[], field: "employmentIncome" | "cpp" | "ei" | "tax"): string | null {
  const values = slips.map((slip) => amount(slip[field])).filter((value): value is string => value !== null);
  if (values.length === 0) return null;
  return values.reduce((total, value) => add(total, value));
}

export function buildT4Submission(input: {
  transmitter: Transmitter;
  taxYear: string;
  employerName: string;
  report: ReportCode;
  amendmentNote?: string;
  slips: readonly T4SlipInput[];
}): string {
  if (input.slips.length === 0) throw new YearEndError("INPUT_REQUIRED");
  const accounts = new Set(input.slips.map((slip) => slip.payrollAccount));
  if (accounts.size !== 1) throw new YearEndError("PAYROLL_ACCOUNT");
  const account = input.slips[0]!.payrollAccount;
  const income = sumField(input.slips, "employmentIncome");
  const cpp = sumField(input.slips, "cpp");
  const ei = sumField(input.slips, "ei");
  const tax = sumField(input.slips, "tax");
  const summary = group("T4Summary", [
    tag("bn", account),
    group("EMPR_NM", [tag("l1_nm", input.employerName)]),
    group("CNTC", [
      tag("cntc_nm", input.transmitter.contactName),
      tag("cntc_area_cd", input.transmitter.areaCode),
      tag("cntc_phn_nbr", input.transmitter.phone),
    ]),
    tag("tx_yr", input.taxYear),
    tag("slp_cnt", String(input.slips.length)),
    tag("rpt_tcd", input.report),
    tag("fileramendmentnote", input.report === "A" ? input.amendmentNote : undefined),
    group("T4_TAMT", [
      income ? tag("tot_empt_incamt", income) : null,
      cpp ? tag("tot_empe_cpp_amt", cpp) : null,
      ei ? tag("tot_empe_eip_amt", ei) : null,
      tax ? tag("tot_itx_ddct_amt", tax) : null,
    ]),
  ]);
  return [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<Submission>`,
    transmitterXml(input.transmitter, 1),
    `<Return><T4>`,
    ...input.slips.map((slip) => t4Slip(slip, input.report)),
    summary,
    `</T4></Return>`,
    `</Submission>`,
    ``,
  ].join("\n");
}

export function buildT4ASubmission(input: {
  transmitter: Transmitter;
  taxYear: string;
  payerName: string;
  report: ReportCode;
  amendmentNote?: string;
  slips: readonly T4ASlipInput[];
}): string {
  if (input.slips.length === 0) throw new YearEndError("INPUT_REQUIRED");
  const accounts = new Set(input.slips.map((slip) => slip.payrollAccount));
  if (accounts.size !== 1) throw new YearEndError("PAYROLL_ACCOUNT");
  const account = input.slips[0]!.payrollAccount;
  const taxes = input.slips.map((slip) => amount(slip.tax)).filter((value): value is string => value !== null);
  const other = input.slips.map((slip) => amount(slip.otherIncome)).filter((value): value is string => value !== null);
  const slips = input.slips.map((slip) => {
    const otherIncome = amount(slip.otherIncome);
    const tax = amount(slip.tax);
    const block = group("T4ASlip", [
      slip.surname ? group("RCPNT_NM", [tag("snm", slip.surname), tag("gvn_nm", slip.givenName)]) : null,
      tag("sin", slip.sin),
      tag("rcpnt_bn", slip.recipientBn),
      tag("bn", slip.payrollAccount),
      tag("rpt_tcd", input.report),
      otherIncome ? group("OTH_INFO", [tag("oth_incamt", otherIncome)]) : null,
      tax ? group("T4A_AMT", [tag("itx_ddct_amt", tax)]) : null,
    ]);
    if (!block) throw new YearEndError("INPUT_REQUIRED");
    return block;
  });
  const summary = group("T4ASummary", [
    tag("bn", account),
    group("PAYR_NM", [tag("l1_nm", input.payerName)]),
    group("CNTC", [
      tag("cntc_nm", input.transmitter.contactName),
      tag("cntc_area_cd", input.transmitter.areaCode),
      tag("cntc_phn_nbr", input.transmitter.phone),
    ]),
    tag("tx_yr", input.taxYear),
    tag("slp_cnt", String(input.slips.length)),
    tag("rpt_tcd", input.report),
    tag("fileramendmentnote", input.report === "A" ? input.amendmentNote : undefined),
    group("T4A_TAMT", [
      taxes.length > 0 ? tag("tot_itx_dedn_amt", taxes.reduce((total, value) => add(total, value))) : null,
      other.length > 0 ? tag("rpt_tot_oth_info_amt", other.reduce((total, value) => add(total, value))) : null,
    ]),
  ]);
  return [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<Submission>`,
    transmitterXml(input.transmitter, 1),
    `<Return><T4A>`,
    ...slips,
    summary,
    `</T4A></Return>`,
    `</Submission>`,
    ``,
  ].join("\n");
}

export type SlipAmounts = {
  employmentIncome: string;
  cpp: string;
  ei: string;
  tax: string;
  pensionable: string;
  insurable: string;
};

export function contributionRoom(maximum: string, imported: string, earnedHere: string): string {
  const room = sub(money(maximum), add(money(imported), money(earnedHere)));
  return cmp(room, "0.00") < 0 ? "0.00" : room;
}

/** One slip for the tax year. Imported year-to-date and CanDo amounts are added, and both count toward the maximums the caller supplies. */
export function combineYearSlip(input: {
  personId: string;
  payrollAccountId: string;
  province: string;
  imported: SlipAmounts;
  cando: SlipAmounts;
  cppMaximum: string;
  eiMaximum: string;
}): { personId: string; payrollAccountId: string; province: string; slipCount: 1; amounts: SlipAmounts; cppRoom: string; eiRoom: string } {
  const amounts: SlipAmounts = {
    employmentIncome: add(input.imported.employmentIncome, input.cando.employmentIncome),
    cpp: add(input.imported.cpp, input.cando.cpp),
    ei: add(input.imported.ei, input.cando.ei),
    tax: add(input.imported.tax, input.cando.tax),
    pensionable: add(input.imported.pensionable, input.cando.pensionable),
    insurable: add(input.imported.insurable, input.cando.insurable),
  };
  return {
    personId: input.personId,
    payrollAccountId: input.payrollAccountId,
    province: input.province,
    slipCount: 1,
    amounts,
    cppRoom: contributionRoom(input.cppMaximum, input.imported.cpp, input.cando.cpp),
    eiRoom: contributionRoom(input.eiMaximum, input.imported.ei, input.cando.ei),
  };
}

export type PierRow = {
  personId: string;
  kind: "cpp" | "ei";
  deducted: string;
  calculated: string;
};

export function pierReport(
  employees: readonly {
    personId: string;
    cppDeducted: string;
    cppCalculated: string;
    eiDeducted: string;
    eiCalculated: string;
  }[],
): PierRow[] {
  const rows: PierRow[] = [];
  for (const employee of employees) {
    const cppDeducted = money(employee.cppDeducted);
    const cppCalculated = money(employee.cppCalculated);
    const eiDeducted = money(employee.eiDeducted);
    const eiCalculated = money(employee.eiCalculated);
    if (cppDeducted !== cppCalculated) {
      rows.push({ personId: employee.personId, kind: "cpp", deducted: cppDeducted, calculated: cppCalculated });
    }
    if (eiDeducted !== eiCalculated) {
      rows.push({ personId: employee.personId, kind: "ei", deducted: eiDeducted, calculated: eiCalculated });
    }
  }
  return rows;
}
