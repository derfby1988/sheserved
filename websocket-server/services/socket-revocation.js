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
const SUBSCRIBE_RETRY_MS = 2000;

let _io = null;
let _subscriber = null;
let _redis = null;
let _subscribeRetryTimer = null;

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

/** Wire one dedicated subscriber connection to the revoke channel. */
function _subscribe(redis) {
  try {
    _subscriber = redis.duplicate();
    _subscriber.on('error', (err) => {
      console.warn('[Revocation] subscriber error:', err.message);
    });
    _subscriber.on('message', (channel, message) => {
      if (channel !== REVOKE_CHANNEL) return;
      try {
        handleRevocation(JSON.parse(message));
      } catch (err) {
        console.error('[Revocation] malformed message:', err.message);
      }
    });
    _subscriber.subscribe(REVOKE_CHANNEL, (err) => {
      if (!err) {
        console.log('[Revocation] subscribed to', REVOKE_CHANNEL);
        return;
      }
      console.error('[Revocation] subscribe failed:', err.message);
      // Leave no half-open subscriber: publishRevocation() treats a non-null
      // _subscriber as "propagation handled" and would skip the local
      // fallback, silently dropping live revocations on this instance.
      _subscriber = null;
      _scheduleSubscribeRetry(redis);
    });
  } catch (err) {
    console.error('[Revocation] init failed:', err.message);
    _subscriber = null;
    _scheduleSubscribeRetry(redis);
  }
}

// initSocketRevocation() runs while the shared Redis client is still
// connecting (enableOfflineQueue=false), so the first subscribe can fail.
// Retry until the client is ready instead of degrading for the whole run.
function _scheduleSubscribeRetry(redis) {
  if (_subscribeRetryTimer) return;
  _subscribeRetryTimer = setTimeout(() => {
    _subscribeRetryTimer = null;
    if (_subscriber) return;
    if (redis.status !== 'ready') {
      _scheduleSubscribeRetry(redis);
      return;
    }
    _subscribe(redis);
  }, SUBSCRIBE_RETRY_MS);
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
  _subscribe(redis);
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
  if (_subscribeRetryTimer) {
    clearTimeout(_subscribeRetryTimer);
    _subscribeRetryTimer = null;
  }
  if (_subscriber) {
    _subscriber.unsubscribe(REVOKE_CHANNEL).catch(() => {});
    _subscriber.disconnect();
    _subscriber = null;
  }
}

module.exports = { initSocketRevocation, publishRevocation, handleRevocation, shutdown };
