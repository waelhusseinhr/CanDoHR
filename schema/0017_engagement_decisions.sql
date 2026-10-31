-- =====================================================================================
-- Migration 0017 · Engagement and recognition decisions (docs/31)
--
-- Applies the owner's Module 10 review of 29 and 30 October 2026 (claude/review/10-engagement-recognition-decisions.md).
-- CanDo's own survey tool, confidential by default with an anonymous option, results only for groups large enough,
-- comments read by HR, recognition private until its recipient makes it public, CRA's gift and award limits tracked
-- for payroll, announcements with read receipts and SMS only for emergencies, an anonymous feedback box.
--
--   §1  Settings, and whether each employer is covered by a freedom-of-information law
--   §2  Surveys: questions, escalation contacts, invitations, submissions without identity, comment flags, imports
--   §3  Results with suppression, and action plans
--   §4  Recognition, points budgets, rewards and CRA's gift and award limits
--   §5  Service milestones and celebrations
--   §6  Announcements, ideas and the anonymous feedback box
--   §7  Wellbeing resources, the directory and the observances calendar
--   §8  Routes, cautions, no self-approval, text fields, row-level security
--
-- Run after 0016.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/31 §2.1)
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('engagement.default_mode', 'engagement', 'text', '["confidential","anonymous"]', '"confidential"', ARRAY['tenant','legal_entity'], false,
  'How a new survey keeps answers: confidential (linked to HR details, shown only as group results) or fully anonymous (only the unit kept). An employer covered by a freedom-of-information law always runs anonymous surveys.',
  'docs/31 §3.2 (R1.3)', 'decided', NULL, NULL, NULL),
 ('engagement.min_group_size', 'engagement', 'integer', NULL, '5', ARRAY['tenant'], false,
  'Smallest group whose survey results are shown, by unit or any other breakdown except self-identified groups (privacy.min_group_size_self_id, 10).',
  'docs/31 §3.3 (R1.4)', 'decided', 3, NULL, NULL),
 ('engagement.ai_comment_themes', 'engagement', 'boolean', NULL, 'false', ARRAY['tenant'], false,
  'AI summaries of the themes in open comments, only above the minimum group. Until switched on, themes come from fixed keyword rules.',
  'docs/31 §4.2 (R1.2)', 'decided', NULL, NULL, NULL),
 ('engagement.action_plan_days', 'engagement', 'integer', NULL, '60', ARRAY['tenant','legal_entity'], false,
  'Days after a survey closes by which each manager with results agrees actions with the team.',
  'docs/31 §4.3 (R3.3)', 'decided', 1, NULL, NULL),
 ('engagement.lifecycle_surveys', 'engagement', 'text_array', NULL, '["onboarding_30","onboarding_90","exit","promotion","return_from_leave"]', ARRAY['tenant','legal_entity'], false,
  'Events that send a lifecycle survey automatically.',
  'docs/31 §3.6 (R3.4)', 'decided', NULL, NULL, NULL),
 ('recognition.milestone_years', 'recognition', 'integer_array', NULL, '[5,10,15,20,25,30,35,40,45,50]', ARRAY['tenant','legal_entity'], false,
  'Years of continuous service celebrated as milestones.',
  'docs/31 §6.3 (R5.1)', 'decided', NULL, NULL, NULL),
 ('recognition.milestone_reminder_days', 'recognition', 'integer', NULL, '30', ARRAY['tenant','legal_entity'], false,
  'Days before a service milestone when the manager is reminded.',
  'docs/31 §6.3 (R5.1)', 'decided', 0, NULL, NULL),
 ('announcements.read_reminder_days', 'announcements', 'integer_array', NULL, '[3,7]', ARRAY['tenant','legal_entity'], false,
  'Days after an important notice is published when people who have not read it are reminded.',
  'docs/31 §7.1 (R6.1)', 'decided', NULL, NULL, NULL),
 ('announcements.sms_for_urgent', 'announcements', 'boolean', NULL, 'true', ARRAY['tenant','legal_entity'], false,
  'Urgent alerts (site closures, weather, safety incidents) also go by SMS to everyone with a phone number; the organization pays per message. SMS is never used for anything else.',
  'docs/31 §7.2 (R6.2)', 'decided', NULL, NULL, NULL);

-- Whether an employer is covered by a freedom-of-information law, recorded on its version (docs/31 §3.4)
ALTER TABLE core.legal_entity_version
  ADD COLUMN information_access_covered boolean,
  ADD COLUMN information_access_law text,
  ADD CONSTRAINT legal_entity_information_access_law CHECK (information_access_covered IS NOT TRUE OR coalesce(length(btrim(information_access_law)), 0) > 0);

CREATE FUNCTION core.information_access_covered(p_legal_entity uuid, p_on date) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT v.information_access_covered FROM core.legal_entity_version v
   WHERE v.legal_entity_id = p_legal_entity AND v.valid_period @> p_on AND upper_inf(v.sys_period)
$$;

-- -------------------------------------------------------------------------------------
-- 2. Surveys (docs/31 §3)
-- -------------------------------------------------------------------------------------
COMMENT ON TABLE talent.survey_response IS 'Read-only after 0017: survey answers are in talent.survey_submission, with no person link and no time of day (docs/31 §3.2).';

CREATE TABLE talent.survey (
  tenant_id      uuid NOT NULL REFERENCES platform.tenant,
  survey_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code           text NOT NULL,
  kind           text NOT NULL CHECK (kind IN ('census','pulse','lifecycle','enps','inclusion','ad_hoc')),
  lifecycle_event text CHECK (lifecycle_event IN ('onboarding_30','onboarding_90','exit','promotion','return_from_leave')),
  name_en        text NOT NULL,
  name_fr        text,
  source         text NOT NULL CHECK (source IN ('cando','uploaded_questions','imported_results')),
  source_document_id uuid REFERENCES platform.document,     -- the uploaded questionnaire or results file
  mode           text NOT NULL CHECK (mode IN ('confidential','anonymous')),   -- filled from engagement.default_mode, or anonymous (§3.4)
  legal_entity_id uuid REFERENCES core.legal_entity,        -- NULL: the whole organization
  audience       jsonb NOT NULL,                            -- orgUnits, locations, agreements, legalEntities, employmentTypes
  min_group_size integer,                                   -- raises the organization's minimum for this survey only
  union_consultation_required boolean NOT NULL,             -- from the agreement library (Step 7)
  opens_on       date,
  closes_on      date,
  status         text NOT NULL CHECK (status IN ('draft','open','closed')),
  created_by     uuid NOT NULL REFERENCES platform.app_user,
  UNIQUE (tenant_id, code),
  CONSTRAINT survey_lifecycle_event CHECK ((kind = 'lifecycle') = (lifecycle_event IS NOT NULL)),
  CONSTRAINT survey_upload_document CHECK (source = 'cando' OR source_document_id IS NOT NULL),
  CONSTRAINT survey_dates CHECK (closes_on IS NULL OR opens_on IS NULL OR closes_on >= opens_on)
);

