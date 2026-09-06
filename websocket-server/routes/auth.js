'use strict';

/**
 * Auth routes — Phase 13.2 (Decision Q3=A, Q4=B, Q6=B, Q7=C, Q11=B)
 * ─────────────────────────────────────────────────────────────
 * Endpoints:
 *   POST   /auth/login           — password login (Argon2id + legacy SHA-256)
 *   POST   /auth/social/:provider — social login (verify provider token server-side)
 *   POST   /auth/refresh          — rotate refresh token
 *   POST   /auth/logout           — revoke current session
 *   POST   /auth/logout-all       — revoke all sessions
 *   GET    /auth/me               — current user info
 *   GET    /auth/sessions         — list active sessions
 *   DELETE /auth/sessions/:id     — revoke specific session
 *
 * Security:
 * - Backend verifies password, never returns password_hash
 * - Refresh tokens are ≥256-bit random, stored as SHA-256 hash
 * - Rotation with grace window 60s + Redis SETNX lock
 * - Audit events written via durable outbox (audit_logs table)
 * - Rate limiting applied via middleware (Phase 13.2-I)
 */

const express = require('express');
const crypto = require('crypto');

const { signAccessToken } = require('../lib/jwt');
const { verifyPassword, rehashToArgon2id } = require('../lib/password');
const { generateRefreshToken, createSession, rotateRefreshToken, revokeSession, revokeAllSessions, listSessions, lookupSession } = require('../lib/session');
const { writeAuditEvent, extractRequestMeta, EVENT_TYPES } = require('../lib/audit');
const { withTransaction } = require('../db/supabase-gateway-pool');

const router = express.Router();

/**
 * POST /auth/login
 * Body: { phone, password } or { username, password }
 * Returns: { accessToken, refreshToken, user: { id, username, phone, role } }
 */
router.post('/login', async (req, res) => {
  const { phone, username, password } = req.body;
  const meta = extractRequestMeta(req);

  if (!password || (!phone && !username)) {
    return res.status(400).json({ error: 'Phone or username and password are required' });
  }

  try {
    // Look up user by phone or username via gateway pool.
    const identifier = phone || username;
    const column = phone ? 'phone' : 'username';

    const userResult = await withTransaction('00000000-0000-0000-0000-000000000000', async (client) => {
      const result = await client.query(
        `SELECT id, username, phone, email, first_name, last_name,
                user_category_id, is_active, password_hash, password_algo
         FROM public.users
         WHERE ${column} = $1
         LIMIT 1`,
        [identifier]
      );
      return result.rows[0];
    });

    if (!userResult) {
      if (req.recordLoginFailure) await req.recordLoginFailure();
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTH_LOGIN_FAILURE,
        resourceType: 'user',
        action: 'login',
        outcome: 'denied',
        reason: 'user_not_found',
        ...meta,
      });
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    if (!userResult.is_active) {
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTH_LOGIN_FAILURE,
        actorId: userResult.id,
        resourceType: 'user',
        resourceId: userResult.id,
        action: 'login',
        outcome: 'denied',
        reason: 'inactive',
        ...meta,
      });
      return res.status(403).json({ error: 'Account is inactive' });
    }

    // Verify password.
    const verifyResult = await verifyPassword(
      password,
      userResult.password_hash,
      userResult.password_algo
    );

    if (!verifyResult.valid) {
      if (req.recordLoginFailure) await req.recordLoginFailure();
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTH_LOGIN_FAILURE,
        actorId: userResult.id,
        resourceType: 'user',
        resourceId: userResult.id,
        action: 'login',
        outcome: 'denied',
        reason: verifyResult.reason || 'invalid_password',
        ...meta,
      });
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Lazy rehash: if legacy SHA-256 verified, upgrade to Argon2id.
    if (verifyResult.needsRehash) {
      try {
        const { hash, algo } = await rehashToArgon2id(password);
        await withTransaction(userResult.id, async (client) => {
          await client.query(
            `UPDATE public.users
             SET password_hash = $1, password_algo = $2,
                 password_migrated_at = now(), password_updated_at = now()
             WHERE id = $3`,
            [hash, algo, userResult.id]
          );
        });
      } catch (rehashErr) {
        // Rehash failure is non-fatal — login still succeeds.
        console.error('[Auth] Lazy rehash failed:', rehashErr.message);
      }
    }

    // Force reset for plaintext passwords.
    if (verifyResult.forceReset) {
      if (req.resetLoginFailures) await req.resetLoginFailures();
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTH_LOGIN_SUCCESS,
        actorId: userResult.id,
        actorRole: userResult.user_category_id,
        resourceType: 'user',
        resourceId: userResult.id,
        action: 'login',
        ...meta,
      });
      return res.status(200).json({
        requiresPasswordReset: true,
        userId: userResult.id,
      });
    }

    // Create session + tokens.
    const refreshToken = generateRefreshToken();
    const session = await createSession({
      userId: userResult.id,
      refreshToken,
      ipAddress: meta.ipAddress,
      deviceInfo: { userAgent: meta.userAgent },
    });

    const accessToken = signAccessToken({
      userId: userResult.id,
      role: userResult.user_category_id || 'consumer',
      sessionId: session.sessionId,
    });

    if (req.resetLoginFailures) await req.resetLoginFailures();
    await writeAuditEvent({
      eventType: EVENT_TYPES.AUTH_LOGIN_SUCCESS,
      actorId: userResult.id,
      actorRole: userResult.user_category_id,
      resourceType: 'user',
      resourceId: userResult.id,
      action: 'login',
      sessionId: session.sessionId,
      ...meta,
    });

    return res.status(200).json({
      accessToken,
      refreshToken,
      user: {
        id: userResult.id,
        username: userResult.username,
        phone: userResult.phone,
        email: userResult.email,
        firstName: userResult.first_name,
        lastName: userResult.last_name,
        role: userResult.user_category_id || 'consumer',
      },
    });
  } catch (err) {
    console.error('[Auth] Login error:', err.message);
    return res.status(500).json({ error: 'Login failed' });
  }
});

