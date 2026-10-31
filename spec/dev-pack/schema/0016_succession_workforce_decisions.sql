-- =====================================================================================
-- Migration 0016 · Succession and workforce planning decisions (docs/30)
--
-- Applies the owner's Module 09 review of 29 October 2026 (claude/review/09-succession-workforce-planning-decisions.md).
-- One module for every organization: key roles and backups for everyone, talent reviews and workforce planning
-- switched on by each organization. People choose; suggestions are rule-based; succession data is seen only by the
-- people named on a review or plan, and HR.
--
--   §1  Settings
--   §2  Critical roles and risk (flight risk, retirement outlook, vacancy dates, aspirations)
--   §3  Talent reviews, potential and the nine-box
--   §4  Succession plans, successors, language gaps, continuity sheets
--   §5  Talent pools
--   §6  Career paths
--   §7  Workforce planning: segments, history, scenarios, supply, demand, gap strategies
--   §8  Position and headcount plans
--   §9  Routes, cautions, no self-approval, text fields, row-level security
--
-- Run after 0015.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/30 §2.1)
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('succession.talent_review_enabled', 'succession', 'boolean', NULL, 'false', ARRAY['tenant','legal_entity'], false,
  'Talent reviews (potential assessments and review meetings). Key roles, backups and succession plans are always available.',
  'docs/30 §3.1 (R1.1)', 'decided', NULL, NULL, NULL),
 ('succession.nine_box_enabled', 'succession', 'boolean', NULL, 'false', ARRAY['tenant','legal_entity'], false,
  'The nine-box grid (performance by potential) in talent reviews.',
  'docs/30 §5.3 (R3.2)', 'decided', NULL, NULL, NULL),
 ('workforce.planning_enabled', 'workforce', 'boolean', NULL, 'false', ARRAY['tenant'], false,
  'Workforce planning: segments, supply and demand, scenarios and gap strategies.',
  'docs/30 §3.1 (R1.1)', 'decided', NULL, NULL, NULL),
 ('succession.critical_weights', 'succession', 'json', NULL,
  '{"impact":20,"hardToReplace":20,"singlePointOfFailure":20,"marketScarcity":20,"requiredByLaw":20}', ARRAY['tenant','legal_entity'], false,
  'Weights of the five criteria leaders score a role on (1 to 5 each), as percentages adding up to 100.',
  'docs/30 §4.1 (R2.1)', 'decided', NULL, NULL, ARRAY['impact','hardToReplace','singlePointOfFailure','marketScarcity','requiredByLaw']),
 ('succession.potential_criteria', 'succession', 'json', NULL,
  '{"criteria":[{"code":"learning_agility","en":"Learning agility","fr":"Agilité d''apprentissage","levels":{"low":{"en":"Learns well in familiar situations","fr":"Apprend bien dans des situations connues"},"moderate":{"en":"Learns quickly and applies it to new situations","fr":"Apprend vite et l''applique à des situations nouvelles"},"high":{"en":"Seeks out the unfamiliar and thrives in it","fr":"Recherche l''inconnu et s''y épanouit"}}},{"code":"leadership","en":"Leadership","fr":"Leadership","levels":{"low":{"en":"Leads own work","fr":"Mène son propre travail"},"moderate":{"en":"Leads peers and projects","fr":"Mène ses pairs et des projets"},"high":{"en":"Leads people and change across teams","fr":"Mène des personnes et le changement entre équipes"}}},{"code":"aspiration","en":"Aspiration","fr":"Aspiration","levels":{"low":{"en":"Wants to grow in the current role","fr":"Souhaite progresser dans son rôle actuel"},"moderate":{"en":"Wants a broader or next-level role","fr":"Souhaite un rôle plus large ou de niveau supérieur"},"high":{"en":"Wants significantly larger roles","fr":"Souhaite des rôles nettement plus importants"}}},{"code":"engagement","en":"Engagement","fr":"Engagement","levels":{"low":{"en":"Committed to the job","fr":"Engagé dans son emploi"},"moderate":{"en":"Committed to the team and its goals","fr":"Engagé envers l''équipe et ses objectifs"},"high":{"en":"Committed to the organization''s mission","fr":"Engagé envers la mission de l''organisation"}}}]}',
  ARRAY['tenant','legal_entity'], false,
  'Criteria and level descriptions managers use to assess potential, in English and French. The employee''s own stated aspiration is always shown beside them.',
  'docs/30 §5.2 (R3.1)', 'decided', NULL, NULL, ARRAY['criteria']),
 ('succession.nine_box_boxes', 'succession', 'json', NULL,
  '{"boxes":{"high_high":{"en":"Future leader","fr":"Leader de demain","action_en":"Stretch roles and a succession slot","action_fr":"Rôles exigeants et place dans une relève"},"high_moderate":{"en":"Rising star","fr":"Étoile montante","action_en":"Accelerate development","action_fr":"Accélérer le développement"},"high_low":{"en":"Emerging talent","fr":"Talent émergent","action_en":"Clarify expectations and coach","action_fr":"Clarifier les attentes et accompagner"},"moderate_high":{"en":"High performer","fr":"Très performant","action_en":"Broaden experience","action_fr":"Élargir l''expérience"},"moderate_moderate":{"en":"Core contributor","fr":"Contributeur essentiel","action_en":"Develop in role","action_fr":"Développer dans le rôle"},"moderate_low":{"en":"Developing","fr":"En développement","action_en":"Support and review goals","action_fr":"Soutenir et revoir les objectifs"},"low_high":{"en":"Trusted expert","fr":"Expert de confiance","action_en":"Recognize and retain","action_fr":"Reconnaître et retenir"},"low_moderate":{"en":"Solid contributor","fr":"Contributeur solide","action_en":"Keep engaged","action_fr":"Maintenir l''engagement"},"low_low":{"en":"Needs attention","fr":"À soutenir","action_en":"Understand causes first, then a plan","action_fr":"Comprendre d''abord les causes, puis un plan"}}}',
  ARRAY['tenant','legal_entity'], false,
  'Names and suggested actions of the nine boxes (potential then performance: high_high is high potential and high performance).',
  'docs/30 §5.3 (R3.2)', 'decided', NULL, NULL, ARRAY['boxes']),
 ('succession.employee_sees_placement', 'succession', 'boolean', NULL, 'false', ARRAY['tenant','legal_entity'], false,
  'Employees see their own potential rating and nine-box placement. Off: the manager shares the readiness feedback they choose.',
  'docs/30 §5.4 (R3.3)', 'decided', NULL, NULL, NULL),
 ('succession.bias_prompts', 'succession', 'boolean', NULL, 'true', ARRAY['tenant','legal_entity'], false,
  'Bias prompts in talent reviews, for groups at least as large as privacy.min_group_size_self_id.',
  'docs/30 §5.5 (R3.4)', 'decided', NULL, NULL, NULL),
 ('succession.plan_review_months', 'succession', 'integer', NULL, '12', ARRAY['tenant','legal_entity'], false,
  'Months between reviews of a succession plan.',
  'docs/30 §6.4 (R4.4)', 'decided', 1, NULL, NULL),
 ('succession.plan_review_reminder_days', 'succession', 'integer', NULL, '30', ARRAY['tenant','legal_entity'], false,
  'Days before a succession plan''s review date when its owner is reminded.',
  'docs/30 §6.4 (R4.4)', 'decided', 0, NULL, NULL),
 ('succession.continuity_review_months', 'succession', 'integer', NULL, '12', ARRAY['tenant','legal_entity'], false,
  'Months between updates of a critical role''s continuity sheet.',
  'docs/30 §6.5 (R4.5)', 'decided', 1, NULL, NULL),
 ('workforce.thin_history', 'workforce', 'json', NULL, '{"minPeople":10,"minYears":2}', ARRAY['tenant'], false,
  'A segment''s turnover history is too thin to project from below this many people or years; CanDo then suggests the next level up and the planner decides.',
  'docs/30 §9.2 (R6.3)', 'decided', NULL, NULL, ARRAY['minPeople','minYears']);

