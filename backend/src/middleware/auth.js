'use strict';
const jwt = require('jsonwebtoken');
const env = require('../config/env');

// Verify the Bearer token and attach req.user. In the applicant portion this
// guards the download/PDF endpoints: after Birth-Cert + DOB + mobile-OTP
// verification, the retrieve route issues a short-lived, application-scoped JWT
// (signed with JWT_SECRET) that the client sends back to fetch the applicant copy.
function requireAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Authentication required' });
  try {
    req.user = jwt.verify(token, env.JWT_SECRET);
    next();
  } catch (e) {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = { requireAuth };
