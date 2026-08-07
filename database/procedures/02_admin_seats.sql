-- ============================================================================
-- procedures/02_admin_seats.sql
-- Master-admin school creation and authority seat management.
-- ============================================================================

-- Create a school + its authority login. Generates a sequence-based EIIN and a
-- random temporary password (returned once, stored only as a bcrypt hash).
CREATE OR REPLACE PROCEDURE sp_add_school(
    p_name          TEXT,
    p_postcode      TEXT,
    p_school_gender seat_gender_t,
    INOUT p_eiin     TEXT DEFAULT NULL,
    INOUT p_password TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM postcode WHERE postcode = p_postcode) THEN
        RAISE EXCEPTION 'Invalid postcode %', p_postcode USING ERRCODE = '23503';
    END IF;

    p_eiin := lpad(nextval('seq_eiin')::TEXT, 6, '0');
    INSERT INTO school (eiin, name, postcode, school_gender)
    VALUES (p_eiin, p_name, p_postcode, p_school_gender);

    -- 8 hex chars = a reasonable temporary password.
    p_password := encode(gen_random_bytes(4), 'hex');
    INSERT INTO account (role, login_id, password_hash, eiin, must_change_password)
    VALUES ('SCHOOL_AUTHORITY', p_eiin, fn_hash_password(p_password), p_eiin, TRUE);
END;
$$;

-- Delete a school outright (master-admin "Delete" button). A plain `DELETE FROM
-- school` would cascade onto its seats/account/eligibility rows fine, but would
-- hit the (deliberately non-cascading) FKs from application_choice and
-- admission_result and abort with a raw, unreadable constraint error. Check
-- those blockers first and raise a message an admin can actually act on.
CREATE OR REPLACE PROCEDURE sp_delete_school(
    p_eiin TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_chosen   INT;
    v_admitted INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM school WHERE eiin = p_eiin) THEN
        RAISE EXCEPTION 'School % not found', p_eiin USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*) INTO v_chosen
    FROM application_choice ac JOIN seat se ON se.seat_id = ac.seat_id
    WHERE se.eiin = p_eiin;
    IF v_chosen > 0 THEN
        RAISE EXCEPTION
            'School % is chosen by % application(s) and cannot be deleted', p_eiin, v_chosen
            USING ERRCODE = '23503';
    END IF;

    SELECT count(*) INTO v_admitted
    FROM admission_result r JOIN seat se ON se.seat_id = r.admitted_seat_id
    WHERE se.eiin = p_eiin;
    IF v_admitted > 0 THEN
        RAISE EXCEPTION
            'School % has % admitted/waiting result(s) and cannot be deleted', p_eiin, v_admitted
            USING ERRCODE = '23503';
    END IF;

    -- Nothing references it: seat, seat_quota, account and
    -- school_class_eligibility all cascade from here.
    DELETE FROM school WHERE eiin = p_eiin;
END;
$$;

