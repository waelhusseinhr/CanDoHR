-- Smoke test for migration 0003 (docs/17). Run as a superuser after every migration (0001 to 0008), as CI does;
-- it switches to cando_app (no BYPASSRLS) for the tenant checks. Run in a disposable database.
\set ON_ERROR_STOP 1
DO $$ BEGIN CREATE ROLE cando_app LOGIN NOBYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT USAGE ON SCHEMA core, payroll, timeleave, finance TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA core, payroll, timeleave, finance TO cando_app;
-- Every organization exists in platform.tenant before it has data (0008: lists and languages come with it)
INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Tenant A'),
  ('22222222-2222-2222-2222-222222222222', 'Tenant B')
ON CONFLICT DO NOTHING;

-- 1. Every new tenant table has RLS forced
DO $$
DECLARE missing text;
BEGIN
  SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO missing
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r' AND n.nspname IN ('core','finance','payroll','timeleave')
    AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attname = 'tenant_id')
    AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'RLS missing on: %', missing; END IF;
  RAISE NOTICE 'PASS 1: RLS forced on every tenant table';
END $$;

SET ROLE cando_app;
SET app.tenant_id = '11111111-1111-1111-1111-111111111111';

-- Fixtures for tenant A
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001');
INSERT INTO core.hierarchy (tenant_id, hierarchy_id, code, kind, name_en)
  VALUES (current_setting('app.tenant_id')::uuid, 'bbbbbbbb-0000-0000-0000-000000000001', 'MGMT', 'management', 'Management');
INSERT INTO core.org_level_type (tenant_id, hierarchy_id, code, name_en, rank)
  VALUES (current_setting('app.tenant_id')::uuid, 'bbbbbbbb-0000-0000-0000-000000000001', 'CLUSTER', 'Cluster', 2),
         (current_setting('app.tenant_id')::uuid, 'bbbbbbbb-0000-0000-0000-000000000001', 'SECTION', 'Section', 4);
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, 'cccccccc-0000-0000-0000-000000000001');
-- 2. A tenant-defined level type is accepted now that the fixed list is gone
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, hierarchy_id, level_type_code)
  VALUES (current_setting('app.tenant_id')::uuid, 'cccccccc-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(),
          'aaaaaaaa-0000-0000-0000-000000000001', 'CLUSTER', 'CS', 'Community Services', 'bbbbbbbb-0000-0000-0000-000000000001', 'CLUSTER');
\echo PASS 2: tenant-defined level type accepted

-- 3. level_type_code must equal unit_type
DO $$ BEGIN
  INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, level_type_code)
    VALUES (current_setting('app.tenant_id')::uuid, 'cccccccc-0000-0000-0000-000000000001', '[2025-01-01,2025-06-01)', gen_random_uuid(),
            'aaaaaaaa-0000-0000-0000-000000000001', 'SECTION', 'X', 'X', 'CLUSTER');
  RAISE EXCEPTION 'FAIL 3: mismatched level accepted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 3: level/type mismatch rejected';
END $$;

-- 4. Second management hierarchy rejected
DO $$ BEGIN
  INSERT INTO core.hierarchy (tenant_id, code, kind, name_en) VALUES (current_setting('app.tenant_id')::uuid, 'MGMT2', 'management', 'Second');
  RAISE EXCEPTION 'FAIL 4';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS 4: one management hierarchy per tenant';
END $$;

-- 5. Fiscal calendar with non-overlapping periods
INSERT INTO finance.calendar (tenant_id, calendar_id, code, kind, owner_type, name_en)
  VALUES (current_setting('app.tenant_id')::uuid, 'dddddddd-0000-0000-0000-000000000001', 'FY-APR', 'funder', 'funding_source', 'Funder year Apr-Mar');
INSERT INTO finance.calendar_period (tenant_id, period_id, calendar_id, year_label, period_no, dates, status)
  VALUES (current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 'FY2026-27', 1, '[2026-04-01,2027-04-01)', 'open');
