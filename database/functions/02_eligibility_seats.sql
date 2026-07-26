-- ============================================================================
-- functions/02_eligibility_seats.sql
-- Age-eligibility, id generation, and seat-availability helpers.
-- ============================================================================

-- Table-returning function: every class a child born on p_dob is eligible for.
CREATE OR REPLACE FUNCTION fn_eligible_classes(p_dob DATE)
RETURNS TABLE (class_level INT, min_dob DATE, max_dob DATE)
LANGUAGE sql STABLE AS $$
    SELECT ce.class_level, ce.min_dob, ce.max_dob
    FROM class_eligibility ce
    WHERE p_dob BETWEEN ce.min_dob AND ce.max_dob
    ORDER BY ce.class_level;
$$;

-- True if a child born on p_dob is age-eligible for class p_class.
CREATE OR REPLACE FUNCTION fn_is_class_eligible(p_dob DATE, p_class INT)
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM class_eligibility
        WHERE class_level = p_class AND p_dob BETWEEN min_dob AND max_dob
    );
$$;

-- Generate the next human-readable application id, e.g. APP-2026-000123.
CREATE OR REPLACE FUNCTION fn_next_application_id()
RETURNS TEXT
LANGUAGE plpgsql AS $$
DECLARE
    v_n BIGINT;
BEGIN
    v_n := nextval('seq_application');
    RETURN 'APP-' || to_char(now(), 'YYYY') || '-' || lpad(v_n::TEXT, 6, '0');
END;
$$;

-- Remaining capacity for one quota on a seat row (0 if none / unknown).
CREATE OR REPLACE FUNCTION fn_seat_available(p_seat_id TEXT, p_quota TEXT)
RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(
        (SELECT capacity FROM seat_quota WHERE seat_id = p_seat_id AND quota_code = p_quota),
        0
    );
$$;

-- Total remaining capacity (across all quotas) for a seat row.
CREATE OR REPLACE FUNCTION fn_seat_total_available(p_seat_id TEXT)
RETURNS INT
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(SUM(capacity), 0)::INT FROM seat_quota WHERE seat_id = p_seat_id;
$$;
