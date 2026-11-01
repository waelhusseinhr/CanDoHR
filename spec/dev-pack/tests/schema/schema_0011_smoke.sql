-- Smoke test for schema/0011_compensation_decisions.sql (docs/25): the new settings, the philosophy and its approval
-- before a market-based structure, structure approval through the route, location pay per structure, catch-up plans
-- below the minimum, promotion and demotion rules, guideline exceptions with HR's approval, cycles that start from the
-- settings, incentive plans, awards and clawbacks, long-term incentive grants, salary disclosure lists, bargaining
-- scenarios, starter routes and decision kinds, RLS and tenant isolation.
-- Run after every migration, 0001 to 0011 (CI, after the 0010 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0011_smoke.sql
-- It does not depend on today's date. It inserts test rows; run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ref, platform, core, payroll, timeleave, talent, recruit, comp, compliance TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('b1111111-1111-1111-1111-111111111111', 'Compensation Test Society'),
  ('b2222222-2222-2222-2222-222222222222', 'Other Organization')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', 'b1111111-1111-1111-1111-111111111111', false) AS cfg \gset
SELECT set_config('app.roles', 'comp_admin,comp_analyst', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, starter routes and decision kinds, RLS
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/25%') <> 18 THEN
    RAISE EXCEPTION 'FAIL 1a: expected 18 settings decided in docs/25, found %', (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/25%');
  END IF;
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/25%' AND decision_status = 'pending') <> 2 THEN
    RAISE EXCEPTION 'FAIL 1a: acting pay is chosen at setup';
  END IF;
  IF platform.setting_text(t, 'comp.above_maximum_handling') <> 'manager_proposes'
     OR platform.setting_text(t, 'cycles.out_of_guideline') <> 'reason_and_hr'
     OR platform.setting_number(t, 'comp.promotion_min_increase_pct') <> 5
     OR (platform.setting(t, 'comp.range_spread_by_track') ->> 'E')::int <> 60
     OR platform.setting_text(t, 'total_rewards.statement_mode') <> 'on_request' THEN
    RAISE EXCEPTION 'FAIL 1b: decided defaults not in place';
  END IF;
  BEGIN
    PERFORM platform.setting_text(t, 'comp.acting_pay_method');
    RAISE EXCEPTION 'FAIL 1b: acting pay read before the organization chose it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 1b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
      VALUES (t, 'privacy.min_group_size_self_id', 'tenant', NULL, '8', '[2027-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 1b: self-identification groups below 10 allowed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_BELOW_MINIMUM%' THEN RAISE EXCEPTION 'FAIL 1b: %', SQLERRM; END IF;
  END;
  IF (SELECT count(*) FROM platform.workflow_route WHERE tenant_id = t
        AND code IN ('comp_philosophy','pay_structure_version','comp_decision','incentive_payout','salary_disclosure')) <> 5
     OR (SELECT count(*) FROM core.list_value WHERE tenant_id = t AND list_code = 'comp_decision_kind' AND code IN ('demotion','acting','catch_up')) <> 3 THEN
    RAISE EXCEPTION 'FAIL 1c: starter routes or decision kinds not copied';
  END IF;
  SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE c.relkind = 'r' AND n.nspname IN ('comp','compliance')
     AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
     AND c.relname IN ('philosophy','range_catch_up','incentive_plan','incentive_award','lti_grant','salary_disclosure','bargaining_scenario')
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1d: RLS missing on %', bad; END IF;
  RAISE NOTICE 'PASS 1a-d: settings, decided defaults, acting pay chosen at setup, groups never below 10, starter routes and decision kinds, RLS';
END $$;

-- Fixtures: one employer, a unit, a position, two people, the organization's staff
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  (current_setting('app.tenant_id')::uuid, '0ba00000-0000-0000-0000-000000000001', 'analyst', 'analyst@example.test'),   -- compensation analyst
  (current_setting('app.tenant_id')::uuid, '0ba00000-0000-0000-0000-000000000002', 'hr', 'hr@example.test'),             -- HR
  (current_setting('app.tenant_id')::uuid, '0ba00000-0000-0000-0000-000000000003', 'fin', 'fin@example.test'),           -- finance
  (current_setting('app.tenant_id')::uuid, '0ba00000-0000-0000-0000-000000000004', 'exec', 'exec@example.test'),         -- executive
  (current_setting('app.tenant_id')::uuid, '0ba00000-0000-0000-0000-000000000005', 'mgr', 'mgr@example.test');           -- a manager
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, '0b100000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, '0b200000-0000-0000-0000-000000000001');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction) VALUES
  (current_setting('app.tenant_id')::uuid, '0b200000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Office', '1 Main St', 'Victoria', 'BC', 'V8W 1A1', 'America/Vancouver', 'BC');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, '0b300000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, '0b400000-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, '0b400000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'PO', 'Program Officer', 'Agent de programme');
INSERT INTO core.position (tenant_id, position_id, number) VALUES (current_setting('app.tenant_id')::uuid, '0b500000-0000-0000-0000-000000000001', 'P-PO');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0b300000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0b100000-0000-0000-0000-000000000001', 'DEPT', 'PRG', 'Programs', '0b500000-0000-0000-0000-000000000001');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0b500000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0b400000-0000-0000-0000-000000000001', '0b300000-0000-0000-0000-000000000001', '0b200000-0000-0000-0000-000000000001', NULL, 2, 'permanent', 'active');
INSERT INTO core.person (tenant_id, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0b600000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0b600000-0000-0000-0000-000000000002');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0b700000-0000-0000-0000-000000000001', '0b600000-0000-0000-0000-000000000001', '0b100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0b700000-0000-0000-0000-000000000002', '0b600000-0000-0000-0000-000000000002', '0b100000-0000-0000-0000-000000000001');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0b800000-0000-0000-0000-000000000001', '0b700000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0b800000-0000-0000-0000-000000000002', '0b700000-0000-0000-0000-000000000002');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type) VALUES
  (current_setting('app.tenant_id')::uuid, '0b800000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), '0b500000-0000-0000-0000-000000000001', '0b300000-0000-0000-0000-000000000001', '0b200000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '0b800000-0000-0000-0000-000000000002', '[2026-01-01,)', gen_random_uuid(), '0b500000-0000-0000-0000-000000000001', '0b300000-0000-0000-0000-000000000001', '0b200000-0000-0000-0000-000000000001', 1, true, 'permanent');
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by) VALUES
  (current_setting('app.tenant_id')::uuid, '0bd00000-0000-0000-0000-000000000001', 'person', '0b600000-0000-0000-0000-000000000001', 'bonus_agreement', 'restricted', 'payroll', 'test/bonus.pdf', 'x', 'application/pdf', '0ba00000-0000-0000-0000-000000000002');
INSERT INTO comp.market_definition (tenant_id, definition_id, code, name_en) VALUES
  (current_setting('app.tenant_id')::uuid, '0b0e0000-0000-0000-0000-000000000001', 'ALL', 'All jobs');
INSERT INTO comp.market_pricing_run (tenant_id, run_id, definition_id, as_of, definition_snapshot, created_by) VALUES
  (current_setting('app.tenant_id')::uuid, '0b0f0000-0000-0000-0000-000000000001', '0b0e0000-0000-0000-0000-000000000001', '2027-01-01', '{}', '0ba00000-0000-0000-0000-000000000001');

-- ---------------------------------------------------------------------------------
-- 2. Philosophy and structure approval through their routes
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r_phil uuid; r_struct uuid;
BEGIN
  SELECT route_id INTO r_phil FROM platform.workflow_route WHERE tenant_id = t AND code = 'comp_philosophy';
  SELECT route_id INTO r_struct FROM platform.workflow_route WHERE tenant_id = t AND code = 'pay_structure_version';
  INSERT INTO comp.pay_structure (tenant_id, structure_id, code, name_en, kind) VALUES (t, '0b0a0000-0000-0000-0000-000000000001', 'NU', 'Non-union', 'graded');
  INSERT INTO comp.pay_structure_version (tenant_id, structure_version_id, structure_id, label, valid_period, pricing_run_id)
    VALUES (t, '0b0b0000-0000-0000-0000-000000000001', '0b0a0000-0000-0000-0000-000000000001', '2027', '[2027-01-01,2028-01-01)', '0b0f0000-0000-0000-0000-000000000001');
  INSERT INTO comp.pay_grade (tenant_id, grade_id, structure_version_id, grade_code, rank, minimum, midpoint, maximum, spread_pct)
    VALUES (t, '0b0c0000-0000-0000-0000-000000000001', '0b0b0000-0000-0000-0000-000000000001', 'G05', 5, 55000, 66000, 77000, 40);
  BEGIN
    UPDATE comp.pay_structure_version SET status = 'approved', approved_by = '0ba00000-0000-0000-0000-000000000004', approved_at = now()
     WHERE structure_version_id = '0b0b0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2a: structure approved outside its route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  UPDATE comp.pay_structure_version SET submitted_by = '0ba00000-0000-0000-0000-000000000001', route_id = r_struct
   WHERE structure_version_id = '0b0b0000-0000-0000-0000-000000000001';
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'pay_structure_version', '0b0b0000-0000-0000-0000-000000000001', 1, 'approved', '0ba00000-0000-0000-0000-000000000002', now(), 'hr'),
    (t, 'pay_structure_version', '0b0b0000-0000-0000-0000-000000000001', 2, 'approved', '0ba00000-0000-0000-0000-000000000003', now(), 'finance');
  BEGIN
    UPDATE comp.pay_structure_version SET status = 'approved', approved_by = '0ba00000-0000-0000-0000-000000000004', approved_at = now()
     WHERE structure_version_id = '0b0b0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2b: structure approved without the executive step';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'pay_structure_version', '0b0b0000-0000-0000-0000-000000000001', 3, 'approved', '0ba00000-0000-0000-0000-000000000004', now(), 'executive');
  BEGIN
    UPDATE comp.pay_structure_version SET status = 'approved', approved_by = '0ba00000-0000-0000-0000-000000000004', approved_at = now()
     WHERE structure_version_id = '0b0b0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2c: market-based structure approved without an approved philosophy';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PHILOSOPHY_NOT_APPROVED%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  END;
  -- The philosophy, pre-filled from the setting, approved by an executive (never by who submitted it)
  INSERT INTO comp.philosophy (tenant_id, philosophy_id, valid_period, target, submitted_by, route_id, status)
    VALUES (t, '0b0d0000-0000-0000-0000-000000000001', '[2027-01-01,)',
            jsonb_build_object('default', platform.setting(t, 'comp.philosophy_starter')), '0ba00000-0000-0000-0000-000000000001', r_phil, 'draft');
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'comp_philosophy', '0b0d0000-0000-0000-0000-000000000001', 1, 'approved', '0ba00000-0000-0000-0000-000000000001', now(), 'executive');
    RAISE EXCEPTION 'FAIL 2d: the analyst approved their own philosophy';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE comp.philosophy SET status = 'approved', approved_at = now() WHERE philosophy_id = '0b0d0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 2d: philosophy approved without its route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'comp_philosophy', '0b0d0000-0000-0000-0000-000000000001', 1, 'approved', '0ba00000-0000-0000-0000-000000000004', now(), 'executive');
  UPDATE comp.philosophy SET status = 'approved', approved_at = now() WHERE philosophy_id = '0b0d0000-0000-0000-0000-000000000001';
  UPDATE comp.pay_structure_version SET status = 'approved', approved_by = '0ba00000-0000-0000-0000-000000000004', approved_at = now()
   WHERE structure_version_id = '0b0b0000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 2a-d: structures approved only through their route; a market-based one needs the executive-approved philosophy';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Location pay per structure; 4. catch-up plans below the minimum
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; d date;
BEGIN
  INSERT INTO comp.pay_structure (tenant_id, structure_id, code, name_en, kind, location_method)
    VALUES (t, '0b0a0000-0000-0000-0000-000000000002', 'LOC', 'By location', 'graded', 'location_ranges');
  INSERT INTO comp.pay_structure_version (tenant_id, structure_version_id, structure_id, label, valid_period)
    VALUES (t, '0b0b0000-0000-0000-0000-000000000002', '0b0a0000-0000-0000-0000-000000000002', '2027', '[2027-01-01,2028-01-01)');
  BEGIN
    INSERT INTO comp.pay_grade (tenant_id, structure_version_id, grade_code, rank, minimum, midpoint, maximum)
      VALUES (t, '0b0b0000-0000-0000-0000-000000000002', 'G05', 5, 55000, 66000, 77000);
    RAISE EXCEPTION 'FAIL 3: grade without its location group in a structure with ranges per location';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LOCATION_GROUP_MISMATCH%' THEN RAISE EXCEPTION 'FAIL 3: %', SQLERRM; END IF;
  END;
  INSERT INTO comp.pay_grade (tenant_id, structure_version_id, grade_code, rank, minimum, midpoint, maximum, location_group) VALUES
    (t, '0b0b0000-0000-0000-0000-000000000002', 'G05', 5, 55000, 66000, 77000, 'SOUTH'),
    (t, '0b0b0000-0000-0000-0000-000000000002', 'G05', 5, 63250, 75900, 88550, 'NORTH');
  RAISE NOTICE 'PASS 3: ranges per location group where the structure says so';

  INSERT INTO comp.salary_range (tenant_id, range_id, grade, valid_period, minimum, midpoint, maximum, structure_version_id, grade_id)
    VALUES (t, '0b0c1000-0000-0000-0000-000000000001', 'G05', '[2027-01-01,2028-01-01)', 55000, 66000, 77000,
            '0b0b0000-0000-0000-0000-000000000001', '0b0c0000-0000-0000-0000-000000000001');
  INSERT INTO comp.range_catch_up (tenant_id, catch_up_id, assignment_id, range_id, flagged_on, gap_amount, status)
    VALUES (t, '0b0c2000-0000-0000-0000-000000000001', '0b800000-0000-0000-0000-000000000002', '0b0c1000-0000-0000-0000-000000000001', '2027-01-01', 1500, 'open')
    RETURNING target_date INTO d;
  IF d <> '2028-01-01' THEN RAISE EXCEPTION 'FAIL 4a: catch-up target % instead of 12 months later', d; END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'comp.below_minimum_catch_up_months', 'legal_entity', '0b100000-0000-0000-0000-000000000001', '6', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO comp.range_catch_up (tenant_id, assignment_id, range_id, flagged_on, gap_amount, status)
    VALUES (t, '0b800000-0000-0000-0000-000000000001', '0b0c1000-0000-0000-0000-000000000001', '2027-01-01', 800, 'open')
    RETURNING target_date INTO d;
  IF d <> '2027-07-01' THEN RAISE EXCEPTION 'FAIL 4b: the employer''s 6 months not used (%)', d; END IF;
  BEGIN
    UPDATE comp.range_catch_up SET status = 'cancelled' WHERE catch_up_id = '0b0c2000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4c: catch-up cancelled without a reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 4a-c: catch-up to the minimum within the organization''s months; never dropped without a reason';
