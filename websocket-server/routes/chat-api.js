'use strict';

/**
 * Routes: emergency chat history REST API
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 * Mounted at /api — paths carry the full prefix.
 *
 *   GET  /videos/:videoId/chat
 *   GET  /videos/:videoId/chat/archived
 *   POST /chat/archive/:videoId
 */

const express = require('express');
const { cacheAside, TTL, strictRateLimiter, duplicateCheckMiddleware } = require('../middleware');
const { archiveChatMessages } = require('../services/chat-archive-service');

/**
 * @param {{pool: object|null}} deps
 */
function chatApiRoutes({ pool }) {
  const router = express.Router();

  router.get('/videos/:videoId/chat', async (req, res) => {
    const { videoId } = req.params;
    const limit = parseInt(req.query.limit) || 50;

    try {
      if (!pool) return res.status(503).json({ error: 'Database not available' });

      const data = await cacheAside(`chat:active:${videoId}:${limit}`, async () => {
        const result = await pool.query(
          `SELECT
             m.id,
             m.room_id,
             r.video_id           AS "videoId",
             m.sender_id          AS "userId",
             m.content,
             m.created_at         AS "timestamp",
             m.metadata->>'role'         AS role,
             m.metadata->>'userName'     AS "userName",
             m.metadata->>'profileImageUrl' AS "profileImageUrl",
             m.metadata->>'professionName' AS "professionName",
             m.metadata->>'replyToId'    AS "replyToId",
             m.metadata->>'replyToContent' AS "replyToContent",
             m.metadata->>'replyToUserName' AS "replyToUserName"
           FROM chat_messages m
           JOIN chat_rooms r ON m.room_id = r.id
           WHERE r.video_id = $1
           ORDER BY m.created_at ASC
           LIMIT $2`,
          [videoId, limit]
        );
        return result.rows;
      }, TTL.SESSION);

      res.json(data);
    } catch (error) {
      console.error('[Chat History] Error:', error.message);
      res.status(500).json({ error: error.message });
    }
  });

  router.get('/videos/:videoId/chat/archived', async (req, res) => {
    const { videoId } = req.params;
    const limit = parseInt(req.query.limit) || 100;

    try {
      if (!pool) return res.status(503).json({ error: 'Database not available' });

      const data = await cacheAside(`chat:archived:${videoId}:${limit}`, async () => {
        const result = await pool.query(
          `SELECT
             a.id,
             a.video_id           AS "videoId",
             a.sender_id          AS "userId",
             a.content,
             a.created_at         AS "timestamp",
             a.metadata->>'role'         AS role,
             a.metadata->>'userName'     AS "userName",
             a.metadata->>'profileImageUrl' AS "profileImageUrl",
             a.metadata->>'professionName' AS "professionName",
             a.metadata->>'replyToId'    AS "replyToId",
             a.metadata->>'replyToContent' AS "replyToContent",
             a.metadata->>'replyToUserName' AS "replyToUserName"
           FROM chat_messages_archive a
           WHERE a.video_id = $1
           ORDER BY a.created_at ASC
           LIMIT $2`,
          [videoId, limit]
        );
        return result.rows;
      }, TTL.SESSION);

      res.json(data);
    } catch (error) {
      console.error('[Chat Archive History] Error:', error.message);
      res.status(500).json({ error: error.message });
    }
  });

  // POST /chat/archive/:videoId — Manual archive trigger via REST
  router.post('/chat/archive/:videoId', strictRateLimiter, duplicateCheckMiddleware('chat-archive', 10), async (req, res) => {
    const { videoId } = req.params;
    try {
      if (!pool) return res.status(503).json({ error: 'Database not available' });
      await archiveChatMessages(pool, videoId, 'manual-api');
      res.json({ success: true, message: `Chat archived for video ${videoId}` });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  return router;
}

module.exports = { chatApiRoutes };
