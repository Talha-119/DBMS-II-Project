-- ============================================================================
-- 001_extensions_enums.sql
-- Extensions + enumerated domain types.
-- Re-runnable: guarded with IF NOT EXISTS / pg_type checks.
-- ============================================================================

-- pgcrypto: gen_random_uuid(), digest() for hashing OTP codes inside the DB.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Enum types ---------------------------------------------------------------

-- Student / person gender.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'gender_t') THEN
        CREATE TYPE gender_t AS ENUM ('MALE', 'FEMALE', 'OTHER');
    END IF;
END $$;

-- School / seat gender (a school or seat can serve BOTH).
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'seat_gender_t') THEN
        CREATE TYPE seat_gender_t AS ENUM ('MALE', 'FEMALE', 'BOTH');
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'shift_t') THEN
        CREATE TYPE shift_t AS ENUM ('MORNING', 'DAY');
    END IF;
END $$;

DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'religion_t') THEN
        CREATE TYPE religion_t AS ENUM ('ISLAM', 'HINDU', 'CHRISTIAN', 'BUDDHIST', 'OTHER');
    END IF;
END $$;

-- Lifecycle of an application.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'application_status_t') THEN
        CREATE TYPE application_status_t AS ENUM
            ('SUBMITTED', 'CANCELLED', 'ADMITTED', 'WAITING', 'NOT_ADMITTED');
    END IF;
END $$;

-- Outcome of the lottery for one application.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'result_status_t') THEN
        CREATE TYPE result_status_t AS ENUM ('ADMITTED', 'WAITING', 'NOT_ADMITTED');
    END IF;
END $$;

-- Login roles (applicants are account-less, so they are NOT here).
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'account_role_t') THEN
        CREATE TYPE account_role_t AS ENUM ('SCHOOL_AUTHORITY', 'MASTER_ADMIN');
    END IF;
END $$;

-- Deletion-request workflow (applicant requests, master admin decides).
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'deletion_status_t') THEN
        CREATE TYPE deletion_status_t AS ENUM ('PENDING', 'APPROVED', 'REJECTED');
    END IF;
END $$;
