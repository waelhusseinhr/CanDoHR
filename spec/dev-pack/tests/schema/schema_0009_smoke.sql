-- Smoke test for schema/0009_recruitment_onboarding.sql (docs/23): the new settings and their limits, cautions and
-- acknowledgements, approval routes the organization builds, requisitions with funding and posting exemptions,
-- postings with pay and channels, applications decided only by people, candidate retention from the law and the
-- organization, interviews, offers (routes, changed terms, conditional checks, the hire after the contract is
-- signed, internal moves, direct hires), pre-boarding and onboarding tasks (legal due dates, s. 87, escalation,
-- buddies and mentors), probation (calendar end, check-ins, reminders, leave near the end, extensions, the end
-- date passing), open cases before an ending, status conversion, starter data, tenant isolation and RLS.
-- Run after every migration, 0001 to 0009 (CI, after the 0008 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0009_smoke.sql
-- It does not depend on today's date. It inserts test rows (including a test employment standards edition for 2026);
-- run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, finance, compliance, talent, recruit TO cando_app;
GRANT DELETE ON platform.caution_acknowledgement, recruit.interview_score TO cando_app;   -- so the tests reach the triggers that refuse deletes
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ref, platform, core, payroll, talent, recruit TO cando_app;

-- Test data outside any organization: three organizations, a test employment standards edition, two holidays
INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('91111111-1111-1111-1111-111111111111', 'Recruitment Test Society'),
  ('92222222-2222-2222-2222-222222222222', 'Other Organization'),
  ('93333333-3333-3333-3333-333333333333', 'Strict Contact Organization')
ON CONFLICT DO NOTHING;
INSERT INTO ref.rule_edition (edition_id, family, tax_year, effective_from, effective_to, content, content_sha256, status) VALUES
  ('TEST-ES-0009', 'employment_standards', 2026, '2026-01-01', '2026-12-31',
   '{"nationwide":{"sin_due":{"days_after_start":3,"status":"secondary"}},
     "jurisdictions":{
       "ON":{"candidate_records_retention":{"months":36,"from":"posting_closed","status":"secondary"},
             "termination_notice":{"bands":[{"from_months":3,"weeks":1},{"from_years":1,"weeks":2}],"status":"secondary"}},
       "BC":{"candidate_records_retention":{"months":12,"from":"decision","status":"secondary"}},
       "AB":{"candidate_records_retention":{"months":0,"from":"decision","status":"verify_at_load"}}}}',
   'test-0009', 'active');
