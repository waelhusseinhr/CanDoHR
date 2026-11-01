-- =====================================================================================
-- Migration 0015 · Learning and development decisions (docs/29)
--
-- Applies the owner's Module 08 review of 28 October 2026 (claude/review/08-learning-development-decisions.md).
-- CanDo keeps the learning record, the training the law and the organization require, credentials and development
-- plans; courses run in the customer's LMS or a provider's platform (integration-first, no course player); no AI.
--
--   §1  Settings
--   §2  Learning items, sessions and the training the law requires
--   §3  Training rules, assignments and completions (escalation, refresher cycles, the law's changes)
--   §4  Credentials, continuing education and apprenticeships
--   §5  Ready for the work: credentials and training checked when a shift is published
--   §6  Skills consent and development plans
--   §7  Training requests, budgets, repayment, grants and the Quebec 1% rule
--   §8  Mentoring
--   §9  Routes, cautions, no self-approval, text fields, row-level security
--
-- Run after 0014.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/29 §2.1)
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('learning.overdue_escalation', 'learning', 'json', NULL, '{"remindDaysBefore":[14,3],"managerDaysAfter":1,"hrDaysAfter":7}',
  ARRAY['tenant','legal_entity'], false,
  'Mandatory training: the employee is reminded on these days before the due date; the manager is told this many days after it is overdue, then HR.',
  'docs/29 §4.4 (R2.2)', 'decided', NULL, NULL, ARRAY['remindDaysBefore','managerDaysAfter','hrDaysAfter']),
 ('learning.refresher_early_window_days', 'learning', 'integer', NULL, '60', ARRAY['tenant','legal_entity'], false,
  'A refresher completed within this many days before its due date keeps its cycle (the next one is due a full period after the old due date); completed earlier, the next one counts from the completion.',
  'docs/29 §4.5 (R2.4)', 'decided', 0, NULL, NULL),
 ('learning.law_change_due_days', 'learning', 'integer', NULL, '30', ARRAY['tenant','legal_entity'], false,
  'When the law adds or changes a training requirement and gives no deadline, current employees are due to complete it within this many days of its effective date.',
  'docs/29 §4.6 (R2.5)', 'decided', 1, NULL, NULL),
 ('learning.assignment_events', 'learning', 'text_array', NULL, '["hire","job_change","promotion","location_transfer","return_from_leave"]',
  ARRAY['tenant','legal_entity'], false,
  'Events on which a new training rule assigns the role''s and location''s training automatically. Each rule can change its own list.',
  'docs/29 §4.3 (R2.6)', 'decided', NULL, NULL, NULL),
 ('learning.credential_alert_days', 'learning', 'json', NULL, '{"employee":[90,60,30],"managerAndHr":[30,0]}',
  ARRAY['tenant','legal_entity'], false,
  'Days before a credential expires when the employee is alerted, and when the manager and HR are (0 is the expiry date).',
  'docs/29 §5.2 (R3.2)', 'decided', NULL, NULL, ARRAY['employee','managerAndHr']),
 ('learning.request_hr_above_amount', 'learning', 'number', NULL, NULL, ARRAY['tenant','legal_entity'], false,
  'Cost of a training request above which HR approves as well as the manager (the starter route). Each organization chooses it at setup.',
  'docs/29 §8.1 (R5.2)', 'pending', 0, NULL, NULL),
 ('learning.repayment_without_rule', 'learning', 'text', '["hr_decides","no_repayment"]', NULL, ARRAY['tenant','legal_entity'], false,
  'What happens to a paid training request that none of the organization''s repayment rules covers: HR decides on the request, or there is no repayment. Each organization chooses it at setup.',
  'docs/29 §8.3 (R5.3)', 'pending', NULL, NULL, NULL),
 ('learning.records_keep_extra_years', 'learning', 'integer', NULL, '0', ARRAY['tenant'], false,
  'Years training and credential records are kept beyond the longest period the law and safety regulators expect (0: the law''s period).',
  'docs/29 §10.2 (R7.2)', 'decided', 0, NULL, NULL);

-- -------------------------------------------------------------------------------------
-- 2. Learning items, sessions and the training the law requires (docs/29 §3)
-- -------------------------------------------------------------------------------------
-- What the law requires, by jurisdiction and sector, loaded by CanDo from rules/learning (no RLS; written by the loader only)
CREATE TABLE ref.training_requirement (
  requirement_code text PRIMARY KEY,                -- 'ON-OHS-WORKER-AWARENESS'
  jurisdiction     ref.jurisdiction_code NOT NULL,
  sectors          text[],                          -- null: every sector
  topic            text NOT NULL CHECK (topic IN ('health_safety','hazardous_products','harassment_violence','accessibility','privacy',
                                                  'human_rights','indigenous_awareness','sector','role','orientation','other')),
  name_en          text NOT NULL,
  name_fr          text,
  audience         jsonb NOT NULL,                  -- {"roles":["worker"]}, {"roles":["supervisor"]}, {"hazards":["hazardous_products"]}
  before_work      boolean NOT NULL,                -- must be done before the work starts
  due_days         integer CHECK (due_days >= 0),   -- days from the event; null with before_work or "as soon as practicable"
  due_note         text,                            -- the law's own words where it gives no number
  frequency_months integer CHECK (frequency_months > 0),
  cite             text NOT NULL,
  status           text NOT NULL CHECK (status IN ('official','secondary','verify_at_load')),
  effective_from   date NOT NULL,
  effective_to     date,
  CONSTRAINT training_requirement_audience CHECK (jsonb_typeof(audience) = 'object')
);

CREATE TABLE talent.learning_item (
  tenant_id        uuid NOT NULL REFERENCES platform.tenant,
  item_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             text NOT NULL,                   -- matched by work_requirement.satisfied_by courseCode
  title_en         text NOT NULL,
  title_fr         text,
  kind             text NOT NULL CHECK (kind IN ('elearning','video','document_ack','classroom','virtual','on_the_job','external_course',
                                                 'conference','certification','mentoring','job_shadowing')),
  provider_kind    text NOT NULL CHECK (provider_kind IN ('customer_lms','partner_library','government','external_provider','internal')),
  standard         text CHECK (standard IN ('scorm_1_2','scorm_2004','xapi','cmi5','lti','provider_api','none')),
  external_ref     text,                            -- the course id in the LMS or library
  launch_url       text,
  languages        text[] NOT NULL,                 -- language versions offered
  duration_minutes integer CHECK (duration_minutes > 0),
  credits          numeric(6,2) CHECK (credits >= 0),   -- continuing education credits or hours
  competency_codes text[] NOT NULL DEFAULT '{}',   -- skills it develops
  version          text NOT NULL,                   -- completions keep the version taken
  status           text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT learning_item_external CHECK (provider_kind = 'internal' OR external_ref IS NOT NULL OR launch_url IS NOT NULL)
);

