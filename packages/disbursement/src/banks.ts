import { createHash } from "node:crypto";
import { DisbursementError, money, sum } from "./money.ts";

export type BankFormat = "cpa005" | "pain001";

/** CanDo test profiles. Data-centre numbers are samples, not a bank's spec sheet. */
export type BankProfile = {
  id: string;
  format: BankFormat;
  originatorId: string;
  creationNumber: string;
  dataCentre?: string;
  memberId?: string;
};

export const BANK_PROFILES: readonly BankProfile[] = [
  { id: "rbc", format: "cpa005", originatorId: "RBC0000001", creationNumber: "0001", dataCentre: "00310" },
  { id: "td", format: "cpa005", originatorId: "TD00000001", creationNumber: "0001", dataCentre: "00420" },
  { id: "bmo", format: "cpa005", originatorId: "BMO0000001", creationNumber: "0001", dataCentre: "00160" },
  { id: "cibc", format: "cpa005", originatorId: "CIBC000001", creationNumber: "0001", dataCentre: "00100" },
  { id: "national_bank", format: "cpa005", originatorId: "NBC0000001", creationNumber: "0001", dataCentre: "00061" },
  { id: "desjardins", format: "cpa005", originatorId: "DESJ000001", creationNumber: "0001", dataCentre: "81520" },
  { id: "credit_union", format: "cpa005", originatorId: "CU00000001", creationNumber: "0001", dataCentre: "82800" },
  { id: "scotiabank", format: "pain001", originatorId: "BNS0000001", creationNumber: "0001", memberId: "000212345" },
];

export type DirectDeposit = {
  name: string;
  amount: string;
  institution: string;
  account: string;
};

export type BankFileInput = {
  profile: BankProfile;
  fileDate: string;
  payDate: string;
  payments: readonly DirectDeposit[];
  runTotal: string;
  approved: boolean;
  releasers: readonly string[];
  employerShortName?: string;
  employerLongName?: string;
};

export type BankFile = {
  bytes: Uint8Array;
  checksum: string;
  controlTotal: string;
  format: BankFormat;
  sftp: false;
};

const RECORD_LENGTH = 1464;
const SEGMENT_LENGTH = 240;

export function julianDate(iso: string): string {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) throw new DisbursementError("DATE");
  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const utc = Date.UTC(year, month - 1, day);
  const check = new Date(utc);
  if (check.getUTCFullYear() !== year || check.getUTCMonth() !== month - 1 || check.getUTCDate() !== day) {
    throw new DisbursementError("DATE");
  }
  const dayOfYear = Math.floor((utc - Date.UTC(year, 0, 1)) / 86_400_000) + 1;
  return `0${String(year % 100).padStart(2, "0")}${String(dayOfYear).padStart(3, "0")}`;
}

function exact(value: string, length: number): string {
  if (value.length !== length) throw new DisbursementError("FIELD");
  return value;
}

function text(value: string, length: number): string {
  if (value.length > length) throw new DisbursementError("FIELD");
  return value.padEnd(length, " ");
}

function digits(value: string, length: number): string {
  if (!/^\d+$/.test(value) || value.length > length) throw new DisbursementError("FIELD");
  return value.padStart(length, "0");
}

function cents(amount: string, length: number): string {
  const fixed = money(amount);
  if (fixed.startsWith("-")) throw new DisbursementError("AMOUNT");
  return digits(fixed.replace(".", ""), length);
}

function assertWidth(value: string, length: number): string {
  if (value.length !== length) throw new DisbursementError("RECORD_LENGTH");
  return value;
}

function headerA(profile: BankProfile, fileDate: string): string {
  // structural: optional value absent; empty string for typing
  const dataCentre = exact(profile.dataCentre ?? "", 5);
  return assertWidth(
    "A" +
      digits("1", 9) +
      exact(profile.originatorId, 10) +
      exact(profile.creationNumber, 4) +
      julianDate(fileDate) +
      dataCentre +
      " ".repeat(20) +
      "CAD" +
      " ".repeat(1406),
    RECORD_LENGTH,
  );
}

