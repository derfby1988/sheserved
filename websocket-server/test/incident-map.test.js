'use strict';

/**
 * Unit tests for the Incident Overview Map (VIDEO_SYSTEM_PLAN.md §22)
 *
 * Covers:
 *   1. Age-bucket policy boundaries (contiguous, inclusive upper bounds,
 *      future/invalid timestamps never bucketed)
 *   2. Canonical coordinate validation ((0,0) sentinel, ranges)
 *   3. Query parsing/validation + mode selection (zoom threshold)
 *   4. Cursor round-trip + clustering + photo capping
 *   5. Route contract: GET /api/videos/emergency/map with a fake pool,
 *      Supabase RPC fallback on local failure, fail-closed 500 when both fail
 *
 * Mounts the real router with a fake pool — no PostgreSQL/Redis needed
 * (same require.cache pattern as emergency-list-filter.test.js).
 *
 * Run: node --test test/incident-map.test.js   (or: npm test)
 */

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
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
const INCIDENT_MAP_PATH = require.resolve('../services/incident-map');

const policy = require('../services/incident-map-policy');
const svc = require('../services/incident-map');

const UUID_A = '11111111-1111-4111-8111-111111111111';
const UUID_B = '22222222-2222-4222-8222-222222222222';
const UUID_C = '33333333-3333-4333-8333-333333333333';

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

// ──────────────────────────────────────────────────────────────
// 1. Age-bucket policy
// ──────────────────────────────────────────────────────────────

test('policy: bucket boundaries are contiguous and inclusive at the upper bound', () => {
  const now = Date.parse('2026-10-06T12:00:00Z');
  const at = (ms) => new Date(now - ms).toISOString();
  const H = policy.HOUR_MS;
  const D = policy.DAY_MS;

  assert.equal(policy.bucketForCreatedAt(at(0), now), 'red');
  assert.equal(policy.bucketForCreatedAt(at(24 * H), now), 'red');
  assert.equal(policy.bucketForCreatedAt(at(24 * H + 1), now), 'orange');
  assert.equal(policy.bucketForCreatedAt(at(7 * D), now), 'orange');
  assert.equal(policy.bucketForCreatedAt(at(7 * D + 1), now), 'gold');
  assert.equal(policy.bucketForCreatedAt(at(35 * D), now), 'gold');
  assert.equal(policy.bucketForCreatedAt(at(35 * D + 1), now), 'gray');
  assert.equal(policy.bucketForCreatedAt(at(365 * D), now), 'gray');
  assert.equal(policy.bucketForCreatedAt(at(365 * D + 1), now), 'black');
  // leap-year style long span still black, never a gap
  assert.equal(policy.bucketForCreatedAt(at(400 * D), now), 'black');
});

test('policy: future, missing and unparseable created_at are never bucketed', () => {
  const now = Date.parse('2026-10-06T12:00:00Z');
  assert.equal(policy.bucketForCreatedAt(new Date(now + 1).toISOString(), now), null);
  assert.equal(policy.bucketForCreatedAt(null, now), null);
  assert.equal(policy.bucketForCreatedAt(undefined, now), null);
  assert.equal(policy.bucketForCreatedAt('not-a-date', now), null);
  assert.equal(policy.bucketForAge(-1), null);
  assert.equal(policy.bucketForAge(Number.NaN), null);
});

test('policy: coordinate validation rejects out-of-range, non-finite and (0,0) sentinel', () => {
  assert.equal(policy.isValidCoordinate(13.7, 100.5), true);
  assert.equal(policy.isValidCoordinate('13.7', '100.5'), true);
  assert.equal(policy.isValidCoordinate(0, 0), false);
  assert.equal(policy.isValidCoordinate(91, 100), false);
  assert.equal(policy.isValidCoordinate(13, 181), false);
  assert.equal(policy.isValidCoordinate(Number.NaN, 100), false);
  assert.equal(policy.isValidCoordinate(null, 100), false);
});

// ──────────────────────────────────────────────────────────────
// 2. Query parsing / mode selection
// ──────────────────────────────────────────────────────────────

