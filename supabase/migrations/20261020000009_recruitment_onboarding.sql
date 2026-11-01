-- =====================================================================================
-- Migration 0009 · Recruitment and onboarding decisions (docs/23)
--
-- Applies the owner's Module 02 review of 25 October 2026 (claude/review/02-recruitment-onboarding-decisions.md):
-- every route, rule and message is the organization's, starting from CanDo's starter copies, and can be changed
-- later; a user who goes past a caution acknowledges it, and CanDo records who did what (§2).
--
--   §1  Settings for recruitment, offers, onboarding, probation, conversion and cautions
--   §2  Cautions and acknowledgements (the cross-module rule)
--   §3  Approval routes the organization builds; executive capability; no self-approval on routed subjects
--   §4  Employment standards values read from the active edition, strictly
--   §5  Requisitions: content, funding lines, hiring without a posting, approval gate
--   §6  Postings: audience, pay shown, channels, employer questions, incumbent average
--   §7  Candidates and applications: contact, decisions by people only, retention, interviews, messages
--   §8  Offers: routes, conditional offers and checks, changed terms, the hire after the contract is signed
--   §9  Pre-boarding and onboarding: plans by kind and scope, tasks with legal due dates, s. 87, supporters
--   §10 Probation: check-ins, reminders, the end date passing (FB-034), extensions, leave near the end
--   §11 Open cases before an ending: case parties, new case categories, the change-set gate
--   §12 Status conversion
--   §13 Text fields registered as translatable; column defaults from settings; row-level security
--   §14 Starter data: posting channels, routes, onboarding plans; seeding of every organization
--
-- Run after 0008. Every new business column that needs a default takes it from a setting (platform.column_default);
-- columns with legal or pay effect have none. Errors are named; nothing falls back silently (AGENTS rules 43 and 44).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/23 §2.3). decided: chosen by the owner in the review; pending: no CanDo default, each
--    organization chooses at setup (platform.setting raises SETTING_NOT_SET until it does).
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('recruit.direct_hire', 'recruitment', 'text', '["allowed_with_route","not_allowed"]', '"allowed_with_route"', ARRAY['tenant','legal_entity'], false,
  'Hiring without a requisition: allowed only through the organization''s direct-hire approval route, or not allowed.',
  'docs/23 §3.1 (R2.7)', 'decided', NULL, NULL, NULL),
 ('recruit.posting_default', 'recruitment', 'text', '["required","optional"]', '"required"', ARRAY['tenant','legal_entity'], false,
  'Whether a requisition needs a posting unless one of the organization''s posting exemption rules applies (a named candidate, the talent pool, extra duties for a current employee, on-call staff).',
  'docs/23 §3.3 (R2.8)', 'decided', NULL, NULL, NULL),
 ('recruit.screening_owner', 'recruitment', 'text', '["hr","department","both"]', NULL, ARRAY['tenant','legal_entity'], false,
  'Who screens applicants and sees them first: HR, the hiring department, or both. No CanDo default.',
  'docs/23 §4.6 (R1.5)', 'pending', NULL, NULL, NULL),
 ('recruit.ai_match', 'recruitment', 'json', NULL, '{"enabled":false}', ARRAY['tenant'], false,
  'AI match suggestions, with criteria and weights the employer sets on each posting. Off until the organization switches them on. AI never rejects or advances a candidate.',
  'docs/23 §4.6 (R1.4)', 'decided', NULL, NULL, ARRAY['enabled']),
 ('recruit.missing_requirement', 'recruitment', 'text', '["flag","screen_out"]', NULL, ARRAY['tenant','legal_entity'], false,
  'Starting choice for a new posting when a candidate lacks a required certification or qualification: flag for a person to decide, or screen out. Chosen again on each posting.',
  'docs/23 §4.6 (R2.5)', 'pending', NULL, NULL, NULL),
 ('recruit.posting_audience', 'recruitment', 'text', '["internal_and_public","internal_first","internal_only","public_only"]', '"internal_and_public"', ARRAY['tenant','legal_entity'], false,
  'Starting audience of a new posting; chosen again on each posting. Internal-first postings state their internal days (or take them from the agreement).',
  'docs/23 §4.1 (R3.1)', 'decided', NULL, NULL, NULL),
 ('recruit.posting_pay_shown', 'recruitment', 'boolean', NULL, 'true', ARRAY['tenant','legal_entity'], false,
  'Pay is shown on new postings. The employer can remove it only where the law of the posting''s jurisdiction allows.',
  'docs/23 §4.2 (R3.2)', 'decided', NULL, NULL, NULL),
 ('recruit.posting_pay_basis', 'recruitment', 'text', '["range","incumbent_average","market_point","other"]', '"range"', ARRAY['tenant','legal_entity'], false,
  'What a new posting shows as pay: a range, the average of current incumbents, a market point (for example the 75th percentile) or another value, within the province''s rules.',
  'docs/23 §4.2 (R3.2)', 'decided', NULL, NULL, NULL),
 ('recruit.incumbent_average_min', 'recruitment', 'integer', NULL, '3', ARRAY['tenant'], false,
  'Fewest current incumbents for a posting to show their average pay. Cannot be set below 3, so no one''s own pay can be worked out from a posting.',
  'docs/23 §4.2 (R3.6)', 'decided', 3, NULL, NULL),
 ('recruit.apply_agreement_seniority', 'recruitment', 'boolean', NULL, 'true', ARRAY['tenant','legal_entity'], false,
  'CanDo applies the collective agreement''s seniority order in selection. The organization can switch it off, or override it on a posting with a written reason.',
  'docs/23 §4.3 (R3.3, R3.7)', 'decided', NULL, NULL, NULL),
 ('recruit.applicant_contact', 'recruitment', 'text', '["email_or_phone","email","phone","email_and_phone"]', '"email_or_phone"', ARRAY['tenant'], false,
  'Contact details a candidate must give to apply without an account.',
  'docs/23 §4.4 (R4.1)', 'decided', NULL, NULL, NULL),
 ('recruit.candidate_retention', 'recruitment', 'json', NULL, NULL, ARRAY['tenant'], false,
  'How long candidate records are kept, never less than the law: mode per_province (the law of the posting''s jurisdiction) or longest_for_all (the longest of every jurisdiction where the organization has a location); organizationMonths: the organization''s own minimum after the decision. No CanDo default.',
  'docs/23 §4.5 (R4.2)', 'pending', NULL, NULL, ARRAY['mode','organizationMonths']),
 ('recruit.interview_scoring', 'recruitment', 'text', '["every_interview","optional"]', NULL, ARRAY['tenant','legal_entity'], false,
  'Whether every interview is scored with the posting''s kit before a decision, or scoring is optional. No CanDo default.',
  'docs/23 §4.7 (R4.3)', 'pending', NULL, NULL, NULL),
 ('recruit.blind_screening', 'recruitment', 'boolean', NULL, 'false', ARRAY['tenant','legal_entity'], false,
  'Blind screening hides names, photos and other identifying details from screeners. Off until the organization turns it on.',
  'docs/23 §4.6 (R4.4)', 'decided', NULL, NULL, NULL),
 ('offers.default_expiry', 'offers', 'json', NULL, '{"amount":5,"unit":"working_days"}', ARRAY['tenant','legal_entity'], false,
  'Default time an offer stays open: amount and unit (working_days or calendar_days). Pre-filled at setup; HR or the offering manager can change it on each offer.',
  'docs/23 §5.2 (R5.3, Q46)', 'decided', NULL, NULL, ARRAY['amount','unit']),
 ('offers.expiry_changed_by', 'offers', 'text_array', NULL, '["hr","offering_manager"]', ARRAY['tenant'], false,
  'Who can change the expiry on a single offer.',
  'docs/23 §5.2 (R5.3)', 'decided', NULL, NULL, NULL),
 ('offers.reapprove_on_change', 'offers', 'text', '["any_change","pay_or_start_changed","none"]', '"any_change"', ARRAY['tenant','legal_entity'], false,
  'Which changes to approved offer terms go back through the offer route: any change (CanDo default), only a higher pay rate or a different start date, or none.',
  'docs/23 §5.4 (R5.5)', 'decided', NULL, NULL, NULL),
 ('onboarding.escalation', 'onboarding', 'json', NULL, '{"hrAfterDaysOverdue":3,"managerAfterDaysOverdue":1,"ownerReminderDaysBefore":2}', ARRAY['tenant','legal_entity'], false,
  'Overdue onboarding tasks: the owner is reminded ownerReminderDaysBefore days before the due date, then the owner''s manager is told managerAfterDaysOverdue days after it, then HR hrAfterDaysOverdue days after it. Pre-filled at setup; each organization can change them.',
  'docs/23 §6.4 (R6.4, Q46)', 'decided', NULL, NULL, ARRAY['hrAfterDaysOverdue','managerAfterDaysOverdue','ownerReminderDaysBefore']),
 ('onboarding.extras', 'onboarding', 'json', NULL,
  '{"buddyProgram":{"enabled":false,"required":false},"checkInSurveys":{"enabled":false,"required":false,"days":[]},"culturalTrack":{"enabled":false,"required":false},"welcomeVideos":{"enabled":false,"required":false}}',
  ARRAY['tenant','legal_entity'], false,
  'Optional onboarding pieces: welcome videos, check-in surveys (on the days the organization sets), an Indigenous and culturally aligned track, and the buddy program. Each stays off until the organization turns it on and says whether it is required.',
  'docs/23 §6.6 (R6.6)', 'decided', NULL, NULL, ARRAY['buddyProgram','checkInSurveys','culturalTrack','welcomeVideos']),
 ('probation.check_ins', 'probation', 'json', NULL,
  '{"default":[{"from":"start","days":30},{"from":"start","days":60},{"from":"end","days":14}]}', ARRAY['tenant','legal_entity'], false,
  'Check-ins during probation, counted from the start or back from the end. "default" applies to every probation; the keys employer, agreement and trial replace it for that kind. An agreement''s own schedule wins for its probations.',
  'docs/23 §7.1 (R7.1)', 'decided', NULL, NULL, ARRAY['default']),
 ('probation.end_reminders_days', 'probation', 'integer_array', NULL, '[30,15,10,5,3,2,1]', ARRAY['tenant','legal_entity'], false,
  'Days before the end of a probation when the manager and HR are reminded that a decision is due. The largest number also opens the window in which a leave request shows a caution.',
  'docs/23 §7.2 (R7.2)', 'decided', NULL, NULL, NULL),
 ('probation.non_union_extension_max', 'probation', 'json', NULL, '{"amount":null,"measure":"calendar_months"}', ARRAY['tenant','legal_entity'], false,
  'Longest total extension of an employer or non-union trial probation, in the probation''s own measure; amount null means the organization sets no maximum. Union probations use the agreement''s maximum.',
  'docs/23 §7.4 (R7.3)', 'decided', NULL, NULL, ARRAY['amount','measure']),
 ('probation.confirmation_letter', 'probation', 'text', '["hr_sends","send_automatically","off"]', '"hr_sends"', ARRAY['tenant','legal_entity'], false,
  'When probation is passed CanDo prepares a confirmation letter from the organization''s template: HR sends it, CanDo sends it automatically, or no letter.',
  'docs/23 §7.6 (R7.6)', 'decided', NULL, NULL, NULL),
 ('conversion.thresholds', 'probation', 'json', NULL, '{"enabled":false,"rules":[]}', ARRAY['tenant','legal_entity'], false,
  'Thresholds at which CanDo flags temporary, casual or auxiliary staff for conversion to regular (for example 12 months of regular hours). Off by default: conversions start when a manager asks. Conversions a collective agreement requires are always flagged to HR.',
  'docs/23 §8 (R7.5)', 'decided', NULL, NULL, ARRAY['enabled','rules']),
 ('cautions.reason_required', 'cautions', 'text_array', NULL, '[]', ARRAY['tenant'], false,
  'Caution codes for which the organization also asks a written reason when a user goes past them. Cautions CanDo marks reason_always need one whatever this says.',
  'docs/23 §2.1 (X1)', 'decided', NULL, NULL, NULL),
 ('cautions.approval_required', 'cautions', 'text_array', NULL, '[]', ARRAY['tenant'], false,
  'Caution codes for which going past the caution also needs an approval, through the organization''s caution route.',
  'docs/23 §2.1 (X1)', 'decided', NULL, NULL, NULL),
 ('endings.open_case_review', 'endings', 'boolean', NULL, 'true', ARRAY['tenant'], true,
  'Before probation is failed or employment ends, any open or recently closed case or leave of the employee is reviewed by HR, who acknowledges it (legal protection; cannot be switched off).',
  'docs/23 §7.5 (R7.4)', 'decided', NULL, NULL, NULL),
 ('endings.closed_case_lookback_months', 'endings', 'integer', NULL, '12', ARRAY['tenant','legal_entity'], false,
  'Cases closed within this many months before the ending date also need HR''s review, since protection against reprisal can outlast a case.',
  'docs/23 §7.5 (Q47)', 'decided', 0, NULL, NULL);

-- -------------------------------------------------------------------------------------
-- 2. Cautions and acknowledgements (docs/23 §2.1). A caution tells the user what they are about to go past
--    (a rule, the law, an agreement). Going past it is recorded with what was shown, by whom, when, and the reason.
-- -------------------------------------------------------------------------------------
CREATE TABLE ref.caution (
  caution_code  text PRIMARY KEY,
  area          text NOT NULL,
  name_en       text NOT NULL,
  name_fr       text NOT NULL,
  message_en    text NOT NULL,
  message_fr    text NOT NULL,
  reason_always boolean NOT NULL,          -- a written reason is needed whatever the organization sets
  shows_law     boolean NOT NULL,          -- the message states what the law or the agreement requires
  decision_ref  text NOT NULL
);

INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('recruit.seniority_order_overridden', 'recruitment', 'Seniority order overridden', 'Ordre d''ancienneté écarté',
  'The collective agreement ranks these candidates by seniority. You are choosing a different order.',
  'La convention collective classe ces candidats selon l''ancienneté. Vous choisissez un autre ordre.', true, true, 'docs/23 §4.3 (R3.7)'),
 ('recruit.posting_skipped_where_required', 'recruitment', 'No posting where one is required', 'Aucun affichage alors qu''il est exigé',
  'A collective agreement or a policy requires this position to be posted. You are filling it without a posting.',
  'Une convention collective ou une politique exige l''affichage de ce poste. Vous le pourvoyez sans affichage.', true, true, 'docs/23 §3.3 (R2.8)'),
 ('recruit.missing_requirement_advanced', 'recruitment', 'Candidate without a required qualification', 'Candidat sans une qualification exigée',
  'This candidate has not shown a qualification the requisition requires. You are moving them forward.',
  'Ce candidat n''a pas démontré une qualification exigée par la demande. Vous le faites avancer.', false, false, 'docs/23 §4.6 (R2.5)'),
 ('probation.leave_near_end', 'probation', 'Leave near the end of probation', 'Congé près de la fin du stage',
  'This leave falls in the last days of a probation, when a decision is due. The agreement may extend the probation by the leave.',
  'Ce congé tombe dans les derniers jours d''un stage, au moment où une décision est attendue. La convention peut prolonger le stage de la durée du congé.', false, true, 'docs/23 §7.3 (R7.2)'),
 ('probation.extension_past_notice_threshold', 'probation', 'Extension past the law''s notice threshold', 'Prolongation au-delà du seuil de préavis prévu par la loi',
  'Extending probation does not delay the law''s notice rights. After this date the employee is owed notice or pay in lieu under employment standards, whatever the probation says.',
  'La prolongation du stage ne retarde pas les droits au préavis prévus par la loi. Après cette date, l''employé a droit au préavis ou à une indemnité selon les normes du travail, quoi qu''en dise le stage.', false, true, 'docs/23 §7.4 (R7.3)'),
 ('endings.open_cases', 'endings', 'Open cases before an ending', 'Dossiers ouverts avant une fin d''emploi',
  'This employee has an open or recently closed case, or a leave (for example an accommodation, a claim, a grievance, an investigation or a complaint). Ending employment now may breach the law. HR must review before going ahead.',
  'Cet employé a un dossier ouvert ou fermé récemment, ou un congé (par exemple une mesure d''adaptation, une réclamation, un grief, une enquête ou une plainte). Mettre fin à l''emploi maintenant pourrait enfreindre la loi. Les RH doivent examiner la situation avant d''aller plus loin.', true, true, 'docs/23 §7.5 (R7.4, Q47)'),
 ('conversion.agreement_requires', 'conversion', 'Conversion the agreement requires', 'Conversion exigée par la convention',
  'The collective agreement requires this employee to be converted to regular status. You are declining or delaying it.',
  'La convention collective exige que cet employé devienne régulier. Vous refusez ou retardez la conversion.', true, true, 'docs/23 §8 (R7.5)');