INSERT INTO ref.holiday (jurisdiction, holiday_date, observed_date, code, name_en, name_fr, statutory) VALUES
  ('ON', '2026-04-03', '2026-04-03', 'good_friday', 'Good Friday', 'Vendredi saint', true),
  ('ON', '2026-12-25', '2026-12-25', 'christmas', 'Christmas Day', 'Noël', true)
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', '91111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, limits, the locked review of open cases, RLS, starter data
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/23%') <> 28 THEN
    RAISE EXCEPTION 'FAIL 1a: expected 28 settings from docs/23, found %', (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/23%');
  END IF;
  SELECT string_agg(setting_key, ', ' ORDER BY setting_key) INTO bad FROM platform.setting_definition
   WHERE decision_ref LIKE 'docs/23%' AND decision_status = 'pending';
  IF bad <> 'recruit.candidate_retention, recruit.interview_scoring, recruit.missing_requirement, recruit.screening_owner' THEN
    RAISE EXCEPTION 'FAIL 1a: pending settings are %', bad;
  END IF;
  BEGIN
    PERFORM platform.setting(t, 'recruit.screening_owner');
    RAISE EXCEPTION 'FAIL 1b: a setting with no CanDo default returned a value';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 1b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
      VALUES (t, 'recruit.incumbent_average_min', '2', '[2026-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 1c: an incumbent average of 2 people accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_BELOW_MINIMUM%' THEN RAISE EXCEPTION 'FAIL 1c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
      VALUES (t, 'endings.open_case_review', 'false', '[2026-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 1d: the open-case review switched off';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_LOCKED%' THEN RAISE EXCEPTION 'FAIL 1d: %', SQLERRM; END IF;
  END;
  SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.relkind = 'r' AND n.nspname IN ('platform','core','recruit','compliance')
     AND NOT (n.nspname = 'platform' AND c.relname = 'tenant')
     AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1e: RLS missing on %', bad; END IF;
  IF (SELECT count(*) FROM platform.workflow_route WHERE tenant_id = t) <> (SELECT count(*) FROM ref.workflow_route_starter)
     OR (SELECT count(*) FROM recruit.onboarding_plan WHERE tenant_id = t) <> 5
     OR (SELECT count(*) FROM recruit.onboarding_plan_item WHERE tenant_id = t) <> 66
     OR (SELECT count(*) FROM core.list_value WHERE tenant_id = t AND list_code = 'posting_channel') <> 6
     OR NOT EXISTS (SELECT 1 FROM core.list_value WHERE tenant_id = t AND list_code = 'case_kind' AND category = 'complaint') THEN
    RAISE EXCEPTION 'FAIL 1f: starter routes, plans, channels or case kinds not copied to the new organization';
  END IF;
  RAISE NOTICE 'PASS 1a-f: settings and their status, no value without setup, minimum of 3 incumbents, locked open-case review, RLS, starter data';
END $$;

-- ---------------------------------------------------------------------------------
-- Fixtures: one employer in Ontario with a BC office; a unit with its head; a job held by two incumbents;
-- a manager, a supporter and users for HR, finance and an executive
-- ---------------------------------------------------------------------------------
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  (current_setting('app.tenant_id')::uuid, '09a00000-0000-0000-0000-000000000001', 'req9',  'req9@example.test'),
  (current_setting('app.tenant_id')::uuid, '09a00000-0000-0000-0000-000000000002', 'hr9a',  'hr9a@example.test'),
  (current_setting('app.tenant_id')::uuid, '09a00000-0000-0000-0000-000000000003', 'hr9b',  'hr9b@example.test'),
  (current_setting('app.tenant_id')::uuid, '09a00000-0000-0000-0000-000000000004', 'fin9',  'fin9@example.test'),
  (current_setting('app.tenant_id')::uuid, '09a00000-0000-0000-0000-000000000005', 'mgr9',  'mgr9@example.test'),
  (current_setting('app.tenant_id')::uuid, '09a00000-0000-0000-0000-000000000006', 'exec9', 'exec9@example.test'),
  (current_setting('app.tenant_id')::uuid, '09a00000-0000-0000-0000-000000000007', 'new9',  'new9@example.test');
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, 'a9000000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'b9000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'b9000000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, 'b9000000-0000-0000-0000-000000000003');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction) VALUES
  (current_setting('app.tenant_id')::uuid, 'b9000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Head office', '9 Bay St', 'Toronto', 'ON', 'M5J 2N8', 'America/Toronto', 'ON'),
  (current_setting('app.tenant_id')::uuid, 'b9000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'West office', '9 Pender St', 'Vancouver', 'BC', 'V6B 1A1', 'America/Vancouver', 'BC'),
  (current_setting('app.tenant_id')::uuid, 'b9000000-0000-0000-0000-000000000003', '[2026-12-10,)', gen_random_uuid(), 'Calgary office', '9 Stephen Ave', 'Calgary', 'AB', 'T2P 1J9', 'America/Edmonton', 'AB');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, 'c9000000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'd9000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'd9000000-0000-0000-0000-000000000002');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, 'd9000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'CW', 'Community Worker', 'Intervenant communautaire'),
  (current_setting('app.tenant_id')::uuid, 'd9000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'MGR', 'Program Manager', 'Gestionnaire de programme');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, 'e9000000-0000-0000-0000-000000000000', 'P-HEAD'),
  (current_setting('app.tenant_id')::uuid, 'e9000000-0000-0000-0000-000000000001', 'P-OPEN'),
  (current_setting('app.tenant_id')::uuid, 'e9000000-0000-0000-0000-000000000002', 'P-CW2'),
  (current_setting('app.tenant_id')::uuid, 'e9000000-0000-0000-0000-000000000003', 'P-CW3'),
  (current_setting('app.tenant_id')::uuid, 'e9000000-0000-0000-0000-000000000004', 'P-CW4');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'c9000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'a9000000-0000-0000-0000-000000000001', 'DEPT', 'CS', 'Community services', 'e9000000-0000-0000-0000-000000000000');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status)
SELECT current_setting('app.tenant_id')::uuid, p, '[2020-01-01,)', gen_random_uuid(),
       CASE WHEN p IN ('e9000000-0000-0000-0000-000000000000','e9000000-0000-0000-0000-000000000004') THEN 'd9000000-0000-0000-0000-000000000002'::uuid
            ELSE 'd9000000-0000-0000-0000-000000000001'::uuid END,       -- the head and the supporter hold another job
       'c9000000-0000-0000-0000-000000000001',
       'b9000000-0000-0000-0000-000000000001', CASE WHEN p = 'e9000000-0000-0000-0000-000000000000' THEN NULL ELSE 'e9000000-0000-0000-0000-000000000000'::uuid END,
       1, 'permanent', 'active'
  FROM unnest(ARRAY['e9000000-0000-0000-0000-000000000000','e9000000-0000-0000-0000-000000000001','e9000000-0000-0000-0000-000000000002',
                    'e9000000-0000-0000-0000-000000000003','e9000000-0000-0000-0000-000000000004']::uuid[]) p;
INSERT INTO core.person (tenant_id, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f9000000-0000-0000-0000-000000000001'),   -- incumbent 1
  (current_setting('app.tenant_id')::uuid, 'f9000000-0000-0000-0000-000000000002'),   -- incumbent 2
  (current_setting('app.tenant_id')::uuid, 'f9000000-0000-0000-0000-000000000003'),   -- the manager (unit head)
  (current_setting('app.tenant_id')::uuid, 'f9000000-0000-0000-0000-000000000004'),   -- the new hire
  (current_setting('app.tenant_id')::uuid, 'f9000000-0000-0000-0000-000000000005');   -- a supporter
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f9100000-0000-0000-0000-000000000001', 'f9000000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'f9100000-0000-0000-0000-000000000002', 'f9000000-0000-0000-0000-000000000002', 'a9000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'f9100000-0000-0000-0000-000000000003', 'f9000000-0000-0000-0000-000000000003', 'a9000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'f9100000-0000-0000-0000-000000000004', 'f9000000-0000-0000-0000-000000000004', 'a9000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'f9100000-0000-0000-0000-000000000005', 'f9000000-0000-0000-0000-000000000005', 'a9000000-0000-0000-0000-000000000001');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000001', 'f9100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000002', 'f9100000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000003', 'f9100000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000004', 'f9100000-0000-0000-0000-000000000004'),
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000005', 'f9100000-0000-0000-0000-000000000005');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type) VALUES
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000001', '[2025-01-01,)', gen_random_uuid(), 'e9000000-0000-0000-0000-000000000002', 'c9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000002', '[2025-01-01,)', gen_random_uuid(), 'e9000000-0000-0000-0000-000000000003', 'c9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'e9000000-0000-0000-0000-000000000000', 'c9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000004', '[2026-11-02,)', gen_random_uuid(), 'e9000000-0000-0000-0000-000000000001', 'c9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '09200000-0000-0000-0000-000000000005', '[2024-01-01,)', gen_random_uuid(), 'e9000000-0000-0000-0000-000000000004', 'c9000000-0000-0000-0000-000000000001', 'b9000000-0000-0000-0000-000000000002', 1, true, 'permanent');
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by) VALUES
  (current_setting('app.tenant_id')::uuid, '09d00000-0000-0000-0000-000000000001', 'candidate', '09c00000-0000-0000-0000-000000000002', 'check_consent', 'restricted', 'recruitment', 'test/consent.pdf', 'x', 'application/pdf',
   '09a00000-0000-0000-0000-000000000002');

-- ---------------------------------------------------------------------------------
-- 2. Cautions: a written reason where it is needed, acknowledgements never change, approval by someone else
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; ack uuid;
BEGIN
  BEGIN
    INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by)
      VALUES (t, 'recruit.seniority_order_overridden', 'posting', gen_random_uuid(), 'shown', 'en', '09a00000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'FAIL 2a: seniority override without a reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_REASON_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'recruit.seniority_order_overridden', 'posting', gen_random_uuid(), 'shown', 'en', '09a00000-0000-0000-0000-000000000002',
            'The senior applicant does not hold the required licence') RETURNING ack_id INTO ack;
  BEGIN
    UPDATE platform.caution_acknowledgement SET reason = 'changed' WHERE ack_id = ack;
    RAISE EXCEPTION 'FAIL 2b: acknowledgement changed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_ACK_IMMUTABLE%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  BEGIN
    DELETE FROM platform.caution_acknowledgement WHERE ack_id = ack;
    RAISE EXCEPTION 'FAIL 2b: acknowledgement deleted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_ACK_IMMUTABLE%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  -- The organization asks a reason and an approval for advancing a candidate without a required qualification
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id) VALUES
    (t, 'cautions.reason_required',   '["recruit.missing_requirement_advanced"]', '[2000-01-01,)', gen_random_uuid()),
    (t, 'cautions.approval_required', '["recruit.missing_requirement_advanced"]', '[2000-01-01,)', gen_random_uuid());
  BEGIN
    INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by)
      VALUES (t, 'recruit.missing_requirement_advanced', 'application', '09e00000-0000-0000-0000-000000000099', 'shown', 'en', '09a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 2c: the organization''s reason requirement ignored';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_REASON_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (ack_id, tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES ('09f00000-0000-0000-0000-000000000001', t, 'recruit.missing_requirement_advanced', 'application', '09e00000-0000-0000-0000-000000000099',
            'shown', 'en', '09a00000-0000-0000-0000-000000000005', 'Licence exam passed; certificate arrives next week');
  IF platform.caution_cleared(t, 'recruit.missing_requirement_advanced', 'application', '09e00000-0000-0000-0000-000000000099') THEN
    RAISE EXCEPTION 'FAIL 2d: cleared without the approval the organization asks for';
  END IF;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, task_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, '09f10000-0000-0000-0000-000000000001', 'caution', '09f00000-0000-0000-0000-000000000001', 1, 'approved', '09a00000-0000-0000-0000-000000000005', now(), 'hr');
    RAISE EXCEPTION 'FAIL 2d: the acknowledger approved their own caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, task_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, '09f10000-0000-0000-0000-000000000002', 'caution', '09f00000-0000-0000-0000-000000000001', 1, 'approved', '09a00000-0000-0000-0000-000000000002', now(), 'hr');
  UPDATE platform.caution_acknowledgement SET approval_task_id = '09f10000-0000-0000-0000-000000000002' WHERE ack_id = '09f00000-0000-0000-0000-000000000001';
  IF NOT platform.caution_cleared(t, 'recruit.missing_requirement_advanced', 'application', '09e00000-0000-0000-0000-000000000099') THEN
    RAISE EXCEPTION 'FAIL 2d: not cleared after HR approved it';
  END IF;
  RAISE NOTICE 'PASS 2a-d: reasons where needed, acknowledgements immutable, the organization''s extra reason and approval, no self-approval';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Routes the organization builds: conditions, priority, missing facts, no route
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO platform.workflow_route (tenant_id, code, subject_type, name_en, conditions, priority, status)
      VALUES (t, 'colour', 'offer', 'By colour', '{"colour":["blue"]}', 99, 'active');
    RAISE EXCEPTION 'FAIL 3a: unknown route condition accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_CONDITION_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 3a: %', SQLERRM; END IF;
  END;
  IF (SELECT code FROM platform.workflow_route WHERE route_id = platform.route_for(t, 'requisition', '{"requisitionType":"replacement","overBudget":false}')) <> 'req_replacement'
     OR (SELECT code FROM platform.workflow_route WHERE route_id = platform.route_for(t, 'requisition', '{"requisitionType":"new_position","overBudget":true}')) <> 'req_over_budget'
     OR (SELECT code FROM platform.workflow_route WHERE route_id = platform.route_for(t, 'offer', '{"outsideRange":false}')) <> 'offer_standard' THEN
    RAISE EXCEPTION 'FAIL 3b: route not chosen by priority and conditions';
  END IF;
  BEGIN
    PERFORM platform.route_for(t, 'requisition', '{"requisitionType":"replacement"}');
    RAISE EXCEPTION 'FAIL 3c: a route chosen without a fact its conditions need';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_FACT_MISSING%' THEN RAISE EXCEPTION 'FAIL 3c: %', SQLERRM; END IF;
  END;
  BEGIN
    PERFORM platform.route_for(t, 'caution', '{}');
    RAISE EXCEPTION 'FAIL 3d: a route found where the organization has none';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_NOT_FOUND%' THEN RAISE EXCEPTION 'FAIL 3d: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 3a-d: route conditions checked, first match by priority, missing facts and missing routes are errors';
END $$;

-- ---------------------------------------------------------------------------------
-- 4. Requisitions: funding lines adding to 100, the route complete, no self-approval, posting exemptions
-- ---------------------------------------------------------------------------------
INSERT INTO recruit.posting_exemption_rule (tenant_id, code, category, name_en, name_fr, status) VALUES
  (current_setting('app.tenant_id')::uuid, 'NAMED', 'named_candidate', 'A candidate the manager has in mind', 'Un candidat que le gestionnaire a en tête', 'active');
INSERT INTO recruit.requisition (tenant_id, requisition_id, number, position_id, requisition_type, posting_jurisdiction, uses_ai_screening, vacancy_exists, status,
                                 requested_by, hiring_manager_user, employment_type, fte, target_start, route_id) VALUES
  (current_setting('app.tenant_id')::uuid, '09b00000-0000-0000-0000-000000000001', 'R-1', 'e9000000-0000-0000-0000-000000000001', 'replacement', 'ON', false, true, 'draft',
   '09a00000-0000-0000-0000-000000000001', '09a00000-0000-0000-0000-000000000005', 'permanent', 1, '2026-11-02',
   (SELECT route_id FROM platform.workflow_route WHERE tenant_id = current_setting('app.tenant_id')::uuid AND code = 'req_replacement')),
  (current_setting('app.tenant_id')::uuid, '09b00000-0000-0000-0000-000000000002', 'R-2', 'e9000000-0000-0000-0000-000000000001', 'replacement', 'ON', false, true, 'draft',
   '09a00000-0000-0000-0000-000000000001', '09a00000-0000-0000-0000-000000000005', 'permanent', 1, '2026-11-02',
   (SELECT route_id FROM platform.workflow_route WHERE tenant_id = current_setting('app.tenant_id')::uuid AND code = 'req_replacement')),
  (current_setting('app.tenant_id')::uuid, '09b00000-0000-0000-0000-000000000003', 'R-3', 'e9000000-0000-0000-0000-000000000001', 'replacement', 'ON', false, true, 'draft',
   '09a00000-0000-0000-0000-000000000001', '09a00000-0000-0000-0000-000000000005', 'permanent', 1, '2026-11-02', NULL);
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    UPDATE recruit.requisition SET status = 'pending_approval' WHERE requisition_id = '09b00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4a: submitted without funding';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'REQUISITION_FUNDING_MISSING%' THEN RAISE EXCEPTION 'FAIL 4a: %', SQLERRM; END IF;
  END;
  INSERT INTO recruit.requisition_funding (tenant_id, requisition_id, line_no, segments, share_percent) VALUES
    (t, '09b00000-0000-0000-0000-000000000001', 1, '{"cost_centre":"4410"}', 60),
    (t, '09b00000-0000-0000-0000-000000000001', 2, '{"cost_centre":"4420","fund":"PROV-GRANT"}', 30);
  BEGIN
    UPDATE recruit.requisition SET status = 'pending_approval' WHERE requisition_id = '09b00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4b: shares of 90 accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'REQUISITION_FUNDING_NOT_100%' THEN RAISE EXCEPTION 'FAIL 4b: %', SQLERRM; END IF;
  END;
  INSERT INTO recruit.requisition_funding (tenant_id, requisition_id, line_no, segments, share_percent) VALUES
    (t, '09b00000-0000-0000-0000-000000000001', 3, '{"cost_centre":"4430","funder":"UNITED-WAY"}', 10);
  UPDATE recruit.requisition SET status = 'pending_approval' WHERE requisition_id = '09b00000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE recruit.requisition SET status = 'approved' WHERE requisition_id = '09b00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4c: approved with no approvals';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 4c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'requisition', '09b00000-0000-0000-0000-000000000001', 1, 'approved', '09a00000-0000-0000-0000-000000000001', now(), 'hr');
    RAISE EXCEPTION 'FAIL 4d: the requester approved their own requisition';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 4d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'requisition', '09b00000-0000-0000-0000-000000000001', 1, 'approved', '09a00000-0000-0000-0000-000000000002', now(), 'hr');
  UPDATE recruit.requisition SET status = 'approved' WHERE requisition_id = '09b00000-0000-0000-0000-000000000001';

  -- Filled without a posting although an agreement requires one: the caution is acknowledged first
  UPDATE recruit.requisition SET posting_exemption_code = 'NAMED', posting_required_by = ARRAY['agreement:CUPE-9:12.1']
   WHERE requisition_id = '09b00000-0000-0000-0000-000000000002';
  INSERT INTO recruit.requisition_funding (tenant_id, requisition_id, line_no, segments, share_percent) VALUES
    (t, '09b00000-0000-0000-0000-000000000002', 1, '{"cost_centre":"4410"}', 100);
  UPDATE recruit.requisition SET status = 'pending_approval' WHERE requisition_id = '09b00000-0000-0000-0000-000000000002';
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'requisition', '09b00000-0000-0000-0000-000000000002', 1, 'approved', '09a00000-0000-0000-0000-000000000002', now(), 'hr');
  BEGIN
    UPDATE recruit.requisition SET status = 'approved' WHERE requisition_id = '09b00000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 4e: posting skipped where the agreement requires one, without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 4e: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'recruit.posting_skipped_where_required', 'requisition', '09b00000-0000-0000-0000-000000000002', 'shown', 'en',
            '09a00000-0000-0000-0000-000000000002', 'Union agreed in writing to a direct appointment (letter of 20 Oct)');
  UPDATE recruit.requisition SET status = 'approved' WHERE requisition_id = '09b00000-0000-0000-0000-000000000002';
  INSERT INTO recruit.requisition_funding (tenant_id, requisition_id, line_no, segments, share_percent) VALUES
    (t, '09b00000-0000-0000-0000-000000000003', 1, '{"cost_centre":"4410"}', 100);
  UPDATE recruit.requisition SET route_id = (SELECT route_id FROM platform.workflow_route WHERE tenant_id = t AND code = 'req_replacement')
   WHERE requisition_id = '09b00000-0000-0000-0000-000000000003';
  BEGIN
    UPDATE recruit.requisition SET posting_exemption_code = 'NOPE', status = 'pending_approval' WHERE requisition_id = '09b00000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 4f: unknown posting exemption accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'POSTING_EXEMPTION_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 4f: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 4a-f: funding lines must add to 100, route complete, no self-approval, posting exemption with the caution';
