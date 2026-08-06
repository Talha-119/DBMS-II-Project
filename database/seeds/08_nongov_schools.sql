-- ============================================================================
-- seeds/08_nongov_schools.sql
-- Non-government (private) track schools, mirroring the portal's second track.
-- EIIN range 2xxxxx to keep them visually distinct from the government schools.
-- Each gets seats (split across quotas by sp_add_seat) and an authority login
-- (login = EIIN, password "school123", same as the government demo logins).
-- ============================================================================

INSERT INTO school (eiin, name, postcode, school_gender, school_type) VALUES
    ('200005', 'Ideal School & College',            '1000', 'BOTH',   'NON_GOVERNMENT'),
    ('200002', 'Monipur High School & College',     '1206', 'BOTH',   'NON_GOVERNMENT'),
    ('200003', 'Holy Cross Girls'' High School',    '1212', 'FEMALE', 'NON_GOVERNMENT'),
    ('200004', 'St. Joseph Higher Secondary School','1217', 'MALE',   'NON_GOVERNMENT')
ON CONFLICT (eiin) DO NOTHING;

DO $$
DECLARE v_seat TEXT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM seat WHERE eiin = '200005') THEN
        CALL sp_add_seat('200005', 1, 'MORNING', 'BOTH',   15, v_seat);
        CALL sp_add_seat('200005', 3, 'DAY',     'BOTH',   15, v_seat);
        CALL sp_add_seat('200005', 6, 'DAY',     'BOTH',   15, v_seat);
        CALL sp_add_seat('200005', 9, 'DAY',     'BOTH',   10, v_seat);
        CALL sp_add_seat('200002', 3, 'DAY',     'BOTH',   20, v_seat);
        CALL sp_add_seat('200002', 6, 'DAY',     'BOTH',   20, v_seat);
        CALL sp_add_seat('200003', 3, 'DAY',     'FEMALE', 12, v_seat);
        CALL sp_add_seat('200003', 6, 'DAY',     'FEMALE', 12, v_seat);
        CALL sp_add_seat('200004', 6, 'DAY',     'MALE',   12, v_seat);
        CALL sp_add_seat('200004', 9, 'DAY',     'MALE',   12, v_seat);
    END IF;
END $$;

INSERT INTO account (role, login_id, password_hash, eiin, must_change_password)
VALUES
    ('SCHOOL_AUTHORITY', '200005', fn_hash_password('school123'), '200005', FALSE),
    ('SCHOOL_AUTHORITY', '200002', fn_hash_password('school123'), '200002', FALSE),
    ('SCHOOL_AUTHORITY', '200003', fn_hash_password('school123'), '200003', FALSE),
    ('SCHOOL_AUTHORITY', '200004', fn_hash_password('school123'), '200004', FALSE)
ON CONFLICT (login_id) DO NOTHING;

-- These EIINs sit at the start of seq_eiin's range (used by sp_add_school for
-- admin-created schools), so advance the sequence past them to avoid collisions.
DO $$
BEGIN
    IF (SELECT last_value FROM seq_eiin) < 200005 THEN
        PERFORM setval('seq_eiin', 200005, true);
    END IF;
END $$;
