-- Smoke test for schema/0004_position_codes.sql (docs/18): published NOC versions and their immutability,
-- hierarchy distance, title search, tenant code schemes (published, list, free, unique, many-with-shares),
-- target rules, inheritance job → position → incumbent, requirements with a bona fide rationale,
-- suggestions, and row-level security on every new table.
-- Run after every migration, 0001 to 0008 (CI, after the 0003 smoke test), or on a scratch database holding them:
--   psql -v ON_ERROR_STOP=1 -f tests/schema/schema_0004_smoke.sql
-- It inserts test rows; run `supabase db reset` afterwards on the local stack.
\set ON_ERROR_STOP 1

DO $$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cando_app') THEN CREATE ROLE cando_app LOGIN; END IF;
END $$;
GRANT USAGE ON SCHEMA ref, platform, core, payroll TO cando_app;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA platform, core, payroll TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA core, ref TO cando_app;

INSERT INTO platform.tenant (tenant_id, name) VALUES
  ('41111111-1111-1111-1111-111111111111', 'Codes Test Tenant'),
  ('42222222-2222-2222-2222-222222222222', 'Other Codes Tenant')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------------
-- Loader (runs as the owner, never as cando_app): NOC 2021 V1.0 published, NOC 2026 V1.0 announced
-- ---------------------------------------------------------------------------------
INSERT INTO ref.code_scheme (scheme_code, name_en, name_fr, publisher, country, purpose, structure, code_pattern) VALUES
  ('NOC', 'National Occupational Classification', 'Classification nationale des professions',
   'Statistics Canada and Employment and Social Development Canada', 'CA', 'occupation', 'hierarchical', '^[0-9]{1,5}$');
INSERT INTO ref.code_scheme_version (version_id, scheme_code, label, status, release_date, assignable_levels, source, licence) VALUES
  ('NOC-2021-1.0', 'NOC', '2021 Version 1.0', 'loading', '2021-09-21', ARRAY['unit_group'],
   'Statistics Canada, Catalogue no. 12-583-X', 'Statistics Canada Open Licence');
INSERT INTO ref.code_scheme_version (version_id, scheme_code, label, status, expected_release, assignable_levels, supersedes) VALUES
  ('NOC-2026-1.0', 'NOC', '2026 Version 1.0', 'announced', 'December 2026', ARRAY['unit_group'], 'NOC-2021-1.0');