END $$;

-- ---------------------------------------------------------------------------------
-- 5. Pay decisions: promotion rule, guideline exceptions, HR approval, demotion caution, no self-approval
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r uuid; light uuid;
BEGIN
  SELECT route_id INTO r FROM platform.workflow_route WHERE tenant_id = t AND code = 'comp_decision';
  BEGIN
    INSERT INTO comp.decision (tenant_id, assignment_id, kind, effective_date, status, current_rate, new_rate, new_range_minimum, requested_by)
      VALUES (t, '0b800000-0000-0000-0000-000000000001', 'promotion', '2027-02-01', 'proposed', 60000, 62000, 61000, '0ba00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 5a: promotion of 3.3%% accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PROMOTION_BELOW_RULE%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO comp.decision (tenant_id, assignment_id, kind, effective_date, status, current_rate, new_rate, new_range_minimum, requested_by)
      VALUES (t, '0b800000-0000-0000-0000-000000000001', 'promotion', '2027-02-01', 'proposed', 60000, 64000, 65000, '0ba00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 5a: promotion below the new minimum accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PROMOTION_BELOW_RULE%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  INSERT INTO comp.decision (tenant_id, decision_id, assignment_id, kind, effective_date, status, current_rate, new_rate, new_range_minimum, requested_by, route_id)
    VALUES (t, '0b0d1000-0000-0000-0000-000000000001', '0b800000-0000-0000-0000-000000000001', 'promotion', '2027-02-01', 'proposed', 60000, 63000, 61000,
            '0ba00000-0000-0000-0000-000000000005', r);
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'comp_decision', '0b0d1000-0000-0000-0000-000000000001', 1, 'approved', '0ba00000-0000-0000-0000-000000000005', now(), 'manager');
    RAISE EXCEPTION 'FAIL 5b: the manager approved their own recommendation';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 5b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'comp_decision', '0b0d1000-0000-0000-0000-000000000001', 1, 'approved', '0ba00000-0000-0000-0000-000000000004', now(), 'manager'),
    (t, 'comp_decision', '0b0d1000-0000-0000-0000-000000000001', 2, 'approved', '0ba00000-0000-0000-0000-000000000002', now(), 'hr');
  UPDATE comp.decision SET status = 'approved' WHERE decision_id = '0b0d1000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 5a-b: a promotion reaches the new minimum and 5%%; approved through the route, never by the person who proposed it';

  -- Outside the guideline: a reason, then HR's approval even where the organization's route has no HR step
  BEGIN
    INSERT INTO comp.decision (tenant_id, assignment_id, kind, effective_date, status, percent, guideline_percent, out_of_guideline, requested_by)
      VALUES (t, '0b800000-0000-0000-0000-000000000002', 'merit', '2027-04-01', 'proposed', 6, 3, true, '0ba00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 5c: exception without a reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CYCLE_EXCEPTION_REASON_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 5c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.workflow_route (tenant_id, route_id, code, subject_type, name_en, conditions, priority, status)
    VALUES (t, gen_random_uuid(), 'comp_decision_light', 'comp_decision', 'Manager only', '{}', 20, 'active') RETURNING route_id INTO light;
  INSERT INTO platform.workflow_route_step (tenant_id, route_id, step_no, approver_kind, capability, mode, min_approvals)
    VALUES (t, light, 1, 'capability', 'manager', 'any', 1);
  INSERT INTO comp.decision (tenant_id, decision_id, assignment_id, kind, effective_date, status, percent, guideline_percent, out_of_guideline, reason, requested_by, route_id)
    VALUES (t, '0b0d1000-0000-0000-0000-000000000002', '0b800000-0000-0000-0000-000000000002', 'merit', '2027-04-01', 'proposed', 6, 3, true,
            'Below the range minimum after the structure change', '0ba00000-0000-0000-0000-000000000005', light);
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'comp_decision', '0b0d1000-0000-0000-0000-000000000002', 1, 'approved', '0ba00000-0000-0000-0000-000000000004', now(), 'manager');
  BEGIN
    UPDATE comp.decision SET status = 'approved' WHERE decision_id = '0b0d1000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 5d: exception approved without HR';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'HR_APPROVAL_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 5d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'comp_decision', '0b0d1000-0000-0000-0000-000000000002', 2, 'approved', '0ba00000-0000-0000-0000-000000000002', now(), 'hr');
  UPDATE comp.decision SET status = 'approved' WHERE decision_id = '0b0d1000-0000-0000-0000-000000000002';
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'cycles.out_of_guideline', 'legal_entity', '0b100000-0000-0000-0000-000000000001', '"blocked"', '[2027-06-01,)', gen_random_uuid());
  BEGIN
    INSERT INTO comp.decision (tenant_id, assignment_id, kind, effective_date, status, percent, out_of_guideline, reason, requested_by)
      VALUES (t, '0b800000-0000-0000-0000-000000000002', 'merit', '2027-07-01', 'proposed', 6, true, 'Retention', '0ba00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 5e: exception accepted where the employer blocks them';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'OUT_OF_GUIDELINE_BLOCKED%' THEN RAISE EXCEPTION 'FAIL 5e: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 5c-e: exceptions need a reason and HR''s approval; an employer can block them';

  -- A pay cut on a demotion needs the caution with its reason
  INSERT INTO comp.decision (tenant_id, decision_id, assignment_id, kind, effective_date, status, current_rate, new_rate, requested_by, route_id)
    VALUES (t, '0b0d1000-0000-0000-0000-000000000003', '0b800000-0000-0000-0000-000000000002', 'demotion', '2027-03-01', 'proposed', 70000, 66000,
            '0ba00000-0000-0000-0000-000000000005', r);
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'comp_decision', '0b0d1000-0000-0000-0000-000000000003', 1, 'approved', '0ba00000-0000-0000-0000-000000000004', now(), 'manager'),
    (t, 'comp_decision', '0b0d1000-0000-0000-0000-000000000003', 2, 'approved', '0ba00000-0000-0000-0000-000000000002', now(), 'hr');
  BEGIN
    UPDATE comp.decision SET status = 'approved' WHERE decision_id = '0b0d1000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 5f: pay cut approved without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 5f: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'comp.pay_reduced_on_demotion', 'comp_decision', '0b0d1000-0000-0000-0000-000000000003', 'shown', 'en', '0ba00000-0000-0000-0000-000000000002',
            'Voluntary move to a lower job at the employee''s written request');
  UPDATE comp.decision SET status = 'approved' WHERE decision_id = '0b0d1000-0000-0000-0000-000000000003';
  RAISE NOTICE 'PASS 5f: a pay cut on a demotion needs the caution and its reason';
