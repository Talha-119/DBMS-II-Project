'use strict';
const { Pool, types } = require('pg');
const env = require('./env');

// A Postgres DATE (dob, min_dob, max_dob) is a calendar day with no timezone.
// By default the driver turns it into a JS Date at LOCAL midnight, which then
// serializes to the PREVIOUS day in UTC (2018-03-10 -> "2018-03-09T18:00:00Z"
// in Asia/Dhaka) — so the applicant copy printed the wrong date of birth.
// Keep DATE as the plain 'YYYY-MM-DD' string it already is. TIMESTAMPTZ
// (submitted_at) is a real instant and is deliberately left alone.
types.setTypeParser(types.builtins.DATE, (v) => v);

// The API connects as the least-privilege role `admission_app` (NOT a superuser).
const pool = new Pool({
  host: env.PGHOST,
  port: env.PGPORT,
  user: env.APP_DB_USER,
  password: env.APP_DB_PASSWORD,
  database: env.APP_DB,
  max: 10,
  idleTimeoutMillis: 30000,
});

pool.on('error', (e) => console.error('[pg] idle client error:', e.message));

module.exports = {
  pool,
  // Always parameterized — never string-concatenate user input into SQL.
  query: (text, params) => pool.query(text, params),
};
