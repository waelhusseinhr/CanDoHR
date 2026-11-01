-- =====================================================================================
-- Migration 0011 · Compensation decisions (docs/25)
--
-- Applies the owner's Module 04 review of 27 and 28 October 2026 (claude/review/04-compensation-decisions.md). Every
-- rule is the organization's, starting from CanDo's pre-filled suggestions; the law and the collective agreements
-- come first; people decide pay, through the organization's routes.
--
--   §1  Settings
--   §2  Routes for the philosophy, structures, pay decisions, incentive payouts and disclosure lists
--   §3  The compensation philosophy, and its approval before a market-based structure is approved
--   §4  Structures: approval through the route; location pay per structure; catch-up plans below the minimum
--   §5  Pay decisions: promotions, demotions, guideline exceptions, approval through the route
--   §6  Planning cycles start from the organization's settings
--   §7  Incentive plans, awards and clawbacks; basic long-term incentive tracking
--   §8  Public salary disclosure lists
--   §9  Costing bargaining proposals
--   §10 Cautions, starter routes and list values; text fields; row-level security
--
-- Run after 0010. Nothing here changes anyone's pay by itself: approved decisions load as change sets (Core HR) and
-- approved awards as one-time items (payroll), as before.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Settings (docs/25 §2)
-- -------------------------------------------------------------------------------------
INSERT INTO platform.setting_definition
  (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref, decision_status, min_value, max_value, required_keys) VALUES
 ('comp.philosophy_starter', 'compensation', 'json', NULL, '{"stance":"match","statistic":"p50"}', ARRAY['tenant','legal_entity'], false,
  'What the setup screen pre-fills in the compensation philosophy: the target position against the market. The organization edits the philosophy itself; an executive approves it before a market-based structure is approved.',
  'docs/25 §3 (R1.1)', 'decided', NULL, NULL, ARRAY['stance','statistic']),
 ('comp.manager_sees_market_ratio', 'compensation', 'boolean', NULL, 'false', ARRAY['tenant','legal_entity'], false,
  'Managers see their team''s market ratios (pay divided by the market rate). Never shown where a survey used in the pricing restricts derived results.',
  'docs/25 §8.1 (R1.3)', 'decided', NULL, NULL, NULL),
 ('comp.range_spread_by_track', 'compensation', 'json', NULL, '{"S":30,"P":40,"M":50,"E":60}', ARRAY['tenant','legal_entity'], false,
  'Range spread (percent) the structure builder starts from for grades of each career track: support, professional, management, executive. Editable for each grade.',
  'docs/25 §4.1 (R2.1)', 'decided', NULL, NULL, ARRAY['S','P','M','E']),
 ('comp.below_minimum_catch_up_months', 'compensation', 'integer', NULL, '12', ARRAY['tenant','legal_entity'], false,
  'Months within which a person paid below their range minimum is brought to the minimum; the catch-up plan''s target date.',
  'docs/25 §4.3 (R2.3)', 'decided', 0, NULL, NULL),
 ('comp.above_maximum_handling', 'compensation', 'text', '["manager_proposes","lump_sum","freeze"]', '"manager_proposes"', ARRAY['tenant','legal_entity'], false,
  'Increases for someone paid above their range maximum: the manager proposes and the route approves (no CanDo rule), or always a lump sum, or frozen.',
  'docs/25 §5.1 (R3.1)', 'decided', NULL, NULL, NULL),
 ('comp.promotion_min_increase_pct', 'compensation', 'number', NULL, '5', ARRAY['tenant','legal_entity'], false,
  'Smallest percentage increase on a promotion, on top of reaching the new range minimum.',
  'docs/25 §5.2 (R3.2)', 'decided', 0, NULL, NULL),
 ('comp.demotion_pay', 'compensation', 'text', '["keep_red_circle","phase_down","reduce_to_maximum"]', '"keep_red_circle"', ARRAY['tenant','legal_entity'], false,
  'Pay on a non-union demotion or a job reclassified down: kept and red-circled, phased down, or reduced to the new maximum. A reduction always needs the caution.',
  'docs/25 §5.3 (R3.3)', 'decided', NULL, NULL, NULL),
 ('comp.acting_pay_method', 'compensation', 'text', '["percent_above","acting_job_minimum","higher_of_percent_or_minimum","step_above"]', NULL, ARRAY['tenant','legal_entity'], false,
  'How non-union acting pay is set: a percentage above current pay, the acting job''s range minimum, the higher of the two, or the acting job''s first step above current pay. Chosen at setup; agreements keep their own rules.',
  'docs/25 §5.4 (R3.4)', 'pending', NULL, NULL, NULL),
 ('comp.acting_pay_percent', 'compensation', 'number', NULL, NULL, ARRAY['tenant','legal_entity'], false,
  'The percentage above current pay for acting pay, where the acting pay method uses one. Chosen at setup.',
  'docs/25 §5.4 (R3.4)', 'pending', 0, NULL, NULL),
 ('cycles.eligibility_starter', 'compensation', 'json', NULL, '{"excludeNegotiatedIncreases":true,"excludeHiredWithinMonths":3,"unpaidLeave":"on_return"}', ARRAY['tenant'], false,
  'Eligibility a new increase cycle starts from: union groups on negotiated increases excluded, people hired within this many months excluded, people on unpaid leave given their increase when they return. Each cycle can change it.',
  'docs/25 §6.1 (R4.1)', 'decided', NULL, NULL, ARRAY['excludeNegotiatedIncreases','excludeHiredWithinMonths','unpaidLeave']),
 ('cycles.guideline_method', 'compensation', 'text', '["matrix","range_position","across_the_board","discretion"]', '"matrix"', ARRAY['tenant'], false,
  'How a new cycle''s guidelines work: a matrix of rating and position in range (range position only where there are no ratings), range position only, the same percentage for everyone, or manager discretion within budget.',
  'docs/25 §6.2 (R4.2)', 'decided', NULL, NULL, NULL),
 ('cycles.out_of_guideline', 'compensation', 'text', '["reason_and_hr","reason_and_route","blocked"]', '"reason_and_hr"', ARRAY['tenant','legal_entity'], false,
  'A recommendation outside the guideline: needs a reason and HR''s approval as well as the route, needs a reason and the route only, or is not allowed.',
  'docs/25 §6.3 (R4.3)', 'decided', NULL, NULL, NULL),
 ('cycles.letter_release', 'compensation', 'text', '["hr_review","automatic","manager_delivers"]', '"hr_review"', ARRAY['tenant'], false,
  'How cycle letters reach employees: HR reviews and releases them to self-service, released automatically on the effective date, or given by managers and then released.',
  'docs/25 §6.4 (R4.4)', 'decided', NULL, NULL, NULL),
 ('incentives.proration', 'compensation', 'text', '["eligible_days","employed_on_payout","plan_decides"]', '"eligible_days"', ARRAY['tenant','legal_entity'], false,
  'How a new incentive plan prorates awards for hires, transfers and leaves: by eligible days in the plan year, in full if employed on the payout date, or as each plan states. Statutory leaves as the law requires.',
  'docs/25 §7.2 (R5.3)', 'decided', NULL, NULL, NULL),
 ('transparency.employee_view', 'compensation', 'json', NULL,
  '{"philosophy":"summary","marketPosition":"not_shown","ranges":"own","positionInRange":"quartile","managerRanges":"team"}', ARRAY['tenant','legal_entity'], false,
  'What employees and managers see about pay: the philosophy (not_shown, summary, full), market position (not_shown, general, by_job_group), ranges (own, own_family, all), position in range (not_shown, quartile, compa_ratio), and managers'' view of ranges (team, all).',
  'docs/25 §8.1 (R6.1)', 'decided', NULL, NULL, ARRAY['philosophy','marketPosition','ranges','positionInRange','managerRanges']),
 ('pay_gap.groups', 'compensation', 'text_array', NULL, '["gender","indigenous","racialized","disability"]', ARRAY['tenant'], false,
  'Groups pay gap analysis covers, from voluntary self-identification only and only with consent.',
  'docs/25 §8.2 (R6.2)', 'decided', NULL, NULL, NULL),
 ('privacy.min_group_size_self_id', 'compensation', 'integer', NULL, '10', ARRAY['tenant'], false,
  'Smallest group shown in any result that uses self-identification data; smaller groups are hidden. An organization can raise it, never lower it below 10.',
  'docs/25 §8.2 (R6.2); docs/22 §10.2', 'decided', 10, NULL, NULL),
 ('total_rewards.statement_mode', 'compensation', 'text', '["on_request","annual","annual_and_self_service"]', '"on_request"', ARRAY['tenant','legal_entity'], false,
  'When total rewards statements are produced: on request by HR or the employee, once a year, or once a year plus an up-to-date view in self-service.',
  'docs/25 §8.4 (R6.4)', 'decided', NULL, NULL, NULL);

