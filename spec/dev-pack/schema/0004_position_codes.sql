-- =====================================================================================
-- CanDo HRIS — migration 0004: code schemes, occupational classification (NOC),
-- position and job requirements, code suggestions and similarity profiles
-- Applies after 0001_initial (schema/cando_schema.sql), 0002_roles and
-- 0003_enterprise_structures. Specification: docs/18-position-codes-and-requirements.md
-- (section numbers below). Conventions as in 0001: tenant_id + RLS on every tenant
-- table, effective-dated rows with valid_period and sys_period, change_set_id on every
-- business row. Published classifications (NOC and others) are global reference data
-- in ref, read-only to cando_app, loaded from rules/classifications/ by the loader.
-- =====================================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- title search (§2.6); on Supabase, in the extensions schema

-- Orderings a scheme can choose (§3.2). ICU collations: natural order sorts A2 before A10.
CREATE COLLATION IF NOT EXISTS core.natural_sort (provider = icu, locale = 'und-u-kn');
CREATE COLLATION IF NOT EXISTS core.en_ca (provider = icu, locale = 'en-CA');
CREATE COLLATION IF NOT EXISTS core.fr_ca (provider = icu, locale = 'fr-CA');

-- -------------------------------------------------------------------------------------
-- Published schemes: global reference data (no RLS) (§2, §8)
-- -------------------------------------------------------------------------------------
CREATE TABLE ref.code_scheme (
  scheme_code   text PRIMARY KEY,                      -- 'NOC', 'EEOG', 'ISCO', 'US_SOC', 'UK_SOC'
  name_en       text NOT NULL,
  name_fr       text,
  publisher     text NOT NULL,
  country       text NOT NULL,                         -- ISO 3166-1 alpha-2, or 'INT' for international
  purpose       text NOT NULL CHECK (purpose IN ('occupation','employment_equity','skills','other')),
  structure     text NOT NULL CHECK (structure IN ('flat','hierarchical')),
  code_pattern  text                                   -- e.g. '^[0-9]{1,5}$' for NOC
);

CREATE TABLE ref.code_scheme_version (
  version_id      text PRIMARY KEY,                    -- 'NOC-2021-1.0', 'NOC-2026-1.0'
  scheme_code     text NOT NULL REFERENCES ref.code_scheme,
  label           text NOT NULL,                       -- '2021 Version 1.0'
  status          text NOT NULL CHECK (status IN ('announced','loading','published','superseded','retired')),
  release_date    date,
  expected_release text,                               -- for announced versions, as the publisher states it
  levels          jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{ "level": "unit_group", "depth": 5, "count": 516 }, …]
  assignable_levels text[] NOT NULL DEFAULT '{}',      -- levels a job or position may be coded at (NOC: unit_group)
  source          text,
  licence         text,
  content_sha256  text,                                -- of the data file loaded
  item_count      integer,
  supersedes      text REFERENCES ref.code_scheme_version,
  loaded_at       timestamptz,
  CHECK (status IN ('announced','loading') OR (content_sha256 IS NOT NULL AND item_count IS NOT NULL))
);

CREATE TABLE ref.code_item (
  version_id     text NOT NULL REFERENCES ref.code_scheme_version,
  code           text NOT NULL,
  level          text NOT NULL,                        -- NOC: broad_category, major_group, sub_major_group, minor_group, unit_group
  depth          smallint NOT NULL CHECK (depth >= 1),
  parent_code    text,
  title_en       text NOT NULL,
  title_fr       text,                                 -- NOC: from the French CNP publication, not a translation
  definition_en  text,
  definition_fr  text,
  attributes     jsonb NOT NULL DEFAULT '{}'::jsonb,   -- NOC: { "teer": 2, "broadCategory": "4" }
  content        jsonb NOT NULL DEFAULT '{}'::jsonb,   -- duties, example titles, inclusions, exclusions, additional information
  related_codes  text[] NOT NULL DEFAULT '{}',         -- cross-references (NOC: unit groups named in the exclusions)
  PRIMARY KEY (version_id, code),
  FOREIGN KEY (version_id, parent_code) REFERENCES ref.code_item (version_id, code),
  CHECK ((parent_code IS NULL) = (depth = 1))
);
CREATE INDEX code_item_parent ON ref.code_item (version_id, parent_code);
CREATE INDEX code_item_teer ON ref.code_item (version_id, ((attributes->>'teer')::smallint)) WHERE attributes ? 'teer';

