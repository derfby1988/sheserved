'use strict';

/**
 * Unified Queue Registry for Sheserved Phase 2
 *
 * Imports every BullMQ queue and worker from services/ so that
 * server.js can mount routes, graceful-shutdown, and health-check
 * them from a single entry point.
 *
 * Design rule: each individual queue file still lives in services/
 * (where it is co-located with its business logic).  This index
 * only re-exports and adds the cross-cutting concerns:
 *   – graceful shutdown of all workers/queues
 *   – health-check aggregation
 *   – DLQ / failed-job inspection
 */

const { redis } = require('../middleware/redis-client');
const { resolveHealthThresholds } = require('../utils/queue-config');
const paymentQueueService = require('../services/payment-queue-service');
const thumbnailQueueService = require('../services/thumbnail-queue');
const videoService = require('../services/video-service');
const consultationQueueService = require('../services/consultation-queue');
const donationQueueService = require('../services/donation-queue');
const syncQueueService = require('../services/sync-queue');
const notificationQueueService = require('../services/notification-queue');

// ── Registry ───────────────────────────────────────────────
const registry = [
  {
    name: 'payment-transfers',
    queue: paymentQueueService.transferQueue,
    worker: paymentQueueService.transferWorker,
    events: paymentQueueService.transferQueueEvents,
    shutdown: paymentQueueService.shutdown,
    hasWorker: true,
    healthThresholds: resolveHealthThresholds('payment-transfers', { maxWaiting: 100, maxFailed: 20 }),
  },
  {
    name: 'thumbnail-generation',
    queue: thumbnailQueueService.thumbnailQueue,
    worker: thumbnailQueueService.worker,
    events: thumbnailQueueService.thumbnailQueueEvents,
    shutdown: thumbnailQueueService.shutdown,
    hasWorker: true,
    healthThresholds: resolveHealthThresholds('thumbnail-generation', { maxWaiting: 500, maxFailed: 50 }),
  },
  {
    name: 'video-processing',
    queue: videoService.videoQueue,
    worker: videoService.worker,
    shutdown: videoService.shutdown,
    hasWorker: true,
    healthThresholds: resolveHealthThresholds('video-processing', { maxWaiting: 200, maxFailed: 40 }),
  },
  {
    name: 'consultation-flow',
    queue: consultationQueueService.consultationQueue,
    worker: consultationQueueService.consultationWorker,
    shutdown: consultationQueueService.shutdown,
    hasWorker: true,
    healthThresholds: resolveHealthThresholds('consultation-flow', { maxWaiting: 200, maxFailed: 40 }),
  },
  {
    name: 'notification-events',
    queue: notificationQueueService.notificationQueue,
    worker: notificationQueueService.notificationWorker,
    shutdown: notificationQueueService.shutdown,
    hasWorker: true,
    healthThresholds: resolveHealthThresholds('notification-events', { maxWaiting: 1000, maxFailed: 100 }),
  },
  {
    name: 'donation-escrow',
    queue: donationQueueService.donationQueue,
    worker: donationQueueService.donationWorker,
    events: donationQueueService.donationQueueEvents,
    shutdown: donationQueueService.shutdown,
    hasWorker: true,
    healthThresholds: resolveHealthThresholds('donation-escrow', { maxWaiting: 200, maxFailed: 40 }),
  },
  {
    name: 'health-sync',
    queue: syncQueueService.syncQueue,
    worker: syncQueueService.syncWorker,
    shutdown: syncQueueService.shutdown,
    hasWorker: true,
    healthThresholds: resolveHealthThresholds('health-sync', { maxWaiting: 10, maxFailed: 10 }),
  },
];

// ── Graceful Shutdown ──────────────────────────────────────
async function shutdownAll() {
  console.log('[QueueRegistry] Graceful shutdown — closing workers & queues...');

  const promises = [];

  for (const entry of registry) {
    if (entry.shutdown) {
      promises.push(
        entry.shutdown().catch((err) => {
          console.error(`[QueueRegistry] ${entry.name} shutdown failed:`, err.message);
        })
      );
    } else if (entry.worker) {
      promises.push(
        entry.worker.close().catch((err) => {
          console.error(`[QueueRegistry] ${entry.name} worker close failed:`, err.message);
        })
      );
    }

    if (entry.queue) {
      promises.push(
        entry.queue.close().catch((err) => {
          console.error(`[QueueRegistry] ${entry.name} queue close failed:`, err.message);
        })
      );
    }
  }

  await Promise.allSettled(promises);

  // Close the shared Redis connection last
  if (redis) {
    await redis.quit().catch(() => {});
  }

  console.log('[QueueRegistry] All queues closed.');
}

