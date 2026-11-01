-- Smoke test for schema/0017_engagement_decisions.sql (docs/31): the new settings, employers covered by a
-- freedom-of-information law, surveys (confidential by default, anonymous only for covered employers, audiences,
-- minimum groups, questions locked once open, the escalation contact and the union caution before opening),
-- submissions with no identity, comment flags, imported results, results and breakdowns suppressed below their
-- minimum, participation, action plans, recognition (private until its recipient asks, HR's route, attachment to a
-- review only by the recipient, points budgets), rewards against CRA's gift and award limits with payroll's
-- confirmation, cash awards through the route, milestones and reminders, celebrations by opt-in, announcements with
-- SMS only for urgent alerts and read reminders, ideas, the anonymous feedback box, observances, RLS and isolation.
-- Run after every migration, 0001 to 0017 (CI, after the 0016 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0017_smoke.sql
-- Every date is fixed in the test; nothing depends on today's date. It inserts test rows; run `supabase db reset`
-- afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit, benefits TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit, benefits TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ref, platform, core, payroll, timeleave, talent, recruit, comp, compliance, benefits TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('17111111-1111-1111-1111-111111111111', 'Engagement Test Society'),
  ('17222222-2222-2222-2222-222222222222', 'Other Organization')
ON CONFLICT DO NOTHING;

-- CRA's limits as the loader writes them from rules/recognition (test years, so they never clash with a real edition):
-- 2026 usable, 2024 still to verify, 2025 not loaded
INSERT INTO ref.gift_award_rule (tax_year, non_cash_annual_limit, long_service_limit, long_service_min_years, long_service_interval_years, status, cite) VALUES
  (2026, 500, 500, 5, 5, 'secondary', 'test'),
  (2024, 500, 500, 5, 5, 'verify_at_load', 'test')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', '17111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, caution, starter routes, observances, RLS
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/31%') <> 9
     OR (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/31%' AND decision_status = 'pending') <> 0 THEN
    RAISE EXCEPTION 'FAIL 1a: expected 9 settings from docs/31, none left to choose at setup';
  END IF;
  IF platform.setting_text(t, 'engagement.default_mode') <> 'confidential' OR platform.setting_number(t, 'engagement.min_group_size') <> 5
     OR (platform.setting(t, 'engagement.ai_comment_themes'))::boolean OR platform.setting_number(t, 'engagement.action_plan_days') <> 60
     OR jsonb_array_length(platform.setting(t, 'engagement.lifecycle_surveys')) <> 5
     OR platform.setting(t, 'recognition.milestone_years') ->> 0 <> '5' OR platform.setting_number(t, 'recognition.milestone_reminder_days') <> 30
     OR platform.setting(t, 'announcements.read_reminder_days') <> '[3,7]'::jsonb OR NOT (platform.setting(t, 'announcements.sms_for_urgent'))::boolean THEN
    RAISE EXCEPTION 'FAIL 1b: decided defaults not in place';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM ref.caution WHERE caution_code = 'engagement.union_consultation' AND reason_always)
     OR (SELECT count(*) FROM platform.workflow_route_step s JOIN platform.workflow_route r ON r.route_id = s.route_id
          WHERE r.tenant_id = t AND r.code = 'recognition_award') <> 2
     OR NOT EXISTS (SELECT 1 FROM platform.workflow_route WHERE tenant_id = t AND code = 'recognition_publication')
     OR (SELECT count(*) FROM ref.observance) <> 17 THEN
    RAISE EXCEPTION 'FAIL 1c: caution, starter routes or observances missing';
  END IF;
  SELECT string_agg(c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'talent' AND c.relkind = 'r'
     AND c.relname IN ('survey','survey_question','survey_escalation_contact','survey_invitation','survey_submission','comment_flag',
                       'imported_result','action_plan','action_item','points_budget','recognition','reward','celebration_consent',
                       'announcement','announcement_channel','announcement_receipt','idea','idea_vote','feedback_thread',
                       'feedback_message','wellbeing_resource','profile_extra','observance')
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1d: RLS missing on %', bad; END IF;
  RAISE NOTICE 'PASS 1a-d: settings, defaults, caution, starter routes, observances, RLS';
END $$;

-- Fixtures: a society (not covered by a freedom-of-information law) and a town (covered). Ana manages Ben and Cy at the
-- society; Dee works for the town. HR, payroll and Ana's own manager are users without a person record here
INSERT INTO core.person (tenant_id, person_id, person_type) VALUES
  (current_setting('app.tenant_id')::uuid, '17600000-0000-0000-0000-000000000001', 'employee'),
  (current_setting('app.tenant_id')::uuid, '17600000-0000-0000-0000-000000000002', 'employee'),
  (current_setting('app.tenant_id')::uuid, '17600000-0000-0000-0000-000000000003', 'employee'),
  (current_setting('app.tenant_id')::uuid, '17600000-0000-0000-0000-000000000004', 'employee');
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, '17a00000-0000-0000-0000-000000000001', 'ana', 'ana@example.test', '17600000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '17a00000-0000-0000-0000-000000000002', 'ben', 'ben@example.test', '17600000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '17a00000-0000-0000-0000-000000000003', 'cy',  'cy@example.test',  '17600000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '17a00000-0000-0000-0000-000000000004', 'dee', 'dee@example.test', '17600000-0000-0000-0000-000000000004'),
  (current_setting('app.tenant_id')::uuid, '17a00000-0000-0000-0000-000000000005', 'hr',  'hr@example.test',  NULL),
  (current_setting('app.tenant_id')::uuid, '17a00000-0000-0000-0000-000000000006', 'pay', 'pay@example.test', NULL),
  (current_setting('app.tenant_id')::uuid, '17a00000-0000-0000-0000-000000000007', 'ed',  'ed@example.test',  NULL);
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, '17100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '17100000-0000-0000-0000-000000000002');
DO $$
BEGIN
  BEGIN
    INSERT INTO core.legal_entity_version (tenant_id, legal_entity_id, valid_period, change_set_id, legal_name, business_number, regulatory_jurisdiction,
                                           fiscal_year_start_month, first_nation_government, information_access_covered, information_access_law)
      VALUES (current_setting('app.tenant_id')::uuid, '17100000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'Town of Test', '222222222',
              'provincial', 1, false, true, NULL);
    RAISE EXCEPTION 'FAIL 0: an employer covered by a freedom-of-information law with no law named';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END $$;
INSERT INTO core.legal_entity_version (tenant_id, legal_entity_id, valid_period, change_set_id, legal_name, business_number, regulatory_jurisdiction,
                                       fiscal_year_start_month, first_nation_government, information_access_covered, information_access_law) VALUES
  (current_setting('app.tenant_id')::uuid, '17100000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Test Society', '111111111', 'provincial', 4, false, false, NULL),
  (current_setting('app.tenant_id')::uuid, '17100000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'Town of Test', '222222222', 'provincial', 1, false, true,
   'BC Freedom of Information and Protection of Privacy Act');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES
  (current_setting('app.tenant_id')::uuid, '17300000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '17300000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '17300000-0000-0000-0000-000000000003');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en) VALUES
  (current_setting('app.tenant_id')::uuid, '17300000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '17100000-0000-0000-0000-000000000001', 'DEPT', 'PROG', 'Programs'),
  (current_setting('app.tenant_id')::uuid, '17300000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '17100000-0000-0000-0000-000000000001', 'DEPT', 'OUTR', 'Outreach'),
  (current_setting('app.tenant_id')::uuid, '17300000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), '17100000-0000-0000-0000-000000000002', 'DEPT', 'WORKS', 'Public works');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, '17700000-0000-0000-0000-000000000001', '17600000-0000-0000-0000-000000000001', '17100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '17700000-0000-0000-0000-000000000002', '17600000-0000-0000-0000-000000000002', '17100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '17700000-0000-0000-0000-000000000003', '17600000-0000-0000-0000-000000000003', '17100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '17700000-0000-0000-0000-000000000004', '17600000-0000-0000-0000-000000000004', '17100000-0000-0000-0000-000000000002');
INSERT INTO core.employment_version (tenant_id, employment_id, valid_period, change_set_id, original_hire_date, continuous_service_date, status) VALUES
  (current_setting('app.tenant_id')::uuid, '17700000-0000-0000-0000-000000000001', '[2016-05-01,)', gen_random_uuid(), '2016-05-01', '2016-05-01', 'active'),
  (current_setting('app.tenant_id')::uuid, '17700000-0000-0000-0000-000000000002', '[2021-11-29,)', gen_random_uuid(), '2021-11-29', '2021-11-29', 'active'),
  (current_setting('app.tenant_id')::uuid, '17700000-0000-0000-0000-000000000003', '[2024-01-08,)', gen_random_uuid(), '2024-01-08', '2024-01-08', 'active'),
  (current_setting('app.tenant_id')::uuid, '17700000-0000-0000-0000-000000000004', '[2020-01-06,)', gen_random_uuid(), '2020-01-06', '2020-01-06', 'active');
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by)
  VALUES (current_setting('app.tenant_id')::uuid, '17120000-0000-0000-0000-000000000001', 'tenant', current_setting('app.tenant_id')::uuid, 'import', 'hr', 'standard',
          'test/pulse-results-2025.csv', 'abc', 'text/csv', '17a00000-0000-0000-0000-000000000005');

-- ---------------------------------------------------------------------------------
-- 2. Surveys: mode, audience, minimum, opening, submissions, flags, imports
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; s talent.survey;
BEGIN
  -- An employer whose coverage is not recorded stops the survey (the failed block rolls the employer back too)
  BEGIN
    INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (t, '17100000-0000-0000-0000-000000000003');
    INSERT INTO core.legal_entity_version (tenant_id, legal_entity_id, valid_period, change_set_id, legal_name, business_number, regulatory_jurisdiction,
                                           fiscal_year_start_month, first_nation_government)
      VALUES (t, '17100000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'New Employer', '333333333', 'provincial', 1, false);
    INSERT INTO talent.survey (tenant_id, code, kind, name_en, source, legal_entity_id, audience, union_consultation_required, status, created_by)
      VALUES (t, 'X', 'pulse', 'Pulse', 'cando', '17100000-0000-0000-0000-000000000003', '{}', false, 'draft', '17a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 2a: a survey for an employer whose coverage is not recorded';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.survey (tenant_id, survey_id, code, kind, name_en, source, legal_entity_id, audience, union_consultation_required, status, created_by)
    VALUES (t, '17b00000-0000-0000-0000-000000000001', 'CENSUS-2026', 'census', 'Engagement census 2026', 'cando', '17100000-0000-0000-0000-000000000001',
            '{"orgUnits":["17300000-0000-0000-0000-000000000001","17300000-0000-0000-0000-000000000002"]}', true, 'draft', '17a00000-0000-0000-0000-000000000005')
    RETURNING * INTO s;
  IF s.mode <> 'confidential' THEN RAISE EXCEPTION 'FAIL 2b: the society''s survey is % (confidential expected)', s.mode; END IF;
  INSERT INTO talent.survey (tenant_id, survey_id, code, kind, name_en, source, legal_entity_id, audience, union_consultation_required, status, created_by)
    VALUES (t, '17b00000-0000-0000-0000-000000000002', 'TOWN-PULSE', 'pulse', 'Town pulse', 'cando', '17100000-0000-0000-0000-000000000002', '{}', false, 'draft', '17a00000-0000-0000-0000-000000000005')
    RETURNING * INTO s;
  IF s.mode <> 'anonymous' THEN RAISE EXCEPTION 'FAIL 2b: the town''s survey is % (anonymous expected)', s.mode; END IF;
  BEGIN
    UPDATE talent.survey SET mode = 'confidential' WHERE survey_id = '17b00000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 2c: a confidential survey for a covered employer';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SURVEY_MODE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.survey (tenant_id, code, kind, name_en, source, mode, audience, union_consultation_required, status, created_by)
      VALUES (t, 'ALL', 'census', 'Everyone', 'cando', 'confidential', '{}', false, 'draft', '17a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 2c: a confidential survey of the whole organization, which includes the town';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SURVEY_MODE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.survey (tenant_id, code, kind, name_en, source, legal_entity_id, audience, union_consultation_required, status, created_by)
      VALUES (t, 'Y', 'pulse', 'Pulse', 'cando', '17100000-0000-0000-0000-000000000001', '{"teams":["a"]}', false, 'draft', '17a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 2d: an audience scope CanDo does not know';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'AUDIENCE_SCOPE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.survey (tenant_id, code, kind, name_en, source, legal_entity_id, audience, min_group_size, union_consultation_required, status, created_by)
      VALUES (t, 'Z', 'pulse', 'Pulse', 'cando', '17100000-0000-0000-0000-000000000001', '{}', 4, false, 'draft', '17a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 2d: a survey lowering the minimum group';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SURVEY_MIN_GROUP_BELOW_ORGANIZATION%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.survey (tenant_id, code, kind, name_en, source, legal_entity_id, audience, union_consultation_required, status, created_by)
      VALUES (t, 'L', 'lifecycle', 'Lifecycle', 'cando', '17100000-0000-0000-0000-000000000001', '{}', false, 'draft', '17a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 2d: a lifecycle survey with no event';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.survey_question (tenant_id, survey_id, item_no, kind, text_en, text_fr, driver, source) VALUES
    (t, '17b00000-0000-0000-0000-000000000001', 1, 'likert_5', 'I would recommend this organization as a place to work', 'Je recommanderais cette organisation', 'engagement', 'library'),
    (t, '17b00000-0000-0000-0000-000000000001', 2, 'likert_5', 'My workload is manageable', 'Ma charge de travail est raisonnable', 'workload', 'library'),
    (t, '17b00000-0000-0000-0000-000000000001', 3, 'enps', 'How likely are you to recommend working here?', 'Quelle est la probabilité que vous recommandiez de travailler ici?', 'engagement', 'library'),
    (t, '17b00000-0000-0000-0000-000000000001', 4, 'open_text', 'What one thing would you change?', 'Quelle chose changeriez-vous?', NULL, 'organization');
  BEGIN
    INSERT INTO talent.survey_question (tenant_id, survey_id, item_no, kind, text_en, source)
      VALUES (t, '17b00000-0000-0000-0000-000000000001', 5, 'choice', 'Which site?', 'organization');
    RAISE EXCEPTION 'FAIL 2e: a choice question with no choices';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- Opening: dates, the escalation contact for open comments, then the union caution
  BEGIN
    UPDATE talent.survey SET status = 'open' WHERE survey_id = '17b00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2f: opened without dates';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2f: %', SQLERRM; END IF;
  END;
  UPDATE talent.survey SET opens_on = '2026-10-05', closes_on = '2026-10-23' WHERE survey_id = '17b00000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE talent.survey SET status = 'open' WHERE survey_id = '17b00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2f: open comments with no one named to receive flagged comments';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ESCALATION_CONTACT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2f: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.survey_escalation_contact (tenant_id, contact_id, user_id, legal_entity_id, active)
    VALUES (t, '17b10000-0000-0000-0000-000000000001', '17a00000-0000-0000-0000-000000000005', NULL, true);
  BEGIN
    UPDATE talent.survey SET status = 'open' WHERE survey_id = '17b00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2f: a survey of a unionized group opened without the union caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED: engagement.union_consultation%' THEN RAISE EXCEPTION 'FAIL 2f: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'engagement.union_consultation', 'survey', '17b00000-0000-0000-0000-000000000001', 'shown', 'en', '17a00000-0000-0000-0000-000000000005',
            'Questions shared with the local''s president on 22 September; no changes asked');
  UPDATE talent.survey SET status = 'open' WHERE survey_id = '17b00000-0000-0000-0000-000000000001';
  BEGIN
    INSERT INTO talent.survey_question (tenant_id, survey_id, item_no, kind, text_en, source)
      VALUES (t, '17b00000-0000-0000-0000-000000000001', 6, 'likert_5', 'Late question', 'organization');
    RAISE EXCEPTION 'FAIL 2g: a question added after opening';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SURVEY_LOCKED%' THEN RAISE EXCEPTION 'FAIL 2g: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE talent.survey SET mode = 'anonymous' WHERE survey_id = '17b00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2g: the mode changed after opening';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SURVEY_LOCKED%' THEN RAISE EXCEPTION 'FAIL 2g: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 2a-g: coverage recorded; confidential by default, anonymous only for the town; audience and minimum; questions; opening checks; locked once open';
END $$;

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; sub uuid;
BEGIN
  BEGIN
    INSERT INTO talent.survey_submission (tenant_id, survey_id, submitted_on, attributes, answers)
      VALUES (t, '17b00000-0000-0000-0000-000000000001', '2026-10-06', '{"orgUnit":"17300000-0000-0000-0000-000000000001","employmentId":"x"}', '{"1":4}');
    RAISE EXCEPTION 'FAIL 2h: an answer kept with a person link';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SUBMISSION_ATTRIBUTE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 2h: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.survey_submission (tenant_id, survey_id, submitted_on, attributes, answers)
      VALUES (t, '17b00000-0000-0000-0000-000000000001', '2026-10-06', '{"orgUnit":"17300000-0000-0000-0000-000000000001"}', '{"9":4}');
    RAISE EXCEPTION 'FAIL 2h: an answer to a question the survey does not have';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ANSWER_UNKNOWN_ITEM%' THEN RAISE EXCEPTION 'FAIL 2h: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.survey_submission (tenant_id, survey_id, submitted_on, attributes, answers)
      VALUES (t, '17b00000-0000-0000-0000-000000000001', '2026-10-30', '{"orgUnit":"17300000-0000-0000-0000-000000000001"}', '{"1":4}');
    RAISE EXCEPTION 'FAIL 2h: an answer after the survey closed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SURVEY_NOT_OPEN%' THEN RAISE EXCEPTION 'FAIL 2h: %', SQLERRM; END IF;
  END;
  -- Programs: 6 answers (only 4 answer the workload item); Outreach: 3 answers
  INSERT INTO talent.survey_submission (tenant_id, submission_id, survey_id, submitted_on, attributes, answers) VALUES
    (t, '17b20000-0000-0000-0000-000000000001', '17b00000-0000-0000-0000-000000000001', '2026-10-06', '{"orgUnit":"17300000-0000-0000-0000-000000000001","tenureBand":"0-2","selfId":"group_a"}', '{"1":5,"2":4,"3":9,"4":"More training on the new system"}'),
    (t, '17b20000-0000-0000-0000-000000000002', '17b00000-0000-0000-0000-000000000001', '2026-10-06', '{"orgUnit":"17300000-0000-0000-0000-000000000001","tenureBand":"0-2","selfId":"group_a"}', '{"1":4,"2":2,"3":7}'),
    (t, '17b20000-0000-0000-0000-000000000003', '17b00000-0000-0000-0000-000000000001', '2026-10-07', '{"orgUnit":"17300000-0000-0000-0000-000000000001","tenureBand":"0-2","selfId":"group_a"}', '{"1":4,"2":3,"3":8}'),
    (t, '17b20000-0000-0000-0000-000000000004', '17b00000-0000-0000-0000-000000000001', '2026-10-08', '{"orgUnit":"17300000-0000-0000-0000-000000000001","tenureBand":"0-2","selfId":"group_a"}', '{"1":3,"2":3,"3":6}'),
    (t, '17b20000-0000-0000-0000-000000000005', '17b00000-0000-0000-0000-000000000001', '2026-10-09', '{"orgUnit":"17300000-0000-0000-0000-000000000001","tenureBand":"0-2","selfId":"group_a"}', '{"1":4,"3":8}'),
    (t, '17b20000-0000-0000-0000-000000000006', '17b00000-0000-0000-0000-000000000001', '2026-10-09', '{"orgUnit":"17300000-0000-0000-0000-000000000001","tenureBand":"3-5","selfId":"group_a"}', '{"1":4,"3":10,"4":"My supervisor keeps threatening people"}'),
    (t, '17b20000-0000-0000-0000-000000000007', '17b00000-0000-0000-0000-000000000001', '2026-10-12', '{"orgUnit":"17300000-0000-0000-0000-000000000002","tenureBand":"3-5"}', '{"1":2,"2":2,"3":3}'),
    (t, '17b20000-0000-0000-0000-000000000008', '17b00000-0000-0000-0000-000000000001', '2026-10-12', '{"orgUnit":"17300000-0000-0000-0000-000000000002","tenureBand":"3-5"}', '{"1":3,"2":2,"3":5}'),
    (t, '17b20000-0000-0000-0000-000000000009', '17b00000-0000-0000-0000-000000000001', '2026-10-13', '{"orgUnit":"17300000-0000-0000-0000-000000000002","tenureBand":"3-5"}', '{"1":3,"2":3,"3":6}');
  BEGIN
    UPDATE talent.survey_submission SET answers = '{"1":1}' WHERE submission_id = '17b20000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2i: an answer changed after it was given';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SURVEY_LOCKED%' THEN RAISE EXCEPTION 'FAIL 2i: %', SQLERRM; END IF;
  END;
  -- The town's anonymous pulse keeps only the unit
  INSERT INTO talent.survey_question (tenant_id, survey_id, item_no, kind, text_en, source)
    VALUES (t, '17b00000-0000-0000-0000-000000000002', 1, 'likert_5', 'I have the tools I need', 'library');
  UPDATE talent.survey SET opens_on = '2026-10-05', closes_on = '2026-10-23', status = 'open' WHERE survey_id = '17b00000-0000-0000-0000-000000000002';
  BEGIN
    INSERT INTO talent.survey_submission (tenant_id, survey_id, submitted_on, attributes, answers)
      VALUES (t, '17b00000-0000-0000-0000-000000000002', '2026-10-06', '{"orgUnit":"17300000-0000-0000-0000-000000000003","tenureBand":"0-2"}', '{}');
    RAISE EXCEPTION 'FAIL 2j: an anonymous answer kept with its tenure';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SUBMISSION_ATTRIBUTE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 2j: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.survey_submission (tenant_id, survey_id, submitted_on, attributes, answers)
    VALUES (t, '17b00000-0000-0000-0000-000000000002', '2026-10-06', '{"orgUnit":"17300000-0000-0000-0000-000000000003"}', '{}');
  -- The flagged comment goes to the named contact, with no identity; handling it states what was done
  INSERT INTO talent.comment_flag (tenant_id, flag_id, submission_id, item_no, category, comment_text, contact_id, sent_at, status)
    VALUES (t, '17b30000-0000-0000-0000-000000000001', '17b20000-0000-0000-0000-000000000006', 4, 'harassment', 'My supervisor keeps threatening people',
            '17b10000-0000-0000-0000-000000000001', now(), 'open');
  BEGIN
    UPDATE talent.comment_flag SET status = 'handled' WHERE flag_id = '17b30000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2k: a flag handled with no note';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  UPDATE talent.comment_flag SET status = 'handled', handled_note = 'Respectful workplace review opened for Programs; speak-up channel reminded to all staff'
   WHERE flag_id = '17b30000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 2h-k: no person link, known items only, only while open, never changed; anonymous keeps the unit; flags without identity';
END $$;

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  INSERT INTO talent.survey (tenant_id, survey_id, code, kind, name_en, source, source_document_id, legal_entity_id, audience, union_consultation_required, status, created_by)
    VALUES (t, '17b00000-0000-0000-0000-000000000003', 'PULSE-2025-IMPORT', 'pulse', 'Pulse 2025 (previous tool)', 'imported_results', '17120000-0000-0000-0000-000000000001',
            '17100000-0000-0000-0000-000000000001', '{}', false, 'closed', '17a00000-0000-0000-0000-000000000005');
  BEGIN
    UPDATE talent.survey SET status = 'open', opens_on = '2026-11-01', closes_on = '2026-11-15' WHERE survey_id = '17b00000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 2l: imported results opened as a survey';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2l: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.imported_result (tenant_id, survey_id, group_key, item_code, respondents, average)
      VALUES (t, '17b00000-0000-0000-0000-000000000003', '{"orgUnit":"17300000-0000-0000-0000-000000000002"}', 'Q1', 4, 3.5);
    RAISE EXCEPTION 'FAIL 2l: an imported group of 4';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'IMPORT_BELOW_MIN_GROUP%' THEN RAISE EXCEPTION 'FAIL 2l: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.imported_result (tenant_id, survey_id, group_key, item_code, respondents, average)
      VALUES (t, '17b00000-0000-0000-0000-000000000003', '{"selfId":"group_a"}', 'Q1', 8, 3.9);
    RAISE EXCEPTION 'FAIL 2l: an imported self-identified group of 8';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'IMPORT_BELOW_MIN_GROUP%' THEN RAISE EXCEPTION 'FAIL 2l: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.imported_result (tenant_id, survey_id, group_key, item_code, respondents, average)
      VALUES (t, '17b00000-0000-0000-0000-000000000003', '{"email":"ana@example.test"}', 'Q1', 6, 4);
    RAISE EXCEPTION 'FAIL 2l: an imported row naming a person';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SUBMISSION_ATTRIBUTE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 2l: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.imported_result (tenant_id, survey_id, group_key, item_code, respondents, average)
      VALUES (t, '17b00000-0000-0000-0000-000000000001', '{"orgUnit":"17300000-0000-0000-0000-000000000001"}', 'Q1', 6, 4);
    RAISE EXCEPTION 'FAIL 2l: results imported into CanDo''s own survey';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2l: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.imported_result (tenant_id, survey_id, group_key, item_code, respondents, average) VALUES
    (t, '17b00000-0000-0000-0000-000000000003', '{"orgUnit":"17300000-0000-0000-0000-000000000001"}', 'Q1', 6, 3.8),
    (t, '17b00000-0000-0000-0000-000000000003', '{"selfId":"group_a"}', 'Q1', 12, 3.6);
  RAISE NOTICE 'PASS 2l: imported results checked against the same minimum groups, never a person';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Results, breakdowns, participation, action plans
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; s uuid := '17b00000-0000-0000-0000-000000000001'; r record; n int;
BEGIN
  SELECT * INTO r FROM talent.survey_scores(s, ARRAY['17300000-0000-0000-0000-000000000001']::uuid[], NULL) WHERE item_no = 1;
  IF r.respondents <> 6 OR r.average <> 4.00 THEN RAISE EXCEPTION 'FAIL 3a: Programs item 1: % answers, average %', r.respondents, r.average; END IF;
  IF EXISTS (SELECT 1 FROM talent.survey_scores(s, ARRAY['17300000-0000-0000-0000-000000000001']::uuid[], NULL) WHERE item_no = 2) THEN
    RAISE EXCEPTION 'FAIL 3a: the workload item shown with 4 answers';
  END IF;
  IF EXISTS (SELECT 1 FROM talent.survey_scores(s, ARRAY['17300000-0000-0000-0000-000000000002']::uuid[], NULL)) THEN
    RAISE EXCEPTION 'FAIL 3b: Outreach''s 3 answers shown';
  END IF;
  SELECT respondents INTO n FROM talent.survey_scores(s, ARRAY['17300000-0000-0000-0000-000000000001','17300000-0000-0000-0000-000000000002']::uuid[], NULL) WHERE item_no = 1;
  IF n <> 9 THEN RAISE EXCEPTION 'FAIL 3b: the roll-up counts % (9 expected, Outreach included)', n; END IF;
  IF (SELECT count(DISTINCT grp) FROM talent.survey_breakdown(s, 'tenureBand', NULL)) <> 1
     OR NOT EXISTS (SELECT 1 FROM talent.survey_breakdown(s, 'tenureBand', NULL) WHERE grp = '0-2' AND item_no = 1 AND respondents = 5) THEN
    RAISE EXCEPTION 'FAIL 3c: tenure groups not shown from 5 only';
  END IF;
  IF EXISTS (SELECT 1 FROM talent.survey_breakdown(s, 'selfId', NULL)) THEN
    RAISE EXCEPTION 'FAIL 3c: a self-identified group of 6 shown';
  END IF;
  -- Participation counts by unit, from 5 invited
  INSERT INTO talent.survey_invitation (tenant_id, survey_id, employment_id, org_unit_id, channel, sent_on, responded)
    SELECT t, s, e, '17300000-0000-0000-0000-000000000002', 'email', '2026-10-05', false
      FROM unnest(ARRAY['17700000-0000-0000-0000-000000000002','17700000-0000-0000-0000-000000000003']::uuid[]) e;
  IF EXISTS (SELECT 1 FROM talent.survey_participation(s, ARRAY['17300000-0000-0000-0000-000000000002']::uuid[])) THEN
    RAISE EXCEPTION 'FAIL 3d: participation shown for 2 invited';
  END IF;
  -- Action plans: due 60 days after the survey closes; agreed only with an action
  INSERT INTO talent.action_plan (tenant_id, plan_id, survey_id, org_unit_id, owner_user, status)
    VALUES (t, '17b40000-0000-0000-0000-000000000001', s, '17300000-0000-0000-0000-000000000001', '17a00000-0000-0000-0000-000000000001', 'open');
  IF (SELECT due_on FROM talent.action_plan WHERE plan_id = '17b40000-0000-0000-0000-000000000001') <> '2026-12-22' THEN
    RAISE EXCEPTION 'FAIL 3e: plan due % (22 December expected)', (SELECT due_on FROM talent.action_plan WHERE plan_id = '17b40000-0000-0000-0000-000000000001');
  END IF;
  BEGIN
    UPDATE talent.action_plan SET status = 'agreed' WHERE plan_id = '17b40000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 3e: a plan agreed with no action';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 3e: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.action_item (tenant_id, plan_id, description, linked_items, owner_user, due_on, status, shared_with_team)
    VALUES (t, '17b40000-0000-0000-0000-000000000001', 'Two training sessions on the new case system', ARRAY[2], '17a00000-0000-0000-0000-000000000001', '2027-01-31', 'planned', true);
  IF NOT EXISTS (SELECT 1 FROM talent.action_plans_overdue(t, '2026-12-23')) OR EXISTS (SELECT 1 FROM talent.action_plans_overdue(t, '2026-12-22')) THEN
    RAISE EXCEPTION 'FAIL 3f: an open plan past its date not listed for a reminder';
  END IF;
  UPDATE talent.action_plan SET status = 'agreed' WHERE plan_id = '17b40000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 3a-f: scores from 5 answers, items from 5, roll-ups, breakdowns from 5 and self-identified groups from 10, participation from 5, action plans';
END $$;

-- ---------------------------------------------------------------------------------
-- 4. Recognition: private until its recipient asks; HR's route; reviews; points
-- ---------------------------------------------------------------------------------
INSERT INTO core.list_value (tenant_id, list_code, code, category, rank, name_en)
  VALUES (current_setting('app.tenant_id')::uuid, 'recognition_value', 'courage', 'value', 1, 'Courage');

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; rid uuid := '17c00000-0000-0000-0000-000000000001';
BEGIN
  BEGIN
    INSERT INTO talent.recognition (tenant_id, batch_id, giver_user, recipient_employment_id, value_code, message, given_on, visibility)
      VALUES (t, gen_random_uuid(), '17a00000-0000-0000-0000-000000000002', '17700000-0000-0000-0000-000000000002', 'courage', 'Me!', '2026-10-20', 'private');
    RAISE EXCEPTION 'FAIL 4a: someone recognized themself';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_RECOGNITION%' THEN RAISE EXCEPTION 'FAIL 4a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.recognition (tenant_id, batch_id, giver_user, recipient_employment_id, value_code, message, given_on, visibility)
      VALUES (t, gen_random_uuid(), '17a00000-0000-0000-0000-000000000001', '17700000-0000-0000-0000-000000000002', 'courage', 'Well done', '2026-10-20', 'public');
    RAISE EXCEPTION 'FAIL 4a: a recognition posted publicly by its sender';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RECIPIENT_CONSENT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.recognition (tenant_id, batch_id, giver_user, recipient_employment_id, value_code, message, given_on, visibility)
      VALUES (t, gen_random_uuid(), '17a00000-0000-0000-0000-000000000001', '17700000-0000-0000-0000-000000000002', 'speed', 'Well done', '2026-10-20', 'private');
    RAISE EXCEPTION 'FAIL 4a: a value the organization does not have';
  EXCEPTION WHEN foreign_key_violation THEN
    IF SQLERRM NOT LIKE 'LIST_VALUE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 4a: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.recognition (tenant_id, recognition_id, batch_id, giver_user, recipient_employment_id, value_code, message, given_on, visibility)
    VALUES (t, rid, gen_random_uuid(), '17a00000-0000-0000-0000-000000000001', '17700000-0000-0000-0000-000000000002', 'courage',
            'Ben calmly handled the flood at the drop-in centre and kept everyone safe', '2026-10-20', 'private');
  BEGIN
    UPDATE talent.recognition SET visibility = 'public_requested', public_requested_by = '17a00000-0000-0000-0000-000000000001',
                                  route_id = platform.route_for(t, 'recognition_publication', '{}') WHERE recognition_id = rid;
    RAISE EXCEPTION 'FAIL 4b: the sender made it public';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RECIPIENT_CONSENT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4b: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE talent.recognition SET visibility = 'public_requested', public_requested_by = '17a00000-0000-0000-0000-000000000002' WHERE recognition_id = rid;
    RAISE EXCEPTION 'FAIL 4b: asked to go public with no route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4b: %', SQLERRM; END IF;
  END;
  UPDATE talent.recognition SET visibility = 'public_requested', public_requested_by = '17a00000-0000-0000-0000-000000000002',
                                route_id = platform.route_for(t, 'recognition_publication', '{}') WHERE recognition_id = rid;
  BEGIN
    UPDATE talent.recognition SET visibility = 'public' WHERE recognition_id = rid;
    RAISE EXCEPTION 'FAIL 4c: public before HR approved';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 4c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'recognition_publication', rid, 1, 'approved', '17a00000-0000-0000-0000-000000000002', now());
    RAISE EXCEPTION 'FAIL 4c: the recipient approved his own';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 4c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'recognition_publication', rid, 1, 'approved', '17a00000-0000-0000-0000-000000000001', now());
    RAISE EXCEPTION 'FAIL 4c: the sender approved it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 4c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'recognition_publication', rid, 1, 'approved', '17a00000-0000-0000-0000-000000000005', now());
  UPDATE talent.recognition SET visibility = 'public' WHERE recognition_id = rid;
  -- Only the recipient attaches it to his own review
  BEGIN
    UPDATE talent.recognition SET attached_review_id = gen_random_uuid(), attached_by = '17a00000-0000-0000-0000-000000000001' WHERE recognition_id = rid;
    RAISE EXCEPTION 'FAIL 4d: the manager attached it to a review';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RECIPIENT_CONSENT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4d: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE talent.recognition SET attached_review_id = gen_random_uuid(), attached_by = '17a00000-0000-0000-0000-000000000002' WHERE recognition_id = rid;
    RAISE EXCEPTION 'FAIL 4d: attached to a review that is not his';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4d: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE talent.recognition SET visibility = 'removed', removed_by = '17a00000-0000-0000-0000-000000000005' WHERE recognition_id = rid;
    RAISE EXCEPTION 'FAIL 4e: removed with no reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4e: %', SQLERRM; END IF;
  END;
  -- Points come from the giver's budget
  BEGIN
    INSERT INTO talent.recognition (tenant_id, batch_id, giver_user, recipient_employment_id, value_code, message, points, given_on, visibility)
      VALUES (t, gen_random_uuid(), '17a00000-0000-0000-0000-000000000001', '17700000-0000-0000-0000-000000000003', 'courage', 'Thanks', 50, '2026-10-21', 'private');
    RAISE EXCEPTION 'FAIL 4f: points given with no budget';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'POINTS_BUDGET_EXCEEDED%' THEN RAISE EXCEPTION 'FAIL 4f: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.points_budget (tenant_id, holder_user, period, points) VALUES (t, '17a00000-0000-0000-0000-000000000001', '[2026-01-01,2027-01-01)', 100);
  INSERT INTO talent.recognition (tenant_id, batch_id, giver_user, recipient_employment_id, value_code, message, points, given_on, visibility)
    VALUES (t, gen_random_uuid(), '17a00000-0000-0000-0000-000000000001', '17700000-0000-0000-0000-000000000003', 'courage', 'Thanks for covering the late shift', 60, '2026-10-21', 'private');
  BEGIN
    INSERT INTO talent.recognition (tenant_id, batch_id, giver_user, recipient_employment_id, value_code, message, points, given_on, visibility)
      VALUES (t, gen_random_uuid(), '17a00000-0000-0000-0000-000000000001', '17700000-0000-0000-0000-000000000002', 'courage', 'Again', 50, '2026-10-22', 'private');
    RAISE EXCEPTION 'FAIL 4f: 110 points from a budget of 100';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'POINTS_BUDGET_EXCEEDED: 40%' THEN RAISE EXCEPTION 'FAIL 4f: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 4a-f: no self-recognition; private until the recipient asks; HR approves through the route; reviews only by the recipient; removal with a reason; points budgets';
END $$;

-- ---------------------------------------------------------------------------------
-- 5. Rewards and CRA's limits; cash awards through the route; payroll confirms
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; w talent.reward;
BEGIN
  BEGIN
    INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
      VALUES (t, '17700000-0000-0000-0000-000000000003', 'non_cash', 'special_occasion', 'Holiday hamper', 80, '2025-12-15', '17a00000-0000-0000-0000-000000000005', 'given');
    RAISE EXCEPTION 'FAIL 5a: a gift recorded for a year whose limits are not loaded';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'GIFT_RULE_MISSING%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
      VALUES (t, '17700000-0000-0000-0000-000000000003', 'non_cash', 'special_occasion', 'Holiday hamper', 80, '2024-12-15', '17a00000-0000-0000-0000-000000000005', 'given');
    RAISE EXCEPTION 'FAIL 5a: limits still to verify used';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RULE_NOT_VERIFIED%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  -- Cy: $300, then $300 more (the second is $100 over the $500), then a qualifying gift card (all taxable), then one
  -- that can be cashed (taxable in full)
  INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
    VALUES (t, '17700000-0000-0000-0000-000000000003', 'non_cash', 'recognition', 'Jacket with the society''s logo', 300, '2026-03-01', '17a00000-0000-0000-0000-000000000005', 'given')
    RETURNING * INTO w;
  IF w.cra_bucket <> 'general' OR w.taxable_amount <> 0 OR w.payroll_status <> 'not_taxable' THEN RAISE EXCEPTION 'FAIL 5b: first gift %, %', w.cra_bucket, w.taxable_amount; END IF;
  INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
    VALUES (t, '17700000-0000-0000-0000-000000000003', 'non_cash', 'special_occasion', 'Wedding gift', 300, '2026-06-10', '17a00000-0000-0000-0000-000000000005', 'given')
    RETURNING * INTO w;
  IF w.taxable_amount <> 100 OR w.payroll_status <> 'to_confirm' THEN RAISE EXCEPTION 'FAIL 5b: second gift taxable % (100 expected)', w.taxable_amount; END IF;
  BEGIN
    INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
      VALUES (t, '17700000-0000-0000-0000-000000000003', 'gift_card', 'special_occasion', 'Gift card', 50, '2026-12-15', '17a00000-0000-0000-0000-000000000005', 'given');
    RAISE EXCEPTION 'FAIL 5c: a gift card with no record of its terms';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, card_retailers, card_prepaid, card_no_cash, requested_by, status)
    VALUES (t, '17700000-0000-0000-0000-000000000003', 'gift_card', 'special_occasion', 'Bookstore gift card', 50, '2026-12-15', 'One bookstore chain', true, true,
            '17a00000-0000-0000-0000-000000000005', 'given')
    RETURNING * INTO w;
  IF w.cra_bucket <> 'general' OR w.taxable_amount <> 50 THEN RAISE EXCEPTION 'FAIL 5c: qualifying card %, taxable %', w.cra_bucket, w.taxable_amount; END IF;
  INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, card_retailers, card_prepaid, card_no_cash, requested_by, status)
    VALUES (t, '17700000-0000-0000-0000-000000000004', 'gift_card', 'special_occasion', 'Prepaid card usable anywhere', 50, '2026-12-15', 'Any store', true, false,
            '17a00000-0000-0000-0000-000000000005', 'given')
    RETURNING * INTO w;
  IF w.cra_bucket <> 'taxable_in_full' OR w.taxable_amount <> 50 THEN RAISE EXCEPTION 'FAIL 5c: a cashable card %', w.cra_bucket; END IF;
  -- Ana: 10 years of service, $600 long-service award ($100 taxable); another within five years falls to the general limit
  INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
    VALUES (t, '17700000-0000-0000-0000-000000000001', 'non_cash', 'long_service', 'Ten-year watch', 600, '2026-05-15', '17a00000-0000-0000-0000-000000000005', 'given')
    RETURNING * INTO w;
  IF w.cra_bucket <> 'long_service' OR w.taxable_amount <> 100 THEN RAISE EXCEPTION 'FAIL 5d: long-service %, taxable %', w.cra_bucket, w.taxable_amount; END IF;
  INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
    VALUES (t, '17700000-0000-0000-0000-000000000001', 'non_cash', 'long_service', 'Another pin', 200, '2026-09-01', '17a00000-0000-0000-0000-000000000005', 'given')
    RETURNING * INTO w;
  IF w.cra_bucket <> 'general' OR w.taxable_amount <> 0 THEN RAISE EXCEPTION 'FAIL 5d: second long-service within five years %, %', w.cra_bucket, w.taxable_amount; END IF;
  INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
    VALUES (t, '17700000-0000-0000-0000-000000000003', 'non_cash', 'long_service', 'Two-year pin', 20, '2026-01-10', '17a00000-0000-0000-0000-000000000005', 'given')
    RETURNING * INTO w;
  IF w.cra_bucket <> 'general' THEN RAISE EXCEPTION 'FAIL 5d: a long-service award at two years counted as long service'; END IF;
  INSERT INTO talent.reward (tenant_id, employment_id, kind, occasion, description, value, given_on, requested_by, status)
    VALUES (t, '17700000-0000-0000-0000-000000000004', 'non_cash', 'performance', 'Tablet for meeting targets', 300, '2026-07-01', '17a00000-0000-0000-0000-000000000005', 'given')
    RETURNING * INTO w;
  IF w.cra_bucket <> 'taxable_in_full' OR w.taxable_amount <> 300 THEN RAISE EXCEPTION 'FAIL 5e: a performance reward not taxable in full'; END IF;
  RAISE NOTICE 'PASS 5a-e: limits loaded and verified; $500 a year; qualifying gift cards; cashable cards and performance rewards taxable; long service every five years';
END $$;

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; wid uuid := '17d00000-0000-0000-0000-000000000001'; w talent.reward;
BEGIN
  INSERT INTO talent.reward (tenant_id, reward_id, employment_id, kind, occasion, description, value, given_on, requested_by, route_id, status)
    VALUES (t, wid, '17700000-0000-0000-0000-000000000002', 'cash', 'recognition', 'Spot award for the flood response', 250, '2026-10-30',
            '17a00000-0000-0000-0000-000000000001', platform.route_for(t, 'recognition_award', '{}'), 'proposed');
  BEGIN
    UPDATE talent.reward SET status = 'approved' WHERE reward_id = wid;
    RAISE EXCEPTION 'FAIL 5f: a cash award approved without its route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 5f: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'recognition_award', wid, 1, 'approved', '17a00000-0000-0000-0000-000000000001', now());
    RAISE EXCEPTION 'FAIL 5f: the proposer approved her own award';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 5f: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'recognition_award', wid, 2, 'approved', '17a00000-0000-0000-0000-000000000002', now());
    RAISE EXCEPTION 'FAIL 5f: the recipient approved his own award';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 5f: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at) VALUES
    (t, 'recognition_award', wid, 1, 'approved', '17a00000-0000-0000-0000-000000000007', now()),
    (t, 'recognition_award', wid, 2, 'approved', '17a00000-0000-0000-0000-000000000005', now());
  UPDATE talent.reward SET status = 'approved' WHERE reward_id = wid;
  UPDATE talent.reward SET status = 'given' WHERE reward_id = wid RETURNING * INTO w;
  IF w.cra_bucket <> 'taxable_in_full' OR w.taxable_amount <> 250 OR w.payroll_status <> 'to_confirm' THEN
    RAISE EXCEPTION 'FAIL 5g: cash award %, %, %', w.cra_bucket, w.taxable_amount, w.payroll_status;
  END IF;
  BEGIN
    UPDATE talent.reward SET payroll_status = 'confirmed', payroll_confirmed_by = '17a00000-0000-0000-0000-000000000001' WHERE reward_id = wid;
    RAISE EXCEPTION 'FAIL 5g: the proposer confirmed it for payroll';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 5g: %', SQLERRM; END IF;
  END;
  UPDATE talent.reward SET payroll_status = 'confirmed', payroll_confirmed_by = '17a00000-0000-0000-0000-000000000006' WHERE reward_id = wid;
  IF (SELECT taxable FROM talent.cra_award_year('17700000-0000-0000-0000-000000000003', 2026) WHERE cra_bucket = 'general') <> 170 THEN
    RAISE EXCEPTION 'FAIL 5h: Cy''s taxable gifts for 2026 not 170 ($100 + $50 + the $20 pin once the $500 is used)';
  END IF;
  RAISE NOTICE 'PASS 5f-h: cash awards through the route with no self-approval; taxable in full; payroll confirms; yearly totals';
END $$;

-- ---------------------------------------------------------------------------------
-- 6. Milestones and celebrations
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r record;
BEGIN
  SELECT * INTO r FROM talent.milestones_due(t, '[2026-11-01,2026-12-01)');
  IF r.employment_id IS DISTINCT FROM '17700000-0000-0000-0000-000000000002'::uuid OR r.years <> 5 OR r.milestone_on <> '2026-11-29'
     OR (SELECT count(*) FROM talent.milestones_due(t, '[2026-11-01,2026-12-01)')) <> 1 THEN
    RAISE EXCEPTION 'FAIL 6a: Ben''s 5 years on 29 November not found alone';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM talent.milestone_reminders(t, '2026-10-30') WHERE employment_id = '17700000-0000-0000-0000-000000000002')
     OR EXISTS (SELECT 1 FROM talent.milestone_reminders(t, '2026-10-29')) THEN
    RAISE EXCEPTION 'FAIL 6b: the manager not reminded 30 days before';
  END IF;
  BEGIN
    INSERT INTO talent.celebration_consent (tenant_id, person_id, kind, given_at) VALUES (t, '17600000-0000-0000-0000-000000000003', 'birthday', now());
    RAISE EXCEPTION 'FAIL 6c: a birthday opt-in with no day';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO talent.celebration_consent (tenant_id, person_id, kind, month_day, given_at) VALUES (t, '17600000-0000-0000-0000-000000000003', 'birthday', '13-01', now());
    RAISE EXCEPTION 'FAIL 6c: month 13';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.celebration_consent (tenant_id, person_id, kind, month_day, given_at) VALUES (t, '17600000-0000-0000-0000-000000000003', 'birthday', '07-14', now());
  RAISE NOTICE 'PASS 6a-c: milestones every 5 years from the service date; manager reminded 30 days before; birthdays only by opt-in';