CREATE TABLE talent.survey_question (
  tenant_id  uuid NOT NULL,
  question_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id  uuid NOT NULL REFERENCES talent.survey,
  item_no    integer NOT NULL CHECK (item_no >= 1),
  kind       text NOT NULL CHECK (kind IN ('likert_5','enps','choice','multi_choice','ranking','open_text','yes_no')),
  text_en    text NOT NULL,
  text_fr    text,
  choices    jsonb,
  driver     text,                                -- the question library's driver (leadership, workload, belonging ...)
  source     text NOT NULL CHECK (source IN ('library','organization','partner')),
  UNIQUE (survey_id, item_no),
  CONSTRAINT survey_question_choices CHECK ((kind IN ('choice','multi_choice','ranking')) = (choices IS NOT NULL))
);

-- The HR contact a flagged comment goes to, without the writer's identity (docs/31 §3.8)
CREATE TABLE talent.survey_escalation_contact (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  contact_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES platform.app_user,
  legal_entity_id uuid REFERENCES core.legal_entity,
  active      boolean NOT NULL
);

CREATE FUNCTION talent.survey_entities(p_survey talent.survey) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
  SELECT p_survey.legal_entity_id WHERE p_survey.legal_entity_id IS NOT NULL
  UNION ALL
  SELECT l.legal_entity_id FROM core.legal_entity l WHERE p_survey.legal_entity_id IS NULL AND l.tenant_id = p_survey.tenant_id
$$;

CREATE FUNCTION talent.check_survey() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE on_ date := coalesce(NEW.opens_on, current_date); unknown int; covered int; k text; org_min numeric;
BEGIN
  SELECT count(*) FILTER (WHERE c IS NULL), count(*) FILTER (WHERE c)
    INTO unknown, covered
    FROM (SELECT core.information_access_covered(e, on_) AS c FROM talent.survey_entities(NEW) e) x;
  IF unknown > 0 THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: record whether each employer in the survey is covered by a freedom-of-information law' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.mode IS NULL THEN
    NEW.mode := CASE WHEN covered > 0 THEN 'anonymous'
                     ELSE platform.setting_text(NEW.tenant_id, 'engagement.default_mode', on_, NEW.legal_entity_id) END;
  END IF;
  IF covered > 0 AND NEW.mode <> 'anonymous' THEN
    RAISE EXCEPTION 'SURVEY_MODE_NOT_ALLOWED: an employer covered by a freedom-of-information law runs anonymous surveys only' USING ERRCODE = 'check_violation';
  END IF;
  FOR k IN SELECT jsonb_object_keys(NEW.audience) LOOP
    IF k NOT IN ('orgUnits','locations','agreements','legalEntities','employmentTypes') OR jsonb_typeof(NEW.audience -> k) <> 'array' THEN
      RAISE EXCEPTION 'AUDIENCE_SCOPE_UNKNOWN: % is not an audience scope (each takes a list)', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  org_min := platform.setting_number(NEW.tenant_id, 'engagement.min_group_size');
  IF NEW.min_group_size IS NOT NULL AND NEW.min_group_size < org_min THEN
    RAISE EXCEPTION 'SURVEY_MIN_GROUP_BELOW_ORGANIZATION: a survey can raise the minimum group of %, never lower it', org_min USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status <> 'draft' AND (NEW.mode, NEW.audience, NEW.kind, NEW.legal_entity_id) IS DISTINCT FROM (OLD.mode, OLD.audience, OLD.kind, OLD.legal_entity_id) THEN
    RAISE EXCEPTION 'SURVEY_LOCKED: a survey that has opened keeps its mode and audience' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'open' AND (TG_OP = 'INSERT' OR OLD.status <> 'open') THEN
    IF NEW.source = 'imported_results' THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: imported results are loaded into a closed survey; nothing is sent' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.opens_on IS NULL OR NEW.closes_on IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a survey opens with its opening and closing dates' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM talent.survey_question q WHERE q.survey_id = NEW.survey_id) THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a survey opens with its questions' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM talent.survey_question q WHERE q.survey_id = NEW.survey_id AND q.kind = 'open_text')
       AND NOT EXISTS (SELECT 1 FROM talent.survey_escalation_contact c WHERE c.tenant_id = NEW.tenant_id AND c.active
                         AND (c.legal_entity_id IS NULL OR c.legal_entity_id = NEW.legal_entity_id)) THEN
      RAISE EXCEPTION 'ESCALATION_CONTACT_REQUIRED: name the HR contact flagged comments go to before a survey with open comments opens'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.union_consultation_required AND NOT platform.caution_cleared(NEW.tenant_id, 'engagement.union_consultation', 'survey', NEW.survey_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: engagement.union_consultation' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER survey_check BEFORE INSERT OR UPDATE ON talent.survey FOR EACH ROW EXECUTE FUNCTION talent.check_survey();

CREATE FUNCTION talent.check_survey_question() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM talent.survey s WHERE s.survey_id = NEW.survey_id AND s.status <> 'draft') THEN
    RAISE EXCEPTION 'SURVEY_LOCKED: questions are fixed once the survey opens' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER survey_question_check BEFORE INSERT OR UPDATE ON talent.survey_question FOR EACH ROW EXECUTE FUNCTION talent.check_survey_question();

-- Who was invited, to send reminders and count participation by unit; never shown per person (docs/31 §3.5)
CREATE TABLE talent.survey_invitation (
  tenant_id     uuid NOT NULL,
  invitation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id     uuid NOT NULL REFERENCES talent.survey,
  employment_id uuid NOT NULL REFERENCES core.employment,
  org_unit_id   uuid NOT NULL REFERENCES core.org_unit,
  channel       text NOT NULL CHECK (channel IN ('email','app')),
  sent_on       date NOT NULL,
  last_reminded_on date,
  responded     boolean NOT NULL,
  UNIQUE (survey_id, employment_id)
);

