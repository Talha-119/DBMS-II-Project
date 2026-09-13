-- 013_procedures.sql
-- Stored procedures for admission lifecycle management.
-- audit_log real columns: table_name, action, row_pk, old_data (JSONB), new_data (JSONB), actor, at.

-- Disqualify applicant and write a detailed audit record
CREATE OR REPLACE PROCEDURE proc_disqualify_applicant(p_application_id VARCHAR, p_reason TEXT)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_status admission_lifecycle_status_t;
BEGIN
    SELECT lifecycle_status INTO v_old_status
    FROM application
    WHERE application_id = p_application_id;

    UPDATE application
    SET lifecycle_status = 'DISQUALIFIED'
    WHERE application_id = p_application_id;

    INSERT INTO audit_log(table_name, action, row_pk, old_data, new_data)
    VALUES (
        'application',
        'DISQUALIFY',
        p_application_id,
        jsonb_build_object('lifecycle_status', v_old_status::text),
        jsonb_build_object('lifecycle_status', 'DISQUALIFIED', 'reason', p_reason)
    );
END;
$$;

-- Auto-forfeit: mark all ALLOTTED applications submitted before the deadline as FORFEITED
CREATE OR REPLACE PROCEDURE proc_process_expired_allotments(p_deadline_timestamp TIMESTAMPTZ)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE application
    SET lifecycle_status = 'FORFEITED'
    WHERE lifecycle_status = 'ALLOTTED'
      AND submitted_at < p_deadline_timestamp;

    INSERT INTO audit_log(table_name, action, row_pk, new_data)
    SELECT
        'application',
        'FORFEIT',
        application_id,
        jsonb_build_object('lifecycle_status', 'FORFEITED', 'deadline', p_deadline_timestamp)
    FROM application
    WHERE lifecycle_status = 'FORFEITED';
END;
$$;

-- Promote the highest-priority WAITLISTED applicant for a vacated seat
CREATE OR REPLACE PROCEDURE proc_promote_waitlist(p_seat_id VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
    v_app_id VARCHAR;
BEGIN
    SELECT a.application_id INTO v_app_id
    FROM application a
    JOIN application_choice ac ON ac.application_id = a.application_id
    WHERE ac.seat_id = p_seat_id
      AND a.lifecycle_status = 'WAITLISTED'
    ORDER BY a.submitted_at ASC
    LIMIT 1;

    IF v_app_id IS NOT NULL THEN
        UPDATE application
        SET lifecycle_status = 'ALLOTTED'
        WHERE application_id = v_app_id;

        INSERT INTO audit_log(table_name, action, row_pk, new_data)
        VALUES (
            'application',
            'WAITLIST_PROMOTE',
            v_app_id,
            jsonb_build_object('lifecycle_status', 'ALLOTTED', 'seat_id', p_seat_id)
        );
    END IF;
END;
$$;

-- Choice upgradation: mark WAITLISTED applications that still have a first-choice slot as UPGRADED
CREATE OR REPLACE PROCEDURE proc_run_choice_upgradation()
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE application a
    SET lifecycle_status = 'UPGRADED'
    FROM application_choice ac
    WHERE a.application_id = ac.application_id
      AND a.lifecycle_status = 'WAITLISTED'
      AND ac.preference = 1;

    INSERT INTO audit_log(table_name, action, new_data)
    SELECT
        'application',
        'CHOICE_UPGRADE',
        jsonb_build_object('ran_at', now())
    WHERE EXISTS (SELECT 1 FROM application WHERE lifecycle_status = 'UPGRADED');
END;
$$;

-- Convert unfilled specialized quota seats into the general merit pool
CREATE OR REPLACE PROCEDURE proc_convert_unfilled_quotas()
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE quota_type qt
    SET is_default = TRUE
    WHERE qt.is_default = FALSE
      AND NOT EXISTS (
          SELECT 1 FROM choice_quota cq WHERE cq.quota_code = qt.code
      );

    INSERT INTO audit_log(table_name, action, new_data)
    VALUES (
        'quota_type',
        'QUOTA_CONVERT',
        jsonb_build_object('ran_at', now())
    );
END;
$$;