CREATE TABLE platform.caution_acknowledgement (
  tenant_id        uuid NOT NULL REFERENCES platform.tenant,
  ack_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  caution_code     text NOT NULL REFERENCES ref.caution,
  subject_type     text NOT NULL,                        -- requisition | application | offer | probation_extension | change_set | status_conversion | leave_request | ...
  subject_id       uuid NOT NULL,
  shown_text       text NOT NULL,                        -- the caution exactly as the user saw it
  shown_lang       text NOT NULL REFERENCES ref.language,
  acknowledged_by  uuid NOT NULL REFERENCES platform.app_user,
  acknowledged_at  timestamptz NOT NULL DEFAULT now(),
  reason           text,
  approval_task_id uuid REFERENCES platform.approval_task,
  CONSTRAINT caution_ack_reason_not_blank CHECK (reason IS NULL OR length(btrim(reason)) > 0)
);
CREATE INDEX caution_ack_subject ON platform.caution_acknowledgement (tenant_id, subject_type, subject_id, caution_code);

CREATE FUNCTION platform.check_caution_acknowledgement() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c ref.caution;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'CAUTION_ACK_IMMUTABLE: an acknowledgement is part of the audit trail' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.approval_task_id IS NULL AND NEW.approval_task_id IS NOT NULL
       AND (to_jsonb(NEW) - 'approval_task_id') = (to_jsonb(OLD) - 'approval_task_id') THEN
      RETURN NEW;                                            -- the approval it needed is attached once
    END IF;
    RAISE EXCEPTION 'CAUTION_ACK_IMMUTABLE: an acknowledgement is part of the audit trail' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO c FROM ref.caution WHERE caution_code = NEW.caution_code;
  IF NEW.reason IS NULL AND (c.reason_always
       OR platform.setting(NEW.tenant_id, 'cautions.reason_required', NEW.acknowledged_at::date) ? NEW.caution_code) THEN
    RAISE EXCEPTION 'CAUTION_REASON_REQUIRED: % needs a written reason', NEW.caution_code USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER caution_acknowledgement_check BEFORE INSERT OR UPDATE OR DELETE ON platform.caution_acknowledgement
  FOR EACH ROW EXECUTE FUNCTION platform.check_caution_acknowledgement();

-- Whether a user has gone past a caution on a subject as the organization requires: acknowledged (with a reason where
-- one is needed, checked on insert) and, where the organization asks for it, approved by someone else.
CREATE FUNCTION platform.caution_cleared(p_tenant uuid, p_code text, p_subject_type text, p_subject_id uuid) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM platform.caution_acknowledgement a
     WHERE a.tenant_id = p_tenant AND a.caution_code = p_code AND a.subject_type = p_subject_type AND a.subject_id = p_subject_id
       AND (NOT (platform.setting(p_tenant, 'cautions.approval_required', a.acknowledged_at::date) ? p_code)
            OR EXISTS (SELECT 1 FROM platform.approval_task t
                        WHERE t.task_id = a.approval_task_id AND t.status = 'approved'
                          AND t.decided_by IS NOT NULL AND t.decided_by <> a.acknowledged_by)))
$$;

-- -------------------------------------------------------------------------------------
-- 3. Approval routes the organization builds (docs/23 §2.2). Each subject picks the first active route, by
--    priority, whose conditions match the subject's facts; a missing fact or no matching route is an error.
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.approval_task DROP CONSTRAINT IF EXISTS approval_task_capability_check;
ALTER TABLE platform.approval_task ADD CONSTRAINT approval_task_capability_check
  CHECK (capability IN ('manager','hr','payroll','finance','labour_relations','executive','other'));

CREATE TABLE platform.workflow_route (
  tenant_id    uuid NOT NULL REFERENCES platform.tenant,
  route_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL,
  subject_type text NOT NULL CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution')),
  name_en      text NOT NULL,
  name_fr      text,
  conditions   jsonb NOT NULL,                            -- {} matches every subject of the type
  priority     smallint NOT NULL,
  status       text NOT NULL CHECK (status IN ('active','retired')),
  starter_code text,                                      -- the CanDo starter route it was copied from, if any
  UNIQUE (tenant_id, code),
  CONSTRAINT workflow_route_conditions_object CHECK (jsonb_typeof(conditions) = 'object')
);
CREATE UNIQUE INDEX workflow_route_priority ON platform.workflow_route (tenant_id, subject_type, priority) WHERE status = 'active';

CREATE TABLE platform.workflow_route_step (
  tenant_id     uuid NOT NULL,
  route_id      uuid NOT NULL REFERENCES platform.workflow_route ON DELETE CASCADE,
  step_no       smallint NOT NULL CHECK (step_no >= 1),
  approver_kind text NOT NULL CHECK (approver_kind IN ('hiring_manager','requester_manager','unit_head','capability','role','user')),
  capability    text CHECK (capability IN ('manager','hr','payroll','finance','labour_relations','executive','other')),
  role_code     text,
  user_id       uuid REFERENCES platform.app_user,
  mode          text NOT NULL CHECK (mode IN ('any','all')),   -- any: min_approvals people; all: every task of the step
  min_approvals smallint NOT NULL CHECK (min_approvals >= 1),
  purpose_en    text,
  purpose_fr    text,
  PRIMARY KEY (route_id, step_no),
  CONSTRAINT route_step_capability CHECK ((approver_kind = 'capability') = (capability IS NOT NULL)),
  CONSTRAINT route_step_role CHECK ((approver_kind = 'role') = (role_code IS NOT NULL)),
  CONSTRAINT route_step_user CHECK ((approver_kind = 'user') = (user_id IS NOT NULL))
);

