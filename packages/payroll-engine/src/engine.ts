/**
 * Payroll calculation, ported from reference/payroll_reference.py.
 * Amounts come from the statutory edition for the pay date. Quebec is refused.
 */
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import Decimal from "decimal.js";
import { canonicalize } from "./canonical.ts";

export function statutoryDirectory(): string {
  return fileURLToPath(new URL("../../../rules/statutory/", import.meta.url));
}

Decimal.set({ precision: 28 });

const CENT = new Decimal("0.01");

export class PayrollError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PayrollError";
  }
}

type Obj = Record<string, unknown>;

function isObj(value: unknown): value is Obj {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function D(value: unknown): Decimal {
  return new Decimal(String(value));
}

function money(value: Decimal): Decimal {
  return value.toDecimalPlaces(2, Decimal.ROUND_HALF_UP);
}

function truncCents(value: Decimal): Decimal {
  return value.toDecimalPlaces(2, Decimal.ROUND_DOWN);
}

function moneyText(value: Decimal): string {
  return money(value).toFixed(2);
}

function plain(value: Decimal): string {
  return value.toSignificantDigits(28).toFixed();
}

function amount(input: Obj, key: string): Decimal {
  return D(input[key] ?? 0);
}

function exempt(input: Obj, key: string): boolean {
  return Boolean(input[key] ?? false);
}

function required(input: Obj, key: string): unknown {
  if (!(key in input) || input[key] == null) {
    throw new PayrollError(`INPUT_REQUIRED: ${key}`);
  }
  return input[key];
}

export type PayResult = {
  edition: string;
  tax_year: unknown;
  cpp_employee: string;
  cpp2_employee: string;
  ei_employee: string;
  income_tax: string;
  income_tax_regular: string;
  federal_tax_regular: string;
  provincial_tax_regular: string;
  income_tax_non_periodic: string;
  cpp_employer: string;
  cpp2_employer: string;
  ei_employer: string;
  net_pay: string;
  trace: Array<[string, string]>;
};

type Edition = Obj & {
  id: string;
  effective_from: string;
  effective_to: string;
  tax_year: unknown;
  federal: Obj;
  provinces: Record<string, Obj>;
  cpp: Obj;
  cpp2: Obj;
  ei: Obj;
  non_periodic: Obj;
};

export function loadRules(payDate: string, rulesDir = statutoryDirectory()): Edition {
  const files = readdirSync(rulesDir)
    .filter((name) => name.startsWith("ca-") && name.endsWith(".json"))
    .sort();
  for (const name of files) {
    const edition = JSON.parse(readFileSync(join(rulesDir, name), "utf8")) as Edition;
    if (edition.effective_from <= payDate && payDate <= edition.effective_to) return edition;
  }
  throw new PayrollError(`No statutory rule edition loaded for pay date ${payDate}`);
}

function bracket(brackets: Obj[], annual: Decimal): { rate: Decimal; constant: Decimal } {
  let chosen = brackets[0];
  for (const band of brackets) {
    if (annual.gte(D(band.threshold))) chosen = band;
  }
  return { rate: D(chosen.rate), constant: D(chosen.constant) };
}

function incomeTestedBpa(spec: Obj, income: Decimal): Decimal {
  const max = D(spec.max);
  const min = D(spec.min);
  const start = D(spec.phase_out_start);
  const end = D(spec.phase_out_end);
  if (income.lte(start)) return max;
  if (income.gte(end)) return min;
  return money(max.minus(income.minus(start).mul(max.minus(min).div(end.minus(start)))));
}

function ontarioHealthPremium(spec: Obj, annual: Decimal): Decimal {
  const bands = spec.bands as Obj[];
  for (let index = 0; index < bands.length - 1; index += 1) {
    const previous = bands[index];
    const next = bands[index + 1];
    if (previous.upto == null || !D(previous.upto).eq(D(next.over))) {
      throw new PayrollError("RULE_SHAPE_UNKNOWN: health_premium_V2 bands are not contiguous");
    }
  }
  if (bands[bands.length - 1].upto != null) {
    throw new PayrollError("RULE_SHAPE_UNKNOWN: the last health_premium_V2 band must be open-ended");
  }
  let chosen = bands[0];
  for (const band of bands) {
    if (annual.gt(D(band.over))) chosen = band;
  }
  return Decimal.min(
    D(chosen.cap),
    D(chosen.base).plus(D(chosen.rate).mul(annual.minus(D(chosen.over)))),
  );
}

type Trace = Array<[string, string]>;

function annualTax(
  edition: Edition,
  province: string,
  annual: Decimal,
  periods: Decimal,
  input: Obj,
  cppForCredit: Decimal,
  eiForCredit: Decimal,
  grossEmployment: Decimal,
  months: Decimal,
  trace: Trace | null,
  tag: string,
): { federal: Decimal; provincial: Decimal } {
  const federal = edition.federal;
  const northern = amount(input, "HD");
  const netIncome = annual.plus(northern);
  const lowest = D(federal.lowest_rate);
  const cpp = edition.cpp;
  const baseRatio = D(cpp.base_rate).div(D(cpp.rate));
  const maxBase = D(cpp.max_base_contribution_for_credit).mul(months).div(12);
  const maxEi = D(edition.ei.max_employee_premium);
  const employmentAmount = D(federal.canada_employment_amount);
  const federalBracket = bracket(federal.brackets as Obj[], annual);
  const federalClaim = input.TC;
  const federalBpa =
    federalClaim == null
      ? incomeTestedBpa(federal.basic_personal_amount as Obj, netIncome)
      : D(federalClaim);
  const k1 = lowest.mul(federalBpa);
  const cppCreditBase = Decimal.min(cppForCredit.mul(baseRatio), maxBase);
  const eiCreditBase = Decimal.min(eiForCredit, maxEi);
  const k2 = lowest.mul(cppCreditBase).plus(lowest.mul(eiCreditBase));
  const k3 = amount(input, "K3");
  const k4 = Decimal.min(lowest.mul(grossEmployment), lowest.mul(employmentAmount));
  const t3 = Decimal.max(
    new Decimal(0),
    federalBracket.rate.mul(annual).minus(federalBracket.constant).minus(k1).minus(k2).minus(k3).minus(k4),
  );
  const t1 = t3;

  const provincial = edition.provinces[province];
  const provincialBracket = bracket(provincial.brackets as Obj[], annual);
  const provincialLowest = D(provincial.lowest_rate);
  const bpa = provincial.basic_personal_amount as Obj;
  let provincialClaim: Decimal;
  if (input.TCP == null) {
    if (bpa.type === "fixed") provincialClaim = D(bpa.amount);
    else if (bpa.type === "income_tested") provincialClaim = incomeTestedBpa(bpa, netIncome);
    else if (bpa.type === "same_as_federal") {
      provincialClaim = incomeTestedBpa(federal.basic_personal_amount as Obj, netIncome);
    } else {
      throw new PayrollError(`RULE_SHAPE_UNKNOWN: provinces.${province}.basic_personal_amount.type ${String(bpa.type)}`);
    }
  } else {
    provincialClaim = D(input.TCP);
  }
  const k1p = provincialLowest.mul(provincialClaim);
  const k2p = provincialLowest.mul(cppCreditBase).plus(provincialLowest.mul(eiCreditBase));
  const k3p = amount(input, "K3P");
  let k4p = new Decimal(0);
  if (isObj(provincial.employment_credit_K4P)) {
    const credit = provincial.employment_credit_K4P;
    k4p = Decimal.min(D(credit.rate).mul(grossEmployment), D(credit.rate).mul(D(credit.amount)));
  }
  let k5p = new Decimal(0);
  if (isObj(provincial.supplemental_credit_K5P)) {
    const credit = provincial.supplemental_credit_K5P;
    k5p = Decimal.max(new Decimal(0), k1p.plus(k2p).minus(D(credit.threshold)).mul(D(credit.rate)));
  }
  const t4 = Decimal.max(
    new Decimal(0),
    provincialBracket.rate
      .mul(annual)
      .minus(provincialBracket.constant)
      .minus(k1p)
      .minus(k2p)
      .minus(k3p)
      .minus(k4p)
      .minus(k5p),
  );

  let v1 = new Decimal(0);
  let v2 = new Decimal(0);
  let reduction = new Decimal(0);
  if (isObj(provincial.surtax_V1)) {
    for (const tier of provincial.surtax_V1.tiers as Obj[]) {
      const over = D(tier.over);
      if (t4.gt(over)) v1 = v1.plus(D(tier.rate).mul(t4.minus(over)));
    }
  }
  if (isObj(provincial.health_premium_V2)) v2 = ontarioHealthPremium(provincial.health_premium_V2, annual);
  if (province === "ON") {
    const taxReduction = provincial.tax_reduction_S as Obj;
    const perDependant = D(taxReduction.per_dependant_Y);
    const dependants = perDependant
      .mul(amount(input, "Y_dependants_under_19"))
      .plus(perDependant.mul(amount(input, "Y_dependants_disabled")));
    const basic = D(taxReduction.basic_amount_S2);
    const combined = t4.plus(v1);
    reduction = Decimal.max(new Decimal(0), Decimal.min(combined, new Decimal(2).mul(basic.plus(dependants)).minus(combined)));
  } else if (province === "BC") {
    const taxReduction = provincial.tax_reduction_S as Obj;
    const credit = D(taxReduction.amount);
    const threshold = D(taxReduction.income_threshold);
    const rate = D(taxReduction.phase_out_rate);
    const cap = D(taxReduction.income_cap);
    if (annual.lte(threshold)) reduction = Decimal.min(t4, credit);
    else if (annual.lte(cap)) reduction = Decimal.min(t4, Decimal.max(new Decimal(0), credit.minus(annual.minus(threshold).mul(rate))));
  }
  const t2 = Decimal.max(new Decimal(0), t4.plus(v1).plus(v2).minus(reduction));

  if (trace) {
    const shown: Record<string, Decimal | string> = {
      A: annual,
      R: federalBracket.rate,
      K: federalBracket.constant,
      TC: federalBpa,
      K1: k1,
      K2: k2,
      K4: k4,
      T3: t3,
      T1: t1,
      V: provincialBracket.rate,
      KP: provincialBracket.constant,
      TCP: provincialClaim,
      K1P: k1p,
      K2P: k2p,
      K4P: k4p,
      K5P: k5p,
      T4: t4,
      V1: v1,
      V2: v2,
      S: reduction,
      T2: t2,
    };
    for (const [key, value] of Object.entries(shown)) {
      const text = value instanceof Decimal && key !== "R" && key !== "V" ? moneyText(value) : plain(value as Decimal);
      trace.push([`${tag}.${key}`, text]);
    }
  }
  return { federal: t1, provincial: t2 };
}

export function calculate(input: Obj, rulesDir = statutoryDirectory()): PayResult {
  const province = String(input.province);
  if (province === "QC") {
    throw new PayrollError("Quebec payroll is phase 2 (Revenu Québec TP-1015.F).");
  }
  const edition = loadRules(String(input.pay_date), rulesDir);
  const trace: Trace = [["edition", edition.id]];
  const periods = D(input.P);
  const periodic = amount(input, "I");
  const bonus = amount(input, "B");
  const bonusYtd = amount(input, "B1");
  const pensionable = "PI" in input ? D(input.PI) : periodic.plus(bonus);
  const insurable = "IE" in input ? D(input.IE) : periodic.plus(bonus);
  const f = amount(input, "F");
  const f2 = amount(input, "F2");
  const f3 = amount(input, "F3");
  const f4 = amount(input, "F4");
  const f5bYtd = amount(input, "F5BYTD");
  const unionDues = amount(input, "U1");
  const annualDeductions = amount(input, "F1");
  const northern = amount(input, "HD");
  const extraTax = amount(input, "L");
  const months = D(required(input, "PM"));
  const cppYtd = amount(input, "D_cpp_ytd");
  const cpp2Ytd = amount(input, "D2_cpp2_ytd");
  const eiYtd = amount(input, "D1_ei_ytd");
  const pensionableYtd = amount(input, "PIYTD");
  const cpp = edition.cpp;
  const rate = D(cpp.rate);

  const cppOn = (earnings: Decimal, deducted: Decimal, applyExemption: boolean): Decimal => {
    if (exempt(input, "cpp_exempt") || earnings.lte(0)) return new Decimal(0);
    const exemption = applyExemption ? truncCents(D(cpp.basic_exemption).div(periods)) : new Decimal(0);
    const room = D(cpp.max_employee_contribution).mul(months).div(12).minus(deducted);
    return Decimal.max(new Decimal(0), Decimal.min(room, money(rate.mul(earnings.minus(exemption)))));
  };

  const applyExemption = Boolean(required(input, "apply_cpp_exemption"));
  const cppThis = cppOn(pensionable, cppYtd, applyExemption);
  const cppRegular = bonus.gt(0) ? cppOn(pensionable.minus(bonus), cppYtd, applyExemption) : cppThis;
  const cppBonus = cppThis.minus(cppRegular);
  trace.push([
    "CPP.exemption_per_period",
    plain(applyExemption ? truncCents(D(cpp.basic_exemption).div(periods)) : new Decimal(0)),
  ]);

  let cpp2 = new Decimal(0);
  if (!exempt(input, "cpp_exempt")) {
    const wageBase = Decimal.max(pensionableYtd, D(cpp.ympe).mul(months).div(12));
    const room = D(edition.cpp2.max_employee_contribution).mul(months).div(12).minus(cpp2Ytd);
    cpp2 = Decimal.max(
      new Decimal(0),
      Decimal.min(room, money(Decimal.max(new Decimal(0), pensionableYtd.plus(pensionable).minus(wageBase)).mul(D(edition.cpp2.rate)))),
    );
  }

  const eiOn = (earnings: Decimal): Decimal => {
    if (exempt(input, "ei_exempt") || earnings.lte(0)) return new Decimal(0);
    const room = D(edition.ei.max_employee_premium).minus(eiYtd);
    return Decimal.max(new Decimal(0), Decimal.min(room, money(D(edition.ei.rate).mul(earnings))));
  };
  const eiThis = eiOn(insurable);
  const eiRegular = bonus.gt(0) ? eiOn(insurable.minus(bonus)) : eiThis;
  const eiBonus = eiThis.minus(eiRegular);

  const f5 = money(cppThis.mul(D(cpp.first_additional_rate).div(rate)).plus(cpp2));
  const f5a = pensionable.gt(0) ? money(f5.mul(pensionable.minus(bonus).div(pensionable))) : new Decimal(0);
  const f5b = pensionable.gt(0) ? money(f5.mul(bonus.div(pensionable))) : new Decimal(0);

  const annualRegular = Decimal.max(
    new Decimal(0),
    periods.mul(periodic.minus(f).minus(f2).minus(f5a).minus(unionDues)).minus(northern).minus(annualDeductions),
  );
  const recent = periodic.eq(0) && bonus.gt(0) ? D(required(input, "I_recent")) : new Decimal(0);
  const annualBase = periodic.gt(0)
    ? annualRegular
    : Decimal.max(new Decimal(0), periods.mul(recent.minus(f).minus(f2).minus(unionDues)).minus(northern).minus(annualDeductions));
  const annualizedPeriodic = periodic.gt(0) ? periodic : recent;
  const grossEmployment =
    "gross_employment_annual" in input ? D(input.gross_employment_annual) : periods.mul(annualizedPeriodic).plus(bonus).plus(bonusYtd);
  const grossRegular =
    "gross_employment_annual" in input ? D(input.gross_employment_annual) : periods.mul(annualizedPeriodic).plus(bonusYtd);
  const regularTax = annualTax(
    edition,
    province,
    annualRegular,
    periods,
    input,
    periods.mul(cppRegular),
    periods.mul(eiRegular),
    grossRegular,
    months,
    trace,
    "regular",
  );
  const taxRegular = periodic.gt(0) ? regularTax.federal.plus(regularTax.provincial).div(periods).plus(extraTax) : extraTax;

  let taxBonus = new Decimal(0);
  if (bonus.gt(0)) {
    const prior = Decimal.max(new Decimal(0), bonusYtd.minus(f4).minus(f5bYtd));
    const withPayment = annualBase.plus(Decimal.max(new Decimal(0), bonus.minus(f3).minus(f5b))).plus(prior);
    const withoutPayment = annualBase.plus(prior);
    const small = edition.non_periodic.small_payment_rule as Obj;
    if (withPayment.lte(D(small.threshold))) {
      taxBonus = D(small.federal_rate).mul(bonus);
      trace.push(["bonus.method", "15% small-payment rule"]);
    } else {
      const remaining = D(required(input, "PR"));
      const cppProjected = cppYtd.plus(remaining.mul(cppRegular));
      const eiProjected = eiYtd.plus(remaining.mul(eiRegular));
      const withTax = annualTax(
        edition,
        province,
        withPayment,
        periods,
        input,
        cppProjected.plus(cppBonus),
        eiProjected.plus(eiBonus),
        grossEmployment,
        months,
        trace,
        "bonus_step1",
      );
      const withoutTax = annualTax(
        edition,
        province,
        withoutPayment,
        periods,
        input,
        cppProjected,
        eiProjected,
        grossRegular,
        months,
        trace,
        "bonus_step2",
      );
      taxBonus = Decimal.max(new Decimal(0), withTax.federal.plus(withTax.provincial).minus(withoutTax.federal.plus(withoutTax.provincial)));
      trace.push(["bonus.method", "annual tax with payment minus annual tax without"]);
    }
  }

  const taxTotal = money(taxRegular.plus(taxBonus));
  return {
    edition: edition.id,
    tax_year: edition.tax_year,
    cpp_employee: moneyText(cppThis),
    cpp2_employee: moneyText(cpp2),
    ei_employee: moneyText(eiThis),
    income_tax: moneyText(taxTotal),
    income_tax_regular: moneyText(taxRegular),
    federal_tax_regular: periodic.gt(0) ? moneyText(regularTax.federal.div(periods)) : "0.00",
    provincial_tax_regular: periodic.gt(0) ? moneyText(regularTax.provincial.div(periods)) : "0.00",
    income_tax_non_periodic: moneyText(taxBonus),
    cpp_employer: moneyText(cppThis),
    cpp2_employer: moneyText(cpp2),
    ei_employer: moneyText(eiThis.mul(D(edition.ei.employer_multiplier))),
    net_pay: moneyText(
      periodic
        .plus(bonus)
        .plus(amount(input, "non_taxable_earnings"))
        .minus(f)
        .minus(f2)
        .minus(f3)
        .minus(unionDues)
        .minus(cppThis)
        .minus(cpp2)
        .minus(eiThis)
        .minus(taxTotal),
    ),
    trace,
  };
}

export function resultSha256(result: PayResult): string {
  return createHash("sha256").update(canonicalize(result)).digest("hex");
}

export function checkCase(testCase: Obj, rulesDir = statutoryDirectory()): string[] {
  const fails: string[] = [];
  if (typeof testCase.expect_error === "string") {
    try {
      calculate(testCase.input as Obj, rulesDir);
      fails.push("expected an error, got a result");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (!message.includes(testCase.expect_error)) fails.push(`wrong error: ${message}`);
    }
    return fails;
  }
  const got = calculate(testCase.input as Obj, rulesDir);
  const trace = new Map(got.trace);
  const expected = isObj(testCase.expected) ? testCase.expected : {};
  for (const [key, value] of Object.entries(expected)) {
    if (got[key as keyof PayResult] !== value) fails.push(`${key}: got ${String(got[key as keyof PayResult])} expected ${String(value)}`);
  }
  const expectedTrace = isObj(testCase.expected_trace) ? testCase.expected_trace : {};
  for (const [key, value] of Object.entries(expectedTrace)) {
    if (trace.get(key) !== value) fails.push(`trace ${key}: got ${trace.get(key)} expected ${String(value)}`);
  }
  const tolerance = D(testCase.tolerance ?? "0");
  const within = isObj(testCase.expected_within) ? testCase.expected_within : {};
  for (const [key, value] of Object.entries(within)) {
    const actual = D(got[key as keyof PayResult]);
    if (actual.minus(D(value)).abs().gt(tolerance)) {
      fails.push(`${key}: got ${String(got[key as keyof PayResult])} expected ${String(value)} +/- ${tolerance.toString()}`);
    }
  }
  return fails;
}
