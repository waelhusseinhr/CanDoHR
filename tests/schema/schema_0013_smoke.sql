-- Smoke test for schema/0013_time_attendance_leave.sql (docs/27): the new settings and leave categories, protected
-- leave types, time exceptions and the rest-period caution, averaging arrangements, overtime exemptions, how each
-- group records time, timesheets (self-approval, the optional second approval, the cut-off), leave plans (carry-over,
-- payout, plan years), declines, the team availability bar, the attendance program, scheduling notice, swaps and
-- offers, RLS and tenant isolation.
-- Run after every migration, 0001 to 0013 (CI, after the 0012 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0013_smoke.sql
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
  ('d1111111-1111-1111-1111-111111111111', 'Time Test Society'),
  ('d2222222-2222-2222-2222-222222222222', 'Other Organization')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', 'd1111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, leave categories, cautions, RLS
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/27%') <> 13
     OR EXISTS (SELECT 1 FROM platform.setting_definition WHERE decision_ref LIKE 'docs/27%' AND decision_status = 'pending') THEN
    RAISE EXCEPTION 'FAIL 1a: expected 13 decided settings from docs/27';
  END IF;
  IF platform.setting_number(t, 'time.punch_rounding_minutes') <> 0 OR (platform.setting(t, 'time.geofence'))::boolean
     OR (platform.setting(t, 'attendance.program_enabled'))::boolean OR platform.setting_number(t, 'scheduling.notice_days') <> 14
     OR platform.setting_number(t, 'absence.disability_check_after_days') <> 5
     OR NOT (platform.setting(t, 'time.employee_confirmation'))::boolean
     OR platform.setting(t, 'time.unapproved_overtime_alerts') -> 'beforePayroll' <> '["manager","hr"]'::jsonb THEN
    RAISE EXCEPTION 'FAIL 1b: decided defaults not in place';
  END IF;
  IF (SELECT count(*) FROM ref.leave_category) <> 21
     OR NOT (SELECT reason_always_protected FROM ref.leave_category WHERE category = 'domestic_violence')
     OR (SELECT count(*) FROM ref.caution WHERE caution_code IN ('time.rest_or_hours_limit','time.schedule_changed_late')) <> 2 THEN
    RAISE EXCEPTION 'FAIL 1c: leave categories or cautions missing';
  END IF;
  SELECT string_agg(c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'timeleave' AND c.relkind = 'r'
     AND c.relname IN ('time_exception','averaging_arrangement','overtime_exemption','recording_rule','leave_plan','plan_entry',
                       'staffing_level','blackout_period','attendance_program','attendance_stage','shift_offer','shift_swap')
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1d: RLS missing on %', bad; END IF;
  RAISE NOTICE 'PASS 1a-d: settings, decided defaults, leave categories, cautions, RLS';
END $$;

-- Fixtures: one employer in BC, a care unit and an office unit, an employee with two positions, her manager, a colleague
INSERT INTO core.person (tenant_id, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0d600000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0d600000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0d600000-0000-0000-0000-000000000003');
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0da00000-0000-0000-0000-000000000001', 'emp', 'emp@example.test', '0d600000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0da00000-0000-0000-0000-000000000002', 'mgr', 'mgr@example.test', '0d600000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0da00000-0000-0000-0000-000000000003', 'hr', 'hr@example.test', NULL),
  (current_setting('app.tenant_id')::uuid, '0da00000-0000-0000-0000-000000000004', 'col', 'col@example.test', '0d600000-0000-0000-0000-000000000003');
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, '0d100000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, '0d200000-0000-0000-0000-000000000001');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction) VALUES
  (current_setting('app.tenant_id')::uuid, '0d200000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'House', '1 Main St', 'Victoria', 'BC', 'V8W 1A1', 'America/Vancouver', 'BC');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0d300000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0d300000-0000-0000-0000-000000000002');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, '0d400000-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, '0d400000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'CW', 'Care Worker', 'Préposé aux soins');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, '0d500000-0000-0000-0000-000000000001', 'P-1'),
  (current_setting('app.tenant_id')::uuid, '0d500000-0000-0000-0000-000000000002', 'P-MGR'),
  (current_setting('app.tenant_id')::uuid, '0d500000-0000-0000-0000-000000000003', 'P-3'),
  (current_setting('app.tenant_id')::uuid, '0d500000-0000-0000-0000-000000000004', 'P-OFF');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0d300000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0d100000-0000-0000-0000-000000000001', 'DEPT', 'CARE', 'Care', '0d500000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0d300000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '0d100000-0000-0000-0000-000000000001', 'DEPT', 'OFFICE', 'Office', '0d500000-0000-0000-0000-000000000002');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0d500000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '0d400000-0000-0000-0000-000000000001', '0d300000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001', NULL, 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0d500000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '0d400000-0000-0000-0000-000000000001', '0d300000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001', '0d500000-0000-0000-0000-000000000002', 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0d500000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), '0d400000-0000-0000-0000-000000000001', '0d300000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001', '0d500000-0000-0000-0000-000000000002', 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, '0d500000-0000-0000-0000-000000000004', '[2020-01-01,)', gen_random_uuid(), '0d400000-0000-0000-0000-000000000001', '0d300000-0000-0000-0000-000000000002', '0d200000-0000-0000-0000-000000000001', '0d500000-0000-0000-0000-000000000002', 0.4, 'permanent', 'active');
