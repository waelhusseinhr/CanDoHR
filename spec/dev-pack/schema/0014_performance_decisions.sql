-- =====================================================================================
-- Migration 0014 · Performance decisions (docs/28)
--
-- Applies the owner's Module 07 review of 28 October 2026 (claude/review/07-performance-decisions.md). People rate
-- people, through the organization's own routes; each position is rated by itself; a review is final only after
-- calibration where the cycle uses it, a one-up look and, where there is a concern, HR; employees always see and
-- answer what is written about them; 360° feedback stays anonymous and developmental; performance improvement plans
-- start only with HR and never during a protected leave; adverse records stop counting after their sunset.
--
--   §1  Settings (and the overall method and minimum days of docs/20 §5, decided)
--   §2  Rating scales and review cycles
--   §3  Goals: shared, aligned, agreed, every amendment kept
--   §4  Reviews: section ratings, calibration, release, sign-off, changes after final
--   §5  Feedback, 360° reviews and check-ins
--   §6  Performance improvement plans
--   §7  Adverse records and sunset clauses
--   §8  Routes, caution, no self-approval, text fields, row-level security
--
-- Run after 0013.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/28 §2)
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('performance.rating_scale_starter', 'performance', 'json', NULL,
  '{"levels":[{"value":1,"en":"Not meeting expectations","fr":"Ne répond pas aux attentes"},{"value":2,"en":"Partly meeting expectations","fr":"Répond partiellement aux attentes"},{"value":3,"en":"Fully meeting expectations","fr":"Répond pleinement aux attentes"},{"value":4,"en":"Exceeding expectations","fr":"Dépasse les attentes"},{"value":5,"en":"Exceptional","fr":"Exceptionnel"}]}',
  ARRAY['tenant'], false,
  'The rating scale a new organization starts from: five points from not meeting expectations to exceptional. The organization can use 3 or 4 points or its own wording, and separate scales for goals, competencies and values.',
  'docs/28 §3.1 (R1.1)', 'decided', NULL, NULL, ARRAY['levels']),
 ('performance.ai_writing_help', 'performance', 'boolean', NULL, 'false', ARRAY['tenant'], false,
  'AI writing help in reviews (wording, bias-language flags, feedback summaries), marked as AI and editable. Comes with the platform assistant; off until the organization switches it on. AI never rates, ranks or recommends terminations.',
  'docs/28 §3.3 (R1.3)', 'decided', NULL, NULL, NULL),
 ('performance.new_hire_no_rating_months', 'performance', 'integer', NULL, '3', ARRAY['tenant','legal_entity'], false,
  'People hired within this many months of the end of a cycle get goals but no year-end rating.',
  'docs/28 §4.2 (R2.2)', 'decided', 0, NULL, NULL),
 ('performance.weights_starter', 'performance', 'json', NULL, '{"goals":50,"competencies":50}', ARRAY['tenant','legal_entity'], false,
  'Weights of goals and competencies in the rating CanDo suggests for a position, as percentages adding up to 100. Each cycle can change them.',
  'docs/28 §4.4 (R2.4)', 'decided', NULL, NULL, ARRAY['goals','competencies']),
 ('performance.calibration', 'performance', 'boolean', NULL, 'true', ARRAY['tenant','legal_entity'], false,
  'New cycles include calibration: ratings are final only after leaders and HR compare them across teams. Each cycle can turn it off.',
  'docs/28 §5.2 (R3.1)', 'decided', NULL, NULL, NULL),
 ('performance.hr_review_concerns', 'performance', 'text_array', NULL,
  '["lowest_rating","differs_from_suggestion","protected_leave","flagged_by_reviewer"]', ARRAY['tenant','legal_entity'], false,
  'What sends a review to HR before the employee sees it, as well as the one-up look: the lowest rating, a rating different from CanDo''s suggestion, protected leave in the cycle, or the one-up reviewer flagging it.',
  'docs/28 §5.3 (R3.2)', 'decided', NULL, NULL, NULL),
 ('performance.rater_group_min', 'performance', 'integer', NULL, '3', ARRAY['tenant','legal_entity'], false,
  'Answers from a 360° rater group (peers, direct reports, others) are shown only when at least this many raters answered, so nobody can be identified. Never below 3.',
  'docs/28 §7.2 (R5.2)', 'decided', 3, NULL, NULL),
 ('performance.rater_group_max', 'performance', 'integer', NULL, '5', ARRAY['tenant','legal_entity'], false,
  'Most raters in one 360° rater group, nominated by the employee, the manager or others.',
  'docs/28 §7.2 (R5.2)', 'decided', 3, NULL, NULL),
 ('performance.feedback_360_use', 'performance', 'text', '["development_only","informs_ratings"]', '"development_only"', ARRAY['tenant','legal_entity'], false,
  'How a new cycle uses 360° results: for development only, or also to inform ratings.',
  'docs/28 §7.3 (R5.3)', 'decided', NULL, NULL, NULL),
 ('performance.checkin_nudge_days', 'performance', 'integer', NULL, '30', ARRAY['tenant','legal_entity'], false,
  'Days without a one-on-one check-in after which the manager is nudged (about a month).',
  'docs/28 §7.4 (R5.4)', 'decided', 1, NULL, NULL),
 ('performance.pip_default_days', 'performance', 'integer', NULL, '60', ARRAY['tenant','legal_entity'], false,
  'Length of a performance improvement plan unless the plan sets its own.',
  'docs/28 §8.2 (R6.2)', 'decided', 1, NULL, NULL),
 ('performance.non_union_sunset', 'performance', 'json', NULL, '{"months":null}', ARRAY['tenant','legal_entity'], false,
  'Months after which an adverse record (a poor review, an improvement plan) of a non-union employee stops counting. None unless the organization sets a number; unionized employees follow their agreement.',
  'docs/28 §9.2 (R7.2)', 'decided', NULL, NULL, ARRAY['months']);

