import { D, HUNDRED, ONE, TWELVE, ZERO, dec, pyStr, q, qstr, roundToUnit, type Dec } from "./decimal.ts";

/**
 * Port of reference/market_pricing_reference.py.
 * Every case in tests/compensation/market_pricing_cases.json must match.
 * Rounding happens only where that file rounds.
 */

type Row = Record<string, unknown>;

export type Files = {
  plan: Row;
  practices: { practices: Row[]; comparison: Row };
};

function need(d: Row, k: string, what: string): unknown {
  if (!(k in d) || d[k] === null || d[k] === undefined) {
    throw new Error(`${what}_INCOMPLETE: ${k} is not set`);
  }
  return d[k];
}

function monthsBetween(fromDate: string, toDate: string): Dec {
  const a = fromDate.split("-").map((p) => Number(p));
  const b = toDate.split("-").map((p) => Number(p));
  const whole = (b[0] - a[0]) * 12 + (b[1] - a[1]);
  // rule: docs/19 §7.3 - a part month is counted in 30ths
  return q(new D(whole).plus(new D(b[2] - a[2]).div(30)), "0.01");
}

function ageingFactor(months: Dec, annualRate: Dec, method: string): Dec {
  if (method === "none" || annualRate.eq(ZERO) || months.eq(ZERO)) return ONE;
  if (method === "simple") return ONE.plus(annualRate.mul(months).div(TWELVE));
  if (method === "compound") return ONE.plus(annualRate).pow(months.div(TWELVE));
  throw new Error(`unknown ageing method ${method}`);
}

function orgCount(row: Row): Dec {
  if (!("n_orgs" in row) || row.n_orgs === null || row.n_orgs === undefined) return ZERO;
  return dec(row.n_orgs);
}

function incumbentCount(row: Row): Dec {
  const v = row.n_incumbents;
  if (v === null || v === undefined || v === 0 || v === "0") return ZERO;
  return dec(v);
}

function usable(row: Row | undefined, stat: string, minimum: Row): { ok: boolean; why: string | null } {
  if (row === undefined) return { ok: false, why: "NOT_IN_EDITION" };
  if (row[stat] === null || row[stat] === undefined) return { ok: false, why: "MASKED" };
  if (orgCount(row).lt(dec(need(minimum, "nOrgs", "DEFINITION")))) return { ok: false, why: "BELOW_MINIMUM_ORGS" };
  if ("nIncumbents" in minimum && minimum.nIncumbents !== null && minimum.nIncumbents !== undefined) {
    if (incumbentCount(row).lt(dec(minimum.nIncumbents))) return { ok: false, why: "BELOW_MINIMUM_INCUMBENTS" };
  }
  return { ok: true, why: null };
}

function surveyKey(code: unknown, cut: unknown, weighting: unknown, element: unknown): string {
  return `${String(code)}\u0000${String(cut)}\u0000${String(weighting)}\u0000${String(element)}`;
}

function surveyValue(
  source: Row,
  edition: Row,
  matches: Row[],
  stat: string,
  targetStat: string,
  minimum: Row,
): { value: Dec | null; info: Row } {
  const rows = edition.rows as Row[];
  const index = new Map<string, Row>();
  for (const r of rows) {
    index.set(surveyKey(r.job_code, r.cut, r.weighting, r.element), r);
  }
  const reasons: Row[] = [];
  const chain = source.cutChain as string[];
  for (const cut of chain) {
    const comps: { m: Row; row: Row }[] = [];
    let ok = true;
    for (const m of matches) {
      const row = index.get(surveyKey(m.code, cut, source.weighting, source.element));
      const good = usable(row, targetStat, minimum);
      if (!good.ok || row === undefined) {
        ok = false;
        reasons.push({ cut, code: m.code, reason: good.why });
        break;
      }
      comps.push({ m, row });
    }
    if (!ok) continue;
    for (const c of comps) {
      if (c.row[stat] === null || c.row[stat] === undefined) {
        return { value: null, info: { cut, reason: "STAT_NOT_PUBLISHED", tried: reasons } };
      }
    }
    let value = ZERO;
    const components: Row[] = [];
    for (const c of comps) {
      value = value.plus(dec(c.m.share).div(HUNDRED).mul(dec(c.row[stat])));
      components.push({ code: c.m.code, share: c.m.share, nOrgs: c.row.n_orgs, value: String(c.row[stat]) });
    }
    return { value, info: { cut, components, tried: reasons } };
  }
  return { value: null, info: { reason: "NO_USABLE_CUT", tried: reasons } };
}

