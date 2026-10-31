-- =====================================================================================
-- Migration 0012 · Benefits decisions (docs/26)
--
-- Applies the owner's Module 05 review of 28 October 2026 (claude/review/05-benefits-decisions.md). Plans, classes and
-- leave rules are the organization's, set at setup; HR decides the cases a rule cannot (two agreements, two plans of
-- one kind, a position ending with no rule); the law's floors always apply; no medical information is stored.
--
--   §1  Settings
--   §2  Routes for carrier invoices; no self-approval
--   §3  Plan setup: waiting period, late enrolment, life event window, hours test, open enrolment default
--   §4  Dependents and age-out notices
--   §5  Two agreements and two plans of one kind: HR decides
--   §6  Leaves: contributions during statutory leave; the organization's rules for other unpaid leaves; coverage when
--       employment ends, by class, to the end of notice or severance where the organization says so
--   §7  Opt-outs with proof; enrolment sources (automatic pension enrolment)
--   §8  Premium adjustments for past months; carrier invoices
--   §9  Benefits advisors through provider access grants
--   §10 Starter routes; text fields; row-level security
--
-- Run after 0011. Nothing here pays a claim: spending accounts are administered by a partner (docs/26 §3.1).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/26 §2)
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('benefits.life_event_window_days', 'benefits', 'integer', NULL, NULL, ARRAY['tenant','legal_entity'], false,
  'Days after a life event (marriage, birth, divorce, loss of other coverage) during which the employee can change elections. Each plan can set its own. Chosen at setup.',
  'docs/26 §4.2 (R2.2)', 'pending', 1, NULL, NULL),
 ('benefits.retro_adjust_months', 'benefits', 'integer', NULL, NULL, ARRAY['tenant','legal_entity'], false,
  'How many months back premium adjustments for late enrolments, life events and rate changes are made automatically; anything older goes to HR to approve. Chosen at setup.',
  'docs/26 §8.1 (R5.1)', 'pending', 0, NULL, NULL),
 ('benefits.late_enrolment_starter', 'benefits', 'json', NULL, '{"life":"eoi","add":"eoi","std":"eoi","ltd":"eoi","dental":"limited_coverage"}', ARRAY['tenant','legal_entity'], false,
  'What a new plan of each kind starts from when someone enrols after their window: evidence of insurability (eoi), limited coverage, the next open enrolment, or HR decides. Kinds not listed state their rule when the plan is set up.',
  'docs/26 §4.3 (R2.3)', 'decided', NULL, NULL, NULL),
 ('benefits.open_enrolment_no_action', 'benefits', 'text', '["keep_current","plan_default","optional_ends"]', '"keep_current"', ARRAY['tenant','legal_entity'], false,
  'When an employee does nothing in open enrolment: current elections roll over, the plan''s default option applies, or optional coverage ends. A flex plan can name its own default option.',
  'docs/26 §4.4 (R2.4)', 'decided', NULL, NULL, NULL),
 ('benefits.statutory_leave_contributions', 'benefits', 'json', NULL, '{"methods":["prepay","arrears_on_return","payroll"],"employerPays":false}', ARRAY['tenant','legal_entity'], false,
  'How the employee''s share of premiums is paid during a statutory leave: the choices the employee is offered (pay ahead, arrears on return, through payroll while still paid), and whether the employer pays it instead.',
  'docs/26 §6.1 (R4.1)', 'decided', NULL, NULL, ARRAY['methods','employerPays']),
 ('benefits.dependent_ageout_notice_days', 'benefits', 'integer', NULL, '60', ARRAY['tenant','legal_entity'], false,
  'Days before a dependent child ages out of coverage when the employee and HR are told; proof of full-time studies is asked each year.',
  'docs/26 §4.5 (R5.3)', 'decided', 1, NULL, NULL),
 ('benefits.ai_enrolment_assistant', 'benefits', 'boolean', NULL, 'false', ARRAY['tenant'], false,
  'An assistant that answers enrolment questions from the plan booklet only, with citations, and never recommends an election. Comes with the platform assistant; off until the organization switches it on.',
  'docs/26 §3.4 (R1.4)', 'decided', NULL, NULL, NULL);

