-- Smoke test for schema/0010_payroll_decisions.sql (docs/24): the new settings and the ones the review decided, pay
-- run approval through the organization's route, holds for failed checks, the parallel run before going live, vacation
-- pay rules per group, banked-time policies and payout requests, the arrears rule per deduction, voluntary deductions,
-- garnishment orders confirmed before the first deduction, recoveries only with written authorization, delivery of
-- pay statements and slips by CRA's rule, former employees' access, ROE review, outside payroll providers, starter routes, RLS and
-- tenant isolation.
-- Run after every migration, 0001 to 0010 (CI, after the 0009 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0010_smoke.sql
-- It does not depend on today's date. It inserts test rows; run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, finance, compliance, talent, recruit TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ref, platform, core, payroll, timeleave, talent, recruit TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('a1111111-1111-1111-1111-111111111111', 'Payroll Test Society'),
  ('a2222222-2222-2222-2222-222222222222', 'Other Organization'),
  ('a3333333-3333-3333-3333-333333333333', 'Bookkeeping Partners')        -- an outside payroll provider
ON CONFLICT DO NOTHING;
-- The provider's own user, in the provider's organization (created by the identity Worker in real life)
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  ('a3333333-3333-3333-3333-333333333333', '0ab00000-0000-0000-0000-000000000001', 'prov1', 'prov1@example.test');

SET ROLE cando_app;
SELECT set_config('app.tenant_id', 'a1111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, decided defaults, starter routes, RLS
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/24%') <> 6 THEN
    RAISE EXCEPTION 'FAIL 1a: expected 6 settings decided in docs/24, found %', (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/24%');
  END IF;
  IF (SELECT decision_status FROM platform.setting_definition WHERE setting_key = 'payroll.default_proration_method') <> 'pending'
     OR platform.setting_text(t, 'payroll.one_time_allocation') <> 'assignment'
     OR platform.setting_text(t, 'payroll.failed_check_handling') <> 'hold_affected'
     OR (SELECT decision_status FROM platform.setting_definition WHERE setting_key = 'funding.default_cap_behaviour') <> 'decided' THEN
    RAISE EXCEPTION 'FAIL 1b: decided defaults not in place';
  END IF;
  IF (SELECT count(*) FROM platform.workflow_route WHERE tenant_id = t AND code IN ('pay_run','voluntary_deduction','banked_time_payout')) <> 3 THEN
    RAISE EXCEPTION 'FAIL 1c: starter payroll routes not copied';
  END IF;
  SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.relkind = 'r' AND n.nspname IN ('platform','payroll','timeleave')
     AND NOT (n.nspname = 'platform' AND c.relname = 'tenant')
     AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1d: RLS missing on %', bad; END IF;
  RAISE NOTICE 'PASS 1a-d: settings, decided defaults, starter payroll routes, RLS';
END $$;

-- Fixtures: one employer, a unit, two positions (permanent and casual), three people, payroll staff, one payroll account
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  (current_setting('app.tenant_id')::uuid, '0aa00000-0000-0000-0000-000000000001', 'prep', 'prep@example.test'),     -- prepares pay runs
  (current_setting('app.tenant_id')::uuid, '0aa00000-0000-0000-0000-000000000002', 'paychk', 'paychk@example.test'), -- payroll reviewer
  (current_setting('app.tenant_id')::uuid, '0aa00000-0000-0000-0000-000000000003', 'fin', 'fin@example.test'),       -- finance approver
  (current_setting('app.tenant_id')::uuid, '0aa00000-0000-0000-0000-000000000004', 'emp', 'emp@example.test'),       -- an employee
  (current_setting('app.tenant_id')::uuid, '0aa00000-0000-0000-0000-000000000005', 'admin', 'admin@example.test');   -- the client's administrator
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, '0a100000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, '0a200000-0000-0000-0000-000000000001');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction) VALUES
  (current_setting('app.tenant_id')::uuid, '0a200000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Office', '1 Main St', 'Victoria', 'BC', 'V8W 1A1', 'America/Vancouver', 'BC');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, '0a300000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, '0a400000-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, '0a400000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'SW', 'Support Worker', 'Intervenant de soutien');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, '0a500000-0000-0000-0000-000000000001', 'P-PERM'),
  (current_setting('app.tenant_id')::uuid, '0a500000-0000-0000-0000-000000000002', 'P-CAS');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0a300000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0a100000-0000-0000-0000-000000000001', 'DEPT', 'SUP', 'Support services', '0a500000-0000-0000-0000-000000000001');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0a500000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0a400000-0000-0000-0000-000000000001', '0a300000-0000-0000-0000-000000000001', '0a200000-0000-0000-0000-000000000001', NULL, 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0a500000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '0a400000-0000-0000-0000-000000000001', '0a300000-0000-0000-0000-000000000001', '0a200000-0000-0000-0000-000000000001', '0a500000-0000-0000-0000-000000000001', 0.5, 'casual', 'active');
INSERT INTO core.person (tenant_id, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0a600000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0a600000-0000-0000-0000-000000000002');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0a700000-0000-0000-0000-000000000001', '0a600000-0000-0000-0000-000000000001', '0a100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0a700000-0000-0000-0000-000000000002', '0a600000-0000-0000-0000-000000000002', '0a100000-0000-0000-0000-000000000001');
INSERT INTO core.payroll_account (tenant_id, payroll_account_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
  VALUES (current_setting('app.tenant_id')::uuid, '0a900000-0000-0000-0000-000000000001', '0a100000-0000-0000-0000-000000000001', 'RP0001', 'regular', '[2026-01-01,)');
DO $$
BEGIN
  BEGIN
    INSERT INTO payroll.pay_group (tenant_id, pay_group_id, payroll_account_id, code, name, frequency, periods_per_year)
      VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), '0a900000-0000-0000-0000-000000000001', 'X', 'No proration chosen', 'biweekly', '{"2026": 26}');
    RAISE EXCEPTION 'FAIL 1e: pay group created without its proration method';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 1e: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 1e: each pay group chooses its proration method';
END $$;
INSERT INTO payroll.pay_group (tenant_id, pay_group_id, payroll_account_id, code, name, frequency, periods_per_year, proration_method)
  VALUES (current_setting('app.tenant_id')::uuid, '0a900000-0000-0000-0000-000000000002', '0a900000-0000-0000-0000-000000000001', 'BW', 'Bi-weekly', 'biweekly', '{"2026": 26}', 'working_days');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0a800000-0000-0000-0000-000000000001', '0a700000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0a800000-0000-0000-0000-000000000002', '0a700000-0000-0000-0000-000000000002');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type, pay_group_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0a800000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), '0a500000-0000-0000-0000-000000000001', '0a300000-0000-0000-0000-000000000001', '0a200000-0000-0000-0000-000000000001', 1, true, 'permanent', '0a900000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0a800000-0000-0000-0000-000000000002', '[2026-01-01,)', gen_random_uuid(), '0a500000-0000-0000-0000-000000000002', '0a300000-0000-0000-0000-000000000001', '0a200000-0000-0000-0000-000000000001', 0.5, true, 'casual', '0a900000-0000-0000-0000-000000000002');
INSERT INTO payroll.pay_code (tenant_id, pay_code, kind, name_en, name_fr, accrues_leave) VALUES
  (current_setting('app.tenant_id')::uuid, 'REG', 'earning', 'Regular pay', 'Salaire régulier', true),
  (current_setting('app.tenant_id')::uuid, 'ADV-REC', 'earning', 'Advance recovery', 'Recouvrement d''avance', false);
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by) VALUES
  (current_setting('app.tenant_id')::uuid, '0ad00000-0000-0000-0000-000000000001', 'person', '0a600000-0000-0000-0000-000000000001', 'garnishment_order', 'restricted', 'payroll', 'test/order.pdf', 'x', 'application/pdf', '0aa00000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0ad00000-0000-0000-0000-000000000002', 'person', '0a600000-0000-0000-0000-000000000001', 'recovery_authorization', 'restricted', 'payroll', 'test/auth.pdf', 'x', 'application/pdf', '0aa00000-0000-0000-0000-000000000002');