test('parseMapQuery: valid params and zoom-threshold mode selection', () => {
  const p = svc.parseMapQuery({
    category_id: UUID_A,
    bounds: '5.5,97.5,20.5,105.5',
    zoom: '11',
  });
  assert.equal(p.categoryId, UUID_A);
  assert.deepEqual(p.bounds, { south: 5.5, west: 97.5, north: 20.5, east: 105.5 });
  assert.equal(p.mode, 'clusters');
  assert.equal(svc.parseMapQuery({ category_id: UUID_A, bounds: '5.5,97.5,20.5,105.5', zoom: '12' }).mode, 'points');
  assert.equal(svc.parseMapQuery({ category_id: UUID_A, bounds: '5.5,97.5,20.5,105.5', zoom: '22' }).limit, svc.DEFAULT_PAGE_LIMIT);
  assert.equal(
    svc.parseMapQuery({ category_id: UUID_A, bounds: '5.5,97.5,20.5,105.5', zoom: '14', limit: '500' }).limit,
    500,
  );
});

test('parseMapQuery: rejects malformed input', () => {
  const bad = (q) => assert.throws(() => svc.parseMapQuery(q), (e) => e.statusCode === 400);
  bad({});
  bad({ category_id: 'not-a-uuid', bounds: '1,2,3,4', zoom: '5' });
  bad({ category_id: UUID_A, bounds: '1,2,3', zoom: '5' });
  bad({ category_id: UUID_A, bounds: 'a,b,c,d', zoom: '5' });
  bad({ category_id: UUID_A, bounds: '20.5,97.5,5.5,105.5', zoom: '5' }); // south > north
  bad({ category_id: UUID_A, bounds: '5.5,105.5,20.5,97.5', zoom: '5' }); // west > east
  bad({ category_id: UUID_A, bounds: '95.5,97.5,96.5,105.5', zoom: '5' }); // lat out of range
  bad({ category_id: UUID_A, bounds: '5.5,97.5,20.5,105.5', zoom: '23' });
  bad({ category_id: UUID_A, bounds: '5.5,97.5,20.5,105.5', zoom: '5.5' });
  bad({ category_id: UUID_A, bounds: '5.5,97.5,20.5,105.5', zoom: '5', limit: '501' });
  bad({ category_id: UUID_A, bounds: '5.5,97.5,20.5,105.5', zoom: '5', limit: '0' });
});

// ──────────────────────────────────────────────────────────────
// 3. Cursor / clustering / photos / response
// ──────────────────────────────────────────────────────────────

test('cursor: round-trip and invalid inputs', () => {
  const row = { created_at: '2026-10-06T12:00:00.000Z', id: UUID_A };
  const cursor = svc.encodeCursor(row);
  assert.deepEqual(svc.decodeCursor(cursor), { createdAt: row.created_at, id: UUID_A });
  assert.equal(svc.decodeCursor('!!!not-base64'), null);
  assert.equal(svc.decodeCursor(Buffer.from('{"c":"nope","i":"x"}').toString('base64url')), null);
});

test('clusterPoints: nearby points merge with per-bucket counts and centroid', () => {
  const now = Date.parse('2026-10-06T12:00:00Z');
  const rows = [
    { id: UUID_A, category_id: UUID_C, created_at: new Date(now - policy.HOUR_MS).toISOString(), latitude: 13.7, longitude: 100.5 },
    { id: UUID_B, category_id: UUID_C, created_at: new Date(now - 2 * policy.DAY_MS).toISOString(), latitude: 13.71, longitude: 100.51 },
  ];
  const points = svc.normalizeIncidentRows(rows, now);
  const clusters = svc.clusterPoints(points, 5);
  assert.equal(clusters.length, 1);
  assert.equal(clusters[0].count, 2);
  assert.equal(clusters[0].byBucket.red, 1);
  assert.equal(clusters[0].byBucket.orange, 1);
  assert.ok(Math.abs(clusters[0].lat - 13.705) < 1e-9);
  // far apart at high zoom → separate cells
  const far = svc.clusterPoints(points, 12);
  assert.equal(far.length, 2);
});

