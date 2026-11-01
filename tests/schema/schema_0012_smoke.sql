-- Smoke test for schema/0012_benefits_decisions.sql (docs/26): the new settings, plan setup (waiting period, late
-- enrolment, life event window, hours test), dependents' age-out notices, coordination of benefits and the governing
-- agreement decided by HR, statutory leave contributions, rules for other unpaid leaves, opt-outs with proof, premium
-- adjustments for past months, carrier invoices through the route, advisor capabilities, RLS and tenant isolation.
-- Run after every migration, 0001 to 0012 (CI, after the 0011 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0012_smoke.sql
-- It does not depend on today's date. It inserts test rows; run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit, benefits TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit, benefits TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ref, platform, core, payroll, timeleave, talent, recruit, comp, compliance, benefits TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('c1111111-1111-1111-1111-111111111111', 'Benefits Test Society'),
  ('c2222222-2222-2222-2222-222222222222', 'Other Organization')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', 'c1111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, the starter route, advisor capabilities, RLS
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/26%') <> 7
     OR (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/26%' AND decision_status = 'pending') <> 2 THEN
    RAISE EXCEPTION 'FAIL 1a: expected 7 settings from docs/26, 2 of them chosen at setup';
  END IF;
  IF platform.setting_text(t, 'benefits.open_enrolment_no_action') <> 'keep_current'
     OR platform.setting_number(t, 'benefits.dependent_ageout_notice_days') <> 60
     OR platform.setting(t, 'benefits.late_enrolment_starter') ->> 'ltd' <> 'eoi'
     OR (platform.setting(t, 'benefits.statutory_leave_contributions') ->> 'employerPays')::boolean THEN
    RAISE EXCEPTION 'FAIL 1b: decided defaults not in place';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM platform.workflow_route WHERE tenant_id = t AND code = 'carrier_invoice')
     OR (SELECT count(*) FROM ref.provider_capability WHERE capability IN ('benefits_plan_costs','benefits_individual_data')) <> 2 THEN
    RAISE EXCEPTION 'FAIL 1c: starter route or advisor capabilities missing';
  END IF;
  SELECT string_agg(c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'benefits' AND c.relkind = 'r'
     AND c.relname IN ('dependent','governing_agreement','leave_contribution_choice','leave_rule','opt_out','carrier_invoice')
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1d: RLS missing on %', bad; END IF;
  RAISE NOTICE 'PASS 1a-d: settings, decided defaults, carrier invoice route, advisor capabilities, RLS';
END $$;

-- Fixtures: one employer, two agreements, one person in two positions (one under each), staff
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  (current_setting('app.tenant_id')::uuid, '0ca00000-0000-0000-0000-000000000001', 'benadmin', 'benadmin@example.test'),
  (current_setting('app.tenant_id')::uuid, '0ca00000-0000-0000-0000-000000000002', 'hr', 'hr@example.test'),
  (current_setting('app.tenant_id')::uuid, '0ca00000-0000-0000-0000-000000000003', 'fin', 'fin@example.test'),
  (current_setting('app.tenant_id')::uuid, '0ca00000-0000-0000-0000-000000000004', 'emp', 'emp@example.test');
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, '0c100000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, '0c200000-0000-0000-0000-000000000001');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction) VALUES
  (current_setting('app.tenant_id')::uuid, '0c200000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Centre', '1 Main St', 'Victoria', 'BC', 'V8W 1A1', 'America/Vancouver', 'BC');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, '0c300000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, '0c400000-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, '0c400000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'CW', 'Care Worker', 'Préposé aux soins');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, '0c500000-0000-0000-0000-000000000001', 'P-FT'),
  (current_setting('app.tenant_id')::uuid, '0c500000-0000-0000-0000-000000000002', 'P-PT');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0c300000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0c100000-0000-0000-0000-000000000001', 'DEPT', 'CARE', 'Care', '0c500000-0000-0000-0000-000000000001');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0c500000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0c400000-0000-0000-0000-000000000001', '0c300000-0000-0000-0000-000000000001', '0c200000-0000-0000-0000-000000000001', NULL, 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0c500000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '0c400000-0000-0000-0000-000000000001', '0c300000-0000-0000-0000-000000000001', '0c200000-0000-0000-0000-000000000001', '0c500000-0000-0000-0000-000000000001', 0.5, 'casual', 'active');
INSERT INTO core.agreement (tenant_id, agreement_id, name, union_name, jurisdiction, status, bargaining_employer_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'FT', 'Full-time agreement', 'Union A', 'BC', 'in_force', '0c100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'PT', 'Part-time agreement', 'Union B', 'BC', 'in_force', '0c100000-0000-0000-0000-000000000001');
INSERT INTO core.person (tenant_id, person_id) VALUES (current_setting('app.tenant_id')::uuid, '0c600000-0000-0000-0000-000000000001');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0c700000-0000-0000-0000-000000000001', '0c600000-0000-0000-0000-000000000001', '0c100000-0000-0000-0000-000000000001');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0c800000-0000-0000-0000-000000000001', '0c700000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0c800000-0000-0000-0000-000000000002', '0c700000-0000-0000-0000-000000000001');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type, agreement_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0c800000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), '0c500000-0000-0000-0000-000000000001', '0c300000-0000-0000-0000-000000000001', '0c200000-0000-0000-0000-000000000001', 0.6, true, 'permanent', 'FT'),
  (current_setting('app.tenant_id')::uuid, '0c800000-0000-0000-0000-000000000002', '[2026-06-01,)', gen_random_uuid(), '0c500000-0000-0000-0000-000000000002', '0c300000-0000-0000-0000-000000000001', '0c200000-0000-0000-0000-000000000001', 0.4, false, 'casual', 'PT');
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by) VALUES
  (current_setting('app.tenant_id')::uuid, '0cd00000-0000-0000-0000-000000000001', 'person', '0c600000-0000-0000-0000-000000000001', 'other_coverage_proof', 'restricted', 'benefits', 'test/proof.pdf', 'x', 'application/pdf', '0ca00000-0000-0000-0000-000000000001');
