-- =====================================================================================
-- CanDo HRIS — migration 0005: competencies, job evaluation, salary surveys, market
-- pricing, pay structures, survey participation, benefits and practice benchmarking
-- Applies after 0001 to 0004. Specification: docs/19-competencies-job-evaluation-and-
-- total-rewards.md (section numbers below). Conventions as in 0001: tenant_id + RLS on
-- every tenant table, effective-dated rows with valid_period and sys_period where the
-- business needs history, change_set_id on business rows, money numeric(14,2).
-- Survey content is licensed to the tenant: market data, survey job descriptions and
-- pseudonyms carry a second, restrictive policy keyed on the survey's access role (§12).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- Request roles for restrictive policies (§12). The API sets app.roles next to
-- app.tenant_id at the start of each request transaction: a comma-separated list.
-- -------------------------------------------------------------------------------------
CREATE FUNCTION platform.has_role(p_role text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM unnest(string_to_array(coalesce(current_setting('app.roles', true), ''), ',')) AS r(role)
                 WHERE btrim(r.role) = p_role)
$$;

-- -------------------------------------------------------------------------------------
-- Reference data for every tenant (no RLS; written by the loader only)
-- -------------------------------------------------------------------------------------
-- Public wage data by NOC code and geography, e.g. ESDC Job Bank wages (§6.5)
CREATE TABLE ref.public_wage_edition (
  edition_id        text PRIMARY KEY,                    -- 'JOBBANK-2025-11'
  publisher         text NOT NULL,
  name_en           text NOT NULL,
  name_fr           text,
  noc_version_id    text NOT NULL REFERENCES ref.code_scheme_version,
  reference_period  text NOT NULL,                       -- '2023-2024'
  effective_date    date NOT NULL,                       -- middle of the reference period, used for ageing
  released_on       date NOT NULL,
  licence           text NOT NULL,
  source_url        text,
  files             jsonb NOT NULL DEFAULT '[]'::jsonb,  -- [{ "name": "…", "sha256": "…" }]
  status            text NOT NULL CHECK (status IN ('loading','published','superseded','retired'))
);

CREATE TABLE ref.public_wage (
  edition_id     text NOT NULL REFERENCES ref.public_wage_edition,
  noc_version_id text NOT NULL,
  noc_code       text NOT NULL,
  geo_code       text NOT NULL,                          -- Statistics Canada SGC: 'CA', province '59', economic region '5920'
  geo_level      text NOT NULL CHECK (geo_level IN ('national','province','region')),
  geo_name_en    text NOT NULL,
  geo_name_fr    text,
  basis          text NOT NULL CHECK (basis IN ('hourly','annual')),
  low            numeric(14,4),                          -- P10 in most cases
  median         numeric(14,4),
  high           numeric(14,4),                          -- P90 in most cases
  estimation     text NOT NULL DEFAULT 'direct' CHECK (estimation IN ('direct','small_area','other_geography','other_source')),
  data_source    text,                                   -- e.g. 'Labour Force Survey'
  PRIMARY KEY (edition_id, noc_code, geo_code),
  FOREIGN KEY (noc_version_id, noc_code) REFERENCES ref.code_item (version_id, code),
  CHECK (low <= median AND median <= high AND low <= high),
  CHECK (low >= 0 AND median >= 0 AND high >= 0)
);

CREATE FUNCTION ref.guard_public_wage() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text;
BEGIN
  SELECT status INTO st FROM ref.public_wage_edition WHERE edition_id = coalesce(NEW.edition_id, OLD.edition_id);
  IF st IS DISTINCT FROM 'loading' THEN
    RAISE EXCEPTION 'PUBLIC_WAGE_EDITION_IMMUTABLE: % is %', coalesce(NEW.edition_id, OLD.edition_id), st USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER public_wage_immutable BEFORE INSERT OR UPDATE OR DELETE ON ref.public_wage
  FOR EACH ROW EXECUTE FUNCTION ref.guard_public_wage();

-- The practice catalogue (§8.1), loaded from rules/total-rewards/benefit-practices.json
CREATE TABLE ref.reward_practice (
  practice_code     text PRIMARY KEY,
  catalogue_version text NOT NULL,
  category          text NOT NULL,
  name_en           text NOT NULL,
  name_fr           text NOT NULL,
  value_type        text NOT NULL CHECK (value_type IN ('boolean','money','multiple_of_salary','percent','days','weeks','months','count','enum','text')),
  unit              text,
  richer_when       text NOT NULL CHECK (richer_when IN ('higher','lower','yes','none')),
  enum_values       text[],                              -- leanest to richest when richer_when = 'higher'
  own_value_source  jsonb NOT NULL,
  display_order     smallint NOT NULL DEFAULT 100,
  CHECK (value_type <> 'enum' OR coalesce(cardinality(enum_values), 0) >= 2)
);

-- =====================================================================================
-- TALENT — competency frameworks, targets, assessments (§4)
-- =====================================================================================
CREATE TABLE talent.competency_framework (
  tenant_id     uuid NOT NULL,
  framework_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL,                           -- 'UCM'
  name_en       text NOT NULL,
  name_fr       text,
  description_en text,
  description_fr text,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code)
);

CREATE TABLE talent.competency_framework_version (
  tenant_id            uuid NOT NULL,
  framework_version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  framework_id         uuid NOT NULL REFERENCES talent.competency_framework,
  label                text NOT NULL,                    -- '1.0'
  status               text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  scale                jsonb NOT NULL,                   -- [{ "level": 1, "code": "FOUNDATIONAL", "name_en": …, "descriptor_en": … }, …]
  max_level            smallint GENERATED ALWAYS AS (jsonb_array_length(scale)) STORED,
  domains              jsonb NOT NULL DEFAULT '[]'::jsonb,
  source               text,
  published_at         timestamptz,
  published_by         uuid,
  UNIQUE (framework_id, label),
  CHECK (jsonb_typeof(scale) = 'array' AND jsonb_array_length(scale) BETWEEN 2 AND 9)
);

CREATE TABLE talent.competency (
  tenant_id            uuid NOT NULL,
  competency_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  framework_version_id uuid NOT NULL REFERENCES talent.competency_framework_version,
  code                 text NOT NULL,                    -- stable across versions: same code, same competency
  domain_code          text NOT NULL,
  name_en              text NOT NULL,
  name_fr              text,
  definition_en        text NOT NULL,
  definition_fr        text,
  indicators_status    text NOT NULL DEFAULT 'as_provided' CHECK (indicators_status IN ('as_provided','proposed','reviewed')),
  original_examples    jsonb,
  display_order        smallint NOT NULL DEFAULT 100,
  UNIQUE (framework_version_id, code)
);

CREATE TABLE talent.competency_indicator (
  tenant_id      uuid NOT NULL,
  indicator_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  competency_id  uuid NOT NULL REFERENCES talent.competency,
  level          smallint NOT NULL CHECK (level >= 1),
  seq            smallint NOT NULL,
  text_en        text NOT NULL,
  text_fr        text,
  UNIQUE (competency_id, level, seq)
);

-- Content of a published version cannot change (§4.1)
CREATE FUNCTION talent.guard_framework_content() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_max smallint; v_version uuid;
BEGIN
  IF TG_TABLE_NAME = 'competency' THEN
    v_version := coalesce(NEW.framework_version_id, OLD.framework_version_id);
  ELSE
    SELECT c.framework_version_id INTO v_version FROM talent.competency c WHERE c.competency_id = coalesce(NEW.competency_id, OLD.competency_id);
  END IF;
  SELECT status, max_level INTO v_status, v_max FROM talent.competency_framework_version WHERE framework_version_id = v_version;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'FRAMEWORK_VERSION_IMMUTABLE: version is %, create a new version instead', v_status USING ERRCODE = 'check_violation';
  END IF;
  IF TG_TABLE_NAME = 'competency_indicator' AND TG_OP <> 'DELETE' THEN
    IF NEW.level > v_max THEN
      RAISE EXCEPTION 'LEVEL_OUTSIDE_SCALE: level % on a % level scale', NEW.level, v_max USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER competency_content_guard BEFORE INSERT OR UPDATE OR DELETE ON talent.competency
  FOR EACH ROW EXECUTE FUNCTION talent.guard_framework_content();
CREATE TRIGGER competency_indicator_content_guard BEFORE INSERT OR UPDATE OR DELETE ON talent.competency_indicator
  FOR EACH ROW EXECUTE FUNCTION talent.guard_framework_content();