test('attachPhotos: caps at 15 with equal per-sender rounds and pending slots', () => {
  const points = [{ id: UUID_A, photos: [] }, { id: UUID_B, photos: [] }];
  const senders = ['user-a', 'user-b', 'user-c'];
  const photoRows = [];
  const base = Date.parse('2026-10-06T12:00:00Z');
  let previewRank = 0;
  for (let rank = 1; rank <= 7; rank++) {
    for (let i = 0; i < senders.length; i++) {
      photoRows.push({
        video_id: UUID_A,
        user_id: senders[i],
        id: `${senders[i]}-${rank}`,
        photo_url: `u-${senders[i]}-${rank}`,
        blur_status: 'completed',
        created_at: new Date(base - ((rank - 1) * senders.length + i) * 1000).toISOString(),
        preview_rank: ++previewRank,
      });
    }
  }
  svc.attachPhotos(points, photoRows.reverse());
  assert.equal(points[0].photos.length, 15);
  assert.deepEqual(
    points[0].photos.map((p) => p.id),
    Array.from({ length: 5 }, (_, i) => senders.map((sender) => `${sender}-${i + 1}`)).flat(),
  );
  assert.deepEqual(points[1].photos, []);
  assert.ok(points[0].photos.every((photo) => !Object.hasOwn(photo, 'user_id')));

  // §22.19 — a photo still blurring keeps its slot but carries no url
  const pending = [{ id: UUID_A, photos: [] }];
  svc.attachPhotos(pending, [
    { video_id: UUID_A, user_id: 'user-a', id: 'wait', photo_url: 'u-raw', blur_status: 'blurring', created_at: '2026-10-06T12:00:01.000Z' },
    { video_id: UUID_A, user_id: 'user-b', id: 'done', photo_url: 'u-done', blur_status: 'completed', created_at: '2026-10-06T12:00:00.000Z' },
  ]);
  assert.deepEqual(pending[0].photos.map((p) => [p.id, p.url, p.blurStatus]), [
    ['wait', '', 'blurring'],
    ['done', 'u-done', 'completed'],
  ]);
});

test('attachPhotos: over 15 senders gets one newest representative each', () => {
  const points = [{ id: UUID_A, photos: [] }];
  const base = Date.parse('2026-10-06T12:00:00Z');
  const photoRows = Array.from({ length: 20 }, (_, i) => ({
    video_id: UUID_A,
    user_id: `user-${i + 1}`,
    id: `photo-${i + 1}`,
    photo_url: `url-${i + 1}`,
    blur_status: 'completed',
    created_at: new Date(base - i * 1000).toISOString(),
    preview_rank: i + 1,
  }));

  svc.attachPhotos(points, photoRows);
  assert.deepEqual(
    points[0].photos.map((photo) => photo.id),
    Array.from({ length: 15 }, (_, i) => `photo-${i + 1}`),
  );
  assert.equal(new Set(points[0].photos.map((photo) => photo.id)).size, 15);
});

test('PHOTOS_SQL: fair sender rounds, cap 15, pending included, sender ids not returned', () => {
  assert.match(svc.PHOTOS_SQL, /PARTITION BY video_id, user_id/i);
  assert.match(svc.PHOTOS_SQL, /ORDER BY sender_rank, created_at DESC NULLS LAST, id DESC/i);
  assert.match(svc.PHOTOS_SQL, /preview_rank <= \$2/);
  assert.match(svc.PHOTOS_SQL, /blur_status IN \('completed', 'blurring'\)/);
  assert.doesNotMatch(svc.PHOTOS_SQL, /SELECT\s+user_id/i);
  assert.equal(svc.PHOTOS_PER_POINT, 15);
});

test('Supabase RPC migration uses the same fair 15-photo preview policy', () => {
  const migration = fs.readFileSync(
    path.join(__dirname, '../../supabase/migrations/20261019100000_incident_map_fair_photo_previews.sql'),
    'utf8',
  );
  const rollback = fs.readFileSync(
    path.join(__dirname, '../../supabase/rollbacks/20261019100000_incident_map_fair_photo_previews.sql'),
    'utf8',
  );
  assert.match(migration, /PARTITION BY user_id/i);
  assert.match(migration, /sender_rank <= 15/);
  assert.match(migration, /LIMIT 15/);
  assert.doesNotMatch(migration, /'user_id'\s*,/i);
  assert.match(rollback, /LIMIT 9/);
});