INSERT INTO timeleave.leave_type (tenant_id, leave_type_code, name_en, name_fr, category, statutory, jurisdictions, paid_percent, job_protected, reason_restricted, roe_trigger) VALUES
  (current_setting('app.tenant_id')::uuid, 'PARENTAL', 'Parental leave', 'Congé parental', 'parental', true, ARRAY['BC']::ref.jurisdiction_code[], 0, true, false, true),
  (current_setting('app.tenant_id')::uuid, 'PERSONAL_UNPAID', 'Personal unpaid leave', 'Congé personnel non payé', 'personal', false, ARRAY['BC']::ref.jurisdiction_code[], 0, false, false, false);

-- ---------------------------------------------------------------------------------
-- 2. Plan setup: the organization states the waiting period and late-enrolment rule; the life event window
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; p benefits.plan;
BEGIN
  BEGIN
    INSERT INTO benefits.plan (tenant_id, code, kind, eligibility) VALUES (t, 'LIFE', 'life', '{}');
    RAISE EXCEPTION 'FAIL 2a: plan saved without its waiting period';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO benefits.plan (tenant_id, code, kind, eligibility, waiting_rule) VALUES (t, 'LIFE', 'life', '{}', '{"kind":"weeks","n":4}');
    RAISE EXCEPTION 'FAIL 2a: unknown waiting rule accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'WAITING_RULE_INVALID%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  INSERT INTO benefits.plan (tenant_id, plan_id, code, kind, eligibility, waiting_rule)
    VALUES (t, '0c900000-0000-0000-0000-000000000001', 'LIFE', 'life', '{}', '{"kind":"months","n":3}') RETURNING * INTO p;
  IF p.late_enrolment <> 'eoi' THEN RAISE EXCEPTION 'FAIL 2b: life plan late enrolment %', p.late_enrolment; END IF;
  BEGIN
    INSERT INTO benefits.plan (tenant_id, code, kind, eligibility, waiting_rule) VALUES (t, 'HEALTH', 'health', '{}', '{"kind":"none"}');
    RAISE EXCEPTION 'FAIL 2b: health plan saved without its late-enrolment rule';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO benefits.plan (tenant_id, code, kind, eligibility, waiting_rule, late_enrolment, hours_test)
      VALUES (t, 'HEALTH', 'health', '{}', '{"kind":"none"}', 'next_open_enrolment', '{"lookbackWeeks":13}');
    RAISE EXCEPTION 'FAIL 2c: incomplete hours test accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO benefits.plan (tenant_id, plan_id, code, kind, eligibility, eligibility_scope, waiting_rule, late_enrolment, hours_test) VALUES
    (t, '0c900000-0000-0000-0000-000000000002', 'HEALTH', 'health', '{}', 'employer', '{"kind":"first_of_month_after","n":3}', 'next_open_enrolment',
     '{"lookbackWeeks":13,"retestEvery":"quarter","minAvgHours":20}'),
    (t, '0c900000-0000-0000-0000-000000000003', 'TRUST-PT', 'health', '{}', 'employer', '{"kind":"hours","n":480}', 'hr_decides', NULL);
  UPDATE benefits.plan SET life_event_window_days = 45 WHERE plan_id = '0c900000-0000-0000-0000-000000000003';
  IF benefits.life_event_window('0c900000-0000-0000-0000-000000000003', '2027-01-10', '0c100000-0000-0000-0000-000000000001') <> 45 THEN
    RAISE EXCEPTION 'FAIL 2d: plan''s own window not used';
  END IF;
  BEGIN
    PERFORM benefits.life_event_window('0c900000-0000-0000-0000-000000000002', '2027-01-10', '0c100000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL 2d: life event window assumed before the organization chose one';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'benefits.life_event_window_days', 'tenant', NULL, '31', '[2026-01-01,)', gen_random_uuid());
  IF benefits.life_event_window('0c900000-0000-0000-0000-000000000002', '2027-01-10', '0c100000-0000-0000-0000-000000000001') <> 31 THEN
    RAISE EXCEPTION 'FAIL 2d: organization''s window not used';
  END IF;
  RAISE NOTICE 'PASS 2a-d: plans state their waiting period and late-enrolment rule; life events use the plan''s or the organization''s window';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Dependents' age-out notice; 4. coordination of benefits decided by HR; 5. the governing agreement
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; n int; g text;
BEGIN
  INSERT INTO benefits.dependent (tenant_id, employment_id, relationship, given_name, family_name, birth_date, disabled, valid_period)
    VALUES (t, '0c700000-0000-0000-0000-000000000001', 'child', 'Sam', 'Test', '2006-06-15', false, '[2026-01-01,)');
  IF benefits.ageout_notice_on(t, '0c100000-0000-0000-0000-000000000001', '2027-06-15') <> '2027-04-16' THEN
    RAISE EXCEPTION 'FAIL 3: age-out notice on %', benefits.ageout_notice_on(t, '0c100000-0000-0000-0000-000000000001', '2027-06-15');
  END IF;
  RAISE NOTICE 'PASS 3: the employee and HR are told 60 days before a dependent ages out';

  INSERT INTO benefits.enrolment (tenant_id, enrolment_id, employment_id, plan_id, coverage_level, valid_period, employee_cost_per_period, employer_cost_per_period, source) VALUES
    (t, '0c910000-0000-0000-0000-000000000001', '0c700000-0000-0000-0000-000000000001', '0c900000-0000-0000-0000-000000000002', 'family', '[2026-04-01,)', 30, 150, 'employee'),
    (t, '0c910000-0000-0000-0000-000000000002', '0c700000-0000-0000-0000-000000000001', '0c900000-0000-0000-0000-000000000003', 'single', '[2026-09-01,)', 0, 40, 'automatic');
  SELECT count(*) INTO n FROM benefits.cob_decisions_needed(t, '2026-10-01');
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL 4a: % people waiting for HR''s order, expected 1', n; END IF;
  BEGIN
    UPDATE benefits.enrolment SET cob_rank = 1 WHERE enrolment_id = '0c910000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4b: order set without HR''s decision and reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  UPDATE benefits.enrolment SET cob_rank = 1, cob_decided_by = '0ca00000-0000-0000-0000-000000000002', cob_decided_at = now(),
         cob_reason = 'Family coverage is on the full-time plan; the trust plan pays second'
   WHERE enrolment_id = '0c910000-0000-0000-0000-000000000001';
  UPDATE benefits.enrolment SET cob_rank = 2, cob_decided_by = '0ca00000-0000-0000-0000-000000000002', cob_decided_at = now(),
         cob_reason = 'Family coverage is on the full-time plan; the trust plan pays second'
   WHERE enrolment_id = '0c910000-0000-0000-0000-000000000002';
  IF EXISTS (SELECT 1 FROM benefits.cob_decisions_needed(t, '2026-10-01')) THEN RAISE EXCEPTION 'FAIL 4c: still waiting after HR decided'; END IF;
  RAISE NOTICE 'PASS 4a-c: two plans of one kind wait for HR''s order, recorded with a reason';

  IF benefits.governing_agreement_for('0c700000-0000-0000-0000-000000000001', '2026-03-01') <> 'FT' THEN
    RAISE EXCEPTION 'FAIL 5a: one agreement before June';
  END IF;
  BEGIN
    PERFORM benefits.governing_agreement_for('0c700000-0000-0000-0000-000000000001', '2026-10-01');
    RAISE EXCEPTION 'FAIL 5b: governing agreement chosen without HR';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'GOVERNING_AGREEMENT_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 5b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO benefits.governing_agreement (tenant_id, employment_id, agreement_id, valid_period, decided_by, reason)
      VALUES (t, '0c700000-0000-0000-0000-000000000001', 'PT', '[2026-06-01,)', '0ca00000-0000-0000-0000-000000000002', ' ');
    RAISE EXCEPTION 'FAIL 5c: HR''s choice without a reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO benefits.governing_agreement (tenant_id, employment_id, agreement_id, valid_period, decided_by, reason)
    VALUES (t, '0c700000-0000-0000-0000-000000000001', 'FT', '[2026-06-01,)', '0ca00000-0000-0000-0000-000000000002',
            'Benefit class follows the full-time position the employee was hired into');
  g := benefits.governing_agreement_for('0c700000-0000-0000-0000-000000000001', '2026-10-01');
  IF g <> 'FT' THEN RAISE EXCEPTION 'FAIL 5d: governing agreement %', g; END IF;
  RAISE NOTICE 'PASS 5a-d: with two agreements, HR chooses the governing one and records why; CanDo never picks';