END $$;

-- ---------------------------------------------------------------------------------
-- 5. Postings: starting values from settings, a choice the organization must make, the incumbent average, channels
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; p recruit.posting;
BEGIN
  BEGIN
    INSERT INTO recruit.posting (tenant_id, requisition_id, legal_entity_id, title, ai_notice_included, status)
      VALUES (t, '09b00000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001', 'Community Worker', false, 'draft');
    RAISE EXCEPTION 'FAIL 5a: posting created before the organization chose how missing qualifications are handled';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'recruit.missing_requirement', '"flag"', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO recruit.posting (tenant_id, posting_id, requisition_id, legal_entity_id, title, ai_notice_included, status)
    VALUES (t, '09ee0000-0000-0000-0000-000000000001', '09b00000-0000-0000-0000-000000000001', 'a9000000-0000-0000-0000-000000000001', 'Community Worker', false, 'draft')
    RETURNING * INTO p;
  IF p.audience <> 'internal_and_public' OR NOT p.pay_shown OR p.pay_basis <> 'range' OR NOT p.seniority_applies
     OR p.lang <> 'en' OR p.missing_requirement <> 'flag' THEN
    RAISE EXCEPTION 'FAIL 5b: starting values not taken from the settings: %', to_jsonb(p);
  END IF;
  IF recruit.incumbent_count('09b00000-0000-0000-0000-000000000001', '2026-10-15') <> 2 THEN
    RAISE EXCEPTION 'FAIL 5c: incumbents of the job counted as %', recruit.incumbent_count('09b00000-0000-0000-0000-000000000001', '2026-10-15');
  END IF;
  BEGIN
    UPDATE recruit.posting SET pay_basis = 'incumbent_average', status = 'published', published_by = '09a00000-0000-0000-0000-000000000002', opens_on = '2026-10-15'
     WHERE posting_id = '09ee0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5c: the average of 2 incumbents shown';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INCUMBENT_AVERAGE_UNAVAILABLE%' THEN RAISE EXCEPTION 'FAIL 5c: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.posting SET status = 'published', published_by = '09a00000-0000-0000-0000-000000000002', opens_on = '2026-10-15'
     WHERE posting_id = '09ee0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5d: a range published without its numbers';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 5d: %', SQLERRM; END IF;
  END;
  UPDATE recruit.posting SET status = 'published', published_by = '09a00000-0000-0000-0000-000000000002', opens_on = '2026-10-15',
         closes_on = '2026-11-30', pay_min = 24, pay_max = 29, pay_unit = 'hour'
   WHERE posting_id = '09ee0000-0000-0000-0000-000000000001';
  BEGIN
    INSERT INTO recruit.posting (tenant_id, requisition_id, legal_entity_id, title, ai_notice_included, status, published_by, opens_on, pay_min, pay_max, pay_unit)
      VALUES (t, '09b00000-0000-0000-0000-000000000003', 'a9000000-0000-0000-0000-000000000001', 'Community Worker', false, 'published', '09a00000-0000-0000-0000-000000000002', '2026-10-15', 24, 29, 'hour');
    RAISE EXCEPTION 'FAIL 5e: posting published on a requisition not approved';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'POSTING_REQUISITION_NOT_APPROVED%' THEN RAISE EXCEPTION 'FAIL 5e: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO recruit.posting_channel (tenant_id, posting_id, channel_code) VALUES (t, '09ee0000-0000-0000-0000-000000000001', 'billboard');
    RAISE EXCEPTION 'FAIL 5f: a channel not on the organization''s list accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    IF SQLERRM NOT LIKE 'LIST_VALUE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 5f: %', SQLERRM; END IF;
  END;
  INSERT INTO recruit.posting_channel (tenant_id, posting_id, channel_code, published_at) VALUES
    (t, '09ee0000-0000-0000-0000-000000000001', 'career_page', now()),
    (t, '09ee0000-0000-0000-0000-000000000001', 'professional_body', now());
  BEGIN
    INSERT INTO recruit.posting_question (tenant_id, posting_id, seq, kind, required, text_en)
      VALUES (t, '09ee0000-0000-0000-0000-000000000001', 1, 'multiple_choice', true, 'Which shift can you work?');
    RAISE EXCEPTION 'FAIL 5g: a multiple-choice question without choices';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO recruit.posting_question (tenant_id, posting_id, seq, kind, required, text_en, text_fr) VALUES
    (t, '09ee0000-0000-0000-0000-000000000001', 1, 'yes_no', true, 'Do you hold a valid class 5 driver''s licence?', 'Avez-vous un permis de conduire de classe 5 valide?');
  -- A setting set for one employer starts that employer's postings
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'recruit.posting_pay_basis', 'legal_entity', 'a9000000-0000-0000-0000-000000000001', '"market_point"', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO recruit.posting (tenant_id, requisition_id, legal_entity_id, title, ai_notice_included, status)
    VALUES (t, '09b00000-0000-0000-0000-000000000002', 'a9000000-0000-0000-0000-000000000001', 'Community Worker', false, 'draft') RETURNING * INTO p;
  IF p.pay_basis <> 'market_point' THEN RAISE EXCEPTION 'FAIL 5h: the employer''s own setting not used (%)', p.pay_basis; END IF;
  RAISE NOTICE 'PASS 5a-h: starting values from settings (per employer), the organization''s own choice required, incumbent average needs 3, range numbers, approved requisition, channels from the list, questions';
