'use strict';

// Maps PostgreSQL SQLSTATE codes (including those raised by our PL/pgSQL with
// `USING ERRCODE=...`) to clean HTTP responses. Business-rule violations raised
// in the DB surface as friendly 4xx messages instead of leaking stack traces.
const SQLSTATE_STATUS = {
  '23514': 400, // check_violation (our rule failures)
  '23502': 400, // not_null_violation
  '22P02': 400, // invalid_text_representation
  '23503': 400, // foreign_key_violation (bad reference / not found)
  '23505': 409, // unique_violation (duplicate)
  '42501': 403, // insufficient_privilege (protected registry)
  'P0002': 404, // no_data_found
};

function notFound(req, res) {
  res.status(404).json({ error: 'Not found: ' + req.method + ' ' + req.originalUrl });
}

function errorHandler(err, req, res, _next) {
  let status = 500;
  if (err.status) status = err.status;
  else if (err.code && SQLSTATE_STATUS[err.code]) status = SQLSTATE_STATUS[err.code];
  else if (err.code) status = 400; // any other DB error from bad input

  const message = err.expose === false ? 'Internal server error' : err.message || 'Internal server error';
  if (status >= 500) console.error('[error]', err);
  res.status(status).json({ error: message });
}

module.exports = { notFound, errorHandler };
