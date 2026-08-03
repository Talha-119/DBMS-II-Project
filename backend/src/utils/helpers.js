'use strict';

// Wrap async route handlers so thrown/rejected errors reach the error middleware.
const asyncHandler = (fn) => (req, res, next) =>
  Promise.resolve(fn(req, res, next)).catch(next);

// Mask a mobile number for display: 017****21
function maskMobile(m) {
  if (!m || m.length < 5) return m;
  return m.slice(0, 3) + '****' + m.slice(-2);
}

module.exports = { asyncHandler, maskMobile };
