-- ============================================================================
-- 010_school_type.sql
-- Government vs non-government track (mirrors the real GSA portal, which keeps
-- separate result-search and authority-login entries for each track).
-- Existing schools default to GOVERNMENT; seeds/08 adds NON_GOVERNMENT ones.
-- ============================================================================

ALTER TABLE school
    ADD COLUMN IF NOT EXISTS school_type VARCHAR(15) NOT NULL DEFAULT 'GOVERNMENT'
        CHECK (school_type IN ('GOVERNMENT', 'NON_GOVERNMENT'));

CREATE INDEX IF NOT EXISTS idx_school_type ON school(school_type);
