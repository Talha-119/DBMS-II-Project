-- ============================================================================
-- views/01_views.sql
-- Read models built from multi-table joins. The API reads these directly so the
-- join logic lives once, in the database.
-- ============================================================================

-- Schools enriched with their administrative area (drives cascading dropdowns).
CREATE OR REPLACE VIEW vw_area_schools AS
SELECT sch.eiin, sch.name, sch.school_gender,
       pc.postcode, pc.division, pc.district, pc.thana
FROM school sch
JOIN postcode pc ON pc.postcode = sch.postcode;

-- Seat rows with school + area + live per-quota availability.
CREATE OR REPLACE VIEW vw_seat_availability AS
SELECT se.seat_id, se.eiin, sch.name AS school_name, sch.postcode,
       pc.division, pc.district, pc.thana,
       se.class_level, se.shift, se.seat_gender,
       COALESCE(SUM(sq.capacity), 0)::INT AS total_available,
       COALESCE(
           jsonb_object_agg(sq.quota_code, sq.capacity) FILTER (WHERE sq.quota_code IS NOT NULL),
           '{}'::jsonb
       ) AS by_quota
FROM seat se
JOIN school sch ON sch.eiin = se.eiin
JOIN postcode pc ON pc.postcode = sch.postcode
LEFT JOIN seat_quota sq ON sq.seat_id = se.seat_id
GROUP BY se.seat_id, se.eiin, sch.name, sch.postcode,
         pc.division, pc.district, pc.thana, se.class_level, se.shift, se.seat_gender;

-- The full applicant copy (everything needed to render/print the PDF form).
CREATE OR REPLACE VIEW vw_applicant_copy AS
SELECT
    a.application_id, a.submitted_at, a.status, s.desired_class, s.prev_school_name,
    a.applying_postcode,
    ap.division AS applying_division, ap.district AS applying_district, ap.thana AS applying_thana,
    bc.bc_no, bc.name AS student_name, bc.dob, bc.gender,
    s.religion, s.mobile,
    s.father_nid, fn.name AS father_name,
    s.mother_nid, mn.name AS mother_name,
    s.local_guardian_nid, lg.name AS local_guardian_name,
    s.present_postcode, pp.division AS present_division, pp.district AS present_district,
    pp.thana AS present_thana, s.present_detail,
    s.permanent_postcode, qp.division AS permanent_division, qp.district AS permanent_district,
    qp.thana AS permanent_thana, s.permanent_detail,
    pay.status AS payment_status, pay.amount AS fee_amount, pay.method AS payment_method,
    (SELECT jsonb_agg(jsonb_build_object(
                'preference', c.preference,
                'seat_id',    c.seat_id,
                'school_name', sch.name,
                'class',      se.class_level,
                'shift',      se.shift,
                'seat_gender', se.seat_gender,
                'quotas',     (SELECT jsonb_agg(cq.quota_code ORDER BY qt.priority)
                               FROM choice_quota cq JOIN quota_type qt ON qt.code = cq.quota_code
                               WHERE cq.choice_id = c.choice_id)) ORDER BY c.preference)
     FROM application_choice c
     JOIN seat se   ON se.seat_id = c.seat_id
     JOIN school sch ON sch.eiin = se.eiin
     WHERE c.application_id = a.application_id) AS choices
FROM application a
JOIN student s            ON s.bc_no = a.bc_no
JOIN birth_certificate bc ON bc.bc_no = a.bc_no
JOIN postcode ap          ON ap.postcode = a.applying_postcode
JOIN postcode pp          ON pp.postcode = s.present_postcode
JOIN postcode qp          ON qp.postcode = s.permanent_postcode
LEFT JOIN nid fn          ON fn.nid = s.father_nid
LEFT JOIN nid mn          ON mn.nid = s.mother_nid
LEFT JOIN nid lg          ON lg.nid = s.local_guardian_nid
LEFT JOIN payment pay     ON pay.application_id = a.application_id;

-- Lottery results with student + school names resolved.
CREATE OR REPLACE VIEW vw_admission_result AS
SELECT r.application_id, a.bc_no, bc.name AS student_name,
       r.status, r.allocated_quota, r.admitted_seat_id,
       sch.eiin, sch.name AS school_name, se.class_level, se.shift,
       r.round, r.decided_at
FROM admission_result r
JOIN application a         ON a.application_id = r.application_id
JOIN birth_certificate bc  ON bc.bc_no = a.bc_no
LEFT JOIN seat se          ON se.seat_id = r.admitted_seat_id
LEFT JOIN school sch       ON sch.eiin = se.eiin;

-- (The per-school dashboard aggregate view used by the authority/admin portals
--  is not part of this applicant project.)
