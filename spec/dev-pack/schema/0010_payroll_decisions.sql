-- =====================================================================================
-- Migration 0010 · Payroll decisions (docs/24)
--
-- Applies the owner's Module 03 review of 27 October 2026 (claude/review/03-payroll-decisions.md). CanDo calculates,
-- prepares and reminds; the employer moves the money, pays the remittances and uploads the filings. Every rule is the
-- organization's, per group of employees where it matters; the law's minimums always apply.
--
--   §1  Settings: new ones, and the 0008 settings this review decided
--   §2  Routes for pay runs, voluntary deductions and banked-time payouts; no self-approval on them
--   §3  Pay runs: approval through the route, holds for failed checks, the parallel run before going live
--   §4  Vacation pay rules per group of employees
--   §5  Banked overtime (time off in lieu) policies and payout requests
--   §6  Deductions: arrears rule per deduction, arrears, voluntary deductions, garnishment orders, recoveries
--   §7  Pay statements and slips: delivery by CRA's rule (self-service, paper, consent), former employees' access, ROE review
--   §8  Outside payroll providers working for several organizations
--   §9  Starter routes; text fields; row-level security
--
-- Run after 0009. Nothing here moves money or files with a government: CanDo builds the bank file, the remittance
-- amounts and the slip and ROE files; the employer sends them (docs/24 §3).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/24 §2)
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('payroll.failed_check_handling', 'payroll', 'text', '["hold_affected","stop_run"]', '"hold_affected"', ARRAY['tenant','legal_entity'], false,
  'When pre-run checks fail for some employees: hold only those employees, with a reason, and pay everyone else on time (they are paid in an off-cycle run once fixed); or stop the whole run until every problem is fixed.',
  'docs/24 §4.2 (R2.2)', 'decided', NULL, NULL, NULL),
 ('payroll.parallel_run_periods', 'payroll', 'integer', NULL, '1', ARRAY['tenant','legal_entity'], false,
  'Pay periods run alongside the old system, with every difference explained and accepted, before a payroll account''s first live pay run. Never fewer than 1.',
  'docs/24 §4.4 (R7.3)', 'decided', 1, NULL, NULL),
 ('remittances.reminder_days', 'payroll', 'integer_array', NULL, '[7,3,1]', ARRAY['tenant','legal_entity'], false,
  'Days before a remittance''s due date when payroll is reminded to pay it (CRA, workers'' compensation, employer health tax, unions, pension plans). Pre-filled at setup; each organization can change them.',
  'docs/24 §3.2 (R1.2; pre-filled as decided in Q46)', 'decided', NULL, NULL, NULL),
 ('self_service.former_employee_access', 'self_service', 'json', NULL, '{"monthsAfterNextT4":12}', ARRAY['tenant','legal_entity'], false,
  'How long a former employee keeps a limited login to their own pay statements, slips and ROE: until the T4 for their last year is due (the end of February) plus this many months.',
  'docs/24 §7.2 (R5.2)', 'decided', NULL, NULL, ARRAY['monthsAfterNextT4']);

-- Decided in this review: settings 0008 created from the specifications
UPDATE platform.setting_definition
   SET default_value = NULL, decision_status = 'pending', decision_ref = 'docs/24 §5.2 (R3.2)',
       description_en = 'How salaried pay is prorated for a partial period (calendar days, working days or scheduled hours), chosen for each pay group at setup within the law. No CanDo default.'
 WHERE setting_key = 'payroll.default_proration_method';
UPDATE platform.setting_definition
   SET default_value = '"assignment"', decision_status = 'decided', decision_ref = 'docs/24 §8.2 (R7.2)',
       description_en = 'A one-time payment for someone in several positions names the position it belongs to (assignment); an organization can choose to share unnamed payments by earnings instead (earnings_share).'
 WHERE setting_key = 'payroll.one_time_allocation';
UPDATE platform.setting_definition SET decision_status = 'decided', decision_ref = decision_ref || '; docs/24 §8.1 (R6.2)'
 WHERE setting_key IN ('funding.default_cap_behaviour', 'funding.default_alert_days');
UPDATE platform.setting_definition SET decision_status = 'decided', decision_ref = decision_ref || '; docs/24 §8.1 (R6.3)'
 WHERE setting_key = 'funding.default_post_close_policy';

-- -------------------------------------------------------------------------------------
-- 2. Routes for pay runs, voluntary deductions and banked-time payouts (docs/24 §4.1, §6.2, §5.3)
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.workflow_route DROP CONSTRAINT IF EXISTS workflow_route_subject_type_check;
ALTER TABLE platform.workflow_route ADD CONSTRAINT workflow_route_subject_type_check
  CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution',
                          'pay_run','voluntary_deduction','banked_time_payout'));