DO $$
BEGIN
  BEGIN
    INSERT INTO payroll.one_time_item (tenant_id, employment_id, pay_code, amount, pay_on_or_after, source, status)
      VALUES (current_setting('app.tenant_id')::uuid, '0a700000-0000-0000-0000-000000000001', 'REG', 500, '2026-11-20', 'award', 'pending');
    RAISE EXCEPTION 'FAIL 1f: a one-time payment saved without its position';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO payroll.one_time_item (tenant_id, employment_id, pay_code, amount, pay_on_or_after, source, status, assignment_id)
    VALUES (current_setting('app.tenant_id')::uuid, '0a700000-0000-0000-0000-000000000001', 'REG', 500, '2026-11-20', 'award', 'pending', '0a800000-0000-0000-0000-000000000001');
  RAISE NOTICE 'PASS 1f: a one-time payment names its position';
END $$;

-- ---------------------------------------------------------------------------------
-- 2. Pay run approval through the organization's route; no self-approval
-- ---------------------------------------------------------------------------------
INSERT INTO payroll.pay_run (tenant_id, pay_run_id, number, run_type, legal_entity_id, pay_group_id, population, work_period, pay_date, status, created_by, route_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0ac00000-0000-0000-0000-000000000001', 1, 'regular', '0a100000-0000-0000-0000-000000000001', '0a900000-0000-0000-0000-000000000002',
   '{"mode":"pay_group"}', '[2026-11-01,2026-11-14]', '2026-11-20', 'reviewed', '0aa00000-0000-0000-0000-000000000001',
   (SELECT route_id FROM platform.workflow_route WHERE tenant_id = current_setting('app.tenant_id')::uuid AND code = 'pay_run')),
  (current_setting('app.tenant_id')::uuid, '0ac00000-0000-0000-0000-000000000002', 2, 'regular', '0a100000-0000-0000-0000-000000000001', '0a900000-0000-0000-0000-000000000002',
   '{"mode":"pay_group"}', '[2026-11-15,2026-11-28]', '2026-12-04', 'reviewed', '0aa00000-0000-0000-0000-000000000001',
   (SELECT route_id FROM platform.workflow_route WHERE tenant_id = current_setting('app.tenant_id')::uuid AND code = 'pay_run'));
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    UPDATE payroll.pay_run SET status = 'approved' WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2a: approved without naming the approver';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE payroll.pay_run SET status = 'approved', approved_by = '0aa00000-0000-0000-0000-000000000003' WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2b: approved with the route incomplete';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'pay_run', '0ac00000-0000-0000-0000-000000000001', 1, 'approved', '0aa00000-0000-0000-0000-000000000001', now(), 'finance');
    RAISE EXCEPTION 'FAIL 2c: the preparer approved their own pay run';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'pay_run', '0ac00000-0000-0000-0000-000000000001', 1, 'approved', '0aa00000-0000-0000-0000-000000000003', now(), 'finance');
  UPDATE payroll.pay_run SET status = 'approved', approved_by = '0aa00000-0000-0000-0000-000000000003' WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 2a-c: pay run approved only through its route, never by its preparer';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Held employees and the organization's choice to stop the run; 4. the parallel run before going live
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  INSERT INTO payroll.pay_run_hold (tenant_id, pay_run_id, person_id, payroll_account_id, check_code, reason, held_by)
    VALUES (t, '0ac00000-0000-0000-0000-000000000002', '0a600000-0000-0000-0000-000000000002', '0a900000-0000-0000-0000-000000000001',
            'BANK_ACCOUNT_MISSING', 'No bank account on file', '0aa00000-0000-0000-0000-000000000001');
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'pay_run', '0ac00000-0000-0000-0000-000000000002', 1, 'approved', '0aa00000-0000-0000-0000-000000000003', now(), 'finance');
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'payroll.failed_check_handling', 'legal_entity', '0a100000-0000-0000-0000-000000000001', '"stop_run"', '[2026-12-01,)', gen_random_uuid());
  BEGIN
    UPDATE payroll.pay_run SET status = 'approved', approved_by = '0aa00000-0000-0000-0000-000000000003' WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 3a: run approved with a failed check where the employer stops the run';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PAY_RUN_HAS_FAILED_CHECKS%' THEN RAISE EXCEPTION 'FAIL 3a: %', SQLERRM; END IF;
  END;
  UPDATE payroll.pay_run_hold SET released_at = now() WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000002';
  UPDATE payroll.pay_run SET status = 'approved', approved_by = '0aa00000-0000-0000-0000-000000000003' WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000002';
  RAISE NOTICE 'PASS 3a: held employees; an employer that stops the run approves only once every check is fixed';

  BEGIN
    UPDATE payroll.pay_run SET status = 'finalized', finalized_at = now() WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4a: first live run without a parallel run';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PARALLEL_RUN_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO payroll.parallel_run (tenant_id, payroll_account_id, pay_date, legacy_totals, status, accepted_by, accepted_at)
      VALUES (t, '0a900000-0000-0000-0000-000000000001', '2026-11-06', '{"net":"10234.55"}', 'accepted', '0aa00000-0000-0000-0000-000000000003', now());
    RAISE EXCEPTION 'FAIL 4b: parallel run accepted without its differences explained';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO payroll.parallel_run (tenant_id, payroll_account_id, pay_date, legacy_totals, differences, status, accepted_by, accepted_at)
    VALUES (t, '0a900000-0000-0000-0000-000000000001', '2026-11-06', '{"net":"10234.55"}',
            '[{"person":"0a600000-0000-0000-0000-000000000001","code":"TAX","diff":"0.01","explanation":"Old system rounds per period"}]',
            'accepted', '0aa00000-0000-0000-0000-000000000003', now());
  UPDATE payroll.pay_run SET status = 'finalized', finalized_at = now() WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000001';
  UPDATE payroll.pay_run SET status = 'finalized', finalized_at = now() WHERE pay_run_id = '0ac00000-0000-0000-0000-000000000002';
  RAISE NOTICE 'PASS 4a-b: the first live run waits for an accepted parallel run with every difference explained; later runs do not';
