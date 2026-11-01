-- Smoke test for schema/0005_total_rewards.sql (docs/19): public wages and the practice catalogue, competency
-- frameworks, targets, assessments and gaps, job evaluation plans and evaluations (the sample plan's worked example),
-- survey editions and market data, the licence policy, pricing runs, pay structures, survey submissions with
-- pseudonyms, practice benchmarking, tenant isolation and row-level security on every new table.
-- Run from the repository root after every migration, 0001 to 0008 (CI, after the 0004 smoke test), or on a scratch
-- database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0005_smoke.sql
-- It reads rules/job-evaluation/sample-point-factor-plan.json and inserts test rows; run `supabase db reset` afterwards.
\set ON_ERROR_STOP 1
\set plan `cat rules/job-evaluation/sample-point-factor-plan.json`

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, comp, talent, benefits TO cando_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core, comp, talent, benefits TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref, platform TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA platform, core, ref, comp, talent TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('51111111-1111-1111-1111-111111111111', 'Rewards Test Tenant'),
  ('52222222-2222-2222-2222-222222222222', 'Other Rewards Tenant')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------------
-- Loader (owner): NOC 2021 items if the 0004 smoke test has not loaded them, public wages, practice catalogue
-- ---------------------------------------------------------------------------------
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM ref.code_scheme_version WHERE version_id = 'NOC-2021-1.0') THEN
    INSERT INTO ref.code_scheme (scheme_code, name_en, publisher, country, purpose, structure, code_pattern)
      VALUES ('NOC', 'National Occupational Classification', 'Statistics Canada', 'CA', 'occupation', 'hierarchical', '^[0-9]{1,5}$')
      ON CONFLICT DO NOTHING;
    INSERT INTO ref.code_scheme_version (version_id, scheme_code, label, status, assignable_levels)
      VALUES ('NOC-2021-1.0', 'NOC', '2021 Version 1.0', 'loading', ARRAY['unit_group']);
    INSERT INTO ref.code_item (version_id, code, level, depth, parent_code, title_en, attributes) VALUES
      ('NOC-2021-1.0', '1', 'broad_category', 1, NULL, 'Business, finance and administration occupations', '{}'),
      ('NOC-2021-1.0', '13', 'major_group', 2, '1', 'Administrative occupations and transportation logistics occupations', '{"teer": 3}'),
      ('NOC-2021-1.0', '131', 'sub_major_group', 3, '13', 'Administrative occupations', '{"teer": 3}'),
      ('NOC-2021-1.0', '1310', 'minor_group', 4, '131', 'Administrative, property and payroll officers', '{"teer": 3}'),
      ('NOC-2021-1.0', '13102', 'unit_group', 5, '1310', 'Payroll administrators', '{"teer": 3}'),
      ('NOC-2021-1.0', '4', 'broad_category', 1, NULL, 'Occupations in education, law and social, community and government services', '{}'),
      ('NOC-2021-1.0', '42', 'major_group', 2, '4', 'Front-line public protection services and paraprofessional occupations', '{"teer": 2}'),
      ('NOC-2021-1.0', '422', 'sub_major_group', 3, '42', 'Paraprofessional occupations in legal, social, community and education services', '{"teer": 2}'),
      ('NOC-2021-1.0', '4220', 'minor_group', 4, '422', 'Paraprofessional occupations in legal, social, community and education services', '{"teer": 2}'),
      ('NOC-2021-1.0', '42201', 'unit_group', 5, '4220', 'Social and community service workers', '{"teer": 2}');
    UPDATE ref.code_scheme_version SET status = 'published', content_sha256 = 'smoke-test', item_count = 10, loaded_at = now()
      WHERE version_id = 'NOC-2021-1.0';
  END IF;
END $$;

INSERT INTO ref.public_wage_edition (edition_id, publisher, name_en, noc_version_id, reference_period, effective_date, released_on, licence, status, statistic_columns)
  VALUES ('TEST-WAGES-2025', 'Employment and Social Development Canada', 'Job Bank wages (test rows)', 'NOC-2021-1.0', '2023-2024',
          '2024-01-01', '2025-11-19', 'Open Government Licence - Canada', 'loading', '{"p10": "low", "p50": "median", "p90": "high"}');
INSERT INTO ref.public_wage (edition_id, noc_version_id, noc_code, geo_code, geo_level, geo_name_en, basis, low, median, high, data_source) VALUES
  ('TEST-WAGES-2025', 'NOC-2021-1.0', '42201', 'CA', 'national', 'Canada', 'hourly', 19.00, 26.00, 36.06, 'Labour Force Survey'),
  ('TEST-WAGES-2025', 'NOC-2021-1.0', '42201', '59', 'province', 'British Columbia', 'hourly', 20.00, 27.50, 38.00, 'Labour Force Survey'),
  ('TEST-WAGES-2025', 'NOC-2021-1.0', '13102', 'CA', 'national', 'Canada', 'hourly', 21.00, 30.00, 41.00, 'Labour Force Survey');

-- 1. Public wages: order of low, median and high; real NOC codes; frozen once published
DO $$ BEGIN
  INSERT INTO ref.public_wage (edition_id, noc_version_id, noc_code, geo_code, geo_level, geo_name_en, basis, low, median, high)
    VALUES ('TEST-WAGES-2025', 'NOC-2021-1.0', '13102', '59', 'province', 'British Columbia', 'hourly', 31.00, 30.00, 41.00);
  RAISE EXCEPTION 'FAIL 1a';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 1a: low above median refused';
END $$;
DO $$ BEGIN
  INSERT INTO ref.public_wage (edition_id, noc_version_id, noc_code, geo_code, geo_level, geo_name_en, basis, median)
    VALUES ('TEST-WAGES-2025', 'NOC-2021-1.0', '99999', 'CA', 'national', 'Canada', 'hourly', 30.00);
  RAISE EXCEPTION 'FAIL 1b';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PASS 1b: NOC code must exist in the NOC version';
END $$;
UPDATE ref.public_wage_edition SET status = 'published' WHERE edition_id = 'TEST-WAGES-2025';
DO $$ BEGIN
  UPDATE ref.public_wage SET median = 31.00 WHERE edition_id = 'TEST-WAGES-2025' AND noc_code = '13102';
  RAISE EXCEPTION 'FAIL 1c';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'PUBLIC_WAGE_EDITION_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 1c: published wage edition is frozen';
END $$;

INSERT INTO ref.reward_practice (practice_code, catalogue_version, category, name_en, name_fr, value_type, unit, richer_when, enum_values, own_value_source) VALUES
  ('STD_WAIT_DAYS', '2026.10', 'life_disability', 'Short-term disability waiting period (illness)', 'Délai de carence de l’invalidité de courte durée (maladie)', 'days', 'days', 'lower', NULL, '{"module": "05", "planKind": "std", "designPath": "waitingDays"}'),
  ('LIF_BASIC_MULT', '2026.10', 'life_disability', 'Basic life insurance', 'Assurance vie de base', 'multiple_of_salary', 'x salary', 'higher', NULL, '{"module": "05", "planKind": "life", "designPath": "multiple"}'),
  ('ALW_PARKING', '2026.10', 'allowances', 'Parking', 'Stationnement', 'enum', NULL, 'higher', ARRAY['none','subsidized','free'], '{"module": "01", "resolver": "policy"}');
-- 2. An enum practice needs its values
DO $$ BEGIN
  INSERT INTO ref.reward_practice (practice_code, catalogue_version, category, name_en, name_fr, value_type, richer_when, own_value_source)
    VALUES ('BAD_ENUM', '2026.10', 'other', 'Bad', 'Mauvais', 'enum', 'higher', '{}');
  RAISE EXCEPTION 'FAIL 2';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 2: enum practice without values refused';
