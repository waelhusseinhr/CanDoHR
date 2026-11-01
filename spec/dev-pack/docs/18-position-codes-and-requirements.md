# 18 · Position codes, occupational classification and requirements

Oct 24, 2026 · @Wael

This document defines how CanDo classifies jobs, positions and the people in them. It covers four things:

- The National Occupational Classification (NOC 2021 Version 1.0), loaded as reference data with every occupation's requirements.
- Any number of other classification and coding schemes, external or internal, in any order and format.
- Several codes per position or per incumbent, connected to each other.
- A search that finds the most similar position in the HRIS.

It also prepares for NOC 2026, which Statistics Canada has announced but not yet released.

**Precedence.** Where `requirements/01`, `02`, `04`, `09`, `12` or `13`, or `docs/03`, says something different on these topics, this document wins. §14 lists every place that changes. The schema is `schema/0004_position_codes.sql`, applied as migration 0004 in Step 1 and checked by `tests/schema/schema_0004_smoke.sql`. The data is in `rules/classifications/`. The similarity scorer is specified by `reference/position_similarity_reference.py` and `tests/classifications/similarity_cases.json`.

**The rule behind everything here: a code is data, attached through one table, with its scheme and its version.** A NOC code, a salary survey match, a department code, a position control number and a legacy ID are all the same kind of thing: a value from a scheme, attached to a job, a position, an incumbent or another target for a period. CanDo never adds a column for a new kind of code, and never compares codes from different versions without the official correspondence.

---

## 1. What this has to do

| Need | How CanDo meets it | Section |
| --- | --- | --- |
| Classify positions with NOC 2021 | NOC 2021 V1.0 loaded from Statistics Canada's publication: 822 groups at five levels, TEER, definitions, duties, 2,063 requirement statements and 28,012 job titles | §2 |
| Use other classifications freely: internal, alphabetical, other countries | Tenant-defined schemes with their own values, order (natural, alphabetical by code or title, custom rank, hierarchy), format and hierarchy; other countries' published schemes load the same way as NOC | §3 |
| Several codes per position, for example salary survey, department, unique IDs | Any number of schemes per target; one or several codes per scheme; optional uniqueness so a code belongs to one position at a time | §4 |
| Codes on the position or on its incumbent | Targets are job, position, assignment (the incumbent in that position), person, org unit, location and requisition; codes inherit down from job to position to incumbent unless overridden | §4 |
| Codes connected and related | Mappings between schemes and versions, derived schemes, consistency rules | §5 |
| Requirements of each position | Requirements on the job and the position, proposed from the NOC unit group and decided by HR, in a structured form that recruiting, onboarding, learning and matching can use | §6 |
| Find the most similar position | A scorer that uses the NOC hierarchy, NOC's own cross-references, TEER, requirements and internal codes, and explains every result | §7 |
| NOC 2026, other versions and other countries | Versioned schemes, correspondence tables and a recoding campaign | §8 |

---

## 2. NOC 2021 Version 1.0 in CanDo

### 2.1 The structure

The NOC classifies jobs, not people, by the kind of work performed. It has two classification criteria: ten broad occupational categories (BOC), defined by the type of work, field of study and industry, and six TEER categories (Training, Education, Experience and Responsibilities). Both are in the code itself:

| Level | Code | Count in NOC 2021 V1.0 | Meaning of the new digit |
| --- | --- | --- | --- |
| Broad occupational category | `4` | 10 | Type of work (first digit) |
| Major group | `42` | 45 | TEER category (second digit) |
| Sub-major group | `422` | 89 | Group within the major group |
| Minor group | `4220` | 162 | Occupational domain |
| Unit group | `42201` | 516 | One or more occupations |

| TEER | Typical path into the occupation |
| --- | --- |
| 0 | Management responsibilities |
| 1 | University degree, or experience from a related TEER 2 occupation |
| 2 | College program of two to three years or apprenticeship of two to five years; supervisory or significant safety responsibilities; or several years in a related TEER 3 occupation |
| 3 | College program under two years, apprenticeship under two years, more than six months of job-specific training, or several years in a related TEER 4 occupation |
| 4 | Secondary school, several weeks of on-the-job training, or experience in a related TEER 5 occupation |
| 5 | Short work demonstration; no formal education requirement |

Example: `4` Occupations in education, law and social, community and government services › `42` Front-line public protection services and paraprofessional occupations in legal, social, community, education services › `422` › `4220` Paraprofessional occupations in legal, social, community and education services › `42201` Social and community service workers (TEER 2).

### 2.2 What each unit group holds

Each of the 516 unit groups has the standard sections of the publication, and CanDo stores all of them:

| Section | Stored in | Used for |
| --- | --- | --- |
| Lead statement (definition) | `ref.code_item.definition_en` | Coding assistant, job descriptions |
| Illustrative example titles | `ref.code_item.content`, `ref.code_item_title` (kind `example`) | Title search |
| Inclusions | `content`, `ref.code_item_title` (kind `inclusion`) | Title search for borderline titles |
| Exclusions | `content`; the unit groups they name go to `ref.code_item.related_codes` | Coding guidance; similarity (§7.3) |
| Main duties, with sub-groups (for example Lawyers / Quebec notaries) and specialization notes | `content` | Job description drafts; duties comparison |
| Employment requirements, each with its strength (*is required*, *is usually required*, *may be required*) and sub-group | `ref.code_item_requirement` | Requirement proposals (§6.3) |
| Additional information (progression, mobility) | `content` | Career paths, succession |
| Alphabetical index titles (28,012) | `ref.code_item_title` (kind `index`) | Title search |

The parent groups (broad to minor) have their definitions too.

### 2.3 The data files

`rules/classifications/` holds NOC 2021 V1.0 extracted from Statistics Canada's PDF (catalogue 12-583-X, 1,110 pages). Their SHA-256 values are listed in `schemes.json`:

| File | Contents | Where |
| --- | --- | --- |
| `noc-2021-v1.0-structure.json` | All 822 groups: code, level, depth, parent, English title, TEER, cross-references | In the pack |
| `noc-2021-v1.0.json` | All 822 groups with definitions; for unit groups also example titles, inclusions, exclusions, main duties, specializations, requirement statements with sub-group, kind and strength, and additional information | Separate download (2 MB): `CanDo-NOC-2021-data.zip` |
| `noc-2021-v1.0-index-titles.json` | The 28,012 titles of the alphabetical index with their unit groups | Separate download (1.3 MB), same zip |
| `schemes.json` | The scheme catalogue: published schemes and versions (NOC 2021 published, NOC 2026 announced), tenant scheme templates, default similarity profiles, the requirement key vocabulary | In the pack |

The extraction was checked against the publication. The level counts are 10, 45, 89, 162 and 516, matching the publication's own table. Every unit group has a definition, example titles, main duties and employment requirements, and 515 of 516 have exclusions (12201 Insurance adjusters and claims examiners has none in the publication). Entries 13102 Payroll administrators and 42201 Social and community service workers were compared line by line with the PDF pages. Requirement *kinds* (education, training, experience, licence or certification) and *strengths* are tags derived from the wording. The statement text is authoritative and the tags are a starting point for HR.

The files are adapted from Statistics Canada material under the Statistics Canada Open Licence, and the attribution in each file's `licence` field travels with the data. Two things must be loaded before French-speaking tenants go live. First, the French titles and descriptions come from the separate French publication (CNP 2021 V1.0), whose titles are proper to French usage rather than translations. Second, until then the French interface shows the code with the English title marked *EN* (`docs/16` Q22).

### 2.4 Loading

The loader (Step 5) does four things, as the owner role and never as `cando_app`:

1. It checks the file's SHA-256 against `schemes.json`.
2. It inserts the version as `loading`, then its items, titles and requirement rows.
3. It checks the level counts and that every parent exists.
4. It sets the version to `published` with `content_sha256` and `item_count`.

Once published, a trigger refuses any change to that version's rows (`CODE_VERSION_IMMUTABLE`). A correction is a new version, like rule editions (`docs/08`).

### 2.5 Conventions CanDo respects

- **One code per job.** A job is classified in exactly one unit group. CanDo assigns NOC only at unit group level (`assignable_levels`), and only one code per version per target per day.
- **"Other" groups end in 9**, for example 10019 Other administrative services managers. The coding assistant offers them last.
- **Supervisors** are usually classified with the workers they supervise. The exceptions are the separate supervisor unit groups in administrative services, nursing, sales and service, trades, natural resources and manufacturing. Lead hands are not supervisors.
- **Apprentices, trainees, interns, residents and articling students** are classified with their occupation.
- **TEER describes the occupation, not the person.** A person's own education may differ from the TEER of their job. CanDo never infers a person's education from their NOC code.

### 2.6 Coding a job: the assistant

The assistant follows Statistics Canada's own method for selecting a NOC code. It offers one screen with three ways in.

1. **Search by title.** Type a title; CanDo searches the 28,012 index titles and the example and inclusion titles with trigram matching (`ref.search_code_titles`, pg_trgm). It shows the matching unit groups with the title that matched. For example, *youth worker* finds 42201.
2. **Read the profile.** For each candidate, show the definition, main duties, employment requirements, example titles and exclusions side by side with the job's own description. Exclusions link to the unit group they name, so a coder can jump to *Social workers (41300)* from 42201.
3. **Walk the structure.** Pick the broad category, then the TEER, then the sub-major and minor groups. This narrows the list to the unit groups of one minor group.

The coder picks a unit group and CanDo stores the evidence with the code: the method, the query, the matched title and the score. When the assistant is switched on (`docs/12`), it can also rank candidates from the job's duties text. Its suggestion is stored in `core.code_suggestion` with the reasons, and a person accepts or rejects it (AGENTS rule 14).

---

## 3. Code schemes

### 3.1 Two kinds, one model

| Kind | Where its values come from | Examples |
| --- | --- | --- |
| Published | A publisher's classification, loaded into `ref.code_item` by version | NOC 2021 V1.0; later NOC 2026 V1.0; ISCO-08; U.S. SOC; U.K. SOC |
| Tenant | The tenant's own values in `core.code_value`, effective-dated, or free codes typed in | Job family, career level, pay grade, salary survey matches, department code, position control number, budget line, legacy system ID, any internal scheme |
| Derived | Computed from another scheme through a mapping | Employment equity occupational group from NOC |

Every scheme a tenant uses, published or not, has one row in `core.code_scheme` with these settings:

| Setting | Values | Example |
| --- | --- | --- |
| `code`, names (EN/FR), description | | `SURVEY_A` "Salary survey A" |
| `source` | `published`, `tenant`, `derived` | |
| `ref_scheme_code`, `current_version_id`, `accepted_version_ids` | The published scheme, the version for new codes, and other versions allowed at the same time | NOC, `NOC-2021-1.0`; during transition also `NOC-2026-1.0` |
| `purpose` | occupation, job family, job level, pay grade, salary survey, department, cost, pay equity, employment equity, identifier, external system, other | |
| `country` | ISO 3166-1 code when the scheme is national | `CA`, `US`, `GB` |
| `structure` | `flat` or `hierarchical` (values have parents) | Job family → sub-family |
| `ordering` | `natural_code` (A2 before A10), `alpha_code`, `alpha_title` (by the user's language, en-CA or fr-CA collation), `custom_rank`, `hierarchy` | Career levels by rank; job families by title |
| `values_mode` | `list` (only listed values), `free` (any code that matches the pattern), `list_or_free` | Position control numbers are free |
| `code_pattern`, `code_case` | A regular expression every code must match; upper-case or as entered | `^POS-[0-9]{5}$` |
| `applies_to`, `required_on` | Which targets can carry the scheme, and where it is mandatory | NOC on job, position, assignment, requisition; required on job |
| `values_per_target` | `one`, or `many` (with optional shares that total 100) | A blended survey match: 60% one benchmark, 40% another |
| `uniqueness` | `none` or `unique` (a code belongs to one target at a time) | Position control numbers, budget lines, legacy IDs |
| `inherit` | `down` (job → position → incumbent) or `none` | NOC inherits; position control numbers do not |
| `override_needs_reason` | Whether overriding an inherited code needs a reason | |
| `maintainer_role`, `status`, `display_order` | Who maintains the values; active or retired; order on screens | |

### 3.2 Order: alphabetical or any other way

Each scheme sorts its values the way its users think about them:

- `natural_code` uses an ICU collation with numeric ordering (`core.natural_sort`), so `G2` comes before `G10`.
- `alpha_code` and `alpha_title` sort by code or title in the viewer's language (`core.en_ca`, `core.fr_ca`), so accented French titles sort correctly.
- `custom_rank` uses the `rank` on each value, so career levels can run from *Entry* to *Executive* in a meaningful order.
- `hierarchy` shows parents first, then children in each parent's order.

Lists, filters, exports and reports all follow the scheme's ordering.

### 3.3 Values of tenant schemes

Values are effective-dated rows in `core.code_value`: code, parent (hierarchical schemes), titles and descriptions in English and French, rank, and free attributes (for example a survey vendor's job number or level). Adding, renaming, retiring or moving a value is a change set operation with an effective date. A retired value stays on history and can no longer be assigned from its end date.

### 3.4 Starting templates

`schemes.json` offers templates a tenant can switch on and adjust: NOC, EEOG (derived from NOC), job family, career level, pay grade, salary survey match (one scheme per survey), pay equity job class, department code, position control number, budget line and legacy system ID. A tenant can add any other scheme, for example a three-letter internal occupational code in alphabetical order, a funder's position classification, or another country's occupational classification for staff abroad.

---

## 4. Attaching codes to jobs, positions and incumbents

### 4.1 Targets

| Target | Meaning | Typical schemes |
| --- | --- | --- |
| `job` | The job in the catalogue | NOC, job family, career level, grade, pay equity class |
| `position` | A budgeted seat | Position control number, budget line, department code, a NOC override for a position that differs from its job |
| `assignment` | The incumbent in that position, for that period | Legacy payroll ID, an incumbent-specific survey match (for example a job share where one incumbent does the senior half of the work) |
| `person` | The person across all jobs | Codes from another system that follow the person |
| `org_unit`, `location` | The unit or site | Department code, site code |
| `requisition` | A vacancy being recruited | NOC for the posting and for programs that require it |

The incumbent level matters because several people can hold one position (job share, overlap, pools). Codes that describe the person's own arrangement in the position belong to their assignment, not to the position.

### 4.2 One code, several codes, unique codes

`core.code_assignment` holds one row per code per target per period. The trigger `core.check_code_assignment()` refuses a code with these error codes:

| Refusal | When |
| --- | --- |
| `CODE_TARGET_NOT_ALLOWED` | The scheme does not apply to the target type (a legacy ID on a position) |
| `CODE_VERSION_NOT_ACCEPTED`, `CODE_VERSION_NOT_PUBLISHED` | A published code from a version the tenant has not accepted, or that is not loaded |
| `CODE_LEVEL_NOT_ASSIGNABLE` | A NOC minor group (`4220`) instead of a unit group |
| `CODE_FORMAT` | The code does not match the scheme's pattern |
| `CODE_NOT_IN_LIST` | A list scheme's code that is not a value on that date |
| `CODE_SHARE_NOT_ALLOWED` | A share on a one-value scheme |

The trigger also sets a `slot` that lets the exclusion constraints do the rest. It allows one value per version per target per day for `one` schemes, and one row per code for `many` schemes. A `unique` scheme lets a code belong to only one target at a time, so position control number `POS-00410` can move from NL-041 to NL-042 only when NL-041 releases it. For `many` schemes with `shares_total_100`, change set validation checks that the shares on a target add up to 100 on every date.

### 4.3 Example: one position, seven codes

Position NL-041 Community Support Worker 2, held by Ana Silva:

| Scheme | Code | Held on | Notes |
| --- | --- | --- | --- |
| NOC 2021 V1.0 | 42201 Social and community service workers | Job CSW2 | Inherited by the position and by Ana |
| Job family | CS-SUP Community Support (under CS Community Services) | Job | Hierarchical tenant scheme |
| Pay grade | G05 | Job | Custom rank |
| Salary survey A | S-410 (60%), S-415 (40%) | Position | Blended match |
| Department code | 410 | Position | Reporting code |
| Position control number | POS-00410 | Position | Unique; not inherited |
| Legacy payroll ID | L-88213 | Ana's assignment | Unique; incumbent only |

### 4.4 Inheritance and overrides

`core.resolve_codes(target_type, target_id, as_of)` returns the effective codes of a target on a date. For each scheme and version it takes the nearest level that has a code: the incumbent first, then the position, then the job. Schemes with `inherit = none` are read only from the target itself. Each code comes back with its origin, so the profile can show "NOC 42201, from the job".

A position whose work differs from its job can override the job's code: source `override`, with a reason where the scheme requires one. In the smoke test, NL-041 runs an early learning program from 1 September and is overridden to 42202, while the job stays 42201. A high share of overrides on a job is reported as a sign that the job catalogue needs a new job.

### 4.5 History and changes

Codes are effective-dated and bi-temporal like everything else (`docs/03`). Attaching, changing, overriding or ending a code is a change set operation (§10). The consequences list shows what follows from the change:

- reports and employment equity groups that change;
- requirements that the new NOC would propose;
- survey matches that no longer satisfy a consistency rule;
- requisitions that carry the old code.

---

## 5. Connected and related

### 5.1 Mappings

| Table | Holds | Examples |
| --- | --- | --- |
| `ref.code_mapping` | Published correspondence between versions and crosswalks between schemes, with the relation (`one_to_one`, `split`, `merge`, `partial`, `renamed`) and the share where the publisher gives one | NOC 2021 → NOC 2026; NOC 2016 → NOC 2021; NOC 2021 ↔ ISCO-08 |
| `core.code_mapping` | The tenant's own mappings, effective-dated | Internal occupational code → NOC; job family → survey benchmark; the tenant's decision for a NOC 2026 split |

### 5.2 Derived schemes

A derived scheme has no values of its own on targets. Its code is computed from another scheme through a mapping, and it is recomputed when the source code changes. The main case is the employment equity occupational group (EEOG), derived from NOC through ESDC's correspondence and used by federal employment equity reports (Module 13). TEER and broad category are attributes of the NOC code, not separate schemes.

### 5.3 Consistency rules

`core.code_scheme_rule` keeps schemes consistent. Each rule produces a warning or blocks the change set.

| Kind | Meaning | Example |
| --- | --- | --- |
| `requires` | If scheme A has a code, scheme B must too | Every job with a survey match has a NOC code |
| `must_map` | A's code must map to B's code at a given level | A survey match must map to the job's NOC minor group, or warn |
| `derive` | B is computed from A | EEOG from NOC |
| `same_branch` | Two hierarchical codes must share an ancestor | A position's department code must sit under its job family's division |

### 5.4 What stays where it is

- **Agreement classifications and grid steps** (CSW2 step 3) stay in the agreement library (`docs/17` §2, `docs/08`). They price the work and drive seniority and layoff. The similarity scorer can use them as an internal signal, but they are not copied into a code scheme.
- **GL segments** (cost centre, fund, program) stay in `finance.cost_distribution` (`docs/17` §8).
- **Integration keys** between systems (identity provider IDs, ERP keys) stay in `core.external_ref`. A code scheme is for codes people see, search, filter and report on.
- **The old columns** `core.job_version.noc_code`, `pay_equity_class` and `ee_occupational_group` are read only by the data migration into code assignments, then ignored. New code reads codes only through `core.resolve_codes()`, the same pattern as `core.position_funding` in `docs/17` §8.1.

---

## 6. Requirements for each position

### 6.1 Where requirements live

Requirements belong to the job, which gives the default, and to the position, which can add requirements or switch an inherited one off with a reason (`core.work_requirement_suppression`). They never belong to the person. What a person *holds* is in their credentials, learning records and documents (Modules 01 and 08), and CanDo compares the two.

### 6.2 What a requirement records

| Field | Meaning |
| --- | --- |
| `kind` | education, training, experience, licence, certification, registration, language, security screening, driver's licence, physical demand, working condition, skill, competency, other |
| `strength` | `required`, `preferred` or `asset` |
| Text (EN/FR) | As it will appear in a posting |
| `criteria`, `match_key` | The structured form, for example `{ "educationLevel": "college_diploma", "fields": ["social work", "child and youth care"] }` with key `education:college_diploma`. Keys come from the vocabulary in `schemes.json`, so requirements on different jobs can be compared. |
| `jurisdictions` | Where it applies, for example a regulated profession's provincial registration |
| `verification` | Self-declared, document, credential record, background check, assessment or none |
| `satisfied_by` | The course codes, credentials or codes that meet it, linked to Module 08 |
| `rationale` | Why the requirement is a bona fide occupational requirement. It is mandatory for an active `required` item (a database check). |
| `source`, `source_ref` | NOC (with version, code and statement number), job, position, collective agreement, legislation or manual |
| `status` | `proposed` (not yet decided) or `active` |

### 6.3 Proposed from NOC, decided by HR

When a job is coded, CanDo proposes the unit group's employment requirement statements as `proposed` requirements, each with its source. If the unit group has sub-groups, only the matching sub-group's statements are proposed: a notary position gets the *Notaries (Quebec)* statements, not the *Lawyers* ones. CanDo pre-fills the strength from NOC's wording as a starting point, never as a decision:

| NOC wording | Proposed strength |
| --- | --- |
| *is required* | required |
| *is usually required* | preferred |
| *may be required* | asset |

HR accepts, edits or rejects each proposal. Accepting one as `required` asks for the rationale.

NOC describes what is typical for an occupation across Canada. The employer decides what its job actually needs, and a requirement such as "Canadian experience" or a degree the work does not need can discriminate. The proposal screen says so in plain words.

Regulated occupations are flagged. When a NOC statement says a licence, certificate or registration is required (156 unit groups have at least one such statement, by the derived tags), the proposal carries the province from the position's location and links to the licence tracking in Module 13.

### 6.4 Where requirements are used

| Module | Use |
| --- | --- |
| 02 Recruitment | Requisitions copy the position's active requirements into the posting and screening questions. The posting validator checks them against each jurisdiction's posting rules. |
| 02 Onboarding | Licences, registrations and screenings marked `document` or `background_check` become checklist items before the start date |
| 08 Learning | `satisfied_by` courses and credentials; required courses for a job move (the stage 3 link) |
| 09 Succession | Readiness gaps: required items a successor does not yet hold |
| 13 Compliance | Expiry of licences and registrations for every incumbent whose position requires them |
| 12 Analytics | Positions without requirements, required items without rationale, incumbents missing a required credential |

---

## 7. Finding the most similar position

### 7.1 What can be asked

The question can start from:

- a position or job in CanDo;
- a NOC code;
- a free-text title or description from outside CanDo, such as a job posting or a role being designed;
- a person, for internal mobility, redeployment, accommodation or layoff alternatives;
- a code from another scheme, such as an ISCO or U.S. SOC code from a foreign credential.

The answer is a ranked list of positions with a score from 0 to 100 and the reasons behind it. By default the list shows positions that are available: vacant on the as-of date, becoming vacant soon, or with an open requisition.

### 7.2 Steps

1. **Resolve the question to codes.** A position or job uses its effective codes and requirements on the as-of date. A title goes through the title search (§2.6) and becomes NOC candidates. An external code goes through `ref.code_mapping`.
2. **Filter candidates in SQL.** Apply the profile's filters: available, active (not frozen or eliminated), same legal entity or location if asked, the asker's security scope. For a person, also require that they hold every `required` item.
3. **Score** each candidate (§7.3).
4. **Explain** with reason codes (§7.6) and **rank**.

### 7.3 The score

Each component is a value from 0 to 1. Components that cannot be computed for a pair (for example no requirements on either side) are left out, and the remaining weights are renormalized.

| Component | Value | Default weight |
| --- | --- | --- |
| Occupation | NOC proximity from the deepest common ancestor: same unit group 1.00, minor group 0.75, sub-major group 0.55, major group 0.40, broad category 0.15, otherwise 0. If either unit group names the other in its exclusions, at least 0.60. | 0.45 |
| TEER | 1 − \|TEER difference\| ÷ 5 | 0.15 |
| Requirements | Weighted Jaccard over requirement match keys (required 1.0, preferred 0.5, asset 0.25): Σ min ÷ Σ max | 0.25 |
| Internal | Average over the internal schemes named in the profile: equal codes 1 or 0; ranked codes 1 − \|rank difference\| ÷ range | 0.15 |
| Title | pg_trgm `similarity()` of the titles, as PostgreSQL computes it | 0 (1 for title search) |

The total is 100 × Σ(weight × value) ÷ Σ(weight), rounded half up to one decimal. Ties go to the higher occupation value, then the position number in natural order.

**Why NOC's exclusions matter.** The hierarchy alone can miss close neighbours. For example, 11200 Human resources professionals and 12101 Human resources and recruitment officers share only the broad category, because they have different TEER categories. Likewise, 42201 Social and community service workers and 41300 Social workers sit in different major groups. In each pair, the publication lists the other group in its exclusions because the work is functionally similar. 514 of the 516 unit groups have such cross-references, about four each, so CanDo uses them as an explicit signal.

**Worked example** (`tests/classifications/similarity_cases.json`, SIM-001). The question is position NL-041, coded NOC 42201, job family CS-SUP, grade G05. Its requirements are a college diploma (required), social services experience (preferred), a vulnerable sector check (required) and a driver's licence (asset).

| Candidate | Occupation | TEER | Requirements | Internal | Score |
| --- | --- | --- | --- | --- | --- |
| H-118 Housing Support Worker, 42201, CS-SUP, G05 | 1.00 (same unit group) | 1.00 | 0.82 | 1.00 | **95.5** |
| NL-047 Early Childhood Educator, 42202, CS-ECE, G04 | 0.75 (same minor group 4220) | 1.00 | 0.53 | 0.45 | **68.8** |
| NL-031 Social Worker, 41300, CS-SW, G08 | 0.60 (NOC cross-reference) | 0.80 | 0.21 | 0.35 | **49.5** |
| H-126 Home Support Worker, 44101, CS-SUP, G03 | 0.15 (same broad category) | 0.60 | 0.28 | 0.90 | **36.2** |
| NL-012 Payroll Administrator, 13102, FIN-PAY, G05 | 0 | 0.80 | 0 | 0.50 | **19.5** |

NL-050 has the same code but is not available, so it is excluded with reason `NOT_AVAILABLE`.

Checked by hand for H-118:

- Requirements: Σ min = 1 + 0 + 1 + 0.25 = 2.25 and Σ max = 1 + 0.5 + 1 + 0.25 = 2.75, so the value is 2.25 ÷ 2.75 = 0.8182.
- Total: 100 × (0.45 + 0.15 + 0.25 × 0.8182 + 0.15) = 95.45, which rounds to 95.5.

### 7.4 Profiles

`core.similarity_profile` holds the weights, proximity values, internal schemes and filters per purpose. The defaults are in `schemes.json`:

| Profile | Use | What changes |
| --- | --- | --- |
| `default` | Most similar available positions | As in §7.3 |
| `redeployment` | Layoff alternatives, return to work, accommodation | Requirements weigh more; the person must hold every required item; reasons list what is missing for the excluded positions |
| `succession` | Successor slates, career paths | Includes filled positions; shows requirement gaps |
| `survey_benchmark` | Choosing salary survey matches and comparators | Occupation and TEER weigh more; includes filled positions |
| `duplicate_jobs` | Cleaning the job catalogue | Compares jobs with jobs; title counts a little |
| `title_search` | A title typed in from outside | Title only, until a NOC code is chosen |

### 7.5 Across versions and schemes

A candidate coded in another version (NOC 2016 V1.3 4212, or NOC 2026 later) or another scheme (ISCO-08) is first mapped into the question's version through `ref.code_mapping`, then compared. A split mapping gives the share-weighted average of the parts. SIM-003 shows a split of 0.6 to 42201 and 0.4 to 42202, giving 0.6 × 1.00 + 0.4 × 0.75 = 0.90. The result is marked `VIA_CORRESPONDENCE`. Without a mapping, the occupation component is left out and the reason `NO_CORRESPONDENCE` is shown.

### 7.6 Explanations

Every result carries reason codes with parameters, and the screens translate them into English and French. The codes are:

- occupation: `SAME_UNIT_GROUP`, `SAME_MINOR_GROUP`, `SAME_SUB_MAJOR_GROUP`, `SAME_MAJOR_GROUP`, `SAME_BROAD_CATEGORY`, `DIFFERENT_OCCUPATION`, `NOC_CROSS_REFERENCE`;
- correspondence: `VIA_CORRESPONDENCE`, `NO_CORRESPONDENCE`;
- TEER: `TEER_SAME`, `TEER_DIFFERENT`;
- requirements and internal codes: `REQUIREMENTS_SHARED` (shared and total keys), `INTERNAL_MATCH`, `INTERNAL_DIFFERENT`;
- title: `TITLE_SIMILAR`;
- exclusions: `NOT_AVAILABLE`, `MISSING_REQUIRED` (with the missing keys).

For example: "Same minor group 4220 (Paraprofessional occupations in legal, social, community and education services); TEER 2 for both; 2 of 5 requirements shared."

### 7.7 Guardrails

- **Proposals only.** The list helps a person decide. Moving, offering, bumping and accommodating are decided by people and by the rules that apply. Under a collective agreement, posting, bumping and recall follow the agreement's own rules (`docs/17` §11); similarity can inform a choice those rules leave open, never override them.
- **No protected grounds.** The scorer uses work facts only: codes, requirements, grades and titles. It never uses age, sex, gender identity, race, disability, family status, other protected grounds or self-identification data, and has no access to them.
- **Scope.** A user sees only candidates inside their security scope, and the reasons never reveal another position's incumbent or pay.
- **Logged.** Searches from redeployment and accommodation, and the choice made, are kept with the case (Modules 11 and 13).

### 7.8 Reference and tests

`reference/position_similarity_reference.py` is the readable specification. It loads `noc-2021-v1.0-structure.json`, computes every component with Decimal arithmetic, implements pg_trgm's `similarity()` exactly (seven cases compared with PostgreSQL 16), and ranks. `tests/classifications/similarity_cases.json` holds 19 cases:

- five ranking cases, covering the default profile, a NOC 2016 candidate, a split correspondence, redeployment with missing requirements and a title-only search;
- seven trigram parity cases;
- seven hierarchy depth cases.

The TypeScript port must reproduce every value (`python3 reference/position_similarity_reference.py --selftest`).

### 7.9 Performance

Each position's similarity features are refreshed when a change set that touches its codes, requirements or job commits:

- NOC path and TEER;
- requirement keys with strengths;
- internal codes;
- normalized title.

Candidate filtering uses indexed columns and the org closure tables. Scoring runs in the API on the filtered set. Target: under 300 ms for 50,000 positions with the default profile.

---

## 8. Versions: NOC 2026 and later

### 8.1 Version status

| Status | Meaning |
| --- | --- |
| `announced` | Known to be coming; no items. Codes cannot be assigned. |
| `loading` | The loader is inserting it |
| `published` | Loaded, hashed and frozen; tenants can accept it |
| `superseded` | A newer version exists; still readable and still accepted where the tenant allows |
| `retired` | Kept for history only |

**NOC 2026 V1.0** is in the catalogue as `announced`. Statistics Canada's consultation report says it will be released in December 2026. The report also says:

- 165 unit groups are affected: 18 with real (structural) changes and 147 with content-only changes;
- the real changes include new unit groups, split-offs, take-overs and transfers;
- a NOC 2021 V1.0 to NOC 2026 V1.0 correspondence table will be released with it.

The design keeps the 5-digit code and TEER, as the report implies. If the release changes the structure, the loader's count checks will show it and this section will be updated.

### 8.2 When NOC 2026 is released

1. Load NOC 2026 V1.0 and the official correspondence table into `ref` (§2.4), add their hashes to `schemes.json`, and publish.
2. Tenants see a notice. Each tenant chooses when to adopt: it adds `NOC-2026-1.0` to `accepted_version_ids` and sets an effective date.
3. **Recoding campaign** (`core.recoding_campaign`). For every NOC 2021 code on a job, position, incumbent or open requisition:
   - `one_to_one` or `renamed`: proposed automatically in one bulk change set;
   - `split`: a task for HR with a suggestion ranked by duties and requirements (`core.code_suggestion`, purpose `recoding`), since the publisher's table says which groups the work could go to but not which one this job is;
   - `merge` and `partial`: proposed, flagged for review.

   Nothing is committed until a person approves the change set.
4. **Dual coding.** During the transition a target can carry both its NOC 2021 and its NOC 2026 code: one per version, which the exclusion constraint allows. Each report states which version it uses, and government reports use the version the program requires.
5. **History is kept.** Past codes stay on their dates. "As of 2026" reports show NOC 2021; later ones show NOC 2026. Comparisons across years go through the correspondence table.
6. **Requirements.** For each recoded job, CanDo compares the new unit group's requirements with the job's active requirements and proposes additions. It never removes requirements on its own.

### 8.3 Other schemes and countries

The same mechanism serves other versions and countries:

- earlier NOC versions for history;
- ISCO-08 for international comparison;
- the U.S. and U.K. Standard Occupational Classifications for staff abroad or foreign surveys;
- any other national classification.

Each loads as a published scheme with versions and, where the publisher provides them, crosswalks to NOC.

---

## 9. Data model (migration 0004)

| Table | Kind | Purpose |
| --- | --- | --- |
| `ref.code_scheme` | Global | Published schemes (NOC, EEOG, ISCO, U.S. SOC, U.K. SOC) |
| `ref.code_scheme_version` | Global | Versions with status, release, levels, assignable levels, source, licence, hash |
| `ref.code_item` | Global | Every group of every version: code, level, depth, parent, titles, definitions, attributes (TEER, broad category), content, cross-references; frozen once published |
| `ref.code_item_title` | Global | Official, example, inclusion and index titles, trigram-indexed |
| `ref.code_item_requirement` | Global | Published requirement statements with sub-group, kinds and strength |
| `ref.code_mapping` | Global | Correspondence and crosswalks |
| `core.code_scheme` | Tenant | Every scheme the tenant uses, with its settings (§3.1) |
| `core.code_value` | Tenant, effective-dated | Values of tenant schemes |
| `core.code_assignment` | Tenant, effective-dated | Codes on targets, with share, match quality, source, reason, evidence |
| `core.code_mapping` | Tenant, effective-dated | Tenant mappings |
| `core.code_scheme_rule` | Tenant | Consistency rules |
| `core.work_requirement` | Tenant, effective-dated | Job and position requirements |
| `core.work_requirement_suppression` | Tenant, effective-dated | A position switching off a job requirement |
| `core.code_suggestion` | Tenant | Coding, recoding and requirement suggestions with candidates and decisions |
| `core.recoding_campaign` | Tenant | One campaign per version change |
| `core.similarity_profile` | Tenant | Weights, proximity values, internal schemes, filters |

The functions are:

- `ref.code_path` and `ref.code_common_depth` for hierarchy distance;
- `ref.search_code_titles` for title search;
- `core.check_code_assignment` (trigger) for integrity;
- `core.resolve_codes` for effective codes by date with their origin.

Collations `core.natural_sort`, `core.en_ca` and `core.fr_ca` handle ordering. Row-level security is forced on every new `core` table. `ref.noc.title_fr` becomes nullable until the French publication is loaded.

---

## 10. Operations, API and events

**Change set operations** (added to `docs/03` §4):

- `code_scheme.create`, `code_scheme.update`, `code_scheme.retire`;
- `code_value.add`, `code_value.update`, `code_value.retire`, `code_value.move`;
- `code.assign`, `code.change`, `code.override`, `code.end`;
- `code_mapping.set`, `code_scheme_rule.set`;
- `requirement.propose_from_code`, `requirement.accept`, `requirement.set`, `requirement.end`, `requirement.suppress`;
- `recoding_campaign.create`, `recoding_campaign.commit`.

**Validation** (added to `docs/03` §6):

- the trigger refusals in §4.2;
- shares add to 100 for `shares_total_100` schemes;
- `required_on` schemes present before a job or position is activated;
- consistency rules (§5.3);
- override reasons;
- a rationale for every active required requirement.

**API** (`api/openapi-codes.yaml`, merged into `api/openapi.yaml` in Step 5):

| Method and path | Purpose |
| --- | --- |
| `GET /code-schemes`, `POST /code-schemes`, `GET /code-schemes/{schemeCode}` | List, create and read schemes |
| `GET /code-schemes/{schemeCode}/values?asOf=&q=&parent=` | Values in the scheme's order, with search |
| `GET /classifications/{versionId}/items/{code}` | A published group with its full profile |
| `GET /classifications/{versionId}/search?q=&lang=` | Title search (§2.6) |
| `GET /{targetType}/{targetId}/codes?asOf=` | Effective codes with origin (`core.resolve_codes`) |
| `POST /{targetType}/{targetId}/code-suggestions` | Coding suggestions from title, duties or structure |
| `GET /jobs/{jobId}/requirements`, `GET /positions/{positionId}/requirements?asOf=` | Requirements with inheritance and suppressions |
| `POST /jobs/{jobId}/requirements/propose` | Proposals from the job's NOC unit group |
| `POST /similar-positions` | Ranked similar positions for a position, job, NOC code, title, person or external code, with a profile |
| `POST /recoding-campaigns`, `GET /recoding-campaigns/{id}` | NOC 2026 recoding |

Writes go through `POST /change-sets` as everywhere else.

**Events** (added to `api/events.yaml` in Step 5):

- `code.assigned`, `code.changed` and `code.ended` carry the target, scheme, version, before and after;
- `requirement.changed`;
- `classification_version.published` starts the tenant notice for a new NOC;
- `recoding_campaign.committed`.

Subscribers include:

- Recruitment, for postings on open requisitions;
- Compensation, for survey matching;
- Analytics, to refresh features and reports;
- Compliance, for employment equity groups and licence tracking.

---

## 11. Screens

- **Job and position: Codes tab.** Every scheme in display order with its code, title, origin (job, position or incumbent), dates and History. Actions are Add, Change, Override (with reason) and End. Empty required schemes are flagged.
- **NOC coding assistant** (§2.6). Title search, the side-by-side profile and the structure walk, plus the "Other" and supervisor conventions in plain words.
- **Job and position: Requirements tab.** Active requirements, NOC proposals waiting for a decision (with their source statement), inherited requirements and suppressions. "Required" asks for the rationale.
- **Similar positions panel.** Available from a position, a job, a requisition, a person's profile, the redeployment case and the succession slate. It shows the score bar, the component values and the reasons in the user's language, with profile and filter choices.
- **Admin → Code schemes.** Create and configure schemes (§3.1), manage values with drag-to-order for custom ranks (with a keyboard alternative), and manage mappings and consistency rules.
- **Admin → Classifications.** Loaded versions, their status, counts, hash and source; accept a new version; start a recoding campaign; work through the split tasks.

---

## 12. Reports and analytics

- Headcount, vacancies and pay by NOC unit, minor, sub-major and major group, broad category and TEER, as of any date and for a stated version.
- Employment equity workforce analysis by EEOG (derived from NOC).
- Survey match coverage, share of positions matched by quality, and positions whose survey match breaks a consistency rule.
- Jobs and positions missing required codes; overrides per job.
- Requirements by kind and strength; required items without a rationale; regulated positions and their licence coverage; incumbents missing a required credential.
- Recoding campaign progress.

All reports respect small-group suppression and field security (Module 12).

---

## 13. Acceptance scenarios

| ID | Scenario | Expected | Step |
| --- | --- | --- | --- |
| CODE-001 | Load NOC 2021 V1.0 from the three files | Hashes match `schemes.json`; 10, 45, 89, 162 and 516 items; 28,012 index titles; 2,063 requirement statements; version `published` | 5 |
| CODE-002 | Change a published NOC item | Refused with `CODE_VERSION_IMMUTABLE` | 1 |
| CODE-003 | Search "youth worker" in NOC 2021 | 42201 first, matched title shown | 5 |
| CODE-004 | Assign 42201 to job CSW2; then assign 4220 | First accepted; second refused with `CODE_LEVEL_NOT_ASSIGNABLE` | 1 |
| CODE-005 | Assign a NOC 2026 code before NOC 2026 is published and accepted | Refused (`CODE_VERSION_NOT_ACCEPTED`) | 1 |
| CODE-006 | Second NOC 2021 code on the same job for overlapping dates | Refused (one value per version per day) | 1 |
| CODE-007 | Tenant creates an internal scheme ordered alphabetically by title in French | Values list in fr-CA collation order (accented titles sorted correctly); natural order for `natural_code` schemes (G2 before G10) | 5 |
| CODE-008 | Job family code that is not a value on the date | Refused with `CODE_NOT_IN_LIST` | 1 |
| CODE-009 | Position control number with the wrong format; the same number on two positions at once; then moved after the first releases it | `CODE_FORMAT`; refused; accepted | 1 |
| CODE-010 | Legacy ID on a position instead of the incumbent | Refused with `CODE_TARGET_NOT_ALLOWED`; accepted on the assignment, upper-cased | 1 |
| CODE-011 | Two survey matches on one position, 60% and 40%; then 60% and 30% | First accepted; second refused at validation (shares must total 100) | 5 |
| CODE-012 | Effective codes for Ana's assignment | NOC and job family from the job, survey match from the position, legacy ID from the assignment; position control number not inherited | 5 |
| CODE-013 | Position override to 42202 from 1 September, with reason | Ana's NOC is 42202 from that date and 42201 before; profile shows the origin | 5 |
| CODE-014 | Code job CSW2 as 42201 | Three NOC requirement statements proposed with source; strengths pre-filled per §6.3; none active until HR decides | 5 |
| CODE-015 | Accept a requirement as required without a rationale | Refused; accepted with a rationale | 1 and 5 |
| CODE-016 | Code a job as 41101 for a Quebec notary position | Only the *Notaries (Quebec)* statements are proposed | 5 |
| CODE-017 | A position suppresses an inherited job requirement with a reason | The requirement disappears from the position and its postings from the date; History shows the reason | 5 |
| CODE-018 | Similar positions for NL-041 with the default profile | Ranking and scores as SIM-001 (H-118 95.5, NL-047 68.8, NL-031 49.5, H-126 36.2, NL-012 19.5; NL-050 excluded as not available) | 5 |
| CODE-019 | Candidate coded in NOC 2016 V1.3 | Compared through the correspondence table, marked `VIA_CORRESPONDENCE` (SIM-002) | 5 |
| CODE-020 | Redeployment for a person without a vulnerable sector check | Positions requiring it excluded with `MISSING_REQUIRED` and the missing key (SIM-004) | 16 |
| CODE-021 | Title-only search "youth outreach worker" | Scores equal to PostgreSQL `similarity()` × 100 (SIM-005) | 5 |
| CODE-022 | Successor suggestions for a key position | Succession profile; requirement gaps listed per candidate | 17 |
| CODE-023 | Requisition from NL-041 | Posting carries the position's active requirements and NOC code; posting validator runs on them | 14 |
| CODE-024 | Similarity results for a user scoped to one division | Only positions in scope; no incumbent names or pay in the reasons | 5 |
| CODE-025 | NOC 2026 published; tenant accepts it from 1 April 2027 | Recoding campaign: one-to-one codes proposed in one change set; each split becomes a task with ranked suggestions; nothing committed before approval | 5 (loader), 18 (campaign screens) |
| CODE-026 | During the transition, a job carries both 42201 (2021) and its 2026 code | Allowed; reports state their version | 5 |
| CODE-027 | Headcount by TEER and NOC minor group as of two dates | Correct for each date; small groups suppressed | 18 |
| CODE-028 | EEOG derived from NOC after the ESDC correspondence is loaded | Every job's EEOG computed; recomputed when its NOC changes | 18 |
| CODE-029 | Another tenant reads codes or requirements | Sees none; cannot write into the first tenant | 1 |
| CODE-030 | A survey match that does not map to the job's NOC minor group under a `must_map` rule with severity `warning` | Change set shows the warning; approval still possible | 5 |

Scenarios CODE-002, 004 to 006, 008 to 010, 012, 013, 015 and 029 are already covered by `tests/schema/schema_0004_smoke.sql`. CODE-018 to 021 are covered by `tests/classifications/similarity_cases.json`.

---

## 14. Changes to other documents

| Document | Change |
| --- | --- |
| `requirements/01` Position management and Job architecture | Replaced by §3 to §6 (codes, schemes, requirements); position attributes gain codes and requirements; NOC row now refers to this document |
| `requirements/02` Requisitions and postings | Requisitions carry NOC and the position's requirements; screening questions from requirements; onboarding checklist items from licences and screenings (§6.4) |
| `requirements/04` Market pricing | Salary survey matches are code schemes with shares and match quality (§3, §4); the survey benchmark profile (§7.4) suggests matches |
| `requirements/08` Learning | `satisfied_by` links requirements to courses and credentials |
| `requirements/09` Succession and workforce planning | Successor and career path suggestions from the similarity scorer; workforce plans by NOC and TEER |
| `requirements/11` Offboarding | Layoff alternatives and redeployment use the redeployment profile, inside the agreement's rules |
| `requirements/12` Analytics | Reports in §12 |
| `requirements/13` Compliance | EEOG derived from NOC; licence and registration tracking from requirements |
| `docs/03` §4 and §6 | Operations and validation in §10 |
| `docs/03` §5 | Job no longer carries NOC, pay equity class and employment equity group as columns (§5.4) |
| `docs/05` §3 cascade matrix | `code.changed` on a job → re-resolve inherited codes, propose requirements, recompute derived schemes and similarity features |
| `docs/12` Smart assistant | Tools: coding suggestion from duties text; explanation of a similarity result |
| `docs/13` Screens | §11 |
| `docs/15` Steps 1, 5, 14, 17 and 18 | Migration 0004 in Step 1; loader, codes, requirements and similarity in Step 5; requisition requirements in Step 14; succession in Step 17; equity and recoding screens in Step 18 (see AGENTS "How to work") |
| `AGENTS.md` | Reading order item for this document and rules 31 to 33 |
| `api/openapi.yaml`, `api/events.yaml` | Paths in `api/openapi-codes.yaml` merged in Step 5; events in §10 |
| `schema/0004_position_codes.sql`, `tests/schema/schema_0004_smoke.sql` | New |
| `rules/classifications/`, `reference/position_similarity_reference.py`, `tests/classifications/similarity_cases.json` | New |

---

## 15. Open questions

| # | Question | Default until decided |
| --- | --- | --- |
| C1 | Load the French CNP 2021 V1.0 before the first French-speaking tenant? (`docs/16` Q22) | Required before go-live for any tenant using French; English title marked *EN* until then |
| C2 | Adopt NOC 2026 for CanDo's own defaults and demo tenants when it is released, or wait for customers to ask? (Q23) | Load it within a month of release; tenants adopt on their own date |
| C3 | Turn on assistant ranking of NOC codes from duties text? (Q24) | Off until the assistant is approved (`docs/12`); title search and structure walk always on |
| C4 | Source for the EEOG list and NOC 2021 correspondence (Q25) | Load from ESDC's Labour Program publication before Step 18 |
| C5 | Default similarity weights after testing with anchor customers (Q26) | §7.3 defaults; tenants can tune per profile |

---

## Sources

- Statistics Canada, National Occupational Classification (NOC) 2021 Version 1.0, Catalogue no. 12-583-X (release date September 21, 2021; PDF published November 2, 2022), the publication extracted into `rules/classifications/`
- Statistics Canada, Revising the National Occupational Classification (NOC) 2021 Version 1.0 to NOC 2026 Version 1.0, consultation results report: https://www.statcan.gc.ca/en/consultation/2024/noc/results-report
- Statistics Canada, NOC 2021 Version 1.0 standard: https://www.statcan.gc.ca/eng/subjects/standard/noc/2021/indexV1
- Employment and Social Development Canada, NOC revision process: https://cnp.edsc.gc.ca/Home/RevisionProcess
- Statistics Canada Open Licence: https://www.statcan.gc.ca/en/terms-conditions/open-licence
- PostgreSQL 16 documentation, pg_trgm (similarity and word similarity) and ICU collations
