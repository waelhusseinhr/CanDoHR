-- =====================================================================================
-- CanDo HRIS — migration 0007: Core HR review decisions (October 2026)
-- Organization settings with defaults and locked legal floors; employment type per
-- position with a worked-out employment status; probation per bargaining unit; rehire
-- eligibility kept by HR; one employee number per person for life; positions always
-- (light mode removed) with positions created automatically at hire; unit heads and
-- routing past vacant manager positions; reporting across employers only under a
-- shared-services arrangement; position control overrides; several titles per position;
-- change reasons; approvals that HR and payroll must give, and "communicated" changes;
-- overpayments held until recovery is authorized; agreement findings against employment
-- standards with dual approval; bank account changes verified live; self-identification
-- categories with consent per category; support access grants and OCAP® data isolation.
-- Applies after 0001 to 0006. Specification: docs/21-core-hr-decisions.md.
-- Conventions as in 0001: tenant_id + RLS on every tenant table, effective-dated rows
-- with valid_period and sys_period, change_set_id on business rows. Alters no table
-- that 0004, 0005 or 0006 alters, except core.assignment_version (new columns only).
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- 1. Organization settings (docs/21 §2)
-- Every decision is a default an organization can change, except locked settings:
-- legal floors and safety rules that no organization can switch off.
-- -------------------------------------------------------------------------------------
CREATE TABLE platform.setting_definition (
  setting_key    text PRIMARY KEY,
  area           text NOT NULL,
  value_type     text NOT NULL CHECK (value_type IN ('boolean','integer','text','text_array','json')),
  allowed_values jsonb,                                  -- for text settings: ["finance_approval","hard_stop"]
  default_value  jsonb NOT NULL,
  scopes         text[] NOT NULL DEFAULT ARRAY['tenant']::text[],
  locked         boolean NOT NULL DEFAULT false,         -- legal floor or safety rule
  description_en text NOT NULL,
  description_fr text,
  decision_ref   text NOT NULL,                          -- e.g. 'docs/21 §4.2 (R3.2)'
  CHECK (scopes <@ ARRAY['tenant','legal_entity']::text[] AND 'tenant' = ANY (scopes)),
  CHECK (allowed_values IS NULL OR jsonb_typeof(allowed_values) = 'array')
);

CREATE TABLE platform.tenant_setting (
  tenant_id     uuid NOT NULL REFERENCES platform.tenant,
  version_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  setting_key   text NOT NULL REFERENCES platform.setting_definition,
  scope_type    text NOT NULL DEFAULT 'tenant' CHECK (scope_type IN ('tenant','legal_entity')),
  scope_id      uuid REFERENCES core.legal_entity,
  value         jsonb NOT NULL,
  reason        text,
  valid_period  daterange NOT NULL,
  sys_period    tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id uuid NOT NULL,
  CHECK ((scope_type = 'tenant') = (scope_id IS NULL)),
  EXCLUDE USING gist (tenant_id WITH =, setting_key WITH =, scope_type WITH =,
                      (coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period))
);

CREATE FUNCTION platform.check_tenant_setting() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d platform.setting_definition; t text := jsonb_typeof(NEW.value); type_ok boolean;
BEGIN
  SELECT * INTO d FROM platform.setting_definition WHERE setting_key = NEW.setting_key;
  IF d.locked THEN
    RAISE EXCEPTION 'SETTING_LOCKED: % is a legal floor or safety rule and cannot be changed', NEW.setting_key
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT (NEW.scope_type = ANY (d.scopes)) THEN
    RAISE EXCEPTION 'SETTING_SCOPE_NOT_ALLOWED: % cannot be set per %', NEW.setting_key, NEW.scope_type USING ERRCODE = 'check_violation';
  END IF;
  type_ok := CASE d.value_type
               WHEN 'boolean'    THEN t = 'boolean'
               WHEN 'integer'    THEN t = 'number' AND (NEW.value #>> '{}') ~ '^-?[0-9]+$'
               WHEN 'text'       THEN t = 'string'
               WHEN 'text_array' THEN t = 'array' AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(NEW.value) e WHERE jsonb_typeof(e) <> 'string')
               WHEN 'json'       THEN t = 'object'
             END;
  IF NOT coalesce(type_ok, false) THEN
    RAISE EXCEPTION 'SETTING_VALUE_TYPE: % takes a % value', NEW.setting_key, d.value_type USING ERRCODE = 'check_violation';
  END IF;
  IF d.allowed_values IS NOT NULL AND NOT (d.allowed_values @> jsonb_build_array(NEW.value)) THEN
    RAISE EXCEPTION 'SETTING_VALUE_NOT_ALLOWED: % must be one of %', NEW.setting_key, d.allowed_values USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER tenant_setting_check BEFORE INSERT OR UPDATE OF setting_key, scope_type, value ON platform.tenant_setting
  FOR EACH ROW EXECUTE FUNCTION platform.check_tenant_setting();

