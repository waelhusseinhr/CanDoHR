-- =====================================================================================
-- CanDo HRIS — migration 0003: enterprise structures, funding, calendars, go-live
-- Applies after 0001_initial (schema/cando_schema.sql) and 0002_roles.
-- Specification: docs/17-enterprise-structures-and-integration.md (section numbers below).
-- Conventions as in 0001: tenant_id + RLS on every tenant table, effective-dated rows with
-- valid_period and sys_period, money numeric(14,2), change_set_id on every business version.
-- =====================================================================================

CREATE SCHEMA IF NOT EXISTS finance;

-- -------------------------------------------------------------------------------------
-- Calendars (docs/17 §9.1): fiscal, funder, agreement, plan, leave and pension years
-- -------------------------------------------------------------------------------------
CREATE TABLE finance.calendar (
  tenant_id     uuid NOT NULL,
  calendar_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('fiscal','funder','agreement_year','benefit_plan_year','leave_year','pension_year','custom')),
  owner_type    text NOT NULL CHECK (owner_type IN ('tenant','legal_entity','funding_source','agreement','benefit_plan','pension_plan','leave_plan')),
  owner_id      text,
  name_en       text NOT NULL,
  name_fr       text,
  UNIQUE (tenant_id, code)
);

CREATE TABLE finance.calendar_period (
  tenant_id     uuid NOT NULL,
  period_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  calendar_id   uuid NOT NULL REFERENCES finance.calendar,
  year_label    text NOT NULL,                       -- e.g. 'FY2026-27'
  period_no     smallint NOT NULL CHECK (period_no BETWEEN 1 AND 53),
  dates         daterange NOT NULL,
  status        text NOT NULL DEFAULT 'future' CHECK (status IN ('future','open','soft_closed','closed','locked')),
  closed_at     timestamptz,
  closed_by     uuid,
  UNIQUE (calendar_id, year_label, period_no),
  EXCLUDE USING gist (calendar_id WITH =, dates WITH &&)
);

-- -------------------------------------------------------------------------------------
-- Organization: hierarchies and tenant-defined level types (docs/17 §3)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.hierarchy (
  tenant_id     uuid NOT NULL,
  hierarchy_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('management','financial','funding','geographic','governance','custom')),
  name_en       text NOT NULL,
  name_fr       text,
  UNIQUE (tenant_id, code)
);
-- exactly one management hierarchy per tenant (the second half of "exactly" is checked at tenant setup)
CREATE UNIQUE INDEX hierarchy_one_management ON core.hierarchy (tenant_id) WHERE kind = 'management';

CREATE TABLE core.org_level_type (
  tenant_id            uuid NOT NULL,
  hierarchy_id         uuid NOT NULL REFERENCES core.hierarchy,
  code                 text NOT NULL,                -- e.g. CORP, CLUSTER, DEPT, DIV, SECTION, SECTOR, UNIT, CREW
  name_en              text NOT NULL,
  name_fr              text,
  rank                 smallint NOT NULL CHECK (rank >= 1),
  allowed_parent_codes text[] NOT NULL DEFAULT '{}', -- empty = only the level with rank - 1 (or none for rank 1)
  owns_budget          boolean NOT NULL DEFAULT false,
  is_cost_object       boolean NOT NULL DEFAULT false,
  approval_level       boolean NOT NULL DEFAULT false,
  may_be_bargaining_employer boolean NOT NULL DEFAULT false,
  may_anchor_security_scope  boolean NOT NULL DEFAULT true,
  authority_limits     jsonb NOT NULL DEFAULT '{}'::jsonb, -- delegation of authority (§3.5)
  PRIMARY KEY (hierarchy_id, code)
);

-- org_unit_version: unit_type is no longer a fixed list; it must equal level_type_code
ALTER TABLE core.org_unit_version DROP CONSTRAINT IF EXISTS org_unit_version_unit_type_check;
ALTER TABLE core.org_unit_version
  ADD COLUMN hierarchy_id        uuid REFERENCES core.hierarchy,
  ADD COLUMN level_type_code     text,
  ADD COLUMN bargaining_employer boolean NOT NULL DEFAULT false;