END $$;

-- ---------------------------------------------------------------------------------
-- 6. Candidates apply without an account, with an email or a phone number as the organization asks
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO recruit.candidate (tenant_id, first_name, last_name, consent) VALUES (t, 'No', 'Contact', '{}');
    RAISE EXCEPTION 'FAIL 6a: a candidate with no way to reach them';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO recruit.candidate (tenant_id, candidate_id, first_name, last_name, email, phone, consent) VALUES
    (t, '09c00000-0000-0000-0000-000000000001', 'Ana',  'Phone', NULL, '+1 416 555 0101', '{"privacy":"2026-10-16"}'),
    (t, '09c00000-0000-0000-0000-000000000002', 'Sam',  'Lee',   'sam@example.test', NULL, '{"privacy":"2026-10-16"}'),
    (t, '09c00000-0000-0000-0000-000000000003', 'Rae',  'Moss',  'rae@example.test', NULL, '{"privacy":"2026-10-17"}'),
    (t, '09c00000-0000-0000-0000-000000000004', 'Inez', 'Inside','inez@example.test', NULL, '{"privacy":"2026-10-18"}');
  PERFORM set_config('app.tenant_id', '93333333-3333-3333-3333-333333333333', false);
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES ('93333333-3333-3333-3333-333333333333', 'recruit.applicant_contact', '"email"', '[2000-01-01,)', gen_random_uuid());
  BEGIN
    INSERT INTO recruit.candidate (tenant_id, first_name, last_name, phone, consent)
      VALUES ('93333333-3333-3333-3333-333333333333', 'Only', 'Phone', '+1 604 555 0102', '{}');
    RAISE EXCEPTION 'FAIL 6b: phone only accepted where the organization asks for an email';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CANDIDATE_CONTACT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 6b: %', SQLERRM; END IF;
  END;
  PERFORM set_config('app.tenant_id', '91111111-1111-1111-1111-111111111111', false);
  RAISE NOTICE 'PASS 6a-b: an email or a phone number; the organization can ask for more';
END $$;

