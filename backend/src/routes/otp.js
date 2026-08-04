'use strict';
// OTP issue/verify. Rate-limited; codes are generated + hashed inside the DB.
const router = require('express').Router();
const { body } = require('express-validator');
const rateLimit = require('express-rate-limit');
const env = require('../config/env');
const { validate } = require('../middleware/validate');
const { asyncHandler } = require('../utils/helpers');
const { issueOtp, verifyOtp } = require('../services/otpService');

const PURPOSES = ['APPLY', 'RETRIEVE', 'DELETE', 'RECOVER'];

// Tight limit on OTP sending to deter abuse (max configurable via env).
const sendLimiter = rateLimit({ windowMs: 60 * 1000, max: env.OTP_SEND_MAX, standardHeaders: true, legacyHeaders: false });

router.post('/send',
  sendLimiter,
  body('mobile').matches(/^01[3-9][0-9]{8}$/).withMessage('Invalid Bangladeshi mobile'),
  body('purpose').isIn(PURPOSES),
  validate,
  asyncHandler(async (req, res) => {
    res.json(await issueOtp(req.body.purpose, req.body.mobile));
  }));

router.post('/verify',
  body('mobile').matches(/^01[3-9][0-9]{8}$/),
  body('purpose').isIn(PURPOSES),
  body('code').isLength({ min: 6, max: 6 }),
  validate,
  asyncHandler(async (req, res) => {
    const { mobile, purpose, code } = req.body;
    res.json({ valid: await verifyOtp(purpose, mobile, code) });
  }));

module.exports = router;