-- Real NOC 2021 V1.0 rows (generated from rules/classifications/noc-2021-v1.0.json)
INSERT INTO ref.code_item (version_id, code, level, depth, parent_code, title_en, attributes, related_codes) VALUES
  ('NOC-2021-1.0', '1', 'broad_category', 1, NULL, 'Business, finance and administration occupations', '{"broadCategory": "1"}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '4', 'broad_category', 1, NULL, 'Occupations in education, law and social, community and government services', '{"broadCategory": "4"}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '13', 'major_group', 2, '1', 'Administrative occupations and transportation logistics occupations', '{"broadCategory": "1", "teer": 3}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '41', 'major_group', 2, '4', 'Professional occupations in law, education, social, community and government services', '{"broadCategory": "4", "teer": 1}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '42', 'major_group', 2, '4', 'Front-line public protection services and paraprofessional occupations in legal, social, community, education services', '{"broadCategory": "4", "teer": 2}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '44', 'major_group', 2, '4', 'Care providers and legal and public protection support occupations', '{"broadCategory": "4", "teer": 4}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '131', 'sub_major_group', 3, '13', 'Administrative occupations', '{"broadCategory": "1", "teer": 3}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '413', 'sub_major_group', 3, '41', 'Professional occupations in social and community services', '{"broadCategory": "4", "teer": 1}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '422', 'sub_major_group', 3, '42', 'Paraprofessional occupations in legal, social, community and education services', '{"broadCategory": "4", "teer": 2}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '441', 'sub_major_group', 3, '44', 'Home care provider occupations', '{"broadCategory": "4", "teer": 4}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '1310', 'minor_group', 4, '131', 'Administrative, property and payroll officers', '{"broadCategory": "1", "teer": 3}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '4130', 'minor_group', 4, '413', 'Social and community service professionals', '{"broadCategory": "4", "teer": 1}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '4220', 'minor_group', 4, '422', 'Paraprofessional occupations in legal, social, community and education services', '{"broadCategory": "4", "teer": 2}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '4410', 'minor_group', 4, '441', 'Home care provider occupations', '{"broadCategory": "4", "teer": 4}'::jsonb, ARRAY[]::text[]),
  ('NOC-2021-1.0', '13102', 'unit_group', 5, '1310', 'Payroll administrators', '{"broadCategory": "1", "teer": 3}'::jsonb, ARRAY['12011','12101','12104','14102']::text[]),
  ('NOC-2021-1.0', '41300', 'unit_group', 5, '4130', 'Social workers', '{"broadCategory": "4", "teer": 1}'::jsonb, ARRAY['40030','41301','41320','42201']::text[]),
  ('NOC-2021-1.0', '42201', 'unit_group', 5, '4220', 'Social and community service workers', '{"broadCategory": "4", "teer": 2}'::jsonb, ARRAY['40030','41300','41301','41320','42203','54100']::text[]),
  ('NOC-2021-1.0', '42202', 'unit_group', 5, '4220', 'Early childhood educators and assistants', '{"broadCategory": "4", "teer": 2}'::jsonb, ARRAY['40030','41221','43100']::text[]),
  ('NOC-2021-1.0', '44101', 'unit_group', 5, '4410', 'Home support workers, caregivers and related occupations', '{"broadCategory": "4", "teer": 4}'::jsonb, ARRAY['44100']::text[]);
INSERT INTO ref.code_item_title (version_id, code, lang, title, kind) VALUES
  ('NOC-2021-1.0', '42201', 'en', 'Social and community service workers', 'official'),
  ('NOC-2021-1.0', '42201', 'en', 'Aboriginal outreach worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'addictions worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'child and youth worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'community development worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'community service worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'crisis intervention worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'developmental service worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'drop-in centre worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'family service worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'group home worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'income maintenance officer - social services', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'life skills instructor', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'mental health worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'rehabilitation worker - social services', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'social services worker', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'veteran services officer', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'welfare and compensation officer', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'women’s shelter supervisor', 'example'),
  ('NOC-2021-1.0', '42201', 'en', 'youth worker', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'Early childhood educators and assistants', 'official'),
  ('NOC-2021-1.0', '42202', 'en', 'child care worker assistant', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'daycare helper', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'daycare supervisor', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'daycare worker', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'early childhood assistant', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'early childhood education worker', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'early childhood educator (ECE)', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'early childhood educator (ECE) assistant', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'early childhood educator - preschool', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'early childhood program staff assistant', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'early childhood supervisor', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'preschool helper', 'example'),
  ('NOC-2021-1.0', '42202', 'en', 'preschool supervisor', 'example'),
  ('NOC-2021-1.0', '41300', 'en', 'Social workers', 'official'),
  ('NOC-2021-1.0', '41300', 'en', 'coordinator of social work', 'example'),
  ('NOC-2021-1.0', '41300', 'en', 'medical social worker', 'example'),
  ('NOC-2021-1.0', '41300', 'en', 'psychiatric social worker', 'example'),
  ('NOC-2021-1.0', '41300', 'en', 'social work supervisor', 'example'),
  ('NOC-2021-1.0', '41300', 'en', 'social worker', 'example'),
  ('NOC-2021-1.0', '44101', 'en', 'Home support workers, caregivers and related occupations', 'official'),
  ('NOC-2021-1.0', '44101', 'en', 'attendant for persons with disabilities - home care', 'example'),
  ('NOC-2021-1.0', '44101', 'en', 'family caregiver', 'example'),
  ('NOC-2021-1.0', '44101', 'en', 'home support worker', 'example'),
  ('NOC-2021-1.0', '44101', 'en', 'live-in caregiver', 'example'),
  ('NOC-2021-1.0', '44101', 'en', 'live-in caregiver - seniors', 'example'),
  ('NOC-2021-1.0', '44101', 'en', 'personal aide - home support', 'example'),
  ('NOC-2021-1.0', '44101', 'en', 'personal care attendant - home care', 'example'),
  ('NOC-2021-1.0', '44101', 'en', 'respite worker - home support', 'example'),
  ('NOC-2021-1.0', '13102', 'en', 'Payroll administrators', 'official'),
  ('NOC-2021-1.0', '13102', 'en', 'benefits officer - payroll administration', 'example'),
  ('NOC-2021-1.0', '13102', 'en', 'pay advisor', 'example'),
  ('NOC-2021-1.0', '13102', 'en', 'pay and benefits administrator', 'example'),
  ('NOC-2021-1.0', '13102', 'en', 'pay and benefits clerk', 'example'),
  ('NOC-2021-1.0', '13102', 'en', 'pay clerk', 'example'),
  ('NOC-2021-1.0', '13102', 'en', 'payroll clerk', 'example'),
  ('NOC-2021-1.0', '13102', 'en', 'payroll officer', 'example'),
  ('NOC-2021-1.0', '13102', 'en', 'salary administration officer', 'example');
INSERT INTO ref.code_item_requirement (version_id, code, seq, applies_to, text_en, kinds, strength) VALUES
  ('NOC-2021-1.0', '42201', 1, NULL, 'Completion of a college or university program in social work, child and youth care, psychology or other social science or health-related discipline is usually required.', ARRAY['education']::text[], 'usually_required'),
  ('NOC-2021-1.0', '42201', 2, NULL, 'Previous work experience in a social service environment as a volunteer or in a support capacity may replace formal education requirements for some occupations in this unit group.', ARRAY['experience']::text[], 'unspecified'),
  ('NOC-2021-1.0', '42201', 3, NULL, 'Social service workers may be required to be a member of a provincial regulatory body in some provinces.', ARRAY['licence_or_certification']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '42202', 1, 'Early childhood educators', 'Completion of a two- to four-year college program in early childhood education or A bachelor’s degree in child development is required.', ARRAY['education']::text[], 'required'),
  ('NOC-2021-1.0', '42202', 2, 'Early childhood educators', 'Licensing is required in Ontario and certification is required in British Columbia for early childhood educators. Licensing for early childhood educators is usually required in all other provinces and territories.', ARRAY['licence_or_certification']::text[], 'usually_required'),
  ('NOC-2021-1.0', '42202', 3, 'Early childhood educator assistants', 'Completion of secondary school is required.', ARRAY['education']::text[], 'required'),
  ('NOC-2021-1.0', '42202', 4, 'Early childhood educator assistants', 'Experience in child care is required.', ARRAY['experience']::text[], 'required'),
  ('NOC-2021-1.0', '42202', 5, 'Early childhood educator assistants', 'Completion of an early childhood education assistant certificate program or post-secondary courses in early childhood education may be required.', ARRAY['education','licence_or_certification']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '42202', 6, 'Early childhood educator assistants', 'Licensing by a provincial or territorial association as an early childhood educator may be required.', ARRAY['licence_or_certification']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '41300', 1, NULL, 'A bachelor’s degree in social work is required in Newfoundland and Labrador, Nova Scotia, Prince Edward Island, New Brunswick, Quebec, Ontario, Manitoba, Saskatchewan, British Columbia, the Northwest Territories and Nunavut.', ARRAY['education']::text[], 'required'),
  ('NOC-2021-1.0', '41300', 2, NULL, 'In Alberta, a bachelor’s degree or diploma in social work is required.', ARRAY['education']::text[], 'required'),
  ('NOC-2021-1.0', '41300', 3, NULL, 'Supervised practical experience is usually required.', ARRAY['experience']::text[], 'usually_required'),
  ('NOC-2021-1.0', '41300', 4, NULL, 'Successful completion of provincial written and oral examinations may be required.', ARRAY['other']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '41300', 5, NULL, 'Registration with a provincial governing body is mandatory to practise as a social worker in Newfoundland and Labrador, Nova Scotia, Prince Edward Island, New Brunswick, Quebec, Ontario, Alberta and British Columbia.', ARRAY['licence_or_certification']::text[], 'unspecified'),
  ('NOC-2021-1.0', '41300', 6, NULL, 'Use of the titles “Social Worker” and “Registered Social Worker” is regulated in all provinces.', ARRAY['licence_or_certification']::text[], 'unspecified'),
  ('NOC-2021-1.0', '41300', 7, NULL, 'Membership in a provincial association of social workers is usually required.', ARRAY['licence_or_certification']::text[], 'usually_required'),
  ('NOC-2021-1.0', '44101', 1, NULL, 'Some secondary school education is usually required.', ARRAY['education']::text[], 'usually_required'),
  ('NOC-2021-1.0', '44101', 2, NULL, 'Home management experience may be required.', ARRAY['experience']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '44101', 3, NULL, 'College or other courses in home support may be required.', ARRAY['education']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '44101', 4, NULL, 'First aid certification may be required.', ARRAY['licence_or_certification']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '44101', 5, NULL, 'Completion of a training program in care of the elderly, care of persons with disabilities, convalescent care or in a related field may be required.', ARRAY['education','training']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '13102', 1, NULL, 'Completion of secondary school is usually required.', ARRAY['education']::text[], 'usually_required'),
  ('NOC-2021-1.0', '13102', 2, NULL, 'Completion of college or other courses in accounting, bookkeeping or payroll administration or Experience in payroll administration is usually required.', ARRAY['education','experience']::text[], 'usually_required'),
  ('NOC-2021-1.0', '13102', 3, NULL, 'Payroll association certification may be required.', ARRAY['licence_or_certification']::text[], 'may_be_required'),
  ('NOC-2021-1.0', '13102', 4, NULL, 'Experience using a payroll system or software may be required.', ARRAY['experience']::text[], 'may_be_required');

UPDATE ref.code_scheme_version SET status = 'published', content_sha256 = 'smoke-test', item_count = 19, loaded_at = now()
 WHERE version_id = 'NOC-2021-1.0';

-- 1. A published version cannot change
DO $$ BEGIN
  UPDATE ref.code_item SET title_en = 'changed' WHERE version_id = 'NOC-2021-1.0' AND code = '42201';
  RAISE EXCEPTION 'FAIL 1: published NOC item changed';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 1: published NOC 2021 items cannot be changed';
END $$;

-- 2. Depth of the deepest common ancestor
DO $$ BEGIN
  IF ref.code_common_depth('NOC-2021-1.0', '42201', '42201') <> 5
     OR ref.code_common_depth('NOC-2021-1.0', '42201', '42202') <> 4
     OR ref.code_common_depth('NOC-2021-1.0', '42201', '41300') <> 1
     OR ref.code_common_depth('NOC-2021-1.0', '42201', '13102') <> 0 THEN
    RAISE EXCEPTION 'FAIL 2: common depth';
  END IF;
  RAISE NOTICE 'PASS 2: 42201 vs 42201 = 5, vs 42202 = 4 (same minor group), vs 41300 = 1, vs 13102 = 0';
END $$;

-- 3. Title search finds the unit group from an example title
DO $$ DECLARE c text; t text; BEGIN
  SELECT code, matched_title INTO c, t FROM ref.search_code_titles('NOC-2021-1.0', 'youth worker', 'en');
  IF c IS DISTINCT FROM '42201' THEN RAISE EXCEPTION 'FAIL 3: got %', c; END IF;
  RAISE NOTICE 'PASS 3: "youth worker" -> % (%)', c, t;
END $$;

-- 4. A mapping must point at real items (NOC 2026 has no items yet)
DO $$ BEGIN
  INSERT INTO ref.code_mapping (from_version_id, from_code, to_version_id, to_code, relation, source)
    VALUES ('NOC-2021-1.0', '42201', 'NOC-2026-1.0', '42201', 'one_to_one', 'test');
  RAISE EXCEPTION 'FAIL 4';
EXCEPTION WHEN foreign_key_violation THEN RAISE NOTICE 'PASS 4: no mapping to a version that is not loaded';
END $$;

-- ---------------------------------------------------------------------------------
-- Tenant data as cando_app
-- ---------------------------------------------------------------------------------
SET ROLE cando_app;
SELECT set_config('app.tenant_id', '41111111-1111-1111-1111-111111111111', false);

INSERT INTO core.legal_entity (tenant_id, legal_entity_id) VALUES (current_setting('app.tenant_id')::uuid, 'a4000000-0000-0000-0000-000000000001');
INSERT INTO core.location (tenant_id, location_id) VALUES (current_setting('app.tenant_id')::uuid, 'b4000000-0000-0000-0000-000000000001');
INSERT INTO core.org_unit (tenant_id, org_unit_id) VALUES (current_setting('app.tenant_id')::uuid, 'c4000000-0000-0000-0000-000000000001');
INSERT INTO core.job (tenant_id, job_id) VALUES (current_setting('app.tenant_id')::uuid, 'd4000000-0000-0000-0000-000000000001');
INSERT INTO core.job_version (tenant_id, job_id, valid_period, change_set_id, code, title_en)
  VALUES (current_setting('app.tenant_id')::uuid, 'd4000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'CSW2', 'Community Support Worker 2');
INSERT INTO core.position (tenant_id, position_id, number) VALUES
  (current_setting('app.tenant_id')::uuid, 'e4000000-0000-0000-0000-000000000001', 'NL-041'),
  (current_setting('app.tenant_id')::uuid, 'e4000000-0000-0000-0000-000000000002', 'NL-042');
INSERT INTO core.position_version (tenant_id, position_id, valid_period, change_set_id, job_id, org_unit_id, location_id, fte_budget, employment_type, status) VALUES
  (current_setting('app.tenant_id')::uuid, 'e4000000-0000-0000-0000-000000000001', '[2020-01-01,)', gen_random_uuid(), 'd4000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 1, 'permanent', 'active'),
  (current_setting('app.tenant_id')::uuid, 'e4000000-0000-0000-0000-000000000002', '[2020-01-01,)', gen_random_uuid(), 'd4000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 1, 'permanent', 'active');
INSERT INTO core.person (tenant_id, person_id) VALUES (current_setting('app.tenant_id')::uuid, 'f4000000-0000-0000-0000-000000000001');
INSERT INTO core.employment (tenant_id, employment_id, person_id, legal_entity_id, employee_number)
  VALUES (current_setting('app.tenant_id')::uuid, 'f4100000-0000-0000-0000-000000000001', 'f4000000-0000-0000-0000-000000000001', 'a4000000-0000-0000-0000-000000000001', 'E-041');
INSERT INTO core.assignment (tenant_id, assignment_id, employment_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'f4200000-0000-0000-0000-000000000001', 'f4100000-0000-0000-0000-000000000001');
INSERT INTO core.assignment_version (tenant_id, assignment_id, valid_period, change_set_id, position_id, org_unit_id, location_id, fte, is_primary)
  VALUES (current_setting('app.tenant_id')::uuid, 'f4200000-0000-0000-0000-000000000001', '[2021-04-01,)', gen_random_uuid(),
          'e4000000-0000-0000-0000-000000000001', 'c4000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000001', 1, true);

-- Code schemes: NOC (published), job family (tenant list, hierarchical), salary survey (several codes with shares),
-- position control number (free, pattern, unique, position only), legacy payroll ID (free, unique, incumbent only)
INSERT INTO core.code_scheme (tenant_id, scheme_id, code, name_en, name_fr, source, ref_scheme_code, current_version_id, purpose, country,
                              structure, ordering, applies_to, required_on) VALUES
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000001', 'NOC', 'NOC', 'CNP', 'published', 'NOC', 'NOC-2021-1.0',
   'occupation', 'CA', 'hierarchical', 'hierarchy', ARRAY['job','position','assignment'], ARRAY['job']);
INSERT INTO core.code_scheme (tenant_id, scheme_id, code, name_en, source, purpose, structure, ordering, applies_to) VALUES
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000002', 'JOB_FAMILY', 'Job family', 'tenant', 'job_family',
   'hierarchical', 'alpha_title', ARRAY['job','position']);
INSERT INTO core.code_scheme (tenant_id, scheme_id, code, name_en, source, purpose, applies_to, values_per_target, shares_total_100) VALUES
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000003', 'SURVEY_A', 'Salary survey A', 'tenant', 'salary_survey',
   ARRAY['job','position'], 'many', true);
INSERT INTO core.code_scheme (tenant_id, scheme_id, code, name_en, source, purpose, values_mode, code_pattern, applies_to, uniqueness, inherit) VALUES
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000004', 'POSITION_CONTROL', 'Position control number', 'tenant',
   'identifier', 'free', '^POS-[0-9]{5}$', ARRAY['position'], 'unique', 'none');
INSERT INTO core.code_scheme (tenant_id, scheme_id, code, name_en, source, purpose, values_mode, code_case, applies_to, uniqueness) VALUES
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000005', 'LEGACY_ID', 'Legacy payroll ID', 'tenant',
   'external_system', 'free', 'upper', ARRAY['assignment'], 'unique');