function segment(input: {
  amount: string;
  payDate: string;
  institution: string;
  account: string;
  trace: string;
  shortName: string;
  payeeName: string;
  longName: string;
  originatorId: string;
  crossRef: string;
  returnInstitution: string;
  returnAccount: string;
}): string {
  return assertWidth(
    "200" +
      cents(input.amount, 10) +
      julianDate(input.payDate) +
      exact(input.institution, 9) +
      exact(input.account, 12) +
      exact(input.trace, 22) +
      "200" +
      text(input.shortName, 15) +
      text(input.payeeName, 30) +
      text(input.longName, 30) +
      exact(input.originatorId, 10) +
      exact(input.crossRef, 19) +
      exact(input.returnInstitution, 9) +
      exact(input.returnAccount, 12) +
      " ".repeat(15) +
      " ".repeat(22) +
      " ".repeat(2) +
      " ".repeat(11),
    SEGMENT_LENGTH,
  );
}

function creditRecord(profile: BankProfile, recordNumber: number, segments: readonly string[]): string {
  const padded = [...segments];
  while (padded.length < 6) padded.push(" ".repeat(SEGMENT_LENGTH));
  return assertWidth(
    "C" + digits(String(recordNumber), 9) + exact(profile.originatorId, 10) + exact(profile.creationNumber, 4) + padded.slice(0, 6).join(""),
    RECORD_LENGTH,
  );
}

function trailer(profile: BankProfile, recordNumber: number, creditValue: string, creditCount: number): string {
  return assertWidth(
    "Z" +
      digits(String(recordNumber), 9) +
      exact(profile.originatorId, 10) +
      exact(profile.creationNumber, 4) +
      digits("0", 14) +
      digits("0", 8) +
      cents(creditValue, 14) +
      digits(String(creditCount), 8) +
      " ".repeat(1396),
    RECORD_LENGTH,
  );
}

function cpa005(input: BankFileInput, controlTotal: string): string {
  const shortName = input.employerShortName ?? "CANDOHR"; // structural: file layout label when employer name omitted in tests
  // structural: file layout labels for bank export tests
  const longName = input.employerLongName ?? "CANDO HR PAYROLL";
  const returnInstitution = "000100001";
  const returnAccount = "000000000001";
  const segments: string[] = [];
  input.payments.forEach((payment, index) => {
    const sequence = String(index + 1).padStart(8, "0");
    segments.push(
      segment({
        amount: payment.amount,
        payDate: input.payDate,
        institution: payment.institution,
        account: payment.account,
        trace: `${input.profile.originatorId}${input.profile.creationNumber}${sequence}`,
        shortName,
        payeeName: payment.name,
        longName,
        originatorId: input.profile.originatorId,
        crossRef: `P${String(index + 1).padStart(18, "0")}`,
        returnInstitution,
        returnAccount,
      }),
    );
  });
  const records = [headerA(input.profile, input.fileDate)];
  // structural: loop index or iteration bound, not a business default
  for (let offset = 0; offset < segments.length; offset += 6) {
    records.push(creditRecord(input.profile, records.length + 1, segments.slice(offset, offset + 6)));
  }
  if (segments.length === 0) records.push(creditRecord(input.profile, records.length + 1, []));
  records.push(trailer(input.profile, records.length + 1, controlTotal, input.payments.length));
  return records.join("");
}

function xml(value: string): string {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
}

