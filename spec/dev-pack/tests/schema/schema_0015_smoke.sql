-- Smoke test for schema/0015_learning_decisions.sql (docs/29): the new settings, the law's training and rules that can be
-- stricter but never looser, assignments (never waiving the law's training, council and board members, the
-- organization's language), completions (sign-offs, paid time), refresher cycles, the law's changes, notices,
-- credentials and their verification and alerts, continuing education, apprenticeships, readiness for a shift,
-- skills consent, development plans, training requests through the route with the HR amount and the budget,
-- repayment rules, grants, mentoring, sessions, RLS and tenant isolation.
-- Run after every migration, 0001 to 0015 (CI, after the 0014 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0015_smoke.sql
-- Shifts are placed relative to now(); nothing else depends on today's date. It inserts test rows; run
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
  ('f1111111-1111-1111-1111-111111111111', 'Learning Test Society'),
  ('f2222222-2222-2222-2222-222222222222', 'Other Organization')
ON CONFLICT DO NOTHING;

-- The law's training as the loader writes it from rules/learning (test codes, so they never clash with a real edition)
INSERT INTO ref.training_requirement (requirement_code, jurisdiction, topic, name_en, audience, before_work, due_days, due_note, frequency_months, cite, status, effective_from) VALUES
  ('TEST-SUPERVISOR', 'BC', 'health_safety', 'Supervisor awareness', '{"roles":["supervisor"]}', false, 7, NULL, NULL, 'test', 'secondary', '2020-01-01'),
  ('TEST-ORIENTATION', 'BC', 'orientation', 'New worker orientation', '{"roles":["new_worker"]}', true, NULL, NULL, NULL, 'test', 'official', '2020-01-01'),
  ('TEST-HV', 'BC', 'harassment_violence', 'Harassment and violence prevention', '{"roles":["employee"]}', false, 90, 'within three months', 36, 'test', 'official', '2020-01-01'),
  ('TEST-ASAP', 'BC', 'accessibility', 'Accessible service', '{"roles":["employee"]}', false, NULL, 'as soon as practicable', NULL, 'test', 'secondary', '2020-01-01'),
  ('TEST-UNVERIFIED', 'BC', 'privacy', 'Privacy basics', '{"roles":["employee"]}', false, 30, NULL, NULL, 'test', 'verify_at_load', '2020-01-01')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', 'f1111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, cautions, starter routes, RLS
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/29%') <> 8
     OR (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/29%' AND decision_status = 'pending') <> 2 THEN
    RAISE EXCEPTION 'FAIL 1a: expected 8 settings from docs/29, 2 chosen at setup';
  END IF;
  IF platform.setting(t, 'learning.overdue_escalation') <> '{"remindDaysBefore":[14,3],"managerDaysAfter":1,"hrDaysAfter":7}'::jsonb
     OR platform.setting_number(t, 'learning.refresher_early_window_days') <> 60 OR platform.setting_number(t, 'learning.law_change_due_days') <> 30
     OR platform.setting(t, 'learning.credential_alert_days') <> '{"employee":[90,60,30],"managerAndHr":[30,0]}'::jsonb
     OR jsonb_array_length(platform.setting(t, 'learning.assignment_events')) <> 5
     OR platform.setting_number(t, 'learning.records_keep_extra_years') <> 0 THEN
    RAISE EXCEPTION 'FAIL 1b: decided defaults not in place';
  END IF;
  BEGIN
    PERFORM platform.setting(t, 'learning.request_hr_above_amount');
    RAISE EXCEPTION 'FAIL 1c: an HR amount CanDo chose';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 1c: %', SQLERRM; END IF;
  END;
  IF (SELECT count(*) FROM ref.caution WHERE caution_code IN ('learning.not_ready_for_work','learning.over_budget') AND reason_always) <> 2
     OR (SELECT count(*) FROM platform.workflow_route WHERE tenant_id = t AND subject_type = 'training_request') <> 2 THEN
    RAISE EXCEPTION 'FAIL 1d: cautions or starter routes missing';
  END IF;
  SELECT string_agg(c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'talent' AND c.relkind = 'r'
     AND c.relname IN ('learning_item','learning_session','session_attendee','training_rule','learning_assignment','learning_completion',
                       'credential','ce_requirement','apprenticeship','apprenticeship_hours','skills_consent','development_plan',
                       'development_action','development_plan_change','training_budget','repayment_rule','training_request','grant_claim',
                       'mentoring_pair','mentoring_session')
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1e: RLS missing on %', bad; END IF;
  RAISE NOTICE 'PASS 1a-e: settings (two chosen at setup), defaults, cautions, starter routes, RLS';
END $$;

-- Fixtures: one employer in BC; Ana (a nurse), Ben (her manager), Cy (a nurse without a registration), Dee (a council
-- member, no employment), HR
INSERT INTO core.person (tenant_id, person_id, person_type) VALUES
  (current_setting('app.tenant_id')::uuid, '0f600000-0000-0000-0000-000000000001', 'employee'),
  (current_setting('app.tenant_id')::uuid, '0f600000-0000-0000-0000-000000000002', 'employee'),
  (current_setting('app.tenant_id')::uuid, '0f600000-0000-0000-0000-000000000003', 'employee'),
  (current_setting('app.tenant_id')::uuid, '0f600000-0000-0000-0000-000000000004', 'board_appointee');
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0fa00000-0000-0000-0000-000000000001', 'ana', 'ana@example.test', '0f600000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0fa00000-0000-0000-0000-000000000002', 'ben', 'ben@example.test', '0f600000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0fa00000-0000-0000-0000-000000000003', 'cy',  'cy@example.test',  '0f600000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '0fa00000-0000-0000-0000-000000000005', 'hr',  'hr@example.test',  NULL);
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, '0f100000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, '0f200000-0000-0000-0000-000000000001');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction) VALUES
  (current_setting('app.tenant_id')::uuid, '0f200000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Care home', '1 Main St', 'Victoria', 'BC', 'V8W 1A1', 'America/Vancouver', 'BC');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, '0f300000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0f400000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0f400000-0000-0000-0000-000000000002');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, '0f400000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'RN', 'Registered Nurse', 'Infirmière autorisée'),
  (current_setting('app.tenant_id')::uuid, '0f400000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'MGR', 'Care Manager', 'Gestionnaire des soins');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, '0f500000-0000-0000-0000-000000000001', 'P-RN1'),
  (current_setting('app.tenant_id')::uuid, '0f500000-0000-0000-0000-000000000002', 'P-MGR'),
  (current_setting('app.tenant_id')::uuid, '0f500000-0000-0000-0000-000000000003', 'P-RN2');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0f300000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0f100000-0000-0000-0000-000000000001', 'DEPT', 'CARE', 'Care', '0f500000-0000-0000-0000-000000000002');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0f500000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '0f400000-0000-0000-0000-000000000002', '0f300000-0000-0000-0000-000000000001', '0f200000-0000-0000-0000-000000000001', NULL, 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0f500000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0f400000-0000-0000-0000-000000000001', '0f300000-0000-0000-0000-000000000001', '0f200000-0000-0000-0000-000000000001', '0f500000-0000-0000-0000-000000000002', 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0f500000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), '0f400000-0000-0000-0000-000000000001', '0f300000-0000-0000-0000-000000000001', '0f200000-0000-0000-0000-000000000001', '0f500000-0000-0000-0000-000000000002', 1, 'permanent', 'active');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0f700000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000001', '0f100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0f700000-0000-0000-0000-000000000002', '0f600000-0000-0000-0000-000000000002', '0f100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0f700000-0000-0000-0000-000000000003', '0f600000-0000-0000-0000-000000000003', '0f100000-0000-0000-0000-000000000001');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0f800000-0000-0000-0000-000000000001', '0f700000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0f800000-0000-0000-0000-000000000002', '0f700000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0f800000-0000-0000-0000-000000000003', '0f700000-0000-0000-0000-000000000003');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type) VALUES
  (current_setting('app.tenant_id')::uuid, '0f800000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), '0f500000-0000-0000-0000-000000000001', '0f300000-0000-0000-0000-000000000001', '0f200000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '0f800000-0000-0000-0000-000000000002', '[2026-01-01,)', gen_random_uuid(), '0f500000-0000-0000-0000-000000000002', '0f300000-0000-0000-0000-000000000001', '0f200000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '0f800000-0000-0000-0000-000000000003', '[2026-01-01,)', gen_random_uuid(), '0f500000-0000-0000-0000-000000000003', '0f300000-0000-0000-0000-000000000001', '0f200000-0000-0000-0000-000000000001', 1, true, 'permanent');
-- The nurse job requires a registration the law requires and first aid the organization requires
INSERT INTO core.work_requirement (tenant_id, requirement_id, target_type, target_id, status, kind, strength, text_en, satisfied_by, rationale, source, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', '0f400000-0000-0000-0000-000000000001', 'active', 'registration', 'required',
   'Practising registration with the nursing college', '[{"credential":"RN-BC"}]', 'Required by the Health Professions Act to practise', 'legislation', '[2020-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', '0f400000-0000-0000-0000-000000000001', 'active', 'certification', 'required',
   'Standard first aid', '[{"credential":"FA-STD"}]', 'Residents may need first aid at any time', 'job', '[2020-01-01,)', gen_random_uuid());
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by) VALUES
  (current_setting('app.tenant_id')::uuid, '0f0d0000-0000-0000-0000-000000000001', 'person', '0f600000-0000-0000-0000-000000000001', 'certificate', 'restricted', 'learning', 'docs/c1', 'h1', 'application/pdf', '0fa00000-0000-0000-0000-000000000005'),
  (current_setting('app.tenant_id')::uuid, '0f0d0000-0000-0000-0000-000000000002', 'person', '0f600000-0000-0000-0000-000000000001', 'repayment_agreement', 'restricted', 'learning', 'docs/r1', 'h2', 'application/pdf', '0fa00000-0000-0000-0000-000000000005');