-- -------------------------------------------------------------------------------------
-- 2. Routes for compensation subjects (docs/25 §2.4)
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.workflow_route DROP CONSTRAINT IF EXISTS workflow_route_subject_type_check;
ALTER TABLE platform.workflow_route ADD CONSTRAINT workflow_route_subject_type_check
  CHECK (subject_type IN ('requisition','direct_hire','offer','probation_extension','status_conversion','caution',
                          'pay_run','voluntary_deduction','banked_time_payout',
                          'comp_philosophy','pay_structure_version','comp_decision','incentive_payout','salary_disclosure'));

-- -------------------------------------------------------------------------------------
-- 3. The compensation philosophy (docs/25 §3)
-- -------------------------------------------------------------------------------------
CREATE TABLE comp.philosophy (
  tenant_id     uuid NOT NULL REFERENCES platform.tenant,
  philosophy_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  valid_period  daterange NOT NULL,
  target        jsonb NOT NULL,                       -- {"default":{"stance":"match","statistic":"p50"},"byJobGroup":{"EXE":{"stance":"lead","statistic":"p75"}}}
  pay_mix       jsonb,                                -- {"base":..,"variable":..,"benefits":..}
  progression   text,                                 -- role of performance, seniority and skills
  notes_en      text,
  notes_fr      text,
  submitted_by  uuid REFERENCES platform.app_user,
  route_id      uuid REFERENCES platform.workflow_route,
  status        text NOT NULL CHECK (status IN ('draft','approved','superseded')),
  approved_at   timestamptz,
  CONSTRAINT philosophy_target_default CHECK (jsonb_typeof(target -> 'default') = 'object'),
  CONSTRAINT philosophy_approved_dated CHECK (status = 'draft' OR approved_at IS NOT NULL),
  EXCLUDE USING gist (tenant_id WITH =, valid_period WITH &&) WHERE (status = 'approved')
);
CREATE FUNCTION comp.check_philosophy() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved')
     AND (NEW.route_id IS NULL OR NEW.submitted_by IS NULL
          OR NOT platform.route_complete(NEW.route_id, 'comp_philosophy', NEW.philosophy_id, NEW.submitted_by, NULL)) THEN
    RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the philosophy''s route is not complete' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER philosophy_check BEFORE INSERT OR UPDATE ON comp.philosophy
  FOR EACH ROW EXECUTE FUNCTION comp.check_philosophy();

