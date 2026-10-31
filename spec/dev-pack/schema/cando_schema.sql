-- =====================================================================================
-- CanDo HRIS — PostgreSQL 16 schema (starting migration)
-- Conventions:
--   * Every tenant-owned table has tenant_id and row-level security (see end of file).
--   * Effective-dated entities: identity table + *_version table with
--       valid_period daterange (business time, [start, end)) and
--       sys_period   tstzrange (system time; current row has upper_inf(sys_period)).
--     An exclusion constraint guarantees one current row per entity per day.
--   * Money: numeric(14,2). Rates: numeric(12,6). Never float.
--   * Every version row records the change_set_id that produced it.
-- Validated by loading into PostgreSQL 16 (see tests/schema/load_schema.sh).
-- =====================================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS ref;
CREATE SCHEMA IF NOT EXISTS platform;
CREATE SCHEMA IF NOT EXISTS core;
CREATE SCHEMA IF NOT EXISTS payroll;
CREATE SCHEMA IF NOT EXISTS timeleave;
CREATE SCHEMA IF NOT EXISTS recruit;
CREATE SCHEMA IF NOT EXISTS comp;
CREATE SCHEMA IF NOT EXISTS benefits;
CREATE SCHEMA IF NOT EXISTS talent;      -- performance, learning, succession, engagement
CREATE SCHEMA IF NOT EXISTS offboard;
CREATE SCHEMA IF NOT EXISTS compliance;

-- -------------------------------------------------------------------------------------
-- Shared types
-- -------------------------------------------------------------------------------------
CREATE TYPE ref.jurisdiction_code AS ENUM
  ('FED','NL','PE','NS','NB','QC','ON','MB','SK','AB','BC','YT','NT','NU');
CREATE TYPE ref.province_code AS ENUM
  ('NL','PE','NS','NB','QC','ON','MB','SK','AB','BC','YT','NT','NU');
CREATE TYPE ref.lang AS ENUM ('en','fr');

-- =====================================================================================
-- REF — global reference data (no RLS; read-only to the application role)
-- =====================================================================================
CREATE TABLE ref.rule_edition (
  edition_id      text PRIMARY KEY,                 -- e.g. 'CA-2026-07-01'
  family          text NOT NULL CHECK (family IN ('statutory','employer_taxes','employment_standards','quebec_tax')),
  tax_year        int  NOT NULL,
  effective_from  date NOT NULL,
  effective_to    date NOT NULL,
  content         jsonb NOT NULL,                   -- the JSON file from rules/
  content_sha256  text NOT NULL,
  status          text NOT NULL CHECK (status IN ('draft','tested','active','retired')),
  supersedes      text REFERENCES ref.rule_edition,  -- a correction is a new edition, never an edit
  activated_by    text,
  activated_at    timestamptz,
  CHECK (effective_to >= effective_from)
);
CREATE INDEX ON ref.rule_edition (family, effective_from, effective_to);
ALTER TABLE ref.rule_edition ADD CONSTRAINT rule_edition_no_overlap
  EXCLUDE USING gist (family WITH =, daterange(effective_from, effective_to, '[]') WITH &&)
  WHERE (status = 'active');

CREATE TABLE ref.holiday (
  jurisdiction  ref.jurisdiction_code NOT NULL,
  holiday_date  date NOT NULL,
  observed_date date NOT NULL,
  code          text NOT NULL,
  name_en       text NOT NULL,
  name_fr       text NOT NULL,
  statutory     boolean NOT NULL DEFAULT true,
  PRIMARY KEY (jurisdiction, holiday_date, code)
);

CREATE TABLE ref.noc (
  noc_code    text PRIMARY KEY,                     -- NOC 2021, 5 digits
  teer        smallint NOT NULL CHECK (teer BETWEEN 0 AND 5),
  title_en    text NOT NULL,
  title_fr    text NOT NULL
);

-- =====================================================================================
-- PLATFORM — tenants, identity, change sets, audit, outbox, documents, workflow
-- =====================================================================================
CREATE TABLE platform.tenant (
  tenant_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name             text NOT NULL,
  residency        text NOT NULL DEFAULT 'CA' CHECK (residency IN ('CA','EU')),
  languages        ref.lang[] NOT NULL DEFAULT ARRAY['en','fr']::ref.lang[],
  org_mode         text NOT NULL DEFAULT 'position' CHECK (org_mode IN ('position','light')),
  modules_enabled  text[] NOT NULL DEFAULT ARRAY['core'],
  assistant_enabled boolean NOT NULL DEFAULT false,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE platform.app_user (
  tenant_id     uuid NOT NULL REFERENCES platform.tenant,
  user_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  idp_subject   text NOT NULL,
  email         citext NOT NULL,
  person_id     uuid,                                -- link to core.person when the user is an employee
  locale        text NOT NULL DEFAULT 'en-CA' CHECK (locale IN ('en-CA','fr-CA')),
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled')),
  mfa_required  boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, idp_subject)
);

CREATE TABLE platform.role (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  role_code   text NOT NULL,
  name_en     text NOT NULL,
  name_fr     text NOT NULL,
  permissions jsonb NOT NULL,       -- [{ "action": "read", "fieldClass": "employment", "entity": "assignment" }, ...]
  PRIMARY KEY (tenant_id, role_code)
);

CREATE TABLE platform.role_grant (
  tenant_id    uuid NOT NULL REFERENCES platform.tenant,
  grant_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES platform.app_user,
  role_code    text NOT NULL,
  scope        jsonb NOT NULL,      -- { "type": "subtree", "orgUnitId": "..." } | { "type": "legal_entities", "ids": [...] } | { "type": "self" } ...
  valid_period daterange NOT NULL DEFAULT daterange(current_date, NULL),
  granted_by   uuid,
  reason       text,
  FOREIGN KEY (tenant_id, role_code) REFERENCES platform.role (tenant_id, role_code)
);

CREATE TABLE platform.change_set (
  tenant_id       uuid NOT NULL REFERENCES platform.tenant,
  change_set_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number          bigint NOT NULL,                   -- human-readable per tenant
  kind            text NOT NULL,                     -- hire, transfer, reorg, rate_change, correction, agreement_activation, ...
  reason_code     text NOT NULL,
  is_correction   boolean NOT NULL DEFAULT false,
  effective_date  date NOT NULL,
  source          text NOT NULL CHECK (source IN ('ui_form','org_chart','mass_change','import','api','workflow','assistant_draft','system')),
  plan_id         uuid,                              -- set when part of a what-if plan
  status          text NOT NULL CHECK (status IN ('draft','validated','pending_approval','approved','scheduled','committed','rejected','cancelled')),
  requested_by    uuid NOT NULL,
  requested_at    timestamptz NOT NULL DEFAULT now(),
  committed_at    timestamptz,
  base_versions   jsonb NOT NULL DEFAULT '{}'::jsonb, -- optimistic concurrency: { "assignment:<id>": 7 }
  validation      jsonb,                             -- { errors: [], warnings: [], consequences: [] }
  retro_estimate  numeric(14,2),
  comment         text,
  UNIQUE (tenant_id, number)
);
CREATE INDEX ON platform.change_set (tenant_id, status, effective_date);

CREATE TABLE platform.change_set_operation (
  tenant_id      uuid NOT NULL,
  change_set_id  uuid NOT NULL REFERENCES platform.change_set ON DELETE CASCADE,
  seq            int  NOT NULL,
  op             text NOT NULL,                      -- e.g. 'assignment.update'
  target_type    text NOT NULL,
  target_id      uuid,
  payload        jsonb NOT NULL,                     -- the 'set' values; sensitive values stored encrypted in payload_secure
  payload_secure bytea,
  added_by_cascade boolean NOT NULL DEFAULT false,
  PRIMARY KEY (change_set_id, seq)
);