-- The overall method and minimum days of docs/20 §5 are decided: each position stands by itself, rated from 90 days
UPDATE platform.setting_definition SET default_value = '"none"', decision_status = 'decided', decision_ref = 'docs/28 §6.1 (R4.1)',
       description_en = 'How a review with sections for several positions is combined. The owner''s decision: each position stands by itself (none), with no combined rating; an organization can choose FTE × days weighting or the primary manager.'
 WHERE setting_key = 'reviews.overall_method';
UPDATE platform.setting_definition SET default_value = '90', decision_status = 'decided', decision_ref = 'docs/28 §6.2 (R4.2, R7.4)',
       description_en = 'Days a person must have worked in a position during the cycle (protected leave not counted) before its section is rated; shorter periods get comments only.'
 WHERE setting_key = 'reviews.min_section_days';

-- -------------------------------------------------------------------------------------
-- 2. Rating scales and review cycles (docs/28 §3.1, §4)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.rating_scale (
  tenant_id  uuid NOT NULL REFERENCES platform.tenant,
  scale_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL,
  name_en    text NOT NULL,
  name_fr    text,
  levels     jsonb NOT NULL,       -- [{"value":1,"en":"…","fr":"…"}, …], lowest first
  status     text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT rating_scale_levels CHECK (jsonb_typeof(levels) = 'array' AND jsonb_array_length(levels) >= 2)
);

CREATE TABLE talent.review_cycle (
  tenant_id        uuid NOT NULL REFERENCES platform.tenant,
  cycle_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             text NOT NULL,                     -- talent.review.cycle_code
  name_en          text NOT NULL,
  name_fr          text,
  period           daterange NOT NULL,
  scale_id         uuid NOT NULL REFERENCES talent.rating_scale,
  applies_to       jsonb NOT NULL,
  weights          jsonb,                             -- filled from performance.weights_starter
  calibration      boolean,                           -- filled from performance.calibration
  feedback_360_use text CHECK (feedback_360_use IN ('development_only','informs_ratings')),   -- filled from the setting
  new_hire_no_rating_months smallint,                 -- filled from the setting
  mid_year         boolean NOT NULL,
  status           text NOT NULL CHECK (status IN ('draft','open','calibration','closed')),
  UNIQUE (tenant_id, code),
  CONSTRAINT review_cycle_scope_object CHECK (jsonb_typeof(applies_to) = 'object')
);
CREATE TRIGGER review_cycle_scope BEFORE INSERT OR UPDATE OF applies_to ON talent.review_cycle
  FOR EACH ROW EXECUTE FUNCTION payroll.check_scope_keys();
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('talent','review_cycle','weights','setting','performance.weights_starter'),
      ('talent','review_cycle','calibration','setting','performance.calibration'),
      ('talent','review_cycle','feedback_360_use','setting','performance.feedback_360_use'),
      ('talent','review_cycle','new_hire_no_rating_months','setting','performance.new_hire_no_rating_months')
    ) AS x(s, t, c, src, k)
  LOOP
    INSERT INTO platform.column_default (table_schema, table_name, column_name, source, setting_key) VALUES (r.s, r.t, r.c, r.src, r.k);
  END LOOP;
END $$;
CREATE TRIGGER a00_fill_from_settings BEFORE INSERT ON talent.review_cycle FOR EACH ROW EXECUTE FUNCTION platform.fill_from_settings();

CREATE FUNCTION talent.check_review_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.weights IS NULL OR NOT (NEW.weights ?& ARRAY['goals','competencies'])
     OR (NEW.weights ->> 'goals')::numeric < 0 OR (NEW.weights ->> 'competencies')::numeric < 0
     OR (NEW.weights ->> 'goals')::numeric + (NEW.weights ->> 'competencies')::numeric <> 100 THEN
    RAISE EXCEPTION 'PERFORMANCE_WEIGHTS_INVALID: goals and competencies add up to 100 (%)', NEW.weights USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.calibration IS NULL OR NEW.feedback_360_use IS NULL OR NEW.new_hire_no_rating_months IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: a cycle states its calibration, its use of 360° results and its new-hire rule' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER review_cycle_check BEFORE INSERT OR UPDATE ON talent.review_cycle
  FOR EACH ROW EXECUTE FUNCTION talent.check_review_cycle();