INSERT INTO core.code_value (tenant_id, scheme_id, code, parent_code, title_en, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000002', 'CS', NULL, 'Community Services', '[2020-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000002', 'CS-SUP', 'CS', 'Community Support', '[2020-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000003', 'S-410', NULL, 'Community services worker II', '[2020-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, '04000000-0000-0000-0000-000000000003', 'S-415', NULL, 'Youth worker', '[2020-01-01,)', gen_random_uuid());

-- 5. NOC unit group on the job
INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, ref_version_id, code, slot, source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'job', 'd4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000001',
          'NOC-2021-1.0', '42201', '', 'manual', '[2026-01-01,)', gen_random_uuid());
\echo PASS 5: NOC 42201 attached to the job

-- 6. Only unit groups can be assigned
DO $$ BEGIN
  INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, ref_version_id, code, slot, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000002', '04000000-0000-0000-0000-000000000001',
            'NOC-2021-1.0', '4220', '', 'manual', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 6';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 6: minor group 4220 refused (CODE_LEVEL_NOT_ASSIGNABLE)';
END $$;

-- 7. NOC 2026 is announced, not accepted
DO $$ BEGIN
  INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, ref_version_id, code, slot, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'job', 'd4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000001',
            'NOC-2026-1.0', '42201', '', 'manual', '[2027-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 7';
EXCEPTION WHEN check_violation OR foreign_key_violation THEN RAISE NOTICE 'PASS 7: NOC 2026 code refused until loaded and accepted';
END $$;

-- 8. One NOC code per version per target per day
DO $$ BEGIN
  INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, ref_version_id, code, slot, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'job', 'd4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000001',
            'NOC-2021-1.0', '42202', '', 'manual', '[2026-06-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 8';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 8: second NOC 2021 code on the same job and dates refused';
END $$;

-- 9. List schemes take only their values
DO $$ BEGIN
  INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'job', 'd4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000002',
            'XX', '', 'manual', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 9';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 9: job family XX refused (CODE_NOT_IN_LIST)';
END $$;
INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'job', 'd4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000002',
          'CS-SUP', '', 'manual', '[2026-01-01,)', gen_random_uuid());

-- 10. Free codes: format and uniqueness across positions
DO $$ BEGIN
  INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000004',
            'POS-12', '', 'manual', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 10a';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 10a: POS-12 refused (CODE_FORMAT)';
END $$;
INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000004',
          'POS-00410', '', 'manual', '[2026-01-01,2027-01-01)', gen_random_uuid());