-- Feature switches: a talent review or workforce scenario needs its feature switched on
CREATE FUNCTION talent.feature_on(p_tenant uuid, p_key text, p_legal_entity uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT (platform.setting(p_tenant, p_key, current_date, p_legal_entity))::boolean
$$;

-- -------------------------------------------------------------------------------------
-- 2. Critical roles and risk (docs/30 §4)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.critical_role (
  tenant_id        uuid NOT NULL REFERENCES platform.tenant,
  critical_role_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position_id      uuid NOT NULL REFERENCES core.position,
  scores           jsonb NOT NULL,            -- {"impact":4,...}: 1 to 5 for each criterion in succession.critical_weights
  score            numeric(4,2),              -- weighted, 1 to 5; computed
  required_by_law  boolean NOT NULL,
  legal_basis      text,
  scored_by        uuid NOT NULL REFERENCES platform.app_user,
  confirmed_by     uuid REFERENCES platform.app_user,
  confirmed_at     timestamptz,
  owner_user       uuid NOT NULL REFERENCES platform.app_user,
  status           text NOT NULL CHECK (status IN ('proposed','confirmed','retired')),
  CONSTRAINT critical_role_law CHECK (NOT required_by_law OR coalesce(length(btrim(legal_basis)), 0) > 0),
  CONSTRAINT critical_role_confirmed CHECK (status <> 'confirmed' OR (confirmed_by IS NOT NULL AND confirmed_at IS NOT NULL))
);
CREATE UNIQUE INDEX critical_role_one_per_position ON talent.critical_role (tenant_id, position_id) WHERE status <> 'retired';

CREATE FUNCTION talent.check_critical_role() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE w jsonb; k text; total numeric := 0; s numeric := 0; v numeric;
BEGIN
  w := platform.setting(NEW.tenant_id, 'succession.critical_weights', current_date, core.position_legal_entity(NEW.position_id, current_date));
  FOR k IN SELECT jsonb_object_keys(w) LOOP total := total + (w ->> k)::numeric; END LOOP;
  IF total <> 100 THEN
    RAISE EXCEPTION 'CRITICAL_WEIGHTS_INVALID: the organization''s weights add up to %, not 100', total USING ERRCODE = 'check_violation';
  END IF;
  IF jsonb_typeof(NEW.scores) <> 'object' OR NOT (NEW.scores ?& ARRAY(SELECT jsonb_object_keys(w)))
     OR EXISTS (SELECT 1 FROM jsonb_object_keys(NEW.scores) x WHERE NOT (w ? x)) THEN
    RAISE EXCEPTION 'CRITICAL_SCORE_INVALID: score each of % once', ARRAY(SELECT jsonb_object_keys(w)) USING ERRCODE = 'check_violation';
  END IF;
  FOR k IN SELECT jsonb_object_keys(w) LOOP
    v := (NEW.scores ->> k)::numeric;
    IF v IS NULL OR v NOT IN (1,2,3,4,5) THEN
      RAISE EXCEPTION 'CRITICAL_SCORE_INVALID: % is scored 1 to 5', k USING ERRCODE = 'check_violation';
    END IF;
    s := s + v * (w ->> k)::numeric / 100;
  END LOOP;
  NEW.score := round(s, 2);
  IF NEW.status = 'confirmed' AND NEW.confirmed_by = NEW.scored_by THEN
    RAISE EXCEPTION 'SELF_APPROVAL: the leader who scored the role does not confirm it; HR does' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER critical_role_check BEFORE INSERT OR UPDATE ON talent.critical_role
  FOR EACH ROW EXECUTE FUNCTION talent.check_critical_role();

-- Flight risk is the manager's assessment, never a model (docs/30 §4.3)
CREATE TABLE talent.flight_risk_assessment (
  tenant_id     uuid NOT NULL,
  assessment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  level         text NOT NULL CHECK (level IN ('low','medium','high')),
  note          text NOT NULL,
  assessed_by   uuid NOT NULL REFERENCES platform.app_user,
  assessed_on   date NOT NULL
);
CREATE FUNCTION talent.check_flight_risk() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.assessed_by IN (SELECT u.user_id FROM platform.app_user u JOIN core.employment e ON e.person_id = u.person_id
                          WHERE e.employment_id = NEW.employment_id) THEN
    RAISE EXCEPTION 'SELF_REVIEW: flight risk is the manager''s assessment, not the employee''s own' USING ERRCODE = 'check_violation';
  END IF;
  IF length(btrim(NEW.note)) = 0 THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: a flight risk assessment states what it is based on' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER flight_risk_check BEFORE INSERT OR UPDATE ON talent.flight_risk_assessment
  FOR EACH ROW EXECUTE FUNCTION talent.check_flight_risk();

-- Retirement: pension eligibility and what the employee chooses to share; never age per person (docs/30 §4.4)
CREATE TABLE talent.retirement_outlook (
  tenant_id     uuid NOT NULL,
  outlook_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  eligible_on   date,
  eligibility_source text CHECK (eligibility_source IN ('pension_plan','agreement','organization_policy')),
  intention_shared boolean NOT NULL,
  intended_window daterange,
  phased_interest boolean,
  shared_at     timestamptz,
  UNIQUE (employment_id),
  CONSTRAINT retirement_eligibility_source CHECK ((eligible_on IS NULL) = (eligibility_source IS NULL)),
  CONSTRAINT retirement_intention CHECK (intention_shared = (shared_at IS NOT NULL)
                                         AND (intention_shared OR (intended_window IS NULL AND phased_interest IS NULL)))
);

-- A date a role may become vacant, kept by HR only (end of a work authorization, a term); no immigration details
CREATE TABLE talent.vacancy_risk (
  tenant_id      uuid NOT NULL,
  risk_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id  uuid NOT NULL REFERENCES core.employment,
  kind           text NOT NULL CHECK (kind IN ('authorization_end','term_end','other')),
  may_vacate_on  date NOT NULL,
  recorded_by    uuid NOT NULL REFERENCES platform.app_user
);

-- The employee's own career aspiration: target jobs, mobility, openness to succession, visibility to recruiters
CREATE TABLE talent.career_aspiration (
  tenant_id       uuid NOT NULL,
  aspiration_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id       uuid NOT NULL REFERENCES core.person,
  target_job_ids  uuid[] NOT NULL DEFAULT '{}',
  target_text     text,
  mobility        jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {"relocate":false,"locations":[...]}
  timeframe       text,
  open_to_succession boolean NOT NULL,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (person_id)
);

-- -------------------------------------------------------------------------------------
-- 3. Talent reviews, potential and the nine-box (docs/30 §5)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.talent_review (
  tenant_id     uuid NOT NULL REFERENCES platform.tenant,
  review_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL,
  name_en       text NOT NULL,
  name_fr       text,
  period        daterange NOT NULL,
  legal_entity_id uuid REFERENCES core.legal_entity,
  uses_nine_box boolean,                      -- filled from succession.nine_box_enabled
  participants  uuid[] NOT NULL,              -- the people named on the review, who see its data with HR
  owner_user    uuid NOT NULL REFERENCES platform.app_user,
  status        text NOT NULL CHECK (status IN ('draft','open','closed')),
  UNIQUE (tenant_id, code),
  CONSTRAINT talent_review_participants CHECK (cardinality(participants) > 0)
);
INSERT INTO platform.column_default (table_schema, table_name, column_name, source, setting_key)
  VALUES ('talent','talent_review','uses_nine_box','setting','succession.nine_box_enabled');
CREATE TRIGGER a00_fill_from_settings BEFORE INSERT ON talent.talent_review FOR EACH ROW EXECUTE FUNCTION platform.fill_from_settings();

CREATE FUNCTION talent.check_talent_review() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT talent.feature_on(NEW.tenant_id, 'succession.talent_review_enabled', NEW.legal_entity_id) THEN
    RAISE EXCEPTION 'FEATURE_OFF: talent reviews are off until the organization switches them on' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.uses_nine_box AND NOT talent.feature_on(NEW.tenant_id, 'succession.nine_box_enabled', NEW.legal_entity_id) THEN
    RAISE EXCEPTION 'FEATURE_OFF: the nine-box is off until the organization switches it on' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER talent_review_check BEFORE INSERT OR UPDATE ON talent.talent_review
  FOR EACH ROW EXECUTE FUNCTION talent.check_talent_review();

CREATE TABLE talent.potential_assessment (
  tenant_id     uuid NOT NULL,
  assessment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id     uuid REFERENCES talent.talent_review,
  employment_id uuid NOT NULL REFERENCES core.employment,
  criteria      jsonb NOT NULL,               -- {"learning_agility":"high",...}: the organization's criteria
  potential     text NOT NULL CHECK (potential IN ('low','moderate','high')),
  aspiration    jsonb,                        -- the employee's own stated aspiration, copied when assessed
  note          text,
  assessed_by   uuid NOT NULL REFERENCES platform.app_user,
  assessed_on   date NOT NULL
);
CREATE FUNCTION talent.check_potential_assessment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE crit jsonb; k text; person uuid; le uuid; a talent.career_aspiration;
BEGIN
  SELECT e.person_id, e.legal_entity_id INTO person, le FROM core.employment e WHERE e.employment_id = NEW.employment_id;
  IF NEW.assessed_by IN (SELECT u.user_id FROM platform.app_user u WHERE u.person_id = person) THEN
    RAISE EXCEPTION 'SELF_REVIEW: no one assesses their own potential' USING ERRCODE = 'check_violation';
  END IF;
  crit := platform.setting(NEW.tenant_id, 'succession.potential_criteria', NEW.assessed_on, le) -> 'criteria';
  FOR k IN SELECT jsonb_object_keys(NEW.criteria) LOOP
    IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(crit) c WHERE c ->> 'code' = k) THEN
      RAISE EXCEPTION 'POTENTIAL_CRITERION_UNKNOWN: % is not one of the organization''s criteria', k USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.criteria ->> k NOT IN ('low','moderate','high') THEN
      RAISE EXCEPTION 'POTENTIAL_CRITERION_UNKNOWN: % is assessed low, moderate or high', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(crit) c WHERE NOT (NEW.criteria ? (c ->> 'code'))) THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: assess every one of the organization''s criteria' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.aspiration IS NULL THEN
    SELECT * INTO a FROM talent.career_aspiration WHERE person_id = person;
    NEW.aspiration := CASE WHEN a.aspiration_id IS NULL THEN '{"stated":false}'::jsonb
                           ELSE jsonb_build_object('stated', true, 'targets', a.target_job_ids, 'text', a.target_text,
                                                   'openToSuccession', a.open_to_succession, 'mobility', a.mobility) END;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER potential_assessment_check BEFORE INSERT OR UPDATE ON talent.potential_assessment
  FOR EACH ROW EXECUTE FUNCTION talent.check_potential_assessment();