-- -------------------------------------------------------------------------------------
-- 2. Routes for carrier invoices (docs/26 §8.2)
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.workflow_route DROP CONSTRAINT IF EXISTS workflow_route_subject_type_check;
ALTER TABLE platform.workflow_route ADD CONSTRAINT workflow_route_subject_type_check
  CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution',
                          'pay_run','voluntary_deduction','banked_time_payout',
                          'comp_philosophy','pay_structure_version','comp_decision','incentive_payout','salary_disclosure',
                          'carrier_invoice'));

-- -------------------------------------------------------------------------------------
-- 3. Plan setup (docs/26 §4): the organization states the waiting period and the late-enrolment rule of each plan
-- -------------------------------------------------------------------------------------
ALTER TABLE benefits.plan
  ADD COLUMN waiting_rule                 jsonb,      -- {"kind":"none"} | {"kind":"days","n":90} | {"kind":"months","n":3} | {"kind":"first_of_month_after","n":3} | {"kind":"hours","n":480}
  ADD COLUMN late_enrolment               text CHECK (late_enrolment IN ('eoi','limited_coverage','next_open_enrolment','hr_decides')),
  ADD COLUMN life_event_window_days       smallint CHECK (life_event_window_days >= 1),   -- the plan's own window; otherwise the setting
  ADD COLUMN hours_test                   jsonb,      -- {"lookbackWeeks":13,"retestEvery":"quarter","minAvgHours":20} for variable-hour eligibility
  ADD COLUMN open_enrolment_default_option text,      -- a flex plan's option for people who do nothing
  ADD COLUMN dependent_rules              jsonb;      -- {"childMaxAge":21,"studentMaxAge":25,"disabledNoLimit":true}, from the plan contract

CREATE FUNCTION benefits.check_plan_setup() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text;
BEGIN
  IF NEW.waiting_rule IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: plan % states its waiting period (none, days, months, first of the month after, or hours worked)', NEW.code
      USING ERRCODE = 'check_violation';
  END IF;
  k := NEW.waiting_rule ->> 'kind';
  IF k IS NULL OR k NOT IN ('none','days','months','first_of_month_after','hours')
     OR (k <> 'none' AND coalesce((NEW.waiting_rule ->> 'n')::numeric, 0) <= 0) THEN
    RAISE EXCEPTION 'WAITING_RULE_INVALID: %', NEW.waiting_rule USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.late_enrolment IS NULL THEN
    NEW.late_enrolment := platform.setting(NEW.tenant_id, 'benefits.late_enrolment_starter') ->> NEW.kind;
  END IF;
  IF NEW.late_enrolment IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: plan % states what happens on a late enrolment', NEW.code USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.hours_test IS NOT NULL AND NOT (NEW.hours_test ?& ARRAY['lookbackWeeks','retestEvery','minAvgHours']) THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: an hours test states its look-back weeks, re-test schedule and minimum average hours' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a10_plan_setup BEFORE INSERT OR UPDATE ON benefits.plan
  FOR EACH ROW EXECUTE FUNCTION benefits.check_plan_setup();

-- The life event window for a plan on a date: the plan's own, else the organization's (chosen at setup)
CREATE FUNCTION benefits.life_event_window(p_plan uuid, p_on date, p_legal_entity uuid) RETURNS integer
LANGUAGE sql STABLE AS $$
  SELECT coalesce(p.life_event_window_days::int,
                  platform.setting_number(p.tenant_id, 'benefits.life_event_window_days', p_on, p_legal_entity)::int)
    FROM benefits.plan p WHERE p.plan_id = p_plan
$$;

-- -------------------------------------------------------------------------------------
-- 4. Dependents (docs/26 §4.5): kept under the employee's record, for plan administration only
-- -------------------------------------------------------------------------------------
CREATE TABLE benefits.dependent (
  tenant_id      uuid NOT NULL,
  dependent_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id  uuid NOT NULL REFERENCES core.employment,
  relationship   text NOT NULL CHECK (relationship IN ('spouse','child','other')),
  given_name     text NOT NULL,
  family_name    text NOT NULL,
  birth_date     date NOT NULL,
  student_proof_until date,                 -- proof of full-time studies received, valid to this date
  disabled       boolean NOT NULL,          -- a disabled dependent may have no age limit, as the plan says
  valid_period   daterange NOT NULL
);
-- The day the employee and HR are told before a dependent ages out
CREATE FUNCTION benefits.ageout_notice_on(p_tenant uuid, p_legal_entity uuid, p_ageout date) RETURNS date
LANGUAGE sql STABLE AS $$
  SELECT p_ageout - platform.setting_number(p_tenant, 'benefits.dependent_ageout_notice_days', p_ageout, p_legal_entity)::int
