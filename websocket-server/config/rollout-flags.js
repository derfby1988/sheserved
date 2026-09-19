'use strict';

/**
 * Phase 13.3 — Rollout Flags (rollback unit per wave)
 * ─────────────────────────────────────────────────────────────
 * Central parser for staged-rollout flags.  Every wave of Phase 13.3
 * must be reversible by unsetting one env var — no code rollback needed.
 *
 * Flags:
 *   STRICT_AUTH_ROUTES   Comma-separated list of route prefixes that require
 *                        a *verified JWT* identity (x-user-id and anonymous
 *                        are rejected with 401).  Empty/unset = compatibility
 *                        mode (legacy x-user-id still accepted where the old
 *                        code allowed it).
 *                        Example: "users,users-preferences,locations"
 *                        Prefixes match the path segment after /api/.
 *
 *   STRICT_SOCKET_AUTH   "true" = socket connections must authenticate with a
 *                        signed Backend access token.  Legacy auth.userId /
 *                        x-user-id handshakes are rejected (fail closed) and
 *                        events that require identity reject unverified sockets.
 *                        Default false during the compatibility window
 *                        (Phase 13.3 → 13.5 cutover).
 *
 *   STRICT_SOCKET_EVENTS Comma-separated list of event names that always
 *                        require a verified (jwt) socket identity even while
 *                        STRICT_SOCKET_AUTH=false.  Lets us tighten
 *                        high-risk events per-wave without breaking
 *                        anonymous public viewers.
 *
 * Never logs flag values beyond the parsed route/event names.
 */

function _csvSet(raw) {
  if (!raw || typeof raw !== 'string') return new Set();
  return new Set(
    raw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
  );
}

const STRICT_ROUTE_PREFIXES = _csvSet(process.env.STRICT_AUTH_ROUTES);
const STRICT_SOCKET_EVENTS = _csvSet(process.env.STRICT_SOCKET_EVENTS);
const STRICT_SOCKET_AUTH =
  String(process.env.STRICT_SOCKET_AUTH || '').toLowerCase() === 'true';

/**
 * Is the given Express request path inside a strict-enforcement prefix?
 * `req.path` here is relative to the mount point, so we also accept the
 * full /api/... form for inline routes.
 * @param {string} path e.g. "/users/abc/preferences" or "/api/users/abc"
 */
function isStrictRoute(path) {
  if (STRICT_ROUTE_PREFIXES.size === 0 || !path) return false;
  const clean = path.startsWith('/') ? path.slice(1) : path;
  const noApi = clean.startsWith('api/') ? clean.slice(4) : clean;
  const firstSegment = noApi.split('/')[0];
  return STRICT_ROUTE_PREFIXES.has(firstSegment);
}

/**
 * Does this socket event currently require a verified identity?
 * Under STRICT_SOCKET_AUTH every identity-bound event is strict;
 * otherwise only events named in STRICT_SOCKET_EVENTS are.
 * @param {string} eventName
 */
function isStrictSocketEvent(eventName) {
  return STRICT_SOCKET_AUTH || STRICT_SOCKET_EVENTS.has(eventName);
}

/**
 * Human-readable snapshot for startup logs (no secrets).
 */
function describe() {
  return {
    strictAuthRoutes: [...STRICT_ROUTE_PREFIXES],
    strictSocketAuth: STRICT_SOCKET_AUTH,
    strictSocketEvents: [...STRICT_SOCKET_EVENTS],
  };
}

module.exports = {
  isStrictRoute,
  isStrictSocketEvent,
  strictSocketAuthEnabled: () => STRICT_SOCKET_AUTH,
  describe,
};
