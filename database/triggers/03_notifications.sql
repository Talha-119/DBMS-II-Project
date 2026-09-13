-- ============================================================================
-- triggers/03_notifications.sql
-- Automatic side of the notification system. Each trigger fires off the same
-- row-level events the rest of the schema already treats as meaningful
-- (trg_create_payment on application insert, the audit triggers on every
-- write) and calls fn_create_notification() instead of writing its own INSERT,
-- the same way every audit trigger shares trg_fn_audit().
-- ============================================================================

-- 1. Applicant: application submitted. -----------------------------------
CREATE OR REPLACE FUNCTION trg_fn_notify_application_submitted()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_class INT;
BEGIN
    SELECT desired_class INTO v_class FROM student WHERE bc_no = NEW.bc_no;
    PERFORM fn_create_notification(
        'APPLICANT', NEW.bc_no, NULL, NEW.application_id,
        'APPLICATION_SUBMITTED', 'Application submitted',
        'Application ' || NEW.application_id || ' for class ' || COALESCE(v_class::TEXT, '—') ||
        ' was received and is awaiting the draw.'
    );
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_notify_application_submitted
    AFTER INSERT ON application
    FOR EACH ROW EXECUTE FUNCTION trg_fn_notify_application_submitted();

-- 2. Applicant: fee paid. --------------------------------------------------
CREATE OR REPLACE FUNCTION trg_fn_notify_payment_paid()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_bc TEXT;
BEGIN
    IF NEW.status = 'PAID' AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'PAID') THEN
        SELECT bc_no INTO v_bc FROM application WHERE application_id = NEW.application_id;
        IF v_bc IS NOT NULL THEN
            PERFORM fn_create_notification(
                'APPLICANT', v_bc, NULL, NEW.application_id,
                'PAYMENT_RECEIVED', 'Application fee received',
                'Payment of ' || NEW.amount || ' for application ' || NEW.application_id || ' was recorded.'
            );
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_notify_payment_paid
    AFTER INSERT OR UPDATE ON payment
    FOR EACH ROW EXECUTE FUNCTION trg_fn_notify_payment_paid();

-- 3. Master admin: a deletion request needs review. ------------------------
CREATE OR REPLACE FUNCTION trg_fn_notify_deletion_requested()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_name TEXT;
BEGIN
    SELECT bc.name INTO v_name
      FROM application a JOIN birth_certificate bc ON bc.bc_no = a.bc_no
     WHERE a.application_id = NEW.application_id;
    PERFORM fn_create_notification(
        'MASTER_ADMIN', NULL, NULL, NEW.application_id,
        'DELETION_REQUESTED', 'Deletion request awaiting review',
        COALESCE(v_name, 'An applicant') || '''s application ' || NEW.application_id ||
        ' has a pending deletion request.'
    );
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_notify_deletion_requested
    AFTER INSERT ON deletion_request
    FOR EACH ROW EXECUTE FUNCTION trg_fn_notify_deletion_requested();

-- 4. School authority: a new applicant listed their school. -----------------
CREATE OR REPLACE FUNCTION trg_fn_notify_new_choice()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_eiin  TEXT;
    v_class INT;
    v_name  TEXT;
BEGIN
    SELECT se.eiin, se.class_level INTO v_eiin, v_class FROM seat se WHERE se.seat_id = NEW.seat_id;
    SELECT bc.name INTO v_name
      FROM application a JOIN birth_certificate bc ON bc.bc_no = a.bc_no
     WHERE a.application_id = NEW.application_id;
    PERFORM fn_create_notification(
        'SCHOOL_AUTHORITY', NULL, v_eiin, NEW.application_id,
        'NEW_APPLICANT', 'New applicant choice received',
        COALESCE(v_name, 'An applicant') || ' listed your school as preference ' || NEW.preference ||
        ' for class ' || v_class || ' on application ' || NEW.application_id || '.'
    );
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_notify_new_choice
    AFTER INSERT ON application_choice
    FOR EACH ROW EXECUTE FUNCTION trg_fn_notify_new_choice();

-- 5. School authority: the lottery filled one of their seats. ---------------
CREATE OR REPLACE FUNCTION trg_fn_notify_admitted()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_eiin  TEXT;
    v_class INT;
    v_shift TEXT;
    v_name  TEXT;
BEGIN
    IF NEW.status = 'ADMITTED' AND NEW.admitted_seat_id IS NOT NULL THEN
        SELECT se.eiin, se.class_level, se.shift::TEXT INTO v_eiin, v_class, v_shift
          FROM seat se WHERE se.seat_id = NEW.admitted_seat_id;
        SELECT bc.name INTO v_name
          FROM application a JOIN birth_certificate bc ON bc.bc_no = a.bc_no
         WHERE a.application_id = NEW.application_id;
        PERFORM fn_create_notification(
            'SCHOOL_AUTHORITY', NULL, v_eiin, NEW.application_id,
            'SEAT_FILLED', 'Seat filled by the lottery',
            COALESCE(v_name, 'An applicant') || ' was allotted a class ' || v_class || ' (' || v_shift ||
            ') seat under the ' || COALESCE(NEW.allocated_quota, '—') || ' quota.'
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_notify_admitted
    AFTER INSERT ON admission_result
    FOR EACH ROW EXECUTE FUNCTION trg_fn_notify_admitted();

-- 6. app_setting is a generic key/value table (ROUND_OPEN, RESULT_READY,
-- CURRENT_ROUND, ADMISSION_YEAR, ...), so ONE trigger inspects NEW.key rather
-- than adding a table per setting. It reacts to exactly the two keys whose
-- flip is itself the event applicants/admins care about; every other key is a
-- no-op pass-through.
CREATE OR REPLACE FUNCTION trg_fn_notify_app_setting()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_admitted INT;
    v_waiting  INT;
BEGIN
    -- 6a. Applicant: results just published (sp_publish_results). One
    -- notification per decided application, deep-linked to it.
    IF NEW.key = 'RESULT_READY' AND NEW.value = 'TRUE'
       AND (TG_OP = 'INSERT' OR OLD.value IS DISTINCT FROM 'TRUE') THEN
        INSERT INTO notification (audience, bc_no, application_id, type, title, body)
        SELECT 'APPLICANT', a.bc_no, a.application_id, 'RESULT_PUBLISHED',
               'Your admission result is ready',
               'The result for application ' || a.application_id ||
               ' has been published. Go to Download / Delete Application to check your status.'
          FROM admission_result r
          JOIN application a ON a.application_id = r.application_id;
    END IF;

    -- 6b. Master admin: a lottery round just finished (sp_run_lottery updates
    -- CURRENT_ROUND last, after every admission_result row for the round
    -- already exists), so the "Publish results" step isn't missed.
    IF NEW.key = 'CURRENT_ROUND' AND (TG_OP = 'INSERT' OR OLD.value IS DISTINCT FROM NEW.value) THEN
        SELECT count(*) FILTER (WHERE status = 'ADMITTED'),
               count(*) FILTER (WHERE status = 'WAITING')
          INTO v_admitted, v_waiting
          FROM admission_result WHERE round = NEW.value::INT;

        PERFORM fn_create_notification(
            'MASTER_ADMIN', NULL, NULL, NULL,
            'LOTTERY_RUN', 'Lottery round ' || NEW.value || ' completed',
            v_admitted || ' admitted, ' || v_waiting || ' waiting. Review the results, then publish when ready.'
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_notify_app_setting
    AFTER INSERT OR UPDATE ON app_setting
    FOR EACH ROW EXECUTE FUNCTION trg_fn_notify_app_setting();
