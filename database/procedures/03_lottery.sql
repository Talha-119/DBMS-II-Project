-- ============================================================================
-- procedures/03_lottery.sql
-- Applicant-proposing lottery: each applicant gets ONE random lottery number
-- for the whole run (not one per seat), and is then offered their OWN ranked
-- choices in the order they ranked them (preference 1 first). This is the
-- standard "single random number + ranked-choice" design real school-choice
-- lotteries use (e.g. NYC/SF style), and it guarantees an applicant never
-- loses a more-preferred, still-open seat to a less-preferred one just
-- because of which seat happened to get processed first.
--
-- Within a chosen seat, quotas the applicant claimed on that choice are tried
-- in quota-priority order (e.g. Freedom Fighter before General), same as
-- before. A student who wins anywhere is removed from contention everywhere
-- else (checked by birth-certificate number, since one student may file
-- multiple applications).
--
-- MULTI-ROUND: each run keeps prior ADMITTED results (and their consumed
-- seats), clears the non-final WAITING results, and allocates the remaining
-- seat capacity to applicants who are still unseated. So calling it again
-- (round 2, 3…) migrates waiting applicants into seats freed up / left over.
-- Safe to re-run. Concurrency-safe via a transaction advisory lock.
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_run_lottery(p_round INT DEFAULT 1)
LANGUAGE plpgsql AS $$
DECLARE
    v_app    RECORD;
    v_choice RECORD;
    v_res    RECORD;
    v_sq     RECORD;
    v_rows   INT;
    v_def_q  TEXT;