CREATE TABLE talent.learning_session (
  tenant_id     uuid NOT NULL,
  session_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id       uuid NOT NULL REFERENCES talent.learning_item,
  starts_at     timestamptz NOT NULL,
  ends_at       timestamptz NOT NULL,
  location_id   uuid REFERENCES core.location,
  meeting_link  text,
  instructor_person_id uuid REFERENCES core.person,
  capacity      integer CHECK (capacity > 0),
  CONSTRAINT learning_session_times CHECK (ends_at > starts_at),
  CONSTRAINT learning_session_place CHECK (location_id IS NOT NULL OR meeting_link IS NOT NULL)
);
CREATE TABLE talent.session_attendee (
  tenant_id   uuid NOT NULL,
  attendee_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  uuid NOT NULL REFERENCES talent.learning_session,
  person_id   uuid NOT NULL REFERENCES core.person,
  status      text NOT NULL CHECK (status IN ('registered','waitlisted','attended','no_show','cancelled')),
  recorded_by uuid REFERENCES platform.app_user,
  UNIQUE (session_id, person_id)
);
CREATE FUNCTION talent.check_session_attendee() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cap int; n int;
BEGIN
  IF NEW.status = 'registered' AND (TG_OP = 'INSERT' OR OLD.status <> 'registered') THEN
    SELECT capacity INTO cap FROM talent.learning_session WHERE session_id = NEW.session_id;
    SELECT count(*) INTO n FROM talent.session_attendee WHERE session_id = NEW.session_id AND status = 'registered' AND attendee_id <> NEW.attendee_id;
    IF cap IS NOT NULL AND n >= cap THEN
      RAISE EXCEPTION 'SESSION_FULL: the session has % places; add the person to the waitlist', cap USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.status IN ('attended','no_show') AND NEW.recorded_by IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: attendance names who recorded it' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER session_attendee_check BEFORE INSERT OR UPDATE ON talent.session_attendee
  FOR EACH ROW EXECUTE FUNCTION talent.check_session_attendee();

-- -------------------------------------------------------------------------------------
-- 3. Training rules, assignments and completions (docs/29 §4)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.training_rule (
  tenant_id        uuid NOT NULL REFERENCES platform.tenant,
  rule_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code             text NOT NULL,
  name_en          text NOT NULL,
  name_fr          text,
  source           text NOT NULL CHECK (source IN ('law','organization')),
  requirement_code text REFERENCES ref.training_requirement,   -- the law's requirement this rule carries out
  item_id          uuid NOT NULL REFERENCES talent.learning_item,
  applies_to       jsonb NOT NULL,                  -- {} everyone; keys: jobs, positions, orgUnits, locations, provinces, agreements, employmentTypes, legalEntities, personTypes, supervisors
  events           text[],                          -- filled from learning.assignment_events
  due_days         integer CHECK (due_days >= 0),   -- days after the event; null when the training comes before the work
  frequency_months integer CHECK (frequency_months > 0),
  grace_days       integer CHECK (grace_days > 0),  -- none unless the organization adds one to its own rule
  early_window_days integer CHECK (early_window_days >= 0),   -- filled from learning.refresher_early_window_days
  blocks_work      boolean NOT NULL,
  status           text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT training_rule_law CHECK ((source = 'law') = (requirement_code IS NOT NULL)),
  CONSTRAINT training_rule_scope_object CHECK (jsonb_typeof(applies_to) = 'object'),
  CONSTRAINT training_rule_due CHECK (blocks_work OR due_days IS NOT NULL)
);
INSERT INTO platform.column_default (table_schema, table_name, column_name, source, setting_key) VALUES
  ('talent','training_rule','events','setting','learning.assignment_events'),
  ('talent','training_rule','early_window_days','setting','learning.refresher_early_window_days');
CREATE TRIGGER a00_fill_from_settings BEFORE INSERT ON talent.training_rule FOR EACH ROW EXECUTE FUNCTION platform.fill_from_settings();

-- A rule that carries out the law can be stricter than the law, never looser; the law's unverified values are not applied
CREATE FUNCTION talent.check_training_rule() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text; e text; r ref.training_requirement;
BEGIN
  FOR k IN SELECT jsonb_object_keys(NEW.applies_to) LOOP
    IF k NOT IN ('jobs','positions','orgUnits','locations','provinces','agreements','employmentTypes','legalEntities','personTypes','supervisors') THEN
      RAISE EXCEPTION 'TRAINING_SCOPE_UNKNOWN: % is not a training rule scope', k USING ERRCODE = 'check_violation';
    END IF;
    IF k <> 'supervisors' AND jsonb_typeof(NEW.applies_to -> k) <> 'array' THEN
      RAISE EXCEPTION 'TRAINING_SCOPE_UNKNOWN: % takes a list', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  FOREACH e IN ARRAY coalesce(NEW.events, '{}') LOOP
    IF e NOT IN ('hire','job_change','promotion','location_transfer','return_from_leave') THEN
      RAISE EXCEPTION 'TRAINING_EVENT_UNKNOWN: %', e USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  IF NEW.source = 'law' THEN
    SELECT * INTO r FROM ref.training_requirement WHERE requirement_code = NEW.requirement_code;
    IF r.status = 'verify_at_load' AND NEW.status = 'active' THEN
      RAISE EXCEPTION 'RULE_NOT_VERIFIED: % is still marked verify_at_load', r.requirement_code USING ERRCODE = 'check_violation';
    END IF;
    IF (r.before_work AND NOT NEW.blocks_work)
       OR (r.due_days IS NOT NULL AND (NEW.due_days IS NULL AND NOT NEW.blocks_work OR NEW.due_days > r.due_days))
       OR (r.frequency_months IS NOT NULL AND (NEW.frequency_months IS NULL OR NEW.frequency_months > r.frequency_months))
       OR NEW.grace_days IS NOT NULL THEN
      RAISE EXCEPTION 'TRAINING_RULE_LOOSER_THAN_LAW: % (the law: before work %, within % days, every % months, no grace period)',
        r.requirement_code, r.before_work, r.due_days, r.frequency_months USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER training_rule_check BEFORE INSERT OR UPDATE ON talent.training_rule
  FOR EACH ROW EXECUTE FUNCTION talent.check_training_rule();