-- Split a seat's total capacity across all quota types by their default_share,
-- giving the rounding remainder to the catch-all (is_default) quota. Reused by
-- sp_add_seat and sp_rebalance_seats, so quota changes are applied consistently.
CREATE OR REPLACE PROCEDURE sp_set_seat_quotas(
    p_seat_id TEXT,
    p_total   INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_q        RECORD;
    v_assigned INT := 0;
    v_cap      INT;
    v_default  TEXT;
BEGIN
    -- The catch-all quota (is_default); fall back to lowest priority if none flagged.
    SELECT code INTO v_default FROM quota_type WHERE is_default ORDER BY priority LIMIT 1;
    IF v_default IS NULL THEN
        SELECT code INTO v_default FROM quota_type ORDER BY priority DESC LIMIT 1;
    END IF;

    DELETE FROM seat_quota WHERE seat_id = p_seat_id;

    FOR v_q IN SELECT code, default_share FROM quota_type WHERE code <> v_default ORDER BY priority LOOP
        v_cap := floor(p_total * v_q.default_share)::INT;
        INSERT INTO seat_quota (seat_id, quota_code, capacity) VALUES (p_seat_id, v_q.code, v_cap);
        v_assigned := v_assigned + v_cap;
    END LOOP;

    INSERT INTO seat_quota (seat_id, quota_code, capacity)
    VALUES (p_seat_id, v_default, GREATEST(p_total - v_assigned, 0));
END;
$$;

-- Create or retune a quota type at runtime (new quota, changed %, new priority,
-- or move the catch-all flag). Keeps the single-default invariant.
CREATE OR REPLACE PROCEDURE sp_upsert_quota_type(
    p_code     TEXT,
    p_name     TEXT,
    p_requires BOOLEAN,
    p_priority INT,
    p_share    NUMERIC,
    p_is_default BOOLEAN
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_priority IS NULL OR p_priority <= 0 THEN
        RAISE EXCEPTION 'Quota priority must be a positive integer' USING ERRCODE = '23514';
    END IF;
    IF p_is_default THEN
        UPDATE quota_type SET is_default = FALSE WHERE is_default AND code <> p_code;
    END IF;
    INSERT INTO quota_type (code, name, requires_reference, priority, default_share, is_default)
    VALUES (p_code, p_name, COALESCE(p_requires, FALSE), p_priority, COALESCE(p_share, 0), COALESCE(p_is_default, FALSE))
    ON CONFLICT (code) DO UPDATE SET
        name = EXCLUDED.name,
        requires_reference = EXCLUDED.requires_reference,
        priority = EXCLUDED.priority,
        default_share = EXCLUDED.default_share,
        is_default = EXCLUDED.is_default;
END;
$$;

-- Add (or update) a seat row for a school and split its total capacity by the
-- current quota shares (data-driven; new quotas auto-participate).
CREATE OR REPLACE PROCEDURE sp_add_seat(
    p_eiin   TEXT,
    p_class  INT,
    p_shift  shift_t,
    p_gender seat_gender_t,
    p_total  INT,
    INOUT p_seat_id TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_total < 0 THEN
        RAISE EXCEPTION 'Total seats cannot be negative' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM school WHERE eiin = p_eiin) THEN
        RAISE EXCEPTION 'School % not found', p_eiin USING ERRCODE = '23503';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM class_eligibility WHERE class_level = p_class) THEN
        RAISE EXCEPTION 'Class % is not configured in class_eligibility', p_class USING ERRCODE = '23503';
    END IF;

    SELECT seat_id INTO p_seat_id FROM seat
    WHERE eiin = p_eiin AND class_level = p_class AND shift = p_shift AND seat_gender = p_gender;

    IF p_seat_id IS NULL THEN
        p_seat_id := 'S-' || lpad(nextval('seq_seat')::TEXT, 8, '0');
        INSERT INTO seat (seat_id, eiin, class_level, shift, seat_gender)
        VALUES (p_seat_id, p_eiin, p_class, p_shift, p_gender);
    END IF;

    CALL sp_set_seat_quotas(p_seat_id, p_total);
END;
$$;

-- Re-split every seat by the CURRENT quota shares. Intended for use after quota
-- percentages/types change and BEFORE the lottery runs (it derives each seat's
-- total from its current remaining capacity = the original total pre-lottery).
CREATE OR REPLACE PROCEDURE sp_rebalance_seats()
LANGUAGE plpgsql AS $$
DECLARE
    v_seat   TEXT;
    v_total  INT;
BEGIN
    IF EXISTS (SELECT 1 FROM app_setting WHERE key = 'RESULT_READY' AND value = 'TRUE') THEN
        RAISE EXCEPTION 'Cannot rebalance seats after results are published' USING ERRCODE = '23514';
    END IF;
    FOR v_seat IN SELECT seat_id FROM seat LOOP
        SELECT COALESCE(SUM(capacity), 0)::INT INTO v_total FROM seat_quota WHERE seat_id = v_seat;
        CALL sp_set_seat_quotas(v_seat, v_total);
    END LOOP;
END;
$$;

-- Set (or add) a class's accepted date-of-birth window. Admin-managed config, so
-- the rules live here rather than in the API. Windows deliberately MAY overlap:
-- fn_eligible_classes returns every class a date of birth qualifies for and the
-- apply wizard lets the student pick one, exactly like a wide class-1 window that
-- overlaps class 2 on the national portal.
CREATE OR REPLACE PROCEDURE sp_upsert_class_eligibility(
    p_class   INT,
    p_min_dob DATE,
    p_max_dob DATE
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_class IS NULL OR p_class < 1 OR p_class > 12 THEN
        RAISE EXCEPTION 'Class level must be between 1 and 12' USING ERRCODE = '23514';
    END IF;
    IF p_min_dob IS NULL OR p_max_dob IS NULL THEN
        RAISE EXCEPTION 'Both the earliest and latest date of birth are required' USING ERRCODE = '23514';
    END IF;
    IF p_min_dob > p_max_dob THEN
        RAISE EXCEPTION 'The earliest date of birth must not be after the latest' USING ERRCODE = '23514';
    END IF;
    INSERT INTO class_eligibility (class_level, min_dob, max_dob)
    VALUES (p_class, p_min_dob, p_max_dob)
    ON CONFLICT (class_level)
    DO UPDATE SET min_dob = EXCLUDED.min_dob, max_dob = EXCLUDED.max_dob;
END;
$$;

-- A single school narrows its own accepted date-of-birth window for a class.
-- The national window (above) is the outer bound and is not editable here; the
-- trigger on school_class_eligibility rejects anything wider.
CREATE OR REPLACE PROCEDURE sp_upsert_school_class_eligibility(
    p_eiin    TEXT,
    p_class   INT,
    p_min_dob DATE,
    p_max_dob DATE
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM school WHERE eiin = p_eiin) THEN
        RAISE EXCEPTION 'School % not found', p_eiin USING ERRCODE = '23503';
    END IF;
    IF p_min_dob IS NULL OR p_max_dob IS NULL THEN
        RAISE EXCEPTION 'Both the earliest and latest date of birth are required' USING ERRCODE = '23514';
    END IF;
    IF p_min_dob > p_max_dob THEN
        RAISE EXCEPTION 'The earliest date of birth must not be after the latest' USING ERRCODE = '23514';
    END IF;

    INSERT INTO school_class_eligibility (eiin, class_level, min_dob, max_dob)
    VALUES (p_eiin, p_class, p_min_dob, p_max_dob)
    ON CONFLICT (eiin, class_level)
    DO UPDATE SET min_dob = EXCLUDED.min_dob, max_dob = EXCLUDED.max_dob, updated_at = now();
END;
$$;

-- Drop a school's override so the class falls back to the national window.
CREATE OR REPLACE PROCEDURE sp_reset_school_class_eligibility(
    p_eiin  TEXT,
    p_class INT
)
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM school_class_eligibility WHERE eiin = p_eiin AND class_level = p_class;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'School % has no custom window for class %', p_eiin, p_class
            USING ERRCODE = '23503';
    END IF;
END;
$$;

-- Remove one of a school's own seat rows. Scoped by EIIN so a school can never
-- delete another school's seats. Blocked once applicants or results reference it
-- (the FKs would refuse anyway; this reports why in plain language).
CREATE OR REPLACE PROCEDURE sp_delete_seat(
    p_eiin    TEXT,
    p_seat_id TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_owner TEXT;
    v_used  INT;
BEGIN
    SELECT eiin INTO v_owner FROM seat WHERE seat_id = p_seat_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Seat % not found', p_seat_id USING ERRCODE = '23503';
    END IF;
    IF v_owner <> p_eiin THEN
        RAISE EXCEPTION 'Seat % does not belong to school %', p_seat_id, p_eiin USING ERRCODE = '42501';
    END IF;

    SELECT count(*) INTO v_used FROM application_choice WHERE seat_id = p_seat_id;
    IF v_used > 0 THEN
        RAISE EXCEPTION 'Seat % is chosen by % application(s) and cannot be deleted', p_seat_id, v_used
            USING ERRCODE = '23503';
    END IF;
    IF EXISTS (SELECT 1 FROM admission_result WHERE admitted_seat_id = p_seat_id) THEN
        RAISE EXCEPTION 'Seat % has admitted students and cannot be deleted', p_seat_id
            USING ERRCODE = '23503';
    END IF;

    DELETE FROM seat WHERE seat_id = p_seat_id;   -- seat_quota cascades
END;
$$;

-- Master-admin: remove a school entirely. school -> seat -> seat_quota all
-- cascade at the FK level, but application_choice.seat_id and
-- admission_result.admitted_seat_id do NOT (a chosen/admitted seat must not
-- silently disappear from someone's application). A raw `DELETE FROM school`
-- would therefore fail with a confusing foreign_key_violation on those tables
-- the moment any applicant had chosen one of its seats. Check up front and
-- raise a clear, actionable message instead.
CREATE OR REPLACE PROCEDURE sp_delete_school(
    p_eiin TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_choices INT;
    v_results INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM school WHERE eiin = p_eiin) THEN
        RAISE EXCEPTION 'School % not found', p_eiin USING ERRCODE = 'P0002';
    END IF;

    SELECT count(*) INTO v_choices
    FROM application_choice ac JOIN seat se ON se.seat_id = ac.seat_id
    WHERE se.eiin = p_eiin;
    IF v_choices > 0 THEN
        RAISE EXCEPTION 'School % has % application choice(s) referencing its seats and cannot be deleted',
            p_eiin, v_choices USING ERRCODE = '23503';
    END IF;

    SELECT count(*) INTO v_results
    FROM admission_result r JOIN seat se ON se.seat_id = r.admitted_seat_id
    WHERE se.eiin = p_eiin;
    IF v_results > 0 THEN
        RAISE EXCEPTION 'School % has % admission result(s) tied to its seats and cannot be deleted',
            p_eiin, v_results USING ERRCODE = '23503';
    END IF;

    -- Nothing references its seats: safe to remove. seat/seat_quota/account/
    -- school_class_eligibility all cascade from school via FK.
    DELETE FROM school WHERE eiin = p_eiin;
END;
$$;
