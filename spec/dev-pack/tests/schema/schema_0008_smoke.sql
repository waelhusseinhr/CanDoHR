-- Smoke test for schema/0008_values_and_languages.sql (docs/22): strict settings with limits and required keys,
-- no setting without a value, business column defaults filled from settings, organization lists mapped to fixed
-- categories, any main language and any data language, translations and what shows when one is missing, limits
-- from settings (FTE, override reasons, support access), countries and postal codes, the EI employer rate from
-- the rules, approvals and employee numbers that read every value from their settings, relationship purposes
-- across employers, overall ratings, starter data for new organizations, tenant isolation and RLS.
-- Run after migrations 0001 to 0008 (CI, after the 0007 smoke test) or on a scratch database:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0008_smoke.sql
-- It does not depend on today's date. It inserts test rows; run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll, timeleave, finance, compliance, talent, comp TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll, talent TO cando_app;
GRANT DELETE ON core.list_value, platform.tenant_language TO cando_app;     -- so the tests reach the triggers that refuse deletes
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA platform, core, payroll, talent TO cando_app;

-- ---------------------------------------------------------------------------------
-- 1. Catalogue: no fixed defaults left on registered columns, no fixed language type, every text field registered
-- ---------------------------------------------------------------------------------
DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(d.table_schema || '.' || d.table_name || '.' || d.column_name, ', ') INTO bad
    FROM platform.column_default d
    JOIN information_schema.columns c USING (table_schema, table_name, column_name)
   WHERE c.column_default IS NOT NULL;
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1a: registered columns still have a table DEFAULT: %', bad; END IF;
  SELECT string_agg(DISTINCT d.table_schema || '.' || d.table_name, ', ') INTO bad
    FROM platform.column_default d
   WHERE NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = format('%I.%I', d.table_schema, d.table_name)::regclass
                       AND t.tgname = 'a00_fill_from_settings');
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1b: no fill trigger on %', bad; END IF;
  IF to_regtype('ref.lang') IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1c: ref.lang still exists'; END IF;
  SELECT string_agg(c.table_schema || '.' || c.table_name || '.' || c.column_name, ', ') INTO bad
    FROM information_schema.columns c
    JOIN information_schema.tables tb ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name AND tb.table_type = 'BASE TABLE'
   WHERE c.column_name ~ '_en$'
     AND c.table_schema IN ('platform','core','payroll','timeleave','finance','comp','talent','benefits','recruit','offboard','compliance')
     AND EXISTS (SELECT 1 FROM information_schema.columns x WHERE x.table_schema = c.table_schema AND x.table_name = c.table_name AND x.column_name = 'tenant_id')
     AND NOT EXISTS (SELECT 1 FROM platform.translatable_field f WHERE f.table_schema = c.table_schema AND f.table_name = c.table_name
                       AND f.columns ->> 'en' = c.column_name);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1d: text fields not registered as translatable: %', bad; END IF;
  SELECT string_agg(DISTINCT f.table_schema || '.' || f.table_name, ', ') INTO bad
    FROM platform.translatable_field f
   WHERE f.required AND NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = format('%I.%I', f.table_schema, f.table_name)::regclass
                                      AND t.tgname = 'zz_required_text');
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1e: no required-text check on %', bad; END IF;
  SELECT string_agg(f.table_schema || '.' || f.table_name || '.' || (f.columns ->> 'en'), ', ') INTO bad
    FROM platform.translatable_field f
    JOIN information_schema.columns c ON c.table_schema = f.table_schema AND c.table_name = f.table_name AND c.column_name = f.columns ->> 'en'
   WHERE c.is_nullable = 'NO';
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1f: English text still NOT NULL (the main language can be any language): %', bad; END IF;
  SELECT string_agg(n.nspname || '.' || c.relname, ', ') INTO bad
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE (n.nspname, c.relname) IN (('core','list_value'), ('platform','tenant_language'), ('platform','translation'))
     AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 1g: RLS not forced on %', bad; END IF;
  IF (SELECT pronargdefaults FROM pg_proc WHERE oid = 'talent.competency_gap(uuid,date,text[])'::regprocedure) <> 0
     OR (SELECT pronargdefaults FROM pg_proc WHERE oid = 'talent.review_overall(uuid,numeric)'::regprocedure) <> 0
     OR to_regprocedure('talent.competency_gap(uuid,date)') IS NULL OR to_regprocedure('talent.review_overall(uuid)') IS NULL THEN
    RAISE EXCEPTION 'FAIL 1h: review and gap functions still carry their own defaults';
  END IF;
  RAISE NOTICE 'PASS 1: no fixed defaults on registered columns; languages are data; every text field registered and checked; RLS forced';
END $$;

-- 2. Settings catalogue: every setting says where it was decided; pending settings have no default; no fallback
DO $$
DECLARE bad text;
BEGIN
  SELECT string_agg(setting_key, ', ') INTO bad FROM platform.setting_definition
   WHERE decision_status IS NULL OR btrim(coalesce(decision_ref, '')) = '' OR btrim(coalesce(description_en, '')) = '';
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL 2a: settings without decision status, reference or description: %', bad; END IF;
  BEGIN
    INSERT INTO platform.setting_definition (setting_key, area, value_type, default_value, description_en, decision_ref, decision_status, min_value)
      VALUES ('test.bad_default', 'test', 'integer', '0', 'Test', 'test', 'spec_default', 1);
    RAISE EXCEPTION 'FAIL 2b: a default below its own minimum was accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_DEFAULT_INVALID%' THEN RAISE EXCEPTION 'FAIL 2b: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.setting_definition (setting_key, area, value_type, default_value, description_en, decision_ref, decision_status)
      VALUES ('test.pending_with_default', 'test', 'text', '"x"', 'Test', 'test', 'pending');
    RAISE EXCEPTION 'FAIL 2c: a pending setting carried a CanDo default';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  INSERT INTO platform.setting_definition (setting_key, area, value_type, default_value, description_en, decision_ref, decision_status)
    VALUES ('test.pending_choice', 'test', 'text', NULL, 'Test: each organization chooses at setup', 'test', 'pending');
  BEGIN
    PERFORM platform.setting('81111111-1111-1111-1111-111111111111', 'test.pending_choice');
    RAISE EXCEPTION 'FAIL 2d: a setting with no value anywhere returned something';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_NOT_SET%' THEN RAISE EXCEPTION 'FAIL 2d: %', SQLERRM; END IF;
  END;
  DELETE FROM platform.setting_definition WHERE setting_key = 'test.pending_choice';
  BEGIN
    PERFORM platform.setting('81111111-1111-1111-1111-111111111111', 'no.such.setting');
    RAISE EXCEPTION 'FAIL 2e: an unknown setting returned something';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SETTING_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 2e: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 2: defaults pass their own checks; a pending setting stops with SETTING_NOT_SET; an unknown key stops with SETTING_UNKNOWN';