CREATE FUNCTION comp.philosophy_approved_on(p_tenant uuid, p_on date) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM comp.philosophy p WHERE p.tenant_id = p_tenant AND p.status = 'approved' AND p.valid_period @> p_on)
$$;

-- -------------------------------------------------------------------------------------
-- 4. Structures (docs/25 §4)
-- -------------------------------------------------------------------------------------
ALTER TABLE comp.pay_structure_version
  ADD COLUMN submitted_by uuid REFERENCES platform.app_user,
  ADD COLUMN route_id     uuid REFERENCES platform.workflow_route;

-- A structure version is approved only through its route; a market-based one also needs an approved philosophy
CREATE FUNCTION comp.check_structure_approval() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status = 'draft' THEN
    IF NEW.route_id IS NULL OR NEW.submitted_by IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a structure version is approved through its route, naming who submitted it' USING ERRCODE = 'check_violation';
    END IF;
    IF NOT platform.route_complete(NEW.route_id, 'pay_structure_version', NEW.structure_version_id, NEW.submitted_by, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the structure version''s route is not complete' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.pricing_run_id IS NOT NULL AND NOT comp.philosophy_approved_on(NEW.tenant_id, lower(NEW.valid_period)) THEN
      RAISE EXCEPTION 'PHILOSOPHY_NOT_APPROVED: a market-based structure needs an approved compensation philosophy on %', lower(NEW.valid_period)
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pay_structure_version_approval BEFORE UPDATE OF status ON comp.pay_structure_version
  FOR EACH ROW EXECUTE FUNCTION comp.check_structure_approval();

-- Location pay: each structure says whether it uses ranges per location group or a premium for the person
ALTER TABLE comp.pay_structure
  ADD COLUMN location_method text NOT NULL DEFAULT 'none' CHECK (location_method IN ('none','location_ranges','location_premium'));
ALTER TABLE comp.pay_grade ADD COLUMN location_group text;          -- set on every grade of a location_ranges structure
ALTER TABLE comp.pay_grade DROP CONSTRAINT IF EXISTS pay_grade_structure_version_id_grade_code_key;
CREATE UNIQUE INDEX pay_grade_code_location ON comp.pay_grade (structure_version_id, grade_code, coalesce(location_group, ''));
ALTER TABLE comp.pay_grade DROP CONSTRAINT IF EXISTS pay_grade_structure_version_id_rank_key;
CREATE UNIQUE INDEX pay_grade_rank_location ON comp.pay_grade (structure_version_id, rank, coalesce(location_group, ''));
CREATE FUNCTION comp.check_grade_location() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE m text;
BEGIN
  SELECT s.location_method INTO m FROM comp.pay_structure s JOIN comp.pay_structure_version v ON v.structure_id = s.structure_id
   WHERE v.structure_version_id = NEW.structure_version_id;
  IF (m = 'location_ranges') <> (NEW.location_group IS NOT NULL) THEN
    RAISE EXCEPTION 'LOCATION_GROUP_MISMATCH: grades of a structure with ranges per location name their location group, and only those'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER pay_grade_location_check BEFORE INSERT OR UPDATE OF location_group ON comp.pay_grade
  FOR EACH ROW EXECUTE FUNCTION comp.check_grade_location();

-- Below the minimum: a catch-up plan with a target date from the organization's setting
CREATE TABLE comp.range_catch_up (
  tenant_id      uuid NOT NULL,
  catch_up_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id  uuid NOT NULL REFERENCES core.assignment,
  range_id       uuid NOT NULL REFERENCES comp.salary_range,
  flagged_on     date NOT NULL,
  gap_amount     numeric(14,2) NOT NULL CHECK (gap_amount > 0),
  target_date    date NOT NULL,
  status         text NOT NULL CHECK (status IN ('open','met','cancelled')),
  closed_reason  text,
  CONSTRAINT catch_up_cancel_reason CHECK (status <> 'cancelled' OR coalesce(length(btrim(closed_reason)), 0) > 0)
);
CREATE FUNCTION comp.fill_catch_up_target() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le uuid;
BEGIN
  IF NEW.target_date IS NULL THEN
    SELECT e.legal_entity_id INTO le FROM core.assignment a JOIN core.employment e ON e.employment_id = a.employment_id
     WHERE a.assignment_id = NEW.assignment_id;
    NEW.target_date := (NEW.flagged_on
      + make_interval(months => platform.setting_number(NEW.tenant_id, 'comp.below_minimum_catch_up_months', NEW.flagged_on, le)::int))::date;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER a10_catch_up_target BEFORE INSERT ON comp.range_catch_up
  FOR EACH ROW EXECUTE FUNCTION comp.fill_catch_up_target();

-- -------------------------------------------------------------------------------------
-- 5. Pay decisions (docs/25 §5, §6.3)
-- -------------------------------------------------------------------------------------
UPDATE ref.list_definition SET categories = categories || ARRAY['demotion','acting','catch_up']
 WHERE list_code = 'comp_decision_kind' AND NOT categories @> ARRAY['demotion'];
INSERT INTO ref.list_starter (list_code, code, category, rank, name_en, name_fr, attributes) VALUES
 ('comp_decision_kind', 'demotion', 'demotion', 8, 'Demotion or reclassification down', 'Rétrogradation ou reclassement à la baisse', '{}'),
 ('comp_decision_kind', 'acting',   'acting',   9, 'Acting pay', 'Rémunération d''intérim', '{}'),
 ('comp_decision_kind', 'catch_up', 'catch_up', 10, 'Catch-up to range minimum', 'Rattrapage au minimum de l''échelle', '{}');

ALTER TABLE comp.decision
  ADD COLUMN requested_by      uuid REFERENCES platform.app_user,
  ADD COLUMN route_id          uuid REFERENCES platform.workflow_route,
  ADD COLUMN current_rate      numeric(14,2) CHECK (current_rate > 0),
  ADD COLUMN new_rate          numeric(14,2) CHECK (new_rate > 0),
  ADD COLUMN new_range_minimum numeric(14,2),
  ADD COLUMN guideline_percent numeric(6,3),
  ADD COLUMN out_of_guideline  boolean NOT NULL DEFAULT false,
  ADD COLUMN reason            text,
  ADD COLUMN catch_up_id       uuid REFERENCES comp.range_catch_up;

CREATE FUNCTION comp.decision_category(p_tenant uuid, p_kind text) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT category FROM core.list_value WHERE tenant_id = p_tenant AND list_code = 'comp_decision_kind' AND code = p_kind
$$;

CREATE FUNCTION comp.check_decision() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE cat text; le uuid; rule text; pct numeric;
BEGIN
  cat := comp.decision_category(NEW.tenant_id, NEW.kind);
  SELECT e.legal_entity_id INTO le FROM core.assignment a JOIN core.employment e ON e.employment_id = a.employment_id
   WHERE a.assignment_id = NEW.assignment_id;

  -- A promotion reaches the new minimum and the organization's minimum percentage (R3.2)
  IF cat = 'promotion' THEN
    IF NEW.current_rate IS NULL OR NEW.new_rate IS NULL OR NEW.new_range_minimum IS NULL THEN
      RAISE EXCEPTION 'INPUT_REQUIRED: a promotion states the current rate, the new rate and the new range minimum' USING ERRCODE = 'check_violation';
    END IF;
    pct := platform.setting_number(NEW.tenant_id, 'comp.promotion_min_increase_pct', NEW.effective_date, le);
    IF NEW.new_rate < NEW.new_range_minimum OR (NEW.new_rate - NEW.current_rate) * 100 < pct * NEW.current_rate THEN
      RAISE EXCEPTION 'PROMOTION_BELOW_RULE: a promotion pays at least the new minimum (%) and at least % percent more', NEW.new_range_minimum, pct
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  -- Outside the guideline: a reason, or not at all where the organization blocks it (R4.3)
  IF NEW.out_of_guideline THEN
    rule := platform.setting_text(NEW.tenant_id, 'cycles.out_of_guideline', NEW.effective_date, le);
    IF rule = 'blocked' THEN
      RAISE EXCEPTION 'OUT_OF_GUIDELINE_BLOCKED: the organization does not allow recommendations outside the guideline' USING ERRCODE = 'check_violation';
    END IF;
    IF coalesce(length(btrim(NEW.reason)), 0) = 0 THEN
      RAISE EXCEPTION 'CYCLE_EXCEPTION_REASON_REQUIRED: a recommendation outside the guideline states why' USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved') THEN
    IF NEW.route_id IS NULL OR NEW.requested_by IS NULL
       OR NOT platform.route_complete(NEW.route_id, 'comp_decision', NEW.decision_id, NEW.requested_by, NULL) THEN
      RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the pay decision''s route is not complete' USING ERRCODE = 'check_violation';
    END IF;
    IF NEW.out_of_guideline AND rule = 'reason_and_hr'
       AND NOT EXISTS (SELECT 1 FROM platform.approval_task t
                        WHERE t.subject_type = 'comp_decision' AND t.subject_id = NEW.decision_id AND t.status = 'approved'
                          AND t.capability = 'hr' AND t.decided_by IS NOT NULL AND t.decided_by <> NEW.requested_by) THEN
      RAISE EXCEPTION 'HR_APPROVAL_REQUIRED: HR approves a recommendation outside the guideline' USING ERRCODE = 'check_violation';
    END IF;
    -- Pay reduced on a demotion: the caution, with its reason, before approval (R3.3)
    IF cat = 'demotion' AND NEW.new_rate IS NOT NULL AND NEW.current_rate IS NOT NULL AND NEW.new_rate < NEW.current_rate
       AND NOT platform.caution_cleared(NEW.tenant_id, 'comp.pay_reduced_on_demotion', 'comp_decision', NEW.decision_id) THEN
      RAISE EXCEPTION 'CAUTION_NOT_ACKNOWLEDGED: comp.pay_reduced_on_demotion' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER decision_check BEFORE INSERT OR UPDATE ON comp.decision
  FOR EACH ROW EXECUTE FUNCTION comp.check_decision();

-- -------------------------------------------------------------------------------------
-- 6. Planning cycles start from the organization's settings (docs/25 §6)
-- -------------------------------------------------------------------------------------
ALTER TABLE comp.cycle
  ADD COLUMN eligibility      jsonb,
  ADD COLUMN guideline_method text CHECK (guideline_method IN ('matrix','range_position','across_the_board','discretion')),
  ADD COLUMN letter_release   text CHECK (letter_release IN ('hr_review','automatic','manager_delivers'));
ALTER TABLE comp.decision
  ADD COLUMN letter_released_by uuid REFERENCES platform.app_user,
  ADD COLUMN letter_released_at timestamptz;

-- -------------------------------------------------------------------------------------
-- 7. Incentive plans, awards and clawbacks; basic long-term incentive tracking (docs/25 §7)
-- -------------------------------------------------------------------------------------
CREATE TABLE comp.incentive_plan (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  plan_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL,
  name_en     text NOT NULL,
  name_fr     text,
  kind        text NOT NULL CHECK (kind IN ('annual_bonus','commission','spot','retention','signing','profit_sharing','long_term')),
  plan_year   daterange,
  proration   text CHECK (proration IN ('eligible_days','employed_on_payout','plan_decides')),
  rules       jsonb NOT NULL,                          -- targets, metrics and weights; commission rates, tiers and caps
  clawback    jsonb,                                   -- {"months":12,"shareRecovered":"1"} for signing and retention bonuses
  status      text NOT NULL CHECK (status IN ('draft','active','retired')),
  UNIQUE (tenant_id, code),
  CONSTRAINT incentive_rules_object CHECK (jsonb_typeof(rules) = 'object')
);

CREATE TABLE comp.incentive_award (
  tenant_id        uuid NOT NULL,
  award_id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id          uuid NOT NULL REFERENCES comp.incentive_plan,
  assignment_id    uuid NOT NULL REFERENCES core.assignment,          -- the position it is for (docs/24 §8.2)
  amount           numeric(14,2) NOT NULL CHECK (amount > 0),
  calculation      jsonb,                                            -- results, proration and the arithmetic, for the statement
  requested_by     uuid NOT NULL REFERENCES platform.app_user,
  route_id         uuid REFERENCES platform.workflow_route,
  status           text NOT NULL CHECK (status IN ('proposed','approved','rejected','paid','cancelled')),
  one_time_item_id uuid REFERENCES payroll.one_time_item,
  clawback_until   date,
  clawback_authorization_id uuid REFERENCES payroll.recovery_authorization   -- the employee's signed bonus agreement
);
CREATE FUNCTION comp.check_incentive_award() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.clawback_until IS NOT NULL AND NEW.clawback_authorization_id IS NULL THEN
    RAISE EXCEPTION 'CLAWBACK_NOT_SIGNED: a clawback needs the employee''s signed bonus agreement' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'approved')
     AND (NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'incentive_payout', NEW.award_id, NEW.requested_by, NULL)) THEN
    RAISE EXCEPTION 'ROUTE_APPROVALS_MISSING: the payout''s route is not complete' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER incentive_award_check BEFORE INSERT OR UPDATE ON comp.incentive_award
  FOR EACH ROW EXECUTE FUNCTION comp.check_incentive_award();