END $$;

-- ---------------------------------------------------------------------------------
-- 6. Leaves: statutory leave contributions; the organization's rules for other unpaid leaves
-- ---------------------------------------------------------------------------------
INSERT INTO timeleave.leave_request (tenant_id, leave_request_id, employment_id, leave_type_code, period, hours, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0c0a0000-0000-0000-0000-000000000001', '0c700000-0000-0000-0000-000000000001', 'PARENTAL', '[2027-02-01 00:00-08,2027-12-01 00:00-08)', 1500, 'approved'),
  (current_setting('app.tenant_id')::uuid, '0c0a0000-0000-0000-0000-000000000002', '0c700000-0000-0000-0000-000000000001', 'PARENTAL', '[2028-02-01 00:00-08,2028-04-01 00:00-08)', 300, 'approved');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r benefits.leave_rule;
BEGIN
  BEGIN
    INSERT INTO benefits.leave_contribution_choice (tenant_id, leave_request_id, method, chosen_by)
      VALUES (t, '0c0a0000-0000-0000-0000-000000000001', 'employer_pays', '0ca00000-0000-0000-0000-000000000004');
    RAISE EXCEPTION 'FAIL 6a: employer pays where the organization does not';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 6a: %', SQLERRM; END IF;
  END;
  INSERT INTO benefits.leave_contribution_choice (tenant_id, leave_request_id, method, chosen_by)
    VALUES (t, '0c0a0000-0000-0000-0000-000000000001', 'arrears_on_return', '0ca00000-0000-0000-0000-000000000004');
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'benefits.statutory_leave_contributions', 'legal_entity', '0c100000-0000-0000-0000-000000000001',
            '{"methods":["prepay"],"employerPays":true}', '[2028-01-01,)', gen_random_uuid());
  INSERT INTO benefits.leave_contribution_choice (tenant_id, leave_request_id, method, chosen_by)
    VALUES (t, '0c0a0000-0000-0000-0000-000000000002', 'employer_pays', '0ca00000-0000-0000-0000-000000000002');
  RAISE NOTICE 'PASS 6a: the employee chooses among the ways the organization offers; the organization can pay instead';

  BEGIN
    PERFORM benefits.leave_rule_for('0c800000-0000-0000-0000-000000000001', 'PARENTAL', 'health', '2027-03-01');
    RAISE EXCEPTION 'FAIL 6b: a rule applied to a statutory leave';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'STATUTORY_LEAVE_FOLLOWS_LAW%' THEN RAISE EXCEPTION 'FAIL 6b: %', SQLERRM; END IF;
  END;
  BEGIN
    PERFORM benefits.leave_rule_for('0c800000-0000-0000-0000-000000000001', 'PERSONAL_UNPAID', 'health', '2027-03-01');
    RAISE EXCEPTION 'FAIL 6c: unpaid leave handled without the organization''s rule';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LEAVE_BENEFIT_RULE_MISSING%' THEN RAISE EXCEPTION 'FAIL 6c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO benefits.leave_rule (tenant_id, code, name_en, applies_to, action, priority, status)
      VALUES (t, 'BAD', 'Employer pays, no period', '{}', 'continue_employer_paid', 99, 'active');
    RAISE EXCEPTION 'FAIL 6d: employer-paid continuation without its period';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO benefits.leave_rule (tenant_id, code, name_en, applies_to, action, employer_paid_months, then_action, priority, status) VALUES
    (t, 'PERM-PERS', 'Permanent staff: employer pays 3 months, then the employee', '{"leaveTypes":["PERSONAL_UNPAID"],"employmentTypes":["permanent"]}',
     'continue_employer_paid', 3, 'continue_employee_cost', 10, 'active'),
    (t, 'OTHER', 'Everyone else: suspended', '{}', 'suspend', NULL, NULL, 20, 'active');
  r := benefits.leave_rule_for('0c800000-0000-0000-0000-000000000001', 'PERSONAL_UNPAID', 'health', '2027-03-01');
  IF r.code <> 'PERM-PERS' THEN RAISE EXCEPTION 'FAIL 6e: permanent position got %', r.code; END IF;
  r := benefits.leave_rule_for('0c800000-0000-0000-0000-000000000002', 'PERSONAL_UNPAID', 'health', '2027-03-01');
  IF r.code <> 'OTHER' THEN RAISE EXCEPTION 'FAIL 6e: casual position got %', r.code; END IF;
  RAISE NOTICE 'PASS 6b-e: statutory leaves follow the law; other unpaid leaves follow the organization''s rule for the type and class';
