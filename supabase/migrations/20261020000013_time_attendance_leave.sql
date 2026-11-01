-- =====================================================================================
-- Migration 0013 · Time, attendance and leave decisions (docs/27)
--
-- Applies the owner's Module 06 review of 28 October 2026 (claude/review/06-time-attendance-leave-decisions.md).
-- Hours actually worked are always paid and payroll never waits; rules about hours, leave and schedules are the
-- organization's, set per plan or group at setup; the law's floors stop with a caution and a reason; statutory leaves
-- are never refused for staffing; no proof of leave and no biometric or location coordinates are stored.
--
--   §1  Settings
--   §2  Leave categories (CanDo's fixed list) and protected leave types
--   §3  Punches and time exceptions (unapproved overtime, unconfirmed breaks, rest periods and hours limits)
--   §4  Hours of work: averaging arrangements, overtime exemptions, how each group records time
--   §5  Timesheets: employee confirmation, the organization's optional second approval, the cut-off
--   §6  Leave plans: years, carry-over, negative balances, payout; declines; staffing levels and team availability
--   §7  The attendance management program
--   §8  Scheduling: notice and late changes, offers, swaps
--   §9  Cautions; no self-approval; text fields; row-level security
--
-- Run after 0012.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/27 §2)
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('time.punch_rounding_minutes', 'time', 'integer', NULL, '0', ARRAY['tenant','legal_entity'], false,
  'Rounding of punches to the nearest number of minutes, applied the same way up and down so it never systematically underpays. 0 pays the exact minutes.',
  'docs/27 §4.1 (R2.1)', 'decided', 0, 15, NULL),
 ('time.geofence', 'time', 'boolean', NULL, 'false', ARRAY['tenant','legal_entity'], false,
  'Check at punch time that a mobile punch is inside the work site. Only "inside or outside" is kept, never the coordinates.',
  'docs/27 §4.4 (R2.4)', 'decided', NULL, NULL, NULL),
 ('time.unapproved_overtime_alerts', 'time', 'json', NULL, '{"sameDay":["manager"],"beforePayroll":["manager","hr"]}', ARRAY['tenant','legal_entity'], false,
  'Who is told about hours worked beyond the schedule without approval: on the same day, and again before the payroll run. The hours are paid whatever happens; payroll never waits.',
  'docs/27 §4.3 (R2.3)', 'decided', NULL, NULL, ARRAY['sameDay','beforePayroll']),
 ('time.recording_method_starter', 'time', 'json', NULL, '{"hourly":"punch","daily":"punch","annual_salary":"exceptions","period_salary":"exceptions"}', ARRAY['tenant','legal_entity'], false,
  'How a position records time when no recording rule of the organization covers it, by the basis of its base pay: punches, a timesheet, or exceptions only (leave and overtime).',
  'docs/27 §5.4 (R3.4)', 'decided', NULL, NULL, ARRAY['hourly','daily','annual_salary','period_salary']),
 ('time.employee_confirmation', 'time', 'boolean', NULL, 'true', ARRAY['tenant','legal_entity'], false,
  'Employees confirm their own timesheet each pay period, with reminders. Payroll does not wait for them.',
  'docs/27 §6.4 (R4.4)', 'decided', NULL, NULL, NULL),
 ('time.correction_off_cycle', 'time', 'json', NULL, '{"aboveAmount":null}', ARRAY['tenant','legal_entity'], false,
  'A correction after the cut-off is paid in the next regular run; an off-cycle pay is proposed when waiting would miss the law''s pay deadline, or when the amount is above aboveAmount (none unless the organization sets one).',
  'docs/27 §6.3 (R4.3)', 'decided', NULL, NULL, ARRAY['aboveAmount']),
 ('time.averaging_reminder_days', 'time', 'integer_array', NULL, '[60, 30]', ARRAY['tenant','legal_entity'], false,
  'Days before an averaging agreement or permit ends when HR is reminded.',
  'docs/27 §5.2 (R3.2)', 'decided', NULL, NULL, NULL),
 ('attendance.program_enabled', 'attendance', 'boolean', NULL, 'false', ARRAY['tenant','legal_entity'], false,
  'The attendance management program (stages, letters and meetings). Protected absences are never counted and HR reviews before any disciplinary stage.',
  'docs/27 §8.4 (R1.4)', 'decided', NULL, NULL, NULL),
 ('absence.disability_check_after_days', 'attendance', 'integer', NULL, '5', ARRAY['tenant','legal_entity'], false,
  'Consecutive working days of absence after which HR is prompted to check short-term disability and accommodation.',
  'docs/27 §8.3 (R6.4)', 'decided', 1, NULL, NULL),
 ('leave.expiry_warning_days', 'leave', 'integer_array', NULL, '[60, 30]', ARRAY['tenant','legal_entity'], false,
  'Days before unused leave above the law''s minimum expires, and before the law''s window to schedule statutory vacation closes, when the employee and the manager are warned.',
  'docs/27 §7.1 (R5.1)', 'decided', NULL, NULL, NULL),
 ('leave.termination_payout_starter', 'leave', 'json', NULL, '{"vacation":"all","sick":"none","personal":"none"}', ARRAY['tenant','legal_entity'], false,
  'What a new leave plan pays out when employment ends, by leave category: all of the unused balance, only the law''s part, or none. Categories not listed state their rule on the plan; vacation never pays less than the law.',
  'docs/27 §7.3 (R5.3)', 'decided', NULL, NULL, NULL),
 ('leave.protected_categories', 'leave', 'text_array', NULL, '["domestic_violence","medical","family_caregiver","disability","workers_comp"]', ARRAY['tenant'], false,
  'Leave categories that managers see only as "protected leave"; only HR sees the reason. Domestic violence leave is always protected.',
  'docs/27 §8.2 (R6.3)', 'decided', NULL, NULL, NULL),
 ('scheduling.notice_days', 'scheduling', 'integer', NULL, '14', ARRAY['tenant','legal_entity'], false,
  'Days of notice before a published shift starts, where no agreement or law sets the notice. A change inside the notice needs the caution time.schedule_changed_late and a reason.',
  'docs/27 §9.1 (R7.1)', 'decided', 0, NULL, NULL);

