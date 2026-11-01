-- =====================================================================================
-- CanDo HRIS · migration 0008 · values as data, no silent fallbacks, any language (docs/22)
--
-- Every number, list and default an organization could want different now lives in the settings catalogue
-- or in the organization's own lists; legal values come from the rules files; the database fills a missing
-- value only from a registered setting, and otherwise stops with a named error. Languages are data.
--
--   0. Settings: strict lookup, decision status, limits, required keys, number types
--   1. New settings: defaults carried over from earlier migrations and specifications
--   2. Business column defaults come from settings (platform.column_default)
--   3. Organization lists mapped to fixed categories (core.list_value) replace fixed value lists
--   4. Languages as data: ref.language, ref.locale, platform.tenant_language, platform.translation
--   5. Limits from settings: assignment FTE, override reasons, support access grants
--   6. Countries and postal code formats (ref.country); data regions (ref.data_region)
--   7. Legal values come from the rules: EI employer rate, overtime rate basis, public wage statistics
--   8. Fixes to 0006 and 0007: approvals, employee numbers, relationship purposes, titles, review and gap settings
--   9. Starter data for every organization, new and existing
--  10. Row-level security on the new tenant tables
--
-- Applied after 0007. Existing data is migrated here: organizations keep their languages, get the starter lists,
-- and keep the behaviour 0007 gave their relationship types until they review them (§8.3).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 0. Settings: strict lookup, decision status, limits, required keys
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.setting_definition DROP CONSTRAINT IF EXISTS setting_definition_value_type_check;
ALTER TABLE platform.setting_definition
  ADD CONSTRAINT setting_definition_value_type_check
    CHECK (value_type IN ('boolean','integer','number','text','text_array','integer_array','json')),
  ADD COLUMN decision_status text,
  ADD COLUMN min_value       numeric,
  ADD COLUMN max_value       numeric,
  ADD COLUMN required_keys   text[];
UPDATE platform.setting_definition SET decision_status = 'decided';      -- every 0007 setting came from the Core HR review
UPDATE platform.setting_definition SET required_keys = ARRAY(SELECT jsonb_object_keys(default_value) ORDER BY 1)
  WHERE value_type = 'json';
ALTER TABLE platform.setting_definition
  ALTER COLUMN decision_status SET NOT NULL,
  ALTER COLUMN default_value DROP NOT NULL,
  ADD CONSTRAINT setting_definition_decision_status_check CHECK (decision_status IN ('decided','spec_default','pending')),
  ADD CONSTRAINT setting_definition_pending_has_no_default CHECK ((default_value IS NULL) = (decision_status = 'pending')),
  ADD CONSTRAINT setting_definition_limits_numeric CHECK ((min_value IS NULL AND max_value IS NULL) OR value_type IN ('integer','number')),
  ADD CONSTRAINT setting_definition_keys_json CHECK (required_keys IS NULL OR value_type = 'json');
COMMENT ON COLUMN platform.setting_definition.decision_status IS
  'decided: the product owner chose it in a module review; spec_default: written in the specifications and confirmed in that module''s review; pending: no CanDo default, each organization must choose it at setup (platform.setting raises SETTING_NOT_SET).';