// ── Health Check ───────────────────────────────────────────
async function getLagMetrics(entry) {
  if (!entry.events) return { latencyMs: null, lastCompletedAt: null, lastFailedAt: null };
  try {
    const state = await entry.events.getState();
    return {
      latencyMs: typeof state?.latency === 'number' ? state.latency : null,
      lastCompletedAt: state?.lastCompletedOn ? new Date(state.lastCompletedOn).toISOString() : null,
      lastFailedAt: state?.lastFailedOn ? new Date(state.lastFailedOn).toISOString() : null,
    };
  } catch (err) {
    return { latencyMs: null, lastCompletedAt: null, lastFailedAt: null, eventsError: err.message };
  }
}

async function getHealthSnapshot() {
  const snapshot = {
    queues: {},
    healthy: true,
    timestamp: new Date().toISOString(),
  };

  for (const entry of registry) {
    if (!entry.queue) continue;

    try {
      const counts = await entry.queue.getJobCounts(
        'waiting',
        'active',
        'completed',
        'failed',
        'delayed',
        'paused'
      );

      const lagMetrics = await getLagMetrics(entry);

      const thresholds = entry.healthThresholds || resolveHealthThresholds(entry.name, {});
      const healthy = counts.waiting < thresholds.maxWaiting && counts.failed < thresholds.maxFailed;

      snapshot.queues[entry.name] = {
        ...counts,
        ...lagMetrics,
        thresholds,
        healthy,
      };

      if (!healthy) {
        snapshot.healthy = false;
      }
    } catch (err) {
      snapshot.queues[entry.name] = {
        error: err.message,
        healthy: false,
      };
      snapshot.healthy = false;
    }
  }

  return snapshot;
}

// ── DLQ / Failed Job Inspection ───────────────────────────
async function getFailedJobs(queueName, start = 0, end = 49) {
  const entry = registry.find((e) => e.name === queueName);
  if (!entry || !entry.queue) {
    throw new Error(`Queue "${queueName}" not found in registry`);
  }

  const failed = await entry.queue.getFailed(start, end);
  return failed.map((job) => ({
    id: job.id,
    name: job.name,
    data: job.data,
    failedReason: job.failedReason,
    attemptsMade: job.attemptsMade,
    stacktrace: job.stacktrace,
    timestamp: job.timestamp,
  }));
}

// ── Retry Job ─────────────────────────────────────────────
async function retryJob(queueName, jobId) {
  const entry = registry.find((e) => e.name === queueName);
  if (!entry || !entry.queue) {
    throw new Error(`Queue "${queueName}" not found in registry`);
  }

  const job = await entry.queue.getJob(jobId);
  if (!job) {
    throw new Error(`Job ${jobId} not found in queue ${queueName}`);
  }

  await job.retry();
  return { jobId, queueName };
}

// ── Exports ────────────────────────────────────────────────
module.exports = {
  registry,
  shutdownAll,
  getHealthSnapshot,
  getFailedJobs,
  retryJob,

  // Re-export individual queues for direct use in routes
  paymentQueue: paymentQueueService.transferQueue,
  thumbnailQueue: thumbnailQueueService.thumbnailQueue,
  videoQueue: videoService.videoQueue,
  consultationQueue: consultationQueueService.consultationQueue,
  notificationQueue: notificationQueueService.notificationQueue,
  thumbnailQueueEvents: thumbnailQueueService.thumbnailQueueEvents,
  paymentQueueEvents: paymentQueueService.transferQueueEvents,
  donationQueueEvents: donationQueueService.donationQueueEvents,

  // Re-export individual helpers
  enqueueTransfer: paymentQueueService.enqueueTransfer,
  addThumbnailJob: thumbnailQueueService.addJob,
  addVideoJob: videoService.addToQueue,
  submitConsultationRequest: consultationQueueService.submitConsultationRequest,
  enqueueSocketToUser: notificationQueueService.enqueueSocketToUser,
  enqueueSocketToRoom: notificationQueueService.enqueueSocketToRoom,
};