CREATE TABLE talent.nine_box_placement (
  tenant_id     uuid NOT NULL,
  placement_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id     uuid NOT NULL REFERENCES talent.talent_review,
  employment_id uuid NOT NULL REFERENCES core.employment,
  performance   text NOT NULL CHECK (performance IN ('low','moderate','high')),
  potential     text NOT NULL CHECK (potential IN ('low','moderate','high')),
  box           text,                         -- potential_performance; computed
  placed_by     uuid NOT NULL REFERENCES platform.app_user,
  reason        text,
  UNIQUE (review_id, employment_id)
);
CREATE TABLE talent.placement_history (
  tenant_id    uuid NOT NULL,
  history_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  placement_id uuid NOT NULL REFERENCES talent.nine_box_placement,
  old_box      text NOT NULL,
  new_box      text NOT NULL,
  moved_by     uuid NOT NULL REFERENCES platform.app_user,
  reason       text NOT NULL,
  moved_at     timestamptz NOT NULL DEFAULT now()
);
CREATE FUNCTION talent.check_nine_box_placement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE nine boolean;
BEGIN
  SELECT uses_nine_box INTO nine FROM talent.talent_review WHERE review_id = NEW.review_id;
  IF NOT coalesce(nine, false) THEN
    RAISE EXCEPTION 'FEATURE_OFF: this talent review does not use the nine-box' USING ERRCODE = 'check_violation';
  END IF;
  NEW.box := NEW.potential || '_' || NEW.performance;
  IF TG_OP = 'UPDATE' AND NEW.box <> OLD.box THEN
    IF coalesce(length(btrim(NEW.reason)), 0) = 0 OR NEW.reason IS NOT DISTINCT FROM OLD.reason THEN
      RAISE EXCEPTION 'PLACEMENT_REASON_REQUIRED: moving someone to another box needs a reason' USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO talent.placement_history (tenant_id, placement_id, old_box, new_box, moved_by, reason)
      VALUES (NEW.tenant_id, NEW.placement_id, OLD.box, NEW.box, NEW.placed_by, NEW.reason);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER nine_box_placement_check BEFORE INSERT OR UPDATE ON talent.nine_box_placement
  FOR EACH ROW EXECUTE FUNCTION talent.check_nine_box_placement();

-- Bias prompt for part-time staff: share placed at low potential, shown only when both groups are large enough
CREATE FUNCTION talent.bias_check_part_time(p_review uuid)
RETURNS TABLE (grp text, people integer, low_potential_share numeric) LANGUAGE sql STABLE AS $$
  WITH r AS (SELECT * FROM talent.talent_review WHERE review_id = p_review),
  p AS (
    SELECT n.employment_id, n.potential,
           CASE WHEN (SELECT sum(av.fte) FROM core.assignment a JOIN core.assignment_version av ON av.assignment_id = a.assignment_id
                       WHERE a.employment_id = n.employment_id AND upper_inf(av.sys_period)
                         AND av.valid_period @> (upper((SELECT period FROM r)) - 1)) < 1 THEN 'part_time' ELSE 'full_time' END AS grp
      FROM talent.nine_box_placement n WHERE n.review_id = p_review),
  g AS (SELECT grp, count(*)::int AS people, round(100.0 * count(*) FILTER (WHERE potential = 'low') / count(*), 1) AS share FROM p GROUP BY grp),
  m AS (SELECT platform.setting_number(r.tenant_id, 'privacy.min_group_size_self_id') AS min_size,
               (platform.setting(r.tenant_id, 'succession.bias_prompts', current_date, r.legal_entity_id))::boolean AS on_ FROM r)
  SELECT g.grp, g.people, g.share FROM g, m
   WHERE m.on_ AND (SELECT count(*) FROM g) = 2 AND NOT EXISTS (SELECT 1 FROM g x WHERE x.people < m.min_size)
$$;

-- -------------------------------------------------------------------------------------
-- 4. Succession plans, successors, language gaps, continuity sheets (docs/30 §6)
-- -------------------------------------------------------------------------------------
-- Legacy slates (0001) stay as history; plans and successors below replace them
COMMENT ON TABLE talent.succession_slate IS 'Read-only after 0016: succession plans are in talent.succession_plan and talent.successor (docs/30 §6).';

CREATE TABLE talent.succession_plan (
  tenant_id        uuid NOT NULL REFERENCES platform.tenant,
  plan_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position_id      uuid NOT NULL REFERENCES core.position,
  critical_role_id uuid REFERENCES talent.critical_role,
  owner_user       uuid NOT NULL REFERENCES platform.app_user,
  members          uuid[] NOT NULL DEFAULT '{}',   -- other people named on the plan, who see it with HR
  emergency_successor_employment_id uuid REFERENCES core.employment,
  development_only boolean,                        -- a unionized role: development, not appointment (computed)
  external_hire_option boolean NOT NULL,
  route_id         uuid REFERENCES platform.workflow_route,
  status           text NOT NULL CHECK (status IN ('draft','submitted','approved','retired')),
  submitted_at     timestamptz,
  approved_at      timestamptz,
  last_reviewed_on date,
  review_due_on    date
);
CREATE UNIQUE INDEX succession_plan_one_per_position ON talent.succession_plan (tenant_id, position_id) WHERE status <> 'retired';

CREATE FUNCTION talent.position_unionized(p_position uuid, p_on date) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT pv.agreement_id IS NOT NULL FROM core.position_version pv
                    WHERE pv.position_id = p_position AND pv.valid_period @> p_on AND upper_inf(pv.sys_period)), false)
$$;

CREATE FUNCTION talent.check_succession_plan() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE by_law boolean; le uuid;
BEGIN
  NEW.development_only := talent.position_unionized(NEW.position_id, current_date);
  le := core.position_legal_entity(NEW.position_id, current_date);
  IF NEW.status = 'submitted' AND (TG_OP = 'INSERT' OR OLD.status <> 'submitted') THEN
    IF NEW.route_id IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a succession plan is submitted with its route' USING ERRCODE = 'check_violation';
    END IF;
    NEW.submitted_at := now();
  END IF;
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved') THEN
    IF NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'succession_plan', NEW.plan_id, NEW.owner_user, NEW.submitted_at - interval '1 microsecond') THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the organization''s route for this succession plan is not complete' USING ERRCODE = 'check_violation';
    END IF;
    SELECT c.required_by_law INTO by_law FROM talent.critical_role c WHERE c.critical_role_id = NEW.critical_role_id;
    IF coalesce(by_law, false) AND NEW.emergency_successor_employment_id IS NULL THEN
      RAISE EXCEPTION 'EMERGENCY_SUCCESSOR_REQUIRED: a position the law requires has an emergency successor' USING ERRCODE = 'check_violation';
    END IF;
    NEW.approved_at := now();
    NEW.last_reviewed_on := coalesce(NEW.last_reviewed_on, current_date);
    UPDATE talent.successor SET status = 'approved' WHERE plan_id = NEW.plan_id AND status = 'proposed';
  END IF;
  IF NEW.last_reviewed_on IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.last_reviewed_on IS DISTINCT FROM OLD.last_reviewed_on OR NEW.review_due_on IS NULL) THEN
    NEW.review_due_on := (NEW.last_reviewed_on
                          + make_interval(months => platform.setting_number(NEW.tenant_id, 'succession.plan_review_months', NEW.last_reviewed_on, le)::int))::date;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER succession_plan_check BEFORE INSERT OR UPDATE ON talent.succession_plan
  FOR EACH ROW EXECUTE FUNCTION talent.check_succession_plan();

