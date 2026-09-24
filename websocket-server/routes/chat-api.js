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
const { requireVerifiedIdentity } = require('../middleware/auth');

/**
 * @param {{pool: object|null, supabaseForSync: object|null, verifyTokenMw: Function}} deps
 */
function chatApiRoutes({ pool, supabaseForSync, verifyTokenMw }) {
  const router = express.Router();
  const closedEndedAuth = verifyTokenMw
    ? [verifyTokenMw, requireVerifiedIdentity()]
    : [(req, res) => res.status(503).json({ code: 'FAILED' })];
  const isUuid = (value) =>
    typeof value === 'string' &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
  const statusForCode = (code) => ({
    OK: 200,
    ALREADY_ANSWERED: 200,
    INVALID_CONFIG: 400,
    INVALID_CONTENT: 400,
    INVALID_INDEX: 400,
    UNAUTHORIZED: 401,
    FORBIDDEN: 403,
    NOT_FOUND: 404,
  })[code] || 502;
  const sendRpcResult = (res, result) => {
    if (!result || typeof result !== 'object' || Array.isArray(result)) {
      return res.status(502).json({ code: 'FAILED' });
    }
    return res.status(statusForCode(result.code)).json(result);
  };
  const attachMessage = async (result, messageId) => {
    if (
      !result ||
      typeof result !== 'object' ||
      !messageId ||
      !['OK', 'ALREADY_ANSWERED'].includes(result.code)
    ) {
      return result;
    }
    try {
      const { data, error } = await supabaseForSync
        .from('chat_messages')
        .select('*')
        .eq('id', messageId)
        .maybeSingle();
      if (!error && data) return { ...result, message: data };
    } catch (error) {
      console.error('[Closed-ended API] Message refresh failed:', error.message);
    }
    return result;
  };

  router.post('/chat/closed-ended/send', ...closedEndedAuth, async (req, res) => {
    if (!supabaseForSync) return res.status(503).json({ code: 'FAILED' });
    if (!isUuid(req.userId)) return res.status(401).json({ code: 'UNAUTHORIZED' });

    const { roomId, content, config, bodyPart } = req.body || {};
    if (
      typeof roomId !== 'string' ||
      roomId.trim().length === 0 ||
      typeof content !== 'string' ||
      content.trim().length === 0
    ) {
      return sendRpcResult(res, { code: 'INVALID_CONTENT' });
    }
    if (!config || typeof config !== 'object' || Array.isArray(config)) {
      return sendRpcResult(res, { code: 'INVALID_CONFIG' });
    }
    if (bodyPart != null && typeof bodyPart !== 'string') {
      return sendRpcResult(res, { code: 'INVALID_CONTENT' });
    }

    try {
      const { data, error } = await supabaseForSync.rpc(
        'send_closed_ended_question_backend',
        {
          p_room_id: roomId,
          p_content: content,
          p_config: config,
          p_body_part: bodyPart ?? null,
          p_caller_id: req.userId,
        },
      );
      if (error) {
        console.error('[Closed-ended API] Send RPC failed:', error.message);
        return res.status(502).json({ code: 'FAILED' });
      }
      const result = await attachMessage(data, data?.message_id?.toString());
      return sendRpcResult(res, result);
    } catch (error) {
      console.error('[Closed-ended API] Send RPC failed:', error.message);
      return res.status(502).json({ code: 'FAILED' });
    }
  });

  router.post(
    '/chat/closed-ended/:questionMessageId/reading',
    ...closedEndedAuth,
    async (req, res) => {
      if (!supabaseForSync) return res.status(503).json({ code: 'FAILED' });
      if (!isUuid(req.userId)) {
        return res.status(401).json({ code: 'UNAUTHORIZED' });
      }
      const { questionMessageId } = req.params;
      if (!isUuid(questionMessageId)) {
        return sendRpcResult(res, { code: 'NOT_FOUND' });
      }

      try {
        const { data, error } = await supabaseForSync.rpc(
          'mark_closed_ended_question_reading_backend',
          {
            p_question_message_id: questionMessageId,
            p_caller_id: req.userId,
          },
        );
        if (error) {
          console.error('[Closed-ended API] Reading RPC failed:', error.message);
          return res.status(502).json({ code: 'FAILED' });
        }
        return sendRpcResult(res, await attachMessage(data, questionMessageId));
      } catch (error) {
        console.error('[Closed-ended API] Reading RPC failed:', error.message);
        return res.status(502).json({ code: 'FAILED' });
      }
    },
  );

  router.post(
    '/chat/closed-ended/:questionMessageId/answer',
    ...closedEndedAuth,
    async (req, res) => {
      if (!supabaseForSync) return res.status(503).json({ code: 'FAILED' });
      if (!isUuid(req.userId)) {
        return res.status(401).json({ code: 'UNAUTHORIZED' });
      }
      const { questionMessageId } = req.params;
      const { selectedIndex } = req.body || {};
      if (!isUuid(questionMessageId)) {
        return sendRpcResult(res, { code: 'NOT_FOUND' });
      }
      if (!Number.isInteger(selectedIndex)) {
        return sendRpcResult(res, { code: 'INVALID_INDEX' });
      }

      try {
        const { data, error } = await supabaseForSync.rpc(
          'answer_closed_ended_question_backend',
          {
            p_question_message_id: questionMessageId,
            p_selected_index: selectedIndex,
            p_caller_id: req.userId,
          },
        );
        if (error) {
          console.error('[Closed-ended API] Answer RPC failed:', error.message);
          return res.status(502).json({ code: 'FAILED' });
        }
        return sendRpcResult(res, await attachMessage(data, questionMessageId));
      } catch (error) {
        console.error('[Closed-ended API] Answer RPC failed:', error.message);
        return res.status(502).json({ code: 'FAILED' });
      }
    },
  );

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