-- -------------------------------------------------------------------------------------
-- 3. Goals (docs/28 §4.1): a living, shared document; every amendment after agreement is kept
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.goal (
  tenant_id       uuid NOT NULL,
  goal_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_code      text NOT NULL,
  level           text NOT NULL CHECK (level IN ('mission','organization','department','team','individual')),
  employment_id   uuid REFERENCES core.employment,
  assignment_id   uuid REFERENCES core.assignment,   -- the position an individual goal belongs to
  org_unit_id     uuid REFERENCES core.org_unit,
  parent_goal_id  uuid REFERENCES talent.goal,       -- the goal it aligns to
  kind            text NOT NULL CHECK (kind IN ('objective','development','training','job_standard')),
  title_en        text NOT NULL,
  title_fr        text,
  measure         text,
  target          text,
  weight          numeric(5,2) CHECK (weight >= 0 AND weight <= 100),
  learning_ref    text,                               -- the learning item a training goal points to (Module 08)
  proposed_by     uuid NOT NULL REFERENCES platform.app_user,
  employee_agreed_at timestamptz,
  manager_agreed_at  timestamptz,
  status          text NOT NULL CHECK (status IN ('draft','proposed','agreed','completed','cancelled')),
  changed_by      uuid REFERENCES platform.app_user,  -- who made the latest amendment
  change_reason   text,
  CONSTRAINT goal_individual_owner CHECK ((level = 'individual') = (employment_id IS NOT NULL)),
  CONSTRAINT goal_unit CHECK (level NOT IN ('department','team') OR org_unit_id IS NOT NULL)
);
CREATE TABLE talent.goal_change (
  tenant_id   uuid NOT NULL,
  change_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  goal_id     uuid NOT NULL REFERENCES talent.goal,
  changed_by  uuid NOT NULL REFERENCES platform.app_user,
  changed_at  timestamptz NOT NULL DEFAULT now(),
  reason      text,
  before      jsonb NOT NULL,
  after       jsonb NOT NULL
);

CREATE FUNCTION talent.check_goal() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE keep text[] := ARRAY['parent_goal_id','kind','title_en','title_fr','measure','target','weight','learning_ref','assignment_id','status'];
        b jsonb; a jsonb;
BEGIN
  IF NEW.status = 'agreed' AND NEW.level = 'individual'
     AND (NEW.employee_agreed_at IS NULL OR NEW.manager_agreed_at IS NULL) THEN
    RAISE EXCEPTION 'GOAL_NOT_AGREED: the employee and the manager both agree an individual goal' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IN ('agreed','completed') THEN
    SELECT jsonb_object_agg(k, to_jsonb(OLD) -> k) INTO b FROM unnest(keep) k;
    SELECT jsonb_object_agg(k, to_jsonb(NEW) -> k) INTO a FROM unnest(keep) k;
    IF a IS DISTINCT FROM b THEN
      IF NEW.changed_by IS NULL OR NEW.changed_by IS NOT DISTINCT FROM OLD.changed_by AND NEW.change_reason IS NOT DISTINCT FROM OLD.change_reason THEN
        RAISE EXCEPTION 'INPUT_REQUIRED: an amendment to an agreed goal names who made it' USING ERRCODE = 'check_violation';
      END IF;
      INSERT INTO talent.goal_change (tenant_id, goal_id, changed_by, reason, before, after)
        VALUES (NEW.tenant_id, NEW.goal_id, NEW.changed_by, NEW.change_reason, b, a);
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER goal_check BEFORE INSERT OR UPDATE ON talent.goal
  FOR EACH ROW EXECUTE FUNCTION talent.check_goal();

-- -------------------------------------------------------------------------------------
-- 4. Reviews (docs/28 §5, §6)
-- -------------------------------------------------------------------------------------
ALTER TABLE talent.review DROP CONSTRAINT IF EXISTS review_status_check;
ALTER TABLE talent.review ADD CONSTRAINT review_status_check
  CHECK (status IN ('not_started','self','manager','calibration','one_up','released','signed','closed'));
ALTER TABLE talent.review
  ADD COLUMN calibrated_at          timestamptz,
  ADD COLUMN concerns               text[] NOT NULL DEFAULT '{}',   -- concerns found (docs/28 §5.3); those in performance.hr_review_concerns send it to HR
  ADD COLUMN hr_reviewed_by         uuid REFERENCES platform.app_user,
  ADD COLUMN hr_reviewed_at         timestamptz,
  ADD COLUMN release_route_id       uuid REFERENCES platform.workflow_route,
  ADD COLUMN released_at            timestamptz,
  ADD COLUMN acknowledged_at        timestamptz,                    -- "I have seen it", not "I agree"
  ADD COLUMN employee_comment       text,
  ADD COLUMN hr_review_requested_at timestamptz,
  ADD COLUMN hr_review_outcome      text CHECK (hr_review_outcome IN ('reopened','upheld')),
  ADD COLUMN hr_review_reason       text,
  ADD COLUMN hr_review_decided_by   uuid REFERENCES platform.app_user,
  ADD COLUMN rating_mode            text CHECK (rating_mode IN ('rated','not_rated','development_only','agreement_form')),
  ADD COLUMN rating_mode_source     text,                           -- 'agreement:UA#2:12.3', 'cycle', 'new_hire', 'mid_year', 'organization'
  ADD CONSTRAINT review_hr_outcome_reason CHECK (hr_review_outcome IS NULL OR (hr_review_decided_by IS NOT NULL AND coalesce(length(btrim(hr_review_reason)), 0) > 0)),
  ADD CONSTRAINT review_hr_outcome_requested CHECK (hr_review_outcome IS NULL OR hr_review_requested_at IS NOT NULL),
  ADD CONSTRAINT review_signed_seen CHECK (status NOT IN ('signed','closed') OR acknowledged_at IS NOT NULL OR released_at IS NULL);