-- Every title people may type: official, example, inclusion and alphabetical index titles (§2.6)
CREATE TABLE ref.code_item_title (
  version_id  text NOT NULL,
  code        text NOT NULL,
  lang        ref.lang NOT NULL,
  title       text NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('official','example','inclusion','index')),
  FOREIGN KEY (version_id, code) REFERENCES ref.code_item (version_id, code)
);
CREATE INDEX code_item_title_trgm ON ref.code_item_title USING gin (title gin_trgm_ops);
CREATE INDEX code_item_title_code ON ref.code_item_title (version_id, code);

-- Employment requirements as published, one statement per row (§6.3)
CREATE TABLE ref.code_item_requirement (
  version_id  text NOT NULL,
  code        text NOT NULL,
  seq         smallint NOT NULL,
  applies_to  text,                                    -- sub-group heading in the publication, e.g. 'Notaries (Quebec)'
  text_en     text NOT NULL,
  text_fr     text,
  kinds       text[] NOT NULL CHECK (kinds <@ ARRAY['education','training','experience','licence_or_certification','other']::text[]),
  strength    text NOT NULL CHECK (strength IN ('required','usually_required','may_be_required','unspecified')),
  PRIMARY KEY (version_id, code, seq),
  FOREIGN KEY (version_id, code) REFERENCES ref.code_item (version_id, code)
);

-- Correspondence between versions (NOC 2021 → 2026) and crosswalks between schemes (NOC ↔ ISCO) (§5.1, §8)
CREATE TABLE ref.code_mapping (
  from_version_id text NOT NULL,
  from_code       text NOT NULL,
  to_version_id   text NOT NULL,
  to_code         text NOT NULL,
  relation        text NOT NULL CHECK (relation IN ('one_to_one','split','merge','partial','renamed')),
  share           numeric(5,4) CHECK (share > 0 AND share <= 1),   -- part of the from-code that goes to this to-code, when published
  note            text,
  source          text NOT NULL,                       -- the publisher's correspondence table
  PRIMARY KEY (from_version_id, from_code, to_version_id, to_code),
  FOREIGN KEY (from_version_id, from_code) REFERENCES ref.code_item (version_id, code),
  FOREIGN KEY (to_version_id, to_code) REFERENCES ref.code_item (version_id, code),
  CHECK (from_version_id <> to_version_id)
);

-- A published version cannot change: a correction is a new version (same principle as rule editions)
CREATE FUNCTION ref.guard_published_code_rows() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v text := COALESCE(OLD.version_id, NEW.version_id);
BEGIN
  IF EXISTS (SELECT 1 FROM ref.code_scheme_version WHERE version_id = v AND status IN ('published','superseded','retired')) THEN
    RAISE EXCEPTION 'CODE_VERSION_IMMUTABLE: % is published; load a new version instead', v USING ERRCODE = 'check_violation';
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;
CREATE TRIGGER code_item_immutable BEFORE INSERT OR UPDATE OR DELETE ON ref.code_item
  FOR EACH ROW EXECUTE FUNCTION ref.guard_published_code_rows();
CREATE TRIGGER code_item_title_immutable BEFORE INSERT OR UPDATE OR DELETE ON ref.code_item_title
  FOR EACH ROW EXECUTE FUNCTION ref.guard_published_code_rows();
