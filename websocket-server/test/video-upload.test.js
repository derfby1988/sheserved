'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const express = require('express');
const {
  videoUpload,
  photoUpload,
  photoUploadErrorHandler,
  MAX_VIDEO_BYTES,
  MAX_PHOTO_BYTES,
} = require('../utils/video-upload');

test('photo upload uses image validation and its own size limit', async (t) => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'sheserved-photo-upload-'));
  const previousTempPath = process.env.TEMP_VIDEO_PATH;
  process.env.TEMP_VIDEO_PATH = tempDir;

  const app = express();
  const respondWithFiles = async (req, res, next) => {
    const files = req.files ?? (req.file ? [req.file] : []);
    try {
      const result = files.map((file) => ({ filename: file.filename, size: file.size }));
      await Promise.all(files.map((file) => fs.unlink(file.path)));
      res.json(result);
    } catch (error) {
      next(error);
    }
  };

  app.post('/photos', photoUpload.array('photos', 5), photoUploadErrorHandler, respondWithFiles);
  app.post(
    '/videos',
    videoUpload.single('video'),
    respondWithFiles,
    (error, req, res, next) => {
      if (error.statusCode === 415) return res.status(415).json({ error: error.message });
      return next(error);
    },
  );

  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(async () => {
    await new Promise((resolve, reject) => {
      server.close((error) => error ? reject(error) : resolve());
    });
    if (previousTempPath === undefined) {
      delete process.env.TEMP_VIDEO_PATH;
    } else {
      process.env.TEMP_VIDEO_PATH = previousTempPath;
    }
    await fs.rm(tempDir, { recursive: true, force: true });
  });

  const address = server.address();
  const baseUrl = `http://127.0.0.1:${address.port}`;
  const upload = (url, field, filename, bytes) => {
    const form = new FormData();
    form.append(field, new Blob([bytes]), filename);
    return fetch(`${baseUrl}${url}`, { method: 'POST', body: form });
  };

  assert.equal(MAX_PHOTO_BYTES, 10 * 1024 * 1024);
  assert.equal(MAX_VIDEO_BYTES, 20 * 1024 * 1024);

  const photoResponse = await upload(
    '/photos',
    'photos',
    'capture.jpg',
    Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
  );
  assert.equal(photoResponse.status, 200);
  const [photo] = await photoResponse.json();
  assert.match(photo.filename, /\.jpg$/);
  assert.equal(photo.size, 4);

  const wrongKindResponse = await upload('/photos', 'photos', 'clip.mp4', Buffer.from('video'));
  assert.equal(wrongKindResponse.status, 415);
  assert.match((await wrongKindResponse.json()).error, /Unsupported image file extension/);

  const oversizedPhotoResponse = await upload(
    '/photos',
    'photos',
    'oversized.jpg',
    Buffer.alloc(MAX_PHOTO_BYTES + 1),
  );
  assert.equal(oversizedPhotoResponse.status, 413);

  const videoResponse = await upload('/videos', 'video', 'clip.mov', Buffer.from('video'));
  assert.equal(videoResponse.status, 200);
  assert.match((await videoResponse.json())[0].filename, /\.mov$/);
  assert.deepEqual(await fs.readdir(tempDir), []);
});
