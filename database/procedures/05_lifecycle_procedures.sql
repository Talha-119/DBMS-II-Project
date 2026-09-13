-- 05_lifecycle_procedures.sql
-- Stored procedures for admission lifecycle management.
--
-- NOTE: audit_log's real columns are (log_id, table_name, action, row_pk,
-- old_data, new_data, actor, at) — there is no row_id or details column.
-- Every INSERT INTO audit_log below previously used those two nonexistent
-- names and would fail with "column ... does not exist" the moment any of
-- these procedures ran; fixed to use row_pk + new_data (jsonb).

-- Disqualify applicant
CREATE OR REPLACE PROCEDURE proc_disqualify_applicant(p_application_id VARCHAR, p_reason TEXT)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE application
    SET lifecycle_status = 'DISQUALIFIED'
    WHERE application_id = p_application_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Application % not found', p_application_id USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO audit_log(table_name, action, row_pk, new_data, "at")
    VALUES ('application', 'disqualify', p_application_id, jsonb_build_object('reason', p_reason), now());
END;
$$;

-- Process expired allotments (auto-forfeit).
-- application.allocated_at was never added to the schema; the moment this
-- was called it would fail with "column allocated_at does not exist". The
-- timestamp that already exists for exactly this purpose is
-- admission_result.decided_at (set when the lottery admits the applicant),
-- so use that instead of a phantom column.
CREATE OR REPLACE PROCEDURE proc_process_expired_allotments(p_deadline_timestamp TIMESTAMPTZ)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE application a
    SET lifecycle_status = 'FORFEITED'
    FROM admission_result r
    WHERE r.application_id = a.application_id
      AND a.lifecycle_status = 'ALLOTTED'
      AND r.status = 'ADMITTED'
      AND r.decided_at < p_deadline_timestamp;

    INSERT INTO audit_log(table_name, action, row_pk, "at")
    SELECT 'application', 'forfeit', a.application_id, now()
    FROM application a
    WHERE a.lifecycle_status = 'FORFEITED';
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
        INSERT INTO audit_log(table_name, action, row_pk, "at")
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