-- -------------------------------------------------------------------------------------
-- 3. Pay runs: approval through the organization's route, holds, the parallel run before going live (docs/24 §4)
-- -------------------------------------------------------------------------------------
ALTER TABLE payroll.pay_run ADD COLUMN route_id uuid REFERENCES platform.workflow_route;

-- Employees held from a run because a pre-run check failed for them; they are paid in an off-cycle run once fixed
CREATE TABLE payroll.pay_run_hold (
  tenant_id          uuid NOT NULL,
  hold_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_run_id         uuid NOT NULL REFERENCES payroll.pay_run,
  person_id          uuid NOT NULL REFERENCES core.person,
  payroll_account_id uuid NOT NULL REFERENCES core.payroll_account,
  check_code         text NOT NULL,                      -- the failed check, e.g. BANK_ACCOUNT_MISSING, UNRESOLVED_INTERACTION
  reason             text NOT NULL CHECK (length(btrim(reason)) > 0),
  held_by            uuid NOT NULL REFERENCES platform.app_user,
  held_at            timestamptz NOT NULL DEFAULT now(),
  released_at        timestamptz,
  released_in_run_id uuid REFERENCES payroll.pay_run,
  UNIQUE (pay_run_id, person_id, payroll_account_id)
);

CREATE FUNCTION payroll.check_pay_run() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE acct uuid; needed int; accepted int;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN RETURN NEW; END IF;
  IF NEW.status = 'approved' AND NEW.run_type <> 'simulation' THEN
    IF NEW.route_id IS NULL OR NEW.approved_by IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a pay run is approved through its route, naming its final approver' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT platform.route_complete(NEW.route_id, 'pay_run', NEW.pay_run_id, NEW.created_by, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the pay run''s route is not complete' USING ERRCODE = 'check_violation';
    END IF;
    IF platform.setting_text(NEW.tenant_id, 'payroll.failed_check_handling', NEW.pay_date, NEW.legal_entity_id) = 'stop_run'
       AND EXISTS (SELECT 1 FROM payroll.pay_run_hold h WHERE h.pay_run_id = NEW.pay_run_id AND h.released_at IS NULL) THEN
      RAISE EXCEPTION 'PAY_RUN_HAS_FAILED_CHECKS: the organization stops the run until every failed check is fixed' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  -- The first live run of a payroll account waits for the parallel run(s) to be accepted (docs/24 §4.4)
  IF NEW.status = 'finalized' AND NEW.run_type <> 'simulation' AND NEW.pay_group_id IS NOT NULL THEN
    SELECT payroll_account_id INTO acct FROM payroll.pay_group WHERE pay_group_id = NEW.pay_group_id;
    IF NOT EXISTS (SELECT 1 FROM payroll.pay_run r JOIN payroll.pay_group g ON g.pay_group_id = r.pay_group_id
                    WHERE g.payroll_account_id = acct AND r.status IN ('finalized','paid') AND r.run_type <> 'simulation'
                      AND r.pay_run_id <> NEW.pay_run_id) THEN
      needed := platform.setting_number(NEW.tenant_id, 'payroll.parallel_run_periods', NEW.pay_date, NEW.legal_entity_id)::int;
      SELECT count(*) INTO accepted FROM payroll.parallel_run p WHERE p.payroll_account_id = acct AND p.status = 'accepted';
      IF accepted < needed THEN
        RAISE EXCEPTION 'PARALLEL_RUN_REQUIRED: % accepted parallel run(s) of the % needed before the first live run', accepted, needed
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- A pay period run alongside the old system, with every difference explained
CREATE TABLE payroll.parallel_run (
  tenant_id          uuid NOT NULL,
  parallel_run_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_account_id uuid NOT NULL REFERENCES core.payroll_account,
  pay_date           date NOT NULL,
  simulation_run_id  uuid REFERENCES payroll.pay_run,    -- CanDo's run for the period, as a simulation
  legacy_totals      jsonb NOT NULL,                     -- the old system's totals by person and code, imported
  differences        jsonb,                              -- each difference with its explanation
  status             text NOT NULL CHECK (status IN ('in_progress','explained','accepted')),
  accepted_by        uuid REFERENCES platform.app_user,
  accepted_at        timestamptz,
  CONSTRAINT parallel_run_accepted_signed CHECK (status <> 'accepted' OR (accepted_by IS NOT NULL AND accepted_at IS NOT NULL AND differences IS NOT NULL))
);

CREATE TRIGGER pay_run_check BEFORE UPDATE OF status ON payroll.pay_run
  FOR EACH ROW EXECUTE FUNCTION payroll.check_pay_run();

