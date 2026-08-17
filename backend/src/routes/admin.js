'use strict';
// Master-admin portal API.
const router = require('express').Router();
const { body } = require('express-validator');
const { query } = require('../config/db');
const { requireAuth, requireRole } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { asyncHandler } = require('../utils/helpers');

router.use(requireAuth, requireRole('MASTER_ADMIN'));

// Schools -------------------------------------------------------------------
router.get('/schools', asyncHandler(async (_req, res) => {
  const { rows } = await query('SELECT * FROM vw_school_dashboard ORDER BY eiin');
  res.json(rows);
}));

router.post('/schools',
  body('name').isString().notEmpty(),
  body('postcode').matches(/^[0-9]{4}$/),
  body('school_gender').isIn(['MALE', 'FEMALE', 'BOTH']),
  validate,
  asyncHandler(async (req, res) => {
    const { name, postcode, school_gender } = req.body;
    const { rows } = await query(
      'CALL sp_add_school($1, $2, $3::seat_gender_t, $4, $5)',
      [name, postcode, school_gender, null, null]);
    // Returns the generated EIIN + a one-time temporary password (show once).
    res.status(201).json({ eiin: rows[0].p_eiin, temp_password: rows[0].p_password });
  }));

router.delete('/schools/:eiin', asyncHandler(async (req, res) => {
  // sp_delete_school pre-checks for applications/results referencing the
  // school and raises a clear, actionable message instead of a raw FK error.
  await query('CALL sp_delete_school($1)', [req.params.eiin]);
  res.json({ deleted: true });
}));

// Lottery -------------------------------------------------------------------
router.post('/lottery',
  body('round').optional().isInt({ min: 1 }),
  validate,
  asyncHandler(async (req, res) => {
    const round = req.body.round || 1;
    await query('CALL sp_run_lottery($1::int)', [round]);
    res.json({ ran: true, round });
  }));

// Deletion approvals --------------------------------------------------------
router.get('/deletion-requests', asyncHandler(async (_req, res) => {
  const { rows } = await query(
    `SELECT d.request_id, d.application_id, d.reason, d.status, d.requested_at,
            bc.name AS student_name
     FROM deletion_request d
     JOIN application a ON a.application_id = d.application_id
     JOIN birth_certificate bc ON bc.bc_no = a.bc_no
     WHERE d.status = 'PENDING'
     ORDER BY d.requested_at`);
  res.json(rows);
}));

router.post('/deletion-requests/:id',
  body('approve').isBoolean(),
  validate,
  asyncHandler(async (req, res) => {
    await query('CALL sp_approve_deletion($1::bigint, $2, $3::boolean)',
      [req.params.id, req.user.login_id, req.body.approve]);
    res.json({ decided: true, approved: req.body.approve });
  }));

// Forms / results / audit ---------------------------------------------------
router.get('/applications/:id', asyncHandler(async (req, res) => {
  const { rows } = await query('SELECT * FROM vw_applicant_copy WHERE application_id = $1', [req.params.id]);
  if (!rows.length) return res.status(404).json({ error: 'Application not found' });
  res.json(rows[0]);
}));

router.get('/results', asyncHandler(async (_req, res) => {
  const { rows } = await query('SELECT * FROM vw_admission_result ORDER BY status, application_id');
  res.json(rows);
}));

router.get('/audit', asyncHandler(async (_req, res) => {
  const { rows } = await query(
    'SELECT log_id, table_name, action, at FROM audit_log ORDER BY log_id DESC LIMIT 50');
  res.json(rows);
}));

// Quota types (extensible: add quotas, retune %, change priority, rebalance) ---
router.get('/quota-types', asyncHandler(async (_req, res) => {
  const { rows } = await query(
    'SELECT code, name, requires_reference, priority, default_share, is_default FROM quota_type ORDER BY priority');
  res.json(rows);
}));

router.post('/quota-types',
  body('code').matches(/^[A-Z0-9_]{2,20}$/).withMessage('code must be UPPER_SNAKE (2-20)'),
  body('name').isString().notEmpty(),
  body('priority').isInt({ min: 1 }),
  body('default_share').isFloat({ min: 0, max: 1 }),
  body('requires_reference').optional().isBoolean(),
  body('is_default').optional().isBoolean(),
  validate,
  asyncHandler(async (req, res) => {
    const b = req.body;
    await query('CALL sp_upsert_quota_type($1,$2,$3,$4::int,$5::numeric,$6)',
      [b.code, b.name, b.requires_reference ?? false, b.priority, b.default_share, b.is_default ?? false]);
    res.status(201).json({ saved: true, code: b.code });
  }));