-- Language proficiency, so successors for bilingual positions show a gap (docs/30 §10.4)
CREATE TABLE talent.language_proficiency (
  tenant_id   uuid NOT NULL,
  proficiency_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id   uuid NOT NULL REFERENCES core.person,
  language    text NOT NULL,
  level       text NOT NULL CHECK (level IN ('X','A','B','C','E')),   -- federal second language results: X below A; E exempt from further testing (holds C)
  assessed_on date NOT NULL,
  source      text NOT NULL CHECK (source IN ('test','self_declared','manager','hr'))
);
-- What a person lacks for the position's language requirement on a date, or NULL
CREATE FUNCTION talent.language_gap(p_person uuid, p_position uuid, p_on date) RETURNS text LANGUAGE sql STABLE AS $$
  WITH req AS (
    SELECT v.attributes FROM core.position_version pv
      JOIN core.list_value v ON v.tenant_id = pv.tenant_id AND v.list_code = 'language_requirement' AND v.code = pv.language_requirement
     WHERE pv.position_id = p_position AND pv.valid_period @> p_on AND upper_inf(pv.sys_period)),
  need AS (SELECT l AS language, req.attributes ->> 'level' AS level FROM req, jsonb_array_elements_text(coalesce(req.attributes -> 'languages', '[]')) l),
  have AS (SELECT language, max(array_position(ARRAY['X','A','B','C','E'], level)) AS rank
             FROM talent.language_proficiency WHERE person_id = p_person AND assessed_on <= p_on GROUP BY language)
  SELECT string_agg(n.language || coalesce(' ' || n.level, ''), ', ' ORDER BY n.language)
    FROM need n LEFT JOIN have h ON h.language = n.language
   WHERE (SELECT count(*) FROM need) > 1
     AND (h.rank IS NULL OR (n.level IS NOT NULL AND h.rank < array_position(ARRAY['X','A','B','C','E'], n.level)))
$$;

CREATE TABLE talent.successor (
  tenant_id     uuid NOT NULL,
  successor_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id       uuid NOT NULL REFERENCES talent.succession_plan,
  employment_id uuid NOT NULL REFERENCES core.employment,
  readiness     text NOT NULL,                 -- the organization's succession_readiness list
  proposed_by   uuid NOT NULL REFERENCES platform.app_user,
  status        text NOT NULL CHECK (status IN ('proposed','approved','removed')),
  aspiration_mismatch boolean,                 -- computed from the person's own aspiration
  language_gap  text,                          -- computed from the position's language requirement
  development_plan_id uuid REFERENCES talent.development_plan,   -- the successor's own plan, agreed by both (docs/29 §7.3)
  UNIQUE (plan_id, employment_id)
);
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON talent.successor
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('readiness', 'succession_readiness');

CREATE FUNCTION talent.check_successor() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p talent.succession_plan; person uuid; a talent.career_aspiration; job uuid;
BEGIN
  SELECT * INTO p FROM talent.succession_plan WHERE plan_id = NEW.plan_id;
  SELECT e.person_id INTO person FROM core.employment e WHERE e.employment_id = NEW.employment_id;
  SELECT pv.job_id INTO job FROM core.position_version pv
   WHERE pv.position_id = p.position_id AND pv.valid_period @> current_date AND upper_inf(pv.sys_period);
  SELECT * INTO a FROM talent.career_aspiration WHERE person_id = person;
  NEW.aspiration_mismatch := a.aspiration_id IS NOT NULL
                             AND (NOT a.open_to_succession OR (cardinality(a.target_job_ids) > 0 AND NOT (job = ANY (a.target_job_ids))));
  NEW.language_gap := talent.language_gap(person, p.position_id, current_date);
  -- A change to an approved plan's successors goes back through the route
  IF p.status = 'approved' AND (TG_OP = 'INSERT' OR (NEW.readiness, NEW.status) IS DISTINCT FROM (OLD.readiness, OLD.status)) AND NEW.status <> 'approved' THEN
    UPDATE talent.succession_plan SET status = 'submitted' WHERE plan_id = p.plan_id;
  ELSIF p.status = 'approved' AND TG_OP = 'UPDATE' AND NEW.status = 'approved' AND NEW.readiness IS DISTINCT FROM OLD.readiness THEN
    NEW.status := 'proposed';
    UPDATE talent.succession_plan SET status = 'submitted' WHERE plan_id = p.plan_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER successor_check BEFORE INSERT OR UPDATE ON talent.successor
  FOR EACH ROW EXECUTE FUNCTION talent.check_successor();

-- Plans due for review on a date: the reminder day before the due date, and every day once overdue
CREATE FUNCTION talent.plans_due_for_review(p_tenant uuid, p_on date)
RETURNS TABLE (plan_id uuid, review_due_on date, overdue boolean) LANGUAGE sql STABLE AS $$
  SELECT p.plan_id, p.review_due_on, p.review_due_on < p_on
    FROM talent.succession_plan p
   WHERE p.tenant_id = p_tenant AND p.status = 'approved' AND p.review_due_on IS NOT NULL
     AND (p.review_due_on < p_on OR p.review_due_on - platform.setting_number(p_tenant, 'succession.plan_review_reminder_days', p_on,
                                       core.position_legal_entity(p.position_id, p_on))::int = p_on)
$$;

-- Positions the law requires with no approved plan or no emergency successor: HR is reminded (docs/30 §4.2)
CREATE FUNCTION talent.required_roles_without_plan(p_tenant uuid)
RETURNS TABLE (critical_role_id uuid, position_id uuid, missing text) LANGUAGE sql STABLE AS $$
  SELECT c.critical_role_id, c.position_id,
         CASE WHEN p.plan_id IS NULL OR p.status <> 'approved' THEN 'approved_plan' ELSE 'emergency_successor' END
    FROM talent.critical_role c
    LEFT JOIN talent.succession_plan p ON p.position_id = c.position_id AND p.status <> 'retired'
   WHERE c.tenant_id = p_tenant AND c.required_by_law AND c.status <> 'retired'
     AND (p.plan_id IS NULL OR p.status <> 'approved' OR p.emergency_successor_employment_id IS NULL)
$$;

-- Direct hire into a unionized position with a development plan needs the caution (docs/30 §6.3)
CREATE FUNCTION talent.check_offer_succession() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('approved','sent') AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('approved','sent'))
     AND NEW.hire_path = 'direct_hire'
     AND EXISTS (SELECT 1 FROM talent.succession_plan p WHERE p.position_id = NEW.position_id AND p.status = 'approved' AND p.development_only)
     AND NOT platform.caution_cleared(NEW.tenant_id, 'succession.appoint_without_posting', 'offer', NEW.offer_id) THEN
    RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: succession.appoint_without_posting' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER offer_succession_check BEFORE INSERT OR UPDATE ON recruit.offer
  FOR EACH ROW EXECUTE FUNCTION talent.check_offer_succession();

-- Continuity sheet: contacts, systems and delegations, never passwords or secrets (docs/30 §6.5)
CREATE TABLE talent.continuity_sheet (
  tenant_id     uuid NOT NULL,
  sheet_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position_id   uuid NOT NULL REFERENCES core.position,
  maintained_by uuid NOT NULL REFERENCES platform.app_user,
  contacts      jsonb NOT NULL DEFAULT '[]'::jsonb,
  systems       jsonb NOT NULL DEFAULT '[]'::jsonb,
  delegations   jsonb NOT NULL DEFAULT '[]'::jsonb,
  notes         text,
  updated_on    date NOT NULL,
  review_due_on date,                          -- filled from succession.continuity_review_months
  UNIQUE (tenant_id, position_id)
);
CREATE FUNCTION talent.check_continuity_sheet() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le uuid;
BEGIN
  -- A key that holds a secret (adminPassword, pin, token, apiKey...) or a note giving one ("password: ...") is refused
  IF (NEW.contacts::text || NEW.systems::text || NEW.delegations::text)
       ~* '"([a-z_]*(password|passcode|passwd|passphrase)[a-z_]*|pin|pin_?code|secret|client_?secret|token|access_?token|api_?key|mfa_?code|otp)"\s*:'
     OR coalesce(NEW.notes, '') ~* '\m(password|passcode|passwd|passphrase|pin)\s*(is\s*)?[:=]' THEN
    RAISE EXCEPTION 'SECRET_NOT_ALLOWED: passwords, PINs and other secrets are never stored in CanDo; name where they are kept instead'
      USING ERRCODE = 'check_violation';
  END IF;
  le := core.position_legal_entity(NEW.position_id, NEW.updated_on);
  NEW.review_due_on := (NEW.updated_on + make_interval(months => platform.setting_number(NEW.tenant_id, 'succession.continuity_review_months', NEW.updated_on, le)::int))::date;
  RETURN NEW;
