'use strict';

/**
 * Unit tests for GET /api/videos/emergency/list?category_ids=... (Phase 20)
 *
 * Mounts the real router with a fake pool — no PostgreSQL/Redis needed.
 * The whole `../middleware` module is swapped in require.cache (like
 * socket-revocation.test.js does for redis-client) so cacheAside can be
 * asserted directly and all limiters become pass-through.
 *
 * Run: node --test test/emergency-list-filter.test.js   (or: npm test)
 */

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');

const ROUTE_PATH = require.resolve('../routes/video');
const MIDDLEWARE_PATH = require.resolve('../middleware/index.js');
const VIDEO_SERVICE_PATH = require.resolve('../services/video-service');
const SOCKET_SERVICE_PATH = require.resolve('../services/socket-service');
const FACE_BLUR_PATH = require.resolve('../services/face-blur-service');
const THUMBNAIL_SERVICE_PATH = require.resolve('../services/thumbnail-service');
const THUMBNAIL_QUEUE_PATH = require.resolve('../services/thumbnail-queue');
const WATERMARK_PATH = require.resolve('../services/watermark-service');
const VIDEO_UPLOAD_PATH = require.resolve('../utils/video-upload');

const UUID_A = '11111111-1111-4111-8111-111111111111';
const UUID_B = '22222222-2222-4222-8222-222222222222';

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

const pass = (req, res, next) => next();
const factory = () => pass;

function setup({ rows = [] } = {}) {
  // In-memory cacheAside so the test can prove filtered requests bypass it.
  const cache = new Map();
  const cacheKeys = [];
  const cacheAside = async (key, fetcher) => {
    cacheKeys.push(key);
    if (cache.has(key)) return cache.get(key);
    const value = await fetcher();
    cache.set(key, value);
    return value;
  };

  seedModuleCache(MIDDLEWARE_PATH, {
    strictRateLimiter: pass,
    rateLimiter: factory,
    idempotencyMiddleware: pass,
    duplicateCheckMiddleware: factory,
    cacheAside,
    invalidateCachePattern: async () => 0,
    TTL: { DEFAULT: 60 },
    requireAuth: pass,
    uploadQuotaLimiter: pass,
    ipLimiter: pass,
  });
  seedModuleCache(VIDEO_SERVICE_PATH, { init: () => {} });
  seedModuleCache(SOCKET_SERVICE_PATH, new Proxy({}, { get: () => () => {} }));
  seedModuleCache(FACE_BLUR_PATH, {});
  seedModuleCache(THUMBNAIL_SERVICE_PATH, {
    generateThumbnail: async () => null,
    uploadThumbnailToBunny: async () => null,
  });
  seedModuleCache(THUMBNAIL_QUEUE_PATH, {});
  seedModuleCache(WATERMARK_PATH, {});
  seedModuleCache(VIDEO_UPLOAD_PATH, {
    videoUpload: { single: factory, array: factory, fields: factory },
    photoUpload: { single: factory, array: factory, fields: factory },
    photoUploadErrorHandler: pass,
    MAX_VIDEO_BYTES: 0,
    MAX_PHOTO_BYTES: 0,
  });

  const queries = [];
  const pool = {
    query: async (sql, params) => {
      queries.push({ sql, params });
      return { rows };
    },
  };

  delete require.cache[ROUTE_PATH];
  const routerFactory = require('../routes/video');
  const app = express();
  app.use('/api/videos', routerFactory(pool, null));

  return { app, queries, cacheKeys };
}

async function withServer(setupResult, run) {
  const server = setupResult.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const { port } = server.address();
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((error) => (error ? reject(error) : resolve())),
    );
  }
}

