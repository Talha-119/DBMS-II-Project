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
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_student_profile_immutable
    BEFORE UPDATE ON student
    FOR EACH ROW EXECUTE FUNCTION trg_fn_student_profile_immutable();

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