ALTER TABLE core.org_unit_version
  ADD CONSTRAINT org_unit_version_level_matches_type
  CHECK (level_type_code IS NULL OR level_type_code = unit_type);

-- Mapping from a management node to its node in another hierarchy (§3.2)
CREATE TABLE core.org_node_mapping (
  tenant_id            uuid NOT NULL,
  mapping_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source_org_unit_id   uuid NOT NULL REFERENCES core.org_unit,
  target_hierarchy_id  uuid NOT NULL REFERENCES core.hierarchy,
  target_org_unit_id   uuid NOT NULL REFERENCES core.org_unit,
  valid_period         daterange NOT NULL,
  sys_period           tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id        uuid NOT NULL,
  EXCLUDE USING gist (source_org_unit_id WITH =, target_hierarchy_id WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period))
);

CREATE TABLE core.position_hierarchy_override (
  tenant_id            uuid NOT NULL,
  override_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position_id          uuid NOT NULL REFERENCES core.position,
  target_hierarchy_id  uuid NOT NULL REFERENCES core.hierarchy,
  target_org_unit_id   uuid NOT NULL REFERENCES core.org_unit,
  reason               text NOT NULL,
  valid_period         daterange NOT NULL,
  sys_period           tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id        uuid NOT NULL,
  EXCLUDE USING gist (position_id WITH =, target_hierarchy_id WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period))
);

-- Closure table per hierarchy per valid period; derived, rebuilt after each committed change set (§3.3)
CREATE TABLE core.org_closure (
  tenant_id            uuid NOT NULL,
  hierarchy_id         uuid NOT NULL REFERENCES core.hierarchy,
  ancestor_id          uuid NOT NULL,
  descendant_id        uuid NOT NULL,
  depth                smallint NOT NULL CHECK (depth >= 0),
  valid_period         daterange NOT NULL,
  built_from_change_set uuid,
  EXCLUDE USING gist (hierarchy_id WITH =, ancestor_id WITH =, descendant_id WITH =, valid_period WITH &&)
);
CREATE INDEX org_closure_ancestor ON core.org_closure USING gist (ancestor_id, valid_period);
CREATE INDEX org_closure_descendant ON core.org_closure USING gist (descendant_id, valid_period);

-- Groupings that agreements reference: Branch, business unit, facility ... (§3.4)
CREATE TABLE core.org_grouping_rule (
  tenant_id   uuid NOT NULL,
  code        text NOT NULL,
  name_en     text NOT NULL,
  name_fr     text,
  basis       jsonb NOT NULL,   -- { "kind": "level_type" | "first_excluded_head" | "subtree" | "facility" | "classification_within" | "bargaining_unit", ... }
  PRIMARY KEY (tenant_id, code)
);

-- -------------------------------------------------------------------------------------
-- Reporting relationships and authority (§5)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.relationship_type (
  tenant_id   uuid NOT NULL,
  code        text NOT NULL,   -- line, administrative, functional, project, timekeeper, acting_manager, delegate, hrbp, mentor
  name_en     text NOT NULL,
  name_fr     text,
  is_line     boolean NOT NULL DEFAULT false,
  authorities jsonb NOT NULL,  -- { "approveTime": true, "approveLeave": true, "approveOvertime": true, "initiate": true, "review": "lead|contribute|none", "viewPay": false, ... }
  PRIMARY KEY (tenant_id, code)
);

ALTER TABLE core.assignment_relationship DROP CONSTRAINT IF EXISTS assignment_relationship_kind_check;
ALTER TABLE core.assignment_relationship
  ADD COLUMN relationship_type_code text,
  ADD COLUMN scope      jsonb,                         -- optional narrowing, e.g. { "projectIds": [...] }
  ADD COLUMN sys_period tstzrange NOT NULL DEFAULT tstzrange(now(), NULL);

-- -------------------------------------------------------------------------------------
-- Assignments: types, status, acting return (§4.2, §4.6)
-- -------------------------------------------------------------------------------------
ALTER TABLE core.assignment_version DROP CONSTRAINT IF EXISTS assignment_version_assignment_type_check;
ALTER TABLE core.assignment_version
  ADD CONSTRAINT assignment_version_assignment_type_check
  CHECK (assignment_type IN ('regular','term','casual_pool','acting','relief_pool','secondment_in','secondment_out','overlap','job_share'));
