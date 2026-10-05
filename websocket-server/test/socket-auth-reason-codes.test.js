'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');

process.env.JWT_ACTIVE_KID = 'test-active';
process.env.JWT_ACTIVE_SECRET = 'test-active-secret-32-bytes-minimum-value';
process.env.JWT_ISSUER = 'sheserved';
process.env.JWT_AUDIENCE = 'sheserved-app';

const LOGGER_PATH = require.resolve('../utils/logger');
const REDIS_PATH = require.resolve('../middleware/redis-client');
const GATEWAY_PATH = require.resolve('../db/supabase-gateway-pool');
const SOCKET_AUTH_PATH = require.resolve('../middleware/socket-auth');
const USER_ID = '11111111-1111-4111-8111-111111111111';
const SESSION_ID = '22222222-2222-4222-8222-222222222222';
const ACTIVE_SECRET = process.env.JWT_ACTIVE_SECRET;
const logs = [];
const redisKeys = [];

function seedModuleCache(path, exports) {
  require.cache[path] = {
    id: path,
    filename: path,
    loaded: true,
    exports,
    parent: null,
    children: [],
    paths: [],
  };
}

seedModuleCache(LOGGER_PATH, {
  warn: (fields, message) => logs.push({ level: 'warn', fields, message }),
  error: (fields, message) => logs.push({ level: 'error', fields, message }),
});
seedModuleCache(REDIS_PATH, {
  redis: {
    incr: async (key) => {
      redisKeys.push(key);
      return 1;
    },
    expire: async () => 1,
  },
});
seedModuleCache(GATEWAY_PATH, {
  withTransaction: async (_userId, callback) =>
    callback({
      query: async (sql) => {
        if (sql.includes('public.users')) {
          return { rows: [{ id: USER_ID, is_active: true, user_category_id: 'admin' }] };
        }
        if (sql.includes('public.sessions')) {
          return { rows: [{ revoked_at: new Date() }] };
        }
        return { rows: [] };
      },
    }),
});

const { socketAuthMiddleware } = require('../middleware/socket-auth');
const authMiddleware = socketAuthMiddleware({ getPool: () => null, supabaseForSync: null });

function makeToken({ secret = ACTIVE_SECRET, kid = 'test-active', expiresIn = 900, sessionId } = {}) {
  return jwt.sign(
    {
      sub: USER_ID,
      role: 'admin',
      iss: process.env.JWT_ISSUER,
      aud: process.env.JWT_AUDIENCE,
      typ: 'access',
      ...(sessionId ? { sid: sessionId } : {}),
    },
    secret,
    { algorithm: 'HS256', keyid: kid, expiresIn }
  );
}

function authenticate(token) {
  const socket = { handshake: { auth: { token }, headers: {} } };
  return new Promise((resolve) => {
    authMiddleware(socket, (error) => resolve({ error, socket }));
  });
}

test('returns stable reason codes and records safe rejection diagnostics', async () => {
  const expired = makeToken({ expiresIn: -5 });
  const wrongKeyId = makeToken({ kid: 'unknown-kid' });
  const invalidSignature = makeToken({ secret: 'different-signing-secret-32-bytes-minimum' });

  const expiredResult = await authenticate(expired);
  const malformedResult = await authenticate('not-a-jwt');
  const unknownKeyResult = await authenticate(wrongKeyId);
  const invalidSignatureResult = await authenticate(invalidSignature);
  const revokedResult = await authenticate(makeToken({ sessionId: SESSION_ID }));

  assert.equal(expiredResult.error?.data?.code, 'token_expired');
  assert.equal(malformedResult.error?.data?.code, 'malformed_token');
  assert.equal(unknownKeyResult.error?.data?.code, 'unknown_kid');
  assert.equal(invalidSignatureResult.error?.data?.code, 'invalid_signature');
  assert.equal(revokedResult.error?.data?.code, 'session_revoked');

  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(logs.length, 5);
  assert.ok(logs.every((entry) => entry.fields.tokenLength > 0));
  assert.ok(logs.every((entry) => !JSON.stringify(entry).includes(expired)));
  assert.equal(redisKeys.length, 5);
  assert.ok(redisKeys.every((key) => key.startsWith('socket:auth:rejections:')));
});