-- Answers, with no person link and no time of day; confidential surveys keep group attributes, anonymous ones the unit
CREATE TABLE talent.survey_submission (
  tenant_id     uuid NOT NULL,
  submission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id     uuid NOT NULL REFERENCES talent.survey,
  submitted_on  date NOT NULL,
  attributes    jsonb NOT NULL,
  answers       jsonb NOT NULL                -- {"1":4,"2":"text",...} by item number
);
CREATE FUNCTION talent.check_survey_submission() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s talent.survey; k text;
BEGIN
  SELECT * INTO s FROM talent.survey WHERE survey_id = NEW.survey_id;
  IF s.status <> 'open' OR NEW.submitted_on NOT BETWEEN s.opens_on AND s.closes_on THEN
    RAISE EXCEPTION 'SURVEY_NOT_OPEN: answers are taken only while the survey is open' USING ERRCODE = 'check_violation';
  END IF;
  FOR k IN SELECT jsonb_object_keys(NEW.attributes) LOOP
    IF (s.mode = 'anonymous' AND k <> 'orgUnit')
       OR (s.mode = 'confidential' AND k NOT IN ('orgUnit','location','legalEntity','employmentType','tenureBand','careerLevel','unionized','shift','lifecycleEvent','selfId')) THEN
      RAISE EXCEPTION 'SUBMISSION_ATTRIBUTE_NOT_ALLOWED: % is not kept with % answers', k, s.mode USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  FOR k IN SELECT jsonb_object_keys(NEW.answers) LOOP
    IF NOT EXISTS (SELECT 1 FROM talent.survey_question q WHERE q.survey_id = NEW.survey_id AND q.item_no::text = k) THEN
      RAISE EXCEPTION 'ANSWER_UNKNOWN_ITEM: the survey has no question %', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  IF TG_OP = 'UPDATE' THEN
    RAISE EXCEPTION 'SURVEY_LOCKED: answers are never changed once given' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER survey_submission_check BEFORE INSERT OR UPDATE ON talent.survey_submission FOR EACH ROW EXECUTE FUNCTION talent.check_survey_submission();

-- A comment flagged by the keyword rules (rules/engagement), sent without identity to the named contact (docs/31 §3.8)
CREATE TABLE talent.comment_flag (
  tenant_id     uuid NOT NULL,
  flag_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  submission_id uuid NOT NULL REFERENCES talent.survey_submission,
  item_no       integer NOT NULL,
  category      text NOT NULL CHECK (category IN ('harassment','safety','self_harm')),
  comment_text  text NOT NULL,
  contact_id    uuid NOT NULL REFERENCES talent.survey_escalation_contact,
  sent_at       timestamptz NOT NULL,
  status        text NOT NULL CHECK (status IN ('open','handled')),
  handled_note  text,
  CONSTRAINT comment_flag_handled CHECK (status <> 'handled' OR coalesce(length(btrim(handled_note)), 0) > 0)
);

-- Results imported from another survey tool, checked against the same minimum groups (docs/31 §3.1)
CREATE TABLE talent.imported_result (
  tenant_id   uuid NOT NULL,
  result_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id   uuid NOT NULL REFERENCES talent.survey,
  group_key   jsonb NOT NULL,                 -- {"orgUnit": ...} or {"selfId": ...}; never a person
  item_code   text NOT NULL,
  respondents integer NOT NULL CHECK (respondents >= 0),
  average     numeric(8,3),
  favourable_pct numeric(5,2)
);

CREATE FUNCTION talent.survey_min_group(p_survey uuid, p_self_id boolean) RETURNS integer LANGUAGE sql STABLE AS $$
  SELECT greatest(coalesce(s.min_group_size, platform.setting_number(s.tenant_id, 'engagement.min_group_size')::int),
                  CASE WHEN p_self_id THEN platform.setting_number(s.tenant_id, 'privacy.min_group_size_self_id')::int ELSE 0 END)
    FROM talent.survey s WHERE s.survey_id = p_survey
$$;

CREATE FUNCTION talent.check_imported_result() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE src text; k text;
BEGIN
  SELECT source INTO src FROM talent.survey WHERE survey_id = NEW.survey_id;
  IF src <> 'imported_results' THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: imported results belong to a survey whose source is imported results' USING ERRCODE = 'check_violation';
  END IF;
  FOR k IN SELECT jsonb_object_keys(NEW.group_key) LOOP
    IF k NOT IN ('orgUnit','location','legalEntity','employmentType','tenureBand','careerLevel','unionized','shift','selfId','organization') THEN
      RAISE EXCEPTION 'SUBMISSION_ATTRIBUTE_NOT_ALLOWED: % is not a group CanDo shows', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  IF NEW.respondents < talent.survey_min_group(NEW.survey_id, NEW.group_key ? 'selfId') THEN
    RAISE EXCEPTION 'IMPORT_BELOW_MIN_GROUP: a group of % is under the minimum; leave it out of the file', NEW.respondents USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER imported_result_check BEFORE INSERT OR UPDATE ON talent.imported_result FOR EACH ROW EXECUTE FUNCTION talent.check_imported_result();

-- -------------------------------------------------------------------------------------
-- 3. Results with suppression, and action plans (docs/31 §4)
-- -------------------------------------------------------------------------------------
-- Scores for a set of units (NULL: everyone) over the survey or a window of it; nothing when fewer respondents than the
-- minimum, and an item only when enough people answered it
CREATE FUNCTION talent.survey_scores(p_survey uuid, p_units uuid[], p_window daterange)
RETURNS TABLE (item_no integer, respondents integer, average numeric) LANGUAGE sql STABLE AS $$
  WITH sub AS (
    SELECT s.* FROM talent.survey_submission s
     WHERE s.survey_id = p_survey
       AND (p_units IS NULL OR (s.attributes ->> 'orgUnit')::uuid = ANY (p_units))
       AND (p_window IS NULL OR p_window @> s.submitted_on)),
  m AS (SELECT talent.survey_min_group(p_survey, false) AS min_n)
  SELECT q.item_no, count(*)::int, round(avg((sub.answers ->> q.item_no::text)::numeric), 2)
    FROM sub CROSS JOIN m
    JOIN talent.survey_question q ON q.survey_id = p_survey AND q.kind IN ('likert_5','enps','yes_no')
   WHERE sub.answers ? q.item_no::text AND jsonb_typeof(sub.answers -> q.item_no::text) = 'number'
     AND (SELECT count(*) FROM sub) >= m.min_n
   GROUP BY q.item_no, m.min_n
  HAVING count(*) >= m.min_n
$$;

-- A breakdown by one attribute (tenure band, shift, self-identified group ...): each group shown only from its minimum
CREATE FUNCTION talent.survey_breakdown(p_survey uuid, p_attribute text, p_units uuid[])
RETURNS TABLE (grp text, item_no integer, respondents integer, average numeric) LANGUAGE sql STABLE AS $$
  WITH sub AS (
    SELECT s.*, s.attributes ->> p_attribute AS g FROM talent.survey_submission s
     WHERE s.survey_id = p_survey AND s.attributes ? p_attribute
       AND (p_units IS NULL OR (s.attributes ->> 'orgUnit')::uuid = ANY (p_units))),
  sizes AS (SELECT g, count(*) AS n FROM sub GROUP BY g),
  m AS (SELECT talent.survey_min_group(p_survey, p_attribute = 'selfId') AS min_n)
  SELECT sub.g, q.item_no, count(*)::int, round(avg((sub.answers ->> q.item_no::text)::numeric), 2)
    FROM sub JOIN sizes z ON z.g = sub.g CROSS JOIN m
    JOIN talent.survey_question q ON q.survey_id = p_survey AND q.kind IN ('likert_5','enps','yes_no')
   WHERE z.n >= m.min_n AND jsonb_typeof(sub.answers -> q.item_no::text) = 'number'
   GROUP BY sub.g, q.item_no, m.min_n
  HAVING count(*) >= m.min_n
