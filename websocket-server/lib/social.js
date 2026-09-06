'use strict';

/**
 * Social provider token verification — Phase 13.2 (Decision Q3=A, free-only)
 * ─────────────────────────────────────────────────────────────────────────
 * Verifies provider-issued identity tokens SERVER-SIDE before the backend
 * maps them to a public.users row.  Identity (sub/email/name) always derives
 * from the verified token claims — never from client-supplied fields.
 *
 * Supported (free, no paid quota):
 *   - Google:  ID token (RS256) verified against Google's public JWKS
 *              https://www.googleapis.com/oauth2/v3/certs
 *   - Apple:   Identity token (RS256) verified against Apple's public JWKS
 *              https://appleid.apple.com/auth/keys
 *
 * JWKS are fetched on demand and cached in-memory (default TTL 1h) to avoid
 * a network round-trip per login.  No provider credentials/API keys are
 * required for verification — only the expected audience (client id / bundle
 * id) which is configuration, not a secret.
 *
 * Fail-closed: any malformed/unverifiable token, unknown kid, wrong
 * issuer/audience/algorithm, or expired token throws SocialVerificationError.
 */

const crypto = require('crypto');
const jwt = require('jsonwebtoken');

const GOOGLE_CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';

const GOOGLE_ISSUERS = ['accounts.google.com', 'https://accounts.google.com'];
const APPLE_ISSUER = 'https://appleid.apple.com';

const JWKS_CACHE_TTL_MS = 60 * 60 * 1000; // 1 hour
const jwksCache = new Map(); // { [url]: { keys, fetchedAt } }

class SocialVerificationError extends Error {
  constructor(message, reason) {
    super(message);
    this.name = 'SocialVerificationError';
    this.reason = reason || 'invalid_token';
  }
}

/**
 * Fetch + cache a provider JWKS document.
 * @param {string} url
 * @param {Function} [fetcher] - injectable fetch for tests (defaults to global fetch)
 */
async function getJwks(url, fetcher) {
  const cached = jwksCache.get(url);
  if (cached && Date.now() - cached.fetchedAt < JWKS_CACHE_TTL_MS) {
    return cached.keys;
  }

  const doFetch = fetcher || ((u) => fetch(u));
  const res = await doFetch(url);
  if (!res.ok) {
    throw new SocialVerificationError(
      `Failed to fetch JWKS from ${url}: HTTP ${res.status}`,
      'jwks_unavailable'
    );
  }
  const body = await res.json();
  if (!Array.isArray(body.keys) || body.keys.length === 0) {
    throw new SocialVerificationError('JWKS response has no keys', 'jwks_unavailable');
  }

  jwksCache.set(url, { keys: body.keys, fetchedAt: Date.now() });
  return body.keys;
}

/** Convert a JWK (RSA) to a crypto KeyObject usable by jsonwebtoken. */
function jwkToPublicKey(jwk) {
  try {
    return crypto.createPublicKey({ key: jwk, format: 'jwk' });
  } catch (err) {
    throw new SocialVerificationError(
      `Unsupported JWK: ${err.message}`,
      'unsupported_key'
    );
  }
}

/**
 * Verify a provider JWT against its JWKS.
 * @param {string} token
 * @param {string} jwksUrl
 * @param {object} opts { audience, issuers, nonce?, nonceHashed?, fetcher? }
 * @returns {object} verified payload (claims)
 */