-- -------------------------------------------------------------------------------------
-- 4. Vacation pay rules per group of employees (docs/24 §5.1): accrue and pay when taken, or pay on each cheque,
--    at the law's minimum for the employee's service or a higher percentage. The first active rule by priority whose
--    scope matches the position applies; none matching is an error.
-- -------------------------------------------------------------------------------------
CREATE TABLE payroll.vacation_pay_rule (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  rule_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL,
  name_en     text NOT NULL,
  name_fr     text,
  method      text NOT NULL CHECK (method IN ('accrue_pay_when_taken','pay_each_cheque')),
  rate_source text NOT NULL CHECK (rate_source IN ('law_minimum','fixed_percent')),
  percent     numeric(5,2) CHECK (percent > 0 AND percent <= 100),
  applies_to  jsonb NOT NULL,                            -- {} = everyone; keys: payGroups, employmentTypes, agreements, legalEntities, orgUnits
  priority    smallint NOT NULL,
  status      text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT vacation_pay_rule_percent CHECK ((rate_source = 'fixed_percent') = (percent IS NOT NULL)),
  CONSTRAINT vacation_pay_rule_scope_object CHECK (jsonb_typeof(applies_to) = 'object')
);
CREATE UNIQUE INDEX vacation_pay_rule_priority ON payroll.vacation_pay_rule (tenant_id, priority) WHERE status = 'active';

-- Scope keys shared by the payroll rule tables
CREATE FUNCTION payroll.check_scope_keys() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE k text;
BEGIN
  FOR k IN SELECT jsonb_object_keys(NEW.applies_to) LOOP
    IF k NOT IN ('payGroups','employmentTypes','agreements','legalEntities','orgUnits') OR jsonb_typeof(NEW.applies_to -> k) <> 'array' THEN
      RAISE EXCEPTION 'PAYROLL_SCOPE_UNKNOWN: % is not a scope (payGroups, employmentTypes, agreements, legalEntities, orgUnits, each a list)', k
        USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  RETURN NEW;
END $$;
CREATE TRIGGER vacation_pay_rule_scope BEFORE INSERT OR UPDATE OF applies_to ON payroll.vacation_pay_rule
  FOR EACH ROW EXECUTE FUNCTION payroll.check_scope_keys();

-- What one position looks like to a scope on a date
CREATE FUNCTION payroll.assignment_scope_facts(p_assignment uuid, p_as_of date) RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT jsonb_build_object(
           'payGroups',       jsonb_build_array(av.pay_group_id),
           'employmentTypes', jsonb_build_array(lt.category),
           'agreements',      jsonb_build_array(av.agreement_id),
           'legalEntities',   jsonb_build_array(e.legal_entity_id),
           'orgUnits',        jsonb_build_array(av.org_unit_id))
    FROM core.assignment a
    JOIN core.employment e ON e.employment_id = a.employment_id
    JOIN core.assignment_version av ON av.assignment_id = a.assignment_id AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
    LEFT JOIN core.list_value lt ON lt.tenant_id = av.tenant_id AND lt.list_code = 'employment_type' AND lt.code = av.employment_type
   WHERE a.assignment_id = p_assignment
$$;

CREATE FUNCTION payroll.scope_matches(p_scope jsonb, p_facts jsonb) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_scope) k
     WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(p_scope -> k) x WHERE (p_facts -> k) @> jsonb_build_array(x)))
$$;

CREATE FUNCTION payroll.vacation_pay_rule_for(p_assignment uuid, p_as_of date) RETURNS payroll.vacation_pay_rule
LANGUAGE plpgsql STABLE AS $$
DECLARE f jsonb; r payroll.vacation_pay_rule;
BEGIN
  f := payroll.assignment_scope_facts(p_assignment, p_as_of);
  IF f IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: position % is not held on %', p_assignment, p_as_of USING ERRCODE = 'check_violation';
  END IF;
  SELECT v.* INTO r FROM payroll.vacation_pay_rule v
    JOIN core.assignment a ON a.tenant_id = v.tenant_id AND a.assignment_id = p_assignment
   WHERE v.status = 'active' AND payroll.scope_matches(v.applies_to, f)
   ORDER BY v.priority LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'VACATION_PAY_RULE_MISSING: no vacation pay rule covers position % on %; the organization sets its rules at setup', p_assignment, p_as_of
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN r;
END $$;

INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('payroll.vacation_pay_each_cheque', 'payroll', 'Vacation pay on each cheque', 'Indemnité de vacances sur chaque paie',
  'Paying vacation pay on each cheque needs the employee''s written agreement in some provinces, and the employee still takes their vacation time. Check the law for these employees before going ahead.',
  'Verser l''indemnité de vacances sur chaque paie exige l''accord écrit de l''employé dans certaines provinces, et l''employé prend quand même ses vacances. Vérifiez la loi pour ces employés avant d''aller plus loin.',
  false, true, 'docs/24 §5.1 (R3.1)');

