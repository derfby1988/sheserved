/**
 * Authentication & Authorization Middleware
 * ─────────────────────────────────────────────────────────────
 * Phase 1 — Route Security Implementation Plan
 *
 * Verifies user identity via PostgreSQL lookup and enforces role-based
 * access control.  Designed to work without Supabase Auth (per project
 * architecture: custom AuthService / ServiceLocator pattern).
 *
 * Dependencies used: pg (existing)
 *
 * TODO (future): Add JWT signature verification when jsonwebtoken is installed.
 *   For now we accept x-user-id + optional Authorization bearer fallback
 *   but ALWAYS verify against the local database.
 */

'use strict';

/**
 * Extract userId from request headers.
 * Priority: 1) x-user-id  2) Authorization Bearer token payload (sub)
 * Returns null if neither is present.
 */
function _extractUserId(req) {
  // 1. Direct userId header (existing Flutter pattern)
  const userId = req.headers['x-user-id'];
  if (userId && typeof userId === 'string' && userId.length > 0) {
    return userId;
  }

  // 2. Bearer token — try to extract sub claim from JWT payload (unsigned decode)
  //    This is defense-in-depth; signature is NOT verified here (no jsonwebtoken).
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    try {
      // JWT = header.payload.signature — split by '.' and base64-decode payload
      const parts = token.split('.');
      if (parts.length === 3) {
        const payload = Buffer.from(parts[1], 'base64url').toString('utf8');
        const claims = JSON.parse(payload);
        if (claims.sub) return claims.sub;
      }
    } catch (err) {
      // Malformed token — silently fall through
    }
  }

  return null;
}

/**
 * verifyToken(pool) — Express middleware
 * Resolves user from request headers, queries local DB for
 * id | is_active | role, and attaches to req.user / req.userId / req.userRole.
 *
 * Must be wired BEFORE any route that needs identity or role checks.
 */
function verifyToken(pool) {
  return async (req, res, next) => {
    // Clear any stale values
    req.user = null;
    req.userId = null;
    req.userRole = null;

    const rawId = _extractUserId(req);
    if (!rawId) {
      // No identity supplied — not an error; anonymous requests allowed
      // downstream routes should check req.userId before trusting.
      return next();
    }

    if (!pool) {
      console.error('[AuthMiddleware] Database pool is not available');
      return res.status(503).json({ error: 'Service unavailable' });
    }

    try {
      const result = await pool.query(
        'SELECT id, is_active, user_category_id FROM users WHERE id = $1',
        [rawId]
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
        role: userRow.user_category_id || 'consumer',
      };
      req.userId = userRow.id;
      req.userRole = userRow.user_category_id || 'consumer';

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