END $$;
CREATE TRIGGER continuity_sheet_check BEFORE INSERT OR UPDATE ON talent.continuity_sheet
  FOR EACH ROW EXECUTE FUNCTION talent.check_continuity_sheet();

-- Who sees a continuity sheet besides HR: the person keeping it, the incumbents of the position and of the position it
-- reports to (the manager), and the emergency successor named on its plan
CREATE FUNCTION talent.continuity_sheet_can_see(p_sheet uuid, p_user uuid, p_on date DEFAULT current_date) RETURNS boolean
LANGUAGE sql STABLE AS $$
  WITH s AS (SELECT * FROM talent.continuity_sheet WHERE sheet_id = p_sheet),
  holders AS (
    SELECT u.user_id FROM s
      JOIN core.position_version pv ON pv.position_id = s.position_id AND pv.valid_period @> p_on AND upper_inf(pv.sys_period)
      JOIN core.assignment_version av ON av.position_id IN (s.position_id, pv.reports_to_position_id)
                                     AND av.valid_period @> p_on AND upper_inf(av.sys_period)
      JOIN core.assignment a ON a.assignment_id = av.assignment_id
      JOIN core.employment e ON e.employment_id = a.employment_id
      JOIN platform.app_user u ON u.person_id = e.person_id),
  interim AS (
    SELECT u.user_id FROM s
      JOIN talent.succession_plan p ON p.position_id = s.position_id AND p.status <> 'retired'
      JOIN core.employment e ON e.employment_id = p.emergency_successor_employment_id
      JOIN platform.app_user u ON u.person_id = e.person_id)
  SELECT coalesce(p_user IN (SELECT maintained_by FROM s UNION SELECT user_id FROM holders UNION SELECT user_id FROM interim), false)
$$;

-- Every view of succession data is logged (docs/30 §3.4)
CREATE TABLE talent.succession_view_log (
  tenant_id    uuid NOT NULL,
  view_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  viewer       uuid NOT NULL REFERENCES platform.app_user,
  subject_type text NOT NULL CHECK (subject_type IN ('talent_review','succession_plan','potential_assessment','nine_box_placement','continuity_sheet','talent_pool')),
  subject_id   uuid NOT NULL,
  viewed_at    timestamptz NOT NULL DEFAULT now()
);
-- Who may see a review or plan: the people named on it (and HR, checked by the API's capability)
CREATE FUNCTION talent.named_on(p_subject_type text, p_subject_id uuid, p_user uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT CASE p_subject_type
           WHEN 'talent_review'   THEN EXISTS (SELECT 1 FROM talent.talent_review r WHERE r.review_id = p_subject_id AND (p_user = ANY (r.participants) OR r.owner_user = p_user))
           WHEN 'succession_plan' THEN EXISTS (SELECT 1 FROM talent.succession_plan p WHERE p.plan_id = p_subject_id AND (p_user = ANY (p.members) OR p.owner_user = p_user))
           WHEN 'continuity_sheet' THEN talent.continuity_sheet_can_see(p_subject_id, p_user)
           ELSE false END
$$;

-- -------------------------------------------------------------------------------------
-- 5. Talent pools (docs/30 §6.6)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.talent_pool (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  pool_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL,
  name_en     text NOT NULL,
  name_fr     text,
  criteria_en text NOT NULL,
  criteria_fr text,
  owner_user  uuid NOT NULL REFERENCES platform.app_user,
  accepts_applications boolean NOT NULL,
  status      text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code)
);
CREATE TABLE talent.pool_member (
  tenant_id    uuid NOT NULL,
  member_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pool_id      uuid NOT NULL REFERENCES talent.talent_pool,
  person_id    uuid NOT NULL REFERENCES core.person,
  source       text NOT NULL CHECK (source IN ('nominated','applied')),
  nominated_by uuid NOT NULL REFERENCES platform.app_user,
  route_id     uuid REFERENCES platform.workflow_route,
  status       text NOT NULL CHECK (status IN ('proposed','approved','declined','exited')),
  reason       text,
  UNIQUE (pool_id, person_id)
);
CREATE FUNCTION talent.check_pool_member() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE pool talent.talent_pool;
BEGIN
  SELECT * INTO pool FROM talent.talent_pool WHERE pool_id = NEW.pool_id;
  IF NEW.source = 'applied' THEN
    IF NOT pool.accepts_applications THEN
      RAISE EXCEPTION 'POOL_CLOSED_TO_APPLICATIONS: this pool takes nominations only' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.nominated_by NOT IN (SELECT u.user_id FROM platform.app_user u WHERE u.person_id = NEW.person_id) THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: an application to a pool is made by the employee themself' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved') THEN
    IF NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'talent_pool_membership', NEW.member_id, NEW.nominated_by, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the pool owner approves through the organization''s route' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.status IN ('declined','exited') AND (TG_OP = 'INSERT' OR OLD.status <> NEW.status) AND coalesce(length(btrim(NEW.reason)), 0) = 0 THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: declining or ending a pool membership states why' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pool_member_check BEFORE INSERT OR UPDATE ON talent.pool_member
  FOR EACH ROW EXECUTE FUNCTION talent.check_pool_member();

-- -------------------------------------------------------------------------------------
-- 6. Career paths (docs/30 §7)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.career_path_step (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  step_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_job_id uuid NOT NULL REFERENCES core.job,
  to_job_id   uuid NOT NULL REFERENCES core.job,
  move_type   text NOT NULL CHECK (move_type IN ('vertical','lateral','cross_functional')),
  source      text NOT NULL CHECK (source IN ('job_architecture','observed_moves','hr')),
  created_by  uuid NOT NULL REFERENCES platform.app_user,
  status      text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, from_job_id, to_job_id),
  CONSTRAINT career_path_not_same CHECK (from_job_id <> to_job_id)
);
-- Moves people actually made between jobs (in the same assignment) since a date, to propose career path steps
CREATE FUNCTION talent.observed_job_moves(p_tenant uuid, p_since date)
RETURNS TABLE (from_job_id uuid, to_job_id uuid, moves bigint) LANGUAGE sql STABLE AS $$
  WITH v AS (
    SELECT av.assignment_id, lower(av.valid_period) AS d, pv.job_id
      FROM core.assignment_version av
      JOIN core.position_version pv ON pv.position_id = av.position_id AND pv.valid_period @> lower(av.valid_period) AND upper_inf(pv.sys_period)
     WHERE av.tenant_id = p_tenant AND upper_inf(av.sys_period)),
  m AS (SELECT job_id, lag(job_id) OVER (PARTITION BY assignment_id ORDER BY d) AS prev, d FROM v)
  SELECT prev, job_id, count(*) FROM m WHERE prev IS NOT NULL AND prev <> job_id AND d >= p_since GROUP BY prev, job_id
$$;

-- -------------------------------------------------------------------------------------
-- 7. Workforce planning (docs/30 §9)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.workforce_segment (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  segment_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL,
  name_en     text NOT NULL,
  name_fr     text,
  parent_code text,                            -- the next level up, used when history is thin
  criteria    jsonb NOT NULL,                  -- orgUnits, jobs, jobFamilies, careerLevels, locations, agreements, employmentTypes, legalEntities
  UNIQUE (tenant_id, code),
  FOREIGN KEY (tenant_id, parent_code) REFERENCES talent.workforce_segment (tenant_id, code),
  CONSTRAINT workforce_segment_criteria CHECK (jsonb_typeof(criteria) = 'object'),
  CONSTRAINT workforce_segment_parent CHECK (parent_code IS DISTINCT FROM code)
);
CREATE FUNCTION talent.check_workforce_segment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(NEW.criteria) LOOP
    IF k NOT IN ('orgUnits','jobs','jobFamilies','careerLevels','locations','agreements','employmentTypes','legalEntities')
       OR jsonb_typeof(NEW.criteria -> k) <> 'array' THEN
      RAISE EXCEPTION 'SEGMENT_SCOPE_UNKNOWN: % is not a segment scope (each takes a list)', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER workforce_segment_check BEFORE INSERT OR UPDATE ON talent.workforce_segment
  FOR EACH ROW EXECUTE FUNCTION talent.check_workforce_segment();

