'use strict';

/**
 * Phase 13.3 — Socket.IO Connection Authentication
 * ─────────────────────────────────────────────────────────────
 * Trusted actor = signed Backend access token ONLY (verify signature,
 * kid, iss, aud, exp, typ='access', session revoke, active user).
 *
 * Identity sources on the socket:
 *   socket.identitySource = 'jwt'      — verified Backend token (trusted)
 *                         'legacy'     — auth.userId / x-user-id compat
 *                                        window (Phase 13.3 → 13.5, NOT
 *                                        a trusted actor)
 *                         'anonymous'  — no credentials (public allowlist
 *                                        events only)
 *
 * Compatibility policy (config/rollout-flags.js):
 *   STRICT_SOCKET_AUTH=true   → legacy handshake rejected (fail closed)
 *   STRICT_SOCKET_EVENTS=...  → per-event verified-identity requirement
 *
 * Match_Sport_PLAN Phase 13.3 ข้อห้าม: ห้ามใช้ handshake auth.userId,
 * x-user-id หรือ payload userId เป็น trusted actor.
 */

const { verifyAccessToken } = require('../lib/jwt');
const {
  strictSocketAuthEnabled,
  isStrictSocketEvent,
} = require('../config/rollout-flags');

/**
 * Verify a Backend-JWT-authenticated identity against Supabase:
 * user must exist + be active, session must not be revoked.
 * Same contract as middleware/auth.js verifyToken.
 * @returns {Promise<{ok:true,user:object}|{ok:false,status:number,error:string}>}
 */
async function verifyJwtSubject({ userId, sessionId }) {
  try {
    // Lazy require — same pattern as middleware/auth.js so tests can stub
    // the gateway pool and so the pool initializes on first use.
    const { withTransaction } = require('../db/supabase-gateway-pool');
    return await withTransaction(userId, async (client) => {
      const u = await client.query(
        'SELECT id, is_active, user_category_id FROM public.users WHERE id = $1',
        [userId]
      );
      if (u.rows.length === 0) {
        return { ok: false, status: 401, error: 'User not found' };
      }
      if (!u.rows[0].is_active) {
        return { ok: false, status: 403, error: 'User is inactive' };
      }
      if (sessionId) {
        const s = await client.query(
          'SELECT revoked_at FROM public.sessions WHERE id = $1',
          [sessionId]
        );
        if (s.rows.length > 0 && s.rows[0].revoked_at != null) {
          return { ok: false, status: 401, error: 'Session revoked' };
        }
      }
      return { ok: true, user: u.rows[0] };
    });
  } catch (err) {
    console.error('[SocketAuth] Gateway DB error:', err.message);
    return { ok: false, status: 500, error: 'Authentication backend error' };
  }
}

/**
 * socketAuthMiddleware({ getPool, supabaseForSync }) → io.use() middleware.
 *
 * - auth.token present → MUST verify as Backend JWT; invalid/forged/expired
 *   = hard reject (never falls back to legacy identity).
 * - else auth.userId / x-user-id header → legacy compat identity
 *   (rejected when STRICT_SOCKET_AUTH=true).
 * - else → anonymous.
 *
 * `getPool` is a thunk (() => pool) because the DB pool is initialized
 * after the middleware is wired — it must resolve per-connection.
 */
