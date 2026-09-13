-- ============================================================================
-- 015_enrollment.sql
-- Post-lottery enrollment. A lottery admission only HOLDS a seat: the student
-- still has to hand their certificates to the school, and the school authority
-- then confirms the admission (lifecycle ENROLLED). The master admin sets one
-- certificate deadline for every school (app_setting ENROLL_DEADLINE). Once it
-- has passed, the next lottery round forfeits every admission still unconfirmed
-- and hands those seats to the waiting list (see procedures/03_lottery.sql).
-- Re-runnable.
-- ============================================================================

-- When the school confirmed the admission (NULL until then).
ALTER TABLE admission_result ADD COLUMN IF NOT EXISTS enrolled_at TIMESTAMPTZ;

-- Waiting-list position: drawn once, the first time an application enters a
-- lottery, and kept for every later round.
ALTER TABLE application ADD COLUMN IF NOT EXISTS lottery_rank INT;