$$;

-- Participation for a set of units, shown only when the invited group reaches the minimum
CREATE FUNCTION talent.survey_participation(p_survey uuid, p_units uuid[])
RETURNS TABLE (invited integer, responded integer) LANGUAGE sql STABLE AS $$
  SELECT count(*)::int, count(*) FILTER (WHERE i.responded)::int
    FROM talent.survey_invitation i
   WHERE i.survey_id = p_survey AND (p_units IS NULL OR i.org_unit_id = ANY (p_units))
  HAVING count(*) >= talent.survey_min_group(p_survey, false)
$$;

CREATE TABLE talent.action_plan (
  tenant_id   uuid NOT NULL,
  plan_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_id   uuid NOT NULL REFERENCES talent.survey,
  org_unit_id uuid REFERENCES core.org_unit,     -- NULL: an organization-wide plan owned by an executive
  owner_user  uuid NOT NULL REFERENCES platform.app_user,
  due_on      date,                              -- filled from engagement.action_plan_days after the survey closes
  status      text NOT NULL CHECK (status IN ('open','agreed','done','cancelled')),
  UNIQUE (survey_id, org_unit_id)
);
CREATE FUNCTION talent.check_action_plan() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s talent.survey;
BEGIN
  SELECT * INTO s FROM talent.survey WHERE survey_id = NEW.survey_id;
  IF NEW.due_on IS NULL THEN
    IF s.closes_on IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: an action plan follows a survey with a closing date' USING ERRCODE = 'check_violation';
    END IF;
    NEW.due_on := s.closes_on + platform.setting_number(NEW.tenant_id, 'engagement.action_plan_days', s.closes_on, s.legal_entity_id)::int;
  END IF;
  IF NEW.status = 'agreed' AND NOT EXISTS (SELECT 1 FROM talent.action_item i WHERE i.plan_id = NEW.plan_id) THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: a plan is agreed with at least one action' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE TABLE talent.action_item (
  tenant_id   uuid NOT NULL,
  item_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id     uuid NOT NULL REFERENCES talent.action_plan,
  description text NOT NULL,
  linked_items integer[] NOT NULL,               -- the survey questions it answers
  owner_user  uuid NOT NULL REFERENCES platform.app_user,
  due_on      date NOT NULL,
  status      text NOT NULL CHECK (status IN ('planned','in_progress','done','dropped')),
  shared_with_team boolean NOT NULL               -- shown to the team as "you said, we did"
);
CREATE TRIGGER action_plan_check BEFORE INSERT OR UPDATE ON talent.action_plan FOR EACH ROW EXECUTE FUNCTION talent.check_action_plan();

-- Plans past their date and not yet agreed: the owner is reminded (docs/31 §4.3)
CREATE FUNCTION talent.action_plans_overdue(p_tenant uuid, p_on date)
RETURNS TABLE (plan_id uuid, owner_user uuid, due_on date) LANGUAGE sql STABLE AS $$
  SELECT p.plan_id, p.owner_user, p.due_on FROM talent.action_plan p
   WHERE p.tenant_id = p_tenant AND p.status = 'open' AND p.due_on < p_on
$$;

-- -------------------------------------------------------------------------------------
-- 4. Recognition, points, rewards and CRA's gift and award limits (docs/31 §5, §6)
-- -------------------------------------------------------------------------------------
INSERT INTO ref.list_definition (list_code, name_en, name_fr, categories, decision_ref) VALUES
 ('recognition_value', 'Values recognition is tied to', 'Valeurs auxquelles la reconnaissance est liée', ARRAY['value'], 'docs/31 §5.1 (R4.1)');

CREATE TABLE talent.points_budget (
  tenant_id   uuid NOT NULL,
  budget_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  holder_user uuid NOT NULL REFERENCES platform.app_user,
  period      daterange NOT NULL,
  points      integer NOT NULL CHECK (points > 0),
  EXCLUDE USING gist (holder_user WITH =, period WITH &&)
);

CREATE TABLE talent.recognition (
  tenant_id     uuid NOT NULL,
  recognition_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id      uuid NOT NULL,                  -- one message to several people shares a batch
  giver_user    uuid NOT NULL REFERENCES platform.app_user,
  recipient_employment_id uuid NOT NULL REFERENCES core.employment,
  value_code    text NOT NULL,                  -- the organization's recognition_value list
  message       text NOT NULL,
  points        integer CHECK (points >= 0),
  given_on      date NOT NULL,
  visibility    text NOT NULL CHECK (visibility IN ('private','public_requested','public','removed')),
  public_requested_by uuid REFERENCES platform.app_user,
  route_id      uuid REFERENCES platform.workflow_route,
  public_requested_at timestamptz,
  removed_by    uuid REFERENCES platform.app_user,
  removed_reason text,
  attached_review_id uuid REFERENCES talent.review,
  attached_by   uuid REFERENCES platform.app_user
);
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON talent.recognition
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('value_code', 'recognition_value');

CREATE FUNCTION talent.employment_users(p_employment uuid) RETURNS SETOF uuid LANGUAGE sql STABLE AS $$
  SELECT u.user_id FROM platform.app_user u JOIN core.employment e ON e.person_id = u.person_id WHERE e.employment_id = p_employment
$$;