-- One check for a value against its definition, used by tenant settings and by CanDo's own defaults
CREATE FUNCTION platform.setting_value_problem(d platform.setting_definition, v jsonb) RETURNS text
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t text := jsonb_typeof(v); ok boolean;
BEGIN
  ok := CASE d.value_type
          WHEN 'boolean'       THEN t = 'boolean'
          WHEN 'integer'       THEN t = 'number' AND (v #>> '{}') ~ '^-?[0-9]+$'
          WHEN 'number'        THEN t = 'number'
          WHEN 'text'          THEN t = 'string'
          WHEN 'text_array'    THEN t = 'array' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v) e WHERE jsonb_typeof(e) <> 'string')
          WHEN 'integer_array' THEN t = 'array' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v) e
                                                                 WHERE jsonb_typeof(e) <> 'number' OR (e #>> '{}') !~ '^-?[0-9]+$')
          WHEN 'json'          THEN t = 'object'
        END;
  IF ok IS NOT TRUE THEN RETURN format('SETTING_VALUE_TYPE: %s takes a %s value', d.setting_key, d.value_type); END IF;
  IF d.allowed_values IS NOT NULL AND NOT (d.allowed_values @> jsonb_build_array(v)) THEN
    RETURN format('SETTING_VALUE_NOT_ALLOWED: %s must be one of %s', d.setting_key, d.allowed_values);
  END IF;
  IF d.min_value IS NOT NULL AND (v #>> '{}')::numeric < d.min_value THEN
    RETURN format('SETTING_BELOW_MINIMUM: %s cannot be below %s', d.setting_key, d.min_value);
  END IF;
  IF d.max_value IS NOT NULL AND (v #>> '{}')::numeric > d.max_value THEN
    RETURN format('SETTING_ABOVE_MAXIMUM: %s cannot be above %s', d.setting_key, d.max_value);
  END IF;
  IF d.required_keys IS NOT NULL AND NOT (v ?& d.required_keys) THEN
    RETURN format('SETTING_KEYS_MISSING: %s needs the keys %s', d.setting_key, d.required_keys);
  END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION platform.check_tenant_setting() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d platform.setting_definition; problem text;
BEGIN
  SELECT * INTO d FROM platform.setting_definition WHERE setting_key = NEW.setting_key;
  IF d.locked THEN
    RAISE EXCEPTION 'SETTING_LOCKED: % is a legal floor or safety rule and cannot be changed', NEW.setting_key
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT (NEW.scope_type = ANY (d.scopes)) THEN
    RAISE EXCEPTION 'SETTING_SCOPE_NOT_ALLOWED: % cannot be set per %', NEW.setting_key, NEW.scope_type USING ERRCODE = 'check_violation';
  END IF;
  problem := platform.setting_value_problem(d, NEW.value);
  IF problem IS NOT NULL THEN RAISE EXCEPTION '%', problem USING ERRCODE = 'check_violation'; END IF;
  RETURN NEW;
END $$;

-- CanDo's own defaults must pass the same checks
CREATE FUNCTION platform.check_setting_definition() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE problem text;
BEGIN
  IF NEW.default_value IS NOT NULL THEN
    problem := platform.setting_value_problem(NEW, NEW.default_value);
    IF problem IS NOT NULL THEN RAISE EXCEPTION 'SETTING_DEFAULT_INVALID: %', problem USING ERRCODE = 'check_violation'; END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER setting_definition_check BEFORE INSERT OR UPDATE ON platform.setting_definition
  FOR EACH ROW EXECUTE FUNCTION platform.check_setting_definition();

-- The value in force: legal entity override, then organization override, then CanDo's registered default.
-- An unknown key or a setting with no value anywhere is an error, never a silent fallback.
CREATE OR REPLACE FUNCTION platform.setting(p_tenant uuid, p_key text, p_as_of date DEFAULT current_date, p_legal_entity uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE d platform.setting_definition; v jsonb;
BEGIN
  SELECT * INTO d FROM platform.setting_definition WHERE setting_key = p_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'SETTING_UNKNOWN: % is not in platform.setting_definition', p_key USING ERRCODE = 'check_violation';
  END IF;
  IF d.locked THEN RETURN d.default_value; END IF;
  IF p_legal_entity IS NOT NULL THEN
    SELECT s.value INTO v FROM platform.tenant_setting s
     WHERE s.tenant_id = p_tenant AND s.setting_key = p_key AND s.scope_type = 'legal_entity' AND s.scope_id = p_legal_entity
       AND s.valid_period @> p_as_of AND upper_inf(s.sys_period);
  END IF;
  IF v IS NULL THEN
    SELECT s.value INTO v FROM platform.tenant_setting s
     WHERE s.tenant_id = p_tenant AND s.setting_key = p_key AND s.scope_type = 'tenant'
       AND s.valid_period @> p_as_of AND upper_inf(s.sys_period);
  END IF;
  IF v IS NULL THEN v := d.default_value; END IF;
  IF v IS NULL THEN
    RAISE EXCEPTION 'SETTING_NOT_SET: % has no CanDo default; the organization chooses it at setup (%)', p_key, d.decision_ref
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN v;
END $$;

CREATE FUNCTION platform.setting_text(p_tenant uuid, p_key text, p_as_of date DEFAULT current_date, p_legal_entity uuid DEFAULT NULL)
RETURNS text LANGUAGE sql STABLE AS $$ SELECT platform.setting(p_tenant, p_key, p_as_of, p_legal_entity) #>> '{}' $$;
CREATE FUNCTION platform.setting_number(p_tenant uuid, p_key text, p_as_of date DEFAULT current_date, p_legal_entity uuid DEFAULT NULL)
RETURNS numeric LANGUAGE sql STABLE AS $$ SELECT (platform.setting(p_tenant, p_key, p_as_of, p_legal_entity) #>> '{}')::numeric $$;

-- -------------------------------------------------------------------------------------
-- 1. New settings. Each default is the value an earlier migration or specification already used;
--    decision_status says whether the product owner has confirmed it (docs/22 §2).
-- -------------------------------------------------------------------------------------
UPDATE platform.setting_definition
   SET default_value = default_value || '{"olderHrApprovals": 2}'::jsonb,
       required_keys = ARRAY['hrApprovals','olderHrApprovals','payrollApproval','secondHrApprovalOlderThan'],
       description_en = 'Approvals for a change whose effective date reaches a finalized pay period: hrApprovals HR approvals and, when payrollApproval is true, one payroll approval; olderHrApprovals HR approvals from different people when the effective date is more than secondHrApprovalOlderThan before the request.'
 WHERE setting_key = 'retro.backdate_approval';
UPDATE platform.setting_definition
   SET description_en = 'Order of employment type categories used to work out an employment''s status from its positions: the first category held by any position that has not ended. Every category of the organization''s employment types must appear.'
 WHERE setting_key = 'employment.status_precedence';

INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value) VALUES
 ('languages.starter', 'languages', 'json', NULL,
  '{"languages":[{"code":"en","locale":"en-CA","main":true,"forData":"required"}]}', ARRAY['tenant'], false,
  'Language a new organization types its own words in (its main language): English unless it chooses French at setup. An organization with a work location in Quebec has French (docs/22 §4.2).',
  'Owner, 25 Oct 2026 (docs/16 Q44); requirements/00; docs/22 §4', 'decided', NULL, NULL),
 ('people.default_person_type', 'people', 'text', NULL, '"employee"', ARRAY['tenant'], false,
  'Person type of a new person record when the transaction does not name one. Must be a code on the organization''s person type list.',
  'cando_schema.sql (0001); docs/22 §3', 'spec_default', NULL, NULL),
 ('locations.default_country', 'locations', 'text', NULL, '"CA"', ARRAY['tenant','legal_entity'], false,
  'Country of a new work location when none is given. Postal codes are checked against the country''s format in ref.country.',
  'cando_schema.sql (0001); docs/22 §6', 'spec_default', NULL, NULL),
 ('positions.max_assignment_fte', 'positions', 'number', NULL, '1.5', ARRAY['tenant','legal_entity'], false,
  'Highest FTE a single assignment may have.', 'cando_schema.sql (0001)', 'spec_default', 0.01, NULL),
 ('approvals.override_reason_min_length', 'approvals', 'integer', NULL, '10', ARRAY['tenant'], false,
  'Shortest written reason accepted for a position control override, in characters.', 'docs/21 §5.2; 0007 §6', 'spec_default', 1, NULL),
 ('approvals.multi_manager_mode', 'approvals', 'text', '["by_coverage","all","any"]', '"by_coverage"', ARRAY['tenant','legal_entity'], false,
  'Default routing for a position with several managers: each approves the days and hours they cover, all must approve, or any one decides. A position can set its own (core.approval_policy).',
  'docs/20 §2', 'spec_default', NULL, NULL),
 ('approvals.multi_manager_overlap', 'approvals', 'text', '["all","any"]', '"all"', ARRAY['tenant','legal_entity'], false,
  'When several managers cover the same minutes: all of them approve, or any one decides.', 'docs/20 §2', 'spec_default', NULL, NULL),
 ('approvals.uncovered_time', 'approvals', 'text', '["line","hr"]', '"line"', ARRAY['tenant','legal_entity'], false,
  'Minutes that no manager''s coverage includes go to the line manager, or to HR.', 'docs/20 §2', 'spec_default', NULL, NULL),
 ('approvals.coverage_capabilities', 'approvals', 'text_array', NULL, '["leave","time","overtime"]', ARRAY['tenant'], false,
  'What a manager''s approval coverage includes when the coverage record does not list it.', 'docs/20 §2', 'spec_default', NULL, NULL),
 ('support.max_grant_days', 'platform', 'integer', NULL, '7', ARRAY['tenant'], false,
  'Longest support access grant, in days. CanDo''s security ceiling is 7; an organization can set fewer.',
  'docs/21 §9.3 (R7.3); 0007 §15', 'spec_default', 1, 7),
 ('reviews.min_section_days', 'reviews', 'integer', NULL, '60', ARRAY['tenant'], false,
  'A position held fewer days in the cycle gives comments but no weight in the overall rating.', 'docs/20 §5.3; requirements/07', 'spec_default', 0, NULL),
 ('reviews.overall_method', 'reviews', 'text', '["fte_weighted","primary_manager","none"]', '"fte_weighted"', ARRAY['tenant'], false,
  'How the overall rating is set for a person in several positions.', 'docs/20 §5.3', 'spec_default', NULL, NULL),
 ('reviews.overall_rounding_step', 'reviews', 'number', NULL, '1', ARRAY['tenant'], false,
  'Step the overall rating is rounded to, for example 0.5 on a half-point scale.', 'docs/20 §5.3', 'spec_default', 0.01, NULL),
 ('competencies.gap_sources', 'competencies', 'text_array', NULL, '["calibrated","assessment","manager","peer_360","evidence"]', ARRAY['tenant'], false,
  'Assessment sources counted when CanDo works out a competency gap. Self-assessments are shown beside the gap and never counted.',
  'docs/19 §4; docs/20 §5.4', 'spec_default', NULL, NULL),
 ('competencies.default_criticality', 'competencies', 'text', '["critical","important","useful"]', '"important"', ARRAY['tenant'], false,
  'Criticality of a new competency target when none is given.', 'docs/19 §4; 0005', 'spec_default', NULL, NULL),
 ('comp.merit_rating_source', 'compensation', 'text', '["section","overall"]', '"section"', ARRAY['tenant'], false,
  'Rating a merit increase reads for a person in several positions: the section of the position being increased, or the overall rating.',
  'docs/20 §5.5', 'spec_default', NULL, NULL),
 ('market.default_statistic', 'compensation', 'text', '["mean","p10","p25","p50","p75","p90"]', '"p50"', ARRAY['tenant'], false,
  'Market statistic a new market definition targets.', 'docs/19 §7; 0005', 'spec_default', NULL, NULL),
 ('market.default_statistics', 'compensation', 'text_array', NULL, '["p25","p50","p75"]', ARRAY['tenant'], false,
  'Statistics a new market definition reports.', 'docs/19 §7; 0005', 'spec_default', NULL, NULL),
 ('market.default_minimum', 'compensation', 'json', NULL, '{"nOrgs":4}', ARRAY['tenant'], false,
  'Fewest organizations (and, if set, incumbents) behind a survey value before a new market definition uses it.', 'docs/19 §7.2; 0005', 'spec_default', NULL, NULL),
 ('market.default_min_sources', 'compensation', 'integer', NULL, '1', ARRAY['tenant'], false,
  'Fewest usable sources before a job is priced.', 'docs/19 §7; 0005', 'spec_default', 1, NULL),
 ('market.default_ageing', 'compensation', 'json', NULL, '{"method":"none","annualRate":"0"}', ARRAY['tenant'], false,
  'How a new market definition ages survey data to a common date.', 'docs/19 §7.3; 0005', 'spec_default', NULL, NULL),
 ('market.line_outlier_pct', 'compensation', 'number', NULL, '15', ARRAY['tenant'], false,
  'A benchmark job more than this per cent above or below the market line is flagged as an outlier for review; it is never removed automatically.',
  'docs/19 §7.6', 'spec_default', 0, 100),
 ('pay.default_structure_basis', 'compensation', 'text', '["annual","hourly"]', '"annual"', ARRAY['tenant'], false,
  'Basis of a new pay structure or salary range when none is given.', 'docs/19 §7.7; 0005', 'spec_default', NULL, NULL),
 ('pay.structure_rounding', 'compensation', 'integer', NULL, '100', ARRAY['tenant'], false,
  'Unit that grade minimums, midpoints and maximums are rounded to.', 'docs/19 §7.7; 0005', 'spec_default', 1, NULL),
 ('money.currency', 'finance', 'text', NULL, '"CAD"', ARRAY['tenant','legal_entity'], false,
  'Currency of new money records (pay structures, survey editions) when none is given.', 'cando_schema.sql; 0005', 'spec_default', NULL, NULL),
 ('surveys.duties_match_threshold', 'compensation', 'integer', NULL, '70', ARRAY['tenant'], false,
  'Share of duties (per cent) a job must share with a survey job to count as a match.', 'docs/19 §6; 0005', 'spec_default', 0, 100),
 ('surveys.default_weightings', 'compensation', 'text_array', NULL, '["organization"]', ARRAY['tenant'], false,
  'Weightings a new survey edition publishes when none are given.', 'docs/19 §6; 0005', 'spec_default', NULL, NULL),
 ('job_evaluation.default_method', 'compensation', 'text', '["point_factor","classification","ranking","market_slotting"]', '"point_factor"', ARRAY['tenant'], false,
  'Method of a new job evaluation plan.', 'docs/19 §5; 0005', 'spec_default', NULL, NULL),
 ('job_evaluation.default_purposes', 'compensation', 'text_array', NULL, '["grading"]', ARRAY['tenant'], false,
  'Purposes of a new job evaluation plan.', 'docs/19 §5; 0005', 'spec_default', NULL, NULL),
 ('job_evaluation.evidence_combine', 'compensation', 'text', '["max","min"]', '"max"', ARRAY['tenant'], false,
  'How several competency targets combine into one evidence level for a factor.', 'docs/19 §5; 0005', 'spec_default', NULL, NULL),
 ('codes.default_code_case', 'codes', 'text', '["as_entered","upper"]', '"as_entered"', ARRAY['tenant'], false,
  'Letter case of codes in a new code scheme.', 'docs/18 §3; 0004', 'spec_default', NULL, NULL),
 ('codes.default_inherit', 'codes', 'text', '["none","down"]', '"down"', ARRAY['tenant'], false,
  'Whether codes in a new scheme pass down from job to position to incumbent.', 'docs/18 §4; 0004', 'spec_default', NULL, NULL),
 ('codes.default_ordering', 'codes', 'text', '["natural_code","alpha_code","alpha_title","custom_rank","hierarchy"]', '"natural_code"', ARRAY['tenant'], false,
  'Sort order of a new code scheme''s values.', 'docs/18 §3; 0004', 'spec_default', NULL, NULL),
 ('codes.default_structure', 'codes', 'text', '["flat","hierarchical"]', '"flat"', ARRAY['tenant'], false,
  'Structure of a new code scheme.', 'docs/18 §3; 0004', 'spec_default', NULL, NULL),
 ('codes.default_values_mode', 'codes', 'text', '["list","free","list_or_free"]', '"list"', ARRAY['tenant'], false,
  'Whether a new code scheme takes values from its list, free text, or both.', 'docs/18 §3; 0004', 'spec_default', NULL, NULL),
 ('codes.default_values_per_target', 'codes', 'text', '["one","many"]', '"one"', ARRAY['tenant'], false,
  'How many values of a new code scheme a target can hold at once.', 'docs/18 §3; 0004', 'spec_default', NULL, NULL),
 ('codes.default_uniqueness', 'codes', 'text', '["none","unique"]', '"none"', ARRAY['tenant'], false,
  'Whether a value of a new code scheme may be held by only one target at a time.', 'docs/18 §3; 0004', 'spec_default', NULL, NULL),
 ('codes.default_rule_severity', 'codes', 'text', '["warning","block"]', '"warning"', ARRAY['tenant'], false,
  'Severity of a new code scheme rule.', 'docs/18 §5; 0004', 'spec_default', NULL, NULL),
 ('lists.end_reason_applies_to', 'lists', 'text', '["assignment","employment","both"]', '"both"', ARRAY['tenant'], false,
  'What a new end reason can end when not stated.', 'docs/20 §6; 0006', 'spec_default', NULL, NULL),
 ('requirements.default_verification', 'requirements', 'text',
  '["self_declared","document","credential_record","background_check","assessment","none"]', '"document"', ARRAY['tenant'], false,
  'How a new work requirement is verified when not stated.', 'docs/18 §6; 0004', 'spec_default', NULL, NULL),
 ('benefits.default_eligibility_scope', 'benefits', 'text', '["employer","agreement","assignment"]', '"employer"', ARRAY['tenant'], false,
  'Eligibility scope of a new benefit plan when not stated.', 'docs/20 §6.1; 0006', 'spec_default', NULL, NULL),
 ('funding.default_cap_behaviour', 'finance', 'text', '["hard_stop","spill_next_line","spill_fallback","warn_only"]', '"spill_fallback"', ARRAY['tenant'], false,
  'What a new funding source does when a cost is over its cap or not eligible for it.', 'docs/17 §8.3; docs/16 Q12', 'spec_default', NULL, NULL),
 ('funding.default_post_close_policy', 'finance', 'text', '["successor","fallback","suspense"]', '"fallback"', ARRAY['tenant'], false,
  'Where retro and corrections go when a new funding source is closed.', 'docs/17 §8.7', 'spec_default', NULL, NULL),
 ('funding.default_accounting_basis', 'finance', 'text', '["accrual","cash"]', '"accrual"', ARRAY['tenant'], false,
  'Accounting basis of a new funding source.', 'docs/17 §8.5', 'spec_default', NULL, NULL),
 ('funding.default_alert_days', 'finance', 'integer_array', NULL, '[90,60,30]', ARRAY['tenant'], false,
  'Days before a new funding source ends that alerts go to the position owner and finance.', 'docs/17 §8.6; docs/16 Q12', 'spec_default', NULL, NULL),
 ('finance.fiscal_year_start_month', 'finance', 'integer', NULL, '1', ARRAY['tenant','legal_entity'], false,
  'First month of the fiscal year of a new legal entity version when not stated.', 'cando_schema.sql (0001)', 'spec_default', 1, 12),
 ('gl.default_apply_by', 'finance', 'text', '["work_date","posting_date"]', '"work_date"', ARRAY['tenant'], false,
  'Which date selects a new GL mapping version.', 'docs/17 §9', 'spec_default', NULL, NULL),
 ('payroll.one_time_allocation', 'payroll', 'text', '["assignment","earnings_share"]', '"earnings_share"', ARRAY['tenant','legal_entity'], false,
  'How a one-time payment that names no position is shared: by the period''s earnings in each position, or it must name one.',
  'docs/20 §4.3', 'spec_default', NULL, NULL),
 ('payroll.default_proration_method', 'payroll', 'text', '["calendar_days","working_days","scheduled_hours"]', '"working_days"', ARRAY['tenant','legal_entity'], false,
  'How salary is prorated in a new pay group when not stated.', 'docs/06; cando_schema.sql (0001)', 'spec_default', NULL, NULL),
 ('pay_items.default_cost_target', 'payroll', 'text', '["assignment","explicit"]', '"assignment"', ARRAY['tenant'], false,
  'Where a new pay item is costed when not stated.', 'docs/20 §4; 0006', 'spec_default', NULL, NULL),
 ('tenant.default_residency', 'platform', 'text', NULL, '"CA"', ARRAY['tenant'], false,
  'Data region of a new organization (ref.data_region).', 'docs/02; cando_schema.sql (0001)', 'spec_default', NULL, NULL),
 ('tenant.default_data_isolation', 'platform', 'text', '["shared","dedicated"]', '"shared"', ARRAY['tenant'], false,
  'Database arrangement of a new organization. A First Nation chooses at setup between the shared platform with OCAP® controls and its own database.',
  'docs/21 §9.3 (R7.3)', 'decided', NULL, NULL),
 ('tenant.default_modules', 'platform', 'text_array', NULL, '["core"]', ARRAY['tenant'], false,
  'Modules a new organization starts with.', 'cando_schema.sql (0001)', 'spec_default', NULL, NULL);
UPDATE platform.setting_definition SET required_keys = ARRAY(SELECT jsonb_object_keys(default_value) ORDER BY 1)
  WHERE value_type = 'json' AND required_keys IS NULL;

-- -------------------------------------------------------------------------------------
-- 2. Business column defaults come from settings. A column listed here has no DEFAULT in the table;
--    when an insert leaves it empty, the trigger fills it from the organization's setting (or its main
--    language or locale). Every other empty value fails its NOT NULL or check. (docs/22 §3)
-- -------------------------------------------------------------------------------------
CREATE TABLE platform.column_default (
  table_schema text NOT NULL,
  table_name   text NOT NULL,
  column_name  text NOT NULL,
  source       text NOT NULL CHECK (source IN ('setting','tenant_main_language','tenant_main_locale')),
  setting_key  text REFERENCES platform.setting_definition,
  PRIMARY KEY (table_schema, table_name, column_name),
  CHECK ((source = 'setting') = (setting_key IS NOT NULL))
);

CREATE FUNCTION platform.main_language(p_tenant uuid) RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE v text;
BEGIN
  SELECT lang INTO v FROM platform.tenant_language WHERE tenant_id = p_tenant AND is_main;
  IF v IS NULL THEN
    RAISE EXCEPTION 'MAIN_LANGUAGE_NOT_SET: organization % has no main language', p_tenant USING ERRCODE = 'check_violation';
  END IF;
  RETURN v;
END $$;

CREATE FUNCTION platform.main_locale(p_tenant uuid) RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE v text;
BEGIN
  SELECT locale INTO v FROM platform.tenant_language WHERE tenant_id = p_tenant AND is_main;
  IF v IS NULL THEN
    RAISE EXCEPTION 'MAIN_LANGUAGE_NOT_SET: organization % has no main language', p_tenant USING ERRCODE = 'check_violation';
  END IF;
  RETURN v;
END $$;

CREATE FUNCTION platform.fill_from_settings() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE r record; j jsonb := to_jsonb(NEW); v jsonb; t uuid; le uuid; filled boolean := false;
BEGIN
  t := (j ->> 'tenant_id')::uuid;
  IF j ? 'legal_entity_id' THEN le := (j ->> 'legal_entity_id')::uuid; END IF;
  FOR r IN SELECT d.column_name, d.source, d.setting_key FROM platform.column_default d
            WHERE d.table_schema = TG_TABLE_SCHEMA AND d.table_name = TG_TABLE_NAME LOOP
    IF jsonb_typeof(j -> r.column_name) IS NULL OR jsonb_typeof(j -> r.column_name) = 'null' THEN
      v := CASE r.source
             WHEN 'setting'              THEN platform.setting(t, r.setting_key, current_date, le)
             WHEN 'tenant_main_language' THEN to_jsonb(platform.main_language(t))
             WHEN 'tenant_main_locale'   THEN to_jsonb(platform.main_locale(t))
           END;
      j := jsonb_set(j, ARRAY[r.column_name], v);
      filled := true;
    END IF;
  END LOOP;
  IF filled THEN NEW := jsonb_populate_record(NEW, j); END IF;
  RETURN NEW;
END $$;

-- Registered defaults: (schema, table, column, setting) ; the table's DEFAULT is dropped and the trigger added
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('benefits','plan','eligibility_scope','benefits.default_eligibility_scope'),
      ('comp','cycle','merit_rating_source','comp.merit_rating_source'),
      ('comp','je_evidence_link','combine','job_evaluation.evidence_combine'),
      ('comp','je_plan','method','job_evaluation.default_method'),
      ('comp','je_plan','purposes','job_evaluation.default_purposes'),
      ('comp','market_definition','ageing','market.default_ageing'),
      ('comp','market_definition','min_sources','market.default_min_sources'),
      ('comp','market_definition','minimum','market.default_minimum'),
      ('comp','market_definition','statistic','market.default_statistic'),
      ('comp','market_definition','statistics','market.default_statistics'),
      ('comp','pay_structure','basis','pay.default_structure_basis'),
      ('comp','pay_structure','currency','money.currency'),
      ('comp','pay_structure_version','rounding','pay.structure_rounding'),
      ('comp','salary_range','basis','pay.default_structure_basis'),
      ('comp','survey','duties_match_threshold','surveys.duties_match_threshold'),
      ('comp','survey_edition','currency','money.currency'),
      ('comp','survey_edition','weightings','surveys.default_weightings'),
      ('core','approval_coverage','capabilities','approvals.coverage_capabilities'),
      ('core','approval_policy','mode','approvals.multi_manager_mode'),
      ('core','approval_policy','overlap','approvals.multi_manager_overlap'),
      ('core','approval_policy','uncovered','approvals.uncovered_time'),
      ('core','assignment_pay_item','cost_target','pay_items.default_cost_target'),
      ('core','code_scheme','code_case','codes.default_code_case'),
      ('core','code_scheme','inherit','codes.default_inherit'),
      ('core','code_scheme','ordering','codes.default_ordering'),
      ('core','code_scheme','structure','codes.default_structure'),
      ('core','code_scheme','values_mode','codes.default_values_mode'),
      ('core','code_scheme','values_per_target','codes.default_values_per_target'),
      ('core','code_scheme','uniqueness','codes.default_uniqueness'),
      ('core','code_scheme_rule','severity','codes.default_rule_severity'),
      ('core','end_reason','applies_to','lists.end_reason_applies_to'),
      ('core','legal_entity_version','fiscal_year_start_month','finance.fiscal_year_start_month'),
      ('core','person','person_type','people.default_person_type'),
      ('core','work_requirement','verification','requirements.default_verification'),
      ('finance','funding_source','accounting_basis','funding.default_accounting_basis'),
      ('finance','funding_source','alert_days','funding.default_alert_days'),
      ('finance','funding_source','cap_behaviour','funding.default_cap_behaviour'),
      ('finance','funding_source','post_close_policy','funding.default_post_close_policy'),
      ('finance','gl_mapping_version','apply_by','gl.default_apply_by'),
      ('payroll','one_time_item','allocation','payroll.one_time_allocation'),
      ('payroll','pay_group','proration_method','payroll.default_proration_method'),
      ('platform','tenant','residency','tenant.default_residency'),
      ('platform','tenant','data_isolation','tenant.default_data_isolation'),
      ('platform','tenant','modules_enabled','tenant.default_modules'),
      ('talent','competency_target','criticality','competencies.default_criticality'),
      ('talent','review','min_section_days','reviews.min_section_days'),
      ('talent','review','overall_method','reviews.overall_method')
    ) AS x(s, t, c, k)
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I DROP DEFAULT', r.s, r.t, r.c);
    INSERT INTO platform.column_default (table_schema, table_name, column_name, source, setting_key) VALUES (r.s, r.t, r.c, 'setting', r.k);
  END LOOP;
END $$;

-- Columns with legal or pay effect keep no default at all: whoever creates the row states the value
-- (a leave type's pay, job protection, ROE effect and whether its reason is restricted; a shift's unpaid break;
-- whether a posting is for an existing vacancy and uses AI screening; whether a benefit change offers conversion;
-- whether a pay code accrues leave; a pay result's tax; a survey licence's limit on derived results; whether an
-- employer is a First Nation government). A default stays only where it is technical, the first state of a workflow,
-- the law applying until an exemption is recorded, the most protective safety value, or a feature off until switched
-- on; docs/22 §3 lists each one.
ALTER TABLE timeleave.leave_type ALTER COLUMN paid_percent DROP DEFAULT,
                                 ALTER COLUMN job_protected DROP DEFAULT,
                                 ALTER COLUMN roe_trigger DROP DEFAULT,
                                 ALTER COLUMN reason_restricted DROP DEFAULT;
ALTER TABLE timeleave.shift ALTER COLUMN break_minutes DROP DEFAULT;
ALTER TABLE recruit.requisition ALTER COLUMN vacancy_exists DROP DEFAULT,
                                ALTER COLUMN uses_ai_screening DROP DEFAULT;
ALTER TABLE benefits.change_rule ALTER COLUMN offer_conversion DROP DEFAULT;
ALTER TABLE benefits.change_decision ALTER COLUMN offer_conversion DROP DEFAULT;
ALTER TABLE payroll.pay_code ALTER COLUMN accrues_leave DROP DEFAULT;
ALTER TABLE payroll.pay_result ALTER COLUMN territorial_payroll_tax DROP DEFAULT;
ALTER TABLE comp.survey ALTER COLUMN derived_results_restricted DROP DEFAULT;
ALTER TABLE core.legal_entity_version ALTER COLUMN first_nation_government DROP DEFAULT;

-- -------------------------------------------------------------------------------------
-- 3. Organization lists mapped to fixed categories. Each organization names and orders its own values;
--    CanDo's logic reads only the category. Starter values are copied when an organization is created.
-- -------------------------------------------------------------------------------------
CREATE TABLE ref.list_definition (
  list_code    text PRIMARY KEY,
  name_en      text NOT NULL,
  name_fr      text,
  categories   text[] NOT NULL CHECK (cardinality(categories) >= 1),
  decision_ref text NOT NULL
);

CREATE TABLE ref.list_starter (
  list_code  text NOT NULL REFERENCES ref.list_definition,
  code       text NOT NULL,
  category   text NOT NULL,
  rank       smallint NOT NULL,
  name_en    text NOT NULL,
  name_fr    text,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (list_code, code)
);

CREATE TABLE core.list_value (
  tenant_id  uuid NOT NULL REFERENCES platform.tenant,
  list_code  text NOT NULL REFERENCES ref.list_definition,
  code       text NOT NULL,
  category   text NOT NULL,
  rank       smallint NOT NULL,
  name_en    text NOT NULL,                              -- registered as translatable in §9: then text is required in the main language, whichever it is
  name_fr    text,
  attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
  status     text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  PRIMARY KEY (tenant_id, list_code, code),
  CHECK (code ~ '^[A-Za-z0-9_.-]{1,40}$')
);
COMMENT ON TABLE core.list_value IS
  'The organization''s own values for each list in ref.list_definition, each mapped to a fixed category. A retired value stays valid on existing records; screens and imports offer only active values (docs/22 §3).';

CREATE FUNCTION core.check_list_category() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cats text[];
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'LIST_VALUE_RETIRE_INSTEAD: retire %.% instead of deleting it', OLD.list_code, OLD.code USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.category IS DISTINCT FROM OLD.category THEN
    RAISE EXCEPTION 'LIST_CATEGORY_IMMUTABLE: %.% keeps category %; add a new value instead', OLD.list_code, OLD.code, OLD.category
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT categories INTO cats FROM ref.list_definition WHERE list_code = NEW.list_code;
  IF NOT (NEW.category = ANY (cats)) THEN
    RAISE EXCEPTION 'LIST_CATEGORY_UNKNOWN: % is not a category of % (%)', NEW.category, NEW.list_code, cats USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER list_value_category BEFORE INSERT OR UPDATE OR DELETE ON core.list_value
  FOR EACH ROW EXECUTE FUNCTION core.check_list_category();
CREATE TRIGGER list_starter_category BEFORE INSERT OR UPDATE ON ref.list_starter
  FOR EACH ROW EXECUTE FUNCTION core.check_list_category();

-- A column that takes a list value: the trigger arguments are pairs (column, list_code)
CREATE FUNCTION core.check_list_values() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE j jsonb := to_jsonb(NEW); i int; col text; lst text; v text;
BEGIN
  FOR i IN 0 .. TG_NARGS - 1 BY 2 LOOP
    col := TG_ARGV[i]; lst := TG_ARGV[i + 1]; v := j ->> col;
    CONTINUE WHEN v IS NULL;
    IF NOT EXISTS (SELECT 1 FROM core.list_value lv
                    WHERE lv.tenant_id = (j ->> 'tenant_id')::uuid AND lv.list_code = lst AND lv.code = v) THEN
      RAISE EXCEPTION 'LIST_VALUE_UNKNOWN: "%" is not on the organization''s % list (%.%)', v, lst, TG_TABLE_NAME, col
        USING ERRCODE = 'foreign_key_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

INSERT INTO ref.list_definition (list_code, name_en, name_fr, categories, decision_ref) VALUES
 ('employment_type', 'Employment types', 'Types d''emploi',
  ARRAY['permanent','term','casual','auxiliary','seasonal','student'], 'docs/21 §3.1 (R1.1); docs/22 §3'),
 ('person_type', 'Person types', 'Types de personne',
  ARRAY['employee','elected_official','board_appointee','volunteer','contractor','student','candidate_converted'], 'cando_schema.sql (0001); docs/22 §3'),
 ('language_requirement', 'Language requirements of positions', 'Exigences linguistiques des postes',
  ARRAY['one_language','two_languages','several_languages','other'], 'requirements/01; docs/22 §4'),
 ('case_kind', 'Case types', 'Types de dossier',
  ARRAY['grievance','accommodation','return_to_work','investigation','privacy_request','wcb_claim','pay_equity','other'], 'requirements/13; docs/22 §3'),
 ('review_kind', 'Review types', 'Types d''évaluation',
  ARRAY['probation','annual','mid_year','pip','other'], 'requirements/07; docs/22 §3'),
 ('succession_readiness', 'Successor readiness levels', 'Niveaux de préparation de la relève',
  ARRAY['ready_now','near_term','long_term'], 'requirements/09; docs/22 §3'),
 ('requisition_type', 'Requisition types', 'Types de demande de dotation',
  ARRAY['replacement','additional_headcount','new_position'], 'requirements/02; docs/22 §3'),
 ('comp_decision_kind', 'Pay decision types', 'Types de décision salariale',
  ARRAY['merit','promotion','market_adjustment','equity_adjustment','retention','counter_offer','bonus','lump_sum','other'], 'requirements/04; docs/22 §3');

INSERT INTO ref.list_starter (list_code, code, category, rank, name_en, name_fr, attributes) VALUES
 ('employment_type', 'permanent', 'permanent', 1, 'Permanent', 'Permanent', '{}'),
 ('employment_type', 'term',      'term',      2, 'Term', 'Durée déterminée', '{}'),
 ('employment_type', 'auxiliary', 'auxiliary', 3, 'Auxiliary', 'Auxiliaire', '{}'),
 ('employment_type', 'seasonal',  'seasonal',  4, 'Seasonal', 'Saisonnier', '{}'),
 ('employment_type', 'casual',    'casual',    5, 'Casual', 'Occasionnel', '{}'),
 ('employment_type', 'student',   'student',   6, 'Student', 'Étudiant', '{}'),
 ('person_type', 'employee',            'employee',            1, 'Employee', 'Employé', '{}'),
 ('person_type', 'elected_official',    'elected_official',    2, 'Elected official', 'Élu', '{}'),
 ('person_type', 'board_appointee',     'board_appointee',     3, 'Board appointee', 'Membre nommé au conseil', '{}'),
 ('person_type', 'volunteer',           'volunteer',           4, 'Volunteer', 'Bénévole', '{}'),
 ('person_type', 'contractor',          'contractor',          5, 'Contractor', 'Entrepreneur', '{}'),
 ('person_type', 'student',             'student',             6, 'Student', 'Étudiant', '{}'),
 ('person_type', 'candidate_converted', 'candidate_converted', 7, 'Former candidate', 'Ancien candidat', '{}'),
 ('language_requirement', 'en',          'one_language', 1, 'English', 'Anglais', '{"languages":["en"]}'),
 ('language_requirement', 'fr',          'one_language', 2, 'French', 'Français', '{"languages":["fr"]}'),
 ('language_requirement', 'bilingual_b', 'two_languages', 3, 'English and French, level B', 'Anglais et français, niveau B', '{"languages":["en","fr"],"level":"B"}'),
 ('language_requirement', 'bilingual_c', 'two_languages', 4, 'English and French, level C', 'Anglais et français, niveau C', '{"languages":["en","fr"],"level":"C"}'),
 ('language_requirement', 'other',       'other',        5, 'Other', 'Autre', '{}'),
 ('case_kind', 'grievance',       'grievance',       1, 'Grievance', 'Grief', '{}'),
 ('case_kind', 'accommodation',   'accommodation',   2, 'Accommodation', 'Mesures d''adaptation', '{}'),
 ('case_kind', 'return_to_work',  'return_to_work',  3, 'Return to work', 'Retour au travail', '{}'),
 ('case_kind', 'investigation',   'investigation',   4, 'Investigation', 'Enquête', '{}'),
 ('case_kind', 'privacy_request', 'privacy_request', 5, 'Privacy request', 'Demande relative à la vie privée', '{}'),
 ('case_kind', 'wcb_claim',       'wcb_claim',       6, 'Workers'' compensation claim', 'Réclamation à la commission des accidents du travail', '{}'),
 ('case_kind', 'pay_equity',      'pay_equity',      7, 'Pay equity', 'Équité salariale', '{}'),
 ('case_kind', 'other',           'other',           8, 'Other', 'Autre', '{}'),
 ('review_kind', 'probation', 'probation', 1, 'Probation review', 'Évaluation de stage', '{}'),
 ('review_kind', 'annual',    'annual',    2, 'Annual review', 'Évaluation annuelle', '{}'),
 ('review_kind', 'mid_year',  'mid_year',  3, 'Mid-year review', 'Évaluation de mi-année', '{}'),
 ('review_kind', 'pip',       'pip',       4, 'Performance improvement plan', 'Plan d''amélioration du rendement', '{}'),
 ('succession_readiness', 'ready_now',    'ready_now', 1, 'Ready now', 'Prêt maintenant', '{}'),
 ('succession_readiness', '1_2_years',    'near_term', 2, 'Ready in 1 to 2 years', 'Prêt d''ici 1 à 2 ans', '{}'),
 ('succession_readiness', '3_plus_years', 'long_term', 3, 'Ready in 3 years or more', 'Prêt dans 3 ans ou plus', '{}'),
 ('requisition_type', 'replacement',          'replacement',          1, 'Replacement', 'Remplacement', '{}'),
 ('requisition_type', 'additional_headcount', 'additional_headcount', 2, 'Additional headcount', 'Effectif supplémentaire', '{}'),
 ('requisition_type', 'new_position',         'new_position',         3, 'New position', 'Nouveau poste', '{}'),
 ('comp_decision_kind', 'merit',             'merit',             1, 'Merit increase', 'Augmentation au mérite', '{}'),
 ('comp_decision_kind', 'promotion',         'promotion',         2, 'Promotion', 'Promotion', '{}'),
 ('comp_decision_kind', 'market_adjustment', 'market_adjustment', 3, 'Market adjustment', 'Rajustement au marché', '{}'),
 ('comp_decision_kind', 'equity_adjustment', 'equity_adjustment', 4, 'Equity adjustment', 'Rajustement d''équité', '{}'),
 ('comp_decision_kind', 'retention',         'retention',         5, 'Retention increase', 'Augmentation de maintien', '{}'),
 ('comp_decision_kind', 'bonus',             'bonus',             6, 'Bonus', 'Prime', '{}'),
 ('comp_decision_kind', 'lump_sum',          'lump_sum',          7, 'Lump sum', 'Montant forfaitaire', '{}');

-- The fixed value lists become the organization's lists
ALTER TABLE core.position_version   DROP CONSTRAINT IF EXISTS position_version_employment_type_check,
                                    DROP CONSTRAINT IF EXISTS position_version_language_requirement_check;
ALTER TABLE core.assignment_version DROP CONSTRAINT IF EXISTS assignment_version_employment_type_check;
ALTER TABLE core.employment_version DROP CONSTRAINT IF EXISTS employment_version_employment_type_check;
ALTER TABLE core.person             DROP CONSTRAINT IF EXISTS person_person_type_check;
ALTER TABLE compliance.case_file    DROP CONSTRAINT IF EXISTS case_file_kind_check;
ALTER TABLE talent.review           DROP CONSTRAINT IF EXISTS review_kind_check;
ALTER TABLE talent.succession_slate DROP CONSTRAINT IF EXISTS succession_slate_readiness_check;
ALTER TABLE recruit.requisition     DROP CONSTRAINT IF EXISTS requisition_requisition_type_check;
ALTER TABLE comp.decision           DROP CONSTRAINT IF EXISTS decision_kind_check;

CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON core.position_version
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('employment_type', 'employment_type', 'language_requirement', 'language_requirement');
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON core.assignment_version
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('employment_type', 'employment_type');
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON core.employment_version
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('employment_type', 'employment_type');
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON core.person
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('person_type', 'person_type');
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON compliance.case_file
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('kind', 'case_kind');
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON talent.review
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('kind', 'review_kind');
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON talent.succession_slate
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('readiness', 'succession_readiness');
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON recruit.requisition
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('requisition_type', 'requisition_type');
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON comp.decision
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('kind', 'comp_decision_kind');

-- An employment's status reads the category of its positions' employment types (docs/21 §3.1)
CREATE OR REPLACE FUNCTION core.employment_status_type(p_employment uuid, p_as_of date) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE e record; cats text[]; prec text[]; missing text[]; v text;
BEGIN
  SELECT tenant_id, legal_entity_id INTO e FROM core.employment WHERE employment_id = p_employment;
  SELECT array_agg(DISTINCT lv.category) INTO cats
    FROM core.assignment a
    JOIN core.assignment_version av ON av.assignment_id = a.assignment_id
    JOIN core.list_value lv ON lv.tenant_id = av.tenant_id AND lv.list_code = 'employment_type' AND lv.code = av.employment_type
   WHERE a.employment_id = p_employment AND av.valid_period @> p_as_of AND upper_inf(av.sys_period) AND av.status <> 'ended';
  IF cats IS NULL THEN RETURN NULL; END IF;                     -- no position held on that date: no status to work out
  prec := ARRAY(SELECT jsonb_array_elements_text(platform.setting(e.tenant_id, 'employment.status_precedence', p_as_of, e.legal_entity_id)));
  missing := ARRAY(SELECT unnest(cats) EXCEPT SELECT unnest(prec));
  IF cardinality(missing) > 0 THEN
    RAISE EXCEPTION 'EMPLOYMENT_STATUS_UNRESOLVED: employment.status_precedence does not list %', missing USING ERRCODE = 'check_violation';
  END IF;
  SELECT x.t INTO v FROM unnest(prec) WITH ORDINALITY AS x(t, ord) WHERE x.t = ANY (cats) ORDER BY x.ord LIMIT 1;
  RETURN v;
END $$;

-- -------------------------------------------------------------------------------------
-- 4. Languages as data. Any language can be switched on for an organization's data; the interface has
--    resource files for the languages marked interface_available. English and French text stays in the
--    *_en and *_fr columns; every other language goes in platform.translation. (docs/22 §4)
-- -------------------------------------------------------------------------------------
CREATE TABLE ref.language (
  code                text PRIMARY KEY CHECK (code ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),   -- BCP 47
  name_en             text NOT NULL,
  name_fr             text NOT NULL,
  endonym             text,
  direction           text NOT NULL CHECK (direction IN ('ltr','rtl')),
  interface_available boolean NOT NULL
);
CREATE TABLE ref.locale (
  code     text PRIMARY KEY CHECK (code ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})+$'),
  language text NOT NULL REFERENCES ref.language,
  region   text NOT NULL
);
INSERT INTO ref.language (code, name_en, name_fr, endonym, direction, interface_available) VALUES
 ('en',  'English', 'anglais', 'English', 'ltr', true),
 ('fr',  'French', 'français', 'français', 'ltr', true),
 ('iu',  'Inuktut (Inuktitut)', 'inuktut (inuktitut)', NULL, 'ltr', false),
 ('ikt', 'Inuinnaqtun', 'inuinnaqtun', 'Inuinnaqtun', 'ltr', false),
 ('cr',  'Cree', 'cri', NULL, 'ltr', false),
 ('oj',  'Ojibwe', 'ojibwé', NULL, 'ltr', false),
 ('mic', 'Mi''kmaq', 'micmac', NULL, 'ltr', false),
 ('moh', 'Mohawk', 'mohawk', NULL, 'ltr', false),
 ('den', 'Dene (Slavey)', 'déné (esclave)', NULL, 'ltr', false),
 ('bla', 'Blackfoot', 'pied-noir', NULL, 'ltr', false),
 ('ar',  'Arabic', 'arabe', 'العربية', 'rtl', false),
 ('fa',  'Persian', 'persan', 'فارسی', 'rtl', false),
 ('ur',  'Urdu', 'ourdou', 'اردو', 'rtl', false),
 ('es',  'Spanish', 'espagnol', 'español', 'ltr', false),
 ('pa',  'Punjabi', 'pendjabi', 'ਪੰਜਾਬੀ', 'ltr', false),
 ('zh',  'Chinese', 'chinois', '中文', 'ltr', false),
 ('tl',  'Tagalog', 'tagalog', 'Tagalog', 'ltr', false),
 ('uk',  'Ukrainian', 'ukrainien', 'українська', 'ltr', false);
INSERT INTO ref.locale (code, language, region) SELECT code || '-CA', code, 'CA' FROM ref.language;
COMMENT ON TABLE ref.language IS 'Languages CanDo can hold data in. Adding one is a new row (a platform data change), never a code change.';

-- The languages an organization types its own words in: its main language (chosen at setup), and any other
-- language its texts are kept in (required: every required text has it; optional: some texts have it, for example
-- after CanDo's translation service). Screens are the user's own choice and do not depend on this table.
CREATE TABLE platform.tenant_language (
  tenant_id    uuid NOT NULL REFERENCES platform.tenant,
  lang         text NOT NULL REFERENCES ref.language,
  locale       text NOT NULL REFERENCES ref.locale,
  is_main      boolean NOT NULL,
  for_data     text NOT NULL CHECK (for_data IN ('required','optional')),
  PRIMARY KEY (tenant_id, lang),
  CONSTRAINT main_language_required CHECK (NOT is_main OR for_data = 'required')
);
CREATE UNIQUE INDEX tenant_language_one_main ON platform.tenant_language (tenant_id) WHERE is_main;

-- Text in languages that have no column (everything except the *_en and *_fr columns)
CREATE TABLE platform.translation (
  tenant_id  uuid NOT NULL REFERENCES platform.tenant,
  table_name text NOT NULL,                              -- 'core.position_title'
  row_key    jsonb NOT NULL,                             -- the row's primary key values, in key order, as text
  field      text NOT NULL,                              -- 'title'
  lang       text NOT NULL REFERENCES ref.language,
  value      text NOT NULL CHECK (btrim(value) <> ''),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, table_name, row_key, field, lang)
);

-- Every text field that exists in English and French columns, with the columns per language and the row key
CREATE TABLE platform.translatable_field (
  table_schema   text NOT NULL,
  table_name     text NOT NULL,
  field          text NOT NULL,
  columns        jsonb NOT NULL,                         -- {"en": "name_en", "fr": "name_fr"}
  required       boolean NOT NULL,                       -- the field needs text in every required language
  key_columns    text[] NOT NULL,
  has_sys_period boolean NOT NULL,
  PRIMARY KEY (table_schema, table_name, field)
);

CREATE FUNCTION platform.row_key(p_row jsonb, p_key_columns text[]) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_agg(p_row ->> c ORDER BY ord) FROM unnest(p_key_columns) WITH ORDINALITY AS u(c, ord)
$$;

-- The text of one field of one row in one language, from its column or from platform.translation
CREATE FUNCTION platform.raw_text(p_tenant uuid, f platform.translatable_field, p_row jsonb, p_lang text) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT CASE WHEN f.columns ? p_lang THEN nullif(btrim(p_row ->> (f.columns ->> p_lang)), '')
              ELSE (SELECT tr.value FROM platform.translation tr
                     WHERE tr.tenant_id = p_tenant AND tr.table_name = f.table_schema || '.' || f.table_name
                       AND tr.row_key = platform.row_key(p_row, f.key_columns) AND tr.field = f.field AND tr.lang = p_lang) END
$$;

-- Reading a text in the user's screen language: the text in that language when the organization has it;
-- otherwise the text as the organization typed it (its main language), marked with that language so the screen
-- shows its tag (docs/22 FB-016). A required language with no text is a data error.
CREATE FUNCTION platform.text_for(p_tenant uuid, p_table text, p_row jsonb, p_field text, p_lang text)
RETURNS TABLE (value text, lang text, substituted boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE tl platform.tenant_language; f platform.translatable_field; v text; main text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM ref.language WHERE code = p_lang) THEN
    RAISE EXCEPTION 'LANGUAGE_UNKNOWN: %', p_lang USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO f FROM platform.translatable_field x WHERE x.table_schema || '.' || x.table_name = p_table AND x.field = p_field;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSLATABLE_FIELD_UNKNOWN: %.%', p_table, p_field USING ERRCODE = 'check_violation';
  END IF;
  v := platform.raw_text(p_tenant, f, p_row, p_lang);
  IF v IS NOT NULL THEN
    value := v; lang := p_lang; substituted := false; RETURN NEXT; RETURN;
  END IF;
  SELECT * INTO tl FROM platform.tenant_language x WHERE x.tenant_id = p_tenant AND x.lang = p_lang;
  IF FOUND AND tl.for_data = 'required' AND f.required THEN
    RAISE EXCEPTION 'TRANSLATION_MISSING: %.% has no % text', p_table, p_field, p_lang USING ERRCODE = 'check_violation';
  END IF;
  main := platform.main_language(p_tenant);
  value := platform.raw_text(p_tenant, f, p_row, main); lang := main; substituted := true;   -- fallback: FB-016
  RETURN NEXT;
END $$;

-- Every required field has text in every required language of the organization (checked at commit,
-- so translations can be written in the same transaction). Closed history rows are not rechecked.
CREATE FUNCTION platform.check_required_text() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE j jsonb := to_jsonb(NEW); t uuid := (to_jsonb(NEW) ->> 'tenant_id')::uuid; f platform.translatable_field; l record;
BEGIN
  IF j ? 'sys_period' AND NOT upper_inf((j ->> 'sys_period')::tstzrange) THEN RETURN NULL; END IF;
  PERFORM platform.main_language(t);
  FOR f IN SELECT * FROM platform.translatable_field x WHERE x.table_schema = TG_TABLE_SCHEMA AND x.table_name = TG_TABLE_NAME AND x.required LOOP
    FOR l IN SELECT tl.lang FROM platform.tenant_language tl WHERE tl.tenant_id = t AND tl.for_data = 'required' LOOP
      IF platform.raw_text(t, f, j, l.lang) IS NULL THEN
        RAISE EXCEPTION 'REQUIRED_TEXT_MISSING: %.%.% needs text in %', TG_TABLE_SCHEMA, TG_TABLE_NAME, f.field, l.lang
          USING ERRCODE = 'not_null_violation';
      END IF;
    END LOOP;
  END LOOP;
  RETURN NULL;
END $$;

-- Rows of an organization that have no text in a language, for a required field (current rows only)
CREATE FUNCTION platform.missing_translations(p_tenant uuid, p_lang text)
RETURNS TABLE (table_name text, row_key jsonb, field text) LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE f platform.translatable_field;
BEGIN
  FOR f IN SELECT * FROM platform.translatable_field x WHERE x.required LOOP
    RETURN QUERY EXECUTE format(
      'SELECT %L::text, platform.row_key(to_jsonb(r), %L::text[]), %L::text FROM %I.%I r
        WHERE r.tenant_id = $1 %s AND platform.raw_text($1, $2, to_jsonb(r), $3) IS NULL',
      f.table_schema || '.' || f.table_name, f.key_columns, f.field, f.table_schema, f.table_name,
      CASE WHEN f.has_sys_period THEN 'AND upper_inf(r.sys_period)' ELSE '' END)
      USING p_tenant, f, p_lang;
  END LOOP;
END $$;

-- Quebec: an organization with a current work location in Quebec keeps its own words in French (Charter of the
-- French Language; a legal floor no setting changes). English for such an organization is CanDo's paid service.
CREATE FUNCTION platform.has_quebec_location(p_tenant uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = pg_catalog AS $$
  SELECT EXISTS (SELECT 1 FROM core.location_version lv
                  WHERE lv.tenant_id = p_tenant AND lv.province = 'QC' AND upper_inf(lv.sys_period)
                    AND (upper_inf(lv.valid_period) OR upper(lv.valid_period) > current_date))
$$;

CREATE FUNCTION platform.check_tenant_language() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE n bigint;
BEGIN
  IF TG_OP IN ('DELETE','UPDATE') AND OLD.lang = 'fr' AND OLD.for_data = 'required'
     AND (TG_OP = 'DELETE' OR NEW.for_data <> 'required') AND platform.has_quebec_location(OLD.tenant_id) THEN
    RAISE EXCEPTION 'FRENCH_REQUIRED_FOR_QUEBEC: the organization has a work location in Quebec, so its texts stay in French'
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_main THEN
      RAISE EXCEPTION 'MAIN_LANGUAGE_REQUIRED: choose another main language before removing %', OLD.lang USING ERRCODE = 'check_violation';
    END IF;
    RETURN OLD;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ref.locale WHERE code = NEW.locale AND language = NEW.lang) THEN
    RAISE EXCEPTION 'LOCALE_LANGUAGE_MISMATCH: locale % is not for language %', NEW.locale, NEW.lang USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.for_data = 'required' AND (TG_OP = 'INSERT' OR OLD.for_data <> 'required') THEN
    SELECT count(*) INTO n FROM platform.missing_translations(NEW.tenant_id, NEW.lang);
    IF n > 0 THEN
      RAISE EXCEPTION 'TRANSLATIONS_INCOMPLETE: % texts have no % version yet; switch the language on as optional, complete them (platform.missing_translations), then make it required',
        n, NEW.lang USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tenant_language_check BEFORE INSERT OR UPDATE OR DELETE ON platform.tenant_language
  FOR EACH ROW EXECUTE FUNCTION platform.check_tenant_language();

CREATE FUNCTION platform.check_translation() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE f platform.translatable_field;
BEGIN
  SELECT * INTO f FROM platform.translatable_field x WHERE x.table_schema || '.' || x.table_name = NEW.table_name AND x.field = NEW.field;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TRANSLATABLE_FIELD_UNKNOWN: %.%', NEW.table_name, NEW.field USING ERRCODE = 'check_violation';
  END IF;
  IF f.columns ? NEW.lang THEN
    RAISE EXCEPTION 'TRANSLATION_HAS_COLUMN: % text of %.% is stored in column %', NEW.lang, NEW.table_name, NEW.field, f.columns ->> NEW.lang
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM platform.tenant_language WHERE tenant_id = NEW.tenant_id AND lang = NEW.lang) THEN
    RAISE EXCEPTION 'LANGUAGE_NOT_ENABLED: % is not one of the organization''s languages', NEW.lang USING ERRCODE = 'check_violation';
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
CREATE TRIGGER translation_check BEFORE INSERT OR UPDATE ON platform.translation
  FOR EACH ROW EXECUTE FUNCTION platform.check_translation();

