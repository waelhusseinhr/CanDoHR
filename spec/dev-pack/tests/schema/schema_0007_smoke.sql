-- Smoke test for schema/0007_core_hr_decisions.sql (docs/21): organization settings and locked legal floors,
-- one employee number per person, employment status from positions, probation per unit, rehire eligibility,
-- light mode removed, routing past vacant manager positions, units without a head, reporting across employers,
-- position control overrides, position titles, approvals HR and payroll must give, communicated changes,
-- overpayments, agreement findings against employment standards, bank account changes, self-identification
-- categories, support access, tenant isolation and RLS on every new table.
-- Run after every migration, 0001 to 0008 (CI, after the 0006 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0007_smoke.sql
-- It inserts test rows; run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, finance, compliance TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA platform, core, payroll TO cando_app;

-- 1. RLS forced on every tenant table in the schemas 0007 adds to (platform.tenant stays outside)
DO $$
DECLARE missing text;
BEGIN
  SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO missing
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r' AND n.nspname IN ('platform','core','payroll')
    AND NOT (n.nspname = 'platform' AND c.relname = 'tenant')
    AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
    AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1: RLS missing on %', missing; END IF;
  IF (SELECT relrowsecurity FROM pg_class WHERE oid = 'platform.tenant'::regclass) THEN
    RAISE EXCEPTION 'FAIL 1: platform.tenant must stay outside tenant RLS';
  END IF;
  RAISE NOTICE 'PASS 1: RLS forced on every tenant table; platform.tenant untouched';
END $$;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('71111111-1111-1111-1111-111111111111', 'Core HR Test City'),
  ('72222222-2222-2222-2222-222222222222', 'Other Tenant')
ON CONFLICT DO NOTHING;
-- Some of this organization's texts are also kept in French (optional): a text with no French version shows the English one, marked (0008 §4)
INSERT INTO platform.tenant_language (tenant_id, lang, locale, is_main, for_data)
  VALUES ('71111111-1111-1111-1111-111111111111', 'fr', 'fr-CA', false, 'optional')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', '71111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- Fixtures: the City (LE1) and its library board (LE2); a head, a vacant manager position, Jordan in two positions
-- ---------------------------------------------------------------------------------
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  (current_setting('app.tenant_id')::uuid, '07a00000-0000-0000-0000-000000000001', 'req',  'req@example.test'),
  (current_setting('app.tenant_id')::uuid, '07a00000-0000-0000-0000-000000000002', 'hr1',  'hr1@example.test'),
  (current_setting('app.tenant_id')::uuid, '07a00000-0000-0000-0000-000000000003', 'hr2',  'hr2@example.test'),
  (current_setting('app.tenant_id')::uuid, '07a00000-0000-0000-0000-000000000004', 'pay',  'pay@example.test'),
  (current_setting('app.tenant_id')::uuid, '07a00000-0000-0000-0000-000000000005', 'fin',  'fin@example.test'),
  (current_setting('app.tenant_id')::uuid, '07a00000-0000-0000-0000-000000000006', 'jordan', 'jordan@example.test');
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'a7000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'a7000000-0000-0000-0000-000000000002');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, 'b7000000-0000-0000-0000-000000000001');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'c7000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'c7000000-0000-0000-0000-000000000002');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, 'd7000000-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, 'd7000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'PC', 'Program Coordinator', 'Coordonnateur de programme');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000001', 'HEAD'),
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000002', 'MGR'),
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000003', 'STAFF'),
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000004', 'LIB'),
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000005', 'CASUAL');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'c7000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'a7000000-0000-0000-0000-000000000001', 'DIV', 'REC', 'Recreation', 'e7000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'c7000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'a7000000-0000-0000-0000-000000000002', 'DIV', 'LIB', 'Library services', NULL);
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'd7000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', NULL, 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'd7000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'd7000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000002', 0.6, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000005', '[2020-01-01,)', gen_random_uuid(), 'd7000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000002', 0.4, 'casual', 'active');
INSERT INTO core.person (tenant_id, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f7000000-0000-0000-0000-000000000001'),   -- Jordan
  (current_setting('app.tenant_id')::uuid, 'f7000000-0000-0000-0000-000000000002');   -- the division head

-- 2. Settings: defaults, tenant and legal entity overrides, locked floors, types and allowed values
DO $$ BEGIN
  IF platform.setting(current_setting('app.tenant_id')::uuid, 'positions.over_budget') #>> '{}' <> 'finance_approval' THEN
    RAISE EXCEPTION 'FAIL 2a: default not returned';
  END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'positions.over_budget', '"hard_stop"', '[2026-01-01,)', gen_random_uuid());
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'positions.over_budget', 'legal_entity', 'a7000000-0000-0000-0000-000000000002',
            '"finance_approval"', '[2026-01-01,)', gen_random_uuid());
  IF platform.setting(current_setting('app.tenant_id')::uuid, 'positions.over_budget', '2026-06-01', 'a7000000-0000-0000-0000-000000000001') #>> '{}' <> 'hard_stop'
     OR platform.setting(current_setting('app.tenant_id')::uuid, 'positions.over_budget', '2026-06-01', 'a7000000-0000-0000-0000-000000000002') #>> '{}' <> 'finance_approval'
     OR platform.setting(current_setting('app.tenant_id')::uuid, 'positions.over_budget', '2025-06-01', 'a7000000-0000-0000-0000-000000000001') #>> '{}' <> 'finance_approval' THEN
    RAISE EXCEPTION 'FAIL 2b: overrides not resolved by scope and date';
  END IF;
  RAISE NOTICE 'PASS 2a-b: default, tenant override, legal entity override and dates resolved';
