'use strict';

/**
 * Routes: /health + /health/queues*
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 * Mounted at root — paths carry the full prefix.
 */

const express = require('express');
const queueRegistry = require('../queues');
const { isHealthy: isRedisHealthy } = require('../middleware');

/**
 * @param {{getPool: Function, connectedUsers: Map}} deps
 *   getPool is a thunk because pool initializes after routers are wired.
 */
function healthRoutes({ getPool, connectedUsers }) {
  const router = express.Router();

  router.get('/health', async (req, res) => {
    const pool = getPool();
    // ✅ Phase 1: เพิ่ม Redis health status
    const redisOk = await isRedisHealthy().catch(() => false);
    res.json({
      status: 'ok',
      connectedUsers: connectedUsers.size,
      database: pool ? 'connected' : 'not connected',
      redis: redisOk ? 'connected' : 'not connected',
      middleware: {
        rateLimiter: 'active',
        idempotency: 'active',
        cacheAside: 'active',
      },
    });
  });

  // Phase 2: Health Check Endpoint for BullMQ Queues
  router.get('/health/queues', async (req, res) => {
    try {
      const snapshot = await queueRegistry.getHealthSnapshot();
      res.status(snapshot.healthy ? 200 : 503).json(snapshot);
    } catch (err) {
      console.error('[Health] Queue health check failed:', err.message);
      res.status(500).json({ error: 'Health check failed', detail: err.message });
    }
  });

  // Phase 2: DLQ / Failed Job Inspection Endpoint
  router.get('/health/queues/:queueName/failed', async (req, res) => {
    try {
      const { queueName } = req.params;
      const { start = 0, end = 49 } = req.query;
      const jobs = await queueRegistry.getFailedJobs(queueName, parseInt(start, 10), parseInt(end, 10));
      res.json({ queue: queueName, failedJobs: jobs, count: jobs.length });
    } catch (err) {
      console.error(`[Health] Failed to fetch DLQ for ${req.params.queueName}:`, err.message);
      res.status(500).json({ error: 'DLQ inspection failed', detail: err.message });
    }
  });

  // Phase 2: Requeue failed job endpoint
  router.post('/health/queues/:queueName/retry', async (req, res) => {
    try {
      const { queueName } = req.params;
      const { jobId } = req.body || {};
      if (!jobId) {
        return res.status(400).json({ error: 'jobId required' });
      }

      await queueRegistry.retryJob(queueName, jobId);
      res.json({ queue: queueName, jobId, retried: true });
    } catch (err) {
      console.error(`[Health] Failed to retry job ${req.params.queueName}:`, err.message);
      res.status(500).json({ error: 'Requeue failed', detail: err.message });
    }
  });

  return router;
}

module.exports = { healthRoutes };
