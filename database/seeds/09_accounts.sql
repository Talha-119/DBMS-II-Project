-- ============================================================================
-- seeds/09_accounts.sql
-- Demo login accounts (passwords stored bcrypt-hashed via fn_hash_password) and
-- initial app settings. CHANGE THESE PASSWORDS for any real deployment.
-- ============================================================================

-- Master admin: login "admin" / password "admin123".
INSERT INTO account (role, login_id, password_hash, eiin, must_change_password)
VALUES ('MASTER_ADMIN', 'admin', fn_hash_password('admin123'), NULL, FALSE)
ON CONFLICT (login_id) DO NOTHING;

-- A couple of school-authority logins (login = EIIN). Password "school123".
INSERT INTO account (role, login_id, password_hash, eiin, must_change_password)
VALUES
    ('SCHOOL_AUTHORITY', '108103', fn_hash_password('school123'), '108103', FALSE),
    ('SCHOOL_AUTHORITY', '108101', fn_hash_password('school123'), '108101', FALSE),
    ('SCHOOL_AUTHORITY', '108201', fn_hash_password('school123'), '108201', FALSE)
ON CONFLICT (login_id) DO NOTHING;

-- Admission round is open; results not yet published.
-- ADMISSION_YEAR is the reference year for age limits: a class's advertised age
-- range is measured at 1 January of this year (see fn_admission_reference_date).
INSERT INTO app_setting (key, value) VALUES
    ('ROUND_OPEN', 'TRUE'),
    ('RESULT_READY', 'FALSE'),
    ('ADMISSION_YEAR', '2026')
ON CONFLICT (key) DO NOTHING;