CREATE TABLE talent.learning_assignment (
  tenant_id     uuid NOT NULL,
  assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id     uuid NOT NULL REFERENCES core.person,
  employment_id uuid REFERENCES core.employment,    -- none for council and board members, volunteers and contractors
  item_id       uuid NOT NULL REFERENCES talent.learning_item,
  rule_id       uuid REFERENCES talent.training_rule,
  source        text NOT NULL CHECK (source IN ('rule','law_change','manager','development_plan','self_enrolment','suggestion','onboarding')),
  event         text CHECK (event IN ('hire','job_change','promotion','location_transfer','return_from_leave')),
  assigned_on   date NOT NULL,
  due_on        date,
  legal_due_on  date,                               -- the law's own deadline, never later than due_on allows
  blocks_work   boolean NOT NULL,
  language      text,                               -- filled with the organization's main language; others on request
  status        text NOT NULL CHECK (status IN ('assigned','in_progress','completed','waived','cancelled')),
  waived_by     uuid REFERENCES platform.app_user,
  waive_reason  text,
  assigned_by   uuid REFERENCES platform.app_user,
  CONSTRAINT learning_assignment_rule CHECK ((source IN ('rule','law_change')) = (rule_id IS NOT NULL)),
  CONSTRAINT learning_assignment_due CHECK (due_on IS NOT NULL OR blocks_work),
  CONSTRAINT learning_assignment_legal_due CHECK (legal_due_on IS NULL OR due_on IS NULL OR due_on <= legal_due_on),
  CONSTRAINT learning_assignment_waive CHECK (status <> 'waived' OR (waived_by IS NOT NULL AND coalesce(length(btrim(waive_reason)), 0) > 0))
);
INSERT INTO platform.column_default (table_schema, table_name, column_name, source) VALUES ('talent','learning_assignment','language','tenant_main_language');
CREATE TRIGGER a00_fill_from_settings BEFORE INSERT ON talent.learning_assignment FOR EACH ROW EXECUTE FUNCTION platform.fill_from_settings();

CREATE FUNCTION talent.check_learning_assignment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cat text; src text;
BEGIN
  IF NEW.employment_id IS NULL THEN
    SELECT v.category INTO cat FROM core.person p JOIN core.list_value v ON v.tenant_id = p.tenant_id AND v.list_code = 'person_type' AND v.code = p.person_type
     WHERE p.person_id = NEW.person_id;
    IF cat IS NULL OR cat = 'employee' THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: an employee''s training names the employment; only council and board members, volunteers and contractors have none'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.status = 'waived' AND (TG_OP = 'INSERT' OR OLD.status <> 'waived') THEN
    SELECT r.source INTO src FROM talent.training_rule r WHERE r.rule_id = NEW.rule_id;
    IF src = 'law' THEN
      RAISE EXCEPTION 'LEGAL_TASK_CANNOT_BE_WAIVED: training the law requires is never waived' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER learning_assignment_check BEFORE INSERT OR UPDATE ON talent.learning_assignment
  FOR EACH ROW EXECUTE FUNCTION talent.check_learning_assignment();

-- Due date when the law adds or changes a requirement: the law's deadline, else the organization's days (docs/29 §4.6)
CREATE FUNCTION talent.law_change_due_on(p_tenant uuid, p_requirement text, p_effective date, p_legal_entity uuid) RETURNS date
LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN r.due_days IS NOT NULL THEN p_effective + r.due_days
              ELSE p_effective + platform.setting_number(p_tenant, 'learning.law_change_due_days', p_effective, p_legal_entity)::int END
    FROM ref.training_requirement r WHERE r.requirement_code = p_requirement
$$;

-- The next due date of a refresher: a completion inside the early window keeps the cycle (docs/29 §4.5)
CREATE FUNCTION talent.next_due_on(p_rule uuid, p_previous_due date, p_completed_on date) RETURNS date LANGUAGE sql STABLE AS $$
  SELECT CASE
           WHEN r.frequency_months IS NULL THEN NULL
           WHEN p_previous_due IS NOT NULL AND p_completed_on <= p_previous_due
                AND p_completed_on >= p_previous_due - r.early_window_days
             THEN (p_previous_due + make_interval(months => r.frequency_months))::date
           ELSE (p_completed_on + make_interval(months => r.frequency_months))::date
         END
    FROM talent.training_rule r WHERE r.rule_id = p_rule
$$;

-- Who is told about mandatory training on a date: the employee before, the manager and HR after (docs/29 §4.4)
CREATE FUNCTION talent.learning_notices_due(p_tenant uuid, p_on date)
RETURNS TABLE (assignment_id uuid, notify text, days integer) LANGUAGE sql STABLE AS $$
  SELECT a.assignment_id, n.notify, n.days
    FROM talent.learning_assignment a
    LEFT JOIN core.employment e ON e.employment_id = a.employment_id
    LEFT JOIN talent.training_rule r ON r.rule_id = a.rule_id
    CROSS JOIN LATERAL (SELECT platform.setting(p_tenant, 'learning.overdue_escalation', p_on, e.legal_entity_id) AS s) cfg
    CROSS JOIN LATERAL (
      SELECT 'employee'::text AS notify, d::int AS days FROM jsonb_array_elements_text(cfg.s -> 'remindDaysBefore') d
       WHERE a.due_on - d::int = p_on
      UNION ALL SELECT 'manager', (cfg.s ->> 'managerDaysAfter')::int
       WHERE a.due_on + coalesce(r.grace_days, 0) + (cfg.s ->> 'managerDaysAfter')::int = p_on
      UNION ALL SELECT 'hr', (cfg.s ->> 'hrDaysAfter')::int
       WHERE a.due_on + coalesce(r.grace_days, 0) + (cfg.s ->> 'hrDaysAfter')::int = p_on) n
   WHERE a.tenant_id = p_tenant AND a.status IN ('assigned','in_progress') AND a.due_on IS NOT NULL
$$;

