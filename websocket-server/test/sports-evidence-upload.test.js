'use strict';

/**
 * Unit tests for POST /api/sports/evidence/upload — the grant-gated,
 * sanitizing upload endpoint. The Supabase client is a stub that captures
 * rpc/storage calls; real sharp runs so the EXIF strip is exercised for
 * real.
 */

const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('crypto');
const express = require('express');
const sharp = require('sharp');

const { sportsEvidenceRoutes } = require('../routes/sports-evidence');

function fakeClient({ grant, uploadError } = {}) {
  const calls = { rpc: [], uploads: [] };
  return {
    calls,
    rpc: async (name, params) => {
      calls.rpc.push({ name, params });
      return { data: grant === undefined ? null : grant, error: null };
    },
    storage: {
      from: (bucket) => ({
        upload: async (path, buf, opts) => {
          calls.uploads.push({ bucket, path, buf, opts });
          return { data: {}, error: uploadError || null };
        },
      }),
    },
  };
}

async function serve(client) {
  const app = express();
  app.use('/api/sports', sportsEvidenceRoutes({ supabaseForSync: client }));
  const server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  return {
    server,
    url: `http://127.0.0.1:${server.address().port}/api/sports/evidence/upload`,
  };
}

async function jpegWithExif() {
  return sharp({
    create: { width: 8, height: 8, channels: 3, background: '#ffffff' },
  })
    .jpeg()
    .withMetadata({ exif: { IFD0: { Copyright: 'secret' } } })
    .toBuffer();
}

function postUpload(url, { token, buf } = {}) {
  const form = new FormData();
  if (token !== undefined) form.append('token', token);
  if (buf) {
    form.append('file', new Blob([buf], { type: 'image/jpeg' }), 'e.jpg');
  }
  return fetch(url, { method: 'POST', body: form });
}

test('valid jpeg redeems the grant once and stores sanitized bytes', async () => {
  const token = 'tok-abc';
  const grant = {
    path: 'groups/g1/payment/u1.jpg',
    groupId: 'g1',
    userId: 'u1',
    purpose: 'evidence',
    requirementKey: 'payment',
  };
  const client = fakeClient({ grant });
  const { server, url } = await serve(client);
  try {
    const res = await postUpload(url, { token, buf: await jpegWithExif() });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.path, grant.path);
    assert.equal(body.mime, 'image/jpeg');

    // Token is hashed before hitting the DB — the raw value never leaves.
    assert.equal(client.calls.rpc.length, 1);
    assert.equal(
      client.calls.rpc[0].params.p_token_hash,
      crypto.createHash('md5').update(token).digest('hex'),
    );

    // The stored object is the re-encoded JPEG with no EXIF/GPS left.
    assert.equal(client.calls.uploads.length, 1);
    const up = client.calls.uploads[0];
    assert.equal(up.path, grant.path);
    assert.equal(up.opts.upsert, false);
    const meta = await sharp(up.buf).metadata();
    assert.equal(meta.exif, undefined);
    assert.equal(meta.format, 'jpeg');
  } finally {
    server.close();
  }
});

test('an invalid/expired grant is rejected before any write', async () => {
  const client = fakeClient({ grant: null });
  const { server, url } = await serve(client);
  try {
    const res = await postUpload(url, {
      token: 'bad-token',
      buf: await jpegWithExif(),
    });
    assert.equal(res.status, 403);
    assert.equal(client.calls.uploads.length, 0);
  } finally {
    server.close();
  }
});

test('non-image bytes are rejected without consuming the grant', async () => {
  const client = fakeClient({ grant: { path: 'groups/g/x.jpg' } });
  const { server, url } = await serve(client);
  try {
    const res = await postUpload(url, {
      token: 'tok',
      buf: Buffer.from('MZ this is not an image'),
    });
    assert.equal(res.status, 415);
    assert.equal(client.calls.rpc.length, 0);
    assert.equal(client.calls.uploads.length, 0);
  } finally {
    server.close();
  }
});

test('missing token or file is a 400', async () => {
  const client = fakeClient({});
  const { server, url } = await serve(client);
  try {
    let res = await postUpload(url, { buf: await jpegWithExif() });
    assert.equal(res.status, 400);
    res = await postUpload(url, { token: 'tok' });
    assert.equal(res.status, 400);
  } finally {
    server.close();
  }
});
