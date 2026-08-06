'use strict';
const path = require('path');
const fs = require('fs');
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const env = require('./config/env');
const { notFound, errorHandler } = require('./middleware/errorHandler');

const app = express();

// Security + parsing middleware.
app.use(helmet());
app.use(cors({ origin: env.CLIENT_ORIGIN, credentials: true }));
app.use(express.json({ limit: '200kb' }));
if (env.NODE_ENV !== 'test') app.use(morgan('dev'));

// Global, gentle rate limit (OTP endpoints add their own tighter limit).
app.use(rateLimit({ windowMs: 60 * 1000, max: env.GLOBAL_RATE_MAX, standardHeaders: true, legacyHeaders: false }));

app.get('/health', (_req, res) => res.json({ ok: true, service: 'admission-api', time: new Date().toISOString() }));

// Routes.
app.use('/api/lookup', require('./routes/lookup'));
app.use('/api/otp', require('./routes/otp'));
app.use('/api/applications', require('./routes/applications'));
app.use('/api/results', require('./routes/results'));
app.use('/api/auth', require('./routes/auth'));
app.use('/api/authority', require('./routes/authority'));
app.use('/api/admin', require('./routes/admin'));

// Production: serve the built React app (frontend/dist) for any non-API route, so
// the whole system can run from a single server ("live server" deployment).
const clientDist = path.resolve(__dirname, '../../frontend/dist');
if (fs.existsSync(clientDist)) {
  app.use(express.static(clientDist));
  app.get(/^\/(?!api\/).*/, (_req, res) => res.sendFile(path.join(clientDist, 'index.html')));
}

// 404 (for unmatched /api routes) + centralized error handling (DB SQLSTATE -> HTTP).
app.use(notFound);
app.use(errorHandler);

module.exports = app;