test('no category_ids keeps the unfiltered cached path', async () => {
  const ctx = setup({ rows: [{ id: 'v1', type: 'emergency' }] });
  await withServer(ctx, async (base) => {
    const first = await fetch(`${base}/api/videos/emergency/list`);
    assert.equal(first.status, 200);
    const second = await fetch(`${base}/api/videos/emergency/list`);
    assert.equal(second.status, 200);
    // Second request served from cache-aside — only one pool query.
    assert.equal(ctx.queries.length, 1);
    assert.match(ctx.queries[0].sql, /ORDER BY v\.created_at DESC/);
    assert.deepEqual(ctx.cacheKeys, [
      'video:emergency:list:v3:1:20',
      'video:emergency:list:v3:1:20',
    ]);
    assert.equal(first.headers.get('x-emergency-category-filter'), null);
  });
});

test('valid category_ids filter the query, set the marker and bypass cache', async () => {
  const ctx = setup({ rows: [{ id: 'v1', category_id: UUID_A }] });
  await withServer(ctx, async (base) => {
    const res = await fetch(
      `${base}/api/videos/emergency/list?category_ids=${UUID_A},${UUID_B}`,
    );
    assert.equal(res.status, 200);
    assert.equal(res.headers.get('x-emergency-category-filter'), 'applied');
    assert.equal(ctx.queries.length, 1);
    assert.match(ctx.queries[0].sql, /v\.category_id = ANY\(\$3::uuid\[\]\)/);
    assert.match(ctx.queries[0].sql, /ORDER BY v\.created_at DESC, v\.id DESC/);
    assert.deepEqual(ctx.queries[0].params[2], [UUID_A, UUID_B]);
    assert.equal(ctx.cacheKeys.length, 0); // filtered requests bypass cache-aside

    // A second identical request must hit the DB again (no cache).
    await fetch(`${base}/api/videos/emergency/list?category_ids=${UUID_A},${UUID_B}`);
    assert.equal(ctx.queries.length, 2);
  });
});

test('duplicate and unordered ids are deduplicated and sorted', async () => {
  const ctx = setup({ rows: [] });
  await withServer(ctx, async (base) => {
    const res = await fetch(
      `${base}/api/videos/emergency/list?category_ids=${UUID_B}, ${UUID_A},${UUID_B}`,
    );
    assert.equal(res.status, 200);
    assert.deepEqual(ctx.queries[0].params[2], [UUID_A, UUID_B]);
  });
});

test('rejects malformed category_ids with 400, not 500', async () => {
  const ctx = setup({ rows: [] });
  await withServer(ctx, async (base) => {
    for (const bad of ['', 'not-a-uuid', `${UUID_A},bad`, ';;']) {
      const res = await fetch(
        `${base}/api/videos/emergency/list?category_ids=${encodeURIComponent(bad)}`,
      );
      assert.equal(res.status, 400, `expected 400 for "${bad}"`);
      const body = await res.json();
      assert.match(body.error, /category_ids/);
    }
    assert.equal(ctx.queries.length, 0); // never reached the DB
    assert.equal(ctx.cacheKeys.length, 0);
  });
});

test('rejects category_ids lists over the cap with 400', async () => {
  const ctx = setup({ rows: [] });
  await withServer(ctx, async (base) => {
    const many = Array.from(
      { length: 101 },
      (_, i) => `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`,
    );
    const res = await fetch(
      `${base}/api/videos/emergency/list?category_ids=${many.join(',')}`,
    );
    assert.equal(res.status, 400);
    assert.match((await res.json()).error, /exceeds maximum/);
    assert.equal(ctx.queries.length, 0);
  });
});

test('filtered and unfiltered requests do not share cache entries', async () => {
  const ctx = setup({ rows: [{ id: 'v1' }] });
  await withServer(ctx, async (base) => {
    await fetch(`${base}/api/videos/emergency/list`);
    await fetch(`${base}/api/videos/emergency/list?category_ids=${UUID_A}`);
    await fetch(`${base}/api/videos/emergency/list`);
    // unfiltered hit cache once (2 requests, 1 query) + filtered query = 2 total.
    assert.equal(ctx.queries.length, 2);
    // Only the unfiltered key exists — no per-combination key is created.
    assert.deepEqual([...new Set(ctx.cacheKeys)], [
      'video:emergency:list:v3:1:20',
    ]);
  });
});