-- Condition keys a route may use, and the fact each one reads
CREATE FUNCTION platform.route_condition_fact(p_key text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
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
         END
$$;

CREATE FUNCTION platform.check_workflow_route() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(NEW.conditions) LOOP
    IF platform.route_condition_fact(k) IS NULL THEN
      RAISE EXCEPTION 'ROUTE_CONDITION_UNKNOWN: % is not a route condition', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER workflow_route_check BEFORE INSERT OR UPDATE OF conditions ON platform.workflow_route
  FOR EACH ROW EXECUTE FUNCTION platform.check_workflow_route();

CREATE FUNCTION platform.route_matches(p_conditions jsonb, p_facts jsonb) RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE k text; v jsonb; f jsonb;
BEGIN
  FOR k, v IN SELECT * FROM jsonb_each(p_conditions) LOOP
    f := p_facts -> platform.route_condition_fact(k);
    IF f IS NULL OR jsonb_typeof(f) = 'null' THEN
      RAISE EXCEPTION 'ROUTE_FACT_MISSING: % is needed to choose a route', platform.route_condition_fact(k) USING ERRCODE = 'check_violation';
    END IF;
    IF k = 'minAnnualCost' THEN
      IF (f #>> '{}')::numeric < (v #>> '{}')::numeric THEN RETURN false; END IF;
    ELSIF jsonb_typeof(v) = 'array' THEN
      IF NOT (v @> jsonb_build_array(f)) THEN RETURN false; END IF;
    ELSIF v <> f THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN true;
END $$;

CREATE FUNCTION platform.route_for(p_tenant uuid, p_subject_type text, p_facts jsonb) RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT route_id, conditions FROM platform.workflow_route
            WHERE tenant_id = p_tenant AND subject_type = p_subject_type AND status = 'active' ORDER BY priority LOOP
    IF platform.route_matches(r.conditions, p_facts) THEN RETURN r.route_id; END IF;
  END LOOP;
  RAISE EXCEPTION 'ROUTE_NOT_FOUND: no active % route matches %', p_subject_type, p_facts USING ERRCODE = 'check_violation';
END $$;

-- A route is complete when every step has its approvals from people other than the requester, no task of the
-- subject is rejected, and (for a re-approval) the approvals were given after p_decided_after.
CREATE FUNCTION platform.route_complete(p_route uuid, p_subject_type text, p_subject_id uuid, p_requester uuid, p_decided_after timestamptz)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (SELECT 1 FROM platform.approval_task t
                      WHERE t.subject_type = p_subject_type AND t.subject_id = p_subject_id AND t.status = 'rejected'
                        AND (p_decided_after IS NULL OR t.decided_at > p_decided_after))
     AND NOT EXISTS (
       SELECT 1 FROM platform.workflow_route_step s
        WHERE s.route_id = p_route
          AND ((SELECT count(DISTINCT t.decided_by) FROM platform.approval_task t
                 WHERE t.subject_type = p_subject_type AND t.subject_id = p_subject_id AND t.step = s.step_no
                   AND t.status = 'approved' AND t.decided_by IS NOT NULL AND t.decided_by IS DISTINCT FROM p_requester
                   AND (p_decided_after IS NULL OR t.decided_at > p_decided_after)) < s.min_approvals
               OR (s.mode = 'all' AND EXISTS (SELECT 1 FROM platform.approval_task t
                     WHERE t.subject_type = p_subject_type AND t.subject_id = p_subject_id AND t.step = s.step_no
                       AND t.status = 'open'))))
$$;

-- -------------------------------------------------------------------------------------
-- 4. Employment standards values, read from the active edition (rules/employment-standards, merged with the
--    additions files in Step 7). p_jurisdiction NULL reads the rules that apply to every employer in Canada.
-- -------------------------------------------------------------------------------------
CREATE FUNCTION ref.employment_standard(p_jurisdiction text, p_key text, p_on date) RETURNS jsonb
LANGUAGE plpgsql STABLE AS $$
DECLARE c jsonb; v jsonb;
BEGIN
  SELECT content INTO c FROM ref.rule_edition
   WHERE family = 'employment_standards' AND status = 'active' AND p_on BETWEEN effective_from AND effective_to;
  IF c IS NULL THEN
    RAISE EXCEPTION 'JURISDICTION_RULE_MISSING: no active employment standards edition on %', p_on USING ERRCODE = 'check_violation';
  END IF;
  v := CASE WHEN p_jurisdiction IS NULL THEN c -> 'nationwide' -> p_key ELSE c -> 'jurisdictions' -> p_jurisdiction -> p_key END;
  IF v IS NULL OR jsonb_typeof(v) = 'null' THEN
    RAISE EXCEPTION 'JURISDICTION_RULE_MISSING: % has no % rule on %', coalesce(p_jurisdiction, 'nationwide'), p_key, p_on
      USING ERRCODE = 'check_violation';
  END IF;
  IF v ->> 'status' = 'verify_at_load' THEN
    RAISE EXCEPTION 'RULE_NOT_VERIFIED: % % is still marked verify_at_load', coalesce(p_jurisdiction, 'nationwide'), p_key
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN v;
END $$;

-- The last day before the law's first notice band applies (for example 3 months in Ontario): extending probation
-- past it does not delay the employee's notice rights.
CREATE FUNCTION ref.notice_threshold_date(p_jurisdiction text, p_started_on date) RETURNS date LANGUAGE plpgsql STABLE AS $$
DECLARE r jsonb; b jsonb; d date;
BEGIN
  r := ref.employment_standard(p_jurisdiction, 'termination_notice', p_started_on);
  b := r -> 'bands' -> 0;
  d := CASE
         WHEN b ? 'from_months' THEN (p_started_on + make_interval(months => (b ->> 'from_months')::int))::date
         WHEN b ? 'from_weeks'  THEN (p_started_on + make_interval(weeks  => (b ->> 'from_weeks')::int))::date
         WHEN b ? 'from_days'   THEN (p_started_on + make_interval(days   => (b ->> 'from_days')::int))::date
         WHEN b ? 'from_years'  THEN (p_started_on + make_interval(years  => (b ->> 'from_years')::int))::date
       END;
  IF d IS NULL THEN
    RAISE EXCEPTION 'JURISDICTION_RULE_MISSING: % termination_notice has no first band to count from', p_jurisdiction
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN d - 1;
END $$;

-- -------------------------------------------------------------------------------------
-- 5. Requisitions (docs/23 §3): what the hire is, how it is funded, whether it is posted, and its approval route
-- -------------------------------------------------------------------------------------
ALTER TABLE recruit.requisition
  ADD COLUMN requested_by           uuid REFERENCES platform.app_user,
  ADD COLUMN hiring_manager_user    uuid REFERENCES platform.app_user,
  ADD COLUMN employment_type        text,                       -- the organization's employment type (list employment_type)
  ADD COLUMN fte                    numeric(6,4) CHECK (fte > 0),
  ADD COLUMN target_start           date,
  ADD COLUMN end_date               date,                       -- term, fixed-term, seasonal and student hires; empty for ongoing work
  ADD COLUMN replaces_employment_id uuid REFERENCES core.employment,
  ADD COLUMN posting_exemption_code text,                       -- recruit.posting_exemption_rule; empty when the position is posted
  ADD COLUMN posting_required_by    text[] NOT NULL DEFAULT '{}', -- agreements or policies found to require a posting (set on submission)
  ADD COLUMN route_id               uuid REFERENCES platform.workflow_route,
  ADD CONSTRAINT requisition_dates CHECK (end_date IS NULL OR target_start IS NULL OR end_date >= target_start);

DROP TRIGGER a01_list_values ON recruit.requisition;
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON recruit.requisition
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('requisition_type', 'requisition_type', 'employment_type', 'employment_type');

-- Budget coding: cost centres and funding sources with their shares (docs/17 §8); one position can have several funders
CREATE TABLE recruit.requisition_funding (
  tenant_id         uuid NOT NULL,
  requisition_id    uuid NOT NULL REFERENCES recruit.requisition ON DELETE CASCADE,
  line_no           smallint NOT NULL CHECK (line_no >= 1),
  funding_source_id uuid REFERENCES finance.funding_source,
  segments          jsonb NOT NULL,                          -- GL segment codes (finance.segment_definition), e.g. {"cost_centre":"4410"}
  share_percent     numeric(7,4) NOT NULL CHECK (share_percent > 0 AND share_percent <= 100),
  PRIMARY KEY (requisition_id, line_no),
  CONSTRAINT requisition_funding_segments_object CHECK (jsonb_typeof(segments) = 'object')
);

-- The organization's own rules for filling a position without a posting (docs/23 §3.3)
CREATE TABLE recruit.posting_exemption_rule (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  code        text NOT NULL,
  category    text NOT NULL CHECK (category IN ('named_candidate','talent_pool','extra_duties','on_call','other')),
  name_en     text NOT NULL,
  name_fr     text,
  employment_type_categories text[],                          -- limits the rule to these employment type categories; empty: any
  status      text NOT NULL CHECK (status IN ('active','retired')),
  PRIMARY KEY (tenant_id, code)
);

CREATE FUNCTION recruit.check_requisition() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE total numeric; n int;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status = 'pending_approval' THEN
    IF NEW.requested_by IS NULL OR NEW.employment_type IS NULL OR NEW.route_id IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a requisition is submitted with its requester, employment type and approval route'
        USING ERRCODE = 'check_violation';
    END IF;
    SELECT count(*), coalesce(sum(share_percent), 0) INTO n, total FROM recruit.requisition_funding WHERE requisition_id = NEW.requisition_id;
    IF n = 0 THEN
      RAISE EXCEPTION 'REQUISITION_FUNDING_MISSING: a requisition names its cost centre or funding sources' USING ERRCODE = 'check_violation';
    END IF;
    IF total <> 100 THEN
      RAISE EXCEPTION 'REQUISITION_FUNDING_NOT_100: funding shares add up to %', total USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.posting_exemption_code IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM recruit.posting_exemption_rule r
          WHERE r.tenant_id = NEW.tenant_id AND r.code = NEW.posting_exemption_code AND r.status = 'active') THEN
      RAISE EXCEPTION 'POSTING_EXEMPTION_UNKNOWN: % is not an active posting exemption rule', NEW.posting_exemption_code
        USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.status = 'approved' THEN
    IF NOT platform.route_complete(NEW.route_id, 'requisition', NEW.requisition_id, NEW.requested_by, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the requisition''s route is not complete' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.posting_exemption_code IS NOT NULL AND cardinality(NEW.posting_required_by) > 0
       AND NOT platform.caution_cleared(NEW.tenant_id, 'recruit.posting_skipped_where_required', 'requisition', NEW.requisition_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: % require a posting; recruit.posting_skipped_where_required must be acknowledged',
        NEW.posting_required_by USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER requisition_check BEFORE UPDATE OF status ON recruit.requisition
  FOR EACH ROW EXECUTE FUNCTION recruit.check_requisition();

-- -------------------------------------------------------------------------------------
-- 6. Postings (docs/23 §4.1 to §4.3)
-- -------------------------------------------------------------------------------------
CREATE TABLE recruit.posting (
  tenant_id           uuid NOT NULL REFERENCES platform.tenant,
  posting_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requisition_id      uuid NOT NULL REFERENCES recruit.requisition,
  legal_entity_id     uuid NOT NULL REFERENCES core.legal_entity,  -- the employer posting it; per-employer settings fill the starting values
  audience            text NOT NULL CHECK (audience IN ('internal_and_public','internal_first','internal_only','public_only')),
  internal_days       smallint CHECK (internal_days > 0),        -- internal-first: days before it goes public
  title               text NOT NULL,                             -- core.position_title_for(.., 'posting', .., lang)
  lang                text NOT NULL REFERENCES ref.language,
  pay_shown           boolean NOT NULL,
  pay_basis           text NOT NULL CHECK (pay_basis IN ('range','incumbent_average','market_point','other')),
  pay_min             numeric(14,2),
  pay_max             numeric(14,2),
  pay_point           numeric(14,2),
  pay_unit            text CHECK (pay_unit IN ('hour','day','week','month','year')),
  pay_text            text,
  missing_requirement text NOT NULL CHECK (missing_requirement IN ('flag','screen_out')),
  seniority_applies   boolean NOT NULL,
  ai_notice_included  boolean NOT NULL,                          -- stated by the posting validator from the jurisdiction's rules
  opens_on            date,
  closes_on           date,
  status              text NOT NULL CHECK (status IN ('draft','published','closed','cancelled')),
  published_by        uuid REFERENCES platform.app_user,
  CONSTRAINT posting_internal_first_days CHECK (audience <> 'internal_first' OR internal_days IS NOT NULL),
  CONSTRAINT posting_pay_range CHECK (pay_max IS NULL OR pay_min IS NULL OR pay_max >= pay_min),
  CONSTRAINT posting_dates CHECK (closes_on IS NULL OR opens_on IS NULL OR closes_on >= opens_on)
);

-- Current incumbents of the requisition's job on a date (for "average of current incumbents")
CREATE FUNCTION recruit.incumbent_count(p_requisition uuid, p_as_of date) RETURNS int LANGUAGE sql STABLE AS $$
  SELECT count(DISTINCT av.assignment_id)::int
    FROM recruit.requisition r
    JOIN core.position_version pv0 ON pv0.position_id = r.position_id AND pv0.valid_period @> p_as_of AND upper_inf(pv0.sys_period)
    JOIN core.position_version pv  ON pv.tenant_id = pv0.tenant_id AND pv.job_id = pv0.job_id
                                  AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
    JOIN core.assignment_version av ON av.position_id = pv.position_id AND av.valid_period @> p_as_of
                                   AND upper_inf(av.sys_period) AND av.status <> 'ended'
   WHERE r.requisition_id = p_requisition
$$;

CREATE FUNCTION recruit.check_posting() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE req recruit.requisition; n int; need int;
BEGIN
  IF NEW.status = 'published' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'published') THEN
    SELECT * INTO req FROM recruit.requisition WHERE requisition_id = NEW.requisition_id;
    IF req.status NOT IN ('approved','posted') THEN
      RAISE EXCEPTION 'POSTING_REQUISITION_NOT_APPROVED: requisition % is %', req.number, req.status USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.published_by IS NULL OR NEW.opens_on IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a published posting names who published it and when it opens' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.pay_shown AND NEW.pay_basis = 'incumbent_average' THEN
      n := recruit.incumbent_count(NEW.requisition_id, NEW.opens_on);
      need := platform.setting_number(NEW.tenant_id, 'recruit.incumbent_average_min', NEW.opens_on)::int;
      IF n < need THEN
        RAISE EXCEPTION 'INCUMBENT_AVERAGE_UNAVAILABLE: % current incumbents; at least % are needed to show their average', n, need
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    IF NEW.pay_shown AND NEW.pay_basis = 'range' AND (NEW.pay_min IS NULL OR NEW.pay_max IS NULL OR NEW.pay_unit IS NULL) THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a posting that shows a range states its minimum, maximum and unit' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER posting_check BEFORE INSERT OR UPDATE ON recruit.posting
  FOR EACH ROW EXECUTE FUNCTION recruit.check_posting();

-- Where the posting goes: the organization's channels (partner job boards, its career page, Google, Indeed's free
-- listings, professional and regulatory bodies)
CREATE TABLE recruit.posting_channel (
  tenant_id    uuid NOT NULL,
  posting_id   uuid NOT NULL REFERENCES recruit.posting ON DELETE CASCADE,
  channel_code text NOT NULL,                                -- the organization's posting_channel list
  external_ref text,
  published_at timestamptz,
  withdrawn_at timestamptz,
  PRIMARY KEY (posting_id, channel_code)
);
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON recruit.posting_channel
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('channel_code', 'posting_channel');

-- The employer's own questions, each optional or mandatory
CREATE TABLE recruit.posting_question (
  tenant_id  uuid NOT NULL,
  posting_id uuid NOT NULL REFERENCES recruit.posting ON DELETE CASCADE,
  seq        smallint NOT NULL CHECK (seq >= 1),
  kind       text NOT NULL CHECK (kind IN ('multiple_choice','yes_no','date','number','text')),
  required   boolean NOT NULL,
  text_en    text NOT NULL,
  text_fr    text,
  options    jsonb,
  PRIMARY KEY (posting_id, seq),
  CONSTRAINT posting_question_options CHECK ((kind = 'multiple_choice') = (options IS NOT NULL))
);

-- -------------------------------------------------------------------------------------
-- 7. Candidates and applications (docs/23 §4.4 to §4.9)
-- -------------------------------------------------------------------------------------
ALTER TABLE recruit.candidate
  ALTER COLUMN email DROP NOT NULL,
  ALTER COLUMN retention_until DROP NOT NULL,                  -- set from the applications once each is decided (§4.5)
  ADD COLUMN talent_pool_consent    boolean NOT NULL DEFAULT false,
  ADD COLUMN talent_pool_consent_at timestamptz,
  ADD CONSTRAINT candidate_contact CHECK (email IS NOT NULL OR phone IS NOT NULL),
  ADD CONSTRAINT candidate_pool_consent_dated CHECK (NOT talent_pool_consent OR talent_pool_consent_at IS NOT NULL);
COMMENT ON COLUMN recruit.candidate.retention_until IS
  'The latest retention_until of the candidate''s decided applications (recruit.application), or of the talent pool consent; empty while every application is open.';

CREATE FUNCTION recruit.check_candidate() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE need text := platform.setting_text(NEW.tenant_id, 'recruit.applicant_contact');
BEGIN
  IF (need IN ('email','email_and_phone') AND NEW.email IS NULL) OR (need IN ('phone','email_and_phone') AND NEW.phone IS NULL) THEN
    RAISE EXCEPTION 'CANDIDATE_CONTACT_REQUIRED: the organization asks for % to apply', need USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER candidate_check BEFORE INSERT OR UPDATE OF email, phone ON recruit.candidate
  FOR EACH ROW EXECUTE FUNCTION recruit.check_candidate();

ALTER TABLE recruit.application
  ADD COLUMN posting_id           uuid REFERENCES recruit.posting,
  ADD COLUMN missing_requirements text[] NOT NULL DEFAULT '{}',   -- required qualifications not shown (flagged or screened out)
  ADD COLUMN match_score          numeric(5,2),
  ADD COLUMN match_reasons        jsonb,
  ADD COLUMN decided_by           uuid REFERENCES platform.app_user,
  ADD COLUMN decided_by_kind      text CHECK (decided_by_kind IN ('person','requirement_rule')),
  ADD COLUMN decided_on           date,
  ADD COLUMN retention_until      date;

-- How long a decided application is kept: never less than the law of each jurisdiction that applies, and never
-- less than the organization's own minimum (setting recruit.candidate_retention, chosen at setup).
CREATE FUNCTION recruit.retention_until(p_tenant uuid, p_posting_jurisdiction text, p_decided_on date, p_posting_closed_on date)
RETURNS date LANGUAGE plpgsql STABLE AS $$
DECLARE s jsonb; js text[]; j text; r jsonb; base date; result date;
BEGIN
  s := platform.setting(p_tenant, 'recruit.candidate_retention', p_decided_on);
  IF s ->> 'mode' = 'per_province' THEN
    js := ARRAY[p_posting_jurisdiction];
  ELSIF s ->> 'mode' = 'longest_for_all' THEN
    js := ARRAY(SELECT DISTINCT x FROM unnest(ARRAY(
            SELECT lv.province::text FROM core.location_version lv
             WHERE lv.tenant_id = p_tenant AND lv.valid_period @> p_decided_on AND upper_inf(lv.sys_period)) || p_posting_jurisdiction) x);
  ELSE
    RAISE EXCEPTION 'SETTING_VALUE_NOT_ALLOWED: recruit.candidate_retention mode must be per_province or longest_for_all'
      USING ERRCODE = 'check_violation';
  END IF;
  result := (p_decided_on + make_interval(months => (s ->> 'organizationMonths')::int))::date;
  FOREACH j IN ARRAY js LOOP
    r := ref.employment_standard(j, 'candidate_records_retention', p_decided_on);
    base := CASE r ->> 'from' WHEN 'decision' THEN p_decided_on WHEN 'posting_closed' THEN p_posting_closed_on END;
    IF base IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: the % retention period counts from %, which is not known', j, r ->> 'from' USING ERRCODE = 'check_violation';
    END IF;
    result := greatest(result, (base + make_interval(months => (r ->> 'months')::int))::date);
  END LOOP;
  RETURN result;
END $$;

CREATE FUNCTION recruit.check_application() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p recruit.posting; req recruit.requisition; ai jsonb;
BEGIN
  SELECT * INTO req FROM recruit.requisition WHERE requisition_id = NEW.requisition_id;
  IF NEW.match_score IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.match_score IS DISTINCT FROM OLD.match_score) THEN
    ai := platform.setting(NEW.tenant_id, 'recruit.ai_match');
    IF NOT (ai ->> 'enabled')::boolean THEN
      RAISE EXCEPTION 'MATCH_SUGGESTIONS_OFF: AI match suggestions are not switched on' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.match_reasons IS NULL THEN
      RAISE EXCEPTION 'MATCH_WITHOUT_REASONS: a match score shows its reasons' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.outcome IS NOT NULL AND (TG_OP = 'INSERT' OR NEW.outcome IS DISTINCT FROM OLD.outcome) THEN
    IF NEW.decided_by_kind IS NULL OR NEW.decided_on IS NULL OR (NEW.decided_by_kind = 'person' AND NEW.decided_by IS NULL) THEN
      RAISE EXCEPTION 'APPLICATION_DECISION_UNSIGNED: an outcome names the person who decided it and the date' USING ERRCODE = 'check_violation';
    END IF;
    SELECT * INTO p FROM recruit.posting WHERE posting_id = NEW.posting_id;
    IF NEW.decided_by_kind = 'requirement_rule' AND NOT (NEW.outcome = 'screened_out' AND p.missing_requirement = 'screen_out'
                                                         AND cardinality(NEW.missing_requirements) > 0) THEN
      RAISE EXCEPTION 'REQUIREMENT_RULE_NOT_ALLOWED: only a posting set to screen out can screen out a candidate missing a required qualification; every other decision is a person''s'
        USING ERRCODE = 'check_violation';
    END IF;
    IF EXISTS (SELECT 1 FROM recruit.interview i WHERE i.application_id = NEW.application_id AND i.status = 'held'
                 AND NOT EXISTS (SELECT 1 FROM recruit.interview_score s WHERE s.interview_id = i.interview_id AND s.submitted_at IS NOT NULL)) THEN
      IF platform.setting_text(NEW.tenant_id, 'recruit.interview_scoring', NEW.decided_on,
                               core.position_legal_entity(req.position_id, NEW.decided_on)) = 'every_interview' THEN
        RAISE EXCEPTION 'INTERVIEW_SCORE_REQUIRED: every interview is scored before a decision' USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    NEW.retention_until := recruit.retention_until(NEW.tenant_id, req.posting_jurisdiction::text, NEW.decided_on, p.closes_on);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER application_check BEFORE INSERT OR UPDATE ON recruit.application
  FOR EACH ROW EXECUTE FUNCTION recruit.check_application();

-- The candidate keeps the latest retention date of its decided applications
CREATE FUNCTION recruit.roll_up_retention() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  UPDATE recruit.candidate c SET retention_until = (
           SELECT max(a.retention_until) FROM recruit.application a WHERE a.candidate_id = c.candidate_id)
   WHERE c.candidate_id = NEW.candidate_id;
  RETURN NULL;
END $$;
CREATE TRIGGER application_retention_roll_up AFTER INSERT OR UPDATE OF retention_until ON recruit.application
  FOR EACH ROW WHEN (NEW.retention_until IS NOT NULL) EXECUTE FUNCTION recruit.roll_up_retention();

CREATE TABLE recruit.application_answer (
  tenant_id      uuid NOT NULL,
  application_id uuid NOT NULL REFERENCES recruit.application ON DELETE CASCADE,
  posting_id     uuid NOT NULL,
  seq            smallint NOT NULL,
  answer         jsonb NOT NULL,
  PRIMARY KEY (application_id, seq),
  FOREIGN KEY (posting_id, seq) REFERENCES recruit.posting_question (posting_id, seq)
);

-- Interviews and scores: a submitted score is locked; a panelist sees others' scores only after submitting their own
CREATE TABLE recruit.interview (
  tenant_id      uuid NOT NULL,
  interview_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES recruit.application,
  kit_code       text,
  held_on        date,
  status         text NOT NULL CHECK (status IN ('scheduled','held','cancelled')),
  CONSTRAINT interview_held_dated CHECK (status <> 'held' OR held_on IS NOT NULL)
);
CREATE TABLE recruit.interview_score (
  tenant_id     uuid NOT NULL,
  interview_id  uuid NOT NULL REFERENCES recruit.interview,
  panelist_user uuid NOT NULL REFERENCES platform.app_user,
  scores        jsonb NOT NULL,
  notes         text,
  submitted_at  timestamptz,
  PRIMARY KEY (interview_id, panelist_user)
);
CREATE FUNCTION recruit.guard_interview_score() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' OR OLD.submitted_at IS NOT NULL THEN
    RAISE EXCEPTION 'SCORE_LOCKED: a submitted interview score cannot be changed or removed' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER interview_score_locked BEFORE UPDATE OR DELETE ON recruit.interview_score
  FOR EACH ROW EXECUTE FUNCTION recruit.guard_interview_score();
CREATE FUNCTION recruit.can_see_panel_scores(p_interview uuid, p_viewer uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM recruit.interview_score s
                  WHERE s.interview_id = p_interview AND s.panelist_user = p_viewer AND s.submitted_at IS NOT NULL)
$$;

-- Messages to candidates come from the organization's templates, with or without a reason
CREATE TABLE recruit.message_template (
  tenant_id       uuid NOT NULL REFERENCES platform.tenant,
  code            text NOT NULL,
  purpose         text NOT NULL CHECK (purpose IN ('not_selected','shortlisted','interview_invitation','offer','talent_pool','general')),
  includes_reason boolean NOT NULL,
  subject_en      text NOT NULL,
  subject_fr      text,
  body_en         text NOT NULL,
  body_fr         text,
  status          text NOT NULL CHECK (status IN ('active','retired')),
  PRIMARY KEY (tenant_id, code)
);
CREATE TABLE recruit.message_batch (
  tenant_id     uuid NOT NULL,
  batch_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_code text NOT NULL,
  posting_id    uuid REFERENCES recruit.posting,
  sent_by       uuid NOT NULL REFERENCES platform.app_user,
  sent_at       timestamptz NOT NULL DEFAULT now(),
  recipients    int NOT NULL CHECK (recipients > 0),
  reason        text,
  FOREIGN KEY (tenant_id, template_code) REFERENCES recruit.message_template (tenant_id, code)
);
CREATE FUNCTION recruit.check_message_batch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT includes_reason FROM recruit.message_template WHERE tenant_id = NEW.tenant_id AND code = NEW.template_code)
     AND (NEW.reason IS NULL OR length(btrim(NEW.reason)) = 0) THEN
    RAISE EXCEPTION 'MESSAGE_REASON_REQUIRED: template % includes a reason', NEW.template_code USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER message_batch_check BEFORE INSERT ON recruit.message_batch
  FOR EACH ROW EXECUTE FUNCTION recruit.check_message_batch();

