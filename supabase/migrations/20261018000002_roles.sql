-- CanDo application roles (passwords set in CI from secrets, not in migrations).

CREATE ROLE cando_app LOGIN NOBYPASSRLS;
CREATE ROLE cando_sealer LOGIN NOBYPASSRLS;

ALTER ROLE cando_app SET search_path = platform, core, payroll, timeleave, recruit, comp, benefits, talent, offboard, compliance, ref, extensions, public;
ALTER ROLE cando_sealer SET search_path = platform, extensions, public;

GRANT USAGE ON SCHEMA platform, core, payroll, timeleave, recruit, comp, benefits, talent, offboard, compliance, ref TO cando_app, cando_sealer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA platform, core, payroll, timeleave, recruit, comp, benefits, talent, offboard, compliance TO cando_app;
GRANT SELECT ON ALL TABLES IN SCHEMA ref TO cando_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA platform, core, payroll, timeleave, recruit, comp, benefits, talent, offboard, compliance TO cando_app;

GRANT INSERT, SELECT ON platform.audit_entry TO cando_app;
GRANT SELECT ON platform.audit_batch TO cando_app;
GRANT SELECT, UPDATE (batch_id) ON platform.audit_entry TO cando_sealer;
GRANT INSERT, SELECT ON platform.audit_batch TO cando_sealer;

DO $$
DECLARE s text;
BEGIN
  FOREACH s IN ARRAY ARRAY['platform','core','payroll','timeleave','recruit','comp','benefits','talent','offboard','compliance','ref']
  LOOP
    EXECUTE format('REVOKE ALL ON SCHEMA %I FROM anon, authenticated', s);
    EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA %I FROM anon, authenticated', s);
    EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA %I FROM anon, authenticated', s);
    EXECUTE format('REVOKE ALL ON ALL FUNCTIONS IN SCHEMA %I FROM anon, authenticated', s);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I REVOKE ALL ON TABLES FROM anon, authenticated', s);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I REVOKE ALL ON SEQUENCES FROM anon, authenticated', s);
    EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I REVOKE ALL ON FUNCTIONS FROM anon, authenticated', s);
  END LOOP;
END $$;