CREATE FUNCTION talent.check_recognition() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE b talent.points_budget; used integer;
BEGIN
  IF NEW.giver_user IN (SELECT talent.employment_users(NEW.recipient_employment_id)) THEN
    RAISE EXCEPTION 'SELF_RECOGNITION: no one recognizes themself' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'INSERT' AND NEW.visibility <> 'private' THEN
    RAISE EXCEPTION 'RECIPIENT_CONSENT_REQUIRED: recognition starts private; only its recipient can ask to make it public' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.visibility = 'public_requested' AND (TG_OP = 'INSERT' OR OLD.visibility <> 'public_requested') THEN
    IF NEW.public_requested_by IS NULL OR NEW.public_requested_by NOT IN (SELECT talent.employment_users(NEW.recipient_employment_id)) THEN
      RAISE EXCEPTION 'RECIPIENT_CONSENT_REQUIRED: only the person recognized can make it public' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.route_id IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a request to make recognition public goes with its route' USING ERRCODE = 'check_violation';
    END IF;
    NEW.public_requested_at := now();
  END IF;
  IF NEW.visibility = 'public' AND (TG_OP = 'INSERT' OR OLD.visibility <> 'public') THEN
    IF TG_OP = 'INSERT' OR OLD.visibility <> 'public_requested'
       OR NOT platform.route_complete(NEW.route_id, 'recognition_publication', NEW.recognition_id, NEW.public_requested_by,
                                      NEW.public_requested_at - interval '1 microsecond') THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the organization''s route approves recognition before it goes public' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.visibility = 'removed' AND (TG_OP = 'INSERT' OR OLD.visibility <> 'removed')
     AND (NEW.removed_by IS NULL OR coalesce(length(btrim(NEW.removed_reason)), 0) = 0) THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: removing a recognition records who removed it and why' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.attached_review_id IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.attached_review_id IS DISTINCT FROM OLD.attached_review_id) THEN
    IF NEW.attached_by IS NULL OR NEW.attached_by NOT IN (SELECT talent.employment_users(NEW.recipient_employment_id)) THEN
      RAISE EXCEPTION 'RECIPIENT_CONSENT_REQUIRED: only the person recognized attaches it to their review' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM talent.review r WHERE r.review_id = NEW.attached_review_id AND r.employment_id = NEW.recipient_employment_id) THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: recognition is attached to the recipient''s own review' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF coalesce(NEW.points, 0) > 0 AND (TG_OP = 'INSERT' OR NEW.points IS DISTINCT FROM OLD.points) THEN
    SELECT * INTO b FROM talent.points_budget WHERE holder_user = NEW.giver_user AND period @> NEW.given_on;
    SELECT coalesce(sum(r.points), 0) INTO used FROM talent.recognition r
     WHERE r.giver_user = NEW.giver_user AND b.period @> r.given_on AND r.recognition_id <> NEW.recognition_id;
    IF b.budget_id IS NULL OR used + NEW.points > b.points THEN
      RAISE EXCEPTION 'POINTS_BUDGET_EXCEEDED: % points left', greatest(coalesce(b.points, 0) - used, 0) USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER recognition_check BEFORE INSERT OR UPDATE ON talent.recognition FOR EACH ROW EXECUTE FUNCTION talent.check_recognition();

-- CRA's administrative policy on gifts and awards by tax year, loaded from rules/recognition (docs/31 §6.1)
CREATE TABLE ref.gift_award_rule (
  tax_year              integer PRIMARY KEY,
  non_cash_annual_limit numeric(10,2) NOT NULL,
  long_service_limit    numeric(10,2) NOT NULL,
  long_service_min_years integer NOT NULL,
  long_service_interval_years integer NOT NULL,
  status                text NOT NULL CHECK (status IN ('official','secondary','verify_at_load')),
  cite                  text NOT NULL
);

CREATE TABLE talent.reward (
  tenant_id      uuid NOT NULL,
  reward_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id  uuid NOT NULL REFERENCES core.employment,
  kind           text NOT NULL CHECK (kind IN ('cash','near_cash','gift_card','non_cash')),
  occasion       text NOT NULL CHECK (occasion IN ('special_occasion','recognition','long_service','performance')),
  description    text NOT NULL,
  value          numeric(10,2) NOT NULL CHECK (value > 0),   -- fair market value including taxes
  given_on       date NOT NULL,
  card_retailers text,                                       -- gift cards: the retailer or group named on the card
  card_prepaid   boolean,
  card_no_cash   boolean,                                    -- its terms forbid converting it to cash
  recognition_id uuid REFERENCES talent.recognition,
  requested_by   uuid NOT NULL REFERENCES platform.app_user,
  route_id       uuid REFERENCES platform.workflow_route,
  submitted_at   timestamptz,
  status         text NOT NULL CHECK (status IN ('proposed','approved','given','cancelled')),
  cra_bucket     text CHECK (cra_bucket IN ('taxable_in_full','general','long_service')),   -- computed when given
  taxable_amount numeric(10,2),                              -- computed when given
  payroll_status text CHECK (payroll_status IN ('not_taxable','to_confirm','confirmed')),
  payroll_confirmed_by uuid REFERENCES platform.app_user,
  one_time_item_id uuid REFERENCES payroll.one_time_item,
  CONSTRAINT reward_gift_card CHECK ((kind = 'gift_card') = (card_prepaid IS NOT NULL AND card_no_cash IS NOT NULL))
);

CREATE FUNCTION talent.check_reward() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rule ref.gift_award_rule; csd date; last_ls date; used numeric; non_cash boolean;
BEGIN
  IF NEW.status = 'proposed' AND (TG_OP = 'INSERT' OR OLD.status <> 'proposed') THEN
    NEW.submitted_at := now();
  END IF;
  -- Cash and near-cash awards go through the organization's route (R5.3)
  IF NEW.kind IN ('cash','near_cash') AND NEW.status IN ('approved','given') AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('approved','given')) THEN
    IF NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'recognition_award', NEW.reward_id, NEW.requested_by, NEW.submitted_at - interval '1 microsecond') THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: a cash award is approved through the organization''s route' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.status = 'given' AND (TG_OP = 'INSERT' OR OLD.status <> 'given') THEN
    SELECT * INTO rule FROM ref.gift_award_rule WHERE tax_year = extract(year FROM NEW.given_on)::int;
    IF rule.tax_year IS NULL THEN
      RAISE EXCEPTION 'GIFT_RULE_MISSING: CRA''s gift and award limits for % are not loaded', extract(year FROM NEW.given_on) USING ERRCODE = 'check_violation';
    END IF;
    IF rule.status = 'verify_at_load' THEN
      RAISE EXCEPTION 'RULE_NOT_VERIFIED: CRA''s gift and award limits for % are still marked verify_at_load', rule.tax_year USING ERRCODE = 'check_violation';
    END IF;
    non_cash := NEW.kind = 'non_cash'
                OR (NEW.kind = 'gift_card' AND NEW.card_prepaid AND NEW.card_no_cash AND coalesce(length(btrim(NEW.card_retailers)), 0) > 0);
    IF NOT non_cash OR NEW.occasion = 'performance' THEN
      NEW.cra_bucket := 'taxable_in_full';
      NEW.taxable_amount := NEW.value;
    ELSE
      IF NEW.occasion = 'long_service' THEN
        SELECT v.continuous_service_date INTO csd FROM core.employment_version v
         WHERE v.employment_id = NEW.employment_id AND v.valid_period @> NEW.given_on AND upper_inf(v.sys_period);
        SELECT max(r.given_on) INTO last_ls FROM talent.reward r
         WHERE r.employment_id = NEW.employment_id AND r.cra_bucket = 'long_service' AND r.reward_id <> NEW.reward_id;
      END IF;
      IF NEW.occasion = 'long_service' AND csd IS NOT NULL
         AND NEW.given_on >= (csd + make_interval(years => rule.long_service_min_years))::date
         AND (last_ls IS NULL OR NEW.given_on >= (last_ls + make_interval(years => rule.long_service_interval_years))::date) THEN
        NEW.cra_bucket := 'long_service';
        NEW.taxable_amount := greatest(NEW.value - rule.long_service_limit, 0);
      ELSE
        SELECT coalesce(sum(r.value - r.taxable_amount), 0) INTO used FROM talent.reward r
         WHERE r.employment_id = NEW.employment_id AND r.cra_bucket = 'general' AND r.status = 'given'
           AND extract(year FROM r.given_on) = extract(year FROM NEW.given_on) AND r.reward_id <> NEW.reward_id;
        NEW.cra_bucket := 'general';
        NEW.taxable_amount := greatest(NEW.value - greatest(rule.non_cash_annual_limit - used, 0), 0);
      END IF;
    END IF;
    NEW.payroll_status := CASE WHEN NEW.taxable_amount > 0 THEN 'to_confirm' ELSE 'not_taxable' END;
  END IF;
  IF NEW.payroll_status = 'confirmed' AND (TG_OP = 'INSERT' OR OLD.payroll_status <> 'confirmed') THEN
    IF NEW.payroll_confirmed_by IS NULL OR NEW.payroll_confirmed_by = NEW.requested_by THEN
      RAISE EXCEPTION 'SELF_APPROVAL: payroll confirms a taxable award, never the person who recorded it' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER reward_check BEFORE INSERT OR UPDATE ON talent.reward FOR EACH ROW EXECUTE FUNCTION talent.check_reward();