-- Turnover history by segment: from CanDo's own records, and uploaded from a previous system
CREATE TABLE talent.turnover_history (
  tenant_id     uuid NOT NULL,
  history_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  segment_code  text NOT NULL,
  period        daterange NOT NULL,
  average_headcount numeric(10,2) NOT NULL CHECK (average_headcount >= 0),
  separations   numeric(10,2) NOT NULL CHECK (separations >= 0),
  retirements   numeric(10,2) NOT NULL CHECK (retirements >= 0),
  source        text NOT NULL CHECK (source IN ('cando','upload')),
  upload_document_id uuid REFERENCES platform.document,
  loaded_by     uuid NOT NULL REFERENCES platform.app_user,
  FOREIGN KEY (tenant_id, segment_code) REFERENCES talent.workforce_segment (tenant_id, code),
  EXCLUDE USING gist (tenant_id WITH =, segment_code WITH =, source WITH =, period WITH &&),
  CONSTRAINT turnover_upload_document CHECK (source <> 'upload' OR upload_document_id IS NOT NULL),
  CONSTRAINT turnover_retirements CHECK (retirements <= separations)
);
CREATE FUNCTION talent.history_summary(p_tenant uuid, p_segment text)
RETURNS TABLE (people numeric, years numeric, annual_rate numeric, thin boolean) LANGUAGE sql STABLE AS $$
  WITH h AS (SELECT * FROM talent.turnover_history WHERE tenant_id = p_tenant AND segment_code = p_segment),
  s AS (SELECT avg(average_headcount) AS people,
               sum((upper(period) - lower(period)) / 365.25) AS years,
               sum(separations) AS seps,
               sum(average_headcount * (upper(period) - lower(period)) / 365.25) AS exposure FROM h),
  t AS (SELECT platform.setting(p_tenant, 'workforce.thin_history') AS cfg)
  SELECT round(s.people, 2), round(s.years, 2), CASE WHEN s.exposure > 0 THEN round(s.seps / s.exposure, 4) END,
         coalesce(s.people < (t.cfg ->> 'minPeople')::numeric OR s.years < (t.cfg ->> 'minYears')::numeric, true)
    FROM s, t
$$;
-- The rate CanDo suggests: the segment's own, or the first level up whose history is not thin (docs/30 §9.2)
CREATE FUNCTION talent.suggested_turnover_rate(p_tenant uuid, p_segment text)
RETURNS TABLE (annual_rate numeric, from_segment text, own_history_thin boolean) LANGUAGE plpgsql STABLE AS $$
DECLARE cur text := p_segment; own_thin boolean; h record; depth int := 0;
BEGIN
  SELECT x.thin INTO own_thin FROM talent.history_summary(p_tenant, p_segment) x;
  WHILE cur IS NOT NULL AND depth < 20 LOOP
    SELECT * INTO h FROM talent.history_summary(p_tenant, cur);
    IF NOT h.thin THEN
      annual_rate := h.annual_rate; from_segment := cur; own_history_thin := own_thin; RETURN NEXT; RETURN;
    END IF;
    SELECT parent_code INTO cur FROM talent.workforce_segment WHERE tenant_id = p_tenant AND code = cur;
    depth := depth + 1;
  END LOOP;
  annual_rate := NULL; from_segment := NULL; own_history_thin := own_thin; RETURN NEXT;
END $$;

CREATE TABLE talent.workforce_scenario (
  tenant_id     uuid NOT NULL REFERENCES platform.tenant,
  scenario_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL,
  version       integer NOT NULL CHECK (version >= 1),
  name_en       text NOT NULL,
  name_fr       text,
  copied_from   uuid REFERENCES talent.workforce_scenario,
  horizon       daterange NOT NULL,
  status        text NOT NULL CHECK (status IN ('draft','saved')),
  created_by    uuid NOT NULL REFERENCES platform.app_user,
  saved_at      timestamptz,
  UNIQUE (tenant_id, code, version),
  CONSTRAINT workforce_scenario_saved CHECK ((status = 'saved') = (saved_at IS NOT NULL))
);
CREATE FUNCTION talent.check_workforce_scenario() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT talent.feature_on(NEW.tenant_id, 'workforce.planning_enabled', NULL) THEN
    RAISE EXCEPTION 'FEATURE_OFF: workforce planning is off until the organization switches it on' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status = 'saved' THEN
    RAISE EXCEPTION 'SCENARIO_VERSION_LOCKED: a saved version is kept as it was; copy it to change it' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER workforce_scenario_check BEFORE INSERT OR UPDATE ON talent.workforce_scenario
  FOR EACH ROW EXECUTE FUNCTION talent.check_workforce_scenario();

-- Lines of a saved scenario cannot change
CREATE FUNCTION talent.check_scenario_line() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM talent.workforce_scenario s WHERE s.scenario_id = NEW.scenario_id AND s.status = 'saved') THEN
    RAISE EXCEPTION 'SCENARIO_VERSION_LOCKED: a saved version is kept as it was; copy it to change it' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TABLE talent.workforce_driver (
  tenant_id    uuid NOT NULL,
  driver_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_id  uuid NOT NULL REFERENCES talent.workforce_scenario,
  segment_code text NOT NULL,
  driver       text NOT NULL,                  -- the organization's own: beds, caseload, students, projects, funded programs
  period       daterange NOT NULL,
  value        numeric(14,2) NOT NULL CHECK (value >= 0),
  FOREIGN KEY (tenant_id, segment_code) REFERENCES talent.workforce_segment (tenant_id, code)
);
CREATE TABLE talent.workforce_ratio (
  tenant_id    uuid NOT NULL,
  ratio_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_id  uuid NOT NULL REFERENCES talent.workforce_scenario,
  segment_code text NOT NULL,
  driver       text NOT NULL,
  units_per_fte numeric(12,4) NOT NULL CHECK (units_per_fte > 0),   -- 12 staff per supervisor, 6 beds per nurse
  UNIQUE (scenario_id, segment_code, driver),
  FOREIGN KEY (tenant_id, segment_code) REFERENCES talent.workforce_segment (tenant_id, code)
);
CREATE TABLE talent.supply_rate (
  tenant_id    uuid NOT NULL,
  rate_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_id  uuid NOT NULL REFERENCES talent.workforce_scenario,
  segment_code text NOT NULL,
  kind         text NOT NULL CHECK (kind IN ('attrition','retirement','internal_out','internal_in')),
  annual_rate  numeric(6,4) NOT NULL CHECK (annual_rate >= 0 AND annual_rate <= 1),
  source       text NOT NULL CHECK (source IN ('history','next_level','planner')),
  from_segment_code text,
  reason       text,
  set_by       uuid NOT NULL REFERENCES platform.app_user,
  UNIQUE (scenario_id, segment_code, kind),
  FOREIGN KEY (tenant_id, segment_code) REFERENCES talent.workforce_segment (tenant_id, code),
  CONSTRAINT supply_rate_next_level CHECK ((source = 'next_level') = (from_segment_code IS NOT NULL))
);
CREATE FUNCTION talent.check_supply_rate() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE thin boolean;
BEGIN
  IF NEW.source = 'planner' AND coalesce(length(btrim(NEW.reason)), 0) = 0 THEN
    RAISE EXCEPTION 'SUPPLY_RATE_REASON_REQUIRED: a rate the planner sets states why' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.source IN ('history','next_level') THEN
    SELECT x.thin INTO thin FROM talent.history_summary(NEW.tenant_id, NEW.segment_code) x;
    IF NEW.source = 'history' AND thin THEN
      RAISE EXCEPTION 'HISTORY_TOO_THIN: % has too little history; use the next level up or set a rate with a reason', NEW.segment_code
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.source = 'next_level' AND NOT thin THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: % has enough history of its own', NEW.segment_code USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a10_scenario_line BEFORE INSERT OR UPDATE ON talent.workforce_driver FOR EACH ROW EXECUTE FUNCTION talent.check_scenario_line();
CREATE TRIGGER a10_scenario_line BEFORE INSERT OR UPDATE ON talent.workforce_ratio FOR EACH ROW EXECUTE FUNCTION talent.check_scenario_line();
CREATE TRIGGER a10_scenario_line BEFORE INSERT OR UPDATE ON talent.supply_rate FOR EACH ROW EXECUTE FUNCTION talent.check_scenario_line();
CREATE TRIGGER supply_rate_check BEFORE INSERT OR UPDATE ON talent.supply_rate FOR EACH ROW EXECUTE FUNCTION talent.check_supply_rate();

-- Demand in FTE for a segment and period: each driver divided by its ratio
CREATE FUNCTION talent.demand_fte(p_scenario uuid, p_segment text, p_period daterange) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT round(coalesce(sum(d.value / r.units_per_fte), 0), 2)
    FROM talent.workforce_driver d
    JOIN talent.workforce_ratio r ON r.scenario_id = d.scenario_id AND r.segment_code = d.segment_code AND r.driver = d.driver
   WHERE d.scenario_id = p_scenario AND d.segment_code = p_segment AND d.period = p_period
$$;