DO $$ BEGIN
  INSERT INTO finance.calendar_period (tenant_id, calendar_id, year_label, period_no, dates)
    VALUES (current_setting('app.tenant_id')::uuid, 'dddddddd-0000-0000-0000-000000000001', 'FY2026-27', 2, '[2027-03-01,2027-05-01)');
  RAISE EXCEPTION 'FAIL 5';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 5: overlapping calendar periods rejected';
END $$;

-- 6. Funding source: successor policy needs a successor
DO $$ BEGIN
  INSERT INTO finance.funding_source (tenant_id, code, funder_name, legal_entity_id, valid_period, status, eligible_categories, post_close_policy, fallback_segments)
    VALUES (current_setting('app.tenant_id')::uuid, 'BAD', 'Province', 'aaaaaaaa-0000-0000-0000-000000000001', '[2026-04-01,2027-04-01)', 'active', ARRAY['salary'], 'successor', '{}');
  RAISE EXCEPTION 'FAIL 6';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 6: successor policy without successor rejected';
END $$;
INSERT INTO finance.funding_source (tenant_id, funding_source_id, code, funder_name, legal_entity_id, calendar_id, valid_period, status, eligible_categories, fallback_segments)
  VALUES (current_setting('app.tenant_id')::uuid, 'ffffffff-0000-0000-0000-000000000001', 'YOUTH-GRANT', 'Province of Ontario', 'aaaaaaaa-0000-0000-0000-000000000001',
          'dddddddd-0000-0000-0000-000000000001', '[2026-04-01,2027-04-01)', 'active', ARRAY['salary','statutory_burden'], '{"fund":"OPERATING"}');

-- 7. Cost distribution versions cannot overlap for the same target
INSERT INTO core.position (tenant_id, position_id, number) VALUES (current_setting('app.tenant_id')::uuid, '99999999-0000-0000-0000-000000000001', 'P-1001');
INSERT INTO finance.cost_distribution (tenant_id, distribution_id, target_type, target_id)
  VALUES (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000001', 'position', '99999999-0000-0000-0000-000000000001');
INSERT INTO finance.cost_distribution_version (tenant_id, distribution_id, valid_period, change_set_id, lines)
  VALUES (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000001', '[2026-04-01,2027-04-01)', gen_random_uuid(),
          '[{"seq":1,"segments":{"fund":"OPERATING"},"percent":70},{"seq":2,"fundingSourceId":"ffffffff-0000-0000-0000-000000000001","segments":{"fund":"GRANT"},"percent":30}]');
DO $$ BEGIN
  INSERT INTO finance.cost_distribution_version (tenant_id, distribution_id, valid_period, change_set_id, lines)
    VALUES (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000001', '[2027-01-01,)', gen_random_uuid(), '[{"seq":1,"percent":100}]');
  RAISE EXCEPTION 'FAIL 7';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 7: overlapping cost distribution versions rejected';
END $$;
DO $$ BEGIN
  INSERT INTO finance.cost_distribution_version (tenant_id, distribution_id, valid_period, change_set_id, lines)
    VALUES (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000001', '[2027-04-01,)', gen_random_uuid(), '[]');
  RAISE EXCEPTION 'FAIL 7b';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 7b: empty distribution rejected';
END $$;

-- 8. Assignments: new types and statuses; partially approved leave
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, '12121212-0000-0000-0000-000000000001');
INSERT INTO core.person (tenant_id, person_id) VALUES (current_setting('app.tenant_id')::uuid, '77777777-0000-0000-0000-000000000001');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id, employee_number)
  VALUES (current_setting('app.tenant_id')::uuid, '66666666-0000-0000-0000-000000000001', '77777777-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'E1');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '55555555-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '55555555-0000-0000-0000-000000000002', '66666666-0000-0000-0000-000000000001');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, assignment_type, position_id, org_unit_id, location_id, fte, is_primary, status, returns_to_assignment_id)
  VALUES (current_setting('app.tenant_id')::uuid, '55555555-0000-0000-0000-000000000002', '[2026-05-01,2026-07-10)', gen_random_uuid(), 'acting',
          '99999999-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', '12121212-0000-0000-0000-000000000001', 1.0, false, 'active', '55555555-0000-0000-0000-000000000001');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, assignment_type, org_unit_id, location_id, fte, is_primary, status)
  VALUES (current_setting('app.tenant_id')::uuid, '55555555-0000-0000-0000-000000000001', '[2026-05-01,2026-07-10)', gen_random_uuid(), 'term',
          'cccccccc-0000-0000-0000-000000000001', '12121212-0000-0000-0000-000000000001', 0.6, true, 'suspended_for_acting');
