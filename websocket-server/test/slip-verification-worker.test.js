'use strict';

/**
 * Unit tests for services/slip-verification-worker.js — the durable-outbox
 * drain loop behind auto_verify slips. All Supabase/provider calls are
 * stubbed: a fake client captures rpc/storage calls, and fetchImpl is a
 * controllable stub.
 */

const { test } = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');

const WORKER_PATH = path.join(
  __dirname,
  '../services/slip-verification-worker.js',
);

function loadWorker() {
  delete require.cache[WORKER_PATH];
  return require(WORKER_PATH);
}

function fakeClient({ pending = [], rpcHandler = () => ({ data: null }) }) {
  const calls = { rpc: [], download: [] };
  const client = {
    calls,
    from: () => ({
      select: () => ({
        is: () => ({
          order: () => ({
            limit: async () => ({ data: pending, error: null }),
          }),
        }),
      }),
    }),
    rpc: async (name, params) => {
      calls.rpc.push({ name, params });
      return rpcHandler(name, params);
    },
    storage: {
      from: () => ({
        download: async (p) => {
          calls.download.push(p);
          return {
            data: { arrayBuffer: async () => Buffer.from('img').buffer },
            error: null,
          };
        },
      }),
    },
  };
  return client;
}

const CLAIM_VERIFY = {
  action: 'verify',
  attemptId: 'att-1',
  evidenceId: 'ev-1',
  storagePath: 'groups/g1/slip.jpg',
  mime: 'image/jpeg',
  provider: {
    code: 'slipok',
    endpointUrl: 'https://api.slipok.com/api/branch/api/v1',
    apiKeyRef: 'SLIPOK',
  },
};

test('claims a pending attempt, downloads slip, applies verified result', async () => {
  const worker = loadWorker();
  process.env.SLIP_PROVIDER_KEY_SLIPOK = 'secret';
  const client = fakeClient({
    pending: [{ attempt_id: 'att-1' }],
    rpcHandler: (name) => {
      if (name === 'worker_claim_sports_venue_slip_verification') {
        return { data: CLAIM_VERIFY };
      }
      return { data: 'applied_confirmed' };
    },
  });
  worker._init({
    client,
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      json: async () => ({
        success: true,
        data: { amount: 200, transRef: 'TRX9' },
      }),
    }),
  });
  await worker._tick();
  const apply = client.calls.rpc.find((c) =>
    c.name.includes('apply'),
  );
  assert.equal(apply.params.p_result, 'verified');
  assert.equal(apply.params.p_amount, 200);
  assert.equal(apply.params.p_provider_code, 'slipok');
  assert.equal(client.calls.download[0], 'groups/g1/slip.jpg');
  delete process.env.SLIP_PROVIDER_KEY_SLIPOK;
});

test('skip verdict from claim leaves the attempt untouched', async () => {
  const worker = loadWorker();
  const client = fakeClient({
    pending: [{ attempt_id: 'att-2' }],
    rpcHandler: (name) => ({
      data: name.includes('claim')
        ? { action: 'skip', reason: 'stale' }
        : null,
    }),
  });
  worker._init({ client });
  await worker._tick();
  assert.equal(
    client.calls.rpc.filter((c) => c.name.includes('apply')).length,
    0,
  );
});

test('provider failure applies unavailable — no fail-open', async () => {
  const worker = loadWorker();
  process.env.SLIP_PROVIDER_KEY_SLIPOK = 'secret';
  const client = fakeClient({
    pending: [{ attempt_id: 'att-3' }],
    rpcHandler: (name) =>
      name.includes('claim') ? { data: CLAIM_VERIFY } : { data: 'applied' },
  });
  worker._init({
    client,
    fetchImpl: async () => {
      throw new Error('ECONNREFUSED');
    },
  });
  await worker._tick();
  const apply = client.calls.rpc.find((c) => c.name.includes('apply'));
  assert.equal(apply.params.p_result, 'unavailable');
  delete process.env.SLIP_PROVIDER_KEY_SLIPOK;
});

test('missing provider key applies unavailable without calling fetch', async () => {
  const worker = loadWorker();
  let fetched = false;
  const client = fakeClient({
    pending: [{ attempt_id: 'att-4' }],
    rpcHandler: (name) =>
      name.includes('claim') ? { data: CLAIM_VERIFY } : { data: 'applied' },
  });
  worker._init({
    client,
    fetchImpl: async () => {
      fetched = true;
      return {};
    },
  });
  await worker._tick();
  const apply = client.calls.rpc.find((c) => c.name.includes('apply'));
  assert.equal(apply.params.p_result, 'unavailable');
  assert.equal(fetched, false);
});

test('SSRF guard rejects private/plain-http endpoints before fetching', async () => {
  const worker = loadWorker();
  assert.equal(
    worker._isAllowedEndpoint('https://api.slipok.com/api/branch/api/v1'),
    true,
  );
  for (const bad of [
    'http://api.slipok.com/x',
    'https://localhost/x',
    'https://127.0.0.1/x',
    'https://192.168.1.5/x',
    'https://169.254.169.254/latest/meta-data',
    'not-a-url',
  ]) {
    assert.equal(worker._isAllowedEndpoint(bad), false, bad);
  }

  process.env.SLIP_PROVIDER_KEY_SLIPOK = 'secret';
  let fetched = false;
  const client = fakeClient({
    pending: [{ attempt_id: 'att-6' }],
    rpcHandler: (name) =>
      name.includes('claim')
        ? {
            data: {
              ...CLAIM_VERIFY,
              provider: {
                code: 'slipok',
                endpointUrl: 'https://169.254.169.254/steal',
                apiKeyRef: 'SLIPOK',
              },
            },
          }
        : { data: 'applied' },
  });
  worker._init({
    client,
    fetchImpl: async () => {
      fetched = true;
      return {};
    },
  });
  await worker._tick();
  const apply = client.calls.rpc.find((c) => c.name.includes('apply'));
  assert.equal(apply.params.p_result, 'unavailable');
  assert.equal(fetched, false);
  delete process.env.SLIP_PROVIDER_KEY_SLIPOK;
});

test('a null claim (fresh lease owned elsewhere) is a no-op', async () => {
  const worker = loadWorker();
  const client = fakeClient({
    pending: [{ attempt_id: 'att-5' }],
    rpcHandler: () => ({ data: null }),
  });
  worker._init({ client });
  await worker._tick();
  assert.equal(client.calls.download.length, 0);
  assert.equal(
    client.calls.rpc.filter((c) => c.name.includes('apply')).length,
    0,
  );
});
