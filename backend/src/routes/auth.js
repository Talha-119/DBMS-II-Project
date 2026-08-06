'use strict';
// Login for privileged accounts. Password verification happens in the DB
// (fn_verify_login / bcrypt via pgcrypto); the API only mints the JWT.
const router = require('express').Router();
const { body } = require('express-validator');
const { query } = require('../config/db');
const { validate } = require('../middleware/validate');
const { signToken, requireAuth } = require('../middleware/auth');
const { asyncHandler } = require('../utils/helpers');

router.post('/login',
  body('login_id').isString().notEmpty(),
  body('password').isString().notEmpty(),
  validate,
  asyncHandler(async (req, res) => {
    const { login_id, password } = req.body;
    const { rows } = await query('SELECT * FROM fn_verify_login($1, $2)', [login_id, password]);
    if (!rows.length) return res.status(401).json({ error: 'Invalid credentials' });
    const a = rows[0];
    const token = signToken({ account_id: a.account_id, role: a.role, eiin: a.eiin, login_id });
    res.json({ token, role: a.role, eiin: a.eiin, must_change_password: a.must_change_password });
  }));

router.post('/change-password',
  requireAuth,
  body('new_password').isLength({ min: 6 }).withMessage('Password must be at least 6 characters'),
  validate,
  asyncHandler(async (req, res) => {
    await query('SELECT fn_set_password($1, $2)', [req.user.login_id, req.body.new_password]);
    res.json({ changed: true });
  }));

module.exports = router;
