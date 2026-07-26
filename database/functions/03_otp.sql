-- ============================================================================
-- functions/03_otp.sql
-- One-time-password (OTP) helpers, implemented in the DB with pgcrypto so codes
-- are never stored or compared in plaintext, and the same rules apply to every
-- client. Applicants are account-less, so there is no login/password logic here
-- (staff authentication lives in the separate school-authority/admin system).
-- ============================================================================

-- Issue a 6-digit OTP for (purpose, mobile). Stores only the HASH + an expiry,
-- and returns the plaintext code so the caller can deliver it (SMS in prod;
-- shown in dev).
CREATE OR REPLACE FUNCTION fn_issue_otp(p_purpose TEXT, p_mobile TEXT, p_ttl_seconds INT DEFAULT 300)
RETURNS TEXT
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_code TEXT;
BEGIN
    IF NOT fn_validate_bd_mobile(p_mobile) THEN
        RAISE EXCEPTION 'Invalid mobile number %', p_mobile USING ERRCODE = '23514';
    END IF;
    v_code := lpad((floor(random() * 1000000))::INT::TEXT, 6, '0');
    INSERT INTO otp (purpose, mobile, code_hash, expires_at)
    VALUES (p_purpose, p_mobile, crypt(v_code, gen_salt('bf', 8)),
            now() + make_interval(secs => p_ttl_seconds));
    RETURN v_code;
END;
$$;

-- Verify an OTP: must be the latest unconsumed, unexpired code for (purpose,
-- mobile). Marks it consumed on success (single-use).
CREATE OR REPLACE FUNCTION fn_verify_otp(p_purpose TEXT, p_mobile TEXT, p_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_id BIGINT;
BEGIN
    SELECT otp_id INTO v_id
    FROM otp
    WHERE purpose = p_purpose
      AND mobile = p_mobile
      AND consumed = FALSE
      AND expires_at > now()
      AND code_hash = crypt(p_code, code_hash)
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_id IS NULL THEN
        RETURN FALSE;
    END IF;

    UPDATE otp SET consumed = TRUE WHERE otp_id = v_id;
    RETURN TRUE;
END;
$$;
