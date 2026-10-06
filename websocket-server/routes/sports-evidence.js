'use strict';

/**
 * Route: GET /api/sports/evidence?token=<raw>
 *
 * Streams one private booking-evidence object. The read token is minted by
 * `mint_sports_venue_evidence_read_token` which only grants access to the
 * booker who owns the group or a manager of that venue — so this endpoint
 * needs no JWT; the token itself is the credential. Tokens are single-
 * purpose, md5-hashed at rest, and expire after 10 minutes.
 *
 * The bucket stays private: service-role downloads server-side and streams
 * the bytes — no signed/public URL is ever handed to the client.
 */

const express = require('express');
const crypto = require('crypto');
const multer = require('multer');
const sharp = require('sharp');

const BUCKET = 'booking-evidence';
const MAX_UPLOAD_BYTES = 10 * 1024 * 1024;
const MAX_DIMENSION = 2048;

const MIME_BY_EXT = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  pdf: 'application/pdf',
};

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_UPLOAD_BYTES, files: 1 },
});

/** Magic-byte sniff — the declared mimetype is never trusted. */
function sniffImageType(buf) {
  if (buf.length >= 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
    return 'jpeg';
  }
  if (
    buf.length >= 8 &&
    buf[0] === 0x89 && buf[1] === 0x50 && buf[2] === 0x4e && buf[3] === 0x47
  ) {
    return 'png';
  }
  if (
    buf.length >= 12 &&
    buf.subarray(0, 4).toString('ascii') === 'RIFF' &&
    buf.subarray(8, 12).toString('ascii') === 'WEBP'
  ) {
    return 'webp';
  }
  return null;
}

function sportsEvidenceRoutes({ supabaseForSync }) {
  const router = express.Router();

  /**
   * POST /api/sports/evidence/upload
   * multipart fields: token (one-time grant from
   * create_sports_venue_evidence_upload_grant) + file.
   *
   * The grant binds user/group/requirement/stage to a pre-assigned path;
   * the file is magic-byte checked, decoded and re-encoded through sharp
   * (which drops all EXIF/GPS metadata) before the service role writes it
   * to the private bucket. Client-side direct uploads are no longer
   * permitted — the bucket has no INSERT policy for anon/authenticated.
   */
  router.post('/evidence/upload', upload.single('file'), async (req, res) => {
    if (!supabaseForSync) {
      return res.status(503).json({ error: 'Store not available' });
    }
    const token = (req.body?.token || '').toString();
    if (!token || token.length > 128) {
      return res.status(400).json({ error: 'MISSING_TOKEN' });
    }
    const buf = req.file?.buffer;
    if (!buf || !buf.length) {
      return res.status(400).json({ error: 'MISSING_FILE' });
    }
    if (!sniffImageType(buf)) {
      return res.status(415).json({ error: 'UNSUPPORTED_FILE' });
    }
    try {
      // Consume first: the grant is single-use so a replayed token can
      // never write a second object.
      const { data: grant, error: grantError } = await supabaseForSync.rpc(
        'consume_sports_venue_evidence_upload_grant',
        { p_token_hash: crypto.createHash('md5').update(token).digest('hex') },
      );
      if (grantError) throw grantError;
      if (!grant?.path || !grant.path.startsWith('groups/')) {
        return res.status(403).json({ error: 'INVALID_GRANT' });
      }

      // Decode + auto-orient + bound dimensions + re-encode as JPEG.
      // sharp drops all metadata unless .withMetadata() is passed, so
      // EXIF/GPS can never survive this pipeline.
      const clean = await sharp(buf, { failOn: 'truncated' })
        .rotate()
        .resize({
          width: MAX_DIMENSION,
          height: MAX_DIMENSION,
          fit: 'inside',
          withoutEnlargement: true,
        })
        .jpeg({ quality: 85, mozjpeg: true })
        .toBuffer();

      const { error: upError } = await supabaseForSync.storage
        .from(BUCKET)
        .upload(grant.path, clean, {
          contentType: 'image/jpeg',
          upsert: false,
        });
      if (upError) {
        return res.status(409).json({ error: 'UPLOAD_FAILED' });
      }
      return res.json({
        path: grant.path,
        mime: 'image/jpeg',
        sizeBytes: clean.length,
      });
    } catch (err) {
      console.error('[SportsEvidence] upload failed:', err.message);
      return res.status(500).json({ error: 'UPLOAD_FAILED' });
    }
  });


  router.get('/evidence', async (req, res) => {
    if (!supabaseForSync) {
      return res.status(503).json({ error: 'Store not available' });
    }
    const token = (req.query.token || '').toString();
    if (!token || token.length > 128) {
      return res.status(400).json({ error: 'Missing token' });
    }
    try {
      const { data, error } = await supabaseForSync.rpc(
        'get_sports_venue_evidence_object_for_token',
        { p_token_hash: crypto.createHash('md5').update(token).digest('hex') },
      );
      if (error) throw error;
      const path = data?.path;
      if (!path || !path.startsWith('groups/')) {
        return res.status(404).json({ error: 'Not found' });
      }
      const { data: file, error: dlError } = await supabaseForSync.storage
        .from(BUCKET)
        .download(path);
      if (dlError || !file) {
        return res.status(404).json({ error: 'Not found' });
      }
      const ext = path.split('.').pop().toLowerCase();
      res.setHeader(
        'Content-Type',
        MIME_BY_EXT[ext] || 'application/octet-stream',
      );
      res.setHeader('Cache-Control', 'private, max-age=60');
      res.setHeader('X-Content-Type-Options', 'nosniff');
      const buffer = Buffer.from(await file.arrayBuffer());
      return res.send(buffer);
    } catch (err) {
      console.error('[SportsEvidence] read failed:', err.message);
      return res.status(500).json({ error: 'Failed to read evidence' });
    }
  });

  return router;
}

module.exports = { sportsEvidenceRoutes };
