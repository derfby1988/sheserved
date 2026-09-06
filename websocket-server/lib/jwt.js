'use strict';

/**
 * JWT signing and verification — HS256 dual-key (Decision Q3 = A)
 * ─────────────────────────────────────────────────────────────
 * - Sign with the ACTIVE key; embed `kid` in JWT header.
 * - Verify accepts active OR previous key (known kids only).
 * - Claims: sub, role, iss, aud, iat, exp, sid (session id), jti (token id).
 * - ACCESS_TTL / REFRESH_TTL from env (seconds).
 * - Never logs secrets or token strings.
 *
 * Env vars:
 *   JWT_ACTIVE_KID, JWT_ACTIVE_SECRET
 *   JWT_PREVIOUS_KID, JWT_PREVIOUS_SECRET  (optional during rotation window)
 *   JWT_ISSUER (default: sheserved)
 *   JWT_AUDIENCE (default: sheserved-app)
 *   ACCESS_TTL (default: 900 = 15 min)
 *   REFRESH_TTL (default: 604800 = 7 days)
 */

const jwt = require('jsonwebtoken');

const ALGORITHM = 'HS256';

const ACTIVE_KID = process.env.JWT_ACTIVE_KID || 'active-1';
const ACTIVE_SECRET = process.env.JWT_ACTIVE_SECRET;
const PREVIOUS_KID = process.env.JWT_PREVIOUS_KID;
const PREVIOUS_SECRET = process.env.JWT_PREVIOUS_SECRET;

const ISSUER = process.env.JWT_ISSUER || 'sheserved';
const AUDIENCE = process.env.JWT_AUDIENCE || 'sheserved-app';

const ACCESS_TTL = parseInt(process.env.ACCESS_TTL, 10) || 900;       // 15 min
const REFRESH_TTL = parseInt(process.env.REFRESH_TTL, 10) || 604800;  // 7 days

/**
 * Per-role TTL override (plan: "ACCESS_TTL/REFRESH_TTL ตาม role").
 * Env: ACCESS_TTL_<ROLE> / REFRESH_TTL_<ROLE> (role uppercased, e.g.
 * ACCESS_TTL_ADMIN=300, ACCESS_TTL_CONSUMER=900).  Falls back to the
 * global ACCESS_TTL / REFRESH_TTL.
 */
function ttlFor(kind, role) {
  const globalTtl = kind === 'access' ? ACCESS_TTL : REFRESH_TTL;
  if (!role) return globalTtl;
  const kindKey = kind === 'access' ? 'ACCESS' : 'REFRESH';
  const roleKey = `${kindKey}_TTL_${String(role).toUpperCase().replace(/[^A-Z0-9_]/g, '')}`;
  const override = parseInt(process.env[roleKey], 10);
  return Number.isFinite(override) && override > 0 ? override : globalTtl;
}

// Map kid → secret for verification.  Only known kids are accepted.
const KEY_MAP = new Map();
if (ACTIVE_SECRET) KEY_MAP.set(ACTIVE_KID, ACTIVE_SECRET);
if (PREVIOUS_KID && PREVIOUS_SECRET) KEY_MAP.set(PREVIOUS_KID, PREVIOUS_SECRET);

/**
 * Sign an access token for a user.
 * @param {object} opts
 * @param {string} opts.userId   - user UUID (sub claim)
 * @param {string} opts.role     - user role (e.g. 'consumer', 'provider', 'admin')
 * @param {string} [opts.sessionId] - session UUID (sid claim)
 * @param {string} [opts.jti]    - unique token id (for replay prevention)
 * @returns {string} signed JWT
 */
function signAccessToken({ userId, role, sessionId, jti }) {
  if (!ACTIVE_SECRET) {
    throw new Error('JWT_ACTIVE_SECRET is not configured');
  }
  if (!userId) {
    throw new Error('userId is required to sign access token');
  }

  const payload = {
    sub: userId,
    role: role || 'consumer',
    iss: ISSUER,
    aud: AUDIENCE,
    typ: 'access',
  };
  if (sessionId) payload.sid = sessionId;
  if (jti) payload.jti = jti;

  return jwt.sign(payload, ACTIVE_SECRET, {
    algorithm: ALGORITHM,
    expiresIn: ttlFor('access', role),
    keyid: ACTIVE_KID,
  });
}