INSERT INTO core.agreement (tenant_id, agreement_id, name, union_name, jurisdiction, status, bargaining_employer_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'UA', 'Care agreement', 'Union A', 'BC', 'in_force', '0d100000-0000-0000-0000-000000000001');
INSERT INTO core.payroll_account (tenant_id, payroll_account_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
  VALUES (current_setting('app.tenant_id')::uuid, '0d900000-0000-0000-0000-000000000001', '0d100000-0000-0000-0000-000000000001', 'RP0001', 'regular', '[2026-01-01,)');
INSERT INTO payroll.pay_group (tenant_id, pay_group_id, payroll_account_id, code, name, frequency, periods_per_year, proration_method)
  VALUES (current_setting('app.tenant_id')::uuid, '0d900000-0000-0000-0000-000000000002', '0d900000-0000-0000-0000-000000000001', 'BW', 'Bi-weekly', 'biweekly', '{"2027": 26}', 'working_days');
INSERT INTO payroll.pay_period (tenant_id, pay_period_id, pay_group_id, tax_year, period_number, work_period, cutoff_at, pay_date, status)
  VALUES (current_setting('app.tenant_id')::uuid, '0d910000-0000-0000-0000-000000000001', '0d900000-0000-0000-0000-000000000002', 2027, 5,
          '[2027-03-01,2027-03-14]', '2027-03-15 12:00-08', '2027-03-19', 'open');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0d700000-0000-0000-0000-000000000001', '0d600000-0000-0000-0000-000000000001', '0d100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0d700000-0000-0000-0000-000000000002', '0d600000-0000-0000-0000-000000000002', '0d100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0d700000-0000-0000-0000-000000000003', '0d600000-0000-0000-0000-000000000003', '0d100000-0000-0000-0000-000000000001');
INSERT INTO core.employment_version (tenant_id, employment_id, valid_period, change_set_id, original_hire_date, continuous_service_date, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0d700000-0000-0000-0000-000000000001', '[2019-03-15,)', gen_random_uuid(), '2019-03-15', '2020-06-01', 'active');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0d800000-0000-0000-0000-000000000001', '0d700000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '0d800000-0000-0000-0000-000000000002', '0d700000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0d800000-0000-0000-0000-000000000003', '0d700000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '0d800000-0000-0000-0000-000000000004', '0d700000-0000-0000-0000-000000000001');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type, agreement_id, pay_group_id) VALUES
  (current_setting('app.tenant_id')::uuid, '0d800000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), '0d500000-0000-0000-0000-000000000001', '0d300000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001', 0.6, true, 'permanent', 'UA', '0d900000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0d800000-0000-0000-0000-000000000002', '[2026-01-01,)', gen_random_uuid(), '0d500000-0000-0000-0000-000000000002', '0d300000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001', 1, true, 'permanent', NULL, '0d900000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0d800000-0000-0000-0000-000000000003', '[2026-01-01,)', gen_random_uuid(), '0d500000-0000-0000-0000-000000000003', '0d300000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001', 1, true, 'permanent', 'UA', '0d900000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0d800000-0000-0000-0000-000000000004', '[2026-01-01,)', gen_random_uuid(), '0d500000-0000-0000-0000-000000000004', '0d300000-0000-0000-0000-000000000002', '0d200000-0000-0000-0000-000000000001', 0.4, false, 'permanent', NULL, '0d900000-0000-0000-0000-000000000002');
INSERT INTO core.pay_rate (tenant_id, pay_rate_id, assignment_id, component) VALUES
  (current_setting('app.tenant_id')::uuid, '0d920000-0000-0000-0000-000000000001', '0d800000-0000-0000-0000-000000000001', 'base'),
  (current_setting('app.tenant_id')::uuid, '0d920000-0000-0000-0000-000000000004', '0d800000-0000-0000-0000-000000000004', 'base');
INSERT INTO core.pay_rate_version (tenant_id, pay_rate_id, valid_period, change_set_id, basis, amount, source) VALUES
  (current_setting('app.tenant_id')::uuid, '0d920000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), 'hourly', 30.85, 'agreement_grid'),
  (current_setting('app.tenant_id')::uuid, '0d920000-0000-0000-0000-000000000004', '[2026-01-01,)', gen_random_uuid(), 'annual_salary', 24000, 'manual');
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by) VALUES
  (current_setting('app.tenant_id')::uuid, '0dd00000-0000-0000-0000-000000000001', 'legal_entity', '0d100000-0000-0000-0000-000000000001', 'averaging_agreement', 'restricted', 'payroll', 'test/avg.pdf', 'x', 'application/pdf', '0da00000-0000-0000-0000-000000000003');

-- ---------------------------------------------------------------------------------
-- 2. Leave types: CanDo's categories; protected reasons from the organization's list; domestic violence always protected
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO timeleave.leave_type (tenant_id, leave_type_code, name_en, name_fr, category, statutory, jurisdictions, paid_percent, job_protected, roe_trigger)
      VALUES (t, 'X', 'Wellness', 'Bien-être', 'wellness', false, ARRAY['BC']::ref.jurisdiction_code[], 0, false, false);
    RAISE EXCEPTION 'FAIL 2a: unknown leave category accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LIST_VALUE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO timeleave.leave_type (tenant_id, leave_type_code, name_en, name_fr, category, statutory, jurisdictions, paid_percent, job_protected, reason_restricted, roe_trigger)
      VALUES (t, 'DV', 'Domestic violence leave', 'Congé pour violence familiale', 'domestic_violence', true, ARRAY['BC']::ref.jurisdiction_code[], 0, true, false, false);
    RAISE EXCEPTION 'FAIL 2b: domestic violence leave shown to managers';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LEAVE_REASON_MUST_BE_PROTECTED%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  INSERT INTO timeleave.leave_type (tenant_id, leave_type_code, name_en, name_fr, category, statutory, jurisdictions, paid_percent, job_protected, roe_trigger) VALUES
    (t, 'VAC', 'Vacation', 'Vacances', 'vacation', false, ARRAY['BC']::ref.jurisdiction_code[], 100, false, false),
    (t, 'SICK', 'Sick day', 'Journée de maladie', 'sick', false, ARRAY['BC']::ref.jurisdiction_code[], 100, false, false),
    (t, 'PARENTAL', 'Parental leave', 'Congé parental', 'parental', true, ARRAY['BC']::ref.jurisdiction_code[], 0, true, true),
    (t, 'MED', 'Medical leave', 'Congé médical', 'medical', true, ARRAY['BC']::ref.jurisdiction_code[], 0, true, false),
    (t, 'UNION', 'Union business', 'Activités syndicales', 'union_business', false, ARRAY['BC']::ref.jurisdiction_code[], 100, false, false);
  IF NOT (SELECT reason_restricted FROM timeleave.leave_type WHERE leave_type_code = 'MED')
     OR (SELECT reason_restricted FROM timeleave.leave_type WHERE leave_type_code = 'VAC') THEN
    RAISE EXCEPTION 'FAIL 2c: protected categories not applied';
  END IF;
  RAISE NOTICE 'PASS 2a-c: leave types use CanDo''s categories; medical shows as protected leave; domestic violence always does';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Punches and time exceptions: hours worked stay paid; rest-period breaches need the caution
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  INSERT INTO timeleave.punch (tenant_id, assignment_id, punched_at, kind, source) VALUES
    (t, '0d800000-0000-0000-0000-000000000001', '2027-03-02 07:00-08', 'in', 'mobile'),
    (t, '0d800000-0000-0000-0000-000000000001', '2027-03-02 12:00-08', 'break_confirmed', 'mobile');
  BEGIN
    INSERT INTO timeleave.punch (tenant_id, assignment_id, punched_at, kind) VALUES (t, '0d800000-0000-0000-0000-000000000001', '2027-03-02 17:00-08', 'out');
    RAISE EXCEPTION 'FAIL 3a: punch without its source';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO timeleave.time_exception (tenant_id, exception_id, assignment_id, work_date, kind, hours, status) VALUES
    (t, '0de00000-0000-0000-0000-000000000001', '0d800000-0000-0000-0000-000000000001', '2027-03-02', 'unapproved_overtime', 1.5, 'open'),
    (t, '0de00000-0000-0000-0000-000000000002', '0d800000-0000-0000-0000-000000000001', '2027-03-03', 'rest_period', NULL, 'open');
  BEGIN
    UPDATE timeleave.time_exception SET status = 'not_authorized', decided_by = '0da00000-0000-0000-0000-000000000002', decided_at = now()
     WHERE exception_id = '0de00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 3b: not authorized without a reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  UPDATE timeleave.time_exception SET status = 'not_authorized', decided_by = '0da00000-0000-0000-0000-000000000002', decided_at = now(),
         reason = 'Stayed late without asking; spoke with her about calling first'
   WHERE exception_id = '0de00000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE timeleave.time_exception SET status = 'not_authorized', decided_by = '0da00000-0000-0000-0000-000000000002', decided_at = now(), reason = 'x'
     WHERE exception_id = '0de00000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 3c: a rest-period breach marked not authorized';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE timeleave.time_exception SET status = 'acknowledged', decided_by = '0da00000-0000-0000-0000-000000000002', decided_at = now(),
           reason = 'Storm: no relief staff could reach the house'
     WHERE exception_id = '0de00000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 3d: rest-period breach acknowledged without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 3d: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 3a-d: punches state their source; unapproved overtime is paid and noted with a reason; rest breaches need the caution';
END $$;

-- ---------------------------------------------------------------------------------
-- 4. Hours of work: averaging with its document and end date; exemptions with their legal basis; recording methods
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; a timeleave.averaging_arrangement;
BEGIN
  BEGIN
    INSERT INTO timeleave.averaging_arrangement (tenant_id, legal_entity_id, jurisdiction, kind, applies_to, cycle_weeks, anchor_date, valid_period, recorded_by)
      VALUES (t, '0d100000-0000-0000-0000-000000000001', 'BC', 'written_agreement', '{"orgUnits":["0d300000-0000-0000-0000-000000000001"]}', 4, '2027-01-04', '[2027-01-04,2028-01-03)', '0da00000-0000-0000-0000-000000000003');
    RAISE EXCEPTION 'FAIL 4a: averaging agreement without its document';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO timeleave.averaging_arrangement (tenant_id, legal_entity_id, jurisdiction, kind, document_id, applies_to, cycle_weeks, anchor_date, valid_period, recorded_by)
      VALUES (t, '0d100000-0000-0000-0000-000000000001', 'BC', 'written_agreement', '0dd00000-0000-0000-0000-000000000001', '{"orgUnits":["0d300000-0000-0000-0000-000000000001"]}', 4, '2027-01-04', '[2027-01-04,)', '0da00000-0000-0000-0000-000000000003');
    RAISE EXCEPTION 'FAIL 4a: averaging agreement with no end date';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO timeleave.averaging_arrangement (tenant_id, legal_entity_id, jurisdiction, kind, document_id, applies_to, cycle_weeks, anchor_date, valid_period, recorded_by)
    VALUES (t, '0d100000-0000-0000-0000-000000000001', 'BC', 'written_agreement', '0dd00000-0000-0000-0000-000000000001', '{"orgUnits":["0d300000-0000-0000-0000-000000000001"]}', 4, '2027-01-04', '[2027-01-04,2028-01-03)', '0da00000-0000-0000-0000-000000000003');
  a := timeleave.averaging_for('0d800000-0000-0000-0000-000000000001', '2027-03-02');
  IF a.cycle_weeks IS DISTINCT FROM 4::smallint OR timeleave.averaging_for('0d800000-0000-0000-0000-000000000004', '2027-03-02') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL 4b: averaging not found for the care unit only';
  END IF;
  INSERT INTO timeleave.averaging_arrangement (tenant_id, legal_entity_id, jurisdiction, kind, agreement_id, applies_to, cycle_weeks, anchor_date, valid_period, recorded_by)
    VALUES (t, '0d100000-0000-0000-0000-000000000001', 'BC', 'collective_agreement', 'UA', '{"agreements":["UA"]}', 3, '2027-01-04', '[2027-01-04,)', '0da00000-0000-0000-0000-000000000003');
  BEGIN
    PERFORM timeleave.averaging_for('0d800000-0000-0000-0000-000000000001', '2027-03-02');
    RAISE EXCEPTION 'FAIL 4c: two averaging arrangements resolved silently';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'AVERAGING_CONFLICT%' THEN RAISE EXCEPTION 'FAIL 4c: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 4a-c: averaging arrangements recorded with their document and end; two at once is an error';

  BEGIN
    INSERT INTO timeleave.overtime_exemption (tenant_id, position_id, jurisdiction, exemption_code, legal_basis, reason, decided_by, valid_period)
      VALUES (t, '0d500000-0000-0000-0000-000000000002', 'BC', 'BC_MANAGER', ' ', 'Manages the house', '0da00000-0000-0000-0000-000000000003', '[2026-01-01,)');
    RAISE EXCEPTION 'FAIL 4d: exemption without its legal basis';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO timeleave.overtime_exemption (tenant_id, position_id, jurisdiction, exemption_code, legal_basis, reason, decided_by, valid_period)
    VALUES (t, '0d500000-0000-0000-0000-000000000002', 'BC', 'BC_MANAGER', 'Employment Standards Regulation, s. 34(f)', 'Manages the house and its staff; schedules and disciplines', '0da00000-0000-0000-0000-000000000003', '[2026-01-01,)');
  IF NOT timeleave.overtime_exempt('0d500000-0000-0000-0000-000000000002', '2027-03-02') OR timeleave.overtime_exempt('0d500000-0000-0000-0000-000000000001', '2027-03-02') THEN
    RAISE EXCEPTION 'FAIL 4e: exemption not read';
  END IF;
  RAISE NOTICE 'PASS 4d-e: HR marks a position exempt with the legal basis';

  IF timeleave.recording_method_for('0d800000-0000-0000-0000-000000000001', '2027-03-02') <> 'punch'
     OR timeleave.recording_method_for('0d800000-0000-0000-0000-000000000004', '2027-03-02') <> 'exceptions' THEN
    RAISE EXCEPTION 'FAIL 4f: starter recording methods by pay basis';
  END IF;
  BEGIN
    PERFORM timeleave.recording_method_for('0d800000-0000-0000-0000-000000000003', '2027-03-02');
    RAISE EXCEPTION 'FAIL 4g: recording method assumed without base pay';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4g: %', SQLERRM; END IF;
  END;
  INSERT INTO timeleave.recording_rule (tenant_id, code, name_en, applies_to, method, priority, status)
    VALUES (t, 'OFFICE-TS', 'Office staff keep timesheets for project costing', '{"orgUnits":["0d300000-0000-0000-0000-000000000002"]}', 'timesheet', 10, 'active');
  IF timeleave.recording_method_for('0d800000-0000-0000-0000-000000000004', '2027-03-02') <> 'timesheet'
     OR timeleave.recording_method_for('0d800000-0000-0000-0000-000000000001', '2027-03-02') <> 'punch' THEN
    RAISE EXCEPTION 'FAIL 4h: the organization''s recording rule not applied';
  END IF;
  RAISE NOTICE 'PASS 4f-h: hourly staff punch and salaried staff record exceptions unless the organization''s rule says otherwise';
END $$;

-- ---------------------------------------------------------------------------------
-- 5. Timesheets: never approved by the employee; rest breaches first; the optional second approval; the cut-off
-- ---------------------------------------------------------------------------------
INSERT INTO timeleave.timesheet (tenant_id, timesheet_id, assignment_id, pay_period_id, status, employee_confirmed_at) VALUES
  (current_setting('app.tenant_id')::uuid, '0df00000-0000-0000-0000-000000000001', '0d800000-0000-0000-0000-000000000001', '0d910000-0000-0000-0000-000000000001', 'submitted', now()),
  (current_setting('app.tenant_id')::uuid, '0df00000-0000-0000-0000-000000000003', '0d800000-0000-0000-0000-000000000003', '0d910000-0000-0000-0000-000000000001', 'submitted', NULL);
UPDATE timeleave.time_exception SET timesheet_id = '0df00000-0000-0000-0000-000000000001' WHERE exception_id = '0de00000-0000-0000-0000-000000000002';
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r uuid;
BEGIN
  BEGIN
    UPDATE timeleave.timesheet SET status = 'approved', approved_by = '0da00000-0000-0000-0000-000000000001', approved_at = now()
     WHERE timesheet_id = '0df00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5a: employee approved her own timesheet';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE timeleave.timesheet SET status = 'approved', approved_by = '0da00000-0000-0000-0000-000000000002', approved_at = now()
     WHERE timesheet_id = '0df00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5b: approved with an open rest-period breach';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 5b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'time.rest_or_hours_limit', 'time_exception', '0de00000-0000-0000-0000-000000000002', 'shown', 'en', '0da00000-0000-0000-0000-000000000002',
            'Storm: no relief staff could reach the house');
  UPDATE timeleave.time_exception SET status = 'acknowledged', decided_by = '0da00000-0000-0000-0000-000000000002', decided_at = now(),
         reason = 'Storm: no relief staff could reach the house'
   WHERE exception_id = '0de00000-0000-0000-0000-000000000002';

  INSERT INTO platform.workflow_route (tenant_id, route_id, code, subject_type, name_en, conditions, priority, status)
    VALUES (t, '0db00000-0000-0000-0000-000000000001', 'ts_big_ot', 'timesheet', 'Large overtime: HR second approval', '{"minOvertimeHours":8}', 10, 'active');
  INSERT INTO platform.workflow_route_step (tenant_id, route_id, step_no, approver_kind, capability, mode, min_approvals)
    VALUES (t, '0db00000-0000-0000-0000-000000000001', 1, 'capability', 'hr', 'any', 1);
  IF timeleave.timesheet_route(t, '{"overtimeHours":3}') IS NOT NULL
     OR timeleave.timesheet_route(t, '{"overtimeHours":9.5}') IS DISTINCT FROM '0db00000-0000-0000-0000-000000000001'::uuid THEN
    RAISE EXCEPTION 'FAIL 5c: second approval only above the organization''s overtime hours';
  END IF;
  UPDATE timeleave.timesheet SET route_id = '0db00000-0000-0000-0000-000000000001' WHERE timesheet_id = '0df00000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE timeleave.timesheet SET status = 'approved', approved_by = '0da00000-0000-0000-0000-000000000002', approved_at = now()
     WHERE timesheet_id = '0df00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 5d: approved without the organization''s second approval';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 5d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
      VALUES (t, 'timesheet', '0df00000-0000-0000-0000-000000000001', 1, 'approved', '0da00000-0000-0000-0000-000000000001', now(), 'hr');
    RAISE EXCEPTION 'FAIL 5e: the employee gave the second approval';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 5e: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at, capability)
    VALUES (t, 'timesheet', '0df00000-0000-0000-0000-000000000001', 1, 'approved', '0da00000-0000-0000-0000-000000000003', now(), 'hr');
  UPDATE timeleave.timesheet SET status = 'approved', approved_by = '0da00000-0000-0000-0000-000000000002', approved_at = now()
   WHERE timesheet_id = '0df00000-0000-0000-0000-000000000001';

  UPDATE timeleave.timesheet SET status = 'locked' WHERE timesheet_id = '0df00000-0000-0000-0000-000000000003';
  IF (SELECT locked_at FROM timeleave.timesheet WHERE timesheet_id = '0df00000-0000-0000-0000-000000000003') IS NULL
     OR (SELECT approved_by FROM timeleave.timesheet WHERE timesheet_id = '0df00000-0000-0000-0000-000000000003') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL 5f: unapproved timesheet not locked for pay at the cut-off';
  END IF;
  RAISE NOTICE 'PASS 5a-f: no self-approval; rest breaches acknowledged first; second approval only where the organization''s route says; unapproved timesheets paid at the cut-off';