-- Language columns become references to ref.language and ref.locale
ALTER TABLE platform.document ALTER COLUMN language TYPE text USING language::text;
ALTER TABLE platform.document ADD CONSTRAINT document_language_fk FOREIGN KEY (language) REFERENCES ref.language;
ALTER TABLE core.person_version ALTER COLUMN preferred_language DROP DEFAULT;
ALTER TABLE core.person_version ALTER COLUMN preferred_language TYPE text USING preferred_language::text;
ALTER TABLE core.person_version ADD CONSTRAINT person_version_preferred_language_fk FOREIGN KEY (preferred_language) REFERENCES ref.language;
INSERT INTO platform.column_default (table_schema, table_name, column_name, source) VALUES ('core','person_version','preferred_language','tenant_main_language');
ALTER TABLE ref.code_item_title ALTER COLUMN lang TYPE text USING lang::text;
ALTER TABLE ref.code_item_title ADD CONSTRAINT code_item_title_lang_fk FOREIGN KEY (lang) REFERENCES ref.language;
ALTER TABLE platform.app_user DROP CONSTRAINT IF EXISTS app_user_locale_check;
ALTER TABLE platform.app_user ALTER COLUMN locale DROP DEFAULT;
ALTER TABLE platform.app_user ADD CONSTRAINT app_user_locale_fk FOREIGN KEY (locale) REFERENCES ref.locale;
INSERT INTO platform.column_default (table_schema, table_name, column_name, source) VALUES ('platform','app_user','locale','tenant_main_locale');
-- A user's screens are in a language CanDo has screens for (ref.language.interface_available); data, documents and
-- notices follow the organization's data languages. No screen language is ever substituted silently.
CREATE FUNCTION platform.check_interface_locale() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM ref.locale lo JOIN ref.language la ON la.code = lo.language
                  WHERE lo.code = NEW.locale AND la.interface_available) THEN
    RAISE EXCEPTION 'INTERFACE_LANGUAGE_NOT_AVAILABLE: CanDo''s screens are not available in % yet; give the user a locale whose language has screens', NEW.locale
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a01_interface_locale BEFORE INSERT OR UPDATE OF locale ON platform.app_user
  FOR EACH ROW EXECUTE FUNCTION platform.check_interface_locale();

