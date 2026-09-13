-- ============================================================================
-- seeds/03_settings.sql
-- Initial application settings the applicant flow reads. The admission round is
-- open and results are not yet published. In the full system these flags are
-- toggled by the admin/authority side; here they are seeded to a sane starting
-- state so the applicant portion runs standalone.
-- ============================================================================

-- MAX_APPLICATIONS is the per-student cap enforced by
-- trg_application_max_three. It lives here, not as a literal in the trigger, so
-- the trigger, the API and the apply form all read the same number and an admin
-- can retune it without a schema change.
INSERT INTO app_setting (key, value) VALUES
    ('ROUND_OPEN', 'TRUE'),
    ('RESULT_READY', 'FALSE'),
    ('MAX_APPLICATIONS', '3')
ON CONFLICT (key) DO NOTHING;
