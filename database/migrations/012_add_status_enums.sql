-- 012_add_status_enums.sql
-- Migration to add admission lifecycle status enum and columns to application and admission_result tables.

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

-- Add lifecycle_status column to application (default ALLOTTED)
ALTER TABLE IF EXISTS application
    ADD COLUMN IF NOT EXISTS lifecycle_status admission_lifecycle_status_t NOT NULL DEFAULT 'ALLOTTED';

-- Add lifecycle_status column to admission_result (default ALLOTTED)
ALTER TABLE IF EXISTS admission_result
    ADD COLUMN IF NOT EXISTS lifecycle_status admission_lifecycle_status_t NOT NULL DEFAULT 'ALLOTTED';

-- Indexes for quick lookup
CREATE INDEX IF NOT EXISTS idx_application_lifecycle_status ON application(lifecycle_status);
CREATE INDEX IF NOT EXISTS idx_admission_result_lifecycle_status ON admission_result(lifecycle_status);