CREATE TABLE talent.learning_completion (
  tenant_id        uuid NOT NULL,
  completion_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id        uuid NOT NULL REFERENCES core.person,
  item_id          uuid NOT NULL REFERENCES talent.learning_item,
  item_version     text NOT NULL,
  assignment_id    uuid REFERENCES talent.learning_assignment,
  completed_on     date NOT NULL,
  source           text NOT NULL CHECK (source IN ('lms_import','provider_import','session_attendance','on_the_job_signoff',
                                                   'policy_acknowledgement','external_certificate','hr_entry')),
  score            numeric(6,2),
  credits          numeric(6,2) CHECK (credits >= 0),
  outside_schedule boolean NOT NULL,
  training_minutes integer CHECK (training_minutes > 0),
  timesheet_id     uuid REFERENCES timeleave.timesheet,   -- where the paid training time went
  signed_off_by    uuid REFERENCES platform.app_user,
  evidence_document_id uuid REFERENCES platform.document,
  wsdrf_eligible   boolean,                         -- counted in Quebec's 1% (phase 2 report); null until assessed
  recorded_by      uuid NOT NULL REFERENCES platform.app_user
);
CREATE FUNCTION talent.check_learning_completion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE learner uuid; mandatory boolean;
BEGIN
  SELECT u.user_id INTO learner FROM platform.app_user u WHERE u.tenant_id = NEW.tenant_id AND u.person_id = NEW.person_id LIMIT 1;
  IF NEW.source = 'on_the_job_signoff' AND (NEW.signed_off_by IS NULL OR NEW.signed_off_by IS NOT DISTINCT FROM learner) THEN
    RAISE EXCEPTION 'SIGNOFF_REQUIRED: on-the-job training is signed off by a supervisor, never by the learner' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.source = 'external_certificate' AND NEW.evidence_document_id IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: an external course is recorded with its certificate' USING ERRCODE = 'check_violation';
  END IF;
  SELECT a.rule_id IS NOT NULL INTO mandatory FROM talent.learning_assignment a WHERE a.assignment_id = NEW.assignment_id;
  IF coalesce(mandatory, false) AND NEW.outside_schedule AND NEW.training_minutes IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: mandatory training outside scheduled hours records its minutes, which go to the timesheet and are paid'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.assignment_id IS NOT NULL THEN
    UPDATE talent.learning_assignment SET status = 'completed' WHERE assignment_id = NEW.assignment_id AND status IN ('assigned','in_progress');
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER learning_completion_check BEFORE INSERT ON talent.learning_completion
  FOR EACH ROW EXECUTE FUNCTION talent.check_learning_completion();

-- Earlier learning records (0001) stay as history; new completions and credentials use the tables above
COMMENT ON TABLE talent.learning_record IS 'Read-only after 0015: completions are in talent.learning_completion and credentials in talent.credential (docs/29 §12).';

-- -------------------------------------------------------------------------------------
-- 4. Credentials, continuing education and apprenticeships (docs/29 §5)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.credential (
  tenant_id       uuid NOT NULL,
  credential_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id       uuid NOT NULL REFERENCES core.person,
  credential_code text NOT NULL,                    -- matched by work_requirement.satisfied_by credential
  kind            text NOT NULL CHECK (kind IN ('professional_licence','registration','trade_certificate','safety_certificate',
                                                'driver_licence','screening','operator_ticket','other')),
  issuer          text NOT NULL,
  number          text,
  issued_on       date,
  expires_on      date,
  status          text NOT NULL CHECK (status IN ('pending','valid','suspended','revoked')),
  verified_by     uuid REFERENCES platform.app_user,
  verified_at     timestamptz,
  verification_method text CHECK (verification_method IN ('document','public_registry','issuer_contact')),
  document_id     uuid REFERENCES platform.document,
  CONSTRAINT credential_dates CHECK (expires_on IS NULL OR issued_on IS NULL OR expires_on > issued_on),
  CONSTRAINT credential_verified CHECK (status <> 'valid' OR (verified_by IS NOT NULL AND verified_at IS NOT NULL AND verification_method IS NOT NULL))
);
CREATE FUNCTION talent.check_credential() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'valid' AND NEW.verified_by IN (SELECT u.user_id FROM platform.app_user u WHERE u.person_id = NEW.person_id) THEN
    RAISE EXCEPTION 'SELF_APPROVAL: a person does not verify their own credential' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER credential_check BEFORE INSERT OR UPDATE ON talent.credential
  FOR EACH ROW EXECUTE FUNCTION talent.check_credential();

-- Valid on a date: verified, not suspended or revoked, not expired. Pending never counts (docs/29 §5.3)
CREATE FUNCTION talent.credential_valid(p_person uuid, p_code text, p_on date) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM talent.credential c WHERE c.person_id = p_person AND c.credential_code = p_code AND c.status = 'valid'
                   AND (c.issued_on IS NULL OR c.issued_on <= p_on) AND (c.expires_on IS NULL OR c.expires_on > p_on))
$$;

-- Alerts due on a date: the employee on its days, the manager and HR on theirs (0 is the expiry date)
CREATE FUNCTION talent.credential_alerts_due(p_tenant uuid, p_on date)
RETURNS TABLE (credential_id uuid, audience text, days integer) LANGUAGE sql STABLE AS $$
  SELECT c.credential_id, a.audience, a.days
    FROM talent.credential c
    CROSS JOIN LATERAL (SELECT platform.setting(p_tenant, 'learning.credential_alert_days', p_on,
                                (SELECT e.legal_entity_id FROM core.employment e WHERE e.person_id = c.person_id ORDER BY e.employment_id LIMIT 1)) AS s) cfg
    CROSS JOIN LATERAL (
      SELECT 'employee'::text AS audience, d::int AS days FROM jsonb_array_elements_text(cfg.s -> 'employee') d WHERE c.expires_on - d::int = p_on
      UNION ALL
      SELECT 'manager_and_hr', d::int FROM jsonb_array_elements_text(cfg.s -> 'managerAndHr') d WHERE c.expires_on - d::int = p_on) a
   WHERE c.tenant_id = p_tenant AND c.status IN ('valid','pending') AND c.expires_on IS NOT NULL
$$;

