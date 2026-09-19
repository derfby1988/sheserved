#!/usr/bin/env node
'use strict';

/**
 * Phase 13.3 — Verified Identity test harness (P0 preflight)
 * ─────────────────────────────────────────────────────────────
 * Security contract tests required by Match_Sport_PLAN Phase 13.3 step 1:
 *   - forged / malformed / expired / unknown-kid / wrong-typ tokens
 *   - revoked session  → 401
 *   - inactive user    → 403
 *   - actor mismatch   → verified identity wins / request rejected
 *   - anonymous access → passes compatibility path, rejected on strict routes
 *
 * Runs without a live database: the gateway pool and local pool are stubbed.
 * Socket-level tests for middleware/socket-auth.js are appended by step 4
 * of the rollout (same harness file, same assertions).
 *
 * Usage:
 *   node scripts/test-phase-13-3-auth.js
 */

const assert = require('assert');
const crypto = require('crypto');

// Deterministic test keys — set BEFORE requiring lib modules because
// lib/jwt.js reads env at module-load time.
process.env.JWT_ACTIVE_KID = 'test-active';
process.env.JWT_ACTIVE_SECRET = crypto.randomBytes(32).toString('hex');
process.env.JWT_PREVIOUS_KID = 'test-previous';
process.env.JWT_PREVIOUS_SECRET = crypto.randomBytes(32).toString('hex');
process.env.JWT_ISSUER = 'sheserved-test';
process.env.JWT_AUDIENCE = 'sheserved-test-app';

const jwtLib = require('../lib/jwt');
const { verifyToken } = require('../middleware/auth');
const gateway = require('../db/supabase-gateway-pool');

// ── helpers ────────────────────────────────────────────────────────────

const results = [];
async function test(name, fn) {
  try {
    await fn();
    results.push({ name, status: 'PASS' });
    console.log(`  ✅ ${name}`);
  } catch (err) {
    results.push({ name, status: 'FAIL', error: err.message });
    console.log(`  ❌ ${name}: ${err.message}`);
  }
}

/** Minimal Express req/res/next fakes. */
function fakeReq(headers = {}, extra = {}) {
  return { headers, path: extra.path || '/', params: extra.params || {}, ...extra };
}
function fakeRes() {
  const res = { statusCode: null, body: null };
  res.status = (code) => { res.statusCode = code; return res; };
  res.json = (body) => { res.body = body; return res; };
  return res;
}
function runMiddleware(mw, req) {
  return new Promise((resolve) => {
    const res = fakeRes();
    mw(req, res, () => resolve({ req, res, nextCalled: true }));
    // If middleware answered directly, resolve on next tick.
    setImmediate(() => resolve({ req, res, nextCalled: false }));
  });
}

/** Stub gateway withTransaction → returns canned verify result. */
function stubGateway(fn) {
  const original = gateway.withTransaction;
  gateway.withTransaction = fn;
  return () => { gateway.withTransaction = original; };
}

const USER_ID = '11111111-2222-3333-4444-555555555555';
const SESSION_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const OTHER_USER = '99999999-8888-7777-6666-555555555555';

const gatewayOk = async (userId, cb) => {
  const fakeClient = {
    query: async (sql) => {
      if (sql.includes('FROM public.users')) {
        return { rows: [{ id: USER_ID, is_active: true, user_category_id: 'consumer' }] };
      }
      if (sql.includes('FROM public.sessions')) {
        return { rows: [{ revoked_at: null }] };
      }
      return { rows: [] };
    },
  };
  return cb(fakeClient);
};

const localPoolOk = {
  query: async () => ({
    rows: [{ id: USER_ID, is_active: true, user_category_id: 'consumer' }],
  }),
};