-- -------------------------------------------------------------------------------------
-- 2. Leave categories (docs/27 §8): CanDo's fixed list that logic reads; each organization names its own leave types
-- -------------------------------------------------------------------------------------
CREATE TABLE ref.leave_category (
  category                     text PRIMARY KEY,
  name_en                      text NOT NULL,
  name_fr                      text NOT NULL,
  never_counted_for_attendance boolean NOT NULL,   -- protected under employment standards or human rights law
  reason_always_protected      boolean NOT NULL,   -- the law keeps the reason confidential
  decision_ref                 text NOT NULL
);
INSERT INTO ref.leave_category (category, name_en, name_fr, never_counted_for_attendance, reason_always_protected, decision_ref) VALUES
 ('vacation',            'Vacation',                              'Vacances',                                   false, false, 'docs/27 §8'),
 ('sick',                'Sick leave',                            'Congé de maladie',                           false, false, 'docs/27 §8'),
 ('medical',             'Medical or long-term illness leave',    'Congé médical ou pour maladie de longue durée', true, false, 'docs/27 §8'),
 ('pregnancy',           'Pregnancy or maternity leave',          'Congé de grossesse ou de maternité',          true,  false, 'docs/27 §8'),
 ('parental',            'Parental leave',                        'Congé parental',                              true,  false, 'docs/27 §8'),
 ('family_caregiver',    'Family, caregiver or compassionate care leave', 'Congé pour obligations familiales, de proche aidant ou de soignant', true, false, 'docs/27 §8'),
 ('bereavement',         'Bereavement leave',                     'Congé de deuil',                              true,  false, 'docs/27 §8'),
 ('domestic_violence',   'Domestic or sexual violence leave',     'Congé pour violence familiale ou sexuelle',   true,  true,  'docs/27 §8'),
 ('indigenous_practice', 'Indigenous practices or cultural leave', 'Congé pour pratiques autochtones ou culturelles', true, false, 'docs/27 §8'),
 ('civic',               'Jury, witness, voting, reservist or citizenship leave', 'Congé de juré, de témoin, de vote, de réserviste ou de citoyenneté', true, false, 'docs/27 §8'),
 ('public_health',       'Public health emergency or organ donor leave', 'Congé d''urgence de santé publique ou de don d''organe', true, false, 'docs/27 §8'),
 ('disability',          'Disability-related absence',            'Absence liée à une invalidité',               true,  false, 'docs/27 §8'),
 ('workers_comp',        'Workers'' compensation absence',         'Absence indemnisée par l''organisme d''indemnisation des accidentés du travail', true, false, 'docs/27 §8'),
 ('union_business',      'Union business leave',                  'Congé pour activités syndicales',             true,  false, 'docs/27 §8'),
 ('personal',            'Personal day',                          'Journée personnelle',                         false, false, 'docs/27 §8'),
 ('floating_holiday',    'Floating holiday',                      'Congé mobile',                                false, false, 'docs/27 §8'),
 ('education',           'Education or sabbatical leave',         'Congé d''études ou sabbatique',               false, false, 'docs/27 §8'),
 ('secondment',          'Secondment',                            'Détachement',                                 false, false, 'docs/27 §8'),
 ('deferred_salary',     'Deferred salary leave',                 'Congé à traitement différé',                  false, false, 'docs/27 §8'),
 ('unpaid_personal',     'Unpaid personal leave',                 'Congé personnel non payé',                    false, false, 'docs/27 §8'),
 ('other',               'Other leave',                           'Autre congé',                                 false, false, 'docs/27 §8');

ALTER TABLE timeleave.leave_type ADD CONSTRAINT leave_type_category_fk FOREIGN KEY (category) REFERENCES ref.leave_category NOT VALID;

-- Whether managers see the leave type or only "protected leave" comes from the organization's protected categories,
-- unless the leave type states it; domestic violence leave is always protected (docs/27 §8.2)
CREATE FUNCTION timeleave.check_leave_type_setup() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE always boolean;
BEGIN
  SELECT c.reason_always_protected INTO always FROM ref.leave_category c WHERE c.category = NEW.category;
  IF always IS NULL THEN
    RAISE EXCEPTION 'LIST_VALUE_UNKNOWN: % is not a leave category (ref.leave_category)', NEW.category USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.reason_restricted IS NULL THEN
    NEW.reason_restricted := platform.setting(NEW.tenant_id, 'leave.protected_categories') ? NEW.category;
  END IF;
  IF always AND NOT NEW.reason_restricted THEN
    RAISE EXCEPTION 'LEAVE_REASON_MUST_BE_PROTECTED: the law keeps the reason for % leave confidential', NEW.category USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a10_leave_type_setup BEFORE INSERT OR UPDATE ON timeleave.leave_type
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_leave_type_setup();

-- An absence HR knows is protected under human rights law (disability, accommodation, workers' compensation)
ALTER TABLE timeleave.leave_request
  ADD COLUMN protected_reason text CHECK (protected_reason IN ('disability','accommodation','workers_comp','human_rights_other'));

-- -------------------------------------------------------------------------------------
-- 3. Punches and time exceptions (docs/27 §4, §5.1)
-- -------------------------------------------------------------------------------------
ALTER TABLE timeleave.punch DROP CONSTRAINT IF EXISTS punch_kind_check;
ALTER TABLE timeleave.punch ADD CONSTRAINT punch_kind_check
  CHECK (kind IN ('in','out','break_start','break_end','break_confirmed','job_switch'));
ALTER TABLE timeleave.punch
  ADD COLUMN source text CHECK (source IN ('mobile','web','kiosk','clock','import','manual')),
  ADD CONSTRAINT punch_source_stated CHECK (source IS NOT NULL) NOT VALID,
  ADD CONSTRAINT punch_edit_reason CHECK (edited_by IS NULL OR coalesce(length(btrim(edit_reason)), 0) > 0) NOT VALID;

-- What the time engine flags for people to look at. A flag never removes paid hours: hours worked are paid.
CREATE TABLE timeleave.time_exception (
  tenant_id     uuid NOT NULL,
  exception_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES core.assignment,
  shift_id      uuid REFERENCES timeleave.shift,
  timesheet_id  uuid REFERENCES timeleave.timesheet,
  work_date     date NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('unapproved_overtime','unconfirmed_break','missed_punch','rest_period','hours_limit','schedule_variance')),
  hours         numeric(8,2),
  rule_source   text,                          -- 'es:ON excess_hours' | 'agreement:EXAMPLE-MUNI-0001#2:16.05'
  detected_at   timestamptz NOT NULL DEFAULT now(),
  same_day_notice_at   timestamptz,
  pre_payroll_notice_at timestamptz,
  status        text NOT NULL CHECK (status IN ('open','approved','not_authorized','corrected','acknowledged')),
  decided_by    uuid REFERENCES platform.app_user,
  decided_at    timestamptz,
  reason        text,
  CONSTRAINT time_exception_decided CHECK (status = 'open' OR (decided_by IS NOT NULL AND decided_at IS NOT NULL)),
  CONSTRAINT time_exception_reason CHECK (status NOT IN ('not_authorized','corrected','acknowledged') OR coalesce(length(btrim(reason)), 0) > 0),
  CONSTRAINT time_exception_not_authorized CHECK (status <> 'not_authorized' OR kind = 'unapproved_overtime'),
  CONSTRAINT time_exception_acknowledged CHECK (status <> 'acknowledged' OR kind IN ('rest_period','hours_limit'))
);
CREATE INDEX time_exception_open ON timeleave.time_exception (tenant_id, assignment_id, work_date) WHERE status = 'open';