-- The value in force: legal entity override, then tenant override, then CanDo's default. Locked settings
-- always return the default.
CREATE FUNCTION platform.setting(p_tenant uuid, p_key text, p_as_of date DEFAULT current_date, p_legal_entity uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN d.locked THEN d.default_value ELSE coalesce(
    (SELECT s.value FROM platform.tenant_setting s
      WHERE s.tenant_id = p_tenant AND s.setting_key = p_key AND s.scope_type = 'legal_entity' AND s.scope_id = p_legal_entity
        AND s.valid_period @> p_as_of AND upper_inf(s.sys_period)),
    (SELECT s.value FROM platform.tenant_setting s
      WHERE s.tenant_id = p_tenant AND s.setting_key = p_key AND s.scope_type = 'tenant'
        AND s.valid_period @> p_as_of AND upper_inf(s.sys_period)),
    d.default_value) END
  FROM platform.setting_definition d WHERE d.setting_key = p_key
$$;

INSERT INTO platform.setting_definition (setting_key, area, value_type, allowed_values, default_value, scopes, locked, description_en, decision_ref) VALUES
 ('employment.status_precedence', 'employment', 'text_array', NULL,
  '["permanent","term","auxiliary","seasonal","casual","student"]', ARRAY['tenant'], false,
  'Order used to work out an employment''s status from its positions: the first type held by any position that has not ended.', 'docs/21 §3.1 (R1.1)'),
 ('probation.non_union', 'probation', 'json', NULL,
  '{"measure":"calendar_months","amount":3,"extendable":true}', ARRAY['tenant','legal_entity'], false,
  'Employer probation for positions outside every bargaining unit. Union probation comes from the agreement.', 'docs/21 §3.2 (R1.2)'),
 ('probation.trial_period_non_union', 'probation', 'json', NULL,
  '{"enabled":false}', ARRAY['tenant','legal_entity'], false,
  'Trial period when a non-union employee moves to another position. Union trial periods come from the agreement.', 'docs/21 §3.2 (R1.2)'),
 ('rehire.review_max_months', 'rehire', 'integer', NULL, '24', ARRAY['tenant'], false,
  'Longest time before a "check with HR" or "not eligible" rehire status must be reviewed.', 'docs/21 §3.4 (R1.4)'),
 ('rehire.service_bridging', 'rehire', 'text', '["propose_hr_confirms","apply_rule"]', '"propose_hr_confirms"', ARRAY['tenant'], false,
  'On rehire, the agreement or policy rule proposes which prior service counts; by default HR confirms it.', 'docs/21 §3.6'),
 ('employee_number.format', 'identity', 'json', NULL, '{"prefix":"","width":6}', ARRAY['tenant'], false,
  'Format of the employee number CanDo gives each person once, for life.', 'docs/21 §3.5 (R1.5)'),
 ('approvals.vacant_manager', 'approvals', 'json', NULL, '{"route":"next_filled_up","alertHr":true}', ARRAY['tenant'], false,
  'When the manager''s position is vacant and no acting manager is named: approvals go to the next filled position up, and HR is alerted.', 'docs/21 §4.1 (R2.1)'),
 ('org.unit_without_head', 'organization', 'text', '["warn","block"]', '"warn"', ARRAY['tenant'], false,
  'What happens when an org unit has no head position on a date.', 'docs/21 §4.2 (R2.2)'),
 ('org_chart.employee_view', 'organization', 'json', NULL, '{"vacancies":false,"changeBadges":false,"futureDates":false}', ARRAY['tenant'], false,
  'What employees see on the published org chart. By default: filled positions as of today only.', 'docs/21 §4.3 (R2.3)'),
 ('org_chart.manager_view', 'organization', 'json', NULL, '{"vacancies":"own_area","changeBadges":"own_area","futureDates":"own_area"}', ARRAY['tenant'], false,
  'What managers see on the org chart beyond filled positions.', 'docs/21 §4.3 (R2.3)'),
 ('reporting.cross_employer', 'organization', 'text', '["arrangement_required"]', '"arrangement_required"', ARRAY['tenant'], true,
  'Reporting across employers needs a recorded shared-services arrangement (privacy limit; cannot be switched off).', 'docs/21 §4.4 (R2.4)'),
 ('positions.management', 'positions', 'text', '["managed","automatic"]', '"managed"', ARRAY['tenant','legal_entity'], false,
  '"managed": positions are created before hiring and position control applies. "automatic": CanDo creates the position at hire under the manager HR picks, and position control is off.', 'docs/21 §5.1 (R3.1)'),
 ('positions.over_budget', 'positions', 'text', '["finance_approval","hard_stop"]', '"finance_approval"', ARRAY['tenant','legal_entity'], false,
  'A hire or change over the position''s budget: allowed with finance approval and a written reason, or stopped.', 'docs/21 §5.2 (R3.2)'),
 ('positions.over_complement', 'positions', 'text', '["finance_approval","hard_stop"]', '"finance_approval"', ARRAY['tenant','legal_entity'], false,
  'A hire or change over the approved complement: allowed with finance approval and a written reason, or stopped.', 'docs/21 §5.2 (R3.2)'),
 ('codes.warn_when_missing', 'codes', 'json', NULL, '{"NOC":["job"]}', ARRAY['tenant'], false,
  'Code schemes that raise a warning when missing on a target (scheme code: targets). Required schemes are set on core.code_scheme.required_on.', 'docs/21 §6.1 (R4.1)'),
 ('retro.backdate_approval', 'approvals', 'json', NULL, '{"hrApprovals":1,"payrollApproval":true,"secondHrApprovalOlderThan":"1 month"}', ARRAY['tenant','legal_entity'], false,
  'Approvals for a change whose effective date reaches a finalized pay period.', 'docs/21 §7.1 (R5.1)'),
 ('payroll.overpayment_recovery', 'payroll', 'text', '["employee_authorization","jurisdiction_rule_allows"]', '"employee_authorization"', ARRAY['tenant','legal_entity'], false,
  'An overpayment is recovered only with the employee''s written authorization, unless the organization allows recovery where a verified jurisdiction or agreement rule permits it.', 'docs/21 §7.2 (R5.1)'),
 ('self_service.show_changes', 'self_service', 'text', '["when_communicated","when_approved","when_effective"]', '"when_communicated"', ARRAY['tenant'], false,
  'When an employee sees an approved change on their own profile. Changes the employee asked for are always visible.', 'docs/21 §7.3 (R5.2)'),
 ('approvals.hr_required', 'approvals', 'text_array', NULL, '["termination","demotion","leave_or_accommodation"]', ARRAY['tenant'], true,
  'Changes that always need HR approval, whatever the organization''s workflow.', 'docs/21 §7.4 (R5.3)'),
 ('approvals.no_self_approval', 'approvals', 'boolean', NULL, 'true', ARRAY['tenant'], true,
  'No one approves their own request or change, from any of their positions.', 'docs/21 §2.2'),
 ('approvals.escalate_after_working_days', 'approvals', 'integer', NULL, '3', ARRAY['tenant'], false,
  'Working days before an undecided approval also goes to the approver''s own manager.', 'docs/21 §7.5 (docs/16 Q34)'),
 ('agreements.below_law_dual_approval', 'agreements', 'boolean', NULL, 'true', ARRAY['tenant'], true,
  'Where an agreement gives less than the law in a part the law lets it replace, the HR administrator and the payroll administrator both approve before activation.', 'docs/21 §8.1 (R6.1)'),
 ('agreements.customer_can_amend', 'agreements', 'boolean', NULL, 'true', ARRAY['tenant'], false,
  'After CanDo or a partner sets up an agreement, the organization''s HR can amend it through CanDo''s screens.', 'docs/21 §8.2 (R6.2)'),
 ('bank_change.hold_hours', 'payroll', 'integer', NULL, '72', ARRAY['tenant'], false,
  'Hours a new bank account waits before pay can go to it.', 'docs/21 §9.1 (R7.1)'),
 ('bank_change.hr_live_verification', 'payroll', 'boolean', NULL, 'true', ARRAY['tenant','legal_entity'], false,
  'HR approves a bank account change only after a live video or phone check with photo ID.', 'docs/21 §9.1 (R7.1)'),
 ('support.access_requires_approval', 'platform', 'boolean', NULL, 'true', ARRAY['tenant'], false,
  'CanDo staff see the organization''s data only with a time-limited grant approved by the organization.', 'docs/21 §9.3 (R7.3)');

-- -------------------------------------------------------------------------------------
-- 2. Employment type per position; employment status worked out from positions (§3.1)
-- -------------------------------------------------------------------------------------
ALTER TABLE core.assignment_version
  ADD COLUMN employment_type text CHECK (employment_type IN ('permanent','term','casual','auxiliary','seasonal','student'));
ALTER TABLE core.employment_version ALTER COLUMN employment_type DROP NOT NULL;
COMMENT ON COLUMN core.employment_version.employment_type IS
  'Read-only after migration 0007: employment type lives on each assignment; the employment''s status comes from core.employment_status_type() (docs/21 §3.1).';
COMMENT ON COLUMN core.assignment_version.employment_type IS
  'Required on every new assignment version (change-set validation EMPLOYMENT_TYPE_REQUIRED); the data migration copies it from employment_version.';

CREATE FUNCTION core.employment_status_type(p_employment uuid, p_as_of date) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT x.t
  FROM core.employment e
  CROSS JOIN LATERAL jsonb_array_elements_text(platform.setting(e.tenant_id, 'employment.status_precedence', p_as_of, e.legal_entity_id))
       WITH ORDINALITY AS x(t, ord)
  WHERE e.employment_id = p_employment
    AND EXISTS (SELECT 1 FROM core.assignment a
                JOIN core.assignment_version av ON av.assignment_id = a.assignment_id
                WHERE a.employment_id = e.employment_id AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
                  AND av.status <> 'ended' AND av.employment_type = x.t)
  ORDER BY x.ord
  LIMIT 1
$$;

-- -------------------------------------------------------------------------------------
-- 3. Probation per bargaining unit, employer probation, trial periods (§3.2)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.probation (
  tenant_id       uuid NOT NULL,
  version_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  probation_id    uuid NOT NULL,                        -- one probation across its versions
  employment_id   uuid NOT NULL REFERENCES core.employment,
  kind            text NOT NULL CHECK (kind IN ('agreement','employer','trial')),
  agreement_id    text,
  bargaining_unit text,
  assignment_id   uuid REFERENCES core.assignment,     -- the position that started it; required for a trial period
  measure         text NOT NULL CHECK (measure IN ('calendar_days','calendar_months','hours_paid','hours_worked','days_worked','shifts_worked')),
  required_amount numeric(10,2) NOT NULL CHECK (required_amount > 0),
  counter_code    text,                                 -- core.counter_ledger code for counted measures
  started_on      date NOT NULL,
  extended_by     numeric(10,2) NOT NULL DEFAULT 0 CHECK (extended_by >= 0),
  status          text NOT NULL DEFAULT 'in_progress'
                  CHECK (status IN ('in_progress','extended','passed','failed','waived','returned','ended')),
  outcome_on      date,
  reason          text,
  rule_source     text NOT NULL,                        -- 'agreement:CUPE-503-PT#4:7.1' | 'setting:probation.non_union'
  valid_period    daterange NOT NULL,
  sys_period      tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id   uuid NOT NULL,
  CONSTRAINT probation_agreement_named CHECK ((kind = 'agreement') = (agreement_id IS NOT NULL) OR kind = 'trial'),
  CONSTRAINT probation_employer_has_no_unit CHECK (kind <> 'employer' OR (agreement_id IS NULL AND bargaining_unit IS NULL)),
  CONSTRAINT probation_trial_names_position CHECK (kind <> 'trial' OR assignment_id IS NOT NULL),
  CONSTRAINT probation_counted_measure CHECK (measure IN ('calendar_days','calendar_months') OR counter_code IS NOT NULL),
  CONSTRAINT probation_extension CHECK (status <> 'extended' OR extended_by > 0),
  CONSTRAINT probation_outcome_dated CHECK (status IN ('in_progress','extended') OR outcome_on IS NOT NULL),
  CONSTRAINT probation_outcome_reason CHECK (status NOT IN ('failed','waived','returned','extended') OR reason IS NOT NULL),
  EXCLUDE USING gist (probation_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period)),
  -- one open probation per employment per unit (or per employer for non-union work)
  EXCLUDE USING gist (employment_id WITH =, kind WITH =, (coalesce(agreement_id, '')) WITH =, (coalesce(bargaining_unit, '')) WITH =,
                      valid_period WITH &&)
    WHERE (upper_inf(sys_period) AND status IN ('in_progress','extended'))
);
CREATE INDEX probation_lookup ON core.probation (tenant_id, employment_id) WHERE upper_inf(sys_period);
COMMENT ON COLUMN core.employment_version.probation_end IS
  'Read-only after migration 0007: probation is kept per bargaining unit, employer and trial period in core.probation (docs/21 §3.2).';