END $$;

-- ---------------------------------------------------------------------------------
-- 7. Announcements, ideas and the anonymous feedback box
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; a uuid := '17e00000-0000-0000-0000-000000000001'; u uuid := '17e00000-0000-0000-0000-000000000002';
BEGIN
  BEGIN
    INSERT INTO talent.announcement (tenant_id, title_en, body_en, audience, important, urgent, publish_at, created_by, status)
      VALUES (t, 'Hello', 'Body', '{"teams":["x"]}', false, false, '2026-10-20 09:00-07', '17a00000-0000-0000-0000-000000000005', 'draft');
    RAISE EXCEPTION 'FAIL 7a: an audience scope CanDo does not know';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'AUDIENCE_SCOPE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 7a: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.announcement (tenant_id, announcement_id, title_en, title_fr, body_en, body_fr, audience, important, urgent, publish_at, legal_entity_id, created_by, status)
    VALUES (t, a, 'New respectful workplace policy', 'Nouvelle politique sur le milieu de travail respectueux', 'Please read the new policy.', 'Veuillez lire la nouvelle politique.',
            '{"legalEntities":["17100000-0000-0000-0000-000000000001"]}', true, false, '2026-10-20 09:00-07', '17100000-0000-0000-0000-000000000001',
            '17a00000-0000-0000-0000-000000000005', 'published');
  INSERT INTO talent.announcement_channel (tenant_id, announcement_id, channel) VALUES (t, a, 'app'), (t, a, 'email'), (t, a, 'teams');
  BEGIN
    INSERT INTO talent.announcement_channel (tenant_id, announcement_id, channel) VALUES (t, a, 'sms');
    RAISE EXCEPTION 'FAIL 7b: a policy notice sent by SMS';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SMS_URGENT_ONLY%' THEN RAISE EXCEPTION 'FAIL 7b: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.announcement (tenant_id, announcement_id, title_en, body_en, audience, important, urgent, publish_at, legal_entity_id, created_by, status)
    VALUES (t, u, 'Drop-in centre closed today: flooding', 'Do not come in; your manager will call you.', '{"locations":["any"]}', true, true,
            '2026-10-21 06:30-07', '17100000-0000-0000-0000-000000000001', '17a00000-0000-0000-0000-000000000005', 'published');
  INSERT INTO talent.announcement_channel (tenant_id, announcement_id, channel) VALUES (t, u, 'push'), (t, u, 'sms');
  BEGIN
    UPDATE talent.announcement SET urgent = false WHERE announcement_id = u;
    RAISE EXCEPTION 'FAIL 7b: an SMS alert turned into an ordinary notice';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SMS_URGENT_ONLY%' THEN RAISE EXCEPTION 'FAIL 7b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
      VALUES (t, 'announcements.sms_for_urgent', 'false', '[2000-01-01,)', gen_random_uuid());
    INSERT INTO talent.announcement_channel (tenant_id, announcement_id, channel) VALUES (t, u, 'email');
    UPDATE talent.announcement_channel SET channel = 'sms' WHERE announcement_id = u AND channel = 'email';
    RAISE EXCEPTION 'FAIL 7c: SMS sent after the organization switched it off';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FEATURE_OFF%' THEN RAISE EXCEPTION 'FAIL 7c: %', SQLERRM; END IF;
  END;
  -- Read receipts: Ben has not read the policy by day 3 or day 7; Ana has
  INSERT INTO talent.announcement_receipt (tenant_id, announcement_id, person_id, delivered_on, read_at) VALUES
    (t, a, '17600000-0000-0000-0000-000000000001', '2026-10-20', '2026-10-20 10:00-07'),
    (t, a, '17600000-0000-0000-0000-000000000002', '2026-10-20', NULL);
  IF (SELECT array_agg(person_id) FROM talent.receipts_to_remind(a, '2026-10-23')) <> ARRAY['17600000-0000-0000-0000-000000000002']::uuid[]
     OR EXISTS (SELECT 1 FROM talent.receipts_to_remind(a, '2026-10-24'))
     OR NOT EXISTS (SELECT 1 FROM talent.receipts_to_remind(a, '2026-10-27')) THEN
    RAISE EXCEPTION 'FAIL 7d: unread notice reminders not on days 3 and 7';
  END IF;
  RAISE NOTICE 'PASS 7a-d: audiences; SMS only for urgent alerts and only while switched on; read reminders on days 3 and 7';