-- Each person's year against CRA's limits, for payroll and the employee's statement
CREATE FUNCTION talent.cra_award_year(p_employment uuid, p_year integer)
RETURNS TABLE (cra_bucket text, total_value numeric, taxable numeric) LANGUAGE sql STABLE AS $$
  SELECT r.cra_bucket, sum(r.value), sum(r.taxable_amount) FROM talent.reward r
   WHERE r.employment_id = p_employment AND r.status = 'given' AND extract(year FROM r.given_on) = p_year
   GROUP BY r.cra_bucket
$$;

-- -------------------------------------------------------------------------------------
-- 5. Service milestones and celebrations (docs/31 §6.3, §6.4)
-- -------------------------------------------------------------------------------------
-- Milestones falling in a window, from the continuous service date and the organization's years
CREATE FUNCTION talent.milestones_due(p_tenant uuid, p_window daterange)
RETURNS TABLE (employment_id uuid, years integer, milestone_on date) LANGUAGE sql STABLE AS $$
  SELECT v.employment_id, y.years, (v.continuous_service_date + make_interval(years => y.years))::date
    FROM core.employment_version v
    JOIN core.employment e ON e.employment_id = v.employment_id
   CROSS JOIN LATERAL (
     SELECT x::int AS years FROM jsonb_array_elements_text(
       platform.setting(p_tenant, 'recognition.milestone_years', lower(p_window), e.legal_entity_id)) x) y
   WHERE v.tenant_id = p_tenant AND upper_inf(v.sys_period) AND v.valid_period @> lower(p_window)
     AND v.status IN ('active','on_leave')
     AND p_window @> (v.continuous_service_date + make_interval(years => y.years))::date
$$;

-- Milestones the manager is reminded of on a date: those falling the organization's reminder days later
CREATE FUNCTION talent.milestone_reminders(p_tenant uuid, p_on date)
RETURNS TABLE (employment_id uuid, years integer, milestone_on date) LANGUAGE sql STABLE AS $$
  SELECT v.employment_id, y.years, (v.continuous_service_date + make_interval(years => y.years))::date
    FROM core.employment_version v
    JOIN core.employment e ON e.employment_id = v.employment_id
   CROSS JOIN LATERAL (SELECT platform.setting_number(p_tenant, 'recognition.milestone_reminder_days', p_on, e.legal_entity_id)::int AS days) d
   CROSS JOIN LATERAL (
     SELECT x::int AS years FROM jsonb_array_elements_text(
       platform.setting(p_tenant, 'recognition.milestone_years', p_on, e.legal_entity_id)) x) y
   WHERE v.tenant_id = p_tenant AND upper_inf(v.sys_period) AND v.valid_period @> p_on
     AND v.status IN ('active','on_leave')
     AND (v.continuous_service_date + make_interval(years => y.years))::date = p_on + d.days
$$;

-- Birthdays and other personal celebrations only with the employee's own opt-in; the date is the one they give here,
-- never their date of birth from Core HR
CREATE TABLE talent.celebration_consent (
  tenant_id    uuid NOT NULL,
  consent_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id    uuid NOT NULL REFERENCES core.person,
  kind         text NOT NULL CHECK (kind IN ('birthday','other')),
  month_day    text CHECK (month_day ~ '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$'),
  given_at     timestamptz NOT NULL,
  withdrawn_at timestamptz,
  CONSTRAINT celebration_birthday_day CHECK (kind <> 'birthday' OR month_day IS NOT NULL),
  CONSTRAINT celebration_order CHECK (withdrawn_at IS NULL OR withdrawn_at > given_at)
);

-- -------------------------------------------------------------------------------------
-- 6. Announcements, ideas and the anonymous feedback box (docs/31 §7)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.announcement (
  tenant_id     uuid NOT NULL REFERENCES platform.tenant,
  announcement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title_en      text NOT NULL,
  title_fr      text,
  body_en       text NOT NULL,
  body_fr       text,
  audience      jsonb NOT NULL,                 -- legalEntities, locations, orgUnits, agreements, languages, employmentTypes
  important     boolean NOT NULL,               -- needs a read receipt, with reminders
  urgent        boolean NOT NULL,               -- an emergency alert: may also go by SMS
  publish_at    timestamptz NOT NULL,
  legal_entity_id uuid REFERENCES core.legal_entity,
  created_by    uuid NOT NULL REFERENCES platform.app_user,
  status        text NOT NULL CHECK (status IN ('draft','scheduled','published','withdrawn'))
);
CREATE TABLE talent.announcement_channel (
  tenant_id       uuid NOT NULL,
  announcement_id uuid NOT NULL REFERENCES talent.announcement,
  channel         text NOT NULL CHECK (channel IN ('app','email','push','sms','teams','slack')),
  PRIMARY KEY (announcement_id, channel)
);
CREATE FUNCTION talent.check_announcement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(NEW.audience) LOOP
    IF k NOT IN ('legalEntities','locations','orgUnits','agreements','languages','employmentTypes') OR jsonb_typeof(NEW.audience -> k) <> 'array' THEN
      RAISE EXCEPTION 'AUDIENCE_SCOPE_UNKNOWN: % is not an audience scope (each takes a list)', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  IF TG_OP = 'UPDATE' AND NOT NEW.urgent AND OLD.urgent
     AND EXISTS (SELECT 1 FROM talent.announcement_channel c WHERE c.announcement_id = NEW.announcement_id AND c.channel = 'sms') THEN
    RAISE EXCEPTION 'SMS_URGENT_ONLY: SMS is used only for urgent alerts' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER announcement_check BEFORE INSERT OR UPDATE ON talent.announcement FOR EACH ROW EXECUTE FUNCTION talent.check_announcement();