-- Existing organizations' languages move to platform.tenant_language in §9, once every text field is registered

DROP FUNCTION ref.search_code_titles(text, text, ref.lang, int);
CREATE FUNCTION ref.search_code_titles(p_version text, p_query text, p_lang text, p_limit int DEFAULT 10)
RETURNS TABLE (code text, title_en text, matched_title text, kind text, score real)
LANGUAGE sql STABLE AS $$
  SELECT DISTINCT ON (i.code) i.code, i.title_en, t.title, t.kind, similarity(t.title, p_query)
  FROM ref.code_item_title t
  JOIN ref.code_item i ON i.version_id = t.version_id AND i.code = t.code
  WHERE t.version_id = p_version AND t.lang = p_lang AND p_query <% t.title
  ORDER BY i.code, similarity(t.title, p_query) DESC
  LIMIT p_limit
$$;

-- -------------------------------------------------------------------------------------
-- 5. Limits from settings: assignment FTE, override reasons, support access grants
-- -------------------------------------------------------------------------------------
ALTER TABLE core.assignment_version DROP CONSTRAINT IF EXISTS assignment_version_fte_check;
ALTER TABLE core.assignment_version ADD CONSTRAINT assignment_version_fte_positive CHECK (fte > 0);
CREATE FUNCTION core.check_assignment_fte() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE le uuid; lim numeric;
BEGIN
  SELECT e.legal_entity_id INTO le FROM core.assignment a JOIN core.employment e ON e.employment_id = a.employment_id
   WHERE a.assignment_id = NEW.assignment_id;
  lim := platform.setting_number(NEW.tenant_id, 'positions.max_assignment_fte', lower(NEW.valid_period), le);
  IF NEW.fte > lim THEN
    RAISE EXCEPTION 'FTE_ABOVE_LIMIT: % is above the organization''s limit of % for one assignment', NEW.fte, lim USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a02_assignment_fte BEFORE INSERT OR UPDATE OF fte ON core.assignment_version
  FOR EACH ROW EXECUTE FUNCTION core.check_assignment_fte();