END $$;

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; i uuid := '17e10000-0000-0000-0000-000000000001'; th uuid := '17e20000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO talent.idea (tenant_id, idea_id, title, body, submitted_by, submitted_on, status)
    VALUES (t, i, 'Bike racks at the drop-in centre', 'Several of us cycle in.', '17a00000-0000-0000-0000-000000000003', '2026-10-01', 'submitted');
  INSERT INTO talent.idea_vote (tenant_id, idea_id, user_id) VALUES (t, i, '17a00000-0000-0000-0000-000000000002');
  BEGIN
    INSERT INTO talent.idea_vote (tenant_id, idea_id, user_id) VALUES (t, i, '17a00000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'FAIL 7e: voted twice';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    UPDATE talent.idea SET status = 'declined', decided_by = '17a00000-0000-0000-0000-000000000005' WHERE idea_id = i;
    RAISE EXCEPTION 'FAIL 7e: declined with no reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.feedback_thread (tenant_id, thread_id, token_hash, topic, opened_on, status)
    VALUES (t, th, 'sha256:0f3a', 'Scheduling', '2026-10-02', 'open');
  INSERT INTO talent.feedback_message (tenant_id, thread_id, author, body, sent_on)
    VALUES (t, th, 'employee', 'Schedules come out too late to plan childcare.', '2026-10-02');
  BEGIN
    INSERT INTO talent.feedback_message (tenant_id, thread_id, author, body, sent_on) VALUES (t, th, 'hr', 'Thanks', '2026-10-03');
    RAISE EXCEPTION 'FAIL 7f: an HR reply with no HR user';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.feedback_message (tenant_id, thread_id, author, hr_user_id, body, sent_on)
    VALUES (t, th, 'hr', '17a00000-0000-0000-0000-000000000005', 'Thank you. From January schedules will be posted three weeks ahead.', '2026-10-03');
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'talent' AND table_name IN ('feedback_thread','feedback_message','survey_submission')
               AND (column_name ~ 'person|employment|email' OR (column_name = 'submitted_at'))) THEN
    RAISE EXCEPTION 'FAIL 7g: an anonymous table keeps a person link or a time of day';
  END IF;
  RAISE NOTICE 'PASS 7e-g: ideas with one vote each and reasons; the anonymous box with replies and no person link';