-- Status moves forward; publishing checks completeness (§4.1, §4.2)
CREATE FUNCTION talent.guard_framework_version() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ord text[] := ARRAY['draft','published','retired']; bad text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN RAISE EXCEPTION 'FRAMEWORK_VERSION_IMMUTABLE: only drafts can be deleted' USING ERRCODE = 'check_violation'; END IF;
    RETURN OLD;
  END IF;
  IF array_position(ord, NEW.status) < array_position(ord, OLD.status) THEN
    RAISE EXCEPTION 'FRAMEWORK_VERSION_STATUS_BACKWARDS: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status <> 'draft' AND (NEW.scale, NEW.domains, NEW.label, NEW.framework_id) IS DISTINCT FROM (OLD.scale, OLD.domains, OLD.label, OLD.framework_id) THEN
    RAISE EXCEPTION 'FRAMEWORK_VERSION_IMMUTABLE: version is %', OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'draft' AND NEW.status = 'published' THEN
    SELECT string_agg(code, ', ') INTO bad FROM talent.competency
      WHERE framework_version_id = NEW.framework_version_id AND indicators_status = 'proposed';
    IF bad IS NOT NULL THEN
      RAISE EXCEPTION 'FRAMEWORK_INDICATORS_PROPOSED: review indicators of % before publishing', bad USING ERRCODE = 'check_violation';
    END IF;
    SELECT string_agg(c.code || ' L' || l.level, ', ') INTO bad
      FROM talent.competency c CROSS JOIN generate_series(1, NEW.max_level) AS l(level)
      WHERE c.framework_version_id = NEW.framework_version_id
        AND NOT EXISTS (SELECT 1 FROM talent.competency_indicator i WHERE i.competency_id = c.competency_id AND i.level = l.level);
    IF bad IS NOT NULL THEN
      RAISE EXCEPTION 'FRAMEWORK_LEVELS_INCOMPLETE: no indicator for %', bad USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM talent.competency WHERE framework_version_id = NEW.framework_version_id) THEN
      RAISE EXCEPTION 'FRAMEWORK_EMPTY' USING ERRCODE = 'check_violation';
    END IF;
    NEW.published_at := coalesce(NEW.published_at, now());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER framework_version_guard BEFORE UPDATE OR DELETE ON talent.competency_framework_version
  FOR EACH ROW EXECUTE FUNCTION talent.guard_framework_version();

-- Target levels on jobs and positions, effective-dated (§4.3)
CREATE TABLE talent.competency_target (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_id        uuid NOT NULL,                        -- one target across its versions
  target_type      text NOT NULL CHECK (target_type IN ('job','position')),
  target_ref       uuid NOT NULL,                        -- job_id or position_id
  competency_id    uuid NOT NULL REFERENCES talent.competency,
  framework_id     uuid NOT NULL,                        -- set by the trigger
  competency_code  text NOT NULL,                        -- set by the trigger
  status           text NOT NULL DEFAULT 'active' CHECK (status IN ('proposed','active')),
  required_level   smallint NOT NULL CHECK (required_level >= 1),
  entry_level      smallint CHECK (entry_level >= 1),
  criticality      text NOT NULL DEFAULT 'important' CHECK (criticality IN ('critical','important','useful')),
  source           text NOT NULL CHECK (source IN ('career_level_default','job','position','manual','assistant')),
  reason           text,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  CHECK (entry_level IS NULL OR entry_level <= required_level),
  EXCLUDE USING gist (target_type WITH =, target_ref WITH =, framework_id WITH =, competency_code WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period) AND status = 'active')
);
CREATE INDEX competency_target_ref ON talent.competency_target (tenant_id, target_type, target_ref) WHERE upper_inf(sys_period);

CREATE FUNCTION talent.check_competency_target() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_max smallint; v_job uuid;
BEGIN
  SELECT fv.status, fv.max_level, fv.framework_id, c.code INTO v_status, v_max, NEW.framework_id, NEW.competency_code
    FROM talent.competency c JOIN talent.competency_framework_version fv USING (framework_version_id)
    WHERE c.competency_id = NEW.competency_id;
  IF v_status <> 'published' THEN
    RAISE EXCEPTION 'TARGET_FRAMEWORK_NOT_PUBLISHED: framework version is %', v_status USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.required_level > v_max OR NEW.entry_level > v_max THEN
    RAISE EXCEPTION 'LEVEL_OUTSIDE_SCALE: level above % on this scale', v_max USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.target_type = 'position' AND NEW.status = 'active' AND upper_inf(NEW.sys_period) AND NEW.reason IS NULL THEN
    SELECT pv.job_id INTO v_job FROM core.position_version pv
      WHERE pv.position_id = NEW.target_ref AND pv.valid_period @> lower(NEW.valid_period) AND upper_inf(pv.sys_period);
    IF EXISTS (SELECT 1 FROM talent.competency_target t
               WHERE t.target_type = 'job' AND t.target_ref = v_job AND t.framework_id = NEW.framework_id
                 AND t.competency_code = NEW.competency_code AND t.status = 'active' AND upper_inf(t.sys_period)
                 AND t.valid_period && NEW.valid_period) THEN
      RAISE EXCEPTION 'OVERRIDE_NEEDS_REASON: the position overrides its job''s % target', NEW.competency_code USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER competency_target_check BEFORE INSERT OR UPDATE ON talent.competency_target
  FOR EACH ROW EXECUTE FUNCTION talent.check_competency_target();

-- Assessments of people (§4.5)
CREATE TABLE talent.competency_assessment (
  tenant_id          uuid NOT NULL,
  assessment_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id          uuid NOT NULL REFERENCES core.person,
  competency_id      uuid NOT NULL REFERENCES talent.competency,
  framework_id       uuid NOT NULL,                      -- set by the trigger
  competency_code    text NOT NULL,                      -- set by the trigger
  assessed_level     smallint NOT NULL CHECK (assessed_level >= 1),
  source             text NOT NULL CHECK (source IN ('self','manager','peer_360','assessment','evidence','calibrated')),
  context            text NOT NULL CHECK (context IN ('performance_review','development','promotion','succession','selection','probation','other')),
  assessed_on        date NOT NULL,
  assessor_person_id uuid REFERENCES core.person,
  review_id          uuid REFERENCES talent.review,
  evidence           jsonb NOT NULL DEFAULT '[]'::jsonb,
  comment            text,
  status             text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','final','superseded')),
  supersedes_assessment_id uuid REFERENCES talent.competency_assessment,
  finalized_at       timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  change_set_id      uuid,
  CHECK (source <> 'self' OR assessor_person_id IS NULL OR assessor_person_id = person_id),
  CHECK (status = 'draft' OR finalized_at IS NOT NULL)
);
CREATE INDEX competency_assessment_person ON talent.competency_assessment (tenant_id, person_id, framework_id, competency_code, assessed_on DESC)
  WHERE status = 'final';

CREATE FUNCTION talent.guard_competency_assessment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_max smallint;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN RAISE EXCEPTION 'ASSESSMENT_IMMUTABLE' USING ERRCODE = 'check_violation'; END IF;
    RETURN OLD;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status <> 'draft' THEN
    IF NOT (OLD.status = 'final' AND NEW.status = 'superseded'
            AND (to_jsonb(NEW) - 'status') = (to_jsonb(OLD) - 'status')) THEN
      RAISE EXCEPTION 'ASSESSMENT_IMMUTABLE: a final assessment is corrected by a new one' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  SELECT fv.max_level, fv.framework_id, c.code INTO v_max, NEW.framework_id, NEW.competency_code
    FROM talent.competency c JOIN talent.competency_framework_version fv USING (framework_version_id)
    WHERE c.competency_id = NEW.competency_id;
  IF NEW.assessed_level > v_max THEN
    RAISE EXCEPTION 'LEVEL_OUTSIDE_SCALE: level % on a % level scale', NEW.assessed_level, v_max USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'final' AND (TG_OP = 'INSERT' OR OLD.status = 'draft') THEN
    NEW.finalized_at := coalesce(NEW.finalized_at, now());
    IF NEW.supersedes_assessment_id IS NOT NULL THEN
      UPDATE talent.competency_assessment SET status = 'superseded'
        WHERE assessment_id = NEW.supersedes_assessment_id AND status = 'final';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER competency_assessment_guard BEFORE INSERT OR UPDATE OR DELETE ON talent.competency_assessment
  FOR EACH ROW EXECUTE FUNCTION talent.guard_competency_assessment();