ALTER TABLE core.assignment_version
  ADD COLUMN status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('active','on_leave','suspended_for_acting','laid_off','ended')),
  ADD COLUMN end_reason text,
  ADD COLUMN returns_to_assignment_id uuid REFERENCES core.assignment;

-- Which assignment governs which domain (§4.3)
CREATE TABLE core.domain_governance (
  tenant_id    uuid NOT NULL,
  domain       text NOT NULL,   -- benefits_eligibility, benefit_class, vacation, review_owner, ...
  rule         text NOT NULL CHECK (rule IN ('primary_assignment','highest_fte','combined_same_employer','combined_same_agreement','per_assignment','governing_agreement','person')),
  scope        jsonb NOT NULL DEFAULT '{}'::jsonb,
  valid_period daterange NOT NULL,
  EXCLUDE USING gist (tenant_id WITH =, domain WITH =, valid_period WITH &&)
);

-- -------------------------------------------------------------------------------------
-- Rate components (§6.1)
-- -------------------------------------------------------------------------------------
ALTER TABLE core.pay_rate
  ADD COLUMN component text NOT NULL DEFAULT 'base'
    CHECK (component IN ('base','market_supplement','out_of_schedule','red_circle'));
CREATE UNIQUE INDEX pay_rate_one_per_component ON core.pay_rate (assignment_id, component);
ALTER TABLE core.pay_rate_version
  ADD COLUMN protection_rule  text CHECK (protection_rule IN ('freeze_until_range_catches_up','general_increases_for_months','lump_sum_increases')),
  ADD COLUMN protection_months smallint,
  ADD COLUMN notice_given_on  date;

-- -------------------------------------------------------------------------------------
-- Agreement library structure (§11.1)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.union_local (
  tenant_id     uuid NOT NULL,
  local_id      text NOT NULL,                       -- e.g. 'CUPE-38'
  union_name    text NOT NULL,
  local_number  text,
  PRIMARY KEY (tenant_id, local_id)
);
ALTER TABLE core.agreement
  ADD COLUMN local_id text,
  ADD COLUMN bargaining_employer_entity_id   uuid REFERENCES core.legal_entity,
  ADD COLUMN bargaining_employer_org_unit_id uuid REFERENCES core.org_unit,
  ADD COLUMN pattern_group text;                     -- agreements settled together (§11.5)
ALTER TABLE core.agreement
  ADD CONSTRAINT agreement_has_bargaining_employer
  CHECK (bargaining_employer_entity_id IS NOT NULL OR bargaining_employer_org_unit_id IS NOT NULL
         OR status = 'superseded') NOT VALID;      -- existing rows are backfilled, then VALIDATE

-- -------------------------------------------------------------------------------------
-- Funding and costing (§8)
-- -------------------------------------------------------------------------------------
CREATE TABLE finance.segment_definition (
  tenant_id     uuid NOT NULL,
  code          text NOT NULL,                       -- fund, cost_centre, program, project, activity, location, funder
  name_en       text NOT NULL,
  name_fr       text,
  position      smallint NOT NULL,                   -- order in the GL string
  required      boolean NOT NULL DEFAULT false,
  PRIMARY KEY (tenant_id, code)
);