/**
 * POST /auth/register
 * Body: { username, phone, password } (optional: firstName, lastName, email)
 *
 * Phase 13.2 (Decision Q4 = B): new passwords are hashed server-side with
 * Argon2id inside a gateway transaction — the client never computes or
 * writes password_hash (this closes the legacy client-side SHA-256 insert).
 * Returns the same token pair as login, so the app can proceed immediately.
 */
router.post('/register', async (req, res) => {
  const { username, phone, password, email, firstName, lastName } = req.body;
  const meta = extractRequestMeta(req);

  if (!username || !phone || !password) {
    return res.status(400).json({ error: 'Username, phone and password are required' });
  }
  if (!firstName) {
    return res.status(400).json({ error: 'First name is required' });
  }
  if (typeof password !== 'string' || password.length < 8) {
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  }

  try {
    // Hash server-side (Argon2id primary, bcrypt cost-12 fallback).
    const { hash, algo } = await rehashToArgon2id(password);

    // Create user + issue session in a single gateway transaction.
    const SYSTEM_ACTOR = '00000000-0000-0000-0000-000000000000';
    const userRow = await withTransaction(SYSTEM_ACTOR, async (client) => {
      // Unique checks first — return explicit conflict instead of DB error.
      const dup = await client.query(
        `SELECT 1 FROM public.users WHERE username = $1 OR phone = $2 LIMIT 1`,
        [username, phone]
      );
      if (dup.rows.length > 0) {
        const err = new Error('Username or phone already registered');
        err.code = 'DUPLICATE';
        throw err;
      }

      const inserted = await client.query(
        `INSERT INTO public.users
           (username, phone, email, first_name, last_name, password_hash, password_algo,
            password_updated_at, password_migrated_at, requires_password_reset,
            user_category_id, is_active)
         VALUES ($1, $2, $3, $4, $5, $6, $7, now(), now(), false, 'consumer', true)
         RETURNING id, username, phone, email, first_name, last_name, user_category_id`,
        [username, phone, email || null, firstName, lastName || null, hash, algo]
      );
      return inserted.rows[0];
    });

    // Issue tokens + session (same shape as login response).
    const refreshToken = generateRefreshToken();
    const session = await createSession({
      userId: userRow.id,
      refreshToken,
      ipAddress: meta.ipAddress,
      deviceInfo: { userAgent: meta.userAgent },
    });

    const accessToken = signAccessToken({
      userId: userRow.id,
      role: userRow.user_category_id || 'consumer',
      sessionId: session.sessionId,
    });

    await writeAuditEvent({
      eventType: EVENT_TYPES.AUTH_LOGIN_SUCCESS,
      actorId: userRow.id,
      actorRole: userRow.user_category_id,
      resourceType: 'user',
      resourceId: userRow.id,
      action: 'create',
      reason: 'register',
      sessionId: session.sessionId,
      ...meta,
    });

    return res.status(201).json({
      accessToken,
      refreshToken,
      user: {
        id: userRow.id,
        username: userRow.username,
        phone: userRow.phone,
        email: userRow.email,
        firstName: userRow.first_name,
        lastName: userRow.last_name,
        role: userRow.user_category_id || 'consumer',
      },
    });
  } catch (err) {
    if (err.code === 'DUPLICATE') {
      return res.status(409).json({ error: err.message });
    }
    console.error('[Auth] Register error:', err.message);
    return res.status(500).json({ error: 'Registration failed' });
  }
});