function pain001(input: BankFileInput, controlTotal: string): string {
  // structural: optional value absent; empty string for typing
  const memberId = exact(input.profile.memberId ?? "", 9);
  const msgId = `CANDO-${input.fileDate.replaceAll("-", "")}-${input.profile.creationNumber}`;
  const transactions = input.payments
    .map((payment, index) =>
      [
        "      <CdtTrfTxInf>",
        "        <PmtId>",
        `          <EndToEndId>E2E-${String(index + 1).padStart(4, "0")}</EndToEndId>`,
        "        </PmtId>",
        "        <Amt>",
        `          <InstdAmt Ccy="CAD">${money(payment.amount)}</InstdAmt>`,
        "        </Amt>",
        "        <CdtrAgt>",
        "          <FinInstnId>",
        "            <ClrSysMmbId>",
        `              <MmbId>${xml(payment.institution)}</MmbId>`,
        "            </ClrSysMmbId>",
        "          </FinInstnId>",
        "        </CdtrAgt>",
        "        <Cdtr>",
        `          <Nm>${xml(payment.name)}</Nm>`,
        "        </Cdtr>",
        "        <CdtrAcct>",
        "          <Id>",
        "            <Othr>",
        `              <Id>${xml(payment.account)}</Id>`,
        "            </Othr>",
        "          </Id>",
        "        </CdtrAcct>",
        "      </CdtTrfTxInf>",
      ].join("\n"),
    )
    .join("\n");
  return [
    `<?xml version="1.0" encoding="UTF-8"?>`,
    `<Document xmlns="urn:iso:std:iso:20022:tech:xsd:pain.001.001.03">`,
    `  <CstmrCdtTrfInitn>`,
    `    <GrpHdr>`,
    `      <MsgId>${msgId}</MsgId>`,
    `      <CreDtTm>${input.fileDate}T00:00:00Z</CreDtTm>`,
    `      <NbOfTxs>${input.payments.length}</NbOfTxs>`,
    `      <CtrlSum>${money(controlTotal)}</CtrlSum>`,
    `      <InitgPty>`,
    `        <Nm>CANDO HR</Nm>`,
    `        <Id>`,
    `          <OrgId>`,
    `            <Othr>`,
    `              <Id>${xml(input.profile.originatorId)}</Id>`,
    `            </Othr>`,
    `          </OrgId>`,
    `        </Id>`,
    `      </InitgPty>`,
    `    </GrpHdr>`,
    `    <PmtInf>`,
    `      <PmtInfId>${msgId}</PmtInfId>`,
    `      <PmtMtd>TRF</PmtMtd>`,
    `      <ReqdExctnDt>${input.payDate}</ReqdExctnDt>`,
    `      <Dbtr>`,
    `        <Nm>CANDO HR</Nm>`,
    `      </Dbtr>`,
    `      <DbtrAcct>`,
    `        <Id>`,
    `          <Othr>`,
    `            <Id>${memberId}</Id>`,
    `          </Othr>`,
    `        </Id>`,
    `      </DbtrAcct>`,
    `      <DbtrAgt>`,
    `        <FinInstnId>`,
    `          <ClrSysMmbId>`,
    `            <MmbId>${memberId}</MmbId>`,
    `          </ClrSysMmbId>`,
    `        </FinInstnId>`,
    `      </DbtrAgt>`,
    transactions,
    `    </PmtInf>`,
    `  </CstmrCdtTrfInitn>`,
    `</Document>`,
    "",
  ].join("\n");
}

export function releaseBankFile(input: BankFileInput): BankFile {
  if (!input.approved) throw new DisbursementError("RUN_NOT_APPROVED");
  const releasers = input.releasers.map((id) => id.trim()).filter((id) => id !== "");
  if (releasers.length !== 2 || releasers[0] === releasers[1]) throw new DisbursementError("DUAL_CONTROL");
  exact(input.profile.originatorId, 10);
  exact(input.profile.creationNumber, 4);
  const controlTotal = sum(input.payments.map((payment) => payment.amount));
  if (controlTotal !== money(input.runTotal)) throw new DisbursementError("CONTROL_TOTAL_MISMATCH");
  const text = input.profile.format === "cpa005" ? cpa005(input, controlTotal) : pain001(input, controlTotal);
  if (input.profile.format === "cpa005" && (text.length % RECORD_LENGTH !== 0 || text.includes("\n"))) {
    throw new DisbursementError("RECORD_LENGTH");
  }
  const bytes = new TextEncoder().encode(text);
  return {
    bytes,
    checksum: createHash("sha256").update(bytes).digest("hex"),
    controlTotal,
    format: input.profile.format,
    sftp: false,
  };
}