-- A signed bonus agreement is a recovery authorization of its own kind (docs/24 §6.4)
ALTER TABLE payroll.recovery_authorization DROP CONSTRAINT IF EXISTS recovery_authorization_kind_check;
ALTER TABLE payroll.recovery_authorization ADD CONSTRAINT recovery_authorization_kind_check
  CHECK (kind IN ('advance','equipment','training','loan','bonus_clawback','other'));

-- Long-term incentives: grants and vesting tracked; the taxable benefit is sent to payroll when it arises; no valuations
CREATE TABLE comp.lti_grant (
  tenant_id      uuid NOT NULL,
  grant_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id        uuid NOT NULL REFERENCES comp.incentive_plan,
  employment_id  uuid NOT NULL REFERENCES core.employment,
  instrument     text NOT NULL CHECK (instrument IN ('stock_option','rsu','psu','phantom_unit','other')),
  grant_date     date NOT NULL,
  units          numeric(18,4) NOT NULL CHECK (units > 0),
  exercise_price numeric(14,4) CHECK (exercise_price >= 0),
  vesting        jsonb NOT NULL,                    -- [{"date":"2027-06-30","units":"250"}, …]
  status         text NOT NULL CHECK (status IN ('granted','vesting','vested','exercised','forfeited','expired')),
  document_id    uuid REFERENCES platform.document,
  CONSTRAINT lti_vesting_array CHECK (jsonb_typeof(vesting) = 'array')
);
CREATE FUNCTION comp.check_lti_plan() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT kind FROM comp.incentive_plan WHERE plan_id = NEW.plan_id) <> 'long_term' THEN
    RAISE EXCEPTION 'LTI_PLAN_REQUIRED: a long-term incentive grant belongs to a long-term plan' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER lti_grant_plan_check BEFORE INSERT OR UPDATE OF plan_id ON comp.lti_grant
  FOR EACH ROW EXECUTE FUNCTION comp.check_lti_plan();

