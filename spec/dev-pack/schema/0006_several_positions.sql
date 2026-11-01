-- =====================================================================================
-- CanDo HRIS — migration 0006: people in several positions
-- Approval policy and coverage when a position has two managers, approval parts for
-- requests split across positions and managers, pay items and duty rates per position,
-- one-time payments per position, review sections per position, competency assessments
-- in a position's context, benefit plans per agreement with coordination of benefits,
-- end reasons, and benefit-change rules and decisions when one position ends.
-- Applies after 0001 to 0005. Specification: docs/20-people-in-several-positions.md.
-- Conventions as in 0001: tenant_id + RLS on every tenant table, effective-dated rows
-- with valid_period and sys_period, change_set_id on business rows.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- End reasons (§6.2): the tenant's own list, each mapped to a category the rules use
-- -------------------------------------------------------------------------------------
CREATE TABLE core.end_reason (
  tenant_id          uuid NOT NULL,
  code               text NOT NULL,
  name_en            text NOT NULL,
  name_fr            text,
  category           text NOT NULL CHECK (category IN ('resignation','retirement','end_of_term','layoff','position_eliminated',
                                                      'termination_without_cause','termination_with_cause','reduction_by_employer',
                                                      'transfer','death','other')),
  employer_initiated boolean NOT NULL,
  applies_to         text NOT NULL DEFAULT 'both' CHECK (applies_to IN ('assignment','employment','both')),
  status             text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  PRIMARY KEY (tenant_id, code)
);
ALTER TABLE core.assignment_version
  ADD CONSTRAINT assignment_version_end_reason_fk FOREIGN KEY (tenant_id, end_reason)
  REFERENCES core.end_reason (tenant_id, code) NOT VALID;    -- rows from before 0006 are mapped, then VALIDATE