END $$;

-- ---------------------------------------------------------------------------------
-- Tenant data as cando_app, with the compensation roles but not the survey's role yet
-- ---------------------------------------------------------------------------------
-- Approvals the 0011 rules need before a structure version is approved (docs/25 §3, §4.2): who submits, the approved
-- compensation philosophy (the 2026 structure is market-based), and each structure route step approved by someone else
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  ('51111111-1111-1111-1111-111111111111', '05a00000-0000-0000-0000-000000000001', 'comp-analyst', 'analyst@example.test'),
  ('51111111-1111-1111-1111-111111111111', '05a00000-0000-0000-0000-000000000002', 'comp-approver', 'approver@example.test');
INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
  ('51111111-1111-1111-1111-111111111111', 'comp_philosophy', '05600000-0000-0000-0000-000000000001', 1, 'approved', '05a00000-0000-0000-0000-000000000002', now(), 'executive'),
  ('51111111-1111-1111-1111-111111111111', 'pay_structure_version', '05510000-0000-0000-0000-000000000001', 1, 'approved', '05a00000-0000-0000-0000-000000000002', now(), 'hr'),
  ('51111111-1111-1111-1111-111111111111', 'pay_structure_version', '05510000-0000-0000-0000-000000000001', 2, 'approved', '05a00000-0000-0000-0000-000000000002', now(), 'finance'),
  ('51111111-1111-1111-1111-111111111111', 'pay_structure_version', '05510000-0000-0000-0000-000000000001', 3, 'approved', '05a00000-0000-0000-0000-000000000002', now(), 'executive'),
  ('51111111-1111-1111-1111-111111111111', 'pay_structure_version', '05510000-0000-0000-0000-000000000002', 1, 'approved', '05a00000-0000-0000-0000-000000000002', now(), 'hr'),
  ('51111111-1111-1111-1111-111111111111', 'pay_structure_version', '05510000-0000-0000-0000-000000000002', 2, 'approved', '05a00000-0000-0000-0000-000000000002', now(), 'finance'),
  ('51111111-1111-1111-1111-111111111111', 'pay_structure_version', '05510000-0000-0000-0000-000000000002', 3, 'approved', '05a00000-0000-0000-0000-000000000002', now(), 'executive');
INSERT INTO comp.philosophy (tenant_id, philosophy_id, valid_period, target, submitted_by, route_id, status, approved_at)
  SELECT '51111111-1111-1111-1111-111111111111', '05600000-0000-0000-0000-000000000001', '[2026-01-01,)', '{"default":{"stance":"match","statistic":"p50"}}',
         '05a00000-0000-0000-0000-000000000001', route_id, 'approved', now()
    FROM platform.workflow_route WHERE tenant_id = '51111111-1111-1111-1111-111111111111' AND code = 'comp_philosophy';

SET ROLE cando_app;
SELECT set_config('app.tenant_id', '51111111-1111-1111-1111-111111111111', false) AS cfg \gset
SELECT set_config('app.roles', 'comp_admin,comp_analyst', false) AS cfg \gset
CREATE TEMP TABLE plan_json AS SELECT :'plan'::jsonb AS j;

INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, 'a5000000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, 'b5000000-0000-0000-0000-000000000001');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, 'c5000000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'd5000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'd5000000-0000-0000-0000-000000000002');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, noc_code) VALUES
  (current_setting('app.tenant_id')::uuid, 'd5000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'CSV-YTH-P2', 'Youth outreach worker', NULL),
  (current_setting('app.tenant_id')::uuid, 'd5000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'FIN-PAY-S3', 'Payroll coordinator', NULL);
INSERT INTO core.position (tenant_id, position_id, number) VALUES (current_setting('app.tenant_id')::uuid, 'e5000000-0000-0000-0000-000000000001', 'YO-001');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, fte_budget, employment_type, status)
  VALUES (current_setting('app.tenant_id')::uuid, 'e5000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(),
          'd5000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001', 1, 'permanent', 'active');
INSERT INTO core.person (tenant_id, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f5000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'f5000000-0000-0000-0000-000000000002');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id, employee_number) VALUES
  (current_setting('app.tenant_id')::uuid, 'f5100000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001', 'a5000000-0000-0000-0000-000000000001', 'E-501');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'f5200000-0000-0000-0000-000000000001', 'f5100000-0000-0000-0000-000000000001');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary)
  VALUES (current_setting('app.tenant_id')::uuid, 'f5200000-0000-0000-0000-000000000001', '[2024-04-01,)', gen_random_uuid(),
          'e5000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000001', 'b5000000-0000-0000-0000-000000000001', 1, true);

-- ---------------------------------------------------------------------------------
-- Competency framework (§4)
-- ---------------------------------------------------------------------------------
INSERT INTO talent.competency_framework (tenant_id, framework_id, code, name_en, name_fr)
  VALUES (current_setting('app.tenant_id')::uuid, '05100000-0000-0000-0000-000000000001', 'UCM', 'Unified Competency Model', 'Modèle unifié de compétences');
INSERT INTO talent.competency_framework_version (tenant_id, framework_version_id, framework_id, label, scale)
  VALUES (current_setting('app.tenant_id')::uuid, '05110000-0000-0000-0000-000000000001', '05100000-0000-0000-0000-000000000001', '1.0',
          '[{"level":1,"code":"FOUNDATIONAL"},{"level":2,"code":"APPLIED"},{"level":3,"code":"PROFICIENT"},{"level":4,"code":"ADVANCED"},{"level":5,"code":"STRATEGIC"}]');
INSERT INTO talent.competency (tenant_id, competency_id, framework_version_id, code, domain_code, name_en, definition_en, indicators_status) VALUES
  (current_setting('app.tenant_id')::uuid, '05120000-0000-0000-0000-000000000001', '05110000-0000-0000-0000-000000000001', 'CLI', 'CORE', 'Client-Centered Practice', 'Seeks to understand and meet clients'' needs.', 'as_provided'),
  (current_setting('app.tenant_id')::uuid, '05120000-0000-0000-0000-000000000002', '05110000-0000-0000-0000-000000000001', 'NAV', 'FUNC', 'Needs Assessment & Navigation', 'Assesses needs and connects people with services.', 'proposed');
INSERT INTO talent.competency_indicator (tenant_id, competency_id, level, seq, text_en)
  SELECT current_setting('app.tenant_id')::uuid, c, l, 1, 'Indicator at level ' || l
  FROM unnest(ARRAY['05120000-0000-0000-0000-000000000001','05120000-0000-0000-0000-000000000002']::uuid[]) c, generate_series(1, 5) l;

-- 3. An indicator above the scale
DO $$ BEGIN
  INSERT INTO talent.competency_indicator (tenant_id, competency_id, level, seq, text_en)
    VALUES (current_setting('app.tenant_id')::uuid, '05120000-0000-0000-0000-000000000001', 6, 1, 'Too high');
  RAISE EXCEPTION 'FAIL 3';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'LEVEL_OUTSIDE_SCALE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 3: indicator level 6 on a five-level scale refused';
END $$;

-- 4. TR-001: no publishing while indicators are proposed; publishing after review
DO $$ BEGIN
  UPDATE talent.competency_framework_version SET status = 'published' WHERE framework_version_id = '05110000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 4a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'FRAMEWORK_INDICATORS_PROPOSED%NAV%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 4a: %', SQLERRM;
