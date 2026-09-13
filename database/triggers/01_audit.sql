-- ============================================================================
-- triggers/01_audit.sql
-- A single generic trigger function writes a full before/after audit trail for
-- every change on the important tables, using TG_OP + to_jsonb (no per-table code).
-- ============================================================================

-- Binary columns are summarised, never copied. audit_log keeps a full
-- before/after image of every audited row, and to_jsonb() renders a BYTEA as a
-- hex string twice its byte size -- so student.photo would put ~60KB of text in
-- new_data on every INSERT and both halves of every UPDATE, for a photograph the
-- audit trail has no use for. Worse, it would leave copies of the image in a
-- table nothing ever prunes, outliving any removal from `student`.
--
-- What an audit needs is whether the photograph was set or replaced and how big
-- it was, which the marker below records. Written as a generic key rewrite so
-- trg_fn_audit stays the one table-agnostic function it was designed to be.
CREATE OR REPLACE FUNCTION fn_audit_payload(p_row JSONB)
RETURNS JSONB
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    v_hex TEXT;
BEGIN
    IF p_row IS NULL OR NOT (p_row ? 'photo') THEN
        RETURN p_row;
    END IF;
    IF jsonb_typeof(p_row -> 'photo') <> 'string' THEN
        RETURN p_row;                              -- NULL photo: nothing to hide
    END IF;
    v_hex := p_row ->> 'photo';
    -- Default bytea_output is 'hex', rendering as '\xDEADBEEF' -- two leading
    -- characters, then two per byte. Under 'escape' the length is not a byte
    -- count, so the marker just omits the size rather than reporting a wrong one.
    RETURN jsonb_set(p_row, '{photo}', to_jsonb(
        CASE WHEN left(v_hex, 2) = '\x'
             THEN '<image data, ' || ((length(v_hex) - 2) / 2)::TEXT || ' bytes>'
             ELSE '<image data>'
        END));
END;
$$;

CREATE OR REPLACE FUNCTION trg_fn_audit()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, fn_audit_payload(to_jsonb(OLD)), NULL);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, action, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, fn_audit_payload(to_jsonb(OLD)), fn_audit_payload(to_jsonb(NEW)));
        RETURN NEW;
    ELSE  -- INSERT
        INSERT INTO audit_log (table_name, action, old_data, new_data)
        VALUES (TG_TABLE_NAME, TG_OP, NULL, fn_audit_payload(to_jsonb(NEW)));
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