CREATE FUNCTION timeleave.check_time_exception() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'acknowledged' AND (TG_OP = 'INSERT' OR OLD.status <> 'acknowledged')
     AND NOT platform.caution_cleared(NEW.tenant_id, 'time.rest_or_hours_limit', 'time_exception', NEW.exception_id) THEN
    RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: time.rest_or_hours_limit' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER time_exception_check BEFORE INSERT OR UPDATE ON timeleave.time_exception
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_time_exception();

-- -------------------------------------------------------------------------------------
-- 4. Hours of work (docs/27 §5)
-- -------------------------------------------------------------------------------------
-- 4.1 Averaging agreements and permits, with their document, who they cover and their end date
CREATE TABLE timeleave.averaging_arrangement (
  tenant_id       uuid NOT NULL,
  arrangement_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id uuid NOT NULL REFERENCES core.legal_entity,
  jurisdiction    ref.jurisdiction_code NOT NULL,
  kind            text NOT NULL CHECK (kind IN ('written_agreement','government_permit','collective_agreement')),
  agreement_id    text,
  document_id     uuid REFERENCES platform.document,
  applies_to      jsonb NOT NULL,
  cycle_weeks     smallint NOT NULL CHECK (cycle_weeks >= 2),
  anchor_date     date NOT NULL,
  valid_period    daterange NOT NULL,
  recorded_by     uuid NOT NULL REFERENCES platform.app_user,
  FOREIGN KEY (tenant_id, agreement_id) REFERENCES core.agreement (tenant_id, agreement_id),
  CONSTRAINT averaging_document CHECK (kind = 'collective_agreement' OR document_id IS NOT NULL),
  CONSTRAINT averaging_agreement CHECK ((kind = 'collective_agreement') = (agreement_id IS NOT NULL)),
  CONSTRAINT averaging_ends CHECK (kind = 'collective_agreement' OR NOT upper_inf(valid_period)),
  CONSTRAINT averaging_scope_object CHECK (jsonb_typeof(applies_to) = 'object')
);
CREATE TRIGGER averaging_arrangement_scope BEFORE INSERT OR UPDATE OF applies_to ON timeleave.averaging_arrangement
  FOR EACH ROW EXECUTE FUNCTION payroll.check_scope_keys();

-- The arrangement covering a position on a date; none means the law's weekly rule; two is an error
CREATE FUNCTION timeleave.averaging_for(p_assignment uuid, p_on date) RETURNS timeleave.averaging_arrangement
LANGUAGE plpgsql STABLE AS $$
DECLARE f jsonb; r timeleave.averaging_arrangement; n int;
BEGIN
  f := payroll.assignment_scope_facts(p_assignment, p_on);
  IF f IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: position % is not held on %', p_assignment, p_on USING ERRCODE = 'check_violation';
  END IF;
  SELECT count(*) INTO n FROM timeleave.averaging_arrangement x
    JOIN core.assignment a ON a.tenant_id = x.tenant_id AND a.assignment_id = p_assignment
   WHERE x.valid_period @> p_on AND payroll.scope_matches(x.applies_to, f);
  IF n > 1 THEN
    RAISE EXCEPTION 'AVERAGING_CONFLICT: % averaging arrangements cover position % on %; HR ends one', n, p_assignment, p_on USING ERRCODE = 'check_violation';
  END IF;
  SELECT x.* INTO r FROM timeleave.averaging_arrangement x
    JOIN core.assignment a ON a.tenant_id = x.tenant_id AND a.assignment_id = p_assignment
   WHERE x.valid_period @> p_on AND payroll.scope_matches(x.applies_to, f);
  RETURN r;
END $$;

-- 4.2 Overtime exemptions: HR picks one of the province's exemptions (rules file) with its legal basis
CREATE TABLE timeleave.overtime_exemption (
  tenant_id      uuid NOT NULL,
  exemption_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position_id    uuid NOT NULL REFERENCES core.position,
  jurisdiction   ref.jurisdiction_code NOT NULL,
  exemption_code text NOT NULL,            -- from overtime_exemptions in rules/employment-standards/ca-2026-time-additions.json
  legal_basis    text NOT NULL CHECK (length(btrim(legal_basis)) > 0),
  reason         text NOT NULL CHECK (length(btrim(reason)) > 0),
  decided_by     uuid NOT NULL REFERENCES platform.app_user,
  decided_at     timestamptz NOT NULL DEFAULT now(),
  valid_period   daterange NOT NULL,
  EXCLUDE USING gist (position_id WITH =, valid_period WITH &&)
);
CREATE FUNCTION timeleave.overtime_exempt(p_position uuid, p_on date) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM timeleave.overtime_exemption x WHERE x.position_id = p_position AND x.valid_period @> p_on)
$$;

-- 4.3 How each group records time (punches, a timesheet, or exceptions only)
CREATE TABLE timeleave.recording_rule (
  tenant_id  uuid NOT NULL REFERENCES platform.tenant,
  rule_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL,
  name_en    text NOT NULL,
  name_fr    text,
  applies_to jsonb NOT NULL,
  method     text NOT NULL CHECK (method IN ('punch','timesheet','exceptions')),
  priority   smallint NOT NULL,
  status     text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT recording_rule_scope_object CHECK (jsonb_typeof(applies_to) = 'object')
);
CREATE UNIQUE INDEX recording_rule_priority ON timeleave.recording_rule (tenant_id, priority) WHERE status = 'active';
CREATE TRIGGER recording_rule_scope BEFORE INSERT OR UPDATE OF applies_to ON timeleave.recording_rule
  FOR EACH ROW EXECUTE FUNCTION payroll.check_scope_keys();

CREATE FUNCTION timeleave.recording_method_for(p_assignment uuid, p_on date) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE f jsonb; m text; basis text; t uuid; le uuid;
BEGIN
  f := payroll.assignment_scope_facts(p_assignment, p_on);
  IF f IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: position % is not held on %', p_assignment, p_on USING ERRCODE = 'check_violation';
  END IF;
  SELECT a.tenant_id, e.legal_entity_id INTO t, le FROM core.assignment a JOIN core.employment e ON e.employment_id = a.employment_id
   WHERE a.assignment_id = p_assignment;
  SELECT r.method INTO m FROM timeleave.recording_rule r
   WHERE r.tenant_id = t AND r.status = 'active' AND payroll.scope_matches(r.applies_to, f)
   ORDER BY r.priority LIMIT 1;
  IF m IS NOT NULL THEN RETURN m; END IF;
  SELECT v.basis INTO basis FROM core.pay_rate p JOIN core.pay_rate_version v ON v.pay_rate_id = p.pay_rate_id
   WHERE p.assignment_id = p_assignment AND p.component = 'base' AND v.valid_period @> p_on AND upper_inf(v.sys_period);
  IF basis IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: position % has no base pay on %, so how it records time is not known', p_assignment, p_on USING ERRCODE = 'check_violation';
  END IF;
  m := platform.setting(t, 'time.recording_method_starter', p_on, le) ->> basis;
  IF m IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: time.recording_method_starter names no method for % pay', basis USING ERRCODE = 'check_violation';
  END IF;
  RETURN m;