DO $$ BEGIN
  INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000002', '04000000-0000-0000-0000-000000000004',
            'POS-00410', '', 'manual', '[2026-06-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 10b';
EXCEPTION WHEN exclusion_violation THEN RAISE NOTICE 'PASS 10b: POS-00410 cannot belong to two positions at once';
END $$;
INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000002', '04000000-0000-0000-0000-000000000004',
          'POS-00410', '', 'manual', '[2027-01-01,)', gen_random_uuid());
\echo PASS 10c: POS-00410 moves to NL-042 once NL-041 releases it

-- 11. Incumbent-only scheme; codes upper-cased by the scheme
DO $$ BEGIN
  INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000005',
            'L-1', '', 'manual', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 11a';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 11a: legacy ID refused on a position (CODE_TARGET_NOT_ALLOWED)';
END $$;
INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, source, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'assignment', 'f4200000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000005',
          'l-88213', '', 'import', '[2026-01-01,)', gen_random_uuid());
DO $$ BEGIN
  IF (SELECT code FROM core.code_assignment WHERE scheme_id = '04000000-0000-0000-0000-000000000005') <> 'L-88213' THEN RAISE EXCEPTION 'FAIL 11b'; END IF;
  RAISE NOTICE 'PASS 11b: incumbent code stored as L-88213';
