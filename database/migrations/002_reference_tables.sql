-- ============================================================================
-- 002_reference_tables.sql
-- Authoritative reference registries. These are the SOURCE OF TRUTH that the
-- application auto-fills from, so applicants never re-type identity data
-- (this is the core fix for the "info mismatch" problem of the real portal).
-- ============================================================================

-- Postcode -> administrative area. One postcode = one (division, district, thana).
CREATE TABLE IF NOT EXISTS postcode (
    postcode  CHAR(4)      PRIMARY KEY CHECK (postcode ~ '^[0-9]{4}$'),
    division  VARCHAR(50)  NOT NULL,
    district  VARCHAR(50)  NOT NULL,
    thana     VARCHAR(50)  NOT NULL
);

-- National birth-certificate registry. Auto-fills name/dob/gender/parents.
CREATE TABLE IF NOT EXISTS birth_certificate (
    bc_no        VARCHAR(20) PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    dob          DATE         NOT NULL,
    father_name  VARCHAR(100) NOT NULL,
    mother_name  VARCHAR(100) NOT NULL,
    gender       gender_t     NOT NULL,
    postcode     CHAR(4)      NOT NULL REFERENCES postcode(postcode)
);

-- National ID registry. Auto-fills/validates parent & guardian names.
CREATE TABLE IF NOT EXISTS nid (
    nid   VARCHAR(20)  PRIMARY KEY CHECK (nid ~ '^[0-9]{10,17}$'),
    name  VARCHAR(100) NOT NULL
);

-- Quota types kept as a LOOKUP TABLE (not a hard enum) so new quotas can be
-- added without a schema change. priority = allocation order (1 first).
-- default_share = fraction of a seat row's total capacity reserved for this
-- quota when a seat is created (e.g. FF 0.20, AREA 0.10, GENERAL 0.70). Making
-- this data-driven means new quotas auto-participate in seat splitting + lottery.
CREATE TABLE IF NOT EXISTS quota_type (
    code               VARCHAR(20) PRIMARY KEY,
    name               VARCHAR(60) NOT NULL,
    requires_reference BOOLEAN     NOT NULL DEFAULT FALSE,
    priority           INT         NOT NULL CHECK (priority > 0),
    default_share      NUMERIC(4,3) NOT NULL DEFAULT 0 CHECK (default_share >= 0 AND default_share <= 1),
    -- exactly one quota is the "catch-all" that absorbs the rounding remainder
    -- when a seat total is split (independent of priority). Usually GENERAL.
    is_default         BOOLEAN     NOT NULL DEFAULT FALSE
);

-- At most one default/catch-all quota.
CREATE UNIQUE INDEX IF NOT EXISTS uq_quota_default ON quota_type ((is_default)) WHERE is_default;

-- Proof references for quotas that require documentation (e.g. Freedom Fighter).
CREATE TABLE IF NOT EXISTS quota_reference (
    ref_id      VARCHAR(20) PRIMARY KEY,
    nid         VARCHAR(20) NOT NULL REFERENCES nid(nid),
    quota_code  VARCHAR(20) NOT NULL REFERENCES quota_type(code)
);

-- Age eligibility per class: a child is eligible for class C if their DOB is
-- within [min_dob, max_dob] for that class.
CREATE TABLE IF NOT EXISTS class_eligibility (
    class_level INT  PRIMARY KEY CHECK (class_level BETWEEN 1 AND 12),
    min_dob     DATE NOT NULL,
    max_dob     DATE NOT NULL,
    CHECK (min_dob <= max_dob)
);

-- Indexes for the cascading address dropdown (division -> district -> thana).
CREATE INDEX IF NOT EXISTS idx_postcode_division ON postcode(division);
CREATE INDEX IF NOT EXISTS idx_postcode_district ON postcode(district);
CREATE INDEX IF NOT EXISTS idx_quota_reference_nid ON quota_reference(nid);