CREATE FUNCTION talent.check_announcement_channel() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a talent.announcement;
BEGIN
  SELECT * INTO a FROM talent.announcement WHERE announcement_id = NEW.announcement_id;
  IF NEW.channel = 'sms' THEN
    IF NOT a.urgent THEN
      RAISE EXCEPTION 'SMS_URGENT_ONLY: SMS is used only for urgent alerts' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT (platform.setting(a.tenant_id, 'announcements.sms_for_urgent', current_date, a.legal_entity_id))::boolean THEN
      RAISE EXCEPTION 'FEATURE_OFF: the organization does not send urgent alerts by SMS' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER announcement_channel_check BEFORE INSERT OR UPDATE ON talent.announcement_channel
  FOR EACH ROW EXECUTE FUNCTION talent.check_announcement_channel();

CREATE TABLE talent.announcement_receipt (
  tenant_id       uuid NOT NULL,
  receipt_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id uuid NOT NULL REFERENCES talent.announcement,
  person_id       uuid NOT NULL REFERENCES core.person,
  delivered_on    date NOT NULL,
  read_at         timestamptz,
  UNIQUE (announcement_id, person_id)
);
-- People to remind on a date: an important notice still unread on one of the organization's reminder days
CREATE FUNCTION talent.receipts_to_remind(p_announcement uuid, p_on date)
RETURNS TABLE (person_id uuid) LANGUAGE sql STABLE AS $$
  SELECT r.person_id FROM talent.announcement_receipt r
    JOIN talent.announcement a ON a.announcement_id = r.announcement_id
   WHERE r.announcement_id = p_announcement AND a.important AND a.status = 'published' AND r.read_at IS NULL
     AND (p_on - a.publish_at::date) IN (SELECT x::int FROM jsonb_array_elements_text(
            platform.setting(a.tenant_id, 'announcements.read_reminder_days', p_on, a.legal_entity_id)) x)
$$;

CREATE TABLE talent.idea (
  tenant_id     uuid NOT NULL,
  idea_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title         text NOT NULL,
  body          text NOT NULL,
  submitted_by  uuid NOT NULL REFERENCES platform.app_user,
  submitted_on  date NOT NULL,
  status        text NOT NULL CHECK (status IN ('submitted','under_review','planned','done','declined')),
  status_reason text,
  decided_by    uuid REFERENCES platform.app_user,
  CONSTRAINT idea_declined_reason CHECK (status <> 'declined' OR (coalesce(length(btrim(status_reason)), 0) > 0 AND decided_by IS NOT NULL))
);
CREATE TABLE talent.idea_vote (
  tenant_id uuid NOT NULL,
  idea_id   uuid NOT NULL REFERENCES talent.idea,
  user_id   uuid NOT NULL REFERENCES platform.app_user,
  PRIMARY KEY (idea_id, user_id)
);

-- The anonymous feedback box: no person link; the writer reads replies with a secret only they hold (its hash here)
CREATE TABLE talent.feedback_thread (
  tenant_id   uuid NOT NULL,
  thread_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token_hash  text NOT NULL UNIQUE,
  topic       text,
  opened_on   date NOT NULL,
  status      text NOT NULL CHECK (status IN ('open','answered','closed'))
);
CREATE TABLE talent.feedback_message (
  tenant_id   uuid NOT NULL,
  message_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id   uuid NOT NULL REFERENCES talent.feedback_thread,
  author      text NOT NULL CHECK (author IN ('employee','hr')),
  hr_user_id  uuid REFERENCES platform.app_user,
  body        text NOT NULL,
  sent_on     date NOT NULL,
  CONSTRAINT feedback_message_author CHECK ((author = 'hr') = (hr_user_id IS NOT NULL))
);

-- -------------------------------------------------------------------------------------
-- 7. Wellbeing resources, the directory and the observances calendar (docs/31 §8)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.wellbeing_resource (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  resource_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind        text NOT NULL CHECK (kind IN ('eap','mental_health','crisis_line','financial','wellness_account','other')),
  title_en    text NOT NULL,
  title_fr    text,
  url         text NOT NULL,
  audience    jsonb NOT NULL,
  active      boolean NOT NULL
);

-- What an employee chooses to add to the directory; name, role, unit and work contact come from Core HR
CREATE TABLE talent.profile_extra (
  tenant_id   uuid NOT NULL,
  person_id   uuid PRIMARY KEY REFERENCES core.person,
  photo_document_id uuid REFERENCES platform.document,
  interests   text,
  name_pronunciation text,
  show_skills boolean NOT NULL,                  -- the skills profile, as in Learning (docs/29 §7.2)
  updated_at  timestamptz NOT NULL
);

