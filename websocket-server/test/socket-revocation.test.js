'use strict';

/**
 * Unit tests for services/socket-revocation.js
 *
 * No real Redis needed — the shared middleware/redis-client module is swapped
 * in require.cache for a fake BEFORE the module under test is loaded (its
 * require() is lazy inside _getRedis()), and services/room-authorization is
 * stubbed the same way. The fakes record calls so the tests can assert on
 * subscriber lifecycle without a server.
 *
 * Run: node --test test/socket-revocation.test.js   (or: npm test)
 */

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('node:events');

const SVC_PATH = require.resolve('../services/socket-revocation');
const REDIS_CLIENT_PATH = require.resolve('../middleware/redis-client');
const ROOM_AUTH_PATH = require.resolve('../services/room-authorization');
const REVOKE_CHANNEL = 'socket:revoke';

// ── Fakes ─────────────────────────────────────────────────────────────

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

function makeSubscriber({ initiallyReady = false, subscribeError = null } = {}) {
  const sub = new EventEmitter();
  sub.status = initiallyReady ? 'ready' : 'connecting';
  sub.subscribeCalls = [];
  sub.disconnectCalls = 0;
  sub.unsubscribeCalls = 0;
  sub.subscribe = (channel, cb) => {
    sub.subscribeCalls.push({ channel, statusAtCall: sub.status });
    setImmediate(() => cb(subscribeError));
  };
  sub.unsubscribe = async () => {
    sub.unsubscribeCalls++;
  };
  sub.disconnect = () => {
    sub.disconnectCalls++;
    sub.status = 'end';
  };
  sub._becomeReady = () => {
    sub.status = 'ready';
    sub.emit('ready');
  };
  return sub;
}

function makeSharedRedis() {
  const redis = new EventEmitter();
  redis.status = 'ready';
  redis.duplicateCalls = 0;
  redis.subs = [];
  redis.published = [];
  redis.publish = async (channel, message) => {
    redis.published.push([channel, message]);
    return 1;
  };
  redis.makeNextSubscriber = () => makeSubscriber({ initiallyReady: true });
  redis.duplicate = () => {
    redis.duplicateCalls++;
    const sub = redis.makeNextSubscriber();
    redis.subs.push(sub);
    return sub;
  };
  return redis;
}

function makeIo(socketList = []) {
  const sockets = new Map();
  socketList.forEach((s, i) => sockets.set(`sock-${i}`, s));
  return { sockets: { sockets } };
}

function makeSocket(userId, sessionId = null) {
  return {
    userId,
    sessionId,
    emitCalls: [],
    disconnectCalls: 0,
    emit(ev, data) {
      this.emitCalls.push([ev, data]);
    },
    disconnect() {
      this.disconnectCalls++;
    },
  };
}

const tick = () => new Promise((resolve) => setImmediate(resolve));
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function setup() {
  const redis = makeSharedRedis();
  const invalidated = [];
  seedModuleCache(REDIS_CLIENT_PATH, { redis, isHealthy: async () => true });
  seedModuleCache(ROOM_AUTH_PATH, {
    invalidateMemberCacheForUser: async (userId) => {
      invalidated.push(userId);
    },
  });
  delete require.cache[SVC_PATH];
  return { svc: require('../services/socket-revocation'), redis, invalidated };
}

// ── Tests ─────────────────────────────────────────────────────────────

test('waits for the subscriber\'s own ready event before subscribing', async () => {
  const { svc, redis } = setup();
  redis.makeNextSubscriber = () => makeSubscriber({ initiallyReady: false });
  svc.initSocketRevocation(makeIo());

  const sub = redis.subs[0];
  assert.ok(sub);
  // Regression guard: the buggy version issued subscribe() while the
  // duplicated client was still 'connecting', which ioredis rejected with
  // "Stream isn't writeable and enableOfflineQueue options is false" every 2s.
  assert.equal(sub.subscribeCalls.length, 0);

  sub._becomeReady();
  await tick();
  await tick();

  assert.deepEqual(
    sub.subscribeCalls.map((c) => c.channel),
    [REVOKE_CHANNEL]
  );
  assert.equal(sub.subscribeCalls[0].statusAtCall, 'ready');

  svc.shutdown();
  assert.equal(sub.unsubscribeCalls, 1); // proves the sub was registered
});

