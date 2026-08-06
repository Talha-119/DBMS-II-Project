-- ============================================================================
-- migrations/011_school_class_eligibility.sql
-- Per-school age windows.
--
-- class_eligibility stays the NATIONAL baseline: it is the FK anchor for both
-- seat.class_level and application.desired_class, so it must keep one row per
-- offered class. This table lets an individual school NARROW that window for
-- its own intake (its own admission criteria). A school with no row here simply
-- uses the national window.
--
-- A school window may never be WIDER than the national one — otherwise a school
-- could accept a student that sp_submit_application already rejected at the
-- application level. That containment rule is enforced by a trigger in
-- triggers/02_rules.sql (it needs a cross-row lookup, so it can't be a CHECK).
-- ============================================================================

CREATE TABLE IF NOT EXISTS school_class_eligibility (
    eiin        VARCHAR(10) NOT NULL REFERENCES school(eiin) ON DELETE CASCADE,
    class_level INT         NOT NULL REFERENCES class_eligibility(class_level) ON DELETE CASCADE,
    min_dob     DATE        NOT NULL,
    max_dob     DATE        NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (eiin, class_level),
    CHECK (min_dob <= max_dob)
);

CREATE INDEX IF NOT EXISTS idx_school_class_elig_eiin ON school_class_eligibility (eiin);