-- -------------------------------------------------------------------------------------
-- 5. Banked overtime (time off in lieu) policies per group, and payout requests (docs/24 §5.3)
-- -------------------------------------------------------------------------------------
CREATE TABLE timeleave.banked_time_policy (
  tenant_id               uuid NOT NULL REFERENCES platform.tenant,
  policy_id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                    text NOT NULL,
  name_en                 text NOT NULL,
  name_fr                 text,
  year_end_action         text NOT NULL CHECK (year_end_action IN ('pay_out','carry_over','carry_then_pay')),
  carry_limit_hours       numeric(8,2) CHECK (carry_limit_hours >= 0),
  employee_payout_requests boolean NOT NULL,            -- employees can ask for a payout during the year, through the payout route
  applies_to              jsonb NOT NULL,
  priority                smallint NOT NULL,
  status                  text NOT NULL CHECK (status IN ('active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT banked_time_carry_limit CHECK ((year_end_action = 'carry_then_pay') = (carry_limit_hours IS NOT NULL)),
  CONSTRAINT banked_time_scope_object CHECK (jsonb_typeof(applies_to) = 'object')
);
CREATE UNIQUE INDEX banked_time_policy_priority ON timeleave.banked_time_policy (tenant_id, priority) WHERE status = 'active';
CREATE TRIGGER banked_time_policy_scope BEFORE INSERT OR UPDATE OF applies_to ON timeleave.banked_time_policy
  FOR EACH ROW EXECUTE FUNCTION payroll.check_scope_keys();

CREATE FUNCTION timeleave.banked_time_policy_for(p_assignment uuid, p_as_of date) RETURNS timeleave.banked_time_policy
LANGUAGE plpgsql STABLE AS $$
DECLARE f jsonb; r timeleave.banked_time_policy;
BEGIN
  f := payroll.assignment_scope_facts(p_assignment, p_as_of);
  IF f IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: position % is not held on %', p_assignment, p_as_of USING ERRCODE = 'check_violation';
  END IF;
  SELECT b.* INTO r FROM timeleave.banked_time_policy b
    JOIN core.assignment a ON a.tenant_id = b.tenant_id AND a.assignment_id = p_assignment
   WHERE b.status = 'active' AND payroll.scope_matches(b.applies_to, f)
   ORDER BY b.priority LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'BANKED_TIME_POLICY_MISSING: no banked time policy covers position % on %', p_assignment, p_as_of USING ERRCODE = 'check_violation';
  END IF;
  RETURN r;
END $$;

CREATE TABLE timeleave.banked_time_payout_request (
  tenant_id     uuid NOT NULL,
  request_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES core.assignment,
  hours         numeric(8,2) NOT NULL CHECK (hours > 0),
  requested_on  date NOT NULL,
  requested_by  uuid NOT NULL REFERENCES platform.app_user,
  route_id      uuid REFERENCES platform.workflow_route,
  status        text NOT NULL CHECK (status IN ('requested','approved','rejected','paid','cancelled')),
  one_time_item_id uuid REFERENCES payroll.one_time_item
);
CREATE FUNCTION timeleave.check_banked_payout() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NOT (timeleave.banked_time_policy_for(NEW.assignment_id, NEW.requested_on)).employee_payout_requests THEN
    RAISE EXCEPTION 'BANKED_PAYOUT_NOT_ALLOWED: the banked time policy for this position does not allow payout requests' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved')
     AND (NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'banked_time_payout', NEW.request_id, NEW.requested_by, NULL)) THEN
    RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the payout request''s route is not complete' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER banked_payout_check BEFORE INSERT OR UPDATE ON timeleave.banked_time_payout_request
  FOR EACH ROW EXECUTE FUNCTION timeleave.check_banked_payout();

-- -------------------------------------------------------------------------------------
-- 6. Deductions (docs/24 §6)
-- -------------------------------------------------------------------------------------
-- 6.1 Each deduction says what happens to a shortfall when a pay cannot cover it (the law's order comes first)
ALTER TABLE payroll.pay_code
  ADD COLUMN arrears_recovery      text CHECK (arrears_recovery IN ('next_pay','spread','hr_decides','not_recovered')),
  ADD COLUMN arrears_spread_periods smallint CHECK (arrears_spread_periods > 1),
  ADD CONSTRAINT pay_code_arrears_spread CHECK ((arrears_recovery = 'spread') = (arrears_spread_periods IS NOT NULL));
CREATE FUNCTION payroll.check_pay_code_arrears() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.kind = 'deduction' AND NEW.arrears_recovery IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: deduction % states what happens to a shortfall (arrears_recovery)', NEW.pay_code USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pay_code_arrears_check BEFORE INSERT OR UPDATE OF kind, arrears_recovery ON payroll.pay_code
  FOR EACH ROW EXECUTE FUNCTION payroll.check_pay_code_arrears();

CREATE TABLE payroll.deduction_arrears (
  tenant_id        uuid NOT NULL,
  arrears_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id    uuid NOT NULL REFERENCES core.employment,
  pay_code         text NOT NULL,
  amount           numeric(14,2) NOT NULL CHECK (amount > 0),
  recovered        numeric(14,2) NOT NULL DEFAULT 0 CHECK (recovered >= 0),
  from_result_id   uuid REFERENCES payroll.pay_result,
  status           text NOT NULL CHECK (status IN ('open','recovering','recovered','written_off')),
  written_off_by   uuid REFERENCES platform.app_user,
  written_off_reason text,
  FOREIGN KEY (tenant_id, pay_code) REFERENCES payroll.pay_code (tenant_id, pay_code),
  CONSTRAINT arrears_not_over CHECK (recovered <= amount),
  CONSTRAINT arrears_write_off_signed CHECK (status <> 'written_off' OR (written_off_by IS NOT NULL AND coalesce(length(btrim(written_off_reason)), 0) > 0))
);

-- 6.2 Voluntary deductions started or stopped by the employee, approved through the organization's route
CREATE TABLE payroll.voluntary_deduction (
  tenant_id      uuid NOT NULL,
  deduction_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id  uuid NOT NULL REFERENCES core.employment,
  pay_code       text NOT NULL,
  amount_per_pay numeric(14,2) NOT NULL CHECK (amount_per_pay > 0),
  goal_amount    numeric(14,2) CHECK (goal_amount > 0),
  start_on       date NOT NULL,
  end_on         date,
  requested_by   uuid NOT NULL REFERENCES platform.app_user,
  route_id       uuid REFERENCES platform.workflow_route,
  status         text NOT NULL CHECK (status IN ('requested','approved','stopped','rejected')),
  FOREIGN KEY (tenant_id, pay_code) REFERENCES payroll.pay_code (tenant_id, pay_code),
  CONSTRAINT voluntary_deduction_dates CHECK (end_on IS NULL OR end_on >= start_on)
);
CREATE FUNCTION payroll.check_voluntary_deduction() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT kind FROM payroll.pay_code WHERE tenant_id = NEW.tenant_id AND pay_code = NEW.pay_code) <> 'deduction' THEN
    RAISE EXCEPTION 'PAY_CODE_NOT_DEDUCTION: % is not a deduction code', NEW.pay_code USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved')
     AND (NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'voluntary_deduction', NEW.deduction_id, NEW.requested_by, NULL)) THEN
    RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the deduction''s route is not complete' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER voluntary_deduction_check BEFORE INSERT OR UPDATE ON payroll.voluntary_deduction
  FOR EACH ROW EXECUTE FUNCTION payroll.check_voluntary_deduction();