-- Every new review states how it is rated (the API reads the collective agreement, the cycle, the review type and the
-- hire date: docs/28 §4.2, §4.3, §9.1). Reviews written before this migration were rated under the earlier rules and
-- keep their ratings (FB-038).
UPDATE talent.review SET rating_mode = 'rated' WHERE rating_mode IS NULL;   -- fallback: FB-038
ALTER TABLE talent.review ALTER COLUMN rating_mode SET NOT NULL,
  ADD CONSTRAINT review_rating_mode_source CHECK (rating_mode = 'rated' OR rating_mode_source IS NOT NULL);

ALTER TABLE talent.review_section
  ADD COLUMN goal_score       numeric(4,2),
  ADD COLUMN competency_score numeric(4,2),
  ADD COLUMN suggested_rating numeric(4,2),   -- from the cycle's weights, rounded to the scale
  ADD COLUMN rating_reason    text,           -- why the manager's rating differs from the suggestion
  ADD COLUMN days_worked      integer CHECK (days_worked >= 0),   -- days worked in the position in the cycle, protected leave not counted
  ADD COLUMN changed_by       uuid REFERENCES platform.app_user,
  ADD COLUMN change_reason    text,
  ADD COLUMN section_period   daterange;      -- the part of the cycle this section covers; empty means the whole cycle
-- When someone changes manager or position during the cycle, the previous manager rates their own period (docs/28 §6.3):
-- one position can have a section per period, never two for the same days
ALTER TABLE talent.review_section DROP CONSTRAINT review_section_review_id_assignment_id_key,
  ADD CONSTRAINT review_section_one_per_period
  EXCLUDE USING gist (review_id WITH =, assignment_id WITH =, (coalesce(section_period, '(,)'::daterange)) WITH &&);

CREATE TABLE talent.rating_history (
  tenant_id   uuid NOT NULL,
  history_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section_id  uuid NOT NULL REFERENCES talent.review_section,
  stage       text NOT NULL CHECK (stage IN ('calibration','after_final')),
  old_score   numeric(4,2),
  new_score   numeric(4,2),
  changed_by  uuid REFERENCES platform.app_user,
  reason      text NOT NULL,
  changed_at  timestamptz NOT NULL DEFAULT now()
);

-- Why a review cannot carry ratings, or NULL when it can: the review's rating mode (an agreement that forbids ratings,
-- development-only, the agreement's own form), a mid-year review, or a person hired in the last months of the cycle
CREATE FUNCTION talent.rating_blocked(p_review uuid) RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE r talent.review; cat text; c talent.review_cycle; hired date;
BEGIN
  SELECT * INTO r FROM talent.review WHERE review_id = p_review;
  IF r.rating_mode <> 'rated' THEN
    RETURN format('the review is %s (%s)', replace(r.rating_mode, '_', ' '), r.rating_mode_source);
  END IF;
  SELECT v.category INTO cat FROM core.list_value v WHERE v.tenant_id = r.tenant_id AND v.list_code = 'review_kind' AND v.code = r.kind;
  IF cat = 'mid_year' THEN
    RETURN 'a mid-year review records progress and comments only';
  END IF;
  SELECT * INTO c FROM talent.review_cycle WHERE tenant_id = r.tenant_id AND code = r.cycle_code;
  IF FOUND AND cat = 'annual' THEN
    SELECT min(lower(v.valid_period)) INTO hired FROM core.employment_version v WHERE v.employment_id = r.employment_id AND upper_inf(v.sys_period);
    IF hired >= (upper(c.period) - make_interval(months => c.new_hire_no_rating_months))::date THEN
      RETURN format('hired on %s, within the last %s months of the cycle: goals, no rating', hired, c.new_hire_no_rating_months);
    END IF;
  END IF;
  RETURN NULL;
END $$;