END $$;

-- -------------------------------------------------------------------------------------
-- 5. Timesheets (docs/27 §6)
-- -------------------------------------------------------------------------------------
ALTER TABLE timeleave.timesheet
  ADD COLUMN employee_confirmed_at  timestamptz,
  ADD COLUMN route_id               uuid REFERENCES platform.workflow_route,     -- the organization's second-approval route, when one matches
  ADD COLUMN locked_at              timestamptz,
  ADD COLUMN reviewed_after_lock_by uuid REFERENCES platform.app_user,
  ADD COLUMN reviewed_after_lock_at timestamptz,
  ADD CONSTRAINT timesheet_approved_complete CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)) NOT VALID;

ALTER TABLE platform.workflow_route DROP CONSTRAINT IF EXISTS workflow_route_subject_type_check;
ALTER TABLE platform.workflow_route ADD CONSTRAINT workflow_route_subject_type_check
  CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution',
                          'pay_run','voluntary_deduction','banked_time_payout',
                          'comp_philosophy','pay_structure_version','comp_decision','incentive_payout','salary_disclosure',
                          'carrier_invoice','timesheet'));

-- Conditions an organization can put on a timesheet route: overtime above a number of hours, time charged to another
-- department's cost centre (adds to 0009 §3)
CREATE OR REPLACE FUNCTION platform.route_condition_fact(p_key text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_key
           WHEN 'requisitionTypes'  THEN 'requisitionType'       -- category of the organization's requisition type
           WHEN 'employmentTypes'   THEN 'employmentType'        -- category of the organization's employment type
           WHEN 'term'              THEN 'term'                  -- the hire has an end date
           WHEN 'overBudget'        THEN 'overBudget'
           WHEN 'outsideRange'      THEN 'outsideRange'          -- offer pay outside the grade range or agreement step
           WHEN 'postingExemption'  THEN 'postingExemption'      -- filled under a posting exemption rule
           WHEN 'unionized'         THEN 'unionized'
           WHEN 'legalEntities'     THEN 'legalEntity'
           WHEN 'orgUnits'          THEN 'orgUnit'
           WHEN 'probationKinds'    THEN 'probationKind'
           WHEN 'cautionCodes'      THEN 'cautionCode'
           WHEN 'minAnnualCost'     THEN 'annualCost'
           WHEN 'minOvertimeHours'  THEN 'overtimeHours'         -- overtime hours on the timesheet
           WHEN 'otherCostCentre'   THEN 'otherCostCentre'       -- time charged to a cost centre outside the approver's area
         END
$$;

CREATE OR REPLACE FUNCTION platform.route_matches(p_conditions jsonb, p_facts jsonb) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE k text; v jsonb; f jsonb;
BEGIN
  FOR k, v IN SELECT * FROM jsonb_each(p_conditions) LOOP
    f := p_facts -> platform.route_condition_fact(k);
    IF f IS NULL OR jsonb_typeof(f) = 'null' THEN
      RAISE EXCEPTION 'ROUTE_FACT_MISSING: % is needed to choose a route', platform.route_condition_fact(k) USING ERRCODE = 'check_violation';
    END IF;
    IF k IN ('minAnnualCost','minOvertimeHours') THEN
      IF (f #>> '{}')::numeric < (v #>> '{}')::numeric THEN RETURN false; END IF;
    ELSIF jsonb_typeof(v) = 'array' THEN
      IF NOT (v @> jsonb_build_array(f)) THEN RETURN false; END IF;
    ELSIF v <> f THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
END $$;

-- The user who is the employee of a position (for self-approval checks)
CREATE FUNCTION timeleave.employee_user(p_assignment uuid) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT u.user_id FROM core.assignment a JOIN core.employment e ON e.employment_id = a.employment_id
    JOIN platform.app_user u ON u.tenant_id = a.tenant_id AND u.person_id = e.person_id
   WHERE a.assignment_id = p_assignment LIMIT 1
$$;

-- Second approvals are optional: a timesheet whose facts match none of the organization's timesheet routes needs
-- only its manager's approval (FB-037, docs/27 §6.1)
CREATE FUNCTION timeleave.timesheet_route(p_tenant uuid, p_facts jsonb) RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT route_id, conditions FROM platform.workflow_route
            WHERE tenant_id = p_tenant AND subject_type = 'timesheet' AND status = 'active' ORDER BY priority LOOP
    IF platform.route_matches(r.conditions, p_facts) THEN RETURN r.route_id; END IF;
  END LOOP;
  RETURN NULL;   -- fallback: FB-037
END $$;

CREATE FUNCTION timeleave.check_timesheet() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE emp uuid;
BEGIN
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved') THEN
    emp := timeleave.employee_user(NEW.assignment_id);
    IF NEW.approved_by IS NOT DISTINCT FROM emp THEN
      RAISE EXCEPTION 'SELF_APPROVAL: the requester cannot approve their own timesheet' USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM timeleave.time_exception x WHERE x.timesheet_id = NEW.timesheet_id
                 AND x.kind IN ('rest_period','hours_limit') AND x.status = 'open') THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: time.rest_or_hours_limit' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.route_id IS NOT NULL AND NOT platform.route_complete(NEW.route_id, 'timesheet', NEW.timesheet_id, emp, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the timesheet''s second approval is not complete' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  -- At the cut-off a timesheet is locked and paid as recorded, approved or not (R4.2)
  IF NEW.status = 'locked' AND (TG_OP = 'INSERT' OR OLD.status <> 'locked') THEN
    NEW.locked_at := coalesce(NEW.locked_at, now());
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER timesheet_check BEFORE INSERT OR UPDATE ON timeleave.timesheet
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_timesheet();

-- -------------------------------------------------------------------------------------
-- 6. Leave plans (docs/27 §7, §8.5)
-- -------------------------------------------------------------------------------------
CREATE TABLE timeleave.leave_plan (
  tenant_id            uuid NOT NULL REFERENCES platform.tenant,
  plan_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                 text NOT NULL,                 -- the ledger's plan_code
  name_en              text NOT NULL,
  name_fr              text,
  leave_type_code      text NOT NULL,
  agreement_id         text,                          -- the agreement that owns the plan; none for a policy plan
  applies_to           jsonb NOT NULL,
  accrual_method       text NOT NULL CHECK (accrual_method IN ('front_loaded','per_pay_period','per_hour','percent_of_wages','none')),
  tiers                jsonb,                         -- [{"fromYears":0,"hours":80},{"fromYears":5,"hours":120}] or percentages
  year_basis           text NOT NULL CHECK (year_basis IN ('calendar','fiscal','hire_anniversary','service_anniversary','plan_entry')),
  year_calendar_id     uuid REFERENCES finance.calendar,
  tier_step_basis      text NOT NULL CHECK (tier_step_basis IN ('year_start','hire_anniversary','service_anniversary','plan_entry')),
  carry_over           jsonb NOT NULL,                -- {"kind":"none"} | {"kind":"limited","limitHours":40,"expiresMonths":3} | {"kind":"unlimited"}
  negative_limit_hours numeric(8,2) CHECK (negative_limit_hours > 0),   -- none: no negative balance
  termination_payout   text CHECK (termination_payout IN ('all','statutory_only','none')),
  priority             smallint NOT NULL,
  status               text NOT NULL CHECK (status IN ('active','retired')),
  valid_period         daterange NOT NULL,
  FOREIGN KEY (tenant_id, leave_type_code) REFERENCES timeleave.leave_type (tenant_id, leave_type_code),
  FOREIGN KEY (tenant_id, agreement_id) REFERENCES core.agreement (tenant_id, agreement_id),
  EXCLUDE USING gist (tenant_id WITH =, code WITH =, valid_period WITH &&),
  CONSTRAINT leave_plan_tiers CHECK ((accrual_method = 'none') = (tiers IS NULL)),
  CONSTRAINT leave_plan_fiscal_calendar CHECK ((year_basis = 'fiscal') = (year_calendar_id IS NOT NULL)),
  CONSTRAINT leave_plan_scope_object CHECK (jsonb_typeof(applies_to) = 'object')
);
CREATE TRIGGER leave_plan_scope BEFORE INSERT OR UPDATE OF applies_to ON timeleave.leave_plan
  FOR EACH ROW EXECUTE FUNCTION payroll.check_scope_keys();

CREATE FUNCTION timeleave.check_leave_plan() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cat text; k text; ck text;
BEGIN
  SELECT lt.category INTO cat FROM timeleave.leave_type lt WHERE lt.tenant_id = NEW.tenant_id AND lt.leave_type_code = NEW.leave_type_code;
  k := NEW.carry_over ->> 'kind';
  IF k IS NULL OR k NOT IN ('none','limited','unlimited')
     OR (k = 'limited' AND coalesce((NEW.carry_over ->> 'limitHours')::numeric, 0) <= 0)
     OR (k = 'limited' AND NEW.carry_over ? 'expiresMonths' AND coalesce((NEW.carry_over ->> 'expiresMonths')::numeric, 0) < 1) THEN
    RAISE EXCEPTION 'LEAVE_CARRYOVER_INVALID: %', NEW.carry_over USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.year_calendar_id IS NOT NULL THEN
    SELECT c.kind INTO ck FROM finance.calendar c WHERE c.calendar_id = NEW.year_calendar_id;
    IF ck NOT IN ('fiscal','leave_year') THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a plan''s fiscal year comes from a fiscal or leave-year calendar, not a % calendar', ck USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.termination_payout IS NULL THEN
    NEW.termination_payout := platform.setting(NEW.tenant_id, 'leave.termination_payout_starter') ->> cat;
  END IF;
  IF NEW.termination_payout IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: plan % states what is paid out when employment ends', NEW.code USING ERRCODE = 'check_violation';
  END IF;
  IF cat = 'vacation' AND NEW.termination_payout = 'none' THEN
    RAISE EXCEPTION 'LEAVE_PAYOUT_BELOW_LAW: unused vacation is paid out when employment ends, at least the law''s part' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a10_leave_plan_setup BEFORE INSERT OR UPDATE ON timeleave.leave_plan
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_leave_plan();

-- The plan of a leave type that covers a position on a date
CREATE FUNCTION timeleave.leave_plan_for(p_assignment uuid, p_leave_type text, p_on date) RETURNS timeleave.leave_plan
LANGUAGE plpgsql STABLE AS $$
DECLARE f jsonb; r timeleave.leave_plan; n int;
BEGIN
  f := payroll.assignment_scope_facts(p_assignment, p_on);
  IF f IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: position % is not held on %', p_assignment, p_on USING ERRCODE = 'check_violation';
  END IF;
  SELECT p.* INTO r FROM timeleave.leave_plan p JOIN core.assignment a ON a.tenant_id = p.tenant_id AND a.assignment_id = p_assignment
   WHERE p.leave_type_code = p_leave_type AND p.status = 'active' AND p.valid_period @> p_on AND payroll.scope_matches(p.applies_to, f)
   ORDER BY p.priority LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LEAVE_PLAN_MISSING: no % plan covers position % on %', p_leave_type, p_assignment, p_on USING ERRCODE = 'check_violation';
  END IF;
  SELECT count(*) INTO n FROM timeleave.leave_plan p JOIN core.assignment a ON a.tenant_id = p.tenant_id AND a.assignment_id = p_assignment
   WHERE p.leave_type_code = p_leave_type AND p.status = 'active' AND p.valid_period @> p_on AND payroll.scope_matches(p.applies_to, f)
     AND p.priority = r.priority;
  IF n > 1 THEN
    RAISE EXCEPTION 'LEAVE_PLAN_AMBIGUOUS: % plans of % share priority % for position %', n, p_leave_type, r.priority, p_assignment USING ERRCODE = 'check_violation';
  END IF;
  RETURN r;
END $$;

-- When a person joined a plan through an event (hire, promotion, becoming exempt, a move of location or agreement)
CREATE TABLE timeleave.plan_entry (
  tenant_id     uuid NOT NULL,
  entry_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  plan_code     text NOT NULL,
  entered_on    date NOT NULL,
  event         text NOT NULL CHECK (event IN ('hire','promotion','became_exempt','location_move','agreement_move','other')),
  change_set_id uuid,
  UNIQUE (employment_id, plan_code, entered_on)
);

-- The latest anniversary of p_anchor on or before p_on
CREATE FUNCTION timeleave.last_anniversary(p_anchor date, p_on date) RETURNS date LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p_on < p_anchor THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: % is before the anchor date %', p_on, p_anchor USING ERRCODE = 'check_violation';
  END IF;
  RETURN (p_anchor + make_interval(years => extract(year FROM age(p_on, p_anchor))::int))::date;
END $$;

-- The start of the current cycle of a plan on a date, for its year or for its service tiers (docs/27 §7.4)
CREATE FUNCTION timeleave.plan_cycle_start(p_plan uuid, p_employment uuid, p_on date, p_for text) RETURNS date
LANGUAGE plpgsql STABLE AS $$
DECLARE p timeleave.leave_plan; b text; d date; yl text;
BEGIN
  SELECT * INTO p FROM timeleave.leave_plan WHERE plan_id = p_plan;
  IF p_for = 'year' THEN b := p.year_basis;
  ELSIF p_for = 'tiers' THEN b := CASE WHEN p.tier_step_basis = 'year_start' THEN p.year_basis ELSE p.tier_step_basis END;
  ELSE RAISE EXCEPTION 'INPUT_REQUIRED: p_for is year or tiers' USING ERRCODE = 'check_violation';
  END IF;
  IF b = 'calendar' THEN
    RETURN date_trunc('year', p_on)::date;
  ELSIF b = 'fiscal' THEN
    SELECT cp.year_label INTO yl FROM finance.calendar_period cp WHERE cp.calendar_id = p.year_calendar_id AND cp.dates @> p_on;
    SELECT min(lower(cp.dates)) INTO d FROM finance.calendar_period cp WHERE cp.calendar_id = p.year_calendar_id AND cp.year_label = yl;
    IF d IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: the plan''s calendar has no period on %', p_on USING ERRCODE = 'check_violation';
    END IF;
    RETURN d;
  ELSIF b IN ('hire_anniversary','service_anniversary') THEN
    SELECT CASE WHEN b = 'hire_anniversary' THEN v.original_hire_date ELSE v.continuous_service_date END INTO d
      FROM core.employment_version v WHERE v.employment_id = p_employment AND v.valid_period @> p_on AND upper_inf(v.sys_period);
    IF d IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: employment % has no version on %', p_employment, p_on USING ERRCODE = 'check_violation';
    END IF;
    RETURN timeleave.last_anniversary(d, p_on);
  ELSE  -- plan_entry
    SELECT max(e.entered_on) INTO d FROM timeleave.plan_entry e
     WHERE e.employment_id = p_employment AND e.plan_code = p.code AND e.entered_on <= p_on;
    IF d IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: no entry into plan % is recorded for employment %', p.code, p_employment USING ERRCODE = 'check_violation';
    END IF;
    RETURN timeleave.last_anniversary(d, p_on);
  END IF;
END $$;

-- A declined part of a leave request states why; a statutory leave is never refused for staffing (docs/27 §8.5)
ALTER TABLE timeleave.leave_request_component
  ADD COLUMN decline_category text CHECK (decline_category IN ('staffing','blackout','balance','other')),
  ADD COLUMN decline_reason   text;

CREATE FUNCTION timeleave.check_leave_component() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE stat boolean;
BEGIN
  IF NEW.status = 'declined' AND (TG_OP = 'INSERT' OR OLD.status <> 'declined') THEN
    IF NEW.decline_category IS NULL OR coalesce(length(btrim(NEW.decline_reason)), 0) = 0 THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a declined leave states its category and reason' USING ERRCODE = 'check_violation';
    END IF;
    SELECT lt.statutory INTO stat FROM timeleave.leave_request r
      JOIN timeleave.leave_type lt ON lt.tenant_id = r.tenant_id AND lt.leave_type_code = r.leave_type_code
     WHERE r.leave_request_id = NEW.leave_request_id;
    IF stat AND NEW.decline_category IN ('staffing','blackout') THEN
      RAISE EXCEPTION 'STATUTORY_LEAVE_NOT_REFUSABLE: a statutory leave is never refused for staffing or a blackout period' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER leave_component_check BEFORE INSERT OR UPDATE ON timeleave.leave_request_component
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_leave_component();

-- Managers decline through their approval parts (docs/20): a decline decision carries its category and reason, and
-- a statutory leave is never declined for staffing or a blackout period
CREATE FUNCTION core.check_part_decline() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE stat boolean; e jsonb;
BEGIN
  IF NEW.subject_type <> 'leave_request' THEN RETURN NEW; END IF;
  SELECT lt.statutory INTO stat FROM timeleave.leave_request r
    JOIN timeleave.leave_type lt ON lt.tenant_id = r.tenant_id AND lt.leave_type_code = r.leave_type_code
   WHERE r.leave_request_id = NEW.subject_id;
  FOR e IN SELECT x FROM jsonb_array_elements(NEW.decisions) x WHERE x ->> 'decision' = 'decline' LOOP
    IF coalesce(e ->> 'category', '') NOT IN ('staffing','blackout','balance','other') OR coalesce(length(btrim(e ->> 'reason')), 0) = 0 THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a declined leave states its category (staffing, blackout, balance, other) and reason' USING ERRCODE = 'check_violation';
    END IF;
    IF stat AND e ->> 'category' IN ('staffing','blackout') THEN
      RAISE EXCEPTION 'STATUTORY_LEAVE_NOT_REFUSABLE: a statutory leave is never refused for staffing or a blackout period' USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER approval_part_decline_check BEFORE INSERT OR UPDATE ON core.approval_part
  FOR EACH ROW EXECUTE FUNCTION core.check_part_decline();

-- The component keeps the category and reason of the decline that decided it (replaces 0006's roll-up)
CREATE OR REPLACE FUNCTION core.roll_up_leave_request() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c text; r text; d jsonb;
BEGIN
  IF NEW.subject_type <> 'leave_request' THEN RETURN NEW; END IF;
  SELECT core.roll_up(array_agg(status)) INTO c FROM core.approval_part
    WHERE subject_type = 'leave_request' AND subject_id = NEW.subject_id AND assignment_id = NEW.assignment_id;
  SELECT x INTO d FROM core.approval_part p, jsonb_array_elements(p.decisions) WITH ORDINALITY AS t(x, ord)
   WHERE p.subject_type = 'leave_request' AND p.subject_id = NEW.subject_id AND p.assignment_id = NEW.assignment_id
     AND x ->> 'decision' = 'decline'
   ORDER BY p.seq, t.ord LIMIT 1;
  UPDATE timeleave.leave_request_component
     SET status = CASE c WHEN 'pending' THEN 'requested' ELSE c END,
         decline_category = CASE WHEN c = 'declined' THEN d ->> 'category' ELSE decline_category END,
         decline_reason   = CASE WHEN c = 'declined' THEN d ->> 'reason' ELSE decline_reason END
    WHERE leave_request_id = NEW.subject_id AND assignment_id = NEW.assignment_id AND status <> 'taken';
  SELECT core.roll_up(array_agg(status)) INTO r FROM core.approval_part
    WHERE subject_type = 'leave_request' AND subject_id = NEW.subject_id;
  UPDATE timeleave.leave_request SET status = CASE r WHEN 'pending' THEN 'requested' ELSE r END
    WHERE leave_request_id = NEW.subject_id AND status NOT IN ('taken');
  RETURN NEW;
END $$;

-- Minimum staffing and blackout periods, for warnings and the team availability bar
CREATE TABLE timeleave.staffing_level (
  tenant_id    uuid NOT NULL,
  level_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_unit_id  uuid NOT NULL REFERENCES core.org_unit,
  days_of_week smallint[] NOT NULL,           -- ISO days, 1 = Monday
  min_staff    smallint NOT NULL CHECK (min_staff >= 0),
  valid_period daterange NOT NULL,
  CONSTRAINT staffing_days CHECK (cardinality(days_of_week) > 0 AND days_of_week <@ '{1,2,3,4,5,6,7}'::smallint[])
);
CREATE TABLE timeleave.blackout_period (
  tenant_id   uuid NOT NULL,
  blackout_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_unit_id uuid NOT NULL REFERENCES core.org_unit,
  period      daterange NOT NULL,
  reason      text NOT NULL CHECK (length(btrim(reason)) > 0),
  created_by  uuid NOT NULL REFERENCES platform.app_user
);

-- The team availability bar: a level per day, never names or counts. Requested, approved and taken leave count as away.
-- Where several staffing levels apply on a day, the highest minimum is used; a day with none is "unknown".
CREATE FUNCTION timeleave.team_availability(p_org_unit uuid, p_from date, p_to date)
RETURNS TABLE (day date, level text) LANGUAGE sql STABLE AS $$
  WITH days AS (SELECT d::date AS day FROM generate_series(p_from, p_to, interval '1 day') d),
  unit AS (
    SELECT days.day, av.assignment_id FROM days
      JOIN core.assignment_version av ON av.org_unit_id = p_org_unit AND av.valid_period @> days.day AND upper_inf(av.sys_period)
                                     AND av.status NOT IN ('ended','on_leave','laid_off')),
  away AS (
    SELECT u.day, count(DISTINCT u.assignment_id) AS n FROM unit u
      JOIN timeleave.leave_request_component c ON c.assignment_id = u.assignment_id AND c.status IN ('requested','approved','taken')
      JOIN timeleave.leave_request r ON r.leave_request_id = c.leave_request_id AND r.status NOT IN ('declined','cancelled')
                                    AND r.period && tstzrange(u.day::timestamptz, (u.day + 1)::timestamptz)
     GROUP BY u.day),
  head AS (SELECT u.day, count(DISTINCT u.assignment_id) AS n FROM unit u GROUP BY u.day),
  minimum AS (
    SELECT days.day, max(s.min_staff) AS m FROM days
      JOIN timeleave.staffing_level s ON s.org_unit_id = p_org_unit AND s.valid_period @> days.day
                                     AND extract(isodow FROM days.day)::smallint = ANY (s.days_of_week)
     GROUP BY days.day)
  SELECT days.day,
         CASE WHEN EXISTS (SELECT 1 FROM timeleave.blackout_period b WHERE b.org_unit_id = p_org_unit AND b.period @> days.day) THEN 'red'
              WHEN minimum.m IS NULL THEN 'unknown'
              WHEN coalesce(head.n, 0) - coalesce(away.n, 0) - 1 < minimum.m THEN 'red'
              WHEN coalesce(head.n, 0) - coalesce(away.n, 0) - 1 = minimum.m THEN 'amber'
              ELSE 'green' END
    FROM days LEFT JOIN head USING (day) LEFT JOIN away USING (day) LEFT JOIN minimum USING (day)
   ORDER BY days.day
$$;

-- -------------------------------------------------------------------------------------
-- 7. The attendance management program (docs/27 §8.4)
-- -------------------------------------------------------------------------------------
CREATE TABLE timeleave.attendance_program (
  tenant_id  uuid NOT NULL REFERENCES platform.tenant,
  program_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL,
  name_en    text NOT NULL,
  name_fr    text,
  applies_to jsonb NOT NULL,
  stages     jsonb NOT NULL,       -- [{"stageNo":1,"kind":"supportive","absences":4,"periodMonths":6}, ...]
  priority   smallint NOT NULL,
  status     text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT attendance_scope_object CHECK (jsonb_typeof(applies_to) = 'object'),
  CONSTRAINT attendance_stages_list CHECK (jsonb_typeof(stages) = 'array' AND jsonb_array_length(stages) > 0)
);
CREATE TRIGGER attendance_program_scope BEFORE INSERT OR UPDATE OF applies_to ON timeleave.attendance_program
  FOR EACH ROW EXECUTE FUNCTION payroll.check_scope_keys();

CREATE TABLE timeleave.attendance_stage (
  tenant_id        uuid NOT NULL,
  stage_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id    uuid NOT NULL REFERENCES core.employment,
  program_id       uuid NOT NULL REFERENCES timeleave.attendance_program,
  stage_no         smallint NOT NULL CHECK (stage_no >= 1),
  kind             text NOT NULL CHECK (kind IN ('supportive','disciplinary')),
  counted_requests uuid[] NOT NULL,
  accommodation_considered boolean NOT NULL,
  opened_by        uuid NOT NULL REFERENCES platform.app_user,
  opened_at        timestamptz NOT NULL DEFAULT now(),
  hr_reviewed_by   uuid REFERENCES platform.app_user,
  hr_reviewed_at   timestamptz,
  status           text NOT NULL CHECK (status IN ('draft','issued','withdrawn'))
);

CREATE FUNCTION timeleave.check_attendance_stage() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le uuid; bad uuid;
BEGIN
  SELECT e.legal_entity_id INTO le FROM core.employment e WHERE e.employment_id = NEW.employment_id;
  IF NOT (platform.setting(NEW.tenant_id, 'attendance.program_enabled', NEW.opened_at::date, le))::boolean THEN
    RAISE EXCEPTION 'ATTENDANCE_PROGRAM_OFF: the organization has not turned on the attendance program' USING ERRCODE = 'check_violation';
  END IF;
  SELECT x INTO bad FROM unnest(NEW.counted_requests) x
   WHERE NOT EXISTS (SELECT 1 FROM timeleave.leave_request r
                       JOIN timeleave.leave_type lt ON lt.tenant_id = r.tenant_id AND lt.leave_type_code = r.leave_type_code
                       JOIN ref.leave_category c ON c.category = lt.category
                      WHERE r.leave_request_id = x AND r.employment_id = NEW.employment_id
                        AND NOT lt.statutory AND NOT lt.reason_restricted AND NOT c.never_counted_for_attendance
                        AND r.protected_reason IS NULL)
   LIMIT 1;
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'ATTENDANCE_PROTECTED_ABSENCE: absence % is protected (or not this employee''s) and is never counted', bad USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'issued' AND (TG_OP = 'INSERT' OR OLD.status <> 'issued') THEN
    IF NEW.stage_no > 1 AND NOT NEW.accommodation_considered THEN
      RAISE EXCEPTION 'ACCOMMODATION_NOT_CONSIDERED: consider accommodation before moving to stage %', NEW.stage_no USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.kind = 'disciplinary' AND (NEW.hr_reviewed_by IS NULL OR NEW.hr_reviewed_by = NEW.opened_by OR NEW.hr_reviewed_at IS NULL) THEN
      RAISE EXCEPTION 'HR_REVIEW_REQUIRED: HR reviews a disciplinary stage before it is issued' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER attendance_stage_check BEFORE INSERT OR UPDATE ON timeleave.attendance_stage
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_attendance_stage();

-- -------------------------------------------------------------------------------------
-- 8. Scheduling (docs/27 §9)
-- -------------------------------------------------------------------------------------
ALTER TABLE timeleave.shift
  ADD COLUMN published_at timestamptz,
  ADD COLUMN published_by uuid REFERENCES platform.app_user,
  ADD COLUMN notice_hours integer CHECK (notice_hours >= 0);   -- from the agreement or the law, else scheduling.notice_days

-- Offers of extra shifts and overtime, logged with every response (the agreement's order for unionized staff)
CREATE TABLE timeleave.shift_offer (
  tenant_id     uuid NOT NULL,
  offer_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id      uuid NOT NULL REFERENCES timeleave.shift,
  offered_to    uuid NOT NULL REFERENCES core.assignment,
  method        text NOT NULL CHECK (method IN ('manager_choice','open_board','seniority','rotation','equal_hours')),
  rank          smallint,                      -- place in the agreement's order, where it has one
  offered_by    uuid NOT NULL REFERENCES platform.app_user,
  offered_at    timestamptz NOT NULL DEFAULT now(),
  response      text NOT NULL CHECK (response IN ('pending','accepted','declined','no_answer','withdrawn')),
  responded_at  timestamptz,
  CONSTRAINT shift_offer_answered CHECK (response IN ('pending','withdrawn') OR responded_at IS NOT NULL)
);

-- Swaps the employees agree, checked by CanDo and approved by the manager
CREATE TABLE timeleave.shift_swap (
  tenant_id       uuid NOT NULL,
  swap_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id        uuid NOT NULL REFERENCES timeleave.shift,
  from_assignment uuid NOT NULL REFERENCES core.assignment,
  to_assignment   uuid NOT NULL REFERENCES core.assignment,
  requested_by    uuid NOT NULL REFERENCES platform.app_user,
  colleague_agreed_at timestamptz,
  checks          jsonb NOT NULL,             -- eligibility, credentials, overtime and rest, each with its result
  checks_passed   boolean NOT NULL,
  approved_by     uuid REFERENCES platform.app_user,
  approved_at     timestamptz,
  status          text NOT NULL CHECK (status IN ('requested','agreed','approved','declined','cancelled')),
  CONSTRAINT shift_swap_two_people CHECK (from_assignment <> to_assignment)
);
CREATE FUNCTION timeleave.check_shift_swap() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved') THEN
    IF NEW.colleague_agreed_at IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: the colleague agrees to the swap before the manager approves it' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT NEW.checks_passed THEN
      RAISE EXCEPTION 'SHIFT_SWAP_CHECKS_FAILED: %', NEW.checks USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.approved_by IS NULL OR NEW.approved_at IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: the manager who approves the swap' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.approved_by = NEW.requested_by OR NEW.approved_by IS NOT DISTINCT FROM timeleave.employee_user(NEW.to_assignment)
       OR NEW.approved_by IS NOT DISTINCT FROM timeleave.employee_user(NEW.from_assignment) THEN
      RAISE EXCEPTION 'SELF_APPROVAL: the requester cannot approve their own shift swap' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER shift_swap_check BEFORE INSERT OR UPDATE ON timeleave.shift_swap
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_shift_swap();

-- Publishing stops on an unacknowledged rest or hours-limit breach; a change inside the notice needs its caution,
-- except a swap the manager approved (docs/27 §5.1, §9.1, §9.3)
CREATE FUNCTION timeleave.check_shift() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE notice int;
BEGIN
  IF NEW.published AND (TG_OP = 'INSERT' OR NOT OLD.published) THEN
    IF TG_OP = 'UPDATE' AND EXISTS (SELECT 1 FROM timeleave.time_exception x WHERE x.shift_id = NEW.shift_id
                                      AND x.kind IN ('rest_period','hours_limit') AND x.status = 'open') THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: time.rest_or_hours_limit' USING ERRCODE = 'check_violation';
    END IF;
    NEW.published_at := coalesce(NEW.published_at, now());
    IF NEW.notice_hours IS NULL THEN
      NEW.notice_hours := 24 * platform.setting_number(NEW.tenant_id, 'scheduling.notice_days', NEW.starts_at::date)::int;
    END IF;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.published
     AND (NEW.starts_at, NEW.ends_at, NEW.assignment_id, NEW.break_minutes) IS DISTINCT FROM (OLD.starts_at, OLD.ends_at, OLD.assignment_id, OLD.break_minutes) THEN
    notice := coalesce(OLD.notice_hours, 24 * platform.setting_number(OLD.tenant_id, 'scheduling.notice_days', OLD.starts_at::date)::int);
    IF now() > OLD.starts_at - make_interval(hours => notice)
       AND NOT EXISTS (SELECT 1 FROM timeleave.shift_swap s WHERE s.shift_id = OLD.shift_id AND s.status = 'approved'
                         AND s.from_assignment = OLD.assignment_id AND s.to_assignment = NEW.assignment_id
                         AND (NEW.starts_at, NEW.ends_at, NEW.break_minutes) = (OLD.starts_at, OLD.ends_at, OLD.break_minutes))
       AND NOT platform.caution_cleared(OLD.tenant_id, 'time.schedule_changed_late', 'shift', OLD.shift_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: time.schedule_changed_late' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a10_shift_check BEFORE INSERT OR UPDATE ON timeleave.shift
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_shift();

-- -------------------------------------------------------------------------------------
-- 9. Cautions; no self-approval; text fields; row-level security
-- -------------------------------------------------------------------------------------
INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('time.rest_or_hours_limit', 'time', 'Rest period or hours limit not met', 'Période de repos ou limite d''heures non respectée',
  'This schedule or timesheet breaks a rest period or a maximum-hours rule of the law or the collective agreement shown. Go ahead only for a real need, such as an emergency, and state why.',
  'Cet horaire ou cette feuille de temps ne respecte pas une période de repos ou une limite d''heures prévue par la loi ou la convention collective indiquée. Ne poursuivez qu''en cas de besoin réel, par exemple une urgence, et indiquez pourquoi.',
  true, true, 'docs/27 §5.1 (R3.1)'),
 ('time.schedule_changed_late', 'scheduling', 'Schedule changed inside the notice period', 'Horaire modifié pendant la période de préavis',
  'This shift was published and starts within the notice the agreement, the law or the organization requires. Changing it now may give the employee a right to refuse it or to a premium. State why.',
  'Ce quart a été publié et commence pendant le préavis exigé par la convention, la loi ou l''organisation. Le modifier maintenant peut donner à l''employé le droit de le refuser ou à une prime. Indiquez pourquoi.',
  true, true, 'docs/27 §9.1 (R7.1)');

CREATE OR REPLACE FUNCTION platform.check_approval_task() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE requester uuid;
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
  END IF;
  IF NEW.decided_by = requester THEN
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
      ('timeleave','time_exception'), ('timeleave','averaging_arrangement'), ('timeleave','overtime_exemption'),
      ('timeleave','recording_rule'), ('timeleave','leave_plan'), ('timeleave','plan_entry'), ('timeleave','staffing_level'),
      ('timeleave','blackout_period'), ('timeleave','attendance_program'), ('timeleave','attendance_stage'),
      ('timeleave','shift_offer'), ('timeleave','shift_swap')) AS x(s, t) LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$, r.s, r.t);
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT, INSERT and UPDATE on the new tenant tables, SELECT on
-- ref.leave_category, and EXECUTE on the new functions. Leave reasons of protected categories are for HR only
-- (requirements/06 Security); the team availability bar returns levels, never names or counts.