function socketAuthMiddleware({ getPool, supabaseForSync }) {
  return async (socket, next) => {
    try {
      const handshakeToken = socket.handshake.auth?.token;

      // ── 1. Signed Backend access token — the ONLY trusted identity ──
      if (handshakeToken) {
        let payload;
        try {
          payload = verifyAccessToken(`${handshakeToken}`);
        } catch (err) {
          console.warn(`[SocketAuth] token rejected: ${err.message}`);
          return next(new Error('Authentication failed: invalid or expired token'));
        }

        const verified = await verifyJwtSubject({
          userId: payload.sub,
          sessionId: payload.sid || null,
        });
        if (!verified.ok) {
          return next(new Error(`Authentication failed: ${verified.error}`));
        }

        socket.user = {
          id: verified.user.id,
          role: verified.user.user_category_id || payload.role || 'consumer',
        };
        socket.userId = verified.user.id;
        socket.userRole =
          verified.user.user_category_id || payload.role || 'consumer';
        socket.sessionId = payload.sid || null;
        socket.identitySource = 'jwt';
        return next();
      }

      // ── 2. Legacy handshake (compat window only) ──
      let userId =
        socket.handshake.auth?.userId ||
        socket.handshake.headers?.['x-user-id'] ||
        null;

      if (!userId && socket.handshake.headers?.authorization) {
        // Bearer header present but unusable as trusted identity.
        // Decode sub for legacy convenience only — flagged 'legacy',
        // never 'jwt' (no signature verification happened here).
        const authHeader = socket.handshake.headers.authorization;
        if (authHeader.startsWith('Bearer ')) {
          try {
            const parts = authHeader.slice(7).split('.');
            if (parts.length === 3) {
              const claims = JSON.parse(
                Buffer.from(parts[1], 'base64url').toString('utf8')
              );
              if (claims.sub) userId = claims.sub;
            }
          } catch (_) {
            // malformed — stay anonymous/legacy below
          }
        }
      }

      if (userId) {
        if (strictSocketAuthEnabled()) {
          console.warn('[SocketAuth] legacy handshake rejected (STRICT_SOCKET_AUTH)');
          return next(
            new Error('Authentication failed: verified login required')
          );
        }

        // Compat lookup — user must exist and be active.
        // user_category_id (fine-grained, JWT source of truth) is used
        // for consistency with the HTTP middleware — fixes the old
        // coarse `role` column divergence.
        let userRow = null;
        if (supabaseForSync) {
          const { data, error } = await supabaseForSync
            .from('users')
            .select('id, is_active, user_category_id')
            .eq('id', userId)
            .maybeSingle();
          if (error) throw error;
          userRow = data;
        } else {
          const localPool = getPool ? getPool() : null;
          if (localPool) {
            const result = await localPool.query(
              'SELECT id, is_active, user_category_id FROM users WHERE id = $1',
              [userId]
            );
            userRow = result.rows[0] || null;
          }
        }

        if (!userRow) {
          return next(new Error('Authentication failed: User not found'));
        }
        if (!userRow.is_active) {
          return next(new Error('Authentication failed: User is inactive'));
        }
        socket.user = {
          id: userRow.id,
          role: userRow.user_category_id || 'consumer',
        };
        socket.userId = userRow.id;
        socket.userRole = userRow.user_category_id || 'consumer';
        socket.sessionId = null;
        socket.identitySource = 'legacy';
        return next();
      }

      // ── 3. Anonymous — public allowlist events only ──
      socket.user = null;
      socket.userId = null;
      socket.userRole = null;
      socket.sessionId = null;
      socket.identitySource = 'anonymous';
      next();
    } catch (err) {
      console.error('[SocketAuth] Connection auth error:', err.message);
      next(new Error('Internal server error during authentication'));
    }
  };
}

/**
 * Has this socket a verified (trusted-actor) identity?
 */
function isVerifiedSocket(socket) {
  return socket.identitySource === 'jwt' && !!socket.userId;
}

/**
 * Event-level guard for handlers: identity-required events accept verified
 * or legacy sockets (compat window); strict events (STRICT_SOCKET_EVENTS /
 * STRICT_SOCKET_AUTH) accept verified only.
 *
 * @returns {null | {code: string, message: string}} null when allowed
 */
function checkEventIdentity(socket, eventName) {
  if (isStrictSocketEvent(eventName)) {
    if (!isVerifiedSocket(socket)) {
      return {
        code: 'VERIFIED_REQUIRED',
        message: 'verified login required for this action',
      };
    }
    return null;
  }
  if (!socket.userId) {
    return { code: 'AUTH_REQUIRED', message: 'login required for this action' };
  }
  return null;
}

/**
 * Claimed-actor check: payload userId must equal socket.userId.
 * Verified sockets are checked unconditionally; legacy sockets too
 * (compat keeps existing defense-in-depth semantics).
 */
function claimedActorMismatch(socket, claimedUserId) {
  if (claimedUserId == null || claimedUserId === '') return false;
  return !!socket.userId && `${socket.userId}` !== `${claimedUserId}`;
}

module.exports = {
  socketAuthMiddleware,
  verifyJwtSubject,
  isVerifiedSocket,
  checkEventIdentity,
  claimedActorMismatch,
};