END $$;

-- ---------------------------------------------------------------------------------
-- 6. Cycles start from the settings; 7. incentives, clawbacks and long-term grants
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; c comp.cycle; p comp.incentive_plan; r uuid;
BEGIN
  INSERT INTO comp.cycle (tenant_id, name, effective_date, status) VALUES (t, '2027 merit', '2027-04-01', 'planning') RETURNING * INTO c;
  IF c.guideline_method <> 'matrix' OR c.letter_release <> 'hr_review' OR (c.eligibility ->> 'excludeHiredWithinMonths')::int <> 3 THEN
    RAISE EXCEPTION 'FAIL 6: cycle did not start from the settings';
  END IF;
  RAISE NOTICE 'PASS 6: a cycle starts from the organization''s eligibility, guideline method and letter release';

  INSERT INTO comp.incentive_plan (tenant_id, plan_id, code, name_en, kind, rules, clawback, status)
    VALUES (t, '0b0e1000-0000-0000-0000-000000000001', 'RET', 'Retention bonus', 'retention', '{}', '{"months":12,"shareRecovered":"1"}', 'active')
    RETURNING * INTO p;
  IF p.proration <> 'eligible_days' THEN RAISE EXCEPTION 'FAIL 7a: plan proration %', p.proration; END IF;
  BEGIN
    INSERT INTO comp.incentive_award (tenant_id, plan_id, assignment_id, amount, requested_by, status, clawback_until)
      VALUES (t, '0b0e1000-0000-0000-0000-000000000001', '0b800000-0000-0000-0000-000000000001', 5000, '0ba00000-0000-0000-0000-000000000005', 'proposed', '2028-02-01');
    RAISE EXCEPTION 'FAIL 7b: clawback without a signed agreement';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CLAWBACK_NOT_SIGNED%' THEN RAISE EXCEPTION 'FAIL 7b: %', SQLERRM; END IF;
  END;
  INSERT INTO payroll.recovery_authorization (tenant_id, authorization_id, employment_id, kind, description, amount, document_id, signed_on)
    VALUES (t, '0b0e2000-0000-0000-0000-000000000001', '0b700000-0000-0000-0000-000000000001', 'bonus_clawback', 'Retention bonus repayable within 12 months',
            5000, '0bd00000-0000-0000-0000-000000000001', '2027-01-20');
  SELECT route_id INTO r FROM platform.workflow_route WHERE tenant_id = t AND code = 'incentive_payout';
  INSERT INTO comp.incentive_award (tenant_id, award_id, plan_id, assignment_id, amount, requested_by, route_id, status, clawback_until, clawback_authorization_id)
    VALUES (t, '0b0e3000-0000-0000-0000-000000000001', '0b0e1000-0000-0000-0000-000000000001', '0b800000-0000-0000-0000-000000000001', 5000,
            '0ba00000-0000-0000-0000-000000000001', r, 'proposed', '2028-02-01', '0b0e2000-0000-0000-0000-000000000001');
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'incentive_payout', '0b0e3000-0000-0000-0000-000000000001', 1, 'approved', '0ba00000-0000-0000-0000-000000000005', now(), 'manager'),
    (t, 'incentive_payout', '0b0e3000-0000-0000-0000-000000000001', 2, 'approved', '0ba00000-0000-0000-0000-000000000002', now(), 'hr');
  BEGIN
    UPDATE comp.incentive_award SET status = 'approved' WHERE award_id = '0b0e3000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7c: payout approved without finance';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 7c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'incentive_payout', '0b0e3000-0000-0000-0000-000000000001', 3, 'approved', '0ba00000-0000-0000-0000-000000000003', now(), 'finance');
  UPDATE comp.incentive_award SET status = 'approved' WHERE award_id = '0b0e3000-0000-0000-0000-000000000001';
  BEGIN
    INSERT INTO comp.lti_grant (tenant_id, plan_id, employment_id, instrument, grant_date, units, vesting, status)
      VALUES (t, '0b0e1000-0000-0000-0000-000000000001', '0b700000-0000-0000-0000-000000000001', 'phantom_unit', '2027-01-15', 1000,
              '[{"date":"2028-01-15","units":"500"},{"date":"2029-01-15","units":"500"}]', 'granted');
    RAISE EXCEPTION 'FAIL 7d: long-term grant on a retention plan';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LTI_PLAN_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7d: %', SQLERRM; END IF;
  END;
  INSERT INTO comp.incentive_plan (tenant_id, plan_id, code, name_en, kind, rules, status)
    VALUES (t, '0b0e1000-0000-0000-0000-000000000002', 'PHANTOM', 'Phantom unit plan', 'long_term', '{}', 'active');
  INSERT INTO comp.lti_grant (tenant_id, plan_id, employment_id, instrument, grant_date, units, vesting, status)
    VALUES (t, '0b0e1000-0000-0000-0000-000000000002', '0b700000-0000-0000-0000-000000000001', 'phantom_unit', '2027-01-15', 1000,
            '[{"date":"2028-01-15","units":"500"},{"date":"2029-01-15","units":"500"}]', 'granted');
  RAISE NOTICE 'PASS 7a-d: plans prorate by the setting; clawbacks need the signed agreement; payouts through the route; grants tracked on long-term plans';
