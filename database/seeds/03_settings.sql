-- ============================================================================
-- seeds/03_settings.sql
-- Initial application settings the applicant flow reads. The admission round is
-- open and results are not yet published. In the full system these flags are
-- toggled by the admin/authority side; here they are seeded to a sane starting
-- state so the applicant portion runs standalone.
-- ============================================================================

INSERT INTO app_setting (key, value) VALUES
    ('ROUND_OPEN', 'TRUE'),
    ('RESULT_READY', 'FALSE')
ON CONFLICT (key) DO NOTHING;