/**
 * Sign a refresh token.  Refresh tokens have a longer TTL and carry
 * only sub + sid + typ='refresh'.  They are NOT used for API access.
 * @param {object} opts
 * @param {string} opts.userId
 * @param {string} [opts.sessionId]
 * @param {string} [opts.jti]
 * @returns {string} signed JWT
 */
function signRefreshToken({ userId, sessionId, jti }) {
  if (!ACTIVE_SECRET) {
    throw new Error('JWT_ACTIVE_SECRET is not configured');
  }
  if (!userId) {
    throw new Error('userId is required to sign refresh token');
  }

  const payload = {
    sub: userId,
    iss: ISSUER,
    aud: AUDIENCE,
    typ: 'refresh',
  };
  if (sessionId) payload.sid = sessionId;
  if (jti) payload.jti = jti;

  return jwt.sign(payload, ACTIVE_SECRET, {
    algorithm: ALGORITHM,
    expiresIn: REFRESH_TTL,
    keyid: ACTIVE_KID,
  });
}

/**
 * Verify a JWT.
 * - Algorithm must be HS256 (reject 'none' and asymmetric).
 * - kid must be in KEY_MAP (known key).
 * - iss and aud must match configured values.
 * - typ must match expected ('access' or 'refresh') if specified.
 *
 * @param {string} token
 * @param {object} [opts]
 * @param {string} [opts.expectedTyp] - 'access' or 'refresh'; skip check if omitted
 * @returns {object} decoded payload
 * @throws Error if verification fails
 */
function verifyToken(token, opts = {}) {
  if (!token || typeof token !== 'string') {
    throw new Error('Token is required');
  }

  // Decode header to find kid (without verifying first).
  let header;
  try {
    const parts = token.split('.');
    if (parts.length !== 3) {
      throw new Error('Malformed token');
    }
    header = JSON.parse(Buffer.from(parts[0], 'base64url').toString('utf8'));
  } catch (err) {
    throw new Error('Malformed token header');
  }

  if (header.alg !== ALGORITHM) {
    throw new Error(`Unsupported algorithm: ${header.alg}`);
  }

  const kid = header.kid;
  const secret = KEY_MAP.get(kid);
  if (!secret) {
    throw new Error(`Unknown key id: ${kid}`);
  }

  let payload;
  try {
    payload = jwt.verify(token, secret, {
      algorithms: [ALGORITHM],
      issuer: ISSUER,
      audience: AUDIENCE,
    });
  } catch (err) {
    // Map jsonwebtoken errors to generic messages (don't leak internals).
    if (err.name === 'TokenExpiredError') {
      throw new Error('Token expired');
    }
    if (err.name === 'JsonWebTokenError') {
      throw new Error('Invalid token');
    }
    if (err.name === 'NotBeforeError') {
      throw new Error('Token not active yet');
    }
    throw new Error('Token verification failed');
  }

  if (opts.expectedTyp && payload.typ !== opts.expectedTyp) {
    throw new Error(`Expected token type '${opts.expectedTyp}', got '${payload.typ}'`);
  }

  return payload;
}

/**
 * Verify an access token (convenience wrapper).
 */
function verifyAccessToken(token) {
  return verifyToken(token, { expectedTyp: 'access' });
}

/**
 * Verify a refresh token (convenience wrapper).
 */
function verifyRefreshToken(token) {
  return verifyToken(token, { expectedTyp: 'refresh' });
}

module.exports = {
  ALGORITHM,
  ISSUER,
  AUDIENCE,
  ACCESS_TTL,
  REFRESH_TTL,
  ttlFor,
  signAccessToken,
  signRefreshToken,
  verifyToken,
  verifyAccessToken,
  verifyRefreshToken,
};
