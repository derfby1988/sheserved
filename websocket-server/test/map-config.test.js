'use strict';

/**
 * Unit tests for routes/map-config.js (Phase 1 — map_provider_rollout_plan.md)
 *
 * Mounts the real router with an in-memory fake pool — no PostgreSQL/Redis.
 * The whole `../middleware` module is swapped in require.cache so limiters
 * and cacheAside are pass-through; requireRole is a faithful replica that
 * enforces the role injected by the test, and verifyToken is simulated by a
 * tiny middleware that sets req.userId/req.userRole per-request via headers.
 *
 * Run: node --test test/map-config.test.js   (or: npm test)
 */

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const express = require('express');

const ROUTE_PATH = require.resolve('../routes/map-config');
const MIDDLEWARE_PATH = require.resolve('../middleware/index.js');

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

function seedConfig(overrides = {}) {
  return {
    platformDefaults: {
      web: { enabled: false, renderer: 'google', tileSourceId: null },
      ios: { enabled: true, renderer: 'google', tileSourceId: null },
      android: { enabled: true, renderer: 'google', tileSourceId: null },
    },
    featureOverrides: {},
    services: {
      routing: { provider: 'google_directions', enabled: true },
      search: { primary: 'nominatim', fallbackEnabled: true },
      traffic: { provider: 'google' },
    },
    fallback: { enabled: false, providerId: null },
    rateConfig: {
      googleWebMapPerThousand: 7,
      googleDirectionsPerThousand: 5,
      googlePlacesPerThousand: 17,
    },
    ...overrides,
  };
}

/**
 * In-memory emulation of map_provider_config (+audit) — pattern-matches the
 * SQL issued by the route so transaction semantics (conflict → 0 rows) hold.
 */
function makeFakePool({ environment = 'dev', revision = 3 } = {}) {
  const state = {
    row: {
      id: 1,
      revision,
      environment,
      config: seedConfig(),
      reason: 'seed',
      updated_by: 'seed',
      updated_at: new Date().toISOString(),
    },
    audit: [],
    auditSeq: 0,
  };
  const queries = [];

  async function query(sql, params = []) {
    queries.push(sql);
    if (/FROM map_provider_config WHERE id = 1/.test(sql)) {
      return { rows: [{ ...state.row }] };
    }
    if (/UPDATE map_provider_config/.test(sql)) {
      const [config, reason, actor, expectedRev] = params;
      if (state.row.revision !== expectedRev) return { rows: [] };
      state.row = {
        ...state.row,
        revision: state.row.revision + 1,
        config,
        reason,
        updated_by: actor,
        updated_at: new Date().toISOString(),
      };
      return { rows: [{ ...state.row }] };
    }
    if (/INSERT INTO map_provider_config_audit/.test(sql)) {
      const [rev, env, oldConfig, newConfig, reason, actor] = params;
      const entry = {
        id: ++state.auditSeq,
        revision: rev,
        environment: env,
        old_config: oldConfig,
        new_config: newConfig,
        reason,
        actor,
        created_at: new Date().toISOString(),
      };
      state.audit.push(entry);
      return { rows: [entry] };
    }
    if (/FROM map_provider_config_audit WHERE id = \$1/.test(sql)) {
      return { rows: state.audit.filter((a) => a.id === params[0]) };
    }
    if (/FROM map_provider_config_audit ORDER BY/.test(sql)) {
      return { rows: [...state.audit].reverse().slice(0, params[0]) };
    }
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql.trim())) {
      return { rows: [] };
    }
    throw new Error(`unmatched SQL: ${sql}`);
  }

  return {
    query,
    connect: async () => ({ query, release: () => {} }),
    _state: state,
    _queries: queries,
  };
}

function setup(poolOpts = {}) {
  const cacheStore = new Map();
  seedModuleCache(MIDDLEWARE_PATH, {
    strictRateLimiter: pass,
    authRateLimiter: pass,
    rateLimiter: factory,
    requireAuth: pass,
    // Faithful replica of the real requireRole — the test injects
    // req.userId/req.userRole before routes via a tiny middleware below.
    requireRole: (required) => (req, res, next) => {
      if (!req.userId) {
        return res.status(401).json({ error: 'Unauthorized: Login required' });
      }
      if (req.userRole !== required) {
        return res.status(403).json({ error: `Forbidden: Requires '${required}' role` });
      }
      next();
    },
    cacheAside: async (key, fetcher) => {
      if (cacheStore.has(key)) return cacheStore.get(key);
      const v = await fetcher();
      cacheStore.set(key, v);
      return v;
    },
    invalidateCache: async (key) => cacheStore.delete(key),
    invalidateCachePattern: async () => 0,
    TTL: { DEFAULT: 60 },
  });

  const pool = makeFakePool(poolOpts);
  delete require.cache[ROUTE_PATH];
  const routerFactory = require('../routes/map-config');
  const app = express();
  app.use(express.json());
  // Simulates verifyToken: x-test-user / x-test-role headers become identity.
  app.use((req, res, next) => {
    req.userId = req.headers['x-test-user'] || null;
    req.userRole = req.headers['x-test-role'] || null;
    req.user = req.userId ? { id: req.userId, role: req.userRole } : null;
    next();
  });
  app.use('/api', routerFactory(pool));
  return { app, pool, cacheStore };
}