-- 6.3 Garnishments and support orders: CanDo works out the deduction and the protected amount from the law;
--     payroll confirms the first deduction of each order before it becomes active
CREATE TABLE payroll.garnishment_order (
  tenant_id      uuid NOT NULL,
  order_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id  uuid NOT NULL REFERENCES core.employment,
  kind           text NOT NULL CHECK (kind IN ('family_support','cra_requirement_to_pay','federal_garnishment','provincial_garnishment','other')),
  jurisdiction   text NOT NULL,                          -- the law the order is made under (province or FED)
  issuer         text NOT NULL,
  reference      text NOT NULL,
  document_id    uuid NOT NULL REFERENCES platform.document,
  terms          jsonb NOT NULL,                         -- {"perPay":..} | {"percent":..} | {"totalOwed":..,"perPay":..}
  received_on    date NOT NULL,
  start_on       date NOT NULL,
  entered_by     uuid NOT NULL REFERENCES platform.app_user,
  first_deduction_confirmed_by uuid REFERENCES platform.app_user,
  first_deduction_confirmed_at timestamptz,
  status         text NOT NULL CHECK (status IN ('received','active','suspended','satisfied','withdrawn')),
  CONSTRAINT garnishment_terms_object CHECK (jsonb_typeof(terms) = 'object')
);
CREATE FUNCTION payroll.check_garnishment_order() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'active' AND (NEW.first_deduction_confirmed_by IS NULL OR NEW.first_deduction_confirmed_at IS NULL) THEN
    RAISE EXCEPTION 'GARNISHMENT_NOT_CONFIRMED: payroll confirms the first deduction of an order before it is taken' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER garnishment_order_check BEFORE INSERT OR UPDATE ON payroll.garnishment_order
  FOR EACH ROW EXECUTE FUNCTION payroll.check_garnishment_order();