async function verifyProviderToken(token, jwksUrl, opts) {
  const { audience, issuers, nonce, nonceHashed, fetcher } = opts;

  const decoded = jwt.decode(token, { complete: true });
  if (!decoded || !decoded.header || !decoded.payload) {
    throw new SocialVerificationError('Malformed provider token', 'malformed_token');
  }

  const { kid, alg } = decoded.header;
  if (alg !== 'RS256') {
    throw new SocialVerificationError(
      `Unexpected algorithm: ${alg} (RS256 required)`,
      'wrong_algorithm'
    );
  }
  if (!kid) {
    throw new SocialVerificationError('Token is missing kid', 'missing_kid');
  }

  const keys = await getJwks(jwksUrl, fetcher);
  const jwk = keys.find((k) => k.kid === kid);
  if (!jwk) {
    throw new SocialVerificationError(
      `No matching key for kid=${kid} (key rotation?)`,
      'unknown_kid'
    );
  }

  const publicKey = jwkToPublicKey(jwk);
  let payload;
  try {
    payload = jwt.verify(token, publicKey, {
      algorithms: ['RS256'],
      issuer: issuers,
      audience,
    });
  } catch (err) {
    throw new SocialVerificationError(
      `Provider token verification failed: ${err.message}`,
      'invalid_signature_or_claims'
    );
  }

  if (nonce) {
    // Google stores the nonce claim as-is; Apple stores SHA-256(raw nonce).
    const expected = nonceHashed ? sha256Hex(nonce) : nonce;
    if (payload.nonce !== expected) {
      throw new SocialVerificationError('Nonce mismatch', 'nonce_mismatch');
    }
  }

  return payload;
}

function sha256Hex(input) {
  return crypto.createHash('sha256').update(String(input), 'utf8').digest('hex');
}

/**
 * Verify a Google ID token.
 * @param {string} idToken
 * @param {object} opts { clientId, extraClientIds?, nonce?, fetcher? }
 *   - clientId: Web/server client ID (primary audience)
 *   - extraClientIds: platform client IDs (iOS/Android) — Google returns the
 *     platform client ID as `aud` on those platforms even when serverClientId
 *     is configured, so the server must accept the project's client ID set.
 * @returns {object} normalized profile { provider, providerUserId, email, emailVerified, firstName, lastName, displayName, photoUrl }
 */
async function verifyGoogleIdToken(idToken, { clientId, extraClientIds, nonce, fetcher } = {}) {
  if (!clientId) {
    throw new SocialVerificationError(
      'GOOGLE_CLIENT_ID is not configured',
      'provider_not_configured'
    );
  }

  const audiences = [clientId, ...(Array.isArray(extraClientIds) ? extraClientIds : [])]
    .map((id) => String(id).trim())
    .filter(Boolean);

  const payload = await verifyProviderToken(idToken, GOOGLE_CERTS_URL, {
    audience: audiences,
    issuers: GOOGLE_ISSUERS,
    nonce, // Google: nonce claim is stored as-is
    fetcher,
  });

  return normalizeProfile('google', payload);
}

/**
 * Verify an Apple identity token.
 * @param {string} identityToken
 * @param {object} opts { bundleId, nonce?, fetcher? }
 * @returns {object} normalized profile { provider, providerUserId, email, emailVerified, firstName, lastName, displayName, photoUrl }
 */
async function verifyAppleIdentityToken(identityToken, { bundleId, nonce, fetcher } = {}) {
  if (!bundleId) {
    throw new SocialVerificationError(
      'APPLE_BUNDLE_ID is not configured',
      'provider_not_configured'
    );
  }

  const payload = await verifyProviderToken(identityToken, APPLE_KEYS_URL, {
    audience: bundleId,
    issuers: [APPLE_ISSUER],
    nonce,
    nonceHashed: true, // Apple: nonce claim is SHA-256(raw nonce)
    fetcher,
  });

  return normalizeProfile('apple', payload);
}

/** Map verified claims to the normalized profile shape used by the route. */
function normalizeProfile(provider, payload) {
  return {
    provider,
    providerUserId: payload.sub,
    email: payload.email || null,
    emailVerified: payload.email_verified === true,
    firstName: payload.given_name || payload.name?.split(' ')[0] || null,
    lastName: payload.family_name || null,
    displayName: payload.name || null,
    photoUrl: payload.picture || null,
  };
}

module.exports = {
  SocialVerificationError,
  verifyGoogleIdToken,
  verifyAppleIdentityToken,
  // Test hooks
  _getJwks: getJwks,
  _clearJwksCache: () => jwksCache.clear(),
};