-- ---------------------------------------------------------------------------------
-- 7. Applications: AI suggestions only when switched on; decisions by people; retention from the law and the
--    organization; interviews scored and locked
-- ---------------------------------------------------------------------------------
INSERT INTO recruit.application (tenant_id, application_id, requisition_id, candidate_id, stage, posting_id, internal_employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '09e00000-0000-0000-0000-000000000001', '09b00000-0000-0000-0000-000000000001', '09c00000-0000-0000-0000-000000000001', 'applied', '09ee0000-0000-0000-0000-000000000001', NULL),
  (current_setting('app.tenant_id')::uuid, '09e00000-0000-0000-0000-000000000002', '09b00000-0000-0000-0000-000000000001', '09c00000-0000-0000-0000-000000000002', 'applied', '09ee0000-0000-0000-0000-000000000001', NULL),
  (current_setting('app.tenant_id')::uuid, '09e00000-0000-0000-0000-000000000003', '09b00000-0000-0000-0000-000000000003', '09c00000-0000-0000-0000-000000000003', 'applied', NULL, NULL),
  (current_setting('app.tenant_id')::uuid, '09e00000-0000-0000-0000-000000000004', '09b00000-0000-0000-0000-000000000001', '09c00000-0000-0000-0000-000000000004', 'applied', '09ee0000-0000-0000-0000-000000000001', 'f9100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '09e00000-0000-0000-0000-000000000006', '09b00000-0000-0000-0000-000000000001', '09c00000-0000-0000-0000-000000000003', 'applied', '09ee0000-0000-0000-0000-000000000001', NULL),
  (current_setting('app.tenant_id')::uuid, '09e00000-0000-0000-0000-000000000007', '09b00000-0000-0000-0000-000000000001', '09c00000-0000-0000-0000-000000000001', 'applied', '09ee0000-0000-0000-0000-000000000001', NULL);
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; a recruit.application;
BEGIN
  BEGIN
    UPDATE recruit.application SET match_score = 82, match_reasons = '{"licence":"yes"}' WHERE application_id = '09e00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7a: AI score stored while suggestions are off';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'MATCH_SUGGESTIONS_OFF%' THEN RAISE EXCEPTION 'FAIL 7a: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.application SET outcome = 'not_selected' WHERE application_id = '09e00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7b: a decision nobody signed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'APPLICATION_DECISION_UNSIGNED%' THEN RAISE EXCEPTION 'FAIL 7b: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.application SET outcome = 'screened_out', decided_by_kind = 'requirement_rule', decided_on = '2026-11-02',
           missing_requirements = ARRAY['class 5 licence'] WHERE application_id = '09e00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7c: screened out by a rule on a posting that flags';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'REQUIREMENT_RULE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 7c: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.application SET outcome = 'not_selected', decided_by_kind = 'person', decided_by = '09a00000-0000-0000-0000-000000000005', decided_on = '2026-11-02'
     WHERE application_id = '09e00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7d: decided before the organization chose how long candidate records are kept';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 7d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id) VALUES
    (t, 'recruit.candidate_retention', '{"mode":"per_province","organizationMonths":6}',    '[2026-01-01,2026-12-01)', gen_random_uuid()),
    (t, 'recruit.candidate_retention', '{"mode":"longest_for_all","organizationMonths":6}', '[2026-12-01,)', gen_random_uuid());
  UPDATE recruit.application SET outcome = 'not_selected', decided_by_kind = 'person', decided_by = '09a00000-0000-0000-0000-000000000005', decided_on = '2026-11-02'
   WHERE application_id = '09e00000-0000-0000-0000-000000000001' RETURNING * INTO a;
  IF a.retention_until <> '2029-11-30' OR (SELECT retention_until FROM recruit.candidate WHERE candidate_id = '09c00000-0000-0000-0000-000000000001') <> '2029-11-30' THEN
    RAISE EXCEPTION 'FAIL 7e: Ontario keeps postings and applications 3 years after the posting closes; got %', a.retention_until;
  END IF;
  BEGIN
    UPDATE recruit.application SET outcome = 'not_selected', decided_by_kind = 'person', decided_by = '09a00000-0000-0000-0000-000000000005', decided_on = '2026-11-02'
     WHERE application_id = '09e00000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 7f: Ontario retention worked out without the posting''s closing date';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7f: %', SQLERRM; END IF;
  END;
  -- Every interview is scored before a decision; a submitted score is locked
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'recruit.interview_scoring', '"every_interview"', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO recruit.interview (tenant_id, interview_id, application_id, kit_code, held_on, status)
    VALUES (t, '09ac0000-0000-0000-0000-000000000001', '09e00000-0000-0000-0000-000000000006', 'CW-KIT', '2026-11-20', 'held');
  BEGIN
    UPDATE recruit.application SET outcome = 'not_selected', decided_by_kind = 'person', decided_by = '09a00000-0000-0000-0000-000000000005', decided_on = '2026-12-05'
     WHERE application_id = '09e00000-0000-0000-0000-000000000006';
    RAISE EXCEPTION 'FAIL 7g: decided with an unscored interview';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INTERVIEW_SCORE_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7g: %', SQLERRM; END IF;
  END;
  INSERT INTO recruit.interview_score (tenant_id, interview_id, panelist_user, scores, submitted_at)
    VALUES (t, '09ac0000-0000-0000-0000-000000000001', '09a00000-0000-0000-0000-000000000005', '{"client_focus":4,"safety":3}', now());
  BEGIN
    UPDATE recruit.interview_score SET scores = '{"client_focus":5,"safety":5}' WHERE interview_id = '09ac0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7h: submitted score changed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SCORE_LOCKED%' THEN RAISE EXCEPTION 'FAIL 7h: %', SQLERRM; END IF;
  END;
  IF NOT recruit.can_see_panel_scores('09ac0000-0000-0000-0000-000000000001', '09a00000-0000-0000-0000-000000000005')
     OR recruit.can_see_panel_scores('09ac0000-0000-0000-0000-000000000001', '09a00000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'FAIL 7h: panel scores visible before submitting one''s own';
  END IF;
  -- After 1 December the organization keeps records for the longest period of all its locations (Ontario, BC)
  UPDATE recruit.application SET outcome = 'not_selected', decided_by_kind = 'person', decided_by = '09a00000-0000-0000-0000-000000000005', decided_on = '2026-12-05'
   WHERE application_id = '09e00000-0000-0000-0000-000000000006' RETURNING * INTO a;
  IF a.retention_until <> '2029-11-30' THEN RAISE EXCEPTION 'FAIL 7i: longest period not kept: %', a.retention_until; END IF;
  -- A location in Alberta from 10 December: its rule is not verified yet, so nothing is decided on a guess
  BEGIN
    UPDATE recruit.application SET outcome = 'not_selected', decided_by_kind = 'person', decided_by = '09a00000-0000-0000-0000-000000000005', decided_on = '2026-12-15'
     WHERE application_id = '09e00000-0000-0000-0000-000000000007';
    RAISE EXCEPTION 'FAIL 7j: retention worked out from an unverified rule';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RULE_NOT_VERIFIED%' THEN RAISE EXCEPTION 'FAIL 7j: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 7a-j: AI off until switched on, decisions by people, retention from the law and the organization, interviews scored and locked, unverified rules stop';
END $$;

-- ---------------------------------------------------------------------------------
-- 8. Offers: required content, posting needed, route, expiry, changed terms, conditional checks with consent,
--    the hire only after the contract is signed, internal moves, direct hires
-- ---------------------------------------------------------------------------------
INSERT INTO recruit.offer (tenant_id, offer_id, application_id, start_date, pay_rate, pay_basis, status, hire_path, conditional, terms, requested_by) VALUES
  (current_setting('app.tenant_id')::uuid, '09ab0000-0000-0000-0000-000000000001', '09e00000-0000-0000-0000-000000000002', '2026-11-02', 26, 'hour', 'draft',
   'requisition', true, '{"payRate":26,"startDate":"2026-11-02"}', '09a00000-0000-0000-0000-000000000005'),
  (current_setting('app.tenant_id')::uuid, '09ab0000-0000-0000-0000-000000000002', '09e00000-0000-0000-0000-000000000002', '2026-11-02', 26, 'hour', 'draft',
   'requisition', false, '{"payRate":26,"startDate":"2026-11-02"}', '09a00000-0000-0000-0000-000000000005'),
  (current_setting('app.tenant_id')::uuid, '09ab0000-0000-0000-0000-000000000003', '09e00000-0000-0000-0000-000000000004', '2026-11-02', 27, 'hour', 'draft',
   'requisition', false, '{"payRate":27,"startDate":"2026-11-02"}', '09a00000-0000-0000-0000-000000000005');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r uuid; o recruit.offer;
BEGIN
  SELECT route_id INTO r FROM platform.workflow_route WHERE tenant_id = t AND code = 'offer_standard';
  BEGIN
    INSERT INTO recruit.offer (tenant_id, application_id, start_date, pay_rate, pay_basis, status)
      VALUES (t, '09e00000-0000-0000-0000-000000000002', '2026-11-02', 26, 'hour', 'draft');
    RAISE EXCEPTION 'FAIL 8a: offer without its hire path, conditions and terms';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 8a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO recruit.offer (tenant_id, application_id, start_date, pay_rate, pay_basis, status, hire_path, conditional, terms, requested_by)
      VALUES (t, '09e00000-0000-0000-0000-000000000003', '2026-11-02', 26, 'hour', 'draft', 'requisition', false, '{"payRate":26}', '09a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 8b: offer without a posting or a posting exemption';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'POSTING_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 8b: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.offer SET status = 'pending_approval' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8c: submitted without a route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 8c: %', SQLERRM; END IF;
  END;
  UPDATE recruit.offer SET route_id = r, status = 'pending_approval' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE recruit.offer SET status = 'approved' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8d: approved with no approvals';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 8d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'offer', '09ab0000-0000-0000-0000-000000000001', 1, 'approved', '09a00000-0000-0000-0000-000000000002', clock_timestamp() - interval '1 hour', 'hr');
  UPDATE recruit.offer SET status = 'approved' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001' RETURNING * INTO o;
  IF o.approved_terms IS DISTINCT FROM o.terms THEN RAISE EXCEPTION 'FAIL 8d: approved terms not kept'; END IF;
  -- A background check is a condition of the conditional offer, and starts only once the offer is made
  INSERT INTO recruit.offer_condition (tenant_id, condition_id, offer_id, kind, status)
    VALUES (t, '09ab1000-0000-0000-0000-000000000001', '09ab0000-0000-0000-0000-000000000001', 'criminal_record_check', 'pending');
  BEGIN
    UPDATE recruit.offer_condition SET status = 'requested', requested_at = now(), consent_document_id = '09d00000-0000-0000-0000-000000000001'
     WHERE condition_id = '09ab1000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8e: criminal record check started before the conditional offer was made';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CHECK_BEFORE_CONDITIONAL_OFFER%' THEN RAISE EXCEPTION 'FAIL 8e: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.offer SET status = 'sent' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8f: sent without an expiry';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'OFFER_NOT_READY%' THEN RAISE EXCEPTION 'FAIL 8f: %', SQLERRM; END IF;
  END;
  UPDATE recruit.offer SET status = 'sent', expires_on = '2026-10-30', expiry_set_by = '09a00000-0000-0000-0000-000000000005'
   WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
  -- Changed terms go back through the route (offers.reapprove_on_change = any_change)
  BEGIN
    UPDATE recruit.offer SET terms = '{"payRate":27,"startDate":"2026-11-02"}' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8g: terms changed without going back for approval';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'OFFER_CHANGE_NEEDS_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 8g: %', SQLERRM; END IF;
  END;
  UPDATE recruit.offer SET terms = '{"payRate":27,"startDate":"2026-11-02"}', status = 'pending_approval' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE recruit.offer SET status = 'approved' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8g: changed terms approved with the approval of the old terms';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 8g: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'offer', '09ab0000-0000-0000-0000-000000000001', 1, 'approved', '09a00000-0000-0000-0000-000000000003', clock_timestamp(), 'hr');
  UPDATE recruit.offer SET status = 'approved' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
  UPDATE recruit.offer SET status = 'sent' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE recruit.offer_condition SET status = 'requested', requested_at = now() WHERE condition_id = '09ab1000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8h: criminal record check without consent';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CONSENT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 8h: %', SQLERRM; END IF;
  END;
  UPDATE recruit.offer_condition SET status = 'requested', requested_at = now(), consent_document_id = '09d00000-0000-0000-0000-000000000001'
   WHERE condition_id = '09ab1000-0000-0000-0000-000000000001';
  BEGIN
    INSERT INTO recruit.offer_condition (tenant_id, offer_id, kind, status) VALUES (t, '09ab0000-0000-0000-0000-000000000002', 'background_check', 'pending');
    RAISE EXCEPTION 'FAIL 8i: background check on an offer that is not conditional';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CHECK_NEEDS_CONDITIONAL_OFFER%' THEN RAISE EXCEPTION 'FAIL 8i: %', SQLERRM; END IF;
  END;
  -- Accepted is not hired: the record is created once the contract is signed
  UPDATE recruit.offer SET status = 'accepted' WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE recruit.offer SET hire_change_set_id = gen_random_uuid() WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8j: employee record created before the contract was signed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'HIRE_BEFORE_CONTRACT_SIGNED%' THEN RAISE EXCEPTION 'FAIL 8j: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.offer SET contract_signed_at = now() WHERE offer_id = '09ab0000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 8j: contract signed on an offer not accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CONTRACT_BEFORE_ACCEPTANCE%' THEN RAISE EXCEPTION 'FAIL 8j: %', SQLERRM; END IF;
  END;
  UPDATE recruit.offer SET contract_signed_at = now() WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
  UPDATE recruit.offer SET hire_change_set_id = gen_random_uuid() WHERE offer_id = '09ab0000-0000-0000-0000-000000000001';
  -- An internal applicant: telling the current supervisor becomes a condition; the move is a transfer or a resignation
  UPDATE recruit.offer SET route_id = r, status = 'pending_approval' WHERE offer_id = '09ab0000-0000-0000-0000-000000000003';
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'offer', '09ab0000-0000-0000-0000-000000000003', 1, 'approved', '09a00000-0000-0000-0000-000000000002', clock_timestamp(), 'hr');
  UPDATE recruit.offer SET status = 'approved' WHERE offer_id = '09ab0000-0000-0000-0000-000000000003';
  UPDATE recruit.offer SET status = 'sent', expires_on = '2026-10-30', expiry_set_by = '09a00000-0000-0000-0000-000000000002' WHERE offer_id = '09ab0000-0000-0000-0000-000000000003';
  UPDATE recruit.offer SET status = 'accepted' WHERE offer_id = '09ab0000-0000-0000-0000-000000000003';
  IF NOT EXISTS (SELECT 1 FROM recruit.offer_condition WHERE offer_id = '09ab0000-0000-0000-0000-000000000003' AND kind = 'tell_current_supervisor') THEN
    RAISE EXCEPTION 'FAIL 8k: telling the current supervisor not added as a condition';
  END IF;
  UPDATE recruit.offer SET contract_signed_at = now() WHERE offer_id = '09ab0000-0000-0000-0000-000000000003';
  BEGIN
    UPDATE recruit.offer SET hire_change_set_id = gen_random_uuid() WHERE offer_id = '09ab0000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 8k: internal move without saying whether it is a transfer';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 8k: %', SQLERRM; END IF;
  END;
  UPDATE recruit.offer SET internal_move = 'transfer', hire_change_set_id = gen_random_uuid() WHERE offer_id = '09ab0000-0000-0000-0000-000000000003';
  IF recruit.open_conditions('09ab0000-0000-0000-0000-000000000003') <> 1 THEN RAISE EXCEPTION 'FAIL 8k: open conditions not counted'; END IF;
  -- Direct hire through the organization's route; an organization can forbid it
  INSERT INTO recruit.offer (tenant_id, candidate_id, position_id, start_date, pay_rate, pay_basis, status, hire_path, conditional, terms, requested_by)
    VALUES (t, '09c00000-0000-0000-0000-000000000003', 'e9000000-0000-0000-0000-000000000001', '2026-11-16', 26, 'hour', 'draft', 'direct_hire', false,
            '{"payRate":26,"startDate":"2026-11-16"}', '09a00000-0000-0000-0000-000000000005');
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'recruit.direct_hire', '"not_allowed"', '[2000-01-01,)', gen_random_uuid());
  BEGIN
    INSERT INTO recruit.offer (tenant_id, candidate_id, position_id, start_date, pay_rate, pay_basis, status, hire_path, conditional, terms, requested_by)
      VALUES (t, '09c00000-0000-0000-0000-000000000003', 'e9000000-0000-0000-0000-000000000001', '2026-11-16', 26, 'hour', 'draft', 'direct_hire', false,
              '{"payRate":26}', '09a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 8l: direct hire where the organization does not allow it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'DIRECT_HIRE_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 8l: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 8a-l: offer content, posting needed, route, expiry, re-approval after a change, conditional checks with consent, hire after signing, internal moves, direct hire';
END $$;

-- ---------------------------------------------------------------------------------
-- 9. Pre-boarding and onboarding: plans that apply, tasks with legal due dates, s. 87, escalation, supporters
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; n int; s recruit.onboarding_task; e record;
BEGIN
  IF (SELECT count(*) FROM recruit.plans_for('f9100000-0000-0000-0000-000000000004', 'new_hire', '2026-11-02')) <> 1 THEN
    RAISE EXCEPTION 'FAIL 9a: plans for a new hire not found';
  END IF;
  n := recruit.generate_onboarding_tasks('f9100000-0000-0000-0000-000000000004', 'new_hire', '2026-10-20', '2026-11-02');
  IF n <> 22 OR EXISTS (SELECT 1 FROM recruit.onboarding_task WHERE employment_id = 'f9100000-0000-0000-0000-000000000004' AND item_code = 'welcome_videos') THEN
    RAISE EXCEPTION 'FAIL 9b: % tasks (22 expected; extras that are off left out)', n;
  END IF;
  SELECT * INTO s FROM recruit.onboarding_task WHERE employment_id = 'f9100000-0000-0000-0000-000000000004' AND form_code = 'sin';
  IF s.legal_due_date <> '2026-11-05' OR s.due_date <> '2026-11-02' THEN
    RAISE EXCEPTION 'FAIL 9b: SIN due % (legal %); expected 2026-11-02 and 2026-11-05', s.due_date, s.legal_due_date;
  END IF;
  BEGIN
    UPDATE recruit.onboarding_task SET due_date = '2026-11-10' WHERE task_id = s.task_id;
    RAISE EXCEPTION 'FAIL 9c: SIN due after the legal date';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'DUE_AFTER_LEGAL_DATE%' THEN RAISE EXCEPTION 'FAIL 9c: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.onboarding_task SET status = 'waived' WHERE task_id = s.task_id;
    RAISE EXCEPTION 'FAIL 9d: the SIN waived';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LEGAL_TASK_CANNOT_BE_WAIVED%' THEN RAISE EXCEPTION 'FAIL 9d: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.onboarding_task SET due_date = '2026-11-03' WHERE employment_id = 'f9100000-0000-0000-0000-000000000004' AND item_code = 'td1_federal';
    RAISE EXCEPTION 'FAIL 9e: pre-boarding due after the first day';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PREBOARDING_DUE_AFTER_START%' THEN RAISE EXCEPTION 'FAIL 9e: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.onboarding_task SET status = 'done' WHERE employment_id = 'f9100000-0000-0000-0000-000000000004' AND item_code = 'td1_federal';
    RAISE EXCEPTION 'FAIL 9f: completed with nobody named';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'TASK_COMPLETION_UNSIGNED%' THEN RAISE EXCEPTION 'FAIL 9f: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE recruit.onboarding_task SET status = 'done', completed_at = now(), completed_by = '09a00000-0000-0000-0000-000000000007'
     WHERE employment_id = 'f9100000-0000-0000-0000-000000000004' AND item_code = 's87_declaration';
    RAISE EXCEPTION 'FAIL 9f: s. 87 question completed without an answer';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 9f: %', SQLERRM; END IF;
  END;
  UPDATE recruit.onboarding_task SET status = 'done', completed_at = now(), completed_by = '09a00000-0000-0000-0000-000000000007', answer = '{"claims":true}'
   WHERE employment_id = 'f9100000-0000-0000-0000-000000000004' AND item_code = 's87_declaration';
  IF NOT EXISTS (SELECT 1 FROM recruit.onboarding_task WHERE employment_id = 'f9100000-0000-0000-0000-000000000004'
                   AND item_code = 'record_s87_exemption' AND owner_kind = 'hr' AND due_event = 'first_pay' AND status = 'open') THEN
    RAISE EXCEPTION 'FAIL 9f: claiming s. 87 gave HR no task before the first pay';
  END IF;
  -- Buddies only with the buddy program on; several buddies, mentors and trainers; never the new hire themselves
  BEGIN
    INSERT INTO recruit.onboarding_support (tenant_id, employment_id, supporter_person_id, role, valid_period, chosen_by, from_suggestion)
      VALUES (t, 'f9100000-0000-0000-0000-000000000004', 'f9000000-0000-0000-0000-000000000005', 'buddy', '[2026-11-02,2027-02-02)', '09a00000-0000-0000-0000-000000000005', true);
    RAISE EXCEPTION 'FAIL 9g: buddy assigned with the program off';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FEATURE_OFF%' THEN RAISE EXCEPTION 'FAIL 9g: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id) VALUES
    (t, 'onboarding.extras', '{"buddyProgram":{"enabled":true,"required":false},"checkInSurveys":{"enabled":false,"required":false,"days":[]},"culturalTrack":{"enabled":false,"required":false},"welcomeVideos":{"enabled":false,"required":false}}',
     '[2000-01-01,)', gen_random_uuid());
  INSERT INTO recruit.onboarding_support (tenant_id, employment_id, supporter_person_id, role, scope_note, valid_period, chosen_by, from_suggestion) VALUES
    (t, 'f9100000-0000-0000-0000-000000000004', 'f9000000-0000-0000-0000-000000000005', 'buddy',   'Day-to-day questions', '[2026-11-02,2027-02-02)', '09a00000-0000-0000-0000-000000000005', true),
    (t, 'f9100000-0000-0000-0000-000000000004', 'f9000000-0000-0000-0000-000000000001', 'trainer', 'Client intake system', '[2026-11-02,2026-11-30)', '09a00000-0000-0000-0000-000000000005', false),
    (t, 'f9100000-0000-0000-0000-000000000004', 'f9000000-0000-0000-0000-000000000002', 'mentor',  'Case planning',        '[2026-11-16,2027-05-01)', '09a00000-0000-0000-0000-000000000005', false);
  BEGIN
    INSERT INTO recruit.onboarding_support (tenant_id, employment_id, supporter_person_id, role, valid_period, chosen_by, from_suggestion)
      VALUES (t, 'f9100000-0000-0000-0000-000000000004', 'f9000000-0000-0000-0000-000000000004', 'mentor', '[2026-11-02,2027-02-02)', '09a00000-0000-0000-0000-000000000005', false);
    RAISE EXCEPTION 'FAIL 9g: the new hire mentors themselves';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SUPPORT_SELF%' THEN RAISE EXCEPTION 'FAIL 9g: %', SQLERRM; END IF;
  END;
  IF NOT EXISTS (SELECT 1 FROM recruit.suggest_supporters('f9100000-0000-0000-0000-000000000004', '2026-11-02') x
                  WHERE x.person_id = 'f9000000-0000-0000-0000-000000000005' AND x.reason = 'same_org_unit') THEN
    RAISE EXCEPTION 'FAIL 9g: colleague in the same unit not suggested';
  END IF;
  -- Escalation on the days pre-filled at setup (owner 2 days before, manager 1 day after, HR 3 days after; Q46)
  SELECT x.next_level, x.notify INTO e FROM recruit.tasks_to_escalate(t, '2026-11-04') x
    JOIN recruit.onboarding_task k ON k.task_id = x.task_id WHERE k.item_code = 'td1_federal' AND k.employment_id = 'f9100000-0000-0000-0000-000000000004';
  IF e.next_level <> 2 OR e.notify <> 'owner_manager' THEN RAISE EXCEPTION 'FAIL 9h: TD1 two days overdue escalates to %', e; END IF;
  SELECT x.next_level, x.notify INTO e FROM recruit.tasks_to_escalate(t, '2026-11-04') x
    JOIN recruit.onboarding_task k ON k.task_id = x.task_id WHERE k.item_code = 'personnel_file' AND k.employment_id = 'f9100000-0000-0000-0000-000000000004';
  IF e.next_level <> 3 OR e.notify <> 'hr' THEN RAISE EXCEPTION 'FAIL 9h: personnel file three days overdue escalates to %', e; END IF;
  BEGIN
    INSERT INTO recruit.onboarding_plan_item (tenant_id, plan_id, item_code, seq, phase, kind, form_code, owner_kind, due_event, due_offset_days, required, name_en)
      SELECT t, plan_id, 'self_id_forced', 99, 'pre_boarding', 'form', 'self_identification', 'new_hire', 'start_date', 0, true, 'Self-identification'
        FROM recruit.onboarding_plan WHERE tenant_id = t AND code = 'core_new_hire';
    RAISE EXCEPTION 'FAIL 9i: self-identification made required';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 9a-i: plans that apply, 22 tasks, SIN within the legal date and never waived, pre-boarding by day one, s. 87 HR task, supporters, escalation on the organization''s days, self-identification voluntary';
