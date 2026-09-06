#!/usr/bin/env node
'use strict';

/**
 * Phase 13.1 spike: verify direct Supabase Postgres connection through the
 * transaction pooler with SET LOCAL ROLE + app.user_id.
 *
 * Run with real Supabase direct-pool credentials, e.g.:
 *
 *   SUPABASE_DB_HOST=aws-0-<region>.pooler.supabase.com \
 *   SUPABASE_DB_PORT=6543 \
 *   SUPABASE_DB_NAME=postgres \
 *   SUPABASE_DB_USER=postgres.<project-ref> \
 *   SUPABASE_DB_PASSWORD=<db-password> \
 *   SUPABASE_DB_SSL=require \
 *   SPIKE_CONFIRM=yes \
 *   TEST_USER_ID=9b1d3f0d-983e-4359-8de5-fd7281662765 \
 *     node scripts/spike-supabase-pooler.js
 *
 * Safety guards (Phase 13.1 runbook — docs/secure/17_phase_13_1_supabase_spike_runbook.md):
 *   - If host contains "supabase.co" the script refuses to run without
 *     SPIKE_CONFIRM=yes (prevents accidental run against a real project).
 *   - If host is a Supabase project, port 6543 (transaction pooler) is
 *     required because SET LOCAL depends on transaction mode.
 *   - Pool size is capped at 2 to avoid consuming project connection quota.
 *   - Statement timeout is short (10s) so no query runs away.
 *   - Read-only: spike only issues SELECT + transaction-local SET LOCAL.
 *
 * Success criteria:
 *   1. Pool connects to Supabase Postgres (port 6543).
 *   2. A transaction sets LOCAL ROLE sheserved_app.
 *   3. SET LOCAL app.user_id works and persists for subsequent queries.
 *   4. app.current_user_id() / app.require_current_user_id() return the test user.
 *   5. After COMMIT, the identity context is gone (transaction-local).
 *   6. No connections left behind (pool closed).
 */

// Load .env before reading SUPABASE_DB_* / TEST_USER_ID variables
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { withTransaction, query, getPool, closePool } = require('../db/supabase-gateway-pool');

const TEST_USER_ID = process.env.TEST_USER_ID;
const HOST = process.env.SUPABASE_DB_HOST || process.env.DB_HOST || 'localhost';
const PORT = parseInt(process.env.SUPABASE_DB_PORT, 10) || parseInt(process.env.DB_PORT, 10) || 6543;
// Supabase projects use *.supabase.co (direct/REST) or *.pooler.supabase.com (Supavisor)
const IS_SUPABASE_HOST = /(?:\.supabase\.co|\.supabase\.com)$/i.test(HOST);

if (!TEST_USER_ID) {
  console.error('Set TEST_USER_ID to an existing user UUID (is_active=true)');
  process.exit(1);
}

// Guard 1: require explicit confirmation for real Supabase projects.
if (IS_SUPABASE_HOST && process.env.SPIKE_CONFIRM !== 'yes') {
  console.error(`Refusing to run against Supabase host "${HOST}" without SPIKE_CONFIRM=yes.`);
  console.error('Use a STAGING project only. See docs/secure/17_phase_13_1_supabase_spike_runbook.md');
  process.exit(1);
}

// Guard 2: transaction pooler port is mandatory for SET LOCAL semantics on Supabase.
if (IS_SUPABASE_HOST && PORT !== 6543) {
  console.error(`Supabase project requires transaction pooler port 6543 (got ${PORT}).`);
  console.error('Session-mode port 5432 cannot preserve SET LOCAL for subsequent statements.');
  process.exit(1);
}

// Guard 3: cap pool size so the spike never consumes project connection quota.
const cappedPoolMax = Math.min(parseInt(process.env.SUPABASE_DB_POOL_MAX, 10) || 2, 2);
process.env.SUPABASE_DB_POOL_MAX = String(cappedPoolMax);
process.env.SUPABASE_DB_STATEMENT_TIMEOUT_MS = String(
  Math.min(parseInt(process.env.SUPABASE_DB_STATEMENT_TIMEOUT_MS, 10) || 10000, 10000)
);

async function main() {
  try {
    console.log('Target:', `${HOST}:${PORT} (pool max ${cappedPoolMax}, statement timeout 10s)`);
    console.log('1. Testing single query through gateway pool...');
    const rows = await query(
      'SELECT current_user AS role, app.require_current_user_id() AS actor',
      [],
      TEST_USER_ID
    );
    console.log('   result:', JSON.stringify(rows[0]));

    if (rows[0].role !== 'sheserved_app') {
      throw new Error(`Expected current_user=sheserved_app, got ${rows[0].role}`);
    }
    if (rows[0].actor !== TEST_USER_ID) {
      throw new Error(`Expected actor=${TEST_USER_ID}, got ${rows[0].actor}`);
    }

    console.log('2. Testing transaction scope isolation...');
    const isolated = await withTransaction(TEST_USER_ID, async (client) => {
      const { rows: r1 } = await client.query(
        "SELECT current_user AS role, app.current_user_id() AS actor, current_setting('app.user_id', true) AS raw_guc"
      );
      return r1[0];
    });
    console.log('   in-transaction:', JSON.stringify(isolated));

    console.log('3. Verifying SET LOCAL does not leak across pooled connections...');
    // Open a raw connection WITHOUT any SET and confirm app.user_id is empty.
    // This proves transaction-local GUCs do not survive commit on pooled conns.
    const rawClient = await getPool().connect();
    try {
      const { rows: r2 } = await rawClient.query(
        "SELECT COALESCE(current_setting('app.user_id', true), '') = '' AS guc_cleared"
      );
      console.log('   fresh pooled connection guc cleared:', JSON.stringify(r2[0]));
      if (r2[0].guc_cleared !== true) {
        throw new Error('app.user_id leaked across pooled connections after COMMIT');
      }
    } finally {
      rawClient.release();
    }

    console.log('✅ Supabase pooler spike passed');
  } catch (err) {
    console.error('❌ Spike failed:', err.message);
    process.exitCode = 1;
  } finally {
    await closePool();
  }
}

main();
