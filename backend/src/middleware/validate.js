'use strict';
const { validationResult } = require('express-validator');

// Collects express-validator results; returns 400 with details if anything failed.
// Put after the validation chain(s) on a route.
function validate(req, res, next) {
  const result = validationResult(req);
  if (result.isEmpty()) return next();
  res.status(400).json({
    error: 'Validation failed',
    details: result.array().map((e) => ({ field: e.path, message: e.msg })),
  });
}

module.exports = { validate };