END $$;

-- 12. Several survey matches with shares; shares are refused on one-value schemes
INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, code, slot, share, match_quality, source, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000003', 'S-410', '', 60, 'blended', 'manual', '[2026-01-01,)', gen_random_uuid()),
  (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000003', 'S-415', '', 40, 'blended', 'manual', '[2026-01-01,)', gen_random_uuid());
DO $$ BEGIN
  INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, ref_version_id, code, slot, share, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000002', '04000000-0000-0000-0000-000000000001',
            'NOC-2021-1.0', '42201', '', 50, 'manual', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 12';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 12: two survey matches at 60/40 kept; a 50%% NOC share refused';
END $$;

-- 13. The incumbent's effective codes: NOC and job family from the job, survey from the position, legacy ID from the
--     assignment; the position control number does not inherit (inherit = none)
DO $$ DECLARE n int; noc_origin text; BEGIN
  SELECT count(*) INTO n FROM core.resolve_codes('assignment', 'f4200000-0000-0000-0000-000000000001', '2026-11-01');
  SELECT origin_type INTO noc_origin FROM core.resolve_codes('assignment', 'f4200000-0000-0000-0000-000000000001', '2026-11-01') WHERE scheme_code = 'NOC';
  IF n <> 5 OR noc_origin <> 'job' THEN RAISE EXCEPTION 'FAIL 13: % rows, NOC from %', n, noc_origin; END IF;
  RAISE NOTICE 'PASS 13: incumbent resolves 5 codes; NOC 42201 inherited from the job';
END $$;

-- 14. A position-level override wins for its incumbents
INSERT INTO core.code_assignment (tenant_id, target_type, target_id, scheme_id, ref_version_id, code, slot, source, reason, valid_period, change_set_id)
  VALUES (current_setting('app.tenant_id')::uuid, 'position', 'e4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000001',
          'NOC-2021-1.0', '42202', '', 'override', 'Position runs the early learning program', '[2026-09-01,)', gen_random_uuid());
DO $$ DECLARE c text; o text; BEGIN
  SELECT code, origin_type INTO c, o FROM core.resolve_codes('assignment', 'f4200000-0000-0000-0000-000000000001', '2026-11-01') WHERE scheme_code = 'NOC';
  IF c <> '42202' OR o <> 'position' THEN RAISE EXCEPTION 'FAIL 14: % from %', c, o; END IF;
  SELECT code INTO c FROM core.resolve_codes('assignment', 'f4200000-0000-0000-0000-000000000001', '2026-08-31') WHERE scheme_code = 'NOC';
  IF c <> '42201' THEN RAISE EXCEPTION 'FAIL 14b: % on 31 Aug', c; END IF;
  RAISE NOTICE 'PASS 14: override 42202 from 1 Sep; 42201 from the job before that';
END $$;

-- 15. Nothing before the codes were valid
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM core.resolve_codes('assignment', 'f4200000-0000-0000-0000-000000000001', '2025-06-01')) THEN RAISE EXCEPTION 'FAIL 15'; END IF;
  RAISE NOTICE 'PASS 15: no codes as of 1 Jun 2025';
