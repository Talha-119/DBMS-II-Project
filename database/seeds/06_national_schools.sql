-- ============================================================================
-- seeds/06_national_schools.sql
-- NATIONAL SCHOOL INVENTORY (the catalogue applicants across the country browse).
--
-- For every district Sadar seeded in 05, generate three government schools and
-- their seat inventory across all twelve classes:
--   * Government Boys' High School    -> classes 6-10 (MALE)
--   * Government Girls' High School   -> classes 6-10 (FEMALE)
--   * Government Model School&College -> classes 1-5 + 11-12 (BOTH)
--
-- Each seat's total is split across quota types by default_share (FF 20 / Area 10
-- / General 70), the catch-all (is_default) quota absorbing the remainder --
-- computed inline from quota_type, so no admin procedure is required. In the full
-- system schools/seats/authority-logins are created by the master-admin and
-- school-authority side; that side is NOT part of this applicant project, so no
-- login accounts are created here.
--
-- EIINs are minted from 110001 upward: clear of the curated Dhaka block
-- (108001-108301) so nothing collides.
-- ============================================================================

DO $$
DECLARE
    r            RECORD;
    spec         RECORD;
    v_n          INT  := 110000;   -- EIIN counter
    v_eiin_boys  TEXT;
    v_eiin_girls TEXT;
    v_eiin_model TEXT;
    v_seat       TEXT;
    v_total      INT;
BEGIN
    FOR r IN
        SELECT postcode, district
        FROM postcode
        WHERE thana LIKE '% SADAR'
        ORDER BY district
    LOOP
        v_n := v_n + 1; v_eiin_boys  := lpad(v_n::TEXT, 6, '0');
        v_n := v_n + 1; v_eiin_girls := lpad(v_n::TEXT, 6, '0');
        v_n := v_n + 1; v_eiin_model := lpad(v_n::TEXT, 6, '0');

        INSERT INTO school (eiin, name, postcode, school_gender) VALUES
            (v_eiin_boys,  initcap(r.district) || ' Government Boys'' High School',        r.postcode, 'MALE'),
            (v_eiin_girls, initcap(r.district) || ' Government Girls'' High School',       r.postcode, 'FEMALE'),
            (v_eiin_model, initcap(r.district) || ' Government Model School & College',    r.postcode, 'BOTH')
        ON CONFLICT (eiin) DO NOTHING;

        -- All seats for this district's three schools in one pass.
        FOR spec IN
            SELECT * FROM (VALUES
                -- Boys' High School: classes 6-10 (MALE, 50 each)
                (v_eiin_boys,  6, 'DAY'::shift_t, 'MALE'::seat_gender_t, 50),
                (v_eiin_boys,  7, 'DAY', 'MALE', 50),
                (v_eiin_boys,  8, 'DAY', 'MALE', 50),
                (v_eiin_boys,  9, 'DAY', 'MALE', 50),
                (v_eiin_boys, 10, 'DAY', 'MALE', 50),
                -- Girls' High School: classes 6-10 (FEMALE, 50 each)
                (v_eiin_girls,  6, 'DAY', 'FEMALE', 50),
                (v_eiin_girls,  7, 'DAY', 'FEMALE', 50),
                (v_eiin_girls,  8, 'DAY', 'FEMALE', 50),
                (v_eiin_girls,  9, 'DAY', 'FEMALE', 50),
                (v_eiin_girls, 10, 'DAY', 'FEMALE', 50),
                -- Model School & College: classes 1-5 + 11-12 (BOTH, 40 each)
                (v_eiin_model,  1, 'MORNING', 'BOTH', 40),
                (v_eiin_model,  2, 'DAY', 'BOTH', 40),
                (v_eiin_model,  3, 'DAY', 'BOTH', 40),
                (v_eiin_model,  4, 'DAY', 'BOTH', 40),
                (v_eiin_model,  5, 'DAY', 'BOTH', 40),
                (v_eiin_model, 11, 'DAY', 'BOTH', 40),
                (v_eiin_model, 12, 'DAY', 'BOTH', 40)
            ) AS t(eiin, class_level, shift, seat_gender, total)
        LOOP
            v_total := spec.total;
            v_seat  := 'S-' || lpad(nextval('seq_seat')::TEXT, 8, '0');

            INSERT INTO seat (seat_id, eiin, class_level, shift, seat_gender)
            VALUES (v_seat, spec.eiin, spec.class_level, spec.shift, spec.seat_gender)
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
    END LOOP;
END $$;