END $$;

-- 3. New organizations get the starter lists and their languages
INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('81111111-1111-1111-1111-111111111111', 'Values Test Org'),
  ('82222222-2222-2222-2222-222222222222', 'Organisme francophone'),
  ('83333333-3333-3333-3333-333333333333', 'Language Test Org')
ON CONFLICT DO NOTHING;
DO $$ BEGIN
  IF (SELECT count(*) FROM core.list_value WHERE tenant_id = '81111111-1111-1111-1111-111111111111') <> (SELECT count(*) FROM ref.list_starter)
     OR (SELECT lang FROM platform.tenant_language WHERE tenant_id = '81111111-1111-1111-1111-111111111111' AND is_main) <> 'en'
     OR (SELECT residency FROM platform.tenant WHERE tenant_id = '81111111-1111-1111-1111-111111111111') <> 'CA'
     OR (SELECT modules_enabled FROM platform.tenant WHERE tenant_id = '81111111-1111-1111-1111-111111111111') <> ARRAY['core'] THEN
    RAISE EXCEPTION 'FAIL 3: new organization not seeded from the starters and settings';
  END IF;
  RAISE NOTICE 'PASS 3: a new organization gets the starter lists, English as main language, and its defaults from settings';
END $$;

-- The francophone organization's setup: French is its main language and English is not used
INSERT INTO platform.tenant_language (tenant_id, lang, locale, is_main, for_data)
  VALUES ('82222222-2222-2222-2222-222222222222', 'fr', 'fr-CA', false, 'required');
UPDATE platform.tenant_language SET is_main = false WHERE tenant_id = '82222222-2222-2222-2222-222222222222' AND lang = 'en';
UPDATE platform.tenant_language SET is_main = true  WHERE tenant_id = '82222222-2222-2222-2222-222222222222' AND lang = 'fr';
DELETE FROM platform.tenant_language WHERE tenant_id = '82222222-2222-2222-2222-222222222222' AND lang = 'en';

SET ROLE cando_app;
SELECT set_config('app.tenant_id', '81111111-1111-1111-1111-111111111111', false) AS cfg \gset