-- A section is rated only after the minimum days worked; a rating that differs from CanDo's suggestion says why;
-- changes in calibration and after release are reasoned and kept
CREATE FUNCTION talent.check_section_rating() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r talent.review; st text; why text;
BEGIN
  SELECT * INTO r FROM talent.review WHERE review_id = NEW.review_id;
  IF NEW.rating_score IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.rating_score IS DISTINCT FROM OLD.rating_score) THEN
    why := talent.rating_blocked(NEW.review_id);
    IF why IS NOT NULL THEN
      RAISE EXCEPTION 'RATING_NOT_ALLOWED: %', why USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.days_worked IS NULL OR NEW.days_worked < r.min_section_days THEN
      RAISE EXCEPTION 'SECTION_TOO_SHORT_TO_RATE: % days worked in the position; a section is rated from % days, comments only before', NEW.days_worked, r.min_section_days
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.suggested_rating IS NOT NULL AND NEW.rating_score <> NEW.suggested_rating AND coalesce(length(btrim(NEW.rating_reason)), 0) = 0 THEN
      RAISE EXCEPTION 'RATING_REASON_REQUIRED: the rating differs from the suggested %; say why', NEW.suggested_rating USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.rating_score IS DISTINCT FROM OLD.rating_score THEN
    st := CASE WHEN r.status = 'calibration' THEN 'calibration'
               WHEN r.status IN ('released','signed','closed') THEN 'after_final' END;
    IF st IS NOT NULL THEN
      IF NEW.changed_by IS NULL OR coalesce(length(btrim(NEW.change_reason)), 0) = 0
         OR (NEW.changed_by IS NOT DISTINCT FROM OLD.changed_by AND NEW.change_reason IS NOT DISTINCT FROM OLD.change_reason) THEN
        RAISE EXCEPTION 'RATING_CHANGE_REASON_REQUIRED: a rating changed in calibration or after release names who changed it and why' USING ERRCODE = 'check_violation';
      END IF;
      INSERT INTO talent.rating_history (tenant_id, section_id, stage, old_score, new_score, changed_by, reason)
        VALUES (NEW.tenant_id, NEW.section_id, st, OLD.rating_score, NEW.rating_score, NEW.changed_by, NEW.change_reason);
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER review_section_rating BEFORE INSERT OR UPDATE ON talent.review_section
  FOR EACH ROW EXECUTE FUNCTION talent.check_section_rating();

-- The user who is the employee of a review, and the user who wrote it
CREATE FUNCTION talent.review_employee_user(p_review uuid) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT u.user_id FROM talent.review r JOIN core.employment e ON e.employment_id = r.employment_id
    JOIN platform.app_user u ON u.tenant_id = r.tenant_id AND u.person_id = e.person_id
   WHERE r.review_id = p_review LIMIT 1
$$;
CREATE FUNCTION talent.review_reviewer_user(p_review uuid) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT u.user_id FROM talent.review r JOIN core.assignment a ON a.assignment_id = r.reviewer_assignment_id
    JOIN core.employment e ON e.employment_id = a.employment_id
    JOIN platform.app_user u ON u.tenant_id = r.tenant_id AND u.person_id = e.person_id
   WHERE r.review_id = p_review LIMIT 1
$$;

-- Release: calibration first where the cycle uses it; the one-up route; HR where there is a concern (docs/28 §5)
CREATE FUNCTION talent.check_review_release() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cal boolean; reviewer uuid; le uuid; hr_concerns text[];
BEGIN
  IF NEW.status = 'released' AND (TG_OP = 'INSERT' OR OLD.status <> 'released') THEN
    SELECT c.calibration INTO cal FROM talent.review_cycle c WHERE c.tenant_id = NEW.tenant_id AND c.code = NEW.cycle_code;
    IF cal IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: review cycle % is not set up', NEW.cycle_code USING ERRCODE = 'check_violation';
    END IF;
    IF cal AND NEW.calibrated_at IS NULL THEN
      RAISE EXCEPTION 'CALIBRATION_REQUIRED: the cycle calibrates ratings before they are released' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM talent.review_section s WHERE s.review_id = NEW.review_id AND s.rating_score IS NOT NULL)
       AND talent.rating_blocked(NEW.review_id) IS NOT NULL THEN
      RAISE EXCEPTION 'RATING_NOT_ALLOWED: %', talent.rating_blocked(NEW.review_id) USING ERRCODE = 'check_violation';
    END IF;
    reviewer := talent.review_reviewer_user(NEW.review_id);
    IF reviewer IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a review is released with its reviewing manager' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.release_route_id IS NULL OR NOT platform.route_complete(NEW.release_route_id, 'performance_review', NEW.review_id, reviewer, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the one-up look before release is not complete' USING ERRCODE = 'check_violation';
    END IF;
    SELECT e.legal_entity_id INTO le FROM core.employment e WHERE e.employment_id = NEW.employment_id;
    SELECT array_agg(c) INTO hr_concerns FROM unnest(NEW.concerns) c
     WHERE platform.setting(NEW.tenant_id, 'performance.hr_review_concerns', current_date, le) ? c;
    IF hr_concerns IS NOT NULL AND (NEW.hr_reviewed_by IS NULL OR NEW.hr_reviewed_at IS NULL OR NEW.hr_reviewed_by IS NOT DISTINCT FROM reviewer) THEN
      RAISE EXCEPTION 'HR_REVIEW_REQUIRED: HR looks at this review before release (%)', array_to_string(hr_concerns, ', ') USING ERRCODE = 'check_violation';
    END IF;
    NEW.released_at := coalesce(NEW.released_at, now());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER review_release_check BEFORE INSERT OR UPDATE ON talent.review
  FOR EACH ROW EXECUTE FUNCTION talent.check_review_release();

