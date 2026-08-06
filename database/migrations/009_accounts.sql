-- ============================================================================
-- 009_accounts.sql
-- Login accounts for the two privileged roles. Applicants have NO account
-- (they are identified by Birth-Cert + DOB + mobile OTP).
--   * MASTER_ADMIN    -> login_id is a username, eiin must be NULL
--   * SCHOOL_AUTHORITY -> login_id equals the school's EIIN, eiin must be set
-- ============================================================================

CREATE TABLE IF NOT EXISTS account (
    account_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    role                account_role_t NOT NULL,
    login_id            VARCHAR(40)    NOT NULL UNIQUE,
    password_hash       TEXT           NOT NULL,
    eiin                VARCHAR(10)     REFERENCES school(eiin) ON DELETE CASCADE,
    must_change_password BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ    NOT NULL DEFAULT now(),
    -- Role/EIIN consistency: authorities are tied to a school, admins are not.
    CONSTRAINT chk_account_role_eiin CHECK (
        (role = 'SCHOOL_AUTHORITY' AND eiin IS NOT NULL) OR
        (role = 'MASTER_ADMIN'     AND eiin IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_account_eiin ON account(eiin);