-- ---------------------------------------------------------------------------------
-- Fixtures: two employers (LE1, LE2); Sam in two positions at LE1; Mo, a manager, at LE2
-- ---------------------------------------------------------------------------------
INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'a8000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'a8000000-0000-0000-0000-000000000002');
INSERT INTO core.location (tenant_id, location_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000002'),
  (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000003'),
  (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000004');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'c8000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'c8000000-0000-0000-0000-000000000002');
INSERT INTO core.org_unit_version (tenant_id, org_unit_id, valid_period, change_set_id, legal_entity_id, unit_type, code, name_en) VALUES
  (current_setting('app.tenant_id')::uuid, 'c8000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'a8000000-0000-0000-0000-000000000001', 'DIV', 'OPS', 'Operations'),
  (current_setting('app.tenant_id')::uuid, 'c8000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'a8000000-0000-0000-0000-000000000002', 'DIV', 'SVC', 'Shared services');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, 'd8000000-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en) VALUES
  (current_setting('app.tenant_id')::uuid, 'd8000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'CW', 'Community Worker');
INSERT INTO core.list_value (tenant_id, list_code, code, category, rank, name_en)
  VALUES (current_setting('app.tenant_id')::uuid, 'employment_type', 'rft', 'permanent', 7, 'Regular full-time');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, 'e8000000-0000-0000-0000-000000000001', 'P1'),
  (current_setting('app.tenant_id')::uuid, 'e8000000-0000-0000-0000-000000000002', 'P2'),
  (current_setting('app.tenant_id')::uuid, 'e8000000-0000-0000-0000-000000000003', 'PM');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, reports_to_position_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, 'e8000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'd8000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', NULL, 3, 'casual', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e8000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'd8000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', NULL, 1, 'rft', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e8000000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'd8000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000002', 'b8000000-0000-0000-0000-000000000001', NULL, 3, 'permanent', 'active');
INSERT INTO core.person (tenant_id, person_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f8000000-0000-0000-0000-000000000001'),   -- Sam
  (current_setting('app.tenant_id')::uuid, 'f8000000-0000-0000-0000-000000000002');   -- Mo
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'f8100000-0000-0000-0000-000000000001', 'f8000000-0000-0000-0000-000000000001', 'a8000000-0000-0000-0000-000000000001'),
  (current_setting('app.tenant_id')::uuid, 'f8100000-0000-0000-0000-000000000002', 'f8000000-0000-0000-0000-000000000002', 'a8000000-0000-0000-0000-000000000002');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id) VALUES
  (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000001', 'f8100000-0000-0000-0000-000000000001'),   -- Sam A1 (casual)
  (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000002', 'f8100000-0000-0000-0000-000000000001'),   -- Sam A2 (regular full-time)
  (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000003', 'f8100000-0000-0000-0000-000000000002'),   -- Mo AM
  (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000004', 'f8100000-0000-0000-0000-000000000001'),   -- Sam AX (FTE tests)
  (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000005', 'f8100000-0000-0000-0000-000000000002');   -- Mo AY (FTE tests)
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type) VALUES
  (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000001', '[2026-01-01,)', gen_random_uuid(), 'e8000000-0000-0000-0000-000000000001', 'c8000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 0.6, true, 'casual'),
  (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000002', '[2026-01-01,)', gen_random_uuid(), 'e8000000-0000-0000-0000-000000000002', 'c8000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 0.4, false, 'rft'),
  (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000003', '[2026-01-01,)', gen_random_uuid(), 'e8000000-0000-0000-0000-000000000003', 'c8000000-0000-0000-0000-000000000002', 'b8000000-0000-0000-0000-000000000001', 1, true, 'permanent');

-- 4. Column defaults come from the organization's settings; a value the organization's list lacks is refused
DO $$ BEGIN
  IF (SELECT person_type FROM core.person WHERE person_id = 'f8000000-0000-0000-0000-000000000001') <> 'employee' THEN
    RAISE EXCEPTION 'FAIL 4a: person type not filled from people.default_person_type';
  END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'people.default_person_type', '"volunteer"', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO core.person (tenant_id, person_id) VALUES (current_setting('app.tenant_id')::uuid, 'f8000000-0000-0000-0000-000000000009');
  IF (SELECT person_type FROM core.person WHERE person_id = 'f8000000-0000-0000-0000-000000000009') <> 'volunteer' THEN
    RAISE EXCEPTION 'FAIL 4b: the organization''s own default ignored';
  END IF;
  BEGIN
    UPDATE platform.tenant_setting SET value = '"board_member"'
     WHERE tenant_id = current_setting('app.tenant_id')::uuid AND setting_key = 'people.default_person_type';
    INSERT INTO core.person (tenant_id, person_id) VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid());
    RAISE EXCEPTION 'FAIL 4c: a default that is not on the organization''s list was used';
  EXCEPTION WHEN foreign_key_violation THEN
    IF SQLERRM NOT LIKE 'LIST_VALUE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 4c: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 4: defaults filled from the organization''s settings; values checked against its lists';
END $$;

-- 5. Organization lists: own values mapped to fixed categories; no deletes, no category changes
DO $$ BEGIN
  BEGIN
    INSERT INTO core.list_value (tenant_id, list_code, code, category, rank, name_en)
      VALUES (current_setting('app.tenant_id')::uuid, 'employment_type', 'prob', 'probationary', 8, 'Probationary');
    RAISE EXCEPTION 'FAIL 5a: unknown category accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LIST_CATEGORY_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 5a: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, fte_budget, employment_type, status)
      VALUES (current_setting('app.tenant_id')::uuid, 'e8000000-0000-0000-0000-000000000001', '[2030-01-01,)', gen_random_uuid(), 'd8000000-0000-0000-0000-000000000001',
              'c8000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 1, 'contract', 'active');
    RAISE EXCEPTION 'FAIL 5b: employment type not on the list accepted';
  EXCEPTION WHEN foreign_key_violation THEN
    IF SQLERRM NOT LIKE 'LIST_VALUE_UNKNOWN%' THEN RAISE EXCEPTION 'FAIL 5b: %', SQLERRM; END IF;
  END;
  BEGIN
    DELETE FROM core.list_value WHERE tenant_id = current_setting('app.tenant_id')::uuid AND list_code = 'employment_type' AND code = 'seasonal';
    RAISE EXCEPTION 'FAIL 5c: list value deleted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LIST_VALUE_RETIRE_INSTEAD%' THEN RAISE EXCEPTION 'FAIL 5c: %', SQLERRM; END IF;
  END;
  BEGIN
    UPDATE core.list_value SET category = 'casual' WHERE tenant_id = current_setting('app.tenant_id')::uuid AND list_code = 'employment_type' AND code = 'rft';
    RAISE EXCEPTION 'FAIL 5d: category changed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LIST_CATEGORY_IMMUTABLE%' THEN RAISE EXCEPTION 'FAIL 5d: %', SQLERRM; END IF;
  END;
  UPDATE core.list_value SET status = 'retired' WHERE tenant_id = current_setting('app.tenant_id')::uuid AND list_code = 'employment_type' AND code = 'seasonal';
  RAISE NOTICE 'PASS 5: own values mapped to fixed categories; unknown values refused; retire, never delete or recategorize';
END $$;

-- 6. Employment status reads the categories of the organization's own employment types
DO $$ BEGIN
  IF core.employment_status_type('f8100000-0000-0000-0000-000000000001', '2026-06-01') <> 'permanent' THEN
    RAISE EXCEPTION 'FAIL 6a: "Regular full-time" not read as the permanent category';
  END IF;
  BEGIN
    INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
      VALUES (current_setting('app.tenant_id')::uuid, 'employment.status_precedence', '["term","auxiliary","seasonal","student"]', '[2000-01-01,)', gen_random_uuid());
    PERFORM core.employment_status_type('f8100000-0000-0000-0000-000000000001', '2026-06-01');
    RAISE EXCEPTION 'FAIL 6b: a status was guessed for categories the precedence does not list';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'EMPLOYMENT_STATUS_UNRESOLVED%' THEN RAISE EXCEPTION 'FAIL 6b: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 6: status from categories; an incomplete precedence stops instead of guessing';
END $$;

-- 7. Settings are checked against their type, allowed values, limits and required keys
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('support.max_grant_days', '8', 'SETTING_ABOVE_MAXIMUM'),
      ('support.max_grant_days', '0', 'SETTING_BELOW_MINIMUM'),
      ('employee_number.format', '{"prefix":"E"}', 'SETTING_KEYS_MISSING'),
      ('retro.backdate_approval', '{"hrApprovals":1,"payrollApproval":true,"secondHrApprovalOlderThan":"1 month"}', 'SETTING_KEYS_MISSING'),
      ('positions.max_assignment_fte', '"1.2"', 'SETTING_VALUE_TYPE'),
      ('reviews.overall_method', '"median"', 'SETTING_VALUE_NOT_ALLOWED'),
      ('funding.default_alert_days', '[90, "sixty"]', 'SETTING_VALUE_TYPE')
    ) AS x(k, v, err)
  LOOP
    BEGIN
      INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
        VALUES (current_setting('app.tenant_id')::uuid, r.k, r.v::jsonb, '[2000-01-01,)', gen_random_uuid());
      RAISE EXCEPTION 'FAIL 7: % = % accepted', r.k, r.v;
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM NOT LIKE r.err || '%' THEN RAISE EXCEPTION 'FAIL 7 (% = %): %', r.k, r.v, SQLERRM; END IF;
    END;
  END LOOP;
  RAISE NOTICE 'PASS 7: types, allowed values, limits and required keys enforced on every organization setting';
END $$;

-- 8. Assignment FTE limit from the setting, per employer
INSERT INTO platform.tenant_setting (tenant_id, setting_key, scope_type, scope_id, value, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'positions.max_assignment_fte', 'legal_entity', 'a8000000-0000-0000-0000-000000000001', '1.0', '[2000-01-01,)', gen_random_uuid());
DO $$ BEGIN
  BEGIN
    INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type)
      VALUES (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000004', '[2026-01-01,)', gen_random_uuid(), 'e8000000-0000-0000-0000-000000000001',
              'c8000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 1.2, false, 'casual');
    RAISE EXCEPTION 'FAIL 8a: FTE above the employer''s limit accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FTE_ABOVE_LIMIT%' THEN RAISE EXCEPTION 'FAIL 8a: %', SQLERRM; END IF;
  END;
  INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type)
    VALUES (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000005', '[2026-01-01,)', gen_random_uuid(), 'e8000000-0000-0000-0000-000000000003',
            'c8000000-0000-0000-0000-000000000002', 'b8000000-0000-0000-0000-000000000001', 1.2, false, 'permanent');
  BEGIN
    INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary, employment_type)
      VALUES (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000004', '[2026-01-01,)', gen_random_uuid(), 'e8000000-0000-0000-0000-000000000001',
              'c8000000-0000-0000-0000-000000000001', 'b8000000-0000-0000-0000-000000000001', 1.6, false, 'casual');
    RAISE EXCEPTION 'FAIL 8b: FTE above the organization''s limit accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 8: 1.2 FTE refused at the employer limited to 1.0 and accepted at the other (organization limit 1.5)';
END $$;

-- 9. Support access grants: the organization can shorten CanDo's seven-day ceiling, never lengthen it
INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'support.max_grant_days', '3', '[2000-01-01,)', gen_random_uuid());
DO $$ BEGIN
  BEGIN
    INSERT INTO platform.support_access_grant (tenant_id, requested_by, purpose, valid_period)
      VALUES (current_setting('app.tenant_id')::uuid, 'cando-support:alex', 'Ticket 456', tstzrange('2026-03-01 09:00-05', '2026-03-06 09:00-05'));
    RAISE EXCEPTION 'FAIL 9a: five-day grant accepted with a three-day limit';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'SUPPORT_GRANT_TOO_LONG%' THEN RAISE EXCEPTION 'FAIL 9a: %', SQLERRM; END IF;
  END;
  INSERT INTO platform.support_access_grant (tenant_id, requested_by, purpose, valid_period)
    VALUES (current_setting('app.tenant_id')::uuid, 'cando-support:alex', 'Ticket 456', tstzrange('2026-03-01 09:00-05', '2026-03-03 09:00-05'));
  RAISE NOTICE 'PASS 9: grant length follows the organization''s limit inside CanDo''s ceiling';
END $$;

-- 10. Position control override reasons: length from the setting
INSERT INTO core.change_reason (tenant_id, code, name_en, category) VALUES
  (current_setting('app.tenant_id')::uuid, 'HIRE', 'New hire', 'hire'),
  (current_setting('app.tenant_id')::uuid, 'PROMO', 'Promotion', 'promotion')
ON CONFLICT DO NOTHING;
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  (current_setting('app.tenant_id')::uuid, '08a00000-0000-0000-0000-000000000001', 'req8', 'req8@example.test');
INSERT INTO platform.change_set (tenant_id, change_set_id, number, kind, reason_code, effective_date, source, status, requested_by)
  VALUES (current_setting('app.tenant_id')::uuid, '08400000-0000-0000-0000-000000000001', 1, 'hire', 'HIRE', '2026-11-01', 'ui_form', 'pending_approval',
          '08a00000-0000-0000-0000-000000000001');
INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'approvals.override_reason_min_length', '25', '[2000-01-01,)', gen_random_uuid());
DO $$ BEGIN
  BEGIN
    INSERT INTO core.position_control_override (tenant_id, change_set_id, position_id, check_kind, amount_over, reason, status)
      VALUES (current_setting('app.tenant_id')::uuid, '08400000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'budget', 900, 'Winter coverage', 'pending');
    RAISE EXCEPTION 'FAIL 10a: short reason accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'REASON_TOO_SHORT%' THEN RAISE EXCEPTION 'FAIL 10a: %', SQLERRM; END IF;
  END;
  INSERT INTO core.position_control_override (tenant_id, change_set_id, position_id, check_kind, amount_over, reason, status)
    VALUES (current_setting('app.tenant_id')::uuid, '08400000-0000-0000-0000-000000000001', 'e8000000-0000-0000-0000-000000000001', 'budget', 900,
            'Winter coverage for the two shelters', 'pending');
  RAISE NOTICE 'PASS 10: override reasons meet the organization''s minimum length';
END $$;

-- 11. Employee numbers and back-dated approvals read every value from their settings
INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'employee_number.format', '{"prefix":"CD-","width":5}', '[2000-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, 'retro.backdate_approval',
   '{"hrApprovals":1,"olderHrApprovals":3,"payrollApproval":false,"secondHrApprovalOlderThan":"2 months"}', '[2000-01-01,)', gen_random_uuid());
DO $$
DECLARE n text; a record; b record;
BEGIN
  n := core.next_employee_number(current_setting('app.tenant_id')::uuid);
  IF n !~ '^CD-[0-9]{5}$' THEN RAISE EXCEPTION 'FAIL 11a: employee number % ignores the format', n; END IF;
  SELECT * INTO a FROM platform.required_approvals(jsonb_populate_record(NULL::platform.change_set, jsonb_build_object(
    'tenant_id', current_setting('app.tenant_id'), 'kind', 'job_change', 'effective_date', '2026-01-01',
    'requested_at', '2026-10-01 10:00-05', 'reaches_finalized_pay', true)));
  SELECT * INTO b FROM platform.required_approvals(jsonb_populate_record(NULL::platform.change_set, jsonb_build_object(
    'tenant_id', current_setting('app.tenant_id'), 'kind', 'job_change', 'effective_date', '2026-09-15',
    'requested_at', '2026-10-01 10:00-05', 'reaches_finalized_pay', true)));
  IF a.hr_needed <> 3 OR a.payroll_needed <> 0 OR b.hr_needed <> 1 OR b.payroll_needed <> 0 THEN
    RAISE EXCEPTION 'FAIL 11b: approvals % / % not taken from the setting', a, b;
  END IF;
  RAISE NOTICE 'PASS 11: employee number %; nine months back needs 3 HR approvals, two weeks back needs 1, payroll approval switched off', n;
END $$;

-- 12. Relationships across employers name a type, and the type says which arrangement it needs
INSERT INTO core.relationship_type (tenant_id, code, name_en, is_line, authorities, cross_employer_purpose) VALUES
  (current_setting('app.tenant_id')::uuid, 'mentor', 'Mentor', false, '{}', 'none'),
  (current_setting('app.tenant_id')::uuid, 'functional', 'Functional lead', false, '{"approveTime": true}', 'supervision');
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES (NULL, 'RELATIONSHIP_TYPE_REQUIRED'), ('coach', 'RELATIONSHIP_TYPE_UNKNOWN'), ('functional', 'CROSS_EMPLOYER_NO_ARRANGEMENT')) AS x(t, err) LOOP
    BEGIN
      INSERT INTO core.assignment_relationship (tenant_id, assignment_id, related_assignment_id, kind, valid_period, change_set_id, relationship_type_code)
        VALUES (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000001', '08200000-0000-0000-0000-000000000003', 'dotted',
                '[2026-01-01,)', gen_random_uuid(), r.t);
      RAISE EXCEPTION 'FAIL 12a: relationship type % across employers accepted', r.t;
    EXCEPTION WHEN check_violation THEN
      IF SQLERRM NOT LIKE r.err || '%' THEN RAISE EXCEPTION 'FAIL 12a (%): %', r.t, SQLERRM; END IF;
    END;
  END LOOP;
  INSERT INTO core.assignment_relationship (tenant_id, assignment_id, related_assignment_id, kind, valid_period, change_set_id, relationship_type_code)
    VALUES (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000001', '08200000-0000-0000-0000-000000000003', 'mentor',
            '[2026-01-01,)', gen_random_uuid(), 'mentor');
  INSERT INTO core.assignment_relationship (tenant_id, assignment_id, related_assignment_id, kind, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, '08200000-0000-0000-0000-000000000002', '08200000-0000-0000-0000-000000000001', 'dotted',
            '[2026-01-01,)', gen_random_uuid());
  RAISE NOTICE 'PASS 12: across employers the type is required and known; a mentor needs no arrangement; same employer unchanged';
END $$;

-- 13. Overall rating: method, minimum days and rounding step from the settings. CanDo's defaults are each position by
--     itself and 90 days (docs/28 §6); this organization then chooses the FTE x days method.
INSERT INTO talent.review (tenant_id, review_id, employment_id, cycle_code, kind, status, rating_mode)
  VALUES (current_setting('app.tenant_id')::uuid, '08600000-0000-0000-0000-000000000001', 'f8100000-0000-0000-0000-000000000001', '2026', 'annual', 'not_started', 'rated');
INSERT INTO talent.review_section (tenant_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, rated, rating_score) VALUES
  (current_setting('app.tenant_id')::uuid, '08600000-0000-0000-0000-000000000001', '08200000-0000-0000-0000-000000000001', '08200000-0000-0000-0000-000000000003', 0.6, 200, 200, true, 4),
  (current_setting('app.tenant_id')::uuid, '08600000-0000-0000-0000-000000000001', '08200000-0000-0000-0000-000000000002', '08200000-0000-0000-0000-000000000003', 0.4, 200, 200, true, 3);
DO $$ BEGIN
  IF (SELECT min_section_days FROM talent.review WHERE review_id = '08600000-0000-0000-0000-000000000001') <> 90
     OR (SELECT overall_method FROM talent.review WHERE review_id = '08600000-0000-0000-0000-000000000001') <> 'none'
     OR talent.review_overall('08600000-0000-0000-0000-000000000001') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL 13a: review defaults wrong, or a combined rating where each position stands by itself';
  END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'reviews.overall_method', '"fte_weighted"', '[2000-01-01,)', gen_random_uuid());
  INSERT INTO talent.review (tenant_id, review_id, employment_id, cycle_code, kind, status, rating_mode)
    VALUES (current_setting('app.tenant_id')::uuid, '08600000-0000-0000-0000-000000000002', 'f8100000-0000-0000-0000-000000000001', '2027', 'annual', 'not_started', 'rated');
  INSERT INTO talent.review_section (tenant_id, review_id, assignment_id, owner_assignment_id, fte, days_in_cycle, days_worked, rated, rating_score) VALUES
    (current_setting('app.tenant_id')::uuid, '08600000-0000-0000-0000-000000000002', '08200000-0000-0000-0000-000000000001', '08200000-0000-0000-0000-000000000003', 0.6, 200, 200, true, 4),
    (current_setting('app.tenant_id')::uuid, '08600000-0000-0000-0000-000000000002', '08200000-0000-0000-0000-000000000002', '08200000-0000-0000-0000-000000000003', 0.4, 200, 200, true, 3);
  IF (SELECT overall_method FROM talent.review WHERE review_id = '08600000-0000-0000-0000-000000000002') <> 'fte_weighted'
     OR talent.review_overall('08600000-0000-0000-0000-000000000002') <> 4 THEN
    RAISE EXCEPTION 'FAIL 13b: the organization''s method or whole-point rounding ignored';
  END IF;
  INSERT INTO platform.tenant_setting (tenant_id, setting_key, value, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'reviews.overall_rounding_step', '0.5', '[2000-01-01,)', gen_random_uuid());
  IF talent.review_overall('08600000-0000-0000-0000-000000000002') <> 3.5 THEN
    RAISE EXCEPTION 'FAIL 13c: rounding step setting ignored';
  END IF;
  RAISE NOTICE 'PASS 13: by default no combined rating; with the organization''s FTE x days method 3.6 rounds to 4 on whole points and to 3.5 on half points';
