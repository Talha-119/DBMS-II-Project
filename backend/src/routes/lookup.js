'use strict';
// Public lookup endpoints that power the auto-fill flow (no manual identity entry).
const router = require('express').Router();
const { query } = require('../config/db');
const { asyncHandler } = require('../utils/helpers');

// Birth certificate -> identity (name/dob/gender/parents/area). The apply form
// fills itself from this; the applicant never types these fields.
//
// Parent NAMES are joined from the NID registry for display. The parent NIDs
// themselves are deliberately NOT returned: this endpoint is public, so
// returning them would hand the guardian NID of any child to anyone who knows a
// birth-certificate number — and would reduce the guardian check to copying a
// value the form had already shown.
router.get('/birth-cert/:bc', asyncHandler(async (req, res) => {
  const { rows } = await query(
    `SELECT b.bc_no, b.name, b.dob, b.gender,
            f.name AS father_name, m.name AS mother_name,
            b.postcode, p.division, p.district, p.thana
     FROM birth_certificate b
     JOIN postcode p ON p.postcode = b.postcode
     JOIN nid f ON f.nid = b.father_nid
     JOIN nid m ON m.nid = b.mother_nid
     WHERE b.bc_no = $1`, [req.params.bc]);
  if (!rows.length) return res.status(404).json({ error: 'Birth certificate not found' });
  res.json(rows[0]);
}));

// Does this NID belong to the parent recorded on this birth certificate?
// Powers the apply form's live ✓ / ✗ on the guardian fields, which used to
// compare names in the browser — the same weak check the database has now
// dropped (BUG-002).
//
// Answers only yes/no plus the name of the NID that was *submitted* (already
// public via /lookup/nid). It never reveals the recorded NID, so it cannot be
// used to look one up; a caller must already know the number to get a "true".
router.get('/guardian-check', asyncHandler(async (req, res) => {
  const { bc, nid, role } = req.query;
  if (!bc || !nid || !['father', 'mother'].includes(role)) {
    return res.status(400).json({ error: 'bc, nid and role (father|mother) are required' });
  }
  const { rows } = await query(
    `SELECT n.name,
            (b.${role === 'father' ? 'father_nid' : 'mother_nid'} = $2) AS match
     FROM birth_certificate b
     LEFT JOIN nid n ON n.nid = $2
     WHERE b.bc_no = $1`, [bc, nid]);
  if (!rows.length) return res.status(404).json({ error: 'Birth certificate not found' });
  // A NID that isn't in the registry at all reads as "not the parent", with no
  // separate signal — one uniform negative answer.
  res.json({ match: rows[0].match === true, name: rows[0].name || null });
}));

// NID -> registered name (for guardian auto-fill / validation).
router.get('/nid/:nid', asyncHandler(async (req, res) => {
  const { rows } = await query('SELECT nid, name FROM nid WHERE nid = $1', [req.params.nid]);
  if (!rows.length) return res.status(404).json({ error: 'NID not found' });
  res.json(rows[0]);
}));

// Postcode -> administrative area.
router.get('/postcode/:pc', asyncHandler(async (req, res) => {
  const { rows } = await query(
    'SELECT postcode, division, district, thana FROM postcode WHERE postcode = $1', [req.params.pc]);
  if (!rows.length) return res.status(404).json({ error: 'Postcode not found' });
  res.json(rows[0]);
}));

// All areas (drives cascading division -> district -> thana dropdowns).
router.get('/areas', asyncHandler(async (_req, res) => {
  const { rows } = await query(
    'SELECT postcode, division, district, thana FROM postcode ORDER BY division, district, thana');
  res.json(rows);
}));

// Age-eligible classes for a DOB (calls the PL/pgSQL function).
router.get('/eligible-classes', asyncHandler(async (req, res) => {
  const { dob } = req.query;
  if (!dob) return res.status(400).json({ error: 'dob query param required (YYYY-MM-DD)' });
  const { rows } = await query('SELECT class_level, min_dob, max_dob FROM fn_eligible_classes($1)', [dob]);
  res.json(rows);
}));

// Schools (optionally in a postcode) for the cascading selector.
router.get('/schools', asyncHandler(async (req, res) => {
  const { postcode } = req.query;
  const { rows } = postcode
    ? await query('SELECT * FROM vw_area_schools WHERE postcode = $1 ORDER BY name', [postcode])
    : await query('SELECT * FROM vw_area_schools ORDER BY division, district, thana, name');
  res.json(rows);
}));

// Available seats in an area for a class, gender-compatible, capacity > 0.
router.get('/seats', asyncHandler(async (req, res) => {
  const { postcode, gender } = req.query;
  const cls = req.query.class;
  const { rows } = await query(
    `SELECT * FROM vw_seat_availability
     WHERE ($1::text IS NULL OR postcode = $1)
       AND ($2::int  IS NULL OR class_level = $2)
       AND ($3::text IS NULL OR seat_gender::text = 'BOTH' OR seat_gender::text = $3)
       AND total_available > 0
     ORDER BY school_name, shift`,
    [postcode || null, cls || null, gender || null]);
  res.json(rows);
}));

// Quota catalogue + reference validation.
router.get('/quota-types', asyncHandler(async (_req, res) => {
  const { rows } = await query(
    'SELECT code, name, requires_reference, priority FROM quota_type ORDER BY priority');
  res.json(rows);
}));

router.get('/quota-reference/:refId', asyncHandler(async (req, res) => {
  const { rows } = await query(
    'SELECT ref_id, nid, quota_code FROM quota_reference WHERE ref_id = $1', [req.params.refId]);
  if (!rows.length) return res.status(404).json({ error: 'Reference not found' });
  res.json(rows[0]);
}));

// Existing reusable profile for a birth certificate. A student may apply several
// times; their personal details (religion, mobile, guardians, addresses) are the
// same each time, so a returning applicant's form pre-fills from here and only the
// applying area + school choices differ. 404 when this is a first-time applicant.
router.get('/student/:bc', asyncHandler(async (req, res) => {
  const { rows } = await query(
    `SELECT bc_no, religion, mobile, father_nid, mother_nid, local_guardian_nid,
            present_postcode, present_detail, permanent_postcode, permanent_detail,
            desired_class, prev_school_name
     FROM student WHERE bc_no = $1`, [req.params.bc]);
  if (!rows.length) return res.status(404).json({ error: 'No existing profile' });
  res.json(rows[0]);
}));

module.exports = router;
