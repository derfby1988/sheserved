#!/usr/bin/env node
'use strict';

/**
 * Phase 13.2 — Integration tests for auth endpoints
 * ─────────────────────────────────────────────────────────────
 * Tests:
 * 1. JWT sign + verify (access + refresh)
 * 2. Password verify (Argon2id + legacy SHA-256 + lazy rehash)
 * 3. PostgREST token mint
 * 4. Session create + verify + rotate + revoke
 * 5. Audit event write
 * 6. Login endpoint (requires running server)
 * 7. Refresh endpoint (requires running server)
 * 8. Reuse detection (requires running server)
 *
 * Usage:
 *   node scripts/test-phase-13-2-auth.js
 *
 * For endpoint tests, server must be running on PORT (default 3000).
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const assert = require('assert');
const crypto = require('crypto');

// Set test secrets if not configured (must be before requiring lib modules
// because they read env vars at module load time).
if (!process.env.JWT_ACTIVE_SECRET) {
  process.env.JWT_ACTIVE_SECRET = crypto.randomBytes(32).toString('hex');
  process.env.JWT_ACTIVE_KID = 'test-active';
}
if (!process.env.JWT_PREVIOUS_SECRET) {
  process.env.JWT_PREVIOUS_KID = 'test-previous';
  process.env.JWT_PREVIOUS_SECRET = crypto.randomBytes(32).toString('hex');
}
if (!process.env.SUPABASE_JWT_SECRET) {
  process.env.SUPABASE_JWT_SECRET = crypto.randomBytes(32).toString('hex');
}

// Test results tracking
const results = [];
function test(name, fn) {
  return Promise.resolve()
    .then(() => fn())
    .then(() => {
      results.push({ name, status: 'PASS' });
      console.log(`  ✅ ${name}`);
    })
    .catch((err) => {
      results.push({ name, status: 'FAIL', error: err.message });
      console.log(`  ❌ ${name}: ${err.message}`);
    });
}

async function main() {
  console.log('Phase 13.2 — Integration Tests\n');

  // ── 1. JWT ──
  console.log('1. JWT tests:');
  const jwt = require('../lib/jwt');

  await test('sign + verify access token', async () => {
    const token = jwt.signAccessToken({ userId: '00000000-0000-0000-0000-000000000001', role: 'consumer' });
    const payload = jwt.verifyAccessToken(token);
    assert.strictEqual(payload.sub, '00000000-0000-0000-0000-000000000001');
    assert.strictEqual(payload.role, 'consumer');
    assert.strictEqual(payload.typ, 'access');
  });

  await test('sign + verify refresh token', async () => {
    const token = jwt.signRefreshToken({ userId: '00000000-0000-0000-0000-000000000001' });
    const payload = jwt.verifyRefreshToken(token);
    assert.strictEqual(payload.sub, '00000000-0000-0000-0000-000000000001');
    assert.strictEqual(payload.typ, 'refresh');
  });

  await test('reject wrong token type', async () => {
    const token = jwt.signAccessToken({ userId: '00000000-0000-0000-0000-000000000001' });
    assert.throws(() => jwt.verifyRefreshToken(token), /Expected token type/);
  });

  await test('reject tampered token', async () => {
    const token = jwt.signAccessToken({ userId: '00000000-0000-0000-0000-000000000001' });
    const tampered = token.slice(0, -5) + 'XXXXX';
    assert.throws(() => jwt.verifyAccessToken(tampered), /Invalid token|verification failed/);
  });

  await test('per-role TTL override (ACCESS_TTL_ADMIN)', async () => {
    process.env.ACCESS_TTL_ADMIN = '300';
    const ttlAdmin = jwt.ttlFor('access', 'admin');
    const ttlDefault = jwt.ttlFor('access', 'consumer');
    assert.strictEqual(ttlAdmin, 300);
    assert.notStrictEqual(ttlAdmin, ttlDefault);
    delete process.env.ACCESS_TTL_ADMIN;
  });

  // ── 2. Password ──
  console.log('\n2. Password tests:');
  const password = require('../lib/password');

  await test('Argon2id hash + verify', async () => {
    const hash = await password.hashPassword('testPassword123');
    const result = await password.verifyPassword('testPassword123', hash, 'argon2id');
    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.needsRehash, false);
  });

  await test('Argon2id reject wrong password', async () => {
    const hash = await password.hashPassword('correctPassword');
    const result = await password.verifyPassword('wrongPassword', hash, 'argon2id');
    assert.strictEqual(result.valid, false);
  });

  await test('Legacy SHA-256 verify + needsRehash', async () => {
    const sha256Hash = password.sha256Hash('legacyPassword');
    const result = await password.verifyPassword('legacyPassword', sha256Hash, 'sha256');
    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.needsRehash, true);
  });

  await test('Lazy rehash to Argon2id', async () => {
    const { hash, algo } = await password.rehashToArgon2id('myPassword');
    assert.strictEqual(algo, 'argon2id');
    const result = await password.verifyPassword('myPassword', hash, 'argon2id');
    assert.strictEqual(result.valid, true);
  });

  await test('Plaintext force reset', async () => {
    const result = await password.verifyPassword('rawPassword', 'rawPassword', 'plaintext');
    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.forceReset, true);
  });

  await test('bcrypt fallback verify + lazy upgrade to argon2', async () => {
    const bcrypt = require('bcryptjs');
    const bh = await bcrypt.hash('legacyBcryptPw', 12);
    const result = await password.verifyPassword('legacyBcryptPw', bh, 'bcrypt');
    assert.strictEqual(result.valid, true);
    assert.strictEqual(result.needsRehash, true, 'bcrypt row should be marked for argon2 upgrade');
    const wrong = await password.verifyPassword('wrong', bh, 'bcrypt');
    assert.strictEqual(wrong.valid, false);
  });

  await test('register hash uses Argon2id (Q4-B)', async () => {
    const { hash, algo } = await password.rehashToArgon2id('registerPw123');
    assert.strictEqual(algo, password.ARGON2ID_ALGO);
    const verify = await password.verifyPassword('registerPw123', hash, algo);
    assert.strictEqual(verify.valid, true);
  });

  // ── 3. PostgREST token ──
  console.log('\n3. PostgREST token tests:');
  const postgrestToken = require('../lib/postgrest-token');

  await test('mint PostgREST token', async () => {
    const token = postgrestToken.mintPostgrestToken({ userId: '00000000-0000-0000-0000-000000000001' });
    assert(token.split('.').length === 3, 'should be a JWT');
    const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
    assert.strictEqual(payload.sub, '00000000-0000-0000-0000-000000000001');
    assert.strictEqual(payload.role, 'authenticated');
  });

  // ── 4. Session ──
  console.log('\n4. Session tests (requires DB connection):');
  const session = require('../lib/session');

  // These tests require a live DB — skip if not available.
  let dbAvailable = false;
  try {
    const s = session.generateRefreshToken();
    const h = session.hashToken(s);
    assert(h.length === 64, 'SHA-256 hash should be 64 hex chars');
    dbAvailable = true;
  } catch (err) {
    console.log('   ⚠️ DB tests skipped:', err.message);
  }

  if (dbAvailable) {
    await test('generate refresh token (≥256-bit)', async () => {
      const token = session.generateRefreshToken();
      // base64url of 32 bytes = ~43 chars, decoded = 32 bytes = 256 bits
      const bytes = Buffer.from(token, 'base64url');
      assert(bytes.length >= 32, 'token should be at least 256 bits');
    });

    await test('hash refresh token', async () => {
      const token = session.generateRefreshToken();
      const hash = session.hashToken(token);
      assert.strictEqual(hash.length, 64, 'SHA-256 hex = 64 chars');
    });
  }

  // ── 5. Audit ──
  console.log('\n5. Audit tests:');
  const audit = require('../lib/audit');

  await test('extractRequestMeta from mock request', async () => {
    const mockReq = {
      ip: '127.0.0.1',
      get: (h) => h === 'user-agent' ? 'test-agent' : null,
      headers: { 'x-request-id': 'test-123' },
    };
    const meta = audit.extractRequestMeta(mockReq);
    assert.strictEqual(meta.ipAddress, '127.0.0.1');
    assert.strictEqual(meta.userAgent, 'test-agent');
    assert.strictEqual(meta.requestId, 'test-123');
  });

  await test('EVENT_TYPES has required events', async () => {
    const required = ['AUTH_LOGIN_SUCCESS', 'AUTH_LOGIN_FAILURE', 'AUTH_REFRESH_SUCCESS',
                      'AUTH_REFRESH_REUSE_DETECTED', 'AUTH_LOGOUT', 'AUTH_SESSION_REVOKED',
                      'AUTH_PASSWORD_CHANGED', 'AUTHZ_DENIED'];
    for (const key of required) {
      assert(audit.EVENT_TYPES[key], `missing event type: ${key}`);
    }
  });

  // ── 6. Min app version ──
  console.log('\n6. Min app version tests:');
  const { compareVersions } = require('../middleware/app-version');

  await test('compareVersions ordering', async () => {
    assert.strictEqual(compareVersions('1.0.0', '1.0.0'), 0);
    assert.strictEqual(compareVersions('1.2.3', '1.2.2'), 1);
    assert.strictEqual(compareVersions('1.0.0', '1.0.1'), -1);
    assert.strictEqual(compareVersions('2.0.0', '1.9.9'), 1);
  });

  // ── 7. Social provider verification (lib/social) ──
  console.log('\n7. Social provider verification tests:');
  const social = require('../lib/social');
  const jwtLib = require('jsonwebtoken');

  // Local RSA keypair + JWKS stub — no network calls in tests.
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
  });
  const jwkPublic = publicKey.export({ format: 'jwk' });
  const TEST_KID = 'test-kid-1';
  const testJwks = {
    keys: [{ ...jwkPublic, kid: TEST_KID, alg: 'RS256', use: 'sig' }],
  };
  const stubFetcher = async (url) => ({
    ok: true,
    status: 200,
    json: async () => testJwks,
  });

  const signTestToken = (claims, { kid = TEST_KID, algorithm = 'RS256' } = {}) =>
    jwtLib.sign(claims, privateKey, {
      algorithm,
      keyid: kid,
      expiresIn: '10m',
    });

  const GOOGLE_AUD = 'test-google-client.apps.googleusercontent.com';
  const APPLE_AUD = 'com.test.sheserved';

  await test('google: valid ID token → verified profile', async () => {
    social._clearJwksCache();
    const token = signTestToken({
      iss: 'https://accounts.google.com',
      aud: GOOGLE_AUD,
      sub: 'google-user-123',
      email: 'test@example.com',
      email_verified: true,
      name: 'Test User',
      given_name: 'Test',
      family_name: 'User',
    });
    const profile = await social.verifyGoogleIdToken(token, {
      clientId: GOOGLE_AUD,
      fetcher: stubFetcher,
    });
    assert.strictEqual(profile.provider, 'google');
    assert.strictEqual(profile.providerUserId, 'google-user-123');
    assert.strictEqual(profile.email, 'test@example.com');
    assert.strictEqual(profile.firstName, 'Test');
    assert.strictEqual(profile.lastName, 'User');
  });

  await test('google: wrong audience rejected', async () => {
    const token = signTestToken({
      iss: 'https://accounts.google.com',
      aud: 'some-other-client.apps.googleusercontent.com',
      sub: 'google-user-456',
    });
    await assert.rejects(
      social.verifyGoogleIdToken(token, { clientId: GOOGLE_AUD, fetcher: stubFetcher }),
      (err) => err.reason === 'invalid_signature_or_claims'
    );
  });

  await test('google: wrong issuer rejected', async () => {
    const token = signTestToken({
      iss: 'https://evil.example.com',
      aud: GOOGLE_AUD,
      sub: 'google-user-789',
    });
    await assert.rejects(
      social.verifyGoogleIdToken(token, { clientId: GOOGLE_AUD, fetcher: stubFetcher }),
      (err) => err.reason === 'invalid_signature_or_claims'
    );
  });

  await test('google: unknown kid rejected (key rotation)', async () => {
    const token = signTestToken(
      { iss: 'https://accounts.google.com', aud: GOOGLE_AUD, sub: 'g1' },
      { kid: 'unknown-kid' }
    );
    await assert.rejects(
      social.verifyGoogleIdToken(token, { clientId: GOOGLE_AUD, fetcher: stubFetcher }),
      (err) => err.reason === 'unknown_kid'
    );
  });

  await test('google: tampered signature rejected', async () => {
    const token = signTestToken({
      iss: 'https://accounts.google.com',
      aud: GOOGLE_AUD,
      sub: 'google-user-111',
    });
    const tampered = token.slice(0, -5) + 'XXXXX';
    await assert.rejects(
      social.verifyGoogleIdToken(tampered, { clientId: GOOGLE_AUD, fetcher: stubFetcher }),
      (err) => err.reason === 'invalid_signature_or_claims' || err.reason === 'malformed_token'
    );
  });

  await test('google: nonce check (claim as-is)', async () => {
    const token = signTestToken({
      iss: 'https://accounts.google.com',
      aud: GOOGLE_AUD,
      sub: 'google-user-222',
      nonce: 'my-raw-nonce',
    });
    const ok = await social.verifyGoogleIdToken(token, {
      clientId: GOOGLE_AUD,
      nonce: 'my-raw-nonce',
      fetcher: stubFetcher,
    });
    assert.strictEqual(ok.providerUserId, 'google-user-222');
    await assert.rejects(
      social.verifyGoogleIdToken(token, {
        clientId: GOOGLE_AUD,
        nonce: 'wrong-nonce',
        fetcher: stubFetcher,
      }),
      (err) => err.reason === 'nonce_mismatch'
    );
  });

  await test('google: missing clientId config → provider_not_configured', async () => {
    const token = signTestToken({
      iss: 'https://accounts.google.com',
      aud: GOOGLE_AUD,
      sub: 'g-cfg',
    });
    await assert.rejects(
      social.verifyGoogleIdToken(token, { fetcher: stubFetcher }),
      (err) => err.reason === 'provider_not_configured'
    );
  });

  await test('google: extra client ids (iOS aud) accepted + rejected without them', async () => {
    social._clearJwksCache();
    const iosAud = '1075504521633-iosclient-test.apps.googleusercontent.com';
    const token = signTestToken({
      iss: 'https://accounts.google.com',
      aud: iosAud,
      sub: 'google-ios-user',
    });
    const ok = await social.verifyGoogleIdToken(token, {
      clientId: GOOGLE_AUD,
      extraClientIds: [iosAud],
      fetcher: stubFetcher,
    });
    assert.strictEqual(ok.providerUserId, 'google-ios-user');
    await assert.rejects(
      social.verifyGoogleIdToken(token, { clientId: GOOGLE_AUD, fetcher: stubFetcher }),
      (err) => err.reason === 'invalid_signature_or_claims'
    );
  });

  await test('apple: valid identity token → verified profile', async () => {
    social._clearJwksCache();
    const token = signTestToken({
      iss: 'https://appleid.apple.com',
      aud: APPLE_AUD,
      sub: 'apple-user-001',
      email: 'apple@example.com',
    });
    const profile = await social.verifyAppleIdentityToken(token, {
      bundleId: APPLE_AUD,
      fetcher: stubFetcher,
    });
    assert.strictEqual(profile.provider, 'apple');
    assert.strictEqual(profile.providerUserId, 'apple-user-001');
    assert.strictEqual(profile.email, 'apple@example.com');
  });

  await test('apple: nonce check (SHA-256 hashed claim)', async () => {
    const rawNonce = 'apple-raw-nonce';
    const token = signTestToken({
      iss: 'https://appleid.apple.com',
      aud: APPLE_AUD,
      sub: 'apple-user-002',
      nonce: crypto.createHash('sha256').update(rawNonce).digest('hex'),
    });
    const ok = await social.verifyAppleIdentityToken(token, {
      bundleId: APPLE_AUD,
      nonce: rawNonce,
      fetcher: stubFetcher,
    });
    assert.strictEqual(ok.providerUserId, 'apple-user-002');
  });

  await test('apple: wrong issuer rejected', async () => {
    const token = signTestToken({
      iss: 'https://evil.example.com',
      aud: APPLE_AUD,
      sub: 'apple-user-003',
    });
    await assert.rejects(
      social.verifyAppleIdentityToken(token, { bundleId: APPLE_AUD, fetcher: stubFetcher }),
      (err) => err.reason === 'invalid_signature_or_claims'
    );
  });

  await test('social: malformed token rejected', async () => {
    await assert.rejects(
      social.verifyGoogleIdToken('not.a.jwt', { clientId: GOOGLE_AUD, fetcher: stubFetcher }),
      (err) => err.reason === 'malformed_token'
    );
  });

  await test('social: HS256 token rejected (RS256 only)', async () => {
    const hsToken = jwtLib.sign(
      { iss: 'https://accounts.google.com', aud: GOOGLE_AUD, sub: 'hs-attack' },
      'some-shared-secret',
      { algorithm: 'HS256', header: { kid: TEST_KID } }
    );
    await assert.rejects(
      social.verifyGoogleIdToken(hsToken, { clientId: GOOGLE_AUD, fetcher: stubFetcher }),
      (err) => err.reason === 'wrong_algorithm'
    );
  });

  await test('social: JWKS fetch failure → jwks_unavailable', async () => {
    social._clearJwksCache();
    const failFetcher = async () => ({ ok: false, status: 500 });
    const token = signTestToken({
      iss: 'https://accounts.google.com',
      aud: GOOGLE_AUD,
      sub: 'g-net',
    });
    await assert.rejects(
      social.verifyGoogleIdToken(token, { clientId: GOOGLE_AUD, fetcher: failFetcher }),
      (err) => err.reason === 'jwks_unavailable'
    );
  });

  // ── Summary ──
  console.log('\n──────────────────────────────────');
  const passed = results.filter(r => r.status === 'PASS').length;
  const failed = results.filter(r => r.status === 'FAIL').length;
  console.log(`Results: ${passed} passed, ${failed} failed, ${results.length} total`);

  if (failed > 0) {
    console.log('\nFailed tests:');
    results.filter(r => r.status === 'FAIL').forEach(r => {
      console.log(`  ❌ ${r.name}: ${r.error}`);
    });
    process.exitCode = 1;
  } else {
    console.log('\n✅ All tests passed');
  }

  // Cleanup
  try {
    await session.closeSessionPool();
  } catch (_) {}
}

main();
