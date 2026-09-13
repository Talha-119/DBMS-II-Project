-- ============================================================================
-- functions/05_limits.sql
-- Read-side helpers for the application rate limits. The rules themselves are
-- enforced by triggers (triggers/02_rules.sql) and sp_submit_application; these
-- functions only *report* the same state, so the apply form can grey out what is
-- already spent instead of letting a student fill a whole form the database will
-- refuse at the last step.
--
-- Both deliberately ignore DELETED applications: withdrawing an application
-- releases its slot, its area and its schools.
-- ============================================================================

-- Schools this student already holds in a live application. Used to filter the
-- school/seat pickers, and stated at school level because one student gets one
-- shot per school regardless of which shift they picked.
CREATE OR REPLACE FUNCTION fn_schools_used_by(p_bc TEXT)
RETURNS TABLE (eiin VARCHAR(10))
LANGUAGE sql STABLE AS $$
    SELECT DISTINCT se.eiin
    FROM application_choice ac
    JOIN application a ON a.application_id = ac.application_id
    JOIN seat se       ON se.seat_id = ac.seat_id
    WHERE a.bc_no = p_bc
      AND a.status <> 'DELETED';
$$;

-- Everything the apply form needs to explain the limits to one applicant.
-- Returns a single row, and works for a first-time applicant (all zeroes), so
-- the caller never has to special-case "no profile yet".
CREATE OR REPLACE FUNCTION fn_applicant_limits(p_bc TEXT)
RETURNS TABLE (
    max_applications       INT,
    applications_used      INT,
    applications_remaining INT,
    applications_deleted   INT,
    used_postcodes         JSONB,
    used_schools           JSONB
)
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_max INT;
BEGIN
    v_max := COALESCE(
        (SELECT value::INT FROM app_setting WHERE key = 'MAX_APPLICATIONS'), 3);

    RETURN QUERY
    WITH live AS (
        SELECT * FROM application WHERE bc_no = p_bc AND status <> 'DELETED'
    ),
    gone AS (
        SELECT * FROM application WHERE bc_no = p_bc AND status = 'DELETED'
    )
    SELECT
        v_max,
        (SELECT count(*)::INT FROM live),
        GREATEST(v_max - (SELECT count(*)::INT FROM live), 0),
        (SELECT count(*)::INT FROM gone),
        COALESCE((
            SELECT jsonb_agg(DISTINCT l.applying_postcode ORDER BY l.applying_postcode)
            FROM live l
        ), '[]'::jsonb),
        COALESCE((
            SELECT jsonb_agg(DISTINCT jsonb_build_object('eiin', s.eiin, 'name', s.name))
            FROM fn_schools_used_by(p_bc) u
            JOIN school s ON s.eiin = u.eiin
        ), '[]'::jsonb);
END;
$$;