-- -------------------------------------------------------------------------------------
-- 8. Offers (docs/23 §5)
-- -------------------------------------------------------------------------------------
ALTER TABLE recruit.offer DROP CONSTRAINT IF EXISTS offer_status_check;
ALTER TABLE recruit.offer
  ALTER COLUMN application_id DROP NOT NULL,                  -- a direct hire has no application
  ADD COLUMN hire_path            text CHECK (hire_path IN ('requisition','direct_hire')),
  ADD COLUMN candidate_id         uuid REFERENCES recruit.candidate,
  ADD COLUMN position_id          uuid REFERENCES core.position,
  ADD COLUMN requested_by         uuid REFERENCES platform.app_user,
  ADD COLUMN route_id             uuid REFERENCES platform.workflow_route,
  ADD COLUMN conditional          boolean,
  ADD COLUMN terms                jsonb,                       -- {"payRate":..,"payBasis":..,"startDate":..,"fte":..,"probation":..}
  ADD COLUMN approved_terms       jsonb,
  ADD COLUMN terms_changed_at     timestamptz,
  ADD COLUMN expires_on           date,
  ADD COLUMN expiry_set_by        uuid REFERENCES platform.app_user,
  ADD COLUMN contract_document_id uuid REFERENCES platform.document,
  ADD COLUMN contract_signed_at   timestamptz,
  ADD COLUMN internal_move        text CHECK (internal_move IN ('transfer','resign_and_rehire')),
  ADD CONSTRAINT offer_status_check CHECK (status IN ('draft','pending_approval','approved','sent','accepted','declined','withdrawn','expired'));

CREATE FUNCTION recruit.offer_internal_employment(p_offer recruit.offer) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT a.internal_employment_id FROM recruit.application a WHERE a.application_id = p_offer.application_id
$$;

CREATE FUNCTION recruit.check_offer() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE rule text; reapprove boolean := false; le uuid;
BEGIN
  le := core.position_legal_entity(coalesce(NEW.position_id,
          (SELECT r.position_id FROM recruit.application a JOIN recruit.requisition r ON r.requisition_id = a.requisition_id
            WHERE a.application_id = NEW.application_id)), NEW.start_date);
  IF TG_OP = 'INSERT' THEN
    IF NEW.hire_path IS NULL OR NEW.conditional IS NULL OR NEW.terms IS NULL OR NEW.requested_by IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: an offer states its hire path, whether it is conditional, its terms and its requester'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.hire_path = 'requisition' AND NEW.application_id IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: an offer on a requisition names its application' USING ERRCODE = 'check_violation';
    END IF;
    -- A posting is needed unless the requisition uses one of the organization's exemption rules (§3.3)
    IF NEW.hire_path = 'requisition' AND EXISTS (
         SELECT 1 FROM recruit.application a JOIN recruit.requisition r ON r.requisition_id = a.requisition_id
          WHERE a.application_id = NEW.application_id AND a.posting_id IS NULL AND r.posting_exemption_code IS NULL
            AND platform.setting_text(r.tenant_id, 'recruit.posting_default', NEW.start_date, le) = 'required') THEN
      RAISE EXCEPTION 'POSTING_REQUIRED: the application came from no posting and the requisition uses no posting exemption rule'
        USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.hire_path = 'direct_hire' AND (NEW.candidate_id IS NULL OR NEW.position_id IS NULL OR NEW.application_id IS NOT NULL) THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a direct hire names the candidate and the position, and has no application' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.hire_path = 'direct_hire' AND platform.setting_text(NEW.tenant_id, 'recruit.direct_hire', NEW.start_date, le) = 'not_allowed' THEN
      RAISE EXCEPTION 'DIRECT_HIRE_NOT_ALLOWED: the organization hires only through requisitions' USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  -- Changed terms after approval go back through the route, as the organization sets (§5.4)
  IF NEW.terms IS DISTINCT FROM OLD.terms AND OLD.status IN ('approved','sent') THEN
    rule := platform.setting_text(NEW.tenant_id, 'offers.reapprove_on_change', NEW.start_date, le);
    reapprove := CASE rule
                   WHEN 'any_change' THEN true
                   WHEN 'pay_or_start_changed' THEN (NEW.terms ->> 'payRate')::numeric > (OLD.approved_terms ->> 'payRate')::numeric
                                                     OR (NEW.terms ->> 'startDate') IS DISTINCT FROM (OLD.approved_terms ->> 'startDate')
                   ELSE false
                 END;
    IF reapprove AND NEW.status <> 'pending_approval' THEN
      RAISE EXCEPTION 'OFFER_CHANGE_NEEDS_APPROVAL: changed terms go back through the offer route (offers.reapprove_on_change = %)', rule
        USING ERRCODE = 'check_violation';
    END IF;
    IF reapprove THEN NEW.terms_changed_at := now(); END IF;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'pending_approval' AND NEW.route_id IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: an offer is submitted with its approval route' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status = 'approved' THEN
      IF NOT platform.route_complete(NEW.route_id, 'offer', NEW.offer_id, NEW.requested_by, NEW.terms_changed_at) THEN
        RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the offer''s route is not complete' USING ERRCODE = 'check_violation';
      END IF;
      NEW.approved_terms := NEW.terms;
    END IF;
    IF NEW.status = 'sent' AND (OLD.status <> 'approved' OR NEW.expires_on IS NULL OR NEW.expiry_set_by IS NULL) THEN
      RAISE EXCEPTION 'OFFER_NOT_READY: an offer is sent once approved, with its expiry date and who set it' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status = 'accepted' AND OLD.status <> 'sent' THEN
      RAISE EXCEPTION 'OFFER_NOT_SENT: only a sent offer can be accepted' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF NEW.contract_signed_at IS NOT NULL AND OLD.contract_signed_at IS NULL AND NEW.status <> 'accepted' THEN
    RAISE EXCEPTION 'CONTRACT_BEFORE_ACCEPTANCE: the contract is signed after the offer is accepted' USING ERRCODE = 'check_violation';
  END IF;
  -- The person becomes an employee only when the offer is accepted and the contract signed (§5.5)
  IF NEW.hire_change_set_id IS NOT NULL AND OLD.hire_change_set_id IS NULL THEN
    IF NEW.status <> 'accepted' OR NEW.contract_signed_at IS NULL THEN
      RAISE EXCEPTION 'HIRE_BEFORE_CONTRACT_SIGNED: the employee record is created when the offer is accepted and the contract signed'
        USING ERRCODE = 'check_violation';
    END IF;
    IF recruit.offer_internal_employment(NEW) IS NOT NULL AND NEW.internal_move IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: an internal move is a transfer or a resignation and rehire' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER offer_check BEFORE INSERT OR UPDATE ON recruit.offer
  FOR EACH ROW EXECUTE FUNCTION recruit.check_offer();

-- Conditions of an offer. Background, criminal record, reference, credential, licence and medical checks happen only
-- after a conditional offer, with the candidate's consent (§5.3).
CREATE TABLE recruit.offer_condition (
  tenant_id           uuid NOT NULL,
  condition_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id            uuid NOT NULL REFERENCES recruit.offer,
  kind                text NOT NULL CHECK (kind IN ('background_check','criminal_record_check','reference_check','credential_check',
                                                    'licence_check','medical','work_authorization','tell_current_supervisor','other')),
  description         text,
  status              text NOT NULL CHECK (status IN ('pending','requested','met','not_met','waived')),
  consent_document_id uuid REFERENCES platform.document,
  requested_at        timestamptz,
  provider_ref        text,
  decided_by          uuid REFERENCES platform.app_user,
  decided_at          timestamptz,
  CONSTRAINT offer_condition_other_described CHECK (kind <> 'other' OR description IS NOT NULL),
  CONSTRAINT offer_condition_decided CHECK (status NOT IN ('met','not_met','waived') OR (decided_by IS NOT NULL AND decided_at IS NOT NULL))
);

CREATE FUNCTION recruit.check_offer_condition() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE o recruit.offer;
BEGIN
  SELECT * INTO o FROM recruit.offer WHERE offer_id = NEW.offer_id;
  IF NEW.kind IN ('background_check','criminal_record_check','reference_check','credential_check','licence_check','medical') THEN
    IF NOT o.conditional THEN
      RAISE EXCEPTION 'CHECK_NEEDS_CONDITIONAL_OFFER: % is a condition of a conditional offer only', NEW.kind USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.status <> 'pending' AND (TG_OP = 'INSERT' OR OLD.status = 'pending') THEN
      IF o.status NOT IN ('sent','accepted') THEN
        RAISE EXCEPTION 'CHECK_BEFORE_CONDITIONAL_OFFER: % starts after the conditional offer is made', NEW.kind USING ERRCODE = 'check_violation';
      END IF;
      IF NEW.kind IN ('background_check','criminal_record_check') AND NEW.consent_document_id IS NULL THEN
        RAISE EXCEPTION 'CONSENT_REQUIRED: a % needs the candidate''s signed consent', NEW.kind USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER offer_condition_check BEFORE INSERT OR UPDATE ON recruit.offer_condition
  FOR EACH ROW EXECUTE FUNCTION recruit.check_offer_condition();

-- An internal applicant who accepts tells their current supervisor: a condition of the move (§4.9)
CREATE FUNCTION recruit.add_internal_conditions() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF recruit.offer_internal_employment(NEW) IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM recruit.offer_condition c WHERE c.offer_id = NEW.offer_id AND c.kind = 'tell_current_supervisor') THEN
    INSERT INTO recruit.offer_condition (tenant_id, offer_id, kind, status) VALUES (NEW.tenant_id, NEW.offer_id, 'tell_current_supervisor', 'pending');
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER offer_internal_conditions AFTER UPDATE OF status ON recruit.offer
  FOR EACH ROW WHEN (NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted') EXECUTE FUNCTION recruit.add_internal_conditions();

CREATE FUNCTION recruit.open_conditions(p_offer uuid) RETURNS int LANGUAGE sql STABLE AS $$
  SELECT count(*)::int FROM recruit.offer_condition WHERE offer_id = p_offer AND status NOT IN ('met','waived')
$$;

-- -------------------------------------------------------------------------------------
-- 9. Pre-boarding and onboarding (docs/23 §6). Pre-boarding opens when the contract is signed; the new hire uses
--    the login they keep as an employee, limited to pre-boarding screens until the start date.
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.app_user ADD COLUMN preboarding_until date;
COMMENT ON COLUMN platform.app_user.preboarding_until IS
  'Set for a new hire when the contract is signed: until this date (the start date) the user sees only pre-boarding screens (docs/23 §6.1).';

CREATE TABLE recruit.onboarding_plan (
  tenant_id    uuid NOT NULL REFERENCES platform.tenant,
  plan_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL,
  name_en      text NOT NULL,
  name_fr      text,
  hire_kind    text NOT NULL CHECK (hire_kind IN ('new_hire','rehire','internal_transfer','student','contractor','other')),
  applies_to   jsonb NOT NULL,                     -- {} = everyone of this kind; keys narrow it: orgUnits, jobs, locations, provinces, agreements, employmentTypes
  status       text NOT NULL CHECK (status IN ('active','retired')),
  starter_code text,
  UNIQUE (tenant_id, code),
  CONSTRAINT onboarding_plan_scope_object CHECK (jsonb_typeof(applies_to) = 'object')
);

CREATE FUNCTION recruit.check_onboarding_plan() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(NEW.applies_to) LOOP
    IF k NOT IN ('orgUnits','jobs','locations','provinces','agreements','employmentTypes') THEN
      RAISE EXCEPTION 'ONBOARDING_SCOPE_UNKNOWN: % is not an onboarding plan scope', k USING ERRCODE = 'check_violation';
    END IF;
    IF jsonb_typeof(NEW.applies_to -> k) <> 'array' THEN
      RAISE EXCEPTION 'ONBOARDING_SCOPE_UNKNOWN: % takes a list', k USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER onboarding_plan_check BEFORE INSERT OR UPDATE OF applies_to ON recruit.onboarding_plan
  FOR EACH ROW EXECUTE FUNCTION recruit.check_onboarding_plan();

CREATE TABLE recruit.onboarding_plan_item (
  tenant_id       uuid NOT NULL,
  plan_id         uuid NOT NULL REFERENCES recruit.onboarding_plan ON DELETE CASCADE,
  item_code       text NOT NULL,
  seq             smallint NOT NULL,
  phase           text NOT NULL CHECK (phase IN ('pre_boarding','onboarding')),
  kind            text NOT NULL CHECK (kind IN ('form','document','training','equipment','access','orientation','meeting','task','survey','video')),
  form_code       text CHECK (form_code IN ('sin','td1_federal','provincial_tax_form','direct_deposit','emergency_contact','work_authorization',
                                            's87_declaration','policy_acknowledgement','self_identification','benefits_enrolment')),
  training_code   text,                                   -- a course in Learning (requirements/08), when there is one
  owner_kind      text NOT NULL CHECK (owner_kind IN ('new_hire','hr','payroll','it','facilities','finance','hiring_manager','learning',
                                                      'security','communications','buddy','other')),
  due_event       text NOT NULL CHECK (due_event IN ('contract_signed','start_date','first_pay','benefits_start','probation_end')),
  due_offset_days smallint NOT NULL,                      -- negative: before the event
  depends_on      text,                                   -- another item_code of the same plan
  required        boolean NOT NULL,
  extra           text CHECK (extra IN ('welcomeVideos','checkInSurveys','culturalTrack','buddyProgram')),
  name_en         text NOT NULL,
  name_fr         text,
  PRIMARY KEY (plan_id, item_code),
  CONSTRAINT plan_item_form CHECK ((kind = 'form') = (form_code IS NOT NULL)),
  CONSTRAINT plan_item_self_id_voluntary CHECK (form_code IS DISTINCT FROM 'self_identification' OR NOT required),
  CONSTRAINT plan_item_preboarding_by_start CHECK (phase <> 'pre_boarding' OR due_event = 'contract_signed'
                                                   OR (due_event = 'start_date' AND due_offset_days <= 0))
);

ALTER TABLE recruit.onboarding_task
  ADD COLUMN plan_id              uuid REFERENCES recruit.onboarding_plan,
  ADD COLUMN item_code            text,
  ADD COLUMN phase                text CHECK (phase IN ('pre_boarding','onboarding')),
  ADD COLUMN form_code            text CHECK (form_code IN ('sin','td1_federal','provincial_tax_form','direct_deposit','emergency_contact','work_authorization',
                                                            's87_declaration','policy_acknowledgement','self_identification','benefits_enrolment')),
  ADD COLUMN owner_kind           text CHECK (owner_kind IN ('new_hire','hr','payroll','it','facilities','finance','hiring_manager','learning',
                                                             'security','communications','buddy','other')),
  ADD COLUMN owner_user           uuid REFERENCES platform.app_user,
  ADD COLUMN start_date           date,
  ADD COLUMN due_event            text CHECK (due_event IN ('contract_signed','start_date','first_pay','benefits_start','probation_end')),
  ADD COLUMN legal_due_date       date,                   -- set from the law (the SIN within 3 days of starting); the due date may be earlier, never later
  ADD COLUMN required             boolean,
  ADD COLUMN depends_on           uuid REFERENCES recruit.onboarding_task,
  ADD COLUMN answer               jsonb,
  ADD COLUMN evidence_document_id uuid REFERENCES platform.document,
  ADD COLUMN completed_at         timestamptz,
  ADD COLUMN completed_by         uuid REFERENCES platform.app_user,
  ADD COLUMN escalation_level     smallint NOT NULL DEFAULT 0 CHECK (escalation_level BETWEEN 0 AND 3),   -- 1 owner reminded, 2 manager told, 3 HR told
  ADD COLUMN name_en              text,
  ADD COLUMN name_fr              text;

CREATE FUNCTION recruit.check_onboarding_task() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.form_code = 'sin' THEN
    IF NEW.start_date IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: the SIN task needs the start date' USING ERRCODE = 'check_violation';
    END IF;
    NEW.legal_due_date := NEW.start_date + (ref.employment_standard(NULL, 'sin_due', NEW.start_date) ->> 'days_after_start')::int;
  END IF;
  IF NEW.legal_due_date IS NOT NULL AND NEW.due_date IS NOT NULL AND NEW.due_date > NEW.legal_due_date THEN
    RAISE EXCEPTION 'DUE_AFTER_LEGAL_DATE: due % is after the legal date %', NEW.due_date, NEW.legal_due_date USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.phase = 'pre_boarding' AND NEW.due_date IS NOT NULL AND NEW.start_date IS NOT NULL AND NEW.due_date > NEW.start_date THEN
    RAISE EXCEPTION 'PREBOARDING_DUE_AFTER_START: pre-boarding is completed by the first day of work' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'waived' AND NEW.legal_due_date IS NOT NULL THEN
    RAISE EXCEPTION 'LEGAL_TASK_CANNOT_BE_WAIVED: % is required by law', NEW.form_code USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'done' AND (TG_OP = 'INSERT' OR OLD.status <> 'done') THEN
    IF NEW.completed_at IS NULL OR NEW.completed_by IS NULL THEN
      RAISE EXCEPTION 'TASK_COMPLETION_UNSIGNED: a completed task names who completed it and when' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.form_code = 's87_declaration' AND jsonb_typeof(NEW.answer -> 'claims') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: the s. 87 question is answered yes or no (answer.claims)' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER onboarding_task_check BEFORE INSERT OR UPDATE ON recruit.onboarding_task
  FOR EACH ROW EXECUTE FUNCTION recruit.check_onboarding_task();

-- A new hire who claims the s. 87 exemption gives HR a task before the first pay; until HR records the exemption with
-- its basis, normal deductions apply (docs/22 FB-024)
CREATE FUNCTION recruit.s87_follow_up() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.answer ->> 'claims')::boolean THEN
    INSERT INTO recruit.onboarding_task (tenant_id, employment_id, code, owner_role, due_date, status, item_code, phase, owner_kind,
                                         start_date, due_event, required, depends_on, name_en, name_fr)
    VALUES (NEW.tenant_id, NEW.employment_id, 'record_s87_exemption', 'hr', NULL, 'open', 'record_s87_exemption', 'onboarding', 'hr',
            NEW.start_date, 'first_pay', true, NEW.task_id,
            'Record the Indian Act s. 87 exemption and its basis before the first pay',
            'Inscrire l''exemption de l''article 87 de la Loi sur les Indiens et son fondement avant la première paie');
  END IF;
  RETURN NULL;
