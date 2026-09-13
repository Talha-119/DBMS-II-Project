-- ============================================================================
-- triggers/02_rules.sql
-- Business-rule triggers: protect the immutable registries, cap choices at 5,
-- and keep student.updated_at fresh.
-- ============================================================================

-- The reference registries are authoritative and must never be edited/removed by
-- the application. Inserts (seeding) are allowed; UPDATE/DELETE are blocked.
CREATE OR REPLACE FUNCTION trg_fn_protect_registry()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'Table % is a read-only registry; % is not allowed', TG_TABLE_NAME, TG_OP
        USING ERRCODE = '42501';
END;
$$;

CREATE OR REPLACE TRIGGER trg_protect_birth_certificate
    BEFORE UPDATE OR DELETE ON birth_certificate
    FOR EACH ROW EXECUTE FUNCTION trg_fn_protect_registry();

CREATE OR REPLACE TRIGGER trg_protect_nid
    BEFORE UPDATE OR DELETE ON nid
    FOR EACH ROW EXECUTE FUNCTION trg_fn_protect_registry();

CREATE OR REPLACE TRIGGER trg_protect_postcode
    BEFORE UPDATE OR DELETE ON postcode
    FOR EACH ROW EXECUTE FUNCTION trg_fn_protect_registry();

-- Hard cap of 5 choices per application (a row count can't be a CHECK constraint).
CREATE OR REPLACE FUNCTION trg_fn_choice_max_five()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF (SELECT count(*) FROM application_choice WHERE application_id = NEW.application_id) >= 5 THEN
        RAISE EXCEPTION 'An application can have at most 5 choices' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_choice_max_five
    BEFORE INSERT ON application_choice
    FOR EACH ROW EXECUTE FUNCTION trg_fn_choice_max_five();

-- ============================================================================
-- Application rate limits. Both are row-count rules over a student's OTHER
-- applications, which a CHECK constraint cannot express, so they are triggers —
-- same reason as trg_choice_max_five above.
--
-- DELETED applications are excluded from both counts. That is the whole point of
-- the deletion cycle: an applicant who withdraws an application gets the slot
-- (and that area) back, exactly as if they had never filed it.
--
-- sp_submit_application inserts the application row, so these fire on the submit
-- path automatically; they also hold for direct SQL, which is why they are
-- triggers rather than checks inside the procedure.
-- ============================================================================

-- One application per area, per student. Without this, a student could file
-- application after application into the same postcode — each one drawing its own
-- lottery number for the same set of schools, which is exactly the spam this
-- forbids. Choices are already constrained to the applying area
-- (sp_submit_application step 7), so "one application per area" also means a
-- school can never be reached twice across two applications.
CREATE OR REPLACE FUNCTION trg_fn_application_postcode_once()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM application
        WHERE bc_no = NEW.bc_no
          AND applying_postcode = NEW.applying_postcode
          AND status <> 'DELETED'
          AND application_id IS DISTINCT FROM NEW.application_id
    ) THEN
        RAISE EXCEPTION
            'You already have an application in area %. One application per area is allowed — delete the existing one first if you want to re-apply there',
            NEW.applying_postcode
            USING ERRCODE = '23505';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_application_postcode_once
    BEFORE INSERT ON application
    FOR EACH ROW EXECUTE FUNCTION trg_fn_application_postcode_once();

-- Cap on live applications per student, default 3. Each application is an
-- independent entry in the draw (sp_run_lottery gives one random number per
-- application), so an uncapped student could simply buy more lottery tickets
-- than everyone else.
--
-- The cap is read from app_setting.MAX_APPLICATIONS rather than hardcoded, so
-- this trigger, /api/lookup/applicant-limits and the apply form all agree on one
-- number and an admin can retune it.
CREATE OR REPLACE FUNCTION trg_fn_application_max_three()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_live INT;
    v_max  INT;
