'use strict';
const path = require('path');

// The single .env lives at the project root (admission-system/.env).
require('dotenv').config({ path: path.resolve(__dirname, '../../../.env') });

module.exports = {
  PGHOST: process.env.PGHOST || 'localhost',
  PGPORT: parseInt(process.env.PGPORT || '5432', 10),
  APP_DB: process.env.APP_DB || 'admission_applicant',
  APP_DB_USER: process.env.APP_DB_USER || 'admission_app',
  APP_DB_PASSWORD: process.env.APP_DB_PASSWORD || 'admission_app_pw',

  PORT: parseInt(process.env.PORT || '4000', 10),
  NODE_ENV: process.env.NODE_ENV || 'development',

  JWT_SECRET: process.env.JWT_SECRET || 'dev_secret_change_me',
  JWT_EXPIRES_IN: process.env.JWT_EXPIRES_IN || '2h',

  CLIENT_ORIGIN: process.env.CLIENT_ORIGIN || 'http://localhost:5173',

  OTP_DEV_RETURN: (process.env.OTP_DEV_RETURN || 'true') === 'true',
  OTP_TTL_SECONDS: parseInt(process.env.OTP_TTL_SECONDS || '300', 10),

  // Rate-limit knobs (overridable so the test harness can run deterministically
  // and also spin a tight-limit instance to prove limiting works).
  GLOBAL_RATE_MAX: parseInt(process.env.GLOBAL_RATE_MAX || '300', 10),
  OTP_SEND_MAX: parseInt(process.env.OTP_SEND_MAX || '5', 10),
};