test('buildResponse: points page shape, nextCursor only when hasMore', () => {
  const now = Date.parse('2026-10-06T12:00:00Z');
  const rows = [
    { id: UUID_A, category_id: UUID_C, created_at: new Date(now - policy.HOUR_MS).toISOString(), latitude: 13.7, longitude: 100.5 },
  ];
  const points = svc.attachPhotos(svc.normalizeIncidentRows(rows, now), [
    { video_id: UUID_A, id: 'p1', photo_url: 'u1', created_at: new Date(now).toISOString() },
  ]);
  const agg = { red: 1, orange: 0, gold: 0, gray: 0, black: 0, invalidTime: 2, noUsableCoordinate: 1 };
  const res = svc.buildResponse({ mode: 'points', zoom: 14, points, agg, hasMore: true, lastRow: rows[0] });
  assert.equal(res.mode, 'points');
  assert.deepEqual(res.legend, { red: 1, orange: 0, gold: 0, gray: 0, black: 0, total: 1 });
  assert.deepEqual(res.excluded, { noUsableCoordinate: 1, invalidTime: 2 });
  assert.equal(res.items[0].kind, 'point');
  assert.equal(res.items[0].bucket, 'red');
  assert.equal(res.items[0].photos[0].url, 'u1');
  assert.ok(res.nextCursor);
  const noMore = svc.buildResponse({ mode: 'points', zoom: 14, points, agg, hasMore: false, lastRow: null });
  assert.equal(noMore.nextCursor, null);
});

// ──────────────────────────────────────────────────────────────
// 4. Route contract (fake pool + stubbed middleware)
// ──────────────────────────────────────────────────────────────

function incidentRow(id, createdAt, lat, lng) {
  return { id, category_id: UUID_C, created_at: createdAt, latitude: lat, longitude: lng };
}

function setupRouter({
  poolBehavior,
  supabaseRpc,
  photoUploadArrayFactory,
  faceBlurService,
} = {}) {
  const calls = { queries: [], cacheKeys: [], invalidatedPatterns: [], socketEvents: [] };

  const fakePool = {
    async query(text, params) {
      calls.queries.push({ text: String(text).slice(0, 40), params });
      if (typeof poolBehavior === 'function') return poolBehavior(text, params, calls);
      if (poolBehavior instanceof Error) throw poolBehavior;
      return { rows: [] };
    },
  };

  const supabase = {
    async rpc(name, args) {
      calls.rpc = { name, args };
      if (typeof supabaseRpc === 'function') return supabaseRpc(args, calls);
      return { data: null, error: { message: 'rpc unavailable' } };
    },
  };

  seedModuleCache(MIDDLEWARE_PATH, {
    strictRateLimiter: pass,
    rateLimiter: factory,
    idempotencyMiddleware: pass,
    duplicateCheckMiddleware: factory,
    cacheAside: async (key, fetcher) => {
      calls.cacheKeys.push(key);
      return fetcher();
    },
    invalidateCachePattern: async (pattern) => {
      calls.invalidatedPatterns.push(pattern);
      return 0;
    },
    TTL: { DEFAULT: 60, MAP: 120 },
    requireAuth: pass,
    uploadQuotaLimiter: pass,
    ipLimiter: pass,
  });
  seedModuleCache(VIDEO_SERVICE_PATH, { init: () => {} });
  seedModuleCache(
    SOCKET_SERVICE_PATH,
    new Proxy(
      {},
      {
        get: (_target, prop) =>
          (...args) => {
            calls.socketEvents.push({ name: String(prop), args });
          },
      },
    ),
  );
  seedModuleCache(FACE_BLUR_PATH, faceBlurService ?? {});
  seedModuleCache(THUMBNAIL_SERVICE_PATH, {
    generateThumbnail: async () => null,
    uploadThumbnailToBunny: async () => null,
  });
  seedModuleCache(THUMBNAIL_QUEUE_PATH, { addJob: async () => {} });
  seedModuleCache(WATERMARK_PATH, {});
  seedModuleCache(VIDEO_UPLOAD_PATH, {
    videoUpload: { single: factory, array: factory, fields: factory },
    photoUpload: {
      single: factory,
      array: photoUploadArrayFactory ?? factory,
      fields: factory,
    },
    photoUploadErrorHandler: pass,
    MAX_VIDEO_BYTES: 0,
    MAX_PHOTO_BYTES: 0,
  });
  // Re-seed the service module so the router picks up the stubbed middleware.
  delete require.cache[INCIDENT_MAP_PATH];
  require(INCIDENT_MAP_PATH);
  delete require.cache[ROUTE_PATH];

  const router = require(ROUTE_PATH)(fakePool, supabase);
  const app = express();
  app.use('/api/videos', router);

  return { app, calls };
}