-- 6.4 Money an employee owes (advance, equipment, unearned training) is recovered only with their written
--     authorization, never more than it allows (overpayments keep their own flow from 0007)
CREATE TABLE payroll.recovery_authorization (
  tenant_id        uuid NOT NULL,
  authorization_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id    uuid NOT NULL REFERENCES core.employment,
  kind             text NOT NULL CHECK (kind IN ('advance','equipment','training','loan','other')),
  description      text NOT NULL,
  amount           numeric(14,2) NOT NULL CHECK (amount > 0),
  per_pay_limit    numeric(14,2) CHECK (per_pay_limit > 0),
  document_id      uuid NOT NULL REFERENCES platform.document,   -- the employee's signed authorization
  signed_on        date NOT NULL
);
ALTER TABLE payroll.one_time_item ADD COLUMN recovery_authorization_id uuid REFERENCES payroll.recovery_authorization;
CREATE FUNCTION payroll.check_debt_recovery() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE a payroll.recovery_authorization; used numeric;
BEGIN
  IF NEW.source = 'recovery' AND NEW.overpayment_id IS NULL AND NEW.recovery_authorization_id IS NULL THEN
    RAISE EXCEPTION 'RECOVERY_NOT_AUTHORIZED: money owed is recovered only with the employee''s written authorization' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.recovery_authorization_id IS NOT NULL THEN
    SELECT * INTO a FROM payroll.recovery_authorization WHERE authorization_id = NEW.recovery_authorization_id;
    IF a.employment_id <> NEW.employment_id THEN
      RAISE EXCEPTION 'RECOVERY_NOT_AUTHORIZED: the authorization is for another employment' USING ERRCODE = 'check_violation';
    END IF;
    SELECT coalesce(sum(abs(i.amount)), 0) INTO used FROM payroll.one_time_item i
     WHERE i.recovery_authorization_id = a.authorization_id AND i.status <> 'cancelled' AND i.item_id <> NEW.item_id;
    IF used + abs(NEW.amount) > a.amount THEN
      RAISE EXCEPTION 'RECOVERY_ABOVE_AUTHORIZED: % would be recovered of the % authorized', used + abs(NEW.amount), a.amount USING ERRCODE = 'check_violation';
    END IF;
    IF a.per_pay_limit IS NOT NULL AND abs(NEW.amount) > a.per_pay_limit THEN
      RAISE EXCEPTION 'RECOVERY_ABOVE_AUTHORIZED: % in one pay; the authorization allows % per pay', abs(NEW.amount), a.per_pay_limit USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER one_time_item_debt_recovery BEFORE INSERT OR UPDATE OF source, amount, recovery_authorization_id ON payroll.one_time_item
  FOR EACH ROW EXECUTE FUNCTION payroll.check_debt_recovery();

-- -------------------------------------------------------------------------------------
-- 7. Pay statements, slips and ROEs (docs/24 §7)
-- -------------------------------------------------------------------------------------
-- 7.1 Delivery follows CRA's rule for slips (and the provinces' for pay statements): current employees get them in
--     self-service, on paper if they ask; former employees and people on extended leave get them electronically only
--     with their consent, otherwise on paper; email only with consent (docs/24 §7.1). The rule is CRA's
--     (nationwide.tax_slip_delivery in rules/employment-standards/ca-2026-payroll-additions.json); CanDo treats a position
--     on leave or laid off as extended leave, so those people get paper unless they consent. A paper request is also how
--     HR records that someone cannot reasonably reach self-service.
CREATE TABLE payroll.delivery_choice (
  tenant_id     uuid NOT NULL,
  choice_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id     uuid NOT NULL REFERENCES core.person,
  document_kind text NOT NULL CHECK (document_kind IN ('pay_statement','tax_slip')),
  choice        text NOT NULL CHECK (choice IN ('electronic_consent','email_consent','paper_request')),
  given_at      timestamptz NOT NULL,
  method        text NOT NULL CHECK (method IN ('self_service','paper_form')),
  withdrawn_at  timestamptz,
  CONSTRAINT delivery_choice_dates CHECK (withdrawn_at IS NULL OR withdrawn_at >= given_at)
);
CREATE FUNCTION payroll.delivery_choice_active(p_person uuid, p_kind text, p_choice text, p_at timestamptz) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM payroll.delivery_choice c
                  WHERE c.person_id = p_person AND c.document_kind = p_kind AND c.choice = p_choice
                    AND c.given_at <= p_at AND (c.withdrawn_at IS NULL OR c.withdrawn_at > p_at))