END $$;

-- ---------------------------------------------------------------------------------
-- 10. Probation: calendar end, check-ins, reminders, leave near the end, extensions, the end date passing
-- ---------------------------------------------------------------------------------
INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, measure, required_amount, started_on, rule_source, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, '09ad0000-0000-0000-0000-000000000001', 'f9100000-0000-0000-0000-000000000001', 'employer', 'calendar_months', 3,
   '2026-01-05', 'setting:probation.non_union', '[2026-01-05,)', gen_random_uuid());
INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, agreement_id, bargaining_unit, assignment_id, measure, required_amount, counter_code, started_on, rule_source, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, '09ad0000-0000-0000-0000-000000000002', 'f9100000-0000-0000-0000-000000000002', 'agreement', 'CUPE-9', 'CUPE-9',
   '09200000-0000-0000-0000-000000000002', 'hours_worked', 600, 'PROB_HOURS', '2026-02-01', 'agreement:CUPE-9:7.1', '[2026-02-01,)', gen_random_uuid());
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; d date[]; c record; r uuid; n int;
BEGIN
  IF core.probation_calendar_end('09ad0000-0000-0000-0000-000000000001', '2026-02-01') <> '2026-04-04' THEN
    RAISE EXCEPTION 'FAIL 10a: 3 months from 5 January end on %', core.probation_calendar_end('09ad0000-0000-0000-0000-000000000001', '2026-02-01');
  END IF;
  d := ARRAY(SELECT due_on FROM core.probation_check_in_dates('09ad0000-0000-0000-0000-000000000001', '2026-02-01') ORDER BY 1);
  IF d <> ARRAY['2026-02-04','2026-03-06','2026-03-21']::date[] THEN RAISE EXCEPTION 'FAIL 10b: check-ins on %', d; END IF;
  IF NOT EXISTS (SELECT 1 FROM core.probation_reminders_due(t, '2026-03-30') WHERE probation_id = '09ad0000-0000-0000-0000-000000000001' AND days_left = 5)
     OR EXISTS (SELECT 1 FROM core.probation_reminders_due(t, '2026-03-28') WHERE probation_id = '09ad0000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL 10c: reminders not on the organization''s days';
  END IF;
  SELECT * INTO c FROM core.probation_leave_caution('f9100000-0000-0000-0000-000000000001', '[2026-03-30,2026-04-02]', '2026-03-01');
  IF c.probation_id IS NULL OR c.ends_on <> '2026-04-04' OR c.holidays <> ARRAY['2026-04-03']::date[] THEN
    RAISE EXCEPTION 'FAIL 10d: leave near the end not cautioned with the holiday: %', c;
  END IF;
  IF EXISTS (SELECT 1 FROM core.probation_leave_caution('f9100000-0000-0000-0000-000000000001', '[2026-02-10,2026-02-12]', '2026-02-01')) THEN
    RAISE EXCEPTION 'FAIL 10d: a February leave cautioned';
  END IF;
  BEGIN
    PERFORM core.probation_calendar_end('09ad0000-0000-0000-0000-000000000002', '2026-03-01');
    RAISE EXCEPTION 'FAIL 10e: a probation counted in hours given a calendar end';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PROBATION_MEASURE_COUNTED%' THEN RAISE EXCEPTION 'FAIL 10e: %', SQLERRM; END IF;
  END;
  IF (SELECT count(*) FROM core.probation_leave_caution('f9100000-0000-0000-0000-000000000002', '[2026-03-02,2026-03-03]', '2026-03-01') x WHERE x.ends_on IS NULL) <> 1 THEN
    RAISE EXCEPTION 'FAIL 10e: leave during an hours probation not cautioned';
  END IF;

  -- Extension: approved through the route, the employee told before the end date, the law''s notice threshold acknowledged
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'probation.non_union_extension_max', '{"amount":1,"measure":"calendar_months"}', '[2000-01-01,)', gen_random_uuid());
  SELECT route_id INTO r FROM platform.workflow_route WHERE tenant_id = t AND code = 'probation_extension';
  INSERT INTO core.probation_extension (tenant_id, extension_id, probation_id, amount, reason, requested_by, route_id, jurisdiction, union_notice_required, status, change_set_id)
    VALUES (t, '09ae0000-0000-0000-0000-000000000001', '09ad0000-0000-0000-0000-000000000001', 1, 'More time to assess client reports',
            '09a00000-0000-0000-0000-000000000005', r, 'ON', false, 'proposed', gen_random_uuid());
  BEGIN
    UPDATE core.probation_extension SET status = 'approved' WHERE extension_id = '09ae0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 10f: extension approved with no approvals';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 10f: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'probation_extension', '09ae0000-0000-0000-0000-000000000001', 1, 'approved', '09a00000-0000-0000-0000-000000000002', clock_timestamp(), 'hr');
  UPDATE core.probation_extension SET status = 'approved' WHERE extension_id = '09ae0000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE core.probation_extension SET status = 'in_effect' WHERE extension_id = '09ae0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 10f: extension in effect before the employee was told';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'EXTENSION_NOT_COMMUNICATED%' THEN RAISE EXCEPTION 'FAIL 10f: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE core.probation_extension SET status = 'in_effect', employee_notified_at = '2026-04-10 10:00-04', employee_notice_method = 'letter'
     WHERE extension_id = '09ae0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 10f: extension told after the end date';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'EXTENSION_AFTER_END%' THEN RAISE EXCEPTION 'FAIL 10f: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE core.probation_extension SET status = 'in_effect', employee_notified_at = '2026-03-20 10:00-04', employee_notice_method = 'in_person'
     WHERE extension_id = '09ae0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 10f: extension past Ontario''s 3-month notice threshold without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 10f: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by)
    VALUES (t, 'probation.extension_past_notice_threshold', 'probation_extension', '09ae0000-0000-0000-0000-000000000001', 'shown', 'en', '09a00000-0000-0000-0000-000000000005');
  UPDATE core.probation_extension SET status = 'in_effect', employee_notified_at = '2026-03-20 10:00-04', employee_notice_method = 'in_person'
   WHERE extension_id = '09ae0000-0000-0000-0000-000000000001';
  IF (SELECT status || ':' || extended_by FROM core.probation WHERE probation_id = '09ad0000-0000-0000-0000-000000000001' AND upper_inf(sys_period)) <> 'extended:1.00'
     OR core.probation_calendar_end('09ad0000-0000-0000-0000-000000000001', '2026-04-01') <> '2026-05-04' THEN
    RAISE EXCEPTION 'FAIL 10f: extension not applied to the probation';
  END IF;
  INSERT INTO core.probation_extension (tenant_id, extension_id, probation_id, amount, reason, requested_by, route_id, jurisdiction, union_notice_required, status, change_set_id)
    VALUES (t, '09ae0000-0000-0000-0000-000000000002', '09ad0000-0000-0000-0000-000000000001', 1, 'Still not sure',
            '09a00000-0000-0000-0000-000000000005', r, 'ON', false, 'proposed', gen_random_uuid());
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'probation_extension', '09ae0000-0000-0000-0000-000000000002', 1, 'approved', '09a00000-0000-0000-0000-000000000002', clock_timestamp(), 'hr');
  UPDATE core.probation_extension SET status = 'approved' WHERE extension_id = '09ae0000-0000-0000-0000-000000000002';
  BEGIN
    UPDATE core.probation_extension SET status = 'in_effect', employee_notified_at = '2026-04-20 10:00-04', employee_notice_method = 'letter'
     WHERE extension_id = '09ae0000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 10g: extended past the organization''s maximum';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'EXTENSION_ABOVE_MAXIMUM%' THEN RAISE EXCEPTION 'FAIL 10g: %', SQLERRM; END IF;
  END;
  -- The end date passes with no decision: passed, and HR told (FB-034)
  SELECT count(*) INTO n FROM core.close_lapsed_probations(t, '2026-05-10', gen_random_uuid());
  IF n <> 1 OR (SELECT status FROM core.probation WHERE probation_id = '09ad0000-0000-0000-0000-000000000001' AND upper_inf(sys_period)) <> 'passed'
     OR (SELECT reason FROM core.probation WHERE probation_id = '09ad0000-0000-0000-0000-000000000001' AND upper_inf(sys_period)) NOT LIKE '%FB-034%'
     OR (SELECT outcome_on FROM core.probation WHERE probation_id = '09ad0000-0000-0000-0000-000000000001' AND upper_inf(sys_period)) <> '2026-05-04' THEN
    RAISE EXCEPTION 'FAIL 10h: lapsed probation not closed as passed (% closed)', n;
  END IF;
  IF (SELECT count(*) FROM core.close_lapsed_probations(t, '2026-05-11', gen_random_uuid())) <> 0 THEN RAISE EXCEPTION 'FAIL 10h: closed twice'; END IF;
  RAISE NOTICE 'PASS 10a-h: calendar end, check-ins, reminders, leave near the end with holidays, counted probations, extension rules, the end date passing (FB-034)';
