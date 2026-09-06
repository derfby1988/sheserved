#!/usr/bin/env node
'use strict';

/**
 * Phase 13.1 — Dry-run migration on Supabase (no commit)
 *
 * Wraps the Phase 13.1 migration in BEGIN ... ROLLBACK so syntax and privilege
 * errors surface WITHOUT making any permanent change.  PostgreSQL DDL is
 * transactional, so CREATE ROLE / ALTER FUNCTION OWNER TO / GRANT / REVOKE /
 * ALTER TABLE all roll back cleanly.
 *
 * Usage (with real Supabase staging credentials):
 *
 *   SUPABASE_DB_HOST=aws-0-<region>.pooler.supabase.com \
 *   SUPABASE_DB_PORT=6543 \
 *   SUPABASE_DB_NAME=postgres \
 *   SUPABASE_DB_USER=postgres.<project-ref> \
 *   SUPABASE_DB_PASSWORD=<password> \
 *   SUPABASE_DB_SSL=require \
 *   SUPABASE_DB_POOL_MAX=2 \
 *     node scripts/dry-run-phase-13-1-migration.js
 *
 * Exit code 0 = migration is safe to apply for real.
 */

// Load .env before reading SUPABASE_DB_* variables
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const MIGRATION_FILE = path.join(
  __dirname,
  '..',
  '..',
  'supabase',
  'migrations',
  '20260905140000_phase_13_1_db_identity_roles.sql'
);

const SQL = fs.readFileSync(MIGRATION_FILE, 'utf8');

if (!process.env.SUPABASE_DB_HOST) {
  console.error('Missing SUPABASE_DB_HOST. Set it in websocket-server/.env before running dry-run.');
  process.exit(1);
}

const pool = new Pool({
  host: process.env.SUPABASE_DB_HOST || process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.SUPABASE_DB_PORT, 10) || 6543,
  database: process.env.SUPABASE_DB_NAME || 'postgres',
  user: process.env.SUPABASE_DB_USER || 'postgres',
  password: process.env.SUPABASE_DB_PASSWORD || '',
  max: Math.min(parseInt(process.env.SUPABASE_DB_POOL_MAX, 10) || 2, 5),
  statement_timeout: 10000,
  connectionTimeoutMillis: 10000,
  ssl: parseSSL(process.env.SUPABASE_DB_SSL),
});

function parseSSL(value) {
  if (!value) return false;
  const lower = value.trim().toLowerCase();
  // 'require' = encrypt connection, do not verify hostname/cert.
  // This is what Supavisor shared pooler typically needs because the
  // connection terminates at an AWS load balancer whose cert does not match
  // the pooler CNAME 1:1.
  if (lower === 'true' || lower === '1') return { rejectUnauthorized: true };
  if (lower === 'false' || lower === '0') return false;
  if (lower === 'require' || lower === 'prefer') return { rejectUnauthorized: false };
  return { rejectUnauthorized: true };
}

async function main() {
  const client = await pool.connect();
  try {
    console.log('Target:', `${process.env.SUPABASE_DB_HOST || 'localhost'}:${process.env.SUPABASE_DB_PORT || 6543}/${process.env.SUPABASE_DB_NAME || 'postgres'}`);
    console.log('Dry-run migration (BEGIN ... ROLLBACK — no permanent change)...');

    // Surface RAISE NOTICE messages so skipped operations are visible.
    client.on('notice', (msg) => {
      if (msg && msg.message && msg.message.startsWith('Skipping')) {
        console.log(`   ⚠️ NOTICE: ${msg.message}`);
      }
    });

    await client.query('BEGIN');

    // Split SQL into statements to identify which one fails.
    // Simple split on semicolons at end of line — not perfect but good enough
    // for identifying the failing statement in a migration file.
    const statements = splitSqlStatements(SQL);
    console.log(`Migration has ${statements.length} statements. Executing one by one...`);

    for (let i = 0; i < statements.length; i++) {
      const stmt = statements[i].trim();
      if (!stmt) continue;
      const preview = stmt.substring(0, 80).replace(/\n/g, ' ');
      try {
        await client.query(stmt);
      } catch (err) {
        console.error(`\n❌ Statement #${i + 1} FAILED:`);
        console.error(`   Preview: ${preview}...`);
        console.error(`   Error: ${err.message}`);
        console.error(`   Full statement (${stmt.length} chars):`);
        console.error(stmt);
        console.error(`   --- END OF STATEMENT ---`);
        throw err;
      }
      // Log progress for DO blocks and major statements
      if (preview.startsWith('CREATE') || preview.startsWith('DO') || preview.startsWith('GRANT') || preview.startsWith('REVOKE') || preview.startsWith('ALTER')) {
        console.log(`   [${i + 1}/${statements.length}] OK: ${preview.substring(0, 60)}...`);
      }
    }

    console.log('✅ Migration statements executed successfully (inside transaction).');
    await client.query('ROLLBACK');
    console.log('✅ ROLLBACK complete — no permanent change. Safe to apply for real.');
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (_) { /* ignore */ }
    console.error('\n❌ Dry-run FAILED (nothing was committed):', err.message);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

/**
 * Split SQL into individual statements.
 * Handles:
 *   - Line comments (-- to end of line)
 *   - Block comments (/* *​/)
 *   - Dollar-quoted strings ($tag$ ... $tag$)
 *   - Single-quoted strings ('...')
 */
function splitSqlStatements(sql) {
  const statements = [];
  let current = '';
  let inDollarQuote = false;
  let dollarTag = '';
  let inLineComment = false;
  let inBlockComment = false;
  let inSingleQuote = false;

  for (let i = 0; i < sql.length; i++) {
    const ch = sql[i];
    const next = sql[i + 1];

    // Handle line comments
    if (inLineComment) {
      current += ch;
      if (ch === '\n') inLineComment = false;
      continue;
    }

    // Handle block comments
    if (inBlockComment) {
      current += ch;
      if (ch === '*' && next === '/') {
        current += '/';
        i++;
        inBlockComment = false;
      }
      continue;
    }

    // Handle single-quoted strings
    if (inSingleQuote) {
      current += ch;
      if (ch === "'") {
        // Check for escaped quote ''
        if (next === "'") {
          current += "'";
          i++;
        } else {
          inSingleQuote = false;
        }
      }
      continue;
    }

    // Detect start of comments
    if (ch === '-' && next === '-') {
      inLineComment = true;
      current += '--';
      i++;
      continue;
    }
    if (ch === '/' && next === '*') {
      inBlockComment = true;
      current += '/*';
      i++;
      continue;
    }

    // Detect single-quoted strings
    if (ch === "'" && !inDollarQuote) {
      inSingleQuote = true;
      current += ch;
      continue;
    }

    // Detect dollar-quoted strings
    if (!inDollarQuote) {
      const dollarMatch = sql.substring(i).match(/^\$[a-zA-Z0-9_]*\$/);
      if (dollarMatch) {
        dollarTag = dollarMatch[0];
        current += dollarTag;
        i += dollarTag.length - 1;
        inDollarQuote = true;
        continue;
      }
    } else {
      if (sql.substring(i).startsWith(dollarTag)) {
        current += dollarTag;
        i += dollarTag.length - 1;
        inDollarQuote = false;
        dollarTag = '';
        continue;
      }
    }

    current += ch;

    // Split on semicolon when not inside any quoted/commented section
    if (ch === ';' && !inDollarQuote && !inLineComment && !inBlockComment && !inSingleQuote) {
      statements.push(current);
      current = '';
    }
  }
  if (current.trim()) statements.push(current);
  return statements;
}

main();