test('route: Thai Mhung photo completion invalidates emergency map cache', async () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'incident-map-photos-'));
  const previousTempPath = process.env.TEMP_VIDEO_PATH;
  process.env.TEMP_VIDEO_PATH = tempDir;
  const sourcePath = path.join(tempDir, 'upload.bin');
  fs.writeFileSync(sourcePath, Buffer.from('photo'));

  const { app, calls } = setupRouter({
    poolBehavior: (text) => {
      if (text.includes('watermark_configs')) return { rows: [] };
      if (text.includes('INSERT INTO videos')) return { rows: [{ id: UUID_A }] };
      if (text.includes('INSERT INTO thai_mhung_photos')) {
        return { rows: [{ id: 'photo-1' }] };
      }
      return { rows: [] };
    },
    photoUploadArrayFactory: () => (req, res, next) => {
      req.userId = UUID_B;
      req.body = {
        isThaiMhung: 'true',
        incidentId: UUID_A,
        categoryId: UUID_C,
      };
      req.files = [{ path: sourcePath, filename: 'upload.bin', size: 5 }];
      next();
    },
    faceBlurService: {
      blurFacesInImage: async () => ({ success: true }),
    },
  });

  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    const response = await fetch(
      `http://127.0.0.1:${server.address().port}/api/videos/upload-photos`,
      { method: 'POST' },
    );
    assert.equal(response.status, 200);
    assert.equal((await response.json()).status, 'blurring');

    const deadline = Date.now() + 2000;
    while (
      (!calls.invalidatedPatterns.includes('video:emergency:map:*') ||
        !calls.socketEvents.some(
          (e) => e.name === 'broadcastIncidentMapPhotoReady',
        )) &&
      Date.now() < deadline
    ) {
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    assert.ok(calls.invalidatedPatterns.includes('video:emergency:map:*'));
    // §22.19 — the map does not join the video room, so blur completion must
    // also reach it through the global event.
    const mapReady = calls.socketEvents.find(
      (e) => e.name === 'broadcastIncidentMapPhotoReady',
    );
    assert.ok(mapReady, 'expected broadcastIncidentMapPhotoReady');
    assert.equal(mapReady.args[0], UUID_A);
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    });
    if (previousTempPath === undefined) {
      delete process.env.TEMP_VIDEO_PATH;
    } else {
      process.env.TEMP_VIDEO_PATH = previousTempPath;
    }
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('route: returns clusters from the local pool with legend and excluded counts', async () => {
  const now = Date.now();
  const { app } = setupRouter({
    poolBehavior: (text) => {
      if (text.includes('FILTER (WHERE fp.age')) {
        return { rows: [{ red: 1, orange: 0, gold: 0, gray: 0, black: 0, invalid_time: 0, no_usable_coordinate: 1 }] };
      }
      if (text.includes('CROSS JOIN LATERAL') && text.includes('LIMIT $6')) {
        return { rows: [incidentRow(UUID_A, new Date(now - policy.HOUR_MS).toISOString(), 13.7, 100.5)] };
      }
      return { rows: [] };
    },
  });

  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;
  const res = await fetch(`http://127.0.0.1:${port}/api/videos/emergency/map?category_id=${UUID_C}&bounds=5.5,97.5,20.5,105.5&zoom=5`);
  await server.close();

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.mode, 'clusters');
  assert.equal(body.legend.total, 1);
  assert.equal(body.excluded.noUsableCoordinate, 1);
  assert.equal(body.items.length, 1);
  assert.equal(body.items[0].kind, 'cluster');
});