END $$;
CREATE TRIGGER onboarding_task_s87 AFTER UPDATE OF status ON recruit.onboarding_task
  FOR EACH ROW WHEN (NEW.form_code = 's87_declaration' AND NEW.status = 'done' AND OLD.status IS DISTINCT FROM 'done')
  EXECUTE FUNCTION recruit.s87_follow_up();

-- The plans that apply to a new hire: every active plan of the hire kind whose scope matches one of the
-- employment's positions on the date (organization-wide, department and role plans combine)
CREATE FUNCTION recruit.plans_for(p_employment uuid, p_hire_kind text, p_as_of date) RETURNS SETOF uuid
LANGUAGE plpgsql STABLE AS $$
DECLARE f jsonb; p record; k text; ok boolean;
BEGIN
  SELECT jsonb_build_object(
           'orgUnits',        coalesce(jsonb_agg(DISTINCT av.org_unit_id) , '[]'::jsonb),
           'jobs',            coalesce(jsonb_agg(DISTINCT pv.job_id) FILTER (WHERE pv.job_id IS NOT NULL), '[]'::jsonb),
           'locations',       coalesce(jsonb_agg(DISTINCT av.location_id), '[]'::jsonb),
           'provinces',       coalesce(jsonb_agg(DISTINCT lv.province), '[]'::jsonb),
           'agreements',      coalesce(jsonb_agg(DISTINCT av.agreement_id) FILTER (WHERE av.agreement_id IS NOT NULL), '[]'::jsonb),
           'employmentTypes', coalesce(jsonb_agg(DISTINCT lt.category) FILTER (WHERE lt.category IS NOT NULL), '[]'::jsonb))
    INTO f
    FROM core.assignment a
    JOIN core.assignment_version av ON av.assignment_id = a.assignment_id AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
    LEFT JOIN core.position_version pv ON pv.position_id = av.position_id AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
    LEFT JOIN core.location_version lv ON lv.location_id = av.location_id AND lv.valid_period @> p_as_of AND upper_inf(lv.sys_period)
    LEFT JOIN core.list_value lt ON lt.tenant_id = av.tenant_id AND lt.list_code = 'employment_type' AND lt.code = av.employment_type
   WHERE a.employment_id = p_employment;
  IF f -> 'orgUnits' = '[]'::jsonb THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: employment % holds no position on %', p_employment, p_as_of USING ERRCODE = 'check_violation';
  END IF;
  FOR p IN SELECT op.plan_id, op.applies_to FROM recruit.onboarding_plan op JOIN core.employment e ON e.tenant_id = op.tenant_id
            WHERE e.employment_id = p_employment AND op.hire_kind = p_hire_kind AND op.status = 'active' LOOP
    ok := true;
    FOR k IN SELECT jsonb_object_keys(p.applies_to) LOOP
      IF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p.applies_to -> k) x WHERE (f -> k) @> jsonb_build_array(x)) THEN
        ok := false; EXIT;
      END IF;
    END LOOP;
    IF ok THEN RETURN NEXT p.plan_id; END IF;
  END LOOP;
END $$;

-- Tasks for a new hire from every plan that applies. An item in several plans becomes one task (the earliest due
-- date). Items tied to an optional extra come only when the organization has turned that extra on. Due dates tied
-- to a later event (the first pay, benefits, the end of probation) are set when that date is known.
CREATE FUNCTION recruit.generate_onboarding_tasks(p_employment uuid, p_hire_kind text, p_contract_signed date, p_start date)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE e core.employment; x jsonb; n int;
BEGIN
  SELECT * INTO e FROM core.employment WHERE employment_id = p_employment;
  x := platform.setting(e.tenant_id, 'onboarding.extras', p_start, e.legal_entity_id);
  INSERT INTO recruit.onboarding_task (tenant_id, employment_id, code, owner_role, due_date, status, plan_id, item_code, phase, form_code,
                                       owner_kind, start_date, due_event, required, name_en, name_fr)
  SELECT DISTINCT ON (i.item_code) e.tenant_id, p_employment, i.item_code, i.owner_kind,
         CASE i.due_event WHEN 'contract_signed' THEN p_contract_signed + i.due_offset_days
                          WHEN 'start_date'      THEN p_start + i.due_offset_days END,
         'open', i.plan_id, i.item_code, i.phase, i.form_code, i.owner_kind, p_start, i.due_event,
         i.required OR (i.extra IS NOT NULL AND (x -> i.extra ->> 'required')::boolean),
         i.name_en, i.name_fr
    FROM recruit.plans_for(p_employment, p_hire_kind, p_start) pl(plan_id)
    JOIN recruit.onboarding_plan_item i ON i.plan_id = pl.plan_id
   WHERE i.extra IS NULL OR (x -> i.extra ->> 'enabled')::boolean
   ORDER BY i.item_code, CASE i.due_event WHEN 'contract_signed' THEN p_contract_signed + i.due_offset_days
                                          WHEN 'start_date'      THEN p_start + i.due_offset_days END NULLS LAST;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

-- Overdue tasks to escalate on a date: the owner, then the owner's manager, then HR (setting onboarding.escalation)
CREATE FUNCTION recruit.tasks_to_escalate(p_tenant uuid, p_as_of date)
RETURNS TABLE (task_id uuid, next_level smallint, notify text) LANGUAGE sql STABLE AS $$
  SELECT t.task_id, lvl.level, CASE lvl.level WHEN 1 THEN 'owner' WHEN 2 THEN 'owner_manager' ELSE 'hr' END
    FROM recruit.onboarding_task t
    JOIN core.employment e ON e.employment_id = t.employment_id
    CROSS JOIN LATERAL (SELECT platform.setting(t.tenant_id, 'onboarding.escalation', p_as_of, e.legal_entity_id) AS s) cfg
    CROSS JOIN LATERAL (SELECT (CASE
                          WHEN p_as_of >= t.due_date + (cfg.s ->> 'hrAfterDaysOverdue')::int      THEN 3
                          WHEN p_as_of >= t.due_date + (cfg.s ->> 'managerAfterDaysOverdue')::int THEN 2
                          WHEN p_as_of >= t.due_date - (cfg.s ->> 'ownerReminderDaysBefore')::int THEN 1
                          ELSE 0 END)::smallint AS level) lvl
   WHERE t.tenant_id = p_tenant AND t.status = 'open' AND t.due_date IS NOT NULL AND lvl.level > t.escalation_level
$$;

-- Buddies, mentors and trainers: the manager chooses, CanDo suggests; a new hire can have several, each for part
-- of the work and part of the timeline (docs/23 §6.5)
CREATE TABLE recruit.onboarding_support (
  tenant_id           uuid NOT NULL,
  support_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id       uuid NOT NULL REFERENCES core.employment,
  supporter_person_id uuid NOT NULL REFERENCES core.person,
  role                text NOT NULL CHECK (role IN ('buddy','mentor','trainer')),
  scope_note          text,                                -- the function or task this person covers, as the manager typed it
  valid_period        daterange NOT NULL,
  chosen_by           uuid NOT NULL REFERENCES platform.app_user,
  from_suggestion     boolean NOT NULL,
  CONSTRAINT onboarding_support_period CHECK (NOT isempty(valid_period))
);
CREATE FUNCTION recruit.check_onboarding_support() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE e core.employment;
BEGIN
  SELECT * INTO e FROM core.employment WHERE employment_id = NEW.employment_id;
  IF e.person_id = NEW.supporter_person_id THEN
    RAISE EXCEPTION 'SUPPORT_SELF: a new hire is not their own buddy or mentor' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.role = 'buddy' AND NOT (platform.setting(NEW.tenant_id, 'onboarding.extras', lower(NEW.valid_period), e.legal_entity_id)
                                   -> 'buddyProgram' ->> 'enabled')::boolean THEN
    RAISE EXCEPTION 'FEATURE_OFF: the buddy program is not turned on' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER onboarding_support_check BEFORE INSERT OR UPDATE ON recruit.onboarding_support
  FOR EACH ROW EXECUTE FUNCTION recruit.check_onboarding_support();

-- Suggestions for the manager: people in the same org unit, then the same location, on the date
CREATE FUNCTION recruit.suggest_supporters(p_employment uuid, p_as_of date)
RETURNS TABLE (person_id uuid, reason text) LANGUAGE sql STABLE AS $$
  WITH mine AS (
    SELECT av.org_unit_id, av.location_id, e.person_id
      FROM core.employment e JOIN core.assignment a ON a.employment_id = e.employment_id
      JOIN core.assignment_version av ON av.assignment_id = a.assignment_id AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
     WHERE e.employment_id = p_employment)
  SELECT DISTINCT ON (e2.person_id) e2.person_id,
         CASE WHEN av2.org_unit_id IN (SELECT org_unit_id FROM mine) THEN 'same_org_unit' ELSE 'same_location' END
    FROM core.assignment_version av2
    JOIN core.assignment a2 ON a2.assignment_id = av2.assignment_id
    JOIN core.employment e2 ON e2.employment_id = a2.employment_id
   WHERE av2.valid_period @> p_as_of AND upper_inf(av2.sys_period) AND av2.status = 'active'
     AND (av2.org_unit_id IN (SELECT org_unit_id FROM mine) OR av2.location_id IN (SELECT location_id FROM mine))
     AND e2.person_id NOT IN (SELECT person_id FROM mine)
   ORDER BY e2.person_id, CASE WHEN av2.org_unit_id IN (SELECT org_unit_id FROM mine) THEN 0 ELSE 1 END
$$;

-- -------------------------------------------------------------------------------------
-- 10. Probation (docs/23 §7; probation kinds and lengths: docs/21 §3.2)
-- -------------------------------------------------------------------------------------
-- Last day of a probation counted in calendar days or months, extensions included. A probation counted in hours,
-- days or shifts ends when its counter reaches the amount (docs/21 §3.2); asking for its calendar end is an error.
CREATE FUNCTION core.probation_calendar_end(p_probation uuid, p_as_of date) RETURNS date LANGUAGE plpgsql STABLE AS $$
DECLARE p core.probation; total numeric;
BEGIN
  SELECT * INTO p FROM core.probation WHERE probation_id = p_probation AND valid_period @> p_as_of AND upper_inf(sys_period);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROBATION_UNKNOWN: no probation % on %', p_probation, p_as_of USING ERRCODE = 'check_violation';
  END IF;
  total := p.required_amount + p.extended_by;
  IF p.measure NOT IN ('calendar_days','calendar_months') THEN
    RAISE EXCEPTION 'PROBATION_MEASURE_COUNTED: probation % is counted in %; its end comes from its counter', p_probation, p.measure
      USING ERRCODE = 'check_violation';
  END IF;
  IF total <> trunc(total) THEN
    RAISE EXCEPTION 'PROBATION_AMOUNT_NOT_WHOLE: % % cannot be counted on a calendar', total, p.measure USING ERRCODE = 'check_violation';
  END IF;
  RETURN CASE p.measure
           WHEN 'calendar_months' THEN (p.started_on + make_interval(months => total::int))::date - 1
           ELSE p.started_on + total::int - 1
         END;
END $$;

CREATE TABLE core.probation_check_in (
  tenant_id          uuid NOT NULL,
  check_in_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  probation_id       uuid NOT NULL,
  due_on             date NOT NULL,
  basis              jsonb NOT NULL,                       -- the check-in point that set it, e.g. {"from":"start","days":30}
  review_id          uuid REFERENCES talent.review,
  status             text NOT NULL CHECK (status IN ('scheduled','done','missed','cancelled')),
  manager_signed_at  timestamptz,
  employee_signed_at timestamptz,
  CONSTRAINT probation_check_in_signed CHECK (status <> 'done' OR manager_signed_at IS NOT NULL)
);

-- The check-in dates for a probation from the setting (its kind's list, or the default list)
CREATE FUNCTION core.probation_check_in_dates(p_probation uuid, p_as_of date)
RETURNS TABLE (due_on date, basis jsonb) LANGUAGE plpgsql STABLE AS $$
DECLARE p core.probation; e core.employment; s jsonb; pts jsonb; pt jsonb; ends date;
BEGIN
  SELECT * INTO p FROM core.probation x WHERE x.probation_id = p_probation AND x.valid_period @> p_as_of AND upper_inf(x.sys_period);
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROBATION_UNKNOWN: no probation % on %', p_probation, p_as_of USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO e FROM core.employment WHERE employment_id = p.employment_id;
  s := platform.setting(p.tenant_id, 'probation.check_ins', p.started_on, e.legal_entity_id);
  pts := coalesce(s -> p.kind, s -> 'default');           -- the kind's own list replaces the default list (docs/23 §7.1)
  FOR pt IN SELECT jsonb_array_elements(pts) LOOP
    IF pt ->> 'from' = 'start' THEN
      due_on := p.started_on + (pt ->> 'days')::int;
    ELSIF pt ->> 'from' = 'end' THEN
      ends := core.probation_calendar_end(p_probation, p_as_of);
      due_on := ends - (pt ->> 'days')::int;
    ELSE
      RAISE EXCEPTION 'SETTING_VALUE_NOT_ALLOWED: probation.check_ins points count from start or end' USING ERRCODE = 'check_violation';
    END IF;
    basis := pt;
    RETURN NEXT;
  END LOOP;
END $$;

-- Reminders due on a date: the days before the end that the setting lists
CREATE FUNCTION core.probation_reminders_due(p_tenant uuid, p_as_of date)
RETURNS TABLE (probation_id uuid, employment_id uuid, ends_on date, days_left int) LANGUAGE sql STABLE AS $$
  SELECT x.probation_id, x.employment_id, x.ends_on, (x.ends_on - p_as_of)
    FROM (SELECT p.probation_id, p.employment_id, p.tenant_id, e.legal_entity_id, core.probation_calendar_end(p.probation_id, p_as_of) AS ends_on
            FROM core.probation p JOIN core.employment e ON e.employment_id = p.employment_id
           WHERE p.tenant_id = p_tenant AND p.valid_period @> p_as_of AND upper_inf(p.sys_period)
             AND p.status IN ('in_progress','extended') AND p.measure IN ('calendar_days','calendar_months')) x
   WHERE platform.setting(x.tenant_id, 'probation.end_reminders_days', p_as_of, x.legal_entity_id) @> to_jsonb(x.ends_on - p_as_of)
$$;

-- The end date passed and nobody recorded a decision: the probation is passed and HR is told (docs/22 FB-034).
-- Run daily by the scheduler with a system change set; returns the probations it closed so HR can be told.
CREATE FUNCTION core.close_lapsed_probations(p_tenant uuid, p_as_of date, p_change_set uuid)
RETURNS TABLE (probation_id uuid, employment_id uuid, ended_on date) LANGUAGE plpgsql AS $$
DECLARE r core.probation; ends date;
BEGIN
  FOR r IN SELECT * FROM core.probation p
            WHERE p.tenant_id = p_tenant AND p.valid_period @> p_as_of AND upper_inf(p.sys_period)
              AND p.status IN ('in_progress','extended') AND p.measure IN ('calendar_days','calendar_months') LOOP
    ends := core.probation_calendar_end(r.probation_id, p_as_of);
    CONTINUE WHEN ends >= p_as_of;
    UPDATE core.probation SET sys_period = tstzrange(lower(sys_period), now()) WHERE version_id = r.version_id;
    -- fallback: FB-034
    INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, agreement_id, bargaining_unit, assignment_id, measure,
                                required_amount, counter_code, started_on, extended_by, status, outcome_on, reason, rule_source,
                                valid_period, change_set_id)
    VALUES (r.tenant_id, r.probation_id, r.employment_id, r.kind, r.agreement_id, r.bargaining_unit, r.assignment_id, r.measure,
            r.required_amount, r.counter_code, r.started_on, r.extended_by, 'passed', ends,
            'End date passed without a recorded decision; passed and HR told (docs/22 FB-034)', r.rule_source, r.valid_period, p_change_set);
    probation_id := r.probation_id; employment_id := r.employment_id; ended_on := ends;
    RETURN NEXT;
  END LOOP;
