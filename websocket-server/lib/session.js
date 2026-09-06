'use strict';

/**
 * Session management — refresh token rotation with grace window
 * (Decision Q6 = B)
 * ─────────────────────────────────────────────────────────────
 * - Refresh token: random ≥256-bit opaque string; only SHA-256 hash is stored
 *   in public.sessions (never raw token in DB/log).
 * - Rotate on every refresh; the NEW session row stores prev_token_hash
 *   = hash(old token) for reuse detection.
 * - Grace window: 60 seconds — old token returns the same rotated result
 *   (idempotent) so parallel requests don't fail.
 * - Redis SETNX lock per old token hash + cached result (TTL = grace).
 *   If Redis is down, fall back to DB row lock (SELECT ... FOR UPDATE).
 * - Reuse of an already-rotated token after grace → revoke entire family
 *   + audit event (caller emits auth.refresh.reuse_detected).
 *
 * All DB access goes through the Supabase gateway pool with
 * SET LOCAL ROLE sheserved_app + app.user_id (Phase 13.1 identity boundary).
 *
 * Env:
 *   REFRESH_GRACE_SECONDS (default: 60)
 *   REFRESH_TTL (default: 604800 = 7 days)
 *   REDIS_HOST, REDIS_PORT, REDIS_PASSWORD
 */

const crypto = require('crypto');
const { withTransaction } = require('../db/supabase-gateway-pool');

const GRACE_SECONDS = parseInt(process.env.REFRESH_GRACE_SECONDS, 10) || 60;
const REFRESH_TTL = parseInt(process.env.REFRESH_TTL, 10) || 604800;

// System UUID used for pre-auth operations (login/refresh before identity
// is verified).  The GUC is advisory for our queries; RLS policies allow
// sheserved_app regardless, so this does not weaken authorization.
const SYSTEM_ACTOR = '00000000-0000-0000-0000-000000000000';

// Lazy Redis client — only connect when needed.
let _redis = null;
let _redisBroken = false;
async function getRedis() {
  if (_redisBroken) return null;
  if (_redis) return _redis;
  try {
    const Redis = require('ioredis');
    // Prefer REDIS_URL (project convention), fall back to host/port parts.
    const redisUrl = process.env.REDIS_URL;
    const opts = redisUrl
      ? redisUrl
      : {
          host: process.env.REDIS_HOST || 'localhost',
          port: parseInt(process.env.REDIS_PORT, 10) || 6379,
          password: process.env.REDIS_PASSWORD || undefined,
        };
    _redis = new Redis(opts, { maxRetriesPerRequest: 1, retryStrategy: () => null, lazyConnect: false });
    // If the connection fails on first command, mark broken and fall back.
    _redis.on('error', () => { _redisBroken = true; });
    return _redis;
  } catch (_) {
    _redisBroken = true;
    return null;
  }
}

async function closeSessionResources() {
  if (_redis) { try { await _redis.quit(); } catch (_) {} _redis = null; }
}

/**
 * Generate a cryptographically secure refresh token (≥256 bits = 32 bytes).
 * Returns the raw token (to send to client) — store only its hash.
 */
function generateRefreshToken() {
  return crypto.randomBytes(32).toString('base64url');
}

/**
 * Hash a refresh token for storage (SHA-256, not Argon2 — tokens are high-entropy).
 */
function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

/**
 * Create a new session row in the database.
 * Runs inside a gateway transaction (SET LOCAL ROLE sheserved_app).
 *
 * @param {object} opts
 * @param {string} opts.userId
 * @param {string} opts.refreshToken  - raw token (will be hashed)
 * @param {string} [opts.ipAddress]
 * @param {object} [opts.deviceInfo]
 * @param {string} [opts.familyId]   - rotation chain id
 * @param {string} [opts.prevTokenHash] - hash of the previous token (rotation)
 * @returns {Promise<object>} { sessionId, familyId, tokenHash, expiresAt }
 */
async function createSession({ userId, refreshToken, ipAddress, deviceInfo, familyId, prevTokenHash }) {
  const tokenHash = hashToken(refreshToken);

  const row = await withTransaction(userId || SYSTEM_ACTOR, async (client) => {
    const result = await client.query(
      `INSERT INTO public.sessions
         (user_id, token_hash, ip_address, device_info, expires_at, family_id, prev_token_hash, rotated_at)
       VALUES ($1, $2, $3, $4, now() + ($5 || ' seconds')::interval, $6::uuid, $7::text,
              CASE WHEN $7 IS NOT NULL THEN now() ELSE NULL END)
       RETURNING id, family_id, expires_at`,
      [
        userId,
        tokenHash,
        ipAddress || null,
        deviceInfo ? JSON.stringify(deviceInfo) : null,
        String(REFRESH_TTL),
        familyId || null,
        prevTokenHash || null,
      ]
    );
    return result.rows[0];
  });

  return { sessionId: row.id, familyId: row.family_id, tokenHash, expiresAt: row.expires_at };
}

