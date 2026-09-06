'use strict';

/**
 * PostgREST short-lived token mint (Decision Q7 = C)
 * ─────────────────────────────────────────────────────────────
 * Backend mints a short-lived JWT (TTL ≤ 5 minutes) signed with
 * SUPABASE_JWT_SECRET so PostgREST can verify it and enforce RLS
 * via the `authenticated` role.
 *
 * This is NOT the access/refresh token.  Flutter never sees this token
 * directly — Backend uses it for private reads on behalf of the user.
 *
 * Claims:
 *   sub        — user UUID
 *   role       — 'authenticated' (PostgREST role)
 *   iss        — 'sheserved-backend'
 *   aud        — 'postgrest'
 *   iat, exp   — standard
 *   email      — optional (if available)
 *
 * Env:
 *   SUPABASE_JWT_SECRET — must match Supabase project's JWT secret
 *   POSTGREST_TOKEN_TTL — seconds (default: 300 = 5 min, max: 300)
 */

const jwt = require('jsonwebtoken');

const ALGORITHM = 'HS256';
const MAX_TTL = 300; // 5 minutes hard cap per plan Q7-C

const SUPABASE_JWT_SECRET = process.env.SUPABASE_JWT_SECRET;
const TOKEN_TTL = Math.min(parseInt(process.env.POSTGREST_TOKEN_TTL, 10) || 300, MAX_TTL);

/**
 * Mint a short-lived PostgREST token for a user.
 * @param {object} opts
 * @param {string} opts.userId    - user UUID (sub)
 * @param {string} [opts.email]   - user email (optional, for RLS convenience)
 * @returns {string} signed JWT
 */
function mintPostgrestToken({ userId, email }) {
  if (!SUPABASE_JWT_SECRET) {
    throw new Error('SUPABASE_JWT_SECRET is not configured');
  }
  if (!userId) {
    throw new Error('userId is required to mint PostgREST token');
  }

  const payload = {
    sub: userId,
    role: 'authenticated',
    iss: 'sheserved-backend',
    aud: 'postgrest',
  };
  if (email) payload.email = email;

  return jwt.sign(payload, SUPABASE_JWT_SECRET, {
    algorithm: ALGORITHM,
    expiresIn: TOKEN_TTL,
  });
}

module.exports = {
  mintPostgrestToken,
  MAX_TTL,
  TOKEN_TTL,
};
