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

-- The admission reference date: 1 January of the admission year. Age limits are
-- quoted against this date (as the national portal does), not against "today",
-- so a class's advertised age range stays stable throughout the round.
CREATE OR REPLACE FUNCTION fn_admission_reference_date()
RETURNS DATE
LANGUAGE sql STABLE AS $$
    SELECT make_date(
        COALESCE(
            (SELECT value::INT FROM app_setting WHERE key = 'ADMISSION_YEAR'),
            EXTRACT(YEAR FROM CURRENT_DATE)::INT
        ), 1, 1);
$$;

-- Every configured class with its accepted date-of-birth window AND the age
-- range that window represents. Powers the public age calculator (which must be
-- able to show the window for a class the applicant FAILED) and the admin editor.
CREATE OR REPLACE FUNCTION fn_class_eligibility_info()
RETURNS TABLE (class_level INT, min_dob DATE, max_dob DATE, min_age INT, max_age INT, reference_date DATE)
LANGUAGE sql STABLE AS $$
    SELECT ce.class_level, ce.min_dob, ce.max_dob,
           EXTRACT(YEAR FROM age(fn_admission_reference_date(), ce.max_dob))::INT AS min_age,
           EXTRACT(YEAR FROM age(fn_admission_reference_date(), ce.min_dob))::INT AS max_age,
           fn_admission_reference_date()
    FROM class_eligibility ce
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

-- The date-of-birth window a single school actually applies for a class: its own
-- narrowed window when it has set one, otherwise the national baseline.
CREATE OR REPLACE FUNCTION fn_school_class_window(p_eiin TEXT, p_class INT)
RETURNS TABLE (min_dob DATE, max_dob DATE, is_custom BOOLEAN)
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(sce.min_dob, ce.min_dob),
           COALESCE(sce.max_dob, ce.max_dob),
           sce.eiin IS NOT NULL
    FROM class_eligibility ce
    LEFT JOIN school_class_eligibility sce
           ON sce.class_level = ce.class_level AND sce.eiin = p_eiin
    WHERE ce.class_level = p_class;
$$;

-- True if a child born on p_dob is age-eligible for class p_class AT THIS SCHOOL.
-- Stricter than (or equal to) fn_is_class_eligible, never looser: the trigger on
-- school_class_eligibility keeps every school window inside the national one.
CREATE OR REPLACE FUNCTION fn_is_class_eligible_at_school(p_dob DATE, p_class INT, p_eiin TEXT)
RETURNS BOOLEAN
LANGUAGE sql STABLE AS $$
    SELECT EXISTS (
        SELECT 1 FROM fn_school_class_window(p_eiin, p_class) w
        WHERE p_dob BETWEEN w.min_dob AND w.max_dob
    );
$$;

-- Every class as one school sees it: the national baseline, this school's own
-- override (NULL when it has none), and the effective window in force. Powers
-- the school-authority editor.
CREATE OR REPLACE FUNCTION fn_school_class_eligibility_info(p_eiin TEXT)
RETURNS TABLE (
    class_level INT, national_min_dob DATE, national_max_dob DATE,
    school_min_dob DATE, school_max_dob DATE,
    min_dob DATE, max_dob DATE, is_custom BOOLEAN,
    min_age INT, max_age INT, reference_date DATE
)
LANGUAGE sql STABLE AS $$
    SELECT ce.class_level, ce.min_dob, ce.max_dob,
           sce.min_dob, sce.max_dob,
           COALESCE(sce.min_dob, ce.min_dob), COALESCE(sce.max_dob, ce.max_dob),
           sce.eiin IS NOT NULL,
           EXTRACT(YEAR FROM age(fn_admission_reference_date(), COALESCE(sce.max_dob, ce.max_dob)))::INT,
           EXTRACT(YEAR FROM age(fn_admission_reference_date(), COALESCE(sce.min_dob, ce.min_dob)))::INT,
           fn_admission_reference_date()
    FROM class_eligibility ce
    LEFT JOIN school_class_eligibility sce
           ON sce.class_level = ce.class_level AND sce.eiin = p_eiin
    ORDER BY ce.class_level;
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