router.delete('/quota-types/:code', asyncHandler(async (req, res) => {
  const r = await query('DELETE FROM quota_type WHERE code = $1', [req.params.code]);
  if (!r.rowCount) return res.status(404).json({ error: 'Quota type not found' });
  res.json({ deleted: true });
}));

// Re-split all seats by current quota shares (pre-lottery).
router.post('/quota-types/rebalance', asyncHandler(async (_req, res) => {
  await query('CALL sp_rebalance_seats()');
  res.json({ rebalanced: true });
}));

// Class age eligibility — READ ONLY for the master admin.
// The national windows are policy: the admin can see them but not change them.
// Each school sets its own (narrower) window through the authority portal
// (POST /authority/class-eligibility), so admission criteria belong to the
// school that admits the student, not to the central operator.
router.get('/class-eligibility', asyncHandler(async (_req, res) => {
  const { rows } = await query('SELECT * FROM fn_class_eligibility_info()');
  res.json(rows);
}));

// Which schools have narrowed a class window, for oversight.
router.get('/school-class-eligibility', asyncHandler(async (_req, res) => {
  const { rows } = await query(
    `SELECT sce.eiin, s.name AS school_name, sce.class_level,
            sce.min_dob, sce.max_dob, sce.updated_at,
            ce.min_dob AS national_min_dob, ce.max_dob AS national_max_dob
     FROM school_class_eligibility sce
     JOIN school s ON s.eiin = sce.eiin
     JOIN class_eligibility ce ON ce.class_level = sce.class_level
     ORDER BY s.name, sce.class_level`);
  res.json(rows);
}));

// Settings (e.g. reopen the admission round) --------------------------------
router.get('/settings', asyncHandler(async (_req, res) => {
  const { rows } = await query('SELECT key, value, updated_at FROM app_setting ORDER BY key');
  res.json(rows);
}));

router.post('/settings',
  body('key').isString().notEmpty(),
  body('value').isString().notEmpty(),
  validate,
  asyncHandler(async (req, res) => {
    await query(
      `INSERT INTO app_setting(key, value) VALUES ($1, $2)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [req.body.key, req.body.value]);
    res.json({ saved: true });
  }));

// Analytics: Division stats
router.get('/analytics/division', asyncHandler(async (req, res) => {
  const division = req.query.division;
  const { rows } = await query(`
    SELECT 
      COUNT(*) AS total_choices,
      SUM(CASE WHEN pref = 1 THEN 1 ELSE 0 END)::float / COUNT(*) * 100 AS choice1_pct,
      SUM(CASE WHEN pref = 1 THEN 1 ELSE 0 END)::float / NULLIF(s.capacity,0) AS demand_ratio,
      json_agg(json_build_object(
        'eiin', s.eiin,
        'school_name', s.name,
        'capacity', s.capacity,
        'choice1_hits', COUNT(CASE WHEN ac.preference = 1 THEN 1 END),
        'total_hits', COUNT(*)
      )) AS top_schools
    FROM vw_school_dashboard s
    JOIN application_choice ac ON ac.seat_id = s.seat_id
    WHERE s.division = $1
    GROUP BY s.eiin, s.name, s.capacity
    ORDER BY choice1_hits DESC
    LIMIT 10;
  `, [division]);
  res.json(rows);
}));

// Lottery results search
router.get('/lottery-results', asyncHandler(async (req, res) => {
  const { search, status } = req.query;
  const { rows } = await query(`
    SELECT ar.*, st.name AS student_name, sc.name AS school_name, sc.eiin
    FROM vw_admission_result ar
    JOIN student st ON st.bc_no = ar.bc_no
    JOIN seat sc ON sc.seat_id = ar.seat_id
    WHERE ($1 IS NULL OR ar.application_id ILIKE $1 OR st.name ILIKE $1 OR st.bc_no ILIKE $1)
      AND ($2 IS NULL OR ar.result_status = $2);
  `, [search ? `%${search}%` : null, status && status !== 'ALL' ? status : null]);
  res.json(rows);
}));

// Forfeit expired allotments
router.post('/lottery/forfeit-expired', asyncHandler(async (req, res) => {
  const deadline = req.body.deadline; // ISO timestamp
  await query('CALL proc_process_expired_allotments($1::timestamptz)', [deadline]);
  res.json({ forfeit: true });
}));

// Disqualify applicant
router.post('/lottery/disqualify',
  body('applicationId').isString(),
  body('reason').isString(),
  validate,
  asyncHandler(async (req, res) => {
    const { applicationId, reason } = req.body;
    await query('CALL proc_disqualify_applicant($1, $2)', [applicationId, reason]);
    res.json({ disqualified: true });
  })
);

module.exports = router;

