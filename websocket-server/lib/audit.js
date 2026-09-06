'use strict';

/**
 * Audit event logger — durable queue/outbox pattern (Decision Q11 = B)
 * ─────────────────────────────────────────────────────────────
 * Auth handlers write audit events to a durable outbox (audit_logs table)
 * in the same transaction as the operation.  A separate audit-worker
 * (using sheserved_worker role) processes the queue asynchronously.
 *
 * The HTTP request handler does NOT hold service_role — it uses
 * sheserved_app via the gateway pool, which has INSERT-only on audit_logs.
 *
 * Redaction: never store password, token, OTP, signing key, or PII.
 */

const { withTransaction } = require('../db/supabase-gateway-pool');

// Event types per plan Phase 13.2
const EVENT_TYPES = {
  AUTH_LOGIN_SUCCESS: 'auth.login.success',
  AUTH_LOGIN_FAILURE: 'auth.login.failure',
  AUTH_REFRESH_SUCCESS: 'auth.refresh.success',
  AUTH_REFRESH_REUSE_DETECTED: 'auth.refresh.reuse_detected',
  AUTH_LOGOUT: 'auth.logout',
  AUTH_SESSION_REVOKED: 'auth.session.revoked',
  AUTH_PASSWORD_CHANGED: 'auth.password.changed',
  AUTHZ_DENIED: 'authz.denied',
  // Fitness events (used in later phases)
  FITNESS_SESSION_CREATED: 'fitness.session.created',
  FITNESS_SESSION_CANCELLED: 'fitness.session.cancelled',
  FITNESS_BOOKING_APPROVED: 'fitness.booking.approved',
  FITNESS_BOOKING_REJECTED: 'fitness.booking.rejected',
  FITNESS_MEMBER_REMOVED: 'fitness.member.removed',
  FITNESS_USER_BLOCKED: 'fitness.user.blocked',
};

/**
 * Write an audit event.
 * Uses the gateway pool (sheserved_app role) which has INSERT on audit_logs.
 *
 * @param {object} event
 * @param {string} event.eventType     - e.g. 'auth.login.success'
 * @param {string} [event.actorId]     - user UUID
 * @param {string} [event.actorRole]   - user role
 * @param {string} [event.resourceType]
 * @param {string} [event.resourceId]
 * @param {string} [event.action]      - read|create|update|delete|approve|deny
 * @param {string} [event.outcome]     - success|denied|error (default: success)
 * @param {string} [event.reason]
 * @param {object} [event.beforeState]
 * @param {object} [event.afterState]
 * @param {string} [event.ipAddress]
 * @param {string} [event.userAgent]
 * @param {string} [event.requestId]
 * @param {string} [event.sessionId]
 * @param {object} [pool]              - optional external pool (for same-txn audit)
 * @returns {Promise<void>}
 */
async function writeAuditEvent(event) {
  const {
    eventType,
    actorId,
    actorRole,
    resourceType,
    resourceId,
    action,
    outcome = 'success',
    reason,
    beforeState,
    afterState,
    ipAddress,
    userAgent,
    requestId,
    sessionId,
  } = event;

  if (!eventType) {
    throw new Error('eventType is required for audit event');
  }

  await withTransaction(actorId || '00000000-0000-0000-0000-000000000000', async (client) => {
    await client.query(
      `INSERT INTO public.audit_logs
         (event_type, actor_id, actor_role, resource_type, resource_id,
          action, outcome, reason, before_state, after_state,
          ip_address, user_agent, request_id, session_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)`,
      [
        eventType,
        actorId || null,
        actorRole || null,
        resourceType || null,
        resourceId || null,
        action || null,
        outcome,
        reason || null,
        beforeState ? JSON.stringify(beforeState) : null,
        afterState ? JSON.stringify(afterState) : null,
        ipAddress || null,
        userAgent || null,
        requestId || null,
        sessionId || null,
      ]
    );
  });
}

/**
 * Extract audit metadata from an Express request.
 * @param {object} req - Express request
 * @returns {object} { ipAddress, userAgent, requestId }
 */
function extractRequestMeta(req) {
  return {
    ipAddress: req.ip || (req.socket && req.socket.remoteAddress) || null,
    userAgent: req.get('user-agent') || null,
    requestId: req.id || (req.headers && req.headers['x-request-id']) || null,
  };
}

module.exports = {
  EVENT_TYPES,
  writeAuditEvent,
  extractRequestMeta,
};