CREATE TABLE finance.funding_source (
  tenant_id            uuid NOT NULL,
  funding_source_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 text NOT NULL,
  funder_name          text NOT NULL,
  funder_agreement_ref text,
  legal_entity_id      uuid NOT NULL REFERENCES core.legal_entity,
  calendar_id          uuid REFERENCES finance.calendar,   -- funder year
  valid_period         daterange NOT NULL,
  status               text NOT NULL CHECK (status IN ('draft','active','closing','closed')),
  eligible_categories  text[] NOT NULL,              -- salary, overtime, premiums, statutory_burden, benefits_employer, pension_employer, vacation_accrual, severance, retro, training
  admin_cap_percent    numeric(5,2),
  cap_behaviour        text NOT NULL DEFAULT 'spill_fallback' CHECK (cap_behaviour IN ('hard_stop','spill_next_line','spill_fallback','warn_only')),
  post_close_policy    text NOT NULL DEFAULT 'fallback' CHECK (post_close_policy IN ('successor','fallback','suspense')),
  successor_id         uuid REFERENCES finance.funding_source,
  fallback_segments    jsonb NOT NULL,
  accounting_basis     text NOT NULL DEFAULT 'accrual' CHECK (accounting_basis IN ('accrual','cash')),
  alert_days           smallint[] NOT NULL DEFAULT ARRAY[90,60,30]::smallint[],
  UNIQUE (tenant_id, code),
  CHECK (post_close_policy <> 'successor' OR successor_id IS NOT NULL)
);

CREATE TABLE finance.funding_budget (
  tenant_id          uuid NOT NULL,
  funding_source_id  uuid NOT NULL REFERENCES finance.funding_source,
  category           text NOT NULL,
  period_id          uuid NOT NULL REFERENCES finance.calendar_period,
  amount             numeric(16,2) NOT NULL CHECK (amount >= 0),
  PRIMARY KEY (funding_source_id, category, period_id)
);