$$;

-- -------------------------------------------------------------------------------------
-- 5. Two agreements and two plans of one kind: HR decides (docs/26 §5; FB-020 and FB-023 decided)
-- -------------------------------------------------------------------------------------
ALTER TABLE benefits.enrolment
  ADD COLUMN cob_decided_by uuid,
  ADD COLUMN cob_decided_at timestamptz,
  ADD COLUMN cob_reason     text,
  ADD CONSTRAINT enrolment_cob_decided
    CHECK (cob_rank IS NULL OR (cob_decided_by IS NOT NULL AND cob_decided_at IS NOT NULL AND coalesce(length(btrim(cob_reason)), 0) > 0)) NOT VALID;
-- NOT VALID: orders set before 0012 are not rechecked; HR records the decision at their next change (docs/26 §11)

-- People who hold two plans of one kind on a date with no order decided yet: HR's task list, and the carrier file
-- stops for them (COB_ORDER_NOT_SET) until HR decides
CREATE FUNCTION benefits.cob_decisions_needed(p_tenant uuid, p_on date)
RETURNS TABLE (employment_id uuid, plan_kind text, enrolment_ids uuid[]) LANGUAGE sql STABLE AS $$
  SELECT e.employment_id, p.kind, array_agg(e.enrolment_id ORDER BY e.enrolment_id)
    FROM benefits.enrolment e JOIN benefits.plan p ON p.plan_id = e.plan_id
   WHERE e.tenant_id = p_tenant AND e.valid_period @> p_on
   GROUP BY e.employment_id, p.kind
  HAVING count(*) > 1 AND bool_or(e.cob_rank IS NULL)
$$;

-- The agreement that governs benefit rules for a person under two agreements, chosen by HR with a reason
CREATE TABLE benefits.governing_agreement (
  tenant_id     uuid NOT NULL,
  choice_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  agreement_id  text NOT NULL,
  valid_period  daterange NOT NULL,
  decided_by    uuid NOT NULL REFERENCES platform.app_user,
  decided_at    timestamptz NOT NULL DEFAULT now(),
  reason        text NOT NULL CHECK (length(btrim(reason)) > 0),
  FOREIGN KEY (tenant_id, agreement_id) REFERENCES core.agreement (tenant_id, agreement_id),
  EXCLUDE USING gist (employment_id WITH =, valid_period WITH &&)
);
CREATE FUNCTION benefits.governing_agreement_for(p_employment uuid, p_on date) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE n int; one text; chosen text;
BEGIN
  SELECT count(DISTINCT av.agreement_id), min(av.agreement_id) INTO n, one
    FROM core.assignment a JOIN core.assignment_version av ON av.assignment_id = a.assignment_id
   WHERE a.employment_id = p_employment AND av.valid_period @> p_on AND upper_inf(av.sys_period)
     AND av.agreement_id IS NOT NULL AND av.status NOT IN ('ended');
  IF n <= 1 THEN RETURN one; END IF;
  SELECT g.agreement_id INTO chosen FROM benefits.governing_agreement g
   WHERE g.employment_id = p_employment AND g.valid_period @> p_on;
  IF chosen IS NULL THEN
    RAISE EXCEPTION 'GOVERNING_AGREEMENT_NOT_SET: this person is under % agreements on %; HR chooses which governs their benefits', n, p_on
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN chosen;
END $$;

-- -------------------------------------------------------------------------------------
-- 6. Leaves (docs/26 §6)
-- -------------------------------------------------------------------------------------
-- 6.1 During a statutory leave the employee chooses how their share is paid, from the choices the organization allows
CREATE TABLE benefits.leave_contribution_choice (
  tenant_id        uuid NOT NULL,
  choice_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  leave_request_id uuid NOT NULL REFERENCES timeleave.leave_request,
  method           text NOT NULL CHECK (method IN ('prepay','arrears_on_return','payroll','employer_pays')),
  chosen_by        uuid NOT NULL REFERENCES platform.app_user,
  chosen_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (leave_request_id)
);
CREATE FUNCTION benefits.check_leave_contribution() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE s jsonb; le uuid; d date;
BEGIN
  SELECT e.legal_entity_id, lower(r.period) INTO le, d
    FROM timeleave.leave_request r JOIN core.employment e ON e.employment_id = r.employment_id
   WHERE r.leave_request_id = NEW.leave_request_id;
  s := platform.setting(NEW.tenant_id, 'benefits.statutory_leave_contributions', coalesce(d, current_date), le);
  IF NEW.method = 'employer_pays' AND NOT (s ->> 'employerPays')::boolean THEN
    RAISE EXCEPTION 'LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED: the organization does not pay the employee''s share' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.method <> 'employer_pays' AND NOT (s -> 'methods') ? NEW.method THEN
    RAISE EXCEPTION 'LEAVE_CONTRIBUTION_METHOD_NOT_ALLOWED: % is not offered by the organization', NEW.method USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER leave_contribution_check BEFORE INSERT OR UPDATE ON benefits.leave_contribution_choice
  FOR EACH ROW EXECUTE FUNCTION benefits.check_leave_contribution();

