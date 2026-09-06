'use strict';

/**
 * Supabase Direct Pool / Gateway Transaction Adapter
 * Phase 13.1 — Trusted Backend Identity Bridge
 *
 * Provides a dedicated `pg` Pool that connects directly to Supabase Postgres
 * through the transaction pooler (port 6543 by default).  Every gateway
 * mutation runs inside a single transaction with:
 *
 *   BEGIN;
 *   SET LOCAL ROLE sheserved_app;        -- drop from gateway login to app permission role
 *   SET LOCAL app.user_id = '<uuid>';      -- verified user identity
 *   SET LOCAL app.session_id = '<uuid>';   -- optional session correlation
 *   SET LOCAL app.role = '<role>';         -- optional claim role
 *   -- business query / RPC
 *   COMMIT;
 *
 * PostgREST cannot preserve `SET LOCAL` across separate HTTP calls because
 * each RPC is its own transaction.  This adapter is required for mutations
 * that rely on `app.current_user_id()` / `app.require_current_user_id()`.
 *
 * Usage:
 *   const { withTransaction, query } = require('./db/supabase-gateway-pool');
 *   const result = await withTransaction(req.userId, async (client) => {
 *     const { rows } = await client.query('SELECT app.require_current_user_id()');
 *     return rows[0];
 *   });
 */

const fs = require('fs');
const { Pool } = require('pg');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const DEFAULT_GW_CONFIG = buildDefaultGwConfig();

function buildDefaultGwConfig() {
  const port = parseInt(process.env.SUPABASE_DB_PORT, 10)
    || parseInt(process.env.DB_PORT, 10)
    || 6543;

  return {
    host: process.env.SUPABASE_DB_HOST || process.env.DB_HOST || 'localhost',
    port,
    database: process.env.SUPABASE_DB_NAME || process.env.DB_NAME || 'postgres',
    user: process.env.SUPABASE_DB_USER || 'postgres',
    password: process.env.SUPABASE_DB_PASSWORD || process.env.DB_PASSWORD || '',
    max: parseInt(process.env.SUPABASE_DB_POOL_MAX, 10)
      || parseInt(process.env.DB_POOL_MAX, 10)
      || 20,
    statement_timeout: parseInt(process.env.SUPABASE_DB_STATEMENT_TIMEOUT_MS, 10)
      || parseInt(process.env.DB_STATEMENT_TIMEOUT_MS, 10)
      || 30000,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
    // Supabase hosted (and Supavisor shared pooler) requires TLS.
    ssl: parseSSL(process.env.SUPABASE_DB_SSL, process.env.SUPABASE_DB_SSL_CA),
  };
}

/**
 * Parse SSL env value.
 *
 * Supports:
 *   true / 1           -> TLS with certificate verification (direct connection)
 *   false / 0          -> no TLS (local development only)
 *   require            -> TLS encrypted, no certificate verification
 *                         (default for Supavisor shared pooler, where the
 *                         load balancer's cert may not match the pooler host)
 *   prefer             -> try TLS, allow fallback (no cert verification)
 *   JSON object        -> pass through to node TLS (e.g. {"ca":"..."})
 *
 * SUPABASE_DB_SSL_CA -> path to PEM CA file; if provided, sets the ca option
 *                       and enables verification unless mode says otherwise.
 */
function parseSSL(value, caPath) {
  if (!value) return false;

  const lower = value.trim().toLowerCase();
  let result = false;

  if (lower === 'true' || lower === '1') {
    result = { rejectUnauthorized: true };
  } else if (lower === 'false' || lower === '0') {
    result = false;
  } else if (lower === 'require') {
    result = { rejectUnauthorized: false };
  } else if (lower === 'prefer') {
    result = { rejectUnauthorized: false };
  } else {
    try {
      result = JSON.parse(value);
    } catch {
      result = { rejectUnauthorized: true };
    }
  }

  if (result && caPath) {
    try {
      result = {
        ...result,
        ca: fs.readFileSync(caPath),
      };
    } catch (err) {
      console.error('[SupabaseGatewayPool] Failed to read SUPABASE_DB_SSL_CA:', err.message);
      throw err;
    }
  }

  return result;
}

function assertUuid(value, fieldName) {
  if (typeof value !== 'string' || !UUID_RE.test(value)) {
    const err = new Error(`Invalid ${fieldName}: expected UUID`);
    err.code = 'INVALID_UUID';
    throw err;
  }
}

let pool = null;

/**
 * Lazily create and return the Supabase gateway pool.
 */
function getPool() {
  if (!pool) {
    pool = new Pool(DEFAULT_GW_CONFIG);

    pool.on('error', (err) => {
      console.error('[SupabaseGatewayPool] Unexpected pool error:', err.message);
    });
  }
  return pool;
}

/**
 * Run a callback inside a single transaction with identity context set.
 * The callback receives a `client` on which all queries share the same
 * transaction and `app.*` GUCs.
 *
 * @param {string} userId     Verified user UUID (required)
 * @param {Function} callback async (client) => any
 * @param {Object}   [context]  Optional context: sessionId, role, organizationId, branchId
 * @returns {Promise<any>}
 */
async function withTransaction(userId, callback, context = {}) {
  assertUuid(userId, 'userId');
  if (context.sessionId) assertUuid(context.sessionId, 'sessionId');

  const client = await getPool().connect();
  try {
    await client.query('BEGIN');
    await client.query('SET LOCAL ROLE sheserved_app');
    await client.query("SELECT set_config('app.user_id', $1, true)", [userId]);

    if (context.sessionId) {
      await client.query("SELECT set_config('app.session_id', $1, true)", [context.sessionId]);
    } else {
      await client.query("SELECT set_config('app.session_id', '', true)");
    }

    if (context.role) {
      await client.query("SELECT set_config('app.role', $1, true)", [context.role]);
    } else {
      await client.query("SELECT set_config('app.role', '', true)");
    }

    if (context.organizationId) {
      await client.query("SELECT set_config('app.organization_id', $1, true)", [context.organizationId]);
    } else {
      await client.query("SELECT set_config('app.organization_id', '', true)");
    }

    if (context.branchId) {
      await client.query("SELECT set_config('app.branch_id', $1, true)", [context.branchId]);
    } else {
      await client.query("SELECT set_config('app.branch_id', '', true)");
    }

    const result = await callback(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    try {
      await client.query('ROLLBACK');
    } catch (rbErr) {
      console.error('[SupabaseGatewayPool] ROLLBACK failed:', rbErr.message);
    }
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Convenience wrapper for a single query inside an identity transaction.
 */
async function query(text, params, userId, context = {}) {
  return withTransaction(userId, async (client) => {
    const { rows } = await client.query(text, params);
    return rows;
  }, context);
}

/**
 * Close the pool gracefully.  Used in test teardown and graceful shutdown.
 */
async function closePool() {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

module.exports = {
  getPool,
  withTransaction,
  query,
  closePool,
};