-- Gaps for an assignment on a date (§4.6): the position's targets replace the job's for the same competency;
-- the latest final assessment from the accepted sources is used, and the latest self-assessment is shown beside it.
CREATE FUNCTION talent.competency_gap(p_assignment uuid, p_as_of date,
                                      p_sources text[] DEFAULT ARRAY['calibrated','assessment','manager','peer_360','evidence'])
RETURNS TABLE (framework_id uuid, competency_code text, required_level smallint, entry_level smallint, criticality text,
               target_from text, assessed_level smallint, assessed_on date, assessment_source text, self_level smallint, gap smallint)
LANGUAGE sql STABLE AS $$
  WITH a AS (
    SELECT av.position_id, e.person_id, pv.job_id
    FROM core.assignment_version av
    JOIN core.assignment asg ON asg.assignment_id = av.assignment_id
    JOIN core.employment e ON e.employment_id = asg.employment_id
    LEFT JOIN core.position_version pv ON pv.position_id = av.position_id AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
    WHERE av.assignment_id = p_assignment AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
  ), targets AS (
    SELECT DISTINCT ON (t.framework_id, t.competency_code)
           t.framework_id, t.competency_code, t.required_level, t.entry_level, t.criticality, t.target_type
    FROM talent.competency_target t, a
    WHERE t.status = 'active' AND upper_inf(t.sys_period) AND t.valid_period @> p_as_of
      AND ((t.target_type = 'position' AND t.target_ref = a.position_id) OR (t.target_type = 'job' AND t.target_ref = a.job_id))
    ORDER BY t.framework_id, t.competency_code, (t.target_type = 'position') DESC
  )
  SELECT tg.framework_id, tg.competency_code, tg.required_level, tg.entry_level, tg.criticality, tg.target_type,
         asm.assessed_level, asm.assessed_on, asm.source, slf.assessed_level,
         CASE WHEN asm.assessed_level IS NULL THEN NULL ELSE (tg.required_level - asm.assessed_level)::smallint END
  FROM targets tg CROSS JOIN a
  LEFT JOIN LATERAL (
    SELECT x.assessed_level, x.assessed_on, x.source FROM talent.competency_assessment x
    WHERE x.person_id = a.person_id AND x.framework_id = tg.framework_id AND x.competency_code = tg.competency_code
      AND x.status = 'final' AND x.source = ANY (p_sources) AND x.assessed_on <= p_as_of
    ORDER BY x.assessed_on DESC, (x.source = 'calibrated') DESC, x.created_at DESC LIMIT 1) asm ON true
  LEFT JOIN LATERAL (
    SELECT x.assessed_level FROM talent.competency_assessment x
    WHERE x.person_id = a.person_id AND x.framework_id = tg.framework_id AND x.competency_code = tg.competency_code
      AND x.status = 'final' AND x.source = 'self' AND x.assessed_on <= p_as_of
    ORDER BY x.assessed_on DESC, x.created_at DESC LIMIT 1) slf ON true
  ORDER BY tg.framework_id, tg.competency_code
$$;

-- =====================================================================================
-- COMP — job evaluation (§5)
-- =====================================================================================
CREATE TABLE comp.je_plan (
  tenant_id  uuid NOT NULL,
  plan_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL,
  name_en    text NOT NULL,
  name_fr    text,
  method     text NOT NULL DEFAULT 'point_factor' CHECK (method IN ('point_factor','classification','ranking','market_slotting')),
  purposes   text[] NOT NULL DEFAULT ARRAY['grading']::text[],
  status     text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CHECK (purposes <@ ARRAY['grading','pay_equity']::text[] AND cardinality(purposes) >= 1),
  CHECK (method = 'point_factor' OR NOT ('pay_equity' = ANY (purposes)))
);

CREATE TABLE comp.je_plan_version (
  tenant_id        uuid NOT NULL,
  plan_version_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id          uuid NOT NULL REFERENCES comp.je_plan,
  label            text NOT NULL,
  status           text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  max_points       integer NOT NULL CHECK (max_points > 0),
  grade_bands      jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{ "grade": "G01", "min": 180, "max": 249 }, …]
  gender_neutral_review jsonb,                           -- { "reviewedOn": "2026-11-02", "reviewedBy": ["…"], "findings": "…" }
  source           text NOT NULL DEFAULT 'tenant' CHECK (source IN ('cando_sample','tenant')),
  published_at     timestamptz,
  published_by     uuid,
  UNIQUE (plan_id, label),
  CHECK (jsonb_typeof(grade_bands) = 'array')
);

CREATE TABLE comp.je_factor (
  tenant_id        uuid NOT NULL,
  factor_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_version_id  uuid NOT NULL REFERENCES comp.je_plan_version,
  code             text NOT NULL,
  factor_group     text NOT NULL CHECK (factor_group IN ('skill','effort','responsibility','working_conditions')),
  name_en          text NOT NULL,
  name_fr          text,
  definition_en    text NOT NULL,
  definition_fr    text,
  max_points       integer NOT NULL CHECK (max_points > 0),
  display_order    smallint NOT NULL DEFAULT 100,
  UNIQUE (plan_version_id, code)
);

CREATE TABLE comp.je_degree (
  tenant_id      uuid NOT NULL,
  factor_id      uuid NOT NULL REFERENCES comp.je_factor,
  degree         smallint NOT NULL CHECK (degree >= 1),
  points         integer NOT NULL CHECK (points >= 0),
  descriptor_en  text NOT NULL,
  descriptor_fr  text,
  PRIMARY KEY (factor_id, degree)
);

-- Evidence shown beside a factor, and the degree range it suggests (§5.5)
CREATE TABLE comp.je_evidence_link (
  tenant_id         uuid NOT NULL,
  link_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  factor_id         uuid NOT NULL REFERENCES comp.je_factor,
  source            text NOT NULL CHECK (source IN ('noc_teer','career_level','competency_targets','work_requirements','position_tree')),
  framework_code    text,                                -- for competency_targets
  competency_codes  text[],
  requirement_kinds text[],
  combine           text NOT NULL DEFAULT 'max' CHECK (combine IN ('max','min')),
  suggest           jsonb,                               -- { "3": [2, 4], "none": [1, 2] } evidence value → [lowest, highest] degree
  note_en           text,
  CHECK (source <> 'competency_targets' OR coalesce(cardinality(competency_codes), 0) >= 1)
);

CREATE FUNCTION comp.guard_je_plan_content() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_version uuid; v_status text;
BEGIN
  IF TG_TABLE_NAME = 'je_factor' THEN
    v_version := coalesce(NEW.plan_version_id, OLD.plan_version_id);
  ELSE
    SELECT f.plan_version_id INTO v_version FROM comp.je_factor f WHERE f.factor_id = coalesce(NEW.factor_id, OLD.factor_id);
  END IF;
  SELECT status INTO v_status FROM comp.je_plan_version WHERE plan_version_id = v_version;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'JE_PLAN_VERSION_IMMUTABLE: version is %, create a new version instead', v_status USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER je_factor_guard BEFORE INSERT OR UPDATE OR DELETE ON comp.je_factor
  FOR EACH ROW EXECUTE FUNCTION comp.guard_je_plan_content();
CREATE TRIGGER je_degree_guard BEFORE INSERT OR UPDATE OR DELETE ON comp.je_degree
  FOR EACH ROW EXECUTE FUNCTION comp.guard_je_plan_content();
CREATE TRIGGER je_evidence_link_guard BEFORE INSERT OR UPDATE OR DELETE ON comp.je_evidence_link
  FOR EACH ROW EXECUTE FUNCTION comp.guard_je_plan_content();