-- 6.2 Other unpaid leaves: the organization's rule for each leave type and class; none matching is an error
CREATE TABLE benefits.leave_rule (
  tenant_id     uuid NOT NULL REFERENCES platform.tenant,
  rule_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code          text NOT NULL,
  name_en       text NOT NULL,
  name_fr       text,
  applies_to    jsonb NOT NULL,     -- keys: leaveTypes, planKinds, employmentTypes, agreements, legalEntities (each a list); {} = all
  action        text NOT NULL CHECK (action IN ('continue_employee_cost','continue_employer_paid','suspend')),
  employer_paid_months smallint CHECK (employer_paid_months >= 1),
  then_action   text CHECK (then_action IN ('continue_employee_cost','suspend')),
  priority      smallint NOT NULL,
  status        text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT leave_rule_employer_period CHECK ((action = 'continue_employer_paid') = (employer_paid_months IS NOT NULL AND then_action IS NOT NULL)),
  CONSTRAINT leave_rule_scope_object CHECK (jsonb_typeof(applies_to) = 'object')
);
CREATE UNIQUE INDEX leave_rule_priority ON benefits.leave_rule (tenant_id, priority) WHERE status = 'active';
CREATE FUNCTION benefits.check_leave_rule_scope() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(NEW.applies_to) LOOP
    IF k NOT IN ('leaveTypes','planKinds','employmentTypes','agreements','legalEntities') OR jsonb_typeof(NEW.applies_to -> k) <> 'array' THEN
      RAISE EXCEPTION 'BENEFITS_SCOPE_UNKNOWN: % is not a scope (leaveTypes, planKinds, employmentTypes, agreements, legalEntities, each a list)', k
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER leave_rule_scope BEFORE INSERT OR UPDATE OF applies_to ON benefits.leave_rule
  FOR EACH ROW EXECUTE FUNCTION benefits.check_leave_rule_scope();

CREATE FUNCTION benefits.leave_rule_for(p_assignment uuid, p_leave_type text, p_plan_kind text, p_on date) RETURNS benefits.leave_rule
LANGUAGE plpgsql STABLE AS $$
DECLARE t uuid; statutory boolean; f jsonb; r benefits.leave_rule;
BEGIN
  SELECT a.tenant_id INTO t FROM core.assignment a WHERE a.assignment_id = p_assignment;
  SELECT lt.statutory INTO statutory FROM timeleave.leave_type lt WHERE lt.tenant_id = t AND lt.leave_type_code = p_leave_type;
  IF statutory IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: leave type % is unknown', p_leave_type USING ERRCODE = 'check_violation';
  END IF;
  IF statutory THEN
    RAISE EXCEPTION 'STATUTORY_LEAVE_FOLLOWS_LAW: benefits continue as the law requires during %; contributions follow benefits.statutory_leave_contributions', p_leave_type
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT jsonb_build_object(
           'leaveTypes',      jsonb_build_array(p_leave_type),
           'planKinds',       jsonb_build_array(p_plan_kind),
           'employmentTypes', jsonb_build_array(lt.category),
           'agreements',      jsonb_build_array(av.agreement_id),
           'legalEntities',   jsonb_build_array(e.legal_entity_id))
    INTO f
    FROM core.assignment a
    JOIN core.employment e ON e.employment_id = a.employment_id
    JOIN core.assignment_version av ON av.assignment_id = a.assignment_id AND av.valid_period @> p_on AND upper_inf(av.sys_period)
    LEFT JOIN core.list_value lt ON lt.tenant_id = av.tenant_id AND lt.list_code = 'employment_type' AND lt.code = av.employment_type
   WHERE a.assignment_id = p_assignment;
  IF f IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: position % is not held on %', p_assignment, p_on USING ERRCODE = 'check_violation';
  END IF;
  SELECT lr.* INTO r FROM benefits.leave_rule lr
   WHERE lr.tenant_id = t AND lr.status = 'active' AND payroll.scope_matches(lr.applies_to, f)
   ORDER BY lr.priority LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'LEAVE_BENEFIT_RULE_MISSING: no rule says what happens to % coverage during % leave; the organization sets it at setup', p_plan_kind, p_leave_type
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN r;
END $$;

