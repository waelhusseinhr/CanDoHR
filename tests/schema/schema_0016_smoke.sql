-- Smoke test for schema/0016_succession_workforce_decisions.sql (docs/30): the new settings and switches, critical
-- roles scored on the organization's weights and confirmed by HR, positions the law requires, flight risk, retirement
-- and vacancy dates, career aspirations, talent reviews with potential and the nine-box, bias prompts only for large
-- enough groups, succession plans through the route with an emergency successor, successors with readiness,
-- aspiration and language gaps, unionized roles as development only, continuity sheets without secrets, talent pools,
-- career paths from real moves, workforce segments, thin history, versioned scenarios, demand from drivers, gap
-- strategies with the labour relations review, the annual position plan through its route, RLS and tenant isolation.
-- Run after every migration, 0001 to 0016 (CI, after the 0015 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0016_smoke.sql
-- Review dates are relative to current_date. It inserts test rows; run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit, benefits TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, finance, compliance, talent, comp, recruit, benefits TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ref, platform, core, payroll, timeleave, talent, recruit, comp, compliance, benefits TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('16111111-1111-1111-1111-111111111111', 'Succession Test Township'),
  ('16222222-2222-2222-2222-222222222222', 'Other Organization')
ON CONFLICT DO NOTHING;

SET ROLE cando_app;
SELECT set_config('app.tenant_id', '16111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: settings, switches, cautions, starter routes, RLS
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text; t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  IF (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/30%') <> 12
     OR (SELECT count(*) FROM platform.setting_definition WHERE decision_ref LIKE 'docs/30%' AND decision_status = 'pending') <> 0 THEN
    RAISE EXCEPTION 'FAIL 1a: expected 12 settings from docs/30, none left to choose at setup';
  END IF;
  IF (platform.setting(t, 'succession.talent_review_enabled'))::boolean OR (platform.setting(t, 'succession.nine_box_enabled'))::boolean
     OR (platform.setting(t, 'workforce.planning_enabled'))::boolean OR (platform.setting(t, 'succession.employee_sees_placement'))::boolean
     OR NOT (platform.setting(t, 'succession.bias_prompts'))::boolean THEN
    RAISE EXCEPTION 'FAIL 1b: talent reviews, the nine-box and workforce planning start off; bias prompts on; placements hidden';
  END IF;
  IF platform.setting(t, 'succession.critical_weights') <> '{"impact":20,"hardToReplace":20,"singlePointOfFailure":20,"marketScarcity":20,"requiredByLaw":20}'::jsonb
     OR jsonb_array_length(platform.setting(t, 'succession.potential_criteria') -> 'criteria') <> 4
     OR (SELECT count(*) FROM jsonb_object_keys(platform.setting(t, 'succession.nine_box_boxes') -> 'boxes')) <> 9
     OR platform.setting_number(t, 'succession.plan_review_months') <> 12 OR platform.setting_number(t, 'succession.plan_review_reminder_days') <> 30
     OR platform.setting_number(t, 'succession.continuity_review_months') <> 12
     OR platform.setting(t, 'workforce.thin_history') <> '{"minPeople":10,"minYears":2}'::jsonb THEN
    RAISE EXCEPTION 'FAIL 1c: decided defaults not in place';
  END IF;
  IF (SELECT count(*) FROM ref.caution WHERE caution_code IN ('succession.appoint_without_posting','workforce.reduction_unionized') AND reason_always) <> 2
     OR (SELECT count(*) FROM platform.workflow_route WHERE tenant_id = t AND subject_type IN ('succession_plan','talent_pool_membership','position_plan')) <> 3
     OR (SELECT count(*) FROM platform.workflow_route_step s JOIN platform.workflow_route r ON r.route_id = s.route_id
          WHERE r.tenant_id = t AND r.code = 'position_plan') <> 3
     OR (SELECT s.approver_kind FROM platform.workflow_route_step s JOIN platform.workflow_route r ON r.route_id = s.route_id
          WHERE r.tenant_id = t AND r.code = 'talent_pool_membership') <> 'subject_owner' THEN
    RAISE EXCEPTION 'FAIL 1d: cautions or starter routes missing';
  END IF;
  SELECT string_agg(c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'talent' AND c.relkind = 'r'
     AND c.relname IN ('critical_role','flight_risk_assessment','retirement_outlook','vacancy_risk','career_aspiration','talent_review',
                       'potential_assessment','nine_box_placement','placement_history','succession_plan','language_proficiency','successor',
                       'continuity_sheet','succession_view_log','talent_pool','pool_member','career_path_step','workforce_segment',
                       'turnover_history','workforce_scenario','workforce_driver','workforce_ratio','supply_rate','gap_strategy','plan_assumption')
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1e: RLS missing on %', bad; END IF;
  RAISE NOTICE 'PASS 1a-e: settings, switches off, defaults, cautions, starter routes (with the pool owner as approver), RLS';
END $$;

-- Fixtures: a township in Ontario. Ana is the clerk (a position the law requires), Ben the deputy clerk (who moved up
-- from analyst), Cy (part time) and Dee analysts, Eli in a unionized operations position; HR, finance, the CAO and
-- labour relations are users without a person record here
INSERT INTO core.person (tenant_id, person_id, person_type) VALUES
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000001', 'employee'),
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000002', 'employee'),
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000003', 'employee'),
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000004', 'employee'),
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000005', 'employee');
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, '16a00000-0000-0000-0000-000000000001', 'ana', 'ana@example.test', '16600000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '16a00000-0000-0000-0000-000000000002', 'ben', 'ben@example.test', '16600000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '16a00000-0000-0000-0000-000000000003', 'cy',  'cy@example.test',  '16600000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '16a00000-0000-0000-0000-000000000004', 'dee', 'dee@example.test', '16600000-0000-0000-0000-000000000004'),
  (current_setting('app.tenant_id')::uuid, '16a00000-0000-0000-0000-000000000005', 'hr',  'hr@example.test',  NULL),
  (current_setting('app.tenant_id')::uuid, '16a00000-0000-0000-0000-000000000006', 'fin', 'fin@example.test', NULL),
  (current_setting('app.tenant_id')::uuid, '16a00000-0000-0000-0000-000000000007', 'cao', 'cao@example.test', NULL),
  (current_setting('app.tenant_id')::uuid, '16a00000-0000-0000-0000-000000000008', 'lr',  'lr@example.test',  NULL);
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, '16100000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, '16200000-0000-0000-0000-000000000001');
INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction) VALUES
  (current_setting('app.tenant_id')::uuid, '16200000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Township hall', '1 Main St', 'Russell', 'ON', 'K4R 1A1', 'America/Toronto', 'ON');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, '16300000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES
  (current_setting('app.tenant_id')::uuid, '16400000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '16400000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '16400000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '16400000-0000-0000-0000-000000000004');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en, title_fr) VALUES
  (current_setting('app.tenant_id')::uuid, '16400000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'CLERK', 'Municipal Clerk', 'Greffier municipal'),
  (current_setting('app.tenant_id')::uuid, '16400000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'DEPUTY', 'Deputy Clerk', 'Greffier adjoint'),
  (current_setting('app.tenant_id')::uuid, '16400000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'ANALYST', 'Policy Analyst', 'Analyste des politiques'),
  (current_setting('app.tenant_id')::uuid, '16400000-0000-0000-0000-000000000004', '[2020-01-01,)', gen_random_uuid(), 'OPS', 'Roads Operator', 'Opérateur des routes');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, '16500000-0000-0000-0000-000000000001', 'P-CLERK'),
  (current_setting('app.tenant_id')::uuid, '16500000-0000-0000-0000-000000000002', 'P-DEPUTY'),
  (current_setting('app.tenant_id')::uuid, '16500000-0000-0000-0000-000000000003', 'P-ANALYST'),
  (current_setting('app.tenant_id')::uuid, '16500000-0000-0000-0000-000000000004', 'P-OPS');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en, head_position_id) VALUES
  (current_setting('app.tenant_id')::uuid, '16300000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '16100000-0000-0000-0000-000000000001', 'DEPT', 'CLERKS', 'Clerk''s office', '16500000-0000-0000-0000-000000000001');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status, language_requirement, agreement_id, bargaining_unit) VALUES
  (current_setting('app.tenant_id')::uuid, '16500000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '16400000-0000-0000-0000-000000000001', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', NULL, 1, 'permanent', 'active', 'bilingual_b', NULL, NULL),
  (current_setting('app.tenant_id')::uuid, '16500000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), '16400000-0000-0000-0000-000000000002', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', '16500000-0000-0000-0000-000000000001', 1, 'permanent', 'active', 'bilingual_b', NULL, NULL),
  (current_setting('app.tenant_id')::uuid, '16500000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), '16400000-0000-0000-0000-000000000003', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', '16500000-0000-0000-0000-000000000002', 30, 'permanent', 'active', 'en', NULL, NULL),
  (current_setting('app.tenant_id')::uuid, '16500000-0000-0000-0000-000000000004', '[2020-01-01,)', gen_random_uuid(), '16400000-0000-0000-0000-000000000004', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', '16500000-0000-0000-0000-000000000002', 5, 'permanent', 'active', 'en', 'CUPE-1', 'outside_workers');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, '16700000-0000-0000-0000-000000000001', '16600000-0000-0000-0000-000000000001', '16100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '16700000-0000-0000-0000-000000000002', '16600000-0000-0000-0000-000000000002', '16100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '16700000-0000-0000-0000-000000000003', '16600000-0000-0000-0000-000000000003', '16100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '16700000-0000-0000-0000-000000000004', '16600000-0000-0000-0000-000000000004', '16100000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '16700000-0000-0000-0000-000000000005', '16600000-0000-0000-0000-000000000005', '16100000-0000-0000-0000-000000000001');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000001', '16700000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000002', '16700000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000003', '16700000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000004', '16700000-0000-0000-0000-000000000004'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000005', '16700000-0000-0000-0000-000000000005');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type) VALUES
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), '16500000-0000-0000-0000-000000000001', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000002', '[2022-01-01,2025-01-01)', gen_random_uuid(), '16500000-0000-0000-0000-000000000003', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000002', '[2025-01-01,)', gen_random_uuid(), '16500000-0000-0000-0000-000000000002', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000003', '[2024-01-01,)', gen_random_uuid(), '16500000-0000-0000-0000-000000000003', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', 0.6, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000004', '[2024-01-01,)', gen_random_uuid(), '16500000-0000-0000-0000-000000000003', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', 1, true, 'permanent'),
  (current_setting('app.tenant_id')::uuid, '16800000-0000-0000-0000-000000000005', '[2024-01-01,)', gen_random_uuid(), '16500000-0000-0000-0000-000000000004', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001', 1, true, 'permanent');

-- ---------------------------------------------------------------------------------
-- 2. Critical roles and risk
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r talent.critical_role;
BEGIN
  BEGIN
    INSERT INTO talent.critical_role (tenant_id, position_id, scores, required_by_law, legal_basis, scored_by, owner_user, status)
      VALUES (t, '16500000-0000-0000-0000-000000000001', '{"impact":5,"hardToReplace":4,"singlePointOfFailure":5,"marketScarcity":3}', true,
              'Municipal Act, 2001, s. 228', '16a00000-0000-0000-0000-000000000007', '16a00000-0000-0000-0000-000000000007', 'proposed');
    RAISE EXCEPTION 'FAIL 2a: a role scored on four of the five criteria';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CRITICAL_SCORE_INVALID%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.critical_role (tenant_id, position_id, scores, required_by_law, legal_basis, scored_by, owner_user, status)
      VALUES (t, '16500000-0000-0000-0000-000000000001', '{"impact":6,"hardToReplace":4,"singlePointOfFailure":5,"marketScarcity":3,"requiredByLaw":5}', true,
              'Municipal Act, 2001, s. 228', '16a00000-0000-0000-0000-000000000007', '16a00000-0000-0000-0000-000000000007', 'proposed');
    RAISE EXCEPTION 'FAIL 2a: a score of 6';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CRITICAL_SCORE_INVALID%' THEN RAISE EXCEPTION 'FAIL 2a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.critical_role (tenant_id, position_id, scores, required_by_law, legal_basis, scored_by, owner_user, status)
      VALUES (t, '16500000-0000-0000-0000-000000000002', '{"impact":3,"hardToReplace":3,"singlePointOfFailure":3,"marketScarcity":3,"requiredByLaw":5}', true,
              NULL, '16a00000-0000-0000-0000-000000000007', '16a00000-0000-0000-0000-000000000007', 'proposed');
    RAISE EXCEPTION 'FAIL 2b: required by law with no legal basis';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE '%critical_role_law%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  -- The organization's weights must add up to 100 (the failed insert rolls the setting back too)
  BEGIN
    INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
      VALUES (t, 'succession.critical_weights', '{"impact":40,"hardToReplace":20,"singlePointOfFailure":20,"marketScarcity":20,"requiredByLaw":20}', '[2000-01-01,)', gen_random_uuid());
    INSERT INTO talent.critical_role (tenant_id, position_id, scores, required_by_law, scored_by, owner_user, status)
      VALUES (t, '16500000-0000-0000-0000-000000000002', '{"impact":3,"hardToReplace":3,"singlePointOfFailure":3,"marketScarcity":3,"requiredByLaw":1}', false,
              '16a00000-0000-0000-0000-000000000007', '16a00000-0000-0000-0000-000000000007', 'proposed');
    RAISE EXCEPTION 'FAIL 2c: weights adding up to 120 accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CRITICAL_WEIGHTS_INVALID%' THEN RAISE EXCEPTION 'FAIL 2c: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.critical_role (tenant_id, critical_role_id, position_id, scores, required_by_law, legal_basis, scored_by, owner_user, status)
    VALUES (t, '16b00000-0000-0000-0000-000000000001', '16500000-0000-0000-0000-000000000001',
            '{"impact":5,"hardToReplace":4,"singlePointOfFailure":5,"marketScarcity":3,"requiredByLaw":5}', true,
            'Municipal Act, 2001, s. 228', '16a00000-0000-0000-0000-000000000007', '16a00000-0000-0000-0000-000000000007', 'proposed')
    RETURNING * INTO r;
  IF r.score <> 4.40 THEN RAISE EXCEPTION 'FAIL 2d: score % (4.40 expected with equal weights)', r.score; END IF;
  BEGIN
    UPDATE talent.critical_role SET status = 'confirmed', confirmed_by = '16a00000-0000-0000-0000-000000000007', confirmed_at = now()
     WHERE critical_role_id = r.critical_role_id;
    RAISE EXCEPTION 'FAIL 2e: the leader who scored the role confirmed it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 2e: %', SQLERRM; END IF;
  END;
  UPDATE talent.critical_role SET status = 'confirmed', confirmed_by = '16a00000-0000-0000-0000-000000000005', confirmed_at = now()
   WHERE critical_role_id = r.critical_role_id;
  IF (SELECT missing FROM talent.required_roles_without_plan(t) WHERE position_id = '16500000-0000-0000-0000-000000000001') <> 'approved_plan' THEN
    RAISE EXCEPTION 'FAIL 2f: HR not reminded that the clerk has no succession plan';
  END IF;
  RAISE NOTICE 'PASS 2a-f: five criteria scored 1 to 5, the law''s basis stated, weights adding up to 100, weighted score, HR confirms, reminder';
END $$;

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  BEGIN
    INSERT INTO talent.flight_risk_assessment (tenant_id, employment_id, level, note, assessed_by, assessed_on)
      VALUES (t, '16700000-0000-0000-0000-000000000003', 'low', 'Happy here', '16a00000-0000-0000-0000-000000000003', current_date);
    RAISE EXCEPTION 'FAIL 2g: an employee assessed her own flight risk';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_REVIEW%' THEN RAISE EXCEPTION 'FAIL 2g: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.flight_risk_assessment (tenant_id, employment_id, level, note, assessed_by, assessed_on)
    VALUES (t, '16700000-0000-0000-0000-000000000003', 'medium', 'Asked about the analyst opening in the county', '16a00000-0000-0000-0000-000000000002', current_date);
  BEGIN
    INSERT INTO talent.retirement_outlook (tenant_id, employment_id, eligible_on, eligibility_source, intention_shared, intended_window)
      VALUES (t, '16700000-0000-0000-0000-000000000001', '2028-06-30', 'pension_plan', false, '[2028-07-01,2029-01-01)');
    RAISE EXCEPTION 'FAIL 2h: an intention recorded that the employee did not share';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO talent.retirement_outlook (tenant_id, employment_id, eligible_on, intention_shared)
      VALUES (t, '16700000-0000-0000-0000-000000000001', '2028-06-30', false);
    RAISE EXCEPTION 'FAIL 2h: an eligibility date without its source';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.retirement_outlook (tenant_id, employment_id, eligible_on, eligibility_source, intention_shared, intended_window, phased_interest, shared_at)
    VALUES (t, '16700000-0000-0000-0000-000000000001', '2028-06-30', 'pension_plan', true, '[2028-07-01,2029-01-01)', true, now());
  INSERT INTO talent.vacancy_risk (tenant_id, employment_id, kind, may_vacate_on, recorded_by)
    VALUES (t, '16700000-0000-0000-0000-000000000004', 'authorization_end', '2027-08-31', '16a00000-0000-0000-0000-000000000005');
  INSERT INTO talent.career_aspiration (tenant_id, person_id, target_job_ids, target_text, mobility, timeframe, open_to_succession) VALUES
    (t, '16600000-0000-0000-0000-000000000002', ARRAY['16400000-0000-0000-0000-000000000001']::uuid[], 'Clerk', '{"relocate":false}', '2 years', true),
    (t, '16600000-0000-0000-0000-000000000004', '{}', 'Stay in policy work', '{"relocate":true}', NULL, false);
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'talent' AND table_name IN ('retirement_outlook','vacancy_risk')
               AND column_name ~ 'birth|age|permit|immigration|citizenship') THEN
    RAISE EXCEPTION 'FAIL 2i: age or immigration details stored per person';
  END IF;
  RAISE NOTICE 'PASS 2g-i: flight risk is the manager''s with a note; retirement from eligibility and what the employee shares; vacancy dates without immigration details';
END $$;

-- ---------------------------------------------------------------------------------
-- 3. Talent reviews, potential and the nine-box; bias prompts
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; a talent.potential_assessment; n talent.nine_box_placement;
BEGIN
  BEGIN
    INSERT INTO talent.talent_review (tenant_id, code, name_en, period, participants, owner_user, status)
      VALUES (t, 'TR-2026', '2026 talent review', '[2026-01-01,2027-01-01)', ARRAY['16a00000-0000-0000-0000-000000000002','16a00000-0000-0000-0000-000000000007']::uuid[], '16a00000-0000-0000-0000-000000000005', 'open');
    RAISE EXCEPTION 'FAIL 3a: a talent review while they are off';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FEATURE_OFF%' THEN RAISE EXCEPTION 'FAIL 3a: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'succession.talent_review_enabled', 'true', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO talent.talent_review (tenant_id, review_id, code, name_en, period, participants, owner_user, status)
    VALUES (t, '16c00000-0000-0000-0000-000000000001', 'TR-2026', '2026 talent review', '[2026-01-01,2027-01-01)',
            ARRAY['16a00000-0000-0000-0000-000000000002','16a00000-0000-0000-0000-000000000007']::uuid[], '16a00000-0000-0000-0000-000000000005', 'open');
  IF (SELECT uses_nine_box FROM talent.talent_review WHERE review_id = '16c00000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL 3b: the nine-box used while it is off';
  END IF;
  BEGIN
    INSERT INTO talent.nine_box_placement (tenant_id, review_id, employment_id, performance, potential, placed_by)
      VALUES (t, '16c00000-0000-0000-0000-000000000001', '16700000-0000-0000-0000-000000000004', 'high', 'high', '16a00000-0000-0000-0000-000000000002');
    RAISE EXCEPTION 'FAIL 3b: a nine-box placement in a review without it';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FEATURE_OFF%' THEN RAISE EXCEPTION 'FAIL 3b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.talent_review (tenant_id, code, name_en, period, uses_nine_box, participants, owner_user, status)
      VALUES (t, 'TR-X', 'Nine-box', '[2026-01-01,2027-01-01)', true, ARRAY['16a00000-0000-0000-0000-000000000002']::uuid[], '16a00000-0000-0000-0000-000000000005', 'open');
    RAISE EXCEPTION 'FAIL 3b: the nine-box turned on for one review while the organization has it off';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FEATURE_OFF%' THEN RAISE EXCEPTION 'FAIL 3b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'succession.nine_box_enabled', 'true', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO talent.talent_review (tenant_id, review_id, code, name_en, period, participants, owner_user, status)
    VALUES (t, '16c00000-0000-0000-0000-000000000002', 'TR-2026-9', '2026 talent review with the nine-box', '[2026-01-01,2027-01-01)',
            ARRAY['16a00000-0000-0000-0000-000000000002','16a00000-0000-0000-0000-000000000007']::uuid[], '16a00000-0000-0000-0000-000000000005', 'open');
  IF NOT (SELECT uses_nine_box FROM talent.talent_review WHERE review_id = '16c00000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'FAIL 3c: the nine-box not filled from the organization''s setting';
  END IF;
  -- Potential against the organization's criteria, never one's own, with the stated aspiration beside it
  BEGIN
    INSERT INTO talent.potential_assessment (tenant_id, review_id, employment_id, criteria, potential, assessed_by, assessed_on)
      VALUES (t, '16c00000-0000-0000-0000-000000000002', '16700000-0000-0000-0000-000000000003',
              '{"learning_agility":"high","leadership":"high","aspiration":"high","engagement":"high"}', 'high', '16a00000-0000-0000-0000-000000000003', current_date);
    RAISE EXCEPTION 'FAIL 3d: an employee assessed her own potential';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_REVIEW%' THEN RAISE EXCEPTION 'FAIL 3d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.potential_assessment (tenant_id, review_id, employment_id, criteria, potential, assessed_by, assessed_on)
      VALUES (t, '16c00000-0000-0000-0000-000000000002', '16700000-0000-0000-0000-000000000004',
              '{"learning_agility":"high","leadership":"moderate","aspiration":"low","engagement":"high","charisma":"high"}', 'moderate', '16a00000-0000-0000-0000-000000000002', current_date);
    RAISE EXCEPTION 'FAIL 3d: a criterion the organization does not use';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'POTENTIAL_CRITERION_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 3d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.potential_assessment (tenant_id, review_id, employment_id, criteria, potential, assessed_by, assessed_on)
      VALUES (t, '16c00000-0000-0000-0000-000000000002', '16700000-0000-0000-0000-000000000004',
              '{"learning_agility":"high","leadership":"moderate"}', 'moderate', '16a00000-0000-0000-0000-000000000002', current_date);
    RAISE EXCEPTION 'FAIL 3d: two of the four criteria assessed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 3d: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.potential_assessment (tenant_id, review_id, employment_id, criteria, potential, assessed_by, assessed_on)
    VALUES (t, '16c00000-0000-0000-0000-000000000002', '16700000-0000-0000-0000-000000000004',
            '{"learning_agility":"high","leadership":"moderate","aspiration":"low","engagement":"high"}', 'moderate', '16a00000-0000-0000-0000-000000000002', current_date)
    RETURNING * INTO a;
  IF NOT (a.aspiration ->> 'stated')::boolean OR (a.aspiration ->> 'openToSuccession')::boolean THEN
    RAISE EXCEPTION 'FAIL 3e: Dee''s own aspiration (not open to succession) not shown beside the assessment: %', a.aspiration;
  END IF;
  INSERT INTO talent.potential_assessment (tenant_id, review_id, employment_id, criteria, potential, assessed_by, assessed_on)
    VALUES (t, '16c00000-0000-0000-0000-000000000002', '16700000-0000-0000-0000-000000000003',
            '{"learning_agility":"moderate","leadership":"low","aspiration":"moderate","engagement":"moderate"}', 'low', '16a00000-0000-0000-0000-000000000002', current_date)
    RETURNING * INTO a;
  IF a.aspiration <> '{"stated":false}'::jsonb THEN RAISE EXCEPTION 'FAIL 3e: an aspiration Cy never stated: %', a.aspiration; END IF;
  -- Placements and moves with a reason
  INSERT INTO talent.nine_box_placement (tenant_id, placement_id, review_id, employment_id, performance, potential, placed_by)
    VALUES (t, '16d00000-0000-0000-0000-000000000001', '16c00000-0000-0000-0000-000000000002', '16700000-0000-0000-0000-000000000004', 'high', 'moderate', '16a00000-0000-0000-0000-000000000002')
    RETURNING * INTO n;
  IF n.box <> 'moderate_high' THEN RAISE EXCEPTION 'FAIL 3f: box % (moderate_high expected)', n.box; END IF;
  BEGIN
    UPDATE talent.nine_box_placement SET potential = 'high' WHERE placement_id = n.placement_id;
    RAISE EXCEPTION 'FAIL 3f: moved without a reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PLACEMENT_REASON_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 3f: %', SQLERRM; END IF;
  END;
  UPDATE talent.nine_box_placement SET potential = 'high', reason = 'Led the records digitization across two departments', placed_by = '16a00000-0000-0000-0000-000000000007'
   WHERE placement_id = n.placement_id;
  IF (SELECT count(*) FROM talent.placement_history WHERE placement_id = n.placement_id AND old_box = 'moderate_high' AND new_box = 'high_high') <> 1 THEN
    RAISE EXCEPTION 'FAIL 3f: the move not kept';
  END IF;
  INSERT INTO talent.nine_box_placement (tenant_id, review_id, employment_id, performance, potential, placed_by)
    VALUES (t, '16c00000-0000-0000-0000-000000000002', '16700000-0000-0000-0000-000000000003', 'moderate', 'low', '16a00000-0000-0000-0000-000000000002');
  IF EXISTS (SELECT 1 FROM talent.bias_check_part_time('16c00000-0000-0000-0000-000000000002')) THEN
    RAISE EXCEPTION 'FAIL 3g: a bias prompt for groups of one';
  END IF;
  IF NOT talent.named_on('talent_review', '16c00000-0000-0000-0000-000000000002', '16a00000-0000-0000-0000-000000000002')
     OR talent.named_on('talent_review', '16c00000-0000-0000-0000-000000000002', '16a00000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'FAIL 3h: review data not limited to the people named on it';
  END IF;
  RAISE NOTICE 'PASS 3a-h: switched on by the organization; potential on its criteria with the aspiration; nine-box moves kept with reasons; bias prompts suppressed for small groups; named people only';
END $$;

-- Twenty more analysts, ten part time: both groups reach 10 and the prompt shows
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; i int; p uuid; e uuid; a uuid; g record; pt numeric; ft numeric;
BEGIN
  FOR i IN 1..20 LOOP
    p := gen_random_uuid(); e := gen_random_uuid(); a := gen_random_uuid();
    INSERT INTO core.person (tenant_id, person_id, person_type) VALUES (t, p, 'employee');
    INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES (t, e, p, '16100000-0000-0000-0000-000000000001');
    INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES (t, a, e);
    INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type)
      VALUES (t, a, '[2024-01-01,)', gen_random_uuid(), '16500000-0000-0000-0000-000000000003', '16300000-0000-0000-0000-000000000001', '16200000-0000-0000-0000-000000000001',
              CASE WHEN i <= 10 THEN 0.5 ELSE 1 END, true, 'permanent');
    INSERT INTO talent.nine_box_placement (tenant_id, review_id, employment_id, performance, potential, placed_by)
      VALUES (t, '16c00000-0000-0000-0000-000000000002', e, 'moderate',
              CASE WHEN i <= 6 OR i IN (11, 12) THEN 'low' ELSE 'moderate' END, '16a00000-0000-0000-0000-000000000002');
  END LOOP;
  SELECT low_potential_share INTO pt FROM talent.bias_check_part_time('16c00000-0000-0000-0000-000000000002') WHERE grp = 'part_time';
  SELECT low_potential_share INTO ft FROM talent.bias_check_part_time('16c00000-0000-0000-0000-000000000002') WHERE grp = 'full_time';
  IF pt IS DISTINCT FROM 63.6 OR ft IS DISTINCT FROM 18.2 THEN
    RAISE EXCEPTION 'FAIL 3i: part-time % and full-time % placed at low potential (63.6 and 18.2 expected)', pt, ft;
  END IF;
  RAISE NOTICE 'PASS 3i: bias prompt shown once both groups have 10 or more';
END $$;

-- ---------------------------------------------------------------------------------
-- 4. Succession plans, successors, language gaps, unionized roles
-- ---------------------------------------------------------------------------------
INSERT INTO talent.language_proficiency (tenant_id, person_id, language, level, assessed_on, source) VALUES
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000002', 'en', 'C', '2025-01-01', 'test'),
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000002', 'fr', 'A', '2025-01-01', 'test'),
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000004', 'en', 'C', '2025-01-01', 'test'),
  (current_setting('app.tenant_id')::uuid, '16600000-0000-0000-0000-000000000004', 'fr', 'C', '2025-01-01', 'test');

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; route uuid; p talent.succession_plan; s talent.successor;
BEGIN
  route := platform.route_for(t, 'succession_plan', '{}');
  INSERT INTO talent.succession_plan (tenant_id, plan_id, position_id, critical_role_id, owner_user, external_hire_option, status)
    VALUES (t, '16e00000-0000-0000-0000-000000000001', '16500000-0000-0000-0000-000000000001', '16b00000-0000-0000-0000-000000000001',
            '16a00000-0000-0000-0000-000000000007', false, 'draft');
  BEGIN
    UPDATE talent.succession_plan SET status = 'submitted' WHERE plan_id = '16e00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4a: submitted without its route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4a: %', SQLERRM; END IF;
  END;
  UPDATE talent.succession_plan SET status = 'submitted', route_id = route WHERE plan_id = '16e00000-0000-0000-0000-000000000001';
  BEGIN
    INSERT INTO talent.successor (tenant_id, plan_id, employment_id, readiness, proposed_by, status)
      VALUES (t, '16e00000-0000-0000-0000-000000000001', '16700000-0000-0000-0000-000000000002', 'soon', '16a00000-0000-0000-0000-000000000007', 'proposed');
    RAISE EXCEPTION 'FAIL 4b: a readiness level not on the organization''s list';
  EXCEPTION WHEN foreign_key_violation THEN
    IF SQLERRM NOT LIKE 'LIST_VALUE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 4b: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.successor (tenant_id, plan_id, employment_id, readiness, proposed_by, status)
    VALUES (t, '16e00000-0000-0000-0000-000000000001', '16700000-0000-0000-0000-000000000002', 'ready_now', '16a00000-0000-0000-0000-000000000007', 'proposed')
    RETURNING * INTO s;
  IF s.aspiration_mismatch OR s.language_gap IS DISTINCT FROM 'fr B' THEN
    RAISE EXCEPTION 'FAIL 4c: Ben (wants to be clerk, French A for a level B position): mismatch %, gap %', s.aspiration_mismatch, s.language_gap;
  END IF;
  INSERT INTO talent.successor (tenant_id, plan_id, employment_id, readiness, proposed_by, status)
    VALUES (t, '16e00000-0000-0000-0000-000000000001', '16700000-0000-0000-0000-000000000004', '3_plus_years', '16a00000-0000-0000-0000-000000000007', 'proposed')
    RETURNING * INTO s;
  IF NOT s.aspiration_mismatch OR s.language_gap IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL 4c: Dee (not open to succession, bilingual C): mismatch %, gap %', s.aspiration_mismatch, s.language_gap;
  END IF;
  BEGIN
    UPDATE talent.succession_plan SET status = 'approved' WHERE plan_id = '16e00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4d: approved without its route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 4d: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'succession_plan', '16e00000-0000-0000-0000-000000000001', 1, 'approved', '16a00000-0000-0000-0000-000000000007', now());
    RAISE EXCEPTION 'FAIL 4e: the plan owner approved her own plan';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 4e: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'succession_plan', '16e00000-0000-0000-0000-000000000001', 1, 'approved', '16a00000-0000-0000-0000-000000000005', now());
  BEGIN
    UPDATE talent.succession_plan SET status = 'approved' WHERE plan_id = '16e00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4f: a position the law requires approved without an emergency successor';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'EMERGENCY_SUCCESSOR_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 4f: %', SQLERRM; END IF;
  END;
  UPDATE talent.succession_plan SET status = 'approved', emergency_successor_employment_id = '16700000-0000-0000-0000-000000000002'
   WHERE plan_id = '16e00000-0000-0000-0000-000000000001'
   RETURNING * INTO p;
  IF p.last_reviewed_on <> current_date OR p.review_due_on <> (current_date + interval '12 months')::date OR p.development_only THEN
    RAISE EXCEPTION 'FAIL 4g: reviewed %, due % (a year after approval expected)', p.last_reviewed_on, p.review_due_on;
  END IF;
  IF (SELECT count(*) FROM talent.successor WHERE plan_id = p.plan_id AND status = 'approved') <> 2
     OR EXISTS (SELECT 1 FROM talent.required_roles_without_plan(t)) THEN
    RAISE EXCEPTION 'FAIL 4g: successors not approved with the plan, or HR still reminded';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM talent.plans_due_for_review(t, p.review_due_on - 30) WHERE plan_id = p.plan_id AND NOT overdue)
     OR EXISTS (SELECT 1 FROM talent.plans_due_for_review(t, p.review_due_on - 29))
     OR NOT EXISTS (SELECT 1 FROM talent.plans_due_for_review(t, p.review_due_on + 1) WHERE plan_id = p.plan_id AND overdue) THEN
    RAISE EXCEPTION 'FAIL 4h: the owner not reminded 30 days before, or not told once overdue';
  END IF;
  RAISE NOTICE 'PASS 4a-h: route, readiness from the organization''s list, aspiration and language gaps, no self-approval, emergency successor, yearly review';
END $$;

-- A change on an approved plan goes back through the route; earlier approvals no longer count
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  UPDATE talent.successor SET readiness = '1_2_years' WHERE plan_id = '16e00000-0000-0000-0000-000000000001' AND employment_id = '16700000-0000-0000-0000-000000000004';
  IF (SELECT status FROM talent.succession_plan WHERE plan_id = '16e00000-0000-0000-0000-000000000001') <> 'submitted'
     OR (SELECT status FROM talent.successor WHERE plan_id = '16e00000-0000-0000-0000-000000000001' AND employment_id = '16700000-0000-0000-0000-000000000004') <> 'proposed' THEN
    RAISE EXCEPTION 'FAIL 4i: a changed readiness did not go back through the route';
  END IF;
  BEGIN
    UPDATE talent.succession_plan SET status = 'approved' WHERE plan_id = '16e00000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4i: re-approved on the earlier approval';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 4i: %', SQLERRM; END IF;
  END;
END $$;
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid;
BEGIN
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'succession_plan', '16e00000-0000-0000-0000-000000000001', 1, 'approved', '16a00000-0000-0000-0000-000000000005', now());
  UPDATE talent.succession_plan SET status = 'approved' WHERE plan_id = '16e00000-0000-0000-0000-000000000001';
  IF (SELECT status FROM talent.successor WHERE plan_id = '16e00000-0000-0000-0000-000000000001' AND employment_id = '16700000-0000-0000-0000-000000000004') <> 'approved' THEN
    RAISE EXCEPTION 'FAIL 4i: the changed successor not approved again';
  END IF;
  RAISE NOTICE 'PASS 4i: a change goes back through the route';
END $$;

-- A unionized position: a development pipeline, and a direct appointment needs the caution
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; offer_route uuid := gen_random_uuid();
BEGIN
  INSERT INTO talent.succession_plan (tenant_id, plan_id, position_id, owner_user, external_hire_option, status, route_id)
    VALUES (t, '16e00000-0000-0000-0000-000000000002', '16500000-0000-0000-0000-000000000004', '16a00000-0000-0000-0000-000000000002', true, 'submitted',
            platform.route_for(t, 'succession_plan', '{}'));
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'succession_plan', '16e00000-0000-0000-0000-000000000002', 1, 'approved', '16a00000-0000-0000-0000-000000000005', now());
  UPDATE talent.succession_plan SET status = 'approved' WHERE plan_id = '16e00000-0000-0000-0000-000000000002';
  IF NOT (SELECT development_only FROM talent.succession_plan WHERE plan_id = '16e00000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'FAIL 4j: a unionized role''s plan not marked development only';
  END IF;
  INSERT INTO recruit.candidate (tenant_id, candidate_id, first_name, last_name, email, consent)
    VALUES (t, '16f00000-0000-0000-0000-000000000001', 'Rae', 'Moss', 'rae@example.test', '{"privacy":"2026-10-29"}');
  INSERT INTO platform.workflow_route (tenant_id, route_id, code, subject_type, name_en, conditions, priority, status)
    VALUES (t, offer_route, 'test_offer', 'offer', 'Test offer route', '{}', 5, 'active');
  INSERT INTO platform.workflow_route_step (tenant_id, route_id, step_no, approver_kind, capability, mode, min_approvals, purpose_en)
    VALUES (t, offer_route, 1, 'capability', 'hr', 'any', 1, 'HR');
  INSERT INTO recruit.offer (tenant_id, offer_id, candidate_id, position_id, start_date, pay_rate, pay_basis, status, hire_path, conditional, terms, requested_by)
    VALUES (t, '16f10000-0000-0000-0000-000000000001', '16f00000-0000-0000-0000-000000000001', '16500000-0000-0000-0000-000000000004', '2026-12-01', 31, 'hour',
            'draft', 'direct_hire', false, '{"payRate":31,"startDate":"2026-12-01"}', '16a00000-0000-0000-0000-000000000002');
  UPDATE recruit.offer SET status = 'pending_approval', route_id = offer_route WHERE offer_id = '16f10000-0000-0000-0000-000000000001';
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'offer', '16f10000-0000-0000-0000-000000000001', 1, 'approved', '16a00000-0000-0000-0000-000000000005', now());
  BEGIN
    UPDATE recruit.offer SET status = 'approved' WHERE offer_id = '16f10000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 4k: appointed into a unionized role without a posting and without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED: succession.appoint_without_posting%' THEN RAISE EXCEPTION 'FAIL 4k: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'succession.appoint_without_posting', 'offer', '16f10000-0000-0000-0000-000000000001', 'shown', 'en', '16a00000-0000-0000-0000-000000000005',
            'Posted internally under article 12; no bidders; the union agreed to external hire on 20 October');
  UPDATE recruit.offer SET status = 'approved' WHERE offer_id = '16f10000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 4j-k: a unionized role''s plan is development only; a direct appointment needs the caution with a reason';
END $$;

-- ---------------------------------------------------------------------------------
-- 5. Continuity sheets: no secrets; who sees them
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; c talent.continuity_sheet;
BEGIN
  BEGIN
    INSERT INTO talent.continuity_sheet (tenant_id, position_id, maintained_by, systems, updated_on)
      VALUES (t, '16500000-0000-0000-0000-000000000001', '16a00000-0000-0000-0000-000000000001',
              '[{"name":"Records system","adminPassword":"x"}]', current_date);
    RAISE EXCEPTION 'FAIL 5a: a password stored';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SECRET_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.continuity_sheet (tenant_id, position_id, maintained_by, notes, updated_on)
      VALUES (t, '16500000-0000-0000-0000-000000000001', '16a00000-0000-0000-0000-000000000001', 'Vault PIN: 4471', current_date);
    RAISE EXCEPTION 'FAIL 5a: a PIN in the notes';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SECRET_NOT_ALLOWED%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.continuity_sheet (tenant_id, position_id, maintained_by, contacts, systems, delegations, notes, updated_on)
    VALUES (t, '16500000-0000-0000-0000-000000000001', '16a00000-0000-0000-0000-000000000001',
            '[{"name":"Mayor''s office","phone":"613-555-0100"}]',
            '[{"name":"Records system","access":"IT grants on request","whereSecretsAreKept":"IT password vault"}]',
            '[{"what":"Signing bylaws","to":"Deputy clerk","by":"Bylaw 2024-17"}]',
            'Passwords are kept in the IT vault; ask IT for access.', current_date)
    RETURNING * INTO c;
  IF c.review_due_on <> (current_date + interval '12 months')::date THEN RAISE EXCEPTION 'FAIL 5b: update due %', c.review_due_on; END IF;
  IF NOT talent.continuity_sheet_can_see(c.sheet_id, '16a00000-0000-0000-0000-000000000001')
     OR NOT talent.continuity_sheet_can_see(c.sheet_id, '16a00000-0000-0000-0000-000000000002')
     OR talent.continuity_sheet_can_see(c.sheet_id, '16a00000-0000-0000-0000-000000000003')
     OR NOT talent.named_on('continuity_sheet', c.sheet_id, '16a00000-0000-0000-0000-000000000002') THEN
    RAISE EXCEPTION 'FAIL 5c: the sheet not limited to the incumbent, the interim successor and the manager';
  END IF;
  RAISE NOTICE 'PASS 5a-c: no passwords or PINs; yearly update; seen by the incumbent, the interim successor, the manager (and HR)';
END $$;

-- ---------------------------------------------------------------------------------
-- 6. Talent pools
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; route uuid := platform.route_for(current_setting('app.tenant_id')::uuid, 'talent_pool_membership', '{}');
BEGIN
  INSERT INTO talent.talent_pool (tenant_id, pool_id, code, name_en, criteria_en, owner_user, accepts_applications, status) VALUES
    (t, '16900000-0000-0000-0000-000000000001', 'LEADERS', 'Future leaders', 'Nominated by a director; high potential in a talent review', '16a00000-0000-0000-0000-000000000007', false, 'active'),
    (t, '16900000-0000-0000-0000-000000000002', 'EMERGING', 'Emerging talent', 'Two years of service; a development plan in place', '16a00000-0000-0000-0000-000000000005', true, 'active');
  BEGIN
    INSERT INTO talent.pool_member (tenant_id, pool_id, person_id, source, nominated_by, status)
      VALUES (t, '16900000-0000-0000-0000-000000000001', '16600000-0000-0000-0000-000000000003', 'applied', '16a00000-0000-0000-0000-000000000003', 'proposed');
    RAISE EXCEPTION 'FAIL 6a: applied to a pool that takes nominations only';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'POOL_CLOSED_TO_APPLICATIONS%' THEN RAISE EXCEPTION 'FAIL 6a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.pool_member (tenant_id, pool_id, person_id, source, nominated_by, status)
      VALUES (t, '16900000-0000-0000-0000-000000000002', '16600000-0000-0000-0000-000000000003', 'applied', '16a00000-0000-0000-0000-000000000002', 'proposed');
    RAISE EXCEPTION 'FAIL 6a: an application made by someone else';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 6a: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.pool_member (tenant_id, member_id, pool_id, person_id, source, nominated_by, status, route_id) VALUES
    (t, '16910000-0000-0000-0000-000000000001', '16900000-0000-0000-0000-000000000002', '16600000-0000-0000-0000-000000000003', 'applied', '16a00000-0000-0000-0000-000000000003', 'proposed', route),
    (t, '16910000-0000-0000-0000-000000000002', '16900000-0000-0000-0000-000000000001', '16600000-0000-0000-0000-000000000004', 'nominated', '16a00000-0000-0000-0000-000000000002', 'proposed', route);
  BEGIN
    UPDATE talent.pool_member SET status = 'approved' WHERE member_id = '16910000-0000-0000-0000-000000000002';
    RAISE EXCEPTION 'FAIL 6b: approved without the pool owner';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 6b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'talent_pool_membership', '16910000-0000-0000-0000-000000000002', 1, 'approved', '16a00000-0000-0000-0000-000000000002', now());
    RAISE EXCEPTION 'FAIL 6c: the nominating manager approved';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 6c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'talent_pool_membership', '16910000-0000-0000-0000-000000000002', 1, 'approved', '16a00000-0000-0000-0000-000000000004', now());
    RAISE EXCEPTION 'FAIL 6c: the nominee approved her own membership';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 6c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'talent_pool_membership', '16910000-0000-0000-0000-000000000002', 1, 'approved', '16a00000-0000-0000-0000-000000000007', now());
  UPDATE talent.pool_member SET status = 'approved' WHERE member_id = '16910000-0000-0000-0000-000000000002';
  BEGIN
    UPDATE talent.pool_member SET status = 'declined' WHERE member_id = '16910000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 6d: declined without saying why';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 6d: %', SQLERRM; END IF;
  END;
  UPDATE talent.pool_member SET status = 'declined', reason = 'Under two years of service; welcome to apply in March'
   WHERE member_id = '16910000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS 6a-d: nominations and applications; the pool owner approves through the route; no self-approval; reasons';
