'use strict';

/**
 * Phase 13.3 Step 7 — Socket Revocation Propagation
 * ─────────────────────────────────────────────────────────────
 * เมื่อ session ถูก revoke (logout-all / reuse_detected / admin revoke)
 * socket ที่ผูกกับ user นั้นต้องถูกตัดการเชื่อมต่อภายใน ≤ cache window
 *
 * Mechanism:
 *   publishRevocation({userId, sessionId})  — เรียกจาก lib/session.js
 *     → Redis PUBLISH 'socket:revoke' (ทุก instance ได้รับ)
 *     → subscriber disconnect sockets ที่ socket.userId ตรง
 *       (sessionId ตรง = เฉพาะ session นั้น; null = ทุก session ของ user)
 *     → invalidate membership cache `room:member:*:{userId}`
 *
 * Multi-instance safe ผ่าน Redis Pub/Sub; single-instance (no Redis)
 * ทำงาน local ผ่าน handleRevocation ตรงๆ
 */

const REVOKE_CHANNEL = 'socket:revoke';

let _io = null;
let _subscriber = null;
let _redis = null;

function _getRedis() {
  if (_redis) return _redis;
  try {
    ({ redis: _redis } = require('../middleware/redis-client'));
  } catch (_) {
    _redis = null;
  }
  return _redis;
}

/**
 * Handle a revocation event on THIS instance: disconnect matching sockets
 * and drop their room-membership cache entries.
 */
async function handleRevocation({ userId, sessionId = null }) {
  if (!userId) return;

  if (_io) {
    for (const [, socket] of _io.sockets.sockets) {
      if (`${socket.userId}` !== `${userId}`) continue;
      if (sessionId && socket.sessionId && `${socket.sessionId}` !== `${sessionId}`) continue;
      socket.emit('session-revoked', { reason: 'session_revoked' });
      socket.disconnect(true);
      console.log(`[Revocation] force-disconnected socket=${socket.id} user=${userId} session=${sessionId || '*'}`);
    }
  }

  try {
    const { invalidateMemberCacheForUser } = require('./room-authorization');
    await invalidateMemberCacheForUser(userId);
  } catch (err) {
    console.warn('[Revocation] member cache invalidation failed:', err.message);
  }
}

/**
 * initSocketRevocation(io) — wire the Redis subscriber.  Call once after
 * the Socket.IO server exists.  Safe when Redis is unavailable (propagation
 * degrades to local-instance only via publishRevocation fallback).
 */
function initSocketRevocation(io) {
  _io = io;
  const redis = _getRedis();
  if (!redis) {
    console.warn('[Revocation] Redis not available — revocation propagates locally only');
    return;
  }
  try {
    _subscriber = redis.duplicate();
    _subscriber.subscribe(REVOKE_CHANNEL, (err) => {
      if (err) console.error('[Revocation] subscribe failed:', err.message);
      else console.log('[Revocation] subscribed to', REVOKE_CHANNEL);
    });
    _subscriber.on('message', (channel, message) => {
      if (channel !== REVOKE_CHANNEL) return;
      try {
        handleRevocation(JSON.parse(message));
      } catch (err) {
        console.error('[Revocation] malformed message:', err.message);
      }
    });
  } catch (err) {
    console.error('[Revocation] init failed:', err.message);
    _subscriber = null;
  }
}

/**
 * Publish a revocation.  Called by lib/session.js after DB update.
 * Non-blocking / best-effort — revocation is already enforced at
 * verifyToken/verifyJwtSubject on the next request; this only shortens
 * the live-socket window.
 */
async function publishRevocation({ userId, sessionId = null }) {
  const redis = _getRedis();
  let published = false;
  if (redis) {
    try {
      await redis.publish(REVOKE_CHANNEL, JSON.stringify({ userId, sessionId }));
      published = true;
    } catch (err) {
      console.warn('[Revocation] publish failed:', err.message);
    }
  }
  // No subscriber (or no Redis) → handle locally so single-instance dev
  // still gets immediate propagation.
  if (!published || !_subscriber) {
    await handleRevocation({ userId, sessionId });
  }
}

function shutdown() {
  if (_subscriber) {
    _subscriber.unsubscribe(REVOKE_CHANNEL).catch(() => {});
    _subscriber.disconnect();
    _subscriber = null;
  }
}

module.exports = { initSocketRevocation, publishRevocation, handleRevocation, shutdown };