-- 6.3 When employment ends, coverage ends as the organization's rule for the class says (docs/26 §7.1): the change rules
-- of 0006 also match the ending position's employment type (employmentTypes), and can run to the end of the severance
-- period. No rule matching goes to HR (FB-021); the statutory floor applies on top, as in 0006.
ALTER TABLE benefits.change_rule DROP CONSTRAINT change_rule_until_rule_check;
ALTER TABLE benefits.change_rule ADD CONSTRAINT change_rule_until_rule_check
  CHECK (until_rule IS NULL OR until_rule ->> 'kind' IN ('end_of_month','end_of_next_month','days','weeks','end_of_notice','end_of_severance','date'));

-- 6.4 Benefits during notice outside Ontario (docs/26 §7.2, R4.4): until employment counsel confirms each province, a
-- decision that carries COMMON_LAW_REVIEW or RULE_NOT_VERIFIED stops for HR: the caution is acknowledged and a reason
-- written before it is decided. The warnings are read from before and after the change, so clearing them never skips it.
INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('benefits.common_law_notice', 'benefits', 'Benefits during reasonable notice', 'Avantages sociaux pendant le préavis raisonnable',
  'CanDo has not confirmed whether this province''s law requires benefits to continue during the notice period. Even where it does not, a court can award the value of benefits for the whole reasonable notice period (at common law, or under the Civil Code in Quebec). Check with employment counsel before coverage ends before the notice period does, and state why.',
  'CanDo n''a pas confirmé si la loi de cette province exige de maintenir les avantages sociaux pendant la période de préavis. Même lorsqu''elle ne l''exige pas, un tribunal peut accorder la valeur des avantages pour toute la période de préavis raisonnable (en common law, ou en vertu du Code civil au Québec). Consultez un conseiller juridique en droit du travail avant que la couverture prenne fin avant le préavis, et indiquez pourquoi.',
  true, true, 'docs/26 §7.2 (R4.4)');

CREATE FUNCTION benefits.check_change_decision_caution() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE w text[];
BEGIN
  IF NEW.status NOT IN ('decided','applied') OR (TG_OP = 'UPDATE' AND OLD.status IN ('decided','applied')) THEN RETURN NEW; END IF;
  w := NEW.warnings;
  IF TG_OP = 'UPDATE' THEN w := w || OLD.warnings; END IF;
  IF w && ARRAY['COMMON_LAW_REVIEW','RULE_NOT_VERIFIED'] THEN
    IF coalesce(length(btrim(NEW.reason)), 0) = 0 THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: HR states why when the notice-period rule is not confirmed' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT platform.caution_cleared(NEW.tenant_id, 'benefits.common_law_notice', 'benefit_change_decision', NEW.decision_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: benefits.common_law_notice' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER change_decision_caution BEFORE INSERT OR UPDATE ON benefits.change_decision
  FOR EACH ROW EXECUTE FUNCTION benefits.check_change_decision_caution();

-- -------------------------------------------------------------------------------------
-- 7. Opt-outs with proof; where an enrolment came from (docs/26 §4.6, §9.2)
-- -------------------------------------------------------------------------------------
CREATE TABLE benefits.opt_out (
  tenant_id       uuid NOT NULL,
  opt_out_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id   uuid NOT NULL REFERENCES core.employment,
  plan_kind       text NOT NULL CHECK (plan_kind IN ('health','dental')),
  other_coverage  text NOT NULL,            -- carrier or plan sponsor of the other coverage
  proof_document_id uuid NOT NULL REFERENCES platform.document,
  valid_period    daterange NOT NULL,
  recorded_by     uuid NOT NULL REFERENCES platform.app_user
);

ALTER TABLE benefits.enrolment
  ADD COLUMN source text CHECK (source IN ('employee','hr','automatic','life_event','open_enrolment','rollover','migration'));

