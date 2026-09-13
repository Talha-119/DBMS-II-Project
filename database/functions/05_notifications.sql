-- ============================================================================
-- functions/05_notifications.sql
-- Single insert point for the notification system. Every notify trigger in
-- triggers/03_notifications.sql calls this instead of writing its own INSERT,
-- the same way trg_fn_audit() is the one place that knows the audit_log shape.
-- If the notification table ever grows a column, this is the only place that
-- needs to change.
-- ============================================================================

CREATE OR REPLACE FUNCTION fn_create_notification(
    p_audience       TEXT,   -- 'APPLICANT' | 'SCHOOL_AUTHORITY' | 'MASTER_ADMIN'
    p_bc_no          TEXT,   -- set for APPLICANT, else NULL
    p_eiin           TEXT,   -- set for SCHOOL_AUTHORITY, else NULL
    p_application_id TEXT,   -- optional deep link; may be NULL
    p_type           TEXT,   -- short machine-readable event code, e.g. 'RESULT_PUBLISHED'
    p_title          TEXT,
    p_body           TEXT
)
RETURNS BIGINT
LANGUAGE plpgsql AS $$
DECLARE
    v_id BIGINT;
BEGIN
    -- p_audience arrives as a plain TEXT parameter (not an untyped literal), so
    -- unlike a bare 'APPLICANT' in a VALUES list it needs an explicit cast to
    -- the enum column.
    INSERT INTO notification (audience, bc_no, eiin, application_id, type, title, body)
    VALUES (p_audience::notification_audience_t, p_bc_no, p_eiin, p_application_id, p_type, p_title, p_body)
    RETURNING notification_id INTO v_id;
    RETURN v_id;
END;
$$;
