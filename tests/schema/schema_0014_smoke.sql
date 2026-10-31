-- Smoke test for schema/0014_performance_decisions.sql (docs/28): the new settings and the decided overall method and
-- minimum days, rating scales and cycles, shared goals and their amendment log, section ratings (minimum days worked,
-- reasons, the previous manager's period, reviews that carry no rating), calibration, the one-up route, HR on a
-- concern, sign-off and HR's review, changes after release, 360° feedback, check-ins, improvement plans, adverse records
-- and their sunset, RLS and tenant isolation.
-- Run after every migration, 0001 to 0014 (CI, after the 0013 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0014_smoke.sql
-- Check-ins are placed relative to today; nothing else depends on today's date. It inserts test rows; run
-- `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit, benefits TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit, benefits TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ref, platform, core, payroll, timeleave, talent, recruit, comp, compliance, benefits TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('e1111111-1111-1111-1111-111111111111', 'Performance Test Society'),
  ('e2222222-2222-2222-2222-222222222222', 'Other Organization')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', 'e1111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, decided overall method and minimum days, caution, starter routes, RLS
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/28%') <> 14
     OR EXISTS (SELECT 1 FROM platform.setting_definition WHERE decision_ref LIKE 'docs/28%' AND decision_status <> 'decided') THEN
    RAISE EXCEPTION 'FAIL 1a: expected 14 decided settings from docs/28';
  END IF;
  IF platform.setting_text(t, 'reviews.overall_method') <> 'none' OR platform.setting_number(t, 'reviews.min_section_days') <> 90
     OR jsonb_array_length(platform.setting(t, 'performance.rating_scale_starter') -> 'levels') <> 5
     OR (platform.setting(t, 'performance.ai_writing_help'))::boolean OR NOT (platform.setting(t, 'performance.calibration'))::boolean
     OR platform.setting(t, 'performance.weights_starter') <> '{"goals":50,"competencies":50}'::jsonb
     OR platform.setting_number(t, 'performance.new_hire_no_rating_months') <> 3
     OR platform.setting_number(t, 'performance.rater_group_min') <> 3 OR platform.setting_number(t, 'performance.rater_group_max') <> 5
     OR platform.setting_text(t, 'performance.feedback_360_use') <> 'development_only'
     OR platform.setting_number(t, 'performance.checkin_nudge_days') <> 30 OR platform.setting_number(t, 'performance.pip_default_days') <> 60
     OR platform.setting(t, 'performance.non_union_sunset') <> '{"months":null}'::jsonb THEN
    RAISE EXCEPTION 'FAIL 1b: decided defaults not in place';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ref.caution WHERE caution_code = 'performance.pip_protected_ground' AND reason_always)
     OR (SELECT count(*) FROM platform.workflow_route WHERE tenant_id = t AND code IN ('performance_review','pip')) <> 2 THEN
    RAISE EXCEPTION 'FAIL 1c: caution or starter routes missing';
  END IF;
  BEGIN
    INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
      VALUES (t, 'performance.rater_group_min', '2', '[2000-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 1d: a 360 group shown with two raters';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_BELOW_MINIMUM%' THEN RAISE EXCEPTION 'FAIL 1d: %', SQLERRM; END IF;
  END;
  SELECT string_agg(c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'talent' AND c.relkind = 'r'
     AND c.relname IN ('rating_scale','review_cycle','goal','goal_change','rating_history','feedback_request','feedback_rater','checkin',
                       'checkin_rule','strengths_view','pip','pip_meeting','adverse_record')
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1e: RLS missing on %', bad; END IF;
  RAISE NOTICE 'PASS 1a-e: settings, decided defaults (each position by itself, 90 days), caution, starter routes, 360 minimum, RLS';
END $$;

-- Fixtures: one employer in Ontario; Ana holds two positions; Ben manages her now, Cy managed her until April, Dee is
-- Ben's manager; Eve was hired in November; six colleagues can give feedback
INSERT INTO core.person (tenant_id, person_id)
  SELECT current_setting('app.tenant_id')::uuid, ('0e600000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid FROM generate_series(1, 11) i;
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0ea00000-0000-0000-0000-000000000001', 'ana', 'ana@example.test', '0e600000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0ea00000-0000-0000-0000-000000000002', 'ben', 'ben@example.test', '0e600000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0ea00000-0000-0000-0000-000000000003', 'cy',  'cy@example.test',  '0e600000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '0ea00000-0000-0000-0000-000000000004', 'dee', 'dee@example.test', '0e600000-0000-0000-0000-000000000004'),
  (current_setting('app.tenant_id')::uuid, '0ea00000-0000-0000-0000-000000000005', 'hr',  'hr@example.test',  NULL);
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, '0e100000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, '0e200000-0000-0000-0000-000000000001');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction) VALUES
  (current_setting('app.tenant_id')::uuid, '0e200000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Office', '1 King St', 'Toronto', 'ON', 'M5H 1A1', 'America/Toronto', 'ON');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0e300000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0e300000-0000-0000-0000-000000000002');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, '0e400000-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, '0e400000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'ANL', 'Analyst', 'Analyste');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, '0e500000-0000-0000-0000-000000000001', 'P-1'),
  (current_setting('app.tenant_id')::uuid, '0e500000-0000-0000-0000-000000000002', 'P-2'),
  (current_setting('app.tenant_id')::uuid, '0e500000-0000-0000-0000-000000000003', 'P-MGR');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0e300000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0e100000-0000-0000-0000-000000000001', 'DEPT', 'FIN', 'Finance', '0e500000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '0e300000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '0e100000-0000-0000-0000-000000000001', 'DEPT', 'IT', 'Information technology', '0e500000-0000-0000-0000-000000000003');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0e500000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), '0e400000-0000-0000-0000-000000000001', '0e300000-0000-0000-0000-000000000001', '0e200000-0000-0000-0000-000000000001', NULL, 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0e500000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0e400000-0000-0000-0000-000000000001', '0e300000-0000-0000-0000-000000000001', '0e200000-0000-0000-0000-000000000001', '0e500000-0000-0000-0000-000000000003', 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0e500000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '0e400000-0000-0000-0000-000000000001', '0e300000-0000-0000-0000-000000000002', '0e200000-0000-0000-0000-000000000001', '0e500000-0000-0000-0000-000000000003', 0.4, 'permanent', 'active');
INSERT INTO core.agreement (tenant_id, agreement_id, name, union_name, jurisdiction, status, bargaining_employer_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'UA', 'Office agreement', 'Union A', 'ON', 'in_force', '0e100000-0000-0000-0000-000000000001');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id)
  SELECT current_setting('app.tenant_id')::uuid, ('0e700000-0000-0000-0000-00000000000' || i)::uuid, ('0e600000-0000-0000-0000-00000000000' || i)::uuid,
         '0e100000-0000-0000-0000-000000000001'
    FROM generate_series(1, 5) i;
INSERT INTO core.employment_version (tenant_id, employment_id, valid_period, change_set_id, original_hire_date, continuous_service_date, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0e700000-0000-0000-0000-000000000001', '[2019-03-15,)', gen_random_uuid(), '2019-03-15', '2019-03-15', 'active'),
  (current_setting('app.tenant_id')::uuid, '0e700000-0000-0000-0000-000000000005', '[2026-11-15,)', gen_random_uuid(), '2026-11-15', '2026-11-15', 'active');
-- Assignments: 1 and 2 are Ana's two positions, 3 Ben's, 4 Cy's, 5 Dee's, 6 Eve's
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000001', '0e700000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000002', '0e700000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000003', '0e700000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000004', '0e700000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000005', '0e700000-0000-0000-0000-000000000004'),
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000006', '0e700000-0000-0000-0000-000000000005');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type, agreement_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), '0e500000-0000-0000-0000-000000000001', '0e300000-0000-0000-0000-000000000001', '0e200000-0000-0000-0000-000000000001', 0.6, true, 'permanent', NULL),
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000002', '[2026-01-01,)', gen_random_uuid(), '0e500000-0000-0000-0000-000000000002', '0e300000-0000-0000-0000-000000000002', '0e200000-0000-0000-0000-000000000001', 0.4, false, 'permanent', 'UA'),
  (current_setting('app.tenant_id')::uuid, '0e800000-0000-0000-0000-000000000003', '[2026-01-01,)', gen_random_uuid(), '0e500000-0000-0000-0000-000000000003', '0e300000-0000-0000-0000-000000000001', '0e200000-0000-0000-0000-000000000001', 1, true, 'permanent', NULL);

-- ---------------------------------------------------------------------------------
-- 2. Rating scales and cycles
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; c talent.review_cycle;
BEGIN
  INSERT INTO talent.rating_scale (tenant_id, scale_id, code, name_en, name_fr, levels, status)
    VALUES (t, '0eb00000-0000-0000-0000-000000000001', 'FIVE', 'Five points', 'Cinq points', platform.setting(t, 'performance.rating_scale_starter') -> 'levels', 'active');
  INSERT INTO talent.review_cycle (tenant_id, cycle_id, code, name_en, period, scale_id, applies_to, mid_year, status)
    VALUES (t, '0ec00000-0000-0000-0000-000000000001', 'PERF2026', '2026 reviews', '[2026-01-01,2027-01-01)', '0eb00000-0000-0000-0000-000000000001', '{}', true, 'open')
    RETURNING * INTO c;
  IF c.weights <> '{"goals":50,"competencies":50}'::jsonb OR NOT c.calibration OR c.feedback_360_use <> 'development_only'
     OR c.new_hire_no_rating_months <> 3 THEN
    RAISE EXCEPTION 'FAIL 2a: cycle not pre-filled from the settings';
  END IF;
  BEGIN
    INSERT INTO talent.review_cycle (tenant_id, code, name_en, period, scale_id, applies_to, weights, mid_year, status)
      VALUES (t, 'BAD', 'Bad weights', '[2026-01-01,2027-01-01)', '0eb00000-0000-0000-0000-000000000001', '{}', '{"goals":60,"competencies":50}', false, 'draft');
    RAISE EXCEPTION 'FAIL 2b: weights over 100 accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PERFORMANCE_WEIGHTS_INVALID%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.review_cycle (tenant_id, code, name_en, period, scale_id, applies_to, mid_year, status)
      VALUES (t, 'BAD2', 'Bad scope', '[2026-01-01,2027-01-01)', '0eb00000-0000-0000-0000-000000000001', '{"teams":["x"]}', false, 'draft');
    RAISE EXCEPTION 'FAIL 2c: unknown scope accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PAYROLL_SCOPE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 2a-c: cycles pre-filled with 50/50, calibration and development-only 360; weights add up to 100; scopes known';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Goals: aligned upward, agreed by both, every amendment kept; strengths beside the manager's view
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; g talent.goal_change;
BEGIN
  INSERT INTO talent.goal (tenant_id, goal_id, cycle_code, level, kind, title_en, proposed_by, status)
    VALUES (t, '0ed00000-0000-0000-0000-000000000001', 'PERF2026', 'organization', 'objective', 'Close the books in five days', '0ea00000-0000-0000-0000-000000000005', 'agreed');
  BEGIN
    INSERT INTO talent.goal (tenant_id, cycle_code, level, kind, title_en, proposed_by, status)
      VALUES (t, 'PERF2026', 'department', 'objective', 'Faster month-end', '0ea00000-0000-0000-0000-000000000002', 'agreed');
    RAISE EXCEPTION 'FAIL 3a: department goal with no department';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.goal (tenant_id, goal_id, cycle_code, level, org_unit_id, parent_goal_id, kind, title_en, proposed_by, status)
    VALUES (t, '0ed00000-0000-0000-0000-000000000002', 'PERF2026', 'department', '0e300000-0000-0000-0000-000000000001', '0ed00000-0000-0000-0000-000000000001',
            'objective', 'Faster month-end', '0ea00000-0000-0000-0000-000000000002', 'agreed');
  INSERT INTO talent.goal (tenant_id, goal_id, cycle_code, level, employment_id, assignment_id, parent_goal_id, kind, title_en, measure, target, weight, proposed_by, status)
    VALUES (t, '0ed00000-0000-0000-0000-000000000003', 'PERF2026', 'individual', '0e700000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000001',
            '0ed00000-0000-0000-0000-000000000002', 'objective', 'Automate the reconciliations', 'Accounts reconciled automatically', '20 accounts', 60,
            '0ea00000-0000-0000-0000-000000000001', 'proposed');
  BEGIN
    UPDATE talent.goal SET status = 'agreed', employee_agreed_at = now() WHERE goal_id = '0ed00000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 3b: goal agreed by the employee alone';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'GOAL_NOT_AGREED%' THEN RAISE EXCEPTION 'FAIL 3b: %', SQLERRM; END IF;
  END;
  UPDATE talent.goal SET status = 'agreed', employee_agreed_at = now(), manager_agreed_at = now() WHERE goal_id = '0ed00000-0000-0000-0000-000000000003';
  INSERT INTO talent.goal (tenant_id, goal_id, cycle_code, level, employment_id, assignment_id, kind, title_en, learning_ref, proposed_by, status)
    VALUES (t, '0ed00000-0000-0000-0000-000000000004', 'PERF2026', 'individual', '0e700000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000002',
            'training', 'Security awareness for IT staff', 'IT-SEC-101', '0ea00000-0000-0000-0000-000000000002', 'proposed');
  BEGIN
    UPDATE talent.goal SET target = '30 accounts' WHERE goal_id = '0ed00000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 3c: agreed goal amended by nobody';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 3c: %', SQLERRM; END IF;
  END;
  UPDATE talent.goal SET target = '30 accounts', changed_by = '0ea00000-0000-0000-0000-000000000002', change_reason = 'Two more ledgers added in June'
   WHERE goal_id = '0ed00000-0000-0000-0000-000000000003';
  SELECT * INTO g FROM talent.goal_change WHERE goal_id = '0ed00000-0000-0000-0000-000000000003';
  IF g.before ->> 'target' <> '20 accounts' OR g.after ->> 'target' <> '30 accounts' OR g.changed_by <> '0ea00000-0000-0000-0000-000000000002'::uuid THEN
    RAISE EXCEPTION 'FAIL 3d: amendment not kept with who, what and when';
  END IF;
  INSERT INTO talent.strengths_view (tenant_id, employment_id, cycle_code, author, written_by, strengths, areas_to_develop) VALUES
    (t, '0e700000-0000-0000-0000-000000000001', 'PERF2026', 'employee', '0ea00000-0000-0000-0000-000000000001', 'Analysis', 'Presenting'),
    (t, '0e700000-0000-0000-0000-000000000001', 'PERF2026', 'manager', '0ea00000-0000-0000-0000-000000000002', 'Accuracy', 'Delegation');
  RAISE NOTICE 'PASS 3a-d: goals align upward, both agree individual goals, a training goal points to learning, amendments are kept';
END $$;

-- ---------------------------------------------------------------------------------
-- 4. Section ratings: minimum days worked, reasons, the previous manager's period, reviews with no rating
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO talent.review (tenant_id, employment_id, cycle_code, kind, status)
      VALUES (t, '0e700000-0000-0000-0000-000000000001', 'PERF2026', 'annual', 'manager');
    RAISE EXCEPTION 'FAIL 4a: review without its rating mode';
  EXCEPTION WHEN not_null_violation THEN NULL;
  END;
  INSERT INTO talent.review (tenant_id, review_id, employment_id, cycle_code, kind, reviewer_assignment_id, status, rating_mode)
    VALUES (t, '0ee00000-0000-0000-0000-000000000001', '0e700000-0000-0000-0000-000000000001', 'PERF2026', 'annual', '0e800000-0000-0000-0000-000000000003', 'manager', 'rated');
  -- Cy rated January to April, Ben rates May to December, in the same position
  INSERT INTO talent.review_section (tenant_id, section_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, section_period,
                                     goal_score, competency_score, suggested_rating, rating_score) VALUES
    (t, '0ef00000-0000-0000-0000-000000000001', '0ee00000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000004',
     0.6, 120, 120, '[2026-01-01,2026-05-01)', 4, 4, 4, 4);
  INSERT INTO talent.review_section (tenant_id, section_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, section_period,
                                     goal_score, competency_score, suggested_rating) VALUES
    (t, '0ef00000-0000-0000-0000-000000000002', '0ee00000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000003',
     0.6, 245, 245, '[2026-05-01,2027-01-01)', 3, 3, 3);
  BEGIN
    INSERT INTO talent.review_section (tenant_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, section_period)
      VALUES (t, '0ee00000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000005', 0.6, 30, '[2026-04-01,2026-05-01)');
    RAISE EXCEPTION 'FAIL 4b: two sections for the same days of one position';
  EXCEPTION WHEN exclusion_violation THEN NULL;
  END;
  BEGIN
    UPDATE talent.review_section SET rating_score = 2 WHERE section_id = '0ef00000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 4c: rating different from the suggestion with no reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RATING_REASON_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4c: %', SQLERRM; END IF;
  END;
  UPDATE talent.review_section SET rating_score = 3 WHERE section_id = '0ef00000-0000-0000-0000-000000000002';
  -- The second position was held 60 days: comments only
  INSERT INTO talent.review_section (tenant_id, section_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked)
    VALUES (t, '0ef00000-0000-0000-0000-000000000003', '0ee00000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000002', '0e800000-0000-0000-0000-000000000003', 0.4, 60, 60);
  BEGIN
    UPDATE talent.review_section SET rating_score = 3 WHERE section_id = '0ef00000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 4d: section rated after 60 days';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SECTION_TOO_SHORT_TO_RATE%' THEN RAISE EXCEPTION 'FAIL 4d: %', SQLERRM; END IF;
  END;
  UPDATE talent.review_section SET rated = false WHERE section_id = '0ef00000-0000-0000-0000-000000000003';
  IF talent.review_overall('0ee00000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL 4e: a combined rating where each position stands by itself';
  END IF;

  -- Mid-year, a unit whose agreement forbids ratings, and a person hired in the last three months: no rating
  INSERT INTO talent.review (tenant_id, review_id, employment_id, cycle_code, kind, reviewer_assignment_id, status, rating_mode) VALUES
    (t, '0ee00000-0000-0000-0000-000000000002', '0e700000-0000-0000-0000-000000000001', 'PERF2026', 'mid_year', '0e800000-0000-0000-0000-000000000003', 'manager', 'rated');
  BEGIN
    INSERT INTO talent.review_section (tenant_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, rating_score)
      VALUES (t, '0ee00000-0000-0000-0000-000000000002', '0e800000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000003', 0.6, 180, 180, 3);
    RAISE EXCEPTION 'FAIL 4f: mid-year review rated';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RATING_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 4f: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.review (tenant_id, employment_id, cycle_code, kind, status, rating_mode)
      VALUES (t, '0e700000-0000-0000-0000-000000000004', 'PERF2026', 'annual', 'manager', 'development_only');
    RAISE EXCEPTION 'FAIL 4g: development-only review with no source';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.review (tenant_id, review_id, employment_id, cycle_code, kind, status, rating_mode, rating_mode_source) VALUES
    (t, '0ee00000-0000-0000-0000-000000000004', '0e700000-0000-0000-0000-000000000004', 'PERF2026', 'annual', 'manager', 'development_only', 'agreement:UA#1:12.3');
  BEGIN
    INSERT INTO talent.review_section (tenant_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, rating_score)
      VALUES (t, '0ee00000-0000-0000-0000-000000000004', '0e800000-0000-0000-0000-000000000005', '0e800000-0000-0000-0000-000000000003', 1, 365, 365, 4);
    RAISE EXCEPTION 'FAIL 4h: rating where the agreement forbids it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RATING_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 4h: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.review (tenant_id, review_id, employment_id, cycle_code, kind, reviewer_assignment_id, status, rating_mode) VALUES
    (t, '0ee00000-0000-0000-0000-000000000005', '0e700000-0000-0000-0000-000000000005', 'PERF2026', 'annual', '0e800000-0000-0000-0000-000000000003', 'manager', 'rated');
  BEGIN
    INSERT INTO talent.review_section (tenant_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, rating_score)
      VALUES (t, '0ee00000-0000-0000-0000-000000000005', '0e800000-0000-0000-0000-000000000006', '0e800000-0000-0000-0000-000000000003', 1, 47, 47, 3);
    RAISE EXCEPTION 'FAIL 4i: new hire rated';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RATING_NOT_ALLOWED: hired%' THEN RAISE EXCEPTION 'FAIL 4i: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.review_section (tenant_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, rated)
    VALUES (t, '0ee00000-0000-0000-0000-000000000005', '0e800000-0000-0000-0000-000000000006', '0e800000-0000-0000-0000-000000000003', 1, 47, 47, false);
  RAISE NOTICE 'PASS 4a-i: rating mode stated; previous manager rates their period; reasons for differences; 90 days to rate; no combined rating; mid-year, agreement and new-hire reviews unrated';
END $$;

-- ---------------------------------------------------------------------------------
-- 5. Calibration, the one-up route, HR on a concern, sign-off, HR's review, changes after release
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; route uuid; h talent.rating_history;
BEGIN
  SELECT route_id INTO route FROM platform.workflow_route WHERE tenant_id = t AND code = 'performance_review';
  UPDATE talent.review SET status = 'calibration' WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE talent.review_section SET rating_score = 2, rating_reason = 'Two missed closes' WHERE section_id = '0ef00000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 5a: calibration change with no reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RATING_CHANGE_REASON_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  UPDATE talent.review_section SET rating_score = 2, rating_reason = 'Two missed closes', changed_by = '0ea00000-0000-0000-0000-000000000005',
         change_reason = 'Calibration: consistent with the other finance teams'
   WHERE section_id = '0ef00000-0000-0000-0000-000000000002';
  SELECT * INTO h FROM talent.rating_history WHERE section_id = '0ef00000-0000-0000-0000-000000000002';
  IF h.stage <> 'calibration' OR h.old_score <> 3 OR h.new_score <> 2 THEN RAISE EXCEPTION 'FAIL 5b: calibration change not kept'; END IF;
  UPDATE talent.review SET status = 'one_up', concerns = ARRAY['differs_from_suggestion'] WHERE review_id = '0ee00000-0000-0000-0000-000000000001';

  BEGIN
    UPDATE talent.review SET status = 'released' WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5c: released before calibration';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CALIBRATION_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 5c: %', SQLERRM; END IF;
  END;
  UPDATE talent.review SET calibrated_at = now() WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE talent.review SET status = 'released', release_route_id = route WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5d: released without the one-up look';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 5d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'performance_review', '0ee00000-0000-0000-0000-000000000001', 1, 'approved', '0ea00000-0000-0000-0000-000000000002', now());
    RAISE EXCEPTION 'FAIL 5e: the reviewing manager approved their own review';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 5e: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'performance_review', '0ee00000-0000-0000-0000-000000000001', 1, 'approved', '0ea00000-0000-0000-0000-000000000001', now());
    RAISE EXCEPTION 'FAIL 5e: the employee approved their own review';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 5e: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'performance_review', '0ee00000-0000-0000-0000-000000000001', 1, 'approved', '0ea00000-0000-0000-0000-000000000004', now());
  BEGIN
    UPDATE talent.review SET status = 'released', release_route_id = route WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5f: released with a concern and no HR look';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'HR_REVIEW_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 5f: %', SQLERRM; END IF;
  END;
  UPDATE talent.review SET status = 'released', release_route_id = route, hr_reviewed_by = '0ea00000-0000-0000-0000-000000000005', hr_reviewed_at = now()
   WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
  IF (SELECT released_at FROM talent.review WHERE review_id = '0ee00000-0000-0000-0000-000000000001') IS NULL THEN
    RAISE EXCEPTION 'FAIL 5g: release time not recorded';
  END IF;

  BEGIN
    UPDATE talent.review SET status = 'signed' WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5h: signed without the employee seeing it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE '%review_signed_seen%' THEN RAISE EXCEPTION 'FAIL 5h: %', SQLERRM; END IF;
  END;
  UPDATE talent.review SET status = 'signed', acknowledged_at = now(), employee_comment = 'I closed on time once the new ledger was fixed.',
         hr_review_requested_at = now()
   WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE talent.review SET hr_review_outcome = 'upheld', hr_review_decided_by = '0ea00000-0000-0000-0000-000000000005'
     WHERE review_id = '0ee00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5i: HR decided with no reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  UPDATE talent.review SET hr_review_outcome = 'upheld', hr_review_decided_by = '0ea00000-0000-0000-0000-000000000005',
         hr_review_reason = 'The ledger fix came after the two missed closes'
   WHERE review_id = '0ee00000-0000-0000-0000-000000000001';

  BEGIN
    UPDATE talent.review_section SET rating_score = 3 WHERE section_id = '0ef00000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 5j: rating changed after release with no new reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RATING_CHANGE_REASON_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 5j: %', SQLERRM; END IF;
  END;
  UPDATE talent.review_section SET rating_score = 3, changed_by = '0ea00000-0000-0000-0000-000000000005',
         change_reason = 'Grievance settled: the missed closes were caused by the system outage'
   WHERE section_id = '0ef00000-0000-0000-0000-000000000002';
  IF NOT EXISTS (SELECT 1 FROM talent.rating_history WHERE section_id = '0ef00000-0000-0000-0000-000000000002' AND stage = 'after_final' AND new_score = 3) THEN
    RAISE EXCEPTION 'FAIL 5k: change after release not kept';
  END IF;

  -- The organization sends only the lowest rating and the reviewer's flag to HR: a protected-leave concern goes straight out
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'performance.hr_review_concerns', '["lowest_rating","flagged_by_reviewer"]', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'performance_review', '0ee00000-0000-0000-0000-000000000005', 1, 'approved', '0ea00000-0000-0000-0000-000000000004', now());
  UPDATE talent.review SET status = 'released', release_route_id = route, calibrated_at = now(), concerns = ARRAY['protected_leave']
   WHERE review_id = '0ee00000-0000-0000-0000-000000000005';
  RAISE NOTICE 'PASS 5a-k: calibration changes reasoned and kept; one-up route, never the reviewer or the employee; HR on the organization''s concerns; signed means seen; HR decides with a reason; later changes kept';
END $$;

-- ---------------------------------------------------------------------------------
-- 6. 360° feedback and check-ins
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; i int;
BEGIN
  BEGIN
    INSERT INTO talent.feedback_request (tenant_id, subject_employment_id, cycle_code, kind, purpose, requested_by, status)
      VALUES (t, '0e700000-0000-0000-0000-000000000001', 'PERF2026', '360', 'rating', '0ea00000-0000-0000-0000-000000000002', 'open');
    RAISE EXCEPTION 'FAIL 6a: 360 used for ratings in a development-only cycle';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FEEDBACK_DEVELOPMENT_ONLY%' THEN RAISE EXCEPTION 'FAIL 6a: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.feedback_request (tenant_id, request_id, subject_employment_id, cycle_code, kind, purpose, requested_by, status)
    VALUES (t, '0e0a0000-0000-0000-0000-000000000001', '0e700000-0000-0000-0000-000000000001', 'PERF2026', '360', 'development', '0ea00000-0000-0000-0000-000000000001', 'open');
  BEGIN
    INSERT INTO talent.feedback_rater (tenant_id, request_id, rater_person_id, rater_group, nominated_by, status)
      VALUES (t, '0e0a0000-0000-0000-0000-000000000001', '0e600000-0000-0000-0000-000000000001', 'peer', '0ea00000-0000-0000-0000-000000000001', 'invited');
    RAISE EXCEPTION 'FAIL 6b: the employee rates themself';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_REVIEW%' THEN RAISE EXCEPTION 'FAIL 6b: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.feedback_rater (tenant_id, request_id, rater_person_id, rater_group, nominated_by, status)
    VALUES (t, '0e0a0000-0000-0000-0000-000000000001', '0e600000-0000-0000-0000-000000000002', 'manager', '0ea00000-0000-0000-0000-000000000002', 'invited');
  -- Five peers: three nominated by Ana, two by Ben
  FOR i IN 6..10 LOOP
    INSERT INTO talent.feedback_rater (tenant_id, rater_id, request_id, rater_person_id, rater_group, nominated_by, status)
      VALUES (t, ('0e0b0000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid, '0e0a0000-0000-0000-0000-000000000001',
              ('0e600000-0000-0000-0000-0000000000' || lpad(i::text, 2, '0'))::uuid, 'peer',
              CASE WHEN i <= 8 THEN '0ea00000-0000-0000-0000-000000000001' ELSE '0ea00000-0000-0000-0000-000000000002' END::uuid, 'invited');
  END LOOP;
  BEGIN
    INSERT INTO talent.feedback_rater (tenant_id, request_id, rater_person_id, rater_group, nominated_by, status)
      VALUES (t, '0e0a0000-0000-0000-0000-000000000001', '0e600000-0000-0000-0000-000000000011', 'peer', '0ea00000-0000-0000-0000-000000000005', 'invited');
    RAISE EXCEPTION 'FAIL 6c: a sixth peer accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FEEDBACK_RATERS_OVER_MAX%' THEN RAISE EXCEPTION 'FAIL 6c: %', SQLERRM; END IF;
  END;
  UPDATE talent.feedback_rater SET status = 'submitted', answers = '{"q1":4}', submitted_at = now()
   WHERE rater_id IN ('0e0b0000-0000-0000-0000-000000000006', '0e0b0000-0000-0000-0000-000000000007');
  IF talent.feedback_group_visible('0e0a0000-0000-0000-0000-000000000001', 'peer') OR NOT talent.feedback_group_visible('0e0a0000-0000-0000-0000-000000000001', 'manager') THEN
    RAISE EXCEPTION 'FAIL 6d: two peers shown, or the manager hidden';
  END IF;
  UPDATE talent.feedback_rater SET status = 'submitted', answers = '{"q1":3}', submitted_at = now() WHERE rater_id = '0e0b0000-0000-0000-0000-000000000008';
  IF NOT talent.feedback_group_visible('0e0a0000-0000-0000-0000-000000000001', 'peer') THEN
    RAISE EXCEPTION 'FAIL 6e: three peers answered and the group is still hidden';
  END IF;
  RAISE NOTICE 'PASS 6a-e: 360 development only; raters nominated by anyone, never the employee themself; 5 per group at most; groups shown from 3 answers';

  IF NOT talent.checkin_due('0e800000-0000-0000-0000-000000000001', current_date) THEN RAISE EXCEPTION 'FAIL 6f: no check-in yet and no nudge'; END IF;
  INSERT INTO talent.checkin (tenant_id, employee_assignment_id, manager_assignment_id, held_on, shared_notes, private_notes)
    VALUES (t, '0e800000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000003', current_date - 10, 'Reconciliation tool on track', 'Ask about the course');
  IF talent.checkin_due('0e800000-0000-0000-0000-000000000001', current_date) THEN RAISE EXCEPTION 'FAIL 6g: nudged 10 days after a check-in'; END IF;
  INSERT INTO talent.checkin_rule (tenant_id, org_unit_id, nudge_days) VALUES (t, '0e300000-0000-0000-0000-000000000001', 7);
  IF NOT talent.checkin_due('0e800000-0000-0000-0000-000000000001', current_date) THEN RAISE EXCEPTION 'FAIL 6h: the team''s weekly rule ignored'; END IF;
  RAISE NOTICE 'PASS 6f-h: managers nudged after the organization''s or the team''s days without a check-in';
END $$;

-- ---------------------------------------------------------------------------------
-- 7. Performance improvement plans
-- ---------------------------------------------------------------------------------
INSERT INTO timeleave.leave_type (tenant_id, leave_type_code, name_en, name_fr, category, statutory, jurisdictions, paid_percent, job_protected, roe_trigger)
  VALUES (current_setting('app.tenant_id')::uuid, 'PARENTAL', 'Parental leave', 'Congé parental', 'parental', true, ARRAY['ON']::ref.jurisdiction_code[], 0, true, true);
INSERT INTO timeleave.leave_request (tenant_id, leave_request_id, employment_id, leave_type_code, period, hours, status)
  VALUES (current_setting('app.tenant_id')::uuid, '0e0c0000-0000-0000-0000-000000000001', '0e700000-0000-0000-0000-000000000001', 'PARENTAL',
          '[2027-05-01 00:00-04,2027-11-01 00:00-04)', 900, 'approved');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; route uuid; p talent.pip;
        ok jsonb := '{"expectations":true,"training":true,"workload":true,"accommodation":true}';
BEGIN
  SELECT route_id INTO route FROM platform.workflow_route WHERE tenant_id = t AND code = 'pip';
  BEGIN
    INSERT INTO talent.pip (tenant_id, employment_id, assignment_id, created_by, causes_ruled_out, gaps, standards, measures, support, start_on, protected_ground_possible, status)
      VALUES (t, '0e700000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000001', '0ea00000-0000-0000-0000-000000000002',
              '{"expectations":true,"training":true,"workload":false,"accommodation":true}', '["Month-end close late"]', 'Close in 5 days', 'Days to close',
              'Weekly coaching', '2027-02-01', false, 'submitted');
    RAISE EXCEPTION 'FAIL 7a: plan submitted before workload was ruled out';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PIP_CAUSES_NOT_REVIEWED%' THEN RAISE EXCEPTION 'FAIL 7a: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.pip (tenant_id, pip_id, employment_id, assignment_id, created_by, causes_ruled_out, gaps, standards, measures, support, start_on, protected_ground_possible, status)
    VALUES (t, '0e0d0000-0000-0000-0000-000000000001', '0e700000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000001', '0ea00000-0000-0000-0000-000000000002',
            ok, '["Month-end close late"]', 'Close in 5 days', 'Days to close', 'Weekly coaching', '2027-02-01', false, 'submitted')
    RETURNING * INTO p;
  IF p.end_on <> '2027-04-02' THEN RAISE EXCEPTION 'FAIL 7b: plan length not 60 days by default (%)', p.end_on; END IF;
  BEGIN
    UPDATE talent.pip SET status = 'approved' WHERE pip_id = p.pip_id;
    RAISE EXCEPTION 'FAIL 7c: plan approved without HR';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 7c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'pip', p.pip_id, 1, 'approved', '0ea00000-0000-0000-0000-000000000002', now(), 'hr');
    RAISE EXCEPTION 'FAIL 7d: the manager approved their own plan';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 7d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'pip', p.pip_id, 1, 'approved', '0ea00000-0000-0000-0000-000000000001', now(), 'hr');
    RAISE EXCEPTION 'FAIL 7d: the employee approved the plan';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 7d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'pip', p.pip_id, 1, 'approved', '0ea00000-0000-0000-0000-000000000005', now(), 'hr');
  UPDATE talent.pip SET status = 'approved', route_id = route WHERE pip_id = p.pip_id;
  BEGIN
    UPDATE talent.pip SET status = 'active' WHERE pip_id = p.pip_id;
    RAISE EXCEPTION 'FAIL 7e: plan started before the employee acknowledged it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7e: %', SQLERRM; END IF;
  END;
  UPDATE talent.pip SET status = 'active', employee_acknowledged_at = now() WHERE pip_id = p.pip_id;
  INSERT INTO talent.pip_meeting (tenant_id, pip_id, held_on, representation, notes)
    VALUES (t, p.pip_id, '2027-02-01', 'support_person', 'Ana brought a colleague');
  BEGIN
    UPDATE talent.pip SET status = 'extended' WHERE pip_id = p.pip_id;
    RAISE EXCEPTION 'FAIL 7f: extended with no reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE talent.pip SET status = 'extended', extension_reason = 'Good progress, one more close to see' WHERE pip_id = p.pip_id;
    RAISE EXCEPTION 'FAIL 7f: extended with the same end date';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7f: %', SQLERRM; END IF;
  END;
  UPDATE talent.pip SET status = 'extended', extension_reason = 'Good progress, one more close to see', end_on = '2027-05-02' WHERE pip_id = p.pip_id;
  RAISE NOTICE 'PASS 7a-f: causes ruled out first; 60 days by default; HR approves through the route, never the manager or the employee; acknowledged before it starts; extensions reasoned';

  -- During a protected leave: never; a protected ground: the caution first
  INSERT INTO talent.pip (tenant_id, pip_id, employment_id, assignment_id, created_by, causes_ruled_out, gaps, standards, measures, support, start_on, protected_ground_possible, status, route_id)
    VALUES (t, '0e0d0000-0000-0000-0000-000000000002', '0e700000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000001', '0ea00000-0000-0000-0000-000000000002',
            ok, '["Errors"]', 'No errors', 'Errors found', 'Checklist', '2027-06-01', false, 'submitted', route);
  BEGIN
    UPDATE talent.pip SET status = 'approved' WHERE pip_id = '0e0d0000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 7g: plan during parental leave';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PIP_DURING_PROTECTED_LEAVE%' THEN RAISE EXCEPTION 'FAIL 7g: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.pip (tenant_id, pip_id, employment_id, assignment_id, created_by, causes_ruled_out, gaps, standards, measures, support, start_on, protected_ground_possible, status, route_id)
    VALUES (t, '0e0d0000-0000-0000-0000-000000000003', '0e700000-0000-0000-0000-000000000001', '0e800000-0000-0000-0000-000000000002', '0ea00000-0000-0000-0000-000000000002',
            ok, '["Slow tickets"]', 'Tickets in 2 days', 'Ticket age', 'Pairing', '2027-01-15', true, 'submitted', route);
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'pip', '0e0d0000-0000-0000-0000-000000000003', 1, 'approved', '0ea00000-0000-0000-0000-000000000005', now(), 'hr');
  BEGIN
    UPDATE talent.pip SET status = 'approved' WHERE pip_id = '0e0d0000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 7h: plan approved where a protected ground may be involved, without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 7h: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'performance.pip_protected_ground', 'pip', '0e0d0000-0000-0000-0000-000000000003', 'shown', 'en', '0ea00000-0000-0000-0000-000000000005',
            'Accommodation reviewed with Ana: screen reader provided in December; the gap remains');
  UPDATE talent.pip SET status = 'approved' WHERE pip_id = '0e0d0000-0000-0000-0000-000000000003';
  RAISE NOTICE 'PASS 7g-h: no plan during protected leave; a possible protected ground needs the accommodation caution';
END $$;

-- ---------------------------------------------------------------------------------
-- 8. Adverse records and sunset clauses
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; s date;
BEGIN
  INSERT INTO talent.adverse_record (tenant_id, employment_id, subject_type, subject_id, recorded_on, basis)
    VALUES (t, '0e700000-0000-0000-0000-000000000001', 'review', '0ee00000-0000-0000-0000-000000000001', '2026-12-15', 'organization')
    RETURNING sunset_on INTO s;
  IF s IS NOT NULL OR NOT talent.adverse_record_in_force('review', '0ee00000-0000-0000-0000-000000000001', '2035-01-01') THEN
    RAISE EXCEPTION 'FAIL 8a: a non-union record has a sunset the organization did not set';
  END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'performance.non_union_sunset', '{"months":24}', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO talent.adverse_record (tenant_id, employment_id, subject_type, subject_id, recorded_on, basis)
    VALUES (t, '0e700000-0000-0000-0000-000000000001', 'pip', '0e0d0000-0000-0000-0000-000000000001', '2027-05-02', 'organization')
    RETURNING sunset_on INTO s;
  IF s <> '2029-05-02' OR NOT talent.adverse_record_in_force('pip', '0e0d0000-0000-0000-0000-000000000001', '2029-05-01')
     OR talent.adverse_record_in_force('pip', '0e0d0000-0000-0000-0000-000000000001', '2029-05-02') THEN
    RAISE EXCEPTION 'FAIL 8b: the organization''s 24 months not applied (%)', s;
  END IF;
  BEGIN
    INSERT INTO talent.adverse_record (tenant_id, employment_id, subject_type, subject_id, recorded_on, basis, agreement_id)
      VALUES (t, '0e700000-0000-0000-0000-000000000001', 'review', '0ee00000-0000-0000-0000-000000000002', '2026-07-01', 'agreement', 'UA');
    RAISE EXCEPTION 'FAIL 8c: agreement record with no sunset';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.adverse_record (tenant_id, employment_id, subject_type, subject_id, recorded_on, basis, agreement_id, sunset_on)
    VALUES (t, '0e700000-0000-0000-0000-000000000001', 'review', '0ee00000-0000-0000-0000-000000000002', '2026-07-01', 'agreement', 'UA', '2027-07-01');
  RAISE NOTICE 'PASS 8a-c: no sunset for non-union staff unless the organization sets one; the agreement''s period otherwise; records stop counting on the sunset';
END $$;

-- ---------------------------------------------------------------------------------
-- 9. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', 'e2222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM talent.goal) <> 0 OR (SELECT count(*) FROM talent.pip) <> 0 OR (SELECT count(*) FROM talent.feedback_rater) <> 0
     OR (SELECT count(*) FROM talent.checkin) <> 0 OR (SELECT count(*) FROM talent.adverse_record) <> 0 OR (SELECT count(*) FROM talent.rating_history) <> 0
     OR (SELECT count(*) FROM talent.review_cycle) <> 0 OR (SELECT count(*) FROM talent.strengths_view) <> 0 THEN
    RAISE EXCEPTION 'FAIL 9: another organization''s performance data is visible';
  END IF;
  RAISE NOTICE 'PASS 9: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0014_smoke: all checks passed'