END $$;
DO $$ BEGIN
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'approvals.no_self_approval', 'false', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 2c: locked setting changed';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SETTING_LOCKED%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 2c: locked setting refused (SETTING_LOCKED)';
END $$;
DO $$ BEGIN
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'rehire.review_max_months', '"twelve"', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 2d: wrong value type accepted';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SETTING_VALUE_TYPE%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 2d: wrong value type refused';
END $$;
DO $$ BEGIN
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'self_service.show_changes', '"sometimes"', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 2e: value outside the allowed list accepted';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SETTING_VALUE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 2e: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 2e: value outside the allowed list refused';
END $$;
DO $$ BEGIN
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'employment.status_precedence', 'legal_entity', 'a7000000-0000-0000-0000-000000000001',
            '["casual"]', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 2f: tenant-only setting set per legal entity';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SETTING_SCOPE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 2f: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 2f: scope not allowed refused';
END $$;

-- 3. One employee number per person, for life
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id, employee_number) VALUES
  (current_setting('app.tenant_id')::uuid, 'f7100000-0000-0000-0000-000000000001', 'f7000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000001', 'E-100');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f7100000-0000-0000-0000-000000000003', 'f7000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, 'f7100000-0000-0000-0000-000000000002', 'f7000000-0000-0000-0000-000000000002', 'a7000000-0000-0000-0000-000000000001');
DO $$ BEGIN
  IF (SELECT employee_number FROM core.person WHERE person_id = 'f7000000-0000-0000-0000-000000000001') <> 'E-100' THEN
    RAISE EXCEPTION 'FAIL 3a: legacy number not adopted';
  END IF;
  IF (SELECT employee_number FROM core.person WHERE person_id = 'f7000000-0000-0000-0000-000000000002') <> '000001' THEN
    RAISE EXCEPTION 'FAIL 3b: number not generated (%)', (SELECT employee_number FROM core.person WHERE person_id = 'f7000000-0000-0000-0000-000000000002');
  END IF;
  RAISE NOTICE 'PASS 3a-b: legacy number adopted once; second employment keeps it; new person numbered 000001';
END $$;
DO $$ BEGIN
  UPDATE core.person SET employee_number = 'E-999' WHERE person_id = 'f7000000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 3c: employee number changed';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'EMPLOYEE_NUMBER_IMMUTABLE%' THEN RAISE EXCEPTION 'FAIL 3c: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 3c: employee number immutable';
END $$;

INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000001', 'f7100000-0000-0000-0000-000000000001'),  -- Jordan A1
  (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000002', 'f7100000-0000-0000-0000-000000000001'),  -- Jordan A2
  (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000003', 'f7100000-0000-0000-0000-000000000003'),  -- Jordan A3 (library board)
  (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000009', 'f7100000-0000-0000-0000-000000000002');  -- the head
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type) VALUES
  (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), 'e7000000-0000-0000-0000-000000000003', 'c7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 0.6, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000002', '[2025-01-01,)', gen_random_uuid(), 'e7000000-0000-0000-0000-000000000005', 'c7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 0.4, false, 'casual'),
  (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000009', '[2020-01-01,)', gen_random_uuid(), 'e7000000-0000-0000-0000-000000000001', 'c7000000-0000-0000-0000-000000000001', 'b7000000-0000-0000-0000-000000000001', 1, true, 'permanent');

-- 4. Employment status worked out from the positions, in the organization's order
DO $$ BEGIN
  IF core.employment_status_type('f7100000-0000-0000-0000-000000000001', '2025-06-01') <> 'casual'
     OR core.employment_status_type('f7100000-0000-0000-0000-000000000001', '2026-06-01') <> 'permanent' THEN
    RAISE EXCEPTION 'FAIL 4a: status not worked out from positions';
  END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'employment.status_precedence', '["casual","permanent","term","auxiliary","seasonal","student"]', '[2026-01-01,)', gen_random_uuid());
  IF core.employment_status_type('f7100000-0000-0000-0000-000000000001', '2026-06-01') <> 'casual' THEN
    RAISE EXCEPTION 'FAIL 4b: tenant precedence ignored';
  END IF;
  RAISE NOTICE 'PASS 4: casual before A1 starts, permanent after; the organization''s precedence applies';
END $$;

-- 5. Probation per bargaining unit, employer probation and trial periods
INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, agreement_id, bargaining_unit, assignment_id, measure, required_amount, counter_code, started_on, rule_source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, '07300000-0000-0000-0000-000000000001', 'f7100000-0000-0000-0000-000000000001', 'agreement', 'IO', 'IO', '07200000-0000-0000-0000-000000000001',
          'hours_paid', 624, 'PROBATION_HOURS', '2026-01-01', 'agreement:IO#1:7.1', '[2026-01-01,)', gen_random_uuid());
INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, agreement_id, bargaining_unit, assignment_id, measure, required_amount, started_on, rule_source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, '07300000-0000-0000-0000-000000000002', 'f7100000-0000-0000-0000-000000000001', 'agreement', 'PT', 'PT', '07200000-0000-0000-0000-000000000002',
          'calendar_months', 6, '2026-01-01', 'agreement:PT#1:9.2', '[2026-01-01,)', gen_random_uuid());
\echo 'PASS 5a: two probations at once, one per bargaining unit'
DO $$ BEGIN
  INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, agreement_id, bargaining_unit, measure, required_amount, started_on, rule_source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'f7100000-0000-0000-0000-000000000001', 'agreement', 'IO', 'IO',
            'calendar_months', 3, '2026-03-01', 'agreement:IO#1:7.1', '[2026-03-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 5b: second open probation in the same unit accepted';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 5b: one open probation per unit';
END $$;
DO $$ BEGIN
  INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, measure, required_amount, started_on, rule_source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'f7100000-0000-0000-0000-000000000001', 'agreement',
            'calendar_months', 3, '2026-03-01', 'x', '[2026-03-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 5c: agreement probation without agreement';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%probation_agreement_named%' THEN RAISE EXCEPTION 'FAIL 5c: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 5c: agreement probation names its agreement';
END $$;
DO $$ BEGIN
  INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, measure, required_amount, started_on, rule_source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'f7100000-0000-0000-0000-000000000001', 'trial',
            'calendar_months', 3, '2026-03-01', 'x', '[2026-03-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 5d: trial period without its position';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%probation_trial_names_position%' THEN RAISE EXCEPTION 'FAIL 5d: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 5d: a trial period names its position';