-- Continuing education a licensing body requires, counted from completions with credits (docs/29 §5.5)
CREATE TABLE talent.ce_requirement (
  tenant_id       uuid NOT NULL,
  ce_requirement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  credential_code text NOT NULL,
  body            text NOT NULL,
  hours_required  numeric(6,2) NOT NULL CHECK (hours_required > 0),
  period_months   integer NOT NULL CHECK (period_months > 0),
  remind_days_before integer[] NOT NULL,
  UNIQUE (tenant_id, credential_code)
);
CREATE FUNCTION talent.ce_progress(p_person uuid, p_code text, p_period daterange) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT coalesce(sum(x.credits), 0) FROM talent.learning_completion x
   WHERE x.person_id = p_person AND x.completed_on <@ p_period AND x.credits IS NOT NULL
     AND EXISTS (SELECT 1 FROM talent.credential c WHERE c.person_id = p_person AND c.credential_code = p_code)
$$;

-- Apprenticeships, basic at launch: hours by trade and level, technical training, the wage step (docs/29 §5.6)
CREATE TABLE talent.apprenticeship (
  tenant_id       uuid NOT NULL,
  apprenticeship_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id       uuid NOT NULL REFERENCES core.person,
  employment_id   uuid NOT NULL REFERENCES core.employment,
  trade           text NOT NULL,
  jurisdiction    ref.jurisdiction_code NOT NULL,
  level           smallint NOT NULL CHECK (level >= 1),
  level_hours_required numeric(8,2) NOT NULL CHECK (level_hours_required > 0),
  registration_number text,
  wage_step_ref   text,                             -- the grid step of this level (Module 04 or the agreement)
  status          text NOT NULL CHECK (status IN ('active','completed','withdrawn'))
);
CREATE TABLE talent.apprenticeship_hours (
  tenant_id       uuid NOT NULL,
  entry_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  apprenticeship_id uuid NOT NULL REFERENCES talent.apprenticeship,
  level           smallint NOT NULL,
  period          daterange NOT NULL,
  hours           numeric(8,2) NOT NULL CHECK (hours > 0),
  kind            text NOT NULL CHECK (kind IN ('on_the_job','technical_training')),
  source          text NOT NULL CHECK (source IN ('timesheet','school_record','manual')),
  recorded_by     uuid NOT NULL REFERENCES platform.app_user
);
CREATE FUNCTION talent.apprentice_hours(p_apprenticeship uuid, p_level smallint) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT coalesce(sum(hours), 0) FROM talent.apprenticeship_hours WHERE apprenticeship_id = p_apprenticeship AND level = p_level AND kind = 'on_the_job'
$$;

-- -------------------------------------------------------------------------------------
-- 5. Ready for the work (docs/29 §6): a shift is published only to someone with the credentials the position requires
--    and the training required before the work. A licence the law requires stops it with no override; anything else
--    needs the caution learning.not_ready_for_work
-- -------------------------------------------------------------------------------------
CREATE FUNCTION talent.position_requirements(p_position uuid, p_on date)
RETURNS SETOF core.work_requirement LANGUAGE sql STABLE AS $$
  SELECT w.* FROM core.work_requirement w
   WHERE w.status = 'active' AND upper_inf(w.sys_period) AND w.valid_period @> p_on
     AND ((w.target_type = 'position' AND w.target_id = p_position)
          OR (w.target_type = 'job' AND w.target_id = (SELECT pv.job_id FROM core.position_version pv
                                                        WHERE pv.position_id = p_position AND pv.valid_period @> p_on AND upper_inf(pv.sys_period))))
     AND NOT EXISTS (SELECT 1 FROM core.work_requirement_suppression s
                      WHERE s.position_id = p_position AND s.requirement_id = w.requirement_id AND s.valid_period @> p_on AND upper_inf(s.sys_period))
$$;

CREATE FUNCTION talent.work_readiness(p_assignment uuid, p_position uuid, p_on date)
RETURNS TABLE (problem text, detail text, by_law boolean) LANGUAGE sql STABLE AS $$
  WITH who AS (
    SELECT e.person_id FROM core.assignment a JOIN core.employment e ON e.employment_id = a.employment_id WHERE a.assignment_id = p_assignment
  ), pos AS (
    SELECT coalesce(p_position, (SELECT av.position_id FROM core.assignment_version av
                                  WHERE av.assignment_id = p_assignment AND av.valid_period @> p_on AND upper_inf(av.sys_period))) AS position_id
  )
  SELECT 'credential_not_valid', w.text_en, w.source = 'legislation'
    FROM pos, who, talent.position_requirements(pos.position_id, p_on) w
   WHERE w.strength = 'required'
     AND EXISTS (SELECT 1 FROM jsonb_array_elements(w.satisfied_by) s WHERE s ? 'credential')
     AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(w.satisfied_by) s
                      WHERE s ? 'credential' AND talent.credential_valid(who.person_id, s ->> 'credential', p_on))
  UNION ALL
  SELECT 'training_before_work', i.code, false
    FROM who, talent.learning_assignment la JOIN talent.learning_item i ON i.item_id = la.item_id
   WHERE la.person_id = who.person_id AND la.blocks_work AND la.status IN ('assigned','in_progress')
$$;

CREATE FUNCTION talent.check_shift_readiness() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r record; law text; other text;
BEGIN
  IF NEW.published AND (TG_OP = 'INSERT' OR NOT OLD.published OR NEW.assignment_id IS DISTINCT FROM OLD.assignment_id
                        OR NEW.starts_at IS DISTINCT FROM OLD.starts_at) THEN
    FOR r IN SELECT * FROM talent.work_readiness(NEW.assignment_id, NEW.position_id, NEW.starts_at::date) LOOP
      IF r.by_law THEN law := concat_ws('; ', law, r.detail); ELSE other := concat_ws('; ', other, r.detail); END IF;
    END LOOP;
    IF law IS NOT NULL THEN
      RAISE EXCEPTION 'CREDENTIAL_REQUIRED_BY_LAW: % (no override: the law requires it for this work)', law USING ERRCODE = 'check_violation';
    END IF;
    IF other IS NOT NULL AND NOT platform.caution_cleared(NEW.tenant_id, 'learning.not_ready_for_work', 'shift', NEW.shift_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: learning.not_ready_for_work (%)', other USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a20_shift_readiness BEFORE INSERT OR UPDATE ON timeleave.shift
  FOR EACH ROW EXECUTE FUNCTION talent.check_shift_readiness();

-- -------------------------------------------------------------------------------------
-- 6. Skills consent and development plans (docs/29 §7)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.skills_consent (
  tenant_id    uuid NOT NULL,
  consent_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id    uuid NOT NULL REFERENCES core.person,       -- consent to show the skills profile for internal opportunities
  given_at     timestamptz NOT NULL,
  withdrawn_at timestamptz,
  CONSTRAINT skills_consent_order CHECK (withdrawn_at IS NULL OR withdrawn_at > given_at)
);
-- Whether managers and recruiters may see a person's skills profile for internal opportunities: only after they opt in
CREATE FUNCTION talent.skills_visible(p_person uuid, p_at timestamptz) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM talent.skills_consent c WHERE c.person_id = p_person
                   AND c.given_at <= p_at AND (c.withdrawn_at IS NULL OR c.withdrawn_at > p_at))