END $$;

-- ---------------------------------------------------------------------------------
-- 5. Vacation pay rules per group; 6. banked-time policies and payout requests
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r payroll.vacation_pay_rule; route uuid;
BEGIN
  BEGIN
    PERFORM payroll.vacation_pay_rule_for('0a800000-0000-0000-0000-000000000001', '2026-11-02');
    RAISE EXCEPTION 'FAIL 5a: a vacation pay rule assumed before the organization set any';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'VACATION_PAY_RULE_MISSING%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO payroll.vacation_pay_rule (tenant_id, code, name_en, method, rate_source, applies_to, priority, status)
      VALUES (t, 'BAD', 'Bad scope', 'accrue_pay_when_taken', 'law_minimum', '{"shoeSize":["9"]}', 99, 'active');
    RAISE EXCEPTION 'FAIL 5b: unknown scope accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PAYROLL_SCOPE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 5b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO payroll.vacation_pay_rule (tenant_id, code, name_en, method, rate_source, applies_to, priority, status)
      VALUES (t, 'FIX', 'Fixed without a percentage', 'accrue_pay_when_taken', 'fixed_percent', '{}', 98, 'active');
    RAISE EXCEPTION 'FAIL 5b: a fixed rate without its percentage';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO payroll.vacation_pay_rule (tenant_id, code, name_en, name_fr, method, rate_source, percent, applies_to, priority, status) VALUES
    (t, 'CASUAL', 'Casual and on-call: on each cheque', 'Occasionnels et sur appel : sur chaque paie', 'pay_each_cheque', 'law_minimum', NULL, '{"employmentTypes":["casual"]}', 10, 'active'),
    (t, 'ALL', 'Everyone else: accrue, 6%', 'Tous les autres : accumulée, 6 %', 'accrue_pay_when_taken', 'fixed_percent', 6, '{}', 20, 'active');
  r := payroll.vacation_pay_rule_for('0a800000-0000-0000-0000-000000000002', '2026-11-02');
  IF r.code <> 'CASUAL' OR r.method <> 'pay_each_cheque' THEN RAISE EXCEPTION 'FAIL 5c: casual position got rule %', r.code; END IF;
  r := payroll.vacation_pay_rule_for('0a800000-0000-0000-0000-000000000001', '2026-11-02');
  IF r.code <> 'ALL' OR r.percent <> 6 THEN RAISE EXCEPTION 'FAIL 5c: permanent position got rule %', r.code; END IF;
  RAISE NOTICE 'PASS 5a-c: vacation pay set per group of employees; nothing assumed without a rule';

  BEGIN
    INSERT INTO timeleave.banked_time_policy (tenant_id, code, name_en, year_end_action, employee_payout_requests, applies_to, priority, status)
      VALUES (t, 'MIX', 'Carry then pay', 'carry_then_pay', false, '{}', 50, 'active');
    RAISE EXCEPTION 'FAIL 6a: carry-then-pay without its limit';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO timeleave.banked_time_policy (tenant_id, code, name_en, year_end_action, carry_limit_hours, employee_payout_requests, applies_to, priority, status) VALUES
    (t, 'CASUAL', 'Casual: pay out at year-end, requests allowed', 'pay_out', NULL, true, '{"employmentTypes":["casual"]}', 10, 'active'),
    (t, 'MIX', 'Carry up to 40 hours, pay the rest', 'carry_then_pay', 40, false, '{}', 20, 'active');
  BEGIN
    INSERT INTO timeleave.banked_time_payout_request (tenant_id, assignment_id, hours, requested_on, requested_by, status)
      VALUES (t, '0a800000-0000-0000-0000-000000000001', 8, '2026-11-02', '0aa00000-0000-0000-0000-000000000004', 'requested');
    RAISE EXCEPTION 'FAIL 6b: payout request where the policy does not allow one';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'BANKED_PAYOUT_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 6b: %', SQLERRM; END IF;
  END;
  SELECT route_id INTO route FROM platform.workflow_route WHERE tenant_id = t AND code = 'banked_time_payout';
  INSERT INTO timeleave.banked_time_payout_request (tenant_id, request_id, assignment_id, hours, requested_on, requested_by, route_id, status)
    VALUES (t, '0ae00000-0000-0000-0000-000000000001', '0a800000-0000-0000-0000-000000000002', 8, '2026-11-02', '0aa00000-0000-0000-0000-000000000004', route, 'requested');
  BEGIN
    UPDATE timeleave.banked_time_payout_request SET status = 'approved' WHERE request_id = '0ae00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 6c: payout approved with the route incomplete';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 6c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'banked_time_payout', '0ae00000-0000-0000-0000-000000000001', 1, 'approved', '0aa00000-0000-0000-0000-000000000005', now(), 'manager'),
    (t, 'banked_time_payout', '0ae00000-0000-0000-0000-000000000001', 2, 'approved', '0aa00000-0000-0000-0000-000000000002', now(), 'payroll');
  UPDATE timeleave.banked_time_payout_request SET status = 'approved' WHERE request_id = '0ae00000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 6a-c: banked time per group, mixing carry-over and payout; payout requests only where allowed and approved';
