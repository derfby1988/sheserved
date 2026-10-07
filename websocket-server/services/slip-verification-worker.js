'use strict';

/**
 * SlipVerificationWorker (Sports Hub — Phase 21.7.21.6)
 * =====================================================
 * Drains the durable slip-verification outbox (`slip_verification_usage`
 * rows with result IS NULL) one attempt at a time:
 *
 *   1. worker_claim_sports_venue_slip_verification(attempt_id, worker_id)
 *      atomically leases the row — expired leases (>2 min) roll over to the
 *      next worker, so a crashed process never wedges an attempt.
 *   2. The claim response says 'verify' (call provider) or 'skip'
 *      (stale/scope-disabled/quota — already settled server-side).
 *   3. 'verify' downloads the slip from the private booking-evidence bucket
 *      with the service-role client, calls the configured provider adapter
 *      (SlipOK by default) and commits through
 *      worker_apply_sports_venue_slip_verification — never a direct table
 *      write.
 *
 * Provider API keys come from the server environment (secret-store ref in
 * the registry resolves to `SLIP_PROVIDER_KEY_<CODE>`), never from the DB.
 * Provider failures are applied as 'unavailable'/'timeout' so the slip
 * falls back to owner review instead of auto-confirming (no fail-open).
 *
 * Kill switch: SLIP_VERIFICATION_WORKER_ENABLED=false disables the loop;
 * disabling every provider in the registry makes claims return
 * {action:'skip', reason:'no_provider'} without calling this worker.
 */

const { createClient } = require('@supabase/supabase-js');
const crypto = require('crypto');
const dns = require('dns').promises;
const net = require('net');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY =
  process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

const WORKER_ID =
  process.env.SLIP_VERIFICATION_WORKER_ID ||
  `slip-worker-${process.pid}`;
const POLL_INTERVAL_MS = parseInt(
  process.env.SLIP_VERIFICATION_INTERVAL_MS || '15000',
  10,
);
const BATCH_SIZE = parseInt(
  process.env.SLIP_VERIFICATION_BATCH_SIZE || '5',
  10,
);
const PROVIDER_TIMEOUT_MS = parseInt(
  process.env.SLIP_VERIFICATION_PROVIDER_TIMEOUT_MS || '20000',
  10,
);
const BUCKET = 'booking-evidence';

let _client = null;
let _interval = null;
let _running = false;
let _fetchImpl = null;
let _storageDownload = null;
let _dnsLookup = null;
let _allowlistWarned = false;

/** Late-bound for tests: pass a fake supabase client / fetch / dns. */
function _init(overrides = {}) {
  _client =
    overrides.client ||
    (SUPABASE_URL && SUPABASE_SERVICE_KEY
      ? createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
      : null);
  _fetchImpl = overrides.fetchImpl || globalThis.fetch;
  _storageDownload =
    overrides.storageDownload ||
    ((path) =>
      _client.storage.from(BUCKET).download(path));
  _dnsLookup =
    overrides.dnsLookup ||
    ((hostname, options) => dns.lookup(hostname, options));
}

/** Parsed VERIFICATION_ALLOWED_HOSTS: null when unset (legacy mode),
 * otherwise the lowercase hostname allowlist. */
function _allowedHosts() {
  const raw = process.env.VERIFICATION_ALLOWED_HOSTS;
  if (raw == null) return null;
  const list = raw
    .split(',')
    .map((h) => h.trim().toLowerCase())
    .filter(Boolean);
  return list.length ? list : null;
}

function start(overrides = {}) {
  if (process.env.SLIP_VERIFICATION_WORKER_ENABLED === 'false') {
    console.log('[SlipVerificationWorker] Disabled via env — not started');
    return;
  }
  _init(overrides);
  if (!_client) {
    console.warn(
      '[SlipVerificationWorker] Supabase service client unavailable — not started',
    );
    return;
  }
  if (_interval) return;
  console.log(
    `[SlipVerificationWorker] Started id=${WORKER_ID} interval=${POLL_INTERVAL_MS}ms`,
  );
  _interval = setInterval(_tick, POLL_INTERVAL_MS);
  if (_interval.unref) _interval.unref();
}