CREATE TRIGGER code_item_requirement_immutable BEFORE INSERT OR UPDATE OR DELETE ON ref.code_item_requirement
  FOR EACH ROW EXECUTE FUNCTION ref.guard_published_code_rows();

-- Path from the top of the hierarchy to a code, and the depth of the deepest common ancestor (§7.3)
CREATE FUNCTION ref.code_path(p_version text, p_code text) RETURNS text[] LANGUAGE sql STABLE AS $$
  WITH RECURSIVE up (code, parent_code, depth) AS (
    SELECT code, parent_code, depth FROM ref.code_item WHERE version_id = p_version AND code = p_code
    UNION ALL
    SELECT i.code, i.parent_code, i.depth
    FROM ref.code_item i JOIN up ON i.version_id = p_version AND i.code = up.parent_code
  )
  SELECT array_agg(code ORDER BY depth) FROM up
$$;

CREATE FUNCTION ref.code_common_depth(p_version text, p_a text, p_b text) RETURNS smallint LANGUAGE sql STABLE AS $$
  SELECT count(*)::smallint
  FROM unnest(ref.code_path(p_version, p_a)) WITH ORDINALITY AS a (code, n)
  JOIN unnest(ref.code_path(p_version, p_b)) WITH ORDINALITY AS b (code, n) ON a.n = b.n AND a.code = b.code
$$;

-- Title search across official, example and index titles (§2.6). One row per code: its best-matching title.
-- score = pg_trgm word_similarity(query, title): how well the typed words match part of a title;
-- ties go to the closer whole title (similarity), then the code.
CREATE FUNCTION ref.search_code_titles(p_version text, p_query text, p_lang ref.lang DEFAULT 'en', p_limit int DEFAULT 10)
RETURNS TABLE (code text, matched_title text, kind text, score real, whole_title_score real) LANGUAGE sql STABLE AS $$
  SELECT * FROM (
    SELECT DISTINCT ON (t.code) t.code, t.title, t.kind,
           word_similarity(p_query, t.title) AS score, similarity(p_query, t.title) AS whole_title_score
    FROM ref.code_item_title t
    WHERE t.version_id = p_version AND t.lang = p_lang AND p_query <% t.title
    ORDER BY t.code, word_similarity(p_query, t.title) DESC, similarity(p_query, t.title) DESC, t.title
  ) best
  ORDER BY score DESC, whole_title_score DESC, code
  LIMIT p_limit
$$;

-- The existing NOC table stays for job_version.noc_code until the data migration (§5.4);
-- French titles arrive later from the CNP publication.
ALTER TABLE ref.noc ALTER COLUMN title_fr DROP NOT NULL;
COMMENT ON COLUMN core.job_version.noc_code IS
  'Read-only after migration 0004: codes live in core.code_assignment; read them with core.resolve_codes(). Kept for the data migration only (docs/18 §5.4).';
COMMENT ON COLUMN core.job_version.pay_equity_class IS
  'Read-only after migration 0004: use the PAY_EQUITY_CLASS code scheme (docs/18 §5.4).';
COMMENT ON COLUMN core.job_version.ee_occupational_group IS
  'Read-only after migration 0004: use the EEOG code scheme derived from NOC (docs/18 §5.2).';