END $$;

-- ---------------------------------------------------------------------------------
-- 11. Open cases before an ending: HR reviews and acknowledges; a respondent sees only that HR must review
-- ---------------------------------------------------------------------------------
INSERT INTO core.change_reason (tenant_id, code, name_en, category) VALUES (current_setting('app.tenant_id')::uuid, 'TERM', 'Termination', 'termination');
INSERT INTO compliance.case_file (tenant_id, case_id, kind, subject_employment_id, status, opened_on)
  VALUES (current_setting('app.tenant_id')::uuid, '09af0000-0000-0000-0000-000000000001', 'complaint', 'f9100000-0000-0000-0000-000000000002', 'open', '2026-09-01');
INSERT INTO compliance.case_party (tenant_id, case_id, employment_id, role)
  VALUES (current_setting('app.tenant_id')::uuid, '09af0000-0000-0000-0000-000000000001', 'f9100000-0000-0000-0000-000000000003', 'respondent');
INSERT INTO platform.change_set (tenant_id, change_set_id, number, kind, reason_code, effective_date, source, status, requested_by)
  VALUES (current_setting('app.tenant_id')::uuid, '09ba0000-0000-0000-0000-000000000001', 901, 'separation', 'TERM', '2026-11-15', 'ui_form', 'pending_approval',
          '09a00000-0000-0000-0000-000000000005');