/**
 * Look up a session by token hash.
 * @param {string} refreshToken - raw token
 * @returns {Promise<object|null>} session row + status or null
 */
async function lookupSession(refreshToken) {
  const tokenHash = hashToken(refreshToken);
  const row = await withTransaction(SYSTEM_ACTOR, async (client) => {
    const result = await client.query(
      `SELECT id, user_id, family_id, prev_token_hash, rotated_at, expires_at, revoked_at, token_hash
       FROM public.sessions WHERE token_hash = $1 LIMIT 1`,
      [tokenHash]
    );
    return result.rows[0];
  });
  if (!row) return null;
  if (row.revoked_at) return { ...row, status: 'revoked' };
  if (new Date(row.expires_at) < new Date()) return { ...row, status: 'expired' };
  return { ...row, status: row.rotated_at ? 'rotated' : 'valid' };
}

/**
 * Check whether a token hash has already been rotated (i.e. some newer session
 * has prev_token_hash = this hash).  Used for reuse detection.
 */
async function findRotatedDescendant(oldHash, client) {
  const result = await client.query(
    `SELECT id, user_id, family_id, rotated_at
     FROM public.sessions
     WHERE prev_token_hash = $1
     ORDER BY rotated_at DESC NULLS LAST
     LIMIT 1`,
    [oldHash]
  );
  return result.rows[0];
}

/**
 * Rotate a refresh token (Decision Q6 = B).
 *
 * Semantics:
 *  - First rotation: returns new token; new session gets prev_token_hash=old,
 *    family_id = old.family_id || old.id.
 *  - Old token used again within grace → return the same cached result.
 *  - Old token used after grace → revoke entire family, return { reused: true }.
 *  - Redis down → fall back to SELECT ... FOR UPDATE on the old session row.
 *
 * @param {string} oldRefreshToken
 * @param {object} [meta] - { ipAddress, deviceInfo }
 * @returns {Promise<object>}
 */
