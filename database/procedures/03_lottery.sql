-- ============================================================================
-- procedures/03_lottery.sql
-- The seat-allocation lottery, implemented with an explicit CURSOR over seats.
-- For each seat it fills quotas in priority order (e.g. Freedom Fighter -> Area
-- -> General), picking a random eligible applicant for each open slot. A student
-- who wins anywhere is removed from contention for everything else.
--
-- MULTI-ROUND: each run keeps prior ADMITTED results (and their consumed seats),
-- clears the non-final WAITING results, and allocates the *remaining* seat
-- capacity to applicants who are still unseated. So calling it again (round 2, 3…)
-- migrates waiting applicants into seats freed up / left over. Safe to re-run.
-- Concurrency-safe via a transaction advisory lock.
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_run_lottery(p_round INT DEFAULT 1)
LANGUAGE plpgsql AS $$
DECLARE
    seat_cur CURSOR FOR SELECT seat_id FROM seat ORDER BY seat_id;
    v_seat_id  TEXT;
    v_progress BOOLEAN := TRUE;
    v_q        RECORD;
    v_winner   RECORD;
BEGIN
    -- Only one lottery may run at a time (prevents double allocation).
    PERFORM pg_advisory_xact_lock(42);

    -- Keep finalized admissions; reconsider everyone else this round.
    DELETE FROM admission_result WHERE status <> 'ADMITTED';
    UPDATE application SET status = 'SUBMITTED' WHERE status <> 'ADMITTED';

    -- Repeat full passes until a pass seats nobody new (converges as remaining
    -- capacity and candidate pools shrink).
    WHILE v_progress LOOP
        v_progress := FALSE;
        OPEN seat_cur;
        LOOP
            FETCH seat_cur INTO v_seat_id;
            EXIT WHEN NOT FOUND;

            -- Try quotas in priority order; seat at most one applicant per seat per pass.
            FOR v_q IN
                SELECT sq.quota_code
                FROM seat_quota sq
                JOIN quota_type qt ON qt.code = sq.quota_code
                WHERE sq.seat_id = v_seat_id AND sq.capacity > 0
                ORDER BY qt.priority
            LOOP
                SELECT ac.application_id, a.bc_no
                INTO v_winner
                FROM application_choice ac
                JOIN application a ON a.application_id = ac.application_id
                JOIN choice_quota cq ON cq.choice_id = ac.choice_id
                WHERE ac.seat_id = v_seat_id
                  AND cq.quota_code = v_q.quota_code
                  AND a.status = 'SUBMITTED'
                  AND NOT EXISTS (SELECT 1 FROM admission_result r WHERE r.application_id = ac.application_id)
                  -- the student must not already be admitted (via any application/round)
                  AND NOT EXISTS (
                        SELECT 1 FROM admission_result r
                        JOIN application a2 ON a2.application_id = r.application_id
                        WHERE a2.bc_no = a.bc_no AND r.status = 'ADMITTED'
                  )
                ORDER BY random()
                LIMIT 1;

                IF FOUND THEN
                    INSERT INTO admission_result (application_id, admitted_seat_id, allocated_quota, status, round)
                    VALUES (v_winner.application_id, v_seat_id, v_q.quota_code, 'ADMITTED', p_round);

                    UPDATE application SET status = 'ADMITTED' WHERE application_id = v_winner.application_id;

                    UPDATE seat_quota SET capacity = capacity - 1
                    WHERE seat_id = v_seat_id AND quota_code = v_q.quota_code;

                    v_progress := TRUE;
                    EXIT;  -- one winner per seat per pass
                END IF;
            END LOOP;
        END LOOP;
        CLOSE seat_cur;
    END LOOP;

    -- Anyone still SUBMITTED did not get a seat this round -> WAITING.
    INSERT INTO admission_result (application_id, admitted_seat_id, allocated_quota, status, round)
    SELECT a.application_id, NULL, NULL, 'WAITING', p_round
    FROM application a
    WHERE a.status = 'SUBMITTED'
      AND NOT EXISTS (SELECT 1 FROM admission_result r WHERE r.application_id = a.application_id);

    UPDATE application SET status = 'WAITING'
    WHERE status = 'SUBMITTED'
      AND application_id IN (SELECT application_id FROM admission_result WHERE status = 'WAITING' AND round = p_round);

    -- Publish: results are ready and the application window is closed.
    INSERT INTO app_setting (key, value) VALUES ('RESULT_READY', 'TRUE')
    ON CONFLICT (key) DO UPDATE SET value = 'TRUE', updated_at = now();
    INSERT INTO app_setting (key, value) VALUES ('ROUND_OPEN', 'FALSE')
    ON CONFLICT (key) DO UPDATE SET value = 'FALSE', updated_at = now();
    INSERT INTO app_setting (key, value) VALUES ('CURRENT_ROUND', p_round::TEXT)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();
END;
$$;
