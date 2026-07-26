-- ============================================================================
-- functions/01_validation.sql
-- Validation / lookup functions. These encode identity rules in the DB so the
-- same checks apply no matter which client calls them (anti-mismatch + security).
-- ============================================================================

-- True if the string is a valid Bangladeshi mobile number (01[3-9] + 8 digits).
CREATE OR REPLACE FUNCTION fn_validate_bd_mobile(p_mobile TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
    RETURN p_mobile ~ '^01[3-9][0-9]{8}$';
END;
$$;

-- Resolve a NID to its registered name (NULL if the NID is unknown).
CREATE OR REPLACE FUNCTION fn_nid_name(p_nid TEXT)
RETURNS TEXT
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_name TEXT;
BEGIN
    SELECT name INTO v_name FROM nid WHERE nid = p_nid;
    RETURN v_name;
END;
$$;

-- Enforce guardian rules for a student. Raises a descriptive exception when a
-- rule is violated; returns normally when everything is consistent:
--   * at least one guardian must be supplied;
--   * any supplied parent NID must exist AND its name must match the birth
--     certificate (this is the core "no info mismatch" guarantee);
--   * any supplied local-guardian NID must exist in the NID registry.
CREATE OR REPLACE FUNCTION fn_check_guardian(
    p_bc_no      TEXT,
    p_father_nid TEXT,
    p_mother_nid TEXT,
    p_local_nid  TEXT
) RETURNS VOID
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_bc   birth_certificate%ROWTYPE;
    v_name TEXT;
BEGIN
    SELECT * INTO v_bc FROM birth_certificate WHERE bc_no = p_bc_no;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Birth certificate % not found in registry', p_bc_no
            USING ERRCODE = '23503';
    END IF;

    IF p_father_nid IS NULL AND p_mother_nid IS NULL AND p_local_nid IS NULL THEN
        RAISE EXCEPTION 'At least one guardian (father, mother, or local guardian) is required'
            USING ERRCODE = '23514';
    END IF;

    IF p_father_nid IS NOT NULL THEN
        v_name := fn_nid_name(p_father_nid);
        IF v_name IS NULL THEN
            RAISE EXCEPTION 'Father NID % not found in NID registry', p_father_nid
                USING ERRCODE = '23503';
        END IF;
        IF upper(trim(v_name)) <> upper(trim(v_bc.father_name)) THEN
            RAISE EXCEPTION 'Father name on NID (%) does not match birth certificate (%)',
                v_name, v_bc.father_name USING ERRCODE = '23514';
        END IF;
    END IF;

    IF p_mother_nid IS NOT NULL THEN
        v_name := fn_nid_name(p_mother_nid);
        IF v_name IS NULL THEN
            RAISE EXCEPTION 'Mother NID % not found in NID registry', p_mother_nid
                USING ERRCODE = '23503';
        END IF;
        IF upper(trim(v_name)) <> upper(trim(v_bc.mother_name)) THEN
            RAISE EXCEPTION 'Mother name on NID (%) does not match birth certificate (%)',
                v_name, v_bc.mother_name USING ERRCODE = '23514';
        END IF;
    END IF;

    IF p_local_nid IS NOT NULL AND fn_nid_name(p_local_nid) IS NULL THEN
        RAISE EXCEPTION 'Local guardian NID % not found in NID registry', p_local_nid
            USING ERRCODE = '23503';
    END IF;
END;
$$;

-- Validate that a quota reference exists and matches the claimed quota.
-- Returns normally when valid, raises otherwise. NULL ref is allowed only for
-- quotas that do not require a reference (checked by the caller).
CREATE OR REPLACE FUNCTION fn_check_quota_reference(
    p_quota_code TEXT,
    p_ref_id     TEXT
) RETURNS VOID
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_requires BOOLEAN;
    v_ref_quota TEXT;
BEGIN
    SELECT requires_reference INTO v_requires FROM quota_type WHERE code = p_quota_code;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Unknown quota %', p_quota_code USING ERRCODE = '23503';
    END IF;

    IF v_requires THEN
        IF p_ref_id IS NULL THEN
            RAISE EXCEPTION 'Quota % requires a reference id', p_quota_code
                USING ERRCODE = '23514';
        END IF;
        SELECT quota_code INTO v_ref_quota FROM quota_reference WHERE ref_id = p_ref_id;
        IF v_ref_quota IS NULL THEN
            RAISE EXCEPTION 'Reference % not found', p_ref_id USING ERRCODE = '23503';
        END IF;
        IF v_ref_quota <> p_quota_code THEN
            RAISE EXCEPTION 'Reference % is not valid for quota %', p_ref_id, p_quota_code
                USING ERRCODE = '23514';
        END IF;
    END IF;
END;
$$;