-- -------------------------------------------------------------------------------------
-- Approvals when a position has several managers (§2)
-- -------------------------------------------------------------------------------------
-- How a position's (or one assignment's) requests are approved, per capability
CREATE TABLE core.approval_policy (
  tenant_id     uuid NOT NULL,
  version_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_type   text NOT NULL CHECK (target_type IN ('position','assignment')),
  target_id     uuid NOT NULL,
  capability    text NOT NULL CHECK (capability IN ('leave','time','overtime','expense','availability')),
  mode          text NOT NULL DEFAULT 'by_coverage' CHECK (mode IN ('by_coverage','all','any')),
  overlap       text NOT NULL DEFAULT 'all' CHECK (overlap IN ('all','any')),     -- hours two managers both cover
  uncovered     text NOT NULL DEFAULT 'line' CHECK (uncovered IN ('line','hr')),  -- hours no manager covers
  valid_period  daterange NOT NULL,
  sys_period    tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id uuid NOT NULL,
  EXCLUDE USING gist (target_type WITH =, target_id WITH =, capability WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

-- The days, hours and places each manager supervises on a position (or one assignment)
CREATE TABLE core.approval_coverage (
  tenant_id       uuid NOT NULL,
  version_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  target_type     text NOT NULL CHECK (target_type IN ('position','assignment')),
  target_id       uuid NOT NULL,
  approver        text NOT NULL CHECK (approver IN ('line','relationship')),
  relationship_id uuid REFERENCES core.assignment_relationship,
  capabilities    text[] NOT NULL DEFAULT ARRAY['leave','time','overtime']::text[],
  days_of_week    smallint[],                                       -- ISO 1 = Monday … 7 = Sunday; the shift's start day
  time_windows    jsonb,                                            -- [["08:00","14:00"], ["22:00","06:00"]] local time
  location_ids    uuid[],
  valid_period    daterange NOT NULL,
  sys_period      tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id   uuid NOT NULL,
  CHECK ((approver = 'line') = (relationship_id IS NULL)),
  CHECK (days_of_week IS NULL OR (days_of_week <@ ARRAY[1,2,3,4,5,6,7]::smallint[] AND cardinality(days_of_week) >= 1)),
  CHECK (days_of_week IS NOT NULL OR time_windows IS NOT NULL OR location_ids IS NOT NULL),
  CHECK (capabilities <@ ARRAY['leave','time','overtime','expense','availability']::text[]),
  EXCLUDE USING gist (target_type WITH =, target_id WITH =, approver WITH =,
                      (coalesce(relationship_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period))
);

CREATE FUNCTION core.check_approval_coverage() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.time_windows IS NOT NULL AND (jsonb_typeof(NEW.time_windows) <> 'array' OR EXISTS (
       SELECT 1 FROM jsonb_array_elements(NEW.time_windows) w
       WHERE jsonb_typeof(w) <> 'array' OR jsonb_array_length(w) <> 2
          OR NOT (w->>0 ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' AND w->>1 ~ '^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$')
          OR w->>0 = w->>1)) THEN
    RAISE EXCEPTION 'COVERAGE_WINDOW_INVALID: time windows are [["HH:MM","HH:MM"], …] with different start and end'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER approval_coverage_check BEFORE INSERT OR UPDATE ON core.approval_coverage
  FOR EACH ROW EXECUTE FUNCTION core.check_approval_coverage();

-- One part of a request: the hours of one assignment that one manager (or a set of managers) decides (§2.4, §3)
CREATE TABLE core.approval_part (
  tenant_id            uuid NOT NULL,
  part_id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type         text NOT NULL CHECK (subject_type IN ('leave_request','timesheet','overtime_preauth','availability_change')),
  subject_id           uuid NOT NULL,
  assignment_id        uuid NOT NULL REFERENCES core.assignment,
  seq                  smallint NOT NULL,
  requester_person_id  uuid NOT NULL REFERENCES core.person,
  approvers            uuid[] NOT NULL,                  -- approvers' assignments
  rule                 text NOT NULL CHECK (rule IN ('all','any')),
  minutes              integer NOT NULL CHECK (minutes >= 0),
  intervals            jsonb NOT NULL DEFAULT '[]'::jsonb,
  routed_by            text NOT NULL CHECK (routed_by IN ('coverage','uncovered_line','uncovered_hr','all','any','escalated')),
  status               text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','declined','cancelled')),
  decisions            jsonb NOT NULL DEFAULT '[]'::jsonb, -- [{ "approver": "<assignment>", "decision": "approve" | "decline", "at": "…" }]
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (subject_type, subject_id, assignment_id, seq),
  CHECK (cardinality(approvers) >= 1),
  CHECK (jsonb_typeof(decisions) = 'array')
);
CREATE INDEX approval_part_inbox ON core.approval_part USING gin (approvers) WHERE status = 'pending';

CREATE FUNCTION core.part_status(p_rule text, p_approvers uuid[], p_decisions jsonb) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  WITH d AS (SELECT (e->>'approver')::uuid AS approver, e->>'decision' AS decision, ord
             FROM jsonb_array_elements(p_decisions) WITH ORDINALITY AS t(e, ord))
  SELECT CASE
    WHEN p_rule = 'any' THEN coalesce((SELECT CASE decision WHEN 'approve' THEN 'approved' ELSE 'declined' END
                                       FROM d ORDER BY ord LIMIT 1), 'pending')
    WHEN EXISTS (SELECT 1 FROM d WHERE decision = 'decline') THEN 'declined'
    WHEN (SELECT count(DISTINCT approver) FROM d WHERE decision = 'approve' AND approver = ANY (p_approvers))
         = cardinality(p_approvers) THEN 'approved'
    ELSE 'pending' END
$$;

CREATE FUNCTION core.roll_up(p_statuses text[]) RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_statuses <@ ARRAY['cancelled'] THEN 'cancelled'
    WHEN array_remove(p_statuses, 'cancelled') <@ ARRAY['approved'] THEN 'approved'
    WHEN array_remove(p_statuses, 'cancelled') <@ ARRAY['declined'] THEN 'declined'
    WHEN 'pending' = ANY (p_statuses) THEN 'pending'
    ELSE 'partially_approved' END
$$;

CREATE FUNCTION core.guard_approval_part() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE self_hit uuid; bad text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'APPROVAL_PART_IMMUTABLE: cancel it instead' USING ERRCODE = 'check_violation';
  END IF;
  IF (SELECT count(DISTINCT x) FROM unnest(NEW.approvers) x) <> cardinality(NEW.approvers) THEN
    RAISE EXCEPTION 'APPROVERS_DUPLICATED' USING ERRCODE = 'check_violation';
  END IF;
  -- nobody approves their own request, even from another of their positions (docs/17 §5.2)
  SELECT x INTO self_hit FROM unnest(NEW.approvers) x
    JOIN core.assignment a ON a.assignment_id = x JOIN core.employment e ON e.employment_id = a.employment_id
    WHERE e.person_id = NEW.requester_person_id LIMIT 1;
  IF self_hit IS NOT NULL THEN
    RAISE EXCEPTION 'SELF_APPROVAL: approver % is the requester; route the part to that position''s own approver', self_hit
      USING ERRCODE = 'check_violation';
  END IF;
  SELECT string_agg(e->>'approver', ', ') INTO bad FROM jsonb_array_elements(NEW.decisions) e
    WHERE NOT ((e->>'approver')::uuid = ANY (NEW.approvers)) OR e->>'decision' NOT IN ('approve','decline');
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'DECISION_NOT_ALLOWED: % is not an approver of this part', bad USING ERRCODE = 'check_violation';
  END IF;
  IF (SELECT count(*) FROM jsonb_array_elements(NEW.decisions)) <> (SELECT count(DISTINCT e->>'approver') FROM jsonb_array_elements(NEW.decisions) e) THEN
    RAISE EXCEPTION 'DECISION_TWICE: each approver decides once' USING ERRCODE = 'check_violation';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status IN ('declined','cancelled') OR (OLD.status = 'approved' AND NEW.status <> 'cancelled') THEN
      RAISE EXCEPTION 'APPROVAL_PART_IMMUTABLE: part is %', OLD.status USING ERRCODE = 'check_violation';
    END IF;
    IF (to_jsonb(NEW) - ARRAY['status','decisions']) <> (to_jsonb(OLD) - ARRAY['status','decisions'])
       OR NOT (jsonb_array_length(NEW.decisions) >= jsonb_array_length(OLD.decisions)
               AND (SELECT jsonb_agg(e ORDER BY ord) FROM jsonb_array_elements(NEW.decisions) WITH ORDINALITY t(e, ord)
                    WHERE ord <= jsonb_array_length(OLD.decisions)) IS NOT DISTINCT FROM
                   (CASE WHEN jsonb_array_length(OLD.decisions) = 0 THEN NULL ELSE OLD.decisions END)) THEN
      RAISE EXCEPTION 'DECISIONS_APPEND_ONLY: only new decisions or a cancellation can be added' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  IF NEW.status <> 'cancelled' THEN
    NEW.status := core.part_status(NEW.rule, NEW.approvers, NEW.decisions);
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER approval_part_guard BEFORE INSERT OR UPDATE OR DELETE ON core.approval_part
  FOR EACH ROW EXECUTE FUNCTION core.guard_approval_part();

-- A component can now be partly approved (one manager's days approved, the other's declined)
ALTER TABLE timeleave.leave_request_component DROP CONSTRAINT IF EXISTS leave_request_component_status_check;
ALTER TABLE timeleave.leave_request_component
  ADD CONSTRAINT leave_request_component_status_check
  CHECK (status IN ('requested','approved','partially_approved','declined','cancelled','taken'));

-- Leave request and component statuses follow their parts
CREATE FUNCTION core.roll_up_leave_request() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE c text; r text;
BEGIN
  IF NEW.subject_type <> 'leave_request' THEN RETURN NEW; END IF;
  SELECT core.roll_up(array_agg(status)) INTO c FROM core.approval_part
    WHERE subject_type = 'leave_request' AND subject_id = NEW.subject_id AND assignment_id = NEW.assignment_id;
  UPDATE timeleave.leave_request_component SET status = CASE c WHEN 'pending' THEN 'requested' ELSE c END
    WHERE leave_request_id = NEW.subject_id AND assignment_id = NEW.assignment_id AND status <> 'taken';
  SELECT core.roll_up(array_agg(status)) INTO r FROM core.approval_part
    WHERE subject_type = 'leave_request' AND subject_id = NEW.subject_id;
  UPDATE timeleave.leave_request SET status = CASE r WHEN 'pending' THEN 'requested' ELSE r END
    WHERE leave_request_id = NEW.subject_id AND status NOT IN ('taken');
  RETURN NEW;
END $$;
CREATE TRIGGER approval_part_roll_up AFTER INSERT OR UPDATE ON core.approval_part
  FOR EACH ROW EXECUTE FUNCTION core.roll_up_leave_request();

-- -------------------------------------------------------------------------------------
-- Pay items and duty rates per position (§4)
-- -------------------------------------------------------------------------------------
CREATE TABLE payroll.duty (
  tenant_id   uuid NOT NULL,
  duty_code   text NOT NULL,                             -- e.g. DRIVING, INTERPRETING, SENIOR_ON_SHIFT, FIRST_AID
  name_en     text NOT NULL,
  name_fr     text,
  pay_code    text NOT NULL,
  status      text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  PRIMARY KEY (tenant_id, duty_code),
  FOREIGN KEY (tenant_id, pay_code) REFERENCES payroll.pay_code (tenant_id, pay_code)
);

CREATE TABLE core.assignment_pay_item (
  tenant_id      uuid NOT NULL,
  version_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pay_item_id    uuid NOT NULL,                          -- one item across its versions
  assignment_id  uuid NOT NULL REFERENCES core.assignment,
  kind           text NOT NULL CHECK (kind IN ('allowance','stipend','duty_rate','duty_premium','on_call','other')),
  pay_code       text NOT NULL,
  duty_code      text,
  basis          text NOT NULL CHECK (basis IN ('per_pay_period','per_month','per_year','per_day_worked','per_shift',
                                                'per_hour_worked','per_duty_hour','rate_for_duty_hours','percent_of_base')),
  amount         numeric(14,4),
  percent        numeric(7,4),
  applies_when   jsonb NOT NULL DEFAULT '{}'::jsonb,     -- { "requiresCredential": "DL-CLASS-4" } … checked by the time engine
  cost_target    text NOT NULL DEFAULT 'assignment' CHECK (cost_target IN ('assignment','explicit')),
  cost_lines     jsonb,                                  -- same shape as finance.cost_distribution_version.lines
  source         text NOT NULL CHECK (source IN ('agreement','policy','offer','compensation_decision','manual')),
  reason         text,
  valid_period   daterange NOT NULL,
  sys_period     tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id  uuid NOT NULL,
  FOREIGN KEY (tenant_id, pay_code) REFERENCES payroll.pay_code (tenant_id, pay_code),
  FOREIGN KEY (tenant_id, duty_code) REFERENCES payroll.duty (tenant_id, duty_code),
  CHECK ((kind IN ('duty_rate','duty_premium')) = (duty_code IS NOT NULL)),
  CHECK (kind <> 'duty_rate' OR basis = 'rate_for_duty_hours'),
  CHECK (kind <> 'duty_premium' OR basis = 'per_duty_hour'),
  CHECK ((basis = 'percent_of_base') = (percent IS NOT NULL)),
  CHECK (basis = 'percent_of_base' OR amount IS NOT NULL),
  CHECK (amount IS NULL OR amount >= 0),
  CHECK ((cost_target = 'explicit') = (cost_lines IS NOT NULL)),
  CHECK (source <> 'manual' OR reason IS NOT NULL),
  EXCLUDE USING gist (assignment_id WITH =, pay_code WITH =, (coalesce(duty_code, '')) WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period))
);
CREATE INDEX assignment_pay_item_lookup ON core.assignment_pay_item (tenant_id, assignment_id) WHERE upper_inf(sys_period);

ALTER TABLE timeleave.time_line ADD COLUMN duty_code text;
ALTER TABLE timeleave.time_line
  ADD CONSTRAINT time_line_duty_fk FOREIGN KEY (tenant_id, duty_code) REFERENCES payroll.duty (tenant_id, duty_code);

-- One-time payments name the position they belong to, or are shared by earnings (§4.3)
ALTER TABLE payroll.one_time_item
  ADD COLUMN assignment_id uuid REFERENCES core.assignment,
  ADD COLUMN allocation    text NOT NULL DEFAULT 'earnings_share' CHECK (allocation IN ('assignment','earnings_share'));
ALTER TABLE payroll.one_time_item
  ADD CONSTRAINT one_time_item_allocation_target CHECK ((allocation = 'assignment') = (assignment_id IS NOT NULL));

-- -------------------------------------------------------------------------------------
-- Reviews with a section per position (§5)
-- -------------------------------------------------------------------------------------
ALTER TABLE talent.review
  ADD COLUMN overall_method   text NOT NULL DEFAULT 'fte_weighted' CHECK (overall_method IN ('fte_weighted','primary_manager','none')),
  ADD COLUMN overall_score    numeric(4,2),
  ADD COLUMN min_section_days smallint NOT NULL DEFAULT 60 CHECK (min_section_days >= 0);

CREATE TABLE talent.review_section (
  tenant_id            uuid NOT NULL,
  section_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id            uuid NOT NULL REFERENCES talent.review,
  assignment_id        uuid NOT NULL REFERENCES core.assignment,
  owner_assignment_id  uuid NOT NULL REFERENCES core.assignment,   -- the manager who rates this section
  contributor_assignment_ids uuid[] NOT NULL DEFAULT '{}',
  fte                  numeric(6,4) NOT NULL CHECK (fte > 0),
  days_in_cycle        integer NOT NULL CHECK (days_in_cycle >= 0),
  rated                boolean NOT NULL DEFAULT true,             -- false where the agreement excludes ratings
  rating_score         numeric(4,2),
  rating_label         text,
  status               text NOT NULL DEFAULT 'not_started' CHECK (status IN ('not_started','in_progress','submitted','signed')),
  UNIQUE (review_id, assignment_id),
  CHECK (rated OR rating_score IS NULL),
  CHECK (owner_assignment_id <> assignment_id)
);

CREATE FUNCTION talent.check_review_section() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_emp uuid; v_person uuid;
BEGIN
  SELECT r.employment_id, e.person_id INTO v_emp, v_person
    FROM talent.review r JOIN core.employment e USING (employment_id) WHERE r.review_id = NEW.review_id;
  IF NOT EXISTS (SELECT 1 FROM core.assignment a WHERE a.assignment_id = NEW.assignment_id AND a.employment_id = v_emp) THEN
    RAISE EXCEPTION 'SECTION_NOT_IN_EMPLOYMENT: the section''s position belongs to another employment' USING ERRCODE = 'check_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM core.assignment a JOIN core.employment e USING (employment_id)
             WHERE a.assignment_id = ANY (NEW.contributor_assignment_ids || NEW.owner_assignment_id) AND e.person_id = v_person) THEN
    RAISE EXCEPTION 'SELF_REVIEW: a person cannot rate their own section' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER review_section_check BEFORE INSERT OR UPDATE ON talent.review_section
  FOR EACH ROW EXECUTE FUNCTION talent.check_review_section();

-- Overall score: FTE × days held, over rated sections held at least min_section_days, rounded half-up to p_step
CREATE FUNCTION talent.review_overall(p_review uuid, p_step numeric DEFAULT 1) RETURNS numeric LANGUAGE sql STABLE AS $$
  SELECT round(sum(s.fte * s.days_in_cycle * s.rating_score) / sum(s.fte * s.days_in_cycle) / p_step) * p_step
  FROM talent.review_section s JOIN talent.review r USING (review_id)
  WHERE s.review_id = p_review AND s.rated AND s.rating_score IS NOT NULL AND s.days_in_cycle >= r.min_section_days
    AND r.overall_method = 'fte_weighted'
$$;

-- Assessments made in a position's section; gaps prefer the same position's assessment (§5.3)
ALTER TABLE talent.competency_assessment
  ADD COLUMN assignment_id     uuid REFERENCES core.assignment,
  ADD COLUMN review_section_id uuid REFERENCES talent.review_section;

CREATE OR REPLACE FUNCTION talent.competency_gap(p_assignment uuid, p_as_of date,
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
    ORDER BY (x.assignment_id IS NOT DISTINCT FROM p_assignment) DESC, x.assessed_on DESC,
             (x.source = 'calibrated') DESC, x.created_at DESC LIMIT 1) asm ON true
  LEFT JOIN LATERAL (
    SELECT x.assessed_level FROM talent.competency_assessment x
    WHERE x.person_id = a.person_id AND x.framework_id = tg.framework_id AND x.competency_code = tg.competency_code
      AND x.status = 'final' AND x.source = 'self' AND x.assessed_on <= p_as_of
    ORDER BY (x.assignment_id IS NOT DISTINCT FROM p_assignment) DESC, x.assessed_on DESC, x.created_at DESC LIMIT 1) slf ON true
  ORDER BY tg.framework_id, tg.competency_code
$$;

-- Merit guidelines read the position's own section rating by default (§5.4)
ALTER TABLE comp.cycle
  ADD COLUMN merit_rating_source text NOT NULL DEFAULT 'section' CHECK (merit_rating_source IN ('section','overall'));

-- -------------------------------------------------------------------------------------
-- Benefits across agreements, coordination, and changes when one position ends (§6)
-- -------------------------------------------------------------------------------------
ALTER TABLE benefits.plan
  ADD COLUMN eligibility_scope text NOT NULL DEFAULT 'employer' CHECK (eligibility_scope IN ('employer','agreement','assignment')),
  ADD COLUMN agreement_id      text;
ALTER TABLE benefits.plan
  ADD CONSTRAINT plan_agreement_scope CHECK ((eligibility_scope = 'agreement') = (agreement_id IS NOT NULL)),
  ADD CONSTRAINT plan_agreement_fk FOREIGN KEY (tenant_id, agreement_id) REFERENCES core.agreement (tenant_id, agreement_id);

ALTER TABLE benefits.enrolment
  ADD COLUMN via_assignment_id uuid REFERENCES core.assignment,    -- the position giving eligibility (agreement and assignment scopes)
  ADD COLUMN cob_rank          smallint CHECK (cob_rank >= 1);     -- 1 = primary when two plans of one kind cover the person

CREATE FUNCTION benefits.check_enrolment_scope() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_scope text; v_agreement text;
BEGIN
  SELECT eligibility_scope, agreement_id INTO v_scope, v_agreement FROM benefits.plan WHERE plan_id = NEW.plan_id;
  IF v_scope IN ('agreement','assignment') AND NEW.via_assignment_id IS NULL THEN
    RAISE EXCEPTION 'ENROLMENT_NEEDS_ASSIGNMENT: a % plan names the position that makes the person eligible', v_scope
      USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.via_assignment_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM core.assignment a WHERE a.assignment_id = NEW.via_assignment_id AND a.employment_id = NEW.employment_id) THEN
    RAISE EXCEPTION 'ENROLMENT_ASSIGNMENT_MISMATCH' USING ERRCODE = 'check_violation';
  END IF;
  IF v_scope = 'agreement' AND NOT EXISTS (
       SELECT 1 FROM core.assignment_version av
       WHERE av.assignment_id = NEW.via_assignment_id AND av.agreement_id = v_agreement
         AND av.valid_period @> lower(NEW.valid_period) AND upper_inf(av.sys_period)) THEN
    RAISE EXCEPTION 'ENROLMENT_AGREEMENT_MISMATCH: the position is not under agreement % on the coverage start date', v_agreement
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER enrolment_scope_check BEFORE INSERT OR UPDATE ON benefits.enrolment
  FOR EACH ROW EXECUTE FUNCTION benefits.check_enrolment_scope();

-- The tenant's rules for what happens to coverage when a position ends (§6.2)
CREATE TABLE benefits.change_rule (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  rule_id          uuid NOT NULL,
  code             text NOT NULL,
  name_en          text NOT NULL,
  name_fr          text,
  priority         integer NOT NULL,
  match            jsonb NOT NULL DEFAULT '{}'::jsonb, -- { planKinds, planIds, scopes, endReasonCategories, employerInitiated, jurisdictions, agreementIds, employmentContinues }
  action           text NOT NULL CHECK (action IN ('continue_until','end_on_date','hr_decides')),
  until_rule       jsonb,                              -- { "kind": "end_of_month" | "end_of_next_month" | "days" | "weeks" | "end_of_notice" | "date", "n": 31, "date": "…" }
  offer_conversion boolean NOT NULL DEFAULT false,
  cite             text,                               -- policy, plan contract or agreement article
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  CHECK (jsonb_typeof(match) = 'object'),
  CHECK ((action = 'continue_until') = (until_rule IS NOT NULL)),
  CHECK (until_rule IS NULL OR until_rule->>'kind' IN ('end_of_month','end_of_next_month','days','weeks','end_of_notice','date')),
  EXCLUDE USING gist (rule_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period)),
  EXCLUDE USING gist (tenant_id WITH =, code WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

-- One decision per affected enrolment when a position ends; the statutory floor can never be undercut
CREATE TABLE benefits.change_decision (
  tenant_id              uuid NOT NULL,
  decision_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrolment_id           uuid NOT NULL REFERENCES benefits.enrolment,
  ended_assignment_id    uuid NOT NULL REFERENCES core.assignment,
  end_date               date NOT NULL,
  end_reason             text NOT NULL,
  eligible_after         boolean NOT NULL,
  fte_after              numeric(6,4) NOT NULL,
  rule_id                uuid,                          -- null when no rule matched (case by case)
  statutory_floor_until  date,
  statutory_basis        text,                          -- e.g. 'ES:ON benefits_during_notice'
  proposed_outcome       text NOT NULL CHECK (proposed_outcome IN ('no_change','continue_until','end_on_date','hr_decides')),
  proposed_until         date,
  outcome                text NOT NULL CHECK (outcome IN ('no_change','continue_until','end_on_date','hr_decides')),
  coverage_until         date,
  offer_conversion       boolean NOT NULL DEFAULT false,
  warnings               text[] NOT NULL DEFAULT '{}',
  status                 text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed','hr_review','decided','applied','cancelled')),
  reason                 text,
  decided_by             uuid,
  decided_at             timestamptz,
  change_set_id          uuid,
  created_at             timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (tenant_id, end_reason) REFERENCES core.end_reason (tenant_id, code),
  CONSTRAINT statutory_floor_respected
    CHECK (statutory_floor_until IS NULL OR coverage_until IS NULL OR coverage_until >= statutory_floor_until),
  CONSTRAINT case_by_case_needs_reason
    CHECK (status NOT IN ('decided','applied') OR rule_id IS NOT NULL OR reason IS NOT NULL),
  CONSTRAINT override_needs_reason
    CHECK (status NOT IN ('decided','applied') OR proposed_until IS NULL OR coverage_until IS NOT DISTINCT FROM proposed_until OR reason IS NOT NULL),
  CONSTRAINT decided_is_complete
    CHECK (status NOT IN ('decided','applied') OR (outcome <> 'hr_decides' AND decided_by IS NOT NULL AND decided_at IS NOT NULL
                                                  AND (outcome = 'no_change' OR coverage_until IS NOT NULL))),
  CHECK (outcome <> 'end_on_date' OR coverage_until = end_date)
);
CREATE INDEX change_decision_open ON benefits.change_decision (tenant_id, status) WHERE status IN ('proposed','hr_review');

CREATE FUNCTION benefits.guard_change_decision() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'CHANGE_DECISION_IMMUTABLE: cancel it instead' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.status IN ('applied','cancelled') THEN
    RAISE EXCEPTION 'CHANGE_DECISION_IMMUTABLE: decision is %', OLD.status USING ERRCODE = 'check_violation';
  END IF;
  IF (to_jsonb(NEW) - ARRAY['outcome','coverage_until','offer_conversion','status','reason','decided_by','decided_at','change_set_id','warnings'])
     <> (to_jsonb(OLD) - ARRAY['outcome','coverage_until','offer_conversion','status','reason','decided_by','decided_at','change_set_id','warnings']) THEN
    RAISE EXCEPTION 'CHANGE_DECISION_FACTS_FROZEN: the facts and the proposal cannot change; cancel and recompute' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER change_decision_guard BEFORE UPDATE OR DELETE ON benefits.change_decision
  FOR EACH ROW EXECUTE FUNCTION benefits.guard_change_decision();

-- -------------------------------------------------------------------------------------
-- Row-level security on every new tenant table (same policy as 0001)
-- -------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT n.nspname AS s, c.relname AS t
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND NOT c.relrowsecurity
      AND n.nspname IN ('core','payroll','timeleave','talent','benefits','comp')
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

-- Grants follow 0002_roles: cando_app gets SELECT, INSERT and UPDATE on the new tables and EXECUTE on the new
-- functions. core.approval_part rows are written by the routing service only (docs/20 §3.4).