test('route: points mode paginates with cursor and attaches photos', async () => {
  const now = Date.now();
  const photoId = 'photo-1';
  const { app, calls } = setupRouter({
    poolBehavior: (text, params) => {
      if (text.includes('FILTER (WHERE fp.age')) {
        return { rows: [{ red: 2, orange: 0, gold: 0, gray: 0, black: 0, invalid_time: 0, no_usable_coordinate: 0 }] };
      }
      if (text.includes('LIMIT $8')) {
        // limit+1 rows → hasMore true
        return {
          rows: [
            incidentRow(UUID_A, new Date(now - policy.HOUR_MS).toISOString(), 13.7, 100.5),
            incidentRow(UUID_B, new Date(now - 2 * policy.HOUR_MS).toISOString(), 13.8, 100.6),
          ],
        };
      }
      if (text.includes('thai_mhung_photos')) {
        return { rows: [{ video_id: UUID_A, id: photoId, photo_url: 'u1', blur_status: 'completed', created_at: new Date(now).toISOString() }] };
      }
      return { rows: [] };
    },
  });

  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;
  const res = await fetch(`http://127.0.0.1:${port}/api/videos/emergency/map?category_id=${UUID_C}&bounds=5.5,97.5,20.5,105.5&zoom=14&limit=1`);
  await server.close();

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.mode, 'points');
  assert.equal(body.items.length, 1);
  assert.equal(body.items[0].id, UUID_A);
  assert.deepEqual(body.items[0].photos.map((p) => p.id), [photoId]);
  assert.deepEqual(body.items[0].photos.map((p) => p.blurStatus), ['completed']);
  assert.match(calls.cacheKeys[0], /^video:emergency:map:v2:/);
  assert.ok(body.nextCursor);
  // cursor decodes to the last row of the page
  assert.deepEqual(svc.decodeCursor(body.nextCursor), {
    createdAt: new Date(now - policy.HOUR_MS).toISOString(),
    id: UUID_A,
  });
});

test('route: falls back to the Supabase RPC when the local pool fails', async () => {
  const { app, calls } = setupRouter({
    poolBehavior: new Error('connection refused'),
    supabaseRpc: () => ({
      data: {
        mode: 'points', zoom: 14, truncated: false,
        legend: { red: 1, orange: 0, gold: 0, gray: 0, black: 0, total: 1 },
        excluded: { noUsableCoordinate: 0, invalidTime: 0 },
        items: [{
          kind: 'point', id: UUID_A, categoryId: UUID_C, createdAt: '2026-10-06T11:00:00.000Z', bucket: 'red', lat: 13.7, lng: 100.5,
          // 10 rows from an older RPC body (no blurStatus) + one pending row
          photos: [
            ...Array.from({ length: 20 }, (_, i) => ({ id: `old-${i}`, url: `u${i}`, createdAt: '2026-10-06T11:00:00.000Z' })),
            { id: 'pending', url: 'raw-url', blurStatus: 'blurring', createdAt: '2026-10-06T11:00:01.000Z' },
          ],
        }],
        nextCursor: null,
      },
      error: null,
    }),
  });

  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;
  const res = await fetch(`http://127.0.0.1:${port}/api/videos/emergency/map?category_id=${UUID_C}&bounds=5.5,97.5,20.5,105.5&zoom=14`);
  await server.close();

  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.mode, 'points');
  assert.equal(body.items[0].id, UUID_A);
  assert.equal(calls.rpc.name, 'get_emergency_incident_map');
  // §22.19 — RPC fallback must expose the same capped/shape contract
  assert.equal(body.items[0].photos.length, 15);
  assert.deepEqual(
    body.items[0].photos.map((p) => p.blurStatus),
    Array.from({ length: 15 }, () => 'completed'),
  );
});

test('route: fail-closed 500 when both paths fail; 400 on bad params', async () => {
  const { app } = setupRouter({
    poolBehavior: new Error('connection refused'),
    supabaseRpc: () => ({ data: null, error: { message: 'rpc down' } }),
  });

  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;

  const res500 = await fetch(`http://127.0.0.1:${port}/api/videos/emergency/map?category_id=${UUID_C}&bounds=5.5,97.5,20.5,105.5&zoom=14`);
  assert.equal(res500.status, 500);

  const res400 = await fetch(`http://127.0.0.1:${port}/api/videos/emergency/map?category_id=nope&bounds=5.5,97.5,20.5,105.5&zoom=14`);
  assert.equal(res400.status, 400);

  await server.close();
});

test('gallery route: pagination sorts equal timestamps by photo id', async () => {
  let galleryQuery = '';
  const { app } = setupRouter({
    poolBehavior: (text) => {
      galleryQuery = String(text);
      return { rows: [] };
    },
  });

  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const port = server.address().port;
  const res = await fetch(
    `http://127.0.0.1:${port}/api/videos/${UUID_A}/gallery?page=1&limit=20`,
  );
  await server.close();

  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), []);
  assert.match(galleryQuery, /ORDER BY created_at DESC, id DESC/i);
});