END $$;

-- ---------------------------------------------------------------------------------
-- 8. Observances, wellbeing resources, the directory
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  INSERT INTO talent.observance (tenant_id, code, category, name_en, name_fr, rule, month, day, source, active)
    SELECT t, o.code, o.category, o.name_en, o.name_fr, o.rule, o.month, o.day, 'starter', true FROM ref.observance o WHERE o.code IN ('truth_reconciliation','pride_month');
  INSERT INTO talent.observance (tenant_id, code, category, name_en, rule, dates, source, active)
    VALUES (t, 'spring_gathering', 'community', 'Spring gathering on the land', 'dated', ARRAY['[2027-05-14,2027-05-16)'::daterange], 'organization', true);
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'talent' AND table_name = 'observance' AND column_name ~ 'holiday|pay') THEN
    RAISE EXCEPTION 'FAIL 8a: an observance carries pay';
  END IF;
  INSERT INTO talent.wellbeing_resource (tenant_id, kind, title_en, title_fr, url, audience, active)
    VALUES (t, 'crisis_line', '9-8-8 Suicide Crisis Helpline', 'Ligne d''aide en cas de crise de suicide 9-8-8', 'https://988.ca', '{}', true);
  INSERT INTO talent.profile_extra (tenant_id, person_id, interests, name_pronunciation, show_skills, updated_at)
    VALUES (t, '17600000-0000-0000-0000-000000000002', 'Cycling, community radio', 'BEN', false, now());
  RAISE NOTICE 'PASS 8a: observances from the starter list and the organization''s own, never paid; wellbeing links; directory extras by the employee';
END $$;

-- ---------------------------------------------------------------------------------
-- 9. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', '17222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM talent.survey) <> 0 OR (SELECT count(*) FROM talent.survey_submission) <> 0 OR (SELECT count(*) FROM talent.comment_flag) <> 0
     OR (SELECT count(*) FROM talent.recognition) <> 0 OR (SELECT count(*) FROM talent.reward) <> 0 OR (SELECT count(*) FROM talent.announcement) <> 0
     OR (SELECT count(*) FROM talent.feedback_thread) <> 0 OR (SELECT count(*) FROM talent.idea) <> 0 OR (SELECT count(*) FROM talent.imported_result) <> 0 THEN
    RAISE EXCEPTION 'FAIL 9: another organization''s engagement data is visible';
  END IF;
  RAISE NOTICE 'PASS 9: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0017_smoke: all checks passed'