BEGIN
    -- Only one lottery may run at a time (prevents double allocation).
    PERFORM pg_advisory_xact_lock(42);

    -- 1. Restore seat quota capacity for prior ADMITTED results that did NOT get ENROLLED.
    -- If a student was selected in a previous lottery but forfeited, was disqualified, or
    -- didn't get enrolled, their seat becomes vacant again and capacity is returned.
    FOR v_res IN
        SELECT r.admitted_seat_id, r.allocated_quota
        FROM admission_result r
        JOIN application a ON a.application_id = r.application_id
        WHERE r.status = 'ADMITTED'
          AND COALESCE(r.lifecycle_status, a.lifecycle_status) <> 'ENROLLED'
          AND r.admitted_seat_id IS NOT NULL
          AND r.allocated_quota IS NOT NULL
    LOOP
        UPDATE seat_quota
        SET capacity = capacity + 1
        WHERE seat_id = v_res.admitted_seat_id AND quota_code = v_res.allocated_quota;
    END LOOP;

    -- 2. Clear non-finalized admission results (keep only ENROLLED admissions).
    DELETE FROM admission_result
    WHERE status <> 'ADMITTED'
       OR (status = 'ADMITTED' AND COALESCE(lifecycle_status, 'ALLOTTED') <> 'ENROLLED');

    -- 3. Reset application status to SUBMITTED / WAITLISTED for students eligible for this draw.
    -- Exclude ENROLLED, DELETED, DISQUALIFIED, and CANCELLED students.
    UPDATE application
    SET status = 'SUBMITTED',
        lifecycle_status = 'WAITLISTED'
    WHERE status NOT IN ('DELETED', 'CANCELLED')
      AND lifecycle_status NOT IN ('ENROLLED', 'DISQUALIFIED');

    -- 4. One random draw per applicant for this whole run.
    DROP TABLE IF EXISTS tmp_lottery_draw;
    CREATE TEMP TABLE tmp_lottery_draw ON COMMIT DROP AS
    SELECT application_id, row_number() OVER (ORDER BY random()) AS draw
    FROM application
    WHERE status = 'SUBMITTED'
      AND lifecycle_status NOT IN ('ENROLLED', 'DISQUALIFIED');

    -- 5. Pass 1: Walk applicants in lottery order and try claimed quotas for their ranked choices.
    FOR v_app IN
        SELECT a.application_id, a.bc_no
        FROM application a
        JOIN tmp_lottery_draw t ON t.application_id = a.application_id
        WHERE a.status = 'SUBMITTED'
        ORDER BY t.draw
    LOOP
        -- Skip if this student already won a seat via a different application.
        IF EXISTS (
            SELECT 1 FROM admission_result r
            JOIN application a2 ON a2.application_id = r.application_id
            WHERE a2.bc_no = v_app.bc_no AND r.status = 'ADMITTED'
        ) THEN
            CONTINUE;
        END IF;

        FOR v_choice IN
            SELECT ac.seat_id, cq.quota_code
            FROM application_choice ac
            JOIN choice_quota cq ON cq.choice_id = ac.choice_id
            JOIN quota_type qt   ON qt.code = cq.quota_code
            WHERE ac.application_id = v_app.application_id
            ORDER BY ac.preference, qt.priority
        LOOP
            UPDATE seat_quota SET capacity = capacity - 1
            WHERE seat_id = v_choice.seat_id AND quota_code = v_choice.quota_code AND capacity > 0;
            GET DIAGNOSTICS v_rows = ROW_COUNT;

            IF v_rows > 0 THEN
                INSERT INTO admission_result (application_id, admitted_seat_id, allocated_quota, status, round, lifecycle_status)
                VALUES (v_app.application_id, v_choice.seat_id, v_choice.quota_code, 'ADMITTED', p_round, 'ALLOTTED');

                UPDATE application
                SET status = 'ADMITTED', lifecycle_status = 'ALLOTTED'
                WHERE application_id = v_app.application_id;
                EXIT;  -- seated; stop trying this applicant's remaining choices
            END IF;
        END LOOP;
    END LOOP;

    -- 6. Pass 2: Transfer remaining unfilled specialized quota capacities to default quota pool
    -- so waitlisted applicants can be pulled into seats where quota was not filled.
    SELECT code INTO v_def_q FROM quota_type WHERE is_default ORDER BY priority LIMIT 1;
    IF v_def_q IS NULL THEN
        SELECT code INTO v_def_q FROM quota_type ORDER BY priority DESC LIMIT 1;
    END IF;

    FOR v_sq IN
        SELECT sq.seat_id, sq.quota_code, sq.capacity
        FROM seat_quota sq
        JOIN quota_type qt ON qt.code = sq.quota_code
        WHERE qt.is_default = FALSE AND sq.capacity > 0
    LOOP
        UPDATE seat_quota
        SET capacity = capacity + v_sq.capacity
        WHERE seat_id = v_sq.seat_id AND quota_code = v_def_q;

        UPDATE seat_quota
        SET capacity = 0
        WHERE seat_id = v_sq.seat_id AND quota_code = v_sq.quota_code;
    END LOOP;

    -- Process unseated applicants from waitlist for remaining seat capacity under default quota
    FOR v_app IN
        SELECT a.application_id, a.bc_no
        FROM application a
        JOIN tmp_lottery_draw t ON t.application_id = a.application_id
        WHERE a.status = 'SUBMITTED'
        ORDER BY t.draw
    LOOP
        IF EXISTS (
            SELECT 1 FROM admission_result r
            JOIN application a2 ON a2.application_id = r.application_id
            WHERE a2.bc_no = v_app.bc_no AND r.status = 'ADMITTED'
        ) THEN
            CONTINUE;
        END IF;

        FOR v_choice IN
            SELECT ac.seat_id
            FROM application_choice ac
            WHERE ac.application_id = v_app.application_id
            ORDER BY ac.preference
        LOOP
            UPDATE seat_quota SET capacity = capacity - 1
            WHERE seat_id = v_choice.seat_id AND quota_code = v_def_q AND capacity > 0;
            GET DIAGNOSTICS v_rows = ROW_COUNT;

            IF v_rows > 0 THEN
                INSERT INTO admission_result (application_id, admitted_seat_id, allocated_quota, status, round, lifecycle_status)
                VALUES (v_app.application_id, v_choice.seat_id, v_def_q, 'ADMITTED', p_round, 'ALLOTTED');

                UPDATE application
                SET status = 'ADMITTED', lifecycle_status = 'ALLOTTED'
                WHERE application_id = v_app.application_id;
                EXIT;
            END IF;
        END LOOP;
    END LOOP;

    -- 7. Anyone still SUBMITTED did not get any seat this round -> WAITING / WAITLISTED.
    INSERT INTO admission_result (application_id, admitted_seat_id, allocated_quota, status, round, lifecycle_status)
    SELECT a.application_id, NULL, NULL, 'WAITING', p_round, 'WAITLISTED'
    FROM application a
    WHERE a.status = 'SUBMITTED'
      AND NOT EXISTS (SELECT 1 FROM admission_result r WHERE r.application_id = a.application_id);

    UPDATE application
    SET status = 'WAITING', lifecycle_status = 'WAITLISTED'
    WHERE status = 'SUBMITTED'
      AND application_id IN (SELECT application_id FROM admission_result WHERE status = 'WAITING' AND round = p_round);

    -- 8. Save settings & automatically publish results after every lottery run.
    INSERT INTO app_setting (key, value) VALUES ('RESULT_READY', 'TRUE')
    ON CONFLICT (key) DO UPDATE SET value = 'TRUE', updated_at = now();
    INSERT INTO app_setting (key, value) VALUES ('ROUND_OPEN', 'FALSE')
    ON CONFLICT (key) DO UPDATE SET value = 'FALSE', updated_at = now();
    INSERT INTO app_setting (key, value) VALUES ('CURRENT_ROUND', p_round::TEXT)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
END;
$$;


-- ============================================================================
-- Publication control. Separate from the draw on purpose: allocating seats and
-- telling the country about it are two different decisions, and only the second
-- one is irreversible in practice (people act on a published result).
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_publish_results()
LANGUAGE plpgsql AS $$
BEGIN
    -- Nothing to publish before a lottery has been run: publishing an empty
    -- result set would open the public lookup only for it to answer
    -- "no result found" to every applicant.
    IF NOT EXISTS (SELECT 1 FROM admission_result) THEN
        RAISE EXCEPTION 'No lottery results to publish — run the lottery first';
    END IF;

    INSERT INTO app_setting (key, value) VALUES ('RESULT_READY', 'TRUE')
    ON CONFLICT (key) DO UPDATE SET value = 'TRUE', updated_at = now();
END;
$$;


CREATE OR REPLACE PROCEDURE sp_unpublish_results()
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO app_setting (key, value) VALUES ('RESULT_READY', 'FALSE')
    ON CONFLICT (key) DO UPDATE SET value = 'FALSE', updated_at = now();
END;
$$;


-- Open / close the application window on its own, without touching results.
CREATE OR REPLACE PROCEDURE sp_set_round_open(p_open BOOLEAN)
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO app_setting (key, value)
    VALUES ('ROUND_OPEN', CASE WHEN p_open THEN 'TRUE' ELSE 'FALSE' END)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
END;
$$;

