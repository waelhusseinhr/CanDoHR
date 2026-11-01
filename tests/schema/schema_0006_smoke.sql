-- Smoke test for schema/0006_several_positions.sql (docs/20): end reasons, approval policy and coverage for a
-- position with two managers, approval parts with self-approval and decision rules and their roll-up into leave
-- requests, pay items and duty rates per position, one-time payment targets, review sections and the overall
-- score, competency gaps that prefer the position's own assessment, benefit plans per agreement, benefit-change
-- rules and decisions with the statutory floor, tenant isolation and RLS on every new table.
-- Run after every migration, 0001 to 0008 (CI, after the 0005 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0006_smoke.sql
-- It inserts test rows; run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, comp, talent, benefits TO cando_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA core, payroll, timeleave, comp, talent, benefits TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref, platform TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA platform, core, ref, comp, talent, benefits TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('61111111-1111-1111-1111-111111111111', 'Several Positions Tenant'),
  ('62222222-2222-2222-2222-222222222222', 'Other Tenant')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', '61111111-1111-1111-1111-111111111111', false) AS cfg \gset
SELECT set_config('app.roles', 'hr_admin', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- Fixtures: Jordan holds A1 (Program Coordinator, 0.6) and A2 (Lifeguard, 0.4); M1 and M2 manage them
-- ---------------------------------------------------------------------------------
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, 'a6000000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, 'b6000000-0000-0000-0000-000000000001');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, 'c6000000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'd6000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'd6000000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, 'd6000000-0000-0000-0000-000000000003');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en) VALUES
  (current_setting('app.tenant_id')::uuid, 'd6000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'CSV-GEN-P2', 'Program Coordinator'),
  (current_setting('app.tenant_id')::uuid, 'd6000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'FAC-AQU-S2', 'Lifeguard-Instructor'),
  (current_setting('app.tenant_id')::uuid, 'd6000000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'CSV-GEN-M2', 'Program Manager');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, 'e6000000-0000-0000-0000-000000000001', 'PC-001'),
  (current_setting('app.tenant_id')::uuid, 'e6000000-0000-0000-0000-000000000002', 'LG-001'),
  (current_setting('app.tenant_id')::uuid, 'e6000000-0000-0000-0000-000000000003', 'MGR-1'),
  (current_setting('app.tenant_id')::uuid, 'e6000000-0000-0000-0000-000000000004', 'MGR-2');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, 'e6000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'd6000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 0.6, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e6000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'd6000000-0000-0000-0000-000000000002', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 0.4, 'casual', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e6000000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'd6000000-0000-0000-0000-000000000003', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e6000000-0000-0000-0000-000000000004', '[2020-01-01,)', gen_random_uuid(), 'd6000000-0000-0000-0000-000000000003', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 1, 'permanent', 'active');
INSERT INTO core.agreement (tenant_id, agreement_id, name, union_name, jurisdiction, status, bargaining_employer_entity_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'PT', 'Part-time recreation agreement', 'Local 1', 'ON', 'in_force', 'a6000000-0000-0000-0000-000000000001');
INSERT INTO core.person (tenant_id, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f6000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'f6000000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, 'f6000000-0000-0000-0000-000000000003');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id, employee_number) VALUES
  (current_setting('app.tenant_id')::uuid, '06100000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000001', 'E-601'),
  (current_setting('app.tenant_id')::uuid, '06100000-0000-0000-0000-000000000002', 'f6000000-0000-0000-0000-000000000002', 'a6000000-0000-0000-0000-000000000001', 'E-602'),
  (current_setting('app.tenant_id')::uuid, '06100000-0000-0000-0000-000000000003', 'f6000000-0000-0000-0000-000000000003', 'a6000000-0000-0000-0000-000000000001', 'E-603');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000001', '06100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000002', '06100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000003', '06100000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000004', '06100000-0000-0000-0000-000000000003');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, agreement_id) VALUES
  (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000001', '[2024-04-01,)', gen_random_uuid(), 'e6000000-0000-0000-0000-000000000001', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 0.6, true, NULL),
  (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000002', '[2025-01-01,2027-03-16)', gen_random_uuid(), 'e6000000-0000-0000-0000-000000000002', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 0.4, false, 'PT'),
  (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'e6000000-0000-0000-0000-000000000003', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 1, true, NULL),
  (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000004', '[2020-01-01,)', gen_random_uuid(), 'e6000000-0000-0000-0000-000000000004', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 1, true, NULL);
-- A1 also reports to M2 on a program relationship (two managers on one position)
INSERT INTO core.assignment_relationship (tenant_id, relationship_id, assignment_id, related_assignment_id, kind, valid_period, change_set_id, relationship_type_code)
  VALUES (current_setting('app.tenant_id')::uuid, '06300000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000001',
          '06200000-0000-0000-0000-000000000004', 'dotted', '[2024-04-01,)', gen_random_uuid(), 'program');

-- 1. End reasons: the tenant's list, and assignments can only use reasons on it
INSERT INTO core.end_reason (tenant_id, code, name_en, category, employer_initiated) VALUES
  (current_setting('app.tenant_id')::uuid, 'RESIGNED', 'Resigned from this position', 'resignation', false),
  (current_setting('app.tenant_id')::uuid, 'ELIMINATED', 'Position eliminated', 'position_eliminated', true),
  (current_setting('app.tenant_id')::uuid, 'OTHER', 'Other', 'other', false);
DO $$ BEGIN
  INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, status, end_reason)
    VALUES (current_setting('app.tenant_id')::uuid, '06200000-0000-0000-0000-000000000002', '[2027-03-16,2027-03-17)', gen_random_uuid(),
            'e6000000-0000-0000-0000-000000000002', 'c6000000-0000-0000-0000-000000000001', 'b6000000-0000-0000-0000-000000000001', 0.4, false, 'ended', 'QUIT');
  RAISE EXCEPTION 'FAIL 1';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PASS 1: an end reason must be on the tenant''s list';
END $$;

-- 2. Approval policy per position and capability, one at a time
INSERT INTO core.approval_policy (tenant_id, target_type, target_id, capability, mode, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e6000000-0000-0000-0000-000000000001', 'leave', 'by_coverage', '[2024-04-01,)', gen_random_uuid());
DO $$ BEGIN
  INSERT INTO core.approval_policy (tenant_id, target_type, target_id, capability, mode, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e6000000-0000-0000-0000-000000000001', 'leave', 'all', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 2';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 2: one approval policy per position and capability per day';
END $$;

-- 3. Coverage: the line manager supervises Monday-Wednesday, the program manager Thursday-Friday
INSERT INTO core.approval_coverage (tenant_id, target_type, target_id, approver, relationship_id, days_of_week, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'position', 'e6000000-0000-0000-0000-000000000001', 'line', NULL, ARRAY[1,2,3]::smallint[], '[2024-04-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, 'position', 'e6000000-0000-0000-0000-000000000001', 'relationship', '06300000-0000-0000-0000-000000000001', ARRAY[4,5]::smallint[], '[2024-04-01,)', gen_random_uuid());
DO $$ BEGIN
  BEGIN
    INSERT INTO core.approval_coverage (tenant_id, target_type, target_id, approver, time_windows, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e6000000-0000-0000-0000-000000000002', 'line', '[["25:00","06:00"]]', '[2024-04-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 3a';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'COVERAGE_WINDOW_INVALID%' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO core.approval_coverage (tenant_id, target_type, target_id, approver, days_of_week, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e6000000-0000-0000-0000-000000000002', 'line', ARRAY[0]::smallint[], '[2024-04-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 3b';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO core.approval_coverage (tenant_id, target_type, target_id, approver, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e6000000-0000-0000-0000-000000000002', 'line', '[2024-04-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 3c';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO core.approval_coverage (tenant_id, target_type, target_id, approver, time_windows, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e6000000-0000-0000-0000-000000000002', 'line', '[["22:00","06:00"]]', '[2024-04-01,)', gen_random_uuid());
  RAISE NOTICE 'PASS 3: coverage by days and by overnight hours accepted; bad windows, days and empty coverage refused';
END $$;

-- 4. A sick-leave request covering both positions, split into one part per position
INSERT INTO timeleave.leave_request (tenant_id, leave_request_id, employment_id, leave_type_code, period, hours, status)
  VALUES (current_setting('app.tenant_id')::uuid, '06400000-0000-0000-0000-000000000001', '06100000-0000-0000-0000-000000000001', 'SICK',
          '[2027-03-03 00:00-05,2027-03-05 00:00-05)', 15, 'requested');
INSERT INTO timeleave.leave_request_component (tenant_id, leave_request_id, assignment_id, plan_code, hours, status) VALUES
  (current_setting('app.tenant_id')::uuid, '06400000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000001', 'IO-VAC-SICK', 7.5, 'requested'),
  (current_setting('app.tenant_id')::uuid, '06400000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000002', 'PT-SICK', 7.5, 'requested');
DO $$ BEGIN
  INSERT INTO core.approval_part (tenant_id, subject_type, subject_id, assignment_id, seq, requester_person_id, approvers, rule, minutes, routed_by)
    VALUES (current_setting('app.tenant_id')::uuid, 'leave_request', '06400000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000001', 9,
            'f6000000-0000-0000-0000-000000000001', ARRAY['06200000-0000-0000-0000-000000000002']::uuid[], 'any', 450, 'coverage');
  RAISE EXCEPTION 'FAIL 4a';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 4a: Jordan cannot approve her own request from her other position';
END $$;
INSERT INTO core.approval_part (tenant_id, part_id, subject_type, subject_id, assignment_id, seq, requester_person_id, approvers, rule, minutes, routed_by) VALUES
  (current_setting('app.tenant_id')::uuid, '06500000-0000-0000-0000-000000000001', 'leave_request', '06400000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000001', 1,
   'f6000000-0000-0000-0000-000000000001', ARRAY['06200000-0000-0000-0000-000000000003']::uuid[], 'any', 450, 'coverage'),
  (current_setting('app.tenant_id')::uuid, '06500000-0000-0000-0000-000000000002', 'leave_request', '06400000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000002', 1,
   'f6000000-0000-0000-0000-000000000001', ARRAY['06200000-0000-0000-0000-000000000004']::uuid[], 'any', 450, 'coverage');
DO $$ BEGIN
  UPDATE core.approval_part SET decisions = '[{"approver": "06200000-0000-0000-0000-000000000004", "decision": "approve"}]'
    WHERE part_id = '06500000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 4b';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'DECISION_NOT_ALLOWED%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 4b: only the part''s own approver decides it';
END $$;
UPDATE core.approval_part SET decisions = '[{"approver": "06200000-0000-0000-0000-000000000003", "decision": "approve"}]'
  WHERE part_id = '06500000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF (SELECT status FROM core.approval_part WHERE part_id = '06500000-0000-0000-0000-000000000001') <> 'approved'
     OR (SELECT status FROM timeleave.leave_request_component WHERE assignment_id = '06200000-0000-0000-0000-000000000001') <> 'approved'
     OR (SELECT status FROM timeleave.leave_request WHERE leave_request_id = '06400000-0000-0000-0000-000000000001') <> 'requested' THEN
    RAISE EXCEPTION 'FAIL 4c';
  END IF;
  RAISE NOTICE 'PASS 4c: A1 part approved; A1 component approved; the request waits for A2';
END $$;
UPDATE core.approval_part SET decisions = '[{"approver": "06200000-0000-0000-0000-000000000004", "decision": "decline", "category": "staffing", "reason": "Two of three staff already away that week"}]'
  WHERE part_id = '06500000-0000-0000-0000-000000000002';
DO $$ BEGIN
  IF (SELECT status FROM timeleave.leave_request WHERE leave_request_id = '06400000-0000-0000-0000-000000000001') <> 'partially_approved'
     OR (SELECT status FROM timeleave.leave_request_component WHERE assignment_id = '06200000-0000-0000-0000-000000000002') <> 'declined' THEN
    RAISE EXCEPTION 'FAIL 4d';
  END IF;
  RAISE NOTICE 'PASS 4d: A2 declined; the request is partially approved';
END $$;
DO $$ BEGIN
  UPDATE core.approval_part SET decisions = '[]' WHERE part_id = '06500000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL 4e';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE 'APPROVAL_PART_IMMUTABLE%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 4e: a decided part cannot be rewritten';
END $$;
UPDATE core.approval_part SET status = 'cancelled' WHERE part_id = '06500000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF (SELECT status FROM timeleave.leave_request_component WHERE assignment_id = '06200000-0000-0000-0000-000000000001') <> 'cancelled'
     OR (SELECT status FROM timeleave.leave_request WHERE leave_request_id = '06400000-0000-0000-0000-000000000001') <> 'declined' THEN
    RAISE EXCEPTION 'FAIL 4f';
  END IF;
  RAISE NOTICE 'PASS 4f: Jordan cancels the approved A1 part; what remains is declined';
END $$;

-- 5. A part that both managers must approve
INSERT INTO core.approval_part (tenant_id, part_id, subject_type, subject_id, assignment_id, seq, requester_person_id, approvers, rule, minutes, routed_by)
  VALUES (current_setting('app.tenant_id')::uuid, '06500000-0000-0000-0000-000000000003', 'timesheet', gen_random_uuid(), '06200000-0000-0000-0000-000000000001', 1,
          'f6000000-0000-0000-0000-000000000001', ARRAY['06200000-0000-0000-0000-000000000003','06200000-0000-0000-0000-000000000004']::uuid[], 'all', 900, 'all');
UPDATE core.approval_part SET decisions = '[{"approver": "06200000-0000-0000-0000-000000000003", "decision": "approve"}]'
  WHERE part_id = '06500000-0000-0000-0000-000000000003';
DO $$ BEGIN
  IF (SELECT status FROM core.approval_part WHERE part_id = '06500000-0000-0000-0000-000000000003') <> 'pending' THEN RAISE EXCEPTION 'FAIL 5a'; END IF;
  BEGIN
    UPDATE core.approval_part SET decisions = '[{"approver": "06200000-0000-0000-0000-000000000003", "decision": "approve"}, {"approver": "06200000-0000-0000-0000-000000000003", "decision": "approve"}]'
      WHERE part_id = '06500000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 5b';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'DECISION_TWICE%' THEN RAISE; END IF;
  END;
  UPDATE core.approval_part SET decisions = '[{"approver": "06200000-0000-0000-0000-000000000003", "decision": "approve"}, {"approver": "06200000-0000-0000-0000-000000000004", "decision": "approve"}]'
    WHERE part_id = '06500000-0000-0000-0000-000000000003';
  IF (SELECT status FROM core.approval_part WHERE part_id = '06500000-0000-0000-0000-000000000003') <> 'approved' THEN RAISE EXCEPTION 'FAIL 5c'; END IF;
  RAISE NOTICE 'PASS 5: one approval leaves a "both" part pending; the second approves it; nobody decides twice';
END $$;

-- 6. Pay items and duty rates per position
INSERT INTO payroll.pay_code (tenant_id, pay_code, kind, name_en, name_fr, accrues_leave) VALUES
  (current_setting('app.tenant_id')::uuid, 'ALW-CAR', 'earning', 'Car allowance', 'Allocation automobile', false),
  (current_setting('app.tenant_id')::uuid, 'DUTY-DRIVE', 'earning', 'Driving duty', 'Fonctions de conduite', true),
  (current_setting('app.tenant_id')::uuid, 'REG', 'earning', 'Regular pay', 'Salaire régulier', true);
INSERT INTO payroll.duty (tenant_id, duty_code, name_en, pay_code) VALUES
  (current_setting('app.tenant_id')::uuid, 'DRIVING', 'Driving the program van', 'DUTY-DRIVE');
INSERT INTO core.assignment_pay_item (tenant_id, pay_item_id, assignment_id, kind, pay_code, basis, amount, source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), '06200000-0000-0000-0000-000000000001', 'allowance', 'ALW-CAR', 'per_month', 150, 'policy', '[2026-01-01,)', gen_random_uuid());
INSERT INTO core.assignment_pay_item (tenant_id, pay_item_id, assignment_id, kind, pay_code, duty_code, basis, amount, source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), '06200000-0000-0000-0000-000000000002', 'duty_rate', 'DUTY-DRIVE', 'DRIVING', 'rate_for_duty_hours', 28.50, 'policy', '[2026-01-01,)', gen_random_uuid());
DO $$ BEGIN
  BEGIN
    INSERT INTO core.assignment_pay_item (tenant_id, pay_item_id, assignment_id, kind, pay_code, basis, amount, source, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), '06200000-0000-0000-0000-000000000002', 'duty_rate', 'DUTY-DRIVE', 'rate_for_duty_hours', 30, 'policy', '[2026-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 6a';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO core.assignment_pay_item (tenant_id, pay_item_id, assignment_id, kind, pay_code, basis, amount, source, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), '06200000-0000-0000-0000-000000000001', 'stipend', 'ALW-CAR', 'per_month', 100, 'manual', '[2027-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 6b';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO core.assignment_pay_item (tenant_id, pay_item_id, assignment_id, kind, pay_code, basis, amount, source, reason, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), '06200000-0000-0000-0000-000000000001', 'stipend', 'ALW-CAR', 'per_month', 100, 'manual', 'x', '[2027-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 6c';
  EXCEPTION WHEN exclusion_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO core.assignment_pay_item (tenant_id, pay_item_id, assignment_id, kind, pay_code, basis, source, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), '06200000-0000-0000-0000-000000000002', 'allowance', 'ALW-CAR', 'percent_of_base', 'policy', '[2026-01-01,)', gen_random_uuid());
    RAISE EXCEPTION 'FAIL 6d';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 6: allowance on A1 and driving rate on A2 accepted; duty rate without a duty, manual item without a reason, the same pay code twice and a percentage without a percent refused';
END $$;

-- 7. Time lines name the duty; one-time items name a position or are shared by earnings
INSERT INTO core.payroll_account (tenant_id, payroll_account_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
  VALUES (current_setting('app.tenant_id')::uuid, '06600000-0000-0000-0000-000000000001', 'a6000000-0000-0000-0000-000000000001', 'RP0001', 'regular', '[2026-01-01,)');
INSERT INTO payroll.pay_group (tenant_id, pay_group_id, payroll_account_id, code, name, frequency, periods_per_year, proration_method)
  VALUES (current_setting('app.tenant_id')::uuid, '06600000-0000-0000-0000-000000000002', '06600000-0000-0000-0000-000000000001', 'BW', 'Bi-weekly', 'biweekly', '{"2027": 26}', 'working_days');
INSERT INTO payroll.pay_period (tenant_id, pay_period_id, pay_group_id, tax_year, period_number, work_period, cutoff_at, pay_date, status)
  VALUES (current_setting('app.tenant_id')::uuid, '06600000-0000-0000-0000-000000000003', '06600000-0000-0000-0000-000000000002', 2027, 5,
          '[2027-02-28,2027-03-14)', '2027-03-15 12:00-05', '2027-03-19', 'open');
INSERT INTO timeleave.timesheet (tenant_id, timesheet_id, assignment_id, pay_period_id, status)
  VALUES (current_setting('app.tenant_id')::uuid, '06600000-0000-0000-0000-000000000004', '06200000-0000-0000-0000-000000000002', '06600000-0000-0000-0000-000000000003', 'open');
INSERT INTO timeleave.time_line (tenant_id, timesheet_id, work_date, pay_code, hours, duty_code, rate_basis)
  VALUES (current_setting('app.tenant_id')::uuid, '06600000-0000-0000-0000-000000000004', '2027-03-04', 'REG', 2.0, 'DRIVING', 'regular_rate');
DO $$ BEGIN
  BEGIN
    INSERT INTO timeleave.time_line (tenant_id, timesheet_id, work_date, pay_code, hours, duty_code, rate_basis)
      VALUES (current_setting('app.tenant_id')::uuid, '06600000-0000-0000-0000-000000000004', '2027-03-04', 'REG', 1.0, 'FLYING', 'regular_rate');
    RAISE EXCEPTION 'FAIL 7a';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO payroll.one_time_item (tenant_id, employment_id, pay_code, amount, pay_on_or_after, source, status, allocation)
      VALUES (current_setting('app.tenant_id')::uuid, '06100000-0000-0000-0000-000000000001', 'REG', 500, '2027-03-19', 'award', 'pending', 'assignment');
    RAISE EXCEPTION 'FAIL 7b';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO payroll.one_time_item (tenant_id, employment_id, pay_code, amount, pay_on_or_after, source, status, allocation)
    VALUES (current_setting('app.tenant_id')::uuid, '06100000-0000-0000-0000-000000000001', 'REG', 500, '2027-03-19', 'award', 'pending', 'earnings_share');
  RAISE NOTICE 'PASS 7: driving hours recorded with their duty; unknown duty refused; a one-time item marked to be shared is shared by earnings';
END $$;

-- 8. One review with a section per position. Each position stands by itself unless the organization chooses a combined
--    rating (docs/28 §6.1); this review states the FTE x days method and 60 days so the method itself is tested.
INSERT INTO talent.review (tenant_id, review_id, employment_id, cycle_code, kind, status, overall_method, min_section_days, rating_mode)
  VALUES (current_setting('app.tenant_id')::uuid, '06700000-0000-0000-0000-000000000001', '06100000-0000-0000-0000-000000000001', 'FY2026', 'annual', 'manager',
          'fte_weighted', 60, 'rated');
INSERT INTO talent.review_section (tenant_id, section_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, rating_score) VALUES
  (current_setting('app.tenant_id')::uuid, '06710000-0000-0000-0000-000000000001', '06700000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000003', 0.6, 365, 365, 4),
  (current_setting('app.tenant_id')::uuid, '06710000-0000-0000-0000-000000000002', '06700000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000002', '06200000-0000-0000-0000-000000000004', 0.4, 365, 365, 3);
DO $$ BEGIN
  IF talent.review_overall('06700000-0000-0000-0000-000000000001') <> 4 THEN RAISE EXCEPTION 'FAIL 8a'; END IF;
  UPDATE talent.review_section SET days_in_cycle = 45, days_worked = 45, rating_score = NULL, rated = false WHERE section_id = '06710000-0000-0000-0000-000000000002';
  IF talent.review_overall('06700000-0000-0000-0000-000000000001', 0.5) <> 4.0 THEN RAISE EXCEPTION 'FAIL 8b'; END IF;
  BEGIN
    UPDATE talent.review_section SET owner_assignment_id = '06200000-0000-0000-0000-000000000001' WHERE section_id = '06710000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 8c';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'SELF_REVIEW%' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO talent.review_section (tenant_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle)
      VALUES (current_setting('app.tenant_id')::uuid, '06700000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000003', '06200000-0000-0000-0000-000000000004', 1, 365);
    RAISE EXCEPTION 'FAIL 8d';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'SECTION_NOT_IN_EMPLOYMENT%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS 8: 0.6 x 4 and 0.4 x 3 give 4; a section held 45 days is not rated and carries no weight; no self-rating; sections stay inside the employment';
END $$;

-- 9. Competency gaps prefer the assessment made in the same position
INSERT INTO talent.competency_framework (tenant_id, framework_id, code, name_en) VALUES (current_setting('app.tenant_id')::uuid, '06800000-0000-0000-0000-000000000001', 'UCM', 'Unified Competency Model');
INSERT INTO talent.competency_framework_version (tenant_id, framework_version_id, framework_id, label, scale)
  VALUES (current_setting('app.tenant_id')::uuid, '06810000-0000-0000-0000-000000000001', '06800000-0000-0000-0000-000000000001', '1.0',
          '[{"level":1},{"level":2},{"level":3},{"level":4},{"level":5}]');
INSERT INTO talent.competency (tenant_id, competency_id, framework_version_id, code, domain_code, name_en, definition_en)
  VALUES (current_setting('app.tenant_id')::uuid, '06820000-0000-0000-0000-000000000001', '06810000-0000-0000-0000-000000000001', 'CLI', 'CORE', 'Client-Centered Practice', 'Meets clients'' needs.');
INSERT INTO talent.competency_indicator (tenant_id, competency_id, level, seq, text_en)
  SELECT current_setting('app.tenant_id')::uuid, '06820000-0000-0000-0000-000000000001', l, 1, 'Level ' || l FROM generate_series(1, 5) l;
UPDATE talent.competency_framework_version SET status = 'published' WHERE framework_version_id = '06810000-0000-0000-0000-000000000001';
INSERT INTO talent.competency_target (tenant_id, target_id, target_type, target_ref, competency_id, required_level, source, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd6000000-0000-0000-0000-000000000001', '06820000-0000-0000-0000-000000000001', 3, 'job', '[2026-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd6000000-0000-0000-0000-000000000002', '06820000-0000-0000-0000-000000000001', 2, 'job', '[2026-01-01,)', gen_random_uuid());
INSERT INTO talent.competency_assessment (tenant_id, person_id, competency_id, assessed_level, source, context, assessed_on, assessor_person_id, status, assignment_id, review_section_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f6000000-0000-0000-0000-000000000001', '06820000-0000-0000-0000-000000000001', 3, 'manager', 'performance_review', '2026-03-01',
   'f6000000-0000-0000-0000-000000000002', 'final', '06200000-0000-0000-0000-000000000001', '06710000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'f6000000-0000-0000-0000-000000000001', '06820000-0000-0000-0000-000000000001', 1, 'manager', 'performance_review', '2026-09-01',
   'f6000000-0000-0000-0000-000000000003', 'final', '06200000-0000-0000-0000-000000000002', '06710000-0000-0000-0000-000000000002');
DO $$ DECLARE g1 smallint; g2 smallint; BEGIN
  SELECT gap INTO g1 FROM talent.competency_gap('06200000-0000-0000-0000-000000000001', '2026-10-01') WHERE competency_code = 'CLI';
  SELECT gap INTO g2 FROM talent.competency_gap('06200000-0000-0000-0000-000000000002', '2026-10-01') WHERE competency_code = 'CLI';
  IF g1 <> 0 OR g2 <> 1 THEN RAISE EXCEPTION 'FAIL 9: % %', g1, g2; END IF;
  RAISE NOTICE 'PASS 9: A1 uses its own manager''s level 3 (gap 0) although a newer level 1 exists from A2; A2 uses its own (gap 1)';
END $$;

-- 10. Benefit plans per agreement, enrolment through the position that makes the person eligible
INSERT INTO benefits.plan (tenant_id, plan_id, code, kind, eligibility, eligibility_scope, agreement_id, waiting_rule, late_enrolment) VALUES
  (current_setting('app.tenant_id')::uuid, '06900000-0000-0000-0000-000000000001', 'HEALTH-EMP', 'health', '{"minFte": 0.75}', 'employer', NULL, '{"kind":"months","n":3}', 'eoi'),
  (current_setting('app.tenant_id')::uuid, '06900000-0000-0000-0000-000000000002', 'TRUST-PT', 'health', '{"minFte": 0.2}', 'agreement', 'PT', '{"kind":"none"}', 'next_open_enrolment');
DO $$ BEGIN
  BEGIN
    INSERT INTO benefits.plan (tenant_id, code, kind, eligibility, eligibility_scope, waiting_rule, late_enrolment)
      VALUES (current_setting('app.tenant_id')::uuid, 'BAD', 'health', '{}', 'agreement', '{"kind":"none"}', 'eoi');
    RAISE EXCEPTION 'FAIL 10a';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO benefits.enrolment (tenant_id, employment_id, plan_id, coverage_level, valid_period, employee_cost_per_period, employer_cost_per_period)
      VALUES (current_setting('app.tenant_id')::uuid, '06100000-0000-0000-0000-000000000001', '06900000-0000-0000-0000-000000000002', 'single', '[2025-02-01,)', 0, 40);
    RAISE EXCEPTION 'FAIL 10b';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'ENROLMENT_NEEDS_ASSIGNMENT%' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO benefits.enrolment (tenant_id, employment_id, plan_id, coverage_level, valid_period, employee_cost_per_period, employer_cost_per_period, via_assignment_id)
      VALUES (current_setting('app.tenant_id')::uuid, '06100000-0000-0000-0000-000000000001', '06900000-0000-0000-0000-000000000002', 'single', '[2025-02-01,)', 0, 40, '06200000-0000-0000-0000-000000000003');
    RAISE EXCEPTION 'FAIL 10c';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'ENROLMENT_ASSIGNMENT_MISMATCH%' THEN RAISE; END IF;
  END;
  BEGIN
    INSERT INTO benefits.enrolment (tenant_id, employment_id, plan_id, coverage_level, valid_period, employee_cost_per_period, employer_cost_per_period, via_assignment_id)
      VALUES (current_setting('app.tenant_id')::uuid, '06100000-0000-0000-0000-000000000001', '06900000-0000-0000-0000-000000000002', 'single', '[2025-02-01,)', 0, 40, '06200000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL 10d';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'ENROLMENT_AGREEMENT_MISMATCH%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS 10: an agreement plan names its agreement; enrolment names Jordan''s own position under that agreement';
END $$;
-- The order of two plans of one kind is HR's decision, recorded with its reason (docs/26 §5.2)
INSERT INTO benefits.enrolment (tenant_id, enrolment_id, employment_id, plan_id, coverage_level, valid_period, employee_cost_per_period, employer_cost_per_period, via_assignment_id, cob_rank,
                                cob_decided_by, cob_decided_at, cob_reason) VALUES
  (current_setting('app.tenant_id')::uuid, '06910000-0000-0000-0000-000000000001', '06100000-0000-0000-0000-000000000001', '06900000-0000-0000-0000-000000000001', 'family', '[2024-05-01,)', 25, 180, NULL, 1,
   gen_random_uuid(), now(), 'Employer plan covers the family; trust plan pays second'),
  (current_setting('app.tenant_id')::uuid, '06910000-0000-0000-0000-000000000002', '06100000-0000-0000-0000-000000000001', '06900000-0000-0000-0000-000000000002', 'single', '[2025-02-01,)', 0, 40, '06200000-0000-0000-0000-000000000002', 2,
   gen_random_uuid(), now(), 'Employer plan covers the family; trust plan pays second');

-- 11. Benefit-change rules and decisions when A2 ends
DO $$ BEGIN
  INSERT INTO benefits.change_rule (tenant_id, rule_id, code, name_en, priority, match, action, offer_conversion, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'BAD', 'Bad', 1, '{}', 'continue_until', false, '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 11a';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 11a: "continue until" needs its date rule';
END $$;
INSERT INTO benefits.change_rule (tenant_id, rule_id, code, name_en, priority, match, action, until_rule, offer_conversion, cite, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, '06920000-0000-0000-0000-000000000020', 'R20', 'Employer-ended: to month end, offer conversion', 20,
   '{"employerInitiated": true}', 'continue_until', '{"kind": "end_of_month"}', true, 'Benefits policy 4.2', '[2026-01-01,)', gen_random_uuid());
DO $$ BEGIN
  INSERT INTO benefits.change_decision (tenant_id, enrolment_id, ended_assignment_id, end_date, end_reason, eligible_after, fte_after, rule_id,
                                        statutory_floor_until, statutory_basis, proposed_outcome, proposed_until, outcome, coverage_until, offer_conversion)
    VALUES (current_setting('app.tenant_id')::uuid, '06910000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000002', '2027-03-15', 'ELIMINATED', false, 0.6,
            '06920000-0000-0000-0000-000000000020', '2027-04-12', 'ES:ON benefits_during_notice', 'continue_until', '2027-03-31', 'continue_until', '2027-03-31', true);
  RAISE EXCEPTION 'FAIL 11b';
EXCEPTION WHEN check_violation THEN
  IF SQLERRM NOT LIKE '%statutory_floor_respected%' THEN RAISE; END IF;
  RAISE NOTICE 'PASS 11b: coverage can never end before the statutory floor (Ontario notice period)';
END $$;
INSERT INTO benefits.change_decision (tenant_id, decision_id, enrolment_id, ended_assignment_id, end_date, end_reason, eligible_after, fte_after, rule_id,
                                      statutory_floor_until, statutory_basis, proposed_outcome, proposed_until, outcome, coverage_until, offer_conversion)
  VALUES (current_setting('app.tenant_id')::uuid, '06930000-0000-0000-0000-000000000001', '06910000-0000-0000-0000-000000000001', '06200000-0000-0000-0000-000000000002',
          '2027-03-15', 'ELIMINATED', false, 0.6, '06920000-0000-0000-0000-000000000020', '2027-04-12', 'ES:ON benefits_during_notice',
          'continue_until', '2027-04-12', 'continue_until', '2027-04-12', true);
INSERT INTO benefits.change_decision (tenant_id, decision_id, enrolment_id, ended_assignment_id, end_date, end_reason, eligible_after, fte_after,
                                      proposed_outcome, outcome, offer_conversion)
  VALUES (current_setting('app.tenant_id')::uuid, '06930000-0000-0000-0000-000000000002', '06910000-0000-0000-0000-000000000002', '06200000-0000-0000-0000-000000000002',
          '2027-03-15', 'OTHER', false, 0, 'hr_decides', 'hr_decides', false);
DO $$ BEGIN
  BEGIN
    UPDATE benefits.change_decision SET outcome = 'continue_until', coverage_until = '2027-04-30', status = 'decided', decided_by = gen_random_uuid(), decided_at = now()
      WHERE decision_id = '06930000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 11c';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE '%case_by_case_needs_reason%' THEN RAISE; END IF;
  END;
  UPDATE benefits.change_decision SET outcome = 'continue_until', coverage_until = '2027-04-30', status = 'decided', decided_by = gen_random_uuid(), decided_at = now(),
         reason = 'Trust rules allow coverage to the end of the following month'
    WHERE decision_id = '06930000-0000-0000-0000-000000000002';
  BEGIN
    UPDATE benefits.change_decision SET coverage_until = '2027-05-31', status = 'decided', decided_by = gen_random_uuid(), decided_at = now()
      WHERE decision_id = '06930000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 11d';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE '%override_needs_reason%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE benefits.change_decision SET end_date = '2027-03-31' WHERE decision_id = '06930000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 11e';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'CHANGE_DECISION_FACTS_FROZEN%' THEN RAISE; END IF;
  END;
  UPDATE benefits.change_decision SET status = 'applied' WHERE decision_id = '06930000-0000-0000-0000-000000000002';
  BEGIN
    UPDATE benefits.change_decision SET reason = 'changed' WHERE decision_id = '06930000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 11f';
  EXCEPTION WHEN check_violation THEN IF SQLERRM NOT LIKE 'CHANGE_DECISION_IMMUTABLE%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS 11: case-by-case and overriding decisions need a reason; facts frozen; applied decisions frozen';
END $$;

-- 12. Merit reads the position's own section by default
DO $$ BEGIN
  IF platform.setting_text(current_setting('app.tenant_id')::uuid, 'comp.merit_rating_source') IS DISTINCT FROM 'section'
     OR NOT EXISTS (SELECT 1 FROM platform.column_default WHERE table_schema = 'comp' AND table_name = 'cycle'
                     AND column_name = 'merit_rating_source' AND setting_key = 'comp.merit_rating_source') THEN
    RAISE EXCEPTION 'FAIL 12';
  END IF;
  RAISE NOTICE 'PASS 12: compensation cycles default to the section rating of each position';
END $$;

-- 13. Tenant isolation
SELECT set_config('app.tenant_id', '62222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM core.approval_part) + (SELECT count(*) FROM core.approval_coverage) + (SELECT count(*) FROM core.assignment_pay_item)
     + (SELECT count(*) FROM talent.review_section) + (SELECT count(*) FROM benefits.change_decision) + (SELECT count(*) FROM core.end_reason) <> 0 THEN
    RAISE EXCEPTION 'FAIL 13a';
  END IF;
  RAISE NOTICE 'PASS 13a: other tenant sees none of these rows';
END $$;
DO $$ BEGIN
  INSERT INTO core.end_reason (tenant_id, code, name_en, category, employer_initiated) VALUES ('61111111-1111-1111-1111-111111111111', 'X', 'X', 'other', false);
  RAISE EXCEPTION 'FAIL 13b';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS 13b: cannot write into another tenant';
END $$;
RESET ROLE;

-- 14. Row-level security forced on every new tenant table
DO $$ DECLARE missing text; BEGIN
  SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO missing
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE c.relkind = 'r' AND (n.nspname, c.relname) IN (
      ('core','end_reason'), ('core','approval_policy'), ('core','approval_coverage'), ('core','approval_part'),
      ('payroll','duty'), ('core','assignment_pay_item'), ('talent','review_section'), ('benefits','change_rule'), ('benefits','change_decision'))
    AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL 14: %', missing; END IF;
  RAISE NOTICE 'PASS 14: RLS forced on the 9 new tenant tables';
END $$;

\echo Migration 0006 smoke test passed.