-- ---------------------------------------------------------------------------------
-- 2. Learning items and rules: the law's training can be made stricter, never looser
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r talent.training_rule;
BEGIN
  INSERT INTO talent.learning_item (tenant_id, item_id, code, title_en, title_fr, kind, provider_kind, standard, external_ref, languages, duration_minutes, credits, version, status) VALUES
    (t, '0fb00000-0000-0000-0000-000000000001', 'SUP-AWARE', 'Supervisor awareness', 'Sensibilisation des superviseurs', 'elearning', 'government', 'none', 'https://example.test/sup', ARRAY['en','fr'], 60, 1, '2026.1', 'active'),
    (t, '0fb00000-0000-0000-0000-000000000002', 'ORIENT', 'New worker orientation', 'Orientation des nouveaux travailleurs', 'on_the_job', 'internal', NULL, NULL, ARRAY['en'], 120, NULL, '1', 'active'),
    (t, '0fb00000-0000-0000-0000-000000000003', 'HV', 'Harassment and violence prevention', 'Prévention du harcèlement et de la violence', 'elearning', 'partner_library', 'scorm_2004', 'LIB-HV-1', ARRAY['en','fr'], 90, 1.5, '3', 'active'),
    (t, '0fb00000-0000-0000-0000-000000000004', 'WOUND', 'Wound care update', NULL, 'classroom', 'internal', NULL, NULL, ARRAY['en'], 240, 4, '1', 'active');
  BEGIN
    INSERT INTO talent.training_rule (tenant_id, code, name_en, source, requirement_code, item_id, applies_to, due_days, blocks_work, status)
      VALUES (t, 'SUP14', 'Supervisors', 'law', 'TEST-SUPERVISOR', '0fb00000-0000-0000-0000-000000000001', '{"supervisors":true}', 14, false, 'active');
    RAISE EXCEPTION 'FAIL 2a: 14 days where the law says 7';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'TRAINING_RULE_LOOSER_THAN_LAW%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.training_rule (tenant_id, rule_id, code, name_en, source, requirement_code, item_id, applies_to, due_days, blocks_work, status)
    VALUES (t, '0fc00000-0000-0000-0000-000000000001', 'SUP5', 'Supervisors', 'law', 'TEST-SUPERVISOR', '0fb00000-0000-0000-0000-000000000001', '{"supervisors":true}', 5, false, 'active')
    RETURNING * INTO r;
  IF cardinality(r.events) <> 5 OR r.early_window_days <> 60 THEN RAISE EXCEPTION 'FAIL 2b: rule not pre-filled from the settings'; END IF;
  BEGIN
    INSERT INTO talent.training_rule (tenant_id, code, name_en, source, requirement_code, item_id, applies_to, due_days, frequency_months, grace_days, blocks_work, status)
      VALUES (t, 'HVG', 'HV with grace', 'law', 'TEST-HV', '0fb00000-0000-0000-0000-000000000003', '{}', 60, 36, 30, false, 'active');
    RAISE EXCEPTION 'FAIL 2c: a grace period on the law''s training';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'TRAINING_RULE_LOOSER_THAN_LAW%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.training_rule (tenant_id, code, name_en, source, requirement_code, item_id, applies_to, due_days, frequency_months, blocks_work, status)
      VALUES (t, 'HV48', 'HV every 4 years', 'law', 'TEST-HV', '0fb00000-0000-0000-0000-000000000003', '{}', 60, 48, false, 'active');
    RAISE EXCEPTION 'FAIL 2d: refresher less often than the law';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'TRAINING_RULE_LOOSER_THAN_LAW%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.training_rule (tenant_id, rule_id, code, name_en, source, requirement_code, item_id, applies_to, due_days, frequency_months, blocks_work, status)
    VALUES (t, '0fc00000-0000-0000-0000-000000000002', 'HV', 'Harassment and violence prevention', 'law', 'TEST-HV', '0fb00000-0000-0000-0000-000000000003', '{}', 60, 36, false, 'active');
  BEGIN
    INSERT INTO talent.training_rule (tenant_id, code, name_en, source, requirement_code, item_id, applies_to, blocks_work, status)
      VALUES (t, 'ORX', 'Orientation after starting', 'law', 'TEST-ORIENTATION', '0fb00000-0000-0000-0000-000000000002', '{}', false, 'active');
    RAISE EXCEPTION 'FAIL 2e: orientation the law requires before work allowed after it';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.training_rule (tenant_id, rule_id, code, name_en, source, requirement_code, item_id, applies_to, blocks_work, status)
    VALUES (t, '0fc00000-0000-0000-0000-000000000003', 'ORIENT', 'New worker orientation', 'law', 'TEST-ORIENTATION', '0fb00000-0000-0000-0000-000000000002', '{"locations":["0f200000-0000-0000-0000-000000000001"]}', true, 'active');
  BEGIN
    INSERT INTO talent.training_rule (tenant_id, code, name_en, source, requirement_code, item_id, applies_to, due_days, blocks_work, status)
      VALUES (t, 'PRIV', 'Privacy', 'law', 'TEST-UNVERIFIED', '0fb00000-0000-0000-0000-000000000003', '{}', 30, false, 'active');
    RAISE EXCEPTION 'FAIL 2f: an unverified law value applied';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RULE_NOT_VERIFIED%' THEN RAISE EXCEPTION 'FAIL 2f: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.training_rule (tenant_id, code, name_en, source, item_id, applies_to, due_days, blocks_work, status)
      VALUES (t, 'TEAMS', 'By team', 'organization', '0fb00000-0000-0000-0000-000000000004', '{"teams":["x"]}', 30, false, 'active');
    RAISE EXCEPTION 'FAIL 2g: unknown scope accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'TRAINING_SCOPE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 2g: %', SQLERRM; END IF;
  END;
  -- The organization's own rule may have a grace period
  INSERT INTO talent.training_rule (tenant_id, rule_id, code, name_en, source, item_id, applies_to, due_days, frequency_months, grace_days, blocks_work, status)
    VALUES (t, '0fc00000-0000-0000-0000-000000000004', 'WOUND', 'Wound care', 'organization', '0fb00000-0000-0000-0000-000000000004', '{"jobs":["0f400000-0000-0000-0000-000000000001"]}', 30, 24, 14, false, 'active');
  RAISE NOTICE 'PASS 2a-g: the law''s training stricter but never looser, before work stays before work, unverified law not applied, scopes known; own rules may add grace';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Assignments, completions, refresher cycles, the law's changes, notices
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; a talent.learning_assignment; n int;
BEGIN
  INSERT INTO talent.learning_assignment (tenant_id, assignment_id, person_id, employment_id, item_id, rule_id, source, event, assigned_on, due_on, blocks_work, status, assigned_by)
    VALUES (t, '0fd00000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000001', '0f700000-0000-0000-0000-000000000001', '0fb00000-0000-0000-0000-000000000003',
            '0fc00000-0000-0000-0000-000000000002', 'rule', 'hire', '2027-01-01', '2027-03-01', false, 'assigned', NULL)
    RETURNING * INTO a;
  IF a.language <> 'en' THEN RAISE EXCEPTION 'FAIL 3a: not assigned in the organization''s main language'; END IF;
  BEGIN
    UPDATE talent.learning_assignment SET status = 'waived', waived_by = '0fa00000-0000-0000-0000-000000000005', waive_reason = 'Did it elsewhere'
     WHERE assignment_id = a.assignment_id;
    RAISE EXCEPTION 'FAIL 3b: the law''s training waived';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LEGAL_TASK_CANNOT_BE_WAIVED%' THEN RAISE EXCEPTION 'FAIL 3b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.learning_assignment (tenant_id, person_id, item_id, source, assigned_on, due_on, blocks_work, status)
      VALUES (t, '0f600000-0000-0000-0000-000000000003', '0fb00000-0000-0000-0000-000000000004', 'manager', '2027-01-01', '2027-02-01', false, 'assigned');
    RAISE EXCEPTION 'FAIL 3c: an employee''s training with no employment';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 3c: %', SQLERRM; END IF;
  END;
  -- A council or board member's training has no employment
  INSERT INTO talent.learning_assignment (tenant_id, person_id, item_id, source, assigned_on, due_on, blocks_work, status)
    VALUES (t, '0f600000-0000-0000-0000-000000000004', '0fb00000-0000-0000-0000-000000000003', 'manager', '2027-01-01', '2027-02-01', false, 'assigned');

  BEGIN
    INSERT INTO talent.learning_completion (tenant_id, person_id, item_id, item_version, completed_on, source, outside_schedule, signed_off_by, recorded_by)
      VALUES (t, '0f600000-0000-0000-0000-000000000001', '0fb00000-0000-0000-0000-000000000002', '1', '2027-01-02', 'on_the_job_signoff', false,
              '0fa00000-0000-0000-0000-000000000001', '0fa00000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL 3d: on-the-job training signed off by the learner';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SIGNOFF_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 3d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.learning_completion (tenant_id, person_id, item_id, item_version, assignment_id, completed_on, source, outside_schedule, recorded_by)
      VALUES (t, '0f600000-0000-0000-0000-000000000001', '0fb00000-0000-0000-0000-000000000003', '3', a.assignment_id, '2027-01-15', 'lms_import', true,
              '0fa00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 3e: mandatory training outside hours with no paid time';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 3e: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.learning_completion (tenant_id, person_id, item_id, item_version, assignment_id, completed_on, source, credits, outside_schedule, training_minutes, recorded_by)
    VALUES (t, '0f600000-0000-0000-0000-000000000001', '0fb00000-0000-0000-0000-000000000003', '3', a.assignment_id, '2027-01-15', 'lms_import', 1.5, true, 90,
            '0fa00000-0000-0000-0000-000000000005');
  IF (SELECT status FROM talent.learning_assignment WHERE assignment_id = a.assignment_id) <> 'completed' THEN
    RAISE EXCEPTION 'FAIL 3f: completion did not complete the assignment';
  END IF;
  IF talent.next_due_on('0fc00000-0000-0000-0000-000000000002', '2027-03-01', '2027-01-15') <> '2030-03-01'
     OR talent.next_due_on('0fc00000-0000-0000-0000-000000000002', '2027-03-01', '2026-11-01') <> '2029-11-01'
     OR talent.next_due_on('0fc00000-0000-0000-0000-000000000002', '2027-03-01', '2027-04-10') <> '2030-04-10' THEN
    RAISE EXCEPTION 'FAIL 3g: refresher cycle wrong';
  END IF;
  IF talent.law_change_due_on(t, 'TEST-HV', '2027-06-01', NULL) <> '2027-08-30'
     OR talent.law_change_due_on(t, 'TEST-ASAP', '2027-06-01', NULL) <> '2027-07-01' THEN
    RAISE EXCEPTION 'FAIL 3h: the law''s deadline, else the organization''s 30 days';
  END IF;
  INSERT INTO talent.learning_assignment (tenant_id, assignment_id, person_id, employment_id, item_id, rule_id, source, assigned_on, due_on, blocks_work, status)
    VALUES (t, '0fd00000-0000-0000-0000-000000000002', '0f600000-0000-0000-0000-000000000003', '0f700000-0000-0000-0000-000000000003', '0fb00000-0000-0000-0000-000000000004',
            '0fc00000-0000-0000-0000-000000000004', 'rule', '2027-01-01', '2027-02-01', false, 'assigned');
  SELECT count(*) INTO n FROM talent.learning_notices_due(t, '2027-01-18') x WHERE x.assignment_id = '0fd00000-0000-0000-0000-000000000002' AND x.notify = 'employee' AND x.days = 14;
  IF n <> 1
     OR NOT EXISTS (SELECT 1 FROM talent.learning_notices_due(t, '2027-01-29') x WHERE x.assignment_id = '0fd00000-0000-0000-0000-000000000002' AND x.days = 3)
     OR NOT EXISTS (SELECT 1 FROM talent.learning_notices_due(t, '2027-02-16') x WHERE x.assignment_id = '0fd00000-0000-0000-0000-000000000002' AND x.notify = 'manager')
     OR NOT EXISTS (SELECT 1 FROM talent.learning_notices_due(t, '2027-02-22') x WHERE x.assignment_id = '0fd00000-0000-0000-0000-000000000002' AND x.notify = 'hr') THEN
    RAISE EXCEPTION 'FAIL 3i: notices not 14 and 3 days before, manager 1 day and HR 7 days after the grace period';
  END IF;
  RAISE NOTICE 'PASS 3a-i: main language; the law never waived; officials without employment; sign-off by another; paid time; cycles; law changes; notices';
END $$;

-- ---------------------------------------------------------------------------------
-- 4. Credentials, continuing education and apprenticeships
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO talent.credential (tenant_id, person_id, credential_code, kind, issuer, expires_on, status)
      VALUES (t, '0f600000-0000-0000-0000-000000000001', 'RN-BC', 'registration', 'BC College of Nurses and Midwives', '2028-01-01', 'valid');
    RAISE EXCEPTION 'FAIL 4a: valid without verification';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO talent.credential (tenant_id, person_id, credential_code, kind, issuer, expires_on, status, verified_by, verified_at, verification_method)
      VALUES (t, '0f600000-0000-0000-0000-000000000001', 'RN-BC', 'registration', 'BCCNM', '2028-01-01', 'valid', '0fa00000-0000-0000-0000-000000000001', now(), 'document');
    RAISE EXCEPTION 'FAIL 4b: verified by its holder';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 4b: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.credential (tenant_id, credential_id, person_id, credential_code, kind, issuer, issued_on, expires_on, status, verified_by, verified_at, verification_method, document_id) VALUES
    (t, '0fe00000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000001', 'RN-BC', 'registration', 'BCCNM', '2024-01-01', '2028-01-01', 'valid',
     '0fa00000-0000-0000-0000-000000000005', now(), 'public_registry', NULL),
    (t, '0fe00000-0000-0000-0000-000000000002', '0f600000-0000-0000-0000-000000000003', 'RN-BC', 'registration', 'BCCNM', '2024-01-01', '2028-01-01', 'pending',
     NULL, NULL, NULL, NULL);
  IF NOT talent.credential_valid('0f600000-0000-0000-0000-000000000001', 'RN-BC', '2027-12-31')
     OR talent.credential_valid('0f600000-0000-0000-0000-000000000001', 'RN-BC', '2028-01-01')
     OR talent.credential_valid('0f600000-0000-0000-0000-000000000003', 'RN-BC', '2027-01-01') THEN
    RAISE EXCEPTION 'FAIL 4c: valid until expiry; pending never valid';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM talent.credential_alerts_due(t, '2027-10-03') x WHERE x.credential_id = '0fe00000-0000-0000-0000-000000000001' AND x.audience = 'employee' AND x.days = 90)
     OR EXISTS (SELECT 1 FROM talent.credential_alerts_due(t, '2027-10-03') x WHERE x.audience = 'manager_and_hr')
     OR (SELECT count(*) FROM talent.credential_alerts_due(t, '2027-12-02') x WHERE x.credential_id = '0fe00000-0000-0000-0000-000000000001') <> 2
     OR NOT EXISTS (SELECT 1 FROM talent.credential_alerts_due(t, '2028-01-01') x WHERE x.credential_id = '0fe00000-0000-0000-0000-000000000001' AND x.audience = 'manager_and_hr' AND x.days = 0) THEN
    RAISE EXCEPTION 'FAIL 4d: alerts not employee 90/60/30, manager and HR at 30 and on expiry';
  END IF;
  INSERT INTO talent.ce_requirement (tenant_id, credential_code, body, hours_required, period_months, remind_days_before)
    VALUES (t, 'RN-BC', 'BCCNM', 30, 24, ARRAY[90,30]);
  IF talent.ce_progress('0f600000-0000-0000-0000-000000000001', 'RN-BC', '[2026-01-01,2028-01-01)') <> 1.5 THEN
    RAISE EXCEPTION 'FAIL 4e: continuing education credits not counted';
  END IF;
  INSERT INTO talent.apprenticeship (tenant_id, apprenticeship_id, person_id, employment_id, trade, jurisdiction, level, level_hours_required, status)
    VALUES (t, '0f0a0000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000003', '0f700000-0000-0000-0000-000000000003', 'Cook', 'BC', 1, 1500, 'active');
  INSERT INTO talent.apprenticeship_hours (tenant_id, apprenticeship_id, level, period, hours, kind, source, recorded_by) VALUES
    (t, '0f0a0000-0000-0000-0000-000000000001', 1, '[2027-01-01,2027-02-01)', 140, 'on_the_job', 'timesheet', '0fa00000-0000-0000-0000-000000000005'),
    (t, '0f0a0000-0000-0000-0000-000000000001', 1, '[2027-02-01,2027-03-01)', 120, 'technical_training', 'school_record', '0fa00000-0000-0000-0000-000000000005');
  IF talent.apprentice_hours('0f0a0000-0000-0000-0000-000000000001', 1::smallint) <> 140 THEN
    RAISE EXCEPTION 'FAIL 4f: apprenticeship hours on the job';
  END IF;
  RAISE NOTICE 'PASS 4a-f: verified by someone else; valid until expiry; pending never valid; alerts; continuing education; apprenticeship hours';
END $$;

-- ---------------------------------------------------------------------------------
-- 5. Ready for the work when a shift is published
-- ---------------------------------------------------------------------------------
INSERT INTO timeleave.shift (tenant_id, shift_id, assignment_id, position_id, location_id, starts_at, ends_at, break_minutes, published) VALUES
  (current_setting('app.tenant_id')::uuid, '0f950000-0000-0000-0000-000000000001', '0f800000-0000-0000-0000-000000000001', '0f500000-0000-0000-0000-000000000001', '0f200000-0000-0000-0000-000000000001',
   date_trunc('hour', now()) + interval '30 days', date_trunc('hour', now()) + interval '30 days 8 hours', 30, false),
  (current_setting('app.tenant_id')::uuid, '0f950000-0000-0000-0000-000000000002', '0f800000-0000-0000-0000-000000000003', '0f500000-0000-0000-0000-000000000003', '0f200000-0000-0000-0000-000000000001',
   date_trunc('hour', now()) + interval '30 days', date_trunc('hour', now()) + interval '30 days 8 hours', 30, false);
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  -- Ana is registered but has no first aid: a caution with a reason lets the shift go ahead
  BEGIN
    UPDATE timeleave.shift SET published = true, published_by = '0fa00000-0000-0000-0000-000000000002' WHERE shift_id = '0f950000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5a: published without first aid and without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED: learning.not_ready_for_work%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'learning.not_ready_for_work', 'shift', '0f950000-0000-0000-0000-000000000001', 'shown', 'en', '0fa00000-0000-0000-0000-000000000002',
            'First aid course booked for next week; two first aiders on the same shift');
  UPDATE timeleave.shift SET published = true, published_by = '0fa00000-0000-0000-0000-000000000002' WHERE shift_id = '0f950000-0000-0000-0000-000000000001';
  -- Cy's registration is still pending: the law's licence stops the shift, whatever is acknowledged
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'learning.not_ready_for_work', 'shift', '0f950000-0000-0000-0000-000000000002', 'shown', 'en', '0fa00000-0000-0000-0000-000000000002', 'Short staffed');
  BEGIN
    UPDATE timeleave.shift SET published = true, published_by = '0fa00000-0000-0000-0000-000000000002' WHERE shift_id = '0f950000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 5b: shift published to someone without the registration the law requires';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CREDENTIAL_REQUIRED_BY_LAW%' THEN RAISE EXCEPTION 'FAIL 5b: %', SQLERRM; END IF;
  END;
  -- Training required before the work: a new orientation for Ana stops a reassigned shift until acknowledged
  INSERT INTO talent.learning_assignment (tenant_id, person_id, employment_id, item_id, rule_id, source, event, assigned_on, blocks_work, status)
    VALUES (t, '0f600000-0000-0000-0000-000000000001', '0f700000-0000-0000-0000-000000000001', '0fb00000-0000-0000-0000-000000000002',
            '0fc00000-0000-0000-0000-000000000003', 'rule', 'location_transfer', current_date, true, 'assigned');
  IF NOT EXISTS (SELECT 1 FROM talent.work_readiness('0f800000-0000-0000-0000-000000000001', NULL, current_date + 30) w WHERE w.problem = 'training_before_work') THEN
    RAISE EXCEPTION 'FAIL 5c: training required before work not seen';
  END IF;
  RAISE NOTICE 'PASS 5a-c: a credential the organization requires needs the caution; one the law requires stops with no override; training before work counts';
