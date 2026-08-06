-- ============================================================================
-- 005_results_ops.sql
-- Lottery results + operational tables (deletion workflow, OTP, audit, settings).
-- ============================================================================

-- One result row per application after the lottery runs.
CREATE TABLE IF NOT EXISTS admission_result (
    application_id   VARCHAR(20) PRIMARY KEY REFERENCES application(application_id) ON DELETE CASCADE,
    admitted_seat_id VARCHAR(20) REFERENCES seat(seat_id),
    allocated_quota  VARCHAR(20) REFERENCES quota_type(code),
    status           result_status_t NOT NULL,
    round            INT         NOT NULL DEFAULT 1,
    decided_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Applicant asks to delete an application; a master admin approves/rejects.
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

-- Generic audit trail, populated by triggers using to_jsonb (see Phase 2).
CREATE TABLE IF NOT EXISTS audit_log (
    log_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name VARCHAR(40) NOT NULL,
    action     VARCHAR(10) NOT NULL,           -- INSERT | UPDATE | DELETE
    row_pk     VARCHAR(60),
    old_data   JSONB,
    new_data   JSONB,
    actor      VARCHAR(60) DEFAULT current_user,
    at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Simple key/value settings (e.g. admission round open/closed, RESULT_READY).
CREATE TABLE IF NOT EXISTS app_setting (
    key        VARCHAR(40) PRIMARY KEY,
    value      VARCHAR(200) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_otp_mobile_purpose ON otp(mobile, purpose);
CREATE INDEX IF NOT EXISTS idx_deletion_status    ON deletion_request(status);
CREATE INDEX IF NOT EXISTS idx_audit_table        ON audit_log(table_name, at);