-- Starter observances; dated religious observances are loaded each year (docs/31 §8.3). An observance is never a paid
-- holiday: holidays come only from the organization's holiday calendar
CREATE TABLE ref.observance (
  code      text PRIMARY KEY,
  category  text NOT NULL CHECK (category IN ('indigenous','heritage','pride','religious','other')),
  name_en   text NOT NULL,
  name_fr   text NOT NULL,
  rule      text NOT NULL CHECK (rule IN ('fixed_day','month','dated')),
  month     smallint CHECK (month BETWEEN 1 AND 12),
  day       smallint CHECK (day BETWEEN 1 AND 31),
  decision_ref text NOT NULL,
  CONSTRAINT observance_rule CHECK ((rule = 'fixed_day') = (day IS NOT NULL) AND (rule = 'dated') = (month IS NULL))
);
INSERT INTO ref.observance (code, category, name_en, name_fr, rule, month, day, decision_ref) VALUES
 ('truth_reconciliation', 'indigenous', 'National Day for Truth and Reconciliation', 'Journée nationale de la vérité et de la réconciliation', 'fixed_day', 9, 30, 'docs/31 §8.3 (R8.2)'),
 ('indigenous_peoples_day', 'indigenous', 'National Indigenous Peoples Day', 'Journée nationale des peuples autochtones', 'fixed_day', 6, 21, 'docs/31 §8.3 (R8.2)'),
 ('black_history_month', 'heritage', 'Black History Month', 'Mois de l''histoire des Noirs', 'month', 2, NULL, 'docs/31 §8.3 (R8.2)'),
 ('asian_heritage_month', 'heritage', 'Asian Heritage Month', 'Mois du patrimoine asiatique', 'month', 5, NULL, 'docs/31 §8.3 (R8.2)'),
 ('pride_month', 'pride', 'Pride Month', 'Mois de la fierté', 'month', 6, NULL, 'docs/31 §8.3 (R8.2)'),
 ('christmas', 'religious', 'Christmas', 'Noël', 'fixed_day', 12, 25, 'docs/31 §8.3 (R8.2)'),
 ('easter', 'religious', 'Easter', 'Pâques', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('lunar_new_year', 'religious', 'Lunar New Year', 'Nouvel An lunaire', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('ramadan', 'religious', 'Ramadan', 'Ramadan', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('eid_al_fitr', 'religious', 'Eid al-Fitr', 'Aïd el-Fitr', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('eid_al_adha', 'religious', 'Eid al-Adha', 'Aïd el-Adha', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('passover', 'religious', 'Passover', 'Pâque juive', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('rosh_hashanah', 'religious', 'Rosh Hashanah', 'Roch Hachana', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('yom_kippur', 'religious', 'Yom Kippur', 'Yom Kippour', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('vaisakhi', 'religious', 'Vaisakhi', 'Vaisakhi', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('diwali', 'religious', 'Diwali', 'Diwali', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)'),
 ('hanukkah', 'religious', 'Hanukkah', 'Hanoukka', 'dated', NULL, NULL, 'docs/31 §8.3 (R8.2)');

CREATE TABLE ref.observance_date (
  code      text NOT NULL REFERENCES ref.observance,
  year      integer NOT NULL,
  dates     daterange NOT NULL,
  status    text NOT NULL CHECK (status IN ('official','secondary','verify_at_load')),
  PRIMARY KEY (code, year)
);

CREATE TABLE talent.observance (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  observance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL,
  category    text NOT NULL CHECK (category IN ('indigenous','heritage','pride','religious','community','other')),
  name_en     text NOT NULL,
  name_fr     text,
  rule        text NOT NULL CHECK (rule IN ('fixed_day','month','dated')),
  month       smallint CHECK (month BETWEEN 1 AND 12),
  day         smallint CHECK (day BETWEEN 1 AND 31),
  dates       daterange[],                      -- the organization's own dated events (ceremonies, land-based activities)
  source      text NOT NULL CHECK (source IN ('starter','organization')),
  active      boolean NOT NULL,
  UNIQUE (tenant_id, code)
);

-- -------------------------------------------------------------------------------------
-- 8. Routes, cautions, no self-approval, text fields, row-level security
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.workflow_route DROP CONSTRAINT IF EXISTS workflow_route_subject_type_check;
ALTER TABLE platform.workflow_route ADD CONSTRAINT workflow_route_subject_type_check
  CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution',
                          'pay_run','voluntary_deduction','banked_time_payout',
                          'comp_philosophy','pay_structure_version','comp_decision','incentive_payout','salary_disclosure',
                          'carrier_invoice','timesheet','performance_review','pip','training_request',
                          'succession_plan','talent_pool_membership','position_plan',
                          'recognition_publication','recognition_award'));

INSERT INTO ref.workflow_route_starter (code, subject_type, name_en, name_fr, conditions, priority, decision_ref) VALUES
 ('recognition_publication', 'recognition_publication', 'Recognition made public', 'Reconnaissance rendue publique', '{}', 10, 'docs/31 §5.2 (R4.2)'),
 ('recognition_award', 'recognition_award', 'Cash award', 'Prix en espèces', '{}', 10, 'docs/31 §6.2 (R5.3)');
INSERT INTO ref.workflow_route_step_starter (route_code, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr) VALUES
 ('recognition_publication', 1, 'capability', 'hr', 'any', 1, 'HR', 'RH'),
 ('recognition_award', 1, 'requester_manager', NULL, 'any', 1, 'The proposer''s manager', 'Le gestionnaire de la personne qui propose'),
 ('recognition_award', 2, 'capability', 'hr', 'any', 1, 'HR', 'RH');

INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('engagement.union_consultation', 'engagement', 'Survey of a unionized group', 'Sondage d''un groupe syndiqué',
  'The collective agreement for this group requires the union to be consulted on surveys. Confirm when and how the union was consulted.',
  'La convention collective de ce groupe exige que le syndicat soit consulté sur les sondages. Confirmez quand et comment le syndicat a été consulté.',
  true, true, 'docs/31 §3.7 (R2.4)');

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
  ELSIF NEW.subject_type = 'recognition_publication' THEN
    SELECT r.public_requested_by, r.giver_user INTO subject_person, requester FROM talent.recognition r WHERE r.recognition_id = NEW.subject_id;
  ELSIF NEW.subject_type = 'recognition_award' THEN
    SELECT w.requested_by, u.user_id INTO requester, subject_person FROM talent.reward w
      JOIN core.employment e ON e.employment_id = w.employment_id
      LEFT JOIN platform.app_user u ON u.tenant_id = w.tenant_id AND u.person_id = e.person_id
     WHERE w.reward_id = NEW.subject_id;
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
      ('talent','survey'), ('talent','survey_question'), ('talent','survey_escalation_contact'), ('talent','survey_invitation'),
      ('talent','survey_submission'), ('talent','comment_flag'), ('talent','imported_result'), ('talent','action_plan'),
      ('talent','action_item'), ('talent','points_budget'), ('talent','recognition'), ('talent','reward'),
      ('talent','celebration_consent'), ('talent','announcement'), ('talent','announcement_channel'), ('talent','announcement_receipt'),
      ('talent','idea'), ('talent','idea_vote'), ('talent','feedback_thread'), ('talent','feedback_message'),
      ('talent','wellbeing_resource'), ('talent','profile_extra'), ('talent','observance')) AS x(s, t) LOOP
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
      RAISE NOTICE 'organization %: starter recognition routes not copied because % is required for its data; add them with their texts (docs/31 §11)', t.tenant_id, langs;
    END IF;
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT, INSERT and UPDATE on the new tenant tables and EXECUTE on the new
-- functions. Survey submissions, comments and flags are read only by HR (comments) and through the result functions
-- (scores), never per person; invitations are used only for reminders and participation counts; the feedback box is
-- read by HR and by the writer with their secret; recognition is seen by its recipient and their manager until it is
-- public (docs/31 §3, §4.2, §5.1, §7.3).