async function rotateRefreshToken(oldRefreshToken, meta = {}) {
  const oldHash = hashToken(oldRefreshToken);
  const lockKey = `refresh:lock:${oldHash}`;
  const resultKey = `refresh:result:${oldHash}`;
  const redis = await getRedis();

  // 1) Result cache check FIRST — within grace, the old token must return
  //    the same rotated result (idempotent for parallel/sequential requests).
  if (redis) {
    const cached = await redis.get(resultKey);
    if (cached) return { ...JSON.parse(cached), cached: true };
  }

  // 2) Acquire Redis lock (single-flight).  If lock held → wait for result.
  //    Poll up to ~3s (generous for pooler latency); if the lock is released
  //    but no result appeared, the holder finished — retry the rotate once.
  let lockAcquired = false;
  if (redis) {
    lockAcquired = await redis.set(lockKey, '1', 'PX', GRACE_SECONDS * 1000, 'NX');
    if (!lockAcquired) {
      for (let i = 0; i < 15; i++) {
        await new Promise((r) => setTimeout(r, 200));
        const retry = await redis.get(resultKey);
        if (retry) return { ...JSON.parse(retry), cached: true };
        const stillHeld = await redis.exists(lockKey);
        if (!stillHeld) break; // holder finished — fall through to retry rotate
      }
      if (lockAcquired === false) {
        // Lock released without a cached result → retry the rotation once.
        const second = await redis.set(lockKey, '1', 'PX', GRACE_SECONDS * 1000, 'NX');
        if (!second) {
          throw new Error('Refresh token rotation in progress, please retry');
        }
        lockAcquired = true;
      }
    }
  }

  try {
    const outcome = await withTransaction(SYSTEM_ACTOR, async (client) => {
      // DB-level lock as fallback when Redis is unavailable.
      // Lock the old session row so concurrent rotations serialize.
      const found = await client.query(
        `SELECT id, user_id, family_id, rotated_at, expires_at, revoked_at
         FROM public.sessions WHERE token_hash = $1 FOR UPDATE`,
        [oldHash]
      );
      const session = found.rows[0];

      if (!session) {
        // Token unknown — maybe already rotated.  Reuse detection:
        const desc = await findRotatedDescendant(oldHash, client);
        if (desc) {
          await client.query(
            `UPDATE public.sessions SET revoked_at = now(), revoke_reason = 'reuse_detected'
             WHERE family_id = $1 AND revoked_at IS NULL`,
            [desc.family_id || desc.id]
          );
          return { reused: true, sessionId: desc.id, userId: desc.user_id };
        }
        throw new Error('Invalid refresh token');
      }

      if (session.revoked_at) throw new Error('Refresh token revoked');
      if (new Date(session.expires_at) < new Date()) {
        // Expired or past grace → reuse of rotated token?
        const desc = await findRotatedDescendant(oldHash, client);
        if (desc) {
          await client.query(
            `UPDATE public.sessions SET revoked_at = now(), revoke_reason = 'reuse_detected'
             WHERE family_id = $1 AND revoked_at IS NULL`,
            [desc.family_id || session.family_id || session.id]
          );
          return { reused: true, sessionId: session.id, userId: session.user_id };
        }
        throw new Error('Refresh token expired');
      }

      if (session.rotated_at) {
        // Already rotated within grace → return existing descendant's result
        // is only available via Redis cache (checked above).  Without Redis,
        // we must not mint a second token — find the descendant and fail safe.
        const desc = await findRotatedDescendant(oldHash, client);
        if (desc) {
          return { alreadyRotated: true, sessionId: desc.id, userId: session.user_id };
        }
      }

      const familyId = session.family_id || session.id;

      // Backfill family_id on the root session so family revoke catches it.
      if (!session.family_id) {
        await client.query(
          'UPDATE public.sessions SET family_id = $1 WHERE id = $2',
          [familyId, session.id]
        );
      }

      const newRefreshToken = generateRefreshToken();
      const newHash = hashToken(newRefreshToken);

      // Insert the new session carrying prev_token_hash = old hash.
      const inserted = await client.query(
        `INSERT INTO public.sessions
           (user_id, token_hash, family_id, prev_token_hash, rotated_at,
            ip_address, device_info, expires_at)
         VALUES ($1, $2, $3, $4, now(), $5, $6,
                 now() + ($7 || ' seconds')::interval)
         RETURNING id, expires_at`,
        [
          session.user_id,
          newHash,
          familyId,
          oldHash,
          meta.ipAddress || null,
          meta.deviceInfo ? JSON.stringify(meta.deviceInfo) : null,
          String(REFRESH_TTL),
        ]
      );

      // Old session: mark rotated + shorten expiry to grace window end.
      await client.query(
        `UPDATE public.sessions
         SET rotated_at = now(), expires_at = now() + ($1 || ' seconds')::interval
         WHERE id = $2`,
        [String(GRACE_SECONDS), session.id]
      );

      return {
        refreshToken: newRefreshToken,
        sessionId: inserted.rows[0].id,
        userId: session.user_id,
        familyId,
        reused: false,
      };
    });

    // Cache the result for the grace window so parallel/sequential requests
    // with the old token get the same rotated pair.
    if (redis && outcome.refreshToken) {
      await redis.set(resultKey, JSON.stringify(outcome), 'PX', GRACE_SECONDS * 1000);
    }

    return outcome;
  } finally {
    if (redis && lockAcquired) await redis.del(lockKey);
  }
}

/**
 * Revoke a session by session ID.
 */
async function revokeSession(sessionId, reason = 'logout') {
  await withTransaction(SYSTEM_ACTOR, async (client) => {
    await client.query(
      `UPDATE public.sessions SET revoked_at = now(), revoke_reason = $1 WHERE id = $2`,
      [reason, sessionId]
    );
  });
}

/**
 * Revoke all sessions for a user (logout-all).
 */
async function revokeAllSessions(userId, reason = 'logout_all') {
  await withTransaction(userId || SYSTEM_ACTOR, async (client) => {
    await client.query(
      `UPDATE public.sessions SET revoked_at = now(), revoke_reason = $1
       WHERE user_id = $2 AND revoked_at IS NULL`,
      [reason, userId]
    );
  });
}

/**
 * List sessions for a user.
 */
async function listSessions(userId) {
  return withTransaction(userId || SYSTEM_ACTOR, async (client) => {
    const result = await client.query(
      `SELECT id, ip_address, device_info, created_at, last_active_at,
              expires_at, revoked_at, revoke_reason
       FROM public.sessions WHERE user_id = $1
       ORDER BY created_at DESC LIMIT 50`,
      [userId]
    );
    return result.rows;
  });
}

module.exports = {
  GRACE_SECONDS,
  REFRESH_TTL,
  generateRefreshToken,
  hashToken,
  createSession,
  lookupSession,
  rotateRefreshToken,
  revokeSession,
  revokeAllSessions,
  listSessions,
  closeSessionResources,
};