-- Replaces direct use of core.position_funding: one distribution per position, assignment or org node
CREATE TABLE finance.cost_distribution (
  tenant_id        uuid NOT NULL,
  distribution_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type      text NOT NULL CHECK (target_type IN ('position','assignment','org_unit')),
  target_id        uuid NOT NULL,
  UNIQUE (target_type, target_id)
);
CREATE TABLE finance.cost_distribution_version (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  distribution_id  uuid NOT NULL REFERENCES finance.cost_distribution,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  -- [{ "seq": 1, "fundingSourceId": "…", "segments": { "fund": "…", "costCentre": "…" },
  --    "percent": 70.00 | "fixedPerPeriod": "1200.00", "categories": ["salary", …], "priority": 1 }]
  lines            jsonb NOT NULL CHECK (jsonb_typeof(lines) = 'array' AND jsonb_array_length(lines) >= 1),
  EXCLUDE USING gist (distribution_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

-- Intercompany recoveries for secondments, loans and shared services (§8.10)
CREATE TABLE finance.intercompany_arrangement (
  tenant_id           uuid NOT NULL,
  arrangement_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id       uuid NOT NULL REFERENCES core.assignment,
  paying_entity_id    uuid NOT NULL REFERENCES core.legal_entity,
  receiving_entity_id uuid NOT NULL REFERENCES core.legal_entity,
  recovery_basis      text NOT NULL CHECK (recovery_basis IN ('cost','cost_plus','fixed')),
  markup_percent      numeric(6,3),
  fixed_amount_per_period numeric(14,2),
  valid_period        daterange NOT NULL,
  change_set_id       uuid NOT NULL,
  CHECK (paying_entity_id <> receiving_entity_id)
);

-- Every pay result line distributed to the cent (§8.2, §8.8)
CREATE TABLE payroll.pay_result_line_distribution (
  tenant_id          uuid NOT NULL,
  line_id            bigint NOT NULL REFERENCES payroll.pay_result_line,
  seq                smallint NOT NULL,
  funding_source_id  uuid REFERENCES finance.funding_source,
  segments           jsonb NOT NULL,
  category           text NOT NULL,
  percent            numeric(7,4),
  amount             numeric(14,2) NOT NULL,
  source_rule        text NOT NULL CHECK (source_rule IN ('time_line','one_time','assignment','position','org_unit','fallback','suspense','spill')),
  work_period_id     uuid REFERENCES finance.calendar_period,
  funder_period_id   uuid REFERENCES finance.calendar_period,
  PRIMARY KEY (line_id, seq)
);

-- -------------------------------------------------------------------------------------
-- General ledger (§9)
-- -------------------------------------------------------------------------------------
CREATE TABLE finance.gl_mapping_version (
  tenant_id          uuid NOT NULL,
  mapping_version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id    uuid NOT NULL REFERENCES core.legal_entity,
  valid_period       daterange NOT NULL,
  apply_by           text NOT NULL DEFAULT 'work_date' CHECK (apply_by IN ('work_date','posting_date')),
  rules              jsonb NOT NULL,
  approved_by        uuid,
  approved_at        timestamptz,
  EXCLUDE USING gist (legal_entity_id WITH =, valid_period WITH &&)
);

ALTER TABLE payroll.gl_journal DROP CONSTRAINT IF EXISTS gl_journal_kind_check;
ALTER TABLE payroll.gl_journal
  ADD CONSTRAINT gl_journal_kind_check
  CHECK (kind IN ('cash','accrual','accrual_reversal','retro','prior_year_adjustment','opening_balance','intercompany_recovery','liability_adjustment'));
ALTER TABLE payroll.gl_journal ALTER COLUMN pay_run_id DROP NOT NULL;   -- accrual runs and opening balances have no pay run
ALTER TABLE payroll.gl_journal
  ADD COLUMN legal_entity_id     uuid REFERENCES core.legal_entity,
  ADD COLUMN source              text CHECK (source IN ('pay_run','accrual_run','liability_valuation','go_live','intercompany','manual')),
  ADD COLUMN work_period_id      uuid REFERENCES finance.calendar_period,
  ADD COLUMN posting_period_id   uuid REFERENCES finance.calendar_period,
  ADD COLUMN mapping_version_id  uuid REFERENCES finance.gl_mapping_version,
  ADD COLUMN reverses_journal_id uuid REFERENCES payroll.gl_journal;

-- -------------------------------------------------------------------------------------
-- Time and leave across assignments (§4.6, §7.4, §7.5, §5.2)
-- -------------------------------------------------------------------------------------
ALTER TABLE timeleave.time_line
  ADD COLUMN worked_position_id    uuid REFERENCES core.position,
  ADD COLUMN worked_classification text,
  ADD COLUMN averaging_cycle_end   date,
  ADD COLUMN provisional           boolean NOT NULL DEFAULT false;

ALTER TABLE timeleave.leave_ledger ADD COLUMN plan_code text;   -- agreement or policy leave plan
CREATE INDEX leave_ledger_by_plan ON timeleave.leave_ledger (tenant_id, employment_id, plan_code, leave_type_code, entry_date)
  WHERE upper_inf(sys_period);

ALTER TABLE timeleave.leave_request DROP CONSTRAINT IF EXISTS leave_request_status_check;
ALTER TABLE timeleave.leave_request
  ADD CONSTRAINT leave_request_status_check
  CHECK (status IN ('requested','approved','partially_approved','declined','cancelled','taken'));

CREATE TABLE timeleave.leave_request_component (
  tenant_id         uuid NOT NULL,
  leave_request_id  uuid NOT NULL REFERENCES timeleave.leave_request,
  assignment_id     uuid NOT NULL REFERENCES core.assignment,
  plan_code         text,
  hours             numeric(8,2) NOT NULL CHECK (hours >= 0),
  status            text NOT NULL CHECK (status IN ('requested','approved','declined','cancelled','taken')),
  approver_user     uuid,
  decided_at        timestamptz,
  PRIMARY KEY (leave_request_id, assignment_id)
);

-- -------------------------------------------------------------------------------------
-- Counters: seniority points, progression hours, conversion windows, relief days ... (§13)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.counter_ledger (
  tenant_id          uuid NOT NULL,
  entry_id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employment_id      uuid NOT NULL REFERENCES core.employment,
  assignment_id      uuid REFERENCES core.assignment,
  counter_code       text NOT NULL,
  scope              jsonb NOT NULL DEFAULT '{}'::jsonb,   -- { agreementId, seniorityType, classification, grouping }
  calendar_period_id uuid REFERENCES finance.calendar_period,
  entry_date         date NOT NULL,
  quantity           numeric(12,4) NOT NULL,
  kind               text NOT NULL CHECK (kind IN ('opening','accrual','adjustment','transfer_in','transfer_out','cap','reset','loss')),
  rule_source        text,
  sys_period         tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id      uuid
);
CREATE INDEX counter_ledger_lookup ON core.counter_ledger (tenant_id, employment_id, counter_code, entry_date)
  WHERE upper_inf(sys_period);

-- -------------------------------------------------------------------------------------
-- Mid-year go-live (§10)
-- -------------------------------------------------------------------------------------
CREATE TABLE payroll.external_pay_coverage (
  tenant_id          uuid NOT NULL,
  coverage_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id      uuid NOT NULL REFERENCES core.employment,
  payroll_account_id uuid NOT NULL REFERENCES core.payroll_account,
  covered_work       daterange NOT NULL,
  source             text NOT NULL,                  -- legacy system name
  reference          text,
  batch_id           uuid NOT NULL,
  EXCLUDE USING gist (employment_id WITH =, covered_work WITH &&)
);

CREATE TABLE payroll.migrated_pay_history (
  tenant_id            uuid NOT NULL,
  history_id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  person_id            uuid NOT NULL REFERENCES core.person,
  employment_id        uuid NOT NULL REFERENCES core.employment,
  payroll_account_id   uuid NOT NULL REFERENCES core.payroll_account,
  assignment_id        uuid REFERENCES core.assignment,
  pay_date             date NOT NULL,
  work_period          daterange NOT NULL,
  pay_code             text NOT NULL,
  hours                numeric(10,2),
  rate                 numeric(14,4),
  amount               numeric(14,2) NOT NULL,
  insurable_earnings   numeric(14,2),
  insurable_hours      numeric(10,2),
  pensionable_earnings numeric(14,2),
  classification       text,
  grid_step            smallint,
  agreement_id         text,
  segments             jsonb,
  source_system        text NOT NULL,
  batch_id             uuid NOT NULL
);
CREATE INDEX migrated_pay_history_lookup ON payroll.migrated_pay_history (tenant_id, employment_id, pay_date);

CREATE TABLE payroll.opening_balance (
  tenant_id          uuid NOT NULL,
  opening_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id    uuid NOT NULL REFERENCES core.legal_entity,
  kind               text NOT NULL CHECK (kind IN ('vacation_liability','banked_time_liability','sick_payout_liability','retro_reserve','payroll_clearing','funding_spent_to_date','legacy_accrual')),
  employment_id      uuid REFERENCES core.employment,
  funding_source_id  uuid REFERENCES finance.funding_source,
  category           text,
  as_of              date NOT NULL,
  quantity           numeric(12,4),
  amount             numeric(16,2) NOT NULL,
  gl_account         text,
  batch_id           uuid NOT NULL
);

-- -------------------------------------------------------------------------------------
-- Row-level security on every new tenant table (same policy as 0001)
-- -------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS s, c.relname AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND NOT c.relrowsecurity
      AND n.nspname IN ('core','finance','payroll','timeleave')
      AND EXISTS (SELECT 1 FROM pg_attribute a
                  WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$,
                   r.s, r.t);
  END LOOP;
END $$;

-- Grants for finance (schema is created here; 0002 runs before this file).
ALTER ROLE cando_app SET search_path = platform, core, payroll, timeleave, recruit, comp, benefits, talent, offboard, compliance, ref, finance, extensions, public;

GRANT USAGE ON SCHEMA finance TO cando_app, cando_sealer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA finance TO cando_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA finance TO cando_app;

DO $$
BEGIN
  EXECUTE 'REVOKE ALL ON SCHEMA finance FROM anon, authenticated';
  EXECUTE 'REVOKE ALL ON ALL TABLES IN SCHEMA finance FROM anon, authenticated';
  EXECUTE 'REVOKE ALL ON ALL SEQUENCES IN SCHEMA finance FROM anon, authenticated';
  EXECUTE 'REVOKE ALL ON ALL FUNCTIONS IN SCHEMA finance FROM anon, authenticated';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA finance REVOKE ALL ON TABLES FROM anon, authenticated';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA finance REVOKE ALL ON SEQUENCES FROM anon, authenticated';
  EXECUTE 'ALTER DEFAULT PRIVILEGES IN SCHEMA finance REVOKE ALL ON FUNCTIONS FROM anon, authenticated';
END $$;
