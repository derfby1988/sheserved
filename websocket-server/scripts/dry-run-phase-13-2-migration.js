#!/usr/bin/env node
'use strict';

/**
 * Phase 13.2 — Dry-run migration on Supabase (no commit)
 *
 * Wraps the Phase 13.2 audit_logs migration in BEGIN ... ROLLBACK so syntax
 * and privilege errors surface WITHOUT making any permanent change.
 *
 * Usage (with real Supabase staging credentials):
 *
 *   node scripts/dry-run-phase-13-2-migration.js
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
  '20260906120000_phase_13_2_audit_logs.sql'
);

const pool = new Pool({
  host: process.env.SUPABASE_DB_HOST || 'localhost',
  port: parseInt(process.env.SUPABASE_DB_PORT, 10) || 6543,
  database: process.env.SUPABASE_DB_NAME || 'postgres',
  user: process.env.SUPABASE_DB_USER || 'postgres',
  password: process.env.SUPABASE_DB_PASSWORD,
  ssl: process.env.SUPABASE_DB_SSL === 'require'
    ? { rejectUnauthorized: false }
    : process.env.SUPABASE_DB_SSL === 'true'
      ? { rejectUnauthorized: true }
      : false,
  max: 2,
  statement_timeout: parseInt(process.env.SUPABASE_DB_STATEMENT_TIMEOUT_MS, 10) || 10000,
});

const SQL = fs.readFileSync(MIGRATION_FILE, 'utf8');

async function main() {
  const client = await pool.connect();
  try {
    console.log('Target:', `${process.env.SUPABASE_DB_HOST || 'localhost'}:${process.env.SUPABASE_DB_PORT || 6543}/${process.env.SUPABASE_DB_NAME || 'postgres'}`);
    console.log('Dry-run Phase 13.2 migration (BEGIN ... ROLLBACK — no permanent change)...');

    client.on('notice', (msg) => {
      if (msg && msg.message && msg.message.startsWith('Skipping')) {
        console.log(`   ⚠️ NOTICE: ${msg.message}`);
      }
    });

    await client.query('BEGIN');

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
 * Handles line comments, block comments, dollar-quoted strings, single-quoted strings.
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

    if (inLineComment) {
      current += ch;
      if (ch === '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      current += ch;
      if (ch === '*' && next === '/') { current += '/'; i++; inBlockComment = false; }
      continue;
    }
    if (inSingleQuote) {
      current += ch;
      if (ch === "'") {
        if (next === "'") { current += "'"; i++; }
        else inSingleQuote = false;
      }
      continue;
    }
    if (ch === '-' && next === '-') { inLineComment = true; current += '--'; i++; continue; }
    if (ch === '/' && next === '*') { inBlockComment = true; current += '/*'; i++; continue; }
    if (ch === "'" && !inDollarQuote) { inSingleQuote = true; current += ch; continue; }

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
    if (ch === ';' && !inDollarQuote && !inLineComment && !inBlockComment && !inSingleQuote) {
      statements.push(current);
      current = '';
    }
  }
  if (current.trim()) statements.push(current);
  return statements;
}

main();