END $$;

-- 14. Countries and postal codes; province codes only for Canadian locations
DO $$ BEGIN
  INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction)
    VALUES (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Main office', '1 Main St', 'Toronto', 'ON', 'M5V 3L9', 'America/Toronto', 'ON');
  IF (SELECT country_code FROM core.location_version WHERE location_id = 'b8000000-0000-0000-0000-000000000001') <> 'CA' THEN
    RAISE EXCEPTION 'FAIL 14a: country not filled from locations.default_country';
  END IF;
  BEGIN
    INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction)
      VALUES (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'Annex', '2 Main St', 'Toronto', 'ON', 'M5V-3L9', 'America/Toronto', 'ON');
    RAISE EXCEPTION 'FAIL 14b: malformed Canadian postal code accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'POSTAL_CODE_FORMAT%' THEN RAISE EXCEPTION 'FAIL 14b: %', SQLERRM; END IF;
  END;
  INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, country_code, name, address_line1, city, postal_code, time_zone)
    VALUES (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'US', 'Seattle office', '3 Pine St', 'Seattle', '98101', 'America/Los_Angeles');
  BEGIN
    INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, country_code, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction)
      VALUES (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000004', '[2020-01-01,)', gen_random_uuid(), 'US', 'Buffalo office', '4 Elm St', 'Buffalo', 'ON', '14201', 'America/New_York', 'ON');
    RAISE EXCEPTION 'FAIL 14c: Canadian province on a US location accepted';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'PROVINCE_NOT_APPLICABLE%' THEN RAISE EXCEPTION 'FAIL 14c: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 14: postal code format per country; Canadian province codes only in Canada';
END $$;

-- 15. EI employer rate: from the rule edition unless CRA assigned a reduced rate, with its reference
DO $$ BEGIN
  INSERT INTO core.payroll_account (tenant_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid)
    VALUES (current_setting('app.tenant_id')::uuid, 'a8000000-0000-0000-0000-000000000001', 'RP0001', 'regular', '[2026-01-01,)');
  INSERT INTO core.payroll_account (tenant_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid, ei_employer_rate, ei_reduced_rate_ref)
    VALUES (current_setting('app.tenant_id')::uuid, 'a8000000-0000-0000-0000-000000000002', 'RP0002', 'regular', '[2026-01-01,)', 1.2, 'CRA letter 2026-0042');
  BEGIN
    INSERT INTO core.payroll_account (tenant_id, legal_entity_id, rp_number, remitter_type, remitter_type_valid, ei_employer_rate)
      VALUES (current_setting('app.tenant_id')::uuid, 'a8000000-0000-0000-0000-000000000002', 'RP0003', 'regular', '[2026-01-01,)', 1.3);
    RAISE EXCEPTION 'FAIL 15: reduced rate without CRA''s reference accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  RAISE NOTICE 'PASS 15: no stored EI rate unless CRA assigned one';
END $$;

-- 16. Locale and preferred language come from the organization's main language; screens are the user's choice
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  (current_setting('app.tenant_id')::uuid, '08a00000-0000-0000-0000-000000000002', 'sam8', 'sam8@example.test');
INSERT INTO core.person_version (tenant_id, person_id, valid_period, change_set_id, legal_first_name, legal_last_name)
  VALUES (current_setting('app.tenant_id')::uuid, 'f8000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'Sam', 'Rivera');
DO $$ BEGIN
  IF (SELECT locale FROM platform.app_user WHERE user_id = '08a00000-0000-0000-0000-000000000002') <> 'en-CA'
     OR (SELECT preferred_language FROM core.person_version WHERE person_id = 'f8000000-0000-0000-0000-000000000001') <> 'en' THEN
    RAISE EXCEPTION 'FAIL 16: locale or preferred language not from the main language';
  END IF;
  INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email, locale)
    VALUES (current_setting('app.tenant_id')::uuid, '08a00000-0000-0000-0000-000000000004', 'mo8', 'mo8@example.test', 'fr-CA');
  IF (SELECT row(t.value, t.lang, t.substituted)::text FROM core.org_unit_version o
        CROSS JOIN LATERAL platform.text_for(o.tenant_id, 'core.org_unit_version', to_jsonb(o), 'name', 'fr') t
       WHERE o.org_unit_id = 'c8000000-0000-0000-0000-000000000001') <> '(Operations,en,t)' THEN
    RAISE EXCEPTION 'FAIL 16b: a French-screen user does not see the English name as typed, marked en';
  END IF;
  INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000005');
  BEGIN
    INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction)
      VALUES (current_setting('app.tenant_id')::uuid, 'b8000000-0000-0000-0000-000000000005', '[2020-01-01,)', gen_random_uuid(), 'Gatineau office', '2 rue Laval', 'Gatineau', 'QC', 'J8X 3H3', 'America/Toronto', 'QC');
    RAISE EXCEPTION 'FAIL 16c: Quebec location in an organization without French';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FRENCH_REQUIRED_FOR_QUEBEC%' THEN RAISE EXCEPTION 'FAIL 16c: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 16: English-main organization: en-CA and en by default; a user may pick French screens and sees English names marked; no Quebec location without French';
