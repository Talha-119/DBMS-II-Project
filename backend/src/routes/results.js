'use strict';
// Public result lookup by birth-certificate number (only after results publish).
const router = require('express').Router();
const { query } = require('../config/db');
const { asyncHandler } = require('../utils/helpers');

router.get('/:bc', asyncHandler(async (req, res) => {
  const ready = await query("SELECT value FROM app_setting WHERE key = 'RESULT_READY'");
  if (!ready.rows.length || ready.rows[0].value !== 'TRUE') {
    return res.status(409).json({ error: 'Results are not published yet' });
  }
  // Optional ?type=GOVERNMENT|NON_GOVERNMENT mirrors the portal's separate
  // govt / non-govt result searches. WAITING rows have no school yet, so they
  // are kept in both tracks.
  const type = req.query.type || null;
  const { rows } = await query(
    `SELECT application_id, status, allocated_quota, school_name, school_type, class_level, shift, round
     FROM vw_admission_result
     WHERE bc_no = $1 AND ($2::text IS NULL OR school_type IS NULL OR school_type = $2)
     ORDER BY application_id`, [req.params.bc, type]);
  res.json(rows);
}));

module.exports = router;
