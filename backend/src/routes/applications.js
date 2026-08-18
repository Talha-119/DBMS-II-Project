'use strict';
// Applicant-facing application lifecycle: submit, retrieve (BC+DOB+OTP), view,
// download PDF, request deletion. Applicants are account-less; a short-lived
// "applicant token" (issued on successful retrieve) gates access to a copy.
const router = require('express').Router();
const jwt = require('jsonwebtoken');
const { body } = require('express-validator');
const { query } = require('../config/db');
const env = require('../config/env');
const { validate } = require('../middleware/validate');
const { requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../utils/helpers');
const { issueOtp, verifyOtp } = require('../services/otpService');
const { streamApplicantCopy } = require('../utils/pdf');

// Gate for applicant-copy access. requireAuth verifies the JWT (applicant token
// or staff token) and sets req.user; ensureCanAccess then authorizes by ownership.
const applicantAccess = requireAuth;

async function fetchCopy(applicationId) {
  const { rows } = await query('SELECT * FROM vw_applicant_copy WHERE application_id = $1', [applicationId]);
  return rows[0] || null;
}

// Running the lottery sets application.status to ADMITTED / WAITING immediately,
// but a run is not a published result: the admin reviews it first and may re-run.
// So on the applicant side the outcome is hidden until RESULT_READY — otherwise
// the retrieve screen and the PDF would quietly announce a result the admin has
// deliberately not published yet, and the "Check Result" gate would be pointless.
async function resultsPublished() {
  const { rows } = await query("SELECT value FROM app_setting WHERE key = 'RESULT_READY'");
  return rows.length > 0 && rows[0].value === 'TRUE';
}

const OUTCOME_STATUSES = new Set(['ADMITTED', 'WAITING', 'NOT_ADMITTED']);

// Falls back to the applicant's own last-known state ("your form is in"), which
// is exactly what it was before the draw. CANCELLED is an applicant-visible
// administrative state, not a lottery outcome, so it is left alone.
function maskOutcome(row) {
  if (!row || !OUTCOME_STATUSES.has(row.status)) return row;
  return { ...row, status: 'SUBMITTED' };
}

async function ensureCanAccess(req, copy) {
  if (!copy) return { ok: false, status: 404, error: 'Application not found' };
  if (req.user && req.user.role === 'MASTER_ADMIN') return { ok: true };
  if (req.user && req.user.scope === 'applicant' && req.user.bc_no === copy.bc_no) return { ok: true };
  return { ok: false, status: 403, error: 'Forbidden' };
}

// --- Verify an APPLY OTP up-front and return a short-lived proof token bound to
//     the mobile. The apply form calls this the moment the code is entered, so the
//     UI can show a "verified" badge and lock the mobile to the verified number.
//     The single-use OTP is consumed here; submit then trusts this proof. ---
router.post('/verify-otp',
  body('mobile').matches(/^01[3-9][0-9]{8}$/),
  body('code').isLength({ min: 6, max: 6 }),
  validate,
  asyncHandler(async (req, res) => {
    const { mobile, code } = req.body;
    if (!(await verifyOtp('APPLY', mobile, code))) {
      return res.status(400).json({ error: 'Invalid or expired OTP' });
    }
    const token = jwt.sign({ scope: 'apply_otp', mobile }, env.JWT_SECRET, { expiresIn: '30m' });
    res.json({ verified: true, token });
  }));

// --- Submit a new application. Mobile ownership is proven by an `apply_token`
//     (from /verify-otp, the new UI flow) OR a raw `otp_code` (back-compat). ---
router.post('/',
  body('bc_no').isString().notEmpty(),
  body('religion').isIn(['ISLAM', 'HINDU', 'CHRISTIAN', 'BUDDHIST', 'OTHER']),
  body('mobile').matches(/^01[3-9][0-9]{8}$/),
  body('present_postcode').matches(/^[0-9]{4}$/),
  body('permanent_postcode').matches(/^[0-9]{4}$/),
  body('applying_postcode').matches(/^[0-9]{4}$/),
  body('desired_class').isInt({ min: 1, max: 12 }),
  body('choices').isArray({ min: 1, max: 5 }),
  body('otp_code').optional().isLength({ min: 6, max: 6 }),
  body('apply_token').optional().isString(),
  validate,
  asyncHandler(async (req, res) => {
    const b = req.body;

    // Mobile OTP must be verified FOR THE MOBILE BEING SUBMITTED (so changing the
    // number after verifying invalidates the proof and blocks submission).
    let otpOk = false;
    if (b.apply_token) {
      try {
        const d = jwt.verify(b.apply_token, env.JWT_SECRET);
        otpOk = d.scope === 'apply_otp' && d.mobile === b.mobile;
      } catch { otpOk = false; }
    } else if (b.otp_code) {
      otpOk = await verifyOtp('APPLY', b.mobile, b.otp_code);
    }
    if (!otpOk) {
      return res.status(400).json({ error: 'Mobile not verified. Please verify the OTP for the exact mobile number you are submitting with.' });
    }

    const { rows } = await query(
      `CALL sp_submit_application($1,$2::religion_t,$3,$4,$5,$6,$7,$8,$9,$10,$11::int,$12,$13,$14::jsonb,$15)`,
      [
        b.bc_no, b.religion, b.mobile,
        b.father_nid || null, b.mother_nid || null, b.local_guardian_nid || null,
        b.present_postcode, b.present_detail, b.permanent_postcode, b.permanent_detail,
        b.desired_class, b.applying_postcode, b.prev_school_name || null,
        JSON.stringify(b.choices), null,
      ]);
    res.status(201).json({ application_id: rows[0].p_application_id });
  }));

// --- Retrieve step 1: confirm BC + DOB, send OTP to the registered mobile ---
router.post('/retrieve/start',
  body('bc_no').isString().notEmpty(),
  body('dob').isISO8601(),
  validate,
  asyncHandler(async (req, res) => {
    const { bc_no, dob } = req.body;
    const { rows } = await query(
      `SELECT s.mobile FROM student s
       JOIN birth_certificate b ON b.bc_no = s.bc_no
       WHERE s.bc_no = $1 AND b.dob = $2`, [bc_no, dob]);
    if (!rows.length) return res.status(404).json({ error: 'No application found for that birth certificate and date of birth' });
    res.json(await issueOtp('RETRIEVE', rows[0].mobile));
  }));

// --- Retrieve step 2: verify OTP, return applications + an applicant token ---
router.post('/retrieve',
  body('bc_no').isString().notEmpty(),
  body('dob').isISO8601(),
  body('code').isLength({ min: 6, max: 6 }),
  validate,
  asyncHandler(async (req, res) => {
    const { bc_no, dob, code } = req.body;
    const stu = await query(
      `SELECT s.mobile FROM student s
       JOIN birth_certificate b ON b.bc_no = s.bc_no
       WHERE s.bc_no = $1 AND b.dob = $2`, [bc_no, dob]);
    if (!stu.rows.length) return res.status(404).json({ error: 'No application found' });

    if (!(await verifyOtp('RETRIEVE', stu.rows[0].mobile, code))) {
      return res.status(400).json({ error: 'Invalid or expired OTP' });
    }

    const apps = await query(
      `SELECT a.application_id, s.desired_class, a.status, a.submitted_at,
              p.thana, p.district, p.division, a.applying_postcode,
              pay.status AS payment_status, pay.amount AS fee_amount
       FROM application a
       JOIN student s ON s.bc_no = a.bc_no
       JOIN postcode p ON p.postcode = a.applying_postcode
       LEFT JOIN payment pay ON pay.application_id = a.application_id
       WHERE a.bc_no = $1 ORDER BY a.submitted_at DESC`, [bc_no]);

    const published = await resultsPublished();
    const applications = published ? apps.rows : apps.rows.map(maskOutcome);

    const token = jwt.sign({ scope: 'applicant', bc_no }, env.JWT_SECRET, { expiresIn: '30m' });
    res.json({ token, applications, result_ready: published });
  }));

// The admin sees the real state (they need it to review an unpublished run);
// an applicant sees the outcome only once it has been published.
async function copyForViewer(req, copy) {
  if (req.user && req.user.role === 'MASTER_ADMIN') return copy;
  return (await resultsPublished()) ? copy : maskOutcome(copy);
}

// --- View a single applicant copy (JSON) ---
router.get('/:id', applicantAccess, asyncHandler(async (req, res) => {
  const copy = await fetchCopy(req.params.id);
  const access = await ensureCanAccess(req, copy);
  if (!access.ok) return res.status(access.status).json({ error: access.error });
  res.json(await copyForViewer(req, copy));
}));

// --- Download the applicant copy as PDF ---
router.get('/:id/pdf', applicantAccess, asyncHandler(async (req, res) => {
  const copy = await fetchCopy(req.params.id);
  const access = await ensureCanAccess(req, copy);
  if (!access.ok) return res.status(access.status).json({ error: access.error });
  streamApplicantCopy(await copyForViewer(req, copy), res);
}));

// --- Request deletion (verifies a DELETE OTP, queues for master-admin approval) ---
router.post('/:id/delete-request',
  body('otp_code').isLength({ min: 6, max: 6 }),
  validate,
  asyncHandler(async (req, res) => {
    const copy = await fetchCopy(req.params.id);
    if (!copy) return res.status(404).json({ error: 'Application not found' });

    if (!(await verifyOtp('DELETE', copy.mobile, req.body.otp_code))) {
      return res.status(400).json({ error: 'Invalid or expired OTP' });
    }

    const { rows } = await query('CALL sp_request_deletion($1, $2, $3)',
      [req.params.id, req.body.reason || null, null]);
    res.status(201).json({ request_id: rows[0].p_request_id, status: 'PENDING' });
  }));

// --- Pay the application fee (mock gateway; applicant token or admin) ---
router.post('/:id/pay', applicantAccess,
  body('method').optional().isString(),
  validate,
  asyncHandler(async (req, res) => {
    const copy = await fetchCopy(req.params.id);
    const access = await ensureCanAccess(req, copy);
    if (!access.ok) return res.status(access.status).json({ error: access.error });
    await query('CALL sp_pay_fee($1, $2)', [req.params.id, req.body.method || 'CARD']);
    res.json({ paid: true });
  }));

// --- Send a DELETE OTP for an application (to the registered mobile) ---
router.post('/:id/delete-otp', asyncHandler(async (req, res) => {
  const copy = await fetchCopy(req.params.id);
  if (!copy) return res.status(404).json({ error: 'Application not found' });
  res.json(await issueOtp('DELETE', copy.mobile));
}));

module.exports = router;
