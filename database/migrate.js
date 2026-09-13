#!/usr/bin/env node
'use strict';

/*
 * Cross-platform migration runner for the admission database.
 *
 *   node database/migrate.js up      -> create role + db, then run all SQL in order
 *   node database/migrate.js reset   -> drop the db and re-run `up`
 *   node database/migrate.js test    -> run database/test_queries.sql and print results
 *
 * Execution order for `up`:
 *   migrations/  ->  functions/  ->  procedures/  ->  triggers/  ->  views/
 *   ->  permissions.sql  ->  seeds/
 * Files within a folder run in filename order, so numeric prefixes control order.
 *
 * Connects as the PG superuser (to create the database + app role), then runs the
 * object/seed files inside the application database. The API itself connects as
 * the least-privilege role created here.
 */

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const cfg = {
  host: process.env.PGHOST || 'localhost',
  port: parseInt(process.env.PGPORT || '5432', 10),
  superuser: process.env.PGSUPERUSER || 'postgres',
  superpass: process.env.PGSUPERPASSWORD || 'postgres',
  appDb: process.env.APP_DB || 'admission',
  appUser: process.env.APP_DB_USER || 'admission_app',
  appPass: process.env.APP_DB_PASSWORD || 'admission_app_pw',
};

function qIdent(id) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(id)) throw new Error('Unsafe identifier: ' + id);
  return '"' + id + '"';
}
function qLit(s) {
  return "'" + String(s).replace(/'/g, "''") + "'";
}
function adminClient(database) {
  return new Client({
    host: cfg.host, port: cfg.port,
    user: cfg.superuser, password: cfg.superpass,
    database,
  });
}

async function ensureRoleAndDb() {
  const c = adminClient('postgres');
  await c.connect();
  try {
    const role = await c.query('SELECT 1 FROM pg_roles WHERE rolname = $1', [cfg.appUser]);
    if (!role.rowCount) {
      await c.query(`CREATE ROLE ${qIdent(cfg.appUser)} LOGIN PASSWORD ${qLit(cfg.appPass)}`);
      console.log('  created role', cfg.appUser);
    } else {
      await c.query(`ALTER ROLE ${qIdent(cfg.appUser)} LOGIN PASSWORD ${qLit(cfg.appPass)}`);
    }
    const db = await c.query('SELECT 1 FROM pg_database WHERE datname = $1', [cfg.appDb]);
    if (!db.rowCount) {
      await c.query(`CREATE DATABASE ${qIdent(cfg.appDb)}`);
      console.log('  created database', cfg.appDb);
    }
    await c.query(`GRANT ALL ON DATABASE ${qIdent(cfg.appDb)} TO ${qIdent(cfg.appUser)}`);
  } finally {
    await c.end();
  }
}

function sqlFilesInOrder() {
  const base = __dirname;
  const groups = ['migrations', 'functions', 'procedures', 'triggers', 'views'];
  const files = [];
  for (const g of groups) {
    const dir = path.join(base, g);
    if (fs.existsSync(dir)) {
      for (const f of fs.readdirSync(dir).filter((f) => f.endsWith('.sql')).sort()) {
        files.push(path.join(dir, f));
      }
    }
  }
  const perms = path.join(base, 'permissions.sql');
  if (fs.existsSync(perms)) files.push(perms);
  const seeds = path.join(base, 'seeds');
  if (fs.existsSync(seeds)) {
    for (const f of fs.readdirSync(seeds).filter((f) => f.endsWith('.sql')).sort()) {
      files.push(path.join(seeds, f));
    }
  }
  return files;
}

async function runUp() {
  console.log('Setting up database ...');
  await ensureRoleAndDb();
  const c = adminClient(cfg.appDb);
  await c.connect();
  c.on('notice', (m) => console.log('   NOTICE:', (m.message || '').trim()));
  try {
    for (const file of sqlFilesInOrder()) {
      const sql = fs.readFileSync(file, 'utf8');
      if (!sql.trim()) continue;
      process.stdout.write('  - ' + path.relative(__dirname, file).replace(/\\/g, '/') + ' ... ');
      try {
        await c.query(sql);
        console.log('ok');
      } catch (e) {
        console.log('FAILED');
        console.error('\n' + e.message + '\n');
        process.exitCode = 1;
        return;
      }
    }
    console.log('\nDatabase ready: ' + cfg.appDb + ' (app role: ' + cfg.appUser + ')');
  } finally {
    await c.end();
  }
}

async function runReset() {
  console.log('Resetting database ' + cfg.appDb + ' ...');
  const c = adminClient('postgres');
  await c.connect();
  try {
    await c.query(
      'SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = $1 AND pid <> pg_backend_pid()',
      [cfg.appDb]
    );
    await c.query(`DROP DATABASE IF EXISTS ${qIdent(cfg.appDb)}`);
    console.log('  dropped database', cfg.appDb);
  } finally {
    await c.end();
  }
  await runUp();
}

async function runTest() {
  const file = path.join(__dirname, 'test_queries.sql');
  if (!fs.existsSync(file)) {
    console.error('test_queries.sql not found');
    process.exitCode = 1;
    return;
  }
  const c = adminClient(cfg.appDb);
  await c.connect();
  c.on('notice', (m) => console.log('   NOTICE:', (m.message || '').trim()));
  try {
    const sql = fs.readFileSync(file, 'utf8');
    // Statements are separated by a line containing only:  -- @@
    const chunks = sql.split(/\r?\n--\s*@@\s*\r?\n/).map((s) => s.trim()).filter(Boolean);
    let i = 0;
    for (const chunk of chunks) {
      i++;
      const m = chunk.match(/^--\s*(.+)/);
      const title = m ? m[1].trim() : 'Step ' + i;
      console.log('\n=== ' + title + ' ===');
      try {
        const res = await c.query(chunk);
        const r = Array.isArray(res) ? res[res.length - 1] : res;
        if (r && r.rows && r.rows.length) {
          console.table(r.rows);
        } else if (r && typeof r.rowCount === 'number') {
          console.log('(' + r.rowCount + ' row(s) affected)');
        }
      } catch (e) {
        console.log('-> raised (as expected for protection demos): ' + e.message);
      }
    }
  } finally {
    await c.end();
  }
}

async function runCheck() {
  const file = path.join(__dirname, 'integrity_checks.sql');
  if (!fs.existsSync(file)) {
    console.error('integrity_checks.sql not found');
    process.exitCode = 1;
    return;
  }
  const c = adminClient(cfg.appDb);
  await c.connect();
  try {
    const res = await c.query(fs.readFileSync(file, 'utf8'));
    const rows = (Array.isArray(res) ? res[res.length - 1] : res).rows;
    console.table(rows.map((r) => ({ category: r.category, check: r.check_name, violations: Number(r.violations), status: r.status })));
    const fails = rows.filter((r) => Number(r.violations) > 0);
    console.log(`\nIntegrity: ${rows.length} checks — ${rows.length - fails.length} PASS, ${fails.length} FAIL`);
    if (fails.length) process.exitCode = 1;
  } finally {
    await c.end();
  }
}

(async () => {
  const cmd = (process.argv[2] || 'up').toLowerCase();
  try {
    if (cmd === 'up') await runUp();
    else if (cmd === 'reset') await runReset();
    else if (cmd === 'test') await runTest();
    else if (cmd === 'check') await runCheck();
    else {
      console.error('Unknown command: ' + cmd + ' (use: up | reset | test | check)');
      process.exitCode = 1;
    }
  } catch (e) {
    console.error('\nFatal:', e.message);
    if (/password|authentication|ECONNREFUSED/i.test(e.message)) {
      console.error('Check that PostgreSQL is running and .env credentials (PGSUPERPASSWORD) are correct.');
    }
    process.exitCode = 1;
  }
})();