async function withServer(ctx, run) {
  const server = ctx.app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  try {
    const { port } = server.address();
    await run(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve, reject) =>
      server.close((e) => (e ? reject(e) : resolve())),
    );
  }
}

const ADMIN = { 'x-test-user': 'u-admin', 'x-test-role': 'admin' };

// ── Public read ───────────────────────────────────────────────────────

test('GET /api/map-config returns config + tile source registry without auth', async () => {
  const ctx = setup();
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/map-config`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.revision, 3);
    assert.equal(body.environment, 'dev');
    assert.equal(body.config.platformDefaults.ios.renderer, 'google');
    assert.equal(body.tileSources.osm_standard.readiness, 'dev_only');
    // No write metadata leaks through the public shape.
    assert.equal(body.updatedBy, undefined);
  });
});

// ── Authorization ─────────────────────────────────────────────────────

test('PUT rejects anonymous with 401 and non-admin with 403', async () => {
  const ctx = setup();
  await withServer(ctx, async (base) => {
    const anon = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ config: seedConfig(), expectedRevision: 3 }),
    });
    assert.equal(anon.status, 401);

    const user = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'x-test-user': 'u1',
        'x-test-role': 'consumer',
      },
      body: JSON.stringify({ config: seedConfig(), expectedRevision: 3 }),
    });
    assert.equal(user.status, 403);
    // Nothing written.
    assert.equal(ctx.pool._state.audit.length, 0);
  });
});

// ── Optimistic concurrency ────────────────────────────────────────────

test('PUT with stale revision returns 409 and does not write', async () => {
  const ctx = setup();
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({ config: seedConfig(), expectedRevision: 1 }),
    });
    assert.equal(res.status, 409);
    const body = await res.json();
    assert.equal(body.currentRevision, 3);
    assert.equal(ctx.pool._state.row.revision, 3);
    assert.equal(ctx.pool._state.audit.length, 0);
  });
});

test('PUT with matching revision bumps revision and writes audit', async () => {
  const ctx = setup();
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({
        config: seedConfig(),
        expectedRevision: 3,
        reason: 'test save',
      }),
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.data.revision, 4);
    assert.equal(ctx.pool._state.row.revision, 4);
    assert.equal(ctx.pool._state.audit.length, 1);
    assert.equal(ctx.pool._state.audit[0].revision, 4);
    assert.equal(ctx.pool._state.audit[0].actor, 'u-admin');
    assert.equal(ctx.pool._state.audit[0].reason, 'test save');
    // Audit captured the pre-save config snapshot.
    assert.equal(
      ctx.pool._state.audit[0].old_config.platformDefaults.web.enabled,
      false,
    );
  });
});

test('If-Match header works as alternative to expectedRevision', async () => {
  const ctx = setup();
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'If-Match': '3', ...ADMIN },
      body: JSON.stringify({ config: seedConfig() }),
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.data.revision, 4);
  });
});

// ── Validation (§4.5) ─────────────────────────────────────────────────

test('osm renderer without tileSourceId is rejected', async () => {
  const ctx = setup();
  const bad = seedConfig();
  bad.platformDefaults.ios = { enabled: true, renderer: 'osm', tileSourceId: null };
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({ config: bad, expectedRevision: 3 }),
    });
    assert.equal(res.status, 422);
    const body = await res.json();
    assert.match(body.details.join(' '), /tileSourceId/);
  });
});

test('needs_key tile source (carto_light) is rejected until key configured', async () => {
  const ctx = setup();
  const bad = seedConfig();
  bad.platformDefaults.ios = {
    enabled: true,
    renderer: 'osm',
    tileSourceId: 'carto_light',
  };
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({
        config: bad,
        expectedRevision: 3,
        confirmations: { osmNoTraffic: true },
      }),
    });
    assert.equal(res.status, 422);
    const body = await res.json();
    assert.match(body.details.join(' '), /API key/);
  });
});

test('yield_way override is rejected (locked inherit to emergency)', async () => {
  const ctx = setup();
  const bad = seedConfig();
  bad.featureOverrides = { yield_way: { mode: 'override', renderer: 'osm', tileSourceId: 'osm_standard' } };
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({ config: bad, expectedRevision: 3 }),
    });
    assert.equal(res.status, 422);
    assert.match((await res.json()).details.join(' '), /yield_way/);
  });
});

test('Google on web requires googleWebBudget confirmation', async () => {
  const ctx = setup();
  const cfg = seedConfig();
  cfg.platformDefaults.web = { enabled: true, renderer: 'google', tileSourceId: null };
  await withServer(ctx, async (base) => {
    const noConfirm = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({ config: cfg, expectedRevision: 3 }),
    });
    assert.equal(noConfirm.status, 422);

    const confirmed = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({
        config: cfg,
        expectedRevision: 3,
        confirmations: { googleWebBudget: true },
      }),
    });
    assert.equal(confirmed.status, 200);
  });
});

test('OSM anywhere requires osmNoTraffic acknowledgement', async () => {
  const ctx = setup();
  const cfg = seedConfig();
  cfg.platformDefaults.ios = { enabled: true, renderer: 'osm', tileSourceId: 'osm_standard' };
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({ config: cfg, expectedRevision: 3 }),
    });
    assert.equal(res.status, 422);
    assert.match((await res.json()).details.join(' '), /osmNoTraffic/);
  });
});

test('dev_only tile source blocked in prod', async () => {
  const ctx = setup({ environment: 'prod' });
  const cfg = seedConfig();
  cfg.platformDefaults.ios = { enabled: true, renderer: 'osm', tileSourceId: 'osm_standard' };
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({
        config: cfg,
        expectedRevision: 3,
        reason: 'prod save',
        confirmations: { osmNoTraffic: true },
      }),
    });
    assert.equal(res.status, 422);
    assert.match((await res.json()).details.join(' '), /dev-only/);
  });
});

test('prod save without reason is rejected', async () => {
  const ctx = setup({ environment: 'prod' });
  await withServer(ctx, async (base) => {
    const res = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({ config: seedConfig(), expectedRevision: 3 }),
    });
    assert.equal(res.status, 422);
    assert.match((await res.json()).details.join(' '), /reason/);
  });
});

// ── History + rollback ────────────────────────────────────────────────

test('history returns newest first; rollback restores config as new revision', async () => {
  const ctx = setup();
  await withServer(ctx, async (base) => {
    // Save a change: ios → osm.
    const cfg = seedConfig();
    cfg.platformDefaults.ios = { enabled: true, renderer: 'osm', tileSourceId: 'osm_standard' };
    const save = await fetch(`${base}/api/admin/map-config`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({
        config: cfg,
        expectedRevision: 3,
        reason: 'try osm on ios',
        confirmations: { osmNoTraffic: true },
      }),
    });
    assert.equal(save.status, 200);

    const hist = await fetch(`${base}/api/admin/map-config/history`, {
      headers: ADMIN,
    });
    assert.equal(hist.status, 200);
    const items = (await hist.json()).items;
    assert.equal(items.length, 1);
    assert.equal(items[0].revision, 4);
    assert.equal(items[0].actor, 'u-admin');

    // Roll back to the audit entry (which stores the osm config as new_config —
    // to restore the PRE-osm state we roll back to... the audit's new_config
    // IS the saved config. Rolling back entry restores that doc; here we
    // verify the mechanism returns a new revision with that doc).
    const rb = await fetch(`${base}/api/admin/map-config/rollback`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...ADMIN },
      body: JSON.stringify({ auditId: items[0].id, expectedRevision: 4 }),
    });
    assert.equal(rb.status, 200);
    const rbBody = await rb.json();
    assert.equal(rbBody.data.revision, 5);
    assert.equal(
      rbBody.data.config.platformDefaults.ios.renderer,
      'osm',
    );
    assert.equal(ctx.pool._state.audit.length, 2);
  });
});

// ── Direct validation unit checks ─────────────────────────────────────

test('validateMapConfig: google-only config passes with no errors', () => {
  const { validateMapConfig } = require('../routes/map-config');
  const { errors } = validateMapConfig(seedConfig(), { environment: 'dev' });
  assert.deepEqual(errors, []);
});

test('validateMapConfig: unknown feature warns instead of failing', () => {
  const { validateMapConfig } = require('../routes/map-config');
  const cfg = seedConfig();
  cfg.featureOverrides = { future_feature: { mode: 'inherit' } };
  const { errors, warnings } = validateMapConfig(cfg, { environment: 'dev' });
  assert.deepEqual(errors, []);
  assert.match(warnings.join(' '), /future_feature/);
});