-- Publishing validates the plan (§5.1)
CREATE FUNCTION comp.guard_je_plan_version() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ord text[] := ARRAY['draft','published','retired']; bad text; v_sum integer; v_purposes text[]; prev_max integer := NULL; b jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN RAISE EXCEPTION 'JE_PLAN_VERSION_IMMUTABLE: only drafts can be deleted' USING ERRCODE = 'check_violation'; END IF;
    RETURN OLD;
  END IF;
  IF array_position(ord, NEW.status) < array_position(ord, OLD.status) THEN
    RAISE EXCEPTION 'JE_PLAN_STATUS_BACKWARDS: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status <> 'draft' AND (NEW.max_points, NEW.grade_bands, NEW.gender_neutral_review, NEW.label, NEW.plan_id)
       IS DISTINCT FROM (OLD.max_points, OLD.grade_bands, OLD.gender_neutral_review, OLD.label, OLD.plan_id) THEN
    RAISE EXCEPTION 'JE_PLAN_VERSION_IMMUTABLE: version is %', OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'draft' AND NEW.status = 'published' THEN
    -- degrees numbered 1..n, points rising, top degree = factor maximum
    SELECT string_agg(f.code, ', ') INTO bad FROM comp.je_factor f
      WHERE f.plan_version_id = NEW.plan_version_id
        AND NOT EXISTS (
          SELECT 1 FROM (SELECT count(*) AS n, min(degree) AS lo, max(degree) AS hi,
                                bool_and(points > coalesce(prev, -1)) AS rising,
                                max(points) FILTER (WHERE last) AS top
                         FROM (SELECT d.degree, d.points, lag(d.points) OVER (ORDER BY d.degree) AS prev,
                                      d.degree = max(d.degree) OVER () AS last
                               FROM comp.je_degree d WHERE d.factor_id = f.factor_id) s) z
          WHERE z.n >= 2 AND z.lo = 1 AND z.hi = z.n AND z.rising AND z.top = f.max_points);
    IF bad IS NOT NULL THEN
      RAISE EXCEPTION 'JE_PLAN_DEGREES_INVALID: %', bad USING ERRCODE = 'check_violation';
    END IF;
    SELECT sum(max_points) INTO v_sum FROM comp.je_factor WHERE plan_version_id = NEW.plan_version_id;
    IF v_sum IS DISTINCT FROM NEW.max_points THEN
      RAISE EXCEPTION 'JE_PLAN_POINTS_MISMATCH: factors total %, plan maximum %', v_sum, NEW.max_points USING ERRCODE = 'check_violation';
    END IF;
    SELECT purposes INTO v_purposes FROM comp.je_plan WHERE plan_id = NEW.plan_id;
    IF 'pay_equity' = ANY (v_purposes) THEN
      SELECT string_agg(g, ', ') INTO bad FROM unnest(ARRAY['skill','effort','responsibility','working_conditions']) AS g
        WHERE NOT EXISTS (SELECT 1 FROM comp.je_factor f WHERE f.plan_version_id = NEW.plan_version_id AND f.factor_group = g);
      IF bad IS NOT NULL THEN
        RAISE EXCEPTION 'JE_PLAN_GROUP_MISSING: %', bad USING ERRCODE = 'check_violation';
      END IF;
      IF NEW.gender_neutral_review IS NULL OR NOT (NEW.gender_neutral_review ? 'reviewedOn' AND NEW.gender_neutral_review ? 'reviewedBy') THEN
        RAISE EXCEPTION 'JE_PLAN_REVIEW_MISSING: record the gender-neutral review before publishing' USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    IF jsonb_array_length(NEW.grade_bands) = 0 THEN
      RAISE EXCEPTION 'JE_PLAN_BANDS_INVALID: no grade bands' USING ERRCODE = 'check_violation';
    END IF;
    FOR b IN SELECT x FROM jsonb_array_elements(NEW.grade_bands) x ORDER BY (x->>'min')::int LOOP
      IF (b->>'min')::int > (b->>'max')::int OR (prev_max IS NOT NULL AND (b->>'min')::int <= prev_max) THEN
        RAISE EXCEPTION 'JE_PLAN_BANDS_INVALID: band % overlaps or is reversed', b->>'grade' USING ERRCODE = 'check_violation';
      END IF;
      prev_max := (b->>'max')::int;
    END LOOP;
    NEW.published_at := coalesce(NEW.published_at, now());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER je_plan_version_guard BEFORE UPDATE OR DELETE ON comp.je_plan_version
  FOR EACH ROW EXECUTE FUNCTION comp.guard_je_plan_version();