$$;

CREATE TABLE talent.development_plan (
  tenant_id     uuid NOT NULL,
  plan_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id     uuid NOT NULL REFERENCES core.person,
  employment_id uuid NOT NULL REFERENCES core.employment,
  period        daterange NOT NULL,
  proposed_by   uuid NOT NULL REFERENCES platform.app_user,
  employee_agreed_at timestamptz,
  manager_agreed_at  timestamptz,
  status        text NOT NULL CHECK (status IN ('draft','proposed','agreed','closed'))
);
CREATE TABLE talent.development_action (
  tenant_id     uuid NOT NULL,
  action_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id       uuid NOT NULL REFERENCES talent.development_plan,
  kind          text NOT NULL CHECK (kind IN ('experience','relationship','formal')),   -- 70-20-10
  title_en      text NOT NULL,
  title_fr      text,
  item_id       uuid REFERENCES talent.learning_item,
  goal_id       uuid REFERENCES talent.goal,        -- the development goal it serves (docs/28 §4.1)
  target_on     date,
  status        text NOT NULL CHECK (status IN ('planned','in_progress','done','dropped')),
  changed_by    uuid REFERENCES platform.app_user,
  change_reason text
);
CREATE TABLE talent.development_plan_change (
  tenant_id  uuid NOT NULL,
  change_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id    uuid NOT NULL REFERENCES talent.development_plan,
  action_id  uuid,
  changed_by uuid NOT NULL REFERENCES platform.app_user,
  changed_at timestamptz NOT NULL DEFAULT now(),
  reason     text,
  before     jsonb,
  after      jsonb
);
CREATE FUNCTION talent.check_development_plan() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'agreed' AND (NEW.employee_agreed_at IS NULL OR NEW.manager_agreed_at IS NULL) THEN
    RAISE EXCEPTION 'PLAN_NOT_AGREED: the employee and the manager both agree a development plan' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER development_plan_check BEFORE INSERT OR UPDATE ON talent.development_plan
  FOR EACH ROW EXECUTE FUNCTION talent.check_development_plan();

-- Once a plan is agreed, every added or changed action names who changed it, and the change is kept
CREATE FUNCTION talent.check_development_action() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE st text;
BEGIN
  SELECT status INTO st FROM talent.development_plan WHERE plan_id = NEW.plan_id;
  IF st = 'agreed' THEN
    IF NEW.changed_by IS NULL OR (TG_OP = 'UPDATE' AND NEW.changed_by IS NOT DISTINCT FROM OLD.changed_by
                                  AND NEW.change_reason IS NOT DISTINCT FROM OLD.change_reason) THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a change to an agreed development plan names who made it' USING ERRCODE = 'check_violation';
    END IF;
    INSERT INTO talent.development_plan_change (tenant_id, plan_id, action_id, changed_by, reason, before, after)
      VALUES (NEW.tenant_id, NEW.plan_id, NEW.action_id, NEW.changed_by, NEW.change_reason,
              CASE WHEN TG_OP = 'UPDATE' THEN to_jsonb(OLD) - 'changed_by' - 'change_reason' END,
              to_jsonb(NEW) - 'changed_by' - 'change_reason');
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER development_action_check BEFORE INSERT OR UPDATE ON talent.development_action
  FOR EACH ROW EXECUTE FUNCTION talent.check_development_action();

