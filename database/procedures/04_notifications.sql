-- ============================================================================
-- procedures/04_notifications.sql
-- Manual side of the notification system: an admin-composed announcement,
-- pushed straight into an inbox (as opposed to the automatic notifications
-- fired by triggers/03_notifications.sql off application/payment/result
-- events).
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_broadcast_notification(
    p_audience TEXT,   -- 'APPLICANT' | 'SCHOOL_AUTHORITY'
    p_eiin     TEXT,   -- SCHOOL_AUTHORITY only: one school's EIIN, or NULL for every school
    p_title    TEXT,
    p_body     TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_title IS NULL OR btrim(p_title) = '' THEN
        RAISE EXCEPTION 'Announcement title is required' USING ERRCODE = '23514';
    END IF;

    IF p_audience = 'APPLICANT' THEN
        -- One row per registered student profile, i.e. every bc_no that has
        -- ever filed an application (an applicant has no account to broadcast
        -- to before that point).
        INSERT INTO notification (audience, bc_no, type, title, body)
        SELECT 'APPLICANT', s.bc_no, 'ANNOUNCEMENT', p_title, p_body FROM student s;

    ELSIF p_audience = 'SCHOOL_AUTHORITY' THEN
        IF p_eiin IS NOT NULL THEN
            IF NOT EXISTS (SELECT 1 FROM school WHERE eiin = p_eiin) THEN
                RAISE EXCEPTION 'School % not found', p_eiin USING ERRCODE = '23503';
            END IF;
            INSERT INTO notification (audience, eiin, type, title, body)
            VALUES ('SCHOOL_AUTHORITY', p_eiin, 'ANNOUNCEMENT', p_title, p_body);
        ELSE
            INSERT INTO notification (audience, eiin, type, title, body)
            SELECT 'SCHOOL_AUTHORITY', sch.eiin, 'ANNOUNCEMENT', p_title, p_body FROM school sch;
        END IF;

    ELSE
        RAISE EXCEPTION 'Unknown announcement audience % (use APPLICANT or SCHOOL_AUTHORITY)', p_audience
            USING ERRCODE = '23514';
    END IF;
END;
$$;

-- ----------------------------------------------------------------------------
-- sp_approve_deletion — decide a pending deletion request.
--
-- routes/admin.js already calls this ("CALL sp_approve_deletion($1::bigint, $2,
-- $3::boolean)") and Admin.jsx already has working Approve/Reject buttons wired
-- to it, but the procedure itself was never written (01_application.sql only
-- notes that approval "belongs to the separate school-authority/admin system"
-- and stops there) — so every decision on a deletion request currently fails
-- with "procedure sp_approve_deletion does not exist". Added here because the
-- new DELETION_DECIDED applicant notification (triggers/03_notifications.sql)
-- has nothing to fire on otherwise; sp_request_deletion right above is the
-- other half of the same workflow.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_approve_deletion(
    p_request_id BIGINT,
    p_decided_by TEXT,
    p_approve    BOOLEAN
)
LANGUAGE plpgsql AS $$
DECLARE
    v_status deletion_status_t;
    v_app_id TEXT;
BEGIN
    SELECT status, application_id INTO v_status, v_app_id
    FROM deletion_request WHERE request_id = p_request_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Deletion request % not found', p_request_id USING ERRCODE = 'P0002';
    END IF;
    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Deletion request % has already been decided (%)', p_request_id, v_status
            USING ERRCODE = '23514';
    END IF;

    -- The UPDATE fires trg_notify_deletion_decided (AFTER UPDATE), which reads
    -- the applicant's bc_no via v_app_id — so it must happen BEFORE the
    -- application row (and the bc_no lookup it depends on) can disappear below.
    UPDATE deletion_request
       SET status = (CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END)::deletion_status_t,
           decided_at = now(), decided_by = p_decided_by
     WHERE request_id = p_request_id;

    IF p_approve THEN
        DELETE FROM application WHERE application_id = v_app_id;
    END IF;
END;
$$;
