'use strict';

/**
 * Minimum supported app version middleware (Phase 13.2 — force-update policy)
 * ─────────────────────────────────────────────────────────────
 * Reads the client version from the `x-app-version` header.  If the version
 * is below MIN_APP_VERSION (env), responds 426 Upgrade Required with:
 *   - JSON body: { error, minVersion, storeUrl? }
 *   - Header: x-min-app-version, x-force-update: true
 *
 * Missing header (unknown version) is treated as "below minimum" — fail
 * closed — once MIN_APP_VERSION is set and enforcement is enabled.
 *
 * Env:
 *   MIN_APP_VERSION (e.g. "1.0.0") — empty/absent disables enforcement
 *   MIN_APP_VERSION_ENFORCE (true|false, default: true when MIN_APP_VERSION set)
 *   APP_STORE_URL (optional, for the update prompt)
 */

function compareVersions(a, b) {
  const pa = String(a).split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b).split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < 3; i++) {
    const va = pa[i] || 0;
    const vb = pb[i] || 0;
    if (va < vb) return -1;
    if (va > vb) return 1;
  }
  return 0;
}

function minAppVersionMiddleware(req, res, next) {
  const minVersion = (process.env.MIN_APP_VERSION || '').trim();
  if (!minVersion) {
    // Enforcement not configured — pass through.
    return next();
  }

  const enforce = (process.env.MIN_APP_VERSION_ENFORCE || 'true') !== 'false';
  if (!enforce) {
    // Still advertise the minimum version in a header for clients to see.
    res.setHeader('x-min-app-version', minVersion);
    return next();
  }

  const clientVersion = (req.headers['x-app-version'] || '').trim();
  // Fail closed: unknown/absent version is treated as below minimum.
  const ok = clientVersion && compareVersions(clientVersion, minVersion) >= 0;

  res.setHeader('x-min-app-version', minVersion);

  if (!ok) {
    res.setHeader('x-force-update', 'true');
    return res.status(426).json({
      error: 'App version is no longer supported',
      minVersion,
      storeUrl: process.env.APP_STORE_URL || null,
    });
  }

  return next();
}

module.exports = { minAppVersionMiddleware, compareVersions };