/**
 * POST /auth/social/:provider
 * Body: { providerToken } — token from provider (Google, Apple, etc.)
 * Backend verifies provider token server-side before mapping to user.
 *
 * Phase 13.2 (Decision Q3=A, free-only): Google/Apple tokens are verified
 * against the provider's public JWKS (lib/social.js).  Identity (sub/email/
 * name) derives ONLY from the verified token claims — client-supplied
 * userId is never used for authorization.  Unsupported providers (Facebook/
 * LINE/TikTok until verified) fail closed with 501.
 */
const { verifyGoogleIdToken, verifyAppleIdentityToken, SocialVerificationError } = require('../lib/social');

const SUPPORTED_SOCIAL_PROVIDERS = ['google', 'apple'];

// Server-side username generator: social users have no phone/username input,
// so derive a slug from verified claims and ensure uniqueness.
async function generateUniqueUsername(client, base) {
  const sanitized = (base || 'user')
    .toLowerCase()
    .replace(/[^a-z0-9]/g, '')
    .slice(0, 20) || 'user';

  // Try base first, then base + short random suffix (up to N attempts).
  const candidates = [sanitized];
  for (let i = 0; i < 5; i++) {
    candidates.push(`${sanitized.slice(0, 16)}_${crypto.randomInt(10000, 99999)}`);
  }

  for (const candidate of candidates) {
    const exists = await client.query(
      'SELECT 1 FROM public.users WHERE username = $1 LIMIT 1',
      [candidate]
    );
    if (exists.rows.length === 0) return candidate;
  }

  // Extremely unlikely — fail closed rather than colliding.
  throw new Error('Unable to generate a unique username for social account');
}

router.post('/social/:provider', async (req, res) => {
  const { provider } = req.params;
  const { providerToken, nonce } = req.body;
  const meta = extractRequestMeta(req);

  if (!providerToken) {
    return res.status(400).json({ error: 'Provider token is required' });
  }

  if (!SUPPORTED_SOCIAL_PROVIDERS.includes(provider)) {
    await writeAuditEvent({
      eventType: EVENT_TYPES.AUTH_LOGIN_FAILURE,
      resourceType: 'user',
      action: 'social_login',
      outcome: 'denied',
      reason: 'provider_not_supported',
      ...meta,
    });
    return res.status(501).json({ error: `Social login for "${provider}" is not yet implemented` });
  }

  try {
    // 1. Verify provider token server-side (identity derives from claims).
    const profile =
      provider === 'google'
        ? await verifyGoogleIdToken(providerToken, {
            clientId: process.env.GOOGLE_CLIENT_ID,
            extraClientIds: String(process.env.GOOGLE_CLIENT_IDS || '')
              .split(/[,\s]+/)
              .filter(Boolean),
            nonce,
          })
        : await verifyAppleIdentityToken(providerToken, {
            bundleId: process.env.APPLE_BUNDLE_ID,
            nonce,
          });

    // 2. Find or create the user inside a gateway transaction
    //    (SET LOCAL ROLE sheserved_app + identity context).
    const SYSTEM_ACTOR = '00000000-0000-0000-0000-000000000000';
    const userRow = await withTransaction(SYSTEM_ACTOR, async (client) => {
      const existing = await client.query(
        `SELECT id, username, email, first_name, last_name, user_category_id, is_active
         FROM public.users
         WHERE social_provider = $1 AND social_id = $2
         LIMIT 1`,
        [profile.provider, profile.providerUserId]
      );

      if (existing.rows.length > 0) {
        return { user: existing.rows[0], created: false };
      }

      // Create a new user from verified profile claims.
      const username = await generateUniqueUsername(
        client,
        profile.displayName || profile.email || profile.firstName || 'user'
      );
      const firstName = profile.firstName || profile.displayName || 'ผู้ใช้';
      const lastName = profile.lastName || '';

      const inserted = await client.query(
        `INSERT INTO public.users
           (username, email, first_name, last_name,
            social_provider, social_id, profile_image_url,
            verification_status, is_active, user_category_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'verified', true, 'consumer')
         RETURNING id, username, email, first_name, last_name, user_category_id, is_active`,
        [
          username,
          profile.email,
          firstName,
          lastName,
          profile.provider,
          profile.providerUserId,
          profile.photoUrl,
        ]
      );
      return { user: inserted.rows[0], created: true };
    });

    if (!userRow.user.is_active) {
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTH_LOGIN_FAILURE,
        actorId: userRow.user.id,
        resourceType: 'user',
        resourceId: userRow.user.id,
        action: 'social_login',
        outcome: 'denied',
        reason: 'inactive',
        ...meta,
      });
      return res.status(403).json({ error: 'Account is inactive' });
    }

    // 3. Issue session + tokens (same shape as login).
    const refreshToken = generateRefreshToken();
    const session = await createSession({
      userId: userRow.user.id,
      refreshToken,
      ipAddress: meta.ipAddress,
      deviceInfo: { userAgent: meta.userAgent },
    });

    const accessToken = signAccessToken({
      userId: userRow.user.id,
      role: userRow.user.user_category_id || 'consumer',
      sessionId: session.sessionId,
    });

    await writeAuditEvent({
      eventType: EVENT_TYPES.AUTH_LOGIN_SUCCESS,
      actorId: userRow.user.id,
      actorRole: userRow.user.user_category_id,
      resourceType: 'user',
      resourceId: userRow.user.id,
      action: 'social_login',
      reason: userRow.created ? 'social_register' : 'social_login',
      sessionId: session.sessionId,
      ...meta,
    });

    return res.status(200).json({
      accessToken,
      refreshToken,
      user: {
        id: userRow.user.id,
        username: userRow.user.username,
        phone: null,
        email: userRow.user.email,
        firstName: userRow.user.first_name,
        lastName: userRow.user.last_name,
        role: userRow.user.user_category_id || 'consumer',
      },
    });
  } catch (err) {
    if (err instanceof SocialVerificationError) {
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTH_LOGIN_FAILURE,
        resourceType: 'user',
        action: 'social_login',
        outcome: 'denied',
        reason: err.reason || 'invalid_token',
        ...meta,
      });
      return res.status(401).json({ error: 'Invalid provider token' });
    }
    console.error('[Auth] Social login error:', err.message);
    return res.status(500).json({ error: 'Social login failed' });
  }
});