-- -------------------------------------------------------------------------------------
-- 8. Public salary disclosure lists (docs/25 §10.1): drafted from amounts paid, reviewed, approved, then published
-- -------------------------------------------------------------------------------------
CREATE TABLE compliance.salary_disclosure (
  tenant_id       uuid NOT NULL,
  disclosure_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id uuid NOT NULL REFERENCES core.legal_entity,
  statute         text NOT NULL,                     -- a key of rules/compensation/salary-disclosure.json
  year            smallint NOT NULL,
  document_id     uuid REFERENCES platform.document, -- the drafted list
  prepared_by     uuid NOT NULL REFERENCES platform.app_user,
  route_id        uuid REFERENCES platform.workflow_route,
  status          text NOT NULL CHECK (status IN ('draft','approved','published','withdrawn')),
  published_at    timestamptz,
  UNIQUE (legal_entity_id, statute, year)
);
CREATE FUNCTION compliance.check_salary_disclosure() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status IN ('approved','published') AND (TG_OP = 'INSERT' OR OLD.status NOT IN ('approved','published'))
     AND (NEW.route_id IS NULL OR NOT platform.route_complete(NEW.route_id, 'salary_disclosure', NEW.disclosure_id, NEW.prepared_by, NULL)) THEN
    RAISE EXCEPTION 'DISCLOSURE_NOT_APPROVED: the list is reviewed and approved through its route before it is published' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.status = 'published' AND NEW.published_at IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: a published list records when it was published' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER salary_disclosure_check BEFORE INSERT OR UPDATE ON compliance.salary_disclosure
  FOR EACH ROW EXECUTE FUNCTION compliance.check_salary_disclosure();