END $$;

-- 16. An active required requirement needs a bona fide rationale; a proposal from NOC does not yet
DO $$ BEGIN
  INSERT INTO core.work_requirement (tenant_id, requirement_id, target_type, target_id, status, kind, strength, text_en, source, valid_period, change_set_id)
    VALUES (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd4000000-0000-0000-0000-000000000001', 'active', 'education', 'required',
            'College diploma in social work, child and youth care or a related field', 'job', '[2026-01-01,)', gen_random_uuid());
  RAISE EXCEPTION 'FAIL 16';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 16a: required without rationale refused';
END $$;
INSERT INTO core.work_requirement (tenant_id, requirement_id, target_type, target_id, status, kind, strength, text_en, match_key, source, source_ref, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd4000000-0000-0000-0000-000000000001', 'proposed', 'education', 'preferred',
   'Completion of a college or university program in social work, child and youth care, psychology or other social science or health-related discipline is usually required.',
   'education:college_diploma', 'noc', '{"versionId":"NOC-2021-1.0","code":"42201","seq":1}', '[2026-01-01,)', gen_random_uuid());
INSERT INTO core.work_requirement (tenant_id, requirement_id, target_type, target_id, status, kind, strength, text_en, match_key, rationale, source, valid_period, change_set_id) VALUES
  (current_setting('app.tenant_id')::uuid, gen_random_uuid(), 'job', 'd4000000-0000-0000-0000-000000000001', 'active', 'security_screening', 'required',
   'Criminal record check for work with vulnerable people', 'screening:vulnerable_sector',
   'The role works alone with youth; required by the funding agreement and provincial criminal records review rules', 'job', '[2026-01-01,)', gen_random_uuid());
