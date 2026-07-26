-- ============================================================================
-- 005_results_ops.sql
-- Operational tables the applicant flow reads or writes:
--   * admission_result  -- READ ONLY here: the applicant checks their result.
--                          Rows are produced by the separate admin/authority
--                          system's seat-allocation lottery (not part of this
--                          applicant project), so this table stays empty until
--                          that system publishes results into the shared DB.
--   * deletion_request  -- the applicant asks to delete an application; the
--                          admin system approves/rejects it.
--   * otp               -- hashed one-time codes for apply/retrieve/delete/recover.
--   * app_setting       -- key/value flags the applicant reads (e.g. RESULT_READY).
-- ============================================================================

-- One result row per application (written by the admin lottery; read by applicants).
CREATE TABLE IF NOT EXISTS admission_result (
    application_id   VARCHAR(20) PRIMARY KEY REFERENCES application(application_id) ON DELETE CASCADE,
    admitted_seat_id VARCHAR(20) REFERENCES seat(seat_id),
    allocated_quota  VARCHAR(20) REFERENCES quota_type(code),
    status           result_status_t NOT NULL,
    round            INT         NOT NULL DEFAULT 1,
    decided_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Applicant asks to delete an application; the admin system approves/rejects.
CREATE TABLE IF NOT EXISTS deletion_request (
    request_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    application_id VARCHAR(20) NOT NULL REFERENCES application(application_id) ON DELETE CASCADE,
    reason         VARCHAR(300),
    status         deletion_status_t NOT NULL DEFAULT 'PENDING',
    requested_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    decided_at     TIMESTAMPTZ,
    decided_by     VARCHAR(40)
);

-- OTP codes are stored HASHED (never in plaintext) with an expiry.
CREATE TABLE IF NOT EXISTS otp (
    otp_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purpose     VARCHAR(30) NOT NULL,          -- APPLY | RETRIEVE | DELETE | RECOVER
    mobile      VARCHAR(11) NOT NULL,
    code_hash   TEXT        NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed    BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Simple key/value settings (e.g. admission round open/closed, RESULT_READY).
-- The applicant flow READS these; the admin system toggles them.
CREATE TABLE IF NOT EXISTS app_setting (
    key        VARCHAR(40) PRIMARY KEY,
    value      VARCHAR(200) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_otp_mobile_purpose ON otp(mobile, purpose);
CREATE INDEX IF NOT EXISTS idx_deletion_status    ON deletion_request(status);