-- -------------------------------------------------------------------------------------
-- 5. Feedback, 360° reviews and check-ins (docs/28 §7)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.feedback_request (
  tenant_id     uuid NOT NULL,
  request_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_employment_id uuid NOT NULL REFERENCES core.employment,
  cycle_code    text,
  kind          text NOT NULL CHECK (kind IN ('360','ad_hoc')),
  purpose       text NOT NULL CHECK (purpose IN ('development','rating')),
  requested_by  uuid NOT NULL REFERENCES platform.app_user,
  status        text NOT NULL CHECK (status IN ('open','closed'))
);
CREATE TABLE talent.feedback_rater (
  tenant_id       uuid NOT NULL,
  rater_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      uuid NOT NULL REFERENCES talent.feedback_request,
  rater_person_id uuid NOT NULL REFERENCES core.person,
  rater_group     text NOT NULL CHECK (rater_group IN ('manager','peer','direct_report','other')),
  nominated_by    uuid NOT NULL REFERENCES platform.app_user,     -- the employee, the manager or someone else
  status          text NOT NULL CHECK (status IN ('invited','submitted','declined')),
  answers         jsonb,
  submitted_at    timestamptz,
  UNIQUE (request_id, rater_person_id),
  CONSTRAINT feedback_submitted CHECK ((status = 'submitted') = (answers IS NOT NULL AND submitted_at IS NOT NULL))
);

CREATE FUNCTION talent.check_feedback_request() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE use text;
BEGIN
  IF NEW.purpose = 'rating' THEN
    SELECT c.feedback_360_use INTO use FROM talent.review_cycle c WHERE c.tenant_id = NEW.tenant_id AND c.code = NEW.cycle_code;
    IF use IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: feedback that informs ratings belongs to a review cycle' USING ERRCODE = 'check_violation';
    END IF;
    IF use <> 'informs_ratings' THEN
      RAISE EXCEPTION 'FEEDBACK_DEVELOPMENT_ONLY: this cycle uses 360° results for development only' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER feedback_request_check BEFORE INSERT OR UPDATE ON talent.feedback_request
  FOR EACH ROW EXECUTE FUNCTION talent.check_feedback_request();

CREATE FUNCTION talent.check_feedback_rater() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE subj uuid; le uuid; mx int; n int;
BEGIN
  SELECT e.person_id, e.legal_entity_id INTO subj, le FROM talent.feedback_request q JOIN core.employment e ON e.employment_id = q.subject_employment_id
   WHERE q.request_id = NEW.request_id;
  IF NEW.rater_person_id = subj THEN
    RAISE EXCEPTION 'SELF_REVIEW: the person reviewed is not one of their own raters' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.rater_group <> 'manager' AND (TG_OP = 'INSERT' OR NEW.rater_group IS DISTINCT FROM OLD.rater_group) THEN
    mx := platform.setting_number(NEW.tenant_id, 'performance.rater_group_max', current_date, le)::int;
    SELECT count(*) INTO n FROM talent.feedback_rater r WHERE r.request_id = NEW.request_id AND r.rater_group = NEW.rater_group
       AND r.status <> 'declined' AND r.rater_id <> NEW.rater_id;
    IF n + 1 > mx THEN
      RAISE EXCEPTION 'FEEDBACK_RATERS_OVER_MAX: a % group has at most % raters', NEW.rater_group, mx USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER feedback_rater_check BEFORE INSERT OR UPDATE ON talent.feedback_rater
  FOR EACH ROW EXECUTE FUNCTION talent.check_feedback_rater();

-- Whether a rater group's answers can be shown: the manager's always (never anonymous); others only from the minimum
CREATE FUNCTION talent.feedback_group_visible(p_request uuid, p_group text) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT p_group = 'manager' OR
         (SELECT count(*) FROM talent.feedback_rater r WHERE r.request_id = p_request AND r.rater_group = p_group AND r.status = 'submitted')
         >= (SELECT platform.setting_number(q.tenant_id, 'performance.rater_group_min', current_date, e.legal_entity_id)
               FROM talent.feedback_request q JOIN core.employment e ON e.employment_id = q.subject_employment_id WHERE q.request_id = p_request)
$$;

CREATE TABLE talent.checkin (
  tenant_id              uuid NOT NULL,
  checkin_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_assignment_id uuid NOT NULL REFERENCES core.assignment,
  manager_assignment_id  uuid NOT NULL REFERENCES core.assignment,
  held_on                date NOT NULL,
  shared_notes           text,
  private_notes          text,                -- the author and HR only
  actions                jsonb NOT NULL DEFAULT '[]'::jsonb,
  CONSTRAINT checkin_two_people CHECK (employee_assignment_id <> manager_assignment_id)
);

-- A team can nudge more or less often than the organization (docs/28 §7.4)
CREATE TABLE talent.checkin_rule (
  tenant_id    uuid NOT NULL,
  org_unit_id  uuid NOT NULL REFERENCES core.org_unit,
  nudge_days   integer NOT NULL CHECK (nudge_days >= 1),
  PRIMARY KEY (tenant_id, org_unit_id)
);
-- Whether the manager should be nudged: no check-in for this position within the team's or the organization's days
CREATE FUNCTION talent.checkin_due(p_employee_assignment uuid, p_on date) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT coalesce(max(c.held_on), '-infinity'::date) <= p_on - coalesce(
           (SELECT r.nudge_days FROM talent.checkin_rule r WHERE r.tenant_id = a.tenant_id AND r.org_unit_id = av.org_unit_id),
           platform.setting_number(a.tenant_id, 'performance.checkin_nudge_days', p_on, e.legal_entity_id)::int)
    FROM core.assignment a
    JOIN core.employment e ON e.employment_id = a.employment_id
    JOIN core.assignment_version av ON av.assignment_id = a.assignment_id AND av.valid_period @> p_on AND upper_inf(av.sys_period)
    LEFT JOIN talent.checkin c ON c.employee_assignment_id = a.assignment_id AND c.held_on <= p_on
   WHERE a.assignment_id = p_employee_assignment
   GROUP BY a.tenant_id, av.org_unit_id, e.legal_entity_id
