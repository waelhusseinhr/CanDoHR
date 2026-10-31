# 08 · Rules engine and collective agreement library

Legislation, collective agreements and employer policies are all data, versioned and effective-dated. Every module asks the rules engine one question, "what applies to this person on this date?", and gets one answer with its source.

## 1. Rule families

| Family | Files or tables | Owner | Versioning |
| --- | --- | --- | --- |
| Statutory payroll | `rules/statutory/ca-YYYY-MM-DD.json` → `ref.rule_edition` | CanDo (global) | Edition per CRA publication |
| Employer payroll taxes | `rules/employer-taxes/ca-YYYY.json` | CanDo (global) | Per year, amended when provinces change |
| Employment standards | `rules/employment-standards/ca-YYYY.json` → `ref.es_rule` | CanDo (global) | Per jurisdiction and effective date |
| Holiday calendars | Generated into `ref.holiday` from rules | CanDo (global) | Per jurisdiction and year |
| Collective agreements | `agreement` + `agreement_version` (JSON per `rules/agreements/agreement.schema.json`) | Tenant | Version per ratification or award |
| Employer policies | `policy_rule_set` (same shapes as agreements: leave plans, overtime, premiums, probation) | Tenant | Version per approval |

## 2. Resolution: the greater right

For an assignment on a date, the engine builds the effective rule set in layers:

1. Employment standards for the jurisdiction (federal or provincial, from legal entity and location)
2. Collective agreement version in force for the assignment's bargaining unit, or employer policy for non-union staff
3. Individual terms (for example a contract with more vacation)

For each entitlement, the engine computes the result under each layer and applies the most favourable to the employee where the law requires it (vacation weeks, overtime pay, notice). It records which layer won. Example: an agreement with overtime after 7 hours a day beats Ontario's 44 hours a week, and the time engine applies both thresholds and pays the greater.

Some agreement terms replace rather than compare (premiums, grids, seniority); the schema marks which.

## 3. Evaluation API (internal)

```ts
rules.resolve({ assignmentId, date }) → {
  jurisdiction: 'ON',
  esVersion: 'CA-ES-2026@ON#3',
  agreement: { id: 'EXAMPLE-MUNI-0001', version: 2 } | null,
  overtime: [{ basis: 'daily', afterHours: 7, multiplier: 1.5, source: 'agreement:15' }, …],
  minimumWage: { amount: 17.95, source: 'es:ON' },
  vacation: { days: 20, payPercent: 8, source: 'agreement:21' },
  …
}
```

Results are cached per (assignment, date, versions) and invalidated by `agreement.version_activated` and rule edition loads.

## 4. The agreement library (Module 13)

**Import:** upload a signed agreement or fetch it from Negotech or a provincial registry. CanDo stores the original PDF, its SHA-256 hash and the registry reference.

**Extract:** the assistant proposes rules in the `agreement.schema.json` shape, one rule at a time, each with the article citation and a short quote. Every proposed rule starts with `provenance.extracted_by = "ai"` and `verified = false`.

**Verify:** a labour relations specialist reviews each rule side by side with the clause, then edits and accepts it. A version cannot be activated while any rule is unverified. Two-person approval is required for activation.

**Activate:** activation commits an `agreement.activate_version` change set. If `retro_from` is set, the retro engine creates requests (`06` §6). Grid changes produce rate changes for every covered assignment, previewed before approval. Once a version is `verified`, its rules and `content_sha256` can no longer change (database trigger); a fix is a new version. Pay runs pin versions by that hash (`06` §8), and a version activated while runs are locked reaches them through retro after they finalize.

**Renewals and awards:** a new version copies the previous one, so only changed clauses need re-verification. A side-by-side diff shows what changed.

**Bridging:** when an agreement expires and bargaining continues, the old version stays in force (status `expired_bridging`) until a new version is activated.

## 5. Pay composition: stacking and precedence

Agreements rarely say only "time and a half after 7 hours". They also say what happens when a night shift runs into overtime, when overtime falls on a holiday, and whether premiums count in the rate overtime is paid on. Arbitrators decide grievances on exactly these points, so the answer must be explicit, cited and identical every time. It lives in `pay_composition` (required whenever a version defines overtime, premiums or holidays) and in three fields on every hourly premium. `reference/premium_stacking_reference.py` defines the evaluation exactly, and `tests/agreements/stacking_cases.json` holds the cases the TypeScript engine must reproduce.

**Input.** The time engine (`09` §1) hands over blocks of hours. Each block lists the multiplier sources that apply (`daily` or `weekly` overtime with its tier, `consecutive_days`, `rest_day`, `second_rest_day`, `holiday`), the premiums whose conditions are met, and the employment standards minimum multiplier for those hours.

