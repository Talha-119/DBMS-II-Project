-- 013_procedures.sql
-- Stored procedures for admission lifecycle management

-- Disqualify applicant
CREATE OR REPLACE PROCEDURE proc_disqualify_applicant(p_application_id VARCHAR, p_reason TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE application
    SET lifecycle_status = 'DISQUALIFIED'
    WHERE application_id = p_application_id;
    INSERT INTO audit_log(table_name, action, row_id, details, "at")
    VALUES ('application', 'disqualify', p_application_id, p_reason, now());
END;
$$;

-- Process expired allotments (auto-forfeit)
CREATE OR REPLACE PROCEDURE proc_process_expired_allotments(p_deadline_timestamp TIMESTAMPTZ)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE application
    SET lifecycle_status = 'FORFEITED'
    WHERE lifecycle_status = 'ALLOTTED' AND allocated_at IS NOT NULL AND allocated_at < p_deadline_timestamp;
    INSERT INTO audit_log(table_name, action, details, "at")
    SELECT 'application', 'forfeit', application_id, now()
    FROM application
    WHERE lifecycle_status = 'FORFEITED';
END;
$$;

-- Promote waitlist to a vacated seat
CREATE OR REPLACE PROCEDURE proc_promote_waitlist(p_seat_id VARCHAR)
LANGUAGE plpgsql AS $$
DECLARE
    v_app_id VARCHAR;
BEGIN
    SELECT application_id INTO v_app_id
    FROM application a
    JOIN application_choice ac ON ac.application_id = a.application_id
    WHERE ac.seat_id = p_seat_id AND a.lifecycle_status = 'WAITLISTED'
    ORDER BY a.submitted_at ASC
    LIMIT 1;

    IF v_app_id IS NOT NULL THEN
        UPDATE application SET lifecycle_status = 'ALLOTTED' WHERE application_id = v_app_id;
        INSERT INTO audit_log(table_name, action, row_id, "at")
        VALUES ('application', 'waitlist_promote', v_app_id, now());
    END IF;
END;
$$;

-- Choice upgradation (simplified)
CREATE OR REPLACE PROCEDURE proc_run_choice_upgradation()
LANGUAGE plpgsql AS $$
BEGIN
    -- Upgrade waitlisted applications that have higher-choice seats available
    UPDATE application a
    SET lifecycle_status = 'UPGRADED'
    FROM application_choice ac
    WHERE a.application_id = ac.application_id
      AND a.lifecycle_status = 'WAITLISTED'
      AND ac.preference > 1;
END;
$$;

-- Convert unfilled quotas to general merit pool
CREATE OR REPLACE PROCEDURE proc_convert_unfilled_quotas()
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE quota_type qt
    SET is_default = TRUE
    WHERE NOT EXISTS (SELECT 1 FROM seat_quota sq WHERE sq.quota_code = qt.code);
END;
$$;
