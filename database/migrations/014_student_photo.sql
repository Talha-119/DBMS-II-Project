-- ============================================================================
-- 014_student_photo.sql
-- BUG-005: gives `student` a passport photograph column.
--
-- 004_application.sql already declares the new shape, so on a freshly built
-- database this file is a no-op. It exists for databases created before the
-- change; every step is guarded, so running it repeatedly (as migrate.js does)
-- is safe.
--
-- Nothing is backfilled and nothing is made NOT NULL: there is no registry of
-- photographs to backfill FROM, and every student row that predates this column
-- was accepted without one. Applications filed from now on carry a photo when
-- the applicant uploads one; the column stays nullable so the ones already on
-- file remain valid.
--
-- The format rule (real JPEG bytes) is a trigger rather than a CHECK because it
-- calls fn_is_jpeg, and migrate.js runs migrations/ before functions/ — the
-- function does not exist yet at this point. See functions/01_validation.sql
-- and triggers/02_rules.sql. The size rule needs no function, so it is a plain
-- CHECK here.
-- ============================================================================

ALTER TABLE student ADD COLUMN IF NOT EXISTS photo BYTEA;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
         WHERE conrelid = 'student'::regclass
           AND conname  = 'chk_student_photo_size'
    ) THEN
        ALTER TABLE student
            ADD CONSTRAINT chk_student_photo_size
            CHECK (photo IS NULL OR octet_length(photo) BETWEEN 100 AND 524288);
        RAISE NOTICE 'student.photo added (BYTEA, <= 512KB, JPEG enforced by trigger).';
    END IF;
END $$;
