# 14 · Testing and quality

## 1. Test layers

| Layer | Tool | What must be covered |
| --- | --- | --- |
| Unit | Vitest | Pure functions: payroll engine, cascade rules, rules resolution, time classification, accrual ledger, permission evaluation, cost distribution and rounding |
| Workers runtime | Vitest with `@cloudflare/vitest-pool-workers` | Route handlers, Queue consumers, Cron handlers and Durable Objects run in the Workers runtime, with the same limits as production |
| Payroll fixtures | Vitest runner over `tests/payroll/cases.json` | Every case passes. The TypeScript engine and `reference/payroll_reference.py` agree to the cent. |
| Pay composition fixtures | Vitest runner over `tests/agreements/stacking_cases.json` | Every case and validation case passes with the same totals, lines and problems as `reference/premium_stacking_reference.py` |
| Audit vectors | Vitest over `tests/audit/merkle_vectors.json` | Leaf hashes, roots, batch hashes and inclusion proofs byte for byte; forged leaves rejected |
| Database | `tests/schema/load_schema.sh`, `tests/schema/schema_smoke.sql` and `tests/schema/schema_0003_smoke.sql` against the local Supabase stack (`supabase start`) in CI | Migrations apply in order; exclusion constraints, immutability triggers, tenant isolation, RLS on every tenant table |
| Determinism | Vitest against the local Supabase stack | The same run with 1 and 100 buckets gives identical `result_sha256`; a redelivered Queue message or a killed consumer leaves no duplicate result; nightly replay finds a tampered line |
| Property-based | fast-check | Effective dating (no overlaps, as-of returns one row), cascades terminate, CPP/EI never exceed maximums, net = gross − deductions, distributions add up to the cent |
| Integration | Vitest against the local Supabase stack and `wrangler dev` | Change set commit with RLS through the tenant transaction wrapper, outbox relay, exclusion constraints, concurrency conflicts |
| Platform guards | CI script | No CanDo schema exposed through Supabase's Data API; `anon` and `authenticated` hold no privileges on CanDo schemas; every Hyperdrive configuration has caching disabled; the `service_role` secret is bound only to `apps/identity`; no Worker that holds it has a Hyperdrive binding; no personal-data fields in Queue message or Durable Object schemas |
| API contract | Schemathesis or Dredd against `api/openapi.yaml` | Responses match the schema; error formats |
| End to end | Playwright against preview deployments | Acceptance tests in `04`, `06`, `09`, `12`, `17` §14 and the stories in `stories/` |
| Accessibility | axe-core in Playwright plus manual screen-reader passes | WCAG 2.1 AA on every screen |
| Performance | k6 from a Canadian location against staging | Targets in `02` (50,000-employee run; org chart load; API p95) |
| Security | CodeQL, Dependabot, secret scanning with push protection, ZAP baseline, annual pen test | OWASP ASVS L2 |

## 2. Payroll verification policy

1. `official` cases (CRA worked examples) must match exactly.
2. `official-table` cases (T4032) must be within $0.05, because the tables round.
3. `reference-only` cases must be confirmed in CRA's PDOC before go-live. Whoever confirms a case sets `"verification": "pdoc"` and records the PDOC date and inputs in the case `source`.
4. Each new statutory edition adds at least one PDOC-verified case per jurisdiction for bi-weekly and monthly pay, at three income levels (below the YMPE, between the YMPE and the YAMPE, above the top federal bracket), and one bonus case.
5. Parallel runs with each customer's legacy payroll: at least two full cycles, every difference explained, before go-live.

## 3. Definition of done (every story)

- Acceptance criteria in the story pass as automated tests.
- English and French strings present; no hard-coded text.
- Permissions enforced in SQL scope, and tested for an allowed and a denied user.
- Audit entries written for every change.
- Effective dating respected: the `asOf` read is correct for past, today and future.
- No personal data in logs (log-redaction test passes).
- OpenAPI updated and the contract test passes.
- Accessibility check passes.
- The pull request passed CI and was approved by a human reviewer; changes to protected paths were approved by their code owner (`15` §Working with AI agents and GitHub).

## 4. Synthetic data

`supabase/seed.sql` (reference data) and `supabase/seeds/demo/` build three tenants for tests and demos:

- **Northern Lights Non-Profit:** 60 employees, AB and BC, grant-funded positions, light org mode
- **Example Municipality:** 2,400 employees, ON, four agreements including the example agreement, platoon schedules, OMERS-style pension, several hierarchies, people with several assignments (`17` §14)
- **Example First Nation:** 180 employees, MB on-reserve and off-reserve, s.87 cases, federal jurisdiction

All people and organizations are fictional. No real SINs: generate numbers that pass the Luhn check from a reserved test range, and label them as test data. Real customer data never enters local, preview or staging environments, and never enters an AI agent's context.