END $$;

-- ---------------------------------------------------------------------------------
-- 7. Deductions: arrears rule, voluntary deductions, garnishments, arrears write-off; 8. recoveries
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; route uuid;
BEGIN
  BEGIN
    INSERT INTO payroll.pay_code (tenant_id, pay_code, kind, name_en, name_fr, accrues_leave) VALUES (t, 'CHAR', 'deduction', 'Charity', 'Bienfaisance', false);
    RAISE EXCEPTION 'FAIL 7a: deduction without its shortfall rule';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO payroll.pay_code (tenant_id, pay_code, kind, name_en, name_fr, accrues_leave, arrears_recovery) VALUES (t, 'PARK', 'deduction', 'Parking', 'Stationnement', false, 'spread');
    RAISE EXCEPTION 'FAIL 7a: spread arrears without the number of periods';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO payroll.pay_code (tenant_id, pay_code, kind, name_en, name_fr, accrues_leave, arrears_recovery, arrears_spread_periods) VALUES
    (t, 'CHAR', 'deduction', 'Charity', 'Bienfaisance', false, 'not_recovered', NULL),
    (t, 'PARK', 'deduction', 'Parking', 'Stationnement', false, 'spread', 3);
  BEGIN
    INSERT INTO payroll.voluntary_deduction (tenant_id, employment_id, pay_code, amount_per_pay, start_on, requested_by, status)
      VALUES (t, '0a700000-0000-0000-0000-000000000001', 'REG', 10, '2026-11-01', '0aa00000-0000-0000-0000-000000000004', 'requested');
    RAISE EXCEPTION 'FAIL 7b: voluntary deduction on an earnings code';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PAY_CODE_NOT_DEDUCTION%' THEN RAISE EXCEPTION 'FAIL 7b: %', SQLERRM; END IF;
  END;
  SELECT route_id INTO route FROM platform.workflow_route WHERE tenant_id = t AND code = 'voluntary_deduction';
  INSERT INTO payroll.voluntary_deduction (tenant_id, deduction_id, employment_id, pay_code, amount_per_pay, goal_amount, start_on, requested_by, route_id, status)
    VALUES (t, '0af00000-0000-0000-0000-000000000001', '0a700000-0000-0000-0000-000000000001', 'CHAR', 10, 260, '2026-11-01', '0aa00000-0000-0000-0000-000000000004', route, 'requested');
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'voluntary_deduction', '0af00000-0000-0000-0000-000000000001', 1, 'approved', '0aa00000-0000-0000-0000-000000000004', now(), 'payroll');
    RAISE EXCEPTION 'FAIL 7c: the employee approved their own deduction';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 7c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'voluntary_deduction', '0af00000-0000-0000-0000-000000000001', 1, 'approved', '0aa00000-0000-0000-0000-000000000002', now(), 'payroll');
  UPDATE payroll.voluntary_deduction SET status = 'approved' WHERE deduction_id = '0af00000-0000-0000-0000-000000000001';

  BEGIN
    INSERT INTO payroll.garnishment_order (tenant_id, order_id, employment_id, kind, jurisdiction, issuer, reference, document_id, terms, received_on, start_on, entered_by, status)
      VALUES (t, '0a0a0000-0000-0000-0000-000000000001', '0a700000-0000-0000-0000-000000000001', 'family_support', 'BC', 'BC Family Maintenance Enforcement Program',
              'FMEP-123', '0ad00000-0000-0000-0000-000000000001', '{"perPay":"250.00"}', '2026-10-20', '2026-11-01', '0aa00000-0000-0000-0000-000000000002', 'active');
    RAISE EXCEPTION 'FAIL 7d: support order deducted before payroll confirmed it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'GARNISHMENT_NOT_CONFIRMED%' THEN RAISE EXCEPTION 'FAIL 7d: %', SQLERRM; END IF;
  END;
  INSERT INTO payroll.garnishment_order (tenant_id, order_id, employment_id, kind, jurisdiction, issuer, reference, document_id, terms, received_on, start_on, entered_by,
                                         first_deduction_confirmed_by, first_deduction_confirmed_at, status)
    VALUES (t, '0a0a0000-0000-0000-0000-000000000001', '0a700000-0000-0000-0000-000000000001', 'family_support', 'BC', 'BC Family Maintenance Enforcement Program',
            'FMEP-123', '0ad00000-0000-0000-0000-000000000001', '{"perPay":"250.00"}', '2026-10-20', '2026-11-01', '0aa00000-0000-0000-0000-000000000002',
            '0aa00000-0000-0000-0000-000000000002', now(), 'active');
  BEGIN
    INSERT INTO payroll.deduction_arrears (tenant_id, employment_id, pay_code, amount, status, written_off_by)
      VALUES (t, '0a700000-0000-0000-0000-000000000001', 'PARK', 30, 'written_off', '0aa00000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'FAIL 7e: arrears written off without a reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 7a-e: each deduction states its shortfall rule; voluntary deductions through the route; support orders confirmed first; write-offs explained';

  -- 8. Money owed is recovered only with written authorization, never more than authorized
  BEGIN
    INSERT INTO payroll.one_time_item (tenant_id, employment_id, assignment_id, pay_code, amount, pay_on_or_after, source, status)
      VALUES (t, '0a700000-0000-0000-0000-000000000001', '0a800000-0000-0000-0000-000000000001', 'ADV-REC', -150, '2026-11-20', 'recovery', 'pending');
    RAISE EXCEPTION 'FAIL 8a: recovery without the employee''s authorization';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RECOVERY_NOT_AUTHORIZED%' THEN RAISE EXCEPTION 'FAIL 8a: %', SQLERRM; END IF;
  END;
  INSERT INTO payroll.recovery_authorization (tenant_id, authorization_id, employment_id, kind, description, amount, per_pay_limit, document_id, signed_on)
    VALUES (t, '0a0b0000-0000-0000-0000-000000000001', '0a700000-0000-0000-0000-000000000001', 'advance', 'Pay advance of 15 October', 300, 150,
            '0ad00000-0000-0000-0000-000000000002', '2026-10-15');
  INSERT INTO payroll.one_time_item (tenant_id, employment_id, assignment_id, pay_code, amount, pay_on_or_after, source, status, recovery_authorization_id) VALUES
    (t, '0a700000-0000-0000-0000-000000000001', '0a800000-0000-0000-0000-000000000001', 'ADV-REC', -150, '2026-11-20', 'recovery', 'pending', '0a0b0000-0000-0000-0000-000000000001'),
    (t, '0a700000-0000-0000-0000-000000000001', '0a800000-0000-0000-0000-000000000001', 'ADV-REC', -150, '2026-12-04', 'recovery', 'pending', '0a0b0000-0000-0000-0000-000000000001');
  BEGIN
    INSERT INTO payroll.one_time_item (tenant_id, employment_id, assignment_id, pay_code, amount, pay_on_or_after, source, status, recovery_authorization_id)
      VALUES (t, '0a700000-0000-0000-0000-000000000001', '0a800000-0000-0000-0000-000000000001', 'ADV-REC', -50, '2026-12-18', 'recovery', 'pending', '0a0b0000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL 8b: recovered more than authorized';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'RECOVERY_ABOVE_AUTHORIZED%' THEN RAISE EXCEPTION 'FAIL 8b: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 8a-b: money owed recovered only with written authorization and never above it';
END $$;

-- ---------------------------------------------------------------------------------
-- 9. Delivery by CRA's rule; 10. former employees' access; 11. ROE review
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  -- A current employee gets slips in self-service without consent, on paper if they ask
  IF payroll.delivery_method('0a600000-0000-0000-0000-000000000001', 'tax_slip', '2027-02-01') <> 'portal' THEN
    RAISE EXCEPTION 'FAIL 9a: a current employee''s T4 not in self-service';
  END IF;
  INSERT INTO payroll.delivery_choice (tenant_id, person_id, document_kind, choice, given_at, method)
    VALUES (t, '0a600000-0000-0000-0000-000000000001', 'pay_statement', 'paper_request', '2026-11-02 09:00-08', 'paper_form');
  IF payroll.delivery_method('0a600000-0000-0000-0000-000000000001', 'pay_statement', '2027-02-01') <> 'print'
     OR payroll.may_email('0a600000-0000-0000-0000-000000000001', 'tax_slip', '2027-02-01') THEN
    RAISE EXCEPTION 'FAIL 9b: paper request ignored, or email without consent';
  END IF;
  -- A former employee: paper unless they consented
  INSERT INTO core.person (tenant_id, person_id) VALUES (t, '0a600000-0000-0000-0000-000000000009');
  INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id)
    VALUES (t, '0a700000-0000-0000-0000-000000000009', '0a600000-0000-0000-0000-000000000009', '0a100000-0000-0000-0000-000000000001');
  INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES (t, '0a800000-0000-0000-0000-000000000009', '0a700000-0000-0000-0000-000000000009');
  INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type)
    VALUES (t, '0a800000-0000-0000-0000-000000000009', '[2025-01-01,2026-10-01)', gen_random_uuid(), '0a500000-0000-0000-0000-000000000002',
            '0a300000-0000-0000-0000-000000000001', '0a200000-0000-0000-0000-000000000001', 0.5, true, 'casual');
  IF payroll.delivery_method('0a600000-0000-0000-0000-000000000009', 'tax_slip', '2027-02-01') <> 'print' THEN
    RAISE EXCEPTION 'FAIL 9c: a former employee''s T4 sent electronically without consent';
  END IF;
  INSERT INTO payroll.delivery_choice (tenant_id, person_id, document_kind, choice, given_at, method)
    VALUES (t, '0a600000-0000-0000-0000-000000000009', 'tax_slip', 'electronic_consent', '2026-09-15 09:00-07', 'self_service');
  IF payroll.delivery_method('0a600000-0000-0000-0000-000000000009', 'tax_slip', '2027-02-01') <> 'portal' THEN
    RAISE EXCEPTION 'FAIL 9c: a former employee''s consent ignored';
  END IF;
  RAISE NOTICE 'PASS 9a-c: self-service for current staff, paper on request; former staff electronic only with consent; email only with consent';

  IF payroll.former_employee_access_until(t, '0a100000-0000-0000-0000-000000000001', '2026-11-15') <> '2028-02-28' THEN
    RAISE EXCEPTION 'FAIL 10a: access until %', payroll.former_employee_access_until(t, '0a100000-0000-0000-0000-000000000001', '2026-11-15');
  END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'self_service.former_employee_access', 'legal_entity', '0a100000-0000-0000-0000-000000000001', '{"monthsAfterNextT4":24}', '[2000-01-01,)', gen_random_uuid());
  IF payroll.former_employee_access_until(t, '0a100000-0000-0000-0000-000000000001', '2026-11-15') <> '2029-02-28' THEN
    RAISE EXCEPTION 'FAIL 10b: the employer''s own period not used';
  END IF;
  RAISE NOTICE 'PASS 10: former employees keep access until the next T4 is due plus the employer''s months';

  BEGIN
    INSERT INTO payroll.roe (tenant_id, employment_id, reason_code, first_day_worked, last_day_paid, final_pay_period_end, blocks, status, due_date)
      VALUES (t, '0a700000-0000-0000-0000-000000000002', 'E', '2026-01-05', '2026-11-13', '2026-11-14', '{}', 'validated', '2026-11-19');
    RAISE EXCEPTION 'FAIL 11: ROE built without HR''s review';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROE_NOT_REVIEWED%' THEN RAISE EXCEPTION 'FAIL 11: %', SQLERRM; END IF;
  END;
  INSERT INTO payroll.roe (tenant_id, employment_id, reason_code, first_day_worked, last_day_paid, final_pay_period_end, blocks, status, due_date, reviewed_by, reviewed_at)
    VALUES (t, '0a700000-0000-0000-0000-000000000002', 'E', '2026-01-05', '2026-11-13', '2026-11-14', '{}', 'validated', '2026-11-19', '0aa00000-0000-0000-0000-000000000005', now());
  RAISE NOTICE 'PASS 11: HR reviews every ROE before its file is built';
