'use strict';
// School-authority portal API (scoped to the logged-in school's EIIN).
const router = require('express').Router();
const { body } = require('express-validator');
const { query } = require('../config/db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { asyncHandler } = require('../utils/helpers');

router.use(requireAuth, requireRole('SCHOOL_AUTHORITY'));

router.get('/me', asyncHandler(async (req, res) => {
  const { rows } = await query('SELECT eiin, name, postcode, school_gender FROM school WHERE eiin = $1', [req.user.eiin]);
  res.json(rows[0] || {});
}));

router.get('/dashboard', asyncHandler(async (req, res) => {
  const { rows } = await query('SELECT * FROM vw_school_dashboard WHERE eiin = $1', [req.user.eiin]);
  res.json(rows[0] || {});
}));

router.get('/seats', asyncHandler(async (req, res) => {
  const { rows } = await query(
    'SELECT * FROM vw_seat_availability WHERE eiin = $1 ORDER BY class_level, shift, seat_gender', [req.user.eiin]);
  res.json(rows);
}));

// Add or update a seat row; total is split across quotas by sp_add_seat.
router.post('/seats',
  body('class_level').isInt({ min: 1, max: 12 }),
  body('shift').isIn(['MORNING', 'DAY']),
  body('seat_gender').isIn(['MALE', 'FEMALE', 'BOTH']),
  body('total').isInt({ min: 0 }),
  validate,
  asyncHandler(async (req, res) => {
    const { class_level, shift, seat_gender, total } = req.body;
    const { rows } = await query(
      'CALL sp_add_seat($1, $2::int, $3::shift_t, $4::seat_gender_t, $5::int, $6)',
      [req.user.eiin, class_level, shift, seat_gender, total, null]);
    res.status(201).json({ seat_id: rows[0].p_seat_id });
  }));

// Remove one of this school's seat rows. sp_delete_seat re-checks ownership in
// the DB, so the EIIN from the token is verified server-side and again in SQL.
router.delete('/seats/:seatId', asyncHandler(async (req, res) => {
  await query('CALL sp_delete_seat($1, $2)', [req.user.eiin, req.params.seatId]);
  res.json({ deleted: true });
}));

// Class age eligibility for THIS school: the national baseline, this school's
// own override, and the effective window in force for each class.
router.get('/class-eligibility', asyncHandler(async (req, res) => {
  const { rows } = await query('SELECT * FROM fn_school_class_eligibility_info($1)', [req.user.eiin]);
  res.json(rows);
}));

// Narrow this school's window for a class. The DB trigger rejects any window
// wider than the national one.
router.post('/class-eligibility',
  body('class_level').isInt({ min: 1, max: 12 }),
  body('min_dob').isISO8601().withMessage('min_dob must be a date (YYYY-MM-DD)'),
  body('max_dob').isISO8601().withMessage('max_dob must be a date (YYYY-MM-DD)'),
  validate,
  asyncHandler(async (req, res) => {
    const { class_level, min_dob, max_dob } = req.body;
    await query('CALL sp_upsert_school_class_eligibility($1, $2::int, $3::date, $4::date)',
      [req.user.eiin, class_level, min_dob, max_dob]);
    res.status(201).json({ saved: true, class_level });
  }));

// Drop the override so this class falls back to the national window.
router.delete('/class-eligibility/:class', asyncHandler(async (req, res) => {
  await query('CALL sp_reset_school_class_eligibility($1, $2::int)',
    [req.user.eiin, req.params.class]);
  res.json({ reset: true });
}));

// Applicants who chose a seat in this school.
router.get('/applicants', asyncHandler(async (req, res) => {
  const { rows } = await query(
    `SELECT DISTINCT a.application_id, bc.name AS student_name, s.desired_class,
            a.status, a.submitted_at
     FROM application a
     JOIN birth_certificate bc ON bc.bc_no = a.bc_no
     JOIN student s ON s.bc_no = a.bc_no
     JOIN application_choice ac ON ac.application_id = a.application_id
     JOIN seat se ON se.seat_id = ac.seat_id
     WHERE se.eiin = $1
     ORDER BY a.submitted_at DESC`, [req.user.eiin]);
  res.json(rows);
}));

router.get('/results', asyncHandler(async (req, res) => {
  const { rows } = await query(
    'SELECT * FROM vw_admission_result WHERE eiin = $1 ORDER BY status, application_id', [req.user.eiin]);
  res.json(rows);
}));

module.exports = router;
