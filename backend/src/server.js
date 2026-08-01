'use strict';
const app = require('./app');
const env = require('./config/env');
const { pool } = require('./config/db');

const server = app.listen(env.PORT, () => {
  console.log(`[admission-api] listening on http://localhost:${env.PORT} (${env.NODE_ENV})`);
});

// Graceful shutdown.
function shutdown(sig) {
  console.log(`\n[admission-api] ${sig} received, shutting down ...`);
  server.close(() => pool.end().then(() => process.exit(0)));
}
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