END $$;
UPDATE talent.competency SET indicators_status = 'reviewed' WHERE competency_id = '05120000-0000-0000-0000-000000000002';
UPDATE talent.competency_framework_version SET status = 'published' WHERE framework_version_id = '05110000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF (SELECT published_at FROM talent.competency_framework_version WHERE framework_version_id = '05110000-0000-0000-0000-000000000001') IS NULL THEN
    RAISE EXCEPTION 'FAIL 4b';
  END IF;
  RAISE NOTICE 'PASS 4b: published after review, with a publication time';
END $$;

-- 5. TR-002: a published version is frozen and cannot go back to draft
DO $$ BEGIN
  UPDATE talent.competency_indicator SET text_en = 'Changed' WHERE competency_id = '05120000-0000-0000-0000-000000000001' AND level = 1;
  RAISE EXCEPTION 'FAIL 5a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'FRAMEWORK_VERSION_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 5a: indicator in a published version cannot change';
END $$;
DO $$ BEGIN
  UPDATE talent.competency_framework_version SET status = 'draft' WHERE framework_version_id = '05110000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 5b';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 5b: status cannot go backwards';
END $$;

-- 6. Targets: TR-004 level outside the scale; TR-005 a position override needs a reason
INSERT INTO talent.competency_target (tenant_id, target_id, target_type, target_ref, competency_id, required_level, entry_level, criticality, source, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd5000000-0000-0000-0000-000000000001', '05120000-0000-0000-0000-000000000001', 3, 2, 'critical', 'career_level_default', '[2026-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd5000000-0000-0000-0000-000000000001', '05120000-0000-0000-0000-000000000002', 3, NULL, 'important', 'career_level_default', '[2026-01-01,)', gen_random_uuid());
DO $$ BEGIN
  INSERT INTO talent.competency_target (tenant_id, target_id, target_type, target_ref, competency_id, required_level, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd5000000-0000-0000-0000-000000000002', '05120000-0000-0000-0000-000000000001', 6, 'job', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 6a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'LEVEL_OUTSIDE_SCALE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 6a: target level 6 refused';
END $$;
DO $$ BEGIN
  INSERT INTO talent.competency_target (tenant_id, target_id, target_type, target_ref, competency_id, required_level, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'position', 'e5000000-0000-0000-0000-000000000001', '05120000-0000-0000-0000-000000000001', 4, 'position', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 6b';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'OVERRIDE_NEEDS_REASON%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 6b: position override without a reason refused';
END $$;
INSERT INTO talent.competency_target (tenant_id, target_id, target_type, target_ref, competency_id, required_level, criticality, source, reason, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'position', 'e5000000-0000-0000-0000-000000000001', '05120000-0000-0000-0000-000000000001', 4,
          'critical', 'position', 'Position leads the outreach team''s complex cases', '[2026-01-01,)', gen_random_uuid());
DO $$ BEGIN
  INSERT INTO talent.competency_target (tenant_id, target_id, target_type, target_ref, competency_id, required_level, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd5000000-0000-0000-0000-000000000001', '05120000-0000-0000-0000-000000000001', 2, 'job', '[2026-06-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 6c';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 6c: one active target per competency per day';
END $$;

-- 7. TR-006: gaps use the position override and the latest final non-self assessment; corrections supersede
INSERT INTO talent.competency_assessment (tenant_id, assessment_id, person_id, competency_id, assessed_level, source, context, assessed_on, assessor_person_id, status) VALUES
  (current_setting('app.tenant_id')::uuid, '05130000-0000-0000-0000-000000000001', 'f5000000-0000-0000-0000-000000000001', '05120000-0000-0000-0000-000000000001', 2, 'manager', 'performance_review', '2026-03-01', 'f5000000-0000-0000-0000-000000000002', 'final'),
  (current_setting('app.tenant_id')::uuid, '05130000-0000-0000-0000-000000000002', 'f5000000-0000-0000-0000-000000000001', '05120000-0000-0000-0000-000000000001', 4, 'self', 'performance_review', '2026-06-01', NULL, 'final');
DO $$ DECLARE r record; BEGIN
  SELECT * INTO r FROM talent.competency_gap('f5200000-0000-0000-0000-000000000001', '2026-10-01') WHERE competency_code = 'CLI';
  IF r.required_level <> 4 OR r.target_from <> 'position' OR r.assessed_level <> 2 OR r.assessment_source <> 'manager' OR r.self_level <> 4 OR r.gap <> 2 THEN
    RAISE EXCEPTION 'FAIL 7a: %', r;
  END IF;
  SELECT * INTO r FROM talent.competency_gap('f5200000-0000-0000-0000-000000000001', '2026-10-01') WHERE competency_code = 'NAV';
  IF r.required_level <> 3 OR r.target_from <> 'job' OR r.assessed_level IS NOT NULL OR r.gap IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL 7a NAV: %', r;
  END IF;
  RAISE NOTICE 'PASS 7a: CLI required 4 (position), assessed 2 by the manager, self 4 shown, gap 2; NAV from the job, not assessed';
END $$;
INSERT INTO talent.competency_assessment (tenant_id, person_id, competency_id, assessed_level, source, context, assessed_on, assessor_person_id, status, supersedes_assessment_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'f5000000-0000-0000-0000-000000000001', '05120000-0000-0000-0000-000000000001', 3, 'manager', 'performance_review',
          '2026-03-01', 'f5000000-0000-0000-0000-000000000002', 'final', '05130000-0000-0000-0000-000000000001');
DO $$ BEGIN
  IF (SELECT status FROM talent.competency_assessment WHERE assessment_id = '05130000-0000-0000-0000-000000000001') <> 'superseded'
     OR (SELECT gap FROM talent.competency_gap('f5200000-0000-0000-0000-000000000001', '2026-10-01') WHERE competency_code = 'CLI') <> 1 THEN
    RAISE EXCEPTION 'FAIL 7b';
  END IF;
  RAISE NOTICE 'PASS 7b: correction supersedes the first assessment; gap now 1';
END $$;
DO $$ BEGIN
  UPDATE talent.competency_assessment SET assessed_level = 5 WHERE assessment_id = '05130000-0000-0000-0000-000000000002';
  RAISE EXCEPTION 'FAIL 7c';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'ASSESSMENT_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 7c: a final assessment cannot change';
END $$;

-- ---------------------------------------------------------------------------------
-- Job evaluation (§5) with the sample plan from rules/job-evaluation/
-- ---------------------------------------------------------------------------------
INSERT INTO comp.je_plan (tenant_id, plan_id, code, name_en, purposes)
  VALUES (current_setting('app.tenant_id')::uuid, '05200000-0000-0000-0000-000000000001', 'CANDO-PF', 'CanDo point-factor plan', ARRAY['grading','pay_equity']);
INSERT INTO comp.je_plan_version (tenant_id, plan_version_id, plan_id, label, max_points, grade_bands, source)
  SELECT current_setting('app.tenant_id')::uuid, v.id, '05200000-0000-0000-0000-000000000001', v.label, v.maxp, j->'grade_bands', 'cando_sample'
  FROM plan_json, (VALUES ('05210000-0000-0000-0000-000000000001'::uuid, 'A-no-working-conditions', 900),
                          ('05210000-0000-0000-0000-000000000002'::uuid, '2026.10', 999)) v(id, label, maxp);
INSERT INTO comp.je_factor (tenant_id, factor_id, plan_version_id, code, factor_group, name_en, name_fr, definition_en, max_points, display_order)
  SELECT current_setting('app.tenant_id')::uuid, gen_random_uuid(), v.id, f->>'code', f->>'group', f->>'name_en', f->>'name_fr', f->>'definition_en',
         (f->>'max_points')::int, n::smallint
  FROM plan_json, jsonb_array_elements(j->'factors') WITH ORDINALITY AS x(f, n),
       (VALUES ('05210000-0000-0000-0000-000000000001'::uuid), ('05210000-0000-0000-0000-000000000002'::uuid)) v(id)
  WHERE v.id = '05210000-0000-0000-0000-000000000002' OR f->>'group' <> 'working_conditions';
INSERT INTO comp.je_degree (tenant_id, factor_id, degree, points, descriptor_en)
  SELECT current_setting('app.tenant_id')::uuid, jf.factor_id, (d->>'degree')::smallint, (d->>'points')::int, d->>'descriptor_en'
  FROM plan_json, jsonb_array_elements(j->'factors') f, jsonb_array_elements(f->'degrees') d, comp.je_factor jf
  WHERE jf.code = f->>'code';
INSERT INTO comp.je_evidence_link (tenant_id, factor_id, source, framework_code, competency_codes, suggest)
  SELECT current_setting('app.tenant_id')::uuid, jf.factor_id, f->'evidence'->>'source', 'UCM',
         ARRAY(SELECT jsonb_array_elements_text(coalesce(f->'evidence'->'competencies', '[]'))), f->'evidence'->'suggest'
  FROM plan_json, jsonb_array_elements(j->'factors') f, comp.je_factor jf
  WHERE jf.code = f->>'code' AND jf.plan_version_id = '05210000-0000-0000-0000-000000000002' AND f->'evidence' ? 'suggest';

-- 8. TR-007 and TR-008: publishing checks
DO $$ BEGIN
  UPDATE comp.je_plan_version SET status = 'published' WHERE plan_version_id = '05210000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 8a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'JE_PLAN_GROUP_MISSING%working_conditions%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 8a: pay equity plan without working conditions refused';
END $$;
DO $$ BEGIN
  UPDATE comp.je_plan_version SET status = 'published' WHERE plan_version_id = '05210000-0000-0000-0000-000000000002';
  RAISE EXCEPTION 'FAIL 8b';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'JE_PLAN_POINTS_MISMATCH%1000%999%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 8b: %', SQLERRM;
END $$;
UPDATE comp.je_plan_version SET max_points = 1000 WHERE plan_version_id = '05210000-0000-0000-0000-000000000002';
DO $$ BEGIN
  UPDATE comp.je_plan_version SET status = 'published' WHERE plan_version_id = '05210000-0000-0000-0000-000000000002';
  RAISE EXCEPTION 'FAIL 8c';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'JE_PLAN_REVIEW_MISSING%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 8c: no publishing without the gender-neutral review';
END $$;
UPDATE comp.je_plan_version
  SET gender_neutral_review = '{"reviewedOn": "2026-10-20", "reviewedBy": ["pay equity committee"], "findings": "Piloted on 6 job classes"}',
      status = 'published'
  WHERE plan_version_id = '05210000-0000-0000-0000-000000000002';
DO $$ BEGIN
  UPDATE comp.je_degree SET points = 26
    WHERE degree = 1 AND factor_id = (SELECT factor_id FROM comp.je_factor WHERE code = 'K1' AND plan_version_id = '05210000-0000-0000-0000-000000000002');
  RAISE EXCEPTION 'FAIL 8d';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'JE_PLAN_VERSION_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 8d: 12 factors and 1000 points published; degrees frozen';
END $$;

-- 9. TR-009: the youth outreach worker's ratings give 560 points and G06
INSERT INTO comp.job_evaluation (tenant_id, evaluation_id, plan_version_id, job_id, effective_from, evaluator_ids)
  VALUES (current_setting('app.tenant_id')::uuid, '05220000-0000-0000-0000-000000000001', '05210000-0000-0000-0000-000000000002',
          'd5000000-0000-0000-0000-000000000001', '2026-11-01', ARRAY['f5000000-0000-0000-0000-000000000002']::uuid[]);
INSERT INTO comp.job_evaluation_rating (tenant_id, evaluation_id, factor_id, degree, points, rationale, suggested_low, suggested_high)
  SELECT current_setting('app.tenant_id')::uuid, '05220000-0000-0000-0000-000000000001', jf.factor_id, r.value::smallint, 0,
         'Rated from the job description and evidence', NULL, NULL
  FROM plan_json, jsonb_each_text(j->'worked_examples'->0->'ratings') r, comp.je_factor jf
  WHERE jf.code = r.key AND jf.plan_version_id = '05210000-0000-0000-0000-000000000002';
UPDATE comp.job_evaluation SET status = 'approved', approved_by = 'f5000000-0000-0000-0000-000000000002'
  WHERE evaluation_id = '05220000-0000-0000-0000-000000000001';
DO $$ DECLARE p int; g text; BEGIN
  SELECT total_points, grade INTO p, g FROM comp.job_evaluation WHERE evaluation_id = '05220000-0000-0000-0000-000000000001';
  IF p <> 560 OR g <> 'G06' THEN RAISE EXCEPTION 'FAIL 9: % %', p, g; END IF;
  RAISE NOTICE 'PASS 9: youth outreach worker % points, %', p, g;
END $$;

-- 10. TR-010: approval needs every factor
INSERT INTO comp.job_evaluation (tenant_id, evaluation_id, plan_version_id, job_id, effective_from)
  VALUES (current_setting('app.tenant_id')::uuid, '05220000-0000-0000-0000-000000000002', '05210000-0000-0000-0000-000000000002',
          'd5000000-0000-0000-0000-000000000002', '2026-11-01');
INSERT INTO comp.job_evaluation_rating (tenant_id, evaluation_id, factor_id, degree, points, rationale)
  SELECT current_setting('app.tenant_id')::uuid, '05220000-0000-0000-0000-000000000002', jf.factor_id, r.value::smallint, 0, 'Rated'
  FROM plan_json, jsonb_each_text(j->'worked_examples'->1->'ratings') r, comp.je_factor jf
  WHERE jf.code = r.key AND jf.plan_version_id = '05210000-0000-0000-0000-000000000002' AND r.key <> 'W2';
DO $$ BEGIN
  UPDATE comp.job_evaluation SET status = 'approved', approved_by = gen_random_uuid() WHERE evaluation_id = '05220000-0000-0000-0000-000000000002';
  RAISE EXCEPTION 'FAIL 10';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'EVALUATION_INCOMPLETE%W2%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 10: %', SQLERRM;
END $$;
INSERT INTO comp.job_evaluation_rating (tenant_id, evaluation_id, factor_id, degree, points, rationale)
  SELECT current_setting('app.tenant_id')::uuid, '05220000-0000-0000-0000-000000000002', factor_id, 1, 0, 'Office setting'
  FROM comp.je_factor WHERE code = 'W2' AND plan_version_id = '05210000-0000-0000-0000-000000000002';
UPDATE comp.job_evaluation SET status = 'approved', approved_by = gen_random_uuid() WHERE evaluation_id = '05220000-0000-0000-0000-000000000002';
DO $$ BEGIN
  IF (SELECT (total_points, grade) FROM comp.job_evaluation WHERE evaluation_id = '05220000-0000-0000-0000-000000000002') IS DISTINCT FROM (427, 'G04'::text) THEN
    RAISE EXCEPTION 'FAIL 10b';
  END IF;
  RAISE NOTICE 'PASS 10b: payroll coordinator 427 points, G04';
END $$;

-- 11. TR-011: a degree outside the evidence-based suggestion needs a reason
INSERT INTO comp.job_evaluation (tenant_id, evaluation_id, plan_version_id, job_id, effective_from, supersedes_evaluation_id)
  VALUES (current_setting('app.tenant_id')::uuid, '05220000-0000-0000-0000-000000000003', '05210000-0000-0000-0000-000000000002',
          'd5000000-0000-0000-0000-000000000001', '2027-01-01', '05220000-0000-0000-0000-000000000001');
DO $$ BEGIN
  INSERT INTO comp.job_evaluation_rating (tenant_id, evaluation_id, factor_id, degree, points, rationale, suggested_low, suggested_high)
    SELECT current_setting('app.tenant_id')::uuid, '05220000-0000-0000-0000-000000000003', factor_id, 2, 0, 'Rated', 4, 5
    FROM comp.je_factor WHERE code = 'K1' AND plan_version_id = '05210000-0000-0000-0000-000000000002';
  RAISE EXCEPTION 'FAIL 11';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%outside_suggestion_needs_reason%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 11: K1 degree 2 against a 4-5 suggestion needs a reason';
END $$;

-- 12. TR-012: approving a re-evaluation supersedes the current one in the same transaction
INSERT INTO comp.job_evaluation_rating (tenant_id, evaluation_id, factor_id, degree, points, rationale, outside_reason, suggested_low, suggested_high)
  SELECT current_setting('app.tenant_id')::uuid, '05220000-0000-0000-0000-000000000003', jf.factor_id,
         CASE WHEN r.key = 'R2' THEN 3 ELSE r.value::smallint END, 0, 'Re-evaluated after the team lead duties were added',
         CASE WHEN r.key = 'R2' THEN 'Now leads two outreach workers' END,
         CASE WHEN r.key = 'R2' THEN 1 END, CASE WHEN r.key = 'R2' THEN 2 END
  FROM plan_json, jsonb_each_text(j->'worked_examples'->0->'ratings') r, comp.je_factor jf
  WHERE jf.code = r.key AND jf.plan_version_id = '05210000-0000-0000-0000-000000000002';
UPDATE comp.job_evaluation SET status = 'approved', approved_by = gen_random_uuid() WHERE evaluation_id = '05220000-0000-0000-0000-000000000003';
DO $$ BEGIN
  IF (SELECT status FROM comp.job_evaluation WHERE evaluation_id = '05220000-0000-0000-0000-000000000001') <> 'superseded'
     OR (SELECT total_points FROM comp.job_evaluation WHERE evaluation_id = '05220000-0000-0000-0000-000000000003') <> 580
     OR (SELECT count(*) FROM comp.job_evaluation WHERE job_id = 'd5000000-0000-0000-0000-000000000001' AND status = 'approved') <> 1 THEN
    RAISE EXCEPTION 'FAIL 12';
  END IF;
  RAISE NOTICE 'PASS 12: re-evaluation at 580 points approved, the first superseded, one approved';
END $$;

-- 13. TR-013: an approved evaluation is frozen; only its review flag may be set
DO $$ BEGIN
  UPDATE comp.job_evaluation_rating SET degree = 5, rationale = 'x'
    WHERE evaluation_id = '05220000-0000-0000-0000-000000000003'
      AND factor_id = (SELECT factor_id FROM comp.je_factor WHERE code = 'K2' AND plan_version_id = '05210000-0000-0000-0000-000000000002');
  RAISE EXCEPTION 'FAIL 13a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'EVALUATION_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 13a: rating on an approved evaluation cannot change';
END $$;
DO $$ BEGIN
  UPDATE comp.job_evaluation SET total_points = 999 WHERE evaluation_id = '05220000-0000-0000-0000-000000000003';
  RAISE EXCEPTION 'FAIL 13b';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 13b: points of an approved evaluation cannot change';
END $$;
UPDATE comp.job_evaluation SET review_flag = 'Requirements changed on 2027-02-01' WHERE evaluation_id = '05220000-0000-0000-0000-000000000003';

-- ---------------------------------------------------------------------------------
-- Surveys, market data and the licence policy (§6, §12)
-- ---------------------------------------------------------------------------------
INSERT INTO core.code_scheme (tenant_id, scheme_id, code, name_en, source, purpose, applies_to, values_per_target, shares_total_100) VALUES
  (current_setting('app.tenant_id')::uuid, '05300000-0000-0000-0000-000000000001', 'SURVEY_T', 'Test salary survey', 'tenant', 'salary_survey',
   ARRAY['job','position','assignment'], 'many', true),
  (current_setting('app.tenant_id')::uuid, '05300000-0000-0000-0000-000000000002', 'JOB_FAMILY_T', 'Job family', 'tenant', 'job_family', ARRAY['job'], 'one', false);

-- 14. A survey's scheme must be a salary survey scheme
DO $$ BEGIN
  INSERT INTO comp.survey (tenant_id, code, name, publisher, scheme_id, derived_results_restricted)
    VALUES (current_setting('app.tenant_id')::uuid, 'WRONG', 'Wrong', 'Test', '05300000-0000-0000-0000-000000000002', false);
  RAISE EXCEPTION 'FAIL 14';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SURVEY_SCHEME_PURPOSE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 14: survey needs a salary survey scheme';
END $$;
INSERT INTO comp.survey (tenant_id, survey_id, code, name, publisher, scheme_id, licence, derived_results_restricted)
  VALUES (current_setting('app.tenant_id')::uuid, '05310000-0000-0000-0000-000000000001', 'SVY_T', 'Test survey', 'Fictional Publisher',
          '05300000-0000-0000-0000-000000000001', '{"licensee": "Rewards Test Tenant", "employeesMaySee": false}', false);
DO $$ BEGIN
  IF (SELECT access_role FROM comp.survey WHERE survey_id = '05310000-0000-0000-0000-000000000001') <> 'survey_data:SVY_T' THEN RAISE EXCEPTION 'FAIL 14b'; END IF;
  RAISE NOTICE 'PASS 14b: access role defaults to survey_data:SVY_T';
END $$;

-- The import job holds the survey's role
SELECT set_config('app.roles', 'comp_admin,comp_analyst,survey_data:SVY_T', false) AS cfg \gset
INSERT INTO core.code_value (tenant_id, scheme_id, code, title_en, description_en, attributes, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, '05300000-0000-0000-0000-000000000001', 'SA-101', 'Community program worker', 'Licensed description', '{"family": "CS", "level": "2"}', '[2025-04-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, '05300000-0000-0000-0000-000000000001', 'SA-102', 'Senior community program worker', 'Licensed description', '{"family": "CS", "level": "3"}', '[2025-04-01,)', gen_random_uuid());
INSERT INTO comp.survey_edition (tenant_id, edition_id, survey_id, label, effective_date, participants, hours_basis)
  VALUES (current_setting('app.tenant_id')::uuid, '05320000-0000-0000-0000-000000000001', '05310000-0000-0000-0000-000000000001', '2025', '2025-04-01', 40, 1950);
INSERT INTO comp.survey_cut (tenant_id, cut_id, edition_id, cut_code, dimension, label_en) VALUES
  (current_setting('app.tenant_id')::uuid, '05330000-0000-0000-0000-000000000001', '05320000-0000-0000-0000-000000000001', 'ALL', 'all', 'All participants'),
  (current_setting('app.tenant_id')::uuid, '05330000-0000-0000-0000-000000000002', '05320000-0000-0000-0000-000000000001', 'R1', 'region', 'Region 1');
INSERT INTO comp.market_data (tenant_id, edition_id, survey_id, job_code, cut_id, weighting, element, n_orgs, n_incumbents, mean, p10, p25, p50, p75, p90, masked_fields) VALUES
  (current_setting('app.tenant_id')::uuid, '05320000-0000-0000-0000-000000000001', '05310000-0000-0000-0000-000000000001', 'SA-101', '05330000-0000-0000-0000-000000000001', 'organization', 'base_salary', 22, 88, 51300, 44200, 47600, 50800, 55100, 59900, '{}'),
  (current_setting('app.tenant_id')::uuid, '05320000-0000-0000-0000-000000000001', '05310000-0000-0000-0000-000000000001', 'SA-102', '05330000-0000-0000-0000-000000000002', 'organization', 'base_salary', 3, 5, NULL, NULL, NULL, NULL, NULL, NULL, ARRAY['mean','p10','p25','p50','p75','p90']);

-- 15. TR-015 and TR-016: percentiles in order; job codes from the catalogue
DO $$ BEGIN
  INSERT INTO comp.market_data (tenant_id, edition_id, survey_id, job_code, cut_id, weighting, element, n_orgs, p25, p50, p75)
    VALUES (current_setting('app.tenant_id')::uuid, '05320000-0000-0000-0000-000000000001', '05310000-0000-0000-0000-000000000001', 'SA-102',
            '05330000-0000-0000-0000-000000000001', 'organization', 'base_salary', 15, 57400, 61500, 60000);
  RAISE EXCEPTION 'FAIL 15a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%percentiles_ordered%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 15a: P75 below P50 refused';
END $$;
DO $$ BEGIN
  INSERT INTO comp.market_data (tenant_id, edition_id, survey_id, job_code, cut_id, weighting, element, n_orgs, p50)
    VALUES (current_setting('app.tenant_id')::uuid, '05320000-0000-0000-0000-000000000001', '05310000-0000-0000-0000-000000000001', 'SA-999',
            '05330000-0000-0000-0000-000000000001', 'organization', 'base_salary', 15, 61500);
  RAISE EXCEPTION 'FAIL 15b';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SURVEY_JOB_NOT_IN_CATALOGUE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 15b: job code not in the survey catalogue refused';
END $$;
UPDATE comp.survey_edition SET status = 'published' WHERE edition_id = '05320000-0000-0000-0000-000000000001';
DO $$ BEGIN
  UPDATE comp.market_data SET p50 = 50000 WHERE job_code = 'SA-101';
  RAISE EXCEPTION 'FAIL 15c';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'EDITION_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 15c: data of a published edition is frozen';
END $$;

-- 16. TR-025: without the survey's role, market data and the survey's job catalogue are invisible and cannot be written
SELECT set_config('app.roles', 'comp_admin,comp_analyst', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM comp.market_data) <> 0
     OR (SELECT count(*) FROM core.code_value WHERE scheme_id = '05300000-0000-0000-0000-000000000001') <> 0 THEN
    RAISE EXCEPTION 'FAIL 16a';
  END IF;
  IF (SELECT count(*) FROM comp.survey) <> 1 THEN RAISE EXCEPTION 'FAIL 16a: survey list should stay visible'; END IF;
  RAISE NOTICE 'PASS 16a: no market data or catalogue rows without survey_data:SVY_T; the survey itself is listed';
END $$;
DO $$ BEGIN
  INSERT INTO core.code_value (tenant_id, scheme_id, code, title_en, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, '05300000-0000-0000-0000-000000000001', 'SA-103', 'x', '[2025-04-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 16b';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS 16b: cannot add survey catalogue values without the role';
END $$;
SELECT set_config('app.roles', 'comp_admin,comp_analyst, survey_data:SVY_T', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM comp.market_data) <> 2 THEN RAISE EXCEPTION 'FAIL 16c'; END IF;
  RAISE NOTICE 'PASS 16c: rows visible with the role (spaces in app.roles ignored)';
END $$;

-- ---------------------------------------------------------------------------------
-- Market definitions, pricing runs and derived results (§7, §12)
-- ---------------------------------------------------------------------------------
INSERT INTO comp.market_definition (tenant_id, definition_id, code, name_en, is_default, statistic, ageing)
  VALUES (current_setting('app.tenant_id')::uuid, '05400000-0000-0000-0000-000000000001', 'DEFAULT', 'Default market', true, 'p50',
          '{"method": "simple", "annualRate": "0.03"}');
INSERT INTO comp.market_definition_source (tenant_id, definition_id, seq, kind, edition_id, weighting, element, cut_chain, weight) VALUES
  (current_setting('app.tenant_id')::uuid, '05400000-0000-0000-0000-000000000001', 1, 'survey', '05320000-0000-0000-0000-000000000001',
   'organization', 'base_salary', ARRAY['R1','ALL'], 70);
INSERT INTO comp.market_definition_source (tenant_id, definition_id, seq, kind, public_edition_id, geo_chain, hours_basis, weight) VALUES
  (current_setting('app.tenant_id')::uuid, '05400000-0000-0000-0000-000000000001', 2, 'public_wage', 'TEST-WAGES-2025', ARRAY['5920','59','CA'], 1950, 30);

-- 17. A source is either a survey edition or a public wage edition, with what that kind needs
DO $$ BEGIN
  INSERT INTO comp.market_definition_source (tenant_id, definition_id, seq, kind, public_edition_id, geo_chain, weight)
    VALUES (current_setting('app.tenant_id')::uuid, '05400000-0000-0000-0000-000000000001', 3, 'public_wage', 'TEST-WAGES-2025', ARRAY['CA'], 10);
  RAISE EXCEPTION 'FAIL 17';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 17: public wage source without an hours basis refused';
END $$;

INSERT INTO comp.market_pricing_run (tenant_id, run_id, definition_id, as_of, definition_snapshot, survey_ids, created_by)
  VALUES (current_setting('app.tenant_id')::uuid, '05410000-0000-0000-0000-000000000001', '05400000-0000-0000-0000-000000000001', '2026-01-01',
          '{"statistic": "p50"}', ARRAY['05310000-0000-0000-0000-000000000001']::uuid[], gen_random_uuid());
INSERT INTO comp.market_composite (tenant_id, run_id, job_id, status, p25, p50, p75, target, lineage)
  VALUES (current_setting('app.tenant_id')::uuid, '05410000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000001', 'priced',
          49591.25, 54271.75, 57260.00, 54271.75, '[{"source": "SVY-A-2025", "used": true}, {"source": "PUBLIC-2025", "used": true}]');
UPDATE comp.market_pricing_run SET status = 'approved', approved_by = gen_random_uuid(), approved_at = now()
  WHERE run_id = '05410000-0000-0000-0000-000000000001';

-- 18. An approved run is frozen; approving the next run supersedes it
DO $$ BEGIN
  INSERT INTO comp.market_composite (tenant_id, run_id, job_id, status, lineage)
    VALUES (current_setting('app.tenant_id')::uuid, '05410000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002', 'insufficient_data', '[]');
  RAISE EXCEPTION 'FAIL 18a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'RUN_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 18a: approved run cannot gain results';
END $$;
INSERT INTO comp.market_pricing_run (tenant_id, run_id, definition_id, as_of, definition_snapshot, survey_ids, created_by)
  VALUES (current_setting('app.tenant_id')::uuid, '05410000-0000-0000-0000-000000000002', '05400000-0000-0000-0000-000000000001', '2026-07-01',
          '{"statistic": "p50"}', ARRAY['05310000-0000-0000-0000-000000000001']::uuid[], gen_random_uuid());
UPDATE comp.market_pricing_run SET status = 'approved', approved_by = gen_random_uuid(), approved_at = now()
  WHERE run_id = '05410000-0000-0000-0000-000000000002';
DO $$ BEGIN
  IF (SELECT status FROM comp.market_pricing_run WHERE run_id = '05410000-0000-0000-0000-000000000001') <> 'superseded' THEN RAISE EXCEPTION 'FAIL 18b'; END IF;
  RAISE NOTICE 'PASS 18b: earlier run superseded';
END $$;

-- 19. Derived results: visible to compensation roles unless the survey restricts them
SELECT set_config('app.roles', 'comp_admin,comp_analyst', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM comp.market_composite) <> 1 THEN RAISE EXCEPTION 'FAIL 19a'; END IF;
  RAISE NOTICE 'PASS 19a: approved results visible without the survey role';
END $$;
UPDATE comp.survey SET derived_results_restricted = true WHERE survey_id = '05310000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF (SELECT count(*) FROM comp.market_composite) <> 0 THEN RAISE EXCEPTION 'FAIL 19b'; END IF;
  RAISE NOTICE 'PASS 19b: hidden once the survey restricts derived results';
END $$;
SELECT set_config('app.roles', 'comp_admin,comp_analyst,survey_data:SVY_T', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- Pay structures (§7.7)
-- ---------------------------------------------------------------------------------
INSERT INTO comp.pay_structure (tenant_id, structure_id, code, name_en, kind)
  VALUES (current_setting('app.tenant_id')::uuid, '05500000-0000-0000-0000-000000000001', 'NONUNION', 'Non-union salary structure', 'graded');
INSERT INTO comp.pay_structure_version (tenant_id, structure_version_id, structure_id, label, valid_period, je_plan_version_id, pricing_run_id, method,
                                       submitted_by, route_id)
  VALUES (current_setting('app.tenant_id')::uuid, '05510000-0000-0000-0000-000000000001', '05500000-0000-0000-0000-000000000001', '2026',
          '[2026-01-01,2027-01-01)', '05210000-0000-0000-0000-000000000002', '05410000-0000-0000-0000-000000000002',
          '{"marketLine": {"a": "9.9486059631", "b": "0.0020975312", "r2": "0.9545"}}', '05a00000-0000-0000-0000-000000000001',
          (SELECT route_id FROM platform.workflow_route WHERE tenant_id = current_setting('app.tenant_id')::uuid AND code = 'pay_structure_version'));
INSERT INTO comp.pay_grade (tenant_id, structure_version_id, grade_code, rank, points_min, points_max, minimum, midpoint, maximum, spread_pct) VALUES
  (current_setting('app.tenant_id')::uuid, '05510000-0000-0000-0000-000000000001', 'G04', 4, 390, 459, 42500, 51000, 59500, 40),
  (current_setting('app.tenant_id')::uuid, '05510000-0000-0000-0000-000000000001', 'G06', 6, 530, 609, 57600, 69100, 80600, 40);

-- 20. Grades are ordered; an approved version is frozen; approved versions cannot overlap (TR-022)
DO $$ BEGIN
  INSERT INTO comp.pay_grade (tenant_id, structure_version_id, grade_code, rank, minimum, midpoint, maximum)
    VALUES (current_setting('app.tenant_id')::uuid, '05510000-0000-0000-0000-000000000001', 'G05', 5, 60000, 59000, 68800);
  RAISE EXCEPTION 'FAIL 20a';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 20a: minimum above midpoint refused';
END $$;
UPDATE comp.pay_structure_version SET status = 'approved', approved_by = gen_random_uuid(), approved_at = now()
  WHERE structure_version_id = '05510000-0000-0000-0000-000000000001';
DO $$ BEGIN
  UPDATE comp.pay_grade SET midpoint = 70000 WHERE grade_code = 'G06';
  RAISE EXCEPTION 'FAIL 20b';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'STRUCTURE_VERSION_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 20b: grades of an approved version are frozen';
END $$;
INSERT INTO comp.pay_structure_version (tenant_id, structure_version_id, structure_id, label, valid_period, submitted_by, route_id)
  VALUES (current_setting('app.tenant_id')::uuid, '05510000-0000-0000-0000-000000000002', '05500000-0000-0000-0000-000000000001', '2026-b', '[2026-07-01,2027-07-01)',
          '05a00000-0000-0000-0000-000000000001',
          (SELECT route_id FROM platform.workflow_route WHERE tenant_id = current_setting('app.tenant_id')::uuid AND code = 'pay_structure_version'));
DO $$ BEGIN
  UPDATE comp.pay_structure_version SET status = 'approved', approved_by = gen_random_uuid(), approved_at = now()
    WHERE structure_version_id = '05510000-0000-0000-0000-000000000002';
  RAISE EXCEPTION 'FAIL 20c';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 20c: overlapping approved versions refused';
END $$;
INSERT INTO comp.salary_range (tenant_id, grade, valid_period, minimum, midpoint, maximum, structure_version_id, grade_id)
  SELECT current_setting('app.tenant_id')::uuid, grade_code, '[2026-01-01,2027-01-01)', minimum, midpoint, maximum, structure_version_id, grade_id
  FROM comp.pay_grade WHERE structure_version_id = '05510000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF (SELECT count(*) FROM comp.salary_range WHERE structure_version_id = '05510000-0000-0000-0000-000000000001') <> 2 THEN RAISE EXCEPTION 'FAIL 20d'; END IF;
  RAISE NOTICE 'PASS 20d: published ranges linked to their structure version';
END $$;

-- ---------------------------------------------------------------------------------
-- Survey participation (§10)
-- ---------------------------------------------------------------------------------
INSERT INTO comp.survey_pseudonym (tenant_id, survey_id, assignment_id)
  VALUES (current_setting('app.tenant_id')::uuid, '05310000-0000-0000-0000-000000000001', 'f5200000-0000-0000-0000-000000000001');

-- 21. Pseudonyms are per position held, random, well formed and never change (TR-028)
DO $$ DECLARE p text; BEGIN
  SELECT pseudonym INTO p FROM comp.survey_pseudonym WHERE assignment_id = 'f5200000-0000-0000-0000-000000000001';
  IF p !~ '^P[0-9A-F]{12}$' OR p LIKE '%E-501%' THEN RAISE EXCEPTION 'FAIL 21a: %', p; END IF;
  BEGIN
    UPDATE comp.survey_pseudonym SET pseudonym = 'PNEW' WHERE assignment_id = 'f5200000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 21b';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 21: pseudonym % generated and frozen', p;
END $$;

-- 22. Self-identification fields need the privacy officer's approval
DO $$ BEGIN
  INSERT INTO comp.survey_submission (tenant_id, survey_id, edition_label, as_of, included_fields)
    VALUES (current_setting('app.tenant_id')::uuid, '05310000-0000-0000-0000-000000000001', '2027', '2027-04-01', ARRAY['gender']);
  RAISE EXCEPTION 'FAIL 22';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%self_id_needs_privacy_approval%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 22: gender in a submission needs privacy approval';
END $$;
INSERT INTO comp.survey_submission (tenant_id, submission_id, survey_id, edition_label, as_of, included_fields)
  VALUES (current_setting('app.tenant_id')::uuid, '05600000-0000-0000-0000-000000000001', '05310000-0000-0000-0000-000000000001', '2027', '2027-04-01', ARRAY['hire_year']);

-- 23. Rows carry no direct identifiers and only switched-on fields
DO $$ BEGIN
  INSERT INTO comp.survey_submission_row (tenant_id, submission_id, survey_id, pseudonym, job_code, fte, annual_base, extra)
    SELECT current_setting('app.tenant_id')::uuid, '05600000-0000-0000-0000-000000000001', survey_id, pseudonym, 'SA-101', 1, 54000, '{"name": "Ana"}'
    FROM comp.survey_pseudonym WHERE assignment_id = 'f5200000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 23a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SUBMISSION_DIRECT_IDENTIFIER%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 23a: a name in a submission row refused';
END $$;
DO $$ BEGIN
  INSERT INTO comp.survey_submission_row (tenant_id, submission_id, survey_id, pseudonym, job_code, fte, annual_base, extra)
    SELECT current_setting('app.tenant_id')::uuid, '05600000-0000-0000-0000-000000000001', survey_id, pseudonym, 'SA-101', 1, 54000, '{"bargaining_unit": "CUPE"}'
    FROM comp.survey_pseudonym WHERE assignment_id = 'f5200000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 23b';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SUBMISSION_FIELD_NOT_INCLUDED%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 23b: a field not switched on refused';
END $$;
INSERT INTO comp.survey_submission_row (tenant_id, submission_id, survey_id, pseudonym, job_code, match_quality, fte, annual_base, extra)
  SELECT current_setting('app.tenant_id')::uuid, '05600000-0000-0000-0000-000000000001', survey_id, pseudonym, 'SA-101', 'exact', 1, 54000, '{"hire_year": 2024}'
  FROM comp.survey_pseudonym WHERE assignment_id = 'f5200000-0000-0000-0000-000000000001';
UPDATE comp.survey_submission SET status = 'in_review' WHERE submission_id = '05600000-0000-0000-0000-000000000001';
UPDATE comp.survey_submission SET status = 'approved', approved_by = gen_random_uuid(), approved_at = now() WHERE submission_id = '05600000-0000-0000-0000-000000000001';

-- 24. TR-029: an approved submission is frozen; row count recorded; it cannot go back
DO $$ BEGIN
  IF (SELECT row_count FROM comp.survey_submission WHERE submission_id = '05600000-0000-0000-0000-000000000001') <> 1 THEN RAISE EXCEPTION 'FAIL 24a'; END IF;
  BEGIN
    UPDATE comp.survey_submission_row SET annual_base = 55000 WHERE submission_id = '05600000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 24b';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'SUBMISSION_IMMUTABLE%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE comp.survey_submission SET status = 'draft' WHERE submission_id = '05600000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 24c';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 24: approved submission frozen with 1 row; status cannot go back';
END $$;
UPDATE comp.survey_submission SET status = 'exported', file_sha256 = 'test', exported_by = gen_random_uuid(), exported_at = now()
  WHERE submission_id = '05600000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------------------------
-- Practice benchmarking (§8)
-- ---------------------------------------------------------------------------------
INSERT INTO benefits.practice (tenant_id, practice_code, source, ref_practice_code, category, name_en, value_type, unit, richer_when)
  SELECT current_setting('app.tenant_id')::uuid, practice_code, 'catalogue', practice_code, category, name_en, value_type, unit, richer_when
  FROM ref.reward_practice WHERE practice_code IN ('STD_WAIT_DAYS','LIF_BASIC_MULT');
UPDATE comp.survey_edition SET status = 'retired' WHERE edition_id = '05320000-0000-0000-0000-000000000001';
INSERT INTO comp.survey_edition (tenant_id, edition_id, survey_id, label, effective_date)
  VALUES (current_setting('app.tenant_id')::uuid, '05320000-0000-0000-0000-000000000002', '05310000-0000-0000-0000-000000000001', '2027', '2027-04-01');
INSERT INTO benefits.practice_market (tenant_id, edition_id, survey_id, practice_code, n_orgs, prevalence_pct, p25, p50, p75)
  VALUES (current_setting('app.tenant_id')::uuid, '05320000-0000-0000-0000-000000000002', '05310000-0000-0000-0000-000000000001', 'STD_WAIT_DAYS', 40, 64, 3, 7, 7);
INSERT INTO benefits.practice_own_value (tenant_id, practice_code, population, value, source, derived_from, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'STD_WAIT_DAYS', 'NONUNION', '{"value": 3}', 'derived', '{"designPath": "waitingDays"}', '[2026-01-01,)', gen_random_uuid());

-- 25. Practice data: one market row per edition, practice and cut (null cut included); manual values need a reason;
--     one own value per population per day
DO $$ BEGIN
  BEGIN
    INSERT INTO benefits.practice_market (tenant_id, edition_id, survey_id, practice_code, n_orgs, prevalence_pct)
      VALUES (current_setting('app.tenant_id')::uuid, '05320000-0000-0000-0000-000000000002', '05310000-0000-0000-0000-000000000001', 'STD_WAIT_DAYS', 40, 60);
    RAISE EXCEPTION 'FAIL 25a';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO benefits.practice_own_value (tenant_id, practice_code, population, value, source, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, 'LIF_BASIC_MULT', 'NONUNION', '{"value": 2}', 'manual', '[2026-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 25b';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO benefits.practice_own_value (tenant_id, practice_code, population, value, source, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, 'STD_WAIT_DAYS', 'NONUNION', '{"value": 5}', 'derived', '[2026-06-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 25c';
  EXCEPTION WHEN exclusion_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 25: practice market and own-value rules';
END $$;

-- 26. Practice market data follows the licence too
SELECT set_config('app.roles', 'benefits_analyst', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM benefits.practice_market) <> 0 OR (SELECT count(*) FROM benefits.practice_own_value) <> 1 THEN RAISE EXCEPTION 'FAIL 26'; END IF;
  RAISE NOTICE 'PASS 26: practice market data hidden without the survey role; own values visible';
END $$;

-- 27. Tenant isolation
SELECT set_config('app.tenant_id', '52222222-2222-2222-2222-222222222222', false) AS cfg \gset
SELECT set_config('app.roles', 'comp_admin,survey_data:SVY_T', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM comp.job_evaluation) + (SELECT count(*) FROM comp.survey) + (SELECT count(*) FROM comp.market_data)
     + (SELECT count(*) FROM talent.competency_target) + (SELECT count(*) FROM comp.survey_pseudonym) + (SELECT count(*) FROM benefits.practice) <> 0 THEN
    RAISE EXCEPTION 'FAIL 27a';
  END IF;
  RAISE NOTICE 'PASS 27a: other tenant sees no evaluations, surveys, market data, targets, pseudonyms or practices';
END $$;
DO $$ BEGIN
  INSERT INTO comp.je_plan (tenant_id, code, name_en) VALUES ('51111111-1111-1111-1111-111111111111', 'X', 'X');
  RAISE EXCEPTION 'FAIL 27b';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS 27b: cannot write into another tenant';
END $$;
RESET ROLE;

-- 28. Row-level security forced on every new tenant table; restrictive licence policies in place
DO $$ DECLARE missing text; BEGIN
  SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO missing
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r' AND (n.nspname, c.relname) IN (
      ('talent','competency_framework'), ('talent','competency_framework_version'), ('talent','competency'), ('talent','competency_indicator'),
      ('talent','competency_target'), ('talent','competency_assessment'), ('comp','je_plan'), ('comp','je_plan_version'), ('comp','je_factor'),
      ('comp','je_degree'), ('comp','je_evidence_link'), ('comp','job_evaluation'), ('comp','job_evaluation_rating'), ('comp','survey'),
      ('comp','survey_edition'), ('comp','survey_cut'), ('comp','market_data'), ('comp','market_definition'), ('comp','market_definition_source'),
      ('comp','market_pricing_run'), ('comp','market_composite'), ('comp','pay_structure'), ('comp','pay_structure_version'), ('comp','pay_grade'),
      ('comp','survey_pseudonym'), ('comp','survey_submission'), ('comp','survey_submission_row'), ('comp','total_rewards_component'),
      ('benefits','practice'), ('benefits','practice_market'), ('benefits','practice_own_value'))
    AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL 28a: %', missing; END IF;
  IF (SELECT count(*) FROM pg_policy WHERE NOT polpermissive AND polname IN ('survey_licence','derived_results')) <> 6 THEN
    RAISE EXCEPTION 'FAIL 28b: restrictive policies';
  END IF;
  RAISE NOTICE 'PASS 28: RLS forced on the 31 new tenant tables; 6 restrictive licence policies';
END $$;

\echo Migration 0005 smoke test passed.
