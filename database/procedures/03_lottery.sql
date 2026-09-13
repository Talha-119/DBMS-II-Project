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
--
-- WAITING LIST: an application's lottery position is drawn once and kept for
-- every later round, so freed seats go to the top of a stable waiting list.
--
-- ENROLLMENT: a lottery admission holds its seat until the school confirms it
-- (ENROLLED, see procedures/05_enrollment.sql). Once the master admin's
-- certificate deadline (ENROLL_DEADLINE) has passed, a run first forfeits every
-- admission still unconfirmed and returns those seats to the pool.
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_run_lottery(p_round INT DEFAULT 1)
LANGUAGE plpgsql AS $$
DECLARE
    v_app      RECORD;
    v_choice   RECORD;
    v_sq       RECORD;
    v_rows     INT;
    v_def_q    TEXT;
    v_deadline TIMESTAMPTZ;
BEGIN
    -- Only one lottery may run at a time (prevents double allocation).
    PERFORM pg_advisory_xact_lock(42);

    -- 1. Release seats that are no longer held. A DISQUALIFIED applicant loses
    -- their seat on any run. Once the certificate deadline has passed, every
    -- admission still ALLOTTED (not confirmed by its school) is FORFEITED too.
    -- The seat goes back to the quota it came from, so this run can hand it to
    -- a waiting applicant, and the student is out of this admission: all their
    -- applications close as NOT_ADMITTED.
    SELECT value::TIMESTAMPTZ INTO v_deadline FROM app_setting WHERE key = 'ENROLL_DEADLINE';

    DROP TABLE IF EXISTS tmp_release;
    CREATE TEMP TABLE tmp_release ON COMMIT DROP AS
    SELECT r.application_id, r.admitted_seat_id, r.allocated_quota, a.bc_no,
           (CASE WHEN a.lifecycle_status = 'DISQUALIFIED' THEN 'DISQUALIFIED' ELSE 'FORFEITED' END)::admission_lifecycle_status_t AS outcome
      FROM admission_result r
      JOIN application a ON a.application_id = r.application_id
     WHERE r.status = 'ADMITTED'
       AND r.admitted_seat_id IS NOT NULL
       AND (a.lifecycle_status = 'DISQUALIFIED'
            OR (v_deadline IS NOT NULL AND v_deadline <= now() AND r.lifecycle_status = 'ALLOTTED'));

    UPDATE seat_quota sq
       SET capacity = sq.capacity + f.n
      FROM (SELECT admitted_seat_id, allocated_quota, count(*) AS n
              FROM tmp_release GROUP BY 1, 2) f
     WHERE sq.seat_id = f.admitted_seat_id AND sq.quota_code = f.allocated_quota;

    UPDATE admission_result r
       SET status = 'NOT_ADMITTED', lifecycle_status = f.outcome, decided_at = now()
      FROM tmp_release f
     WHERE r.application_id = f.application_id;

    UPDATE application a
       SET status = 'NOT_ADMITTED',
           lifecycle_status = COALESCE((SELECT f.outcome FROM tmp_release f WHERE f.application_id = a.application_id),
                                       a.lifecycle_status)
     WHERE a.bc_no IN (SELECT bc_no FROM tmp_release)
       AND a.status <> 'DELETED';

    -- The deadline is used up: the students this round admits need a new one.
    IF v_deadline IS NOT NULL AND v_deadline <= now() THEN
        DELETE FROM app_setting WHERE key = 'ENROLL_DEADLINE';
    END IF;

    -- 2. Clear the non-final WAITING results and put everyone not yet seated back
    -- into the draw. Kept as they are: admissions (ALLOTTED or ENROLLED) and
    -- released seats. Never re-entered: DELETED and CANCELLED applications,
    -- NOT_ADMITTED (a student who forfeited or was disqualified) and
    -- DISQUALIFIED applicants.
    DELETE FROM admission_result WHERE status = 'WAITING';

    UPDATE application
    SET status = 'SUBMITTED',
        lifecycle_status = 'WAITLISTED'
    WHERE status NOT IN ('ADMITTED', 'DELETED', 'CANCELLED', 'NOT_ADMITTED')
      AND lifecycle_status NOT IN ('ENROLLED', 'DISQUALIFIED');

    -- 3. One random position per application, drawn the first time it enters a
    -- lottery and kept for every later round. Every one of an applicant's
    -- choices is judged on that same number, and a freed seat goes to whoever
    -- is highest on a stable waiting list rather than to a fresh roll.
    -- Applications new to this round rank after everyone already ranked.
    UPDATE application a
       SET lottery_rank = d.base + d.draw
      FROM (SELECT application_id,
                   row_number() OVER (ORDER BY random()) AS draw,
                   (SELECT COALESCE(max(lottery_rank), 0) FROM application) AS base
              FROM application
             WHERE status = 'SUBMITTED' AND lottery_rank IS NULL) d
     WHERE a.application_id = d.application_id;

    -- 4. Pass 1: Walk applicants in waiting-list order and try claimed quotas for their ranked choices.
    FOR v_app IN
        SELECT a.application_id, a.bc_no
        FROM application a
        WHERE a.status = 'SUBMITTED'
        ORDER BY a.lottery_rank
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

    -- 5. Pass 2: Transfer remaining unfilled specialized quota capacities to default quota pool
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

    -- Process unseated applicants from the waiting list for remaining seat capacity under default quota
    FOR v_app IN
        SELECT a.application_id, a.bc_no
        FROM application a
        WHERE a.status = 'SUBMITTED'
        ORDER BY a.lottery_rank
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

    -- 6. Anyone still SUBMITTED did not get any seat this round -> WAITING / WAITLISTED.
    INSERT INTO admission_result (application_id, admitted_seat_id, allocated_quota, status, round, lifecycle_status)
    SELECT a.application_id, NULL, NULL, 'WAITING', p_round, 'WAITLISTED'
    FROM application a
    WHERE a.status = 'SUBMITTED'
      AND NOT EXISTS (SELECT 1 FROM admission_result r WHERE r.application_id = a.application_id);

    UPDATE application
    SET status = 'WAITING', lifecycle_status = 'WAITLISTED'
    WHERE status = 'SUBMITTED'
      AND application_id IN (SELECT application_id FROM admission_result WHERE status = 'WAITING' AND round = p_round);

    -- 7. Save settings & automatically publish results after every lottery run.
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