CREATE TABLE talent.gap_strategy (
  tenant_id    uuid NOT NULL,
  strategy_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  scenario_id  uuid NOT NULL REFERENCES talent.workforce_scenario,
  segment_code text NOT NULL,
  period       daterange NOT NULL,
  gap_fte      numeric(10,2) NOT NULL,
  strategy     text NOT NULL CHECK (strategy IN ('build','buy','borrow','bind','bot','redeploy','reduce')),
  draft_kind   text CHECK (draft_kind IN ('training_plan','requisition_forecast','contingent_budget','retention_action','process_change','position_plan')),
  draft_ref    uuid,                            -- the draft in its own module; nothing happens until approved there
  status       text NOT NULL CHECK (status IN ('proposed','drafted','released','dropped')),
  released_by  uuid REFERENCES platform.app_user,
  labour_relations_reviewed_by uuid REFERENCES platform.app_user,
  FOREIGN KEY (tenant_id, segment_code) REFERENCES talent.workforce_segment (tenant_id, code),
  CONSTRAINT gap_strategy_draft CHECK (status NOT IN ('drafted','released') OR (draft_kind IS NOT NULL AND draft_ref IS NOT NULL))
);
CREATE FUNCTION talent.check_gap_strategy() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE unionized boolean;
BEGIN
  IF NEW.status = 'released' AND (TG_OP = 'INSERT' OR OLD.status <> 'released') THEN
    IF NEW.released_by IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: who releases the strategy to its module' USING ERRCODE = 'check_violation';
    END IF;
    SELECT jsonb_array_length(coalesce(criteria -> 'agreements', '[]')) > 0 INTO unionized
      FROM talent.workforce_segment WHERE tenant_id = NEW.tenant_id AND code = NEW.segment_code;
    IF NEW.strategy IN ('reduce','redeploy') AND unionized THEN
      IF NEW.labour_relations_reviewed_by IS NULL OR NEW.labour_relations_reviewed_by = NEW.released_by THEN
        RAISE EXCEPTION 'LABOUR_RELATIONS_REVIEW_REQUIRED: labour relations reviews a reduction in a unionized group before any real step'
          USING ERRCODE = 'check_violation';
      END IF;
      IF NOT platform.caution_cleared(NEW.tenant_id, 'workforce.reduction_unionized', 'gap_strategy', NEW.strategy_id) THEN
        RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: workforce.reduction_unionized' USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER gap_strategy_check BEFORE INSERT OR UPDATE ON talent.gap_strategy FOR EACH ROW EXECUTE FUNCTION talent.check_gap_strategy();

-- -------------------------------------------------------------------------------------
-- 8. Position and headcount plans (docs/30 §10): the plan of draft change sets, approved through the route
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.plan
  ADD COLUMN kind         text CHECK (kind IN ('org_chart','workforce','position_budget')),
  ADD COLUMN fiscal_year  text,
  ADD COLUMN route_id     uuid REFERENCES platform.workflow_route,
  ADD COLUMN submitted_at timestamptz;
-- Every plan before 0016 came from the org chart (docs/04), the only feature that made them (FB-039)
UPDATE platform.plan SET kind = 'org_chart' WHERE kind IS NULL;
ALTER TABLE platform.plan ALTER COLUMN kind SET NOT NULL,
  ADD CONSTRAINT plan_position_budget_year CHECK (kind <> 'position_budget' OR fiscal_year IS NOT NULL);

CREATE FUNCTION talent.check_position_plan() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.kind <> 'position_budget' THEN RETURN NEW; END IF;
  IF NEW.status = 'submitted' AND (TG_OP = 'INSERT' OR OLD.status <> 'submitted') THEN
    IF NEW.route_id IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a position plan is submitted with its route' USING ERRCODE = 'check_violation';
    END IF;
    NEW.submitted_at := now();
  END IF;
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved') THEN
    IF NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'position_plan', NEW.plan_id, NEW.owner_id, NEW.submitted_at - interval '1 microsecond') THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the organization''s route for this position plan is not complete' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER position_plan_check BEFORE INSERT OR UPDATE ON platform.plan FOR EACH ROW EXECUTE FUNCTION talent.check_position_plan();

CREATE TABLE talent.plan_assumption (
  tenant_id     uuid NOT NULL,
  assumption_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id       uuid NOT NULL REFERENCES platform.plan,
  segment_code  text,
  kind          text NOT NULL CHECK (kind IN ('increase','overtime','vacancy','burden','other')),
  value         numeric(12,4) NOT NULL,
  unit          text NOT NULL CHECK (unit IN ('percent','amount')),
  source        text NOT NULL CHECK (source IN ('agreement','comp_cycle','history','payroll_benefits','planner')),
  source_ref    text,                          -- the agreement version, cycle or history period it came from
  reason        text,
  set_by        uuid NOT NULL REFERENCES platform.app_user,
  CONSTRAINT plan_assumption_reason CHECK (source <> 'planner' OR coalesce(length(btrim(reason)), 0) > 0),
  CONSTRAINT plan_assumption_source_ref CHECK (source = 'planner' OR source_ref IS NOT NULL)
);

-- -------------------------------------------------------------------------------------
-- 9. Routes, cautions, no self-approval, text fields, row-level security
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.workflow_route DROP CONSTRAINT IF EXISTS workflow_route_subject_type_check;
ALTER TABLE platform.workflow_route ADD CONSTRAINT workflow_route_subject_type_check
  CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution',
                          'pay_run','voluntary_deduction','banked_time_payout',
                          'comp_philosophy','pay_structure_version','comp_decision','incentive_payout','salary_disclosure',
                          'carrier_invoice','timesheet','performance_review','pip','training_request',
                          'succession_plan','talent_pool_membership','position_plan'));