END $$;

-- Extensions: for any reason the employer records, before the end date, after the employee is told (docs/23 §7.4)
CREATE TABLE core.probation_extension (
  tenant_id              uuid NOT NULL,
  extension_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  probation_id           uuid NOT NULL,
  amount                 numeric(10,2) NOT NULL CHECK (amount > 0),   -- in the probation's own measure
  reason                 text NOT NULL CHECK (length(btrim(reason)) > 0),
  requested_by           uuid NOT NULL REFERENCES platform.app_user,
  route_id               uuid REFERENCES platform.workflow_route,
  jurisdiction           text NOT NULL,                    -- employment standards jurisdiction of the position
  agreement_maximum      numeric(10,2),                    -- the agreement's longest total extension, for agreement and trial probations
  employee_notified_at   timestamptz,
  employee_notice_method text CHECK (employee_notice_method IN ('in_person','video','phone','letter','email','other')),
  union_notice_required  boolean NOT NULL,
  union_notified_at      timestamptz,
  status                 text NOT NULL CHECK (status IN ('proposed','approved','in_effect','cancelled')),
  change_set_id          uuid,
  CONSTRAINT probation_extension_notice_method CHECK (employee_notified_at IS NULL OR employee_notice_method IS NOT NULL)
);

CREATE FUNCTION core.check_probation_extension() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE p core.probation; e core.employment; ends date; new_end date; mx jsonb; total numeric;
BEGIN
  SELECT * INTO p FROM core.probation x WHERE x.probation_id = NEW.probation_id AND upper_inf(x.sys_period)
     AND x.status IN ('in_progress','extended') ORDER BY lower(x.valid_period) DESC LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROBATION_NOT_OPEN: probation % is not in progress', NEW.probation_id USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IS NOT DISTINCT FROM (CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END) THEN RETURN NEW; END IF;
  IF NEW.status = 'approved' THEN
    IF NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'probation_extension', NEW.extension_id, NEW.requested_by, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the extension''s route is not complete' USING ERRCODE = 'check_violation';
    END IF;
  ELSIF NEW.status = 'in_effect' THEN
    IF TG_OP = 'INSERT' OR OLD.status <> 'approved' THEN
      RAISE EXCEPTION 'EXTENSION_NOT_APPROVED: an extension takes effect once approved' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.employee_notified_at IS NULL THEN
      RAISE EXCEPTION 'EXTENSION_NOT_COMMUNICATED: the employee is told before the extension takes effect' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.change_set_id IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: an extension takes effect through a change set' USING ERRCODE = 'check_violation';
    END IF;
    total := p.extended_by + NEW.amount;
    SELECT * INTO e FROM core.employment WHERE employment_id = p.employment_id;
    IF p.kind = 'employer' OR (p.kind = 'trial' AND p.agreement_id IS NULL) THEN
      mx := platform.setting(p.tenant_id, 'probation.non_union_extension_max', p.started_on, e.legal_entity_id);
      IF mx ->> 'amount' IS NOT NULL THEN
        IF mx ->> 'measure' <> p.measure THEN
          RAISE EXCEPTION 'EXTENSION_MEASURE_DIFFERS: the maximum is in %, the probation in %', mx ->> 'measure', p.measure USING ERRCODE = 'check_violation';
        END IF;
        IF total > (mx ->> 'amount')::numeric THEN
          RAISE EXCEPTION 'EXTENSION_ABOVE_MAXIMUM: % % in total; the organization allows %', total, p.measure, mx ->> 'amount' USING ERRCODE = 'check_violation';
        END IF;
      END IF;
    ELSE
      IF NEW.agreement_maximum IS NULL THEN
        RAISE EXCEPTION 'INPUT_REQUIRED: an agreement probation''s extension states the agreement''s maximum' USING ERRCODE = 'check_violation';
      END IF;
      IF total > NEW.agreement_maximum THEN
        RAISE EXCEPTION 'EXTENSION_ABOVE_MAXIMUM: % % in total; the agreement allows %', total, p.measure, NEW.agreement_maximum USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    IF p.measure IN ('calendar_days','calendar_months') THEN
      ends := core.probation_calendar_end(p.probation_id, lower(p.valid_period));
      IF NEW.employee_notified_at::date > ends THEN
        RAISE EXCEPTION 'EXTENSION_AFTER_END: probation ended on %; the employee was told on %', ends, NEW.employee_notified_at::date
          USING ERRCODE = 'check_violation';
      END IF;
      new_end := CASE p.measure WHEN 'calendar_months' THEN (p.started_on + make_interval(months => (p.required_amount + total)::int))::date - 1
                                ELSE p.started_on + (p.required_amount + total)::int - 1 END;
    END IF;
    -- Extending does not delay the law's notice rights: past that date the manager has acknowledged the caution
    IF (new_end IS NULL OR new_end > ref.notice_threshold_date(NEW.jurisdiction, p.started_on))
       AND NOT platform.caution_cleared(NEW.tenant_id, 'probation.extension_past_notice_threshold', 'probation_extension', NEW.extension_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: probation.extension_past_notice_threshold must be acknowledged' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER probation_extension_check BEFORE INSERT OR UPDATE ON core.probation_extension
  FOR EACH ROW EXECUTE FUNCTION core.check_probation_extension();

-- When an extension takes effect, the probation gets a new version with the longer period
CREATE FUNCTION core.apply_probation_extension() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE r core.probation;
BEGIN
  SELECT * INTO r FROM core.probation x WHERE x.probation_id = NEW.probation_id AND upper_inf(x.sys_period)
     AND x.status IN ('in_progress','extended') ORDER BY lower(x.valid_period) DESC LIMIT 1;
  UPDATE core.probation SET sys_period = tstzrange(lower(sys_period), now()) WHERE version_id = r.version_id;
  INSERT INTO core.probation (tenant_id, probation_id, employment_id, kind, agreement_id, bargaining_unit, assignment_id, measure,
                              required_amount, counter_code, started_on, extended_by, status, outcome_on, reason, rule_source,
                              valid_period, change_set_id)
  VALUES (r.tenant_id, r.probation_id, r.employment_id, r.kind, r.agreement_id, r.bargaining_unit, r.assignment_id, r.measure,
          r.required_amount, r.counter_code, r.started_on, r.extended_by + NEW.amount, 'extended', NULL, NEW.reason, r.rule_source,
          r.valid_period, NEW.change_set_id);
  RETURN NULL;
END $$;
CREATE TRIGGER probation_extension_apply AFTER UPDATE OF status ON core.probation_extension
  FOR EACH ROW WHEN (NEW.status = 'in_effect' AND OLD.status IS DISTINCT FROM 'in_effect') EXECUTE FUNCTION core.apply_probation_extension();

-- A leave that falls near the end of a probation: the approver sees a caution (probation.leave_near_end) before
-- approving. Used for the probationary employee's own leave and for their manager's leave in the same window.
-- A probation counted in hours, days or shifts is always shown, since the leave may move its end (docs/23 §7.3).
CREATE FUNCTION core.probation_leave_caution(p_employment uuid, p_leave daterange, p_as_of date)
RETURNS TABLE (probation_id uuid, ends_on date, window_from date, holidays date[]) LANGUAGE plpgsql STABLE AS $$
DECLARE p record; reminders jsonb; widest int; jur text[];
BEGIN
  FOR p IN SELECT x.*, e.legal_entity_id FROM core.probation x JOIN core.employment e ON e.employment_id = x.employment_id
            WHERE x.employment_id = p_employment AND x.valid_period @> p_as_of AND upper_inf(x.sys_period)
              AND x.status IN ('in_progress','extended') LOOP
    reminders := platform.setting(p.tenant_id, 'probation.end_reminders_days', p_as_of, p.legal_entity_id);
    SELECT max(v::int) INTO widest FROM jsonb_array_elements_text(reminders) v;
    IF widest IS NULL THEN
      RAISE EXCEPTION 'SETTING_VALUE_NOT_ALLOWED: probation.end_reminders_days lists no day, so no decision window can be worked out'
        USING ERRCODE = 'check_violation';
    END IF;
    IF p.measure IN ('calendar_days','calendar_months') THEN
      ends_on := core.probation_calendar_end(p.probation_id, p_as_of);
      window_from := ends_on - widest;
      CONTINUE WHEN NOT (p_leave && daterange(window_from, ends_on, '[]'));
    ELSE
      ends_on := NULL; window_from := NULL;
    END IF;
    jur := ARRAY(SELECT DISTINCT lv.holiday_jurisdiction::text
                   FROM core.assignment a
                   JOIN core.assignment_version av ON av.assignment_id = a.assignment_id AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
                   JOIN core.location_version lv ON lv.location_id = av.location_id AND lv.valid_period @> p_as_of AND upper_inf(lv.sys_period)
                  WHERE a.employment_id = p_employment AND lv.holiday_jurisdiction IS NOT NULL);
    IF cardinality(jur) = 0 THEN
      RAISE EXCEPTION 'HOLIDAY_CALENDAR_MISSING: no work location of employment % names its holiday calendar', p_employment
        USING ERRCODE = 'check_violation';
    END IF;
    holidays := ARRAY(SELECT DISTINCT h.observed_date FROM ref.holiday h
                       WHERE h.jurisdiction::text = ANY (jur) AND h.statutory
                         AND h.observed_date <@ CASE WHEN ends_on IS NULL THEN p_leave ELSE daterange(window_from, ends_on, '[]') END
                       ORDER BY 1);
    probation_id := p.probation_id;
    RETURN NEXT;
  END LOOP;
END $$;

-- -------------------------------------------------------------------------------------
-- 11. Open cases before an ending (docs/23 §7.5). Before probation is failed or employment ends, any open case or
--     leave of the employee is reviewed by an HR approver, who acknowledges the caution endings.open_cases.
-- -------------------------------------------------------------------------------------
UPDATE ref.list_definition SET categories = categories || ARRAY['complaint','discipline'] WHERE list_code = 'case_kind';
INSERT INTO ref.list_starter (list_code, code, category, rank, name_en, name_fr, attributes) VALUES
 ('case_kind', 'complaint',  'complaint',  9, 'Complaint (human rights, employment standards, harassment)',
  'Plainte (droits de la personne, normes du travail, harcèlement)', '{}'),
 ('case_kind', 'discipline', 'discipline', 10, 'Warning letter or discipline', 'Lettre d''avertissement ou mesure disciplinaire', '{}');

-- Who is involved in a case, beyond its subject: a complaint against a manager names the manager as respondent
CREATE TABLE compliance.case_party (
  tenant_id     uuid NOT NULL,
  case_id       uuid NOT NULL REFERENCES compliance.case_file,
  employment_id uuid NOT NULL REFERENCES core.employment,
  role          text NOT NULL CHECK (role IN ('subject','complainant','respondent','witness','representative')),
  PRIMARY KEY (case_id, employment_id, role)
);

-- An employee's open matters on a date: cases they are the subject of or brought, open or closed within the
-- organization's look-back (endings.closed_case_lookback_months), and leave requested, approved or under way
CREATE FUNCTION core.open_matters(p_employment uuid, p_as_of date)
RETURNS TABLE (source text, ref_id uuid, category text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT CASE WHEN c.closed_on IS NULL OR c.closed_on > p_as_of THEN 'case' ELSE 'closed_case' END, c.case_id, lv.category
    FROM compliance.case_file c
    JOIN core.employment e ON e.employment_id = p_employment
    JOIN core.list_value lv ON lv.tenant_id = c.tenant_id AND lv.list_code = 'case_kind' AND lv.code = c.kind
   WHERE c.opened_on <= p_as_of
     AND (c.closed_on IS NULL OR c.closed_on > p_as_of
          OR c.closed_on > (p_as_of - make_interval(months => platform.setting_number(e.tenant_id, 'endings.closed_case_lookback_months',
                                                                                     p_as_of, e.legal_entity_id)::int))::date)
     AND (c.subject_employment_id = p_employment
          OR EXISTS (SELECT 1 FROM compliance.case_party cp WHERE cp.case_id = c.case_id AND cp.employment_id = p_employment
                       AND cp.role IN ('subject','complainant')))
  UNION ALL
  SELECT 'leave', l.leave_request_id, 'leave'
    FROM timeleave.leave_request l
   WHERE l.employment_id = p_employment AND l.status IN ('requested','approved','taken') AND upper(l.period)::date >= p_as_of
$$;

-- What a viewer is told about an employee's open matters: nothing, or only that HR must review when the viewer is a
-- respondent in one of them (a complaint against the manager); details are for HR only
CREATE FUNCTION core.viewer_is_case_respondent(p_employment uuid, p_viewer_person uuid, p_as_of date) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT EXISTS (
    SELECT 1 FROM core.open_matters(p_employment, p_as_of) m
      JOIN compliance.case_party cp ON cp.case_id = m.ref_id AND cp.role = 'respondent'
      JOIN core.employment e ON e.employment_id = cp.employment_id
     WHERE m.source IN ('case','closed_case') AND e.person_id = p_viewer_person)
$$;

CREATE FUNCTION platform.check_ending_open_matters() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE emp uuid; n int;
BEGIN
  IF NEW.status NOT IN ('approved','scheduled','committed') OR NEW.source = 'import' OR NEW.reason_category IS DISTINCT FROM 'termination' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IN ('approved','scheduled','committed') THEN RETURN NEW; END IF;
  IF NOT platform.setting(NEW.tenant_id, 'endings.open_case_review', NEW.effective_date)::boolean THEN RETURN NEW; END IF;
  FOR emp IN SELECT DISTINCT coalesce(CASE WHEN o.target_type = 'employment' THEN o.target_id END, a.employment_id)
               FROM platform.change_set_operation o
               LEFT JOIN core.assignment a ON o.target_type = 'assignment' AND a.assignment_id = o.target_id
              WHERE o.change_set_id = NEW.change_set_id AND o.target_type IN ('employment','assignment') LOOP
    CONTINUE WHEN emp IS NULL;
    SELECT count(*) INTO n FROM core.open_matters(emp, NEW.effective_date);
    IF n > 0 AND NOT EXISTS (
         SELECT 1 FROM platform.caution_acknowledgement k
           JOIN platform.approval_task t ON t.subject_type = 'change_set' AND t.subject_id = NEW.change_set_id
                                        AND t.capability = 'hr' AND t.status = 'approved' AND t.decided_by = k.acknowledged_by
          WHERE k.tenant_id = NEW.tenant_id AND k.caution_code = 'endings.open_cases'
            AND k.subject_type = 'change_set' AND k.subject_id = NEW.change_set_id) THEN
      RAISE EXCEPTION 'OPEN_CASES_NOT_REVIEWED: the employee has % open case(s) or leave; an HR approver acknowledges endings.open_cases first', n
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER change_set_3_open_matters BEFORE INSERT OR UPDATE OF status ON platform.change_set
  FOR EACH ROW EXECUTE FUNCTION platform.check_ending_open_matters();

-- -------------------------------------------------------------------------------------
-- 12. Status conversion (docs/23 §8): starts when a manager asks; organizations can add thresholds; a conversion a
--     collective agreement requires is always flagged to HR, and declining it needs the caution and a reason
-- -------------------------------------------------------------------------------------
CREATE TABLE core.status_conversion_request (
  tenant_id          uuid NOT NULL,
  request_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id      uuid NOT NULL REFERENCES core.employment,
  assignment_id      uuid NOT NULL REFERENCES core.assignment,
  to_employment_type text NOT NULL,                        -- the organization's employment type (list employment_type)
  started_by         text NOT NULL CHECK (started_by IN ('manager_request','threshold','agreement')),
  rule_source        text,                                 -- the threshold rule or the agreement clause that flagged it
  requested_by       uuid REFERENCES platform.app_user,
  route_id           uuid REFERENCES platform.workflow_route,
  status             text NOT NULL CHECK (status IN ('flagged','requested','approved','declined','completed','cancelled')),
  reason             text,
  change_set_id      uuid,
  CONSTRAINT conversion_rule_named CHECK (started_by = 'manager_request' OR rule_source IS NOT NULL),
  CONSTRAINT conversion_manager_named CHECK (started_by <> 'manager_request' OR requested_by IS NOT NULL)
);
CREATE TRIGGER a01_list_values BEFORE INSERT OR UPDATE ON core.status_conversion_request
  FOR EACH ROW EXECUTE FUNCTION core.check_list_values('to_employment_type', 'employment_type');

CREATE FUNCTION core.check_status_conversion() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE e core.employment;
BEGIN
  SELECT * INTO e FROM core.employment WHERE employment_id = NEW.employment_id;
  IF TG_OP = 'INSERT' AND NEW.started_by = 'threshold'
     AND NOT (platform.setting(NEW.tenant_id, 'conversion.thresholds', current_date, e.legal_entity_id) ->> 'enabled')::boolean THEN
    RAISE EXCEPTION 'CONVERSION_THRESHOLDS_OFF: the organization has not set conversion thresholds' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IS NOT DISTINCT FROM (CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END) THEN RETURN NEW; END IF;
  IF NEW.status = 'approved'
     AND (NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'status_conversion', NEW.request_id, NEW.requested_by, NULL)) THEN
    RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the conversion''s route is not complete' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status IN ('declined','cancelled') AND NEW.started_by = 'agreement' THEN
    IF NEW.reason IS NULL OR NOT platform.caution_cleared(NEW.tenant_id, 'conversion.agreement_requires', 'status_conversion', NEW.request_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: the agreement requires this conversion; conversion.agreement_requires and a reason are needed'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER status_conversion_check BEFORE INSERT OR UPDATE ON core.status_conversion_request
  FOR EACH ROW EXECUTE FUNCTION core.check_status_conversion();

-- No one approves their own request from any position, on every routed subject (docs/21 §2.2, AGENTS rule 37)
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
  END IF;
  IF NEW.decided_by = requester THEN
    RAISE EXCEPTION 'SELF_APPROVAL: the requester cannot approve their own %', replace(NEW.subject_type, '_', ' ') USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- -------------------------------------------------------------------------------------
-- 13. Text fields of the new tables registered as translatable (as 0008 §9 did for the earlier tables): required
--     text is checked at commit in the organization's main language, whichever it is; row-level security.
-- -------------------------------------------------------------------------------------
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

-- Business columns that start from a setting or the organization's main language (0008 §2)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('recruit','posting','audience','setting','recruit.posting_audience'),
      ('recruit','posting','pay_shown','setting','recruit.posting_pay_shown'),
      ('recruit','posting','pay_basis','setting','recruit.posting_pay_basis'),
      ('recruit','posting','missing_requirement','setting','recruit.missing_requirement'),
      ('recruit','posting','seniority_applies','setting','recruit.apply_agreement_seniority'),
      ('recruit','posting','lang','tenant_main_language',NULL)
    ) AS x(s, t, c, src, k)
  LOOP
    INSERT INTO platform.column_default (table_schema, table_name, column_name, source, setting_key) VALUES (r.s, r.t, r.c, r.src, r.k);
  END LOOP;
END $$;
CREATE TRIGGER a00_fill_from_settings BEFORE INSERT ON recruit.posting FOR EACH ROW EXECUTE FUNCTION platform.fill_from_settings();

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('platform','caution_acknowledgement'), ('platform','workflow_route'), ('platform','workflow_route_step'),
      ('recruit','requisition_funding'), ('recruit','posting_exemption_rule'), ('recruit','posting'), ('recruit','posting_channel'),
      ('recruit','posting_question'), ('recruit','application_answer'), ('recruit','interview'), ('recruit','interview_score'),
      ('recruit','message_template'), ('recruit','message_batch'), ('recruit','offer_condition'), ('recruit','onboarding_plan'),
      ('recruit','onboarding_plan_item'), ('recruit','onboarding_support'), ('core','probation_check_in'), ('core','probation_extension'),
      ('compliance','case_party'), ('core','status_conversion_request')) AS x(s, t) LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$, r.s, r.t);
  END LOOP;