END $$;

-- ---------------------------------------------------------------------------------
-- 6. Leave plans: carry-over, payout, the plan's own year
-- ---------------------------------------------------------------------------------
INSERT INTO finance.calendar (tenant_id, calendar_id, code, kind, owner_type, name_en)
  VALUES (current_setting('app.tenant_id')::uuid, '0dc00000-0000-0000-0000-000000000001', 'FY-APR', 'fiscal', 'tenant', 'Fiscal year April to March');
INSERT INTO finance.calendar_period (tenant_id, calendar_id, year_label, period_no, dates, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0dc00000-0000-0000-0000-000000000001', 'FY2026-27', 1, '[2026-04-01,2026-10-01)', 'open'),
  (current_setting('app.tenant_id')::uuid, '0dc00000-0000-0000-0000-000000000001', 'FY2026-27', 2, '[2026-10-01,2027-04-01)', 'open');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; p timeleave.leave_plan;
BEGIN
  BEGIN
    INSERT INTO timeleave.leave_plan (tenant_id, code, name_en, leave_type_code, applies_to, accrual_method, tiers, year_basis, tier_step_basis, carry_over, priority, status, valid_period)
      VALUES (t, 'VAC-X', 'Vacation', 'VAC', '{}', 'per_pay_period', '[{"fromYears":0,"hours":80}]', 'calendar', 'year_start', '{"kind":"limited"}', 50, 'active', '[2026-01-01,)');
    RAISE EXCEPTION 'FAIL 6a: carry-over limit missing';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LEAVE_CARRYOVER_INVALID%' THEN RAISE EXCEPTION 'FAIL 6a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO timeleave.leave_plan (tenant_id, code, name_en, leave_type_code, applies_to, accrual_method, tiers, year_basis, tier_step_basis, carry_over, termination_payout, priority, status, valid_period)
      VALUES (t, 'VAC-X', 'Vacation', 'VAC', '{}', 'per_pay_period', '[{"fromYears":0,"hours":80}]', 'calendar', 'year_start', '{"kind":"none"}', 'none', 50, 'active', '[2026-01-01,)');
    RAISE EXCEPTION 'FAIL 6b: vacation not paid out';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LEAVE_PAYOUT_BELOW_LAW%' THEN RAISE EXCEPTION 'FAIL 6b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO timeleave.leave_plan (tenant_id, code, name_en, leave_type_code, applies_to, accrual_method, year_basis, tier_step_basis, carry_over, priority, status, valid_period)
      VALUES (t, 'UNION', 'Union business', 'UNION', '{}', 'none', 'calendar', 'year_start', '{"kind":"none"}', 50, 'active', '[2026-01-01,)');
    RAISE EXCEPTION 'FAIL 6c: payout assumed for a category the starter does not list';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 6c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO timeleave.leave_plan (tenant_id, code, name_en, leave_type_code, applies_to, accrual_method, tiers, year_basis, tier_step_basis, carry_over, priority, status, valid_period)
      VALUES (t, 'VAC-F', 'Vacation', 'VAC', '{}', 'per_pay_period', '[{"fromYears":0,"hours":80}]', 'fiscal', 'year_start', '{"kind":"none"}', 50, 'active', '[2026-01-01,)');
    RAISE EXCEPTION 'FAIL 6d: fiscal year without its calendar';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO timeleave.leave_plan (tenant_id, plan_id, code, name_en, leave_type_code, agreement_id, applies_to, accrual_method, tiers, year_basis, year_calendar_id, tier_step_basis, carry_over, negative_limit_hours, priority, status, valid_period) VALUES
    (t, '0d930000-0000-0000-0000-000000000001', 'VAC-UA', 'Care agreement vacation', 'VAC', 'UA', '{"agreements":["UA"]}', 'per_pay_period',
     '[{"fromYears":0,"hours":112},{"fromYears":5,"hours":150}]', 'calendar', NULL, 'service_anniversary', '{"kind":"limited","limitHours":40,"expiresMonths":3}', NULL, 10, 'active', '[2026-01-01,)'),
    (t, '0d930000-0000-0000-0000-000000000002', 'VAC-POL', 'Policy vacation', 'VAC', NULL, '{}', 'front_loaded',
     '[{"fromYears":0,"hours":80}]', 'fiscal', '0dc00000-0000-0000-0000-000000000001', 'year_start', '{"kind":"unlimited"}', 16, 20, 'active', '[2026-01-01,)'),
    (t, '0d930000-0000-0000-0000-000000000003', 'SICK-PROMO', 'Sick days from the date of joining the plan', 'SICK', NULL, '{}', 'front_loaded',
     '[{"fromYears":0,"hours":40}]', 'plan_entry', NULL, 'year_start', '{"kind":"none"}', NULL, 10, 'active', '[2026-01-01,)');
  SELECT * INTO p FROM timeleave.leave_plan WHERE plan_id = '0d930000-0000-0000-0000-000000000001';
  IF p.termination_payout <> 'all' OR (SELECT termination_payout FROM timeleave.leave_plan WHERE code = 'SICK-PROMO') <> 'none' THEN
    RAISE EXCEPTION 'FAIL 6e: payout not filled from the starter';
  END IF;
  IF (timeleave.leave_plan_for('0d800000-0000-0000-0000-000000000001', 'VAC', '2027-01-10')).code <> 'VAC-UA'
     OR (timeleave.leave_plan_for('0d800000-0000-0000-0000-000000000004', 'VAC', '2027-01-10')).code <> 'VAC-POL' THEN
    RAISE EXCEPTION 'FAIL 6f: plans by agreement and policy';
  END IF;
  BEGIN
    PERFORM timeleave.leave_plan_for('0d800000-0000-0000-0000-000000000001', 'PARENTAL', '2027-01-10');
    RAISE EXCEPTION 'FAIL 6g: plan assumed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LEAVE_PLAN_MISSING%' THEN RAISE EXCEPTION 'FAIL 6g: %', SQLERRM; END IF;
  END;
  -- One person, three plans, three different years
  IF timeleave.plan_cycle_start('0d930000-0000-0000-0000-000000000001', '0d700000-0000-0000-0000-000000000001', '2027-01-10', 'year') <> '2027-01-01'
     OR timeleave.plan_cycle_start('0d930000-0000-0000-0000-000000000001', '0d700000-0000-0000-0000-000000000001', '2027-01-10', 'tiers') <> '2026-06-01'
     OR timeleave.plan_cycle_start('0d930000-0000-0000-0000-000000000002', '0d700000-0000-0000-0000-000000000001', '2027-01-10', 'year') <> '2026-04-01'
     OR timeleave.plan_cycle_start('0d930000-0000-0000-0000-000000000002', '0d700000-0000-0000-0000-000000000001', '2027-01-10', 'tiers') <> '2026-04-01' THEN
    RAISE EXCEPTION 'FAIL 6h: calendar, service anniversary and fiscal years';
  END IF;
  BEGIN
    PERFORM timeleave.plan_cycle_start('0d930000-0000-0000-0000-000000000003', '0d700000-0000-0000-0000-000000000001', '2027-01-10', 'year');
    RAISE EXCEPTION 'FAIL 6i: plan entry assumed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 6i: %', SQLERRM; END IF;
  END;
  INSERT INTO timeleave.plan_entry (tenant_id, employment_id, plan_code, entered_on, event)
    VALUES (t, '0d700000-0000-0000-0000-000000000001', 'SICK-PROMO', '2026-09-01', 'promotion');
  IF timeleave.plan_cycle_start('0d930000-0000-0000-0000-000000000003', '0d700000-0000-0000-0000-000000000001', '2027-01-10', 'year') <> '2026-09-01'
     OR timeleave.plan_cycle_start('0d930000-0000-0000-0000-000000000003', '0d700000-0000-0000-0000-000000000001', '2027-09-02', 'year') <> '2027-09-01' THEN
    RAISE EXCEPTION 'FAIL 6i: year from the promotion date';
  END IF;
  RAISE NOTICE 'PASS 6a-i: plans state carry-over and payout (vacation always paid); one person holds plans on calendar, fiscal, anniversary and promotion years';
END $$;

-- ---------------------------------------------------------------------------------
-- 7. Declines and the team availability bar
-- ---------------------------------------------------------------------------------
INSERT INTO timeleave.leave_request (tenant_id, leave_request_id, employment_id, leave_type_code, period, hours, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000001', '0d700000-0000-0000-0000-000000000001', 'PARENTAL', '[2027-05-01 00:00-07,2027-11-01 00:00-07)', 900, 'requested'),
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000002', '0d700000-0000-0000-0000-000000000001', 'VAC', '[2027-03-08 00:00-08,2027-03-13 00:00-08)', 37.5, 'requested'),
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000003', '0d700000-0000-0000-0000-000000000003', 'VAC', '[2027-03-02 00:00-08,2027-03-04 00:00-08)', 15, 'approved'),
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000004', '0d700000-0000-0000-0000-000000000002', 'VAC', '[2027-03-03 00:00-08,2027-03-04 00:00-08)', 7.5, 'approved');
INSERT INTO timeleave.leave_request_component (tenant_id, leave_request_id, assignment_id, hours, status) VALUES
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000001', '0d800000-0000-0000-0000-000000000001', 900, 'requested'),
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000002', '0d800000-0000-0000-0000-000000000001', 37.5, 'requested'),
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000003', '0d800000-0000-0000-0000-000000000003', 15, 'approved'),
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000004', '0d800000-0000-0000-0000-000000000002', 7.5, 'approved');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; levels text;
BEGIN
  BEGIN
    UPDATE timeleave.leave_request_component SET status = 'declined', decline_category = 'staffing', decline_reason = 'Short staffed in May'
     WHERE leave_request_id = '0d0a0000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 7a: parental leave refused for staffing';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'STATUTORY_LEAVE_NOT_REFUSABLE%' THEN RAISE EXCEPTION 'FAIL 7a: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE timeleave.leave_request_component SET status = 'declined' WHERE leave_request_id = '0d0a0000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 7b: declined without a reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO core.approval_part (tenant_id, subject_type, subject_id, assignment_id, seq, requester_person_id, approvers, rule, minutes, routed_by, decisions)
      VALUES (t, 'leave_request', '0d0a0000-0000-0000-0000-000000000001', '0d800000-0000-0000-0000-000000000001', 1, '0d600000-0000-0000-0000-000000000001',
              ARRAY['0d800000-0000-0000-0000-000000000002']::uuid[], 'any', 54000, 'coverage',
              '[{"approver":"0d800000-0000-0000-0000-000000000002","decision":"decline","category":"blackout","reason":"Summer blackout"}]');
    RAISE EXCEPTION 'FAIL 7c: manager declined a statutory leave for a blackout';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'STATUTORY_LEAVE_NOT_REFUSABLE%' THEN RAISE EXCEPTION 'FAIL 7c: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 7a-c: declines state why; statutory leave never refused for staffing or a blackout, by any path';

  INSERT INTO timeleave.staffing_level (tenant_id, org_unit_id, days_of_week, min_staff, valid_period)
    VALUES (t, '0d300000-0000-0000-0000-000000000001', '{1,2,3,4,5}', 1, '[2027-01-01,)');
  INSERT INTO timeleave.blackout_period (tenant_id, org_unit_id, period, reason, created_by)
    VALUES (t, '0d300000-0000-0000-0000-000000000001', '[2027-03-04,2027-03-05)', 'Accreditation visit', '0da00000-0000-0000-0000-000000000002');
  SELECT string_agg(day || '=' || level, ' ' ORDER BY day) INTO levels
    FROM timeleave.team_availability('0d300000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-06');
  IF levels <> '2027-03-01=green 2027-03-02=amber 2027-03-03=red 2027-03-04=red 2027-03-05=green 2027-03-06=unknown' THEN
    RAISE EXCEPTION 'FAIL 7d: availability levels %', levels;
  END IF;
  IF (SELECT count(*) FROM information_schema.routines r JOIN information_schema.parameters p ON p.specific_name = r.specific_name
       WHERE r.routine_schema = 'timeleave' AND r.routine_name = 'team_availability' AND p.parameter_mode = 'OUT') <> 2 THEN
    RAISE EXCEPTION 'FAIL 7e: the availability bar returns more than a day and a level';
  END IF;
  RAISE NOTICE 'PASS 7d-e: the availability bar shows green, amber, red or unknown per day, with no names or counts';
END $$;

-- ---------------------------------------------------------------------------------
-- 8. The attendance program: off until turned on; protected absences never counted; HR before discipline
-- ---------------------------------------------------------------------------------
INSERT INTO timeleave.leave_request (tenant_id, leave_request_id, employment_id, leave_type_code, period, hours, status, protected_reason) VALUES
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000011', '0d700000-0000-0000-0000-000000000003', 'SICK', '[2027-01-11 00:00-08,2027-01-12 00:00-08)', 7.5, 'taken', NULL),
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000012', '0d700000-0000-0000-0000-000000000003', 'SICK', '[2027-01-18 00:00-08,2027-01-19 00:00-08)', 7.5, 'taken', 'disability'),
  (current_setting('app.tenant_id')::uuid, '0d0a0000-0000-0000-0000-000000000013', '0d700000-0000-0000-0000-000000000003', 'MED', '[2027-01-25 00:00-08,2027-01-27 00:00-08)', 15, 'taken', NULL);
INSERT INTO timeleave.attendance_program (tenant_id, program_id, code, name_en, applies_to, stages, priority, status)
  VALUES (current_setting('app.tenant_id')::uuid, '0d940000-0000-0000-0000-000000000001', 'AMP', 'Attendance support program', '{}',
          '[{"stageNo":1,"kind":"supportive","absences":4,"periodMonths":6},{"stageNo":2,"kind":"disciplinary","absences":6,"periodMonths":6}]', 10, 'active');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO timeleave.attendance_stage (tenant_id, employment_id, program_id, stage_no, kind, counted_requests, accommodation_considered, opened_by, status)
      VALUES (t, '0d700000-0000-0000-0000-000000000003', '0d940000-0000-0000-0000-000000000001', 1, 'supportive', ARRAY['0d0a0000-0000-0000-0000-000000000011']::uuid[], false, '0da00000-0000-0000-0000-000000000002', 'draft');
    RAISE EXCEPTION 'FAIL 8a: program used before the organization turned it on';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ATTENDANCE_PROGRAM_OFF%' THEN RAISE EXCEPTION 'FAIL 8a: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
    VALUES (t, 'attendance.program_enabled', 'tenant', NULL, 'true', '[2026-01-01,)', gen_random_uuid());
  BEGIN
    INSERT INTO timeleave.attendance_stage (tenant_id, employment_id, program_id, stage_no, kind, counted_requests, accommodation_considered, opened_by, status)
      VALUES (t, '0d700000-0000-0000-0000-000000000003', '0d940000-0000-0000-0000-000000000001', 1, 'supportive',
              ARRAY['0d0a0000-0000-0000-0000-000000000011','0d0a0000-0000-0000-0000-000000000012']::uuid[], false, '0da00000-0000-0000-0000-000000000002', 'draft');
    RAISE EXCEPTION 'FAIL 8b: a disability-related absence counted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ATTENDANCE_PROTECTED_ABSENCE%' THEN RAISE EXCEPTION 'FAIL 8b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO timeleave.attendance_stage (tenant_id, employment_id, program_id, stage_no, kind, counted_requests, accommodation_considered, opened_by, status)
      VALUES (t, '0d700000-0000-0000-0000-000000000003', '0d940000-0000-0000-0000-000000000001', 1, 'supportive',
              ARRAY['0d0a0000-0000-0000-0000-000000000013']::uuid[], false, '0da00000-0000-0000-0000-000000000002', 'draft');
    RAISE EXCEPTION 'FAIL 8b: a statutory medical leave counted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ATTENDANCE_PROTECTED_ABSENCE%' THEN RAISE EXCEPTION 'FAIL 8b: %', SQLERRM; END IF;
  END;
  INSERT INTO timeleave.attendance_stage (tenant_id, employment_id, program_id, stage_no, kind, counted_requests, accommodation_considered, opened_by, status)
    VALUES (t, '0d700000-0000-0000-0000-000000000003', '0d940000-0000-0000-0000-000000000001', 1, 'supportive',
            ARRAY['0d0a0000-0000-0000-0000-000000000011']::uuid[], false, '0da00000-0000-0000-0000-000000000002', 'issued');
  BEGIN
    INSERT INTO timeleave.attendance_stage (tenant_id, employment_id, program_id, stage_no, kind, counted_requests, accommodation_considered, opened_by, status)
      VALUES (t, '0d700000-0000-0000-0000-000000000003', '0d940000-0000-0000-0000-000000000001', 2, 'disciplinary',
              ARRAY['0d0a0000-0000-0000-0000-000000000011']::uuid[], false, '0da00000-0000-0000-0000-000000000002', 'issued');
    RAISE EXCEPTION 'FAIL 8c: stage 2 without considering accommodation';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ACCOMMODATION_NOT_CONSIDERED%' THEN RAISE EXCEPTION 'FAIL 8c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO timeleave.attendance_stage (tenant_id, employment_id, program_id, stage_no, kind, counted_requests, accommodation_considered, opened_by, status)
      VALUES (t, '0d700000-0000-0000-0000-000000000003', '0d940000-0000-0000-0000-000000000001', 2, 'disciplinary',
              ARRAY['0d0a0000-0000-0000-0000-000000000011']::uuid[], true, '0da00000-0000-0000-0000-000000000002', 'issued');
    RAISE EXCEPTION 'FAIL 8d: disciplinary stage without HR''s review';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'HR_REVIEW_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 8d: %', SQLERRM; END IF;
  END;
  INSERT INTO timeleave.attendance_stage (tenant_id, employment_id, program_id, stage_no, kind, counted_requests, accommodation_considered, opened_by, hr_reviewed_by, hr_reviewed_at, status)
    VALUES (t, '0d700000-0000-0000-0000-000000000003', '0d940000-0000-0000-0000-000000000001', 2, 'disciplinary',
            ARRAY['0d0a0000-0000-0000-0000-000000000011']::uuid[], true, '0da00000-0000-0000-0000-000000000002', '0da00000-0000-0000-0000-000000000003', now(), 'issued');
  RAISE NOTICE 'PASS 8a-d: attendance program off until turned on; protected absences never counted; accommodation before stage 2; HR before discipline';
END $$;

-- ---------------------------------------------------------------------------------
-- 9. Scheduling: notice from the setting; late changes need the caution; swaps; offers
-- ---------------------------------------------------------------------------------
INSERT INTO timeleave.shift (tenant_id, shift_id, assignment_id, position_id, location_id, starts_at, ends_at, break_minutes, published, published_by) VALUES
  (current_setting('app.tenant_id')::uuid, '0d950000-0000-0000-0000-000000000001', '0d800000-0000-0000-0000-000000000001', '0d500000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001',
   date_trunc('hour', now()) + interval '1 day', date_trunc('hour', now()) + interval '1 day 8 hours', 30, true, '0da00000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0d950000-0000-0000-0000-000000000002', '0d800000-0000-0000-0000-000000000001', '0d500000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001',
   date_trunc('hour', now()) + interval '60 days', date_trunc('hour', now()) + interval '60 days 8 hours', 30, true, '0da00000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '0d950000-0000-0000-0000-000000000003', '0d800000-0000-0000-0000-000000000003', '0d500000-0000-0000-0000-000000000003', '0d200000-0000-0000-0000-000000000001',
   date_trunc('hour', now()) + interval '2 days', date_trunc('hour', now()) + interval '2 days 8 hours', 30, false, NULL),
  (current_setting('app.tenant_id')::uuid, '0d950000-0000-0000-0000-000000000004', '0d800000-0000-0000-0000-000000000001', '0d500000-0000-0000-0000-000000000001', '0d200000-0000-0000-0000-000000000001',
   date_trunc('hour', now()) + interval '3 days', date_trunc('hour', now()) + interval '3 days 8 hours', 30, true, '0da00000-0000-0000-0000-000000000002');
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT notice_hours FROM timeleave.shift WHERE shift_id = '0d950000-0000-0000-0000-000000000001') <> 336
     OR (SELECT published_at FROM timeleave.shift WHERE shift_id = '0d950000-0000-0000-0000-000000000001') IS NULL THEN
    RAISE EXCEPTION 'FAIL 9a: notice not taken from the organization''s 14 days';
  END IF;
  UPDATE timeleave.shift SET starts_at = starts_at + interval '1 hour', ends_at = ends_at + interval '1 hour' WHERE shift_id = '0d950000-0000-0000-0000-000000000002';
  BEGIN
    UPDATE timeleave.shift SET starts_at = starts_at + interval '2 hours' WHERE shift_id = '0d950000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 9b: shift changed inside the notice without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 9b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'time.schedule_changed_late', 'shift', '0d950000-0000-0000-0000-000000000001', 'shown', 'en', '0da00000-0000-0000-0000-000000000002',
            'Resident admitted overnight; start moved with the employee''s agreement');
  UPDATE timeleave.shift SET starts_at = starts_at + interval '2 hours' WHERE shift_id = '0d950000-0000-0000-0000-000000000001';
  INSERT INTO timeleave.time_exception (tenant_id, assignment_id, shift_id, work_date, kind, status)
    VALUES (t, '0d800000-0000-0000-0000-000000000003', '0d950000-0000-0000-0000-000000000003', current_date + 2, 'rest_period', 'open');
  BEGIN
    UPDATE timeleave.shift SET published = true WHERE shift_id = '0d950000-0000-0000-0000-000000000003';
    RAISE EXCEPTION 'FAIL 9c: published with an open rest-period breach';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 9c: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 9a-c: notice from the setting; late changes need the caution; breaches stop publishing';

  INSERT INTO timeleave.shift_swap (tenant_id, swap_id, shift_id, from_assignment, to_assignment, requested_by, checks, checks_passed, status)
    VALUES (t, '0d960000-0000-0000-0000-000000000001', '0d950000-0000-0000-0000-000000000004', '0d800000-0000-0000-0000-000000000001', '0d800000-0000-0000-0000-000000000003',
            '0da00000-0000-0000-0000-000000000001', '{"credentials":"pass","rest":"pass","overtime":"pass"}', true, 'requested');
  BEGIN
    UPDATE timeleave.shift_swap SET status = 'approved', approved_by = '0da00000-0000-0000-0000-000000000002', approved_at = now()
     WHERE swap_id = '0d960000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 9d: approved before the colleague agreed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 9d: %', SQLERRM; END IF;
  END;
  UPDATE timeleave.shift_swap SET status = 'agreed', colleague_agreed_at = now() WHERE swap_id = '0d960000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE timeleave.shift_swap SET status = 'approved', approved_by = '0da00000-0000-0000-0000-000000000004', approved_at = now()
     WHERE swap_id = '0d960000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 9e: the colleague approved the swap herself';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 9e: %', SQLERRM; END IF;
  END;
  UPDATE timeleave.shift_swap SET status = 'approved', approved_by = '0da00000-0000-0000-0000-000000000002', approved_at = now()
   WHERE swap_id = '0d960000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE timeleave.shift SET assignment_id = '0d800000-0000-0000-0000-000000000002' WHERE shift_id = '0d950000-0000-0000-0000-000000000004';
    RAISE EXCEPTION 'FAIL 9e: reassigned to someone outside the swap without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED%' THEN RAISE EXCEPTION 'FAIL 9e: %', SQLERRM; END IF;
  END;
  UPDATE timeleave.shift SET assignment_id = '0d800000-0000-0000-0000-000000000003' WHERE shift_id = '0d950000-0000-0000-0000-000000000004';
  RAISE NOTICE 'PASS 9d-e: swaps agreed by the colleague, checked and approved by the manager, then applied inside the notice';

  BEGIN
    INSERT INTO timeleave.shift_offer (tenant_id, shift_id, offered_to, method, offered_by, response)
      VALUES (t, '0d950000-0000-0000-0000-000000000002', '0d800000-0000-0000-0000-000000000003', 'seniority', '0da00000-0000-0000-0000-000000000002', 'accepted');
    RAISE EXCEPTION 'FAIL 9f: offer answered with no time';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO timeleave.shift_offer (tenant_id, shift_id, offered_to, method, rank, offered_by, response, responded_at)
    VALUES (t, '0d950000-0000-0000-0000-000000000002', '0d800000-0000-0000-0000-000000000003', 'seniority', 1, '0da00000-0000-0000-0000-000000000002', 'declined', now());
  RAISE NOTICE 'PASS 9f: every offer and its answer is logged';
END $$;

-- ---------------------------------------------------------------------------------
-- 10. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', 'd2222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM timeleave.time_exception) <> 0 OR (SELECT count(*) FROM timeleave.leave_plan) <> 0
     OR (SELECT count(*) FROM timeleave.attendance_stage) <> 0 OR (SELECT count(*) FROM timeleave.shift_swap) <> 0
     OR (SELECT count(*) FROM timeleave.staffing_level) <> 0 OR (SELECT count(*) FROM timeleave.overtime_exemption) <> 0 THEN
    RAISE EXCEPTION 'FAIL 10: another organization''s time and leave data is visible';
  END IF;
  RAISE NOTICE 'PASS 10: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0013_smoke: all checks passed'