-- Evaluations and ratings (§5.4)
CREATE TABLE comp.job_evaluation (
  tenant_id          uuid NOT NULL,
  evaluation_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_version_id    uuid NOT NULL REFERENCES comp.je_plan_version,
  plan_id            uuid NOT NULL,                      -- set by the trigger
  job_id             uuid NOT NULL REFERENCES core.job,
  position_id        uuid REFERENCES core.position,      -- set for a position-specific evaluation
  job_description_ref jsonb,                             -- { "documentId": "…", "version": 3 }
  status             text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','in_review','approved','superseded','withdrawn')),
  total_points       integer,                            -- computed on approval
  grade              text,                               -- from the plan version's bands, on approval
  effective_from     date NOT NULL,
  evaluator_ids      uuid[] NOT NULL DEFAULT '{}',
  committee          jsonb NOT NULL DEFAULT '[]'::jsonb, -- [{ "personId": "…", "role": "employer" | "employee" | "chair" }]
  rationale          text,
  supersedes_evaluation_id uuid REFERENCES comp.job_evaluation,
  approved_by        uuid,
  approved_at        timestamptz,
  review_flag        text,                               -- set when the job changes after approval (§5.6)
  change_set_id      uuid,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (status NOT IN ('approved','superseded') OR (total_points IS NOT NULL AND approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE UNIQUE INDEX job_evaluation_one_approved ON comp.job_evaluation
  (plan_id, job_id, coalesce(position_id, '00000000-0000-0000-0000-000000000000'::uuid)) WHERE status = 'approved';

CREATE TABLE comp.job_evaluation_rating (
  tenant_id       uuid NOT NULL,
  evaluation_id   uuid NOT NULL REFERENCES comp.job_evaluation,
  factor_id       uuid NOT NULL REFERENCES comp.je_factor,
  degree          smallint NOT NULL,
  points          integer NOT NULL,                      -- set by the trigger from comp.je_degree
  rationale       text NOT NULL CHECK (length(btrim(rationale)) > 0),
  evidence        jsonb NOT NULL DEFAULT '{}'::jsonb,
  suggested_low   smallint,
  suggested_high  smallint,
  outside_reason  text,
  PRIMARY KEY (evaluation_id, factor_id),
  CONSTRAINT outside_suggestion_needs_reason
    CHECK (suggested_low IS NULL OR suggested_high IS NULL OR degree BETWEEN suggested_low AND suggested_high OR outside_reason IS NOT NULL)
);

CREATE FUNCTION comp.check_job_evaluation_rating() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_version uuid;
BEGIN
  SELECT status, plan_version_id INTO v_status, v_version FROM comp.job_evaluation
    WHERE evaluation_id = coalesce(NEW.evaluation_id, OLD.evaluation_id);
  IF v_status NOT IN ('draft','in_review') THEN
    RAISE EXCEPTION 'EVALUATION_IMMUTABLE: evaluation is %', v_status USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF NOT EXISTS (SELECT 1 FROM comp.je_factor WHERE factor_id = NEW.factor_id AND plan_version_id = v_version) THEN
    RAISE EXCEPTION 'RATING_FACTOR_NOT_IN_PLAN' USING ERRCODE = 'check_violation';
  END IF;
  SELECT points INTO NEW.points FROM comp.je_degree WHERE factor_id = NEW.factor_id AND degree = NEW.degree;
  IF NEW.points IS NULL THEN
    RAISE EXCEPTION 'DEGREE_NOT_IN_FACTOR: degree %', NEW.degree USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER job_evaluation_rating_check BEFORE INSERT OR UPDATE OR DELETE ON comp.job_evaluation_rating
  FOR EACH ROW EXECUTE FUNCTION comp.check_job_evaluation_rating();

CREATE FUNCTION comp.guard_job_evaluation() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_plan_status text; v_bands jsonb; missing text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status NOT IN ('draft','withdrawn') THEN RAISE EXCEPTION 'EVALUATION_IMMUTABLE' USING ERRCODE = 'check_violation'; END IF;
    RETURN OLD;
  END IF;
  SELECT plan_id, status, grade_bands INTO NEW.plan_id, v_plan_status, v_bands
    FROM comp.je_plan_version WHERE plan_version_id = NEW.plan_version_id;
  IF TG_OP = 'INSERT' AND NEW.status NOT IN ('draft','in_review') THEN
    RAISE EXCEPTION 'EVALUATION_STARTS_AS_DRAFT' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IN ('approved','superseded','withdrawn') THEN
    IF NOT ((OLD.status = 'approved' AND NEW.status IN ('approved','superseded'))
            AND (to_jsonb(NEW) - ARRAY['status','review_flag']) = (to_jsonb(OLD) - ARRAY['status','review_flag'])) THEN
      RAISE EXCEPTION 'EVALUATION_IMMUTABLE: evaluation is %', OLD.status USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.status = 'approved' THEN
    IF v_plan_status <> 'published' THEN
      RAISE EXCEPTION 'JE_PLAN_NOT_PUBLISHED' USING ERRCODE = 'check_violation';
    END IF;
    SELECT string_agg(f.code, ', ' ORDER BY f.display_order, f.code) INTO missing FROM comp.je_factor f
      WHERE f.plan_version_id = NEW.plan_version_id
        AND NOT EXISTS (SELECT 1 FROM comp.job_evaluation_rating r WHERE r.evaluation_id = NEW.evaluation_id AND r.factor_id = f.factor_id);
    IF missing IS NOT NULL THEN
      RAISE EXCEPTION 'EVALUATION_INCOMPLETE: no rating for %', missing USING ERRCODE = 'check_violation';
    END IF;
    SELECT sum(points) INTO NEW.total_points FROM comp.job_evaluation_rating WHERE evaluation_id = NEW.evaluation_id;
    SELECT x->>'grade' INTO NEW.grade FROM jsonb_array_elements(v_bands) x
      WHERE NEW.total_points BETWEEN (x->>'min')::int AND (x->>'max')::int;
    NEW.approved_at := coalesce(NEW.approved_at, now());
    IF NEW.supersedes_evaluation_id IS NOT NULL THEN
      UPDATE comp.job_evaluation SET status = 'superseded'
        WHERE evaluation_id = NEW.supersedes_evaluation_id AND status = 'approved'
          AND plan_id = NEW.plan_id AND job_id = NEW.job_id AND position_id IS NOT DISTINCT FROM NEW.position_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'SUPERSEDED_EVALUATION_NOT_FOUND' USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER job_evaluation_guard BEFORE INSERT OR UPDATE OR DELETE ON comp.job_evaluation
  FOR EACH ROW EXECUTE FUNCTION comp.guard_job_evaluation();

-- =====================================================================================
-- COMP — salary surveys (§6)
-- =====================================================================================
CREATE TABLE comp.survey (
  tenant_id     uuid NOT NULL,
  survey_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL,
  name          text NOT NULL,
  publisher     text NOT NULL,
  scheme_id     uuid NOT NULL UNIQUE REFERENCES core.code_scheme,   -- holds the survey's job catalogue (docs/18 §3)
  licence       jsonb NOT NULL DEFAULT '{}'::jsonb,  -- { "licensee": …, "allowedUses": [...], "employeesMaySee": false, "expiresOn": "…", "deleteOnExpiry": true }
  access_role   text NOT NULL,                       -- default 'survey_data:<code>', set by the trigger
  derived_results_restricted boolean NOT NULL DEFAULT false,
  duties_match_threshold numeric(5,2) NOT NULL DEFAULT 70 CHECK (duties_match_threshold BETWEEN 0 AND 100),
  participates  boolean NOT NULL DEFAULT false,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','expired','retired')),
  UNIQUE (tenant_id, code)
);

CREATE FUNCTION comp.check_survey() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.access_role := coalesce(NEW.access_role, 'survey_data:' || NEW.code);
  IF NOT EXISTS (SELECT 1 FROM core.code_scheme WHERE scheme_id = NEW.scheme_id AND purpose = 'salary_survey' AND source = 'tenant') THEN
    RAISE EXCEPTION 'SURVEY_SCHEME_PURPOSE: the scheme must be a tenant scheme with purpose salary_survey' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER survey_check BEFORE INSERT OR UPDATE OF scheme_id, access_role, code ON comp.survey
  FOR EACH ROW EXECUTE FUNCTION comp.check_survey();

-- Visible when the request holds the survey's access role (§12)
CREATE FUNCTION comp.survey_visible(p_survey uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM comp.survey s WHERE s.survey_id = p_survey AND platform.has_role(s.access_role))
$$;

CREATE TABLE comp.survey_edition (
  tenant_id       uuid NOT NULL,
  edition_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id       uuid NOT NULL REFERENCES comp.survey,
  label           text NOT NULL,                         -- '2025'
  effective_date  date NOT NULL,
  published_on    date,
  currency        char(3) NOT NULL DEFAULT 'CAD',
  participants    integer CHECK (participants >= 0),
  hours_basis     numeric(7,2) CHECK (hours_basis > 0),  -- annual hours used by the publisher
  masking         jsonb NOT NULL DEFAULT '{}'::jsonb,    -- as published, e.g. { "p50": { "nOrgs": 4 } }
  weightings      text[] NOT NULL DEFAULT ARRAY['organization']::text[],
  files           jsonb NOT NULL DEFAULT '[]'::jsonb,    -- [{ "name": "…", "sha256": "…", "profile": "wide_stats" }]
  status          text NOT NULL DEFAULT 'loading' CHECK (status IN ('loading','published','retired')),
  published_at    timestamptz,
  UNIQUE (survey_id, label),
  CHECK (weightings <@ ARRAY['organization','incumbent','single']::text[])
);

CREATE TABLE comp.survey_cut (
  tenant_id    uuid NOT NULL,
  cut_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  edition_id   uuid NOT NULL REFERENCES comp.survey_edition,
  cut_code     text NOT NULL,                            -- as in the file; 'ALL' for all participants
  dimension    text NOT NULL CHECK (dimension IN ('all','region','size_fte','size_budget','size_revenue','complexity','sector','focus','industry','ownership','other')),
  label_en     text NOT NULL,
  label_fr     text,
  criteria     jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (edition_id, cut_code)
);

CREATE TABLE comp.market_data (
  tenant_id      uuid NOT NULL,
  row_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  edition_id     uuid NOT NULL REFERENCES comp.survey_edition,
  survey_id      uuid NOT NULL,                          -- set by the trigger; keys the licence policy
  job_code       text NOT NULL,
  cut_id         uuid NOT NULL REFERENCES comp.survey_cut,
  weighting      text NOT NULL CHECK (weighting IN ('organization','incumbent','single')),
  element        text NOT NULL CHECK (element IN ('base_salary','hourly_rate','range_min','range_mid','range_max','sti_target_pct',
                                                  'sti_actual','sti_actual_pct','sti_eligible','allowances','total_cash','total_direct')),
  n_orgs         integer NOT NULL CHECK (n_orgs >= 0),
  n_incumbents   integer CHECK (n_incumbents >= 0),
  mean           numeric(14,4),
  p10            numeric(14,4),
  p25            numeric(14,4),
  p50            numeric(14,4),
  p75            numeric(14,4),
  p90            numeric(14,4),
  prevalence_pct numeric(5,2) CHECK (prevalence_pct BETWEEN 0 AND 100),
  masked_fields  text[] NOT NULL DEFAULT '{}',           -- statistics the publisher masked
  UNIQUE (edition_id, job_code, cut_id, weighting, element),
  -- a comparison with a null passes, so only published values are checked
  CONSTRAINT percentiles_ordered CHECK (p10 <= p25 AND p10 <= p50 AND p10 <= p75 AND p10 <= p90
                                       AND p25 <= p50 AND p25 <= p75 AND p25 <= p90
                                       AND p50 <= p75 AND p50 <= p90 AND p75 <= p90),
  CONSTRAINT values_not_negative CHECK (mean >= 0 AND p10 >= 0 AND p25 >= 0 AND p50 >= 0 AND p75 >= 0 AND p90 >= 0)
);
CREATE INDEX market_data_lookup ON comp.market_data (edition_id, job_code, weighting, element);

CREATE FUNCTION comp.check_market_data() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_scheme uuid; v_eff date; v_survey uuid;
BEGIN
  SELECT e.status, s.scheme_id, e.effective_date, s.survey_id INTO v_status, v_scheme, v_eff, v_survey
    FROM comp.survey_edition e JOIN comp.survey s USING (survey_id)
    WHERE e.edition_id = coalesce(NEW.edition_id, OLD.edition_id);
  IF v_status <> 'loading' THEN
    RAISE EXCEPTION 'EDITION_IMMUTABLE: edition is %', v_status USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  NEW.survey_id := v_survey;
  IF NOT EXISTS (SELECT 1 FROM comp.survey_cut c WHERE c.cut_id = NEW.cut_id AND c.edition_id = NEW.edition_id) THEN
    RAISE EXCEPTION 'CUT_NOT_IN_EDITION' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM core.code_value v WHERE v.scheme_id = v_scheme AND v.code = NEW.job_code
                   AND v.valid_period @> v_eff AND upper_inf(v.sys_period)) THEN
    RAISE EXCEPTION 'SURVEY_JOB_NOT_IN_CATALOGUE: %', NEW.job_code USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER market_data_check BEFORE INSERT OR UPDATE OR DELETE ON comp.market_data
  FOR EACH ROW EXECUTE FUNCTION comp.check_market_data();

CREATE FUNCTION comp.guard_survey_edition() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ord text[] := ARRAY['loading','published','retired'];
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'loading' THEN RAISE EXCEPTION 'EDITION_IMMUTABLE: retire it instead' USING ERRCODE = 'check_violation'; END IF;
    RETURN OLD;
  END IF;
  IF array_position(ord, NEW.status) < array_position(ord, OLD.status) THEN
    RAISE EXCEPTION 'EDITION_STATUS_BACKWARDS: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status <> 'loading' AND (to_jsonb(NEW) - ARRAY['status','published_at']) <> (to_jsonb(OLD) - ARRAY['status','published_at']) THEN
    RAISE EXCEPTION 'EDITION_IMMUTABLE: edition is %', OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'loading' AND NEW.status = 'published' THEN
    NEW.published_at := coalesce(NEW.published_at, now());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER survey_edition_guard BEFORE UPDATE OR DELETE ON comp.survey_edition
  FOR EACH ROW EXECUTE FUNCTION comp.guard_survey_edition();
-- Rows under an edition (cuts, practice prevalence) change only while it is loading
CREATE FUNCTION comp.check_market_data_parent() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_survey uuid;
BEGIN
  SELECT e.status, e.survey_id INTO v_status, v_survey FROM comp.survey_edition e
    WHERE e.edition_id = coalesce(NEW.edition_id, OLD.edition_id);
  IF v_status <> 'loading' THEN
    RAISE EXCEPTION 'EDITION_IMMUTABLE: edition is %', v_status USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  IF TG_TABLE_NAME = 'practice_market' THEN
    NEW.survey_id := v_survey;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER survey_cut_guard BEFORE INSERT OR UPDATE OR DELETE ON comp.survey_cut
  FOR EACH ROW EXECUTE FUNCTION comp.check_market_data_parent();

-- =====================================================================================
-- COMP — market definitions and pricing runs (§7)
-- =====================================================================================
CREATE TABLE comp.market_definition (
  tenant_id      uuid NOT NULL,
  definition_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           text NOT NULL,
  name_en        text NOT NULL,
  name_fr        text,
  applies_to     jsonb NOT NULL DEFAULT '{}'::jsonb,     -- { "jobFamily": ["FIN"], "careerLevel": ["S1","S2"], "jobIds": [] }
  is_default     boolean NOT NULL DEFAULT false,
  statistic      text NOT NULL DEFAULT 'p50' CHECK (statistic IN ('mean','p10','p25','p50','p75','p90')),
  statistics     text[] NOT NULL DEFAULT ARRAY['p25','p50','p75']::text[],
  adjust_pct     numeric(6,3) NOT NULL DEFAULT 0,        -- +5 = lead the market by 5%
  minimum        jsonb NOT NULL DEFAULT '{"nOrgs": 4}'::jsonb,
  min_sources    smallint NOT NULL DEFAULT 1 CHECK (min_sources >= 1),
  ageing         jsonb NOT NULL DEFAULT '{"method": "none", "annualRate": "0"}'::jsonb,
  status         text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CHECK (statistics <@ ARRAY['mean','p10','p25','p50','p75','p90']::text[]),
  CHECK (ageing->>'method' IN ('none','simple','compound'))
);
CREATE UNIQUE INDEX market_definition_one_default ON comp.market_definition (tenant_id) WHERE is_default AND status = 'active';

CREATE TABLE comp.market_definition_source (
  tenant_id          uuid NOT NULL,
  source_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  definition_id      uuid NOT NULL REFERENCES comp.market_definition,
  seq                smallint NOT NULL,
  kind               text NOT NULL CHECK (kind IN ('survey','public_wage')),
  edition_id         uuid REFERENCES comp.survey_edition,
  public_edition_id  text REFERENCES ref.public_wage_edition,
  weighting          text CHECK (weighting IN ('organization','incumbent','single')),
  element            text,
  cut_chain          text[],
  geo_chain          text[],
  hours_basis        numeric(7,2) CHECK (hours_basis > 0),
  weight             numeric(6,2) NOT NULL CHECK (weight > 0),
  geo_differential_pct numeric(6,3) NOT NULL DEFAULT 0,
  UNIQUE (definition_id, seq),
  CHECK ((kind = 'survey' AND edition_id IS NOT NULL AND public_edition_id IS NULL AND weighting IS NOT NULL
          AND element IS NOT NULL AND coalesce(cardinality(cut_chain), 0) >= 1)
      OR (kind = 'public_wage' AND public_edition_id IS NOT NULL AND edition_id IS NULL
          AND coalesce(cardinality(geo_chain), 0) >= 1 AND hours_basis IS NOT NULL))
);

CREATE TABLE comp.market_pricing_run (
  tenant_id           uuid NOT NULL,
  run_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  definition_id       uuid NOT NULL REFERENCES comp.market_definition,
  as_of               date NOT NULL,                     -- the common date values are aged to
  status              text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','superseded')),
  definition_snapshot jsonb NOT NULL,                    -- the definition and its sources as used
  survey_ids          uuid[] NOT NULL DEFAULT '{}',      -- surveys the run used; keys the derived-results policy
  stale               boolean NOT NULL DEFAULT false,    -- a newer edition of a source exists
  created_by          uuid NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  approved_by         uuid,
  approved_at         timestamptz,
  change_set_id       uuid,
  CHECK (status = 'draft' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL))
);
CREATE UNIQUE INDEX market_pricing_run_one_approved ON comp.market_pricing_run (definition_id) WHERE status = 'approved';

CREATE TABLE comp.market_composite (
  tenant_id     uuid NOT NULL,
  composite_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  run_id        uuid NOT NULL REFERENCES comp.market_pricing_run,
  job_id        uuid NOT NULL REFERENCES core.job,
  status        text NOT NULL CHECK (status IN ('priced','insufficient_data')),
  mean          numeric(14,2),
  p10           numeric(14,2),
  p25           numeric(14,2),
  p50           numeric(14,2),
  p75           numeric(14,2),
  p90           numeric(14,2),
  target        numeric(14,2),
  lineage       jsonb NOT NULL,                          -- per source: cut or geography, counts, raw, ageing factor, weight, used, reason
  is_benchmark  boolean NOT NULL DEFAULT true,
  UNIQUE (run_id, job_id),
  CHECK (status <> 'priced' OR target IS NOT NULL),
  CHECK (status <> 'insufficient_data' OR target IS NULL)
);

-- Derived results are hidden only when a run used a survey marked derived_results_restricted (§12)
CREATE FUNCTION comp.run_visible(p_run uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM comp.market_pricing_run r JOIN comp.survey s ON s.survey_id = ANY (r.survey_ids)
    WHERE r.run_id = p_run AND s.derived_results_restricted AND NOT platform.has_role(s.access_role))
$$;

CREATE FUNCTION comp.guard_pricing_run() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN RAISE EXCEPTION 'RUN_IMMUTABLE' USING ERRCODE = 'check_violation'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.status <> 'draft' THEN
    IF NOT (OLD.status = 'approved' AND NEW.status IN ('approved','superseded')
            AND (to_jsonb(NEW) - ARRAY['status','stale']) = (to_jsonb(OLD) - ARRAY['status','stale'])) THEN
      RAISE EXCEPTION 'RUN_IMMUTABLE: run is %', OLD.status USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.status = 'approved' THEN
    UPDATE comp.market_pricing_run SET status = 'superseded'
      WHERE definition_id = NEW.definition_id AND status = 'approved' AND run_id <> NEW.run_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pricing_run_guard BEFORE UPDATE OR DELETE ON comp.market_pricing_run
  FOR EACH ROW EXECUTE FUNCTION comp.guard_pricing_run();

CREATE FUNCTION comp.guard_market_composite() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM comp.market_pricing_run WHERE run_id = coalesce(NEW.run_id, OLD.run_id);
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'RUN_IMMUTABLE: run is %', v_status USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER market_composite_guard BEFORE INSERT OR UPDATE OR DELETE ON comp.market_composite
  FOR EACH ROW EXECUTE FUNCTION comp.guard_market_composite();

-- =====================================================================================
-- COMP — pay structures (§7.6 to §7.8)
-- =====================================================================================
CREATE TABLE comp.pay_structure (
  tenant_id     uuid NOT NULL,
  structure_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL,
  name_en       text NOT NULL,
  name_fr       text,
  kind          text NOT NULL CHECK (kind IN ('graded','broadband','market_job','step_grid','hourly_table')),
  currency      char(3) NOT NULL DEFAULT 'CAD',
  basis         text NOT NULL DEFAULT 'annual' CHECK (basis IN ('annual','hourly')),
  applies_to    jsonb NOT NULL DEFAULT '{}'::jsonb,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code)
);

