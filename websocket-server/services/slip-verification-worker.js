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

/** Late-bound for tests: pass a fake supabase client / fetch. */
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

/** Egress/SSRF guard: provider endpoints must be https on a public host.
 * The admin registry is trusted input, but a hijacked/stale row must never
 * make the worker POST slip images to loopback/private/metadata targets.
 * Redirects are not followed implicitly — Node fetch defaults to 'follow',
 * so adapters keep redirect handling off and treat 3xx as unavailable. */
function _isAllowedEndpoint(endpointUrl) {
  try {
    const u = new URL(endpointUrl);
    if (u.protocol !== 'https:') return false;
    if (PRIVATE_HOST_RE.test(u.hostname)) return false;
    return true;
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
  if (!_isAllowedEndpoint(provider.endpointUrl)) {
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
  WORKER_ID,
};