-- -------------------------------------------------------------------------------------
-- 9. Costing bargaining proposals (docs/25 §10.3): models only; pay changes only through a ratified agreement version
-- -------------------------------------------------------------------------------------
CREATE TABLE comp.bargaining_scenario (
  tenant_id            uuid NOT NULL,
  scenario_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agreement_id         text NOT NULL,
  name                 text NOT NULL,
  term                 daterange NOT NULL,
  proposals            jsonb NOT NULL,             -- general increases, step changes, premiums, retro, by year
  results              jsonb,                      -- cost by year and in total, from live pay, benefits and schedules, with the data date
  prepared_by          uuid NOT NULL REFERENCES platform.app_user,
  shared_at            timestamptz,                -- shared with labour relations
  status               text NOT NULL CHECK (status IN ('draft','shared','ratified','withdrawn')),
  ratified_version     int,                        -- the agreement version that carries the ratified terms
  FOREIGN KEY (tenant_id, agreement_id) REFERENCES core.agreement (tenant_id, agreement_id),
  FOREIGN KEY (tenant_id, agreement_id, ratified_version) REFERENCES core.agreement_version (tenant_id, agreement_id, version),
  CONSTRAINT scenario_ratified_version CHECK (status <> 'ratified' OR ratified_version IS NOT NULL),
  CONSTRAINT scenario_shared_dated CHECK (status NOT IN ('shared','ratified') OR shared_at IS NOT NULL)
);