**Evaluation, in this order:**

| Step | Rule | Field |
| --- | --- | --- |
| 1. Multiplier per source | From the threshold tier, or the holiday multiplier (a version may not define two different holiday multipliers) | `overtime.thresholds`, `holidays.worked_multiplier` |
| 2. Combine sources | If two or more sources apply, use the rule whose `when` set equals them exactly, otherwise `default_resolution`. `greater_of` takes the highest, `sum_premiums` adds the parts above 1 (1.5 and 1.5 give 2.0), `multiply` multiplies (2.25), `first_in_order` takes the first source in `evaluation_order`. Then apply `multiplier_cap`. | `pay_composition.multiplier_conflicts` |
| 3. Statute floor | The multiplier is never below the employment standards minimum for those hours, even after a cap | ES rule set (`§2`) |
| 4. Which premiums | Within an `exclusive_groups` entry only the highest is paid. Then `premium_stacking`: `all`, or `highest_only` | `pay_composition` |
| 5. Regular rate | Base rate plus every paid premium marked `in_regular_rate` | premium `in_regular_rate` |
| 6. Premiums against the multiplier | `multiplied`, `flat` or `excluded`. `holiday_interaction` governs any block that includes `holiday`; `overtime_interaction` governs the other multiplied blocks. A premium in the regular rate is always multiplied and has no separate line. | premium `overtime_interaction`, `holiday_interaction` |

Each line is rounded half up to the cent once, with no rounding of intermediate rates.

**Worked example** (Clerk 2 step 3, $30.85 an hour; night premium $1.75; 2 hours of daily overtime at 1.5):

| Premium setting | Pay | Total |
| --- | --- | --- |
| `flat` | 2 × 30.85 × 1.5 = 92.55, plus 2 × 1.75 = 3.50 | $96.05 |
| `multiplied` | 92.55, plus 2 × 1.75 × 1.5 = 5.25 | $97.80 |
| `in_regular_rate` | 2 × (30.85 + 1.75) × 1.5, one line | $97.80 |
| `excluded` | 92.55 | $92.55 |

The same hours on a holiday at 1.5 under `sum_premiums` pay 2 × 30.85 × 2.0 = $123.40; under `greater_of`, $92.55; under `multiply`, 2 × 30.85 × 2.25 = 138.825, rounded to $138.83.

**Completeness guard.** Verification (`§4`) runs the validator over the version. It lists every combination of two or more sources the version defines that can apply to the same hours. `rest_day` and `second_rest_day` never meet, and `daily` and `weekly` never meet when `hours_counting.daily_overtime_counts_toward_weekly` is false. Each combination needs an exact rule or the default. Every hourly premium must state all three interaction fields. A version with any `UNRESOLVED_INTERACTION`, `MISSING_INTERACTION`, `INCONSISTENT_INTERACTION`, `AMBIGUOUS_HOLIDAY_MULTIPLIER` or `UNKNOWN_SOURCE` cannot be verified or activated. The engine checks again at run time: a block that still meets an open combination stops the timesheet approval (and the pay run lock) with `UNRESOLVED_INTERACTION`, rather than guessing.

**Traceability.** Every line carries its `rule_path`: the threshold, the conflict rule or default, the cap, the floor, the stacking decision and the interaction, each with its article. The pay statement explanation (PAY-003) and the grievance view show it, so a steward can see which clause produced each cent.

**Hours counting.** `hours_counting` tells the time engine whether daily overtime hours also count toward the weekly threshold (pyramiding), and whether paid holidays, paid leave and call-backs count as hours worked for overtime.

## 6. Testing a rule change before activation

Every rule set (agreement version, policy version, ES update) has a **sandbox test**: choose a sample of employees and pay periods, run time evaluation and payroll simulation with the old and new versions, and compare. The activation screen shows the differences: who is affected, by how much, and the total cost. The sandbox uses simulation runs (`06` §2), so nothing is posted.

## 7. Authoring rules for policies

HR administrators edit policies in forms generated from the same JSON schema, never in raw JSON. Validation errors are shown in plain language. Each saved version records author, approver and reason.

## 8. What the AI agent must not do

- Invent rule values. If a value is unknown, leave it out and mark the rule `verify_at_load`.
- Compute statutory results from memory. Load the edition file.
- Put agreement terms in code branches such as `if (union === 'CUPE')`. Every difference between agreements is data.
- Fill in a missing interaction or conflict rule with a guess. Leave it out so the validator reports it, and let a labour relations specialist decide from the agreement text.