END $$;

-- ---------------------------------------------------------------------------------
-- 8. Salary disclosure lists; 9. bargaining scenarios
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r uuid;
BEGIN
  SELECT route_id INTO r FROM platform.workflow_route WHERE tenant_id = t AND code = 'salary_disclosure';
  INSERT INTO compliance.salary_disclosure (tenant_id, disclosure_id, legal_entity_id, statute, year, prepared_by, route_id, status)
    VALUES (t, '0b0f1000-0000-0000-0000-000000000001', '0b100000-0000-0000-0000-000000000001', 'BC_FIA_REMUNERATION', 2027, '0ba00000-0000-0000-0000-000000000001', r, 'draft');
  BEGIN
    UPDATE compliance.salary_disclosure SET status = 'published', published_at = now() WHERE disclosure_id = '0b0f1000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8: list published before it was approved';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'DISCLOSURE_NOT_APPROVED%' THEN RAISE EXCEPTION 'FAIL 8: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability) VALUES
    (t, 'salary_disclosure', '0b0f1000-0000-0000-0000-000000000001', 1, 'approved', '0ba00000-0000-0000-0000-000000000002', now(), 'hr'),
    (t, 'salary_disclosure', '0b0f1000-0000-0000-0000-000000000001', 2, 'approved', '0ba00000-0000-0000-0000-000000000003', now(), 'finance');
  UPDATE compliance.salary_disclosure SET status = 'approved' WHERE disclosure_id = '0b0f1000-0000-0000-0000-000000000001';
  UPDATE compliance.salary_disclosure SET status = 'published', published_at = now() WHERE disclosure_id = '0b0f1000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 8: a disclosure list is reviewed by HR and finance before it is published';

  INSERT INTO core.agreement (tenant_id, agreement_id, name, union_name, jurisdiction, status, bargaining_employer_entity_id)
    VALUES (t, 'CUPE-T', 'Test agreement', 'CUPE', 'BC', 'in_bargaining', '0b100000-0000-0000-0000-000000000001');
  BEGIN
    INSERT INTO comp.bargaining_scenario (tenant_id, agreement_id, name, term, proposals, prepared_by, shared_at, status)
      VALUES (t, 'CUPE-T', 'Union proposal 1', '[2027-01-01,2030-01-01)', '{"generalIncreases":["3","3","3"]}', '0ba00000-0000-0000-0000-000000000001', now(), 'ratified');
    RAISE EXCEPTION 'FAIL 9: scenario marked ratified without the ratified agreement version';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO comp.bargaining_scenario (tenant_id, agreement_id, name, term, proposals, prepared_by, shared_at, status)
    VALUES (t, 'CUPE-T', 'Union proposal 1', '[2027-01-01,2030-01-01)', '{"generalIncreases":["3","3","3"]}', '0ba00000-0000-0000-0000-000000000001', now(), 'shared');
  RAISE NOTICE 'PASS 9: bargaining is costed in scenarios; only a ratified agreement version changes pay';
END $$;

-- ---------------------------------------------------------------------------------
-- 10. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', 'b2222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM comp.philosophy) <> 0 OR (SELECT count(*) FROM comp.incentive_award) <> 0
     OR (SELECT count(*) FROM comp.range_catch_up) <> 0 OR (SELECT count(*) FROM compliance.salary_disclosure) <> 0
     OR (SELECT count(*) FROM comp.bargaining_scenario) <> 0 OR (SELECT count(*) FROM comp.lti_grant) <> 0 THEN
    RAISE EXCEPTION 'FAIL 10: another organization''s compensation data is visible';
  END IF;
  RAISE NOTICE 'PASS 10: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0011_smoke: all checks passed'