CREATE TABLE comp.pay_structure_version (
  tenant_id            uuid NOT NULL,
  structure_version_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  structure_id         uuid NOT NULL REFERENCES comp.pay_structure,
  label                text NOT NULL,
  valid_period         daterange NOT NULL,
  status               text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','superseded')),
  je_plan_version_id   uuid REFERENCES comp.je_plan_version,
  pricing_run_id       uuid REFERENCES comp.market_pricing_run,
  method               jsonb NOT NULL DEFAULT '{}'::jsonb,   -- { "marketLine": { "a": "…", "b": "…", "r2": "…" }, "excluded": [{ "jobId": "…", "reason": "…" }] }
  rounding             numeric(10,2) NOT NULL DEFAULT 100 CHECK (rounding > 0),
  approved_by          uuid,
  approved_at          timestamptz,
  change_set_id        uuid,
  UNIQUE (structure_id, label),
  CHECK (status = 'draft' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  EXCLUDE USING gist (structure_id WITH =, valid_period WITH &&) WHERE (status = 'approved')
);

CREATE TABLE comp.pay_grade (
  tenant_id            uuid NOT NULL,
  grade_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  structure_version_id uuid NOT NULL REFERENCES comp.pay_structure_version,
  grade_code           text NOT NULL,
  rank                 smallint NOT NULL,
  points_min           integer,
  points_max           integer,
  minimum              numeric(14,2) NOT NULL,
  midpoint             numeric(14,2) NOT NULL,
  maximum              numeric(14,2) NOT NULL,
  spread_pct           numeric(6,2),
  midpoint_edit_reason text,                             -- smoothing by the analyst (§7.7)
  UNIQUE (structure_version_id, grade_code),
  UNIQUE (structure_version_id, rank),
  CHECK (minimum <= midpoint AND midpoint <= maximum),
  CHECK (points_min <= points_max)
);

CREATE FUNCTION comp.guard_pay_structure_version() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'draft' THEN RAISE EXCEPTION 'STRUCTURE_VERSION_IMMUTABLE' USING ERRCODE = 'check_violation'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.status <> 'draft' THEN
    IF NOT (OLD.status = 'approved' AND NEW.status IN ('approved','superseded')
            AND (to_jsonb(NEW) - 'status') = (to_jsonb(OLD) - 'status')) THEN
      RAISE EXCEPTION 'STRUCTURE_VERSION_IMMUTABLE: version is %', OLD.status USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pay_structure_version_guard BEFORE UPDATE OR DELETE ON comp.pay_structure_version
  FOR EACH ROW EXECUTE FUNCTION comp.guard_pay_structure_version();

CREATE FUNCTION comp.guard_pay_grade() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text;
BEGIN
  SELECT status INTO v_status FROM comp.pay_structure_version
    WHERE structure_version_id = coalesce(NEW.structure_version_id, OLD.structure_version_id);
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'STRUCTURE_VERSION_IMMUTABLE: version is %', v_status USING ERRCODE = 'check_violation';
  END IF;
  RETURN coalesce(NEW, OLD);
END $$;
CREATE TRIGGER pay_grade_guard BEFORE INSERT OR UPDATE OR DELETE ON comp.pay_grade
  FOR EACH ROW EXECUTE FUNCTION comp.guard_pay_grade();

-- Published ranges stay in comp.salary_range (read by postings, offers, cycles and payroll), now linked to their version
ALTER TABLE comp.salary_range
  ADD COLUMN structure_version_id uuid REFERENCES comp.pay_structure_version,
  ADD COLUMN grade_id             uuid REFERENCES comp.pay_grade,
  ADD COLUMN basis                text NOT NULL DEFAULT 'annual' CHECK (basis IN ('annual','hourly'));

-- =====================================================================================
-- COMP — taking part in surveys (§10)
-- =====================================================================================
-- One pseudonym per position held (assignment), so a person in two matched positions is two incumbents, each at its
-- own FTE (docs/20 §7). Stable across editions for as long as the assignment lasts.
CREATE TABLE comp.survey_pseudonym (
  tenant_id      uuid NOT NULL,
  survey_id      uuid NOT NULL REFERENCES comp.survey,
  assignment_id  uuid NOT NULL REFERENCES core.assignment,
  pseudonym      text NOT NULL DEFAULT ('P' || upper(encode(gen_random_bytes(6), 'hex'))),
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (survey_id, assignment_id),
  UNIQUE (survey_id, pseudonym)
);
CREATE FUNCTION comp.block_pseudonym_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'PSEUDONYM_IMMUTABLE: a pseudonym stays the same for the life of the survey' USING ERRCODE = 'check_violation';
END $$;
CREATE TRIGGER survey_pseudonym_immutable BEFORE UPDATE OR DELETE ON comp.survey_pseudonym
  FOR EACH ROW EXECUTE FUNCTION comp.block_pseudonym_change();

CREATE TABLE comp.survey_submission (
  tenant_id        uuid NOT NULL,
  submission_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id        uuid NOT NULL REFERENCES comp.survey,
  edition_label    text NOT NULL,                        -- the edition being collected, usually not loaded yet
  as_of            date NOT NULL,
  status           text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','in_review','approved','exported','withdrawn')),
  org_profile      jsonb NOT NULL DEFAULT '{}'::jsonb,
  included_fields  text[] NOT NULL DEFAULT '{}',         -- optional fields switched on, e.g. 'hire_year', 'bargaining_unit', 'gender'
  privacy_approval jsonb,                                -- { "approvedBy": "…", "approvedOn": "…", "dpaRef": "…" }
  practice_answers jsonb NOT NULL DEFAULT '{}'::jsonb,
  row_count        integer,
  file_sha256      text,
  approved_by      uuid,
  approved_at      timestamptz,
  exported_by      uuid,
  exported_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  CHECK (status NOT IN ('approved','exported') OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK (status <> 'exported' OR (file_sha256 IS NOT NULL AND exported_at IS NOT NULL AND exported_by IS NOT NULL)),
  CONSTRAINT self_id_needs_privacy_approval
    CHECK (NOT (included_fields && ARRAY['gender','self_identification']::text[]) OR privacy_approval IS NOT NULL),
  CONSTRAINT no_direct_identifier_fields
    CHECK (NOT (included_fields && ARRAY['name','first_name','last_name','sin','date_of_birth','birth_date','address','email','phone','employee_number']::text[]))
);

CREATE TABLE comp.survey_submission_row (
  tenant_id       uuid NOT NULL,
  row_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  submission_id   uuid NOT NULL REFERENCES comp.survey_submission,
  survey_id       uuid NOT NULL,                         -- set by the trigger
  pseudonym       text,                                  -- null only for a vacant position
  vacant          boolean NOT NULL DEFAULT false,
  job_code        text NOT NULL,
  match_quality   text CHECK (match_quality IN ('exact','close','partial')),
  fte             numeric(6,4),
  annual_base     numeric(14,2),
  hourly_rate     numeric(12,4),
  sti_eligible    boolean,
  sti_target_pct  numeric(6,3),
  sti_paid        numeric(14,2),
  location_code   text,
  extra           jsonb NOT NULL DEFAULT '{}'::jsonb,    -- only fields listed in included_fields
  FOREIGN KEY (survey_id, pseudonym) REFERENCES comp.survey_pseudonym (survey_id, pseudonym),
  UNIQUE (submission_id, pseudonym),
  CHECK (vacant OR pseudonym IS NOT NULL),
  CONSTRAINT no_direct_identifiers
    CHECK (NOT (extra ?| ARRAY['name','first_name','last_name','sin','date_of_birth','birth_date','address','email','phone','employee_number']))
);

CREATE FUNCTION comp.guard_survey_submission_row() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_status text; v_survey uuid; v_fields text[];
BEGIN
  SELECT status, survey_id, included_fields INTO v_status, v_survey, v_fields FROM comp.survey_submission
    WHERE submission_id = coalesce(NEW.submission_id, OLD.submission_id);
  IF v_status NOT IN ('draft','in_review') THEN
    RAISE EXCEPTION 'SUBMISSION_IMMUTABLE: submission is %', v_status USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  NEW.survey_id := v_survey;
  IF NEW.extra ?| ARRAY['name','first_name','last_name','sin','date_of_birth','birth_date','address','email','phone','employee_number'] THEN
    RAISE EXCEPTION 'SUBMISSION_DIRECT_IDENTIFIER: names, SIN, birth dates, contact details and employee numbers are never submitted'
      USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(NEW.extra) k WHERE NOT (k = ANY (v_fields))) THEN
    RAISE EXCEPTION 'SUBMISSION_FIELD_NOT_INCLUDED: switch the field on for the submission first' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER survey_submission_row_guard BEFORE INSERT OR UPDATE OR DELETE ON comp.survey_submission_row
  FOR EACH ROW EXECUTE FUNCTION comp.guard_survey_submission_row();

CREATE FUNCTION comp.guard_survey_submission() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ord text[] := ARRAY['draft','in_review','approved','exported'];
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status NOT IN ('draft','withdrawn') THEN RAISE EXCEPTION 'SUBMISSION_IMMUTABLE' USING ERRCODE = 'check_violation'; END IF;
    RETURN OLD;
  END IF;
  IF OLD.status IN ('exported','withdrawn') THEN
    RAISE EXCEPTION 'SUBMISSION_IMMUTABLE: submission is %', OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status <> 'withdrawn' AND array_position(ord, NEW.status) < array_position(ord, OLD.status) THEN
    RAISE EXCEPTION 'SUBMISSION_STATUS_BACKWARDS: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status = 'approved' AND (to_jsonb(NEW) - ARRAY['status','file_sha256','exported_by','exported_at'])
                                 <> (to_jsonb(OLD) - ARRAY['status','file_sha256','exported_by','exported_at']) THEN
    RAISE EXCEPTION 'SUBMISSION_IMMUTABLE: submission is approved' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'approved' AND OLD.status <> 'approved' THEN
    SELECT count(*) INTO NEW.row_count FROM comp.survey_submission_row WHERE submission_id = NEW.submission_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER survey_submission_guard BEFORE UPDATE OR DELETE ON comp.survey_submission
  FOR EACH ROW EXECUTE FUNCTION comp.guard_survey_submission();

-- =====================================================================================
-- COMP — total rewards components (§9)
-- =====================================================================================
CREATE TABLE comp.total_rewards_component (
  tenant_id            uuid NOT NULL,
  code                 text NOT NULL,
  name_en              text NOT NULL,
  name_fr              text,
  category             text NOT NULL CHECK (category IN ('base','variable','statutory','benefits','retirement','time_off','learning','recognition','perk','other')),
  valuation            text NOT NULL CHECK (valuation IN ('rate_components','paid_last_12_months','employer_premiums','employer_contributions',
                                                         'db_current_service','entitlement_days_x_daily_rate','learning_spend','fixed_amount','manual')),
  source               jsonb NOT NULL DEFAULT '{}'::jsonb,
  show_on_statement    boolean NOT NULL DEFAULT true,
  include_in_benchmark boolean NOT NULL DEFAULT false,
  display_order        smallint NOT NULL DEFAULT 100,
  PRIMARY KEY (tenant_id, code)
);

-- =====================================================================================
-- BENEFITS — plan design and practice benchmarking (§8)
-- =====================================================================================
ALTER TABLE benefits.plan
  ADD COLUMN design jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(design) = 'object');
