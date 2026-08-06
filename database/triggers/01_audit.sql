-- ============================================================================
-- triggers/01_audit.sql
-- A single generic trigger function writes a full before/after audit trail for
-- every change on the important tables, using TG_OP + to_jsonb (no per-table code).
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_fn_audit()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), NULL);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, action, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSE  -- INSERT
        INSERT INTO audit_log (table_name, action, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, NULL, to_jsonb(NEW));
        RETURN NEW;
    END IF;
END;
$$;

CREATE OR REPLACE TRIGGER trg_audit_application
    AFTER INSERT OR UPDATE OR DELETE ON application
    FOR EACH ROW EXECUTE FUNCTION trg_fn_audit();

CREATE OR REPLACE TRIGGER trg_audit_student
    AFTER INSERT OR UPDATE OR DELETE ON student
    FOR EACH ROW EXECUTE FUNCTION trg_fn_audit();

CREATE OR REPLACE TRIGGER trg_audit_application_choice
    AFTER INSERT OR UPDATE OR DELETE ON application_choice
    FOR EACH ROW EXECUTE FUNCTION trg_fn_audit();

CREATE OR REPLACE TRIGGER trg_audit_seat_quota
    AFTER INSERT OR UPDATE OR DELETE ON seat_quota
    FOR EACH ROW EXECUTE FUNCTION trg_fn_audit();

CREATE OR REPLACE TRIGGER trg_audit_admission_result
    AFTER INSERT OR UPDATE OR DELETE ON admission_result
    FOR EACH ROW EXECUTE FUNCTION trg_fn_audit();

CREATE OR REPLACE TRIGGER trg_audit_school
    AFTER INSERT OR UPDATE OR DELETE ON school
    FOR EACH ROW EXECUTE FUNCTION trg_fn_audit();
