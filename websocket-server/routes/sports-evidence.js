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

const BUCKET = 'booking-evidence';

const MIME_BY_EXT = {
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  pdf: 'application/pdf',
};

function sportsEvidenceRoutes({ supabaseForSync }) {
  const router = express.Router();

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