ALTER TABLE core.position_control_override DROP CONSTRAINT IF EXISTS position_control_override_reason_check;
ALTER TABLE core.position_control_override ADD CONSTRAINT position_control_override_reason_present CHECK (btrim(reason) <> '');
CREATE FUNCTION core.check_override_reason() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE n numeric := platform.setting_number(NEW.tenant_id, 'approvals.override_reason_min_length');
BEGIN
  IF length(btrim(NEW.reason)) < n THEN
    RAISE EXCEPTION 'REASON_TOO_SHORT: the reason needs at least % characters', n USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a02_override_reason BEFORE INSERT OR UPDATE OF reason ON core.position_control_override
  FOR EACH ROW EXECUTE FUNCTION core.check_override_reason();

ALTER TABLE platform.support_access_grant DROP CONSTRAINT IF EXISTS support_access_grant_valid_period_check;
CREATE FUNCTION platform.check_support_grant_length() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE days numeric := platform.setting_number(NEW.tenant_id, 'support.max_grant_days');
BEGIN
  IF upper(NEW.valid_period) - lower(NEW.valid_period) > make_interval(days => days::int) THEN
    RAISE EXCEPTION 'SUPPORT_GRANT_TOO_LONG: a support access grant lasts at most % days', days USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a02_support_grant_length BEFORE INSERT OR UPDATE OF valid_period ON platform.support_access_grant
  FOR EACH ROW EXECUTE FUNCTION platform.check_support_grant_length();