test('disconnects a failed subscriber and retries with a fresh client', async () => {
  const { svc, redis } = setup();
  let attempt = 0;
  redis.makeNextSubscriber = () => {
    attempt++;
    return makeSubscriber({
      initiallyReady: true,
      subscribeError: attempt === 1 ? new Error('boom') : null,
    });
  };
  svc.initSocketRevocation(makeIo());
  await tick();
  await tick();

  const first = redis.subs[0];
  assert.equal(first.disconnectCalls, 1); // no half-open/leaked connection

  // Retry (SUBSCRIBE_RETRY_MS = 2000) must create a NEW client — never reuse
  // the dead one.
  await sleep(2300);
  assert.equal(redis.duplicateCalls, 2);
  const second = redis.subs[1];
  assert.equal(second.subscribeCalls[0].channel, REVOKE_CHANNEL);
  assert.equal(second.subscribeCalls[0].statusAtCall, 'ready');

  svc.shutdown();
  assert.equal(second.unsubscribeCalls, 1);
});

test('delivers channel messages to handleRevocation and disconnects only matching sockets', async () => {
  const { svc, redis, invalidated } = setup();
  const s1 = makeSocket('u1', 'sess-1');
  const s2 = makeSocket('u1', 'sess-2');
  const s3 = makeSocket('u2', 'sess-3');
  svc.initSocketRevocation(makeIo([s1, s2, s3]));
  await tick();
  await tick();
  const sub = redis.subs[0];

  sub.emit('message', REVOKE_CHANNEL, JSON.stringify({ userId: 'u1' }));
  await tick();

  assert.equal(s1.disconnectCalls, 1);
  assert.equal(s2.disconnectCalls, 1); // null sessionId = revoke all of u1
  assert.equal(s3.disconnectCalls, 0);
  assert.deepEqual(s1.emitCalls[0], ['session-revoked', { reason: 'session_revoked' }]);
  assert.deepEqual(invalidated, ['u1']);

  const before1 = s1.disconnectCalls;
  const before2 = s2.disconnectCalls;
  sub.emit('message', REVOKE_CHANNEL, JSON.stringify({ userId: 'u1', sessionId: 'sess-1' }));
  await tick();

  assert.equal(s1.disconnectCalls, before1 + 1); // session matches
  assert.equal(s2.disconnectCalls, before2); // different session skipped
  assert.equal(s3.disconnectCalls, 0);

  // Wrong channel is ignored.
  sub.emit('message', 'other:channel', JSON.stringify({ userId: 'u1' }));
  await tick();
  assert.equal(s1.disconnectCalls, before1 + 1);

  svc.shutdown();
});

test('clears the subscriber on permanent end so publishRevocation falls back locally', async () => {
  const { svc, redis } = setup();
  const s1 = makeSocket('u1');
  svc.initSocketRevocation(makeIo([s1]));
  await tick();
  await tick();
  const sub = redis.subs[0];

  // While subscribed, publish goes through the channel — no local handling.
  await svc.publishRevocation({ userId: 'u1' });
  assert.equal(s1.disconnectCalls, 0);
  assert.deepEqual(redis.published[0], [REVOKE_CHANNEL, JSON.stringify({ userId: 'u1', sessionId: null })]);

  sub.emit('end'); // permanent close -> registration cleared, retry scheduled
  await svc.publishRevocation({ userId: 'u1' });
  assert.equal(s1.disconnectCalls, 1);
  assert.equal(s1.emitCalls[0][0], 'session-revoked');

  svc.shutdown(); // clears the scheduled retry timer
});

test('falls back locally when there is no active subscriber or publish fails', async () => {
  const { svc, redis } = setup();
  // Subscriber stays 'connecting' forever -> _subscriber never registered.
  redis.makeNextSubscriber = () => makeSubscriber({ initiallyReady: false });
  const s1 = makeSocket('u1');
  svc.initSocketRevocation(makeIo([s1]));

  await svc.publishRevocation({ userId: 'u1' });
  assert.equal(s1.disconnectCalls, 1);

  // Publish failure (Redis down) must also run the local handler.
  redis.publish = async () => {
    throw new Error('redis down');
  };
  await svc.publishRevocation({ userId: 'u1' });
  assert.equal(s1.disconnectCalls, 2);

  svc.shutdown();
});