$$;
-- 'portal' or 'print' for a document issued at p_at
CREATE FUNCTION payroll.delivery_method(p_person uuid, p_kind text, p_at timestamptz) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE
           WHEN payroll.delivery_choice_active(p_person, p_kind, 'paper_request', p_at) THEN 'print'
           -- a current employee not on extended leave: self-service, no consent needed
           WHEN EXISTS (SELECT 1 FROM core.employment e
                          JOIN core.assignment a ON a.employment_id = e.employment_id
                          JOIN core.assignment_version av ON av.assignment_id = a.assignment_id
                                                         AND av.valid_period @> p_at::date AND upper_inf(av.sys_period)
                         WHERE e.person_id = p_person AND av.status NOT IN ('ended','on_leave','laid_off')) THEN 'portal'
           -- a former employee, or one on extended leave: electronic only with consent
           WHEN payroll.delivery_choice_active(p_person, p_kind, 'electronic_consent', p_at) THEN 'portal'
           ELSE 'print'
         END
$$;
CREATE FUNCTION payroll.may_email(p_person uuid, p_kind text, p_at timestamptz) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT payroll.delivery_choice_active(p_person, p_kind, 'email_consent', p_at)
$$;

-- 7.2 Former employees keep a limited login to their own pay statements, slips and ROE
ALTER TABLE platform.app_user ADD COLUMN former_employee_until date;
COMMENT ON COLUMN platform.app_user.former_employee_until IS
  'Set when a person''s last employment ends: until this date they can sign in to see only their own pay statements, slips and ROE (docs/24 §7.2).';
CREATE FUNCTION payroll.former_employee_access_until(p_tenant uuid, p_legal_entity uuid, p_last_day date) RETURNS date
LANGUAGE sql STABLE AS $$
  -- the T4 for the year of the last day is due at the end of the following February (nationwide.tax_slip_delivery.due)
  SELECT ((date_trunc('year', p_last_day) + interval '1 year 2 months' - interval '1 day')::date
          + make_interval(months => (platform.setting(p_tenant, 'self_service.former_employee_access', p_last_day, p_legal_entity)
                                     ->> 'monthsAfterNextT4')::int))::date
$$;

-- 7.3 CanDo prepares the ROE; HR reviews the reason code and comments before the file is built for ROE Web
ALTER TABLE payroll.roe
  ADD COLUMN reviewed_by uuid REFERENCES platform.app_user,
  ADD COLUMN reviewed_at timestamptz;
CREATE FUNCTION payroll.check_roe_review() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('validated','submitted','accepted') AND (NEW.reviewed_by IS NULL OR NEW.reviewed_at IS NULL) THEN
    RAISE EXCEPTION 'ROE_NOT_REVIEWED: HR reviews the reason code and comments before the ROE file is built' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER roe_review_check BEFORE INSERT OR UPDATE OF status ON payroll.roe
  FOR EACH ROW EXECUTE FUNCTION payroll.check_roe_review();

-- -------------------------------------------------------------------------------------
-- 8. Outside payroll providers (docs/24 §4.5): an accounting firm or a CanDo partner works for several client
--    organizations from one login, only with each client's approval of what it can do
-- -------------------------------------------------------------------------------------
CREATE TABLE ref.provider_capability (
  capability  text PRIMARY KEY,
  name_en     text NOT NULL,
  name_fr     text NOT NULL
);
INSERT INTO ref.provider_capability (capability, name_en, name_fr) VALUES
 ('payroll_prepare', 'Prepare pay runs', 'Préparer les paies'),
 ('payroll_approve', 'Approve pay runs', 'Approuver les paies'),
 ('payroll_files',   'Build bank, remittance, slip and ROE files', 'Produire les fichiers bancaires, de versement, de feuillets et de RE'),
 ('employee_records_read', 'See employee pay records', 'Consulter les dossiers de paie des employés'),
 ('employee_records_edit', 'Change employee pay records', 'Modifier les dossiers de paie des employés'),
 ('reports', 'Run payroll reports', 'Produire les rapports de paie');