-- -------------------------------------------------------------------------------------
-- 10. Cautions, approvals, starter routes and list values; text fields; row-level security
-- -------------------------------------------------------------------------------------
INSERT INTO ref.caution (caution_code, area, name_en, name_fr, message_en, message_fr, reason_always, shows_law, decision_ref) VALUES
 ('comp.pay_reduced_on_demotion', 'compensation', 'Pay reduced on a demotion', 'Rémunération réduite lors d''une rétrogradation',
  'Reducing someone''s pay without their agreement can be treated as constructive dismissal. The organization''s rule is to keep their pay and red-circle it. State why you are reducing it.',
  'Réduire la rémunération d''une personne sans son accord peut être considéré comme un congédiement déguisé. La règle de l''organisation est de maintenir sa rémunération et de la bloquer (cercle rouge). Indiquez pourquoi vous la réduisez.',
  true, true, 'docs/25 §5.3 (R3.3)');

-- No one approves their own philosophy, structure version, pay decision, payout or disclosure list (adds to 0010 §8)
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
  END IF;
  IF NEW.decided_by = requester THEN
    RAISE EXCEPTION 'SELF_APPROVAL: the requester cannot approve their own %', replace(NEW.subject_type, '_', ' ') USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

INSERT INTO ref.workflow_route_starter (code, subject_type, name_en, name_fr, conditions, priority, decision_ref) VALUES
 ('comp_philosophy', 'comp_philosophy', 'Compensation philosophy', 'Philosophie de rémunération', '{}', 10, 'docs/25 §3 (R1.1)'),
 ('pay_structure_version', 'pay_structure_version', 'Pay structure approval', 'Approbation de la structure salariale', '{}', 10, 'docs/25 §4.2 (R2.2)'),
 ('comp_decision', 'comp_decision', 'Pay decision', 'Décision salariale', '{}', 10, 'docs/25 §5, §6.3 (R3, R4.3)'),
 ('incentive_payout', 'incentive_payout', 'Incentive payout', 'Versement incitatif', '{}', 10, 'docs/25 §7.1 (R5.1)'),
 ('salary_disclosure', 'salary_disclosure', 'Salary disclosure list', 'Liste de divulgation des traitements', '{}', 10, 'docs/25 §10.1 (R7.1)');
