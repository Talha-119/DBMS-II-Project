-- ============================================================================
-- functions/04_auth.sql
-- Authentication + OTP, implemented in the DB with pgcrypto so secrets are
-- never stored or compared in plaintext, and the same rules apply to every client.
-- ============================================================================

-- Hash a password with bcrypt (pgcrypto blowfish). Returns the hash to store.
CREATE OR REPLACE FUNCTION fn_hash_password(p_password TEXT)
RETURNS TEXT
LANGUAGE sql VOLATILE AS $$
    SELECT crypt(p_password, gen_salt('bf', 10));
$$;

-- Verify a login. Returns the account row(s) when credentials match, else none.
CREATE OR REPLACE FUNCTION fn_verify_login(p_login_id TEXT, p_password TEXT)
RETURNS TABLE (account_id BIGINT, role account_role_t, eiin VARCHAR, must_change_password BOOLEAN)
LANGUAGE sql STABLE AS $$
    SELECT a.account_id, a.role, a.eiin, a.must_change_password
    FROM account a
    WHERE a.login_id = p_login_id
      AND a.password_hash = crypt(p_password, a.password_hash);
$$;

-- Change an account's password (hashed) and clear the must-change flag.
CREATE OR REPLACE FUNCTION fn_set_password(p_login_id TEXT, p_new_password TEXT)
RETURNS VOID
LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    UPDATE account
       SET password_hash = fn_hash_password(p_new_password),
           must_change_password = FALSE
     WHERE login_id = p_login_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account % not found', p_login_id USING ERRCODE = 'P0002';
    END IF;
END;
$$;

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