-- -------------------------------------------------------------------------------------
-- 8. Premium adjustments for past months; carrier invoices (docs/26 §8)
-- -------------------------------------------------------------------------------------
-- Whether an adjustment reaching back to p_from needs HR's approval (older than the organization's months)
CREATE FUNCTION benefits.retro_needs_hr(p_tenant uuid, p_legal_entity uuid, p_from date, p_on date) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT p_from < (date_trunc('month', p_on)
                   - make_interval(months => platform.setting_number(p_tenant, 'benefits.retro_adjust_months', p_on, p_legal_entity)::int))::date
$$;

CREATE TABLE benefits.carrier_invoice (
  tenant_id     uuid NOT NULL,
  invoice_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id uuid NOT NULL REFERENCES core.legal_entity,
  carrier       text NOT NULL,
  period        daterange NOT NULL,
  amount        numeric(14,2) NOT NULL,
  self_billed   boolean NOT NULL,              -- the employer produced the bill (self-billing) rather than the carrier
  document_id   uuid REFERENCES platform.document,
  differences   jsonb,                         -- by employee and plan: invoice amount, CanDo amount, explanation
  prepared_by   uuid NOT NULL REFERENCES platform.app_user,
  route_id      uuid REFERENCES platform.workflow_route,
  status        text NOT NULL CHECK (status IN ('draft','reconciled','approved','sent_to_payables','rejected')),
  CONSTRAINT invoice_reconciled CHECK (status NOT IN ('reconciled','approved','sent_to_payables') OR differences IS NOT NULL)
);
CREATE FUNCTION benefits.check_carrier_invoice() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('approved','sent_to_payables') AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('approved','sent_to_payables'))
     AND (NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'carrier_invoice', NEW.invoice_id, NEW.prepared_by, NULL)) THEN
    RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the invoice''s route is not complete' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER carrier_invoice_check BEFORE INSERT OR UPDATE ON benefits.carrier_invoice
  FOR EACH ROW EXECUTE FUNCTION benefits.check_carrier_invoice();

-- -------------------------------------------------------------------------------------
-- 9. Benefits advisors and brokers work through the provider access grants of 0010 §8 (docs/26 §3.3)
-- -------------------------------------------------------------------------------------
INSERT INTO ref.provider_capability (capability, name_en, name_fr) VALUES
 ('benefits_plan_costs', 'See plan design, enrolment counts and costs', 'Consulter la conception des régimes, le nombre d''adhésions et les coûts'),
 ('benefits_individual_data', 'See individual employees'' benefits data', 'Consulter les données d''avantages sociaux de chaque employé');

-- -------------------------------------------------------------------------------------
-- 10. No self-approval; starter routes; text fields; row-level security
-- -------------------------------------------------------------------------------------
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
  END IF;
  IF NEW.decided_by = requester THEN
    RAISE EXCEPTION 'SELF_APPROVAL: the requester cannot approve their own %', replace(NEW.subject_type, '_', ' ') USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

INSERT INTO ref.workflow_route_starter (code, subject_type, name_en, name_fr, conditions, priority, decision_ref) VALUES
 ('carrier_invoice', 'carrier_invoice', 'Carrier invoice approval', 'Approbation de la facture de l''assureur', '{}', 10, 'docs/26 §8.2 (R5.2)');
INSERT INTO ref.workflow_route_step_starter (route_code, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr) VALUES
 ('carrier_invoice', 1, 'capability', 'hr', 'any', 1, 'Benefits review of the reconciliation', 'Examen du rapprochement par les avantages sociaux'),
 ('carrier_invoice', 2, 'capability', 'finance', 'any', 1, 'Finance approval for payment', 'Approbation des finances pour paiement');

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
      ('benefits','dependent'), ('benefits','governing_agreement'), ('benefits','leave_contribution_choice'), ('benefits','leave_rule'),
      ('benefits','opt_out'), ('benefits','carrier_invoice')) AS x(s, t) LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$, r.s, r.t);
  END LOOP;
END $$;

-- Existing organizations get the new starter route (as in 0009, skipping one whose required data language has no
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
      RAISE NOTICE 'organization %: starter carrier invoice route not copied because % is required for its data; add it with its texts (docs/26 §11)', t.tenant_id, langs;
    END IF;
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT, INSERT and UPDATE on the new tenant tables and EXECUTE on the new
-- functions. Dependents' data is visible to the employee and benefits roles only (requirements/05 Security).
