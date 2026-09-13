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
--   * any supplied parent NID must BE the NID recorded on the birth certificate
--     (this is the core "no info mismatch" guarantee);
--   * any supplied local-guardian NID must exist in the NID registry.
--
-- The parent check is an identity comparison, not a name comparison. It used to
-- resolve the submitted NID to a name and string-match that against
-- birth_certificate.father_name — which any same-named stranger satisfied, and
-- in this registry up to 8 citizens share a name (BUG-002). Because the birth
-- certificate now records the parent's NID directly, the correct check is simply
-- whether the submitted NID *is* that one.
--
-- The recorded NID is deliberately NOT echoed in the error. The caller has
-- proven nothing at this point, so a mismatch must not leak the very value it is
-- asking for — otherwise the check degrades into an oracle that hands out the
-- parent's national ID to anyone who knows a birth-certificate number.
CREATE OR REPLACE FUNCTION fn_check_guardian(
    p_bc_no      TEXT,
    p_father_nid TEXT,
    p_mother_nid TEXT,
    p_local_nid  TEXT
) RETURNS VOID
LANGUAGE plpgsql STABLE AS $$
DECLARE
    v_bc birth_certificate%ROWTYPE;
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

    IF p_father_nid IS NOT NULL AND p_father_nid IS DISTINCT FROM v_bc.father_nid THEN
        RAISE EXCEPTION 'The NID given as father is not the father recorded on birth certificate %', p_bc_no
            USING ERRCODE = '23514';
    END IF;

    IF p_mother_nid IS NOT NULL AND p_mother_nid IS DISTINCT FROM v_bc.mother_nid THEN
        RAISE EXCEPTION 'The NID given as mother is not the mother recorded on birth certificate %', p_bc_no
            USING ERRCODE = '23514';
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

-- True if the bytes look like a real JPEG: the SOI marker (FF D8) opens the
-- stream and the EOI marker (FF D9) closes it. NULL is "nothing to check", so it
-- passes — student.photo is optional (see migrations/004_application.sql).
--
-- This is a backstop, not the real validation. The upload route decodes the
-- image with sharp and re-encodes it to JPEG at a fixed size before anything is
-- written (backend/src/utils/photo.js), so traffic arriving through the API is
-- already guaranteed to satisfy this. What the function adds is that the
-- guarantee also holds for direct SQL — the same reason fn_validate_bd_mobile
-- and fn_check_guardian live in the database rather than in the form.
--
-- It deliberately checks only the container markers. Postgres cannot decode an
-- image, so it cannot tell a real photograph from a JPEG of a blank wall; what
-- it can cheaply refuse is a PNG, a PDF, a ZIP or a text file sitting in a
-- column the rest of the system serves as image/jpeg.
CREATE OR REPLACE FUNCTION fn_is_jpeg(p_image BYTEA)
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_len INT;
BEGIN
    IF p_image IS NULL THEN
        RETURN TRUE;
    END IF;
    v_len := octet_length(p_image);
    IF v_len < 4 THEN
        RETURN FALSE;
    END IF;
    RETURN get_byte(p_image, 0)         = 255   -- 0xFF ) start of image
       AND get_byte(p_image, 1)         = 216   -- 0xD8 )
       AND get_byte(p_image, v_len - 2) = 255   -- 0xFF ) end of image
       AND get_byte(p_image, v_len - 1) = 217;  -- 0xD9 )
END;
$$;