\echo PASS 16b: NOC proposal and a required screening with its rationale stored

-- 17. An accepted suggestion records the choice and the person
DO $$ BEGIN
  INSERT INTO core.code_suggestion (tenant_id, target_type, target_id, scheme_id, ref_version_id, purpose, method, candidates, status)
    VALUES (current_setting('app.tenant_id')::uuid, 'job', 'd4000000-0000-0000-0000-000000000001', '04000000-0000-0000-0000-000000000001',
            'NOC-2021-1.0', 'coding', 'title_index', '[{"code":"42201","score":0.83}]', 'accepted');
  RAISE EXCEPTION 'FAIL 17';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'PASS 17: accepted suggestion without decision details refused';
END $$;

-- 18. Tenant isolation
SELECT set_config('app.tenant_id', '42222222-2222-2222-2222-222222222222', false);
DO $$ BEGIN
  IF (SELECT count(*) FROM core.code_assignment) <> 0 OR (SELECT count(*) FROM core.code_scheme) <> 0
     OR (SELECT count(*) FROM core.work_requirement) <> 0 THEN RAISE EXCEPTION 'FAIL 18a'; END IF;
  RAISE NOTICE 'PASS 18a: other tenant sees no schemes, codes or requirements';
END $$;
DO $$ BEGIN
  INSERT INTO core.code_scheme (tenant_id, code, name_en, source, purpose, applies_to)
    VALUES ('41111111-1111-1111-1111-111111111111', 'X', 'X', 'tenant', 'other', ARRAY['job']);
  RAISE EXCEPTION 'FAIL 18b';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS 18b: cannot write into another tenant';
END $$;
RESET ROLE;

-- 19. Row-level security on every new core table
DO $$ DECLARE missing text; BEGIN
  SELECT string_agg(c.relname, ', ') INTO missing
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'core' AND c.relkind = 'r'
    AND c.relname IN ('code_scheme','code_value','code_assignment','code_mapping','code_scheme_rule','work_requirement',
                      'work_requirement_suppression','code_suggestion','recoding_campaign','similarity_profile')
    AND NOT (c.relrowsecurity AND c.relforcerowsecurity);
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'FAIL 19: %', missing; END IF;
  RAISE NOTICE 'PASS 19: RLS forced on the 10 new core tables';
END $$;

\echo Migration 0004 smoke test passed.