function stop() {
  if (_interval) {
    clearInterval(_interval);
    _interval = null;
  }
}

/** Resolve the provider secret: registry stores a ref name; the value lives
 * in `SLIP_PROVIDER_KEY_<REF>` — the DB never holds raw keys. */
function _resolveApiKey(provider) {
  const ref = provider?.apiKeyRef;
  if (!ref) return null;
  return process.env[`SLIP_PROVIDER_KEY_${ref}`] || null;
}

const PRIVATE_HOST_RE =
  /^(localhost|127\.|0\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|::1|fc00:|fd00:|fe80:|\[)/i;

/** Synchronous URL-shape checks for the SSRF guard. With
 * VERIFICATION_ALLOWED_HOSTS set, the hostname must be on the allowlist;
 * without it we fall back to the pre-P0.3 hostname heuristics and warn
 * once, so existing deployments keep working until the env is set. */
function _isAllowedEndpoint(endpointUrl) {
  try {
    const u = new URL(endpointUrl);
    if (u.protocol !== 'https:') return false;
    if (u.username || u.password) return false;
    if (u.port && u.port !== '443') return false;
    const host = u.hostname.toLowerCase();
    const bare = host.replace(/^\[|\]$/g, '');
    if (net.isIP(bare)) return false;
    const allowed = _allowedHosts();
    if (allowed) return allowed.includes(host);
    if (!_allowlistWarned) {
      _allowlistWarned = true;
      console.warn(
        '[SlipVerificationWorker] VERIFICATION_ALLOWED_HOSTS is not set —' +
          ' provider endpoints are checked with hostname heuristics only;' +
          ' set an explicit allowlist (e.g. api.slipok.com)',
      );
    }
    if (PRIVATE_HOST_RE.test(host)) return false;
    return true;
  } catch {
    return false;
  }
}

/** Private/loopback/link-local/reserved IP check for resolved answers. */
function _isPrivateIp(address) {
  if (net.isIPv6(address)) {
    const a = address.toLowerCase();
    if (a === '::1' || a === '::') return true;
    if (a.startsWith('fe80:') || a.startsWith('fc') || a.startsWith('fd')) {
      return true;
    }
    const mapped = a.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
    if (mapped) return _isPrivateIp(mapped[1]);
    return false;
  }
  const parts = address.split('.').map((n) => parseInt(n, 10));
  if (
    parts.length !== 4 ||
    parts.some((n) => !Number.isInteger(n) || n < 0 || n > 255)
  ) {
    return true;
  }
  const [a, b] = parts;
  if (a === 0 || a === 10 || a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 100 && b >= 64 && b <= 127) return true;
  if (a >= 224) return true;
  return false;
}

/** Full egress check: URL shape, then — only when the allowlist is
 * configured — a best-effort DNS resolution check. Best-effort because the
 * answer can change between lookup and connect (TOCTOU); the hostname
 * allowlist remains the primary control, this complements it. Lookup
 * failures fail closed. */
async function _endpointAllowed(endpointUrl) {
  if (!_isAllowedEndpoint(endpointUrl)) return false;
  if (!_allowedHosts()) return true;
  try {
    const addrs = await _dnsLookup(new URL(endpointUrl).hostname, {
      all: true,
    });
    if (!addrs || addrs.length === 0) return false;
    return addrs.every((a) => !_isPrivateIp(a.address));
  } catch {
    return false;
  }
}

/** SlipOK adapter — POST the image as multipart `files`. */
async function _callSlipOk({ endpointUrl, apiKey, image, mime }) {
  const form = new FormData();
  form.append(
    'files',
    new Blob([image], { type: mime || 'image/jpeg' }),
    'slip.jpg',
  );
  const res = await _fetchImpl(endpointUrl, {
    method: 'POST',
    headers: { 'x-authorization': apiKey },
    body: form,
    redirect: 'error',
    signal: AbortSignal.timeout(PROVIDER_TIMEOUT_MS),
  });
  const body = await res.json().catch(() => ({}));
  // SlipOK success: {success:true, data:{amount, transRef/transTimestamp...}}
  const data = body?.data || body;
  const verified =
    body?.success === true && res.ok && data && data.amount != null;
  const amount =
    data?.amount != null ? parseFloat(data.amount) : null;
  const fingerprint =
    data?.transRef || data?.transactionId || data?.transTimestamp
      ? `${data.transRef || data.transactionId || ''}|${data.transTimestamp || ''}|${amount ?? ''}`
      : null;
  return {
    ok: verified,
    result: verified ? 'verified' : 'failed',
    amount: Number.isFinite(amount) ? amount : null,
    fingerprint,
    providerRef: data?.transRef || data?.transactionId || null,
    meta: { httpStatus: res.status },
  };
}

async function _callProvider(provider, image, mime) {
  const apiKey = _resolveApiKey(provider);
  if (!apiKey) {
    return { result: 'unavailable', meta: { reason: 'missing_api_key' } };
  }
  if (!(await _endpointAllowed(provider.endpointUrl))) {
    return { result: 'unavailable', meta: { reason: 'endpoint_blocked' } };
  }
  const code = (provider.code || '').toLowerCase();
  try {
    if (code === 'slipok') {
      return await _callSlipOk({
        endpointUrl: provider.endpointUrl,
        apiKey,
        image,
        mime,
      });
    }
    return { result: 'unavailable', meta: { reason: 'unknown_adapter' } };
  } catch (err) {
    const timeout =
      err?.name === 'TimeoutError' || err?.name === 'AbortError';
    return {
      result: timeout ? 'timeout' : 'unavailable',
      meta: { error: err.message },
    };
  }
}

async function _tick() {
  if (_running || !_client) return;
  _running = true;
  try {
    const { data: pending, error } = await _client
      .from('slip_verification_usage')
      .select('attempt_id')
      .is('result', null)
      .order('created_at', { ascending: true })
      .limit(BATCH_SIZE);
    if (error) {
      console.error(
        '[SlipVerificationWorker] poll failed:',
        error.message,
      );
      return;
    }
    for (const row of pending || []) {
      await _processAttempt(row.attempt_id);
    }
  } catch (err) {
    console.error('[SlipVerificationWorker] tick error:', err.message);
  } finally {
    _running = false;
  }
}

async function _processAttempt(attemptId) {
  try {
    const { data: claim, error } = await _client.rpc(
      'worker_claim_sports_venue_slip_verification',
      { p_attempt_id: attemptId, p_worker_id: WORKER_ID },
    );
    if (error) throw error;
    if (!claim || claim.action !== 'verify') return;

    const provider = claim.provider || {};
    let outcome;
    const { data: image, error: dlError } = await _storageDownload(
      claim.storagePath,
    );
    if (dlError || !image) {
      outcome = {
        result: 'unavailable',
        meta: { reason: 'storage_read_failed' },
      };
    } else {
      const bytes = Buffer.from(await image.arrayBuffer());
      outcome = await _callProvider(provider, bytes, claim.mime);
    }

    const { error: applyError } = await _client.rpc(
      'worker_apply_sports_venue_slip_verification',
      {
        p_attempt_id: attemptId,
        p_provider_code: provider.code || null,
        p_result: outcome.result,
        p_amount: outcome.amount ?? null,
        p_fingerprint:
          outcome.fingerprint ||
          crypto
            .createHash('sha256')
            .update(`${attemptId}:${claim.evidenceId}`)
            .digest('hex'),
        p_provider_ref: outcome.providerRef || null,
        p_meta: outcome.meta || {},
      },
    );
    if (applyError) {
      console.error(
        `[SlipVerificationWorker] apply failed attempt=${attemptId}:`,
        applyError.message,
      );
    }
  } catch (err) {
    console.error(
      `[SlipVerificationWorker] attempt=${attemptId} error:`,
      err.message,
    );
  }
}

module.exports = {
  start,
  stop,
  _init,
  _tick,
  _processAttempt,
  _resolveApiKey,
  _callSlipOk,
  _isAllowedEndpoint,
  _isPrivateIp,
  _endpointAllowed,
  WORKER_ID,
};