END $$;

-- ---------------------------------------------------------------------------------
-- 17. A French-main organization: no English needed anywhere
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', '82222222-2222-2222-2222-222222222222', false) AS cfg \gset
INSERT INTO core.hierarchy (tenant_id, hierarchy_id, code, kind, name_fr)
  VALUES (current_setting('app.tenant_id')::uuid, 'b8200000-0000-0000-0000-000000000001', 'GEST', 'management', 'Gestion');
INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email) VALUES
  (current_setting('app.tenant_id')::uuid, '08a00000-0000-0000-0000-000000000003', 'claude8', 'claude8@example.test');
INSERT INTO core.person (tenant_id, person_id) VALUES (current_setting('app.tenant_id')::uuid, 'f8000000-0000-0000-0000-000000000003');
INSERT INTO core.person_version (tenant_id, person_id, valid_period, change_set_id, legal_first_name, legal_last_name)
  VALUES (current_setting('app.tenant_id')::uuid, 'f8000000-0000-0000-0000-000000000003', '[2020-01-01,)', gen_random_uuid(), 'Claude', 'Tremblay');
DO $$
DECLARE h jsonb;
BEGIN
  SELECT to_jsonb(x) INTO h FROM core.hierarchy x WHERE hierarchy_id = 'b8200000-0000-0000-0000-000000000001';
  IF (SELECT value FROM platform.text_for(current_setting('app.tenant_id')::uuid, 'core.hierarchy', h, 'name', 'fr')) <> 'Gestion'
     OR (SELECT locale FROM platform.app_user WHERE user_id = '08a00000-0000-0000-0000-000000000003') <> 'fr-CA'
     OR (SELECT preferred_language FROM core.person_version WHERE person_id = 'f8000000-0000-0000-0000-000000000003') <> 'fr' THEN
    RAISE EXCEPTION 'FAIL 17a: French-main organization not served in French';
  END IF;
  IF (SELECT row(value, lang, substituted)::text FROM platform.text_for(current_setting('app.tenant_id')::uuid, 'core.hierarchy', h, 'name', 'en'))
     <> '(Gestion,fr,t)' THEN
    RAISE EXCEPTION 'FAIL 17b: an English-screen user does not see the French text as typed, marked fr';
  END IF;
  BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    INSERT INTO core.hierarchy (tenant_id, hierarchy_id, code, kind, name_en)
      VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'FIN', 'financial', 'Finance');
    RAISE EXCEPTION 'FAIL 17c: no French name accepted in a French-main organization';
  EXCEPTION WHEN not_null_violation THEN
    IF SQLERRM NOT LIKE 'REQUIRED_TEXT_MISSING%' THEN RAISE EXCEPTION 'FAIL 17c: %', SQLERRM; END IF;
  END;
  BEGIN
    DELETE FROM platform.tenant_language WHERE tenant_id = current_setting('app.tenant_id')::uuid AND lang = 'fr';
    RAISE EXCEPTION 'FAIL 17d: main language removed';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'MAIN_LANGUAGE_REQUIRED%' THEN RAISE EXCEPTION 'FAIL 17d: %', SQLERRM; END IF;
  END;
  INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, 'b8200000-0000-0000-0000-000000000009');
  INSERT INTO core.location_version (tenant_id, location_id, valid_period, change_set_id, name, address_line1, city, province, postal_code, time_zone, holiday_jurisdiction)
    VALUES (current_setting('app.tenant_id')::uuid, 'b8200000-0000-0000-0000-000000000009', '[2020-01-01,)', gen_random_uuid(), 'Bureau de Montréal', '1 rue Sainte-Catherine', 'Montréal', 'QC', 'H2X 1Y4', 'America/Toronto', 'QC');
  BEGIN
    DELETE FROM platform.tenant_language WHERE tenant_id = current_setting('app.tenant_id')::uuid AND lang = 'fr';
    RAISE EXCEPTION 'FAIL 17e: French removed from an organization with a Quebec location';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'FRENCH_REQUIRED_FOR_QUEBEC%' THEN RAISE EXCEPTION 'FAIL 17e: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 17: French-main organization: French text required, fr-CA and fr filled, English screens see the French text marked, a Quebec location keeps French';
