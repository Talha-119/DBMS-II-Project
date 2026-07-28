-- ============================================================================
-- seeds/02_schools_seats.sql
-- Real Dhaka schools + their seat inventory (the catalogue an applicant browses).
--
-- In the full system, schools/seats are created by the master-admin and school-
-- authority side. That side is NOT part of this applicant project, so here the
-- catalogue is seeded directly. Each seat's total capacity is split across the
-- configured quota types by their default_share (FF 20% / Area 10% / General 70%),
-- with the catch-all (is_default) quota absorbing the rounding remainder — the
-- same data-driven split the admin tools apply, computed inline from quota_type
-- so no admin procedure is needed.
-- ============================================================================

INSERT INTO school (eiin, name, postcode, school_gender) VALUES
    -- Cantonment (1206)
    ('108001', 'Adamjee Cantonment School',          '1206', 'BOTH'),
    ('108003', 'Shaheed Anwar Girls'' School',        '1206', 'FEMALE'),
    -- Motijheel (1000)
    ('108101', 'Motijheel Govt. Boys'' High School',  '1000', 'MALE'),
    ('108102', 'Motijheel Govt. Girls'' High School', '1000', 'FEMALE'),
    ('108103', 'Motijheel Model School & College',    '1000', 'BOTH'),
    -- Ramna (1217)
    ('108201', 'Viqarunnisa Noon School & College',   '1217', 'FEMALE'),
    ('108203', 'BIAM Model School & College',         '1217', 'BOTH')
ON CONFLICT (eiin) DO NOTHING;

-- Seats + per-quota capacity. One row of the VALUES list = one seat
-- (school, class, shift, seat-gender, total capacity).
DO $$
DECLARE
    r       RECORD;
    v_seat  TEXT;
    v_total INT;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            -- Motijheel Model (BOTH)
            ('108103', 1, 'MORNING'::shift_t, 'BOTH'::seat_gender_t, 10),
            ('108103', 3, 'DAY',     'BOTH',   12),
            ('108103', 6, 'DAY',     'BOTH',   10),
            ('108103', 9, 'DAY',     'BOTH',   10),
            -- Motijheel Boys (MALE)
            ('108101', 3, 'DAY',     'MALE',   10),
            ('108101', 6, 'DAY',     'MALE',   10),
            -- Motijheel Girls (FEMALE)
            ('108102', 3, 'DAY',     'FEMALE', 10),
            ('108102', 6, 'DAY',     'FEMALE', 10),
            -- Adamjee Cantonment (BOTH)
            ('108001', 3, 'DAY',     'BOTH',   10),
            ('108001', 6, 'MORNING', 'BOTH',   10),
            ('108001', 9, 'DAY',     'BOTH',   10),
            -- Shaheed Anwar Girls' (FEMALE)
            ('108003', 3, 'DAY',     'FEMALE', 10),
            -- Viqarunnisa (FEMALE)
            ('108201', 3, 'DAY',     'FEMALE', 10),
            ('108201', 6, 'DAY',     'FEMALE', 10),
            ('108201', 9, 'DAY',     'FEMALE', 10),
            -- BIAM Model (BOTH)
            ('108203', 1, 'MORNING', 'BOTH',   10),
            ('108203', 3, 'DAY',     'BOTH',   10)
        ) AS t(eiin, class_level, shift, seat_gender, total)
    LOOP
        v_total := r.total;
        v_seat  := 'S-' || lpad(nextval('seq_seat')::TEXT, 8, '0');

        INSERT INTO seat (seat_id, eiin, class_level, shift, seat_gender)
        VALUES (v_seat, r.eiin, r.class_level, r.shift, r.seat_gender)
        ON CONFLICT (eiin, class_level, shift, seat_gender) DO NOTHING;

        -- If the seat already existed (idempotent re-run), skip its quota split.
        CONTINUE WHEN NOT EXISTS (SELECT 1 FROM seat WHERE seat_id = v_seat);

        INSERT INTO seat_quota (seat_id, quota_code, capacity)
        SELECT v_seat, qt.code,
               CASE WHEN qt.is_default
                    THEN v_total - COALESCE(
                             (SELECT SUM(floor(v_total * q2.default_share))::INT
                                FROM quota_type q2 WHERE NOT q2.is_default), 0)
                    ELSE floor(v_total * qt.default_share)::INT
               END
        FROM quota_type qt;
    END LOOP;
END $$;