-- -------------------------------------------------------------------------------------
-- Tenant code schemes and values (§3)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.code_scheme (
  tenant_id            uuid NOT NULL,
  scheme_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 text NOT NULL,                  -- 'NOC', 'JOB_FAMILY', 'SURVEY_A', 'POSITION_CONTROL', 'LEGACY_ID'
  name_en              text NOT NULL,
  name_fr              text,
  description_en       text,
  description_fr       text,
  source               text NOT NULL CHECK (source IN ('published','tenant','derived')),
  ref_scheme_code      text REFERENCES ref.code_scheme,
  current_version_id   text REFERENCES ref.code_scheme_version,  -- version new codes use (published and derived schemes)
  accepted_version_ids text[] NOT NULL DEFAULT '{}',   -- versions allowed at the same time, e.g. during the NOC 2026 transition
  purpose              text NOT NULL CHECK (purpose IN ('occupation','job_family','job_level','pay_grade','salary_survey','department',
                                                       'cost','pay_equity','employment_equity','identifier','external_system','other')),
  country              text,                           -- ISO 3166-1 alpha-2 when the scheme is national
  structure            text NOT NULL DEFAULT 'flat' CHECK (structure IN ('flat','hierarchical')),
  ordering             text NOT NULL DEFAULT 'natural_code'
                       CHECK (ordering IN ('natural_code','alpha_code','alpha_title','custom_rank','hierarchy')),
  values_mode          text NOT NULL DEFAULT 'list' CHECK (values_mode IN ('list','free','list_or_free')),
  code_pattern         text,                           -- every code must match, e.g. '^POS-[0-9]{5}$'
  code_case            text NOT NULL DEFAULT 'as_entered' CHECK (code_case IN ('as_entered','upper')),
  applies_to           text[] NOT NULL,
  required_on          text[] NOT NULL DEFAULT '{}',
  values_per_target    text NOT NULL DEFAULT 'one' CHECK (values_per_target IN ('one','many')),
  shares_total_100     boolean NOT NULL DEFAULT false, -- 'many' schemes: shares on one target add up to 100 (blended survey match)
  uniqueness           text NOT NULL DEFAULT 'none' CHECK (uniqueness IN ('none','unique')),  -- unique: a code belongs to one target at a time
  inherit              text NOT NULL DEFAULT 'down' CHECK (inherit IN ('none','down')),      -- down: job → position → incumbent
  override_needs_reason boolean NOT NULL DEFAULT true,
  derived_from         jsonb,                          -- { "schemeCode": "NOC", "mapping": "ref" | "tenant", "toVersionId": "…" }
  maintainer_role      text,
  status               text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  display_order        smallint NOT NULL DEFAULT 100,
  UNIQUE (tenant_id, code),
  CHECK (applies_to <@ ARRAY['job','position','assignment','person','org_unit','location','requisition']::text[]
         AND array_length(applies_to, 1) >= 1),
  CHECK (required_on <@ applies_to),
  CHECK (source = 'tenant' OR (ref_scheme_code IS NOT NULL AND current_version_id IS NOT NULL)),
  CHECK (source <> 'derived' OR derived_from IS NOT NULL),
  CHECK (values_per_target = 'many' OR NOT shares_total_100),
  CHECK (source = 'tenant' OR values_mode = 'list')
);