-- -------------------------------------------------------------------------------------
-- 6. Countries and postal code formats; data regions
-- -------------------------------------------------------------------------------------
CREATE TABLE ref.country (
  code                char(2) PRIMARY KEY CHECK (code ~ '^[A-Z]{2}$'),
  name_en             text NOT NULL,
  name_fr             text NOT NULL,
  has_postal_codes    boolean NOT NULL,
  postal_code_pattern text,
  uses_province_codes boolean NOT NULL,                  -- addresses use ref.province_code (Canada)
  CHECK (has_postal_codes = (postal_code_pattern IS NOT NULL))
);
INSERT INTO ref.country (code, name_en, name_fr, has_postal_codes, postal_code_pattern, uses_province_codes) VALUES
 ('CA', 'Canada', 'Canada', true, '^[A-Z][0-9][A-Z] ?[0-9][A-Z][0-9]$', true),
 ('US', 'United States', 'États-Unis', true, '^[0-9]{5}(-[0-9]{4})?$', false);

ALTER TABLE core.location_version DROP CONSTRAINT IF EXISTS location_version_postal_code_check;
ALTER TABLE core.location_version ADD COLUMN country_code char(2) REFERENCES ref.country;
UPDATE core.location_version SET country_code = 'CA' WHERE country_code IS NULL;   -- every existing row has a Canadian province
ALTER TABLE core.location_version
  ALTER COLUMN country_code SET NOT NULL,
  ALTER COLUMN postal_code DROP NOT NULL,
  ALTER COLUMN province DROP NOT NULL,
  ALTER COLUMN holiday_jurisdiction DROP NOT NULL;