\echo PASS 8: term and acting assignments with suspended home assignment accepted
INSERT INTO timeleave.leave_request (tenant_id, leave_request_id, employment_id, leave_type_code, period, hours, status)
  VALUES (current_setting('app.tenant_id')::uuid, '44444444-0000-0000-0000-000000000001', '66666666-0000-0000-0000-000000000001', 'VAC',
          '[2026-08-03 00:00+00,2026-08-08 00:00+00)', 40, 'partially_approved');
INSERT INTO timeleave.leave_request_component (tenant_id, leave_request_id, assignment_id, hours, status, decline_category, decline_reason) VALUES
  (current_setting('app.tenant_id')::uuid, '44444444-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 24, 'approved', NULL, NULL),
  (current_setting('app.tenant_id')::uuid, '44444444-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000002', 16, 'declined', 'staffing', 'Minimum staffing that week');
\echo PASS 8b: leave request split into components

-- 9. One rate per component per assignment
INSERT INTO core.pay_rate (tenant_id, assignment_id, component) VALUES
  (current_setting('app.tenant_id')::uuid, '55555555-0000-0000-0000-000000000001', 'base'),
  (current_setting('app.tenant_id')::uuid, '55555555-0000-0000-0000-000000000001', 'red_circle');
DO $$ BEGIN
  INSERT INTO core.pay_rate (tenant_id, assignment_id, component) VALUES (current_setting('app.tenant_id')::uuid, '55555555-0000-0000-0000-000000000001', 'base');
  RAISE EXCEPTION 'FAIL 9';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS 9: one rate per component';
END $$;

-- 10. External pay coverage cannot overlap (no double pay at go-live)
INSERT INTO core.payroll_account (tenant_id, payroll_account_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
  VALUES (current_setting('app.tenant_id')::uuid, '33333333-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'RP0001', 'regular', '[2026-01-01,)');
INSERT INTO payroll.external_pay_coverage (tenant_id, employment_id, payroll_account_id, covered_work, source, batch_id)
  VALUES (current_setting('app.tenant_id')::uuid, '66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', '[2026-01-01,2026-06-14)', 'legacy', gen_random_uuid());
DO $$ BEGIN
  INSERT INTO payroll.external_pay_coverage (tenant_id, employment_id, payroll_account_id, covered_work, source, batch_id)
    VALUES (current_setting('app.tenant_id')::uuid, '66666666-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', '[2026-06-10,2026-06-20)', 'legacy', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 10';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 10: overlapping external pay coverage rejected';
END $$;

-- 11. GL journal without a pay run (accrual run) with new kind
INSERT INTO payroll.gl_journal (tenant_id, kind, fiscal_year, fiscal_period, lines, source, legal_entity_id, work_period_id, posting_period_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'accrual', 2026, 1, '[]', 'accrual_run', 'aaaaaaaa-0000-0000-0000-000000000001',
          'eeeeeeee-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001');
\echo PASS 11: accrual-run journal without a pay run accepted

-- 12. Tenant isolation on new tables
SET app.tenant_id = '22222222-2222-2222-2222-222222222222';
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM finance.funding_source;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 12: tenant B sees % funding sources', n; END IF;
  SELECT count(*) INTO n FROM core.hierarchy;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL 12: tenant B sees hierarchies'; END IF;
  BEGIN
    INSERT INTO finance.calendar (tenant_id, code, kind, owner_type, name_en)
      VALUES ('11111111-1111-1111-1111-111111111111', 'X', 'fiscal', 'tenant', 'X');
    RAISE EXCEPTION 'FAIL 12b: cross-tenant insert accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS 12: new tables isolated by tenant';
END $$;
RESET ROLE;
\echo ALL CHECKS PASSED