-- Values of tenant schemes, effective-dated (§3.3)
CREATE TABLE core.code_value (
  tenant_id       uuid NOT NULL,
  version_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  scheme_id       uuid NOT NULL REFERENCES core.code_scheme,
  code            text NOT NULL,
  parent_code     text,                                -- hierarchical schemes
  title_en        text NOT NULL,
  title_fr        text,
  description_en  text,
  description_fr  text,
  rank            integer,                             -- custom ordering
  attributes      jsonb NOT NULL DEFAULT '{}'::jsonb,  -- e.g. survey level, grade range, vendor job number
  valid_period    daterange NOT NULL,
  sys_period      tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id   uuid NOT NULL,
  EXCLUDE USING gist (scheme_id WITH =, code WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);
CREATE INDEX code_value_lookup ON core.code_value (tenant_id, scheme_id, code) WHERE upper_inf(sys_period);
CREATE INDEX code_value_title_trgm ON core.code_value USING gin (title_en gin_trgm_ops);

-- -------------------------------------------------------------------------------------
-- Codes attached to jobs, positions, incumbents and other targets (§4)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.code_assignment (
  tenant_id       uuid NOT NULL,
  row_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_type     text NOT NULL CHECK (target_type IN ('job','position','assignment','person','org_unit','location','requisition')),
  target_id       uuid NOT NULL,                       -- 'assignment' = the incumbent's assignment to a position
  scheme_id       uuid NOT NULL REFERENCES core.code_scheme,
  ref_version_id  text REFERENCES ref.code_scheme_version,  -- published and derived schemes; null for tenant schemes
  code            text NOT NULL,
  slot            text NOT NULL DEFAULT '',            -- set by the trigger: one value per version, or one row per code
  share           numeric(5,2) CHECK (share > 0 AND share <= 100),
  match_quality   text CHECK (match_quality IN ('exact','close','partial','blended')),
  source          text NOT NULL CHECK (source IN ('manual','suggestion_accepted','import','concordance','derived','override')),
  reason          text,                                -- why an inherited code is overridden
  suggestion_id   uuid,
  evidence        jsonb,                               -- { "method": "title_index", "query": "youth worker", "score": 0.83 }
  unique_code     boolean NOT NULL DEFAULT false,      -- copied from the scheme by the trigger
  valid_period    daterange NOT NULL,
  sys_period      tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id   uuid NOT NULL,
  FOREIGN KEY (ref_version_id, code) REFERENCES ref.code_item (version_id, code),
  EXCLUDE USING gist (target_type WITH =, target_id WITH =, scheme_id WITH =, slot WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period)),
  EXCLUDE USING gist (scheme_id WITH =, code WITH =, valid_period WITH &&)
    WHERE (unique_code AND upper_inf(sys_period))
);
CREATE INDEX code_assignment_target ON core.code_assignment (tenant_id, target_type, target_id) WHERE upper_inf(sys_period);
CREATE INDEX code_assignment_code ON core.code_assignment (tenant_id, scheme_id, ref_version_id, code) WHERE upper_inf(sys_period);

CREATE FUNCTION core.check_code_assignment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  s core.code_scheme;
  v ref.code_scheme_version;
  lvl text;
BEGIN
  SELECT * INTO s FROM core.code_scheme WHERE scheme_id = NEW.scheme_id;
  IF NOT (NEW.target_type = ANY (s.applies_to)) THEN
    RAISE EXCEPTION 'CODE_TARGET_NOT_ALLOWED: scheme % does not apply to %', s.code, NEW.target_type USING ERRCODE = 'check_violation';
  END IF;
  IF s.source IN ('published','derived') THEN
    IF NEW.ref_version_id IS NULL
       OR NOT (NEW.ref_version_id = s.current_version_id OR NEW.ref_version_id = ANY (s.accepted_version_ids)) THEN
      RAISE EXCEPTION 'CODE_VERSION_NOT_ACCEPTED: % is not accepted for scheme %', NEW.ref_version_id, s.code USING ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO v FROM ref.code_scheme_version WHERE version_id = NEW.ref_version_id;
    IF v.status <> 'published' AND v.status <> 'superseded' THEN
      RAISE EXCEPTION 'CODE_VERSION_NOT_PUBLISHED: % is %', v.version_id, v.status USING ERRCODE = 'check_violation';
    END IF;
    SELECT level INTO lvl FROM ref.code_item WHERE version_id = NEW.ref_version_id AND code = NEW.code;
    IF cardinality(v.assignable_levels) > 0 AND NOT (lvl = ANY (v.assignable_levels)) THEN
      RAISE EXCEPTION 'CODE_LEVEL_NOT_ASSIGNABLE: % is a % in %', NEW.code, lvl, v.version_id USING ERRCODE = 'check_violation';
    END IF;
  ELSE
    IF NEW.ref_version_id IS NOT NULL THEN
      RAISE EXCEPTION 'CODE_SCHEME_MISMATCH: tenant scheme % takes no published version', s.code USING ERRCODE = 'check_violation';
    END IF;
    IF s.code_case = 'upper' THEN NEW.code := upper(NEW.code); END IF;
    IF s.code_pattern IS NOT NULL AND NEW.code !~ s.code_pattern THEN
      RAISE EXCEPTION 'CODE_FORMAT: % does not match % for scheme %', NEW.code, s.code_pattern, s.code USING ERRCODE = 'check_violation';
    END IF;
    IF s.values_mode = 'list' AND NOT EXISTS (
         SELECT 1 FROM core.code_value cv
         WHERE cv.scheme_id = s.scheme_id AND cv.code = NEW.code AND upper_inf(cv.sys_period)
           AND cv.valid_period @> lower(NEW.valid_period)) THEN
      RAISE EXCEPTION 'CODE_NOT_IN_LIST: % is not a value of scheme % on %', NEW.code, s.code, lower(NEW.valid_period) USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  NEW.slot := CASE WHEN s.values_per_target = 'one' THEN COALESCE(NEW.ref_version_id, '-')
                   ELSE COALESCE(NEW.ref_version_id, '-') || ':' || NEW.code END;
  NEW.unique_code := (s.uniqueness = 'unique');
  IF NEW.share IS NOT NULL AND s.values_per_target = 'one' AND NEW.share <> 100 THEN
    RAISE EXCEPTION 'CODE_SHARE_NOT_ALLOWED: scheme % holds one value per target', s.code USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER code_assignment_check BEFORE INSERT OR UPDATE OF scheme_id, code, ref_version_id, target_type, valid_period
  ON core.code_assignment FOR EACH ROW EXECUTE FUNCTION core.check_code_assignment();