BEGIN
    v_max := COALESCE(
        (SELECT value::INT FROM app_setting WHERE key = 'MAX_APPLICATIONS'), 3);

    SELECT count(*) INTO v_live
    FROM application
    WHERE bc_no = NEW.bc_no
      AND status <> 'DELETED'
      AND application_id IS DISTINCT FROM NEW.application_id;

    IF v_live >= v_max THEN
        RAISE EXCEPTION
            'A student may hold at most % applications (you already have %). Delete one before filing another',
            v_max, v_live
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_application_max_three
    BEFORE INSERT ON application
    FOR EACH ROW EXECUTE FUNCTION trg_fn_application_max_three();

-- One school per student, across every live application. sp_submit_application
-- checks this on the submit path with a school-named message; this is the
-- backstop for direct SQL, and it is stated at school (eiin) level rather than
-- seat level on purpose: a school can offer several seat rows for one class (one
-- per shift), so a seat-level rule let the same school be re-picked through a
-- different shift.
CREATE OR REPLACE FUNCTION trg_fn_choice_school_once()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_bc   VARCHAR(20);
    v_eiin VARCHAR(10);
BEGIN
    SELECT bc_no INTO v_bc FROM application WHERE application_id = NEW.application_id;
    SELECT eiin  INTO v_eiin FROM seat      WHERE seat_id = NEW.seat_id;

    IF EXISTS (
        SELECT 1
        FROM application_choice ac
        JOIN application a ON a.application_id = ac.application_id
        JOIN seat se       ON se.seat_id = ac.seat_id
        WHERE a.bc_no = v_bc
          AND a.status <> 'DELETED'
          AND se.eiin = v_eiin
          AND ac.choice_id IS DISTINCT FROM NEW.choice_id
    ) THEN
        RAISE EXCEPTION 'School % has already been chosen by student %', v_eiin, v_bc
            USING ERRCODE = '23505';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_choice_school_once
    BEFORE INSERT ON application_choice
    FOR EACH ROW EXECUTE FUNCTION trg_fn_choice_school_once();

-- A student profile is written once, by that student's first application, and is
-- immutable afterwards. sp_submit_application already refuses to change it on the
-- submit path; this trigger is the backstop, so the rule holds for direct SQL too
-- and not only for traffic that goes through the procedure.
--
-- Only the profile columns are frozen: created_at/updated_at stay writable so the
-- touch trigger below (which fires after this one — BEFORE ROW triggers run in
-- name order, and 'trg_s...' precedes 'trg_t...') is not blocked by it.
CREATE OR REPLACE FUNCTION trg_fn_student_profile_immutable()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.bc_no              IS DISTINCT FROM OLD.bc_no
       OR NEW.religion           IS DISTINCT FROM OLD.religion
       OR NEW.mobile             IS DISTINCT FROM OLD.mobile
       OR NEW.father_nid         IS DISTINCT FROM OLD.father_nid
       OR NEW.mother_nid         IS DISTINCT FROM OLD.mother_nid
       OR NEW.local_guardian_nid IS DISTINCT FROM OLD.local_guardian_nid
       OR NEW.present_postcode   IS DISTINCT FROM OLD.present_postcode
       OR NEW.present_detail     IS DISTINCT FROM OLD.present_detail
       OR NEW.permanent_postcode IS DISTINCT FROM OLD.permanent_postcode
       OR NEW.permanent_detail   IS DISTINCT FROM OLD.permanent_detail
       OR NEW.desired_class      IS DISTINCT FROM OLD.desired_class
       OR NEW.prev_school_name   IS DISTINCT FROM OLD.prev_school_name THEN
        RAISE EXCEPTION 'Student profile % is locked by their first application and cannot be modified', OLD.bc_no
            USING ERRCODE = '42501';
    END IF;

    -- The photograph is part of the same lock, with one carve-out: an EMPTY slot
    -- may still be filled. Every student who applied before the column existed
    -- has NULL there, and so does anyone who submitted without uploading one, so
    -- freezing NULL as hard as a real value would mean those applicants could
    -- never have a photo on their copy at all. Once a photo IS on file it is
    -- frozen exactly like the religion or the guardian NID beside it — otherwise
    -- a later application could swap the face on an identity document that
    -- earlier applications also print, which is the whole shape of BUG-001.
    --
    -- Clearing a photo back to NULL is a change like any other, so it is refused
    -- too: `IS DISTINCT FROM` covers non-NULL -> NULL.
    IF OLD.photo IS NOT NULL AND NEW.photo IS DISTINCT FROM OLD.photo THEN
        RAISE EXCEPTION 'The photograph on student profile % was set by an earlier application and cannot be replaced', OLD.bc_no
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_student_profile_immutable
    BEFORE UPDATE ON student
    FOR EACH ROW EXECUTE FUNCTION trg_fn_student_profile_immutable();

