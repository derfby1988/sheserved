'use strict';

/**
 * Map Provider Config routes — Phase 1 (map_provider_rollout_plan.md §4.6, §5)
 *
 * Storage: local DB tables `map_provider_config` (single row, id=1) and
 * `map_provider_config_audit` (append-only).  Write path is ONLY
 * PUT /api/admin/map-config behind requireRole('admin') with optimistic
 * concurrency via `revision` (body `expectedRevision` or If-Match header).
 * Every successful save writes an audit row (actor, env, old/new, reason).
 *
 * Server-side validation mirrors §4.5 — the client is never trusted.
 * Tile-source readiness is canonical HERE (mirrored in
 * lib/features/admin/models/map_provider_config.dart): the client renders
 * labels/URLs, but this allowlist decides what may be saved.
 */

const express = require('express');
const {
  authRateLimiter,
  strictRateLimiter,
  requireRole,
  cacheAside,
  invalidateCache,
  TTL,
} = require('../middleware');

const CACHE_KEY = 'map-config:v1';

// Canonical tile-source registry — IDs must match the Dart registry.
// readiness: 'ready' | 'dev_only' (allowed in dev/staging only) | 'needs_key'
const TILE_SOURCES = Object.freeze({
  osm_standard: { readiness: 'dev_only', label: 'OSM Standard' },
  opentopo: { readiness: 'dev_only', label: 'OpenTopoMap' },
  carto_light: { readiness: 'needs_key', label: 'CARTO Light' },
  carto_voyager: { readiness: 'needs_key', label: 'CARTO Voyager' },
});

const PLATFORMS = ['web', 'ios', 'android'];
const FEATURES = ['home', 'rescue', 'emergency', 'group_create'];
const RENDERERS = ['google', 'osm'];
const ROUTING_PROVIDERS = ['google_directions', 'osrm', 'off'];
const SEARCH_PROVIDERS = ['nominatim', 'google_places'];
const TRAFFIC_PROVIDERS = ['google', 'none'];

