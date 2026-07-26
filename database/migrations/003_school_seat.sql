-- ============================================================================
-- 003_school_seat.sql
-- Schools and their seat inventory. Seats are a (school, class, shift, gender)
-- combination; capacity is broken down per quota in a junction table so new
-- quota types need NO schema change (extensibility) and the lottery can iterate
-- quotas generically by priority.
-- ============================================================================

-- Sequences used to mint human-readable EIINs and seat IDs (see Phase 2 procs).
-- seq_eiin starts at 200001 so generated EIINs never collide with the seeded
-- real-school EIINs (108001-108207).
CREATE SEQUENCE IF NOT EXISTS seq_eiin START WITH 200001;
CREATE SEQUENCE IF NOT EXISTS seq_seat START WITH 1;

CREATE TABLE IF NOT EXISTS school (
    eiin          VARCHAR(10)   PRIMARY KEY CHECK (eiin ~ '^[0-9]{6}$'),
    name          VARCHAR(120)  NOT NULL,
    postcode      CHAR(4)       NOT NULL REFERENCES postcode(postcode),
    school_gender seat_gender_t NOT NULL DEFAULT 'BOTH'
);

-- One seat row = one (school, class, shift, seat-gender) combination.
CREATE TABLE IF NOT EXISTS seat (
    seat_id     VARCHAR(20)   PRIMARY KEY,
    eiin        VARCHAR(10)   NOT NULL REFERENCES school(eiin) ON DELETE CASCADE,
    class_level INT           NOT NULL REFERENCES class_eligibility(class_level),
    shift       shift_t       NOT NULL,
    seat_gender seat_gender_t NOT NULL,
    UNIQUE (eiin, class_level, shift, seat_gender)
);

-- Capacity per quota for each seat row. capacity is the LIVE remaining count
-- (the lottery decrements it). PK(seat_id, quota_code) prevents duplicates.
CREATE TABLE IF NOT EXISTS seat_quota (
    seat_id    VARCHAR(20) NOT NULL REFERENCES seat(seat_id) ON DELETE CASCADE,
    quota_code VARCHAR(20) NOT NULL REFERENCES quota_type(code),
    capacity   INT         NOT NULL DEFAULT 0 CHECK (capacity >= 0),
    PRIMARY KEY (seat_id, quota_code)
);

CREATE INDEX IF NOT EXISTS idx_school_postcode ON school(postcode);
CREATE INDEX IF NOT EXISTS idx_seat_eiin       ON seat(eiin);
CREATE INDEX IF NOT EXISTS idx_seat_class      ON seat(class_level);
CREATE INDEX IF NOT EXISTS idx_seat_lookup     ON seat(class_level, seat_gender);
CREATE INDEX IF NOT EXISTS idx_seatquota_seat  ON seat_quota(seat_id);