END $$;

-- -------------------------------------------------------------------------------------
-- 14. Starter data each organization copies and edits: posting channels, approval routes, onboarding plans
--     (docs/23 §2.2, §4.1, §6.3). Generated from the review's decisions; organizations change them at any time.
-- -------------------------------------------------------------------------------------
INSERT INTO ref.list_definition (list_code, name_en, name_fr, categories, decision_ref) VALUES
 ('posting_channel', 'Posting channels', 'Canaux d''affichage',
  ARRAY['partner_job_board','career_page','google','indeed_free','professional_body','other'], 'docs/23 §4.1 (R3.5)');
INSERT INTO ref.list_starter (list_code, code, category, rank, name_en, name_fr, attributes) VALUES
 ('posting_channel', 'partner_job_board', 'partner_job_board', 1, 'Job boards through CanDo''s posting partner', 'Sites d''emploi par le partenaire d''affichage de CanDo', '{}'),
 ('posting_channel', 'career_page', 'career_page', 2, 'Our career page', 'Notre page Carrières', '{}'),
 ('posting_channel', 'google', 'google', 3, 'Google for Jobs', 'Google pour les emplois', '{}'),
 ('posting_channel', 'indeed_free', 'indeed_free', 4, 'Indeed free listing', 'Offre gratuite sur Indeed', '{}'),
 ('posting_channel', 'professional_body', 'professional_body', 5, 'Professional and regulatory bodies', 'Ordres et associations professionnels', '{}'),
 ('posting_channel', 'other', 'other', 6, 'Other', 'Autre', '{}');

CREATE TABLE ref.workflow_route_starter (
  code         text PRIMARY KEY,
  subject_type text NOT NULL,
  name_en      text NOT NULL,
  name_fr      text NOT NULL,
  conditions   jsonb NOT NULL,
  priority     smallint NOT NULL,
  decision_ref text NOT NULL
);
CREATE TABLE ref.workflow_route_step_starter (
  route_code    text NOT NULL REFERENCES ref.workflow_route_starter,
  step_no       smallint NOT NULL,
  approver_kind text NOT NULL,
  capability    text,
  mode          text NOT NULL,
  min_approvals smallint NOT NULL,
  purpose_en    text NOT NULL,
  purpose_fr    text NOT NULL,
  PRIMARY KEY (route_code, step_no)
);
INSERT INTO ref.workflow_route_starter (code, subject_type, name_en, name_fr, conditions, priority, decision_ref) VALUES
 ('req_over_budget', 'requisition', 'Requisition over budget', 'Demande de dotation hors budget', '{"overBudget":true}', 10, 'docs/23 §3.4 (R2.1, R2.3)'),
 ('req_additional_headcount', 'requisition', 'Additional headcount', 'Effectif supplémentaire', '{"requisitionTypes":["additional_headcount"]}', 20, 'docs/23 §3.4 (R2.1, R2.3)'),
 ('req_new_position', 'requisition', 'New position', 'Nouveau poste', '{"requisitionTypes":["new_position"]}', 30, 'docs/23 §3.4 (R2.1, R2.3)'),
 ('req_replacement', 'requisition', 'Replacement', 'Remplacement', '{"requisitionTypes":["replacement"]}', 40, 'docs/23 §3.4 (R2.1, R2.3)'),
 ('direct_hire', 'direct_hire', 'Direct hire without a requisition', 'Embauche directe sans demande de dotation', '{}', 10, 'docs/23 §3.1 (R2.7)'),
 ('offer_outside_range', 'offer', 'Offer outside the range or step', 'Offre hors de l''échelle ou de l''échelon', '{"outsideRange":true}', 10, 'docs/23 §5.1 (R5.1)'),
 ('offer_standard', 'offer', 'Offer', 'Offre', '{}', 20, 'docs/23 §5.1 (R5.1)'),
 ('probation_extension', 'probation_extension', 'Probation extension', 'Prolongation du stage', '{}', 10, 'docs/23 §7.4 (R7.3)'),
 ('status_conversion', 'status_conversion', 'Conversion to regular status', 'Conversion au statut régulier', '{}', 10, 'docs/23 §8 (R7.5)');
INSERT INTO ref.workflow_route_step_starter (route_code, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr) VALUES
 ('req_over_budget', 1, 'unit_head', NULL, 'any', 1, 'Department head', 'Chef du service'),
 ('req_over_budget', 2, 'capability', 'hr', 'any', 1, 'Job description and pay grade', 'Description d''emploi et classe salariale'),
 ('req_over_budget', 3, 'capability', 'finance', 'any', 1, 'Budget, with the written reason', 'Budget, avec la raison écrite'),
 ('req_additional_headcount', 1, 'unit_head', NULL, 'any', 1, 'Department head', 'Chef du service'),
 ('req_additional_headcount', 2, 'capability', 'hr', 'any', 1, 'Job description and pay grade', 'Description d''emploi et classe salariale'),
 ('req_additional_headcount', 3, 'capability', 'finance', 'any', 1, 'Budget', 'Budget'),
 ('req_additional_headcount', 4, 'capability', 'executive', 'any', 1, 'Headcount', 'Effectif'),
 ('req_new_position', 1, 'unit_head', NULL, 'any', 1, 'Department head', 'Chef du service'),
 ('req_new_position', 2, 'capability', 'hr', 'any', 1, 'Job description and pay grade', 'Description d''emploi et classe salariale'),
 ('req_new_position', 3, 'capability', 'finance', 'any', 1, 'Budget', 'Budget'),
 ('req_replacement', 1, 'capability', 'hr', 'any', 1, 'Replacement of the same position', 'Remplacement au même poste'),
 ('direct_hire', 1, 'unit_head', NULL, 'any', 1, 'Department head', 'Chef du service'),
 ('direct_hire', 2, 'capability', 'hr', 'any', 1, 'Reason for hiring without a requisition', 'Raison de l''embauche sans demande de dotation'),
 ('offer_outside_range', 1, 'capability', 'hr', 'any', 1, 'Offer terms', 'Conditions de l''offre'),
 ('offer_outside_range', 2, 'capability', 'finance', 'any', 1, 'Pay outside the range or step', 'Salaire hors de l''échelle ou de l''échelon'),
 ('offer_standard', 1, 'capability', 'hr', 'any', 1, 'Offer terms', 'Conditions de l''offre'),
 ('probation_extension', 1, 'capability', 'hr', 'any', 1, 'Extension and its reason', 'Prolongation et sa raison'),
 ('status_conversion', 1, 'capability', 'hr', 'any', 1, 'Policy and agreement', 'Politique et convention'),
 ('status_conversion', 2, 'capability', 'finance', 'any', 1, 'Budget', 'Budget');

CREATE TABLE ref.onboarding_plan_starter (
  code       text PRIMARY KEY,
  hire_kind  text NOT NULL,
  name_en    text NOT NULL,
  name_fr    text NOT NULL,
  applies_to jsonb NOT NULL
);
CREATE TABLE ref.onboarding_plan_item_starter (
  plan_code       text NOT NULL REFERENCES ref.onboarding_plan_starter,
  item_code       text NOT NULL,
  seq             smallint NOT NULL,
  phase           text NOT NULL,
  kind            text NOT NULL,
  form_code       text,
  owner_kind      text NOT NULL,
  due_event       text NOT NULL,
  due_offset_days smallint NOT NULL,
  depends_on      text,
  required        boolean NOT NULL,
  extra           text,
  name_en         text NOT NULL,
  name_fr         text NOT NULL,
  PRIMARY KEY (plan_code, item_code)
);
INSERT INTO ref.onboarding_plan_starter (code, hire_kind, name_en, name_fr, applies_to) VALUES
 ('core_new_hire', 'new_hire', 'New hire: everyone', 'Nouvel employé : tout le personnel', '{}'),
 ('core_rehire', 'rehire', 'Rehire: everyone', 'Réembauche : tout le personnel', '{}'),
 ('core_internal_transfer', 'internal_transfer', 'Internal transfer: everyone', 'Mutation interne : tout le personnel', '{}'),
 ('core_student', 'student', 'Student: everyone', 'Étudiant : tout le personnel', '{}'),
 ('core_contractor', 'contractor', 'Contractor: everyone', 'Entrepreneur : tout le personnel', '{}');
