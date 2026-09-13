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
-- sp_approve_deletion lives in procedures/01_application.sql, NOT here.
--
-- A second copy used to sit at this spot. It was written in good faith: on the
-- branch it was authored from, 01_application.sql genuinely had no such
-- procedure (a merge had dropped it), so admin.js was calling something that
-- did not exist. Both copies then loaded, and because this file sorts after
-- 01_application.sql, this one silently overwrote the other.
--
-- The two disagreed on what approval means, and it mattered:
--   * this copy ran DELETE FROM application, which cascaded the deletion_request
--     row away with it — the approval destroyed its own audit record — and
--     never returned the seat the lottery had already allocated, so an admitted
--     application that was later deleted permanently burned a seat;
--   * it also left application_status_t's DELETED value unused, which every
--     rate-limit rule, the lottery and integrity_checks.sql all test against.
--
-- The canonical version soft-deletes (status = 'DELETED'), restores the seat
-- capacity and drops the result row, keeping the application and its request
-- readable afterwards.
-- ----------------------------------------------------------------------------
