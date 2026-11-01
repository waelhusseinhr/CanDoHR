-- Smoke test for schema/cando_schema.sql: effective dating, org chart as-of, exclusion constraint, RLS,
-- audit immutability and sealing, pay-run subject leases, rule edition and agreement version immutability.
-- Run: psql -v ON_ERROR_STOP=1 -f schema/cando_schema.sql && psql -f tests/schema/schema_smoke.sql
\set ON_ERROR_STOP 1
DO $$ BEGIN CREATE ROLE cando_app LOGIN NOBYPASSRLS; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('11111111-1111-1111-1111-111111111111', 'Example Municipality'),
  ('22222222-2222-2222-2222-222222222222', 'Other Tenant');

SET ROLE cando_app;
SELECT set_config('app.tenant_id', '11111111-1111-1111-1111-111111111111', false);

-- Reference objects
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001');
-- Whether the employer is a First Nation government has to be stated. Neither answer is a default (docs/22 §3.2).
INSERT INTO core.legal_entity_version (tenant_id, legal_entity_id, valid_period, change_set_id, legal_name, business_number, regulatory_jurisdiction, first_nation_government)
VALUES (current_setting('app.tenant_id')::uuid, 'aaaaaaaa-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Example Municipality', '123456789', 'provincial', false);
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, 'bbbbbbbb-0000-0000-0000-000000000001');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction)
VALUES (current_setting('app.tenant_id')::uuid, 'bbbbbbbb-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'City Hall', '1 Main St', 'Example', 'ON', 'K1A 0B1', 'America/Toronto', 'ON');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, 'cccccccc-0000-0000-0000-000000000001');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en)
VALUES (current_setting('app.tenant_id')::uuid, 'cccccccc-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'aaaaaaaa-0000-0000-0000-000000000001', 'department', 'PW', 'Public Works');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, 'dddddddd-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en)
VALUES (current_setting('app.tenant_id')::uuid, 'dddddddd-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'GEN', 'Generic job');

-- Positions: P1 head; P2 and P3 report to P1; P4 reports to P2
INSERT INTO core.position (tenant_id, position_id, number) VALUES
 (current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000001', 'P1'),
 (current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000002', 'P2'),
 (current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000003', 'P3'),
 (current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000004', 'P4');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status)
SELECT current_setting('app.tenant_id')::uuid, p.id::uuid, '[2026-01-01,)', gen_random_uuid(), 'dddddddd-0000-0000-0000-000000000001',
       'cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', p.parent::uuid, 1.0, 'permanent', 'active'
FROM (VALUES ('eeeeeeee-0000-0000-0000-000000000001', NULL),
             ('eeeeeeee-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000001'),
             ('eeeeeeee-0000-0000-0000-000000000003', 'eeeeeeee-0000-0000-0000-000000000001'),
             ('eeeeeeee-0000-0000-0000-000000000004', 'eeeeeeee-0000-0000-0000-000000000002')) AS p(id, parent);

-- Org chart move: P4 moves from P2 to P3 effective 2026-11-01 (change set commit pattern)
BEGIN;
UPDATE core.position_version SET sys_period = tstzrange(lower(sys_period), now())
 WHERE position_id = 'eeeeeeee-0000-0000-0000-000000000004' AND upper_inf(sys_period);
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
 (current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000004', '[2026-01-01,2026-11-01)', gen_random_uuid(), 'dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000002', 1.0, 'permanent', 'active'),
 (current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000004', '[2026-11-01,)', gen_random_uuid(), 'dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000003', 1.0, 'permanent', 'active');
COMMIT;

\echo '--- P4 parent as of 2026-10-15 (expect P2) and 2026-11-15 (expect P3)'
SELECT p.number AS position, d AS as_of, par.number AS reports_to
FROM (VALUES (date '2026-10-15'), (date '2026-11-15')) AS dates(d)
CROSS JOIN LATERAL core.position_tree_as_of(current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000001', d) t
JOIN core.position p ON p.position_id = t.position_id
LEFT JOIN core.position par ON par.position_id = t.reports_to_position_id
WHERE p.number = 'P4' ORDER BY d;

\echo '--- Overlapping current version must be rejected by the exclusion constraint'
DO $$ BEGIN
  INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, fte_budget, employment_type, status)
  VALUES (current_setting('app.tenant_id')::uuid, 'eeeeeeee-0000-0000-0000-000000000004', '[2026-12-01,)', gen_random_uuid(), 'dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000001', 1.0, 'permanent', 'active');
  RAISE EXCEPTION 'FAIL: overlap accepted';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS: overlap rejected';
END $$;

\echo '--- Row-level security: other tenant sees no positions (expect 0)'
SELECT set_config('app.tenant_id', '22222222-2222-2222-2222-222222222222', false);
SELECT count(*) AS positions_visible_to_other_tenant FROM core.position_version;

\echo '--- Writing a row for another tenant must be rejected'
DO $$ BEGIN
  INSERT INTO core.position (tenant_id, position_id, number) VALUES ('11111111-1111-1111-1111-111111111111', gen_random_uuid(), 'X1');
  RAISE EXCEPTION 'FAIL: cross-tenant insert accepted';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: cross-tenant insert rejected';
END $$;
RESET ROLE;

-- =====================================================================================
-- Design hardening checks: audit sealing, pay-run subject leases, rule immutability
-- =====================================================================================
SET ROLE cando_app;
SELECT set_config('app.tenant_id', '11111111-1111-1111-1111-111111111111', false);

\echo '--- Audit rows: content is immutable; batch_id is set once by the sealer'
INSERT INTO platform.audit_entry (tenant_id, actor_type, actor_id, action, subject_type, subject_id, reason, leaf_hash)
VALUES (current_setting('app.tenant_id')::uuid, 'user', 'user:hr-admin', 'change_set.commit', 'change_set', 'cs-0001', 'REORG', sha256('leaf-1'::bytea));
DO $$ BEGIN
  UPDATE platform.audit_entry SET reason = 'edited' WHERE subject_id = 'cs-0001';
  RAISE EXCEPTION 'FAIL: audit row edited';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: audit row content locked';
END $$;
INSERT INTO platform.audit_batch (tenant_id, batch_no, first_audit_id, last_audit_id, leaf_count, sealed_at, merkle_root, prev_batch_hash, batch_hash, signature, signing_key_id)
SELECT current_setting('app.tenant_id')::uuid, 1, min(audit_id), max(audit_id), count(*), now(), sha256('root'::bytea), sha256(''::bytea), sha256('bh'::bytea), '\x00'::bytea, 'kms-key-test'
FROM platform.audit_entry;
UPDATE platform.audit_entry SET batch_id = (SELECT batch_id FROM platform.audit_batch WHERE batch_no = 1) WHERE batch_id IS NULL;
DO $$ BEGIN
  UPDATE platform.audit_entry SET batch_id = NULL WHERE subject_id = 'cs-0001';
  RAISE EXCEPTION 'FAIL: sealed row moved out of its batch';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: sealed row stays in its batch';
END $$;
DO $$ BEGIN
  DELETE FROM platform.audit_entry WHERE subject_id = 'cs-0001';
  RAISE EXCEPTION 'FAIL: audit row deleted';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: audit row delete rejected (no DELETE grant)';
END $$;
UPDATE platform.audit_batch SET anchor_uri = 's3://anchor/t1/1.json', anchor_version_id = 'v1', anchored_at = now() WHERE batch_no = 1;
DO $$ BEGIN
  UPDATE platform.audit_batch SET merkle_root = sha256('other'::bytea) WHERE batch_no = 1;
  RAISE EXCEPTION 'FAIL: sealed batch root changed';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: sealed batch root locked';
END $$;
DO $$ BEGIN
  UPDATE platform.audit_batch SET anchor_version_id = 'v2' WHERE batch_no = 1;
  RAISE EXCEPTION 'FAIL: anchor rewritten';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: anchor written once';
END $$;

\echo '--- Pay-run subject leases: one open run per person per payroll account'
INSERT INTO core.payroll_account (tenant_id, payroll_account_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
VALUES (current_setting('app.tenant_id')::uuid, 'ffffffff-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'RP0001', 'regular', '[2026-01-01,)');
INSERT INTO core.person (tenant_id, person_id) VALUES (current_setting('app.tenant_id')::uuid, '99999999-0000-0000-0000-000000000001');
INSERT INTO payroll.pay_run (tenant_id, pay_run_id, number, run_type, legal_entity_id, population, pay_date, status, created_by)
VALUES (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000001', 1, 'regular',  'aaaaaaaa-0000-0000-0000-000000000001', '{"mode":"pay_group"}', '2026-10-23', 'inputs_locked', gen_random_uuid()),
       (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000002', 2, 'off_cycle', 'aaaaaaaa-0000-0000-0000-000000000001', '{"mode":"ids"}',       '2026-10-23', 'draft',         gen_random_uuid());
INSERT INTO payroll.pay_run_subject (tenant_id, pay_run_id, payroll_account_id, person_id, bucket)
VALUES (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000001', 'ffffffff-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000001', 0);
DO $$ BEGIN
  INSERT INTO payroll.pay_run_subject (tenant_id, pay_run_id, payroll_account_id, person_id, bucket)
  VALUES (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000002', 'ffffffff-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000001', 0);
  RAISE EXCEPTION 'FAIL: second open run accepted for the same subject';
EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'PASS: SUBJECT_IN_OPEN_RUN enforced';
END $$;
UPDATE payroll.pay_run_subject SET released_at = now() WHERE pay_run_id = '88888888-0000-0000-0000-000000000001';
INSERT INTO payroll.pay_run_subject (tenant_id, pay_run_id, payroll_account_id, person_id, bucket)
VALUES (current_setting('app.tenant_id')::uuid, '88888888-0000-0000-0000-000000000002', 'ffffffff-0000-0000-0000-000000000001', '99999999-0000-0000-0000-000000000001', 0);
\echo 'PASS: lease available again after the first run releases it'
RESET ROLE;

\echo '--- Even a superuser cannot delete or rewrite a sealed audit row (trigger)'
DO $$ BEGIN
  DELETE FROM platform.audit_entry WHERE subject_id = 'cs-0001';
  RAISE EXCEPTION 'FAIL: superuser deleted audit row';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: superuser delete rejected';
END $$;

\echo '--- Rule editions: editable as draft, frozen once tested, status only moves forward'
INSERT INTO ref.rule_edition (edition_id, family, tax_year, effective_from, effective_to, content, content_sha256, status)
VALUES ('TEST-2099-01-01', 'statutory', 2099, '2099-01-01', '2099-06-30', '{"v":1}', 'h1', 'draft');
UPDATE ref.rule_edition SET content = '{"v":2}', content_sha256 = 'h2' WHERE edition_id = 'TEST-2099-01-01';
UPDATE ref.rule_edition SET status = 'tested' WHERE edition_id = 'TEST-2099-01-01';
DO $$ BEGIN
  UPDATE ref.rule_edition SET content = '{"v":3}' WHERE edition_id = 'TEST-2099-01-01';
  RAISE EXCEPTION 'FAIL: tested edition edited';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: tested edition content locked';
END $$;
DO $$ BEGIN
  UPDATE ref.rule_edition SET status = 'draft' WHERE edition_id = 'TEST-2099-01-01';
  RAISE EXCEPTION 'FAIL: status moved backwards';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: status only moves forward';
END $$;
DO $$ BEGIN
  DELETE FROM ref.rule_edition WHERE edition_id = 'TEST-2099-01-01';
  RAISE EXCEPTION 'FAIL: tested edition deleted';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: tested edition delete rejected';
END $$;

\echo '--- Agreement versions: frozen once verified'
SELECT set_config('app.tenant_id', '11111111-1111-1111-1111-111111111111', false);
INSERT INTO core.agreement (tenant_id, agreement_id, name, union_name, jurisdiction, status, bargaining_employer_entity_id)
VALUES ('11111111-1111-1111-1111-111111111111', 'TEST-AGR', 'Test agreement', 'Test union', 'ON', 'in_force', 'aaaaaaaa-0000-0000-0000-000000000001');
INSERT INTO core.agreement_version (tenant_id, agreement_id, version, effective_from, rules, content_sha256, status)
VALUES ('11111111-1111-1111-1111-111111111111', 'TEST-AGR', 1, '2026-01-01', '{"premiums":[]}', 'h1', 'verified');
DO $$ BEGIN
  UPDATE core.agreement_version SET rules = '{"premiums":[{"code":"X"}]}' WHERE agreement_id = 'TEST-AGR';
  RAISE EXCEPTION 'FAIL: verified agreement edited';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS: verified agreement version locked';
END $$;
UPDATE core.agreement_version SET status = 'active' WHERE agreement_id = 'TEST-AGR';
\echo 'PASS: status may still move forward (verified -> active)'