-- -------------------------------------------------------------------------------------
-- 4. Rehire eligibility, kept by HR with a reason category and a review date (§3.4)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.rehire_reason (
  tenant_id  uuid NOT NULL,
  code       text NOT NULL,
  name_en    text NOT NULL,
  name_fr    text,
  -- fixed categories; none of them is a protected ground, a leave or a health matter
  category   text NOT NULL CHECK (category IN ('conduct','performance','job_abandonment','policy_breach','misrepresentation',
                                               'safety','contract_terms','other')),
  status     text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  PRIMARY KEY (tenant_id, code)
);

CREATE TABLE core.rehire_eligibility (
  tenant_id      uuid NOT NULL,
  version_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  person_id      uuid NOT NULL REFERENCES core.person,
  employment_id  uuid REFERENCES core.employment,      -- the employment it arose from
  status         text NOT NULL CHECK (status IN ('eligible','check_with_hr','not_eligible')),
  reason_code    text,
  note           text,                                 -- restricted field class; never names a protected ground
  review_on      date,
  decided_by     uuid NOT NULL,
  decided_at     timestamptz NOT NULL DEFAULT now(),
  valid_period   daterange NOT NULL,
  sys_period     tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id  uuid NOT NULL,
  FOREIGN KEY (tenant_id, reason_code) REFERENCES core.rehire_reason (tenant_id, code),
  CONSTRAINT rehire_reason_when_restricted CHECK ((status = 'eligible') = (reason_code IS NULL)),
  CONSTRAINT rehire_review_when_restricted CHECK (status = 'eligible' OR review_on IS NOT NULL),
  CONSTRAINT rehire_review_in_future CHECK (review_on IS NULL OR review_on > lower(valid_period)),
  EXCLUDE USING gist (person_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

CREATE FUNCTION core.check_rehire_eligibility() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE max_months int;
BEGIN
  IF NEW.review_on IS NOT NULL THEN
    max_months := (platform.setting(NEW.tenant_id, 'rehire.review_max_months', lower(NEW.valid_period)) #>> '{}')::int;
    IF NEW.review_on > lower(NEW.valid_period) + make_interval(months => max_months) THEN
      RAISE EXCEPTION 'REHIRE_REVIEW_TOO_FAR: review within % months', max_months USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER rehire_eligibility_check BEFORE INSERT OR UPDATE OF review_on, valid_period ON core.rehire_eligibility
  FOR EACH ROW EXECUTE FUNCTION core.check_rehire_eligibility();

-- What recruiters see: only whether to check with HR. A status past its review date still says check with HR.
CREATE FUNCTION core.rehire_signal(p_person uuid, p_as_of date DEFAULT current_date) RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN r.status IS NULL OR r.status = 'eligible' THEN 'none' ELSE 'check_with_hr' END
  FROM (SELECT 1) one
  LEFT JOIN core.rehire_eligibility r
    ON r.person_id = p_person AND r.valid_period @> p_as_of AND upper_inf(r.sys_period)
$$;
COMMENT ON COLUMN core.employment_version.rehire_eligible IS
  'Read-only after migration 0007: rehire eligibility is in core.rehire_eligibility, visible to HR only (docs/21 §3.4).';

-- -------------------------------------------------------------------------------------
-- 5. One employee number per person, for life (§3.5)
-- -------------------------------------------------------------------------------------
ALTER TABLE core.person ADD COLUMN employee_number text;
CREATE UNIQUE INDEX person_employee_number ON core.person (tenant_id, employee_number) WHERE employee_number IS NOT NULL;
ALTER TABLE core.employment ALTER COLUMN employee_number DROP NOT NULL;
COMMENT ON COLUMN core.employment.employee_number IS
  'Legacy employer-specific number only (kept for the data migration and as a code, docs/18). The employee number is core.person.employee_number.';

CREATE TABLE core.employee_number_counter (
  tenant_id  uuid PRIMARY KEY,
  last_value bigint NOT NULL DEFAULT 0
);

CREATE FUNCTION core.next_employee_number(p_tenant uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE fmt jsonb := platform.setting(p_tenant, 'employee_number.format'); n bigint; candidate text;
BEGIN
  INSERT INTO core.employee_number_counter (tenant_id) VALUES (p_tenant) ON CONFLICT (tenant_id) DO NOTHING;
  LOOP
    UPDATE core.employee_number_counter SET last_value = last_value + 1 WHERE tenant_id = p_tenant RETURNING last_value INTO n;
    candidate := coalesce(fmt->>'prefix', '') || lpad(n::text, coalesce((fmt->>'width')::int, 6), '0');
    EXIT WHEN NOT EXISTS (SELECT 1 FROM core.person WHERE tenant_id = p_tenant AND employee_number = candidate)
          AND NOT EXISTS (SELECT 1 FROM core.employment WHERE tenant_id = p_tenant AND employee_number = candidate);
  END LOOP;
  RETURN candidate;
END $$;

-- A person gets their number with their first employment: the legacy number given with it, or the next one
CREATE FUNCTION core.assign_employee_number() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  SELECT employee_number INTO v FROM core.person WHERE person_id = NEW.person_id;
  IF v IS NULL THEN
    v := coalesce(NEW.employee_number, core.next_employee_number(NEW.tenant_id));
    UPDATE core.person SET employee_number = v WHERE person_id = NEW.person_id;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER employment_assign_employee_number BEFORE INSERT ON core.employment
  FOR EACH ROW EXECUTE FUNCTION core.assign_employee_number();

CREATE FUNCTION core.guard_employee_number() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.employee_number IS NOT NULL AND NEW.employee_number IS DISTINCT FROM OLD.employee_number THEN
    RAISE EXCEPTION 'EMPLOYEE_NUMBER_IMMUTABLE: a person keeps % for life', OLD.employee_number USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER person_employee_number_immutable BEFORE UPDATE OF employee_number ON core.person
  FOR EACH ROW EXECUTE FUNCTION core.guard_employee_number();

-- -------------------------------------------------------------------------------------
-- 6. Positions always; light mode removed; positions created at hire (§5.1)
-- -------------------------------------------------------------------------------------
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM platform.tenant WHERE org_mode = 'light') THEN
    RAISE EXCEPTION 'LIGHT_MODE_TENANTS_EXIST: create one position per assignment for those tenants first (docs/21 §5.1)';
  END IF;
END $$;
ALTER TABLE platform.tenant DROP CONSTRAINT IF EXISTS tenant_org_mode_check;
ALTER TABLE platform.tenant ADD CONSTRAINT tenant_org_mode_check CHECK (org_mode = 'position');
COMMENT ON COLUMN platform.tenant.org_mode IS
  'Always position since 0007. How positions are created is the positions.management setting (docs/21 §5.1).';
COMMENT ON COLUMN core.assignment_version.position_id IS
  'Required on every new assignment version since 0007 (change-set validation POSITION_REQUIRED); no light mode.';
COMMENT ON COLUMN core.assignment_version.manager_assignment_id IS
  'Not used since 0007: the line manager comes from the position tree; acting managers and delegates are typed relationships (change-set validation DIRECT_MANAGER_NOT_USED).';

ALTER TABLE core.position
  ADD COLUMN origin      text NOT NULL DEFAULT 'planned' CHECK (origin IN ('planned','auto_at_hire','status_conversion','import','data_migration')),
  ADD COLUMN reviewed_at timestamptz,                   -- automatic positions are reviewed when position control is switched on
  ADD COLUMN reviewed_by uuid;

-- Over-budget and over-complement overrides, approved by finance with a written reason (§5.2)
CREATE TABLE core.position_control_override (
  tenant_id          uuid NOT NULL,
  override_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  change_set_id      uuid NOT NULL REFERENCES platform.change_set,
  position_id        uuid REFERENCES core.position,
  org_unit_id        uuid REFERENCES core.org_unit,
  check_kind         text NOT NULL CHECK (check_kind IN ('fte','budget','complement','funding')),
  amount_over        numeric(16,2),
  fte_over           numeric(6,4),
  reason             text NOT NULL CHECK (length(btrim(reason)) >= 10),
  status             text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
  finance_approver   uuid,
  finance_decided_at timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (position_id IS NOT NULL OR org_unit_id IS NOT NULL),
  CHECK (status = 'pending' OR (finance_approver IS NOT NULL AND finance_decided_at IS NOT NULL))
);

CREATE FUNCTION core.check_position_control_override() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.finance_approver IS NOT NULL AND NEW.finance_approver = (SELECT requested_by FROM platform.change_set WHERE change_set_id = NEW.change_set_id) THEN
    RAISE EXCEPTION 'SELF_APPROVAL: finance approval comes from someone other than the requester' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER position_control_override_check BEFORE INSERT OR UPDATE ON core.position_control_override
  FOR EACH ROW EXECUTE FUNCTION core.check_position_control_override();

-- -------------------------------------------------------------------------------------
-- 7. Unit heads and routing past vacant manager positions (§4.1, §4.2)
-- -------------------------------------------------------------------------------------
ALTER TABLE core.org_unit_version
  ADD CONSTRAINT org_unit_version_head_position_fk FOREIGN KEY (head_position_id) REFERENCES core.position NOT VALID;

-- Management units with no head position, or whose head position is not active, on a date
CREATE FUNCTION core.org_units_without_head(p_as_of date DEFAULT current_date)
RETURNS TABLE (org_unit_id uuid, code text, name_en text, head_position_id uuid) LANGUAGE sql STABLE AS $$
  SELECT ou.org_unit_id, ou.code, ou.name_en, ou.head_position_id
  FROM core.org_unit_version ou
  LEFT JOIN core.hierarchy h ON h.hierarchy_id = ou.hierarchy_id
  WHERE ou.valid_period @> p_as_of AND upper_inf(ou.sys_period) AND ou.status = 'active'
    AND (ou.hierarchy_id IS NULL OR h.kind = 'management')
    AND (ou.head_position_id IS NULL OR NOT EXISTS (
          SELECT 1 FROM core.position_version pv
          WHERE pv.position_id = ou.head_position_id AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
            AND pv.status <> 'eliminated'))
  ORDER BY ou.code
$$;

-- The nearest position above with someone in it (active, on leave, or acting in it) on a date
CREATE FUNCTION core.next_filled_position_up(p_position uuid, p_as_of date)
RETURNS TABLE (position_id uuid, holder_assignment_ids uuid[], levels_up int) LANGUAGE sql STABLE AS $$
  WITH RECURSIVE up (position_id, lvl) AS (
    SELECT pv.reports_to_position_id, 1
    FROM core.position_version pv
    WHERE pv.position_id = p_position AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
    UNION ALL
    SELECT pv.reports_to_position_id, up.lvl + 1
    FROM up JOIN core.position_version pv
      ON pv.position_id = up.position_id AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
    WHERE up.position_id IS NOT NULL AND up.lvl < 50
  )
  SELECT up.position_id, h.ids, up.lvl
  FROM up
  CROSS JOIN LATERAL (
    SELECT array_agg(av.assignment_id ORDER BY av.assignment_id) AS ids
    FROM core.assignment_version av
    WHERE av.position_id = up.position_id AND av.valid_period @> p_as_of AND upper_inf(av.sys_period)
      AND av.status IN ('active','on_leave')) h
  WHERE up.position_id IS NOT NULL AND h.ids IS NOT NULL
  ORDER BY up.lvl
  LIMIT 1
$$;

-- -------------------------------------------------------------------------------------
-- 8. Reporting across employers only under a shared-services arrangement (§4.4)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.shared_services_arrangement (
  tenant_id          uuid NOT NULL,
  version_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  arrangement_id     uuid NOT NULL,
  code               text NOT NULL,
  serving_entity_id  uuid NOT NULL REFERENCES core.legal_entity,   -- employer of the managers or HR staff who serve
  served_entity_id   uuid NOT NULL REFERENCES core.legal_entity,   -- employer of the staff being served
  purposes           text[] NOT NULL,
  privacy_basis      text NOT NULL,                                -- the clause and authority that allow the data to be shared
  document_id        uuid REFERENCES platform.document,
  valid_period       daterange NOT NULL,
  sys_period         tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id      uuid NOT NULL,
  CHECK (serving_entity_id <> served_entity_id),
  CHECK (purposes <@ ARRAY['supervision','hr_services','payroll_services']::text[] AND cardinality(purposes) >= 1),
  EXCLUDE USING gist (arrangement_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

CREATE FUNCTION core.has_shared_services(p_serving uuid, p_served uuid, p_purpose text, p_date date) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM core.shared_services_arrangement a
                 WHERE a.serving_entity_id = p_serving AND a.served_entity_id = p_served AND p_purpose = ANY (a.purposes)
                   AND a.valid_period @> p_date AND upper_inf(a.sys_period))
$$;

CREATE FUNCTION core.position_legal_entity(p_position uuid, p_as_of date) RETURNS uuid LANGUAGE sql STABLE AS $$
  SELECT ouv.legal_entity_id
  FROM core.position_version pv
  JOIN core.org_unit_version ouv ON ouv.org_unit_id = pv.org_unit_id AND ouv.valid_period @> p_as_of AND upper_inf(ouv.sys_period)
  WHERE pv.position_id = p_position AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
  LIMIT 1
$$;

-- Line reporting in the position tree across employers
CREATE FUNCTION core.check_cross_employer_line() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE d date := lower(NEW.valid_period); le_self uuid; le_mgr uuid;
BEGIN
  IF NEW.reports_to_position_id IS NULL OR NOT upper_inf(NEW.sys_period) THEN RETURN NEW; END IF;
  SELECT legal_entity_id INTO le_self FROM core.org_unit_version
    WHERE org_unit_id = NEW.org_unit_id AND valid_period @> d AND upper_inf(sys_period);
  le_mgr := core.position_legal_entity(NEW.reports_to_position_id, d);
  IF le_self IS NOT NULL AND le_mgr IS NOT NULL AND le_self <> le_mgr
     AND NOT core.has_shared_services(le_mgr, le_self, 'supervision', d) THEN
    RAISE EXCEPTION 'CROSS_EMPLOYER_NO_ARRANGEMENT: the position reports to another employer''s position without a shared-services arrangement for supervision'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER position_version_cross_employer BEFORE INSERT ON core.position_version
  FOR EACH ROW EXECUTE FUNCTION core.check_cross_employer_line();

-- Typed relationships across employers (functional, program, acting manager, delegate, HR business partner ...)
CREATE FUNCTION core.check_cross_employer_relationship() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le_self uuid; le_other uuid; purpose text;
BEGIN
  purpose := CASE coalesce(NEW.relationship_type_code, NEW.kind) WHEN 'mentor' THEN NULL WHEN 'hrbp' THEN 'hr_services' ELSE 'supervision' END;
  IF purpose IS NULL THEN RETURN NEW; END IF;
  SELECT e.legal_entity_id INTO le_self FROM core.assignment a JOIN core.employment e USING (employment_id) WHERE a.assignment_id = NEW.assignment_id;
  SELECT e.legal_entity_id INTO le_other FROM core.assignment a JOIN core.employment e USING (employment_id) WHERE a.assignment_id = NEW.related_assignment_id;
  IF le_self <> le_other AND NOT core.has_shared_services(le_other, le_self, purpose, lower(NEW.valid_period)) THEN
    RAISE EXCEPTION 'CROSS_EMPLOYER_NO_ARRANGEMENT: no shared-services arrangement for % between the two employers', purpose
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER assignment_relationship_cross_employer BEFORE INSERT ON core.assignment_relationship
  FOR EACH ROW EXECUTE FUNCTION core.check_cross_employer_relationship();

-- -------------------------------------------------------------------------------------
-- 9. Several titles per position, each with its purpose (§6.4)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.position_title (
  tenant_id         uuid NOT NULL,
  version_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  title_id          uuid NOT NULL,
  position_id       uuid NOT NULL REFERENCES core.position,
  purpose           text NOT NULL CHECK (purpose IN ('working','funder','posting','legacy','other')),
  funding_source_id uuid REFERENCES finance.funding_source,
  label             text,                               -- what an 'other' title is for, e.g. 'Ministry contract'
  title_en          text NOT NULL,
  title_fr          text,
  valid_period      daterange NOT NULL,
  sys_period        tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id     uuid NOT NULL,
  CHECK ((purpose = 'funder') = (funding_source_id IS NOT NULL)),
  CHECK (purpose <> 'other' OR label IS NOT NULL),
  EXCLUDE USING gist (title_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period)),
  EXCLUDE USING gist (position_id WITH =, purpose WITH =,
                      (coalesce(funding_source_id, '00000000-0000-0000-0000-000000000000'::uuid)) WITH =,
                      (coalesce(label, '')) WITH =, valid_period WITH &&)
    WHERE (upper_inf(sys_period))
);
CREATE INDEX position_title_lookup ON core.position_title (tenant_id, position_id) WHERE upper_inf(sys_period);
COMMENT ON COLUMN core.position_version.title_override_en IS
  'Read-only after migration 0007: working and other titles are in core.position_title (docs/21 §6.4).';

-- The title for a purpose on a date: that purpose (and funder), then the working title, then the job's title
CREATE FUNCTION core.position_title_for(p_position uuid, p_purpose text, p_as_of date, p_funding_source uuid DEFAULT NULL,
                                        p_lang ref.lang DEFAULT 'en')
RETURNS TABLE (title text, origin text) LANGUAGE sql STABLE AS $$
  SELECT t.title, t.origin FROM (
    SELECT CASE WHEN p_lang = 'fr' THEN coalesce(pt.title_fr, pt.title_en) ELSE pt.title_en END AS title, pt.purpose AS origin,
           CASE WHEN pt.purpose = p_purpose THEN 1 ELSE 2 END AS rank
    FROM core.position_title pt
    WHERE pt.position_id = p_position AND pt.valid_period @> p_as_of AND upper_inf(pt.sys_period)
      AND ((pt.purpose = p_purpose AND pt.funding_source_id IS NOT DISTINCT FROM p_funding_source) OR pt.purpose = 'working')
    UNION ALL
    SELECT CASE WHEN p_lang = 'fr' THEN coalesce(jv.title_fr, jv.title_en) ELSE jv.title_en END, 'job', 3
    FROM core.position_version pv
    JOIN core.job_version jv ON jv.job_id = pv.job_id AND jv.valid_period @> p_as_of AND upper_inf(jv.sys_period)
    WHERE pv.position_id = p_position AND pv.valid_period @> p_as_of AND upper_inf(pv.sys_period)
  ) t
  ORDER BY t.rank
  LIMIT 1
$$;

-- -------------------------------------------------------------------------------------
-- 10. Change reasons, approvals HR and payroll must give, communicated changes (§7)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.change_reason (
  tenant_id  uuid NOT NULL,
  code       text NOT NULL,
  name_en    text NOT NULL,
  name_fr    text,
  category   text NOT NULL CHECK (category IN ('hire','rehire','probation','status_conversion','promotion','demotion','lateral_transfer',
                                               'reclassification','reorganization','pay_change','hours_change','leave','acting',
                                               'assignment_end','termination','correction','data_update','other')),
  status     text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  PRIMARY KEY (tenant_id, code)
);

ALTER TABLE platform.approval_task
  ADD COLUMN capability text CHECK (capability IN ('manager','hr','payroll','finance','labour_relations','other'));

ALTER TABLE platform.change_set
  ADD COLUMN reason_category         text,
  ADD COLUMN linked_case_id          uuid REFERENCES compliance.case_file,
  ADD COLUMN linked_leave_request_id uuid REFERENCES timeleave.leave_request,
  ADD COLUMN reaches_finalized_pay   boolean NOT NULL DEFAULT false,   -- set by validation (docs/03 §4)
  ADD COLUMN communicated_at         timestamptz,
  ADD COLUMN communicated_by         uuid,
  ADD COLUMN communication_method    text CHECK (communication_method IN ('in_person','video','phone','letter','email','other'));
ALTER TABLE platform.change_set
  ADD CONSTRAINT change_set_communicated_after_approval
    CHECK (communicated_at IS NULL OR (status IN ('approved','scheduled','committed') AND communicated_by IS NOT NULL));

CREATE FUNCTION platform.change_set_reason_category() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  SELECT category INTO NEW.reason_category FROM core.change_reason
    WHERE tenant_id = NEW.tenant_id AND code = NEW.reason_code;
  RETURN NEW;
END $$;
CREATE TRIGGER change_set_1_reason_category BEFORE INSERT OR UPDATE OF reason_code ON platform.change_set
  FOR EACH ROW EXECUTE FUNCTION platform.change_set_reason_category();

-- Approvals a change set needs from HR and payroll, from the locked HR list and the back-dating setting
CREATE FUNCTION platform.required_approvals(cs platform.change_set)
RETURNS TABLE (hr_needed int, payroll_needed int) LANGUAGE plpgsql STABLE AS $$
DECLARE hr_list jsonb; bd jsonb; hr int := 0; pay int := 0;
BEGIN
  hr_list := platform.setting(cs.tenant_id, 'approvals.hr_required', cs.effective_date);
  IF (hr_list ? 'termination' AND 'termination' IN (cs.reason_category, cs.kind))
     OR (hr_list ? 'demotion' AND 'demotion' IN (cs.reason_category, cs.kind))
     OR (hr_list ? 'leave_or_accommodation' AND (cs.linked_case_id IS NOT NULL OR cs.linked_leave_request_id IS NOT NULL)) THEN
    hr := 1;
  END IF;
  IF cs.reaches_finalized_pay THEN
    bd := platform.setting(cs.tenant_id, 'retro.backdate_approval', cs.effective_date);
    hr := greatest(hr, coalesce((bd->>'hrApprovals')::int, 1));
    IF cs.effective_date < (cs.requested_at::date - coalesce((bd->>'secondHrApprovalOlderThan')::interval, interval '1 month')) THEN
      hr := greatest(hr, 2);
    END IF;
    IF coalesce((bd->>'payrollApproval')::boolean, true) THEN pay := 1; END IF;
  END IF;
  hr_needed := hr; payroll_needed := pay;
  RETURN NEXT;
END $$;

CREATE FUNCTION platform.check_change_set_approvals() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE need record; hr_have int; pay_have int;
BEGIN
  IF NEW.status NOT IN ('approved','scheduled','committed') OR NEW.source = 'import' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IN ('approved','scheduled','committed') THEN RETURN NEW; END IF;
  SELECT * INTO need FROM platform.required_approvals(NEW);
  SELECT count(DISTINCT decided_by) FILTER (WHERE capability = 'hr'),
         count(DISTINCT decided_by) FILTER (WHERE capability = 'payroll')
    INTO hr_have, pay_have
    FROM platform.approval_task
    WHERE subject_type = 'change_set' AND subject_id = NEW.change_set_id AND status = 'approved'
      AND decided_by IS NOT NULL AND decided_by <> NEW.requested_by;
  IF hr_have < need.hr_needed OR pay_have < need.payroll_needed THEN
    RAISE EXCEPTION 'APPROVALS_MISSING: needs % HR and % payroll approvals from people other than the requester; has % and %',
      need.hr_needed, need.payroll_needed, hr_have, pay_have USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER change_set_2_approvals_check BEFORE INSERT OR UPDATE OF status ON platform.change_set
  FOR EACH ROW EXECUTE FUNCTION platform.check_change_set_approvals();

-- No one approves their own change set
CREATE FUNCTION platform.check_approval_task() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.subject_type = 'change_set' AND NEW.status = 'approved' AND NEW.decided_by IS NOT NULL
     AND NEW.decided_by = (SELECT requested_by FROM platform.change_set WHERE change_set_id = NEW.subject_id) THEN
    RAISE EXCEPTION 'SELF_APPROVAL: the requester cannot approve their own change' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER approval_task_check BEFORE INSERT OR UPDATE ON platform.approval_task
  FOR EACH ROW EXECUTE FUNCTION platform.check_approval_task();

-- Whether an employee sees a change on their own profile yet (§7.3)
CREATE FUNCTION platform.employee_sees_change(p_change_set uuid, p_viewer_user uuid, p_as_of date DEFAULT current_date)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT cs.requested_by = p_viewer_user
      OR (cs.status IN ('approved','scheduled','committed') AND CASE platform.setting(cs.tenant_id, 'self_service.show_changes', p_as_of) #>> '{}'
            WHEN 'when_approved'  THEN true
            WHEN 'when_effective' THEN cs.effective_date <= p_as_of
            ELSE cs.communicated_at IS NOT NULL END)
  FROM platform.change_set cs WHERE cs.change_set_id = p_change_set
$$;

-- -------------------------------------------------------------------------------------
-- 11. Overpayments held until recovery is authorized (§7.2)
-- -------------------------------------------------------------------------------------
ALTER TABLE payroll.retro_request DROP CONSTRAINT IF EXISTS retro_request_status_check;
ALTER TABLE payroll.retro_request
  ADD CONSTRAINT retro_request_status_check
  CHECK (status IN ('queued','calculated','approved','paid','no_difference','overpayment_held','cancelled'));

CREATE TABLE payroll.overpayment (
  tenant_id                 uuid NOT NULL,
  overpayment_id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id             uuid NOT NULL REFERENCES core.employment,
  retro_request_id          uuid REFERENCES payroll.retro_request,
  source                    text NOT NULL CHECK (source IN ('retro','correction','manual','other')),
  gross_amount              numeric(14,2) NOT NULL CHECK (gross_amount > 0),
  net_amount                numeric(14,2),
  identified_on             date NOT NULL,
  status                    text NOT NULL DEFAULT 'held'
                            CHECK (status IN ('held','authorization_requested','authorized','recovering','recovered','waived','disputed','cancelled')),
  recovery_basis            text CHECK (recovery_basis IN ('employee_authorization','jurisdiction_rule','agreement_rule','court_order')),
  authorization_document_id uuid REFERENCES platform.document,
  authorized_on             date,
  schedule                  jsonb,                     -- [{ "payOnOrAfter": "2026-12-04", "amount": "50.00" }]
  basis_ref                 text,                      -- rule, article or order when not by the employee's authorization
  recovered_amount          numeric(14,2) NOT NULL DEFAULT 0,
  decided_by                uuid,
  reason                    text,
  created_at                timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT recovery_needs_basis CHECK (status NOT IN ('authorized','recovering','recovered') OR (
       (recovery_basis = 'employee_authorization' AND authorization_document_id IS NOT NULL AND authorized_on IS NOT NULL AND schedule IS NOT NULL)
    OR (recovery_basis IN ('jurisdiction_rule','agreement_rule','court_order') AND basis_ref IS NOT NULL AND schedule IS NOT NULL))),
  CONSTRAINT recovered_within_amount CHECK (recovered_amount >= 0 AND recovered_amount <= gross_amount),
  CONSTRAINT waiver_needs_reason CHECK (status <> 'waived' OR (decided_by IS NOT NULL AND reason IS NOT NULL))
);

CREATE FUNCTION payroll.check_overpayment() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le uuid;
BEGIN
  IF NEW.status IN ('authorized','recovering','recovered') AND NEW.recovery_basis IN ('jurisdiction_rule','agreement_rule') THEN
    SELECT legal_entity_id INTO le FROM core.employment WHERE employment_id = NEW.employment_id;
    IF platform.setting(NEW.tenant_id, 'payroll.overpayment_recovery', NEW.identified_on, le) #>> '{}' <> 'jurisdiction_rule_allows' THEN
      RAISE EXCEPTION 'OVERPAYMENT_NEEDS_AUTHORIZATION: this organization recovers overpayments only with the employee''s written authorization'
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER overpayment_check BEFORE INSERT OR UPDATE ON payroll.overpayment
  FOR EACH ROW EXECUTE FUNCTION payroll.check_overpayment();

ALTER TABLE payroll.one_time_item ADD COLUMN overpayment_id uuid REFERENCES payroll.overpayment;
CREATE FUNCTION payroll.check_recovery_item() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.overpayment_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM payroll.overpayment o WHERE o.overpayment_id = NEW.overpayment_id AND o.status IN ('authorized','recovering')) THEN
    RAISE EXCEPTION 'OVERPAYMENT_NOT_AUTHORIZED: no recovery before the overpayment is authorized' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER one_time_item_recovery_check BEFORE INSERT OR UPDATE OF overpayment_id ON payroll.one_time_item
  FOR EACH ROW EXECUTE FUNCTION payroll.check_recovery_item();

-- -------------------------------------------------------------------------------------
-- 12. Agreements against employment standards; who prepared an agreement (§8)
-- -------------------------------------------------------------------------------------
ALTER TABLE core.agreement_version
  ADD COLUMN prepared_by text CHECK (prepared_by IN ('cando','partner','customer'));

CREATE TABLE core.agreement_standards_finding (
  tenant_id           uuid NOT NULL,
  finding_id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agreement_id        text NOT NULL,
  version             int NOT NULL,
  jurisdiction        ref.jurisdiction_code NOT NULL,
  standard_code       text NOT NULL,                   -- e.g. 'overtime.daily', 'statutory_holiday.pay', 'vacation.entitlement'
  agreement_ref       text,                            -- article
  finding             text NOT NULL CHECK (finding IN ('meets_or_exceeds','below_law_replaceable','below_law_not_replaceable','not_verified')),
  comparison          text NOT NULL CHECK (comparison IN ('per_hour','whole_standard')),
  detail              jsonb NOT NULL DEFAULT '{}'::jsonb,
  hr_approved_by      uuid,
  hr_approved_at      timestamptz,
  payroll_approved_by uuid,
  payroll_approved_at timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (tenant_id, agreement_id, version) REFERENCES core.agreement_version (tenant_id, agreement_id, version),
  UNIQUE (tenant_id, agreement_id, version, jurisdiction, standard_code),
  CHECK ((hr_approved_by IS NULL) = (hr_approved_at IS NULL)),
  CHECK ((payroll_approved_by IS NULL) = (payroll_approved_at IS NULL)),
  CONSTRAINT two_people_approve CHECK (hr_approved_by IS NULL OR payroll_approved_by IS NULL OR hr_approved_by <> payroll_approved_by),
  CONSTRAINT approvals_only_below_law CHECK (finding = 'below_law_replaceable' OR (hr_approved_by IS NULL AND payroll_approved_by IS NULL))
);

CREATE FUNCTION core.check_agreement_findings() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE bad text;
BEGIN
  IF NEW.status = 'active' AND OLD.status IS DISTINCT FROM 'active' THEN
    SELECT string_agg(jurisdiction || ':' || standard_code, ', ') INTO bad FROM core.agreement_standards_finding
      WHERE tenant_id = NEW.tenant_id AND agreement_id = NEW.agreement_id AND version = NEW.version AND finding = 'not_verified';
    IF bad IS NOT NULL THEN
      RAISE EXCEPTION 'RULE_NOT_VERIFIED: employment standards not yet verified for %', bad USING ERRCODE = 'check_violation';
    END IF;
    SELECT string_agg(jurisdiction || ':' || standard_code, ', ') INTO bad FROM core.agreement_standards_finding
      WHERE tenant_id = NEW.tenant_id AND agreement_id = NEW.agreement_id AND version = NEW.version
        AND finding = 'below_law_replaceable' AND (hr_approved_by IS NULL OR payroll_approved_by IS NULL);
    IF bad IS NOT NULL THEN
      RAISE EXCEPTION 'AGREEMENT_BELOW_LAW_NOT_APPROVED: the HR and payroll administrators must both approve %', bad
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER agreement_version_findings_gate BEFORE UPDATE OF status ON core.agreement_version
  FOR EACH ROW EXECUTE FUNCTION core.check_agreement_findings();

-- -------------------------------------------------------------------------------------
-- 13. Bank account changes: second factor, notices, hold, live check by HR (§9.1)
-- -------------------------------------------------------------------------------------
CREATE TABLE payroll.bank_change_request (
  tenant_id            uuid NOT NULL,
  request_id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id        uuid NOT NULL REFERENCES core.employment,
  bank_account_id      uuid NOT NULL REFERENCES payroll.bank_account,   -- the new pay destination
  requested_by_user    uuid NOT NULL,
  channel              text NOT NULL CHECK (channel IN ('self_service','hr_on_behalf','import')),
  reauthenticated_at   timestamptz,                    -- second factor at the time of the change
  notices_sent_at      timestamptz,                    -- to the email and phone already on file
  hold_until           timestamptz,
  verification_method  text CHECK (verification_method IN ('video','phone')),
  phone_on_file_used   boolean,
  id_type_seen         text CHECK (id_type_seen IN ('drivers_licence','passport','provincial_photo_id','status_card','other_government_photo_id')),
  verified_by          uuid,
  verified_at          timestamptz,
  status               text NOT NULL DEFAULT 'pending_verification'
                       CHECK (status IN ('pending_verification','approved','rejected','cancelled','in_effect')),
  reason               text,
  created_at           timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT self_service_needs_second_factor CHECK (channel <> 'self_service' OR reauthenticated_at IS NOT NULL),
  CONSTRAINT verifier_not_requester CHECK (verified_by IS NULL OR verified_by <> requested_by_user),
  CONSTRAINT rejection_needs_reason CHECK (status <> 'rejected' OR reason IS NOT NULL)
);
COMMENT ON TABLE payroll.bank_change_request IS
  'No image or number of the ID document is ever stored: only its type, who saw it, how and when (docs/21 §9.1).';

CREATE FUNCTION payroll.check_bank_change_request() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE le uuid; hold int;
BEGIN
  SELECT legal_entity_id INTO le FROM core.employment WHERE employment_id = NEW.employment_id;
  hold := (platform.setting(NEW.tenant_id, 'bank_change.hold_hours', NEW.created_at::date, le) #>> '{}')::int;
  NEW.hold_until := greatest(coalesce(NEW.hold_until, NEW.created_at), NEW.created_at + make_interval(hours => hold));
  IF NEW.status IN ('approved','in_effect') AND NEW.channel <> 'import' THEN
    IF NEW.notices_sent_at IS NULL THEN
      RAISE EXCEPTION 'BANK_CHANGE_NOTICE_MISSING: notices go to the email and phone on file before approval' USING ERRCODE = 'check_violation';
    END IF;
    IF (platform.setting(NEW.tenant_id, 'bank_change.hr_live_verification', NEW.created_at::date, le) #>> '{}')::boolean THEN
      IF NEW.verification_method IS NULL OR NEW.id_type_seen IS NULL OR NEW.verified_by IS NULL OR NEW.verified_at IS NULL THEN
        RAISE EXCEPTION 'BANK_CHANGE_NOT_VERIFIED: HR approves after a live video or phone check with photo ID' USING ERRCODE = 'check_violation';
      END IF;
      IF NEW.verification_method = 'phone' AND NEW.phone_on_file_used IS NOT TRUE THEN
        RAISE EXCEPTION 'BANK_CHANGE_PHONE_NOT_ON_FILE: call the number already on file, never one given with the request' USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;
  IF NEW.status = 'in_effect' AND now() < NEW.hold_until THEN
    RAISE EXCEPTION 'BANK_CHANGE_ON_HOLD: pay can go to the new account from %', NEW.hold_until USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER bank_change_request_check BEFORE INSERT OR UPDATE ON payroll.bank_change_request
  FOR EACH ROW EXECUTE FUNCTION payroll.check_bank_change_request();

-- Payment files use an account only if it came from a change now in effect (or was loaded before 0007)
CREATE FUNCTION payroll.bank_account_usable(p_bank_account uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (SELECT 1 FROM payroll.bank_change_request r WHERE r.bank_account_id = p_bank_account)
      OR EXISTS (SELECT 1 FROM payroll.bank_change_request r WHERE r.bank_account_id = p_bank_account AND r.status = 'in_effect')
$$;

-- -------------------------------------------------------------------------------------
-- 14. Self-identification categories, each with its purpose and its own consent (§9.2)
-- -------------------------------------------------------------------------------------
CREATE TABLE core.self_id_category (
  tenant_id            uuid NOT NULL,
  category_code        text NOT NULL,
  origin               text NOT NULL CHECK (origin IN ('cando_standard','tenant')),
  name_en              text NOT NULL,
  name_fr              text,
  question_en          text NOT NULL,
  question_fr          text,
  purpose_en           text NOT NULL,
  purpose_fr           text,
  answer_options       jsonb NOT NULL,                 -- [{ "code": "yes", "en": "…", "fr": "…" }, …, { "code": "prefer_not_to_answer", … }]
  official_group       text CHECK (official_group IN ('ee_women','ee_indigenous','ee_disability','ee_visible_minority')),
  consent_text_version text NOT NULL,
  status               text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','retired')),
  PRIMARY KEY (tenant_id, category_code),
  CONSTRAINT answers_offer_decline CHECK (jsonb_typeof(answer_options) = 'array' AND answer_options @> '[{"code":"prefer_not_to_answer"}]'),
  CONSTRAINT official_groups_are_standard CHECK (official_group IS NULL OR origin = 'cando_standard')
);

CREATE TABLE core.self_id_consent (
  tenant_id            uuid NOT NULL,
  person_id            uuid NOT NULL REFERENCES core.person,
  category_code        text NOT NULL,
  consent_given_at     timestamptz NOT NULL,
  consent_text_version text NOT NULL,
  withdrawn_at         timestamptz,
  PRIMARY KEY (person_id, category_code, consent_given_at),
  FOREIGN KEY (tenant_id, category_code) REFERENCES core.self_id_category (tenant_id, category_code),
  CHECK (withdrawn_at IS NULL OR withdrawn_at >= consent_given_at)
);
COMMENT ON TABLE core.self_identification IS
  'Answers stay encrypted here; consent is recorded per category in core.self_id_consent (docs/21 §9.2). No gender field exists anywhere else.';

-- -------------------------------------------------------------------------------------
-- 15. OCAP® data isolation and support access (§9.3)
-- -------------------------------------------------------------------------------------
ALTER TABLE platform.tenant
  ADD COLUMN data_isolation text NOT NULL DEFAULT 'shared' CHECK (data_isolation IN ('shared','dedicated')),
  ADD COLUMN ocap_controls  boolean NOT NULL DEFAULT false;

CREATE TABLE platform.support_access_grant (
  tenant_id     uuid NOT NULL REFERENCES platform.tenant,
  grant_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requested_by  text NOT NULL,                          -- CanDo staff identity, never a tenant user
  purpose       text NOT NULL,
  scope         jsonb NOT NULL DEFAULT '{}'::jsonb,
  valid_period  tstzrange NOT NULL,
  status        text NOT NULL DEFAULT 'requested' CHECK (status IN ('requested','approved','declined','revoked','expired')),
  approved_by   uuid REFERENCES platform.app_user,
  approved_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (status <> 'approved' OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CHECK (upper(valid_period) - lower(valid_period) <= interval '7 days')
);

-- -------------------------------------------------------------------------------------
-- Row-level security on every new tenant table (same policy as 0001); platform.tenant stays outside
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
      AND n.nspname IN ('platform','core','payroll')
      AND NOT (n.nspname = 'platform' AND c.relname = 'tenant')
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

-- Grants follow 0002_roles: cando_app gets SELECT on platform.setting_definition; SELECT, INSERT and UPDATE on the
-- new tenant tables; EXECUTE on the new functions. Only the identity Worker writes platform.support_access_grant
-- approvals, and only a tenant user can approve one.