INSERT INTO platform.column_default (table_schema, table_name, column_name, source, setting_key)
  VALUES ('core','location_version','country_code','setting','locations.default_country');
CREATE FUNCTION core.check_location_address() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE c ref.country;
BEGIN
  SELECT * INTO c FROM ref.country WHERE code = NEW.country_code;
  IF c.has_postal_codes AND (NEW.postal_code IS NULL OR NEW.postal_code !~ c.postal_code_pattern) THEN
    RAISE EXCEPTION 'POSTAL_CODE_FORMAT: % is not a postal code of %', NEW.postal_code, c.name_en USING ERRCODE = 'check_violation';
  END IF;
  IF c.uses_province_codes AND (NEW.province IS NULL OR NEW.holiday_jurisdiction IS NULL) THEN
    RAISE EXCEPTION 'PROVINCE_REQUIRED: a location in % needs its province and holiday jurisdiction', c.name_en USING ERRCODE = 'check_violation';
  END IF;
  IF NOT c.uses_province_codes AND (NEW.province IS NOT NULL OR NEW.holiday_jurisdiction IS NOT NULL) THEN
    RAISE EXCEPTION 'PROVINCE_NOT_APPLICABLE: Canadian province codes do not apply to a location in %', c.name_en USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a02_location_address BEFORE INSERT OR UPDATE ON core.location_version
  FOR EACH ROW EXECUTE FUNCTION core.check_location_address();
CREATE FUNCTION core.check_quebec_french() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
BEGIN
  IF NEW.province = 'QC' AND upper_inf(NEW.sys_period) AND NOT EXISTS (
       SELECT 1 FROM platform.tenant_language tl WHERE tl.tenant_id = NEW.tenant_id AND tl.lang = 'fr' AND tl.for_data = 'required') THEN
    RAISE EXCEPTION 'FRENCH_REQUIRED_FOR_QUEBEC: a work location in Quebec needs the organization''s texts in French; make French its main or a required language first'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a03_quebec_french BEFORE INSERT OR UPDATE OF province ON core.location_version
  FOR EACH ROW EXECUTE FUNCTION core.check_quebec_french();
COMMENT ON COLUMN core.location_version.country_code IS
  'Payroll, employment standards and holiday calendars run for Canadian locations; a location in another country stops a pay run with LOCATION_OUTSIDE_CANADA until a payroll for that country exists (docs/22 §6).';

CREATE TABLE ref.data_region (
  code    text PRIMARY KEY,
  name_en text NOT NULL,
  name_fr text NOT NULL
);
INSERT INTO ref.data_region (code, name_en, name_fr) VALUES
 ('CA', 'Canada', 'Canada'),
 ('EU', 'European Union', 'Union européenne');
ALTER TABLE platform.tenant DROP CONSTRAINT IF EXISTS tenant_residency_check;
ALTER TABLE platform.tenant ADD CONSTRAINT tenant_residency_fk FOREIGN KEY (residency) REFERENCES ref.data_region;

-- -------------------------------------------------------------------------------------
-- 7. Legal values come from the rules
-- -------------------------------------------------------------------------------------
-- EI: the employer multiplier is the rule edition's ei.employer_multiplier; an account stores a rate only
-- when CRA has assigned it a reduced rate, with CRA's reference
ALTER TABLE core.payroll_account ALTER COLUMN ei_employer_rate DROP DEFAULT;
ALTER TABLE core.payroll_account ALTER COLUMN ei_employer_rate DROP NOT NULL;
ALTER TABLE core.payroll_account ADD COLUMN ei_reduced_rate_ref text;
UPDATE core.payroll_account SET ei_employer_rate = NULL WHERE ei_employer_rate = 1.4 AND ei_reduced_rate_ref IS NULL;
-- NOT VALID: an account that stored another rate before 0008 keeps it until its CRA reference is recorded;
-- then VALIDATE CONSTRAINT (AGENTS.md Step 1). New and changed accounts are checked now.
ALTER TABLE core.payroll_account ADD CONSTRAINT payroll_account_reduced_rate_has_reference
  CHECK ((ei_employer_rate IS NULL) = (ei_reduced_rate_ref IS NULL)) NOT VALID;
COMMENT ON COLUMN core.payroll_account.ei_employer_rate IS
  'Only a CRA-assigned reduced employer rate (with ei_reduced_rate_ref). Otherwise payroll uses ei.employer_multiplier from the rule edition of the pay date.';

