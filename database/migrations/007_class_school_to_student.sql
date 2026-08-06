-- ============================================================================
-- 007_class_school_to_student.sql
-- Moves desired_class + prev_school_name from `application` onto `student`.
--
-- Rationale is in 004_application.sql: both are functionally dependent on the
-- student rather than on the individual application, and holding them per
-- application let one child file for two different classes across two areas.
--
-- 004 already declares the new shape, so on a freshly built database this file
-- is a no-op. It exists for databases created before the change: every step is
-- guarded, so running it repeatedly (as migrate.js does) is safe.
-- ============================================================================

-- 1. Add the columns to student, initially nullable so existing rows can be
--    backfilled before the NOT NULL is applied.
ALTER TABLE student ADD COLUMN IF NOT EXISTS desired_class    INT;
ALTER TABLE student ADD COLUMN IF NOT EXISTS prev_school_name VARCHAR(120);

DO $$
BEGIN
    -- 2. Backfill from each student's EARLIEST application, then drop the old
    --    columns. Only runs while `application` still carries them.
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'application' AND column_name = 'desired_class'
    ) THEN
        -- A student with two applications that disagree is exactly the defect
        -- being closed; the first application wins, matching "the first
        -- submission fixes the profile" everywhere else.
        UPDATE student s
           SET desired_class    = a.desired_class,
               prev_school_name = a.prev_school_name
          FROM (
            SELECT DISTINCT ON (bc_no) bc_no, desired_class, prev_school_name
              FROM application
             ORDER BY bc_no, submitted_at, application_id
          ) a
         WHERE a.bc_no = s.bc_no;

        -- vw_applicant_copy still selects these from `application`, which blocks
        -- the DROP. views/01_views.sql runs after every migration and rebuilds it
        -- reading from `student` instead.
        EXECUTE 'DROP VIEW IF EXISTS vw_applicant_copy';

        ALTER TABLE application DROP COLUMN desired_class;
        ALTER TABLE application DROP COLUMN prev_school_name;

        RAISE NOTICE 'Moved desired_class/prev_school_name onto student.';
    END IF;

    -- 3. Constraints, once the data is in place. Guarded so a re-run is a no-op.
    IF EXISTS (SELECT 1 FROM student WHERE desired_class IS NULL) THEN
        -- Only reachable if a student row somehow has no application to inherit
        -- from; leave it nullable rather than failing the whole migration.
        RAISE WARNING 'student rows with NULL desired_class remain; NOT NULL not applied.';
    ELSE
        ALTER TABLE student ALTER COLUMN desired_class SET NOT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE table_name = 'student' AND constraint_name = 'student_desired_class_fkey'
    ) THEN
        ALTER TABLE student
            ADD CONSTRAINT student_desired_class_fkey
            FOREIGN KEY (desired_class) REFERENCES class_eligibility(class_level);
    END IF;
END $$;
