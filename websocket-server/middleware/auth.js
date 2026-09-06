/**
 * Authentication & Authorization Middleware
 * ─────────────────────────────────────────────────────────────
 * Phase 13.2 — JWT signature verification (HS256 dual-key, Decision Q3=A)
 *
 * Verifies user identity via signed JWT (Authorization: Bearer).
 * Falls back to x-user-id ONLY during compatibility window (Phase 13.2-13.5).
 * After Phase 13.5 cutover, x-user-id will be rejected entirely.
 *
 * Security:
 * - Algorithm allowlist: HS256 only (reject 'none' and asymmetric).
 * - Known kid only (active/previous).
 * - iss, aud, exp verified.
 * - Session revoke check via public.sessions.
 * - Active user check via public.users.
 *
 * Dependencies: jsonwebtoken, pg (existing)
 */

'use strict';

const { verifyAccessToken } = require('../lib/jwt');

/**
 * Extract and verify JWT from Authorization header.
 * During compatibility window, also accepts x-user-id (legacy, unsigned).
 * Returns { userId, role, sessionId } or null.
 */
async function _extractVerifiedIdentity(req) {
  // 1. Authorization: Bearer <token> — PREFERRED (signed JWT)
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    try {
      const payload = verifyAccessToken(token);
      return {
        userId: payload.sub,
        role: payload.role || 'consumer',
        sessionId: payload.sid || null,
        source: 'jwt',
      };
    } catch (err) {
      // Token verification failed — do NOT fall back to x-user-id.
      // This is a hard rejection: invalid token = 401, not anonymous.
      throw new Error(`JWT verification failed: ${err.message}`);
    }
  }

  // 2. x-user-id — LEGACY (compatibility window only, Phase 13.2-13.5)
  //    After Phase 13.5 cutover, this path will be removed.
  const legacyUserId = req.headers['x-user-id'];
  if (legacyUserId && typeof legacyUserId === 'string' && legacyUserId.length > 0) {
    return {
      userId: legacyUserId,
      role: null, // will be looked up from DB
      sessionId: null,
      source: 'legacy_header',
    };
  }

  return null;
}

/**
 * verifyToken(pool) — Express middleware
 * Verifies JWT signature (or legacy x-user-id during compatibility window),
 * checks session revocation and active user status.
 * Attaches to req.user / req.userId / req.userRole / req.sessionId.
 *
 * Must be wired BEFORE any route that needs identity or role checks.
 */
function verifyToken(pool) {
  return async (req, res, next) => {
    // Clear any stale values
    req.user = null;
    req.userId = null;
    req.userRole = null;
    req.sessionId = null;

    let identity;
    try {
      identity = await _extractVerifiedIdentity(req);
    } catch (err) {
      // JWT verification failed — hard 401
      return res.status(401).json({ error: 'Unauthorized: Invalid or expired token' });
    }

    if (!identity) {
      // No identity supplied — anonymous request allowed downstream.
      return next();
    }

    // JWT-sourced identities are verified against Supabase (users/sessions
    // live there — the gateway pool enforces the sheserved_app role).
    // The legacy x-user-id path (compatibility window, Phase 13.2-13.5)
    // keeps using the local pool as before.
    if (identity.source === 'jwt') {
      try {
        const { withTransaction } = require('../db/supabase-gateway-pool');
        const verified = await withTransaction(identity.userId, async (client) => {
          const u = await client.query(
            'SELECT id, is_active, user_category_id FROM public.users WHERE id = $1',
            [identity.userId]
          );
          if (u.rows.length === 0) return { error: 'not_found' };
          if (!u.rows[0].is_active) return { error: 'inactive' };
          let revoked = false;
          if (identity.sessionId) {
            const s = await client.query(
              'SELECT revoked_at FROM public.sessions WHERE id = $1',
              [identity.sessionId]
            );
            revoked = s.rows.length > 0 && s.rows[0].revoked_at != null;
          }
          return { user: u.rows[0], revoked };
        });

        if (verified.error === 'not_found') {
          return res.status(401).json({ error: 'Unauthorized: User not found' });
        }
        if (verified.error === 'inactive') {
          return res.status(403).json({ error: 'Forbidden: User is inactive' });
        }
        if (verified.revoked) {
          return res.status(401).json({ error: 'Unauthorized: Session revoked' });
        }

        req.user = {
          id: verified.user.id,
          role: verified.user.user_category_id || identity.role || 'consumer',
        };
        req.userId = verified.user.id;
        req.userRole = verified.user.user_category_id || identity.role || 'consumer';
        req.sessionId = identity.sessionId;
        req.identitySource = identity.source;
        return next();
      } catch (err) {
        console.error('[AuthMiddleware] Gateway DB error:', err.message);
        return res.status(500).json({ error: 'Server error during authentication' });
      }
    }

    // ── Legacy x-user-id path (compatibility window only) ──
    if (!pool) {
      console.error('[AuthMiddleware] Database pool is not available');
      return res.status(503).json({ error: 'Service unavailable' });
    }

    try {
      const result = await pool.query(
        'SELECT id, is_active, user_category_id FROM users WHERE id = $1',
        [identity.userId]
      );

      if (result.rows.length === 0) {
        return res.status(401).json({ error: 'Unauthorized: User not found' });
      }

      const userRow = result.rows[0];
      if (!userRow.is_active) {
        return res.status(403).json({ error: 'Forbidden: User is inactive' });
      }

      req.user = {
        id: userRow.id,
        role: userRow.user_category_id || identity.role || 'consumer',
      };
      req.userId = userRow.id;
      req.userRole = userRow.user_category_id || identity.role || 'consumer';
      req.sessionId = identity.sessionId;
      req.identitySource = identity.source;

      next();
    } catch (err) {
      console.error('[AuthMiddleware] DB error:', err.message);
      res.status(500).json({ error: 'Server error during authentication' });
    }
  };
}

/**
 * requireRole(requiredRole) — Express middleware factory
 * Must be used AFTER verifyToken(pool).
 */
function requireRole(requiredRole) {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({ error: 'Unauthorized: Login required' });
    }
    if (req.userRole !== requiredRole) {
      return res.status(403).json({
        error: `Forbidden: Requires '${requiredRole}' role`,
        currentRole: req.userRole,
      });
    }
    next();
  };
}

/**
 * requireAuth — shorthand for "any logged-in user" (any role).
 */
function requireAuth(req, res, next) {
  if (!req.user) {
    return res.status(401).json({ error: 'Unauthorized: Login required' });
  }
  next();
}

module.exports = {
  verifyToken,
  requireRole,
  requireAuth,
};