async function main() {
  console.log('Phase 13.3 — Verified Identity Test Harness\n');

  // ── 1. Token forgery / malformation ─────────────────────────────────
  console.log('1. Token forgery & malformation:');

  await test('forged signature (right claims, wrong key) → reject', async () => {
    const forged = require('jsonwebtoken').sign(
      { sub: USER_ID, role: 'admin', iss: 'sheserved-test', aud: 'sheserved-test-app', typ: 'access' },
      crypto.randomBytes(32).toString('hex'),
      { algorithm: 'HS256', keyid: 'test-active' }
    );
    assert.throws(() => jwtLib.verifyAccessToken(forged));
  });

  await test('unknown kid → reject', async () => {
    const token = require('jsonwebtoken').sign(
      { sub: USER_ID, iss: 'sheserved-test', aud: 'sheserved-test-app', typ: 'access' },
      process.env.JWT_ACTIVE_SECRET,
      { algorithm: 'HS256', keyid: 'evil-key' }
    );
    assert.throws(() => jwtLib.verifyAccessToken(token), /Unknown key id/);
  });

  await test('alg=none token → reject', async () => {
    const header = Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url');
    const payload = Buffer.from(JSON.stringify({ sub: USER_ID, typ: 'access' })).toString('base64url');
    assert.throws(() => jwtLib.verifyAccessToken(`${header}.${payload}.`));
  });

  await test('expired token → reject', async () => {
    const token = require('jsonwebtoken').sign(
      { sub: USER_ID, iss: 'sheserved-test', aud: 'sheserved-test-app', typ: 'access' },
      process.env.JWT_ACTIVE_SECRET,
      { algorithm: 'HS256', keyid: 'test-active', expiresIn: -10 }
    );
    assert.throws(() => jwtLib.verifyAccessToken(token), /expired/);
  });

  await test('refresh token used as access → reject', async () => {
    const refresh = jwtLib.signRefreshToken({ userId: USER_ID });
    assert.throws(() => jwtLib.verifyAccessToken(refresh));
  });

  await test('tampered payload → reject', async () => {
    const token = jwtLib.signAccessToken({ userId: USER_ID });
    const parts = token.split('.');
    const evil = Buffer.from(JSON.stringify({ sub: OTHER_USER, typ: 'access' })).toString('base64url');
    assert.throws(() => jwtLib.verifyAccessToken(`${parts[0]}.${evil}.${parts[2]}`));
  });

  // ── 2. HTTP middleware — verified identity contract ──────────────────
  console.log('\n2. HTTP middleware (verifyToken):');

  await test('valid Bearer JWT → identity attached (source=jwt)', async () => {
    const restore = stubGateway(gatewayOk);
    try {
      const token = jwtLib.signAccessToken({ userId: USER_ID, role: 'consumer', sessionId: SESSION_ID });
      const { req, nextCalled } = await runMiddleware(
        verifyToken(localPoolOk),
        fakeReq({ authorization: `Bearer ${token}` })
      );
      assert.strictEqual(nextCalled, true);
      assert.strictEqual(req.userId, USER_ID);
      assert.strictEqual(req.identitySource, 'jwt');
      assert.strictEqual(req.sessionId, SESSION_ID);
    } finally { restore(); }
  });

  await test('forged Bearer → 401 (never falls back to x-user-id)', async () => {
    const restore = stubGateway(gatewayOk);
    try {
      const forged = require('jsonwebtoken').sign(
        { sub: USER_ID, iss: 'sheserved-test', aud: 'sheserved-test-app', typ: 'access' },
        'wrong-secret-wrong-secret-wrong-sec',
        { algorithm: 'HS256', keyid: 'test-active' }
      );
      const { res, nextCalled } = await runMiddleware(
        verifyToken(localPoolOk),
        fakeReq({ authorization: `Bearer ${forged}`, 'x-user-id': USER_ID })
      );
      assert.strictEqual(nextCalled, false);
      assert.strictEqual(res.statusCode, 401);
    } finally { restore(); }
  });

  await test('revoked session → 401', async () => {
    const restore = stubGateway(async (userId, cb) => {
      const client = {
        query: async (sql) => {
          if (sql.includes('public.users')) {
            return { rows: [{ id: USER_ID, is_active: true, user_category_id: 'consumer' }] };
          }
          if (sql.includes('public.sessions')) {
            return { rows: [{ revoked_at: new Date() }] };
          }
          return { rows: [] };
        },
      };
      return cb(client);
    });
    try {
      const token = jwtLib.signAccessToken({ userId: USER_ID, sessionId: SESSION_ID });
      const { res, nextCalled } = await runMiddleware(
        verifyToken(localPoolOk),
        fakeReq({ authorization: `Bearer ${token}` })
      );
      assert.strictEqual(nextCalled, false);
      assert.strictEqual(res.statusCode, 401);
      assert.match(res.body.error, /revoked/i);
    } finally { restore(); }
  });

  await test('inactive user → 403', async () => {
    const restore = stubGateway(async (userId, cb) => {
      const client = {
        query: async (sql) => {
          if (sql.includes('public.users')) {
            return { rows: [{ id: USER_ID, is_active: false, user_category_id: 'consumer' }] };
          }
          return { rows: [] };
        },
      };
      return cb(client);
    });
    try {
      const token = jwtLib.signAccessToken({ userId: USER_ID });
      const { res, nextCalled } = await runMiddleware(
        verifyToken(localPoolOk),
        fakeReq({ authorization: `Bearer ${token}` })
      );
      assert.strictEqual(nextCalled, false);
      assert.strictEqual(res.statusCode, 403);
    } finally { restore(); }
  });

  await test('x-user-id only → legacy identity (compat window)', async () => {
    const { req, nextCalled } = await runMiddleware(
      verifyToken(localPoolOk),
      fakeReq({ 'x-user-id': USER_ID })
    );
    assert.strictEqual(nextCalled, true);
    assert.strictEqual(req.userId, USER_ID);
    assert.strictEqual(req.identitySource, 'legacy_header');
  });

  await test('anonymous (no credentials) → passes with null identity', async () => {
    const { req, nextCalled } = await runMiddleware(verifyToken(localPoolOk), fakeReq());
    assert.strictEqual(nextCalled, true);
    assert.strictEqual(req.userId, null);
    assert.strictEqual(req.identitySource, undefined);
  });

  // ── 3. Strict-route contract (added in step 2 of the rollout) ────────
  console.log('\n3. Strict-route / actor-mismatch contract:');

  const {
    requireVerifiedIdentity,
    assertActorMatches,
  } = require('../middleware/auth');

  await test('requireVerifiedIdentity: legacy x-user-id → 401', async () => {
    const mw = requireVerifiedIdentity();
    const req = fakeReq({ 'x-user-id': USER_ID });
    req.user = { id: USER_ID };
    req.userId = USER_ID;
    req.identitySource = 'legacy_header';
    const { res, nextCalled } = await runMiddleware(mw, req);
    assert.strictEqual(nextCalled, false);
    assert.strictEqual(res.statusCode, 401);
  });

  await test('requireVerifiedIdentity: jwt identity → next()', async () => {
    const mw = requireVerifiedIdentity();
    const req = fakeReq();
    req.user = { id: USER_ID };
    req.userId = USER_ID;
    req.identitySource = 'jwt';
    const { nextCalled } = await runMiddleware(mw, req);
    assert.strictEqual(nextCalled, true);
  });

  await test('requireVerifiedIdentity: anonymous → 401', async () => {
    const mw = requireVerifiedIdentity();
    const { res, nextCalled } = await runMiddleware(mw, fakeReq());
    assert.strictEqual(nextCalled, false);
    assert.strictEqual(res.statusCode, 401);
  });

  await test('assertActorMatches: body userId ≠ verified → 403', async () => {
    const mw = assertActorMatches((req) => req.body && req.body.userId);
    const req = fakeReq();
    req.userId = USER_ID;
    req.body = { userId: OTHER_USER };
    const { res, nextCalled } = await runMiddleware(mw, req);
    assert.strictEqual(nextCalled, false);
    assert.strictEqual(res.statusCode, 403);
  });

  await test('assertActorMatches: param userId = verified → next()', async () => {
    const mw = assertActorMatches((req) => req.params.userId || req.params.id);
    const req = fakeReq({}, { params: { id: USER_ID } });
    req.userId = USER_ID;
    const { nextCalled } = await runMiddleware(mw, req);
    assert.strictEqual(nextCalled, true);
  });

  // ── 4. Rollout flags ──────────────────────────────────────────────────
  console.log('\n4. Rollout flags:');

  await test('isStrictRoute honours STRICT_AUTH_ROUTES prefixes', async () => {
    process.env.STRICT_AUTH_ROUTES = 'users,locations';
    delete require.cache[require.resolve('../config/rollout-flags')];
    const flags = require('../config/rollout-flags');
    assert.strictEqual(flags.isStrictRoute('/api/users/abc'), true);
    assert.strictEqual(flags.isStrictRoute('/users/abc'), true);
    assert.strictEqual(flags.isStrictRoute('/api/videos/1'), false);
    delete process.env.STRICT_AUTH_ROUTES;
  });

  // ── 5. Socket connection authentication (step 4) ─────────────────────
  console.log('\n5. Socket connection auth (middleware/socket-auth.js):');

  const {
    socketAuthMiddleware,
    isVerifiedSocket,
    checkEventIdentity,
    claimedActorMismatch,
  } = require('../middleware/socket-auth');

  function fakeSocket({ auth = {}, headers = {} } = {}) {
    return {
      handshake: { auth, headers },
      emitted: [],
      emit(event, payload) { this.emitted.push([event, payload]); },
    };
  }
  function runSocketAuth(mw, socket) {
    return new Promise((resolve) => {
      mw(socket, (err) => resolve({ socket, error: err || null }));
    });
  }
  const mw = () =>
    socketAuthMiddleware({ getPool: () => localPoolOk, supabaseForSync: null });

  await test('valid Backend JWT socket → verified identity (source=jwt)', async () => {
    const restore = stubGateway(gatewayOk);
    try {
      const token = jwtLib.signAccessToken({ userId: USER_ID, sessionId: SESSION_ID });
      const { socket, error } = await runSocketAuth(mw(), fakeSocket({ auth: { token } }));
      assert.strictEqual(error, null);
      assert.strictEqual(socket.identitySource, 'jwt');
      assert.strictEqual(socket.userId, USER_ID);
      assert.strictEqual(isVerifiedSocket(socket), true);
    } finally { restore(); }
  });

  await test('forged token socket → hard reject (no legacy fallback)', async () => {
    const forged = require('jsonwebtoken').sign(
      { sub: USER_ID, iss: 'sheserved-test', aud: 'sheserved-test-app', typ: 'access' },
      'wrong-secret-wrong-secret-wrong-sec',
      { algorithm: 'HS256', keyid: 'test-active' }
    );
    const { error } = await runSocketAuth(
      mw(),
      fakeSocket({ auth: { token: forged, userId: USER_ID } })
    );
    assert.ok(error, 'expected rejection');
    assert.match(error.message, /invalid or expired/i);
  });

  await test('expired token socket → reject', async () => {
    const token = require('jsonwebtoken').sign(
      { sub: USER_ID, iss: 'sheserved-test', aud: 'sheserved-test-app', typ: 'access' },
      process.env.JWT_ACTIVE_SECRET,
      { algorithm: 'HS256', keyid: 'test-active', expiresIn: -5 }
    );
    const { error } = await runSocketAuth(mw(), fakeSocket({ auth: { token } }));
    assert.ok(error);
  });

  await test('revoked session socket → reject', async () => {
    const restore = stubGateway(async (userId, cb) => {
      const client = {
        query: async (sql) => {
          if (sql.includes('public.users')) {
            return { rows: [{ id: USER_ID, is_active: true, user_category_id: 'consumer' }] };
          }
          if (sql.includes('public.sessions')) {
            return { rows: [{ revoked_at: new Date() }] };
          }
          return { rows: [] };
        },
      };
      return cb(client);
    });
    try {
      const token = jwtLib.signAccessToken({ userId: USER_ID, sessionId: SESSION_ID });
      const { error } = await runSocketAuth(mw(), fakeSocket({ auth: { token } }));
      assert.ok(error);
      assert.match(error.message, /revoked/i);
    } finally { restore(); }
  });

  await test('legacy auth.userId → compat identity (source=legacy)', async () => {
    const { socket, error } = await runSocketAuth(
      mw(),
      fakeSocket({ auth: { userId: USER_ID } })
    );
    assert.strictEqual(error, null);
    assert.strictEqual(socket.identitySource, 'legacy');
    assert.strictEqual(socket.userId, USER_ID);
    assert.strictEqual(isVerifiedSocket(socket), false);
  });

  await test('STRICT_SOCKET_AUTH=true → legacy handshake rejected', async () => {
    process.env.STRICT_SOCKET_AUTH = 'true';
    delete require.cache[require.resolve('../config/rollout-flags')];
    delete require.cache[require.resolve('../middleware/socket-auth')];
    const strict = require('../middleware/socket-auth').socketAuthMiddleware({
      getPool: () => localPoolOk, supabaseForSync: null,
    });
    const { error } = await runSocketAuth(strict, fakeSocket({ auth: { userId: USER_ID } }));
    assert.ok(error, 'expected rejection');
    delete process.env.STRICT_SOCKET_AUTH;
    delete require.cache[require.resolve('../config/rollout-flags')];
    delete require.cache[require.resolve('../middleware/socket-auth')];
  });

  await test('anonymous socket → allowed with null identity (public allowlist)', async () => {
    const { socket, error } = await runSocketAuth(mw(), fakeSocket());
    assert.strictEqual(error, null);
    assert.strictEqual(socket.identitySource, 'anonymous');
    assert.strictEqual(socket.userId, null);
  });

  await test('checkEventIdentity: strict event requires verified socket', async () => {
    process.env.STRICT_SOCKET_EVENTS = 'user-connected';
    delete require.cache[require.resolve('../config/rollout-flags')];
    delete require.cache[require.resolve('../middleware/socket-auth')];
    const sa = require('../middleware/socket-auth');
    const anon = { identitySource: 'anonymous', userId: null };
    const legacy = { identitySource: 'legacy', userId: USER_ID };
    const jwtSock = { identitySource: 'jwt', userId: USER_ID };
    assert.strictEqual(sa.checkEventIdentity(anon, 'user-connected').code, 'VERIFIED_REQUIRED');
    assert.strictEqual(sa.checkEventIdentity(legacy, 'user-connected').code, 'VERIFIED_REQUIRED');
    assert.strictEqual(sa.checkEventIdentity(jwtSock, 'user-connected'), null);
    // non-strict event: anonymous denied, legacy OK
    assert.strictEqual(sa.checkEventIdentity(anon, 'video-interaction').code, 'AUTH_REQUIRED');
    assert.strictEqual(sa.checkEventIdentity(legacy, 'video-interaction'), null);
    delete process.env.STRICT_SOCKET_EVENTS;
    delete require.cache[require.resolve('../config/rollout-flags')];
    delete require.cache[require.resolve('../middleware/socket-auth')];
  });

  await test('claimedActorMismatch: payload ≠ socket → mismatch detected', async () => {
    const sock = { userId: USER_ID };
    assert.strictEqual(claimedActorMismatch(sock, OTHER_USER), true);
    assert.strictEqual(claimedActorMismatch(sock, USER_ID), false);
    assert.strictEqual(claimedActorMismatch(sock, null), false);
    assert.strictEqual(claimedActorMismatch({ userId: null }, OTHER_USER), false);
  });

  // ── Summary ──────────────────────────────────────────────────────────
  const passed = results.filter((r) => r.status === 'PASS').length;
  const failed = results.filter((r) => r.status === 'FAIL').length;
  console.log(`\n${'═'.repeat(50)}`);
  console.log(`Results: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}

main().catch((err) => {
  console.error('Harness crashed:', err);
  process.exit(1);
});