-- The owner named on the subject (a talent pool's owner) as an approver kind
ALTER TABLE platform.workflow_route_step DROP CONSTRAINT workflow_route_step_approver_kind_check,
  ADD CONSTRAINT workflow_route_step_approver_kind_check
  CHECK (approver_kind IN ('hiring_manager','requester_manager','unit_head','capability','role','user','subject_owner'));

INSERT INTO ref.workflow_route_starter (code, subject_type, name_en, name_fr, conditions, priority, decision_ref) VALUES
 ('succession_plan', 'succession_plan', 'Succession plan approval', 'Approbation du plan de relève', '{}', 10, 'docs/30 §6.1 (R4.1)'),
 ('talent_pool_membership', 'talent_pool_membership', 'Talent pool membership', 'Adhésion à un bassin de talents', '{}', 10, 'docs/30 §6.6 (R4.6)'),
 ('position_plan', 'position_plan', 'Annual position plan', 'Plan annuel des postes', '{}', 10, 'docs/30 §10.1 (R7.1)');
INSERT INTO ref.workflow_route_step_starter (route_code, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr) VALUES
 ('succession_plan', 1, 'capability', 'hr', 'any', 1, 'HR', 'RH'),
 ('talent_pool_membership', 1, 'subject_owner', NULL, 'any', 1, 'The pool''s owner', 'Le responsable du bassin'),
 ('position_plan', 1, 'capability', 'finance', 'any', 1, 'Finance review', 'Examen des finances'),
 ('position_plan', 2, 'capability', 'hr', 'any', 1, 'HR review', 'Examen des RH'),
 ('position_plan', 3, 'capability', 'executive', 'any', 1, 'Executive approval', 'Approbation de la direction');

INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('succession.appoint_without_posting', 'succession', 'Appointing into a unionized role without a posting', 'Nomination à un poste syndiqué sans affichage',
  'This unionized position has a succession plan for development only. The collective agreement''s posting and seniority rules still decide who fills it. State why a direct appointment is allowed here.',
  'Ce poste syndiqué a un plan de relève à des fins de développement seulement. Les règles d''affichage et d''ancienneté de la convention collective décident toujours qui le comble. Indiquez pourquoi une nomination directe est permise ici.',
  true, true, 'docs/30 §6.3 (R4.3)'),
 ('workforce.reduction_unionized', 'workforce', 'Reduction in a unionized group', 'Réduction dans un groupe syndiqué',
  'A reduction or redeployment in a unionized group follows the collective agreement''s layoff, bumping and recall rules, and may require notice to the union and under employment standards. Labour relations has reviewed it; state why it goes ahead.',
  'Une réduction ou un redéploiement dans un groupe syndiqué suit les règles de la convention collective sur la mise à pied, la supplantation et le rappel, et peut exiger un préavis au syndicat et selon les normes du travail. Les relations de travail l''ont examiné; indiquez pourquoi il va de l''avant.',
  true, true, 'docs/30 §9.5 (R6.6)');

CREATE OR REPLACE FUNCTION platform.check_approval_task() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE requester uuid; subject_person uuid;
BEGIN
  IF NEW.status <> 'approved' OR NEW.decided_by IS NULL THEN RETURN NEW; END IF;
  IF NEW.subject_type = 'change_set' THEN
    SELECT requested_by INTO requester FROM platform.change_set WHERE change_set_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'requisition' THEN
    SELECT requested_by INTO requester FROM recruit.requisition WHERE requisition_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'offer' THEN
    SELECT requested_by INTO requester FROM recruit.offer WHERE offer_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'probation_extension' THEN
    SELECT requested_by INTO requester FROM core.probation_extension WHERE extension_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'status_conversion' THEN
    SELECT requested_by INTO requester FROM core.status_conversion_request WHERE request_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'caution' THEN
    SELECT acknowledged_by INTO requester FROM platform.caution_acknowledgement WHERE ack_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'pay_run' THEN
    SELECT created_by INTO requester FROM payroll.pay_run WHERE pay_run_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'voluntary_deduction' THEN
    SELECT requested_by INTO requester FROM payroll.voluntary_deduction WHERE deduction_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'banked_time_payout' THEN
    SELECT requested_by INTO requester FROM timeleave.banked_time_payout_request WHERE request_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'comp_philosophy' THEN
    SELECT submitted_by INTO requester FROM comp.philosophy WHERE philosophy_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'pay_structure_version' THEN
    SELECT submitted_by INTO requester FROM comp.pay_structure_version WHERE structure_version_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'comp_decision' THEN
    SELECT requested_by INTO requester FROM comp.decision WHERE decision_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'incentive_payout' THEN
    SELECT requested_by INTO requester FROM comp.incentive_award WHERE award_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'salary_disclosure' THEN
    SELECT prepared_by INTO requester FROM compliance.salary_disclosure WHERE disclosure_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'carrier_invoice' THEN
    SELECT prepared_by INTO requester FROM benefits.carrier_invoice WHERE invoice_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'timesheet' THEN
    SELECT timeleave.employee_user(assignment_id) INTO requester FROM timeleave.timesheet WHERE timesheet_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'performance_review' THEN
    requester := talent.review_reviewer_user(NEW.subject_id);
    subject_person := talent.review_employee_user(NEW.subject_id);
  ELSIF NEW.subject_type = 'pip' THEN
    SELECT p.created_by, u.user_id INTO requester, subject_person FROM talent.pip p
      JOIN core.employment e ON e.employment_id = p.employment_id
      LEFT JOIN platform.app_user u ON u.tenant_id = p.tenant_id AND u.person_id = e.person_id
     WHERE p.pip_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'training_request' THEN
    SELECT r.requested_by, u.user_id INTO requester, subject_person FROM talent.training_request r
      LEFT JOIN platform.app_user u ON u.tenant_id = r.tenant_id AND u.person_id = r.person_id
     WHERE r.request_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'succession_plan' THEN
    SELECT owner_user INTO requester FROM talent.succession_plan WHERE plan_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'talent_pool_membership' THEN
    SELECT m.nominated_by, u.user_id INTO requester, subject_person FROM talent.pool_member m
      LEFT JOIN platform.app_user u ON u.tenant_id = m.tenant_id AND u.person_id = m.person_id
     WHERE m.member_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'position_plan' THEN
    SELECT owner_id INTO requester FROM platform.plan WHERE plan_id = NEW.subject_id;
  END IF;
  IF NEW.decided_by = requester OR NEW.decided_by = subject_person THEN
    RAISE EXCEPTION 'SELF_APPROVAL: the requester cannot approve their own %', replace(NEW.subject_type, '_', ' ') USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DO $$
DECLARE r record; k text[]; sp boolean;
BEGIN
  FOR r IN
    SELECT c.table_schema AS s, c.table_name AS t, c.column_name AS col, c.is_nullable = 'NO' AS req,
           regexp_replace(c.column_name, '_en$', '') AS field,
           EXISTS (SELECT 1 FROM information_schema.columns f WHERE f.table_schema = c.table_schema AND f.table_name = c.table_name
                     AND f.column_name = regexp_replace(c.column_name, '_en$', '_fr')) AS has_fr
    FROM information_schema.columns c
    JOIN information_schema.tables tb ON tb.table_schema = c.table_schema AND tb.table_name = c.table_name AND tb.table_type = 'BASE TABLE'
    WHERE c.column_name ~ '_en$'
      AND c.table_schema IN ('platform','core','payroll','timeleave','finance','comp','talent','benefits','recruit','offboard','compliance')
      AND EXISTS (SELECT 1 FROM information_schema.columns x WHERE x.table_schema = c.table_schema AND x.table_name = c.table_name AND x.column_name = 'tenant_id')
      AND NOT EXISTS (SELECT 1 FROM platform.translatable_field f WHERE f.table_schema = c.table_schema AND f.table_name = c.table_name
                        AND f.columns ->> 'en' = c.column_name)
    ORDER BY 1, 2, 3
  LOOP
    SELECT array_agg(a.attname ORDER BY array_position(i.indkey::int2[], a.attnum)) INTO k
      FROM pg_index i JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
     WHERE i.indrelid = format('%I.%I', r.s, r.t)::regclass AND i.indisprimary;
    IF k IS NULL THEN RAISE EXCEPTION 'translatable table %.% has no primary key', r.s, r.t; END IF;
    sp := EXISTS (SELECT 1 FROM information_schema.columns x WHERE x.table_schema = r.s AND x.table_name = r.t AND x.column_name = 'sys_period');
    INSERT INTO platform.translatable_field (table_schema, table_name, field, columns, required, key_columns, has_sys_period)
      VALUES (r.s, r.t, r.field,
              jsonb_build_object('en', r.col) || CASE WHEN r.has_fr THEN jsonb_build_object('fr', r.field || '_fr') ELSE '{}'::jsonb END,
              r.req, k, sp);
    IF r.req THEN EXECUTE format('ALTER TABLE %I.%I ALTER COLUMN %I DROP NOT NULL', r.s, r.t, r.col); END IF;
  END LOOP;
  FOR r IN SELECT DISTINCT f.table_schema AS s, f.table_name AS t FROM platform.translatable_field f
            WHERE f.required AND NOT EXISTS (SELECT 1 FROM pg_trigger g WHERE g.tgrelid = format('%I.%I', f.table_schema, f.table_name)::regclass
                                               AND g.tgname = 'zz_required_text') LOOP
    EXECUTE format('CREATE CONSTRAINT TRIGGER zz_required_text AFTER INSERT OR UPDATE ON %I.%I DEFERRABLE INITIALLY DEFERRED
                    FOR EACH ROW EXECUTE FUNCTION platform.check_required_text()', r.s, r.t);
  END LOOP;
END $$;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('talent','critical_role'), ('talent','flight_risk_assessment'), ('talent','retirement_outlook'), ('talent','vacancy_risk'),
      ('talent','career_aspiration'), ('talent','talent_review'), ('talent','potential_assessment'), ('talent','nine_box_placement'),
      ('talent','placement_history'), ('talent','succession_plan'), ('talent','language_proficiency'), ('talent','successor'),
      ('talent','continuity_sheet'), ('talent','succession_view_log'), ('talent','talent_pool'), ('talent','pool_member'),
      ('talent','career_path_step'), ('talent','workforce_segment'), ('talent','turnover_history'), ('talent','workforce_scenario'),
      ('talent','workforce_driver'), ('talent','workforce_ratio'), ('talent','supply_rate'), ('talent','gap_strategy'),
      ('talent','plan_assumption')) AS x(s, t) LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$, r.s, r.t);
  END LOOP;
END $$;

-- Existing organizations get the new starter routes (as in 0009, skipping one whose required data language has no
-- starter text)
DO $$
DECLARE t record; langs text;
BEGIN
  FOR t IN SELECT tenant_id FROM platform.tenant LOOP
    SELECT string_agg(l.lang, ', ' ORDER BY l.lang) INTO langs
      FROM platform.tenant_language l
      JOIN platform.translatable_field f ON f.table_schema = 'core' AND f.table_name = 'list_value' AND f.field = 'name'
     WHERE l.tenant_id = t.tenant_id AND l.for_data = 'required' AND NOT (f.columns ? l.lang);
    IF langs IS NULL THEN
      PERFORM core.seed_tenant(t.tenant_id);
    ELSE
      RAISE NOTICE 'organization %: starter succession and position plan routes not copied because % is required for its data; add them with their texts (docs/30 §12)', t.tenant_id, langs;
    END IF;
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT, INSERT and UPDATE on the new tenant tables and EXECUTE on the new
-- functions. Talent reviews, potential, nine-box placements, succession plans and continuity sheets are shown only to
-- the people named on them (talent.named_on()) and HR, and every view is written to talent.succession_view_log;
-- flight risk and retirement outlooks to planners named on the plan and HR; vacancy risks to HR only; age only in
-- totals from the analytics service (docs/30 §3.4, §4).