END $$;

-- ---------------------------------------------------------------------------------
-- 18. Another data language (Inuktut): optional first, what shows when a text is missing, then required
-- ---------------------------------------------------------------------------------
SELECT set_config('app.tenant_id', '83333333-3333-3333-3333-333333333333', false) AS cfg \gset
INSERT INTO platform.tenant_language (tenant_id, lang, locale, is_main, for_data)
  VALUES (current_setting('app.tenant_id')::uuid, 'iu', 'iu-CA', false, 'optional');
INSERT INTO core.hierarchy (tenant_id, hierarchy_id, code, kind, name_en) VALUES
  (current_setting('app.tenant_id')::uuid, 'b8300000-0000-0000-0000-000000000001', 'OPS', 'management', 'Operations'),
  (current_setting('app.tenant_id')::uuid, 'b8300000-0000-0000-0000-000000000002', 'FIN', 'financial', 'Finance');
DO $$
DECLARE h1 jsonb; h2 jsonb; r record;
BEGIN
  SELECT to_jsonb(x) INTO h1 FROM core.hierarchy x WHERE hierarchy_id = 'b8300000-0000-0000-0000-000000000001';
  SELECT to_jsonb(x) INTO h2 FROM core.hierarchy x WHERE hierarchy_id = 'b8300000-0000-0000-0000-000000000002';
  SELECT * INTO r FROM platform.text_for(current_setting('app.tenant_id')::uuid, 'core.hierarchy', h1, 'name', 'iu');
  IF r.value <> 'Operations' OR r.lang <> 'en' OR NOT r.substituted THEN RAISE EXCEPTION 'FAIL 18a: % ', r; END IF;
  INSERT INTO platform.translation (tenant_id, table_name, row_key, field, lang, value)
    VALUES (current_setting('app.tenant_id')::uuid, 'core.hierarchy', '["b8300000-0000-0000-0000-000000000001"]', 'name', 'iu', 'ᐊᐅᓚᑦᑎᔨᓂᖅ');
  SELECT * INTO r FROM platform.text_for(current_setting('app.tenant_id')::uuid, 'core.hierarchy', h1, 'name', 'iu');
  IF r.value <> 'ᐊᐅᓚᑦᑎᔨᓂᖅ' OR r.lang <> 'iu' OR r.substituted THEN RAISE EXCEPTION 'FAIL 18b: %', r; END IF;
  BEGIN
    INSERT INTO platform.translation (tenant_id, table_name, row_key, field, lang, value)
      VALUES (current_setting('app.tenant_id')::uuid, 'core.hierarchy', '["b8300000-0000-0000-0000-000000000001"]', 'name', 'fr', 'Exploitation');
    RAISE EXCEPTION 'FAIL 18c: French stored outside its column';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'TRANSLATION_HAS_COLUMN%' THEN RAISE EXCEPTION 'FAIL 18c: %', SQLERRM; END IF;
  END;
  BEGIN
    INSERT INTO platform.translation (tenant_id, table_name, row_key, field, lang, value)
      VALUES (current_setting('app.tenant_id')::uuid, 'core.hierarchy', '["b8300000-0000-0000-0000-000000000001"]', 'name', 'es', 'Operaciones');
    RAISE EXCEPTION 'FAIL 18d: text in a language the organization has not switched on';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'LANGUAGE_NOT_ENABLED%' THEN RAISE EXCEPTION 'FAIL 18d: %', SQLERRM; END IF;
  END;
  SELECT * INTO r FROM platform.text_for(current_setting('app.tenant_id')::uuid, 'core.hierarchy', h2, 'name', 'iu');
  IF r.value <> 'Finance' OR r.lang <> 'en' OR NOT r.substituted THEN RAISE EXCEPTION 'FAIL 18e: %', r; END IF;
  BEGIN
    UPDATE platform.tenant_language SET for_data = 'required' WHERE tenant_id = current_setting('app.tenant_id')::uuid AND lang = 'iu';
    RAISE EXCEPTION 'FAIL 18f: language made required while texts are missing';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'TRANSLATIONS_INCOMPLETE%' THEN RAISE EXCEPTION 'FAIL 18f: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 18a-f: a text with no version in the language asked shows as typed, marked with its language';