COMMENT ON COLUMN benefits.plan.design IS
  'Plan design values with the keys named by designPath in rules/total-rewards/benefit-practices.json (docs/19 §8.2).';

CREATE TABLE benefits.practice (
  tenant_id          uuid NOT NULL,
  practice_code      text NOT NULL,
  source             text NOT NULL CHECK (source IN ('catalogue','tenant')),
  ref_practice_code  text REFERENCES ref.reward_practice,
  category           text NOT NULL,
  name_en            text NOT NULL,
  name_fr            text,
  value_type         text NOT NULL CHECK (value_type IN ('boolean','money','multiple_of_salary','percent','days','weeks','months','count','enum','text')),
  unit               text,
  richer_when        text NOT NULL CHECK (richer_when IN ('higher','lower','yes','none')),
  enum_values        text[],
  own_value_source   jsonb,
  enabled            boolean NOT NULL DEFAULT true,
  PRIMARY KEY (tenant_id, practice_code),
  CHECK (source <> 'catalogue' OR ref_practice_code IS NOT NULL),
  CHECK (value_type <> 'enum' OR coalesce(cardinality(enum_values), 0) >= 2)
);

CREATE TABLE benefits.practice_market (
  tenant_id      uuid NOT NULL,
  row_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  edition_id     uuid NOT NULL REFERENCES comp.survey_edition,
  survey_id      uuid NOT NULL,                          -- set by the trigger; keys the licence policy
  practice_code  text NOT NULL,
  cut_id         uuid REFERENCES comp.survey_cut,
  n_orgs         integer NOT NULL CHECK (n_orgs >= 0),
  prevalence_pct numeric(5,2) CHECK (prevalence_pct BETWEEN 0 AND 100),
  p25            numeric(14,4),
  p50            numeric(14,4),
  p75            numeric(14,4),
  mode           text,
  distribution   jsonb,                                  -- { "2": 40, "3": 35, "4": 25 }
  masked         boolean NOT NULL DEFAULT false,
  FOREIGN KEY (tenant_id, practice_code) REFERENCES benefits.practice,
  UNIQUE NULLS NOT DISTINCT (edition_id, practice_code, cut_id),
  CHECK (p25 <= p50 AND p50 <= p75 AND p25 <= p75)
);