END $$;

-- ---------------------------------------------------------------------------------
-- 6. Skills consent and development plans
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF talent.skills_visible('0f600000-0000-0000-0000-000000000001', now()) THEN RAISE EXCEPTION 'FAIL 6a: skills shown before the employee opted in'; END IF;
  INSERT INTO talent.skills_consent (tenant_id, consent_id, person_id, given_at)
    VALUES (t, '0f0b0000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000001', now() - interval '1 day');
  IF NOT talent.skills_visible('0f600000-0000-0000-0000-000000000001', now()) THEN RAISE EXCEPTION 'FAIL 6b: opt-in ignored'; END IF;
  UPDATE talent.skills_consent SET withdrawn_at = now() - interval '1 hour' WHERE consent_id = '0f0b0000-0000-0000-0000-000000000001';
  IF talent.skills_visible('0f600000-0000-0000-0000-000000000001', now()) THEN RAISE EXCEPTION 'FAIL 6c: withdrawal ignored'; END IF;

  INSERT INTO talent.development_plan (tenant_id, plan_id, person_id, employment_id, period, proposed_by, status)
    VALUES (t, '0f0c0000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000001', '0f700000-0000-0000-0000-000000000001', '[2027-01-01,2028-01-01)',
            '0fa00000-0000-0000-0000-000000000001', 'proposed');
  INSERT INTO talent.development_action (tenant_id, action_id, plan_id, kind, title_en, item_id, status) VALUES
    (t, '0f0c1000-0000-0000-0000-000000000001', '0f0c0000-0000-0000-0000-000000000001', 'experience', 'Lead the wound care rounds', NULL, 'planned'),
    (t, '0f0c1000-0000-0000-0000-000000000002', '0f0c0000-0000-0000-0000-000000000001', 'formal', 'Wound care update', '0fb00000-0000-0000-0000-000000000004', 'planned');
  BEGIN
    UPDATE talent.development_plan SET status = 'agreed', employee_agreed_at = now() WHERE plan_id = '0f0c0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 6d: plan agreed by the employee alone';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PLAN_NOT_AGREED%' THEN RAISE EXCEPTION 'FAIL 6d: %', SQLERRM; END IF;
  END;
  UPDATE talent.development_plan SET status = 'agreed', employee_agreed_at = now(), manager_agreed_at = now() WHERE plan_id = '0f0c0000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE talent.development_action SET target_on = '2027-06-30' WHERE action_id = '0f0c1000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 6e: agreed plan changed by nobody';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 6e: %', SQLERRM; END IF;
  END;
  UPDATE talent.development_action SET target_on = '2027-06-30', changed_by = '0fa00000-0000-0000-0000-000000000002', change_reason = 'Rounds start in June'
   WHERE action_id = '0f0c1000-0000-0000-0000-000000000001';
  IF NOT EXISTS (SELECT 1 FROM talent.development_plan_change WHERE plan_id = '0f0c0000-0000-0000-0000-000000000001' AND after ->> 'target_on' = '2027-06-30')
     OR talent.development_mix('0f0c0000-0000-0000-0000-000000000001') <> '{"experience":50,"formal":50}'::jsonb THEN
    RAISE EXCEPTION 'FAIL 6f: change not kept, or mix wrong';
  END IF;
  RAISE NOTICE 'PASS 6a-f: skills seen only after opt-in; plans agreed by both; changes kept; the 70-20-10 view';