function publicValue(source: Row, edition: Row, noc: string | null, stat: string): { value: Dec | null; info: Row } {
  if (noc === null) return { value: null, info: { reason: "NO_NOC_CODE" } };
  const columns = need(edition, "statisticColumns", "EDITION") as Row;
  const col = columns[stat];
  if (col === null || col === undefined) return { value: null, info: { reason: "STAT_NOT_PUBLISHED" } };
  const index = new Map<string, Row>();
  for (const r of edition.rows as Row[]) {
    index.set(`${String(r.noc)}\u0000${String(r.geo)}`, r);
  }
  const geos = source.geoChain as string[];
  for (const geo of geos) {
    const row = index.get(`${noc}\u0000${geo}`);
    if (row === undefined || row[String(col)] === null || row[String(col)] === undefined) continue;
    let v = dec(row[String(col)]);
    if (row.basis === "hourly") v = v.mul(dec(source.hoursBasis));
    return { value: v, info: { geo, basis: row.basis, value: String(row[String(col)]) } };
  }
  return { value: null, info: { reason: "NO_USABLE_GEOGRAPHY" } };
}

function geoFactor(source: Row): Dec {
  // structural: no geographic differential unless the source states one (reference price_job)
  if (!("geoDifferentialPct" in source) || source.geoDifferentialPct === null || source.geoDifferentialPct === undefined) {
    return ONE;
  }
  return ONE.plus(dec(source.geoDifferentialPct).div(HUNDRED));
}

export function priceJob(job: Row, definition: Row, editions: Record<string, Row>, asOf: string): Row {
  const targetStat = String(definition.statistic);
  const named = need(definition, "statistics", "DEFINITION") as string[];
  const stats: string[] = [];
  for (const s of named) {
    if (!stats.includes(s)) stats.push(s);
  }
  if (!stats.includes(targetStat)) stats.push(targetStat);
  const minimum = need(definition, "minimum", "DEFINITION") as Row;
  const ageing = need(definition, "ageing", "DEFINITION") as Row;
  const method = String(need(ageing, "method", "DEFINITION"));
  const rate = method === "none" ? ZERO : dec(need(ageing, "annualRate", "DEFINITION"));
  const lineage: Row[] = [];
  const perStat = new Map<string, { w: Dec; v: Dec }[]>();
  for (const s of stats) perStat.set(s, []);
  const sources = definition.sources as Row[];
  for (const src of sources) {
    const ed = editions[String(src.code)];
    const entry: Row = { source: src.code, weight: src.weight, used: false };
    let base: Dec | null;
    let info: Row;
    if (src.kind === "survey") {
      const matches = (job.matches as Row | undefined)?.[String(src.code)] as Row[] | undefined;
      if (matches === undefined || matches.length === 0) {
        entry.reason = "NOT_MATCHED";
        lineage.push(entry);
        continue;
      }
      let totalShare = ZERO;
      for (const m of matches) totalShare = totalShare.plus(dec(m.share));
      if (!totalShare.eq(HUNDRED)) {
        throw new Error(`match shares for ${String(job.jobId)} in ${String(src.code)} total ${pyStr(totalShare)}, not 100`);
      }
      const got = surveyValue(src, ed, matches, targetStat, targetStat, minimum);
      base = got.value;
      info = got.info;
    } else {
      const noc = job.noc === undefined || job.noc === null ? null : String(job.noc);
      const got = publicValue(src, ed, noc, targetStat);
      base = got.value;
      info = got.info;
    }
    Object.assign(entry, info);
    if (base === null) {
      lineage.push(entry);
      continue;
    }
    const months = monthsBetween(String(ed.effectiveDate), asOf);
    const factor = ageingFactor(months, rate, method);
    const geo = geoFactor(src);
    entry.used = true;
    entry.months = qstr(months, "0.01");
    entry.ageingFactor = qstr(factor, "0.000001");
    entry.geoFactor = pyStr(geo);
    for (const s of stats) {
      let v: Dec | null;
      if (s === targetStat) {
        v = base;
      } else if (src.kind === "survey") {
        const matches = (job.matches as Row)[String(src.code)] as Row[];
        v = surveyValue(src, ed, matches, s, targetStat, minimum).value;
      } else {
        const noc = job.noc === undefined || job.noc === null ? null : String(job.noc);
        v = publicValue(src, ed, noc, s).value;
      }
      if (v !== null) perStat.get(s)!.push({ w: dec(src.weight), v: v.mul(factor).mul(geo) });
    }
    entry.agedTarget = qstr(base.mul(factor).mul(geo), "0.01");
    lineage.push(entry);
  }
  const used = lineage.filter((e) => e.used === true);
  const result: Row = { jobId: job.jobId, lineage };
  if (used.length < Number(need(definition, "minSources", "DEFINITION"))) {
    result.status = "insufficient_data";
    return result;
  }
  const market: Row = {};
  for (const s of stats) {
    const vals = perStat.get(s)!;
    if (vals.length === 0) {
      market[s] = null;
      continue;
    }
    let wsum = ZERO;
    let acc = ZERO;
    for (const item of vals) {
      wsum = wsum.plus(item.w);
      acc = acc.plus(item.w.mul(item.v));
    }
    market[s] = qstr(acc.div(wsum), "0.01");
  }
  const adj = ONE.plus(dec(need(definition, "adjustPct", "DEFINITION")).div(HUNDRED));
  result.status = "priced";
  result.market = market;
  result.target = qstr(dec(market[targetStat]).mul(adj), "0.01");
  let wsumUsed = ZERO;
  for (const e of used) wsumUsed = wsumUsed.plus(dec(e.weight));
  for (const e of used) {
    e.effectiveWeightPct = qstr(dec(e.weight).mul(HUNDRED).div(wsumUsed), "0.01");
  }
  return result;
}