END $$;

-- ---------------------------------------------------------------------------------
-- 7. Career paths and workforce planning
-- ---------------------------------------------------------------------------------
INSERT INTO platform.document (tenant_id, document_id, owner_type, owner_id, doc_type, access_class, retention_class, storage_key, sha256, mime_type, uploaded_by)
  VALUES (current_setting('app.tenant_id')::uuid, '16120000-0000-0000-0000-000000000001', 'tenant', current_setting('app.tenant_id')::uuid, 'import', 'hr', 'standard',
          'test/turnover-2022-2024.csv', 'abc', 'text/csv', '16a00000-0000-0000-0000-000000000005');

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; r record; h record;
BEGIN
  BEGIN
    INSERT INTO talent.career_path_step (tenant_id, from_job_id, to_job_id, move_type, source, created_by, status)
      VALUES (t, '16400000-0000-0000-0000-000000000003', '16400000-0000-0000-0000-000000000003', 'lateral', 'hr', '16a00000-0000-0000-0000-000000000005', 'active');
    RAISE EXCEPTION 'FAIL 7a: a career step to the same job';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  SELECT * INTO r FROM talent.observed_job_moves(t, '2020-01-01') WHERE from_job_id = '16400000-0000-0000-0000-000000000003';
  IF r.to_job_id IS DISTINCT FROM '16400000-0000-0000-0000-000000000002'::uuid OR r.moves <> 1 THEN
    RAISE EXCEPTION 'FAIL 7a: Ben''s move from analyst to deputy clerk not found';
  END IF;
  INSERT INTO talent.career_path_step (tenant_id, from_job_id, to_job_id, move_type, source, created_by, status)
    VALUES (t, r.from_job_id, r.to_job_id, 'vertical', 'observed_moves', '16a00000-0000-0000-0000-000000000005', 'active');
  -- Workforce planning, switched on by the organization
  BEGIN
    INSERT INTO talent.workforce_scenario (tenant_id, code, version, name_en, horizon, status, created_by)
      VALUES (t, 'BASE', 1, 'Base case', '[2027-01-01,2030-01-01)', 'draft', '16a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 7b: a scenario while workforce planning is off';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FEATURE_OFF%' THEN RAISE EXCEPTION 'FAIL 7b: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (t, 'workforce.planning_enabled', 'true', '[2000-01-01,)', gen_random_uuid());
  BEGIN
    INSERT INTO talent.workforce_segment (tenant_id, code, name_en, criteria) VALUES (t, 'X', 'Teams', '{"teams":["a"]}');
    RAISE EXCEPTION 'FAIL 7c: a scope CanDo does not know';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SEGMENT_SCOPE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 7c: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.workforce_segment (tenant_id, code, name_en, parent_code, criteria) VALUES
    (t, 'CLERKS', 'Clerk''s office', NULL, '{"orgUnits":["16300000-0000-0000-0000-000000000001"]}'),
    (t, 'ANALYSTS', 'Analysts', 'CLERKS', '{"jobs":["16400000-0000-0000-0000-000000000003"]}'),
    (t, 'ROADS', 'Roads operators', 'CLERKS', '{"jobs":["16400000-0000-0000-0000-000000000004"],"agreements":["CUPE-1"]}');
  -- History: the team's is thin; the department's three years come from an upload of the previous system
  INSERT INTO talent.turnover_history (tenant_id, segment_code, period, average_headcount, separations, retirements, source, loaded_by)
    VALUES (t, 'ANALYSTS', '[2025-01-01,2026-01-01)', 3, 1, 0, 'cando', '16a00000-0000-0000-0000-000000000005');
  BEGIN
    INSERT INTO talent.turnover_history (tenant_id, segment_code, period, average_headcount, separations, retirements, source, loaded_by)
      VALUES (t, 'CLERKS', '[2022-01-01,2025-01-01)', 40, 6, 2, 'upload', '16a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 7d: an upload without its file';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.turnover_history (tenant_id, segment_code, period, average_headcount, separations, retirements, source, upload_document_id, loaded_by)
    VALUES (t, 'CLERKS', '[2022-01-01,2025-01-01)', 40, 6, 2, 'upload', '16120000-0000-0000-0000-000000000001', '16a00000-0000-0000-0000-000000000005');
  BEGIN
    INSERT INTO talent.turnover_history (tenant_id, segment_code, period, average_headcount, separations, retirements, source, upload_document_id, loaded_by)
      VALUES (t, 'CLERKS', '[2024-01-01,2025-01-01)', 40, 1, 0, 'upload', '16120000-0000-0000-0000-000000000001', '16a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 7d: the same year uploaded twice';
  EXCEPTION WHEN exclusion_violation THEN NULL;
  END;
  SELECT * INTO h FROM talent.history_summary(t, 'ANALYSTS');
  IF NOT h.thin THEN RAISE EXCEPTION 'FAIL 7e: 3 people over 1 year not thin'; END IF;
  SELECT * INTO h FROM talent.suggested_turnover_rate(t, 'ANALYSTS');
  IF h.from_segment IS DISTINCT FROM 'CLERKS' OR NOT h.own_history_thin OR h.annual_rate <> 0.0500 THEN
    RAISE EXCEPTION 'FAIL 7e: suggested % from % (0.0500 from CLERKS expected)', h.annual_rate, h.from_segment;
  END IF;
  RAISE NOTICE 'PASS 7a-e: career steps from real moves; workforce planning switched on; segments; uploaded history; thin history suggests the next level up';
END $$;

DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; s1 uuid := '16130000-0000-0000-0000-000000000001'; s2 uuid := '16130000-0000-0000-0000-000000000002'; g uuid := gen_random_uuid();
BEGIN
  INSERT INTO talent.workforce_scenario (tenant_id, scenario_id, code, version, name_en, horizon, status, created_by)
    VALUES (t, s1, 'BASE', 1, 'Base case', '[2027-01-01,2030-01-01)', 'draft', '16a00000-0000-0000-0000-000000000005');
  BEGIN
    INSERT INTO talent.supply_rate (tenant_id, scenario_id, segment_code, kind, annual_rate, source, set_by)
      VALUES (t, s1, 'ANALYSTS', 'attrition', 0.33, 'history', '16a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 7f: a rate from thin history';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'HISTORY_TOO_THIN%' THEN RAISE EXCEPTION 'FAIL 7f: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.supply_rate (tenant_id, scenario_id, segment_code, kind, annual_rate, source, set_by)
      VALUES (t, s1, 'ANALYSTS', 'retirement', 0.02, 'planner', '16a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 7f: the planner''s rate without a reason';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SUPPLY_RATE_REASON_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7f: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO talent.supply_rate (tenant_id, scenario_id, segment_code, kind, annual_rate, source, from_segment_code, set_by)
      VALUES (t, s1, 'CLERKS', 'attrition', 0.05, 'next_level', 'CLERKS', '16a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 7f: the next level up for a segment with its own history';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7f: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.supply_rate (tenant_id, scenario_id, segment_code, kind, annual_rate, source, from_segment_code, reason, set_by) VALUES
    (t, s1, 'ANALYSTS', 'attrition', 0.05, 'next_level', 'CLERKS', NULL, '16a00000-0000-0000-0000-000000000005'),
    (t, s1, 'ANALYSTS', 'retirement', 0.02, 'planner', NULL, 'Two analysts eligible in 2028 and both have said so', '16a00000-0000-0000-0000-000000000005'),
    (t, s1, 'CLERKS', 'attrition', 0.05, 'history', NULL, NULL, '16a00000-0000-0000-0000-000000000005');
  -- Demand from the organization's own drivers and ratios
  INSERT INTO talent.workforce_driver (tenant_id, scenario_id, segment_code, driver, period, value)
    VALUES (t, s1, 'ROADS', 'lane_km', '[2027-01-01,2028-01-01)', 360);
  INSERT INTO talent.workforce_ratio (tenant_id, scenario_id, segment_code, driver, units_per_fte)
    VALUES (t, s1, 'ROADS', 'lane_km', 12);
  IF talent.demand_fte(s1, 'ROADS', '[2027-01-01,2028-01-01)') <> 30 THEN
    RAISE EXCEPTION 'FAIL 7g: demand % FTE (30 expected from 360 lane km at 12 per operator)', talent.demand_fte(s1, 'ROADS', '[2027-01-01,2028-01-01)');
  END IF;
  UPDATE talent.workforce_scenario SET status = 'saved', saved_at = now() WHERE scenario_id = s1;
  BEGIN
    UPDATE talent.workforce_driver SET value = 400 WHERE scenario_id = s1;
    RAISE EXCEPTION 'FAIL 7h: a saved version changed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SCENARIO_VERSION_LOCKED%' THEN RAISE EXCEPTION 'FAIL 7h: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE talent.workforce_scenario SET name_en = 'Renamed' WHERE scenario_id = s1;
    RAISE EXCEPTION 'FAIL 7h: a saved version renamed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SCENARIO_VERSION_LOCKED%' THEN RAISE EXCEPTION 'FAIL 7h: %', SQLERRM; END IF;
  END;
  INSERT INTO talent.workforce_scenario (tenant_id, scenario_id, code, version, name_en, copied_from, horizon, status, created_by)
    VALUES (t, s2, 'BASE', 2, 'Base case, fewer lane km after the transfer to the county', s1, '[2027-01-01,2030-01-01)', 'draft', '16a00000-0000-0000-0000-000000000005');
  -- Gap strategies draft actions; a reduction in a unionized group needs labour relations and the caution
  BEGIN
    INSERT INTO talent.gap_strategy (tenant_id, scenario_id, segment_code, period, gap_fte, strategy, status)
      VALUES (t, s2, 'ROADS', '[2027-01-01,2028-01-01)', -3, 'reduce', 'released');
    RAISE EXCEPTION 'FAIL 7i: released with no draft in its module';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.gap_strategy (tenant_id, strategy_id, scenario_id, segment_code, period, gap_fte, strategy, draft_kind, draft_ref, status)
    VALUES (t, g, s2, 'ROADS', '[2027-01-01,2028-01-01)', -3, 'reduce', 'position_plan', gen_random_uuid(), 'drafted');
  BEGIN
    UPDATE talent.gap_strategy SET status = 'released', released_by = '16a00000-0000-0000-0000-000000000005' WHERE strategy_id = g;
    RAISE EXCEPTION 'FAIL 7j: a unionized reduction released without labour relations';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LABOUR_RELATIONS_REVIEW_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7j: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE talent.gap_strategy SET status = 'released', released_by = '16a00000-0000-0000-0000-000000000005', labour_relations_reviewed_by = '16a00000-0000-0000-0000-000000000005'
     WHERE strategy_id = g;
    RAISE EXCEPTION 'FAIL 7j: the releaser reviewed it as labour relations';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LABOUR_RELATIONS_REVIEW_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 7j: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE talent.gap_strategy SET status = 'released', released_by = '16a00000-0000-0000-0000-000000000005', labour_relations_reviewed_by = '16a00000-0000-0000-0000-000000000008'
     WHERE strategy_id = g;
    RAISE EXCEPTION 'FAIL 7j: released without the caution';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'CAUTION_NOT_ACKNOWLEDGED: workforce.reduction_unionized%' THEN RAISE EXCEPTION 'FAIL 7j: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.caution_acknowledgement (tenant_id, caution_code, subject_type, subject_id, shown_text, shown_lang, acknowledged_by, reason)
    VALUES (t, 'workforce.reduction_unionized', 'gap_strategy', g, 'shown', 'en', '16a00000-0000-0000-0000-000000000005',
            'Three vacancies left unfilled, no layoffs; article 22 notice to the local by 1 March reviewed with labour relations');
  UPDATE talent.gap_strategy SET status = 'released', released_by = '16a00000-0000-0000-0000-000000000005', labour_relations_reviewed_by = '16a00000-0000-0000-0000-000000000008'
   WHERE strategy_id = g;
  INSERT INTO talent.gap_strategy (tenant_id, scenario_id, segment_code, period, gap_fte, strategy, draft_kind, draft_ref, status, released_by)
    VALUES (t, s2, 'ANALYSTS', '[2027-01-01,2028-01-01)', 1, 'build', 'training_plan', gen_random_uuid(), 'released', '16a00000-0000-0000-0000-000000000005');
  RAISE NOTICE 'PASS 7f-j: supply rates from history, the next level up or the planner with a reason; demand from drivers; saved versions kept; drafts released by people; unionized reductions reviewed';
END $$;

-- ---------------------------------------------------------------------------------
-- 8. The annual position plan through its route; cost assumptions
-- ---------------------------------------------------------------------------------
DO $$
DECLARE t uuid := current_setting('app.tenant_id')::uuid; route uuid := platform.route_for(current_setting('app.tenant_id')::uuid, 'position_plan', '{}');
BEGIN
  BEGIN
    INSERT INTO platform.plan (tenant_id, name, owner_id, as_of, status) VALUES (t, 'No kind', '16a00000-0000-0000-0000-000000000002', current_date, 'open');
    RAISE EXCEPTION 'FAIL 8a: a plan without its kind';
  EXCEPTION WHEN not_null_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO platform.plan (tenant_id, name, owner_id, as_of, status, kind) VALUES (t, 'No year', '16a00000-0000-0000-0000-000000000002', current_date, 'open', 'position_budget');
    RAISE EXCEPTION 'FAIL 8a: a position plan without its fiscal year';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO platform.plan (tenant_id, plan_id, name, owner_id, as_of, status, kind, fiscal_year)
    VALUES (t, '16140000-0000-0000-0000-000000000001', 'Clerk''s office 2027', '16a00000-0000-0000-0000-000000000002', '2027-01-01', 'open', 'position_budget', '2027');
  BEGIN
    UPDATE platform.plan SET status = 'submitted' WHERE plan_id = '16140000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8b: submitted without its route';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INPUT_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 8b: %', SQLERRM; END IF;
  END;
  UPDATE platform.plan SET status = 'submitted', route_id = route WHERE plan_id = '16140000-0000-0000-0000-000000000001';
  BEGIN
    INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
      VALUES (t, 'position_plan', '16140000-0000-0000-0000-000000000001', 1, 'approved', '16a00000-0000-0000-0000-000000000002', now());
    RAISE EXCEPTION 'FAIL 8c: the department leader approved her own plan';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SELF_APPROVAL%' THEN RAISE EXCEPTION 'FAIL 8c: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at) VALUES
    (t, 'position_plan', '16140000-0000-0000-0000-000000000001', 1, 'approved', '16a00000-0000-0000-0000-000000000006', now()),
    (t, 'position_plan', '16140000-0000-0000-0000-000000000001', 2, 'approved', '16a00000-0000-0000-0000-000000000005', now());
  BEGIN
    UPDATE platform.plan SET status = 'approved' WHERE plan_id = '16140000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL 8d: approved before the executive';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'ROUTE_APPROVALS_MISSING%' THEN RAISE EXCEPTION 'FAIL 8d: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.approval_task (tenant_id, subject_type, subject_id, step, status, decided_by, decided_at)
    VALUES (t, 'position_plan', '16140000-0000-0000-0000-000000000001', 3, 'approved', '16a00000-0000-0000-0000-000000000007', now());
  UPDATE platform.plan SET status = 'approved' WHERE plan_id = '16140000-0000-0000-0000-000000000001';
  -- An org chart plan keeps working as before (docs/04)
  INSERT INTO platform.plan (tenant_id, name, owner_id, as_of, status, kind) VALUES (t, 'What-if', '16a00000-0000-0000-0000-000000000002', current_date, 'approved', 'org_chart');
  BEGIN
    INSERT INTO talent.plan_assumption (tenant_id, plan_id, kind, value, unit, source, set_by)
      VALUES (t, '16140000-0000-0000-0000-000000000001', 'overtime', 6, 'percent', 'planner', '16a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 8e: the planner''s assumption without a reason';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO talent.plan_assumption (tenant_id, plan_id, kind, value, unit, source, set_by)
      VALUES (t, '16140000-0000-0000-0000-000000000001', 'increase', 2.5, 'percent', 'agreement', '16a00000-0000-0000-0000-000000000005');
    RAISE EXCEPTION 'FAIL 8e: an increase from the agreement without saying which';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO talent.plan_assumption (tenant_id, plan_id, segment_code, kind, value, unit, source, source_ref, reason, set_by) VALUES
    (t, '16140000-0000-0000-0000-000000000001', 'ROADS', 'increase', 2.5, 'percent', 'agreement', 'CUPE-1 2026-2029, year 2', NULL, '16a00000-0000-0000-0000-000000000005'),
    (t, '16140000-0000-0000-0000-000000000001', 'ROADS', 'overtime', 6, 'percent', 'planner', NULL, 'Snow season averaged 6% over three winters; 2026 was 9%', '16a00000-0000-0000-0000-000000000005');
  RAISE NOTICE 'PASS 8a-e: kinds of plan; the position plan through finance, HR and the executive; no self-approval; assumptions with their source or a reason';
END $$;

-- ---------------------------------------------------------------------------------
-- 9. Tenant isolation
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', '16222222-2222-2222-2222-222222222222', false) AS cfg \gset
DO $$ BEGIN
  IF (SELECT count(*) FROM talent.critical_role) <> 0 OR (SELECT count(*) FROM talent.succession_plan) <> 0 OR (SELECT count(*) FROM talent.successor) <> 0
     OR (SELECT count(*) FROM talent.nine_box_placement) <> 0 OR (SELECT count(*) FROM talent.potential_assessment) <> 0
     OR (SELECT count(*) FROM talent.flight_risk_assessment) <> 0 OR (SELECT count(*) FROM talent.vacancy_risk) <> 0
     OR (SELECT count(*) FROM talent.continuity_sheet) <> 0 OR (SELECT count(*) FROM talent.workforce_scenario) <> 0
     OR (SELECT count(*) FROM talent.turnover_history) <> 0 OR (SELECT count(*) FROM talent.pool_member) <> 0 THEN
    RAISE EXCEPTION 'FAIL 9: another organization''s succession or workforce data is visible';
  END IF;
  RAISE NOTICE 'PASS 9: tenant isolation';
END $$;

RESET ROLE;
\echo 'schema_0016_smoke: all checks passed'