INSERT INTO platform.change_set_operation (tenant_id, change_set_id, seq, op, target_type, target_id, payload)
  VALUES (current_setting('app.tenant_id')::uuid, '09ba0000-0000-0000-0000-000000000001', 1, 'employment.end', 'employment', 'f9100000-0000-0000-0000-000000000002', '{}');
INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
  VALUES (current_setting('app.tenant_id')::uuid, 'change_set', '09ba0000-0000-0000-0000-000000000001', 1, 'approved', '09a00000-0000-0000-0000-000000000002', now(), 'hr');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    UPDATE platform.change_set SET status = 'approved' WHERE change_set_id = '09ba0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 11a: employment ended with an open complaint and no HR review';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'OPEN_CASES_NOT_REVIEWED%' THEN RAISE EXCEPTION 'FAIL 11a: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'endings.open_cases', 'change_set', '09ba0000-0000-0000-0000-000000000001', 'shown', 'en', '09a00000-0000-0000-0000-000000000003', 'Seen');
  BEGIN
    UPDATE platform.change_set SET status = 'approved' WHERE change_set_id = '09ba0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 11b: acknowledged by someone who is not an HR approver of the change';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'OPEN_CASES_NOT_REVIEWED%' THEN RAISE EXCEPTION 'FAIL 11b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'endings.open_cases', 'change_set', '09ba0000-0000-0000-0000-000000000001', 'shown', 'en', '09a00000-0000-0000-0000-000000000002',
            'Complaint reviewed with counsel; the ending is for documented attendance reasons that predate it');
  UPDATE platform.change_set SET status = 'approved' WHERE change_set_id = '09ba0000-0000-0000-0000-000000000001';
  IF NOT core.viewer_is_case_respondent('f9100000-0000-0000-0000-000000000002', 'f9000000-0000-0000-0000-000000000003', '2026-11-01')
     OR core.viewer_is_case_respondent('f9100000-0000-0000-0000-000000000002', 'f9000000-0000-0000-0000-000000000001', '2026-11-01') THEN
    RAISE EXCEPTION 'FAIL 11c: respondent not recognized';
  END IF;
  INSERT INTO timeleave.leave_request (tenant_id, leave_request_id, employment_id, leave_type_code, period, hours, status)
    VALUES (t, gen_random_uuid(), 'f9100000-0000-0000-0000-000000000001', 'VAC', '[2026-12-21 00:00-05,2026-12-24 00:00-05)', 22.5, 'requested');
  IF NOT EXISTS (SELECT 1 FROM core.open_matters('f9100000-0000-0000-0000-000000000001', '2026-11-01') WHERE source = 'leave') THEN
    RAISE EXCEPTION 'FAIL 11d: a requested leave not counted as an open matter';
  END IF;
  -- A case closed within the look-back (12 months by default) still counts; the organization can shorten it (Q47)
  INSERT INTO compliance.case_file (tenant_id, case_id, kind, subject_employment_id, status, opened_on, closed_on)
    VALUES (t, '09af0000-0000-0000-0000-000000000002', 'grievance', 'f9100000-0000-0000-0000-000000000005', 'closed', '2026-03-01', '2026-08-01');
  IF NOT EXISTS (SELECT 1 FROM core.open_matters('f9100000-0000-0000-0000-000000000005', '2026-11-01') WHERE source = 'closed_case') THEN
    RAISE EXCEPTION 'FAIL 11e: a grievance closed three months ago not counted';
  END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'endings.closed_case_lookback_months', '2', '[2000-01-01,)', gen_random_uuid());
  IF EXISTS (SELECT 1 FROM core.open_matters('f9100000-0000-0000-0000-000000000005', '2026-11-01') WHERE source = 'closed_case') THEN
    RAISE EXCEPTION 'FAIL 11e: a case closed before the organization''s look-back still counted';
  END IF;
  RAISE NOTICE 'PASS 11a-e: an ending waits for the HR approver''s review of open and recently closed cases; respondents see only that HR must review; leave counts';
END $$;

-- ---------------------------------------------------------------------------------
-- 12. Status conversion: thresholds only when set; an agreement's conversion declined only with the caution
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r uuid;
BEGIN
  BEGIN
    INSERT INTO core.status_conversion_request (tenant_id, employment_id, assignment_id, to_employment_type, started_by, rule_source, status)
      VALUES (t, 'f9100000-0000-0000-0000-000000000005', '09200000-0000-0000-0000-000000000005', 'permanent', 'threshold', 'threshold#1', 'flagged');
    RAISE EXCEPTION 'FAIL 12a: flagged by a threshold the organization has not set';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CONVERSION_THRESHOLDS_OFF%' THEN RAISE EXCEPTION 'FAIL 12a: %', SQLERRM; END IF;
  END;
  INSERT INTO core.status_conversion_request (tenant_id, request_id, employment_id, assignment_id, to_employment_type, started_by, rule_source, status)
    VALUES (t, '09bb0000-0000-0000-0000-000000000001', 'f9100000-0000-0000-0000-000000000005', '09200000-0000-0000-0000-000000000005', 'permanent',
            'agreement', 'agreement:CUPE-9:14.3', 'flagged');
  BEGIN
    UPDATE core.status_conversion_request SET status = 'declined', reason = 'Budget' WHERE request_id = '09bb0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 12b: a conversion the agreement requires declined without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 12b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'conversion.agreement_requires', 'status_conversion', '09bb0000-0000-0000-0000-000000000001', 'shown', 'en', '09a00000-0000-0000-0000-000000000002',
            'Grant ends in March; union agreed to defer by letter');
  UPDATE core.status_conversion_request SET status = 'declined', reason = 'Deferred by agreement with the union' WHERE request_id = '09bb0000-0000-0000-0000-000000000001';
  SELECT route_id INTO r FROM platform.workflow_route WHERE tenant_id = t AND code = 'status_conversion';
  INSERT INTO core.status_conversion_request (tenant_id, request_id, employment_id, assignment_id, to_employment_type, started_by, requested_by, route_id, status)
    VALUES (t, '09bb0000-0000-0000-0000-000000000002', 'f9100000-0000-0000-0000-000000000005', '09200000-0000-0000-0000-000000000005', 'permanent',
            'manager_request', '09a00000-0000-0000-0000-000000000005', r, 'requested');
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'status_conversion', '09bb0000-0000-0000-0000-000000000002', 1, 'approved', '09a00000-0000-0000-0000-000000000002', clock_timestamp(), 'hr');
  BEGIN
    UPDATE core.status_conversion_request SET status = 'approved' WHERE request_id = '09bb0000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 12c: conversion approved without the budget step';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 12c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'status_conversion', '09bb0000-0000-0000-0000-000000000002', 2, 'approved', '09a00000-0000-0000-0000-000000000004', clock_timestamp(), 'finance');
  UPDATE core.status_conversion_request SET status = 'approved' WHERE request_id = '09bb0000-0000-0000-0000-000000000002';
  RAISE NOTICE 'PASS 12a-c: thresholds only when set, agreement conversions declined only with the caution, conversion route complete';
END $$;

-- ---------------------------------------------------------------------------------
-- 13. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', '92222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM recruit.posting) <> 0 OR (SELECT count(*) FROM recruit.offer) <> 0
     OR (SELECT count(*) FROM platform.caution_acknowledgement) <> 0 OR (SELECT count(*) FROM core.probation_extension) <> 0
     OR (SELECT count(*) FROM platform.workflow_route) <> (SELECT count(*) FROM ref.workflow_route_starter) THEN
    RAISE EXCEPTION 'FAIL 13: another organization''s recruitment data is visible';
  END IF;
  RAISE NOTICE 'PASS 13: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0009_smoke: all checks passed'