END $$;

-- ---------------------------------------------------------------------------------
-- 12. Outside payroll providers: only what the client approved
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO platform.provider_access_grant (tenant_id, provider_tenant_id, provider_user_id, capabilities, valid_period, status)
      VALUES (t, 'a3333333-3333-3333-3333-333333333333', '0ab00000-0000-0000-0000-000000000001', ARRAY['payroll_prepare','everything'], '[2026-11-01,2027-11-01)', 'requested');
    RAISE EXCEPTION 'FAIL 12a: unknown provider capability accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PROVIDER_CAPABILITY_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 12a: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.provider_access_grant (tenant_id, grant_id, provider_tenant_id, provider_user_id, capabilities, valid_period, status)
    VALUES (t, '0a0c0000-0000-0000-0000-000000000001', 'a3333333-3333-3333-3333-333333333333', '0ab00000-0000-0000-0000-000000000001',
            ARRAY['payroll_prepare','payroll_files','reports'], '[2026-11-01,2027-11-01)', 'requested');
  IF platform.provider_can(t, '0ab00000-0000-0000-0000-000000000001', 'payroll_prepare', '2026-12-01') THEN
    RAISE EXCEPTION 'FAIL 12b: provider acting before the client approved';
  END IF;
  BEGIN
    UPDATE platform.provider_access_grant SET status = 'approved', approved_by = '0ab00000-0000-0000-0000-000000000001', approved_at = now()
     WHERE grant_id = '0a0c0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 12c: the provider approved its own access';
  EXCEPTION WHEN check_violation OR foreign_key_violation THEN NULL;
  END;
  UPDATE platform.provider_access_grant SET status = 'approved', approved_by = '0aa00000-0000-0000-0000-000000000005', approved_at = now()
   WHERE grant_id = '0a0c0000-0000-0000-0000-000000000001';
  IF NOT platform.provider_can(t, '0ab00000-0000-0000-0000-000000000001', 'payroll_prepare', '2026-12-01')
     OR platform.provider_can(t, '0ab00000-0000-0000-0000-000000000001', 'payroll_approve', '2026-12-01')
     OR platform.provider_can(t, '0ab00000-0000-0000-0000-000000000001', 'payroll_prepare', '2027-12-01') THEN
    RAISE EXCEPTION 'FAIL 12d: provider access not limited to what the client approved, for the period approved';
  END IF;
  RAISE NOTICE 'PASS 12a-d: a provider acts for a client only with the client''s approval, for what and how long it approved';
END $$;

-- ---------------------------------------------------------------------------------
-- 13. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', 'a2222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM payroll.vacation_pay_rule) <> 0 OR (SELECT count(*) FROM payroll.garnishment_order) <> 0
     OR (SELECT count(*) FROM payroll.pay_run_hold) <> 0 OR (SELECT count(*) FROM platform.provider_access_grant) <> 0
     OR (SELECT count(*) FROM payroll.recovery_authorization) <> 0 OR (SELECT count(*) FROM payroll.delivery_choice) <> 0 THEN
    RAISE EXCEPTION 'FAIL 13: another organization''s payroll data is visible';
  END IF;
  RAISE NOTICE 'PASS 13: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0010_smoke: all checks passed'