-- The 70-20-10 view of a plan, as guidance (docs/29 §7.3)
CREATE FUNCTION talent.development_mix(p_plan uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT coalesce(jsonb_object_agg(kind, round(100.0 * n / total, 0)), '{}'::jsonb)
    FROM (SELECT kind, count(*) AS n, sum(count(*)) OVER () AS total
            FROM talent.development_action WHERE plan_id = p_plan AND status <> 'dropped' GROUP BY kind) x
$$;

-- -------------------------------------------------------------------------------------
-- 7. Training requests, budgets, repayment, grants and the Quebec 1% rule (docs/29 §8, §9)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.training_budget (
  tenant_id    uuid NOT NULL,
  budget_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_unit_id  uuid NOT NULL REFERENCES core.org_unit,
  period       daterange NOT NULL,
  amount       numeric(14,2) NOT NULL CHECK (amount >= 0),
  per_employee_amount numeric(14,2) CHECK (per_employee_amount >= 0),   -- optional
  EXCLUDE USING gist (org_unit_id WITH =, period WITH &&)
);

CREATE TABLE talent.repayment_rule (
  tenant_id    uuid NOT NULL,
  rule_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL,
  kinds        text[] NOT NULL,                     -- request kinds it covers
  cost_from    numeric(14,2) NOT NULL CHECK (cost_from >= 0),
  cost_to      numeric(14,2),
  method       text NOT NULL CHECK (method IN ('none','prorated','full')),
  months       integer CHECK (months > 0),
  status       text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT repayment_rule_months CHECK ((method = 'none') = (months IS NULL)),
  CONSTRAINT repayment_rule_range CHECK (cost_to IS NULL OR cost_to > cost_from)
);

CREATE TABLE talent.training_request (
  tenant_id      uuid NOT NULL,
  request_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id      uuid NOT NULL REFERENCES core.person,
  employment_id  uuid NOT NULL REFERENCES core.employment,
  kind           text NOT NULL CHECK (kind IN ('course','certification','degree_program','conference','other')),
  item_id        uuid REFERENCES talent.learning_item,
  description    text NOT NULL,
  provider       text,
  starts_on      date,
  cost           numeric(14,2) NOT NULL CHECK (cost >= 0),
  time_off_hours numeric(6,2) CHECK (time_off_hours >= 0),
  business_case  text,
  budget_id      uuid REFERENCES talent.training_budget,
  funding_source_id uuid REFERENCES finance.funding_source,   -- a grant or training fund that pays part of it
  agreement_right text,                             -- the agreement clause it relies on, from the agreement library
  requested_by   uuid NOT NULL REFERENCES platform.app_user,
  route_id       uuid REFERENCES platform.workflow_route,
  status         text NOT NULL CHECK (status IN ('draft','submitted','approved','rejected','completed','reimbursed','cancelled')),
  primarily_for  text CHECK (primarily_for IN ('employer','employee')),   -- HR's mark, with CRA's guidance (taxable when employee)
  marked_by      uuid REFERENCES platform.app_user,
  repayment_rule_id uuid REFERENCES talent.repayment_rule,
  repayment_method text CHECK (repayment_method IN ('none','prorated','full')),
  repayment_months integer CHECK (repayment_months > 0),
  repayment_decided_by uuid REFERENCES platform.app_user,
  repayment_agreement_signed_at timestamptz,
  repayment_document_id uuid REFERENCES platform.document,
  wsdrf_eligible boolean,                           -- Quebec 1% (phase 2 report); null until assessed
  CONSTRAINT training_request_marked CHECK (primarily_for IS NULL OR marked_by IS NOT NULL),
  CONSTRAINT training_request_repayment_months CHECK (repayment_method IS NULL OR (repayment_method = 'none') = (repayment_months IS NULL))
);

-- The organization's repayment rule for a kind of training and its cost; two rules that fit are an error
CREATE FUNCTION talent.repayment_rule_for(p_tenant uuid, p_kind text, p_cost numeric) RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE ids uuid[];
BEGIN
  SELECT array_agg(rule_id) INTO ids FROM talent.repayment_rule
   WHERE tenant_id = p_tenant AND status = 'active' AND p_kind = ANY (kinds) AND p_cost >= cost_from AND (cost_to IS NULL OR p_cost < cost_to);
  IF cardinality(ids) > 1 THEN
    RAISE EXCEPTION 'REPAYMENT_RULE_AMBIGUOUS: % rules cover a % costing %', cardinality(ids), p_kind, p_cost USING ERRCODE = 'check_violation';
  END IF;
  RETURN ids[1];
END $$;

-- What is owed if the employee leaves on a date: the full cost, or the cost reduced month by month over the period
CREATE FUNCTION talent.repayment_owed(p_request uuid, p_completed_on date, p_leaving_on date) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT CASE
           WHEN r.repayment_method IS NULL OR r.repayment_method = 'none' THEN 0
           WHEN p_leaving_on >= (p_completed_on + make_interval(months => r.repayment_months))::date THEN 0
           WHEN r.repayment_method = 'full' THEN r.cost
           ELSE round(r.cost * (r.repayment_months - (EXTRACT(year FROM age(p_leaving_on, p_completed_on)) * 12
                                                      + EXTRACT(month FROM age(p_leaving_on, p_completed_on)))) / r.repayment_months, 2)
         END
    FROM talent.training_request r WHERE r.request_id = p_request
$$;

-- Spend against a budget: approved and later requests
CREATE FUNCTION talent.budget_remaining(p_budget uuid, p_except uuid) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT b.amount - coalesce((SELECT sum(r.cost) FROM talent.training_request r
                               WHERE r.budget_id = b.budget_id AND r.status IN ('approved','completed','reimbursed')
                                 AND r.request_id IS DISTINCT FROM p_except), 0)
    FROM talent.training_budget b WHERE b.budget_id = p_budget
$$;

-- The facts the organization's training request routes read (docs/29 §8.1); the HR amount is chosen at setup
CREATE FUNCTION talent.training_request_facts(p_request uuid) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
           'aboveHrAmount', r.cost > platform.setting_number(r.tenant_id, 'learning.request_hr_above_amount', current_date, e.legal_entity_id),
           'overBudget', r.budget_id IS NOT NULL AND r.cost > talent.budget_remaining(r.budget_id, r.request_id),
           'legalEntity', e.legal_entity_id)
    FROM talent.training_request r JOIN core.employment e ON e.employment_id = r.employment_id WHERE r.request_id = p_request
$$;

CREATE FUNCTION talent.check_training_request() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le uuid; no_rule text;
BEGIN
  IF NEW.status <> 'draft' AND NEW.route_id IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: a training request is submitted with its route' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved') THEN
    IF NOT platform.route_complete(NEW.route_id, 'training_request', NEW.request_id, NEW.requested_by, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the organization''s route for this request is not complete' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.budget_id IS NOT NULL AND NEW.cost > talent.budget_remaining(NEW.budget_id, NEW.request_id)
       AND NOT platform.caution_cleared(NEW.tenant_id, 'learning.over_budget', 'training_request', NEW.request_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: learning.over_budget' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.status = 'reimbursed' AND (TG_OP = 'INSERT' OR OLD.status <> 'reimbursed') AND NEW.cost > 0 THEN
    IF NEW.primarily_for IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: HR marks whether the training is mainly for the employer or for the employee (CRA) before it is paid'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.repayment_method IS NULL THEN
      NEW.repayment_rule_id := coalesce(NEW.repayment_rule_id, talent.repayment_rule_for(NEW.tenant_id, NEW.kind, NEW.cost));
      IF NEW.repayment_rule_id IS NOT NULL THEN
        SELECT method, months INTO NEW.repayment_method, NEW.repayment_months FROM talent.repayment_rule WHERE rule_id = NEW.repayment_rule_id;
      ELSE
        SELECT e.legal_entity_id INTO le FROM core.employment e WHERE e.employment_id = NEW.employment_id;
        no_rule := platform.setting_text(NEW.tenant_id, 'learning.repayment_without_rule', current_date, le);
        IF no_rule = 'no_repayment' THEN
          NEW.repayment_method := 'none';
        ELSE
          RAISE EXCEPTION 'INPUT_REQUIRED: no repayment rule covers this request; HR decides on repayment' USING ERRCODE = 'check_violation';
        END IF;
      END IF;
    END IF;
    IF NEW.repayment_method <> 'none' AND (NEW.repayment_agreement_signed_at IS NULL OR NEW.repayment_document_id IS NULL) THEN
      RAISE EXCEPTION 'REPAYMENT_AGREEMENT_REQUIRED: the employee signs the repayment agreement before reimbursement' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER training_request_check BEFORE INSERT OR UPDATE ON talent.training_request
  FOR EACH ROW EXECUTE FUNCTION talent.check_training_request();

-- Grant-funded training: claims against the program's funding source (docs/29 §9.2)
CREATE TABLE talent.grant_claim (
  tenant_id     uuid NOT NULL,
  claim_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  funding_source_id uuid NOT NULL REFERENCES finance.funding_source,
  period        daterange NOT NULL,
  eligible_cost numeric(14,2) NOT NULL CHECK (eligible_cost >= 0),
  employer_share numeric(14,2) NOT NULL CHECK (employer_share >= 0),
  amount_claimed numeric(14,2) NOT NULL CHECK (amount_claimed >= 0),
  status        text NOT NULL CHECK (status IN ('draft','submitted','paid','rejected')),
  document_id   uuid REFERENCES platform.document,
  CONSTRAINT grant_claim_amounts CHECK (amount_claimed + employer_share <= eligible_cost)
);

-- -------------------------------------------------------------------------------------
-- 8. Mentoring, basic at launch (docs/29 §10.1)
-- -------------------------------------------------------------------------------------
CREATE TABLE talent.mentoring_pair (
  tenant_id  uuid NOT NULL,
  pair_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  mentor_person_id uuid NOT NULL REFERENCES core.person,
  mentee_person_id uuid NOT NULL REFERENCES core.person,
  program_code text,
  purpose    text NOT NULL,
  period     daterange NOT NULL,
  paired_by  uuid NOT NULL REFERENCES platform.app_user,
  status     text NOT NULL CHECK (status IN ('active','ended')),
  CONSTRAINT mentoring_not_self CHECK (mentor_person_id <> mentee_person_id)
);
CREATE TABLE talent.mentoring_session (
  tenant_id  uuid NOT NULL,
  session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pair_id    uuid NOT NULL REFERENCES talent.mentoring_pair,
  held_on    date NOT NULL,
  notes      text,
  mentee_feedback text,
  mentor_feedback text
);

-- -------------------------------------------------------------------------------------
-- 9. Routes, cautions, no self-approval, text fields, row-level security
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.workflow_route DROP CONSTRAINT IF EXISTS workflow_route_subject_type_check;
ALTER TABLE platform.workflow_route ADD CONSTRAINT workflow_route_subject_type_check
  CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution',
                          'pay_run','voluntary_deduction','banked_time_payout',
                          'comp_philosophy','pay_structure_version','comp_decision','incentive_payout','salary_disclosure',
                          'carrier_invoice','timesheet','performance_review','pip','training_request'));

