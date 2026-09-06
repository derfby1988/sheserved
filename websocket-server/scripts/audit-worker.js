#!/usr/bin/env node
'use strict';

/**
 * Audit Worker — Phase 13.2 (Decision Q11 = B)
 * ─────────────────────────────────────────────────────────────
 * Consumes audit events from the durable outbox (audit_logs table)
 * using the sheserved_worker role (NOT service_role).
 *
 * Responsibilities:
 * - Read unprocessed audit events
 * - Forward to external logging/monitoring (pino, Loki, etc.)
 * - Clean up expired sessions (revoke past grace window)
 * - Mark processed events
 *
 * This worker runs as a separate process, NOT in the HTTP request path.
 *
 * Usage:
 *   node scripts/audit-worker.js
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const { Pool } = require('pg');
const pino = require('pino');

const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  redact: ['password', 'token', 'refreshToken', 'accessToken', 'secret', '*.secret', '*.password'],
});

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
  statement_timeout: 10000,
});

const POLL_INTERVAL = parseInt(process.env.AUDIT_WORKER_POLL_MS, 10) || 5000;
const BATCH_SIZE = 100;

async function processBatch() {
  const client = await pool.connect();
  try {
    // Claim undelivered rows: FOR UPDATE SKIP LOCKED so multiple worker
    // instances don't duplicate delivery.  delivered_at marks the outbox
    // as consumed — the row itself remains immutable.
    await client.query('BEGIN');
    const result = await client.query(
      `SELECT id, occurred_at, actor_id, actor_role, event_type,
              resource_type, resource_id, action, outcome, reason,
              ip_address, request_id, session_id
       FROM public.audit_logs
       WHERE delivered_at IS NULL
       ORDER BY occurred_at ASC
       LIMIT $1
       FOR UPDATE SKIP LOCKED`,
      [BATCH_SIZE]
    );

    if (result.rows.length === 0) {
      await client.query('COMMIT');
      return;
    }

    for (const row of result.rows) {
      // Forward to structured logger (pino) — redaction handles sensitive fields.
      logger.info({
        audit: true,
        eventId: row.id,
        eventType: row.event_type,
        actorId: row.actor_id,
        actorRole: row.actor_role,
        resourceType: row.resource_type,
        resourceId: row.resource_id,
        action: row.action,
        outcome: row.outcome,
        reason: row.reason,
        ipAddress: row.ip_address,
        requestId: row.request_id,
        sessionId: row.session_id,
        occurredAt: row.occurred_at,
      }, 'audit_event');
    }

    // Mark the batch as delivered.
    const ids = result.rows.map((r) => r.id);
    await client.query(
      `UPDATE public.audit_logs SET delivered_at = now() WHERE id = ANY($1::bigint[])`,
      [ids]
    );
    await client.query('COMMIT');

    logger.debug({ count: result.rows.length }, 'Processed audit batch');
  } catch (err) {
    try { await client.query('ROLLBACK'); } catch (_) { /* ignore */ }
    logger.error({ err: err.message }, 'Audit worker batch failed');
  } finally {
    client.release();
  }
}

/**
 * Clean up expired sessions that are past the grace window.
 * Marks them as revoked so they can no longer be used for refresh.
 */
async function cleanupExpiredSessions() {
  const client = await pool.connect();
  try {
    const result = await client.query(
      `UPDATE public.sessions
       SET revoked_at = now(), revoke_reason = 'expired'
       WHERE expires_at < now()
         AND revoked_at IS NULL`,
    );
    if (result.rowCount > 0) {
      logger.info({ count: result.rowCount }, 'Cleaned up expired sessions');
    }
  } catch (err) {
    logger.error({ err: err.message }, 'Session cleanup failed');
  } finally {
    client.release();
  }
}

async function main() {
  logger.info({ pollInterval: POLL_INTERVAL }, 'Audit worker started');

  // Graceful shutdown
  let running = true;
  const shutdown = async () => {
    if (!running) return;
    running = false;
    logger.info('Audit worker shutting down...');
    await pool.end();
    process.exit(0);
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);

  // Main loop
  while (running) {
    try {
      await processBatch();
      await cleanupExpiredSessions();
    } catch (err) {
      logger.error({ err: err.message }, 'Audit worker cycle error');
    }
    await new Promise((r) => setTimeout(r, POLL_INTERVAL));
  }
}

main();
