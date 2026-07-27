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

-- Least privilege for the applicant portion: the app role only WRITES the
-- applicant's own data (student, application, application_choice, choice_quota,
-- payment, otp, deletion_request). Everything else is READ ONLY for the app:
--   * the identity registries (authoritative auto-fill sources),
--   * the quota configuration and the school/seat catalogue (seeded here;
--     owned/managed by the separate admin/authority system),
--   * admission_result and app_setting (published/toggled by the admin system).
-- Seeding runs as superuser, so these revokes don't affect it; triggers also
-- block writes to the registries (defense in depth).
REVOKE INSERT, UPDATE, DELETE ON
    postcode, birth_certificate, nid, quota_reference, class_eligibility,
    quota_type, school, seat, seat_quota, admission_result, app_setting
    FROM admission_app;

-- Make future objects (if any are added later) inherit the same defaults.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO admission_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO admission_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT EXECUTE ON FUNCTIONS TO admission_app;
