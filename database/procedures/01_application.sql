-- ============================================================================
-- procedures/01_application.sql
-- The transactional heart of the system. sp_submit_application validates every
-- rule (identity, eligibility, quota, gender, seat reuse) inside one transaction
-- and raises a descriptive exception on any violation, so a half-written
-- application can never be persisted.
-- ============================================================================

CREATE OR REPLACE PROCEDURE sp_submit_application(
    p_bc_no              TEXT,
    p_religion           religion_t,
    p_mobile             TEXT,
    p_father_nid         TEXT,
    p_mother_nid         TEXT,
    p_local_nid          TEXT,
    p_present_postcode   TEXT,
    p_present_detail     TEXT,
    p_permanent_postcode TEXT,
    p_permanent_detail   TEXT,
    p_desired_class      INT,
    p_applying_postcode  TEXT,
    p_prev_school_name   TEXT,
    p_choices            JSONB,
    INOUT p_application_id TEXT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
DECLARE
    v_dob        DATE;
    v_gender     gender_t;
    v_choice     JSONB;
    v_seat_id    TEXT;
    v_pref       INT;
    v_quota      TEXT;
    v_ref        TEXT;
    v_seat       seat%ROWTYPE;
    v_student    student%ROWTYPE;
    v_school_pc  CHAR(4);
    v_requires   BOOLEAN;
    v_ref_nid    TEXT;
    v_count      INT := 0;
    v_choice_id  BIGINT;
    v_quota_list JSONB;
    v_qrec       JSONB;
    v_nquota     INT;
BEGIN
    -- 1. Identity comes from the birth-certificate registry (never typed).
    SELECT dob, gender INTO v_dob, v_gender FROM birth_certificate WHERE bc_no = p_bc_no;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Birth certificate % not found in registry', p_bc_no USING ERRCODE = '23503';
    END IF;

    -- 2. Mobile format.
    IF NOT fn_validate_bd_mobile(p_mobile) THEN
        RAISE EXCEPTION 'Invalid Bangladeshi mobile number: %', p_mobile USING ERRCODE = '23514';
    END IF;

    -- 3. Guardian rules (parent name match / local guardian fallback).
    PERFORM fn_check_guardian(p_bc_no, p_father_nid, p_mother_nid, p_local_nid);

    -- 4. Age eligibility for the desired class.
    IF NOT fn_is_class_eligible(v_dob, p_desired_class) THEN
        RAISE EXCEPTION 'Student (DOB %) is not age-eligible for class %', v_dob, p_desired_class
            USING ERRCODE = '23514';
    END IF;

    -- 5. Student profile: written once by the first application, LOCKED thereafter.
    --    A student may file as many applications as they like, but the
    --    identity-bearing half of the form (religion, mobile, guardians, addresses)
    --    is fixed by their first submission; only the applicant half (applying area,
    --    desired class, previous school, seat choices, quotas) varies per application.
    --
    --    This must be a lock and not an upsert. Refreshing the profile on every
    --    submission turned each re-application into a silent profile *edit*, which
    --    (a) let one student claim the AREA quota in any number of districts by
    --    re-pointing their present address, (b) let a guardian NID be swapped for one
    --    holding a Freedom-Fighter reference, (c) retroactively rewrote the address
    --    printed on already-submitted applications, since vw_applicant_copy joins
    --    student live, and (d) let anyone who knows a birth-certificate number
    --    re-register the mobile that authorises retrieve/delete on every earlier
    --    application under it.
    --
    --    A mismatch is rejected naming the offending field rather than silently
    --    substituting the stored value, so a tamper attempt is visible. The stored
    --    value is deliberately NOT echoed back: the caller has to prove nothing to
    --    reach this point, so an error must not disclose the registered mobile,
    --    guardian NID or address of whoever owns that birth certificate.
    SELECT * INTO v_student FROM student WHERE bc_no = p_bc_no;
    IF FOUND THEN
        IF v_student.religion IS DISTINCT FROM p_religion THEN
            RAISE EXCEPTION 'Religion cannot be changed for a returning applicant; it was confirmed by your first application'
                USING ERRCODE = '23514';
        END IF;
        -- One birth certificate, one registered mobile. Every application under this
        -- bc_no is reachable from it (retrieve, delete OTP), so it is a student
        -- attribute, not a per-application one.
        IF v_student.mobile IS DISTINCT FROM p_mobile THEN
            RAISE EXCEPTION 'Mobile number cannot be changed for a returning applicant; all applications under one birth certificate share the mobile registered on the first application'
                USING ERRCODE = '23514';
        END IF;
        IF v_student.father_nid IS DISTINCT FROM p_father_nid THEN
            RAISE EXCEPTION 'Father NID cannot be changed for a returning applicant; it was confirmed by your first application'
                USING ERRCODE = '23514';
        END IF;
        IF v_student.mother_nid IS DISTINCT FROM p_mother_nid THEN
            RAISE EXCEPTION 'Mother NID cannot be changed for a returning applicant; it was confirmed by your first application'
                USING ERRCODE = '23514';
        END IF;
        IF v_student.local_guardian_nid IS DISTINCT FROM p_local_nid THEN
            RAISE EXCEPTION 'Local guardian NID cannot be changed for a returning applicant; it was confirmed by your first application'
                USING ERRCODE = '23514';
        END IF;
        IF v_student.present_postcode IS DISTINCT FROM p_present_postcode
           OR btrim(v_student.present_detail) IS DISTINCT FROM btrim(p_present_detail) THEN
            RAISE EXCEPTION 'Present address cannot be changed for a returning applicant; it was confirmed by your first application'
                USING ERRCODE = '23514';
        END IF;
        IF v_student.permanent_postcode IS DISTINCT FROM p_permanent_postcode
           OR btrim(v_student.permanent_detail) IS DISTINCT FROM btrim(p_permanent_detail) THEN
            RAISE EXCEPTION 'Permanent address cannot be changed for a returning applicant; it was confirmed by your first application'
                USING ERRCODE = '23514';
        END IF;
        -- One child is admitted into one class per session. The eligibility
        -- ranges overlap deliberately (a borderline-age child may pick between
        -- two classes), but picking is not the same as filing for both: two
        -- applications in different classes would double the student's lottery
        -- entries and burn seat choices in each. The first application picks.
        IF v_student.desired_class IS DISTINCT FROM p_desired_class THEN
            RAISE EXCEPTION 'Desired class cannot be changed for a returning applicant; your first application is for class %', v_student.desired_class
                USING ERRCODE = '23514';
        END IF;
        -- The previous school is a fact about the student's history, so it must
        -- read the same on every applicant copy they hold.
        IF btrim(coalesce(v_student.prev_school_name, '')) IS DISTINCT FROM btrim(coalesce(p_prev_school_name, '')) THEN
            RAISE EXCEPTION 'Previous school cannot be changed for a returning applicant; it was confirmed by your first application'
                USING ERRCODE = '23514';
        END IF;
    ELSE
        INSERT INTO student (bc_no, religion, mobile, father_nid, mother_nid, local_guardian_nid,
                             present_postcode, present_detail, permanent_postcode, permanent_detail,
                             desired_class, prev_school_name)
        VALUES (p_bc_no, p_religion, p_mobile, p_father_nid, p_mother_nid, p_local_nid,
                p_present_postcode, p_present_detail, p_permanent_postcode, p_permanent_detail,
                p_desired_class, p_prev_school_name);
    END IF;

    -- 6. Create the application (id generated by sequence-backed function).
    p_application_id := fn_next_application_id();
    -- Class and previous school now live on `student` (written above), so the
    -- application row carries only what varies per application.
    INSERT INTO application (application_id, bc_no, applying_postcode)
    VALUES (p_application_id, p_bc_no, p_applying_postcode);

    -- 7. Choices (1..5).
    IF p_choices IS NULL OR jsonb_array_length(p_choices) = 0 THEN
        RAISE EXCEPTION 'At least one seat choice is required' USING ERRCODE = '23514';
    END IF;
    IF jsonb_array_length(p_choices) > 5 THEN
        RAISE EXCEPTION 'A maximum of 5 choices is allowed' USING ERRCODE = '23514';
    END IF;

    FOR v_choice IN SELECT * FROM jsonb_array_elements(p_choices) LOOP
        v_count   := v_count + 1;
        v_seat_id := v_choice ->> 'seat_id';
        v_pref    := COALESCE((v_choice ->> 'preference')::INT, v_count);

        SELECT * INTO v_seat FROM seat WHERE seat_id = v_seat_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Seat % not found', v_seat_id USING ERRCODE = '23503';
        END IF;

        -- Seat must be for the desired class.
        IF v_seat.class_level <> p_desired_class THEN
            RAISE EXCEPTION 'Seat % is for class %, not the desired class %',
                v_seat_id, v_seat.class_level, p_desired_class USING ERRCODE = '23514';
        END IF;

        -- Seat must be in the applying area.
        SELECT postcode INTO v_school_pc FROM school WHERE eiin = v_seat.eiin;
        IF v_school_pc <> p_applying_postcode THEN
            RAISE EXCEPTION 'Seat % is not in the applying area %', v_seat_id, p_applying_postcode
                USING ERRCODE = '23514';
        END IF;

        -- Gender compatibility (BOTH accepts anyone).
        IF v_seat.seat_gender <> 'BOTH' AND v_seat.seat_gender::TEXT <> v_gender::TEXT THEN
            RAISE EXCEPTION 'Seat % gender (%) does not match student gender (%)',
                v_seat_id, v_seat.seat_gender, v_gender USING ERRCODE = '23514';
        END IF;

        -- Resolve the quota list for this choice. Accept either a `quotas` array
        -- (new, multi-quota) or a single `quota_code`/`ref_id` (backward compatible).
        IF (v_choice ? 'quotas') AND jsonb_typeof(v_choice -> 'quotas') = 'array'
           AND jsonb_array_length(v_choice -> 'quotas') > 0 THEN
            v_quota_list := v_choice -> 'quotas';
        ELSE
            v_quota_list := jsonb_build_array(
                jsonb_build_object('quota_code', v_choice ->> 'quota_code', 'ref_id', v_choice ->> 'ref_id'));
        END IF;

        -- Validate every claimed quota BEFORE persisting anything for this choice.
        v_nquota := 0;
        FOR v_qrec IN SELECT * FROM jsonb_array_elements(v_quota_list) LOOP
            v_quota := v_qrec ->> 'quota_code';
            v_ref   := v_qrec ->> 'ref_id';
            IF v_quota IS NULL OR v_quota = '' THEN
                RAISE EXCEPTION 'A quota is required for each choice' USING ERRCODE = '23514';
            END IF;
            v_nquota := v_nquota + 1;

            -- Quota reference validity (raises if a required reference is missing/invalid).
            PERFORM fn_check_quota_reference(v_quota, v_ref);

            -- A reference-backed quota (e.g. Freedom Fighter) must belong to a parent.
            SELECT requires_reference INTO v_requires FROM quota_type WHERE code = v_quota;
            IF v_requires THEN
                SELECT nid INTO v_ref_nid FROM quota_reference WHERE ref_id = v_ref;
                IF v_ref_nid IS DISTINCT FROM p_father_nid AND v_ref_nid IS DISTINCT FROM p_mother_nid THEN
                    RAISE EXCEPTION 'Reference % must belong to the father or mother NID', v_ref
                        USING ERRCODE = '23514';
                END IF;
            END IF;

            -- Area quota only when the applying area equals the present address area.
            IF v_quota = 'AREA' AND p_applying_postcode IS DISTINCT FROM p_present_postcode THEN
                RAISE EXCEPTION 'Area quota requires the present address to be in the applying area'
                    USING ERRCODE = '23514';
            END IF;
        END LOOP;

        IF v_nquota = 0 THEN
            RAISE EXCEPTION 'Each choice must claim at least one quota' USING ERRCODE = '23514';
        END IF;

        -- A student may not reuse the same seat across their applications.
        IF EXISTS (
            SELECT 1 FROM application_choice ac
            JOIN application a ON a.application_id = ac.application_id
            WHERE a.bc_no = p_bc_no AND ac.seat_id = v_seat_id
        ) THEN
            RAISE EXCEPTION 'Seat % was already used in a previous application of this student', v_seat_id
                USING ERRCODE = '23505';
        END IF;

        -- Persist the choice and its (validated) quotas.
        INSERT INTO application_choice (application_id, seat_id, preference)
        VALUES (p_application_id, v_seat_id, v_pref)
        RETURNING choice_id INTO v_choice_id;

        FOR v_qrec IN SELECT * FROM jsonb_array_elements(v_quota_list) LOOP
            INSERT INTO choice_quota (choice_id, quota_code, ref_id)
            VALUES (v_choice_id, v_qrec ->> 'quota_code', v_qrec ->> 'ref_id');
        END LOOP;
    END LOOP;
END;
$$;

-- Queue a deletion request (applicant-initiated, master-admin approved).
CREATE OR REPLACE PROCEDURE sp_request_deletion(
    p_application_id TEXT,
    p_reason         TEXT,
    INOUT p_request_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM application WHERE application_id = p_application_id) THEN
        RAISE EXCEPTION 'Application % not found', p_application_id USING ERRCODE = '23503';
    END IF;
    INSERT INTO deletion_request (application_id, reason)
    VALUES (p_application_id, p_reason)
    RETURNING request_id INTO p_request_id;
END;
$$;

-- Pay the application fee (mock gateway). Idempotency: paying twice raises.
CREATE OR REPLACE PROCEDURE sp_pay_fee(
    p_application_id TEXT,
    p_method         TEXT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE payment
       SET status = 'PAID', method = p_method, paid_at = now()
     WHERE application_id = p_application_id AND status = 'PENDING';
    IF NOT FOUND THEN
        IF EXISTS (SELECT 1 FROM payment WHERE application_id = p_application_id) THEN
            RAISE EXCEPTION 'Fee already paid for %', p_application_id USING ERRCODE = '23505';
        ELSE
            RAISE EXCEPTION 'Application % not found', p_application_id USING ERRCODE = '23503';
        END IF;
    END IF;
END;
$$;

-- NOTE: approving/rejecting a deletion request (sp_approve_deletion) and running
-- the seat-allocation lottery belong to the separate school-authority/admin
-- system and are intentionally NOT part of this applicant project. The applicant
-- can only *raise* a deletion request (sp_request_deletion, above); the admin
-- system decides it.