END $$;

-- ---------------------------------------------------------------------------------
-- 7. Training requests: route with the HR amount, budget, CRA mark, repayment
-- ---------------------------------------------------------------------------------
INSERT INTO talent.training_budget (tenant_id, budget_id, org_unit_id, period, amount)
  VALUES (current_setting('app.tenant_id')::uuid, '0f0e0000-0000-0000-0000-000000000001', '0f300000-0000-0000-0000-000000000001', '[2027-01-01,2028-01-01)', 1000);
INSERT INTO talent.training_request (tenant_id, request_id, person_id, employment_id, kind, description, provider, starts_on, cost, budget_id, requested_by, status)
  VALUES (current_setting('app.tenant_id')::uuid, '0f0f0000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000001', '0f700000-0000-0000-0000-000000000001',
          'certification', 'Gerontology nursing certificate', 'College', '2027-02-01', 1200, '0f0e0000-0000-0000-0000-000000000001', '0fa00000-0000-0000-0000-000000000001', 'draft');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; route uuid; facts jsonb;
BEGIN
  BEGIN
    UPDATE talent.training_request SET status = 'submitted' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7a: submitted with no route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7a: %', SQLERRM; END IF;
  END;
  BEGIN
    PERFORM talent.training_request_facts('0f0f0000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL 7b: an HR amount CanDo chose';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 7b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'learning.request_hr_above_amount', '500', '[2000-01-01,)', gen_random_uuid());
  facts := talent.training_request_facts('0f0f0000-0000-0000-0000-000000000001');
  route := platform.route_for(t, 'training_request', facts);
  IF NOT (facts ->> 'aboveHrAmount')::boolean OR NOT (facts ->> 'overBudget')::boolean
     OR (SELECT code FROM platform.workflow_route WHERE route_id = route) <> 'training_request_hr'
     OR (SELECT code FROM platform.workflow_route WHERE route_id = platform.route_for(t, 'training_request', '{"aboveHrAmount":false}')) <> 'training_request' THEN
    RAISE EXCEPTION 'FAIL 7c: route not chosen by the organization''s HR amount';
  END IF;
  UPDATE talent.training_request SET status = 'submitted', route_id = route WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE talent.training_request SET status = 'approved' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7d: approved without its route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 7d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'training_request', '0f0f0000-0000-0000-0000-000000000001', 1, 'approved', '0fa00000-0000-0000-0000-000000000001', now());
    RAISE EXCEPTION 'FAIL 7e: the employee approved her own request';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 7e: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'training_request', '0f0f0000-0000-0000-0000-000000000001', 1, 'approved', '0fa00000-0000-0000-0000-000000000002', now(), NULL),
    (t, 'training_request', '0f0f0000-0000-0000-0000-000000000001', 2, 'approved', '0fa00000-0000-0000-0000-000000000005', now(), 'hr');
  BEGIN
    UPDATE talent.training_request SET status = 'approved' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7f: approved over the budget without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED: learning.over_budget%' THEN RAISE EXCEPTION 'FAIL 7f: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'learning.over_budget', 'training_request', '0f0f0000-0000-0000-0000-000000000001', 'shown', 'en', '0fa00000-0000-0000-0000-000000000005',
            'Required for the new dementia unit; finance moves 200 from operations');
  UPDATE talent.training_request SET status = 'approved' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
  UPDATE talent.training_request SET status = 'completed' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 7a-f: submitted with its route; the HR amount chosen at setup picks the route; no self-approval; over budget needs the caution';