CREATE OR REPLACE FUNCTION platform.route_condition_fact(p_key text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_key
           WHEN 'requisitionTypes'  THEN 'requisitionType'
           WHEN 'employmentTypes'   THEN 'employmentType'
           WHEN 'term'              THEN 'term'
           WHEN 'overBudget'        THEN 'overBudget'
           WHEN 'outsideRange'      THEN 'outsideRange'
           WHEN 'postingExemption'  THEN 'postingExemption'
           WHEN 'unionized'         THEN 'unionized'
           WHEN 'legalEntities'     THEN 'legalEntity'
           WHEN 'orgUnits'          THEN 'orgUnit'
           WHEN 'probationKinds'    THEN 'probationKind'
           WHEN 'cautionCodes'      THEN 'cautionCode'
           WHEN 'minAnnualCost'     THEN 'annualCost'
           WHEN 'minOvertimeHours'  THEN 'overtimeHours'
           WHEN 'otherCostCentre'   THEN 'otherCostCentre'
           WHEN 'aboveHrAmount'     THEN 'aboveHrAmount'         -- a training request above the organization's HR amount
         END
$$;

INSERT INTO ref.workflow_route_starter (code, subject_type, name_en, name_fr, conditions, priority, decision_ref) VALUES
 ('training_request_hr', 'training_request', 'Training request above the HR amount', 'Demande de formation au-dessus du montant fixé pour les RH',
  '{"aboveHrAmount":true}', 10, 'docs/29 §8.1 (R5.2)'),
 ('training_request', 'training_request', 'Training request', 'Demande de formation', '{}', 20, 'docs/29 §8.1 (R5.2)');
INSERT INTO ref.workflow_route_step_starter (route_code, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr) VALUES
 ('training_request_hr', 1, 'requester_manager', NULL, 'any', 1, 'The employee''s manager', 'Le gestionnaire de l''employé'),
 ('training_request_hr', 2, 'capability', 'hr', 'any', 1, 'HR', 'RH'),
 ('training_request', 1, 'requester_manager', NULL, 'any', 1, 'The employee''s manager', 'Le gestionnaire de l''employé');

INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('learning.not_ready_for_work', 'learning', 'Not ready for this work', 'Pas prêt pour ce travail',
  'This person has not completed training required before this work, or a credential the position requires is not valid. Go ahead only for a real need and state why; the training or credential stays due.',
  'Cette personne n''a pas suivi une formation exigée avant ce travail, ou un titre exigé par le poste n''est pas valide. Ne poursuivez qu''en cas de besoin réel et indiquez pourquoi; la formation ou le titre demeure exigé.',
  true, false, 'docs/29 §6 (R2.1, R3.1)'),
 ('learning.over_budget', 'learning', 'Over the training budget', 'Dépassement du budget de formation',
  'This request is more than what is left in the department''s training budget. Approving it needs a reason, and finance approves as the organization''s route says.',
  'Cette demande dépasse ce qui reste du budget de formation du service. Son approbation exige une raison, et les finances l''approuvent comme le prévoit le circuit de l''organisation.',
  true, false, 'docs/29 §9.1 (R6.1)');

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
      ('talent','learning_item'), ('talent','learning_session'), ('talent','session_attendee'), ('talent','training_rule'),
      ('talent','learning_assignment'), ('talent','learning_completion'), ('talent','credential'), ('talent','ce_requirement'),
      ('talent','apprenticeship'), ('talent','apprenticeship_hours'), ('talent','skills_consent'), ('talent','development_plan'),
      ('talent','development_action'), ('talent','development_plan_change'), ('talent','training_budget'), ('talent','repayment_rule'),
      ('talent','training_request'), ('talent','grant_claim'), ('talent','mentoring_pair'), ('talent','mentoring_session')) AS x(s, t) LOOP
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
      RAISE NOTICE 'organization %: starter training request routes not copied because % is required for its data; add them with their texts (docs/29 §12)', t.tenant_id, langs;
    END IF;
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT, INSERT and UPDATE on the new tenant tables and EXECUTE on the new
-- functions; ref.training_requirement is written by the loader only. Credential documents and numbers are for HR;
-- managers see their teams' training status, employees their own, and a compliance role the organization grants sees
-- status across the organization (docs/29 §10.4).
