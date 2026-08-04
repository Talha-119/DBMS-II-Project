'use strict';
const { query } = require('../config/db');
const env = require('../config/env');
const { maskMobile } = require('../utils/helpers');

// Issue an OTP for (purpose, mobile) and build the standard API response.
// The code is generated + hashed in the DB (fn_issue_otp); in dev we also
// return it so the flow is testable without a real SMS gateway.
async function issueOtp(purpose, mobile) {
  const { rows } = await query('SELECT fn_issue_otp($1, $2, $3) AS code', [purpose, mobile, env.OTP_TTL_SECONDS]);
  const resp = { sent: true, mobile_masked: maskMobile(mobile) };
  if (env.OTP_DEV_RETURN) resp.dev_code = rows[0].code;
  return resp;
}

// Verify an OTP (single-use, expiring) via the DB function.
async function verifyOtp(purpose, mobile, code) {
  const { rows } = await query('SELECT fn_verify_otp($1, $2, $3) AS valid', [purpose, mobile, code]);
  return rows[0].valid === true;
}

module.exports = { issueOtp, verifyOtp };