-- Whatever ends up in student.photo must actually be a JPEG. The upload route
-- re-encodes every accepted image before storing it, so this never fires on API
-- traffic; it is here so the guarantee survives a direct INSERT/UPDATE too. The
-- serving endpoint and the PDF both label those bytes image/jpeg without
-- inspecting them, and this is what earns them the right to.
--
-- A trigger rather than a CHECK constraint only because migrate.js creates
-- tables (migrations/) before functions/, so fn_is_jpeg does not exist yet when
-- `student` is built. The size bound, which needs no function, IS a CHECK on
-- the column (chk_student_photo_size).
CREATE OR REPLACE FUNCTION trg_fn_student_photo_is_jpeg()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT fn_is_jpeg(NEW.photo) THEN
        RAISE EXCEPTION 'student.photo must be JPEG image data (the bytes given for % are not)', NEW.bc_no
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_student_photo_is_jpeg
    BEFORE INSERT OR UPDATE ON student
    FOR EACH ROW EXECUTE FUNCTION trg_fn_student_photo_is_jpeg();

-- Touch student.updated_at on every update.
CREATE OR REPLACE FUNCTION trg_fn_touch_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_touch_student_updated_at
    BEFORE UPDATE ON student
    FOR EACH ROW EXECUTE FUNCTION trg_fn_touch_updated_at();

-- Auto-create a PENDING fee row whenever an application is submitted.
CREATE OR REPLACE FUNCTION trg_fn_create_payment()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO payment (application_id) VALUES (NEW.application_id)
    ON CONFLICT (application_id) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_create_payment
    AFTER INSERT ON application
    FOR EACH ROW EXECUTE FUNCTION trg_fn_create_payment();

-- A seat's gender must be compatible with its school's gender: a single-gender
-- school (MALE/FEMALE) may only offer seats of that gender; a co-ed school
-- (BOTH) may offer MALE, FEMALE or BOTH seats. Enforced in the DB so the seeded
-- seat catalogue stays consistent (and any future seat insert is guarded too).
CREATE OR REPLACE FUNCTION trg_fn_seat_gender_consistent()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_school_gender seat_gender_t;
BEGIN
    SELECT school_gender INTO v_school_gender FROM school WHERE eiin = NEW.eiin;
    IF v_school_gender <> 'BOTH' AND NEW.seat_gender <> v_school_gender THEN
        RAISE EXCEPTION '% seat is not allowed in a %-only school (%)',
            NEW.seat_gender, v_school_gender, NEW.eiin
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_seat_gender_consistent
    BEFORE INSERT OR UPDATE ON seat
    FOR EACH ROW EXECUTE FUNCTION trg_fn_seat_gender_consistent();
-- A school may narrow its own accepted date-of-birth window, never widen it.
-- sp_submit_application checks the national window first, so a school window
-- reaching outside it could never be satisfied anyway — reject it up front with
-- a clear message instead of silently accepting dead configuration.
CREATE OR REPLACE FUNCTION trg_fn_school_window_within_national()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_min DATE;
    v_max DATE;
BEGIN
    SELECT min_dob, max_dob INTO v_min, v_max
    FROM class_eligibility WHERE class_level = NEW.class_level;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Class % is not configured nationally', NEW.class_level
            USING ERRCODE = '23503';
    END IF;
    IF NEW.min_dob < v_min OR NEW.max_dob > v_max THEN
        RAISE EXCEPTION
            'School window %..% for class % is wider than the national window %..%; a school may only narrow it',
            NEW.min_dob, NEW.max_dob, NEW.class_level, v_min, v_max
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_school_window_within_national
    BEFORE INSERT OR UPDATE ON school_class_eligibility
    FOR EACH ROW EXECUTE FUNCTION trg_fn_school_window_within_national();