END $$;

-- ---------------------------------------------------------------------------------
-- 7. Opt-outs need proof; coverage when employment ends; 8. premium adjustments for past months; 9. carrier invoices
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r uuid;
BEGIN
  BEGIN
    INSERT INTO benefits.opt_out (tenant_id, employment_id, plan_kind, other_coverage, valid_period, recorded_by)
      VALUES (t, '0c700000-0000-0000-0000-000000000001', 'dental', 'Spouse''s plan', '[2027-01-01,)', '0ca00000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL 7: opt-out without proof';
  EXCEPTION WHEN not_null_violation THEN NULL;
  END;
  INSERT INTO benefits.opt_out (tenant_id, employment_id, plan_kind, other_coverage, proof_document_id, valid_period, recorded_by)
    VALUES (t, '0c700000-0000-0000-0000-000000000001', 'dental', 'Spouse''s plan', '0cd00000-0000-0000-0000-000000000001', '[2027-01-01,)', '0ca00000-0000-0000-0000-000000000001');
  RAISE NOTICE 'PASS 7a: opting out of dental needs proof of the other coverage';

  INSERT INTO benefits.change_rule (tenant_id, rule_id, code, name_en, priority, match, action, until_rule, offer_conversion, valid_period, change_set_id)
    VALUES (t, gen_random_uuid(), 'P10', 'Permanent staff ended by the employer: to the end of severance', 10,
            '{"employmentContinues":false,"employmentTypes":["permanent"]}', 'continue_until', '{"kind":"end_of_severance"}', false, '[2026-01-01,)', gen_random_uuid());
  BEGIN
    INSERT INTO benefits.change_rule (tenant_id, rule_id, code, name_en, priority, match, action, until_rule, offer_conversion, valid_period, change_set_id)
      VALUES (t, gen_random_uuid(), 'P11', 'Unknown date rule', 11, '{}', 'continue_until', '{"kind":"end_of_benefit_year"}', false, '[2026-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 7b: unknown date rule accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 7b: a class rule can keep coverage to the end of the severance period';

  INSERT INTO core.end_reason (tenant_id, code, name_en, category, employer_initiated) VALUES (t, 'ELIM', 'Position eliminated', 'position_eliminated', true);
  INSERT INTO benefits.change_decision (tenant_id, decision_id, enrolment_id, ended_assignment_id, end_date, end_reason, eligible_after, fte_after,
                                        proposed_outcome, proposed_until, outcome, coverage_until, offer_conversion, warnings, status)
    VALUES (t, '0c0c0000-0000-0000-0000-000000000001', '0c910000-0000-0000-0000-000000000002', '0c800000-0000-0000-0000-000000000002', '2027-03-15', 'ELIM',
            false, 0.6, 'continue_until', '2027-03-31', 'continue_until', '2027-03-31', false, ARRAY['COMMON_LAW_REVIEW'], 'proposed');
  BEGIN
    UPDATE benefits.change_decision SET status = 'decided', warnings = '{}', decided_by = '0ca00000-0000-0000-0000-000000000002', decided_at = now(),
           reason = 'Policy: month end' WHERE decision_id = '0c0c0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7c: decided past the common-law caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 7c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'benefits.common_law_notice', 'benefit_change_decision', '0c0c0000-0000-0000-0000-000000000001', 'shown', 'en',
            '0ca00000-0000-0000-0000-000000000002', 'Counsel advised month end; the employee keeps the full-time plan');
  UPDATE benefits.change_decision SET status = 'decided', decided_by = '0ca00000-0000-0000-0000-000000000002', decided_at = now(),
         reason = 'Counsel advised month end; the employee keeps the full-time plan' WHERE decision_id = '0c0c0000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 7c: outside Ontario, HR acknowledges the common-law caution and states why before deciding';

  BEGIN
    PERFORM benefits.retro_needs_hr(t, '0c100000-0000-0000-0000-000000000001', '2027-01-15', '2027-06-10');
    RAISE EXCEPTION 'FAIL 8: retro limit assumed before the organization chose one';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 8: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'benefits.retro_adjust_months', 'tenant', NULL, '3', '[2026-01-01,)', gen_random_uuid());
  IF NOT benefits.retro_needs_hr(t, '0c100000-0000-0000-0000-000000000001', '2027-01-15', '2027-06-10')
     OR benefits.retro_needs_hr(t, '0c100000-0000-0000-0000-000000000001', '2027-04-01', '2027-06-10') THEN
    RAISE EXCEPTION 'FAIL 8: three-month limit not applied';
  END IF;
  RAISE NOTICE 'PASS 8: adjustments older than the organization''s months go to HR';

  SELECT route_id INTO r FROM platform.workflow_route WHERE tenant_id = t AND code = 'carrier_invoice';
  BEGIN
    INSERT INTO benefits.carrier_invoice (tenant_id, legal_entity_id, carrier, period, amount, self_billed, prepared_by, route_id, status)
      VALUES (t, '0c100000-0000-0000-0000-000000000001', 'Carrier A', '[2027-01-01,2027-02-01)', 12500, false, '0ca00000-0000-0000-0000-000000000001', r, 'reconciled');
    RAISE EXCEPTION 'FAIL 9a: reconciled without its differences listed';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO benefits.carrier_invoice (tenant_id, invoice_id, legal_entity_id, carrier, period, amount, self_billed, differences, prepared_by, route_id, status)
    VALUES (t, '0c0b0000-0000-0000-0000-000000000001', '0c100000-0000-0000-0000-000000000001', 'Carrier A', '[2027-01-01,2027-02-01)', 12500, false,
            '[{"employment":"0c700000-0000-0000-0000-000000000001","plan":"HEALTH","invoice":"180.00","cando":"180.00"}]',
            '0ca00000-0000-0000-0000-000000000001', r, 'reconciled');
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'carrier_invoice', '0c0b0000-0000-0000-0000-000000000001', 1, 'approved', '0ca00000-0000-0000-0000-000000000001', now(), 'hr');
    RAISE EXCEPTION 'FAIL 9b: the preparer approved their own reconciliation';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 9b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'carrier_invoice', '0c0b0000-0000-0000-0000-000000000001', 1, 'approved', '0ca00000-0000-0000-0000-000000000002', now(), 'hr');
  BEGIN
    UPDATE benefits.carrier_invoice SET status = 'approved' WHERE invoice_id = '0c0b0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 9c: approved without finance';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 9c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'carrier_invoice', '0c0b0000-0000-0000-0000-000000000001', 2, 'approved', '0ca00000-0000-0000-0000-000000000003', now(), 'finance');
  UPDATE benefits.carrier_invoice SET status = 'approved' WHERE invoice_id = '0c0b0000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 9a-c: invoices reconciled by employee, then approved through the route, never by who prepared them';
END $$;

-- ---------------------------------------------------------------------------------
-- 10. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', 'c2222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM benefits.dependent) <> 0 OR (SELECT count(*) FROM benefits.governing_agreement) <> 0
     OR (SELECT count(*) FROM benefits.leave_rule) <> 0 OR (SELECT count(*) FROM benefits.opt_out) <> 0
     OR (SELECT count(*) FROM benefits.carrier_invoice) <> 0 OR (SELECT count(*) FROM benefits.leave_contribution_choice) <> 0 THEN
    RAISE EXCEPTION 'FAIL 10: another organization''s benefits data is visible';
  END IF;
  RAISE NOTICE 'PASS 10: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0012_smoke: all checks passed'
