-- ============================================================================
-- migrations/013_notifications.sql
-- In-app notifications for all three sides of the system.
--
-- Recipients are addressed the same way everything else here already
-- identifies them, so no new identity concept is introduced:
--   * APPLICANT        -> bc_no   (the birth certificate is the applicant's
--                          identity everywhere else — retrieve, OTP, the
--                          student profile — so their inbox is keyed the same
--                          way and one notification is visible across every
--                          application that bc_no has filed).
--   * SCHOOL_AUTHORITY -> eiin    (one authority account per school; see
--                          009_accounts.sql).
--   * MASTER_ADMIN     -> neither (a single shared operations inbox for the
--                          role — alerts like "a deletion request is pending"
--                          concern the office, not one login).
--
-- Exactly one of bc_no / eiin is set, matching the audience (enforced below,
-- the same pattern 009_accounts.sql uses for chk_account_role_eiin).
-- application_id is an optional deep link back to the application that caused
-- the notice; it is NOT part of the audience check, and it goes NULL rather
-- than cascading if that application is later deleted (e.g. an approved
-- deletion request), so the notification announcing the deletion survives it.
-- ============================================================================

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'notification_audience_t') THEN
        CREATE TYPE notification_audience_t AS ENUM ('APPLICANT', 'SCHOOL_AUTHORITY', 'MASTER_ADMIN');
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS notification (
    notification_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    audience        notification_audience_t NOT NULL,
    bc_no           VARCHAR(20) REFERENCES birth_certificate(bc_no) ON DELETE CASCADE,
    eiin            VARCHAR(10) REFERENCES school(eiin) ON DELETE CASCADE,
    application_id  VARCHAR(20) REFERENCES application(application_id) ON DELETE SET NULL,
    type            VARCHAR(40)  NOT NULL,
    title           VARCHAR(120) NOT NULL,
    body            VARCHAR(400),
    is_read         BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_notification_audience_target CHECK (
        (audience = 'APPLICANT'        AND bc_no IS NOT NULL AND eiin IS NULL) OR
        (audience = 'SCHOOL_AUTHORITY' AND eiin  IS NOT NULL AND bc_no IS NULL) OR
        (audience = 'MASTER_ADMIN'     AND bc_no IS NULL     AND eiin IS NULL)
    )
);

-- Inbox reads are always "my recipient key, newest first"; unread badge counts
-- filter on is_read too, so index that shape rather than the bare FK columns.
CREATE INDEX IF NOT EXISTS idx_notification_bc     ON notification (bc_no, created_at DESC) WHERE bc_no IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notification_eiin   ON notification (eiin, created_at DESC) WHERE eiin IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notification_admin  ON notification (created_at DESC) WHERE audience = 'MASTER_ADMIN';
CREATE INDEX IF NOT EXISTS idx_notification_unread ON notification (audience, is_read);
