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
    v_rows   INT;
BEGIN
    -- Only one lottery may run at a time (prevents double allocation).
    PERFORM pg_advisory_xact_lock(42);

    -- Keep finalized admissions; reconsider everyone else this round.
    DELETE FROM admission_result WHERE status <> 'ADMITTED';
    UPDATE application SET status = 'SUBMITTED' WHERE status <> 'ADMITTED';

    -- One random draw per applicant for this whole run, so every one of their
    -- choices is judged on the same number (a student can't get a "fresh"
    -- roll by being reconsidered choice-by-choice).
    DROP TABLE IF EXISTS tmp_lottery_draw;
    CREATE TEMP TABLE tmp_lottery_draw ON COMMIT DROP AS
    SELECT application_id, row_number() OVER (ORDER BY random()) AS draw
    FROM application
    WHERE status = 'SUBMITTED';

    -- Walk applicants strictly in lottery order (best draw first). For each,
    -- offer THEIR choices in THEIR ranked order (preference 1 first, then 2,
    -- 3…), and seat them at the first (seat, quota) that still has room.
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
                INSERT INTO admission_result (application_id, admitted_seat_id, allocated_quota, status, round)
                VALUES (v_app.application_id, v_choice.seat_id, v_choice.quota_code, 'ADMITTED', p_round);

                UPDATE application SET status = 'ADMITTED' WHERE application_id = v_app.application_id;
                EXIT;  -- seated; stop trying this applicant's remaining choices
            END IF;
        END LOOP;
    END LOOP;

    -- Anyone still SUBMITTED did not get any of their choices this round -> WAITING.
    INSERT INTO admission_result (application_id, admitted_seat_id, allocated_quota, status, round)
    SELECT a.application_id, NULL, NULL, 'WAITING', p_round
    FROM application a
    WHERE a.status = 'SUBMITTED'
      AND NOT EXISTS (SELECT 1 FROM admission_result r WHERE r.application_id = a.application_id);

    UPDATE application SET status = 'WAITING'
    WHERE status = 'SUBMITTED'
      AND application_id IN (SELECT application_id FROM admission_result WHERE status = 'WAITING' AND round = p_round);

    -- Running the lottery CLOSES the application window but does NOT publish.
    -- The allocation now exists in admission_result, yet stays invisible to the
    -- applicant side until the admin explicitly calls sp_publish_results() --
    -- so a run can be inspected (and re-run) before anyone can look it up.
    -- Re-running therefore also un-publishes: the previously published result
    -- no longer matches what is in the table, so it must not stay readable.
    INSERT INTO app_setting (key, value) VALUES ('RESULT_READY', 'FALSE')
    ON CONFLICT (key) DO UPDATE SET value = 'FALSE', updated_at = now();
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