END $$;

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    UPDATE talent.training_request SET status = 'reimbursed' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7g: paid before HR marked it for CRA';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED: HR marks%' THEN RAISE EXCEPTION 'FAIL 7g: %', SQLERRM; END IF;
  END;
  UPDATE talent.training_request SET primarily_for = 'employer', marked_by = '0fa00000-0000-0000-0000-000000000005' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE talent.training_request SET status = 'reimbursed' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7h: repayment decided with no rule and no setup choice';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 7h: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'learning.repayment_without_rule', '"hr_decides"', '[2000-01-01,)', gen_random_uuid());
  BEGIN
    UPDATE talent.training_request SET status = 'reimbursed' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7i: no rule and HR has not decided';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED: no repayment rule%' THEN RAISE EXCEPTION 'FAIL 7i: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.repayment_rule (tenant_id, code, kinds, cost_from, cost_to, method, months, status)
    VALUES (t, 'CERT1000', ARRAY['certification','degree_program'], 1000, NULL, 'prorated', 12, 'active');
  BEGIN
    UPDATE talent.training_request SET status = 'reimbursed' WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7j: reimbursed before the repayment agreement was signed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'REPAYMENT_AGREEMENT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7j: %', SQLERRM; END IF;
  END;
  UPDATE talent.training_request SET status = 'reimbursed', repayment_agreement_signed_at = now(), repayment_document_id = '0f0d0000-0000-0000-0000-000000000002'
   WHERE request_id = '0f0f0000-0000-0000-0000-000000000001';
  IF (SELECT repayment_method FROM talent.training_request WHERE request_id = '0f0f0000-0000-0000-0000-000000000001') <> 'prorated'
     OR talent.repayment_owed('0f0f0000-0000-0000-0000-000000000001', '2027-01-31', '2027-07-31') <> 600
     OR talent.repayment_owed('0f0f0000-0000-0000-0000-000000000001', '2027-01-31', '2028-02-01') <> 0 THEN
    RAISE EXCEPTION 'FAIL 7k: prorated repayment wrong';
  END IF;
  INSERT INTO talent.repayment_rule (tenant_id, code, kinds, cost_from, cost_to, method, months, status)
    VALUES (t, 'CERT500', ARRAY['certification'], 500, 5000, 'full', 6, 'active');
  BEGIN
    PERFORM talent.repayment_rule_for(t, 'certification', 1200);
    RAISE EXCEPTION 'FAIL 7l: two rules fit and one was picked';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'REPAYMENT_RULE_AMBIGUOUS%' THEN RAISE EXCEPTION 'FAIL 7l: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 7g-l: HR marks it for CRA; no rule follows the organization''s setup choice; agreement signed first; prorated; two rules are an error';
