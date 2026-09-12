-- 012_add_status_enums.sql
-- Migration to add admission lifecycle status enum and columns.
-- Fully idempotent: safe to run multiple times.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'admission_lifecycle_status_t') THEN
        CREATE TYPE admission_lifecycle_status_t AS ENUM (
            'ALLOTTED',
            'WAITLISTED',
            'ENROLLED',
            'FORFEITED',
            'DISQUALIFIED',
            'UPGRADED'
        );
    END IF;
END $$;

-- lifecycle_status on application tracks post-lottery state (default WAITLISTED until lottery runs)
ALTER TABLE IF EXISTS application
    ADD COLUMN IF NOT EXISTS lifecycle_status admission_lifecycle_status_t NOT NULL DEFAULT 'WAITLISTED';

-- lifecycle_status on admission_result tracks what happened after the result was issued
ALTER TABLE IF EXISTS admission_result
    ADD COLUMN IF NOT EXISTS lifecycle_status admission_lifecycle_status_t NOT NULL DEFAULT 'ALLOTTED';

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_application_lifecycle_status        ON application(lifecycle_status);
CREATE INDEX IF NOT EXISTS idx_admission_result_lifecycle_status   ON admission_result(lifecycle_status);