END $$;
-- Complete the missing texts (the list the setup screen shows), then make the language required
INSERT INTO platform.translation (tenant_id, table_name, row_key, field, lang, value)
  SELECT current_setting('app.tenant_id')::uuid, m.table_name, m.row_key, m.field, 'iu', 'ᑎᑎᕋᖅᓯᒪᔪᖅ ' || (m.row_key ->> -1)
  FROM platform.missing_translations(current_setting('app.tenant_id')::uuid, 'iu') m;
UPDATE platform.tenant_language SET for_data = 'required'
 WHERE tenant_id = current_setting('app.tenant_id')::uuid AND lang = 'iu';
-- A new row and its Inuktut text in one transaction
BEGIN;
INSERT INTO core.hierarchy (tenant_id, hierarchy_id, code, kind, name_en)
  VALUES (current_setting('app.tenant_id')::uuid, 'b8300000-0000-0000-0000-000000000003', 'GEO', 'geographic', 'Regions');
INSERT INTO platform.translation (tenant_id, table_name, row_key, field, lang, value)
  VALUES (current_setting('app.tenant_id')::uuid, 'core.hierarchy', '["b8300000-0000-0000-0000-000000000003"]', 'name', 'iu', 'ᐊᕕᒃᑐᖅᓯᒪᓂᖏᑦ');