INSERT INTO ref.onboarding_plan_item_starter (plan_code, item_code, seq, phase, kind, form_code, owner_kind, due_event, due_offset_days, depends_on, required, extra, name_en, name_fr) VALUES
 ('core_new_hire', 'sin', 1, 'pre_boarding', 'form', 'sin', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Social insurance number', 'Numéro d''assurance sociale'),
 ('core_new_hire', 'td1_federal', 2, 'pre_boarding', 'form', 'td1_federal', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Federal TD1 personal tax credits return', 'Déclaration fédérale des crédits d''impôt personnels (TD1)'),
 ('core_new_hire', 'provincial_tax_form', 3, 'pre_boarding', 'form', 'provincial_tax_form', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Provincial tax credits form (the province''s TD1, or TP-1015.3 in Quebec)', 'Formulaire provincial des crédits d''impôt (TD1 de la province, ou TP-1015.3 au Québec)'),
 ('core_new_hire', 'direct_deposit', 4, 'pre_boarding', 'form', 'direct_deposit', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Direct deposit banking details', 'Renseignements bancaires pour le dépôt direct'),
 ('core_new_hire', 'emergency_contact', 5, 'pre_boarding', 'form', 'emergency_contact', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Emergency contacts', 'Personnes à joindre en cas d''urgence'),
 ('core_new_hire', 'work_authorization', 6, 'pre_boarding', 'form', 'work_authorization', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Proof of the right to work in Canada', 'Preuve du droit de travailler au Canada'),
 ('core_new_hire', 's87_declaration', 7, 'pre_boarding', 'form', 's87_declaration', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Indian Act s. 87 tax exemption: do you claim it?', 'Exemption fiscale de l''article 87 de la Loi sur les Indiens : la demandez-vous?'),
 ('core_new_hire', 'policy_acknowledgement', 8, 'pre_boarding', 'form', 'policy_acknowledgement', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Read and acknowledge workplace policies', 'Lire et accepter les politiques du milieu de travail'),
 ('core_new_hire', 'self_identification', 9, 'pre_boarding', 'form', 'self_identification', 'new_hire', 'start_date', 0, NULL, false, NULL, 'Voluntary self-identification (optional)', 'Auto-identification volontaire (facultative)'),
 ('core_new_hire', 'welcome_videos', 10, 'pre_boarding', 'video', NULL, 'new_hire', 'start_date', 0, NULL, false, 'welcomeVideos', 'Welcome videos', 'Vidéos de bienvenue'),
 ('core_new_hire', 'personnel_file', 11, 'pre_boarding', 'task', NULL, 'hr', 'start_date', -1, NULL, true, NULL, 'Open the personnel file', 'Ouvrir le dossier de l''employé'),
 ('core_new_hire', 'payroll_setup', 12, 'onboarding', 'task', NULL, 'payroll', 'first_pay', -2, 'td1_federal', true, NULL, 'Set up payroll and check the TD1 forms and banking before the first pay', 'Configurer la paie et vérifier les formulaires TD1 et les renseignements bancaires avant la première paie'),
 ('core_new_hire', 'it_accounts', 13, 'pre_boarding', 'access', NULL, 'it', 'start_date', -2, NULL, true, NULL, 'Accounts and system access', 'Comptes et accès aux systèmes'),
 ('core_new_hire', 'it_equipment', 14, 'pre_boarding', 'equipment', NULL, 'it', 'start_date', -2, NULL, true, NULL, 'Computer and equipment', 'Ordinateur et équipement'),
 ('core_new_hire', 'workspace', 15, 'pre_boarding', 'equipment', NULL, 'facilities', 'start_date', -1, NULL, true, NULL, 'Workspace and supplies', 'Poste de travail et fournitures'),
 ('core_new_hire', 'building_access', 16, 'pre_boarding', 'access', NULL, 'facilities', 'start_date', -1, NULL, true, NULL, 'Building access card', 'Carte d''accès à l''immeuble'),
 ('core_new_hire', 'first_week_plan', 17, 'pre_boarding', 'task', NULL, 'hiring_manager', 'start_date', -3, NULL, true, NULL, 'First-week schedule', 'Horaire de la première semaine'),
 ('core_new_hire', 'choose_supporters', 18, 'pre_boarding', 'task', NULL, 'hiring_manager', 'start_date', -5, NULL, false, 'buddyProgram', 'Choose buddies and mentors', 'Choisir des parrains, marraines et mentors'),
 ('core_new_hire', 'team_introductions', 19, 'onboarding', 'meeting', NULL, 'hiring_manager', 'start_date', 0, NULL, true, NULL, 'Team introductions', 'Présentation à l''équipe'),
 ('core_new_hire', 'orientation', 20, 'onboarding', 'orientation', NULL, 'hr', 'start_date', 10, NULL, true, NULL, 'Organization orientation', 'Séance d''orientation de l''organisation'),
 ('core_new_hire', 'required_training', 21, 'onboarding', 'training', NULL, 'learning', 'start_date', 30, NULL, true, NULL, 'Required training for the role', 'Formation obligatoire pour le poste'),
 ('core_new_hire', 'confidentiality', 22, 'pre_boarding', 'document', NULL, 'security', 'start_date', 0, NULL, false, NULL, 'Confidentiality agreement, where the role needs one', 'Entente de confidentialité, si le poste l''exige'),
 ('core_new_hire', 'announcement', 23, 'onboarding', 'task', NULL, 'communications', 'start_date', 0, NULL, false, NULL, 'Announce the new team member', 'Annoncer l''arrivée du nouveau membre'),
 ('core_new_hire', 'benefits_enrolment', 24, 'onboarding', 'form', 'benefits_enrolment', 'new_hire', 'benefits_start', 0, NULL, true, NULL, 'Benefits enrolment', 'Adhésion aux avantages sociaux'),
 ('core_new_hire', 'check_in_survey', 25, 'onboarding', 'survey', NULL, 'new_hire', 'start_date', 30, NULL, false, 'checkInSurveys', 'Check-in survey', 'Sondage de suivi'),
 ('core_rehire', 'td1_federal', 1, 'pre_boarding', 'form', 'td1_federal', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Federal TD1 personal tax credits return', 'Déclaration fédérale des crédits d''impôt personnels (TD1)'),
 ('core_rehire', 'provincial_tax_form', 2, 'pre_boarding', 'form', 'provincial_tax_form', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Provincial tax credits form (the province''s TD1, or TP-1015.3 in Quebec)', 'Formulaire provincial des crédits d''impôt (TD1 de la province, ou TP-1015.3 au Québec)'),
 ('core_rehire', 'direct_deposit', 3, 'pre_boarding', 'form', 'direct_deposit', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Direct deposit banking details', 'Renseignements bancaires pour le dépôt direct'),
 ('core_rehire', 'emergency_contact', 4, 'pre_boarding', 'form', 'emergency_contact', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Emergency contacts', 'Personnes à joindre en cas d''urgence'),
 ('core_rehire', 'policy_acknowledgement', 5, 'pre_boarding', 'form', 'policy_acknowledgement', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Read and acknowledge workplace policies', 'Lire et accepter les politiques du milieu de travail'),
 ('core_rehire', 'personnel_file', 6, 'pre_boarding', 'task', NULL, 'hr', 'start_date', -1, NULL, true, NULL, 'Open the personnel file', 'Ouvrir le dossier de l''employé'),
 ('core_rehire', 'payroll_setup', 7, 'onboarding', 'task', NULL, 'payroll', 'first_pay', -2, 'td1_federal', true, NULL, 'Set up payroll and check the TD1 forms and banking before the first pay', 'Configurer la paie et vérifier les formulaires TD1 et les renseignements bancaires avant la première paie'),
 ('core_rehire', 'it_accounts', 8, 'pre_boarding', 'access', NULL, 'it', 'start_date', -2, NULL, true, NULL, 'Accounts and system access', 'Comptes et accès aux systèmes'),
 ('core_rehire', 'it_equipment', 9, 'pre_boarding', 'equipment', NULL, 'it', 'start_date', -2, NULL, true, NULL, 'Computer and equipment', 'Ordinateur et équipement'),
 ('core_rehire', 'building_access', 10, 'pre_boarding', 'access', NULL, 'facilities', 'start_date', -1, NULL, true, NULL, 'Building access card', 'Carte d''accès à l''immeuble'),
 ('core_rehire', 'team_introductions', 11, 'onboarding', 'meeting', NULL, 'hiring_manager', 'start_date', 0, NULL, true, NULL, 'Team introductions', 'Présentation à l''équipe'),
 ('core_rehire', 'orientation_refresher', 12, 'onboarding', 'orientation', NULL, 'hr', 'start_date', 10, NULL, false, NULL, 'Orientation refresher', 'Séance de mise à jour de l''orientation'),
 ('core_rehire', 'benefits_enrolment', 13, 'onboarding', 'form', 'benefits_enrolment', 'new_hire', 'benefits_start', 0, NULL, true, NULL, 'Benefits enrolment', 'Adhésion aux avantages sociaux'),
 ('core_internal_transfer', 'handover', 1, 'pre_boarding', 'task', NULL, 'hiring_manager', 'start_date', -5, NULL, true, NULL, 'Handover with the previous manager', 'Passation avec le gestionnaire précédent'),
 ('core_internal_transfer', 'access_changes', 2, 'pre_boarding', 'access', NULL, 'it', 'start_date', -1, NULL, true, NULL, 'Change system access for the new role', 'Modifier les accès aux systèmes pour le nouveau poste'),
 ('core_internal_transfer', 'provincial_tax_form_if_moving', 3, 'pre_boarding', 'form', 'provincial_tax_form', 'new_hire', 'start_date', 0, NULL, false, NULL, 'New provincial tax form if the work province changes', 'Nouveau formulaire provincial d''impôt si la province de travail change'),
 ('core_internal_transfer', 'team_introductions', 4, 'onboarding', 'meeting', NULL, 'hiring_manager', 'start_date', 0, NULL, true, NULL, 'Team introductions', 'Présentation à l''équipe'),
 ('core_internal_transfer', 'required_training', 5, 'onboarding', 'training', NULL, 'learning', 'start_date', 30, NULL, true, NULL, 'Required training for the role', 'Formation obligatoire pour le poste'),
 ('core_internal_transfer', 'it_equipment', 6, 'pre_boarding', 'equipment', NULL, 'it', 'start_date', -2, NULL, false, NULL, 'Computer and equipment', 'Ordinateur et équipement'),
 ('core_student', 'sin', 1, 'pre_boarding', 'form', 'sin', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Social insurance number', 'Numéro d''assurance sociale'),
 ('core_student', 'td1_federal', 2, 'pre_boarding', 'form', 'td1_federal', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Federal TD1 personal tax credits return', 'Déclaration fédérale des crédits d''impôt personnels (TD1)'),
 ('core_student', 'provincial_tax_form', 3, 'pre_boarding', 'form', 'provincial_tax_form', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Provincial tax credits form (the province''s TD1, or TP-1015.3 in Quebec)', 'Formulaire provincial des crédits d''impôt (TD1 de la province, ou TP-1015.3 au Québec)'),
 ('core_student', 'direct_deposit', 4, 'pre_boarding', 'form', 'direct_deposit', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Direct deposit banking details', 'Renseignements bancaires pour le dépôt direct'),
 ('core_student', 'emergency_contact', 5, 'pre_boarding', 'form', 'emergency_contact', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Emergency contacts', 'Personnes à joindre en cas d''urgence'),
 ('core_student', 'work_authorization', 6, 'pre_boarding', 'form', 'work_authorization', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Proof of the right to work in Canada', 'Preuve du droit de travailler au Canada'),
 ('core_student', 's87_declaration', 7, 'pre_boarding', 'form', 's87_declaration', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Indian Act s. 87 tax exemption: do you claim it?', 'Exemption fiscale de l''article 87 de la Loi sur les Indiens : la demandez-vous?'),
 ('core_student', 'policy_acknowledgement', 8, 'pre_boarding', 'form', 'policy_acknowledgement', 'new_hire', 'start_date', 0, NULL, true, NULL, 'Read and acknowledge workplace policies', 'Lire et accepter les politiques du milieu de travail'),
 ('core_student', 'self_identification', 9, 'pre_boarding', 'form', 'self_identification', 'new_hire', 'start_date', 0, NULL, false, NULL, 'Voluntary self-identification (optional)', 'Auto-identification volontaire (facultative)'),
 ('core_student', 'school_paperwork', 10, 'pre_boarding', 'document', NULL, 'hr', 'start_date', 0, NULL, false, NULL, 'School or co-op paperwork', 'Documents de l''établissement d''enseignement ou du stage coopératif'),
 ('core_student', 'personnel_file', 11, 'pre_boarding', 'task', NULL, 'hr', 'start_date', -1, NULL, true, NULL, 'Open the personnel file', 'Ouvrir le dossier de l''employé'),
 ('core_student', 'payroll_setup', 12, 'onboarding', 'task', NULL, 'payroll', 'first_pay', -2, 'td1_federal', true, NULL, 'Set up payroll and check the TD1 forms and banking before the first pay', 'Configurer la paie et vérifier les formulaires TD1 et les renseignements bancaires avant la première paie'),
 ('core_student', 'it_accounts', 13, 'pre_boarding', 'access', NULL, 'it', 'start_date', -2, NULL, true, NULL, 'Accounts and system access', 'Comptes et accès aux systèmes'),
 ('core_student', 'building_access', 14, 'pre_boarding', 'access', NULL, 'facilities', 'start_date', -1, NULL, true, NULL, 'Building access card', 'Carte d''accès à l''immeuble'),
 ('core_student', 'team_introductions', 15, 'onboarding', 'meeting', NULL, 'hiring_manager', 'start_date', 0, NULL, true, NULL, 'Team introductions', 'Présentation à l''équipe'),
 ('core_student', 'orientation', 16, 'onboarding', 'orientation', NULL, 'hr', 'start_date', 10, NULL, true, NULL, 'Organization orientation', 'Séance d''orientation de l''organisation'),
 ('core_student', 'required_training', 17, 'onboarding', 'training', NULL, 'learning', 'start_date', 30, NULL, true, NULL, 'Required training for the role', 'Formation obligatoire pour le poste'),
 ('core_contractor', 'service_contract', 1, 'pre_boarding', 'document', NULL, 'hr', 'contract_signed', 0, NULL, true, NULL, 'Signed service contract', 'Contrat de service signé'),
 ('core_contractor', 'confidentiality', 2, 'pre_boarding', 'document', NULL, 'security', 'start_date', 0, NULL, true, NULL, 'Confidentiality agreement, where the role needs one', 'Entente de confidentialité, si le poste l''exige'),
 ('core_contractor', 'it_accounts', 3, 'pre_boarding', 'access', NULL, 'it', 'start_date', -2, NULL, false, NULL, 'Accounts and system access', 'Comptes et accès aux systèmes'),
 ('core_contractor', 'building_access', 4, 'pre_boarding', 'access', NULL, 'facilities', 'start_date', -1, NULL, false, NULL, 'Building access card', 'Carte d''accès à l''immeuble'),
 ('core_contractor', 'orientation', 5, 'onboarding', 'orientation', NULL, 'hr', 'start_date', 10, NULL, false, NULL, 'Organization orientation', 'Séance d''orientation de l''organisation');

-- Every organization gets the starter lists, routes and plans when it is created (and existing organizations now);
-- they are its own copies from then on
CREATE OR REPLACE FUNCTION core.seed_tenant(p_tenant uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog AS $$
DECLARE l jsonb;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM platform.tenant_language WHERE tenant_id = p_tenant) THEN
    FOR l IN SELECT jsonb_array_elements(platform.setting(p_tenant, 'languages.starter') -> 'languages') LOOP
      INSERT INTO platform.tenant_language (tenant_id, lang, locale, is_main, for_data)
        VALUES (p_tenant, l ->> 'code', l ->> 'locale', (l ->> 'main')::boolean, l ->> 'forData');
    END LOOP;
  END IF;
  INSERT INTO core.list_value (tenant_id, list_code, code, category, rank, name_en, name_fr, attributes, status)
    SELECT p_tenant, s.list_code, s.code, s.category, s.rank, s.name_en, s.name_fr, s.attributes, 'active'
    FROM ref.list_starter s
  ON CONFLICT DO NOTHING;
  INSERT INTO platform.workflow_route (tenant_id, code, subject_type, name_en, name_fr, conditions, priority, status, starter_code)
    SELECT p_tenant, s.code, s.subject_type, s.name_en, s.name_fr, s.conditions, s.priority, 'active', s.code
      FROM ref.workflow_route_starter s
     WHERE NOT EXISTS (SELECT 1 FROM platform.workflow_route r WHERE r.tenant_id = p_tenant AND r.starter_code = s.code)
  ON CONFLICT DO NOTHING;
  INSERT INTO platform.workflow_route_step (tenant_id, route_id, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr)
    SELECT p_tenant, r.route_id, s.step_no, s.approver_kind, s.capability, s.mode, s.min_approvals, s.purpose_en, s.purpose_fr
      FROM ref.workflow_route_step_starter s
      JOIN platform.workflow_route r ON r.tenant_id = p_tenant AND r.starter_code = s.route_code
     WHERE NOT EXISTS (SELECT 1 FROM platform.workflow_route_step x WHERE x.route_id = r.route_id);
  INSERT INTO recruit.onboarding_plan (tenant_id, code, name_en, name_fr, hire_kind, applies_to, status, starter_code)
    SELECT p_tenant, s.code, s.name_en, s.name_fr, s.hire_kind, s.applies_to, 'active', s.code
      FROM ref.onboarding_plan_starter s
     WHERE NOT EXISTS (SELECT 1 FROM recruit.onboarding_plan op WHERE op.tenant_id = p_tenant AND op.starter_code = s.code)
  ON CONFLICT DO NOTHING;
  INSERT INTO recruit.onboarding_plan_item (tenant_id, plan_id, item_code, seq, phase, kind, form_code, owner_kind, due_event,
                                            due_offset_days, depends_on, required, extra, name_en, name_fr)
    SELECT p_tenant, op.plan_id, s.item_code, s.seq, s.phase, s.kind, s.form_code, s.owner_kind, s.due_event,
           s.due_offset_days, s.depends_on, s.required, s.extra, s.name_en, s.name_fr
      FROM ref.onboarding_plan_item_starter s
      JOIN recruit.onboarding_plan op ON op.tenant_id = p_tenant AND op.starter_code = s.plan_code
     WHERE NOT EXISTS (SELECT 1 FROM recruit.onboarding_plan_item x WHERE x.plan_id = op.plan_id);
END $$;
-- Existing organizations get them now. Starter texts exist in English and French only: an organization that keeps
-- another language as required for its data would fail its own completeness check, so it is skipped and told; HR adds
-- the values with their texts (or copies them with core.seed_tenant once the texts can be completed).
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
      RAISE NOTICE 'organization %: starter routes, onboarding plans, posting channels and case kinds not copied because % is required for its data and the starters have no text in it; add them with their texts (docs/23 §10)',
        t.tenant_id, langs;
    END IF;
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT on ref.caution and the new ref starter tables; SELECT, INSERT and
-- UPDATE on the new tenant tables (INSERT only on platform.caution_acknowledgement, whose rows are never changed except
-- to attach their approval); EXECUTE on the new functions. core.close_lapsed_probations runs as the scheduler.