-- Effective codes for a target on a date, nearest level first: incumbent, then position, then job (§4.4)
CREATE FUNCTION core.resolve_codes(p_target_type text, p_target_id uuid, p_as_of date)
RETURNS TABLE (scheme_id uuid, scheme_code text, ref_version_id text, code text, share numeric,
               origin_type text, origin_id uuid) LANGUAGE sql STABLE AS $$
  WITH chain (lvl, t, id) AS (
    SELECT 1, p_target_type, p_target_id
    UNION ALL
    SELECT 2, 'position', av.position_id
    FROM core.assignment_version av
    WHERE p_target_type = 'assignment' AND av.assignment_id = p_target_id AND av.position_id IS NOT NULL
      AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
    UNION ALL
    SELECT 3, 'job', pv.job_id
    FROM core.assignment_version av
    JOIN core.position_version pv ON pv.position_id = av.position_id AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
    WHERE p_target_type = 'assignment' AND av.assignment_id = p_target_id
      AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
    UNION ALL
    SELECT 2, 'job', pv.job_id
    FROM core.position_version pv
    WHERE p_target_type = 'position' AND pv.position_id = p_target_id
      AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
  ),
  found AS (
    SELECT ca.scheme_id, s.code AS scheme_code, ca.ref_version_id, ca.code, ca.share, ca.target_type, ca.target_id, c.lvl
    FROM chain c
    JOIN core.code_assignment ca ON ca.target_type = c.t AND ca.target_id = c.id
     AND ca.valid_period @> p_as_of AND upper_inf(ca.sys_period)
    JOIN core.code_scheme s ON s.scheme_id = ca.scheme_id
    WHERE c.lvl = 1 OR s.inherit = 'down'
  ),
  nearest AS (
    SELECT scheme_id, COALESCE(ref_version_id, '-') AS v, min(lvl) AS lvl FROM found GROUP BY scheme_id, COALESCE(ref_version_id, '-')
  )
  SELECT f.scheme_id, f.scheme_code, f.ref_version_id, f.code, f.share, f.target_type, f.target_id
  FROM found f JOIN nearest n ON n.scheme_id = f.scheme_id AND n.v = COALESCE(f.ref_version_id, '-') AND n.lvl = f.lvl
  ORDER BY f.scheme_code, f.ref_version_id, f.code
$$;

