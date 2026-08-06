-- ============================================================================
-- permissions.sql  (run after all objects exist)
-- Least-privilege grants for the application role `admission_app`. The API never
-- connects as a superuser. Registries are additionally write-protected by
-- triggers (defense in depth).
-- ============================================================================

GRANT USAGE ON SCHEMA public TO admission_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO admission_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO admission_app;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO admission_app;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA public TO admission_app;

-- The app may READ the identity registries but never write them (these are the
-- authoritative auto-fill sources; seeding is done as superuser, and triggers
-- also block writes). NOTE: quota_type, class_eligibility and
-- school_class_eligibility are intentionally NOT locked — they are managed
-- configuration written at runtime through protected endpoints: quotas by the
-- master admin, and each school's own accepted date-of-birth window by that
-- school's authority. So the app role keeps write access to them.
REVOKE INSERT, UPDATE, DELETE ON
    postcode, birth_certificate, nid, quota_reference
    FROM admission_app;

-- Make future objects (if any are added later) inherit the same defaults.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO admission_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO admission_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO admission_app;