END $$;

-- ---------------------------------------------------------------------------------
-- 8. Grants, mentoring and sessions
-- ---------------------------------------------------------------------------------
INSERT INTO finance.calendar (tenant_id, calendar_id, code, kind, owner_type, name_en)
  VALUES (current_setting('app.tenant_id')::uuid, '0f0f1000-0000-0000-0000-000000000001', 'GRANT-YR', 'funder', 'funding_source', 'Grant year');
INSERT INTO finance.funding_source (tenant_id, funding_source_id, code, funder_name, legal_entity_id, calendar_id, valid_period, status, eligible_categories, fallback_segments)
  VALUES (current_setting('app.tenant_id')::uuid, '0f0f2000-0000-0000-0000-000000000001', 'JOB-GRANT', 'Canada-BC Employer Training Grant', '0f100000-0000-0000-0000-000000000001',
          '0f0f1000-0000-0000-0000-000000000001', '[2027-01-01,2028-01-01)', 'active', ARRAY['training'], '{"fund":"OPERATING"}');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO talent.grant_claim (tenant_id, funding_source_id, period, eligible_cost, employer_share, amount_claimed, status)
      VALUES (t, '0f0f2000-0000-0000-0000-000000000001', '[2027-01-01,2027-04-01)', 1000, 400, 800, 'draft');
    RAISE EXCEPTION 'FAIL 8a: claim above the eligible cost';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.grant_claim (tenant_id, funding_source_id, period, eligible_cost, employer_share, amount_claimed, status)
    VALUES (t, '0f0f2000-0000-0000-0000-000000000001', '[2027-01-01,2027-04-01)', 1000, 334, 666, 'draft');
  BEGIN
    INSERT INTO talent.mentoring_pair (tenant_id, mentor_person_id, mentee_person_id, purpose, period, paired_by, status)
      VALUES (t, '0f600000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000001', 'Leadership', '[2027-01-01,2027-07-01)', '0fa00000-0000-0000-0000-000000000005', 'active');
    RAISE EXCEPTION 'FAIL 8b: mentoring herself';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.mentoring_pair (tenant_id, pair_id, mentor_person_id, mentee_person_id, purpose, period, paired_by, status)
    VALUES (t, '0f0f3000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000002', '0f600000-0000-0000-0000-000000000001', 'Leadership',
            '[2027-01-01,2027-07-01)', '0fa00000-0000-0000-0000-000000000005', 'active');
  INSERT INTO talent.mentoring_session (tenant_id, pair_id, held_on, notes, mentee_feedback)
    VALUES (t, '0f0f3000-0000-0000-0000-000000000001', '2027-01-20', 'Delegation', 'Useful');
  INSERT INTO talent.learning_session (tenant_id, session_id, item_id, starts_at, ends_at, location_id, capacity)
    VALUES (t, '0f0f4000-0000-0000-0000-000000000001', '0fb00000-0000-0000-0000-000000000004', '2027-03-01 09:00-08', '2027-03-01 13:00-08', '0f200000-0000-0000-0000-000000000001', 1);
  INSERT INTO talent.session_attendee (tenant_id, session_id, person_id, status)
    VALUES (t, '0f0f4000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000001', 'registered');
  BEGIN
    INSERT INTO talent.session_attendee (tenant_id, session_id, person_id, status)
      VALUES (t, '0f0f4000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000003', 'registered');
    RAISE EXCEPTION 'FAIL 8c: registered over capacity';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SESSION_FULL%' THEN RAISE EXCEPTION 'FAIL 8c: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.session_attendee (tenant_id, session_id, person_id, status)
    VALUES (t, '0f0f4000-0000-0000-0000-000000000001', '0f600000-0000-0000-0000-000000000003', 'waitlisted');
  BEGIN
    UPDATE talent.session_attendee SET status = 'attended' WHERE session_id = '0f0f4000-0000-0000-0000-000000000001' AND person_id = '0f600000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8d: attendance recorded by nobody';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 8d: %', SQLERRM; END IF;
  END;
  UPDATE talent.session_attendee SET status = 'attended', recorded_by = '0fa00000-0000-0000-0000-000000000002'
   WHERE session_id = '0f0f4000-0000-0000-0000-000000000001' AND person_id = '0f600000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 8a-d: grant claims within the eligible cost; no self-mentoring; sessions full means waitlist; attendance recorded by someone';
END $$;

-- ---------------------------------------------------------------------------------
-- 9. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', 'f2222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM talent.learning_item) <> 0 OR (SELECT count(*) FROM talent.credential) <> 0 OR (SELECT count(*) FROM talent.training_request) <> 0
     OR (SELECT count(*) FROM talent.learning_assignment) <> 0 OR (SELECT count(*) FROM talent.development_plan) <> 0 OR (SELECT count(*) FROM talent.skills_consent) <> 0
     OR (SELECT count(*) FROM talent.mentoring_pair) <> 0 OR (SELECT count(*) FROM talent.training_rule) <> 0 THEN
    RAISE EXCEPTION 'FAIL 9: another organization''s learning data is visible';
  END IF;
  RAISE NOTICE 'PASS 9: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0015_smoke: all checks passed'