export function fitMarketLine(points: unknown[], values: unknown[], outlierPct: Dec): Row {
  // rule: docs/19 §7.6 - a least-squares line needs at least three jobs
  if (points.length < 3) throw new Error("a market line needs at least 3 benchmark jobs");
  const xs = points.map((p) => dec(p));
  const ys = values.map((v) => dec(v).ln());
  const n = new D(xs.length);
  let sx = ZERO;
  let sy = ZERO;
  for (const x of xs) sx = sx.plus(x);
  for (const y of ys) sy = sy.plus(y);
  const mx = sx.div(n);
  const my = sy.div(n);
  let sxx = ZERO;
  let sxy = ZERO;
  let i = 0;
  while (i < xs.length) {
    const dx = xs[i].minus(mx);
    sxx = sxx.plus(dx.pow(2));
    sxy = sxy.plus(dx.mul(ys[i].minus(my)));
    i += 1;
  }
  let b = sxy.div(sxx);
  let a = my.minus(b.mul(mx));
  a = q(a, "0.0000000001");
  b = q(b, "0.0000000001");
  let ssRes = ZERO;
  let ssTot = ZERO;
  i = 0;
  while (i < xs.length) {
    const yHat = a.plus(b.mul(xs[i]));
    ssRes = ssRes.plus(ys[i].minus(yHat).pow(2));
    ssTot = ssTot.plus(ys[i].minus(my).pow(2));
    i += 1;
  }
  const r2 = ONE.minus(ssRes.div(ssTot));
  const residuals: Row[] = [];
  i = 0;
  while (i < xs.length) {
    const pred = a.plus(b.mul(xs[i])).exp();
    const pct = dec(values[i]).div(pred).minus(ONE);
    residuals.push({
      points: Number(xs[i].toFixed(0)),
      value: String(values[i]),
      predicted: qstr(pred, "0.01"),
      residualPct: qstr(pct.mul(HUNDRED), "0.1"),
      outlier: pct.abs().gt(outlierPct),
    });
    i += 1;
  }
  return {
    a: qstr(a, "0.0000000001"),
    b: qstr(b, "0.0000000001"),
    r2: qstr(r2, "0.0001"),
    progressionPer100Points: qstr(b.mul(100).exp().minus(ONE).mul(HUNDRED), "0.01"),
    residuals,
  };
}

function predict(line: Row, points: unknown): Dec {
  return dec(line.a).plus(dec(line.b).mul(dec(points))).exp();
}

