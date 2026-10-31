# Values, defaults and fallbacks · Review decisions

Review of 25 Oct 2026 with Wael, after Module 01. It covers the whole developer pack, not one module.

**Status: applied (25 Oct 2026).** The decisions are in the developer pack:

- `dev-pack/docs/22-values-and-fallbacks.md` (new): the three rules, the settings 0008 adds, defaults and organization lists, languages, the fallback register (FB-001 to FB-032), legal values moved into the rules files, the reference calculators, countries, the automatic check, and the changes to other documents. It wins over every other document on these topics.
- `dev-pack/schema/0008_values_and_languages.sql` and `dev-pack/tests/schema/schema_0008_smoke.sql` (new): loaded on PostgreSQL 16 after 0001 and 0003 to 0007, on an empty database and on one holding the earlier smoke tests' data; all six smoke tests pass.
- `dev-pack/rules/register/values-and-fallbacks.json` and `dev-pack/tests/hardcoding/check_values.py` (new): every fixed list, default, API default and fallback, classified; the check fails on anything new that is not registered.
- `dev-pack/rules/employment-standards/ca-2026-separation-additions.json` (new); Ontario Health Premium numbers in both 2026 statutory editions; `benefit-practices.json` and `schemes.json` completed.
- The five reference calculators no longer carry values of their own; test inputs made explicit, no expected value changed (payroll 77/77, stacking all, similarity all, market pricing 17/17, several positions 32/32).
- `dev-pack/AGENTS.md` (reading order item 9; rules 10, 43, 44, 45; Step 1 for 0008; commands), `.cursor/rules/00-cando.mdc`, `docs/13`, `docs/16` (Q44 and items to verify), `docs/21`, `requirements/00`, the four API contracts, and the smoke tests for 0003 to 0007 (fixtures brought up to the 0008 rules).

## Decisions

| # | Decision | Where applied |
| --- | --- | --- |
| 1 | **Fix everything found, now.** Every value an organization could want different becomes a setting, an organization list or a rule value; what stays fixed is classified and registered. | docs/22 §1–3; schema 0008; register |
| 2 | **Languages, option (a):** the database is ready for any language now; screens in English and French at launch; other languages added as data. | docs/22 §4; schema 0008 §4; requirements/00 |
| 3 | **No random fallbacks.** Only registered fallbacks; everything else stops with a named error. Strict checking of every fallback; when in doubt, ask the owner how the fallback should happen. | AGENTS rule 44; docs/22 §1.2 and §5; the check |

## Decided after the first write-up (25 Oct 2026)

The first record of these answers was wrong (an "Ok" was read as agreement before the questions had been read); this is the owner's answer.

| # | Question | Decision |
| --- | --- | --- |
| Q44 | Screen language | Each user picks EN or FR at the top of the screen, at any time; it has nothing to do with the organization |
| Q44 | The organization's own words | Shown as typed, in the language the organization chose at setup (English or French), with a small EN or FR tag when it differs from the screen. Nobody types anything twice |
| Q44 | Quebec | Organizations in Quebec keep their words in French. An English version is a paid extra |
| Q44 | Translation | Only through CanDo's translation service, sold by Wael on request and charged by use. AI may translate job descriptions; it never writes them |
| — | Fallbacks marked `spec` or `proposed` in docs/22 §5 | Brought to the owner in each module's review, starting with Module 02 |

## Decided later

| # | Question | Decision (25 Oct 2026) |
| --- | --- | --- |
| Q45 | Pricing and checking of the translation service | Per word translated (AI cost plus margin), quoted and approved by the organization before each job; HR approves letters and contracts before use |