INSERT INTO ref.workflow_route_step_starter (route_code, step_no, approver_kind, capability, mode, min_approvals, purpose_en, purpose_fr) VALUES
 ('comp_philosophy', 1, 'capability', 'executive', 'any', 1, 'Executive approval', 'Approbation de la direction'),
 ('pay_structure_version', 1, 'capability', 'hr', 'any', 1, 'HR review', 'Examen des RH'),
 ('pay_structure_version', 2, 'capability', 'finance', 'any', 1, 'Cost review', 'Examen des coûts'),
 ('pay_structure_version', 3, 'capability', 'executive', 'any', 1, 'Executive approval', 'Approbation de la direction'),
 ('comp_decision', 1, 'capability', 'manager', 'any', 1, 'Approving manager', 'Gestionnaire approbateur'),
 ('comp_decision', 2, 'capability', 'hr', 'any', 1, 'HR approval', 'Approbation des RH'),
 ('incentive_payout', 1, 'capability', 'manager', 'any', 1, 'Manager approval', 'Approbation du gestionnaire'),
 ('incentive_payout', 2, 'capability', 'hr', 'any', 1, 'HR approval', 'Approbation des RH'),
 ('incentive_payout', 3, 'capability', 'finance', 'any', 1, 'Finance approval', 'Approbation des finances'),
 ('salary_disclosure', 1, 'capability', 'hr', 'any', 1, 'HR review', 'Examen des RH'),
 ('salary_disclosure', 2, 'capability', 'finance', 'any', 1, 'Finance review and approval', 'Examen et approbation des finances');

-- Business columns that start from a setting (0008 §2)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('comp','cycle','eligibility','setting','cycles.eligibility_starter'),
      ('comp','cycle','guideline_method','setting','cycles.guideline_method'),
      ('comp','cycle','letter_release','setting','cycles.letter_release'),
      ('comp','incentive_plan','proration','setting','incentives.proration')
    ) AS x(s, t, c, src, k)
  LOOP
    INSERT INTO platform.column_default (table_schema, table_name, column_name, source, setting_key) VALUES (r.s, r.t, r.c, r.src, r.k);
  END LOOP;
END $$;
-- comp.cycle already fills merit_rating_source from settings (0008); its trigger now fills these too
CREATE TRIGGER a00_fill_from_settings BEFORE INSERT ON comp.incentive_plan FOR EACH ROW EXECUTE FUNCTION platform.fill_from_settings();
-- New cycles and plans always carry these; cycles from before 0011 keep NULL until their next change sets them
CREATE FUNCTION comp.check_cycle_settings() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.eligibility IS NULL OR NEW.guideline_method IS NULL OR NEW.letter_release IS NULL THEN
    RAISE EXCEPTION 'INPUT_REQUIRED: a cycle states its eligibility, guideline method and letter release' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER cycle_settings_check BEFORE INSERT OR UPDATE ON comp.cycle
  FOR EACH ROW EXECUTE FUNCTION comp.check_cycle_settings();
ALTER TABLE comp.incentive_plan ALTER COLUMN proration SET NOT NULL;

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
      ('comp','philosophy'), ('comp','range_catch_up'), ('comp','incentive_plan'), ('comp','incentive_award'), ('comp','lti_grant'),
      ('compliance','salary_disclosure'), ('comp','bargaining_scenario')) AS x(s, t) LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.s, r.t);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$, r.s, r.t);
  END LOOP;
END $$;

-- Existing organizations get the new starter routes and list values (as in 0009, skipping one whose required data
-- language has no starter text)
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
      RAISE NOTICE 'organization %: starter compensation routes and decision kinds not copied because % is required for its data; add them with their texts (docs/25 §11)', t.tenant_id, langs;
    END IF;
  END LOOP;
END $$;

-- Grants follow 0002_roles: cando_app gets SELECT, INSERT and UPDATE on the new tenant tables and EXECUTE on the new
-- functions. Compensation tables keep the role checks of 0005 §12 in the API (comp_admin, comp_analyst).