/**
 * POST /auth/refresh
 * Body: { refreshToken }
 * Returns: { accessToken, refreshToken } — new rotated tokens
 *
 * Refresh token is an opaque ≥256-bit random string (Decision Q6 = B),
 * NOT a JWT — it is verified against the hash in public.sessions.
 */
router.post('/refresh', async (req, res) => {
  const { refreshToken } = req.body;
  const meta = extractRequestMeta(req);

  if (!refreshToken || typeof refreshToken !== 'string') {
    return res.status(400).json({ error: 'Refresh token is required' });
  }

  try {
    // Rotate token in database (handles grace window + reuse detection).
    const result = await rotateRefreshToken(refreshToken, {
      ipAddress: meta.ipAddress,
      deviceInfo: { userAgent: meta.userAgent },
    });

    if (result.reused) {
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTH_REFRESH_REUSE_DETECTED,
        actorId: result.userId,
        resourceType: 'session',
        resourceId: result.sessionId,
        action: 'refresh',
        outcome: 'denied',
        reason: 'reuse_after_grace',
        ...meta,
      });
      return res.status(401).json({ error: 'Refresh token reuse detected — session revoked' });
    }

    if (result.alreadyRotated) {
      // Old token presented within grace but no cached result (Redis down):
      // fail closed rather than minting a second token.
      return res.status(401).json({ error: 'Refresh token already rotated — retry with new token' });
    }

    // Look up user role for the new access token (don't trust client claims).
    const userRow = await withTransaction(result.userId, async (client) => {
      const r = await client.query(
        'SELECT id, user_category_id, is_active FROM public.users WHERE id = $1',
        [result.userId]
      );
      return r.rows[0];
    });
    if (!userRow || !userRow.is_active) {
      return res.status(401).json({ error: 'User inactive or not found' });
    }

    // Mint new access token.
    const accessToken = signAccessToken({
      userId: result.userId,
      role: userRow.user_category_id || 'consumer',
      sessionId: result.sessionId,
    });

    await writeAuditEvent({
      eventType: EVENT_TYPES.AUTH_REFRESH_SUCCESS,
      actorId: result.userId,
      resourceType: 'session',
      resourceId: result.sessionId,
      action: 'refresh',
      sessionId: result.sessionId,
      ...meta,
    });

    return res.status(200).json({
      accessToken,
      refreshToken: result.refreshToken,
    });
  } catch (err) {
    if (err.message.includes('expired')) {
      return res.status(401).json({ error: 'Refresh token expired' });
    }
    if (err.message.includes('Invalid') || err.message.includes('revoked') || err.message.includes('reuse')) {
      return res.status(401).json({ error: 'Invalid refresh token' });
    }
    console.error('[Auth] Refresh error:', err.message);
    return res.status(500).json({ error: 'Token refresh failed' });
  }
});