-- Public wage editions say which statistic each published column is (Job Bank: low and high are usually P10 and
-- P90, docs/19 §6.5); market pricing reads only this, never an assumed mapping. Existing editions are checked when
-- the loader records it (VALIDATE CONSTRAINT, AGENTS.md Step 1); new and changed editions are checked now.
CREATE FUNCTION ref.is_statistic_columns(v jsonb) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_typeof(v) = 'object'
     AND NOT EXISTS (SELECT 1 FROM jsonb_each(v) e
                      WHERE e.key NOT IN ('mean','p10','p25','p50','p75','p90')
                         OR jsonb_typeof(e.value) <> 'string' OR e.value #>> '{}' NOT IN ('low','median','high'))
$$;
ALTER TABLE ref.public_wage_edition ADD COLUMN statistic_columns jsonb CHECK (statistic_columns IS NULL OR ref.is_statistic_columns(statistic_columns));
ALTER TABLE ref.public_wage_edition
  ADD CONSTRAINT public_wage_edition_statistics_stated
    CHECK (status NOT IN ('published','superseded') OR statistic_columns IS NOT NULL) NOT VALID;
COMMENT ON COLUMN ref.public_wage_edition.statistic_columns IS
  'Which statistic each published column is, from the publisher''s methodology, for example {"p10": "low", "p50": "median", "p90": "high"}.';

-- Overtime rate basis: written by the time engine from the employment standards or agreement rule
ALTER TABLE timeleave.time_line ALTER COLUMN rate_basis DROP DEFAULT;
COMMENT ON COLUMN timeleave.time_line.rate_basis IS
  'Written by the time engine from the rule that applies (overtime.rate_basis in the employment standards file, or the agreement); never assumed.';

-- -------------------------------------------------------------------------------------
-- 8. Fixes to 0006 and 0007: no fallbacks written in code
-- -------------------------------------------------------------------------------------
-- 8.1 Approvals for back-dated changes read every number from the setting
CREATE OR REPLACE FUNCTION platform.required_approvals(cs platform.change_set)
RETURNS TABLE (hr_needed int, payroll_needed int) LANGUAGE plpgsql STABLE AS $$
DECLARE hr_list jsonb; bd jsonb; hr int := 0; pay int := 0;
BEGIN
  hr_list := platform.setting(cs.tenant_id, 'approvals.hr_required', cs.effective_date);
  IF (hr_list ? 'termination' AND 'termination' IN (cs.reason_category, cs.kind))
     OR (hr_list ? 'demotion' AND 'demotion' IN (cs.reason_category, cs.kind))
     OR (hr_list ? 'leave_or_accommodation' AND (cs.linked_case_id IS NOT NULL OR cs.linked_leave_request_id IS NOT NULL)) THEN
    hr := 1;
  END IF;
  IF cs.reaches_finalized_pay THEN
    bd := platform.setting(cs.tenant_id, 'retro.backdate_approval', cs.effective_date);
    IF NOT (bd ?& ARRAY['hrApprovals','olderHrApprovals','payrollApproval','secondHrApprovalOlderThan']) THEN
      RAISE EXCEPTION 'SETTING_KEYS_MISSING: retro.backdate_approval' USING ERRCODE = 'check_violation';
    END IF;
    hr := greatest(hr, (bd ->> 'hrApprovals')::int);
    IF cs.effective_date < (cs.requested_at::date - (bd ->> 'secondHrApprovalOlderThan')::interval) THEN
      hr := greatest(hr, (bd ->> 'olderHrApprovals')::int);
    END IF;
    IF (bd ->> 'payrollApproval')::boolean THEN pay := 1; END IF;
  END IF;
  hr_needed := hr; payroll_needed := pay;
  RETURN NEXT;
END $$;

-- 8.2 Employee numbers: the format setting states its prefix and width
CREATE OR REPLACE FUNCTION core.next_employee_number(p_tenant uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE fmt jsonb := platform.setting(p_tenant, 'employee_number.format'); n bigint; candidate text;
BEGIN
  IF NOT (fmt ?& ARRAY['prefix','width']) THEN
    RAISE EXCEPTION 'SETTING_KEYS_MISSING: employee_number.format needs prefix and width' USING ERRCODE = 'check_violation';
  END IF;
  INSERT INTO core.employee_number_counter (tenant_id) VALUES (p_tenant) ON CONFLICT (tenant_id) DO NOTHING;
  LOOP
    UPDATE core.employee_number_counter SET last_value = last_value + 1 WHERE tenant_id = p_tenant RETURNING last_value INTO n;
    candidate := (fmt ->> 'prefix') || lpad(n::text, (fmt ->> 'width')::int, '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM core.person WHERE tenant_id = p_tenant AND employee_number = candidate)
          AND NOT EXISTS (SELECT 1 FROM core.employment WHERE tenant_id = p_tenant AND employee_number = candidate);
  END LOOP;
  RETURN candidate;
END $$;

-- 8.3 Relationships across employers: the relationship type says which shared-services purpose it needs
ALTER TABLE core.relationship_type ADD COLUMN cross_employer_purpose text
  CHECK (cross_employer_purpose IN ('supervision','hr_services','payroll_services','none'));
-- Existing types keep the purpose 0007 gave them (mentor: none; hrbp: hr_services; any other: supervision);
-- the organization reviews them during setup (docs/22 §5, FB-014)
UPDATE core.relationship_type
   SET cross_employer_purpose = CASE code WHEN 'mentor' THEN 'none' WHEN 'hrbp' THEN 'hr_services' ELSE 'supervision' END
 WHERE cross_employer_purpose IS NULL;
ALTER TABLE core.relationship_type ALTER COLUMN cross_employer_purpose SET NOT NULL;
COMMENT ON COLUMN core.relationship_type.cross_employer_purpose IS
  'Shared-services purpose a relationship of this type needs when the two people work for different employers; none = no arrangement needed (for example a mentor).';
CREATE OR REPLACE FUNCTION core.check_cross_employer_relationship() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le_self uuid; le_other uuid; purpose text;
BEGIN
  SELECT e.legal_entity_id INTO le_self FROM core.assignment a JOIN core.employment e USING (employment_id) WHERE a.assignment_id = NEW.assignment_id;
  SELECT e.legal_entity_id INTO le_other FROM core.assignment a JOIN core.employment e USING (employment_id) WHERE a.assignment_id = NEW.related_assignment_id;
  IF le_self = le_other THEN RETURN NEW; END IF;
  IF NEW.relationship_type_code IS NULL THEN
    RAISE EXCEPTION 'RELATIONSHIP_TYPE_REQUIRED: a relationship across employers names its relationship type' USING ERRCODE = 'check_violation';
  END IF;
  SELECT rt.cross_employer_purpose INTO purpose FROM core.relationship_type rt
   WHERE rt.tenant_id = NEW.tenant_id AND rt.code = NEW.relationship_type_code;
  IF purpose IS NULL THEN
    RAISE EXCEPTION 'RELATIONSHIP_TYPE_UNKNOWN: % is not one of the organization''s relationship types', NEW.relationship_type_code
      USING ERRCODE = 'check_violation';
  END IF;
  IF purpose <> 'none' AND NOT core.has_shared_services(le_other, le_self, purpose, lower(NEW.valid_period)) THEN
    RAISE EXCEPTION 'CROSS_EMPLOYER_NO_ARRANGEMENT: no shared-services arrangement for % between the two employers', purpose
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- 8.4 The title for a purpose in any of the organization's languages: that purpose (and funder), then the
--     working title, then the job's title (docs/21 §6.4); the language comes from platform.text_for
DROP FUNCTION core.position_title_for(uuid, text, date, uuid, ref.lang);
CREATE FUNCTION core.position_title_for(p_position uuid, p_purpose text, p_as_of date, p_lang text, p_funding_source uuid DEFAULT NULL)
RETURNS TABLE (title text, origin text, title_lang text, substituted boolean) LANGUAGE sql STABLE AS $$
  SELECT t.title, t.origin, t.lang, t.substituted FROM (
    SELECT x.value AS title, pt.purpose AS origin, x.lang, x.substituted,
           CASE WHEN pt.purpose = p_purpose THEN 1 ELSE 2 END AS rank
    FROM core.position_title pt
    CROSS JOIN LATERAL platform.text_for(pt.tenant_id, 'core.position_title', to_jsonb(pt), 'title', p_lang) x
    WHERE pt.position_id = p_position AND pt.valid_period @> p_as_of AND upper_inf(pt.sys_period)
      AND ((pt.purpose = p_purpose AND pt.funding_source_id IS NOT DISTINCT FROM p_funding_source) OR pt.purpose = 'working')
    UNION ALL
    SELECT x.value, 'job', x.lang, x.substituted, 3
    FROM core.position_version pv
    JOIN core.job_version jv ON jv.job_id = pv.job_id AND jv.valid_period @> p_as_of AND upper_inf(jv.sys_period)
    CROSS JOIN LATERAL platform.text_for(jv.tenant_id, 'core.job_version', to_jsonb(jv), 'title', p_lang) x
    WHERE pv.position_id = p_position AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
  ) t
  ORDER BY t.rank
  LIMIT 1
$$;

-- 8.5 Overall review rating and competency gaps read their settings (docs/20 §5)
DROP FUNCTION talent.review_overall(uuid, numeric);
CREATE FUNCTION talent.review_overall(p_review uuid, p_step numeric) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT round(sum(s.fte * s.days_in_cycle * s.rating_score) / sum(s.fte * s.days_in_cycle) / p_step) * p_step
  FROM talent.review_section s JOIN talent.review r USING (review_id)
  WHERE s.review_id = p_review AND s.rated AND s.rating_score IS NOT NULL AND s.days_in_cycle >= r.min_section_days
    AND r.overall_method = 'fte_weighted'
$$;
CREATE FUNCTION talent.review_overall(p_review uuid) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT talent.review_overall(p_review, platform.setting_number(r.tenant_id, 'reviews.overall_rounding_step'))
  FROM talent.review r WHERE r.review_id = p_review
$$;

DO $$
DECLARE body text;
BEGIN
  SELECT pg_get_functiondef('talent.competency_gap(uuid,date,text[])'::regprocedure) INTO body;
  body := replace(body, 'p_sources text[] DEFAULT ARRAY[''calibrated''::text, ''assessment''::text, ''manager''::text, ''peer_360''::text, ''evidence''::text]',
                        'p_sources text[]');
  IF body NOT LIKE '%p_sources text[])%' THEN
    RAISE EXCEPTION 'competency_gap signature not as expected';
  END IF;
  DROP FUNCTION talent.competency_gap(uuid, date, text[]);
  EXECUTE body;
END $$;
CREATE FUNCTION talent.competency_gap(p_assignment uuid, p_as_of date)
RETURNS TABLE (framework_id uuid, competency_code text, required_level smallint, entry_level smallint, criticality text,
               target_from text, assessed_level smallint, assessed_on date, assessment_source text, self_level smallint, gap smallint)
LANGUAGE sql STABLE AS $$
  SELECT g.* FROM core.assignment a
  CROSS JOIN LATERAL talent.competency_gap(p_assignment, p_as_of,
                 ARRAY(SELECT jsonb_array_elements_text(platform.setting(a.tenant_id, 'competencies.gap_sources', p_as_of)))) g
  WHERE a.assignment_id = p_assignment
$$;

-- -------------------------------------------------------------------------------------
-- 9. Starter data: every organization gets the starter lists and its languages when it is created
-- -------------------------------------------------------------------------------------
CREATE FUNCTION core.seed_tenant(p_tenant uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE l jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM platform.tenant_language WHERE tenant_id = p_tenant) THEN
    FOR l IN SELECT jsonb_array_elements(platform.setting(p_tenant, 'languages.starter') -> 'languages') LOOP
      INSERT INTO platform.tenant_language (tenant_id, lang, locale, is_main, for_data)
        VALUES (p_tenant, l ->> 'code', l ->> 'locale', (l ->> 'main')::boolean, l ->> 'forData');
    END LOOP;
  END IF;
  INSERT INTO core.list_value (tenant_id, list_code, code, category, rank, name_en, name_fr, attributes, status)
    SELECT p_tenant, s.list_code, s.code, s.category, s.rank, s.name_en, s.name_fr, s.attributes, 'active'
    FROM ref.list_starter s
  ON CONFLICT DO NOTHING;
END $$;
CREATE FUNCTION core.seed_new_tenant() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  PERFORM core.seed_tenant(NEW.tenant_id);
  RETURN NULL;
END $$;
CREATE TRIGGER tenant_seed AFTER INSERT ON platform.tenant
  FOR EACH ROW EXECUTE FUNCTION core.seed_new_tenant();

-- The fill trigger on every table with a registered default (named to run before the other BEFORE triggers)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT table_schema AS s, table_name AS t FROM platform.column_default LOOP
    EXECUTE format('CREATE TRIGGER a00_fill_from_settings BEFORE INSERT ON %I.%I FOR EACH ROW EXECUTE FUNCTION platform.fill_from_settings()', r.s, r.t);
  END LOOP;
END $$;

-- Register every English/French text field of the tenant tables (and its French column, where there is one),
-- let the main language be any language, and check required text at commit
DO $$
DECLARE r record; k text[]; sp boolean;
BEGIN
  FOR r IN
    SELECT c.table_schema AS s, c.table_name AS t, c.column_name AS col, c.is_nullable = 'NO' AS req,
           regexp_replace(c.column_name, '_en$', '') AS field,
           EXISTS (SELECT 1 FROM information_schema.columns f WHERE f.table_schema = c.table_schema AND f.table_name = c.table_name
                     AND f.column_name = regexp_replace(c.column_name, '_en$', '_fr')) AS has_fr
    FROM information_schema.columns c
    JOIN information_schema.tables tb ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name AND tb.table_type = 'BASE TABLE'
    WHERE c.column_name ~ '_en$'
      AND c.table_schema IN ('platform','core','payroll','timeleave','finance','comp','talent','benefits','recruit','offboard','compliance')
      AND EXISTS (SELECT 1 FROM information_schema.columns x WHERE x.table_schema = c.table_schema AND x.table_name = c.table_name AND x.column_name = 'tenant_id')
    ORDER BY 1, 2, 3
  LOOP
    SELECT array_agg(a.attname ORDER BY array_position(i.indkey::int2[], a.attnum)) INTO k
      FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
     WHERE i.indrelid = format('%I.%I', r.s, r.t)::regclass AND i.indisprimary;
    IF k IS NULL THEN RAISE EXCEPTION 'translatable table %.% has no primary key', r.s, r.t; END IF;
    sp := EXISTS (SELECT 1 FROM information_schema.columns x WHERE x.table_schema = r.s AND x.table_name = r.t AND x.column_name = 'sys_period');
    INSERT INTO platform.translatable_field (table_schema, table_name, field, columns, required, key_columns, has_sys_period)
      VALUES (r.s, r.t, r.field,
              jsonb_build_object('en', r.col) || CASE WHEN r.has_fr THEN jsonb_build_object('fr', r.field || '_fr') ELSE '{}'::jsonb END,
              r.req, k, sp);
    IF r.req THEN EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I DROP NOT NULL', r.s, r.t, r.col); END IF;
  END LOOP;
  FOR r IN SELECT DISTINCT table_schema AS s, table_name AS t FROM platform.translatable_field WHERE required LOOP
    EXECUTE format('CREATE CONSTRAINT TRIGGER zz_required_text AFTER INSERT OR UPDATE ON %I.%I DEFERRABLE INITIALLY DEFERRED
                    FOR EACH ROW EXECUTE FUNCTION platform.check_required_text()', r.s, r.t);
  END LOOP;
END $$;

-- Existing organizations keep their languages. Before 0008 every text had English, so English is the main language
-- where the organization had it. Another language becomes required when every text already has it; otherwise it is
-- kept as optional, and users reading in it see the English text marked, until the texts are complete (docs/22 FB-017).
DO $$
DECLARE t record; l record; main text; n bigint;
BEGIN
  FOR t IN SELECT tenant_id, languages FROM platform.tenant LOOP
    main := CASE WHEN 'en' = ANY (t.languages::text[]) THEN 'en' ELSE t.languages[1]::text END;
    IF main IS NULL THEN
      RAISE EXCEPTION 'MAIN_LANGUAGE_NOT_SET: organization % has no language; give it one before applying 0008', t.tenant_id;
    END IF;
    INSERT INTO platform.tenant_language (tenant_id, lang, locale, is_main, for_data) VALUES (t.tenant_id, main, main || '-CA', true, 'required');
    FOR l IN SELECT DISTINCT x::text AS lang FROM unnest(t.languages) x WHERE x::text <> main LOOP
      SELECT count(*) INTO n FROM platform.missing_translations(t.tenant_id, l.lang);
      IF n = 0 THEN
        INSERT INTO platform.tenant_language (tenant_id, lang, locale, is_main, for_data) VALUES (t.tenant_id, l.lang, l.lang || '-CA', false, 'required');
      ELSE
        INSERT INTO platform.tenant_language (tenant_id, lang, locale, is_main, for_data)
          VALUES (t.tenant_id, l.lang, l.lang || '-CA', false, 'optional');
        RAISE NOTICE 'organization %: % texts have no % version; % is optional until they are completed', t.tenant_id, n, l.lang, l.lang;
      END IF;
    END LOOP;
  END LOOP;
END $$;
ALTER TABLE platform.tenant DROP COLUMN languages;
SELECT core.seed_tenant(tenant_id) FROM platform.tenant;

DROP TYPE ref.lang;

-- -------------------------------------------------------------------------------------
-- 10. Row-level security on the new tenant tables (same policy as 0001)
-- -------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('core','list_value'), ('platform','tenant_language'), ('platform','translation')) AS x(s, t) LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$, r.s, r.t);
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT on the new ref tables, platform.column_default and
-- platform.translatable_field; SELECT, INSERT and UPDATE on core.list_value, platform.tenant_language and
-- platform.translation; EXECUTE on the new functions. Only CanDo's provisioning path inserts platform.tenant.