-- Tenant mappings: internal codes to NOC, job families to survey benchmarks, local recoding choices (§5.1)
CREATE TABLE core.code_mapping (
  tenant_id        uuid NOT NULL,
  mapping_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_scheme_id   uuid NOT NULL REFERENCES core.code_scheme,
  from_version_id  text REFERENCES ref.code_scheme_version,
  from_code        text NOT NULL,
  to_scheme_id     uuid NOT NULL REFERENCES core.code_scheme,
  to_version_id    text REFERENCES ref.code_scheme_version,
  to_code          text NOT NULL,
  relation         text NOT NULL CHECK (relation IN ('one_to_one','split','merge','partial','benchmark')),
  share            numeric(5,4) CHECK (share > 0 AND share <= 1),
  note             text,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  EXCLUDE USING gist (from_scheme_id WITH =, from_code WITH =, to_scheme_id WITH =, to_code WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period))
);

-- Rules that keep schemes consistent with each other (§5.3)
CREATE TABLE core.code_scheme_rule (
  tenant_id        uuid NOT NULL,
  rule_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind             text NOT NULL CHECK (kind IN ('requires','must_map','derive','same_branch')),
  scheme_id        uuid NOT NULL REFERENCES core.code_scheme,   -- the scheme being checked
  other_scheme_id  uuid NOT NULL REFERENCES core.code_scheme,
  params           jsonb NOT NULL DEFAULT '{}'::jsonb,          -- e.g. { "level": "minor_group" } for must_map
  severity         text NOT NULL DEFAULT 'warning' CHECK (severity IN ('warning','block')),
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  CHECK (scheme_id <> other_scheme_id)
);

-- -------------------------------------------------------------------------------------
-- Requirements of jobs and positions (§6)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.work_requirement (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  requirement_id   uuid NOT NULL,                      -- one requirement across its versions
  target_type      text NOT NULL CHECK (target_type IN ('job','position')),
  target_id        uuid NOT NULL,
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('proposed','active')),
  kind             text NOT NULL CHECK (kind IN ('education','training','experience','licence','certification','registration',
                                                 'language','security_screening','driver_licence','physical_demand',
                                                 'working_condition','skill','competency','other')),
  strength         text NOT NULL CHECK (strength IN ('required','preferred','asset')),
  text_en          text NOT NULL,
  text_fr          text,
  criteria         jsonb NOT NULL DEFAULT '{}'::jsonb, -- structured form; its key feeds matching (§6.2)
  match_key        text,                               -- e.g. 'education:college_diploma', 'screening:vulnerable_sector'
  jurisdictions    ref.jurisdiction_code[],            -- null = everywhere
  verification     text NOT NULL DEFAULT 'document'
                   CHECK (verification IN ('self_declared','document','credential_record','background_check','assessment','none')),
  satisfied_by     jsonb NOT NULL DEFAULT '[]'::jsonb, -- [{ "courseCode": "FA-STD" }, { "credential": "RSW-BC" }]
  rationale        text,                               -- why the requirement is a bona fide occupational requirement
  source           text NOT NULL CHECK (source IN ('noc','job','position','agreement','legislation','manual')),
  source_ref       jsonb,                              -- { "versionId": "NOC-2021-1.0", "code": "42201", "seq": 1 }
  display_order    smallint NOT NULL DEFAULT 100,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  EXCLUDE USING gist (requirement_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period)),
  CHECK (status <> 'active' OR strength <> 'required' OR rationale IS NOT NULL),
  CHECK (source <> 'noc' OR source_ref IS NOT NULL)
);
CREATE INDEX work_requirement_target ON core.work_requirement (tenant_id, target_type, target_id) WHERE upper_inf(sys_period);
CREATE INDEX work_requirement_key ON core.work_requirement (tenant_id, match_key) WHERE upper_inf(sys_period) AND status = 'active';