END $$;
DO $$ BEGIN
  INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, measure, required_amount, started_on, status, outcome_on, rule_source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'f7100000-0000-0000-0000-000000000002', 'employer',
            'calendar_months', 3, '2026-03-01', 'failed', '2026-05-01', 'setting:probation.non_union', '[2026-03-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 5e: failed probation without a reason';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%probation_outcome_reason%' THEN RAISE EXCEPTION 'FAIL 5e: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 5e: failing a probation needs a reason';
END $$;
DO $$ BEGIN
  INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, measure, required_amount, started_on, rule_source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'f7100000-0000-0000-0000-000000000002', 'employer',
            'hours_paid', 500, '2026-03-01', 'setting:probation.non_union', '[2026-03-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 5f: counted probation without a counter';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%probation_counted_measure%' THEN RAISE EXCEPTION 'FAIL 5f: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 5f: an hours-based probation names its counter';
END $$;

-- 6. Rehire eligibility: HR only, with a reason category and a review date; recruiters see a signal only
INSERT INTO core.rehire_reason (tenant_id, code, name_en, category) VALUES
  (current_setting('app.tenant_id')::uuid, 'ABANDON', 'Job abandonment', 'job_abandonment');
DO $$ BEGIN
  INSERT INTO core.rehire_eligibility (tenant_id, person_id, status, reason_code, decided_by, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'f7000000-0000-0000-0000-000000000002', 'not_eligible', 'ABANDON',
            '07a00000-0000-0000-0000-000000000002', '[2026-10-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 6a: restriction without a review date';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%rehire_review_when_restricted%' THEN RAISE EXCEPTION 'FAIL 6a: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 6a: a restriction has a review date';
END $$;
DO $$ BEGIN
  INSERT INTO core.rehire_eligibility (tenant_id, person_id, status, reason_code, review_on, decided_by, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'f7000000-0000-0000-0000-000000000002', 'check_with_hr', 'ABANDON', '2029-04-01',
            '07a00000-0000-0000-0000-000000000002', '[2026-10-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 6b: review date beyond the maximum';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'REHIRE_REVIEW_TOO_FAR%' THEN RAISE EXCEPTION 'FAIL 6b: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 6b: review within the maximum (24 months by default)';
END $$;
DO $$ BEGIN
  INSERT INTO core.rehire_eligibility (tenant_id, person_id, status, reason_code, decided_by, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'f7000000-0000-0000-0000-000000000002', 'eligible', 'ABANDON',
            '07a00000-0000-0000-0000-000000000002', '[2026-10-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 6c: eligible with a restriction reason';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 6c: eligible carries no reason';
END $$;
INSERT INTO core.rehire_eligibility (tenant_id, person_id, status, reason_code, review_on, decided_by, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'f7000000-0000-0000-0000-000000000002', 'check_with_hr', 'ABANDON', '2027-10-01',
          '07a00000-0000-0000-0000-000000000002', '[2026-10-01,)', gen_random_uuid());
DO $$ BEGIN
  IF core.rehire_signal('f7000000-0000-0000-0000-000000000002', '2026-11-01') <> 'check_with_hr'
     OR core.rehire_signal('f7000000-0000-0000-0000-000000000001', '2026-11-01') <> 'none' THEN
    RAISE EXCEPTION 'FAIL 6d: recruiter signal wrong';
  END IF;
  RAISE NOTICE 'PASS 6d: recruiters see "check with HR" or nothing';
END $$;
DO $$ BEGIN
  INSERT INTO core.rehire_reason (tenant_id, code, name_en, category) VALUES (current_setting('app.tenant_id')::uuid, 'MEDLEAVE', 'Left on medical leave', 'medical');
  RAISE EXCEPTION 'FAIL 6e: protected-ground category accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 6e: reason categories are a fixed list with no protected grounds';
END $$;

-- 7. Light mode is gone
RESET ROLE;
DO $$ BEGIN
  UPDATE platform.tenant SET org_mode = 'light' WHERE tenant_id = '71111111-1111-1111-1111-111111111111';
  RAISE EXCEPTION 'FAIL 7: light mode accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 7: org_mode is always position';
END $$;
SET ROLE cando_app;
SELECT set_config('app.tenant_id', '71111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- 8. A vacant manager position: approvals go to the next filled position up
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM core.next_filled_position_up('e7000000-0000-0000-0000-000000000003', '2026-06-01');
  IF r.position_id <> 'e7000000-0000-0000-0000-000000000001' OR r.levels_up <> 2
     OR r.holder_assignment_ids <> ARRAY['07200000-0000-0000-0000-000000000009'::uuid] THEN
    RAISE EXCEPTION 'FAIL 8: got % at % levels', r.position_id, r.levels_up;
  END IF;
  RAISE NOTICE 'PASS 8: STAFF -> MGR (vacant) -> HEAD (filled), two levels up';
END $$;

-- 9. Units without a head
DO $$ BEGIN
  IF (SELECT array_agg(code ORDER BY code) FROM core.org_units_without_head('2026-06-01')) <> ARRAY['LIB'] THEN
    RAISE EXCEPTION 'FAIL 9: wrong units without head';
  END IF;
  RAISE NOTICE 'PASS 9: Library services listed as having no head; Recreation has one';
END $$;

-- 10. Reporting across employers only under a shared-services arrangement
DO $$ BEGIN
  INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status)
    VALUES (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000004', '[2026-01-01,)', gen_random_uuid(), 'd7000000-0000-0000-0000-000000000001',
            'c7000000-0000-0000-0000-000000000002', 'b7000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 1, 'casual', 'active');
  RAISE EXCEPTION 'FAIL 10a: cross-employer line accepted without an arrangement';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'CROSS_EMPLOYER_NO_ARRANGEMENT%' THEN RAISE EXCEPTION 'FAIL 10a: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 10a: library position cannot report to a City position without an arrangement';
END $$;
INSERT INTO core.shared_services_arrangement (tenant_id, arrangement_id, code, serving_entity_id, served_entity_id, purposes, privacy_basis, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'CITY-LIB-2026', 'a7000000-0000-0000-0000-000000000001', 'a7000000-0000-0000-0000-000000000002',
          ARRAY['supervision'], 'Shared services agreement s.4', '[2026-01-01,)', gen_random_uuid());
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status)
  VALUES (current_setting('app.tenant_id')::uuid, 'e7000000-0000-0000-0000-000000000004', '[2026-01-01,)', gen_random_uuid(), 'd7000000-0000-0000-0000-000000000001',
          'c7000000-0000-0000-0000-000000000002', 'b7000000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000001', 1, 'casual', 'active');
\echo 'PASS 10b: accepted once the arrangement is recorded'
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type) VALUES
  (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000003', '[2026-01-01,)', gen_random_uuid(), 'e7000000-0000-0000-0000-000000000004', 'c7000000-0000-0000-0000-000000000002', 'b7000000-0000-0000-0000-000000000001', 0.2, true, 'casual');
INSERT INTO core.relationship_type (tenant_id, code, name_en, is_line, authorities, cross_employer_purpose) VALUES
  (current_setting('app.tenant_id')::uuid, 'functional', 'Functional lead', false, '{"approveTime": true}', 'supervision'),
  (current_setting('app.tenant_id')::uuid, 'hrbp', 'HR business partner', false, '{"review": "contribute"}', 'hr_services')
ON CONFLICT DO NOTHING;
INSERT INTO core.assignment_relationship (tenant_id, assignment_id, related_assignment_id, kind, valid_period, change_set_id, relationship_type_code)
  VALUES (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000003', '07200000-0000-0000-0000-000000000009', 'dotted', '[2026-01-01,)', gen_random_uuid(), 'functional');
DO $$ BEGIN
  INSERT INTO core.assignment_relationship (tenant_id, assignment_id, related_assignment_id, kind, valid_period, change_set_id, relationship_type_code)
    VALUES (current_setting('app.tenant_id')::uuid, '07200000-0000-0000-0000-000000000003', '07200000-0000-0000-0000-000000000009', 'dotted', '[2026-01-01,)', gen_random_uuid(), 'hrbp');
  RAISE EXCEPTION 'FAIL 10c: HR business partner across employers without hr_services';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'CROSS_EMPLOYER_NO_ARRANGEMENT%' THEN RAISE EXCEPTION 'FAIL 10c: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 10c: functional relationship covered by supervision; HR partner needs hr_services';
END $$;

-- 11. Position control overrides: finance approves, never the requester
INSERT INTO platform.change_set (tenant_id, change_set_id, number, kind, reason_code, effective_date, source, status, requested_by)
  VALUES (current_setting('app.tenant_id')::uuid, '07400000-0000-0000-0000-000000000001', 1, 'hire', 'HIRE', '2026-11-01', 'ui_form', 'pending_approval',
          '07a00000-0000-0000-0000-000000000001');
DO $$ BEGIN
  INSERT INTO core.position_control_override (tenant_id, change_set_id, position_id, check_kind, amount_over, reason, status, finance_approver, finance_decided_at)
    VALUES (current_setting('app.tenant_id')::uuid, '07400000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000003', 'budget', 4200,
            'Frontline coverage for winter programs', 'approved', '07a00000-0000-0000-0000-000000000001', now());
  RAISE EXCEPTION 'FAIL 11a: requester approved their own override';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 11a: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 11a: requester cannot approve the override';
END $$;
DO $$ BEGIN
  INSERT INTO core.position_control_override (tenant_id, change_set_id, position_id, check_kind, amount_over, reason, status)
    VALUES (current_setting('app.tenant_id')::uuid, '07400000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000003', 'budget', 4200,
            'Frontline coverage for winter programs', 'approved');
  RAISE EXCEPTION 'FAIL 11b: approved without a finance approver';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 11b: approval names the finance approver';
END $$;
INSERT INTO core.position_control_override (tenant_id, change_set_id, position_id, check_kind, amount_over, reason, status, finance_approver, finance_decided_at)
  VALUES (current_setting('app.tenant_id')::uuid, '07400000-0000-0000-0000-000000000001', 'e7000000-0000-0000-0000-000000000003', 'budget', 4200,
          'Frontline coverage for winter programs', 'approved', '07a00000-0000-0000-0000-000000000005', now());
\echo 'PASS 11c: finance approval with a written reason recorded'

-- 12. Several titles per position, each with its purpose
INSERT INTO finance.funding_source (tenant_id, funding_source_id, code, funder_name, legal_entity_id, valid_period, status, eligible_categories, fallback_segments) VALUES
  (current_setting('app.tenant_id')::uuid, '07500000-0000-0000-0000-000000000001', 'YOUTH-GRANT', 'Province', 'a7000000-0000-0000-0000-000000000001', '[2026-01-01,)', 'active', ARRAY['salary'], '{}'),
  (current_setting('app.tenant_id')::uuid, '07500000-0000-0000-0000-000000000002', 'FOUNDATION', 'Foundation', 'a7000000-0000-0000-0000-000000000001', '[2026-01-01,)', 'active', ARRAY['salary'], '{}');
INSERT INTO core.position_title (tenant_id, title_id, position_id, purpose, funding_source_id, title_en, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'e7000000-0000-0000-0000-000000000003', 'working', NULL, 'Youth Program Coordinator, North', '[2026-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'e7000000-0000-0000-0000-000000000003', 'funder', '07500000-0000-0000-0000-000000000001', 'Youth Program Supervisor', '[2026-01-01,)', gen_random_uuid());
DO $$ BEGIN
  INSERT INTO core.position_title (tenant_id, title_id, position_id, purpose, title_en, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'e7000000-0000-0000-0000-000000000003', 'funder', 'No funder named', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 12a: funder title without its funder';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 12a: a funder title names its funding source';
END $$;
DO $$ BEGIN
  INSERT INTO core.position_title (tenant_id, title_id, position_id, purpose, title_en, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'e7000000-0000-0000-0000-000000000003', 'working', 'Second working title', '[2026-06-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 12b: two working titles at once';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 12b: one working title at a time';
END $$;
DO $$ BEGIN
  IF (SELECT title FROM core.position_title_for('e7000000-0000-0000-0000-000000000003', 'funder', '2026-06-01', 'en', '07500000-0000-0000-0000-000000000001')) <> 'Youth Program Supervisor'
     OR (SELECT title FROM core.position_title_for('e7000000-0000-0000-0000-000000000003', 'funder', '2026-06-01', 'en', '07500000-0000-0000-0000-000000000002')) <> 'Youth Program Coordinator, North'
     OR (SELECT origin FROM core.position_title_for('e7000000-0000-0000-0000-000000000002', 'working', '2026-06-01', 'en')) <> 'job'
     OR (SELECT title FROM core.position_title_for('e7000000-0000-0000-0000-000000000002', 'working', '2026-06-01', 'fr')) <> 'Coordonnateur de programme' THEN
    RAISE EXCEPTION 'FAIL 12c: title fallback wrong';
  END IF;
  RAISE NOTICE 'PASS 12c: funder title, else working title, else the job title (in French when asked)';
END $$;

-- 13. Approvals HR and payroll must give; no self-approval; communicated changes
INSERT INTO core.change_reason (tenant_id, code, name_en, category) VALUES
  (current_setting('app.tenant_id')::uuid, 'TERM-RES', 'Resignation', 'termination'),
  (current_setting('app.tenant_id')::uuid, 'PROMO', 'Promotion', 'promotion');
INSERT INTO platform.change_set (tenant_id, change_set_id, number, kind, reason_code, effective_date, source, status, requested_by)
  VALUES (current_setting('app.tenant_id')::uuid, '07400000-0000-0000-0000-000000000002', 2, 'separation', 'TERM-RES', '2026-11-15', 'ui_form', 'pending_approval',
          '07a00000-0000-0000-0000-000000000001');
DO $$ BEGIN
  IF (SELECT reason_category FROM platform.change_set WHERE change_set_id = '07400000-0000-0000-0000-000000000002') <> 'termination' THEN
    RAISE EXCEPTION 'FAIL 13a: reason category not copied';
  END IF;
  UPDATE platform.change_set SET status = 'approved' WHERE change_set_id = '07400000-0000-0000-0000-000000000002';
  RAISE EXCEPTION 'FAIL 13a: termination approved without HR';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 13a: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 13a: a termination always needs HR';
END $$;
DO $$ BEGIN
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (current_setting('app.tenant_id')::uuid, 'change_set', '07400000-0000-0000-0000-000000000002', 1, 'approved', '07a00000-0000-0000-0000-000000000001', now(), 'hr');
  RAISE EXCEPTION 'FAIL 13b: requester approved their own change';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 13b: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 13b: no self-approval';
END $$;
INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
  VALUES (current_setting('app.tenant_id')::uuid, 'change_set', '07400000-0000-0000-0000-000000000002', 1, 'approved', '07a00000-0000-0000-0000-000000000002', now(), 'hr');
UPDATE platform.change_set SET status = 'approved' WHERE change_set_id = '07400000-0000-0000-0000-000000000002';
\echo 'PASS 13c: approved after HR approves'

-- back-dated promotion reaching a finalized pay period, more than one month back
INSERT INTO platform.change_set (tenant_id, change_set_id, number, kind, reason_code, effective_date, source, status, requested_by, requested_at, reaches_finalized_pay)
  VALUES (current_setting('app.tenant_id')::uuid, '07400000-0000-0000-0000-000000000003', 3, 'job_change', 'PROMO', '2026-06-01', 'ui_form', 'pending_approval',
          '07a00000-0000-0000-0000-000000000001', '2026-10-24 10:00-07', true);
INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
  (current_setting('app.tenant_id')::uuid, 'change_set', '07400000-0000-0000-0000-000000000003', 1, 'approved', '07a00000-0000-0000-0000-000000000002', now(), 'hr'),
  (current_setting('app.tenant_id')::uuid, 'change_set', '07400000-0000-0000-0000-000000000003', 2, 'approved', '07a00000-0000-0000-0000-000000000004', now(), 'payroll');
DO $$ BEGIN
  UPDATE platform.change_set SET status = 'approved' WHERE change_set_id = '07400000-0000-0000-0000-000000000003';
  RAISE EXCEPTION 'FAIL 13d: four months back approved with one HR approval';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'APPROVALS_MISSING: needs 2 HR and 1 payroll%' THEN RAISE EXCEPTION 'FAIL 13d: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 13d: more than one month back needs two HR approvals and payroll';
END $$;
INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
  VALUES (current_setting('app.tenant_id')::uuid, 'change_set', '07400000-0000-0000-0000-000000000003', 3, 'approved', '07a00000-0000-0000-0000-000000000003', now(), 'hr');
UPDATE platform.change_set SET status = 'approved' WHERE change_set_id = '07400000-0000-0000-0000-000000000003';
\echo 'PASS 13e: approved with two HR approvals and payroll'

-- back-dated less than a month: one HR approval and payroll
INSERT INTO platform.change_set (tenant_id, change_set_id, number, kind, reason_code, effective_date, source, status, requested_by, requested_at, reaches_finalized_pay)
  VALUES (current_setting('app.tenant_id')::uuid, '07400000-0000-0000-0000-000000000004', 4, 'job_change', 'PROMO', '2026-10-10', 'ui_form', 'pending_approval',
          '07a00000-0000-0000-0000-000000000001', '2026-10-24 10:00-07', true);
INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
  VALUES (current_setting('app.tenant_id')::uuid, 'change_set', '07400000-0000-0000-0000-000000000004', 1, 'approved', '07a00000-0000-0000-0000-000000000002', now(), 'hr');
DO $$ BEGIN
  UPDATE platform.change_set SET status = 'approved' WHERE change_set_id = '07400000-0000-0000-0000-000000000004';
  RAISE EXCEPTION 'FAIL 13f: back-dated change approved without payroll';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'APPROVALS_MISSING: needs 1 HR and 1 payroll%' THEN RAISE EXCEPTION 'FAIL 13f: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 13f: within a month: one HR approval and payroll';
END $$;
DO $$ BEGIN
  INSERT INTO platform.change_set (tenant_id, change_set_id, number, kind, reason_code, effective_date, source, status, requested_by)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 5, 'separation', 'TERM-RES', '2026-12-01', 'api', 'approved',
            '07a00000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'FAIL 13g: termination inserted as approved';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 13g: cannot insert a termination already approved';
END $$;
DO $$ BEGIN
  UPDATE platform.change_set SET communicated_at = now(), communicated_by = '07a00000-0000-0000-0000-000000000002'
    WHERE change_set_id = '07400000-0000-0000-0000-000000000004';
  RAISE EXCEPTION 'FAIL 13h: communicated before approval';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 13h: a change is communicated only after approval';
END $$;
DO $$ BEGIN
  IF platform.employee_sees_change('07400000-0000-0000-0000-000000000002', '07a00000-0000-0000-0000-000000000006') THEN
    RAISE EXCEPTION 'FAIL 13i: employee sees an approved change not yet communicated';
  END IF;
  UPDATE platform.change_set SET communicated_at = now(), communicated_by = '07a00000-0000-0000-0000-000000000002', communication_method = 'in_person'
    WHERE change_set_id = '07400000-0000-0000-0000-000000000002';
  IF NOT platform.employee_sees_change('07400000-0000-0000-0000-000000000002', '07a00000-0000-0000-0000-000000000006')
     OR NOT platform.employee_sees_change('07400000-0000-0000-0000-000000000004', '07a00000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL 13i: visibility after communication or for the requester';
  END IF;
  RAISE NOTICE 'PASS 13i: employee sees it once communicated; the requester always sees their own';
END $$;

-- 14. Overpayments: held, never recovered without a basis
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by)
  VALUES (current_setting('app.tenant_id')::uuid, '07600000-0000-0000-0000-000000000001', 'person', 'f7000000-0000-0000-0000-000000000001', 'overpayment_authorization',
          'restricted', 'payroll', 'docs/x', 'h', 'application/pdf', '07a00000-0000-0000-0000-000000000004');
INSERT INTO payroll.overpayment (tenant_id, overpayment_id, employment_id, source, gross_amount, identified_on)
  VALUES (current_setting('app.tenant_id')::uuid, '07700000-0000-0000-0000-000000000001', 'f7100000-0000-0000-0000-000000000001', 'retro', 312.50, '2026-10-24');
DO $$ BEGIN
  INSERT INTO payroll.one_time_item (tenant_id, employment_id, pay_code, amount, pay_on_or_after, source, status, overpayment_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'f7100000-0000-0000-0000-000000000001', 'OVP-RECOVERY', 100, '2026-11-06', 'manual', 'pending',
            '07700000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'FAIL 14a: recovery while held';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'OVERPAYMENT_NOT_AUTHORIZED%' THEN RAISE EXCEPTION 'FAIL 14a: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 14a: nothing is recovered while the overpayment is held';
END $$;
DO $$ BEGIN
  UPDATE payroll.overpayment SET status = 'authorized', recovery_basis = 'employee_authorization' WHERE overpayment_id = '07700000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 14b: authorized without the signed authorization';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%recovery_needs_basis%' THEN RAISE EXCEPTION 'FAIL 14b: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 14b: authorization needs the signed document, its date and the schedule';
END $$;
DO $$ BEGIN
  UPDATE payroll.overpayment SET status = 'authorized', recovery_basis = 'jurisdiction_rule', basis_ref = 'ES:XX s.1', schedule = '[{"payOnOrAfter":"2026-11-06","amount":"312.50"}]'
    WHERE overpayment_id = '07700000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 14c: rule-based recovery under the default setting';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'OVERPAYMENT_NEEDS_AUTHORIZATION%' THEN RAISE EXCEPTION 'FAIL 14c: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 14c: by default only the employee''s written authorization allows recovery';
END $$;
UPDATE payroll.overpayment SET status = 'authorized', recovery_basis = 'employee_authorization', authorization_document_id = '07600000-0000-0000-0000-000000000001',
       authorized_on = '2026-10-28', schedule = '[{"payOnOrAfter":"2026-11-06","amount":"156.25"},{"payOnOrAfter":"2026-11-20","amount":"156.25"}]'
  WHERE overpayment_id = '07700000-0000-0000-0000-000000000001';
INSERT INTO payroll.one_time_item (tenant_id, employment_id, pay_code, amount, pay_on_or_after, source, status, overpayment_id, allocation)
  VALUES (current_setting('app.tenant_id')::uuid, 'f7100000-0000-0000-0000-000000000001', 'OVP-RECOVERY', 156.25, '2026-11-06', 'manual', 'pending',
          '07700000-0000-0000-0000-000000000001', 'earnings_share');
\echo 'PASS 14d: recovery item accepted after written authorization'

-- 15. Agreements against employment standards
INSERT INTO core.agreement (tenant_id, agreement_id, name, union_name, jurisdiction, status, bargaining_employer_entity_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'IO', 'Inside/outside', 'Test union', 'BC', 'in_force', 'a7000000-0000-0000-0000-000000000001');
INSERT INTO core.agreement_version (tenant_id, agreement_id, version, effective_from, rules, content_sha256, status, prepared_by) VALUES
  (current_setting('app.tenant_id')::uuid, 'IO', 1, '2026-01-01', '{"standardsComparison":{"method":"per_hour"}}', 'h1', 'verified', 'cando'),
  (current_setting('app.tenant_id')::uuid, 'IO', 2, '2027-01-01', '{"standardsComparison":{"method":"per_hour"}}', 'h2', 'verified', 'customer');
INSERT INTO core.agreement_standards_finding (tenant_id, agreement_id, version, jurisdiction, standard_code, agreement_ref, finding, comparison) VALUES
  (current_setting('app.tenant_id')::uuid, 'IO', 1, 'BC', 'overtime.daily', '15.2', 'below_law_replaceable', 'per_hour'),
  (current_setting('app.tenant_id')::uuid, 'IO', 1, 'BC', 'minimum_wage', '22.1', 'meets_or_exceeds', 'per_hour'),
  (current_setting('app.tenant_id')::uuid, 'IO', 2, 'BC', 'vacation.entitlement', '18.1', 'not_verified', 'per_hour');
DO $$ BEGIN
  UPDATE core.agreement_version SET status = 'active' WHERE agreement_id = 'IO' AND version = 1;
  RAISE EXCEPTION 'FAIL 15a: activated with an unapproved below-law finding';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'AGREEMENT_BELOW_LAW_NOT_APPROVED%' THEN RAISE EXCEPTION 'FAIL 15a: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 15a: below-law part blocks activation until HR and payroll approve';
END $$;
DO $$ BEGIN
  UPDATE core.agreement_standards_finding SET hr_approved_by = '07a00000-0000-0000-0000-000000000002', hr_approved_at = now(),
         payroll_approved_by = '07a00000-0000-0000-0000-000000000002', payroll_approved_at = now()
    WHERE agreement_id = 'IO' AND version = 1 AND standard_code = 'overtime.daily';
  RAISE EXCEPTION 'FAIL 15b: one person approved as both HR and payroll';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%two_people_approve%' THEN RAISE EXCEPTION 'FAIL 15b: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 15b: two different people approve';
END $$;
DO $$ BEGIN
  UPDATE core.agreement_standards_finding SET hr_approved_by = '07a00000-0000-0000-0000-000000000002', hr_approved_at = now()
    WHERE agreement_id = 'IO' AND version = 1 AND standard_code = 'minimum_wage';
  RAISE EXCEPTION 'FAIL 15c: approval recorded on a finding that needs none';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 15c: approvals only on below-law findings';
END $$;
UPDATE core.agreement_standards_finding SET hr_approved_by = '07a00000-0000-0000-0000-000000000002', hr_approved_at = now(),
       payroll_approved_by = '07a00000-0000-0000-0000-000000000004', payroll_approved_at = now()
  WHERE agreement_id = 'IO' AND version = 1 AND standard_code = 'overtime.daily';
UPDATE core.agreement_version SET status = 'active' WHERE agreement_id = 'IO' AND version = 1;
\echo 'PASS 15d: activated after both approvals'
DO $$ BEGIN
  UPDATE core.agreement_version SET status = 'active' WHERE agreement_id = 'IO' AND version = 2;
  RAISE EXCEPTION 'FAIL 15e: activated with an unverified standard';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'RULE_NOT_VERIFIED%' THEN RAISE EXCEPTION 'FAIL 15e: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 15e: an unverified jurisdiction blocks activation';
END $$;

-- 16. Bank account changes
INSERT INTO payroll.bank_account (tenant_id, bank_account_id, employment_id, institution, transit, account_enc, account_last3, split_type, priority, valid_period, key_id)
  VALUES (current_setting('app.tenant_id')::uuid, '07800000-0000-0000-0000-000000000001', 'f7100000-0000-0000-0000-000000000001', '001', '12345', '\x00', '789', 'remainder', 1, '[2026-11-01,)', 'k');
DO $$ BEGIN
  INSERT INTO payroll.bank_change_request (tenant_id, employment_id, bank_account_id, requested_by_user, channel)
    VALUES (current_setting('app.tenant_id')::uuid, 'f7100000-0000-0000-0000-000000000001', '07800000-0000-0000-0000-000000000001', '07a00000-0000-0000-0000-000000000006', 'self_service');
  RAISE EXCEPTION 'FAIL 16a: self-service change without a second factor';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%self_service_needs_second_factor%' THEN RAISE EXCEPTION 'FAIL 16a: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 16a: second factor required';
END $$;
INSERT INTO payroll.bank_change_request (tenant_id, request_id, employment_id, bank_account_id, requested_by_user, channel, reauthenticated_at)
  VALUES (current_setting('app.tenant_id')::uuid, '07900000-0000-0000-0000-000000000001', 'f7100000-0000-0000-0000-000000000001', '07800000-0000-0000-0000-000000000001',
          '07a00000-0000-0000-0000-000000000006', 'self_service', now());
DO $$ BEGIN
  IF (SELECT hold_until - created_at FROM payroll.bank_change_request WHERE request_id = '07900000-0000-0000-0000-000000000001') <> interval '72 hours' THEN
    RAISE EXCEPTION 'FAIL 16b: hold not set from the setting';
  END IF;
  RAISE NOTICE 'PASS 16b: 72-hour hold set';
END $$;
DO $$ BEGIN
  UPDATE payroll.bank_change_request SET status = 'approved', verified_by = '07a00000-0000-0000-0000-000000000002', verified_at = now(),
         verification_method = 'video', id_type_seen = 'drivers_licence' WHERE request_id = '07900000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 16c: approved before notices';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'BANK_CHANGE_NOTICE_MISSING%' THEN RAISE EXCEPTION 'FAIL 16c: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 16c: notices to the contacts on file come first';
END $$;
UPDATE payroll.bank_change_request SET notices_sent_at = now() WHERE request_id = '07900000-0000-0000-0000-000000000001';
DO $$ BEGIN
  UPDATE payroll.bank_change_request SET status = 'approved' WHERE request_id = '07900000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 16d: approved without a live check';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'BANK_CHANGE_NOT_VERIFIED%' THEN RAISE EXCEPTION 'FAIL 16d: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 16d: live video or phone check with photo ID required';
END $$;
DO $$ BEGIN
  UPDATE payroll.bank_change_request SET status = 'approved', verified_by = '07a00000-0000-0000-0000-000000000002', verified_at = now(),
         verification_method = 'phone', phone_on_file_used = false, id_type_seen = 'drivers_licence' WHERE request_id = '07900000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 16e: phone number not on file accepted';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'BANK_CHANGE_PHONE_NOT_ON_FILE%' THEN RAISE EXCEPTION 'FAIL 16e: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 16e: HR calls the number already on file';
END $$;
DO $$ BEGIN
  UPDATE payroll.bank_change_request SET status = 'approved', verified_by = '07a00000-0000-0000-0000-000000000006', verified_at = now(),
         verification_method = 'video', id_type_seen = 'passport' WHERE request_id = '07900000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 16f: requester verified their own change';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 16f: the verifier is not the requester';
END $$;
UPDATE payroll.bank_change_request SET status = 'approved', verified_by = '07a00000-0000-0000-0000-000000000002', verified_at = now(),
       verification_method = 'video', id_type_seen = 'drivers_licence' WHERE request_id = '07900000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF payroll.bank_account_usable('07800000-0000-0000-0000-000000000001') THEN RAISE EXCEPTION 'FAIL 16g: usable before the hold ends'; END IF;
  UPDATE payroll.bank_change_request SET status = 'in_effect' WHERE request_id = '07900000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 16g: in effect during the hold';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'BANK_CHANGE_ON_HOLD%' THEN RAISE EXCEPTION 'FAIL 16g: %', SQLERRM; END IF;
  RAISE NOTICE 'PASS 16g: approved, but pay goes there only after the hold';
END $$;
INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'bank_change.hr_live_verification', 'false', '[2026-01-01,)', gen_random_uuid());
INSERT INTO payroll.bank_change_request (tenant_id, employment_id, bank_account_id, requested_by_user, channel, reauthenticated_at, notices_sent_at, status)
  VALUES (current_setting('app.tenant_id')::uuid, 'f7100000-0000-0000-0000-000000000001', '07800000-0000-0000-0000-000000000001',
          '07a00000-0000-0000-0000-000000000006', 'self_service', now(), now(), 'approved');
\echo 'PASS 16h: an organization that switches off live verification still keeps the second factor, notices and hold'

-- 17. Self-identification categories
DO $$ BEGIN
  INSERT INTO core.self_id_category (tenant_id, category_code, origin, name_en, question_en, purpose_en, answer_options, consent_text_version)
    VALUES (current_setting('app.tenant_id')::uuid, 'VET', 'tenant', 'Veterans', 'Are you a veteran?', 'Program planning',
            '[{"code":"yes","en":"Yes"},{"code":"no","en":"No"}]', 'v1');
  RAISE EXCEPTION 'FAIL 17a: category without a decline option';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 17a: every category offers "prefer not to answer"';
END $$;
DO $$ BEGIN
  INSERT INTO core.self_id_category (tenant_id, category_code, origin, name_en, question_en, purpose_en, answer_options, official_group, consent_text_version)
    VALUES (current_setting('app.tenant_id')::uuid, 'MY-WOMEN', 'tenant', 'Women', 'Q', 'P',
            '[{"code":"yes"},{"code":"prefer_not_to_answer"}]', 'ee_women', 'v1');
  RAISE EXCEPTION 'FAIL 17b: tenant category mapped to an official group';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 17b: only CanDo standard categories feed government reports';
END $$;
INSERT INTO core.self_id_category (tenant_id, category_code, origin, name_en, question_en, purpose_en, answer_options, official_group, consent_text_version) VALUES
  (current_setting('app.tenant_id')::uuid, 'EE_INDIGENOUS', 'cando_standard', 'Indigenous peoples', 'Q', 'P', '[{"code":"yes"},{"code":"no"},{"code":"prefer_not_to_answer"}]', 'ee_indigenous', 'v1'),
  (current_setting('app.tenant_id')::uuid, 'VET', 'tenant', 'Veterans', 'Are you a veteran?', 'Program planning', '[{"code":"yes"},{"code":"no"},{"code":"prefer_not_to_answer"}]', NULL, 'v1');
INSERT INTO core.self_id_consent (tenant_id, person_id, category_code, consent_given_at, consent_text_version)
  VALUES (current_setting('app.tenant_id')::uuid, 'f7000000-0000-0000-0000-000000000001', 'VET', now(), 'v1');
\echo 'PASS 17c: standard and own categories, consent per category'

-- 18. Support access: time-limited and approved by the organization
DO $$ BEGIN
  INSERT INTO platform.support_access_grant (tenant_id, requested_by, purpose, valid_period, status)
    VALUES (current_setting('app.tenant_id')::uuid, 'cando-support:alex', 'Ticket 123', tstzrange(now(), now() + interval '2 days'), 'approved');
  RAISE EXCEPTION 'FAIL 18a: approved without an approver';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 18a: the organization approves support access';
END $$;
DO $$ BEGIN
  INSERT INTO platform.support_access_grant (tenant_id, requested_by, purpose, valid_period)
    VALUES (current_setting('app.tenant_id')::uuid, 'cando-support:alex', 'Ticket 123', tstzrange(now(), now() + interval '10 days'));
  RAISE EXCEPTION 'FAIL 18b: grant longer than seven days';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 18b: at most seven days per grant';
END $$;

-- 19. Tenant isolation
SELECT set_config('app.tenant_id', '72222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM platform.tenant_setting) + (SELECT count(*) FROM core.rehire_eligibility) + (SELECT count(*) FROM core.position_title)
     + (SELECT count(*) FROM payroll.overpayment) + (SELECT count(*) FROM core.probation) + (SELECT count(*) FROM payroll.bank_change_request) <> 0 THEN
    RAISE EXCEPTION 'FAIL 19a: another tenant sees rows';
  END IF;
  IF platform.setting('72222222-2222-2222-2222-222222222222', 'positions.over_budget') #>> '{}' <> 'finance_approval' THEN
    RAISE EXCEPTION 'FAIL 19a: another tenant''s override leaked';
  END IF;
  RAISE NOTICE 'PASS 19a: other tenant sees none of the rows and gets CanDo''s defaults';
END $$;
DO $$ BEGIN
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES ('71111111-1111-1111-1111-111111111111', 'positions.over_budget', '"finance_approval"', '[2030-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 19b: cross-tenant write accepted';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS 19b: cross-tenant write rejected';
END $$;
RESET ROLE;
\echo 'schema_0007_smoke: all checks passed'