CREATE TABLE platform.provider_access_grant (
  tenant_id          uuid NOT NULL REFERENCES platform.tenant,   -- the client organization
  grant_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_tenant_id uuid NOT NULL REFERENCES platform.tenant,   -- the provider's own organization in CanDo
  provider_user_id   uuid NOT NULL,                              -- the provider's user, in the provider's organization
  capabilities       text[] NOT NULL,
  valid_period       tstzrange NOT NULL,
  status             text NOT NULL CHECK (status IN ('requested','approved','revoked','expired')),
  requested_at       timestamptz NOT NULL DEFAULT now(),
  approved_by        uuid REFERENCES platform.app_user,          -- a user of the client organization
  approved_at        timestamptz,
  revoked_by         uuid REFERENCES platform.app_user,
  revoked_at         timestamptz,
  CONSTRAINT provider_not_self CHECK (provider_tenant_id <> tenant_id),
  CONSTRAINT provider_grant_approved CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CONSTRAINT provider_grant_revoked CHECK (status <> 'revoked' OR (revoked_by IS NOT NULL AND revoked_at IS NOT NULL))
);
CREATE FUNCTION platform.check_provider_grant() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog AS $$
DECLARE c text;
BEGIN
  FOREACH c IN ARRAY NEW.capabilities LOOP
    IF NOT EXISTS (SELECT 1 FROM ref.provider_capability WHERE capability = c) THEN
      RAISE EXCEPTION 'PROVIDER_CAPABILITY_UNKNOWN: %', c USING ERRCODE = 'check_violation';
    END IF;
  END LOOP;
  IF NEW.status = 'approved' AND NOT EXISTS (SELECT 1 FROM platform.app_user u WHERE u.user_id = NEW.approved_by AND u.tenant_id = NEW.tenant_id) THEN
    RAISE EXCEPTION 'PROVIDER_GRANT_NOT_CLIENT: only a user of the client organization approves a provider''s access' USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM platform.app_user u WHERE u.user_id = NEW.provider_user_id AND u.tenant_id = NEW.provider_tenant_id) THEN
    RAISE EXCEPTION 'PROVIDER_USER_UNKNOWN: the provider user belongs to the provider''s organization' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER provider_grant_check BEFORE INSERT OR UPDATE ON platform.provider_access_grant
  FOR EACH ROW EXECUTE FUNCTION platform.check_provider_grant();

CREATE FUNCTION platform.provider_can(p_client uuid, p_provider_user uuid, p_capability text, p_at timestamptz) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog AS $$
  SELECT EXISTS (SELECT 1 FROM platform.provider_access_grant g
                  WHERE g.tenant_id = p_client AND g.provider_user_id = p_provider_user AND g.status = 'approved'
                    AND g.valid_period @> p_at AND p_capability = ANY (g.capabilities))
$$;

-- No one approves their own pay run, voluntary deduction or payout request (adds to 0009 §12)
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
  END IF;
  IF NEW.decided_by = requester THEN
    RAISE EXCEPTION 'SELF_APPROVAL: the requester cannot approve their own %', replace(NEW.subject_type, '_', ' ') USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- -------------------------------------------------------------------------------------
-- 9. Starter routes; text fields registered as translatable; row-level security
-- -------------------------------------------------------------------------------------
INSERT INTO ref.workflow_route_starter (code, subject_type, name_en, name_fr, conditions, priority, decision_ref) VALUES
 ('pay_run', 'pay_run', 'Pay run approval', 'Approbation de la paie', '{}', 10, 'docs/24 §4.1 (R2.1)'),
 ('voluntary_deduction', 'voluntary_deduction', 'Voluntary deduction', 'Retenue facultative', '{}', 10, 'docs/24 §6.2 (R4.2)'),
 ('banked_time_payout', 'banked_time_payout', 'Banked time payout', 'Paiement du temps accumulé', '{}', 10, 'docs/24 §5.3 (R3.3)');
INSERT INTO ref.workflow_route_step_starter (route_code, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr) VALUES
 -- R2.1: payroll prepares, HR or finance approves; the starter names finance and setup asks whether HR approves instead
 ('pay_run', 1, 'capability', 'finance', 'any', 1, 'Pay run approval (never the person who prepared it)', 'Approbation de la paie (jamais la personne qui l''a préparée)'),
 ('voluntary_deduction', 1, 'capability', 'payroll', 'any', 1, 'Voluntary deduction', 'Retenue facultative'),
 ('banked_time_payout', 1, 'requester_manager', NULL, 'any', 1, 'Manager approval', 'Approbation du gestionnaire'),
 ('banked_time_payout', 2, 'capability', 'payroll', 'any', 1, 'Payroll', 'Paie');

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
      ('payroll','pay_run_hold'), ('payroll','parallel_run'), ('payroll','vacation_pay_rule'), ('timeleave','banked_time_policy'),
      ('timeleave','banked_time_payout_request'), ('payroll','deduction_arrears'), ('payroll','voluntary_deduction'),
      ('payroll','garnishment_order'), ('payroll','recovery_authorization'), ('payroll','delivery_choice'),
      ('platform','provider_access_grant')) AS x(s, t) LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$, r.s, r.t);
  END LOOP;
END $$;

-- Existing organizations get the new starter routes (as in 0009, skipping one whose required data language has no starter text)
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
      RAISE NOTICE 'organization %: starter payroll routes not copied because % is required for its data; add them with their texts (docs/24 §11)', t.tenant_id, langs;
    END IF;
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT on ref.provider_capability; SELECT, INSERT and UPDATE on the new tenant
-- tables (platform.provider_access_grant approvals only through the identity Worker); EXECUTE on the new functions.