export function buildGrades(line: Row, bands: Row[], spreads: Row, rounding: Dec): Row[] {
  const out: Row[] = [];
  let prevMid: Dec | null = null;
  for (const band of bands) {
    const midPoints = dec(band.min).plus(dec(band.max)).div(2);
    const mid = roundToUnit(predict(line, midPoints), rounding);
    const spread = dec(spreads[String(band.grade)]).div(HUNDRED);
    const minRaw = mid.div(ONE.plus(spread.div(2)));
    const maxRaw = minRaw.mul(ONE.plus(spread));
    const g: Row = {
      grade: band.grade,
      pointsMid: pyStr(midPoints),
      minimum: pyStr(roundToUnit(minRaw, rounding)),
      midpoint: pyStr(mid),
      maximum: pyStr(roundToUnit(maxRaw, rounding)),
      spreadPct: String(spreads[String(band.grade)]),
      progressionPct: prevMid === null ? null : qstr(mid.div(prevMid).minus(ONE).mul(HUNDRED), "0.1"),
    };
    out.push(g);
    prevMid = mid;
  }
  let n = 0;
  while (n < out.length - 1) {
    const lower = out[n];
    const upper = out[n + 1];
    const loMax = dec(lower.maximum);
    const upMin = dec(upper.minimum);
    const gap = loMax.minus(upMin);
    const span = dec(upper.maximum).minus(upMin);
    const overlap = gap.gt(ZERO) ? gap : ZERO;
    upper.overlapWithLowerPct = qstr(overlap.div(span).mul(HUNDRED), "0.1");
    n += 1;
  }
  return out;
}

export function payMetrics(rateIn: unknown, rng: Row, marketRate?: unknown): Row {
  const rate = dec(rateIn);
  const mn = dec(rng.minimum);
  const mid = dec(rng.midpoint);
  const mx = dec(rng.maximum);
  const pen = rate.minus(mn).div(mx.minus(mn));
  let quart: string;
  if (rate.lt(mn)) quart = "below_minimum";
  else if (rate.gt(mx)) quart = "above_maximum";
  else if (pen.lt(new D("0.25"))) quart = "Q1";
  else if (pen.lt(new D("0.5"))) quart = "Q2";
  else if (pen.lt(new D("0.75"))) quart = "Q3";
  else quart = "Q4";
  const out: Row = {
    compaRatio: qstr(rate.div(mid), "0.001"),
    penetration: qstr(pen, "0.001"),
    quartile: quart,
  };
  if (marketRate !== undefined && marketRate !== null) {
    out.marketRatio = qstr(rate.div(dec(marketRate)), "0.001");
  }
  return out;
}

export function costToMinimum(people: Row[], rng: Row): string {
  const mn = dec(rng.minimum);
  let total = ZERO;
  for (const p of people) {
    const gap = mn.minus(dec(p.rate));
    const short = gap.gt(ZERO) ? gap : ZERO;
    total = total.plus(short.mul(dec(p.fte)));
  }
  return qstr(total, "0.01");
}

export function annualize(hourly: unknown, hours: unknown): string {
  return qstr(dec(hourly).mul(dec(hours)), "0.01");
}

export function evaluate(plan: Row, ratings: Row): Row {
  const factors = plan.factors as Row[];
  const byCode = new Map<string, Row>();
  for (const f of factors) byCode.set(String(f.code), f);
  const missing: string[] = [];
  for (const f of factors) {
    if (!(String(f.code) in ratings)) missing.push(String(f.code));
  }
  missing.sort();
  if (missing.length > 0) throw new Error(`EVALUATION_INCOMPLETE: ${missing.join(",")}`);
  let total = 0;
  const detail: Row = {};
  for (const code of Object.keys(ratings)) {
    const factor = byCode.get(code);
    if (factor === undefined) throw new Error(`EVALUATION_INCOMPLETE: ${code}`);
    const degrees = factor.degrees as Row[];
    let pts: number | undefined;
    for (const degree of degrees) {
      if (degree.degree === ratings[code]) pts = Number(degree.points);
    }
    if (pts === undefined) throw new Error(`EVALUATION_INCOMPLETE: ${code}`);
    detail[code] = pts;
    total += pts;
  }
  let grade: string | null = null;
  for (const b of plan.grade_bands as Row[]) {
    if (Number(b.min) <= total && total <= Number(b.max)) {
      grade = String(b.grade);
      break;
    }
  }
  return { points: total, grade, byFactor: detail };
}

