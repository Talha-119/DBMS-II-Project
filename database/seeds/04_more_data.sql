-- ============================================================================
-- seeds/04_more_data.sql
-- Extra demo data: a new area (Gulshan), more registry rows, more birth
-- certificates, and one more school with seats. Order respects FKs
-- (postcode -> nid -> birth_certificate -> school -> seat). Seats use the same
-- inline, data-driven quota split as 02 (no admin procedure). No login accounts
-- are created here -- staff accounts belong to the separate admin system.
-- ============================================================================

INSERT INTO postcode (postcode, division, district, thana) VALUES
    ('1212', 'DHAKA', 'DHAKA', 'GULSHAN')
ON CONFLICT (postcode) DO NOTHING;

INSERT INTO nid (nid, name) VALUES
    ('19910000000000013', 'MD. FORHAD HOSSAIN'),
    ('19910000000000014', 'MD. ANISUR RAHMAN'),
    ('19910000000000015', 'MD. BELAL HOSSAIN'),
    ('19910000000000016', 'MD. JASIM UDDIN'),
    ('19920000000000013', 'TAHMINA AKTER'),
    ('19920000000000014', 'SULTANA RAZIA'),
    ('19920000000000015', 'KHADIJA BEGUM'),
    ('19920000000000016', 'ROKSANA PARVIN')
ON CONFLICT (nid) DO NOTHING;

INSERT INTO birth_certificate (bc_no, name, dob, father_name, mother_name, gender, postcode) VALUES
    ('BC3013', 'IMRAN KHAN',    DATE '2018-05-05', 'MD. FORHAD HOSSAIN', 'TAHMINA AKTER',  'MALE',   '1212'),
    ('BC3014', 'AYESHA SIDDIKA',DATE '2017-06-06', 'MD. ANISUR RAHMAN',  'SULTANA RAZIA',  'FEMALE', '1212'),
    ('BC3015', 'NABIL AHMED',   DATE '2015-07-07', 'MD. BELAL HOSSAIN',  'KHADIJA BEGUM',  'MALE',   '1212'),
    ('BC3016', 'MARIA ISLAM',   DATE '2019-08-08', 'MD. JASIM UDDIN',    'ROKSANA PARVIN', 'FEMALE', '1212')
ON CONFLICT (bc_no) DO NOTHING;

INSERT INTO school (eiin, name, postcode, school_gender) VALUES
    ('108301', 'Gulshan Model School & College', '1212', 'BOTH')
ON CONFLICT (eiin) DO NOTHING;

DO $$
DECLARE
    r       RECORD;
    v_seat  TEXT;
    v_total INT;
BEGIN
    FOR r IN
        SELECT * FROM (VALUES
            ('108301', 1, 'MORNING'::shift_t, 'BOTH'::seat_gender_t, 10),
            ('108301', 3, 'DAY',     'BOTH', 12),
            ('108301', 6, 'DAY',     'BOTH', 10)
        ) AS t(eiin, class_level, shift, seat_gender, total)
    LOOP
        v_total := r.total;
        v_seat  := 'S-' || lpad(nextval('seq_seat')::TEXT, 8, '0');

        INSERT INTO seat (seat_id, eiin, class_level, shift, seat_gender)
        VALUES (v_seat, r.eiin, r.class_level, r.shift, r.seat_gender)
        ON CONFLICT (eiin, class_level, shift, seat_gender) DO NOTHING;

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