$$;

-- The employee's own view of their strengths and areas to develop, beside the manager's (docs/28 §4.1)
CREATE TABLE talent.strengths_view (
  tenant_id      uuid NOT NULL,
  view_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id  uuid NOT NULL REFERENCES core.employment,
  cycle_code     text NOT NULL,
  author         text NOT NULL CHECK (author IN ('employee','manager')),
  written_by     uuid NOT NULL REFERENCES platform.app_user,
  strengths      text,
  areas_to_develop text,
  written_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (employment_id, cycle_code, author)
);

-- -------------------------------------------------------------------------------------
-- 6. Performance improvement plans (docs/28 §8)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.pip (
  tenant_id       uuid NOT NULL,
  pip_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id   uuid NOT NULL REFERENCES core.employment,
  assignment_id   uuid NOT NULL REFERENCES core.assignment,
  created_by      uuid NOT NULL REFERENCES platform.app_user,
  causes_ruled_out jsonb NOT NULL,            -- {"expectations":true,"training":true,"workload":true,"accommodation":true}
  gaps            jsonb NOT NULL,
  standards       text NOT NULL,
  measures        text NOT NULL,
  support         text NOT NULL,
  start_on        date NOT NULL,
  end_on          date,                       -- filled from performance.pip_default_days
  protected_ground_possible boolean NOT NULL,
  route_id        uuid REFERENCES platform.workflow_route,
  employee_acknowledged_at timestamptz,
  status          text NOT NULL CHECK (status IN ('draft','submitted','approved','active','extended','completed','cancelled')),
  extension_reason text,
  outcome         text CHECK (outcome IN ('successful','extended','role_change','termination','closed')),
  outcome_reason  text,
  CONSTRAINT pip_dates CHECK (end_on IS NULL OR end_on > start_on),
  CONSTRAINT pip_extension_reason CHECK (status <> 'extended' OR coalesce(length(btrim(extension_reason)), 0) > 0),
  CONSTRAINT pip_outcome_reason CHECK (outcome IS NULL OR coalesce(length(btrim(outcome_reason)), 0) > 0)
);