function _isObj(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function _validateMapTarget(t, path, environment, errors, warnings) {
  if (!_isObj(t)) {
    errors.push(`${path}: must be an object`);
    return;
  }
  if (typeof t.enabled !== 'boolean') {
    errors.push(`${path}.enabled: must be boolean`);
  }
  if (t.renderer !== undefined && !RENDERERS.includes(t.renderer)) {
    errors.push(`${path}.renderer: must be one of ${RENDERERS.join('|')}`);
  }
  const renderer = t.renderer || 'google';
  if (renderer === 'osm') {
    if (typeof t.tileSourceId !== 'string' || t.tileSourceId.length === 0) {
      errors.push(`${path}.tileSourceId: required when renderer is osm`);
    } else {
      const src = TILE_SOURCES[t.tileSourceId];
      if (!src) {
        errors.push(`${path}.tileSourceId: unknown source '${t.tileSourceId}'`);
      } else if (src.readiness === 'needs_key') {
        errors.push(
          `${path}.tileSourceId: '${t.tileSourceId}' requires an API key that is not configured yet`,
        );
      } else if (src.readiness === 'dev_only' && environment === 'prod') {
        errors.push(
          `${path}.tileSourceId: '${t.tileSourceId}' is dev-only and cannot be used in prod`,
        );
      }
    }
  } else if (t.tileSourceId != null) {
    warnings.push(`${path}.tileSourceId: ignored while renderer is google`);
  }
}

/**
 * Validate the config document per rollout plan §4.5.
 * Returns { errors: string[], warnings: string[] } — errors block the save.
 */
function validateMapConfig(config, { environment, reason, confirmations } = {}) {
  const errors = [];
  const warnings = [];

  if (!_isObj(config)) {
    return { errors: ['config: must be an object'], warnings };
  }

  // platformDefaults — all three platforms required.
  const pd = config.platformDefaults;
  if (!_isObj(pd)) {
    errors.push('platformDefaults: required object');
  } else {
    for (const p of PLATFORMS) {
      if (!(p in pd)) {
        errors.push(`platformDefaults.${p}: missing`);
        continue;
      }
      _validateMapTarget(pd[p], `platformDefaults.${p}`, environment, errors, warnings);
    }
    for (const p of Object.keys(pd)) {
      if (!PLATFORMS.includes(p)) warnings.push(`platformDefaults.${p}: unknown platform ignored`);
    }
    // §4.5.3 — Google on web needs an explicit budget/key confirmation.
    if (pd.web && pd.web.enabled === true && (pd.web.renderer || 'google') === 'google') {
      if (!confirmations || confirmations.googleWebBudget !== true) {
        errors.push(
          'platformDefaults.web: enabling Google on web requires confirmations.googleWebBudget=true',
        );
      }
    }
  }

  // featureOverrides — known features only; yield_way is locked to inherit.
  const fo = config.featureOverrides;
  if (fo !== undefined && !_isObj(fo)) {
    errors.push('featureOverrides: must be an object');
  } else if (_isObj(fo)) {
    for (const [feature, o] of Object.entries(fo)) {
      if (feature === 'yield_way') {
        errors.push('featureOverrides.yield_way: locked — it always inherits emergency');
        continue;
      }
      if (!FEATURES.includes(feature)) {
        warnings.push(`featureOverrides.${feature}: unknown feature ignored`);
        continue;
      }
      if (!_isObj(o)) {
        errors.push(`featureOverrides.${feature}: must be an object`);
        continue;
      }
      if (!['inherit', 'override'].includes(o.mode)) {
        errors.push(`featureOverrides.${feature}.mode: must be inherit|override`);
        continue;
      }
      if (o.mode === 'override') {
        _validateMapTarget(
          { enabled: true, renderer: o.renderer, tileSourceId: o.tileSourceId },
          `featureOverrides.${feature}`,
          environment,
          errors,
          warnings,
        );
      }
    }
  }

  // services — routing/search/traffic are separate from the basemap (§7).
  const sv = config.services;
  if (_isObj(sv)) {
    if (_isObj(sv.routing)) {
      if (!ROUTING_PROVIDERS.includes(sv.routing.provider)) {
        errors.push(`services.routing.provider: must be one of ${ROUTING_PROVIDERS.join('|')}`);
      }
      if (sv.routing.enabled !== undefined && typeof sv.routing.enabled !== 'boolean') {
        errors.push('services.routing.enabled: must be boolean');
      }
    }
    if (_isObj(sv.search)) {
      if (!SEARCH_PROVIDERS.includes(sv.search.primary)) {
        errors.push(`services.search.primary: must be one of ${SEARCH_PROVIDERS.join('|')}`);
      }
    }
    if (_isObj(sv.traffic) && !TRAFFIC_PROVIDERS.includes(sv.traffic.provider)) {
      errors.push(`services.traffic.provider: must be one of ${TRAFFIC_PROVIDERS.join('|')}`);
    }
    // §4.5.4 — OSM anywhere while traffic stays google is allowed but must be
    // acknowledged so admins understand the traffic layer will be absent.
    const usesOsm =
      PLATFORMS.some((p) => pd && pd[p] && pd[p].renderer === 'osm') ||
      Object.values(fo || {}).some((o) => _isObj(o) && o.mode === 'override' && o.renderer === 'osm');
    if (usesOsm && sv.traffic && sv.traffic.provider === 'google') {
      if (!confirmations || confirmations.osmNoTraffic !== true) {
        errors.push(
          'services.traffic: selecting OSM requires confirmations.osmNoTraffic=true (no realtime traffic on OSM)',
        );
      }
    }
  }

  // fallback — must be an approved provider id, never silent.
  const fb = config.fallback;
  if (_isObj(fb) && fb.enabled === true) {
    if (!RENDERERS.includes(fb.providerId)) {
      errors.push(`fallback.providerId: must be one of ${RENDERERS.join('|')} when enabled`);
    }
  }

  // §4.5.6 — production saves need a reason.
  if (environment === 'prod' && (!reason || String(reason).trim().length === 0)) {
    errors.push('reason: required when saving to prod');
  }

  return { errors, warnings };
}

module.exports = (pool) => {
  const router = express.Router();

  async function _loadCurrent(client) {
    const r = await (client || pool).query(
      'SELECT id, revision, environment, config, reason, updated_by, updated_at FROM map_provider_config WHERE id = 1',
    );
    return r.rows[0] || null;
  }

  function _publicShape(row) {
    return {
      revision: row.revision,
      environment: row.environment,
      config: row.config,
      updatedAt: row.updated_at,
    };
  }

  /**
   * Save a new revision inside a transaction.
   * Returns { saved: row } or throws { status, body } for conflicts.
   */
  async function _saveRevision({ config, expectedRevision, reason, actor }) {
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const current = await _loadCurrent(client);
      if (!current) {
        throw { status: 500, body: { error: 'Map config row missing — run migration 04' } };
      }
      if (expectedRevision !== current.revision) {
        throw {
          status: 409,
          body: {
            error: 'Config was modified by someone else',
            currentRevision: current.revision,
          },
        };
      }
      const upd = await client.query(
        `UPDATE map_provider_config
           SET revision = revision + 1, config = $1, reason = $2, updated_by = $3, updated_at = NOW()
         WHERE id = 1 AND revision = $4
         RETURNING id, revision, environment, config, reason, updated_by, updated_at`,
        [config, reason || null, actor, expectedRevision],
      );
      if (upd.rows.length === 0) {
        // Lost the race between SELECT and UPDATE.
        throw { status: 409, body: { error: 'Config was modified by someone else' } };
      }
      await client.query(
        `INSERT INTO map_provider_config_audit (revision, environment, old_config, new_config, reason, actor)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          upd.rows[0].revision,
          upd.rows[0].environment,
          current.config,
          config,
          reason || null,
          actor,
        ],
      );
      await client.query('COMMIT');
      await invalidateCache(CACHE_KEY);
      return { saved: upd.rows[0] };
    } catch (err) {
      try {
        await client.query('ROLLBACK');
      } catch (_) {}
      if (err && err.status) throw err;
      throw err;
    } finally {
      client.release();
    }
  }

  // ── Public read (any client — config holds no secrets) ────────────────

  // GET /api/map-config — effective config + tile-source readiness registry.
  router.get('/map-config', authRateLimiter, async (req, res) => {
    try {
      const data = await cacheAside(
        CACHE_KEY,
        async () => {
          const row = await _loadCurrent();
          return row ? _publicShape(row) : null;
        },
        TTL.DEFAULT,
      );
      if (!data) {
        return res.status(404).json({ error: 'Map config not initialized' });
      }
      res.json({ ...data, tileSources: TILE_SOURCES });
    } catch (err) {
      console.error('Error fetching map config:', err);
      res.status(500).json({ error: 'Server error' });
    }
  });

  // ── Admin endpoints (mounted under /api/admin, after requireRole) ─────

  // GET /api/admin/map-config — config + write metadata.
  router.get('/admin/map-config', authRateLimiter, requireRole('admin'), async (req, res) => {
    try {
      const row = await _loadCurrent();
      if (!row) return res.status(404).json({ error: 'Map config not initialized' });
      res.json({
        ..._publicShape(row),
        updatedBy: row.updated_by,
        reason: row.reason,
        tileSources: TILE_SOURCES,
      });
    } catch (err) {
      console.error('Error fetching admin map config:', err);
      res.status(500).json({ error: 'Server error' });
    }
  });

  // PUT /api/admin/map-config — validated save with optimistic concurrency.
  // Body: { config, expectedRevision, reason?, confirmations? }
  // If-Match: <revision> is honored as an alternative to expectedRevision.
  router.put('/admin/map-config', authRateLimiter, requireRole('admin'), strictRateLimiter, async (req, res) => {
    try {
      const { config, expectedRevision, reason, confirmations } = req.body || {};
      if (!_isObj(config)) {
        return res.status(400).json({ error: 'config: required object' });
      }
      const ifMatch = req.headers['if-match'];
      const expected =
        ifMatch !== undefined ? parseInt(String(ifMatch).replace(/^"|"$/g, ''), 10) : expectedRevision;
      if (!Number.isInteger(expected)) {
        return res.status(400).json({ error: 'expectedRevision (or If-Match) is required' });
      }

      const current = await _loadCurrent();
      if (!current) return res.status(500).json({ error: 'Map config row missing — run migration 04' });

      const { errors, warnings } = validateMapConfig(config, {
        environment: current.environment,
        reason,
        confirmations,
      });
      if (errors.length > 0) {
        return res.status(422).json({ error: 'Validation failed', details: errors, warnings });
      }

      const { saved } = await _saveRevision({
        config,
        expectedRevision: expected,
        reason,
        actor: req.userId || req.user?.id || 'unknown',
      });

      res.json({ message: 'Map config saved', warnings, data: _publicShape(saved) });
    } catch (err) {
      if (err && err.status === 409) {
        return res.status(409).json(err.body);
      }
      console.error('Error saving map config:', err);
      res.status(500).json({ error: 'Server error' });
    }
  });

  // GET /api/admin/map-config/history?limit=20 — newest first.
  router.get('/admin/map-config/history', authRateLimiter, requireRole('admin'), async (req, res) => {
    try {
      const limit = Math.min(parseInt(req.query.limit, 10) || 20, 100);
      const r = await pool.query(
        `SELECT id, revision, environment, old_config, new_config, reason, actor, created_at
           FROM map_provider_config_audit ORDER BY id DESC LIMIT $1`,
        [limit],
      );
      res.json({ items: r.rows });
    } catch (err) {
      console.error('Error fetching map config history:', err);
      res.status(500).json({ error: 'Server error' });
    }
  });

  // POST /api/admin/map-config/rollback — restore config from an audit row.
  // Body: { auditId, expectedRevision, reason? }
  router.post('/admin/map-config/rollback', authRateLimiter, requireRole('admin'), strictRateLimiter, async (req, res) => {
    try {
      const { auditId, expectedRevision, reason } = req.body || {};
      if (!Number.isInteger(auditId)) {
        return res.status(400).json({ error: 'auditId: required integer' });
      }
      if (!Number.isInteger(expectedRevision)) {
        return res.status(400).json({ error: 'expectedRevision is required' });
      }
      const audit = await pool.query(
        'SELECT new_config, revision FROM map_provider_config_audit WHERE id = $1',
        [auditId],
      );
      if (audit.rows.length === 0) {
        return res.status(404).json({ error: 'Audit entry not found' });
      }
      const { saved } = await _saveRevision({
        config: audit.rows[0].new_config,
        expectedRevision,
        reason: reason || `Rollback to revision ${audit.rows[0].revision}`,
        actor: req.userId || req.user?.id || 'unknown',
      });
      res.json({ message: 'Map config rolled back', data: _publicShape(saved) });
    } catch (err) {
      if (err && err.status === 409) {
        return res.status(409).json(err.body);
      }
      console.error('Error rolling back map config:', err);
      res.status(500).json({ error: 'Server error' });
    }
  });

  return router;
};

// Exported for unit tests.
module.exports.validateMapConfig = validateMapConfig;
module.exports.TILE_SOURCES = TILE_SOURCES;
