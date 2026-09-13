-- ============================================================================
-- procedures/05_enrollment.sql
-- Certificate deadline + school-side confirmation of a lottery admission.
-- Forfeiting unconfirmed admissions happens inside sp_run_lottery, because it
-- must happen in the same transaction that hands the freed seats onward.
-- ============================================================================

-- Master admin: one certificate-submission deadline for every school. Stored
-- as ISO-8601 UTC so both SQL (value::TIMESTAMPTZ) and the browser can parse it.
CREATE OR REPLACE PROCEDURE sp_set_enrollment_deadline(p_deadline TIMESTAMPTZ)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_deadline IS NULL THEN
        RAISE EXCEPTION 'A deadline date and time is required' USING ERRCODE = '23502';
    END IF;

    INSERT INTO app_setting (key, value)
    VALUES ('ENROLL_DEADLINE', to_char(p_deadline AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
END;
$$;

-- School authority: the student handed in their certificates, so the seat the
-- lottery allotted becomes a confirmed admission. The lottery already took the
-- seat out of the school's capacity, so nothing is decremented here. Allowed
-- after the deadline too, right up until a later lottery round forfeits it.
CREATE OR REPLACE PROCEDURE sp_confirm_enrollment(p_eiin TEXT, p_application_id TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    v_eiin      TEXT;
    v_lifecycle admission_lifecycle_status_t;
BEGIN
    SELECT se.eiin, r.lifecycle_status INTO v_eiin, v_lifecycle
      FROM admission_result r
      JOIN seat se ON se.seat_id = r.admitted_seat_id
     WHERE r.application_id = p_application_id
       FOR UPDATE OF r;

    IF v_eiin IS DISTINCT FROM p_eiin THEN
        RAISE EXCEPTION 'Application % was not allotted a seat at this school', p_application_id
            USING ERRCODE = '23503';
    END IF;
    IF v_lifecycle = 'ENROLLED' THEN
        RAISE EXCEPTION 'Application % is already confirmed', p_application_id
            USING ERRCODE = '23514';
    END IF;
    IF v_lifecycle = 'FORFEITED' THEN
        RAISE EXCEPTION 'Application % missed the certificate deadline and its seat was released in a later lottery round', p_application_id
            USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM app_setting WHERE key = 'RESULT_READY' AND value = 'TRUE') THEN
        RAISE EXCEPTION 'Results are not published yet, so no admission can be confirmed'
            USING ERRCODE = '23514';
    END IF;

    UPDATE admission_result SET lifecycle_status = 'ENROLLED', enrolled_at = now()
     WHERE application_id = p_application_id;
    UPDATE application SET lifecycle_status = 'ENROLLED'
     WHERE application_id = p_application_id;
END;
$$;
