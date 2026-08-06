-- ============================================================================
-- integrity_checks.sql
-- Run with:  node database/migrate.js check     (or: npm run db:check)
--
-- Every rule this system claims to enforce, re-asserted as a query over the data
-- that is actually there. Constraints, triggers and procedures enforce these at
-- WRITE time; this file proves they held, and catches anything that arrived by
-- another route (direct SQL, a bad seed, a migration).
--
-- Contract with migrate.js: the LAST statement returns one row per check with
-- the columns (category, check_name, violations, status). Non-zero violations
-- make the command exit non-zero.
-- ============================================================================

WITH checks AS (

-- ---- Registry: parentage is a real, coherent identity ----------------------
SELECT 'registry' AS category, 'birth certificate parent NID exists in registry' AS check_name,
       count(*) AS violations
  FROM birth_certificate b
 WHERE NOT EXISTS (SELECT 1 FROM nid n WHERE n.nid = b.father_nid)
    OR NOT EXISTS (SELECT 1 FROM nid n WHERE n.nid = b.mother_nid)

UNION ALL
SELECT 'registry', 'father and mother are different people',
       count(*) FROM birth_certificate WHERE father_nid = mother_nid

UNION ALL
SELECT 'registry', 'no NID is recorded as both a father and a mother',
       (SELECT count(*) FROM (
          SELECT father_nid AS nid FROM birth_certificate
          INTERSECT SELECT mother_nid FROM birth_certificate) x)

-- A father appearing with two different mothers is legal in life but is almost
-- always a seeding accident here, so it is surfaced rather than ignored.
UNION ALL
SELECT 'registry', 'each father is paired with a single mother',
       (SELECT count(*) FROM (
          SELECT father_nid FROM birth_certificate
           GROUP BY father_nid HAVING count(DISTINCT mother_nid) > 1) x)

UNION ALL
SELECT 'registry', 'each mother is paired with a single father',
       (SELECT count(*) FROM (
          SELECT mother_nid FROM birth_certificate
           GROUP BY mother_nid HAVING count(DISTINCT father_nid) > 1) x)

-- ---- Guardian: BUG-002. A submitted parent NID must BE the recorded one -----
UNION ALL
SELECT 'guardian', 'student father NID matches the birth certificate',
       count(*) FROM student s JOIN birth_certificate b ON b.bc_no = s.bc_no
 WHERE s.father_nid IS NOT NULL AND s.father_nid <> b.father_nid

UNION ALL
SELECT 'guardian', 'student mother NID matches the birth certificate',
       count(*) FROM student s JOIN birth_certificate b ON b.bc_no = s.bc_no
 WHERE s.mother_nid IS NOT NULL AND s.mother_nid <> b.mother_nid

UNION ALL
SELECT 'guardian', 'every student has at least one guardian',
       count(*) FROM student
 WHERE father_nid IS NULL AND mother_nid IS NULL AND local_guardian_nid IS NULL

-- ---- Eligibility: the class a student applied for must suit their age -------
UNION ALL
SELECT 'eligibility', 'desired class is age-eligible for the student DOB',
       count(*) FROM student s JOIN birth_certificate b ON b.bc_no = s.bc_no
 WHERE NOT fn_is_class_eligible(b.dob, s.desired_class)

-- ---- Seats: each choice must be valid for the student and the application ---
UNION ALL
SELECT 'seat', 'chosen seat is for the student''s desired class',
       count(*) FROM application_choice ac
  JOIN application a ON a.application_id = ac.application_id
  JOIN student s     ON s.bc_no = a.bc_no
  JOIN seat se       ON se.seat_id = ac.seat_id
 WHERE se.class_level <> s.desired_class

UNION ALL
SELECT 'seat', 'chosen seat is in the applying area',
       count(*) FROM application_choice ac
  JOIN application a ON a.application_id = ac.application_id
  JOIN seat se       ON se.seat_id = ac.seat_id
  JOIN school sch    ON sch.eiin = se.eiin
 WHERE sch.postcode <> a.applying_postcode

UNION ALL
SELECT 'seat', 'chosen seat gender suits the student',
       count(*) FROM application_choice ac
  JOIN application a       ON a.application_id = ac.application_id
  JOIN birth_certificate b ON b.bc_no = a.bc_no
  JOIN seat se             ON se.seat_id = ac.seat_id
 WHERE se.seat_gender <> 'BOTH' AND se.seat_gender::TEXT <> b.gender::TEXT

UNION ALL
SELECT 'seat', 'no seat is reused across one student''s applications',
       (SELECT count(*) FROM (
          SELECT a.bc_no, ac.seat_id FROM application_choice ac
            JOIN application a ON a.application_id = ac.application_id
           GROUP BY a.bc_no, ac.seat_id HAVING count(*) > 1) x)

UNION ALL
SELECT 'seat', 'at most 5 choices per application',
       (SELECT count(*) FROM (
          SELECT application_id FROM application_choice
           GROUP BY application_id HAVING count(*) > 5) x)

-- ---- Quotas: a claimed quota must actually be earned ------------------------
UNION ALL
SELECT 'quota', 'Freedom-Fighter reference belongs to a parent of the student',
       count(*) FROM choice_quota cq
  JOIN application_choice ac ON ac.choice_id = cq.choice_id
  JOIN application a         ON a.application_id = ac.application_id
  JOIN student s             ON s.bc_no = a.bc_no
  JOIN quota_reference qr    ON qr.ref_id = cq.ref_id
 WHERE cq.quota_code = 'FREEDOM_FIGHTER'
   AND qr.nid IS DISTINCT FROM s.father_nid
   AND qr.nid IS DISTINCT FROM s.mother_nid

UNION ALL
SELECT 'quota', 'Area quota only where the applying area is the present address',
       count(*) FROM choice_quota cq
  JOIN application_choice ac ON ac.choice_id = cq.choice_id
  JOIN application a         ON a.application_id = ac.application_id
  JOIN student s             ON s.bc_no = a.bc_no
 WHERE cq.quota_code = 'AREA' AND a.applying_postcode IS DISTINCT FROM s.present_postcode

UNION ALL
SELECT 'quota', 'a quota requiring a reference has one',
       count(*) FROM choice_quota cq JOIN quota_type qt ON qt.code = cq.quota_code
 WHERE qt.requires_reference AND cq.ref_id IS NULL

-- ---- Payment: every application carries a fee row --------------------------
UNION ALL
SELECT 'payment', 'every application has a payment row',
       count(*) FROM application a
 WHERE NOT EXISTS (SELECT 1 FROM payment p WHERE p.application_id = a.application_id)

)
SELECT category, check_name, violations,
       CASE WHEN violations = 0 THEN 'PASS' ELSE 'FAIL' END AS status
  FROM checks
 ORDER BY status DESC, category, check_name;