CREATE TRIGGER practice_market_guard BEFORE INSERT OR UPDATE OR DELETE ON benefits.practice_market
  FOR EACH ROW EXECUTE FUNCTION comp.check_market_data_parent();

CREATE TABLE benefits.practice_own_value (
  tenant_id      uuid NOT NULL,
  row_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  practice_code  text NOT NULL,
  population     text NOT NULL,                          -- benefit class code, agreement id, or 'ALL'
  value          jsonb NOT NULL,                         -- { "value": 7 } in the practice's unit
  source         text NOT NULL CHECK (source IN ('derived','manual')),
  derived_from   jsonb,                                  -- { "planId": "…", "designPath": "waitingDays" }
  reason         text,
  valid_period   daterange NOT NULL,
  sys_period     tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id  uuid NOT NULL,
  FOREIGN KEY (tenant_id, practice_code) REFERENCES benefits.practice,
  CHECK (source <> 'manual' OR reason IS NOT NULL),
  CHECK (value ? 'value'),
  EXCLUDE USING gist (tenant_id WITH =, practice_code WITH =, population WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

-- =====================================================================================
-- Row-level security: tenant isolation on every new tenant table (same policy as 0001)
-- =====================================================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS s, c.relname AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND NOT c.relrowsecurity
      AND n.nspname IN ('comp','talent','benefits')
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

-- Licence: restrictive policies on survey content (§12). Both policies must pass.
CREATE POLICY survey_licence ON comp.market_data AS RESTRICTIVE
  USING (comp.survey_visible(survey_id)) WITH CHECK (comp.survey_visible(survey_id));
CREATE POLICY survey_licence ON benefits.practice_market AS RESTRICTIVE
  USING (comp.survey_visible(survey_id)) WITH CHECK (comp.survey_visible(survey_id));
CREATE POLICY survey_licence ON comp.survey_pseudonym AS RESTRICTIVE
  USING (comp.survey_visible(survey_id)) WITH CHECK (comp.survey_visible(survey_id));
CREATE POLICY survey_licence ON comp.survey_submission_row AS RESTRICTIVE
  USING (comp.survey_visible(survey_id)) WITH CHECK (comp.survey_visible(survey_id));
CREATE POLICY derived_results ON comp.market_composite AS RESTRICTIVE
  USING (comp.run_visible(run_id)) WITH CHECK (comp.run_visible(run_id));
-- The survey job catalogue (titles and licensed descriptions) is values of the survey's code scheme. The check runs
-- as the migration owner so that roles which read core but not comp (recruiting, the org chart) can still read codes;
-- it only answers whether the scheme belongs to a survey whose role the request lacks.
CREATE FUNCTION core.code_value_visible(p_scheme uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$
  SELECT NOT EXISTS (SELECT 1 FROM comp.survey s WHERE s.scheme_id = p_scheme AND NOT platform.has_role(s.access_role))
$$;
CREATE POLICY survey_licence ON core.code_value AS RESTRICTIVE
  USING (core.code_value_visible(scheme_id)) WITH CHECK (core.code_value_visible(scheme_id));

-- Grants follow 0002_roles: cando_app gets SELECT on the new ref tables, SELECT, INSERT and UPDATE on the new
-- comp, talent and benefits tables, and EXECUTE on the new functions. Only the loader writes ref.public_wage* and
-- ref.reward_practice. The licence-expiry job runs as cando_app with the survey's access role in app.roles.