CREATE FUNCTION talent.check_pip() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le uuid;
BEGIN
  SELECT e.legal_entity_id INTO le FROM core.employment e WHERE e.employment_id = NEW.employment_id;
  IF NEW.end_on IS NULL THEN
    NEW.end_on := NEW.start_on + platform.setting_number(NEW.tenant_id, 'performance.pip_default_days', NEW.start_on, le)::int;
  END IF;
  IF NEW.status <> 'draft' AND (TG_OP = 'INSERT' OR OLD.status = 'draft') THEN
    IF NOT coalesce((NEW.causes_ruled_out ->> 'expectations')::boolean AND (NEW.causes_ruled_out ->> 'training')::boolean
                    AND (NEW.causes_ruled_out ->> 'workload')::boolean AND (NEW.causes_ruled_out ->> 'accommodation')::boolean, false) THEN
      RAISE EXCEPTION 'PIP_CAUSES_NOT_REVIEWED: rule out unclear expectations, training gaps, workload and accommodation needs first' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.status IN ('approved','active') AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('approved','active','extended')) THEN
    IF EXISTS (SELECT 1 FROM timeleave.leave_request r
                 JOIN timeleave.leave_type lt ON lt.tenant_id = r.tenant_id AND lt.leave_type_code = r.leave_type_code
                WHERE r.employment_id = NEW.employment_id AND r.status IN ('approved','taken','partially_approved')
                  AND (lt.statutory OR lt.reason_restricted OR r.protected_reason IS NOT NULL)
                  AND r.period @> NEW.start_on::timestamptz) THEN
      RAISE EXCEPTION 'PIP_DURING_PROTECTED_LEAVE: no improvement plan starts while the employee is on a protected leave' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.protected_ground_possible AND NOT platform.caution_cleared(NEW.tenant_id, 'performance.pip_protected_ground', 'pip', NEW.pip_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: performance.pip_protected_ground' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'pip', NEW.pip_id, NEW.created_by, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: HR approves the plan through the organization''s route' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.status = 'extended' AND OLD.status <> 'extended' AND NEW.end_on <= OLD.end_on THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: an extension sets a later end date' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'active' AND NEW.employee_acknowledged_at IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: the employee acknowledges the plan before it starts' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pip_check BEFORE INSERT OR UPDATE ON talent.pip
  FOR EACH ROW EXECUTE FUNCTION talent.check_pip();

CREATE TABLE talent.pip_meeting (
  tenant_id      uuid NOT NULL,
  meeting_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pip_id         uuid NOT NULL REFERENCES talent.pip,
  held_on        date NOT NULL,
  representation text NOT NULL CHECK (representation IN ('union_representative','support_person','offered_declined','not_required')),
  notes          text
);

-- -------------------------------------------------------------------------------------
-- 7. Adverse records and sunset clauses (docs/28 §9.2)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.adverse_record (
  tenant_id     uuid NOT NULL,
  record_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  subject_type  text NOT NULL CHECK (subject_type IN ('review','pip','other')),
  subject_id    uuid NOT NULL,
  recorded_on   date NOT NULL,
  basis         text NOT NULL CHECK (basis IN ('agreement','organization')),
  agreement_id  text,
  sunset_on     date,                      -- the agreement's period, or the organization's months; none when neither sets one
  FOREIGN KEY (tenant_id, agreement_id) REFERENCES core.agreement (tenant_id, agreement_id),
  CONSTRAINT adverse_agreement CHECK ((basis = 'agreement') = (agreement_id IS NOT NULL)),
  CONSTRAINT adverse_agreement_sunset CHECK (basis <> 'agreement' OR sunset_on IS NOT NULL),
  CONSTRAINT adverse_sunset_after CHECK (sunset_on IS NULL OR sunset_on > recorded_on)
);
CREATE FUNCTION talent.check_adverse_record() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le uuid; m numeric;
BEGIN
  IF NEW.basis = 'organization' AND NEW.sunset_on IS NULL THEN
    SELECT e.legal_entity_id INTO le FROM core.employment e WHERE e.employment_id = NEW.employment_id;
    m := (platform.setting(NEW.tenant_id, 'performance.non_union_sunset', NEW.recorded_on, le) ->> 'months')::numeric;
    IF m IS NOT NULL THEN
      NEW.sunset_on := (NEW.recorded_on + make_interval(months => m::int))::date;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER adverse_record_check BEFORE INSERT OR UPDATE ON talent.adverse_record
  FOR EACH ROW EXECUTE FUNCTION talent.check_adverse_record();

-- Whether a record still counts (managers see it and decisions may use it); after its sunset only HR keeps it
CREATE FUNCTION talent.adverse_record_in_force(p_subject_type text, p_subject_id uuid, p_on date) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (SELECT 1 FROM talent.adverse_record a
                      WHERE a.subject_type = p_subject_type AND a.subject_id = p_subject_id
                        AND a.sunset_on IS NOT NULL AND p_on >= a.sunset_on)
$$;

-- -------------------------------------------------------------------------------------
-- 8. Routes, caution, no self-approval, text fields, row-level security
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.workflow_route DROP CONSTRAINT IF EXISTS workflow_route_subject_type_check;
ALTER TABLE platform.workflow_route ADD CONSTRAINT workflow_route_subject_type_check
  CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution',
                          'pay_run','voluntary_deduction','banked_time_payout',
                          'comp_philosophy','pay_structure_version','comp_decision','incentive_payout','salary_disclosure',
                          'carrier_invoice','timesheet','performance_review','pip'));

INSERT INTO ref.workflow_route_starter (code, subject_type, name_en, name_fr, conditions, priority, decision_ref) VALUES
 ('performance_review', 'performance_review', 'Review before release', 'Examen avant diffusion', '{}', 10, 'docs/28 §5.3 (R3.2)'),
 ('pip', 'pip', 'Performance improvement plan approval', 'Approbation du plan d''amélioration du rendement', '{}', 10, 'docs/28 §8.1 (R6.1)');
INSERT INTO ref.workflow_route_step_starter (route_code, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr) VALUES
 ('performance_review', 1, 'requester_manager', NULL, 'any', 1, 'One-up look by the reviewing manager''s own manager', 'Examen par le gestionnaire du gestionnaire évaluateur'),
 ('pip', 1, 'capability', 'hr', 'any', 1, 'HR approval', 'Approbation des RH');

INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('performance.pip_protected_ground', 'performance', 'A protected ground may be involved', 'Un motif protégé pourrait être en cause',
  'The performance issue may be linked to a protected ground, such as a disability or family status. Human rights law requires the employer to consider accommodation first. Record the accommodation review and why the plan should go ahead.',
  'Le problème de rendement pourrait être lié à un motif protégé, comme un handicap ou la situation de famille. La législation sur les droits de la personne oblige l''employeur à envisager d''abord des mesures d''adaptation. Consignez l''examen des mesures d''adaptation et la raison pour laquelle le plan devrait aller de l''avant.',
  true, true, 'docs/28 §8.3 (R6.3)');

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
      ('talent','rating_scale'), ('talent','review_cycle'), ('talent','goal'), ('talent','goal_change'), ('talent','rating_history'),
      ('talent','feedback_request'), ('talent','feedback_rater'), ('talent','checkin'), ('talent','checkin_rule'), ('talent','strengths_view'),
      ('talent','pip'), ('talent','pip_meeting'), ('talent','adverse_record')) AS x(s, t) LOOP
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
      RAISE NOTICE 'organization %: starter performance routes not copied because % is required for its data; add them with their texts (docs/28 §11)', t.tenant_id, langs;
    END IF;
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT, INSERT and UPDATE on the new tenant tables and EXECUTE on the new
-- functions. Private check-in notes, improvement plans and calibration notes are for the author, HR and the manager
-- chain only; each position's manager sees only their own section (requirements/07 Security, docs/28 §6.4).
