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
  const { rows } = await query(
    `SELECT application_id, status, allocated_quota, school_name, class_level, shift
     FROM vw_admission_result WHERE bc_no = $1 ORDER BY application_id`, [req.params.bc]);
  res.json(rows);
}));

module.exports = router;
