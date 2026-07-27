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