/**
 * POST /auth/logout
 * Body: { refreshToken } or uses accessToken's session
 * Revokes current session.
 */
router.post('/logout', async (req, res) => {
  const { refreshToken } = req.body;
  const meta = extractRequestMeta(req);

  if (!refreshToken) {
    return res.status(400).json({ error: 'Refresh token is required' });
  }

  try {
    const session = await lookupSession(refreshToken);
    if (session && session.id) {
      await revokeSession(session.id, 'logout');
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTH_LOGOUT,
        actorId: session.user_id,
        resourceType: 'session',
        resourceId: session.id,
        action: 'logout',
        sessionId: session.id,
        ...meta,
      });
    }
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('[Auth] Logout error:', err.message);
    return res.status(500).json({ error: 'Logout failed' });
  }
});

/**
 * POST /auth/logout-all
 * Requires authenticated user (req.userId from middleware).
 * Revokes all sessions for the user.
 */
router.post('/logout-all', async (req, res) => {
  const meta = extractRequestMeta(req);

  if (!req.userId) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    await revokeAllSessions(req.userId, 'logout_all');
    await writeAuditEvent({
      eventType: EVENT_TYPES.AUTH_SESSION_REVOKED,
      actorId: req.userId,
      resourceType: 'session',
      action: 'revoke_all',
      ...meta,
    });
    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('[Auth] Logout-all error:', err.message);
    return res.status(500).json({ error: 'Logout-all failed' });
  }
});

/**
 * GET /auth/me
 * Requires authenticated user (req.userId from middleware).
 * Returns current user info (never password_hash).
 */
router.get('/me', async (req, res) => {
  if (!req.userId) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    const userResult = await withTransaction(req.userId, async (client) => {
      const result = await client.query(
        `SELECT id, username, phone, email, first_name, last_name, user_category_id, is_active
         FROM public.users
         WHERE id = $1`,
        [req.userId]
      );
      return result.rows[0];
    });

    if (!userResult) {
      return res.status(404).json({ error: 'User not found' });
    }

    return res.status(200).json({
      id: userResult.id,
      username: userResult.username,
      phone: userResult.phone,
      email: userResult.email,
      firstName: userResult.first_name,
      lastName: userResult.last_name,
      role: userResult.user_category_id || 'consumer',
      isActive: userResult.is_active,
    });
  } catch (err) {
    console.error('[Auth] Me error:', err.message);
    return res.status(500).json({ error: 'Failed to get user info' });
  }
});

/**
 * GET /auth/sessions
 * Requires authenticated user.
 * Lists active sessions for the user.
 */
router.get('/sessions', async (req, res) => {
  if (!req.userId) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    const sessions = await listSessions(req.userId);
    return res.status(200).json({ sessions });
  } catch (err) {
    console.error('[Auth] Sessions list error:', err.message);
    return res.status(500).json({ error: 'Failed to list sessions' });
  }
});

/**
 * DELETE /auth/sessions/:id
 * Requires authenticated user.
 * Revokes a specific session (only if it belongs to the user).
 */
router.delete('/sessions/:id', async (req, res) => {
  const { id } = req.params;
  const meta = extractRequestMeta(req);

  if (!req.userId) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    // Verify session belongs to user before revoking (via gateway pool).
    const sessionRow = await withTransaction(req.userId, async (client) => {
      const r = await client.query(
        'SELECT user_id FROM public.sessions WHERE id = $1',
        [id]
      );
      return r.rows[0];
    });

    if (!sessionRow) {
      return res.status(404).json({ error: 'Session not found' });
    }
    if (sessionRow.user_id !== req.userId) {
      await writeAuditEvent({
        eventType: EVENT_TYPES.AUTHZ_DENIED,
        actorId: req.userId,
        resourceType: 'session',
        resourceId: id,
        action: 'revoke',
        outcome: 'denied',
        reason: 'not_owner',
        ...meta,
      });
      return res.status(403).json({ error: 'Cannot revoke another user\'s session' });
    }

    await revokeSession(id, 'user_revoke');
    await writeAuditEvent({
      eventType: EVENT_TYPES.AUTH_SESSION_REVOKED,
      actorId: req.userId,
      resourceType: 'session',
      resourceId: id,
      action: 'revoke',
      ...meta,
    });

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error('[Auth] Session revoke error:', err.message);
    return res.status(500).json({ error: 'Failed to revoke session' });
  }
});

module.exports = router;