-- A position switching off a requirement it inherits from its job (§6.1)
CREATE TABLE core.work_requirement_suppression (
  tenant_id        uuid NOT NULL,
  suppression_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position_id      uuid NOT NULL REFERENCES core.position,
  requirement_id   uuid NOT NULL,
  reason           text NOT NULL,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  EXCLUDE USING gist (position_id WITH =, requirement_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

-- -------------------------------------------------------------------------------------
-- Suggestions, recoding campaigns and similarity profiles (§2.6, §7, §8)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.code_suggestion (
  tenant_id       uuid NOT NULL,
  suggestion_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type     text NOT NULL,
  target_id       uuid NOT NULL,
  scheme_id       uuid NOT NULL REFERENCES core.code_scheme,
  ref_version_id  text REFERENCES ref.code_scheme_version,
  purpose         text NOT NULL CHECK (purpose IN ('coding','recoding','requirements')),
  method          text NOT NULL CHECK (method IN ('title_index','structure_walk','concordance','duties_text','assistant','tenant_mapping')),
  candidates      jsonb NOT NULL,                      -- [{ "code": "42201", "score": 0.83, "reasons": [{ "code": "TITLE_MATCH", "params": {} }] }]
  status          text NOT NULL DEFAULT 'open' CHECK (status IN ('open','accepted','rejected','superseded','expired')),
  chosen_code     text,
  decided_by      uuid,
  decided_at      timestamptz,
  campaign_id     uuid,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'accepted' OR (chosen_code IS NOT NULL AND decided_by IS NOT NULL AND decided_at IS NOT NULL))
);
CREATE INDEX code_suggestion_open ON core.code_suggestion (tenant_id, campaign_id, status);

CREATE TABLE core.recoding_campaign (
  tenant_id        uuid NOT NULL,
  campaign_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scheme_id        uuid NOT NULL REFERENCES core.code_scheme,
  from_version_id  text NOT NULL REFERENCES ref.code_scheme_version,
  to_version_id    text NOT NULL REFERENCES ref.code_scheme_version,
  effective_from   date NOT NULL,
  status           text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','proposals_ready','in_review','committed','cancelled')),
  counts           jsonb NOT NULL DEFAULT '{}'::jsonb, -- { "oneToOne": 410, "split": 37, "unchanged": 12, "decided": 0 }
  change_set_id    uuid,                               -- the bulk change set, once built
  created_by       uuid NOT NULL,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (from_version_id <> to_version_id)
);

CREATE TABLE core.similarity_profile (
  tenant_id        uuid NOT NULL,
  code             text NOT NULL,                      -- default, redeployment, succession, survey_benchmark, duplicate_jobs
  name_en          text NOT NULL,
  name_fr          text,
  weights          jsonb NOT NULL,                     -- { "occupation": 0.45, "teer": 0.15, "requirements": 0.25, "internal": 0.15, "title": 0 }
  proximity        jsonb NOT NULL,                     -- { "5": 1.0, "4": 0.75, "3": 0.55, "2": 0.40, "1": 0.15, "related": 0.60 }
  internal_schemes jsonb NOT NULL DEFAULT '[]'::jsonb, -- [{ "schemeCode": "JOB_FAMILY", "weight": 1, "kind": "equal" }, { "schemeCode": "GRADE", "kind": "rank" }]
  filters          jsonb NOT NULL DEFAULT '{}'::jsonb, -- { "onlyAvailable": true, "sameLegalEntity": false }
  must_meet_required boolean NOT NULL DEFAULT false,
  PRIMARY KEY (tenant_id, code),
  CHECK (jsonb_typeof(weights) = 'object' AND jsonb_typeof(proximity) = 'object')
);

-- -------------------------------------------------------------------------------------
-- Row-level security on every new tenant table (same policy as 0001 and 0003)
-- -------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS s, c.relname AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND NOT c.relrowsecurity
      AND n.nspname = 'core'
      AND EXISTS (SELECT 1 FROM pg_attribute a
                  WHERE a.attrelid = c.oid AND a.attname = 'tenant_id' AND NOT a.attisdropped)
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$,
                   r.s, r.t);
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT on the new ref tables and functions, and SELECT, INSERT and
-- UPDATE (sys_period only, for corrections) on the new core tables. Only the loader role writes ref.code_*.