export function suggestDegrees(plan: Row, evidence: Row): Row {
  const out: Row = {};
  for (const f of plan.factors as Row[]) {
    const ev = f.evidence as Row | undefined;
    if (ev === undefined) continue;
    const sug = ev.suggest as Row | undefined;
    if (sug === undefined || sug === null) continue;
    const src = ev.source;
    let key: string | null = null;
    if (src === "competency_targets") {
      const levels: number[] = [];
      const comps = (ev.competencies as string[]) ?? [];
      const targets = (evidence.competencyTargets as Row | undefined) ?? {};
      for (const c of comps) {
        if (targets[c] !== undefined && targets[c] !== null) levels.push(Number(targets[c]));
      }
      if (levels.length > 0) {
        let max = levels[0];
        for (const level of levels) if (level > max) max = level;
        key = String(max);
      } else if ("none" in sug) key = "none";
    } else if (src === "noc_teer") {
      if (evidence.teer !== undefined && evidence.teer !== null) key = String(evidence.teer);
    } else if (src === "career_level") {
      if (typeof evidence.careerLevel === "string") key = evidence.careerLevel;
    }
    if (key !== null && key in sug) out[String(f.code)] = sug[key];
  }
  return out;
}

export function comparePractice(practice: Row, own: unknown, market: Row, comparison: Row): string {
  const rw = practice.richer_when;
  const vt = practice.value_type;
  if (rw === "none" || vt === "text" || own === null || own === undefined) return "not_compared";
  if (vt === "boolean") {
    const common = dec(market.prevalence_pct).gte(dec(need(comparison, "boolean_common_at_pct", "COMPARISON")));
    if (Boolean(own) === common) return "at_market";
    return own ? "richer" : "leaner";
  }
  if (vt === "enum") {
    const order = practice.enum_values as unknown[];
    const o = order.indexOf(own);
    const m = order.indexOf(market.mode);
    if (o === m) return "at_market";
    return o > m ? "richer" : "leaner";
  }
  const ownD = dec(own);
  const med = dec(market.p50);
  const tolerance = need(comparison, "tolerance", "COMPARISON") as Row;
  const tol = dec(need(tolerance, String(vt), "TOLERANCE"));
  if (ownD.minus(med).abs().lte(tol.mul(med.abs()))) return "at_market";
  const higher = ownD.gt(med);
  return higher === (rw === "higher") ? "richer" : "leaner";
}

export function runCase(caseObj: Row, files: Files): Row {
  const k = String(caseObj.kind);
  const i = caseObj.input as Row;
  if (k === "ageing") {
    const m = monthsBetween(String(i.from), String(i.to));
    const f = ageingFactor(m, dec(i.annualRate), String(i.method));
    return { months: qstr(m, "0.01"), factor: qstr(f, "0.000001"), aged: qstr(dec(i.amount).mul(f), "0.01") };
  }
  if (k === "price") {
    return priceJob(i.job as Row, i.definition as Row, i.editions as Record<string, Row>, String(i.asOf));
  }
  if (k === "market_line") return fitMarketLine(i.points as unknown[], i.values as unknown[], dec(i.outlierPct));
  if (k === "structure") {
    return { grades: buildGrades(i.line as Row, i.bands as Row[], i.spreads as Row, dec(i.rounding)) };
  }
  if (k === "pay_metrics") {
    const people = (i.people as Row[]).map((p) => ({ id: p.id, ...payMetrics(p.rate, i.range as Row, i.marketRate) }));
    return { people, costToMinimum: costToMinimum(i.people as Row[], i.range as Row) };
  }
  if (k === "annualize") return { annual: annualize(i.hourly, i.hours) };
  if (k === "job_evaluation") {
    const out = evaluate(files.plan, i.ratings as Row);
    if ("evidence" in i) out.suggestions = suggestDegrees(files.plan, i.evidence as Row);
    return out;
  }
  if (k === "practice") {
    const cat = new Map<string, Row>();
    for (const p of files.practices.practices) cat.set(String(p.code), p);
    const results: Row = {};
    for (const c of i.comparisons as Row[]) {
      results[String(c.practice)] = comparePractice(cat.get(String(c.practice))!, c.own, c.market as Row, files.practices.comparison);
    }
    return { results };
  }
  throw new Error(`unknown case kind ${k}`);
}

export function runCaseSafe(caseObj: Row, files: Files): Row {
  try {
    return JSON.parse(JSON.stringify(runCase(caseObj, files))) as Row;
  } catch (e) {
    const message = e instanceof Error ? e.message : String(e);
    return { error: message.split(":")[0] };
  }
}