COMMIT;
DO $$ BEGIN
  IF (SELECT count(*) FROM platform.missing_translations(current_setting('app.tenant_id')::uuid, 'iu')) <> 0 THEN
    RAISE EXCEPTION 'FAIL 18h: texts still missing';
  END IF;
  BEGIN
    SET CONSTRAINTS ALL IMMEDIATE;
    INSERT INTO core.hierarchy (tenant_id, hierarchy_id, code, kind, name_en)
      VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'GOV', 'governance', 'Board');
    RAISE EXCEPTION 'FAIL 18i: row without its required Inuktut text accepted';
  EXCEPTION WHEN not_null_violation THEN
    IF SQLERRM NOT LIKE 'REQUIRED_TEXT_MISSING%' THEN RAISE EXCEPTION 'FAIL 18i: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 18h-i: required language once every text has it; new rows bring their text in the same transaction';
END $$;

-- 18j. Screens only in a language CanDo has screens for: an Inuktut-speaking user gets English or French screens explicitly
DO $$ BEGIN
  BEGIN
    INSERT INTO platform.app_user (tenant_id, user_id, idp_subject, email, locale)
      VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'iu-user', 'iu8@example.test', 'iu-CA');
    RAISE EXCEPTION 'FAIL 18j: screens promised in a language that has none';
  EXCEPTION WHEN check_violation THEN
    IF SQLERRM NOT LIKE 'INTERFACE_LANGUAGE_NOT_AVAILABLE%' THEN RAISE EXCEPTION 'FAIL 18j: %', SQLERRM; END IF;
  END;
  RAISE NOTICE 'PASS 18j: a screen language is never substituted; iu-CA refused for screens until they exist';
END $$;

-- 19. Tenant isolation on the new tables
SELECT set_config('app.tenant_id', '81111111-1111-1111-1111-111111111111', false) AS cfg \gset
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM core.list_value WHERE tenant_id <> current_setting('app.tenant_id')::uuid)
     OR EXISTS (SELECT 1 FROM platform.tenant_language WHERE tenant_id <> current_setting('app.tenant_id')::uuid)
     OR EXISTS (SELECT 1 FROM platform.translation WHERE tenant_id <> current_setting('app.tenant_id')::uuid) THEN
    RAISE EXCEPTION 'FAIL 19a: another organization''s rows visible';
  END IF;
  BEGIN
    INSERT INTO core.list_value (tenant_id, list_code, code, category, rank, name_en)
      VALUES ('82222222-2222-2222-2222-222222222222', 'employment_type', 'x', 'casual', 9, 'X');
    RAISE EXCEPTION 'FAIL 19b: wrote another organization''s list';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS 19: lists, languages and translations isolated per organization';
END $$;

RESET ROLE;
\echo 'schema_0008_smoke: all checks passed'