CREATE TABLE platform.plan (
  tenant_id   uuid NOT NULL REFERENCES platform.tenant,
  plan_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text NOT NULL,
  owner_id    uuid NOT NULL,
  members     uuid[] NOT NULL DEFAULT '{}',
  as_of       date NOT NULL,
  status      text NOT NULL CHECK (status IN ('open','submitted','approved','discarded')),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE platform.approval_task (
  tenant_id     uuid NOT NULL,
  task_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subject_type  text NOT NULL,                       -- change_set | pay_run | requisition | leave_request | ...
  subject_id    uuid NOT NULL,
  step          int NOT NULL,
  assignee_user uuid,
  assignee_role text,
  status        text NOT NULL CHECK (status IN ('open','approved','rejected','delegated','expired')),
  due_at        timestamptz,
  decided_by    uuid,
  decided_at    timestamptz,
  comment       text
);
CREATE INDEX ON platform.approval_task (tenant_id, assignee_user, status);

CREATE TABLE platform.audit_entry (
  tenant_id     uuid NOT NULL,
  audit_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  actor_type    text NOT NULL CHECK (actor_type IN ('user','system','assistant','integration')),
  actor_id      text NOT NULL,
  on_behalf_of  uuid,
  action        text NOT NULL,                       -- change_set.commit | sensitive.reveal | export | login | payrun.approve ...
  subject_type  text NOT NULL,
  subject_id    text NOT NULL,
  change_set_id uuid,
  before        jsonb,
  after         jsonb,
  reason        text,
  ip            inet,
  user_agent    text,
  leaf_hash     bytea NOT NULL CHECK (length(leaf_hash) = 32),   -- SHA-256(0x00 || canonical(row)), see reference/audit_merkle_reference.py
  batch_id      bigint                                          -- set by the hourly sealing job
);
CREATE INDEX ON platform.audit_entry (tenant_id, subject_type, subject_id, occurred_at);
CREATE INDEX audit_unsealed ON platform.audit_entry (tenant_id, audit_id) WHERE batch_id IS NULL;

-- Hourly Merkle batches per tenant; each batch is signed and anchored to write-once storage (docs/10 §5)
CREATE TABLE platform.audit_batch (
  tenant_id        uuid NOT NULL,
  batch_id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  batch_no         bigint NOT NULL,                  -- 1, 2, 3 ... per tenant, no gaps
  first_audit_id   bigint,
  last_audit_id    bigint,
  leaf_count       int NOT NULL CHECK (leaf_count >= 0),
  sealed_at        timestamptz NOT NULL,
  merkle_root      bytea NOT NULL CHECK (length(merkle_root) = 32),
  prev_batch_hash  bytea NOT NULL CHECK (length(prev_batch_hash) = 32),
  batch_hash       bytea NOT NULL CHECK (length(batch_hash) = 32),
  signature        bytea NOT NULL,                   -- KMS asymmetric signature over batch_hash
  signing_key_id   text NOT NULL,
  anchor_uri       text,                             -- s3://<anchor-account bucket in ca-west-1>/<tenant>/<batch_no>.json
  anchor_version_id text,                            -- S3 object version (Object Lock, compliance mode)
  anchored_at      timestamptz,
  customer_digest_sent_at timestamptz,
  UNIQUE (tenant_id, batch_no)
);
ALTER TABLE platform.audit_entry ADD FOREIGN KEY (batch_id) REFERENCES platform.audit_batch;

CREATE TABLE platform.outbox (
  tenant_id     uuid NOT NULL,
  event_id      uuid PRIMARY KEY,
  subject_key   text NOT NULL,
  type          text NOT NULL,
  payload       jsonb NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  published_at  timestamptz,
  attempts      int NOT NULL DEFAULT 0,
  last_error    text
);
CREATE INDEX outbox_unpublished ON platform.outbox (created_at) WHERE published_at IS NULL;

CREATE TABLE platform.processed_event (
  tenant_id   uuid NOT NULL,
  subscriber  text NOT NULL,
  event_id    uuid NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (subscriber, event_id)
);

CREATE TABLE platform.document (
  tenant_id       uuid NOT NULL,
  document_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_type      text NOT NULL,                     -- person | position | agreement | case | requisition ...
  owner_id        uuid NOT NULL,
  doc_type        text NOT NULL,
  access_class    text NOT NULL,                     -- matches field classes in docs/10
  retention_class text NOT NULL,
  language        ref.lang,
  storage_key     text NOT NULL,                     -- S3 key
  sha256          text NOT NULL,
  mime_type       text NOT NULL,
  legal_hold      boolean NOT NULL DEFAULT false,
  uploaded_by     uuid NOT NULL,
  uploaded_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE platform.notification (
  tenant_id     uuid NOT NULL,
  notification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL,
  template_code text NOT NULL,
  data          jsonb NOT NULL,
  channel       text NOT NULL CHECK (channel IN ('in_app','email','sms','push')),
  status        text NOT NULL CHECK (status IN ('queued','sent','read','failed')),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- =====================================================================================
-- CORE HR
-- =====================================================================================
CREATE TABLE core.employer_group (
  tenant_id         uuid NOT NULL,
  employer_group_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name              text NOT NULL
);

CREATE TABLE core.legal_entity (
  tenant_id       uuid NOT NULL,
  legal_entity_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE core.legal_entity_version (
  tenant_id         uuid NOT NULL,
  version_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  legal_entity_id   uuid NOT NULL REFERENCES core.legal_entity,
  valid_period      daterange NOT NULL,
  sys_period        tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id     uuid NOT NULL,
  legal_name        text NOT NULL,
  operating_name_en text,
  operating_name_fr text,
  business_number   char(9) NOT NULL,
  regulatory_jurisdiction text NOT NULL CHECK (regulatory_jurisdiction IN ('federal','provincial')),
  employer_group_id uuid REFERENCES core.employer_group,
  fiscal_year_start_month smallint NOT NULL DEFAULT 1 CHECK (fiscal_year_start_month BETWEEN 1 AND 12),
  revenu_quebec_id  text,                            -- phase 2
  first_nation_government boolean NOT NULL DEFAULT false,
  EXCLUDE USING gist (legal_entity_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

CREATE TABLE core.payroll_account (
  tenant_id        uuid NOT NULL,
  payroll_account_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_entity_id  uuid NOT NULL REFERENCES core.legal_entity,
  rp_number        char(6) NOT NULL,                 -- 'RP0001'
  remitter_type    text NOT NULL CHECK (remitter_type IN ('quarterly','regular','accelerated_1','accelerated_2')),
  remitter_type_valid daterange NOT NULL,
  ei_employer_rate numeric(6,4) NOT NULL DEFAULT 1.4, -- reduced rate if registered wage-loss plan
  UNIQUE (legal_entity_id, rp_number)
);

CREATE TABLE core.location (
  tenant_id   uuid NOT NULL,
  location_id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);
CREATE TABLE core.location_version (
  tenant_id       uuid NOT NULL,
  version_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  location_id     uuid NOT NULL REFERENCES core.location,
  valid_period    daterange NOT NULL,
  sys_period      tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id   uuid NOT NULL,
  name            text NOT NULL,
  address_line1   text NOT NULL,
  address_line2   text,
  city            text NOT NULL,
  province        ref.province_code NOT NULL,
  postal_code     text NOT NULL CHECK (postal_code ~ '^[A-Z][0-9][A-Z] ?[0-9][A-Z][0-9]$'),
  time_zone       text NOT NULL,                     -- IANA, e.g. 'America/Toronto'
  holiday_jurisdiction ref.jurisdiction_code NOT NULL,
  northern_zone   text CHECK (northern_zone IN ('none','prescribed','intermediate')),
  on_reserve      boolean NOT NULL DEFAULT false,
  remote_work_site boolean NOT NULL DEFAULT false,
  EXCLUDE USING gist (location_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

CREATE TABLE core.org_unit (
  tenant_id   uuid NOT NULL,
  org_unit_id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);
CREATE TABLE core.org_unit_version (
  tenant_id         uuid NOT NULL,
  version_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  org_unit_id       uuid NOT NULL REFERENCES core.org_unit,
  valid_period      daterange NOT NULL,
  sys_period        tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id     uuid NOT NULL,
  legal_entity_id   uuid NOT NULL REFERENCES core.legal_entity,
  unit_type         text NOT NULL CHECK (unit_type IN ('division','department','branch','team','program','board_or_commission')),
  code              text NOT NULL,
  name_en           text NOT NULL,
  name_fr           text,
  parent_org_unit_id uuid REFERENCES core.org_unit,
  head_position_id  uuid,
  cost_centre       text,
  fund_code         text,
  confidential      boolean NOT NULL DEFAULT false,
  status            text NOT NULL DEFAULT 'active' CHECK (status IN ('active','closed')),
  EXCLUDE USING gist (org_unit_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);
CREATE INDEX ON core.org_unit_version (tenant_id, parent_org_unit_id) WHERE upper_inf(sys_period);

CREATE TABLE core.job (
  tenant_id uuid NOT NULL,
  job_id    uuid PRIMARY KEY DEFAULT gen_random_uuid()
);
CREATE TABLE core.job_version (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  job_id           uuid NOT NULL REFERENCES core.job,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  code             text NOT NULL,
  title_en         text NOT NULL,
  title_fr         text,
  family           text,
  level            text,
  grade            text,
  noc_code         text REFERENCES ref.noc,
  overtime_eligible boolean NOT NULL DEFAULT true,
  default_bargaining_unit text,                      -- null = excluded
  exclusion_reason text,
  pay_equity_class text,
  ee_occupational_group text,
  EXCLUDE USING gist (job_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

CREATE TABLE core.position (
  tenant_id   uuid NOT NULL,
  position_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number      text NOT NULL,
  UNIQUE (tenant_id, number)
);
CREATE TABLE core.position_version (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  position_id      uuid NOT NULL REFERENCES core.position,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  job_id           uuid NOT NULL REFERENCES core.job,
  title_override_en text,
  title_override_fr text,
  org_unit_id      uuid NOT NULL REFERENCES core.org_unit,
  location_id      uuid NOT NULL REFERENCES core.location,
  reports_to_position_id uuid REFERENCES core.position,
  fte_budget       numeric(6,4) NOT NULL CHECK (fte_budget > 0),
  budgeted_hours   numeric(8,2),
  employment_type  text NOT NULL CHECK (employment_type IN ('permanent','term','casual','auxiliary','seasonal','student')),
  bargaining_unit  text,
  agreement_id     text,
  language_requirement text CHECK (language_requirement IN ('en','fr','bilingual_b','bilingual_c','other')),
  security_clearance text,
  status           text NOT NULL CHECK (status IN ('active','frozen','eliminated')),
  confidential     boolean NOT NULL DEFAULT false,
  EXCLUDE USING gist (position_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period)),
  CHECK (reports_to_position_id IS DISTINCT FROM position_id)
);
CREATE INDEX ON core.position_version (tenant_id, reports_to_position_id) WHERE upper_inf(sys_period);

CREATE TABLE core.position_funding (
  tenant_id    uuid NOT NULL,
  funding_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position_id  uuid NOT NULL REFERENCES core.position,
  valid_period daterange NOT NULL,
  fund_code    text NOT NULL,
  funder       text,
  percent      numeric(5,2) NOT NULL CHECK (percent > 0 AND percent <= 100),
  agreement_ref text
);

CREATE TABLE core.person (
  tenant_id  uuid NOT NULL,
  person_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_type text NOT NULL DEFAULT 'employee' CHECK (person_type IN ('employee','elected_official','board_appointee','volunteer','contractor','student','candidate_converted')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE core.person_version (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  person_id        uuid NOT NULL REFERENCES core.person,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  legal_first_name text NOT NULL,
  legal_last_name  text NOT NULL,
  preferred_name   text,
  pronouns         text,
  preferred_language ref.lang NOT NULL DEFAULT 'en',
  personal_email   citext,
  mobile_phone     text,
  home_address     jsonb,                           -- { line1, line2, city, province, postalCode, country }
  emergency_contacts jsonb,
  EXCLUDE USING gist (person_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

-- Restricted personal data: separate table, field-level encryption (envelope key per tenant)
CREATE TABLE core.person_sensitive (
  tenant_id      uuid NOT NULL,
  person_id      uuid PRIMARY KEY REFERENCES core.person,
  sin_enc        bytea,                              -- encrypted SIN
  sin_last3      char(3),                            -- for masked display
  date_of_birth_enc bytea,
  birth_year     smallint,                           -- for age rules without decrypting
  birth_month    smallint,
  key_id         text NOT NULL,
  updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.work_authorization (
  tenant_id     uuid NOT NULL,
  authorization_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id     uuid NOT NULL REFERENCES core.person,
  kind          text NOT NULL CHECK (kind IN ('citizen','permanent_resident','work_permit','study_permit','other')),
  document_number_enc bytea,
  valid_period  daterange NOT NULL,
  verified_by   uuid,
  verified_at   timestamptz
);

-- Voluntary self-identification: separate store, aggregate reporting only
CREATE TABLE core.self_identification (
  tenant_id     uuid NOT NULL,
  person_id     uuid PRIMARY KEY REFERENCES core.person,
  data_enc      bytea NOT NULL,
  consent_given_at timestamptz NOT NULL,
  consent_text_version text NOT NULL,
  key_id        text NOT NULL
);

CREATE TABLE core.employment (
  tenant_id       uuid NOT NULL,
  employment_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id       uuid NOT NULL REFERENCES core.person,
  legal_entity_id uuid NOT NULL REFERENCES core.legal_entity,
  employee_number text NOT NULL,
  UNIQUE (tenant_id, employee_number)
);
CREATE TABLE core.employment_version (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employment_id    uuid NOT NULL REFERENCES core.employment,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  original_hire_date date NOT NULL,
  continuous_service_date date NOT NULL,
  employment_type  text NOT NULL CHECK (employment_type IN ('permanent','term','casual','auxiliary','seasonal','student')),
  status           text NOT NULL CHECK (status IN ('active','on_leave','suspended','terminated')),
  probation_end    date,
  term_end         date,
  termination_reason text,
  rehire_eligible  boolean,
  EXCLUDE USING gist (employment_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

CREATE TABLE payroll.pay_group (
  tenant_id        uuid NOT NULL,
  pay_group_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_account_id uuid NOT NULL REFERENCES core.payroll_account,
  code             text NOT NULL,
  name             text NOT NULL,
  frequency        text NOT NULL CHECK (frequency IN ('weekly','biweekly','semimonthly','monthly','daily','annual','quarterly','other')),
  periods_per_year jsonb NOT NULL,                   -- { "2026": 26, "2027": 27 } — fixed at start of each year
  proration_method text NOT NULL DEFAULT 'working_days' CHECK (proration_method IN ('calendar_days','working_days','scheduled_hours')),
  UNIQUE (tenant_id, code)
);

CREATE TABLE core.assignment (
  tenant_id     uuid NOT NULL,
  assignment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment
);
CREATE TABLE core.assignment_version (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  assignment_id    uuid NOT NULL REFERENCES core.assignment,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  assignment_type  text NOT NULL DEFAULT 'regular' CHECK (assignment_type IN ('regular','acting','secondment','overlap')),
  position_id      uuid REFERENCES core.position,    -- null in light mode
  org_unit_id      uuid NOT NULL REFERENCES core.org_unit,
  location_id      uuid NOT NULL REFERENCES core.location,
  manager_assignment_id uuid REFERENCES core.assignment, -- light mode or explicit override
  fte              numeric(6,4) NOT NULL CHECK (fte > 0 AND fte <= 1.5),
  pay_group_id     uuid REFERENCES payroll.pay_group,
  agreement_id     text,
  bargaining_unit  text,
  is_primary       boolean NOT NULL,
  schedule_template_id uuid,
  EXCLUDE USING gist (assignment_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);
CREATE INDEX ON core.assignment_version (tenant_id, position_id) WHERE upper_inf(sys_period);
CREATE INDEX ON core.assignment_version (tenant_id, org_unit_id) WHERE upper_inf(sys_period);

CREATE TABLE core.assignment_relationship (
  tenant_id      uuid NOT NULL,
  relationship_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id  uuid NOT NULL REFERENCES core.assignment,
  related_assignment_id uuid NOT NULL REFERENCES core.assignment,
  kind           text NOT NULL CHECK (kind IN ('dotted','acting_manager','delegate','mentor')),
  valid_period   daterange NOT NULL,
  change_set_id  uuid NOT NULL
);

CREATE TABLE core.pay_rate (
  tenant_id   uuid NOT NULL,
  pay_rate_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES core.assignment
);
CREATE TABLE core.pay_rate_version (
  tenant_id     uuid NOT NULL,
  version_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pay_rate_id   uuid NOT NULL REFERENCES core.pay_rate,
  valid_period  daterange NOT NULL,
  sys_period    tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id uuid NOT NULL,
  basis         text NOT NULL CHECK (basis IN ('hourly','annual_salary','period_salary','daily')),
  amount        numeric(14,4) NOT NULL CHECK (amount >= 0),
  standard_hours_per_week numeric(6,2),
  grid_classification text,
  grid_step     smallint,
  source        text NOT NULL CHECK (source IN ('agreement_grid','compensation_decision','offer','manual','progression_job','retro_settlement')),
  EXCLUDE USING gist (pay_rate_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

CREATE TABLE core.external_ref (
  tenant_id   uuid NOT NULL,
  system      text NOT NULL,                         -- 'entra', 'erp', 'carrier:sunlife', ...
  ref_type    text NOT NULL,
  ref_value   text NOT NULL,
  entity_type text NOT NULL,
  entity_id   uuid NOT NULL,
  PRIMARY KEY (tenant_id, system, ref_type, ref_value)
);

-- Collective agreements (rules JSON per rules/agreements/agreement.schema.json)
CREATE TABLE core.agreement (
  tenant_id     uuid NOT NULL,
  agreement_id  text NOT NULL,
  name          text NOT NULL,
  union_name    text NOT NULL,
  local         text,
  jurisdiction  ref.jurisdiction_code NOT NULL,
  status        text NOT NULL CHECK (status IN ('in_force','expired_bridging','in_bargaining','superseded')),
  source_document_id uuid REFERENCES platform.document,
  PRIMARY KEY (tenant_id, agreement_id)
);
CREATE TABLE core.agreement_version (
  tenant_id      uuid NOT NULL,
  agreement_id   text NOT NULL,
  version        int NOT NULL,
  effective_from date NOT NULL,
  effective_to   date,
  ratified_on    date,
  retro_from     date,
  rules          jsonb NOT NULL,
  content_sha256 text NOT NULL,                     -- of the canonical rules JSON; pinned by pay runs
  status         text NOT NULL CHECK (status IN ('draft','in_verification','verified','active','superseded')),
  activated_change_set_id uuid,
  PRIMARY KEY (tenant_id, agreement_id, version),
  FOREIGN KEY (tenant_id, agreement_id) REFERENCES core.agreement (tenant_id, agreement_id)
);

CREATE TABLE core.seniority_ledger (
  tenant_id     uuid NOT NULL,
  entry_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employment_id uuid NOT NULL REFERENCES core.employment,
  agreement_id  text NOT NULL,
  seniority_type text NOT NULL,
  entry_date    date NOT NULL,
  hours         numeric(10,2),
  days          numeric(10,2),
  reason        text NOT NULL,
  change_set_id uuid
);

-- =====================================================================================
-- PAYROLL
-- =====================================================================================
CREATE TABLE payroll.payroll_profile (
  tenant_id     uuid NOT NULL,
  profile_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL UNIQUE REFERENCES core.employment
);
CREATE TABLE payroll.payroll_profile_version (
  tenant_id        uuid NOT NULL,
  version_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  profile_id       uuid NOT NULL REFERENCES payroll.payroll_profile,
  valid_period     daterange NOT NULL,
  sys_period       tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id    uuid NOT NULL,
  tax_province_override ref.province_code,           -- null = derived from work location
  override_reason  text,
  td1_federal_claim numeric(12,2),                   -- null = basic personal amount (claim code 1)
  td1_provincial_claim numeric(12,2),
  td1_signed_document_id uuid,
  additional_tax_per_period numeric(12,2) NOT NULL DEFAULT 0,
  annual_deductions_f1 numeric(12,2) NOT NULL DEFAULT 0,
  northern_deduction_hd numeric(12,2) NOT NULL DEFAULT 0,
  other_federal_credits_k3 numeric(12,2) NOT NULL DEFAULT 0,
  other_provincial_credits_k3p numeric(12,2) NOT NULL DEFAULT 0,
  on_dependants_under_19 smallint NOT NULL DEFAULT 0,
  on_dependants_disabled smallint NOT NULL DEFAULT 0,
  cpp_exempt_reason text,                            -- e.g. 'disability_pension', 'cpt30'
  cpt30_effective  date,
  ei_exempt_reason text,
  s87_status       text NOT NULL DEFAULT 'not_applicable' CHECK (s87_status IN ('not_applicable','exempt_full','exempt_partial','under_review')),
  s87_evidence_document_id uuid,
  s87_cpp_elected  boolean NOT NULL DEFAULT false,
  commission_td1x  jsonb,
  non_resident     boolean NOT NULL DEFAULT false,
  EXCLUDE USING gist (profile_id WITH =, valid_period WITH &&) WHERE (upper_inf(sys_period))
);

CREATE TABLE payroll.bank_account (
  tenant_id     uuid NOT NULL,
  bank_account_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  institution   char(3) NOT NULL,
  transit       char(5) NOT NULL,
  account_enc   bytea NOT NULL,
  account_last3 char(3) NOT NULL,
  split_type    text NOT NULL CHECK (split_type IN ('remainder','amount','percent')),
  split_value   numeric(14,2),
  priority      smallint NOT NULL,
  valid_period  daterange NOT NULL,
  verified_at   timestamptz,
  key_id        text NOT NULL
);

CREATE TABLE payroll.pay_code (
  tenant_id     uuid NOT NULL,
  pay_code      text NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('earning','deduction','employer_cost','benefit','memo')),
  name_en       text NOT NULL,
  name_fr       text NOT NULL,
  taxable       boolean NOT NULL DEFAULT true,
  non_periodic  boolean NOT NULL DEFAULT false,      -- bonus method
  cpp_pensionable boolean NOT NULL DEFAULT true,
  ei_insurable  boolean NOT NULL DEFAULT true,
  vacationable  boolean NOT NULL DEFAULT true,
  accrues_leave boolean NOT NULL DEFAULT false,
  reduces_taxable text CHECK (reduces_taxable IN ('F','F2','U1','none')),
  t4_box        text,
  t4_other_code text,
  rl1_box       text,                                -- phase 2
  gl_account    text,
  priority      smallint,                            -- deduction order when net is insufficient
  PRIMARY KEY (tenant_id, pay_code)
);

CREATE TABLE payroll.pay_period (
  tenant_id     uuid NOT NULL,
  pay_period_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_group_id  uuid NOT NULL REFERENCES payroll.pay_group,
  tax_year      int NOT NULL,
  period_number smallint NOT NULL,
  work_period   daterange NOT NULL,
  cutoff_at     timestamptz NOT NULL,
  pay_date      date NOT NULL,
  status        text NOT NULL CHECK (status IN ('future','open','processing','closed')),
  UNIQUE (pay_group_id, tax_year, period_number)
);

CREATE TABLE payroll.pay_run (
  tenant_id     uuid NOT NULL,
  pay_run_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number        bigint NOT NULL,
  run_type      text NOT NULL CHECK (run_type IN ('regular','off_cycle','bonus','retro','final','adjustment','reversal','manual_payment_record','simulation')),
  legal_entity_id uuid NOT NULL REFERENCES core.legal_entity,
  pay_group_id  uuid REFERENCES payroll.pay_group,
  pay_period_id uuid REFERENCES payroll.pay_period,
  population    jsonb NOT NULL,                      -- { mode, ids | query | changeSetId }
  work_period   daterange,                           -- null for bonus-only runs
  pay_date      date NOT NULL,
  tax_year      int GENERATED ALWAYS AS (extract(year FROM pay_date)::int) STORED,
  tax_method    text NOT NULL DEFAULT 'auto' CHECK (tax_method IN ('auto','periodic','non_periodic')),
  rule_edition_id text REFERENCES ref.rule_edition,
  engine_version text,
  inputs_known_at timestamptz,                       -- every read during calculation uses knownAt = this (docs/06 §8)
  bucket_count  smallint CHECK (bucket_count BETWEEN 1 AND 256),
  status        text NOT NULL CHECK (status IN ('draft','inputs_locked','calculating','calculated','reviewed','approved','finalized','paid','cancelled')),
  reason        text,
  created_by    uuid NOT NULL,
  approved_by   uuid,
  finalized_at  timestamptz,
  control_totals jsonb,
  UNIQUE (tenant_id, number),
  CHECK (approved_by IS NULL OR approved_by <> created_by)
);

CREATE TABLE payroll.pay_result (
  tenant_id     uuid NOT NULL,
  pay_result_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_run_id    uuid NOT NULL REFERENCES payroll.pay_run,
  employment_id uuid NOT NULL REFERENCES core.employment,
  person_id     uuid NOT NULL REFERENCES core.person,
  payroll_account_id uuid NOT NULL REFERENCES core.payroll_account,
  bucket        smallint NOT NULL,
  pay_date      date NOT NULL,
  tax_year      int NOT NULL,
  province      ref.province_code NOT NULL,
  periods_per_year smallint NOT NULL,
  tax_method    text NOT NULL,
  gross         numeric(14,2) NOT NULL,
  taxable_periodic numeric(14,2) NOT NULL,
  taxable_non_periodic numeric(14,2) NOT NULL,
  pensionable   numeric(14,2) NOT NULL,
  insurable     numeric(14,2) NOT NULL,
  cpp           numeric(14,2) NOT NULL,
  cpp2          numeric(14,2) NOT NULL,
  ei            numeric(14,2) NOT NULL,
  income_tax_federal numeric(14,2) NOT NULL,
  income_tax_provincial numeric(14,2) NOT NULL,
  territorial_payroll_tax numeric(14,2) NOT NULL DEFAULT 0,
  net           numeric(14,2) NOT NULL,
  employer_cpp  numeric(14,2) NOT NULL,
  employer_cpp2 numeric(14,2) NOT NULL,
  employer_ei   numeric(14,2) NOT NULL,
  input_snapshot_sha256 text NOT NULL,
  result_sha256 text NOT NULL,                       -- canonical result + lines; replayed nightly
  agreement_versions jsonb,
  trace         jsonb NOT NULL,                      -- [{ label, value, ref }]
  reverses_result_id uuid REFERENCES payroll.pay_result,
  status        text NOT NULL CHECK (status IN ('calculated','finalized','reversed')),
  is_simulation boolean NOT NULL DEFAULT false
);
CREATE INDEX ON payroll.pay_result (tenant_id, employment_id, tax_year);

CREATE TABLE payroll.pay_result_line (
  tenant_id     uuid NOT NULL,
  line_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pay_result_id uuid NOT NULL REFERENCES payroll.pay_result,
  pay_code      text NOT NULL,
  assignment_id uuid REFERENCES core.assignment,
  work_period   daterange,
  hours         numeric(10,2),
  rate          numeric(14,4),
  amount        numeric(14,2) NOT NULL,
  ytd_amount    numeric(14,2),
  org_unit_id   uuid,
  cost_centre   text,
  fund_code     text,
  gl_account    text,
  fiscal_year   int,
  fiscal_period smallint,
  retro_of_result_id uuid REFERENCES payroll.pay_result,
  source        text NOT NULL                       -- salary, time, leave, one_time, benefit, statutory, retro, agreement_premium
);

CREATE TABLE payroll.ytd_accumulator (
  tenant_id     uuid NOT NULL,
  person_id     uuid NOT NULL REFERENCES core.person,   -- maximums are per person per employer account
  payroll_account_id uuid NOT NULL REFERENCES core.payroll_account,
  tax_year      int NOT NULL,
  province      ref.province_code NOT NULL,
  code          text NOT NULL,                       -- pay code or statutory bucket: CPP, CPP2, EI, PI, IE, TAX_FED, ...
  amount        numeric(14,2) NOT NULL,
  updated_by_result_id uuid,
  PRIMARY KEY (person_id, payroll_account_id, tax_year, province, code)
);

-- Rule pins: written at inputs_locked; workers load rules by hash (docs/06 §8)
CREATE TABLE payroll.pay_run_rule_pin (
  tenant_id     uuid NOT NULL,
  pay_run_id    uuid NOT NULL REFERENCES payroll.pay_run,
  family        text NOT NULL CHECK (family IN ('statutory','employment_standards','employer_taxes','quebec_tax','agreement','policy','engine')),
  ref_id        text NOT NULL,                       -- edition id, 'AGREEMENT-ID@version', or git commit for 'engine'
  content_sha256 text NOT NULL,
  PRIMARY KEY (pay_run_id, family, ref_id)
);

-- Subject leases: one open (not finalized/cancelled) run per person per payroll account (docs/06 §9)
CREATE TABLE payroll.pay_run_subject (
  tenant_id     uuid NOT NULL,
  pay_run_id    uuid NOT NULL REFERENCES payroll.pay_run,
  payroll_account_id uuid NOT NULL REFERENCES core.payroll_account,
  person_id     uuid NOT NULL REFERENCES core.person,
  bucket        smallint NOT NULL,
  leased_at     timestamptz NOT NULL DEFAULT now(),
  released_at   timestamptz,
  PRIMARY KEY (pay_run_id, payroll_account_id, person_id)
);
CREATE UNIQUE INDEX pay_run_subject_one_open_run
  ON payroll.pay_run_subject (tenant_id, payroll_account_id, person_id) WHERE released_at IS NULL;

-- Calculation buckets, claimed by workers with FOR UPDATE SKIP LOCKED
CREATE TABLE payroll.pay_run_partition (
  tenant_id     uuid NOT NULL,
  pay_run_id    uuid NOT NULL REFERENCES payroll.pay_run,
  bucket        smallint NOT NULL,
  subject_count int NOT NULL,
  status        text NOT NULL CHECK (status IN ('pending','calculating','calculated','failed','finalized')),
  worker_id     text,
  attempts      smallint NOT NULL DEFAULT 0,
  started_at    timestamptz,
  finished_at   timestamptz,
  results_checksum text,                             -- sha256 over the sorted result_sha256 values of the bucket
  PRIMARY KEY (pay_run_id, bucket)
);

CREATE TABLE payroll.one_time_item (
  tenant_id     uuid NOT NULL,
  item_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  pay_code      text NOT NULL,
  amount        numeric(14,2) NOT NULL,
  work_period   daterange,
  pay_on_or_after date NOT NULL,
  source        text NOT NULL,                       -- comp_decision, offboarding, manual, award
  status        text NOT NULL CHECK (status IN ('pending','included','paid','cancelled')),
  included_in_result_id uuid REFERENCES payroll.pay_result
);

CREATE TABLE payroll.retro_request (
  tenant_id     uuid NOT NULL,
  retro_request_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  trigger_change_set_id uuid NOT NULL,
  original_result_id uuid NOT NULL REFERENCES payroll.pay_result,
  status        text NOT NULL CHECK (status IN ('queued','calculated','approved','paid','no_difference','cancelled')),
  difference    jsonb,                               -- by pay code, PI, IE, pension, employer costs
  paid_in_result_id uuid REFERENCES payroll.pay_result,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE payroll.payment_file (
  tenant_id     uuid NOT NULL,
  file_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_run_id    uuid NOT NULL REFERENCES payroll.pay_run,
  format        text NOT NULL CHECK (format IN ('cpa005','iso20022_pain001','positive_pay')),
  bank_profile  text NOT NULL,
  storage_key   text NOT NULL,
  sha256        text NOT NULL,
  record_count  int NOT NULL,
  total_amount  numeric(16,2) NOT NULL,
  released_by   uuid[] NOT NULL DEFAULT '{}',        -- dual control
  released_at   timestamptz
);

CREATE TABLE payroll.remittance (
  tenant_id     uuid NOT NULL,
  remittance_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payee         text NOT NULL,                       -- CRA, RQ, WSIB, ON_EHT, NT_PAYROLL_TAX, union:<id>, pension:<id>, garnishee:<id>
  payroll_account_id uuid REFERENCES core.payroll_account,
  period        daterange NOT NULL,
  due_date      date NOT NULL,
  amount        numeric(16,2) NOT NULL,
  breakdown     jsonb NOT NULL,
  status        text NOT NULL CHECK (status IN ('calculated','scheduled','paid','late')),
  paid_on       date
);

CREATE TABLE payroll.slip (
  tenant_id     uuid NOT NULL,
  slip_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  payroll_account_id uuid NOT NULL REFERENCES core.payroll_account,
  tax_year      int NOT NULL,
  slip_type     text NOT NULL CHECK (slip_type IN ('T4','T4A','RL1','NR4')),
  report_type   text NOT NULL CHECK (report_type IN ('original','amended','cancelled')),
  province      ref.province_code NOT NULL,
  boxes         jsonb NOT NULL,
  filed_in_submission uuid,
  status        text NOT NULL CHECK (status IN ('draft','validated','filed','accepted','rejected'))
);

CREATE TABLE payroll.roe (
  tenant_id     uuid NOT NULL,
  roe_id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  serial_number text,
  reason_code   char(1) NOT NULL,
  first_day_worked date NOT NULL,
  last_day_paid date NOT NULL,
  final_pay_period_end date NOT NULL,
  blocks        jsonb NOT NULL,                      -- 15A/15B/15C insurable hours and earnings, 17 other monies, 19 ...
  amends_roe_id uuid REFERENCES payroll.roe,
  status        text NOT NULL CHECK (status IN ('draft','validated','submitted','accepted','rejected')),
  due_date      date NOT NULL
);

CREATE TABLE payroll.gl_journal (
  tenant_id     uuid NOT NULL,
  journal_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pay_run_id    uuid NOT NULL REFERENCES payroll.pay_run,
  kind          text NOT NULL CHECK (kind IN ('cash','accrual','accrual_reversal','retro')),
  fiscal_year   int NOT NULL,
  fiscal_period smallint NOT NULL,
  lines         jsonb NOT NULL,
  exported_at   timestamptz,
  target_system text
);

-- =====================================================================================
-- TIME & LEAVE
-- =====================================================================================
CREATE TABLE timeleave.schedule_template (
  tenant_id     uuid NOT NULL,
  schedule_template_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  cycle_days    smallint NOT NULL,
  pattern       jsonb NOT NULL                       -- [{ day: 1, start: '07:00', end: '19:00', breakMinutes: 30 }, ...]
);

CREATE TABLE timeleave.shift (
  tenant_id     uuid NOT NULL,
  shift_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid REFERENCES core.assignment,     -- null = open shift
  position_id   uuid REFERENCES core.position,
  location_id   uuid NOT NULL REFERENCES core.location,
  starts_at     timestamptz NOT NULL,
  ends_at       timestamptz NOT NULL,
  break_minutes smallint NOT NULL DEFAULT 0,
  published     boolean NOT NULL DEFAULT false,
  CHECK (ends_at > starts_at)
);

CREATE TABLE timeleave.punch (
  tenant_id     uuid NOT NULL,
  punch_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES core.assignment,
  punched_at    timestamptz NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('in','out','break_start','break_end','job_switch')),
  device        text,
  geo_ok        boolean,                             -- result of geofence check only; no coordinates stored
  original_punched_at timestamptz,
  edited_by     uuid,
  edit_reason   text
);

CREATE TABLE timeleave.timesheet (
  tenant_id     uuid NOT NULL,
  timesheet_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES core.assignment,
  pay_period_id uuid NOT NULL REFERENCES payroll.pay_period,
  status        text NOT NULL CHECK (status IN ('open','submitted','approved','locked','corrected')),
  approved_by   uuid,
  approved_at   timestamptz,
  UNIQUE (assignment_id, pay_period_id)
);

CREATE TABLE timeleave.time_line (
  tenant_id     uuid NOT NULL,
  line_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  timesheet_id  uuid NOT NULL REFERENCES timeleave.timesheet,
  work_date     date NOT NULL,
  pay_code      text NOT NULL,
  hours         numeric(8,2) NOT NULL,
  rate_basis    text NOT NULL DEFAULT 'regular_rate' CHECK (rate_basis IN ('regular_rate','minimum_wage','flat')),
  cost_allocation jsonb,
  rule_source   text,                                -- 'es:BC' | 'agreement:EXAMPLE-MUNI-0001#2:15'
  sys_period    tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id uuid
);

CREATE TABLE timeleave.leave_type (
  tenant_id     uuid NOT NULL,
  leave_type_code text NOT NULL,
  name_en       text NOT NULL,
  name_fr       text NOT NULL,
  category      text NOT NULL,
  statutory     boolean NOT NULL,
  jurisdictions ref.jurisdiction_code[] NOT NULL,
  paid_percent  numeric(5,2) NOT NULL DEFAULT 0,
  job_protected boolean NOT NULL DEFAULT false,
  reason_restricted boolean NOT NULL DEFAULT false,  -- e.g. domestic violence leave
  roe_trigger   boolean NOT NULL DEFAULT false,
  PRIMARY KEY (tenant_id, leave_type_code)
);

CREATE TABLE timeleave.leave_ledger (
  tenant_id     uuid NOT NULL,
  entry_id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  employment_id uuid NOT NULL REFERENCES core.employment,
  leave_type_code text NOT NULL,
  entry_date    date NOT NULL,
  kind          text NOT NULL CHECK (kind IN ('opening','accrual','taken','adjustment','payout','expiry','carryover')),
  hours         numeric(10,2),
  amount        numeric(14,2),                       -- for percentage-of-wages plans
  rule_source   text,
  sys_period    tstzrange NOT NULL DEFAULT tstzrange(now(), NULL),
  change_set_id uuid
);
CREATE INDEX ON timeleave.leave_ledger (tenant_id, employment_id, leave_type_code, entry_date) WHERE upper_inf(sys_period);

CREATE TABLE timeleave.leave_request (
  tenant_id     uuid NOT NULL,
  leave_request_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  leave_type_code text NOT NULL,
  period        tstzrange NOT NULL,
  hours         numeric(8,2) NOT NULL,
  status        text NOT NULL CHECK (status IN ('requested','approved','declined','cancelled','taken')),
  case_id       uuid,
  approved_by   uuid
);

-- =====================================================================================
-- RECRUITMENT & ONBOARDING (key tables; see requirements/02 for the full data model)
-- =====================================================================================
CREATE TABLE recruit.requisition (
  tenant_id     uuid NOT NULL,
  requisition_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  number        text NOT NULL,
  position_id   uuid REFERENCES core.position,
  requisition_type text NOT NULL CHECK (requisition_type IN ('replacement','additional_headcount','new_position')),
  openings      smallint NOT NULL DEFAULT 1,
  salary_min    numeric(14,2),
  salary_max    numeric(14,2),
  posting_jurisdiction ref.jurisdiction_code NOT NULL,
  uses_ai_screening boolean NOT NULL DEFAULT false,
  vacancy_exists boolean NOT NULL DEFAULT true,
  status        text NOT NULL CHECK (status IN ('draft','pending_approval','approved','posted','on_hold','filled','cancelled')),
  change_set_id uuid,
  UNIQUE (tenant_id, number),
  CHECK (salary_max IS NULL OR salary_min IS NULL OR salary_max >= salary_min)
);

CREATE TABLE recruit.candidate (
  tenant_id     uuid NOT NULL,
  candidate_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  first_name    text NOT NULL,
  last_name     text NOT NULL,
  email         citext NOT NULL,
  phone         text,
  consent       jsonb NOT NULL,
  retention_until date NOT NULL
);

CREATE TABLE recruit.application (
  tenant_id     uuid NOT NULL,
  application_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requisition_id uuid NOT NULL REFERENCES recruit.requisition,
  candidate_id  uuid NOT NULL REFERENCES recruit.candidate,
  stage         text NOT NULL,
  internal_employment_id uuid REFERENCES core.employment,
  seniority_considered numeric(10,2),
  interviewed   boolean NOT NULL DEFAULT false,
  outcome       text,
  outcome_notified_at timestamptz,                   -- Ontario: within 45 days of last interview
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE recruit.offer (
  tenant_id     uuid NOT NULL,
  offer_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id uuid NOT NULL REFERENCES recruit.application,
  start_date    date NOT NULL,
  pay_rate      numeric(14,4) NOT NULL,
  pay_basis     text NOT NULL,
  status        text NOT NULL CHECK (status IN ('draft','approved','sent','accepted','declined','withdrawn')),
  hire_change_set_id uuid                            -- created on acceptance; writes Core HR through the normal path
);

CREATE TABLE recruit.onboarding_task (
  tenant_id     uuid NOT NULL,
  task_id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  code          text NOT NULL,
  owner_role    text NOT NULL,
  due_date      date,
  status        text NOT NULL CHECK (status IN ('open','done','waived'))
);

-- =====================================================================================
-- COMPENSATION, BENEFITS, TALENT, OFFBOARDING, COMPLIANCE (core tables)
-- =====================================================================================
CREATE TABLE comp.salary_range (
  tenant_id    uuid NOT NULL,
  range_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  grade        text NOT NULL,
  valid_period daterange NOT NULL,
  minimum      numeric(14,2) NOT NULL,
  midpoint     numeric(14,2) NOT NULL,
  maximum      numeric(14,2) NOT NULL,
  CHECK (minimum <= midpoint AND midpoint <= maximum)
);

CREATE TABLE comp.cycle (
  tenant_id    uuid NOT NULL,
  cycle_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL,
  effective_date date NOT NULL,
  budget       numeric(16,2),
  status       text NOT NULL CHECK (status IN ('planning','open','in_review','approved','loaded'))
);

CREATE TABLE comp.decision (
  tenant_id    uuid NOT NULL,
  decision_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cycle_id     uuid REFERENCES comp.cycle,
  assignment_id uuid NOT NULL REFERENCES core.assignment,
  kind         text NOT NULL CHECK (kind IN ('merit','promotion','market_adjustment','bonus','lump_sum')),
  amount       numeric(14,2),
  percent      numeric(6,3),
  effective_date date NOT NULL,
  status       text NOT NULL CHECK (status IN ('proposed','approved','rejected','loaded')),
  change_set_id uuid
);

CREATE TABLE benefits.plan (
  tenant_id    uuid NOT NULL,
  plan_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code         text NOT NULL,
  carrier      text,
  kind         text NOT NULL CHECK (kind IN ('health','dental','life','add','std','ltd','eap','hsa','pension_db','pension_dc','group_rrsp','tfsa','other')),
  taxable_benefit_rule jsonb,
  eligibility  jsonb NOT NULL
);

CREATE TABLE benefits.enrolment (
  tenant_id    uuid NOT NULL,
  enrolment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  plan_id      uuid NOT NULL REFERENCES benefits.plan,
  coverage_level text NOT NULL,
  valid_period daterange NOT NULL,
  employee_cost_per_period numeric(14,2) NOT NULL,
  employer_cost_per_period numeric(14,2) NOT NULL,
  change_set_id uuid
);

CREATE TABLE talent.review (
  tenant_id    uuid NOT NULL,
  review_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  cycle_code   text NOT NULL,
  kind         text NOT NULL CHECK (kind IN ('probation','annual','mid_year','pip')),
  reviewer_assignment_id uuid REFERENCES core.assignment,
  rating       text,
  status       text NOT NULL CHECK (status IN ('not_started','self','manager','calibration','signed','closed'))
);

CREATE TABLE talent.learning_record (
  tenant_id    uuid NOT NULL,
  record_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  person_id    uuid NOT NULL REFERENCES core.person,
  course_code  text NOT NULL,
  completed_on date,
  expires_on   date,
  credential   boolean NOT NULL DEFAULT false
);

CREATE TABLE talent.succession_slate (
  tenant_id    uuid NOT NULL,
  slate_id     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  position_id  uuid NOT NULL REFERENCES core.position,
  candidate_employment_id uuid NOT NULL REFERENCES core.employment,
  readiness    text NOT NULL CHECK (readiness IN ('ready_now','1_2_years','3_plus_years')),
  reviewed_on  date NOT NULL
);

CREATE TABLE talent.survey_response (
  tenant_id    uuid NOT NULL,
  response_id  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  survey_code  text NOT NULL,
  org_unit_id  uuid,                                 -- no person link for anonymous surveys
  answers      jsonb NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE offboard.separation (
  tenant_id    uuid NOT NULL,
  separation_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employment_id uuid NOT NULL REFERENCES core.employment,
  reason       text NOT NULL,
  notice_given_on date,
  last_day_worked date NOT NULL,
  termination_date date NOT NULL,
  statutory_notice_weeks numeric(5,2),
  severance_weeks numeric(5,2),
  rule_sources jsonb,
  access_removal_at timestamptz,
  status       text NOT NULL CHECK (status IN ('draft','approved','in_progress','complete')),
  change_set_id uuid
);

CREATE TABLE compliance.case_file (
  tenant_id    uuid NOT NULL,
  case_id      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind         text NOT NULL CHECK (kind IN ('grievance','accommodation','return_to_work','investigation','privacy_request','wcb_claim','pay_equity','other')),
  subject_employment_id uuid REFERENCES core.employment,
  agreement_id text,
  status       text NOT NULL,
  restricted   boolean NOT NULL DEFAULT true,
  opened_on    date NOT NULL,
  closed_on    date
);

CREATE TABLE compliance.retention_rule (
  tenant_id    uuid NOT NULL,
  retention_class text NOT NULL,
  jurisdiction ref.jurisdiction_code,
  keep_years   smallint NOT NULL,
  trigger      text NOT NULL,                        -- e.g. 'end_of_tax_year', 'termination', 'case_closed'
  PRIMARY KEY (tenant_id, retention_class)
);

-- =====================================================================================
-- Immutability of pinned rule content (docs/06 §8)
-- =====================================================================================
CREATE FUNCTION ref.guard_rule_edition() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ord text[] := ARRAY['draft','tested','active','retired'];
BEGIN
  IF OLD.status <> 'draft' AND (NEW.content IS DISTINCT FROM OLD.content
      OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
      OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
      OR NEW.effective_to IS DISTINCT FROM OLD.effective_to
      OR NEW.family IS DISTINCT FROM OLD.family
      OR NEW.tax_year IS DISTINCT FROM OLD.tax_year) THEN
    RAISE EXCEPTION 'RULE_EDITION_IMMUTABLE: % is %, publish a new edition instead', OLD.edition_id, OLD.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF array_position(ord, NEW.status) < array_position(ord, OLD.status) THEN
    RAISE EXCEPTION 'RULE_EDITION_STATUS_BACKWARDS: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER rule_edition_immutable BEFORE UPDATE ON ref.rule_edition
  FOR EACH ROW EXECUTE FUNCTION ref.guard_rule_edition();
CREATE FUNCTION ref.block_delete_rule_edition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.status <> 'draft' THEN
    RAISE EXCEPTION 'RULE_EDITION_IMMUTABLE: % cannot be deleted', OLD.edition_id USING ERRCODE = 'check_violation';
  END IF;
  RETURN OLD;
END $$;
CREATE TRIGGER rule_edition_no_delete BEFORE DELETE ON ref.rule_edition
  FOR EACH ROW EXECUTE FUNCTION ref.block_delete_rule_edition();

CREATE FUNCTION core.guard_agreement_version() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE ord text[] := ARRAY['draft','in_verification','verified','active','superseded'];
BEGIN
  IF OLD.status IN ('verified','active','superseded') AND (NEW.rules IS DISTINCT FROM OLD.rules
      OR NEW.content_sha256 IS DISTINCT FROM OLD.content_sha256
      OR NEW.effective_from IS DISTINCT FROM OLD.effective_from
      OR NEW.retro_from IS DISTINCT FROM OLD.retro_from) THEN
    RAISE EXCEPTION 'AGREEMENT_VERSION_IMMUTABLE: %@% is %, create a new version instead', OLD.agreement_id, OLD.version, OLD.status
      USING ERRCODE = 'check_violation';
  END IF;
  IF array_position(ord, NEW.status) < array_position(ord, OLD.status) AND OLD.status IN ('verified','active','superseded') THEN
    RAISE EXCEPTION 'AGREEMENT_VERSION_STATUS_BACKWARDS: % -> %', OLD.status, NEW.status USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER agreement_version_immutable BEFORE UPDATE ON core.agreement_version
  FOR EACH ROW EXECUTE FUNCTION core.guard_agreement_version();

-- =====================================================================================
-- Helper: current-as-of functions (examples; generate one per versioned entity)
-- =====================================================================================
CREATE FUNCTION core.assignment_as_of(p_assignment uuid, p_date date, p_known timestamptz DEFAULT now())
RETURNS core.assignment_version
LANGUAGE sql STABLE AS $$
  SELECT v.* FROM core.assignment_version v
  WHERE v.assignment_id = p_assignment
    AND v.valid_period @> p_date
    AND v.sys_period @> p_known
  LIMIT 1
$$;

-- Org chart (position mode) as of a date: recursive walk of current position versions
CREATE FUNCTION core.position_tree_as_of(p_tenant uuid, p_root uuid, p_date date)
RETURNS TABLE (position_id uuid, reports_to_position_id uuid, depth int)
LANGUAGE sql STABLE AS $$
  WITH RECURSIVE pv AS (
    SELECT v.position_id, v.reports_to_position_id
    FROM core.position_version v
    WHERE v.tenant_id = p_tenant AND v.valid_period @> p_date AND upper_inf(v.sys_period)
      AND v.status <> 'eliminated'
  ), tree AS (
    SELECT pv.position_id, pv.reports_to_position_id, 0 AS depth FROM pv WHERE pv.position_id = p_root
    UNION ALL
    SELECT c.position_id, c.reports_to_position_id, t.depth + 1
    FROM pv c JOIN tree t ON c.reports_to_position_id = t.position_id
    WHERE t.depth < 50
  )
  SELECT * FROM tree
$$;

-- =====================================================================================
-- Row-level security on every tenant table
-- =====================================================================================
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT c.table_schema, c.table_name
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
    WHERE c.column_name = 'tenant_id'
      AND c.table_schema IN ('platform','core','payroll','timeleave','recruit','comp','benefits','talent','offboard','compliance')
      AND NOT (c.table_schema = 'platform' AND c.table_name = 'tenant')
  LOOP
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', r.table_schema, r.table_name);
    EXECUTE format('ALTER TABLE %I.%I FORCE ROW LEVEL SECURITY', r.table_schema, r.table_name);
    EXECUTE format($p$CREATE POLICY tenant_isolation ON %I.%I
                     USING (tenant_id = current_setting('app.tenant_id', true)::uuid)
                     WITH CHECK (tenant_id = current_setting('app.tenant_id', true)::uuid)$p$,
                   r.table_schema, r.table_name);
  END LOOP;
END $$;

-- Audit log is insert-only for the application role (grants are applied in the roles migration):
--   GRANT INSERT, SELECT ON platform.audit_entry TO cando_app;  -- no UPDATE, no DELETE
--   GRANT SELECT, UPDATE (batch_id) ON platform.audit_entry TO cando_sealer;  -- sealing job only
--   GRANT INSERT, SELECT ON platform.audit_batch TO cando_sealer;
--   GRANT SELECT ON platform.audit_batch TO cando_app;
-- The guard below stops even the sealer from moving a row that is already in a batch.
CREATE FUNCTION platform.guard_audit_entry() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'AUDIT_IMMUTABLE: audit rows cannot be deleted' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.batch_id IS NOT NULL
     OR (to_jsonb(NEW) - 'batch_id') IS DISTINCT FROM (to_jsonb(OLD) - 'batch_id') THEN
    RAISE EXCEPTION 'AUDIT_IMMUTABLE: only an unsealed row''s batch_id may be set' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER audit_entry_immutable BEFORE UPDATE OR DELETE ON platform.audit_entry
  FOR EACH ROW EXECUTE FUNCTION platform.guard_audit_entry();
CREATE FUNCTION platform.block_audit_batch_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Anchoring fields are filled once, after the S3 write succeeds; nothing else ever changes
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'AUDIT_IMMUTABLE: audit batches cannot be deleted' USING ERRCODE = 'check_violation';
  END IF;
  IF (to_jsonb(NEW) - ARRAY['anchor_uri','anchor_version_id','anchored_at','customer_digest_sent_at'])
       IS DISTINCT FROM (to_jsonb(OLD) - ARRAY['anchor_uri','anchor_version_id','anchored_at','customer_digest_sent_at'])
     OR (OLD.anchored_at IS NOT NULL AND (NEW.anchor_uri, NEW.anchor_version_id, NEW.anchored_at)
           IS DISTINCT FROM (OLD.anchor_uri, OLD.anchor_version_id, OLD.anchored_at)) THEN
    RAISE EXCEPTION 'AUDIT_IMMUTABLE: a sealed batch cannot change' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER audit_batch_immutable BEFORE UPDATE OR DELETE ON platform.audit_batch
  FOR EACH ROW EXECUTE FUNCTION platform.block_audit_batch_change();
